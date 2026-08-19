#ifndef ALHELPERS_H
#define ALHELPERS_H

#include "AL/al.h"
#include "AL/alc.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Some helper functions to get the name from the format enums. */
const char *FormatName(ALenum format);

/* Easy device init/deinit functions. InitAL returns 0 on success. */
int InitAL(char ***argv, int *argc);
void CloseAL(void);

/* Cross-platform timeget and sleep functions. */
int altime_get(void);
void al_nssleep(unsigned long nsec);

/* C doesn't allow casting between function and non-function pointer types, so
 * with C99 we need to use a union to reinterpret the pointer type. Pre-C99
 * still needs to use a normal cast and live with the warning (C++ is fine with
 * a regular reinterpret_cast).
 */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L
#define FUNCTION_CAST(T, ptr) (union{void *p; T f;}){ptr}.f
#elif defined(__cplusplus)
#define FUNCTION_CAST(T, ptr) reinterpret_cast<T>(ptr)
#else
#define FUNCTION_CAST(T, ptr) (T)(ptr)
#endif

#ifdef __cplusplus
} // extern "C"

#include <cstdio>
#include <iostream>
#include <string>
#include <string_view>

#include "alspan.h"

int InitAL(al::span<std::string_view> &args)
{
    ALCdevice *device{};

    /* Open and initialize a device */
    if(args.size() > 1 && args[0] == "-device")
    {
        device = alcOpenDevice(std::string{args[1]}.c_str());
        if(!device)
            std::cerr<< "Failed to open \""<<args[1]<<"\", trying default\n";
        args = args.subspan(2);
    }
    if(!device)
        device = alcOpenDevice(nullptr);
    if(!device)
    {
        std::fprintf(stderr, "Could not open a device!\n");
        return 1;
    }

    ALCcontext *ctx{alcCreateContext(device, nullptr)};
    if(!ctx || alcMakeContextCurrent(ctx) == ALC_FALSE)
    {
        if(ctx)
            alcDestroyContext(ctx);
        alcCloseDevice(device);
        std::fprintf(stderr, "Could not set a context!\n");
        return 1;
    }

    const ALCchar *name{};
    if(alcIsExtensionPresent(device, "ALC_ENUMERATE_ALL_EXT"))
        name = alcGetString(device, ALC_ALL_DEVICES_SPECIFIER);
    if(!name || alcGetError(device) != AL_NO_ERROR)
        name = alcGetString(device, ALC_DEVICE_SPECIFIER);
    std::printf("Opened \"%s\"\n", name);

    return 0;
}

#endif

#endif /* ALHELPERS_H */
