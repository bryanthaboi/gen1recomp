#ifndef BACKENDS_JACK_H
#define BACKENDS_JACK_H

#include "base.h"

struct JackBackendFactory final : public BackendFactory {
public:
    auto init() -> bool final;

    auto querySupport(BackendType type) -> bool final;

    auto enumerate(BackendType type) -> std::vector<std::string> final;

    auto createBackend(DeviceBase *device, BackendType type) -> BackendPtr final;

    static auto getFactory() -> BackendFactory&;
};

#endif /* BACKENDS_JACK_H */
