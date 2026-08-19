#ifndef COMMON_ALSEM_H
#define COMMON_ALSEM_H

#if defined(__APPLE__)
#include <AvailabilityMacros.h>
#include <TargetConditionals.h>
#if (((MAC_OS_X_VERSION_MIN_REQUIRED > 1050) && !defined(__ppc__)) || TARGET_OS_IOS || TARGET_OS_TV)
#include <dispatch/dispatch.h>
#define AL_APPLE_HAVE_DISPATCH 1
#else
#include <semaphore.h> /* Fallback option for Apple without a working libdispatch */
#endif
#elif !defined(_WIN32)
#include <semaphore.h>
#endif

namespace al {

class semaphore {
#ifdef _WIN32
    using native_type = void*;
#elif defined(AL_APPLE_HAVE_DISPATCH)
    using native_type = dispatch_semaphore_t;
#else
    using native_type = sem_t;
#endif
    native_type mSem{};

public:
    semaphore(unsigned int initial=0);
    semaphore(const semaphore&) = delete;
    ~semaphore();

    semaphore& operator=(const semaphore&) = delete;

    void post();
    void wait() noexcept;
    bool try_wait() noexcept;
};

} // namespace al

#endif /* COMMON_ALSEM_H */
