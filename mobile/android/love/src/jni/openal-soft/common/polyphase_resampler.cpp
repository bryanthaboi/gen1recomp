
#include "polyphase_resampler.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <numeric>
#include <tuple>

#include "alnumbers.h"
#include "opthelpers.h"


using uint = unsigned int;

namespace {

constexpr double Epsilon{1e-9};


/* The zero-order modified Bessel function of the first kind, used for the
 * Kaiser window.
 *
 *   I_0(x) = sum_{k=0}^inf (1 / k!)^2 (x / 2)^(2 k)
 *          = sum_{k=0}^inf ((x / 2)^k / k!)^2
 *
 * This implementation only handles nu = 0, and isn't the most precise (it
 * starts with the largest value and accumulates successively smaller values,
 * compounding the rounding and precision error), but it's good enough.
 */
template<typename T, typename U>
constexpr auto cyl_bessel_i(T nu, U x) -> U
{
    if(nu != T{0})
        throw std::runtime_error{"cyl_bessel_i: nu != 0"};

    /* Start at k=1 since k=0 is trivial. */
    const double x2{x/2.0};
    double term{1.0};
    double sum{1.0};
    int k{1};

    /* Let the integration converge until the term of the sum is no longer
     * significant.
     */
    double last_sum{};
    do {
        const double y{x2 / k};
        ++k;
        last_sum = sum;
        term *= y * y;
        sum += term;
    } while(sum != last_sum);
    return static_cast<U>(sum);
}

/* This is the normalized cardinal sine (sinc) function.
 *
 *   sinc(x) = { 1,                   x = 0
 *             { sin(pi x) / (pi x),  otherwise.
 */
double Sinc(const double x)
{
    if(std::abs(x) < Epsilon) UNLIKELY
        return 1.0;
    return std::sin(al::numbers::pi*x) / (al::numbers::pi*x);
}

/* Calculate a Kaiser window from the given beta value and a normalized k
 * [-1, 1].
 *
 *   w(k) = { I_0(B sqrt(1 - k^2)) / I_0(B),  -1 <= k <= 1
 *          { 0,                              elsewhere.
 *
 * Where k can be calculated as:
 *
 *   k = i / l,         where -l <= i <= l.
 *
 * or:
 *
 *   k = 2 i / M - 1,   where 0 <= i <= M.
 */
double Kaiser(const double beta, const double k, const double besseli_0_beta)
{
    if(!(k >= -1.0 && k <= 1.0))
        return 0.0;
    return ::cyl_bessel_i(0, beta * std::sqrt(1.0 - k*k)) / besseli_0_beta;
}

/* Calculates the size (order) of the Kaiser window.  Rejection is in dB and
 * the transition width is normalized frequency (0.5 is nyquist).
 *
 *   M = { ceil((r - 7.95) / (2.285 2 pi f_t)),  r > 21
 *       { ceil(5.79 / 2 pi f_t),                r <= 21.
 *
 */
constexpr uint CalcKaiserOrder(const double rejection, const double transition)
{
    const double w_t{2.0 * al::numbers::pi * transition};
    if(rejection > 21.0) LIKELY
        return static_cast<uint>(std::ceil((rejection - 7.95) / (2.285 * w_t)));
    return static_cast<uint>(std::ceil(5.79 / w_t));
}

// Calculates the beta value of the Kaiser window.  Rejection is in dB.
constexpr double CalcKaiserBeta(const double rejection)
{
    if(rejection > 50.0) LIKELY
        return 0.1102 * (rejection - 8.7);
    if(rejection >= 21.0)
        return (0.5842 * std::pow(rejection - 21.0, 0.4)) +
               (0.07886 * (rejection - 21.0));
    return 0.0;
}

/* Calculates a point on the Kaiser-windowed sinc filter for the given half-
 * width, beta, gain, and cutoff.  The point is specified in non-normalized
 * samples, from 0 to M, where M = (2 l + 1).
 *
 *   w(k) 2 p f_t sinc(2 f_t x)
 *
 *   x    -- centered sample index (i - l)
 *   k    -- normalized and centered window index (x / l)
 *   w(k) -- window function (Kaiser)
 *   p    -- gain compensation factor when sampling
 *   f_t  -- normalized center frequency (or cutoff; 0.5 is nyquist)
 */
double SincFilter(const uint l, const double beta, const double besseli_0_beta, const double gain,
    const double cutoff, const uint i)
{
    const double x{static_cast<double>(i) - l};
    return Kaiser(beta, x/l, besseli_0_beta) * 2.0 * gain * cutoff * Sinc(2.0 * cutoff * x);
}

} // namespace

// Calculate the resampling metrics and build the Kaiser-windowed sinc filter
// that's used to cut frequencies above the destination nyquist.
void PPhaseResampler::init(const uint srcRate, const uint dstRate)
{
    const uint gcd{std::gcd(srcRate, dstRate)};
    mP = dstRate / gcd;
    mQ = srcRate / gcd;

    /* The cutoff is adjusted by half the transition width, so the transition
     * ends before the nyquist (0.5).  Both are scaled by the downsampling
     * factor.
     */
    const auto [cutoff, width] = (mP > mQ) ? std::make_tuple(0.475 / mP, 0.05 / mP)
        : std::make_tuple(0.475 / mQ, 0.05 / mQ);

    // A rejection of -180 dB is used for the stop band. Round up when
    // calculating the left offset to avoid increasing the transition width.
    const uint l{(CalcKaiserOrder(180.0, width)+1) / 2};
    const double beta{CalcKaiserBeta(180.0)};
    const double besseli_0_beta{::cyl_bessel_i(0, beta)};
    mM = l*2 + 1;
    mL = l;
    mF.resize(mM);
    for(uint i{0};i < mM;i++)
        mF[i] = SincFilter(l, beta, besseli_0_beta, mP, cutoff, i);
}

// Perform the upsample-filter-downsample resampling operation using a
// polyphase filter implementation.
void PPhaseResampler::process(const al::span<const double> in, const al::span<double> out)
{
    if(out.empty()) UNLIKELY
        return;

    // Handle in-place operation.
    std::vector<double> workspace;
    al::span work{out};
    if(work.data() == in.data()) UNLIKELY
    {
        workspace.resize(out.size());
        work = workspace;
    }

    // Resample the input.
    const uint p{mP}, q{mQ}, m{mM}, l{mL};
    const al::span<const double> f{mF};
    for(uint i{0};i < out.size();i++)
    {
        // Input starts at l to compensate for the filter delay.  This will
        // drop any build-up from the first half of the filter.
        std::size_t j_f{(l + q*i) % p};
        std::size_t j_s{(l + q*i) / p};

        // Only take input when 0 <= j_s < in.size().
        double r{0.0};
        if(j_f < m) LIKELY
        {
            std::size_t filt_len{(m-j_f+p-1) / p};
            if(j_s+1 > in.size()) LIKELY
            {
                std::size_t skip{std::min(j_s+1 - in.size(), filt_len)};
                j_f += p*skip;
                j_s -= skip;
                filt_len -= skip;
            }
            std::size_t todo{std::min(j_s+1, filt_len)};
            while(todo)
            {
                r += f[j_f] * in[j_s];
                j_f += p; --j_s;
                --todo;
            }
        }
        work[i] = r;
    }
    // Clean up after in-place operation.
    if(work.data() != out.data())
        std::copy(work.cbegin(), work.cend(), out.begin());
}
