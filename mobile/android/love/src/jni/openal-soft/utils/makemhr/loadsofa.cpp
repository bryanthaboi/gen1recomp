/*
 * HRTF utility for producing and demonstrating the process of creating an
 * OpenAL Soft compatible HRIR data set.
 *
 * Copyright (C) 2018-2019  Christopher Fitzgerald
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Or visit:  http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 */

#include "loadsofa.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <functional>
#include <future>
#include <iterator>
#include <memory>
#include <numeric>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "alspan.h"
#include "alstring.h"
#include "alnumeric.h"
#include "makemhr.h"
#include "polyphase_resampler.h"
#include "sofa-support.h"

#include "mysofa.h"


namespace {

using namespace std::string_view_literals;
using uint = unsigned int;

/* Attempts to produce a compatible layout.  Most data sets tend to be
 * uniform and have the same major axis as used by OpenAL Soft's HRTF model.
 * This will remove outliers and produce a maximally dense layout when
 * possible.  Those sets that contain purely random measurements or use
 * different major axes will fail.
 */
auto PrepareLayout(const al::span<const float> xyzs, HrirDataT *hData) -> bool
{
    fputs("Detecting compatible layout...\n", stdout);

    auto fds = GetCompatibleLayout(xyzs);
    if(fds.size() > MAX_FD_COUNT)
    {
        fputs("Incompatible layout (inumerable radii).\n", stdout);
        return false;
    }

    std::array<double,MAX_FD_COUNT> distances{};
    std::array<uint,MAX_FD_COUNT> evCounts{};
    auto azCounts = std::vector<std::array<uint,MAX_EV_COUNT>>(MAX_FD_COUNT);
    for(auto &azs : azCounts) azs.fill(0u);

    uint fi{0u}, ir_total{0u};
    for(const auto &field : fds)
    {
        distances[fi] = field.mDistance;
        evCounts[fi] = field.mEvCount;

        for(uint ei{0u};ei < field.mEvStart;ei++)
            azCounts[fi][ei] = field.mAzCounts[field.mEvCount-ei-1];
        for(uint ei{field.mEvStart};ei < field.mEvCount;ei++)
        {
            azCounts[fi][ei] = field.mAzCounts[ei];
            ir_total += field.mAzCounts[ei];
        }

        ++fi;
    }
    printf("Using %u of %zu IRs.\n", ir_total, xyzs.size()/3);
    const auto azs = al::span{azCounts}.first<MAX_FD_COUNT>();
    return PrepareHrirData(al::span{distances}.first(fi), evCounts, azs, hData);
}

float GetSampleRate(MYSOFA_HRTF *sofaHrtf)
{
    const char *srate_dim{nullptr};
    const char *srate_units{nullptr};
    MYSOFA_ARRAY *srate_array{&sofaHrtf->DataSamplingRate};
    MYSOFA_ATTRIBUTE *srate_attrs{srate_array->attributes};
    while(srate_attrs)
    {
        if("DIMENSION_LIST"sv == srate_attrs->name)
        {
            if(srate_dim)
            {
                fprintf(stderr, "Duplicate SampleRate.DIMENSION_LIST\n");
                return 0.0f;
            }
            srate_dim = srate_attrs->value;
        }
        else if("Units"sv == srate_attrs->name)
        {
            if(srate_units)
            {
                fprintf(stderr, "Duplicate SampleRate.Units\n");
                return 0.0f;
            }
            srate_units = srate_attrs->value;
        }
        else
            fprintf(stderr, "Unexpected sample rate attribute: %s = %s\n", srate_attrs->name,
                srate_attrs->value);
        srate_attrs = srate_attrs->next;
    }
    if(!srate_dim)
    {
        fprintf(stderr, "Missing sample rate dimensions\n");
        return 0.0f;
    }
    if(srate_dim != "I"sv)
    {
        fprintf(stderr, "Unsupported sample rate dimensions: %s\n", srate_dim);
        return 0.0f;
    }
    if(!srate_units)
    {
        fprintf(stderr, "Missing sample rate unit type\n");
        return 0.0f;
    }
    if(srate_units != "hertz"sv)
    {
        fprintf(stderr, "Unsupported sample rate unit type: %s\n", srate_units);
        return 0.0f;
    }
    /* I dimensions guarantees 1 element, so just extract it. */
    const auto values = al::span{srate_array->values, sofaHrtf->I};
    if(values[0] < float{MIN_RATE} || values[0] > float{MAX_RATE})
    {
        fprintf(stderr, "Sample rate out of range: %f (expected %u to %u)", values[0], MIN_RATE,
            MAX_RATE);
        return 0.0f;
    }
    return values[0];
}

enum class DelayType : uint8_t {
    None,
    I_R, /* [1][Channels] */
    M_R, /* [HRIRs][Channels] */
};
auto PrepareDelay(MYSOFA_HRTF *sofaHrtf) -> std::optional<DelayType>
{
    const char *delay_dim{nullptr};
    MYSOFA_ARRAY *delay_array{&sofaHrtf->DataDelay};
    MYSOFA_ATTRIBUTE *delay_attrs{delay_array->attributes};
    while(delay_attrs)
    {
        if("DIMENSION_LIST"sv == delay_attrs->name)
        {
            if(delay_dim)
            {
                fprintf(stderr, "Duplicate Delay.DIMENSION_LIST\n");
                return std::nullopt;
            }
            delay_dim = delay_attrs->value;
        }
        else
            fprintf(stderr, "Unexpected delay attribute: %s = %s\n", delay_attrs->name,
                delay_attrs->value ? delay_attrs->value : "<null>");
        delay_attrs = delay_attrs->next;
    }
    if(!delay_dim)
    {
        fprintf(stderr, "Missing delay dimensions\n");
        return DelayType::None;
    }
    if(delay_dim == "I,R"sv)
        return DelayType::I_R;
    if(delay_dim == "M,R"sv)
        return DelayType::M_R;

    fprintf(stderr, "Unsupported delay dimensions: %s\n", delay_dim);
    return std::nullopt;
}

bool CheckIrData(MYSOFA_HRTF *sofaHrtf)
{
    const char *ir_dim{nullptr};
    MYSOFA_ARRAY *ir_array{&sofaHrtf->DataIR};
    MYSOFA_ATTRIBUTE *ir_attrs{ir_array->attributes};
    while(ir_attrs)
    {
        if("DIMENSION_LIST"sv == ir_attrs->name)
        {
            if(ir_dim)
            {
                fprintf(stderr, "Duplicate IR.DIMENSION_LIST\n");
                return false;
            }
            ir_dim = ir_attrs->value;
        }
        else
            fprintf(stderr, "Unexpected IR attribute: %s = %s\n", ir_attrs->name,
                ir_attrs->value ? ir_attrs->value : "<null>");
        ir_attrs = ir_attrs->next;
    }
    if(!ir_dim)
    {
        fprintf(stderr, "Missing IR dimensions\n");
        return false;
    }
    if(ir_dim != "M,R,N"sv)
    {
        fprintf(stderr, "Unsupported IR dimensions: %s\n", ir_dim);
        return false;
    }
    return true;
}


/* Calculate the onset time of a HRIR. */
constexpr int OnsetRateMultiple{10};
auto CalcHrirOnset(PPhaseResampler &rs, const uint rate, al::span<double> upsampled,
    const al::span<const double> hrir) -> double
{
    rs.process(hrir, upsampled);

    auto abs_lt = [](const double lhs, const double rhs) -> bool
    { return std::abs(lhs) < std::abs(rhs); };
    auto iter = std::max_element(upsampled.cbegin(), upsampled.cend(), abs_lt);
    return static_cast<double>(std::distance(upsampled.cbegin(), iter)) /
        (double{OnsetRateMultiple}*rate);
}

/* Calculate the magnitude response of a HRIR. */
void CalcHrirMagnitude(const uint points, al::span<complex_d> h, const al::span<double> hrir)
{
    auto iter = std::copy_n(hrir.cbegin(), points, h.begin());
    std::fill(iter, h.end(), complex_d{0.0, 0.0});

    forward_fft(h);
    MagnitudeResponse(h, hrir.first((h.size()/2) + 1));
}

bool LoadResponses(MYSOFA_HRTF *sofaHrtf, HrirDataT *hData, const DelayType delayType,
    const uint outRate)
{
    std::atomic<uint> loaded_count{0u};

    auto load_proc = [sofaHrtf,hData,delayType,outRate,&loaded_count]() -> bool
    {
        const uint channels{(hData->mChannelType == CT_STEREO) ? 2u : 1u};
        hData->mHrirsBase.resize(channels * size_t{hData->mIrCount} * hData->mIrSize, 0.0);
        const auto hrirs = al::span{hData->mHrirsBase};

        std::vector<double> restmp;
        std::optional<PPhaseResampler> resampler;
        if(outRate && outRate != hData->mIrRate)
        {
            resampler.emplace().init(hData->mIrRate, outRate);
            restmp.resize(sofaHrtf->N);
        }

        const auto srcPosValues = al::span{sofaHrtf->SourcePosition.values, sofaHrtf->M*3_uz};
        const auto irValues = al::span{sofaHrtf->DataIR.values,
            size_t{sofaHrtf->M}*sofaHrtf->R*sofaHrtf->N};
        for(uint si{0u};si < sofaHrtf->M;++si)
        {
            loaded_count.fetch_add(1u);

            std::array aer{srcPosValues[3_uz*si], srcPosValues[3_uz*si + 1],
                srcPosValues[3_uz*si + 2]};
            mysofa_c2s(aer.data());

            if(std::abs(aer[1]) >= 89.999f)
                aer[0] = 0.0f;
            else
                aer[0] = std::fmod(360.0f - aer[0], 360.0f);

            auto field = std::find_if(hData->mFds.cbegin(), hData->mFds.cend(),
                [&aer](const HrirFdT &fld) -> bool
                { return (std::abs(aer[2] - fld.mDistance) < 0.001); });
            if(field == hData->mFds.cend())
                continue;

            const double evscale{180.0 / static_cast<double>(field->mEvs.size()-1)};
            double ef{(90.0 + aer[1]) / evscale};
            auto ei = static_cast<uint>(std::round(ef));
            ef = (ef - ei) * evscale;
            if(std::abs(ef) >= 0.1) continue;

            const double azscale{360.0 / static_cast<double>(field->mEvs[ei].mAzs.size())};
            double af{aer[0] / azscale};
            auto ai = static_cast<uint>(std::round(af));
            af = (af-ai) * azscale;
            ai %= static_cast<uint>(field->mEvs[ei].mAzs.size());
            if(std::abs(af) >= 0.1) continue;

            HrirAzT &azd = field->mEvs[ei].mAzs[ai];
            if(!azd.mIrs[0].empty())
            {
                fprintf(stderr, "\nMultiple measurements near [ a=%f, e=%f, r=%f ].\n",
                    aer[0], aer[1], aer[2]);
                return false;
            }

            for(uint ti{0u};ti < channels;++ti)
            {
                azd.mIrs[ti] = hrirs.subspan(
                    (size_t{hData->mIrCount}*ti + azd.mIndex) * hData->mIrSize, hData->mIrSize);
                const auto ir = irValues.subspan((size_t{si}*sofaHrtf->R + ti)*sofaHrtf->N,
                    sofaHrtf->N);
                if(!resampler)
                    std::copy_n(ir.cbegin(), ir.size(), azd.mIrs[ti].begin());
                else
                {
                    std::copy_n(ir.cbegin(), ir.size(), restmp.begin());
                    resampler->process(restmp, azd.mIrs[ti]);
                }
            }

            /* Include any per-channel or per-HRIR delays. */
            if(delayType == DelayType::I_R)
            {
                const auto delayValues = al::span{sofaHrtf->DataDelay.values,
                    size_t{sofaHrtf->I}*sofaHrtf->R};
                for(uint ti{0u};ti < channels;++ti)
                    azd.mDelays[ti] = delayValues[ti] / static_cast<float>(hData->mIrRate);
            }
            else if(delayType == DelayType::M_R)
            {
                const auto delayValues = al::span{sofaHrtf->DataDelay.values,
                    size_t{sofaHrtf->M}*sofaHrtf->R};
                for(uint ti{0u};ti < channels;++ti)
                    azd.mDelays[ti] = delayValues[si*sofaHrtf->R + ti] /
                        static_cast<float>(hData->mIrRate);
            }
        }

        if(outRate && outRate != hData->mIrRate)
        {
            const double scale{static_cast<double>(outRate) / hData->mIrRate};
            hData->mIrRate = outRate;
            hData->mIrPoints = std::min(static_cast<uint>(std::ceil(hData->mIrPoints*scale)),
                hData->mIrSize);
        }
        return true;
    };

    std::future_status load_status{};
    auto load_future = std::async(std::launch::async, load_proc);
    do {
        load_status = load_future.wait_for(std::chrono::milliseconds{50});
        printf("\rLoading HRIRs... %u of %u", loaded_count.load(), sofaHrtf->M);
        fflush(stdout);
    } while(load_status != std::future_status::ready);
    fputc('\n', stdout);
    return load_future.get();
}


/* Calculates the frequency magnitudes of the HRIR set. Work is delegated to
 * this struct, which runs asynchronously on one or more threads (sharing the
 * same calculator object).
 */
struct MagCalculator {
    const uint mFftSize{};
    const uint mIrPoints{};
    std::vector<al::span<double>> mIrs{};
    std::atomic<size_t> mCurrent{};
    std::atomic<size_t> mDone{};

    void Worker()
    {
        auto htemp = std::vector<complex_d>(mFftSize);

        while(true)
        {
            /* Load the current index to process. */
            size_t idx{mCurrent.load()};
            do {
                /* If the index is at the end, we're done. */
                if(idx >= mIrs.size())
                    return;
                /* Otherwise, increment the current index atomically so other
                 * threads know to go to the next one. If this call fails, the
                 * current index was just changed by another thread and the new
                 * value is loaded into idx, which we'll recheck.
                 */
            } while(!mCurrent.compare_exchange_weak(idx, idx+1, std::memory_order_relaxed));

            CalcHrirMagnitude(mIrPoints, htemp, mIrs[idx]);

            /* Increment the number of IRs done. */
            mDone.fetch_add(1);
        }
    }
};

} // namespace

bool LoadSofaFile(const std::string_view filename, const uint numThreads, const uint fftSize,
    const uint truncSize, const uint outRate, const ChannelModeT chanMode, HrirDataT *hData)
{
    int err;
    MySofaHrtfPtr sofaHrtf{mysofa_load(std::string{filename}.c_str(), &err)};
    if(!sofaHrtf)
    {
        printf("Error: Could not load %.*s: %s (%d)\n", al::sizei(filename), filename.data(),
            SofaErrorStr(err), err);
        return false;
    }

    /* NOTE: Some valid SOFA files are failing this check. */
    err = mysofa_check(sofaHrtf.get());
    if(err != MYSOFA_OK)
        fprintf(stderr, "Warning: Supposedly malformed source file '%.*s': %s (%d)\n",
            al::sizei(filename), filename.data(), SofaErrorStr(err), err);

    mysofa_tocartesian(sofaHrtf.get());

    /* Make sure emitter and receiver counts are sane. */
    if(sofaHrtf->E != 1)
    {
        fprintf(stderr, "%u emitters not supported\n", sofaHrtf->E);
        return false;
    }
    if(sofaHrtf->R > 2 || sofaHrtf->R < 1)
    {
        fprintf(stderr, "%u receivers not supported\n", sofaHrtf->R);
        return false;
    }
    /* Assume R=2 is a stereo measurement, and R=1 is mono left-ear-only. */
    if(sofaHrtf->R == 2 && chanMode == CM_AllowStereo)
        hData->mChannelType = CT_STEREO;
    else
        hData->mChannelType = CT_MONO;

    /* Check and set the FFT and IR size. */
    if(sofaHrtf->N > fftSize)
    {
        fprintf(stderr, "Sample points exceeds the FFT size.\n");
        return false;
    }
    if(sofaHrtf->N < truncSize)
    {
        fprintf(stderr, "Sample points is below the truncation size.\n");
        return false;
    }
    hData->mIrPoints = sofaHrtf->N;
    hData->mFftSize = fftSize;
    hData->mIrSize = std::max(1u + (fftSize/2u), sofaHrtf->N);

    /* Assume a default head radius of 9cm. */
    hData->mRadius = 0.09;

    hData->mIrRate = static_cast<uint>(std::lround(GetSampleRate(sofaHrtf.get())));
    if(!hData->mIrRate)
        return false;

    const auto delayType = PrepareDelay(sofaHrtf.get());
    if(!delayType)
        return false;

    if(!CheckIrData(sofaHrtf.get()))
        return false;
    if(!PrepareLayout(al::span{sofaHrtf->SourcePosition.values, sofaHrtf->M*3_uz}, hData))
        return false;
    if(!LoadResponses(sofaHrtf.get(), hData, *delayType, outRate))
        return false;
    sofaHrtf = nullptr;

    for(uint fi{0u};fi < hData->mFds.size();fi++)
    {
        uint ei{0u};
        for(;ei < hData->mFds[fi].mEvs.size();ei++)
        {
            uint ai{0u};
            for(;ai < hData->mFds[fi].mEvs[ei].mAzs.size();ai++)
            {
                HrirAzT &azd = hData->mFds[fi].mEvs[ei].mAzs[ai];
                if(!azd.mIrs[0].empty()) break;
            }
            if(ai < hData->mFds[fi].mEvs[ei].mAzs.size())
                break;
        }
        if(ei >= hData->mFds[fi].mEvs.size())
        {
            fprintf(stderr, "Missing source references [ %d, *, * ].\n", fi);
            return false;
        }
        hData->mFds[fi].mEvStart = ei;
        for(;ei < hData->mFds[fi].mEvs.size();ei++)
        {
            for(uint ai{0u};ai < hData->mFds[fi].mEvs[ei].mAzs.size();ai++)
            {
                HrirAzT &azd = hData->mFds[fi].mEvs[ei].mAzs[ai];
                if(azd.mIrs[0].empty())
                {
                    fprintf(stderr, "Missing source reference [ %d, %d, %d ].\n", fi, ei, ai);
                    return false;
                }
            }
        }
    }


    size_t hrir_total{0};
    const uint channels{(hData->mChannelType == CT_STEREO) ? 2u : 1u};
    const auto hrirs = al::span{hData->mHrirsBase};
    for(uint fi{0u};fi < hData->mFds.size();fi++)
    {
        for(uint ei{0u};ei < hData->mFds[fi].mEvStart;ei++)
        {
            for(uint ai{0u};ai < hData->mFds[fi].mEvs[ei].mAzs.size();ai++)
            {
                HrirAzT &azd = hData->mFds[fi].mEvs[ei].mAzs[ai];
                for(size_t ti{0u};ti < channels;ti++)
                    azd.mIrs[ti] = hrirs.subspan((hData->mIrCount*ti + azd.mIndex)*hData->mIrSize,
                        hData->mIrSize);
            }
        }

        for(uint ei{hData->mFds[fi].mEvStart};ei < hData->mFds[fi].mEvs.size();ei++)
            hrir_total += hData->mFds[fi].mEvs[ei].mAzs.size() * channels;
    }

    std::atomic<size_t> hrir_done{0};
    auto onset_proc = [hData,channels,&hrir_done]() -> bool
    {
        /* Temporary buffer used to calculate the IR's onset. */
        auto upsampled = std::vector<double>(size_t{OnsetRateMultiple} * hData->mIrPoints);
        /* This resampler is used to help detect the response onset. */
        PPhaseResampler rs;
        rs.init(hData->mIrRate, OnsetRateMultiple*hData->mIrRate);

        for(auto &field : hData->mFds)
        {
            for(auto &elev : field.mEvs.subspan(field.mEvStart))
            {
                for(auto &azd : elev.mAzs)
                {
                    for(uint ti{0};ti < channels;ti++)
                    {
                        hrir_done.fetch_add(1u, std::memory_order_acq_rel);
                        azd.mDelays[ti] += CalcHrirOnset(rs, hData->mIrRate, upsampled,
                            azd.mIrs[ti].first(hData->mIrPoints));
                    }
                }
            }
        }
        return true;
    };

    std::future_status load_status{};
    auto load_future = std::async(std::launch::async, onset_proc);
    do {
        load_status = load_future.wait_for(std::chrono::milliseconds{50});
        printf("\rCalculating HRIR onsets... %zu of %zu", hrir_done.load(), hrir_total);
        fflush(stdout);
    } while(load_status != std::future_status::ready);
    fputc('\n', stdout);
    if(!load_future.get())
        return false;

    MagCalculator calculator{hData->mFftSize, hData->mIrPoints};
    for(auto &field : hData->mFds)
    {
        for(auto &elev : field.mEvs.subspan(field.mEvStart))
        {
            for(auto &azd : elev.mAzs)
            {
                for(uint ti{0};ti < channels;ti++)
                    calculator.mIrs.push_back(azd.mIrs[ti]);
            }
        }
    }

    std::vector<std::thread> thrds;
    thrds.reserve(numThreads);
    for(size_t i{0};i < numThreads;++i)
        thrds.emplace_back(std::mem_fn(&MagCalculator::Worker), &calculator);
    size_t count;
    do {
        std::this_thread::sleep_for(std::chrono::milliseconds{50});
        count = calculator.mDone.load();

        printf("\rCalculating HRIR magnitudes... %zu of %zu", count, calculator.mIrs.size());
        fflush(stdout);
    } while(count != calculator.mIrs.size());
    fputc('\n', stdout);

    for(auto &thrd : thrds)
    {
        if(thrd.joinable())
            thrd.join();
    }
    return true;
}
