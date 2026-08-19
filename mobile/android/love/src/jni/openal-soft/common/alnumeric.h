#ifndef AL_NUMERIC_H
#define AL_NUMERIC_H

#include "config_simd.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <type_traits>
#ifdef HAVE_INTRIN_H
#include <intrin.h>
#endif
#if HAVE_SSE_INTRINSICS
#include <xmmintrin.h>
#endif

#include "albit.h"
#include "altraits.h"
#include "opthelpers.h"


constexpr auto operator "" _i64(unsigned long long n) noexcept { return static_cast<std::int64_t>(n); }
constexpr auto operator "" _u64(unsigned long long n) noexcept { return static_cast<std::uint64_t>(n); }

constexpr auto operator "" _z(unsigned long long n) noexcept
{ return static_cast<std::make_signed_t<std::size_t>>(n); }
constexpr auto operator "" _uz(unsigned long long n) noexcept { return static_cast<std::size_t>(n); }
constexpr auto operator "" _zu(unsigned long long n) noexcept { return static_cast<std::size_t>(n); }


constexpr auto GetCounterSuffix(size_t count) noexcept -> const char*
{
    auto &suffix = (((count%100)/10) == 1) ? "th" :
        ((count%10) == 1) ? "st" :
        ((count%10) == 2) ? "nd" :
        ((count%10) == 3) ? "rd" : "th";
    return std::data(suffix);
}


constexpr inline float lerpf(float val1, float val2, float mu) noexcept
{ return val1 + (val2-val1)*mu; }
constexpr inline double lerpd(double val1, double val2, double mu) noexcept
{ return val1 + (val2-val1)*mu; }


/** Find the next power-of-2 for non-power-of-2 numbers. */
inline uint32_t NextPowerOf2(uint32_t value) noexcept
{
    if(value > 0)
    {
        value--;
        value |= value>>1;
        value |= value>>2;
        value |= value>>4;
        value |= value>>8;
        value |= value>>16;
    }
    return value+1;
}

/**
 * If the value is not already a multiple of r, round down to the next
 * multiple.
 */
template<typename T>
constexpr T RoundDown(T value, al::type_identity_t<T> r) noexcept
{ return value - (value%r); }

/**
 * If the value is not already a multiple of r, round up to the next multiple.
 */
template<typename T>
constexpr T RoundUp(T value, al::type_identity_t<T> r) noexcept
{ return RoundDown(value + r-1, r); }


/**
 * Fast float-to-int conversion. No particular rounding mode is assumed; the
 * IEEE-754 default is round-to-nearest with ties-to-even, though an app could
 * change it on its own threads. On some systems, a truncating conversion may
 * always be the fastest method.
 */
inline int fastf2i(float f) noexcept
{
#if HAVE_SSE_INTRINSICS
    return _mm_cvt_ss2si(_mm_set_ss(f));

#elif defined(_MSC_VER) && defined(_M_IX86_FP) && _M_IX86_FP == 0

    int i;
    __asm fld f
    __asm fistp i
    return i;

#elif (defined(__GNUC__) || defined(__clang__)) && (defined(__i386__) || defined(__x86_64__)) \
    && !defined(__SSE_MATH__)

    int i;
    __asm__ __volatile__("fistpl %0" : "=m"(i) : "t"(f) : "st");
    return i;

#else

    return static_cast<int>(f);
#endif
}
inline unsigned int fastf2u(float f) noexcept
{ return static_cast<unsigned int>(fastf2i(f)); }

/** Converts float-to-int using standard behavior (truncation). */
inline int float2int(float f) noexcept
{
#if HAVE_SSE_INTRINSICS
    return _mm_cvtt_ss2si(_mm_set_ss(f));

#elif (defined(_MSC_VER) && defined(_M_IX86_FP) && _M_IX86_FP == 0) \
    || ((defined(__GNUC__) || defined(__clang__)) && (defined(__i386__) || defined(__x86_64__)) \
        && !defined(__SSE_MATH__))
    const int conv_i{al::bit_cast<int>(f)};

    const int sign{(conv_i>>31) | 1};
    const int shift{((conv_i>>23)&0xff) - (127+23)};

    /* Over/underflow */
    if(shift >= 31 || shift < -23) UNLIKELY
        return 0;

    const int mant{(conv_i&0x7fffff) | 0x800000};
    if(shift < 0) LIKELY
        return (mant >> -shift) * sign;
    return (mant << shift) * sign;

#else

    return static_cast<int>(f);
#endif
}
inline unsigned int float2uint(float f) noexcept
{ return static_cast<unsigned int>(float2int(f)); }

/** Converts double-to-int using standard behavior (truncation). */
inline int double2int(double d) noexcept
{
#if HAVE_SSE_INTRINSICS
    return _mm_cvttsd_si32(_mm_set_sd(d));

#elif (defined(_MSC_VER) && defined(_M_IX86_FP) && _M_IX86_FP < 2) \
    || ((defined(__GNUC__) || defined(__clang__)) && (defined(__i386__) || defined(__x86_64__)) \
        && !defined(__SSE2_MATH__))
    const int64_t conv_i64{al::bit_cast<int64_t>(d)};

    const int sign{static_cast<int>(conv_i64 >> 63) | 1};
    const int shift{(static_cast<int>(conv_i64 >> 52) & 0x7ff) - (1023 + 52)};

    /* Over/underflow */
    if(shift >= 63 || shift < -52) UNLIKELY
        return 0;

    const int64_t mant{(conv_i64 & 0xfffffffffffff_i64) | 0x10000000000000_i64};
    if(shift < 0) LIKELY
        return static_cast<int>(mant >> -shift) * sign;
    return static_cast<int>(mant << shift) * sign;

#else

    return static_cast<int>(d);
#endif
}

/**
 * Rounds a float to the nearest integral value, according to the current
 * rounding mode. This is essentially an inlined version of rintf, although
 * makes fewer promises (e.g. -0 or -0.25 rounded to 0 may result in +0).
 */
inline float fast_roundf(float f) noexcept
{
#if (defined(__GNUC__) || defined(__clang__)) && (defined(__i386__) || defined(__x86_64__)) \
    && !defined(__SSE_MATH__)

    float out;
    __asm__ __volatile__("frndint" : "=t"(out) : "0"(f));
    return out;

#elif (defined(__GNUC__) || defined(__clang__)) && defined(__aarch64__)

    float out;
    __asm__ volatile("frintx %s0, %s1" : "=w"(out) : "w"(f));
    return out;

#else

    /* Integral limit, where sub-integral precision is not available for
     * floats.
     */
    static constexpr std::array ilim{
         8388608.0f /*  0x1.0p+23 */,
        -8388608.0f /* -0x1.0p+23 */
    };
    const unsigned int conv_i{al::bit_cast<unsigned int>(f)};

    const unsigned int sign{(conv_i>>31)&0x01};
    const unsigned int expo{(conv_i>>23)&0xff};

    if(expo >= 150/*+23*/) UNLIKELY
    {
        /* An exponent (base-2) of 23 or higher is incapable of sub-integral
         * precision, so it's already an integral value. We don't need to worry
         * about infinity or NaN here.
         */
        return f;
    }
    /* Adding the integral limit to the value (with a matching sign) forces a
     * result that has no sub-integral precision, and is consequently forced to
     * round to an integral value. Removing the integral limit then restores
     * the initial value rounded to the integral. The compiler should not
     * optimize this out because of non-associative rules on floating-point
     * math (as long as you don't use -fassociative-math,
     * -funsafe-math-optimizations, -ffast-math, or -Ofast, in which case this
     * may break without __builtin_assoc_barrier support).
     */
#if HAS_BUILTIN(__builtin_assoc_barrier)
    return __builtin_assoc_barrier(f + ilim[sign]) - ilim[sign];
#else
    f += ilim[sign];
    return f - ilim[sign];
#endif
#endif
}


// Converts level (mB) to gain.
inline float level_mb_to_gain(float x)
{
    if(x <= -10'000.0f)
        return 0.0f;
    return std::pow(10.0f, x / 2'000.0f);
}

// Converts gain to level (mB).
inline float gain_to_level_mb(float x)
{
    if(x <= 1e-05f)
        return -10'000.0f;
    return std::max(std::log10(x) * 2'000.0f, -10'000.0f);
}

#endif /* AL_NUMERIC_H */
