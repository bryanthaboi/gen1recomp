
#include "config.h"

#include "converter.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <climits>

#include "albit.h"
#include "alnumeric.h"
#include "fpu_ctrl.h"


namespace {

constexpr uint MaxPitch{10};

static_assert((BufferLineSize-1)/MaxPitch > 0, "MaxPitch is too large for BufferLineSize!");
static_assert((INT_MAX>>MixerFracBits)/MaxPitch > BufferLineSize,
    "MaxPitch and/or BufferLineSize are too large for MixerFracBits!");

template<DevFmtType T>
constexpr float LoadSample(DevFmtType_t<T> val) noexcept = delete;

template<> constexpr float LoadSample<DevFmtByte>(DevFmtType_t<DevFmtByte> val) noexcept
{ return float(val) * (1.0f/128.0f); }
template<> constexpr float LoadSample<DevFmtShort>(DevFmtType_t<DevFmtShort> val) noexcept
{ return float(val) * (1.0f/32768.0f); }
template<> constexpr float LoadSample<DevFmtInt>(DevFmtType_t<DevFmtInt> val) noexcept
{ return static_cast<float>(val) * (1.0f/2147483648.0f); }
template<> constexpr float LoadSample<DevFmtFloat>(DevFmtType_t<DevFmtFloat> val) noexcept
{ return val; }

template<> constexpr float LoadSample<DevFmtUByte>(DevFmtType_t<DevFmtUByte> val) noexcept
{ return LoadSample<DevFmtByte>(static_cast<int8_t>(val - 128)); }
template<> constexpr float LoadSample<DevFmtUShort>(DevFmtType_t<DevFmtUShort> val) noexcept
{ return LoadSample<DevFmtShort>(static_cast<int16_t>(val - 32768)); }
template<> constexpr float LoadSample<DevFmtUInt>(DevFmtType_t<DevFmtUInt> val) noexcept
{ return LoadSample<DevFmtInt>(static_cast<int32_t>(val - 2147483648u)); }


template<DevFmtType T>
inline void LoadSampleArray(const al::span<float> dst, const void *src, const size_t channel,
    const size_t srcstep) noexcept
{
    assert(channel < srcstep);
    const auto srcspan = al::span{static_cast<const DevFmtType_t<T>*>(src), dst.size()*srcstep};
    auto ssrc = srcspan.cbegin();
    std::generate(dst.begin(), dst.end(), [&ssrc,channel,srcstep]
    {
        const float ret{LoadSample<T>(ssrc[channel])};
        ssrc += ptrdiff_t(srcstep);
        return ret;
    });
}

void LoadSamples(const al::span<float> dst, const void *src, const size_t channel,
    const size_t srcstep, const DevFmtType srctype) noexcept
{
#define HANDLE_FMT(T)                                                         \
    case T: LoadSampleArray<T>(dst, src, channel, srcstep); break
    switch(srctype)
    {
        HANDLE_FMT(DevFmtByte);
        HANDLE_FMT(DevFmtUByte);
        HANDLE_FMT(DevFmtShort);
        HANDLE_FMT(DevFmtUShort);
        HANDLE_FMT(DevFmtInt);
        HANDLE_FMT(DevFmtUInt);
        HANDLE_FMT(DevFmtFloat);
    }
#undef HANDLE_FMT
}


template<DevFmtType T>
inline DevFmtType_t<T> StoreSample(float) noexcept;

template<> inline float StoreSample<DevFmtFloat>(float val) noexcept
{ return val; }
template<> inline int32_t StoreSample<DevFmtInt>(float val) noexcept
{ return fastf2i(std::clamp(val*2147483648.0f, -2147483648.0f, 2147483520.0f)); }
template<> inline int16_t StoreSample<DevFmtShort>(float val) noexcept
{ return static_cast<int16_t>(fastf2i(std::clamp(val*32768.0f, -32768.0f, 32767.0f))); }
template<> inline int8_t StoreSample<DevFmtByte>(float val) noexcept
{ return static_cast<int8_t>(fastf2i(std::clamp(val*128.0f, -128.0f, 127.0f))); }

/* Define unsigned output variations. */
template<> inline uint32_t StoreSample<DevFmtUInt>(float val) noexcept
{ return static_cast<uint32_t>(StoreSample<DevFmtInt>(val)) + 2147483648u; }
template<> inline uint16_t StoreSample<DevFmtUShort>(float val) noexcept
{ return static_cast<uint16_t>(StoreSample<DevFmtShort>(val) + 32768); }
template<> inline uint8_t StoreSample<DevFmtUByte>(float val) noexcept
{ return static_cast<uint8_t>(StoreSample<DevFmtByte>(val) + 128); }

template<DevFmtType T>
inline void StoreSampleArray(void *dst, const al::span<const float> src, const size_t channel,
    const size_t dststep) noexcept
{
    assert(channel < dststep);
    const auto dstspan = al::span{static_cast<DevFmtType_t<T>*>(dst), src.size()*dststep};
    auto sdst = dstspan.begin();
    std::for_each(src.cbegin(), src.cend(), [&sdst,channel,dststep](const float in)
    {
        sdst[channel] = StoreSample<T>(in);
        sdst += ptrdiff_t(dststep);
    });
}


void StoreSamples(void *dst, const al::span<const float> src, const size_t channel,
    const size_t dststep, const DevFmtType dsttype) noexcept
{
#define HANDLE_FMT(T)                                                         \
    case T: StoreSampleArray<T>(dst, src, channel, dststep); break
    switch(dsttype)
    {
        HANDLE_FMT(DevFmtByte);
        HANDLE_FMT(DevFmtUByte);
        HANDLE_FMT(DevFmtShort);
        HANDLE_FMT(DevFmtUShort);
        HANDLE_FMT(DevFmtInt);
        HANDLE_FMT(DevFmtUInt);
        HANDLE_FMT(DevFmtFloat);
    }
#undef HANDLE_FMT
}


template<DevFmtType T>
void Mono2Stereo(const al::span<float> dst, const void *src) noexcept
{
    const auto srcspan = al::span{static_cast<const DevFmtType_t<T>*>(src), dst.size()>>1};
    auto sdst = dst.begin();
    std::for_each(srcspan.cbegin(), srcspan.cend(), [&sdst](const auto in)
    { sdst = std::fill_n(sdst, 2, LoadSample<T>(in)*0.707106781187f); });
}

template<DevFmtType T>
void Multi2Mono(uint chanmask, const size_t step, const float scale, const al::span<float> dst,
    const void *src) noexcept
{
    const auto srcspan = al::span{static_cast<const DevFmtType_t<T>*>(src), step*dst.size()};
    std::fill_n(dst.begin(), dst.size(), 0.0f);
    for(size_t c{0};chanmask;++c)
    {
        if((chanmask&1)) LIKELY
        {
            auto ssrc = srcspan.cbegin();
            std::for_each(dst.begin(), dst.end(), [&ssrc,step,c](float &sample)
            {
                const float s{LoadSample<T>(ssrc[c])};
                ssrc += ptrdiff_t(step);
                sample += s;
            });
        }
        chanmask >>= 1;
    }
    std::for_each(dst.begin(), dst.end(), [scale](float &sample) noexcept { sample *= scale; });
}

} // namespace

SampleConverterPtr SampleConverter::Create(DevFmtType srcType, DevFmtType dstType, size_t numchans,
    uint srcRate, uint dstRate, Resampler resampler)
{
    if(numchans < 1 || srcRate < 1 || dstRate < 1)
        return nullptr;

    SampleConverterPtr converter{new(FamCount(numchans)) SampleConverter{numchans}};
    converter->mSrcType = srcType;
    converter->mDstType = dstType;
    converter->mSrcTypeSize = BytesFromDevFmt(srcType);
    converter->mDstTypeSize = BytesFromDevFmt(dstType);

    converter->mSrcPrepCount = MaxResamplerPadding;
    converter->mFracOffset = 0;
    for(auto &chan : converter->mChan)
        chan.PrevSamples.fill(0.0f);

    /* Have to set the mixer FPU mode since that's what the resampler code expects. */
    FPUCtl mixer_mode{};
    const auto step = std::min(std::round(srcRate*double{MixerFracOne}/dstRate),
        MaxPitch*double{MixerFracOne});
    converter->mIncrement = std::max(static_cast<uint>(step), 1u);
    if(converter->mIncrement == MixerFracOne)
    {
        converter->mResample = [](const InterpState*, const al::span<const float> src, uint,
            const uint, const al::span<float> dst)
        { std::copy_n(src.begin()+MaxResamplerEdge, dst.size(), dst.begin()); };
    }
    else
        converter->mResample = PrepareResampler(resampler, converter->mIncrement,
            &converter->mState);

    return converter;
}

uint SampleConverter::availableOut(uint srcframes) const
{
    if(srcframes < 1)
    {
        /* No output samples if there's no input samples. */
        return 0;
    }

    const uint prepcount{mSrcPrepCount};
    if(prepcount < MaxResamplerPadding && MaxResamplerPadding - prepcount >= srcframes)
    {
        /* Not enough input samples to generate an output sample. */
        return 0;
    }

    uint64_t DataSize64{prepcount};
    DataSize64 += srcframes;
    DataSize64 -= MaxResamplerPadding;
    DataSize64 <<= MixerFracBits;
    DataSize64 -= mFracOffset;

    /* If we have a full prep, we can generate at least one sample. */
    return static_cast<uint>(std::clamp((DataSize64 + mIncrement-1)/mIncrement, 1_u64,
        uint64_t{std::numeric_limits<int>::max()}));
}

uint SampleConverter::convert(const void **src, uint *srcframes, void *dst, uint dstframes)
{
    const size_t SrcFrameSize{mChan.size() * mSrcTypeSize};
    const size_t DstFrameSize{mChan.size() * mDstTypeSize};
    const uint increment{mIncrement};
    uint NumSrcSamples{*srcframes};
    auto SamplesIn = al::span{static_cast<const std::byte*>(*src), NumSrcSamples*SrcFrameSize};
    auto SamplesOut = al::span{static_cast<std::byte*>(dst), dstframes*DstFrameSize};

    FPUCtl mixer_mode{};
    uint pos{0};
    while(pos < dstframes && NumSrcSamples > 0)
    {
        const uint prepcount{mSrcPrepCount};
        const uint readable{std::min(NumSrcSamples, uint{BufferLineSize} - prepcount)};

        if(prepcount < MaxResamplerPadding && MaxResamplerPadding-prepcount >= readable)
        {
            /* Not enough input samples to generate an output sample. Store
             * what we're given for later.
             */
            for(size_t chan{0u};chan < mChan.size();chan++)
                LoadSamples(al::span{mChan[chan].PrevSamples}.subspan(prepcount, readable),
                    SamplesIn.data(), chan, mChan.size(), mSrcType);

            mSrcPrepCount = prepcount + readable;
            NumSrcSamples = 0;
            break;
        }

        const auto SrcData = al::span<float>{mSrcSamples};
        const auto DstData = al::span<float>{mDstSamples};
        uint DataPosFrac{mFracOffset};
        uint64_t DataSize64{prepcount};
        DataSize64 += readable;
        DataSize64 -= MaxResamplerPadding;
        DataSize64 <<= MixerFracBits;
        DataSize64 -= DataPosFrac;

        /* If we have a full prep, we can generate at least one sample. */
        auto DstSize = static_cast<uint>(std::clamp((DataSize64 + increment-1)/increment, 1_u64,
            uint64_t{BufferLineSize}));
        DstSize = std::min(DstSize, dstframes-pos);

        const uint DataPosEnd{DstSize*increment + DataPosFrac};
        const uint SrcDataEnd{DataPosEnd>>MixerFracBits};

        assert(prepcount+readable >= SrcDataEnd);
        const uint nextprep{std::min(prepcount+readable-SrcDataEnd, MaxResamplerPadding)};

        for(size_t chan{0u};chan < mChan.size();chan++)
        {
            /* Load the previous samples into the source data first, then the
             * new samples from the input buffer.
             */
            std::copy_n(mChan[chan].PrevSamples.cbegin(), prepcount, SrcData.begin());
            LoadSamples(SrcData.subspan(prepcount, readable), SamplesIn.data(), chan, mChan.size(),
                mSrcType);

            /* Store as many prep samples for next time as possible, given the
             * number of output samples being generated.
             */
            auto previter = std::copy_n(SrcData.begin()+ptrdiff_t(SrcDataEnd), nextprep,
                mChan[chan].PrevSamples.begin());
            std::fill(previter, mChan[chan].PrevSamples.end(), 0.0f);

            /* Now resample, and store the result in the output buffer. */
            mResample(&mState, SrcData, DataPosFrac, increment, DstData.first(DstSize));

            StoreSamples(SamplesOut.data(), DstData.first(DstSize), chan, mChan.size(), mDstType);
        }

        /* Update the number of prep samples still available, as well as the
         * fractional offset.
         */
        mSrcPrepCount = nextprep;
        mFracOffset = DataPosEnd & MixerFracMask;

        /* Update the src and dst pointers in case there's still more to do. */
        const uint srcread{std::min(NumSrcSamples, SrcDataEnd + mSrcPrepCount - prepcount)};
        SamplesIn = SamplesIn.subspan(SrcFrameSize*srcread);
        NumSrcSamples -= srcread;

        SamplesOut = SamplesOut.subspan(DstFrameSize*DstSize);
        pos += DstSize;
    }

    *src = SamplesIn.data();
    *srcframes = NumSrcSamples;

    return pos;
}

uint SampleConverter::convertPlanar(const void **src, uint *srcframes, void *const*dst, uint dstframes)
{
    const auto srcs = al::span{src, mChan.size()};
    const auto dsts = al::span{dst, mChan.size()};
    const uint increment{mIncrement};
    uint NumSrcSamples{*srcframes};

    FPUCtl mixer_mode{};
    uint pos{0};
    while(pos < dstframes && NumSrcSamples > 0)
    {
        const uint prepcount{mSrcPrepCount};
        const uint readable{std::min(NumSrcSamples, uint{BufferLineSize} - prepcount)};

        if(prepcount < MaxResamplerPadding && MaxResamplerPadding-prepcount >= readable)
        {
            /* Not enough input samples to generate an output sample. Store
             * what we're given for later.
             */
            for(size_t chan{0u};chan < mChan.size();chan++)
            {
                auto samples = al::span{static_cast<const std::byte*>(srcs[chan]),
                    NumSrcSamples*size_t{mSrcTypeSize}};
                LoadSamples(al::span{mChan[chan].PrevSamples}.subspan(prepcount, readable),
                    samples.data(), 0, 1, mSrcType);
                srcs[chan] = samples.subspan(size_t{mSrcTypeSize}*readable).data();
            }

            mSrcPrepCount = prepcount + readable;
            NumSrcSamples = 0;
            break;
        }

        const auto SrcData = al::span{mSrcSamples};
        const auto DstData = al::span{mDstSamples};
        uint DataPosFrac{mFracOffset};
        uint64_t DataSize64{prepcount};
        DataSize64 += readable;
        DataSize64 -= MaxResamplerPadding;
        DataSize64 <<= MixerFracBits;
        DataSize64 -= DataPosFrac;

        /* If we have a full prep, we can generate at least one sample. */
        auto DstSize = static_cast<uint>(std::clamp((DataSize64 + increment-1)/increment, 1_u64,
            uint64_t{BufferLineSize}));
        DstSize = std::min(DstSize, dstframes-pos);

        const uint DataPosEnd{DstSize*increment + DataPosFrac};
        const uint SrcDataEnd{DataPosEnd>>MixerFracBits};

        assert(prepcount+readable >= SrcDataEnd);
        const uint nextprep{std::min(prepcount+readable-SrcDataEnd, MaxResamplerPadding)};

        for(size_t chan{0u};chan < mChan.size();chan++)
        {
            /* Load the previous samples into the source data first, then the
             * new samples from the input buffer.
             */
            auto srciter = std::copy_n(mChan[chan].PrevSamples.cbegin(),prepcount,SrcData.begin());
            LoadSamples({srciter, readable}, srcs[chan], 0, 1, mSrcType);

            /* Store as many prep samples for next time as possible, given the
             * number of output samples being generated.
             */
            auto previter = std::copy_n(SrcData.begin()+ptrdiff_t(SrcDataEnd), nextprep,
                mChan[chan].PrevSamples.begin());
            std::fill(previter, mChan[chan].PrevSamples.end(), 0.0f);

            /* Now resample, and store the result in the output buffer. */
            mResample(&mState, SrcData, DataPosFrac, increment, DstData.first(DstSize));

            auto DstSamples = al::span{static_cast<std::byte*>(dsts[chan]),
                size_t{mDstTypeSize}*dstframes}.subspan(pos*size_t{mDstTypeSize});
            StoreSamples(DstSamples.data(), DstData.first(DstSize), 0, 1, mDstType);
        }

        /* Update the number of prep samples still available, as well as the
         * fractional offset.
         */
        mSrcPrepCount = nextprep;
        mFracOffset = DataPosEnd & MixerFracMask;

        /* Update the src and dst pointers in case there's still more to do. */
        const uint srcread{std::min(NumSrcSamples, SrcDataEnd + mSrcPrepCount - prepcount)};
        std::for_each(srcs.begin(), srcs.end(), [this,NumSrcSamples,srcread](const void *&srcref)
        {
            auto srcspan = al::span{static_cast<const std::byte*>(srcref),
                size_t{mSrcTypeSize}*NumSrcSamples};
            srcref = srcspan.subspan(size_t{mSrcTypeSize}*srcread).data();
        });
        NumSrcSamples -= srcread;

        pos += DstSize;
    }

    *srcframes = NumSrcSamples;

    return pos;
}


void ChannelConverter::convert(const void *src, float *dst, uint frames) const
{
    if(mDstChans == DevFmtMono)
    {
        const float scale{std::sqrt(1.0f / static_cast<float>(al::popcount(mChanMask)))};
        switch(mSrcType)
        {
#define HANDLE_FMT(T) case T: Multi2Mono<T>(mChanMask, mSrcStep, scale, {dst, frames}, src); break
        HANDLE_FMT(DevFmtByte);
        HANDLE_FMT(DevFmtUByte);
        HANDLE_FMT(DevFmtShort);
        HANDLE_FMT(DevFmtUShort);
        HANDLE_FMT(DevFmtInt);
        HANDLE_FMT(DevFmtUInt);
        HANDLE_FMT(DevFmtFloat);
#undef HANDLE_FMT
        }
    }
    else if(mChanMask == 0x1 && mDstChans == DevFmtStereo)
    {
        switch(mSrcType)
        {
#define HANDLE_FMT(T) case T: Mono2Stereo<T>({dst, frames*2_uz}, src); break
        HANDLE_FMT(DevFmtByte);
        HANDLE_FMT(DevFmtUByte);
        HANDLE_FMT(DevFmtShort);
        HANDLE_FMT(DevFmtUShort);
        HANDLE_FMT(DevFmtInt);
        HANDLE_FMT(DevFmtUInt);
        HANDLE_FMT(DevFmtFloat);
#undef HANDLE_FMT
        }
    }
}
