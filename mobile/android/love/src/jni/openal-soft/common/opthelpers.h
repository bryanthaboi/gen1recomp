#ifndef OPTHELPERS_H
#define OPTHELPERS_H

#include <cstdint>
#include <utility>
#include <memory>

#ifdef __has_builtin
#define HAS_BUILTIN __has_builtin
#else
#define HAS_BUILTIN(x) (0)
#endif

#ifdef __has_cpp_attribute
#define HAS_ATTRIBUTE __has_cpp_attribute
#else
#define HAS_ATTRIBUTE(x) (0)
#endif

#ifdef __GNUC__
#define force_inline [[gnu::always_inline]] inline
#define NOINLINE [[gnu::noinline]]
#elif defined(_MSC_VER)
#define force_inline __forceinline
#define NOINLINE __declspec(noinline)
#else
#define force_inline inline
#define NOINLINE
#endif

#if defined(__MINGW32__) && defined(__i386__)
/* 32-bit MinGW targets have a bug where __STDCPP_DEFAULT_NEW_ALIGNMENT__
 * reports 16, despite the default operator new calling standard malloc which
 * only guarantees 8-byte alignment. As a result, structs that need and specify
 * 16-byte alignment only get 8-byte alignment. Explicitly specifying 32-byte
 * alignment forces the over-aligned operator new to be called, giving the
 * correct (if larger than necessary) alignment.
 *
 * Technically this bug affects 32-bit GCC more generally, but typically only
 * with fairly old glibc versions as newer versions do guarantee the 16-byte
 * alignment as specified. MinGW is reliant on msvcrt.dll's malloc however,
 * which can't be updated to give that guarantee.
 */
#define SIMDALIGN alignas(32)
#else
#define SIMDALIGN
#endif

/* Unlike the likely attribute, ASSUME requires the condition to be true or
 * else it invokes undefined behavior. It's essentially an assert without
 * actually checking the condition at run-time, allowing for stronger
 * optimizations than the likely attribute.
 */
#if HAS_BUILTIN(__builtin_assume)
#define ASSUME __builtin_assume
#elif defined(_MSC_VER)
#define ASSUME __assume
#elif __has_attribute(assume)
#define ASSUME(x) [[assume(x)]]
#elif HAS_BUILTIN(__builtin_unreachable)
#define ASSUME(x) do { if(x) break; __builtin_unreachable(); } while(0)
#else
#define ASSUME(x) (static_cast<void>(0))
#endif

/* This shouldn't be needed since unknown attributes are ignored, but older
 * versions of GCC choke on the attribute syntax in certain situations.
 */
#if HAS_ATTRIBUTE(likely)
#define LIKELY [[likely]]
#define UNLIKELY [[unlikely]]
#else
#define LIKELY
#define UNLIKELY
#endif

namespace al {

template<typename T>
constexpr std::underlying_type_t<T> to_underlying(T e) noexcept
{ return static_cast<std::underlying_type_t<T>>(e); }

[[noreturn]] inline void unreachable()
{
#if HAS_BUILTIN(__builtin_unreachable)
    __builtin_unreachable();
#else
    ASSUME(false);
#endif
}

template<std::size_t alignment, typename T>
force_inline constexpr auto assume_aligned(T *ptr) noexcept
{
#ifdef __cpp_lib_assume_aligned
    return std::assume_aligned<alignment,T>(ptr);
#elif HAS_BUILTIN(__builtin_assume_aligned)
    return static_cast<T*>(__builtin_assume_aligned(ptr, alignment));
#elif defined(_MSC_VER)
    constexpr std::size_t alignment_mask{(1<<alignment) - 1};
    if((reinterpret_cast<std::uintptr_t>(ptr)&alignment_mask) == 0)
        return ptr;
    __assume(0);
#elif defined(__ICC)
    __assume_aligned(ptr, alignment);
    return ptr;
#else
    return ptr;
#endif
}

} // namespace al

#endif /* OPTHELPERS_H */
