/**
 * This file is part of the OpenAL Soft cross platform audio library
 *
 * Copyright (C) 2013 by Anis A. Hireche
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 *
 * * Neither the name of Spherical-Harmonic-Transform nor the names of its
 *   contributors may be used to endorse or promote products derived from
 *   this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <variant>

#include "alc/effects/base.h"
#include "alspan.h"
#include "core/ambidefs.h"
#include "core/bufferline.h"
#include "core/device.h"
#include "core/effects/base.h"
#include "core/effectslot.h"
#include "core/mixer/defs.h"
#include "intrusive_ptr.h"

struct BufferStorage;
struct ContextBase;


namespace {

constexpr float AmpEnvelopeMin{0.5f};
constexpr float AmpEnvelopeMax{2.0f};

constexpr float AttackTime{0.1f}; /* 100ms to rise from min to max */
constexpr float ReleaseTime{0.2f}; /* 200ms to drop from max to min */


struct CompressorState final : public EffectState {
    /* Effect gains for each channel */
    struct TargetGain {
        uint mTarget{InvalidChannelIndex};
        float mGain{1.0f};
    };
    std::array<TargetGain,MaxAmbiChannels> mChans;

    /* Effect parameters */
    bool mEnabled{true};
    float mAttackMult{1.0f};
    float mReleaseMult{1.0f};
    float mEnvFollower{1.0f};
    alignas(16) FloatBufferLine mGains{};


    void deviceUpdate(const DeviceBase *device, const BufferStorage *buffer) override;
    void update(const ContextBase *context, const EffectSlot *slot, const EffectProps *props,
        const EffectTarget target) override;
    void process(const size_t samplesToDo, const al::span<const FloatBufferLine> samplesIn,
        const al::span<FloatBufferLine> samplesOut) override;
};

void CompressorState::deviceUpdate(const DeviceBase *device, const BufferStorage*)
{
    /* Number of samples to do a full attack and release (non-integer sample
     * counts are okay).
     */
    const float attackCount{static_cast<float>(device->Frequency) * AttackTime};
    const float releaseCount{static_cast<float>(device->Frequency) * ReleaseTime};

    /* Calculate per-sample multipliers to attack and release at the desired
     * rates.
     */
    mAttackMult  = std::pow(AmpEnvelopeMax/AmpEnvelopeMin, 1.0f/attackCount);
    mReleaseMult = std::pow(AmpEnvelopeMin/AmpEnvelopeMax, 1.0f/releaseCount);
}

void CompressorState::update(const ContextBase*, const EffectSlot *slot,
    const EffectProps *props, const EffectTarget target)
{
    mEnabled = std::get<CompressorProps>(*props).OnOff;

    mOutTarget = target.Main->Buffer;
    auto set_channel = [this](size_t idx, uint outchan, float outgain)
    {
        mChans[idx].mTarget = outchan;
        mChans[idx].mGain = outgain;
    };
    target.Main->setAmbiMixParams(slot->Wet, slot->Gain, set_channel);
}

void CompressorState::process(const size_t samplesToDo,
    const al::span<const FloatBufferLine> samplesIn, const al::span<FloatBufferLine> samplesOut)
{
    /* Generate the per-sample gains from the signal envelope. */
    float env{mEnvFollower};
    if(mEnabled)
    {
        for(size_t i{0u};i < samplesToDo;++i)
        {
            /* Clamp the absolute amplitude to the defined envelope limits,
             * then attack or release the envelope to reach it.
             */
            const float amplitude{std::clamp(std::fabs(samplesIn[0][i]), AmpEnvelopeMin,
                AmpEnvelopeMax)};
            if(amplitude > env)
                env = std::min(env*mAttackMult, amplitude);
            else if(amplitude < env)
                env = std::max(env*mReleaseMult, amplitude);

            /* Apply the reciprocal of the envelope to normalize the volume
             * (compress the dynamic range).
             */
            mGains[i] = 1.0f / env;
        }
    }
    else
    {
        /* Same as above, except the amplitude is forced to 1. This helps
         * ensure smooth gain changes when the compressor is turned on and off.
         */
        for(size_t i{0u};i < samplesToDo;++i)
        {
            const float amplitude{1.0f};
            if(amplitude > env)
                env = std::min(env*mAttackMult, amplitude);
            else if(amplitude < env)
                env = std::max(env*mReleaseMult, amplitude);

            mGains[i] = 1.0f / env;
        }
    }
    mEnvFollower = env;

    /* Now compress the signal amplitude to output. */
    auto chan = mChans.cbegin();
    for(const auto &input : samplesIn)
    {
        const size_t outidx{chan->mTarget};
        if(outidx != InvalidChannelIndex)
        {
            const auto dst = al::span{samplesOut[outidx]};
            const float gain{chan->mGain};
            if(!(std::fabs(gain) > GainSilenceThreshold))
            {
                for(size_t i{0u};i < samplesToDo;++i)
                    dst[i] += input[i] * mGains[i] * gain;
            }
        }
        ++chan;
    }
}


struct CompressorStateFactory final : public EffectStateFactory {
    al::intrusive_ptr<EffectState> create() override
    { return al::intrusive_ptr<EffectState>{new CompressorState{}}; }
};

} // namespace

EffectStateFactory *CompressorStateFactory_getFactory()
{
    static CompressorStateFactory CompressorFactory{};
    return &CompressorFactory;
}
