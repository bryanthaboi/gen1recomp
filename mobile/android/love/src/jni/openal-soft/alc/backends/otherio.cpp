/**
 * OpenAL cross platform audio library
 * Copyright (C) 2024 by authors.
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

#include "otherio.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winreg.h>

#include <cstdio>
#include <cstdlib>
#include <memory.h>

#include <wtypes.h>
#include <cguid.h>
#include <devpropdef.h>
#include <mmreg.h>
#include <propsys.h>
#include <propkey.h>
#include <devpkey.h>
#ifndef _WAVEFORMATEXTENSIBLE_
#include <ks.h>
#include <ksmedia.h>
#endif

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <functional>
#include <future>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "albit.h"
#include "alstring.h"
#include "althrd_setname.h"
#include "comptr.h"
#include "core/converter.h"
#include "core/device.h"
#include "core/helpers.h"
#include "core/logging.h"
#include "strutils.h"


/* A custom C++ interface that should be capable of interoperating with ASIO
 * drivers.
 */
enum class ORIOError : LONG {
    Okay = 0,
    Success = 0x3f4847a0,
    NotPresent = -1000,
    HWMalfunction,
    InvalidParameter,
    InvalidMode,
    SPNotAdvancing,
    NoClock,
    NoMemory,
};

/* A 64-bit integer or double, which has the most significant 32-bit word first. */
struct ORIO64Bit {
    uint32_t hi;
    uint32_t lo;

    template<typename T>
    auto as() const -> T = delete;
};

template<> [[nodiscard]]
auto ORIO64Bit::as() const -> uint64_t { return (uint64_t{hi}<<32) | lo; }
template<> [[nodiscard]]
auto ORIO64Bit::as() const -> int64_t { return static_cast<int64_t>(as<uint64_t>()); }
template<> [[nodiscard]]
auto ORIO64Bit::as() const -> double { return al::bit_cast<double>(as<uint64_t>()); }


enum class ORIOSampleType : LONG {
    Int16BE = 0,
    Int24BE = 1,
    Int32BE = 2,
    Float32BE = 3,
    Float64BE = 4,
    Int32BE16 = 8,
    Int32BE18 = 9,
    Int32BE20 = 10,
    Int32BE24 = 11,

    Int16LE = 16,
    Int24LE = 17,
    Int32LE = 18,
    Float32LE = 19,
    Float64LE = 20,
    Int32LE16 = 24,
    Int32LE18 = 25,
    Int32LE20 = 26,
    Int32LE24 = 27,

    DSDInt8LSB1 = 32,
    DSDInt8MSB1 = 33,

    DSDInt8 = 40,
};

struct ORIOClockSource {
    LONG mIndex;
    LONG mAssocChannel;
    LONG mAssocGroup;
    LONG mIsCurrent;
    std::array<char,32> mName;
};

struct ORIOChannelInfo {
    LONG mChannel;
    LONG mIsInput;
    LONG mIsActive;
    LONG mGroup;
    ORIOSampleType mSampleType;
    std::array<char,32> mName;
};

struct ORIOBufferInfo {
    LONG mIsInput;
    LONG mChannelNum;
    std::array<void*,2> mBuffers;
};

struct ORIOTime {
    struct TimeInfo {
        double mSpeed;
        ORIO64Bit mSystemTime;
        ORIO64Bit mSamplePosition;
        double mSampleRate;
        ULONG mFlags;
        std::array<char,12> mReserved;
    };
    struct TimeCode {
        double mSpeed;
        ORIO64Bit mTimeCodeSamples;
        ULONG mFlags;
        std::array<char,64> mFuture;
    };

    std::array<LONG,4> mReserved;
    TimeInfo mTimeInfo;
    TimeCode mTimeCode;
};

#ifdef _WIN64
#define ORIO_CALLBACK CALLBACK
#else
#define ORIO_CALLBACK
#endif

struct ORIOCallbacks {
    void (ORIO_CALLBACK*BufferSwitch)(LONG bufferIndex, LONG directProcess) noexcept;
    void (ORIO_CALLBACK*SampleRateDidChange)(double srate) noexcept;
    auto (ORIO_CALLBACK*Message)(LONG selector, LONG value, void *message, double *opt) noexcept -> LONG;
    auto (ORIO_CALLBACK*BufferSwitchTimeInfo)(ORIOTime *timeInfo, LONG bufferIndex, LONG directProcess) noexcept -> ORIOTime*;
};

/* COM interfaces don't include a virtual destructor in their pure-virtual
 * classes, and we can't add one without breaking ABI.
 */
#ifdef __GNUC__
_Pragma("GCC diagnostic push")
_Pragma("GCC diagnostic ignored \"-Wnon-virtual-dtor\"")
#endif
/* NOLINTNEXTLINE(cppcoreguidelines-virtual-class-destructor) */
struct ORIOiface : public IUnknown {
    STDMETHOD_(LONG, Init)(void *sysHandle) = 0;
    /* A fixed-length span should be passed exactly the same as one pointer.
     * This ensures an appropriately-sized buffer for the driver.
     */
    STDMETHOD_(void, GetDriverName)(al::span<char,32> name) = 0;
    STDMETHOD_(LONG, GetDriverVersion)() = 0;
    STDMETHOD_(void, GetErrorMessage)(al::span<char,124> message) = 0;
    STDMETHOD_(ORIOError, Start)() = 0;
    STDMETHOD_(ORIOError, Stop)() = 0;
    STDMETHOD_(ORIOError, GetChannels)(LONG *numInput, LONG *numOutput) = 0;
    STDMETHOD_(ORIOError, GetLatencies)(LONG *inputLatency, LONG *outputLatency) = 0;
    STDMETHOD_(ORIOError, GetBufferSize)(LONG *minSize, LONG *maxSize, LONG *preferredSize, LONG *granularity) = 0;
    STDMETHOD_(ORIOError, CanSampleRate)(double srate) = 0;
    STDMETHOD_(ORIOError, GetSampleRate)(double *srate) = 0;
    STDMETHOD_(ORIOError, SetSampleRate)(double srate) = 0;
    STDMETHOD_(ORIOError, GetClockSources)(ORIOClockSource *clocks, LONG *numSources) = 0;
    STDMETHOD_(ORIOError, SetClockSource)(LONG index) = 0;
    STDMETHOD_(ORIOError, GetSamplePosition)(ORIO64Bit *splPos, ORIO64Bit *tstampNS) = 0;
    STDMETHOD_(ORIOError, GetChannelInfo)(ORIOChannelInfo *info) = 0;
    STDMETHOD_(ORIOError, CreateBuffers)(ORIOBufferInfo *infos, LONG numInfos, LONG bufferSize, ORIOCallbacks *callbacks) = 0;
    STDMETHOD_(ORIOError, DisposeBuffers)() = 0;
    STDMETHOD_(ORIOError, ControlPanel)() = 0;
    STDMETHOD_(ORIOError, Future)(LONG selector, void *opt) = 0;
    STDMETHOD_(ORIOError, OutputReady)() = 0;

    ORIOiface() = default;
    ORIOiface(const ORIOiface&) = delete;
    auto operator=(const ORIOiface&) -> ORIOiface& = delete;
    ~ORIOiface() = delete;
};
#ifdef __GNUC__
_Pragma("GCC diagnostic pop")
#endif

namespace {

using namespace std::string_view_literals;
using std::chrono::nanoseconds;
using std::chrono::milliseconds;
using std::chrono::seconds;


struct DeviceEntry {
    std::string mDrvName;
    CLSID mDrvGuid{};
};

std::vector<DeviceEntry> gDeviceList;


struct KeyCloser {
    void operator()(HKEY key) { RegCloseKey(key); }
};
using KeyPtr = std::unique_ptr<std::remove_pointer_t<HKEY>,KeyCloser>;

[[nodiscard]]
auto PopulateDeviceList() -> HRESULT
{
    auto regbase = KeyPtr{};
    auto res = RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"Software\\ASIO", 0, KEY_READ,
        al::out_ptr(regbase));
    if(res != ERROR_SUCCESS)
    {
        ERR("Error opening HKLM\\Software\\ASIO: %ld\n", res);
        return E_NOINTERFACE;
    }

    auto numkeys = DWORD{};
    auto maxkeylen = DWORD{};
    res = RegQueryInfoKeyW(regbase.get(), nullptr, nullptr, nullptr, &numkeys, &maxkeylen, nullptr,
        nullptr, nullptr, nullptr, nullptr, nullptr);
    if(res != ERROR_SUCCESS)
    {
        ERR("Error querying HKLM\\Software\\ASIO info: %ld\n", res);
        return E_FAIL;
    }

    /* maxkeylen is the max number of unicode characters a subkey is. A unicode
     * character can occupy two WCHARs, so ensure there's enough space for them
     * and the null char.
     */
    auto keyname = std::vector<WCHAR>(maxkeylen*2 + 1);
    for(DWORD i{0};i < numkeys;++i)
    {
        auto namelen = static_cast<DWORD>(keyname.size());
        res = RegEnumKeyExW(regbase.get(), i, keyname.data(), &namelen, nullptr, nullptr, nullptr,
            nullptr);
        if(res != ERROR_SUCCESS)
        {
            ERR("Error querying HKLM\\Software\\ASIO subkey %lu: %ld\n", i, res);
            continue;
        }
        if(namelen == 0)
        {
            ERR("HKLM\\Software\\ASIO subkey %lu is blank?\n", i);
            continue;
        }
        auto subkeyname = wstr_to_utf8({keyname.data(), namelen});

        auto subkey = KeyPtr{};
        res = RegOpenKeyExW(regbase.get(), keyname.data(), 0, KEY_READ, al::out_ptr(subkey));
        if(res != ERROR_SUCCESS)
        {
            ERR("Error opening HKLM\\Software\\ASIO\\%s: %ld\n", subkeyname.c_str(), res);
            continue;
        }

        auto idstr = std::array<WCHAR,48>{};
        auto readsize = DWORD{idstr.size()*sizeof(WCHAR)};
        res = RegGetValueW(subkey.get(), L"", L"CLSID", RRF_RT_REG_SZ, nullptr, idstr.data(),
            &readsize);
        if(res != ERROR_SUCCESS)
        {
            ERR("Failed to read HKLM\\Software\\ASIO\\%s\\CLSID: %ld\n", subkeyname.c_str(), res);
            continue;
        }
        idstr.back() = 0;

        auto guid = CLSID{};
        if(auto hr = CLSIDFromString(idstr.data(), &guid); FAILED(hr))
        {
            ERR("Failed to parse CLSID \"%s\": 0x%08lx\n", wstr_to_utf8(idstr.data()).c_str(), hr);
            continue;
        }

        /* The CLSID is also used for the IID. */
        auto iface = ComPtr<ORIOiface>{};
        auto hr = CoCreateInstance(guid, nullptr, CLSCTX_INPROC_SERVER, guid, al::out_ptr(iface));
        if(SUCCEEDED(hr))
        {
#if !ALSOFT_UWP
            if(!iface->Init(GetForegroundWindow()))
#else
            if(!iface->Init(nullptr))
#endif
            {
                ERR("Failed to initialize %s\n", subkeyname.c_str());
                continue;
            }
            auto drvname = std::array<char,32>{};
            iface->GetDriverName(drvname);
            auto drvver = iface->GetDriverVersion();

            auto &entry = gDeviceList.emplace_back();
            entry.mDrvName = drvname.data();
            entry.mDrvGuid = guid;

            TRACE("Got %s v%ld, CLSID {%08lX-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}\n",
                entry.mDrvName.c_str(), drvver, guid.Data1, guid.Data2, guid.Data3, guid.Data4[0],
                guid.Data4[1], guid.Data4[2], guid.Data4[3], guid.Data4[4], guid.Data4[5],
                guid.Data4[6], guid.Data4[7]);
        }
        else
            ERR("Failed to create %s instance for CLSID {%08lX-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X}: 0x%08lx\n",
                subkeyname.c_str(), guid.Data1, guid.Data2, guid.Data3, guid.Data4[0],
                guid.Data4[1], guid.Data4[2], guid.Data4[3], guid.Data4[4], guid.Data4[5],
                guid.Data4[6], guid.Data4[7], hr);
    }

    return S_OK;
}


enum class MsgType {
    OpenDevice,
    ResetDevice,
    StartDevice,
    StopDevice,
    CloseDevice,

    QuitThread
};

constexpr const char *GetMessageTypeName(MsgType type) noexcept
{
    switch(type)
    {
    case MsgType::OpenDevice: return "Open Device";
    case MsgType::ResetDevice: return "Reset Device";
    case MsgType::StartDevice: return "Start Device";
    case MsgType::StopDevice: return "Stop Device";
    case MsgType::CloseDevice: return "Close Device";
    case MsgType::QuitThread: break;
    }
    return "";
}


/* Proxy interface used by the message handler, to ensure COM objects are used
 * on a thread where COM is initialized.
 */
struct OtherIOProxy {
    OtherIOProxy() = default;
    OtherIOProxy(const OtherIOProxy&) = delete;
    OtherIOProxy(OtherIOProxy&&) = delete;
    virtual ~OtherIOProxy() = default;

    void operator=(const OtherIOProxy&) = delete;
    void operator=(OtherIOProxy&&) = delete;

    virtual HRESULT openProxy(std::string_view name) = 0;
    virtual void closeProxy() = 0;

    virtual HRESULT resetProxy() = 0;
    virtual HRESULT startProxy() = 0;
    virtual void stopProxy() = 0;

    struct Msg {
        MsgType mType;
        OtherIOProxy *mProxy;
        std::string_view mParam;
        std::promise<HRESULT> mPromise;

        explicit operator bool() const noexcept { return mType != MsgType::QuitThread; }
    };
    static inline std::deque<Msg> mMsgQueue;
    static inline std::mutex mMsgQueueLock;
    static inline std::condition_variable mMsgQueueCond;

    auto pushMessage(MsgType type, std::string_view param={}) -> std::future<HRESULT>
    {
        auto promise = std::promise<HRESULT>{};
        auto future = std::future<HRESULT>{promise.get_future()};
        {
            auto msglock = std::lock_guard{mMsgQueueLock};
            mMsgQueue.emplace_back(Msg{type, this, param, std::move(promise)});
        }
        mMsgQueueCond.notify_one();
        return future;
    }

    static auto popMessage() -> Msg
    {
        auto lock = std::unique_lock{mMsgQueueLock};
        mMsgQueueCond.wait(lock, []{return !mMsgQueue.empty();});
        auto msg = Msg{std::move(mMsgQueue.front())};
        mMsgQueue.pop_front();
        return msg;
    }

    static void messageHandler(std::promise<HRESULT> *promise);
};

void OtherIOProxy::messageHandler(std::promise<HRESULT> *promise)
{
    TRACE("Starting COM message thread\n");

    auto com = ComWrapper{COINIT_APARTMENTTHREADED};
    if(!com)
    {
        WARN("Failed to initialize COM: 0x%08lx\n", com.status());
        promise->set_value(com.status());
        return;
    }

    auto hr = PopulateDeviceList();
    if(FAILED(hr))
    {
        promise->set_value(hr);
        return;
    }

    promise->set_value(S_OK);
    promise = nullptr;

    TRACE("Starting message loop\n");
    while(Msg msg{popMessage()})
    {
        TRACE("Got message \"%s\" (0x%04x, this=%p, param=\"%.*s\")\n",
            GetMessageTypeName(msg.mType), static_cast<uint>(msg.mType),
            static_cast<void*>(msg.mProxy), al::sizei(msg.mParam), msg.mParam.data());

        switch(msg.mType)
        {
        case MsgType::OpenDevice:
            hr = msg.mProxy->openProxy(msg.mParam);
            msg.mPromise.set_value(hr);
            continue;

        case MsgType::ResetDevice:
            hr = msg.mProxy->resetProxy();
            msg.mPromise.set_value(hr);
            continue;

        case MsgType::StartDevice:
            hr = msg.mProxy->startProxy();
            msg.mPromise.set_value(hr);
            continue;

        case MsgType::StopDevice:
            msg.mProxy->stopProxy();
            msg.mPromise.set_value(S_OK);
            continue;

        case MsgType::CloseDevice:
            msg.mProxy->closeProxy();
            msg.mPromise.set_value(S_OK);
            continue;

        case MsgType::QuitThread:
            break;
        }
        ERR("Unexpected message: %u\n", static_cast<uint>(msg.mType));
        msg.mPromise.set_value(E_FAIL);
    }
    TRACE("Message loop finished\n");
}


struct OtherIOPlayback final : public BackendBase, OtherIOProxy {
    OtherIOPlayback(DeviceBase *device) noexcept : BackendBase{device} { }
    ~OtherIOPlayback() final;

    void mixerProc();

    void open(std::string_view name) final;
    auto openProxy(std::string_view name) -> HRESULT final;
    void closeProxy() final;
    auto reset() -> bool final;
    auto resetProxy() -> HRESULT final;
    void start() final;
    auto startProxy() -> HRESULT final;
    void stop() final;
    void stopProxy() final;

    HRESULT mOpenStatus{E_FAIL};

    std::atomic<bool> mKillNow{true};
    std::thread mThread;
};

OtherIOPlayback::~OtherIOPlayback()
{
    if(SUCCEEDED(mOpenStatus))
        pushMessage(MsgType::CloseDevice).wait();
}

void OtherIOPlayback::mixerProc()
{
    const auto restTime = milliseconds{mDevice->UpdateSize*1000/mDevice->Frequency / 2};

    SetRTPriority();
    althrd_setname(GetMixerThreadName());

    auto done = int64_t{0};
    auto start = std::chrono::steady_clock::now();
    while(!mKillNow.load(std::memory_order_acquire)
        && mDevice->Connected.load(std::memory_order_acquire))
    {
        auto now = std::chrono::steady_clock::now();

        /* This converts from nanoseconds to nanosamples, then to samples. */
        auto avail = int64_t{std::chrono::duration_cast<seconds>((now-start) * mDevice->Frequency).count()};
        if(avail-done < mDevice->UpdateSize)
        {
            std::this_thread::sleep_for(restTime);
            continue;
        }
        while(avail-done >= mDevice->UpdateSize)
        {
            mDevice->renderSamples(nullptr, mDevice->UpdateSize, 0u);
            done += mDevice->UpdateSize;
        }

        if(done >= mDevice->Frequency)
        {
            auto s = seconds{done/mDevice->Frequency};
            start += s;
            done -= mDevice->Frequency*s.count();
        }
    }
}


void OtherIOPlayback::open(std::string_view name)
{
    if(name.empty() && !gDeviceList.empty())
        name = gDeviceList[0].mDrvName;
    else
    {
        auto iter = std::find_if(gDeviceList.cbegin(), gDeviceList.cend(),
            [name](const DeviceEntry &entry) { return entry.mDrvName == name; });
        if(iter == gDeviceList.cend())
            throw al::backend_exception{al::backend_error::NoDevice,
                "Device name \"%.*s\" not found", al::sizei(name), name.data()};
    }

    mOpenStatus = pushMessage(MsgType::OpenDevice, name).get();
    if(FAILED(mOpenStatus))
        throw al::backend_exception{al::backend_error::DeviceError, "Failed to open \"%.*s\"",
            al::sizei(name), name.data()};

    mDeviceName = name;
}

auto OtherIOPlayback::openProxy(std::string_view name [[maybe_unused]]) -> HRESULT
{
    return S_OK;
}

void OtherIOPlayback::closeProxy()
{
}

auto OtherIOPlayback::reset() -> bool
{
    return SUCCEEDED(pushMessage(MsgType::ResetDevice).get());
}

auto OtherIOPlayback::resetProxy() -> HRESULT
{
    setDefaultWFXChannelOrder();
    return S_OK;
}

void OtherIOPlayback::start()
{
    auto hr = pushMessage(MsgType::StartDevice).get();
    if(FAILED(hr))
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to start playback: 0x%08lx", hr};
}

auto OtherIOPlayback::startProxy() -> HRESULT
{
    try {
        mKillNow.store(false, std::memory_order_release);
        mThread = std::thread{std::mem_fn(&OtherIOPlayback::mixerProc), this};
        return S_OK;
    }
    catch(std::exception& e) {
        ERR("Failed to start mixing thread: %s", e.what());
    }
    return E_FAIL;
}

void OtherIOPlayback::stop()
{
    pushMessage(MsgType::StopDevice).wait();
}

void OtherIOPlayback::stopProxy()
{
    if(mKillNow.exchange(true, std::memory_order_acq_rel) || !mThread.joinable())
        return;
    mThread.join();
}

} // namespace


auto OtherIOBackendFactory::init() -> bool
{
    static HRESULT InitResult{E_FAIL};
    if(FAILED(InitResult)) try
    {
        auto promise = std::promise<HRESULT>{};
        auto future = promise.get_future();

        std::thread{&OtherIOProxy::messageHandler, &promise}.detach();
        InitResult = future.get();
    }
    catch(...) {
    }

    return SUCCEEDED(InitResult);
}

auto OtherIOBackendFactory::querySupport(BackendType type) -> bool
{ return type == BackendType::Playback; }

auto OtherIOBackendFactory::enumerate(BackendType type) -> std::vector<std::string>
{
    std::vector<std::string> outnames;

    switch(type)
    {
    case BackendType::Playback:
        std::for_each(gDeviceList.cbegin(), gDeviceList.cend(),
            [&outnames](const DeviceEntry &entry) { outnames.emplace_back(entry.mDrvName); });
        break;

    case BackendType::Capture:
        break;
    }

    return outnames;
}

auto OtherIOBackendFactory::createBackend(DeviceBase *device, BackendType type) -> BackendPtr
{
    if(type == BackendType::Playback)
        return BackendPtr{new OtherIOPlayback{device}};
    return nullptr;
}

auto OtherIOBackendFactory::getFactory() -> BackendFactory&
{
    static auto factory = OtherIOBackendFactory{};
    return factory;
}

auto OtherIOBackendFactory::queryEventSupport(alc::EventType, BackendType) -> alc::EventSupport
{
    return alc::EventSupport::NoSupport;
}
