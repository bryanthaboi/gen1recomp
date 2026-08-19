/*
 * OpenAL Audio Stream Example
 *
 * Copyright (c) 2011 by Chris Robinson <chris.kcat@gmail.com>
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

/* This file contains a relatively simple streaming audio player. */

#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sndfile.h"

#include "AL/al.h"
#include "AL/alext.h"

#include "common/alhelpers.h"

#include "win_main_utf8.h"


/* Define the number of buffers and buffer size (in milliseconds) to use. 4
 * buffers at 200ms each gives a nice per-chunk size, and lets the queue last
 * for almost one second.
 */
enum { NumBuffers = 4 };
enum { BufferMillisec = 200 };

typedef enum SampleType {
    Int16, Float, IMA4, MSADPCM
} SampleType;

typedef struct StreamPlayer {
    /* These are the buffers and source to play out through OpenAL with. */
    ALuint buffers[NumBuffers];
    ALuint source;

    /* Handle for the audio file */
    SNDFILE *sndfile;
    SF_INFO sfinfo;
    void *membuf;

    /* The sample type and block/frame size being read for the buffer. */
    SampleType sample_type;
    int byteblockalign;
    int sampleblockalign;
    int block_count;

    /* The format of the output stream (sample rate is in sfinfo) */
    ALenum format;
} StreamPlayer;

static StreamPlayer *NewPlayer(void);
static void DeletePlayer(StreamPlayer *player);
static int OpenPlayerFile(StreamPlayer *player, const char *filename);
static void ClosePlayerFile(StreamPlayer *player);
static int StartPlayer(StreamPlayer *player);
static int UpdatePlayer(StreamPlayer *player);

/* Creates a new player object, and allocates the needed OpenAL source and
 * buffer objects. Error checking is simplified for the purposes of this
 * example, and will cause an abort if needed.
 */
static StreamPlayer *NewPlayer(void)
{
    StreamPlayer *player;

    player = calloc(1, sizeof(*player));
    assert(player != NULL);

    /* Generate the buffers and source */
    alGenBuffers(NumBuffers, player->buffers);
    assert(alGetError() == AL_NO_ERROR && "Could not create buffers");

    alGenSources(1, &player->source);
    assert(alGetError() == AL_NO_ERROR && "Could not create source");

    /* Set parameters so mono sources play out the front-center speaker and
     * won't distance attenuate. */
    alSource3i(player->source, AL_POSITION, 0, 0, -1);
    alSourcei(player->source, AL_SOURCE_RELATIVE, AL_TRUE);
    alSourcei(player->source, AL_ROLLOFF_FACTOR, 0);
    assert(alGetError() == AL_NO_ERROR && "Could not set source parameters");

    return player;
}

/* Destroys a player object, deleting the source and buffers. No error handling
 * since these calls shouldn't fail with a properly-made player object. */
static void DeletePlayer(StreamPlayer *player)
{
    ClosePlayerFile(player);

    alDeleteSources(1, &player->source);
    alDeleteBuffers(NumBuffers, player->buffers);
    if(alGetError() != AL_NO_ERROR)
        fprintf(stderr, "Failed to delete object IDs\n");

    memset(player, 0, sizeof(*player)); /* NOLINT(clang-analyzer-security.insecureAPI.*) */
    free(player);
}


/* Opens the first audio stream of the named file. If a file is already open,
 * it will be closed first. */
static int OpenPlayerFile(StreamPlayer *player, const char *filename)
{
    int byteblockalign=0, splblockalign=0;

    ClosePlayerFile(player);

    /* Open the audio file and check that it's usable. */
    player->sndfile = sf_open(filename, SFM_READ, &player->sfinfo);
    if(!player->sndfile)
    {
        fprintf(stderr, "Could not open audio in %s: %s\n", filename, sf_strerror(NULL));
        return 0;
    }

    /* Detect a suitable format to load. Formats like Vorbis and Opus use float
     * natively, so load as float to avoid clipping when possible. Formats
     * larger than 16-bit can also use float to preserve a bit more precision.
     */
    switch((player->sfinfo.format&SF_FORMAT_SUBMASK))
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
            player->sample_type = Float;
        break;
    case SF_FORMAT_IMA_ADPCM:
        /* ADPCM formats require setting a block alignment as specified in the
         * file, which needs to be read from the wave 'fmt ' chunk manually
         * since libsndfile doesn't provide it in a format-agnostic way.
         */
        if(player->sfinfo.channels <= 2
            && (player->sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV
            && alIsExtensionPresent("AL_EXT_IMA4")
            && alIsExtensionPresent("AL_SOFT_block_alignment"))
            player->sample_type = IMA4;
        break;
    case SF_FORMAT_MS_ADPCM:
        if(player->sfinfo.channels <= 2
            && (player->sfinfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV
            && alIsExtensionPresent("AL_SOFT_MSADPCM")
            && alIsExtensionPresent("AL_SOFT_block_alignment"))
            player->sample_type = MSADPCM;
        break;
    }

    if(player->sample_type == IMA4 || player->sample_type == MSADPCM)
    {
        /* For ADPCM, lookup the wave file's "fmt " chunk, which is a
         * WAVEFORMATEX-based structure for the audio format.
         */
        SF_CHUNK_INFO inf = { "fmt ", 4, 0, NULL };
        SF_CHUNK_ITERATOR *iter = sf_get_chunk_iterator(player->sndfile, &inf);

        /* If there's an issue getting the chunk or block alignment, load as
         * 16-bit and have libsndfile do the conversion.
         */
        if(!iter || sf_get_chunk_size(iter, &inf) != SF_ERR_NO_ERROR || inf.datalen < 14)
            player->sample_type = Int16;
        else
        {
            ALubyte *fmtbuf = calloc(inf.datalen, 1);
            inf.data = fmtbuf;
            if(sf_get_chunk_data(iter, &inf) != SF_ERR_NO_ERROR)
                player->sample_type = Int16;
            else
            {
                /* Read the nBlockAlign field, and convert from bytes- to
                 * samples-per-block (verifying it's valid by converting back
                 * and comparing to the original value).
                 */
                byteblockalign = fmtbuf[12] | (fmtbuf[13]<<8);
                if(player->sample_type == IMA4)
                {
                    splblockalign = (byteblockalign/player->sfinfo.channels - 4)/4*8 + 1;
                    if(splblockalign < 1
                        || ((splblockalign-1)/2 + 4)*player->sfinfo.channels != byteblockalign)
                        player->sample_type = Int16;
                }
                else
                {
                    splblockalign = (byteblockalign/player->sfinfo.channels - 7)*2 + 2;
                    if(splblockalign < 2
                        || ((splblockalign-2)/2 + 7)*player->sfinfo.channels != byteblockalign)
                        player->sample_type = Int16;
                }
            }
            free(fmtbuf);
        }
    }

    if(player->sample_type == Int16)
    {
        player->sampleblockalign = 1;
        player->byteblockalign = player->sfinfo.channels * 2;
    }
    else if(player->sample_type == Float)
    {
        player->sampleblockalign = 1;
        player->byteblockalign = player->sfinfo.channels * 4;
    }
    else
    {
        player->sampleblockalign = splblockalign;
        player->byteblockalign = byteblockalign;
    }

    /* Figure out the OpenAL format from the file and desired sample type. */
    player->format = AL_NONE;
    if(player->sfinfo.channels == 1)
    {
        if(player->sample_type == Int16)
            player->format = AL_FORMAT_MONO16;
        else if(player->sample_type == Float)
            player->format = AL_FORMAT_MONO_FLOAT32;
        else if(player->sample_type == IMA4)
            player->format = AL_FORMAT_MONO_IMA4;
        else if(player->sample_type == MSADPCM)
            player->format = AL_FORMAT_MONO_MSADPCM_SOFT;
    }
    else if(player->sfinfo.channels == 2)
    {
        if(player->sample_type == Int16)
            player->format = AL_FORMAT_STEREO16;
        else if(player->sample_type == Float)
            player->format = AL_FORMAT_STEREO_FLOAT32;
        else if(player->sample_type == IMA4)
            player->format = AL_FORMAT_STEREO_IMA4;
        else if(player->sample_type == MSADPCM)
            player->format = AL_FORMAT_STEREO_MSADPCM_SOFT;
    }
    else if(player->sfinfo.channels == 3)
    {
        if(sf_command(player->sndfile, SFC_WAVEX_GET_AMBISONIC, NULL, 0) == SF_AMBISONIC_B_FORMAT)
        {
            if(player->sample_type == Int16)
                player->format = AL_FORMAT_BFORMAT2D_16;
            else if(player->sample_type == Float)
                player->format = AL_FORMAT_BFORMAT2D_FLOAT32;
        }
    }
    else if(player->sfinfo.channels == 4)
    {
        if(sf_command(player->sndfile, SFC_WAVEX_GET_AMBISONIC, NULL, 0) == SF_AMBISONIC_B_FORMAT)
        {
            if(player->sample_type == Int16)
                player->format = AL_FORMAT_BFORMAT3D_16;
            else if(player->sample_type == Float)
                player->format = AL_FORMAT_BFORMAT3D_FLOAT32;
        }
    }
    if(!player->format)
    {
        fprintf(stderr, "Unsupported channel count: %d\n", player->sfinfo.channels);
        sf_close(player->sndfile);
        player->sndfile = NULL;
        return 0;
    }

    player->block_count = player->sfinfo.samplerate / player->sampleblockalign;
    player->block_count = player->block_count * BufferMillisec / 1000;
    player->membuf = malloc((size_t)player->block_count * (size_t)player->byteblockalign);

    return 1;
}

/* Closes the audio file stream */
static void ClosePlayerFile(StreamPlayer *player)
{
    if(player->sndfile)
        sf_close(player->sndfile);
    player->sndfile = NULL;

    free(player->membuf);
    player->membuf = NULL;

    if(player->sampleblockalign > 1)
    {
        ALsizei i;
        for(i = 0;i < NumBuffers;i++)
            alBufferi(player->buffers[i], AL_UNPACK_BLOCK_ALIGNMENT_SOFT, 0);
        player->sampleblockalign = 0;
        player->byteblockalign = 0;
    }
}


/* Prebuffers some audio from the file, and starts playing the source */
static int StartPlayer(StreamPlayer *player)
{
    ALsizei i;

    /* Rewind the source position and clear the buffer queue */
    alSourceRewind(player->source);
    alSourcei(player->source, AL_BUFFER, 0);

    /* Fill the buffer queue */
    for(i = 0;i < NumBuffers;i++)
    {
        sf_count_t slen;

        /* Get some data to give it to the buffer */
        if(player->sample_type == Int16)
        {
            slen = sf_readf_short(player->sndfile, player->membuf,
                (sf_count_t)player->block_count * player->sampleblockalign);
            if(slen < 1) break;
            slen *= player->byteblockalign;
        }
        else if(player->sample_type == Float)
        {
            slen = sf_readf_float(player->sndfile, player->membuf,
                (sf_count_t)player->block_count * player->sampleblockalign);
            if(slen < 1) break;
            slen *= player->byteblockalign;
        }
        else
        {
            slen = sf_read_raw(player->sndfile, player->membuf,
                (sf_count_t)player->block_count * player->byteblockalign);
            if(slen > 0) slen -= slen%player->byteblockalign;
            if(slen < 1) break;
        }

        if(player->sampleblockalign > 1)
            alBufferi(player->buffers[i], AL_UNPACK_BLOCK_ALIGNMENT_SOFT,
                player->sampleblockalign);

        alBufferData(player->buffers[i], player->format, player->membuf, (ALsizei)slen,
            player->sfinfo.samplerate);
    }
    if(alGetError() != AL_NO_ERROR)
    {
        fprintf(stderr, "Error buffering for playback\n");
        return 0;
    }

    /* Now queue and start playback! */
    alSourceQueueBuffers(player->source, i, player->buffers);
    alSourcePlay(player->source);
    if(alGetError() != AL_NO_ERROR)
    {
        fprintf(stderr, "Error starting playback\n");
        return 0;
    }

    return 1;
}

static int UpdatePlayer(StreamPlayer *player)
{
    ALint processed, state;

    /* Get relevant source info */
    alGetSourcei(player->source, AL_SOURCE_STATE, &state);
    alGetSourcei(player->source, AL_BUFFERS_PROCESSED, &processed);
    if(alGetError() != AL_NO_ERROR)
    {
        fprintf(stderr, "Error checking source state\n");
        return 0;
    }

    /* Unqueue and handle each processed buffer */
    while(processed > 0)
    {
        ALuint bufid;
        sf_count_t slen;

        alSourceUnqueueBuffers(player->source, 1, &bufid);
        processed--;

        /* Read the next chunk of data, refill the buffer, and queue it
         * back on the source */
        if(player->sample_type == Int16)
        {
            slen = sf_readf_short(player->sndfile, player->membuf,
                (sf_count_t)player->block_count * player->sampleblockalign);
            if(slen > 0) slen *= player->byteblockalign;
        }
        else if(player->sample_type == Float)
        {
            slen = sf_readf_float(player->sndfile, player->membuf,
                (sf_count_t)player->block_count * player->sampleblockalign);
            if(slen > 0) slen *= player->byteblockalign;
        }
        else
        {
            slen = sf_read_raw(player->sndfile, player->membuf,
                (sf_count_t)player->block_count * player->byteblockalign);
            if(slen > 0) slen -= slen%player->byteblockalign;
        }

        if(slen > 0)
        {
            alBufferData(bufid, player->format, player->membuf, (ALsizei)slen,
                player->sfinfo.samplerate);
            alSourceQueueBuffers(player->source, 1, &bufid);
        }
        if(alGetError() != AL_NO_ERROR)
        {
            fprintf(stderr, "Error buffering data\n");
            return 0;
        }
    }

    /* Make sure the source hasn't underrun */
    if(state != AL_PLAYING && state != AL_PAUSED)
    {
        ALint queued;

        /* If no buffers are queued, playback is finished */
        alGetSourcei(player->source, AL_BUFFERS_QUEUED, &queued);
        if(queued == 0)
            return 0;

        alSourcePlay(player->source);
        if(alGetError() != AL_NO_ERROR)
        {
            fprintf(stderr, "Error restarting playback\n");
            return 0;
        }
    }

    return 1;
}


int main(int argc, char **argv)
{
    StreamPlayer *player;
    int i;

    /* Print out usage if no arguments were specified */
    if(argc < 2)
    {
        fprintf(stderr, "Usage: %s [-device <name>] <filenames...>\n", argv[0]);
        return 1;
    }

    argv++; argc--;
    if(InitAL(&argv, &argc) != 0)
        return 1;

    player = NewPlayer();

    /* Play each file listed on the command line */
    for(i = 0;i < argc;i++)
    {
        const char *namepart;

        if(!OpenPlayerFile(player, argv[i]))
            continue;

        /* Get the name portion, without the path, for display. */
        namepart = strrchr(argv[i], '/');
        if(!namepart) namepart = strrchr(argv[i], '\\');
        if(!namepart) namepart = argv[i];
        else namepart++;

        printf("Playing: %s (%s, %dhz)\n", namepart, FormatName(player->format),
            player->sfinfo.samplerate);
        fflush(stdout);

        if(!StartPlayer(player))
        {
            ClosePlayerFile(player);
            continue;
        }

        while(UpdatePlayer(player))
            al_nssleep(10000000);

        /* All done with this file. Close it and go to the next */
        ClosePlayerFile(player);
    }
    printf("Done.\n");

    /* All files done. Delete the player, and close down OpenAL */
    DeletePlayer(player);
    player = NULL;

    CloseAL();

    return 0;
}
