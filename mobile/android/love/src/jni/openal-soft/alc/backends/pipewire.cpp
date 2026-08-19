/**
 * OpenAL cross platform audio library
 * Copyright (C) 2010 by Chris Robinson
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

#include "pipewire.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <bitset>
#include <cinttypes>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <chrono>
#include <ctime>
#include <iterator>
#include <memory>
#include <mutex>
#include <optional>
#include <string_view>
#include <thread>
#include <tuple>
#include <utility>

#include "alc/alconfig.h"
#include "alc/backends/base.h"
#include "almalloc.h"
#include "alspan.h"
#include "alstring.h"
#include "core/devformat.h"
#include "core/device.h"
#include "core/helpers.h"
#include "core/logging.h"
#include "dynload.h"
#include "opthelpers.h"
#include "ringbuffer.h"

/* Ignore warnings caused by PipeWire headers (lots in standard C++ mode). GCC
 * doesn't support ignoring -Weverything, so we have the list the individual
 * warnings to ignore (and ignoring -Winline doesn't seem to work).
 */
_Pragma("GCC diagnostic push")
_Pragma("GCC diagnostic ignored \"-Wpedantic\"")
_Pragma("GCC diagnostic ignored \"-Wconversion\"")
_Pragma("GCC diagnostic ignored \"-Wfloat-conversion\"")
_Pragma("GCC diagnostic ignored \"-Wmissing-field-initializers\"")
_Pragma("GCC diagnostic ignored \"-Wunused-parameter\"")
_Pragma("GCC diagnostic ignored \"-Wold-style-cast\"")
_Pragma("GCC diagnostic ignored \"-Wsign-compare\"")
_Pragma("GCC diagnostic ignored \"-Winline\"")
_Pragma("GCC diagnostic ignored \"-Wpragmas\"")
_Pragma("GCC diagnostic ignored \"-Weverything\"")
#include "pipewire/pipewire.h"
#include "pipewire/extensions/metadata.h"
#include "spa/buffer/buffer.h"
#include "spa/param/audio/format-utils.h"
#include "spa/param/audio/raw.h"
#include "spa/param/format.h"
#include "spa/param/param.h"
#include "spa/pod/builder.h"
#include "spa/utils/json.h"

/* NOLINTBEGIN : All kinds of unsafe C stuff here from PipeWire headers
 * (function-like macros, C style casts in macros, etc), which we can't do
 * anything about except wrap into inline functions.
 */
namespace {
/* Wrap some nasty macros here too... */
template<typename ...Args>
auto ppw_core_add_listener(pw_core *core, Args&& ...args)
{ return pw_core_add_listener(core, std::forward<Args>(args)...); }
template<typename ...Args>
auto ppw_core_sync(pw_core *core, Args&& ...args)
{ return pw_core_sync(core, std::forward<Args>(args)...); }
template<typename ...Args>
auto ppw_registry_add_listener(pw_registry *reg, Args&& ...args)
{ return pw_registry_add_listener(reg, std::forward<Args>(args)...); }
template<typename ...Args>
auto ppw_node_add_listener(pw_node *node, Args&& ...args)
{ return pw_node_add_listener(node, std::forward<Args>(args)...); }
template<typename ...Args>
auto ppw_node_subscribe_params(pw_node *node, Args&& ...args)
{ return pw_node_subscribe_params(node, std::forward<Args>(args)...); }
template<typename ...Args>
auto ppw_metadata_add_listener(pw_metadata *mdata, Args&& ...args)
{ return pw_metadata_add_listener(mdata, std::forward<Args>(args)...); }


constexpr auto get_pod_type(const spa_pod *pod) noexcept
{ return SPA_POD_TYPE(pod); }

template<typename T>
constexpr auto get_pod_body(const spa_pod *pod, size_t count) noexcept
{ return al::span<T>{static_cast<T*>(SPA_POD_BODY(pod)), count}; }
template<typename T, size_t N>
constexpr auto get_pod_body(const spa_pod *pod) noexcept
{ return al::span<T,N>{static_cast<T*>(SPA_POD_BODY(pod)), N}; }

constexpr auto get_array_value_type(const spa_pod *pod) noexcept
{ return SPA_POD_ARRAY_VALUE_TYPE(pod); }

constexpr auto make_pod_builder(void *data, uint32_t size) noexcept
{ return SPA_POD_BUILDER_INIT(data, size); }

constexpr auto PwIdAny = PW_ID_ANY;

} // namespace
/* NOLINTEND */
_Pragma("GCC diagnostic pop")

namespace {

template<typename T> [[nodiscard]] constexpr
auto as_const_ptr(T *ptr) noexcept -> std::add_const_t<T>* { return ptr; }

struct PodDynamicBuilder {
private:
    std::vector<std::byte> mStorage;
    spa_pod_builder mPod{};

    int overflow(uint32_t size) noexcept
    {
        try {
            mStorage.resize(size);
        }
        catch(...) {
            ERR("Failed to resize POD storage\n");
            return -ENOMEM;
        }
        mPod.data = mStorage.data();
        mPod.size = size;
        return 0;
    }

public:
    PodDynamicBuilder(uint32_t initSize=1024) : mStorage(initSize)
        , mPod{make_pod_builder(mStorage.data(), initSize)}
    {
        static constexpr auto callbacks{[]
        {
            spa_pod_builder_callbacks cb{};
            cb.version = SPA_VERSION_POD_BUILDER_CALLBACKS;
            cb.overflow = [](void *data, uint32_t size) noexcept
            { return static_cast<PodDynamicBuilder*>(data)->overflow(size); };
            return cb;
        }()};

        spa_pod_builder_set_callbacks(&mPod, &callbacks, this);
    }

    spa_pod_builder *get() noexcept { return &mPod; }
};

/* Added in 0.3.33, but we currently only require 0.3.23. */
#ifndef PW_KEY_NODE_RATE
#define PW_KEY_NODE_RATE "node.rate"
#endif

using namespace std::string_view_literals;
using std::chrono::seconds;
using std::chrono::milliseconds;
using std::chrono::nanoseconds;
using uint = unsigned int;


bool check_version(const char *version)
{
    /* There doesn't seem to be a function to get the version as an integer, so
     * instead we have to parse the string, which hopefully won't break in the
     * future.
     */
    int major{0}, minor{0}, revision{0};
    int ret{sscanf(version, "%d.%d.%d", &major, &minor, &revision)};
    return ret == 3 && (major > PW_MAJOR || (major == PW_MAJOR && minor > PW_MINOR)
        || (major == PW_MAJOR && minor == PW_MINOR && revision >= PW_MICRO));
}

#ifdef HAVE_DYNLOAD
#define PWIRE_FUNCS(MAGIC)                                                    \
    MAGIC(pw_context_connect)                                                 \
    MAGIC(pw_context_destroy)                                                 \
    MAGIC(pw_context_new)                                                     \
    MAGIC(pw_core_disconnect)                                                 \
    MAGIC(pw_get_library_version)                                             \
    MAGIC(pw_init)                                                            \
    MAGIC(pw_properties_free)                                                 \
    MAGIC(pw_properties_new)                                                  \
    MAGIC(pw_properties_set)                                                  \
    MAGIC(pw_properties_setf)                                                 \
    MAGIC(pw_proxy_add_object_listener)                                       \
    MAGIC(pw_proxy_destroy)                                                   \
    MAGIC(pw_proxy_get_user_data)                                             \
    MAGIC(pw_stream_add_listener)                                             \
    MAGIC(pw_stream_connect)                                                  \
    MAGIC(pw_stream_dequeue_buffer)                                           \
    MAGIC(pw_stream_destroy)                                                  \
    MAGIC(pw_stream_get_state)                                                \
    MAGIC(pw_stream_new)                                                      \
    MAGIC(pw_stream_queue_buffer)                                             \
    MAGIC(pw_stream_set_active)                                               \
    MAGIC(pw_thread_loop_new)                                                 \
    MAGIC(pw_thread_loop_destroy)                                             \
    MAGIC(pw_thread_loop_get_loop)                                            \
    MAGIC(pw_thread_loop_start)                                               \
    MAGIC(pw_thread_loop_stop)                                                \
    MAGIC(pw_thread_loop_lock)                                                \
    MAGIC(pw_thread_loop_wait)                                                \
    MAGIC(pw_thread_loop_signal)                                              \
    MAGIC(pw_thread_loop_unlock)
#if PW_CHECK_VERSION(0,3,50)
#define PWIRE_FUNCS2(MAGIC)                                                   \
    MAGIC(pw_stream_get_time_n)
#else
#define PWIRE_FUNCS2(MAGIC)                                                   \
    MAGIC(pw_stream_get_time)
#endif

void *pwire_handle;
#define MAKE_FUNC(f) decltype(f) * p##f;
PWIRE_FUNCS(MAKE_FUNC)
PWIRE_FUNCS2(MAKE_FUNC)
#undef MAKE_FUNC

bool pwire_load()
{
    if(pwire_handle)
        return true;

    const char *pwire_library{"libpipewire-0.3.so.0"};
    std::string missing_funcs;

    pwire_handle = LoadLib(pwire_library);
    if(!pwire_handle)
    {
        WARN("Failed to load %s\n", pwire_library);
        return false;
    }

#define LOAD_FUNC(f) do {                                                     \
    p##f = reinterpret_cast<decltype(p##f)>(GetSymbol(pwire_handle, #f));     \
    if(p##f == nullptr) missing_funcs += "\n" #f;                             \
} while(0);
    PWIRE_FUNCS(LOAD_FUNC)
    PWIRE_FUNCS2(LOAD_FUNC)
#undef LOAD_FUNC

    if(!missing_funcs.empty())
    {
        WARN("Missing expected functions:%s\n", missing_funcs.c_str());
        CloseLib(pwire_handle);
        pwire_handle = nullptr;
        return false;
    }

    return true;
}

#ifndef IN_IDE_PARSER
#define pw_context_connect ppw_context_connect
#define pw_context_destroy ppw_context_destroy
#define pw_context_new ppw_context_new
#define pw_core_disconnect ppw_core_disconnect
#define pw_get_library_version ppw_get_library_version
#define pw_init ppw_init
#define pw_properties_free ppw_properties_free
#define pw_properties_new ppw_properties_new
#define pw_properties_set ppw_properties_set
#define pw_properties_setf ppw_properties_setf
#define pw_proxy_add_object_listener ppw_proxy_add_object_listener
#define pw_proxy_destroy ppw_proxy_destroy
#define pw_proxy_get_user_data ppw_proxy_get_user_data
#define pw_stream_add_listener ppw_stream_add_listener
#define pw_stream_connect ppw_stream_connect
#define pw_stream_dequeue_buffer ppw_stream_dequeue_buffer
#define pw_stream_destroy ppw_stream_destroy
#define pw_stream_get_state ppw_stream_get_state
#define pw_stream_new ppw_stream_new
#define pw_stream_queue_buffer ppw_stream_queue_buffer
#define pw_stream_set_active ppw_stream_set_active
#define pw_thread_loop_destroy ppw_thread_loop_destroy
#define pw_thread_loop_get_loop ppw_thread_loop_get_loop
#define pw_thread_loop_lock ppw_thread_loop_lock
#define pw_thread_loop_new ppw_thread_loop_new
#define pw_thread_loop_signal ppw_thread_loop_signal
#define pw_thread_loop_start ppw_thread_loop_start
#define pw_thread_loop_stop ppw_thread_loop_stop
#define pw_thread_loop_unlock ppw_thread_loop_unlock
#define pw_thread_loop_wait ppw_thread_loop_wait
#if PW_CHECK_VERSION(0,3,50)
#define pw_stream_get_time_n ppw_stream_get_time_n
#else
inline auto pw_stream_get_time_n(pw_stream *stream, pw_time *ptime, size_t /*size*/)
{ return ppw_stream_get_time(stream, ptime); }
#endif
#endif

#else

constexpr bool pwire_load() { return true; }
#endif

/* Helpers for retrieving values from params */
template<uint32_t T> struct PodInfo { };

template<>
struct PodInfo<SPA_TYPE_Int> {
    using Type = int32_t;
    static auto get_value(const spa_pod *pod, int32_t *val)
    { return spa_pod_get_int(pod, val); }
};
template<>
struct PodInfo<SPA_TYPE_Id> {
    using Type = uint32_t;
    static auto get_value(const spa_pod *pod, uint32_t *val)
    { return spa_pod_get_id(pod, val); }
};

template<uint32_t T>
using Pod_t = typename PodInfo<T>::Type;

template<uint32_t T>
al::span<const Pod_t<T>> get_array_span(const spa_pod *pod)
{
    uint32_t nvals{};
    if(void *v{spa_pod_get_array(pod, &nvals)})
    {
        if(get_array_value_type(pod) == T)
            return {static_cast<const Pod_t<T>*>(v), nvals};
    }
    return {};
}

template<uint32_t T>
std::optional<Pod_t<T>> get_value(const spa_pod *value)
{
    Pod_t<T> val{};
    if(PodInfo<T>::get_value(value, &val) == 0)
        return val;
    return std::nullopt;
}

/* Internally, PipeWire types "inherit" from each other, but this is hidden
 * from the API and the caller is expected to C-style cast to inherited types
 * as needed. It's also not made very clear what types a given type can be
 * casted to. To make it a bit safer, this as() method allows casting pw_*
 * types to known inherited types, generating a compile-time error for
 * unexpected/invalid casts.
 */
template<typename To, typename From>
To as(From) noexcept = delete;

/* pw_proxy
 * - pw_registry
 * - pw_node
 * - pw_metadata
 */
template<>
pw_proxy* as(pw_registry *reg) noexcept { return reinterpret_cast<pw_proxy*>(reg); }
template<>
pw_proxy* as(pw_node *node) noexcept { return reinterpret_cast<pw_proxy*>(node); }
template<>
pw_proxy* as(pw_metadata *mdata) noexcept { return reinterpret_cast<pw_proxy*>(mdata); }


struct PwContextDeleter {
    void operator()(pw_context *context) const { pw_context_destroy(context); }
};
using PwContextPtr = std::unique_ptr<pw_context,PwContextDeleter>;

struct PwCoreDeleter {
    void operator()(pw_core *core) const { pw_core_disconnect(core); }
};
using PwCorePtr = std::unique_ptr<pw_core,PwCoreDeleter>;

struct PwRegistryDeleter {
    void operator()(pw_registry *reg) const { pw_proxy_destroy(as<pw_proxy*>(reg)); }
};
using PwRegistryPtr = std::unique_ptr<pw_registry,PwRegistryDeleter>;

struct PwNodeDeleter {
    void operator()(pw_node *node) const { pw_proxy_destroy(as<pw_proxy*>(node)); }
};
using PwNodePtr = std::unique_ptr<pw_node,PwNodeDeleter>;

struct PwMetadataDeleter {
    void operator()(pw_metadata *mdata) const { pw_proxy_destroy(as<pw_proxy*>(mdata)); }
};
using PwMetadataPtr = std::unique_ptr<pw_metadata,PwMetadataDeleter>;

struct PwStreamDeleter {
    void operator()(pw_stream *stream) const { pw_stream_destroy(stream); }
};
using PwStreamPtr = std::unique_ptr<pw_stream,PwStreamDeleter>;

/* NOLINTBEGIN(*EnumCastOutOfRange) Enums for bitflags... again... *sigh* */
constexpr pw_stream_flags operator|(pw_stream_flags lhs, pw_stream_flags rhs) noexcept
{ return static_cast<pw_stream_flags>(lhs | al::to_underlying(rhs)); }
/* NOLINTEND(*EnumCastOutOfRange) */

constexpr pw_stream_flags& operator|=(pw_stream_flags &lhs, pw_stream_flags rhs) noexcept
{ lhs = lhs | rhs; return lhs; }

class ThreadMainloop {
    pw_thread_loop *mLoop{};

public:
    ThreadMainloop() = default;
    ThreadMainloop(const ThreadMainloop&) = delete;
    ThreadMainloop(ThreadMainloop&& rhs) noexcept : mLoop{rhs.mLoop} { rhs.mLoop = nullptr; }
    explicit ThreadMainloop(pw_thread_loop *loop) noexcept : mLoop{loop} { }
    ~ThreadMainloop() { if(mLoop) pw_thread_loop_destroy(mLoop); }

    ThreadMainloop& operator=(const ThreadMainloop&) = delete;
    ThreadMainloop& operator=(ThreadMainloop&& rhs) noexcept
    { std::swap(mLoop, rhs.mLoop); return *this; }
    ThreadMainloop& operator=(std::nullptr_t) noexcept
    {
        if(mLoop)
            pw_thread_loop_destroy(mLoop);
        mLoop = nullptr;
        return *this;
    }

    explicit operator bool() const noexcept { return mLoop != nullptr; }

    [[nodiscard]]
    auto start() const { return pw_thread_loop_start(mLoop); }
    auto stop() const { return pw_thread_loop_stop(mLoop); }

    [[nodiscard]]
    auto getLoop() const { return pw_thread_loop_get_loop(mLoop); }

    auto lock() const { return pw_thread_loop_lock(mLoop); }
    auto unlock() const { return pw_thread_loop_unlock(mLoop); }

    auto signal(bool wait) const { return pw_thread_loop_signal(mLoop, wait); }

    auto newContext(pw_properties *props=nullptr, size_t user_data_size=0) const
    { return PwContextPtr{pw_context_new(getLoop(), props, user_data_size)}; }

    static auto Create(const char *name, spa_dict *props=nullptr)
    { return ThreadMainloop{pw_thread_loop_new(name, props)}; }

    friend struct MainloopUniqueLock;
};
struct MainloopUniqueLock : public std::unique_lock<ThreadMainloop> {
    using std::unique_lock<ThreadMainloop>::unique_lock;
    MainloopUniqueLock& operator=(MainloopUniqueLock&&) = default;

    auto wait() const -> void
    { pw_thread_loop_wait(mutex()->mLoop); }

    template<typename Predicate>
    auto wait(Predicate done_waiting) const -> void
    { while(!done_waiting()) wait(); }
};
using MainloopLockGuard = std::lock_guard<ThreadMainloop>;


/* There's quite a mess here, but the purpose is to track active devices and
 * their default formats, so playback devices can be configured to match. The
 * device list is updated asynchronously, so it will have the latest list of
 * devices provided by the server.
 */

/* A generic PipeWire node proxy object used to track changes to sink and
 * source nodes.
 */
struct NodeProxy {
    static constexpr pw_node_events CreateNodeEvents()
    {
        pw_node_events ret{};
        ret.version = PW_VERSION_NODE_EVENTS;
        ret.info = infoCallback;
        ret.param = [](void *object, int seq, uint32_t id, uint32_t index, uint32_t next, const spa_pod *param) noexcept
        { static_cast<NodeProxy*>(object)->paramCallback(seq, id, index, next, param); };
        return ret;
    }

    uint32_t mId{};

    PwNodePtr mNode{};
    spa_hook mListener{};

    NodeProxy(uint32_t id, PwNodePtr node)
      : mId{id}, mNode{std::move(node)}
    {
        static constexpr pw_node_events nodeEvents{CreateNodeEvents()};
        ppw_node_add_listener(mNode.get(), &mListener, &nodeEvents, this);

        /* Track changes to the enumerable and current formats (indicates the
         * default and active format, which is what we're interested in).
         */
        std::array<uint32_t,2> fmtids{{SPA_PARAM_EnumFormat, SPA_PARAM_Format}};
        ppw_node_subscribe_params(mNode.get(), fmtids.data(), fmtids.size());
    }
    ~NodeProxy()
    { spa_hook_remove(&mListener); }


    static void infoCallback(void *object, const pw_node_info *info) noexcept;
    void paramCallback(int seq, uint32_t id, uint32_t index, uint32_t next, const spa_pod *param) const noexcept;
};

/* A metadata proxy object used to query the default sink and source. */
struct MetadataProxy {
    static constexpr pw_metadata_events CreateMetadataEvents()
    {
        pw_metadata_events ret{};
        ret.version = PW_VERSION_METADATA_EVENTS;
        ret.property = propertyCallback;
        return ret;
    }

    uint32_t mId{};

    PwMetadataPtr mMetadata{};
    spa_hook mListener{};

    MetadataProxy(uint32_t id, PwMetadataPtr mdata)
      : mId{id}, mMetadata{std::move(mdata)}
    {
        static constexpr pw_metadata_events metadataEvents{CreateMetadataEvents()};
        ppw_metadata_add_listener(mMetadata.get(), &mListener, &metadataEvents, this);
    }
    ~MetadataProxy()
    { spa_hook_remove(&mListener); }

    static auto propertyCallback(void *object, uint32_t id, const char *key, const char *type,
        const char *value) noexcept -> int;
};


/* The global thread watching for global events. This particular class responds
 * to objects being added to or removed from the registry.
 */
struct EventManager {
    ThreadMainloop mLoop{};
    PwContextPtr mContext{};
    PwCorePtr mCore{};
    PwRegistryPtr mRegistry{};
    spa_hook mRegistryListener{};
    spa_hook mCoreListener{};

    /* A list of proxy objects watching for events about changes to objects in
     * the registry.
     */
    std::vector<std::unique_ptr<NodeProxy>> mNodeList;
    std::optional<MetadataProxy> mDefaultMetadata;

    /* Initialization handling. When init() is called, mInitSeq is set to a
     * SequenceID that marks the end of populating the registry. As objects of
     * interest are found, events to parse them are generated and mInitSeq is
     * updated with a newer ID. When mInitSeq stops being updated and the event
     * corresponding to it is reached, mInitDone will be set to true.
     */
    std::atomic<bool> mInitDone{false};
    std::atomic<bool> mHasAudio{false};
    int mInitSeq{};

    ~EventManager() { if(mLoop) mLoop.stop(); }

    bool init();

    void kill();

    auto lock() const { return mLoop.lock(); }
    auto unlock() const { return mLoop.unlock(); }

    [[nodiscard]] inline
    bool initIsDone(std::memory_order m=std::memory_order_seq_cst) const noexcept
    { return mInitDone.load(m); }

    /**
     * Waits for initialization to finish. The event manager must *NOT* be
     * locked when calling this.
     */
    void waitForInit()
    {
        if(!initIsDone(std::memory_order_acquire)) UNLIKELY
        {
            MainloopUniqueLock plock{mLoop};
            plock.wait([this](){ return initIsDone(std::memory_order_acquire); });
        }
    }

    /**
     * Waits for audio support to be detected, or initialization to finish,
     * whichever is first. Returns true if audio support was detected. The
     * event manager must *NOT* be locked when calling this.
     */
    bool waitForAudio()
    {
        MainloopUniqueLock plock{mLoop};
        bool has_audio{};
        plock.wait([this,&has_audio]()
        {
            has_audio = mHasAudio.load(std::memory_order_acquire);
            return has_audio || initIsDone(std::memory_order_acquire);
        });
        return has_audio;
    }

    void syncInit()
    {
        /* If initialization isn't done, update the sequence ID so it won't
         * complete until after currently scheduled events.
         */
        if(!initIsDone(std::memory_order_relaxed))
            mInitSeq = ppw_core_sync(mCore.get(), PW_ID_CORE, mInitSeq);
    }

    void addCallback(uint32_t id, uint32_t permissions, const char *type, uint32_t version,
        const spa_dict *props) noexcept;

    void removeCallback(uint32_t id) noexcept;

    static constexpr pw_registry_events CreateRegistryEvents()
    {
        pw_registry_events ret{};
        ret.version = PW_VERSION_REGISTRY_EVENTS;
        ret.global = [](void *object, uint32_t id, uint32_t permissions, const char *type, uint32_t version, const spa_dict *props) noexcept
        { static_cast<EventManager*>(object)->addCallback(id, permissions, type, version, props); };
        ret.global_remove = [](void *object, uint32_t id) noexcept
        { static_cast<EventManager*>(object)->removeCallback(id); };
        return ret;
    }

    void coreCallback(uint32_t id, int seq) noexcept;

    static constexpr pw_core_events CreateCoreEvents()
    {
        pw_core_events ret{};
        ret.version = PW_VERSION_CORE_EVENTS;
        ret.done = [](void *object, uint32_t id, int seq) noexcept
        { static_cast<EventManager*>(object)->coreCallback(id, seq); };
        return ret;
    }
};
using EventWatcherUniqueLock = std::unique_lock<EventManager>;
using EventWatcherLockGuard = std::lock_guard<EventManager>;

EventManager gEventHandler;

/* Enumerated devices. This is updated asynchronously as the app runs, and the
 * gEventHandler thread loop must be locked when accessing the list.
 */
enum class NodeType : unsigned char {
    Sink, Source, Duplex
};
constexpr auto InvalidChannelConfig = DevFmtChannels(255);
struct DeviceNode {
    uint32_t mId{};

    uint64_t mSerial{};
    std::string mName;
    std::string mDevName;

    NodeType mType{};
    bool mIsHeadphones{};
    bool mIs51Rear{};

    uint mSampleRate{};
    DevFmtChannels mChannels{InvalidChannelConfig};

    static std::vector<DeviceNode> sList;
    static DeviceNode &Add(uint32_t id);
    static DeviceNode *Find(uint32_t id);
    static DeviceNode *FindByDevName(std::string_view devname);
    static void Remove(uint32_t id);
    static auto GetList() noexcept { return al::span{sList}; }

    void parseSampleRate(const spa_pod *value, bool force_update) noexcept;
    void parsePositions(const spa_pod *value, bool force_update) noexcept;
    void parseChannelCount(const spa_pod *value, bool force_update) noexcept;

    void callEvent(alc::EventType type, std::string_view message) const
    {
        /* Source nodes aren't recognized for playback, only Sink and Duplex
         * nodes are. All node types are recognized for capture.
         */
        if(mType != NodeType::Source)
            alc::Event(type, alc::DeviceType::Playback, message);
        alc::Event(type, alc::DeviceType::Capture, message);
    }
};
std::vector<DeviceNode> DeviceNode::sList;
std::string DefaultSinkDevice;
std::string DefaultSourceDevice;

const char *AsString(NodeType type) noexcept
{
    switch(type)
    {
    case NodeType::Sink: return "sink";
    case NodeType::Source: return "source";
    case NodeType::Duplex: return "duplex";
    }
    return "<unknown>";
}

DeviceNode &DeviceNode::Add(uint32_t id)
{
    auto match_id = [id](DeviceNode &n) noexcept -> bool
    { return n.mId == id; };

    /* If the node is already in the list, return the existing entry. */
    auto match = std::find_if(sList.begin(), sList.end(), match_id);
    if(match != sList.end()) return *match;

    auto &n = sList.emplace_back();
    n.mId = id;
    return n;
}

DeviceNode *DeviceNode::Find(uint32_t id)
{
    auto match_id = [id](DeviceNode &n) noexcept -> bool
    { return n.mId == id; };

    auto match = std::find_if(sList.begin(), sList.end(), match_id);
    if(match != sList.end()) return al::to_address(match);

    return nullptr;
}

DeviceNode *DeviceNode::FindByDevName(std::string_view devname)
{
    auto match_id = [devname](DeviceNode &n) noexcept -> bool
    { return n.mDevName == devname; };

    auto match = std::find_if(sList.begin(), sList.end(), match_id);
    if(match != sList.end()) return al::to_address(match);

    return nullptr;
}

void DeviceNode::Remove(uint32_t id)
{
    auto match_id = [id](DeviceNode &n) noexcept -> bool
    {
        if(n.mId != id)
            return false;
        TRACE("Removing device \"%s\"\n", n.mDevName.c_str());
        if(gEventHandler.initIsDone(std::memory_order_relaxed))
        {
            const std::string msg{"Device removed: "+n.mName};
            n.callEvent(alc::EventType::DeviceRemoved, msg);
        }
        return true;
    };

    auto end = std::remove_if(sList.begin(), sList.end(), match_id);
    sList.erase(end, sList.end());
}


constexpr std::array MonoMap{
    SPA_AUDIO_CHANNEL_MONO
};
constexpr std::array StereoMap{
    SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR
};
constexpr std::array QuadMap{
    SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR
};
constexpr std::array X51Map{
    SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC, SPA_AUDIO_CHANNEL_LFE,
    SPA_AUDIO_CHANNEL_SL, SPA_AUDIO_CHANNEL_SR
};
constexpr std::array X51RearMap{
    SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC, SPA_AUDIO_CHANNEL_LFE,
    SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR
};
constexpr std::array X61Map{
    SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC, SPA_AUDIO_CHANNEL_LFE,
    SPA_AUDIO_CHANNEL_RC, SPA_AUDIO_CHANNEL_SL, SPA_AUDIO_CHANNEL_SR
};
constexpr std::array X71Map{
    SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC, SPA_AUDIO_CHANNEL_LFE,
    SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR, SPA_AUDIO_CHANNEL_SL, SPA_AUDIO_CHANNEL_SR
};
constexpr std::array X714Map{
    SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC, SPA_AUDIO_CHANNEL_LFE,
    SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR, SPA_AUDIO_CHANNEL_SL, SPA_AUDIO_CHANNEL_SR,
    SPA_AUDIO_CHANNEL_TFL, SPA_AUDIO_CHANNEL_TFR, SPA_AUDIO_CHANNEL_TRL, SPA_AUDIO_CHANNEL_TRR
};

/**
 * Checks if every channel in 'map1' exists in 'map0' (that is, map0 is equal
 * to or a superset of map1).
 */
bool MatchChannelMap(const al::span<const uint32_t> map0,
    const al::span<const spa_audio_channel> map1)
{
    if(map0.size() < map1.size())
        return false;

    auto find_channel = [map0](const spa_audio_channel chid) -> bool
    { return std::find(map0.begin(), map0.end(), chid) != map0.end(); };
    return std::all_of(map1.cbegin(), map1.cend(), find_channel);
}

void DeviceNode::parseSampleRate(const spa_pod *value, bool force_update) noexcept
{
    /* TODO: Can this be anything else? Long, Float, Double? */
    uint32_t nvals{}, choiceType{};
    value = spa_pod_get_values(value, &nvals, &choiceType);

    const uint podType{get_pod_type(value)};
    if(podType != SPA_TYPE_Int)
    {
        WARN("  Unhandled sample rate POD type: %u\n", podType);
        return;
    }

    if(choiceType == SPA_CHOICE_Range)
    {
        if(nvals != 3)
        {
            WARN("  Unexpected SPA_CHOICE_Range count: %u\n", nvals);
            return;
        }
        auto srates = get_pod_body<int32_t,3>(value);

        /* [0] is the default, [1] is the min, and [2] is the max. */
        TRACE("  sample rate: %d (range: %d -> %d)\n", srates[0], srates[1], srates[2]);
        if(!mSampleRate || force_update)
            mSampleRate = static_cast<uint>(std::clamp<int>(srates[0], MinOutputRate,
                MaxOutputRate));
        return;
    }

    if(choiceType == SPA_CHOICE_Enum)
    {
        if(nvals == 0)
        {
            WARN("  Unexpected SPA_CHOICE_Enum count: %u\n", nvals);
            return;
        }
        auto srates = get_pod_body<int32_t>(value, nvals);

        /* [0] is the default, [1...size()-1] are available selections. */
        std::string others{(srates.size() > 1) ? std::to_string(srates[1]) : std::string{}};
        for(size_t i{2};i < srates.size();++i)
        {
            others += ", ";
            others += std::to_string(srates[i]);
        }
        TRACE("  sample rate: %d (%s)\n", srates[0], others.c_str());
        /* Pick the first rate listed that's within the allowed range (default
         * rate if possible).
         */
        for(const auto &rate : srates)
        {
            if(rate >= int{MinOutputRate} && rate <= int{MaxOutputRate})
            {
                if(!mSampleRate || force_update)
                    mSampleRate = static_cast<uint>(rate);
                break;
            }
        }
        return;
    }

    if(choiceType == SPA_CHOICE_None)
    {
        if(nvals != 1)
        {
            WARN("  Unexpected SPA_CHOICE_None count: %u\n", nvals);
            return;
        }
        auto srates = get_pod_body<int32_t,1>(value);

        TRACE("  sample rate: %d\n", srates[0]);
        if(!mSampleRate || force_update)
            mSampleRate = static_cast<uint>(std::clamp<int>(srates[0], MinOutputRate,
                MaxOutputRate));
        return;
    }

    WARN("  Unhandled sample rate choice type: %u\n", choiceType);
}

void DeviceNode::parsePositions(const spa_pod *value, bool force_update) noexcept
{
    uint32_t choiceCount{}, choiceType{};
    value = spa_pod_get_values(value, &choiceCount, &choiceType);

    if(choiceType != SPA_CHOICE_None || choiceCount != 1)
    {
        ERR("  Unexpected positions choice: type=%u, count=%u\n", choiceType, choiceCount);
        return;
    }

    const auto chanmap = get_array_span<SPA_TYPE_Id>(value);
    if(chanmap.empty()) return;

    if(mChannels == InvalidChannelConfig || force_update)
    {
        mIs51Rear = false;

        if(MatchChannelMap(chanmap, X714Map))
            mChannels = DevFmtX714;
        else if(MatchChannelMap(chanmap, X71Map))
            mChannels = DevFmtX71;
        else if(MatchChannelMap(chanmap, X61Map))
            mChannels = DevFmtX61;
        else if(MatchChannelMap(chanmap, X51Map))
            mChannels = DevFmtX51;
        else if(MatchChannelMap(chanmap, X51RearMap))
        {
            mChannels = DevFmtX51;
            mIs51Rear = true;
        }
        else if(MatchChannelMap(chanmap, QuadMap))
            mChannels = DevFmtQuad;
        else if(MatchChannelMap(chanmap, StereoMap))
            mChannels = DevFmtStereo;
        else
            mChannels = DevFmtMono;
    }
    TRACE("  %zu position%s for %s%s\n", chanmap.size(), (chanmap.size()==1)?"":"s",
        DevFmtChannelsString(mChannels), mIs51Rear?"(rear)":"");
}

void DeviceNode::parseChannelCount(const spa_pod *value, bool force_update) noexcept
{
    /* As a fallback with just a channel count, just assume mono or stereo. */
    uint32_t choiceCount{}, choiceType{};
    value = spa_pod_get_values(value, &choiceCount, &choiceType);

    if(choiceType != SPA_CHOICE_None || choiceCount != 1)
    {
        ERR("  Unexpected positions choice: type=%u, count=%u\n", choiceType, choiceCount);
        return;
    }

    const auto chancount = get_value<SPA_TYPE_Int>(value);
    if(!chancount) return;

    if(mChannels == InvalidChannelConfig || force_update)
    {
        mIs51Rear = false;

        if(*chancount >= 2)
            mChannels = DevFmtStereo;
        else if(*chancount >= 1)
            mChannels = DevFmtMono;
    }
    TRACE("  %d channel%s for %s\n", *chancount, (*chancount==1)?"":"s",
        DevFmtChannelsString(mChannels));
}


[[nodiscard]] constexpr auto GetMonitorPrefix() noexcept { return "Monitor of "sv; }
[[nodiscard]] constexpr auto GetMonitorSuffix() noexcept { return ".monitor"sv; }
[[nodiscard]] constexpr auto GetAudioSinkClassName() noexcept { return "Audio/Sink"sv; }
[[nodiscard]] constexpr auto GetAudioSourceClassName() noexcept { return "Audio/Source"sv; }
[[nodiscard]] constexpr auto GetAudioDuplexClassName() noexcept { return "Audio/Duplex"sv; }
[[nodiscard]] constexpr auto GetAudioSourceVirtualClassName() noexcept
{ return "Audio/Source/Virtual"sv; }


void NodeProxy::infoCallback(void*, const pw_node_info *info) noexcept
{
    /* We only care about property changes here (media class, name/desc).
     * Format changes will automatically invoke the param callback.
     *
     * TODO: Can the media class or name/desc change without being removed and
     * readded?
     */
    if((info->change_mask&PW_NODE_CHANGE_MASK_PROPS))
    {
        /* Can this actually change? */
        const char *media_class{spa_dict_lookup(info->props, PW_KEY_MEDIA_CLASS)};
        if(!media_class) UNLIKELY return;
        const std::string_view className{media_class};

        NodeType ntype{};
        if(al::case_compare(className, GetAudioSinkClassName()) == 0)
            ntype = NodeType::Sink;
        else if(al::case_compare(className, GetAudioSourceClassName()) == 0
            || al::case_compare(className, GetAudioSourceVirtualClassName()) == 0)
            ntype = NodeType::Source;
        else if(al::case_compare(className, GetAudioDuplexClassName()) == 0)
            ntype = NodeType::Duplex;
        else
        {
            TRACE("Dropping device node %u which became type \"%s\"\n", info->id, media_class);
            DeviceNode::Remove(info->id);
            return;
        }

        const char *devName{spa_dict_lookup(info->props, PW_KEY_NODE_NAME)};
        const char *nodeName{spa_dict_lookup(info->props, PW_KEY_NODE_DESCRIPTION)};
        if(!nodeName || !*nodeName) nodeName = spa_dict_lookup(info->props, PW_KEY_NODE_NICK);
        if(!nodeName || !*nodeName) nodeName = devName;

        uint64_t serial_id{info->id};
#ifdef PW_KEY_OBJECT_SERIAL
        if(const char *serial_str{spa_dict_lookup(info->props, PW_KEY_OBJECT_SERIAL)})
        {
            errno = 0;
            char *serial_end{};
            serial_id = std::strtoull(serial_str, &serial_end, 0);
            if(*serial_end != '\0' || errno == ERANGE)
            {
                ERR("Unexpected object serial: %s\n", serial_str);
                serial_id = info->id;
            }
        }
#endif

        std::string name;
        if(nodeName && *nodeName) name = nodeName;
        else name = "PipeWire node #"+std::to_string(info->id);

        const char *form_factor{spa_dict_lookup(info->props, PW_KEY_DEVICE_FORM_FACTOR)};
        TRACE("Got %s device \"%s\"%s%s%s\n", AsString(ntype), devName ? devName : "(nil)",
            form_factor?" (":"", form_factor?form_factor:"", form_factor?")":"");
        TRACE("  \"%s\" = ID %" PRIu64 "\n", name.c_str(), serial_id);

        DeviceNode &node = DeviceNode::Add(info->id);
        node.mSerial = serial_id;
        /* This method is called both to notify about a new sink/source node,
         * and update properties for the node. It's unclear what properties can
         * change for an existing node without being removed first, so err on
         * the side of caution: send a DeviceRemoved event if it had a name
         * that's being changed, and send a DeviceAdded event when the name
         * differs or it didn't have one.
         *
         * The DeviceRemoved event needs to be called before the potentially
         * new NodeType is set, so the removal event is called for the previous
         * device type, while the DeviceAdded event needs to be called after.
         *
         * This is overkill if the node type, name, and devname can't change.
         */
        bool notifyAdd{false};
        if(node.mName != name)
        {
            if(gEventHandler.initIsDone(std::memory_order_relaxed))
            {
                if(!node.mName.empty())
                {
                    const std::string msg{"Device removed: "+node.mName};
                    node.callEvent(alc::EventType::DeviceRemoved, msg);
                }
                notifyAdd = true;
            }
            node.mName = std::move(name);
        }
        node.mDevName = devName ? devName : "";
        node.mType = ntype;
        node.mIsHeadphones = form_factor && (al::case_compare(form_factor, "headphones"sv) == 0
            || al::case_compare(form_factor, "headset"sv) == 0);
        if(notifyAdd)
        {
            const std::string msg{"Device added: "+node.mName};
            node.callEvent(alc::EventType::DeviceAdded, msg);
        }
    }
}

void NodeProxy::paramCallback(int, uint32_t id, uint32_t, uint32_t, const spa_pod *param) const noexcept
{
    if(id == SPA_PARAM_EnumFormat || id == SPA_PARAM_Format)
    {
        DeviceNode *node{DeviceNode::Find(mId)};
        if(!node) UNLIKELY return;

        TRACE("Device ID %" PRIu64 " %s format%s:\n", node->mSerial,
            (id == SPA_PARAM_EnumFormat) ? "available" : "current",
            (id == SPA_PARAM_EnumFormat) ? "s" : "");

        const bool force_update{id == SPA_PARAM_Format};
        if(const spa_pod_prop *prop{spa_pod_find_prop(param, nullptr, SPA_FORMAT_AUDIO_rate)})
            node->parseSampleRate(&prop->value, force_update);

        if(const spa_pod_prop *prop{spa_pod_find_prop(param, nullptr, SPA_FORMAT_AUDIO_position)})
            node->parsePositions(&prop->value, force_update);
        else
        {
            prop = spa_pod_find_prop(param, nullptr, SPA_FORMAT_AUDIO_channels);
            if(prop) node->parseChannelCount(&prop->value, force_update);
        }
    }
}


auto MetadataProxy::propertyCallback(void*, uint32_t id, const char *key, const char *type,
    const char *value) noexcept -> int
{
    if(id != PW_ID_CORE)
        return 0;

    bool isCapture{};
    if("default.audio.sink"sv == key)
        isCapture = false;
    else if("default.audio.source"sv == key)
        isCapture = true;
    else
        return 0;

    if(!type)
    {
        TRACE("Default %s device cleared\n", isCapture ? "capture" : "playback");
        if(!isCapture) DefaultSinkDevice.clear();
        else DefaultSourceDevice.clear();
        return 0;
    }
    if("Spa:String:JSON"sv != type)
    {
        ERR("Unexpected %s property type: %s\n", key, type);
        return 0;
    }

    std::array<spa_json,2> it{};
    spa_json_init(it.data(), value, strlen(value));
    if(spa_json_enter_object(&std::get<0>(it), &std::get<1>(it)) <= 0)
        return 0;

    auto get_json_string = [](spa_json *iter)
    {
        std::optional<std::string> str;

        const char *val{};
        int len{spa_json_next(iter, &val)};
        if(len <= 0) return str;

        str.emplace(static_cast<uint>(len), '\0');
        if(spa_json_parse_string(val, len, str->data()) <= 0)
            str.reset();
        else while(!str->empty() && str->back() == '\0')
            str->pop_back();
        return str;
    };
    while(auto propKey = get_json_string(&std::get<1>(it)))
    {
        if("name"sv == *propKey)
        {
            auto propValue = get_json_string(&std::get<1>(it));
            if(!propValue) break;

            TRACE("Got default %s device \"%s\"\n", isCapture ? "capture" : "playback",
                propValue->c_str());
            if(!isCapture && DefaultSinkDevice != *propValue)
            {
                if(gEventHandler.mInitDone.load(std::memory_order_relaxed))
                {
                    auto entry = DeviceNode::FindByDevName(*propValue);
                    const std::string message{"Default playback device changed: "+
                        (entry ? entry->mName : std::string{})};
                    alc::Event(alc::EventType::DefaultDeviceChanged, alc::DeviceType::Playback,
                        message);
                }
                DefaultSinkDevice = std::move(*propValue);
            }
            else if(isCapture && DefaultSourceDevice != *propValue)
            {
                if(gEventHandler.mInitDone.load(std::memory_order_relaxed))
                {
                    auto entry = DeviceNode::FindByDevName(*propValue);
                    const std::string message{"Default capture device changed: "+
                        (entry ? entry->mName : std::string{})};
                    alc::Event(alc::EventType::DefaultDeviceChanged, alc::DeviceType::Capture,
                        message);
                }
                DefaultSourceDevice = std::move(*propValue);
            }
        }
        else
        {
            const char *v{};
            if(spa_json_next(&std::get<1>(it), &v) <= 0)
                break;
        }
    }
    return 0;
}


bool EventManager::init()
{
    mLoop = ThreadMainloop::Create("PWEventThread");
    if(!mLoop)
    {
        ERR("Failed to create PipeWire event thread loop (errno: %d)\n", errno);
        return false;
    }

    mContext = mLoop.newContext();
    if(!mContext)
    {
        ERR("Failed to create PipeWire event context (errno: %d)\n", errno);
        return false;
    }

    mCore = PwCorePtr{pw_context_connect(mContext.get(), nullptr, 0)};
    if(!mCore)
    {
        ERR("Failed to connect PipeWire event context (errno: %d)\n", errno);
        return false;
    }

    mRegistry = PwRegistryPtr{pw_core_get_registry(mCore.get(), PW_VERSION_REGISTRY, 0)};
    if(!mRegistry)
    {
        ERR("Failed to get PipeWire event registry (errno: %d)\n", errno);
        return false;
    }

    static constexpr pw_core_events coreEvents{CreateCoreEvents()};
    static constexpr pw_registry_events registryEvents{CreateRegistryEvents()};

    ppw_core_add_listener(mCore.get(), &mCoreListener, &coreEvents, this);
    ppw_registry_add_listener(mRegistry.get(), &mRegistryListener, &registryEvents, this);

    /* Set an initial sequence ID for initialization, to trigger after the
     * registry is first populated.
     */
    mInitSeq = ppw_core_sync(mCore.get(), PW_ID_CORE, 0);

    if(int res{mLoop.start()})
    {
        ERR("Failed to start PipeWire event thread loop (res: %d)\n", res);
        return false;
    }

    return true;
}

void EventManager::kill()
{
    if(mLoop) mLoop.stop();

    mDefaultMetadata.reset();
    mNodeList.clear();

    mRegistry = nullptr;
    mCore = nullptr;
    mContext = nullptr;
    mLoop = nullptr;
}

void EventManager::addCallback(uint32_t id, uint32_t, const char *type, uint32_t version,
    const spa_dict *props) noexcept
{
    /* We're only interested in interface nodes. */
    if(std::strcmp(type, PW_TYPE_INTERFACE_Node) == 0)
    {
        const char *media_class{spa_dict_lookup(props, PW_KEY_MEDIA_CLASS)};
        if(!media_class) return;
        const std::string_view className{media_class};

        /* Specifically, audio sinks and sources (and duplexes). */
        const bool isGood{al::case_compare(className, GetAudioSinkClassName()) == 0
            || al::case_compare(className, GetAudioSourceClassName()) == 0
            || al::case_compare(className, GetAudioSourceVirtualClassName()) == 0
            || al::case_compare(className, GetAudioDuplexClassName()) == 0};
        if(!isGood)
        {
            if(!al::contains(className, "/Video"sv) && !al::starts_with(className, "Stream/"sv))
                TRACE("Ignoring node class %s\n", media_class);
            return;
        }

        /* Create the proxy object. */
        auto node = PwNodePtr{static_cast<pw_node*>(pw_registry_bind(mRegistry.get(), id, type,
            version, 0))};
        if(!node)
        {
            ERR("Failed to create node proxy object (errno: %d)\n", errno);
            return;
        }

        /* Initialize the NodeProxy to hold the node object, add it to the
         * active node list, and update the sync point.
         */
        mNodeList.emplace_back(std::make_unique<NodeProxy>(id, std::move(node)));
        syncInit();

        /* Signal any waiters that we have found a source or sink for audio
         * support.
         */
        if(!mHasAudio.exchange(true, std::memory_order_acq_rel))
            mLoop.signal(false);
    }
    else if(std::strcmp(type, PW_TYPE_INTERFACE_Metadata) == 0)
    {
        const char *data_class{spa_dict_lookup(props, PW_KEY_METADATA_NAME)};
        if(!data_class) return;

        if("default"sv != data_class)
        {
            TRACE("Ignoring metadata \"%s\"\n", data_class);
            return;
        }

        if(mDefaultMetadata)
        {
            ERR("Duplicate default metadata\n");
            return;
        }

        auto mdata = PwMetadataPtr{static_cast<pw_metadata*>(pw_registry_bind(mRegistry.get(), id,
            type, version, 0))};
        if(!mdata)
        {
            ERR("Failed to create metadata proxy object (errno: %d)\n", errno);
            return;
        }

        mDefaultMetadata.emplace(id, std::move(mdata));
        syncInit();
    }
}

void EventManager::removeCallback(uint32_t id) noexcept
{
    DeviceNode::Remove(id);

    auto clear_node = [id](std::unique_ptr<NodeProxy> &node) noexcept
    { return node->mId == id; };
    auto node_end = std::remove_if(mNodeList.begin(), mNodeList.end(), clear_node);
    mNodeList.erase(node_end, mNodeList.end());

    if(mDefaultMetadata && mDefaultMetadata->mId == id)
        mDefaultMetadata.reset();
}

void EventManager::coreCallback(uint32_t id, int seq) noexcept
{
    if(id == PW_ID_CORE && seq == mInitSeq)
    {
        /* Initialization done. Remove this callback and signal anyone that may
         * be waiting.
         */
        spa_hook_remove(&mCoreListener);

        mInitDone.store(true);
        mLoop.signal(false);
    }
}


enum use_f32p_e : bool { UseDevType=false, ForceF32Planar=true };
spa_audio_info_raw make_spa_info(DeviceBase *device, bool is51rear, use_f32p_e use_f32p)
{
    spa_audio_info_raw info{};
    if(use_f32p)
    {
        device->FmtType = DevFmtFloat;
        info.format = SPA_AUDIO_FORMAT_F32P;
    }
    else switch(device->FmtType)
    {
    case DevFmtByte: info.format = SPA_AUDIO_FORMAT_S8; break;
    case DevFmtUByte: info.format = SPA_AUDIO_FORMAT_U8; break;
    case DevFmtShort: info.format = SPA_AUDIO_FORMAT_S16; break;
    case DevFmtUShort: info.format = SPA_AUDIO_FORMAT_U16; break;
    case DevFmtInt: info.format = SPA_AUDIO_FORMAT_S32; break;
    case DevFmtUInt: info.format = SPA_AUDIO_FORMAT_U32; break;
    case DevFmtFloat: info.format = SPA_AUDIO_FORMAT_F32; break;
    }

    info.rate = device->Frequency;

    al::span<const spa_audio_channel> map{};
    switch(device->FmtChans)
    {
    case DevFmtMono: map = MonoMap; break;
    case DevFmtStereo: map = StereoMap; break;
    case DevFmtQuad: map = QuadMap; break;
    case DevFmtX51:
        if(is51rear) map = X51RearMap;
        else map = X51Map;
        break;
    case DevFmtX61: map = X61Map; break;
    case DevFmtX71: map = X71Map; break;
    case DevFmtX714: map = X714Map; break;
    case DevFmtX3D71: map = X71Map; break;
    case DevFmtX7144:
    case DevFmtAmbi3D:
        info.flags |= SPA_AUDIO_FLAG_UNPOSITIONED;
        info.channels = device->channelsFromFmt();
        break;
    }
    if(!map.empty())
    {
        info.channels = static_cast<uint32_t>(map.size());
        std::copy(map.begin(), map.end(), std::begin(info.position));
    }

    return info;
}

class PipeWirePlayback final : public BackendBase {
    void stateChangedCallback(pw_stream_state old, pw_stream_state state, const char *error) noexcept;
    void ioChangedCallback(uint32_t id, void *area, uint32_t size) noexcept;
    void outputCallback() noexcept;

    void open(std::string_view name) override;
    bool reset() override;
    void start() override;
    void stop() override;
    ClockLatency getClockLatency() override;

    uint64_t mTargetId{PwIdAny};
    nanoseconds mTimeBase{0};
    ThreadMainloop mLoop;
    PwContextPtr mContext;
    PwCorePtr mCore;
    PwStreamPtr mStream;
    spa_hook mStreamListener{};
    spa_io_rate_match *mRateMatch{};
    std::vector<void*> mChannelPtrs;

    static constexpr pw_stream_events CreateEvents()
    {
        pw_stream_events ret{};
        ret.version = PW_VERSION_STREAM_EVENTS;
        ret.state_changed = [](void *data, pw_stream_state old, pw_stream_state state, const char *error) noexcept
        { static_cast<PipeWirePlayback*>(data)->stateChangedCallback(old, state, error); };
        ret.io_changed = [](void *data, uint32_t id, void *area, uint32_t size) noexcept
        { static_cast<PipeWirePlayback*>(data)->ioChangedCallback(id, area, size); };
        ret.process = [](void *data) noexcept
        { static_cast<PipeWirePlayback*>(data)->outputCallback(); };
        return ret;
    }

public:
    PipeWirePlayback(DeviceBase *device) noexcept : BackendBase{device} { }
    ~PipeWirePlayback() final
    {
        /* Stop the mainloop so the stream can be properly destroyed. */
        if(mLoop) mLoop.stop();
    }
};


void PipeWirePlayback::stateChangedCallback(pw_stream_state, pw_stream_state, const char*) noexcept
{ mLoop.signal(false); }

void PipeWirePlayback::ioChangedCallback(uint32_t id, void *area, uint32_t size) noexcept
{
    switch(id)
    {
    case SPA_IO_RateMatch:
        if(size >= sizeof(spa_io_rate_match))
            mRateMatch = static_cast<spa_io_rate_match*>(area);
        else
            mRateMatch = nullptr;
        break;
    }
}

void PipeWirePlayback::outputCallback() noexcept
{
    pw_buffer *pw_buf{pw_stream_dequeue_buffer(mStream.get())};
    if(!pw_buf) UNLIKELY return;

    const al::span<spa_data> datas{pw_buf->buffer->datas,
        std::min(mChannelPtrs.size(), size_t{pw_buf->buffer->n_datas})};
#if PW_CHECK_VERSION(0,3,49)
    /* In 0.3.49, pw_buffer::requested specifies the number of samples needed
     * by the resampler/graph for this audio update.
     */
    uint length{static_cast<uint>(pw_buf->requested)};
#else
    /* In 0.3.48 and earlier, spa_io_rate_match::size apparently has the number
     * of samples per update.
     */
    uint length{mRateMatch ? mRateMatch->size : 0u};
#endif
    /* If no length is specified, use the device's update size as a fallback. */
    if(!length) UNLIKELY length = mDevice->UpdateSize;

    /* For planar formats, each datas[] seems to contain one channel, so store
     * the pointers in an array. Limit the render length in case the available
     * buffer length in any one channel is smaller than we wanted (shouldn't
     * be, but just in case).
     */
    auto chanptr_end = mChannelPtrs.begin();
    for(const auto &data : datas)
    {
        length = std::min(length, data.maxsize/uint{sizeof(float)});
        *chanptr_end = data.data;
        ++chanptr_end;

        data.chunk->offset = 0;
        data.chunk->stride = sizeof(float);
        data.chunk->size   = length * sizeof(float);
    }

    mDevice->renderSamples(mChannelPtrs, length);

    pw_buf->size = length;
    pw_stream_queue_buffer(mStream.get(), pw_buf);
}


void PipeWirePlayback::open(std::string_view name)
{
    static std::atomic<uint> OpenCount{0};

    uint64_t targetid{PwIdAny};
    std::string devname{};
    gEventHandler.waitForInit();
    if(name.empty())
    {
        EventWatcherLockGuard evtlock{gEventHandler};
        auto&& devlist = DeviceNode::GetList();

        auto match = devlist.cend();
        if(!DefaultSinkDevice.empty())
        {
            auto match_default = [](const DeviceNode &n) -> bool
            { return n.mDevName == DefaultSinkDevice; };
            match = std::find_if(devlist.cbegin(), devlist.cend(), match_default);
        }
        if(match == devlist.cend())
        {
            auto match_playback = [](const DeviceNode &n) -> bool
            { return n.mType != NodeType::Source; };
            match = std::find_if(devlist.cbegin(), devlist.cend(), match_playback);
            if(match == devlist.cend())
                throw al::backend_exception{al::backend_error::NoDevice,
                    "No PipeWire playback device found"};
        }

        targetid = match->mSerial;
        devname = match->mName;
    }
    else
    {
        EventWatcherLockGuard evtlock{gEventHandler};
        auto&& devlist = DeviceNode::GetList();

        auto match_name = [name](const DeviceNode &n) -> bool
        { return n.mType != NodeType::Source && (n.mName == name || n.mDevName == name); };
        auto match = std::find_if(devlist.cbegin(), devlist.cend(), match_name);
        if(match == devlist.cend())
            throw al::backend_exception{al::backend_error::NoDevice,
                "Device name \"%.*s\" not found", al::sizei(name), name.data()};

        targetid = match->mSerial;
        devname = match->mName;
    }

    if(!mLoop)
    {
        const uint count{OpenCount.fetch_add(1, std::memory_order_relaxed)};
        const std::string thread_name{"ALSoftP" + std::to_string(count)};
        mLoop = ThreadMainloop::Create(thread_name.c_str());
        if(!mLoop)
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to create PipeWire mainloop (errno: %d)", errno};
        if(int res{mLoop.start()})
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to start PipeWire mainloop (res: %d)", res};
    }
    MainloopUniqueLock mlock{mLoop};
    if(!mContext)
    {
        pw_properties *cprops{pw_properties_new(PW_KEY_CONFIG_NAME, "client-rt.conf", nullptr)};
        mContext = mLoop.newContext(cprops);
        if(!mContext)
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to create PipeWire event context (errno: %d)\n", errno};
    }
    if(!mCore)
    {
        mCore = PwCorePtr{pw_context_connect(mContext.get(), nullptr, 0)};
        if(!mCore)
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to connect PipeWire event context (errno: %d)\n", errno};
    }
    mlock.unlock();

    /* TODO: Ensure the target ID is still valid/usable and accepts streams. */

    mTargetId = targetid;
    if(!devname.empty())
        mDeviceName = std::move(devname);
    else
        mDeviceName = "PipeWire Output"sv;
}

bool PipeWirePlayback::reset()
{
    if(mStream)
    {
        MainloopLockGuard looplock{mLoop};
        mStream = nullptr;
    }
    mStreamListener = {};
    mRateMatch = nullptr;
    mTimeBase = mDevice->getClockTime();

    /* If connecting to a specific device, update various device parameters to
     * match its format.
     */
    bool is51rear{false};
    mDevice->Flags.reset(DirectEar);
    if(mTargetId != PwIdAny)
    {
        EventWatcherLockGuard evtlock{gEventHandler};
        auto&& devlist = DeviceNode::GetList();

        auto match_id = [targetid=mTargetId](const DeviceNode &n) -> bool
        { return targetid == n.mSerial; };
        auto match = std::find_if(devlist.cbegin(), devlist.cend(), match_id);
        if(match != devlist.cend())
        {
            if(!mDevice->Flags.test(FrequencyRequest) && match->mSampleRate > 0)
            {
                /* Scale the update size if the sample rate changes. */
                const double scale{static_cast<double>(match->mSampleRate) / mDevice->Frequency};
                const double updatesize{std::round(mDevice->UpdateSize * scale)};
                const double buffersize{std::round(mDevice->BufferSize * scale)};

                mDevice->Frequency = match->mSampleRate;
                mDevice->UpdateSize = static_cast<uint>(std::clamp(updatesize, 64.0, 8192.0));
                mDevice->BufferSize = static_cast<uint>(std::max(buffersize, 128.0));
            }
            if(!mDevice->Flags.test(ChannelsRequest) && match->mChannels != InvalidChannelConfig)
                mDevice->FmtChans = match->mChannels;
            if(match->mChannels == DevFmtStereo && match->mIsHeadphones)
                mDevice->Flags.set(DirectEar);
            is51rear = match->mIs51Rear;
        }
    }
    /* Force planar 32-bit float output for playback. This is what PipeWire
     * handles internally, and it's easier for us too.
     */
    auto info = spa_audio_info_raw{make_spa_info(mDevice, is51rear, ForceF32Planar)};

    auto b = PodDynamicBuilder{};
    auto params = as_const_ptr(spa_format_audio_raw_build(b.get(), SPA_PARAM_EnumFormat, &info));
    if(!params)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to set PipeWire audio format parameters"};

    /* TODO: Which properties are actually needed here? Any others that could
     * be useful?
     */
    auto&& binary = GetProcBinary();
    const char *appname{!binary.fname.empty() ? binary.fname.c_str() : "OpenAL Soft"};
    pw_properties *props{pw_properties_new(PW_KEY_NODE_NAME, appname,
        PW_KEY_NODE_DESCRIPTION, appname,
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Playback",
        PW_KEY_MEDIA_ROLE, "Game",
        PW_KEY_NODE_ALWAYS_PROCESS, "true",
        nullptr)};
    if(!props)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to create PipeWire stream properties (errno: %d)", errno};

    pw_properties_setf(props, PW_KEY_NODE_LATENCY, "%u/%u", mDevice->UpdateSize,
        mDevice->Frequency);
    pw_properties_setf(props, PW_KEY_NODE_RATE, "1/%u", mDevice->Frequency);
#ifdef PW_KEY_TARGET_OBJECT
    pw_properties_setf(props, PW_KEY_TARGET_OBJECT, "%" PRIu64, mTargetId);
#else
    pw_properties_setf(props, PW_KEY_NODE_TARGET, "%" PRIu64, mTargetId);
#endif

    MainloopUniqueLock plock{mLoop};
    /* The stream takes overship of 'props', even in the case of failure. */
    mStream = PwStreamPtr{pw_stream_new(mCore.get(), "Playback Stream", props)};
    if(!mStream)
        throw al::backend_exception{al::backend_error::NoDevice,
            "Failed to create PipeWire stream (errno: %d)", errno};
    static constexpr pw_stream_events streamEvents{CreateEvents()};
    pw_stream_add_listener(mStream.get(), &mStreamListener, &streamEvents, this);

    pw_stream_flags flags{PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_INACTIVE
        | PW_STREAM_FLAG_MAP_BUFFERS};
    if(GetConfigValueBool(mDevice->mDeviceName, "pipewire", "rt-mix", false))
        flags |= PW_STREAM_FLAG_RT_PROCESS;
    if(int res{pw_stream_connect(mStream.get(), PW_DIRECTION_OUTPUT, PwIdAny, flags, &params, 1)})
        throw al::backend_exception{al::backend_error::DeviceError,
            "Error connecting PipeWire stream (res: %d)", res};

    /* Wait for the stream to become paused (ready to start streaming). */
    plock.wait([stream=mStream.get()]()
    {
        const char *error{};
        pw_stream_state state{pw_stream_get_state(stream, &error)};
        if(state == PW_STREAM_STATE_ERROR)
            throw al::backend_exception{al::backend_error::DeviceError,
                "Error connecting PipeWire stream: \"%s\"", error};
        return state == PW_STREAM_STATE_PAUSED;
    });

    /* TODO: Update mDevice->UpdateSize with the stream's quantum, and
     * mDevice->BufferSize with the total known buffering delay from the head
     * of this playback stream to the tail of the device output.
     *
     * This info is apparently not available until after the stream starts.
     */
    plock.unlock();

    mChannelPtrs.resize(mDevice->channelsFromFmt());

    setDefaultWFXChannelOrder();

    return true;
}

void PipeWirePlayback::start()
{
    MainloopUniqueLock plock{mLoop};
    if(int res{pw_stream_set_active(mStream.get(), true)})
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to start PipeWire stream (res: %d)", res};

    /* Wait for the stream to start playing (would be nice to not, but we need
     * the actual update size which is only available after starting).
     */
    plock.wait([stream=mStream.get()]()
    {
        const char *error{};
        pw_stream_state state{pw_stream_get_state(stream, &error)};
        if(state == PW_STREAM_STATE_ERROR)
            throw al::backend_exception{al::backend_error::DeviceError,
                "PipeWire stream error: %s", error ? error : "(unknown)"};
        return state == PW_STREAM_STATE_STREAMING;
    });

    /* HACK: Try to work out the update size and total buffering size. There's
     * no actual query for this, so we have to work it out from the stream time
     * info, and assume it stays accurate with future updates. The stream time
     * info may also not be available right away, so we have to wait until it
     * is (up to about 2 seconds).
     */
    int wait_count{100};
    do {
        pw_time ptime{};
        if(int res{pw_stream_get_time_n(mStream.get(), &ptime, sizeof(ptime))})
        {
            ERR("Failed to get PipeWire stream time (res: %d)\n", res);
            break;
        }

        /* The rate match size is the update size for each buffer. */
        const uint updatesize{mRateMatch ? mRateMatch->size : 0u};
#if PW_CHECK_VERSION(0,3,50)
        /* Assume ptime.avail_buffers+ptime.queued_buffers is the target buffer
         * queue size.
         */
        if(ptime.rate.denom > 0 && (ptime.avail_buffers || ptime.queued_buffers) && updatesize > 0)
        {
            const uint totalbuffers{ptime.avail_buffers + ptime.queued_buffers};

            /* Ensure the delay is in sample frames. */
            const uint64_t delay{static_cast<uint64_t>(ptime.delay) * mDevice->Frequency *
                ptime.rate.num / ptime.rate.denom};

            mDevice->UpdateSize = updatesize;
            mDevice->BufferSize = static_cast<uint>(ptime.buffered + delay +
                uint64_t{totalbuffers}*updatesize);
            break;
        }
#else
        /* Prior to 0.3.50, we can only measure the delay with the update size,
         * assuming one buffer and no resample buffering.
         */
        if(ptime.rate.denom > 0 && updatesize > 0)
        {
            /* Ensure the delay is in sample frames. */
            const uint64_t delay{static_cast<uint64_t>(ptime.delay) * mDevice->Frequency *
                ptime.rate.num / ptime.rate.denom};

            mDevice->UpdateSize = updatesize;
            mDevice->BufferSize = static_cast<uint>(delay + updatesize);
            break;
        }
#endif
        if(!--wait_count)
        {
            ERR("Timeout getting PipeWire stream buffering info\n");
            break;
        }

        plock.unlock();
        std::this_thread::sleep_for(milliseconds{20});
        plock.lock();
    } while(pw_stream_get_state(mStream.get(), nullptr) == PW_STREAM_STATE_STREAMING);
}

void PipeWirePlayback::stop()
{
    MainloopUniqueLock plock{mLoop};
    if(int res{pw_stream_set_active(mStream.get(), false)})
        ERR("Failed to stop PipeWire stream (res: %d)\n", res);

    /* Wait for the stream to stop playing. */
    plock.wait([stream=mStream.get()]()
    { return pw_stream_get_state(stream, nullptr) != PW_STREAM_STATE_STREAMING; });
}

ClockLatency PipeWirePlayback::getClockLatency()
{
    /* Given a real-time low-latency output, this is rather complicated to get
     * accurate timing. So, here we go.
     */

    /* First, get the stream time info (tick delay, ticks played, and the
     * CLOCK_MONOTONIC time closest to when that last tick was played).
     */
    pw_time ptime{};
    if(mStream)
    {
        MainloopLockGuard looplock{mLoop};
        if(int res{pw_stream_get_time_n(mStream.get(), &ptime, sizeof(ptime))})
            ERR("Failed to get PipeWire stream time (res: %d)\n", res);
    }

    /* Now get the mixer time and the CLOCK_MONOTONIC time atomically (i.e. the
     * monotonic clock closest to 'now', and the last mixer time at 'now').
     */
    nanoseconds mixtime{};
    timespec tspec{};
    uint refcount;
    do {
        refcount = mDevice->waitForMix();
        mixtime = mDevice->getClockTime();
        clock_gettime(CLOCK_MONOTONIC, &tspec);
        std::atomic_thread_fence(std::memory_order_acquire);
    } while(refcount != mDevice->mMixCount.load(std::memory_order_relaxed));

    /* Convert the monotonic clock, stream ticks, and stream delay to
     * nanoseconds.
     */
    nanoseconds monoclock{seconds{tspec.tv_sec} + nanoseconds{tspec.tv_nsec}};
    nanoseconds curtic{}, delay{};
    if(ptime.rate.denom < 1) UNLIKELY
    {
        /* If there's no stream rate, the stream hasn't had a chance to get
         * going and return time info yet. Just use dummy values.
         */
        ptime.now = monoclock.count();
        curtic = mixtime;
        delay = nanoseconds{seconds{mDevice->BufferSize}} / mDevice->Frequency;
    }
    else
    {
        /* The stream gets recreated with each reset, so include the time that
         * had already passed with previous streams.
         */
        curtic = mTimeBase;
        /* More safely scale the ticks to avoid overflowing the pre-division
         * temporary as it gets larger.
         */
        curtic += seconds{ptime.ticks / ptime.rate.denom} * ptime.rate.num;
        curtic += nanoseconds{seconds{ptime.ticks%ptime.rate.denom} * ptime.rate.num} /
            ptime.rate.denom;

        /* The delay should be small enough to not worry about overflow. */
        delay = nanoseconds{seconds{ptime.delay} * ptime.rate.num} / ptime.rate.denom;
    }

    /* If the mixer time is ahead of the stream time, there's that much more
     * delay relative to the stream delay.
     */
    if(mixtime > curtic)
        delay += mixtime - curtic;
    /* Reduce the delay according to how much time has passed since the known
     * stream time. This isn't 100% accurate since the system monotonic clock
     * doesn't tick at the exact same rate as the audio device, but it should
     * be good enough with ptime.now being constantly updated every few
     * milliseconds with ptime.ticks.
     */
    delay -= monoclock - nanoseconds{ptime.now};

    /* Return the mixer time and delay. Clamp the delay to no less than 0,
     * in case timer drift got that severe.
     */
    ClockLatency ret{};
    ret.ClockTime = mixtime;
    ret.Latency = std::max(delay, nanoseconds{});

    return ret;
}


class PipeWireCapture final : public BackendBase {
    void stateChangedCallback(pw_stream_state old, pw_stream_state state, const char *error) noexcept;
    void inputCallback() noexcept;

    void open(std::string_view name) override;
    void start() override;
    void stop() override;
    void captureSamples(std::byte *buffer, uint samples) override;
    uint availableSamples() override;

    uint64_t mTargetId{PwIdAny};
    ThreadMainloop mLoop;
    PwContextPtr mContext;
    PwCorePtr mCore;
    PwStreamPtr mStream;
    spa_hook mStreamListener{};

    RingBufferPtr mRing{};

    static constexpr pw_stream_events CreateEvents()
    {
        pw_stream_events ret{};
        ret.version = PW_VERSION_STREAM_EVENTS;
        ret.state_changed = [](void *data, pw_stream_state old, pw_stream_state state, const char *error) noexcept
        { static_cast<PipeWireCapture*>(data)->stateChangedCallback(old, state, error); };
        ret.process = [](void *data) noexcept
        { static_cast<PipeWireCapture*>(data)->inputCallback(); };
        return ret;
    }

public:
    PipeWireCapture(DeviceBase *device) noexcept : BackendBase{device} { }
    ~PipeWireCapture() final { if(mLoop) mLoop.stop(); }
};


void PipeWireCapture::stateChangedCallback(pw_stream_state, pw_stream_state, const char*) noexcept
{ mLoop.signal(false); }

void PipeWireCapture::inputCallback() noexcept
{
    pw_buffer *pw_buf{pw_stream_dequeue_buffer(mStream.get())};
    if(!pw_buf) UNLIKELY return;

    spa_data *bufdata{pw_buf->buffer->datas};
    const uint offset{bufdata->chunk->offset % bufdata->maxsize};
    const auto input = al::span{static_cast<const char*>(bufdata->data), bufdata->maxsize}
        .subspan(offset, std::min(bufdata->chunk->size, bufdata->maxsize - offset));

    std::ignore = mRing->write(input.data(), input.size() / mRing->getElemSize());

    pw_stream_queue_buffer(mStream.get(), pw_buf);
}


void PipeWireCapture::open(std::string_view name)
{
    static std::atomic<uint> OpenCount{0};

    uint64_t targetid{PwIdAny};
    std::string devname{};
    gEventHandler.waitForInit();
    if(name.empty())
    {
        EventWatcherLockGuard evtlock{gEventHandler};
        auto&& devlist = DeviceNode::GetList();

        auto match = devlist.cend();
        if(!DefaultSourceDevice.empty())
        {
            auto match_default = [](const DeviceNode &n) -> bool
            { return n.mDevName == DefaultSourceDevice; };
            match = std::find_if(devlist.cbegin(), devlist.cend(), match_default);
        }
        if(match == devlist.cend())
        {
            auto match_capture = [](const DeviceNode &n) -> bool
            { return n.mType != NodeType::Sink; };
            match = std::find_if(devlist.cbegin(), devlist.cend(), match_capture);
        }
        if(match == devlist.cend())
        {
            match = devlist.cbegin();
            if(match == devlist.cend())
                throw al::backend_exception{al::backend_error::NoDevice,
                    "No PipeWire capture device found"};
        }

        targetid = match->mSerial;
        if(match->mType != NodeType::Sink) devname = match->mName;
        else devname = std::string{GetMonitorPrefix()}+match->mName;
    }
    else
    {
        EventWatcherLockGuard evtlock{gEventHandler};
        auto&& devlist = DeviceNode::GetList();
        const std::string_view prefix{GetMonitorPrefix()};
        const std::string_view suffix{GetMonitorSuffix()};

        auto match_name = [name](const DeviceNode &n) -> bool
        { return n.mType != NodeType::Sink && n.mName == name; };
        auto match = std::find_if(devlist.cbegin(), devlist.cend(), match_name);
        if(match == devlist.cend() && al::starts_with(name, prefix))
        {
            const std::string_view sinkname{name.substr(prefix.length())};
            auto match_sinkname = [sinkname](const DeviceNode &n) -> bool
            { return n.mType == NodeType::Sink && n.mName == sinkname; };
            match = std::find_if(devlist.cbegin(), devlist.cend(), match_sinkname);
        }
        else if(match == devlist.cend() && al::ends_with(name, suffix))
        {
            const std::string_view sinkname{name.substr(0, name.size()-suffix.size())};
            auto match_sinkname = [sinkname](const DeviceNode &n) -> bool
            { return n.mType == NodeType::Sink && n.mDevName == sinkname; };
            match = std::find_if(devlist.cbegin(), devlist.cend(), match_sinkname);
        }
        if(match == devlist.cend())
            throw al::backend_exception{al::backend_error::NoDevice,
                "Device name \"%.*s\" not found", al::sizei(name), name.data()};

        targetid = match->mSerial;
        if(match->mType != NodeType::Sink) devname = match->mName;
        else devname = std::string{GetMonitorPrefix()}+match->mName;
    }

    if(!mLoop)
    {
        const uint count{OpenCount.fetch_add(1, std::memory_order_relaxed)};
        const std::string thread_name{"ALSoftC" + std::to_string(count)};
        mLoop = ThreadMainloop::Create(thread_name.c_str());
        if(!mLoop)
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to create PipeWire mainloop (errno: %d)", errno};
        if(int res{mLoop.start()})
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to start PipeWire mainloop (res: %d)", res};
    }
    MainloopUniqueLock mlock{mLoop};
    if(!mContext)
    {
        pw_properties *cprops{pw_properties_new(PW_KEY_CONFIG_NAME, "client-rt.conf", nullptr)};
        mContext = mLoop.newContext(cprops);
        if(!mContext)
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to create PipeWire event context (errno: %d)\n", errno};
    }
    if(!mCore)
    {
        mCore = PwCorePtr{pw_context_connect(mContext.get(), nullptr, 0)};
        if(!mCore)
            throw al::backend_exception{al::backend_error::DeviceError,
                "Failed to connect PipeWire event context (errno: %d)\n", errno};
    }
    mlock.unlock();

    /* TODO: Ensure the target ID is still valid/usable and accepts streams. */

    mTargetId = targetid;
    if(!devname.empty())
        mDeviceName = std::move(devname);
    else
        mDeviceName = "PipeWire Input"sv;


    bool is51rear{false};
    if(mTargetId != PwIdAny)
    {
        EventWatcherLockGuard evtlock{gEventHandler};
        auto&& devlist = DeviceNode::GetList();

        auto match_id = [targetid=mTargetId](const DeviceNode &n) -> bool
        { return targetid == n.mSerial; };
        auto match = std::find_if(devlist.cbegin(), devlist.cend(), match_id);
        if(match != devlist.cend())
            is51rear = match->mIs51Rear;
    }
    auto info = spa_audio_info_raw{make_spa_info(mDevice, is51rear, UseDevType)};

    auto b = PodDynamicBuilder{};
    auto params = as_const_ptr(spa_format_audio_raw_build(b.get(), SPA_PARAM_EnumFormat, &info));
    if(!params)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to set PipeWire audio format parameters"};

    auto&& binary = GetProcBinary();
    const char *appname{!binary.fname.empty() ? binary.fname.c_str() : "OpenAL Soft"};
    pw_properties *props{pw_properties_new(
        PW_KEY_NODE_NAME, appname,
        PW_KEY_NODE_DESCRIPTION, appname,
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_ROLE, "Game",
        PW_KEY_NODE_ALWAYS_PROCESS, "true",
        nullptr)};
    if(!props)
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to create PipeWire stream properties (errno: %d)", errno};

    /* We don't actually care what the latency/update size is, as long as it's
     * reasonable. Unfortunately, when unspecified PipeWire seems to default to
     * around 40ms, which isn't great. So request 20ms instead.
     */
    pw_properties_setf(props, PW_KEY_NODE_LATENCY, "%u/%u", (mDevice->Frequency+25) / 50,
        mDevice->Frequency);
    pw_properties_setf(props, PW_KEY_NODE_RATE, "1/%u", mDevice->Frequency);
#ifdef PW_KEY_TARGET_OBJECT
    pw_properties_setf(props, PW_KEY_TARGET_OBJECT, "%" PRIu64, mTargetId);
#else
    pw_properties_setf(props, PW_KEY_NODE_TARGET, "%" PRIu64, mTargetId);
#endif

    MainloopUniqueLock plock{mLoop};
    mStream = PwStreamPtr{pw_stream_new(mCore.get(), "Capture Stream", props)};
    if(!mStream)
        throw al::backend_exception{al::backend_error::NoDevice,
            "Failed to create PipeWire stream (errno: %d)", errno};
    static constexpr pw_stream_events streamEvents{CreateEvents()};
    pw_stream_add_listener(mStream.get(), &mStreamListener, &streamEvents, this);

    constexpr pw_stream_flags Flags{PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_INACTIVE
        | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS};
    if(int res{pw_stream_connect(mStream.get(), PW_DIRECTION_INPUT, PwIdAny, Flags, &params, 1)})
        throw al::backend_exception{al::backend_error::DeviceError,
            "Error connecting PipeWire stream (res: %d)", res};

    /* Wait for the stream to become paused (ready to start streaming). */
    plock.wait([stream=mStream.get()]()
    {
        const char *error{};
        pw_stream_state state{pw_stream_get_state(stream, &error)};
        if(state == PW_STREAM_STATE_ERROR)
            throw al::backend_exception{al::backend_error::DeviceError,
                "Error connecting PipeWire stream: \"%s\"", error};
        return state == PW_STREAM_STATE_PAUSED;
    });
    plock.unlock();

    setDefaultWFXChannelOrder();

    /* Ensure at least a 100ms capture buffer. */
    mRing = RingBuffer::Create(std::max(mDevice->Frequency/10u, mDevice->BufferSize),
        mDevice->frameSizeFromFmt(), false);
}


void PipeWireCapture::start()
{
    MainloopUniqueLock plock{mLoop};
    if(int res{pw_stream_set_active(mStream.get(), true)})
        throw al::backend_exception{al::backend_error::DeviceError,
            "Failed to start PipeWire stream (res: %d)", res};

    plock.wait([stream=mStream.get()]()
    {
        const char *error{};
        pw_stream_state state{pw_stream_get_state(stream, &error)};
        if(state == PW_STREAM_STATE_ERROR)
            throw al::backend_exception{al::backend_error::DeviceError,
                "PipeWire stream error: %s", error ? error : "(unknown)"};
        return state == PW_STREAM_STATE_STREAMING;
    });
}

void PipeWireCapture::stop()
{
    MainloopUniqueLock plock{mLoop};
    if(int res{pw_stream_set_active(mStream.get(), false)})
        ERR("Failed to stop PipeWire stream (res: %d)\n", res);

    plock.wait([stream=mStream.get()]()
    { return pw_stream_get_state(stream, nullptr) != PW_STREAM_STATE_STREAMING; });
}

uint PipeWireCapture::availableSamples()
{ return static_cast<uint>(mRing->readSpace()); }

void PipeWireCapture::captureSamples(std::byte *buffer, uint samples)
{ std::ignore = mRing->read(buffer, samples); }

} // namespace


bool PipeWireBackendFactory::init()
{
    if(!pwire_load())
        return false;

    const char *version{pw_get_library_version()};
    if(!check_version(version))
    {
        WARN("PipeWire version \"%s\" too old (%s or newer required)\n", version,
            pw_get_headers_version());
        return false;
    }
    TRACE("Found PipeWire version \"%s\" (%s or newer)\n", version, pw_get_headers_version());

    pw_init(nullptr, nullptr);
    if(!gEventHandler.init())
        return false;

    if(!GetConfigValueBool({}, "pipewire", "assume-audio", false)
        && !gEventHandler.waitForAudio())
    {
        gEventHandler.kill();
        /* TODO: Temporary warning, until PipeWire gets a proper way to report
         * audio support.
         */
        WARN("No audio support detected in PipeWire. See the PipeWire options in alsoftrc.sample if this is wrong.\n");
        return false;
    }
    return true;
}

bool PipeWireBackendFactory::querySupport(BackendType type)
{ return type == BackendType::Playback || type == BackendType::Capture; }

auto PipeWireBackendFactory::enumerate(BackendType type) -> std::vector<std::string>
{
    std::vector<std::string> outnames;

    gEventHandler.waitForInit();
    EventWatcherLockGuard evtlock{gEventHandler};
    auto&& devlist = DeviceNode::GetList();

    auto match_defsink = [](const DeviceNode &n) -> bool
    { return n.mDevName == DefaultSinkDevice; };
    auto match_defsource = [](const DeviceNode &n) -> bool
    { return n.mDevName == DefaultSourceDevice; };

    auto sort_devnode = [](DeviceNode &lhs, DeviceNode &rhs) noexcept -> bool
    { return lhs.mId < rhs.mId; };
    std::sort(devlist.begin(), devlist.end(), sort_devnode);

    auto defmatch = devlist.cbegin();
    switch(type)
    {
    case BackendType::Playback:
        defmatch = std::find_if(defmatch, devlist.cend(), match_defsink);
        if(defmatch != devlist.cend())
            outnames.emplace_back(defmatch->mName);
        for(auto iter = devlist.cbegin();iter != devlist.cend();++iter)
        {
            if(iter != defmatch && iter->mType != NodeType::Source)
                outnames.emplace_back(iter->mName);
        }
        break;
    case BackendType::Capture:
        outnames.reserve(devlist.size());
        defmatch = std::find_if(defmatch, devlist.cend(), match_defsource);
        if(defmatch != devlist.cend())
        {
            if(defmatch->mType == NodeType::Sink)
                outnames.emplace_back(std::string{GetMonitorPrefix()}+defmatch->mName);
            else
                outnames.emplace_back(defmatch->mName);
        }
        for(auto iter = devlist.cbegin();iter != devlist.cend();++iter)
        {
            if(iter != defmatch)
            {
                if(iter->mType == NodeType::Sink)
                    outnames.emplace_back(std::string{GetMonitorPrefix()}+iter->mName);
                else
                    outnames.emplace_back(iter->mName);
            }
        }
        break;
    }

    return outnames;
}


BackendPtr PipeWireBackendFactory::createBackend(DeviceBase *device, BackendType type)
{
    if(type == BackendType::Playback)
        return BackendPtr{new PipeWirePlayback{device}};
    if(type == BackendType::Capture)
        return BackendPtr{new PipeWireCapture{device}};
    return nullptr;
}

BackendFactory &PipeWireBackendFactory::getFactory()
{
    static PipeWireBackendFactory factory{};
    return factory;
}

alc::EventSupport PipeWireBackendFactory::queryEventSupport(alc::EventType eventType, BackendType)
{
    switch(eventType)
    {
    case alc::EventType::DefaultDeviceChanged:
    case alc::EventType::DeviceAdded:
    case alc::EventType::DeviceRemoved:
        return alc::EventSupport::FullSupport;

    case alc::EventType::Count:
        break;
    }
    return alc::EventSupport::NoSupport;
}
