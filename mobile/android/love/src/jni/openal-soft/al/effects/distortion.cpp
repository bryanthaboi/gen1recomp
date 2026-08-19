
#include "config.h"

#include "AL/al.h"
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
    DistortionProps props{};
    props.Edge = AL_DISTORTION_DEFAULT_EDGE;
    props.Gain = AL_DISTORTION_DEFAULT_GAIN;
    props.LowpassCutoff = AL_DISTORTION_DEFAULT_LOWPASS_CUTOFF;
    props.EQCenter = AL_DISTORTION_DEFAULT_EQCENTER;
    props.EQBandwidth = AL_DISTORTION_DEFAULT_EQBANDWIDTH;
    return props;
}

} // namespace

const EffectProps DistortionEffectProps{genDefaultProps()};

void DistortionEffectHandler::SetParami(DistortionProps&, ALenum param, int)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid distortion integer property 0x%04x", param}; }
void DistortionEffectHandler::SetParamiv(DistortionProps&, ALenum param, const int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid distortion integer-vector property 0x%04x",
        param};
}
void DistortionEffectHandler::SetParamf(DistortionProps &props, ALenum param, float val)
{
    switch(param)
    {
    case AL_DISTORTION_EDGE:
        if(!(val >= AL_DISTORTION_MIN_EDGE && val <= AL_DISTORTION_MAX_EDGE))
            throw effect_exception{AL_INVALID_VALUE, "Distortion edge out of range"};
        props.Edge = val;
        break;

    case AL_DISTORTION_GAIN:
        if(!(val >= AL_DISTORTION_MIN_GAIN && val <= AL_DISTORTION_MAX_GAIN))
            throw effect_exception{AL_INVALID_VALUE, "Distortion gain out of range"};
        props.Gain = val;
        break;

    case AL_DISTORTION_LOWPASS_CUTOFF:
        if(!(val >= AL_DISTORTION_MIN_LOWPASS_CUTOFF && val <= AL_DISTORTION_MAX_LOWPASS_CUTOFF))
            throw effect_exception{AL_INVALID_VALUE, "Distortion low-pass cutoff out of range"};
        props.LowpassCutoff = val;
        break;

    case AL_DISTORTION_EQCENTER:
        if(!(val >= AL_DISTORTION_MIN_EQCENTER && val <= AL_DISTORTION_MAX_EQCENTER))
            throw effect_exception{AL_INVALID_VALUE, "Distortion EQ center out of range"};
        props.EQCenter = val;
        break;

    case AL_DISTORTION_EQBANDWIDTH:
        if(!(val >= AL_DISTORTION_MIN_EQBANDWIDTH && val <= AL_DISTORTION_MAX_EQBANDWIDTH))
            throw effect_exception{AL_INVALID_VALUE, "Distortion EQ bandwidth out of range"};
        props.EQBandwidth = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid distortion float property 0x%04x", param};
    }
}
void DistortionEffectHandler::SetParamfv(DistortionProps &props, ALenum param, const float *vals)
{ SetParamf(props, param, *vals); }

void DistortionEffectHandler::GetParami(const DistortionProps&, ALenum param, int*)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid distortion integer property 0x%04x", param}; }
void DistortionEffectHandler::GetParamiv(const DistortionProps&, ALenum param, int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid distortion integer-vector property 0x%04x",
        param};
}
void DistortionEffectHandler::GetParamf(const DistortionProps &props, ALenum param, float *val)
{
    switch(param)
    {
    case AL_DISTORTION_EDGE: *val = props.Edge; break;
    case AL_DISTORTION_GAIN: *val = props.Gain; break;
    case AL_DISTORTION_LOWPASS_CUTOFF: *val = props.LowpassCutoff; break;
    case AL_DISTORTION_EQCENTER: *val = props.EQCenter; break;
    case AL_DISTORTION_EQBANDWIDTH: *val = props.EQBandwidth; break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid distortion float property 0x%04x", param};
    }
}
void DistortionEffectHandler::GetParamfv(const DistortionProps &props, ALenum param, float *vals)
{ GetParamf(props, param, vals); }


#if ALSOFT_EAX
namespace {

using DistortionCommitter = EaxCommitter<EaxDistortionCommitter>;

struct EdgeValidator {
    void operator()(float flEdge) const
    {
        eax_validate_range<DistortionCommitter::Exception>(
            "Edge",
            flEdge,
            EAXDISTORTION_MINEDGE,
            EAXDISTORTION_MAXEDGE);
    }
}; // EdgeValidator

struct GainValidator {
    void operator()(long lGain) const
    {
        eax_validate_range<DistortionCommitter::Exception>(
            "Gain",
            lGain,
            EAXDISTORTION_MINGAIN,
            EAXDISTORTION_MAXGAIN);
    }
}; // GainValidator

struct LowPassCutOffValidator {
    void operator()(float flLowPassCutOff) const
    {
        eax_validate_range<DistortionCommitter::Exception>(
            "Low-pass Cut-off",
            flLowPassCutOff,
            EAXDISTORTION_MINLOWPASSCUTOFF,
            EAXDISTORTION_MAXLOWPASSCUTOFF);
    }
}; // LowPassCutOffValidator

struct EqCenterValidator {
    void operator()(float flEQCenter) const
    {
        eax_validate_range<DistortionCommitter::Exception>(
            "EQ Center",
            flEQCenter,
            EAXDISTORTION_MINEQCENTER,
            EAXDISTORTION_MAXEQCENTER);
    }
}; // EqCenterValidator

struct EqBandwidthValidator {
    void operator()(float flEQBandwidth) const
    {
        eax_validate_range<DistortionCommitter::Exception>(
            "EQ Bandwidth",
            flEQBandwidth,
            EAXDISTORTION_MINEQBANDWIDTH,
            EAXDISTORTION_MAXEQBANDWIDTH);
    }
}; // EqBandwidthValidator

struct AllValidator {
    void operator()(const EAXDISTORTIONPROPERTIES& all) const
    {
        EdgeValidator{}(all.flEdge);
        GainValidator{}(all.lGain);
        LowPassCutOffValidator{}(all.flLowPassCutOff);
        EqCenterValidator{}(all.flEQCenter);
        EqBandwidthValidator{}(all.flEQBandwidth);
    }
}; // AllValidator

} // namespace

template<>
struct DistortionCommitter::Exception : public EaxException {
    explicit Exception(const char *message) : EaxException{"EAX_DISTORTION_EFFECT", message}
    { }
};

template<>
[[noreturn]] void DistortionCommitter::fail(const char *message)
{
    throw Exception{message};
}

bool EaxDistortionCommitter::commit(const EAXDISTORTIONPROPERTIES &props)
{
    if(auto *cur = std::get_if<EAXDISTORTIONPROPERTIES>(&mEaxProps); cur && *cur == props)
        return false;

    mEaxProps = props;
    mAlProps = [&]{
        DistortionProps ret{};
        ret.Edge = props.flEdge;
        ret.Gain = level_mb_to_gain(static_cast<float>(props.lGain));
        ret.LowpassCutoff = props.flLowPassCutOff;
        ret.EQCenter = props.flEQCenter;
        ret.EQBandwidth = props.flEdge;
        return ret;
    }();

    return true;
}

void EaxDistortionCommitter::SetDefaults(EaxEffectProps &props)
{
    static constexpr EAXDISTORTIONPROPERTIES defprops{[]
    {
        EAXDISTORTIONPROPERTIES ret{};
        ret.flEdge = EAXDISTORTION_DEFAULTEDGE;
        ret.lGain = EAXDISTORTION_DEFAULTGAIN;
        ret.flLowPassCutOff = EAXDISTORTION_DEFAULTLOWPASSCUTOFF;
        ret.flEQCenter = EAXDISTORTION_DEFAULTEQCENTER;
        ret.flEQBandwidth = EAXDISTORTION_DEFAULTEQBANDWIDTH;
        return ret;
    }()};
    props = defprops;
}

void EaxDistortionCommitter::Get(const EaxCall &call, const EAXDISTORTIONPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXDISTORTION_NONE: break;
    case EAXDISTORTION_ALLPARAMETERS: call.set_value<Exception>(props); break;
    case EAXDISTORTION_EDGE: call.set_value<Exception>(props.flEdge); break;
    case EAXDISTORTION_GAIN: call.set_value<Exception>(props.lGain); break;
    case EAXDISTORTION_LOWPASSCUTOFF: call.set_value<Exception>(props.flLowPassCutOff); break;
    case EAXDISTORTION_EQCENTER: call.set_value<Exception>(props.flEQCenter); break;
    case EAXDISTORTION_EQBANDWIDTH: call.set_value<Exception>(props.flEQBandwidth); break;
    default: fail_unknown_property_id();
    }
}

void EaxDistortionCommitter::Set(const EaxCall &call, EAXDISTORTIONPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXDISTORTION_NONE: break;
    case EAXDISTORTION_ALLPARAMETERS: defer<AllValidator>(call, props); break;
    case EAXDISTORTION_EDGE: defer<EdgeValidator>(call, props.flEdge); break;
    case EAXDISTORTION_GAIN: defer<GainValidator>(call, props.lGain); break;
    case EAXDISTORTION_LOWPASSCUTOFF: defer<LowPassCutOffValidator>(call, props.flLowPassCutOff); break;
    case EAXDISTORTION_EQCENTER: defer<EqCenterValidator>(call, props.flEQCenter); break;
    case EAXDISTORTION_EQBANDWIDTH: defer<EqBandwidthValidator>(call, props.flEQBandwidth); break;
    default: fail_unknown_property_id();
    }
}

#endif // ALSOFT_EAX
