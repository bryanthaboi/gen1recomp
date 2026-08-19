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
#include <complex>
#include <cstdlib>
#include <variant>

#include "alc/effects/base.h"
#include "alnumbers.h"
#include "alnumeric.h"
#include "alspan.h"
#include "core/ambidefs.h"
#include "core/bufferline.h"
#include "core/device.h"
#include "core/effects/base.h"
#include "core/effectslot.h"
#include "core/mixer.h"
#include "core/mixer/defs.h"
#include "intrusive_ptr.h"
#include "pffft.h"

struct BufferStorage;
struct ContextBase;


namespace {

using uint = unsigned int;
using complex_f = std::complex<float>;

constexpr size_t StftSize{1024};
constexpr size_t StftHalfSize{StftSize >> 1};
constexpr size_t OversampleFactor{8};

static_assert(StftSize%OversampleFactor == 0, "Factor must be a clean divisor of the size");
constexpr size_t StftStep{StftSize / OversampleFactor};

/* Define a Hann window, used to filter the STFT input and output. */
struct Windower {
    alignas(16) std::array<float,StftSize> mData{};

    Windower()
    {
        /* Create lookup table of the Hann window for the desired size. */
        for(size_t i{0};i < StftHalfSize;i++)
        {
            constexpr double scale{al::numbers::pi / double{StftSize}};
            const double val{std::sin((static_cast<double>(i)+0.5) * scale)};
            mData[i] = mData[StftSize-1-i] = static_cast<float>(val * val);
        }
    }
};
const Windower gWindow{};


struct FrequencyBin {
    float Magnitude;
    float FreqBin;
};


struct PshifterState final : public EffectState {
    /* Effect parameters */
    size_t mCount{};
    size_t mPos{};
    uint mPitchShiftI{};
    float mPitchShift{};

    /* Effects buffers */
    std::array<float,StftSize> mFIFO{};
    std::array<float,StftHalfSize+1> mLastPhase{};
    std::array<float,StftHalfSize+1> mSumPhase{};
    std::array<float,StftSize> mOutputAccum{};

    PFFFTSetup mFft;
    alignas(16) std::array<float,StftSize> mFftBuffer{};
    alignas(16) std::array<float,StftSize> mFftWorkBuffer{};

    std::array<FrequencyBin,StftHalfSize+1> mAnalysisBuffer{};
    std::array<FrequencyBin,StftHalfSize+1> mSynthesisBuffer{};

    alignas(16) FloatBufferLine mBufferOut{};

    /* Effect gains for each output channel */
    std::array<float,MaxAmbiChannels> mCurrentGains{};
    std::array<float,MaxAmbiChannels> mTargetGains{};


    void deviceUpdate(const DeviceBase *device, const BufferStorage *buffer) override;
    void update(const ContextBase *context, const EffectSlot *slot, const EffectProps *props,
        const EffectTarget target) override;
    void process(const size_t samplesToDo, const al::span<const FloatBufferLine> samplesIn,
        const al::span<FloatBufferLine> samplesOut) override;
};

void PshifterState::deviceUpdate(const DeviceBase*, const BufferStorage*)
{
    /* (Re-)initializing parameters and clear the buffers. */
    mCount       = 0;
    mPos         = StftSize - StftStep;
    mPitchShiftI = MixerFracOne;
    mPitchShift  = 1.0f;

    mFIFO.fill(0.0f);
    mLastPhase.fill(0.0f);
    mSumPhase.fill(0.0f);
    mOutputAccum.fill(0.0f);
    mFftBuffer.fill(0.0f);
    mAnalysisBuffer.fill(FrequencyBin{});
    mSynthesisBuffer.fill(FrequencyBin{});

    mCurrentGains.fill(0.0f);
    mTargetGains.fill(0.0f);

    if(!mFft)
        mFft = PFFFTSetup{StftSize, PFFFT_REAL};
}

void PshifterState::update(const ContextBase*, const EffectSlot *slot,
    const EffectProps *props_, const EffectTarget target)
{
    auto &props = std::get<PshifterProps>(*props_);
    const int tune{props.CoarseTune*100 + props.FineTune};
    const float pitch{std::pow(2.0f, static_cast<float>(tune) / 1200.0f)};
    mPitchShiftI = std::clamp(fastf2u(pitch*MixerFracOne), uint{MixerFracHalf},
        uint{MixerFracOne}*2u);
    mPitchShift  = static_cast<float>(mPitchShiftI) * float{1.0f/MixerFracOne};

    static constexpr auto coeffs = CalcDirectionCoeffs(std::array{0.0f, 0.0f, -1.0f});

    mOutTarget = target.Main->Buffer;
    ComputePanGains(target.Main, coeffs, slot->Gain, mTargetGains);
}

void PshifterState::process(const size_t samplesToDo,
    const al::span<const FloatBufferLine> samplesIn, const al::span<FloatBufferLine> samplesOut)
{
    /* Pitch shifter engine based on the work of Stephan Bernsee.
     * http://blogs.zynaptiq.com/bernsee/pitch-shifting-using-the-ft/
     */

    /* Cycle offset per update expected of each frequency bin (bin 0 is none,
     * bin 1 is x1, bin 2 is x2, etc).
     */
    constexpr float expected_cycles{al::numbers::pi_v<float>*2.0f / OversampleFactor};

    for(size_t base{0u};base < samplesToDo;)
    {
        const size_t todo{std::min(StftStep-mCount, samplesToDo-base)};

        /* Retrieve the output samples from the FIFO and fill in the new input
         * samples.
         */
        auto fifo_iter = mFIFO.begin()+mPos + mCount;
        std::copy_n(fifo_iter, todo, mBufferOut.begin()+base);

        std::copy_n(samplesIn[0].begin()+base, todo, fifo_iter);
        mCount += todo;
        base += todo;

        /* Check whether FIFO buffer is filled with new samples. */
        if(mCount < StftStep) break;
        mCount = 0;
        mPos = (mPos+StftStep) & (mFIFO.size()-1);

        /* Time-domain signal windowing, store in FftBuffer, and apply a
         * forward FFT to get the frequency-domain signal.
         */
        for(size_t src{mPos}, k{0u};src < StftSize;++src,++k)
            mFftBuffer[k] = mFIFO[src] * gWindow.mData[k];
        for(size_t src{0u}, k{StftSize-mPos};src < mPos;++src,++k)
            mFftBuffer[k] = mFIFO[src] * gWindow.mData[k];
        mFft.transform_ordered(mFftBuffer.data(), mFftBuffer.data(), mFftWorkBuffer.data(),
            PFFFT_FORWARD);

        /* Analyze the obtained data. Since the real FFT is symmetric, only
         * StftHalfSize+1 samples are needed.
         */
        for(size_t k{0u};k < StftHalfSize+1;++k)
        {
            const auto cplx = (k == 0) ? complex_f{mFftBuffer[0]} :
                (k == StftHalfSize) ? complex_f{mFftBuffer[1]} :
                complex_f{mFftBuffer[k*2], mFftBuffer[k*2 + 1]};
            const float magnitude{std::abs(cplx)};
            const float phase{std::arg(cplx)};

            /* Compute the phase difference from the last update and subtract
             * the expected phase difference for this bin.
             *
             * When oversampling, the expected per-update offset increments by
             * 1/OversampleFactor for every frequency bin. So, the offset wraps
             * every 'OversampleFactor' bin.
             */
            const auto bin_offset = static_cast<float>(k % OversampleFactor);
            float tmp{(phase - mLastPhase[k]) - bin_offset*expected_cycles};
            /* Store the actual phase for the next update. */
            mLastPhase[k] = phase;

            /* Normalize from pi, and wrap the delta between -1 and +1. */
            tmp *= al::numbers::inv_pi_v<float>;
            int qpd{float2int(tmp)};
            tmp -= static_cast<float>(qpd + (qpd%2));

            /* Get deviation from bin frequency (-0.5 to +0.5), and account for
             * oversampling.
             */
            tmp *= 0.5f * OversampleFactor;

            /* Compute the k-th partials' frequency bin target and store the
             * magnitude and frequency bin in the analysis buffer. We don't
             * need the "true frequency" since it's a linear relationship with
             * the bin.
             */
            mAnalysisBuffer[k].Magnitude = magnitude;
            mAnalysisBuffer[k].FreqBin = static_cast<float>(k) + tmp;
        }

        /* Shift the frequency bins according to the pitch adjustment,
         * accumulating the magnitudes of overlapping frequency bins.
         */
        std::fill(mSynthesisBuffer.begin(), mSynthesisBuffer.end(), FrequencyBin{});

        static constexpr size_t bin_limit{((StftHalfSize+1)<<MixerFracBits) - MixerFracHalf - 1};
        const size_t bin_count{std::min(StftHalfSize+1, bin_limit/mPitchShiftI + 1)};
        for(size_t k{0u};k < bin_count;k++)
        {
            const size_t j{(k*mPitchShiftI + MixerFracHalf) >> MixerFracBits};

            /* If more than two bins end up together, use the target frequency
             * bin for the one with the dominant magnitude. There might be a
             * better way to handle this, but it's better than last-index-wins.
             */
            if(mAnalysisBuffer[k].Magnitude > mSynthesisBuffer[j].Magnitude)
                mSynthesisBuffer[j].FreqBin = mAnalysisBuffer[k].FreqBin * mPitchShift;
            mSynthesisBuffer[j].Magnitude += mAnalysisBuffer[k].Magnitude;
        }

        /* Reconstruct the frequency-domain signal from the adjusted frequency
         * bins.
         */
        for(size_t k{0u};k < StftHalfSize+1;k++)
        {
            /* Calculate the actual delta phase for this bin's target frequency
             * bin, and accumulate it to get the actual bin phase.
             */
            float tmp{mSumPhase[k] + mSynthesisBuffer[k].FreqBin*expected_cycles};

            /* Wrap between -pi and +pi for the sum. If mSumPhase is left to
             * grow indefinitely, it will lose precision and produce less exact
             * phase over time.
             */
            tmp *= al::numbers::inv_pi_v<float>;
            int qpd{float2int(tmp)};
            tmp -= static_cast<float>(qpd + (qpd%2));
            mSumPhase[k] = tmp * al::numbers::pi_v<float>;

            const complex_f cplx{std::polar(mSynthesisBuffer[k].Magnitude, mSumPhase[k])};
            if(k == 0)
                mFftBuffer[0] = cplx.real();
            else if(k == StftHalfSize)
                mFftBuffer[1] = cplx.real();
            else
            {
                mFftBuffer[k*2 + 0] = cplx.real();
                mFftBuffer[k*2 + 1] = cplx.imag();
            }
        }

        /* Apply an inverse FFT to get the time-domain signal, and accumulate
         * for the output with windowing.
         */
        mFft.transform_ordered(mFftBuffer.data(), mFftBuffer.data(), mFftWorkBuffer.data(),
            PFFFT_BACKWARD);

        static constexpr float scale{3.0f / OversampleFactor / StftSize};
        for(size_t dst{mPos}, k{0u};dst < StftSize;++dst,++k)
            mOutputAccum[dst] += gWindow.mData[k]*mFftBuffer[k] * scale;
        for(size_t dst{0u}, k{StftSize-mPos};dst < mPos;++dst,++k)
            mOutputAccum[dst] += gWindow.mData[k]*mFftBuffer[k] * scale;

        /* Copy out the accumulated result, then clear for the next iteration. */
        std::copy_n(mOutputAccum.begin() + mPos, StftStep, mFIFO.begin() + mPos);
        std::fill_n(mOutputAccum.begin() + mPos, StftStep, 0.0f);
    }

    /* Now, mix the processed sound data to the output. */
    MixSamples(al::span{mBufferOut}.first(samplesToDo), samplesOut, mCurrentGains, mTargetGains,
        std::max(samplesToDo, 512_uz), 0);
}


struct PshifterStateFactory final : public EffectStateFactory {
    al::intrusive_ptr<EffectState> create() override
    { return al::intrusive_ptr<EffectState>{new PshifterState{}}; }
};

} // namespace

EffectStateFactory *PshifterStateFactory_getFactory()
{
    static PshifterStateFactory PshifterFactory{};
    return &PshifterFactory;
}
