#include "config.h"
#include "call.h"
#include "exception.h"

namespace {

constexpr auto deferred_flag = 0x80000000U;

class EaxCallException : public EaxException {
public:
    explicit EaxCallException(const char* message)
        : EaxException{"EAX_CALL", message}
    {}
}; // EaxCallException

} // namespace

EaxCall::EaxCall(EaxCallType type, const GUID &property_set_guid, ALuint property_id,
    ALuint property_source_id, ALvoid *property_buffer, ALuint property_size)
    : mCallType{type}, mIsDeferred{(property_id & deferred_flag) != 0}
    , mPropertyId{property_id & ~deferred_flag}, mPropertySourceId{property_source_id}
    , mPropertyBuffer{property_buffer}, mPropertyBufferSize{property_size}
{
    switch(mCallType)
    {
        case EaxCallType::get:
        case EaxCallType::set:
            break;

        default:
            fail("Invalid type.");
    }

    if (false)
    {
    }
    else if (property_set_guid == EAXPROPERTYID_EAX40_Context)
    {
        mVersion = 4;
        mPropertySetId = EaxCallPropertySetId::context;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX50_Context)
    {
        mVersion = 5;
        mPropertySetId = EaxCallPropertySetId::context;
    }
    else if (property_set_guid == DSPROPSETID_EAX20_ListenerProperties)
    {
        mVersion = 2;
        mFxSlotIndex = 0u;
        mPropertySetId = EaxCallPropertySetId::fx_slot_effect;
    }
    else if (property_set_guid == DSPROPSETID_EAX30_ListenerProperties)
    {
        mVersion = 3;
        mFxSlotIndex = 0u;
        mPropertySetId = EaxCallPropertySetId::fx_slot_effect;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX40_FXSlot0)
    {
        mVersion = 4;
        mFxSlotIndex = 0u;
        mPropertySetId = EaxCallPropertySetId::fx_slot;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX50_FXSlot0)
    {
        mVersion = 5;
        mFxSlotIndex = 0u;
        mPropertySetId = EaxCallPropertySetId::fx_slot;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX40_FXSlot1)
    {
        mVersion = 4;
        mFxSlotIndex = 1u;
        mPropertySetId = EaxCallPropertySetId::fx_slot;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX50_FXSlot1)
    {
        mVersion = 5;
        mFxSlotIndex = 1u;
        mPropertySetId = EaxCallPropertySetId::fx_slot;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX40_FXSlot2)
    {
        mVersion = 4;
        mFxSlotIndex = 2u;
        mPropertySetId = EaxCallPropertySetId::fx_slot;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX50_FXSlot2)
    {
        mVersion = 5;
        mFxSlotIndex = 2u;
        mPropertySetId = EaxCallPropertySetId::fx_slot;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX40_FXSlot3)
    {
        mVersion = 4;
        mFxSlotIndex = 3u;
        mPropertySetId = EaxCallPropertySetId::fx_slot;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX50_FXSlot3)
    {
        mVersion = 5;
        mFxSlotIndex = 3u;
        mPropertySetId = EaxCallPropertySetId::fx_slot;
    }
    else if (property_set_guid == DSPROPSETID_EAX20_BufferProperties)
    {
        mVersion = 2;
        mPropertySetId = EaxCallPropertySetId::source;
    }
    else if (property_set_guid == DSPROPSETID_EAX30_BufferProperties)
    {
        mVersion = 3;
        mPropertySetId = EaxCallPropertySetId::source;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX40_Source)
    {
        mVersion = 4;
        mPropertySetId = EaxCallPropertySetId::source;
    }
    else if (property_set_guid == EAXPROPERTYID_EAX50_Source)
    {
        mVersion = 5;
        mPropertySetId = EaxCallPropertySetId::source;
    }
    else if (property_set_guid == DSPROPSETID_EAX_ReverbProperties)
    {
        mVersion = 1;
        mFxSlotIndex = 0u;
        mPropertySetId = EaxCallPropertySetId::fx_slot_effect;
    }
    else if (property_set_guid == DSPROPSETID_EAXBUFFER_ReverbProperties)
    {
        mVersion = 1;
        mPropertySetId = EaxCallPropertySetId::source;
    }
    else
    {
        fail("Unsupported property set id.");
    }

    if(mPropertySetId == EaxCallPropertySetId::context)
    {
        switch(mPropertyId)
        {
        case EAXCONTEXT_LASTERROR:
        case EAXCONTEXT_SPEAKERCONFIG:
        case EAXCONTEXT_EAXSESSION:
            // EAX allow to set "defer" flag on immediate-only properties.
            // If we don't clear our flag then "applyAllUpdates" in EAX context won't be called.
            mIsDeferred = false;
            break;
        }
    }
    else if(mPropertySetId == EaxCallPropertySetId::fx_slot)
    {
        switch(mPropertyId)
        {
        case EAXFXSLOT_NONE:
        case EAXFXSLOT_ALLPARAMETERS:
        case EAXFXSLOT_LOADEFFECT:
        case EAXFXSLOT_VOLUME:
        case EAXFXSLOT_LOCK:
        case EAXFXSLOT_FLAGS:
        case EAXFXSLOT_OCCLUSION:
        case EAXFXSLOT_OCCLUSIONLFRATIO:
            mIsDeferred = false;
            break;
        }
    }

    if(!mIsDeferred)
    {
        if(mPropertySetId != EaxCallPropertySetId::fx_slot && mPropertyId != 0)
        {
            if(mPropertyBuffer == nullptr)
                fail("Null property buffer.");

            if(mPropertyBufferSize == 0)
                fail("Empty property.");
        }
    }

    if(mPropertySetId == EaxCallPropertySetId::source && mPropertySourceId == 0)
        fail("Null AL source id.");

    if(mPropertySetId == EaxCallPropertySetId::fx_slot)
    {
        if(mPropertyId < EAXFXSLOT_NONE)
            mPropertySetId = EaxCallPropertySetId::fx_slot_effect;
    }
}

[[noreturn]] void EaxCall::fail(const char* message)
{
    throw EaxCallException{message};
}

[[noreturn]] void EaxCall::fail_too_small()
{
    fail("Property buffer too small.");
}

EaxCall create_eax_call(
    EaxCallType type,
    const GUID* property_set_id,
    ALuint property_id,
    ALuint property_source_id,
    ALvoid* property_buffer,
    ALuint property_size)
{
    if(!property_set_id)
        throw EaxCallException{"Null property set ID."};

    return EaxCall{
        type,
        *property_set_id,
        property_id,
        property_source_id,
        property_buffer,
        property_size
    };
}
