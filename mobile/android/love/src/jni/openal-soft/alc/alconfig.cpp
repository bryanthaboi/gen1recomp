/**
 * OpenAL cross platform audio library
 * Copyright (C) 1999-2007 by authors.
 * This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 *  License along with this library; if not, write to the
 *  Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 * Or go to http://www.gnu.org/copyleft/lgpl.html
 */

#include "config.h"

#include "alconfig.h"

#ifdef _WIN32
#include <windows.h>
#include <shlobj.h>
#endif
#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#endif

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <istream>
#include <limits>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "almalloc.h"
#include "alstring.h"
#include "core/helpers.h"
#include "core/logging.h"
#include "strutils.h"

#if ALSOFT_UWP
#include <winrt/Windows.Media.Core.h> // !!This is important!!
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
using namespace winrt;
#endif

namespace {

using namespace std::string_view_literals;

#if defined(_WIN32) && !defined(_GAMING_XBOX) && !ALSOFT_UWP
struct CoTaskMemDeleter {
    void operator()(void *mem) const { CoTaskMemFree(mem); }
};
#endif

struct ConfigEntry {
    std::string key;
    std::string value;
};
std::vector<ConfigEntry> ConfOpts;


std::string &lstrip(std::string &line)
{
    size_t pos{0};
    while(pos < line.length() && std::isspace(line[pos]))
        ++pos;
    line.erase(0, pos);
    return line;
}

bool readline(std::istream &f, std::string &output)
{
    while(f.good() && f.peek() == '\n')
        f.ignore();

    return std::getline(f, output) && !output.empty();
}

std::string expdup(std::string_view str)
{
    std::string output;

    while(!str.empty())
    {
        if(auto nextpos = str.find('$'))
        {
            output += str.substr(0, nextpos);
            if(nextpos == std::string_view::npos)
                break;

            str.remove_prefix(nextpos);
        }

        str.remove_prefix(1);
        if(str.empty())
        {
            output += '$';
            break;
        }
        if(str.front() == '$')
        {
            output += '$';
            str.remove_prefix(1);
            continue;
        }

        const bool hasbraces{str.front() == '{'};
        if(hasbraces) str.remove_prefix(1);

        size_t envend{0};
        while(envend < str.size() && (std::isalnum(str[envend]) || str[envend] == '_'))
            ++envend;
        if(hasbraces && (envend == str.size() || str[envend] != '}'))
            continue;
        const std::string envname{str.substr(0, envend)};
        if(hasbraces) ++envend;
        str.remove_prefix(envend);

        if(auto envval = al::getenv(envname.c_str()))
            output += *envval;
    }

    return output;
}

void LoadConfigFromFile(std::istream &f)
{
    std::string curSection;
    std::string buffer;

    while(readline(f, buffer))
    {
        if(lstrip(buffer).empty())
            continue;

        if(buffer[0] == '[')
        {
            auto endpos = buffer.find(']', 1);
            if(endpos == 1 || endpos == std::string::npos)
            {
                ERR(" config parse error: bad line \"%s\"\n", buffer.c_str());
                continue;
            }
            if(buffer[endpos+1] != '\0')
            {
                size_t last{endpos+1};
                while(last < buffer.size() && std::isspace(buffer[last]))
                    ++last;

                if(last < buffer.size() && buffer[last] != '#')
                {
                    ERR(" config parse error: bad line \"%s\"\n", buffer.c_str());
                    continue;
                }
            }

            auto section = std::string_view{buffer}.substr(1, endpos-1);

            curSection.clear();
            if(al::case_compare(section, "general"sv) != 0)
            {
                do {
                    auto nextp = section.find('%');
                    if(nextp == std::string_view::npos)
                    {
                        curSection += section;
                        break;
                    }

                    curSection += section.substr(0, nextp);
                    section.remove_prefix(nextp);

                    if(section.size() > 2 &&
                       ((section[1] >= '0' && section[1] <= '9') ||
                        (section[1] >= 'a' && section[1] <= 'f') ||
                        (section[1] >= 'A' && section[1] <= 'F')) &&
                       ((section[2] >= '0' && section[2] <= '9') ||
                        (section[2] >= 'a' && section[2] <= 'f') ||
                        (section[2] >= 'A' && section[2] <= 'F')))
                    {
                        int b{0};
                        if(section[1] >= '0' && section[1] <= '9')
                            b = (section[1]-'0') << 4;
                        else if(section[1] >= 'a' && section[1] <= 'f')
                            b = (section[1]-'a'+0xa) << 4;
                        else if(section[1] >= 'A' && section[1] <= 'F')
                            b = (section[1]-'A'+0x0a) << 4;
                        if(section[2] >= '0' && section[2] <= '9')
                            b |= (section[2]-'0');
                        else if(section[2] >= 'a' && section[2] <= 'f')
                            b |= (section[2]-'a'+0xa);
                        else if(section[2] >= 'A' && section[2] <= 'F')
                            b |= (section[2]-'A'+0x0a);
                        curSection += static_cast<char>(b);
                        section.remove_prefix(3);
                    }
                    else if(section.size() > 1 && section[1] == '%')
                    {
                        curSection += '%';
                        section.remove_prefix(2);
                    }
                    else
                    {
                        curSection += '%';
                        section.remove_prefix(1);
                    }
                } while(!section.empty());
            }

            continue;
        }

        auto cmtpos = std::min(buffer.find('#'), buffer.size());
        while(cmtpos > 0 && std::isspace(buffer[cmtpos-1]))
            --cmtpos;
        if(!cmtpos) continue;
        buffer.erase(cmtpos);

        auto sep = buffer.find('=');
        if(sep == std::string::npos)
        {
            ERR(" config parse error: malformed option line: \"%s\"\n", buffer.c_str());
            continue;
        }
        auto keypart = std::string_view{buffer}.substr(0, sep++);
        while(!keypart.empty() && std::isspace(keypart.back()))
            keypart.remove_suffix(1);
        if(keypart.empty())
        {
            ERR(" config parse error: malformed option line: \"%s\"\n", buffer.c_str());
            continue;
        }
        auto valpart = std::string_view{buffer}.substr(sep);
        while(!valpart.empty() && std::isspace(valpart.front()))
            valpart.remove_prefix(1);

        std::string fullKey;
        if(!curSection.empty())
        {
            fullKey += curSection;
            fullKey += '/';
        }
        fullKey += keypart;

        if(valpart.size() > size_t{std::numeric_limits<int>::max()})
        {
            ERR(" config parse error: value too long in line \"%s\"\n", buffer.c_str());
            continue;
        }
        if(valpart.size() > 1)
        {
            if((valpart.front() == '"' && valpart.back() == '"')
                || (valpart.front() == '\'' && valpart.back() == '\''))
            {
                valpart.remove_prefix(1);
                valpart.remove_suffix(1);
            }
        }

        TRACE(" setting '%s' = '%.*s'\n", fullKey.c_str(), al::sizei(valpart), valpart.data());

        /* Check if we already have this option set */
        auto find_key = [&fullKey](const ConfigEntry &entry) -> bool
        { return entry.key == fullKey; };
        auto ent = std::find_if(ConfOpts.begin(), ConfOpts.end(), find_key);
        if(ent != ConfOpts.end())
        {
            if(!valpart.empty())
                ent->value = expdup(valpart);
            else
                ConfOpts.erase(ent);
        }
        else if(!valpart.empty())
            ConfOpts.emplace_back(ConfigEntry{std::move(fullKey), expdup(valpart)});
    }
    ConfOpts.shrink_to_fit();
}

auto GetConfigValue(const std::string_view devName, const std::string_view blockName,
    const std::string_view keyName) -> const std::string&
{
    static const auto emptyString = std::string{};
    if(keyName.empty())
        return emptyString;

    std::string key;
    if(!blockName.empty() && al::case_compare(blockName, "general"sv) != 0)
    {
        key = blockName;
        key += '/';
    }
    if(!devName.empty())
    {
        key += devName;
        key += '/';
    }
    key += keyName;

    auto iter = std::find_if(ConfOpts.cbegin(), ConfOpts.cend(),
        [&key](const ConfigEntry &entry) -> bool { return entry.key == key; });
    if(iter != ConfOpts.cend())
    {
        TRACE("Found option %s = \"%s\"\n", key.c_str(), iter->value.c_str());
        if(!iter->value.empty())
            return iter->value;
        return emptyString;
    }

    if(devName.empty())
        return emptyString;
    return GetConfigValue({}, blockName, keyName);
}

} // namespace


#ifdef _WIN32
void ReadALConfig()
{
    namespace fs = std::filesystem;
    fs::path path;

#if !defined(_GAMING_XBOX)
    {
#if !ALSOFT_UWP
        std::unique_ptr<WCHAR,CoTaskMemDeleter> bufstore;
        const HRESULT hr{SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_DONT_UNEXPAND,
            nullptr, al::out_ptr(bufstore))};
        if(SUCCEEDED(hr))
        {
            const std::wstring_view buffer{bufstore.get()};
#else
        winrt::Windows::Storage::ApplicationDataContainer localSettings = winrt::Windows::Storage::ApplicationData::Current().LocalSettings();
        auto bufstore = Windows::Storage::ApplicationData::Current().RoamingFolder().Path();
        std::wstring_view buffer{bufstore};
        {
#endif
            path = fs::path{buffer};
            path /= L"alsoft.ini";

            TRACE("Loading config %s...\n", path.u8string().c_str());
            if(std::ifstream f{path}; f.is_open())
                LoadConfigFromFile(f);
        }
    }
#endif

    path = fs::u8path(GetProcBinary().path);
    if(!path.empty())
    {
        path /= "alsoft.ini";
        TRACE("Loading config %s...\n", path.u8string().c_str());
        if(std::ifstream f{path}; f.is_open())
            LoadConfigFromFile(f);
    }

    if(auto confpath = al::getenv(L"ALSOFT_CONF"))
    {
        path = *confpath;
        TRACE("Loading config %s...\n", path.u8string().c_str());
        if(std::ifstream f{path}; f.is_open())
            LoadConfigFromFile(f);
    }
}

#else

void ReadALConfig()
{
    namespace fs = std::filesystem;
    fs::path path{"/etc/openal/alsoft.conf"};

    TRACE("Loading config %s...\n", path.u8string().c_str());
    if(std::ifstream f{path}; f.is_open())
        LoadConfigFromFile(f);

    std::string confpaths{al::getenv("XDG_CONFIG_DIRS").value_or("/etc/xdg")};
    /* Go through the list in reverse, since "the order of base directories
     * denotes their importance; the first directory listed is the most
     * important". Ergo, we need to load the settings from the later dirs
     * first so that the settings in the earlier dirs override them.
     */
    while(!confpaths.empty())
    {
        auto next = confpaths.rfind(':');
        if(next < confpaths.length())
        {
            path = fs::path{std::string_view{confpaths}.substr(next+1)}.lexically_normal();
            confpaths.erase(next);
        }
        else
        {
            path = fs::path{confpaths}.lexically_normal();
            confpaths.clear();
        }

        if(!path.is_absolute())
            WARN("Ignoring XDG config dir: %s\n", path.u8string().c_str());
        else
        {
            path /= "alsoft.conf";

            TRACE("Loading config %s...\n", path.u8string().c_str());
            if(std::ifstream f{path}; f.is_open())
                LoadConfigFromFile(f);
        }
    }

#ifdef __APPLE__
    CFBundleRef mainBundle = CFBundleGetMainBundle();
    if(mainBundle)
    {
        CFURLRef configURL{CFBundleCopyResourceURL(mainBundle, CFSTR(".alsoftrc"), CFSTR(""),
            nullptr)};

        std::array<unsigned char,PATH_MAX> fileName{};
        if(configURL && CFURLGetFileSystemRepresentation(configURL, true, fileName.data(), fileName.size()))
        {
            if(std::ifstream f{reinterpret_cast<char*>(fileName.data())}; f.is_open())
                LoadConfigFromFile(f);
        }
    }
#endif

    if(auto homedir = al::getenv("HOME"))
    {
        path = *homedir;
        path /= ".alsoftrc";

        TRACE("Loading config %s...\n", path.u8string().c_str());
        if(std::ifstream f{path}; f.is_open())
            LoadConfigFromFile(f);
    }

    if(auto configdir = al::getenv("XDG_CONFIG_HOME"))
    {
        path = *configdir;
        path /= "alsoft.conf";
    }
    else
    {
        path.clear();
        if(auto homedir = al::getenv("HOME"))
        {
            path = *homedir;
            path /= ".config/alsoft.conf";
        }
    }
    if(!path.empty())
    {
        TRACE("Loading config %s...\n", path.u8string().c_str());
        if(std::ifstream f{path}; f.is_open())
            LoadConfigFromFile(f);
    }

    path = GetProcBinary().path;
    if(!path.empty())
    {
        path /= "alsoft.conf";

        TRACE("Loading config %s...\n", path.u8string().c_str());
        if(std::ifstream f{path}; f.is_open())
            LoadConfigFromFile(f);
    }

    if(auto confname = al::getenv("ALSOFT_CONF"))
    {
        TRACE("Loading config %s...\n", confname->c_str());
        if(std::ifstream f{*confname}; f.is_open())
            LoadConfigFromFile(f);
    }
}
#endif

std::optional<std::string> ConfigValueStr(const std::string_view devName,
    const std::string_view blockName, const std::string_view keyName)
{
    if(auto&& val = GetConfigValue(devName, blockName, keyName); !val.empty())
        return val;
    return std::nullopt;
}

std::optional<int> ConfigValueInt(const std::string_view devName, const std::string_view blockName,
    const std::string_view keyName)
{
    if(auto&& val = GetConfigValue(devName, blockName, keyName); !val.empty())
        return static_cast<int>(std::stol(val, nullptr, 0));
    return std::nullopt;
}

std::optional<unsigned int> ConfigValueUInt(const std::string_view devName,
    const std::string_view blockName, const std::string_view keyName)
{
    if(auto&& val = GetConfigValue(devName, blockName, keyName); !val.empty())
        return static_cast<unsigned int>(std::stoul(val, nullptr, 0));
    return std::nullopt;
}

std::optional<float> ConfigValueFloat(const std::string_view devName,
    const std::string_view blockName, const std::string_view keyName)
{
    if(auto&& val = GetConfigValue(devName, blockName, keyName); !val.empty())
        return std::stof(val);
    return std::nullopt;
}

std::optional<bool> ConfigValueBool(const std::string_view devName,
    const std::string_view blockName, const std::string_view keyName)
{
    if(auto&& val = GetConfigValue(devName, blockName, keyName); !val.empty())
        return al::case_compare(val, "on"sv) == 0 || al::case_compare(val, "yes"sv) == 0
            || al::case_compare(val, "true"sv) == 0 || std::stoll(val) != 0;
    return std::nullopt;
}

bool GetConfigValueBool(const std::string_view devName, const std::string_view blockName,
    const std::string_view keyName, bool def)
{
    if(auto&& val = GetConfigValue(devName, blockName, keyName); !val.empty())
        return al::case_compare(val, "on") == 0 || al::case_compare(val, "yes") == 0
            || al::case_compare(val, "true") == 0 || std::stoll(val) != 0;
    return def;
}
