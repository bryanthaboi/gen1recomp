/*
 * OpenAL Direct Context Example
 *
 * Copyright (c) 2024 by Chris Robinson <chris.kcat@gmail.com>
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

/* This file contains an example for playing a sound buffer with the Direct API
 * extension.
 */

#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdio>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "sndfile.h"

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/alext.h"

#include "alspan.h"
#include "common/alhelpers.h"

#include "win_main_utf8.h"

namespace {

/* On Windows when using Creative's router, we need to override the ALC
 * functions and access the driver functions directly. This isn't needed when
 * not using the router, or on other OSs.
 */
LPALCOPENDEVICE p_alcOpenDevice{alcOpenDevice};
LPALCCLOSEDEVICE p_alcCloseDevice{alcCloseDevice};
LPALCISEXTENSIONPRESENT p_alcIsExtensionPresent{alcIsExtensionPresent};
LPALCCREATECONTEXT p_alcCreateContext{alcCreateContext};
LPALCDESTROYCONTEXT p_alcDestroyContext{alcDestroyContext};
LPALCGETPROCADDRESS p_alcGetProcAddress{alcGetProcAddress};


LPALGETSTRINGDIRECT alGetStringDirect{};
LPALGETERRORDIRECT alGetErrorDirect{};
LPALISEXTENSIONPRESENTDIRECT alIsExtensionPresentDirect{};

LPALGENBUFFERSDIRECT alGenBuffersDirect{};
LPALDELETEBUFFERSDIRECT alDeleteBuffersDirect{};
LPALISBUFFERDIRECT alIsBufferDirect{};
LPALBUFFERIDIRECT alBufferiDirect{};
LPALBUFFERDATADIRECT alBufferDataDirect{};

LPALGENSOURCESDIRECT alGenSourcesDirect{};
LPALDELETESOURCESDIRECT alDeleteSourcesDirect{};
LPALSOURCEIDIRECT alSourceiDirect{};
LPALGETSOURCEIDIRECT alGetSourceiDirect{};
LPALGETSOURCEFDIRECT alGetSourcefDirect{};
LPALSOURCEPLAYDIRECT alSourcePlayDirect{};


struct SndFileDeleter {
    void operator()(SNDFILE *sndfile) { sf_close(sndfile); }
};
using SndFilePtr = std::unique_ptr<SNDFILE,SndFileDeleter>;

enum class FormatType {
    Int16,
    Float,
    IMA4,
    MSADPCM
};

/* LoadBuffer loads the named audio file into an OpenAL buffer object, and
 * returns the new buffer ID.
 */
ALuint LoadSound(ALCcontext *context, const std::string_view filename)
{
    /* Open the audio file and check that it's usable. */
    SF_INFO sfinfo{};
    SndFilePtr sndfile{sf_open(std::string{filename}.c_str(), SFM_READ, &sfinfo)};
    if(!sndfile)
    {
        std::cerr<< "Could not open audio in "<<filename<<": "<<sf_strerror(sndfile.get())<<"\n";
        return 0;
    }
    if(sfinfo.frames < 1)
    {
        std::cerr<< "Bad sample count in "<<filename<<" ("<<sfinfo.frames<<")\n";
        return 0;
    }

    /* Detect a suitable format to load. Formats like Vorbis and Opus use float
     * natively, so load as float to avoid clipping when possible. Formats
     * larger than 16-bit can also use float to preserve a bit more precision.
     */
    FormatType sample_format{FormatType::Int16};
    switch((sfinfo.format&SF_FORMAT_SUBMASK))
    {
    case SF_FORMAT_PCM_24:
    case SF_FORMAT_PCM_32:
    case SF_FORMAT_FLOAT:
    case SF_FORMAT_DOUBLE:
    case SF_FORMAT_VORBIS:
    case SF_FORMAT_OPUS:
    case SF_FORMAT_ALAC_20:
    case SF_FORMAT_ALAC_24:
    case SF_FORMAT_ALAC_32:
    case 0x0080/*SF_FORMAT_MPEG_LAYER_I*/:
    case 0x0081/*SF_FORMAT_MPEG_LAYER_II*/:
    case 0x0082/*SF_FORMAT_MPEG_LAYER_III*/:
        if(alIsExtensionPresentDirect(context, "AL_EXT_FLOAT32"))
            sample_format = FormatType::Float;
        break;
    case SF_FORMAT_IMA_ADPCM:
        /* ADPCM formats require setting a block alignment as specified in the
         * file, which needs to be read from the wave 'fmt ' chunk manually
         * since libsndfile doesn't provide it in a format-agnostic way.
         */
        if(sfinfo.channels <= 2 && (sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV
            && alIsExtensionPresentDirect(context, "AL_EXT_IMA4")
            && alIsExtensionPresentDirect(context, "AL_SOFT_block_alignment"))
            sample_format = FormatType::IMA4;
        break;
    case SF_FORMAT_MS_ADPCM:
        if(sfinfo.channels <= 2 && (sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV
            && alIsExtensionPresentDirect(context, "AL_SOFT_MSADPCM")
            && alIsExtensionPresentDirect(context, "AL_SOFT_block_alignment"))
            sample_format = FormatType::MSADPCM;
        break;
    }

    ALint byteblockalign{0}, splblockalign{0};
    if(sample_format == FormatType::IMA4 || sample_format == FormatType::MSADPCM)
    {
        /* For ADPCM, lookup the wave file's "fmt " chunk, which is a
         * WAVEFORMATEX-based structure for the audio format.
         */
        SF_CHUNK_INFO inf{"fmt ", 4, 0, nullptr};
        SF_CHUNK_ITERATOR *iter{sf_get_chunk_iterator(sndfile.get(), &inf)};

        /* If there's an issue getting the chunk or block alignment, load as
         * 16-bit and have libsndfile do the conversion.
         */
        if(!iter || sf_get_chunk_size(iter, &inf) != SF_ERR_NO_ERROR || inf.datalen < 14)
            sample_format = FormatType::Int16;
        else
        {
            auto fmtbuf = std::vector<ALubyte>(inf.datalen, ALubyte{0});
            inf.data = fmtbuf.data();
            if(sf_get_chunk_data(iter, &inf) != SF_ERR_NO_ERROR)
                sample_format = FormatType::Int16;
            else
            {
                /* Read the nBlockAlign field, and convert from bytes- to
                 * samples-per-block (verifying it's valid by converting back
                 * and comparing to the original value).
                 */
                byteblockalign = fmtbuf[12] | (fmtbuf[13]<<8);
                if(sample_format == FormatType::IMA4)
                {
                    splblockalign = (byteblockalign/sfinfo.channels - 4)/4*8 + 1;
                    if(splblockalign < 1
                        || ((splblockalign-1)/2 + 4)*sfinfo.channels != byteblockalign)
                        sample_format = FormatType::Int16;
                }
                else if(sample_format == FormatType::MSADPCM)
                {
                    splblockalign = (byteblockalign/sfinfo.channels - 7)*2 + 2;
                    if(splblockalign < 2
                        || ((splblockalign-2)/2 + 7)*sfinfo.channels != byteblockalign)
                        sample_format = FormatType::Int16;
                }
                else
                    sample_format = FormatType::Int16;
            }
        }
    }

    if(sample_format == FormatType::Int16)
    {
        splblockalign = 1;
        byteblockalign = sfinfo.channels * 2;
    }
    else if(sample_format == FormatType::Float)
    {
        splblockalign = 1;
        byteblockalign = sfinfo.channels * 4;
    }

    /* Figure out the OpenAL format from the file and desired sample type. */
    ALenum format{AL_NONE};
    if(sfinfo.channels == 1)
    {
        if(sample_format == FormatType::Int16)
            format = AL_FORMAT_MONO16;
        else if(sample_format == FormatType::Float)
            format = AL_FORMAT_MONO_FLOAT32;
        else if(sample_format == FormatType::IMA4)
            format = AL_FORMAT_MONO_IMA4;
        else if(sample_format == FormatType::MSADPCM)
            format = AL_FORMAT_MONO_MSADPCM_SOFT;
    }
    else if(sfinfo.channels == 2)
    {
        if(sample_format == FormatType::Int16)
            format = AL_FORMAT_STEREO16;
        else if(sample_format == FormatType::Float)
            format = AL_FORMAT_STEREO_FLOAT32;
        else if(sample_format == FormatType::IMA4)
            format = AL_FORMAT_STEREO_IMA4;
        else if(sample_format == FormatType::MSADPCM)
            format = AL_FORMAT_STEREO_MSADPCM_SOFT;
    }
    else if(sfinfo.channels == 3)
    {
        if(sf_command(sndfile.get(), SFC_WAVEX_GET_AMBISONIC, nullptr, 0) == SF_AMBISONIC_B_FORMAT)
        {
            if(sample_format == FormatType::Int16)
                format = AL_FORMAT_BFORMAT2D_16;
            else if(sample_format == FormatType::Float)
                format = AL_FORMAT_BFORMAT2D_FLOAT32;
        }
    }
    else if(sfinfo.channels == 4)
    {
        if(sf_command(sndfile.get(), SFC_WAVEX_GET_AMBISONIC, nullptr, 0) == SF_AMBISONIC_B_FORMAT)
        {
            if(sample_format == FormatType::Int16)
                format = AL_FORMAT_BFORMAT3D_16;
            else if(sample_format == FormatType::Float)
                format = AL_FORMAT_BFORMAT3D_FLOAT32;
        }
    }
    if(!format)
    {
        std::cerr<< "Unsupported channel count: "<<sfinfo.channels<<"\n";
        return 0;
    }

    if(sfinfo.frames/splblockalign > sf_count_t{std::numeric_limits<int>::max()}/byteblockalign)
    {
        std::cerr<< "Too many sample frames in "<<filename<<" ("<<sfinfo.frames<<")\n";
        return 0;
    }

    /* Decode the whole audio file to a buffer. */
    auto membuf = std::vector<std::byte>(static_cast<size_t>(sfinfo.frames / splblockalign
        * byteblockalign));

    sf_count_t num_frames{};
    if(sample_format == FormatType::Int16)
        num_frames = sf_readf_short(sndfile.get(), reinterpret_cast<short*>(membuf.data()),
            sfinfo.frames);
    else if(sample_format == FormatType::Float)
        num_frames = sf_readf_float(sndfile.get(), reinterpret_cast<float*>(membuf.data()),
            sfinfo.frames);
    else
    {
        const sf_count_t count{sfinfo.frames / splblockalign * byteblockalign};
        num_frames = sf_read_raw(sndfile.get(), membuf.data(), count);
        if(num_frames > 0)
            num_frames = num_frames / byteblockalign * splblockalign;
    }
    if(num_frames < 1)
    {
        std::cerr<< "Failed to read samples in "<<filename<<" ("<<num_frames<<")\n";
        return 0;
    }

    const auto num_bytes = static_cast<ALsizei>(num_frames / splblockalign * byteblockalign);

    std::cout<< "Loading: "<<filename<<" ("<<FormatName(format)<<", "<<sfinfo.samplerate<<"hz)\n"
        <<std::flush;

    ALuint buffer{};
    alGenBuffersDirect(context, 1, &buffer);
    if(splblockalign > 1)
        alBufferiDirect(context, buffer, AL_UNPACK_BLOCK_ALIGNMENT_SOFT, splblockalign);
    alBufferDataDirect(context, buffer, format, membuf.data(), num_bytes, sfinfo.samplerate);

    /* Check if an error occurred, and clean up if so. */
    if(ALenum err{alGetErrorDirect(context)}; err != AL_NO_ERROR)
    {
        std::cerr<< "OpenAL Error: "<<alGetStringDirect(context, err)<<"\n";
        if(buffer && alIsBufferDirect(context, buffer))
            alDeleteBuffersDirect(context, 1, &buffer);
        return 0;
    }

    return buffer;
}


int main(al::span<std::string_view> args)
{
    /* Print out usage if no arguments were specified */
    if(args.size() < 2)
    {
        std::cerr<< "Usage: "<<args[0]<<" [-device <name>] <filename>\n";
        return 1;
    }

    /* Initialize OpenAL. */
    args = args.subspan(1);

    ALCdevice *device{};
    if(args.size() > 1 && args[0] == "-device")
    {
        device = p_alcOpenDevice(std::string{args[1]}.c_str());
        if(!device)
            std::cerr<< "Failed to open \""<<args[1]<<"\", trying default\n";
        args = args.subspan(2);
    }
    if(!device)
        device = p_alcOpenDevice(nullptr);
    if(!device)
    {
        std::cerr<< "Could not open a device!\n";
        return 1;
    }

    if(!p_alcIsExtensionPresent(device, "ALC_EXT_direct_context"))
    {
        std::cerr<< "ALC_EXT_direct_context not supported on device\n";
        p_alcCloseDevice(device);
        return 1;
    }

    /* On Windows with Creative's router, the device needs to be bootstrapped
     * to use it through the driver directly. Otherwise the Direct functions
     * aren't able to recognize the router's ALCcontexts. To handle this, we
     * use the router's alcOpenDevice, alcGetProcAddress, and alcCloseDevice
     * functions to open the device with the router, get the device driver's
     * alcGetProcAddress2 function, and close the device with the router. Then
     * call alcGetProcAddress2 with the null device handle to get the driver's
     * functions. Afterward, we can open the device back up using the driver
     * functions directly and continue on.
     *
     * Note that this will allow using other devices from the same driver just
     * fine, but switching to a device on another driver will require using the
     * original functions from the router (and require re-bootstrapping to use
     * that driver's functions, if applicable). If controlling multiple devices
     * with Direct functions from separate drivers simultaneously is desired, a
     * good strategy may be to associate the driver's ALC and Direct functions
     * with the ALCdevice and ALCcontext handles created from them.
     *
     * This is all unnecessary when not using Creative's router, including on
     * non-Windows OSs or when using OpenAL Soft's router, where the original
     * ALC functions can be used as normal.
     */
    {
        const std::string devname{alcGetString(device, ALC_ALL_DEVICES_SPECIFIER)};
        auto p_alcGetProcAddress2 = reinterpret_cast<LPALCGETPROCADDRESS2>(
            p_alcGetProcAddress(device, "alcGetProcAddress2"));
        p_alcCloseDevice(device);

        /* Load the driver-specific ALC functions we'll be using. */
#define LOAD_PROC(N) p_##N = reinterpret_cast<decltype(p_##N)>(p_alcGetProcAddress2(nullptr, #N))
        LOAD_PROC(alcOpenDevice);
        LOAD_PROC(alcCloseDevice);
        LOAD_PROC(alcIsExtensionPresent);
        LOAD_PROC(alcGetProcAddress);
        LOAD_PROC(alcCreateContext);
        LOAD_PROC(alcDestroyContext);
        LOAD_PROC(alcGetProcAddress);
#undef LOAD_PROC
        device = p_alcOpenDevice(devname.c_str());
        assert(device != nullptr);
    }

    /* Load the Direct API functions we're using. */
#define LOAD_PROC(N) N = reinterpret_cast<decltype(N)>(p_alcGetProcAddress(device, #N))
    LOAD_PROC(alGetStringDirect);
    LOAD_PROC(alGetErrorDirect);
    LOAD_PROC(alIsExtensionPresentDirect);

    LOAD_PROC(alGenBuffersDirect);
    LOAD_PROC(alDeleteBuffersDirect);
    LOAD_PROC(alIsBufferDirect);
    LOAD_PROC(alBufferiDirect);
    LOAD_PROC(alBufferDataDirect);

    LOAD_PROC(alGenSourcesDirect);
    LOAD_PROC(alDeleteSourcesDirect);
    LOAD_PROC(alSourceiDirect);
    LOAD_PROC(alGetSourceiDirect);
    LOAD_PROC(alGetSourcefDirect);
    LOAD_PROC(alSourcePlayDirect);
#undef LOAD_PROC

    /* Create the context. It doesn't need to be set as current to use with the
     * Direct API functions.
     */
    ALCcontext *context{p_alcCreateContext(device, nullptr)};
    if(!context)
    {
        p_alcCloseDevice(device);
        std::cerr<< "Could not create a context!\n";
        return 1;
    }

    /* Load the sound into a buffer. */
    const ALuint buffer{LoadSound(context, args[0])};
    if(!buffer)
    {
        p_alcDestroyContext(context);
        p_alcCloseDevice(device);
        return 1;
    }

    /* Create the source to play the sound with. */
    ALuint source{0};
    alGenSourcesDirect(context, 1, &source);
    alSourceiDirect(context, source, AL_BUFFER, static_cast<ALint>(buffer));
    assert(alGetErrorDirect(context)==AL_NO_ERROR && "Failed to setup sound source");

    /* Play the sound until it finishes. */
    alSourcePlayDirect(context, source);
    ALenum state{};
    do {
        al_nssleep(10000000);
        alGetSourceiDirect(context, source, AL_SOURCE_STATE, &state);

        /* Get the source offset. */
        ALfloat offset{};
        alGetSourcefDirect(context, source, AL_SEC_OFFSET, &offset);
        printf("\rOffset: %f  ", offset);
        fflush(stdout);
    } while(alGetErrorDirect(context) == AL_NO_ERROR && state == AL_PLAYING);
    printf("\n");

    /* All done. Delete resources, and close down OpenAL. */
    alDeleteSourcesDirect(context, 1, &source);
    alDeleteBuffersDirect(context, 1, &buffer);

    p_alcDestroyContext(context);
    p_alcCloseDevice(device);

    return 0;
}

} // namespace

int main(int argc, char **argv)
{
    assert(argc >= 0);
    auto args = std::vector<std::string_view>(static_cast<unsigned int>(argc));
    std::copy_n(argv, args.size(), args.begin());
    return main(al::span{args});
}
