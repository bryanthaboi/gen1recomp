#ifndef EAX_EAX_CALL_INCLUDED
#define EAX_EAX_CALL_INCLUDED

#include "AL/al.h"
#include "alnumeric.h"
#include "alspan.h"
#include "api.h"
#include "fx_slot_index.h"

enum class EaxCallType {
    none,
    get,
    set,
}; // EaxCallType

enum class EaxCallPropertySetId {
    none,
    context,
    fx_slot,
    source,
    fx_slot_effect,
}; // EaxCallPropertySetId

class EaxCall {
public:
    EaxCall(
        EaxCallType type,
        const GUID& property_set_guid,
        ALuint property_id,
        ALuint property_source_id,
        ALvoid* property_buffer,
        ALuint property_size);

    [[nodiscard]] auto is_get() const noexcept -> bool { return mCallType == EaxCallType::get; }
    [[nodiscard]] auto is_deferred() const noexcept -> bool { return mIsDeferred; }
    [[nodiscard]] auto get_version() const noexcept -> int { return mVersion; }
    [[nodiscard]] auto get_property_set_id() const noexcept -> EaxCallPropertySetId { return mPropertySetId; }
    [[nodiscard]] auto get_property_id() const noexcept -> ALuint { return mPropertyId; }
    [[nodiscard]] auto get_property_al_name() const noexcept -> ALuint { return mPropertySourceId; }
    [[nodiscard]] auto get_fx_slot_index() const noexcept -> EaxFxSlotIndex { return mFxSlotIndex; }

    template<typename TException, typename TValue>
    [[nodiscard]] auto get_value() const -> TValue&
    {
        if(mPropertyBufferSize < sizeof(TValue))
            fail_too_small();

        return *static_cast<TValue*>(mPropertyBuffer);
    }

    template<typename TValue>
    [[nodiscard]] auto get_values(size_t max_count) const -> al::span<TValue>
    {
        if(max_count == 0 || mPropertyBufferSize < sizeof(TValue))
            fail_too_small();

        const auto count = std::min(mPropertyBufferSize/sizeof(TValue), max_count);
        return {static_cast<TValue*>(mPropertyBuffer), count};
    }

    template<typename TValue>
    [[nodiscard]] auto get_values() const -> al::span<TValue>
    {
        return get_values<TValue>(~0_uz);
    }

    template<typename TException, typename TValue>
    auto set_value(const TValue& value) const -> void
    {
        get_value<TException, TValue>() = value;
    }

private:
    const EaxCallType mCallType;
    int mVersion{};
    EaxFxSlotIndex mFxSlotIndex{};
    EaxCallPropertySetId mPropertySetId{EaxCallPropertySetId::none};
    bool mIsDeferred;

    const ALuint mPropertyId;
    const ALuint mPropertySourceId;
    ALvoid*const mPropertyBuffer;
    const ALuint mPropertyBufferSize;

    [[noreturn]] static void fail(const char* message);
    [[noreturn]] static void fail_too_small();
}; // EaxCall

EaxCall create_eax_call(
    EaxCallType type,
    const GUID* property_set_id,
    ALuint property_id,
    ALuint property_source_id,
    ALvoid* property_buffer,
    ALuint property_size);

#endif // !EAX_EAX_CALL_INCLUDED
