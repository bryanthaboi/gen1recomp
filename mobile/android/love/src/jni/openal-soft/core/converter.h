#ifndef CORE_CONVERTER_H
#define CORE_CONVERTER_H

#include <chrono>
#include <cstddef>
#include <memory>

#include "almalloc.h"
#include "devformat.h"
#include "flexarray.h"
#include "mixer/defs.h"
#include "resampler_limits.h"

using uint = unsigned int;


struct SampleConverter {
    DevFmtType mSrcType{};
    DevFmtType mDstType{};
    uint mSrcTypeSize{};
    uint mDstTypeSize{};

    uint mSrcPrepCount{};

    uint mFracOffset{};
    uint mIncrement{};
    InterpState mState{};
    ResamplerFunc mResample{};

    alignas(16) FloatBufferLine mSrcSamples{};
    alignas(16) FloatBufferLine mDstSamples{};

    struct ChanSamples {
        alignas(16) std::array<float,MaxResamplerPadding> PrevSamples;
    };
    al::FlexArray<ChanSamples> mChan;

    SampleConverter(size_t numchans) : mChan{numchans} { }

    [[nodiscard]] auto convert(const void **src, uint *srcframes, void *dst, uint dstframes) -> uint;
    [[nodiscard]] auto convertPlanar(const void **src, uint *srcframes, void *const*dst, uint dstframes) -> uint;
    [[nodiscard]] auto availableOut(uint srcframes) const -> uint;

    using SampleOffset = std::chrono::duration<int64_t, std::ratio<1,MixerFracOne>>;
    [[nodiscard]] auto currentInputDelay() const noexcept -> SampleOffset
    {
        const int64_t prep{int64_t{mSrcPrepCount} - MaxResamplerEdge};
        return SampleOffset{(prep<<MixerFracBits) + mFracOffset};
    }

    static std::unique_ptr<SampleConverter> Create(DevFmtType srcType, DevFmtType dstType,
        size_t numchans, uint srcRate, uint dstRate, Resampler resampler);

    DEF_FAM_NEWDEL(SampleConverter, mChan)
};
using SampleConverterPtr = std::unique_ptr<SampleConverter>;

struct ChannelConverter {
    DevFmtType mSrcType{};
    uint mSrcStep{};
    uint mChanMask{};
    DevFmtChannels mDstChans{};

    [[nodiscard]] auto is_active() const noexcept -> bool { return mChanMask != 0; }

    void convert(const void *src, float *dst, uint frames) const;
};

#endif /* CORE_CONVERTER_H */
