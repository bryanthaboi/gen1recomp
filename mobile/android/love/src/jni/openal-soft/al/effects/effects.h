#ifndef AL_EFFECTS_EFFECTS_H
#define AL_EFFECTS_EFFECTS_H

#include <variant>

#include "AL/al.h"

#include "al/error.h"
#include "core/effects/base.h"

#define DECL_HANDLER(N, T)                                                    \
struct N {                                                                    \
    using prop_type = T;                                                      \
                                                                              \
    static void SetParami(prop_type &props, ALenum param, int val);           \
    static void SetParamiv(prop_type &props, ALenum param, const int *vals);  \
    static void SetParamf(prop_type &props, ALenum param, float val);         \
    static void SetParamfv(prop_type &props, ALenum param, const float *vals);\
    static void GetParami(const prop_type &props, ALenum param, int *val);    \
    static void GetParamiv(const prop_type &props, ALenum param, int *vals);  \
    static void GetParamf(const prop_type &props, ALenum param, float *val);  \
    static void GetParamfv(const prop_type &props, ALenum param, float *vals);\
};
DECL_HANDLER(NullEffectHandler, std::monostate)
DECL_HANDLER(ReverbEffectHandler, ReverbProps)
DECL_HANDLER(StdReverbEffectHandler, ReverbProps)
DECL_HANDLER(AutowahEffectHandler, AutowahProps)
DECL_HANDLER(ChorusEffectHandler, ChorusProps)
DECL_HANDLER(CompressorEffectHandler, CompressorProps)
DECL_HANDLER(DistortionEffectHandler, DistortionProps)
DECL_HANDLER(EchoEffectHandler, EchoProps)
DECL_HANDLER(EqualizerEffectHandler, EqualizerProps)
DECL_HANDLER(FlangerEffectHandler, ChorusProps)
DECL_HANDLER(FshifterEffectHandler, FshifterProps)
DECL_HANDLER(ModulatorEffectHandler, ModulatorProps)
DECL_HANDLER(PshifterEffectHandler, PshifterProps)
DECL_HANDLER(VmorpherEffectHandler, VmorpherProps)
DECL_HANDLER(DedicatedDialogEffectHandler, DedicatedProps)
DECL_HANDLER(DedicatedLfeEffectHandler, DedicatedProps)
DECL_HANDLER(ConvolutionEffectHandler, ConvolutionProps)
#undef DECL_HANDLER


using effect_exception = al::context_error;


/* Default properties for the given effect types. */
extern const EffectProps NullEffectProps;
extern const EffectProps ReverbEffectProps;
extern const EffectProps StdReverbEffectProps;
extern const EffectProps AutowahEffectProps;
extern const EffectProps ChorusEffectProps;
extern const EffectProps CompressorEffectProps;
extern const EffectProps DistortionEffectProps;
extern const EffectProps EchoEffectProps;
extern const EffectProps EqualizerEffectProps;
extern const EffectProps FlangerEffectProps;
extern const EffectProps FshifterEffectProps;
extern const EffectProps ModulatorEffectProps;
extern const EffectProps PshifterEffectProps;
extern const EffectProps VmorpherEffectProps;
extern const EffectProps DedicatedDialogEffectProps;
extern const EffectProps DedicatedLfeEffectProps;
extern const EffectProps ConvolutionEffectProps;

#endif /* AL_EFFECTS_EFFECTS_H */
