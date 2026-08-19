#ifndef AL_AUXEFFECTSLOT_H
#define AL_AUXEFFECTSLOT_H

#include "config.h"

#include <array>
#include <atomic>
#include <cstdint>
#include <string_view>
#include <utility>

#include "AL/al.h"
#include "AL/alc.h"

#include "almalloc.h"
#include "alnumeric.h"
#include "core/effects/base.h"
#include "core/effectslot.h"
#include "intrusive_ptr.h"

#if ALSOFT_EAX
#include <memory>
#include "eax/api.h"
#include "eax/call.h"
#include "eax/effect.h"
#include "eax/exception.h"
#include "eax/fx_slot_index.h"
#include "eax/utils.h"
#endif // ALSOFT_EAX

struct ALbuffer;

#if ALSOFT_EAX
class EaxFxSlotException : public EaxException {
public:
	explicit EaxFxSlotException(const char* message)
		: EaxException{"EAX_FX_SLOT", message}
	{}
};
#endif // ALSOFT_EAX

enum class SlotState : bool {
    Initial, Playing,
};

struct ALeffectslot {
    ALuint EffectId{};
    float Gain{1.0f};
    bool  AuxSendAuto{true};
    ALeffectslot *Target{nullptr};
    ALbuffer *Buffer{nullptr};

    struct EffectData {
        EffectSlotType Type{EffectSlotType::None};
        EffectProps Props{};

        al::intrusive_ptr<EffectState> State;
    };
    EffectData Effect;

    bool mPropsDirty{true};

    SlotState mState{SlotState::Initial};

    std::atomic<ALuint> ref{0u};

    EffectSlot *mSlot{nullptr};

    /* Self ID */
    ALuint id{};

    ALeffectslot(ALCcontext *context);
    ALeffectslot(const ALeffectslot&) = delete;
    ALeffectslot& operator=(const ALeffectslot&) = delete;
    ~ALeffectslot();

    ALenum initEffect(ALuint effectId, ALenum effectType, const EffectProps &effectProps,
        ALCcontext *context);
    void updateProps(ALCcontext *context) const;

    static void SetName(ALCcontext *context, ALuint id, std::string_view name);


#if ALSOFT_EAX
public:
    void eax_initialize(ALCcontext& al_context, EaxFxSlotIndexValue index);

    [[nodiscard]] auto eax_get_index() const noexcept -> EaxFxSlotIndexValue { return eax_fx_slot_index_; }
    [[nodiscard]] auto eax_get_eax_fx_slot() const noexcept -> const EAX50FXSLOTPROPERTIES&
    { return eax_; }

    // Returns `true` if all sources should be updated, or `false` otherwise.
    [[nodiscard]] auto eax_dispatch(const EaxCall& call) -> bool
    { return call.is_get() ? eax_get(call) : eax_set(call); }

    void eax_commit();

private:
    static constexpr auto eax_load_effect_dirty_bit = EaxDirtyFlags{1} << 0;
    static constexpr auto eax_volume_dirty_bit = EaxDirtyFlags{1} << 1;
    static constexpr auto eax_lock_dirty_bit = EaxDirtyFlags{1} << 2;
    static constexpr auto eax_flags_dirty_bit = EaxDirtyFlags{1} << 3;
    static constexpr auto eax_occlusion_dirty_bit = EaxDirtyFlags{1} << 4;
    static constexpr auto eax_occlusion_lf_ratio_dirty_bit = EaxDirtyFlags{1} << 5;

    using Exception = EaxFxSlotException;

    using Eax4Props = EAX40FXSLOTPROPERTIES;

    struct Eax4State {
        Eax4Props i; // Immediate.
    };

    using Eax5Props = EAX50FXSLOTPROPERTIES;

    struct Eax5State {
        Eax5Props i; // Immediate.
    };

    struct EaxRangeValidator {
        template<typename TValue>
        void operator()(
            const char* name,
            const TValue& value,
            const TValue& min_value,
            const TValue& max_value) const
        {
            eax_validate_range<Exception>(name, value, min_value, max_value);
        }
    };

    struct Eax4GuidLoadEffectValidator {
        void operator()(const GUID& guidLoadEffect) const
        {
            if (guidLoadEffect != EAX_NULL_GUID &&
                guidLoadEffect != EAX_REVERB_EFFECT &&
                guidLoadEffect != EAX_AGCCOMPRESSOR_EFFECT &&
                guidLoadEffect != EAX_AUTOWAH_EFFECT &&
                guidLoadEffect != EAX_CHORUS_EFFECT &&
                guidLoadEffect != EAX_DISTORTION_EFFECT &&
                guidLoadEffect != EAX_ECHO_EFFECT &&
                guidLoadEffect != EAX_EQUALIZER_EFFECT &&
                guidLoadEffect != EAX_FLANGER_EFFECT &&
                guidLoadEffect != EAX_FREQUENCYSHIFTER_EFFECT &&
                guidLoadEffect != EAX_VOCALMORPHER_EFFECT &&
                guidLoadEffect != EAX_PITCHSHIFTER_EFFECT &&
                guidLoadEffect != EAX_RINGMODULATOR_EFFECT)
            {
                eax_fail_unknown_effect_id();
            }
        }
    };

    struct Eax4VolumeValidator {
        void operator()(long lVolume) const
        {
            EaxRangeValidator{}(
                "Volume",
                lVolume,
                EAXFXSLOT_MINVOLUME,
                EAXFXSLOT_MAXVOLUME);
        }
    };

    struct Eax4LockValidator {
        void operator()(long lLock) const
        {
            EaxRangeValidator{}(
                "Lock",
                lLock,
                EAXFXSLOT_MINLOCK,
                EAXFXSLOT_MAXLOCK);
        }
    };

    struct Eax4FlagsValidator {
        void operator()(unsigned long ulFlags) const
        {
            EaxRangeValidator{}(
                "Flags",
                ulFlags,
                0UL,
                ~EAX40FXSLOTFLAGS_RESERVED);
        }
    };

    struct Eax4AllValidator {
        void operator()(const EAX40FXSLOTPROPERTIES& all) const
        {
            Eax4GuidLoadEffectValidator{}(all.guidLoadEffect);
            Eax4VolumeValidator{}(all.lVolume);
            Eax4LockValidator{}(all.lLock);
            Eax4FlagsValidator{}(all.ulFlags);
        }
    };

    struct Eax5FlagsValidator {
        void operator()(unsigned long ulFlags) const
        {
            EaxRangeValidator{}(
                "Flags",
                ulFlags,
                0UL,
                ~EAX50FXSLOTFLAGS_RESERVED);
        }
    };

    struct Eax5OcclusionValidator {
        void operator()(long lOcclusion) const
        {
            EaxRangeValidator{}(
                "Occlusion",
                lOcclusion,
                EAXFXSLOT_MINOCCLUSION,
                EAXFXSLOT_MAXOCCLUSION);
        }
    };

    struct Eax5OcclusionLfRatioValidator {
        void operator()(float flOcclusionLFRatio) const
        {
            EaxRangeValidator{}(
                "Occlusion LF Ratio",
                flOcclusionLFRatio,
                EAXFXSLOT_MINOCCLUSIONLFRATIO,
                EAXFXSLOT_MAXOCCLUSIONLFRATIO);
        }
    };

    struct Eax5AllValidator {
        void operator()(const EAX50FXSLOTPROPERTIES& all) const
        {
            Eax4GuidLoadEffectValidator{}(all.guidLoadEffect);
            Eax4VolumeValidator{}(all.lVolume);
            Eax4LockValidator{}(all.lLock);
            Eax5FlagsValidator{}(all.ulFlags);
            Eax5OcclusionValidator{}(all.lOcclusion);
            Eax5OcclusionLfRatioValidator{}(all.flOcclusionLFRatio);
        }
    };

    ALCcontext* eax_al_context_{};
    EaxFxSlotIndexValue eax_fx_slot_index_{};
    int eax_version_{}; // Current EAX version.
    EaxDirtyFlags eax_df_{}; // Dirty flags for the current EAX version.
    EaxEffectUPtr eax_effect_{};
    Eax5State eax123_{}; // EAX1/EAX2/EAX3 state.
    Eax4State eax4_{}; // EAX4 state.
    Eax5State eax5_{}; // EAX5 state.
    Eax5Props eax_{}; // Current EAX state.

    [[noreturn]] static void eax_fail(const char* message);
    [[noreturn]] static void eax_fail_unknown_effect_id();
    [[noreturn]] static void eax_fail_unknown_property_id();
    [[noreturn]] static void eax_fail_unknown_version();

    // Gets a new value from EAX call,
    // validates it,
    // sets a dirty flag only if the new value differs form the old one,
    // and assigns the new value.
    template<typename TValidator, EaxDirtyFlags TDirtyBit, typename TProperties>
    static void eax_fx_slot_set(const EaxCall& call, TProperties& dst, EaxDirtyFlags& dirty_flags)
    {
        const auto& src = call.get_value<Exception, const TProperties>();
        TValidator{}(src);
        dirty_flags |= (dst != src ? TDirtyBit : EaxDirtyFlags{});
        dst = src;
    }

    // Gets a new value from EAX call,
    // validates it,
    // sets a dirty flag without comparing the values,
    // and assigns the new value.
    template<typename TValidator, EaxDirtyFlags TDirtyBit, typename TProperties>
    static void eax_fx_slot_set_dirty(const EaxCall& call, TProperties& dst,
        EaxDirtyFlags& dirty_flags)
    {
        const auto& src = call.get_value<Exception, const TProperties>();
        TValidator{}(src);
        dirty_flags |= TDirtyBit;
        dst = src;
    }

    [[nodiscard]] constexpr auto eax4_fx_slot_is_legacy() const noexcept -> bool
    { return eax_fx_slot_index_ < 2; }

    void eax4_fx_slot_ensure_unlocked() const;

    [[nodiscard]] static auto eax_get_efx_effect_type(const GUID& guid) -> ALenum;
    [[nodiscard]] auto eax_get_eax_default_effect_guid() const noexcept -> const GUID&;
    [[nodiscard]] auto eax_get_eax_default_lock() const noexcept -> long;

    void eax4_fx_slot_set_defaults(Eax4Props& props) noexcept;
    void eax5_fx_slot_set_defaults(Eax5Props& props) noexcept;
    void eax4_fx_slot_set_current_defaults(const Eax4Props& props) noexcept;
    void eax5_fx_slot_set_current_defaults(const Eax5Props& props) noexcept;
    void eax_fx_slot_set_current_defaults();
    void eax_fx_slot_set_defaults();

    static void eax4_fx_slot_get(const EaxCall& call, const Eax4Props& props);
    static void eax5_fx_slot_get(const EaxCall& call, const Eax5Props& props);
    void eax_fx_slot_get(const EaxCall& call) const;
    // Returns `true` if all sources should be updated, or `false` otherwise.
    bool eax_get(const EaxCall& call);

    void eax_fx_slot_load_effect(int version, ALenum altype);
    void eax_fx_slot_set_volume();
    void eax_fx_slot_set_environment_flag();
    void eax_fx_slot_set_flags();

    void eax4_fx_slot_set_all(const EaxCall& call);
    void eax5_fx_slot_set_all(const EaxCall& call);

    [[nodiscard]] auto eax_fx_slot_should_update_sources() const noexcept -> bool;

    // Returns `true` if all sources should be updated, or `false` otherwise.
    bool eax4_fx_slot_set(const EaxCall& call);
    // Returns `true` if all sources should be updated, or `false` otherwise.
    bool eax5_fx_slot_set(const EaxCall& call);
    // Returns `true` if all sources should be updated, or `false` otherwise.
    bool eax_fx_slot_set(const EaxCall& call);
    // Returns `true` if all sources should be updated, or `false` otherwise.
    bool eax_set(const EaxCall& call);

    template<
        EaxDirtyFlags TDirtyBit,
        typename TMemberResult,
        typename TProps,
        typename TState>
    void eax_fx_slot_commit_property(TState& state, EaxDirtyFlags& dst_df,
        TMemberResult TProps::*member) noexcept
    {
        auto& src_i = state.i;
        auto& dst_i = eax_;

        if((eax_df_ & TDirtyBit) != EaxDirtyFlags{})
        {
            dst_df |= TDirtyBit;
            dst_i.*member = src_i.*member;
        }
    }

    void eax4_fx_slot_commit(EaxDirtyFlags& dst_df);
    void eax5_fx_slot_commit(Eax5State& state, EaxDirtyFlags& dst_df);

    // `alAuxiliaryEffectSloti(effect_slot, AL_EFFECTSLOT_EFFECT, effect)`
    void eax_set_efx_slot_effect(EaxEffect &effect);

    // `alAuxiliaryEffectSloti(effect_slot, AL_EFFECTSLOT_AUXILIARY_SEND_AUTO, value)`
    void eax_set_efx_slot_send_auto(bool is_send_auto);

    // `alAuxiliaryEffectSlotf(effect_slot, AL_EFFECTSLOT_GAIN, gain)`
    void eax_set_efx_slot_gain(ALfloat gain);

public:
    class EaxDeleter {
    public:
        void operator()(ALeffectslot *effect_slot);
    };
#endif // ALSOFT_EAX
};

void UpdateAllEffectSlotProps(ALCcontext *context);

#if ALSOFT_EAX
using EaxAlEffectSlotUPtr = std::unique_ptr<ALeffectslot, ALeffectslot::EaxDeleter>;

EaxAlEffectSlotUPtr eax_create_al_effect_slot(ALCcontext& context);
void eax_delete_al_effect_slot(ALCcontext& context, ALeffectslot& effect_slot);
#endif // ALSOFT_EAX

struct EffectSlotSubList {
    uint64_t FreeMask{~0_u64};
    gsl::owner<std::array<ALeffectslot,64>*> EffectSlots{nullptr};

    EffectSlotSubList() noexcept = default;
    EffectSlotSubList(const EffectSlotSubList&) = delete;
    EffectSlotSubList(EffectSlotSubList&& rhs) noexcept
      : FreeMask{rhs.FreeMask}, EffectSlots{rhs.EffectSlots}
    { rhs.FreeMask = ~0_u64; rhs.EffectSlots = nullptr; }
    ~EffectSlotSubList();

    EffectSlotSubList& operator=(const EffectSlotSubList&) = delete;
    EffectSlotSubList& operator=(EffectSlotSubList&& rhs) noexcept
    { std::swap(FreeMask, rhs.FreeMask); std::swap(EffectSlots, rhs.EffectSlots); return *this; }
};

#endif
