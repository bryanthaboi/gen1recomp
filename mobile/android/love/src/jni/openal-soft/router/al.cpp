
#include "config.h"

#include <cstddef>

#include "AL/al.h"
#include "router.h"


#define DECL_THUNK1(R,n,T1)                                                   \
AL_API auto AL_APIENTRY n(T1 a) noexcept -> R                                 \
{                                                                             \
    DriverIface *iface = GetThreadDriver();                                   \
    if(!iface) iface = CurrentCtxDriver.load(std::memory_order_acquire);      \
    return iface->n(a);                                                       \
}
#define DECL_THUNK2(R,n,T1,T2)                                                \
AL_API auto AL_APIENTRY n(T1 a, T2 b) noexcept -> R                           \
{                                                                             \
    DriverIface *iface = GetThreadDriver();                                   \
    if(!iface) iface = CurrentCtxDriver.load(std::memory_order_acquire);      \
    return iface->n(a, b);                                                    \
}
#define DECL_THUNK3(R,n,T1,T2,T3)                                             \
AL_API auto AL_APIENTRY n(T1 a, T2 b, T3 c) noexcept -> R                     \
{                                                                             \
    DriverIface *iface = GetThreadDriver();                                   \
    if(!iface) iface = CurrentCtxDriver.load(std::memory_order_acquire);      \
    return iface->n(a, b, c);                                                 \
}
#define DECL_THUNK4(R,n,T1,T2,T3,T4)                                          \
AL_API auto AL_APIENTRY n(T1 a, T2 b, T3 c, T4 d) noexcept -> R               \
{                                                                             \
    DriverIface *iface = GetThreadDriver();                                   \
    if(!iface) iface = CurrentCtxDriver.load(std::memory_order_acquire);      \
    return iface->n(a, b, c, d);                                              \
}
#define DECL_THUNK5(R,n,T1,T2,T3,T4,T5)                                       \
AL_API auto AL_APIENTRY n(T1 a, T2 b, T3 c, T4 d, T5 e) noexcept -> R         \
{                                                                             \
    DriverIface *iface = GetThreadDriver();                                   \
    if(!iface) iface = CurrentCtxDriver.load(std::memory_order_acquire);      \
    return iface->n(a, b, c, d, e);                                           \
}


/* Ugly hack for some apps calling alGetError without a current context, and
 * expecting it to be AL_NO_ERROR.
 */
AL_API auto AL_APIENTRY alGetError() noexcept -> ALenum
{
    DriverIface *iface = GetThreadDriver();
    if(!iface) iface = CurrentCtxDriver.load(std::memory_order_acquire);
    return iface ? iface->alGetError() : AL_NO_ERROR;
}


DECL_THUNK1(void, alDopplerFactor, ALfloat)
DECL_THUNK1(void, alDopplerVelocity, ALfloat)
DECL_THUNK1(void, alSpeedOfSound, ALfloat)
DECL_THUNK1(void, alDistanceModel, ALenum)

DECL_THUNK1(void, alEnable, ALenum)
DECL_THUNK1(void, alDisable, ALenum)
DECL_THUNK1(ALboolean, alIsEnabled, ALenum)

DECL_THUNK1(const ALchar*, alGetString, ALenum)
DECL_THUNK2(void, alGetBooleanv, ALenum, ALboolean*)
DECL_THUNK2(void, alGetIntegerv, ALenum, ALint*)
DECL_THUNK2(void, alGetFloatv, ALenum, ALfloat*)
DECL_THUNK2(void, alGetDoublev, ALenum, ALdouble*)
DECL_THUNK1(ALboolean, alGetBoolean, ALenum)
DECL_THUNK1(ALint, alGetInteger, ALenum)
DECL_THUNK1(ALfloat, alGetFloat, ALenum)
DECL_THUNK1(ALdouble, alGetDouble, ALenum)

DECL_THUNK1(ALboolean, alIsExtensionPresent, const ALchar*)
DECL_THUNK1(void*, alGetProcAddress, const ALchar*)
DECL_THUNK1(ALenum, alGetEnumValue, const ALchar*)

DECL_THUNK2(void, alListenerf, ALenum, ALfloat)
DECL_THUNK4(void, alListener3f, ALenum, ALfloat, ALfloat, ALfloat)
DECL_THUNK2(void, alListenerfv, ALenum, const ALfloat*)
DECL_THUNK2(void, alListeneri, ALenum, ALint)
DECL_THUNK4(void, alListener3i, ALenum, ALint, ALint, ALint)
DECL_THUNK2(void, alListeneriv, ALenum, const ALint*)
DECL_THUNK2(void, alGetListenerf, ALenum, ALfloat*)
DECL_THUNK4(void, alGetListener3f, ALenum, ALfloat*, ALfloat*, ALfloat*)
DECL_THUNK2(void, alGetListenerfv, ALenum, ALfloat*)
DECL_THUNK2(void, alGetListeneri, ALenum, ALint*)
DECL_THUNK4(void, alGetListener3i, ALenum, ALint*, ALint*, ALint*)
DECL_THUNK2(void, alGetListeneriv, ALenum, ALint*)

DECL_THUNK2(void, alGenSources, ALsizei, ALuint*)
DECL_THUNK2(void, alDeleteSources, ALsizei, const ALuint*)
DECL_THUNK1(ALboolean, alIsSource, ALuint)
DECL_THUNK3(void, alSourcef, ALuint, ALenum, ALfloat)
DECL_THUNK5(void, alSource3f, ALuint, ALenum, ALfloat, ALfloat, ALfloat)
DECL_THUNK3(void, alSourcefv, ALuint, ALenum, const ALfloat*)
DECL_THUNK3(void, alSourcei, ALuint, ALenum, ALint)
DECL_THUNK5(void, alSource3i, ALuint, ALenum, ALint, ALint, ALint)
DECL_THUNK3(void, alSourceiv, ALuint, ALenum, const ALint*)
DECL_THUNK3(void, alGetSourcef, ALuint, ALenum, ALfloat*)
DECL_THUNK5(void, alGetSource3f, ALuint, ALenum, ALfloat*, ALfloat*, ALfloat*)
DECL_THUNK3(void, alGetSourcefv, ALuint, ALenum, ALfloat*)
DECL_THUNK3(void, alGetSourcei, ALuint, ALenum, ALint*)
DECL_THUNK5(void, alGetSource3i, ALuint, ALenum, ALint*, ALint*, ALint*)
DECL_THUNK3(void, alGetSourceiv, ALuint, ALenum, ALint*)
DECL_THUNK2(void, alSourcePlayv, ALsizei, const ALuint*)
DECL_THUNK2(void, alSourceStopv, ALsizei, const ALuint*)
DECL_THUNK2(void, alSourceRewindv, ALsizei, const ALuint*)
DECL_THUNK2(void, alSourcePausev, ALsizei, const ALuint*)
DECL_THUNK1(void, alSourcePlay, ALuint)
DECL_THUNK1(void, alSourceStop, ALuint)
DECL_THUNK1(void, alSourceRewind, ALuint)
DECL_THUNK1(void, alSourcePause, ALuint)
DECL_THUNK3(void, alSourceQueueBuffers, ALuint, ALsizei, const ALuint*)
DECL_THUNK3(void, alSourceUnqueueBuffers, ALuint, ALsizei, ALuint*)

DECL_THUNK2(void, alGenBuffers, ALsizei, ALuint*)
DECL_THUNK2(void, alDeleteBuffers, ALsizei, const ALuint*)
DECL_THUNK1(ALboolean, alIsBuffer, ALuint)
DECL_THUNK3(void, alBufferf, ALuint, ALenum, ALfloat)
DECL_THUNK5(void, alBuffer3f, ALuint, ALenum, ALfloat, ALfloat, ALfloat)
DECL_THUNK3(void, alBufferfv, ALuint, ALenum, const ALfloat*)
DECL_THUNK3(void, alBufferi, ALuint, ALenum, ALint)
DECL_THUNK5(void, alBuffer3i, ALuint, ALenum, ALint, ALint, ALint)
DECL_THUNK3(void, alBufferiv, ALuint, ALenum, const ALint*)
DECL_THUNK3(void, alGetBufferf, ALuint, ALenum, ALfloat*)
DECL_THUNK5(void, alGetBuffer3f, ALuint, ALenum, ALfloat*, ALfloat*, ALfloat*)
DECL_THUNK3(void, alGetBufferfv, ALuint, ALenum, ALfloat*)
DECL_THUNK3(void, alGetBufferi, ALuint, ALenum, ALint*)
DECL_THUNK5(void, alGetBuffer3i, ALuint, ALenum, ALint*, ALint*, ALint*)
DECL_THUNK3(void, alGetBufferiv, ALuint, ALenum, ALint*)
DECL_THUNK5(void, alBufferData, ALuint, ALenum, const ALvoid*, ALsizei, ALsizei)

/* EFX 1.0. Required here to be exported from libOpenAL32.dll.a/OpenAL32.lib
 * with the router enabled.
 */
DECL_THUNK2(void, alGenFilters, ALsizei, ALuint*)
DECL_THUNK2(void, alDeleteFilters, ALsizei, const ALuint*)
DECL_THUNK1(ALboolean, alIsFilter, ALuint)
DECL_THUNK3(void, alFilterf, ALuint, ALenum, ALfloat)
DECL_THUNK3(void, alFilterfv, ALuint, ALenum, const ALfloat*)
DECL_THUNK3(void, alFilteri, ALuint, ALenum, ALint)
DECL_THUNK3(void, alFilteriv, ALuint, ALenum, const ALint*)
DECL_THUNK3(void, alGetFilterf, ALuint, ALenum, ALfloat*)
DECL_THUNK3(void, alGetFilterfv, ALuint, ALenum, ALfloat*)
DECL_THUNK3(void, alGetFilteri, ALuint, ALenum, ALint*)
DECL_THUNK3(void, alGetFilteriv, ALuint, ALenum, ALint*)

DECL_THUNK2(void, alGenEffects, ALsizei, ALuint*)
DECL_THUNK2(void, alDeleteEffects, ALsizei, const ALuint*)
DECL_THUNK1(ALboolean, alIsEffect, ALuint)
DECL_THUNK3(void, alEffectf, ALuint, ALenum, ALfloat)
DECL_THUNK3(void, alEffectfv, ALuint, ALenum, const ALfloat*)
DECL_THUNK3(void, alEffecti, ALuint, ALenum, ALint)
DECL_THUNK3(void, alEffectiv, ALuint, ALenum, const ALint*)
DECL_THUNK3(void, alGetEffectf, ALuint, ALenum, ALfloat*)
DECL_THUNK3(void, alGetEffectfv, ALuint, ALenum, ALfloat*)
DECL_THUNK3(void, alGetEffecti, ALuint, ALenum, ALint*)
DECL_THUNK3(void, alGetEffectiv, ALuint, ALenum, ALint*)

DECL_THUNK2(void, alGenAuxiliaryEffectSlots, ALsizei, ALuint*)
DECL_THUNK2(void, alDeleteAuxiliaryEffectSlots, ALsizei, const ALuint*)
DECL_THUNK1(ALboolean, alIsAuxiliaryEffectSlot, ALuint)
DECL_THUNK3(void, alAuxiliaryEffectSlotf, ALuint, ALenum, ALfloat)
DECL_THUNK3(void, alAuxiliaryEffectSlotfv, ALuint, ALenum, const ALfloat*)
DECL_THUNK3(void, alAuxiliaryEffectSloti, ALuint, ALenum, ALint)
DECL_THUNK3(void, alAuxiliaryEffectSlotiv, ALuint, ALenum, const ALint*)
DECL_THUNK3(void, alGetAuxiliaryEffectSlotf, ALuint, ALenum, ALfloat*)
DECL_THUNK3(void, alGetAuxiliaryEffectSlotfv, ALuint, ALenum, ALfloat*)
DECL_THUNK3(void, alGetAuxiliaryEffectSloti, ALuint, ALenum, ALint*)
DECL_THUNK3(void, alGetAuxiliaryEffectSlotiv, ALuint, ALenum, ALint*)
