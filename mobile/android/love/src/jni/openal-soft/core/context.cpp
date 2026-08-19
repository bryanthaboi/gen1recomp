
#include "config.h"

#include <cassert>
#include <functional>
#include <limits>
#include <memory>
#include <stdexcept>
#include <utility>

#include "async_event.h"
#include "context.h"
#include "device.h"
#include "effectslot.h"
#include "logging.h"
#include "ringbuffer.h"
#include "voice.h"
#include "voice_change.h"


#ifdef __cpp_lib_atomic_is_always_lock_free
static_assert(std::atomic<ContextBase::AsyncEventBitset>::is_always_lock_free, "atomic<bitset> isn't lock-free");
#endif

ContextBase::ContextBase(DeviceBase *device) : mDevice{device}
{ assert(mEnabledEvts.is_lock_free()); }

ContextBase::~ContextBase()
{
    mActiveAuxSlots.store(nullptr, std::memory_order_relaxed);
    mVoices.store(nullptr, std::memory_order_relaxed);

    if(mAsyncEvents)
    {
        size_t count{0};
        for(auto &evt : mAsyncEvents->getReadVector())
        {
            if(evt.len > 0)
            {
                std::destroy_n(std::launder(reinterpret_cast<AsyncEvent*>(evt.buf)), evt.len);
                count += evt.len;
            }
        }
        if(count > 0)
            TRACE("Destructed %zu orphaned event%s\n", count, (count==1)?"":"s");
        mAsyncEvents->readAdvance(count);
    }
}


void ContextBase::allocVoiceChanges()
{
    static constexpr size_t clustersize{std::tuple_size_v<VoiceChangeCluster::element_type>};

    VoiceChangeCluster clusterptr{std::make_unique<VoiceChangeCluster::element_type>()};
    const auto cluster = al::span{*clusterptr};

    for(size_t i{1};i < clustersize;++i)
        cluster[i-1].mNext.store(std::addressof(cluster[i]), std::memory_order_relaxed);
    cluster[clustersize-1].mNext.store(mVoiceChangeTail, std::memory_order_relaxed);

    mVoiceChangeClusters.emplace_back(std::move(clusterptr));
    mVoiceChangeTail = mVoiceChangeClusters.back()->data();
}

void ContextBase::allocVoiceProps()
{
    static constexpr size_t clustersize{std::tuple_size_v<VoicePropsCluster::element_type>};

    TRACE("Increasing allocated voice properties to %zu\n",
        (mVoicePropClusters.size()+1) * clustersize);

    auto clusterptr = std::make_unique<VoicePropsCluster::element_type>();
    auto cluster = al::span{*clusterptr};
    for(size_t i{1};i < clustersize;++i)
        cluster[i-1].next.store(std::addressof(cluster[i]), std::memory_order_relaxed);
    mVoicePropClusters.emplace_back(std::move(clusterptr));

    VoicePropsItem *oldhead{mFreeVoiceProps.load(std::memory_order_acquire)};
    do {
        mVoicePropClusters.back()->back().next.store(oldhead, std::memory_order_relaxed);
    } while(mFreeVoiceProps.compare_exchange_weak(oldhead, mVoicePropClusters.back()->data(),
        std::memory_order_acq_rel, std::memory_order_acquire) == false);
}

void ContextBase::allocVoices(size_t addcount)
{
    static constexpr size_t clustersize{std::tuple_size_v<VoiceCluster::element_type>};
    /* Convert element count to cluster count. */
    addcount = (addcount+(clustersize-1)) / clustersize;

    if(!addcount)
    {
        if(!mVoiceClusters.empty())
            return;
        ++addcount;
    }

    if(addcount >= std::numeric_limits<int>::max()/clustersize - mVoiceClusters.size())
        throw std::runtime_error{"Allocating too many voices"};
    const size_t totalcount{(mVoiceClusters.size()+addcount) * clustersize};
    TRACE("Increasing allocated voices to %zu\n", totalcount);

    while(addcount)
    {
        mVoiceClusters.emplace_back(std::make_unique<VoiceCluster::element_type>());
        --addcount;
    }

    auto newarray = VoiceArray::Create(totalcount);
    auto voice_iter = newarray->begin();
    for(VoiceCluster &cluster : mVoiceClusters)
        voice_iter = std::transform(cluster->begin(), cluster->end(), voice_iter,
            [](Voice &voice) noexcept -> Voice* { return &voice; });

    if(auto oldvoices = mVoices.exchange(std::move(newarray), std::memory_order_acq_rel))
        std::ignore = mDevice->waitForMix();
}


void ContextBase::allocEffectSlotProps()
{
    static constexpr size_t clustersize{std::tuple_size_v<EffectSlotPropsCluster::element_type>};

    TRACE("Increasing allocated effect slot properties to %zu\n",
        (mEffectSlotPropClusters.size()+1) * clustersize);

    auto clusterptr = std::make_unique<EffectSlotPropsCluster::element_type>();
    auto cluster = al::span{*clusterptr};
    for(size_t i{1};i < clustersize;++i)
        cluster[i-1].next.store(std::addressof(cluster[i]), std::memory_order_relaxed);
    auto *newcluster = mEffectSlotPropClusters.emplace_back(std::move(clusterptr)).get();

    EffectSlotProps *oldhead{mFreeEffectSlotProps.load(std::memory_order_acquire)};
    do {
        newcluster->back().next.store(oldhead, std::memory_order_relaxed);
    } while(mFreeEffectSlotProps.compare_exchange_weak(oldhead, newcluster->data(),
        std::memory_order_acq_rel, std::memory_order_acquire) == false);
}

EffectSlot *ContextBase::getEffectSlot()
{
    for(auto& clusterptr : mEffectSlotClusters)
    {
        const auto cluster = al::span{*clusterptr};
        auto iter = std::find_if_not(cluster.begin(), cluster.end(),
            std::mem_fn(&EffectSlot::InUse));
        if(iter != cluster.end()) return al::to_address(iter);
    }

    auto clusterptr = std::make_unique<EffectSlotCluster::element_type>();
    if(1 >= std::numeric_limits<int>::max()/clusterptr->size() - mEffectSlotClusters.size())
        throw std::runtime_error{"Allocating too many effect slots"};
    const size_t totalcount{(mEffectSlotClusters.size()+1) * clusterptr->size()};
    TRACE("Increasing allocated effect slots to %zu\n", totalcount);

    mEffectSlotClusters.emplace_back(std::move(clusterptr));
    return mEffectSlotClusters.back()->data();
}


void ContextBase::allocContextProps()
{
    static constexpr size_t clustersize{std::tuple_size_v<ContextPropsCluster::element_type>};

    TRACE("Increasing allocated context properties to %zu\n",
        (mContextPropClusters.size()+1) * clustersize);

    auto clusterptr = std::make_unique<ContextPropsCluster::element_type>();
    auto cluster = al::span{*clusterptr};
    for(size_t i{1};i < clustersize;++i)
        cluster[i-1].next.store(std::addressof(cluster[i]), std::memory_order_relaxed);
    auto *newcluster = mContextPropClusters.emplace_back(std::move(clusterptr)).get();

    ContextProps *oldhead{mFreeContextProps.load(std::memory_order_acquire)};
    do {
        newcluster->back().next.store(oldhead, std::memory_order_relaxed);
    } while(mFreeContextProps.compare_exchange_weak(oldhead, newcluster->data(),
        std::memory_order_acq_rel, std::memory_order_acquire) == false);
}
