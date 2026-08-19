#ifndef INPROGEXT_H
#define INPROGEXT_H

/* NOLINTBEGIN */
#include "AL/al.h"
#include "AL/alc.h"
#include "AL/alext.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifndef AL_SOFT_map_buffer
#define AL_SOFT_map_buffer 1
typedef unsigned int ALbitfieldSOFT;
#define AL_MAP_READ_BIT_SOFT                     0x00000001
#define AL_MAP_WRITE_BIT_SOFT                    0x00000002
#define AL_MAP_PERSISTENT_BIT_SOFT               0x00000004
#define AL_PRESERVE_DATA_BIT_SOFT                0x00000008
typedef void (AL_APIENTRY*LPALBUFFERSTORAGESOFT)(ALuint buffer, ALenum format, const ALvoid *data, ALsizei size, ALsizei freq, ALbitfieldSOFT flags) AL_API_NOEXCEPT17;
typedef void* (AL_APIENTRY*LPALMAPBUFFERSOFT)(ALuint buffer, ALsizei offset, ALsizei length, ALbitfieldSOFT access) AL_API_NOEXCEPT17;
typedef void (AL_APIENTRY*LPALUNMAPBUFFERSOFT)(ALuint buffer) AL_API_NOEXCEPT17;
typedef void (AL_APIENTRY*LPALFLUSHMAPPEDBUFFERSOFT)(ALuint buffer, ALsizei offset, ALsizei length) AL_API_NOEXCEPT17;
typedef void (AL_APIENTRY*LPALBUFFERSTORAGEDIRECTSOFT)(ALCcontext *context, ALuint buffer, ALenum format, const ALvoid *data, ALsizei size, ALsizei freq, ALbitfieldSOFT flags) AL_API_NOEXCEPT17;
typedef void* (AL_APIENTRY*LPALMAPBUFFERDIRECTSOFT)(ALCcontext *context, ALuint buffer, ALsizei offset, ALsizei length, ALbitfieldSOFT access) AL_API_NOEXCEPT17;
typedef void (AL_APIENTRY*LPALUNMAPBUFFERDIRECTSOFT)(ALCcontext *context, ALuint buffer) AL_API_NOEXCEPT17;
typedef void (AL_APIENTRY*LPALFLUSHMAPPEDBUFFERDIRECTSOFT)(ALCcontext *context, ALuint buffer, ALsizei offset, ALsizei length) AL_API_NOEXCEPT17;
#ifdef AL_ALEXT_PROTOTYPES
AL_API void AL_APIENTRY alBufferStorageSOFT(ALuint buffer, ALenum format, const ALvoid *data, ALsizei size, ALsizei freq, ALbitfieldSOFT flags) AL_API_NOEXCEPT;
AL_API void* AL_APIENTRY alMapBufferSOFT(ALuint buffer, ALsizei offset, ALsizei length, ALbitfieldSOFT access) AL_API_NOEXCEPT;
AL_API void AL_APIENTRY alUnmapBufferSOFT(ALuint buffer) AL_API_NOEXCEPT;
AL_API void AL_APIENTRY alFlushMappedBufferSOFT(ALuint buffer, ALsizei offset, ALsizei length) AL_API_NOEXCEPT;
void AL_APIENTRY alBufferStorageDirectSOFT(ALCcontext *context, ALuint buffer, ALenum format, const ALvoid *data, ALsizei size, ALsizei freq, ALbitfieldSOFT flags) AL_API_NOEXCEPT;
void* AL_APIENTRY alMapBufferDirectSOFT(ALCcontext *context, ALuint buffer, ALsizei offset, ALsizei length, ALbitfieldSOFT access) AL_API_NOEXCEPT;
void AL_APIENTRY alUnmapBufferDirectSOFT(ALCcontext *context, ALuint buffer) AL_API_NOEXCEPT;
void AL_APIENTRY alFlushMappedBufferDirectSOFT(ALCcontext *context, ALuint buffer, ALsizei offset, ALsizei length) AL_API_NOEXCEPT;
#endif
#endif

#ifndef AL_SOFT_bformat_hoa
#define AL_SOFT_bformat_hoa
#define AL_UNPACK_AMBISONIC_ORDER_SOFT           0x199D
#endif

#ifndef AL_SOFT_convolution_effect
#define AL_SOFT_convolution_effect
#define AL_EFFECT_CONVOLUTION_SOFT               0xA000
#define AL_CONVOLUTION_ORIENTATION_SOFT          0x100F /* same as AL_ORIENTATION */
#define AL_EFFECTSLOT_STATE_SOFT                 0x199E
#endif

#ifndef AL_SOFT_hold_on_disconnect
#define AL_SOFT_hold_on_disconnect
#define AL_STOP_SOURCES_ON_DISCONNECT_SOFT       0x19AB
#endif


#ifndef AL_EXT_32bit_formats
#define AL_EXT_32bit_formats
#define AL_FORMAT_MONO_I32                       0x19DB
#define AL_FORMAT_STEREO_I32                     0x19DC
#define AL_FORMAT_REAR_I32                       0x19DD
#define AL_FORMAT_REAR_FLOAT32                   0x19DE
#define AL_FORMAT_QUAD_I32                       0x19DF
#define AL_FORMAT_QUAD_FLOAT32                   0x19E0
#define AL_FORMAT_51CHN_I32                      0x19E1
#define AL_FORMAT_51CHN_FLOAT32                  0x19E2
#define AL_FORMAT_61CHN_I32                      0x19E3
#define AL_FORMAT_61CHN_FLOAT32                  0x19E4
#define AL_FORMAT_71CHN_I32                      0x19E5
#define AL_FORMAT_71CHN_FLOAT32                  0x19E6

#define AL_FORMAT_BFORMAT2D_I32                  0x19E7
#define AL_FORMAT_BFORMAT3D_I32                  0x19E8

#define AL_FORMAT_UHJ2CHN_I32_SOFT               0x19E9
#define AL_FORMAT_UHJ3CHN_I32_SOFT               0x19EA
#define AL_FORMAT_UHJ4CHN_I32_SOFT               0x19EB
#endif

#ifndef AL_SOFT_source_panning
#define AL_SOFT_source_panning
#define AL_PANNING_ENABLED_SOFT                  0x19EC
#define AL_PAN_SOFT                              0x19ED
#endif

/* Non-standard exports. Not part of any extension. */
AL_API const ALchar* AL_APIENTRY alsoft_get_version(void) noexcept;

typedef void (ALC_APIENTRY*LPALSOFTLOGCALLBACK)(void *userptr, char level, const char *message, int length) noexcept;
void ALC_APIENTRY alsoft_set_log_callback(LPALSOFTLOGCALLBACK callback, void *userptr) noexcept;

/* Functions from abandoned extensions. Only here for binary compatibility. */
AL_API void AL_APIENTRY alSourceQueueBufferLayersSOFT(ALuint src, ALsizei nb,
    const ALuint *buffers) noexcept;

AL_API void AL_APIENTRY alAuxiliaryEffectSlotPlaySOFT(ALuint slotid) noexcept;
AL_API void AL_APIENTRY alAuxiliaryEffectSlotPlayvSOFT(ALsizei n, const ALuint *slotids) noexcept;
AL_API void AL_APIENTRY alAuxiliaryEffectSlotStopSOFT(ALuint slotid) noexcept;
AL_API void AL_APIENTRY alAuxiliaryEffectSlotStopvSOFT(ALsizei n, const ALuint *slotids) noexcept;

AL_API ALint64SOFT AL_APIENTRY alGetInteger64SOFT(ALenum pname) AL_API_NOEXCEPT;
AL_API void AL_APIENTRY alGetInteger64vSOFT(ALenum pname, ALint64SOFT *values) AL_API_NOEXCEPT;
ALint64SOFT AL_APIENTRY alGetInteger64DirectSOFT(ALCcontext *context, ALenum pname) AL_API_NOEXCEPT;
void AL_APIENTRY alGetInteger64vDirectSOFT(ALCcontext *context, ALenum pname, ALint64SOFT *values) AL_API_NOEXCEPT;

/* Not included in the public headers or export list, as a precaution for apps
 * that check these to determine the behavior of the multi-channel *32 formats.
 */
#define AL_FORMAT_MONO32                         0x1202
#define AL_FORMAT_STEREO32                       0x1203

#ifdef __cplusplus
} /* extern "C" */
#endif
/* NOLINTEND */

#endif /* INPROGEXT_H */
