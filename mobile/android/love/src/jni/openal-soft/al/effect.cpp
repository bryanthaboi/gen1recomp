/**
 * OpenAL cross platform audio library
 * Copyright (C) 1999-2007 by authors.
 * This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 *  License along with this library; if not, write to the
 *  Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 * Or go to http://www.gnu.org/copyleft/lgpl.html
 */

#include "config.h"

#include "effect.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <iterator>
#include <memory>
#include <mutex>
#include <numeric>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <variant>
#include <vector>

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/alext.h"
#include "AL/efx-presets.h"
#include "AL/efx.h"

#include "al/effects/effects.h"
#include "albit.h"
#include "alc/context.h"
#include "alc/device.h"
#include "alc/inprogext.h"
#include "almalloc.h"
#include "alnumeric.h"
#include "alspan.h"
#include "alstring.h"
#include "core/logging.h"
#include "direct_defs.h"
#include "error.h"
#include "intrusive_ptr.h"
#include "opthelpers.h"


const std::array<EffectList,16> gEffectList{{
    { "eaxreverb",   EAXREVERB_EFFECT,   AL_EFFECT_EAXREVERB },
    { "reverb",      REVERB_EFFECT,      AL_EFFECT_REVERB },
    { "autowah",     AUTOWAH_EFFECT,     AL_EFFECT_AUTOWAH },
    { "chorus",      CHORUS_EFFECT,      AL_EFFECT_CHORUS },
    { "compressor",  COMPRESSOR_EFFECT,  AL_EFFECT_COMPRESSOR },
    { "distortion",  DISTORTION_EFFECT,  AL_EFFECT_DISTORTION },
    { "echo",        ECHO_EFFECT,        AL_EFFECT_ECHO },
    { "equalizer",   EQUALIZER_EFFECT,   AL_EFFECT_EQUALIZER },
    { "flanger",     FLANGER_EFFECT,     AL_EFFECT_FLANGER },
    { "fshifter",    FSHIFTER_EFFECT,    AL_EFFECT_FREQUENCY_SHIFTER },
    { "modulator",   MODULATOR_EFFECT,   AL_EFFECT_RING_MODULATOR },
    { "pshifter",    PSHIFTER_EFFECT,    AL_EFFECT_PITCH_SHIFTER },
    { "vmorpher",    VMORPHER_EFFECT,    AL_EFFECT_VOCAL_MORPHER },
    { "dedicated",   DEDICATED_EFFECT,   AL_EFFECT_DEDICATED_LOW_FREQUENCY_EFFECT },
    { "dedicated",   DEDICATED_EFFECT,   AL_EFFECT_DEDICATED_DIALOGUE },
    { "convolution", CONVOLUTION_EFFECT, AL_EFFECT_CONVOLUTION_SOFT },
}};


namespace {

using SubListAllocator = al::allocator<std::array<ALeffect,64>>;

constexpr auto GetDefaultProps(ALenum type) noexcept -> const EffectProps&
{
    switch(type)
    {
    case AL_EFFECT_NULL: return NullEffectProps;
    case AL_EFFECT_EAXREVERB: return ReverbEffectProps;
    case AL_EFFECT_REVERB: return StdReverbEffectProps;
    case AL_EFFECT_AUTOWAH: return AutowahEffectProps;
    case AL_EFFECT_CHORUS: return ChorusEffectProps;
    case AL_EFFECT_COMPRESSOR: return CompressorEffectProps;
    case AL_EFFECT_DISTORTION: return DistortionEffectProps;
    case AL_EFFECT_ECHO: return EchoEffectProps;
    case AL_EFFECT_EQUALIZER: return EqualizerEffectProps;
    case AL_EFFECT_FLANGER: return FlangerEffectProps;
    case AL_EFFECT_FREQUENCY_SHIFTER: return FshifterEffectProps;
    case AL_EFFECT_RING_MODULATOR: return ModulatorEffectProps;
    case AL_EFFECT_PITCH_SHIFTER: return PshifterEffectProps;
    case AL_EFFECT_VOCAL_MORPHER: return VmorpherEffectProps;
    case AL_EFFECT_DEDICATED_DIALOGUE: return DedicatedDialogEffectProps;
    case AL_EFFECT_DEDICATED_LOW_FREQUENCY_EFFECT: return DedicatedLfeEffectProps;
    case AL_EFFECT_CONVOLUTION_SOFT: return ConvolutionEffectProps;
    }
    return NullEffectProps;
}

void InitEffectParams(ALeffect *effect, ALenum type) noexcept
{
    switch(type)
    {
    case AL_EFFECT_NULL: effect->PropsVariant.emplace<NullEffectHandler>(); break;
    case AL_EFFECT_EAXREVERB: effect->PropsVariant.emplace<ReverbEffectHandler>(); break;
    case AL_EFFECT_REVERB: effect->PropsVariant.emplace<StdReverbEffectHandler>(); break;
    case AL_EFFECT_AUTOWAH: effect->PropsVariant.emplace<AutowahEffectHandler>(); break;
    case AL_EFFECT_CHORUS: effect->PropsVariant.emplace<ChorusEffectHandler>(); break;
    case AL_EFFECT_COMPRESSOR: effect->PropsVariant.emplace<CompressorEffectHandler>(); break;
    case AL_EFFECT_DISTORTION: effect->PropsVariant.emplace<DistortionEffectHandler>(); break;
    case AL_EFFECT_ECHO: effect->PropsVariant.emplace<EchoEffectHandler>(); break;
    case AL_EFFECT_EQUALIZER: effect->PropsVariant.emplace<EqualizerEffectHandler>(); break;
    case AL_EFFECT_FLANGER: effect->PropsVariant.emplace<ChorusEffectHandler>(); break;
    case AL_EFFECT_FREQUENCY_SHIFTER: effect->PropsVariant.emplace<FshifterEffectHandler>(); break;
    case AL_EFFECT_RING_MODULATOR: effect->PropsVariant.emplace<ModulatorEffectHandler>(); break;
    case AL_EFFECT_PITCH_SHIFTER: effect->PropsVariant.emplace<PshifterEffectHandler>(); break;
    case AL_EFFECT_VOCAL_MORPHER: effect->PropsVariant.emplace<VmorpherEffectHandler>(); break;
    case AL_EFFECT_DEDICATED_DIALOGUE:
        effect->PropsVariant.emplace<DedicatedDialogEffectHandler>();
        break;
    case AL_EFFECT_DEDICATED_LOW_FREQUENCY_EFFECT:
        effect->PropsVariant.emplace<DedicatedLfeEffectHandler>();
        break;
    case AL_EFFECT_CONVOLUTION_SOFT:
        effect->PropsVariant.emplace<ConvolutionEffectHandler>();
        break;
    }
    effect->Props = GetDefaultProps(type);
    effect->type = type;
}

auto EnsureEffects(ALCdevice *device, size_t needed) noexcept -> bool
try {
    size_t count{std::accumulate(device->EffectList.cbegin(), device->EffectList.cend(), 0_uz,
        [](size_t cur, const EffectSubList &sublist) noexcept -> size_t
        { return cur + static_cast<ALuint>(al::popcount(sublist.FreeMask)); })};

    while(needed > count)
    {
        if(device->EffectList.size() >= 1<<25) UNLIKELY
            return false;

        EffectSubList sublist{};
        sublist.FreeMask = ~0_u64;
        sublist.Effects = SubListAllocator{}.allocate(1);
        device->EffectList.emplace_back(std::move(sublist));
        count += std::tuple_size_v<SubListAllocator::value_type>;
    }
    return true;
}
catch(...) {
    return false;
}

ALeffect *AllocEffect(ALCdevice *device) noexcept
{
    auto sublist = std::find_if(device->EffectList.begin(), device->EffectList.end(),
        [](const EffectSubList &entry) noexcept -> bool
        { return entry.FreeMask != 0; });
    auto lidx = static_cast<ALuint>(std::distance(device->EffectList.begin(), sublist));
    auto slidx = static_cast<ALuint>(al::countr_zero(sublist->FreeMask));
    ASSUME(slidx < 64);

    ALeffect *effect{al::construct_at(al::to_address(sublist->Effects->begin() + slidx))};
    InitEffectParams(effect, AL_EFFECT_NULL);

    /* Add 1 to avoid effect ID 0. */
    effect->id = ((lidx<<6) | slidx) + 1;

    sublist->FreeMask &= ~(1_u64 << slidx);

    return effect;
}

void FreeEffect(ALCdevice *device, ALeffect *effect)
{
    device->mEffectNames.erase(effect->id);

    const ALuint id{effect->id - 1};
    const size_t lidx{id >> 6};
    const ALuint slidx{id & 0x3f};

    std::destroy_at(effect);

    device->EffectList[lidx].FreeMask |= 1_u64 << slidx;
}

inline auto LookupEffect(ALCdevice *device, ALuint id) noexcept -> ALeffect*
{
    const size_t lidx{(id-1) >> 6};
    const ALuint slidx{(id-1) & 0x3f};

    if(lidx >= device->EffectList.size()) UNLIKELY
        return nullptr;
    EffectSubList &sublist = device->EffectList[lidx];
    if(sublist.FreeMask & (1_u64 << slidx)) UNLIKELY
        return nullptr;
    return al::to_address(sublist.Effects->begin() + slidx);
}

} // namespace

AL_API DECL_FUNC2(void, alGenEffects, ALsizei,n, ALuint*,effects)
FORCE_ALIGN void AL_APIENTRY alGenEffectsDirect(ALCcontext *context, ALsizei n, ALuint *effects) noexcept
try {
    if(n < 0)
        throw al::context_error{AL_INVALID_VALUE, "Generating %d effects", n};
    if(n <= 0) UNLIKELY return;

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    const al::span eids{effects, static_cast<ALuint>(n)};
    if(!EnsureEffects(device, eids.size()))
        throw al::context_error{AL_OUT_OF_MEMORY, "Failed to allocate %d effect%s", n,
            (n == 1) ? "" : "s"};

    std::generate(eids.begin(), eids.end(), [device]{ return AllocEffect(device)->id; });
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC2(void, alDeleteEffects, ALsizei,n, const ALuint*,effects)
FORCE_ALIGN void AL_APIENTRY alDeleteEffectsDirect(ALCcontext *context, ALsizei n,
    const ALuint *effects) noexcept
try {
    if(n < 0)
        throw al::context_error{AL_INVALID_VALUE, "Deleting %d effects", n};
    if(n <= 0) UNLIKELY return;

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    /* First try to find any effects that are invalid. */
    auto validate_effect = [device](const ALuint eid) -> bool
    { return !eid || LookupEffect(device, eid) != nullptr; };

    const al::span eids{effects, static_cast<ALuint>(n)};
    auto inveffect = std::find_if_not(eids.begin(), eids.end(), validate_effect);
    if(inveffect != eids.end())
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", *inveffect};

    /* All good. Delete non-0 effect IDs. */
    auto delete_effect = [device](ALuint eid) -> void
    {
        if(ALeffect *effect{eid ? LookupEffect(device, eid) : nullptr})
            FreeEffect(device, effect);
    };
    std::for_each(eids.begin(), eids.end(), delete_effect);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC1(ALboolean, alIsEffect, ALuint,effect)
FORCE_ALIGN ALboolean AL_APIENTRY alIsEffectDirect(ALCcontext *context, ALuint effect) noexcept
{
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};
    if(!effect || LookupEffect(device, effect))
        return AL_TRUE;
    return AL_FALSE;
}

AL_API DECL_FUNC3(void, alEffecti, ALuint,effect, ALenum,param, ALint,value)
FORCE_ALIGN void AL_APIENTRY alEffectiDirect(ALCcontext *context, ALuint effect, ALenum param,
    ALint value) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    ALeffect *aleffect{LookupEffect(device, effect)};
    if(!aleffect)
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", effect};

    switch(param)
    {
    case AL_EFFECT_TYPE:
        if(value != AL_EFFECT_NULL)
        {
            auto check_effect = [value](const EffectList &item) -> bool
            { return value == item.val && !DisabledEffects.test(item.type); };
            if(!std::any_of(gEffectList.cbegin(), gEffectList.cend(), check_effect))
                throw al::context_error{AL_INVALID_VALUE, "Effect type 0x%04x not supported",
                    value};
        }

        InitEffectParams(aleffect, value);
        return;
    }

    /* Call the appropriate handler */
    std::visit([aleffect,param,value](auto &arg)
    {
        using Type = std::remove_cv_t<std::remove_reference_t<decltype(arg)>>;
        using PropType = typename Type::prop_type;
        return arg.SetParami(std::get<PropType>(aleffect->Props), param, value);
    }, aleffect->PropsVariant);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alEffectiv, ALuint,effect, ALenum,param, const ALint*,values)
FORCE_ALIGN void AL_APIENTRY alEffectivDirect(ALCcontext *context, ALuint effect, ALenum param,
    const ALint *values) noexcept
try {
    switch(param)
    {
    case AL_EFFECT_TYPE:
        alEffectiDirect(context, effect, param, *values);
        return;
    }

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    ALeffect *aleffect{LookupEffect(device, effect)};
    if(!aleffect)
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", effect};

    /* Call the appropriate handler */
    std::visit([aleffect,param,values](auto &arg)
    {
        using Type = std::remove_cv_t<std::remove_reference_t<decltype(arg)>>;
        using PropType = typename Type::prop_type;
        return arg.SetParamiv(std::get<PropType>(aleffect->Props), param, values);
    }, aleffect->PropsVariant);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alEffectf, ALuint,effect, ALenum,param, ALfloat,value)
FORCE_ALIGN void AL_APIENTRY alEffectfDirect(ALCcontext *context, ALuint effect, ALenum param,
    ALfloat value) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    ALeffect *aleffect{LookupEffect(device, effect)};
    if(!aleffect) UNLIKELY
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", effect};

    /* Call the appropriate handler */
    std::visit([aleffect,param,value](auto &arg)
    {
        using Type = std::remove_cv_t<std::remove_reference_t<decltype(arg)>>;
        using PropType = typename Type::prop_type;
        return arg.SetParamf(std::get<PropType>(aleffect->Props), param, value);
    }, aleffect->PropsVariant);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alEffectfv, ALuint,effect, ALenum,param, const ALfloat*,values)
FORCE_ALIGN void AL_APIENTRY alEffectfvDirect(ALCcontext *context, ALuint effect, ALenum param,
    const ALfloat *values) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    ALeffect *aleffect{LookupEffect(device, effect)};
    if(!aleffect)
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", effect};

    /* Call the appropriate handler */
    std::visit([aleffect,param,values](auto &arg)
    {
        using Type = std::remove_cv_t<std::remove_reference_t<decltype(arg)>>;
        using PropType = typename Type::prop_type;
        return arg.SetParamfv(std::get<PropType>(aleffect->Props), param, values);
    }, aleffect->PropsVariant);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alGetEffecti, ALuint,effect, ALenum,param, ALint*,value)
FORCE_ALIGN void AL_APIENTRY alGetEffectiDirect(ALCcontext *context, ALuint effect, ALenum param,
    ALint *value) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    const ALeffect *aleffect{LookupEffect(device, effect)};
    if(!aleffect)
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", effect};

    switch(param)
    {
    case AL_EFFECT_TYPE:
        *value = aleffect->type;
        return;
    }

    /* Call the appropriate handler */
    std::visit([aleffect,param,value](auto &arg)
    {
        using Type = std::remove_cv_t<std::remove_reference_t<decltype(arg)>>;
        using PropType = typename Type::prop_type;
        return arg.GetParami(std::get<PropType>(aleffect->Props), param, value);
    }, aleffect->PropsVariant);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alGetEffectiv, ALuint,effect, ALenum,param, ALint*,values)
FORCE_ALIGN void AL_APIENTRY alGetEffectivDirect(ALCcontext *context, ALuint effect, ALenum param,
    ALint *values) noexcept
try {
    switch(param)
    {
    case AL_EFFECT_TYPE:
        alGetEffectiDirect(context, effect, param, values);
        return;
    }

    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    const ALeffect *aleffect{LookupEffect(device, effect)};
    if(!aleffect)
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", effect};

    /* Call the appropriate handler */
    std::visit([aleffect,param,values](auto &arg)
    {
        using Type = std::remove_cv_t<std::remove_reference_t<decltype(arg)>>;
        using PropType = typename Type::prop_type;
        return arg.GetParamiv(std::get<PropType>(aleffect->Props), param, values);
    }, aleffect->PropsVariant);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alGetEffectf, ALuint,effect, ALenum,param, ALfloat*,value)
FORCE_ALIGN void AL_APIENTRY alGetEffectfDirect(ALCcontext *context, ALuint effect, ALenum param,
    ALfloat *value) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    const ALeffect *aleffect{LookupEffect(device, effect)};
    if(!aleffect)
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", effect};

    /* Call the appropriate handler */
    std::visit([aleffect,param,value](auto &arg)
    {
        using Type = std::remove_cv_t<std::remove_reference_t<decltype(arg)>>;
        using PropType = typename Type::prop_type;
        return arg.GetParamf(std::get<PropType>(aleffect->Props), param, value);
    }, aleffect->PropsVariant);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC3(void, alGetEffectfv, ALuint,effect, ALenum,param, ALfloat*,values)
FORCE_ALIGN void AL_APIENTRY alGetEffectfvDirect(ALCcontext *context, ALuint effect, ALenum param,
    ALfloat *values) noexcept
try {
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    const ALeffect *aleffect{LookupEffect(device, effect)};
    if(!aleffect)
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", effect};

    /* Call the appropriate handler */
    std::visit([aleffect,param,values](auto &arg)
    {
        using Type = std::remove_cv_t<std::remove_reference_t<decltype(arg)>>;
        using PropType = typename Type::prop_type;
        return arg.GetParamfv(std::get<PropType>(aleffect->Props), param, values);
    }, aleffect->PropsVariant);
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


void InitEffect(ALeffect *effect)
{
    InitEffectParams(effect, AL_EFFECT_NULL);
}

void ALeffect::SetName(ALCcontext* context, ALuint id, std::string_view name)
{
    ALCdevice *device{context->mALDevice.get()};
    std::lock_guard<std::mutex> effectlock{device->EffectLock};

    auto effect = LookupEffect(device, id);
    if(!effect)
        throw al::context_error{AL_INVALID_NAME, "Invalid effect ID %u", id};

    device->mEffectNames.insert_or_assign(id, name);
}


EffectSubList::~EffectSubList()
{
    if(!Effects)
        return;

    uint64_t usemask{~FreeMask};
    while(usemask)
    {
        const int idx{al::countr_zero(usemask)};
        std::destroy_at(al::to_address(Effects->begin()+idx));
        usemask &= ~(1_u64 << idx);
    }
    FreeMask = ~usemask;
    SubListAllocator{}.deallocate(Effects, 1);
    Effects = nullptr;
}


struct EffectPreset {
    const char name[32]; /* NOLINT(*-avoid-c-arrays) */
    EFXEAXREVERBPROPERTIES props;
};
#define DECL(x) EffectPreset{#x, EFX_REVERB_PRESET_##x}
static constexpr std::array reverblist{
    DECL(GENERIC),
    DECL(PADDEDCELL),
    DECL(ROOM),
    DECL(BATHROOM),
    DECL(LIVINGROOM),
    DECL(STONEROOM),
    DECL(AUDITORIUM),
    DECL(CONCERTHALL),
    DECL(CAVE),
    DECL(ARENA),
    DECL(HANGAR),
    DECL(CARPETEDHALLWAY),
    DECL(HALLWAY),
    DECL(STONECORRIDOR),
    DECL(ALLEY),
    DECL(FOREST),
    DECL(CITY),
    DECL(MOUNTAINS),
    DECL(QUARRY),
    DECL(PLAIN),
    DECL(PARKINGLOT),
    DECL(SEWERPIPE),
    DECL(UNDERWATER),
    DECL(DRUGGED),
    DECL(DIZZY),
    DECL(PSYCHOTIC),

    DECL(CASTLE_SMALLROOM),
    DECL(CASTLE_SHORTPASSAGE),
    DECL(CASTLE_MEDIUMROOM),
    DECL(CASTLE_LARGEROOM),
    DECL(CASTLE_LONGPASSAGE),
    DECL(CASTLE_HALL),
    DECL(CASTLE_CUPBOARD),
    DECL(CASTLE_COURTYARD),
    DECL(CASTLE_ALCOVE),

    DECL(FACTORY_SMALLROOM),
    DECL(FACTORY_SHORTPASSAGE),
    DECL(FACTORY_MEDIUMROOM),
    DECL(FACTORY_LARGEROOM),
    DECL(FACTORY_LONGPASSAGE),
    DECL(FACTORY_HALL),
    DECL(FACTORY_CUPBOARD),
    DECL(FACTORY_COURTYARD),
    DECL(FACTORY_ALCOVE),

    DECL(ICEPALACE_SMALLROOM),
    DECL(ICEPALACE_SHORTPASSAGE),
    DECL(ICEPALACE_MEDIUMROOM),
    DECL(ICEPALACE_LARGEROOM),
    DECL(ICEPALACE_LONGPASSAGE),
    DECL(ICEPALACE_HALL),
    DECL(ICEPALACE_CUPBOARD),
    DECL(ICEPALACE_COURTYARD),
    DECL(ICEPALACE_ALCOVE),

    DECL(SPACESTATION_SMALLROOM),
    DECL(SPACESTATION_SHORTPASSAGE),
    DECL(SPACESTATION_MEDIUMROOM),
    DECL(SPACESTATION_LARGEROOM),
    DECL(SPACESTATION_LONGPASSAGE),
    DECL(SPACESTATION_HALL),
    DECL(SPACESTATION_CUPBOARD),
    DECL(SPACESTATION_ALCOVE),

    DECL(WOODEN_SMALLROOM),
    DECL(WOODEN_SHORTPASSAGE),
    DECL(WOODEN_MEDIUMROOM),
    DECL(WOODEN_LARGEROOM),
    DECL(WOODEN_LONGPASSAGE),
    DECL(WOODEN_HALL),
    DECL(WOODEN_CUPBOARD),
    DECL(WOODEN_COURTYARD),
    DECL(WOODEN_ALCOVE),

    DECL(SPORT_EMPTYSTADIUM),
    DECL(SPORT_SQUASHCOURT),
    DECL(SPORT_SMALLSWIMMINGPOOL),
    DECL(SPORT_LARGESWIMMINGPOOL),
    DECL(SPORT_GYMNASIUM),
    DECL(SPORT_FULLSTADIUM),
    DECL(SPORT_STADIUMTANNOY),

    DECL(PREFAB_WORKSHOP),
    DECL(PREFAB_SCHOOLROOM),
    DECL(PREFAB_PRACTISEROOM),
    DECL(PREFAB_OUTHOUSE),
    DECL(PREFAB_CARAVAN),

    DECL(DOME_TOMB),
    DECL(PIPE_SMALL),
    DECL(DOME_SAINTPAULS),
    DECL(PIPE_LONGTHIN),
    DECL(PIPE_LARGE),
    DECL(PIPE_RESONANT),

    DECL(OUTDOORS_BACKYARD),
    DECL(OUTDOORS_ROLLINGPLAINS),
    DECL(OUTDOORS_DEEPCANYON),
    DECL(OUTDOORS_CREEK),
    DECL(OUTDOORS_VALLEY),

    DECL(MOOD_HEAVEN),
    DECL(MOOD_HELL),
    DECL(MOOD_MEMORY),

    DECL(DRIVING_COMMENTATOR),
    DECL(DRIVING_PITGARAGE),
    DECL(DRIVING_INCAR_RACER),
    DECL(DRIVING_INCAR_SPORTS),
    DECL(DRIVING_INCAR_LUXURY),
    DECL(DRIVING_FULLGRANDSTAND),
    DECL(DRIVING_EMPTYGRANDSTAND),
    DECL(DRIVING_TUNNEL),

    DECL(CITY_STREETS),
    DECL(CITY_SUBWAY),
    DECL(CITY_MUSEUM),
    DECL(CITY_LIBRARY),
    DECL(CITY_UNDERPASS),
    DECL(CITY_ABANDONED),

    DECL(DUSTYROOM),
    DECL(CHAPEL),
    DECL(SMALLWATERROOM),
};
#undef DECL

void LoadReverbPreset(const std::string_view name, ALeffect *effect)
{
    using namespace std::string_view_literals;

    if(al::case_compare(name, "NONE"sv) == 0)
    {
        InitEffectParams(effect, AL_EFFECT_NULL);
        TRACE("Loading reverb '%s'\n", "NONE");
        return;
    }

    if(!DisabledEffects.test(EAXREVERB_EFFECT))
        InitEffectParams(effect, AL_EFFECT_EAXREVERB);
    else if(!DisabledEffects.test(REVERB_EFFECT))
        InitEffectParams(effect, AL_EFFECT_REVERB);
    else
        InitEffectParams(effect, AL_EFFECT_NULL);
    for(const auto &reverbitem : reverblist)
    {
        if(al::case_compare(name, std::data(reverbitem.name)) != 0)
            continue;

        TRACE("Loading reverb '%s'\n", std::data(reverbitem.name));
        const auto &props = reverbitem.props;
        auto &dst = std::get<ReverbProps>(effect->Props);
        dst.Density   = props.flDensity;
        dst.Diffusion = props.flDiffusion;
        dst.Gain   = props.flGain;
        dst.GainHF = props.flGainHF;
        dst.GainLF = props.flGainLF;
        dst.DecayTime    = props.flDecayTime;
        dst.DecayHFRatio = props.flDecayHFRatio;
        dst.DecayLFRatio = props.flDecayLFRatio;
        dst.ReflectionsGain   = props.flReflectionsGain;
        dst.ReflectionsDelay  = props.flReflectionsDelay;
        dst.ReflectionsPan[0] = props.flReflectionsPan[0];
        dst.ReflectionsPan[1] = props.flReflectionsPan[1];
        dst.ReflectionsPan[2] = props.flReflectionsPan[2];
        dst.LateReverbGain   = props.flLateReverbGain;
        dst.LateReverbDelay  = props.flLateReverbDelay;
        dst.LateReverbPan[0] = props.flLateReverbPan[0];
        dst.LateReverbPan[1] = props.flLateReverbPan[1];
        dst.LateReverbPan[2] = props.flLateReverbPan[2];
        dst.EchoTime  = props.flEchoTime;
        dst.EchoDepth = props.flEchoDepth;
        dst.ModulationTime  = props.flModulationTime;
        dst.ModulationDepth = props.flModulationDepth;
        dst.AirAbsorptionGainHF = props.flAirAbsorptionGainHF;
        dst.HFReference = props.flHFReference;
        dst.LFReference = props.flLFReference;
        dst.RoomRolloffFactor = props.flRoomRolloffFactor;
        dst.DecayHFLimit = props.iDecayHFLimit ? AL_TRUE : AL_FALSE;
        return;
    }

    WARN("Reverb preset '%.*s' not found\n", al::sizei(name), name.data());
}

bool IsValidEffectType(ALenum type) noexcept
{
    if(type == AL_EFFECT_NULL)
        return true;

    auto check_effect = [type](const EffectList &item) noexcept -> bool
    { return type == item.val && !DisabledEffects.test(item.type); };
    return std::any_of(gEffectList.cbegin(), gEffectList.cend(), check_effect);
}
