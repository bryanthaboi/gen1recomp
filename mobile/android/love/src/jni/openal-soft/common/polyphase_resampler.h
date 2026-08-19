#ifndef POLYPHASE_RESAMPLER_H
#define POLYPHASE_RESAMPLER_H

#include <vector>

#include "alspan.h"


using uint = unsigned int;

/* This is a polyphase sinc-filtered resampler. It is built for very high
 * quality results, rather than real-time performance.
 *
 *              Upsample                      Downsample
 *
 *              p/q = 3/2                     p/q = 3/5
 *
 *          M-+-+-+->                     M-+-+-+->
 *         -------------------+          ---------------------+
 *   p  s * f f f f|f|        |    p  s * f f f f f           |
 *   |  0 *   0 0 0|0|0       |    |  0 *   0 0 0 0|0|        |
 *   v  0 *     0 0|0|0 0     |    v  0 *     0 0 0|0|0       |
 *      s *       f|f|f f f   |       s *       f f|f|f f     |
 *      0 *        |0|0 0 0 0 |       0 *         0|0|0 0 0   |
 *         --------+=+--------+       0 *          |0|0 0 0 0 |
 *          d . d .|d|. d . d            ----------+=+--------+
 *                                        d . . . .|d|. . . .
 *          q->
 *                                        q-+-+-+->
 *
 *   P_f(i,j) = q i mod p + pj
 *   P_s(i,j) = floor(q i / p) - j
 *   d[i=0..N-1] = sum_{j=0}^{floor((M - 1) / p)} {
 *                   { f[P_f(i,j)] s[P_s(i,j)],  P_f(i,j) < M
 *                   { 0,                        P_f(i,j) >= M. }
 */

struct PPhaseResampler {
    void init(const uint srcRate, const uint dstRate);
    void process(const al::span<const double> in, const al::span<double> out);

    explicit operator bool() const noexcept { return !mF.empty(); }

private:
    uint mP{}, mQ{}, mM{}, mL{};
    std::vector<double> mF;
};

#endif /* POLYPHASE_RESAMPLER_H */
