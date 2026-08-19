/*
 * OpenAL LAF Playback Example
 *
 * Copyright (c) 2024 by Chris Robinson <chris.kcat@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

/* This file contains an example for playback of Limitless Audio Format files.
 *
 * Some current shortcomings:
 *
 * - 256 track limit. Could be made higher, but making it too flexible would
 *   necessitate more micro-allocations.
 *
 * - "Objects" mode only supports sample rates that are a multiple of 48. Since
 *   positions are specified as samples in extra channels/tracks, and 3*16
 *   samples are needed per track to specify the full set of positions, and
 *   each chunk is exactly one second long, other sample rates would result in
 *   the positions being split across chunks, causing the source playback
 *   offset to go out of sync with the offset used to look up the current
 *   spatial positions. Fixing this will require slightly more work to update
 *   and synchronize the spatial position arrays against the playback offset.
 *
 * - Updates are specified as fast as the app can detect and react to the
 *   reported source offset (that in turn depends on how often OpenAL renders).
 *   This can cause some positions to be a touch late and lose some granular
 *   temporal movement. In practice, this should probably be good enough for
 *   most use-cases. Fixing this would need either a new extension to queue
 *   position changes to apply when needed, or use a separate loopback device
 *   to render with and control the number of samples rendered between updates
 *   (with a second device to do the actual playback).
 *
 * - The LAF documentation doesn't prohibit object position tracks from being
 *   separated with audio tracks in between, or from being the first tracks
 *   followed by the audio tracks. It's not known if this is intended to be
 *   allowed, but it's not supported. Object position tracks must be last.
 *
 * Some remaining issues:
 *
 * - There are bursts of static on some channels. This doesn't appear to be a
 *   parsing error since the bursts last less than the chunk size, and it never
 *   loses sync with the remaining chunks. Might be an encoding error with the
 *   files tested.
 *
 * - Positions are specified in left-handed coordinates, despite the LAF
 *   documentation saying it's right-handed. Might be an encoding error with
 *   the files tested, or might be a misunderstanding about which is which. How
 *   to proceed may depend on how wide-spread this issue ends up being, but for
 *   now, they're treated as left-handed here.
 *
 * - The LAF documentation doesn't specify the range or direction for the
 *   channels' X and Y axis rotation in Channels mode. Presumably X rotation
 *   (elevation) goes from -pi/2...+pi/2 and Y rotation (azimuth) goes from
 *   either -pi...+pi or 0...pi*2, but the direction of movement isn't
 *   specified. Currently positive azimuth moves from center rightward and
 *   positive elevation moves from head-level upward.
 */

#include <algorithm>
#include <array>
#include <cassert>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <numeric>
#include <string>
#include <string_view>
#include <thread>
#include <type_traits>
#include <vector>

#include "AL/alc.h"
#include "AL/al.h"
#include "AL/alext.h"

#include "albit.h"
#include "almalloc.h"
#include "alnumeric.h"
#include "alspan.h"
#include "alstring.h"
#include "common/alhelpers.h"

#include "win_main_utf8.h"

namespace {

/* Filter object functions */
auto alGenFilters = LPALGENFILTERS{};
auto alDeleteFilters = LPALDELETEFILTERS{};
auto alIsFilter = LPALISFILTER{};
auto alFilteri = LPALFILTERI{};
auto alFilteriv = LPALFILTERIV{};
auto alFilterf = LPALFILTERF{};
auto alFilterfv = LPALFILTERFV{};
auto alGetFilteri = LPALGETFILTERI{};
auto alGetFilteriv = LPALGETFILTERIV{};
auto alGetFilterf = LPALGETFILTERF{};
auto alGetFilterfv = LPALGETFILTERFV{};

/* Effect object functions */
auto alGenEffects = LPALGENEFFECTS{};
auto alDeleteEffects = LPALDELETEEFFECTS{};
auto alIsEffect = LPALISEFFECT{};
auto alEffecti = LPALEFFECTI{};
auto alEffectiv = LPALEFFECTIV{};
auto alEffectf = LPALEFFECTF{};
auto alEffectfv = LPALEFFECTFV{};
auto alGetEffecti = LPALGETEFFECTI{};
auto alGetEffectiv = LPALGETEFFECTIV{};
auto alGetEffectf = LPALGETEFFECTF{};
auto alGetEffectfv = LPALGETEFFECTFV{};

/* Auxiliary Effect Slot object functions */
auto alGenAuxiliaryEffectSlots = LPALGENAUXILIARYEFFECTSLOTS{};
auto alDeleteAuxiliaryEffectSlots = LPALDELETEAUXILIARYEFFECTSLOTS{};
auto alIsAuxiliaryEffectSlot = LPALISAUXILIARYEFFECTSLOT{};
auto alAuxiliaryEffectSloti = LPALAUXILIARYEFFECTSLOTI{};
auto alAuxiliaryEffectSlotiv = LPALAUXILIARYEFFECTSLOTIV{};
auto alAuxiliaryEffectSlotf = LPALAUXILIARYEFFECTSLOTF{};
auto alAuxiliaryEffectSlotfv = LPALAUXILIARYEFFECTSLOTFV{};
auto alGetAuxiliaryEffectSloti = LPALGETAUXILIARYEFFECTSLOTI{};
auto alGetAuxiliaryEffectSlotiv = LPALGETAUXILIARYEFFECTSLOTIV{};
auto alGetAuxiliaryEffectSlotf = LPALGETAUXILIARYEFFECTSLOTF{};
auto alGetAuxiliaryEffectSlotfv = LPALGETAUXILIARYEFFECTSLOTFV{};


auto MuteFilterID = ALuint{};
auto LowFrequencyEffectID = ALuint{};
auto LfeSlotID = ALuint{};


namespace fs = std::filesystem;
using namespace std::string_view_literals;

[[noreturn]]
void do_assert(const char *message, int linenum, const char *filename, const char *funcname)
{
    auto errstr = std::string{filename};
    errstr += ':';
    errstr += std::to_string(linenum);
    errstr += ": ";
    errstr += funcname;
    errstr += ": ";
    errstr += message;
    throw std::runtime_error{errstr};
}

#define MyAssert(cond) do {                                                   \
    if(!(cond)) UNLIKELY                                                      \
        do_assert("Assertion '" #cond "' failed", __LINE__, __FILE__,         \
            std::data(__func__));                                             \
} while(0)


enum class Quality : std::uint8_t {
    s8, s16, f32, s24
};
enum class Mode : bool {
    Channels, Objects
};

auto GetQualityName(Quality quality) noexcept -> std::string_view
{
    switch(quality)
    {
    case Quality::s8: return "8-bit int"sv;
    case Quality::s16: return "16-bit int"sv;
    case Quality::f32: return "32-bit float"sv;
    case Quality::s24: return "24-bit int"sv;
    }
    return "<unknown>"sv;
}

auto GetModeName(Mode mode) noexcept -> std::string_view
{
    switch(mode)
    {
    case Mode::Channels: return "channels"sv;
    case Mode::Objects: return "objects"sv;
    }
    return "<unknown>"sv;
}

auto BytesFromQuality(Quality quality) noexcept -> size_t
{
    switch(quality)
    {
    case Quality::s8: return 1;
    case Quality::s16: return 2;
    case Quality::f32: return 4;
    case Quality::s24: return 3;
    }
    return 4;
}

auto BufferBytesFromQuality(Quality quality) noexcept -> size_t
{
    switch(quality)
    {
    case Quality::s8: return 1;
    case Quality::s16: return 2;
    case Quality::f32: return 4;
    /* 24-bit samples are converted to 32-bit for OpenAL. */
    case Quality::s24: return 4;
    }
    return 4;
}


/* Helper class for reading little-endian samples on big-endian targets, or
 * convert 24-bit samples.
 */
template<Quality Q>
struct SampleReader;

template<>
struct SampleReader<Quality::s8> {
    using src_t = int8_t;
    using dst_t = int8_t;

    [[nodiscard]] static
    auto read(const src_t &in) noexcept -> dst_t { return in; }
};

template<>
struct SampleReader<Quality::s16> {
    using src_t = int16_t;
    using dst_t = int16_t;

    [[nodiscard]] static
    auto read(const src_t &in) noexcept -> dst_t
    {
        if constexpr(al::endian::native == al::endian::little)
            return in;
        else
            return al::byteswap(in);
    }
};

template<>
struct SampleReader<Quality::f32> {
    /* 32-bit float samples are read as 32-bit integer on big-endian systems,
     * so that they can be byteswapped before being reinterpreted as float.
     */
    using src_t = std::conditional_t<al::endian::native==al::endian::little, float,uint32_t>;
    using dst_t = float;

    [[nodiscard]] static
    auto read(const src_t &in) noexcept -> dst_t
    {
        if constexpr(al::endian::native == al::endian::little)
            return in;
        else
            return al::bit_cast<dst_t>(al::byteswap(static_cast<uint32_t>(in)));
    }
};

template<>
struct SampleReader<Quality::s24> {
    /* 24-bit samples are converted to 32-bit integer. */
    using src_t = std::array<uint8_t,3>;
    using dst_t = int32_t;

    [[nodiscard]] static
    auto read(const src_t &in) noexcept -> dst_t
    {
        return static_cast<int32_t>((uint32_t{in[0]}<<8) | (uint32_t{in[1]}<<16)
            | (uint32_t{in[2]}<<24));
    }
};


/* Each track with position data consists of a set of 3 samples per 16 audio
 * channels, resulting in a full set of positions being specified over 48
 * sample frames.
 */
constexpr auto FramesPerPos = 48_uz;

struct Channel {
    ALuint mSource{};
    std::array<ALuint,2> mBuffers{};
    float mAzimuth{};
    float mElevation{};
    bool mIsLfe{};

    Channel() = default;
    Channel(const Channel&) = delete;
    Channel(Channel&& rhs)
        : mSource{rhs.mSource}, mBuffers{rhs.mBuffers}, mAzimuth{rhs.mAzimuth}
        , mElevation{rhs.mElevation}, mIsLfe{rhs.mIsLfe}
    {
        rhs.mSource = 0;
        rhs.mBuffers.fill(0);
    }
    ~Channel()
    {
        if(mSource) alDeleteSources(1, &mSource);
        if(mBuffers[0]) alDeleteBuffers(ALsizei(mBuffers.size()), mBuffers.data());
    }

    auto operator=(const Channel&) -> Channel& = delete;
    auto operator=(Channel&& rhs) -> Channel&
    {
        std::swap(mSource, rhs.mSource);
        std::swap(mBuffers, rhs.mBuffers);
        std::swap(mAzimuth, rhs.mAzimuth);
        std::swap(mElevation, rhs.mElevation);
        std::swap(mIsLfe, rhs.mIsLfe);
        return *this;
    }
};

struct LafStream {
    std::ifstream mInFile;

    Quality mQuality{};
    Mode mMode{};
    uint32_t mNumTracks{};
    uint32_t mSampleRate{};
    ALenum mALFormat{};
    uint64_t mSampleCount{};

    uint64_t mCurrentSample{};

    std::array<uint8_t,32> mEnabledTracks{};
    uint32_t mNumEnabled{};
    std::vector<char> mSampleChunk;
    al::span<char> mSampleLine;

    std::vector<Channel> mChannels;
    std::vector<std::vector<float>> mPosTracks;

    LafStream() = default;
    LafStream(const LafStream&) = delete;
    ~LafStream() = default;
    auto operator=(const LafStream&) -> LafStream& = delete;

    [[nodiscard]]
    auto readChunk() -> uint32_t;

    void convertSamples(const al::span<char> samples) const;

    void convertPositions(const al::span<float> dst, const al::span<const char> src) const;

    template<Quality Q>
    void copySamples(char *dst, const char *src, size_t idx, size_t count) const;

    [[nodiscard]]
    auto prepareTrack(size_t trackidx, size_t count) -> al::span<char>;

    [[nodiscard]]
    auto isAtEnd() const noexcept -> bool { return mCurrentSample >= mSampleCount; }
};

auto LafStream::readChunk() -> uint32_t
{
    mEnabledTracks.fill(0);
    mInFile.read(reinterpret_cast<char*>(mEnabledTracks.data()), (mNumTracks+7_z)>>3);
    mNumEnabled = std::accumulate(mEnabledTracks.cbegin(), mEnabledTracks.cend(), 0u,
        [](const unsigned int val, const uint8_t in)
        { return val + unsigned(al::popcount(unsigned(in))); });

    /* Make sure enable bits aren't set for non-existent tracks. */
    if(mEnabledTracks[((mNumTracks+7_uz)>>3) - 1] >= (1u<<(mNumTracks&7)))
        throw std::runtime_error{"Invalid channel enable bits"};

    /* Each chunk is exactly one second long, with samples interleaved for each
     * enabled track. The last chunk may be shorter if there isn't enough time
     * remaining for a full second.
     */
    const auto numsamples = std::min(uint64_t{mSampleRate}, mSampleCount-mCurrentSample);

    const auto toread = std::streamsize(numsamples * BytesFromQuality(mQuality) * mNumEnabled);
    mInFile.read(mSampleChunk.data(), toread);
    if(mInFile.gcount() != toread)
        throw std::runtime_error{"Failed to read sample chunk"};

    std::fill(mSampleChunk.begin()+toread, mSampleChunk.end(), char{});

    mCurrentSample += numsamples;
    return static_cast<uint32_t>(numsamples);
}

void LafStream::convertSamples(const al::span<char> samples) const
{
    /* OpenAL uses unsigned 8-bit samples (0...255), so signed 8-bit samples
     * (-128...+127) need conversion. The other formats are fine.
     */
    if(mQuality == Quality::s8)
        std::transform(samples.begin(), samples.end(), samples.begin(),
            [](const char sample) noexcept { return char(sample^0x80); });
}

void LafStream::convertPositions(const al::span<float> dst, const al::span<const char> src) const
{
    switch(mQuality)
    {
    case Quality::s8:
        std::transform(src.begin(), src.end(), dst.begin(),
            [](const int8_t in) { return float(in) / 127.0f; });
        break;
    case Quality::s16:
        {
            auto i16src = al::span{reinterpret_cast<const int16_t*>(src.data()),
                src.size()/sizeof(int16_t)};
            std::transform(i16src.begin(), i16src.end(), dst.begin(),
                [](const int16_t in) { return float(in) / 32767.0f; });
        }
        break;
    case Quality::f32:
        {
            auto f32src = al::span{reinterpret_cast<const float*>(src.data()),
                src.size()/sizeof(float)};
            std::copy(f32src.begin(), f32src.end(), dst.begin());
        }
        break;
    case Quality::s24:
        {
            /* 24-bit samples are converted to 32-bit in copySamples. */
            auto i32src = al::span{reinterpret_cast<const int32_t*>(src.data()),
                src.size()/sizeof(int32_t)};
            std::transform(i32src.begin(), i32src.end(), dst.begin(),
                [](const int32_t in) { return float(in>>8) / 8388607.0f; });
        }
        break;
    }
}

template<Quality Q>
void LafStream::copySamples(char *dst, const char *src, const size_t idx, const size_t count) const
{
    using reader_t = SampleReader<Q>;
    using src_t = typename reader_t::src_t;
    using dst_t = typename reader_t::dst_t;

    const auto step = size_t{mNumEnabled};
    assert(idx < step);

    auto input = al::span{reinterpret_cast<const src_t*>(src), count*step};
    auto output = al::span{reinterpret_cast<dst_t*>(dst), count};

    auto inptr = input.begin();
    std::generate_n(output.begin(), output.size(), [&inptr,idx,step]
    {
        auto ret = reader_t::read(inptr[idx]);
        inptr += ptrdiff_t(step);
        return ret;
    });
}

auto LafStream::prepareTrack(const size_t trackidx, const size_t count) -> al::span<char>
{
    const auto todo = std::min(size_t{mSampleRate}, count);
    if((mEnabledTracks[trackidx>>3] & (1_uz<<(trackidx&7))))
    {
        /* If the track is enabled, get the real index (skipping disabled
         * tracks), and deinterlace it into the mono line.
         */
        const auto idx = [this,trackidx]() -> unsigned int
        {
            const auto bits = al::span{mEnabledTracks}.first(trackidx>>3);
            const auto res = std::accumulate(bits.begin(), bits.end(), 0u,
                [](const unsigned int val, const uint8_t in)
                { return val + unsigned(al::popcount(unsigned(in))); });
            return unsigned(al::popcount(mEnabledTracks[trackidx>>3] & ((1u<<(trackidx&7))-1)))
                + res;
        }();

        switch(mQuality)
        {
        case Quality::s8:
            copySamples<Quality::s8>(mSampleLine.data(), mSampleChunk.data(), idx, todo);
            break;
        case Quality::s16:
            copySamples<Quality::s16>(mSampleLine.data(), mSampleChunk.data(), idx, todo);
            break;
        case Quality::f32:
            copySamples<Quality::f32>(mSampleLine.data(), mSampleChunk.data(), idx, todo);
            break;
        case Quality::s24:
            copySamples<Quality::s24>(mSampleLine.data(), mSampleChunk.data(), idx, todo);
            break;
        }
    }
    else
    {
        /* If the track is disabled, provide silence. */
        std::fill_n(mSampleLine.begin(), mSampleLine.size(), char{});
    }

    return mSampleLine.first(todo * BufferBytesFromQuality(mQuality));
}


auto LoadLAF(const fs::path &fname) -> std::unique_ptr<LafStream>
{
    auto laf = std::make_unique<LafStream>();
    laf->mInFile.open(fname, std::ios_base::binary);

    auto marker = std::array<char,9>{};
    laf->mInFile.read(marker.data(), marker.size());
    if(laf->mInFile.gcount() != marker.size())
        throw std::runtime_error{"Failed to read file marker"};
    if(std::string_view{marker.data(), marker.size()} != "LIMITLESS"sv)
        throw std::runtime_error{"Not an LAF file"};

    auto header = std::array<char,10>{};
    laf->mInFile.read(header.data(), header.size());
    if(laf->mInFile.gcount() != header.size())
        throw std::runtime_error{"Failed to read header"};
    while(std::string_view{header.data(), 4} != "HEAD"sv)
    {
        auto headview = std::string_view{header.data(), header.size()};
        auto hiter = header.begin();
        if(const auto hpos = std::min(headview.find("HEAD"sv), headview.size());
            hpos < headview.size())
        {
            /* Found the HEAD marker. Copy what was read of the header to the
             * front, fill in the rest of the header, and continue loading.
             */
            hiter = std::copy(header.begin()+hpos, header.end(), hiter);
        }
        else if(al::ends_with(headview, "HEA"sv))
        {
            /* Found what might be the HEAD marker at the end. Copy it to the
             * front, refill the header, and check again.
             */
            hiter = std::copy_n(header.end()-3, 3, hiter);
        }
        else if(al::ends_with(headview, "HE"sv))
            hiter = std::copy_n(header.end()-2, 2, hiter);
        else if(headview.back() == 'H')
            hiter = std::copy_n(header.end()-1, 1, hiter);

        const auto toread = std::distance(hiter, header.end());
        laf->mInFile.read(al::to_address(hiter), toread);
        if(laf->mInFile.gcount() != toread)
            throw std::runtime_error{"Failed to read header"};
    }

    laf->mQuality = [stype=int{header[4]}] {
        if(stype == 0) return Quality::s8;
        if(stype == 1) return Quality::s16;
        if(stype == 2) return Quality::f32;
        if(stype == 3) return Quality::s24;
        throw std::runtime_error{"Invalid quality type: "+std::to_string(stype)};
    }();

    laf->mMode = [mode=int{header[5]}] {
        if(mode == 0) return Mode::Channels;
        if(mode == 1) return Mode::Objects;
        throw std::runtime_error{"Invalid mode: "+std::to_string(mode)};
    }();

    laf->mNumTracks = [input=al::span{header}.subspan<6,4>()] {
        return uint32_t{uint8_t(input[0])} | (uint32_t{uint8_t(input[1])}<<8u)
            | (uint32_t{uint8_t(input[2])}<<16u) | (uint32_t{uint8_t(input[3])}<<24u);
    }();

    std::cout<< "Filename: "<<fname<<'\n';
    std::cout<< " quality: "<<GetQualityName(laf->mQuality)<<'\n';
    std::cout<< " mode: "<<GetModeName(laf->mMode)<<'\n';
    std::cout<< " track count: "<<laf->mNumTracks<<'\n';

    if(laf->mNumTracks == 0)
        throw std::runtime_error{"No tracks"};
    if(laf->mNumTracks > 256)
        throw std::runtime_error{"Too many tracks: "+std::to_string(laf->mNumTracks)};

    auto chandata = std::vector<char>(laf->mNumTracks*9_uz);
    laf->mInFile.read(chandata.data(), std::streamsize(chandata.size()));
    if(laf->mInFile.gcount() != std::streamsize(chandata.size()))
        throw std::runtime_error{"Failed to read channel header data"};

    if(laf->mMode == Mode::Channels)
        laf->mChannels.reserve(laf->mNumTracks);
    else
    {
        if(laf->mNumTracks < 2)
            throw std::runtime_error{"Not enough tracks"};

        auto numchans = uint32_t{laf->mNumTracks - 1};
        auto numpostracks = uint32_t{1};
        while(numpostracks*16 < numchans)
        {
            --numchans;
            ++numpostracks;
        }
        laf->mChannels.reserve(numchans);
        laf->mPosTracks.reserve(numpostracks);
    }

    for(uint32_t i{0};i < laf->mNumTracks;++i)
    {
        static constexpr auto read_float = [](al::span<char,4> input)
        {
            const auto value = uint32_t{uint8_t(input[0])} | (uint32_t{uint8_t(input[1])}<<8u)
                | (uint32_t{uint8_t(input[2])}<<16u) | (uint32_t{uint8_t(input[3])}<<24u);
            return al::bit_cast<float>(value);
        };

        auto chan = al::span{chandata}.subspan(i*9_uz, 9);
        auto x_axis = read_float(chan.first<4>());
        auto y_axis = read_float(chan.subspan<4,4>());
        auto lfe_flag = int{chan[8]};

        std::cout<< "Track "<<i<<": E="<<x_axis<<", A="<<y_axis<<" (LFE: "<<lfe_flag<<")\n";

        if(x_axis != x_axis && y_axis == 0.0)
        {
            MyAssert(laf->mMode == Mode::Objects);
            MyAssert(i != 0);
            laf->mPosTracks.emplace_back();
        }
        else
        {
            MyAssert(laf->mPosTracks.empty());
            MyAssert(std::isfinite(x_axis) && std::isfinite(y_axis));
            auto &channel = laf->mChannels.emplace_back();
            channel.mAzimuth = y_axis;
            channel.mElevation = x_axis;
            channel.mIsLfe = lfe_flag != 0;
        }
    }
    std::cout<< "Channels: "<<laf->mChannels.size()<<'\n';

    /* For "objects" mode, ensure there's enough tracks with position data to
     * handle the audio channels.
     */
    if(laf->mMode == Mode::Objects)
        MyAssert(((laf->mChannels.size()-1)>>4) == laf->mPosTracks.size()-1);

    auto footer = std::array<char,12>{};
    laf->mInFile.read(footer.data(), footer.size());
    if(laf->mInFile.gcount() != footer.size())
        throw std::runtime_error{"Failed to read sample header data"};

    laf->mSampleRate = [input=al::span{footer}.first<4>()] {
        return uint32_t{uint8_t(input[0])} | (uint32_t{uint8_t(input[1])}<<8u)
            | (uint32_t{uint8_t(input[2])}<<16u) | (uint32_t{uint8_t(input[3])}<<24u);
    }();
    laf->mSampleCount = [input=al::span{footer}.last<8>()] {
        return uint64_t{uint8_t(input[0])} | (uint64_t{uint8_t(input[1])}<<8)
            | (uint64_t{uint8_t(input[2])}<<16u) | (uint64_t{uint8_t(input[3])}<<24u)
            | (uint64_t{uint8_t(input[4])}<<32u) | (uint64_t{uint8_t(input[5])}<<40u)
            | (uint64_t{uint8_t(input[6])}<<48u) | (uint64_t{uint8_t(input[7])}<<56u);
    }();
    std::cout<< "Sample rate: "<<laf->mSampleRate<<'\n';
    std::cout<< "Length: "<<laf->mSampleCount<<" samples ("
        <<(static_cast<double>(laf->mSampleCount)/static_cast<double>(laf->mSampleRate))<<" sec)\n";

    /* Position vectors get split across the PCM chunks if the sample rate
     * isn't a multiple of 48. Each PCM chunk is exactly one second (the sample
     * rate in sample frames). Each track with position data consists of a set
     * of 3 samples for 16 audio channels, resuling in 48 sample frames for a
     * full set of positions. Extra logic will be needed to manage the position
     * frame offset separate from each chunk.
     */
    MyAssert(laf->mMode == Mode::Channels || (laf->mSampleRate%FramesPerPos) == 0);

    for(size_t i{0};i < laf->mPosTracks.size();++i)
        laf->mPosTracks[i].resize(laf->mSampleRate*2_uz, 0.0f);

    laf->mSampleChunk.resize(laf->mSampleRate*BytesFromQuality(laf->mQuality)*laf->mNumTracks
        + laf->mSampleRate*BufferBytesFromQuality(laf->mQuality));
    laf->mSampleLine = al::span{laf->mSampleChunk}.last(laf->mSampleRate
        * BufferBytesFromQuality(laf->mQuality));

    return laf;
}

void PlayLAF(std::string_view fname)
try {
    auto laf = LoadLAF(fs::u8path(fname));

    switch(laf->mQuality)
    {
    case Quality::s8:
        laf->mALFormat = AL_FORMAT_MONO8;
        break;
    case Quality::s16:
        laf->mALFormat = AL_FORMAT_MONO16;
        break;
    case Quality::f32:
        if(alIsExtensionPresent("AL_EXT_FLOAT32"))
            laf->mALFormat = AL_FORMAT_MONO_FLOAT32;
        break;
    case Quality::s24:
        laf->mALFormat = alGetEnumValue("AL_FORMAT_MONO32");
        if(!laf->mALFormat || laf->mALFormat == -1)
            laf->mALFormat = alGetEnumValue("AL_FORMAT_MONO_I32");
        break;
    }
    if(!laf->mALFormat || laf->mALFormat == -1)
        throw std::runtime_error{"No supported format for "+std::string{GetQualityName(laf->mQuality)}+" samples"};

    auto alloc_channel = [](Channel &channel)
    {
        alGenSources(1, &channel.mSource);
        alGenBuffers(ALsizei(channel.mBuffers.size()), channel.mBuffers.data());

        /* Disable distance attenuation, and make sure the source stays locked
         * relative to the listener.
         */
        alSourcef(channel.mSource, AL_ROLLOFF_FACTOR, 0.0f);
        alSourcei(channel.mSource, AL_SOURCE_RELATIVE, AL_TRUE);

        /* FIXME: Is the Y rotation/azimuth clockwise or counter-clockwise?
         * Does +azimuth move a front sound right or left?
         */
        const auto x = std::sin(channel.mAzimuth) * std::cos(channel.mElevation);
        const auto y = std::sin(channel.mElevation);
        const auto z = -std::cos(channel.mAzimuth) * std::cos(channel.mElevation);
        alSource3f(channel.mSource, AL_POSITION, x, y, z);

        if(channel.mIsLfe)
        {
            if(LfeSlotID)
            {
                /* For LFE, silence the direct/dry path and connect the LFE aux
                 * slot on send 0.
                 */
                alSourcei(channel.mSource, AL_DIRECT_FILTER, ALint(MuteFilterID));
                alSource3i(channel.mSource, AL_AUXILIARY_SEND_FILTER, ALint(LfeSlotID), 0,
                    AL_FILTER_NULL);
            }
            else
            {
                /* If AL_EFFECT_DEDICATED_LOW_FREQUENCY_EFFECT isn't available,
                 * silence LFE channels since they may not be appropriate to
                 * play normally.
                 */
                alSourcef(channel.mSource, AL_GAIN, 0.0f);
            }
        }

        if(auto err=alGetError())
            throw std::runtime_error{std::string{"OpenAL error: "} + alGetString(err)};
    };
    std::for_each(laf->mChannels.begin(), laf->mChannels.end(), alloc_channel);

    while(!laf->isAtEnd())
    {
        auto state = ALenum{};
        auto offset = ALint{};
        auto processed = ALint{};
        /* All sources are played in sync, so they'll all be at the same offset
         * with the same state and number of processed buffers. Query the back
         * source just in case the previous update ran really late and missed
         * updating only some sources on time (in which case, the latter ones
         * will underrun, which this will detect and restart them all as
         * needed).
         */
        alGetSourcei(laf->mChannels.back().mSource, AL_BUFFERS_PROCESSED, &processed);
        alGetSourcei(laf->mChannels.back().mSource, AL_SAMPLE_OFFSET, &offset);
        alGetSourcei(laf->mChannels.back().mSource, AL_SOURCE_STATE, &state);

        if(state == AL_PLAYING || state == AL_PAUSED)
        {
            if(!laf->mPosTracks.empty())
            {
                alcSuspendContext(alcGetCurrentContext());
                for(size_t i{0};i < laf->mChannels.size();++i)
                {
                    const auto trackidx = i>>4;

                    const auto posoffset = unsigned(offset)/FramesPerPos*16_uz + (i&15);
                    const auto x = laf->mPosTracks[trackidx][posoffset*3 + 0];
                    const auto y = laf->mPosTracks[trackidx][posoffset*3 + 1];
                    const auto z = laf->mPosTracks[trackidx][posoffset*3 + 2];

                    /* Contrary to the docs, the position is left-handed and
                     * needs to be converted to right-handed.
                     */
                    alSource3f(laf->mChannels[i].mSource, AL_POSITION, x, y, -z);
                }
                alcProcessContext(alcGetCurrentContext());
            }

            if(processed > 0)
            {
                const auto numsamples = laf->readChunk();
                for(size_t i{0};i < laf->mChannels.size();++i)
                {
                    const auto samples = laf->prepareTrack(i, numsamples);
                    laf->convertSamples(samples);

                    auto bufid = ALuint{};
                    alSourceUnqueueBuffers(laf->mChannels[i].mSource, 1, &bufid);
                    alBufferData(bufid, laf->mALFormat, samples.data(), ALsizei(samples.size()),
                        ALsizei(laf->mSampleRate));
                    alSourceQueueBuffers(laf->mChannels[i].mSource, 1, &bufid);
                }
                for(size_t i{0};i < laf->mPosTracks.size();++i)
                {
                    std::copy(laf->mPosTracks[i].begin() + ptrdiff_t(laf->mSampleRate),
                        laf->mPosTracks[i].end(), laf->mPosTracks[i].begin());

                    const auto positions = laf->prepareTrack(laf->mChannels.size()+i, numsamples);
                    laf->convertPositions(al::span{laf->mPosTracks[i]}.last(laf->mSampleRate),
                        positions);
                }
            }
            else
                std::this_thread::sleep_for(std::chrono::milliseconds{10});
        }
        else if(state == AL_STOPPED)
        {
            auto sources = std::array<ALuint,256>{};
            for(size_t i{0};i < laf->mChannels.size();++i)
                sources[i] = laf->mChannels[i].mSource;
            alSourcePlayv(ALsizei(laf->mChannels.size()), sources.data());
        }
        else if(state == AL_INITIAL)
        {
            auto sources = std::array<ALuint,256>{};
            auto numsamples = laf->readChunk();
            for(size_t i{0};i < laf->mChannels.size();++i)
            {
                const auto samples = laf->prepareTrack(i, numsamples);
                laf->convertSamples(samples);
                alBufferData(laf->mChannels[i].mBuffers[0], laf->mALFormat, samples.data(),
                    ALsizei(samples.size()), ALsizei(laf->mSampleRate));
            }
            for(size_t i{0};i < laf->mPosTracks.size();++i)
            {
                const auto positions = laf->prepareTrack(laf->mChannels.size()+i, numsamples);
                laf->convertPositions(al::span{laf->mPosTracks[i]}.first(laf->mSampleRate),
                    positions);
            }

            numsamples = laf->readChunk();
            for(size_t i{0};i < laf->mChannels.size();++i)
            {
                const auto samples = laf->prepareTrack(i, numsamples);
                laf->convertSamples(samples);
                alBufferData(laf->mChannels[i].mBuffers[1], laf->mALFormat, samples.data(),
                    ALsizei(samples.size()), ALsizei(laf->mSampleRate));
                alSourceQueueBuffers(laf->mChannels[i].mSource,
                    ALsizei(laf->mChannels[i].mBuffers.size()), laf->mChannels[i].mBuffers.data());
                sources[i] = laf->mChannels[i].mSource;
            }
            for(size_t i{0};i < laf->mPosTracks.size();++i)
            {
                const auto positions = laf->prepareTrack(laf->mChannels.size()+i, numsamples);
                laf->convertPositions(al::span{laf->mPosTracks[i]}.last(laf->mSampleRate),
                    positions);
            }

            if(!laf->mPosTracks.empty())
            {
                for(size_t i{0};i < laf->mChannels.size();++i)
                {
                    const auto trackidx = i>>4;

                    const auto x = laf->mPosTracks[trackidx][(i&15)*3 + 0];
                    const auto y = laf->mPosTracks[trackidx][(i&15)*3 + 1];
                    const auto z = laf->mPosTracks[trackidx][(i&15)*3 + 2];

                    alSource3f(laf->mChannels[i].mSource, AL_POSITION, x, y, -z);
                }
            }

            alSourcePlayv(ALsizei(laf->mChannels.size()), sources.data());
        }
        else
            break;
    }

    auto state = ALenum{};
    auto offset = ALint{};
    alGetSourcei(laf->mChannels.back().mSource, AL_SAMPLE_OFFSET, &offset);
    alGetSourcei(laf->mChannels.back().mSource, AL_SOURCE_STATE, &state);
    while(alGetError() == AL_NO_ERROR && state == AL_PLAYING)
    {
        if(!laf->mPosTracks.empty())
        {
            alcSuspendContext(alcGetCurrentContext());
            for(size_t i{0};i < laf->mChannels.size();++i)
            {
                const auto trackidx = i>>4;

                const auto posoffset = unsigned(offset)/FramesPerPos*16_uz + (i&15);
                const auto x = laf->mPosTracks[trackidx][posoffset*3 + 0];
                const auto y = laf->mPosTracks[trackidx][posoffset*3 + 1];
                const auto z = laf->mPosTracks[trackidx][posoffset*3 + 2];

                alSource3f(laf->mChannels[i].mSource, AL_POSITION, x, y, -z);
            }
            alcProcessContext(alcGetCurrentContext());
        }
        std::this_thread::sleep_for(std::chrono::milliseconds{10});
        alGetSourcei(laf->mChannels.back().mSource, AL_SAMPLE_OFFSET, &offset);
        alGetSourcei(laf->mChannels.back().mSource, AL_SOURCE_STATE, &state);
    }
}
catch(std::exception& e) {
    std::cerr<< "Error playing "<<fname<<":\n  "<<e.what()<<'\n';
}

auto main(al::span<std::string_view> args) -> int
{
    /* Print out usage if no arguments were specified */
    if(args.size() < 2)
    {
        fprintf(stderr, "Usage: %.*s [-device <name>] <filenames...>\n", al::sizei(args[0]),
            args[0].data());
        return 1;
    }
    args = args.subspan(1);

    if(InitAL(args) != 0)
        throw std::runtime_error{"Failed to initialize OpenAL"};
    /* A simple RAII container for automating OpenAL shutdown. */
    struct AudioManager {
        AudioManager() = default;
        AudioManager(const AudioManager&) = delete;
        auto operator=(const AudioManager&) -> AudioManager& = delete;
        ~AudioManager()
        {
            if(LfeSlotID)
            {
                alDeleteAuxiliaryEffectSlots(1, &LfeSlotID);
                alDeleteEffects(1, &LowFrequencyEffectID);
                alDeleteFilters(1, &MuteFilterID);
            }
            CloseAL();
        }
    };
    AudioManager almgr;

    if(auto *device = alcGetContextsDevice(alcGetCurrentContext());
        alcIsExtensionPresent(device, "ALC_EXT_EFX")
        && alcIsExtensionPresent(device, "ALC_EXT_DEDICATED"))
    {
#define LOAD_PROC(x) do {                                                     \
        x = reinterpret_cast<decltype(x)>(alGetProcAddress(#x));              \
        if(!x) fprintf(stderr, "Failed to find function '%s'\n", #x);         \
    } while(0)
        LOAD_PROC(alGenFilters);
        LOAD_PROC(alDeleteFilters);
        LOAD_PROC(alIsFilter);
        LOAD_PROC(alFilterf);
        LOAD_PROC(alFilterfv);
        LOAD_PROC(alFilteri);
        LOAD_PROC(alFilteriv);
        LOAD_PROC(alGetFilterf);
        LOAD_PROC(alGetFilterfv);
        LOAD_PROC(alGetFilteri);
        LOAD_PROC(alGetFilteriv);
        LOAD_PROC(alGenEffects);
        LOAD_PROC(alDeleteEffects);
        LOAD_PROC(alIsEffect);
        LOAD_PROC(alEffectf);
        LOAD_PROC(alEffectfv);
        LOAD_PROC(alEffecti);
        LOAD_PROC(alEffectiv);
        LOAD_PROC(alGetEffectf);
        LOAD_PROC(alGetEffectfv);
        LOAD_PROC(alGetEffecti);
        LOAD_PROC(alGetEffectiv);
        LOAD_PROC(alGenAuxiliaryEffectSlots);
        LOAD_PROC(alDeleteAuxiliaryEffectSlots);
        LOAD_PROC(alIsAuxiliaryEffectSlot);
        LOAD_PROC(alAuxiliaryEffectSlotf);
        LOAD_PROC(alAuxiliaryEffectSlotfv);
        LOAD_PROC(alAuxiliaryEffectSloti);
        LOAD_PROC(alAuxiliaryEffectSlotiv);
        LOAD_PROC(alGetAuxiliaryEffectSlotf);
        LOAD_PROC(alGetAuxiliaryEffectSlotfv);
        LOAD_PROC(alGetAuxiliaryEffectSloti);
        LOAD_PROC(alGetAuxiliaryEffectSlotiv);
#undef LOAD_PROC

        alGenFilters(1, &MuteFilterID);
        alFilteri(MuteFilterID, AL_FILTER_TYPE, AL_FILTER_LOWPASS);
        alFilterf(MuteFilterID, AL_LOWPASS_GAIN, 0.0f);
        MyAssert(alGetError() == AL_NO_ERROR);

        alGenEffects(1, &LowFrequencyEffectID);
        alEffecti(LowFrequencyEffectID, AL_EFFECT_TYPE, AL_EFFECT_DEDICATED_LOW_FREQUENCY_EFFECT);
        MyAssert(alGetError() == AL_NO_ERROR);

        alGenAuxiliaryEffectSlots(1, &LfeSlotID);
        alAuxiliaryEffectSloti(LfeSlotID, AL_EFFECTSLOT_EFFECT, ALint(LowFrequencyEffectID));
        MyAssert(alGetError() == AL_NO_ERROR);
    }

    std::for_each(args.begin(), args.end(), PlayLAF);

    return 0;
}

} // namespace

int main(int argc, char **argv)
{
    MyAssert(argc >= 0);
    auto args = std::vector<std::string_view>(static_cast<unsigned int>(argc));
    std::copy_n(argv, args.size(), args.begin());
    return main(al::span{args});
}
