#ifndef COMMON_VECMAT_H
#define COMMON_VECMAT_H

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <limits>

#include "alspan.h"


namespace alu {

class Vector {
    alignas(16) std::array<float,4> mVals{};

public:
    constexpr Vector() noexcept = default;
    constexpr Vector(const Vector&) noexcept = default;
    constexpr Vector(Vector&&) noexcept = default;
    constexpr explicit Vector(float a, float b, float c, float d) noexcept : mVals{{a,b,c,d}} { }

    constexpr auto operator=(const Vector&) noexcept -> Vector& = default;
    constexpr auto operator=(Vector&&) noexcept -> Vector& = default;

    [[nodiscard]] constexpr
    auto operator[](std::size_t idx) noexcept -> float& { return mVals[idx]; }
    [[nodiscard]] constexpr
    auto operator[](std::size_t idx) const noexcept -> const float& { return mVals[idx]; }

    constexpr auto operator+=(const Vector &rhs) noexcept -> Vector&
    {
        mVals[0] += rhs.mVals[0];
        mVals[1] += rhs.mVals[1];
        mVals[2] += rhs.mVals[2];
        mVals[3] += rhs.mVals[3];
        return *this;
    }

    [[nodiscard]] constexpr
    auto operator-(const Vector &rhs) const noexcept -> Vector
    {
        return Vector{mVals[0] - rhs.mVals[0], mVals[1] - rhs.mVals[1],
            mVals[2] - rhs.mVals[2], mVals[3] - rhs.mVals[3]};
    }

    constexpr auto normalize() -> float
    {
        const auto length_sqr = float{mVals[0]*mVals[0] + mVals[1]*mVals[1] + mVals[2]*mVals[2]};
        if(length_sqr > std::numeric_limits<float>::epsilon())
        {
            const auto length = float{std::sqrt(length_sqr)};
            auto inv_length = float{1.0f / length};
            mVals[0] *= inv_length;
            mVals[1] *= inv_length;
            mVals[2] *= inv_length;
            return length;
        }
        mVals[0] = mVals[1] = mVals[2] = 0.0f;
        return 0.0f;
    }

    [[nodiscard]] constexpr auto cross_product(const Vector &rhs) const noexcept -> Vector
    {
        return Vector{
            mVals[1]*rhs.mVals[2] - mVals[2]*rhs.mVals[1],
            mVals[2]*rhs.mVals[0] - mVals[0]*rhs.mVals[2],
            mVals[0]*rhs.mVals[1] - mVals[1]*rhs.mVals[0],
            0.0f};
    }

    [[nodiscard]] constexpr auto dot_product(const Vector &rhs) const noexcept -> float
    { return mVals[0]*rhs.mVals[0] + mVals[1]*rhs.mVals[1] + mVals[2]*rhs.mVals[2]; }
};

class Matrix {
    alignas(16) std::array<float,16> mVals{};

public:
    constexpr Matrix() noexcept = default;
    constexpr Matrix(const Matrix&) noexcept = default;
    constexpr Matrix(Matrix&&) noexcept = default;
    constexpr explicit Matrix(
        float aa, float ab, float ac, float ad,
        float ba, float bb, float bc, float bd,
        float ca, float cb, float cc, float cd,
        float da, float db, float dc, float dd) noexcept
        : mVals{{aa,ab,ac,ad, ba,bb,bc,bd, ca,cb,cc,cd, da,db,dc,dd}}
    { }

    constexpr auto operator=(const Matrix&) noexcept -> Matrix& = default;
    constexpr auto operator=(Matrix&&) noexcept -> Matrix& = default;

    [[nodiscard]] constexpr auto operator[](std::size_t idx) noexcept
    { return al::span<float,4>{&mVals[idx*4], 4}; }
    [[nodiscard]] constexpr auto operator[](std::size_t idx) const noexcept
    { return al::span<const float,4>{&mVals[idx*4], 4}; }

    [[nodiscard]] static constexpr auto Identity() noexcept -> Matrix
    {
        return Matrix{
            1.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 1.0f, 0.0f, 0.0f,
            0.0f, 0.0f, 1.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 1.0f};
    }

    [[nodiscard]] friend constexpr
    auto operator*(const Matrix &mtx, const Vector &vec) noexcept -> Vector
    {
        return Vector{
            vec[0]*mtx[0][0] + vec[1]*mtx[1][0] + vec[2]*mtx[2][0] + vec[3]*mtx[3][0],
            vec[0]*mtx[0][1] + vec[1]*mtx[1][1] + vec[2]*mtx[2][1] + vec[3]*mtx[3][1],
            vec[0]*mtx[0][2] + vec[1]*mtx[1][2] + vec[2]*mtx[2][2] + vec[3]*mtx[3][2],
            vec[0]*mtx[0][3] + vec[1]*mtx[1][3] + vec[2]*mtx[2][3] + vec[3]*mtx[3][3]};
    }
};

} // namespace alu

#endif /* COMMON_VECMAT_H */
