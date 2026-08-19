#ifndef EFFECTS_BASE_H
#define EFFECTS_BASE_H

#include "core/effects/base.h"


/* This is a user config option for modifying the overall output of the reverb
 * effect.
 */
inline float ReverbBoost{1.0f};


EffectStateFactory *NullStateFactory_getFactory();
EffectStateFactory *ReverbStateFactory_getFactory();
EffectStateFactory *ChorusStateFactory_getFactory();
EffectStateFactory *AutowahStateFactory_getFactory();
EffectStateFactory *CompressorStateFactory_getFactory();
EffectStateFactory *DistortionStateFactory_getFactory();
EffectStateFactory *EchoStateFactory_getFactory();
EffectStateFactory *EqualizerStateFactory_getFactory();
EffectStateFactory *FshifterStateFactory_getFactory();
EffectStateFactory *ModulatorStateFactory_getFactory();
EffectStateFactory *PshifterStateFactory_getFactory();
EffectStateFactory* VmorpherStateFactory_getFactory();

EffectStateFactory *DedicatedStateFactory_getFactory();

EffectStateFactory *ConvolutionStateFactory_getFactory();

#endif /* EFFECTS_BASE_H */
