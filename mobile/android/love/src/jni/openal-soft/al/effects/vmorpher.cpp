
#include "config.h"

#include <optional>
#include <stdexcept>

#include "AL/al.h"
#include "AL/efx.h"

#include "core/effects/base.h"
#include "effects.h"

#if ALSOFT_EAX
#include <cassert>
#include "al/eax/effect.h"
#include "al/eax/exception.h"
#include "al/eax/utils.h"
#endif // ALSOFT_EAX


namespace {

constexpr std::optional<VMorpherPhenome> PhenomeFromEnum(ALenum val) noexcept
{
#define HANDLE_PHENOME(x) case AL_VOCAL_MORPHER_PHONEME_ ## x:                \
    return VMorpherPhenome::x
    switch(val)
    {
    HANDLE_PHENOME(A);
    HANDLE_PHENOME(E);
    HANDLE_PHENOME(I);
    HANDLE_PHENOME(O);
    HANDLE_PHENOME(U);
    HANDLE_PHENOME(AA);
    HANDLE_PHENOME(AE);
    HANDLE_PHENOME(AH);
    HANDLE_PHENOME(AO);
    HANDLE_PHENOME(EH);
    HANDLE_PHENOME(ER);
    HANDLE_PHENOME(IH);
    HANDLE_PHENOME(IY);
    HANDLE_PHENOME(UH);
    HANDLE_PHENOME(UW);
    HANDLE_PHENOME(B);
    HANDLE_PHENOME(D);
    HANDLE_PHENOME(F);
    HANDLE_PHENOME(G);
    HANDLE_PHENOME(J);
    HANDLE_PHENOME(K);
    HANDLE_PHENOME(L);
    HANDLE_PHENOME(M);
    HANDLE_PHENOME(N);
    HANDLE_PHENOME(P);
    HANDLE_PHENOME(R);
    HANDLE_PHENOME(S);
    HANDLE_PHENOME(T);
    HANDLE_PHENOME(V);
    HANDLE_PHENOME(Z);
    }
    return std::nullopt;
#undef HANDLE_PHENOME
}
constexpr ALenum EnumFromPhenome(VMorpherPhenome phenome)
{
#define HANDLE_PHENOME(x) case VMorpherPhenome::x: return AL_VOCAL_MORPHER_PHONEME_ ## x
    switch(phenome)
    {
    HANDLE_PHENOME(A);
    HANDLE_PHENOME(E);
    HANDLE_PHENOME(I);
    HANDLE_PHENOME(O);
    HANDLE_PHENOME(U);
    HANDLE_PHENOME(AA);
    HANDLE_PHENOME(AE);
    HANDLE_PHENOME(AH);
    HANDLE_PHENOME(AO);
    HANDLE_PHENOME(EH);
    HANDLE_PHENOME(ER);
    HANDLE_PHENOME(IH);
    HANDLE_PHENOME(IY);
    HANDLE_PHENOME(UH);
    HANDLE_PHENOME(UW);
    HANDLE_PHENOME(B);
    HANDLE_PHENOME(D);
    HANDLE_PHENOME(F);
    HANDLE_PHENOME(G);
    HANDLE_PHENOME(J);
    HANDLE_PHENOME(K);
    HANDLE_PHENOME(L);
    HANDLE_PHENOME(M);
    HANDLE_PHENOME(N);
    HANDLE_PHENOME(P);
    HANDLE_PHENOME(R);
    HANDLE_PHENOME(S);
    HANDLE_PHENOME(T);
    HANDLE_PHENOME(V);
    HANDLE_PHENOME(Z);
    }
    throw std::runtime_error{"Invalid phenome: "+std::to_string(static_cast<int>(phenome))};
#undef HANDLE_PHENOME
}

constexpr std::optional<VMorpherWaveform> WaveformFromEmum(ALenum value) noexcept
{
    switch(value)
    {
    case AL_VOCAL_MORPHER_WAVEFORM_SINUSOID: return VMorpherWaveform::Sinusoid;
    case AL_VOCAL_MORPHER_WAVEFORM_TRIANGLE: return VMorpherWaveform::Triangle;
    case AL_VOCAL_MORPHER_WAVEFORM_SAWTOOTH: return VMorpherWaveform::Sawtooth;
    }
    return std::nullopt;
}
constexpr ALenum EnumFromWaveform(VMorpherWaveform type)
{
    switch(type)
    {
    case VMorpherWaveform::Sinusoid: return AL_VOCAL_MORPHER_WAVEFORM_SINUSOID;
    case VMorpherWaveform::Triangle: return AL_VOCAL_MORPHER_WAVEFORM_TRIANGLE;
    case VMorpherWaveform::Sawtooth: return AL_VOCAL_MORPHER_WAVEFORM_SAWTOOTH;
    }
    throw std::runtime_error{"Invalid vocal morpher waveform: " +
        std::to_string(static_cast<int>(type))};
}

constexpr EffectProps genDefaultProps() noexcept
{
    VmorpherProps props{};
    props.Rate                 = AL_VOCAL_MORPHER_DEFAULT_RATE;
    props.PhonemeA             = PhenomeFromEnum(AL_VOCAL_MORPHER_DEFAULT_PHONEMEA).value();
    props.PhonemeB             = PhenomeFromEnum(AL_VOCAL_MORPHER_DEFAULT_PHONEMEB).value();
    props.PhonemeACoarseTuning = AL_VOCAL_MORPHER_DEFAULT_PHONEMEA_COARSE_TUNING;
    props.PhonemeBCoarseTuning = AL_VOCAL_MORPHER_DEFAULT_PHONEMEB_COARSE_TUNING;
    props.Waveform             = WaveformFromEmum(AL_VOCAL_MORPHER_DEFAULT_WAVEFORM).value();
    return props;
}

} // namespace

const EffectProps VmorpherEffectProps{genDefaultProps()};

void VmorpherEffectHandler::SetParami(VmorpherProps &props, ALenum param, int val)
{
    switch(param)
    {
    case AL_VOCAL_MORPHER_PHONEMEA:
        if(auto phenomeopt = PhenomeFromEnum(val))
            props.PhonemeA = *phenomeopt;
        else
            throw effect_exception{AL_INVALID_VALUE, "Vocal morpher phoneme-a out of range: 0x%04x", val};
        break;

    case AL_VOCAL_MORPHER_PHONEMEA_COARSE_TUNING:
        if(!(val >= AL_VOCAL_MORPHER_MIN_PHONEMEA_COARSE_TUNING && val <= AL_VOCAL_MORPHER_MAX_PHONEMEA_COARSE_TUNING))
            throw effect_exception{AL_INVALID_VALUE, "Vocal morpher phoneme-a coarse tuning out of range"};
        props.PhonemeACoarseTuning = val;
        break;

    case AL_VOCAL_MORPHER_PHONEMEB:
        if(auto phenomeopt = PhenomeFromEnum(val))
            props.PhonemeB = *phenomeopt;
        else
            throw effect_exception{AL_INVALID_VALUE, "Vocal morpher phoneme-b out of range: 0x%04x", val};
        break;

    case AL_VOCAL_MORPHER_PHONEMEB_COARSE_TUNING:
        if(!(val >= AL_VOCAL_MORPHER_MIN_PHONEMEB_COARSE_TUNING && val <= AL_VOCAL_MORPHER_MAX_PHONEMEB_COARSE_TUNING))
            throw effect_exception{AL_INVALID_VALUE, "Vocal morpher phoneme-b coarse tuning out of range"};
        props.PhonemeBCoarseTuning = val;
        break;

    case AL_VOCAL_MORPHER_WAVEFORM:
        if(auto formopt = WaveformFromEmum(val))
            props.Waveform = *formopt;
        else
            throw effect_exception{AL_INVALID_VALUE, "Vocal morpher waveform out of range: 0x%04x", val};
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid vocal morpher integer property 0x%04x",
            param};
    }
}
void VmorpherEffectHandler::SetParamiv(VmorpherProps&, ALenum param, const int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid vocal morpher integer-vector property 0x%04x",
        param};
}
void VmorpherEffectHandler::SetParamf(VmorpherProps &props, ALenum param, float val)
{
    switch(param)
    {
    case AL_VOCAL_MORPHER_RATE:
        if(!(val >= AL_VOCAL_MORPHER_MIN_RATE && val <= AL_VOCAL_MORPHER_MAX_RATE))
            throw effect_exception{AL_INVALID_VALUE, "Vocal morpher rate out of range"};
        props.Rate = val;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid vocal morpher float property 0x%04x",
            param};
    }
}
void VmorpherEffectHandler::SetParamfv(VmorpherProps &props, ALenum param, const float *vals)
{ SetParamf(props, param, *vals); }

void VmorpherEffectHandler::GetParami(const VmorpherProps &props, ALenum param, int* val)
{
    switch(param)
    {
    case AL_VOCAL_MORPHER_PHONEMEA: *val = EnumFromPhenome(props.PhonemeA); break;
    case AL_VOCAL_MORPHER_PHONEMEA_COARSE_TUNING: *val = props.PhonemeACoarseTuning; break;
    case AL_VOCAL_MORPHER_PHONEMEB: *val = EnumFromPhenome(props.PhonemeB); break;
    case AL_VOCAL_MORPHER_PHONEMEB_COARSE_TUNING: *val = props.PhonemeBCoarseTuning; break;
    case AL_VOCAL_MORPHER_WAVEFORM: *val = EnumFromWaveform(props.Waveform); break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid vocal morpher integer property 0x%04x",
            param};
    }
}
void VmorpherEffectHandler::GetParamiv(const VmorpherProps&, ALenum param, int*)
{
    throw effect_exception{AL_INVALID_ENUM, "Invalid vocal morpher integer-vector property 0x%04x",
        param};
}
void VmorpherEffectHandler::GetParamf(const VmorpherProps &props, ALenum param, float *val)
{
    switch(param)
    {
    case AL_VOCAL_MORPHER_RATE:
        *val = props.Rate;
        break;

    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid vocal morpher float property 0x%04x",
            param};
    }
}
void VmorpherEffectHandler::GetParamfv(const VmorpherProps &props, ALenum param, float *vals)
{ GetParamf(props, param, vals); }


#if ALSOFT_EAX
namespace {

using VocalMorpherCommitter = EaxCommitter<EaxVocalMorpherCommitter>;

struct PhonemeAValidator {
    void operator()(unsigned long ulPhonemeA) const
    {
        eax_validate_range<VocalMorpherCommitter::Exception>(
            "Phoneme A",
            ulPhonemeA,
            EAXVOCALMORPHER_MINPHONEMEA,
            EAXVOCALMORPHER_MAXPHONEMEA);
    }
}; // PhonemeAValidator

struct PhonemeACoarseTuningValidator {
    void operator()(long lPhonemeACoarseTuning) const
    {
        eax_validate_range<VocalMorpherCommitter::Exception>(
            "Phoneme A Coarse Tuning",
            lPhonemeACoarseTuning,
            EAXVOCALMORPHER_MINPHONEMEACOARSETUNING,
            EAXVOCALMORPHER_MAXPHONEMEACOARSETUNING);
    }
}; // PhonemeACoarseTuningValidator

struct PhonemeBValidator {
    void operator()(unsigned long ulPhonemeB) const
    {
        eax_validate_range<VocalMorpherCommitter::Exception>(
            "Phoneme B",
            ulPhonemeB,
            EAXVOCALMORPHER_MINPHONEMEB,
            EAXVOCALMORPHER_MAXPHONEMEB);
    }
}; // PhonemeBValidator

struct PhonemeBCoarseTuningValidator {
    void operator()(long lPhonemeBCoarseTuning) const
    {
        eax_validate_range<VocalMorpherCommitter::Exception>(
            "Phoneme B Coarse Tuning",
            lPhonemeBCoarseTuning,
            EAXVOCALMORPHER_MINPHONEMEBCOARSETUNING,
            EAXVOCALMORPHER_MAXPHONEMEBCOARSETUNING);
    }
}; // PhonemeBCoarseTuningValidator

struct WaveformValidator {
    void operator()(unsigned long ulWaveform) const
    {
        eax_validate_range<VocalMorpherCommitter::Exception>(
            "Waveform",
            ulWaveform,
            EAXVOCALMORPHER_MINWAVEFORM,
            EAXVOCALMORPHER_MAXWAVEFORM);
    }
}; // WaveformValidator

struct RateValidator {
    void operator()(float flRate) const
    {
        eax_validate_range<VocalMorpherCommitter::Exception>(
            "Rate",
            flRate,
            EAXVOCALMORPHER_MINRATE,
            EAXVOCALMORPHER_MAXRATE);
    }
}; // RateValidator

struct AllValidator {
    void operator()(const EAXVOCALMORPHERPROPERTIES& all) const
    {
        PhonemeAValidator{}(all.ulPhonemeA);
        PhonemeACoarseTuningValidator{}(all.lPhonemeACoarseTuning);
        PhonemeBValidator{}(all.ulPhonemeB);
        PhonemeBCoarseTuningValidator{}(all.lPhonemeBCoarseTuning);
        WaveformValidator{}(all.ulWaveform);
        RateValidator{}(all.flRate);
    }
}; // AllValidator

} // namespace

template<>
struct VocalMorpherCommitter::Exception : public EaxException {
    explicit Exception(const char *message) : EaxException{"EAX_VOCAL_MORPHER_EFFECT", message}
    { }
};

template<>
[[noreturn]] void VocalMorpherCommitter::fail(const char *message)
{
    throw Exception{message};
}

bool EaxVocalMorpherCommitter::commit(const EAXVOCALMORPHERPROPERTIES &props)
{
    if(auto *cur = std::get_if<EAXVOCALMORPHERPROPERTIES>(&mEaxProps); cur && *cur == props)
        return false;

    mEaxProps = props;

    auto get_phoneme = [](unsigned long phoneme) noexcept
    {
#define HANDLE_PHENOME(x) case x: return VMorpherPhenome::x
        switch(phoneme)
        {
        HANDLE_PHENOME(A);
        HANDLE_PHENOME(E);
        HANDLE_PHENOME(I);
        HANDLE_PHENOME(O);
        HANDLE_PHENOME(U);
        HANDLE_PHENOME(AA);
        HANDLE_PHENOME(AE);
        HANDLE_PHENOME(AH);
        HANDLE_PHENOME(AO);
        HANDLE_PHENOME(EH);
        HANDLE_PHENOME(ER);
        HANDLE_PHENOME(IH);
        HANDLE_PHENOME(IY);
        HANDLE_PHENOME(UH);
        HANDLE_PHENOME(UW);
        HANDLE_PHENOME(B);
        HANDLE_PHENOME(D);
        HANDLE_PHENOME(F);
        HANDLE_PHENOME(G);
        HANDLE_PHENOME(J);
        HANDLE_PHENOME(K);
        HANDLE_PHENOME(L);
        HANDLE_PHENOME(M);
        HANDLE_PHENOME(N);
        HANDLE_PHENOME(P);
        HANDLE_PHENOME(R);
        HANDLE_PHENOME(S);
        HANDLE_PHENOME(T);
        HANDLE_PHENOME(V);
        HANDLE_PHENOME(Z);
        }
        return VMorpherPhenome::A;
#undef HANDLE_PHENOME
    };
    auto get_waveform = [](unsigned long form) noexcept
    {
        if(form == EAX_VOCALMORPHER_SINUSOID) return VMorpherWaveform::Sinusoid;
        if(form == EAX_VOCALMORPHER_TRIANGLE) return VMorpherWaveform::Triangle;
        if(form == EAX_VOCALMORPHER_SAWTOOTH) return VMorpherWaveform::Sawtooth;
        return VMorpherWaveform::Sinusoid;
    };

    mAlProps = [&]{
        VmorpherProps ret{};
        ret.PhonemeA = get_phoneme(props.ulPhonemeA);
        ret.PhonemeACoarseTuning = static_cast<int>(props.lPhonemeACoarseTuning);
        ret.PhonemeB = get_phoneme(props.ulPhonemeB);
        ret.PhonemeBCoarseTuning = static_cast<int>(props.lPhonemeBCoarseTuning);
        ret.Waveform = get_waveform(props.ulWaveform);
        ret.Rate = props.flRate;
        return ret;
    }();

    return true;
}

void EaxVocalMorpherCommitter::SetDefaults(EaxEffectProps &props)
{
    static constexpr EAXVOCALMORPHERPROPERTIES defprops{[]
    {
        EAXVOCALMORPHERPROPERTIES ret{};
        ret.ulPhonemeA = EAXVOCALMORPHER_DEFAULTPHONEMEA;
        ret.lPhonemeACoarseTuning = EAXVOCALMORPHER_DEFAULTPHONEMEACOARSETUNING;
        ret.ulPhonemeB = EAXVOCALMORPHER_DEFAULTPHONEMEB;
        ret.lPhonemeBCoarseTuning = EAXVOCALMORPHER_DEFAULTPHONEMEBCOARSETUNING;
        ret.ulWaveform = EAXVOCALMORPHER_DEFAULTWAVEFORM;
        ret.flRate = EAXVOCALMORPHER_DEFAULTRATE;
        return ret;
    }()};
    props = defprops;
}

void EaxVocalMorpherCommitter::Get(const EaxCall &call, const EAXVOCALMORPHERPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXVOCALMORPHER_NONE: break;
    case EAXVOCALMORPHER_ALLPARAMETERS: call.set_value<Exception>(props); break;
    case EAXVOCALMORPHER_PHONEMEA: call.set_value<Exception>(props.ulPhonemeA); break;
    case EAXVOCALMORPHER_PHONEMEACOARSETUNING: call.set_value<Exception>(props.lPhonemeACoarseTuning); break;
    case EAXVOCALMORPHER_PHONEMEB: call.set_value<Exception>(props.ulPhonemeB); break;
    case EAXVOCALMORPHER_PHONEMEBCOARSETUNING: call.set_value<Exception>(props.lPhonemeBCoarseTuning); break;
    case EAXVOCALMORPHER_WAVEFORM: call.set_value<Exception>(props.ulWaveform); break;
    case EAXVOCALMORPHER_RATE: call.set_value<Exception>(props.flRate); break;
    default: fail_unknown_property_id();
    }
}

void EaxVocalMorpherCommitter::Set(const EaxCall &call, EAXVOCALMORPHERPROPERTIES &props)
{
    switch(call.get_property_id())
    {
    case EAXVOCALMORPHER_NONE: break;
    case EAXVOCALMORPHER_ALLPARAMETERS: defer<AllValidator>(call, props); break;
    case EAXVOCALMORPHER_PHONEMEA: defer<PhonemeAValidator>(call, props.ulPhonemeA); break;
    case EAXVOCALMORPHER_PHONEMEACOARSETUNING: defer<PhonemeACoarseTuningValidator>(call, props.lPhonemeACoarseTuning); break;
    case EAXVOCALMORPHER_PHONEMEB: defer<PhonemeBValidator>(call, props.ulPhonemeB); break;
    case EAXVOCALMORPHER_PHONEMEBCOARSETUNING: defer<PhonemeBCoarseTuningValidator>(call, props.lPhonemeBCoarseTuning); break;
    case EAXVOCALMORPHER_WAVEFORM: defer<WaveformValidator>(call, props.ulWaveform); break;
    case EAXVOCALMORPHER_RATE: defer<RateValidator>(call, props.flRate); break;
    default: fail_unknown_property_id();
    }
}

#endif // ALSOFT_EAX
