#ifndef ALC_EVENTS_H
#define ALC_EVENTS_H

#include "inprogext.h"
#include "opthelpers.h"

#include <bitset>
#include <mutex>
#include <optional>
#include <string_view>


namespace alc {

enum class EventType : uint8_t {
    DefaultDeviceChanged,
    DeviceAdded,
    DeviceRemoved,

    Count
};

std::optional<alc::EventType> GetEventType(ALCenum type);

enum class EventSupport : ALCenum {
    FullSupport = ALC_EVENT_SUPPORTED_SOFT,
    NoSupport = ALC_EVENT_NOT_SUPPORTED_SOFT,
};

enum class DeviceType : ALCenum {
    Playback = ALC_PLAYBACK_DEVICE_SOFT,
    Capture = ALC_CAPTURE_DEVICE_SOFT,
};

using EventBitSet = std::bitset<al::to_underlying(EventType::Count)>;
inline EventBitSet EventsEnabled{0};

inline std::mutex EventMutex;

inline ALCEVENTPROCTYPESOFT EventCallback{};
inline void *EventUserPtr{};

void Event(EventType eventType, DeviceType deviceType, ALCdevice *device, std::string_view message) noexcept;

inline void Event(EventType eventType, DeviceType deviceType, std::string_view message) noexcept
{ Event(eventType, deviceType, nullptr, message); }

} // namespace alc

#endif /* ALC_EVENTS_H */
