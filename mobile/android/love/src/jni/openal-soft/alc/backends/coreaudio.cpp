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

#include "coreaudio.h"

#include <cinttypes>
#include <cmath>
#include <functional>
#include <memory>
#include <optional>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <string.h>
#include <unistd.h>
#include <vector>

#include "alnumeric.h"
#include "alstring.h"
#include "core/converter.h"
#include "core/device.h"
#include "core/logging.h"
#include "ringbuffer.h"

#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioToolbox.h>

#if TARGET_OS_IOS || TARGET_OS_TV
#define CAN_ENUMERATE 0
#else
#include <IOKit/audio/IOAudioTypes.h>
#define CAN_ENUMERATE 1
#endif

namespace {

constexpr auto OutputElement = 0;
constexpr auto InputElement = 1;

// These following arrays should always be defined in ascending AudioChannelLabel value order
constexpr std::array<AudioChannelLabel, 1> MonoChanMap { kAudioChannelLabel_Mono };
constexpr std::array<AudioChannelLabel, 2> StereoChanMap { kAudioChannelLabel_Left, kAudioChannelLabel_Right};
constexpr std::array<AudioChannelLabel, 4> QuadChanMap {
        kAudioChannelLabel_Left, kAudioChannelLabel_Right,
        kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround
};
constexpr std::array<AudioChannelLabel, 6> X51ChanMap {
        kAudioChannelLabel_Left, kAudioChannelLabel_Right,
        kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
        kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround
};
constexpr std::array<AudioChannelLabel, 6> X51RearChanMap {
        kAudioChannelLabel_Left, kAudioChannelLabel_Right,
        kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
        kAudioChannelLabel_RearSurroundRight, kAudioChannelLabel_RearSurroundLeft
};
constexpr std::array<AudioChannelLabel, 7> X61ChanMap {
        kAudioChannelLabel_Left, kAudioChannelLabel_Right,
        kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
        kAudioChannelLabel_CenterSurround,
        kAudioChannelLabel_RearSurroundRight, kAudioChannelLabel_RearSurroundLeft
};
constexpr std::array<AudioChannelLabel, 8> X71ChanMap {
        kAudioChannelLabel_Left, kAudioChannelLabel_Right,
        kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
        kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround,
        kAudioChannelLabel_LeftCenter, kAudioChannelLabel_RightCenter
};

struct FourCCPrinter {
    char mString[sizeof(UInt32) + 1]{};

    constexpr FourCCPrinter(UInt32 code) noexcept
    {
        for(size_t i{0};i < sizeof(UInt32);++i)
        {
            const auto ch = static_cast<char>(code & 0xff);
            /* If this breaks early it'll leave the first byte null, to get
             * read as a 0-length string.
             */
            if(ch <= 0x1f || ch >= 0x7f)
                break;
            mString[sizeof(UInt32)-1-i] = ch;
            code >>= 8;
        }
    }
    constexpr FourCCPrinter(int code) noexcept : FourCCPrinter{static_cast<UInt32>(code)} { }

    constexpr const char *c_str() const noexcept { return mString; }
};

#if CAN_ENUMERATE
struct DeviceEntry {
    AudioDeviceID mId;
    std::string mName;
};

std::vector<DeviceEntry> PlaybackList;
std::vector<DeviceEntry> CaptureList;


OSStatus GetHwProperty(AudioHardwarePropertyID propId, UInt32 dataSize, void *propData)
{
    const AudioObjectPropertyAddress addr{propId, kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMaster};
    return AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &dataSize,
        propData);
}

OSStatus GetHwPropertySize(AudioHardwarePropertyID propId, UInt32 *outSize)
{
    const AudioObjectPropertyAddress addr{propId, kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMaster};
    return AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, nullptr, outSize);
}

OSStatus GetDevProperty(AudioDeviceID devId, AudioDevicePropertyID propId, bool isCapture,
    UInt32 elem, UInt32 dataSize, void *propData)
{
    static const AudioObjectPropertyScope scopes[2]{kAudioDevicePropertyScopeOutput,
        kAudioDevicePropertyScopeInput};
    const AudioObjectPropertyAddress addr{propId, scopes[isCapture], elem};
    return AudioObjectGetPropertyData(devId, &addr, 0, nullptr, &dataSize, propData);
}

OSStatus GetDevPropertySize(AudioDeviceID devId, AudioDevicePropertyID inPropertyID,
    bool isCapture, UInt32 elem, UInt32 *outSize)
{
    static const AudioObjectPropertyScope scopes[2]{kAudioDevicePropertyScopeOutput,
        kAudioDevicePropertyScopeInput};
    const AudioObjectPropertyAddress addr{inPropertyID, scopes[isCapture], elem};
    return AudioObjectGetPropertyDataSize(devId, &addr, 0, nullptr, outSize);
}


std::string GetDeviceName(AudioDeviceID devId)
{
    std::string devname;
    CFStringRef nameRef;

    /* Try to get the device name as a CFString, for Unicode name support. */
    OSStatus err{GetDevProperty(devId, kAudioDevicePropertyDeviceNameCFString, false, 0,
        sizeof(nameRef), &nameRef)};
    if(err == noErr)
    {
        const CFIndex propSize{CFStringGetMaximumSizeForEncoding(CFStringGetLength(nameRef),
            kCFStringEncodingUTF8)};
        devname.resize(static_cast<size_t>(propSize)+1, '\0');

        CFStringGetCString(nameRef, &devname[0], propSize+1, kCFStringEncodingUTF8);
        CFRelease(nameRef);
    }
    else
    {
        /* If that failed, just get the C string. Hopefully there's nothing bad
         * with this.
         */
        UInt32 propSize{};
        if(GetDevPropertySize(devId, kAudioDevicePropertyDeviceName, false, 0, &propSize))
            return devname;

        devname.resize(propSize+1, '\0');
        if(GetDevProperty(devId, kAudioDevicePropertyDeviceName, false, 0, propSize, &devname[0]))
        {
            devname.clear();
            return devname;
        }
    }

    /* Clear extraneous nul chars that may have been written with the name
     * string, and return it.
     */
    while(!devname.empty() && !devname.back())
        devname.pop_back();
    return devname;
}

UInt32 GetDeviceChannelCount(AudioDeviceID devId, bool isCapture)
{
    UInt32 propSize{};
    auto err = GetDevPropertySize(devId, kAudioUnitProperty_AudioChannelLayout, isCapture, 0,
        &propSize);
    if(err)
    {
        ERR("kAudioDevicePropertyStreamConfiguration size query failed: '%s' (%u)\n",
            FourCCPrinter{err}.c_str(), err);
        return 0;
    }

    auto channel_data = std::make_unique<char[]>(propSize);
    auto *channel_layout = reinterpret_cast<AudioChannelLayout*>(channel_data.get());

    err = GetDevProperty(devId, kAudioUnitProperty_AudioChannelLayout, isCapture, 0, propSize,
        channel_layout);
    if(err)
    {
        ERR("kAudioDevicePropertyStreamConfiguration query failed: '%s' (%u)\n",
            FourCCPrinter{err}.c_str(), err);
        return 0;
    }

    return channel_layout->mNumberChannelDescriptions;
}


void EnumerateDevices(std::vector<DeviceEntry> &list, bool isCapture)
{
    UInt32 propSize{};
    if(auto err = GetHwPropertySize(kAudioHardwarePropertyDevices, &propSize))
    {
        ERR("Failed to get device list size: %u\n", err);
        return;
    }

    auto devIds = std::vector<AudioDeviceID>(propSize/sizeof(AudioDeviceID), kAudioDeviceUnknown);
    if(auto err = GetHwProperty(kAudioHardwarePropertyDevices, propSize, devIds.data()))
    {
        ERR("Failed to get device list: '%s' (%u)\n", FourCCPrinter{err}.c_str(), err);
        return;
    }

    std::vector<DeviceEntry> newdevs;
    newdevs.reserve(devIds.size());

    AudioDeviceID defaultId{kAudioDeviceUnknown};
    GetHwProperty(isCapture ? kAudioHardwarePropertyDefaultInputDevice :
        kAudioHardwarePropertyDefaultOutputDevice, sizeof(defaultId), &defaultId);

    if(defaultId != kAudioDeviceUnknown)
    {
        newdevs.emplace_back(DeviceEntry{defaultId, GetDeviceName(defaultId)});
        const auto &entry = newdevs.back();
        TRACE("Got device: %s = ID %u\n", entry.mName.c_str(), entry.mId);
    }
    for(const AudioDeviceID devId : devIds)
    {
        if(devId == kAudioDeviceUnknown)
            continue;

        auto match_devid = [devId](const DeviceEntry &entry) noexcept -> bool
        { return entry.mId == devId; };
        auto match = std::find_if(newdevs.cbegin(), newdevs.cend(), match_devid);
        if(match != newdevs.cend()) continue;

        auto numChannels = GetDeviceChannelCount(devId, isCapture);
        if(numChannels > 0)
        {
            newdevs.emplace_back(DeviceEntry{devId, GetDeviceName(devId)});
            const auto &entry = newdevs.back();
            TRACE("Got device: %s = ID %u\n", entry.mName.c_str(), entry.mId);
        }
    }

    if(newdevs.size() > 1)
    {
        /* Rename entries that have matching names, by appending '#2', '#3',
         * etc, as needed.
         */
        for(auto curitem = newdevs.begin()+1;curitem != newdevs.end();++curitem)
        {
            auto check_match = [curitem](const DeviceEntry &entry) -> bool
            { return entry.mName == curitem->mName; };
            if(std::find_if(newdevs.begin(), curitem, check_match) != curitem)
            {
                std::string name{curitem->mName};
                size_t count{1};
                auto check_name = [&name](const DeviceEntry &entry) -> bool
                { return entry.mName == name; };
                do {
                    name = curitem->mName;
                    name += " #";
                    name += std::to_string(++count);
                } while(std::find_if(newdevs.begin(), curitem, check_name) != curitem);
                curitem->mName = std::move(name);
            }
        }
    }

    newdevs.shrink_to_fit();
    newdevs.swap(list);
}

struct DeviceHelper {
    DeviceHelper()
    {
        AudioObjectPropertyAddress addr{kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        OSStatus status = AudioObjectAddPropertyListener(kAudioObjectSystemObject, &addr, DeviceListenerProc, nil);
        if (status != noErr)
            ERR("AudioObjectAddPropertyListener fail: %d", status);
    }
    ~DeviceHelper()
    {
        AudioObjectPropertyAddress addr{kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        OSStatus status = AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &addr, DeviceListenerProc, nil);
        if (status != noErr)
            ERR("AudioObjectRemovePropertyListener fail: %d", status);
    }

    static OSStatus DeviceListenerProc(AudioObjectID /*inObjectID*/, UInt32 inNumberAddresses,
        const AudioObjectPropertyAddress *inAddresses, void* /*inClientData*/)
    {
        for(UInt32 i = 0; i < inNumberAddresses; ++i)
        {
            switch(inAddresses[i].mSelector)
            {
            case kAudioHardwarePropertyDefaultOutputDevice:
            case kAudioHardwarePropertyDefaultSystemOutputDevice:
                alc::Event(alc::EventType::DefaultDeviceChanged, alc::DeviceType::Playback,
                    "Default playback device changed: "+std::to_string(inAddresses[i].mSelector));
                break;
            case kAudioHardwarePropertyDefaultInputDevice:
                alc::Event(alc::EventType::DefaultDeviceChanged, alc::DeviceType::Capture,
                    "Default capture device changed: "+std::to_string(inAddresses[i].mSelector));
                break;
            }
        }
        return noErr;
    }
};

static std::optional<DeviceHelper> sDeviceHelper;

#else

static constexpr char ca_device[] = "CoreAudio Default";
#endif


struct CoreAudioPlayback final : public BackendBase {
    CoreAudioPlayback(DeviceBase *device) noexcept : BackendBase{device} { }
    ~CoreAudioPlayback() override;

    OSStatus MixerProc(AudioUnitRenderActionFlags *ioActionFlags,
        const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames,
        AudioBufferList *ioData) noexcept;

    void open(std::string_view name) override;
    bool reset() override;
    void start() override;
    void stop() override;

    AudioUnit mAudioUnit{};

    uint mFrameSize{0u};
    AudioStreamBasicDescription mFormat{}; // This is the OpenAL format as a CoreAudio ASBD
};

CoreAudioPlayback::~CoreAudioPlayback()
{
    AudioUnitUninitialize(mAudioUnit);
    AudioComponentInstanceDispose(mAudioUnit);
}


OSStatus CoreAudioPlayback::MixerProc(AudioUnitRenderActionFlags*, const AudioTimeStamp*, UInt32,
    UInt32, AudioBufferList *ioData) noexcept
{
    for(size_t i{0};i < ioData->mNumberBuffers;++i)
    {
        auto &buffer = ioData->mBuffers[i];
        mDevice->renderSamples(buffer.mData, buffer.mDataByteSize/mFrameSize,
            buffer.mNumberChannels);
    }
    return noErr;
}


void CoreAudioPlayback::open(std::string_view name)
{
#if CAN_ENUMERATE
    AudioDeviceID audioDevice{kAudioDeviceUnknown};
    if(name.empty())
        GetHwProperty(kAudioHardwarePropertyDefaultOutputDevice, sizeof(audioDevice),
            &audioDevice);
    else
    {
        if(PlaybackList.empty())
            EnumerateDevices(PlaybackList, false);

        auto find_name = [name](const DeviceEntry &entry) -> bool
        { return entry.mName == name; };
        auto devmatch = std::find_if(PlaybackList.cbegin(), PlaybackList.cend(), find_name);
        if(devmatch == PlaybackList.cend())
            throw al::backend_exception{al::backend_error::NoDevice,
                "Device name \"%.*s\" not found", al::sizei(name), name.data()};

        audioDevice = devmatch->mId;
    }
#else
    if(name.empty())
        name = ca_device;
    else if(name != ca_device)
        throw al::backend_exception{al::backend_error::NoDevice, "Device name \"%.*s\" not found",
            al::sizei(name), name.data()};
#endif

    /* open the default output unit */
    AudioComponentDescription desc{};
    desc.componentType = kAudioUnitType_Output;
#if CAN_ENUMERATE
    desc.componentSubType = (audioDevice == kAudioDeviceUnknown) ?
        kAudioUnitSubType_DefaultOutput : kAudioUnitSubType_HALOutput;
#else
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
#endif
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;

    AudioComponent comp{AudioComponentFindNext(NULL, &desc)};
    if(comp == nullptr)
        throw al::backend_exception{al::backend_error::NoDevice, "Could not find audio component"};

    AudioUnit audioUnit{};
    OSStatus err{AudioComponentInstanceNew(comp, &audioUnit)};
    if(err != noErr)
        throw al::backend_exception{al::backend_error::NoDevice,
            "Could not create component instance: '%s' (%u)", FourCCPrinter{err}.c_str(), err};

#if CAN_ENUMERATE
    if(audioDevice != kAudioDeviceUnknown)
        AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, OutputElement, &audioDevice, sizeof(AudioDeviceID));
#endif

    err = AudioUnitInitialize(audioUnit);
    if(err != noErr)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Could not initialize audio unit: '%s' (%u)", FourCCPrinter{err}.c_str(), err};

    /* WARNING: I don't know if "valid" audio unit values are guaranteed to be
     * non-0. If not, this logic is broken.
     */
    if(mAudioUnit)
    {
        AudioUnitUninitialize(mAudioUnit);
        AudioComponentInstanceDispose(mAudioUnit);
    }
    mAudioUnit = audioUnit;

#if CAN_ENUMERATE
    if(!name.empty())
        mDeviceName = name;
    else
    {
        UInt32 propSize{sizeof(audioDevice)};
        audioDevice = kAudioDeviceUnknown;
        AudioUnitGetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, OutputElement, &audioDevice, &propSize);

        std::string devname{GetDeviceName(audioDevice)};
        if(!devname.empty()) mDeviceName = std::move(devname);
        else mDeviceName = "Unknown Device Name";
    }

    if(audioDevice != kAudioDeviceUnknown)
    {
        UInt32 type{};
        err = GetDevProperty(audioDevice, kAudioDevicePropertyDataSource, false,
            kAudioObjectPropertyElementMaster, sizeof(type), &type);
        if(err != noErr)
            ERR("Failed to get audio device type: %u\n", err);
        else
        {
            TRACE("Got device type '%s'\n", FourCCPrinter{type}.c_str());
            mDevice->Flags.set(DirectEar, (type == kIOAudioOutputPortSubTypeHeadphones));
        }
    }

#else
    mDeviceName = name;
#endif
}

bool CoreAudioPlayback::reset()
{
    OSStatus err{AudioUnitUninitialize(mAudioUnit)};
    if(err != noErr)
        ERR("AudioUnitUninitialize failed: '%s' (%u)\n", FourCCPrinter{err}.c_str(), err);

    /* retrieve default output unit's properties (output side) */
    AudioStreamBasicDescription streamFormat{};
    UInt32 size{sizeof(streamFormat)};
    err = AudioUnitGetProperty(mAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
        OutputElement, &streamFormat, &size);
    if(err != noErr || size != sizeof(streamFormat))
    {
        ERR("AudioUnitGetProperty(StreamFormat) failed: '%s' (%u)\n", FourCCPrinter{err}.c_str(),
            err);
        return false;
    }

#if 0
    TRACE("Output streamFormat of default output unit -\n");
    TRACE("  streamFormat.mFramesPerPacket = %d\n", streamFormat.mFramesPerPacket);
    TRACE("  streamFormat.mChannelsPerFrame = %d\n", streamFormat.mChannelsPerFrame);
    TRACE("  streamFormat.mBitsPerChannel = %d\n", streamFormat.mBitsPerChannel);
    TRACE("  streamFormat.mBytesPerPacket = %d\n", streamFormat.mBytesPerPacket);
    TRACE("  streamFormat.mBytesPerFrame = %d\n", streamFormat.mBytesPerFrame);
    TRACE("  streamFormat.mSampleRate = %5.0f\n", streamFormat.mSampleRate);
#endif

    /* Use the sample rate from the output unit's current parameters, but reset
     * everything else.
     */
    if(mDevice->Frequency != streamFormat.mSampleRate)
    {
        mDevice->BufferSize = static_cast<uint>(mDevice->BufferSize*streamFormat.mSampleRate/
            mDevice->Frequency + 0.5);
        mDevice->Frequency = static_cast<uint>(streamFormat.mSampleRate);
    }

    struct ChannelMap {
        DevFmtChannels fmt;
        al::span<const AudioChannelLabel> map;
        bool is_51rear;
    };

    static constexpr std::array<ChannelMap,7> chanmaps{{
        { DevFmtX71, X71ChanMap, false },
        { DevFmtX61, X61ChanMap, false },
        { DevFmtX51, X51ChanMap, false },
        { DevFmtX51, X51RearChanMap, true },
        { DevFmtQuad, QuadChanMap, false },
        { DevFmtStereo, StereoChanMap, false },
        { DevFmtMono, MonoChanMap, false }
    }};

    /* FIXME: How to tell what channels are what in the output device, and how
     * to specify what we're giving? e.g. 6.0 vs 5.1
     */
    streamFormat.mChannelsPerFrame = mDevice->channelsFromFmt();

    streamFormat.mFramesPerPacket = 1;
    streamFormat.mFormatFlags = kAudioFormatFlagsNativeEndian | kLinearPCMFormatFlagIsPacked;
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    switch(mDevice->FmtType)
    {
        case DevFmtUByte:
            mDevice->FmtType = DevFmtByte;
            /* fall-through */
        case DevFmtByte:
            streamFormat.mFormatFlags |= kLinearPCMFormatFlagIsSignedInteger;
            streamFormat.mBitsPerChannel = 8;
            break;
        case DevFmtUShort:
            mDevice->FmtType = DevFmtShort;
            /* fall-through */
        case DevFmtShort:
            streamFormat.mFormatFlags |= kLinearPCMFormatFlagIsSignedInteger;
            streamFormat.mBitsPerChannel = 16;
            break;
        case DevFmtUInt:
            mDevice->FmtType = DevFmtInt;
            /* fall-through */
        case DevFmtInt:
            streamFormat.mFormatFlags |= kLinearPCMFormatFlagIsSignedInteger;
            streamFormat.mBitsPerChannel = 32;
            break;
        case DevFmtFloat:
            streamFormat.mFormatFlags |= kLinearPCMFormatFlagIsFloat;
            streamFormat.mBitsPerChannel = 32;
            break;
    }
    streamFormat.mBytesPerFrame = streamFormat.mChannelsPerFrame*streamFormat.mBitsPerChannel/8;
    streamFormat.mBytesPerPacket = streamFormat.mBytesPerFrame*streamFormat.mFramesPerPacket;

    err = AudioUnitSetProperty(mAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
        OutputElement, &streamFormat, sizeof(streamFormat));
    if(err != noErr)
    {
        ERR("AudioUnitSetProperty(StreamFormat) failed: '%s' (%u)\n", FourCCPrinter{err}.c_str(),
            err);
        return false;
    }

    if(!mDevice->Flags.test(ChannelsRequest))
    {
        auto propSize = UInt32{};
        auto writable = Boolean{};

        err = AudioUnitGetPropertyInfo(mAudioUnit, kAudioUnitProperty_AudioChannelLayout,
            kAudioUnitScope_Output, OutputElement, &propSize, &writable);
        if(err == noErr)
        {
            auto layout_data = std::make_unique<char[]>(propSize);
            auto *layout = reinterpret_cast<AudioChannelLayout*>(layout_data.get());

            err = AudioUnitGetProperty(mAudioUnit, kAudioUnitProperty_AudioChannelLayout,
                kAudioUnitScope_Output, OutputElement, layout, &propSize);
            if(err == noErr)
            {
                auto descs = al::span{std::data(layout->mChannelDescriptions),
                    layout->mNumberChannelDescriptions};
                auto labels = std::vector<AudioChannelLayoutTag>(descs.size());

                std::transform(descs.begin(), descs.end(), labels.begin(),
                    std::mem_fn(&AudioChannelDescription::mChannelLabel));
                sort(labels.begin(), labels.end());

                auto chaniter = std::find_if(chanmaps.cbegin(), chanmaps.cend(),
                    [&labels](const ChannelMap &chanmap) -> bool
                    {
                        return std::includes(labels.begin(), labels.end(), chanmap.map.begin(),
                            chanmap.map.end());
                    });
                if(chaniter != chanmaps.cend())
                    mDevice->FmtChans = chaniter->fmt;
            }
        }
    }

    setDefaultWFXChannelOrder();

    /* setup callback */
    mFrameSize = mDevice->frameSizeFromFmt();
    AURenderCallbackStruct input{};
    input.inputProc = [](void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) noexcept
    { return static_cast<CoreAudioPlayback*>(inRefCon)->MixerProc(ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData); };
    input.inputProcRefCon = this;

    err = AudioUnitSetProperty(mAudioUnit, kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input, OutputElement, &input, sizeof(AURenderCallbackStruct));
    if(err != noErr)
    {
        ERR("AudioUnitSetProperty(SetRenderCallback) failed: '%s' (%u)\n",
            FourCCPrinter{err}.c_str(), err);
        return false;
    }

    /* init the default audio unit... */
    err = AudioUnitInitialize(mAudioUnit);
    if(err != noErr)
    {
        ERR("AudioUnitInitialize failed: '%s' (%u)\n", FourCCPrinter{err}.c_str(), err);
        return false;
    }

    return true;
}

void CoreAudioPlayback::start()
{
    const OSStatus err{AudioOutputUnitStart(mAudioUnit)};
    if(err != noErr)
        throw al::backend_exception{al::backend_error::DeviceError,
            "AudioOutputUnitStart failed: '%s' (%u)", FourCCPrinter{err}.c_str(), err};
}

void CoreAudioPlayback::stop()
{
    OSStatus err{AudioOutputUnitStop(mAudioUnit)};
    if(err != noErr)
        ERR("AudioOutputUnitStop failed: '%s' (%u)\n", FourCCPrinter{err}.c_str(), err);
}


struct CoreAudioCapture final : public BackendBase {
    CoreAudioCapture(DeviceBase *device) noexcept : BackendBase{device} { }
    ~CoreAudioCapture() override;

    OSStatus RecordProc(AudioUnitRenderActionFlags *ioActionFlags,
        const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
        UInt32 inNumberFrames, AudioBufferList *ioData) noexcept;

    void open(std::string_view name) override;
    void start() override;
    void stop() override;
    void captureSamples(std::byte *buffer, uint samples) override;
    uint availableSamples() override;

    AudioUnit mAudioUnit{0};

    uint mFrameSize{0u};
    AudioStreamBasicDescription mFormat{};  // This is the OpenAL format as a CoreAudio ASBD

    SampleConverterPtr mConverter;

    std::vector<char> mCaptureData;

    RingBufferPtr mRing{nullptr};
};

CoreAudioCapture::~CoreAudioCapture()
{
    if(mAudioUnit)
        AudioComponentInstanceDispose(mAudioUnit);
    mAudioUnit = 0;
}


OSStatus CoreAudioCapture::RecordProc(AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames,
    AudioBufferList*) noexcept
{
    union {
        std::byte buf[std::max(sizeof(AudioBufferList), offsetof(AudioBufferList, mBuffers[1]))];
        AudioBufferList list;
    } audiobuf{};

    audiobuf.list.mNumberBuffers = 1;
    audiobuf.list.mBuffers[0].mNumberChannels = mFormat.mChannelsPerFrame;
    audiobuf.list.mBuffers[0].mData = mCaptureData.data();
    audiobuf.list.mBuffers[0].mDataByteSize = static_cast<UInt32>(mCaptureData.size());

    OSStatus err{AudioUnitRender(mAudioUnit, ioActionFlags, inTimeStamp, inBusNumber,
        inNumberFrames, &audiobuf.list)};
    if(err != noErr)
    {
        ERR("AudioUnitRender capture error: '%s' (%u)\n", FourCCPrinter{err}.c_str(), err);
        return err;
    }

    std::ignore = mRing->write(mCaptureData.data(), inNumberFrames);
    return noErr;
}


void CoreAudioCapture::open(std::string_view name)
{
#if CAN_ENUMERATE
    AudioDeviceID audioDevice{kAudioDeviceUnknown};
    if(name.empty())
        GetHwProperty(kAudioHardwarePropertyDefaultInputDevice, sizeof(audioDevice),
            &audioDevice);
    else
    {
        if(CaptureList.empty())
            EnumerateDevices(CaptureList, true);

        auto find_name = [name](const DeviceEntry &entry) -> bool
        { return entry.mName == name; };
        auto devmatch = std::find_if(CaptureList.cbegin(), CaptureList.cend(), find_name);
        if(devmatch == CaptureList.cend())
            throw al::backend_exception{al::backend_error::NoDevice,
                "Device name \"%.*s\" not found", al::sizei(name), name.data()};

        audioDevice = devmatch->mId;
    }
#else
    if(name.empty())
        name = ca_device;
    else if(name != ca_device)
        throw al::backend_exception{al::backend_error::NoDevice, "Device name \"%.*s\" not found",
            al::sizei(name), name.data()};
#endif

    AudioComponentDescription desc{};
    desc.componentType = kAudioUnitType_Output;
#if CAN_ENUMERATE
    desc.componentSubType = (audioDevice == kAudioDeviceUnknown) ?
        kAudioUnitSubType_DefaultOutput : kAudioUnitSubType_HALOutput;
#else
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
#endif
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;

    // Search for component with given description
    AudioComponent comp{AudioComponentFindNext(NULL, &desc)};
    if(comp == NULL)
        throw al::backend_exception{al::backend_error::NoDevice, "Could not find audio component"};

    // Open the component
    OSStatus err{AudioComponentInstanceNew(comp, &mAudioUnit)};
    if(err != noErr)
        throw al::backend_exception{al::backend_error::NoDevice,
            "Could not create component instance: '%s' (%u)", FourCCPrinter{err}.c_str(), err};

    // Turn off AudioUnit output
    UInt32 enableIO{0};
    err = AudioUnitSetProperty(mAudioUnit, kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Output, OutputElement, &enableIO, sizeof(enableIO));
    if(err != noErr)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Could not disable audio unit output property: '%s' (%u)", FourCCPrinter{err}.c_str(),
            err};

    // Turn on AudioUnit input
    enableIO = 1;
    err = AudioUnitSetProperty(mAudioUnit, kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Input, InputElement, &enableIO, sizeof(enableIO));
    if(err != noErr)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Could not enable audio unit input property: '%s' (%u)", FourCCPrinter{err}.c_str(),
            err};

#if CAN_ENUMERATE
    if(audioDevice != kAudioDeviceUnknown)
        AudioUnitSetProperty(mAudioUnit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, InputElement, &audioDevice, sizeof(AudioDeviceID));
#endif

    // set capture callback
    AURenderCallbackStruct input{};
    input.inputProc = [](void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) noexcept
    { return static_cast<CoreAudioCapture*>(inRefCon)->RecordProc(ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData); };
    input.inputProcRefCon = this;

    err = AudioUnitSetProperty(mAudioUnit, kAudioOutputUnitProperty_SetInputCallback,
        kAudioUnitScope_Global, InputElement, &input, sizeof(AURenderCallbackStruct));
    if(err != noErr)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Could not set capture callback: '%s' (%u)", FourCCPrinter{err}.c_str(), err};

    // Disable buffer allocation for capture
    UInt32 flag{0};
    err = AudioUnitSetProperty(mAudioUnit, kAudioUnitProperty_ShouldAllocateBuffer,
        kAudioUnitScope_Output, InputElement, &flag, sizeof(flag));
    if(err != noErr)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Could not disable buffer allocation property: '%s' (%u)", FourCCPrinter{err}.c_str(),
            err};

    // Initialize the device
    err = AudioUnitInitialize(mAudioUnit);
    if(err != noErr)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Could not initialize audio unit: '%s' (%u)", FourCCPrinter{err}.c_str(), err};

    // Get the hardware format
    AudioStreamBasicDescription hardwareFormat{};
    UInt32 propertySize{sizeof(hardwareFormat)};
    err = AudioUnitGetProperty(mAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
        InputElement, &hardwareFormat, &propertySize);
    if(err != noErr || propertySize != sizeof(hardwareFormat))
        throw al::backend_exception{al::backend_error::DeviceError,
            "Could not get input format: '%s' (%u)", FourCCPrinter{err}.c_str(), err};

    // Set up the requested format description
    AudioStreamBasicDescription requestedFormat{};
    switch(mDevice->FmtType)
    {
    case DevFmtByte:
        requestedFormat.mBitsPerChannel = 8;
        requestedFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        break;
    case DevFmtUByte:
        requestedFormat.mBitsPerChannel = 8;
        requestedFormat.mFormatFlags = kAudioFormatFlagIsPacked;
        break;
    case DevFmtShort:
        requestedFormat.mBitsPerChannel = 16;
        requestedFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger
            | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
        break;
    case DevFmtUShort:
        requestedFormat.mBitsPerChannel = 16;
        requestedFormat.mFormatFlags = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
        break;
    case DevFmtInt:
        requestedFormat.mBitsPerChannel = 32;
        requestedFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger
            | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
        break;
    case DevFmtUInt:
        requestedFormat.mBitsPerChannel = 32;
        requestedFormat.mFormatFlags = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
        break;
    case DevFmtFloat:
        requestedFormat.mBitsPerChannel = 32;
        requestedFormat.mFormatFlags = kLinearPCMFormatFlagIsFloat | kAudioFormatFlagsNativeEndian
            | kAudioFormatFlagIsPacked;
        break;
    }

    switch(mDevice->FmtChans)
    {
    case DevFmtMono:
        requestedFormat.mChannelsPerFrame = 1;
        break;
    case DevFmtStereo:
        requestedFormat.mChannelsPerFrame = 2;
        break;

    case DevFmtQuad:
    case DevFmtX51:
    case DevFmtX61:
    case DevFmtX71:
    case DevFmtX714:
    case DevFmtX7144:
    case DevFmtX3D71:
    case DevFmtAmbi3D:
        throw al::backend_exception{al::backend_error::DeviceError, "%s not supported",
            DevFmtChannelsString(mDevice->FmtChans)};
    }

    requestedFormat.mBytesPerFrame = requestedFormat.mChannelsPerFrame * requestedFormat.mBitsPerChannel / 8;
    requestedFormat.mBytesPerPacket = requestedFormat.mBytesPerFrame;
    requestedFormat.mSampleRate = mDevice->Frequency;
    requestedFormat.mFormatID = kAudioFormatLinearPCM;
    requestedFormat.mReserved = 0;
    requestedFormat.mFramesPerPacket = 1;

    // save requested format description for later use
    mFormat = requestedFormat;
    mFrameSize = mDevice->frameSizeFromFmt();

    // Use intermediate format for sample rate conversion (outputFormat)
    // Set sample rate to the same as hardware for resampling later
    AudioStreamBasicDescription outputFormat{requestedFormat};
    outputFormat.mSampleRate = hardwareFormat.mSampleRate;

    // The output format should be the requested format, but using the hardware sample rate
    // This is because the AudioUnit will automatically scale other properties, except for sample rate
    err = AudioUnitSetProperty(mAudioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
        InputElement, &outputFormat, sizeof(outputFormat));
    if(err != noErr)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Could not set input format: '%s' (%u)", FourCCPrinter{err}.c_str(), err};

    /* Calculate the minimum AudioUnit output format frame count for the pre-
     * conversion ring buffer. Ensure at least 100ms for the total buffer.
     */
    double srateScale{outputFormat.mSampleRate / mDevice->Frequency};
    auto FrameCount64 = std::max(static_cast<uint64_t>(std::ceil(mDevice->BufferSize*srateScale)),
        static_cast<UInt32>(outputFormat.mSampleRate)/10_u64);
    FrameCount64 += MaxResamplerPadding;
    if(FrameCount64 > std::numeric_limits<int32_t>::max())
        throw al::backend_exception{al::backend_error::DeviceError,
            "Calculated frame count is too large: %" PRIu64, FrameCount64};

    UInt32 outputFrameCount{};
    propertySize = sizeof(outputFrameCount);
    err = AudioUnitGetProperty(mAudioUnit, kAudioUnitProperty_MaximumFramesPerSlice,
        kAudioUnitScope_Global, OutputElement, &outputFrameCount, &propertySize);
    if(err != noErr || propertySize != sizeof(outputFrameCount))
        throw al::backend_exception{al::backend_error::DeviceError,
            "Could not get input frame count: '%s' (%u)", FourCCPrinter{err}.c_str(), err};

    mCaptureData.resize(outputFrameCount * mFrameSize);

    outputFrameCount = static_cast<UInt32>(std::max(uint64_t{outputFrameCount}, FrameCount64));
    mRing = RingBuffer::Create(outputFrameCount, mFrameSize, false);

    /* Set up sample converter if needed */
    if(outputFormat.mSampleRate != mDevice->Frequency)
        mConverter = SampleConverter::Create(mDevice->FmtType, mDevice->FmtType,
            mFormat.mChannelsPerFrame, static_cast<uint>(hardwareFormat.mSampleRate),
            mDevice->Frequency, Resampler::FastBSinc24);

#if CAN_ENUMERATE
    if(!name.empty())
        mDeviceName = name;
    else
    {
        UInt32 propSize{sizeof(audioDevice)};
        audioDevice = kAudioDeviceUnknown;
        AudioUnitGetProperty(mAudioUnit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, InputElement, &audioDevice, &propSize);

        std::string devname{GetDeviceName(audioDevice)};
        if(!devname.empty()) mDeviceName = std::move(devname);
        else mDeviceName = "Unknown Device Name";
    }
#else
    mDeviceName = name;
#endif
}


void CoreAudioCapture::start()
{
    OSStatus err{AudioOutputUnitStart(mAudioUnit)};
    if(err != noErr)
        throw al::backend_exception{al::backend_error::DeviceError,
            "AudioOutputUnitStart failed: '%s' (%u)", FourCCPrinter{err}.c_str(), err};
}

void CoreAudioCapture::stop()
{
    OSStatus err{AudioOutputUnitStop(mAudioUnit)};
    if(err != noErr)
        ERR("AudioOutputUnitStop failed: '%s' (%u)\n", FourCCPrinter{err}.c_str(), err);
}

void CoreAudioCapture::captureSamples(std::byte *buffer, uint samples)
{
    if(!mConverter)
    {
        std::ignore = mRing->read(buffer, samples);
        return;
    }

    auto rec_vec = mRing->getReadVector();
    const void *src0{rec_vec[0].buf};
    auto src0len = static_cast<uint>(rec_vec[0].len);
    uint got{mConverter->convert(&src0, &src0len, buffer, samples)};
    size_t total_read{rec_vec[0].len - src0len};
    if(got < samples && !src0len && rec_vec[1].len > 0)
    {
        const void *src1{rec_vec[1].buf};
        auto src1len = static_cast<uint>(rec_vec[1].len);
        got += mConverter->convert(&src1, &src1len, buffer + got*mFrameSize, samples-got);
        total_read += rec_vec[1].len - src1len;
    }

    mRing->readAdvance(total_read);
}

uint CoreAudioCapture::availableSamples()
{
    if(!mConverter) return static_cast<uint>(mRing->readSpace());
    return mConverter->availableOut(static_cast<uint>(mRing->readSpace()));
}

} // namespace

BackendFactory &CoreAudioBackendFactory::getFactory()
{
    static CoreAudioBackendFactory factory{};
    return factory;
}

bool CoreAudioBackendFactory::init() 
{ 
#if CAN_ENUMERATE
    sDeviceHelper.emplace();
#endif
    return true; 
}

bool CoreAudioBackendFactory::querySupport(BackendType type)
{ return type == BackendType::Playback || type == BackendType::Capture; }

auto CoreAudioBackendFactory::enumerate(BackendType type) -> std::vector<std::string>
{
    std::vector<std::string> outnames;
#if CAN_ENUMERATE
    auto append_name = [&outnames](const DeviceEntry &entry) -> void
    { outnames.emplace_back(entry.mName); };

    switch(type)
    {
    case BackendType::Playback:
        EnumerateDevices(PlaybackList, false);
        outnames.reserve(PlaybackList.size());
        std::for_each(PlaybackList.cbegin(), PlaybackList.cend(), append_name);
        break;
    case BackendType::Capture:
        EnumerateDevices(CaptureList, true);
        outnames.reserve(CaptureList.size());
        std::for_each(CaptureList.cbegin(), CaptureList.cend(), append_name);
        break;
    }

#else

    switch(type)
    {
    case BackendType::Playback:
    case BackendType::Capture:
        outnames.emplace_back(ca_device);
        break;
    }
#endif
    return outnames;
}

BackendPtr CoreAudioBackendFactory::createBackend(DeviceBase *device, BackendType type)
{
    if(type == BackendType::Playback)
        return BackendPtr{new CoreAudioPlayback{device}};
    if(type == BackendType::Capture)
        return BackendPtr{new CoreAudioCapture{device}};
    return nullptr;
}

alc::EventSupport CoreAudioBackendFactory::queryEventSupport(alc::EventType eventType, BackendType)
{
    switch(eventType)
    {
    case alc::EventType::DefaultDeviceChanged:
        return alc::EventSupport::FullSupport;

    case alc::EventType::DeviceAdded:
    case alc::EventType::DeviceRemoved:
    case alc::EventType::Count:
        break;
    }
    return alc::EventSupport::NoSupport;
}
