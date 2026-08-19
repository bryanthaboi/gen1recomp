#ifndef AL_DEBUG_H
#define AL_DEBUG_H

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

using uint = unsigned int;


/* Somewhat arbitrary. Avoid letting it get out of control if the app enables
 * logging but never reads it.
 */
inline constexpr std::uint8_t MaxDebugLoggedMessages{64};
inline constexpr std::uint16_t MaxDebugMessageLength{1024};
inline constexpr std::uint8_t MaxDebugGroupDepth{64};
inline constexpr std::uint16_t MaxObjectLabelLength{1024};


inline constexpr uint DebugSourceBase{0};
enum class DebugSource : std::uint8_t {
    API = 0,
    System,
    ThirdParty,
    Application,
    Other,
};
inline constexpr uint DebugSourceCount{5};

inline constexpr uint DebugTypeBase{DebugSourceBase + DebugSourceCount};
enum class DebugType : std::uint8_t {
    Error = 0,
    DeprecatedBehavior,
    UndefinedBehavior,
    Portability,
    Performance,
    Marker,
    PushGroup,
    PopGroup,
    Other,
};
inline constexpr uint DebugTypeCount{9};

inline constexpr uint DebugSeverityBase{DebugTypeBase + DebugTypeCount};
enum class DebugSeverity : std::uint8_t {
    High = 0,
    Medium,
    Low,
    Notification,
};
inline constexpr uint DebugSeverityCount{4};

struct DebugGroup {
    const uint mId;
    const DebugSource mSource;
    std::string mMessage;
    std::vector<uint> mFilters;
    std::vector<std::uint64_t> mIdFilters;

    template<typename T>
    DebugGroup(DebugSource source, uint id, T&& message)
        : mId{id}, mSource{source}, mMessage{std::forward<T>(message)}
    { }
    DebugGroup(const DebugGroup&) = default;
    DebugGroup(DebugGroup&&) = default;
    ~DebugGroup();
};

#endif /* AL_DEBUG_H */
