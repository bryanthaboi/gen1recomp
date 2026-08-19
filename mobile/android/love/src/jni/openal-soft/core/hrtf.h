#ifndef CORE_HRTF_H
#define CORE_HRTF_H

#include <array>
#include <cstddef>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "almalloc.h"
#include "alspan.h"
#include "ambidefs.h"
#include "bufferline.h"
#include "flexarray.h"
#include "intrusive_ptr.h"
#include "mixer/hrtfdefs.h"


struct alignas(16) HrtfStore {
    std::atomic<uint> mRef;

    uint mSampleRate : 24;
    uint mIrSize : 8;

    struct Field {
        float distance;
        ubyte evCount;
    };
    /* NOTE: Fields are stored *backwards*. field[0] is the farthest field, and
     * field[fdCount-1] is the nearest.
     */
    al::span<const Field> mFields;

    struct Elevation {
        ushort azCount;
        ushort irOffset;
    };
    al::span<Elevation> mElev;
    al::span<const HrirArray> mCoeffs;
    al::span<const ubyte2> mDelays;

    void getCoeffs(float elevation, float azimuth, float distance, float spread,
        const HrirSpan coeffs, const al::span<uint,2> delays) const;

    void add_ref();
    void dec_ref();

    void *operator new(size_t) = delete;
    void *operator new[](size_t) = delete;
    void operator delete[](void*) noexcept = delete;

    void operator delete(gsl::owner<void*> block, void*) noexcept
    { ::operator delete[](block, std::align_val_t{alignof(HrtfStore)}); }
    void operator delete(gsl::owner<void*> block) noexcept
    { ::operator delete[](block, std::align_val_t{alignof(HrtfStore)}); }
};
using HrtfStorePtr = al::intrusive_ptr<HrtfStore>;


struct EvRadians { float value; };
struct AzRadians { float value; };
struct AngularPoint {
    EvRadians Elev;
    AzRadians Azim;
};


struct DirectHrtfState {
    std::array<float,BufferLineSize> mTemp{};

    /* HRTF filter state for dry buffer content */
    uint mIrSize{0};
    al::FlexArray<HrtfChannelState> mChannels;

    DirectHrtfState(size_t numchans) : mChannels{numchans} { }
    /**
     * Produces HRTF filter coefficients for decoding B-Format, given a set of
     * virtual speaker positions, a matching decoding matrix, and per-order
     * high-frequency gains for the decoder. The calculated impulse responses
     * are ordered and scaled according to the matrix input.
     */
    void build(const HrtfStore *Hrtf, const uint irSize, const bool perHrirMin,
        const al::span<const AngularPoint> AmbiPoints,
        const al::span<const std::array<float,MaxAmbiChannels>> AmbiMatrix,
        const float XOverFreq, const al::span<const float,MaxAmbiOrder+1> AmbiOrderHFGain);

    static std::unique_ptr<DirectHrtfState> Create(size_t num_chans);

    DEF_FAM_NEWDEL(DirectHrtfState, mChannels)
};


std::vector<std::string> EnumerateHrtf(std::optional<std::string> pathopt);
HrtfStorePtr GetLoadedHrtf(const std::string_view name, const uint devrate);

#endif /* CORE_HRTF_H */
