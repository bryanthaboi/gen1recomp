/**
 * OpenAL cross platform audio library
 * Copyright (C) 2018 by Raul Herraiz.
 * This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 *  License along with this library; if not, write to the
 *  Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 * Or go to http://www.gnu.org/copyleft/lgpl.html
 */

#include "config.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <variant>

#include "alc/effects/base.h"
#include "alnumbers.h"
#include "alnumeric.h"
#include "alspan.h"
#include "core/ambidefs.h"
#include "core/bufferline.h"
#include "core/context.h"
#include "core/device.h"
#include "core/effects/base.h"
#include "core/effectslot.h"
#include "core/mixer.h"
#include "intrusive_ptr.h"

struct BufferStorage;

namespace {

constexpr float GainScale{31621.0f};
constexpr float MinFreq{20.0f};
constexpr float MaxFreq{2500.0f};
constexpr float QFactor{5.0f};

struct AutowahState final : public EffectState {
    /* Effect parameters */
    float mAttackRate{};
    float mReleaseRate{};
    float mResonanceGain{};
    float mPeakGain{};
    float mFreqMinNorm{};
    float mBandwidthNorm{};
    float mEnvDelay{};

    /* Filter components derived from the envelope. */
    struct FilterParam {
        float cos_w0{};
        float alpha{};
    };
    std::array<FilterParam,BufferLineSize> mEnv;

    struct ChannelData {
        uint mTargetChannel{InvalidChannelIndex};

        struct FilterHistory {
            float z1{}, z2{};
        };
        FilterHistory mFilter;

        /* Effect gains for each output channel */
        float mCurrentGain{};
        float mTargetGain{};
    };
    std::array<ChannelData,MaxAmbiChannels> mChans;

    /* Effects buffers */
    alignas(16) FloatBufferLine mBufferOut{};


    void deviceUpdate(const DeviceBase *device, const BufferStorage *buffer) override;
    void update(const ContextBase *context, const EffectSlot *slot, const EffectProps *props,
        const EffectTarget target) override;
    void process(const size_t samplesToDo, const al::span<const FloatBufferLine> samplesIn,
        const al::span<FloatBufferLine> samplesOut) override;
};

void AutowahState::deviceUpdate(const DeviceBase*, const BufferStorage*)
{
    /* (Re-)initializing parameters and clear the buffers. */

    mAttackRate    = 1.0f;
    mReleaseRate   = 1.0f;
    mResonanceGain = 10.0f;
    mPeakGain      = 4.5f;
    mFreqMinNorm   = 4.5e-4f;
    mBandwidthNorm = 0.05f;
    mEnvDelay      = 0.0f;

    for(auto &e : mEnv)
    {
        e.cos_w0 = 0.0f;
        e.alpha = 0.0f;
    }

    for(auto &chan : mChans)
    {
        chan.mTargetChannel = InvalidChannelIndex;
        chan.mFilter.z1 = 0.0f;
        chan.mFilter.z2 = 0.0f;
        chan.mCurrentGain = 0.0f;
    }
}

void AutowahState::update(const ContextBase *context, const EffectSlot *slot,
    const EffectProps *props_, const EffectTarget target)
{
    auto &props = std::get<AutowahProps>(*props_);
    const DeviceBase *device{context->mDevice};
    const auto frequency = static_cast<float>(device->Frequency);

    const float ReleaseTime{std::clamp(props.ReleaseTime, 0.001f, 1.0f)};

    mAttackRate    = std::exp(-1.0f / (props.AttackTime*frequency));
    mReleaseRate   = std::exp(-1.0f / (ReleaseTime*frequency));
    /* 0-20dB Resonance Peak gain */
    mResonanceGain = std::sqrt(std::log10(props.Resonance)*10.0f / 3.0f);
    mPeakGain      = 1.0f - std::log10(props.PeakGain / GainScale);
    mFreqMinNorm   = MinFreq / frequency;
    mBandwidthNorm = (MaxFreq-MinFreq) / frequency;

    mOutTarget = target.Main->Buffer;
    auto set_channel = [this](size_t idx, uint outchan, float outgain)
    {
        mChans[idx].mTargetChannel = outchan;
        mChans[idx].mTargetGain = outgain;
    };
    target.Main->setAmbiMixParams(slot->Wet, slot->Gain, set_channel);
}

void AutowahState::process(const size_t samplesToDo,
    const al::span<const FloatBufferLine> samplesIn, const al::span<FloatBufferLine> samplesOut)
{
    const float attack_rate{mAttackRate};
    const float release_rate{mReleaseRate};
    const float res_gain{mResonanceGain};
    const float peak_gain{mPeakGain};
    const float freq_min{mFreqMinNorm};
    const float bandwidth{mBandwidthNorm};

    float env_delay{mEnvDelay};
    for(size_t i{0u};i < samplesToDo;i++)
    {
        /* Envelope follower described on the book: Audio Effects, Theory,
         * Implementation and Application.
         */
        const float sample{peak_gain * std::fabs(samplesIn[0][i])};
        const float a{(sample > env_delay) ? attack_rate : release_rate};
        env_delay = lerpf(sample, env_delay, a);

        /* Calculate the cos and alpha components for this sample's filter. */
        const float w0{std::min(bandwidth*env_delay + freq_min, 0.46f) *
            (al::numbers::pi_v<float>*2.0f)};
        mEnv[i].cos_w0 = std::cos(w0);
        mEnv[i].alpha = std::sin(w0)/(2.0f * QFactor);
    }
    mEnvDelay = env_delay;

    auto chandata = mChans.begin();
    for(const auto &insamples : samplesIn)
    {
        const size_t outidx{chandata->mTargetChannel};
        if(outidx == InvalidChannelIndex)
        {
            ++chandata;
            continue;
        }

        /* This effectively inlines BiquadFilter_setParams for a peaking
         * filter and BiquadFilter_processC. The alpha and cosine components
         * for the filter coefficients were previously calculated with the
         * envelope. Because the filter changes for each sample, the
         * coefficients are transient and don't need to be held.
         */
        float z1{chandata->mFilter.z1};
        float z2{chandata->mFilter.z2};

        for(size_t i{0u};i < samplesToDo;i++)
        {
            const float alpha{mEnv[i].alpha};
            const float cos_w0{mEnv[i].cos_w0};

            const std::array b{
                1.0f + alpha*res_gain,
                -2.0f * cos_w0,
                1.0f - alpha*res_gain};
            const std::array a{
                1.0f + alpha/res_gain,
                -2.0f * cos_w0,
                1.0f - alpha/res_gain};

            const float input{insamples[i]};
            const float output{input*(b[0]/a[0]) + z1};
            z1 = input*(b[1]/a[0]) - output*(a[1]/a[0]) + z2;
            z2 = input*(b[2]/a[0]) - output*(a[2]/a[0]);
            mBufferOut[i] = output;
        }
        chandata->mFilter.z1 = z1;
        chandata->mFilter.z2 = z2;

        /* Now, mix the processed sound data to the output. */
        MixSamples(al::span{mBufferOut}.first(samplesToDo), samplesOut[outidx],
            chandata->mCurrentGain, chandata->mTargetGain, samplesToDo);
        ++chandata;
    }
}


struct AutowahStateFactory final : public EffectStateFactory {
    al::intrusive_ptr<EffectState> create() override
    { return al::intrusive_ptr<EffectState>{new AutowahState{}}; }
};

} // namespace

EffectStateFactory *AutowahStateFactory_getFactory()
{
    static AutowahStateFactory AutowahFactory{};
    return &AutowahFactory;
}
