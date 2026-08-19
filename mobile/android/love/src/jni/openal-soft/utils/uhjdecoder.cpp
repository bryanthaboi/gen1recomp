/*
 * 2-channel UHJ Decoder
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
#include <cerrno>
#include <complex>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

#include "albit.h"
#include "almalloc.h"
#include "alnumbers.h"
#include "alspan.h"
#include "alstring.h"
#include "vector.h"
#include "opthelpers.h"
#include "phase_shifter.h"

#include "sndfile.h"

#include "win_main_utf8.h"


namespace {

struct FileDeleter {
    void operator()(gsl::owner<FILE*> file) { fclose(file); }
};
using FilePtr = std::unique_ptr<FILE,FileDeleter>;

struct SndFileDeleter {
    void operator()(SNDFILE *sndfile) { sf_close(sndfile); }
};
using SndFilePtr = std::unique_ptr<SNDFILE,SndFileDeleter>;


using ubyte = unsigned char;
using ushort = unsigned short;
using uint = unsigned int;
using complex_d = std::complex<double>;

using byte4 = std::array<std::byte,4>;


constexpr std::array<ubyte,16> SUBTYPE_BFORMAT_FLOAT{
    0x03, 0x00, 0x00, 0x00, 0x21, 0x07, 0xd3, 0x11, 0x86, 0x44, 0xc8, 0xc1,
    0xca, 0x00, 0x00, 0x00
};

void fwrite16le(ushort val, FILE *f)
{
    std::array data{static_cast<ubyte>(val&0xff), static_cast<ubyte>((val>>8)&0xff)};
    fwrite(data.data(), 1, data.size(), f);
}

void fwrite32le(uint val, FILE *f)
{
    std::array data{static_cast<ubyte>(val&0xff), static_cast<ubyte>((val>>8)&0xff),
        static_cast<ubyte>((val>>16)&0xff), static_cast<ubyte>((val>>24)&0xff)};
    fwrite(data.data(), 1, data.size(), f);
}

byte4 f32AsLEBytes(const float value)
{
    auto ret = al::bit_cast<byte4>(value);
    if constexpr(al::endian::native == al::endian::big)
    {
        std::swap(ret[0], ret[3]);
        std::swap(ret[1], ret[2]);
    }
    return ret;
}


constexpr uint BufferLineSize{1024};

using FloatBufferLine = std::array<float,BufferLineSize>;
using FloatBufferSpan = al::span<float,BufferLineSize>;


struct UhjDecoder {
    constexpr static std::size_t sFilterDelay{1024};

    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mS{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mD{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mT{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mQ{};

    /* History for the FIR filter. */
    alignas(16) std::array<float,sFilterDelay-1> mDTHistory{};
    alignas(16) std::array<float,sFilterDelay-1> mSHistory{};

    alignas(16) std::array<float,BufferLineSize + sFilterDelay*2> mTemp{};

    void decode(const al::span<const float> InSamples, const std::size_t InChannels,
        const al::span<FloatBufferLine> OutSamples, const std::size_t SamplesToDo);
    void decode2(const al::span<const float> InSamples, const al::span<FloatBufferLine> OutSamples,
        const std::size_t SamplesToDo);
};

const PhaseShifterT<UhjDecoder::sFilterDelay*2> PShift{};


/* Decoding UHJ is done as:
 *
 * S = Left + Right
 * D = Left - Right
 *
 * W = 0.981532*S + 0.197484*j(0.828331*D + 0.767820*T)
 * X = 0.418496*S - j(0.828331*D + 0.767820*T)
 * Y = 0.795968*D - 0.676392*T + j(0.186633*S)
 * Z = 1.023332*Q
 *
 * where j is a +90 degree phase shift. 3-channel UHJ excludes Q, while 2-
 * channel excludes Q and T. The B-Format signal reconstructed from 2-channel
 * UHJ should not be run through a normal B-Format decoder, as it needs
 * different shelf filters.
 *
 * NOTE: Some sources specify
 *
 * S = (Left + Right)/2
 * D = (Left - Right)/2
 *
 * However, this is incorrect. It's halving Left and Right even though they
 * were already halved during encoding, causing S and D to be half what they
 * initially were at the encoding stage. This division is not present in
 * Gerzon's original paper for deriving Sigma (S) or Delta (D) from the L and R
 * signals. As proof, taking Y for example:
 *
 * Y = 0.795968*D - 0.676392*T + j(0.186633*S)
 *
 * * Plug in the encoding parameters, using ? as a placeholder for whether S
 *   and D should receive an extra 0.5 factor
 * Y = 0.795968*(j(-0.3420201*W + 0.5098604*X) + 0.6554516*Y)*? -
 *     0.676392*(j(-0.1432*W + 0.6512*X) - 0.7071068*Y) +
 *     0.186633*j(0.9396926*W + 0.1855740*X)*?
 *
 * * Move common factors in
 * Y = (j(-0.3420201*0.795968*?*W + 0.5098604*0.795968*?*X) + 0.6554516*0.795968*?*Y) -
 *     (j(-0.1432*0.676392*W + 0.6512*0.676392*X) - 0.7071068*0.676392*Y) +
 *     j(0.9396926*0.186633*?*W + 0.1855740*0.186633*?*X)
 *
 * * Clean up extraneous groupings
 * Y = j(-0.3420201*0.795968*?*W + 0.5098604*0.795968*?*X) + 0.6554516*0.795968*?*Y -
 *     j(-0.1432*0.676392*W + 0.6512*0.676392*X) + 0.7071068*0.676392*Y +
 *     j*(0.9396926*0.186633*?*W + 0.1855740*0.186633*?*X)
 *
 * * Move phase shifts together and combine them
 * Y = j(-0.3420201*0.795968*?*W + 0.5098604*0.795968*?*X - -0.1432*0.676392*W -
 *        0.6512*0.676392*X + 0.9396926*0.186633*?*W + 0.1855740*0.186633*?*X) +
 *     0.6554516*0.795968*?*Y + 0.7071068*0.676392*Y
 *
 * * Reorder terms
 * Y = j(-0.3420201*0.795968*?*W +  0.1432*0.676392*W + 0.9396926*0.186633*?*W +
 *        0.5098604*0.795968*?*X + -0.6512*0.676392*X + 0.1855740*0.186633*?*X) +
 *     0.7071068*0.676392*Y + 0.6554516*0.795968*?*Y
 *
 * * Move common factors out
 * Y = j((-0.3420201*0.795968*? +  0.1432*0.676392 + 0.9396926*0.186633*?)*W +
 *       ( 0.5098604*0.795968*? + -0.6512*0.676392 + 0.1855740*0.186633*?)*X) +
 *     (0.7071068*0.676392 + 0.6554516*0.795968*?)*Y
 *
 * * Result w/ 0.5 factor:
 * -0.3420201*0.795968*0.5 +  0.1432*0.676392 + 0.9396926*0.186633*0.5 =  0.04843*W
 *  0.5098604*0.795968*0.5 + -0.6512*0.676392 + 0.1855740*0.186633*0.5 = -0.22023*X
 *  0.7071068*0.676392                        + 0.6554516*0.795968*0.5 =  0.73914*Y
 * -> Y = j(0.04843*W + -0.22023*X) + 0.73914*Y
 *
 * * Result w/o 0.5 factor:
 * -0.3420201*0.795968 +  0.1432*0.676392 + 0.9396926*0.186633 = 0.00000*W
 *  0.5098604*0.795968 + -0.6512*0.676392 + 0.1855740*0.186633 = 0.00000*X
 *  0.7071068*0.676392                    + 0.6554516*0.795968 = 1.00000*Y
 * -> Y = j(0.00000*W + 0.00000*X) + 1.00000*Y
 *
 * Not halving produces a result matching the original input.
 */
void UhjDecoder::decode(const al::span<const float> InSamples, const std::size_t InChannels,
    const al::span<FloatBufferLine> OutSamples, const std::size_t SamplesToDo)
{
    ASSUME(SamplesToDo > 0);

    auto woutput = al::span{OutSamples[0]};
    auto xoutput = al::span{OutSamples[1]};
    auto youtput = al::span{OutSamples[2]};

    /* Add a delay to the input channels, to align it with the all-passed
     * signal.
     */

    /* S = Left + Right */
    for(std::size_t i{0};i < SamplesToDo;++i)
        mS[sFilterDelay+i] = InSamples[i*InChannels + 0] + InSamples[i*InChannels + 1];

    /* D = Left - Right */
    for(std::size_t i{0};i < SamplesToDo;++i)
        mD[sFilterDelay+i] = InSamples[i*InChannels + 0] - InSamples[i*InChannels + 1];

    if(InChannels > 2)
    {
        /* T */
        for(std::size_t i{0};i < SamplesToDo;++i)
            mT[sFilterDelay+i] = InSamples[i*InChannels + 2];
    }
    if(InChannels > 3)
    {
        /* Q */
        for(std::size_t i{0};i < SamplesToDo;++i)
            mQ[sFilterDelay+i] = InSamples[i*InChannels + 3];
    }

    /* Precompute j(0.828331*D + 0.767820*T) and store in xoutput. */
    auto tmpiter = std::copy(mDTHistory.cbegin(), mDTHistory.cend(), mTemp.begin());
    std::transform(mD.cbegin(), mD.cbegin()+SamplesToDo+sFilterDelay, mT.cbegin(), tmpiter,
        [](const float d, const float t) noexcept { return 0.828331f*d + 0.767820f*t; });
    std::copy_n(mTemp.cbegin()+SamplesToDo, mDTHistory.size(), mDTHistory.begin());
    PShift.process(xoutput.first(SamplesToDo), mTemp);

    for(std::size_t i{0};i < SamplesToDo;++i)
    {
        /* W = 0.981532*S + 0.197484*j(0.828331*D + 0.767820*T) */
        woutput[i] = 0.981532f*mS[i] + 0.197484f*xoutput[i];
        /* X = 0.418496*S - j(0.828331*D + 0.767820*T) */
        xoutput[i] = 0.418496f*mS[i] - xoutput[i];
    }

    /* Precompute j*S and store in youtput. */
    tmpiter = std::copy(mSHistory.cbegin(), mSHistory.cend(), mTemp.begin());
    std::copy_n(mS.cbegin(), SamplesToDo+sFilterDelay, tmpiter);
    std::copy_n(mTemp.cbegin()+SamplesToDo, mSHistory.size(), mSHistory.begin());
    PShift.process(youtput.first(SamplesToDo), mTemp);

    for(std::size_t i{0};i < SamplesToDo;++i)
    {
        /* Y = 0.795968*D - 0.676392*T + j(0.186633*S) */
        youtput[i] = 0.795968f*mD[i] - 0.676392f*mT[i] + 0.186633f*youtput[i];
    }

    if(OutSamples.size() > 3)
    {
        auto zoutput = al::span{OutSamples[3]};
        /* Z = 1.023332*Q */
        for(std::size_t i{0};i < SamplesToDo;++i)
            zoutput[i] = 1.023332f*mQ[i];
    }

    std::copy(mS.begin()+SamplesToDo, mS.begin()+SamplesToDo+sFilterDelay, mS.begin());
    std::copy(mD.begin()+SamplesToDo, mD.begin()+SamplesToDo+sFilterDelay, mD.begin());
    std::copy(mT.begin()+SamplesToDo, mT.begin()+SamplesToDo+sFilterDelay, mT.begin());
    std::copy(mQ.begin()+SamplesToDo, mQ.begin()+SamplesToDo+sFilterDelay, mQ.begin());
}

/* This is an alternative equation for decoding 2-channel UHJ. Not sure what
 * the intended benefit is over the above equation as this slightly reduces the
 * amount of the original left response and has more of the phase-shifted
 * forward response on the left response.
 *
 * This decoding is done as:
 *
 * S = Left + Right
 * D = Left - Right
 *
 * W = 0.981530*S + j*0.163585*D
 * X = 0.418504*S - j*0.828347*D
 * Y = 0.762956*D + j*0.384230*S
 *
 * where j is a +90 degree phase shift.
 *
 * NOTE: As above, S and D should not be halved. The only consequence of
 * halving here is merely a -6dB reduction in output, but it's still incorrect.
 */
void UhjDecoder::decode2(const al::span<const float> InSamples,
    const al::span<FloatBufferLine> OutSamples, const std::size_t SamplesToDo)
{
    ASSUME(SamplesToDo > 0);

    auto woutput = al::span{OutSamples[0]};
    auto xoutput = al::span{OutSamples[1]};
    auto youtput = al::span{OutSamples[2]};

    /* S = Left + Right */
    for(std::size_t i{0};i < SamplesToDo;++i)
        mS[sFilterDelay+i] = InSamples[i*2 + 0] + InSamples[i*2 + 1];

    /* D = Left - Right */
    for(std::size_t i{0};i < SamplesToDo;++i)
        mD[sFilterDelay+i] = InSamples[i*2 + 0] - InSamples[i*2 + 1];

    /* Precompute j*D and store in xoutput. */
    auto tmpiter = std::copy(mDTHistory.cbegin(), mDTHistory.cend(), mTemp.begin());
    std::copy_n(mD.cbegin(), SamplesToDo+sFilterDelay, tmpiter);
    std::copy_n(mTemp.cbegin()+SamplesToDo, mDTHistory.size(), mDTHistory.begin());
    PShift.process(xoutput.first(SamplesToDo), mTemp);

    for(std::size_t i{0};i < SamplesToDo;++i)
    {
        /* W = 0.981530*S + j*0.163585*D */
        woutput[i] = 0.981530f*mS[i] + 0.163585f*xoutput[i];
        /* X = 0.418504*S - j*0.828347*D */
        xoutput[i] = 0.418504f*mS[i] - 0.828347f*xoutput[i];
    }

    /* Precompute j*S and store in youtput. */
    tmpiter = std::copy(mSHistory.cbegin(), mSHistory.cend(), mTemp.begin());
    std::copy_n(mS.cbegin(), SamplesToDo+sFilterDelay, tmpiter);
    std::copy_n(mTemp.cbegin()+SamplesToDo, mSHistory.size(), mSHistory.begin());
    PShift.process(youtput.first(SamplesToDo), mTemp);

    for(std::size_t i{0};i < SamplesToDo;++i)
    {
        /* Y = 0.762956*D + j*0.384230*S */
        youtput[i] = 0.762956f*mD[i] + 0.384230f*youtput[i];
    }

    std::copy(mS.begin()+SamplesToDo, mS.begin()+SamplesToDo+sFilterDelay, mS.begin());
    std::copy(mD.begin()+SamplesToDo, mD.begin()+SamplesToDo+sFilterDelay, mD.begin());
}


int main(al::span<std::string_view> args)
{
    if(args.size() < 2 || args[1] == "-h" || args[1] == "--help")
    {
        printf("Usage: %.*s <[options] filename.wav...>\n\n"
            "  Options:\n"
            "    --general      Use the general equations for 2-channel UHJ (default).\n"
            "    --alternative  Use the alternative equations for 2-channel UHJ.\n"
            "\n"
            "Note: When decoding 2-channel UHJ to an .amb file, the result should not use\n"
            "the normal B-Format shelf filters! Only 3- and 4-channel UHJ can accurately\n"
            "reconstruct the original B-Format signal.",
            al::sizei(args[0]), args[0].data());
        return 1;
    }

    std::size_t num_files{0}, num_decoded{0};
    bool use_general{true};
    for(size_t fidx{1};fidx < args.size();++fidx)
    {
        if(args[fidx] == "--general")
        {
            use_general = true;
            continue;
        }
        if(args[fidx] == "--alternative")
        {
            use_general = false;
            continue;
        }
        ++num_files;
        SF_INFO ininfo{};
        SndFilePtr infile{sf_open(std::string{args[fidx]}.c_str(), SFM_READ, &ininfo)};
        if(!infile)
        {
            fprintf(stderr, "Failed to open %.*s\n", al::sizei(args[fidx]), args[fidx].data());
            continue;
        }
        if(sf_command(infile.get(), SFC_WAVEX_GET_AMBISONIC, nullptr, 0) == SF_AMBISONIC_B_FORMAT)
        {
            fprintf(stderr, "%.*s is already B-Format\n", al::sizei(args[fidx]),
                args[fidx].data());
            continue;
        }
        uint outchans{};
        if(ininfo.channels == 2)
            outchans = 3;
        else if(ininfo.channels == 3 || ininfo.channels == 4)
            outchans = static_cast<uint>(ininfo.channels);
        else
        {
            fprintf(stderr, "%.*s is not a 2-, 3-, or 4-channel file\n", al::sizei(args[fidx]),
                args[fidx].data());
            continue;
        }
        printf("Converting %.*s from %d-channel UHJ%s...\n", al::sizei(args[fidx]),
            args[fidx].data(), ininfo.channels,
            (ininfo.channels == 2) ? use_general ? " (general)" : " (alternative)" : "");

        std::string outname{args[fidx]};
        auto lastslash = outname.find_last_of('/');
        if(lastslash != std::string::npos)
            outname.erase(0, lastslash+1);
        auto lastdot = outname.find_last_of('.');
        if(lastdot != std::string::npos)
            outname.resize(lastdot+1);
        outname += "amb";

        FilePtr outfile{fopen(outname.c_str(), "wb")};
        if(!outfile)
        {
            fprintf(stderr, "Failed to create %s\n", outname.c_str());
            continue;
        }

        fputs("RIFF", outfile.get());
        fwrite32le(0xFFFFFFFF, outfile.get()); // 'RIFF' header len; filled in at close

        fputs("WAVE", outfile.get());

        fputs("fmt ", outfile.get());
        fwrite32le(40, outfile.get()); // 'fmt ' header len; 40 bytes for EXTENSIBLE

        // 16-bit val, format type id (extensible: 0xFFFE)
        fwrite16le(0xFFFE, outfile.get());
        // 16-bit val, channel count
        fwrite16le(static_cast<ushort>(outchans), outfile.get());
        // 32-bit val, frequency
        fwrite32le(static_cast<uint>(ininfo.samplerate), outfile.get());
        // 32-bit val, bytes per second
        fwrite32le(static_cast<uint>(ininfo.samplerate)*outchans*uint{sizeof(float)}, outfile.get());
        // 16-bit val, frame size
        fwrite16le(static_cast<ushort>(sizeof(float)*outchans), outfile.get());
        // 16-bit val, bits per sample
        fwrite16le(static_cast<ushort>(sizeof(float)*8), outfile.get());
        // 16-bit val, extra byte count
        fwrite16le(22, outfile.get());
        // 16-bit val, valid bits per sample
        fwrite16le(static_cast<ushort>(sizeof(float)*8), outfile.get());
        // 32-bit val, channel mask
        fwrite32le(0, outfile.get());
        // 16 byte GUID, sub-type format
        fwrite(SUBTYPE_BFORMAT_FLOAT.data(), 1, SUBTYPE_BFORMAT_FLOAT.size(), outfile.get());

        fputs("data", outfile.get());
        fwrite32le(0xFFFFFFFF, outfile.get()); // 'data' header len; filled in at close
        if(ferror(outfile.get()))
        {
            fprintf(stderr, "Error writing wave file header: %s (%d)\n",
                std::generic_category().message(errno).c_str(), errno);
            continue;
        }

        auto DataStart = ftell(outfile.get());

        auto decoder = std::make_unique<UhjDecoder>();
        auto inmem = std::vector<float>(size_t{BufferLineSize}*static_cast<uint>(ininfo.channels));
        auto decmem = al::vector<std::array<float,BufferLineSize>, 16>(outchans);
        auto outmem = std::vector<byte4>(size_t{BufferLineSize}*outchans);

        /* A number of initial samples need to be skipped to cut the lead-in
         * from the all-pass filter delay. The same number of samples need to
         * be fed through the decoder after reaching the end of the input file
         * to ensure none of the original input is lost.
         */
        std::size_t LeadIn{UhjDecoder::sFilterDelay};
        sf_count_t LeadOut{UhjDecoder::sFilterDelay};
        while(LeadOut > 0)
        {
            sf_count_t sgot{sf_readf_float(infile.get(), inmem.data(), BufferLineSize)};
            sgot = std::max<sf_count_t>(sgot, 0);
            if(sgot < BufferLineSize)
            {
                const sf_count_t remaining{std::min(BufferLineSize - sgot, LeadOut)};
                std::fill_n(inmem.begin() + sgot*ininfo.channels, remaining*ininfo.channels, 0.0f);
                sgot += remaining;
                LeadOut -= remaining;
            }

            auto got = static_cast<std::size_t>(sgot);
            if(ininfo.channels > 2 || use_general)
                decoder->decode(inmem, static_cast<uint>(ininfo.channels), decmem, got);
            else
                decoder->decode2(inmem, decmem, got);
            if(LeadIn >= got)
            {
                LeadIn -= got;
                continue;
            }

            got -= LeadIn;
            for(std::size_t i{0};i < got;++i)
            {
                /* Attenuate by -3dB for FuMa output levels. */
                constexpr auto inv_sqrt2 = static_cast<float>(1.0/al::numbers::sqrt2);
                for(std::size_t j{0};j < outchans;++j)
                    outmem[i*outchans + j] = f32AsLEBytes(decmem[j][LeadIn+i] * inv_sqrt2);
            }
            LeadIn = 0;

            std::size_t wrote{fwrite(outmem.data(), sizeof(byte4)*outchans, got, outfile.get())};
            if(wrote < got)
            {
                fprintf(stderr, "Error writing wave data: %s (%d)\n",
                    std::generic_category().message(errno).c_str(), errno);
                break;
            }
        }

        auto DataEnd = ftell(outfile.get());
        if(DataEnd > DataStart)
        {
            long dataLen{DataEnd - DataStart};
            if(fseek(outfile.get(), 4, SEEK_SET) == 0)
                fwrite32le(static_cast<uint>(DataEnd-8), outfile.get()); // 'WAVE' header len
            if(fseek(outfile.get(), DataStart-4, SEEK_SET) == 0)
                fwrite32le(static_cast<uint>(dataLen), outfile.get()); // 'data' header len
        }
        fflush(outfile.get());
        ++num_decoded;
    }
    if(num_decoded == 0)
        fprintf(stderr, "Failed to decode any input files\n");
    else if(num_decoded < num_files)
        fprintf(stderr, "Decoded %zu of %zu files\n", num_decoded, num_files);
    else
        printf("Decoded %zu file%s\n", num_decoded, (num_decoded==1)?"":"s");
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
