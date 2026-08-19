#ifndef ALC_BACKENDS_BASE_H
#define ALC_BACKENDS_BASE_H

#include <chrono>
#include <cstdarg>
#include <cstddef>
#include <memory>
#include <ratio>
#include <string>
#include <string_view>
#include <vector>

#include "core/device.h"
#include "core/except.h"
#include "alc/events.h"


using uint = unsigned int;

struct ClockLatency {
    std::chrono::nanoseconds ClockTime;
    std::chrono::nanoseconds Latency;
};

struct BackendBase {
    virtual void open(std::string_view name) = 0;

    virtual bool reset();
    virtual void start() = 0;
    virtual void stop() = 0;

    virtual void captureSamples(std::byte *buffer, uint samples);
    virtual uint availableSamples();

    virtual ClockLatency getClockLatency();

    DeviceBase *const mDevice;
    std::string mDeviceName;

    BackendBase() = delete;
    BackendBase(const BackendBase&) = delete;
    BackendBase(BackendBase&&) = delete;
    BackendBase(DeviceBase *device) noexcept : mDevice{device} { }
    virtual ~BackendBase() = default;

    void operator=(const BackendBase&) = delete;
    void operator=(BackendBase&&) = delete;

protected:
    /** Sets the default channel order used by most non-WaveFormatEx-based APIs. */
    void setDefaultChannelOrder() const;
    /** Sets the default channel order used by WaveFormatEx. */
    void setDefaultWFXChannelOrder() const;
};
using BackendPtr = std::unique_ptr<BackendBase>;

enum class BackendType {
    Playback,
    Capture
};


/* Helper to get the device latency from the backend, including any fixed
 * latency from post-processing.
 */
inline ClockLatency GetClockLatency(DeviceBase *device, BackendBase *backend)
{
    ClockLatency ret{backend->getClockLatency()};
    ret.Latency += device->FixedLatency;
    return ret;
}


struct BackendFactory {
    BackendFactory() = default;
    BackendFactory(const BackendFactory&) = delete;
    BackendFactory(BackendFactory&&) = delete;
    virtual ~BackendFactory() = default;

    void operator=(const BackendFactory&) = delete;
    void operator=(BackendFactory&&) = delete;

    virtual auto init() -> bool = 0;

    virtual auto querySupport(BackendType type) -> bool = 0;

    virtual auto queryEventSupport(alc::EventType, BackendType) -> alc::EventSupport
    { return alc::EventSupport::NoSupport; }

    virtual auto enumerate(BackendType type) -> std::vector<std::string> = 0;

    virtual auto createBackend(DeviceBase *device, BackendType type) -> BackendPtr = 0;
};

namespace al {

enum class backend_error {
    NoDevice,
    DeviceError,
    OutOfMemory
};

class backend_exception final : public base_exception {
    backend_error mErrorCode;

public:
#ifdef __MINGW32__
    [[gnu::format(__MINGW_PRINTF_FORMAT, 3, 4)]]
#else
    [[gnu::format(printf, 3, 4)]]
#endif
    backend_exception(backend_error code, const char *msg, ...);
    ~backend_exception() override;

    [[nodiscard]] auto errorCode() const noexcept -> backend_error { return mErrorCode; }
};

} // namespace al

#endif /* ALC_BACKENDS_BASE_H */
