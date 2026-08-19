LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE := libopenal
LOCAL_ARM_NEON := true

LOCAL_CFLAGS := \
    -DAL_BUILD_LIBRARY \
    -DAL_ALEXT_PROTOTYPES \
    -DHAVE_OBOE=1 \
    -DHAVE_OPENSL=1 \
    -fvisibility=hidden
LOCAL_CPPFLAGS := -std=c++17 -fvisibility-inlines-hidden
LOCAL_CPP_FEATURES := exceptions rtti

LOCAL_C_INCLUDES := \
    $(LOCAL_PATH) \
    $(LOCAL_PATH)/al \
    $(LOCAL_PATH)/alc \
    $(LOCAL_PATH)/common \
    $(LOCAL_PATH)/core \
    $(LOCAL_PATH)/include
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)/include

ifeq ($(TARGET_ARCH_ABI),armeabi-v7a)
    LOCAL_CFLAGS += \
        -DHAVE_NEON=1
else ifeq ($(TARGET_ARCH_ABI),arm64-v8a)
    LOCAL_CFLAGS += \
        -DHAVE_NEON=1
else ifeq ($(TARGET_ARCH_ABI),x86)
    LOCAL_CFLAGS += \
        -msse3 \
        -DHAVE_SSE=1 \
        -DHAVE_SSE2=1 \
        -DHAVE_SSE3=1 \
        -DHAVE_SSE_INTRINSICS=1 \
        -DHAVE_CPUID_H \
        -DHAVE_GCC_GET_CPUID
else ifeq ($(TARGET_ARCH_ABI),x86_64)
    LOCAL_CFLAGS += \
        -msse4.1 \
        -DHAVE_SSE=1 \
        -DHAVE_SSE2=1 \
        -DHAVE_SSE3=1 \
        -DHAVE_SSE4_1=1 \
        -DHAVE_SSE_INTRINSICS=1 \
        -DHAVE_CPUID_H \
        -DHAVE_GCC_GET_CPUID
endif

LOCAL_SRC_FILES := \
    common/alassert.cpp \
    common/alcomplex.cpp \
    common/alsem.cpp \
    common/alstring.cpp \
    common/althrd_setname.cpp \
    common/dynload.cpp \
    common/pffft.cpp \
    common/polyphase_resampler.cpp \
    common/ringbuffer.cpp \
    common/strutils.cpp \
    core/ambdec.cpp \
    core/ambidefs.cpp \
    core/bformatdec.cpp \
    core/bs2b.cpp \
    core/bsinc_tables.cpp \
    core/buffer_storage.cpp \
    core/context.cpp \
    core/converter.cpp \
    core/cpu_caps.cpp \
    core/cubic_tables.cpp \
    core/devformat.cpp \
    core/device.cpp \
    core/effectslot.cpp \
    core/except.cpp \
    core/filters/biquad.cpp \
    core/filters/nfc.cpp \
    core/filters/splitter.cpp \
    core/fmt_traits.cpp \
    core/fpu_ctrl.cpp \
    core/helpers.cpp \
    core/hrtf.cpp \
    core/logging.cpp \
    core/mastering.cpp \
    core/mixer.cpp \
    core/storage_formats.cpp \
    core/uhjfilter.cpp \
    core/uiddefs.cpp \
    core/voice.cpp \
    core/mixer/mixer_c.cpp \
    al/auxeffectslot.cpp \
    al/buffer.cpp \
    al/debug.cpp \
    al/effect.cpp \
    al/effects/autowah.cpp \
    al/effects/chorus.cpp \
    al/effects/compressor.cpp \
    al/effects/convolution.cpp \
    al/effects/dedicated.cpp \
    al/effects/distortion.cpp \
    al/effects/echo.cpp \
    al/effects/effects.cpp \
    al/effects/equalizer.cpp \
    al/effects/fshifter.cpp \
    al/effects/modulator.cpp \
    al/effects/null.cpp \
    al/effects/pshifter.cpp \
    al/effects/reverb.cpp \
    al/effects/vmorpher.cpp \
    al/error.cpp \
    al/event.cpp \
    al/extension.cpp \
    al/filter.cpp \
    al/listener.cpp \
    al/source.cpp \
    al/state.cpp \
    alc/alc.cpp \
    alc/alconfig.cpp \
    alc/alu.cpp \
    alc/context.cpp \
    alc/device.cpp \
    alc/events.cpp \
    alc/panning.cpp \
    alc/effects/autowah.cpp \
    alc/effects/chorus.cpp \
    alc/effects/compressor.cpp \
    alc/effects/convolution.cpp \
    alc/effects/dedicated.cpp \
    alc/effects/distortion.cpp \
    alc/effects/echo.cpp \
    alc/effects/equalizer.cpp \
    alc/effects/fshifter.cpp \
    alc/effects/modulator.cpp \
    alc/effects/null.cpp \
    alc/effects/pshifter.cpp \
    alc/effects/reverb.cpp \
    alc/effects/vmorpher.cpp \
    opensl_latency.cpp

ifneq (,$(findstring HAVE_SSE4_1,${LOCAL_CFLAGS}))
    LOCAL_SRC_FILES += \
        core/mixer/mixer_sse.cpp \
        core/mixer/mixer_sse2.cpp \
        core/mixer/mixer_sse3.cpp \
        core/mixer/mixer_sse41.cpp
else ifneq (,$(findstring HAVE_SSE3,${LOCAL_CFLAGS}))
    LOCAL_SRC_FILES += \
        core/mixer/mixer_sse.cpp \
        core/mixer/mixer_sse2.cpp \
        core/mixer/mixer_sse3.cpp
else ifneq (,$(findstring HAVE_SSE2,${LOCAL_CFLAGS}))
    LOCAL_SRC_FILES += \
        core/mixer/mixer_sse.cpp \
        core/mixer/mixer_sse2.cpp
else ifneq (,$(findstring HAVE_NEON,${LOCAL_CFLAGS}))
    LOCAL_SRC_FILES += core/mixer/mixer_neon.cpp
endif

LOCAL_SRC_FILES += \
    alc/backends/base.cpp \
    alc/backends/loopback.cpp \
    alc/backends/null.cpp \
    alc/backends/oboe.cpp \
    alc/backends/opensl.cpp \
    alc/backends/wave.cpp

LOCAL_STATIC_LIBRARIES := oboe
LOCAL_LDLIBS := -lOpenSLES -llog

include $(BUILD_SHARED_LIBRARY)
