#ifndef CORE_VOICE_H
#define CORE_VOICE_H

#include <array>
#include <atomic>
#include <bitset>
#include <chrono>
#include <cstddef>
#include <memory>
#include <optional>
#include <string>

#include "alspan.h"
#include "bufferline.h"
#include "buffer_storage.h"
#include "devformat.h"
#include "filters/biquad.h"
#include "filters/nfc.h"
#include "filters/splitter.h"
#include "mixer/defs.h"
#include "mixer/hrtfdefs.h"
#include "opthelpers.h"
#include "resampler_limits.h"
#include "uhjfilter.h"
#include "vector.h"

struct ContextBase;
struct DeviceBase;
struct EffectSlot;
enum class DistanceModel : unsigned char;

using uint = unsigned int;


inline constexpr size_t MaxSendCount{6};


enum class SpatializeMode : unsigned char {
    Off,
    On,
    Auto
};

enum class DirectMode : unsigned char {
    Off,
    DropMismatch,
    RemixMismatch
};


inline constexpr uint MaxPitch{10};


enum {
    AF_None = 0,
    AF_LowPass = 1,
    AF_HighPass = 2,
    AF_BandPass = AF_LowPass | AF_HighPass
};


struct DirectParams {
    BiquadFilter LowPass;
    BiquadFilter HighPass;

    NfcFilter NFCtrlFilter;

    struct HrtfParams {
        HrtfFilter Old{};
        HrtfFilter Target{};
        alignas(16) std::array<float,HrtfHistoryLength> History{};
    };
    HrtfParams Hrtf;

    struct GainParams {
        std::array<float,MaxOutputChannels> Current{};
        std::array<float,MaxOutputChannels> Target{};
    };
    GainParams Gains;
};

struct SendParams {
    BiquadFilter LowPass;
    BiquadFilter HighPass;

    struct GainParams {
        std::array<float,MaxAmbiChannels> Current{};
        std::array<float,MaxAmbiChannels> Target{};
    };
    GainParams Gains;
};


struct VoiceBufferItem {
    std::atomic<VoiceBufferItem*> mNext{nullptr};

    CallbackType mCallback{nullptr};
    void *mUserData{nullptr};

    uint mBlockAlign{0u};
    uint mSampleLen{0u};
    uint mLoopStart{0u};
    uint mLoopEnd{0u};

    al::span<std::byte> mSamples{};

protected:
    ~VoiceBufferItem() = default;
};


struct VoiceProps {
    float Pitch;
    float Gain;
    float OuterGain;
    float MinGain;
    float MaxGain;
    float InnerAngle;
    float OuterAngle;
    float RefDistance;
    float MaxDistance;
    float RolloffFactor;
    std::array<float,3> Position;
    std::array<float,3> Velocity;
    std::array<float,3> Direction;
    std::array<float,3> OrientAt;
    std::array<float,3> OrientUp;
    bool HeadRelative;
    DistanceModel mDistanceModel;
    Resampler mResampler;
    DirectMode DirectChannels;
    SpatializeMode mSpatializeMode;

    bool DryGainHFAuto;
    bool WetGainAuto;
    bool WetGainHFAuto;
    float OuterGainHF;

    float AirAbsorptionFactor;
    float RoomRolloffFactor;
    float DopplerFactor;

    std::array<float,2> StereoPan;

    float Radius;
    float EnhWidth;
    float Panning;

    /** Direct filter and auxiliary send info. */
    struct DirectData {
        float Gain;
        float GainHF;
        float HFReference;
        float GainLF;
        float LFReference;
    };
    DirectData Direct;

    struct SendData {
        EffectSlot *Slot;
        float Gain;
        float GainHF;
        float HFReference;
        float GainLF;
        float LFReference;
    };
    std::array<SendData,MaxSendCount> Send;
};

struct VoicePropsItem : public VoiceProps {
    std::atomic<VoicePropsItem*> next{nullptr};
};

enum : uint {
    VoiceIsStatic,
    VoiceIsCallback,
    VoiceIsAmbisonic,
    VoiceCallbackStopped,
    VoiceIsFading,
    VoiceHasHrtf,
    VoiceHasNfc,

    VoiceFlagCount
};

struct SIMDALIGN Voice {
    enum State {
        Stopped,
        Playing,
        Stopping,
        Pending
    };

    std::atomic<VoicePropsItem*> mUpdate{nullptr};

    VoiceProps mProps{};

    std::atomic<uint> mSourceID{0u};
    std::atomic<State> mPlayState{Stopped};
    std::atomic<bool> mPendingChange{false};

    /**
     * Source offset in samples, relative to the currently playing buffer, NOT
     * the whole queue.
     */
    std::atomic<int> mPosition{};
    /** Fractional (fixed-point) offset to the next sample. */
    std::atomic<uint> mPositionFrac{};

    /* Current buffer queue item being played. */
    std::atomic<VoiceBufferItem*> mCurrentBuffer{};

    /* Buffer queue item to loop to at end of queue (will be NULL for non-
     * looping voices).
     */
    std::atomic<VoiceBufferItem*> mLoopBuffer{};

    std::chrono::nanoseconds mStartTime{};

    /* Properties for the attached buffer(s). */
    FmtChannels mFmtChannels{};
    FmtType mFmtType{};
    uint mFrequency{};
    uint mFrameStep{}; /**< In steps of the sample type size. */
    uint mBytesPerBlock{}; /**< Or for PCM formats, BytesPerFrame. */
    uint mSamplesPerBlock{}; /**< Always 1 for PCM formats. */
    AmbiLayout mAmbiLayout{};
    AmbiScaling mAmbiScaling{};
    uint mAmbiOrder{};

    std::unique_ptr<DecoderBase> mDecoder;
    uint mDecoderPadding{};

    /** Current target parameters used for mixing. */
    uint mStep{0};

    ResamplerFunc mResampler{};

    InterpState mResampleState{};

    std::bitset<VoiceFlagCount> mFlags{};
    uint mNumCallbackBlocks{0};
    uint mCallbackBlockBase{0};

    struct TargetData {
        int FilterType{};
        al::span<FloatBufferLine> Buffer;
    };
    TargetData mDirect;
    std::array<TargetData,MaxSendCount> mSend;

    /* The first MaxResamplerPadding/2 elements are the sample history from the
     * previous mix, with an additional MaxResamplerPadding/2 elements that are
     * now current (which may be overwritten if the buffer data is still
     * available).
     */
    using HistoryLine = std::array<float,MaxResamplerPadding>;
    al::vector<HistoryLine,16> mPrevSamples{2};

    struct ChannelData {
        float mAmbiHFScale{}, mAmbiLFScale{};
        BandSplitter mAmbiSplitter;

        DirectParams mDryParams;
        std::array<SendParams,MaxSendCount> mWetParams;
    };
    al::vector<ChannelData> mChans{2};

    Voice() = default;
    ~Voice() = default;

    Voice(const Voice&) = delete;
    Voice& operator=(const Voice&) = delete;

    void mix(const State vstate, ContextBase *Context, const std::chrono::nanoseconds deviceTime,
        const uint SamplesToDo);

    void prepare(DeviceBase *device);

    static void InitMixer(std::optional<std::string> resopt);
};

inline Resampler ResamplerDefault{Resampler::Gaussian};

#endif /* CORE_VOICE_H */
