
#include "config.h"

#include "uhjfilter.h"

#include <algorithm>
#include <cmath>
#include <complex>
#include <functional>
#include <vector>

#include "alcomplex.h"
#include "almalloc.h"
#include "alnumbers.h"
#include "core/bufferline.h"
#include "opthelpers.h"
#include "pffft.h"
#include "phase_shifter.h"
#include "vector.h"


namespace {

template<std::size_t A, typename T, std::size_t N>
constexpr auto assume_aligned_span(const al::span<T,N> s) noexcept -> al::span<T,N>
{ return al::span<T,N>{al::assume_aligned<A>(s.data()), s.size()}; }

/* Convolution is implemented using a segmented overlap-add method. The filter
 * response is broken up into multiple segments of 128 samples, and each
 * segment has an FFT applied with a 256-sample buffer (the latter half left
 * silent) to get its frequency-domain response.
 *
 * Input samples are similarly broken up into 128-sample segments, with a 256-
 * sample FFT applied to each new incoming segment to get its frequency-domain
 * response. A history of FFT'd input segments is maintained, equal to the
 * number of filter response segments.
 *
 * To apply the convolution, each filter response segment is convolved with its
 * paired input segment (using complex multiplies, far cheaper than time-domain
 * FIRs), accumulating into an FFT buffer. The input history is then shifted to
 * align with later filter response segments for the next input segment.
 *
 * An inverse FFT is then applied to the accumulated FFT buffer to get a 256-
 * sample time-domain response for output, which is split in two halves. The
 * first half is the 128-sample output, and the second half is a 128-sample
 * (really, 127) delayed extension, which gets added to the output next time.
 * Convolving two time-domain responses of length N results in a time-domain
 * signal of length N*2 - 1, and this holds true regardless of the convolution
 * being applied in the frequency domain, so these "overflow" samples need to
 * be accounted for.
 */
template<size_t N>
struct SegmentedFilter {
    static constexpr size_t sFftLength{256};
    static constexpr size_t sSampleLength{sFftLength / 2};
    static constexpr size_t sNumSegments{N/sSampleLength};
    static_assert(N >= sFftLength);
    static_assert((N % sSampleLength) == 0);

    PFFFTSetup mFft;
    alignas(16) std::array<float,sFftLength*sNumSegments> mFilterData;

    SegmentedFilter() : mFft{sFftLength, PFFFT_REAL}
    {
        static constexpr size_t fft_size{N};

        /* To set up the filter, we first need to generate the desired
         * response (not reversed).
         */
        auto tmpBuffer = std::vector<double>(fft_size, 0.0);
        for(std::size_t i{0};i < fft_size/2;++i)
        {
            const int k{int{fft_size/2} - static_cast<int>(i*2 + 1)};

            const double w{2.0*al::numbers::pi * static_cast<double>(i*2 + 1)
                / double{fft_size}};
            const double window{0.3635819 - 0.4891775*std::cos(w) + 0.1365995*std::cos(2.0*w)
                - 0.0106411*std::cos(3.0*w)};

            const double pk{al::numbers::pi * static_cast<double>(k)};
            tmpBuffer[i*2 + 1] = window * (1.0-std::cos(pk)) / pk;
        }

        /* The segments of the filter are converted back to the frequency
         * domain, each on their own (0 stuffed).
         */
        using complex_d = std::complex<double>;
        auto fftBuffer = std::vector<complex_d>(sFftLength);
        auto fftTmp = al::vector<float,16>(sFftLength);
        auto filter = mFilterData.begin();
        for(size_t s{0};s < sNumSegments;++s)
        {
            const auto tmpspan = al::span{tmpBuffer}.subspan(sSampleLength*s, sSampleLength);
            auto iter = std::copy_n(tmpspan.cbegin(), tmpspan.size(), fftBuffer.begin());
            std::fill(iter, fftBuffer.end(), complex_d{});
            forward_fft(fftBuffer);

            /* Convert to zdomain data for PFFFT, scaled by the FFT length so
             * the iFFT result will be normalized.
             */
            for(size_t i{0};i < sSampleLength;++i)
            {
                fftTmp[i*2 + 0] = static_cast<float>(fftBuffer[i].real()) / float{sFftLength};
                fftTmp[i*2 + 1] = static_cast<float>((i == 0) ? fftBuffer[sSampleLength].real()
                    : fftBuffer[i].imag()) / float{sFftLength};
            }
            mFft.zreorder(fftTmp.data(), al::to_address(filter), PFFFT_BACKWARD);
            filter += sFftLength;
        }
    }
};

template<size_t N>
const SegmentedFilter<N> gSegmentedFilter;

template<size_t N>
const PhaseShifterT<N> PShifter;


/* Filter coefficients for the 'base' all-pass IIR, which applies a frequency-
 * dependent phase-shift of N degrees. The output of the filter requires a 1-
 * sample delay.
 */
constexpr std::array<float,4> Filter1Coeff{{
    0.479400865589f, 0.876218493539f, 0.976597589508f, 0.997499255936f
}};
/* Filter coefficients for the offset all-pass IIR, which applies a frequency-
 * dependent phase-shift of N+90 degrees.
 */
constexpr std::array<float,4> Filter2Coeff{{
    0.161758498368f, 0.733028932341f, 0.945349700329f, 0.990599156684f
}};

} // namespace

void UhjAllPassFilter::processOne(const al::span<const float, 4> coeffs, float x)
{
    auto state = mState;
    for(size_t i{0};i < 4;++i)
    {
        const float y{x*coeffs[i] + state[i].z[0]};
        state[i].z[0] = state[i].z[1];
        state[i].z[1] = y*coeffs[i] - x;
        x = y;
    }
    mState = state;
}

void UhjAllPassFilter::process(const al::span<const float,4> coeffs,
    const al::span<const float> src, const bool updateState, const al::span<float> dst)
{
    auto state = mState;

    auto proc_sample = [&state,coeffs](float x) noexcept -> float
    {
        for(size_t i{0};i < 4;++i)
        {
            const float y{x*coeffs[i] + state[i].z[0]};
            state[i].z[0] = state[i].z[1];
            state[i].z[1] = y*coeffs[i] - x;
            x = y;
        }
        return x;
    };
    std::transform(src.begin(), src.end(), dst.begin(), proc_sample);
    if(updateState) LIKELY mState = state;
}


/* Encoding UHJ from B-Format is done as:
 *
 * S = 0.9396926*W + 0.1855740*X
 * D = j(-0.3420201*W + 0.5098604*X) + 0.6554516*Y
 *
 * Left = (S + D)/2.0
 * Right = (S - D)/2.0
 * T = j(-0.1432*W + 0.6512*X) - 0.7071068*Y
 * Q = 0.9772*Z
 *
 * where j is a wide-band +90 degree phase shift. 3-channel UHJ excludes Q,
 * while 2-channel excludes Q and T.
 *
 * The phase shift is done using a linear FIR filter derived from an FFT'd
 * impulse with the desired shift.
 */

template<size_t N>
void UhjEncoder<N>::encode(float *LeftOut, float *RightOut,
    const al::span<const float*const,3> InSamples, const size_t SamplesToDo)
{
    static constexpr auto &Filter = gSegmentedFilter<N>;
    static_assert(sFftLength == Filter.sFftLength);
    static_assert(sSegmentSize == Filter.sSampleLength);
    static_assert(sNumSegments == Filter.sNumSegments);

    ASSUME(SamplesToDo > 0);
    ASSUME(SamplesToDo <= BufferLineSize);

    const auto winput = al::span{al::assume_aligned<16>(InSamples[0]), SamplesToDo};
    const auto xinput = al::span{al::assume_aligned<16>(InSamples[1]), SamplesToDo};
    const auto yinput = al::span{al::assume_aligned<16>(InSamples[2]), SamplesToDo};

    std::copy_n(winput.begin(), SamplesToDo, mW.begin()+sFilterDelay);
    std::copy_n(xinput.begin(), SamplesToDo, mX.begin()+sFilterDelay);
    std::copy_n(yinput.begin(), SamplesToDo, mY.begin()+sFilterDelay);

    /* S = 0.9396926*W + 0.1855740*X */
    std::transform(mW.begin(), mW.begin()+SamplesToDo, mX.begin(), mS.begin(),
        [](const float w, const float x) noexcept { return 0.9396926f*w + 0.1855740f*x; });

    /* Precompute j(-0.3420201*W + 0.5098604*X) and store in mD. */
    auto dstore = mD.begin();
    size_t curseg{mCurrentSegment};
    for(size_t base{0};base < SamplesToDo;)
    {
        const size_t todo{std::min(sSegmentSize-mFifoPos, SamplesToDo-base)};
        auto wseg = winput.subspan(base, todo);
        auto xseg = xinput.subspan(base, todo);
        auto wxio = al::span{mWXInOut}.subspan(mFifoPos, todo);

        /* Copy out the samples that were previously processed by the FFT. */
        dstore = std::copy_n(wxio.begin(), todo, dstore);

        /* Transform the non-delayed input and store in the front half of the
         * filter input.
         */
        std::transform(wseg.begin(), wseg.end(), xseg.begin(), wxio.begin(),
            [](const float w, const float x) noexcept -> float
            { return -0.3420201f*w + 0.5098604f*x; });

        mFifoPos += todo;
        base += todo;

        /* Check whether the input buffer is filled with new samples. */
        if(mFifoPos < sSegmentSize) break;
        mFifoPos = 0;

        /* Copy the new input to the next history segment, clearing the back
         * half of the segment, and convert to the frequency domain.
         */
        auto input = mWXHistory.begin() + curseg*sFftLength;
        std::copy_n(mWXInOut.begin(), sSegmentSize, input);
        std::fill_n(input+sSegmentSize, sSegmentSize, 0.0f);

        Filter.mFft.transform(al::to_address(input), al::to_address(input), mWorkData.data(),
            PFFFT_FORWARD);

        /* Convolve each input segment with its IR filter counterpart (aligned
         * in time, from newest to oldest).
         */
        mFftBuffer.fill(0.0f);
        auto filter = Filter.mFilterData.begin();
        for(size_t s{curseg};s < sNumSegments;++s)
        {
            Filter.mFft.zconvolve_accumulate(al::to_address(input), al::to_address(filter),
                mFftBuffer.data());
            input += sFftLength;
            filter += sFftLength;
        }
        input = mWXHistory.begin();
        for(size_t s{0};s < curseg;++s)
        {
            Filter.mFft.zconvolve_accumulate(al::to_address(input), al::to_address(filter),
                mFftBuffer.data());
            input += sFftLength;
            filter += sFftLength;
        }

        /* Convert back to samples, writing to the output and storing the extra
         * for next time.
         */
        Filter.mFft.transform(mFftBuffer.data(), mFftBuffer.data(), mWorkData.data(),
            PFFFT_BACKWARD);

        std::transform(mFftBuffer.begin(), mFftBuffer.begin()+sSegmentSize,
            mWXInOut.begin()+sSegmentSize, mWXInOut.begin(), std::plus{});
        std::copy_n(mFftBuffer.begin()+sSegmentSize, sSegmentSize, mWXInOut.begin()+sSegmentSize);

        /* Shift the input history. */
        curseg = curseg ? (curseg-1) : (sNumSegments-1);
    }
    mCurrentSegment = curseg;

    /* D = j(-0.3420201*W + 0.5098604*X) + 0.6554516*Y */
    std::transform(mD.begin(), mD.begin()+SamplesToDo, mY.begin(), mD.begin(),
        [](const float jwx, const float y) noexcept { return jwx + 0.6554516f*y; });

    /* Copy the future samples to the front for next time. */
    std::copy(mW.cbegin()+SamplesToDo, mW.cbegin()+SamplesToDo+sFilterDelay, mW.begin());
    std::copy(mX.cbegin()+SamplesToDo, mX.cbegin()+SamplesToDo+sFilterDelay, mX.begin());
    std::copy(mY.cbegin()+SamplesToDo, mY.cbegin()+SamplesToDo+sFilterDelay, mY.begin());

    /* Apply a delay to the existing output to align with the input delay. */
    auto delayBuffer = mDirectDelay.begin();
    for(float *buffer : {LeftOut, RightOut})
    {
        const auto distbuf = assume_aligned_span<16>(al::span{*delayBuffer});
        ++delayBuffer;

        const auto inout = al::span{al::assume_aligned<16>(buffer), SamplesToDo};
        if(SamplesToDo >= sFilterDelay)
        {
            auto delay_end = std::rotate(inout.begin(), inout.end() - sFilterDelay, inout.end());
            std::swap_ranges(inout.begin(), delay_end, distbuf.begin());
        }
        else
        {
            auto delay_start = std::swap_ranges(inout.begin(), inout.end(), distbuf.begin());
            std::rotate(distbuf.begin(), delay_start, distbuf.begin() + sFilterDelay);
        }
    }

    /* Combine the direct signal with the produced output. */

    /* Left = (S + D)/2.0 */
    const auto left = al::span{al::assume_aligned<16>(LeftOut), SamplesToDo};
    for(size_t i{0};i < SamplesToDo;++i)
        left[i] += (mS[i] + mD[i]) * 0.5f;

    /* Right = (S - D)/2.0 */
    const auto right = al::span{al::assume_aligned<16>(RightOut), SamplesToDo};
    for(size_t i{0};i < SamplesToDo;++i)
        right[i] += (mS[i] - mD[i]) * 0.5f;
}

/* This encoding implementation uses two sets of four chained IIR filters to
 * produce the desired relative phase shift. The first filter chain produces a
 * phase shift of varying degrees over a wide range of frequencies, while the
 * second filter chain produces a phase shift 90 degrees ahead of the first
 * over the same range. Further details are described here:
 *
 * https://web.archive.org/web/20060708031958/http://www.biochem.oulu.fi/~oniemita/dsp/hilbert/
 *
 * 2-channel UHJ output requires the use of three filter chains. The S channel
 * output uses a Filter1 chain on the W and X channel mix, while the D channel
 * output uses a Filter1 chain on the Y channel plus a Filter2 chain on the W
 * and X channel mix. This results in the W and X input mix on the D channel
 * output having the required +90 degree phase shift relative to the other
 * inputs.
 */
void UhjEncoderIIR::encode(float *LeftOut, float *RightOut,
    const al::span<const float *const, 3> InSamples, const size_t SamplesToDo)
{
    ASSUME(SamplesToDo > 0);
    ASSUME(SamplesToDo <= BufferLineSize);

    const auto winput = al::span{al::assume_aligned<16>(InSamples[0]), SamplesToDo};
    const auto xinput = al::span{al::assume_aligned<16>(InSamples[1]), SamplesToDo};
    const auto yinput = al::span{al::assume_aligned<16>(InSamples[2]), SamplesToDo};

    /* S = 0.9396926*W + 0.1855740*X */
    std::transform(winput.begin(), winput.end(), xinput.begin(), mTemp.begin(),
        [](const float w, const float x) noexcept { return 0.9396926f*w + 0.1855740f*x; });
    mFilter1WX.process(Filter1Coeff, al::span{mTemp}.first(SamplesToDo), true,
        al::span{mS}.subspan(1));
    mS[0] = mDelayWX; mDelayWX = mS[SamplesToDo];

    /* Precompute j(-0.3420201*W + 0.5098604*X) and store in mWX. */
    std::transform(winput.begin(), winput.end(), xinput.begin(), mTemp.begin(),
        [](const float w, const float x) noexcept { return -0.3420201f*w + 0.5098604f*x; });
    mFilter2WX.process(Filter2Coeff, al::span{mTemp}.first(SamplesToDo), true, mWX);

    /* Apply filter1 to Y and store in mD. */
    mFilter1Y.process(Filter1Coeff, yinput, true, al::span{mD}.subspan(1));
    mD[0] = mDelayY; mDelayY = mD[SamplesToDo];

    /* D = j(-0.3420201*W + 0.5098604*X) + 0.6554516*Y */
    std::transform(mWX.begin(), mWX.begin()+SamplesToDo, mD.begin(), mD.begin(),
        [](const float jwx, const float y) noexcept { return jwx + 0.6554516f*y; });

    /* Apply the base filter to the existing output to align with the processed
     * signal.
     */
    const auto left = al::span{al::assume_aligned<16>(LeftOut), SamplesToDo};
    mFilter1Direct[0].process(Filter1Coeff, left, true, al::span{mTemp}.subspan(1));
    mTemp[0] = mDirectDelay[0]; mDirectDelay[0] = mTemp[SamplesToDo];

    /* Left = (S + D)/2.0 */
    for(size_t i{0};i < SamplesToDo;++i)
        left[i] = (mS[i] + mD[i])*0.5f + mTemp[i];

    const auto right = al::span{al::assume_aligned<16>(RightOut), SamplesToDo};
    mFilter1Direct[1].process(Filter1Coeff, right, true, al::span{mTemp}.subspan(1));
    mTemp[0] = mDirectDelay[1]; mDirectDelay[1] = mTemp[SamplesToDo];

    /* Right = (S - D)/2.0 */
    for(size_t i{0};i < SamplesToDo;++i)
        right[i] = (mS[i] - mD[i])*0.5f + mTemp[i];
}


/* Decoding UHJ is done as:
 *
 * S = Left + Right
 * D = Left - Right
 *
 * W = 0.981532*S + 0.197484*j(0.828331*D + 0.767820*T)
 * X = 0.418496*S - j(0.828331*D + 0.767820*T)
 * Y = 0.795968*D - 0.676392*T + j(0.186633*S)
 * Z = 1.023332*Q
 *
 * where j is a +90 degree phase shift. 3-channel UHJ excludes Q, while 2-
 * channel excludes Q and T.
 */
template<size_t N>
void UhjDecoder<N>::decode(const al::span<float*> samples, const size_t samplesToDo,
    const bool updateState)
{
    static_assert(sInputPadding <= sMaxPadding, "Filter padding is too large");

    constexpr auto &PShift = PShifter<N>;

    ASSUME(samplesToDo > 0);
    ASSUME(samplesToDo <= BufferLineSize);

    {
        const auto left = al::span{al::assume_aligned<16>(samples[0]), samplesToDo+sInputPadding};
        const auto right = al::span{al::assume_aligned<16>(samples[1]), samplesToDo+sInputPadding};
        const auto t = al::span{al::assume_aligned<16>(samples[2]), samplesToDo+sInputPadding};

        /* S = Left + Right */
        std::transform(left.begin(), left.end(), right.begin(), mS.begin(), std::plus{});

        /* D = Left - Right */
        std::transform(left.begin(), left.end(), right.begin(), mD.begin(), std::minus{});

        /* T */
        std::copy(t.begin(), t.end(), mT.begin());
    }

    const auto woutput = al::span{al::assume_aligned<16>(samples[0]), samplesToDo};
    const auto xoutput = al::span{al::assume_aligned<16>(samples[1]), samplesToDo};
    const auto youtput = al::span{al::assume_aligned<16>(samples[2]), samplesToDo};

    /* Precompute j(0.828331*D + 0.767820*T) and store in xoutput. */
    auto tmpiter = std::copy(mDTHistory.cbegin(), mDTHistory.cend(), mTemp.begin());
    std::transform(mD.cbegin(), mD.cbegin()+samplesToDo+sInputPadding, mT.cbegin(), tmpiter,
        [](const float d, const float t) noexcept { return 0.828331f*d + 0.767820f*t; });
    if(updateState) LIKELY
        std::copy_n(mTemp.cbegin()+samplesToDo, mDTHistory.size(), mDTHistory.begin());
    PShift.process(xoutput, mTemp);

    /* W = 0.981532*S + 0.197484*j(0.828331*D + 0.767820*T) */
    std::transform(mS.begin(), mS.begin()+samplesToDo, xoutput.begin(), woutput.begin(),
        [](const float s, const float jdt) noexcept { return 0.981532f*s + 0.197484f*jdt; });

    /* X = 0.418496*S - j(0.828331*D + 0.767820*T) */
    std::transform(mS.begin(), mS.begin()+samplesToDo, xoutput.begin(), xoutput.begin(),
        [](const float s, const float jdt) noexcept { return 0.418496f*s - jdt; });

    /* Precompute j*S and store in youtput. */
    tmpiter = std::copy(mSHistory.cbegin(), mSHistory.cend(), mTemp.begin());
    std::copy_n(mS.cbegin(), samplesToDo+sInputPadding, tmpiter);
    if(updateState) LIKELY
        std::copy_n(mTemp.cbegin()+samplesToDo, mSHistory.size(), mSHistory.begin());
    PShift.process(youtput, mTemp);

    /* Y = 0.795968*D - 0.676392*T + j(0.186633*S) */
    for(size_t i{0};i < samplesToDo;++i)
        youtput[i] = 0.795968f*mD[i] - 0.676392f*mT[i] + 0.186633f*youtput[i];

    if(samples.size() > 3)
    {
        const auto zoutput = al::span{al::assume_aligned<16>(samples[3]), samplesToDo};
        /* Z = 1.023332*Q */
        std::transform(zoutput.begin(), zoutput.end(), zoutput.begin(),
            [](const float q) noexcept { return 1.023332f*q; });
    }
}

void UhjDecoderIIR::decode(const al::span<float*> samples, const size_t samplesToDo,
    const bool updateState)
{
    static_assert(sInputPadding <= sMaxPadding, "Filter padding is too large");

    ASSUME(samplesToDo > 0);
    ASSUME(samplesToDo <= BufferLineSize);

    {
        const auto left = al::span{al::assume_aligned<16>(samples[0]), samplesToDo+sInputPadding};
        const auto right = al::span{al::assume_aligned<16>(samples[1]), samplesToDo+sInputPadding};

        /* S = Left + Right */
        std::transform(left.begin(), left.end(), right.begin(), mS.begin(), std::plus{});

        /* D = Left - Right */
        std::transform(left.begin(), left.end(), right.begin(), mD.begin(), std::minus{});
    }

    const auto woutput = al::span{al::assume_aligned<16>(samples[0]), samplesToDo};
    const auto xoutput = al::span{al::assume_aligned<16>(samples[1]), samplesToDo};
    const auto youtput = al::span{al::assume_aligned<16>(samples[2]), samplesToDo+sInputPadding};

    /* Precompute j(0.828331*D + 0.767820*T) and store in xoutput. */
    std::transform(mD.cbegin(), mD.cbegin()+sInputPadding+samplesToDo, youtput.begin(),
        mTemp.begin(),
        [](const float d, const float t) noexcept { return 0.828331f*d + 0.767820f*t; });
    if(mFirstRun) mFilter2DT.processOne(Filter2Coeff, mTemp[0]);
    mFilter2DT.process(Filter2Coeff, al::span{mTemp}.subspan(1,samplesToDo), updateState, xoutput);

    /* Apply filter1 to S and store in mTemp. */
    mFilter1S.process(Filter1Coeff, al::span{mS}.first(samplesToDo), updateState, mTemp);

    /* W = 0.981532*S + 0.197484*j(0.828331*D + 0.767820*T) */
    std::transform(mTemp.begin(), mTemp.begin()+samplesToDo, xoutput.begin(), woutput.begin(),
        [](const float s, const float jdt) noexcept { return 0.981532f*s + 0.197484f*jdt; });
    /* X = 0.418496*S - j(0.828331*D + 0.767820*T) */
    std::transform(mTemp.begin(), mTemp.begin()+samplesToDo, xoutput.begin(), xoutput.begin(),
        [](const float s, const float jdt) noexcept { return 0.418496f*s - jdt; });


    /* Apply filter1 to (0.795968*D - 0.676392*T) and store in mTemp. */
    std::transform(mD.cbegin(), mD.cbegin()+samplesToDo, youtput.begin(), youtput.begin(),
        [](const float d, const float t) noexcept { return 0.795968f*d - 0.676392f*t; });
    mFilter1DT.process(Filter1Coeff, youtput.first(samplesToDo), updateState, mTemp);

    /* Precompute j*S and store in youtput. */
    if(mFirstRun) mFilter2S.processOne(Filter2Coeff, mS[0]);
    mFilter2S.process(Filter2Coeff, al::span{mS}.subspan(1, samplesToDo), updateState, youtput);

    /* Y = 0.795968*D - 0.676392*T + j(0.186633*S) */
    std::transform(mTemp.begin(), mTemp.begin()+samplesToDo, youtput.begin(), youtput.begin(),
        [](const float dt, const float js) noexcept { return dt + 0.186633f*js; });

    if(samples.size() > 3)
    {
        const auto zoutput = al::span{al::assume_aligned<16>(samples[3]), samplesToDo};

        /* Apply filter1 to Q and store in mTemp. */
        mFilter1Q.process(Filter1Coeff, zoutput, updateState, mTemp);

        /* Z = 1.023332*Q */
        std::transform(mTemp.begin(), mTemp.end(), zoutput.begin(),
            [](const float q) noexcept { return 1.023332f*q; });
    }

    mFirstRun = false;
}


/* Super Stereo processing is done as:
 *
 * S = Left + Right
 * D = Left - Right
 *
 * W = 0.6098637*S + 0.6896511*j*w*D
 * X = 0.8624776*S - 0.7626955*j*w*D
 * Y = 1.6822415*w*D + 0.2156194*j*S
 *
 * where j is a +90 degree phase shift. w is a variable control for the
 * resulting stereo width, with the range 0 <= w <= 0.7.
 */
template<size_t N>
void UhjStereoDecoder<N>::decode(const al::span<float*> samples, const size_t samplesToDo,
    const bool updateState)
{
    static_assert(sInputPadding <= sMaxPadding, "Filter padding is too large");

    constexpr auto &PShift = PShifter<N>;

    ASSUME(samplesToDo > 0);
    ASSUME(samplesToDo <= BufferLineSize);

    {
        const auto left = al::span{al::assume_aligned<16>(samples[0]), samplesToDo+sInputPadding};
        const auto right = al::span{al::assume_aligned<16>(samples[1]), samplesToDo+sInputPadding};

        std::transform(left.begin(), left.end(), right.begin(), mS.begin(), std::plus{});

        /* Pre-apply the width factor to the difference signal D. Smoothly
         * interpolate when it changes.
         */
        const float wtarget{mWidthControl};
        const float wcurrent{(mCurrentWidth < 0.0f) ? wtarget : mCurrentWidth};
        if(wtarget == wcurrent || !updateState)
        {
            std::transform(left.begin(), left.end(), right.begin(), mD.begin(),
                [wcurrent](const float l, const float r) noexcept { return (l-r) * wcurrent; });
            mCurrentWidth = wcurrent;
        }
        else
        {
            const float wstep{(wtarget - wcurrent) / static_cast<float>(samplesToDo)};
            float fi{0.0f};

            const auto lfade = left.first(samplesToDo);
            auto dstore = std::transform(lfade.begin(), lfade.begin(), right.begin(), mD.begin(),
                [wcurrent,wstep,&fi](const float l, const float r) noexcept
                {
                    const float ret{(l-r) * (wcurrent + wstep*fi)};
                    fi += 1.0f;
                    return ret;
                });

            const auto lend = left.subspan(samplesToDo);
            const auto rend = right.subspan(samplesToDo);
            std::transform(lend.begin(), lend.end(), rend.begin(), dstore,
                [wtarget](const float l, const float r) noexcept { return (l-r) * wtarget; });
            mCurrentWidth = wtarget;
        }
    }

    const auto woutput = al::span{al::assume_aligned<16>(samples[0]), samplesToDo};
    const auto xoutput = al::span{al::assume_aligned<16>(samples[1]), samplesToDo};
    const auto youtput = al::span{al::assume_aligned<16>(samples[2]), samplesToDo};

    /* Precompute j*D and store in xoutput. */
    auto tmpiter = std::copy(mDTHistory.cbegin(), mDTHistory.cend(), mTemp.begin());
    std::copy_n(mD.cbegin(), samplesToDo+sInputPadding, tmpiter);
    if(updateState) LIKELY
        std::copy_n(mTemp.cbegin()+samplesToDo, mDTHistory.size(), mDTHistory.begin());
    PShift.process(xoutput, mTemp);

    /* W = 0.6098637*S + 0.6896511*j*w*D */
    std::transform(mS.begin(), mS.begin()+samplesToDo, xoutput.begin(), woutput.begin(),
        [](const float s, const float jd) noexcept { return 0.6098637f*s + 0.6896511f*jd; });
    /* X = 0.8624776*S - 0.7626955*j*w*D */
    std::transform(mS.begin(), mS.begin()+samplesToDo, xoutput.begin(), xoutput.begin(),
        [](const float s, const float jd) noexcept { return 0.8624776f*s - 0.7626955f*jd; });

    /* Precompute j*S and store in youtput. */
    tmpiter = std::copy(mSHistory.cbegin(), mSHistory.cend(), mTemp.begin());
    std::copy_n(mS.cbegin(), samplesToDo+sInputPadding, tmpiter);
    if(updateState) LIKELY
        std::copy_n(mTemp.cbegin()+samplesToDo, mSHistory.size(), mSHistory.begin());
    PShift.process(youtput, mTemp);

    /* Y = 1.6822415*w*D + 0.2156194*j*S */
    std::transform(mD.begin(), mD.begin()+samplesToDo, youtput.begin(), youtput.begin(),
        [](const float d, const float js) noexcept { return 1.6822415f*d + 0.2156194f*js; });
}

void UhjStereoDecoderIIR::decode(const al::span<float*> samples, const size_t samplesToDo,
    const bool updateState)
{
    static_assert(sInputPadding <= sMaxPadding, "Filter padding is too large");

    ASSUME(samplesToDo > 0);
    ASSUME(samplesToDo <= BufferLineSize);

    {
        const auto left = al::span{al::assume_aligned<16>(samples[0]), samplesToDo+sInputPadding};
        const auto right = al::span{al::assume_aligned<16>(samples[1]), samplesToDo+sInputPadding};

        std::transform(left.begin(), left.end(), right.begin(), mS.begin(), std::plus{});

        /* Pre-apply the width factor to the difference signal D. Smoothly
         * interpolate when it changes.
         */
        const float wtarget{mWidthControl};
        const float wcurrent{(mCurrentWidth < 0.0f) ? wtarget : mCurrentWidth};
        if(wtarget == wcurrent || !updateState)
        {
            std::transform(left.begin(), left.end(), right.begin(), mD.begin(),
                [wcurrent](const float l, const float r) noexcept
                { return (l-r) * wcurrent; });
            mCurrentWidth = wcurrent;
        }
        else
        {
            const float wstep{(wtarget - wcurrent) / static_cast<float>(samplesToDo)};
            float fi{0.0f};

            const auto lfade = left.first(samplesToDo);
            auto dstore = std::transform(lfade.begin(), lfade.begin(), right.begin(), mD.begin(),
                [wcurrent,wstep,&fi](const float l, const float r) noexcept
                {
                    const float ret{(l-r) * (wcurrent + wstep*fi)};
                    fi += 1.0f;
                    return ret;
                });

            const auto lend = left.subspan(samplesToDo);
            const auto rend = right.subspan(samplesToDo);
            std::transform(lend.begin(), lend.end(), rend.begin(), dstore,
                [wtarget](const float l, const float r) noexcept { return (l-r) * wtarget; });
            mCurrentWidth = wtarget;
        }
    }

    const auto woutput = al::span{al::assume_aligned<16>(samples[0]), samplesToDo};
    const auto xoutput = al::span{al::assume_aligned<16>(samples[1]), samplesToDo};
    const auto youtput = al::span{al::assume_aligned<16>(samples[2]), samplesToDo};

    /* Apply filter1 to S and store in mTemp. */
    mFilter1S.process(Filter1Coeff, al::span{mS}.first(samplesToDo), updateState, mTemp);

    /* Precompute j*D and store in xoutput. */
    if(mFirstRun) mFilter2D.processOne(Filter2Coeff, mD[0]);
    mFilter2D.process(Filter2Coeff, al::span{mD}.subspan(1, samplesToDo), updateState, xoutput);

    /* W = 0.6098637*S + 0.6896511*j*w*D */
    std::transform(mTemp.begin(), mTemp.begin()+samplesToDo, xoutput.begin(), woutput.begin(),
        [](const float s, const float jd) noexcept { return 0.6098637f*s + 0.6896511f*jd; });
    /* X = 0.8624776*S - 0.7626955*j*w*D */
    std::transform(mTemp.begin(), mTemp.begin()+samplesToDo, xoutput.begin(), xoutput.begin(),
        [](const float s, const float jd) noexcept { return 0.8624776f*s - 0.7626955f*jd; });

    /* Precompute j*S and store in youtput. */
    if(mFirstRun) mFilter2S.processOne(Filter2Coeff, mS[0]);
    mFilter2S.process(Filter2Coeff, al::span{mS}.subspan(1, samplesToDo), updateState, youtput);

    /* Apply filter1 to D and store in mTemp. */
    mFilter1D.process(Filter1Coeff, al::span{mD}.first(samplesToDo), updateState, mTemp);

    /* Y = 1.6822415*w*D + 0.2156194*j*S */
    std::transform(mTemp.begin(), mTemp.begin()+samplesToDo, youtput.begin(), youtput.begin(),
        [](const float d, const float js) noexcept { return 1.6822415f*d + 0.2156194f*js; });

    mFirstRun = false;
}


template struct UhjEncoder<UhjLength256>;
template struct UhjDecoder<UhjLength256>;
template struct UhjStereoDecoder<UhjLength256>;

template struct UhjEncoder<UhjLength512>;
template struct UhjDecoder<UhjLength512>;
template struct UhjStereoDecoder<UhjLength512>;
