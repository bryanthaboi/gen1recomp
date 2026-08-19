
#include "config.h"

#include "except.h"

#include <cstdio>
#include <cstdarg>

#include "opthelpers.h"


namespace al {

base_exception::~base_exception() = default;

void base_exception::setMessage(const char *msg, std::va_list args)
{
    /* NOLINTBEGIN(*-array-to-pointer-decay) */
    std::va_list args2;
    va_copy(args2, args);
    int msglen{std::vsnprintf(nullptr, 0, msg, args)};
    if(msglen > 0) LIKELY
    {
        mMessage.resize(static_cast<size_t>(msglen)+1);
        std::vsnprintf(mMessage.data(), mMessage.length(), msg, args2);
        mMessage.pop_back();
    }
    va_end(args2);
    /* NOLINTEND(*-array-to-pointer-decay) */
}

} // namespace al
