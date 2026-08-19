/*
 * OpenAL Source Play Example
 *
 * Copyright (c) 2017 by Chris Robinson <chris.kcat@gmail.com>
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

/* This file contains an example for playing a sound buffer. */

#include <assert.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

#include "sndfile.h"

#include "AL/al.h"
#include "AL/alext.h"

#include "common/alhelpers.h"

#include "win_main_utf8.h"


enum FormatType {
    Int16,
    Float,
    IMA4,
    MSADPCM
};

/* LoadBuffer loads the named audio file into an OpenAL buffer object, and
 * returns the new buffer ID.
 */
static ALuint LoadSound(const char *filename)
{
    enum FormatType sample_format = Int16;
    ALint byteblockalign = 0;
    ALint splblockalign = 0;
    sf_count_t num_frames;
    ALenum err, format;
    ALsizei num_bytes;
    SNDFILE *sndfile;
    SF_INFO sfinfo;
    ALuint buffer;
    void *membuf;

    /* Open the audio file and check that it's usable. */
    sndfile = sf_open(filename, SFM_READ, &sfinfo);
    if(!sndfile)
    {
        fprintf(stderr, "Could not open audio in %s: %s\n", filename, sf_strerror(sndfile));
        return 0;
    }
    if(sfinfo.frames < 1)
    {
        fprintf(stderr, "Bad sample count in %s (%" PRId64 ")\n", filename, sfinfo.frames);
        sf_close(sndfile);
        return 0;
    }

    /* Detect a suitable format to load. Formats like Vorbis and Opus use float
     * natively, so load as float to avoid clipping when possible. Formats
     * larger than 16-bit can also use float to preserve a bit more precision.
     */
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
        if(alIsExtensionPresent("AL_EXT_FLOAT32"))
            sample_format = Float;
        break;
    case SF_FORMAT_IMA_ADPCM:
        /* ADPCM formats require setting a block alignment as specified in the
         * file, which needs to be read from the wave 'fmt ' chunk manually
         * since libsndfile doesn't provide it in a format-agnostic way.
         */
        if(sfinfo.channels <= 2 && (sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV
            && alIsExtensionPresent("AL_EXT_IMA4")
            && alIsExtensionPresent("AL_SOFT_block_alignment"))
            sample_format = IMA4;
        break;
    case SF_FORMAT_MS_ADPCM:
        if(sfinfo.channels <= 2 && (sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV
            && alIsExtensionPresent("AL_SOFT_MSADPCM")
            && alIsExtensionPresent("AL_SOFT_block_alignment"))
            sample_format = MSADPCM;
        break;
    }

    if(sample_format == IMA4 || sample_format == MSADPCM)
    {
        /* For ADPCM, lookup the wave file's "fmt " chunk, which is a
         * WAVEFORMATEX-based structure for the audio format.
         */
        SF_CHUNK_INFO inf = { "fmt ", 4, 0, NULL };
        SF_CHUNK_ITERATOR *iter = sf_get_chunk_iterator(sndfile, &inf);

        /* If there's an issue getting the chunk or block alignment, load as
         * 16-bit and have libsndfile do the conversion.
         */
        if(!iter || sf_get_chunk_size(iter, &inf) != SF_ERR_NO_ERROR || inf.datalen < 14)
            sample_format = Int16;
        else
        {
            ALubyte *fmtbuf = calloc(inf.datalen, 1);
            inf.data = fmtbuf;
            if(sf_get_chunk_data(iter, &inf) != SF_ERR_NO_ERROR)
                sample_format = Int16;
            else
            {
                /* Read the nBlockAlign field, and convert from bytes- to
                 * samples-per-block (verifying it's valid by converting back
                 * and comparing to the original value).
                 */
                byteblockalign = fmtbuf[12] | (fmtbuf[13]<<8);
                if(sample_format == IMA4)
                {
                    splblockalign = (byteblockalign/sfinfo.channels - 4)/4*8 + 1;
                    if(splblockalign < 1
                        || ((splblockalign-1)/2 + 4)*sfinfo.channels != byteblockalign)
                        sample_format = Int16;
                }
                else
                {
                    splblockalign = (byteblockalign/sfinfo.channels - 7)*2 + 2;
                    if(splblockalign < 2
                        || ((splblockalign-2)/2 + 7)*sfinfo.channels != byteblockalign)
                        sample_format = Int16;
                }
            }
            free(fmtbuf);
        }
    }

    if(sample_format == Int16)
    {
        splblockalign = 1;
        byteblockalign = sfinfo.channels * 2;
    }
    else if(sample_format == Float)
    {
        splblockalign = 1;
        byteblockalign = sfinfo.channels * 4;
    }

    /* Figure out the OpenAL format from the file and desired sample type. */
    format = AL_NONE;
    if(sfinfo.channels == 1)
    {
        if(sample_format == Int16)
            format = AL_FORMAT_MONO16;
        else if(sample_format == Float)
            format = AL_FORMAT_MONO_FLOAT32;
        else if(sample_format == IMA4)
            format = AL_FORMAT_MONO_IMA4;
        else if(sample_format == MSADPCM)
            format = AL_FORMAT_MONO_MSADPCM_SOFT;
    }
    else if(sfinfo.channels == 2)
    {
        if(sample_format == Int16)
            format = AL_FORMAT_STEREO16;
        else if(sample_format == Float)
            format = AL_FORMAT_STEREO_FLOAT32;
        else if(sample_format == IMA4)
            format = AL_FORMAT_STEREO_IMA4;
        else if(sample_format == MSADPCM)
            format = AL_FORMAT_STEREO_MSADPCM_SOFT;
    }
    else if(sfinfo.channels == 3)
    {
        if(sf_command(sndfile, SFC_WAVEX_GET_AMBISONIC, NULL, 0) == SF_AMBISONIC_B_FORMAT)
        {
            if(sample_format == Int16)
                format = AL_FORMAT_BFORMAT2D_16;
            else if(sample_format == Float)
                format = AL_FORMAT_BFORMAT2D_FLOAT32;
        }
    }
    else if(sfinfo.channels == 4)
    {
        if(sf_command(sndfile, SFC_WAVEX_GET_AMBISONIC, NULL, 0) == SF_AMBISONIC_B_FORMAT)
        {
            if(sample_format == Int16)
                format = AL_FORMAT_BFORMAT3D_16;
            else if(sample_format == Float)
                format = AL_FORMAT_BFORMAT3D_FLOAT32;
        }
    }
    if(!format)
    {
        fprintf(stderr, "Unsupported channel count: %d\n", sfinfo.channels);
        sf_close(sndfile);
        return 0;
    }

    if(sfinfo.frames/splblockalign > (sf_count_t)(INT_MAX/byteblockalign))
    {
        fprintf(stderr, "Too many samples in %s (%" PRId64 ")\n", filename, sfinfo.frames);
        sf_close(sndfile);
        return 0;
    }

    /* Decode the whole audio file to a buffer. */
    membuf = malloc((size_t)(sfinfo.frames / splblockalign * byteblockalign));

    if(sample_format == Int16)
        num_frames = sf_readf_short(sndfile, membuf, sfinfo.frames);
    else if(sample_format == Float)
        num_frames = sf_readf_float(sndfile, membuf, sfinfo.frames);
    else
    {
        sf_count_t count = sfinfo.frames / splblockalign * byteblockalign;
        num_frames = sf_read_raw(sndfile, membuf, count);
        if(num_frames > 0)
            num_frames = num_frames / byteblockalign * splblockalign;
    }
    if(num_frames < 1)
    {
        free(membuf);
        sf_close(sndfile);
        fprintf(stderr, "Failed to read samples in %s (%" PRId64 ")\n", filename, num_frames);
        return 0;
    }
    num_bytes = (ALsizei)(num_frames / splblockalign * byteblockalign);

    printf("Loading: %s (%s, %dhz)\n", filename, FormatName(format), sfinfo.samplerate);
    fflush(stdout);

    /* Buffer the audio data into a new buffer object, then free the data and
     * close the file.
     */
    buffer = 0;
    alGenBuffers(1, &buffer);
    if(splblockalign > 1)
        alBufferi(buffer, AL_UNPACK_BLOCK_ALIGNMENT_SOFT, splblockalign);
    alBufferData(buffer, format, membuf, num_bytes, sfinfo.samplerate);

    free(membuf);
    sf_close(sndfile);

    /* Check if an error occurred, and clean up if so. */
    err = alGetError();
    if(err != AL_NO_ERROR)
    {
        fprintf(stderr, "OpenAL Error: %s\n", alGetString(err));
        if(buffer && alIsBuffer(buffer))
            alDeleteBuffers(1, &buffer);
        return 0;
    }

    return buffer;
}


int main(int argc, char **argv)
{
    ALuint source, buffer;
    ALfloat offset;
    ALenum state;

    /* Print out usage if no arguments were specified */
    if(argc < 2)
    {
        fprintf(stderr, "Usage: %s [-device <name>] <filename>\n", argv[0]);
        return 1;
    }

    /* Initialize OpenAL. */
    argv++; argc--;
    if(InitAL(&argv, &argc) != 0)
        return 1;

    /* Load the sound into a buffer. */
    buffer = LoadSound(argv[0]);
    if(!buffer)
    {
        CloseAL();
        return 1;
    }

    /* Create the source to play the sound with. */
    source = 0;
    alGenSources(1, &source);
    alSourcei(source, AL_BUFFER, (ALint)buffer);
    assert(alGetError()==AL_NO_ERROR && "Failed to setup sound source");

    /* Play the sound until it finishes. */
    alSourcePlay(source);
    do {
        al_nssleep(10000000);
        alGetSourcei(source, AL_SOURCE_STATE, &state);

        /* Get the source offset. */
        alGetSourcef(source, AL_SEC_OFFSET, &offset);
        printf("\rOffset: %f  ", offset);
        fflush(stdout);
    } while(alGetError() == AL_NO_ERROR && state == AL_PLAYING);
    printf("\n");

    /* All done. Delete resources, and close down OpenAL. */
    alDeleteSources(1, &source);
    alDeleteBuffers(1, &buffer);

    CloseAL();

    return 0;
}
