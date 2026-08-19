
#include "config.h"

#include "context.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <functional>
#include <iterator>
#include <numeric>
#include <optional>
#include <string_view>
#include <tuple>
#include <utility>

#include "AL/efx.h"

#include "al/auxeffectslot.h"
#include "al/debug.h"
#include "al/source.h"
#include "al/effect.h"
#include "al/event.h"
#include "al/listener.h"
#include "albit.h"
#include "alc/alu.h"
#include "alc/backends/base.h"
#include "alnumeric.h"
#include "alspan.h"
#include "atomic.h"
#include "core/async_event.h"
#include "core/devformat.h"
#include "core/device.h"
#include "core/effectslot.h"
#include "core/logging.h"
#include "core/voice_change.h"
#include "device.h"
#include "flexarray.h"
#include "ringbuffer.h"
#include "vecmat.h"

#if ALSOFT_EAX
#include "al/eax/call.h"
#include "al/eax/globals.h"
#endif // ALSOFT_EAX

namespace {

using namespace std::string_view_literals;
using voidp = void*;

/* Default context extensions */
std::vector<std::string_view> getContextExtensions() noexcept
{
    return std::vector<std::string_view>{
        "AL_EXT_ALAW"sv,
        "AL_EXT_BFORMAT"sv,
        "AL_EXT_debug"sv,
        "AL_EXT_direct_context"sv,
        "AL_EXT_DOUBLE"sv,
        "AL_EXT_EXPONENT_DISTANCE"sv,
        "AL_EXT_FLOAT32"sv,
        "AL_EXT_IMA4"sv,
        "AL_EXT_LINEAR_DISTANCE"sv,
        "AL_EXT_MCFORMATS"sv,
        "AL_EXT_MULAW"sv,
        "AL_EXT_MULAW_BFORMAT"sv,
        "AL_EXT_MULAW_MCFORMATS"sv,
        "AL_EXT_OFFSET"sv,
        "AL_EXT_source_distance_model"sv,
        "AL_EXT_SOURCE_RADIUS"sv,
        "AL_EXT_STATIC_BUFFER"sv,
        "AL_EXT_STEREO_ANGLES"sv,
        "AL_LOKI_quadriphonic"sv,
        "AL_SOFT_bformat_ex"sv,
        "AL_SOFTX_bformat_hoa"sv,
        "AL_SOFT_block_alignment"sv,
        "AL_SOFT_buffer_length_query"sv,
        "AL_SOFT_callback_buffer"sv,
        "AL_SOFTX_convolution_effect"sv,
        "AL_SOFT_deferred_updates"sv,
        "AL_SOFT_direct_channels"sv,
        "AL_SOFT_direct_channels_remix"sv,
        "AL_SOFT_effect_target"sv,
        "AL_SOFT_events"sv,
        "AL_SOFT_gain_clamp_ex"sv,
        "AL_SOFTX_hold_on_disconnect"sv,
        "AL_SOFT_loop_points"sv,
        "AL_SOFTX_map_buffer"sv,
        "AL_SOFT_MSADPCM"sv,
        "AL_SOFT_source_latency"sv,
        "AL_SOFT_source_length"sv,
        "AL_SOFTX_source_panning"sv,
        "AL_SOFT_source_resampler"sv,
        "AL_SOFT_source_spatialize"sv,
        "AL_SOFT_source_start_delay"sv,
        "AL_SOFT_UHJ"sv,
        "AL_SOFT_UHJ_ex"sv,
    };
}

} // namespace


std::atomic<bool> ALCcontext::sGlobalContextLock{false};
std::atomic<ALCcontext*> ALCcontext::sGlobalContext{nullptr};

ALCcontext::ThreadCtx::~ThreadCtx()
{
    if(ALCcontext *ctx{std::exchange(ALCcontext::sLocalContext, nullptr)})
    {
        const bool result{ctx->releaseIfNoDelete()};
        ERR("Context %p current for thread being destroyed%s!\n", voidp{ctx},
            result ? "" : ", leak detected");
    }
}
thread_local ALCcontext::ThreadCtx ALCcontext::sThreadContext;

ALeffect ALCcontext::sDefaultEffect;


ALCcontext::ALCcontext(al::intrusive_ptr<ALCdevice> device, ContextFlagBitset flags)
    : ContextBase{device.get()}, mALDevice{std::move(device)}, mContextFlags{flags}
{
    mDebugGroups.emplace_back(DebugSource::Other, 0, std::string{});
    mDebugEnabled.store(mContextFlags.test(ContextFlags::DebugBit), std::memory_order_relaxed);

    /* Low-severity debug messages are disabled by default. */
    alDebugMessageControlDirectEXT(this, AL_DONT_CARE_EXT, AL_DONT_CARE_EXT,
        AL_DEBUG_SEVERITY_LOW_EXT, 0, nullptr, AL_FALSE);
}

ALCcontext::~ALCcontext()
{
    TRACE("Freeing context %p\n", voidp{this});

    size_t count{std::accumulate(mSourceList.cbegin(), mSourceList.cend(), 0_uz,
        [](size_t cur, const SourceSubList &sublist) noexcept -> size_t
        { return cur + static_cast<uint>(al::popcount(~sublist.FreeMask)); })};
    if(count > 0)
        WARN("%zu Source%s not deleted\n", count, (count==1)?"":"s");
    mSourceList.clear();
    mNumSources = 0;

#if ALSOFT_EAX
    eaxUninitialize();
#endif // ALSOFT_EAX

    mDefaultSlot = nullptr;
    count = std::accumulate(mEffectSlotList.cbegin(), mEffectSlotList.cend(), 0_uz,
        [](size_t cur, const EffectSlotSubList &sublist) noexcept -> size_t
        { return cur + static_cast<uint>(al::popcount(~sublist.FreeMask)); });
    if(count > 0)
        WARN("%zu AuxiliaryEffectSlot%s not deleted\n", count, (count==1)?"":"s");
    mEffectSlotList.clear();
    mNumEffectSlots = 0;
}

void ALCcontext::init()
{
    if(sDefaultEffect.type != AL_EFFECT_NULL && mDevice->Type == DeviceType::Playback)
    {
        mDefaultSlot = std::make_unique<ALeffectslot>(this);
        aluInitEffectPanning(mDefaultSlot->mSlot, this);
    }

    std::unique_ptr<EffectSlotArray> auxslots;
    if(!mDefaultSlot)
        auxslots = EffectSlot::CreatePtrArray(0);
    else
    {
        auxslots = EffectSlot::CreatePtrArray(2);
        (*auxslots)[0] = mDefaultSlot->mSlot;
        (*auxslots)[1] = mDefaultSlot->mSlot;
        mDefaultSlot->mState = SlotState::Playing;
    }
    mActiveAuxSlots.store(std::move(auxslots), std::memory_order_relaxed);

    allocVoiceChanges();
    {
        VoiceChange *cur{mVoiceChangeTail};
        while(VoiceChange *next{cur->mNext.load(std::memory_order_relaxed)})
            cur = next;
        mCurrentVoiceChange.store(cur, std::memory_order_relaxed);
    }

    mExtensions = getContextExtensions();

    if(sBufferSubDataCompat)
    {
        auto iter = std::find(mExtensions.begin(), mExtensions.end(), "AL_EXT_SOURCE_RADIUS"sv);
        if(iter != mExtensions.end()) mExtensions.erase(iter);
        /* TODO: Would be nice to sort this alphabetically. Needs case-
         * insensitive searching.
         */
        mExtensions.emplace_back("AL_SOFT_buffer_sub_data"sv);
    }

#if ALSOFT_EAX
    eax_initialize_extensions();
#endif // ALSOFT_EAX

    if(!mExtensions.empty())
    {
        const size_t len{std::accumulate(mExtensions.cbegin()+1, mExtensions.cend(),
            mExtensions.front().length(),
            [](size_t current, std::string_view ext) noexcept
            { return current + ext.length() + 1; })};

        std::string extensions;
        extensions.reserve(len);
        extensions += mExtensions.front();
        for(std::string_view ext : al::span{mExtensions}.subspan<1>())
        {
            extensions += ' ';
            extensions += ext;
        }

        mExtensionsString = std::move(extensions);
    }

#if ALSOFT_EAX
    eax_set_defaults();
#endif

    mParams.Position = alu::Vector{0.0f, 0.0f, 0.0f, 1.0f};
    mParams.Matrix = alu::Matrix::Identity();
    mParams.Velocity = alu::Vector{};
    mParams.Gain = mListener.Gain;
    mParams.MetersPerUnit = mListener.mMetersPerUnit
#if ALSOFT_EAX
        * eaxGetDistanceFactor()
#endif
        ;
    mParams.AirAbsorptionGainHF = mAirAbsorptionGainHF;
    mParams.DopplerFactor = mDopplerFactor;
    mParams.SpeedOfSound = mSpeedOfSound * mDopplerVelocity
#if ALSOFT_EAX
        / eaxGetDistanceFactor()
#endif
        ;
    mParams.SourceDistanceModel = mSourceDistanceModel;
    mParams.mDistanceModel = mDistanceModel;


    mAsyncEvents = RingBuffer::Create(1024, sizeof(AsyncEvent), false);
    StartEventThrd(this);


    allocVoices(256);
    mActiveVoiceCount.store(64, std::memory_order_relaxed);
}

void ALCcontext::deinit()
{
    if(sLocalContext == this)
    {
        WARN("%p released while current on thread\n", voidp{this});
        sThreadContext.set(nullptr);
        const auto rc [[maybe_unused]] = dec_ref();
        assert(rc > 0);
    }

    ALCcontext *origctx{this};
    if(sGlobalContext.compare_exchange_strong(origctx, nullptr))
    {
        while(sGlobalContextLock.load()) {
            /* Wait to make sure another thread didn't get the context and is
             * trying to increment its refcount.
             */
        }
        const auto rc [[maybe_unused]] = dec_ref();
        assert(rc > 0);
    }

    bool stopPlayback{};
    /* First make sure this context exists in the device's list. */
    auto *oldarray = mDevice->mContexts.load(std::memory_order_acquire);
    if(auto toremove = static_cast<size_t>(std::count(oldarray->begin(), oldarray->end(), this)))
    {
        using ContextArray = al::FlexArray<ContextBase*>;
        const size_t newsize{oldarray->size() - toremove};
        auto newarray = ContextArray::Create(newsize);

        /* Copy the current/old context handles to the new array, excluding the
         * given context.
         */
        std::copy_if(oldarray->begin(), oldarray->end(), newarray->begin(),
            [this](ContextBase *ctx) { return ctx != this; });

        /* Store the new context array in the device. Wait for any current mix
         * to finish before deleting the old array.
         */
        auto prevarray = mDevice->mContexts.exchange(std::move(newarray));
        std::ignore = mDevice->waitForMix();

        stopPlayback = (newsize == 0);
    }
    else
        stopPlayback = oldarray->empty();

    StopEventThrd(this);

    if(stopPlayback && mALDevice->mDeviceState == DeviceState::Playing)
    {
        mALDevice->Backend->stop();
        mALDevice->mDeviceState = DeviceState::Configured;
    }
}

void ALCcontext::applyAllUpdates()
{
    /* Tell the mixer to stop applying updates, then wait for any active
     * updating to finish, before providing updates.
     */
    mHoldUpdates.store(true, std::memory_order_release);
    while((mUpdateCount.load(std::memory_order_acquire)&1) != 0) {
        /* busy-wait */
    }

#if ALSOFT_EAX
    if(mEaxNeedsCommit)
        eaxCommit();
#endif

    if(std::exchange(mPropsDirty, false))
        UpdateContextProps(this);
    UpdateAllEffectSlotProps(this);
    UpdateAllSourceProps(this);

    /* Now with all updates declared, let the mixer continue applying them so
     * they all happen at once.
     */
    mHoldUpdates.store(false, std::memory_order_release);
}


#if ALSOFT_EAX
namespace {

template<typename F>
void ForEachSource(ALCcontext *context, F func)
{
    for(auto &sublist : context->mSourceList)
    {
        uint64_t usemask{~sublist.FreeMask};
        while(usemask)
        {
            const auto idx = static_cast<uint>(al::countr_zero(usemask));
            usemask &= ~(1_u64 << idx);

            func((*sublist.Sources)[idx]);
        }
    }
}

} // namespace


bool ALCcontext::eaxIsCapable() const noexcept
{
    return eax_has_enough_aux_sends();
}

void ALCcontext::eaxUninitialize() noexcept
{
    if(!mEaxIsInitialized)
        return;

    mEaxIsInitialized = false;
    mEaxIsTried = false;
    mEaxFxSlots.uninitialize();
}

ALenum ALCcontext::eax_eax_set(
    const GUID* property_set_id,
    ALuint property_id,
    ALuint property_source_id,
    ALvoid* property_value,
    ALuint property_value_size)
{
    const auto call = create_eax_call(
        EaxCallType::set,
        property_set_id,
        property_id,
        property_source_id,
        property_value,
        property_value_size);

    eax_initialize();

    switch(call.get_property_set_id())
    {
    case EaxCallPropertySetId::context:
        eax_set(call);
        break;
    case EaxCallPropertySetId::fx_slot:
    case EaxCallPropertySetId::fx_slot_effect:
        eax_dispatch_fx_slot(call);
        break;
    case EaxCallPropertySetId::source:
        eax_dispatch_source(call);
        break;
    default:
        eax_fail_unknown_property_set_id();
    }
    mEaxNeedsCommit = true;

    if(!call.is_deferred())
    {
        eaxCommit();
        if(!mDeferUpdates)
            applyAllUpdates();
    }

    return AL_NO_ERROR;
}

ALenum ALCcontext::eax_eax_get(
    const GUID* property_set_id,
    ALuint property_id,
    ALuint property_source_id,
    ALvoid* property_value,
    ALuint property_value_size)
{
    const auto call = create_eax_call(
        EaxCallType::get,
        property_set_id,
        property_id,
        property_source_id,
        property_value,
        property_value_size);

    eax_initialize();

    switch(call.get_property_set_id())
    {
    case EaxCallPropertySetId::context:
        eax_get(call);
        break;
    case EaxCallPropertySetId::fx_slot:
    case EaxCallPropertySetId::fx_slot_effect:
        eax_dispatch_fx_slot(call);
        break;
    case EaxCallPropertySetId::source:
        eax_dispatch_source(call);
        break;
    default:
        eax_fail_unknown_property_set_id();
    }

    return AL_NO_ERROR;
}

void ALCcontext::eaxSetLastError() noexcept
{
    mEaxLastError = EAXERR_INVALID_OPERATION;
}

[[noreturn]] void ALCcontext::eax_fail(const char* message)
{
    throw ContextException{message};
}

[[noreturn]] void ALCcontext::eax_fail_unknown_property_set_id()
{
    eax_fail("Unknown property ID.");
}

[[noreturn]] void ALCcontext::eax_fail_unknown_primary_fx_slot_id()
{
    eax_fail("Unknown primary FX Slot ID.");
}

[[noreturn]] void ALCcontext::eax_fail_unknown_property_id()
{
    eax_fail("Unknown property ID.");
}

[[noreturn]] void ALCcontext::eax_fail_unknown_version()
{
    eax_fail("Unknown version.");
}

void ALCcontext::eax_initialize_extensions()
{
    if(!eax_g_is_enabled)
        return;

    mExtensions.emplace(mExtensions.begin(), "EAX-RAM"sv);
    if(eaxIsCapable())
    {
        mExtensions.emplace(mExtensions.begin(), "EAX5.0"sv);
        mExtensions.emplace(mExtensions.begin(), "EAX4.0"sv);
        mExtensions.emplace(mExtensions.begin(), "EAX3.0"sv);
        mExtensions.emplace(mExtensions.begin(), "EAX2.0"sv);
        mExtensions.emplace(mExtensions.begin(), "EAX"sv);
    }
}

void ALCcontext::eax_initialize()
{
    if(mEaxIsInitialized)
        return;

    if(mEaxIsTried)
        eax_fail("No EAX.");

    mEaxIsTried = true;

    if(!eax_g_is_enabled)
        eax_fail("EAX disabled by a configuration.");

    eax_ensure_compatibility();
    eax_set_defaults();
    eax_context_commit_air_absorbtion_hf();
    eax_update_speaker_configuration();
    eax_initialize_fx_slots();

    mEaxIsInitialized = true;
}

bool ALCcontext::eax_has_no_default_effect_slot() const noexcept
{
    return mDefaultSlot == nullptr;
}

void ALCcontext::eax_ensure_no_default_effect_slot() const
{
    if(!eax_has_no_default_effect_slot())
        eax_fail("There is a default effect slot in the context.");
}

bool ALCcontext::eax_has_enough_aux_sends() const noexcept
{
    return mALDevice->NumAuxSends >= EAX_MAX_FXSLOTS;
}

void ALCcontext::eax_ensure_enough_aux_sends() const
{
    if(!eax_has_enough_aux_sends())
        eax_fail("Not enough aux sends.");
}

void ALCcontext::eax_ensure_compatibility()
{
    eax_ensure_enough_aux_sends();
}

unsigned long ALCcontext::eax_detect_speaker_configuration() const
{
#define EAX_PREFIX "[EAX_DETECT_SPEAKER_CONFIG]"

    switch(mDevice->FmtChans)
    {
    case DevFmtMono: return SPEAKERS_2;
    case DevFmtStereo:
        /* Pretend 7.1 if using UHJ output, since they both provide full
         * horizontal surround.
         */
        if(mDevice->mUhjEncoder)
            return SPEAKERS_7;
        if(mDevice->Flags.test(DirectEar))
            return HEADPHONES;
        return SPEAKERS_2;
    case DevFmtQuad: return SPEAKERS_4;
    case DevFmtX51: return SPEAKERS_5;
    case DevFmtX61: return SPEAKERS_6;
    case DevFmtX71: return SPEAKERS_7;
    /* 7.1.4(.4) is compatible with 7.1. This could instead be HEADPHONES to
     * suggest with-height surround sound (like HRTF).
     */
    case DevFmtX714: return SPEAKERS_7;
    case DevFmtX7144: return SPEAKERS_7;
    /* 3D7.1 is only compatible with 5.1. This could instead be HEADPHONES to
     * suggest full-sphere surround sound (like HRTF).
     */
    case DevFmtX3D71: return SPEAKERS_5;
    /* This could also be HEADPHONES, since headphones-based HRTF and Ambi3D
     * provide full-sphere surround sound. Depends if apps are more likely to
     * consider headphones or 7.1 for surround sound support.
     */
    case DevFmtAmbi3D: return SPEAKERS_7;
    }
    ERR(EAX_PREFIX "Unexpected device channel format 0x%x.\n", mDevice->FmtChans);
    return HEADPHONES;

#undef EAX_PREFIX
}

void ALCcontext::eax_update_speaker_configuration()
{
    mEaxSpeakerConfig = eax_detect_speaker_configuration();
}

void ALCcontext::eax_set_last_error_defaults() noexcept
{
    mEaxLastError = EAXCONTEXT_DEFAULTLASTERROR;
}

void ALCcontext::eax_session_set_defaults() noexcept
{
    mEaxSession.ulEAXVersion = EAXCONTEXT_DEFAULTEAXSESSION;
    mEaxSession.ulMaxActiveSends = EAXCONTEXT_DEFAULTMAXACTIVESENDS;
}

void ALCcontext::eax4_context_set_defaults(Eax4Props& props) noexcept
{
    props.guidPrimaryFXSlotID = EAX40CONTEXT_DEFAULTPRIMARYFXSLOTID;
    props.flDistanceFactor = EAXCONTEXT_DEFAULTDISTANCEFACTOR;
    props.flAirAbsorptionHF = EAXCONTEXT_DEFAULTAIRABSORPTIONHF;
    props.flHFReference = EAXCONTEXT_DEFAULTHFREFERENCE;
}

void ALCcontext::eax4_context_set_defaults(Eax4State& state) noexcept
{
    eax4_context_set_defaults(state.i);
    state.d = state.i;
}

void ALCcontext::eax5_context_set_defaults(Eax5Props& props) noexcept
{
    props.guidPrimaryFXSlotID = EAX50CONTEXT_DEFAULTPRIMARYFXSLOTID;
    props.flDistanceFactor = EAXCONTEXT_DEFAULTDISTANCEFACTOR;
    props.flAirAbsorptionHF = EAXCONTEXT_DEFAULTAIRABSORPTIONHF;
    props.flHFReference = EAXCONTEXT_DEFAULTHFREFERENCE;
    props.flMacroFXFactor = EAXCONTEXT_DEFAULTMACROFXFACTOR;
}

void ALCcontext::eax5_context_set_defaults(Eax5State& state) noexcept
{
    eax5_context_set_defaults(state.i);
    state.d = state.i;
}

void ALCcontext::eax_context_set_defaults()
{
    eax5_context_set_defaults(mEax123);
    eax4_context_set_defaults(mEax4);
    eax5_context_set_defaults(mEax5);
    mEax = mEax5.i;
    mEaxVersion = 5;
    mEaxDf = EaxDirtyFlags{};
}

void ALCcontext::eax_set_defaults()
{
    eax_set_last_error_defaults();
    eax_session_set_defaults();
    eax_context_set_defaults();
}

void ALCcontext::eax_dispatch_fx_slot(const EaxCall& call)
{
    const auto fx_slot_index = call.get_fx_slot_index();
    if(!fx_slot_index.has_value())
        eax_fail("Invalid fx slot index.");

    auto& fx_slot = eaxGetFxSlot(*fx_slot_index);
    if(fx_slot.eax_dispatch(call))
    {
        std::lock_guard<std::mutex> source_lock{mSourceLock};
        ForEachSource(this, std::mem_fn(&ALsource::eaxMarkAsChanged));
    }
}

void ALCcontext::eax_dispatch_source(const EaxCall& call)
{
    const auto source_id = call.get_property_al_name();
    std::lock_guard<std::mutex> source_lock{mSourceLock};
    const auto source = ALsource::EaxLookupSource(*this, source_id);

    if (source == nullptr)
        eax_fail("Source not found.");

    source->eaxDispatch(call);
}

void ALCcontext::eax_get_misc(const EaxCall& call)
{
    switch(call.get_property_id())
    {
    case EAXCONTEXT_NONE:
        break;
    case EAXCONTEXT_LASTERROR:
        call.set_value<ContextException>(mEaxLastError);
        mEaxLastError = EAX_OK;
        break;
    case EAXCONTEXT_SPEAKERCONFIG:
        call.set_value<ContextException>(mEaxSpeakerConfig);
        break;
    case EAXCONTEXT_EAXSESSION:
        call.set_value<ContextException>(mEaxSession);
        break;
    default:
        eax_fail_unknown_property_id();
    }
}

void ALCcontext::eax4_get(const EaxCall& call, const Eax4Props& props)
{
    switch(call.get_property_id())
    {
    case EAXCONTEXT_ALLPARAMETERS:
        call.set_value<ContextException>(props);
        break;
    case EAXCONTEXT_PRIMARYFXSLOTID:
        call.set_value<ContextException>(props.guidPrimaryFXSlotID);
        break;
    case EAXCONTEXT_DISTANCEFACTOR:
        call.set_value<ContextException>(props.flDistanceFactor);
        break;
    case EAXCONTEXT_AIRABSORPTIONHF:
        call.set_value<ContextException>(props.flAirAbsorptionHF);
        break;
    case EAXCONTEXT_HFREFERENCE:
        call.set_value<ContextException>(props.flHFReference);
        break;
    default:
        eax_get_misc(call);
        break;
    }
}

void ALCcontext::eax5_get(const EaxCall& call, const Eax5Props& props)
{
    switch(call.get_property_id())
    {
    case EAXCONTEXT_ALLPARAMETERS:
        call.set_value<ContextException>(props);
        break;
    case EAXCONTEXT_PRIMARYFXSLOTID:
        call.set_value<ContextException>(props.guidPrimaryFXSlotID);
        break;
    case EAXCONTEXT_DISTANCEFACTOR:
        call.set_value<ContextException>(props.flDistanceFactor);
        break;
    case EAXCONTEXT_AIRABSORPTIONHF:
        call.set_value<ContextException>(props.flAirAbsorptionHF);
        break;
    case EAXCONTEXT_HFREFERENCE:
        call.set_value<ContextException>(props.flHFReference);
        break;
    case EAXCONTEXT_MACROFXFACTOR:
        call.set_value<ContextException>(props.flMacroFXFactor);
        break;
    default:
        eax_get_misc(call);
        break;
    }
}

void ALCcontext::eax_get(const EaxCall& call)
{
    switch(call.get_version())
    {
    case 4: eax4_get(call, mEax4.i); break;
    case 5: eax5_get(call, mEax5.i); break;
    default: eax_fail_unknown_version();
    }
}

void ALCcontext::eax_context_commit_primary_fx_slot_id()
{
    mEaxPrimaryFxSlotIndex = mEax.guidPrimaryFXSlotID;
}

void ALCcontext::eax_context_commit_distance_factor()
{
    /* mEax.flDistanceFactor was changed, so the context props are dirty. */
    mPropsDirty = true;
}

void ALCcontext::eax_context_commit_air_absorbtion_hf()
{
    const auto new_value = level_mb_to_gain(mEax.flAirAbsorptionHF);

    if(mAirAbsorptionGainHF == new_value)
        return;

    mAirAbsorptionGainHF = new_value;
    mPropsDirty = true;
}

void ALCcontext::eax_context_commit_hf_reference()
{
    // TODO
}

void ALCcontext::eax_context_commit_macro_fx_factor()
{
    // TODO
}

void ALCcontext::eax_initialize_fx_slots()
{
    mEaxFxSlots.initialize(*this);
    mEaxPrimaryFxSlotIndex = mEax.guidPrimaryFXSlotID;
}

void ALCcontext::eax_update_sources()
{
    std::unique_lock<std::mutex> source_lock{mSourceLock};
    auto update_source = [](ALsource &source)
    { source.eaxCommit(); };
    ForEachSource(this, update_source);
}

void ALCcontext::eax_set_misc(const EaxCall& call)
{
    switch(call.get_property_id())
    {
    case EAXCONTEXT_NONE:
        break;
    case EAXCONTEXT_SPEAKERCONFIG:
        eax_set<Eax5SpeakerConfigValidator>(call, mEaxSpeakerConfig);
        break;
    case EAXCONTEXT_EAXSESSION:
        eax_set<Eax5SessionAllValidator>(call, mEaxSession);
        break;
    default:
        eax_fail_unknown_property_id();
    }
}

void ALCcontext::eax4_defer_all(const EaxCall& call, Eax4State& state)
{
    const auto& src = call.get_value<ContextException, const EAX40CONTEXTPROPERTIES>();
    Eax4AllValidator{}(src);
    const auto& dst_i = state.i;
    auto& dst_d = state.d;
    dst_d = src;

    if(dst_i.guidPrimaryFXSlotID != dst_d.guidPrimaryFXSlotID)
        mEaxDf |= eax_primary_fx_slot_id_dirty_bit;

    if(dst_i.flDistanceFactor != dst_d.flDistanceFactor)
        mEaxDf |= eax_distance_factor_dirty_bit;

    if(dst_i.flAirAbsorptionHF != dst_d.flAirAbsorptionHF)
        mEaxDf |= eax_air_absorption_hf_dirty_bit;

    if(dst_i.flHFReference != dst_d.flHFReference)
        mEaxDf |= eax_hf_reference_dirty_bit;
}

void ALCcontext::eax4_defer(const EaxCall& call, Eax4State& state)
{
    switch(call.get_property_id())
    {
    case EAXCONTEXT_ALLPARAMETERS:
        eax4_defer_all(call, state);
        break;
    case EAXCONTEXT_PRIMARYFXSLOTID:
        eax_defer<Eax4PrimaryFxSlotIdValidator, eax_primary_fx_slot_id_dirty_bit>(
            call, state, &EAX40CONTEXTPROPERTIES::guidPrimaryFXSlotID);
        break;
    case EAXCONTEXT_DISTANCEFACTOR:
        eax_defer<Eax4DistanceFactorValidator, eax_distance_factor_dirty_bit>(
            call, state, &EAX40CONTEXTPROPERTIES::flDistanceFactor);
        break;
    case EAXCONTEXT_AIRABSORPTIONHF:
        eax_defer<Eax4AirAbsorptionHfValidator, eax_air_absorption_hf_dirty_bit>(
            call, state, &EAX40CONTEXTPROPERTIES::flAirAbsorptionHF);
        break;
    case EAXCONTEXT_HFREFERENCE:
        eax_defer<Eax4HfReferenceValidator, eax_hf_reference_dirty_bit>(
            call, state, &EAX40CONTEXTPROPERTIES::flHFReference);
        break;
    default:
        eax_set_misc(call);
        break;
    }
}

void ALCcontext::eax5_defer_all(const EaxCall& call, Eax5State& state)
{
    const auto& src = call.get_value<ContextException, const EAX50CONTEXTPROPERTIES>();
    Eax4AllValidator{}(src);
    const auto& dst_i = state.i;
    auto& dst_d = state.d;
    dst_d = src;

    if(dst_i.guidPrimaryFXSlotID != dst_d.guidPrimaryFXSlotID)
        mEaxDf |= eax_primary_fx_slot_id_dirty_bit;

    if(dst_i.flDistanceFactor != dst_d.flDistanceFactor)
        mEaxDf |= eax_distance_factor_dirty_bit;

    if(dst_i.flAirAbsorptionHF != dst_d.flAirAbsorptionHF)
        mEaxDf |= eax_air_absorption_hf_dirty_bit;

    if(dst_i.flHFReference != dst_d.flHFReference)
        mEaxDf |= eax_hf_reference_dirty_bit;

    if(dst_i.flMacroFXFactor != dst_d.flMacroFXFactor)
        mEaxDf |= eax_macro_fx_factor_dirty_bit;
}

void ALCcontext::eax5_defer(const EaxCall& call, Eax5State& state)
{
    switch(call.get_property_id())
    {
    case EAXCONTEXT_ALLPARAMETERS:
        eax5_defer_all(call, state);
        break;
    case EAXCONTEXT_PRIMARYFXSLOTID:
        eax_defer<Eax5PrimaryFxSlotIdValidator, eax_primary_fx_slot_id_dirty_bit>(
            call, state, &EAX50CONTEXTPROPERTIES::guidPrimaryFXSlotID);
        break;
    case EAXCONTEXT_DISTANCEFACTOR:
        eax_defer<Eax4DistanceFactorValidator, eax_distance_factor_dirty_bit>(
            call, state, &EAX50CONTEXTPROPERTIES::flDistanceFactor);
        break;
    case EAXCONTEXT_AIRABSORPTIONHF:
        eax_defer<Eax4AirAbsorptionHfValidator, eax_air_absorption_hf_dirty_bit>(
            call, state, &EAX50CONTEXTPROPERTIES::flAirAbsorptionHF);
        break;
    case EAXCONTEXT_HFREFERENCE:
        eax_defer<Eax4HfReferenceValidator, eax_hf_reference_dirty_bit>(
            call, state, &EAX50CONTEXTPROPERTIES::flHFReference);
        break;
    case EAXCONTEXT_MACROFXFACTOR:
        eax_defer<Eax5MacroFxFactorValidator, eax_macro_fx_factor_dirty_bit>(
            call, state, &EAX50CONTEXTPROPERTIES::flMacroFXFactor);
        break;
    default:
        eax_set_misc(call);
        break;
    }
}

void ALCcontext::eax_set(const EaxCall& call)
{
    const auto version = call.get_version();
    switch(version)
    {
    case 4: eax4_defer(call, mEax4); break;
    case 5: eax5_defer(call, mEax5); break;
    default: eax_fail_unknown_version();
    }
    if(version != mEaxVersion)
        mEaxDf = ~EaxDirtyFlags();
    mEaxVersion = version;
}

void ALCcontext::eax4_context_commit(Eax4State& state, EaxDirtyFlags& dst_df)
{
    if(mEaxDf == EaxDirtyFlags{})
        return;

    eax_context_commit_property<eax_primary_fx_slot_id_dirty_bit>(
        state, dst_df, &EAX40CONTEXTPROPERTIES::guidPrimaryFXSlotID);
    eax_context_commit_property<eax_distance_factor_dirty_bit>(
        state, dst_df, &EAX40CONTEXTPROPERTIES::flDistanceFactor);
    eax_context_commit_property<eax_air_absorption_hf_dirty_bit>(
        state, dst_df, &EAX40CONTEXTPROPERTIES::flAirAbsorptionHF);
    eax_context_commit_property<eax_hf_reference_dirty_bit>(
        state, dst_df, &EAX40CONTEXTPROPERTIES::flHFReference);

    mEaxDf = EaxDirtyFlags{};
}

void ALCcontext::eax5_context_commit(Eax5State& state, EaxDirtyFlags& dst_df)
{
    if(mEaxDf == EaxDirtyFlags{})
        return;

    eax_context_commit_property<eax_primary_fx_slot_id_dirty_bit>(
        state, dst_df, &EAX50CONTEXTPROPERTIES::guidPrimaryFXSlotID);
    eax_context_commit_property<eax_distance_factor_dirty_bit>(
        state, dst_df, &EAX50CONTEXTPROPERTIES::flDistanceFactor);
    eax_context_commit_property<eax_air_absorption_hf_dirty_bit>(
        state, dst_df, &EAX50CONTEXTPROPERTIES::flAirAbsorptionHF);
    eax_context_commit_property<eax_hf_reference_dirty_bit>(
        state, dst_df, &EAX50CONTEXTPROPERTIES::flHFReference);
    eax_context_commit_property<eax_macro_fx_factor_dirty_bit>(
        state, dst_df, &EAX50CONTEXTPROPERTIES::flMacroFXFactor);

    mEaxDf = EaxDirtyFlags{};
}

void ALCcontext::eax_context_commit()
{
    auto dst_df = EaxDirtyFlags{};

    switch(mEaxVersion)
    {
    case 1:
    case 2:
    case 3:
        eax5_context_commit(mEax123, dst_df);
        break;
    case 4:
        eax4_context_commit(mEax4, dst_df);
        break;
    case 5:
        eax5_context_commit(mEax5, dst_df);
        break;
    }

    if(dst_df == EaxDirtyFlags{})
        return;

    if((dst_df & eax_primary_fx_slot_id_dirty_bit) != EaxDirtyFlags{})
        eax_context_commit_primary_fx_slot_id();

    if((dst_df & eax_distance_factor_dirty_bit) != EaxDirtyFlags{})
        eax_context_commit_distance_factor();

    if((dst_df & eax_air_absorption_hf_dirty_bit) != EaxDirtyFlags{})
        eax_context_commit_air_absorbtion_hf();

    if((dst_df & eax_hf_reference_dirty_bit) != EaxDirtyFlags{})
        eax_context_commit_hf_reference();

    if((dst_df & eax_macro_fx_factor_dirty_bit) != EaxDirtyFlags{})
        eax_context_commit_macro_fx_factor();

    if((dst_df & eax_primary_fx_slot_id_dirty_bit) != EaxDirtyFlags{})
        eax_update_sources();
}

void ALCcontext::eaxCommit()
{
    mEaxNeedsCommit = false;
    eax_context_commit();
    eaxCommitFxSlots();
    eax_update_sources();
}


FORCE_ALIGN auto AL_APIENTRY EAXSet(const GUID *property_set_id, ALuint property_id,
    ALuint source_id, ALvoid *value, ALuint value_size) noexcept -> ALenum
{
    auto context = GetContextRef();
    if(!context) UNLIKELY return AL_INVALID_OPERATION;
    return EAXSetDirect(context.get(), property_set_id, property_id, source_id, value, value_size);
}

FORCE_ALIGN auto AL_APIENTRY EAXSetDirect(ALCcontext *context, const GUID *property_set_id,
    ALuint property_id, ALuint source_id, ALvoid *value, ALuint value_size) noexcept -> ALenum
try
{
    std::lock_guard<std::mutex> prop_lock{context->mPropLock};
    return context->eax_eax_set(property_set_id, property_id, source_id, value, value_size);
}
catch(...)
{
    context->eaxSetLastError();
    eax_log_exception(std::data(__func__));
    return AL_INVALID_OPERATION;
}


FORCE_ALIGN auto AL_APIENTRY EAXGet(const GUID *property_set_id, ALuint property_id,
    ALuint source_id, ALvoid *value, ALuint value_size) noexcept -> ALenum
{
    auto context = GetContextRef();
    if(!context) UNLIKELY return AL_INVALID_OPERATION;
    return EAXGetDirect(context.get(), property_set_id, property_id, source_id, value, value_size);
}

FORCE_ALIGN auto AL_APIENTRY EAXGetDirect(ALCcontext *context, const GUID *property_set_id,
    ALuint property_id, ALuint source_id, ALvoid *value, ALuint value_size) noexcept -> ALenum
try
{
    std::lock_guard<std::mutex> prop_lock{context->mPropLock};
    return context->eax_eax_get(property_set_id, property_id, source_id, value, value_size);
}
catch(...)
{
    context->eaxSetLastError();
    eax_log_exception(std::data(__func__));
    return AL_INVALID_OPERATION;
}
#endif // ALSOFT_EAX
