#ifndef ALSOFT_ANDROID_CONFIG_SIMD_H
#define ALSOFT_ANDROID_CONFIG_SIMD_H

#ifndef HAVE_SSE
#define HAVE_SSE 0
#endif
#ifndef HAVE_SSE2
#define HAVE_SSE2 0
#endif
#ifndef HAVE_SSE3
#define HAVE_SSE3 0
#endif
#ifndef HAVE_SSE4_1
#define HAVE_SSE4_1 0
#endif

#ifndef HAVE_SSE_INTRINSICS
#define HAVE_SSE_INTRINSICS 0
#endif

#ifndef HAVE_NEON
#define HAVE_NEON 0
#endif

#endif
