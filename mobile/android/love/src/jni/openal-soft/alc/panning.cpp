/**
 * OpenAL cross platform audio library
 * Copyright (C) 1999-2010 by authors.
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
#include <bitset>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdint>
#include <functional>
#include <memory>
#include <numeric>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "AL/alc.h"
#include "AL/alext.h"

#include "alc/context.h"
#include "alnumbers.h"
#include "alnumeric.h"
#include "alspan.h"
#include "alstring.h"
#include "alu.h"
#include "core/ambdec.h"
#include "core/ambidefs.h"
#include "core/bformatdec.h"
#include "core/bufferline.h"
#include "core/bs2b.h"
#include "core/context.h"
#include "core/devformat.h"
#include "core/device.h"
#include "core/effectslot.h"
#include "core/filters/nfc.h"
#include "core/filters/splitter.h"
#include "core/front_stablizer.h"
#include "core/hrtf.h"
#include "core/logging.h"
#include "core/mixer/hrtfdefs.h"
#include "core/uhjfilter.h"
#include "device.h"
#include "flexarray.h"
#include "intrusive_ptr.h"
#include "opthelpers.h"
#include "vector.h"


namespace {

using namespace std::string_view_literals;
using std::chrono::seconds;
using std::chrono::nanoseconds;

const char *GetLabelFromChannel(Channel channel)
{
    switch(channel)
    {
        case FrontLeft: return "front-left";
        case FrontRight: return "front-right";
        case FrontCenter: return "front-center";
        case LFE: return "lfe";
        case BackLeft: return "back-left";
        case BackRight: return "back-right";
        case BackCenter: return "back-center";
        case SideLeft: return "side-left";
        case SideRight: return "side-right";

        case TopFrontLeft: return "top-front-left";
        case TopFrontCenter: return "top-front-center";
        case TopFrontRight: return "top-front-right";
        case TopCenter: return "top-center";
        case TopBackLeft: return "top-back-left";
        case TopBackCenter: return "top-back-center";
        case TopBackRight: return "top-back-right";

        case BottomFrontLeft: return "bottom-front-left";
        case BottomFrontRight: return "bottom-front-right";
        case BottomBackLeft: return "bottom-back-left";
        case BottomBackRight: return "bottom-back-right";

        case Aux0: return "Aux0";
        case Aux1: return "Aux1";
        case Aux2: return "Aux2";
        case Aux3: return "Aux3";
        case Aux4: return "Aux4";
        case Aux5: return "Aux5";
        case Aux6: return "Aux6";
        case Aux7: return "Aux7";
        case Aux8: return "Aux8";
        case Aux9: return "Aux9";
        case Aux10: return "Aux10";
        case Aux11: return "Aux11";
        case Aux12: return "Aux12";
        case Aux13: return "Aux13";
        case Aux14: return "Aux14";
        case Aux15: return "Aux15";

        case MaxChannels: break;
    }
    return "(unknown)";
}

auto GetLayoutName(DevAmbiLayout layout) noexcept -> const char*
{
    switch(layout)
    {
    case DevAmbiLayout::FuMa: return "FuMa";
    case DevAmbiLayout::ACN: return "ACN";
    }
    return "<unknown layout enum>";
}

auto GetScalingName(DevAmbiScaling scaling) noexcept -> const char*
{
    switch(scaling)
    {
    case DevAmbiScaling::FuMa: return "FuMa";
    case DevAmbiScaling::SN3D: return "SN3D";
    case DevAmbiScaling::N3D: return "N3D";
    }
    return "<unknown scaling enum>";
}


std::unique_ptr<FrontStablizer> CreateStablizer(const size_t outchans, const uint srate)
{
    auto stablizer = FrontStablizer::Create(outchans);

    /* Initialize band-splitting filter for the mid signal, with a crossover at
     * 5khz (could be higher).
     */
    stablizer->MidFilter.init(5000.0f / static_cast<float>(srate));
    for(auto &filter : stablizer->ChannelFilters)
        filter = stablizer->MidFilter;

    return stablizer;
}

void AllocChannels(ALCdevice *device, const size_t main_chans, const size_t real_chans)
{
    TRACE("Channel config, Main: %zu, Real: %zu\n", main_chans, real_chans);

    /* Allocate extra channels for any post-filter output. */
    const size_t num_chans{main_chans + real_chans};

    TRACE("Allocating %zu channels, %zu bytes\n", num_chans,
        num_chans*sizeof(device->MixBuffer[0]));
    device->MixBuffer.resize(num_chans);
    al::span<FloatBufferLine> buffer{device->MixBuffer};

    device->Dry.Buffer = buffer.first(main_chans);
    buffer = buffer.subspan(main_chans);
    if(real_chans != 0)
    {
        device->RealOut.Buffer = buffer.first(real_chans);
        buffer = buffer.subspan(real_chans);
    }
    else
        device->RealOut.Buffer = device->Dry.Buffer;
}


using ChannelCoeffs = std::array<float,MaxAmbiChannels>;
enum DecoderMode : bool {
    SingleBand = false,
    DualBand = true
};

template<DecoderMode Mode, size_t N>
struct DecoderConfig;

template<size_t N>
struct DecoderConfig<SingleBand, N> {
    uint8_t mOrder{};
    bool mIs3D{};
    std::array<Channel,N> mChannels{};
    DevAmbiScaling mScaling{};
    std::array<float,MaxAmbiOrder+1> mOrderGain{};
    std::array<ChannelCoeffs,N> mCoeffs{};
};

template<size_t N>
struct DecoderConfig<DualBand, N> {
    uint8_t mOrder{};
    bool mIs3D{};
    std::array<Channel,N> mChannels{};
    DevAmbiScaling mScaling{};
    std::array<float,MaxAmbiOrder+1> mOrderGain{};
    std::array<ChannelCoeffs,N> mCoeffs{};
    std::array<float,MaxAmbiOrder+1> mOrderGainLF{};
    std::array<ChannelCoeffs,N> mCoeffsLF{};
};

template<>
struct DecoderConfig<DualBand, 0> {
    uint8_t mOrder{};
    bool mIs3D{};
    al::span<const Channel> mChannels;
    DevAmbiScaling mScaling{};
    al::span<const float> mOrderGain;
    al::span<const ChannelCoeffs> mCoeffs;
    al::span<const float> mOrderGainLF;
    al::span<const ChannelCoeffs> mCoeffsLF;

    template<size_t N>
    DecoderConfig& operator=(const DecoderConfig<SingleBand,N> &rhs) noexcept
    {
        mOrder = rhs.mOrder;
        mIs3D = rhs.mIs3D;
        mChannels = rhs.mChannels;
        mScaling = rhs.mScaling;
        mOrderGain = rhs.mOrderGain;
        mCoeffs = rhs.mCoeffs;
        mOrderGainLF = {};
        mCoeffsLF = {};
        return *this;
    }

    template<size_t N>
    DecoderConfig& operator=(const DecoderConfig<DualBand,N> &rhs) noexcept
    {
        mOrder = rhs.mOrder;
        mIs3D = rhs.mIs3D;
        mChannels = rhs.mChannels;
        mScaling = rhs.mScaling;
        mOrderGain = rhs.mOrderGain;
        mCoeffs = rhs.mCoeffs;
        mOrderGainLF = rhs.mOrderGainLF;
        mCoeffsLF = rhs.mCoeffsLF;
        return *this;
    }

    explicit operator bool() const noexcept { return !mChannels.empty(); }
};
using DecoderView = DecoderConfig<DualBand, 0>;


void InitNearFieldCtrl(ALCdevice *device, const float ctrl_dist, const uint order, const bool is3d)
{
    static const std::array<uint,MaxAmbiOrder+1> chans_per_order2d{{1, 2, 2, 2}};
    static const std::array<uint,MaxAmbiOrder+1> chans_per_order3d{{1, 3, 5, 7}};

    /* NFC is only used when AvgSpeakerDist is greater than 0. */
    if(!device->getConfigValueBool("decoder", "nfc", false) || !(ctrl_dist > 0.0f))
        return;

    device->AvgSpeakerDist = std::clamp(ctrl_dist, 0.1f, 10.0f);
    TRACE("Using near-field reference distance: %.2f meters\n", device->AvgSpeakerDist);

    const float w1{SpeedOfSoundMetersPerSec /
        (device->AvgSpeakerDist * static_cast<float>(device->Frequency))};
    device->mNFCtrlFilter.init(w1);

    auto iter = std::copy_n(is3d ? chans_per_order3d.begin() : chans_per_order2d.begin(), order+1u,
        device->NumChannelsPerOrder.begin());
    std::fill(iter, device->NumChannelsPerOrder.end(), 0u);
}

void InitDistanceComp(ALCdevice *device, const al::span<const Channel> channels,
    const al::span<const float,MaxOutputChannels> dists)
{
    const float maxdist{std::accumulate(dists.begin(), dists.end(), 0.0f,
        [](const float a, const float b) noexcept -> float { return std::max(a, b); })};

    if(!device->getConfigValueBool("decoder", "distance-comp", true) || !(maxdist > 0.0f))
        return;

    const auto distSampleScale = static_cast<float>(device->Frequency) / SpeedOfSoundMetersPerSec;

    struct DistCoeffs { uint Length{}; float Gain{}; };
    std::vector<DistCoeffs> ChanDelay;
    ChanDelay.reserve(device->RealOut.Buffer.size());

    size_t total{0u};
    for(size_t chidx{0};chidx < channels.size();++chidx)
    {
        const Channel ch{channels[chidx]};
        const size_t idx{device->RealOut.ChannelIndex[ch]};
        if(idx == InvalidChannelIndex)
            continue;

        const float distance{dists[chidx]};

        /* Distance compensation only delays in steps of the sample rate. This
         * is a bit less accurate since the delay time falls to the nearest
         * sample time, but it's far simpler as it doesn't have to deal with
         * phase offsets. This means at 48khz, for instance, the distance delay
         * will be in steps of about 7 millimeters.
         */
        float delay{std::floor((maxdist - distance)*distSampleScale + 0.5f)};
        if(delay > float{DistanceComp::MaxDelay-1})
        {
            ERR("Delay for channel %zu (%s) exceeds buffer length (%f > %d)\n", idx,
                GetLabelFromChannel(ch), delay, DistanceComp::MaxDelay-1);
            delay = float{DistanceComp::MaxDelay-1};
        }

        ChanDelay.resize(std::max(ChanDelay.size(), idx+1_uz));
        ChanDelay[idx].Length = static_cast<uint>(delay);
        ChanDelay[idx].Gain = distance / maxdist;
        TRACE("Channel %s distance comp: %u samples, %f gain\n", GetLabelFromChannel(ch),
            ChanDelay[idx].Length, ChanDelay[idx].Gain);

        /* Round up to the next 4th sample, so each channel buffer starts
         * 16-byte aligned.
         */
        total += RoundUp(ChanDelay[idx].Length, 4);
    }

    if(total > 0)
    {
        auto chandelays = DistanceComp::Create(total);
        auto chanbuffer = chandelays->mSamples.begin();

        auto set_bufptr = [&chanbuffer](const DistCoeffs &data)
        {
            DistanceComp::ChanData ret{};
            ret.Buffer = al::span{chanbuffer, data.Length};
            ret.Gain = data.Gain;
            chanbuffer += ptrdiff_t(RoundUp(data.Length, 4));
            return ret;
        };
        std::transform(ChanDelay.begin(), ChanDelay.end(), chandelays->mChannels.begin(),
            set_bufptr);
        device->ChannelDelays = std::move(chandelays);
    }
}


constexpr auto GetAmbiScales(DevAmbiScaling scaletype) noexcept
{
    if(scaletype == DevAmbiScaling::FuMa) return al::span{AmbiScale::FromFuMa};
    if(scaletype == DevAmbiScaling::SN3D) return al::span{AmbiScale::FromSN3D};
    return al::span{AmbiScale::FromN3D};
}

constexpr auto GetAmbiLayout(DevAmbiLayout layouttype) noexcept
{
    if(layouttype == DevAmbiLayout::FuMa) return al::span{AmbiIndex::FromFuMa};
    return al::span{AmbiIndex::FromACN};
}


DecoderView MakeDecoderView(ALCdevice *device, const AmbDecConf *conf,
    DecoderConfig<DualBand,MaxOutputChannels> &decoder)
{
    DecoderView ret{};

    decoder.mOrder = (conf->ChanMask > Ambi3OrderMask) ? uint8_t{4} :
        (conf->ChanMask > Ambi2OrderMask) ? uint8_t{3} :
        (conf->ChanMask > Ambi1OrderMask) ? uint8_t{2} : uint8_t{1};
    decoder.mIs3D = (conf->ChanMask&AmbiPeriphonicMask) != 0;

    switch(conf->CoeffScale)
    {
    case AmbDecScale::Unset: ASSUME(false); break;
    case AmbDecScale::N3D: decoder.mScaling = DevAmbiScaling::N3D; break;
    case AmbDecScale::SN3D: decoder.mScaling = DevAmbiScaling::SN3D; break;
    case AmbDecScale::FuMa: decoder.mScaling = DevAmbiScaling::FuMa; break;
    }

    const auto hfordermin = std::min(conf->HFOrderGain.size(), decoder.mOrderGain.size());
    std::copy_n(conf->HFOrderGain.begin(), hfordermin, decoder.mOrderGain.begin());
    const auto lfordermin = std::min(conf->LFOrderGain.size(), decoder.mOrderGainLF.size());
    std::copy_n(conf->LFOrderGain.begin(), lfordermin, decoder.mOrderGainLF.begin());

    const auto num_coeffs = decoder.mIs3D ? AmbiChannelsFromOrder(decoder.mOrder)
        : Ambi2DChannelsFromOrder(decoder.mOrder);
    const auto idx_map = decoder.mIs3D ? al::span<const uint8_t>{AmbiIndex::FromACN}
        : al::span<const uint8_t>{AmbiIndex::FromACN2D};
    const auto hfmatrix = conf->HFMatrix;
    const auto lfmatrix = conf->LFMatrix;

    uint chan_count{0};
    for(auto &speaker : al::span{std::as_const(conf->Speakers)})
    {
        /* NOTE: AmbDec does not define any standard speaker names, however
         * for this to work we have to by able to find the output channel
         * the speaker definition corresponds to. Therefore, OpenAL Soft
         * requires these channel labels to be recognized:
         *
         * LF = Front left
         * RF = Front right
         * LS = Side left
         * RS = Side right
         * LB = Back left
         * RB = Back right
         * CE = Front center
         * CB = Back center
         * LFT = Top front left
         * RFT = Top front right
         * LBT = Top back left
         * RBT = Top back right
         * LFB = Bottom front left
         * RFB = Bottom front right
         * LBB = Bottom back left
         * RBB = Bottom back right
         *
         * Additionally, surround51 will acknowledge back speakers for side
         * channels, to avoid issues with an ambdec expecting 5.1 to use the
         * back channels.
         */
        Channel ch{};
        if(speaker.Name == "LF"sv)
            ch = FrontLeft;
        else if(speaker.Name == "RF"sv)
            ch = FrontRight;
        else if(speaker.Name == "CE"sv)
            ch = FrontCenter;
        else if(speaker.Name == "LS"sv)
            ch = SideLeft;
        else if(speaker.Name == "RS"sv)
            ch = SideRight;
        else if(speaker.Name == "LB"sv)
            ch = (device->FmtChans == DevFmtX51) ? SideLeft : BackLeft;
        else if(speaker.Name == "RB"sv)
            ch = (device->FmtChans == DevFmtX51) ? SideRight : BackRight;
        else if(speaker.Name == "CB"sv)
            ch = BackCenter;
        else if(speaker.Name == "LFT"sv)
            ch = TopFrontLeft;
        else if(speaker.Name == "RFT"sv)
            ch = TopFrontRight;
        else if(speaker.Name == "LBT"sv)
            ch = TopBackLeft;
        else if(speaker.Name == "RBT"sv)
            ch = TopBackRight;
        else if(speaker.Name == "LFB"sv)
            ch = BottomFrontLeft;
        else if(speaker.Name == "RFB"sv)
            ch = BottomFrontRight;
        else if(speaker.Name == "LBB"sv)
            ch = BottomBackLeft;
        else if(speaker.Name == "RBB"sv)
            ch = BottomBackRight;
        else
        {
            int idx{};
            char c{};
            if(sscanf(speaker.Name.c_str(), "AUX%d%c", &idx, &c) != 1 || idx < 0
                || idx >= MaxChannels-Aux0)
            {
                ERR("AmbDec speaker label \"%s\" not recognized\n", speaker.Name.c_str());
                continue;
            }
            ch = static_cast<Channel>(Aux0+idx);
        }

        decoder.mChannels[chan_count] = ch;
        for(size_t dst{0};dst < num_coeffs;++dst)
        {
            const size_t src{idx_map[dst]};
            decoder.mCoeffs[chan_count][dst] = hfmatrix[chan_count][src];
        }
        if(conf->FreqBands > 1)
        {
            for(size_t dst{0};dst < num_coeffs;++dst)
            {
                const size_t src{idx_map[dst]};
                decoder.mCoeffsLF[chan_count][dst] = lfmatrix[chan_count][src];
            }
        }
        ++chan_count;
    }

    if(chan_count > 0)
    {
        ret.mOrder = decoder.mOrder;
        ret.mIs3D = decoder.mIs3D;
        ret.mScaling = decoder.mScaling;
        ret.mChannels = al::span{decoder.mChannels}.first(chan_count);
        ret.mOrderGain = decoder.mOrderGain;
        ret.mCoeffs = al::span{decoder.mCoeffs}.first(chan_count);
        if(conf->FreqBands > 1)
        {
            ret.mOrderGainLF = decoder.mOrderGainLF;
            ret.mCoeffsLF = al::span{decoder.mCoeffsLF}.first(chan_count);
        }
    }
    return ret;
}

constexpr DecoderConfig<SingleBand, 1> MonoConfig{
    0, false, {{FrontCenter}},
    DevAmbiScaling::N3D,
    {{1.0f}},
    {{ {{1.0f}} }}
};
constexpr DecoderConfig<SingleBand, 2> StereoConfig{
    1, false, {{FrontLeft, FrontRight}},
    DevAmbiScaling::N3D,
    {{1.0f, 1.0f}},
    {{
        {{5.00000000e-1f,  2.88675135e-1f,  5.52305643e-2f}},
        {{5.00000000e-1f, -2.88675135e-1f,  5.52305643e-2f}},
    }}
};
constexpr DecoderConfig<DualBand, 4> QuadConfig{
    1, false, {{BackLeft, FrontLeft, FrontRight, BackRight}},
    DevAmbiScaling::N3D,
    /*HF*/{{1.41421356e+0f, 1.00000000e+0f}},
    {{
        {{2.50000000e-1f,  2.04124145e-1f, -2.04124145e-1f}},
        {{2.50000000e-1f,  2.04124145e-1f,  2.04124145e-1f}},
        {{2.50000000e-1f, -2.04124145e-1f,  2.04124145e-1f}},
        {{2.50000000e-1f, -2.04124145e-1f, -2.04124145e-1f}},
    }},
    /*LF*/{{1.00000000e+0f, 1.00000000e+0f}},
    {{
        {{2.50000000e-1f,  2.04124145e-1f, -2.04124145e-1f}},
        {{2.50000000e-1f,  2.04124145e-1f,  2.04124145e-1f}},
        {{2.50000000e-1f, -2.04124145e-1f,  2.04124145e-1f}},
        {{2.50000000e-1f, -2.04124145e-1f, -2.04124145e-1f}},
    }}
};
constexpr DecoderConfig<DualBand, 5> X51Config{
    2, false, {{SideLeft, FrontLeft, FrontCenter, FrontRight, SideRight}},
    DevAmbiScaling::FuMa,
    /*HF*/{{1.00000000e+0f, 1.00000000e+0f, 1.00000000e+0f}},
    {{
        {{5.67316000e-1f,  4.22920000e-1f, -3.15495000e-1f, -6.34490000e-2f, -2.92380000e-2f}},
        {{3.68584000e-1f,  2.72349000e-1f,  3.21616000e-1f,  1.92645000e-1f,  4.82600000e-2f}},
        {{1.83579000e-1f,  0.00000000e+0f,  1.99588000e-1f,  0.00000000e+0f,  9.62820000e-2f}},
        {{3.68584000e-1f, -2.72349000e-1f,  3.21616000e-1f, -1.92645000e-1f,  4.82600000e-2f}},
        {{5.67316000e-1f, -4.22920000e-1f, -3.15495000e-1f,  6.34490000e-2f, -2.92380000e-2f}},
    }},
    /*LF*/{{1.00000000e+0f, 1.00000000e+0f, 1.00000000e+0f}},
    {{
        {{4.90109850e-1f,  3.77305010e-1f, -3.73106990e-1f, -1.25914530e-1f,  1.45133000e-2f}},
        {{1.49085730e-1f,  3.03561680e-1f,  1.53290060e-1f,  2.45112480e-1f, -1.50753130e-1f}},
        {{1.37654920e-1f,  0.00000000e+0f,  4.49417940e-1f,  0.00000000e+0f,  2.57844070e-1f}},
        {{1.49085730e-1f, -3.03561680e-1f,  1.53290060e-1f, -2.45112480e-1f, -1.50753130e-1f}},
        {{4.90109850e-1f, -3.77305010e-1f, -3.73106990e-1f,  1.25914530e-1f,  1.45133000e-2f}},
    }}
};
constexpr DecoderConfig<SingleBand, 5> X61Config{
    2, false, {{SideLeft, FrontLeft, FrontRight, SideRight, BackCenter}},
    DevAmbiScaling::N3D,
    {{1.0f, 1.0f, 1.0f}},
    {{
        {{2.04460341e-1f,  2.17177926e-1f, -4.39996780e-2f, -2.60790269e-2f, -6.87239792e-2f}},
        {{1.58923161e-1f,  9.21772680e-2f,  1.59658796e-1f,  6.66278083e-2f,  3.84686854e-2f}},
        {{1.58923161e-1f, -9.21772680e-2f,  1.59658796e-1f, -6.66278083e-2f,  3.84686854e-2f}},
        {{2.04460341e-1f, -2.17177926e-1f, -4.39996780e-2f,  2.60790269e-2f, -6.87239792e-2f}},
        {{2.50001688e-1f,  0.00000000e+0f, -2.50000094e-1f,  0.00000000e+0f,  6.05133395e-2f}},
    }}
};
constexpr DecoderConfig<DualBand, 6> X71Config{
    2, false, {{BackLeft, SideLeft, FrontLeft, FrontRight, SideRight, BackRight}},
    DevAmbiScaling::N3D,
    /*HF*/{{1.41421356e+0f, 1.22474487e+0f, 7.07106781e-1f}},
    {{
        {{1.66666667e-1f,  9.62250449e-2f, -1.66666667e-1f, -1.49071198e-1f,  8.60662966e-2f}},
        {{1.66666667e-1f,  1.92450090e-1f,  0.00000000e+0f,  0.00000000e+0f, -1.72132593e-1f}},
        {{1.66666667e-1f,  9.62250449e-2f,  1.66666667e-1f,  1.49071198e-1f,  8.60662966e-2f}},
        {{1.66666667e-1f, -9.62250449e-2f,  1.66666667e-1f, -1.49071198e-1f,  8.60662966e-2f}},
        {{1.66666667e-1f, -1.92450090e-1f,  0.00000000e+0f,  0.00000000e+0f, -1.72132593e-1f}},
        {{1.66666667e-1f, -9.62250449e-2f, -1.66666667e-1f,  1.49071198e-1f,  8.60662966e-2f}},
    }},
    /*LF*/{{1.00000000e+0f, 1.00000000e+0f, 1.00000000e+0f}},
    {{
        {{1.66666667e-1f,  9.62250449e-2f, -1.66666667e-1f, -1.49071198e-1f,  8.60662966e-2f}},
        {{1.66666667e-1f,  1.92450090e-1f,  0.00000000e+0f,  0.00000000e+0f, -1.72132593e-1f}},
        {{1.66666667e-1f,  9.62250449e-2f,  1.66666667e-1f,  1.49071198e-1f,  8.60662966e-2f}},
        {{1.66666667e-1f, -9.62250449e-2f,  1.66666667e-1f, -1.49071198e-1f,  8.60662966e-2f}},
        {{1.66666667e-1f, -1.92450090e-1f,  0.00000000e+0f,  0.00000000e+0f, -1.72132593e-1f}},
        {{1.66666667e-1f, -9.62250449e-2f, -1.66666667e-1f,  1.49071198e-1f,  8.60662966e-2f}},
    }}
};
constexpr DecoderConfig<DualBand, 6> X3D71Config{
    1, true, {{Aux0, SideLeft, FrontLeft, FrontRight, SideRight, Aux1}},
    DevAmbiScaling::N3D,
    /*HF*/{{1.73205081e+0f, 1.00000000e+0f}},
    {{
        {{1.666666667e-01f,  0.000000000e+00f,  2.356640879e-01f, -1.667265410e-01f}},
        {{1.666666667e-01f,  2.033043281e-01f, -1.175581508e-01f, -1.678904388e-01f}},
        {{1.666666667e-01f,  2.033043281e-01f,  1.175581508e-01f,  1.678904388e-01f}},
        {{1.666666667e-01f, -2.033043281e-01f,  1.175581508e-01f,  1.678904388e-01f}},
        {{1.666666667e-01f, -2.033043281e-01f, -1.175581508e-01f, -1.678904388e-01f}},
        {{1.666666667e-01f,  0.000000000e+00f, -2.356640879e-01f,  1.667265410e-01f}},
    }},
    /*LF*/{{1.00000000e+0f, 1.00000000e+0f}},
    {{
        {{1.666666667e-01f,  0.000000000e+00f,  2.356640879e-01f, -1.667265410e-01f}},
        {{1.666666667e-01f,  2.033043281e-01f, -1.175581508e-01f, -1.678904388e-01f}},
        {{1.666666667e-01f,  2.033043281e-01f,  1.175581508e-01f,  1.678904388e-01f}},
        {{1.666666667e-01f, -2.033043281e-01f,  1.175581508e-01f,  1.678904388e-01f}},
        {{1.666666667e-01f, -2.033043281e-01f, -1.175581508e-01f, -1.678904388e-01f}},
        {{1.666666667e-01f,  0.000000000e+00f, -2.356640879e-01f,  1.667265410e-01f}},
    }}
};
constexpr DecoderConfig<SingleBand, 10> X714Config{
    1, true, {{FrontLeft, FrontRight, SideLeft, SideRight, BackLeft, BackRight, TopFrontLeft, TopFrontRight, TopBackLeft, TopBackRight }},
    DevAmbiScaling::N3D,
    {{1.00000000e+0f, 1.00000000e+0f, 1.00000000e+0f}},
    {{
        {{1.27149251e-01f,  7.63047539e-02f, -3.64373750e-02f,  1.59700680e-01f}},
        {{1.07005418e-01f, -7.67638760e-02f, -4.92129762e-02f,  1.29012797e-01f}},
        {{1.26400196e-01f,  1.77494694e-01f, -3.71203389e-02f,  0.00000000e+00f}},
        {{1.26396516e-01f, -1.77488059e-01f, -3.71297878e-02f,  0.00000000e+00f}},
        {{1.06996956e-01f,  7.67615256e-02f, -4.92166307e-02f, -1.29001640e-01f}},
        {{1.27145671e-01f, -7.63003471e-02f, -3.64353304e-02f, -1.59697510e-01f}},
        {{8.80919747e-02f,  7.48940670e-02f,  9.08786244e-02f,  6.22527183e-02f}},
        {{1.57880745e-01f, -7.28755272e-02f,  1.82364187e-01f,  8.74240284e-02f}},
        {{1.57892225e-01f,  7.28944768e-02f,  1.82363474e-01f, -8.74301086e-02f}},
        {{8.80892603e-02f, -7.48948724e-02f,  9.08779842e-02f, -6.22480443e-02f}},
    }}
};
constexpr DecoderConfig<DualBand, 14> X7144Config{
    1, true, {{BackLeft, SideLeft, FrontLeft, FrontRight, SideRight, BackRight, TopBackLeft, TopFrontLeft, TopFrontRight, TopBackRight, BottomBackLeft, BottomFrontLeft, BottomFrontRight, BottomBackRight}},
    DevAmbiScaling::N3D,
    /*HF*/{{2.64575131e+0f, 1.52752523e+0f}},
    {{
        {{7.14285714e-02f,  5.09426708e-02f,  0.00000000e+00f, -8.82352941e-02f}},
        {{7.14285714e-02f,  1.01885342e-01f,  0.00000000e+00f,  0.00000000e+00f}},
        {{7.14285714e-02f,  5.09426708e-02f,  0.00000000e+00f,  8.82352941e-02f}},
        {{7.14285714e-02f, -5.09426708e-02f,  0.00000000e+00f,  8.82352941e-02f}},
        {{7.14285714e-02f, -1.01885342e-01f,  0.00000000e+00f,  0.00000000e+00f}},
        {{7.14285714e-02f, -5.09426708e-02f,  0.00000000e+00f, -8.82352941e-02f}},
        {{7.14285714e-02f,  5.88235294e-02f,  1.25000000e-01f, -5.88235294e-02f}},
        {{7.14285714e-02f,  5.88235294e-02f,  1.25000000e-01f,  5.88235294e-02f}},
        {{7.14285714e-02f, -5.88235294e-02f,  1.25000000e-01f,  5.88235294e-02f}},
        {{7.14285714e-02f, -5.88235294e-02f,  1.25000000e-01f, -5.88235294e-02f}},
        {{7.14285714e-02f,  5.88235294e-02f, -1.25000000e-01f, -5.88235294e-02f}},
        {{7.14285714e-02f,  5.88235294e-02f, -1.25000000e-01f,  5.88235294e-02f}},
        {{7.14285714e-02f, -5.88235294e-02f, -1.25000000e-01f,  5.88235294e-02f}},
        {{7.14285714e-02f, -5.88235294e-02f, -1.25000000e-01f, -5.88235294e-02f}},
    }},
    /*LF*/{{1.00000000e+0f, 1.00000000e+0f}},
    {{
        {{7.14285714e-02f,  5.09426708e-02f,  0.00000000e+00f, -8.82352941e-02f}},
        {{7.14285714e-02f,  1.01885342e-01f,  0.00000000e+00f,  0.00000000e+00f}},
        {{7.14285714e-02f,  5.09426708e-02f,  0.00000000e+00f,  8.82352941e-02f}},
        {{7.14285714e-02f, -5.09426708e-02f,  0.00000000e+00f,  8.82352941e-02f}},
        {{7.14285714e-02f, -1.01885342e-01f,  0.00000000e+00f,  0.00000000e+00f}},
        {{7.14285714e-02f, -5.09426708e-02f,  0.00000000e+00f, -8.82352941e-02f}},
        {{7.14285714e-02f,  5.88235294e-02f,  1.25000000e-01f, -5.88235294e-02f}},
        {{7.14285714e-02f,  5.88235294e-02f,  1.25000000e-01f,  5.88235294e-02f}},
        {{7.14285714e-02f, -5.88235294e-02f,  1.25000000e-01f,  5.88235294e-02f}},
        {{7.14285714e-02f, -5.88235294e-02f,  1.25000000e-01f, -5.88235294e-02f}},
        {{7.14285714e-02f,  5.88235294e-02f, -1.25000000e-01f, -5.88235294e-02f}},
        {{7.14285714e-02f,  5.88235294e-02f, -1.25000000e-01f,  5.88235294e-02f}},
        {{7.14285714e-02f, -5.88235294e-02f, -1.25000000e-01f,  5.88235294e-02f}},
        {{7.14285714e-02f, -5.88235294e-02f, -1.25000000e-01f, -5.88235294e-02f}},
    }}
};

void InitPanning(ALCdevice *device, const bool hqdec=false, const bool stablize=false,
    DecoderView decoder={})
{
    if(!decoder)
    {
        switch(device->FmtChans)
        {
        case DevFmtMono: decoder = MonoConfig; break;
        case DevFmtStereo: decoder = StereoConfig; break;
        case DevFmtQuad: decoder = QuadConfig; break;
        case DevFmtX51: decoder = X51Config; break;
        case DevFmtX61: decoder = X61Config; break;
        case DevFmtX71: decoder = X71Config; break;
        case DevFmtX714: decoder = X714Config; break;
        case DevFmtX7144: decoder = X7144Config; break;
        case DevFmtX3D71: decoder = X3D71Config; break;
        case DevFmtAmbi3D:
            /* For DevFmtAmbi3D, the ambisonic order is already set. */
            const size_t count{AmbiChannelsFromOrder(device->mAmbiOrder)};
            const auto acnmap = GetAmbiLayout(device->mAmbiLayout).first(count);
            const auto n3dscale = GetAmbiScales(device->mAmbiScale);

            std::transform(acnmap.cbegin(), acnmap.cend(), device->Dry.AmbiMap.begin(),
                [n3dscale](const uint8_t &acn) noexcept -> BFChannelConfig
                { return BFChannelConfig{1.0f/n3dscale[acn], acn}; });
            AllocChannels(device, count, 0);
            device->m2DMixing = false;

            float avg_dist{};
            if(auto distopt = device->configValue<float>("decoder", "speaker-dist"))
                avg_dist = *distopt;
            else if(auto delayopt = device->configValue<float>("decoder", "nfc-ref-delay"))
            {
                WARN("nfc-ref-delay is deprecated, use speaker-dist instead\n");
                avg_dist = *delayopt * SpeedOfSoundMetersPerSec;
            }

            TRACE("%u%s order ambisonic output (%s layout, %s scaling)\n", device->mAmbiOrder,
                  GetCounterSuffix(device->mAmbiOrder), GetLayoutName(device->mAmbiLayout),
                  GetScalingName(device->mAmbiScale));
            InitNearFieldCtrl(device, avg_dist, device->mAmbiOrder, true);
            return;
        }
    }

    const size_t ambicount{decoder.mIs3D ? AmbiChannelsFromOrder(decoder.mOrder) :
        Ambi2DChannelsFromOrder(decoder.mOrder)};
    const bool dual_band{hqdec && !decoder.mCoeffsLF.empty()};
    std::vector<ChannelDec> chancoeffs, chancoeffslf;
    for(size_t i{0u};i < decoder.mChannels.size();++i)
    {
        const size_t idx{device->channelIdxByName(decoder.mChannels[i])};
        if(idx == InvalidChannelIndex)
        {
            ERR("Failed to find %s channel in device\n",
                GetLabelFromChannel(decoder.mChannels[i]));
            continue;
        }

        auto ordermap = decoder.mIs3D ? al::span<const uint8_t>{AmbiIndex::OrderFromChannel}
            : al::span<const uint8_t>{AmbiIndex::OrderFrom2DChannel};

        chancoeffs.resize(std::max(chancoeffs.size(), idx+1_zu), ChannelDec{});
        al::span<const float,MaxAmbiChannels> src{decoder.mCoeffs[i]};
        al::span<float,MaxAmbiChannels> dst{chancoeffs[idx]};
        for(size_t ambichan{0};ambichan < ambicount;++ambichan)
            dst[ambichan] = src[ambichan] * decoder.mOrderGain[ordermap[ambichan]];

        if(!dual_band)
            continue;

        chancoeffslf.resize(std::max(chancoeffslf.size(), idx+1_zu), ChannelDec{});
        src = decoder.mCoeffsLF[i];
        dst = chancoeffslf[idx];
        for(size_t ambichan{0};ambichan < ambicount;++ambichan)
            dst[ambichan] = src[ambichan] * decoder.mOrderGainLF[ordermap[ambichan]];
    }

    /* For non-DevFmtAmbi3D, set the ambisonic order. */
    device->mAmbiOrder = decoder.mOrder;
    device->m2DMixing = !decoder.mIs3D;

    const auto acnmap = decoder.mIs3D ? al::span{AmbiIndex::FromACN}.first(ambicount)
        : al::span{AmbiIndex::FromACN2D}.first(ambicount);
    const auto coeffscale = GetAmbiScales(decoder.mScaling);
    std::transform(acnmap.begin(), acnmap.end(), device->Dry.AmbiMap.begin(),
        [coeffscale](const uint8_t &acn) noexcept
        { return BFChannelConfig{1.0f/coeffscale[acn], acn}; });
    AllocChannels(device, ambicount, device->channelsFromFmt());

    std::unique_ptr<FrontStablizer> stablizer;
    if(stablize)
    {
        /* Only enable the stablizer if the decoder does not output to the
         * front-center channel.
         */
        const size_t cidx{device->RealOut.ChannelIndex[FrontCenter]};
        bool hasfc{false};
        if(cidx < chancoeffs.size())
        {
            for(const auto &coeff : chancoeffs[cidx])
                hasfc |= coeff != 0.0f;
        }
        if(!hasfc && cidx < chancoeffslf.size())
        {
            for(const auto &coeff : chancoeffslf[cidx])
                hasfc |= coeff != 0.0f;
        }
        if(!hasfc)
        {
            stablizer = CreateStablizer(device->channelsFromFmt(), device->Frequency);
            TRACE("Front stablizer enabled\n");
        }
    }

    TRACE("Enabling %s-band %s-order%s ambisonic decoder\n",
        !dual_band ? "single" : "dual",
        (decoder.mOrder > 3) ? "fourth" :
        (decoder.mOrder > 2) ? "third" :
        (decoder.mOrder > 1) ? "second" : "first",
        decoder.mIs3D ? " periphonic" : "");
    device->AmbiDecoder = BFormatDec::Create(ambicount, chancoeffs, chancoeffslf,
        device->mXOverFreq/static_cast<float>(device->Frequency), std::move(stablizer));
}

void InitHrtfPanning(ALCdevice *device)
{
    static constexpr float Deg180{al::numbers::pi_v<float>};
    static constexpr float Deg_90{Deg180 / 2.0f /* 90 degrees*/};
    static constexpr float Deg_45{Deg_90 / 2.0f /* 45 degrees*/};
    static constexpr float Deg135{Deg_45 * 3.0f /*135 degrees*/};
    static constexpr float Deg_21{3.648638281e-01f /* 20~ 21 degrees*/};
    static constexpr float Deg_32{5.535743589e-01f /* 31~ 32 degrees*/};
    static constexpr float Deg_35{6.154797087e-01f /* 35~ 36 degrees*/};
    static constexpr float Deg_58{1.017221968e+00f /* 58~ 59 degrees*/};
    static constexpr float Deg_69{1.205932499e+00f /* 69~ 70 degrees*/};
    static constexpr float Deg111{1.935660155e+00f /*110~111 degrees*/};
    static constexpr float Deg122{2.124370686e+00f /*121~122 degrees*/};
    static constexpr std::array AmbiPoints1O{
        AngularPoint{EvRadians{ Deg_35}, AzRadians{-Deg_45}},
        AngularPoint{EvRadians{ Deg_35}, AzRadians{-Deg135}},
        AngularPoint{EvRadians{ Deg_35}, AzRadians{ Deg_45}},
        AngularPoint{EvRadians{ Deg_35}, AzRadians{ Deg135}},
        AngularPoint{EvRadians{-Deg_35}, AzRadians{-Deg_45}},
        AngularPoint{EvRadians{-Deg_35}, AzRadians{-Deg135}},
        AngularPoint{EvRadians{-Deg_35}, AzRadians{ Deg_45}},
        AngularPoint{EvRadians{-Deg_35}, AzRadians{ Deg135}},
    };
    static constexpr std::array AmbiPoints2O{
        AngularPoint{EvRadians{-Deg_32}, AzRadians{   0.0f}},
        AngularPoint{EvRadians{   0.0f}, AzRadians{ Deg_58}},
        AngularPoint{EvRadians{ Deg_58}, AzRadians{ Deg_90}},
        AngularPoint{EvRadians{ Deg_32}, AzRadians{   0.0f}},
        AngularPoint{EvRadians{   0.0f}, AzRadians{ Deg122}},
        AngularPoint{EvRadians{-Deg_58}, AzRadians{-Deg_90}},
        AngularPoint{EvRadians{-Deg_32}, AzRadians{ Deg180}},
        AngularPoint{EvRadians{   0.0f}, AzRadians{-Deg122}},
        AngularPoint{EvRadians{ Deg_58}, AzRadians{-Deg_90}},
        AngularPoint{EvRadians{ Deg_32}, AzRadians{ Deg180}},
        AngularPoint{EvRadians{   0.0f}, AzRadians{-Deg_58}},
        AngularPoint{EvRadians{-Deg_58}, AzRadians{ Deg_90}},
    };
    static constexpr std::array AmbiPoints3O{
        AngularPoint{EvRadians{ Deg_69}, AzRadians{-Deg_90}},
        AngularPoint{EvRadians{ Deg_69}, AzRadians{ Deg_90}},
        AngularPoint{EvRadians{-Deg_69}, AzRadians{-Deg_90}},
        AngularPoint{EvRadians{-Deg_69}, AzRadians{ Deg_90}},
        AngularPoint{EvRadians{   0.0f}, AzRadians{-Deg_69}},
        AngularPoint{EvRadians{   0.0f}, AzRadians{-Deg111}},
        AngularPoint{EvRadians{   0.0f}, AzRadians{ Deg_69}},
        AngularPoint{EvRadians{   0.0f}, AzRadians{ Deg111}},
        AngularPoint{EvRadians{ Deg_21}, AzRadians{   0.0f}},
        AngularPoint{EvRadians{ Deg_21}, AzRadians{ Deg180}},
        AngularPoint{EvRadians{-Deg_21}, AzRadians{   0.0f}},
        AngularPoint{EvRadians{-Deg_21}, AzRadians{ Deg180}},
        AngularPoint{EvRadians{ Deg_35}, AzRadians{-Deg_45}},
        AngularPoint{EvRadians{ Deg_35}, AzRadians{-Deg135}},
        AngularPoint{EvRadians{ Deg_35}, AzRadians{ Deg_45}},
        AngularPoint{EvRadians{ Deg_35}, AzRadians{ Deg135}},
        AngularPoint{EvRadians{-Deg_35}, AzRadians{-Deg_45}},
        AngularPoint{EvRadians{-Deg_35}, AzRadians{-Deg135}},
        AngularPoint{EvRadians{-Deg_35}, AzRadians{ Deg_45}},
        AngularPoint{EvRadians{-Deg_35}, AzRadians{ Deg135}},
    };
    static constexpr std::array AmbiMatrix1O{
        ChannelCoeffs{1.250000000e-01f,  1.250000000e-01f,  1.250000000e-01f,  1.250000000e-01f},
        ChannelCoeffs{1.250000000e-01f,  1.250000000e-01f,  1.250000000e-01f, -1.250000000e-01f},
        ChannelCoeffs{1.250000000e-01f, -1.250000000e-01f,  1.250000000e-01f,  1.250000000e-01f},
        ChannelCoeffs{1.250000000e-01f, -1.250000000e-01f,  1.250000000e-01f, -1.250000000e-01f},
        ChannelCoeffs{1.250000000e-01f,  1.250000000e-01f, -1.250000000e-01f,  1.250000000e-01f},
        ChannelCoeffs{1.250000000e-01f,  1.250000000e-01f, -1.250000000e-01f, -1.250000000e-01f},
        ChannelCoeffs{1.250000000e-01f, -1.250000000e-01f, -1.250000000e-01f,  1.250000000e-01f},
        ChannelCoeffs{1.250000000e-01f, -1.250000000e-01f, -1.250000000e-01f, -1.250000000e-01f},
    };
    static constexpr std::array AmbiMatrix2O{
        ChannelCoeffs{8.333333333e-02f,  0.000000000e+00f, -7.588274978e-02f,  1.227808683e-01f,  0.000000000e+00f,  0.000000000e+00f, -1.591525047e-02f, -1.443375673e-01f,  1.167715449e-01f},
        ChannelCoeffs{8.333333333e-02f, -1.227808683e-01f,  0.000000000e+00f,  7.588274978e-02f, -1.443375673e-01f,  0.000000000e+00f, -9.316949906e-02f,  0.000000000e+00f, -7.216878365e-02f},
        ChannelCoeffs{8.333333333e-02f, -7.588274978e-02f,  1.227808683e-01f,  0.000000000e+00f,  0.000000000e+00f, -1.443375673e-01f,  1.090847495e-01f,  0.000000000e+00f, -4.460276122e-02f},
        ChannelCoeffs{8.333333333e-02f,  0.000000000e+00f,  7.588274978e-02f,  1.227808683e-01f,  0.000000000e+00f,  0.000000000e+00f, -1.591525047e-02f,  1.443375673e-01f,  1.167715449e-01f},
        ChannelCoeffs{8.333333333e-02f, -1.227808683e-01f,  0.000000000e+00f, -7.588274978e-02f,  1.443375673e-01f,  0.000000000e+00f, -9.316949906e-02f,  0.000000000e+00f, -7.216878365e-02f},
        ChannelCoeffs{8.333333333e-02f,  7.588274978e-02f, -1.227808683e-01f,  0.000000000e+00f,  0.000000000e+00f, -1.443375673e-01f,  1.090847495e-01f,  0.000000000e+00f, -4.460276122e-02f},
        ChannelCoeffs{8.333333333e-02f,  0.000000000e+00f, -7.588274978e-02f, -1.227808683e-01f,  0.000000000e+00f,  0.000000000e+00f, -1.591525047e-02f,  1.443375673e-01f,  1.167715449e-01f},
        ChannelCoeffs{8.333333333e-02f,  1.227808683e-01f,  0.000000000e+00f, -7.588274978e-02f, -1.443375673e-01f,  0.000000000e+00f, -9.316949906e-02f,  0.000000000e+00f, -7.216878365e-02f},
        ChannelCoeffs{8.333333333e-02f,  7.588274978e-02f,  1.227808683e-01f,  0.000000000e+00f,  0.000000000e+00f,  1.443375673e-01f,  1.090847495e-01f,  0.000000000e+00f, -4.460276122e-02f},
        ChannelCoeffs{8.333333333e-02f,  0.000000000e+00f,  7.588274978e-02f, -1.227808683e-01f,  0.000000000e+00f,  0.000000000e+00f, -1.591525047e-02f, -1.443375673e-01f,  1.167715449e-01f},
        ChannelCoeffs{8.333333333e-02f,  1.227808683e-01f,  0.000000000e+00f,  7.588274978e-02f,  1.443375673e-01f,  0.000000000e+00f, -9.316949906e-02f,  0.000000000e+00f, -7.216878365e-02f},
        ChannelCoeffs{8.333333333e-02f, -7.588274978e-02f, -1.227808683e-01f,  0.000000000e+00f,  0.000000000e+00f,  1.443375673e-01f,  1.090847495e-01f,  0.000000000e+00f, -4.460276122e-02f},
    };
    static constexpr std::array AmbiMatrix3O{
        ChannelCoeffs{5.000000000e-02f,  3.090169944e-02f,  8.090169944e-02f,  0.000000000e+00f,  0.000000000e+00f,  6.454972244e-02f,  9.045084972e-02f,  0.000000000e+00f, -1.232790000e-02f, -1.256118221e-01f,  0.000000000e+00f,  1.126112056e-01f,  7.944389175e-02f,  0.000000000e+00f,  2.421151497e-02f,  0.000000000e+00f},
        ChannelCoeffs{5.000000000e-02f, -3.090169944e-02f,  8.090169944e-02f,  0.000000000e+00f,  0.000000000e+00f, -6.454972244e-02f,  9.045084972e-02f,  0.000000000e+00f, -1.232790000e-02f,  1.256118221e-01f,  0.000000000e+00f, -1.126112056e-01f,  7.944389175e-02f,  0.000000000e+00f,  2.421151497e-02f,  0.000000000e+00f},
        ChannelCoeffs{5.000000000e-02f,  3.090169944e-02f, -8.090169944e-02f,  0.000000000e+00f,  0.000000000e+00f, -6.454972244e-02f,  9.045084972e-02f,  0.000000000e+00f, -1.232790000e-02f, -1.256118221e-01f,  0.000000000e+00f,  1.126112056e-01f, -7.944389175e-02f,  0.000000000e+00f, -2.421151497e-02f,  0.000000000e+00f},
        ChannelCoeffs{5.000000000e-02f, -3.090169944e-02f, -8.090169944e-02f,  0.000000000e+00f,  0.000000000e+00f,  6.454972244e-02f,  9.045084972e-02f,  0.000000000e+00f, -1.232790000e-02f,  1.256118221e-01f,  0.000000000e+00f, -1.126112056e-01f, -7.944389175e-02f,  0.000000000e+00f, -2.421151497e-02f,  0.000000000e+00f},
        ChannelCoeffs{5.000000000e-02f,  8.090169944e-02f,  0.000000000e+00f,  3.090169944e-02f,  6.454972244e-02f,  0.000000000e+00f, -5.590169944e-02f,  0.000000000e+00f, -7.216878365e-02f, -7.763237543e-02f,  0.000000000e+00f, -2.950836627e-02f,  0.000000000e+00f, -1.497759251e-01f,  0.000000000e+00f, -7.763237543e-02f},
        ChannelCoeffs{5.000000000e-02f,  8.090169944e-02f,  0.000000000e+00f, -3.090169944e-02f, -6.454972244e-02f,  0.000000000e+00f, -5.590169944e-02f,  0.000000000e+00f, -7.216878365e-02f, -7.763237543e-02f,  0.000000000e+00f, -2.950836627e-02f,  0.000000000e+00f,  1.497759251e-01f,  0.000000000e+00f,  7.763237543e-02f},
        ChannelCoeffs{5.000000000e-02f, -8.090169944e-02f,  0.000000000e+00f,  3.090169944e-02f, -6.454972244e-02f,  0.000000000e+00f, -5.590169944e-02f,  0.000000000e+00f, -7.216878365e-02f,  7.763237543e-02f,  0.000000000e+00f,  2.950836627e-02f,  0.000000000e+00f, -1.497759251e-01f,  0.000000000e+00f, -7.763237543e-02f},
        ChannelCoeffs{5.000000000e-02f, -8.090169944e-02f,  0.000000000e+00f, -3.090169944e-02f,  6.454972244e-02f,  0.000000000e+00f, -5.590169944e-02f,  0.000000000e+00f, -7.216878365e-02f,  7.763237543e-02f,  0.000000000e+00f,  2.950836627e-02f,  0.000000000e+00f,  1.497759251e-01f,  0.000000000e+00f,  7.763237543e-02f},
        ChannelCoeffs{5.000000000e-02f,  0.000000000e+00f,  3.090169944e-02f,  8.090169944e-02f,  0.000000000e+00f,  0.000000000e+00f, -3.454915028e-02f,  6.454972244e-02f,  8.449668365e-02f,  0.000000000e+00f,  0.000000000e+00f,  0.000000000e+00f,  3.034486645e-02f, -6.779013272e-02f,  1.659481923e-01f,  4.797944664e-02f},
        ChannelCoeffs{5.000000000e-02f,  0.000000000e+00f,  3.090169944e-02f, -8.090169944e-02f,  0.000000000e+00f,  0.000000000e+00f, -3.454915028e-02f, -6.454972244e-02f,  8.449668365e-02f,  0.000000000e+00f,  0.000000000e+00f,  0.000000000e+00f,  3.034486645e-02f,  6.779013272e-02f,  1.659481923e-01f, -4.797944664e-02f},
        ChannelCoeffs{5.000000000e-02f,  0.000000000e+00f, -3.090169944e-02f,  8.090169944e-02f,  0.000000000e+00f,  0.000000000e+00f, -3.454915028e-02f, -6.454972244e-02f,  8.449668365e-02f,  0.000000000e+00f,  0.000000000e+00f,  0.000000000e+00f, -3.034486645e-02f, -6.779013272e-02f, -1.659481923e-01f,  4.797944664e-02f},
        ChannelCoeffs{5.000000000e-02f,  0.000000000e+00f, -3.090169944e-02f, -8.090169944e-02f,  0.000000000e+00f,  0.000000000e+00f, -3.454915028e-02f,  6.454972244e-02f,  8.449668365e-02f,  0.000000000e+00f,  0.000000000e+00f,  0.000000000e+00f, -3.034486645e-02f,  6.779013272e-02f, -1.659481923e-01f, -4.797944664e-02f},
        ChannelCoeffs{5.000000000e-02f,  5.000000000e-02f,  5.000000000e-02f,  5.000000000e-02f,  6.454972244e-02f,  6.454972244e-02f,  0.000000000e+00f,  6.454972244e-02f,  0.000000000e+00f,  1.016220987e-01f,  6.338656910e-02f, -1.092600649e-02f, -7.364853795e-02f,  1.011266756e-01f, -7.086833869e-02f, -1.482646439e-02f},
        ChannelCoeffs{5.000000000e-02f,  5.000000000e-02f,  5.000000000e-02f, -5.000000000e-02f, -6.454972244e-02f,  6.454972244e-02f,  0.000000000e+00f, -6.454972244e-02f,  0.000000000e+00f,  1.016220987e-01f, -6.338656910e-02f, -1.092600649e-02f, -7.364853795e-02f, -1.011266756e-01f, -7.086833869e-02f,  1.482646439e-02f},
        ChannelCoeffs{5.000000000e-02f, -5.000000000e-02f,  5.000000000e-02f,  5.000000000e-02f, -6.454972244e-02f, -6.454972244e-02f,  0.000000000e+00f,  6.454972244e-02f,  0.000000000e+00f, -1.016220987e-01f, -6.338656910e-02f,  1.092600649e-02f, -7.364853795e-02f,  1.011266756e-01f, -7.086833869e-02f, -1.482646439e-02f},
        ChannelCoeffs{5.000000000e-02f, -5.000000000e-02f,  5.000000000e-02f, -5.000000000e-02f,  6.454972244e-02f, -6.454972244e-02f,  0.000000000e+00f, -6.454972244e-02f,  0.000000000e+00f, -1.016220987e-01f,  6.338656910e-02f,  1.092600649e-02f, -7.364853795e-02f, -1.011266756e-01f, -7.086833869e-02f,  1.482646439e-02f},
        ChannelCoeffs{5.000000000e-02f,  5.000000000e-02f, -5.000000000e-02f,  5.000000000e-02f,  6.454972244e-02f, -6.454972244e-02f,  0.000000000e+00f, -6.454972244e-02f,  0.000000000e+00f,  1.016220987e-01f, -6.338656910e-02f, -1.092600649e-02f,  7.364853795e-02f,  1.011266756e-01f,  7.086833869e-02f, -1.482646439e-02f},
        ChannelCoeffs{5.000000000e-02f,  5.000000000e-02f, -5.000000000e-02f, -5.000000000e-02f, -6.454972244e-02f, -6.454972244e-02f,  0.000000000e+00f,  6.454972244e-02f,  0.000000000e+00f,  1.016220987e-01f,  6.338656910e-02f, -1.092600649e-02f,  7.364853795e-02f, -1.011266756e-01f,  7.086833869e-02f,  1.482646439e-02f},
        ChannelCoeffs{5.000000000e-02f, -5.000000000e-02f, -5.000000000e-02f,  5.000000000e-02f, -6.454972244e-02f,  6.454972244e-02f,  0.000000000e+00f, -6.454972244e-02f,  0.000000000e+00f, -1.016220987e-01f,  6.338656910e-02f,  1.092600649e-02f,  7.364853795e-02f,  1.011266756e-01f,  7.086833869e-02f, -1.482646439e-02f},
        ChannelCoeffs{5.000000000e-02f, -5.000000000e-02f, -5.000000000e-02f, -5.000000000e-02f,  6.454972244e-02f,  6.454972244e-02f,  0.000000000e+00f,  6.454972244e-02f,  0.000000000e+00f, -1.016220987e-01f, -6.338656910e-02f,  1.092600649e-02f,  7.364853795e-02f, -1.011266756e-01f,  7.086833869e-02f,  1.482646439e-02f},
    };
    static constexpr std::array<float,MaxAmbiOrder+1> AmbiOrderHFGain1O{
        /*ENRGY*/ 2.000000000e+00f, 1.154700538e+00f
    };
    static constexpr std::array<float,MaxAmbiOrder+1> AmbiOrderHFGain2O{
        /*ENRGY*/ 1.825741858e+00f, 1.414213562e+00f, 7.302967433e-01f
        /*AMP   1.000000000e+00f, 7.745966692e-01f, 4.000000000e-01f*/
        /*RMS   9.128709292e-01f, 7.071067812e-01f, 3.651483717e-01f*/
    };
    static constexpr std::array<float,MaxAmbiOrder+1> AmbiOrderHFGain3O{
        /*ENRGY 1.865086714e+00f, 1.606093894e+00f, 1.142055301e+00f, 5.683795528e-01f*/
        /*AMP*/ 1.000000000e+00f, 8.611363116e-01f, 6.123336207e-01f, 3.047469850e-01f
        /*RMS   8.340921354e-01f, 7.182670250e-01f, 5.107426573e-01f, 2.541870634e-01f*/
    };

    static_assert(AmbiPoints1O.size() == AmbiMatrix1O.size(), "First-Order Ambisonic HRTF mismatch");
    static_assert(AmbiPoints2O.size() == AmbiMatrix2O.size(), "Second-Order Ambisonic HRTF mismatch");
    static_assert(AmbiPoints3O.size() == AmbiMatrix3O.size(), "Third-Order Ambisonic HRTF mismatch");

    /* A 700hz crossover frequency provides tighter sound imaging at the sweet
     * spot with ambisonic decoding, as the distance between the ears is closer
     * to half this frequency wavelength, which is the optimal point where the
     * response should change between optimizing phase vs volume. Normally this
     * tighter imaging is at the cost of a smaller sweet spot, but since the
     * listener is fixed in the center of the HRTF responses for the decoder,
     * we don't have to worry about ever being out of the sweet spot.
     *
     * A better option here may be to have the head radius as part of the HRTF
     * data set and calculate the optimal crossover frequency from that.
     */
    device->mXOverFreq = 700.0f;

    /* Don't bother with HOA when using full HRTF rendering. Nothing needs it,
     * and it eases the CPU/memory load.
     */
    device->mRenderMode = RenderMode::Hrtf;
    uint ambi_order{1};
    if(auto modeopt = device->configValue<std::string>({}, "hrtf-mode"))
    {
        struct HrtfModeEntry {
            std::string_view name;
            RenderMode mode;
            uint order;
        };
        constexpr std::array hrtf_modes{
            HrtfModeEntry{"full"sv, RenderMode::Hrtf, 1},
            HrtfModeEntry{"ambi1"sv, RenderMode::Normal, 1},
            HrtfModeEntry{"ambi2"sv, RenderMode::Normal, 2},
            HrtfModeEntry{"ambi3"sv, RenderMode::Normal, 3},
        };

        std::string_view mode{*modeopt};
        if(al::case_compare(mode, "basic"sv) == 0)
        {
            ERR("HRTF mode \"%s\" deprecated, substituting \"%s\"\n", modeopt->c_str(), "ambi2");
            mode = "ambi2";
        }

        auto match_entry = [mode](const HrtfModeEntry &entry) -> bool
        { return al::case_compare(mode, entry.name) == 0; };
        auto iter = std::find_if(hrtf_modes.begin(), hrtf_modes.end(), match_entry);
        if(iter == hrtf_modes.end())
            ERR("Unexpected hrtf-mode: %s\n", modeopt->c_str());
        else
        {
            device->mRenderMode = iter->mode;
            ambi_order = iter->order;
        }
    }
    TRACE("%u%s order %sHRTF rendering enabled, using \"%s\"\n", ambi_order,
        GetCounterSuffix(ambi_order), (device->mRenderMode == RenderMode::Hrtf) ? "+ Full " : "",
        device->mHrtfName.c_str());

    bool perHrirMin{false};
    auto AmbiPoints = al::span{AmbiPoints1O}.subspan(0);
    auto AmbiMatrix = al::span{AmbiMatrix1O}.subspan(0);
    auto AmbiOrderHFGain = al::span{AmbiOrderHFGain1O};
    if(ambi_order >= 3)
    {
        perHrirMin = true;
        AmbiPoints = AmbiPoints3O;
        AmbiMatrix = AmbiMatrix3O;
        AmbiOrderHFGain = AmbiOrderHFGain3O;
    }
    else if(ambi_order == 2)
    {
        AmbiPoints = AmbiPoints2O;
        AmbiMatrix = AmbiMatrix2O;
        AmbiOrderHFGain = AmbiOrderHFGain2O;
    }
    device->mAmbiOrder = ambi_order;
    device->m2DMixing = false;

    const size_t count{AmbiChannelsFromOrder(ambi_order)};
    const auto acnmap = al::span{AmbiIndex::FromACN}.first(count);
    std::transform(acnmap.begin(), acnmap.end(), device->Dry.AmbiMap.begin(),
        [](const uint8_t &index) noexcept { return BFChannelConfig{1.0f, index}; });
    AllocChannels(device, count, device->channelsFromFmt());

    HrtfStore *Hrtf{device->mHrtf.get()};
    auto hrtfstate = DirectHrtfState::Create(count);
    hrtfstate->build(Hrtf, device->mIrSize, perHrirMin, AmbiPoints, AmbiMatrix, device->mXOverFreq,
        AmbiOrderHFGain);
    device->mHrtfState = std::move(hrtfstate);

    InitNearFieldCtrl(device, Hrtf->mFields[0].distance, ambi_order, true);
}

void InitUhjPanning(ALCdevice *device)
{
    /* UHJ is always 2D first-order. */
    static constexpr size_t count{Ambi2DChannelsFromOrder(1)};

    device->mAmbiOrder = 1;
    device->m2DMixing = true;

    const auto acnmap = al::span{AmbiIndex::FromFuMa2D}.first<count>();
    std::transform(acnmap.cbegin(), acnmap.cend(), device->Dry.AmbiMap.begin(),
        [](const uint8_t &acn) noexcept -> BFChannelConfig
        { return BFChannelConfig{1.0f/AmbiScale::FromUHJ[acn], acn}; });
    AllocChannels(device, count, device->channelsFromFmt());
}

} // namespace

void aluInitRenderer(ALCdevice *device, int hrtf_id, std::optional<StereoEncoding> stereomode)
{
    /* Hold the HRTF the device last used, in case it's used again. */
    HrtfStorePtr old_hrtf{std::move(device->mHrtf)};

    device->mHrtfState = nullptr;
    device->mHrtf = nullptr;
    device->mIrSize = 0;
    device->mHrtfName.clear();
    device->mXOverFreq = 400.0f;
    device->m2DMixing = false;
    device->mRenderMode = RenderMode::Normal;

    if(device->FmtChans != DevFmtStereo)
    {
        old_hrtf = nullptr;
        if(stereomode && *stereomode == StereoEncoding::Hrtf)
            device->mHrtfStatus = ALC_HRTF_UNSUPPORTED_FORMAT_SOFT;

        const char *layout{nullptr};
        switch(device->FmtChans)
        {
        case DevFmtQuad: layout = "quad"; break;
        case DevFmtX51: layout = "surround51"; break;
        case DevFmtX61: layout = "surround61"; break;
        case DevFmtX71: layout = "surround71"; break;
        case DevFmtX714: layout = "surround714"; break;
        case DevFmtX7144: layout = "surround7144"; break;
        case DevFmtX3D71: layout = "surround3d71"; break;
        /* Mono, Stereo, and Ambisonics output don't use custom decoders. */
        case DevFmtMono:
        case DevFmtStereo:
        case DevFmtAmbi3D:
            break;
        }

        std::unique_ptr<DecoderConfig<DualBand,MaxOutputChannels>> decoder_store;
        DecoderView decoder{};
        std::array<float,MaxOutputChannels> speakerdists{};
        auto load_config = [device,&decoder_store,&decoder,&speakerdists](const char *config)
        {
            AmbDecConf conf{};
            if(auto err = conf.load(config))
            {
                ERR("Failed to load layout file %s\n", config);
                ERR("  %s\n", err->c_str());
                return false;
            }
            if(conf.Speakers.size() > MaxOutputChannels)
            {
                ERR("Unsupported decoder speaker count %zu (max %zu)\n", conf.Speakers.size(),
                    MaxOutputChannels);
                return false;
            }
            if(conf.ChanMask > Ambi3OrderMask)
            {
                ERR("Unsupported decoder channel mask 0x%04x (max 0x%x)\n", conf.ChanMask,
                    Ambi3OrderMask);
                return false;
            }

            TRACE("Using %s decoder: \"%s\"\n", DevFmtChannelsString(device->FmtChans),
                conf.Description.c_str());
            device->mXOverFreq = std::clamp(conf.XOverFreq, 100.0f, 1000.0f);

            decoder_store = std::make_unique<DecoderConfig<DualBand,MaxOutputChannels>>();
            decoder = MakeDecoderView(device, &conf, *decoder_store);

            const auto confspeakers = al::span{std::as_const(conf.Speakers)}
                .first(decoder.mChannels.size());
            std::transform(confspeakers.cbegin(), confspeakers.cend(), speakerdists.begin(),
                std::mem_fn(&AmbDecConf::SpeakerConf::Distance));
            return true;
        };
        bool usingCustom{false};
        if(layout)
        {
            if(auto decopt = device->configValue<std::string>("decoder", layout))
                usingCustom = load_config(decopt->c_str());
        }
        if(!usingCustom && device->FmtChans != DevFmtAmbi3D)
            TRACE("Using built-in %s decoder\n", DevFmtChannelsString(device->FmtChans));

        /* Enable the stablizer only for formats that have front-left, front-
         * right, and front-center outputs.
         */
        const bool stablize{device->RealOut.ChannelIndex[FrontCenter] != InvalidChannelIndex
            && device->RealOut.ChannelIndex[FrontLeft] != InvalidChannelIndex
            && device->RealOut.ChannelIndex[FrontRight] != InvalidChannelIndex
            && device->getConfigValueBool({}, "front-stablizer", false)};
        const bool hqdec{device->getConfigValueBool("decoder", "hq-mode", true)};
        InitPanning(device, hqdec, stablize, decoder);
        if(decoder)
        {
            float accum_dist{0.0f}, spkr_count{0.0f};
            for(auto dist : speakerdists)
            {
                if(dist > 0.0f)
                {
                    accum_dist += dist;
                    spkr_count += 1.0f;
                }
            }

            const float avg_dist{(accum_dist > 0.0f && spkr_count > 0) ? accum_dist/spkr_count :
                device->configValue<float>("decoder", "speaker-dist").value_or(1.0f)};
            InitNearFieldCtrl(device, avg_dist, decoder.mOrder, decoder.mIs3D);

            if(spkr_count > 0)
                InitDistanceComp(device, decoder.mChannels, speakerdists);
        }
        if(auto *ambidec{device->AmbiDecoder.get()})
        {
            device->PostProcess = ambidec->hasStablizer() ? &ALCdevice::ProcessAmbiDecStablized
                : &ALCdevice::ProcessAmbiDec;
        }
        return;
    }


    /* If HRTF is explicitly requested, or if there's no explicit request and
     * the device is headphones, try to enable it.
     */
    if(stereomode.value_or(StereoEncoding::Default) == StereoEncoding::Hrtf
        || (!stereomode && device->Flags.test(DirectEar)))
    {
        if(device->mHrtfList.empty())
            device->enumerateHrtfs();

        if(hrtf_id >= 0 && static_cast<uint>(hrtf_id) < device->mHrtfList.size())
        {
            const std::string_view hrtfname{device->mHrtfList[static_cast<uint>(hrtf_id)]};
            if(HrtfStorePtr hrtf{GetLoadedHrtf(hrtfname, device->Frequency)})
            {
                device->mHrtf = std::move(hrtf);
                device->mHrtfName = hrtfname;
            }
        }

        if(!device->mHrtf)
        {
            for(const std::string_view hrtfname : device->mHrtfList)
            {
                if(HrtfStorePtr hrtf{GetLoadedHrtf(hrtfname, device->Frequency)})
                {
                    device->mHrtf = std::move(hrtf);
                    device->mHrtfName = hrtfname;
                    break;
                }
            }
        }

        if(device->mHrtf)
        {
            old_hrtf = nullptr;

            HrtfStore *hrtf{device->mHrtf.get()};
            device->mIrSize = hrtf->mIrSize;
            if(auto hrtfsizeopt = device->configValue<uint>({}, "hrtf-size"))
            {
                if(*hrtfsizeopt > 0 && *hrtfsizeopt < device->mIrSize)
                    device->mIrSize = std::max(*hrtfsizeopt, MinIrLength);
            }

            InitHrtfPanning(device);
            device->PostProcess = &ALCdevice::ProcessHrtf;
            device->mHrtfStatus = ALC_HRTF_ENABLED_SOFT;
            return;
        }
    }
    old_hrtf = nullptr;

    if(stereomode.value_or(StereoEncoding::Default) == StereoEncoding::Uhj)
    {
        auto ftype = std::string_view{};
        switch(UhjEncodeQuality)
        {
        case UhjQualityType::IIR:
            device->mUhjEncoder = std::make_unique<UhjEncoderIIR>();
            ftype = "IIR"sv;
            break;
        case UhjQualityType::FIR256:
            device->mUhjEncoder = std::make_unique<UhjEncoder<UhjLength256>>();
            ftype = "FIR-256"sv;
            break;
        case UhjQualityType::FIR512:
            device->mUhjEncoder = std::make_unique<UhjEncoder<UhjLength512>>();
            ftype = "FIR-512"sv;
            break;
        }
        assert(device->mUhjEncoder != nullptr);

        TRACE("UHJ enabled (%.*s encoder)\n", al::sizei(ftype), ftype.data());
        InitUhjPanning(device);
        device->PostProcess = &ALCdevice::ProcessUhj;
        return;
    }

    device->mRenderMode = RenderMode::Pairwise;
    if(device->Type != DeviceType::Loopback)
    {
        if(auto cflevopt = device->configValue<int>({}, "cf_level"))
        {
            if(*cflevopt > 0 && *cflevopt <= 6)
            {
                auto bs2b = std::make_unique<Bs2b::bs2b>();
                bs2b->set_params(*cflevopt, static_cast<int>(device->Frequency));
                device->Bs2b = std::move(bs2b);
                TRACE("BS2B enabled\n");
                InitPanning(device);
                device->PostProcess = &ALCdevice::ProcessBs2b;
                return;
            }
        }
    }

    TRACE("Stereo rendering\n");
    InitPanning(device);
    device->PostProcess = &ALCdevice::ProcessAmbiDec;
}


void aluInitEffectPanning(EffectSlot *slot, ALCcontext *context)
{
    DeviceBase *device{context->mDevice};
    const size_t count{AmbiChannelsFromOrder(device->mAmbiOrder)};

    slot->mWetBuffer.resize(count);

    const auto acnmap = al::span{AmbiIndex::FromACN}.first(count);
    const auto iter = std::transform(acnmap.cbegin(), acnmap.cend(), slot->Wet.AmbiMap.begin(),
        [](const uint8_t &acn) noexcept -> BFChannelConfig { return BFChannelConfig{1.0f, acn}; });
    std::fill(iter, slot->Wet.AmbiMap.end(), BFChannelConfig{});
    slot->Wet.Buffer = slot->mWetBuffer;
}
