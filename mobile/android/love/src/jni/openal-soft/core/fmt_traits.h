#ifndef CORE_FMT_TRAITS_H
#define CORE_FMT_TRAITS_H

#include <array>
#include <cstdint>

#include "storage_formats.h"


namespace al {

extern const std::array<std::int16_t,256> muLawDecompressionTable;
extern const std::array<std::int16_t,256> aLawDecompressionTable;


template<FmtType T>
struct FmtTypeTraits { };

template<>
struct FmtTypeTraits<FmtUByte> {
    using Type = std::uint8_t;

    constexpr float operator()(const Type val) const noexcept
    { return float(val)*(1.0f/128.0f) - 1.0f; }
};
template<>
struct FmtTypeTraits<FmtShort> {
    using Type = std::int16_t;

    constexpr float operator()(const Type val) const noexcept
    { return float(val) * (1.0f/32768.0f); }
};
template<>
struct FmtTypeTraits<FmtInt> {
    using Type = std::int32_t;

    constexpr float operator()(const Type val) const noexcept
    { return static_cast<float>(val)*(1.0f/2147483648.0f); }
};
template<>
struct FmtTypeTraits<FmtFloat> {
    using Type = float;

    constexpr float operator()(const Type val) const noexcept { return val; }
};
template<>
struct FmtTypeTraits<FmtDouble> {
    using Type = double;

    constexpr float operator()(const Type val) const noexcept { return static_cast<float>(val); }
};
template<>
struct FmtTypeTraits<FmtMulaw> {
    using Type = std::uint8_t;

    constexpr float operator()(const Type val) const noexcept
    { return float(muLawDecompressionTable[val]) * (1.0f/32768.0f); }
};
template<>
struct FmtTypeTraits<FmtAlaw> {
    using Type = std::uint8_t;

    constexpr float operator()(const Type val) const noexcept
    { return float(aLawDecompressionTable[val]) * (1.0f/32768.0f); }
};

} // namespace al

#endif /* CORE_FMT_TRAITS_H */
