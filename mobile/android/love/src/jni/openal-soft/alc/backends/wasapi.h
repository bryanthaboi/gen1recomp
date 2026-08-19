#ifndef BACKENDS_WASAPI_H
#define BACKENDS_WASAPI_H

#include "base.h"

struct WasapiBackendFactory final : public BackendFactory {
public:
    auto init() -> bool final;

    auto querySupport(BackendType type) -> bool final;

    auto queryEventSupport(alc::EventType eventType, BackendType type) -> alc::EventSupport final;

    auto enumerate(BackendType type) -> std::vector<std::string> final;

    auto createBackend(DeviceBase *device, BackendType type) -> BackendPtr final;

    static auto getFactory() -> BackendFactory&;
};

#endif /* BACKENDS_WASAPI_H */
