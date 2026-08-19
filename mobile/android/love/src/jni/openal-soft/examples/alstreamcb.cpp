/*
 * OpenAL Callback-based Stream Example
 *
 * Copyright (c) 2020 by Chris Robinson <chris.kcat@gmail.com>
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

/* This file contains a streaming audio player using a callback buffer. */


#include <algorithm>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstddef>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "sndfile.h"

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/alext.h"

#include "alspan.h"
#include "alstring.h"
#include "common/alhelpers.h"

#include "win_main_utf8.h"


namespace {

using std::chrono::seconds;
using std::chrono::nanoseconds;

LPALBUFFERCALLBACKSOFT alBufferCallbackSOFT;

struct StreamPlayer {
    /* A lockless ring-buffer (supports single-provider, single-consumer
     * operation).
     */
    std::vector<std::byte> mBufferData;
    std::atomic<size_t> mReadPos{0};
    std::atomic<size_t> mWritePos{0};
    size_t mSamplesPerBlock{1};
    size_t mBytesPerBlock{1};

    enum class SampleType {
        Int16, Float, IMA4, MSADPCM
    };
    SampleType mSampleFormat{SampleType::Int16};

    /* The buffer to get the callback, and source to play with. */
    ALuint mBuffer{0}, mSource{0};
    size_t mStartOffset{0};

    /* Handle for the audio file to decode. */
    SNDFILE *mSndfile{nullptr};
    SF_INFO mSfInfo{};
    size_t mDecoderOffset{0};

    /* The format of the callback samples. */
    ALenum mFormat{};

    StreamPlayer()
    {
        alGenBuffers(1, &mBuffer);
        if(alGetError() != AL_NO_ERROR)
            throw std::runtime_error{"alGenBuffers failed"};
        alGenSources(1, &mSource);
        if(alGetError() != AL_NO_ERROR)
        {
            alDeleteBuffers(1, &mBuffer);
            throw std::runtime_error{"alGenSources failed"};
        }
    }
    ~StreamPlayer()
    {
        alDeleteSources(1, &mSource);
        alDeleteBuffers(1, &mBuffer);
        if(mSndfile)
            sf_close(mSndfile);
    }

    void close()
    {
        if(mSamplesPerBlock > 1)
            alBufferi(mBuffer, AL_UNPACK_BLOCK_ALIGNMENT_SOFT, 0);

        if(mSndfile)
        {
            alSourceRewind(mSource);
            alSourcei(mSource, AL_BUFFER, 0);
            sf_close(mSndfile);
            mSndfile = nullptr;
        }
    }

    bool open(const std::string &filename)
    {
        close();

        /* Open the file and figure out the OpenAL format. */
        mSndfile = sf_open(filename.c_str(), SFM_READ, &mSfInfo);
        if(!mSndfile)
        {
            fprintf(stderr, "Could not open audio in %s: %s\n", filename.c_str(),
                sf_strerror(mSndfile));
            return false;
        }

        switch((mSfInfo.format&SF_FORMAT_SUBMASK))
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
                mSampleFormat = SampleType::Float;
            break;
        case SF_FORMAT_IMA_ADPCM:
            if(mSfInfo.channels <= 2 && (mSfInfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV
                && alIsExtensionPresent("AL_EXT_IMA4")
                && alIsExtensionPresent("AL_SOFT_block_alignment"))
                mSampleFormat = SampleType::IMA4;
            break;
        case SF_FORMAT_MS_ADPCM:
            if(mSfInfo.channels <= 2 && (mSfInfo.format&SF_FORMAT_TYPEMASK) == SF_FORMAT_WAV
                && alIsExtensionPresent("AL_SOFT_MSADPCM")
                && alIsExtensionPresent("AL_SOFT_block_alignment"))
                mSampleFormat = SampleType::MSADPCM;
            break;
        }

        int splblocksize{}, byteblocksize{};
        if(mSampleFormat == SampleType::IMA4 || mSampleFormat == SampleType::MSADPCM)
        {
            SF_CHUNK_INFO inf{ "fmt ", 4, 0, nullptr };
            SF_CHUNK_ITERATOR *iter = sf_get_chunk_iterator(mSndfile, &inf);
            if(!iter || sf_get_chunk_size(iter, &inf) != SF_ERR_NO_ERROR || inf.datalen < 14)
                mSampleFormat = SampleType::Int16;
            else
            {
                auto fmtbuf = std::vector<ALubyte>(inf.datalen);
                inf.data = fmtbuf.data();
                if(sf_get_chunk_data(iter, &inf) != SF_ERR_NO_ERROR)
                    mSampleFormat = SampleType::Int16;
                else
                {
                    byteblocksize = fmtbuf[12] | (fmtbuf[13]<<8u);
                    if(mSampleFormat == SampleType::IMA4)
                    {
                        splblocksize = (byteblocksize/mSfInfo.channels - 4)/4*8 + 1;
                        if(splblocksize < 1
                            || ((splblocksize-1)/2 + 4)*mSfInfo.channels != byteblocksize)
                            mSampleFormat = SampleType::Int16;
                    }
                    else
                    {
                        splblocksize = (byteblocksize/mSfInfo.channels - 7)*2 + 2;
                        if(splblocksize < 2
                            || ((splblocksize-2)/2 + 7)*mSfInfo.channels != byteblocksize)
                            mSampleFormat = SampleType::Int16;
                    }
                }
            }
        }

        if(mSampleFormat == SampleType::Int16)
        {
            mSamplesPerBlock = 1;
            mBytesPerBlock = static_cast<size_t>(mSfInfo.channels) * 2;
        }
        else if(mSampleFormat == SampleType::Float)
        {
            mSamplesPerBlock = 1;
            mBytesPerBlock = static_cast<size_t>(mSfInfo.channels) * 4;
        }
        else
        {
            mSamplesPerBlock = static_cast<size_t>(splblocksize);
            mBytesPerBlock = static_cast<size_t>(byteblocksize);
        }

        mFormat = AL_NONE;
        if(mSfInfo.channels == 1)
        {
            if(mSampleFormat == SampleType::Int16)
                mFormat = AL_FORMAT_MONO16;
            else if(mSampleFormat == SampleType::Float)
                mFormat = AL_FORMAT_MONO_FLOAT32;
            else if(mSampleFormat == SampleType::IMA4)
                mFormat = AL_FORMAT_MONO_IMA4;
            else if(mSampleFormat == SampleType::MSADPCM)
                mFormat = AL_FORMAT_MONO_MSADPCM_SOFT;
        }
        else if(mSfInfo.channels == 2)
        {
            if(mSampleFormat == SampleType::Int16)
                mFormat = AL_FORMAT_STEREO16;
            else if(mSampleFormat == SampleType::Float)
                mFormat = AL_FORMAT_STEREO_FLOAT32;
            else if(mSampleFormat == SampleType::IMA4)
                mFormat = AL_FORMAT_STEREO_IMA4;
            else if(mSampleFormat == SampleType::MSADPCM)
                mFormat = AL_FORMAT_STEREO_MSADPCM_SOFT;
        }
        else if(mSfInfo.channels == 3)
        {
            if(sf_command(mSndfile, SFC_WAVEX_GET_AMBISONIC, nullptr, 0) == SF_AMBISONIC_B_FORMAT)
            {
                if(mSampleFormat == SampleType::Int16)
                    mFormat = AL_FORMAT_BFORMAT2D_16;
                else if(mSampleFormat == SampleType::Float)
                    mFormat = AL_FORMAT_BFORMAT2D_FLOAT32;
            }
        }
        else if(mSfInfo.channels == 4)
        {
            if(sf_command(mSndfile, SFC_WAVEX_GET_AMBISONIC, nullptr, 0) == SF_AMBISONIC_B_FORMAT)
            {
                if(mSampleFormat == SampleType::Int16)
                    mFormat = AL_FORMAT_BFORMAT3D_16;
                else if(mSampleFormat == SampleType::Float)
                    mFormat = AL_FORMAT_BFORMAT3D_FLOAT32;
            }
        }
        if(!mFormat)
        {
            fprintf(stderr, "Unsupported channel count: %d\n", mSfInfo.channels);
            sf_close(mSndfile);
            mSndfile = nullptr;

            return false;
        }

        /* Set a 1s ring buffer size. */
        size_t numblocks{(static_cast<ALuint>(mSfInfo.samplerate) + mSamplesPerBlock-1)
            / mSamplesPerBlock};
        mBufferData.resize(static_cast<ALuint>(numblocks * mBytesPerBlock));
        mReadPos.store(0, std::memory_order_relaxed);
        mWritePos.store(0, std::memory_order_relaxed);
        mDecoderOffset = 0;

        return true;
    }

    /* The actual C-style callback just forwards to the non-static method. Not
     * strictly needed and the compiler will optimize it to a normal function,
     * but it allows the callback implementation to have a nice 'this' pointer
     * with normal member access.
     */
    static ALsizei AL_APIENTRY bufferCallbackC(void *userptr, void *data, ALsizei size) noexcept
    { return static_cast<StreamPlayer*>(userptr)->bufferCallback(data, size); }
    ALsizei bufferCallback(void *data, ALsizei size) noexcept
    {
        const auto output = al::span{static_cast<std::byte*>(data), static_cast<ALuint>(size)};
        auto dst = output.begin();

        /* NOTE: The callback *MUST* be real-time safe! That means no blocking,
         * no allocations or deallocations, no I/O, no page faults, or calls to
         * functions that could do these things (this includes calling to
         * libraries like SDL_sound, libsndfile, ffmpeg, etc). Nothing should
         * unexpectedly stall this call since the audio has to get to the
         * device on time.
         */

        size_t roffset{mReadPos.load(std::memory_order_acquire)};
        while(const auto remaining = static_cast<size_t>(std::distance(dst, output.end())))
        {
            /* If the write offset == read offset, there's nothing left in the
             * ring-buffer. Break from the loop and give what has been written.
             */
            const size_t woffset{mWritePos.load(std::memory_order_relaxed)};
            if(woffset == roffset) break;

            /* If the write offset is behind the read offset, the readable
             * portion wrapped around. Just read up to the end of the buffer in
             * that case, otherwise read up to the write offset. Also limit the
             * amount to copy given how much is remaining to write.
             */
            size_t todo{((woffset < roffset) ? mBufferData.size() : woffset) - roffset};
            todo = std::min(todo, remaining);

            /* Copy from the ring buffer to the provided output buffer. Wrap
             * the resulting read offset if it reached the end of the ring-
             * buffer.
             */
            const auto input = al::span{mBufferData}.subspan(roffset, todo);
            dst = std::copy_n(input.begin(), input.size(), dst);

            roffset += todo;
            if(roffset == mBufferData.size())
                roffset = 0;
        }
        /* Finally, store the updated read offset, and return how many bytes
         * have been written.
         */
        mReadPos.store(roffset, std::memory_order_release);

        return static_cast<ALsizei>(std::distance(output.begin(), dst));
    }

    bool prepare()
    {
        if(mSamplesPerBlock > 1)
            alBufferi(mBuffer, AL_UNPACK_BLOCK_ALIGNMENT_SOFT, static_cast<int>(mSamplesPerBlock));
        alBufferCallbackSOFT(mBuffer, mFormat, mSfInfo.samplerate, bufferCallbackC, this);
        alSourcei(mSource, AL_BUFFER, static_cast<ALint>(mBuffer));
        if(ALenum err{alGetError()})
        {
            fprintf(stderr, "Failed to set callback: %s (0x%04x)\n", alGetString(err), err);
            return false;
        }
        return true;
    }

    bool update()
    {
        ALenum state;
        ALint pos;
        alGetSourcei(mSource, AL_SAMPLE_OFFSET, &pos);
        alGetSourcei(mSource, AL_SOURCE_STATE, &state);

        size_t woffset{mWritePos.load(std::memory_order_acquire)};
        if(state != AL_INITIAL)
        {
            const size_t roffset{mReadPos.load(std::memory_order_relaxed)};
            const size_t readable{((woffset >= roffset) ? woffset : (mBufferData.size()+woffset)) -
                roffset};
            /* For a stopped (underrun) source, the current playback offset is
             * the current decoder offset excluding the readable buffered data.
             * For a playing/paused source, it's the source's offset including
             * the playback offset the source was started with.
             */
            const auto curtime = ((state == AL_STOPPED)
                ? (mDecoderOffset-readable) / mBytesPerBlock * mSamplesPerBlock
                : (size_t{static_cast<ALuint>(pos)} + mStartOffset))
                / static_cast<ALuint>(mSfInfo.samplerate);
            printf("\r %zum%02zus (%3zu%% full)", curtime/60, curtime%60,
                readable * 100 / mBufferData.size());
        }
        else
            fputs("Starting...", stdout);
        fflush(stdout);

        while(!sf_error(mSndfile))
        {
            const auto roffset = mReadPos.load(std::memory_order_relaxed);
            auto get_writable = [this,roffset,woffset]() noexcept -> size_t
            {
                if(roffset > woffset)
                {
                    /* Note that the ring buffer's writable space is one byte
                     * less than the available area because the write offset
                     * ending up at the read offset would be interpreted as
                     * being empty instead of full.
                     */
                    return roffset - woffset - 1;
                }

                /* If the read offset is at or behind the write offset, the
                 * writeable area (might) wrap around. Make sure the sample
                 * data can fit, and calculate how much can go in front before
                 * wrapping.
                 */
                return mBufferData.size() - (!roffset ? woffset+1 : woffset);
            };

            const auto writable = get_writable() / mBytesPerBlock;
            if(!writable) break;

            auto read_bytes = size_t{};
            if(mSampleFormat == SampleType::Int16)
            {
                const auto num_frames = sf_readf_short(mSndfile,
                    reinterpret_cast<short*>(&mBufferData[woffset]),
                    static_cast<sf_count_t>(writable*mSamplesPerBlock));
                if(num_frames < 1) break;
                read_bytes = static_cast<size_t>(num_frames) * mBytesPerBlock;
            }
            else if(mSampleFormat == SampleType::Float)
            {
                const auto num_frames = sf_readf_float(mSndfile,
                    reinterpret_cast<float*>(&mBufferData[woffset]),
                    static_cast<sf_count_t>(writable*mSamplesPerBlock));
                if(num_frames < 1) break;
                read_bytes = static_cast<size_t>(num_frames) * mBytesPerBlock;
            }
            else
            {
                const auto numbytes = sf_read_raw(mSndfile, &mBufferData[woffset],
                    static_cast<sf_count_t>(writable*mBytesPerBlock));
                if(numbytes < 1) break;
                read_bytes = static_cast<size_t>(numbytes);
            }

            woffset += read_bytes;
            if(woffset == mBufferData.size())
                woffset = 0;

            mWritePos.store(woffset, std::memory_order_release);
            mDecoderOffset += read_bytes;
        }

        if(state != AL_PLAYING && state != AL_PAUSED)
        {
            /* If the source is not playing or paused, it either underrun
             * (AL_STOPPED) or is just getting started (AL_INITIAL). If the
             * ring buffer is empty, it's done, otherwise play the source with
             * what's available.
             */
            const auto roffset = mReadPos.load(std::memory_order_relaxed);
            const auto readable = ((woffset < roffset) ? mBufferData.size()+woffset : woffset) -
                roffset;
            if(readable == 0)
                return false;

            /* Store the playback offset that the source will start reading
             * from, so it can be tracked during playback.
             */
            mStartOffset = (mDecoderOffset-readable) / mBytesPerBlock * mSamplesPerBlock;
            alSourcePlay(mSource);
            if(alGetError() != AL_NO_ERROR)
                return false;
        }
        return true;
    }
};

int main(al::span<std::string_view> args)
{
    /* Print out usage if no arguments were specified */
    if(args.size() < 2)
    {
        fprintf(stderr, "Usage: %.*s [-device <name>] <filenames...>\n", al::sizei(args[0]),
            args[0].data());
        return 1;
    }
    args = args.subspan(1);

    if(InitAL(args) != 0)
        throw std::runtime_error{"Failed to initialize OpenAL"};
    /* A simple RAII container for automating OpenAL shutdown. */
    struct AudioManager {
        AudioManager() = default;
        AudioManager(const AudioManager&) = delete;
        auto operator=(const AudioManager&) -> AudioManager& = delete;
        ~AudioManager() { CloseAL(); }
    };
    AudioManager almgr;

    if(!alIsExtensionPresent("AL_SOFT_callback_buffer"))
    {
        fprintf(stderr, "AL_SOFT_callback_buffer extension not available\n");
        return 1;
    }

    alBufferCallbackSOFT = reinterpret_cast<LPALBUFFERCALLBACKSOFT>(
        alGetProcAddress("alBufferCallbackSOFT"));

    ALCint refresh{25};
    alcGetIntegerv(alcGetContextsDevice(alcGetCurrentContext()), ALC_REFRESH, 1, &refresh);

    auto player = std::make_unique<StreamPlayer>();

    /* Play each file listed on the command line */
    for(size_t i{0};i < args.size();++i)
    {
        if(!player->open(std::string{args[i]}))
            continue;

        /* Get the name portion, without the path, for display. */
        auto namepart = args[i];
        if(auto sep = namepart.rfind('/'); sep < namepart.size())
            namepart = namepart.substr(sep+1);
        else if(sep = namepart.rfind('\\'); sep < namepart.size())
            namepart = namepart.substr(sep+1);

        printf("Playing: %.*s (%s, %dhz)\n", al::sizei(namepart), namepart.data(),
            FormatName(player->mFormat), player->mSfInfo.samplerate);
        fflush(stdout);

        if(!player->prepare())
        {
            player->close();
            continue;
        }

        while(player->update())
            std::this_thread::sleep_for(nanoseconds{seconds{1}} / refresh);
        putc('\n', stdout);

        /* All done with this file. Close it and go to the next */
        player->close();
    }
    /* All done. */
    printf("Done.\n");

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
