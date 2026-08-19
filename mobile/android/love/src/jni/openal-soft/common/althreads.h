#ifndef AL_THREADS_H
#define AL_THREADS_H

#include <cstdint>
#include <stdexcept>
#include <type_traits>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#elif defined(__APPLE__)

#include <pthread.h>

#else

#include <threads.h>
#endif

#include "albit.h"

namespace al {

template<typename T>
class tss {
    static_assert(sizeof(T) <= sizeof(void*));
    static_assert(std::is_trivially_destructible_v<T> && std::is_trivially_copy_constructible_v<T>);

    [[nodiscard]]
    static auto to_ptr(const T &value) noexcept -> void*
    {
        if constexpr(std::is_pointer_v<T>)
        {
            if constexpr(std::is_const_v<std::remove_pointer_t<T>>)
                return const_cast<void*>(static_cast<const void*>(value)); /* NOLINT(*-const-cast) */
            else
                return static_cast<void*>(value);
        }
        else if constexpr(sizeof(T) == sizeof(void*))
            return al::bit_cast<void*>(value);
        else if constexpr(std::is_integral_v<T>)
            return al::bit_cast<void*>(static_cast<std::uintptr_t>(value));
    }

    [[nodiscard]]
    static auto from_ptr(void *ptr) noexcept -> T
    {
        if constexpr(std::is_pointer_v<T>)
            return static_cast<T>(ptr);
        else if constexpr(sizeof(T) == sizeof(void*))
            return al::bit_cast<T>(ptr);
        else if constexpr(std::is_integral_v<T>)
            return static_cast<T>(al::bit_cast<std::uintptr_t>(ptr));
    }

#ifdef _WIN32
    DWORD mTss{TLS_OUT_OF_INDEXES};

public:
    tss() : mTss{TlsAlloc()}
    {
        if(mTss == TLS_OUT_OF_INDEXES)
            throw std::runtime_error{"al::tss::tss()"};
    }
    explicit tss(const T &init) : tss{}
    {
        if(TlsSetValue(mTss, to_ptr(init)) == FALSE)
            throw std::runtime_error{"al::tss::tss(T)"};
    }
    ~tss() { TlsFree(mTss); }

    void set(const T &value) const
    {
        if(TlsSetValue(mTss, to_ptr(value)) == FALSE)
            throw std::runtime_error{"al::tss::set(T)"};
    }

    [[nodiscard]]
    auto get() const noexcept -> T { return from_ptr(TlsGetValue(mTss)); }

#elif defined(__APPLE__)

    pthread_key_t mTss{};

public:
    tss()
    {
        if(int res{pthread_key_create(&mTss, nullptr)}; res != 0)
            throw std::runtime_error{"al::tss::tss()"};
    }
    explicit tss(const T &init) : tss{}
    {
        if(int res{pthread_setspecific(mTss, to_ptr(init))}; res != 0)
            throw std::runtime_error{"al::tss::tss(T)"};
    }
    ~tss() { pthread_key_delete(mTss); }

    void set(const T &value) const
    {
        if(int res{pthread_setspecific(mTss, to_ptr(value))}; res != 0)
            throw std::runtime_error{"al::tss::set(T)"};
    }

    [[nodiscard]]
    auto get() const noexcept -> T { return from_ptr(pthread_getspecific(mTss)); }

#else

    tss_t mTss{};

public:
    tss()
    {
        if(int res{tss_create(&mTss, nullptr)}; res != thrd_success)
            throw std::runtime_error{"al::tss::tss()"};
    }
    explicit tss(const T &init) : tss{}
    {
        if(int res{tss_set(mTss, to_ptr(init))}; res != thrd_success)
            throw std::runtime_error{"al::tss::tss(T)"};
    }
    ~tss() { tss_delete(mTss); }

    void set(const T &value) const
    {
        if(int res{tss_set(mTss, to_ptr(value))}; res != thrd_success)
            throw std::runtime_error{"al::tss::set(T)"};
    }

    [[nodiscard]]
    auto get() const noexcept -> T { return from_ptr(tss_get(mTss)); }
#endif /* _WIN32 */

    tss(const tss&) = delete;
    tss(tss&&) = delete;
    void operator=(const tss&) = delete;
    void operator=(tss&&) = delete;
};

} // namespace al

#endif /* AL_THREADS_H */
