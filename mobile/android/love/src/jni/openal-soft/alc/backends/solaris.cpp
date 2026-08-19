/**
 * OpenAL cross platform audio library
 * Copyright (C) 1999-2007 by authors.
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

#include "solaris.h"

#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <memory.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <math.h>
#include <string.h>
#include <vector>

#include <thread>
#include <functional>

#include "alc/alconfig.h"
#include "alstring.h"
#include "althrd_setname.h"
#include "core/device.h"
#include "core/helpers.h"
#include "core/logging.h"

#include <sys/audioio.h>


namespace {

using namespace std::string_view_literals;

[[nodiscard]] constexpr auto GetDefaultName() noexcept { return "Solaris Default"sv; }

std::string solaris_driver{"/dev/audio"};


struct SolarisBackend final : public BackendBase {
    SolarisBackend(DeviceBase *device) noexcept : BackendBase{device} { }
    ~SolarisBackend() override;

    int mixerProc();

    void open(std::string_view name) override;
    bool reset() override;
    void start() override;
    void stop() override;

    int mFd{-1};

    uint mFrameStep{};
    std::vector<std::byte> mBuffer;

    std::atomic<bool> mKillNow{true};
    std::thread mThread;
};

SolarisBackend::~SolarisBackend()
{
    if(mFd != -1)
        close(mFd);
    mFd = -1;
}

int SolarisBackend::mixerProc()
{
    SetRTPriority();
    althrd_setname(GetMixerThreadName());

    const size_t frame_step{mDevice->channelsFromFmt()};
    const size_t frame_size{mDevice->frameSizeFromFmt()};

    while(!mKillNow.load(std::memory_order_acquire)
        && mDevice->Connected.load(std::memory_order_acquire))
    {
        pollfd pollitem{};
        pollitem.fd = mFd;
        pollitem.events = POLLOUT;

        int pret{poll(&pollitem, 1, 1000)};
        if(pret < 0)
        {
            if(errno == EINTR || errno == EAGAIN)
                continue;
            ERR("poll failed: %s\n", strerror(errno));
            mDevice->handleDisconnect("Failed to wait for playback buffer: %s", strerror(errno));
            break;
        }
        else if(pret == 0)
        {
            WARN("poll timeout\n");
            continue;
        }

        al::span<std::byte> buffer{mBuffer};
        mDevice->renderSamples(buffer.data(), static_cast<uint>(buffer.size()/frame_size),
            frame_step);
        while(!buffer.empty() && !mKillNow.load(std::memory_order_acquire))
        {
            ssize_t wrote{write(mFd, buffer.data(), buffer.size())};
            if(wrote < 0)
            {
                if(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
                    continue;
                ERR("write failed: %s\n", strerror(errno));
                mDevice->handleDisconnect("Failed to write playback samples: %s", strerror(errno));
                break;
            }

            buffer = buffer.subspan(static_cast<size_t>(wrote));
        }
    }

    return 0;
}


void SolarisBackend::open(std::string_view name)
{
    if(name.empty())
        name = GetDefaultName();
    else if(name != GetDefaultName())
        throw al::backend_exception{al::backend_error::NoDevice, "Device name \"%.*s\" not found",
            al::sizei(name), name.data()};

    int fd{::open(solaris_driver.c_str(), O_WRONLY)};
    if(fd == -1)
        throw al::backend_exception{al::backend_error::NoDevice, "Could not open %s: %s",
            solaris_driver.c_str(), strerror(errno)};

    if(mFd != -1)
        ::close(mFd);
    mFd = fd;

    mDeviceName = name;
}

bool SolarisBackend::reset()
{
    audio_info_t info;
    AUDIO_INITINFO(&info);

    info.play.sample_rate = mDevice->Frequency;
    info.play.channels = mDevice->channelsFromFmt();
    switch(mDevice->FmtType)
    {
    case DevFmtByte:
        info.play.precision = 8;
        info.play.encoding = AUDIO_ENCODING_LINEAR;
        break;
    case DevFmtUByte:
        info.play.precision = 8;
        info.play.encoding = AUDIO_ENCODING_LINEAR8;
        break;
    case DevFmtUShort:
    case DevFmtInt:
    case DevFmtUInt:
    case DevFmtFloat:
        mDevice->FmtType = DevFmtShort;
        /* fall-through */
    case DevFmtShort:
        info.play.precision = 16;
        info.play.encoding = AUDIO_ENCODING_LINEAR;
        break;
    }
    info.play.buffer_size = mDevice->BufferSize * mDevice->frameSizeFromFmt();

    if(ioctl(mFd, AUDIO_SETINFO, &info) < 0)
    {
        ERR("ioctl failed: %s\n", strerror(errno));
        return false;
    }

    if(mDevice->channelsFromFmt() != info.play.channels)
    {
        if(info.play.channels >= 2)
            mDevice->FmtChans = DevFmtStereo;
        else if(info.play.channels == 1)
            mDevice->FmtChans = DevFmtMono;
        else
            throw al::backend_exception{al::backend_error::DeviceError,
                "Got %u device channels", info.play.channels};
    }

    if(info.play.precision == 8 && info.play.encoding == AUDIO_ENCODING_LINEAR8)
        mDevice->FmtType = DevFmtUByte;
    else if(info.play.precision == 8 && info.play.encoding == AUDIO_ENCODING_LINEAR)
        mDevice->FmtType = DevFmtByte;
    else if(info.play.precision == 16 && info.play.encoding == AUDIO_ENCODING_LINEAR)
        mDevice->FmtType = DevFmtShort;
    else if(info.play.precision == 32 && info.play.encoding == AUDIO_ENCODING_LINEAR)
        mDevice->FmtType = DevFmtInt;
    else
    {
        ERR("Got unhandled sample type: %d (0x%x)\n", info.play.precision, info.play.encoding);
        return false;
    }

    uint frame_size{mDevice->bytesFromFmt() * info.play.channels};
    mFrameStep = info.play.channels;
    mDevice->Frequency = info.play.sample_rate;
    mDevice->BufferSize = info.play.buffer_size / frame_size;
    /* How to get the actual period size/count? */
    mDevice->UpdateSize = mDevice->BufferSize / 2;

    setDefaultChannelOrder();

    mBuffer.resize(mDevice->UpdateSize * size_t{frame_size});
    std::fill(mBuffer.begin(), mBuffer.end(), std::byte{});

    return true;
}

void SolarisBackend::start()
{
    try {
        mKillNow.store(false, std::memory_order_release);
        mThread = std::thread{std::mem_fn(&SolarisBackend::mixerProc), this};
    }
    catch(std::exception& e) {
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to start mixing thread: %s", e.what()};
    }
}

void SolarisBackend::stop()
{
    if(mKillNow.exchange(true, std::memory_order_acq_rel) || !mThread.joinable())
        return;
    mThread.join();

    if(ioctl(mFd, AUDIO_DRAIN) < 0)
        ERR("Error draining device: %s\n", strerror(errno));
}

} // namespace

BackendFactory &SolarisBackendFactory::getFactory()
{
    static SolarisBackendFactory factory{};
    return factory;
}

bool SolarisBackendFactory::init()
{
    if(auto devopt = ConfigValueStr({}, "solaris", "device"))
        solaris_driver = std::move(*devopt);
    return true;
}

bool SolarisBackendFactory::querySupport(BackendType type)
{ return type == BackendType::Playback; }

auto SolarisBackendFactory::enumerate(BackendType type) -> std::vector<std::string>
{
    switch(type)
    {
    case BackendType::Playback:
        if(struct stat buf{}; stat(solaris_driver.c_str(), &buf) == 0)
            return std::vector{std::string{GetDefaultName()}};
        break;

    case BackendType::Capture:
        break;
    }
    return {};
}

BackendPtr SolarisBackendFactory::createBackend(DeviceBase *device, BackendType type)
{
    if(type == BackendType::Playback)
        return BackendPtr{new SolarisBackend{device}};
    return nullptr;
}
