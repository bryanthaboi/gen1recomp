
#include "config.h"
#include "config_simd.h"

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <complex>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <vector>

#if HAVE_SSE_INTRINSICS
#include <xmmintrin.h>
#elif HAVE_NEON
#include <arm_neon.h>
#endif

#include "alcomplex.h"
#include "almalloc.h"
#include "alnumbers.h"
#include "alnumeric.h"
#include "alspan.h"
#include "base.h"
#include "core/ambidefs.h"
#include "core/bufferline.h"
#include "core/buffer_storage.h"
#include "core/context.h"
#include "core/devformat.h"
#include "core/device.h"
#include "core/effects/base.h"
#include "core/effectslot.h"
#include "core/filters/splitter.h"
#include "core/fmt_traits.h"
#include "core/mixer.h"
#include "core/uhjfilter.h"
#include "intrusive_ptr.h"
#include "opthelpers.h"
#include "pffft.h"
#include "polyphase_resampler.h"
#include "vecmat.h"
#include "vector.h"


namespace {

/* Convolution is implemented using a segmented overlap-add method. The impulse
 * response is split into multiple segments of 128 samples, and each segment
 * has an FFT applied with a 256-sample buffer (the latter half left silent) to
 * get its frequency-domain response. The resulting response has its positive/
 * non-mirrored frequencies saved (129 bins) in each segment. Note that since
 * the 0- and half-frequency bins are real for a real signal, their imaginary
 * components are always 0 and can be dropped, allowing their real components
 * to be combined so only 128 complex values are stored for the 129 bins.
 *
 * Input samples are similarly broken up into 128-sample segments, with a 256-
 * sample FFT applied to each new incoming segment to get its 129 bins. A
 * history of FFT'd input segments is maintained, equal to the number of
 * impulse response segments.
 *
 * To apply the convolution, each impulse response segment is convolved with
 * its paired input segment (using complex multiplies, far cheaper than FIRs),
 * accumulating into a 129-bin FFT buffer. The input history is then shifted to
 * align with later impulse response segments for the next input segment.
 *
 * An inverse FFT is then applied to the accumulated FFT buffer to get a 256-
 * sample time-domain response for output, which is split in two halves. The
 * first half is the 128-sample output, and the second half is a 128-sample
 * (really, 127) delayed extension, which gets added to the output next time.
 * Convolving two time-domain responses of length N results in a time-domain
 * signal of length N*2 - 1, and this holds true regardless of the convolution
 * being applied in the frequency domain, so these "overflow" samples need to
 * be accounted for.
 *
 * To avoid a delay with gathering enough input samples for the FFT, the first
 * segment is applied directly in the time-domain as the samples come in. Once
 * enough have been retrieved, the FFT is applied on the input and it's paired
 * with the remaining (FFT'd) filter segments for processing.
 */


template<FmtType SrcType>
inline void LoadSampleArray(const al::span<float> dst, const std::byte *src,
    const std::size_t channel, const std::size_t srcstep) noexcept
{
    using TypeTraits = al::FmtTypeTraits<SrcType>;
    using SampleType = typename TypeTraits::Type;
    const auto converter = TypeTraits{};
    assert(channel < srcstep);

    const auto srcspan = al::span{reinterpret_cast<const SampleType*>(src), dst.size()*srcstep};
    auto ssrc = srcspan.cbegin();
    std::generate(dst.begin(), dst.end(), [converter,channel,srcstep,&ssrc]
    {
        const auto ret = converter(ssrc[channel]);
        ssrc += ptrdiff_t(srcstep);
        return ret;
    });
}

void LoadSamples(const al::span<float> dst, const std::byte *src, const size_t channel,
    const size_t srcstep, const FmtType srctype) noexcept
{
#define HANDLE_FMT(T)  case T: LoadSampleArray<T>(dst, src, channel, srcstep); break
    switch(srctype)
    {
    HANDLE_FMT(FmtUByte);
    HANDLE_FMT(FmtShort);
    HANDLE_FMT(FmtInt);
    HANDLE_FMT(FmtFloat);
    HANDLE_FMT(FmtDouble);
    HANDLE_FMT(FmtMulaw);
    HANDLE_FMT(FmtAlaw);
    /* FIXME: Handle ADPCM decoding here. */
    case FmtIMA4:
    case FmtMSADPCM:
        std::fill(dst.begin(), dst.end(), 0.0f);
        break;
    }
#undef HANDLE_FMT
}


constexpr auto GetAmbiScales(AmbiScaling scaletype) noexcept
{
    switch(scaletype)
    {
    case AmbiScaling::FuMa: return al::span{AmbiScale::FromFuMa};
    case AmbiScaling::SN3D: return al::span{AmbiScale::FromSN3D};
    case AmbiScaling::UHJ: return al::span{AmbiScale::FromUHJ};
    case AmbiScaling::N3D: break;
    }
    return al::span{AmbiScale::FromN3D};
}

constexpr auto GetAmbiLayout(AmbiLayout layouttype) noexcept
{
    if(layouttype == AmbiLayout::FuMa) return al::span{AmbiIndex::FromFuMa};
    return al::span{AmbiIndex::FromACN};
}

constexpr auto GetAmbi2DLayout(AmbiLayout layouttype) noexcept
{
    if(layouttype == AmbiLayout::FuMa) return al::span{AmbiIndex::FromFuMa2D};
    return al::span{AmbiIndex::FromACN2D};
}


constexpr float sin30{0.5f};
constexpr float cos30{0.866025403785f};
constexpr float sin45{al::numbers::sqrt2_v<float>*0.5f};
constexpr float cos45{al::numbers::sqrt2_v<float>*0.5f};
constexpr float sin110{ 0.939692620786f};
constexpr float cos110{-0.342020143326f};

struct ChanPosMap {
    Channel channel;
    std::array<float,3> pos;
};


using complex_f = std::complex<float>;

constexpr size_t ConvolveUpdateSize{256};
constexpr size_t ConvolveUpdateSamples{ConvolveUpdateSize / 2};


void apply_fir(al::span<float> dst, const al::span<const float> input, const al::span<const float,ConvolveUpdateSamples> filter)
{
    auto src = input.begin();
#if HAVE_SSE_INTRINSICS
    std::generate(dst.begin(), dst.end(), [&src,filter]
    {
        __m128 r4{_mm_setzero_ps()};
        for(size_t j{0};j < ConvolveUpdateSamples;j+=4)
        {
            const __m128 coeffs{_mm_load_ps(&filter[j])};
            const __m128 s{_mm_loadu_ps(&src[j])};

            r4 = _mm_add_ps(r4, _mm_mul_ps(s, coeffs));
        }
        ++src;

        r4 = _mm_add_ps(r4, _mm_shuffle_ps(r4, r4, _MM_SHUFFLE(0, 1, 2, 3)));
        r4 = _mm_add_ps(r4, _mm_movehl_ps(r4, r4));
        return _mm_cvtss_f32(r4);
    });

#elif HAVE_NEON

    std::generate(dst.begin(), dst.end(), [&src,filter]
    {
        float32x4_t r4{vdupq_n_f32(0.0f)};
        for(size_t j{0};j < ConvolveUpdateSamples;j+=4)
            r4 = vmlaq_f32(r4, vld1q_f32(&src[j]), vld1q_f32(&filter[j]));
        ++src;

        r4 = vaddq_f32(r4, vrev64q_f32(r4));
        return vget_lane_f32(vadd_f32(vget_low_f32(r4), vget_high_f32(r4)), 0);
    });

#else

    std::generate(dst.begin(), dst.end(), [&src,filter]
    {
        float ret{0.0f};
        for(size_t j{0};j < ConvolveUpdateSamples;++j)
            ret += src[j] * filter[j];
        ++src;
        return ret;
    });
#endif
}


struct ConvolutionState final : public EffectState {
    FmtChannels mChannels{};
    AmbiLayout mAmbiLayout{};
    AmbiScaling mAmbiScaling{};
    uint mAmbiOrder{};

    size_t mFifoPos{0};
    alignas(16) std::array<float,ConvolveUpdateSamples*2> mInput{};
    al::vector<std::array<float,ConvolveUpdateSamples>,16> mFilter;
    al::vector<std::array<float,ConvolveUpdateSamples*2>,16> mOutput;

    PFFFTSetup mFft{};
    alignas(16) std::array<float,ConvolveUpdateSize> mFftBuffer{};
    alignas(16) std::array<float,ConvolveUpdateSize> mFftWorkBuffer{};

    size_t mCurrentSegment{0};
    size_t mNumConvolveSegs{0};

    struct ChannelData {
        alignas(16) FloatBufferLine mBuffer{};
        float mHfScale{}, mLfScale{};
        BandSplitter mFilter{};
        std::array<float,MaxOutputChannels> Current{};
        std::array<float,MaxOutputChannels> Target{};
    };
    std::vector<ChannelData> mChans;
    al::vector<float,16> mComplexData;


    ConvolutionState() = default;
    ~ConvolutionState() override = default;

    void NormalMix(const al::span<FloatBufferLine> samplesOut, const size_t samplesToDo);
    void UpsampleMix(const al::span<FloatBufferLine> samplesOut, const size_t samplesToDo);
    void (ConvolutionState::*mMix)(const al::span<FloatBufferLine>,const size_t)
    {&ConvolutionState::NormalMix};

    void deviceUpdate(const DeviceBase *device, const BufferStorage *buffer) override;
    void update(const ContextBase *context, const EffectSlot *slot, const EffectProps *props,
        const EffectTarget target) override;
    void process(const size_t samplesToDo, const al::span<const FloatBufferLine> samplesIn,
        const al::span<FloatBufferLine> samplesOut) override;
};

void ConvolutionState::NormalMix(const al::span<FloatBufferLine> samplesOut,
    const size_t samplesToDo)
{
    for(auto &chan : mChans)
        MixSamples(al::span{chan.mBuffer}.first(samplesToDo), samplesOut, chan.Current,
            chan.Target, samplesToDo, 0);
}

void ConvolutionState::UpsampleMix(const al::span<FloatBufferLine> samplesOut,
    const size_t samplesToDo)
{
    for(auto &chan : mChans)
    {
        const auto src = al::span{chan.mBuffer}.first(samplesToDo);
        chan.mFilter.processScale(src, chan.mHfScale, chan.mLfScale);
        MixSamples(src, samplesOut, chan.Current, chan.Target, samplesToDo, 0);
    }
}


void ConvolutionState::deviceUpdate(const DeviceBase *device, const BufferStorage *buffer)
{
    using UhjDecoderType = UhjDecoder<512>;
    static constexpr auto DecoderPadding = UhjDecoderType::sInputPadding;

    static constexpr uint MaxConvolveAmbiOrder{1u};

    if(!mFft)
        mFft = PFFFTSetup{ConvolveUpdateSize, PFFFT_REAL};

    mFifoPos = 0;
    mInput.fill(0.0f);
    decltype(mFilter){}.swap(mFilter);
    decltype(mOutput){}.swap(mOutput);
    mFftBuffer.fill(0.0f);
    mFftWorkBuffer.fill(0.0f);

    mCurrentSegment = 0;
    mNumConvolveSegs = 0;

    decltype(mChans){}.swap(mChans);
    decltype(mComplexData){}.swap(mComplexData);

    /* An empty buffer doesn't need a convolution filter. */
    if(!buffer || buffer->mSampleLen < 1) return;

    mChannels = buffer->mChannels;
    mAmbiLayout = IsUHJ(mChannels) ? AmbiLayout::FuMa : buffer->mAmbiLayout;
    mAmbiScaling = IsUHJ(mChannels) ? AmbiScaling::UHJ : buffer->mAmbiScaling;
    mAmbiOrder = std::min(buffer->mAmbiOrder, MaxConvolveAmbiOrder);

    const auto realChannels = buffer->channelsFromFmt();
    const auto numChannels = (mChannels == FmtUHJ2) ? 3u : ChannelsFromFmt(mChannels, mAmbiOrder);

    mChans.resize(numChannels);

    /* The impulse response needs to have the same sample rate as the input and
     * output. The bsinc24 resampler is decent, but there is high-frequency
     * attenuation that some people may be able to pick up on. Since this is
     * called very infrequently, go ahead and use the polyphase resampler.
     */
    PPhaseResampler resampler;
    if(device->Frequency != buffer->mSampleRate)
        resampler.init(buffer->mSampleRate, device->Frequency);
    const auto resampledCount = static_cast<uint>(
        (uint64_t{buffer->mSampleLen}*device->Frequency+(buffer->mSampleRate-1)) /
        buffer->mSampleRate);

    const BandSplitter splitter{device->mXOverFreq / static_cast<float>(device->Frequency)};
    for(auto &e : mChans)
        e.mFilter = splitter;

    mFilter.resize(numChannels, {});
    mOutput.resize(numChannels, {});

    /* Calculate the number of segments needed to hold the impulse response and
     * the input history (rounded up), and allocate them. Exclude one segment
     * which gets applied as a time-domain FIR filter. Make sure at least one
     * segment is allocated to simplify handling.
     */
    mNumConvolveSegs = (resampledCount+(ConvolveUpdateSamples-1)) / ConvolveUpdateSamples;
    mNumConvolveSegs = std::max(mNumConvolveSegs, 2_uz) - 1_uz;

    const size_t complex_length{mNumConvolveSegs * ConvolveUpdateSize * (numChannels+1)};
    mComplexData.resize(complex_length, 0.0f);

    /* Load the samples from the buffer. */
    const size_t srclinelength{RoundUp(buffer->mSampleLen+DecoderPadding, 16)};
    auto srcsamples = std::vector<float>(srclinelength * numChannels);
    std::fill(srcsamples.begin(), srcsamples.end(), 0.0f);
    for(size_t c{0};c < numChannels && c < realChannels;++c)
        LoadSamples(al::span{srcsamples}.subspan(srclinelength*c, buffer->mSampleLen),
            buffer->mData.data(), c, realChannels, buffer->mType);

    if(IsUHJ(mChannels))
    {
        auto decoder = std::make_unique<UhjDecoderType>();
        std::array<float*,4> samples{};
        for(size_t c{0};c < numChannels;++c)
            samples[c] = al::to_address(srcsamples.begin() + ptrdiff_t(srclinelength*c));
        decoder->decode({samples.data(), numChannels}, buffer->mSampleLen, buffer->mSampleLen);
    }

    auto ressamples = std::vector<double>(buffer->mSampleLen + (resampler ? resampledCount : 0));
    auto ffttmp = al::vector<float,16>(ConvolveUpdateSize);
    auto fftbuffer = std::vector<std::complex<double>>(ConvolveUpdateSize);

    auto filteriter = mComplexData.begin() + ptrdiff_t(mNumConvolveSegs*ConvolveUpdateSize);
    for(size_t c{0};c < numChannels;++c)
    {
        auto bufsamples = al::span{srcsamples}.subspan(srclinelength*c, buffer->mSampleLen);
        /* Resample to match the device. */
        if(resampler)
        {
            auto restmp = al::span{ressamples}.subspan(resampledCount, buffer->mSampleLen);
            std::copy(bufsamples.cbegin(), bufsamples.cend(), restmp.begin());
            resampler.process(restmp, al::span{ressamples}.first(resampledCount));
        }
        else
            std::copy(bufsamples.cbegin(), bufsamples.cend(), ressamples.begin());

        /* Store the first segment's samples in reverse in the time-domain, to
         * apply as a FIR filter.
         */
        const size_t first_size{std::min(size_t{resampledCount}, ConvolveUpdateSamples)};
        auto sampleseg = al::span{ressamples.cbegin(), first_size};
        std::transform(sampleseg.cbegin(), sampleseg.cend(), mFilter[c].rbegin(),
            [](const double d) noexcept -> float { return static_cast<float>(d); });

        size_t done{first_size};
        for(size_t s{0};s < mNumConvolveSegs;++s)
        {
            const size_t todo{std::min(resampledCount-done, ConvolveUpdateSamples)};
            sampleseg = al::span{ressamples}.subspan(done, todo);

            /* Apply a double-precision forward FFT for more precise frequency
             * measurements.
             */
            auto iter = std::copy(sampleseg.cbegin(), sampleseg.cend(), fftbuffer.begin());
            done += todo;
            std::fill(iter, fftbuffer.end(), std::complex<double>{});
            forward_fft(al::span{fftbuffer});

            /* Convert to, and pack in, a float buffer for PFFFT. Note that the
             * first bin stores the real component of the half-frequency bin in
             * the imaginary component. Also scale the FFT by its length so the
             * iFFT'd output will be normalized.
             */
            static constexpr float fftscale{1.0f / float{ConvolveUpdateSize}};
            for(size_t i{0};i < ConvolveUpdateSamples;++i)
            {
                ffttmp[i*2    ] = static_cast<float>(fftbuffer[i].real()) * fftscale;
                ffttmp[i*2 + 1] = static_cast<float>((i == 0) ?
                    fftbuffer[ConvolveUpdateSamples].real() : fftbuffer[i].imag()) * fftscale;
            }
            /* Reorder backward to make it suitable for pffft_zconvolve and the
             * subsequent pffft_transform(..., PFFFT_BACKWARD).
             */
            mFft.zreorder(ffttmp.data(), al::to_address(filteriter), PFFFT_BACKWARD);
            filteriter += ConvolveUpdateSize;
        }
    }
}


void ConvolutionState::update(const ContextBase *context, const EffectSlot *slot,
    const EffectProps *props_, const EffectTarget target)
{
    /* TODO: LFE is not mixed to output. This will require each buffer channel
     * to have its own output target since the main mixing buffer won't have an
     * LFE channel (due to being B-Format).
     */
    static constexpr std::array MonoMap{
        ChanPosMap{FrontCenter, std::array{0.0f, 0.0f, -1.0f}}
    };
    static constexpr std::array StereoMap{
        ChanPosMap{FrontLeft,  std::array{-sin30, 0.0f, -cos30}},
        ChanPosMap{FrontRight, std::array{ sin30, 0.0f, -cos30}},
    };
    static constexpr std::array RearMap{
        ChanPosMap{BackLeft,  std::array{-sin30, 0.0f, cos30}},
        ChanPosMap{BackRight, std::array{ sin30, 0.0f, cos30}},
    };
    static constexpr std::array QuadMap{
        ChanPosMap{FrontLeft,  std::array{-sin45, 0.0f, -cos45}},
        ChanPosMap{FrontRight, std::array{ sin45, 0.0f, -cos45}},
        ChanPosMap{BackLeft,   std::array{-sin45, 0.0f,  cos45}},
        ChanPosMap{BackRight,  std::array{ sin45, 0.0f,  cos45}},
    };
    static constexpr std::array X51Map{
        ChanPosMap{FrontLeft,   std::array{-sin30, 0.0f, -cos30}},
        ChanPosMap{FrontRight,  std::array{ sin30, 0.0f, -cos30}},
        ChanPosMap{FrontCenter, std::array{  0.0f, 0.0f,  -1.0f}},
        ChanPosMap{LFE, {}},
        ChanPosMap{SideLeft,    std::array{-sin110, 0.0f, -cos110}},
        ChanPosMap{SideRight,   std::array{ sin110, 0.0f, -cos110}},
    };
    static constexpr std::array X61Map{
        ChanPosMap{FrontLeft,   std::array{-sin30, 0.0f, -cos30}},
        ChanPosMap{FrontRight,  std::array{ sin30, 0.0f, -cos30}},
        ChanPosMap{FrontCenter, std::array{  0.0f, 0.0f,  -1.0f}},
        ChanPosMap{LFE, {}},
        ChanPosMap{BackCenter,  std::array{ 0.0f, 0.0f, 1.0f} },
        ChanPosMap{SideLeft,    std::array{-1.0f, 0.0f, 0.0f} },
        ChanPosMap{SideRight,   std::array{ 1.0f, 0.0f, 0.0f} },
    };
    static constexpr std::array X71Map{
        ChanPosMap{FrontLeft,   std::array{-sin30, 0.0f, -cos30}},
        ChanPosMap{FrontRight,  std::array{ sin30, 0.0f, -cos30}},
        ChanPosMap{FrontCenter, std::array{  0.0f, 0.0f,  -1.0f}},
        ChanPosMap{LFE, {}},
        ChanPosMap{BackLeft,    std::array{-sin30, 0.0f, cos30}},
        ChanPosMap{BackRight,   std::array{ sin30, 0.0f, cos30}},
        ChanPosMap{SideLeft,    std::array{ -1.0f, 0.0f,  0.0f}},
        ChanPosMap{SideRight,   std::array{  1.0f, 0.0f,  0.0f}},
    };

    if(mNumConvolveSegs < 1) UNLIKELY
        return;

    auto &props = std::get<ConvolutionProps>(*props_);
    mMix = &ConvolutionState::NormalMix;

    for(auto &chan : mChans)
        std::fill(chan.Target.begin(), chan.Target.end(), 0.0f);
    const float gain{slot->Gain};
    if(IsAmbisonic(mChannels))
    {
        DeviceBase *device{context->mDevice};
        if(mChannels == FmtUHJ2 && !device->mUhjEncoder)
        {
            mMix = &ConvolutionState::UpsampleMix;
            mChans[0].mHfScale = 1.0f;
            mChans[0].mLfScale = DecoderBase::sWLFScale;
            mChans[1].mHfScale = 1.0f;
            mChans[1].mLfScale = DecoderBase::sXYLFScale;
            mChans[2].mHfScale = 1.0f;
            mChans[2].mLfScale = DecoderBase::sXYLFScale;
        }
        else if(device->mAmbiOrder > mAmbiOrder)
        {
            mMix = &ConvolutionState::UpsampleMix;
            const auto scales = AmbiScale::GetHFOrderScales(mAmbiOrder, device->mAmbiOrder,
                device->m2DMixing);
            mChans[0].mHfScale = scales[0];
            mChans[0].mLfScale = 1.0f;
            for(size_t i{1};i < mChans.size();++i)
            {
                mChans[i].mHfScale = scales[1];
                mChans[i].mLfScale = 1.0f;
            }
        }
        mOutTarget = target.Main->Buffer;

        alu::Vector N{props.OrientAt[0], props.OrientAt[1], props.OrientAt[2], 0.0f};
        N.normalize();
        alu::Vector V{props.OrientUp[0], props.OrientUp[1], props.OrientUp[2], 0.0f};
        V.normalize();
        /* Build and normalize right-vector */
        alu::Vector U{N.cross_product(V)};
        U.normalize();

        const std::array mixmatrix{
            std::array{1.0f,  0.0f,  0.0f,  0.0f},
            std::array{0.0f,  U[0], -U[1],  U[2]},
            std::array{0.0f, -V[0],  V[1], -V[2]},
            std::array{0.0f, -N[0],  N[1], -N[2]},
        };

        const auto scales = GetAmbiScales(mAmbiScaling);
        const auto index_map = Is2DAmbisonic(mChannels) ?
            al::span{GetAmbi2DLayout(mAmbiLayout)}.subspan(0) :
            al::span{GetAmbiLayout(mAmbiLayout)}.subspan(0);

        std::array<float,MaxAmbiChannels> coeffs{};
        for(size_t c{0u};c < mChans.size();++c)
        {
            const size_t acn{index_map[c]};
            const float scale{scales[acn]};

            std::transform(mixmatrix[acn].cbegin(), mixmatrix[acn].cend(), coeffs.begin(),
                [scale](const float in) noexcept -> float { return in * scale; });

            ComputePanGains(target.Main, coeffs, gain, mChans[c].Target);
        }
    }
    else
    {
        DeviceBase *device{context->mDevice};
        al::span<const ChanPosMap> chanmap{};
        switch(mChannels)
        {
        case FmtMono: chanmap = MonoMap; break;
        case FmtMonoDup: chanmap = MonoMap; break;
        case FmtSuperStereo:
        case FmtStereo: chanmap = StereoMap; break;
        case FmtRear: chanmap = RearMap; break;
        case FmtQuad: chanmap = QuadMap; break;
        case FmtX51: chanmap = X51Map; break;
        case FmtX61: chanmap = X61Map; break;
        case FmtX71: chanmap = X71Map; break;
        case FmtBFormat2D:
        case FmtBFormat3D:
        case FmtUHJ2:
        case FmtUHJ3:
        case FmtUHJ4:
            break;
        }

        mOutTarget = target.Main->Buffer;
        if(device->mRenderMode == RenderMode::Pairwise)
        {
            /* Scales the azimuth of the given vector by 3 if it's in front.
             * Effectively scales +/-30 degrees to +/-90 degrees, leaving > +90
             * and < -90 alone.
             */
            auto ScaleAzimuthFront = [](std::array<float,3> pos) -> std::array<float,3>
            {
                if(pos[2] < 0.0f)
                {
                    /* Normalize the length of the x,z components for a 2D
                     * vector of the azimuth angle. Negate Z since {0,0,-1} is
                     * angle 0.
                     */
                    const float len2d{std::sqrt(pos[0]*pos[0] + pos[2]*pos[2])};
                    float x{pos[0] / len2d};
                    float z{-pos[2] / len2d};

                    /* Z > cos(pi/6) = -30 < azimuth < 30 degrees. */
                    if(z > cos30)
                    {
                        /* Triple the angle represented by x,z. */
                        x = x*3.0f - x*x*x*4.0f;
                        z = z*z*z*4.0f - z*3.0f;

                        /* Scale the vector back to fit in 3D. */
                        pos[0] = x * len2d;
                        pos[2] = -z * len2d;
                    }
                    else
                    {
                        /* If azimuth >= 30 degrees, clamp to 90 degrees. */
                        pos[0] = std::copysign(len2d, pos[0]);
                        pos[2] = 0.0f;
                    }
                }
                return pos;
            };

            for(size_t i{0};i < chanmap.size();++i)
            {
                if(chanmap[i].channel == LFE) continue;
                const auto coeffs = CalcDirectionCoeffs(ScaleAzimuthFront(chanmap[i].pos), 0.0f);
                ComputePanGains(target.Main, coeffs, gain, mChans[i].Target);
            }
        }
        else for(size_t i{0};i < chanmap.size();++i)
        {
            if(chanmap[i].channel == LFE) continue;
            const auto coeffs = CalcDirectionCoeffs(chanmap[i].pos, 0.0f);
            ComputePanGains(target.Main, coeffs, gain, mChans[i].Target);
        }
    }
}

void ConvolutionState::process(const size_t samplesToDo,
    const al::span<const FloatBufferLine> samplesIn, const al::span<FloatBufferLine> samplesOut)
{
    if(mNumConvolveSegs < 1) UNLIKELY
        return;

    size_t curseg{mCurrentSegment};

    for(size_t base{0u};base < samplesToDo;)
    {
        const size_t todo{std::min(ConvolveUpdateSamples-mFifoPos, samplesToDo-base)};

        std::copy_n(samplesIn[0].begin() + ptrdiff_t(base), todo,
            mInput.begin()+ptrdiff_t(ConvolveUpdateSamples+mFifoPos));

        /* Apply the FIR for the newly retrieved input samples, and combine it
         * with the inverse FFT'd output samples.
         */
        for(size_t c{0};c < mChans.size();++c)
        {
            auto outspan = al::span{mChans[c].mBuffer}.subspan(base, todo);
            apply_fir(outspan, al::span{mInput}.subspan(1+mFifoPos), mFilter[c]);

            auto fifospan = al::span{mOutput[c]}.subspan(mFifoPos, todo);
            std::transform(fifospan.cbegin(), fifospan.cend(), outspan.cbegin(), outspan.begin(),
                std::plus{});
        }

        mFifoPos += todo;
        base += todo;

        /* Check whether the input buffer is filled with new samples. */
        if(mFifoPos < ConvolveUpdateSamples) break;
        mFifoPos = 0;

        /* Move the newest input to the front for the next iteration's history. */
        std::copy(mInput.cbegin()+ConvolveUpdateSamples, mInput.cend(), mInput.begin());
        std::fill(mInput.begin()+ConvolveUpdateSamples, mInput.end(), 0.0f);

        /* Calculate the frequency-domain response and add the relevant
         * frequency bins to the FFT history.
         */
        mFft.transform(mInput.data(), &mComplexData[curseg*ConvolveUpdateSize],
            mFftWorkBuffer.data(), PFFFT_FORWARD);

        auto filter = mComplexData.cbegin() + ptrdiff_t(mNumConvolveSegs*ConvolveUpdateSize);
        for(size_t c{0};c < mChans.size();++c)
        {
            /* Convolve each input segment with its IR filter counterpart
             * (aligned in time).
             */
            mFftBuffer.fill(0.0f);
            auto input = mComplexData.cbegin() + ptrdiff_t(curseg*ConvolveUpdateSize);
            for(size_t s{curseg};s < mNumConvolveSegs;++s)
            {
                mFft.zconvolve_accumulate(al::to_address(input), al::to_address(filter),
                    mFftBuffer.data());
                input += ConvolveUpdateSize;
                filter += ConvolveUpdateSize;
            }
            input = mComplexData.cbegin();
            for(size_t s{0};s < curseg;++s)
            {
                mFft.zconvolve_accumulate(al::to_address(input), al::to_address(filter),
                    mFftBuffer.data());
                input += ConvolveUpdateSize;
                filter += ConvolveUpdateSize;
            }

            /* Apply iFFT to get the 256 (really 255) samples for output. The
             * 128 output samples are combined with the last output's 127
             * second-half samples (and this output's second half is
             * subsequently saved for next time).
             */
            mFft.transform(mFftBuffer.data(), mFftBuffer.data(), mFftWorkBuffer.data(),
                PFFFT_BACKWARD);

            /* The filter was attenuated, so the response is already scaled. */
            std::transform(mFftBuffer.cbegin(), mFftBuffer.cbegin()+ConvolveUpdateSamples,
                mOutput[c].cbegin()+ConvolveUpdateSamples, mOutput[c].begin(), std::plus{});
            std::copy(mFftBuffer.cbegin()+ConvolveUpdateSamples, mFftBuffer.cend(),
                mOutput[c].begin()+ConvolveUpdateSamples);
        }

        /* Shift the input history. */
        curseg = curseg ? (curseg-1) : (mNumConvolveSegs-1);
    }
    mCurrentSegment = curseg;

    /* Finally, mix to the output. */
    (this->*mMix)(samplesOut, samplesToDo);
}


struct ConvolutionStateFactory final : public EffectStateFactory {
    al::intrusive_ptr<EffectState> create() override
    { return al::intrusive_ptr<EffectState>{new ConvolutionState{}}; }
};

} // namespace

EffectStateFactory *ConvolutionStateFactory_getFactory()
{
    static ConvolutionStateFactory ConvolutionFactory{};
    return &ConvolutionFactory;
}
