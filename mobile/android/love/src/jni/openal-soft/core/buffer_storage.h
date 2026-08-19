#ifndef CORE_BUFFER_STORAGE_H
#define CORE_BUFFER_STORAGE_H

#include <atomic>
#include <cstddef>

#include "alnumeric.h"
#include "alspan.h"
#include "ambidefs.h"
#include "storage_formats.h"


using uint = unsigned int;

constexpr bool IsBFormat(FmtChannels chans) noexcept
{ return chans == FmtBFormat2D || chans == FmtBFormat3D; }

/* Super Stereo is considered part of the UHJ family here, since it goes
 * through similar processing as UHJ, both result in a B-Format signal, and
 * needs the same consideration as BHJ (three channel result with only two
 * channel input).
 */
constexpr bool IsUHJ(FmtChannels chans) noexcept
{ return chans == FmtUHJ2 || chans == FmtUHJ3 || chans == FmtUHJ4 || chans == FmtSuperStereo; }

/** Ambisonic formats are either B-Format or UHJ formats. */
constexpr bool IsAmbisonic(FmtChannels chans) noexcept
{ return IsBFormat(chans) || IsUHJ(chans); }

constexpr bool Is2DAmbisonic(FmtChannels chans) noexcept
{
    return chans == FmtBFormat2D || chans == FmtUHJ2 || chans == FmtUHJ3
        || chans == FmtSuperStereo;
}


using CallbackType = int(*)(void*, void*, int);

struct BufferStorage {
    CallbackType mCallback{nullptr};
    void *mUserData{nullptr};

    al::span<std::byte> mData;

    uint mSampleRate{0u};
    FmtChannels mChannels{FmtMono};
    FmtType mType{FmtShort};
    uint mSampleLen{0u};
    uint mBlockAlign{0u};

    AmbiLayout mAmbiLayout{AmbiLayout::FuMa};
    AmbiScaling mAmbiScaling{AmbiScaling::FuMa};
    uint mAmbiOrder{0u};

    [[nodiscard]] auto bytesFromFmt() const noexcept -> uint { return BytesFromFmt(mType); }
    [[nodiscard]] auto channelsFromFmt() const noexcept -> uint
    { return ChannelsFromFmt(mChannels, mAmbiOrder); }
    [[nodiscard]] auto frameSizeFromFmt() const noexcept -> uint
    { return channelsFromFmt() * bytesFromFmt(); }

    [[nodiscard]] auto blockSizeFromFmt() const noexcept -> uint
    {
        if(mType == FmtIMA4) return ((mBlockAlign-1)/2 + 4) * channelsFromFmt();
        if(mType == FmtMSADPCM) return ((mBlockAlign-2)/2 + 7) * channelsFromFmt();
        return frameSizeFromFmt();
    };

    [[nodiscard]] auto isBFormat() const noexcept -> bool { return IsBFormat(mChannels); }
};

#endif /* CORE_BUFFER_STORAGE_H */
