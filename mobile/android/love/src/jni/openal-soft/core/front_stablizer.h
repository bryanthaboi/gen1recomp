#ifndef CORE_FRONT_STABLIZER_H
#define CORE_FRONT_STABLIZER_H

#include <array>
#include <memory>

#include "almalloc.h"
#include "bufferline.h"
#include "filters/splitter.h"
#include "flexarray.h"


struct FrontStablizer {
    FrontStablizer(size_t numchans) : ChannelFilters{numchans} { }

    alignas(16) std::array<float,BufferLineSize> MidDirect{};
    alignas(16) std::array<float,BufferLineSize> Side{};
    alignas(16) std::array<float,BufferLineSize> Temp{};

    BandSplitter MidFilter;
    alignas(16) FloatBufferLine MidLF{};
    alignas(16) FloatBufferLine MidHF{};

    al::FlexArray<BandSplitter,16> ChannelFilters;

    static std::unique_ptr<FrontStablizer> Create(size_t numchans)
    { return std::unique_ptr<FrontStablizer>{new(FamCount(numchans)) FrontStablizer{numchans}}; }

    DEF_FAM_NEWDEL(FrontStablizer, ChannelFilters)
};

#endif /* CORE_FRONT_STABLIZER_H */
