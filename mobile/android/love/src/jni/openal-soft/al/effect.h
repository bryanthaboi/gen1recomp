#ifndef AL_EFFECT_H
#define AL_EFFECT_H

#include <array>
#include <bitset>
#include <cstdint>
#include <string_view>
#include <utility>

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/efx.h"

#include "almalloc.h"
#include "alnumeric.h"
#include "core/effects/base.h"
#include "effects/effects.h"


enum {
    EAXREVERB_EFFECT = 0,
    REVERB_EFFECT,
    AUTOWAH_EFFECT,
    CHORUS_EFFECT,
    COMPRESSOR_EFFECT,
    DISTORTION_EFFECT,
    ECHO_EFFECT,
    EQUALIZER_EFFECT,
    FLANGER_EFFECT,
    FSHIFTER_EFFECT,
    MODULATOR_EFFECT,
    PSHIFTER_EFFECT,
    VMORPHER_EFFECT,
    DEDICATED_EFFECT,
    CONVOLUTION_EFFECT,

    MAX_EFFECTS
};
inline std::bitset<MAX_EFFECTS> DisabledEffects;

struct EffectList {
    const char name[16]; /* NOLINT(*-avoid-c-arrays) */
    ALuint type;
    ALenum val;
};
extern const std::array<EffectList,16> gEffectList;

using EffectHandlerVariant = std::variant<NullEffectHandler,ReverbEffectHandler,
    StdReverbEffectHandler,AutowahEffectHandler,ChorusEffectHandler,CompressorEffectHandler,
    DistortionEffectHandler,EchoEffectHandler,EqualizerEffectHandler,FlangerEffectHandler,
    FshifterEffectHandler,ModulatorEffectHandler,PshifterEffectHandler,VmorpherEffectHandler,
    DedicatedDialogEffectHandler,DedicatedLfeEffectHandler,ConvolutionEffectHandler>;

struct ALeffect {
    // Effect type (AL_EFFECT_NULL, ...)
    ALenum type{AL_EFFECT_NULL};

    EffectHandlerVariant PropsVariant;
    EffectProps Props{};

    /* Self ID */
    ALuint id{0u};

    static void SetName(ALCcontext *context, ALuint id, std::string_view name);

    DISABLE_ALLOC
};

void InitEffect(ALeffect *effect);

void LoadReverbPreset(const std::string_view name, ALeffect *effect);

bool IsValidEffectType(ALenum type) noexcept;

struct EffectSubList {
    uint64_t FreeMask{~0_u64};
    gsl::owner<std::array<ALeffect,64>*> Effects{nullptr}; /* 64 */

    EffectSubList() noexcept = default;
    EffectSubList(const EffectSubList&) = delete;
    EffectSubList(EffectSubList&& rhs) noexcept : FreeMask{rhs.FreeMask}, Effects{rhs.Effects}
    { rhs.FreeMask = ~0_u64; rhs.Effects = nullptr; }
    ~EffectSubList();

    EffectSubList& operator=(const EffectSubList&) = delete;
    EffectSubList& operator=(EffectSubList&& rhs) noexcept
    { std::swap(FreeMask, rhs.FreeMask); std::swap(Effects, rhs.Effects); return *this; }
};

#endif
