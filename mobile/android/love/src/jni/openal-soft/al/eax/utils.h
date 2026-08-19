#ifndef EAX_UTILS_INCLUDED
#define EAX_UTILS_INCLUDED

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <type_traits>

#include "opthelpers.h"

using EaxDirtyFlags = unsigned int;

struct EaxAlLowPassParam {
    float gain;
    float gain_hf;
};

void eax_log_exception(std::string_view message) noexcept;

template<typename TException, typename TValue>
void eax_validate_range(std::string_view value_name, const TValue& value, const TValue& min_value,
    const TValue& max_value)
{
    if(value >= min_value && value <= max_value) LIKELY
        return;

    const auto message =
        std::string{value_name} +
        " out of range (value: " +
        std::to_string(value) + "; min: " +
        std::to_string(min_value) + "; max: " +
        std::to_string(max_value) + ").";

    throw TException{message.c_str()};
}

namespace detail {

template<typename T>
struct EaxIsBitFieldStruct {
private:
    using yes = std::true_type;
    using no = std::false_type;

    template<typename U>
    static auto test(int) -> decltype(std::declval<typename U::EaxIsBitFieldStruct>(), yes{});

    template<typename>
    static no test(...);

public:
    static constexpr auto value = std::is_same<decltype(test<T>(0)), yes>::value;
};

template<typename T, typename TValue>
inline bool eax_bit_fields_are_equal(const T& lhs, const T& rhs) noexcept
{
    static_assert(sizeof(T) == sizeof(TValue), "Invalid type size.");
    return reinterpret_cast<const TValue&>(lhs) == reinterpret_cast<const TValue&>(rhs);
}

} // namespace detail

template<
    typename T,
    std::enable_if_t<detail::EaxIsBitFieldStruct<T>::value, int> = 0
>
inline bool operator==(const T& lhs, const T& rhs) noexcept
{
    using Value = std::conditional_t<
        sizeof(T) == 1,
        std::uint8_t,
        std::conditional_t<
            sizeof(T) == 2,
            std::uint16_t,
            std::conditional_t<
                sizeof(T) == 4,
                std::uint32_t,
                void>>>;

    static_assert(!std::is_same<Value, void>::value, "Unsupported type.");
    return detail::eax_bit_fields_are_equal<T, Value>(lhs, rhs);
}

template<
    typename T,
    std::enable_if_t<detail::EaxIsBitFieldStruct<T>::value, int> = 0
>
inline bool operator!=(const T& lhs, const T& rhs) noexcept
{
    return !(lhs == rhs);
}

#endif // !EAX_UTILS_INCLUDED
