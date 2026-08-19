LOCAL_PATH:= $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE := oboe
LOCAL_ARM_NEON := true

LOCAL_CFLAGS := -Wall -Wextra-semi -Wshadow -Wshadow-field
LOCAL_CPPFLAGS := -std=c++17

LOCAL_C_INCLUDES := \
	$(LOCAL_PATH)/include \
	$(LOCAL_PATH)/src
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)/include

LOCAL_SRC_FILES := \
    src/aaudio/AAudioLoader.cpp \
    src/aaudio/AudioStreamAAudio.cpp \
    src/common/AdpfWrapper.cpp \
    src/common/AudioSourceCaller.cpp \
    src/common/AudioStream.cpp \
    src/common/AudioStreamBuilder.cpp \
    src/common/DataConversionFlowGraph.cpp \
    src/common/FilterAudioStream.cpp \
    src/common/FixedBlockAdapter.cpp \
    src/common/FixedBlockReader.cpp \
    src/common/FixedBlockWriter.cpp \
    src/common/LatencyTuner.cpp \
    src/common/OboeExtensions.cpp \
    src/common/SourceFloatCaller.cpp \
    src/common/SourceI16Caller.cpp \
    src/common/SourceI24Caller.cpp \
    src/common/SourceI32Caller.cpp \
    src/common/Utilities.cpp \
    src/common/QuirksManager.cpp \
    src/fifo/FifoBuffer.cpp \
    src/fifo/FifoController.cpp \
    src/fifo/FifoControllerBase.cpp \
    src/fifo/FifoControllerIndirect.cpp \
    src/flowgraph/FlowGraphNode.cpp \
    src/flowgraph/ChannelCountConverter.cpp \
    src/flowgraph/ClipToRange.cpp \
    src/flowgraph/Limiter.cpp \
    src/flowgraph/ManyToMultiConverter.cpp \
    src/flowgraph/MonoBlend.cpp \
    src/flowgraph/MonoToMultiConverter.cpp \
    src/flowgraph/MultiToManyConverter.cpp \
    src/flowgraph/MultiToMonoConverter.cpp \
    src/flowgraph/RampLinear.cpp \
    src/flowgraph/SampleRateConverter.cpp \
    src/flowgraph/SinkFloat.cpp \
    src/flowgraph/SinkI16.cpp \
    src/flowgraph/SinkI24.cpp \
    src/flowgraph/SinkI32.cpp \
    src/flowgraph/SinkI8_24.cpp \
    src/flowgraph/SourceFloat.cpp \
    src/flowgraph/SourceI16.cpp \
    src/flowgraph/SourceI24.cpp \
    src/flowgraph/SourceI32.cpp \
    src/flowgraph/SourceI8_24.cpp \
    src/flowgraph/resampler/IntegerRatio.cpp \
    src/flowgraph/resampler/LinearResampler.cpp \
    src/flowgraph/resampler/MultiChannelResampler.cpp \
    src/flowgraph/resampler/PolyphaseResampler.cpp \
    src/flowgraph/resampler/PolyphaseResamplerMono.cpp \
    src/flowgraph/resampler/PolyphaseResamplerStereo.cpp \
    src/flowgraph/resampler/SincResampler.cpp \
    src/flowgraph/resampler/SincResamplerStereo.cpp \
    src/opensles/AudioInputStreamOpenSLES.cpp \
    src/opensles/AudioOutputStreamOpenSLES.cpp \
    src/opensles/AudioStreamBuffered.cpp \
    src/opensles/AudioStreamOpenSLES.cpp \
    src/opensles/EngineOpenSLES.cpp \
    src/opensles/OpenSLESUtilities.cpp \
    src/opensles/OutputMixerOpenSLES.cpp \
    src/common/StabilizedCallback.cpp \
    src/common/Trace.cpp \
    src/common/Version.cpp

LOCAL_LDLIBS := -llog

include $(BUILD_STATIC_LIBRARY)
