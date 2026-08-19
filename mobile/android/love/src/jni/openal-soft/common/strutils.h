#ifndef AL_STRUTILS_H
#define AL_STRUTILS_H

#include <optional>
#include <string>

#ifdef _WIN32
#include <cwchar>
#include <string_view>

std::string wstr_to_utf8(std::wstring_view wstr);
std::wstring utf8_to_wstr(std::string_view str);
#endif

namespace al {

std::optional<std::string> getenv(const char *envname);
#ifdef _WIN32
std::optional<std::wstring> getenv(const wchar_t *envname);
#endif

} // namespace al

#endif /* AL_STRUTILS_H */
