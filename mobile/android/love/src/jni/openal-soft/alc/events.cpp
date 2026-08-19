
#include "config.h"

#include "events.h"

#include "alspan.h"
#include "core/logging.h"
#include "device.h"


namespace {

ALCenum EnumFromEventType(const alc::EventType type)
{
    switch(type)
    {
    case alc::EventType::DefaultDeviceChanged: return ALC_EVENT_TYPE_DEFAULT_DEVICE_CHANGED_SOFT;
    case alc::EventType::DeviceAdded: return ALC_EVENT_TYPE_DEVICE_ADDED_SOFT;
    case alc::EventType::DeviceRemoved: return ALC_EVENT_TYPE_DEVICE_REMOVED_SOFT;
    case alc::EventType::Count: break;
    }
    throw std::runtime_error{"Invalid EventType: "+std::to_string(al::to_underlying(type))};
}

} // namespace

namespace alc {

std::optional<alc::EventType> GetEventType(ALCenum type)
{
    switch(type)
    {
    case ALC_EVENT_TYPE_DEFAULT_DEVICE_CHANGED_SOFT: return alc::EventType::DefaultDeviceChanged;
    case ALC_EVENT_TYPE_DEVICE_ADDED_SOFT: return alc::EventType::DeviceAdded;
    case ALC_EVENT_TYPE_DEVICE_REMOVED_SOFT: return alc::EventType::DeviceRemoved;
    }
    return std::nullopt;
}

void Event(EventType eventType, DeviceType deviceType, ALCdevice *device, std::string_view message) noexcept
{
    auto eventlock = std::unique_lock{EventMutex};
    if(EventCallback && EventsEnabled.test(al::to_underlying(eventType)))
        EventCallback(EnumFromEventType(eventType), al::to_underlying(deviceType), device,
            static_cast<ALCsizei>(message.length()), message.data(), EventUserPtr);
}

} // namespace alc

FORCE_ALIGN ALCboolean ALC_APIENTRY alcEventControlSOFT(ALCsizei count, const ALCenum *events,
    ALCboolean enable) noexcept
{
    if(enable != ALC_FALSE && enable != ALC_TRUE)
    {
        alcSetError(nullptr, ALC_INVALID_ENUM);
        return ALC_FALSE;
    }
    if(count < 0)
    {
        alcSetError(nullptr, ALC_INVALID_VALUE);
        return ALC_FALSE;
    }
    if(count == 0)
        return ALC_TRUE;
    if(!events)
    {
        alcSetError(nullptr, ALC_INVALID_VALUE);
        return ALC_FALSE;
    }

    alc::EventBitSet eventSet{0};
    for(ALCenum type : al::span{events, static_cast<ALCuint>(count)})
    {
        auto etype = alc::GetEventType(type);
        if(!etype)
        {
            WARN("Invalid event type: 0x%04x\n", type);
            alcSetError(nullptr, ALC_INVALID_ENUM);
            return ALC_FALSE;
        }
        eventSet.set(al::to_underlying(*etype));
    }

    auto eventlock = std::unique_lock{alc::EventMutex};
    if(enable) alc::EventsEnabled |= eventSet;
    else alc::EventsEnabled &= ~eventSet;
    return ALC_TRUE;
}

FORCE_ALIGN void ALC_APIENTRY alcEventCallbackSOFT(ALCEVENTPROCTYPESOFT callback, void *userParam) noexcept
{
    auto eventlock = std::unique_lock{alc::EventMutex};
    alc::EventCallback = callback;
    alc::EventUserPtr = userParam;
}
