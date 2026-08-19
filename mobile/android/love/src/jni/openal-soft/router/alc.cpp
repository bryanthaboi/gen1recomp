
#include "config.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <mutex>
#include <optional>
#include <string_view>
#include <tuple>
#include <unordered_map>

#include "AL/alc.h"

#include "almalloc.h"
#include "router.h"


namespace {

using namespace std::string_view_literals;

struct FuncExportEntry {
    const char *funcName;
    void *address;
};
#define DECL(x) FuncExportEntry{ #x, reinterpret_cast<void*>(x) }
const std::array alcFunctions{
    DECL(alcCreateContext),
    DECL(alcMakeContextCurrent),
    DECL(alcProcessContext),
    DECL(alcSuspendContext),
    DECL(alcDestroyContext),
    DECL(alcGetCurrentContext),
    DECL(alcGetContextsDevice),
    DECL(alcOpenDevice),
    DECL(alcCloseDevice),
    DECL(alcGetError),
    DECL(alcIsExtensionPresent),
    DECL(alcGetProcAddress),
    DECL(alcGetEnumValue),
    DECL(alcGetString),
    DECL(alcGetIntegerv),
    DECL(alcCaptureOpenDevice),
    DECL(alcCaptureCloseDevice),
    DECL(alcCaptureStart),
    DECL(alcCaptureStop),
    DECL(alcCaptureSamples),

    DECL(alcSetThreadContext),
    DECL(alcGetThreadContext),

    DECL(alEnable),
    DECL(alDisable),
    DECL(alIsEnabled),
    DECL(alGetString),
    DECL(alGetBooleanv),
    DECL(alGetIntegerv),
    DECL(alGetFloatv),
    DECL(alGetDoublev),
    DECL(alGetBoolean),
    DECL(alGetInteger),
    DECL(alGetFloat),
    DECL(alGetDouble),
    DECL(alGetError),
    DECL(alIsExtensionPresent),
    DECL(alGetProcAddress),
    DECL(alGetEnumValue),
    DECL(alListenerf),
    DECL(alListener3f),
    DECL(alListenerfv),
    DECL(alListeneri),
    DECL(alListener3i),
    DECL(alListeneriv),
    DECL(alGetListenerf),
    DECL(alGetListener3f),
    DECL(alGetListenerfv),
    DECL(alGetListeneri),
    DECL(alGetListener3i),
    DECL(alGetListeneriv),
    DECL(alGenSources),
    DECL(alDeleteSources),
    DECL(alIsSource),
    DECL(alSourcef),
    DECL(alSource3f),
    DECL(alSourcefv),
    DECL(alSourcei),
    DECL(alSource3i),
    DECL(alSourceiv),
    DECL(alGetSourcef),
    DECL(alGetSource3f),
    DECL(alGetSourcefv),
    DECL(alGetSourcei),
    DECL(alGetSource3i),
    DECL(alGetSourceiv),
    DECL(alSourcePlayv),
    DECL(alSourceStopv),
    DECL(alSourceRewindv),
    DECL(alSourcePausev),
    DECL(alSourcePlay),
    DECL(alSourceStop),
    DECL(alSourceRewind),
    DECL(alSourcePause),
    DECL(alSourceQueueBuffers),
    DECL(alSourceUnqueueBuffers),
    DECL(alGenBuffers),
    DECL(alDeleteBuffers),
    DECL(alIsBuffer),
    DECL(alBufferData),
    DECL(alBufferf),
    DECL(alBuffer3f),
    DECL(alBufferfv),
    DECL(alBufferi),
    DECL(alBuffer3i),
    DECL(alBufferiv),
    DECL(alGetBufferf),
    DECL(alGetBuffer3f),
    DECL(alGetBufferfv),
    DECL(alGetBufferi),
    DECL(alGetBuffer3i),
    DECL(alGetBufferiv),
    DECL(alDopplerFactor),
    DECL(alDopplerVelocity),
    DECL(alSpeedOfSound),
    DECL(alDistanceModel),

    /* EFX 1.0 */
    DECL(alGenFilters),
    DECL(alDeleteFilters),
    DECL(alIsFilter),
    DECL(alFilterf),
    DECL(alFilterfv),
    DECL(alFilteri),
    DECL(alFilteriv),
    DECL(alGetFilterf),
    DECL(alGetFilterfv),
    DECL(alGetFilteri),
    DECL(alGetFilteriv),
    DECL(alGenEffects),
    DECL(alDeleteEffects),
    DECL(alIsEffect),
    DECL(alEffectf),
    DECL(alEffectfv),
    DECL(alEffecti),
    DECL(alEffectiv),
    DECL(alGetEffectf),
    DECL(alGetEffectfv),
    DECL(alGetEffecti),
    DECL(alGetEffectiv),
    DECL(alGenAuxiliaryEffectSlots),
    DECL(alDeleteAuxiliaryEffectSlots),
    DECL(alIsAuxiliaryEffectSlot),
    DECL(alAuxiliaryEffectSlotf),
    DECL(alAuxiliaryEffectSlotfv),
    DECL(alAuxiliaryEffectSloti),
    DECL(alAuxiliaryEffectSlotiv),
    DECL(alGetAuxiliaryEffectSlotf),
    DECL(alGetAuxiliaryEffectSlotfv),
    DECL(alGetAuxiliaryEffectSloti),
    DECL(alGetAuxiliaryEffectSlotiv),
};
#undef DECL

struct EnumExportEntry {
    const ALCchar *enumName;
    ALCenum value;
};
#define DECL(x) EnumExportEntry{ #x, (x) }
const std::array alcEnumerations{
    DECL(ALC_INVALID),
    DECL(ALC_FALSE),
    DECL(ALC_TRUE),

    DECL(ALC_MAJOR_VERSION),
    DECL(ALC_MINOR_VERSION),
    DECL(ALC_ATTRIBUTES_SIZE),
    DECL(ALC_ALL_ATTRIBUTES),
    DECL(ALC_DEFAULT_DEVICE_SPECIFIER),
    DECL(ALC_DEVICE_SPECIFIER),
    DECL(ALC_ALL_DEVICES_SPECIFIER),
    DECL(ALC_DEFAULT_ALL_DEVICES_SPECIFIER),
    DECL(ALC_EXTENSIONS),
    DECL(ALC_FREQUENCY),
    DECL(ALC_REFRESH),
    DECL(ALC_SYNC),
    DECL(ALC_MONO_SOURCES),
    DECL(ALC_STEREO_SOURCES),
    DECL(ALC_CAPTURE_DEVICE_SPECIFIER),
    DECL(ALC_CAPTURE_DEFAULT_DEVICE_SPECIFIER),
    DECL(ALC_CAPTURE_SAMPLES),

    DECL(ALC_NO_ERROR),
    DECL(ALC_INVALID_DEVICE),
    DECL(ALC_INVALID_CONTEXT),
    DECL(ALC_INVALID_ENUM),
    DECL(ALC_INVALID_VALUE),
    DECL(ALC_OUT_OF_MEMORY),

    DECL(AL_INVALID),
    DECL(AL_NONE),
    DECL(AL_FALSE),
    DECL(AL_TRUE),

    DECL(AL_SOURCE_RELATIVE),
    DECL(AL_CONE_INNER_ANGLE),
    DECL(AL_CONE_OUTER_ANGLE),
    DECL(AL_PITCH),
    DECL(AL_POSITION),
    DECL(AL_DIRECTION),
    DECL(AL_VELOCITY),
    DECL(AL_LOOPING),
    DECL(AL_BUFFER),
    DECL(AL_GAIN),
    DECL(AL_MIN_GAIN),
    DECL(AL_MAX_GAIN),
    DECL(AL_ORIENTATION),
    DECL(AL_REFERENCE_DISTANCE),
    DECL(AL_ROLLOFF_FACTOR),
    DECL(AL_CONE_OUTER_GAIN),
    DECL(AL_MAX_DISTANCE),
    DECL(AL_SEC_OFFSET),
    DECL(AL_SAMPLE_OFFSET),
    DECL(AL_BYTE_OFFSET),
    DECL(AL_SOURCE_TYPE),
    DECL(AL_STATIC),
    DECL(AL_STREAMING),
    DECL(AL_UNDETERMINED),

    DECL(AL_SOURCE_STATE),
    DECL(AL_INITIAL),
    DECL(AL_PLAYING),
    DECL(AL_PAUSED),
    DECL(AL_STOPPED),

    DECL(AL_BUFFERS_QUEUED),
    DECL(AL_BUFFERS_PROCESSED),

    DECL(AL_FORMAT_MONO8),
    DECL(AL_FORMAT_MONO16),
    DECL(AL_FORMAT_STEREO8),
    DECL(AL_FORMAT_STEREO16),

    DECL(AL_FREQUENCY),
    DECL(AL_BITS),
    DECL(AL_CHANNELS),
    DECL(AL_SIZE),

    DECL(AL_UNUSED),
    DECL(AL_PENDING),
    DECL(AL_PROCESSED),

    DECL(AL_NO_ERROR),
    DECL(AL_INVALID_NAME),
    DECL(AL_INVALID_ENUM),
    DECL(AL_INVALID_VALUE),
    DECL(AL_INVALID_OPERATION),
    DECL(AL_OUT_OF_MEMORY),

    DECL(AL_VENDOR),
    DECL(AL_VERSION),
    DECL(AL_RENDERER),
    DECL(AL_EXTENSIONS),

    DECL(AL_DOPPLER_FACTOR),
    DECL(AL_DOPPLER_VELOCITY),
    DECL(AL_DISTANCE_MODEL),
    DECL(AL_SPEED_OF_SOUND),

    DECL(AL_INVERSE_DISTANCE),
    DECL(AL_INVERSE_DISTANCE_CLAMPED),
    DECL(AL_LINEAR_DISTANCE),
    DECL(AL_LINEAR_DISTANCE_CLAMPED),
    DECL(AL_EXPONENT_DISTANCE),
    DECL(AL_EXPONENT_DISTANCE_CLAMPED),
};
#undef DECL

[[nodiscard]] constexpr auto GetNoErrorString() noexcept { return "No Error"; }
[[nodiscard]] constexpr auto GetInvalidDeviceString() noexcept { return "Invalid Device"; }
[[nodiscard]] constexpr auto GetInvalidContextString() noexcept { return "Invalid Context"; }
[[nodiscard]] constexpr auto GetInvalidEnumString() noexcept { return "Invalid Enum"; }
[[nodiscard]] constexpr auto GetInvalidValueString() noexcept { return "Invalid Value"; }
[[nodiscard]] constexpr auto GetOutOfMemoryString() noexcept { return "Out of Memory"; }

[[nodiscard]] constexpr auto GetExtensionList() noexcept -> std::string_view
{
    return "ALC_ENUMERATE_ALL_EXT ALC_ENUMERATION_EXT ALC_EXT_CAPTURE "
        "ALC_EXT_thread_local_context"sv;
}

constexpr ALCint alcMajorVersion = 1;
constexpr ALCint alcMinorVersion = 1;


std::recursive_mutex EnumerationLock;
std::mutex ContextSwitchLock;

std::atomic<ALCenum> LastError{ALC_NO_ERROR};
std::unordered_map<ALCdevice*,ALCuint> DeviceIfaceMap;
std::unordered_map<ALCcontext*,ALCuint> ContextIfaceMap;

template<typename T, typename U, typename V>
auto maybe_get(std::unordered_map<T,U> &list, V&& key) -> std::optional<U>
{
    auto iter = list.find(std::forward<V>(key));
    if(iter != list.end()) return iter->second;
    return std::nullopt;
}


struct EnumeratedList {
    std::vector<ALCchar> Names;
    std::vector<ALCuint> Indicies;

    void clear()
    {
        Names.clear();
        Indicies.clear();
    }

    void AppendDeviceList(const ALCchar *names, ALCuint idx);
    [[nodiscard]]
    auto GetDriverIndexForName(const std::string_view name) const -> std::optional<ALCuint>;
};
EnumeratedList DevicesList;
EnumeratedList AllDevicesList;
EnumeratedList CaptureDevicesList;

void EnumeratedList::AppendDeviceList(const ALCchar* names, ALCuint idx)
{
    const ALCchar *name_end = names;
    if(!name_end) return;

    size_t count{0};
    while(*name_end)
    {
        TRACE("Enumerated \"%s\", driver %u\n", name_end, idx);
        ++count;
        name_end += strlen(name_end)+1; /* NOLINT(cppcoreguidelines-pro-bounds-pointer-arithmetic) */
    }
    if(names == name_end)
        return;

    Names.reserve(Names.size() + static_cast<size_t>(name_end - names) + 1);
    Names.insert(Names.cend(), names, name_end);

    Indicies.reserve(Indicies.size() + count);
    Indicies.insert(Indicies.cend(), count, idx);
}

auto EnumeratedList::GetDriverIndexForName(const std::string_view name) const -> std::optional<ALCuint>
{
    auto devnames = Names.cbegin();
    auto index = Indicies.cbegin();

    while(devnames != Names.cend() && *devnames)
    {
        const auto devname = std::string_view{al::to_address(devnames)};
        if(name == devname) return *index;

        devnames += ptrdiff_t(devname.size()+1);
        ++index;
    }
    return std::nullopt;
}


void InitCtxFuncs(DriverIface &iface)
{
    ALCdevice *device{iface.alcGetContextsDevice(iface.alcGetCurrentContext())};

#define LOAD_PROC(x) do {                                                     \
    iface.x = reinterpret_cast<decltype(iface.x)>(iface.alGetProcAddress(#x));\
    if(!iface.x)                                                              \
        ERR("Failed to find entry point for %s in %ls\n", #x,                 \
            iface.Name.c_str());                                              \
} while(0)
    if(iface.alcIsExtensionPresent(device, "ALC_EXT_EFX"))
    {
        LOAD_PROC(alGenFilters);
        LOAD_PROC(alDeleteFilters);
        LOAD_PROC(alIsFilter);
        LOAD_PROC(alFilterf);
        LOAD_PROC(alFilterfv);
        LOAD_PROC(alFilteri);
        LOAD_PROC(alFilteriv);
        LOAD_PROC(alGetFilterf);
        LOAD_PROC(alGetFilterfv);
        LOAD_PROC(alGetFilteri);
        LOAD_PROC(alGetFilteriv);
        LOAD_PROC(alGenEffects);
        LOAD_PROC(alDeleteEffects);
        LOAD_PROC(alIsEffect);
        LOAD_PROC(alEffectf);
        LOAD_PROC(alEffectfv);
        LOAD_PROC(alEffecti);
        LOAD_PROC(alEffectiv);
        LOAD_PROC(alGetEffectf);
        LOAD_PROC(alGetEffectfv);
        LOAD_PROC(alGetEffecti);
        LOAD_PROC(alGetEffectiv);
        LOAD_PROC(alGenAuxiliaryEffectSlots);
        LOAD_PROC(alDeleteAuxiliaryEffectSlots);
        LOAD_PROC(alIsAuxiliaryEffectSlot);
        LOAD_PROC(alAuxiliaryEffectSlotf);
        LOAD_PROC(alAuxiliaryEffectSlotfv);
        LOAD_PROC(alAuxiliaryEffectSloti);
        LOAD_PROC(alAuxiliaryEffectSlotiv);
        LOAD_PROC(alGetAuxiliaryEffectSlotf);
        LOAD_PROC(alGetAuxiliaryEffectSlotfv);
        LOAD_PROC(alGetAuxiliaryEffectSloti);
        LOAD_PROC(alGetAuxiliaryEffectSlotiv);
    }
#undef LOAD_PROC
}

} /* namespace */


ALC_API ALCdevice* ALC_APIENTRY alcOpenDevice(const ALCchar *devicename) noexcept
{
    ALCdevice *device{nullptr};
    std::optional<ALCuint> idx;

    /* Prior to the enumeration extension, apps would hardcode these names as a
     * quality hint for the wrapper driver. Ignore them since there's no sane
     * way to map them.
     */
    if(devicename && *devicename != '\0' && devicename != "DirectSound3D"sv
        && devicename != "DirectSound"sv && devicename != "MMSYSTEM"sv)
    {
        {
            std::lock_guard<std::recursive_mutex> enumlock{EnumerationLock};
            if(DevicesList.Names.empty())
                std::ignore = alcGetString(nullptr, ALC_DEVICE_SPECIFIER);
            idx = DevicesList.GetDriverIndexForName(devicename);
            if(!idx)
            {
                if(AllDevicesList.Names.empty())
                    std::ignore = alcGetString(nullptr, ALC_ALL_DEVICES_SPECIFIER);
                idx = AllDevicesList.GetDriverIndexForName(devicename);
            }
        }

        if(!idx)
        {
            LastError.store(ALC_INVALID_VALUE);
            TRACE("Failed to find driver for name \"%s\"\n", devicename);
            return nullptr;
        }
        TRACE("Found driver %u for name \"%s\"\n", *idx, devicename);
        device = DriverList[*idx]->alcOpenDevice(devicename);
    }
    else
    {
        ALCuint drvidx{0};
        for(const auto &drv : DriverList)
        {
            if(drv->ALCVer >= MAKE_ALC_VER(1, 1)
                || drv->alcIsExtensionPresent(nullptr, "ALC_ENUMERATION_EXT"))
            {
                TRACE("Using default device from driver %u\n", drvidx);
                device = drv->alcOpenDevice(nullptr);
                idx = drvidx;
                break;
            }
            ++drvidx;
        }
    }

    if(device)
    {
        try {
            DeviceIfaceMap.emplace(device, idx.value());
        }
        catch(...) {
            DriverList[idx.value()]->alcCloseDevice(device);
            device = nullptr;
        }
    }

    return device;
}

ALC_API ALCboolean ALC_APIENTRY alcCloseDevice(ALCdevice *device) noexcept
{
    if(const auto idx = maybe_get(DeviceIfaceMap, device))
    {
        if(!DriverList[*idx]->alcCloseDevice(device))
            return ALC_FALSE;
        DeviceIfaceMap.erase(device);
        return ALC_TRUE;
    }

    LastError.store(ALC_INVALID_DEVICE);
    return ALC_FALSE;
}


ALC_API ALCcontext* ALC_APIENTRY alcCreateContext(ALCdevice *device, const ALCint *attrlist) noexcept
{
    const auto idx = maybe_get(DeviceIfaceMap, device);
    if(!idx)
    {
        LastError.store(ALC_INVALID_DEVICE);
        return nullptr;
    }

    ALCcontext *context{DriverList[*idx]->alcCreateContext(device, attrlist)};
    if(context)
    {
        try {
            ContextIfaceMap.emplace(context, *idx);
        }
        catch(...) {
            DriverList[*idx]->alcDestroyContext(context);
            context = nullptr;
        }
    }

    return context;
}

ALC_API ALCboolean ALC_APIENTRY alcMakeContextCurrent(ALCcontext *context) noexcept
{
    std::lock_guard<std::mutex> ctxlock{ContextSwitchLock};

    std::optional<ALCuint> idx;
    if(context)
    {
        idx = maybe_get(ContextIfaceMap, context);
        if(!idx)
        {
            LastError.store(ALC_INVALID_CONTEXT);
            return ALC_FALSE;
        }
        if(!DriverList[*idx]->alcMakeContextCurrent(context))
            return ALC_FALSE;

        std::call_once(DriverList[*idx]->InitOnceCtx, [idx]{ InitCtxFuncs(*DriverList[*idx]); });
    }

    /* Unset the context from the old driver if it's different from the new
     * current one.
     */
    if(!idx)
    {
        DriverIface *oldiface{GetThreadDriver()};
        if(oldiface) oldiface->alcSetThreadContext(nullptr);
        oldiface = CurrentCtxDriver.exchange(nullptr);
        if(oldiface) oldiface->alcMakeContextCurrent(nullptr);
    }
    else
    {
        DriverIface *oldiface{GetThreadDriver()};
        if(oldiface && oldiface != DriverList[*idx].get())
            oldiface->alcSetThreadContext(nullptr);
        oldiface = CurrentCtxDriver.exchange(DriverList[*idx].get());
        if(oldiface && oldiface != DriverList[*idx].get())
            oldiface->alcMakeContextCurrent(nullptr);
    }
    SetThreadDriver(nullptr);

    return ALC_TRUE;
}

ALC_API void ALC_APIENTRY alcProcessContext(ALCcontext *context) noexcept
{
    if(const auto idx = maybe_get(ContextIfaceMap, context))
        return DriverList[*idx]->alcProcessContext(context);

    LastError.store(ALC_INVALID_CONTEXT);
}

ALC_API void ALC_APIENTRY alcSuspendContext(ALCcontext *context) noexcept
{
    if(const auto idx = maybe_get(ContextIfaceMap, context))
        return DriverList[*idx]->alcSuspendContext(context);

    LastError.store(ALC_INVALID_CONTEXT);
}

ALC_API void ALC_APIENTRY alcDestroyContext(ALCcontext *context) noexcept
{
    if(const auto idx = maybe_get(ContextIfaceMap, context))
    {
        DriverList[*idx]->alcDestroyContext(context);
        ContextIfaceMap.erase(context);
        return;
    }
    LastError.store(ALC_INVALID_CONTEXT);
}

ALC_API ALCcontext* ALC_APIENTRY alcGetCurrentContext() noexcept
{
    DriverIface *iface{GetThreadDriver()};
    if(!iface) iface = CurrentCtxDriver.load();
    return iface ? iface->alcGetCurrentContext() : nullptr;
}

ALC_API ALCdevice* ALC_APIENTRY alcGetContextsDevice(ALCcontext *context) noexcept
{
    if(const auto idx = maybe_get(ContextIfaceMap, context))
        return DriverList[*idx]->alcGetContextsDevice(context);

    LastError.store(ALC_INVALID_CONTEXT);
    return nullptr;
}


ALC_API ALCenum ALC_APIENTRY alcGetError(ALCdevice *device) noexcept
{
    if(device)
    {
        if(const auto idx = maybe_get(DeviceIfaceMap, device))
            return DriverList[*idx]->alcGetError(device);
        return ALC_INVALID_DEVICE;
    }
    return LastError.exchange(ALC_NO_ERROR);
}

ALC_API ALCboolean ALC_APIENTRY alcIsExtensionPresent(ALCdevice *device, const ALCchar *extname) noexcept
{
    if(device)
    {
        if(const auto idx = maybe_get(DeviceIfaceMap, device))
            return DriverList[*idx]->alcIsExtensionPresent(device, extname);

        LastError.store(ALC_INVALID_DEVICE);
        return ALC_FALSE;
    }

    const auto tofind = std::string_view{extname};
    const auto extlist = GetExtensionList();
    auto matchpos = extlist.find(tofind);
    while(matchpos != std::string_view::npos)
    {
        const auto endpos = matchpos + tofind.size();
        if((matchpos == 0 || std::isspace(extlist[matchpos-1]))
            && (endpos == extlist.size() || std::isspace(extlist[endpos])))
            return ALC_TRUE;
        matchpos = extlist.find(tofind, matchpos+1);
    }
    return ALC_FALSE;
}

ALC_API void* ALC_APIENTRY alcGetProcAddress(ALCdevice *device, const ALCchar *funcname) noexcept
{
    if(device)
    {
        if(const auto idx = maybe_get(DeviceIfaceMap, device))
            return DriverList[*idx]->alcGetProcAddress(device, funcname);

        LastError.store(ALC_INVALID_DEVICE);
        return nullptr;
    }

    auto iter = std::find_if(alcFunctions.cbegin(), alcFunctions.cend(),
        [funcname](const FuncExportEntry &entry) -> bool
        { return strcmp(funcname, entry.funcName) == 0; }
    );
    return (iter != alcFunctions.cend()) ? iter->address : nullptr;
}

ALC_API ALCenum ALC_APIENTRY alcGetEnumValue(ALCdevice *device, const ALCchar *enumname) noexcept
{
    if(device)
    {
        if(const auto idx = maybe_get(DeviceIfaceMap, device))
            return DriverList[*idx]->alcGetEnumValue(device, enumname);

        LastError.store(ALC_INVALID_DEVICE);
        return 0;
    }

    auto iter = std::find_if(alcEnumerations.cbegin(), alcEnumerations.cend(),
        [enumname](const EnumExportEntry &entry) -> bool
        { return strcmp(enumname, entry.enumName) == 0; }
    );
    return (iter != alcEnumerations.cend()) ? iter->value : 0;
}

ALC_API const ALCchar* ALC_APIENTRY alcGetString(ALCdevice *device, ALCenum param) noexcept
{
    if(device)
    {
        if(const auto idx = maybe_get(DeviceIfaceMap, device))
            return DriverList[*idx]->alcGetString(device, param);

        LastError.store(ALC_INVALID_DEVICE);
        return nullptr;
    }

    switch(param)
    {
    case ALC_NO_ERROR: return GetNoErrorString();
    case ALC_INVALID_ENUM: return GetInvalidEnumString();
    case ALC_INVALID_VALUE: return GetInvalidValueString();
    case ALC_INVALID_DEVICE: return GetInvalidDeviceString();
    case ALC_INVALID_CONTEXT: return GetInvalidContextString();
    case ALC_OUT_OF_MEMORY: return GetOutOfMemoryString();
    case ALC_EXTENSIONS: return GetExtensionList().data();

    case ALC_DEVICE_SPECIFIER:
    {
        std::lock_guard<std::recursive_mutex> enumlock{EnumerationLock};
        DevicesList.clear();
        ALCuint idx{0};
        for(const auto &drv : DriverList)
        {
            /* Only enumerate names from drivers that support it. */
            if(drv->ALCVer >= MAKE_ALC_VER(1, 1)
                || drv->alcIsExtensionPresent(nullptr, "ALC_ENUMERATION_EXT"))
                DevicesList.AppendDeviceList(drv->alcGetString(nullptr,ALC_DEVICE_SPECIFIER), idx);
            ++idx;
        }
        /* Ensure the list is double-null termianted. */
        if(DevicesList.Names.empty())
            DevicesList.Names.emplace_back('\0');
        DevicesList.Names.emplace_back('\0');
        return DevicesList.Names.data();
    }

    case ALC_ALL_DEVICES_SPECIFIER:
    {
        std::lock_guard<std::recursive_mutex> enumlock{EnumerationLock};
        AllDevicesList.clear();
        ALCuint idx{0};
        for(const auto &drv : DriverList)
        {
            /* If the driver doesn't support ALC_ENUMERATE_ALL_EXT, substitute
             * standard enumeration.
             */
            if(drv->alcIsExtensionPresent(nullptr, "ALC_ENUMERATE_ALL_EXT"))
                AllDevicesList.AppendDeviceList(
                    drv->alcGetString(nullptr, ALC_ALL_DEVICES_SPECIFIER), idx);
            else if(drv->ALCVer >= MAKE_ALC_VER(1, 1)
                || drv->alcIsExtensionPresent(nullptr, "ALC_ENUMERATION_EXT"))
                AllDevicesList.AppendDeviceList(
                    drv->alcGetString(nullptr, ALC_DEVICE_SPECIFIER), idx);
            ++idx;
        }
        /* Ensure the list is double-null termianted. */
        if(AllDevicesList.Names.empty())
            AllDevicesList.Names.emplace_back('\0');
        AllDevicesList.Names.emplace_back('\0');
        return AllDevicesList.Names.data();
    }

    case ALC_CAPTURE_DEVICE_SPECIFIER:
    {
        std::lock_guard<std::recursive_mutex> enumlock{EnumerationLock};
        CaptureDevicesList.clear();
        ALCuint idx{0};
        for(const auto &drv : DriverList)
        {
            if(drv->ALCVer >= MAKE_ALC_VER(1, 1)
                || drv->alcIsExtensionPresent(nullptr, "ALC_EXT_CAPTURE"))
                CaptureDevicesList.AppendDeviceList(
                    drv->alcGetString(nullptr, ALC_CAPTURE_DEVICE_SPECIFIER), idx);
            ++idx;
        }
        /* Ensure the list is double-null termianted. */
        if(CaptureDevicesList.Names.empty())
            CaptureDevicesList.Names.emplace_back('\0');
        CaptureDevicesList.Names.emplace_back('\0');
        return CaptureDevicesList.Names.data();
    }

    case ALC_DEFAULT_DEVICE_SPECIFIER:
    {
        for(const auto &drv : DriverList)
        {
            if(drv->ALCVer >= MAKE_ALC_VER(1, 1)
                || drv->alcIsExtensionPresent(nullptr, "ALC_ENUMERATION_EXT"))
                return drv->alcGetString(nullptr, ALC_DEFAULT_DEVICE_SPECIFIER);
        }
        return "";
    }

    case ALC_DEFAULT_ALL_DEVICES_SPECIFIER:
    {
        for(const auto &drv : DriverList)
        {
            if(drv->alcIsExtensionPresent(nullptr, "ALC_ENUMERATE_ALL_EXT") != ALC_FALSE)
                return drv->alcGetString(nullptr, ALC_DEFAULT_ALL_DEVICES_SPECIFIER);
        }
        return "";
    }

    case ALC_CAPTURE_DEFAULT_DEVICE_SPECIFIER:
    {
        for(const auto &drv : DriverList)
        {
            if(drv->ALCVer >= MAKE_ALC_VER(1, 1)
                || drv->alcIsExtensionPresent(nullptr, "ALC_EXT_CAPTURE"))
                return drv->alcGetString(nullptr, ALC_CAPTURE_DEFAULT_DEVICE_SPECIFIER);
        }
        return "";
    }

    default:
        LastError.store(ALC_INVALID_ENUM);
        break;
    }
    return nullptr;
}

ALC_API void ALC_APIENTRY alcGetIntegerv(ALCdevice *device, ALCenum param, ALCsizei size, ALCint *values) noexcept
{
    if(device)
    {
        if(const auto idx = maybe_get(DeviceIfaceMap, device))
            return DriverList[*idx]->alcGetIntegerv(device, param, size, values);

        LastError.store(ALC_INVALID_DEVICE);
        return;
    }

    if(size <= 0 || values == nullptr)
    {
        LastError.store(ALC_INVALID_VALUE);
        return;
    }

    switch(param)
    {
        case ALC_MAJOR_VERSION:
            if(size >= 1)
            {
                *values = alcMajorVersion;
                return;
            }
            LastError.store(ALC_INVALID_VALUE);
            return;
        case ALC_MINOR_VERSION:
            if(size >= 1)
            {
                *values = alcMinorVersion;
                return;
            }
            LastError.store(ALC_INVALID_VALUE);
            return;

        case ALC_ATTRIBUTES_SIZE:
        case ALC_ALL_ATTRIBUTES:
        case ALC_FREQUENCY:
        case ALC_REFRESH:
        case ALC_SYNC:
        case ALC_MONO_SOURCES:
        case ALC_STEREO_SOURCES:
        case ALC_CAPTURE_SAMPLES:
            LastError.store(ALC_INVALID_DEVICE);
            return;

        default:
            LastError.store(ALC_INVALID_ENUM);
            return;
    }
}


ALC_API ALCdevice* ALC_APIENTRY alcCaptureOpenDevice(const ALCchar *devicename, ALCuint frequency,
    ALCenum format, ALCsizei buffersize) noexcept
{
    ALCdevice *device{nullptr};
    std::optional<ALCuint> idx;

    if(devicename && *devicename != '\0')
    {
        {
            std::lock_guard<std::recursive_mutex> enumlock{EnumerationLock};
            if(CaptureDevicesList.Names.empty())
                std::ignore = alcGetString(nullptr, ALC_CAPTURE_DEVICE_SPECIFIER);
            idx = CaptureDevicesList.GetDriverIndexForName(devicename);
        }

        if(!idx)
        {
            LastError.store(ALC_INVALID_VALUE);
            TRACE("Failed to find driver for name \"%s\"\n", devicename);
            return nullptr;
        }
        TRACE("Found driver %u for name \"%s\"\n", *idx, devicename);
        device = DriverList[*idx]->alcCaptureOpenDevice(devicename, frequency, format, buffersize);
    }
    else
    {
        ALCuint drvidx{0};
        for(const auto &drv : DriverList)
        {
            if(drv->ALCVer >= MAKE_ALC_VER(1, 1)
                || drv->alcIsExtensionPresent(nullptr, "ALC_EXT_CAPTURE"))
            {
                TRACE("Using default capture device from driver %u\n", drvidx);
                device = drv->alcCaptureOpenDevice(nullptr, frequency, format, buffersize);
                idx = drvidx;
                break;
            }
            ++drvidx;
        }
    }

    if(device)
    {
        try {
            DeviceIfaceMap.emplace(device, idx.value());
        }
        catch(...) {
            DriverList[idx.value()]->alcCaptureCloseDevice(device);
            device = nullptr;
        }
    }

    return device;
}

ALC_API ALCboolean ALC_APIENTRY alcCaptureCloseDevice(ALCdevice *device) noexcept
{
    if(const auto idx = maybe_get(DeviceIfaceMap, device))
    {
        if(!DriverList[*idx]->alcCaptureCloseDevice(device))
            return ALC_FALSE;
        DeviceIfaceMap.erase(device);
        return ALC_TRUE;
    }

    LastError.store(ALC_INVALID_DEVICE);
    return ALC_FALSE;
}

ALC_API void ALC_APIENTRY alcCaptureStart(ALCdevice *device) noexcept
{
    if(const auto idx = maybe_get(DeviceIfaceMap, device))
        return DriverList[*idx]->alcCaptureStart(device);
    LastError.store(ALC_INVALID_DEVICE);
}

ALC_API void ALC_APIENTRY alcCaptureStop(ALCdevice *device) noexcept
{
    if(const auto idx = maybe_get(DeviceIfaceMap, device))
        return DriverList[*idx]->alcCaptureStop(device);
    LastError.store(ALC_INVALID_DEVICE);
}

ALC_API void ALC_APIENTRY alcCaptureSamples(ALCdevice *device, ALCvoid *buffer, ALCsizei samples) noexcept
{
    if(const auto idx = maybe_get(DeviceIfaceMap, device))
        return DriverList[*idx]->alcCaptureSamples(device, buffer, samples);
    LastError.store(ALC_INVALID_DEVICE);
}


ALC_API ALCboolean ALC_APIENTRY alcSetThreadContext(ALCcontext *context) noexcept
{
    if(!context)
    {
        DriverIface *oldiface{GetThreadDriver()};
        if(oldiface && !oldiface->alcSetThreadContext(nullptr))
            return ALC_FALSE;
        SetThreadDriver(nullptr);
        return ALC_TRUE;
    }

    ALCenum err{ALC_INVALID_CONTEXT};
    if(const auto idx = maybe_get(ContextIfaceMap, context))
    {
        if(DriverList[*idx]->alcSetThreadContext(context))
        {
            std::call_once(DriverList[*idx]->InitOnceCtx, [idx]{InitCtxFuncs(*DriverList[*idx]);});

            DriverIface *oldiface{GetThreadDriver()};
            if(oldiface != DriverList[*idx].get())
            {
                SetThreadDriver(DriverList[*idx].get());
                if(oldiface) oldiface->alcSetThreadContext(nullptr);
            }
            return ALC_TRUE;
        }
        err = DriverList[*idx]->alcGetError(nullptr);
    }
    LastError.store(err);
    return ALC_FALSE;
}

ALC_API ALCcontext* ALC_APIENTRY alcGetThreadContext() noexcept
{
    if(DriverIface *iface{GetThreadDriver()})
        return iface->alcGetThreadContext();
    return nullptr;
}
