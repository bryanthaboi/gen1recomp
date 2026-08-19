#ifndef CORE_AMBDEC_H
#define CORE_AMBDEC_H

#include <array>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "alspan.h"
#include "core/ambidefs.h"

/* Helpers to read .ambdec configuration files. */

enum class AmbDecScale {
    Unset,
    N3D,
    SN3D,
    FuMa,
};
struct AmbDecConf {
    std::string Description;
    int Version{0}; /* Must be 3 */

    unsigned int ChanMask{0u};
    unsigned int FreqBands{0u}; /* Must be 1 or 2 */
    AmbDecScale CoeffScale{AmbDecScale::Unset};

    float XOverFreq{0.0f};
    float XOverRatio{0.0f};

    struct SpeakerConf {
        std::string Name;
        float Distance{0.0f};
        float Azimuth{0.0f};
        float Elevation{0.0f};
        std::string Connection;
    };
    std::vector<SpeakerConf> Speakers;

    using CoeffArray = std::array<float,MaxAmbiChannels>;
    std::vector<CoeffArray> Matrix;

    /* Unused when FreqBands == 1 */
    std::array<float,MaxAmbiOrder+1> LFOrderGain{};
    al::span<CoeffArray> LFMatrix;

    std::array<float,MaxAmbiOrder+1> HFOrderGain{};
    al::span<CoeffArray> HFMatrix;

    ~AmbDecConf();

    std::optional<std::string> load(const char *fname) noexcept;
};

#endif /* CORE_AMBDEC_H */
