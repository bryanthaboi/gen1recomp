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

#include "oss.h"

#include <fcntl.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstring>
#include <exception>
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <system_error>
#include <thread>
#include <utility>
#include <vector>

#include "alc/alconfig.h"
#include "almalloc.h"
#include "alnumeric.h"
#include "alstring.h"
#include "althrd_setname.h"
#include "core/device.h"
#include "core/helpers.h"
#include "core/logging.h"
#include "ringbuffer.h"

#include <sys/soundcard.h>

/*
 * The OSS documentation talks about SOUND_MIXER_READ, but the header
 * only contains MIXER_READ. Play safe. Same for WRITE.
 */
#ifndef SOUND_MIXER_READ
#define SOUND_MIXER_READ MIXER_READ
#endif
#ifndef SOUND_MIXER_WRITE
#define SOUND_MIXER_WRITE MIXER_WRITE
#endif

#if defined(SOUND_VERSION) && (SOUND_VERSION < 0x040000)
#define ALC_OSS_COMPAT
#endif
#ifndef SNDCTL_AUDIOINFO
#define ALC_OSS_COMPAT
#endif

/*
 * FreeBSD strongly discourages the use of specific devices,
 * such as those returned in oss_audioinfo.devnode
 */
#ifdef __FreeBSD__
#define ALC_OSS_DEVNODE_TRUC
#endif

namespace {

using namespace std::string_literals;
using namespace std::string_view_literals;

[[nodiscard]] constexpr auto GetDefaultName() noexcept { return "OSS Default"sv; }

std::string DefaultPlayback{"/dev/dsp"s};
std::string DefaultCapture{"/dev/dsp"s};

struct DevMap {
    std::string name;
    std::string device_name;

    template<typename T, typename U>
    DevMap(T&& name_, U&& devname_)
        : name{std::forward<T>(name_)}, device_name{std::forward<U>(devname_)}
    { }
};

std::vector<DevMap> PlaybackDevices;
std::vector<DevMap> CaptureDevices;


#ifdef ALC_OSS_COMPAT

#define DSP_CAP_OUTPUT 0x00020000
#define DSP_CAP_INPUT 0x00010000
void ALCossListPopulate(std::vector<DevMap> &devlist, int type)
{
    devlist.emplace_back(GetDefaultName(), (type==DSP_CAP_INPUT) ? DefaultCapture : DefaultPlayback);
}

#else

class FileHandle {
    int mFd{-1};

public:
    FileHandle() = default;
    FileHandle(const FileHandle&) = delete;
    FileHandle& operator=(const FileHandle&) = delete;
    ~FileHandle() { if(mFd != -1) ::close(mFd); }

    template<typename ...Args>
    [[nodiscard]] auto open(const char *fname, Args&& ...args) -> bool
    {
        close();
        mFd = ::open(fname, std::forward<Args>(args)...);
        return mFd != -1;
    }
    void close()
    {
        if(mFd != -1)
            ::close(mFd);
        mFd = -1;
    }

    [[nodiscard]]
    auto get() const noexcept -> int { return mFd; }
};

void ALCossListAppend(std::vector<DevMap> &list, std::string_view handle, std::string_view path)
{
#ifdef ALC_OSS_DEVNODE_TRUC
    for(size_t i{0};i < path.size();++i)
    {
        if(path[i] == '.' && handle.size() >= path.size() - i)
        {
            const size_t hoffset{handle.size() + i - path.size()};
            if(strncmp(path.data() + i, handle.data() + hoffset, path.size() - i) == 0)
                handle = handle.substr(0, hoffset);
            path = path.substr(0, i);
        }
    }
#endif
    if(handle.empty())
        handle = path;

    auto match_devname = [path](const DevMap &entry) -> bool
    { return entry.device_name == path; };
    if(std::find_if(list.cbegin(), list.cend(), match_devname) != list.cend())
        return;

    auto checkName = [&list](const std::string_view name) -> bool
    {
        auto match_name = [name](const DevMap &entry) -> bool { return entry.name == name; };
        return std::find_if(list.cbegin(), list.cend(), match_name) != list.cend();
    };
    int count{1};
    std::string newname{handle};
    while(checkName(newname))
    {
        newname = handle;
        newname += " #";
        newname += std::to_string(++count);
    }

    const DevMap &entry = list.emplace_back(std::move(newname), path);

    TRACE("Got device \"%s\", \"%s\"\n", entry.name.c_str(), entry.device_name.c_str());
}

void ALCossListPopulate(std::vector<DevMap> &devlist, int type_flag)
{
    oss_sysinfo si{};
    FileHandle file;
    if(!file.open("/dev/mixer", O_RDONLY))
    {
        TRACE("Could not open /dev/mixer: %s\n", std::generic_category().message(errno).c_str());
        goto done;
    }

    if(ioctl(file.get(), SNDCTL_SYSINFO, &si) == -1)
    {
        TRACE("SNDCTL_SYSINFO failed: %s\n", std::generic_category().message(errno).c_str());
        goto done;
    }

    for(int i{0};i < si.numaudios;i++)
    {
        oss_audioinfo ai{};
        ai.dev = i;
        if(ioctl(file.get(), SNDCTL_AUDIOINFO, &ai) == -1)
        {
            ERR("SNDCTL_AUDIOINFO (%d) failed: %s\n", i,
                std::generic_category().message(errno).c_str());
            continue;
        }
        if(!(ai.caps&type_flag) || ai.devnode[0] == '\0')
            continue;

        std::string_view handle;
        if(ai.handle[0] != '\0')
            handle = {ai.handle, strnlen(ai.handle, sizeof(ai.handle))};
        else
            handle = {ai.name, strnlen(ai.name, sizeof(ai.name))};
        const std::string_view devnode{ai.devnode, strnlen(ai.devnode, sizeof(ai.devnode))};

        ALCossListAppend(devlist, handle, devnode);
    }

done:
    file.close();

    const char *defdev{((type_flag==DSP_CAP_INPUT) ? DefaultCapture : DefaultPlayback).c_str()};
    auto iter = std::find_if(devlist.cbegin(), devlist.cend(),
        [defdev](const DevMap &entry) -> bool
        { return entry.device_name == defdev; }
    );
    if(iter == devlist.cend())
        devlist.insert(devlist.begin(), DevMap{GetDefaultName(), defdev});
    else
    {
        DevMap entry{std::move(*iter)};
        devlist.erase(iter);
        devlist.insert(devlist.begin(), std::move(entry));
    }
    devlist.shrink_to_fit();
}

#endif

uint log2i(uint x)
{
    uint y{0};
    while(x > 1)
    {
        x >>= 1;
        y++;
    }
    return y;
}


struct OSSPlayback final : public BackendBase {
    OSSPlayback(DeviceBase *device) noexcept : BackendBase{device} { }
    ~OSSPlayback() override;

    int mixerProc();

    void open(std::string_view name) override;
    bool reset() override;
    void start() override;
    void stop() override;

    int mFd{-1};

    std::vector<std::byte> mMixData;

    std::atomic<bool> mKillNow{true};
    std::thread mThread;
};

OSSPlayback::~OSSPlayback()
{
    if(mFd != -1)
        ::close(mFd);
    mFd = -1;
}


int OSSPlayback::mixerProc()
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

        if(int pret{poll(&pollitem, 1, 1000)}; pret < 0)
        {
            if(errno == EINTR || errno == EAGAIN)
                continue;
            const auto errstr = std::generic_category().message(errno);
            ERR("poll failed: %s\n", errstr.c_str());
            mDevice->handleDisconnect("Failed waiting for playback buffer: %s", errstr.c_str());
            break;
        }
        else if(pret == 0) /* NOLINT(*-else-after-return) 'pret' is local to the if/else blocks */
        {
            WARN("poll timeout\n");
            continue;
        }

        al::span write_buf{mMixData};
        mDevice->renderSamples(write_buf.data(), static_cast<uint>(write_buf.size()/frame_size),
            frame_step);
        while(!write_buf.empty() && !mKillNow.load(std::memory_order_acquire))
        {
            ssize_t wrote{write(mFd, write_buf.data(), write_buf.size())};
            if(wrote < 0)
            {
                if(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
                    continue;
                const auto errstr = std::generic_category().message(errno);
                ERR("write failed: %s\n", errstr.c_str());
                mDevice->handleDisconnect("Failed writing playback samples: %s", errstr.c_str());
                break;
            }

            write_buf = write_buf.subspan(static_cast<size_t>(wrote));
        }
    }

    return 0;
}


void OSSPlayback::open(std::string_view name)
{
    const char *devname{DefaultPlayback.c_str()};
    if(name.empty())
        name = GetDefaultName();
    else
    {
        if(PlaybackDevices.empty())
            ALCossListPopulate(PlaybackDevices, DSP_CAP_OUTPUT);

        auto iter = std::find_if(PlaybackDevices.cbegin(), PlaybackDevices.cend(),
            [&name](const DevMap &entry) -> bool
            { return entry.name == name; }
        );
        if(iter == PlaybackDevices.cend())
            throw al::backend_exception{al::backend_error::NoDevice,
                "Device name \"%.*s\" not found", al::sizei(name), name.data()};
        devname = iter->device_name.c_str();
    }

    int fd{::open(devname, O_WRONLY)};
    if(fd == -1)
        throw al::backend_exception{al::backend_error::NoDevice, "Could not open %s: %s", devname,
            std::generic_category().message(errno).c_str()};

    if(mFd != -1)
        ::close(mFd);
    mFd = fd;

    mDeviceName = name;
}

bool OSSPlayback::reset()
{
    int ossFormat{};
    switch(mDevice->FmtType)
    {
        case DevFmtByte:
            ossFormat = AFMT_S8;
            break;
        case DevFmtUByte:
            ossFormat = AFMT_U8;
            break;
        case DevFmtUShort:
        case DevFmtInt:
        case DevFmtUInt:
        case DevFmtFloat:
            mDevice->FmtType = DevFmtShort;
            /* fall-through */
        case DevFmtShort:
            ossFormat = AFMT_S16_NE;
            break;
    }

    uint periods{mDevice->BufferSize / mDevice->UpdateSize};
    uint numChannels{mDevice->channelsFromFmt()};
    uint ossSpeed{mDevice->Frequency};
    uint frameSize{numChannels * mDevice->bytesFromFmt()};
    /* According to the OSS spec, 16 bytes (log2(16)) is the minimum. */
    uint log2FragmentSize{std::max(log2i(mDevice->UpdateSize*frameSize), 4u)};
    uint numFragmentsLogSize{(periods << 16) | log2FragmentSize};

    audio_buf_info info{};
#define CHECKERR(func) if((func) < 0)                                         \
    throw al::backend_exception{al::backend_error::DeviceError, "%s failed: %s\n", #func, \
        std::generic_category().message(errno).c_str()};

    /* Don't fail if SETFRAGMENT fails. We can handle just about anything
     * that's reported back via GETOSPACE */
    ioctl(mFd, SNDCTL_DSP_SETFRAGMENT, &numFragmentsLogSize);
    CHECKERR(ioctl(mFd, SNDCTL_DSP_SETFMT, &ossFormat));
    CHECKERR(ioctl(mFd, SNDCTL_DSP_CHANNELS, &numChannels));
    CHECKERR(ioctl(mFd, SNDCTL_DSP_SPEED, &ossSpeed));
    CHECKERR(ioctl(mFd, SNDCTL_DSP_GETOSPACE, &info));
#undef CHECKERR

    if(mDevice->channelsFromFmt() != numChannels)
    {
        ERR("Failed to set %s, got %d channels instead\n", DevFmtChannelsString(mDevice->FmtChans),
            numChannels);
        return false;
    }

    if(!((ossFormat == AFMT_S8 && mDevice->FmtType == DevFmtByte) ||
         (ossFormat == AFMT_U8 && mDevice->FmtType == DevFmtUByte) ||
         (ossFormat == AFMT_S16_NE && mDevice->FmtType == DevFmtShort)))
    {
        ERR("Failed to set %s samples, got OSS format %#x\n", DevFmtTypeString(mDevice->FmtType),
            ossFormat);
        return false;
    }

    mDevice->Frequency = ossSpeed;
    mDevice->UpdateSize = static_cast<uint>(info.fragsize) / frameSize;
    mDevice->BufferSize = static_cast<uint>(info.fragments) * mDevice->UpdateSize;

    setDefaultChannelOrder();

    mMixData.resize(size_t{mDevice->UpdateSize} * mDevice->frameSizeFromFmt());

    return true;
}

void OSSPlayback::start()
{
    try {
        mKillNow.store(false, std::memory_order_release);
        mThread = std::thread{std::mem_fn(&OSSPlayback::mixerProc), this};
    }
    catch(std::exception& e) {
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to start mixing thread: %s", e.what()};
    }
}

void OSSPlayback::stop()
{
    if(mKillNow.exchange(true, std::memory_order_acq_rel) || !mThread.joinable())
        return;
    mThread.join();

    if(ioctl(mFd, SNDCTL_DSP_RESET) != 0)
        ERR("Error resetting device: %s\n", std::generic_category().message(errno).c_str());
}


struct OSScapture final : public BackendBase {
    OSScapture(DeviceBase *device) noexcept : BackendBase{device} { }
    ~OSScapture() override;

    int recordProc();

    void open(std::string_view name) override;
    void start() override;
    void stop() override;
    void captureSamples(std::byte *buffer, uint samples) override;
    uint availableSamples() override;

    int mFd{-1};

    RingBufferPtr mRing{nullptr};

    std::atomic<bool> mKillNow{true};
    std::thread mThread;
};

OSScapture::~OSScapture()
{
    if(mFd != -1)
        close(mFd);
    mFd = -1;
}


int OSScapture::recordProc()
{
    SetRTPriority();
    althrd_setname(GetRecordThreadName());

    const size_t frame_size{mDevice->frameSizeFromFmt()};
    while(!mKillNow.load(std::memory_order_acquire))
    {
        pollfd pollitem{};
        pollitem.fd = mFd;
        pollitem.events = POLLIN;

        if(int pret{poll(&pollitem, 1, 1000)}; pret < 0)
        {
            if(errno == EINTR || errno == EAGAIN)
                continue;
            const auto errstr = std::generic_category().message(errno);
            ERR("poll failed: %s\n", errstr.c_str());
            mDevice->handleDisconnect("Failed to check capture samples: %s", errstr.c_str());
            break;
        }
        else if(pret == 0) /* NOLINT(*-else-after-return) 'pret' is local to the if/else blocks */
        {
            WARN("poll timeout\n");
            continue;
        }

        auto vec = mRing->getWriteVector();
        if(vec[0].len > 0)
        {
            ssize_t amt{read(mFd, vec[0].buf, vec[0].len*frame_size)};
            if(amt < 0)
            {
                const auto errstr = std::generic_category().message(errno);
                ERR("read failed: %s\n", errstr.c_str());
                mDevice->handleDisconnect("Failed reading capture samples: %s", errstr.c_str());
                break;
            }
            mRing->writeAdvance(static_cast<size_t>(amt)/frame_size);
        }
    }

    return 0;
}


void OSScapture::open(std::string_view name)
{
    const char *devname{DefaultCapture.c_str()};
    if(name.empty())
        name = GetDefaultName();
    else
    {
        if(CaptureDevices.empty())
            ALCossListPopulate(CaptureDevices, DSP_CAP_INPUT);

        auto iter = std::find_if(CaptureDevices.cbegin(), CaptureDevices.cend(),
            [&name](const DevMap &entry) -> bool
            { return entry.name == name; }
        );
        if(iter == CaptureDevices.cend())
            throw al::backend_exception{al::backend_error::NoDevice,
                "Device name \"%.*s\" not found", al::sizei(name), name.data()};
        devname = iter->device_name.c_str();
    }

    mFd = ::open(devname, O_RDONLY);
    if(mFd == -1)
        throw al::backend_exception{al::backend_error::NoDevice, "Could not open %s: %s", devname,
            std::generic_category().message(errno).c_str()};

    int ossFormat{};
    switch(mDevice->FmtType)
    {
    case DevFmtByte:
        ossFormat = AFMT_S8;
        break;
    case DevFmtUByte:
        ossFormat = AFMT_U8;
        break;
    case DevFmtShort:
        ossFormat = AFMT_S16_NE;
        break;
    case DevFmtUShort:
    case DevFmtInt:
    case DevFmtUInt:
    case DevFmtFloat:
        throw al::backend_exception{al::backend_error::DeviceError,
            "%s capture samples not supported", DevFmtTypeString(mDevice->FmtType)};
    }

    uint periods{4};
    uint numChannels{mDevice->channelsFromFmt()};
    uint frameSize{numChannels * mDevice->bytesFromFmt()};
    uint ossSpeed{mDevice->Frequency};
    /* according to the OSS spec, 16 bytes are the minimum */
    uint log2FragmentSize{std::max(log2i(mDevice->BufferSize * frameSize / periods), 4u)};
    uint numFragmentsLogSize{(periods << 16) | log2FragmentSize};

    audio_buf_info info{};
#define CHECKERR(func) if((func) < 0) {                                       \
    throw al::backend_exception{al::backend_error::DeviceError, #func " failed: %s", \
        std::generic_category().message(errno).c_str()};                      \
}
    CHECKERR(ioctl(mFd, SNDCTL_DSP_SETFRAGMENT, &numFragmentsLogSize));
    CHECKERR(ioctl(mFd, SNDCTL_DSP_SETFMT, &ossFormat));
    CHECKERR(ioctl(mFd, SNDCTL_DSP_CHANNELS, &numChannels));
    CHECKERR(ioctl(mFd, SNDCTL_DSP_SPEED, &ossSpeed));
    CHECKERR(ioctl(mFd, SNDCTL_DSP_GETISPACE, &info));
#undef CHECKERR

    if(mDevice->channelsFromFmt() != numChannels)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to set %s, got %d channels instead", DevFmtChannelsString(mDevice->FmtChans),
            numChannels};

    if(!((ossFormat == AFMT_S8 && mDevice->FmtType == DevFmtByte)
        || (ossFormat == AFMT_U8 && mDevice->FmtType == DevFmtUByte)
        || (ossFormat == AFMT_S16_NE && mDevice->FmtType == DevFmtShort)))
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to set %s samples, got OSS format %#x", DevFmtTypeString(mDevice->FmtType),
            ossFormat};

    mRing = RingBuffer::Create(mDevice->BufferSize, frameSize, false);

    mDeviceName = name;
}

void OSScapture::start()
{
    try {
        mKillNow.store(false, std::memory_order_release);
        mThread = std::thread{std::mem_fn(&OSScapture::recordProc), this};
    }
    catch(std::exception& e) {
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to start recording thread: %s", e.what()};
    }
}

void OSScapture::stop()
{
    if(mKillNow.exchange(true, std::memory_order_acq_rel) || !mThread.joinable())
        return;
    mThread.join();

    if(ioctl(mFd, SNDCTL_DSP_RESET) != 0)
        ERR("Error resetting device: %s\n", std::generic_category().message(errno).c_str());
}

void OSScapture::captureSamples(std::byte *buffer, uint samples)
{ std::ignore = mRing->read(buffer, samples); }

uint OSScapture::availableSamples()
{ return static_cast<uint>(mRing->readSpace()); }

} // namespace


BackendFactory &OSSBackendFactory::getFactory()
{
    static OSSBackendFactory factory{};
    return factory;
}

bool OSSBackendFactory::init()
{
    if(auto devopt = ConfigValueStr({}, "oss", "device"))
        DefaultPlayback = std::move(*devopt);
    if(auto capopt = ConfigValueStr({}, "oss", "capture"))
        DefaultCapture = std::move(*capopt);

    return true;
}

bool OSSBackendFactory::querySupport(BackendType type)
{ return (type == BackendType::Playback || type == BackendType::Capture); }

auto OSSBackendFactory::enumerate(BackendType type) -> std::vector<std::string>
{
    std::vector<std::string> outnames;
    auto add_device = [&outnames](const DevMap &entry) -> void
    {
        if(struct stat buf{}; stat(entry.device_name.c_str(), &buf) == 0)
            outnames.emplace_back(entry.name);
    };

    switch(type)
    {
    case BackendType::Playback:
        PlaybackDevices.clear();
        ALCossListPopulate(PlaybackDevices, DSP_CAP_OUTPUT);
        outnames.reserve(PlaybackDevices.size());
        std::for_each(PlaybackDevices.cbegin(), PlaybackDevices.cend(), add_device);
        break;

    case BackendType::Capture:
        CaptureDevices.clear();
        ALCossListPopulate(CaptureDevices, DSP_CAP_INPUT);
        outnames.reserve(CaptureDevices.size());
        std::for_each(CaptureDevices.cbegin(), CaptureDevices.cend(), add_device);
        break;
    }

    return outnames;
}

BackendPtr OSSBackendFactory::createBackend(DeviceBase *device, BackendType type)
{
    if(type == BackendType::Playback)
        return BackendPtr{new OSSPlayback{device}};
    if(type == BackendType::Capture)
        return BackendPtr{new OSScapture{device}};
    return nullptr;
}
