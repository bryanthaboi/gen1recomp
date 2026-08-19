
#include "config.h"

#include <optional>
#include <stdexcept>

#include "AL/al.h"
#include "AL/efx.h"

#include "alc/effects/base.h"
#include "effects.h"

#if ALSOFT_EAX
#include <cassert>

#include "al/eax/effect.h"
#include "al/eax/exception.h"
#include "al/eax/utils.h"
#endif // ALSOFT_EAX


namespace {

constexpr std::optional<ModulatorWaveform> WaveformFromEmum(ALenum value) noexcept
{
    switch(value)
    {
    case AL_RING_MODULATOR_SINUSOID: return ModulatorWaveform::Sinusoid;
    case AL_RING_MODULATOR_SAWTOOTH: return ModulatorWaveform::Sawtooth;
    case AL_RING_MODULATOR_SQUARE: return ModulatorWaveform::Square;
    }
    return std::nullopt;
}
constexpr ALenum EnumFromWaveform(ModulatorWaveform type)
{
    switch(type)
    {
    case ModulatorWaveform::Sinusoid: return AL_RING_MODULATOR_SINUSOID;
    case ModulatorWaveform::Sawtooth: return AL_RING_MODULATOR_SAWTOOTH;
    case ModulatorWaveform::Square: return AL_RING_MODULATOR_SQUARE;
    }
    throw std::runtime_error{"Invalid modulator waveform: " +
        std::to_string(static_cast<int>(type))};
}

constexpr EffectProps genDefaultProps() noexcept
{
    ModulatorProps props{};
    props.Frequency      = AL_RING_MODULATOR_DEFAULT_FREQUENCY;
    props.HighPassCutoff = AL_RING_MODULATOR_DEFAULT_HIGHPASS_CUTOFF;
    props.Waveform       = WaveformFromEmum(AL_RING_MODULATOR_DEFAULT_WAVEFORM).value();
    return props;
}

} // namespace

const EffectProps ModulatorEffectProps{genDefaultProps()};

void ModulatorEffectHandler::SetParami(ModulatorProps &props, ALenum param, int val)
{
    switch(param)
    {
    case AL_RING_MODULATOR_FREQUENCY:
    case AL_RING_MODULATOR_HIGHPASS_CUTOFF:
        SetParamf(props, param, static_cast<float>(val));
        break;

    case AL_RING_MODULATOR_WAVEFORM:
        if(auto formopt = WaveformFromEmum(val))
            props.Waveform = *formopt;
        else
            throw effect_exception{AL_INVALID_VALUE, "Invalid modulator waveform: 0x%04x", val};
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid modulator integer property 0x%04x",
            param};
    }
}
void ModulatorEffectHandler::SetParamiv(ModulatorProps &props, ALenum param, const int *vals)
{ SetParami(props, param, *vals); }

void ModulatorEffectHandler::SetParamf(ModulatorProps &props, ALenum param, float val)
{
    switch(param)
    {
    case AL_RING_MODULATOR_FREQUENCY:
        if(!(val >= AL_RING_MODULATOR_MIN_FREQUENCY && val <= AL_RING_MODULATOR_MAX_FREQUENCY))
            throw effect_exception{AL_INVALID_VALUE, "Modulator frequency out of range: %f", val};
        props.Frequency = val;
        break;

    case AL_RING_MODULATOR_HIGHPASS_CUTOFF:
        if(!(val >= AL_RING_MODULATOR_MIN_HIGHPASS_CUTOFF && val <= AL_RING_MODULATOR_MAX_HIGHPASS_CUTOFF))
            throw effect_exception{AL_INVALID_VALUE, "Modulator high-pass cutoff out of range: %f", val};
        props.HighPassCutoff = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid modulator float property 0x%04x", param};
    }
}
void ModulatorEffectHandler::SetParamfv(ModulatorProps &props, ALenum param, const float *vals)
{ SetParamf(props, param, *vals); }

void ModulatorEffectHandler::GetParami(const ModulatorProps &props, ALenum param, int *val)
{
    switch(param)
    {
    case AL_RING_MODULATOR_FREQUENCY: *val = static_cast<int>(props.Frequency); break;
    case AL_RING_MODULATOR_HIGHPASS_CUTOFF: *val = static_cast<int>(props.HighPassCutoff); break;
    case AL_RING_MODULATOR_WAVEFORM: *val = EnumFromWaveform(props.Waveform); break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid modulator integer property 0x%04x",
            param};
    }
}
void ModulatorEffectHandler::GetParamiv(const ModulatorProps &props, ALenum param, int *vals)
{ GetParami(props, param, vals); }
void ModulatorEffectHandler::GetParamf(const ModulatorProps &props, ALenum param, float *val)
{
    switch(param)
    {
    case AL_RING_MODULATOR_FREQUENCY: *val = props.Frequency; break;
    case AL_RING_MODULATOR_HIGHPASS_CUTOFF: *val = props.HighPassCutoff; break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid modulator float property 0x%04x", param};
    }
}
void ModulatorEffectHandler::GetParamfv(const ModulatorProps &props, ALenum param, float *vals)
{ GetParamf(props, param, vals); }


#if ALSOFT_EAX
namespace {

using ModulatorCommitter = EaxCommitter<EaxModulatorCommitter>;

struct FrequencyValidator {
    void operator()(float flFrequency) const
    {
        eax_validate_range<ModulatorCommitter::Exception>(
            "Frequency",
            flFrequency,
            EAXRINGMODULATOR_MINFREQUENCY,
            EAXRINGMODULATOR_MAXFREQUENCY);
    }
}; // FrequencyValidator

struct HighPassCutOffValidator {
    void operator()(float flHighPassCutOff) const
    {
        eax_validate_range<ModulatorCommitter::Exception>(
            "High-Pass Cutoff",
            flHighPassCutOff,
            EAXRINGMODULATOR_MINHIGHPASSCUTOFF,
            EAXRINGMODULATOR_MAXHIGHPASSCUTOFF);
    }
}; // HighPassCutOffValidator

struct WaveformValidator {
    void operator()(unsigned long ulWaveform) const
    {
        eax_validate_range<ModulatorCommitter::Exception>(
            "Waveform",
            ulWaveform,
            EAXRINGMODULATOR_MINWAVEFORM,
            EAXRINGMODULATOR_MAXWAVEFORM);
    }
}; // WaveformValidator

struct AllValidator {
    void operator()(const EAXRINGMODULATORPROPERTIES& all) const
    {
        FrequencyValidator{}(all.flFrequency);
        HighPassCutOffValidator{}(all.flHighPassCutOff);
        WaveformValidator{}(all.ulWaveform);
    }
}; // AllValidator

} // namespace

template<>
struct ModulatorCommitter::Exception : public EaxException {
    explicit Exception(const char *message) : EaxException{"EAX_RING_MODULATOR_EFFECT", message}
    { }
};

template<>
[[noreturn]] void ModulatorCommitter::fail(const char *message)
{
    throw Exception{message};
}

bool EaxModulatorCommitter::commit(const EAXRINGMODULATORPROPERTIES &props)
{
    if(auto *cur = std::get_if<EAXRINGMODULATORPROPERTIES>(&mEaxProps); cur && *cur == props)
        return false;

    mEaxProps = props;

    auto get_waveform = [](unsigned long form)
    {
        if(form == EAX_RINGMODULATOR_SINUSOID)
            return ModulatorWaveform::Sinusoid;
        if(form == EAX_RINGMODULATOR_SAWTOOTH)
            return ModulatorWaveform::Sawtooth;
        if(form == EAX_RINGMODULATOR_SQUARE)
            return ModulatorWaveform::Square;
        return ModulatorWaveform::Sinusoid;
    };

    mAlProps = [&]{
        ModulatorProps ret{};
        ret.Frequency = props.flFrequency;
        ret.HighPassCutoff = props.flHighPassCutOff;
        ret.Waveform = get_waveform(props.ulWaveform);
        return ret;
    }();

    return true;
}

void EaxModulatorCommitter::SetDefaults(EaxEffectProps &props)
{
    static constexpr EAXRINGMODULATORPROPERTIES defprops{[]
    {
        EAXRINGMODULATORPROPERTIES ret{};
        ret.flFrequency = EAXRINGMODULATOR_DEFAULTFREQUENCY;
        ret.flHighPassCutOff = EAXRINGMODULATOR_DEFAULTHIGHPASSCUTOFF;
        ret.ulWaveform = EAXRINGMODULATOR_DEFAULTWAVEFORM;
        return ret;
    }()};
    props = defprops;
}

void EaxModulatorCommitter::Get(const EaxCall &call, const EAXRINGMODULATORPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXRINGMODULATOR_NONE: break;
    case EAXRINGMODULATOR_ALLPARAMETERS: call.set_value<Exception>(props); break;
    case EAXRINGMODULATOR_FREQUENCY: call.set_value<Exception>(props.flFrequency); break;
    case EAXRINGMODULATOR_HIGHPASSCUTOFF: call.set_value<Exception>(props.flHighPassCutOff); break;
    case EAXRINGMODULATOR_WAVEFORM: call.set_value<Exception>(props.ulWaveform); break;
    default: fail_unknown_property_id();
    }
}

void EaxModulatorCommitter::Set(const EaxCall &call, EAXRINGMODULATORPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXRINGMODULATOR_NONE: break;
    case EAXRINGMODULATOR_ALLPARAMETERS: defer<AllValidator>(call, props); break;
    case EAXRINGMODULATOR_FREQUENCY: defer<FrequencyValidator>(call, props.flFrequency); break;
    case EAXRINGMODULATOR_HIGHPASSCUTOFF: defer<HighPassCutOffValidator>(call, props.flHighPassCutOff); break;
    case EAXRINGMODULATOR_WAVEFORM: defer<WaveformValidator>(call, props.ulWaveform); break;
    default: fail_unknown_property_id();
    }
}

#endif // ALSOFT_EAX
