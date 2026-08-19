
#include "config.h"
#include "config_simd.h"

#include "fpu_ctrl.h"

#ifdef HAVE_INTRIN_H
#include <intrin.h>
#endif
#if HAVE_SSE_INTRINSICS
#include <emmintrin.h>
#elif HAVE_SSE
#include <xmmintrin.h>
#endif

#if HAVE_SSE && !defined(_MM_DENORMALS_ZERO_MASK)
/* Some headers seem to be missing these? */
#define _MM_DENORMALS_ZERO_MASK 0x0040u
#define _MM_DENORMALS_ZERO_ON 0x0040u
#endif

#if !HAVE_SSE_INTRINSICS && HAVE_SSE
#include "cpu_caps.h"
#endif

namespace {

#if defined(__GNUC__) && (defined(__i386__) || defined(__x86_64__))
[[gnu::target("sse")]]
#endif
[[maybe_unused]]
void disable_denormals(unsigned int *state [[maybe_unused]])
{
#if HAVE_SSE_INTRINSICS
    *state = _mm_getcsr();
    unsigned int sseState{*state};
    sseState &= ~(_MM_FLUSH_ZERO_MASK | _MM_DENORMALS_ZERO_MASK);
    sseState |= _MM_FLUSH_ZERO_ON | _MM_DENORMALS_ZERO_ON;
    _mm_setcsr(sseState);

#elif HAVE_SSE

    *state = _mm_getcsr();
    unsigned int sseState{*state};
    sseState &= ~_MM_FLUSH_ZERO_MASK;
    sseState |= _MM_FLUSH_ZERO_ON;
    if((CPUCapFlags&CPU_CAP_SSE2))
    {
        sseState &= ~_MM_DENORMALS_ZERO_MASK;
        sseState |= _MM_DENORMALS_ZERO_ON;
    }
    _mm_setcsr(sseState);
#endif
}

#if defined(__GNUC__) && (defined(__i386__) || defined(__x86_64__))
[[gnu::target("sse")]]
#endif
[[maybe_unused]]
void reset_fpu(unsigned int state [[maybe_unused]])
{
#if HAVE_SSE_INTRINSICS || HAVE_SSE
    _mm_setcsr(state);
#endif
}

} // namespace


unsigned int FPUCtl::Set() noexcept
{
    unsigned int state{};
#if HAVE_SSE_INTRINSICS
    disable_denormals(&state);
#elif HAVE_SSE
    if((CPUCapFlags&CPU_CAP_SSE))
        disable_denormals(&state);
#endif
    return state;
}

void FPUCtl::Reset(unsigned int state [[maybe_unused]]) noexcept
{
#if HAVE_SSE_INTRINSICS
    reset_fpu(state);
#elif HAVE_SSE
    if((CPUCapFlags&CPU_CAP_SSE))
        reset_fpu(state);
#endif
}
