#ifndef CORE_AMBIDEFS_H
#define CORE_AMBIDEFS_H

#include <array>
#include <cstddef>
#include <cstdint>

#include "alnumbers.h"


using uint = unsigned int;

/* The maximum number of Ambisonics channels. For a given order (o), the size
 * needed will be (o+1)**2, thus zero-order has 1, first-order has 4, second-
 * order has 9, third-order has 16, and fourth-order has 25.
 */
inline constexpr auto MaxAmbiOrder = std::uint8_t{3};
inline constexpr auto AmbiChannelsFromOrder(std::size_t order) noexcept -> std::size_t
{ return (order+1) * (order+1); }
inline constexpr auto MaxAmbiChannels = size_t{AmbiChannelsFromOrder(MaxAmbiOrder)};

/* A bitmask of ambisonic channels for 0 to 4th order. This only specifies up
 * to 4th order, which is the highest order a 32-bit mask value can specify (a
 * 64-bit mask could handle up to 7th order).
 */
inline constexpr uint Ambi0OrderMask{0x00000001};
inline constexpr uint Ambi1OrderMask{0x0000000f};
inline constexpr uint Ambi2OrderMask{0x000001ff};
inline constexpr uint Ambi3OrderMask{0x0000ffff};
inline constexpr uint Ambi4OrderMask{0x01ffffff};

/* A bitmask of ambisonic channels with height information. If none of these
 * channels are used/needed, there's no height (e.g. with most surround sound
 * speaker setups). This is ACN ordering, with bit 0 being ACN 0, etc.
 */
inline constexpr uint AmbiPeriphonicMask{0xfe7ce4};

/* The maximum number of ambisonic channels for 2D (non-periphonic)
 * representation. This is 2 per each order above zero-order, plus 1 for zero-
 * order. Or simply, o*2 + 1.
 */
inline constexpr auto Ambi2DChannelsFromOrder(std::size_t order) noexcept -> std::size_t
{ return order*2 + 1; }
inline constexpr auto MaxAmbi2DChannels = std::size_t{Ambi2DChannelsFromOrder(MaxAmbiOrder)};


/* NOTE: These are scale factors as applied to Ambisonics content. Decoder
 * coefficients should be divided by these values to get proper scalings.
 */
struct AmbiScale {
    static inline constexpr std::array<float,MaxAmbiChannels> FromN3D{{
        1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f,
        1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f
    }};
    static inline constexpr std::array<float,MaxAmbiChannels> FromSN3D{{
        1.000000000f, /* ACN  0, sqrt(1) */
        1.732050808f, /* ACN  1, sqrt(3) */
        1.732050808f, /* ACN  2, sqrt(3) */
        1.732050808f, /* ACN  3, sqrt(3) */
        2.236067978f, /* ACN  4, sqrt(5) */
        2.236067978f, /* ACN  5, sqrt(5) */
        2.236067978f, /* ACN  6, sqrt(5) */
        2.236067978f, /* ACN  7, sqrt(5) */
        2.236067978f, /* ACN  8, sqrt(5) */
        2.645751311f, /* ACN  9, sqrt(7) */
        2.645751311f, /* ACN 10, sqrt(7) */
        2.645751311f, /* ACN 11, sqrt(7) */
        2.645751311f, /* ACN 12, sqrt(7) */
        2.645751311f, /* ACN 13, sqrt(7) */
        2.645751311f, /* ACN 14, sqrt(7) */
        2.645751311f, /* ACN 15, sqrt(7) */
    }};
    static inline constexpr std::array<float,MaxAmbiChannels> FromFuMa{{
        1.414213562f, /* ACN  0 (W), sqrt(2) */
        1.732050808f, /* ACN  1 (Y), sqrt(3) */
        1.732050808f, /* ACN  2 (Z), sqrt(3) */
        1.732050808f, /* ACN  3 (X), sqrt(3) */
        1.936491673f, /* ACN  4 (V), sqrt(15)/2 */
        1.936491673f, /* ACN  5 (T), sqrt(15)/2 */
        2.236067978f, /* ACN  6 (R), sqrt(5) */
        1.936491673f, /* ACN  7 (S), sqrt(15)/2 */
        1.936491673f, /* ACN  8 (U), sqrt(15)/2 */
        2.091650066f, /* ACN  9 (Q), sqrt(35/8) */
        1.972026594f, /* ACN 10 (O), sqrt(35)/3 */
        2.231093404f, /* ACN 11 (M), sqrt(224/45) */
        2.645751311f, /* ACN 12 (K), sqrt(7) */
        2.231093404f, /* ACN 13 (L), sqrt(224/45) */
        1.972026594f, /* ACN 14 (N), sqrt(35)/3 */
        2.091650066f, /* ACN 15 (P), sqrt(35/8) */
    }};
    static inline constexpr std::array<float,MaxAmbiChannels> FromUHJ{{
        1.000000000f, /* ACN  0 (W), sqrt(1) */
        1.224744871f, /* ACN  1 (Y), sqrt(3/2) */
        1.224744871f, /* ACN  2 (Z), sqrt(3/2) */
        1.224744871f, /* ACN  3 (X), sqrt(3/2) */
        /* Higher orders not relevant for UHJ. */
        1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f,
    }};

    /* Retrieves per-order HF scaling factors for "upsampling" ambisonic data. */
    static std::array<float,MaxAmbiOrder+1> GetHFOrderScales(const uint src_order,
        const uint dev_order, const bool horizontalOnly) noexcept;

    static const std::array<std::array<float,MaxAmbiChannels>,4> FirstOrderUp;
    static const std::array<std::array<float,MaxAmbiChannels>,4> FirstOrder2DUp;
    static const std::array<std::array<float,MaxAmbiChannels>,9> SecondOrderUp;
    static const std::array<std::array<float,MaxAmbiChannels>,9> SecondOrder2DUp;
    static const std::array<std::array<float,MaxAmbiChannels>,16> ThirdOrderUp;
    static const std::array<std::array<float,MaxAmbiChannels>,16> ThirdOrder2DUp;
    static const std::array<std::array<float,MaxAmbiChannels>,25> FourthOrder2DUp;
};

struct AmbiIndex {
    static inline constexpr std::array<std::uint8_t,MaxAmbiChannels> FromFuMa{{
        0,  /* W */
        3,  /* X */
        1,  /* Y */
        2,  /* Z */
        6,  /* R */
        7,  /* S */
        5,  /* T */
        8,  /* U */
        4,  /* V */
        12, /* K */
        13, /* L */
        11, /* M */
        14, /* N */
        10, /* O */
        15, /* P */
        9,  /* Q */
    }};
    static inline constexpr std::array<std::uint8_t,MaxAmbi2DChannels> FromFuMa2D{{
        0,  /* W */
        3,  /* X */
        1,  /* Y */
        8,  /* U */
        4,  /* V */
        15, /* P */
        9,  /* Q */
    }};

    static inline constexpr std::array<std::uint8_t,MaxAmbiChannels> FromACN{{
        0,  1,  2,  3,  4,  5,  6,  7,
        8,  9, 10, 11, 12, 13, 14, 15
    }};
    static inline constexpr std::array<std::uint8_t,MaxAmbi2DChannels> FromACN2D{{
        0, 1,3, 4,8, 9,15
    }};


    static inline constexpr std::array<std::uint8_t,MaxAmbiChannels> OrderFromChannel{{
        0, 1,1,1, 2,2,2,2,2, 3,3,3,3,3,3,3,
    }};
    static inline constexpr std::array<std::uint8_t,MaxAmbi2DChannels> OrderFrom2DChannel{{
        0, 1,1, 2,2, 3,3,
    }};
};


/**
 * Calculates ambisonic encoder coefficients using the X, Y, and Z direction
 * components, which must represent a normalized (unit length) vector.
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
constexpr auto CalcAmbiCoeffs(const float y, const float z, const float x)
{
    const float xx{x*x}, yy{y*y}, zz{z*z}, xy{x*y}, yz{y*z}, xz{x*z};

    return std::array<float,MaxAmbiChannels>{{
        /* Zeroth-order */
        1.0f, /* ACN 0 = 1 */
        /* First-order */
        al::numbers::sqrt3_v<float> * y, /* ACN 1 = sqrt(3) * Y */
        al::numbers::sqrt3_v<float> * z, /* ACN 2 = sqrt(3) * Z */
        al::numbers::sqrt3_v<float> * x, /* ACN 3 = sqrt(3) * X */
        /* Second-order */
        3.872983346e+00f * xy,               /* ACN 4 = sqrt(15) * X * Y */
        3.872983346e+00f * yz,               /* ACN 5 = sqrt(15) * Y * Z */
        1.118033989e+00f * (3.0f*zz - 1.0f), /* ACN 6 = sqrt(5)/2 * (3*Z*Z - 1) */
        3.872983346e+00f * xz,               /* ACN 7 = sqrt(15) * X * Z */
        1.936491673e+00f * (xx - yy),        /* ACN 8 = sqrt(15)/2 * (X*X - Y*Y) */
        /* Third-order */
        2.091650066e+00f * (y*(3.0f*xx - yy)),   /* ACN  9 = sqrt(35/8) * Y * (3*X*X - Y*Y) */
        1.024695076e+01f * (z*xy),               /* ACN 10 = sqrt(105) * Z * X * Y */
        1.620185175e+00f * (y*(5.0f*zz - 1.0f)), /* ACN 11 = sqrt(21/8) * Y * (5*Z*Z - 1) */
        1.322875656e+00f * (z*(5.0f*zz - 3.0f)), /* ACN 12 = sqrt(7)/2 * Z * (5*Z*Z - 3) */
        1.620185175e+00f * (x*(5.0f*zz - 1.0f)), /* ACN 13 = sqrt(21/8) * X * (5*Z*Z - 1) */
        5.123475383e+00f * (z*(xx - yy)),        /* ACN 14 = sqrt(105)/2 * Z * (X*X - Y*Y) */
        2.091650066e+00f * (x*(xx - 3.0f*yy)),   /* ACN 15 = sqrt(35/8) * X * (X*X - 3*Y*Y) */
        /* Fourth-order */
        /* ACN 16 = sqrt(35)*3/2 * X * Y * (X*X - Y*Y) */
        /* ACN 17 = sqrt(35/2)*3/2 * (3*X*X - Y*Y) * Y * Z */
        /* ACN 18 = sqrt(5)*3/2 * X * Y * (7*Z*Z - 1) */
        /* ACN 19 = sqrt(5/2)*3/2 * Y * Z * (7*Z*Z - 3) */
        /* ACN 20 = 3/8 * (35*Z*Z*Z*Z - 30*Z*Z + 3) */
        /* ACN 21 = sqrt(5/2)*3/2 * X * Z * (7*Z*Z - 3) */
        /* ACN 22 = sqrt(5)*3/4 * (X*X - Y*Y) * (7*Z*Z - 1) */
        /* ACN 23 = sqrt(35/2)*3/2 * (X*X - 3*Y*Y) * X * Z */
        /* ACN 24 = sqrt(35)*3/8 * (X*X*X*X - 6*X*X*Y*Y + Y*Y*Y*Y) */
    }};
}

#endif /* CORE_AMBIDEFS_H */
