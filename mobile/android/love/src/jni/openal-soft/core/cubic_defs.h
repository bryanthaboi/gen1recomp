#ifndef CORE_CUBIC_DEFS_H
#define CORE_CUBIC_DEFS_H

#include <array>

/* The number of distinct phase intervals within the cubic filter tables. */
constexpr unsigned int CubicPhaseBits{5};
constexpr unsigned int CubicPhaseCount{1 << CubicPhaseBits};

struct CubicCoefficients {
    alignas(16) std::array<float,4> mCoeffs;
    alignas(16) std::array<float,4> mDeltas;
};

#endif /* CORE_CUBIC_DEFS_H */
