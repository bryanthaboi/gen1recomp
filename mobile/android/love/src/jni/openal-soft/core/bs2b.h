/*-
 * Copyright (c) 2005 Boris Mikhaylov
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#ifndef CORE_BS2B_H
#define CORE_BS2B_H

#include <array>
#include <cstddef>

namespace Bs2b {

enum {
    /* Normal crossfeed levels */
    LowCLevel    = 1,
    MiddleCLevel = 2,
    HighCLevel   = 3,

    /* Easy crossfeed levels */
    LowECLevel    = 4,
    MiddleECLevel = 5,
    HighECLevel   = 6,

    DefaultCLevel = HighECLevel
};

struct bs2b {
    int level{}; /* Crossfeed level */
    int srate{}; /* Sample rate (Hz) */

    /* Lowpass IIR filter coefficients */
    float a0_lo{};
    float b1_lo{};

    /* Highboost IIR filter coefficients */
    float a0_hi{};
    float a1_hi{};
    float b1_hi{};

    /* Buffer of filter history
     * [0] - first channel, [1] - second channel
     */
    struct t_last_sample {
        float lo{};
        float hi{};
    };
    std::array<t_last_sample,2> history{};

    /* Clear buffers and set new coefficients with new crossfeed level and
     * sample rate values.
     * level - crossfeed level of *Level enum values.
     * srate - sample rate by Hz.
     */
    void set_params(int level, int srate);

    /* Return current crossfeed level value */
    [[nodiscard]] auto get_level() const noexcept -> int { return level; }

    /* Return current sample rate value */
    [[nodiscard]] auto get_srate() const noexcept -> int { return srate; }

    /* Clear buffer */
    void clear();

    void cross_feed(float *Left, float *Right, std::size_t SamplesToDo);
};

} // namespace Bs2b

#endif /* CORE_BS2B_H */
