#ifndef BACKENDS_SNDIO_H
#define BACKENDS_SNDIO_H

#include "base.h"

struct SndIOBackendFactory final : public BackendFactory {
public:
    auto init() -> bool final;

    auto querySupport(BackendType type) -> bool final;

    auto enumerate(BackendType type) -> std::vector<std::string> final;

    auto createBackend(DeviceBase *device, BackendType type) -> BackendPtr final;

    static auto getFactory() -> BackendFactory&;
};

#endif /* BACKENDS_SNDIO_H */
