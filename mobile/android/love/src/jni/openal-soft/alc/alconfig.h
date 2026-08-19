#ifndef ALCONFIG_H
#define ALCONFIG_H

#include <optional>
#include <string>
#include <string_view>


void ReadALConfig();

bool GetConfigValueBool(const std::string_view devName, const std::string_view blockName,
    const std::string_view keyName, bool def);

std::optional<std::string> ConfigValueStr(const std::string_view devName,
    const std::string_view blockName, const std::string_view keyName);
std::optional<int> ConfigValueInt(const std::string_view devName, const std::string_view blockName,
    const std::string_view keyName);
std::optional<unsigned int> ConfigValueUInt(const std::string_view devName,
    const std::string_view blockName, const std::string_view keyName);
std::optional<float> ConfigValueFloat(const std::string_view devName,
    const std::string_view blockName, const std::string_view keyName);
std::optional<bool> ConfigValueBool(const std::string_view devName,
    const std::string_view blockName, const std::string_view keyName);

#endif /* ALCONFIG_H */
