
#include "config.h"

#include "althrd_setname.h"


#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

void althrd_setname(const char *name [[maybe_unused]])
{
#if defined(_MSC_VER) && !defined(_M_ARM)

#define MS_VC_EXCEPTION 0x406D1388
#pragma pack(push,8)
    struct InfoStruct {
        DWORD dwType;     // Must be 0x1000.
        LPCSTR szName;    // Pointer to name (in user addr space).
        DWORD dwThreadID; // Thread ID (-1=caller thread).
        DWORD dwFlags;    // Reserved for future use, must be zero.
    };
#pragma pack(pop)
    InfoStruct info{};
    info.dwType = 0x1000;
    info.szName = name;
    info.dwThreadID = ~DWORD{0};
    info.dwFlags = 0;

    /* FIXME: How to do this on MinGW? */
    __try {
        RaiseException(MS_VC_EXCEPTION, 0, sizeof(info)/sizeof(ULONG_PTR), (ULONG_PTR*)&info);
    }
    __except(EXCEPTION_CONTINUE_EXECUTION) {
    }
#undef MS_VC_EXCEPTION
#endif
}

#else

#include <pthread.h>
#ifdef HAVE_PTHREAD_NP_H
#include <pthread_np.h>
#endif

namespace {

using setname_t1 = int(*)(const char*);
using setname_t2 = int(*)(pthread_t, const char*);
using setname_t3 = void(*)(pthread_t, const char*);
using setname_t4 = int(*)(pthread_t, const char*, void*);

[[maybe_unused]] void setname_caller(setname_t1 func, const char *name)
{ func(name); }

[[maybe_unused]] void setname_caller(setname_t2 func, const char *name)
{ func(pthread_self(), name); }

[[maybe_unused]] void setname_caller(setname_t3 func, const char *name)
{ func(pthread_self(), name); }

[[maybe_unused]] void setname_caller(setname_t4 func, const char *name)
{ func(pthread_self(), "%s", const_cast<char*>(name)); /* NOLINT(*-const-cast) */ }

} // namespace

void althrd_setname(const char *name [[maybe_unused]])
{
#if defined(HAVE_PTHREAD_SET_NAME_NP)
    setname_caller(pthread_set_name_np, name);
#elif defined(HAVE_PTHREAD_SETNAME_NP)
    setname_caller(pthread_setname_np, name);
#endif
}

#endif
