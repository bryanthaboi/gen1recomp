
#include "config.h"

#include "mastering.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <functional>
#include <iterator>
#include <limits>
#include <new>

#include "alnumeric.h"
#include "alspan.h"
#include "opthelpers.h"


/* These structures assume BufferLineSize is a power of 2. */
static_assert((BufferLineSize & (BufferLineSize-1)) == 0, "BufferLineSize is not a power of 2");

struct SIMDALIGN SlidingHold {
    alignas(16) FloatBufferLine mValues;
    std::array<uint,BufferLineSize> mExpiries;
    uint mLowerIndex;
    uint mUpperIndex;
    uint mLength;
};


namespace {

template<std::size_t A, typename T, std::size_t N>
constexpr auto assume_aligned_span(const al::span<T,N> s) noexcept -> al::span<T,N>
{ return al::span<T,N>{al::assume_aligned<A>(s.data()), s.size()}; }

/* This sliding hold follows the input level with an instant attack and a
 * fixed duration hold before an instant release to the next highest level.
 * It is a sliding window maximum (descending maxima) implementation based on
 * Richard Harter's ascending minima algorithm available at:
 *
 *   http://www.richardhartersworld.com/cri/2001/slidingmin.html
 */
float UpdateSlidingHold(SlidingHold *Hold, const uint i, const float in)
{
    static constexpr uint mask{BufferLineSize - 1};
    const uint length{Hold->mLength};
    const al::span values{Hold->mValues};
    const al::span expiries{Hold->mExpiries};
    uint lowerIndex{Hold->mLowerIndex};
    uint upperIndex{Hold->mUpperIndex};

    if(i >= expiries[upperIndex])
        upperIndex = (upperIndex + 1) & mask;

    if(in >= values[upperIndex])
    {
        values[upperIndex] = in;
        expiries[upperIndex] = i + length;
        lowerIndex = upperIndex;
    }
    else
    {
        auto findLowerIndex = [&lowerIndex,in,values]() noexcept -> bool
        {
            do {
                if(!(in >= values[lowerIndex]))
                    return true;
            } while(lowerIndex--);
            return false;
        };
        while(!findLowerIndex())
            lowerIndex = mask;

        lowerIndex = (lowerIndex + 1) & mask;
        values[lowerIndex] = in;
        expiries[lowerIndex] = i + length;
    }

    Hold->mLowerIndex = lowerIndex;
    Hold->mUpperIndex = upperIndex;

    return values[upperIndex];
}

void ShiftSlidingHold(SlidingHold *Hold, const uint n)
{
    auto exp_upper = Hold->mExpiries.begin() + Hold->mUpperIndex;
    if(Hold->mLowerIndex < Hold->mUpperIndex)
    {
        std::transform(exp_upper, Hold->mExpiries.end(), exp_upper,
            [n](const uint e) noexcept { return e - n; });
        exp_upper = Hold->mExpiries.begin();
    }
    const auto exp_lower = Hold->mExpiries.begin() + Hold->mLowerIndex;
    std::transform(exp_upper, exp_lower+1, exp_upper,
        [n](const uint e) noexcept { return e - n; });
}

} // namespace

/* Multichannel compression is linked via the absolute maximum of all
 * channels.
 */
void Compressor::linkChannels(const uint SamplesToDo,
    const al::span<const FloatBufferLine> OutBuffer)
{
    ASSUME(SamplesToDo > 0);
    ASSUME(SamplesToDo <= BufferLineSize);

    const auto sideChain = al::span{mSideChain}.subspan(mLookAhead, SamplesToDo);
    std::fill_n(sideChain.begin(), sideChain.size(), 0.0f);

    auto fill_max = [sideChain](const FloatBufferLine &input) -> void
    {
        const auto buffer = assume_aligned_span<16>(al::span{input});
        auto max_abs = [](const float s0, const float s1) noexcept -> float
        { return std::max(s0, std::fabs(s1)); };
        std::transform(sideChain.begin(), sideChain.end(), buffer.begin(), sideChain.begin(),
            max_abs);
    };
    for(const FloatBufferLine &input : OutBuffer)
        fill_max(input);
}

/* This calculates the squared crest factor of the control signal for the
 * basic automation of the attack/release times.  As suggested by the paper,
 * it uses an instantaneous squared peak detector and a squared RMS detector
 * both with 200ms release times.
 */
void Compressor::crestDetector(const uint SamplesToDo)
{
    const float a_crest{mCrestCoeff};
    float y2_peak{mLastPeakSq};
    float y2_rms{mLastRmsSq};

    ASSUME(SamplesToDo > 0);
    ASSUME(SamplesToDo <= BufferLineSize);

    auto calc_crest = [&y2_rms,&y2_peak,a_crest](const float x_abs) noexcept -> float
    {
        const float x2{std::clamp(x_abs*x_abs, 0.000001f, 1000000.0f)};

        y2_peak = std::max(x2, lerpf(x2, y2_peak, a_crest));
        y2_rms = lerpf(x2, y2_rms, a_crest);
        return y2_peak / y2_rms;
    };
    const auto sideChain = al::span{mSideChain}.subspan(mLookAhead, SamplesToDo);
    std::transform(sideChain.cbegin(), sideChain.cend(), mCrestFactor.begin(), calc_crest);

    mLastPeakSq = y2_peak;
    mLastRmsSq = y2_rms;
}

/* The side-chain starts with a simple peak detector (based on the absolute
 * value of the incoming signal) and performs most of its operations in the
 * log domain.
 */
void Compressor::peakDetector(const uint SamplesToDo)
{
    ASSUME(SamplesToDo > 0);
    ASSUME(SamplesToDo <= BufferLineSize);

    /* Clamp the minimum amplitude to near-zero and convert to logarithmic. */
    const auto sideChain = al::span{mSideChain}.subspan(mLookAhead, SamplesToDo);
    std::transform(sideChain.cbegin(), sideChain.cend(), sideChain.begin(),
        [](float s) { return std::log(std::max(0.000001f, s)); });
}

/* An optional hold can be used to extend the peak detector so it can more
 * solidly detect fast transients.  This is best used when operating as a
 * limiter.
 */
void Compressor::peakHoldDetector(const uint SamplesToDo)
{
    ASSUME(SamplesToDo > 0);
    ASSUME(SamplesToDo <= BufferLineSize);

    SlidingHold *hold{mHold.get()};
    uint i{0};
    auto detect_peak = [&i,hold](const float x_abs) -> float
    {
        const float x_G{std::log(std::max(0.000001f, x_abs))};
        return UpdateSlidingHold(hold, i++, x_G);
    };
    auto sideChain = al::span{mSideChain}.subspan(mLookAhead, SamplesToDo);
    std::transform(sideChain.cbegin(), sideChain.cend(), sideChain.begin(), detect_peak);

    ShiftSlidingHold(hold, SamplesToDo);
}

/* This is the heart of the feed-forward compressor.  It operates in the log
 * domain (to better match human hearing) and can apply some basic automation
 * to knee width, attack/release times, make-up/post gain, and clipping
 * reduction.
 */
void Compressor::gainCompressor(const uint SamplesToDo)
{
    const bool autoKnee{mAuto.Knee};
    const bool autoAttack{mAuto.Attack};
    const bool autoRelease{mAuto.Release};
    const bool autoPostGain{mAuto.PostGain};
    const bool autoDeclip{mAuto.Declip};
    const float threshold{mThreshold};
    const float slope{mSlope};
    const float attack{mAttack};
    const float release{mRelease};
    const float c_est{mGainEstimate};
    const float a_adp{mAdaptCoeff};
    auto lookAhead = mSideChain.cbegin() + mLookAhead;
    auto crestFactor = mCrestFactor.cbegin();
    float postGain{mPostGain};
    float knee{mKnee};
    float t_att{attack};
    float t_rel{release - attack};
    float a_att{std::exp(-1.0f / t_att)};
    float a_rel{std::exp(-1.0f / t_rel)};
    float y_1{mLastRelease};
    float y_L{mLastAttack};
    float c_dev{mLastGainDev};

    ASSUME(SamplesToDo > 0);

    auto process = [&](const float input) -> float
    {
        if(autoKnee)
            knee = std::max(0.0f, 2.5f * (c_dev + c_est));
        const float knee_h{0.5f * knee};

        /* This is the gain computer.  It applies a static compression curve
         * to the control signal.
         */
        const float x_over{*(lookAhead++) - threshold};
        const float y_G{
            (x_over <= -knee_h) ? 0.0f :
            (std::fabs(x_over) < knee_h) ? (x_over+knee_h) * (x_over+knee_h) / (2.0f * knee) :
            x_over};

        const float y2_crest{*(crestFactor++)};
        if(autoAttack)
        {
            t_att = 2.0f*attack/y2_crest;
            a_att = std::exp(-1.0f / t_att);
        }
        if(autoRelease)
        {
            t_rel = 2.0f*release/y2_crest - t_att;
            a_rel = std::exp(-1.0f / t_rel);
        }

        /* Gain smoothing (ballistics) is done via a smooth decoupled peak
         * detector.  The attack time is subtracted from the release time
         * above to compensate for the chained operating mode.
         */
        const float x_L{-slope * y_G};
        y_1 = std::max(x_L, lerpf(x_L, y_1, a_rel));
        y_L = lerpf(y_1, y_L, a_att);

        /* Knee width and make-up gain automation make use of a smoothed
         * measurement of deviation between the control signal and estimate.
         * The estimate is also used to bias the measurement to hot-start its
         * average.
         */
        c_dev = lerpf(-(y_L+c_est), c_dev, a_adp);

        if(autoPostGain)
        {
            /* Clipping reduction is only viable when make-up gain is being
             * automated. It modifies the deviation to further attenuate the
             * control signal when clipping is detected. The adaptation time
             * is sufficiently long enough to suppress further clipping at the
             * same output level.
             */
            if(autoDeclip)
                c_dev = std::max(c_dev, input - y_L - threshold - c_est);

            postGain = -(c_dev + c_est);
        }

        return std::exp(postGain - y_L);
    };
    auto sideChain = al::span{mSideChain}.first(SamplesToDo);
    std::transform(sideChain.begin(), sideChain.end(), sideChain.begin(), process);

    mLastRelease = y_1;
    mLastAttack = y_L;
    mLastGainDev = c_dev;
}

/* Combined with the hold time, a look-ahead delay can improve handling of
 * fast transients by allowing the envelope time to converge prior to
 * reaching the offending impulse.  This is best used when operating as a
 * limiter.
 */
void Compressor::signalDelay(const uint SamplesToDo, const al::span<FloatBufferLine> OutBuffer)
{
    const auto lookAhead = mLookAhead;

    ASSUME(SamplesToDo > 0);
    ASSUME(SamplesToDo <= BufferLineSize);
    ASSUME(lookAhead > 0);
    ASSUME(lookAhead < BufferLineSize);

    auto delays = mDelay.begin();
    for(auto &buffer : OutBuffer)
    {
        const auto inout = al::span{buffer}.first(SamplesToDo);
        const auto delaybuf = al::span{*(delays++)}.first(lookAhead);

        if(SamplesToDo >= delaybuf.size()) LIKELY
        {
            const auto inout_start = inout.end() - ptrdiff_t(delaybuf.size());
            const auto delay_end = std::rotate(inout.begin(), inout_start, inout.end());
            std::swap_ranges(inout.begin(), delay_end, delaybuf.begin());
        }
        else
        {
            auto delay_start = std::swap_ranges(inout.begin(), inout.end(), delaybuf.begin());
            std::rotate(delaybuf.begin(), delay_start, delaybuf.end());
        }
    }
}


std::unique_ptr<Compressor> Compressor::Create(const size_t NumChans, const float SampleRate,
    const bool AutoKnee, const bool AutoAttack, const bool AutoRelease, const bool AutoPostGain,
    const bool AutoDeclip, const float LookAheadTime, const float HoldTime, const float PreGainDb,
    const float PostGainDb, const float ThresholdDb, const float Ratio, const float KneeDb,
    const float AttackTime, const float ReleaseTime)
{
    const auto lookAhead = static_cast<uint>(std::clamp(std::round(LookAheadTime*SampleRate), 0.0f,
        BufferLineSize-1.0f));
    const auto hold = static_cast<uint>(std::clamp(std::round(HoldTime*SampleRate), 0.0f,
        BufferLineSize-1.0f));

    auto Comp = CompressorPtr{new Compressor{}};
    Comp->mAuto.Knee = AutoKnee;
    Comp->mAuto.Attack = AutoAttack;
    Comp->mAuto.Release = AutoRelease;
    Comp->mAuto.PostGain = AutoPostGain;
    Comp->mAuto.Declip = AutoPostGain && AutoDeclip;
    Comp->mLookAhead = lookAhead;
    Comp->mPreGain = std::pow(10.0f, PreGainDb / 20.0f);
    Comp->mPostGain = std::log(10.0f)/20.0f * PostGainDb;
    Comp->mThreshold = std::log(10.0f)/20.0f * ThresholdDb;
    Comp->mSlope = 1.0f / std::max(1.0f, Ratio) - 1.0f;
    Comp->mKnee = std::max(0.0f, std::log(10.0f)/20.0f * KneeDb);
    Comp->mAttack = std::max(1.0f, AttackTime * SampleRate);
    Comp->mRelease = std::max(1.0f, ReleaseTime * SampleRate);

    /* Knee width automation actually treats the compressor as a limiter. By
     * varying the knee width, it can effectively be seen as applying
     * compression over a wide range of ratios.
     */
    if(AutoKnee)
        Comp->mSlope = -1.0f;

    if(lookAhead > 0)
    {
        /* The sliding hold implementation doesn't handle a length of 1. A 1-
         * sample hold is useless anyway, it would only ever give back what was
         * just given to it.
         */
        if(hold > 1)
        {
            Comp->mHold = std::make_unique<SlidingHold>();
            Comp->mHold->mValues[0] = -std::numeric_limits<float>::infinity();
            Comp->mHold->mExpiries[0] = hold;
            Comp->mHold->mLength = hold;
        }
        Comp->mDelay.resize(NumChans, FloatBufferLine{});
    }

    Comp->mCrestCoeff = std::exp(-1.0f / (0.200f * SampleRate)); // 200ms
    Comp->mGainEstimate = Comp->mThreshold * -0.5f * Comp->mSlope;
    Comp->mAdaptCoeff = std::exp(-1.0f / (2.0f * SampleRate)); // 2s

    return Comp;
}

Compressor::~Compressor() = default;


void Compressor::process(const uint SamplesToDo, const al::span<FloatBufferLine> InOut)
{
    ASSUME(SamplesToDo > 0);
    ASSUME(SamplesToDo <= BufferLineSize);

    const float preGain{mPreGain};
    if(preGain != 1.0f)
    {
        auto apply_gain = [SamplesToDo,preGain](FloatBufferLine &input) noexcept -> void
        {
            const auto buffer = assume_aligned_span<16>(al::span{input}.first(SamplesToDo));
            std::transform(buffer.cbegin(), buffer.cend(), buffer.begin(),
                [preGain](const float s) noexcept { return s * preGain; });
        };
        std::for_each(InOut.begin(), InOut.end(), apply_gain);
    }

    linkChannels(SamplesToDo, InOut);

    if(mAuto.Attack || mAuto.Release)
        crestDetector(SamplesToDo);

    if(mHold)
        peakHoldDetector(SamplesToDo);
    else
        peakDetector(SamplesToDo);

    gainCompressor(SamplesToDo);

    if(!mDelay.empty())
        signalDelay(SamplesToDo, InOut);

    const auto gains = assume_aligned_span<16>(al::span{mSideChain}.first(SamplesToDo));
    auto apply_comp = [gains](const FloatBufferSpan inout) noexcept -> void
    {
        const auto buffer = assume_aligned_span<16>(inout);
        std::transform(gains.cbegin(), gains.cend(), buffer.cbegin(), buffer.begin(),
            std::multiplies{});
    };
    for(const FloatBufferSpan inout : InOut)
        apply_comp(inout);

    const auto delayedGains = al::span{mSideChain}.subspan(SamplesToDo, mLookAhead);
    std::copy(delayedGains.begin(), delayedGains.end(), mSideChain.begin());
}
