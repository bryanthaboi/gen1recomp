/**
 * OpenAL cross platform audio library
 * Copyright (C) 2014 by Timothy Arceri <t_arceri@yahoo.com.au>.
 * This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 *  License along with this library; if not, write to the
 *  Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 * Or go to http://www.gnu.org/copyleft/lgpl.html
 */

#include "config.h"

#include <xmmintrin.h>
#include <emmintrin.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <variant>

#include "alnumeric.h"
#include "alspan.h"
#include "core/cubic_defs.h"
#include "core/resampler_limits.h"
#include "defs.h"
#include "opthelpers.h"

struct SSE2Tag;
struct LerpTag;
struct CubicTag;


#if defined(__GNUC__) && !defined(__clang__) && !defined(__SSE2__)
#pragma GCC target("sse2")
#endif

using uint = unsigned int;

namespace {

constexpr uint CubicPhaseDiffBits{MixerFracBits - CubicPhaseBits};
constexpr uint CubicPhaseDiffOne{1 << CubicPhaseDiffBits};
constexpr uint CubicPhaseDiffMask{CubicPhaseDiffOne - 1u};

force_inline __m128 vmadd(const __m128 x, const __m128 y, const __m128 z) noexcept
{ return _mm_add_ps(x, _mm_mul_ps(y, z)); }

} // namespace

template<>
void Resample_<LerpTag,SSE2Tag>(const InterpState*, const al::span<const float> src, uint frac,
    const uint increment, const al::span<float> dst)
{
    ASSUME(frac < MixerFracOne);

    const __m128i increment4{_mm_set1_epi32(static_cast<int>(increment*4))};
    const __m128 fracOne4{_mm_set1_ps(1.0f/MixerFracOne)};
    const __m128i fracMask4{_mm_set1_epi32(MixerFracMask)};

    std::array<uint,4> pos_{}, frac_{};
    InitPosArrays(MaxResamplerEdge, frac, increment, al::span{frac_}, al::span{pos_});
    __m128i frac4{_mm_setr_epi32(static_cast<int>(frac_[0]), static_cast<int>(frac_[1]),
        static_cast<int>(frac_[2]), static_cast<int>(frac_[3]))};
    __m128i pos4{_mm_setr_epi32(static_cast<int>(pos_[0]), static_cast<int>(pos_[1]),
        static_cast<int>(pos_[2]), static_cast<int>(pos_[3]))};

    auto vecout = al::span{reinterpret_cast<__m128*>(dst.data()), dst.size()/4};
    std::generate(vecout.begin(), vecout.end(), [=,&pos4,&frac4]() -> __m128
    {
        const auto pos0 = static_cast<uint>(_mm_cvtsi128_si32(pos4));
        const auto pos1 = static_cast<uint>(_mm_cvtsi128_si32(_mm_srli_si128(pos4, 4)));
        const auto pos2 = static_cast<uint>(_mm_cvtsi128_si32(_mm_srli_si128(pos4, 8)));
        const auto pos3 = static_cast<uint>(_mm_cvtsi128_si32(_mm_srli_si128(pos4, 12)));
        ASSUME(pos0 <= pos1); ASSUME(pos1 <= pos2); ASSUME(pos2 <= pos3);
        const __m128 val1{_mm_setr_ps(src[pos0], src[pos1], src[pos2], src[pos3])};
        const __m128 val2{_mm_setr_ps(src[pos0+1_uz], src[pos1+1_uz], src[pos2+1_uz], src[pos3+1_uz])};

        /* val1 + (val2-val1)*mu */
        const __m128 r0{_mm_sub_ps(val2, val1)};
        const __m128 mu{_mm_mul_ps(_mm_cvtepi32_ps(frac4), fracOne4)};
        const __m128 out{_mm_add_ps(val1, _mm_mul_ps(mu, r0))};

        frac4 = _mm_add_epi32(frac4, increment4);
        pos4 = _mm_add_epi32(pos4, _mm_srli_epi32(frac4, MixerFracBits));
        frac4 = _mm_and_si128(frac4, fracMask4);
        return out;
    });

    if(size_t todo{dst.size()&3})
    {
        auto pos = size_t{static_cast<uint>(_mm_cvtsi128_si32(pos4))};
        frac = static_cast<uint>(_mm_cvtsi128_si32(frac4));

        const auto out = dst.last(todo);
        std::generate(out.begin(), out.end(), [&pos,&frac,src,increment]()
        {
            const float smp{lerpf(src[pos+0], src[pos+1],
                static_cast<float>(frac) * (1.0f/MixerFracOne))};

            frac += increment;
            pos  += frac>>MixerFracBits;
            frac &= MixerFracMask;
            return smp;
        });
    }
}

template<>
void Resample_<CubicTag,SSE2Tag>(const InterpState *state, const al::span<const float> src,
    uint frac, const uint increment, const al::span<float> dst)
{
    ASSUME(frac < MixerFracOne);

    const auto filter = std::get<CubicState>(*state).filter;

    const __m128i increment4{_mm_set1_epi32(static_cast<int>(increment*4))};
    const __m128i fracMask4{_mm_set1_epi32(MixerFracMask)};
    const __m128 fracDiffOne4{_mm_set1_ps(1.0f/CubicPhaseDiffOne)};
    const __m128i fracDiffMask4{_mm_set1_epi32(CubicPhaseDiffMask)};

    std::array<uint,4> pos_{}, frac_{};
    InitPosArrays(MaxResamplerEdge-1, frac, increment, al::span{frac_}, al::span{pos_});
    __m128i frac4{_mm_setr_epi32(static_cast<int>(frac_[0]), static_cast<int>(frac_[1]),
        static_cast<int>(frac_[2]), static_cast<int>(frac_[3]))};
    __m128i pos4{_mm_setr_epi32(static_cast<int>(pos_[0]), static_cast<int>(pos_[1]),
        static_cast<int>(pos_[2]), static_cast<int>(pos_[3]))};

    auto vecout = al::span{reinterpret_cast<__m128*>(dst.data()), dst.size()/4};
    std::generate(vecout.begin(), vecout.end(), [=,&pos4,&frac4]
    {
        const auto pos0 = static_cast<uint>(_mm_cvtsi128_si32(pos4));
        const auto pos1 = static_cast<uint>(_mm_cvtsi128_si32(_mm_srli_si128(pos4, 4)));
        const auto pos2 = static_cast<uint>(_mm_cvtsi128_si32(_mm_srli_si128(pos4, 8)));
        const auto pos3 = static_cast<uint>(_mm_cvtsi128_si32(_mm_srli_si128(pos4, 12)));
        ASSUME(pos0 <= pos1); ASSUME(pos1 <= pos2); ASSUME(pos2 <= pos3);
        const __m128 val0{_mm_loadu_ps(&src[pos0])};
        const __m128 val1{_mm_loadu_ps(&src[pos1])};
        const __m128 val2{_mm_loadu_ps(&src[pos2])};
        const __m128 val3{_mm_loadu_ps(&src[pos3])};

        const __m128i pi4{_mm_srli_epi32(frac4, CubicPhaseDiffBits)};
        const auto pi0 = static_cast<uint>(_mm_cvtsi128_si32(pi4));
        const auto pi1 = static_cast<uint>(_mm_cvtsi128_si32(_mm_srli_si128(pi4, 4)));
        const auto pi2 = static_cast<uint>(_mm_cvtsi128_si32(_mm_srli_si128(pi4, 8)));
        const auto pi3 = static_cast<uint>(_mm_cvtsi128_si32(_mm_srli_si128(pi4, 12)));
        ASSUME(pi0 < CubicPhaseCount); ASSUME(pi1 < CubicPhaseCount);
        ASSUME(pi2 < CubicPhaseCount); ASSUME(pi3 < CubicPhaseCount);

        const __m128 pf4{_mm_mul_ps(_mm_cvtepi32_ps(_mm_and_si128(frac4, fracDiffMask4)),
            fracDiffOne4)};

        __m128 r0{_mm_mul_ps(val0,
            vmadd(_mm_load_ps(filter[pi0].mCoeffs.data()),
                _mm_shuffle_ps(pf4, pf4, _MM_SHUFFLE(0, 0, 0, 0)),
                _mm_load_ps(filter[pi0].mDeltas.data())))};
        __m128 r1{_mm_mul_ps(val1,
            vmadd(_mm_load_ps(filter[pi1].mCoeffs.data()),
                _mm_shuffle_ps(pf4, pf4, _MM_SHUFFLE(1, 1, 1, 1)),
                _mm_load_ps(filter[pi1].mDeltas.data())))};
        __m128 r2{_mm_mul_ps(val2,
            vmadd(_mm_load_ps(filter[pi2].mCoeffs.data()),
                _mm_shuffle_ps(pf4, pf4, _MM_SHUFFLE(2, 2, 2, 2)),
                _mm_load_ps(filter[pi2].mDeltas.data())))};
        __m128 r3{_mm_mul_ps(val3,
            vmadd(_mm_load_ps(filter[pi3].mCoeffs.data()),
                _mm_shuffle_ps(pf4, pf4, _MM_SHUFFLE(3, 3, 3, 3)),
                _mm_load_ps(filter[pi3].mDeltas.data())))};

        _MM_TRANSPOSE4_PS(r0, r1, r2, r3);
        r0 = _mm_add_ps(_mm_add_ps(r0, r1), _mm_add_ps(r2, r3));

        frac4 = _mm_add_epi32(frac4, increment4);
        pos4 = _mm_add_epi32(pos4, _mm_srli_epi32(frac4, MixerFracBits));
        frac4 = _mm_and_si128(frac4, fracMask4);
        return r0;
    });

    if(const size_t todo{dst.size()&3})
    {
        auto pos = size_t{static_cast<uint>(_mm_cvtsi128_si32(pos4))};
        frac = static_cast<uint>(_mm_cvtsi128_si32(frac4));

        auto out = dst.last(todo);
        std::generate(out.begin(), out.end(), [&pos,&frac,src,increment,filter]
        {
            const uint pi{frac >> CubicPhaseDiffBits}; ASSUME(pi < CubicPhaseCount);
            const float pf{static_cast<float>(frac&CubicPhaseDiffMask) * (1.0f/CubicPhaseDiffOne)};
            const __m128 pf4{_mm_set1_ps(pf)};

            const __m128 f4 = vmadd(_mm_load_ps(filter[pi].mCoeffs.data()), pf4,
                _mm_load_ps(filter[pi].mDeltas.data()));
            __m128 r4{_mm_mul_ps(f4, _mm_loadu_ps(&src[pos]))};

            r4 = _mm_add_ps(r4, _mm_shuffle_ps(r4, r4, _MM_SHUFFLE(0, 1, 2, 3)));
            r4 = _mm_add_ps(r4, _mm_movehl_ps(r4, r4));
            const float output{_mm_cvtss_f32(r4)};

            frac += increment;
            pos  += frac>>MixerFracBits;
            frac &= MixerFracMask;
            return output;
        });
    }
}
