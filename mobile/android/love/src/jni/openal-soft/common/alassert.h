#ifndef AL_ASSERT_H
#define AL_ASSERT_H

#include <array>

#include "opthelpers.h"

namespace al {

[[noreturn]]
void do_assert(const char *message, int linenum, const char *filename, const char *funcname) noexcept;

} /* namespace al */

/* A custom assert macro that is not compiled out for Release/NDEBUG builds,
 * making it an appropriate replacement for assert() checks that must not be
 * ignored.
 */
#define alassert(cond) do {                                                   \
    if(!(cond)) UNLIKELY                                                      \
        al::do_assert("Assertion '" #cond "' failed", __LINE__, __FILE__, std::data(__func__)); \
} while(0)

#endif /* AL_ASSERT_H */
