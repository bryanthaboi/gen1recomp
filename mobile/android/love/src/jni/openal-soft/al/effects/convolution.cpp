
#include "config.h"

#include <algorithm>
#include <array>
#include <cmath>

#include "AL/al.h"

#include "alc/inprogext.h"
#include "alnumeric.h"
#include "alspan.h"
#include "core/effects/base.h"
#include "effects.h"


namespace {

constexpr EffectProps genDefaultProps() noexcept
{
    ConvolutionProps props{};
    props.OrientAt = {0.0f,  0.0f, -1.0f};
    props.OrientUp = {0.0f,  1.0f,  0.0f};
    return props;
}

} // namespace

const EffectProps ConvolutionEffectProps{genDefaultProps()};

void ConvolutionEffectHandler::SetParami(ConvolutionProps& /*props*/, ALenum param, int /*val*/)
{
    switch(param)
    {
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid convolution effect integer property 0x%04x",
            param};
    }
}
void ConvolutionEffectHandler::SetParamiv(ConvolutionProps &props, ALenum param, const int *vals)
{
    switch(param)
    {
    default:
        SetParami(props, param, *vals);
    }
}
void ConvolutionEffectHandler::SetParamf(ConvolutionProps& /*props*/, ALenum param, float /*val*/)
{
    switch(param)
    {
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid convolution effect float property 0x%04x",
            param};
    }
}
void ConvolutionEffectHandler::SetParamfv(ConvolutionProps &props, ALenum param, const float *values)
{
    static constexpr auto finite_checker = [](float val) -> bool { return std::isfinite(val); };
    al::span<const float> vals;
    switch(param)
    {
    case AL_CONVOLUTION_ORIENTATION_SOFT:
        vals = {values, 6_uz};
        if(!std::all_of(vals.cbegin(), vals.cend(), finite_checker))
            throw effect_exception{AL_INVALID_VALUE, "Property 0x%04x value out of range", param};

        std::copy_n(vals.cbegin(), props.OrientAt.size(), props.OrientAt.begin());
        std::copy_n(vals.cbegin()+3, props.OrientUp.size(), props.OrientUp.begin());
        break;

    default:
        SetParamf(props, param, *values);
    }
}

void ConvolutionEffectHandler::GetParami(const ConvolutionProps& /*props*/, ALenum param, int* /*val*/)
{
    switch(param)
    {
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid convolution effect integer property 0x%04x",
            param};
    }
}
void ConvolutionEffectHandler::GetParamiv(const ConvolutionProps &props, ALenum param, int *vals)
{
    switch(param)
    {
    default:
        GetParami(props, param, vals);
    }
}
void ConvolutionEffectHandler::GetParamf(const ConvolutionProps& /*props*/, ALenum param, float* /*val*/)
{
    switch(param)
    {
    default:
        throw effect_exception{AL_INVALID_ENUM, "Invalid convolution effect float property 0x%04x",
            param};
    }
}
void ConvolutionEffectHandler::GetParamfv(const ConvolutionProps &props, ALenum param, float *values)
{
    al::span<float> vals;
    switch(param)
    {
    case AL_CONVOLUTION_ORIENTATION_SOFT:
        vals = {values, 6_uz};
        std::copy(props.OrientAt.cbegin(), props.OrientAt.cend(), vals.begin());
        std::copy(props.OrientUp.cbegin(), props.OrientUp.cend(), vals.begin()+3);
        break;

    default:
        GetParamf(props, param, values);
    }
}
