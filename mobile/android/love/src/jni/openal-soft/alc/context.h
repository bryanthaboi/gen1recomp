#ifndef ALC_CONTEXT_H
#define ALC_CONTEXT_H

#include "config.h"

#include <atomic>
#include <bitset>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/alext.h"

#include "al/listener.h"
#include "althreads.h"
#include "core/context.h"
#include "intrusive_ptr.h"
#include "opthelpers.h"

#if ALSOFT_EAX
#include "al/eax/api.h"
#include "al/eax/exception.h"
#include "al/eax/fx_slot_index.h"
#include "al/eax/fx_slots.h"
#include "al/eax/utils.h"

class EaxCall;
#endif // ALSOFT_EAX

struct ALeffect;
struct ALeffectslot;
struct DebugGroup;
struct EffectSlotSubList;
struct SourceSubList;

enum class DebugSource : std::uint8_t;
enum class DebugType : std::uint8_t;
enum class DebugSeverity : std::uint8_t;

using uint = unsigned int;


enum ContextFlags {
    DebugBit = 0, /* ALC_CONTEXT_DEBUG_BIT_EXT */
};
using ContextFlagBitset = std::bitset<sizeof(ALuint)*8>;


struct DebugLogEntry {
    const DebugSource mSource;
    const DebugType mType;
    const DebugSeverity mSeverity;
    const uint mId;

    std::string mMessage;

    template<typename T>
    DebugLogEntry(DebugSource source, DebugType type, uint id, DebugSeverity severity, T&& message)
        : mSource{source}, mType{type}, mSeverity{severity}, mId{id}
        , mMessage{std::forward<T>(message)}
    { }
    DebugLogEntry(const DebugLogEntry&) = default;
    DebugLogEntry(DebugLogEntry&&) = default;
};


struct ALCcontext final : public al::intrusive_ref<ALCcontext>, ContextBase {
    const al::intrusive_ptr<ALCdevice> mALDevice;


    bool mPropsDirty{true};
    bool mDeferUpdates{false};

    std::mutex mPropLock;

    al::tss<ALenum> mLastThreadError{AL_NO_ERROR};

    const ContextFlagBitset mContextFlags;
    std::atomic<bool> mDebugEnabled{false};

    DistanceModel mDistanceModel{DistanceModel::Default};
    bool mSourceDistanceModel{false};

    float mDopplerFactor{1.0f};
    float mDopplerVelocity{1.0f};
    float mSpeedOfSound{SpeedOfSoundMetersPerSec};
    float mAirAbsorptionGainHF{AirAbsorbGainHF};

    std::mutex mEventCbLock;
    ALEVENTPROCSOFT mEventCb{};
    void *mEventParam{nullptr};

    std::mutex mDebugCbLock;
    ALDEBUGPROCEXT mDebugCb{};
    void *mDebugParam{nullptr};
    std::vector<DebugGroup> mDebugGroups;
    std::deque<DebugLogEntry> mDebugLog;

    ALlistener mListener{};

    std::vector<SourceSubList> mSourceList;
    ALuint mNumSources{0};
    std::mutex mSourceLock;

    std::vector<EffectSlotSubList> mEffectSlotList;
    ALuint mNumEffectSlots{0u};
    std::mutex mEffectSlotLock;

    /* Default effect slot */
    std::unique_ptr<ALeffectslot> mDefaultSlot;

    std::vector<std::string_view> mExtensions;
    std::string mExtensionsString{};

    std::unordered_map<ALuint,std::string> mSourceNames;
    std::unordered_map<ALuint,std::string> mEffectSlotNames;

    ALCcontext(al::intrusive_ptr<ALCdevice> device, ContextFlagBitset flags);
    ALCcontext(const ALCcontext&) = delete;
    ALCcontext& operator=(const ALCcontext&) = delete;
    ~ALCcontext() final;

    void init();
    /**
     * Removes the context from its device and removes it from being current on
     * the running thread or globally. Stops device playback if this was the
     * last context on its device.
     */
    void deinit();

    /**
     * Defers/suspends updates for the given context's listener and sources.
     * This does *NOT* stop mixing, but rather prevents certain property
     * changes from taking effect. mPropLock must be held when called.
     */
    void deferUpdates() noexcept { mDeferUpdates = true; }

    /**
     * Resumes update processing after being deferred. mPropLock must be held
     * when called.
     */
    void processUpdates()
    {
        if(std::exchange(mDeferUpdates, false))
            applyAllUpdates();
    }

    /**
     * Applies all pending updates for the context, listener, effect slots, and
     * sources.
     */
    void applyAllUpdates();

#ifdef __MINGW32__
    [[gnu::format(__MINGW_PRINTF_FORMAT, 3, 4)]]
#else
    [[gnu::format(printf, 3, 4)]]
#endif
    void setError(ALenum errorCode, const char *msg, ...);

    void sendDebugMessage(std::unique_lock<std::mutex> &debuglock, DebugSource source,
        DebugType type, ALuint id, DebugSeverity severity, std::string_view message);

    void debugMessage(DebugSource source, DebugType type, ALuint id, DebugSeverity severity,
        std::string_view message)
    {
        if(!mDebugEnabled.load(std::memory_order_relaxed)) LIKELY
            return;
        std::unique_lock<std::mutex> debuglock{mDebugCbLock};
        sendDebugMessage(debuglock, source, type, id, severity, message);
    }

    /* Process-wide current context */
    static std::atomic<bool> sGlobalContextLock;
    static std::atomic<ALCcontext*> sGlobalContext;

private:
    /* Thread-local current context. */
    static inline thread_local ALCcontext *sLocalContext{};

    /* Thread-local context handling. This handles attempting to release the
     * context which may have been left current when the thread is destroyed.
     */
    class ThreadCtx {
    public:
        ThreadCtx() = default;
        ThreadCtx(const ThreadCtx&) = delete;
        auto operator=(const ThreadCtx&) -> ThreadCtx& = delete;

        ~ThreadCtx();
        /* NOLINTBEGIN(readability-convert-member-functions-to-static)
         * This should be non-static to invoke construction of the thread-local
         * sThreadContext, so that it's destructor gets run at thread exit to
         * clear sLocalContext (which isn't a member variable to make read
         * access efficient).
         */
        void set(ALCcontext *ctx) const noexcept { sLocalContext = ctx; }
        /* NOLINTEND(readability-convert-member-functions-to-static) */
    };
    static thread_local ThreadCtx sThreadContext;

public:
    static ALCcontext *getThreadContext() noexcept { return sLocalContext; }
    static void setThreadContext(ALCcontext *context) noexcept { sThreadContext.set(context); }

    /* Default effect that applies to sources that don't have an effect on send 0. */
    static ALeffect sDefaultEffect;

#if ALSOFT_EAX
    bool hasEax() const noexcept { return mEaxIsInitialized; }
    bool eaxIsCapable() const noexcept;

    void eaxUninitialize() noexcept;

    ALenum eax_eax_set(
        const GUID* property_set_id,
        ALuint property_id,
        ALuint property_source_id,
        ALvoid* property_value,
        ALuint property_value_size);

    ALenum eax_eax_get(
        const GUID* property_set_id,
        ALuint property_id,
        ALuint property_source_id,
        ALvoid* property_value,
        ALuint property_value_size);

    void eaxSetLastError() noexcept;

    [[nodiscard]]
    auto eaxGetDistanceFactor() const noexcept -> float { return mEax.flDistanceFactor; }

    [[nodiscard]]
    auto eaxGetPrimaryFxSlotIndex() const noexcept -> EaxFxSlotIndex
    { return mEaxPrimaryFxSlotIndex; }

    const ALeffectslot& eaxGetFxSlot(EaxFxSlotIndexValue fx_slot_index) const
    { return mEaxFxSlots.get(fx_slot_index); }
    ALeffectslot& eaxGetFxSlot(EaxFxSlotIndexValue fx_slot_index)
    { return mEaxFxSlots.get(fx_slot_index); }

    bool eaxNeedsCommit() const noexcept { return mEaxNeedsCommit; }
    void eaxCommit();

    void eaxCommitFxSlots()
    { mEaxFxSlots.commit(); }

private:
    static constexpr auto eax_primary_fx_slot_id_dirty_bit = EaxDirtyFlags{1} << 0;
    static constexpr auto eax_distance_factor_dirty_bit = EaxDirtyFlags{1} << 1;
    static constexpr auto eax_air_absorption_hf_dirty_bit = EaxDirtyFlags{1} << 2;
    static constexpr auto eax_hf_reference_dirty_bit = EaxDirtyFlags{1} << 3;
    static constexpr auto eax_macro_fx_factor_dirty_bit = EaxDirtyFlags{1} << 4;

    using Eax4Props = EAX40CONTEXTPROPERTIES;

    struct Eax4State {
        Eax4Props i; // Immediate.
        Eax4Props d; // Deferred.
    };

    using Eax5Props = EAX50CONTEXTPROPERTIES;

    struct Eax5State {
        Eax5Props i; // Immediate.
        Eax5Props d; // Deferred.
    };

    class ContextException final : public EaxException {
    public:
        explicit ContextException(const char *message)
            : EaxException{"EAX_CONTEXT", message}
        { }
    };

    struct Eax4PrimaryFxSlotIdValidator {
        void operator()(const GUID& guidPrimaryFXSlotID) const
        {
            if(guidPrimaryFXSlotID != EAX_NULL_GUID &&
                guidPrimaryFXSlotID != EAXPROPERTYID_EAX40_FXSlot0 &&
                guidPrimaryFXSlotID != EAXPROPERTYID_EAX40_FXSlot1 &&
                guidPrimaryFXSlotID != EAXPROPERTYID_EAX40_FXSlot2 &&
                guidPrimaryFXSlotID != EAXPROPERTYID_EAX40_FXSlot3)
            {
                eax_fail_unknown_primary_fx_slot_id();
            }
        }
    };

    struct Eax4DistanceFactorValidator {
        void operator()(float flDistanceFactor) const
        {
            eax_validate_range<ContextException>(
                "Distance Factor",
                flDistanceFactor,
                EAXCONTEXT_MINDISTANCEFACTOR,
                EAXCONTEXT_MAXDISTANCEFACTOR);
        }
    };

    struct Eax4AirAbsorptionHfValidator {
        void operator()(float flAirAbsorptionHF) const
        {
            eax_validate_range<ContextException>(
                "Air Absorption HF",
                flAirAbsorptionHF,
                EAXCONTEXT_MINAIRABSORPTIONHF,
                EAXCONTEXT_MAXAIRABSORPTIONHF);
        }
    };

    struct Eax4HfReferenceValidator {
        void operator()(float flHFReference) const
        {
            eax_validate_range<ContextException>(
                "HF Reference",
                flHFReference,
                EAXCONTEXT_MINHFREFERENCE,
                EAXCONTEXT_MAXHFREFERENCE);
        }
    };

    struct Eax4AllValidator {
        void operator()(const EAX40CONTEXTPROPERTIES& all) const
        {
            Eax4PrimaryFxSlotIdValidator{}(all.guidPrimaryFXSlotID);
            Eax4DistanceFactorValidator{}(all.flDistanceFactor);
            Eax4AirAbsorptionHfValidator{}(all.flAirAbsorptionHF);
            Eax4HfReferenceValidator{}(all.flHFReference);
        }
    };

    struct Eax5PrimaryFxSlotIdValidator {
        void operator()(const GUID& guidPrimaryFXSlotID) const
        {
            if(guidPrimaryFXSlotID != EAX_NULL_GUID &&
                guidPrimaryFXSlotID != EAXPROPERTYID_EAX50_FXSlot0 &&
                guidPrimaryFXSlotID != EAXPROPERTYID_EAX50_FXSlot1 &&
                guidPrimaryFXSlotID != EAXPROPERTYID_EAX50_FXSlot2 &&
                guidPrimaryFXSlotID != EAXPROPERTYID_EAX50_FXSlot3)
            {
                eax_fail_unknown_primary_fx_slot_id();
            }
        }
    };

    struct Eax5MacroFxFactorValidator {
        void operator()(float flMacroFXFactor) const
        {
            eax_validate_range<ContextException>(
                "Macro FX Factor",
                flMacroFXFactor,
                EAXCONTEXT_MINMACROFXFACTOR,
                EAXCONTEXT_MAXMACROFXFACTOR);
        }
    };

    struct Eax5AllValidator {
        void operator()(const EAX50CONTEXTPROPERTIES& all) const
        {
            Eax5PrimaryFxSlotIdValidator{}(all.guidPrimaryFXSlotID);
            Eax4DistanceFactorValidator{}(all.flDistanceFactor);
            Eax4AirAbsorptionHfValidator{}(all.flAirAbsorptionHF);
            Eax4HfReferenceValidator{}(all.flHFReference);
            Eax5MacroFxFactorValidator{}(all.flMacroFXFactor);
        }
    };

    struct Eax5EaxVersionValidator {
        void operator()(unsigned long ulEAXVersion) const
        {
            eax_validate_range<ContextException>(
                "EAX version",
                ulEAXVersion,
                EAXCONTEXT_MINEAXSESSION,
                EAXCONTEXT_MAXEAXSESSION);
        }
    };

    struct Eax5MaxActiveSendsValidator {
        void operator()(unsigned long ulMaxActiveSends) const
        {
            eax_validate_range<ContextException>(
                "Max Active Sends",
                ulMaxActiveSends,
                EAXCONTEXT_MINMAXACTIVESENDS,
                EAXCONTEXT_MAXMAXACTIVESENDS);
        }
    };

    struct Eax5SessionAllValidator {
        void operator()(const EAXSESSIONPROPERTIES& all) const
        {
            Eax5EaxVersionValidator{}(all.ulEAXVersion);
            Eax5MaxActiveSendsValidator{}(all.ulMaxActiveSends);
        }
    };

    struct Eax5SpeakerConfigValidator {
        void operator()(unsigned long ulSpeakerConfig) const
        {
            eax_validate_range<ContextException>(
                "Speaker Config",
                ulSpeakerConfig,
                EAXCONTEXT_MINSPEAKERCONFIG,
                EAXCONTEXT_MAXSPEAKERCONFIG);
        }
    };

    bool mEaxIsInitialized{};
    bool mEaxIsTried{};

    long mEaxLastError{};
    unsigned long mEaxSpeakerConfig{};

    EaxFxSlotIndex mEaxPrimaryFxSlotIndex{};
    EaxFxSlots mEaxFxSlots{};

    int mEaxVersion{}; // Current EAX version.
    bool mEaxNeedsCommit{};
    EaxDirtyFlags mEaxDf{}; // Dirty flags for the current EAX version.
    Eax5State mEax123{}; // EAX1/EAX2/EAX3 state.
    Eax4State mEax4{}; // EAX4 state.
    Eax5State mEax5{}; // EAX5 state.
    Eax5Props mEax{}; // Current EAX state.
    EAXSESSIONPROPERTIES mEaxSession{};

    [[noreturn]] static void eax_fail(const char* message);
    [[noreturn]] static void eax_fail_unknown_property_set_id();
    [[noreturn]] static void eax_fail_unknown_primary_fx_slot_id();
    [[noreturn]] static void eax_fail_unknown_property_id();
    [[noreturn]] static void eax_fail_unknown_version();

    // Gets a value from EAX call,
    // validates it,
    // and updates the current value.
    template<typename TValidator, typename TProperty>
    static void eax_set(const EaxCall& call, TProperty& property)
    {
        const auto& value = call.get_value<ContextException, const TProperty>();
        TValidator{}(value);
        property = value;
    }

    // Gets a new value from EAX call,
    // validates it,
    // updates the deferred value,
    // updates a dirty flag.
    template<
        typename TValidator,
        EaxDirtyFlags TDirtyBit,
        typename TMemberResult,
        typename TProps,
        typename TState>
    void eax_defer(const EaxCall& call, TState& state, TMemberResult TProps::*member)
    {
        const auto& src = call.get_value<ContextException, const TMemberResult>();
        TValidator{}(src);
        const auto& dst_i = state.i.*member;
        auto& dst_d = state.d.*member;
        dst_d = src;

        if(dst_i != dst_d)
            mEaxDf |= TDirtyBit;
    }

    template<
        EaxDirtyFlags TDirtyBit,
        typename TMemberResult,
        typename TProps,
        typename TState>
    void eax_context_commit_property(TState& state, EaxDirtyFlags& dst_df,
        TMemberResult TProps::*member) noexcept
    {
        if((mEaxDf & TDirtyBit) != EaxDirtyFlags{})
        {
            dst_df |= TDirtyBit;
            const auto& src_d = state.d.*member;
            state.i.*member = src_d;
            mEax.*member = src_d;
        }
    }

    void eax_initialize_extensions();
    void eax_initialize();

    bool eax_has_no_default_effect_slot() const noexcept;
    void eax_ensure_no_default_effect_slot() const;
    bool eax_has_enough_aux_sends() const noexcept;
    void eax_ensure_enough_aux_sends() const;
    void eax_ensure_compatibility();

    unsigned long eax_detect_speaker_configuration() const;
    void eax_update_speaker_configuration();

    void eax_set_last_error_defaults() noexcept;
    void eax_session_set_defaults() noexcept;
    static void eax4_context_set_defaults(Eax4Props& props) noexcept;
    static void eax4_context_set_defaults(Eax4State& state) noexcept;
    static void eax5_context_set_defaults(Eax5Props& props) noexcept;
    static void eax5_context_set_defaults(Eax5State& state) noexcept;
    void eax_context_set_defaults();
    void eax_set_defaults();

    void eax_dispatch_fx_slot(const EaxCall& call);
    void eax_dispatch_source(const EaxCall& call);

    void eax_get_misc(const EaxCall& call);
    void eax4_get(const EaxCall& call, const Eax4Props& props);
    void eax5_get(const EaxCall& call, const Eax5Props& props);
    void eax_get(const EaxCall& call);

    void eax_context_commit_primary_fx_slot_id();
    void eax_context_commit_distance_factor();
    void eax_context_commit_air_absorbtion_hf();
    void eax_context_commit_hf_reference();
    void eax_context_commit_macro_fx_factor();

    void eax_initialize_fx_slots();

    void eax_update_sources();

    void eax_set_misc(const EaxCall& call);
    void eax4_defer_all(const EaxCall& call, Eax4State& state);
    void eax4_defer(const EaxCall& call, Eax4State& state);
    void eax5_defer_all(const EaxCall& call, Eax5State& state);
    void eax5_defer(const EaxCall& call, Eax5State& state);
    void eax_set(const EaxCall& call);

    void eax4_context_commit(Eax4State& state, EaxDirtyFlags& dst_df);
    void eax5_context_commit(Eax5State& state, EaxDirtyFlags& dst_df);
    void eax_context_commit();
#endif // ALSOFT_EAX
};

using ContextRef = al::intrusive_ptr<ALCcontext>;

ContextRef GetContextRef() noexcept;

void UpdateContextProps(ALCcontext *context);


inline bool TrapALError{false};


#if ALSOFT_EAX
auto AL_APIENTRY EAXSet(const GUID *property_set_id, ALuint property_id,
    ALuint source_id, ALvoid *value, ALuint value_size) noexcept -> ALenum;

auto AL_APIENTRY EAXGet(const GUID *property_set_id, ALuint property_id,
    ALuint source_id, ALvoid *value, ALuint value_size) noexcept -> ALenum;
#endif // ALSOFT_EAX

#endif /* ALC_CONTEXT_H */
