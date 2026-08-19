#ifndef CORE_MIXER_H
#define CORE_MIXER_H

#include <array>
#include <cmath>
#include <cstddef>

#include "alspan.h"
#include "ambidefs.h"
#include "bufferline.h"

struct MixParams;

/* Mixer functions that handle one input and multiple output channels. */
using MixerOutFunc = void(*)(const al::span<const float> InSamples,
    const al::span<FloatBufferLine> OutBuffer, const al::span<float> CurrentGains,
    const al::span<const float> TargetGains, const std::size_t Counter, const std::size_t OutPos);

extern MixerOutFunc MixSamplesOut;
inline void MixSamples(const al::span<const float> InSamples,
    const al::span<FloatBufferLine> OutBuffer, const al::span<float> CurrentGains,
    const al::span<const float> TargetGains, const std::size_t Counter, const std::size_t OutPos)
{ MixSamplesOut(InSamples, OutBuffer, CurrentGains, TargetGains, Counter, OutPos); }

/* Mixer functions that handle one input and one output channel. */
using MixerOneFunc = void(*)(const al::span<const float> InSamples,const al::span<float> OutBuffer,
    float &CurrentGain, const float TargetGain, const std::size_t Counter);

extern MixerOneFunc MixSamplesOne;
inline void MixSamples(const al::span<const float> InSamples, const al::span<float> OutBuffer,
    float &CurrentGain, const float TargetGain, const std::size_t Counter)
{ MixSamplesOne(InSamples, OutBuffer, CurrentGain, TargetGain, Counter); }


/**
 * Calculates ambisonic encoder coefficients using the X, Y, and Z direction
 * components, which must represent a normalized (unit length) vector, and the
 * spread is the angular width of the sound (0...tau).
 *
 * NOTE: The components use ambisonic coordinates. As a result:
 *
 * Ambisonic Y = OpenAL -X
 * Ambisonic Z = OpenAL Y
 * Ambisonic X = OpenAL -Z
 *
 * The components are ordered such that OpenAL's X, Y, and Z are the first,
 * second, and third parameters respectively -- simply negate X and Z.
 */
std::array<float,MaxAmbiChannels> CalcAmbiCoeffs(const float y, const float z, const float x,
    const float spread);

/**
 * CalcDirectionCoeffs
 *
 * Calculates ambisonic coefficients based on an OpenAL direction vector. The
 * vector must be normalized (unit length), and the spread is the angular width
 * of the sound (0...tau).
 */
inline std::array<float,MaxAmbiChannels> CalcDirectionCoeffs(const al::span<const float,3> dir,
    const float spread)
{
    /* Convert from OpenAL coords to Ambisonics. */
    return CalcAmbiCoeffs(-dir[0], dir[1], -dir[2], spread);
}

/**
 * CalcDirectionCoeffs
 *
 * Calculates ambisonic coefficients based on an OpenAL direction vector. The
 * vector must be normalized (unit length).
 */
constexpr std::array<float,MaxAmbiChannels> CalcDirectionCoeffs(const al::span<const float,3> dir)
{
    /* Convert from OpenAL coords to Ambisonics. */
    return CalcAmbiCoeffs(-dir[0], dir[1], -dir[2]);
}

/**
 * CalcAngleCoeffs
 *
 * Calculates ambisonic coefficients based on azimuth and elevation. The
 * azimuth and elevation parameters are in radians, going right and up
 * respectively.
 */
inline std::array<float,MaxAmbiChannels> CalcAngleCoeffs(const float azimuth,
    const float elevation, const float spread)
{
    const float x{-std::sin(azimuth) * std::cos(elevation)};
    const float y{ std::sin(elevation)};
    const float z{ std::cos(azimuth) * std::cos(elevation)};

    return CalcAmbiCoeffs(x, y, z, spread);
}


/**
 * ComputePanGains
 *
 * Computes panning gains using the given channel decoder coefficients and the
 * pre-calculated direction or angle coefficients. For B-Format sources, the
 * coeffs are a 'slice' of a transform matrix for the input channel, used to
 * scale and orient the sound samples.
 */
void ComputePanGains(const MixParams *mix, const al::span<const float,MaxAmbiChannels> coeffs,
    const float ingain, const al::span<float,MaxAmbiChannels> gains);

#endif /* CORE_MIXER_H */
