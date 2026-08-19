#ifndef CORE_UHJFILTER_H
#define CORE_UHJFILTER_H

#include <array>
#include <cstddef>
#include <cstdint>

#include "alspan.h"
#include "bufferline.h"
#include "opthelpers.h"


inline constexpr std::size_t UhjLength256{256};
inline constexpr std::size_t UhjLength512{512};

enum class UhjQualityType : std::uint8_t {
    IIR = 0,
    FIR256,
    FIR512,
    Default = IIR
};

inline UhjQualityType UhjDecodeQuality{UhjQualityType::Default};
inline UhjQualityType UhjEncodeQuality{UhjQualityType::Default};


struct UhjAllPassFilter {
    struct AllPassState {
        /* Last two delayed components for direct form II. */
        std::array<float,2> z{};
    };
    std::array<AllPassState,4> mState;

    void processOne(const al::span<const float,4> coeffs, float x);
    void process(const al::span<const float,4> coeffs, const al::span<const float> src,
        const bool update, const al::span<float> dst);
};


struct SIMDALIGN UhjEncoderBase {
    UhjEncoderBase() = default;
    UhjEncoderBase(const UhjEncoderBase&) = delete;
    UhjEncoderBase(UhjEncoderBase&&) = delete;
    virtual ~UhjEncoderBase() = default;

    void operator=(const UhjEncoderBase&) = delete;
    void operator=(UhjEncoderBase&&) = delete;

    virtual std::size_t getDelay() noexcept = 0;

    /**
     * Encodes a 2-channel UHJ (stereo-compatible) signal from a B-Format input
     * signal. The input must use FuMa channel ordering and UHJ scaling (FuMa
     * with an additional +3dB boost).
     */
    virtual void encode(float *LeftOut, float *RightOut,
        const al::span<const float*const,3> InSamples, const std::size_t SamplesToDo) = 0;
};

template<std::size_t N>
struct UhjEncoder final : public UhjEncoderBase {
    static constexpr std::size_t sFftLength{256};
    static constexpr std::size_t sSegmentSize{sFftLength/2};
    static constexpr std::size_t sNumSegments{N/sSegmentSize};
    static constexpr std::size_t sFilterDelay{N/2 + sSegmentSize};

    /* Delays and processing storage for the input signal. */
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mW{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mX{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mY{};

    alignas(16) std::array<float,BufferLineSize> mS{};
    alignas(16) std::array<float,BufferLineSize> mD{};

    /* History and temp storage for the convolution filter. */
    std::size_t mFifoPos{}, mCurrentSegment{};
    alignas(16) std::array<float,sFftLength> mWXInOut{};
    alignas(16) std::array<float,sFftLength> mFftBuffer{};
    alignas(16) std::array<float,sFftLength> mWorkData{};
    alignas(16) std::array<float,sFftLength*sNumSegments> mWXHistory{};

    alignas(16) std::array<std::array<float,sFilterDelay>,2> mDirectDelay{};

    std::size_t getDelay() noexcept override { return sFilterDelay; }

    /**
     * Encodes a 2-channel UHJ (stereo-compatible) signal from a B-Format input
     * signal. The input must use FuMa channel ordering and UHJ scaling (FuMa
     * with an additional +3dB boost).
     */
    void encode(float *LeftOut, float *RightOut, const al::span<const float*const,3> InSamples,
        const std::size_t SamplesToDo) final;
};

struct UhjEncoderIIR final : public UhjEncoderBase {
    static constexpr std::size_t sFilterDelay{1};

    /* Processing storage for the input signal. */
    alignas(16) std::array<float,BufferLineSize+1> mS{};
    alignas(16) std::array<float,BufferLineSize+1> mD{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mWX{};
    alignas(16) std::array<float,BufferLineSize+sFilterDelay> mTemp{};
    float mDelayWX{}, mDelayY{};

    UhjAllPassFilter mFilter1WX;
    UhjAllPassFilter mFilter2WX;
    UhjAllPassFilter mFilter1Y;

    std::array<UhjAllPassFilter,2> mFilter1Direct;
    std::array<float,2> mDirectDelay{};

    std::size_t getDelay() noexcept override { return sFilterDelay; }

    /**
     * Encodes a 2-channel UHJ (stereo-compatible) signal from a B-Format input
     * signal. The input must use FuMa channel ordering and UHJ scaling (FuMa
     * with an additional +3dB boost).
     */
    void encode(float *LeftOut, float *RightOut, const al::span<const float*const,3> InSamples,
        const std::size_t SamplesToDo) final;
};


struct SIMDALIGN DecoderBase {
    static constexpr std::size_t sMaxPadding{256};

    /* For 2-channel UHJ, shelf filters should use these LF responses. */
    static constexpr float sWLFScale{0.661f};
    static constexpr float sXYLFScale{1.293f};

    DecoderBase() = default;
    DecoderBase(const DecoderBase&) = delete;
    DecoderBase(DecoderBase&&) = delete;
    virtual ~DecoderBase() = default;

    void operator=(const DecoderBase&) = delete;
    void operator=(DecoderBase&&) = delete;

    virtual void decode(const al::span<float*> samples, const std::size_t samplesToDo,
        const bool updateState) = 0;

    /**
     * The width factor for Super Stereo processing. Can be changed in between
     * calls to decode, with valid values being between 0...0.7.
     */
    float mWidthControl{0.593f};
};

template<std::size_t N>
struct UhjDecoder final : public DecoderBase {
    /* The number of extra sample frames needed for input. */
    static constexpr std::size_t sInputPadding{N/2};

    alignas(16) std::array<float,BufferLineSize+sInputPadding> mS{};
    alignas(16) std::array<float,BufferLineSize+sInputPadding> mD{};
    alignas(16) std::array<float,BufferLineSize+sInputPadding> mT{};

    alignas(16) std::array<float,sInputPadding-1> mDTHistory{};
    alignas(16) std::array<float,sInputPadding-1> mSHistory{};

    alignas(16) std::array<float,BufferLineSize + sInputPadding*2> mTemp{};

    /**
     * Decodes a 3- or 4-channel UHJ signal into a B-Format signal with FuMa
     * channel ordering and UHJ scaling. For 3-channel, the 3rd channel may be
     * attenuated by 'n', where 0 <= n <= 1. So to decode 2-channel UHJ, supply
     * 3 channels with the 3rd channel silent (n=0). The B-Format signal
     * reconstructed from 2-channel UHJ should not be run through a normal
     * B-Format decoder, as it needs different shelf filters.
     */
    void decode(const al::span<float*> samples, const std::size_t samplesToDo,
        const bool updateState) final;
};

struct UhjDecoderIIR final : public DecoderBase {
    /* These IIR decoder filters normally have a 1-sample delay on the non-
     * filtered components. However, the filtered components are made to skip
     * the first output sample and take one future sample, which puts it ahead
     * by one sample. The first filtered output sample is cut to align it with
     * the first non-filtered sample, similar to the FIR filters.
     */
    static constexpr std::size_t sInputPadding{1};

    bool mFirstRun{true};
    alignas(16) std::array<float,BufferLineSize+sInputPadding> mS{};
    alignas(16) std::array<float,BufferLineSize+sInputPadding> mD{};
    alignas(16) std::array<float,BufferLineSize+sInputPadding> mTemp{};

    UhjAllPassFilter mFilter1S;
    UhjAllPassFilter mFilter2DT;
    UhjAllPassFilter mFilter1DT;
    UhjAllPassFilter mFilter2S;
    UhjAllPassFilter mFilter1Q;

    void decode(const al::span<float*> samples, const std::size_t samplesToDo,
        const bool updateState) final;
};

template<std::size_t N>
struct UhjStereoDecoder final : public DecoderBase {
    static constexpr std::size_t sInputPadding{N/2};

    float mCurrentWidth{-1.0f};

    alignas(16) std::array<float,BufferLineSize+sInputPadding> mS{};
    alignas(16) std::array<float,BufferLineSize+sInputPadding> mD{};

    alignas(16) std::array<float,sInputPadding-1> mDTHistory{};
    alignas(16) std::array<float,sInputPadding-1> mSHistory{};

    alignas(16) std::array<float,BufferLineSize + sInputPadding*2> mTemp{};

    /**
     * Applies Super Stereo processing on a stereo signal to create a B-Format
     * signal with FuMa channel ordering and UHJ scaling. The samples span
     * should contain 3 channels, the first two being the left and right stereo
     * channels, and the third left empty.
     */
    void decode(const al::span<float*> samples, const std::size_t samplesToDo,
        const bool updateState) final;
};

struct UhjStereoDecoderIIR final : public DecoderBase {
    static constexpr std::size_t sInputPadding{1};

    bool mFirstRun{true};
    float mCurrentWidth{-1.0f};

    alignas(16) std::array<float,BufferLineSize+sInputPadding> mS{};
    alignas(16) std::array<float,BufferLineSize+sInputPadding> mD{};
    alignas(16) std::array<float,BufferLineSize> mTemp{};

    UhjAllPassFilter mFilter1S;
    UhjAllPassFilter mFilter2D;
    UhjAllPassFilter mFilter1D;
    UhjAllPassFilter mFilter2S;

    void decode(const al::span<float*> samples, const std::size_t samplesToDo,
        const bool updateState) final;
};

#endif /* CORE_UHJFILTER_H */
