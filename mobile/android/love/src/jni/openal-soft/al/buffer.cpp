/**
 * OpenAL cross platform audio library
 * Copyright (C) 1999-2007 by authors.
 * This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 *  License along with this library; if not, write to the
 *  Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 * Or go to http://www.gnu.org/copyleft/lgpl.html
 */

#include "config.h"

#include "buffer.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iterator>
#include <limits>
#include <memory>
#include <mutex>
#include <numeric>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/alext.h"

#include "albit.h"
#include "alc/context.h"
#include "alc/device.h"
#include "alc/inprogext.h"
#include "almalloc.h"
#include "alnumeric.h"
#include "alspan.h"
#include "core/device.h"
#include "core/resampler_limits.h"
#include "core/voice.h"
#include "direct_defs.h"
#include "error.h"
#include "intrusive_ptr.h"
#include "opthelpers.h"

#if ALSOFT_EAX
#include <unordered_set>

#include "eax/globals.h"
#include "eax/x_ram.h"
#endif // ALSOFT_EAX


namespace {

using SubListAllocator = al::allocator<std::array<ALbuffer,64>>;

constexpr auto AmbiLayoutFromEnum(ALenum layout) noexcept -> std::optional<AmbiLayout>
{
    switch(layout)
    {
    case AL_FUMA_SOFT: return AmbiLayout::FuMa;
    case AL_ACN_SOFT: return AmbiLayout::ACN;
    }
    return std::nullopt;
}
constexpr auto EnumFromAmbiLayout(AmbiLayout layout) -> ALenum
{
    switch(layout)
    {
    case AmbiLayout::FuMa: return AL_FUMA_SOFT;
    case AmbiLayout::ACN: return AL_ACN_SOFT;
    }
    throw std::runtime_error{"Invalid AmbiLayout: "+std::to_string(int(layout))};
}

constexpr auto AmbiScalingFromEnum(ALenum scale) noexcept -> std::optional<AmbiScaling>
{
    switch(scale)
    {
    case AL_FUMA_SOFT: return AmbiScaling::FuMa;
    case AL_SN3D_SOFT: return AmbiScaling::SN3D;
    case AL_N3D_SOFT: return AmbiScaling::N3D;
    }
    return std::nullopt;
}
constexpr auto EnumFromAmbiScaling(AmbiScaling scale) -> ALenum
{
    switch(scale)
    {
    case AmbiScaling::FuMa: return AL_FUMA_SOFT;
    case AmbiScaling::SN3D: return AL_SN3D_SOFT;
    case AmbiScaling::N3D: return AL_N3D_SOFT;
    case AmbiScaling::UHJ: break;
    }
    throw std::runtime_error{"Invalid AmbiScaling: "+std::to_string(int(scale))};
}

#if ALSOFT_EAX
constexpr auto EaxStorageFromEnum(ALenum scale) noexcept -> std::optional<EaxStorage>
{
    switch(scale)
    {
    case AL_STORAGE_AUTOMATIC: return EaxStorage::Automatic;
    case AL_STORAGE_ACCESSIBLE: return EaxStorage::Accessible;
    case AL_STORAGE_HARDWARE: return EaxStorage::Hardware;
    }
    return std::nullopt;
}
constexpr auto EnumFromEaxStorage(EaxStorage storage) -> ALenum
{
    switch(storage)
    {
    case EaxStorage::Automatic: return AL_STORAGE_AUTOMATIC;
    case EaxStorage::Accessible: return AL_STORAGE_ACCESSIBLE;
    case EaxStorage::Hardware: return AL_STORAGE_HARDWARE;
    }
    throw std::runtime_error{"Invalid EaxStorage: "+std::to_string(int(storage))};
}


bool eax_x_ram_check_availability(const ALCdevice &device, const ALbuffer &buffer,
    const ALuint newsize) noexcept
{
    ALuint freemem{device.eax_x_ram_free_size};
    /* If the buffer is currently in "hardware", add its memory to the free
     * pool since it'll be "replaced".
     */
    if(buffer.eax_x_ram_is_hardware)
        freemem += buffer.OriginalSize;
    return freemem >= newsize;
}

void eax_x_ram_apply(ALCdevice &device, ALbuffer &buffer) noexcept
{
    if(buffer.eax_x_ram_is_hardware)
        return;

    if(device.eax_x_ram_free_size >= buffer.OriginalSize)
    {
        device.eax_x_ram_free_size -= buffer.OriginalSize;
        buffer.eax_x_ram_is_hardware = true;
    }
}

void eax_x_ram_clear(ALCdevice& al_device, ALbuffer& al_buffer) noexcept
{
    if(al_buffer.eax_x_ram_is_hardware)
        al_device.eax_x_ram_free_size += al_buffer.OriginalSize;
    al_buffer.eax_x_ram_is_hardware = false;
}
#endif // ALSOFT_EAX


constexpr ALbitfieldSOFT INVALID_STORAGE_MASK{~unsigned(AL_MAP_READ_BIT_SOFT |
    AL_MAP_WRITE_BIT_SOFT | AL_MAP_PERSISTENT_BIT_SOFT | AL_PRESERVE_DATA_BIT_SOFT)};
constexpr ALbitfieldSOFT MAP_READ_WRITE_FLAGS{AL_MAP_READ_BIT_SOFT | AL_MAP_WRITE_BIT_SOFT};
constexpr ALbitfieldSOFT INVALID_MAP_FLAGS{~unsigned(AL_MAP_READ_BIT_SOFT | AL_MAP_WRITE_BIT_SOFT |
    AL_MAP_PERSISTENT_BIT_SOFT)};


auto EnsureBuffers(ALCdevice *device, size_t needed) noexcept -> bool
try {
    size_t count{std::accumulate(device->BufferList.cbegin(), device->BufferList.cend(), 0_uz,
        [](size_t cur, const BufferSubList &sublist) noexcept -> size_t
        { return cur + static_cast<ALuint>(al::popcount(sublist.FreeMask)); })};

    while(needed > count)
    {
        if(device->BufferList.size() >= 1<<25) UNLIKELY
            return false;

        BufferSubList sublist{};
        sublist.FreeMask = ~0_u64;
        sublist.Buffers = SubListAllocator{}.allocate(1);
        device->BufferList.emplace_back(std::move(sublist));
        count += std::tuple_size_v<SubListAllocator::value_type>;
    }
    return true;
}
catch(...) {
    return false;
}

ALbuffer *AllocBuffer(ALCdevice *device) noexcept
{
    auto sublist = std::find_if(device->BufferList.begin(), device->BufferList.end(),
        [](const BufferSubList &entry) noexcept -> bool
        { return entry.FreeMask != 0; });
    auto lidx = static_cast<ALuint>(std::distance(device->BufferList.begin(), sublist));
    auto slidx = static_cast<ALuint>(al::countr_zero(sublist->FreeMask));
    ASSUME(slidx < 64);

    ALbuffer *buffer{al::construct_at(al::to_address(sublist->Buffers->begin() + slidx))};

    /* Add 1 to avoid buffer ID 0. */
    buffer->id = ((lidx<<6) | slidx) + 1;

    sublist->FreeMask &= ~(1_u64 << slidx);

    return buffer;
}

void FreeBuffer(ALCdevice *device, ALbuffer *buffer)
{
#if ALSOFT_EAX
    eax_x_ram_clear(*device, *buffer);
#endif // ALSOFT_EAX

    device->mBufferNames.erase(buffer->id);

    const ALuint id{buffer->id - 1};
    const size_t lidx{id >> 6};
    const ALuint slidx{id & 0x3f};

    std::destroy_at(buffer);

    device->BufferList[lidx].FreeMask |= 1_u64 << slidx;
}

auto LookupBuffer(ALCdevice *device, ALuint id) noexcept -> ALbuffer*
{
    const size_t lidx{(id-1) >> 6};
    const ALuint slidx{(id-1) & 0x3f};

    if(lidx >= device->BufferList.size()) UNLIKELY
        return nullptr;
    BufferSubList &sublist = device->BufferList[lidx];
    if(sublist.FreeMask & (1_u64 << slidx)) UNLIKELY
        return nullptr;
    return al::to_address(sublist.Buffers->begin() + slidx);
}


constexpr auto SanitizeAlignment(FmtType type, ALuint align) noexcept -> ALuint
{
    if(align == 0)
    {
        if(type == FmtIMA4)
        {
            /* Here is where things vary:
             * nVidia and Apple use 64+1 sample frames per block -> block_size=36 bytes per channel
             * Most PC sound software uses 2040+1 sample frames per block -> block_size=1024 bytes per channel
             */
            return 65;
        }
        if(type == FmtMSADPCM)
            return 64;
        return 1;
    }

    if(type == FmtIMA4)
    {
        /* IMA4 block alignment must be a multiple of 8, plus 1. */
        if((align&7) == 1) return align;
        return 0;
    }
    if(type == FmtMSADPCM)
    {
        /* MSADPCM block alignment must be a multiple of 2. */
        if((align&1) == 0) return align;
        return 0;
    }

    return align;
}


/** Loads the specified data into the buffer, using the specified format. */
void LoadData(ALCcontext *context [[maybe_unused]], ALbuffer *ALBuf, ALsizei freq, ALuint size,
    const FmtChannels DstChannels, const FmtType DstType, const al::span<const std::byte> SrcData,
    ALbitfieldSOFT access)
{
    if(ALBuf->ref.load(std::memory_order_relaxed) != 0 || ALBuf->MappedAccess != 0)
        throw al::context_error{AL_INVALID_OPERATION, "Modifying storage for in-use buffer %u",
            ALBuf->id};

    const ALuint unpackalign{ALBuf->UnpackAlign};
    const ALuint align{SanitizeAlignment(DstType, unpackalign)};
    if(align < 1)
        throw al::context_error{AL_INVALID_VALUE, "Invalid unpack alignment %u for %s samples",
            unpackalign, NameFromFormat(DstType)};

    const ALuint ambiorder{IsBFormat(DstChannels) ? ALBuf->UnpackAmbiOrder :
        (IsUHJ(DstChannels) ? 1 : 0)};

    if((access&AL_PRESERVE_DATA_BIT_SOFT))
    {
        /* Can only preserve data with the same format and alignment. */
        if(ALBuf->mChannels != DstChannels || ALBuf->mType != DstType)
            throw al::context_error{AL_INVALID_VALUE, "Preserving data of mismatched format"};
        if(ALBuf->mBlockAlign != align)
            throw al::context_error{AL_INVALID_VALUE, "Preserving data of mismatched alignment"};
        if(ALBuf->mAmbiOrder != ambiorder)
            throw al::context_error{AL_INVALID_VALUE, "Preserving data of mismatched order"};
    }

    /* Convert the size in bytes to blocks using the unpack block alignment. */
    const ALuint NumChannels{ChannelsFromFmt(DstChannels, ambiorder)};
    const ALuint BlockSize{NumChannels *
        ((DstType == FmtIMA4) ? (align-1)/2 + 4 :
        (DstType == FmtMSADPCM) ? (align-2)/2 + 7 :
        (align * BytesFromFmt(DstType)))};
    if((size%BlockSize) != 0)
        throw al::context_error{AL_INVALID_VALUE,
            "Data size %d is not a multiple of frame size %d (%d unpack alignment)",
            size, BlockSize, align};
    const ALuint blocks{size / BlockSize};

    if(blocks > std::numeric_limits<ALsizei>::max()/align)
        throw al::context_error{AL_OUT_OF_MEMORY,
            "Buffer size overflow, %d blocks x %d samples per block", blocks, align};
    if(blocks > std::numeric_limits<size_t>::max()/BlockSize)
        throw al::context_error{AL_OUT_OF_MEMORY,
            "Buffer size overflow, %d frames x %d bytes per frame", blocks, BlockSize};

    const size_t newsize{static_cast<size_t>(blocks) * BlockSize};

#if ALSOFT_EAX
    if(ALBuf->eax_x_ram_mode == EaxStorage::Hardware)
    {
        ALCdevice &device = *context->mALDevice;
        if(!eax_x_ram_check_availability(device, *ALBuf, size))
            throw al::context_error{AL_OUT_OF_MEMORY,
                "Out of X-RAM memory (avail: %u, needed: %u)", device.eax_x_ram_free_size, size};
    }
#endif

    /* This could reallocate only when increasing the size or the new size is
     * less than half the current, but then the buffer's AL_SIZE would not be
     * very reliable for accounting buffer memory usage, and reporting the real
     * size could cause problems for apps that use AL_SIZE to try to get the
     * buffer's play length.
     */
    if(newsize != ALBuf->mDataStorage.size())
    {
        auto newdata = decltype(ALBuf->mDataStorage)(newsize, std::byte{});
        if((access&AL_PRESERVE_DATA_BIT_SOFT))
        {
            const size_t tocopy{std::min(newdata.size(), ALBuf->mDataStorage.size())};
            std::copy_n(ALBuf->mDataStorage.begin(), tocopy, newdata.begin());
        }
        newdata.swap(ALBuf->mDataStorage);
    }
    ALBuf->mData = ALBuf->mDataStorage;
#if ALSOFT_EAX
    eax_x_ram_clear(*context->mALDevice, *ALBuf);
#endif

    if(!SrcData.empty() && !ALBuf->mData.empty())
        std::copy_n(SrcData.begin(), blocks*BlockSize, ALBuf->mData.begin());
    ALBuf->mBlockAlign = (DstType == FmtIMA4 || DstType == FmtMSADPCM) ? align : 1;

    ALBuf->OriginalSize = size;

    ALBuf->Access = access;

    ALBuf->mSampleRate = static_cast<ALuint>(freq);
    ALBuf->mChannels = DstChannels;
    ALBuf->mType = DstType;
    ALBuf->mAmbiOrder = ambiorder;

    ALBuf->mCallback = nullptr;
    ALBuf->mUserData = nullptr;

    ALBuf->mSampleLen = blocks * align;
    ALBuf->mLoopStart = 0;
    ALBuf->mLoopEnd = ALBuf->mSampleLen;

#if ALSOFT_EAX
    if(eax_g_is_enabled && ALBuf->eax_x_ram_mode == EaxStorage::Hardware)
        eax_x_ram_apply(*context->mALDevice, *ALBuf);
#endif
}

/** Prepares the buffer to use the specified callback, using the specified format. */
void PrepareCallback(ALCcontext *context [[maybe_unused]], ALbuffer *ALBuf, ALsizei freq,
    const FmtChannels DstChannels, const FmtType DstType, ALBUFFERCALLBACKTYPESOFT callback,
    void *userptr)
{
    if(ALBuf->ref.load(std::memory_order_relaxed) != 0 || ALBuf->MappedAccess != 0)
        throw al::context_error{AL_INVALID_OPERATION, "Modifying callback for in-use buffer %u",
            ALBuf->id};

    const ALuint ambiorder{IsBFormat(DstChannels) ? ALBuf->UnpackAmbiOrder :
        (IsUHJ(DstChannels) ? 1 : 0)};

    const ALuint unpackalign{ALBuf->UnpackAlign};
    const ALuint align{SanitizeAlignment(DstType, unpackalign)};
    if(align < 1)
        throw al::context_error{AL_INVALID_VALUE, "Invalid unpack alignment %u for %s samples",
            unpackalign, NameFromFormat(DstType)};

    const ALuint BlockSize{ChannelsFromFmt(DstChannels, ambiorder) *
        ((DstType == FmtIMA4) ? (align-1)/2 + 4 :
        (DstType == FmtMSADPCM) ? (align-2)/2 + 7 :
        (align * BytesFromFmt(DstType)))};

    /* The maximum number of samples a callback buffer may need to store is a
     * full mixing line * max pitch * channel count, since it may need to hold
     * a full line's worth of sample frames before downsampling. An additional
     * MaxResamplerEdge is needed for "future" samples during resampling (the
     * voice will hold a history for the past samples).
     */
    static constexpr size_t line_size{DeviceBase::MixerLineSize*MaxPitch + MaxResamplerEdge};
    const size_t line_blocks{(line_size + align-1) / align};

    using BufferVectorType = decltype(ALBuf->mDataStorage);
    BufferVectorType(line_blocks*BlockSize).swap(ALBuf->mDataStorage);
    ALBuf->mData = ALBuf->mDataStorage;

#if ALSOFT_EAX
    eax_x_ram_clear(*context->mALDevice, *ALBuf);
#endif

    ALBuf->mCallback = callback;
    ALBuf->mUserData = userptr;

    ALBuf->OriginalSize = 0;
    ALBuf->Access = 0;

    ALBuf->mBlockAlign = (DstType == FmtIMA4 || DstType == FmtMSADPCM) ? align : 1;
    ALBuf->mSampleRate = static_cast<ALuint>(freq);
    ALBuf->mChannels = DstChannels;
    ALBuf->mType = DstType;
    ALBuf->mAmbiOrder = ambiorder;

    ALBuf->mSampleLen = 0;
    ALBuf->mLoopStart = 0;
    ALBuf->mLoopEnd = ALBuf->mSampleLen;
}

/** Prepares the buffer to use caller-specified storage. */
void PrepareUserPtr(ALCcontext *context [[maybe_unused]], ALbuffer *ALBuf, ALsizei freq,
    const FmtChannels DstChannels, const FmtType DstType, std::byte *sdata, const ALuint sdatalen)
{
    if(ALBuf->ref.load(std::memory_order_relaxed) != 0 || ALBuf->MappedAccess != 0)
        throw al::context_error{AL_INVALID_OPERATION, "Modifying storage for in-use buffer %u",
            ALBuf->id};

    const ALuint unpackalign{ALBuf->UnpackAlign};
    const ALuint align{SanitizeAlignment(DstType, unpackalign)};
    if(align < 1)
        throw al::context_error{AL_INVALID_VALUE, "Invalid unpack alignment %u for %s samples",
            unpackalign, NameFromFormat(DstType)};

    auto get_type_alignment = [](const FmtType type) noexcept -> ALuint
    {
        /* NOTE: This only needs to be the required alignment for the CPU to
         * read/write the given sample type in the mixer.
         */
        switch(type)
        {
        case FmtUByte: return alignof(ALubyte);
        case FmtShort: return alignof(ALshort);
        case FmtInt: return alignof(ALint);
        case FmtFloat: return alignof(ALfloat);
        case FmtDouble: return alignof(ALdouble);
        case FmtMulaw: return alignof(ALubyte);
        case FmtAlaw: return alignof(ALubyte);
        case FmtIMA4: break;
        case FmtMSADPCM: break;
        }
        return 1;
    };
    const auto typealign = get_type_alignment(DstType);
    if((reinterpret_cast<uintptr_t>(sdata) & (typealign-1)) != 0)
        throw al::context_error{AL_INVALID_VALUE, "Pointer %p is misaligned for %s samples (%u)",
            static_cast<void*>(sdata), NameFromFormat(DstType), typealign};

    const ALuint ambiorder{IsBFormat(DstChannels) ? ALBuf->UnpackAmbiOrder :
        (IsUHJ(DstChannels) ? 1 : 0)};

    /* Convert the size in bytes to blocks using the unpack block alignment. */
    const ALuint NumChannels{ChannelsFromFmt(DstChannels, ambiorder)};
    const ALuint BlockSize{NumChannels *
        ((DstType == FmtIMA4) ? (align-1)/2 + 4 :
        (DstType == FmtMSADPCM) ? (align-2)/2 + 7 :
        (align * BytesFromFmt(DstType)))};
    if((sdatalen%BlockSize) != 0)
        throw al::context_error{AL_INVALID_VALUE,
            "Data size %u is not a multiple of frame size %u (%u unpack alignment)",
            sdatalen, BlockSize, align};
    const ALuint blocks{sdatalen / BlockSize};

    if(blocks > std::numeric_limits<ALsizei>::max()/align)
        throw al::context_error{AL_OUT_OF_MEMORY,
            "Buffer size overflow, %d blocks x %d samples per block", blocks, align};
    if(blocks > std::numeric_limits<size_t>::max()/BlockSize)
        throw al::context_error{AL_OUT_OF_MEMORY,
            "Buffer size overflow, %d frames x %d bytes per frame", blocks, BlockSize};

#if ALSOFT_EAX
    if(ALBuf->eax_x_ram_mode == EaxStorage::Hardware)
    {
        ALCdevice &device = *context->mALDevice;
        if(!eax_x_ram_check_availability(device, *ALBuf, sdatalen))
            throw al::context_error{AL_OUT_OF_MEMORY,
                "Out of X-RAM memory (avail: %u, needed: %u)", device.eax_x_ram_free_size,
                sdatalen};
    }
#endif

    decltype(ALBuf->mDataStorage){}.swap(ALBuf->mDataStorage);
    ALBuf->mData = al::span{sdata, sdatalen};

#if ALSOFT_EAX
    eax_x_ram_clear(*context->mALDevice, *ALBuf);
#endif

    ALBuf->mCallback = nullptr;
    ALBuf->mUserData = nullptr;

    ALBuf->OriginalSize = sdatalen;
    ALBuf->Access = 0;

    ALBuf->mBlockAlign = (DstType == FmtIMA4 || DstType == FmtMSADPCM) ? align : 1;
    ALBuf->mSampleRate = static_cast<ALuint>(freq);
    ALBuf->mChannels = DstChannels;
    ALBuf->mType = DstType;
    ALBuf->mAmbiOrder = ambiorder;

    ALBuf->mSampleLen = blocks * align;
    ALBuf->mLoopStart = 0;
    ALBuf->mLoopEnd = ALBuf->mSampleLen;

#if ALSOFT_EAX
    if(ALBuf->eax_x_ram_mode == EaxStorage::Hardware)
        eax_x_ram_apply(*context->mALDevice, *ALBuf);
#endif
}


struct DecompResult { FmtChannels channels; FmtType type; };
auto DecomposeUserFormat(ALenum format) noexcept -> std::optional<DecompResult>
{
    struct FormatMap {
        ALenum format;
        DecompResult result;
    };
    static constexpr std::array UserFmtList{
        FormatMap{AL_FORMAT_MONO8,             {FmtMono, FmtUByte}  },
        FormatMap{AL_FORMAT_MONO16,            {FmtMono, FmtShort}  },
        FormatMap{AL_FORMAT_MONO_I32,          {FmtMono, FmtInt}    },
        FormatMap{AL_FORMAT_MONO_FLOAT32,      {FmtMono, FmtFloat}  },
        FormatMap{AL_FORMAT_MONO_DOUBLE_EXT,   {FmtMono, FmtDouble} },
        FormatMap{AL_FORMAT_MONO_IMA4,         {FmtMono, FmtIMA4}   },
        FormatMap{AL_FORMAT_MONO_MSADPCM_SOFT, {FmtMono, FmtMSADPCM}},
        FormatMap{AL_FORMAT_MONO_MULAW,        {FmtMono, FmtMulaw}  },
        FormatMap{AL_FORMAT_MONO_ALAW_EXT,     {FmtMono, FmtAlaw}   },

        FormatMap{AL_FORMAT_STEREO8,             {FmtStereo, FmtUByte}  },
        FormatMap{AL_FORMAT_STEREO16,            {FmtStereo, FmtShort}  },
        FormatMap{AL_FORMAT_STEREO_I32,          {FmtStereo, FmtInt}    },
        FormatMap{AL_FORMAT_STEREO_FLOAT32,      {FmtStereo, FmtFloat}  },
        FormatMap{AL_FORMAT_STEREO_DOUBLE_EXT,   {FmtStereo, FmtDouble} },
        FormatMap{AL_FORMAT_STEREO_IMA4,         {FmtStereo, FmtIMA4}   },
        FormatMap{AL_FORMAT_STEREO_MSADPCM_SOFT, {FmtStereo, FmtMSADPCM}},
        FormatMap{AL_FORMAT_STEREO_MULAW,        {FmtStereo, FmtMulaw}  },
        FormatMap{AL_FORMAT_STEREO_ALAW_EXT,     {FmtStereo, FmtAlaw}   },

        FormatMap{AL_FORMAT_REAR8,        {FmtRear, FmtUByte}},
        FormatMap{AL_FORMAT_REAR16,       {FmtRear, FmtShort}},
        FormatMap{AL_FORMAT_REAR32,       {FmtRear, FmtFloat}},
        FormatMap{AL_FORMAT_REAR_I32,     {FmtRear, FmtInt}  },
        FormatMap{AL_FORMAT_REAR_FLOAT32, {FmtRear, FmtFloat}},
        FormatMap{AL_FORMAT_REAR_MULAW,   {FmtRear, FmtMulaw}},

        FormatMap{AL_FORMAT_QUAD8_LOKI,  {FmtQuad, FmtUByte}},
        FormatMap{AL_FORMAT_QUAD16_LOKI, {FmtQuad, FmtShort}},

        FormatMap{AL_FORMAT_QUAD8,        {FmtQuad, FmtUByte}},
        FormatMap{AL_FORMAT_QUAD16,       {FmtQuad, FmtShort}},
        FormatMap{AL_FORMAT_QUAD32,       {FmtQuad, FmtFloat}},
        FormatMap{AL_FORMAT_QUAD_I32,     {FmtQuad, FmtInt}  },
        FormatMap{AL_FORMAT_QUAD_FLOAT32, {FmtQuad, FmtFloat}},
        FormatMap{AL_FORMAT_QUAD_MULAW,   {FmtQuad, FmtMulaw}},

        FormatMap{AL_FORMAT_51CHN8,        {FmtX51, FmtUByte}},
        FormatMap{AL_FORMAT_51CHN16,       {FmtX51, FmtShort}},
        FormatMap{AL_FORMAT_51CHN32,       {FmtX51, FmtFloat}},
        FormatMap{AL_FORMAT_51CHN_I32,     {FmtX51, FmtInt}  },
        FormatMap{AL_FORMAT_51CHN_FLOAT32, {FmtX51, FmtFloat}},
        FormatMap{AL_FORMAT_51CHN_MULAW,   {FmtX51, FmtMulaw}},

        FormatMap{AL_FORMAT_61CHN8,        {FmtX61, FmtUByte}},
        FormatMap{AL_FORMAT_61CHN16,       {FmtX61, FmtShort}},
        FormatMap{AL_FORMAT_61CHN32,       {FmtX61, FmtFloat}},
        FormatMap{AL_FORMAT_61CHN_I32,     {FmtX61, FmtInt}  },
        FormatMap{AL_FORMAT_61CHN_FLOAT32, {FmtX61, FmtFloat}},
        FormatMap{AL_FORMAT_61CHN_MULAW,   {FmtX61, FmtMulaw}},

        FormatMap{AL_FORMAT_71CHN8,        {FmtX71, FmtUByte}},
        FormatMap{AL_FORMAT_71CHN16,       {FmtX71, FmtShort}},
        FormatMap{AL_FORMAT_71CHN32,       {FmtX71, FmtFloat}},
        FormatMap{AL_FORMAT_71CHN_I32,     {FmtX71, FmtInt}  },
        FormatMap{AL_FORMAT_71CHN_FLOAT32, {FmtX71, FmtFloat}},
        FormatMap{AL_FORMAT_71CHN_MULAW,   {FmtX71, FmtMulaw}},

        FormatMap{AL_FORMAT_BFORMAT2D_8,       {FmtBFormat2D, FmtUByte}},
        FormatMap{AL_FORMAT_BFORMAT2D_16,      {FmtBFormat2D, FmtShort}},
        FormatMap{AL_FORMAT_BFORMAT2D_I32,     {FmtBFormat2D, FmtInt}  },
        FormatMap{AL_FORMAT_BFORMAT2D_FLOAT32, {FmtBFormat2D, FmtFloat}},
        FormatMap{AL_FORMAT_BFORMAT2D_MULAW,   {FmtBFormat2D, FmtMulaw}},

        FormatMap{AL_FORMAT_BFORMAT3D_8,       {FmtBFormat3D, FmtUByte}},
        FormatMap{AL_FORMAT_BFORMAT3D_16,      {FmtBFormat3D, FmtShort}},
        FormatMap{AL_FORMAT_BFORMAT2D_I32,     {FmtBFormat3D, FmtInt}  },
        FormatMap{AL_FORMAT_BFORMAT3D_FLOAT32, {FmtBFormat3D, FmtFloat}},
        FormatMap{AL_FORMAT_BFORMAT3D_MULAW,   {FmtBFormat3D, FmtMulaw}},

        FormatMap{AL_FORMAT_UHJ2CHN8_SOFT,        {FmtUHJ2, FmtUByte}  },
        FormatMap{AL_FORMAT_UHJ2CHN16_SOFT,       {FmtUHJ2, FmtShort}  },
        FormatMap{AL_FORMAT_UHJ2CHN_I32_SOFT,     {FmtUHJ2, FmtInt}    },
        FormatMap{AL_FORMAT_UHJ2CHN_FLOAT32_SOFT, {FmtUHJ2, FmtFloat}  },
        FormatMap{AL_FORMAT_UHJ2CHN_MULAW_SOFT,   {FmtUHJ2, FmtMulaw}  },
        FormatMap{AL_FORMAT_UHJ2CHN_ALAW_SOFT,    {FmtUHJ2, FmtAlaw}   },
        FormatMap{AL_FORMAT_UHJ2CHN_IMA4_SOFT,    {FmtUHJ2, FmtIMA4}   },
        FormatMap{AL_FORMAT_UHJ2CHN_MSADPCM_SOFT, {FmtUHJ2, FmtMSADPCM}},

        FormatMap{AL_FORMAT_UHJ3CHN8_SOFT,        {FmtUHJ3, FmtUByte}},
        FormatMap{AL_FORMAT_UHJ3CHN16_SOFT,       {FmtUHJ3, FmtShort}},
        FormatMap{AL_FORMAT_UHJ3CHN_I32_SOFT,     {FmtUHJ3, FmtInt}  },
        FormatMap{AL_FORMAT_UHJ3CHN_FLOAT32_SOFT, {FmtUHJ3, FmtFloat}},
        FormatMap{AL_FORMAT_UHJ3CHN_MULAW_SOFT,   {FmtUHJ3, FmtMulaw}},
        FormatMap{AL_FORMAT_UHJ3CHN_ALAW_SOFT,    {FmtUHJ3, FmtAlaw} },

        FormatMap{AL_FORMAT_UHJ4CHN8_SOFT,        {FmtUHJ4, FmtUByte}},
        FormatMap{AL_FORMAT_UHJ4CHN16_SOFT,       {FmtUHJ4, FmtShort}},
        FormatMap{AL_FORMAT_UHJ4CHN_I32_SOFT,     {FmtUHJ4, FmtInt}  },
        FormatMap{AL_FORMAT_UHJ4CHN_FLOAT32_SOFT, {FmtUHJ4, FmtFloat}},
        FormatMap{AL_FORMAT_UHJ4CHN_MULAW_SOFT,   {FmtUHJ4, FmtMulaw}},
        FormatMap{AL_FORMAT_UHJ4CHN_ALAW_SOFT,    {FmtUHJ4, FmtAlaw} },
    };

    auto iter = std::find_if(UserFmtList.cbegin(), UserFmtList.cend(),
        [format](const FormatMap &fmt) noexcept { return fmt.format == format; });
    if(iter != UserFmtList.cend())
        return iter->result;
    return std::nullopt;
}

} // namespace


AL_API DECL_FUNC2(void, alGenBuffers, ALsizei,n, ALuint*,buffers)
FORCE_ALIGN void AL_APIENTRY alGenBuffersDirect(ALCcontext *context, ALsizei n, ALuint *buffers) noexcept
try {
    if(n < 0)
        throw al::context_error{AL_INVALID_VALUE, "Generating %d buffers", n};
    if(n <= 0) UNLIKELY return;

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    const al::span bids{buffers, static_cast<ALuint>(n)};
    if(!EnsureBuffers(device, bids.size()))
        throw al::context_error{AL_OUT_OF_MEMORY, "Failed to allocate %d buffer%s", n,
            (n == 1) ? "" : "s"};

    std::generate(bids.begin(), bids.end(), [device]{ return AllocBuffer(device)->id; });
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC2(void, alDeleteBuffers, ALsizei,n, const ALuint*,buffers)
FORCE_ALIGN void AL_APIENTRY alDeleteBuffersDirect(ALCcontext *context, ALsizei n,
    const ALuint *buffers) noexcept
try {
    if(n < 0)
        throw al::context_error{AL_INVALID_VALUE, "Deleting %d buffers", n};
    if(n <= 0) UNLIKELY return;

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    /* First try to find any buffers that are invalid or in-use. */
    auto validate_buffer = [device](const ALuint bid)
    {
        if(!bid) return;
        ALbuffer *ALBuf{LookupBuffer(device, bid)};
        if(!ALBuf)
            throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", bid};
        if(ALBuf->ref.load(std::memory_order_relaxed) != 0)
            throw al::context_error{AL_INVALID_OPERATION, "Deleting in-use buffer %u", bid};
    };

    const al::span bids{buffers, static_cast<ALuint>(n)};
    std::for_each(bids.begin(), bids.end(), validate_buffer);

    /* All good. Delete non-0 buffer IDs. */
    auto delete_buffer = [device](const ALuint bid) -> void
    {
        if(ALbuffer *buffer{bid ? LookupBuffer(device, bid) : nullptr})
            FreeBuffer(device, buffer);
    };
    std::for_each(bids.begin(), bids.end(), delete_buffer);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC1(ALboolean, alIsBuffer, ALuint,buffer)
FORCE_ALIGN ALboolean AL_APIENTRY alIsBufferDirect(ALCcontext *context, ALuint buffer) noexcept
{
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};
    if(!buffer || LookupBuffer(device, buffer))
        return AL_TRUE;
    return AL_FALSE;
}


AL_API void AL_APIENTRY alBufferData(ALuint buffer, ALenum format, const ALvoid *data, ALsizei size, ALsizei freq) noexcept
{
    auto context = GetContextRef();
    if(!context) UNLIKELY return;
    alBufferStorageDirectSOFT(context.get(), buffer, format, data, size, freq, 0);
}

FORCE_ALIGN void AL_APIENTRY alBufferDataDirect(ALCcontext *context, ALuint buffer, ALenum format, const ALvoid *data, ALsizei size, ALsizei freq) noexcept
{ alBufferStorageDirectSOFT(context, buffer, format, data, size, freq, 0); }

AL_API DECL_FUNCEXT6(void, alBufferStorage,SOFT, ALuint,buffer, ALenum,format, const ALvoid*,data, ALsizei,size, ALsizei,freq, ALbitfieldSOFT,flags)
FORCE_ALIGN void AL_APIENTRY alBufferStorageDirectSOFT(ALCcontext *context, ALuint buffer,
    ALenum format, const ALvoid *data, ALsizei size, ALsizei freq, ALbitfieldSOFT flags) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(size < 0)
        throw al::context_error{AL_INVALID_VALUE, "Negative storage size %d", size};
    if(freq < 1)
        throw al::context_error{AL_INVALID_VALUE, "Invalid sample rate %d", freq};
    if((flags&INVALID_STORAGE_MASK) != 0)
        throw al::context_error{AL_INVALID_VALUE, "Invalid storage flags 0x%x",
            flags&INVALID_STORAGE_MASK};
    if((flags&AL_MAP_PERSISTENT_BIT_SOFT) && !(flags&MAP_READ_WRITE_FLAGS))
        throw al::context_error{AL_INVALID_VALUE,
            "Declaring persistently mapped storage without read or write access"};

    auto usrfmt = DecomposeUserFormat(format);
    if(!usrfmt)
        throw al::context_error{AL_INVALID_ENUM, "Invalid format 0x%04x", format};

    auto bdata = static_cast<const std::byte*>(data);
    LoadData(context, albuf, freq, static_cast<ALuint>(size), usrfmt->channels, usrfmt->type,
        al::span{bdata, bdata ? static_cast<ALuint>(size) : 0u}, flags);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

FORCE_ALIGN DECL_FUNC5(void, alBufferDataStatic, ALuint,buffer, ALenum,format, ALvoid*,data, ALsizei,size, ALsizei,freq)
FORCE_ALIGN void AL_APIENTRY alBufferDataStaticDirect(ALCcontext *context, const ALuint buffer,
    ALenum format, ALvoid *data, ALsizei size, ALsizei freq) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(size < 0)
        throw al::context_error{AL_INVALID_VALUE, "Negative storage size %d", size};
    if(freq < 1)
        throw al::context_error{AL_INVALID_VALUE, "Invalid sample rate %d", freq};

    auto usrfmt = DecomposeUserFormat(format);
    if(!usrfmt)
        throw al::context_error{AL_INVALID_ENUM, "Invalid format 0x%04x", format};

    PrepareUserPtr(context, albuf, freq, usrfmt->channels, usrfmt->type,
        static_cast<std::byte*>(data), static_cast<ALuint>(size));
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNCEXT4(void*, alMapBuffer,SOFT, ALuint,buffer, ALsizei,offset, ALsizei,length, ALbitfieldSOFT,access)
FORCE_ALIGN void* AL_APIENTRY alMapBufferDirectSOFT(ALCcontext *context, ALuint buffer,
    ALsizei offset, ALsizei length, ALbitfieldSOFT access) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if((access&INVALID_MAP_FLAGS) != 0)
        throw al::context_error{AL_INVALID_VALUE, "Invalid map flags 0x%x",
            access&INVALID_MAP_FLAGS};
    if(!(access&MAP_READ_WRITE_FLAGS))
        throw al::context_error{AL_INVALID_VALUE, "Mapping buffer %u without read or write access",
            buffer};

    const ALbitfieldSOFT unavailable{(albuf->Access^access) & access};
    if(albuf->ref.load(std::memory_order_relaxed) != 0 && !(access&AL_MAP_PERSISTENT_BIT_SOFT))
        throw al::context_error{AL_INVALID_OPERATION,
            "Mapping in-use buffer %u without persistent mapping", buffer};
    if(albuf->MappedAccess != 0)
        throw al::context_error{AL_INVALID_OPERATION, "Mapping already-mapped buffer %u", buffer};
    if((unavailable&AL_MAP_READ_BIT_SOFT))
        throw al::context_error{AL_INVALID_VALUE,
            "Mapping buffer %u for reading without read access", buffer};
    if((unavailable&AL_MAP_WRITE_BIT_SOFT))
        throw al::context_error{AL_INVALID_VALUE,
            "Mapping buffer %u for writing without write access", buffer};
    if((unavailable&AL_MAP_PERSISTENT_BIT_SOFT))
        throw al::context_error{AL_INVALID_VALUE,
            "Mapping buffer %u persistently without persistent access", buffer};
    if(offset < 0 || length <= 0 || static_cast<ALuint>(offset) >= albuf->OriginalSize
        || static_cast<ALuint>(length) > albuf->OriginalSize - static_cast<ALuint>(offset))
        throw al::context_error{AL_INVALID_VALUE, "Mapping invalid range %d+%d for buffer %u",
            offset, length, buffer};

    void *retval{albuf->mData.data() + offset};
    albuf->MappedAccess = access;
    albuf->MappedOffset = offset;
    albuf->MappedSize = length;
    return retval;
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
    return nullptr;
}

AL_API DECL_FUNCEXT1(void, alUnmapBuffer,SOFT, ALuint,buffer)
FORCE_ALIGN void AL_APIENTRY alUnmapBufferDirectSOFT(ALCcontext *context, ALuint buffer) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(albuf->MappedAccess == 0)
        throw al::context_error{AL_INVALID_OPERATION, "Unmapping unmapped buffer %u", buffer};

    albuf->MappedAccess = 0;
    albuf->MappedOffset = 0;
    albuf->MappedSize = 0;
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNCEXT3(void, alFlushMappedBuffer,SOFT, ALuint,buffer, ALsizei,offset, ALsizei,length)
FORCE_ALIGN void AL_APIENTRY alFlushMappedBufferDirectSOFT(ALCcontext *context, ALuint buffer,
    ALsizei offset, ALsizei length) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!(albuf->MappedAccess&AL_MAP_WRITE_BIT_SOFT))
        throw al::context_error{AL_INVALID_OPERATION,
            "Flushing buffer %u while not mapped for writing", buffer};
    if(offset < albuf->MappedOffset || length <= 0
        || offset >= albuf->MappedOffset+albuf->MappedSize
        || length > albuf->MappedOffset+albuf->MappedSize-offset)
        throw al::context_error{AL_INVALID_VALUE, "Flushing invalid range %d+%d on buffer %u",
            offset, length, buffer};

    /* FIXME: Need to use some method of double-buffering for the mixer and app
     * to hold separate memory, which can be safely transferred asynchronously.
     * Currently we just say the app shouldn't write where OpenAL's reading,
     * and hope for the best...
     */
    std::atomic_thread_fence(std::memory_order_seq_cst);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNCEXT5(void, alBufferSubData,SOFT, ALuint,buffer, ALenum,format, const ALvoid*,data, ALsizei,offset, ALsizei,length)
FORCE_ALIGN void AL_APIENTRY alBufferSubDataDirectSOFT(ALCcontext *context, ALuint buffer,
    ALenum format, const ALvoid *data, ALsizei offset, ALsizei length) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};

    auto usrfmt = DecomposeUserFormat(format);
    if(!usrfmt)
        throw al::context_error{AL_INVALID_ENUM, "Invalid format 0x%04x", format};

    const ALuint unpack_align{albuf->UnpackAlign};
    const ALuint align{SanitizeAlignment(usrfmt->type, unpack_align)};
    if(align < 1)
        throw al::context_error{AL_INVALID_VALUE, "Invalid unpack alignment %u", unpack_align};
    if(usrfmt->channels != albuf->mChannels || usrfmt->type != albuf->mType)
        throw al::context_error{AL_INVALID_ENUM, "Unpacking data with mismatched format"};
    if(align != albuf->mBlockAlign)
        throw al::context_error{AL_INVALID_VALUE,
            "Unpacking data with alignment %u does not match original alignment %u", align,
            albuf->mBlockAlign};
    if(albuf->isBFormat() && albuf->UnpackAmbiOrder != albuf->mAmbiOrder)
        throw al::context_error{AL_INVALID_VALUE,
            "Unpacking data with mismatched ambisonic order"};
    if(albuf->MappedAccess != 0)
        throw al::context_error{AL_INVALID_OPERATION, "Unpacking data into mapped buffer %u",
            buffer};

    const ALuint num_chans{albuf->channelsFromFmt()};
    const ALuint byte_align{
        (albuf->mType == FmtIMA4) ? ((align-1)/2 + 4) * num_chans :
        (albuf->mType == FmtMSADPCM) ? ((align-2)/2 + 7) * num_chans :
        (align * albuf->bytesFromFmt() * num_chans)};

    if(offset < 0 || length < 0 || static_cast<ALuint>(offset) > albuf->OriginalSize
        || static_cast<ALuint>(length) > albuf->OriginalSize-static_cast<ALuint>(offset))
        throw al::context_error{AL_INVALID_VALUE, "Invalid data sub-range %d+%d on buffer %u",
            offset, length, buffer};
    if((static_cast<ALuint>(offset)%byte_align) != 0)
        throw al::context_error{AL_INVALID_VALUE,
            "Sub-range offset %d is not a multiple of frame size %d (%d unpack alignment)",
            offset, byte_align, align};
    if((static_cast<ALuint>(length)%byte_align) != 0)
        throw al::context_error{AL_INVALID_VALUE,
            "Sub-range length %d is not a multiple of frame size %d (%d unpack alignment)",
            length, byte_align, align};

    std::memcpy(albuf->mData.data()+offset, data, static_cast<ALuint>(length));
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


AL_API DECL_FUNC3(void, alBufferf, ALuint,buffer, ALenum,param, ALfloat,value)
FORCE_ALIGN void AL_APIENTRY alBufferfDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALfloat value [[maybe_unused]]) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    if(LookupBuffer(device, buffer) == nullptr)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};

    switch(param)
    {
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer float property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC5(void, alBuffer3f, ALuint,buffer, ALenum,param, ALfloat,value1, ALfloat,value2, ALfloat,value3)
FORCE_ALIGN void AL_APIENTRY alBuffer3fDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALfloat value1 [[maybe_unused]], ALfloat value2 [[maybe_unused]],
    ALfloat value3 [[maybe_unused]]) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    if(LookupBuffer(device, buffer) == nullptr)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};

    switch(param)
    {
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer 3-float property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alBufferfv, ALuint,buffer, ALenum,param, const ALfloat*,values)
FORCE_ALIGN void AL_APIENTRY alBufferfvDirect(ALCcontext *context, ALuint buffer, ALenum param,
    const ALfloat *values) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    if(LookupBuffer(device, buffer) == nullptr)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!values)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer float-vector property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


AL_API DECL_FUNC3(void, alBufferi, ALuint,buffer, ALenum,param, ALint,value)
FORCE_ALIGN void AL_APIENTRY alBufferiDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALint value) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};

    switch(param)
    {
    case AL_UNPACK_BLOCK_ALIGNMENT_SOFT:
        if(value < 0)
            throw al::context_error{AL_INVALID_VALUE, "Invalid unpack block alignment %d", value};
        albuf->UnpackAlign = static_cast<ALuint>(value);
        return;

    case AL_PACK_BLOCK_ALIGNMENT_SOFT:
        if(value < 0)
            throw al::context_error{AL_INVALID_VALUE, "Invalid pack block alignment %d", value};
        albuf->PackAlign = static_cast<ALuint>(value);
        return;

    case AL_AMBISONIC_LAYOUT_SOFT:
        if(albuf->ref.load(std::memory_order_relaxed) != 0)
            throw al::context_error{AL_INVALID_OPERATION,
                "Modifying in-use buffer %u's ambisonic layout", buffer};
        if(const auto layout = AmbiLayoutFromEnum(value))
        {
            albuf->mAmbiLayout = layout.value();
            return;
        }
        throw al::context_error{AL_INVALID_VALUE, "Invalid unpack ambisonic layout %04x", value};

    case AL_AMBISONIC_SCALING_SOFT:
        if(albuf->ref.load(std::memory_order_relaxed) != 0)
            throw al::context_error{AL_INVALID_OPERATION,
                "Modifying in-use buffer %u's ambisonic scaling", buffer};
        if(const auto scaling = AmbiScalingFromEnum(value))
        {
            albuf->mAmbiScaling = scaling.value();
            return;
        }
        throw al::context_error{AL_INVALID_VALUE, "Invalid unpack ambisonic scaling %04x", value};

    case AL_UNPACK_AMBISONIC_ORDER_SOFT:
        if(value < 1 || value > 14)
            throw al::context_error{AL_INVALID_VALUE, "Invalid unpack ambisonic order %d", value};
        albuf->UnpackAmbiOrder = static_cast<ALuint>(value);
        return;
    }

    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer integer property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC5(void, alBuffer3i, ALuint,buffer, ALenum,param, ALint,value1, ALint,value2, ALint,value3)
FORCE_ALIGN void AL_APIENTRY alBuffer3iDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALint value1 [[maybe_unused]], ALint value2 [[maybe_unused]], ALint value3 [[maybe_unused]]) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    if(LookupBuffer(device, buffer) == nullptr)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};

    switch(param)
    {
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer 3-integer property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alBufferiv, ALuint,buffer, ALenum,param, const ALint*,values)
FORCE_ALIGN void AL_APIENTRY alBufferivDirect(ALCcontext *context, ALuint buffer, ALenum param,
    const ALint *values) noexcept
try {
    if(!values)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    case AL_UNPACK_BLOCK_ALIGNMENT_SOFT:
    case AL_PACK_BLOCK_ALIGNMENT_SOFT:
    case AL_AMBISONIC_LAYOUT_SOFT:
    case AL_AMBISONIC_SCALING_SOFT:
    case AL_UNPACK_AMBISONIC_ORDER_SOFT:
        alBufferiDirect(context, buffer, param, *values);
        return;
    }

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};

    switch(param)
    {
    case AL_LOOP_POINTS_SOFT:
        auto vals = al::span{values, 2_uz};
        if(albuf->ref.load(std::memory_order_relaxed) != 0)
            throw al::context_error{AL_INVALID_OPERATION,
                "Modifying in-use buffer %u's loop points", buffer};
        if(vals[0] < 0 || vals[0] >= vals[1] || static_cast<ALuint>(vals[1]) > albuf->mSampleLen)
            throw al::context_error{AL_INVALID_VALUE,
                "Invalid loop point range %d -> %d on buffer %u", vals[0], vals[1], buffer};

        albuf->mLoopStart = static_cast<ALuint>(vals[0]);
        albuf->mLoopEnd = static_cast<ALuint>(vals[1]);
        return;
    }

    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer integer-vector property 0x%04x",
        param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


AL_API DECL_FUNC3(void, alGetBufferf, ALuint,buffer, ALenum,param, ALfloat*,value)
FORCE_ALIGN void AL_APIENTRY alGetBufferfDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALfloat *value) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!value)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    case AL_SEC_LENGTH_SOFT:
        *value = (albuf->mSampleRate < 1) ? 0.0f :
            (static_cast<float>(albuf->mSampleLen) / static_cast<float>(albuf->mSampleRate));
        return;
    }

    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer float property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC5(void, alGetBuffer3f, ALuint,buffer, ALenum,param, ALfloat*,value1, ALfloat*,value2, ALfloat*,value3)
FORCE_ALIGN void AL_APIENTRY alGetBuffer3fDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALfloat *value1, ALfloat *value2, ALfloat *value3) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    if(LookupBuffer(device, buffer) == nullptr)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!value1 || !value2 || !value3)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer 3-float property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alGetBufferfv, ALuint,buffer, ALenum,param, ALfloat*,values)
FORCE_ALIGN void AL_APIENTRY alGetBufferfvDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALfloat *values) noexcept
try {
    switch(param)
    {
    case AL_SEC_LENGTH_SOFT:
        alGetBufferfDirect(context, buffer, param, values);
        return;
    }

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    if(LookupBuffer(device, buffer) == nullptr)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!values)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer float-vector property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


AL_API DECL_FUNC3(void, alGetBufferi, ALuint,buffer, ALenum,param, ALint*,value)
FORCE_ALIGN void AL_APIENTRY alGetBufferiDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALint *value) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!value)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    case AL_FREQUENCY:
        *value = static_cast<ALint>(albuf->mSampleRate);
        return;

    case AL_BITS:
        *value = (albuf->mType == FmtIMA4 || albuf->mType == FmtMSADPCM) ? 4
            : static_cast<ALint>(albuf->bytesFromFmt() * 8);
        return;

    case AL_CHANNELS:
        *value = static_cast<ALint>(albuf->channelsFromFmt());
        return;

    case AL_SIZE:
        *value = albuf->mCallback ? 0 : static_cast<ALint>(albuf->mData.size());
        return;

    case AL_BYTE_LENGTH_SOFT:
        *value = static_cast<ALint>(albuf->mSampleLen / albuf->mBlockAlign
            * albuf->blockSizeFromFmt());
        return;

    case AL_SAMPLE_LENGTH_SOFT:
        *value = static_cast<ALint>(albuf->mSampleLen);
        return;

    case AL_UNPACK_BLOCK_ALIGNMENT_SOFT:
        *value = static_cast<ALint>(albuf->UnpackAlign);
        return;

    case AL_PACK_BLOCK_ALIGNMENT_SOFT:
        *value = static_cast<ALint>(albuf->PackAlign);
        return;

    case AL_AMBISONIC_LAYOUT_SOFT:
        *value = EnumFromAmbiLayout(albuf->mAmbiLayout);
        return;

    case AL_AMBISONIC_SCALING_SOFT:
        *value = EnumFromAmbiScaling(albuf->mAmbiScaling);
        return;

    case AL_UNPACK_AMBISONIC_ORDER_SOFT:
        *value = static_cast<int>(albuf->UnpackAmbiOrder);
        return;
    }

    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer integer property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC5(void, alGetBuffer3i, ALuint,buffer, ALenum,param, ALint*,value1, ALint*,value2, ALint*,value3)
FORCE_ALIGN void AL_APIENTRY alGetBuffer3iDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALint *value1, ALint *value2, ALint *value3) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    if(LookupBuffer(device, buffer) == nullptr)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!value1 || !value2 || !value3)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer 3-integer property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alGetBufferiv, ALuint,buffer, ALenum,param, ALint*,values)
FORCE_ALIGN void AL_APIENTRY alGetBufferivDirect(ALCcontext *context, ALuint buffer, ALenum param,
    ALint *values) noexcept
try {
    switch(param)
    {
    case AL_FREQUENCY:
    case AL_BITS:
    case AL_CHANNELS:
    case AL_SIZE:
    case AL_INTERNAL_FORMAT_SOFT:
    case AL_BYTE_LENGTH_SOFT:
    case AL_SAMPLE_LENGTH_SOFT:
    case AL_UNPACK_BLOCK_ALIGNMENT_SOFT:
    case AL_PACK_BLOCK_ALIGNMENT_SOFT:
    case AL_AMBISONIC_LAYOUT_SOFT:
    case AL_AMBISONIC_SCALING_SOFT:
    case AL_UNPACK_AMBISONIC_ORDER_SOFT:
        alGetBufferiDirect(context, buffer, param, values);
        return;
    }

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!values)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    case AL_LOOP_POINTS_SOFT:
        auto vals = al::span{values, 2_uz};
        vals[0] = static_cast<ALint>(albuf->mLoopStart);
        vals[1] = static_cast<ALint>(albuf->mLoopEnd);
        return;
    }

    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer integer-vector property 0x%04x",
        param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


AL_API DECL_FUNCEXT5(void, alBufferCallback,SOFT, ALuint,buffer, ALenum,format, ALsizei,freq, ALBUFFERCALLBACKTYPESOFT,callback, ALvoid*,userptr)
FORCE_ALIGN void AL_APIENTRY alBufferCallbackDirectSOFT(ALCcontext *context, ALuint buffer,
    ALenum format, ALsizei freq, ALBUFFERCALLBACKTYPESOFT callback, ALvoid *userptr) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(freq < 1)
        throw al::context_error{AL_INVALID_VALUE, "Invalid sample rate %d", freq};
    if(callback == nullptr)
        throw al::context_error{AL_INVALID_VALUE, "NULL callback"};

    auto usrfmt = DecomposeUserFormat(format);
    if(!usrfmt)
        throw al::context_error{AL_INVALID_ENUM, "Invalid format 0x%04x", format};

    PrepareCallback(context, albuf, freq, usrfmt->channels, usrfmt->type, callback, userptr);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNCEXT3(void, alGetBufferPtr,SOFT, ALuint,buffer, ALenum,param, ALvoid**,value)
FORCE_ALIGN void AL_APIENTRY alGetBufferPtrDirectSOFT(ALCcontext *context, ALuint buffer,
    ALenum param, ALvoid **value) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    ALbuffer *albuf{LookupBuffer(device, buffer)};
    if(!albuf)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!value)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    case AL_BUFFER_CALLBACK_FUNCTION_SOFT:
        *value = reinterpret_cast<void*>(albuf->mCallback);
        return;
    case AL_BUFFER_CALLBACK_USER_PARAM_SOFT:
        *value = albuf->mUserData;
        return;
    }

    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer pointer property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNCEXT5(void, alGetBuffer3Ptr,SOFT, ALuint,buffer, ALenum,param, ALvoid**,value1, ALvoid**,value2, ALvoid**,value3)
FORCE_ALIGN void AL_APIENTRY alGetBuffer3PtrDirectSOFT(ALCcontext *context, ALuint buffer,
    ALenum param, ALvoid **value1, ALvoid **value2, ALvoid **value3) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    if(LookupBuffer(device, buffer) == nullptr)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!value1 || !value2 || !value3)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer 3-pointer property 0x%04x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNCEXT3(void, alGetBufferPtrv,SOFT, ALuint,buffer, ALenum,param, ALvoid**,values)
FORCE_ALIGN void AL_APIENTRY alGetBufferPtrvDirectSOFT(ALCcontext *context, ALuint buffer,
    ALenum param, ALvoid **values) noexcept
try {
    switch(param)
    {
    case AL_BUFFER_CALLBACK_FUNCTION_SOFT:
    case AL_BUFFER_CALLBACK_USER_PARAM_SOFT:
        alGetBufferPtrDirectSOFT(context, buffer, param, values);
        return;
    }

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    if(LookupBuffer(device, buffer) == nullptr)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};
    if(!values)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid buffer pointer-vector property 0x%04x",
        param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


AL_API void AL_APIENTRY alBufferSamplesSOFT(ALuint /*buffer*/, ALuint /*samplerate*/,
    ALenum /*internalformat*/, ALsizei /*samples*/, ALenum /*channels*/, ALenum /*type*/,
    const ALvoid* /*data*/) noexcept
{
    ContextRef context{GetContextRef()};
    if(!context) UNLIKELY return;

    context->setError(AL_INVALID_OPERATION, "alBufferSamplesSOFT not supported");
}

AL_API void AL_APIENTRY alBufferSubSamplesSOFT(ALuint /*buffer*/, ALsizei /*offset*/,
    ALsizei /*samples*/, ALenum /*channels*/, ALenum /*type*/, const ALvoid* /*data*/) noexcept
{
    ContextRef context{GetContextRef()};
    if(!context) UNLIKELY return;

    context->setError(AL_INVALID_OPERATION, "alBufferSubSamplesSOFT not supported");
}

AL_API void AL_APIENTRY alGetBufferSamplesSOFT(ALuint /*buffer*/, ALsizei /*offset*/,
    ALsizei /*samples*/, ALenum /*channels*/, ALenum /*type*/, ALvoid* /*data*/) noexcept
{
    ContextRef context{GetContextRef()};
    if(!context) UNLIKELY return;

    context->setError(AL_INVALID_OPERATION, "alGetBufferSamplesSOFT not supported");
}

AL_API ALboolean AL_APIENTRY alIsBufferFormatSupportedSOFT(ALenum /*format*/) noexcept
{
    ContextRef context{GetContextRef()};
    if(!context) UNLIKELY return AL_FALSE;

    context->setError(AL_INVALID_OPERATION, "alIsBufferFormatSupportedSOFT not supported");
    return AL_FALSE;
}


void ALbuffer::SetName(ALCcontext *context, ALuint id, std::string_view name)
{
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> buflock{device->BufferLock};

    auto buffer = LookupBuffer(device, id);
    if(!buffer)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", id};

    device->mBufferNames.insert_or_assign(id, name);
}


BufferSubList::~BufferSubList()
{
    if(!Buffers)
        return;

    uint64_t usemask{~FreeMask};
    while(usemask)
    {
        const int idx{al::countr_zero(usemask)};
        std::destroy_at(al::to_address(Buffers->begin() + idx));
        usemask &= ~(1_u64 << idx);
    }
    FreeMask = ~usemask;
    SubListAllocator{}.deallocate(Buffers, 1);
    Buffers = nullptr;
}


#if ALSOFT_EAX
FORCE_ALIGN DECL_FUNC3(ALboolean, EAXSetBufferMode, ALsizei,n, const ALuint*,buffers, ALint,value)
FORCE_ALIGN ALboolean AL_APIENTRY EAXSetBufferModeDirect(ALCcontext *context, ALsizei n,
    const ALuint *buffers, ALint value) noexcept
try {
    if(!eax_g_is_enabled)
        throw al::context_error{AL_INVALID_OPERATION, "EAX not enabled"};

    const auto storage = EaxStorageFromEnum(value);
    if(!storage)
        throw al::context_error{AL_INVALID_ENUM, "Unsupported X-RAM mode 0x%x", value};

    if(n == 0)
        return AL_TRUE;

    if(n < 0)
        throw al::context_error{AL_INVALID_VALUE, "Buffer count %d out of range", n};
    if(!buffers)
        throw al::context_error{AL_INVALID_VALUE, "Null AL buffers"};

    auto device = context->mALDevice.get();
    std::lock_guard<std::mutex> devlock{device->BufferLock};

    /* Special-case setting a single buffer, to avoid extraneous allocations. */
    if(n == 1)
    {
        const auto bufid = *buffers;
        if(bufid == AL_NONE)
            return AL_TRUE;

        const auto buffer = LookupBuffer(device, bufid);
        if(!buffer)
            throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", bufid};

        /* TODO: Is the store location allowed to change for in-use buffers, or
         * only when not set/queued on a source?
         */

        if(*storage == EaxStorage::Hardware)
        {
            if(!buffer->eax_x_ram_is_hardware
                && buffer->OriginalSize > device->eax_x_ram_free_size)
                throw al::context_error{AL_OUT_OF_MEMORY,
                    "Out of X-RAM memory (need: %u, avail: %u)", buffer->OriginalSize,
                    device->eax_x_ram_free_size};

            eax_x_ram_apply(*device, *buffer);
        }
        else
            eax_x_ram_clear(*device, *buffer);
        buffer->eax_x_ram_mode = *storage;
        return AL_TRUE;
    }

    /* Validate the buffers. */
    std::unordered_set<ALbuffer*> buflist;
    for(const ALuint bufid : al::span{buffers, static_cast<ALuint>(n)})
    {
        if(bufid == AL_NONE)
            continue;

        const auto buffer = LookupBuffer(device, bufid);
        if(!buffer)
            throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", bufid};

        /* TODO: Is the store location allowed to change for in-use buffers, or
         * only when not set/queued on a source?
         */

        buflist.emplace(buffer);
    }

    if(*storage == EaxStorage::Hardware)
    {
        size_t total_needed{0};
        for(ALbuffer *buffer : buflist)
        {
            if(!buffer->eax_x_ram_is_hardware)
            {
                if(std::numeric_limits<size_t>::max() - buffer->OriginalSize < total_needed)
                    throw al::context_error{AL_OUT_OF_MEMORY, "Size overflow (%u + %zu)",
                        buffer->OriginalSize, total_needed};

                total_needed += buffer->OriginalSize;
            }
        }
        if(total_needed > device->eax_x_ram_free_size)
            throw al::context_error{AL_OUT_OF_MEMORY, "Out of X-RAM memory (need: %zu, avail: %u)",
                total_needed, device->eax_x_ram_free_size};
    }

    /* Update the mode. */
    for(ALbuffer *buffer : buflist)
    {
        if(*storage == EaxStorage::Hardware)
            eax_x_ram_apply(*device, *buffer);
        else
            eax_x_ram_clear(*device, *buffer);
        buffer->eax_x_ram_mode = *storage;
    }

    return AL_TRUE;
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "[EAXSetBufferMode] %s", e.what());
    return AL_FALSE;
}

FORCE_ALIGN DECL_FUNC2(ALenum, EAXGetBufferMode, ALuint,buffer, ALint*,pReserved)
FORCE_ALIGN ALenum AL_APIENTRY EAXGetBufferModeDirect(ALCcontext *context, ALuint buffer,
    ALint *pReserved) noexcept
try {

    if(!eax_g_is_enabled)
        throw al::context_error{AL_INVALID_OPERATION, "EAX not enabled."};

    if(pReserved)
        throw al::context_error{AL_INVALID_VALUE, "Non-null reserved parameter"};

    auto device = context->mALDevice.get();
    std::lock_guard<std::mutex> devlock{device->BufferLock};

    const auto al_buffer = LookupBuffer(device, buffer);
    if(!al_buffer)
        throw al::context_error{AL_INVALID_NAME, "Invalid buffer ID %u", buffer};

    return EnumFromEaxStorage(al_buffer->eax_x_ram_mode);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "[EAXGetBufferMode] %s", e.what());
    return AL_NONE;
}

#endif // ALSOFT_EAX
