#ifndef AL_ERROR_H
#define AL_ERROR_H

#include "AL/al.h"

#include "core/except.h"

namespace al {

class context_error final : public al::base_exception {
    ALenum mErrorCode{};

public:
#ifdef __MINGW32__
    [[gnu::format(__MINGW_PRINTF_FORMAT, 3, 4)]]
#else
    [[gnu::format(printf, 3, 4)]]
#endif
    context_error(ALenum code, const char *msg, ...);
    ~context_error() final;

    [[nodiscard]] auto errorCode() const noexcept -> ALenum { return mErrorCode; }
};

} /* namespace al */

#endif /* AL_ERROR_H */
