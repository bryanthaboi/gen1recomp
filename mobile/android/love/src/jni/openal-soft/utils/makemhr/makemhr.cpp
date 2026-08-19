/*
 * HRTF utility for producing and demonstrating the process of creating an
 * OpenAL Soft compatible HRIR data set.
 *
 * Copyright (C) 2011-2019  Christopher Fitzgerald
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Or visit:  http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 *
 * --------------------------------------------------------------------------
 *
 * A big thanks goes out to all those whose work done in the field of
 * binaural sound synthesis using measured HRTFs makes this utility and the
 * OpenAL Soft implementation possible.
 *
 * The algorithm for diffuse-field equalization was adapted from the work
 * done by Rio Emmanuel and Larcher Veronique of IRCAM and Bill Gardner of
 * MIT Media Laboratory.  It operates as follows:
 *
 *  1.  Take the FFT of each HRIR and only keep the magnitude responses.
 *  2.  Calculate the diffuse-field power-average of all HRIRs weighted by
 *      their contribution to the total surface area covered by their
 *      measurement. This has since been modified to use coverage volume for
 *      multi-field HRIR data sets.
 *  3.  Take the diffuse-field average and limit its magnitude range.
 *  4.  Equalize the responses by using the inverse of the diffuse-field
 *      average.
 *  5.  Reconstruct the minimum-phase responses.
 *  5.  Zero the DC component.
 *  6.  IFFT the result and truncate to the desired-length minimum-phase FIR.
 *
 * The spherical head algorithm for calculating propagation delay was adapted
 * from the paper:
 *
 *  Modeling Interaural Time Difference Assuming a Spherical Head
 *  Joel David Miller
 *  Music 150, Musical Acoustics, Stanford University
 *  December 2, 2001
 *
 * The formulae for calculating the Kaiser window metrics are from the
 * the textbook:
 *
 *  Discrete-Time Signal Processing
 *  Alan V. Oppenheim and Ronald W. Schafer
 *  Prentice-Hall Signal Processing Series
 *  1999
 */

#define _UNICODE /* NOLINT(bugprone-reserved-identifier) */
#include "config.h"

#include "makemhr.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <limits>
#include <memory>
#include <numeric>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

#include "alcomplex.h"
#include "alnumbers.h"
#include "alnumeric.h"
#include "alspan.h"
#include "alstring.h"
#include "loaddef.h"
#include "loadsofa.h"

#include "win_main_utf8.h"


HrirDataT::~HrirDataT() = default;

namespace {

using namespace std::string_view_literals;

struct FileDeleter {
    void operator()(gsl::owner<FILE*> f) { fclose(f); }
};
using FilePtr = std::unique_ptr<FILE,FileDeleter>;

// The epsilon used to maintain signal stability.
constexpr double Epsilon{1e-9};

// The limits to the FFT window size override on the command line.
constexpr uint MinFftSize{65536};
constexpr uint MaxFftSize{131072};

// The limits to the equalization range limit on the command line.
constexpr double MinLimit{2.0};
constexpr double MaxLimit{120.0};

// The limits to the truncation window size on the command line.
constexpr uint MinTruncSize{16};
constexpr uint MaxTruncSize{128};

// The limits to the custom head radius on the command line.
constexpr double MinCustomRadius{0.05};
constexpr double MaxCustomRadius{0.15};

// The maximum propagation delay value supported by OpenAL Soft.
constexpr double MaxHrtd{63.0};

// The OpenAL Soft HRTF format marker.  It stands for minimum-phase head
// response protocol 03.
constexpr auto GetMHRMarker() noexcept { return "MinPHR03"sv; }


// Head model used for calculating the impulse delays.
enum HeadModelT {
    HM_None,
    HM_Dataset, // Measure the onset from the dataset.
    HM_Sphere,   // Calculate the onset using a spherical head model.

    HM_Default = HM_Dataset
};


// The defaults for the command line options.
constexpr uint DefaultFftSize{65536};
constexpr bool DefaultEqualize{true};
constexpr bool DefaultSurface{true};
constexpr double DefaultLimit{24.0};
constexpr uint DefaultTruncSize{64};
constexpr double DefaultCustomRadius{0.0};

/* Channel index enums. Mono uses LeftChannel only. */
enum ChannelIndex : uint {
    LeftChannel = 0u,
    RightChannel = 1u
};


/* Performs a string substitution.  Any case-insensitive occurrences of the
 * pattern string are replaced with the replacement string.  The result is
 * truncated if necessary.
 */
auto StrSubst(std::string_view in, const std::string_view pat, const std::string_view rep) -> std::string
{
    std::string ret;
    ret.reserve(in.size() + pat.size());

    while(in.size() >= pat.size())
    {
        if(al::starts_with(in, pat))
        {
            in = in.substr(pat.size());
            ret += rep;
        }
        else
        {
            size_t endpos{1};
            while(endpos < in.size() && std::toupper(in[endpos]) != std::toupper(pat.front()))
                ++endpos;
            ret += in.substr(0, endpos);
            in = in.substr(endpos);
        }
    }
    ret += in;

    return ret;
}


/*********************
 *** Math routines ***
 *********************/

// Simple clamp routine.
double Clamp(const double val, const double lower, const double upper)
{
    return std::min(std::max(val, lower), upper);
}

inline uint dither_rng(uint *seed)
{
    *seed = *seed * 96314165 + 907633515;
    return *seed;
}

// Performs a triangular probability density function dither. The input samples
// should be normalized (-1 to +1).
void TpdfDither(const al::span<double> out, const al::span<const double> in, const double scale,
    const size_t channel, const size_t step, uint *seed)
{
    static constexpr double PRNG_SCALE = 1.0 / std::numeric_limits<uint>::max();
    assert(channel < step);

    for(size_t i{0};i < in.size();++i)
    {
        uint prn0{dither_rng(seed)};
        uint prn1{dither_rng(seed)};
        out[i*step + channel] = std::round(in[i]*scale + (prn0*PRNG_SCALE - prn1*PRNG_SCALE));
    }
}

/* Apply a range limit (in dB) to the given magnitude response.  This is used
 * to adjust the effects of the diffuse-field average on the equalization
 * process.
 */
void LimitMagnitudeResponse(const uint n, const uint m, const double limit,
    const al::span<double> inout)
{
    const double halfLim{limit / 2.0};
    // Convert the response to dB.
    for(uint i{0};i < m;++i)
        inout[i] = 20.0 * std::log10(inout[i]);
    // Use six octaves to calculate the average magnitude of the signal.
    const auto lower = (static_cast<uint>(std::ceil(n / std::pow(2.0, 8.0)))) - 1;
    const auto upper = (static_cast<uint>(std::floor(n / std::pow(2.0, 2.0)))) - 1;
    double ave{0.0};
    for(uint i{lower};i <= upper;++i)
        ave += inout[i];
    ave /= upper - lower + 1;
    // Keep the response within range of the average magnitude.
    for(uint i{0};i < m;++i)
        inout[i] = Clamp(inout[i], ave - halfLim, ave + halfLim);
    // Convert the response back to linear magnitude.
    for(uint i{0};i < m;++i)
        inout[i] = std::pow(10.0, inout[i] / 20.0);
}

/* Reconstructs the minimum-phase component for the given magnitude response
 * of a signal.  This is equivalent to phase recomposition, sans the missing
 * residuals (which were discarded).  The mirrored half of the response is
 * reconstructed.
 */
void MinimumPhase(const al::span<double> mags, const al::span<complex_d> out)
{
    assert(mags.size() == out.size());
    const size_t m{(mags.size()/2) + 1};

    size_t i;
    for(i = 0;i < m;i++)
        out[i] = std::log(mags[i]);
    for(;i < mags.size();++i)
    {
        mags[i] = mags[mags.size() - i];
        out[i] = out[mags.size() - i];
    }
    complex_hilbert(out);
    // Remove any DC offset the filter has.
    mags[0] = Epsilon;
    for(i = 0;i < mags.size();++i)
        out[i] = std::polar(mags[i], out[i].imag());
}


/***************************
 *** File storage output ***
 ***************************/

// Write an ASCII string to a file.
auto WriteAscii(const std::string_view out, std::ostream &ostream, const std::string_view filename) -> int
{
    if(!ostream.write(out.data(), std::streamsize(out.size())) || ostream.bad())
    {
        fprintf(stderr, "\nError: Bad write to file '%.*s'.\n", al::sizei(filename),
            filename.data());
        return 0;
    }
    return 1;
}

// Write a binary value of the given byte order and byte size to a file,
// loading it from a 32-bit unsigned integer.
auto WriteBin4(const uint bytes, const uint32_t in, std::ostream &ostream,
    const std::string_view filename) -> int
{
    std::array<char,4> out{};
    for(uint i{0};i < bytes;i++)
        out[i] = static_cast<char>((in>>(i*8)) & 0x000000FF);

    if(!ostream.write(out.data(), std::streamsize(bytes)) || ostream.bad())
    {
        fprintf(stderr, "\nError: Bad write to file '%.*s'.\n", al::sizei(filename),
            filename.data());
        return 0;
    }
    return 1;
}

// Store the OpenAL Soft HRTF data set.
auto StoreMhr(const HrirDataT *hData, const std::string_view filename) -> bool
{
    const uint channels{(hData->mChannelType == CT_STEREO) ? 2u : 1u};
    const uint n{hData->mIrPoints};
    uint dither_seed{22222};

    auto ostream = std::ofstream{std::filesystem::u8path(filename), std::ios::binary};
    if(!ostream.is_open())
    {
        fprintf(stderr, "\nError: Could not open MHR file '%.*s'.\n", al::sizei(filename),
            filename.data());
        return false;
    }
    if(!WriteAscii(GetMHRMarker(), ostream, filename))
        return false;
    if(!WriteBin4(4, hData->mIrRate, ostream, filename))
        return false;
    if(!WriteBin4(1, static_cast<uint32_t>(hData->mChannelType), ostream, filename))
        return false;
    if(!WriteBin4(1, hData->mIrPoints, ostream, filename))
        return false;
    if(!WriteBin4(1, static_cast<uint>(hData->mFds.size()), ostream, filename))
        return false;
    for(size_t fi{hData->mFds.size()-1};fi < hData->mFds.size();--fi)
    {
        auto fdist = static_cast<uint32_t>(std::round(1000.0 * hData->mFds[fi].mDistance));
        if(!WriteBin4(2, fdist, ostream, filename))
            return false;
        if(!WriteBin4(1, static_cast<uint32_t>(hData->mFds[fi].mEvs.size()), ostream, filename))
            return false;
        for(size_t ei{0};ei < hData->mFds[fi].mEvs.size();++ei)
        {
            const auto &elev = hData->mFds[fi].mEvs[ei];
            if(!WriteBin4(1, static_cast<uint32_t>(elev.mAzs.size()), ostream, filename))
                return false;
        }
    }

    for(size_t fi{hData->mFds.size()-1};fi < hData->mFds.size();--fi)
    {
        static constexpr double scale{8388607.0};
        static constexpr uint bps{3u};

        for(const auto &evd : hData->mFds[fi].mEvs)
        {
            for(const auto &azd : evd.mAzs)
            {
                std::array<double,MaxTruncSize*2_uz> out{};

                TpdfDither(out, azd.mIrs[0].first(n), scale, 0, channels, &dither_seed);
                if(hData->mChannelType == CT_STEREO)
                    TpdfDither(out, azd.mIrs[1].first(n), scale, 1, channels, &dither_seed);
                const size_t numsamples{size_t{channels} * n};
                for(size_t i{0};i < numsamples;i++)
                {
                    const auto v = static_cast<int>(Clamp(out[i], -scale-1.0, scale));
                    if(!WriteBin4(bps, static_cast<uint32_t>(v), ostream, filename))
                        return false;
                }
            }
        }
    }
    for(size_t fi{hData->mFds.size()-1};fi < hData->mFds.size();--fi)
    {
        /* Delay storage has 2 bits of extra precision. */
        static constexpr double DelayPrecScale{4.0};
        for(const auto &evd : hData->mFds[fi].mEvs)
        {
            for(const auto &azd : evd.mAzs)
            {
                auto v = static_cast<uint>(std::round(azd.mDelays[0]*DelayPrecScale));
                if(!WriteBin4(1, v, ostream, filename)) return false;
                if(hData->mChannelType == CT_STEREO)
                {
                    v = static_cast<uint>(std::round(azd.mDelays[1]*DelayPrecScale));
                    if(!WriteBin4(1, v, ostream, filename)) return false;
                }
            }
        }
    }
    return true;
}


/***********************
 *** HRTF processing ***
 ***********************/

/* Balances the maximum HRIR magnitudes of multi-field data sets by
 * independently normalizing each field in relation to the overall maximum.
 * This is done to ignore distance attenuation.
 */
void BalanceFieldMagnitudes(const HrirDataT *hData, const uint channels, const uint m)
{
    std::array<double,MAX_FD_COUNT> maxMags{};
    double maxMag{0.0};

    for(size_t fi{0};fi < hData->mFds.size();++fi)
    {
        for(size_t ei{hData->mFds[fi].mEvStart};ei < hData->mFds[fi].mEvs.size();++ei)
        {
            for(const auto &azd : hData->mFds[fi].mEvs[ei].mAzs)
            {
                for(size_t ti{0};ti < channels;++ti)
                {
                    for(size_t i{0};i < m;++i)
                        maxMags[fi] = std::max(azd.mIrs[ti][i], maxMags[fi]);
                }
            }
        }

        maxMag = std::max(maxMags[fi], maxMag);
    }

    for(size_t fi{0};fi < hData->mFds.size();++fi)
    {
        const double magFactor{maxMag / maxMags[fi]};

        for(size_t ei{hData->mFds[fi].mEvStart};ei < hData->mFds[fi].mEvs.size();++ei)
        {
            for(const auto &azd : hData->mFds[fi].mEvs[ei].mAzs)
            {
                for(size_t ti{0};ti < channels;++ti)
                {
                    for(size_t i{0};i < m;++i)
                        azd.mIrs[ti][i] *= magFactor;
                }
            }
        }
    }
}

/* Calculate the contribution of each HRIR to the diffuse-field average based
 * on its coverage volume.  All volumes are centered at the spherical HRIR
 * coordinates and measured by extruded solid angle.
 */
void CalculateDfWeights(const HrirDataT *hData, const al::span<double> weights)
{
    double sum, innerRa, outerRa, evs, ev, upperEv, lowerEv;
    double solidAngle, solidVolume;
    uint fi, ei;

    sum = 0.0;
    // The head radius acts as the limit for the inner radius.
    innerRa = hData->mRadius;
    for(fi = 0;fi < hData->mFds.size();fi++)
    {
        // Each volume ends half way between progressive field measurements.
        if((fi + 1) < hData->mFds.size())
            outerRa = 0.5f * (hData->mFds[fi].mDistance + hData->mFds[fi + 1].mDistance);
        // The final volume has its limit extended to some practical value.
        // This is done to emphasize the far-field responses in the average.
        else
            outerRa = 10.0f;

        const double raPowDiff{std::pow(outerRa, 3.0) - std::pow(innerRa, 3.0)};
        evs = al::numbers::pi / 2.0 / static_cast<double>(hData->mFds[fi].mEvs.size() - 1);
        for(ei = hData->mFds[fi].mEvStart;ei < hData->mFds[fi].mEvs.size();ei++)
        {
            const auto &elev = hData->mFds[fi].mEvs[ei];
            // For each elevation, calculate the upper and lower limits of
            // the patch band.
            ev = elev.mElevation;
            lowerEv = std::max(-al::numbers::pi / 2.0, ev - evs);
            upperEv = std::min(al::numbers::pi / 2.0, ev + evs);
            // Calculate the surface area of the patch band.
            solidAngle = 2.0 * al::numbers::pi * (std::sin(upperEv) - std::sin(lowerEv));
            // Then the volume of the extruded patch band.
            solidVolume = solidAngle * raPowDiff / 3.0;
            // Each weight is the volume of one extruded patch.
            weights[(fi*MAX_EV_COUNT) + ei] = solidVolume / static_cast<double>(elev.mAzs.size());
            // Sum the total coverage volume of the HRIRs for all fields.
            sum += solidAngle;
        }

        innerRa = outerRa;
    }

    for(fi = 0;fi < hData->mFds.size();fi++)
    {
        // Normalize the weights given the total surface coverage for all
        // fields.
        for(ei = hData->mFds[fi].mEvStart;ei < hData->mFds[fi].mEvs.size();ei++)
            weights[(fi * MAX_EV_COUNT) + ei] /= sum;
    }
}

/* Calculate the diffuse-field average from the given magnitude responses of
 * the HRIR set.  Weighting can be applied to compensate for the varying
 * coverage of each HRIR.  The final average can then be limited by the
 * specified magnitude range (in positive dB; 0.0 to skip).
 */
void CalculateDiffuseFieldAverage(const HrirDataT *hData, const uint channels, const uint m,
    const bool weighted, const double limit, const al::span<double> dfa)
{
    std::vector<double> weights(hData->mFds.size() * MAX_EV_COUNT);
    uint count;

    if(weighted)
    {
        // Use coverage weighting to calculate the average.
        CalculateDfWeights(hData, weights);
    }
    else
    {
        double weight;

        // If coverage weighting is not used, the weights still need to be
        // averaged by the number of existing HRIRs.
        count = hData->mIrCount;
        for(size_t fi{0};fi < hData->mFds.size();++fi)
        {
            for(size_t ei{0};ei < hData->mFds[fi].mEvStart;++ei)
                count -= static_cast<uint>(hData->mFds[fi].mEvs[ei].mAzs.size());
        }
        weight = 1.0 / count;

        for(size_t fi{0};fi < hData->mFds.size();++fi)
        {
            for(size_t ei{hData->mFds[fi].mEvStart};ei < hData->mFds[fi].mEvs.size();++ei)
                weights[(fi * MAX_EV_COUNT) + ei] = weight;
        }
    }
    for(size_t ti{0};ti < channels;++ti)
    {
        for(size_t i{0};i < m;++i)
            dfa[(ti * m) + i] = 0.0;
        for(size_t fi{0};fi < hData->mFds.size();++fi)
        {
            for(size_t ei{hData->mFds[fi].mEvStart};ei < hData->mFds[fi].mEvs.size();++ei)
            {
                for(size_t ai{0};ai < hData->mFds[fi].mEvs[ei].mAzs.size();++ai)
                {
                    HrirAzT *azd = &hData->mFds[fi].mEvs[ei].mAzs[ai];
                    // Get the weight for this HRIR's contribution.
                    double weight = weights[(fi * MAX_EV_COUNT) + ei];

                    // Add this HRIR's weighted power average to the total.
                    for(size_t i{0};i < m;++i)
                        dfa[(ti * m) + i] += weight * azd->mIrs[ti][i] * azd->mIrs[ti][i];
                }
            }
        }
        // Finish the average calculation and keep it from being too small.
        for(size_t i{0};i < m;++i)
            dfa[(ti * m) + i] = std::max(sqrt(dfa[(ti * m) + i]), Epsilon);
        // Apply a limit to the magnitude range of the diffuse-field average
        // if desired.
        if(limit > 0.0)
            LimitMagnitudeResponse(hData->mFftSize, m, limit, dfa.subspan(ti * m));
    }
}

// Perform diffuse-field equalization on the magnitude responses of the HRIR
// set using the given average response.
void DiffuseFieldEqualize(const uint channels, const uint m, const al::span<const double> dfa,
    const HrirDataT *hData)
{
    for(size_t fi{0};fi < hData->mFds.size();++fi)
    {
        for(size_t ei{hData->mFds[fi].mEvStart};ei < hData->mFds[fi].mEvs.size();++ei)
        {
            for(auto &azd : hData->mFds[fi].mEvs[ei].mAzs)
            {
                for(size_t ti{0};ti < channels;++ti)
                {
                    for(size_t i{0};i < m;++i)
                        azd.mIrs[ti][i] /= dfa[(ti * m) + i];
                }
            }
        }
    }
}

/* Given field and elevation indices and an azimuth, calculate the indices of
 * the two HRIRs that bound the coordinate along with a factor for
 * calculating the continuous HRIR using interpolation.
 */
void CalcAzIndices(const HrirFdT &field, const uint ei, const double az, uint *a0, uint *a1, double *af)
{
    double f{(2.0*al::numbers::pi + az) * static_cast<double>(field.mEvs[ei].mAzs.size()) /
        (2.0*al::numbers::pi)};
    const uint i{static_cast<uint>(f) % static_cast<uint>(field.mEvs[ei].mAzs.size())};

    f -= std::floor(f);
    *a0 = i;
    *a1 = (i + 1) % static_cast<uint>(field.mEvs[ei].mAzs.size());
    *af = f;
}

/* Synthesize any missing onset timings at the bottom elevations of each field.
 * This just mirrors some top elevations for the bottom, and blends the
 * remaining elevations (not an accurate model).
 */
void SynthesizeOnsets(HrirDataT *hData)
{
    const uint channels{(hData->mChannelType == CT_STEREO) ? 2u : 1u};

    auto proc_field = [channels](HrirFdT &field) -> void
    {
        /* Get the starting elevation from the measurements, and use it as the
         * upper elevation limit for what needs to be calculated.
         */
        const uint upperElevReal{field.mEvStart};
        if(upperElevReal <= 0) return;

        /* Get the lowest half of the missing elevations' delays by mirroring
         * the top elevation delays. The responses are on a spherical grid
         * centered between the ears, so these should align.
         */
        uint ei{};
        if(channels > 1)
        {
            /* Take the polar opposite position of the desired measurement and
             * swap the ears.
             */
            field.mEvs[0].mAzs[0].mDelays[0] = field.mEvs[field.mEvs.size()-1].mAzs[0].mDelays[1];
            field.mEvs[0].mAzs[0].mDelays[1] = field.mEvs[field.mEvs.size()-1].mAzs[0].mDelays[0];
            for(ei = 1u;ei < (upperElevReal+1)/2;++ei)
            {
                const uint topElev{static_cast<uint>(field.mEvs.size()-ei-1)};

                for(uint ai{0u};ai < field.mEvs[ei].mAzs.size();ai++)
                {
                    uint a0, a1;
                    double af;

                    /* Rotate this current azimuth by a half-circle, and lookup
                     * the mirrored elevation to find the indices for the polar
                     * opposite position (may need blending).
                     */
                    const double az{field.mEvs[ei].mAzs[ai].mAzimuth + al::numbers::pi};
                    CalcAzIndices(field, topElev, az, &a0, &a1, &af);

                    /* Blend the delays, and again, swap the ears. */
                    field.mEvs[ei].mAzs[ai].mDelays[0] = Lerp(
                        field.mEvs[topElev].mAzs[a0].mDelays[1],
                        field.mEvs[topElev].mAzs[a1].mDelays[1], af);
                    field.mEvs[ei].mAzs[ai].mDelays[1] = Lerp(
                        field.mEvs[topElev].mAzs[a0].mDelays[0],
                        field.mEvs[topElev].mAzs[a1].mDelays[0], af);
                }
            }
        }
        else
        {
            field.mEvs[0].mAzs[0].mDelays[0] = field.mEvs[field.mEvs.size()-1].mAzs[0].mDelays[0];
            for(ei = 1u;ei < (upperElevReal+1)/2;++ei)
            {
                const uint topElev{static_cast<uint>(field.mEvs.size()-ei-1)};

                for(uint ai{0u};ai < field.mEvs[ei].mAzs.size();ai++)
                {
                    uint a0, a1;
                    double af;

                    /* For mono data sets, mirror the azimuth front<->back
                     * since the other ear is a mirror of what we have (e.g.
                     * the left ear's back-left is simulated with the right
                     * ear's front-right, which uses the left ear's front-left
                     * measurement).
                     */
                    double az{field.mEvs[ei].mAzs[ai].mAzimuth};
                    if(az <= al::numbers::pi) az = al::numbers::pi - az;
                    else az = (al::numbers::pi*2.0)-az + al::numbers::pi;
                    CalcAzIndices(field, topElev, az, &a0, &a1, &af);

                    field.mEvs[ei].mAzs[ai].mDelays[0] = Lerp(
                        field.mEvs[topElev].mAzs[a0].mDelays[0],
                        field.mEvs[topElev].mAzs[a1].mDelays[0], af);
                }
            }
        }
        /* Record the lowest elevation filled in with the mirrored top. */
        const uint lowerElevFake{ei-1u};

        /* Fill in the remaining delays using bilinear interpolation. This
         * helps smooth the transition back to the real delays.
         */
        for(;ei < upperElevReal;++ei)
        {
            const double ef{(field.mEvs[upperElevReal].mElevation - field.mEvs[ei].mElevation) /
                (field.mEvs[upperElevReal].mElevation - field.mEvs[lowerElevFake].mElevation)};

            for(uint ai{0u};ai < field.mEvs[ei].mAzs.size();ai++)
            {
                uint a0, a1, a2, a3;
                double af0, af1;

                double az{field.mEvs[ei].mAzs[ai].mAzimuth};
                CalcAzIndices(field, upperElevReal, az, &a0, &a1, &af0);
                CalcAzIndices(field, lowerElevFake, az, &a2, &a3, &af1);
                std::array<double,4> blend{{
                    (1.0-ef) * (1.0-af0),
                    (1.0-ef) * (    af0),
                    (    ef) * (1.0-af1),
                    (    ef) * (    af1)
                }};

                for(uint ti{0u};ti < channels;ti++)
                {
                    field.mEvs[ei].mAzs[ai].mDelays[ti] =
                        field.mEvs[upperElevReal].mAzs[a0].mDelays[ti]*blend[0] +
                        field.mEvs[upperElevReal].mAzs[a1].mDelays[ti]*blend[1] +
                        field.mEvs[lowerElevFake].mAzs[a2].mDelays[ti]*blend[2] +
                        field.mEvs[lowerElevFake].mAzs[a3].mDelays[ti]*blend[3];
                }
            }
        }
    };
    std::for_each(hData->mFds.begin(), hData->mFds.end(), proc_field);
}

/* Attempt to synthesize any missing HRIRs at the bottom elevations of each
 * field.  Right now this just blends the lowest elevation HRIRs together and
 * applies a low-pass filter to simulate body occlusion.  It is a simple, if
 * inaccurate model.
 */
void SynthesizeHrirs(HrirDataT *hData)
{
    const uint channels{(hData->mChannelType == CT_STEREO) ? 2u : 1u};
    auto htemp = std::vector<complex_d>(hData->mFftSize);
    const uint m{hData->mFftSize/2u + 1u};
    auto filter = std::vector<double>(m);
    const double beta{3.5e-6 * hData->mIrRate};

    auto proc_field = [channels,m,beta,&htemp,&filter](HrirFdT &field) -> void
    {
        const uint oi{field.mEvStart};
        if(oi <= 0) return;

        for(uint ti{0u};ti < channels;ti++)
        {
            uint a0, a1;
            double af;

            /* Use the lowest immediate-left response for the left ear and
             * lowest immediate-right response for the right ear. Given no comb
             * effects as a result of the left response reaching the right ear
             * and vice-versa, this produces a decent phantom-center response
             * underneath the head.
             */
            CalcAzIndices(field, oi, al::numbers::pi / ((ti==0) ? -2.0 : 2.0), &a0, &a1, &af);
            for(uint i{0u};i < m;i++)
            {
                field.mEvs[0].mAzs[0].mIrs[ti][i] = Lerp(field.mEvs[oi].mAzs[a0].mIrs[ti][i],
                    field.mEvs[oi].mAzs[a1].mIrs[ti][i], af);
            }
        }

        for(uint ei{1u};ei < field.mEvStart;ei++)
        {
            const double of{static_cast<double>(ei) / field.mEvStart};
            const double b{(1.0 - of) * beta};
            std::array<double,4> lp{};

            /* Calculate a low-pass filter to simulate body occlusion. */
            lp[0] = Lerp(1.0, lp[0], b);
            lp[1] = Lerp(lp[0], lp[1], b);
            lp[2] = Lerp(lp[1], lp[2], b);
            lp[3] = Lerp(lp[2], lp[3], b);
            htemp[0] = lp[3];
            for(size_t i{1u};i < htemp.size();i++)
            {
                lp[0] = Lerp(0.0, lp[0], b);
                lp[1] = Lerp(lp[0], lp[1], b);
                lp[2] = Lerp(lp[1], lp[2], b);
                lp[3] = Lerp(lp[2], lp[3], b);
                htemp[i] = lp[3];
            }
            /* Get the filter's frequency-domain response and extract the
             * frequency magnitudes (phase will be reconstructed later)).
             */
            FftForward(static_cast<uint>(htemp.size()), htemp.data());
            std::transform(htemp.cbegin(), htemp.cbegin()+m, filter.begin(),
                [](const complex_d c) -> double { return std::abs(c); });

            for(uint ai{0u};ai < field.mEvs[ei].mAzs.size();ai++)
            {
                uint a0, a1;
                double af;

                CalcAzIndices(field, oi, field.mEvs[ei].mAzs[ai].mAzimuth, &a0, &a1, &af);
                for(uint ti{0u};ti < channels;ti++)
                {
                    for(uint i{0u};i < m;i++)
                    {
                        /* Blend the two defined HRIRs closest to this azimuth,
                         * then blend that with the synthesized -90 elevation.
                         */
                        const double s1{Lerp(field.mEvs[oi].mAzs[a0].mIrs[ti][i],
                            field.mEvs[oi].mAzs[a1].mIrs[ti][i], af)};
                        const double s{Lerp(field.mEvs[0].mAzs[0].mIrs[ti][i], s1, of)};
                        field.mEvs[ei].mAzs[ai].mIrs[ti][i] = s * filter[i];
                    }
                }
            }
        }
        const double b{beta};
        std::array<double,4> lp{};
        lp[0] = Lerp(1.0, lp[0], b);
        lp[1] = Lerp(lp[0], lp[1], b);
        lp[2] = Lerp(lp[1], lp[2], b);
        lp[3] = Lerp(lp[2], lp[3], b);
        htemp[0] = lp[3];
        for(size_t i{1u};i < htemp.size();i++)
        {
            lp[0] = Lerp(0.0, lp[0], b);
            lp[1] = Lerp(lp[0], lp[1], b);
            lp[2] = Lerp(lp[1], lp[2], b);
            lp[3] = Lerp(lp[2], lp[3], b);
            htemp[i] = lp[3];
        }
        FftForward(static_cast<uint>(htemp.size()), htemp.data());
        std::transform(htemp.cbegin(), htemp.cbegin()+m, filter.begin(),
            [](const complex_d c) -> double { return std::abs(c); });

        for(uint ti{0u};ti < channels;ti++)
        {
            for(uint i{0u};i < m;i++)
                field.mEvs[0].mAzs[0].mIrs[ti][i] *= filter[i];
        }
    };
    std::for_each(hData->mFds.begin(), hData->mFds.end(), proc_field);
}

// The following routines assume a full set of HRIRs for all elevations.

/* Perform minimum-phase reconstruction using the magnitude responses of the
 * HRIR set. Work is delegated to this struct, which runs asynchronously on one
 * or more threads (sharing the same reconstructor object).
 */
struct HrirReconstructor {
    std::vector<al::span<double>> mIrs;
    std::atomic<size_t> mCurrent{};
    std::atomic<size_t> mDone{};
    uint mFftSize{};
    uint mIrPoints{};

    void Worker()
    {
        auto h = std::vector<complex_d>(mFftSize);
        auto mags = std::vector<double>(mFftSize);
        size_t m{(mFftSize/2) + 1};

        while(true)
        {
            /* Load the current index to process. */
            size_t idx{mCurrent.load()};
            do {
                /* If the index is at the end, we're done. */
                if(idx >= mIrs.size())
                    return;
                /* Otherwise, increment the current index atomically so other
                 * threads know to go to the next one. If this call fails, the
                 * current index was just changed by another thread and the new
                 * value is loaded into idx, which we'll recheck.
                 */
            } while(!mCurrent.compare_exchange_weak(idx, idx+1, std::memory_order_relaxed));

            /* Now do the reconstruction, and apply the inverse FFT to get the
             * time-domain response.
             */
            for(size_t i{0};i < m;++i)
                mags[i] = std::max(mIrs[idx][i], Epsilon);
            MinimumPhase(mags, h);
            FftInverse(mFftSize, h.data());
            for(uint i{0u};i < mIrPoints;++i)
                mIrs[idx][i] = h[i].real();

            /* Increment the number of IRs done. */
            mDone.fetch_add(1);
        }
    }
};

void ReconstructHrirs(const HrirDataT *hData, const uint numThreads)
{
    const uint channels{(hData->mChannelType == CT_STEREO) ? 2u : 1u};

    /* Set up the reconstructor with the needed size info and pointers to the
     * IRs to process.
     */
    HrirReconstructor reconstructor;
    reconstructor.mCurrent.store(0, std::memory_order_relaxed);
    reconstructor.mDone.store(0, std::memory_order_relaxed);
    reconstructor.mFftSize = hData->mFftSize;
    reconstructor.mIrPoints = hData->mIrPoints;
    for(const auto &field : hData->mFds)
    {
        for(auto &elev : field.mEvs)
        {
            for(const auto &azd : elev.mAzs)
            {
                for(uint ti{0u};ti < channels;ti++)
                    reconstructor.mIrs.push_back(azd.mIrs[ti]);
            }
        }
    }

    /* Launch threads to work on reconstruction. */
    std::vector<std::thread> thrds;
    thrds.reserve(numThreads);
    for(size_t i{0};i < numThreads;++i)
        thrds.emplace_back(std::mem_fn(&HrirReconstructor::Worker), &reconstructor);

    /* Keep track of the number of IRs done, periodically reporting it. */
    size_t count;
    do {
        std::this_thread::sleep_for(std::chrono::milliseconds{50});

        count = reconstructor.mDone.load();
        size_t pcdone{count * 100 / reconstructor.mIrs.size()};

        printf("\r%3zu%% done (%zu of %zu)", pcdone, count, reconstructor.mIrs.size());
        fflush(stdout);
    } while(count < reconstructor.mIrs.size());
    fputc('\n', stdout);

    for(auto &thrd : thrds)
    {
        if(thrd.joinable())
            thrd.join();
    }
}

// Normalize the HRIR set and slightly attenuate the result.
void NormalizeHrirs(HrirDataT *hData)
{
    const uint channels{(hData->mChannelType == CT_STEREO) ? 2u : 1u};
    const uint irSize{hData->mIrPoints};

    /* Find the maximum amplitude and RMS out of all the IRs. */
    struct LevelPair { double amp, rms; };
    auto mesasure_channel = [irSize](const LevelPair levels, al::span<const double> ir)
    {
        /* Calculate the peak amplitude and RMS of this IR. */
        ir = ir.first(irSize);
        auto current = std::accumulate(ir.cbegin(), ir.cend(), LevelPair{0.0, 0.0},
            [](const LevelPair cur, const double impulse)
            {
                return LevelPair{std::max(std::abs(impulse), cur.amp), cur.rms + impulse*impulse};
            });
        current.rms = std::sqrt(current.rms / irSize);

        /* Accumulate levels by taking the maximum amplitude and RMS. */
        return LevelPair{std::max(current.amp, levels.amp), std::max(current.rms, levels.rms)};
    };
    auto measure_azi = [channels,mesasure_channel](const LevelPair levels, const HrirAzT &azi)
    { return std::accumulate(azi.mIrs.begin(), azi.mIrs.begin()+channels, levels, mesasure_channel); };
    auto measure_elev = [measure_azi](const LevelPair levels, const HrirEvT &elev)
    { return std::accumulate(elev.mAzs.cbegin(), elev.mAzs.cend(), levels, measure_azi); };
    auto measure_field = [measure_elev](const LevelPair levels, const HrirFdT &field)
    { return std::accumulate(field.mEvs.cbegin(), field.mEvs.cend(), levels, measure_elev); };

    const auto maxlev = std::accumulate(hData->mFds.begin(), hData->mFds.end(),
        LevelPair{0.0, 0.0}, measure_field);

    /* Normalize using the maximum RMS of the HRIRs. The RMS measure for the
     * non-filtered signal is of an impulse with equal length (to the filter):
     *
     * rms_impulse = sqrt(sum([ 1^2, 0^2, 0^2, ... ]) / n)
     *             = sqrt(1 / n)
     *
     * This helps keep a more consistent volume between the non-filtered signal
     * and various data sets.
     */
    double factor{std::sqrt(1.0 / irSize) / maxlev.rms};

    /* Also ensure the samples themselves won't clip. */
    factor = std::min(factor, 0.99/maxlev.amp);

    /* Now scale all IRs by the given factor. */
    auto proc_channel = [irSize,factor](al::span<double> ir)
    {
        ir = ir.first(irSize);
        std::transform(ir.cbegin(), ir.cend(), ir.begin(),
            [factor](double s) { return s * factor; });
    };
    auto proc_azi = [channels,proc_channel](HrirAzT &azi)
    { std::for_each(azi.mIrs.begin(), azi.mIrs.begin()+channels, proc_channel); };
    auto proc_elev = [proc_azi](HrirEvT &elev)
    { std::for_each(elev.mAzs.begin(), elev.mAzs.end(), proc_azi); };
    auto proc1_field = [proc_elev](HrirFdT &field)
    { std::for_each(field.mEvs.begin(), field.mEvs.end(), proc_elev); };

    std::for_each(hData->mFds.begin(), hData->mFds.end(), proc1_field);
}

// Calculate the left-ear time delay using a spherical head model.
double CalcLTD(const double ev, const double az, const double rad, const double dist)
{
    double azp, dlp, l, al;

    azp = std::asin(std::cos(ev) * std::sin(az));
    dlp = std::sqrt((dist*dist) + (rad*rad) + (2.0*dist*rad*sin(azp)));
    l = std::sqrt((dist*dist) - (rad*rad));
    al = (0.5 * al::numbers::pi) + azp;
    if(dlp > l)
        dlp = l + (rad * (al - std::acos(rad / dist)));
    return dlp / 343.3;
}

// Calculate the effective head-related time delays for each minimum-phase
// HRIR. This is done per-field since distance delay is ignored.
void CalculateHrtds(const HeadModelT model, const double radius, HrirDataT *hData)
{
    uint channels = (hData->mChannelType == CT_STEREO) ? 2 : 1;
    double customRatio{radius / hData->mRadius};
    uint ti;

    if(model == HM_Sphere)
    {
        for(auto &field : hData->mFds)
        {
            for(auto &elev : field.mEvs)
            {
                for(auto &azd : elev.mAzs)
                {
                    for(ti = 0;ti < channels;ti++)
                        azd.mDelays[ti] = CalcLTD(elev.mElevation, azd.mAzimuth, radius, field.mDistance);
                }
            }
        }
    }
    else if(customRatio != 1.0)
    {
        for(auto &field : hData->mFds)
        {
            for(auto &elev : field.mEvs)
            {
                for(auto &azd : elev.mAzs)
                {
                    for(ti = 0;ti < channels;ti++)
                        azd.mDelays[ti] *= customRatio;
                }
            }
        }
    }

    double maxHrtd{0.0};
    for(auto &field : hData->mFds)
    {
        double minHrtd{std::numeric_limits<double>::infinity()};
        for(auto &elev : field.mEvs)
        {
            for(auto &azd : elev.mAzs)
            {
                for(ti = 0;ti < channels;ti++)
                    minHrtd = std::min(azd.mDelays[ti], minHrtd);
            }
        }

        for(auto &elev : field.mEvs)
        {
            for(auto &azd : elev.mAzs)
            {
                for(ti = 0;ti < channels;ti++)
                {
                    azd.mDelays[ti] = (azd.mDelays[ti]-minHrtd) * hData->mIrRate;
                    maxHrtd = std::max(maxHrtd, azd.mDelays[ti]);
                }
            }
        }
    }
    if(maxHrtd > MaxHrtd)
    {
        printf("  Scaling for max delay of %f samples to %f\n...\n", maxHrtd, MaxHrtd);
        const double scale{MaxHrtd / maxHrtd};
        for(auto &field : hData->mFds)
        {
            for(auto &elev : field.mEvs)
            {
                for(auto &azd : elev.mAzs)
                {
                    for(ti = 0;ti < channels;ti++)
                        azd.mDelays[ti] *= scale;
                }
            }
        }
    }
}

} // namespace

// Allocate and configure dynamic HRIR structures.
bool PrepareHrirData(const al::span<const double> distances,
    const al::span<const uint,MAX_FD_COUNT> evCounts,
    const al::span<const std::array<uint,MAX_EV_COUNT>,MAX_FD_COUNT> azCounts, HrirDataT *hData)
{
    uint evTotal{0}, azTotal{0};

    for(size_t fi{0};fi < distances.size();++fi)
    {
        evTotal += evCounts[fi];
        for(size_t ei{0};ei < evCounts[fi];++ei)
            azTotal += azCounts[fi][ei];
    }
    if(!evTotal || !azTotal)
        return false;

    hData->mEvsBase.resize(evTotal);
    hData->mAzsBase.resize(azTotal);
    hData->mFds.resize(distances.size());
    hData->mIrCount = azTotal;
    evTotal = 0;
    azTotal = 0;
    for(size_t fi{0};fi < distances.size();++fi)
    {
        hData->mFds[fi].mDistance = distances[fi];
        hData->mFds[fi].mEvStart = 0;
        hData->mFds[fi].mEvs = al::span{hData->mEvsBase}.subspan(evTotal, evCounts[fi]);
        evTotal += evCounts[fi];
        for(uint ei{0};ei < evCounts[fi];++ei)
        {
            uint azCount = azCounts[fi][ei];

            hData->mFds[fi].mEvs[ei].mElevation = -al::numbers::pi / 2.0 + al::numbers::pi * ei /
                (evCounts[fi] - 1);
            hData->mFds[fi].mEvs[ei].mAzs = al::span{hData->mAzsBase}.subspan(azTotal, azCount);
            for(uint ai{0};ai < azCount;ai++)
            {
                hData->mFds[fi].mEvs[ei].mAzs[ai].mAzimuth = 2.0 * al::numbers::pi * ai / azCount;
                hData->mFds[fi].mEvs[ei].mAzs[ai].mIndex = azTotal + ai;
                hData->mFds[fi].mEvs[ei].mAzs[ai].mDelays[0] = 0.0;
                hData->mFds[fi].mEvs[ei].mAzs[ai].mDelays[1] = 0.0;
                hData->mFds[fi].mEvs[ei].mAzs[ai].mIrs[0] = {};
                hData->mFds[fi].mEvs[ei].mAzs[ai].mIrs[1] = {};
            }
            azTotal += azCount;
        }
    }
    return true;
}


namespace {

/* Parse the data set definition and process the source data, storing the
 * resulting data set as desired.  If the input name is NULL it will read
 * from standard input.
 */
bool ProcessDefinition(std::string_view inName, const uint outRate, const ChannelModeT chanMode,
    const bool farfield, const uint numThreads, const uint fftSize, const bool equalize,
    const bool surface, const double limit, const uint truncSize, const HeadModelT model,
    const double radius, const std::string_view outName)
{
    HrirDataT hData;

    printf("Using %u thread%s.\n", numThreads, (numThreads==1)?"":"s");
    if(inName.empty() || inName == "-"sv)
    {
        inName = "stdin"sv;
        printf("Reading HRIR definition from %.*s...\n", al::sizei(inName), inName.data());
        if(!LoadDefInput(std::cin, {}, inName, fftSize, truncSize, outRate, chanMode, &hData))
            return false;
    }
    else
    {
        auto input = std::make_unique<std::ifstream>(std::filesystem::u8path(inName));
        if(!input->is_open())
        {
            fprintf(stderr, "Error: Could not open input file '%.*s'\n", al::sizei(inName),
                inName.data());
            return false;
        }

        std::array<char,4> startbytes{};
        input->read(startbytes.data(), startbytes.size());
        if(input->gcount() != startbytes.size() || !input->good())
        {
            fprintf(stderr, "Error: Could not read input file '%.*s'\n", al::sizei(inName),
                inName.data());
            return false;
        }

        if(startbytes[0] == '\x89' && startbytes[1] == 'H' && startbytes[2] == 'D'
            && startbytes[3] == 'F')
        {
            input = nullptr;
            printf("Reading HRTF data from %.*s...\n", al::sizei(inName), inName.data());
            if(!LoadSofaFile(inName, numThreads, fftSize, truncSize, outRate, chanMode, &hData))
                return false;
        }
        else
        {
            printf("Reading HRIR definition from %.*s...\n", al::sizei(inName), inName.data());
            if(!LoadDefInput(*input, startbytes, inName, fftSize, truncSize, outRate, chanMode,
                &hData))
                return false;
        }
    }

    if(equalize)
    {
        uint c{(hData.mChannelType == CT_STEREO) ? 2u : 1u};
        uint m{hData.mFftSize/2u + 1u};
        auto dfa = std::vector<double>(size_t{c} * m);

        if(hData.mFds.size() > 1)
        {
            fputs("Balancing field magnitudes...\n", stdout);
            BalanceFieldMagnitudes(&hData, c, m);
        }
        fputs("Calculating diffuse-field average...\n", stdout);
        CalculateDiffuseFieldAverage(&hData, c, m, surface, limit, dfa);
        fputs("Performing diffuse-field equalization...\n", stdout);
        DiffuseFieldEqualize(c, m, dfa, &hData);
    }
    if(hData.mFds.size() > 1)
    {
        printf("Sorting %zu fields...\n", hData.mFds.size());
        std::sort(hData.mFds.begin(), hData.mFds.end(),
            [](const HrirFdT &lhs, const HrirFdT &rhs) noexcept
            { return lhs.mDistance < rhs.mDistance; });
        if(farfield)
        {
            printf("Clearing %zu near field%s...\n", hData.mFds.size()-1,
                (hData.mFds.size()-1 != 1) ? "s" : "");
            hData.mFds.erase(hData.mFds.cbegin(), hData.mFds.cend()-1);
        }
    }
    fputs("Synthesizing missing elevations...\n", stdout);
    if(model == HM_Dataset)
        SynthesizeOnsets(&hData);
    SynthesizeHrirs(&hData);
    fputs("Performing minimum phase reconstruction...\n", stdout);
    ReconstructHrirs(&hData, numThreads);
    fputs("Truncating minimum-phase HRIRs...\n", stdout);
    hData.mIrPoints = truncSize;
    fputs("Normalizing final HRIRs...\n", stdout);
    NormalizeHrirs(&hData);
    fputs("Calculating impulse delays...\n", stdout);
    CalculateHrtds(model, (radius > DefaultCustomRadius) ? radius : hData.mRadius, &hData);

    const auto rateStr = std::to_string(hData.mIrRate);
    const auto expName = StrSubst(outName, "%r"sv, rateStr);
    printf("Creating MHR data set %s...\n", expName.c_str());
    return StoreMhr(&hData, expName);
}

void PrintHelp(const std::string_view argv0, FILE *ofile)
{
    fprintf(ofile, "Usage:  %.*s [<option>...]\n\n", al::sizei(argv0), argv0.data());
    fprintf(ofile, "Options:\n");
    fprintf(ofile, " -r <rate>       Change the data set sample rate to the specified value and\n");
    fprintf(ofile, "                 resample the HRIRs accordingly.\n");
    fprintf(ofile, " -m              Change the data set to mono, mirroring the left ear for the\n");
    fprintf(ofile, "                 right ear.\n");
    fprintf(ofile, " -a              Change the data set to single field, using the farthest field.\n");
    fprintf(ofile, " -j <threads>    Number of threads used to process HRIRs (default: 2).\n");
    fprintf(ofile, " -f <points>     Override the FFT window size (default: %u).\n", DefaultFftSize);
    fprintf(ofile, " -e {on|off}     Toggle diffuse-field equalization (default: %s).\n", (DefaultEqualize ? "on" : "off"));
    fprintf(ofile, " -s {on|off}     Toggle surface-weighted diffuse-field average (default: %s).\n", (DefaultSurface ? "on" : "off"));
    fprintf(ofile, " -l {<dB>|none}  Specify a limit to the magnitude range of the diffuse-field\n");
    fprintf(ofile, "                 average (default: %.2f).\n", DefaultLimit);
    fprintf(ofile, " -w <points>     Specify the size of the truncation window that's applied\n");
    fprintf(ofile, "                 after minimum-phase reconstruction (default: %u).\n", DefaultTruncSize);
    fprintf(ofile, " -d {dataset|    Specify the model used for calculating the head-delay timing\n");
    fprintf(ofile, "     sphere}     values (default: %s).\n", ((HM_Default == HM_Dataset) ? "dataset" : "sphere"));
    fprintf(ofile, " -c <radius>     Use a customized head radius measured to-ear in meters.\n");
    fprintf(ofile, " -i <filename>   Specify an HRIR definition file to use (defaults to stdin).\n");
    fprintf(ofile, " -o <filename>   Specify an output file. Use of '%%r' will be substituted with\n");
    fprintf(ofile, "                 the data set sample rate.\n");
}

// Standard command line dispatch.
int main(al::span<std::string_view> args)
{
    if(args.size() < 2)
    {
        fputs("HRTF Processing and Composition Utility\n\n", stdout);
        PrintHelp(args[0], stdout);
        exit(EXIT_SUCCESS);
    }

    std::string_view outName{"./oalsoft_hrtf_%r.mhr"sv};
    uint outRate{0};
    ChannelModeT chanMode{CM_AllowStereo};
    uint fftSize{DefaultFftSize};
    bool equalize{DefaultEqualize};
    bool surface{DefaultSurface};
    double limit{DefaultLimit};
    uint numThreads{2};
    uint truncSize{DefaultTruncSize};
    HeadModelT model{HM_Default};
    double radius{DefaultCustomRadius};
    bool farfield{false};
    std::string_view inName;

    const std::string_view optlist{"r:maj:f:e:s:l:w:d:c:e:i:o:h"sv};
    const auto arg0 = args[0];
    args = args.subspan(1);
    std::string_view optarg;
    size_t argplace{0};

    auto getarg = [&args,&argplace,&optarg,optlist]
    {
        while(!args.empty() && argplace >= args[0].size())
        {
            argplace = 0;
            args = args.subspan(1);
        }
        if(args.empty())
            return 0;

        if(argplace == 0)
        {
            if(args[0] == "--"sv)
                return 0;

            if(args[0][0] != '-' || args[0].size() == 1)
            {
                fprintf(stderr, "Invalid argument: %.*s\n", al::sizei(args[0]), args[0].data());
                return -1;
            }
            ++argplace;
        }

        const char nextopt{args[0][argplace]};
        const auto listidx = optlist.find(nextopt);
        if(listidx >= optlist.size())
        {
            fprintf(stderr, "Unknown argument: -%c\n", nextopt);
            return -1;
        }
        const bool needsarg{listidx+1 < optlist.size() && optlist[listidx+1] == ':'};
        if(needsarg && (argplace+1 < args[0].size() || args.size() < 2))
        {
            fprintf(stderr, "Missing parameter for argument: -%c\n", nextopt);
            return -1;
        }
        if(++argplace == args[0].size())
        {
            if(needsarg)
                optarg = args[1];
            argplace = 0;
            args = args.subspan(1u + needsarg);
        }

        return int{nextopt};
    };

    while(auto opt = getarg())
    {
        std::size_t endpos{};
        switch(opt)
        {
        case 'r':
            outRate = static_cast<uint>(std::stoul(std::string{optarg}, &endpos, 10));
            if(endpos != optarg.size() || outRate < MIN_RATE || outRate > MAX_RATE)
            {
                fprintf(stderr, "\nError: Got unexpected value \"%.*s\" for option -%c, expected between %u to %u.\n",
                    al::sizei(optarg), optarg.data(), opt, MIN_RATE, MAX_RATE);
                exit(EXIT_FAILURE);
            }
            break;

        case 'm':
            chanMode = CM_ForceMono;
            break;

        case 'a':
            farfield = true;
            break;

        case 'j':
            numThreads = static_cast<uint>(std::stoul(std::string{optarg}, &endpos, 10));
            if(endpos != optarg.size() || numThreads > 64)
            {
                fprintf(stderr, "\nError: Got unexpected value \"%.*s\" for option -%c, expected between %u to %u.\n",
                    al::sizei(optarg), optarg.data(), opt, 0, 64);
                exit(EXIT_FAILURE);
            }
            if(numThreads == 0)
                numThreads = std::thread::hardware_concurrency();
            break;

        case 'f':
            fftSize = static_cast<uint>(std::stoul(std::string{optarg}, &endpos, 10));
            if(endpos != optarg.size() || (fftSize&(fftSize-1)) || fftSize < MinFftSize
                || fftSize > MaxFftSize)
            {
                fprintf(stderr, "\nError: Got unexpected value \"%.*s\" for option -%c, expected a power-of-two between %u to %u.\n",
                    al::sizei(optarg), optarg.data(), opt, MinFftSize, MaxFftSize);
                exit(EXIT_FAILURE);
            }
            break;

        case 'e':
            if(optarg == "on"sv)
                equalize = true;
            else if(optarg == "off"sv)
                equalize = false;
            else
            {
                fprintf(stderr, "\nError: Got unexpected value \"%.*s\" for option -%c, expected on or off.\n",
                    al::sizei(optarg), optarg.data(), opt);
                exit(EXIT_FAILURE);
            }
            break;

        case 's':
            if(optarg == "on"sv)
                surface = true;
            else if(optarg == "off"sv)
                surface = false;
            else
            {
                fprintf(stderr, "\nError: Got unexpected value \"%.*s\" for option -%c, expected on or off.\n",
                    al::sizei(optarg), optarg.data(), opt);
                exit(EXIT_FAILURE);
            }
            break;

        case 'l':
            if(optarg == "none"sv)
                limit = 0.0;
            else
            {
                limit = std::stod(std::string{optarg}, &endpos);
                if(endpos != optarg.size() || limit < MinLimit || limit > MaxLimit)
                {
                    fprintf(stderr, "\nError: Got unexpected value \"%.*s\" for option -%c, expected between %.0f to %.0f.\n",
                        al::sizei(optarg), optarg.data(), opt, MinLimit, MaxLimit);
                    exit(EXIT_FAILURE);
                }
            }
            break;

        case 'w':
            truncSize = static_cast<uint>(std::stoul(std::string{optarg}, &endpos, 10));
            if(endpos != optarg.size() || truncSize < MinTruncSize || truncSize > MaxTruncSize)
            {
                fprintf(stderr, "\nError: Got unexpected value \"%.*s\" for option -%c, expected between %u to %u.\n",
                    al::sizei(optarg), optarg.data(), opt, MinTruncSize, MaxTruncSize);
                exit(EXIT_FAILURE);
            }
            break;

        case 'd':
            if(optarg == "dataset"sv)
                model = HM_Dataset;
            else if(optarg == "sphere"sv)
                model = HM_Sphere;
            else
            {
                fprintf(stderr, "\nError: Got unexpected value \"%.*s\" for option -%c, expected dataset or sphere.\n",
                    al::sizei(optarg), optarg.data(), opt);
                exit(EXIT_FAILURE);
            }
            break;

        case 'c':
            radius = std::stod(std::string{optarg}, &endpos);
            if(endpos != optarg.size() || radius < MinCustomRadius || radius > MaxCustomRadius)
            {
                fprintf(stderr, "\nError: Got unexpected value \"%.*s\" for option -%c, expected between %.2f to %.2f.\n",
                    al::sizei(optarg), optarg.data(), opt, MinCustomRadius, MaxCustomRadius);
                exit(EXIT_FAILURE);
            }
            break;

        case 'i':
            inName = optarg;
            break;

        case 'o':
            outName = optarg;
            break;

        case 'h':
            PrintHelp(arg0, stdout);
            exit(EXIT_SUCCESS);

        default: /* '?' */
            PrintHelp(arg0, stderr);
            exit(EXIT_FAILURE);
        }
    }

    const int ret{ProcessDefinition(inName, outRate, chanMode, farfield, numThreads, fftSize,
        equalize, surface, limit, truncSize, model, radius, outName)};
    if(!ret) return -1;
    fputs("Operation completed.\n", stdout);

    return EXIT_SUCCESS;
}

} /* namespace */

int main(int argc, char **argv)
{
    assert(argc >= 0);
    auto args = std::vector<std::string_view>(static_cast<unsigned int>(argc));
    std::copy_n(argv, args.size(), args.begin());
    return main(al::span{args});
}
