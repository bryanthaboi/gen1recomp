#ifndef CORE_CONTEXT_H
#define CORE_CONTEXT_H

#include "config.h"

#include <array>
#include <atomic>
#include <bitset>
#include <cstddef>
#include <memory>
#include <thread>
#include <vector>

#include "alsem.h"
#include "alspan.h"
#include "async_event.h"
#include "atomic.h"
#include "flexarray.h"
#include "opthelpers.h"
#include "vecmat.h"

struct DeviceBase;
struct EffectSlot;
struct EffectSlotProps;
struct RingBuffer;
struct Voice;
struct VoiceChange;
struct VoicePropsItem;


inline constexpr float SpeedOfSoundMetersPerSec{343.3f};

inline constexpr float AirAbsorbGainHF{0.99426f}; /* -0.05dB */

enum class DistanceModel : unsigned char {
    Disable,
    Inverse, InverseClamped,
    Linear, LinearClamped,
    Exponent, ExponentClamped,

    Default = InverseClamped
};


struct ContextProps {
    std::array<float,3> Position;
    std::array<float,3> Velocity;
    std::array<float,3> OrientAt;
    std::array<float,3> OrientUp;
    float Gain;
    float MetersPerUnit;
    float AirAbsorptionGainHF;

    float DopplerFactor;
    float DopplerVelocity;
    float SpeedOfSound;
#if ALSOFT_EAX
    float DistanceFactor;
#endif
    bool SourceDistanceModel;
    DistanceModel mDistanceModel;

    std::atomic<ContextProps*> next;
};

struct ContextParams {
    /* Pointer to the most recent property values that are awaiting an update. */
    std::atomic<ContextProps*> ContextUpdate{nullptr};

    alu::Vector Position{};
    alu::Matrix Matrix{alu::Matrix::Identity()};
    alu::Vector Velocity{};

    float Gain{1.0f};
    float MetersPerUnit{1.0f};
    float AirAbsorptionGainHF{AirAbsorbGainHF};

    float DopplerFactor{1.0f};
    float SpeedOfSound{SpeedOfSoundMetersPerSec}; /* in units per sec! */

    bool SourceDistanceModel{false};
    DistanceModel mDistanceModel{};
};

struct ContextBase {
    DeviceBase *const mDevice;

    /* Counter for the pre-mixing updates, in 31.1 fixed point (lowest bit
     * indicates if updates are currently happening).
     */
    std::atomic<unsigned int> mUpdateCount{0u};
    std::atomic<bool> mHoldUpdates{false};
    std::atomic<bool> mStopVoicesOnDisconnect{true};

    float mGainBoost{1.0f};

    /* Linked lists of unused property containers, free to use for future
     * updates.
     */
    std::atomic<ContextProps*> mFreeContextProps{nullptr};
    std::atomic<VoicePropsItem*> mFreeVoiceProps{nullptr};
    std::atomic<EffectSlotProps*> mFreeEffectSlotProps{nullptr};

    /* The voice change tail is the beginning of the "free" elements, up to and
     * *excluding* the current. If tail==current, there's no free elements and
     * new ones need to be allocated. The current voice change is the element
     * last processed, and any after are pending.
     */
    VoiceChange *mVoiceChangeTail{};
    std::atomic<VoiceChange*> mCurrentVoiceChange{};

    void allocVoiceChanges();
    void allocVoiceProps();
    void allocEffectSlotProps();
    void allocContextProps();

    ContextParams mParams;

    using VoiceArray = al::FlexArray<Voice*>;
    al::atomic_unique_ptr<VoiceArray> mVoices{};
    std::atomic<size_t> mActiveVoiceCount{};

    void allocVoices(size_t addcount);
    [[nodiscard]] auto getVoicesSpan() const noexcept -> al::span<Voice*>
    {
        return {mVoices.load(std::memory_order_relaxed)->data(),
            mActiveVoiceCount.load(std::memory_order_relaxed)};
    }
    [[nodiscard]] auto getVoicesSpanAcquired() const noexcept -> al::span<Voice*>
    {
        return {mVoices.load(std::memory_order_acquire)->data(),
            mActiveVoiceCount.load(std::memory_order_acquire)};
    }


    using EffectSlotArray = al::FlexArray<EffectSlot*>;
    /* This array is split in half. The front half is the list of activated
     * effect slots as set by the app, and the back half is the same list but
     * sorted to ensure later effect slots are fed by earlier ones.
     */
    al::atomic_unique_ptr<EffectSlotArray> mActiveAuxSlots;

    std::thread mEventThread;
    al::semaphore mEventSem;
    std::unique_ptr<RingBuffer> mAsyncEvents;
    using AsyncEventBitset = std::bitset<al::to_underlying(AsyncEnableBits::Count)>;
    std::atomic<AsyncEventBitset> mEnabledEvts{0u};

    /* Asynchronous voice change actions are processed as a linked list of
     * VoiceChange objects by the mixer, which is atomically appended to.
     * However, to avoid allocating each object individually, they're allocated
     * in clusters that are stored in a vector for easy automatic cleanup.
     */
    using VoiceChangeCluster = std::unique_ptr<std::array<VoiceChange,128>>;
    std::vector<VoiceChangeCluster> mVoiceChangeClusters;

    using VoiceCluster = std::unique_ptr<std::array<Voice,32>>;
    std::vector<VoiceCluster> mVoiceClusters;

    using VoicePropsCluster = std::unique_ptr<std::array<VoicePropsItem,32>>;
    std::vector<VoicePropsCluster> mVoicePropClusters;


    EffectSlot *getEffectSlot();

    using EffectSlotCluster = std::unique_ptr<std::array<EffectSlot,4>>;
    std::vector<EffectSlotCluster> mEffectSlotClusters;

    using EffectSlotPropsCluster = std::unique_ptr<std::array<EffectSlotProps,4>>;
    std::vector<EffectSlotPropsCluster> mEffectSlotPropClusters;

    /* This could be greater than 2, but there should be no way there can be
     * more than two context property updates in use simultaneously.
     */
    using ContextPropsCluster = std::unique_ptr<std::array<ContextProps,2>>;
    std::vector<ContextPropsCluster> mContextPropClusters;


    ContextBase(DeviceBase *device);
    ContextBase(const ContextBase&) = delete;
    ContextBase& operator=(const ContextBase&) = delete;
    virtual ~ContextBase();
};

#endif /* CORE_CONTEXT_H */
