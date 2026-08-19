
#include "config.h"

#include "logging.h"

#include <array>
#include <cctype>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "alspan.h"
#include "opthelpers.h"
#include "strutils.h"


#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#elif defined(__ANDROID__)
#include <android/log.h>
#endif


FILE *gLogFile{stderr};
#ifdef _DEBUG
LogLevel gLogLevel{LogLevel::Warning};
#else
LogLevel gLogLevel{LogLevel::Error};
#endif


namespace {

enum class LogState : uint8_t {
    FirstRun,
    Ready,
    Disable
};

std::mutex LogCallbackMutex;
LogState gLogState{LogState::FirstRun};

LogCallbackFunc gLogCallback{};
void *gLogCallbackPtr{};

constexpr auto GetLevelCode(LogLevel level) noexcept -> std::optional<char>
{
    switch(level)
    {
    case LogLevel::Disable: break;
    case LogLevel::Error: return 'E';
    case LogLevel::Warning: return 'W';
    case LogLevel::Trace: return 'I';
    }
    return std::nullopt;
}

} // namespace

void al_set_log_callback(LogCallbackFunc callback, void *userptr)
{
    auto cblock = std::lock_guard{LogCallbackMutex};
    gLogCallback = callback;
    gLogCallbackPtr = callback ? userptr : nullptr;
    if(gLogState == LogState::FirstRun)
    {
        auto extlogopt = al::getenv("ALSOFT_DISABLE_LOG_CALLBACK");
        if(!extlogopt || *extlogopt != "1")
            gLogState = LogState::Ready;
        else
            gLogState = LogState::Disable;
    }
}

void al_print(LogLevel level, const char *fmt, ...) noexcept
try {
    /* Kind of ugly since string literals are const char arrays with a size
     * that includes the null terminator, which we want to exclude from the
     * span.
     */
    auto prefix = al::span{"[ALSOFT] (--) "}.first<14>();
    switch(level)
    {
    case LogLevel::Disable: break;
    case LogLevel::Error: prefix = al::span{"[ALSOFT] (EE) "}.first<14>(); break;
    case LogLevel::Warning: prefix = al::span{"[ALSOFT] (WW) "}.first<14>(); break;
    case LogLevel::Trace: prefix = al::span{"[ALSOFT] (II) "}.first<14>(); break;
    }

    std::vector<char> dynmsg;
    std::array<char,256> stcmsg{};

    char *str{stcmsg.data()};
    auto prefend1 = std::copy_n(prefix.begin(), prefix.size(), stcmsg.begin());
    al::span<char> msg{prefend1, stcmsg.end()};

    /* NOLINTBEGIN(*-array-to-pointer-decay) */
    std::va_list args, args2;
    va_start(args, fmt);
    va_copy(args2, args);
    const int msglen{std::vsnprintf(msg.data(), msg.size(), fmt, args)};
    if(msglen >= 0)
    {
        if(static_cast<size_t>(msglen) >= msg.size()) UNLIKELY
        {
            dynmsg.resize(static_cast<size_t>(msglen)+prefix.size() + 1u);

            str = dynmsg.data();
            auto prefend2 = std::copy_n(prefix.begin(), prefix.size(), dynmsg.begin());
            msg = {prefend2, dynmsg.end()};

            std::vsnprintf(msg.data(), msg.size(), fmt, args2);
        }
        msg = msg.first(static_cast<size_t>(msglen));
    }
    else
        msg = {msg.data(), std::strlen(msg.data())};
    va_end(args2);
    va_end(args);
    /* NOLINTEND(*-array-to-pointer-decay) */

    if(gLogLevel >= level)
    {
        auto logfile = gLogFile;
        fputs(str, logfile);
        fflush(logfile);
    }
#if defined(_WIN32) && !defined(NDEBUG)
    /* OutputDebugStringW has no 'level' property to distinguish between
     * informational, warning, or error debug messages. So only print them for
     * non-Release builds.
     */
    std::wstring wstr{utf8_to_wstr(str)};
    OutputDebugStringW(wstr.c_str());
#elif defined(__ANDROID__)
    auto android_severity = [](LogLevel l) noexcept
    {
        switch(l)
        {
        case LogLevel::Trace: return ANDROID_LOG_DEBUG;
        case LogLevel::Warning: return ANDROID_LOG_WARN;
        case LogLevel::Error: return ANDROID_LOG_ERROR;
        /* Should not happen. */
        case LogLevel::Disable:
            break;
        }
        return ANDROID_LOG_ERROR;
    };
    __android_log_print(android_severity(level), "openal", "%s", str);
#endif

    auto cblock = std::lock_guard{LogCallbackMutex};
    if(gLogState != LogState::Disable)
    {
        while(!msg.empty() && std::isspace(msg.back()))
        {
            msg.back() = '\0';
            msg = msg.first(msg.size()-1);
        }
        if(auto logcode = GetLevelCode(level); logcode && !msg.empty())
        {
            if(gLogCallback)
                gLogCallback(gLogCallbackPtr, *logcode, msg.data(), static_cast<int>(msg.size()));
            else if(gLogState == LogState::FirstRun)
                gLogState = LogState::Disable;
        }
    }
}
catch(...) {
    /* Swallow any exceptions */
}
