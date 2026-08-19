#ifndef CORE_MIXER_DEFS_H
#define CORE_MIXER_DEFS_H

#include <array>
#include <cstdint>
#include <cstdlib>
#include <utility>
#include <variant>

#include "alspan.h"
#include "core/bufferline.h"
#include "core/cubic_defs.h"

struct HrtfChannelState;
struct HrtfFilter;
struct MixHrtfFilter;

using uint = unsigned int;
using float2 = std::array<float,2>;


inline constexpr int MixerFracBits{16};
inline constexpr int MixerFracOne{1 << MixerFracBits};
inline constexpr int MixerFracMask{MixerFracOne - 1};
inline constexpr int MixerFracHalf{MixerFracOne >> 1};

inline constexpr float GainSilenceThreshold{0.00001f}; /* -100dB */


enum class Resampler : std::uint8_t {
    Point,
    Linear,
    Spline,
    Gaussian,
    FastBSinc12,
    BSinc12,
    FastBSinc24,
    BSinc24,

    Max = BSinc24
};

/* Interpolator state. Kind of a misnomer since the interpolator itself is
 * stateless. This just keeps it from having to recompute scale-related
 * mappings for every sample.
 */
struct BsincState {
    float sf; /* Scale interpolation factor. */
    uint m; /* Coefficient count. */
    uint l; /* Left coefficient offset. */
    /* Filter coefficients, followed by the phase, scale, and scale-phase
     * delta coefficients. Starting at phase index 0, each subsequent phase
     * index follows contiguously.
     */
    al::span<const float> filter;
};

struct CubicState {
    /* Filter coefficients, and coefficient deltas. Starting at phase index 0,
     * each subsequent phase index follows contiguously.
     */
    al::span<const CubicCoefficients,CubicPhaseCount> filter;
    CubicState(al::span<const CubicCoefficients,CubicPhaseCount> f) : filter{f} { }
};

using InterpState = std::variant<std::monostate,CubicState,BsincState>;

using ResamplerFunc = void(*)(const InterpState *state, const al::span<const float> src, uint frac,
    const uint increment, const al::span<float> dst);

ResamplerFunc PrepareResampler(Resampler resampler, uint increment, InterpState *state);


template<typename TypeTag, typename InstTag>
void Resample_(const InterpState *state, const al::span<const float> src, uint frac,
    const uint increment, const al::span<float> dst);

template<typename InstTag>
void Mix_(const al::span<const float> InSamples, const al::span<FloatBufferLine> OutBuffer,
    const al::span<float> CurrentGains, const al::span<const float> TargetGains,
    const size_t Counter, const size_t OutPos);
template<typename InstTag>
void Mix_(const al::span<const float> InSamples, const al::span<float> OutBuffer,
    float &CurrentGain, const float TargetGain, const size_t Counter);

template<typename InstTag>
void MixHrtf_(const al::span<const float> InSamples, const al::span<float2> AccumSamples,
    const uint IrSize, const MixHrtfFilter *hrtfparams, const size_t SamplesToDo);
template<typename InstTag>
void MixHrtfBlend_(const al::span<const float> InSamples, const al::span<float2> AccumSamples,
    const uint IrSize, const HrtfFilter *oldparams, const MixHrtfFilter *newparams,
    const size_t SamplesToDo);
template<typename InstTag>
void MixDirectHrtf_(const FloatBufferSpan LeftOut, const FloatBufferSpan RightOut,
    const al::span<const FloatBufferLine> InSamples, const al::span<float2> AccumSamples,
    const al::span<float,BufferLineSize> TempBuf, const al::span<HrtfChannelState> ChanState,
    const size_t IrSize, const size_t SamplesToDo);

/* Vectorized resampler helpers */
template<size_t N>
constexpr void InitPosArrays(uint pos, uint frac, const uint increment,
    const al::span<uint,N> frac_arr, const al::span<uint,N> pos_arr)
{
    static_assert(pos_arr.size() == frac_arr.size());
    pos_arr[0] = pos;
    frac_arr[0] = frac;
    for(size_t i{1};i < pos_arr.size();++i)
    {
        const uint frac_tmp{frac_arr[i-1] + increment};
        pos_arr[i] = pos_arr[i-1] + (frac_tmp>>MixerFracBits);
        frac_arr[i] = frac_tmp&MixerFracMask;
    }
}

#endif /* CORE_MIXER_DEFS_H */
