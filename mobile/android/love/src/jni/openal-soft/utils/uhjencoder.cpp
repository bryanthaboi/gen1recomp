/*
 * 2-channel UHJ Encoder
 *
 * Copyright (c) Chris Robinson <chris.kcat@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "config.h"

#include <algorithm>
#include <array>
#include <cassert>
#include <cinttypes>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "alnumbers.h"
#include "alspan.h"
#include "alstring.h"
#include "phase_shifter.h"
#include "vector.h"

#include "sndfile.h"

#include "win_main_utf8.h"


namespace {

using namespace std::string_view_literals;

struct SndFileDeleter {
    void operator()(SNDFILE *sndfile) { sf_close(sndfile); }
};
using SndFilePtr = std::unique_ptr<SNDFILE,SndFileDeleter>;


using uint = unsigned int;

constexpr uint BufferLineSize{1024};

using FloatBufferLine = std::array<float,BufferLineSize>;
using FloatBufferSpan = al::span<float,BufferLineSize>;


struct UhjEncoder {
    constexpr static size_t sFilterDelay{1024};

    /* Delays and processing storage for the unfiltered signal. */
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mW{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mX{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mY{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mZ{};

    alignas(16) std::array<float,BufferLineSize> mS{};
    alignas(16) std::array<float,BufferLineSize> mD{};
    alignas(16) std::array<float,BufferLineSize> mT{};

    /* History for the FIR filter. */
    alignas(16) std::array<float,sFilterDelay*2 - 1> mWXHistory1{};
    alignas(16) std::array<float,sFilterDelay*2 - 1> mWXHistory2{};

    alignas(16) std::array<float,BufferLineSize + sFilterDelay*2> mTemp{};

    void encode(const al::span<FloatBufferLine> OutSamples,
        const al::span<const FloatBufferLine,4> InSamples, const size_t SamplesToDo);
};

const PhaseShifterT<UhjEncoder::sFilterDelay*2> PShift{};


/* Encoding UHJ from B-Format is done as:
 *
 * S = 0.9396926*W + 0.1855740*X
 * D = j(-0.3420201*W + 0.5098604*X) + 0.6554516*Y
 *
 * Left = (S + D)/2.0
 * Right = (S - D)/2.0
 * T = j(-0.1432*W + 0.6512*X) - 0.7071068*Y
 * Q = 0.9772*Z
 *
 * where j is a wide-band +90 degree phase shift. T is excluded from 2-channel
 * output, and Q is excluded from 2- and 3-channel output.
 */
void UhjEncoder::encode(const al::span<FloatBufferLine> OutSamples,
    const al::span<const FloatBufferLine,4> InSamples, const size_t SamplesToDo)
{
    const auto winput = al::span{InSamples[0]}.first(SamplesToDo);
    const auto xinput = al::span{InSamples[1]}.first(SamplesToDo);
    const auto yinput = al::span{InSamples[2]}.first(SamplesToDo);
    const auto zinput = al::span{InSamples[3]}.first(SamplesToDo);

    /* Combine the previously delayed input signal with the new input. */
    std::copy(winput.begin(), winput.end(), mW.begin()+sFilterDelay);
    std::copy(xinput.begin(), xinput.end(), mX.begin()+sFilterDelay);
    std::copy(yinput.begin(), yinput.end(), mY.begin()+sFilterDelay);
    std::copy(zinput.begin(), zinput.end(), mZ.begin()+sFilterDelay);

    /* S = 0.9396926*W + 0.1855740*X */
    for(size_t i{0};i < SamplesToDo;++i)
        mS[i] = 0.9396926f*mW[i] + 0.1855740f*mX[i];

    /* Precompute j(-0.3420201*W + 0.5098604*X) and store in mD. */
    auto tmpiter = std::copy(mWXHistory1.cbegin(), mWXHistory1.cend(), mTemp.begin());
    std::transform(winput.begin(), winput.end(), xinput.begin(), tmpiter,
        [](const float w, const float x) noexcept -> float
        { return -0.3420201f*w + 0.5098604f*x; });
    std::copy_n(mTemp.cbegin()+SamplesToDo, mWXHistory1.size(), mWXHistory1.begin());
    PShift.process(al::span{mD}.first(SamplesToDo), mTemp);

    /* D = j(-0.3420201*W + 0.5098604*X) + 0.6554516*Y */
    for(size_t i{0};i < SamplesToDo;++i)
        mD[i] = mD[i] + 0.6554516f*mY[i];

    /* Left = (S + D)/2.0 */
    auto left = al::span{OutSamples[0]};
    for(size_t i{0};i < SamplesToDo;i++)
        left[i] = (mS[i] + mD[i]) * 0.5f;
    /* Right = (S - D)/2.0 */
    auto right = al::span{OutSamples[1]};
    for(size_t i{0};i < SamplesToDo;i++)
        right[i] = (mS[i] - mD[i]) * 0.5f;

    if(OutSamples.size() > 2)
    {
        /* Precompute j(-0.1432*W + 0.6512*X) and store in mT. */
        tmpiter = std::copy(mWXHistory2.cbegin(), mWXHistory2.cend(), mTemp.begin());
        std::transform(winput.begin(), winput.end(), xinput.begin(), tmpiter,
            [](const float w, const float x) noexcept -> float
            { return -0.1432f*w + 0.6512f*x; });
        std::copy_n(mTemp.cbegin()+SamplesToDo, mWXHistory2.size(), mWXHistory2.begin());
        PShift.process(al::span{mT}.first(SamplesToDo), mTemp);

        /* T = j(-0.1432*W + 0.6512*X) - 0.7071068*Y */
        auto t = al::span{OutSamples[2]};
        for(size_t i{0};i < SamplesToDo;i++)
            t[i] = mT[i] - 0.7071068f*mY[i];
    }
    if(OutSamples.size() > 3)
    {
        /* Q = 0.9772*Z */
        auto q = al::span{OutSamples[3]};
        for(size_t i{0};i < SamplesToDo;i++)
            q[i] = 0.9772f*mZ[i];
    }

    /* Copy the future samples to the front for next time. */
    std::copy(mW.cbegin()+SamplesToDo, mW.cbegin()+SamplesToDo+sFilterDelay, mW.begin());
    std::copy(mX.cbegin()+SamplesToDo, mX.cbegin()+SamplesToDo+sFilterDelay, mX.begin());
    std::copy(mY.cbegin()+SamplesToDo, mY.cbegin()+SamplesToDo+sFilterDelay, mY.begin());
    std::copy(mZ.cbegin()+SamplesToDo, mZ.cbegin()+SamplesToDo+sFilterDelay, mZ.begin());
}


struct SpeakerPos {
    int mChannelID;
    float mAzimuth;
    float mElevation;
};

/* Azimuth is counter-clockwise. */
constexpr std::array MonoMap{
    SpeakerPos{SF_CHANNEL_MAP_CENTER, 0.0f, 0.0f},
};
constexpr std::array StereoMap{
    SpeakerPos{SF_CHANNEL_MAP_LEFT,   30.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_RIGHT, -30.0f, 0.0f},
};
constexpr std::array QuadMap{
    SpeakerPos{SF_CHANNEL_MAP_LEFT,         45.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_RIGHT,       -45.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_REAR_LEFT,   135.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_REAR_RIGHT, -135.0f, 0.0f},
};
constexpr std::array X51Map{
    SpeakerPos{SF_CHANNEL_MAP_LEFT,         30.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_RIGHT,       -30.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_CENTER,        0.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_LFE, 0.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_SIDE_LEFT,   110.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_SIDE_RIGHT, -110.0f, 0.0f},
};
constexpr std::array X51RearMap{
    SpeakerPos{SF_CHANNEL_MAP_LEFT,         30.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_RIGHT,       -30.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_CENTER,        0.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_LFE, 0.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_REAR_LEFT,   110.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_REAR_RIGHT, -110.0f, 0.0f},
};
constexpr std::array X71Map{
    SpeakerPos{SF_CHANNEL_MAP_LEFT,         30.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_RIGHT,       -30.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_CENTER,        0.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_LFE, 0.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_REAR_LEFT,   150.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_REAR_RIGHT, -150.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_SIDE_LEFT,    90.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_SIDE_RIGHT,  -90.0f, 0.0f},
};
constexpr std::array X714Map{
    SpeakerPos{SF_CHANNEL_MAP_LEFT,         30.0f,  0.0f},
    SpeakerPos{SF_CHANNEL_MAP_RIGHT,       -30.0f,  0.0f},
    SpeakerPos{SF_CHANNEL_MAP_CENTER,        0.0f,  0.0f},
    SpeakerPos{SF_CHANNEL_MAP_LFE, 0.0f, 0.0f},
    SpeakerPos{SF_CHANNEL_MAP_REAR_LEFT,   150.0f,  0.0f},
    SpeakerPos{SF_CHANNEL_MAP_REAR_RIGHT, -150.0f,  0.0f},
    SpeakerPos{SF_CHANNEL_MAP_SIDE_LEFT,    90.0f,  0.0f},
    SpeakerPos{SF_CHANNEL_MAP_SIDE_RIGHT,  -90.0f,  0.0f},
    SpeakerPos{SF_CHANNEL_MAP_TOP_FRONT_LEFT,    45.0f, 35.0f},
    SpeakerPos{SF_CHANNEL_MAP_TOP_FRONT_RIGHT,  -45.0f, 35.0f},
    SpeakerPos{SF_CHANNEL_MAP_TOP_REAR_LEFT,    135.0f, 35.0f},
    SpeakerPos{SF_CHANNEL_MAP_TOP_REAR_RIGHT,  -135.0f, 35.0f},
};

constexpr auto GenCoeffs(double x /*+front*/, double y /*+left*/, double z /*+up*/) noexcept
{
    /* Coefficients are +3dB of FuMa. */
    return std::array<float,4>{{
        1.0f,
        static_cast<float>(al::numbers::sqrt2 * x),
        static_cast<float>(al::numbers::sqrt2 * y),
        static_cast<float>(al::numbers::sqrt2 * z)
    }};
}


int main(al::span<std::string_view> args)
{
    if(args.size() < 2 || args[1] == "-h" || args[1] == "--help")
    {
        printf("Usage: %.*s <[options] infile...>\n\n"
            "  Options:\n"
            "    -bhj  Encode 2-channel UHJ, aka \"BJH\" (default).\n"
            "    -thj  Encode 3-channel UHJ, aka \"TJH\".\n"
            "    -phj  Encode 4-channel UHJ, aka \"PJH\".\n"
            "\n"
            "3-channel UHJ supplements 2-channel UHJ with an extra channel that allows full\n"
            "reconstruction of first-order 2D ambisonics. 4-channel UHJ supplements 3-channel\n"
            "UHJ with an extra channel carrying height information, providing for full\n"
            "reconstruction of first-order 3D ambisonics.\n"
            "\n"
            "Note: The third and fourth channels should be ignored if they're not being\n"
            "decoded. Unlike the first two channels, they are not designed for undecoded\n"
            "playback, so the resulting files will not play correctly if this isn't handled.\n",
            al::sizei(args[0]), args[0].data());
        return 1;
    }
    args = args.subspan(1);

    uint uhjchans{2};
    size_t num_files{0}, num_encoded{0};
    auto process_arg = [&uhjchans,&num_files,&num_encoded](std::string_view arg) -> void
    {
        if(arg == "-bhj"sv)
        {
            uhjchans = 2;
            return;
        }
        if(arg == "-thj"sv)
        {
            uhjchans = 3;
            return;
        }
        if(arg == "-phj"sv)
        {
            uhjchans = 4;
            return;
        }
        ++num_files;

        auto outname = std::string{arg};
        const auto lastslash = outname.rfind('/');
        if(lastslash != std::string::npos)
            outname.erase(0, lastslash+1);
        const auto extpos = outname.rfind('.');
        if(extpos != std::string::npos)
            outname.resize(extpos);
        outname += ".uhj.flac";

        SF_INFO ininfo{};
        SndFilePtr infile{sf_open(std::string{arg}.c_str(), SFM_READ, &ininfo)};
        if(!infile)
        {
            fprintf(stderr, "Failed to open %.*s\n", al::sizei(arg), arg.data());
            return;
        }
        printf("Converting %.*s to %s...\n", al::sizei(arg), arg.data(), outname.c_str());

        /* Work out the channel map, preferably using the actual channel map
         * from the file/format, but falling back to assuming WFX order.
         */
        al::span<const SpeakerPos> spkrs;
        auto chanmap = std::vector<int>(static_cast<uint>(ininfo.channels), SF_CHANNEL_MAP_INVALID);
        if(sf_command(infile.get(), SFC_GET_CHANNEL_MAP_INFO, chanmap.data(),
            ininfo.channels*int{sizeof(int)}) == SF_TRUE)
        {
            static const std::array<int,1> monomap{{SF_CHANNEL_MAP_CENTER}};
            static const std::array<int,2> stereomap{{SF_CHANNEL_MAP_LEFT, SF_CHANNEL_MAP_RIGHT}};
            static const std::array<int,4> quadmap{{SF_CHANNEL_MAP_LEFT, SF_CHANNEL_MAP_RIGHT,
                SF_CHANNEL_MAP_REAR_LEFT, SF_CHANNEL_MAP_REAR_RIGHT}};
            static const std::array<int,6> x51map{{SF_CHANNEL_MAP_LEFT, SF_CHANNEL_MAP_RIGHT,
                SF_CHANNEL_MAP_CENTER, SF_CHANNEL_MAP_LFE,
                SF_CHANNEL_MAP_SIDE_LEFT, SF_CHANNEL_MAP_SIDE_RIGHT}};
            static const std::array<int,6> x51rearmap{{SF_CHANNEL_MAP_LEFT, SF_CHANNEL_MAP_RIGHT,
                SF_CHANNEL_MAP_CENTER, SF_CHANNEL_MAP_LFE,
                SF_CHANNEL_MAP_REAR_LEFT, SF_CHANNEL_MAP_REAR_RIGHT}};
            static const std::array<int,8> x71map{{SF_CHANNEL_MAP_LEFT, SF_CHANNEL_MAP_RIGHT,
                SF_CHANNEL_MAP_CENTER, SF_CHANNEL_MAP_LFE,
                SF_CHANNEL_MAP_REAR_LEFT, SF_CHANNEL_MAP_REAR_RIGHT,
                SF_CHANNEL_MAP_SIDE_LEFT, SF_CHANNEL_MAP_SIDE_RIGHT}};
            static const std::array<int,12> x714map{{SF_CHANNEL_MAP_LEFT, SF_CHANNEL_MAP_RIGHT,
                SF_CHANNEL_MAP_CENTER, SF_CHANNEL_MAP_LFE,
                SF_CHANNEL_MAP_REAR_LEFT, SF_CHANNEL_MAP_REAR_RIGHT,
                SF_CHANNEL_MAP_SIDE_LEFT, SF_CHANNEL_MAP_SIDE_RIGHT,
                SF_CHANNEL_MAP_TOP_FRONT_LEFT, SF_CHANNEL_MAP_TOP_FRONT_RIGHT,
                SF_CHANNEL_MAP_TOP_REAR_LEFT, SF_CHANNEL_MAP_TOP_REAR_RIGHT}};
            static const std::array<int,3> ambi2dmap{{SF_CHANNEL_MAP_AMBISONIC_B_W,
                SF_CHANNEL_MAP_AMBISONIC_B_X, SF_CHANNEL_MAP_AMBISONIC_B_Y}};
            static const std::array<int,4> ambi3dmap{{SF_CHANNEL_MAP_AMBISONIC_B_W,
                SF_CHANNEL_MAP_AMBISONIC_B_X, SF_CHANNEL_MAP_AMBISONIC_B_Y,
                SF_CHANNEL_MAP_AMBISONIC_B_Z}};

            auto match_chanmap = [](const al::span<int> a, const al::span<const int> b) -> bool
            {
                if(a.size() != b.size())
                    return false;
                auto find_channel = [b](const int id) -> bool
                { return std::find(b.begin(), b.end(), id) != b.end(); };
                return std::all_of(a.cbegin(), a.cend(), find_channel);
            };
            if(match_chanmap(chanmap, monomap))
                spkrs = MonoMap;
            else if(match_chanmap(chanmap, stereomap))
                spkrs = StereoMap;
            else if(match_chanmap(chanmap, quadmap))
                spkrs = QuadMap;
            else if(match_chanmap(chanmap, x51map))
                spkrs = X51Map;
            else if(match_chanmap(chanmap, x51rearmap))
                spkrs = X51RearMap;
            else if(match_chanmap(chanmap, x71map))
                spkrs = X71Map;
            else if(match_chanmap(chanmap, x714map))
                spkrs = X714Map;
            else if(match_chanmap(chanmap, ambi2dmap) || match_chanmap(chanmap, ambi3dmap))
            {
                /* Do nothing. */
            }
            else
            {
                std::string mapstr;
                if(!chanmap.empty())
                {
                    mapstr = std::to_string(chanmap[0]);
                    for(int idx : al::span<int>{chanmap}.subspan<1>())
                    {
                        mapstr += ',';
                        mapstr += std::to_string(idx);
                    }
                }
                fprintf(stderr, " ... %zu channels not supported (map: %s)\n", chanmap.size(),
                    mapstr.c_str());
                return;
            }
        }
        else if(sf_command(infile.get(), SFC_WAVEX_GET_AMBISONIC, nullptr,
            0) == SF_AMBISONIC_B_FORMAT)
        {
            if(ininfo.channels == 4)
            {
                fprintf(stderr, " ... detected FuMa 3D B-Format\n");
                chanmap[0] = SF_CHANNEL_MAP_AMBISONIC_B_W;
                chanmap[1] = SF_CHANNEL_MAP_AMBISONIC_B_X;
                chanmap[2] = SF_CHANNEL_MAP_AMBISONIC_B_Y;
                chanmap[3] = SF_CHANNEL_MAP_AMBISONIC_B_Z;
            }
            else if(ininfo.channels == 3)
            {
                fprintf(stderr, " ... detected FuMa 2D B-Format\n");
                chanmap[0] = SF_CHANNEL_MAP_AMBISONIC_B_W;
                chanmap[1] = SF_CHANNEL_MAP_AMBISONIC_B_X;
                chanmap[2] = SF_CHANNEL_MAP_AMBISONIC_B_Y;
            }
            else
            {
                fprintf(stderr, " ... unhandled %d-channel B-Format\n", ininfo.channels);
                return;
            }
        }
        else if(ininfo.channels == 1)
        {
            fprintf(stderr, " ... assuming front-center\n");
            spkrs = MonoMap;
            chanmap[0] = SF_CHANNEL_MAP_CENTER;
        }
        else if(ininfo.channels == 2)
        {
            fprintf(stderr, " ... assuming WFX order stereo\n");
            spkrs = StereoMap;
            chanmap[0] = SF_CHANNEL_MAP_LEFT;
            chanmap[1] = SF_CHANNEL_MAP_RIGHT;
        }
        else if(ininfo.channels == 6)
        {
            fprintf(stderr, " ... assuming WFX order 5.1\n");
            spkrs = X51Map;
            chanmap[0] = SF_CHANNEL_MAP_LEFT;
            chanmap[1] = SF_CHANNEL_MAP_RIGHT;
            chanmap[2] = SF_CHANNEL_MAP_CENTER;
            chanmap[3] = SF_CHANNEL_MAP_LFE;
            chanmap[4] = SF_CHANNEL_MAP_SIDE_LEFT;
            chanmap[5] = SF_CHANNEL_MAP_SIDE_RIGHT;
        }
        else if(ininfo.channels == 8)
        {
            fprintf(stderr, " ... assuming WFX order 7.1\n");
            spkrs = X71Map;
            chanmap[0] = SF_CHANNEL_MAP_LEFT;
            chanmap[1] = SF_CHANNEL_MAP_RIGHT;
            chanmap[2] = SF_CHANNEL_MAP_CENTER;
            chanmap[3] = SF_CHANNEL_MAP_LFE;
            chanmap[4] = SF_CHANNEL_MAP_REAR_LEFT;
            chanmap[5] = SF_CHANNEL_MAP_REAR_RIGHT;
            chanmap[6] = SF_CHANNEL_MAP_SIDE_LEFT;
            chanmap[7] = SF_CHANNEL_MAP_SIDE_RIGHT;
        }
        else
        {
            fprintf(stderr, " ... unmapped %d-channel audio not supported\n", ininfo.channels);
            return;
        }

        SF_INFO outinfo{};
        outinfo.frames = ininfo.frames;
        outinfo.samplerate = ininfo.samplerate;
        outinfo.channels = static_cast<int>(uhjchans);
        outinfo.format = SF_FORMAT_PCM_24 | SF_FORMAT_FLAC;
        SndFilePtr outfile{sf_open(outname.c_str(), SFM_WRITE, &outinfo)};
        if(!outfile)
        {
            fprintf(stderr, " ... failed to create %s\n", outname.c_str());
            return;
        }

        auto encoder = std::make_unique<UhjEncoder>();
        auto splbuf = al::vector<FloatBufferLine, 16>(9);
        auto ambmem = al::span{splbuf}.subspan<0,4>();
        auto encmem = al::span{splbuf}.subspan<4,4>();
        auto srcmem = al::span{splbuf[8]};
        auto membuf = al::vector<float,16>((static_cast<uint>(ininfo.channels)+size_t{uhjchans})
            * BufferLineSize);
        auto outmem = al::span{membuf}.first(size_t{BufferLineSize}*uhjchans);
        auto inmem = al::span{membuf}.last(size_t{BufferLineSize}
            * static_cast<uint>(ininfo.channels));

        /* A number of initial samples need to be skipped to cut the lead-in
         * from the all-pass filter delay. The same number of samples need to
         * be fed through the encoder after reaching the end of the input file
         * to ensure none of the original input is lost.
         */
        size_t total_wrote{0};
        size_t LeadIn{UhjEncoder::sFilterDelay};
        sf_count_t LeadOut{UhjEncoder::sFilterDelay};
        while(LeadIn > 0 || LeadOut > 0)
        {
            auto sgot = sf_readf_float(infile.get(), inmem.data(), BufferLineSize);

            sgot = std::max<sf_count_t>(sgot, 0);
            if(sgot < BufferLineSize)
            {
                const sf_count_t remaining{std::min(BufferLineSize - sgot, LeadOut)};
                std::fill_n(inmem.begin() + sgot*ininfo.channels, remaining*ininfo.channels, 0.0f);
                sgot += remaining;
                LeadOut -= remaining;
            }

            for(auto&& buf : ambmem)
                buf.fill(0.0f);

            auto got = static_cast<size_t>(sgot);
            if(spkrs.empty())
            {
                /* B-Format is already in the correct order. It just needs a
                 * +3dB boost.
                 */
                static constexpr float scale{al::numbers::sqrt2_v<float>};
                const size_t chans{std::min<size_t>(static_cast<uint>(ininfo.channels), 4u)};
                for(size_t c{0};c < chans;++c)
                {
                    for(size_t i{0};i < got;++i)
                        ambmem[c][i] = inmem[i*static_cast<uint>(ininfo.channels) + c] * scale;
                }
            }
            else for(size_t idx{0};idx < chanmap.size();++idx)
            {
                const int chanid{chanmap[idx]};
                /* Skip LFE. Or mix directly into W? Or W+X? */
                if(chanid == SF_CHANNEL_MAP_LFE)
                    continue;

                const auto spkr = std::find_if(spkrs.cbegin(), spkrs.cend(),
                    [chanid](const SpeakerPos pos){return pos.mChannelID == chanid;});
                if(spkr == spkrs.cend())
                {
                    fprintf(stderr, " ... failed to find channel ID %d\n", chanid);
                    continue;
                }

                for(size_t i{0};i < got;++i)
                    srcmem[i] = inmem[i*static_cast<uint>(ininfo.channels) + idx];

                static constexpr auto Deg2Rad = al::numbers::pi / 180.0;
                const auto coeffs = GenCoeffs(
                    std::cos(spkr->mAzimuth*Deg2Rad) * std::cos(spkr->mElevation*Deg2Rad),
                    std::sin(spkr->mAzimuth*Deg2Rad) * std::cos(spkr->mElevation*Deg2Rad),
                    std::sin(spkr->mElevation*Deg2Rad));
                for(size_t c{0};c < 4;++c)
                {
                    for(size_t i{0};i < got;++i)
                        ambmem[c][i] += srcmem[i] * coeffs[c];
                }
            }

            encoder->encode(encmem.subspan(0, uhjchans), ambmem, got);
            if(LeadIn >= got)
            {
                LeadIn -= got;
                continue;
            }

            got -= LeadIn;
            for(size_t c{0};c < uhjchans;++c)
            {
                static constexpr float max_val{8388607.0f / 8388608.0f};
                for(size_t i{0};i < got;++i)
                    outmem[i*uhjchans + c] = std::clamp(encmem[c][LeadIn+i], -1.0f, max_val);
            }
            LeadIn = 0;

            sf_count_t wrote{sf_writef_float(outfile.get(), outmem.data(),
                static_cast<sf_count_t>(got))};
            if(wrote < 0)
                fprintf(stderr, " ... failed to write samples: %d\n", sf_error(outfile.get()));
            else
                total_wrote += static_cast<size_t>(wrote);
        }
        printf(" ... wrote %zu samples (%" PRId64 ").\n", total_wrote, int64_t{ininfo.frames});
        ++num_encoded;
    };
    std::for_each(args.begin(), args.end(), process_arg);

    if(num_encoded == 0)
        fprintf(stderr, "Failed to encode any input files\n");
    else if(num_encoded < num_files)
        fprintf(stderr, "Encoded %zu of %zu files\n", num_encoded, num_files);
    else
        printf("Encoded %s%zu file%s\n", (num_encoded > 1) ? "all " : "", num_encoded,
            (num_encoded == 1) ? "" : "s");
    return 0;
}

} /* namespace */

int main(int argc, char **argv)
{
    assert(argc >= 0);
    auto args = std::vector<std::string_view>(static_cast<unsigned int>(argc));
    std::copy_n(argv, args.size(), args.begin());
    return main(al::span{args});
}
