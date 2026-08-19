
#include "config.h"

#include <optional>
#include <stdexcept>

#include "AL/al.h"
#include "AL/efx.h"

#include "effects.h"

#if ALSOFT_EAX
#include <cassert>
#include "al/eax/effect.h"
#include "al/eax/exception.h"
#include "al/eax/utils.h"
#endif // ALSOFT_EAX


namespace {

static_assert(ChorusMaxDelay >= AL_CHORUS_MAX_DELAY, "Chorus max delay too small");
static_assert(FlangerMaxDelay >= AL_FLANGER_MAX_DELAY, "Flanger max delay too small");

static_assert(AL_CHORUS_WAVEFORM_SINUSOID == AL_FLANGER_WAVEFORM_SINUSOID, "Chorus/Flanger waveform value mismatch");
static_assert(AL_CHORUS_WAVEFORM_TRIANGLE == AL_FLANGER_WAVEFORM_TRIANGLE, "Chorus/Flanger waveform value mismatch");

constexpr std::optional<ChorusWaveform> WaveformFromEnum(ALenum type) noexcept
{
    switch(type)
    {
    case AL_CHORUS_WAVEFORM_SINUSOID: return ChorusWaveform::Sinusoid;
    case AL_CHORUS_WAVEFORM_TRIANGLE: return ChorusWaveform::Triangle;
    }
    return std::nullopt;
}
constexpr ALenum EnumFromWaveform(ChorusWaveform type)
{
    switch(type)
    {
    case ChorusWaveform::Sinusoid: return AL_CHORUS_WAVEFORM_SINUSOID;
    case ChorusWaveform::Triangle: return AL_CHORUS_WAVEFORM_TRIANGLE;
    }
    throw std::runtime_error{"Invalid chorus waveform: "+std::to_string(static_cast<int>(type))};
}

constexpr EffectProps genDefaultChorusProps() noexcept
{
    ChorusProps props{};
    props.Waveform = WaveformFromEnum(AL_CHORUS_DEFAULT_WAVEFORM).value();
    props.Phase = AL_CHORUS_DEFAULT_PHASE;
    props.Rate = AL_CHORUS_DEFAULT_RATE;
    props.Depth = AL_CHORUS_DEFAULT_DEPTH;
    props.Feedback = AL_CHORUS_DEFAULT_FEEDBACK;
    props.Delay = AL_CHORUS_DEFAULT_DELAY;
    return props;
}

constexpr EffectProps genDefaultFlangerProps() noexcept
{
    ChorusProps props{};
    props.Waveform = WaveformFromEnum(AL_FLANGER_DEFAULT_WAVEFORM).value();
    props.Phase = AL_FLANGER_DEFAULT_PHASE;
    props.Rate = AL_FLANGER_DEFAULT_RATE;
    props.Depth = AL_FLANGER_DEFAULT_DEPTH;
    props.Feedback = AL_FLANGER_DEFAULT_FEEDBACK;
    props.Delay = AL_FLANGER_DEFAULT_DELAY;
    return props;
}

} // namespace

const EffectProps ChorusEffectProps{genDefaultChorusProps()};

void ChorusEffectHandler::SetParami(ChorusProps &props, ALenum param, int val)
{
    switch(param)
    {
    case AL_CHORUS_WAVEFORM:
        if(auto formopt = WaveformFromEnum(val))
            props.Waveform = *formopt;
        else
            throw effect_exception{AL_INVALID_VALUE, "Invalid chorus waveform: 0x%04x", val};
        break;

    case AL_CHORUS_PHASE:
        if(!(val >= AL_CHORUS_MIN_PHASE && val <= AL_CHORUS_MAX_PHASE))
            throw effect_exception{AL_INVALID_VALUE, "Chorus phase out of range: %d", val};
        props.Phase = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid chorus integer property 0x%04x", param};
    }
}
void ChorusEffectHandler::SetParamiv(ChorusProps &props, ALenum param, const int *vals)
{ SetParami(props, param, *vals); }
void ChorusEffectHandler::SetParamf(ChorusProps &props, ALenum param, float val)
{
    switch(param)
    {
    case AL_CHORUS_RATE:
        if(!(val >= AL_CHORUS_MIN_RATE && val <= AL_CHORUS_MAX_RATE))
            throw effect_exception{AL_INVALID_VALUE, "Chorus rate out of range: %f", val};
        props.Rate = val;
        break;

    case AL_CHORUS_DEPTH:
        if(!(val >= AL_CHORUS_MIN_DEPTH && val <= AL_CHORUS_MAX_DEPTH))
            throw effect_exception{AL_INVALID_VALUE, "Chorus depth out of range: %f", val};
        props.Depth = val;
        break;

    case AL_CHORUS_FEEDBACK:
        if(!(val >= AL_CHORUS_MIN_FEEDBACK && val <= AL_CHORUS_MAX_FEEDBACK))
            throw effect_exception{AL_INVALID_VALUE, "Chorus feedback out of range: %f", val};
        props.Feedback = val;
        break;

    case AL_CHORUS_DELAY:
        if(!(val >= AL_CHORUS_MIN_DELAY && val <= AL_CHORUS_MAX_DELAY))
            throw effect_exception{AL_INVALID_VALUE, "Chorus delay out of range: %f", val};
        props.Delay = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid chorus float property 0x%04x", param};
    }
}
void ChorusEffectHandler::SetParamfv(ChorusProps &props, ALenum param, const float *vals)
{ SetParamf(props, param, *vals); }

void ChorusEffectHandler::GetParami(const ChorusProps &props, ALenum param, int *val)
{
    switch(param)
    {
    case AL_CHORUS_WAVEFORM: *val = EnumFromWaveform(props.Waveform); break;
    case AL_CHORUS_PHASE: *val = props.Phase; break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid chorus integer property 0x%04x", param};
    }
}
void ChorusEffectHandler::GetParamiv(const ChorusProps &props, ALenum param, int *vals)
{ GetParami(props, param, vals); }
void ChorusEffectHandler::GetParamf(const ChorusProps &props, ALenum param, float *val)
{
    switch(param)
    {
    case AL_CHORUS_RATE: *val = props.Rate; break;
    case AL_CHORUS_DEPTH: *val = props.Depth; break;
    case AL_CHORUS_FEEDBACK: *val = props.Feedback; break;
    case AL_CHORUS_DELAY: *val = props.Delay; break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid chorus float property 0x%04x", param};
    }
}
void ChorusEffectHandler::GetParamfv(const ChorusProps &props, ALenum param, float *vals)
{ GetParamf(props, param, vals); }


const EffectProps FlangerEffectProps{genDefaultFlangerProps()};

void FlangerEffectHandler::SetParami(ChorusProps &props, ALenum param, int val)
{
    switch(param)
    {
    case AL_FLANGER_WAVEFORM:
        if(auto formopt = WaveformFromEnum(val))
            props.Waveform = *formopt;
        else
            throw effect_exception{AL_INVALID_VALUE, "Invalid flanger waveform: 0x%04x", val};
        break;

    case AL_FLANGER_PHASE:
        if(!(val >= AL_FLANGER_MIN_PHASE && val <= AL_FLANGER_MAX_PHASE))
            throw effect_exception{AL_INVALID_VALUE, "Flanger phase out of range: %d", val};
        props.Phase = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid flanger integer property 0x%04x", param};
    }
}
void FlangerEffectHandler::SetParamiv(ChorusProps &props, ALenum param, const int *vals)
{ SetParami(props, param, *vals); }
void FlangerEffectHandler::SetParamf(ChorusProps &props, ALenum param, float val)
{
    switch(param)
    {
    case AL_FLANGER_RATE:
        if(!(val >= AL_FLANGER_MIN_RATE && val <= AL_FLANGER_MAX_RATE))
            throw effect_exception{AL_INVALID_VALUE, "Flanger rate out of range: %f", val};
        props.Rate = val;
        break;

    case AL_FLANGER_DEPTH:
        if(!(val >= AL_FLANGER_MIN_DEPTH && val <= AL_FLANGER_MAX_DEPTH))
            throw effect_exception{AL_INVALID_VALUE, "Flanger depth out of range: %f", val};
        props.Depth = val;
        break;

    case AL_FLANGER_FEEDBACK:
        if(!(val >= AL_FLANGER_MIN_FEEDBACK && val <= AL_FLANGER_MAX_FEEDBACK))
            throw effect_exception{AL_INVALID_VALUE, "Flanger feedback out of range: %f", val};
        props.Feedback = val;
        break;

    case AL_FLANGER_DELAY:
        if(!(val >= AL_FLANGER_MIN_DELAY && val <= AL_FLANGER_MAX_DELAY))
            throw effect_exception{AL_INVALID_VALUE, "Flanger delay out of range: %f", val};
        props.Delay = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid flanger float property 0x%04x", param};
    }
}
void FlangerEffectHandler::SetParamfv(ChorusProps &props, ALenum param, const float *vals)
{ SetParamf(props, param, *vals); }

void FlangerEffectHandler::GetParami(const ChorusProps &props, ALenum param, int *val)
{
    switch(param)
    {
    case AL_FLANGER_WAVEFORM: *val = EnumFromWaveform(props.Waveform); break;
    case AL_FLANGER_PHASE: *val = props.Phase; break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid flanger integer property 0x%04x", param};
    }
}
void FlangerEffectHandler::GetParamiv(const ChorusProps &props, ALenum param, int *vals)
{ GetParami(props, param, vals); }
void FlangerEffectHandler::GetParamf(const ChorusProps &props, ALenum param, float *val)
{
    switch(param)
    {
    case AL_FLANGER_RATE: *val = props.Rate; break;
    case AL_FLANGER_DEPTH: *val = props.Depth; break;
    case AL_FLANGER_FEEDBACK: *val = props.Feedback; break;
    case AL_FLANGER_DELAY: *val = props.Delay; break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid flanger float property 0x%04x", param};
    }
}
void FlangerEffectHandler::GetParamfv(const ChorusProps &props, ALenum param, float *vals)
{ GetParamf(props, param, vals); }


#if ALSOFT_EAX
namespace {

struct EaxChorusTraits {
    using EaxProps = EAXCHORUSPROPERTIES;
    using Committer = EaxChorusCommitter;

    static constexpr auto efx_effect() { return AL_EFFECT_CHORUS; }

    static constexpr auto eax_none_param_id() { return EAXCHORUS_NONE; }
    static constexpr auto eax_allparameters_param_id() { return EAXCHORUS_ALLPARAMETERS; }
    static constexpr auto eax_waveform_param_id() { return EAXCHORUS_WAVEFORM; }
    static constexpr auto eax_phase_param_id() { return EAXCHORUS_PHASE; }
    static constexpr auto eax_rate_param_id() { return EAXCHORUS_RATE; }
    static constexpr auto eax_depth_param_id() { return EAXCHORUS_DEPTH; }
    static constexpr auto eax_feedback_param_id() { return EAXCHORUS_FEEDBACK; }
    static constexpr auto eax_delay_param_id() { return EAXCHORUS_DELAY; }

    static constexpr auto eax_min_waveform() { return EAXCHORUS_MINWAVEFORM; }
    static constexpr auto eax_min_phase() { return EAXCHORUS_MINPHASE; }
    static constexpr auto eax_min_rate() { return EAXCHORUS_MINRATE; }
    static constexpr auto eax_min_depth() { return EAXCHORUS_MINDEPTH; }
    static constexpr auto eax_min_feedback() { return EAXCHORUS_MINFEEDBACK; }
    static constexpr auto eax_min_delay() { return EAXCHORUS_MINDELAY; }

    static constexpr auto eax_max_waveform() { return EAXCHORUS_MAXWAVEFORM; }
    static constexpr auto eax_max_phase() { return EAXCHORUS_MAXPHASE; }
    static constexpr auto eax_max_rate() { return EAXCHORUS_MAXRATE; }
    static constexpr auto eax_max_depth() { return EAXCHORUS_MAXDEPTH; }
    static constexpr auto eax_max_feedback() { return EAXCHORUS_MAXFEEDBACK; }
    static constexpr auto eax_max_delay() { return EAXCHORUS_MAXDELAY; }

    static constexpr auto eax_default_waveform() { return EAXCHORUS_DEFAULTWAVEFORM; }
    static constexpr auto eax_default_phase() { return EAXCHORUS_DEFAULTPHASE; }
    static constexpr auto eax_default_rate() { return EAXCHORUS_DEFAULTRATE; }
    static constexpr auto eax_default_depth() { return EAXCHORUS_DEFAULTDEPTH; }
    static constexpr auto eax_default_feedback() { return EAXCHORUS_DEFAULTFEEDBACK; }
    static constexpr auto eax_default_delay() { return EAXCHORUS_DEFAULTDELAY; }

    static constexpr auto efx_min_waveform() { return AL_CHORUS_MIN_WAVEFORM; }
    static constexpr auto efx_min_phase() { return AL_CHORUS_MIN_PHASE; }
    static constexpr auto efx_min_rate() { return AL_CHORUS_MIN_RATE; }
    static constexpr auto efx_min_depth() { return AL_CHORUS_MIN_DEPTH; }
    static constexpr auto efx_min_feedback() { return AL_CHORUS_MIN_FEEDBACK; }
    static constexpr auto efx_min_delay() { return AL_CHORUS_MIN_DELAY; }

    static constexpr auto efx_max_waveform() { return AL_CHORUS_MAX_WAVEFORM; }
    static constexpr auto efx_max_phase() { return AL_CHORUS_MAX_PHASE; }
    static constexpr auto efx_max_rate() { return AL_CHORUS_MAX_RATE; }
    static constexpr auto efx_max_depth() { return AL_CHORUS_MAX_DEPTH; }
    static constexpr auto efx_max_feedback() { return AL_CHORUS_MAX_FEEDBACK; }
    static constexpr auto efx_max_delay() { return AL_CHORUS_MAX_DELAY; }

    static constexpr auto efx_default_waveform() { return AL_CHORUS_DEFAULT_WAVEFORM; }
    static constexpr auto efx_default_phase() { return AL_CHORUS_DEFAULT_PHASE; }
    static constexpr auto efx_default_rate() { return AL_CHORUS_DEFAULT_RATE; }
    static constexpr auto efx_default_depth() { return AL_CHORUS_DEFAULT_DEPTH; }
    static constexpr auto efx_default_feedback() { return AL_CHORUS_DEFAULT_FEEDBACK; }
    static constexpr auto efx_default_delay() { return AL_CHORUS_DEFAULT_DELAY; }

    static ChorusWaveform eax_waveform(unsigned long type)
    {
        if(type == EAX_CHORUS_SINUSOID) return ChorusWaveform::Sinusoid;
        if(type == EAX_CHORUS_TRIANGLE) return ChorusWaveform::Triangle;
        return ChorusWaveform::Sinusoid;
    }
}; // EaxChorusTraits

struct EaxFlangerTraits {
    using EaxProps = EAXFLANGERPROPERTIES;
    using Committer = EaxFlangerCommitter;

    static constexpr auto efx_effect() { return AL_EFFECT_FLANGER; }

    static constexpr auto eax_none_param_id() { return EAXFLANGER_NONE; }
    static constexpr auto eax_allparameters_param_id() { return EAXFLANGER_ALLPARAMETERS; }
    static constexpr auto eax_waveform_param_id() { return EAXFLANGER_WAVEFORM; }
    static constexpr auto eax_phase_param_id() { return EAXFLANGER_PHASE; }
    static constexpr auto eax_rate_param_id() { return EAXFLANGER_RATE; }
    static constexpr auto eax_depth_param_id() { return EAXFLANGER_DEPTH; }
    static constexpr auto eax_feedback_param_id() { return EAXFLANGER_FEEDBACK; }
    static constexpr auto eax_delay_param_id() { return EAXFLANGER_DELAY; }

    static constexpr auto eax_min_waveform() { return EAXFLANGER_MINWAVEFORM; }
    static constexpr auto eax_min_phase() { return EAXFLANGER_MINPHASE; }
    static constexpr auto eax_min_rate() { return EAXFLANGER_MINRATE; }
    static constexpr auto eax_min_depth() { return EAXFLANGER_MINDEPTH; }
    static constexpr auto eax_min_feedback() { return EAXFLANGER_MINFEEDBACK; }
    static constexpr auto eax_min_delay() { return EAXFLANGER_MINDELAY; }

    static constexpr auto eax_max_waveform() { return EAXFLANGER_MAXWAVEFORM; }
    static constexpr auto eax_max_phase() { return EAXFLANGER_MAXPHASE; }
    static constexpr auto eax_max_rate() { return EAXFLANGER_MAXRATE; }
    static constexpr auto eax_max_depth() { return EAXFLANGER_MAXDEPTH; }
    static constexpr auto eax_max_feedback() { return EAXFLANGER_MAXFEEDBACK; }
    static constexpr auto eax_max_delay() { return EAXFLANGER_MAXDELAY; }

    static constexpr auto eax_default_waveform() { return EAXFLANGER_DEFAULTWAVEFORM; }
    static constexpr auto eax_default_phase() { return EAXFLANGER_DEFAULTPHASE; }
    static constexpr auto eax_default_rate() { return EAXFLANGER_DEFAULTRATE; }
    static constexpr auto eax_default_depth() { return EAXFLANGER_DEFAULTDEPTH; }
    static constexpr auto eax_default_feedback() { return EAXFLANGER_DEFAULTFEEDBACK; }
    static constexpr auto eax_default_delay() { return EAXFLANGER_DEFAULTDELAY; }

    static constexpr auto efx_min_waveform() { return AL_FLANGER_MIN_WAVEFORM; }
    static constexpr auto efx_min_phase() { return AL_FLANGER_MIN_PHASE; }
    static constexpr auto efx_min_rate() { return AL_FLANGER_MIN_RATE; }
    static constexpr auto efx_min_depth() { return AL_FLANGER_MIN_DEPTH; }
    static constexpr auto efx_min_feedback() { return AL_FLANGER_MIN_FEEDBACK; }
    static constexpr auto efx_min_delay() { return AL_FLANGER_MIN_DELAY; }

    static constexpr auto efx_max_waveform() { return AL_FLANGER_MAX_WAVEFORM; }
    static constexpr auto efx_max_phase() { return AL_FLANGER_MAX_PHASE; }
    static constexpr auto efx_max_rate() { return AL_FLANGER_MAX_RATE; }
    static constexpr auto efx_max_depth() { return AL_FLANGER_MAX_DEPTH; }
    static constexpr auto efx_max_feedback() { return AL_FLANGER_MAX_FEEDBACK; }
    static constexpr auto efx_max_delay() { return AL_FLANGER_MAX_DELAY; }

    static constexpr auto efx_default_waveform() { return AL_FLANGER_DEFAULT_WAVEFORM; }
    static constexpr auto efx_default_phase() { return AL_FLANGER_DEFAULT_PHASE; }
    static constexpr auto efx_default_rate() { return AL_FLANGER_DEFAULT_RATE; }
    static constexpr auto efx_default_depth() { return AL_FLANGER_DEFAULT_DEPTH; }
    static constexpr auto efx_default_feedback() { return AL_FLANGER_DEFAULT_FEEDBACK; }
    static constexpr auto efx_default_delay() { return AL_FLANGER_DEFAULT_DELAY; }

    static ChorusWaveform eax_waveform(unsigned long type)
    {
        if(type == EAX_FLANGER_SINUSOID) return ChorusWaveform::Sinusoid;
        if(type == EAX_FLANGER_TRIANGLE) return ChorusWaveform::Triangle;
        return ChorusWaveform::Sinusoid;
    }
}; // EaxFlangerTraits

template<typename TTraits>
struct ChorusFlangerEffect {
    using Traits = TTraits;
    using EaxProps = typename Traits::EaxProps;
    using Committer = typename Traits::Committer;
    using Exception = typename Committer::Exception;

    struct WaveformValidator {
        void operator()(unsigned long ulWaveform) const
        {
            eax_validate_range<Exception>(
                "Waveform",
                ulWaveform,
                Traits::eax_min_waveform(),
                Traits::eax_max_waveform());
        }
    }; // WaveformValidator

    struct PhaseValidator {
        void operator()(long lPhase) const
        {
            eax_validate_range<Exception>(
                "Phase",
                lPhase,
                Traits::eax_min_phase(),
                Traits::eax_max_phase());
        }
    }; // PhaseValidator

    struct RateValidator {
        void operator()(float flRate) const
        {
            eax_validate_range<Exception>(
                "Rate",
                flRate,
                Traits::eax_min_rate(),
                Traits::eax_max_rate());
        }
    }; // RateValidator

    struct DepthValidator {
        void operator()(float flDepth) const
        {
            eax_validate_range<Exception>(
                "Depth",
                flDepth,
                Traits::eax_min_depth(),
                Traits::eax_max_depth());
        }
    }; // DepthValidator

    struct FeedbackValidator {
        void operator()(float flFeedback) const
        {
            eax_validate_range<Exception>(
                "Feedback",
                flFeedback,
                Traits::eax_min_feedback(),
                Traits::eax_max_feedback());
        }
    }; // FeedbackValidator

    struct DelayValidator {
        void operator()(float flDelay) const
        {
            eax_validate_range<Exception>(
                "Delay",
                flDelay,
                Traits::eax_min_delay(),
                Traits::eax_max_delay());
        }
    }; // DelayValidator

    struct AllValidator {
        void operator()(const EaxProps& all) const
        {
            WaveformValidator{}(all.ulWaveform);
            PhaseValidator{}(all.lPhase);
            RateValidator{}(all.flRate);
            DepthValidator{}(all.flDepth);
            FeedbackValidator{}(all.flFeedback);
            DelayValidator{}(all.flDelay);
        }
    }; // AllValidator

public:
    static void SetDefaults(EaxEffectProps &props)
    {
        auto&& all = props.emplace<EaxProps>();
        all.ulWaveform = Traits::eax_default_waveform();
        all.lPhase = Traits::eax_default_phase();
        all.flRate = Traits::eax_default_rate();
        all.flDepth = Traits::eax_default_depth();
        all.flFeedback = Traits::eax_default_feedback();
        all.flDelay = Traits::eax_default_delay();
    }


    static void Get(const EaxCall &call, const EaxProps &all)
    {
        switch(call.get_property_id())
        {
        case Traits::eax_none_param_id():
            break;
        case Traits::eax_allparameters_param_id():
            call.template set_value<Exception>(all);
            break;
        case Traits::eax_waveform_param_id():
            call.template set_value<Exception>(all.ulWaveform);
            break;
        case Traits::eax_phase_param_id():
            call.template set_value<Exception>(all.lPhase);
            break;
        case Traits::eax_rate_param_id():
            call.template set_value<Exception>(all.flRate);
            break;
        case Traits::eax_depth_param_id():
            call.template set_value<Exception>(all.flDepth);
            break;
        case Traits::eax_feedback_param_id():
            call.template set_value<Exception>(all.flFeedback);
            break;
        case Traits::eax_delay_param_id():
            call.template set_value<Exception>(all.flDelay);
            break;
        default:
            Committer::fail_unknown_property_id();
        }
    }

    static void Set(const EaxCall &call, EaxProps &all)
    {
        switch(call.get_property_id())
        {
        case Traits::eax_none_param_id():
            break;
        case Traits::eax_allparameters_param_id():
            Committer::template defer<AllValidator>(call, all);
            break;
        case Traits::eax_waveform_param_id():
            Committer::template defer<WaveformValidator>(call, all.ulWaveform);
            break;
        case Traits::eax_phase_param_id():
            Committer::template defer<PhaseValidator>(call, all.lPhase);
            break;
        case Traits::eax_rate_param_id():
            Committer::template defer<RateValidator>(call, all.flRate);
            break;
        case Traits::eax_depth_param_id():
            Committer::template defer<DepthValidator>(call, all.flDepth);
            break;
        case Traits::eax_feedback_param_id():
            Committer::template defer<FeedbackValidator>(call, all.flFeedback);
            break;
        case Traits::eax_delay_param_id():
            Committer::template defer<DelayValidator>(call, all.flDelay);
            break;
        default:
            Committer::fail_unknown_property_id();
        }
    }

    static bool Commit(const EaxProps &props, EaxEffectProps &props_, ChorusProps &al_props_)
    {
        if(auto *cur = std::get_if<EaxProps>(&props_); cur && *cur == props)
            return false;

        props_ = props;

        al_props_.Waveform = Traits::eax_waveform(props.ulWaveform);
        al_props_.Phase = static_cast<int>(props.lPhase);
        al_props_.Rate = props.flRate;
        al_props_.Depth = props.flDepth;
        al_props_.Feedback = props.flFeedback;
        al_props_.Delay = props.flDelay;

        return true;
    }
}; // EaxChorusFlangerEffect


using ChorusCommitter = EaxCommitter<EaxChorusCommitter>;
using FlangerCommitter = EaxCommitter<EaxFlangerCommitter>;

} // namespace

template<>
struct ChorusCommitter::Exception : public EaxException
{
    explicit Exception(const char *message) : EaxException{"EAX_CHORUS_EFFECT", message}
    { }
};

template<>
[[noreturn]] void ChorusCommitter::fail(const char *message)
{
    throw Exception{message};
}

bool EaxChorusCommitter::commit(const EAXCHORUSPROPERTIES &props)
{
    using Committer = ChorusFlangerEffect<EaxChorusTraits>;
    return Committer::Commit(props, mEaxProps, mAlProps.emplace<ChorusProps>());
}

void EaxChorusCommitter::SetDefaults(EaxEffectProps &props)
{
    using Committer = ChorusFlangerEffect<EaxChorusTraits>;
    Committer::SetDefaults(props);
}

void EaxChorusCommitter::Get(const EaxCall &call, const EAXCHORUSPROPERTIES &props)
{
    using Committer = ChorusFlangerEffect<EaxChorusTraits>;
    Committer::Get(call, props);
}

void EaxChorusCommitter::Set(const EaxCall &call, EAXCHORUSPROPERTIES &props)
{
    using Committer = ChorusFlangerEffect<EaxChorusTraits>;
    Committer::Set(call, props);
}

template<>
struct FlangerCommitter::Exception : public EaxException
{
    explicit Exception(const char *message) : EaxException{"EAX_FLANGER_EFFECT", message}
    { }
};

template<>
[[noreturn]] void FlangerCommitter::fail(const char *message)
{
    throw Exception{message};
}

bool EaxFlangerCommitter::commit(const EAXFLANGERPROPERTIES &props)
{
    using Committer = ChorusFlangerEffect<EaxFlangerTraits>;
    return Committer::Commit(props, mEaxProps, mAlProps.emplace<ChorusProps>());
}

void EaxFlangerCommitter::SetDefaults(EaxEffectProps &props)
{
    using Committer = ChorusFlangerEffect<EaxFlangerTraits>;
    Committer::SetDefaults(props);
}

void EaxFlangerCommitter::Get(const EaxCall &call, const EAXFLANGERPROPERTIES &props)
{
    using Committer = ChorusFlangerEffect<EaxFlangerTraits>;
    Committer::Get(call, props);
}

void EaxFlangerCommitter::Set(const EaxCall &call, EAXFLANGERPROPERTIES &props)
{
    using Committer = ChorusFlangerEffect<EaxFlangerTraits>;
    Committer::Set(call, props);
}

#endif // ALSOFT_EAX
