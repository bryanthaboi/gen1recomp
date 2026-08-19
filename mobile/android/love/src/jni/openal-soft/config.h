#ifndef ALSOFT_ANDROID_CONFIG_H
#define ALSOFT_ANDROID_CONFIG_H

#ifndef AL_API
#define AL_API  __attribute__((visibility("default")))
#endif
#ifndef ALC_API
#define ALC_API __attribute__((visibility("default")))
#endif

#if defined(__i386__)
#define FORCE_ALIGN __attribute__((force_align_arg_pointer))
#else
#define FORCE_ALIGN
#endif

#define ALSOFT_EMBED_HRTF_DATA

#define HAVE_DLFCN_H

#define HAVE_PTHREAD_SETSCHEDPARAM

#define HAVE_PTHREAD_SETNAME_NP

#ifndef HAVE_RTKIT
#define HAVE_RTKIT 0
#endif

#ifndef ALSOFT_UWP
#define ALSOFT_UWP 0
#endif

#ifndef ALSOFT_EAX
#define ALSOFT_EAX 0
#endif

#endif
