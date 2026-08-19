#ifndef COMMON_COMPTR_H
#define COMMON_COMPTR_H

#include <cstddef>
#include <memory>
#include <type_traits>
#include <utility>
#include <variant>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>

struct ComWrapper {
    HRESULT mStatus{};

    ComWrapper(void *reserved, DWORD coinit)
        : mStatus{CoInitializeEx(reserved, coinit)}
    { }
    ComWrapper(DWORD coinit=COINIT_APARTMENTTHREADED)
        : mStatus{CoInitializeEx(nullptr, coinit)}
    { }
    ComWrapper(ComWrapper&& rhs) { mStatus = std::exchange(rhs.mStatus, E_FAIL); }
    ComWrapper(const ComWrapper&) = delete;
    ~ComWrapper() { if(SUCCEEDED(mStatus)) CoUninitialize(); }

    ComWrapper& operator=(ComWrapper&& rhs)
    {
        if(SUCCEEDED(mStatus))
            CoUninitialize();
        mStatus = std::exchange(rhs.mStatus, E_FAIL);
        return *this;
    }
    ComWrapper& operator=(const ComWrapper&) = delete;

    [[nodiscard]]
    HRESULT status() const noexcept { return mStatus; }
    explicit operator bool() const noexcept { return SUCCEEDED(status()); }

    void uninit()
    {
        if(SUCCEEDED(mStatus))
            CoUninitialize();
        mStatus = E_FAIL;
    }
};


template<typename T> /* NOLINTNEXTLINE(clazy-rule-of-three) False positive */
struct ComPtr {
    using element_type = T;

    static constexpr bool RefIsNoexcept{noexcept(std::declval<T&>().AddRef())
        && noexcept(std::declval<T&>().Release())};

    ComPtr() noexcept = default;
    ComPtr(const ComPtr &rhs) noexcept(RefIsNoexcept) : mPtr{rhs.mPtr}
    { if(mPtr) mPtr->AddRef(); }
    ComPtr(ComPtr&& rhs) noexcept : mPtr{rhs.mPtr} { rhs.mPtr = nullptr; }
    ComPtr(std::nullptr_t) noexcept { }
    explicit ComPtr(T *ptr) noexcept : mPtr{ptr} { }
    ~ComPtr() { if(mPtr) mPtr->Release(); }

    /* NOLINTNEXTLINE(bugprone-unhandled-self-assignment) Yes it is. */
    ComPtr& operator=(const ComPtr &rhs) noexcept(RefIsNoexcept)
    {
        if constexpr(RefIsNoexcept)
        {
            if(rhs.mPtr) rhs.mPtr->AddRef();
            if(mPtr) mPtr->Release();
            mPtr = rhs.mPtr;
            return *this;
        }
        else
        {
            ComPtr tmp{rhs};
            if(mPtr) mPtr->Release();
            mPtr = tmp.release();
            return *this;
        }
    }
    ComPtr& operator=(ComPtr&& rhs) noexcept(RefIsNoexcept)
    {
        if(&rhs != this)
        {
            if(mPtr) mPtr->Release();
            mPtr = std::exchange(rhs.mPtr, nullptr);
        }
        return *this;
    }

    void reset(T *ptr=nullptr) noexcept(RefIsNoexcept)
    {
        if(mPtr) mPtr->Release();
        mPtr = ptr;
    }

    explicit operator bool() const noexcept { return mPtr != nullptr; }

    T& operator*() const noexcept { return *mPtr; }
    T* operator->() const noexcept { return mPtr; }
    T* get() const noexcept { return mPtr; }

    T* release() noexcept { return std::exchange(mPtr, nullptr); }

    void swap(ComPtr &rhs) noexcept { std::swap(mPtr, rhs.mPtr); }
    void swap(ComPtr&& rhs) noexcept { std::swap(mPtr, rhs.mPtr); }

private:
    T *mPtr{nullptr};
};

#endif
