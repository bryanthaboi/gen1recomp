
#include "config.h"

#include "AL/al.h"
#include "AL/efx.h"

#include "alc/effects/base.h"
#include "effects.h"

#if ALSOFT_EAX
#include "al/eax/effect.h"
#include "al/eax/exception.h"
#include "al/eax/utils.h"
#endif // ALSOFT_EAX


namespace {

constexpr EffectProps genDefaultProps() noexcept
{
    PshifterProps props{};
    props.CoarseTune = AL_PITCH_SHIFTER_DEFAULT_COARSE_TUNE;
    props.FineTune = AL_PITCH_SHIFTER_DEFAULT_FINE_TUNE;
    return props;
}

} // namespace

const EffectProps PshifterEffectProps{genDefaultProps()};

void PshifterEffectHandler::SetParami(PshifterProps &props, ALenum param, int val)
{
    switch(param)
    {
    case AL_PITCH_SHIFTER_COARSE_TUNE:
        if(!(val >= AL_PITCH_SHIFTER_MIN_COARSE_TUNE && val <= AL_PITCH_SHIFTER_MAX_COARSE_TUNE))
            throw effect_exception{AL_INVALID_VALUE, "Pitch shifter coarse tune out of range"};
        props.CoarseTune = val;
        break;

    case AL_PITCH_SHIFTER_FINE_TUNE:
        if(!(val >= AL_PITCH_SHIFTER_MIN_FINE_TUNE && val <= AL_PITCH_SHIFTER_MAX_FINE_TUNE))
            throw effect_exception{AL_INVALID_VALUE, "Pitch shifter fine tune out of range"};
        props.FineTune = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid pitch shifter integer property 0x%04x",
            param};
    }
}
void PshifterEffectHandler::SetParamiv(PshifterProps &props, ALenum param, const int *vals)
{ SetParami(props, param, *vals); }

void PshifterEffectHandler::SetParamf(PshifterProps&, ALenum param, float)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid pitch shifter float property 0x%04x", param}; }
void PshifterEffectHandler::SetParamfv(PshifterProps&, ALenum param, const float*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid pitch shifter float-vector property 0x%04x",
        param};
}

void PshifterEffectHandler::GetParami(const PshifterProps &props, ALenum param, int *val)
{
    switch(param)
    {
    case AL_PITCH_SHIFTER_COARSE_TUNE: *val = props.CoarseTune; break;
    case AL_PITCH_SHIFTER_FINE_TUNE: *val = props.FineTune; break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid pitch shifter integer property 0x%04x",
            param};
    }
}
void PshifterEffectHandler::GetParamiv(const PshifterProps &props, ALenum param, int *vals)
{ GetParami(props, param, vals); }

void PshifterEffectHandler::GetParamf(const PshifterProps&, ALenum param, float*)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid pitch shifter float property 0x%04x", param}; }
void PshifterEffectHandler::GetParamfv(const PshifterProps&, ALenum param, float*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid pitch shifter float vector-property 0x%04x",
        param};
}


#if ALSOFT_EAX
namespace {

using PitchShifterCommitter = EaxCommitter<EaxPitchShifterCommitter>;

struct CoarseTuneValidator {
    void operator()(long lCoarseTune) const
    {
        eax_validate_range<PitchShifterCommitter::Exception>(
            "Coarse Tune",
            lCoarseTune,
            EAXPITCHSHIFTER_MINCOARSETUNE,
            EAXPITCHSHIFTER_MAXCOARSETUNE);
    }
}; // CoarseTuneValidator

struct FineTuneValidator {
    void operator()(long lFineTune) const
    {
        eax_validate_range<PitchShifterCommitter::Exception>(
            "Fine Tune",
            lFineTune,
            EAXPITCHSHIFTER_MINFINETUNE,
            EAXPITCHSHIFTER_MAXFINETUNE);
    }
}; // FineTuneValidator

struct AllValidator {
    void operator()(const EAXPITCHSHIFTERPROPERTIES& all) const
    {
        CoarseTuneValidator{}(all.lCoarseTune);
        FineTuneValidator{}(all.lFineTune);
    }
}; // AllValidator

} // namespace

template<>
struct PitchShifterCommitter::Exception : public EaxException {
    explicit Exception(const char *message) : EaxException{"EAX_PITCH_SHIFTER_EFFECT", message}
    { }
};

template<>
[[noreturn]] void PitchShifterCommitter::fail(const char *message)
{
    throw Exception{message};
}

bool EaxPitchShifterCommitter::commit(const EAXPITCHSHIFTERPROPERTIES &props)
{
    if(auto *cur = std::get_if<EAXPITCHSHIFTERPROPERTIES>(&mEaxProps); cur && *cur == props)
        return false;

    mEaxProps = props;
    mAlProps = [&]{
        PshifterProps ret{};
        ret.CoarseTune = static_cast<int>(props.lCoarseTune);
        ret.FineTune = static_cast<int>(props.lFineTune);
        return ret;
    }();

    return true;
}

void EaxPitchShifterCommitter::SetDefaults(EaxEffectProps &props)
{
    props = EAXPITCHSHIFTERPROPERTIES{EAXPITCHSHIFTER_DEFAULTCOARSETUNE,
        EAXPITCHSHIFTER_DEFAULTFINETUNE};
}

void EaxPitchShifterCommitter::Get(const EaxCall &call, const EAXPITCHSHIFTERPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXPITCHSHIFTER_NONE: break;
    case EAXPITCHSHIFTER_ALLPARAMETERS: call.set_value<Exception>(props); break;
    case EAXPITCHSHIFTER_COARSETUNE: call.set_value<Exception>(props.lCoarseTune); break;
    case EAXPITCHSHIFTER_FINETUNE: call.set_value<Exception>(props.lFineTune); break;
    default: fail_unknown_property_id();
    }
}

void EaxPitchShifterCommitter::Set(const EaxCall &call, EAXPITCHSHIFTERPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXPITCHSHIFTER_NONE: break;
    case EAXPITCHSHIFTER_ALLPARAMETERS: defer<AllValidator>(call, props); break;
    case EAXPITCHSHIFTER_COARSETUNE: defer<CoarseTuneValidator>(call, props.lCoarseTune); break;
    case EAXPITCHSHIFTER_FINETUNE: defer<FineTuneValidator>(call, props.lFineTune); break;
    default: fail_unknown_property_id();
    }
}

#endif // ALSOFT_EAX
