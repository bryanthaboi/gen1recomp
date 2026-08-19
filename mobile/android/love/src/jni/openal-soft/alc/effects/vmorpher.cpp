/**
 * This file is part of the OpenAL Soft cross platform audio library
 *
 * Copyright (C) 2019 by Anis A. Hireche
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
#include <functional>
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

using uint = unsigned int;

constexpr size_t MaxUpdateSamples{256};
constexpr size_t NumFormants{4};
constexpr float RcpQFactor{1.0f / 5.0f};
enum : size_t {
    VowelAIndex,
    VowelBIndex,
    NumFilters
};

constexpr size_t WaveformFracBits{24};
constexpr size_t WaveformFracOne{1<<WaveformFracBits};
constexpr size_t WaveformFracMask{WaveformFracOne-1};

inline float Sin(uint index)
{
    constexpr float scale{al::numbers::pi_v<float>*2.0f / float{WaveformFracOne}};
    return std::sin(static_cast<float>(index) * scale)*0.5f + 0.5f;
}

inline float Saw(uint index)
{ return static_cast<float>(index) / float{WaveformFracOne}; }

inline float Triangle(uint index)
{ return std::fabs(static_cast<float>(index)*(2.0f/WaveformFracOne) - 1.0f); }

inline float Half(uint) { return 0.5f; }

template<float (&func)(uint)>
void Oscillate(const al::span<float> dst, uint index, const uint step)
{
    std::generate(dst.begin(), dst.end(), [&index,step]
    {
        index += step;
        index &= WaveformFracMask;
        return func(index);
    });
}

struct FormantFilter {
    float mCoeff{0.0f};
    float mGain{1.0f};
    float mS1{0.0f};
    float mS2{0.0f};

    FormantFilter() = default;
    FormantFilter(float f0norm, float gain)
      : mCoeff{std::tan(al::numbers::pi_v<float> * f0norm)}, mGain{gain}
    { }

    void process(const float *samplesIn, float *samplesOut, const size_t numInput) noexcept
    {
        /* A state variable filter from a topology-preserving transform.
         * Based on a talk given by Ivan Cohen: https://www.youtube.com/watch?v=esjHXGPyrhg
         */
        const float g{mCoeff};
        const float gain{mGain};
        const float h{1.0f / (1.0f + (g*RcpQFactor) + (g*g))};
        const float coeff{RcpQFactor + g};
        float s1{mS1};
        float s2{mS2};

        const auto input = al::span{samplesIn, numInput};
        const auto output = al::span{samplesOut, numInput};
        std::transform(input.cbegin(), input.cend(), output.cbegin(), output.begin(),
            [g,gain,h,coeff,&s1,&s2](const float in, const float out) noexcept -> float
            {
                const float H{(in - coeff*s1 - s2)*h};
                const float B{g*H + s1};
                const float L{g*B + s2};

                s1 = g*H + B;
                s2 = g*B + L;

                // Apply peak and accumulate samples.
                return out + B*gain;
            });
        mS1 = s1;
        mS2 = s2;
    }

    void clear() noexcept
    {
        mS1 = 0.0f;
        mS2 = 0.0f;
    }
};


struct VmorpherState final : public EffectState {
    struct OutParams {
        uint mTargetChannel{InvalidChannelIndex};

        /* Effect parameters */
        std::array<std::array<FormantFilter,NumFormants>,NumFilters> mFormants;

        /* Effect gains for each channel */
        float mCurrentGain{};
        float mTargetGain{};
    };
    std::array<OutParams,MaxAmbiChannels> mChans;

    void (*mGetSamples)(const al::span<float> dst, uint index, const uint step){};

    uint mIndex{0};
    uint mStep{1};

    /* Effects buffers */
    alignas(16) std::array<float,MaxUpdateSamples> mSampleBufferA{};
    alignas(16) std::array<float,MaxUpdateSamples> mSampleBufferB{};
    alignas(16) std::array<float,MaxUpdateSamples> mLfo{};

    void deviceUpdate(const DeviceBase *device, const BufferStorage *buffer) override;
    void update(const ContextBase *context, const EffectSlot *slot, const EffectProps *props,
        const EffectTarget target) override;
    void process(const size_t samplesToDo, const al::span<const FloatBufferLine> samplesIn,
        const al::span<FloatBufferLine> samplesOut) override;

    static std::array<FormantFilter,NumFormants> getFiltersByPhoneme(VMorpherPhenome phoneme,
        float frequency, float pitch) noexcept;
};

std::array<FormantFilter,NumFormants> VmorpherState::getFiltersByPhoneme(VMorpherPhenome phoneme,
    float frequency, float pitch) noexcept
{
    /* Using soprano formant set of values to
     * better match mid-range frequency space.
     *
     * See: https://www.classes.cs.uchicago.edu/archive/1999/spring/CS295/Computing_Resources/Csound/CsManual3.48b1.HTML/Appendices/table3.html
     */
    switch(phoneme)
    {
    case VMorpherPhenome::A:
        return {{
            {( 800 * pitch) / frequency, 1.000000f}, /* std::pow(10.0f,   0 / 20.0f); */
            {(1150 * pitch) / frequency, 0.501187f}, /* std::pow(10.0f,  -6 / 20.0f); */
            {(2900 * pitch) / frequency, 0.025118f}, /* std::pow(10.0f, -32 / 20.0f); */
            {(3900 * pitch) / frequency, 0.100000f}  /* std::pow(10.0f, -20 / 20.0f); */
        }};
    case VMorpherPhenome::E:
        return {{
            {( 350 * pitch) / frequency, 1.000000f}, /* std::pow(10.0f,   0 / 20.0f); */
            {(2000 * pitch) / frequency, 0.100000f}, /* std::pow(10.0f, -20 / 20.0f); */
            {(2800 * pitch) / frequency, 0.177827f}, /* std::pow(10.0f, -15 / 20.0f); */
            {(3600 * pitch) / frequency, 0.009999f}  /* std::pow(10.0f, -40 / 20.0f); */
        }};
    case VMorpherPhenome::I:
        return {{
            {( 270 * pitch) / frequency, 1.000000f}, /* std::pow(10.0f,   0 / 20.0f); */
            {(2140 * pitch) / frequency, 0.251188f}, /* std::pow(10.0f, -12 / 20.0f); */
            {(2950 * pitch) / frequency, 0.050118f}, /* std::pow(10.0f, -26 / 20.0f); */
            {(3900 * pitch) / frequency, 0.050118f}  /* std::pow(10.0f, -26 / 20.0f); */
        }};
    case VMorpherPhenome::O:
        return {{
            {( 450 * pitch) / frequency, 1.000000f}, /* std::pow(10.0f,   0 / 20.0f); */
            {( 800 * pitch) / frequency, 0.281838f}, /* std::pow(10.0f, -11 / 20.0f); */
            {(2830 * pitch) / frequency, 0.079432f}, /* std::pow(10.0f, -22 / 20.0f); */
            {(3800 * pitch) / frequency, 0.079432f}  /* std::pow(10.0f, -22 / 20.0f); */
        }};
    case VMorpherPhenome::U:
        return {{
            {( 325 * pitch) / frequency, 1.000000f}, /* std::pow(10.0f,   0 / 20.0f); */
            {( 700 * pitch) / frequency, 0.158489f}, /* std::pow(10.0f, -16 / 20.0f); */
            {(2700 * pitch) / frequency, 0.017782f}, /* std::pow(10.0f, -35 / 20.0f); */
            {(3800 * pitch) / frequency, 0.009999f}  /* std::pow(10.0f, -40 / 20.0f); */
        }};
    default:
        break;
    }
    return {};
}


void VmorpherState::deviceUpdate(const DeviceBase*, const BufferStorage*)
{
    for(auto &e : mChans)
    {
        e.mTargetChannel = InvalidChannelIndex;
        std::for_each(e.mFormants[VowelAIndex].begin(), e.mFormants[VowelAIndex].end(),
            std::mem_fn(&FormantFilter::clear));
        std::for_each(e.mFormants[VowelBIndex].begin(), e.mFormants[VowelBIndex].end(),
            std::mem_fn(&FormantFilter::clear));
        e.mCurrentGain = 0.0f;
    }
}

void VmorpherState::update(const ContextBase *context, const EffectSlot *slot,
    const EffectProps *props_, const EffectTarget target)
{
    auto &props = std::get<VmorpherProps>(*props_);
    const DeviceBase *device{context->mDevice};
    const float frequency{static_cast<float>(device->Frequency)};
    const float step{props.Rate / frequency};
    mStep = fastf2u(std::clamp(step*WaveformFracOne, 0.0f, WaveformFracOne-1.0f));

    if(mStep == 0)
        mGetSamples = Oscillate<Half>;
    else if(props.Waveform == VMorpherWaveform::Sinusoid)
        mGetSamples = Oscillate<Sin>;
    else if(props.Waveform == VMorpherWaveform::Triangle)
        mGetSamples = Oscillate<Triangle>;
    else /*if(props.Waveform == VMorpherWaveform::Sawtooth)*/
        mGetSamples = Oscillate<Saw>;

    const float pitchA{std::pow(2.0f, static_cast<float>(props.PhonemeACoarseTuning) / 12.0f)};
    const float pitchB{std::pow(2.0f, static_cast<float>(props.PhonemeBCoarseTuning) / 12.0f)};

    auto vowelA = getFiltersByPhoneme(props.PhonemeA, frequency, pitchA);
    auto vowelB = getFiltersByPhoneme(props.PhonemeB, frequency, pitchB);

    /* Copy the filter coefficients to the input channels. */
    for(size_t i{0u};i < slot->Wet.Buffer.size();++i)
    {
        std::copy(vowelA.begin(), vowelA.end(), mChans[i].mFormants[VowelAIndex].begin());
        std::copy(vowelB.begin(), vowelB.end(), mChans[i].mFormants[VowelBIndex].begin());
    }

    mOutTarget = target.Main->Buffer;
    auto set_channel = [this](size_t idx, uint outchan, float outgain)
    {
        mChans[idx].mTargetChannel = outchan;
        mChans[idx].mTargetGain = outgain;
    };
    target.Main->setAmbiMixParams(slot->Wet, slot->Gain, set_channel);
}

void VmorpherState::process(const size_t samplesToDo, const al::span<const FloatBufferLine> samplesIn, const al::span<FloatBufferLine> samplesOut)
{
    alignas(16) std::array<float,MaxUpdateSamples> blended{};

    /* Following the EFX specification for a conformant implementation which describes
     * the effect as a pair of 4-band formant filters blended together using an LFO.
     */
    for(size_t base{0u};base < samplesToDo;)
    {
        const size_t td{std::min(MaxUpdateSamples, samplesToDo-base)};

        mGetSamples(al::span{mLfo}.first(td), mIndex, mStep);
        mIndex += static_cast<uint>(mStep * td);
        mIndex &= WaveformFracMask;

        auto chandata = mChans.begin();
        for(const auto &input : samplesIn)
        {
            const size_t outidx{chandata->mTargetChannel};
            if(outidx == InvalidChannelIndex)
            {
                ++chandata;
                continue;
            }

            const auto vowelA = al::span{chandata->mFormants[VowelAIndex]};
            const auto vowelB = al::span{chandata->mFormants[VowelBIndex]};

            /* Process first vowel. */
            std::fill_n(mSampleBufferA.begin(), td, 0.0f);
            vowelA[0].process(&input[base], mSampleBufferA.data(), td);
            vowelA[1].process(&input[base], mSampleBufferA.data(), td);
            vowelA[2].process(&input[base], mSampleBufferA.data(), td);
            vowelA[3].process(&input[base], mSampleBufferA.data(), td);

            /* Process second vowel. */
            std::fill_n(mSampleBufferB.begin(), td, 0.0f);
            vowelB[0].process(&input[base], mSampleBufferB.data(), td);
            vowelB[1].process(&input[base], mSampleBufferB.data(), td);
            vowelB[2].process(&input[base], mSampleBufferB.data(), td);
            vowelB[3].process(&input[base], mSampleBufferB.data(), td);

            for(size_t i{0u};i < td;i++)
                blended[i] = lerpf(mSampleBufferA[i], mSampleBufferB[i], mLfo[i]);

            /* Now, mix the processed sound data to the output. */
            MixSamples(al::span{blended}.first(td), al::span{samplesOut[outidx]}.subspan(base),
                chandata->mCurrentGain, chandata->mTargetGain, samplesToDo-base);
            ++chandata;
        }

        base += td;
    }
}


struct VmorpherStateFactory final : public EffectStateFactory {
    al::intrusive_ptr<EffectState> create() override
    { return al::intrusive_ptr<EffectState>{new VmorpherState{}}; }
};

} // namespace

EffectStateFactory *VmorpherStateFactory_getFactory()
{
    static VmorpherStateFactory VmorpherFactory{};
    return &VmorpherFactory;
}
