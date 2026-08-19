#ifndef ALU_H
#define ALU_H

#include <bitset>
#include <cstdint>
#include <optional>

struct ALCcontext;
struct ALCdevice;
struct EffectSlot;

enum class StereoEncoding : std::uint8_t;


constexpr float GainMixMax{1000.0f}; /* +60dB */


enum CompatFlags : std::uint8_t {
    ReverseX,
    ReverseY,
    ReverseZ,

    Count
};
using CompatFlagBitset = std::bitset<CompatFlags::Count>;

void aluInit(CompatFlagBitset flags, const float nfcscale);

/* aluInitRenderer
 *
 * Set up the appropriate panning method and mixing method given the device
 * properties.
 */
void aluInitRenderer(ALCdevice *device, int hrtf_id, std::optional<StereoEncoding> stereomode);

void aluInitEffectPanning(EffectSlot *slot, ALCcontext *context);

#endif
