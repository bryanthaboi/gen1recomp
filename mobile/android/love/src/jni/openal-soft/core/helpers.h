#ifndef CORE_HELPERS_H
#define CORE_HELPERS_H

#include <string>
#include <string_view>
#include <vector>


struct PathNamePair {
    std::string path, fname;
};
const PathNamePair &GetProcBinary();

/* Mixing thread priority level */
inline int RTPrioLevel{1};

/* Allow reducing the process's RTTime limit for RTKit. */
inline bool AllowRTTimeLimit{true};

void SetRTPriority();

auto SearchDataFiles(const std::string_view ext) -> std::vector<std::string>;
auto SearchDataFiles(const std::string_view ext, const std::string_view subdir)
    -> std::vector<std::string>;

#endif /* CORE_HELPERS_H */
