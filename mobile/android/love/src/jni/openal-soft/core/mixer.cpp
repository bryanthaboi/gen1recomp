
#include "config.h"

#include "mixer.h"

#include <algorithm>
#include <cmath>
#include <utility>

#include "alnumbers.h"
#include "core/ambidefs.h"
#include "device.h"
#include "mixer/defs.h"

struct CTag;


MixerOutFunc MixSamplesOut{Mix_<CTag>};
MixerOneFunc MixSamplesOne{Mix_<CTag>};


std::array<float,MaxAmbiChannels> CalcAmbiCoeffs(const float y, const float z, const float x,
    const float spread)
{
    std::array<float,MaxAmbiChannels> coeffs{CalcAmbiCoeffs(y, z, x)};

    if(spread > 0.0f)
    {
        /* Implement the spread by using a spherical source that subtends the
         * angle spread. See:
         * http://www.ppsloan.org/publications/StupidSH36.pdf - Appendix A3
         *
         * When adjusted for N3D normalization instead of SN3D, these
         * calculations are:
         *
         * ZH0 = -sqrt(pi) * (-1+ca);
         * ZH1 =  0.5*sqrt(pi) * sa*sa;
         * ZH2 = -0.5*sqrt(pi) * ca*(-1+ca)*(ca+1);
         * ZH3 = -0.125*sqrt(pi) * (-1+ca)*(ca+1)*(5*ca*ca - 1);
         * ZH4 = -0.125*sqrt(pi) * ca*(-1+ca)*(ca+1)*(7*ca*ca - 3);
         * ZH5 = -0.0625*sqrt(pi) * (-1+ca)*(ca+1)*(21*ca*ca*ca*ca - 14*ca*ca + 1);
         *
         * The gain of the source is compensated for size, so that the
         * loudness doesn't depend on the spread. Thus:
         *
         * ZH0 = 1.0f;
         * ZH1 = 0.5f * (ca+1.0f);
         * ZH2 = 0.5f * (ca+1.0f)*ca;
         * ZH3 = 0.125f * (ca+1.0f)*(5.0f*ca*ca - 1.0f);
         * ZH4 = 0.125f * (ca+1.0f)*(7.0f*ca*ca - 3.0f)*ca;
         * ZH5 = 0.0625f * (ca+1.0f)*(21.0f*ca*ca*ca*ca - 14.0f*ca*ca + 1.0f);
         */
        const float ca{std::cos(spread * 0.5f)};
        /* Increase the source volume by up to +3dB for a full spread. */
        const float scale{std::sqrt(1.0f + al::numbers::inv_pi_v<float>/2.0f*spread)};

        const float ZH0_norm{scale};
        const float ZH1_norm{scale * 0.5f * (ca+1.f)};
        const float ZH2_norm{scale * 0.5f * (ca+1.f)*ca};
        const float ZH3_norm{scale * 0.125f * (ca+1.f)*(5.f*ca*ca-1.f)};

        /* Zeroth-order */
        coeffs[0]  *= ZH0_norm;
        /* First-order */
        coeffs[1]  *= ZH1_norm;
        coeffs[2]  *= ZH1_norm;
        coeffs[3]  *= ZH1_norm;
        /* Second-order */
        coeffs[4]  *= ZH2_norm;
        coeffs[5]  *= ZH2_norm;
        coeffs[6]  *= ZH2_norm;
        coeffs[7]  *= ZH2_norm;
        coeffs[8]  *= ZH2_norm;
        /* Third-order */
        coeffs[9]  *= ZH3_norm;
        coeffs[10] *= ZH3_norm;
        coeffs[11] *= ZH3_norm;
        coeffs[12] *= ZH3_norm;
        coeffs[13] *= ZH3_norm;
        coeffs[14] *= ZH3_norm;
        coeffs[15] *= ZH3_norm;
    }

    return coeffs;
}

void ComputePanGains(const MixParams *mix, const al::span<const float,MaxAmbiChannels> coeffs,
    const float ingain, const al::span<float,MaxAmbiChannels> gains)
{
    auto ambimap = al::span{std::as_const(mix->AmbiMap)}.first(mix->Buffer.size());

    auto iter = std::transform(ambimap.begin(), ambimap.end(), gains.begin(),
        [coeffs,ingain](const BFChannelConfig &chanmap) noexcept -> float
        { return chanmap.Scale * coeffs[chanmap.Index] * ingain; });
    std::fill(iter, gains.end(), 0.0f);
}
