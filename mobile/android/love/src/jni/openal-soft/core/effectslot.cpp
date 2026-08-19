
#include "config.h"

#include "effectslot.h"

#include <cstddef>

#include "almalloc.h"
#include "context.h"


std::unique_ptr<EffectSlotArray> EffectSlot::CreatePtrArray(size_t count)
{
    return std::unique_ptr<EffectSlotArray>{new(FamCount{count}) EffectSlotArray(count)};
}
