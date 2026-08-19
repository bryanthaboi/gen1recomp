#include "config.h"

#include <arm_neon.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <limits>
#include <variant>

#include "alnumeric.h"
#include "alspan.h"
#include "core/bsinc_defs.h"
#include "core/bufferline.h"
#include "core/cubic_defs.h"
#include "core/mixer/hrtfdefs.h"
#include "core/resampler_limits.h"
#include "defs.h"
#include "hrtfbase.h"
#include "opthelpers.h"

struct CTag;
struct NEONTag;
struct LerpTag;
struct CubicTag;
struct BSincTag;
struct FastBSincTag;


#if defined(__GNUC__) && !defined(__clang__) && !defined(__ARM_NEON)
#pragma GCC target("fpu=neon")
#endif

using uint = unsigned int;

namespace {

constexpr uint BSincPhaseDiffBits{MixerFracBits - BSincPhaseBits};
constexpr uint BSincPhaseDiffOne{1 << BSincPhaseDiffBits};
constexpr uint BSincPhaseDiffMask{BSincPhaseDiffOne - 1u};

constexpr uint CubicPhaseDiffBits{MixerFracBits - CubicPhaseBits};
constexpr uint CubicPhaseDiffOne{1 << CubicPhaseDiffBits};
constexpr uint CubicPhaseDiffMask{CubicPhaseDiffOne - 1u};

force_inline
void vtranspose4(float32x4_t &x0, float32x4_t &x1, float32x4_t &x2, float32x4_t &x3) noexcept
{
    float32x4x2_t t0_{vzipq_f32(x0, x2)};
    float32x4x2_t t1_{vzipq_f32(x1, x3)};
    float32x4x2_t u0_{vzipq_f32(t0_.val[0], t1_.val[0])};
    float32x4x2_t u1_{vzipq_f32(t0_.val[1], t1_.val[1])};
    x0 = u0_.val[0];
    x1 = u0_.val[1];
    x2 = u1_.val[0];
    x3 = u1_.val[1];
}

inline float32x4_t set_f4(float l0, float l1, float l2, float l3)
{
    float32x4_t ret{vmovq_n_f32(l0)};
    ret = vsetq_lane_f32(l1, ret, 1);
    ret = vsetq_lane_f32(l2, ret, 2);
    ret = vsetq_lane_f32(l3, ret, 3);
    return ret;
}

inline void ApplyCoeffs(const al::span<float2> Values, const size_t IrSize,
    const ConstHrirSpan Coeffs, const float left, const float right)
{
    ASSUME(IrSize >= MinIrLength);
    ASSUME(IrSize <= HrirLength);

    auto dup_samples = [left,right]() -> float32x4_t
    {
        float32x2_t leftright2{vset_lane_f32(right, vmov_n_f32(left), 1)};
        return vcombine_f32(leftright2, leftright2);
    };
    const auto leftright4 = dup_samples();

    /* Using a loop here instead of std::transform since some builds seem to
     * have an issue with accessing an array/span of float32x4_t.
     */
    for(size_t c{0};c < IrSize;c += 2)
    {
        auto vals = vld1q_f32(&Values[c][0]);
        vals = vmlaq_f32(vals, vld1q_f32(&Coeffs[c][0]), leftright4);
        vst1q_f32(&Values[c][0], vals);
    }
}

force_inline void MixLine(const al::span<const float> InSamples, const al::span<float> dst,
    float &CurrentGain, const float TargetGain, const float delta, const size_t fade_len,
    const size_t realign_len, size_t Counter)
{
    const auto step = float{(TargetGain-CurrentGain) * delta};

    auto pos = size_t{0};
    if(std::abs(step) > std::numeric_limits<float>::epsilon())
    {
        const auto gain = float{CurrentGain};
        auto step_count = float{0.0f};
        /* Mix with applying gain steps in aligned multiples of 4. */
        if(const size_t todo{fade_len >> 2})
        {
            const auto four4 = vdupq_n_f32(4.0f);
            const auto step4 = vdupq_n_f32(step);
            const auto gain4 = vdupq_n_f32(gain);
            auto step_count4 = set_f4(0.0f, 1.0f, 2.0f, 3.0f);

            const auto in4 = al::span{reinterpret_cast<const float32x4_t*>(InSamples.data()),
                InSamples.size()/4}.first(todo);
            const auto out4 = al::span{reinterpret_cast<float32x4_t*>(dst.data()), dst.size()/4};
            std::transform(in4.begin(), in4.end(), out4.begin(), out4.begin(),
                [gain4,step4,four4,&step_count4](const float32x4_t val4, float32x4_t dry4)
                {
                    /* dry += val * (gain + step*step_count) */
                    dry4 = vmlaq_f32(dry4, val4, vmlaq_f32(gain4, step4, step_count4));
                    step_count4 = vaddq_f32(step_count4, four4);
                    return dry4;
                });
            pos += in4.size()*4;

            /* NOTE: step_count4 now represents the next four counts after the
             * last four mixed samples, so the lowest element represents the
             * next step count to apply.
             */
            step_count = vgetq_lane_f32(step_count4, 0);
        }
        /* Mix with applying left over gain steps that aren't aligned multiples of 4. */
        if(const size_t leftover{fade_len&3})
        {
            const auto in = InSamples.subspan(pos, leftover);
            const auto out = dst.subspan(pos);

            std::transform(in.begin(), in.end(), out.begin(), out.begin(),
                [gain,step,&step_count](const float val, float dry) noexcept -> float
                {
                    dry += val * (gain + step*step_count);
                    step_count += 1.0f;
                    return dry;
                });
            pos += leftover;
        }
        if(pos < Counter)
        {
            CurrentGain = gain + step*step_count;
            return;
        }

        /* Mix until pos is aligned with 4 or the mix is done. */
        if(const size_t leftover{realign_len&3})
        {
            const auto in = InSamples.subspan(pos, leftover);
            const auto out = dst.subspan(pos);

            std::transform(in.begin(), in.end(), out.begin(), out.begin(),
                [TargetGain](const float val, const float dry) noexcept -> float
                { return dry + val*TargetGain; });
            pos += leftover;
        }
    }
    CurrentGain = TargetGain;

    if(!(std::abs(TargetGain) > GainSilenceThreshold))
        return;
    if(const size_t todo{(InSamples.size()-pos) >> 2})
    {
        const auto in4 = al::span{reinterpret_cast<const float32x4_t*>(InSamples.data()),
            InSamples.size()/4}.last(todo);
        const auto out = dst.subspan(pos);
        const auto out4 = al::span{reinterpret_cast<float32x4_t*>(out.data()), out.size()/4};

        const auto gain4 = vdupq_n_f32(TargetGain);
        std::transform(in4.begin(), in4.end(), out4.begin(), out4.begin(),
            [gain4](const float32x4_t val4, const float32x4_t dry4) -> float32x4_t
            { return vmlaq_f32(dry4, val4, gain4); });
        pos += in4.size()*4;
    }
    if(const size_t leftover{(InSamples.size()-pos)&3})
    {
        const auto in = InSamples.last(leftover);
        const auto out = dst.subspan(pos);

        std::transform(in.begin(), in.end(), out.begin(), out.begin(),
            [TargetGain](const float val, const float dry) noexcept -> float
            { return dry + val*TargetGain; });
    }
}

} // namespace

template<>
void Resample_<LerpTag,NEONTag>(const InterpState*, const al::span<const float> src, uint frac,
    const uint increment, const al::span<float> dst)
{
    ASSUME(frac < MixerFracOne);

    const uint32x4_t increment4 = vdupq_n_u32(increment*4u);
    const float32x4_t fracOne4 = vdupq_n_f32(1.0f/MixerFracOne);
    const uint32x4_t fracMask4 = vdupq_n_u32(MixerFracMask);

    alignas(16) std::array<uint,4> pos_{}, frac_{};
    InitPosArrays(MaxResamplerEdge, frac, increment, al::span{frac_}, al::span{pos_});
    uint32x4_t frac4 = vld1q_u32(frac_.data());
    uint32x4_t pos4 = vld1q_u32(pos_.data());

    auto vecout = al::span{reinterpret_cast<float32x4_t*>(dst.data()), dst.size()/4};
    std::generate(vecout.begin(), vecout.end(), [=,&pos4,&frac4]() -> float32x4_t
    {
        const uint pos0{vgetq_lane_u32(pos4, 0)};
        const uint pos1{vgetq_lane_u32(pos4, 1)};
        const uint pos2{vgetq_lane_u32(pos4, 2)};
        const uint pos3{vgetq_lane_u32(pos4, 3)};
        ASSUME(pos0 <= pos1); ASSUME(pos1 <= pos2); ASSUME(pos2 <= pos3);
        const float32x4_t val1{set_f4(src[pos0], src[pos1], src[pos2], src[pos3])};
        const float32x4_t val2{set_f4(src[pos0+1_uz], src[pos1+1_uz], src[pos2+1_uz], src[pos3+1_uz])};

        /* val1 + (val2-val1)*mu */
        const float32x4_t r0{vsubq_f32(val2, val1)};
        const float32x4_t mu{vmulq_f32(vcvtq_f32_u32(frac4), fracOne4)};
        const float32x4_t out{vmlaq_f32(val1, mu, r0)};

        frac4 = vaddq_u32(frac4, increment4);
        pos4 = vaddq_u32(pos4, vshrq_n_u32(frac4, MixerFracBits));
        frac4 = vandq_u32(frac4, fracMask4);
        return out;
    });

    if(size_t todo{dst.size()&3})
    {
        auto pos = size_t{vgetq_lane_u32(pos4, 0)};
        frac = vgetq_lane_u32(frac4, 0);

        const auto out = dst.last(todo);
        std::generate(out.begin(), out.end(), [&pos,&frac,src,increment]
        {
            const float output{lerpf(src[pos+0], src[pos+1],
                static_cast<float>(frac) * (1.0f/MixerFracOne))};

            frac += increment;
            pos  += frac>>MixerFracBits;
            frac &= MixerFracMask;
            return output;
        });
    }
}

template<>
void Resample_<CubicTag,NEONTag>(const InterpState *state, const al::span<const float> src,
    uint frac, const uint increment, const al::span<float> dst)
{
    ASSUME(frac < MixerFracOne);

    const auto filter = std::get<CubicState>(*state).filter;

    const uint32x4_t increment4{vdupq_n_u32(increment*4u)};
    const uint32x4_t fracMask4{vdupq_n_u32(MixerFracMask)};
    const float32x4_t fracDiffOne4{vdupq_n_f32(1.0f/CubicPhaseDiffOne)};
    const uint32x4_t fracDiffMask4{vdupq_n_u32(CubicPhaseDiffMask)};

    alignas(16) std::array<uint,4> pos_{}, frac_{};
    InitPosArrays(MaxResamplerEdge-1, frac, increment, al::span{frac_}, al::span{pos_});
    uint32x4_t frac4{vld1q_u32(frac_.data())};
    uint32x4_t pos4{vld1q_u32(pos_.data())};

    auto vecout = al::span{reinterpret_cast<float32x4_t*>(dst.data()), dst.size()/4};
    std::generate(vecout.begin(), vecout.end(), [=,&pos4,&frac4]
    {
        const uint pos0{vgetq_lane_u32(pos4, 0)};
        const uint pos1{vgetq_lane_u32(pos4, 1)};
        const uint pos2{vgetq_lane_u32(pos4, 2)};
        const uint pos3{vgetq_lane_u32(pos4, 3)};
        ASSUME(pos0 <= pos1); ASSUME(pos1 <= pos2); ASSUME(pos2 <= pos3);
        const float32x4_t val0{vld1q_f32(&src[pos0])};
        const float32x4_t val1{vld1q_f32(&src[pos1])};
        const float32x4_t val2{vld1q_f32(&src[pos2])};
        const float32x4_t val3{vld1q_f32(&src[pos3])};

        const uint32x4_t pi4{vshrq_n_u32(frac4, CubicPhaseDiffBits)};
        const uint pi0{vgetq_lane_u32(pi4, 0)}; ASSUME(pi0 < CubicPhaseCount);
        const uint pi1{vgetq_lane_u32(pi4, 1)}; ASSUME(pi1 < CubicPhaseCount);
        const uint pi2{vgetq_lane_u32(pi4, 2)}; ASSUME(pi2 < CubicPhaseCount);
        const uint pi3{vgetq_lane_u32(pi4, 3)}; ASSUME(pi3 < CubicPhaseCount);

        const float32x4_t pf4{vmulq_f32(vcvtq_f32_u32(vandq_u32(frac4, fracDiffMask4)),
            fracDiffOne4)};

        float32x4_t r0{vmulq_f32(val0,
            vmlaq_f32(vld1q_f32(filter[pi0].mCoeffs.data()), vdupq_lane_f32(vget_low_f32(pf4), 0),
                vld1q_f32(filter[pi0].mDeltas.data())))};
        float32x4_t r1{vmulq_f32(val1,
            vmlaq_f32(vld1q_f32(filter[pi1].mCoeffs.data()), vdupq_lane_f32(vget_low_f32(pf4), 1),
                vld1q_f32(filter[pi1].mDeltas.data())))};
        float32x4_t r2{vmulq_f32(val2,
            vmlaq_f32(vld1q_f32(filter[pi2].mCoeffs.data()), vdupq_lane_f32(vget_high_f32(pf4), 0),
                vld1q_f32(filter[pi2].mDeltas.data())))};
        float32x4_t r3{vmulq_f32(val3,
            vmlaq_f32(vld1q_f32(filter[pi3].mCoeffs.data()), vdupq_lane_f32(vget_high_f32(pf4), 1),
                vld1q_f32(filter[pi3].mDeltas.data())))};

        vtranspose4(r0, r1, r2, r3);
        r0 = vaddq_f32(vaddq_f32(r0, r1), vaddq_f32(r2, r3));

        frac4 = vaddq_u32(frac4, increment4);
        pos4 = vaddq_u32(pos4, vshrq_n_u32(frac4, MixerFracBits));
        frac4 = vandq_u32(frac4, fracMask4);
        return r0;
    });

    if(const size_t todo{dst.size()&3})
    {
        auto pos = size_t{vgetq_lane_u32(pos4, 0)};
        frac = vgetq_lane_u32(frac4, 0);

        auto out = dst.last(todo);
        std::generate(out.begin(), out.end(), [&pos,&frac,src,increment,filter]
        {
            const uint pi{frac >> CubicPhaseDiffBits}; ASSUME(pi < CubicPhaseCount);
            const float pf{static_cast<float>(frac&CubicPhaseDiffMask) * (1.0f/CubicPhaseDiffOne)};
            const float32x4_t pf4{vdupq_n_f32(pf)};

            const float32x4_t f4{vmlaq_f32(vld1q_f32(filter[pi].mCoeffs.data()), pf4,
                vld1q_f32(filter[pi].mDeltas.data()))};
            float32x4_t r4{vmulq_f32(f4, vld1q_f32(&src[pos]))};

            r4 = vaddq_f32(r4, vrev64q_f32(r4));
            const float output{vget_lane_f32(vadd_f32(vget_low_f32(r4), vget_high_f32(r4)), 0)};

            frac += increment;
            pos  += frac>>MixerFracBits;
            frac &= MixerFracMask;
            return output;
        });
    }
}

template<>
void Resample_<BSincTag,NEONTag>(const InterpState *state, const al::span<const float> src,
    uint frac, const uint increment, const al::span<float> dst)
{
    const auto &bsinc = std::get<BsincState>(*state);
    const auto sf4 = vdupq_n_f32(bsinc.sf);
    const auto m = size_t{bsinc.m};
    ASSUME(m > 0);
    ASSUME(m <= MaxResamplerPadding);
    ASSUME(frac < MixerFracOne);

    const auto filter = bsinc.filter.first(4_uz*BSincPhaseCount*m);

    ASSUME(bsinc.l <= MaxResamplerEdge);
    auto pos = size_t{MaxResamplerEdge-bsinc.l};
    std::generate(dst.begin(), dst.end(), [&pos,&frac,src,increment,sf4,m,filter]() -> float
    {
        // Calculate the phase index and factor.
        const uint pi{frac >> BSincPhaseDiffBits}; ASSUME(pi < BSincPhaseCount);
        const float pf{static_cast<float>(frac&BSincPhaseDiffMask) * (1.0f/BSincPhaseDiffOne)};

        // Apply the scale and phase interpolated filter.
        float32x4_t r4{vdupq_n_f32(0.0f)};
        {
            const float32x4_t pf4{vdupq_n_f32(pf)};
            const auto fil = filter.subspan(2_uz*pi*m);
            const auto phd = fil.subspan(m);
            const auto scd = fil.subspan(2_uz*BSincPhaseCount*m);
            const auto spd = scd.subspan(m);
            size_t td{m >> 2};
            size_t j{0u};

            do {
                /* f = ((fil + sf*scd) + pf*(phd + sf*spd)) */
                const float32x4_t f4 = vmlaq_f32(
                    vmlaq_f32(vld1q_f32(&fil[j]), sf4, vld1q_f32(&scd[j])),
                    pf4, vmlaq_f32(vld1q_f32(&phd[j]), sf4, vld1q_f32(&spd[j])));
                /* r += f*src */
                r4 = vmlaq_f32(r4, f4, vld1q_f32(&src[pos+j]));
                j += 4;
            } while(--td);
        }
        r4 = vaddq_f32(r4, vrev64q_f32(r4));
        const float output{vget_lane_f32(vadd_f32(vget_low_f32(r4), vget_high_f32(r4)), 0)};

        frac += increment;
        pos  += frac>>MixerFracBits;
        frac &= MixerFracMask;
        return output;
    });
}

template<>
void Resample_<FastBSincTag,NEONTag>(const InterpState *state, const al::span<const float> src,
    uint frac, const uint increment, const al::span<float> dst)
{
    const auto &bsinc = std::get<BsincState>(*state);
    const auto m = size_t{bsinc.m};
    ASSUME(m > 0);
    ASSUME(m <= MaxResamplerPadding);
    ASSUME(frac < MixerFracOne);

    const auto filter = bsinc.filter.first(2_uz*BSincPhaseCount*m);

    ASSUME(bsinc.l <= MaxResamplerEdge);
    auto pos = size_t{MaxResamplerEdge-bsinc.l};
    std::generate(dst.begin(), dst.end(), [&pos,&frac,src,increment,m,filter]() -> float
    {
        // Calculate the phase index and factor.
        const uint pi{frac >> BSincPhaseDiffBits}; ASSUME(pi < BSincPhaseCount);
        const float pf{static_cast<float>(frac&BSincPhaseDiffMask) * (1.0f/BSincPhaseDiffOne)};

        // Apply the phase interpolated filter.
        float32x4_t r4{vdupq_n_f32(0.0f)};
        {
            const float32x4_t pf4{vdupq_n_f32(pf)};
            const auto fil = filter.subspan(2_uz*pi*m);
            const auto phd = fil.subspan(m);
            size_t td{m >> 2};
            size_t j{0u};

            do {
                /* f = fil + pf*phd */
                const float32x4_t f4 = vmlaq_f32(vld1q_f32(&fil[j]), pf4, vld1q_f32(&phd[j]));
                /* r += f*src */
                r4 = vmlaq_f32(r4, f4, vld1q_f32(&src[pos+j]));
                j += 4;
            } while(--td);
        }
        r4 = vaddq_f32(r4, vrev64q_f32(r4));
        const float output{vget_lane_f32(vadd_f32(vget_low_f32(r4), vget_high_f32(r4)), 0)};

        frac += increment;
        pos  += frac>>MixerFracBits;
        frac &= MixerFracMask;
        return output;
    });
}


template<>
void MixHrtf_<NEONTag>(const al::span<const float> InSamples, const al::span<float2> AccumSamples,
    const uint IrSize, const MixHrtfFilter *hrtfparams, const size_t SamplesToDo)
{ MixHrtfBase<ApplyCoeffs>(InSamples, AccumSamples, IrSize, hrtfparams, SamplesToDo); }

template<>
void MixHrtfBlend_<NEONTag>(const al::span<const float> InSamples,
    const al::span<float2> AccumSamples, const uint IrSize, const HrtfFilter *oldparams,
    const MixHrtfFilter *newparams, const size_t SamplesToDo)
{
    MixHrtfBlendBase<ApplyCoeffs>(InSamples, AccumSamples, IrSize, oldparams, newparams,
        SamplesToDo);
}

template<>
void MixDirectHrtf_<NEONTag>(const FloatBufferSpan LeftOut, const FloatBufferSpan RightOut,
    const al::span<const FloatBufferLine> InSamples, const al::span<float2> AccumSamples,
    const al::span<float,BufferLineSize> TempBuf, const al::span<HrtfChannelState> ChanState,
    const size_t IrSize, const size_t SamplesToDo)
{
    MixDirectHrtfBase<ApplyCoeffs>(LeftOut, RightOut, InSamples, AccumSamples, TempBuf, ChanState,
        IrSize, SamplesToDo);
}


template<>
void Mix_<NEONTag>(const al::span<const float> InSamples,const al::span<FloatBufferLine> OutBuffer,
    const al::span<float> CurrentGains, const al::span<const float> TargetGains,
    const size_t Counter, const size_t OutPos)
{
    if((OutPos&3) != 0) UNLIKELY
        return Mix_<CTag>(InSamples, OutBuffer, CurrentGains, TargetGains, Counter, OutPos);

    const float delta{(Counter > 0) ? 1.0f / static_cast<float>(Counter) : 0.0f};
    const auto fade_len = std::min(Counter, InSamples.size());
    const auto realign_len = std::min((fade_len+3_uz) & ~3_uz, InSamples.size()) - fade_len;

    auto curgains = CurrentGains.begin();
    auto targetgains = TargetGains.cbegin();
    for(FloatBufferLine &output : OutBuffer)
        MixLine(InSamples, al::span{output}.subspan(OutPos), *curgains++, *targetgains++, delta,
            fade_len, realign_len, Counter);
}

template<>
void Mix_<NEONTag>(const al::span<const float> InSamples, const al::span<float> OutBuffer,
    float &CurrentGain, const float TargetGain, const size_t Counter)
{
    if((reinterpret_cast<uintptr_t>(OutBuffer.data())&15) != 0) UNLIKELY
        return Mix_<CTag>(InSamples, OutBuffer, CurrentGain, TargetGain, Counter);

    const float delta{(Counter > 0) ? 1.0f / static_cast<float>(Counter) : 0.0f};
    const auto fade_len = std::min(Counter, InSamples.size());
    const auto realign_len = std::min((fade_len+3_uz) & ~3_uz, InSamples.size()) - fade_len;

    MixLine(InSamples, OutBuffer, CurrentGain, TargetGain, delta, fade_len, realign_len, Counter);
}
