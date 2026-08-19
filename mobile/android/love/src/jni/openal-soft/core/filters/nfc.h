#ifndef CORE_FILTERS_NFC_H
#define CORE_FILTERS_NFC_H

#include <array>
#include <cstddef>

#include "alspan.h"


struct NfcFilter1 {
    float base_gain{1.0f}, gain{1.0f};
    float b1{}, a1{};
    std::array<float,1> z{};
};
struct NfcFilter2 {
    float base_gain{1.0f}, gain{1.0f};
    float b1{}, b2{}, a1{}, a2{};
    std::array<float,2> z{};
};
struct NfcFilter3 {
    float base_gain{1.0f}, gain{1.0f};
    float b1{}, b2{}, b3{}, a1{}, a2{}, a3{};
    std::array<float,3> z{};
};
struct NfcFilter4 {
    float base_gain{1.0f}, gain{1.0f};
    float b1{}, b2{}, b3{}, b4{}, a1{}, a2{}, a3{}, a4{};
    std::array<float,4> z{};
};

class NfcFilter {
    NfcFilter1 first;
    NfcFilter2 second;
    NfcFilter3 third;
    NfcFilter4 fourth;

public:
    /* NOTE:
     * w0 = speed_of_sound / (source_distance * sample_rate);
     * w1 = speed_of_sound / (control_distance * sample_rate);
     *
     * Generally speaking, the control distance should be approximately the
     * average speaker distance, or based on the reference delay if outputting
     * NFC-HOA. It must not be negative, 0, or infinite. The source distance
     * should not be too small relative to the control distance.
     */

    void init(const float w1) noexcept;
    void adjust(const float w0) noexcept;

    /* Near-field control filter for first-order ambisonic channels (1-3). */
    void process1(const al::span<const float> src, const al::span<float> dst);

    /* Near-field control filter for second-order ambisonic channels (4-8). */
    void process2(const al::span<const float> src, const al::span<float> dst);

    /* Near-field control filter for third-order ambisonic channels (9-15). */
    void process3(const al::span<const float> src, const al::span<float> dst);

    /* Near-field control filter for fourth-order ambisonic channels (16-24). */
    void process4(const al::span<const float> src, const al::span<float> dst);
};

#endif /* CORE_FILTERS_NFC_H */
