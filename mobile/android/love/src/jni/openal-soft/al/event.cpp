
#include "config.h"

#include "event.h"

#include <array>
#include <atomic>
#include <bitset>
#include <exception>
#include <memory>
#include <mutex>
#include <new>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <tuple>
#include <utility>
#include <variant>

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/alext.h"

#include "alc/context.h"
#include "alsem.h"
#include "alspan.h"
#include "alstring.h"
#include "core/async_event.h"
#include "core/context.h"
#include "core/effects/base.h"
#include "core/logging.h"
#include "debug.h"
#include "direct_defs.h"
#include "error.h"
#include "intrusive_ptr.h"
#include "opthelpers.h"
#include "ringbuffer.h"


namespace {

template<typename... Ts>
struct overloaded : Ts... { using Ts::operator()...; };

template<typename... Ts>
overloaded(Ts...) -> overloaded<Ts...>;

int EventThread(ALCcontext *context)
{
    RingBuffer *ring{context->mAsyncEvents.get()};
    bool quitnow{false};
    while(!quitnow)
    {
        auto evt_data = ring->getReadVector()[0];
        if(evt_data.len == 0)
        {
            context->mEventSem.wait();
            continue;
        }

        auto eventlock = std::lock_guard{context->mEventCbLock};
        const auto enabledevts = context->mEnabledEvts.load(std::memory_order_acquire);
        auto evt_span = al::span{std::launder(reinterpret_cast<AsyncEvent*>(evt_data.buf)),
            evt_data.len};
        for(auto &event : evt_span)
        {
            quitnow = std::holds_alternative<AsyncKillThread>(event);
            if(quitnow) UNLIKELY break;

            auto proc_killthread = [](AsyncKillThread&) { };
            auto proc_release = [](AsyncEffectReleaseEvent &evt)
            {
                al::intrusive_ptr<EffectState>{evt.mEffectState};
            };
            auto proc_srcstate = [context,enabledevts](AsyncSourceStateEvent &evt)
            {
                if(!context->mEventCb
                    || !enabledevts.test(al::to_underlying(AsyncEnableBits::SourceState)))
                    return;

                ALuint state{};
                std::string msg{"Source ID " + std::to_string(evt.mId)};
                msg += " state has changed to ";
                switch(evt.mState)
                {
                case AsyncSrcState::Reset:
                    msg += "AL_INITIAL";
                    state = AL_INITIAL;
                    break;
                case AsyncSrcState::Stop:
                    msg += "AL_STOPPED";
                    state = AL_STOPPED;
                    break;
                case AsyncSrcState::Play:
                    msg += "AL_PLAYING";
                    state = AL_PLAYING;
                    break;
                case AsyncSrcState::Pause:
                    msg += "AL_PAUSED";
                    state = AL_PAUSED;
                    break;
                }
                context->mEventCb(AL_EVENT_TYPE_SOURCE_STATE_CHANGED_SOFT, evt.mId, state,
                    al::sizei(msg), msg.c_str(), context->mEventParam);
            };
            auto proc_buffercomp = [context,enabledevts](AsyncBufferCompleteEvent &evt)
            {
                if(!context->mEventCb
                    || !enabledevts.test(al::to_underlying(AsyncEnableBits::BufferCompleted)))
                    return;

                std::string msg{std::to_string(evt.mCount)};
                if(evt.mCount == 1) msg += " buffer completed";
                else msg += " buffers completed";
                context->mEventCb(AL_EVENT_TYPE_BUFFER_COMPLETED_SOFT, evt.mId, evt.mCount,
                    al::sizei(msg), msg.c_str(), context->mEventParam);
            };
            auto proc_disconnect = [context,enabledevts](AsyncDisconnectEvent &evt)
            {
                if(!context->mEventCb
                    || !enabledevts.test(al::to_underlying(AsyncEnableBits::Disconnected)))
                    return;

                context->mEventCb(AL_EVENT_TYPE_DISCONNECTED_SOFT, 0, 0, al::sizei(evt.msg),
                    evt.msg.c_str(), context->mEventParam);
            };

            std::visit(overloaded{proc_srcstate, proc_buffercomp, proc_release, proc_disconnect,
                proc_killthread}, event);
        }
        std::destroy(evt_span.begin(), evt_span.end());
        ring->readAdvance(evt_span.size());
    }
    return 0;
}

constexpr std::optional<AsyncEnableBits> GetEventType(ALenum etype) noexcept
{
    switch(etype)
    {
    case AL_EVENT_TYPE_BUFFER_COMPLETED_SOFT: return AsyncEnableBits::BufferCompleted;
    case AL_EVENT_TYPE_DISCONNECTED_SOFT: return AsyncEnableBits::Disconnected;
    case AL_EVENT_TYPE_SOURCE_STATE_CHANGED_SOFT: return AsyncEnableBits::SourceState;
    }
    return std::nullopt;
}

} // namespace


void StartEventThrd(ALCcontext *ctx)
{
    try {
        ctx->mEventThread = std::thread{EventThread, ctx};
    }
    catch(std::exception& e) {
        ERR("Failed to start event thread: %s\n", e.what());
    }
    catch(...) {
        ERR("Failed to start event thread! Expect problems.\n");
    }
}

void StopEventThrd(ALCcontext *ctx)
{
    RingBuffer *ring{ctx->mAsyncEvents.get()};
    auto evt_data = ring->getWriteVector()[0];
    if(evt_data.len == 0)
    {
        do {
            std::this_thread::yield();
            evt_data = ring->getWriteVector()[0];
        } while(evt_data.len == 0);
    }
    std::ignore = InitAsyncEvent<AsyncKillThread>(evt_data.buf);
    ring->writeAdvance(1);

    ctx->mEventSem.post();
    if(ctx->mEventThread.joinable())
        ctx->mEventThread.join();
}

AL_API DECL_FUNCEXT3(void, alEventControl,SOFT, ALsizei,count, const ALenum*,types, ALboolean,enable)
FORCE_ALIGN void AL_APIENTRY alEventControlDirectSOFT(ALCcontext *context, ALsizei count,
    const ALenum *types, ALboolean enable) noexcept
try {
    if(count < 0)
        throw al::context_error{AL_INVALID_VALUE, "Controlling %d events", count};
    if(count <= 0) UNLIKELY return;

    if(!types)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    ContextBase::AsyncEventBitset flags{};
    for(ALenum evttype : al::span{types, static_cast<uint>(count)})
    {
        auto etype = GetEventType(evttype);
        if(!etype)
            throw al::context_error{AL_INVALID_ENUM, "Invalid event type 0x%04x", evttype};
        flags.set(al::to_underlying(*etype));
    }

    if(enable)
    {
        auto enabledevts = context->mEnabledEvts.load(std::memory_order_relaxed);
        while(context->mEnabledEvts.compare_exchange_weak(enabledevts, enabledevts|flags,
            std::memory_order_acq_rel, std::memory_order_acquire) == 0)
        {
            /* enabledevts is (re-)filled with the current value on failure, so
             * just try again.
             */
        }
    }
    else
    {
        auto enabledevts = context->mEnabledEvts.load(std::memory_order_relaxed);
        while(context->mEnabledEvts.compare_exchange_weak(enabledevts, enabledevts&~flags,
            std::memory_order_acq_rel, std::memory_order_acquire) == 0)
        {
        }
        /* Wait to ensure the event handler sees the changed flags before
         * returning.
         */
        std::lock_guard<std::mutex> eventlock{context->mEventCbLock};
    }
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNCEXT2(void, alEventCallback,SOFT, ALEVENTPROCSOFT,callback, void*,userParam)
FORCE_ALIGN void AL_APIENTRY alEventCallbackDirectSOFT(ALCcontext *context,
    ALEVENTPROCSOFT callback, void *userParam) noexcept
{
    std::lock_guard<std::mutex> eventlock{context->mEventCbLock};
    context->mEventCb = callback;
    context->mEventParam = userParam;
}
