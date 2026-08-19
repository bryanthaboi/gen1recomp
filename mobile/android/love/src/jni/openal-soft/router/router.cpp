
#include "config.h"

#include "router.h"

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

#include "AL/alc.h"
#include "AL/al.h"

#include "albit.h"
#include "alstring.h"
#include "opthelpers.h"
#include "strutils.h"

#include "version.h"


eLogLevel LogLevel{eLogLevel::Error};
gsl::owner<std::FILE*> LogFile;

namespace {

std::vector<std::wstring> gAcceptList;
std::vector<std::wstring> gRejectList;


void AddModule(HMODULE module, const std::wstring_view name)
{
    for(auto &drv : DriverList)
    {
        if(drv->Module == module)
        {
            TRACE("Skipping already-loaded module %p\n", decltype(std::declval<void*>()){module});
            FreeLibrary(module);
            return;
        }
        if(drv->Name == name)
        {
            TRACE("Skipping similarly-named module %.*ls\n", al::sizei(name), name.data());
            FreeLibrary(module);
            return;
        }
    }
    if(!gAcceptList.empty())
    {
        auto iter = std::find_if(gAcceptList.cbegin(), gAcceptList.cend(),
            [name](const std::wstring_view accept)
            { return al::case_compare(name, accept) == 0; });
        if(iter == gAcceptList.cend())
        {
            TRACE("%.*ls not found in ALROUTER_ACCEPT, skipping\n", al::sizei(name), name.data());
            FreeLibrary(module);
            return;
        }
    }
    if(!gRejectList.empty())
    {
        auto iter = std::find_if(gRejectList.cbegin(), gRejectList.cend(),
            [name](const std::wstring_view accept)
            { return al::case_compare(name, accept) == 0; });
        if(iter != gRejectList.cend())
        {
            TRACE("%.*ls found in ALROUTER_REJECT, skipping\n", al::sizei(name), name.data());
            FreeLibrary(module);
            return;
        }
    }

    DriverIface &newdrv = *DriverList.emplace_back(std::make_unique<DriverIface>(name, module));

    /* Load required functions. */
    bool loadok{true};
    auto do_load = [module,name](auto &func, const char *fname) -> bool
    {
        using func_t = std::remove_reference_t<decltype(func)>;
        auto ptr = GetProcAddress(module, fname);
        if(!ptr)
        {
            ERR("Failed to find entry point for %s in %.*ls\n", fname, al::sizei(name),
                name.data());
            return false;
        }

        func = al::bit_cast<func_t>(ptr);
        return true;
    };
#define LOAD_PROC(x) loadok &= do_load(newdrv.x, #x)
    LOAD_PROC(alcCreateContext);
    LOAD_PROC(alcMakeContextCurrent);
    LOAD_PROC(alcProcessContext);
    LOAD_PROC(alcSuspendContext);
    LOAD_PROC(alcDestroyContext);
    LOAD_PROC(alcGetCurrentContext);
    LOAD_PROC(alcGetContextsDevice);
    LOAD_PROC(alcOpenDevice);
    LOAD_PROC(alcCloseDevice);
    LOAD_PROC(alcGetError);
    LOAD_PROC(alcIsExtensionPresent);
    LOAD_PROC(alcGetProcAddress);
    LOAD_PROC(alcGetEnumValue);
    LOAD_PROC(alcGetString);
    LOAD_PROC(alcGetIntegerv);
    LOAD_PROC(alcCaptureOpenDevice);
    LOAD_PROC(alcCaptureCloseDevice);
    LOAD_PROC(alcCaptureStart);
    LOAD_PROC(alcCaptureStop);
    LOAD_PROC(alcCaptureSamples);

    LOAD_PROC(alEnable);
    LOAD_PROC(alDisable);
    LOAD_PROC(alIsEnabled);
    LOAD_PROC(alGetString);
    LOAD_PROC(alGetBooleanv);
    LOAD_PROC(alGetIntegerv);
    LOAD_PROC(alGetFloatv);
    LOAD_PROC(alGetDoublev);
    LOAD_PROC(alGetBoolean);
    LOAD_PROC(alGetInteger);
    LOAD_PROC(alGetFloat);
    LOAD_PROC(alGetDouble);
    LOAD_PROC(alGetError);
    LOAD_PROC(alIsExtensionPresent);
    LOAD_PROC(alGetProcAddress);
    LOAD_PROC(alGetEnumValue);
    LOAD_PROC(alListenerf);
    LOAD_PROC(alListener3f);
    LOAD_PROC(alListenerfv);
    LOAD_PROC(alListeneri);
    LOAD_PROC(alListener3i);
    LOAD_PROC(alListeneriv);
    LOAD_PROC(alGetListenerf);
    LOAD_PROC(alGetListener3f);
    LOAD_PROC(alGetListenerfv);
    LOAD_PROC(alGetListeneri);
    LOAD_PROC(alGetListener3i);
    LOAD_PROC(alGetListeneriv);
    LOAD_PROC(alGenSources);
    LOAD_PROC(alDeleteSources);
    LOAD_PROC(alIsSource);
    LOAD_PROC(alSourcef);
    LOAD_PROC(alSource3f);
    LOAD_PROC(alSourcefv);
    LOAD_PROC(alSourcei);
    LOAD_PROC(alSource3i);
    LOAD_PROC(alSourceiv);
    LOAD_PROC(alGetSourcef);
    LOAD_PROC(alGetSource3f);
    LOAD_PROC(alGetSourcefv);
    LOAD_PROC(alGetSourcei);
    LOAD_PROC(alGetSource3i);
    LOAD_PROC(alGetSourceiv);
    LOAD_PROC(alSourcePlayv);
    LOAD_PROC(alSourceStopv);
    LOAD_PROC(alSourceRewindv);
    LOAD_PROC(alSourcePausev);
    LOAD_PROC(alSourcePlay);
    LOAD_PROC(alSourceStop);
    LOAD_PROC(alSourceRewind);
    LOAD_PROC(alSourcePause);
    LOAD_PROC(alSourceQueueBuffers);
    LOAD_PROC(alSourceUnqueueBuffers);
    LOAD_PROC(alGenBuffers);
    LOAD_PROC(alDeleteBuffers);
    LOAD_PROC(alIsBuffer);
    LOAD_PROC(alBufferData);
    LOAD_PROC(alDopplerFactor);
    LOAD_PROC(alDopplerVelocity);
    LOAD_PROC(alSpeedOfSound);
    LOAD_PROC(alDistanceModel);
#undef LOAD_PROC
    if(loadok)
    {
        std::array<ALCint,2> alc_ver{0, 0};
        newdrv.alcGetIntegerv(nullptr, ALC_MAJOR_VERSION, 1, &alc_ver[0]);
        newdrv.alcGetIntegerv(nullptr, ALC_MINOR_VERSION, 1, &alc_ver[1]);
        if(newdrv.alcGetError(nullptr) == ALC_NO_ERROR)
            newdrv.ALCVer = MAKE_ALC_VER(alc_ver[0], alc_ver[1]);
        else
        {
            WARN("Failed to query ALC version for %.*ls, assuming 1.0\n", al::sizei(name),
                name.data());
            newdrv.ALCVer = MAKE_ALC_VER(1, 0);
        }

        auto do_load2 = [module,name](auto &func, const char *fname) -> void
        {
            using func_t = std::remove_reference_t<decltype(func)>;
            auto ptr = GetProcAddress(module, fname);
            if(!ptr)
                WARN("Failed to find optional entry point for %s in %.*ls\n", fname,
                    al::sizei(name), name.data());
            else
                func = al::bit_cast<func_t>(ptr);
        };
#define LOAD_PROC(x) do_load2(newdrv.x, #x)
        LOAD_PROC(alBufferf);
        LOAD_PROC(alBuffer3f);
        LOAD_PROC(alBufferfv);
        LOAD_PROC(alBufferi);
        LOAD_PROC(alBuffer3i);
        LOAD_PROC(alBufferiv);
        LOAD_PROC(alGetBufferf);
        LOAD_PROC(alGetBuffer3f);
        LOAD_PROC(alGetBufferfv);
        LOAD_PROC(alGetBufferi);
        LOAD_PROC(alGetBuffer3i);
        LOAD_PROC(alGetBufferiv);
#undef LOAD_PROC

        auto do_load3 = [name,&newdrv](auto &func, const char *fname) -> bool
        {
            using func_t = std::remove_reference_t<decltype(func)>;
            auto ptr = newdrv.alcGetProcAddress(nullptr, fname);
            if(!ptr)
            {
                ERR("Failed to find entry point for %s in %.*ls\n", fname, al::sizei(name),
                    name.data());
                return false;
            }

            func = reinterpret_cast<func_t>(ptr);
            return true;
        };
#define LOAD_PROC(x) loadok &= do_load3(newdrv.x, #x)
        if(newdrv.alcIsExtensionPresent(nullptr, "ALC_EXT_thread_local_context"))
        {
            LOAD_PROC(alcSetThreadContext);
            LOAD_PROC(alcGetThreadContext);
        }
#undef LOAD_PROC
    }

    if(!loadok)
    {
        DriverList.pop_back();
        return;
    }
    TRACE("Loaded module %p, %.*ls, ALC %d.%d\n", decltype(std::declval<void*>()){module},
        al::sizei(name), name.data(), newdrv.ALCVer>>8, newdrv.ALCVer&255);
}

void SearchDrivers(const std::wstring_view path)
{
    TRACE("Searching for drivers in %.*ls...\n", al::sizei(path), path.data());
    std::wstring srchPath{path};
    srchPath += L"\\*oal.dll";

    WIN32_FIND_DATAW fdata{};
    HANDLE srchHdl{FindFirstFileW(srchPath.c_str(), &fdata)};
    if(srchHdl == INVALID_HANDLE_VALUE) return;

    do {
        srchPath = path;
        srchPath += L"\\";
        srchPath += std::data(fdata.cFileName);
        TRACE("Found %ls\n", srchPath.c_str());

        HMODULE mod{LoadLibraryW(srchPath.c_str())};
        if(!mod)
            WARN("Could not load %ls\n", srchPath.c_str());
        else
            AddModule(mod, std::data(fdata.cFileName));
    } while(FindNextFileW(srchHdl, &fdata));
    FindClose(srchHdl);
}

bool GetLoadedModuleDirectory(const WCHAR *name, std::wstring *moddir)
{
    HMODULE module{nullptr};

    if(name)
    {
        module = GetModuleHandleW(name);
        if(!module) return false;
    }

    moddir->assign(256, '\0');
    DWORD res{GetModuleFileNameW(module, moddir->data(), static_cast<DWORD>(moddir->size()))};
    if(res >= moddir->size())
    {
        do {
            moddir->append(256, '\0');
            res = GetModuleFileNameW(module, moddir->data(), static_cast<DWORD>(moddir->size()));
        } while(res >= moddir->size());
    }
    moddir->resize(res);

    auto sep0 = moddir->rfind('/');
    auto sep1 = moddir->rfind('\\');
    if(sep0 < moddir->size() && sep1 < moddir->size())
        moddir->resize(std::max(sep0, sep1));
    else if(sep0 < moddir->size())
        moddir->resize(sep0);
    else if(sep1 < moddir->size())
        moddir->resize(sep1);
    else
        moddir->resize(0);

    return !moddir->empty();
}

void LoadDriverList()
{
    if(auto list = al::getenv(L"ALROUTER_ACCEPT"))
    {
        std::wstring_view namelist{*list};
        while(!namelist.empty())
        {
            auto seppos = namelist.find(',');
            if(seppos > 0)
                gAcceptList.emplace_back(namelist.substr(0, seppos));
            if(seppos < namelist.size())
                namelist.remove_prefix(seppos+1);
            else
                namelist.remove_prefix(namelist.size());
        }
    }
    if(auto list = al::getenv(L"ALROUTER_REJECT"))
    {
        std::wstring_view namelist{*list};
        while(!namelist.empty())
        {
            auto seppos = namelist.find(',');
            if(seppos > 0)
                gRejectList.emplace_back(namelist.substr(0, seppos));
            if(seppos < namelist.size())
                namelist.remove_prefix(seppos+1);
            else
                namelist.remove_prefix(namelist.size());
        }
    }

    std::wstring dll_path;
    if(GetLoadedModuleDirectory(L"OpenAL32.dll", &dll_path))
        TRACE("Got DLL path %ls\n", dll_path.c_str());

    std::wstring cwd_path;
    if(DWORD pathlen{GetCurrentDirectoryW(0, nullptr)})
    {
        do {
            cwd_path.resize(pathlen);
            pathlen = GetCurrentDirectoryW(pathlen, cwd_path.data());
        } while(pathlen >= cwd_path.size());
        cwd_path.resize(pathlen);
    }
    if(!cwd_path.empty() && (cwd_path.back() == '\\' || cwd_path.back() == '/'))
        cwd_path.pop_back();
    if(!cwd_path.empty())
        TRACE("Got current working directory %ls\n", cwd_path.c_str());

    std::wstring proc_path;
    if(GetLoadedModuleDirectory(nullptr, &proc_path))
        TRACE("Got proc path %ls\n", proc_path.c_str());

    std::wstring sys_path;
    if(UINT pathlen{GetSystemDirectoryW(nullptr, 0)})
    {
        do {
            sys_path.resize(pathlen);
            pathlen = GetSystemDirectoryW(sys_path.data(), pathlen);
        } while(pathlen >= sys_path.size());
        sys_path.resize(pathlen);
    }
    if(!sys_path.empty() && (sys_path.back() == '\\' || sys_path.back() == '/'))
        sys_path.pop_back();
    if(!sys_path.empty())
        TRACE("Got system path %ls\n", sys_path.c_str());

    /* Don't search the DLL's path if it is the same as the current working
     * directory, app's path, or system path (don't want to do duplicate
     * searches, or increase the priority of the app or system path).
     */
    if(!dll_path.empty() &&
       (cwd_path.empty() || dll_path != cwd_path) &&
       (proc_path.empty() || dll_path != proc_path) &&
       (sys_path.empty() || dll_path != sys_path))
        SearchDrivers(dll_path);
    if(!cwd_path.empty() &&
       (proc_path.empty() || cwd_path != proc_path) &&
       (sys_path.empty() || cwd_path != sys_path))
        SearchDrivers(cwd_path);
    if(!proc_path.empty() && (sys_path.empty() || proc_path != sys_path))
        SearchDrivers(proc_path);
    if(!sys_path.empty())
        SearchDrivers(sys_path);
}

} // namespace

BOOL APIENTRY DllMain(HINSTANCE, DWORD reason, void*)
{
    switch(reason)
    {
    case DLL_PROCESS_ATTACH:
        if(auto logfname = al::getenv("ALROUTER_LOGFILE"))
        {
            gsl::owner<std::FILE*> f{fopen(logfname->c_str(), "w")};
            if(f == nullptr)
                ERR("Could not open log file: %s\n", logfname->c_str());
            else
                LogFile = f;
        }
        if(auto loglev = al::getenv("ALROUTER_LOGLEVEL"))
        {
            char *end = nullptr;
            long l{strtol(loglev->c_str(), &end, 0)};
            if(!end || *end != '\0')
                ERR("Invalid log level value: %s\n", loglev->c_str());
            else if(l < al::to_underlying(eLogLevel::None)
                || l > al::to_underlying(eLogLevel::Trace))
                ERR("Log level out of range: %s\n", loglev->c_str());
            else
                LogLevel = static_cast<eLogLevel>(l);
        }
        TRACE("Initializing router v0.1-%s %s\n", ALSOFT_GIT_COMMIT_HASH, ALSOFT_GIT_BRANCH);
        LoadDriverList();

        break;

    case DLL_THREAD_ATTACH:
        break;
    case DLL_THREAD_DETACH:
        break;

    case DLL_PROCESS_DETACH:
        DriverList.clear();

        if(LogFile)
            fclose(LogFile);
        LogFile = nullptr;

        break;
    }
    return TRUE;
}
