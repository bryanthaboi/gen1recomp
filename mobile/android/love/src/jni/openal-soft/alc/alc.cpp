/**
 * OpenAL cross platform audio library
 * Copyright (C) 1999-2007 by authors.
 * This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 *  License along with this library; if not, write to the
 *  Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 * Or go to http://www.gnu.org/copyleft/lgpl.html
 */

#include "config.h"
#include "config_backends.h"
#include "config_simd.h"

#include "version.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#include <algorithm>
#include <array>
#include <atomic>
#include <bitset>
#include <cassert>
#include <cctype>
#include <chrono>
#include <cinttypes>
#include <climits>
#include <cmath>
#include <csignal>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <functional>
#include <iterator>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/alext.h"
#include "AL/efx.h"

#include "al/auxeffectslot.h"
#include "al/buffer.h"
#include "al/debug.h"
#include "al/effect.h"
#include "al/filter.h"
#include "al/source.h"
#include "alc/events.h"
#include "albit.h"
#include "alconfig.h"
#include "almalloc.h"
#include "alnumbers.h"
#include "alnumeric.h"
#include "alspan.h"
#include "alstring.h"
#include "alu.h"
#include "atomic.h"
#include "context.h"
#include "core/ambidefs.h"
#include "core/bformatdec.h"
#include "core/bs2b.h"
#include "core/context.h"
#include "core/cpu_caps.h"
#include "core/devformat.h"
#include "core/device.h"
#include "core/effects/base.h"
#include "core/effectslot.h"
#include "core/filters/nfc.h"
#include "core/helpers.h"
#include "core/mastering.h"
#include "core/fpu_ctrl.h"
#include "core/logging.h"
#include "core/uhjfilter.h"
#include "core/voice.h"
#include "core/voice_change.h"
#include "device.h"
#include "effects/base.h"
#include "export_list.h"
#include "flexarray.h"
#include "inprogext.h"
#include "intrusive_ptr.h"
#include "opthelpers.h"
#include "strutils.h"

#include "backends/base.h"
#include "backends/null.h"
#include "backends/loopback.h"
#if HAVE_PIPEWIRE
#include "backends/pipewire.h"
#endif
#if HAVE_JACK
#include "backends/jack.h"
#endif
#if HAVE_PULSEAUDIO
#include "backends/pulseaudio.h"
#endif
#if HAVE_ALSA
#include "backends/alsa.h"
#endif
#if HAVE_WASAPI
#include "backends/wasapi.h"
#endif
#if HAVE_COREAUDIO
#include "backends/coreaudio.h"
#endif
#if HAVE_OPENSL
#include "backends/opensl.h"
#endif
#if HAVE_OBOE
#include "backends/oboe.h"
#endif
#if HAVE_SOLARIS
#include "backends/solaris.h"
#endif
#if HAVE_SNDIO
#include "backends/sndio.h"
#endif
#if HAVE_OSS
#include "backends/oss.h"
#endif
#if HAVE_DSOUND
#include "backends/dsound.h"
#endif
#if HAVE_WINMM
#include "backends/winmm.h"
#endif
#if HAVE_PORTAUDIO
#include "backends/portaudio.h"
#endif
#if HAVE_SDL2
#include "backends/sdl2.h"
#endif
#if HAVE_OTHERIO
#include "backends/otherio.h"
#endif
#if HAVE_WAVE
#include "backends/wave.h"
#endif

#if ALSOFT_EAX
#include "al/eax/api.h"
#include "al/eax/globals.h"
#endif


/************************************************
 * Library initialization
 ************************************************/
#if defined(_WIN32) && !defined(AL_LIBTYPE_STATIC)
BOOL APIENTRY DllMain(HINSTANCE module, DWORD reason, LPVOID /*reserved*/)
{
    switch(reason)
    {
    case DLL_PROCESS_ATTACH:
        /* Pin the DLL so we won't get unloaded until the process terminates */
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
            reinterpret_cast<WCHAR*>(module), &module);
        break;
    }
    return TRUE;
}
#endif

namespace {

using namespace std::string_view_literals;
using std::chrono::seconds;
using std::chrono::nanoseconds;

using voidp = void*;
using float2 = std::array<float,2>;


auto gProcessRunning = true;
struct ProcessWatcher {
    ProcessWatcher() = default;
    ProcessWatcher(const ProcessWatcher&) = delete;
    ProcessWatcher& operator=(const ProcessWatcher&) = delete;
    ~ProcessWatcher() { gProcessRunning = false; }
};
ProcessWatcher gProcessWatcher;

/************************************************
 * Backends
 ************************************************/
struct BackendInfo {
    const char *name;
    BackendFactory& (*getFactory)();
};

std::array BackendList{
#if HAVE_PIPEWIRE
    BackendInfo{"pipewire", PipeWireBackendFactory::getFactory},
#endif
#if HAVE_PULSEAUDIO
    BackendInfo{"pulse", PulseBackendFactory::getFactory},
#endif
#if HAVE_WASAPI
    BackendInfo{"wasapi", WasapiBackendFactory::getFactory},
#endif
#if HAVE_COREAUDIO
    BackendInfo{"core", CoreAudioBackendFactory::getFactory},
#endif
#if HAVE_OBOE
    BackendInfo{"oboe", OboeBackendFactory::getFactory},
#endif
#if HAVE_OPENSL
    BackendInfo{"opensl", OSLBackendFactory::getFactory},
#endif
#if HAVE_ALSA
    BackendInfo{"alsa", AlsaBackendFactory::getFactory},
#endif
#if HAVE_SOLARIS
    BackendInfo{"solaris", SolarisBackendFactory::getFactory},
#endif
#if HAVE_SNDIO
    BackendInfo{"sndio", SndIOBackendFactory::getFactory},
#endif
#if HAVE_OSS
    BackendInfo{"oss", OSSBackendFactory::getFactory},
#endif
#if HAVE_DSOUND
    BackendInfo{"dsound", DSoundBackendFactory::getFactory},
#endif
#if HAVE_WINMM
    BackendInfo{"winmm", WinMMBackendFactory::getFactory},
#endif
#if HAVE_PORTAUDIO
    BackendInfo{"port", PortBackendFactory::getFactory},
#endif
#if HAVE_SDL2
    BackendInfo{"sdl2", SDL2BackendFactory::getFactory},
#endif
#if HAVE_JACK
    BackendInfo{"jack", JackBackendFactory::getFactory},
#endif
#if HAVE_OTHERIO
    BackendInfo{"otherio", OtherIOBackendFactory::getFactory},
#endif

    BackendInfo{"null", NullBackendFactory::getFactory},
#if HAVE_WAVE
    BackendInfo{"wave", WaveBackendFactory::getFactory},
#endif
};

BackendFactory *PlaybackFactory{};
BackendFactory *CaptureFactory{};


[[nodiscard]] constexpr auto GetNoErrorString() noexcept { return "No Error"; }
[[nodiscard]] constexpr auto GetInvalidDeviceString() noexcept { return "Invalid Device"; }
[[nodiscard]] constexpr auto GetInvalidContextString() noexcept { return "Invalid Context"; }
[[nodiscard]] constexpr auto GetInvalidEnumString() noexcept { return "Invalid Enum"; }
[[nodiscard]] constexpr auto GetInvalidValueString() noexcept { return "Invalid Value"; }
[[nodiscard]] constexpr auto GetOutOfMemoryString() noexcept { return "Out of Memory"; }

[[nodiscard]] constexpr auto GetDefaultName() noexcept { return "OpenAL Soft\0"; }

#ifdef _WIN32
[[nodiscard]] constexpr auto GetDevicePrefix() noexcept { return "OpenAL Soft on "sv; }
#else
[[nodiscard]] constexpr auto GetDevicePrefix() noexcept { return std::string_view{}; }
#endif

/************************************************
 * Global variables
 ************************************************/

/* Enumerated device names */
std::vector<std::string> alcAllDevicesArray;
std::vector<std::string> alcCaptureDeviceArray;
std::string alcAllDevicesList;
std::string alcCaptureDeviceList;

/* Default is always the first in the list */
std::string alcDefaultAllDevicesSpecifier;
std::string alcCaptureDefaultDeviceSpecifier;

std::atomic<ALCenum> LastNullDeviceError{ALC_NO_ERROR};

/* Flag to trap ALC device errors */
bool TrapALCError{false};

/* One-time configuration init control */
std::once_flag alc_config_once{};

/* Flag to specify if alcSuspendContext/alcProcessContext should defer/process
 * updates.
 */
bool SuspendDefers{true};

/* Initial seed for dithering. */
constexpr uint DitherRNGSeed{22222u};


/************************************************
 * ALC information
 ************************************************/
[[nodiscard]] constexpr auto GetNoDeviceExtList() noexcept -> const char*
{
    return  "ALC_ENUMERATE_ALL_EXT "
        "ALC_ENUMERATION_EXT "
        "ALC_EXT_CAPTURE "
        "ALC_EXT_direct_context "
        "ALC_EXT_EFX "
        "ALC_EXT_thread_local_context "
        "ALC_SOFT_loopback "
        "ALC_SOFT_loopback_bformat "
        "ALC_SOFT_reopen_device "
        "ALC_SOFT_system_events";
}
[[nodiscard]] constexpr auto GetExtensionList() noexcept -> const char*
{
    return "ALC_ENUMERATE_ALL_EXT "
        "ALC_ENUMERATION_EXT "
        "ALC_EXT_CAPTURE "
        "ALC_EXT_debug "
        "ALC_EXT_DEDICATED "
        "ALC_EXT_direct_context "
        "ALC_EXT_disconnect "
        "ALC_EXT_EFX "
        "ALC_EXT_thread_local_context "
        "ALC_SOFT_device_clock "
        "ALC_SOFT_HRTF "
        "ALC_SOFT_loopback "
        "ALC_SOFT_loopback_bformat "
        "ALC_SOFT_output_limiter "
        "ALC_SOFT_output_mode "
        "ALC_SOFT_pause_device "
        "ALC_SOFT_reopen_device "
        "ALC_SOFT_system_events";
}

constexpr int alcMajorVersion{1};
constexpr int alcMinorVersion{1};

constexpr int alcEFXMajorVersion{1};
constexpr int alcEFXMinorVersion{0};


using DeviceRef = al::intrusive_ptr<ALCdevice>;


/************************************************
 * Device lists
 ************************************************/
std::vector<ALCdevice*> DeviceList;
std::vector<ALCcontext*> ContextList;

std::recursive_mutex ListLock;


void alc_initconfig()
{
    if(auto loglevel = al::getenv("ALSOFT_LOGLEVEL"))
    {
        long lvl = strtol(loglevel->c_str(), nullptr, 0);
        if(lvl >= static_cast<long>(LogLevel::Trace))
            gLogLevel = LogLevel::Trace;
        else if(lvl <= static_cast<long>(LogLevel::Disable))
            gLogLevel = LogLevel::Disable;
        else
            gLogLevel = static_cast<LogLevel>(lvl);
    }

#ifdef _WIN32
    if(const auto logfile = al::getenv(L"ALSOFT_LOGFILE"))
    {
        FILE *logf{_wfopen(logfile->c_str(), L"wt")};
        if(logf) gLogFile = logf;
        else
        {
            auto u8name = wstr_to_utf8(*logfile);
            ERR("Failed to open log file '%s'\n", u8name.c_str());
        }
    }
#else
    if(const auto logfile = al::getenv("ALSOFT_LOGFILE"))
    {
        FILE *logf{fopen(logfile->c_str(), "wt")};
        if(logf) gLogFile = logf;
        else ERR("Failed to open log file '%s'\n", logfile->c_str());
    }
#endif

    TRACE("Initializing library v%s-%s %s\n", ALSOFT_VERSION, ALSOFT_GIT_COMMIT_HASH,
        ALSOFT_GIT_BRANCH);
    {
        std::string names;
        if(std::size(BackendList) < 1)
            names = "(none)";
        else
        {
            const al::span<const BackendInfo> infos{BackendList};
            names = infos[0].name;
            for(const auto &backend : infos.subspan<1>())
            {
                names += ", ";
                names += backend.name;
            }
        }
        TRACE("Supported backends: %s\n", names.c_str());
    }
    ReadALConfig();

    if(auto suspendmode = al::getenv("__ALSOFT_SUSPEND_CONTEXT"))
    {
        if(al::case_compare(*suspendmode, "ignore"sv) == 0)
        {
            SuspendDefers = false;
            TRACE("Selected context suspend behavior, \"ignore\"\n");
        }
        else
            ERR("Unhandled context suspend behavior setting: \"%s\"\n", suspendmode->c_str());
    }

    int capfilter{0};
#if HAVE_SSE4_1
    capfilter |= CPU_CAP_SSE | CPU_CAP_SSE2 | CPU_CAP_SSE3 | CPU_CAP_SSE4_1;
#elif HAVE_SSE3
    capfilter |= CPU_CAP_SSE | CPU_CAP_SSE2 | CPU_CAP_SSE3;
#elif HAVE_SSE2
    capfilter |= CPU_CAP_SSE | CPU_CAP_SSE2;
#elif HAVE_SSE
    capfilter |= CPU_CAP_SSE;
#endif
#if HAVE_NEON
    capfilter |= CPU_CAP_NEON;
#endif
    if(auto cpuopt = ConfigValueStr({}, {}, "disable-cpu-exts"sv))
    {
        std::string_view cpulist{*cpuopt};
        if(al::case_compare(cpulist, "all"sv) == 0)
            capfilter = 0;
        else while(!cpulist.empty())
        {
            auto nextpos = std::min(cpulist.find(','), cpulist.size());
            auto entry = cpulist.substr(0, nextpos);

            while(nextpos < cpulist.size() && cpulist[nextpos] == ',')
                ++nextpos;
            cpulist.remove_prefix(nextpos);

            while(!entry.empty() && std::isspace(entry.front()))
                entry.remove_prefix(1);
            while(!entry.empty() && std::isspace(entry.back()))
                entry.remove_suffix(1);
            if(entry.empty())
                continue;

            if(al::case_compare(entry, "sse"sv) == 0)
                capfilter &= ~CPU_CAP_SSE;
            else if(al::case_compare(entry, "sse2"sv) == 0)
                capfilter &= ~CPU_CAP_SSE2;
            else if(al::case_compare(entry, "sse3"sv) == 0)
                capfilter &= ~CPU_CAP_SSE3;
            else if(al::case_compare(entry, "sse4.1"sv) == 0)
                capfilter &= ~CPU_CAP_SSE4_1;
            else if(al::case_compare(entry, "neon"sv) == 0)
                capfilter &= ~CPU_CAP_NEON;
            else
                WARN("Invalid CPU extension \"%.*s\"\n", al::sizei(entry), entry.data());
        }
    }
    if(auto cpuopt = GetCPUInfo())
    {
        if(!cpuopt->mVendor.empty() || !cpuopt->mName.empty())
        {
            TRACE("Vendor ID: \"%s\"\n", cpuopt->mVendor.c_str());
            TRACE("Name: \"%s\"\n", cpuopt->mName.c_str());
        }
        const int caps{cpuopt->mCaps};
        TRACE("Extensions:%s%s%s%s%s%s\n",
            ((capfilter&CPU_CAP_SSE)    ? ((caps&CPU_CAP_SSE)    ? " +SSE"    : " -SSE")    : ""),
            ((capfilter&CPU_CAP_SSE2)   ? ((caps&CPU_CAP_SSE2)   ? " +SSE2"   : " -SSE2")   : ""),
            ((capfilter&CPU_CAP_SSE3)   ? ((caps&CPU_CAP_SSE3)   ? " +SSE3"   : " -SSE3")   : ""),
            ((capfilter&CPU_CAP_SSE4_1) ? ((caps&CPU_CAP_SSE4_1) ? " +SSE4.1" : " -SSE4.1") : ""),
            ((capfilter&CPU_CAP_NEON)   ? ((caps&CPU_CAP_NEON)   ? " +NEON"   : " -NEON")   : ""),
            ((!capfilter) ? " -none-" : ""));
        CPUCapFlags = caps & capfilter;
    }

    if(auto priopt = ConfigValueInt({}, {}, "rt-prio"sv))
        RTPrioLevel = *priopt;
    if(auto limopt = ConfigValueBool({}, {}, "rt-time-limit"sv))
        AllowRTTimeLimit = *limopt;

    {
        CompatFlagBitset compatflags{};
        auto checkflag = [](const char *envname, const std::string_view optname) -> bool
        {
            if(auto optval = al::getenv(envname))
            {
                return al::case_compare(*optval, "true"sv) == 0
                    || strtol(optval->c_str(), nullptr, 0) == 1;
            }
            return GetConfigValueBool({}, "game_compat", optname, false);
        };
        sBufferSubDataCompat = checkflag("__ALSOFT_ENABLE_SUB_DATA_EXT", "enable-sub-data-ext"sv);
        compatflags.set(CompatFlags::ReverseX, checkflag("__ALSOFT_REVERSE_X", "reverse-x"sv));
        compatflags.set(CompatFlags::ReverseY, checkflag("__ALSOFT_REVERSE_Y", "reverse-y"sv));
        compatflags.set(CompatFlags::ReverseZ, checkflag("__ALSOFT_REVERSE_Z", "reverse-z"sv));

        aluInit(compatflags, ConfigValueFloat({}, "game_compat"sv, "nfc-scale"sv).value_or(1.0f));
    }
    Voice::InitMixer(ConfigValueStr({}, {}, "resampler"sv));

    if(auto uhjfiltopt = ConfigValueStr({}, "uhj"sv, "decode-filter"sv))
    {
        if(al::case_compare(*uhjfiltopt, "fir256"sv) == 0)
            UhjDecodeQuality = UhjQualityType::FIR256;
        else if(al::case_compare(*uhjfiltopt, "fir512"sv) == 0)
            UhjDecodeQuality = UhjQualityType::FIR512;
        else if(al::case_compare(*uhjfiltopt, "iir"sv) == 0)
            UhjDecodeQuality = UhjQualityType::IIR;
        else
            WARN("Unsupported uhj/decode-filter: %s\n", uhjfiltopt->c_str());
    }
    if(auto uhjfiltopt = ConfigValueStr({}, "uhj"sv, "encode-filter"sv))
    {
        if(al::case_compare(*uhjfiltopt, "fir256"sv) == 0)
            UhjEncodeQuality = UhjQualityType::FIR256;
        else if(al::case_compare(*uhjfiltopt, "fir512"sv) == 0)
            UhjEncodeQuality = UhjQualityType::FIR512;
        else if(al::case_compare(*uhjfiltopt, "iir"sv) == 0)
            UhjEncodeQuality = UhjQualityType::IIR;
        else
            WARN("Unsupported uhj/encode-filter: %s\n", uhjfiltopt->c_str());
    }

    if(auto traperr = al::getenv("ALSOFT_TRAP_ERROR"); traperr
        && (al::case_compare(*traperr, "true"sv) == 0
            || std::strtol(traperr->c_str(), nullptr, 0) == 1))
    {
        TrapALError  = true;
        TrapALCError = true;
    }
    else
    {
        traperr = al::getenv("ALSOFT_TRAP_AL_ERROR");
        if(traperr)
            TrapALError = al::case_compare(*traperr, "true"sv) == 0
                || strtol(traperr->c_str(), nullptr, 0) == 1;
        else
            TrapALError = GetConfigValueBool({}, {}, "trap-al-error"sv, false);

        traperr = al::getenv("ALSOFT_TRAP_ALC_ERROR");
        if(traperr)
            TrapALCError = al::case_compare(*traperr, "true"sv) == 0
                || strtol(traperr->c_str(), nullptr, 0) == 1;
        else
            TrapALCError = GetConfigValueBool({}, {}, "trap-alc-error"sv, false);
    }

    if(auto boostopt = ConfigValueFloat({}, "reverb"sv, "boost"sv))
    {
        const float valf{std::isfinite(*boostopt) ? std::clamp(*boostopt, -24.0f, 24.0f) : 0.0f};
        ReverbBoost *= std::pow(10.0f, valf / 20.0f);
    }

    auto BackendListEnd = BackendList.end();
    auto devopt = al::getenv("ALSOFT_DRIVERS");
    if(!devopt) devopt = ConfigValueStr({}, {}, "drivers"sv);
    if(devopt)
    {
        auto backendlist_cur = BackendList.begin();

        bool endlist{true};
        std::string_view drvlist{*devopt};
        while(!drvlist.empty())
        {
            auto nextpos = std::min(drvlist.find(','), drvlist.size());
            auto entry = drvlist.substr(0, nextpos);

            endlist = true;
            if(nextpos < drvlist.size())
            {
                endlist = false;
                while(nextpos < drvlist.size() && drvlist[nextpos] == ',')
                    ++nextpos;
            }
            drvlist.remove_prefix(nextpos);

            while(!entry.empty() && std::isspace(entry.front()))
                entry.remove_prefix(1);
            const bool delitem{!entry.empty() && entry.front() == '-'};
            if(delitem) entry.remove_prefix(1);

            while(!entry.empty() && std::isspace(entry.back()))
                entry.remove_suffix(1);
            if(entry.empty())
                continue;

#ifdef HAVE_WASAPI
            /* HACK: For backwards compatibility, convert backend references of
             * mmdevapi to wasapi. This should eventually be removed.
             */
            if(entry == "mmdevapi"sv)
                entry = "wasapi"sv;
#endif

            auto find_backend = [entry](const BackendInfo &backend) -> bool
            { return entry == backend.name; };
            auto this_backend = std::find_if(BackendList.begin(), BackendListEnd, find_backend);

            if(this_backend == BackendListEnd)
                continue;

            if(delitem)
                BackendListEnd = std::move(this_backend+1, BackendListEnd, this_backend);
            else
                backendlist_cur = std::rotate(backendlist_cur, this_backend, this_backend+1);
        }

        if(endlist)
            BackendListEnd = backendlist_cur;
    }

    auto init_backend = [](BackendInfo &backend) -> void
    {
        if(PlaybackFactory && CaptureFactory)
            return;

        BackendFactory &factory = backend.getFactory();
        if(!factory.init())
        {
            WARN("Failed to initialize backend \"%s\"\n", backend.name);
            return;
        }

        TRACE("Initialized backend \"%s\"\n", backend.name);
        if(!PlaybackFactory && factory.querySupport(BackendType::Playback))
        {
            PlaybackFactory = &factory;
            TRACE("Added \"%s\" for playback\n", backend.name);
        }
        if(!CaptureFactory && factory.querySupport(BackendType::Capture))
        {
            CaptureFactory = &factory;
            TRACE("Added \"%s\" for capture\n", backend.name);
        }
    };
    std::for_each(BackendList.begin(), BackendListEnd, init_backend);

    LoopbackBackendFactory::getFactory().init();

    if(!PlaybackFactory)
        WARN("No playback backend available!\n");
    if(!CaptureFactory)
        WARN("No capture backend available!\n");

    if(auto exclopt = ConfigValueStr({}, {}, "excludefx"sv))
    {
        std::string_view exclude{*exclopt};
        while(!exclude.empty())
        {
            const auto nextpos = exclude.find(',');
            const auto entry = exclude.substr(0, nextpos);
            exclude.remove_prefix((nextpos < exclude.size()) ? nextpos+1 : exclude.size());

            std::for_each(gEffectList.cbegin(), gEffectList.cend(),
                [entry](const EffectList &effectitem) noexcept
                {
                    if(entry == std::data(effectitem.name))
                        DisabledEffects.set(effectitem.type);
                });
        }
    }

    InitEffect(&ALCcontext::sDefaultEffect);
    auto defrevopt = al::getenv("ALSOFT_DEFAULT_REVERB");
    if(!defrevopt) defrevopt = ConfigValueStr({}, {}, "default-reverb"sv);
    if(defrevopt) LoadReverbPreset(*defrevopt, &ALCcontext::sDefaultEffect);

#if ALSOFT_EAX
    {
        if(const auto eax_enable_opt = ConfigValueBool({}, "eax", "enable"))
        {
            eax_g_is_enabled = *eax_enable_opt;
            if(!eax_g_is_enabled)
                TRACE("%s\n", "EAX disabled by a configuration.");
        }
        else
            eax_g_is_enabled = true;

        if((DisabledEffects.test(EAXREVERB_EFFECT) || DisabledEffects.test(CHORUS_EFFECT))
            && eax_g_is_enabled)
        {
            eax_g_is_enabled = false;
            TRACE("EAX disabled because %s disabled.\n",
                (DisabledEffects.test(EAXREVERB_EFFECT) && DisabledEffects.test(CHORUS_EFFECT))
                    ? "EAXReverb and Chorus are" :
                DisabledEffects.test(EAXREVERB_EFFECT) ? "EAXReverb is" :
                DisabledEffects.test(CHORUS_EFFECT) ? "Chorus is" : "");
        }
    }
#endif // ALSOFT_EAX
}
inline void InitConfig()
{ std::call_once(alc_config_once, [](){alc_initconfig();}); }


/************************************************
 * Device enumeration
 ************************************************/
void ProbeAllDevicesList()
{
    InitConfig();

    std::lock_guard<std::recursive_mutex> listlock{ListLock};
    if(!PlaybackFactory)
    {
        decltype(alcAllDevicesArray){}.swap(alcAllDevicesArray);
        decltype(alcAllDevicesList){}.swap(alcAllDevicesList);
    }
    else
    {
        alcAllDevicesArray = PlaybackFactory->enumerate(BackendType::Playback);
        if(const auto prefix = GetDevicePrefix(); !prefix.empty())
            std::for_each(alcAllDevicesArray.begin(), alcAllDevicesArray.end(),
                [prefix](std::string &name) { name.insert(0, prefix); });

        decltype(alcAllDevicesList){}.swap(alcAllDevicesList);
        if(alcAllDevicesArray.empty())
            alcAllDevicesList += '\0';
        else for(auto &devname : alcAllDevicesArray)
            alcAllDevicesList.append(devname) += '\0';
    }
}
void ProbeCaptureDeviceList()
{
    InitConfig();

    std::lock_guard<std::recursive_mutex> listlock{ListLock};
    if(!CaptureFactory)
    {
        decltype(alcCaptureDeviceArray){}.swap(alcCaptureDeviceArray);
        decltype(alcCaptureDeviceList){}.swap(alcCaptureDeviceList);
    }
    else
    {
        alcCaptureDeviceArray = CaptureFactory->enumerate(BackendType::Capture);
        if(const auto prefix = GetDevicePrefix(); !prefix.empty())
            std::for_each(alcCaptureDeviceArray.begin(), alcCaptureDeviceArray.end(),
                [prefix](std::string &name) { name.insert(0, prefix); });

        decltype(alcCaptureDeviceList){}.swap(alcCaptureDeviceList);
        if(alcCaptureDeviceArray.empty())
            alcCaptureDeviceList += '\0';
        else for(auto &devname : alcCaptureDeviceArray)
            alcCaptureDeviceList.append(devname) += '\0';
    }
}


al::span<const ALCint> SpanFromAttributeList(const ALCint *attribs) noexcept
{
    al::span<const ALCint> attrSpan;
    if(attribs)
    {
        const ALCint *attrEnd{attribs};
        while(*attrEnd != 0)
            attrEnd += 2; /* NOLINT(cppcoreguidelines-pro-bounds-pointer-arithmetic) */
        attrSpan = {attribs, attrEnd};
    }
    return attrSpan;
}

struct DevFmtPair { DevFmtChannels chans; DevFmtType type; };
std::optional<DevFmtPair> DecomposeDevFormat(ALenum format)
{
    struct FormatType {
        ALenum format;
        DevFmtChannels channels;
        DevFmtType type;
    };
    static constexpr std::array list{
        FormatType{AL_FORMAT_MONO8,    DevFmtMono, DevFmtUByte},
        FormatType{AL_FORMAT_MONO16,   DevFmtMono, DevFmtShort},
        FormatType{AL_FORMAT_MONO_I32, DevFmtMono, DevFmtInt},
        FormatType{AL_FORMAT_MONO_FLOAT32, DevFmtMono, DevFmtFloat},

        FormatType{AL_FORMAT_STEREO8,    DevFmtStereo, DevFmtUByte},
        FormatType{AL_FORMAT_STEREO16,   DevFmtStereo, DevFmtShort},
        FormatType{AL_FORMAT_STEREO_I32, DevFmtStereo, DevFmtInt},
        FormatType{AL_FORMAT_STEREO_FLOAT32, DevFmtStereo, DevFmtFloat},

        FormatType{AL_FORMAT_QUAD8,    DevFmtQuad, DevFmtUByte},
        FormatType{AL_FORMAT_QUAD16,   DevFmtQuad, DevFmtShort},
        FormatType{AL_FORMAT_QUAD32,   DevFmtQuad, DevFmtFloat},
        FormatType{AL_FORMAT_QUAD_I32, DevFmtQuad, DevFmtInt},
        FormatType{AL_FORMAT_QUAD_FLOAT32, DevFmtQuad, DevFmtFloat},

        FormatType{AL_FORMAT_51CHN8,    DevFmtX51, DevFmtUByte},
        FormatType{AL_FORMAT_51CHN16,   DevFmtX51, DevFmtShort},
        FormatType{AL_FORMAT_51CHN32,   DevFmtX51, DevFmtFloat},
        FormatType{AL_FORMAT_51CHN_I32, DevFmtX51, DevFmtInt},
        FormatType{AL_FORMAT_51CHN_FLOAT32, DevFmtX51, DevFmtFloat},

        FormatType{AL_FORMAT_61CHN8,    DevFmtX61, DevFmtUByte},
        FormatType{AL_FORMAT_61CHN16,   DevFmtX61, DevFmtShort},
        FormatType{AL_FORMAT_61CHN32,   DevFmtX61, DevFmtFloat},
        FormatType{AL_FORMAT_61CHN_I32, DevFmtX61, DevFmtInt},
        FormatType{AL_FORMAT_61CHN_FLOAT32, DevFmtX61, DevFmtFloat},

        FormatType{AL_FORMAT_71CHN8,    DevFmtX71, DevFmtUByte},
        FormatType{AL_FORMAT_71CHN16,   DevFmtX71, DevFmtShort},
        FormatType{AL_FORMAT_71CHN32,   DevFmtX71, DevFmtFloat},
        FormatType{AL_FORMAT_71CHN_I32, DevFmtX71, DevFmtInt},
        FormatType{AL_FORMAT_71CHN_FLOAT32, DevFmtX71, DevFmtFloat},
    };

    for(const auto &item : list)
    {
        if(item.format == format)
            return DevFmtPair{item.channels, item.type};
    }

    return std::nullopt;
}

std::optional<DevFmtType> DevFmtTypeFromEnum(ALCenum type)
{
    switch(type)
    {
    case ALC_BYTE_SOFT: return DevFmtByte;
    case ALC_UNSIGNED_BYTE_SOFT: return DevFmtUByte;
    case ALC_SHORT_SOFT: return DevFmtShort;
    case ALC_UNSIGNED_SHORT_SOFT: return DevFmtUShort;
    case ALC_INT_SOFT: return DevFmtInt;
    case ALC_UNSIGNED_INT_SOFT: return DevFmtUInt;
    case ALC_FLOAT_SOFT: return DevFmtFloat;
    }
    WARN("Unsupported format type: 0x%04x\n", type);
    return std::nullopt;
}
ALCenum EnumFromDevFmt(DevFmtType type)
{
    switch(type)
    {
    case DevFmtByte: return ALC_BYTE_SOFT;
    case DevFmtUByte: return ALC_UNSIGNED_BYTE_SOFT;
    case DevFmtShort: return ALC_SHORT_SOFT;
    case DevFmtUShort: return ALC_UNSIGNED_SHORT_SOFT;
    case DevFmtInt: return ALC_INT_SOFT;
    case DevFmtUInt: return ALC_UNSIGNED_INT_SOFT;
    case DevFmtFloat: return ALC_FLOAT_SOFT;
    }
    throw std::runtime_error{"Invalid DevFmtType: "+std::to_string(int(type))};
}

std::optional<DevFmtChannels> DevFmtChannelsFromEnum(ALCenum channels)
{
    switch(channels)
    {
    case ALC_MONO_SOFT: return DevFmtMono;
    case ALC_STEREO_SOFT: return DevFmtStereo;
    case ALC_QUAD_SOFT: return DevFmtQuad;
    case ALC_5POINT1_SOFT: return DevFmtX51;
    case ALC_6POINT1_SOFT: return DevFmtX61;
    case ALC_7POINT1_SOFT: return DevFmtX71;
    case ALC_BFORMAT3D_SOFT: return DevFmtAmbi3D;
    }
    WARN("Unsupported format channels: 0x%04x\n", channels);
    return std::nullopt;
}
ALCenum EnumFromDevFmt(DevFmtChannels channels)
{
    switch(channels)
    {
    case DevFmtMono: return ALC_MONO_SOFT;
    case DevFmtStereo: return ALC_STEREO_SOFT;
    case DevFmtQuad: return ALC_QUAD_SOFT;
    case DevFmtX51: return ALC_5POINT1_SOFT;
    case DevFmtX61: return ALC_6POINT1_SOFT;
    case DevFmtX71: return ALC_7POINT1_SOFT;
    case DevFmtAmbi3D: return ALC_BFORMAT3D_SOFT;
    /* FIXME: Shouldn't happen. */
    case DevFmtX714:
    case DevFmtX7144:
    case DevFmtX3D71: break;
    }
    throw std::runtime_error{"Invalid DevFmtChannels: "+std::to_string(int(channels))};
}

std::optional<DevAmbiLayout> DevAmbiLayoutFromEnum(ALCenum layout)
{
    switch(layout)
    {
    case ALC_FUMA_SOFT: return DevAmbiLayout::FuMa;
    case ALC_ACN_SOFT: return DevAmbiLayout::ACN;
    }
    WARN("Unsupported ambisonic layout: 0x%04x\n", layout);
    return std::nullopt;
}
ALCenum EnumFromDevAmbi(DevAmbiLayout layout)
{
    switch(layout)
    {
    case DevAmbiLayout::FuMa: return ALC_FUMA_SOFT;
    case DevAmbiLayout::ACN: return ALC_ACN_SOFT;
    }
    throw std::runtime_error{"Invalid DevAmbiLayout: "+std::to_string(int(layout))};
}

std::optional<DevAmbiScaling> DevAmbiScalingFromEnum(ALCenum scaling)
{
    switch(scaling)
    {
    case ALC_FUMA_SOFT: return DevAmbiScaling::FuMa;
    case ALC_SN3D_SOFT: return DevAmbiScaling::SN3D;
    case ALC_N3D_SOFT: return DevAmbiScaling::N3D;
    }
    WARN("Unsupported ambisonic scaling: 0x%04x\n", scaling);
    return std::nullopt;
}
ALCenum EnumFromDevAmbi(DevAmbiScaling scaling)
{
    switch(scaling)
    {
    case DevAmbiScaling::FuMa: return ALC_FUMA_SOFT;
    case DevAmbiScaling::SN3D: return ALC_SN3D_SOFT;
    case DevAmbiScaling::N3D: return ALC_N3D_SOFT;
    }
    throw std::runtime_error{"Invalid DevAmbiScaling: "+std::to_string(int(scaling))};
}


/* Downmixing channel arrays, to map a device format's missing channels to
 * existing ones. Based on what PipeWire does, though simplified.
 */
constexpr float inv_sqrt2f{static_cast<float>(1.0 / al::numbers::sqrt2)};
constexpr std::array FrontStereo3dB{
    InputRemixMap::TargetMix{FrontLeft, inv_sqrt2f},
    InputRemixMap::TargetMix{FrontRight, inv_sqrt2f}
};
constexpr std::array FrontStereo6dB{
    InputRemixMap::TargetMix{FrontLeft, 0.5f},
    InputRemixMap::TargetMix{FrontRight, 0.5f}
};
constexpr std::array SideStereo3dB{
    InputRemixMap::TargetMix{SideLeft, inv_sqrt2f},
    InputRemixMap::TargetMix{SideRight, inv_sqrt2f}
};
constexpr std::array BackStereo3dB{
    InputRemixMap::TargetMix{BackLeft, inv_sqrt2f},
    InputRemixMap::TargetMix{BackRight, inv_sqrt2f}
};
constexpr std::array FrontLeft3dB{InputRemixMap::TargetMix{FrontLeft, inv_sqrt2f}};
constexpr std::array FrontRight3dB{InputRemixMap::TargetMix{FrontRight, inv_sqrt2f}};
constexpr std::array SideLeft0dB{InputRemixMap::TargetMix{SideLeft, 1.0f}};
constexpr std::array SideRight0dB{InputRemixMap::TargetMix{SideRight, 1.0f}};
constexpr std::array BackLeft0dB{InputRemixMap::TargetMix{BackLeft, 1.0f}};
constexpr std::array BackRight0dB{InputRemixMap::TargetMix{BackRight, 1.0f}};
constexpr std::array BackCenter3dB{InputRemixMap::TargetMix{BackCenter, inv_sqrt2f}};

constexpr std::array StereoDownmix{
    InputRemixMap{FrontCenter, FrontStereo3dB},
    InputRemixMap{SideLeft,    FrontLeft3dB},
    InputRemixMap{SideRight,   FrontRight3dB},
    InputRemixMap{BackLeft,    FrontLeft3dB},
    InputRemixMap{BackRight,   FrontRight3dB},
    InputRemixMap{BackCenter,  FrontStereo6dB},
};
constexpr std::array QuadDownmix{
    InputRemixMap{FrontCenter, FrontStereo3dB},
    InputRemixMap{SideLeft,    BackLeft0dB},
    InputRemixMap{SideRight,   BackRight0dB},
    InputRemixMap{BackCenter,  BackStereo3dB},
};
constexpr std::array X51Downmix{
    InputRemixMap{BackLeft,   SideLeft0dB},
    InputRemixMap{BackRight,  SideRight0dB},
    InputRemixMap{BackCenter, SideStereo3dB},
};
constexpr std::array X61Downmix{
    InputRemixMap{BackLeft,  BackCenter3dB},
    InputRemixMap{BackRight, BackCenter3dB},
};
constexpr std::array X71Downmix{
    InputRemixMap{BackCenter, BackStereo3dB},
};


std::unique_ptr<Compressor> CreateDeviceLimiter(const ALCdevice *device, const float threshold)
{
    static constexpr bool AutoKnee{true};
    static constexpr bool AutoAttack{true};
    static constexpr bool AutoRelease{true};
    static constexpr bool AutoPostGain{true};
    static constexpr bool AutoDeclip{true};
    static constexpr float LookAheadTime{0.001f};
    static constexpr float HoldTime{0.002f};
    static constexpr float PreGainDb{0.0f};
    static constexpr float PostGainDb{0.0f};
    static constexpr float Ratio{std::numeric_limits<float>::infinity()};
    static constexpr float KneeDb{0.0f};
    static constexpr float AttackTime{0.02f};
    static constexpr float ReleaseTime{0.2f};

    return Compressor::Create(device->RealOut.Buffer.size(), static_cast<float>(device->Frequency),
        AutoKnee, AutoAttack, AutoRelease, AutoPostGain, AutoDeclip, LookAheadTime, HoldTime,
        PreGainDb, PostGainDb, threshold, Ratio, KneeDb, AttackTime, ReleaseTime);
}

/**
 * Updates the device's base clock time with however many samples have been
 * done. This is used so frequency changes on the device don't cause the time
 * to jump forward or back. Must not be called while the device is running/
 * mixing.
 */
inline void UpdateClockBase(ALCdevice *device)
{
    const auto mixLock = device->getWriteMixLock();

    auto samplesDone = device->mSamplesDone.load(std::memory_order_relaxed);
    auto clockBase = device->mClockBase.load(std::memory_order_relaxed);

    clockBase += nanoseconds{seconds{samplesDone}} / device->Frequency;
    device->mClockBase.store(clockBase, std::memory_order_relaxed);
    device->mSamplesDone.store(0, std::memory_order_relaxed);
}

/**
 * Updates device parameters according to the attribute list (caller is
 * responsible for holding the list lock).
 */
ALCenum UpdateDeviceParams(ALCdevice *device, const al::span<const int> attrList)
{
    if(attrList.empty() && device->Type == DeviceType::Loopback)
    {
        WARN("Missing attributes for loopback device\n");
        return ALC_INVALID_VALUE;
    }

    uint numMono{device->NumMonoSources};
    uint numStereo{device->NumStereoSources};
    uint numSends{device->NumAuxSends};
    std::optional<StereoEncoding> stereomode;
    std::optional<bool> optlimit;
    std::optional<uint> optsrate;
    std::optional<DevFmtChannels> optchans;
    std::optional<DevFmtType> opttype;
    std::optional<DevAmbiLayout> optlayout;
    std::optional<DevAmbiScaling> optscale;
    uint period_size{DefaultUpdateSize};
    uint buffer_size{DefaultUpdateSize * DefaultNumUpdates};
    int hrtf_id{-1};
    uint aorder{0u};

    if(device->Type != DeviceType::Loopback)
    {
        /* Get default settings from the user configuration */

        if(auto freqopt = device->configValue<uint>({}, "frequency"))
        {
            optsrate = std::clamp<uint>(*freqopt, MinOutputRate, MaxOutputRate);

            const double scale{static_cast<double>(*optsrate) / double{DefaultOutputRate}};
            period_size = static_cast<uint>(std::lround(period_size * scale));
        }

        if(auto persizeopt = device->configValue<uint>({}, "period_size"))
            period_size = std::clamp(*persizeopt, 64u, 8192u);
        if(auto numperopt = device->configValue<uint>({}, "periods"))
            buffer_size = std::clamp(*numperopt, 2u, 16u) * period_size;
        else
            buffer_size = period_size * uint{DefaultNumUpdates};

        if(auto typeopt = device->configValue<std::string>({}, "sample-type"))
        {
            struct TypeMap {
                std::string_view name;
                DevFmtType type;
            };
            constexpr std::array typelist{
                TypeMap{"int8"sv,    DevFmtByte  },
                TypeMap{"uint8"sv,   DevFmtUByte },
                TypeMap{"int16"sv,   DevFmtShort },
                TypeMap{"uint16"sv,  DevFmtUShort},
                TypeMap{"int32"sv,   DevFmtInt   },
                TypeMap{"uint32"sv,  DevFmtUInt  },
                TypeMap{"float32"sv, DevFmtFloat },
            };

            const ALCchar *fmt{typeopt->c_str()};
            auto iter = std::find_if(typelist.begin(), typelist.end(),
                [svfmt=std::string_view{fmt}](const TypeMap &entry) -> bool
                { return al::case_compare(entry.name, svfmt) == 0; });
            if(iter == typelist.end())
                ERR("Unsupported sample-type: %s\n", fmt);
            else
                opttype = iter->type;
        }
        if(auto chanopt = device->configValue<std::string>({}, "channels"))
        {
            struct ChannelMap {
                std::string_view name;
                DevFmtChannels chans;
                uint8_t order;
            };
            constexpr std::array chanlist{
                ChannelMap{"mono"sv,       DevFmtMono,   0},
                ChannelMap{"stereo"sv,     DevFmtStereo, 0},
                ChannelMap{"quad"sv,       DevFmtQuad,   0},
                ChannelMap{"surround51"sv, DevFmtX51,    0},
                ChannelMap{"surround61"sv, DevFmtX61,    0},
                ChannelMap{"surround71"sv, DevFmtX71,    0},
                ChannelMap{"surround714"sv, DevFmtX714,  0},
                ChannelMap{"surround7144"sv, DevFmtX7144, 0},
                ChannelMap{"surround3d71"sv, DevFmtX3D71, 0},
                ChannelMap{"surround51rear"sv, DevFmtX51, 0},
                ChannelMap{"ambi1"sv, DevFmtAmbi3D, 1},
                ChannelMap{"ambi2"sv, DevFmtAmbi3D, 2},
                ChannelMap{"ambi3"sv, DevFmtAmbi3D, 3},
            };

            const ALCchar *fmt{chanopt->c_str()};
            auto iter = std::find_if(chanlist.begin(), chanlist.end(),
                [svfmt=std::string_view{fmt}](const ChannelMap &entry) -> bool
                { return al::case_compare(entry.name, svfmt) == 0; });
            if(iter == chanlist.end())
                ERR("Unsupported channels: %s\n", fmt);
            else
            {
                optchans = iter->chans;
                aorder = iter->order;
            }
        }
        if(auto ambiopt = device->configValue<std::string>({}, "ambi-format"sv))
        {
            if(al::case_compare(*ambiopt, "fuma"sv) == 0)
            {
                optlayout = DevAmbiLayout::FuMa;
                optscale = DevAmbiScaling::FuMa;
            }
            else if(al::case_compare(*ambiopt, "acn+fuma"sv) == 0)
            {
                optlayout = DevAmbiLayout::ACN;
                optscale = DevAmbiScaling::FuMa;
            }
            else if(al::case_compare(*ambiopt, "ambix"sv) == 0
                || al::case_compare(*ambiopt, "acn+sn3d"sv) == 0)
            {
                optlayout = DevAmbiLayout::ACN;
                optscale = DevAmbiScaling::SN3D;
            }
            else if(al::case_compare(*ambiopt, "acn+n3d"sv) == 0)
            {
                optlayout = DevAmbiLayout::ACN;
                optscale = DevAmbiScaling::N3D;
            }
            else
                ERR("Unsupported ambi-format: %s\n", ambiopt->c_str());
        }

        if(auto hrtfopt = device->configValue<std::string>({}, "hrtf"sv))
        {
            WARN("general/hrtf is deprecated, please use stereo-encoding instead\n");

            if(al::case_compare(*hrtfopt, "true"sv) == 0)
                stereomode = StereoEncoding::Hrtf;
            else if(al::case_compare(*hrtfopt, "false"sv) == 0)
            {
                if(!stereomode || *stereomode == StereoEncoding::Hrtf)
                    stereomode = StereoEncoding::Default;
            }
            else if(al::case_compare(*hrtfopt, "auto"sv) != 0)
                ERR("Unexpected hrtf value: %s\n", hrtfopt->c_str());
        }
    }

    if(auto encopt = device->configValue<std::string>({}, "stereo-encoding"sv))
    {
        if(al::case_compare(*encopt, "basic"sv) == 0 || al::case_compare(*encopt, "panpot"sv) == 0)
            stereomode = StereoEncoding::Basic;
        else if(al::case_compare(*encopt, "uhj") == 0)
            stereomode = StereoEncoding::Uhj;
        else if(al::case_compare(*encopt, "hrtf") == 0)
            stereomode = StereoEncoding::Hrtf;
        else
            ERR("Unexpected stereo-encoding: %s\n", encopt->c_str());
    }

    // Check for app-specified attributes
    if(!attrList.empty())
    {
        ALenum outmode{ALC_ANY_SOFT};
        std::optional<bool> opthrtf;
        int freqAttr{};

#define ATTRIBUTE(a) a: TRACE("%s = %d\n", #a, attrList[attrIdx + 1]);
        for(size_t attrIdx{0};attrIdx < attrList.size();attrIdx+=2)
        {
            switch(attrList[attrIdx])
            {
            case ATTRIBUTE(ALC_FORMAT_CHANNELS_SOFT)
                if(device->Type == DeviceType::Loopback)
                    optchans = DevFmtChannelsFromEnum(attrList[attrIdx + 1]);
                break;

            case ATTRIBUTE(ALC_FORMAT_TYPE_SOFT)
                if(device->Type == DeviceType::Loopback)
                    opttype = DevFmtTypeFromEnum(attrList[attrIdx + 1]);
                break;

            case ATTRIBUTE(ALC_FREQUENCY)
                freqAttr = attrList[attrIdx + 1];
                break;

            case ATTRIBUTE(ALC_AMBISONIC_LAYOUT_SOFT)
                if(device->Type == DeviceType::Loopback)
                    optlayout = DevAmbiLayoutFromEnum(attrList[attrIdx + 1]);
                break;

            case ATTRIBUTE(ALC_AMBISONIC_SCALING_SOFT)
                if(device->Type == DeviceType::Loopback)
                    optscale = DevAmbiScalingFromEnum(attrList[attrIdx + 1]);
                break;

            case ATTRIBUTE(ALC_AMBISONIC_ORDER_SOFT)
                if(device->Type == DeviceType::Loopback)
                    aorder = static_cast<uint>(attrList[attrIdx + 1]);
                break;

            case ATTRIBUTE(ALC_MONO_SOURCES)
                numMono = static_cast<uint>(attrList[attrIdx + 1]);
                if(numMono > INT_MAX) numMono = 0;
                break;

            case ATTRIBUTE(ALC_STEREO_SOURCES)
                numStereo = static_cast<uint>(attrList[attrIdx + 1]);
                if(numStereo > INT_MAX) numStereo = 0;
                break;

            case ATTRIBUTE(ALC_MAX_AUXILIARY_SENDS)
                numSends = static_cast<uint>(attrList[attrIdx + 1]);
                if(numSends > uint{std::numeric_limits<int>::max()}) numSends = 0;
                else numSends = std::min(numSends, uint{MaxSendCount});
                break;

            case ATTRIBUTE(ALC_HRTF_SOFT)
                if(attrList[attrIdx + 1] == ALC_FALSE)
                    opthrtf = false;
                else if(attrList[attrIdx + 1] == ALC_TRUE)
                    opthrtf = true;
                else if(attrList[attrIdx + 1] == ALC_DONT_CARE_SOFT)
                    opthrtf = std::nullopt;
                break;

            case ATTRIBUTE(ALC_HRTF_ID_SOFT)
                hrtf_id = attrList[attrIdx + 1];
                break;

            case ATTRIBUTE(ALC_OUTPUT_LIMITER_SOFT)
                if(attrList[attrIdx + 1] == ALC_FALSE)
                    optlimit = false;
                else if(attrList[attrIdx + 1] == ALC_TRUE)
                    optlimit = true;
                else if(attrList[attrIdx + 1] == ALC_DONT_CARE_SOFT)
                    optlimit = std::nullopt;
                break;

            case ATTRIBUTE(ALC_OUTPUT_MODE_SOFT)
                outmode = attrList[attrIdx + 1];
                break;

            default:
                TRACE("0x%04X = %d (0x%x)\n", attrList[attrIdx],
                    attrList[attrIdx + 1], attrList[attrIdx + 1]);
                break;
            }
        }
#undef ATTRIBUTE

        if(device->Type == DeviceType::Loopback)
        {
            if(!optchans || !opttype)
                return ALC_INVALID_VALUE;
            if(freqAttr < int{MinOutputRate} || freqAttr > int{MaxOutputRate})
                return ALC_INVALID_VALUE;
            if(*optchans == DevFmtAmbi3D)
            {
                if(!optlayout || !optscale)
                    return ALC_INVALID_VALUE;
                if(aorder < 1 || aorder > MaxAmbiOrder)
                    return ALC_INVALID_VALUE;
                if((*optlayout == DevAmbiLayout::FuMa || *optscale == DevAmbiScaling::FuMa)
                    && aorder > 3)
                    return ALC_INVALID_VALUE;
            }
            else if(*optchans == DevFmtStereo)
            {
                if(opthrtf)
                {
                    if(*opthrtf)
                        stereomode = StereoEncoding::Hrtf;
                    else
                    {
                        if(stereomode.value_or(StereoEncoding::Hrtf) == StereoEncoding::Hrtf)
                            stereomode = StereoEncoding::Default;
                    }
                }

                if(outmode == ALC_STEREO_BASIC_SOFT)
                    stereomode = StereoEncoding::Basic;
                else if(outmode == ALC_STEREO_UHJ_SOFT)
                    stereomode = StereoEncoding::Uhj;
                else if(outmode == ALC_STEREO_HRTF_SOFT)
                    stereomode = StereoEncoding::Hrtf;
            }

            optsrate = static_cast<uint>(freqAttr);
        }
        else
        {
            if(opthrtf)
            {
                if(*opthrtf)
                    stereomode = StereoEncoding::Hrtf;
                else
                {
                    if(stereomode.value_or(StereoEncoding::Hrtf) == StereoEncoding::Hrtf)
                        stereomode = StereoEncoding::Default;
                }
            }

            if(outmode != ALC_ANY_SOFT)
            {
                using OutputMode = ALCdevice::OutputMode;
                switch(OutputMode(outmode))
                {
                case OutputMode::Any: break;
                case OutputMode::Mono: optchans = DevFmtMono; break;
                case OutputMode::Stereo: optchans = DevFmtStereo; break;
                case OutputMode::StereoBasic:
                    optchans = DevFmtStereo;
                    stereomode = StereoEncoding::Basic;
                    break;
                case OutputMode::Uhj2:
                    optchans = DevFmtStereo;
                    stereomode = StereoEncoding::Uhj;
                    break;
                case OutputMode::Hrtf:
                    optchans = DevFmtStereo;
                    stereomode = StereoEncoding::Hrtf;
                    break;
                case OutputMode::Quad: optchans = DevFmtQuad; break;
                case OutputMode::X51: optchans = DevFmtX51; break;
                case OutputMode::X61: optchans = DevFmtX61; break;
                case OutputMode::X71: optchans = DevFmtX71; break;
                }
            }

            if(freqAttr)
            {
                uint oldrate = optsrate.value_or(DefaultOutputRate);
                freqAttr = std::clamp<int>(freqAttr, MinOutputRate, MaxOutputRate);

                const double scale{static_cast<double>(freqAttr) / oldrate};
                period_size = static_cast<uint>(std::lround(period_size * scale));
                buffer_size = static_cast<uint>(std::lround(buffer_size * scale));
                optsrate = static_cast<uint>(freqAttr);
            }
        }

        /* If a context is already running on the device, stop playback so the
         * device attributes can be updated.
         */
        if(device->mDeviceState == DeviceState::Playing)
        {
            device->Backend->stop();
            device->mDeviceState = DeviceState::Unprepared;
        }

        UpdateClockBase(device);
    }

    if(device->mDeviceState == DeviceState::Playing)
        return ALC_NO_ERROR;

    device->mDeviceState = DeviceState::Unprepared;
    device->AvgSpeakerDist = 0.0f;
    device->mNFCtrlFilter = NfcFilter{};
    device->mUhjEncoder = nullptr;
    device->AmbiDecoder = nullptr;
    device->Bs2b = nullptr;
    device->PostProcess = nullptr;

    device->Limiter = nullptr;
    device->ChannelDelays = nullptr;

    std::fill(std::begin(device->HrtfAccumData), std::end(device->HrtfAccumData), float2{});

    device->Dry.AmbiMap.fill(BFChannelConfig{});
    device->Dry.Buffer = {};
    std::fill(std::begin(device->NumChannelsPerOrder), std::end(device->NumChannelsPerOrder), 0u);
    device->RealOut.RemixMap = {};
    device->RealOut.ChannelIndex.fill(InvalidChannelIndex);
    device->RealOut.Buffer = {};
    device->MixBuffer.clear();
    device->MixBuffer.shrink_to_fit();

    UpdateClockBase(device);
    device->FixedLatency = nanoseconds::zero();

    device->DitherDepth = 0.0f;
    device->DitherSeed = DitherRNGSeed;

    device->mHrtfStatus = ALC_HRTF_DISABLED_SOFT;

    /*************************************************************************
     * Update device format request
     */

    if(device->Type == DeviceType::Loopback)
    {
        device->Frequency = *optsrate;
        device->FmtChans = *optchans;
        device->FmtType = *opttype;
        if(device->FmtChans == DevFmtAmbi3D)
        {
            device->mAmbiOrder = aorder;
            device->mAmbiLayout = *optlayout;
            device->mAmbiScale = *optscale;
        }
        device->Flags.set(FrequencyRequest).set(ChannelsRequest).set(SampleTypeRequest);
    }
    else
    {
        device->FmtType = opttype.value_or(DevFmtTypeDefault);
        device->FmtChans = optchans.value_or(DevFmtChannelsDefault);
        device->mAmbiOrder = 0;
        device->BufferSize = buffer_size;
        device->UpdateSize = period_size;
        device->Frequency = optsrate.value_or(DefaultOutputRate);
        device->Flags.set(FrequencyRequest, optsrate.has_value())
            .set(ChannelsRequest, optchans.has_value())
            .set(SampleTypeRequest, opttype.has_value());

        if(device->FmtChans == DevFmtAmbi3D)
        {
            device->mAmbiOrder = std::clamp(aorder, 1u, uint{MaxAmbiOrder});
            device->mAmbiLayout = optlayout.value_or(DevAmbiLayout::Default);
            device->mAmbiScale = optscale.value_or(DevAmbiScaling::Default);
            if(device->mAmbiOrder > 3
                && (device->mAmbiLayout == DevAmbiLayout::FuMa
                    || device->mAmbiScale == DevAmbiScaling::FuMa))
            {
                ERR("FuMa is incompatible with %d%s order ambisonics (up to 3rd order only)\n",
                    device->mAmbiOrder, GetCounterSuffix(device->mAmbiOrder));
                device->mAmbiOrder = 3;
            }
        }
    }

    TRACE("Pre-reset: %s%s, %s%s, %s%uhz, %u / %u buffer\n",
        device->Flags.test(ChannelsRequest)?"*":"", DevFmtChannelsString(device->FmtChans),
        device->Flags.test(SampleTypeRequest)?"*":"", DevFmtTypeString(device->FmtType),
        device->Flags.test(FrequencyRequest)?"*":"", device->Frequency,
        device->UpdateSize, device->BufferSize);

    const uint oldFreq{device->Frequency};
    const DevFmtChannels oldChans{device->FmtChans};
    const DevFmtType oldType{device->FmtType};
    try {
        auto backend = device->Backend.get();
        if(!backend->reset())
            throw al::backend_exception{al::backend_error::DeviceError, "Device reset failure"};
    }
    catch(std::exception &e) {
        ERR("Device error: %s\n", e.what());
        device->handleDisconnect("%s", e.what());
        return ALC_INVALID_DEVICE;
    }

    if(device->FmtChans != oldChans && device->Flags.test(ChannelsRequest))
    {
        ERR("Failed to set %s, got %s instead\n", DevFmtChannelsString(oldChans),
            DevFmtChannelsString(device->FmtChans));
        device->Flags.reset(ChannelsRequest);
    }
    if(device->FmtType != oldType && device->Flags.test(SampleTypeRequest))
    {
        ERR("Failed to set %s, got %s instead\n", DevFmtTypeString(oldType),
            DevFmtTypeString(device->FmtType));
        device->Flags.reset(SampleTypeRequest);
    }
    if(device->Frequency != oldFreq && device->Flags.test(FrequencyRequest))
    {
        WARN("Failed to set %uhz, got %uhz instead\n", oldFreq, device->Frequency);
        device->Flags.reset(FrequencyRequest);
    }

    TRACE("Post-reset: %s, %s, %uhz, %u / %u buffer\n",
        DevFmtChannelsString(device->FmtChans), DevFmtTypeString(device->FmtType),
        device->Frequency, device->UpdateSize, device->BufferSize);

    if(device->Type != DeviceType::Loopback)
    {
        if(auto modeopt = device->configValue<std::string>({}, "stereo-mode"))
        {
            if(al::case_compare(*modeopt, "headphones"sv) == 0)
                device->Flags.set(DirectEar);
            else if(al::case_compare(*modeopt, "speakers"sv) == 0)
                device->Flags.reset(DirectEar);
            else if(al::case_compare(*modeopt, "auto"sv) != 0)
                ERR("Unexpected stereo-mode: %s\n", modeopt->c_str());
        }
    }

    aluInitRenderer(device, hrtf_id, stereomode);

    /* Calculate the max number of sources, and split them between the mono and
     * stereo count given the requested number of stereo sources.
     */
    if(auto srcsopt = device->configValue<uint>({}, "sources"sv))
    {
        if(*srcsopt <= 0) numMono = 256;
        else numMono = std::max(*srcsopt, 16u);
    }
    else
    {
        numMono = std::min(numMono, std::numeric_limits<int>::max()-numStereo);
        numMono = std::max(numMono+numStereo, 256u);
    }
    numStereo = std::min(numStereo, numMono);
    numMono -= numStereo;
    device->SourcesMax = numMono + numStereo;
    device->NumMonoSources = numMono;
    device->NumStereoSources = numStereo;

    if(auto sendsopt = device->configValue<uint>({}, "sends"sv))
        numSends = std::min(numSends, std::clamp(*sendsopt, 0u, uint{MaxSendCount}));
    device->NumAuxSends = numSends;

    TRACE("Max sources: %d (%d + %d), effect slots: %d, sends: %d\n",
        device->SourcesMax, device->NumMonoSources, device->NumStereoSources,
        device->AuxiliaryEffectSlotMax, device->NumAuxSends);

    switch(device->FmtChans)
    {
    case DevFmtMono: break;
    case DevFmtStereo:
        if(!device->mUhjEncoder)
            device->RealOut.RemixMap = StereoDownmix;
        break;
    case DevFmtQuad: device->RealOut.RemixMap = QuadDownmix; break;
    case DevFmtX51: device->RealOut.RemixMap = X51Downmix; break;
    case DevFmtX61: device->RealOut.RemixMap = X61Downmix; break;
    case DevFmtX71: device->RealOut.RemixMap = X71Downmix; break;
    case DevFmtX714: device->RealOut.RemixMap = X71Downmix; break;
    case DevFmtX7144: device->RealOut.RemixMap = X71Downmix; break;
    case DevFmtX3D71: device->RealOut.RemixMap = X51Downmix; break;
    case DevFmtAmbi3D: break;
    }

    size_t sample_delay{0};
    if(auto *encoder{device->mUhjEncoder.get()})
        sample_delay += encoder->getDelay();

    if(device->getConfigValueBool({}, "dither"sv, true))
    {
        int depth{device->configValue<int>({}, "dither-depth"sv).value_or(0)};
        if(depth <= 0)
        {
            switch(device->FmtType)
            {
            case DevFmtByte:
            case DevFmtUByte:
                depth = 8;
                break;
            case DevFmtShort:
            case DevFmtUShort:
                depth = 16;
                break;
            case DevFmtInt:
            case DevFmtUInt:
            case DevFmtFloat:
                break;
            }
        }

        if(depth > 0)
        {
            depth = std::clamp(depth, 2, 24);
            device->DitherDepth = std::pow(2.0f, static_cast<float>(depth-1));
        }
    }
    if(!(device->DitherDepth > 0.0f))
        TRACE("Dithering disabled\n");
    else
        TRACE("Dithering enabled (%d-bit, %g)\n", float2int(std::log2(device->DitherDepth)+0.5f)+1,
              device->DitherDepth);

    if(!optlimit)
        optlimit = device->configValue<bool>({}, "output-limiter");

    /* If the gain limiter is unset, use the limiter for integer-based output
     * (where samples must be clamped), and don't for floating-point (which can
     * take unclamped samples).
     */
    if(!optlimit)
    {
        switch(device->FmtType)
        {
        case DevFmtByte:
        case DevFmtUByte:
        case DevFmtShort:
        case DevFmtUShort:
        case DevFmtInt:
        case DevFmtUInt:
            optlimit = true;
            break;
        case DevFmtFloat:
            break;
        }
    }
    if(!optlimit.value_or(false))
        TRACE("Output limiter disabled\n");
    else
    {
        float thrshld{1.0f};
        switch(device->FmtType)
        {
        case DevFmtByte:
        case DevFmtUByte:
            thrshld = 127.0f / 128.0f;
            break;
        case DevFmtShort:
        case DevFmtUShort:
            thrshld = 32767.0f / 32768.0f;
            break;
        case DevFmtInt:
        case DevFmtUInt:
        case DevFmtFloat:
            break;
        }
        if(device->DitherDepth > 0.0f)
            thrshld -= 1.0f / device->DitherDepth;

        const float thrshld_dB{std::log10(thrshld) * 20.0f};
        auto limiter = CreateDeviceLimiter(device, thrshld_dB);

        sample_delay += limiter->getLookAhead();
        device->Limiter = std::move(limiter);
        TRACE("Output limiter enabled, %.4fdB limit\n", thrshld_dB);
    }

    /* Convert the sample delay from samples to nanosamples to nanoseconds. */
    sample_delay = std::min<size_t>(sample_delay, std::numeric_limits<int>::max());
    device->FixedLatency += nanoseconds{seconds{sample_delay}} / device->Frequency;
    TRACE("Fixed device latency: %" PRId64 "ns\n", int64_t{device->FixedLatency.count()});

    FPUCtl mixer_mode{};
    auto reset_context = [device](ContextBase *ctxbase)
    {
        auto *context = dynamic_cast<ALCcontext*>(ctxbase);
        assert(context != nullptr);
        if(!context) return;

        std::unique_lock<std::mutex> proplock{context->mPropLock};
        std::unique_lock<std::mutex> slotlock{context->mEffectSlotLock};

        /* Clear out unused effect slot clusters. */
        auto slot_cluster_not_in_use = [](ContextBase::EffectSlotCluster &clusterptr) -> bool
        {
            return std::none_of(clusterptr->begin(), clusterptr->end(),
                std::mem_fn(&EffectSlot::InUse));
        };
        auto slotcluster_end = std::remove_if(context->mEffectSlotClusters.begin(),
            context->mEffectSlotClusters.end(), slot_cluster_not_in_use);
        context->mEffectSlotClusters.erase(slotcluster_end, context->mEffectSlotClusters.end());

        /* Free all wet buffers. Any in use will be reallocated with an updated
         * configuration in aluInitEffectPanning.
         */
        auto clear_wetbuffers = [](ContextBase::EffectSlotCluster &clusterptr)
        {
            auto clear_buffer = [](EffectSlot &slot)
            {
                slot.mWetBuffer.clear();
                slot.mWetBuffer.shrink_to_fit();
                slot.Wet.Buffer = {};
            };
            std::for_each(clusterptr->begin(), clusterptr->end(), clear_buffer);
        };
        std::for_each(context->mEffectSlotClusters.begin(), context->mEffectSlotClusters.end(),
            clear_wetbuffers);

        if(ALeffectslot *slot{context->mDefaultSlot.get()})
        {
            auto *slotbase = slot->mSlot;
            aluInitEffectPanning(slotbase, context);

            if(auto *props = slotbase->Update.exchange(nullptr, std::memory_order_relaxed))
                AtomicReplaceHead(context->mFreeEffectSlotProps, props);

            EffectState *state{slot->Effect.State.get()};
            state->mOutTarget = device->Dry.Buffer;
            state->deviceUpdate(device, slot->Buffer);
            slot->mPropsDirty = true;
        }

        if(EffectSlotArray *curarray{context->mActiveAuxSlots.load(std::memory_order_relaxed)})
            std::fill(curarray->begin()+ptrdiff_t(curarray->size()>>1), curarray->end(), nullptr);
        auto reset_slots = [device,context](EffectSlotSubList &sublist)
        {
            uint64_t usemask{~sublist.FreeMask};
            while(usemask)
            {
                const auto idx = static_cast<uint>(al::countr_zero(usemask));
                auto &slot = (*sublist.EffectSlots)[idx];
                usemask &= ~(1_u64 << idx);

                auto *slotbase = slot.mSlot;
                aluInitEffectPanning(slotbase, context);

                if(auto *props = slotbase->Update.exchange(nullptr, std::memory_order_relaxed))
                    AtomicReplaceHead(context->mFreeEffectSlotProps, props);

                EffectState *state{slot.Effect.State.get()};
                state->mOutTarget = device->Dry.Buffer;
                state->deviceUpdate(device, slot.Buffer);
                slot.mPropsDirty = true;
            }
        };
        std::for_each(context->mEffectSlotList.begin(), context->mEffectSlotList.end(),
            reset_slots);

        /* Clear all effect slot props to let them get allocated again. */
        context->mEffectSlotPropClusters.clear();
        context->mFreeEffectSlotProps.store(nullptr, std::memory_order_relaxed);
        slotlock.unlock();

        std::unique_lock<std::mutex> srclock{context->mSourceLock};
        const uint num_sends{device->NumAuxSends};
        auto reset_sources = [num_sends](SourceSubList &sublist)
        {
            uint64_t usemask{~sublist.FreeMask};
            while(usemask)
            {
                const auto idx = static_cast<uint>(al::countr_zero(usemask));
                auto &source = (*sublist.Sources)[idx];
                usemask &= ~(1_u64 << idx);

                auto clear_send = [](ALsource::SendData &send) -> void
                {
                    if(send.Slot)
                        DecrementRef(send.Slot->ref);
                    send.Slot = nullptr;
                    send.Gain = 1.0f;
                    send.GainHF = 1.0f;
                    send.HFReference = LowPassFreqRef;
                    send.GainLF = 1.0f;
                    send.LFReference = HighPassFreqRef;
                };
                const auto sends = al::span{source.Send}.subspan(num_sends);
                std::for_each(sends.begin(), sends.end(), clear_send);

                source.mPropsDirty = true;
            }
        };
        std::for_each(context->mSourceList.begin(), context->mSourceList.end(), reset_sources);

        auto reset_voice = [device,num_sends,context](Voice *voice)
        {
            /* Clear extraneous property set sends. */
            const auto sendparams = al::span{voice->mProps.Send}.subspan(num_sends);
            std::fill(sendparams.begin(), sendparams.end(), VoiceProps::SendData{});

            std::fill(voice->mSend.begin()+num_sends, voice->mSend.end(), Voice::TargetData{});
            auto clear_wetparams = [num_sends](Voice::ChannelData &chandata)
            {
                const auto wetparams = al::span{chandata.mWetParams}.subspan(num_sends);
                std::fill(wetparams.begin(), wetparams.end(), SendParams{});
            };
            std::for_each(voice->mChans.begin(), voice->mChans.end(), clear_wetparams);

            if(VoicePropsItem *props{voice->mUpdate.exchange(nullptr, std::memory_order_relaxed)})
                AtomicReplaceHead(context->mFreeVoiceProps, props);

            /* Force the voice to stopped if it was stopping. */
            Voice::State vstate{Voice::Stopping};
            voice->mPlayState.compare_exchange_strong(vstate, Voice::Stopped,
                std::memory_order_acquire, std::memory_order_acquire);
            if(voice->mSourceID.load(std::memory_order_relaxed) == 0u)
                return;

            voice->prepare(device);
        };
        const auto voicespan = context->getVoicesSpan();
        std::for_each(voicespan.begin(), voicespan.end(), reset_voice);

        /* Clear all voice props to let them get allocated again. */
        context->mVoicePropClusters.clear();
        context->mFreeVoiceProps.store(nullptr, std::memory_order_relaxed);
        srclock.unlock();

        context->mPropsDirty = false;
        UpdateContextProps(context);
        UpdateAllEffectSlotProps(context);
        UpdateAllSourceProps(context);
    };
    auto ctxspan = al::span{*device->mContexts.load()};
    std::for_each(ctxspan.begin(), ctxspan.end(), reset_context);
    mixer_mode.leave();

    device->mDeviceState = DeviceState::Configured;
    if(!device->Flags.test(DevicePaused))
    {
        try {
            auto backend = device->Backend.get();
            backend->start();
            device->mDeviceState = DeviceState::Playing;
        }
        catch(al::backend_exception& e) {
            ERR("%s\n", e.what());
            device->handleDisconnect("%s", e.what());
            return ALC_INVALID_DEVICE;
        }
        TRACE("Post-start: %s, %s, %uhz, %u / %u buffer\n",
            DevFmtChannelsString(device->FmtChans), DevFmtTypeString(device->FmtType),
            device->Frequency, device->UpdateSize, device->BufferSize);
    }

    return ALC_NO_ERROR;
}

/**
 * Updates device parameters as above, and also first clears the disconnected
 * status, if set.
 */
bool ResetDeviceParams(ALCdevice *device, const al::span<const int> attrList)
{
    /* If the device was disconnected, reset it since we're opened anew. */
    if(!device->Connected.load(std::memory_order_relaxed)) UNLIKELY
    {
        /* Make sure disconnection is finished before continuing on. */
        std::ignore = device->waitForMix();

        for(ContextBase *ctxbase : *device->mContexts.load(std::memory_order_acquire))
        {
            auto *ctx = dynamic_cast<ALCcontext*>(ctxbase);
            assert(ctx != nullptr);
            if(!ctx || !ctx->mStopVoicesOnDisconnect.load(std::memory_order_acquire))
                continue;

            /* Clear any pending voice changes and reallocate voices to get a
             * clean restart.
             */
            std::lock_guard<std::mutex> sourcelock{ctx->mSourceLock};
            auto *vchg = ctx->mCurrentVoiceChange.load(std::memory_order_acquire);
            while(auto *next = vchg->mNext.load(std::memory_order_acquire))
                vchg = next;
            ctx->mCurrentVoiceChange.store(vchg, std::memory_order_release);

            ctx->mVoicePropClusters.clear();
            ctx->mFreeVoiceProps.store(nullptr, std::memory_order_relaxed);

            ctx->mVoiceClusters.clear();
            ctx->allocVoices(std::max<size_t>(256,
                ctx->mActiveVoiceCount.load(std::memory_order_relaxed)));
        }

        device->Connected.store(true);
    }

    ALCenum err{UpdateDeviceParams(device, attrList)};
    if(err == ALC_NO_ERROR) LIKELY return ALC_TRUE;

    alcSetError(device, err);
    return ALC_FALSE;
}


/** Checks if the device handle is valid, and returns a new reference if so. */
DeviceRef VerifyDevice(ALCdevice *device)
{
    std::lock_guard<std::recursive_mutex> listlock{ListLock};
    auto iter = std::lower_bound(DeviceList.begin(), DeviceList.end(), device);
    if(iter != DeviceList.end() && *iter == device)
    {
        (*iter)->add_ref();
        return DeviceRef{*iter};
    }
    return nullptr;
}


/**
 * Checks if the given context is valid, returning a new reference to it if so.
 */
ContextRef VerifyContext(ALCcontext *context)
{
    std::lock_guard<std::recursive_mutex> listlock{ListLock};
    auto iter = std::lower_bound(ContextList.begin(), ContextList.end(), context);
    if(iter != ContextList.end() && *iter == context)
    {
        (*iter)->add_ref();
        return ContextRef{*iter};
    }
    return nullptr;
}

} // namespace

FORCE_ALIGN void ALC_APIENTRY alsoft_set_log_callback(LPALSOFTLOGCALLBACK callback, void *userptr) noexcept
{
    al_set_log_callback(callback, userptr);
}

/** Returns a new reference to the currently active context for this thread. */
ContextRef GetContextRef() noexcept
{
    ALCcontext *context{ALCcontext::getThreadContext()};
    if(context)
        context->add_ref();
    else
    {
        while(ALCcontext::sGlobalContextLock.exchange(true, std::memory_order_acquire)) {
            /* Wait to make sure another thread isn't trying to change the
             * current context and bring its refcount to 0.
             */
        }
        context = ALCcontext::sGlobalContext.load(std::memory_order_acquire);
        if(context) LIKELY context->add_ref();
        ALCcontext::sGlobalContextLock.store(false, std::memory_order_release);
    }
    return ContextRef{context};
}

void alcSetError(ALCdevice *device, ALCenum errorCode)
{
    WARN("Error generated on device %p, code 0x%04x\n", voidp{device}, errorCode);
    if(TrapALCError)
    {
#ifdef _WIN32
        /* DebugBreak() will cause an exception if there is no debugger */
        if(IsDebuggerPresent())
            DebugBreak();
#elif defined(SIGTRAP)
        raise(SIGTRAP);
#endif
    }

    if(device)
        device->LastError.store(errorCode);
    else
        LastNullDeviceError.store(errorCode);
}

/************************************************
 * Standard ALC functions
 ************************************************/

ALC_API ALCenum ALC_APIENTRY alcGetError(ALCdevice *device) noexcept
{
    if(!gProcessRunning)
        return ALC_INVALID_DEVICE;

    DeviceRef dev{VerifyDevice(device)};
    if(dev) return dev->LastError.exchange(ALC_NO_ERROR);
    return LastNullDeviceError.exchange(ALC_NO_ERROR);
}


ALC_API void ALC_APIENTRY alcSuspendContext(ALCcontext *context) noexcept
{
    ContextRef ctx{VerifyContext(context)};
    if(!ctx)
    {
        alcSetError(nullptr, ALC_INVALID_CONTEXT);
        return;
    }

    if(ctx->mContextFlags.test(ContextFlags::DebugBit)) UNLIKELY
        ctx->debugMessage(DebugSource::API, DebugType::Portability, 0, DebugSeverity::Medium,
            "alcSuspendContext behavior is not portable -- some implementations suspend all "
            "rendering, some only defer property changes, and some are completely no-op; consider "
            "using alcDevicePauseSOFT to suspend all rendering, or alDeferUpdatesSOFT to only "
            "defer property changes");

    if(SuspendDefers)
    {
        std::lock_guard<std::mutex> proplock{ctx->mPropLock};
        ctx->deferUpdates();
    }
}

ALC_API void ALC_APIENTRY alcProcessContext(ALCcontext *context) noexcept
{
    ContextRef ctx{VerifyContext(context)};
    if(!ctx)
    {
        alcSetError(nullptr, ALC_INVALID_CONTEXT);
        return;
    }

    if(ctx->mContextFlags.test(ContextFlags::DebugBit)) UNLIKELY
        ctx->debugMessage(DebugSource::API, DebugType::Portability, 1, DebugSeverity::Medium,
            "alcProcessContext behavior is not portable -- some implementations resume rendering, "
            "some apply deferred property changes, and some are completely no-op; consider using "
            "alcDeviceResumeSOFT to resume rendering, or alProcessUpdatesSOFT to apply deferred "
            "property changes");

    if(SuspendDefers)
    {
        std::lock_guard<std::mutex> proplock{ctx->mPropLock};
        ctx->processUpdates();
    }
}


ALC_API auto ALC_APIENTRY alcGetString(ALCdevice *Device, ALCenum param) noexcept -> const ALCchar*
{
    switch(param)
    {
    case ALC_NO_ERROR: return GetNoErrorString();
    case ALC_INVALID_ENUM: return GetInvalidEnumString();
    case ALC_INVALID_VALUE: return GetInvalidValueString();
    case ALC_INVALID_DEVICE: return GetInvalidDeviceString();
    case ALC_INVALID_CONTEXT: return GetInvalidContextString();
    case ALC_OUT_OF_MEMORY: return GetOutOfMemoryString();

    case ALC_DEVICE_SPECIFIER:
        return GetDefaultName();

    case ALC_ALL_DEVICES_SPECIFIER:
        if(DeviceRef dev{VerifyDevice(Device)})
        {
            if(dev->Type == DeviceType::Capture)
            {
                alcSetError(dev.get(), ALC_INVALID_ENUM);
                return nullptr;
            }
            if(dev->Type == DeviceType::Loopback)
                return GetDefaultName();

            auto statelock = std::lock_guard{dev->StateLock};
            return dev->mDeviceName.c_str();
        }
        ProbeAllDevicesList();
        return alcAllDevicesList.c_str();

    case ALC_CAPTURE_DEVICE_SPECIFIER:
        if(DeviceRef dev{VerifyDevice(Device)})
        {
            if(dev->Type != DeviceType::Capture)
            {
                alcSetError(dev.get(), ALC_INVALID_ENUM);
                return nullptr;
            }

            auto statelock = std::lock_guard{dev->StateLock};
            return dev->mDeviceName.c_str();
        }
        ProbeCaptureDeviceList();
        return alcCaptureDeviceList.c_str();

    /* Default devices are always first in the list */
    case ALC_DEFAULT_DEVICE_SPECIFIER:
        return GetDefaultName();

    case ALC_DEFAULT_ALL_DEVICES_SPECIFIER:
        if(alcAllDevicesList.empty())
            ProbeAllDevicesList();

        /* Copy first entry as default. */
        if(alcAllDevicesArray.empty())
            return GetDefaultName();

        alcDefaultAllDevicesSpecifier = alcAllDevicesArray.front();
        return alcDefaultAllDevicesSpecifier.c_str();

    case ALC_CAPTURE_DEFAULT_DEVICE_SPECIFIER:
        if(alcCaptureDeviceList.empty())
            ProbeCaptureDeviceList();

        /* Copy first entry as default. */
        if(alcCaptureDeviceArray.empty())
            return GetDefaultName();

        alcCaptureDefaultDeviceSpecifier = alcCaptureDeviceArray.front();
        return alcCaptureDefaultDeviceSpecifier.c_str();

    case ALC_EXTENSIONS:
        if(VerifyDevice(Device))
            return GetExtensionList();
        return GetNoDeviceExtList();

    case ALC_HRTF_SPECIFIER_SOFT:
        if(DeviceRef dev{VerifyDevice(Device)})
        {
            std::lock_guard<std::mutex> statelock{dev->StateLock};
            return dev->mHrtf ? dev->mHrtfName.c_str() : "";
        }
        alcSetError(nullptr, ALC_INVALID_DEVICE);
        return nullptr;

    default:
        alcSetError(VerifyDevice(Device).get(), ALC_INVALID_ENUM);
    }

    return nullptr;
}


static size_t GetIntegerv(ALCdevice *device, ALCenum param, const al::span<int> values)
{
    if(values.empty())
    {
        alcSetError(device, ALC_INVALID_VALUE);
        return 0;
    }

    if(!device)
    {
        switch(param)
        {
        case ALC_MAJOR_VERSION:
            values[0] = alcMajorVersion;
            return 1;
        case ALC_MINOR_VERSION:
            values[0] = alcMinorVersion;
            return 1;

        case ALC_EFX_MAJOR_VERSION:
            values[0] = alcEFXMajorVersion;
            return 1;
        case ALC_EFX_MINOR_VERSION:
            values[0] = alcEFXMinorVersion;
            return 1;
        case ALC_MAX_AUXILIARY_SENDS:
            values[0] = MaxSendCount;
            return 1;

        case ALC_ATTRIBUTES_SIZE:
        case ALC_ALL_ATTRIBUTES:
        case ALC_FREQUENCY:
        case ALC_REFRESH:
        case ALC_SYNC:
        case ALC_MONO_SOURCES:
        case ALC_STEREO_SOURCES:
        case ALC_CAPTURE_SAMPLES:
        case ALC_FORMAT_CHANNELS_SOFT:
        case ALC_FORMAT_TYPE_SOFT:
        case ALC_AMBISONIC_LAYOUT_SOFT:
        case ALC_AMBISONIC_SCALING_SOFT:
        case ALC_AMBISONIC_ORDER_SOFT:
        case ALC_MAX_AMBISONIC_ORDER_SOFT:
            alcSetError(nullptr, ALC_INVALID_DEVICE);
            return 0;

        default:
            alcSetError(nullptr, ALC_INVALID_ENUM);
        }
        return 0;
    }

    std::lock_guard<std::mutex> statelock{device->StateLock};
    if(device->Type == DeviceType::Capture)
    {
        static constexpr int MaxCaptureAttributes{9};
        switch(param)
        {
        case ALC_ATTRIBUTES_SIZE:
            values[0] = MaxCaptureAttributes;
            return 1;
        case ALC_ALL_ATTRIBUTES:
            if(values.size() >= MaxCaptureAttributes)
            {
                size_t i{0};
                values[i++] = ALC_MAJOR_VERSION;
                values[i++] = alcMajorVersion;
                values[i++] = ALC_MINOR_VERSION;
                values[i++] = alcMinorVersion;
                values[i++] = ALC_CAPTURE_SAMPLES;
                values[i++] = static_cast<int>(device->Backend->availableSamples());
                values[i++] = ALC_CONNECTED;
                values[i++] = device->Connected.load(std::memory_order_relaxed);
                values[i++] = 0;
                assert(i == MaxCaptureAttributes);
                return i;
            }
            alcSetError(device, ALC_INVALID_VALUE);
            return 0;

        case ALC_MAJOR_VERSION:
            values[0] = alcMajorVersion;
            return 1;
        case ALC_MINOR_VERSION:
            values[0] = alcMinorVersion;
            return 1;

        case ALC_CAPTURE_SAMPLES:
            values[0] = static_cast<int>(device->Backend->availableSamples());
            return 1;

        case ALC_CONNECTED:
            values[0] = device->Connected.load(std::memory_order_acquire);
            return 1;

        default:
            alcSetError(device, ALC_INVALID_ENUM);
        }
        return 0;
    }

    /* render device */
    auto NumAttrsForDevice = [](const ALCdevice *aldev) noexcept -> uint8_t
    {
        if(aldev->Type == DeviceType::Loopback && aldev->FmtChans == DevFmtAmbi3D)
            return 37;
        return 31;
    };
    switch(param)
    {
    case ALC_ATTRIBUTES_SIZE:
        values[0] = NumAttrsForDevice(device);
        return 1;

    case ALC_ALL_ATTRIBUTES:
        if(values.size() >= NumAttrsForDevice(device))
        {
            size_t i{0};
            values[i++] = ALC_MAJOR_VERSION;
            values[i++] = alcMajorVersion;
            values[i++] = ALC_MINOR_VERSION;
            values[i++] = alcMinorVersion;
            values[i++] = ALC_EFX_MAJOR_VERSION;
            values[i++] = alcEFXMajorVersion;
            values[i++] = ALC_EFX_MINOR_VERSION;
            values[i++] = alcEFXMinorVersion;

            values[i++] = ALC_FREQUENCY;
            values[i++] = static_cast<int>(device->Frequency);
            if(device->Type != DeviceType::Loopback)
            {
                values[i++] = ALC_REFRESH;
                values[i++] = static_cast<int>(device->Frequency / device->UpdateSize);

                values[i++] = ALC_SYNC;
                values[i++] = ALC_FALSE;
            }
            else
            {
                if(device->FmtChans == DevFmtAmbi3D)
                {
                    values[i++] = ALC_AMBISONIC_LAYOUT_SOFT;
                    values[i++] = EnumFromDevAmbi(device->mAmbiLayout);

                    values[i++] = ALC_AMBISONIC_SCALING_SOFT;
                    values[i++] = EnumFromDevAmbi(device->mAmbiScale);

                    values[i++] = ALC_AMBISONIC_ORDER_SOFT;
                    values[i++] = static_cast<int>(device->mAmbiOrder);
                }

                values[i++] = ALC_FORMAT_CHANNELS_SOFT;
                values[i++] = EnumFromDevFmt(device->FmtChans);

                values[i++] = ALC_FORMAT_TYPE_SOFT;
                values[i++] = EnumFromDevFmt(device->FmtType);
            }

            values[i++] = ALC_MONO_SOURCES;
            values[i++] = static_cast<int>(device->NumMonoSources);

            values[i++] = ALC_STEREO_SOURCES;
            values[i++] = static_cast<int>(device->NumStereoSources);

            values[i++] = ALC_MAX_AUXILIARY_SENDS;
            values[i++] = static_cast<int>(device->NumAuxSends);

            values[i++] = ALC_HRTF_SOFT;
            values[i++] = (device->mHrtf ? ALC_TRUE : ALC_FALSE);

            values[i++] = ALC_HRTF_STATUS_SOFT;
            values[i++] = device->mHrtfStatus;

            values[i++] = ALC_OUTPUT_LIMITER_SOFT;
            values[i++] = device->Limiter ? ALC_TRUE : ALC_FALSE;

            values[i++] = ALC_MAX_AMBISONIC_ORDER_SOFT;
            values[i++] = MaxAmbiOrder;

            values[i++] = ALC_OUTPUT_MODE_SOFT;
            values[i++] = static_cast<ALCenum>(device->getOutputMode1());

            values[i++] = 0;
            assert(i == NumAttrsForDevice(device));
            return i;
        }
        alcSetError(device, ALC_INVALID_VALUE);
        return 0;

    case ALC_MAJOR_VERSION:
        values[0] = alcMajorVersion;
        return 1;

    case ALC_MINOR_VERSION:
        values[0] = alcMinorVersion;
        return 1;

    case ALC_EFX_MAJOR_VERSION:
        values[0] = alcEFXMajorVersion;
        return 1;

    case ALC_EFX_MINOR_VERSION:
        values[0] = alcEFXMinorVersion;
        return 1;

    case ALC_FREQUENCY:
        values[0] = static_cast<int>(device->Frequency);
        return 1;

    case ALC_REFRESH:
        if(device->Type == DeviceType::Loopback)
        {
            alcSetError(device, ALC_INVALID_DEVICE);
            return 0;
        }
        values[0] = static_cast<int>(device->Frequency / device->UpdateSize);
        return 1;

    case ALC_SYNC:
        if(device->Type == DeviceType::Loopback)
        {
            alcSetError(device, ALC_INVALID_DEVICE);
            return 0;
        }
        values[0] = ALC_FALSE;
        return 1;

    case ALC_FORMAT_CHANNELS_SOFT:
        if(device->Type != DeviceType::Loopback)
        {
            alcSetError(device, ALC_INVALID_DEVICE);
            return 0;
        }
        values[0] = EnumFromDevFmt(device->FmtChans);
        return 1;

    case ALC_FORMAT_TYPE_SOFT:
        if(device->Type != DeviceType::Loopback)
        {
            alcSetError(device, ALC_INVALID_DEVICE);
            return 0;
        }
        values[0] = EnumFromDevFmt(device->FmtType);
        return 1;

    case ALC_AMBISONIC_LAYOUT_SOFT:
        if(device->Type != DeviceType::Loopback || device->FmtChans != DevFmtAmbi3D)
        {
            alcSetError(device, ALC_INVALID_DEVICE);
            return 0;
        }
        values[0] = EnumFromDevAmbi(device->mAmbiLayout);
        return 1;

    case ALC_AMBISONIC_SCALING_SOFT:
        if(device->Type != DeviceType::Loopback || device->FmtChans != DevFmtAmbi3D)
        {
            alcSetError(device, ALC_INVALID_DEVICE);
            return 0;
        }
        values[0] = EnumFromDevAmbi(device->mAmbiScale);
        return 1;

    case ALC_AMBISONIC_ORDER_SOFT:
        if(device->Type != DeviceType::Loopback || device->FmtChans != DevFmtAmbi3D)
        {
            alcSetError(device, ALC_INVALID_DEVICE);
            return 0;
        }
        values[0] = static_cast<int>(device->mAmbiOrder);
        return 1;

    case ALC_MONO_SOURCES:
        values[0] = static_cast<int>(device->NumMonoSources);
        return 1;

    case ALC_STEREO_SOURCES:
        values[0] = static_cast<int>(device->NumStereoSources);
        return 1;

    case ALC_MAX_AUXILIARY_SENDS:
        values[0] = static_cast<int>(device->NumAuxSends);
        return 1;

    case ALC_CONNECTED:
        values[0] = device->Connected.load(std::memory_order_acquire);
        return 1;

    case ALC_HRTF_SOFT:
        values[0] = (device->mHrtf ? ALC_TRUE : ALC_FALSE);
        return 1;

    case ALC_HRTF_STATUS_SOFT:
        values[0] = device->mHrtfStatus;
        return 1;

    case ALC_NUM_HRTF_SPECIFIERS_SOFT:
        device->enumerateHrtfs();
        values[0] = static_cast<int>(std::min(device->mHrtfList.size(),
            size_t{std::numeric_limits<int>::max()}));
        return 1;

    case ALC_OUTPUT_LIMITER_SOFT:
        values[0] = device->Limiter ? ALC_TRUE : ALC_FALSE;
        return 1;

    case ALC_MAX_AMBISONIC_ORDER_SOFT:
        values[0] = MaxAmbiOrder;
        return 1;

    case ALC_OUTPUT_MODE_SOFT:
        values[0] = static_cast<ALCenum>(device->getOutputMode1());
        return 1;

    default:
        alcSetError(device, ALC_INVALID_ENUM);
    }
    return 0;
}

ALC_API void ALC_APIENTRY alcGetIntegerv(ALCdevice *device, ALCenum param, ALCsizei size, ALCint *values) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(size <= 0 || values == nullptr)
        alcSetError(dev.get(), ALC_INVALID_VALUE);
    else
        GetIntegerv(dev.get(), param, {values, static_cast<uint>(size)});
}

ALC_API void ALC_APIENTRY alcGetInteger64vSOFT(ALCdevice *device, ALCenum pname, ALCsizei size, ALCint64SOFT *values) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(size <= 0 || values == nullptr)
    {
        alcSetError(dev.get(), ALC_INVALID_VALUE);
        return;
    }
    const auto valuespan = al::span{values, static_cast<uint>(size)};
    if(!dev || dev->Type == DeviceType::Capture)
    {
        auto ivals = std::vector<int>(valuespan.size());
        if(size_t got{GetIntegerv(dev.get(), pname, ivals)})
            std::copy_n(ivals.cbegin(), got, valuespan.begin());
        return;
    }
    /* render device */
    auto NumAttrsForDevice = [](ALCdevice *aldev) noexcept -> size_t
    {
        if(aldev->Type == DeviceType::Loopback && aldev->FmtChans == DevFmtAmbi3D)
            return 41;
        return 35;
    };
    std::lock_guard<std::mutex> statelock{dev->StateLock};
    switch(pname)
    {
    case ALC_ATTRIBUTES_SIZE:
        valuespan[0] = static_cast<ALCint64SOFT>(NumAttrsForDevice(dev.get()));
        break;

    case ALC_ALL_ATTRIBUTES:
        if(valuespan.size() < NumAttrsForDevice(dev.get()))
            alcSetError(dev.get(), ALC_INVALID_VALUE);
        else
        {
            size_t i{0};
            valuespan[i++] = ALC_FREQUENCY;
            valuespan[i++] = dev->Frequency;

            if(dev->Type != DeviceType::Loopback)
            {
                valuespan[i++] = ALC_REFRESH;
                valuespan[i++] = dev->Frequency / dev->UpdateSize;

                valuespan[i++] = ALC_SYNC;
                valuespan[i++] = ALC_FALSE;
            }
            else
            {
                valuespan[i++] = ALC_FORMAT_CHANNELS_SOFT;
                valuespan[i++] = EnumFromDevFmt(dev->FmtChans);

                valuespan[i++] = ALC_FORMAT_TYPE_SOFT;
                valuespan[i++] = EnumFromDevFmt(dev->FmtType);

                if(dev->FmtChans == DevFmtAmbi3D)
                {
                    valuespan[i++] = ALC_AMBISONIC_LAYOUT_SOFT;
                    valuespan[i++] = EnumFromDevAmbi(dev->mAmbiLayout);

                    valuespan[i++] = ALC_AMBISONIC_SCALING_SOFT;
                    valuespan[i++] = EnumFromDevAmbi(dev->mAmbiScale);

                    valuespan[i++] = ALC_AMBISONIC_ORDER_SOFT;
                    valuespan[i++] = dev->mAmbiOrder;
                }
            }

            valuespan[i++] = ALC_MONO_SOURCES;
            valuespan[i++] = dev->NumMonoSources;

            valuespan[i++] = ALC_STEREO_SOURCES;
            valuespan[i++] = dev->NumStereoSources;

            valuespan[i++] = ALC_MAX_AUXILIARY_SENDS;
            valuespan[i++] = dev->NumAuxSends;

            valuespan[i++] = ALC_HRTF_SOFT;
            valuespan[i++] = (dev->mHrtf ? ALC_TRUE : ALC_FALSE);

            valuespan[i++] = ALC_HRTF_STATUS_SOFT;
            valuespan[i++] = dev->mHrtfStatus;

            valuespan[i++] = ALC_OUTPUT_LIMITER_SOFT;
            valuespan[i++] = dev->Limiter ? ALC_TRUE : ALC_FALSE;

            ClockLatency clock{GetClockLatency(dev.get(), dev->Backend.get())};
            valuespan[i++] = ALC_DEVICE_CLOCK_SOFT;
            valuespan[i++] = clock.ClockTime.count();

            valuespan[i++] = ALC_DEVICE_LATENCY_SOFT;
            valuespan[i++] = clock.Latency.count();

            valuespan[i++] = ALC_OUTPUT_MODE_SOFT;
            valuespan[i++] = al::to_underlying(device->getOutputMode1());

            valuespan[i++] = 0;
        }
        break;

    case ALC_DEVICE_CLOCK_SOFT:
        {
            uint samplecount, refcount;
            nanoseconds basecount;
            do {
                refcount = dev->waitForMix();
                basecount = dev->mClockBase.load(std::memory_order_relaxed);
                samplecount = dev->mSamplesDone.load(std::memory_order_relaxed);
                std::atomic_thread_fence(std::memory_order_acquire);
            } while(refcount != dev->mMixCount.load(std::memory_order_relaxed));
            basecount += nanoseconds{seconds{samplecount}} / dev->Frequency;
            valuespan[0] = basecount.count();
        }
        break;

    case ALC_DEVICE_LATENCY_SOFT:
        valuespan[0] = GetClockLatency(dev.get(), dev->Backend.get()).Latency.count();
        break;

    case ALC_DEVICE_CLOCK_LATENCY_SOFT:
        if(size < 2)
            alcSetError(dev.get(), ALC_INVALID_VALUE);
        else
        {
            ClockLatency clock{GetClockLatency(dev.get(), dev->Backend.get())};
            valuespan[0] = clock.ClockTime.count();
            valuespan[1] = clock.Latency.count();
        }
        break;

    default:
        auto ivals = std::vector<int>(valuespan.size());
        if(size_t got{GetIntegerv(dev.get(), pname, ivals)})
            std::copy_n(ivals.cbegin(), got, valuespan.begin());
        break;
    }
}


ALC_API ALCboolean ALC_APIENTRY alcIsExtensionPresent(ALCdevice *device, const ALCchar *extName) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(!extName)
    {
        alcSetError(dev.get(), ALC_INVALID_VALUE);
        return ALC_FALSE;
    }

    const std::string_view tofind{extName};
    const auto extlist = dev ? std::string_view{GetExtensionList()}
        : std::string_view{GetNoDeviceExtList()};
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


ALCvoid* ALC_APIENTRY alcGetProcAddress2(ALCdevice *device, const ALCchar *funcName) noexcept
{ return alcGetProcAddress(device, funcName); }

ALC_API ALCvoid* ALC_APIENTRY alcGetProcAddress(ALCdevice *device, const ALCchar *funcName) noexcept
{
    if(!funcName)
    {
        DeviceRef dev{VerifyDevice(device)};
        alcSetError(dev.get(), ALC_INVALID_VALUE);
        return nullptr;
    }

#if ALSOFT_EAX
    if(eax_g_is_enabled)
    {
        for(const auto &func : eaxFunctions)
        {
            if(strcmp(func.funcName, funcName) == 0)
                return func.address;
        }
    }
#endif
    for(const auto &func : alcFunctions)
    {
        if(strcmp(func.funcName, funcName) == 0)
            return func.address;
    }
    return nullptr;
}


ALC_API ALCenum ALC_APIENTRY alcGetEnumValue(ALCdevice *device, const ALCchar *enumName) noexcept
{
    if(!enumName)
    {
        DeviceRef dev{VerifyDevice(device)};
        alcSetError(dev.get(), ALC_INVALID_VALUE);
        return 0;
    }

#if ALSOFT_EAX
    if(eax_g_is_enabled)
    {
        for(const auto &enm : eaxEnumerations)
        {
            if(strcmp(enm.enumName, enumName) == 0)
                return enm.value;
        }
    }
#endif
    for(const auto &enm : alcEnumerations)
    {
        if(strcmp(enm.enumName, enumName) == 0)
            return enm.value;
    }

    return 0;
}


ALC_API ALCcontext* ALC_APIENTRY alcCreateContext(ALCdevice *device, const ALCint *attrList) noexcept
{
    /* Explicitly hold the list lock while taking the StateLock in case the
     * device is asynchronously destroyed, to ensure this new context is
     * properly cleaned up after being made.
     */
    std::unique_lock<std::recursive_mutex> listlock{ListLock};
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type == DeviceType::Capture || !dev->Connected.load(std::memory_order_relaxed))
    {
        listlock.unlock();
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
        return nullptr;
    }
    std::unique_lock<std::mutex> statelock{dev->StateLock};
    listlock.unlock();

    dev->LastError.store(ALC_NO_ERROR);

    const auto attrSpan = SpanFromAttributeList(attrList);
    ALCenum err{UpdateDeviceParams(dev.get(), attrSpan)};
    if(err != ALC_NO_ERROR)
    {
        alcSetError(dev.get(), err);
        return nullptr;
    }

    ContextFlagBitset ctxflags{0};
    for(size_t i{0};i < attrSpan.size();i+=2)
    {
        if(attrSpan[i] == ALC_CONTEXT_FLAGS_EXT)
        {
            ctxflags = static_cast<ALuint>(attrSpan[i+1]);
            break;
        }
    }

    auto context = ContextRef{new(std::nothrow) ALCcontext{dev, ctxflags}};
    if(!context)
    {
        alcSetError(dev.get(), ALC_OUT_OF_MEMORY);
        return nullptr;
    }
    context->init();

    if(auto volopt = dev->configValue<float>({}, "volume-adjust"))
    {
        const float valf{*volopt};
        if(!std::isfinite(valf))
            ERR("volume-adjust must be finite: %f\n", valf);
        else
        {
            const float db{std::clamp(valf, -24.0f, 24.0f)};
            if(db != valf)
                WARN("volume-adjust clamped: %f, range: +/-%f\n", valf, 24.0f);
            context->mGainBoost = std::pow(10.0f, db/20.0f);
            TRACE("volume-adjust gain: %f\n", context->mGainBoost);
        }
    }

    {
        using ContextArray = al::FlexArray<ContextBase*>;

        /* Allocate a new context array, which holds 1 more than the current/
         * old array.
         */
        auto *oldarray = device->mContexts.load();
        auto newarray = ContextArray::Create(oldarray->size() + 1);

        /* Copy the current/old context handles to the new array, appending the
         * new context.
         */
        auto iter = std::copy(oldarray->begin(), oldarray->end(), newarray->begin());
        *iter = context.get();

        /* Store the new context array in the device. Wait for any current mix
         * to finish before deleting the old array.
         */
        auto prevarray = dev->mContexts.exchange(std::move(newarray));
        std::ignore = dev->waitForMix();
    }
    statelock.unlock();

    {
        listlock.lock();
        auto iter = std::lower_bound(ContextList.cbegin(), ContextList.cend(), context.get());
        ContextList.emplace(iter, context.get());
        listlock.unlock();
    }

    if(ALeffectslot *slot{context->mDefaultSlot.get()})
    {
        ALenum sloterr{slot->initEffect(0, ALCcontext::sDefaultEffect.type,
            ALCcontext::sDefaultEffect.Props, context.get())};
        if(sloterr == AL_NO_ERROR)
            slot->updateProps(context.get());
        else
            ERR("Failed to initialize the default effect\n");
    }

    TRACE("Created context %p\n", voidp{context.get()});
    return context.release();
}

ALC_API void ALC_APIENTRY alcDestroyContext(ALCcontext *context) noexcept
{
    if(!gProcessRunning)
        return;

    std::unique_lock<std::recursive_mutex> listlock{ListLock};
    auto iter = std::lower_bound(ContextList.begin(), ContextList.end(), context);
    if(iter == ContextList.end() || *iter != context)
    {
        listlock.unlock();
        alcSetError(nullptr, ALC_INVALID_CONTEXT);
        return;
    }

    /* Hold a reference to this context so it remains valid until the ListLock
     * is released.
     */
    ContextRef ctx{*iter};
    ContextList.erase(iter);

    ALCdevice *Device{ctx->mALDevice.get()};

    std::lock_guard<std::mutex> statelock{Device->StateLock};
    ctx->deinit();
}


ALC_API auto ALC_APIENTRY alcGetCurrentContext() noexcept -> ALCcontext*
{
    ALCcontext *Context{ALCcontext::getThreadContext()};
    if(!Context) Context = ALCcontext::sGlobalContext.load();
    return Context;
}

/** Returns the currently active thread-local context. */
ALC_API auto ALC_APIENTRY alcGetThreadContext() noexcept -> ALCcontext*
{ return ALCcontext::getThreadContext(); }

ALC_API ALCboolean ALC_APIENTRY alcMakeContextCurrent(ALCcontext *context) noexcept
{
    /* context must be valid or nullptr */
    ContextRef ctx;
    if(context)
    {
        ctx = VerifyContext(context);
        if(!ctx)
        {
            alcSetError(nullptr, ALC_INVALID_CONTEXT);
            return ALC_FALSE;
        }
    }
    /* Release this reference (if any) to store it in the GlobalContext
     * pointer. Take ownership of the reference (if any) that was previously
     * stored there, and let the reference go.
     */
    while(ALCcontext::sGlobalContextLock.exchange(true, std::memory_order_acquire)) {
        /* Wait to make sure another thread isn't getting or trying to change
         * the current context as its refcount is decremented.
         */
    }
    ctx = ContextRef{ALCcontext::sGlobalContext.exchange(ctx.release())};
    ALCcontext::sGlobalContextLock.store(false, std::memory_order_release);

    /* Take ownership of the thread-local context reference (if any), clearing
     * the storage to null.
     */
    ctx = ContextRef{ALCcontext::getThreadContext()};
    if(ctx) ALCcontext::setThreadContext(nullptr);
    /* Reset (decrement) the previous thread-local reference. */

    return ALC_TRUE;
}

/** Makes the given context the active context for the current thread. */
ALC_API ALCboolean ALC_APIENTRY alcSetThreadContext(ALCcontext *context) noexcept
{
    /* context must be valid or nullptr */
    ContextRef ctx;
    if(context)
    {
        ctx = VerifyContext(context);
        if(!ctx)
        {
            alcSetError(nullptr, ALC_INVALID_CONTEXT);
            return ALC_FALSE;
        }
    }
    /* context's reference count is already incremented */
    ContextRef old{ALCcontext::getThreadContext()};
    ALCcontext::setThreadContext(ctx.release());

    return ALC_TRUE;
}


ALC_API ALCdevice* ALC_APIENTRY alcGetContextsDevice(ALCcontext *Context) noexcept
{
    ContextRef ctx{VerifyContext(Context)};
    if(!ctx)
    {
        alcSetError(nullptr, ALC_INVALID_CONTEXT);
        return nullptr;
    }
    return ctx->mALDevice.get();
}


ALC_API ALCdevice* ALC_APIENTRY alcOpenDevice(const ALCchar *deviceName) noexcept
{
    InitConfig();

    if(!PlaybackFactory)
    {
        alcSetError(nullptr, ALC_INVALID_VALUE);
        return nullptr;
    }

    std::string_view devname{deviceName ? deviceName : ""};
    if(!devname.empty())
    {
        TRACE("Opening playback device \"%.*s\"\n", al::sizei(devname), devname.data());
        if(al::case_compare(devname, GetDefaultName()) == 0
#ifdef _WIN32
            /* Some old Windows apps hardcode these expecting OpenAL to use a
             * specific audio API, even when they're not enumerated. Creative's
             * router effectively ignores them too.
             */
            || al::case_compare(devname, "DirectSound3D"sv) == 0
            || al::case_compare(devname, "DirectSound"sv) == 0
            || al::case_compare(devname, "MMSYSTEM"sv) == 0
#endif
            /* Some old Linux apps hardcode configuration strings that were
             * supported by the OpenAL SI. We can't really do anything useful
             * with them, so just ignore.
             */
            || al::starts_with(devname, "'("sv)
            || al::case_compare(devname, "openal-soft"sv) == 0)
            devname = {};
        else
        {
            const auto prefix = GetDevicePrefix();
            if(!prefix.empty() && devname.size() > prefix.size()
                && al::starts_with(devname, prefix))
                devname = devname.substr(prefix.size());
        }
    }
    else
        TRACE("Opening default playback device\n");

    const uint DefaultSends{
#if ALSOFT_EAX
        eax_g_is_enabled ? uint{EAX_MAX_FXSLOTS} :
#endif // ALSOFT_EAX
        uint{DefaultSendCount}
    };

    DeviceRef device{new(std::nothrow) ALCdevice{DeviceType::Playback}};
    if(!device)
    {
        WARN("Failed to create playback device handle\n");
        alcSetError(nullptr, ALC_OUT_OF_MEMORY);
        return nullptr;
    }

    /* Set output format */
    device->FmtChans = DevFmtChannelsDefault;
    device->FmtType = DevFmtTypeDefault;
    device->Frequency = DefaultOutputRate;
    device->UpdateSize = DefaultUpdateSize;
    device->BufferSize = DefaultUpdateSize * DefaultNumUpdates;

    device->SourcesMax = 256;
    device->NumStereoSources = 1;
    device->NumMonoSources = device->SourcesMax - device->NumStereoSources;
    device->AuxiliaryEffectSlotMax = 64;
    device->NumAuxSends = DefaultSends;

    try {
        auto backend = PlaybackFactory->createBackend(device.get(), BackendType::Playback);
        std::lock_guard<std::recursive_mutex> listlock{ListLock};
        backend->open(devname);
        device->mDeviceName = std::string{GetDevicePrefix()}+backend->mDeviceName;
        device->Backend = std::move(backend);
    }
    catch(al::backend_exception &e) {
        WARN("Failed to open playback device: %s\n", e.what());
        alcSetError(nullptr, (e.errorCode() == al::backend_error::OutOfMemory)
            ? ALC_OUT_OF_MEMORY : ALC_INVALID_VALUE);
        return nullptr;
    }

    auto checkopt = [&device](const char *envname, const std::string_view optname)
    {
        if(auto optval = al::getenv(envname)) return optval;
        return device->configValue<std::string>("game_compat", optname);
    };
    if(auto overrideopt = checkopt("__ALSOFT_VENDOR_OVERRIDE", "vendor-override"sv))
    {
        device->mVendorOverride = std::move(*overrideopt);
        TRACE("Overriding vendor string: \"%s\"\n", device->mVendorOverride.c_str());
    }
    if(auto overrideopt = checkopt("__ALSOFT_VERSION_OVERRIDE", "version-override"sv))
    {
        device->mVersionOverride = std::move(*overrideopt);
        TRACE("Overriding version string: \"%s\"\n", device->mVersionOverride.c_str());
    }
    if(auto overrideopt = checkopt("__ALSOFT_RENDERER_OVERRIDE", "renderer-override"sv))
    {
        device->mRendererOverride = std::move(*overrideopt);
        TRACE("Overriding renderer string: \"%s\"\n", device->mRendererOverride.c_str());
    }

    {
        std::lock_guard<std::recursive_mutex> listlock{ListLock};
        auto iter = std::lower_bound(DeviceList.cbegin(), DeviceList.cend(), device.get());
        DeviceList.emplace(iter, device.get());
    }

    TRACE("Created device %p, \"%s\"\n", voidp{device.get()}, device->mDeviceName.c_str());
    return device.release();
}

ALC_API ALCboolean ALC_APIENTRY alcCloseDevice(ALCdevice *device) noexcept
{
    if(!gProcessRunning)
        return ALC_FALSE;

    std::unique_lock<std::recursive_mutex> listlock{ListLock};
    auto iter = std::lower_bound(DeviceList.begin(), DeviceList.end(), device);
    if(iter == DeviceList.end() || *iter != device)
    {
        alcSetError(nullptr, ALC_INVALID_DEVICE);
        return ALC_FALSE;
    }
    if((*iter)->Type == DeviceType::Capture)
    {
        alcSetError(*iter, ALC_INVALID_DEVICE);
        return ALC_FALSE;
    }

    /* Erase the device, and any remaining contexts left on it, from their
     * respective lists.
     */
    DeviceRef dev{*iter};
    DeviceList.erase(iter);

    std::unique_lock<std::mutex> statelock{dev->StateLock};
    std::vector<ContextRef> orphanctxs;
    for(ContextBase *ctx : *dev->mContexts.load())
    {
        auto ctxiter = std::lower_bound(ContextList.begin(), ContextList.end(), ctx);
        if(ctxiter != ContextList.end() && *ctxiter == ctx)
        {
            orphanctxs.emplace_back(*ctxiter);
            ContextList.erase(ctxiter);
        }
    }
    listlock.unlock();

    for(ContextRef &context : orphanctxs)
    {
        WARN("Releasing orphaned context %p\n", voidp{context.get()});
        context->deinit();
    }
    orphanctxs.clear();

    if(dev->mDeviceState == DeviceState::Playing)
    {
        dev->Backend->stop();
        dev->mDeviceState = DeviceState::Configured;
    }

    return ALC_TRUE;
}


/************************************************
 * ALC capture functions
 ************************************************/
ALC_API ALCdevice* ALC_APIENTRY alcCaptureOpenDevice(const ALCchar *deviceName, ALCuint frequency, ALCenum format, ALCsizei samples) noexcept
{
    InitConfig();

    if(!CaptureFactory)
    {
        alcSetError(nullptr, ALC_INVALID_VALUE);
        return nullptr;
    }

    if(samples <= 0)
    {
        alcSetError(nullptr, ALC_INVALID_VALUE);
        return nullptr;
    }

    std::string_view devname{deviceName ? deviceName : ""};
    if(!devname.empty())
    {
        TRACE("Opening capture device \"%.*s\"\n", al::sizei(devname), devname.data());
        if(al::case_compare(devname, GetDefaultName()) == 0
            || al::case_compare(devname, "openal-soft"sv) == 0)
            devname = {};
        else
        {
            const auto prefix = GetDevicePrefix();
            if(!prefix.empty() && devname.size() > prefix.size()
                && al::starts_with(devname, prefix))
                devname = devname.substr(prefix.size());
        }
    }
    else
        TRACE("Opening default capture device\n");

    DeviceRef device{new(std::nothrow) ALCdevice{DeviceType::Capture}};
    if(!device)
    {
        WARN("Failed to create capture device handle\n");
        alcSetError(nullptr, ALC_OUT_OF_MEMORY);
        return nullptr;
    }

    auto decompfmt = DecomposeDevFormat(format);
    if(!decompfmt)
    {
        alcSetError(nullptr, ALC_INVALID_ENUM);
        return nullptr;
    }

    device->Frequency = frequency;
    device->FmtChans = decompfmt->chans;
    device->FmtType = decompfmt->type;
    device->Flags.set(FrequencyRequest);
    device->Flags.set(ChannelsRequest);
    device->Flags.set(SampleTypeRequest);

    device->UpdateSize = static_cast<uint>(samples);
    device->BufferSize = static_cast<uint>(samples);

    TRACE("Capture format: %s, %s, %uhz, %u / %u buffer\n", DevFmtChannelsString(device->FmtChans),
        DevFmtTypeString(device->FmtType), device->Frequency, device->UpdateSize,
        device->BufferSize);

    try {
        auto backend = CaptureFactory->createBackend(device.get(), BackendType::Capture);
        std::lock_guard<std::recursive_mutex> listlock{ListLock};
        backend->open(devname);
        device->mDeviceName = std::string{GetDevicePrefix()}+backend->mDeviceName;
        device->Backend = std::move(backend);
    }
    catch(al::backend_exception &e) {
        WARN("Failed to open capture device: %s\n", e.what());
        alcSetError(nullptr, (e.errorCode() == al::backend_error::OutOfMemory)
            ? ALC_OUT_OF_MEMORY : ALC_INVALID_VALUE);
        return nullptr;
    }

    {
        std::lock_guard<std::recursive_mutex> listlock{ListLock};
        auto iter = std::lower_bound(DeviceList.cbegin(), DeviceList.cend(), device.get());
        DeviceList.emplace(iter, device.get());
    }
    device->mDeviceState = DeviceState::Configured;

    TRACE("Created capture device %p, \"%s\"\n", voidp{device.get()}, device->mDeviceName.c_str());
    return device.release();
}

ALC_API ALCboolean ALC_APIENTRY alcCaptureCloseDevice(ALCdevice *device) noexcept
{
    if(!gProcessRunning)
        return ALC_FALSE;

    std::unique_lock<std::recursive_mutex> listlock{ListLock};
    auto iter = std::lower_bound(DeviceList.begin(), DeviceList.end(), device);
    if(iter == DeviceList.end() || *iter != device)
    {
        alcSetError(nullptr, ALC_INVALID_DEVICE);
        return ALC_FALSE;
    }
    if((*iter)->Type != DeviceType::Capture)
    {
        alcSetError(*iter, ALC_INVALID_DEVICE);
        return ALC_FALSE;
    }

    DeviceRef dev{*iter};
    DeviceList.erase(iter);
    listlock.unlock();

    std::lock_guard<std::mutex> statelock{dev->StateLock};
    if(dev->mDeviceState == DeviceState::Playing)
    {
        dev->Backend->stop();
        dev->mDeviceState = DeviceState::Configured;
    }

    return ALC_TRUE;
}

ALC_API void ALC_APIENTRY alcCaptureStart(ALCdevice *device) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type != DeviceType::Capture)
    {
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
        return;
    }

    std::lock_guard<std::mutex> statelock{dev->StateLock};
    if(!dev->Connected.load(std::memory_order_acquire)
        || dev->mDeviceState < DeviceState::Configured)
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
    else if(dev->mDeviceState != DeviceState::Playing)
    {
        try {
            auto backend = dev->Backend.get();
            backend->start();
            dev->mDeviceState = DeviceState::Playing;
        }
        catch(al::backend_exception& e) {
            ERR("%s\n", e.what());
            dev->handleDisconnect("%s", e.what());
            alcSetError(dev.get(), ALC_INVALID_DEVICE);
        }
    }
}

ALC_API void ALC_APIENTRY alcCaptureStop(ALCdevice *device) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type != DeviceType::Capture)
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
    else
    {
        std::lock_guard<std::mutex> statelock{dev->StateLock};
        if(dev->mDeviceState == DeviceState::Playing)
        {
            dev->Backend->stop();
            dev->mDeviceState = DeviceState::Configured;
        }
    }
}

ALC_API void ALC_APIENTRY alcCaptureSamples(ALCdevice *device, ALCvoid *buffer, ALCsizei samples) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type != DeviceType::Capture)
    {
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
        return;
    }

    if(samples < 0 || (samples > 0 && buffer == nullptr))
    {
        alcSetError(dev.get(), ALC_INVALID_VALUE);
        return;
    }
    if(samples < 1)
        return;

    std::lock_guard<std::mutex> statelock{dev->StateLock};
    BackendBase *backend{dev->Backend.get()};

    const auto usamples = static_cast<uint>(samples);
    if(usamples > backend->availableSamples())
    {
        alcSetError(dev.get(), ALC_INVALID_VALUE);
        return;
    }

    backend->captureSamples(static_cast<std::byte*>(buffer), usamples);
}


/************************************************
 * ALC loopback functions
 ************************************************/

/** Open a loopback device, for manual rendering. */
ALC_API ALCdevice* ALC_APIENTRY alcLoopbackOpenDeviceSOFT(const ALCchar *deviceName) noexcept
{
    InitConfig();

    /* Make sure the device name, if specified, is us. */
    if(deviceName && strcmp(deviceName, GetDefaultName()) != 0)
    {
        alcSetError(nullptr, ALC_INVALID_VALUE);
        return nullptr;
    }

    const uint DefaultSends{
#if ALSOFT_EAX
        eax_g_is_enabled ? uint{EAX_MAX_FXSLOTS} :
#endif // ALSOFT_EAX
        uint{DefaultSendCount}
    };

    DeviceRef device{new(std::nothrow) ALCdevice{DeviceType::Loopback}};
    if(!device)
    {
        WARN("Failed to create loopback device handle\n");
        alcSetError(nullptr, ALC_OUT_OF_MEMORY);
        return nullptr;
    }

    device->SourcesMax = 256;
    device->AuxiliaryEffectSlotMax = 64;
    device->NumAuxSends = DefaultSends;

    //Set output format
    device->BufferSize = 0;
    device->UpdateSize = 0;

    device->Frequency = DefaultOutputRate;
    device->FmtChans = DevFmtChannelsDefault;
    device->FmtType = DevFmtTypeDefault;

    device->NumStereoSources = 1;
    device->NumMonoSources = device->SourcesMax - device->NumStereoSources;

    try {
        auto backend = LoopbackBackendFactory::getFactory().createBackend(device.get(),
            BackendType::Playback);
        backend->open("Loopback");
        device->mDeviceName = std::string{GetDevicePrefix()}+backend->mDeviceName;
        device->Backend = std::move(backend);
    }
    catch(al::backend_exception &e) {
        WARN("Failed to open loopback device: %s\n", e.what());
        alcSetError(nullptr, (e.errorCode() == al::backend_error::OutOfMemory)
            ? ALC_OUT_OF_MEMORY : ALC_INVALID_VALUE);
        return nullptr;
    }

    {
        std::lock_guard<std::recursive_mutex> listlock{ListLock};
        auto iter = std::lower_bound(DeviceList.cbegin(), DeviceList.cend(), device.get());
        DeviceList.emplace(iter, device.get());
    }

    TRACE("Created loopback device %p\n", voidp{device.get()});
    return device.release();
}

/**
 * Determines if the loopback device supports the given format for rendering.
 */
ALC_API ALCboolean ALC_APIENTRY alcIsRenderFormatSupportedSOFT(ALCdevice *device, ALCsizei freq, ALCenum channels, ALCenum type) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type != DeviceType::Loopback)
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
    else if(freq <= 0)
        alcSetError(dev.get(), ALC_INVALID_VALUE);
    else
    {
        if(DevFmtTypeFromEnum(type).has_value() && DevFmtChannelsFromEnum(channels).has_value()
            && freq >= int{MinOutputRate} && freq <= int{MaxOutputRate})
            return ALC_TRUE;
    }

    return ALC_FALSE;
}

/**
 * Renders some samples into a buffer, using the format last set by the
 * attributes given to alcCreateContext.
 */
#if defined(__GNUC__) && defined(__i386__)
/* Needed on x86-32 even without SSE codegen, since the mixer may still use SSE
 * and GCC assumes the stack is aligned (x86-64 ABI guarantees alignment).
 */
[[gnu::force_align_arg_pointer]]
#endif
ALC_API void ALC_APIENTRY alcRenderSamplesSOFT(ALCdevice *device, ALCvoid *buffer, ALCsizei samples) noexcept
{
    if(!device || device->Type != DeviceType::Loopback) UNLIKELY
        alcSetError(device, ALC_INVALID_DEVICE);
    else if(samples < 0 || (samples > 0 && buffer == nullptr)) UNLIKELY
        alcSetError(device, ALC_INVALID_VALUE);
    else
        device->renderSamples(buffer, static_cast<uint>(samples), device->channelsFromFmt());
}


/************************************************
 * ALC DSP pause/resume functions
 ************************************************/

/** Pause the DSP to stop audio processing. */
ALC_API void ALC_APIENTRY alcDevicePauseSOFT(ALCdevice *device) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type != DeviceType::Playback)
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
    else
    {
        std::lock_guard<std::mutex> statelock{dev->StateLock};
        if(dev->mDeviceState == DeviceState::Playing)
        {
            dev->Backend->stop();
            dev->mDeviceState = DeviceState::Configured;
        }
        dev->Flags.set(DevicePaused);
    }
}

/** Resume the DSP to restart audio processing. */
ALC_API void ALC_APIENTRY alcDeviceResumeSOFT(ALCdevice *device) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type != DeviceType::Playback)
    {
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
        return;
    }

    std::lock_guard<std::mutex> statelock{dev->StateLock};
    if(!dev->Flags.test(DevicePaused))
        return;
    if(dev->mDeviceState < DeviceState::Configured)
    {
        WARN("Cannot resume unconfigured device\n");
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
        return;
    }
    if(!dev->Connected.load())
    {
        WARN("Cannot resume a disconnected device\n");
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
        return;
    }
    dev->Flags.reset(DevicePaused);
    if(dev->mContexts.load()->empty())
        return;

    try {
        auto backend = dev->Backend.get();
        backend->start();
        dev->mDeviceState = DeviceState::Playing;
    }
    catch(al::backend_exception& e) {
        ERR("%s\n", e.what());
        dev->handleDisconnect("%s", e.what());
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
        return;
    }
    TRACE("Post-resume: %s, %s, %uhz, %u / %u buffer\n",
        DevFmtChannelsString(dev->FmtChans), DevFmtTypeString(dev->FmtType),
        dev->Frequency, dev->UpdateSize, dev->BufferSize);
}


/************************************************
 * ALC HRTF functions
 ************************************************/

/** Gets a string parameter at the given index. */
ALC_API const ALCchar* ALC_APIENTRY alcGetStringiSOFT(ALCdevice *device, ALCenum paramName, ALCsizei index) noexcept
{
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type == DeviceType::Capture)
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
    else switch(paramName)
    {
        case ALC_HRTF_SPECIFIER_SOFT:
            if(index >= 0 && static_cast<uint>(index) < dev->mHrtfList.size())
                return dev->mHrtfList[static_cast<uint>(index)].c_str();
            alcSetError(dev.get(), ALC_INVALID_VALUE);
            break;

        default:
            alcSetError(dev.get(), ALC_INVALID_ENUM);
            break;
    }

    return nullptr;
}

/** Resets the given device output, using the specified attribute list. */
ALC_API ALCboolean ALC_APIENTRY alcResetDeviceSOFT(ALCdevice *device, const ALCint *attribs) noexcept
{
    std::unique_lock<std::recursive_mutex> listlock{ListLock};
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type == DeviceType::Capture)
    {
        listlock.unlock();
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
        return ALC_FALSE;
    }
    std::lock_guard<std::mutex> statelock{dev->StateLock};
    listlock.unlock();

    /* Force the backend to stop mixing first since we're resetting. Also reset
     * the connected state so lost devices can attempt recover.
     */
    if(dev->mDeviceState == DeviceState::Playing)
    {
        dev->Backend->stop();
        dev->mDeviceState = DeviceState::Configured;
    }

    return ResetDeviceParams(dev.get(), SpanFromAttributeList(attribs)) ? ALC_TRUE : ALC_FALSE;
}


/************************************************
 * ALC device reopen functions
 ************************************************/

/** Reopens the given device output, using the specified name and attribute list. */
FORCE_ALIGN ALCboolean ALC_APIENTRY alcReopenDeviceSOFT(ALCdevice *device,
    const ALCchar *deviceName, const ALCint *attribs) noexcept
{
    std::unique_lock<std::recursive_mutex> listlock{ListLock};
    DeviceRef dev{VerifyDevice(device)};
    if(!dev || dev->Type != DeviceType::Playback)
    {
        listlock.unlock();
        alcSetError(dev.get(), ALC_INVALID_DEVICE);
        return ALC_FALSE;
    }
    std::lock_guard<std::mutex> statelock{dev->StateLock};

    std::string_view devname{deviceName ? deviceName : ""};
    if(!devname.empty())
    {
        if(devname.length() >= size_t{std::numeric_limits<int>::max()})
        {
            ERR("Device name too long (%zu >= %d)\n", devname.length(),
                std::numeric_limits<int>::max());
            alcSetError(dev.get(), ALC_INVALID_VALUE);
            return ALC_FALSE;
        }
        if(al::case_compare(devname, GetDefaultName()) == 0)
            devname = {};
        else
        {
            const auto prefix = GetDevicePrefix();
            if(!prefix.empty() && devname.size() > prefix.size()
                && al::starts_with(devname, prefix))
                devname = devname.substr(prefix.size());
        }
    }

    /* Force the backend device to stop first since we're opening another one. */
    const bool wasPlaying{dev->mDeviceState == DeviceState::Playing};
    if(wasPlaying)
    {
        dev->Backend->stop();
        dev->mDeviceState = DeviceState::Configured;
    }

    BackendPtr newbackend;
    try {
        newbackend = PlaybackFactory->createBackend(dev.get(), BackendType::Playback);
        newbackend->open(devname);
    }
    catch(al::backend_exception &e) {
        listlock.unlock();
        newbackend = nullptr;

        WARN("Failed to reopen playback device: %s\n", e.what());
        alcSetError(dev.get(), (e.errorCode() == al::backend_error::OutOfMemory)
            ? ALC_OUT_OF_MEMORY : ALC_INVALID_VALUE);

        if(dev->Connected.load(std::memory_order_relaxed) && wasPlaying)
        {
            try {
                auto backend = dev->Backend.get();
                backend->start();
                dev->mDeviceState = DeviceState::Playing;
            }
            catch(al::backend_exception &be) {
                ERR("%s\n", be.what());
                dev->handleDisconnect("%s", be.what());
            }
        }
        return ALC_FALSE;
    }
    listlock.unlock();
    dev->mDeviceName = std::string{GetDevicePrefix()}+newbackend->mDeviceName;
    dev->Backend = std::move(newbackend);
    dev->mDeviceState = DeviceState::Unprepared;
    TRACE("Reopened device %p, \"%s\"\n", voidp{dev.get()}, dev->mDeviceName.c_str());

    std::string{}.swap(dev->mVendorOverride);
    std::string{}.swap(dev->mVersionOverride);
    std::string{}.swap(dev->mRendererOverride);
    auto checkopt = [&dev](const char *envname, const std::string_view optname)
    {
        if(auto optval = al::getenv(envname)) return optval;
        return dev->configValue<std::string>("game_compat", optname);
    };
    if(auto overrideopt = checkopt("__ALSOFT_VENDOR_OVERRIDE", "vendor-override"sv))
    {
        dev->mVendorOverride = std::move(*overrideopt);
        TRACE("Overriding vendor string: \"%s\"\n", dev->mVendorOverride.c_str());
    }
    if(auto overrideopt = checkopt("__ALSOFT_VERSION_OVERRIDE", "version-override"sv))
    {
        dev->mVersionOverride = std::move(*overrideopt);
        TRACE("Overriding version string: \"%s\"\n", dev->mVersionOverride.c_str());
    }
    if(auto overrideopt = checkopt("__ALSOFT_RENDERER_OVERRIDE", "renderer-override"sv))
    {
        dev->mRendererOverride = std::move(*overrideopt);
        TRACE("Overriding renderer string: \"%s\"\n", dev->mRendererOverride.c_str());
    }

    /* Always return true even if resetting fails. It shouldn't fail, but this
     * is primarily to avoid confusion by the app seeing the function return
     * false while the device is on the new output anyway. We could try to
     * restore the old backend if this fails, but the configuration would be
     * changed with the new backend and would need to be reset again with the
     * old one, and the provided attributes may not be appropriate or desirable
     * for the old device.
     *
     * In this way, we essentially act as if the function succeeded, but
     * immediately disconnects following it.
     */
    ResetDeviceParams(dev.get(), SpanFromAttributeList(attribs));
    return ALC_TRUE;
}

/************************************************
 * ALC event query functions
 ************************************************/

FORCE_ALIGN ALCenum ALC_APIENTRY alcEventIsSupportedSOFT(ALCenum eventType, ALCenum deviceType) noexcept
{
    auto etype = alc::GetEventType(eventType);
    if(!etype)
    {
        WARN("Invalid event type: 0x%04x\n", eventType);
        alcSetError(nullptr, ALC_INVALID_ENUM);
        return ALC_FALSE;
    }

    auto supported = alc::EventSupport::NoSupport;
    switch(deviceType)
    {
    case ALC_PLAYBACK_DEVICE_SOFT:
        if(PlaybackFactory)
            supported = PlaybackFactory->queryEventSupport(*etype, BackendType::Playback);
        return al::to_underlying(supported);

    case ALC_CAPTURE_DEVICE_SOFT:
        if(CaptureFactory)
            supported = CaptureFactory->queryEventSupport(*etype, BackendType::Capture);
        return al::to_underlying(supported);
    }
    WARN("Invalid device type: 0x%04x\n", deviceType);
    alcSetError(nullptr, ALC_INVALID_ENUM);
    return ALC_FALSE;
}
