
#include "config.h"

#include "device.h"

#include <algorithm>
#include <cstddef>
#include <numeric>

#include "al/buffer.h"
#include "al/effect.h"
#include "al/filter.h"
#include "albit.h"
#include "alnumeric.h"
#include "atomic.h"
#include "backends/base.h"
#include "core/devformat.h"
#include "core/hrtf.h"
#include "core/logging.h"
#include "core/mastering.h"
#include "flexarray.h"


namespace {

using voidp = void*;

} // namespace


ALCdevice::ALCdevice(DeviceType type) : DeviceBase{type}
{ }

ALCdevice::~ALCdevice()
{
    TRACE("Freeing device %p\n", voidp{this});

    Backend = nullptr;

    size_t count{std::accumulate(BufferList.cbegin(), BufferList.cend(), 0_uz,
        [](size_t cur, const BufferSubList &sublist) noexcept -> size_t
        { return cur + static_cast<uint>(al::popcount(~sublist.FreeMask)); })};
    if(count > 0)
        WARN("%zu Buffer%s not deleted\n", count, (count==1)?"":"s");

    count = std::accumulate(EffectList.cbegin(), EffectList.cend(), 0_uz,
        [](size_t cur, const EffectSubList &sublist) noexcept -> size_t
        { return cur + static_cast<uint>(al::popcount(~sublist.FreeMask)); });
    if(count > 0)
        WARN("%zu Effect%s not deleted\n", count, (count==1)?"":"s");

    count = std::accumulate(FilterList.cbegin(), FilterList.cend(), 0_uz,
        [](size_t cur, const FilterSubList &sublist) noexcept -> size_t
        { return cur + static_cast<uint>(al::popcount(~sublist.FreeMask)); });
    if(count > 0)
        WARN("%zu Filter%s not deleted\n", count, (count==1)?"":"s");
}

void ALCdevice::enumerateHrtfs()
{
    mHrtfList = EnumerateHrtf(configValue<std::string>({}, "hrtf-paths"));
    if(auto defhrtfopt = configValue<std::string>({}, "default-hrtf"))
    {
        auto iter = std::find(mHrtfList.begin(), mHrtfList.end(), *defhrtfopt);
        if(iter == mHrtfList.end())
            WARN("Failed to find default HRTF \"%s\"\n", defhrtfopt->c_str());
        else if(iter != mHrtfList.begin())
            std::rotate(mHrtfList.begin(), iter, iter+1);
    }
}

auto ALCdevice::getOutputMode1() const noexcept -> OutputMode1
{
    if(mContexts.load(std::memory_order_relaxed)->empty())
        return OutputMode1::Any;

    switch(FmtChans)
    {
    case DevFmtMono: return OutputMode1::Mono;
    case DevFmtStereo:
        if(mHrtf)
            return OutputMode1::Hrtf;
        else if(mUhjEncoder)
            return OutputMode1::Uhj2;
        return OutputMode1::StereoBasic;
    case DevFmtQuad: return OutputMode1::Quad;
    case DevFmtX51: return OutputMode1::X51;
    case DevFmtX61: return OutputMode1::X61;
    case DevFmtX71: return OutputMode1::X71;
    case DevFmtX714:
    case DevFmtX7144:
    case DevFmtX3D71:
    case DevFmtAmbi3D:
        break;
    }
    return OutputMode1::Any;
}
