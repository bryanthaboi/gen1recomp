
#include "alassert.h"

#include <stdexcept>
#include <string>

namespace {

[[noreturn]]
void throw_error(const std::string &message)
{
    throw std::runtime_error{message};
}

} /* namespace */

namespace al {

[[noreturn]]
void do_assert(const char *message, int linenum, const char *filename, const char *funcname) noexcept
{
    /* Throwing an exception that tries to leave a noexcept function will
     * hopefully cause the system to provide info about the caught exception in
     * an error dialog. At least on Linux, this results in the process printing
     *
     * terminate called after throwing an instance of 'std::runtime_error'
     *   what():  <message here>
     *
     * before terminating from a SIGABRT. Hopefully Windows and Mac will do the
     * appropriate things with the message to alert the user about an abnormal
     * termination.
     */
    auto errstr = std::string{filename};
    errstr += ':';
    errstr += std::to_string(linenum);
    errstr += ": ";
    errstr += funcname;
    errstr += ": ";
    errstr += message;

    throw_error(errstr);
}

} /* namespace al */
