
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

static_assert(EchoMaxDelay >= AL_ECHO_MAX_DELAY, "Echo max delay too short");
static_assert(EchoMaxLRDelay >= AL_ECHO_MAX_LRDELAY, "Echo max left-right delay too short");

constexpr EffectProps genDefaultProps() noexcept
{
    EchoProps props{};
    props.Delay    = AL_ECHO_DEFAULT_DELAY;
    props.LRDelay  = AL_ECHO_DEFAULT_LRDELAY;
    props.Damping  = AL_ECHO_DEFAULT_DAMPING;
    props.Feedback = AL_ECHO_DEFAULT_FEEDBACK;
    props.Spread   = AL_ECHO_DEFAULT_SPREAD;
    return props;
}

} // namespace

const EffectProps EchoEffectProps{genDefaultProps()};

void EchoEffectHandler::SetParami(EchoProps&, ALenum param, int)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid echo integer property 0x%04x", param}; }
void EchoEffectHandler::SetParamiv(EchoProps&, ALenum param, const int*)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid echo integer-vector property 0x%04x", param}; }
void EchoEffectHandler::SetParamf(EchoProps &props, ALenum param, float val)
{
    switch(param)
    {
    case AL_ECHO_DELAY:
        if(!(val >= AL_ECHO_MIN_DELAY && val <= AL_ECHO_MAX_DELAY))
            throw effect_exception{AL_INVALID_VALUE, "Echo delay out of range"};
        props.Delay = val;
        break;

    case AL_ECHO_LRDELAY:
        if(!(val >= AL_ECHO_MIN_LRDELAY && val <= AL_ECHO_MAX_LRDELAY))
            throw effect_exception{AL_INVALID_VALUE, "Echo LR delay out of range"};
        props.LRDelay = val;
        break;

    case AL_ECHO_DAMPING:
        if(!(val >= AL_ECHO_MIN_DAMPING && val <= AL_ECHO_MAX_DAMPING))
            throw effect_exception{AL_INVALID_VALUE, "Echo damping out of range"};
        props.Damping = val;
        break;

    case AL_ECHO_FEEDBACK:
        if(!(val >= AL_ECHO_MIN_FEEDBACK && val <= AL_ECHO_MAX_FEEDBACK))
            throw effect_exception{AL_INVALID_VALUE, "Echo feedback out of range"};
        props.Feedback = val;
        break;

    case AL_ECHO_SPREAD:
        if(!(val >= AL_ECHO_MIN_SPREAD && val <= AL_ECHO_MAX_SPREAD))
            throw effect_exception{AL_INVALID_VALUE, "Echo spread out of range"};
        props.Spread = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid echo float property 0x%04x", param};
    }
}
void EchoEffectHandler::SetParamfv(EchoProps &props, ALenum param, const float *vals)
{ SetParamf(props, param, *vals); }

void EchoEffectHandler::GetParami(const EchoProps&, ALenum param, int*)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid echo integer property 0x%04x", param}; }
void EchoEffectHandler::GetParamiv(const EchoProps&, ALenum param, int*)
{ throw effect_exception{AL_INVALID_ENUM, "Invalid echo integer-vector property 0x%04x", param}; }
void EchoEffectHandler::GetParamf(const EchoProps &props, ALenum param, float *val)
{
    switch(param)
    {
    case AL_ECHO_DELAY: *val = props.Delay; break;
    case AL_ECHO_LRDELAY: *val = props.LRDelay; break;
    case AL_ECHO_DAMPING: *val = props.Damping; break;
    case AL_ECHO_FEEDBACK: *val = props.Feedback; break;
    case AL_ECHO_SPREAD: *val = props.Spread; break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid echo float property 0x%04x", param};
    }
}
void EchoEffectHandler::GetParamfv(const EchoProps &props, ALenum param, float *vals)
{ GetParamf(props, param, vals); }


#if ALSOFT_EAX
namespace {

using EchoCommitter = EaxCommitter<EaxEchoCommitter>;

struct DelayValidator {
    void operator()(float flDelay) const
    {
        eax_validate_range<EchoCommitter::Exception>(
            "Delay",
            flDelay,
            EAXECHO_MINDELAY,
            EAXECHO_MAXDELAY);
    }
}; // DelayValidator

struct LrDelayValidator {
    void operator()(float flLRDelay) const
    {
        eax_validate_range<EchoCommitter::Exception>(
            "LR Delay",
            flLRDelay,
            EAXECHO_MINLRDELAY,
            EAXECHO_MAXLRDELAY);
    }
}; // LrDelayValidator

struct DampingValidator {
    void operator()(float flDamping) const
    {
        eax_validate_range<EchoCommitter::Exception>(
            "Damping",
            flDamping,
            EAXECHO_MINDAMPING,
            EAXECHO_MAXDAMPING);
    }
}; // DampingValidator

struct FeedbackValidator {
    void operator()(float flFeedback) const
    {
        eax_validate_range<EchoCommitter::Exception>(
            "Feedback",
            flFeedback,
            EAXECHO_MINFEEDBACK,
            EAXECHO_MAXFEEDBACK);
    }
}; // FeedbackValidator

struct SpreadValidator {
    void operator()(float flSpread) const
    {
        eax_validate_range<EchoCommitter::Exception>(
            "Spread",
            flSpread,
            EAXECHO_MINSPREAD,
            EAXECHO_MAXSPREAD);
    }
}; // SpreadValidator

struct AllValidator {
    void operator()(const EAXECHOPROPERTIES& all) const
    {
        DelayValidator{}(all.flDelay);
        LrDelayValidator{}(all.flLRDelay);
        DampingValidator{}(all.flDamping);
        FeedbackValidator{}(all.flFeedback);
        SpreadValidator{}(all.flSpread);
    }
}; // AllValidator

} // namespace

template<>
struct EchoCommitter::Exception : public EaxException {
    explicit Exception(const char* message) : EaxException{"EAX_ECHO_EFFECT", message}
    { }
};

template<>
[[noreturn]] void EchoCommitter::fail(const char *message)
{
    throw Exception{message};
}

bool EaxEchoCommitter::commit(const EAXECHOPROPERTIES &props)
{
    if(auto *cur = std::get_if<EAXECHOPROPERTIES>(&mEaxProps); cur && *cur == props)
        return false;

    mEaxProps = props;
    mAlProps = [&]{
        EchoProps ret{};
        ret.Delay = props.flDelay;
        ret.LRDelay = props.flLRDelay;
        ret.Damping = props.flDamping;
        ret.Feedback = props.flFeedback;
        ret.Spread = props.flSpread;
        return ret;
    }();

    return true;
}

void EaxEchoCommitter::SetDefaults(EaxEffectProps &props)
{
    static constexpr EAXECHOPROPERTIES defprops{[]
    {
        EAXECHOPROPERTIES ret{};
        ret.flDelay = EAXECHO_DEFAULTDELAY;
        ret.flLRDelay = EAXECHO_DEFAULTLRDELAY;
        ret.flDamping = EAXECHO_DEFAULTDAMPING;
        ret.flFeedback = EAXECHO_DEFAULTFEEDBACK;
        ret.flSpread = EAXECHO_DEFAULTSPREAD;
        return ret;
    }()};
    props = defprops;
}

void EaxEchoCommitter::Get(const EaxCall &call, const EAXECHOPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXECHO_NONE: break;
    case EAXECHO_ALLPARAMETERS: call.set_value<Exception>(props); break;
    case EAXECHO_DELAY: call.set_value<Exception>(props.flDelay); break;
    case EAXECHO_LRDELAY: call.set_value<Exception>(props.flLRDelay); break;
    case EAXECHO_DAMPING: call.set_value<Exception>(props.flDamping); break;
    case EAXECHO_FEEDBACK: call.set_value<Exception>(props.flFeedback); break;
    case EAXECHO_SPREAD: call.set_value<Exception>(props.flSpread); break;
    default: fail_unknown_property_id();
    }
}

void EaxEchoCommitter::Set(const EaxCall &call, EAXECHOPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXECHO_NONE: break;
    case EAXECHO_ALLPARAMETERS: defer<AllValidator>(call, props); break;
    case EAXECHO_DELAY: defer<DelayValidator>(call, props.flDelay); break;
    case EAXECHO_LRDELAY: defer<LrDelayValidator>(call, props.flLRDelay); break;
    case EAXECHO_DAMPING: defer<DampingValidator>(call, props.flDamping); break;
    case EAXECHO_FEEDBACK: defer<FeedbackValidator>(call, props.flFeedback); break;
    case EAXECHO_SPREAD: defer<SpreadValidator>(call, props.flSpread); break;
    default: fail_unknown_property_id();
    }
}

#endif // ALSOFT_EAX
