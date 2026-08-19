
#include "config.h"

#include "strutils.h"

#include <cstdlib>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include "alstring.h"

std::string wstr_to_utf8(std::wstring_view wstr)
{
    std::string ret;

    const int len{WideCharToMultiByte(CP_UTF8, 0, wstr.data(), al::sizei(wstr), nullptr, 0,
        nullptr, nullptr)};
    if(len > 0)
    {
        ret.resize(static_cast<size_t>(len));
        WideCharToMultiByte(CP_UTF8, 0, wstr.data(), al::sizei(wstr), ret.data(), len,
            nullptr, nullptr);
    }

    return ret;
}

std::wstring utf8_to_wstr(std::string_view str)
{
    std::wstring ret;

    const int len{MultiByteToWideChar(CP_UTF8, 0, str.data(), al::sizei(str), nullptr, 0)};
    if(len > 0)
    {
        ret.resize(static_cast<size_t>(len));
        MultiByteToWideChar(CP_UTF8, 0, str.data(), al::sizei(str), ret.data(), len);
    }

    return ret;
}
#endif

namespace al {

std::optional<std::string> getenv(const char *envname)
{
#ifdef _GAMING_XBOX
    const char *str{::getenv(envname)};
#else
    const char *str{std::getenv(envname)};
#endif
    if(str && *str != '\0')
        return str;
    return std::nullopt;
}

#ifdef _WIN32
std::optional<std::wstring> getenv(const WCHAR *envname)
{
    const WCHAR *str{_wgetenv(envname)};
    if(str && *str != L'\0')
        return str;
    return std::nullopt;
}
#endif

} // namespace al
