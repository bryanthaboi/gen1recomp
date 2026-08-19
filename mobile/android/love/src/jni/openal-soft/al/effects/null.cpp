
#include "config.h"

#include "AL/al.h"
#include "AL/efx.h"

#include "alc/effects/base.h"
#include "effects.h"

#if ALSOFT_EAX
#include "al/eax/effect.h"
#include "al/eax/exception.h"
#endif // ALSOFT_EAX


namespace {

constexpr EffectProps genDefaultProps() noexcept
{
    return std::monostate{};
}

} // namespace

const EffectProps NullEffectProps{genDefaultProps()};

void NullEffectHandler::SetParami(std::monostate& /*props*/, ALenum param, int /*val*/)
{
    switch(param)
    {
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid null effect integer property 0x%04x",
            param};
    }
}
void NullEffectHandler::SetParamiv(std::monostate &props, ALenum param, const int *vals)
{
    switch(param)
    {
    default:
        SetParami(props, param, *vals);
    }
}
void NullEffectHandler::SetParamf(std::monostate& /*props*/, ALenum param, float /*val*/)
{
    switch(param)
    {
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid null effect float property 0x%04x",
            param};
    }
}
void NullEffectHandler::SetParamfv(std::monostate &props, ALenum param, const float *vals)
{
    switch(param)
    {
    default:
        SetParamf(props, param, *vals);
    }
}

void NullEffectHandler::GetParami(const std::monostate& /*props*/, ALenum param, int* /*val*/)
{
    switch(param)
    {
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid null effect integer property 0x%04x",
            param};
    }
}
void NullEffectHandler::GetParamiv(const std::monostate &props, ALenum param, int *vals)
{
    switch(param)
    {
    default:
        GetParami(props, param, vals);
    }
}
void NullEffectHandler::GetParamf(const std::monostate& /*props*/, ALenum param, float* /*val*/)
{
    switch(param)
    {
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid null effect float property 0x%04x",
            param};
    }
}
void NullEffectHandler::GetParamfv(const std::monostate &props, ALenum param, float *vals)
{
    switch(param)
    {
    default:
        GetParamf(props, param, vals);
    }
}


#if ALSOFT_EAX
namespace {

using NullCommitter = EaxCommitter<EaxNullCommitter>;

} // namespace

template<>
struct NullCommitter::Exception : public EaxException
{
    explicit Exception(const char *message) : EaxException{"EAX_NULL_EFFECT", message}
    { }
};

template<>
[[noreturn]] void NullCommitter::fail(const char *message)
{
    throw Exception{message};
}

bool EaxNullCommitter::commit(const std::monostate &props)
{
    const bool ret{std::holds_alternative<std::monostate>(mEaxProps)};
    mEaxProps = props;
    mAlProps = std::monostate{};
    return ret;
}

void EaxNullCommitter::SetDefaults(EaxEffectProps &props)
{
    props = std::monostate{};
}

void EaxNullCommitter::Get(const EaxCall &call, const std::monostate&)
{
    if(call.get_property_id() != 0)
        fail_unknown_property_id();
}

void EaxNullCommitter::Set(const EaxCall &call, std::monostate&)
{
    if(call.get_property_id() != 0)
        fail_unknown_property_id();
}

#endif // ALSOFT_EAX
