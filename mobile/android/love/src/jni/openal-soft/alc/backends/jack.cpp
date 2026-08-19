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

#include "jack.h"

#include <array>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <memory.h>
#include <mutex>
#include <thread>
#include <functional>
#include <vector>

#include "alc/alconfig.h"
#include "alnumeric.h"
#include "alsem.h"
#include "alstring.h"
#include "althrd_setname.h"
#include "core/device.h"
#include "core/helpers.h"
#include "core/logging.h"
#include "dynload.h"
#include "ringbuffer.h"

#include <jack/jack.h>
#include <jack/ringbuffer.h>


namespace {

using namespace std::string_view_literals;

#ifdef HAVE_DYNLOAD
#define JACK_FUNCS(MAGIC)          \
    MAGIC(jack_client_open);       \
    MAGIC(jack_client_close);      \
    MAGIC(jack_client_name_size);  \
    MAGIC(jack_get_client_name);   \
    MAGIC(jack_connect);           \
    MAGIC(jack_activate);          \
    MAGIC(jack_deactivate);        \
    MAGIC(jack_port_register);     \
    MAGIC(jack_port_unregister);   \
    MAGIC(jack_port_get_buffer);   \
    MAGIC(jack_port_name);         \
    MAGIC(jack_get_ports);         \
    MAGIC(jack_free);              \
    MAGIC(jack_get_sample_rate);   \
    MAGIC(jack_set_error_function); \
    MAGIC(jack_set_process_callback); \
    MAGIC(jack_set_buffer_size_callback); \
    MAGIC(jack_set_buffer_size);   \
    MAGIC(jack_get_buffer_size);

void *jack_handle;
#define MAKE_FUNC(f) decltype(f) * p##f
JACK_FUNCS(MAKE_FUNC)
decltype(jack_error_callback) * pjack_error_callback;
#undef MAKE_FUNC

#ifndef IN_IDE_PARSER
#define jack_client_open pjack_client_open
#define jack_client_close pjack_client_close
#define jack_client_name_size pjack_client_name_size
#define jack_get_client_name pjack_get_client_name
#define jack_connect pjack_connect
#define jack_activate pjack_activate
#define jack_deactivate pjack_deactivate
#define jack_port_register pjack_port_register
#define jack_port_unregister pjack_port_unregister
#define jack_port_get_buffer pjack_port_get_buffer
#define jack_port_name pjack_port_name
#define jack_get_ports pjack_get_ports
#define jack_free pjack_free
#define jack_get_sample_rate pjack_get_sample_rate
#define jack_set_error_function pjack_set_error_function
#define jack_set_process_callback pjack_set_process_callback
#define jack_set_buffer_size_callback pjack_set_buffer_size_callback
#define jack_set_buffer_size pjack_set_buffer_size
#define jack_get_buffer_size pjack_get_buffer_size
#define jack_error_callback (*pjack_error_callback)
#endif
#endif


jack_options_t ClientOptions = JackNullOption;

bool jack_load()
{
#ifdef HAVE_DYNLOAD
    if(!jack_handle)
    {
#if defined(_WIN64)
#define JACKLIB "libjack64.dll"
#elif defined(_WIN32)
#define JACKLIB "libjack.dll"
#else
#define JACKLIB "libjack.so.0"
#endif
        jack_handle = LoadLib(JACKLIB);
        if(!jack_handle)
        {
            WARN("Failed to load %s\n", JACKLIB);
            return false;
        }

        std::string missing_funcs;
#define LOAD_FUNC(f) do {                                                     \
    p##f = reinterpret_cast<decltype(p##f)>(GetSymbol(jack_handle, #f));      \
    if(p##f == nullptr) missing_funcs += "\n" #f;                             \
} while(0)
        JACK_FUNCS(LOAD_FUNC);
#undef LOAD_FUNC
        /* Optional symbols. These don't exist in all versions of JACK. */
#define LOAD_SYM(f) p##f = reinterpret_cast<decltype(p##f)>(GetSymbol(jack_handle, #f))
        LOAD_SYM(jack_error_callback);
#undef LOAD_SYM

        if(!missing_funcs.empty())
        {
            WARN("Missing expected functions:%s\n", missing_funcs.c_str());
            CloseLib(jack_handle);
            jack_handle = nullptr;
            return false;
        }
    }
#endif

    return true;
}


struct JackDeleter {
    void operator()(void *ptr) { jack_free(ptr); }
};
using JackPortsPtr = std::unique_ptr<const char*[],JackDeleter>; /* NOLINT(*-avoid-c-arrays) */

struct DeviceEntry {
    std::string mName;
    std::string mPattern;

    DeviceEntry() = default;
    DeviceEntry(const DeviceEntry&) = default;
    DeviceEntry(DeviceEntry&&) = default;
    template<typename T, typename U>
    DeviceEntry(T&& name, U&& pattern)
        : mName{std::forward<T>(name)}, mPattern{std::forward<U>(pattern)}
    { }
    ~DeviceEntry();

    DeviceEntry& operator=(const DeviceEntry&) = default;
    DeviceEntry& operator=(DeviceEntry&&) = default;
};
DeviceEntry::~DeviceEntry() = default;

std::vector<DeviceEntry> PlaybackList;


void EnumerateDevices(jack_client_t *client, std::vector<DeviceEntry> &list)
{
    std::remove_reference_t<decltype(list)>{}.swap(list);

    if(JackPortsPtr ports{jack_get_ports(client, nullptr, JACK_DEFAULT_AUDIO_TYPE, JackPortIsInput)})
    {
        for(size_t i{0};ports[i];++i)
        {
            const std::string_view portname{ports[i]};
            const size_t seppos{portname.find(':')};
            if(seppos == 0 || seppos >= portname.size())
                continue;

            const auto portdev = portname.substr(0, seppos);
            auto check_name = [portdev](const DeviceEntry &entry) -> bool
            { return entry.mName == portdev; };
            if(std::find_if(list.cbegin(), list.cend(), check_name) != list.cend())
                continue;

            const auto &entry = list.emplace_back(portdev, std::string{portdev}+":");
            TRACE("Got device: %s = %s\n", entry.mName.c_str(), entry.mPattern.c_str());
        }
        /* There are ports but couldn't get device names from them. Add a
         * generic entry.
         */
        if(ports[0] && list.empty())
        {
            WARN("No device names found in available ports, adding a generic name.\n");
            list.emplace_back("JACK"sv, ""sv);
        }
    }

    if(auto listopt = ConfigValueStr({}, "jack", "custom-devices"))
    {
        for(size_t strpos{0};strpos < listopt->size();)
        {
            size_t nextpos{listopt->find(';', strpos)};
            size_t seppos{listopt->find('=', strpos)};
            if(seppos >= nextpos || seppos == strpos)
            {
                const auto entry = std::string_view{*listopt}.substr(strpos, nextpos-strpos);
                ERR("Invalid device entry: \"%.*s\"\n", al::sizei(entry), entry.data());
                if(nextpos != std::string::npos) ++nextpos;
                strpos = nextpos;
                continue;
            }

            const auto name = std::string_view{*listopt}.substr(strpos, seppos-strpos);
            const auto pattern = std::string_view{*listopt}.substr(seppos+1,
                std::min(nextpos, listopt->size())-(seppos+1));

            /* Check if this custom pattern already exists in the list. */
            auto check_pattern = [pattern](const DeviceEntry &entry) -> bool
            { return entry.mPattern == pattern; };
            auto itemmatch = std::find_if(list.begin(), list.end(), check_pattern);
            if(itemmatch != list.end())
            {
                /* If so, replace the name with this custom one. */
                itemmatch->mName = name;
                TRACE("Customized device name: %s = %s\n", itemmatch->mName.c_str(),
                    itemmatch->mPattern.c_str());
            }
            else
            {
                /* Otherwise, add a new device entry. */
                const auto &entry = list.emplace_back(name, pattern);
                TRACE("Got custom device: %s = %s\n", entry.mName.c_str(), entry.mPattern.c_str());
            }

            if(nextpos != std::string::npos) ++nextpos;
            strpos = nextpos;
        }
    }

    if(list.size() > 1)
    {
        /* Rename entries that have matching names, by appending '#2', '#3',
         * etc, as needed.
         */
        for(auto curitem = list.begin()+1;curitem != list.end();++curitem)
        {
            auto check_match = [curitem](const DeviceEntry &entry) -> bool
            { return entry.mName == curitem->mName; };
            if(std::find_if(list.begin(), curitem, check_match) != curitem)
            {
                std::string name{curitem->mName};
                size_t count{1};
                auto check_name = [&name](const DeviceEntry &entry) -> bool
                { return entry.mName == name; };
                do {
                    name = curitem->mName;
                    name += " #";
                    name += std::to_string(++count);
                } while(std::find_if(list.begin(), curitem, check_name) != curitem);
                curitem->mName = std::move(name);
            }
        }
    }
}


struct JackPlayback final : public BackendBase {
    JackPlayback(DeviceBase *device) noexcept : BackendBase{device} { }
    ~JackPlayback() override;

    int processRt(jack_nframes_t numframes) noexcept;
    static int processRtC(jack_nframes_t numframes, void *arg) noexcept
    { return static_cast<JackPlayback*>(arg)->processRt(numframes); }

    int process(jack_nframes_t numframes) noexcept;
    static int processC(jack_nframes_t numframes, void *arg) noexcept
    { return static_cast<JackPlayback*>(arg)->process(numframes); }

    int mixerProc();

    void open(std::string_view name) override;
    bool reset() override;
    void start() override;
    void stop() override;
    ClockLatency getClockLatency() override;

    std::string mPortPattern;

    jack_client_t *mClient{nullptr};
    std::array<jack_port_t*,MaxOutputChannels> mPort{};

    std::mutex mMutex;

    std::atomic<bool> mPlaying{false};
    bool mRTMixing{false};
    RingBufferPtr mRing;
    al::semaphore mSem;

    std::atomic<bool> mKillNow{true};
    std::thread mThread;
};

JackPlayback::~JackPlayback()
{
    if(!mClient)
        return;

    auto unregister_port = [this](jack_port_t *port) -> void
    { if(port) jack_port_unregister(mClient, port); };
    std::for_each(mPort.begin(), mPort.end(), unregister_port);
    mPort.fill(nullptr);

    jack_client_close(mClient);
    mClient = nullptr;
}


int JackPlayback::processRt(jack_nframes_t numframes) noexcept
{
    auto outptrs = std::array<void*,MaxOutputChannels>{};
    auto numchans = size_t{0};
    for(auto port : mPort)
    {
        if(!port || numchans == mDevice->RealOut.Buffer.size())
            break;
        outptrs[numchans++] = jack_port_get_buffer(port, numframes);
    }

    const auto dst = al::span{outptrs}.first(numchans);
    if(mPlaying.load(std::memory_order_acquire)) LIKELY
        mDevice->renderSamples(dst, static_cast<uint>(numframes));
    else
    {
        std::for_each(dst.begin(), dst.end(), [numframes](void *outbuf) -> void
        { std::fill_n(static_cast<float*>(outbuf), numframes, 0.0f); });
    }

    return 0;
}


int JackPlayback::process(jack_nframes_t numframes) noexcept
{
    std::array<al::span<float>,MaxOutputChannels> out;
    size_t numchans{0};
    for(auto port : mPort)
    {
        if(!port) break;
        out[numchans++] = {static_cast<float*>(jack_port_get_buffer(port, numframes)), numframes};
    }

    size_t total{0};
    if(mPlaying.load(std::memory_order_acquire)) LIKELY
    {
        auto data = mRing->getReadVector();
        const auto update_size = size_t{mDevice->UpdateSize};

        const auto outlen = size_t{numframes / update_size};
        const auto len1 = size_t{std::min(data[0].len/update_size, outlen)};
        const auto len2 = size_t{std::min(data[1].len/update_size, outlen-len1)};

        auto src = al::span{reinterpret_cast<float*>(data[0].buf), update_size*len1*numchans};
        for(size_t i{0};i < len1;++i)
        {
            for(size_t c{0};c < numchans;++c)
            {
                const auto iter = std::copy_n(src.begin(), update_size, out[c].begin());
                out[c] = {iter, out[c].end()};
                src = src.subspan(update_size);
            }
            total += update_size;
        }

        src = al::span{reinterpret_cast<float*>(data[1].buf), update_size*len2*numchans};
        for(size_t i{0};i < len2;++i)
        {
            for(size_t c{0};c < numchans;++c)
            {
                const auto iter = std::copy_n(src.begin(), update_size, out[c].begin());
                out[c] = {iter, out[c].end()};
                src = src.subspan(update_size);
            }
            total += update_size;
        }

        mRing->readAdvance(total);
        mSem.post();
    }

    if(numframes > total)
    {
        auto clear_buf = [](const al::span<float> outbuf) -> void
        { std::fill(outbuf.begin(), outbuf.end(), 0.0f); };
        std::for_each(out.begin(), out.begin()+numchans, clear_buf);
    }

    return 0;
}

int JackPlayback::mixerProc()
{
    SetRTPriority();
    althrd_setname(GetMixerThreadName());

    const auto update_size = uint{mDevice->UpdateSize};
    const auto num_channels = size_t{mDevice->channelsFromFmt()};
    auto outptrs = std::vector<void*>(num_channels);

    while(!mKillNow.load(std::memory_order_acquire)
        && mDevice->Connected.load(std::memory_order_acquire))
    {
        if(mRing->writeSpace() < update_size)
        {
            mSem.wait();
            continue;
        }

        auto data = mRing->getWriteVector();
        const auto len1 = size_t{data[0].len / update_size};
        const auto len2 = size_t{data[1].len / update_size};

        std::lock_guard<std::mutex> dlock{mMutex};
        auto buffer = al::span{reinterpret_cast<float*>(data[0].buf), data[0].len*num_channels};
        auto bufiter = buffer.begin();
        for(size_t i{0};i < len1;++i)
        {
            std::generate_n(outptrs.begin(), outptrs.size(), [&bufiter,update_size]
            {
                auto ret = al::to_address(bufiter);
                bufiter += ptrdiff_t(update_size);
                return ret;
            });
            mDevice->renderSamples(outptrs, update_size);
        }
        if(len2 > 0)
        {
            buffer = al::span{reinterpret_cast<float*>(data[1].buf), data[1].len*num_channels};
            bufiter = buffer.begin();
            for(size_t i{0};i < len2;++i)
            {
                std::generate_n(outptrs.begin(), outptrs.size(), [&bufiter,update_size]
                {
                    auto ret = al::to_address(bufiter);
                    bufiter += ptrdiff_t(update_size);
                    return ret;
                });
                mDevice->renderSamples(outptrs, update_size);
            }
        }
        mRing->writeAdvance((len1+len2) * update_size);
    }

    return 0;
}


void JackPlayback::open(std::string_view name)
{
    if(!mClient)
    {
        const PathNamePair &binname = GetProcBinary();
        const char *client_name{binname.fname.empty() ? "alsoft" : binname.fname.c_str()};

        jack_status_t status{};
        mClient = jack_client_open(client_name, ClientOptions, &status, nullptr);
        if(mClient == nullptr)
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to open client connection: 0x%02x", status};
        if((status&JackServerStarted))
            TRACE("JACK server started\n");
        if((status&JackNameNotUnique))
        {
            client_name = jack_get_client_name(mClient);
            TRACE("Client name not unique, got '%s' instead\n", client_name);
        }
    }

    if(PlaybackList.empty())
        EnumerateDevices(mClient, PlaybackList);

    if(name.empty() && !PlaybackList.empty())
    {
        name = PlaybackList[0].mName;
        mPortPattern = PlaybackList[0].mPattern;
    }
    else
    {
        auto check_name = [name](const DeviceEntry &entry) -> bool
        { return entry.mName == name; };
        auto iter = std::find_if(PlaybackList.cbegin(), PlaybackList.cend(), check_name);
        if(iter == PlaybackList.cend())
            throw al::backend_exception{al::backend_error::NoDevice,
                "Device name \"%.*s\" not found", al::sizei(name), name.data()};
        mPortPattern = iter->mPattern;
    }

    mDeviceName = name;
}

bool JackPlayback::reset()
{
    auto unregister_port = [this](jack_port_t *port) -> void
    { if(port) jack_port_unregister(mClient, port); };
    std::for_each(mPort.begin(), mPort.end(), unregister_port);
    mPort.fill(nullptr);

    mRTMixing = GetConfigValueBool(mDevice->mDeviceName, "jack", "rt-mix", true);
    jack_set_process_callback(mClient,
        mRTMixing ? &JackPlayback::processRtC : &JackPlayback::processC, this);

    /* Ignore the requested buffer metrics and just keep one JACK-sized buffer
     * ready for when requested.
     */
    mDevice->Frequency = jack_get_sample_rate(mClient);
    mDevice->UpdateSize = jack_get_buffer_size(mClient);
    if(mRTMixing)
    {
        /* Assume only two periods when directly mixing. Should try to query
         * the total port latency when connected.
         */
        mDevice->BufferSize = mDevice->UpdateSize * 2;
    }
    else
    {
        const auto devname = std::string_view{mDevice->mDeviceName};
        auto bufsize = ConfigValueUInt(devname, "jack", "buffer-size")
            .value_or(mDevice->UpdateSize);
        bufsize = std::max(NextPowerOf2(bufsize), mDevice->UpdateSize);
        mDevice->BufferSize = bufsize + mDevice->UpdateSize;
    }

    /* Force 32-bit float output. */
    mDevice->FmtType = DevFmtFloat;

    int port_num{0};
    auto ports = al::span{mPort}.first(mDevice->channelsFromFmt());
    auto bad_port = ports.begin();
    while(bad_port != ports.end())
    {
        std::string name{"channel_" + std::to_string(++port_num)};
        *bad_port = jack_port_register(mClient, name.c_str(), JACK_DEFAULT_AUDIO_TYPE,
            JackPortIsOutput | JackPortIsTerminal, 0);
        if(!*bad_port) break;
        ++bad_port;
    }
    if(bad_port != ports.end())
    {
        ERR("Failed to register enough JACK ports for %s output\n",
            DevFmtChannelsString(mDevice->FmtChans));
        if(bad_port == ports.begin()) return false;

        if(bad_port == ports.begin()+1)
            mDevice->FmtChans = DevFmtMono;
        else
        {
            const auto ports_end = ports.begin()+2;
            while(bad_port != ports_end)
            {
                jack_port_unregister(mClient, *(--bad_port));
                *bad_port = nullptr;
            }
            mDevice->FmtChans = DevFmtStereo;
        }
    }

    setDefaultChannelOrder();

    return true;
}

void JackPlayback::start()
{
    if(jack_activate(mClient))
        throw al::backend_exception{al::backend_error::DeviceError, "Failed to activate client"};

    const auto devname = std::string_view{mDevice->mDeviceName};
    if(ConfigValueBool(devname, "jack", "connect-ports").value_or(true))
    {
        JackPortsPtr pnames{jack_get_ports(mClient, mPortPattern.c_str(), JACK_DEFAULT_AUDIO_TYPE,
            JackPortIsInput)};
        if(!pnames)
        {
            jack_deactivate(mClient);
            throw al::backend_exception{al::backend_error::DeviceError, "No playback ports found"};
        }

        for(size_t i{0};i < std::size(mPort) && mPort[i];++i)
        {
            if(!pnames[i])
            {
                ERR("No physical playback port for \"%s\"\n", jack_port_name(mPort[i]));
                break;
            }
            if(jack_connect(mClient, jack_port_name(mPort[i]), pnames[i]))
                ERR("Failed to connect output port \"%s\" to \"%s\"\n", jack_port_name(mPort[i]),
                    pnames[i]);
        }
    }

    /* Reconfigure buffer metrics in case the server changed it since the reset
     * (it won't change again after jack_activate), then allocate the ring
     * buffer with the appropriate size.
     */
    mDevice->Frequency = jack_get_sample_rate(mClient);
    mDevice->UpdateSize = jack_get_buffer_size(mClient);
    mDevice->BufferSize = mDevice->UpdateSize * 2;

    mRing = nullptr;
    if(mRTMixing)
        mPlaying.store(true, std::memory_order_release);
    else
    {
        uint bufsize{ConfigValueUInt(devname, "jack", "buffer-size").value_or(mDevice->UpdateSize)};
        bufsize = std::max(NextPowerOf2(bufsize), mDevice->UpdateSize);
        mDevice->BufferSize = bufsize + mDevice->UpdateSize;

        mRing = RingBuffer::Create(bufsize, mDevice->frameSizeFromFmt(), true);

        try {
            mPlaying.store(true, std::memory_order_release);
            mKillNow.store(false, std::memory_order_release);
            mThread = std::thread{std::mem_fn(&JackPlayback::mixerProc), this};
        }
        catch(std::exception& e) {
            jack_deactivate(mClient);
            mPlaying.store(false, std::memory_order_release);
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to start mixing thread: %s", e.what()};
        }
    }
}

void JackPlayback::stop()
{
    if(mPlaying.load(std::memory_order_acquire))
    {
        mKillNow.store(true, std::memory_order_release);
        if(mThread.joinable())
        {
            mSem.post();
            mThread.join();
        }

        jack_deactivate(mClient);
        mPlaying.store(false, std::memory_order_release);
    }
}


ClockLatency JackPlayback::getClockLatency()
{
    std::lock_guard<std::mutex> dlock{mMutex};
    ClockLatency ret{};
    ret.ClockTime = mDevice->getClockTime();
    ret.Latency  = std::chrono::seconds{mRing ? mRing->readSpace() : mDevice->UpdateSize};
    ret.Latency /= mDevice->Frequency;

    return ret;
}


void jack_msg_handler(const char *message)
{
    WARN("%s\n", message);
}

} // namespace

bool JackBackendFactory::init()
{
    if(!jack_load())
        return false;

    if(!GetConfigValueBool({}, "jack", "spawn-server", false))
        ClientOptions = static_cast<jack_options_t>(ClientOptions | JackNoStartServer);

    const PathNamePair &binname = GetProcBinary();
    const char *client_name{binname.fname.empty() ? "alsoft" : binname.fname.c_str()};

    void (*old_error_cb)(const char*){&jack_error_callback ? jack_error_callback : nullptr};
    jack_set_error_function(jack_msg_handler);
    jack_status_t status{};
    jack_client_t *client{jack_client_open(client_name, ClientOptions, &status, nullptr)};
    jack_set_error_function(old_error_cb);
    if(!client)
    {
        WARN("jack_client_open() failed, 0x%02x\n", status);
        if((status&JackServerFailed) && !(ClientOptions&JackNoStartServer))
            ERR("Unable to connect to JACK server\n");
        return false;
    }

    jack_client_close(client);
    return true;
}

bool JackBackendFactory::querySupport(BackendType type)
{ return (type == BackendType::Playback); }

auto JackBackendFactory::enumerate(BackendType type) -> std::vector<std::string>
{
    std::vector<std::string> outnames;
    auto append_name = [&outnames](const DeviceEntry &entry) -> void
    { outnames.emplace_back(entry.mName); };

    const PathNamePair &binname = GetProcBinary();
    const char *client_name{binname.fname.empty() ? "alsoft" : binname.fname.c_str()};
    jack_status_t status{};
    switch(type)
    {
    case BackendType::Playback:
        if(jack_client_t *client{jack_client_open(client_name, ClientOptions, &status, nullptr)})
        {
            EnumerateDevices(client, PlaybackList);
            jack_client_close(client);
        }
        else
            WARN("jack_client_open() failed, 0x%02x\n", status);
        outnames.reserve(PlaybackList.size());
        std::for_each(PlaybackList.cbegin(), PlaybackList.cend(), append_name);
        break;
    case BackendType::Capture:
        break;
    }
    return outnames;
}

BackendPtr JackBackendFactory::createBackend(DeviceBase *device, BackendType type)
{
    if(type == BackendType::Playback)
        return BackendPtr{new JackPlayback{device}};
    return nullptr;
}

BackendFactory &JackBackendFactory::getFactory()
{
    static JackBackendFactory factory{};
    return factory;
}
