/**
 * OpenAL cross platform audio library
 * Copyright (C) 2011 by authors.
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

#include "wasapi.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <memory.h>

#include <avrt.h>
#include <wtypes.h>
#include <mmdeviceapi.h>
#include <audiosessiontypes.h>
#include <audioclient.h>
#include <spatialaudioclient.h>
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
#include "alc/alconfig.h"
#include "alnumeric.h"
#include "alspan.h"
#include "alstring.h"
#include "althrd_setname.h"
#include "comptr.h"
#include "core/converter.h"
#include "core/device.h"
#include "core/helpers.h"
#include "core/logging.h"
#include "ringbuffer.h"
#include "strutils.h"

#if ALSOFT_UWP

#include <winrt/Windows.Media.Core.h> // !!This is important!!
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Media.Devices.h>

using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::Media::Devices;
using namespace Windows::Devices::Enumeration;
using namespace Windows::Media::Devices;
#endif

/* Some headers seem to define these as macros for __uuidof, which is annoying
 * since some headers don't declare them at all. Hopefully the ifdef is enough
 * to tell if they need to be declared.
 */
#ifndef KSDATAFORMAT_SUBTYPE_PCM
DEFINE_GUID(KSDATAFORMAT_SUBTYPE_PCM, 0x00000001, 0x0000, 0x0010, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71);
#endif
#ifndef KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
DEFINE_GUID(KSDATAFORMAT_SUBTYPE_IEEE_FLOAT, 0x00000003, 0x0000, 0x0010, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71);
#endif
#if !ALSOFT_UWP
DEFINE_DEVPROPKEY(DEVPKEY_Device_FriendlyName, 0xa45c254e, 0xdf1c, 0x4efd, 0x80,0x20, 0x67,0xd1,0x46,0xa8,0x50,0xe0, 14);
DEFINE_PROPERTYKEY(PKEY_AudioEndpoint_FormFactor, 0x1da5d803, 0xd492, 0x4edd, 0x8c,0x23, 0xe0,0xc0,0xff,0xee,0x7f,0x0e, 0);
DEFINE_PROPERTYKEY(PKEY_AudioEndpoint_GUID, 0x1da5d803, 0xd492, 0x4edd, 0x8c, 0x23,0xe0, 0xc0,0xff,0xee,0x7f,0x0e, 4 );
#endif

namespace {

using namespace std::string_view_literals;
using std::chrono::nanoseconds;
using std::chrono::milliseconds;
using std::chrono::seconds;

using ReferenceTime = std::chrono::duration<REFERENCE_TIME,std::ratio<1,10'000'000>>;


#define MONO SPEAKER_FRONT_CENTER
#define STEREO (SPEAKER_FRONT_LEFT|SPEAKER_FRONT_RIGHT)
#define QUAD (SPEAKER_FRONT_LEFT|SPEAKER_FRONT_RIGHT|SPEAKER_BACK_LEFT|SPEAKER_BACK_RIGHT)
#define X5DOT1 (SPEAKER_FRONT_LEFT|SPEAKER_FRONT_RIGHT|SPEAKER_FRONT_CENTER|SPEAKER_LOW_FREQUENCY|SPEAKER_SIDE_LEFT|SPEAKER_SIDE_RIGHT)
#define X5DOT1REAR (SPEAKER_FRONT_LEFT|SPEAKER_FRONT_RIGHT|SPEAKER_FRONT_CENTER|SPEAKER_LOW_FREQUENCY|SPEAKER_BACK_LEFT|SPEAKER_BACK_RIGHT)
#define X6DOT1 (SPEAKER_FRONT_LEFT|SPEAKER_FRONT_RIGHT|SPEAKER_FRONT_CENTER|SPEAKER_LOW_FREQUENCY|SPEAKER_BACK_CENTER|SPEAKER_SIDE_LEFT|SPEAKER_SIDE_RIGHT)
#define X7DOT1 (SPEAKER_FRONT_LEFT|SPEAKER_FRONT_RIGHT|SPEAKER_FRONT_CENTER|SPEAKER_LOW_FREQUENCY|SPEAKER_BACK_LEFT|SPEAKER_BACK_RIGHT|SPEAKER_SIDE_LEFT|SPEAKER_SIDE_RIGHT)
#define X7DOT1DOT4 (SPEAKER_FRONT_LEFT|SPEAKER_FRONT_RIGHT|SPEAKER_FRONT_CENTER|SPEAKER_LOW_FREQUENCY|SPEAKER_BACK_LEFT|SPEAKER_BACK_RIGHT|SPEAKER_SIDE_LEFT|SPEAKER_SIDE_RIGHT|SPEAKER_TOP_FRONT_LEFT|SPEAKER_TOP_FRONT_RIGHT|SPEAKER_TOP_BACK_LEFT|SPEAKER_TOP_BACK_RIGHT)

constexpr inline DWORD MaskFromTopBits(DWORD b) noexcept
{
    b |= b>>1;
    b |= b>>2;
    b |= b>>4;
    b |= b>>8;
    b |= b>>16;
    return b;
}
constexpr DWORD MonoMask{MaskFromTopBits(MONO)};
constexpr DWORD StereoMask{MaskFromTopBits(STEREO)};
constexpr DWORD QuadMask{MaskFromTopBits(QUAD)};
constexpr DWORD X51Mask{MaskFromTopBits(X5DOT1)};
constexpr DWORD X51RearMask{MaskFromTopBits(X5DOT1REAR)};
constexpr DWORD X61Mask{MaskFromTopBits(X6DOT1)};
constexpr DWORD X71Mask{MaskFromTopBits(X7DOT1)};
constexpr DWORD X714Mask{MaskFromTopBits(X7DOT1DOT4)};


#ifndef _MSC_VER
constexpr AudioObjectType operator|(AudioObjectType lhs, AudioObjectType rhs) noexcept
{ return static_cast<AudioObjectType>(lhs | al::to_underlying(rhs)); }
#endif

constexpr AudioObjectType ChannelMask_Mono{AudioObjectType_FrontCenter};
constexpr AudioObjectType ChannelMask_Stereo{AudioObjectType_FrontLeft
    | AudioObjectType_FrontRight};
constexpr AudioObjectType ChannelMask_Quad{AudioObjectType_FrontLeft | AudioObjectType_FrontRight
    | AudioObjectType_BackLeft | AudioObjectType_BackRight};
constexpr AudioObjectType ChannelMask_X51{AudioObjectType_FrontLeft | AudioObjectType_FrontRight
    | AudioObjectType_FrontCenter | AudioObjectType_LowFrequency | AudioObjectType_SideLeft
    | AudioObjectType_SideRight};
constexpr AudioObjectType ChannelMask_X61{AudioObjectType_FrontLeft | AudioObjectType_FrontRight
    | AudioObjectType_FrontCenter | AudioObjectType_LowFrequency | AudioObjectType_SideLeft
    | AudioObjectType_SideRight | AudioObjectType_BackCenter};
constexpr AudioObjectType ChannelMask_X71{AudioObjectType_FrontLeft | AudioObjectType_FrontRight
    | AudioObjectType_FrontCenter | AudioObjectType_LowFrequency | AudioObjectType_SideLeft
    | AudioObjectType_SideRight | AudioObjectType_BackLeft | AudioObjectType_BackRight};
constexpr AudioObjectType ChannelMask_X714{AudioObjectType_FrontLeft | AudioObjectType_FrontRight
    | AudioObjectType_FrontCenter | AudioObjectType_LowFrequency | AudioObjectType_SideLeft
    | AudioObjectType_SideRight | AudioObjectType_BackLeft | AudioObjectType_BackRight
    | AudioObjectType_TopFrontLeft | AudioObjectType_TopFrontRight | AudioObjectType_TopBackLeft
    | AudioObjectType_TopBackRight};
constexpr AudioObjectType ChannelMask_X7144{AudioObjectType_FrontLeft | AudioObjectType_FrontRight
    | AudioObjectType_FrontCenter | AudioObjectType_LowFrequency | AudioObjectType_SideLeft
    | AudioObjectType_SideRight | AudioObjectType_BackLeft | AudioObjectType_BackRight
    | AudioObjectType_TopFrontLeft | AudioObjectType_TopFrontRight | AudioObjectType_TopBackLeft
    | AudioObjectType_TopBackRight | AudioObjectType_BottomFrontLeft
    | AudioObjectType_BottomFrontRight | AudioObjectType_BottomBackLeft
    | AudioObjectType_BottomBackRight};


template<typename... Ts>
struct overloaded : Ts... { using Ts::operator()...; };

template<typename... Ts>
overloaded(Ts...) -> overloaded<Ts...>;


template<typename T>
constexpr auto as_unsigned(T value) noexcept
{
    using UT = std::make_unsigned_t<T>;
    return static_cast<UT>(value);
}


/* Scales the given reftime value, rounding the result. */
template<typename T>
constexpr uint RefTime2Samples(const ReferenceTime &val, T srate) noexcept
{
    const auto retval = (val*srate + ReferenceTime{seconds{1}}/2) / seconds{1};
    return static_cast<uint>(std::min<decltype(retval)>(retval, std::numeric_limits<uint>::max()));
}


class GuidPrinter {
    std::array<char,64> mMsg{};

public:
    GuidPrinter(const GUID &guid)
    {
        std::snprintf(mMsg.data(), mMsg.size(), "{%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x}",
            DWORD{guid.Data1}, guid.Data2, guid.Data3, guid.Data4[0], guid.Data4[1], guid.Data4[2],
            guid.Data4[3], guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7]);
    }
    [[nodiscard]] auto c_str() const -> const char* { return mMsg.data(); }
};

struct PropVariant {
    PROPVARIANT mProp{};

public:
    PropVariant() { PropVariantInit(&mProp); }
    PropVariant(const PropVariant &rhs) : PropVariant{} { PropVariantCopy(&mProp, &rhs.mProp); }
    ~PropVariant() { clear(); }

    auto operator=(const PropVariant &rhs) -> PropVariant&
    {
        if(this != &rhs)
            PropVariantCopy(&mProp, &rhs.mProp);
        return *this;
    }

    void clear() { PropVariantClear(&mProp); }

    PROPVARIANT* get() noexcept { return &mProp; }

    /* NOLINTBEGIN(cppcoreguidelines-pro-type-union-access) */
    [[nodiscard]]
    auto type() const noexcept -> VARTYPE { return mProp.vt; }

    template<typename T> [[nodiscard]]
    auto value() const -> T
    {
        if constexpr(std::is_same_v<T,uint>)
        {
            alassert(mProp.vt == VT_UI4 || mProp.vt == VT_UINT);
            return mProp.uintVal;
        }
        else if constexpr(std::is_same_v<T,std::wstring_view> || std::is_same_v<T,std::wstring>
            || std::is_same_v<T,LPWSTR> || std::is_same_v<T,LPCWSTR>)
        {
            alassert(mProp.vt == VT_LPWSTR);
            return mProp.pwszVal;
        }
    }

    void setBlob(const al::span<BYTE> data)
    {
        if constexpr(sizeof(size_t) > sizeof(ULONG))
            alassert(data.size() <= std::numeric_limits<ULONG>::max());
        mProp.vt = VT_BLOB;
        mProp.blob.cbSize = static_cast<ULONG>(data.size());
        mProp.blob.pBlobData = data.data();
    }
    /* NOLINTEND(cppcoreguidelines-pro-type-union-access) */
};

struct DevMap {
    std::string name;
    std::string endpoint_guid; // obtained from PKEY_AudioEndpoint_GUID , set to "Unknown device GUID" if absent.
    std::wstring devid;

    template<typename T0, typename T1, typename T2>
    DevMap(T0&& name_, T1&& guid_, T2&& devid_)
      : name{std::forward<T0>(name_)}
      , endpoint_guid{std::forward<T1>(guid_)}
      , devid{std::forward<T2>(devid_)}
    { }
    /* To prevent GCC from complaining it doesn't want to inline this. */
    ~DevMap();
};
DevMap::~DevMap() = default;

bool checkName(const al::span<DevMap> list, const std::string_view name)
{
    auto match_name = [name](const DevMap &entry) -> bool { return entry.name == name; };
    return std::find_if(list.cbegin(), list.cend(), match_name) != list.cend();
}


struct DeviceList {
    auto lock() noexcept(noexcept(mMutex.lock())) { return mMutex.lock(); }
    auto unlock() noexcept(noexcept(mMutex.unlock())) { return mMutex.unlock(); }

private:
    std::mutex mMutex;
    std::vector<DevMap> mPlayback;
    std::vector<DevMap> mCapture;
    std::wstring mPlaybackDefaultId;
    std::wstring mCaptureDefaultId;

    friend struct DeviceListLock;
};
struct DeviceListLock : public std::unique_lock<DeviceList> {
    using std::unique_lock<DeviceList>::unique_lock;

    [[nodiscard]] auto& getPlaybackList() const noexcept { return mutex()->mPlayback; }
    [[nodiscard]] auto& getCaptureList() const noexcept { return mutex()->mCapture; }

    void setPlaybackDefaultId(std::wstring_view devid) const { mutex()->mPlaybackDefaultId = devid; }
    [[nodiscard]] auto getPlaybackDefaultId() const noexcept -> std::wstring_view { return mutex()->mPlaybackDefaultId; }
    void setCaptureDefaultId(std::wstring_view devid) const { mutex()->mCaptureDefaultId = devid; }
    [[nodiscard]] auto getCaptureDefaultId() const noexcept -> std::wstring_view { return mutex()->mCaptureDefaultId; }
};

DeviceList gDeviceList;


#ifdef AVRTAPI
struct AvrtHandleCloser {
    void operator()(HANDLE handle) { AvRevertMmThreadCharacteristics(handle); }
};
using AvrtHandlePtr = std::unique_ptr<std::remove_pointer_t<HANDLE>,AvrtHandleCloser>;
#endif

#if ALSOFT_UWP
enum EDataFlow {
    eRender              = 0,
    eCapture             = (eRender + 1),
    eAll                 = (eCapture + 1),
    EDataFlow_enum_count = (eAll + 1)
};
#endif

#if ALSOFT_UWP
using DeviceHandle = Windows::Devices::Enumeration::DeviceInformation;
using EventRegistrationToken = winrt::event_token;
#else
using DeviceHandle = ComPtr<IMMDevice>;
#endif


struct NameGUIDPair { std::string mName; std::string mGuid; };
auto GetDeviceNameAndGuid(const DeviceHandle &device) -> NameGUIDPair
{
    constexpr auto UnknownName = "Unknown Device Name"sv;
    constexpr auto UnknownGuid = "Unknown Device GUID"sv;

#if !ALSOFT_UWP
    auto ps = ComPtr<IPropertyStore>{};
    auto hr = device->OpenPropertyStore(STGM_READ, al::out_ptr(ps));
    if(FAILED(hr))
    {
        WARN("OpenPropertyStore failed: 0x%08lx\n", hr);
        return NameGUIDPair{std::string{UnknownName}, std::string{UnknownGuid}};
    }

    auto ret = NameGUIDPair{};
    auto pvprop = PropVariant{};
    hr = ps->GetValue(al::bit_cast<PROPERTYKEY>(DEVPKEY_Device_FriendlyName), pvprop.get());
    if(FAILED(hr))
        WARN("GetValue Device_FriendlyName failed: 0x%08lx\n", hr);
    else if(pvprop.type() == VT_LPWSTR)
        ret.mName = wstr_to_utf8(pvprop.value<std::wstring_view>());
    else
        WARN("Unexpected Device_FriendlyName PROPVARIANT type: 0x%04x\n", pvprop.type());

    pvprop.clear();
    hr = ps->GetValue(al::bit_cast<PROPERTYKEY>(PKEY_AudioEndpoint_GUID), pvprop.get());
    if(FAILED(hr))
        WARN("GetValue AudioEndpoint_GUID failed: 0x%08lx\n", hr);
    else if(pvprop.type() == VT_LPWSTR)
        ret.mGuid = wstr_to_utf8(pvprop.value<std::wstring_view>());
    else
        WARN("Unexpected AudioEndpoint_GUID PROPVARIANT type: 0x%04x\n", pvprop.type());
#else
    auto ret = NameGUIDPair{wstr_to_utf8(device.Name()), {}};

    // device->Id is DeviceInterfacePath: \\?\SWD#MMDEVAPI#{0.0.0.00000000}.{a21c17a0-fc1d-405e-ab5a-b513422b57d1}#{e6327cad-dcec-4949-ae8a-991e976a79d2}
    auto devIfPath = device.Id();
    if(auto devIdStart = wcsstr(devIfPath.data(), L"}."))
    {
        devIdStart += 2;  // L"}."
        if(auto devIdStartEnd = wcschr(devIdStart, L'#'))
        {
            ret.mGuid = wstr_to_utf8(std::wstring_view{devIdStart,
                static_cast<size_t>(devIdStartEnd - devIdStart)});
            std::transform(ret.mGuid.begin(), ret.mGuid.end(), ret.mGuid.begin(),
                [](char ch) { return static_cast<char>(std::toupper(ch)); });
        }
    }
#endif
    if(ret.mName.empty()) ret.mName = UnknownName;
    if(ret.mGuid.empty()) ret.mGuid = UnknownGuid;
    return ret;
}
#if !ALSOFT_UWP
EndpointFormFactor GetDeviceFormfactor(IMMDevice *device)
{
    ComPtr<IPropertyStore> ps;
    HRESULT hr{device->OpenPropertyStore(STGM_READ, al::out_ptr(ps))};
    if(FAILED(hr))
    {
        WARN("OpenPropertyStore failed: 0x%08lx\n", hr);
        return UnknownFormFactor;
    }

    EndpointFormFactor formfactor{UnknownFormFactor};
    PropVariant pvform;
    hr = ps->GetValue(PKEY_AudioEndpoint_FormFactor, pvform.get());
    if(FAILED(hr))
        WARN("GetValue AudioEndpoint_FormFactor failed: 0x%08lx\n", hr);
    else if(pvform.type() == VT_UI4)
        formfactor = static_cast<EndpointFormFactor>(pvform.value<uint>());
    else if(pvform.type() != VT_EMPTY)
        WARN("Unexpected PROPVARIANT type: 0x%04x\n", pvform.type());
    return formfactor;
}
#endif


#if ALSOFT_UWP
struct DeviceHelper final : public IActivateAudioInterfaceCompletionHandler
#else
struct DeviceHelper final : private IMMNotificationClient
#endif
{
#if ALSOFT_UWP
    DeviceHelper()
    {
        /* TODO: UWP also needs to watch for device added/removed events and
         * dynamically add/remove devices from the lists.
         */
        mActiveClientEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);

        static constexpr auto playback_cb = [](const IInspectable &sender [[maybe_unused]],
            const DefaultAudioRenderDeviceChangedEventArgs &args)
        {
            if(args.Role() == AudioDeviceRole::Default)
            {
                const auto msg = std::string{"Default playback device changed: " +
                    wstr_to_utf8(args.Id())};
                alc::Event(alc::EventType::DefaultDeviceChanged, alc::DeviceType::Playback, msg);
            }
        };
        mRenderDeviceChangedToken = MediaDevice::DefaultAudioRenderDeviceChanged(playback_cb);

        static constexpr auto capture_cb = [](const IInspectable &sender [[maybe_unused]],
            const DefaultAudioCaptureDeviceChangedEventArgs &args)
        {
            if(args.Role() == AudioDeviceRole::Default)
            {
                const auto msg = std::string{"Default capture device changed: " +
                    wstr_to_utf8(args.Id())};
                alc::Event(alc::EventType::DefaultDeviceChanged, alc::DeviceType::Capture, msg);
            }
        };
        mCaptureDeviceChangedToken = MediaDevice::DefaultAudioCaptureDeviceChanged(capture_cb);
    }
#else
    DeviceHelper() = default;
#endif
    ~DeviceHelper()
    {
#if ALSOFT_UWP
        MediaDevice::DefaultAudioRenderDeviceChanged(mRenderDeviceChangedToken);
        MediaDevice::DefaultAudioCaptureDeviceChanged(mCaptureDeviceChangedToken);

        if(mActiveClientEvent != nullptr)
            CloseHandle(mActiveClientEvent);
        mActiveClientEvent = nullptr;
#else
        if(mEnumerator)
            mEnumerator->UnregisterEndpointNotificationCallback(this);
        mEnumerator = nullptr;
#endif
    }

    template<typename T>
    auto as() noexcept -> T { return T{this}; }

    /** -------------------------- IUnknown ----------------------------- */
    std::atomic<ULONG> mRefCount{1};
    STDMETHODIMP_(ULONG) AddRef() noexcept override { return mRefCount.fetch_add(1u) + 1u; }
    STDMETHODIMP_(ULONG) Release() noexcept override { return mRefCount.fetch_sub(1u) - 1u; }

    STDMETHODIMP QueryInterface(const IID& IId, void **UnknownPtrPtr) noexcept override
    {
        // Three rules of QueryInterface:
        // https://docs.microsoft.com/en-us/windows/win32/com/rules-for-implementing-queryinterface
        // 1. Objects must have identity.
        // 2. The set of interfaces on an object instance must be static.
        // 3. It must be possible to query successfully for any interface on an object from any other interface.

        // If ppvObject(the address) is nullptr, then this method returns E_POINTER.
        if(!UnknownPtrPtr)
            return E_POINTER;

        // https://docs.microsoft.com/en-us/windows/win32/com/implementing-reference-counting
        // Whenever a client calls a method(or API function), such as QueryInterface, that returns a new interface
        // pointer, the method being called is responsible for incrementing the reference count through the returned
        // pointer. For example, when a client first creates an object, it receives an interface pointer to an object
        // that, from the client's point of view, has a reference count of one. If the client then calls AddRef on the
        // interface pointer, the reference count becomes two. The client must call Release twice on the interface
        // pointer to drop all of its references to the object.
#if ALSOFT_UWP
        if(IId == __uuidof(IActivateAudioInterfaceCompletionHandler))
        {
            *UnknownPtrPtr = as<IActivateAudioInterfaceCompletionHandler*>();
            AddRef();
            return S_OK;
        }
#else
        if(IId == __uuidof(IMMNotificationClient))
        {
            *UnknownPtrPtr = as<IMMNotificationClient*>();
            AddRef();
            return S_OK;
        }
#endif
        else if(IId == __uuidof(IAgileObject) || IId == __uuidof(IUnknown))
        {
            *UnknownPtrPtr = as<IUnknown*>();
            AddRef();
            return S_OK;
        }

        // This method returns S_OK if the interface is supported, and E_NOINTERFACE otherwise.
        *UnknownPtrPtr = nullptr;
        return E_NOINTERFACE;
    }

#if ALSOFT_UWP
    /** ----------------------- IActivateAudioInterfaceCompletionHandler ------------ */
    HRESULT ActivateCompleted(IActivateAudioInterfaceAsyncOperation*) override
    {
        SetEvent(mActiveClientEvent);

        // Need to return S_OK
        return S_OK;
    }
#else
    /** ----------------------- IMMNotificationClient ------------ */
    STDMETHODIMP OnDeviceStateChanged(LPCWSTR /*pwstrDeviceId*/, DWORD /*dwNewState*/) noexcept override { return S_OK; }

    STDMETHODIMP OnDeviceAdded(LPCWSTR pwstrDeviceId) noexcept override
    {
        ComPtr<IMMDevice> device;
        HRESULT hr{mEnumerator->GetDevice(pwstrDeviceId, al::out_ptr(device))};
        if(FAILED(hr))
        {
            ERR("Failed to get device: 0x%08lx\n", hr);
            return S_OK;
        }

        ComPtr<IMMEndpoint> endpoint;
        hr = device->QueryInterface(__uuidof(IMMEndpoint), al::out_ptr(endpoint));
        if(FAILED(hr))
        {
            ERR("Failed to get device endpoint: 0x%08lx\n", hr);
            return S_OK;
        }

        EDataFlow flowdir{};
        hr = endpoint->GetDataFlow(&flowdir);
        if(FAILED(hr))
        {
            ERR("Failed to get endpoint data flow: 0x%08lx\n", hr);
            return S_OK;
        }

        auto devlock = DeviceListLock{gDeviceList};
        auto &list = (flowdir==eRender) ? devlock.getPlaybackList() : devlock.getCaptureList();

        if(AddDevice(device, pwstrDeviceId, list))
        {
            const auto devtype = (flowdir==eRender) ? alc::DeviceType::Playback
                : alc::DeviceType::Capture;
            const std::string msg{"Device added: "+list.back().name};
            alc::Event(alc::EventType::DeviceAdded, devtype, msg);
        }

        return S_OK;
    }

    STDMETHODIMP OnDeviceRemoved(LPCWSTR pwstrDeviceId) noexcept override
    {
        auto devlock = DeviceListLock{gDeviceList};
        for(auto flowdir : std::array{eRender, eCapture})
        {
            auto &list = (flowdir==eRender) ? devlock.getPlaybackList() : devlock.getCaptureList();
            auto devtype = (flowdir==eRender)?alc::DeviceType::Playback : alc::DeviceType::Capture;

            /* Find the ID in the list to remove. */
            auto iter = std::find_if(list.begin(), list.end(),
                [pwstrDeviceId](const DevMap &entry) noexcept
                { return pwstrDeviceId == entry.devid; });
            if(iter == list.end()) continue;

            TRACE("Removing device \"%s\", \"%s\", \"%ls\"\n", iter->name.c_str(),
                iter->endpoint_guid.c_str(), iter->devid.c_str());

            std::string msg{"Device removed: "+std::move(iter->name)};
            list.erase(iter);

            alc::Event(alc::EventType::DeviceRemoved, devtype, msg);
        }
        return S_OK;
    }

    /* NOLINTNEXTLINE(clazy-function-args-by-ref) */
    STDMETHODIMP OnPropertyValueChanged(LPCWSTR /*pwstrDeviceId*/, const PROPERTYKEY /*key*/) noexcept override { return S_OK; }

    STDMETHODIMP OnDefaultDeviceChanged(EDataFlow flow, ERole role, LPCWSTR pwstrDefaultDeviceId) noexcept override
    {
        if(role != eMultimedia)
            return S_OK;

        const std::wstring_view devid{pwstrDefaultDeviceId ? pwstrDefaultDeviceId
            : std::wstring_view{}};
        if(flow == eRender)
        {
            DeviceListLock{gDeviceList}.setPlaybackDefaultId(devid);
            const std::string msg{"Default playback device changed: " + wstr_to_utf8(devid)};
            alc::Event(alc::EventType::DefaultDeviceChanged, alc::DeviceType::Playback, msg);
        }
        else if(flow == eCapture)
        {
            DeviceListLock{gDeviceList}.setCaptureDefaultId(devid);
            const std::string msg{"Default capture device changed: " + wstr_to_utf8(devid)};
            alc::Event(alc::EventType::DefaultDeviceChanged, alc::DeviceType::Capture, msg);
        }
        return S_OK;
    }
#endif

    /** -------------------------- DeviceHelper ----------------------------- */
    HRESULT init()
    {
#if !ALSOFT_UWP
        HRESULT hr{CoCreateInstance(CLSID_MMDeviceEnumerator, nullptr, CLSCTX_INPROC_SERVER,
            __uuidof(IMMDeviceEnumerator), al::out_ptr(mEnumerator))};
        if(SUCCEEDED(hr))
            mEnumerator->RegisterEndpointNotificationCallback(this);
        else
            WARN("Failed to create IMMDeviceEnumerator instance: 0x%08lx\n", hr);
        return hr;
#else
        return S_OK;
#endif
    }

    HRESULT openDevice(std::wstring_view devid, EDataFlow flow, DeviceHandle& device)
    {
#if !ALSOFT_UWP
        HRESULT hr{E_FAIL};
        if(mEnumerator)
        {
            if(devid.empty())
                hr = mEnumerator->GetDefaultAudioEndpoint(flow, eMultimedia, al::out_ptr(device));
            else
                hr = mEnumerator->GetDevice(devid.data(), al::out_ptr(device));
        }
        return hr;
#else
        const auto deviceRole = Windows::Media::Devices::AudioDeviceRole::Default;
        auto devIfPath =
            devid.empty() ? (flow == eRender ? MediaDevice::GetDefaultAudioRenderId(deviceRole) : MediaDevice::GetDefaultAudioCaptureId(deviceRole))
            : winrt::hstring(devid.data());
        if (devIfPath.empty())
            return E_POINTER;

        auto&& deviceInfo = DeviceInformation::CreateFromIdAsync(devIfPath, nullptr, DeviceInformationKind::DeviceInterface).get();
        if (!deviceInfo)
            return E_NOINTERFACE;
        device = deviceInfo;
        return S_OK;
#endif
    }

#if !ALSOFT_UWP
    static HRESULT activateAudioClient(_In_ DeviceHandle &device, REFIID iid, void **ppv)
    { return device->Activate(iid, CLSCTX_INPROC_SERVER, nullptr, ppv); }
#else
    HRESULT activateAudioClient(_In_ DeviceHandle &device, _In_ REFIID iid, void **ppv)
    {
        ComPtr<IActivateAudioInterfaceAsyncOperation> asyncOp;
        HRESULT hr{ActivateAudioInterfaceAsync(device.Id().data(), iid, nullptr, this,
            al::out_ptr(asyncOp))};
        if(FAILED(hr))
            return hr;

        /* I don't like waiting for INFINITE time, but the activate operation
         * can take an indefinite amount of time since it can require user
         * input.
         */
        DWORD res{WaitForSingleObjectEx(mActiveClientEvent, INFINITE, FALSE)};
        if(res != WAIT_OBJECT_0)
        {
            ERR("WaitForSingleObjectEx error: 0x%lx\n", res);
            return E_FAIL;
        }

        HRESULT hrActivateRes{E_FAIL};
        ComPtr<IUnknown> punkAudioIface;
        hr = asyncOp->GetActivateResult(&hrActivateRes, al::out_ptr(punkAudioIface));
        if(SUCCEEDED(hr)) hr = hrActivateRes;
        if(FAILED(hr)) return hr;

        return punkAudioIface->QueryInterface(iid, ppv);
    }
#endif

    std::wstring probeDevices(EDataFlow flowdir, std::vector<DevMap> &list)
    {
        std::wstring defaultId;
        std::vector<DevMap>{}.swap(list);

#if !ALSOFT_UWP
        ComPtr<IMMDeviceCollection> coll;
        HRESULT hr{mEnumerator->EnumAudioEndpoints(flowdir, DEVICE_STATE_ACTIVE,
            al::out_ptr(coll))};
        if(FAILED(hr))
        {
            ERR("Failed to enumerate audio endpoints: 0x%08lx\n", hr);
            return defaultId;
        }

        UINT count{0};
        hr = coll->GetCount(&count);
        if(SUCCEEDED(hr) && count > 0)
            list.reserve(count);

        ComPtr<IMMDevice> device;
        hr = mEnumerator->GetDefaultAudioEndpoint(flowdir, eMultimedia, al::out_ptr(device));
        if(SUCCEEDED(hr))
        {
            if(WCHAR *devid{GetDeviceId(device.get())})
            {
                defaultId = devid;
                CoTaskMemFree(devid);
            }
            device = nullptr;
        }

        for(UINT i{0};i < count;++i)
        {
            hr = coll->Item(i, al::out_ptr(device));
            if(FAILED(hr))
                continue;

            if(WCHAR *devid{GetDeviceId(device.get())})
            {
                std::ignore = AddDevice(device, devid, list);
                CoTaskMemFree(devid);
            }
            device = nullptr;
        }
#else
        const auto deviceRole = Windows::Media::Devices::AudioDeviceRole::Default;
        auto DefaultAudioId   = flowdir == eRender ? MediaDevice::GetDefaultAudioRenderId(deviceRole)
                                                   : MediaDevice::GetDefaultAudioCaptureId(deviceRole);
        if(!DefaultAudioId.empty())
        {
            auto deviceInfo = DeviceInformation::CreateFromIdAsync(DefaultAudioId, nullptr,
                DeviceInformationKind::DeviceInterface).get();
            if(deviceInfo)
                defaultId = deviceInfo.Id().data();
        }

        // Get the string identifier of the audio renderer
        auto AudioSelector = flowdir == eRender ? MediaDevice::GetAudioRenderSelector() : MediaDevice::GetAudioCaptureSelector();

        // Setup the asynchronous callback
        auto&& DeviceInfoCollection = DeviceInformation::FindAllAsync(AudioSelector, /*PropertyList*/nullptr, DeviceInformationKind::DeviceInterface).get();
        if(DeviceInfoCollection)
        {
            try {
                auto deviceCount = DeviceInfoCollection.Size();
                for(unsigned int i{0};i < deviceCount;++i)
                {
                    auto deviceInfo = DeviceInfoCollection.GetAt(i);
                    if(deviceInfo)
                        std::ignore = AddDevice(deviceInfo, deviceInfo.Id().data(), list);
                }
            }
            catch (const winrt::hresult_error& /*ex*/) {
            }
        }
#endif

        return defaultId;
    }

private:
    static bool AddDevice(const DeviceHandle &device, const WCHAR *devid, std::vector<DevMap> &list)
    {
        for(auto &entry : list)
        {
            if(entry.devid == devid)
                return false;
        }

        auto name_guid = GetDeviceNameAndGuid(device);
        int count{1};
        std::string newname{name_guid.mName};
        while(checkName(list, newname))
        {
            newname = name_guid.mName;
            newname += " #";
            newname += std::to_string(++count);
        }
        list.emplace_back(std::move(newname), std::move(name_guid.mGuid), devid);
        const DevMap &newentry = list.back();

        TRACE("Got device \"%s\", \"%s\", \"%ls\"\n", newentry.name.c_str(),
            newentry.endpoint_guid.c_str(), newentry.devid.c_str());
        return true;
    }

#if !ALSOFT_UWP
    static WCHAR *GetDeviceId(IMMDevice *device)
    {
        WCHAR *devid;

        const HRESULT hr{device->GetId(&devid)};
        if(FAILED(hr))
        {
            ERR("Failed to get device id: %lx\n", hr);
            return nullptr;
        }

        return devid;
    }
    ComPtr<IMMDeviceEnumerator> mEnumerator{nullptr};

#else

    HANDLE mActiveClientEvent{nullptr};

    EventRegistrationToken mRenderDeviceChangedToken;
    EventRegistrationToken mCaptureDeviceChangedToken;
#endif
};

bool MakeExtensible(WAVEFORMATEXTENSIBLE *out, const WAVEFORMATEX *in)
{
    *out = WAVEFORMATEXTENSIBLE{};
    if(in->wFormatTag == WAVE_FORMAT_EXTENSIBLE)
    {
        *out = *CONTAINING_RECORD(in, const WAVEFORMATEXTENSIBLE, Format);
        out->Format.cbSize = sizeof(*out) - sizeof(out->Format);
    }
    else if(in->wFormatTag == WAVE_FORMAT_PCM)
    {
        out->Format = *in;
        out->Format.cbSize = 0;
        /* NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access) */
        out->Samples.wValidBitsPerSample = out->Format.wBitsPerSample;
        if(out->Format.nChannels == 1)
            out->dwChannelMask = MONO;
        else if(out->Format.nChannels == 2)
            out->dwChannelMask = STEREO;
        else
            ERR("Unhandled PCM channel count: %d\n", out->Format.nChannels);
        out->SubFormat = KSDATAFORMAT_SUBTYPE_PCM;
    }
    else if(in->wFormatTag == WAVE_FORMAT_IEEE_FLOAT)
    {
        out->Format = *in;
        out->Format.cbSize = 0;
        /* NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access) */
        out->Samples.wValidBitsPerSample = out->Format.wBitsPerSample;
        if(out->Format.nChannels == 1)
            out->dwChannelMask = MONO;
        else if(out->Format.nChannels == 2)
            out->dwChannelMask = STEREO;
        else
            ERR("Unhandled IEEE float channel count: %d\n", out->Format.nChannels);
        out->SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
    }
    else
    {
        ERR("Unhandled format tag: 0x%04x\n", in->wFormatTag);
        return false;
    }
    return true;
}

void TraceFormat(const char *msg, const WAVEFORMATEX *format)
{
    constexpr size_t fmtex_extra_size{sizeof(WAVEFORMATEXTENSIBLE)-sizeof(WAVEFORMATEX)};
    if(format->wFormatTag == WAVE_FORMAT_EXTENSIBLE && format->cbSize >= fmtex_extra_size)
    {
        const WAVEFORMATEXTENSIBLE *fmtex{
            CONTAINING_RECORD(format, const WAVEFORMATEXTENSIBLE, Format)};
        /* NOLINTBEGIN(cppcoreguidelines-pro-type-union-access) */
        TRACE("%s:\n"
            "    FormatTag      = 0x%04x\n"
            "    Channels       = %d\n"
            "    SamplesPerSec  = %lu\n"
            "    AvgBytesPerSec = %lu\n"
            "    BlockAlign     = %d\n"
            "    BitsPerSample  = %d\n"
            "    Size           = %d\n"
            "    Samples        = %d\n"
            "    ChannelMask    = 0x%lx\n"
            "    SubFormat      = %s\n",
            msg, fmtex->Format.wFormatTag, fmtex->Format.nChannels, fmtex->Format.nSamplesPerSec,
            fmtex->Format.nAvgBytesPerSec, fmtex->Format.nBlockAlign, fmtex->Format.wBitsPerSample,
            fmtex->Format.cbSize, fmtex->Samples.wReserved, fmtex->dwChannelMask,
            GuidPrinter{fmtex->SubFormat}.c_str());
        /* NOLINTEND(cppcoreguidelines-pro-type-union-access) */
    }
    else
        TRACE("%s:\n"
            "    FormatTag      = 0x%04x\n"
            "    Channels       = %d\n"
            "    SamplesPerSec  = %lu\n"
            "    AvgBytesPerSec = %lu\n"
            "    BlockAlign     = %d\n"
            "    BitsPerSample  = %d\n"
            "    Size           = %d\n",
            msg, format->wFormatTag, format->nChannels, format->nSamplesPerSec,
            format->nAvgBytesPerSec, format->nBlockAlign, format->wBitsPerSample, format->cbSize);
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


/* Proxy interface used by the message handler. */
struct WasapiProxy {
    WasapiProxy() = default;
    WasapiProxy(const WasapiProxy&) = delete;
    WasapiProxy(WasapiProxy&&) = delete;
    virtual ~WasapiProxy() = default;

    void operator=(const WasapiProxy&) = delete;
    void operator=(WasapiProxy&&) = delete;

    virtual HRESULT openProxy(std::string_view name) = 0;
    virtual void closeProxy() = 0;

    virtual HRESULT resetProxy() = 0;
    virtual HRESULT startProxy() = 0;
    virtual void stopProxy() = 0;

    struct Msg {
        MsgType mType;
        WasapiProxy *mProxy;
        std::string_view mParam;
        std::promise<HRESULT> mPromise;

        explicit operator bool() const noexcept { return mType != MsgType::QuitThread; }
    };
    static inline std::deque<Msg> mMsgQueue;
    static inline std::mutex mMsgQueueLock;
    static inline std::condition_variable mMsgQueueCond;
    static inline DWORD sAvIndex{};

    static inline std::optional<DeviceHelper> sDeviceHelper;

    std::future<HRESULT> pushMessage(MsgType type, std::string_view param={})
    {
        std::promise<HRESULT> promise;
        std::future<HRESULT> future{promise.get_future()};
        {
            std::lock_guard<std::mutex> msglock{mMsgQueueLock};
            mMsgQueue.emplace_back(Msg{type, this, param, std::move(promise)});
        }
        mMsgQueueCond.notify_one();
        return future;
    }

    static std::future<HRESULT> pushMessageStatic(MsgType type)
    {
        std::promise<HRESULT> promise;
        std::future<HRESULT> future{promise.get_future()};
        {
            std::lock_guard<std::mutex> msglock{mMsgQueueLock};
            mMsgQueue.emplace_back(Msg{type, nullptr, {}, std::move(promise)});
        }
        mMsgQueueCond.notify_one();
        return future;
    }

    static Msg popMessage()
    {
        std::unique_lock<std::mutex> lock{mMsgQueueLock};
        mMsgQueueCond.wait(lock, []{return !mMsgQueue.empty();});
        Msg msg{std::move(mMsgQueue.front())};
        mMsgQueue.pop_front();
        return msg;
    }

    static int messageHandler(std::promise<HRESULT> *promise);
};

int WasapiProxy::messageHandler(std::promise<HRESULT> *promise)
{
    TRACE("Starting message thread\n");

    ComWrapper com{COINIT_MULTITHREADED};
    if(!com)
    {
        WARN("Failed to initialize COM: 0x%08lx\n", com.status());
        promise->set_value(com.status());
        return 0;
    }

    struct HelperResetter {
        HelperResetter() = default;
        HelperResetter(const HelperResetter&) = delete;
        auto operator=(const HelperResetter&) -> HelperResetter& = delete;
        ~HelperResetter() { sDeviceHelper.reset(); }
    };
    HelperResetter scoped_watcher;

    HRESULT hr{sDeviceHelper.emplace().init()};
    promise->set_value(hr);
    promise = nullptr;
    if(FAILED(hr))
        return 0;

    {
        auto devlock = DeviceListLock{gDeviceList};
        auto defaultId = sDeviceHelper->probeDevices(eRender, devlock.getPlaybackList());
        if(!defaultId.empty()) devlock.setPlaybackDefaultId(defaultId);
        defaultId = sDeviceHelper->probeDevices(eCapture, devlock.getCaptureList());
        if(!defaultId.empty()) devlock.setCaptureDefaultId(defaultId);
    }

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

    return 0;
}

struct WasapiPlayback final : public BackendBase, WasapiProxy {
    WasapiPlayback(DeviceBase *device) noexcept : BackendBase{device} { }
    ~WasapiPlayback() override;

    int mixerProc();
    int mixerSpatialProc();

    void open(std::string_view name) override;
    HRESULT openProxy(std::string_view name) override;
    void closeProxy() override;

    bool reset() override;
    HRESULT resetProxy() override;
    void start() override;
    HRESULT startProxy() override;
    void stop() override;
    void stopProxy() override;

    ClockLatency getClockLatency() override;

    void prepareFormat(WAVEFORMATEXTENSIBLE &OutputType);
    void finalizeFormat(WAVEFORMATEXTENSIBLE &OutputType);

    auto initSpatial() -> bool;

    HRESULT mOpenStatus{E_FAIL};
    DeviceHandle mMMDev{nullptr};

    struct PlainDevice {
        ComPtr<IAudioClient> mClient{nullptr};
        ComPtr<IAudioRenderClient> mRender{nullptr};
    };
    struct SpatialDevice {
        ComPtr<ISpatialAudioClient> mClient{nullptr};
        ComPtr<ISpatialAudioObjectRenderStream> mRender{nullptr};
        AudioObjectType mStaticMask{};
    };
    std::variant<PlainDevice,SpatialDevice> mAudio{std::in_place_index_t<0>{}};
    HANDLE mNotifyEvent{nullptr};

    UINT32 mOutBufferSize{}, mOutUpdateSize{};
    std::vector<char> mResampleBuffer{};
    uint mBufferFilled{0};
    SampleConverterPtr mResampler;

    WAVEFORMATEXTENSIBLE mFormat{};
    std::atomic<UINT32> mPadding{0u};

    std::mutex mMutex;

    std::atomic<bool> mKillNow{true};
    std::thread mThread;
};

WasapiPlayback::~WasapiPlayback()
{
    if(SUCCEEDED(mOpenStatus))
        pushMessage(MsgType::CloseDevice).wait();
    mOpenStatus = E_FAIL;

    if(mNotifyEvent != nullptr)
        CloseHandle(mNotifyEvent);
    mNotifyEvent = nullptr;
}


FORCE_ALIGN int WasapiPlayback::mixerProc()
{
    ComWrapper com{COINIT_MULTITHREADED};
    if(!com)
    {
        ERR("CoInitializeEx(nullptr, COINIT_MULTITHREADED) failed: 0x%08lx\n", com.status());
        mDevice->handleDisconnect("COM init failed: 0x%08lx", com.status());
        return 1;
    }

    auto &audio = std::get<PlainDevice>(mAudio);

    SetRTPriority();
    althrd_setname(GetMixerThreadName());

    const uint frame_size{mFormat.Format.nChannels * mFormat.Format.wBitsPerSample / 8u};
    const uint update_size{mOutUpdateSize};
    const UINT32 buffer_len{mOutBufferSize};
    const void *resbufferptr{};

#ifdef AVRTAPI
    /* TODO: "Audio" or "Pro Audio"? The suggestion is to use "Pro Audio" for
     * device periods less than 10ms, and "Audio" for greater than or equal to
     * 10ms.
     */
    auto taskname = (update_size < mFormat.Format.nSamplesPerSec/100) ? L"Pro Audio" : L"Audio";
    auto avhandle = AvrtHandlePtr{AvSetMmThreadCharacteristicsW(taskname, &sAvIndex)};
#endif

    mBufferFilled = 0;
    while(!mKillNow.load(std::memory_order_relaxed))
    {
        UINT32 written;
        HRESULT hr{audio.mClient->GetCurrentPadding(&written)};
        if(FAILED(hr))
        {
            ERR("Failed to get padding: 0x%08lx\n", hr);
            mDevice->handleDisconnect("Failed to retrieve buffer padding: 0x%08lx", hr);
            break;
        }
        mPadding.store(written, std::memory_order_relaxed);

        uint len{buffer_len - written};
        if(len < update_size)
        {
            DWORD res{WaitForSingleObjectEx(mNotifyEvent, 2000, FALSE)};
            if(res != WAIT_OBJECT_0)
                ERR("WaitForSingleObjectEx error: 0x%lx\n", res);
            continue;
        }

        BYTE *buffer;
        hr = audio.mRender->GetBuffer(len, &buffer);
        if(SUCCEEDED(hr))
        {
            if(mResampler)
            {
                std::lock_guard<std::mutex> dlock{mMutex};
                auto dst = al::span{buffer, size_t{len}*frame_size};
                for(UINT32 done{0};done < len;)
                {
                    if(mBufferFilled == 0)
                    {
                        mDevice->renderSamples(mResampleBuffer.data(), mDevice->UpdateSize,
                            mFormat.Format.nChannels);
                        resbufferptr = mResampleBuffer.data();
                        mBufferFilled = mDevice->UpdateSize;
                    }

                    uint got{mResampler->convert(&resbufferptr, &mBufferFilled, dst.data(),
                        len-done)};
                    dst = dst.subspan(size_t{got}*frame_size);
                    done += got;

                    mPadding.store(written + done, std::memory_order_relaxed);
                }
            }
            else
            {
                std::lock_guard<std::mutex> dlock{mMutex};
                mDevice->renderSamples(buffer, len, mFormat.Format.nChannels);
                mPadding.store(written + len, std::memory_order_relaxed);
            }
            hr = audio.mRender->ReleaseBuffer(len, 0);
        }
        if(FAILED(hr))
        {
            ERR("Failed to buffer data: 0x%08lx\n", hr);
            mDevice->handleDisconnect("Failed to send playback samples: 0x%08lx", hr);
            break;
        }
    }
    mPadding.store(0u, std::memory_order_release);

    return 0;
}

FORCE_ALIGN int WasapiPlayback::mixerSpatialProc()
{
    ComWrapper com{COINIT_MULTITHREADED};
    if(!com)
    {
        ERR("CoInitializeEx(nullptr, COINIT_MULTITHREADED) failed: 0x%08lx\n", com.status());
        mDevice->handleDisconnect("COM init failed: 0x%08lx", com.status());
        return 1;
    }

    auto &audio = std::get<SpatialDevice>(mAudio);

    SetRTPriority();
    althrd_setname(GetMixerThreadName());

    std::vector<ComPtr<ISpatialAudioObject>> channels;
    std::vector<void*> buffers;
    std::vector<void*> resbuffers;
    std::vector<const void*> tmpbuffers;

#ifdef AVRTAPI
    auto taskname = (mOutUpdateSize < mFormat.Format.nSamplesPerSec/100) ? L"Pro Audio" : L"Audio";
    auto avhandle = AvrtHandlePtr{AvSetMmThreadCharacteristicsW(taskname, &sAvIndex)};
#endif

    /* TODO: Set mPadding appropriately. There doesn't seem to be a way to
     * update it dynamically based on the stream, so a fixed size may be the
     * best we can do.
     */
    mPadding.store(mOutBufferSize-mOutUpdateSize, std::memory_order_release);

    mBufferFilled = 0;
    while(!mKillNow.load(std::memory_order_relaxed))
    {
        if(DWORD res{WaitForSingleObjectEx(mNotifyEvent, 1000, FALSE)}; res != WAIT_OBJECT_0)
        {
            ERR("WaitForSingleObjectEx error: 0x%lx\n", res);

            HRESULT hr{audio.mRender->Reset()};
            if(FAILED(hr))
            {
                ERR("ISpatialAudioObjectRenderStream::Reset failed: 0x%08lx\n", hr);
                mDevice->handleDisconnect("Device lost: 0x%08lx", hr);
                break;
            }
        }

        UINT32 dynamicCount{}, framesToDo{};
        HRESULT hr{audio.mRender->BeginUpdatingAudioObjects(&dynamicCount, &framesToDo)};
        if(SUCCEEDED(hr))
        {
            if(channels.empty()) UNLIKELY
            {
                auto flags = as_unsigned(audio.mStaticMask);
                channels.reserve(as_unsigned(al::popcount(flags)));
                while(flags)
                {
                    auto id = decltype(flags){1} << al::countr_zero(flags);
                    flags &= ~id;

                    channels.emplace_back();
                    audio.mRender->ActivateSpatialAudioObject(static_cast<AudioObjectType>(id),
                        al::out_ptr(channels.back()));
                }
                buffers.resize(channels.size());
                if(mResampler)
                {
                    tmpbuffers.resize(buffers.size());
                    resbuffers.resize(buffers.size());
                    auto bufptr = mResampleBuffer.begin();
                    for(size_t i{0};i < tmpbuffers.size();++i)
                    {
                        resbuffers[i] = al::to_address(bufptr);
                        bufptr += ptrdiff_t(mDevice->UpdateSize*sizeof(float));
                    }
                }
            }

            /* We have to call to get each channel's buffer individually every
             * update, unfortunately.
             */
            std::transform(channels.cbegin(), channels.cend(), buffers.begin(),
                [](const ComPtr<ISpatialAudioObject> &obj) -> void*
                {
                    auto buffer = LPBYTE{};
                    auto size = UINT32{};
                    obj->GetBuffer(&buffer, &size);
                    return buffer;
                });

            if(!mResampler)
                mDevice->renderSamples(buffers, framesToDo);
            else
            {
                std::lock_guard<std::mutex> dlock{mMutex};
                for(UINT32 pos{0};pos < framesToDo;)
                {
                    if(mBufferFilled == 0)
                    {
                        mDevice->renderSamples(resbuffers, mDevice->UpdateSize);
                        std::copy(resbuffers.cbegin(), resbuffers.cend(), tmpbuffers.begin());
                        mBufferFilled = mDevice->UpdateSize;
                    }

                    const uint got{mResampler->convertPlanar(tmpbuffers.data(), &mBufferFilled,
                        buffers.data(), framesToDo-pos)};
                    for(auto &buf : buffers)
                        buf = static_cast<float*>(buf) + got; /* NOLINT(cppcoreguidelines-pro-bounds-pointer-arithmetic) */
                    pos += got;
                }
            }

            hr = audio.mRender->EndUpdatingAudioObjects();
        }

        if(FAILED(hr))
            ERR("Failed to update playback objects: 0x%08lx\n", hr);
    }
    mPadding.store(0u, std::memory_order_release);

    return 0;
}


void WasapiPlayback::open(std::string_view name)
{
    if(SUCCEEDED(mOpenStatus))
        throw al::backend_exception{al::backend_error::DeviceError,
            "Unexpected duplicate open call"};

    mNotifyEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if(mNotifyEvent == nullptr)
    {
        ERR("Failed to create notify events: %lu\n", GetLastError());
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to create notify events"};
    }

    mOpenStatus = pushMessage(MsgType::OpenDevice, name).get();
    if(FAILED(mOpenStatus))
        throw al::backend_exception{al::backend_error::DeviceError, "Device init failed: 0x%08lx",
            mOpenStatus};
}

HRESULT WasapiPlayback::openProxy(std::string_view name)
{
    std::string devname;
    std::wstring devid;
    if(!name.empty())
    {
        auto devlock = DeviceListLock{gDeviceList};
        auto list = al::span{devlock.getPlaybackList()};
        auto iter = std::find_if(list.cbegin(), list.cend(),
            [name](const DevMap &entry) -> bool
            { return entry.name == name || entry.endpoint_guid == name; });
        if(iter == list.cend())
        {
            const std::wstring wname{utf8_to_wstr(name)};
            iter = std::find_if(list.cbegin(), list.cend(),
                [&wname](const DevMap &entry) -> bool
                { return entry.devid == wname; });
        }
        if(iter == list.cend())
        {
            WARN("Failed to find device name matching \"%.*s\"\n", al::sizei(name), name.data());
            return E_FAIL;
        }
        devname = iter->name;
        devid = iter->devid;
    }

    HRESULT hr{sDeviceHelper->openDevice(devid, eRender, mMMDev)};
    if(FAILED(hr))
    {
        WARN("Failed to open device \"%s\"\n", devname.empty() ? "(default)" : devname.c_str());
        return hr;
    }
    if(!devname.empty())
        mDeviceName = std::move(devname);
    else
        mDeviceName = GetDeviceNameAndGuid(mMMDev).mName;

    return S_OK;
}

void WasapiPlayback::closeProxy()
{
    mAudio.emplace<PlainDevice>();
    mMMDev = nullptr;
}


void WasapiPlayback::prepareFormat(WAVEFORMATEXTENSIBLE &OutputType)
{
    bool isRear51{false};

    if(!mDevice->Flags.test(FrequencyRequest))
        mDevice->Frequency = OutputType.Format.nSamplesPerSec;
    if(!mDevice->Flags.test(ChannelsRequest))
    {
        /* If not requesting a channel configuration, auto-select given what
         * fits the mask's lsb (to ensure no gaps in the output channels). If
         * there's no mask, we can only assume mono or stereo.
         */
        const uint32_t chancount{OutputType.Format.nChannels};
        const DWORD chanmask{OutputType.dwChannelMask};
        if(chancount >= 12 && (chanmask&X714Mask) == X7DOT1DOT4)
            mDevice->FmtChans = DevFmtX714;
        else if(chancount >= 8 && (chanmask&X71Mask) == X7DOT1)
            mDevice->FmtChans = DevFmtX71;
        else if(chancount >= 7 && (chanmask&X61Mask) == X6DOT1)
            mDevice->FmtChans = DevFmtX61;
        else if(chancount >= 6 && (chanmask&X51Mask) == X5DOT1)
            mDevice->FmtChans = DevFmtX51;
        else if(chancount >= 6 && (chanmask&X51RearMask) == X5DOT1REAR)
        {
            mDevice->FmtChans = DevFmtX51;
            isRear51 = true;
        }
        else if(chancount >= 4 && (chanmask&QuadMask) == QUAD)
            mDevice->FmtChans = DevFmtQuad;
        else if(chancount >= 2 && ((chanmask&StereoMask) == STEREO || !chanmask))
            mDevice->FmtChans = DevFmtStereo;
        else if(chancount >= 1 && ((chanmask&MonoMask) == MONO || !chanmask))
            mDevice->FmtChans = DevFmtMono;
        else
            ERR("Unhandled channel config: %d -- 0x%08lx\n", chancount, chanmask);
    }
    else
    {
        const uint32_t chancount{OutputType.Format.nChannels};
        const DWORD chanmask{OutputType.dwChannelMask};
        isRear51 = (chancount == 6 && (chanmask&X51RearMask) == X5DOT1REAR);
    }

    OutputType.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    switch(mDevice->FmtChans)
    {
    case DevFmtMono:
        OutputType.Format.nChannels = 1;
        OutputType.dwChannelMask = MONO;
        break;
    case DevFmtAmbi3D:
        mDevice->FmtChans = DevFmtStereo;
        /*fall-through*/
    case DevFmtStereo:
        OutputType.Format.nChannels = 2;
        OutputType.dwChannelMask = STEREO;
        break;
    case DevFmtQuad:
        OutputType.Format.nChannels = 4;
        OutputType.dwChannelMask = QUAD;
        break;
    case DevFmtX51:
        OutputType.Format.nChannels = 6;
        OutputType.dwChannelMask = isRear51 ? X5DOT1REAR : X5DOT1;
        break;
    case DevFmtX61:
        OutputType.Format.nChannels = 7;
        OutputType.dwChannelMask = X6DOT1;
        break;
    case DevFmtX71:
    case DevFmtX3D71:
        OutputType.Format.nChannels = 8;
        OutputType.dwChannelMask = X7DOT1;
        break;
    case DevFmtX7144:
        mDevice->FmtChans = DevFmtX714;
        /*fall-through*/
    case DevFmtX714:
        OutputType.Format.nChannels = 12;
        OutputType.dwChannelMask = X7DOT1DOT4;
        break;
    }
    switch(mDevice->FmtType)
    {
    case DevFmtByte:
        mDevice->FmtType = DevFmtUByte;
        /* fall-through */
    case DevFmtUByte:
        OutputType.Format.wBitsPerSample = 8;
        OutputType.SubFormat = KSDATAFORMAT_SUBTYPE_PCM;
        break;
    case DevFmtUShort:
        mDevice->FmtType = DevFmtShort;
        /* fall-through */
    case DevFmtShort:
        OutputType.Format.wBitsPerSample = 16;
        OutputType.SubFormat = KSDATAFORMAT_SUBTYPE_PCM;
        break;
    case DevFmtUInt:
        mDevice->FmtType = DevFmtInt;
        /* fall-through */
    case DevFmtInt:
        OutputType.Format.wBitsPerSample = 32;
        OutputType.SubFormat = KSDATAFORMAT_SUBTYPE_PCM;
        break;
    case DevFmtFloat:
        OutputType.Format.wBitsPerSample = 32;
        OutputType.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
        break;
    }
    /* NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access) */
    OutputType.Samples.wValidBitsPerSample = OutputType.Format.wBitsPerSample;
    OutputType.Format.nSamplesPerSec = mDevice->Frequency;

    OutputType.Format.nBlockAlign = static_cast<WORD>(OutputType.Format.nChannels *
        OutputType.Format.wBitsPerSample / 8);
    OutputType.Format.nAvgBytesPerSec = OutputType.Format.nSamplesPerSec *
        OutputType.Format.nBlockAlign;
}

void WasapiPlayback::finalizeFormat(WAVEFORMATEXTENSIBLE &OutputType)
{
    if(!GetConfigValueBool(mDevice->mDeviceName, "wasapi", "allow-resampler", true))
        mDevice->Frequency = uint(OutputType.Format.nSamplesPerSec);
    else
        mDevice->Frequency = std::min(mDevice->Frequency, uint(OutputType.Format.nSamplesPerSec));

    const uint32_t chancount{OutputType.Format.nChannels};
    const DWORD chanmask{OutputType.dwChannelMask};
    /* Don't update the channel format if the requested format fits what's
     * supported.
     */
    bool chansok{false};
    if(mDevice->Flags.test(ChannelsRequest))
    {
        /* When requesting a channel configuration, make sure it fits the
         * mask's lsb (to ensure no gaps in the output channels). If there's no
         * mask, assume the request fits with enough channels.
         */
        switch(mDevice->FmtChans)
        {
        case DevFmtMono:
            chansok = (chancount >= 1 && ((chanmask&MonoMask) == MONO || !chanmask));
            break;
        case DevFmtStereo:
            chansok = (chancount >= 2 && ((chanmask&StereoMask) == STEREO || !chanmask));
            break;
        case DevFmtQuad:
            chansok = (chancount >= 4 && ((chanmask&QuadMask) == QUAD || !chanmask));
            break;
        case DevFmtX51:
            chansok = (chancount >= 6 && ((chanmask&X51Mask) == X5DOT1
                    || (chanmask&X51RearMask) == X5DOT1REAR || !chanmask));
            break;
        case DevFmtX61:
            chansok = (chancount >= 7 && ((chanmask&X61Mask) == X6DOT1 || !chanmask));
            break;
        case DevFmtX71:
        case DevFmtX3D71:
            chansok = (chancount >= 8 && ((chanmask&X71Mask) == X7DOT1 || !chanmask));
            break;
        case DevFmtX714:
            chansok = (chancount >= 12 && ((chanmask&X714Mask) == X7DOT1DOT4 || !chanmask));
        case DevFmtX7144:
        case DevFmtAmbi3D:
            break;
        }
    }
    if(!chansok)
    {
        if(chancount >= 12 && (chanmask&X714Mask) == X7DOT1DOT4)
            mDevice->FmtChans = DevFmtX714;
        else if(chancount >= 8 && (chanmask&X71Mask) == X7DOT1)
            mDevice->FmtChans = DevFmtX71;
        else if(chancount >= 7 && (chanmask&X61Mask) == X6DOT1)
            mDevice->FmtChans = DevFmtX61;
        else if(chancount >= 6 && ((chanmask&X51Mask) == X5DOT1
            || (chanmask&X51RearMask) == X5DOT1REAR))
            mDevice->FmtChans = DevFmtX51;
        else if(chancount >= 4 && (chanmask&QuadMask) == QUAD)
            mDevice->FmtChans = DevFmtQuad;
        else if(chancount >= 2 && ((chanmask&StereoMask) == STEREO || !chanmask))
            mDevice->FmtChans = DevFmtStereo;
        else if(chancount >= 1 && ((chanmask&MonoMask) == MONO || !chanmask))
            mDevice->FmtChans = DevFmtMono;
        else
        {
            ERR("Unhandled extensible channels: %d -- 0x%08lx\n", OutputType.Format.nChannels,
                OutputType.dwChannelMask);
            mDevice->FmtChans = DevFmtStereo;
            OutputType.Format.nChannels = 2;
            OutputType.dwChannelMask = STEREO;
        }
    }

    if(IsEqualGUID(OutputType.SubFormat, KSDATAFORMAT_SUBTYPE_PCM))
    {
        if(OutputType.Format.wBitsPerSample == 8)
            mDevice->FmtType = DevFmtUByte;
        else if(OutputType.Format.wBitsPerSample == 16)
            mDevice->FmtType = DevFmtShort;
        else if(OutputType.Format.wBitsPerSample == 32)
            mDevice->FmtType = DevFmtInt;
        else
        {
            mDevice->FmtType = DevFmtShort;
            OutputType.Format.wBitsPerSample = 16;
        }
    }
    else if(IsEqualGUID(OutputType.SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT))
    {
        mDevice->FmtType = DevFmtFloat;
        OutputType.Format.wBitsPerSample = 32;
    }
    else
    {
        ERR("Unhandled format sub-type: %s\n", GuidPrinter{OutputType.SubFormat}.c_str());
        mDevice->FmtType = DevFmtShort;
        if(OutputType.Format.wFormatTag != WAVE_FORMAT_EXTENSIBLE)
            OutputType.Format.wFormatTag = WAVE_FORMAT_PCM;
        OutputType.Format.wBitsPerSample = 16;
        OutputType.SubFormat = KSDATAFORMAT_SUBTYPE_PCM;
    }
    /* NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access) */
    OutputType.Samples.wValidBitsPerSample = OutputType.Format.wBitsPerSample;
}


auto WasapiPlayback::initSpatial() -> bool
{
    auto &audio = mAudio.emplace<SpatialDevice>();
    HRESULT hr{sDeviceHelper->activateAudioClient(mMMDev, __uuidof(ISpatialAudioClient),
        al::out_ptr(audio.mClient))};
    if(FAILED(hr))
    {
        ERR("Failed to activate spatial audio client: 0x%08lx\n", hr);
        return false;
    }

    ComPtr<IAudioFormatEnumerator> fmtenum;
    hr = audio.mClient->GetSupportedAudioObjectFormatEnumerator(al::out_ptr(fmtenum));
    if(FAILED(hr))
    {
        ERR("Failed to get format enumerator: 0x%08lx\n", hr);
        return false;
    }

    UINT32 fmtcount{};
    hr = fmtenum->GetCount(&fmtcount);
    if(FAILED(hr) || fmtcount == 0)
    {
        ERR("Failed to get format count: 0x%08lx\n", hr);
        return false;
    }

    WAVEFORMATEX *preferredFormat{};
    hr = fmtenum->GetFormat(0, &preferredFormat);
    if(FAILED(hr))
    {
        ERR("Failed to get preferred format: 0x%08lx\n", hr);
        return false;
    }
    TraceFormat("Preferred mix format", preferredFormat);

    UINT32 maxFrames{};
    hr = audio.mClient->GetMaxFrameCount(preferredFormat, &maxFrames);
    if(FAILED(hr))
        ERR("Failed to get max frames: 0x%08lx\n", hr);
    else
        TRACE("Max sample frames: %u\n", maxFrames);
    for(UINT32 i{1};i < fmtcount;++i)
    {
        WAVEFORMATEX *otherFormat{};
        hr = fmtenum->GetFormat(i, &otherFormat);
        if(FAILED(hr))
            ERR("Failed to format %u: 0x%08lx\n", i+1, hr);
        else
        {
            TraceFormat("Other mix format", otherFormat);
            UINT32 otherMaxFrames{};
            hr = audio.mClient->GetMaxFrameCount(otherFormat, &otherMaxFrames);
            if(FAILED(hr))
                ERR("Failed to get max frames: 0x%08lx\n", hr);
            else
                TRACE("Max sample frames: %u\n", otherMaxFrames);
        }
    }

    WAVEFORMATEXTENSIBLE OutputType;
    if(!MakeExtensible(&OutputType, preferredFormat))
        return false;

    /* This seems to be the format of each "object", which should be mono. */
    if(!(OutputType.Format.nChannels == 1
        && (OutputType.dwChannelMask == MONO || !OutputType.dwChannelMask)))
        ERR("Unhandled channel config: %d -- 0x%08lx\n", OutputType.Format.nChannels,
            OutputType.dwChannelMask);

    /* Force 32-bit float. This is currently required for planar output. */
    if(OutputType.Format.wFormatTag != WAVE_FORMAT_EXTENSIBLE
        && OutputType.Format.wFormatTag != WAVE_FORMAT_IEEE_FLOAT)
    {
        OutputType.Format.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
        OutputType.Format.cbSize = 0;
    }
    if(OutputType.Format.wBitsPerSample != 32)
    {
        OutputType.Format.nAvgBytesPerSec = OutputType.Format.nAvgBytesPerSec * 32u
            / OutputType.Format.wBitsPerSample;
        OutputType.Format.nBlockAlign = static_cast<WORD>(OutputType.Format.nBlockAlign * 32
            / OutputType.Format.wBitsPerSample);
        OutputType.Format.wBitsPerSample = 32;
    }
    /* NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access) */
    OutputType.Samples.wValidBitsPerSample = OutputType.Format.wBitsPerSample;
    OutputType.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;

    /* Match the output rate if not requesting anything specific. */
    if(!mDevice->Flags.test(FrequencyRequest))
        mDevice->Frequency = OutputType.Format.nSamplesPerSec;

    auto getTypeMask = [](DevFmtChannels chans) noexcept
    {
        switch(chans)
        {
        case DevFmtMono: return ChannelMask_Mono;
        case DevFmtStereo: return ChannelMask_Stereo;
        case DevFmtQuad: return ChannelMask_Quad;
        case DevFmtX51: return ChannelMask_X51;
        case DevFmtX61: return ChannelMask_X61;
        case DevFmtX3D71: [[fallthrough]];
        case DevFmtX71: return ChannelMask_X71;
        case DevFmtX714: return ChannelMask_X714;
        case DevFmtX7144: return ChannelMask_X7144;
        case DevFmtAmbi3D:
            break;
        }
        return ChannelMask_Stereo;
    };

    SpatialAudioObjectRenderStreamActivationParams streamParams{};
    streamParams.ObjectFormat = &OutputType.Format;
    streamParams.StaticObjectTypeMask = getTypeMask(mDevice->FmtChans);
    streamParams.Category = AudioCategory_Media;
    streamParams.EventHandle = mNotifyEvent;

    PropVariant paramProp{};
    paramProp.setBlob({reinterpret_cast<BYTE*>(&streamParams), sizeof(streamParams)});

    hr = audio.mClient->ActivateSpatialAudioStream(paramProp.get(),
        __uuidof(ISpatialAudioObjectRenderStream), al::out_ptr(audio.mRender));
    if(FAILED(hr))
    {
        ERR("Failed to activate spatial audio stream: 0x%08lx\n", hr);
        return false;
    }

    audio.mStaticMask = streamParams.StaticObjectTypeMask;
    mFormat = OutputType;

    mDevice->FmtType = DevFmtFloat;
    mDevice->Flags.reset(DirectEar).set(Virtualization);
    if(streamParams.StaticObjectTypeMask == ChannelMask_Stereo)
        mDevice->FmtChans = DevFmtStereo;
    if(!GetConfigValueBool(mDevice->mDeviceName, "wasapi", "allow-resampler", true))
        mDevice->Frequency = uint(OutputType.Format.nSamplesPerSec);
    else
        mDevice->Frequency = std::min(mDevice->Frequency,
            uint(OutputType.Format.nSamplesPerSec));

    setDefaultWFXChannelOrder();

    /* FIXME: Get the real update and buffer size. Presumably the actual device
     * is configured once ActivateSpatialAudioStream succeeds, and an
     * IAudioClient from the same IMMDevice accesses the same device
     * configuration. This isn't obviously correct, but for now assume
     * IAudioClient::GetDevicePeriod returns the current device period time
     * that ISpatialAudioObjectRenderStream will try to wake up at.
     *
     * Unfortunately this won't get the buffer size of the
     * ISpatialAudioObjectRenderStream, so we only assume there's two periods.
     */
    mOutUpdateSize = mDevice->UpdateSize;
    mOutBufferSize = mOutUpdateSize*2;
    ReferenceTime per_time{ReferenceTime{seconds{mDevice->UpdateSize}} / mDevice->Frequency};

    ComPtr<IAudioClient> tmpClient;
    hr = sDeviceHelper->activateAudioClient(mMMDev, __uuidof(IAudioClient),
        al::out_ptr(tmpClient));
    if(FAILED(hr))
        ERR("Failed to activate audio client: 0x%08lx\n", hr);
    else
    {
        hr = tmpClient->GetDevicePeriod(&reinterpret_cast<REFERENCE_TIME&>(per_time), nullptr);
        if(FAILED(hr))
            ERR("Failed to get device period: 0x%08lx\n", hr);
        else
        {
            mOutUpdateSize = RefTime2Samples(per_time, mFormat.Format.nSamplesPerSec);
            mOutBufferSize = mOutUpdateSize*2;
        }
    }
    tmpClient = nullptr;

    mDevice->UpdateSize = RefTime2Samples(per_time, mDevice->Frequency);
    mDevice->BufferSize = mDevice->UpdateSize*2;

    mResampler = nullptr;
    mResampleBuffer.clear();
    mResampleBuffer.shrink_to_fit();
    mBufferFilled = 0;
    if(mDevice->Frequency != mFormat.Format.nSamplesPerSec)
    {
        const auto flags = as_unsigned(streamParams.StaticObjectTypeMask);
        const auto channelCount = as_unsigned(al::popcount(flags));
        mResampler = SampleConverter::Create(mDevice->FmtType, mDevice->FmtType, channelCount,
            mDevice->Frequency, mFormat.Format.nSamplesPerSec, Resampler::FastBSinc24);
        mResampleBuffer.resize(size_t{mDevice->UpdateSize} * channelCount *
            mFormat.Format.wBitsPerSample / 8);

        TRACE("Created converter for %s/%s format, dst: %luhz (%u), src: %uhz (%u)\n",
            DevFmtChannelsString(mDevice->FmtChans), DevFmtTypeString(mDevice->FmtType),
            mFormat.Format.nSamplesPerSec, mOutUpdateSize, mDevice->Frequency,
            mDevice->UpdateSize);
    }

    return true;
}

bool WasapiPlayback::reset()
{
    HRESULT hr{pushMessage(MsgType::ResetDevice).get()};
    if(FAILED(hr))
        throw al::backend_exception{al::backend_error::DeviceError, "0x%08lx", hr};
    return true;
}

HRESULT WasapiPlayback::resetProxy()
{
    if(GetConfigValueBool(mDevice->mDeviceName, "wasapi", "spatial-api", false))
    {
        if(initSpatial())
            return S_OK;
    }

    mDevice->Flags.reset(Virtualization);

    auto &audio = mAudio.emplace<PlainDevice>();
    HRESULT hr{sDeviceHelper->activateAudioClient(mMMDev, __uuidof(IAudioClient),
        al::out_ptr(audio.mClient))};
    if(FAILED(hr))
    {
        ERR("Failed to reactivate audio client: 0x%08lx\n", hr);
        return hr;
    }

    WAVEFORMATEX *wfx;
    hr = audio.mClient->GetMixFormat(&wfx);
    if(FAILED(hr))
    {
        ERR("Failed to get mix format: 0x%08lx\n", hr);
        return hr;
    }
    TraceFormat("Device mix format", wfx);

    WAVEFORMATEXTENSIBLE OutputType;
    if(!MakeExtensible(&OutputType, wfx))
    {
        CoTaskMemFree(wfx);
        return E_FAIL;
    }
    CoTaskMemFree(wfx);
    wfx = nullptr;

    const ReferenceTime per_time{ReferenceTime{seconds{mDevice->UpdateSize}} / mDevice->Frequency};
    const ReferenceTime buf_time{ReferenceTime{seconds{mDevice->BufferSize}} / mDevice->Frequency};

    prepareFormat(OutputType);

    TraceFormat("Requesting playback format", &OutputType.Format);
    hr = audio.mClient->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &OutputType.Format, &wfx);
    if(FAILED(hr))
    {
        WARN("Failed to check format support: 0x%08lx\n", hr);
        hr = audio.mClient->GetMixFormat(&wfx);
    }
    if(FAILED(hr))
    {
        ERR("Failed to find a supported format: 0x%08lx\n", hr);
        return hr;
    }

    if(wfx != nullptr)
    {
        TraceFormat("Got playback format", wfx);
        if(!MakeExtensible(&OutputType, wfx))
        {
            CoTaskMemFree(wfx);
            return E_FAIL;
        }
        CoTaskMemFree(wfx);
        wfx = nullptr;

        finalizeFormat(OutputType);
    }
    mFormat = OutputType;

#if !ALSOFT_UWP
    const EndpointFormFactor formfactor{GetDeviceFormfactor(mMMDev.get())};
    mDevice->Flags.set(DirectEar, (formfactor == Headphones || formfactor == Headset));
#else
    mDevice->Flags.set(DirectEar, false);
#endif
    setDefaultWFXChannelOrder();

    hr = audio.mClient->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
        buf_time.count(), 0, &OutputType.Format, nullptr);
    if(FAILED(hr))
    {
        ERR("Failed to initialize audio client: 0x%08lx\n", hr);
        return hr;
    }

    UINT32 buffer_len{};
    ReferenceTime min_per{};
    hr = audio.mClient->GetDevicePeriod(&reinterpret_cast<REFERENCE_TIME&>(min_per), nullptr);
    if(SUCCEEDED(hr))
        hr = audio.mClient->GetBufferSize(&buffer_len);
    if(FAILED(hr))
    {
        ERR("Failed to get audio buffer info: 0x%08lx\n", hr);
        return hr;
    }

    hr = audio.mClient->SetEventHandle(mNotifyEvent);
    if(FAILED(hr))
    {
        ERR("Failed to set event handle: 0x%08lx\n", hr);
        return hr;
    }

    hr = audio.mClient->GetService(__uuidof(IAudioRenderClient), al::out_ptr(audio.mRender));
    if(FAILED(hr))
    {
        ERR("Failed to get IAudioRenderClient: 0x%08lx\n", hr);
        return hr;
    }

    /* Find the nearest multiple of the period size to the update size */
    if(min_per < per_time)
        min_per *= std::max<int64_t>((per_time + min_per/2) / min_per, 1_i64);

    mOutBufferSize = buffer_len;
    mOutUpdateSize = std::min(RefTime2Samples(min_per, mFormat.Format.nSamplesPerSec),
        buffer_len/2u);

    mDevice->BufferSize = static_cast<uint>(uint64_t{buffer_len} * mDevice->Frequency /
        mFormat.Format.nSamplesPerSec);
    mDevice->UpdateSize = std::min(RefTime2Samples(min_per, mDevice->Frequency),
        mDevice->BufferSize/2u);

    mResampler = nullptr;
    mResampleBuffer.clear();
    mResampleBuffer.shrink_to_fit();
    mBufferFilled = 0;
    if(mDevice->Frequency != mFormat.Format.nSamplesPerSec)
    {
        mResampler = SampleConverter::Create(mDevice->FmtType, mDevice->FmtType,
            mFormat.Format.nChannels, mDevice->Frequency, mFormat.Format.nSamplesPerSec,
            Resampler::FastBSinc24);
        mResampleBuffer.resize(size_t{mDevice->UpdateSize} * mFormat.Format.nChannels *
            mFormat.Format.wBitsPerSample / 8);

        TRACE("Created converter for %s/%s format, dst: %luhz (%u), src: %uhz (%u)\n",
            DevFmtChannelsString(mDevice->FmtChans), DevFmtTypeString(mDevice->FmtType),
            mFormat.Format.nSamplesPerSec, mOutUpdateSize, mDevice->Frequency,
            mDevice->UpdateSize);
    }

    return hr;
}


void WasapiPlayback::start()
{
    const HRESULT hr{pushMessage(MsgType::StartDevice).get()};
    if(FAILED(hr))
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to start playback: 0x%lx", hr};
}

HRESULT WasapiPlayback::startProxy()
{
    ResetEvent(mNotifyEvent);

    auto start_plain = [&](PlainDevice &audio) -> HRESULT
    {
        HRESULT hr{audio.mClient->Start()};
        if(FAILED(hr))
        {
            ERR("Failed to start audio client: 0x%08lx\n", hr);
            return hr;
        }

        try {
            mKillNow.store(false, std::memory_order_release);
            mThread = std::thread{std::mem_fn(&WasapiPlayback::mixerProc), this};
        }
        catch(...) {
            ERR("Failed to start thread\n");
            audio.mClient->Stop();
            hr = E_FAIL;
        }
        return hr;
    };
    auto start_spatial = [&](SpatialDevice &audio) -> HRESULT
    {
        HRESULT hr{audio.mRender->Start()};
        if(FAILED(hr))
        {
            ERR("Failed to start spatial audio stream: 0x%08lx\n", hr);
            return hr;
        }

        try {
            mKillNow.store(false, std::memory_order_release);
            mThread = std::thread{std::mem_fn(&WasapiPlayback::mixerSpatialProc), this};
        }
        catch(...) {
            ERR("Failed to start thread\n");
            hr = E_FAIL;
        }

        if(FAILED(hr))
        {
            audio.mRender->Stop();
            audio.mRender->Reset();
        }
        return hr;
    };

    return std::visit(overloaded{start_plain, start_spatial}, mAudio);
}


void WasapiPlayback::stop()
{ pushMessage(MsgType::StopDevice).wait(); }

void WasapiPlayback::stopProxy()
{
    if(!mThread.joinable())
        return;

    mKillNow.store(true, std::memory_order_release);
    mThread.join();

    auto stop_plain = [](PlainDevice &audio) -> void
    { audio.mClient->Stop(); };
    auto stop_spatial = [](SpatialDevice &audio) -> void
    {
        audio.mRender->Stop();
        audio.mRender->Reset();
    };
    std::visit(overloaded{stop_plain, stop_spatial}, mAudio);
}


ClockLatency WasapiPlayback::getClockLatency()
{
    std::lock_guard<std::mutex> dlock{mMutex};
    ClockLatency ret{};
    ret.ClockTime = mDevice->getClockTime();
    ret.Latency  = seconds{mPadding.load(std::memory_order_relaxed)};
    ret.Latency /= mFormat.Format.nSamplesPerSec;
    if(mResampler)
    {
        auto extra = mResampler->currentInputDelay();
        ret.Latency += std::chrono::duration_cast<nanoseconds>(extra) / mDevice->Frequency;
        ret.Latency += nanoseconds{seconds{mBufferFilled}} / mDevice->Frequency;
    }

    return ret;
}


struct WasapiCapture final : public BackendBase, WasapiProxy {
    WasapiCapture(DeviceBase *device) noexcept : BackendBase{device} { }
    ~WasapiCapture() override;

    int recordProc();

    void open(std::string_view name) override;
    HRESULT openProxy(std::string_view name) override;
    void closeProxy() override;

    HRESULT resetProxy() override;
    void start() override;
    HRESULT startProxy() override;
    void stop() override;
    void stopProxy() override;

    void captureSamples(std::byte *buffer, uint samples) override;
    uint availableSamples() override;

    HRESULT mOpenStatus{E_FAIL};
    DeviceHandle mMMDev{nullptr};
    ComPtr<IAudioClient> mClient{nullptr};
    ComPtr<IAudioCaptureClient> mCapture{nullptr};
    HANDLE mNotifyEvent{nullptr};

    ChannelConverter mChannelConv{};
    SampleConverterPtr mSampleConv;
    RingBufferPtr mRing;

    std::atomic<bool> mKillNow{true};
    std::thread mThread;
};

WasapiCapture::~WasapiCapture()
{
    if(SUCCEEDED(mOpenStatus))
        pushMessage(MsgType::CloseDevice).wait();
    mOpenStatus = E_FAIL;

    if(mNotifyEvent != nullptr)
        CloseHandle(mNotifyEvent);
    mNotifyEvent = nullptr;
}


FORCE_ALIGN int WasapiCapture::recordProc()
{
    ComWrapper com{COINIT_MULTITHREADED};
    if(!com)
    {
        ERR("CoInitializeEx(nullptr, COINIT_MULTITHREADED) failed: 0x%08lx\n", com.status());
        mDevice->handleDisconnect("COM init failed: 0x%08lx", com.status());
        return 1;
    }

    althrd_setname(GetRecordThreadName());

    std::vector<float> samples;
    while(!mKillNow.load(std::memory_order_relaxed))
    {
        UINT32 avail;
        HRESULT hr{mCapture->GetNextPacketSize(&avail)};
        if(FAILED(hr))
            ERR("Failed to get next packet size: 0x%08lx\n", hr);
        else if(avail > 0)
        {
            UINT32 numsamples;
            DWORD flags;
            BYTE *rdata;

            hr = mCapture->GetBuffer(&rdata, &numsamples, &flags, nullptr, nullptr);
            if(FAILED(hr))
                ERR("Failed to get capture buffer: 0x%08lx\n", hr);
            else
            {
                if(mChannelConv.is_active())
                {
                    samples.resize(numsamples*2_uz);
                    mChannelConv.convert(rdata, samples.data(), numsamples);
                    rdata = reinterpret_cast<BYTE*>(samples.data());
                }

                auto data = mRing->getWriteVector();

                size_t dstframes;
                if(mSampleConv)
                {
                    static constexpr auto lenlimit = size_t{std::numeric_limits<int>::max()};
                    const void *srcdata{rdata};
                    uint srcframes{numsamples};

                    dstframes = mSampleConv->convert(&srcdata, &srcframes, data[0].buf,
                        static_cast<uint>(std::min(data[0].len, lenlimit)));
                    if(srcframes > 0 && dstframes == data[0].len && data[1].len > 0)
                    {
                        /* If some source samples remain, all of the first dest
                         * block was filled, and there's space in the second
                         * dest block, do another run for the second block.
                         */
                        dstframes += mSampleConv->convert(&srcdata, &srcframes, data[1].buf,
                            static_cast<uint>(std::min(data[1].len, lenlimit)));
                    }
                }
                else
                {
                    const uint framesize{mDevice->frameSizeFromFmt()};
                    auto dst = al::span{rdata, size_t{numsamples}*framesize};
                    size_t len1{std::min(data[0].len, size_t{numsamples})};
                    size_t len2{std::min(data[1].len, numsamples-len1)};

                    memcpy(data[0].buf, dst.data(), len1*framesize);
                    if(len2 > 0)
                    {
                        dst = dst.subspan(len1*framesize);
                        memcpy(data[1].buf, dst.data(), len2*framesize);
                    }
                    dstframes = len1 + len2;
                }

                mRing->writeAdvance(dstframes);

                hr = mCapture->ReleaseBuffer(numsamples);
                if(FAILED(hr)) ERR("Failed to release capture buffer: 0x%08lx\n", hr);
            }
        }

        if(FAILED(hr))
        {
            mDevice->handleDisconnect("Failed to capture samples: 0x%08lx", hr);
            break;
        }

        DWORD res{WaitForSingleObjectEx(mNotifyEvent, 2000, FALSE)};
        if(res != WAIT_OBJECT_0)
            ERR("WaitForSingleObjectEx error: 0x%lx\n", res);
    }

    return 0;
}


void WasapiCapture::open(std::string_view name)
{
    if(SUCCEEDED(mOpenStatus))
        throw al::backend_exception{al::backend_error::DeviceError,
            "Unexpected duplicate open call"};

    mNotifyEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if(mNotifyEvent == nullptr)
    {
        ERR("Failed to create notify events: %lu\n", GetLastError());
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to create notify events"};
    }

    mOpenStatus = pushMessage(MsgType::OpenDevice, name).get();
    if(FAILED(mOpenStatus))
        throw al::backend_exception{al::backend_error::DeviceError, "Device init failed: 0x%08lx",
            mOpenStatus};

    HRESULT hr{pushMessage(MsgType::ResetDevice).get()};
    if(FAILED(hr))
    {
        if(hr == E_OUTOFMEMORY)
            throw al::backend_exception{al::backend_error::OutOfMemory, "Out of memory"};
        throw al::backend_exception{al::backend_error::DeviceError, "Device reset failed"};
    }
}

HRESULT WasapiCapture::openProxy(std::string_view name)
{
    std::string devname;
    std::wstring devid;
    if(!name.empty())
    {
        auto devlock = DeviceListLock{gDeviceList};
        auto devlist = al::span{devlock.getCaptureList()};
        auto iter = std::find_if(devlist.cbegin(), devlist.cend(),
            [name](const DevMap &entry) -> bool
            { return entry.name == name || entry.endpoint_guid == name; });
        if(iter == devlist.cend())
        {
            const std::wstring wname{utf8_to_wstr(name)};
            iter = std::find_if(devlist.cbegin(), devlist.cend(),
                [&wname](const DevMap &entry) -> bool
                { return entry.devid == wname; });
        }
        if(iter == devlist.cend())
        {
            WARN("Failed to find device name matching \"%.*s\"\n", al::sizei(name), name.data());
            return E_FAIL;
        }
        devname = iter->name;
        devid = iter->devid;
    }

    HRESULT hr{sDeviceHelper->openDevice(devid, eCapture, mMMDev)};
    if(FAILED(hr))
    {
        WARN("Failed to open device \"%s\"\n", devname.empty() ? "(default)" : devname.c_str());
        return hr;
    }
    mClient = nullptr;
    if(!devname.empty())
        mDeviceName = std::move(devname);
    else
        mDeviceName = GetDeviceNameAndGuid(mMMDev).mName;

    return S_OK;
}

void WasapiCapture::closeProxy()
{
    mCapture = nullptr;
    mClient = nullptr;
    mMMDev = nullptr;
}

HRESULT WasapiCapture::resetProxy()
{
    mCapture = nullptr;
    mClient = nullptr;

    HRESULT hr{sDeviceHelper->activateAudioClient(mMMDev, __uuidof(IAudioClient),
        al::out_ptr(mClient))};
    if(FAILED(hr))
    {
        ERR("Failed to reactivate audio client: 0x%08lx\n", hr);
        return hr;
    }

    WAVEFORMATEX *wfx;
    hr = mClient->GetMixFormat(&wfx);
    if(FAILED(hr))
    {
        ERR("Failed to get capture format: 0x%08lx\n", hr);
        return hr;
    }
    TraceFormat("Device capture format", wfx);

    WAVEFORMATEXTENSIBLE InputType{};
    if(!MakeExtensible(&InputType, wfx))
    {
        CoTaskMemFree(wfx);
        return E_FAIL;
    }
    CoTaskMemFree(wfx);
    wfx = nullptr;

    const bool isRear51{InputType.Format.nChannels == 6
        && (InputType.dwChannelMask&X51RearMask) == X5DOT1REAR};

    // Make sure buffer is at least 100ms in size
    ReferenceTime buf_time{ReferenceTime{seconds{mDevice->BufferSize}} / mDevice->Frequency};
    buf_time = std::max(buf_time, ReferenceTime{milliseconds{100}});

    InputType = {};
    InputType.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    switch(mDevice->FmtChans)
    {
    case DevFmtMono:
        InputType.Format.nChannels = 1;
        InputType.dwChannelMask = MONO;
        break;
    case DevFmtStereo:
        InputType.Format.nChannels = 2;
        InputType.dwChannelMask = STEREO;
        break;
    case DevFmtQuad:
        InputType.Format.nChannels = 4;
        InputType.dwChannelMask = QUAD;
        break;
    case DevFmtX51:
        InputType.Format.nChannels = 6;
        InputType.dwChannelMask = isRear51 ? X5DOT1REAR : X5DOT1;
        break;
    case DevFmtX61:
        InputType.Format.nChannels = 7;
        InputType.dwChannelMask = X6DOT1;
        break;
    case DevFmtX71:
        InputType.Format.nChannels = 8;
        InputType.dwChannelMask = X7DOT1;
        break;
    case DevFmtX714:
        InputType.Format.nChannels = 12;
        InputType.dwChannelMask = X7DOT1DOT4;
        break;

    case DevFmtX7144:
    case DevFmtX3D71:
    case DevFmtAmbi3D:
        return E_FAIL;
    }
    switch(mDevice->FmtType)
    {
    /* NOTE: Signedness doesn't matter, the converter will handle it. */
    case DevFmtByte:
    case DevFmtUByte:
        InputType.Format.wBitsPerSample = 8;
        InputType.SubFormat = KSDATAFORMAT_SUBTYPE_PCM;
        break;
    case DevFmtShort:
    case DevFmtUShort:
        InputType.Format.wBitsPerSample = 16;
        InputType.SubFormat = KSDATAFORMAT_SUBTYPE_PCM;
        break;
    case DevFmtInt:
    case DevFmtUInt:
        InputType.Format.wBitsPerSample = 32;
        InputType.SubFormat = KSDATAFORMAT_SUBTYPE_PCM;
        break;
    case DevFmtFloat:
        InputType.Format.wBitsPerSample = 32;
        InputType.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
        break;
    }
    /* NOLINTNEXTLINE(cppcoreguidelines-pro-type-union-access) */
    InputType.Samples.wValidBitsPerSample = InputType.Format.wBitsPerSample;
    InputType.Format.nSamplesPerSec = mDevice->Frequency;

    InputType.Format.nBlockAlign = static_cast<WORD>(InputType.Format.nChannels *
        InputType.Format.wBitsPerSample / 8);
    InputType.Format.nAvgBytesPerSec = InputType.Format.nSamplesPerSec *
        InputType.Format.nBlockAlign;
    InputType.Format.cbSize = sizeof(InputType) - sizeof(InputType.Format);

    TraceFormat("Requesting capture format", &InputType.Format);
    hr = mClient->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &InputType.Format, &wfx);
    if(FAILED(hr))
    {
        WARN("Failed to check capture format support: 0x%08lx\n", hr);
        hr = mClient->GetMixFormat(&wfx);
    }
    if(FAILED(hr))
    {
        ERR("Failed to find a supported capture format: 0x%08lx\n", hr);
        return hr;
    }

    mSampleConv = nullptr;
    mChannelConv = {};

    if(wfx != nullptr)
    {
        TraceFormat("Got capture format", wfx);
        if(!MakeExtensible(&InputType, wfx))
        {
            CoTaskMemFree(wfx);
            return E_FAIL;
        }
        CoTaskMemFree(wfx);
        wfx = nullptr;

        auto validate_fmt = [](DeviceBase *device, uint32_t chancount, DWORD chanmask) noexcept
            -> bool
        {
            switch(device->FmtChans)
            {
            /* If the device wants mono, we can handle any input. */
            case DevFmtMono:
                return true;
            /* If the device wants stereo, we can handle mono or stereo input. */
            case DevFmtStereo:
                return (chancount == 2 && (chanmask == 0 || (chanmask&StereoMask) == STEREO))
                    || (chancount == 1 && (chanmask&MonoMask) == MONO);
            /* Otherwise, the device must match the input type. */
            case DevFmtQuad:
                return (chancount == 4 && (chanmask == 0 || (chanmask&QuadMask) == QUAD));
            /* 5.1 (Side) and 5.1 (Rear) are interchangeable here. */
            case DevFmtX51:
                return (chancount == 6 && (chanmask == 0 || (chanmask&X51Mask) == X5DOT1
                        || (chanmask&X51RearMask) == X5DOT1REAR));
            case DevFmtX61:
                return (chancount == 7 && (chanmask == 0 || (chanmask&X61Mask) == X6DOT1));
            case DevFmtX71:
            case DevFmtX3D71:
                return (chancount == 8 && (chanmask == 0 || (chanmask&X71Mask) == X7DOT1));
            case DevFmtX714:
                return (chancount == 12 && (chanmask == 0 || (chanmask&X714Mask) == X7DOT1DOT4));
            case DevFmtX7144:
                return (chancount == 16 && chanmask == 0);
            case DevFmtAmbi3D:
                return (chanmask == 0 && chancount == device->channelsFromFmt());
            }
            return false;
        };
        if(!validate_fmt(mDevice, InputType.Format.nChannels, InputType.dwChannelMask))
        {
            ERR("Failed to match format, wanted: %s %s %uhz, got: 0x%08lx mask %d channel%s %d-bit %luhz\n",
                DevFmtChannelsString(mDevice->FmtChans), DevFmtTypeString(mDevice->FmtType),
                mDevice->Frequency, InputType.dwChannelMask, InputType.Format.nChannels,
                (InputType.Format.nChannels==1)?"":"s", InputType.Format.wBitsPerSample,
                InputType.Format.nSamplesPerSec);
            return E_FAIL;
        }
    }

    DevFmtType srcType{};
    if(IsEqualGUID(InputType.SubFormat, KSDATAFORMAT_SUBTYPE_PCM))
    {
        if(InputType.Format.wBitsPerSample == 8)
            srcType = DevFmtUByte;
        else if(InputType.Format.wBitsPerSample == 16)
            srcType = DevFmtShort;
        else if(InputType.Format.wBitsPerSample == 32)
            srcType = DevFmtInt;
        else
        {
            ERR("Unhandled integer bit depth: %d\n", InputType.Format.wBitsPerSample);
            return E_FAIL;
        }
    }
    else if(IsEqualGUID(InputType.SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT))
    {
        if(InputType.Format.wBitsPerSample == 32)
            srcType = DevFmtFloat;
        else
        {
            ERR("Unhandled float bit depth: %d\n", InputType.Format.wBitsPerSample);
            return E_FAIL;
        }
    }
    else
    {
        ERR("Unhandled format sub-type: %s\n", GuidPrinter{InputType.SubFormat}.c_str());
        return E_FAIL;
    }

    if(mDevice->FmtChans == DevFmtMono && InputType.Format.nChannels != 1)
    {
        uint chanmask{(1u<<InputType.Format.nChannels) - 1u};
        /* Exclude LFE from the downmix. */
        if((InputType.dwChannelMask&SPEAKER_LOW_FREQUENCY))
        {
            constexpr auto lfemask = MaskFromTopBits(SPEAKER_LOW_FREQUENCY);
            const int lfeidx{al::popcount(InputType.dwChannelMask&lfemask) - 1};
            chanmask &= ~(1u << lfeidx);
        }

        mChannelConv = ChannelConverter{srcType, InputType.Format.nChannels, chanmask,
            mDevice->FmtChans};
        TRACE("Created %s multichannel-to-mono converter\n", DevFmtTypeString(srcType));
        /* The channel converter always outputs float, so change the input type
         * for the resampler/type-converter.
         */
        srcType = DevFmtFloat;
    }
    else if(mDevice->FmtChans == DevFmtStereo && InputType.Format.nChannels == 1)
    {
        mChannelConv = ChannelConverter{srcType, 1, 0x1, mDevice->FmtChans};
        TRACE("Created %s mono-to-stereo converter\n", DevFmtTypeString(srcType));
        srcType = DevFmtFloat;
    }

    if(mDevice->Frequency != InputType.Format.nSamplesPerSec || mDevice->FmtType != srcType)
    {
        mSampleConv = SampleConverter::Create(srcType, mDevice->FmtType,
            mDevice->channelsFromFmt(), InputType.Format.nSamplesPerSec, mDevice->Frequency,
            Resampler::FastBSinc24);
        if(!mSampleConv)
        {
            ERR("Failed to create converter for %s format, dst: %s %uhz, src: %s %luhz\n",
                DevFmtChannelsString(mDevice->FmtChans), DevFmtTypeString(mDevice->FmtType),
                mDevice->Frequency, DevFmtTypeString(srcType), InputType.Format.nSamplesPerSec);
            return E_FAIL;
        }
        TRACE("Created converter for %s format, dst: %s %uhz, src: %s %luhz\n",
            DevFmtChannelsString(mDevice->FmtChans), DevFmtTypeString(mDevice->FmtType),
            mDevice->Frequency, DevFmtTypeString(srcType), InputType.Format.nSamplesPerSec);
    }

    hr = mClient->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
        buf_time.count(), 0, &InputType.Format, nullptr);
    if(FAILED(hr))
    {
        ERR("Failed to initialize audio client: 0x%08lx\n", hr);
        return hr;
    }

    hr = mClient->GetService(__uuidof(IAudioCaptureClient), al::out_ptr(mCapture));
    if(FAILED(hr))
    {
        ERR("Failed to get IAudioCaptureClient: 0x%08lx\n", hr);
        return hr;
    }

    UINT32 buffer_len{};
    ReferenceTime min_per{};
    hr = mClient->GetDevicePeriod(&reinterpret_cast<REFERENCE_TIME&>(min_per), nullptr);
    if(SUCCEEDED(hr))
        hr = mClient->GetBufferSize(&buffer_len);
    if(FAILED(hr))
    {
        ERR("Failed to get buffer size: 0x%08lx\n", hr);
        return hr;
    }
    mDevice->UpdateSize = RefTime2Samples(min_per, mDevice->Frequency);
    mDevice->BufferSize = buffer_len;

    mRing = RingBuffer::Create(buffer_len, mDevice->frameSizeFromFmt(), false);

    hr = mClient->SetEventHandle(mNotifyEvent);
    if(FAILED(hr))
    {
        ERR("Failed to set event handle: 0x%08lx\n", hr);
        return hr;
    }

    return hr;
}


void WasapiCapture::start()
{
    const HRESULT hr{pushMessage(MsgType::StartDevice).get()};
    if(FAILED(hr))
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to start recording: 0x%lx", hr};
}

HRESULT WasapiCapture::startProxy()
{
    ResetEvent(mNotifyEvent);

    HRESULT hr{mClient->Start()};
    if(FAILED(hr))
    {
        ERR("Failed to start audio client: 0x%08lx\n", hr);
        return hr;
    }

    try {
        mKillNow.store(false, std::memory_order_release);
        mThread = std::thread{std::mem_fn(&WasapiCapture::recordProc), this};
    }
    catch(...) {
        ERR("Failed to start thread\n");
        mClient->Stop();
        mClient->Reset();
        hr = E_FAIL;
    }

    return hr;
}


void WasapiCapture::stop()
{ pushMessage(MsgType::StopDevice).wait(); }

void WasapiCapture::stopProxy()
{
    if(!mThread.joinable())
        return;

    mKillNow.store(true, std::memory_order_release);
    mThread.join();

    mClient->Stop();
    mClient->Reset();
}


void WasapiCapture::captureSamples(std::byte *buffer, uint samples)
{ std::ignore = mRing->read(buffer, samples); }

uint WasapiCapture::availableSamples()
{ return static_cast<uint>(mRing->readSpace()); }

} // namespace


bool WasapiBackendFactory::init()
{
    static HRESULT InitResult{E_FAIL};
    if(FAILED(InitResult)) try
    {
        std::promise<HRESULT> promise;
        auto future = promise.get_future();

        std::thread{&WasapiProxy::messageHandler, &promise}.detach();
        InitResult = future.get();
    }
    catch(...) {
    }

    return SUCCEEDED(InitResult);
}

bool WasapiBackendFactory::querySupport(BackendType type)
{ return type == BackendType::Playback || type == BackendType::Capture; }

auto WasapiBackendFactory::enumerate(BackendType type) -> std::vector<std::string>
{
    std::vector<std::string> outnames;

    auto devlock = DeviceListLock{gDeviceList};
    switch(type)
    {
    case BackendType::Playback:
        {
            auto defaultId = devlock.getPlaybackDefaultId();
            for(const DevMap &entry : devlock.getPlaybackList())
            {
                if(entry.devid != defaultId)
                {
                    outnames.emplace_back(entry.name);
                    continue;
                }
                /* Default device goes first. */
                outnames.emplace(outnames.cbegin(), entry.name);
            }
        }
        break;

    case BackendType::Capture:
        {
            auto defaultId = devlock.getCaptureDefaultId();
            for(const DevMap &entry : devlock.getCaptureList())
            {
                if(entry.devid != defaultId)
                {
                    outnames.emplace_back(entry.name);
                    continue;
                }
                outnames.emplace(outnames.cbegin(), entry.name);
            }
        }
        break;
    }

    return outnames;
}

BackendPtr WasapiBackendFactory::createBackend(DeviceBase *device, BackendType type)
{
    if(type == BackendType::Playback)
        return BackendPtr{new WasapiPlayback{device}};
    if(type == BackendType::Capture)
        return BackendPtr{new WasapiCapture{device}};
    return nullptr;
}

BackendFactory &WasapiBackendFactory::getFactory()
{
    static WasapiBackendFactory factory{};
    return factory;
}

alc::EventSupport WasapiBackendFactory::queryEventSupport(alc::EventType eventType, BackendType)
{
    switch(eventType)
    {
    case alc::EventType::DefaultDeviceChanged:
        return alc::EventSupport::FullSupport;

    case alc::EventType::DeviceAdded:
    case alc::EventType::DeviceRemoved:
#if !ALSOFT_UWP
        return alc::EventSupport::FullSupport;
#endif

    case alc::EventType::Count:
        break;
    }
    return alc::EventSupport::NoSupport;
}
