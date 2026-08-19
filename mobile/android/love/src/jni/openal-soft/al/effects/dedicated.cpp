
#include "config.h"

#include <cmath>

#include "AL/al.h"
#include "AL/alext.h"

#include "alc/effects/base.h"
#include "effects.h"


namespace {

constexpr EffectProps genDefaultDialogProps() noexcept
{
    DedicatedProps props{};
    props.Target = DedicatedProps::Dialog;
    props.Gain = 1.0f;
    return props;
}

constexpr EffectProps genDefaultLfeProps() noexcept
{
    DedicatedProps props{};
    props.Target = DedicatedProps::Lfe;
    props.Gain = 1.0f;
    return props;
}

} // namespace

const EffectProps DedicatedDialogEffectProps{genDefaultDialogProps()};

void DedicatedDialogEffectHandler::SetParami(DedicatedProps&, ALenum param, int)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated integer property 0x%04x", param}; }
void DedicatedDialogEffectHandler::SetParamiv(DedicatedProps&, ALenum param, const int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated integer-vector property 0x%04x",
        param};
}
void DedicatedDialogEffectHandler::SetParamf(DedicatedProps &props, ALenum param, float val)
{
    switch(param)
    {
    case AL_DEDICATED_GAIN:
        if(!(val >= 0.0f && std::isfinite(val)))
            throw effect_exception{AL_INVALID_VALUE, "Dedicated gain out of range"};
        props.Gain = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated float property 0x%04x", param};
    }
}
void DedicatedDialogEffectHandler::SetParamfv(DedicatedProps &props, ALenum param, const float *vals)
{ SetParamf(props, param, *vals); }

void DedicatedDialogEffectHandler::GetParami(const DedicatedProps&, ALenum param, int*)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated integer property 0x%04x", param}; }
void DedicatedDialogEffectHandler::GetParamiv(const DedicatedProps&, ALenum param, int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated integer-vector property 0x%04x",
        param};
}
void DedicatedDialogEffectHandler::GetParamf(const DedicatedProps &props, ALenum param, float *val)
{
    switch(param)
    {
    case AL_DEDICATED_GAIN: *val = props.Gain; break;
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated float property 0x%04x", param};
    }
}
void DedicatedDialogEffectHandler::GetParamfv(const DedicatedProps &props, ALenum param, float *vals)
{ GetParamf(props, param, vals); }


const EffectProps DedicatedLfeEffectProps{genDefaultLfeProps()};

void DedicatedLfeEffectHandler::SetParami(DedicatedProps&, ALenum param, int)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated integer property 0x%04x", param}; }
void DedicatedLfeEffectHandler::SetParamiv(DedicatedProps&, ALenum param, const int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated integer-vector property 0x%04x",
        param};
}
void DedicatedLfeEffectHandler::SetParamf(DedicatedProps &props, ALenum param, float val)
{
    switch(param)
    {
    case AL_DEDICATED_GAIN:
        if(!(val >= 0.0f && std::isfinite(val)))
            throw effect_exception{AL_INVALID_VALUE, "Dedicated gain out of range"};
        props.Gain = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated float property 0x%04x", param};
    }
}
void DedicatedLfeEffectHandler::SetParamfv(DedicatedProps &props, ALenum param, const float *vals)
{ SetParamf(props, param, *vals); }

void DedicatedLfeEffectHandler::GetParami(const DedicatedProps&, ALenum param, int*)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated integer property 0x%04x", param}; }
void DedicatedLfeEffectHandler::GetParamiv(const DedicatedProps&, ALenum param, int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated integer-vector property 0x%04x",
        param};
}
void DedicatedLfeEffectHandler::GetParamf(const DedicatedProps &props, ALenum param, float *val)
{
    switch(param)
    {
    case AL_DEDICATED_GAIN: *val = props.Gain; break;
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid dedicated float property 0x%04x", param};
    }
}
void DedicatedLfeEffectHandler::GetParamfv(const DedicatedProps &props, ALenum param, float *vals)
{ GetParamf(props, param, vals); }
