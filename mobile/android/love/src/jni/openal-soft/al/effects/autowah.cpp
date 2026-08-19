
#include "config.h"

#include <cmath>
#include <cstdlib>

#include <algorithm>

#include "AL/efx.h"

#include "alc/effects/base.h"
#include "effects.h"

#if ALSOFT_EAX
#include "alnumeric.h"
#include "al/eax/effect.h"
#include "al/eax/exception.h"
#include "al/eax/utils.h"
#endif // ALSOFT_EAX


namespace {

constexpr EffectProps genDefaultProps() noexcept
{
    AutowahProps props{};
    props.AttackTime = AL_AUTOWAH_DEFAULT_ATTACK_TIME;
    props.ReleaseTime = AL_AUTOWAH_DEFAULT_RELEASE_TIME;
    props.Resonance = AL_AUTOWAH_DEFAULT_RESONANCE;
    props.PeakGain = AL_AUTOWAH_DEFAULT_PEAK_GAIN;
    return props;
}

} // namespace

const EffectProps AutowahEffectProps{genDefaultProps()};

void AutowahEffectHandler::SetParami(AutowahProps&, ALenum param, int)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid autowah integer property 0x%04x", param}; }
void AutowahEffectHandler::SetParamiv(AutowahProps&, ALenum param, const int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid autowah integer vector property 0x%04x",
        param};
}

void AutowahEffectHandler::SetParamf(AutowahProps &props, ALenum param, float val)
{
    switch(param)
    {
    case AL_AUTOWAH_ATTACK_TIME:
        if(!(val >= AL_AUTOWAH_MIN_ATTACK_TIME && val <= AL_AUTOWAH_MAX_ATTACK_TIME))
            throw effect_exception{AL_INVALID_VALUE, "Autowah attack time out of range"};
        props.AttackTime = val;
        break;

    case AL_AUTOWAH_RELEASE_TIME:
        if(!(val >= AL_AUTOWAH_MIN_RELEASE_TIME && val <= AL_AUTOWAH_MAX_RELEASE_TIME))
            throw effect_exception{AL_INVALID_VALUE, "Autowah release time out of range"};
        props.ReleaseTime = val;
        break;

    case AL_AUTOWAH_RESONANCE:
        if(!(val >= AL_AUTOWAH_MIN_RESONANCE && val <= AL_AUTOWAH_MAX_RESONANCE))
            throw effect_exception{AL_INVALID_VALUE, "Autowah resonance out of range"};
        props.Resonance = val;
        break;

    case AL_AUTOWAH_PEAK_GAIN:
        if(!(val >= AL_AUTOWAH_MIN_PEAK_GAIN && val <= AL_AUTOWAH_MAX_PEAK_GAIN))
            throw effect_exception{AL_INVALID_VALUE, "Autowah peak gain out of range"};
        props.PeakGain = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid autowah float property 0x%04x", param};
    }
}
void AutowahEffectHandler::SetParamfv(AutowahProps &props,  ALenum param, const float *vals)
{ SetParamf(props, param, *vals); }

void AutowahEffectHandler::GetParami(const AutowahProps&, ALenum param, int*)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid autowah integer property 0x%04x", param}; }
void AutowahEffectHandler::GetParamiv(const AutowahProps&, ALenum param, int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid autowah integer vector property 0x%04x",
        param};
}

void AutowahEffectHandler::GetParamf(const AutowahProps &props, ALenum param, float *val)
{
    switch(param)
    {
    case AL_AUTOWAH_ATTACK_TIME: *val = props.AttackTime; break;
    case AL_AUTOWAH_RELEASE_TIME: *val = props.ReleaseTime; break;
    case AL_AUTOWAH_RESONANCE: *val = props.Resonance; break;
    case AL_AUTOWAH_PEAK_GAIN: *val = props.PeakGain; break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid autowah float property 0x%04x", param};
    }

}
void AutowahEffectHandler::GetParamfv(const AutowahProps &props, ALenum param, float *vals)
{ GetParamf(props, param, vals); }

#if ALSOFT_EAX
namespace {

using AutowahCommitter = EaxCommitter<EaxAutowahCommitter>;

struct AttackTimeValidator {
    void operator()(float flAttackTime) const
    {
        eax_validate_range<AutowahCommitter::Exception>(
            "Attack Time",
            flAttackTime,
            EAXAUTOWAH_MINATTACKTIME,
            EAXAUTOWAH_MAXATTACKTIME);
    }
}; // AttackTimeValidator

struct ReleaseTimeValidator {
    void operator()(float flReleaseTime) const
    {
        eax_validate_range<AutowahCommitter::Exception>(
            "Release Time",
            flReleaseTime,
            EAXAUTOWAH_MINRELEASETIME,
            EAXAUTOWAH_MAXRELEASETIME);
    }
}; // ReleaseTimeValidator

struct ResonanceValidator {
    void operator()(long lResonance) const
    {
        eax_validate_range<AutowahCommitter::Exception>(
            "Resonance",
            lResonance,
            EAXAUTOWAH_MINRESONANCE,
            EAXAUTOWAH_MAXRESONANCE);
    }
}; // ResonanceValidator

struct PeakLevelValidator {
    void operator()(long lPeakLevel) const
    {
        eax_validate_range<AutowahCommitter::Exception>(
            "Peak Level",
            lPeakLevel,
            EAXAUTOWAH_MINPEAKLEVEL,
            EAXAUTOWAH_MAXPEAKLEVEL);
    }
}; // PeakLevelValidator

struct AllValidator {
    void operator()(const EAXAUTOWAHPROPERTIES& all) const
    {
        AttackTimeValidator{}(all.flAttackTime);
        ReleaseTimeValidator{}(all.flReleaseTime);
        ResonanceValidator{}(all.lResonance);
        PeakLevelValidator{}(all.lPeakLevel);
    }
}; // AllValidator

} // namespace

template<>
struct AutowahCommitter::Exception : public EaxException
{
    explicit Exception(const char *message) : EaxException{"EAX_AUTOWAH_EFFECT", message}
    { }
};

template<>
[[noreturn]] void AutowahCommitter::fail(const char *message)
{
    throw Exception{message};
}

bool EaxAutowahCommitter::commit(const EAXAUTOWAHPROPERTIES &props)
{
    if(auto *cur = std::get_if<EAXAUTOWAHPROPERTIES>(&mEaxProps); cur && *cur == props)
        return false;

    mEaxProps = props;
    mAlProps = [&]{
        AutowahProps ret{};
        ret.AttackTime = props.flAttackTime;
        ret.ReleaseTime = props.flReleaseTime;
        ret.Resonance = level_mb_to_gain(static_cast<float>(props.lResonance));
        ret.PeakGain = level_mb_to_gain(static_cast<float>(props.lPeakLevel));
        return ret;
    }();

    return true;
}

void EaxAutowahCommitter::SetDefaults(EaxEffectProps &props)
{
    static constexpr EAXAUTOWAHPROPERTIES defprops{[]
    {
        EAXAUTOWAHPROPERTIES ret{};
        ret.flAttackTime = EAXAUTOWAH_DEFAULTATTACKTIME;
        ret.flReleaseTime = EAXAUTOWAH_DEFAULTRELEASETIME;
        ret.lResonance = EAXAUTOWAH_DEFAULTRESONANCE;
        ret.lPeakLevel = EAXAUTOWAH_DEFAULTPEAKLEVEL;
        return ret;
    }()};
    props = defprops;
}

void EaxAutowahCommitter::Get(const EaxCall &call, const EAXAUTOWAHPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXAUTOWAH_NONE: break;
    case EAXAUTOWAH_ALLPARAMETERS: call.set_value<Exception>(props); break;
    case EAXAUTOWAH_ATTACKTIME: call.set_value<Exception>(props.flAttackTime); break;
    case EAXAUTOWAH_RELEASETIME: call.set_value<Exception>(props.flReleaseTime); break;
    case EAXAUTOWAH_RESONANCE: call.set_value<Exception>(props.lResonance); break;
    case EAXAUTOWAH_PEAKLEVEL: call.set_value<Exception>(props.lPeakLevel); break;
    default: fail_unknown_property_id();
    }
}

void EaxAutowahCommitter::Set(const EaxCall &call, EAXAUTOWAHPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXAUTOWAH_NONE: break;
    case EAXAUTOWAH_ALLPARAMETERS: defer<AllValidator>(call, props); break;
    case EAXAUTOWAH_ATTACKTIME: defer<AttackTimeValidator>(call, props.flAttackTime); break;
    case EAXAUTOWAH_RELEASETIME: defer<ReleaseTimeValidator>(call, props.flReleaseTime); break;
    case EAXAUTOWAH_RESONANCE: defer<ResonanceValidator>(call, props.lResonance); break;
    case EAXAUTOWAH_PEAKLEVEL: defer<PeakLevelValidator>(call, props.lPeakLevel); break;
    default: fail_unknown_property_id();
    }
}

#endif // ALSOFT_EAX
