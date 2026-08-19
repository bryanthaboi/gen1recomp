#ifndef ROUTER_ROUTER_H
#define ROUTER_ROUTER_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winnt.h>

#include <atomic>
#include <cstdio>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "AL/alc.h"
#include "AL/al.h"
#include "AL/alext.h"

#include "almalloc.h"


#define MAKE_ALC_VER(major, minor) (((major)<<8) | (minor))

struct DriverIface {
    LPALCCREATECONTEXT alcCreateContext{nullptr};
    LPALCMAKECONTEXTCURRENT alcMakeContextCurrent{nullptr};
    LPALCPROCESSCONTEXT alcProcessContext{nullptr};
    LPALCSUSPENDCONTEXT alcSuspendContext{nullptr};
    LPALCDESTROYCONTEXT alcDestroyContext{nullptr};
    LPALCGETCURRENTCONTEXT alcGetCurrentContext{nullptr};
    LPALCGETCONTEXTSDEVICE alcGetContextsDevice{nullptr};
    LPALCOPENDEVICE alcOpenDevice{nullptr};
    LPALCCLOSEDEVICE alcCloseDevice{nullptr};
    LPALCGETERROR alcGetError{nullptr};
    LPALCISEXTENSIONPRESENT alcIsExtensionPresent{nullptr};
    LPALCGETPROCADDRESS alcGetProcAddress{nullptr};
    LPALCGETENUMVALUE alcGetEnumValue{nullptr};
    LPALCGETSTRING alcGetString{nullptr};
    LPALCGETINTEGERV alcGetIntegerv{nullptr};
    LPALCCAPTUREOPENDEVICE alcCaptureOpenDevice{nullptr};
    LPALCCAPTURECLOSEDEVICE alcCaptureCloseDevice{nullptr};
    LPALCCAPTURESTART alcCaptureStart{nullptr};
    LPALCCAPTURESTOP alcCaptureStop{nullptr};
    LPALCCAPTURESAMPLES alcCaptureSamples{nullptr};

    PFNALCSETTHREADCONTEXTPROC alcSetThreadContext{nullptr};
    PFNALCGETTHREADCONTEXTPROC alcGetThreadContext{nullptr};

    LPALENABLE alEnable{nullptr};
    LPALDISABLE alDisable{nullptr};
    LPALISENABLED alIsEnabled{nullptr};
    LPALGETSTRING alGetString{nullptr};
    LPALGETBOOLEANV alGetBooleanv{nullptr};
    LPALGETINTEGERV alGetIntegerv{nullptr};
    LPALGETFLOATV alGetFloatv{nullptr};
    LPALGETDOUBLEV alGetDoublev{nullptr};
    LPALGETBOOLEAN alGetBoolean{nullptr};
    LPALGETINTEGER alGetInteger{nullptr};
    LPALGETFLOAT alGetFloat{nullptr};
    LPALGETDOUBLE alGetDouble{nullptr};
    LPALGETERROR alGetError{nullptr};
    LPALISEXTENSIONPRESENT alIsExtensionPresent{nullptr};
    LPALGETPROCADDRESS alGetProcAddress{nullptr};
    LPALGETENUMVALUE alGetEnumValue{nullptr};
    LPALLISTENERF alListenerf{nullptr};
    LPALLISTENER3F alListener3f{nullptr};
    LPALLISTENERFV alListenerfv{nullptr};
    LPALLISTENERI alListeneri{nullptr};
    LPALLISTENER3I alListener3i{nullptr};
    LPALLISTENERIV alListeneriv{nullptr};
    LPALGETLISTENERF alGetListenerf{nullptr};
    LPALGETLISTENER3F alGetListener3f{nullptr};
    LPALGETLISTENERFV alGetListenerfv{nullptr};
    LPALGETLISTENERI alGetListeneri{nullptr};
    LPALGETLISTENER3I alGetListener3i{nullptr};
    LPALGETLISTENERIV alGetListeneriv{nullptr};
    LPALGENSOURCES alGenSources{nullptr};
    LPALDELETESOURCES alDeleteSources{nullptr};
    LPALISSOURCE alIsSource{nullptr};
    LPALSOURCEF alSourcef{nullptr};
    LPALSOURCE3F alSource3f{nullptr};
    LPALSOURCEFV alSourcefv{nullptr};
    LPALSOURCEI alSourcei{nullptr};
    LPALSOURCE3I alSource3i{nullptr};
    LPALSOURCEIV alSourceiv{nullptr};
    LPALGETSOURCEF alGetSourcef{nullptr};
    LPALGETSOURCE3F alGetSource3f{nullptr};
    LPALGETSOURCEFV alGetSourcefv{nullptr};
    LPALGETSOURCEI alGetSourcei{nullptr};
    LPALGETSOURCE3I alGetSource3i{nullptr};
    LPALGETSOURCEIV alGetSourceiv{nullptr};
    LPALSOURCEPLAYV alSourcePlayv{nullptr};
    LPALSOURCESTOPV alSourceStopv{nullptr};
    LPALSOURCEREWINDV alSourceRewindv{nullptr};
    LPALSOURCEPAUSEV alSourcePausev{nullptr};
    LPALSOURCEPLAY alSourcePlay{nullptr};
    LPALSOURCESTOP alSourceStop{nullptr};
    LPALSOURCEREWIND alSourceRewind{nullptr};
    LPALSOURCEPAUSE alSourcePause{nullptr};
    LPALSOURCEQUEUEBUFFERS alSourceQueueBuffers{nullptr};
    LPALSOURCEUNQUEUEBUFFERS alSourceUnqueueBuffers{nullptr};
    LPALGENBUFFERS alGenBuffers{nullptr};
    LPALDELETEBUFFERS alDeleteBuffers{nullptr};
    LPALISBUFFER alIsBuffer{nullptr};
    LPALBUFFERF alBufferf{nullptr};
    LPALBUFFER3F alBuffer3f{nullptr};
    LPALBUFFERFV alBufferfv{nullptr};
    LPALBUFFERI alBufferi{nullptr};
    LPALBUFFER3I alBuffer3i{nullptr};
    LPALBUFFERIV alBufferiv{nullptr};
    LPALGETBUFFERF alGetBufferf{nullptr};
    LPALGETBUFFER3F alGetBuffer3f{nullptr};
    LPALGETBUFFERFV alGetBufferfv{nullptr};
    LPALGETBUFFERI alGetBufferi{nullptr};
    LPALGETBUFFER3I alGetBuffer3i{nullptr};
    LPALGETBUFFERIV alGetBufferiv{nullptr};
    LPALBUFFERDATA alBufferData{nullptr};
    LPALDOPPLERFACTOR alDopplerFactor{nullptr};
    LPALDOPPLERVELOCITY alDopplerVelocity{nullptr};
    LPALSPEEDOFSOUND alSpeedOfSound{nullptr};
    LPALDISTANCEMODEL alDistanceModel{nullptr};

    /* Functions to load after first context creation. */
    LPALGENFILTERS alGenFilters{nullptr};
    LPALDELETEFILTERS alDeleteFilters{nullptr};
    LPALISFILTER alIsFilter{nullptr};
    LPALFILTERF alFilterf{nullptr};
    LPALFILTERFV alFilterfv{nullptr};
    LPALFILTERI alFilteri{nullptr};
    LPALFILTERIV alFilteriv{nullptr};
    LPALGETFILTERF alGetFilterf{nullptr};
    LPALGETFILTERFV alGetFilterfv{nullptr};
    LPALGETFILTERI alGetFilteri{nullptr};
    LPALGETFILTERIV alGetFilteriv{nullptr};
    LPALGENEFFECTS alGenEffects{nullptr};
    LPALDELETEEFFECTS alDeleteEffects{nullptr};
    LPALISEFFECT alIsEffect{nullptr};
    LPALEFFECTF alEffectf{nullptr};
    LPALEFFECTFV alEffectfv{nullptr};
    LPALEFFECTI alEffecti{nullptr};
    LPALEFFECTIV alEffectiv{nullptr};
    LPALGETEFFECTF alGetEffectf{nullptr};
    LPALGETEFFECTFV alGetEffectfv{nullptr};
    LPALGETEFFECTI alGetEffecti{nullptr};
    LPALGETEFFECTIV alGetEffectiv{nullptr};
    LPALGENAUXILIARYEFFECTSLOTS alGenAuxiliaryEffectSlots{nullptr};
    LPALDELETEAUXILIARYEFFECTSLOTS alDeleteAuxiliaryEffectSlots{nullptr};
    LPALISAUXILIARYEFFECTSLOT alIsAuxiliaryEffectSlot{nullptr};
    LPALAUXILIARYEFFECTSLOTF alAuxiliaryEffectSlotf{nullptr};
    LPALAUXILIARYEFFECTSLOTFV alAuxiliaryEffectSlotfv{nullptr};
    LPALAUXILIARYEFFECTSLOTI alAuxiliaryEffectSloti{nullptr};
    LPALAUXILIARYEFFECTSLOTIV alAuxiliaryEffectSlotiv{nullptr};
    LPALGETAUXILIARYEFFECTSLOTF alGetAuxiliaryEffectSlotf{nullptr};
    LPALGETAUXILIARYEFFECTSLOTFV alGetAuxiliaryEffectSlotfv{nullptr};
    LPALGETAUXILIARYEFFECTSLOTI alGetAuxiliaryEffectSloti{nullptr};
    LPALGETAUXILIARYEFFECTSLOTIV alGetAuxiliaryEffectSlotiv{nullptr};

    std::wstring Name;
    HMODULE Module{nullptr};
    int ALCVer{0};
    std::once_flag InitOnceCtx{};

    template<typename T>
    DriverIface(T&& name, HMODULE mod) : Name(std::forward<T>(name)), Module(mod) { }
    ~DriverIface() { if(Module) FreeLibrary(Module); }

    DriverIface(const DriverIface&) = delete;
    DriverIface(DriverIface&&) = delete;
    DriverIface& operator=(const DriverIface&) = delete;
    DriverIface& operator=(DriverIface&&) = delete;
};
using DriverIfacePtr = std::unique_ptr<DriverIface>;

inline std::vector<DriverIfacePtr> DriverList;

inline thread_local DriverIface *ThreadCtxDriver{};
inline std::atomic<DriverIface*> CurrentCtxDriver{};

inline DriverIface *GetThreadDriver() noexcept { return ThreadCtxDriver; }
inline void SetThreadDriver(DriverIface *driver) noexcept { ThreadCtxDriver = driver; }


enum class eLogLevel {
    None  = 0,
    Error = 1,
    Warn  = 2,
    Trace = 3,
};
extern eLogLevel LogLevel;
extern gsl::owner<std::FILE*> LogFile;

#define TRACE(...) do {                                   \
    if(LogLevel >= eLogLevel::Trace)                      \
    {                                                     \
        std::FILE *file{LogFile ? LogFile : stderr};      \
        fprintf(file, "AL Router (II): " __VA_ARGS__);    \
        fflush(file);                                     \
    }                                                     \
} while(0)
#define WARN(...) do {                                    \
    if(LogLevel >= eLogLevel::Warn)                       \
    {                                                     \
        std::FILE *file{LogFile ? LogFile : stderr};      \
        fprintf(file, "AL Router (WW): " __VA_ARGS__);    \
        fflush(file);                                     \
    }                                                     \
} while(0)
#define ERR(...) do {                                     \
    if(LogLevel >= eLogLevel::Error)                      \
    {                                                     \
        std::FILE *file{LogFile ? LogFile : stderr};      \
        fprintf(file, "AL Router (EE): " __VA_ARGS__);    \
        fflush(file);                                     \
    }                                                     \
} while(0)

#endif /* ROUTER_ROUTER_H */
