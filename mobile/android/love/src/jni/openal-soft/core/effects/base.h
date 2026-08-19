#ifndef CORE_EFFECTS_BASE_H
#define CORE_EFFECTS_BASE_H

#include <array>
#include <cstddef>
#include <variant>

#include "alspan.h"
#include "core/bufferline.h"
#include "intrusive_ptr.h"
#include "opthelpers.h"

struct BufferStorage;
struct ContextBase;
struct DeviceBase;
struct EffectSlot;
struct MixParams;
struct RealMixParams;


/** Target gain for the reverb decay feedback reaching the decay time. */
inline constexpr float ReverbDecayGain{0.001f}; /* -60 dB */

inline constexpr float ReverbMaxReflectionsDelay{0.3f};
inline constexpr float ReverbMaxLateReverbDelay{0.1f};

enum class ChorusWaveform {
    Sinusoid,
    Triangle
};

inline constexpr float ChorusMaxDelay{0.016f};
inline constexpr float FlangerMaxDelay{0.004f};

inline constexpr float EchoMaxDelay{0.207f};
inline constexpr float EchoMaxLRDelay{0.404f};

enum class FShifterDirection {
    Down,
    Up,
    Off
};

enum class ModulatorWaveform {
    Sinusoid,
    Sawtooth,
    Square
};

enum class VMorpherPhenome {
    A, E, I, O, U,
    AA, AE, AH, AO, EH, ER, IH, IY, UH, UW,
    B, D, F, G, J, K, L, M, N, P, R, S, T, V, Z
};

enum class VMorpherWaveform {
    Sinusoid,
    Triangle,
    Sawtooth
};

struct ReverbProps {
    float Density;
    float Diffusion;
    float Gain;
    float GainHF;
    float GainLF;
    float DecayTime;
    float DecayHFRatio;
    float DecayLFRatio;
    float ReflectionsGain;
    float ReflectionsDelay;
    std::array<float,3> ReflectionsPan;
    float LateReverbGain;
    float LateReverbDelay;
    std::array<float,3> LateReverbPan;
    float EchoTime;
    float EchoDepth;
    float ModulationTime;
    float ModulationDepth;
    float AirAbsorptionGainHF;
    float HFReference;
    float LFReference;
    float RoomRolloffFactor;
    bool DecayHFLimit;
};

struct AutowahProps {
    float AttackTime;
    float ReleaseTime;
    float Resonance;
    float PeakGain;
};

struct ChorusProps {
    ChorusWaveform Waveform;
    int Phase;
    float Rate;
    float Depth;
    float Feedback;
    float Delay;
};

struct CompressorProps {
    bool OnOff;
};

struct DistortionProps {
    float Edge;
    float Gain;
    float LowpassCutoff;
    float EQCenter;
    float EQBandwidth;
};

struct EchoProps {
    float Delay;
    float LRDelay;

    float Damping;
    float Feedback;

    float Spread;
};

struct EqualizerProps {
    float LowCutoff;
    float LowGain;
    float Mid1Center;
    float Mid1Gain;
    float Mid1Width;
    float Mid2Center;
    float Mid2Gain;
    float Mid2Width;
    float HighCutoff;
    float HighGain;
};

struct FshifterProps {
    float Frequency;
    FShifterDirection LeftDirection;
    FShifterDirection RightDirection;
};

struct ModulatorProps {
    float Frequency;
    float HighPassCutoff;
    ModulatorWaveform Waveform;
};

struct PshifterProps {
    int CoarseTune;
    int FineTune;
};

struct VmorpherProps {
    float Rate;
    VMorpherPhenome PhonemeA;
    VMorpherPhenome PhonemeB;
    int PhonemeACoarseTuning;
    int PhonemeBCoarseTuning;
    VMorpherWaveform Waveform;
};

struct DedicatedProps {
    enum TargetType : bool { Dialog, Lfe };
    TargetType Target;
    float Gain;
};

struct ConvolutionProps {
    std::array<float,3> OrientAt;
    std::array<float,3> OrientUp;
};

using EffectProps = std::variant<std::monostate,
    ReverbProps,
    AutowahProps,
    ChorusProps,
    CompressorProps,
    DistortionProps,
    EchoProps,
    EqualizerProps,
    FshifterProps,
    ModulatorProps,
    PshifterProps,
    VmorpherProps,
    DedicatedProps,
    ConvolutionProps>;


struct EffectTarget {
    MixParams *Main;
    RealMixParams *RealOut;
};

struct SIMDALIGN EffectState : public al::intrusive_ref<EffectState> {
    al::span<FloatBufferLine> mOutTarget;


    virtual ~EffectState() = default;

    virtual void deviceUpdate(const DeviceBase *device, const BufferStorage *buffer) = 0;
    virtual void update(const ContextBase *context, const EffectSlot *slot,
        const EffectProps *props, const EffectTarget target) = 0;
    virtual void process(const size_t samplesToDo, const al::span<const FloatBufferLine> samplesIn,
        const al::span<FloatBufferLine> samplesOut) = 0;
};


struct EffectStateFactory {
    EffectStateFactory() = default;
    EffectStateFactory(const EffectStateFactory&) = delete;
    EffectStateFactory(EffectStateFactory&&) = delete;
    virtual ~EffectStateFactory() = default;

    void operator=(const EffectStateFactory&) = delete;
    void operator=(EffectStateFactory&&) = delete;

    virtual al::intrusive_ptr<EffectState> create() = 0;
};

#endif /* CORE_EFFECTS_BASE_H */
