/* Copyright (c) 2013  Julien Pommier ( pommier@modartt.com )

   Based on original fortran 77 code from FFTPACKv4 from NETLIB,
   authored by Dr Paul Swarztrauber of NCAR, in 1985.

   As confirmed by the NCAR fftpack software curators, the following
   FFTPACKv5 license applies to FFTPACKv4 sources. My changes are
   released under the same terms.

   FFTPACK license:

   http://www.cisl.ucar.edu/css/software/fftpack5/ftpk.html

   Copyright (c) 2004 the University Corporation for Atmospheric
   Research ("UCAR"). All rights reserved. Developed by NCAR's
   Computational and Information Systems Laboratory, UCAR,
   www.cisl.ucar.edu.

   Redistribution and use of the Software in source and binary forms,
   with or without modification, is permitted provided that the
   following conditions are met:

   - Neither the names of NCAR's Computational and Information Systems
   Laboratory, the University Corporation for Atmospheric Research,
   nor the names of its sponsors or contributors may be used to
   endorse or promote products derived from this Software without
   specific prior written permission.

   - Redistributions of source code must retain the above copyright
   notices, this list of conditions, and the disclaimer below.

   - Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions, and the disclaimer below in the
   documentation and/or other materials provided with the
   distribution.

   THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE CONTRIBUTORS OR COPYRIGHT
   HOLDERS BE LIABLE FOR ANY CLAIM, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS WITH THE
   SOFTWARE.
*/

/* PFFFT : a Pretty Fast FFT.
 *
 * This is basically an adaptation of the single precision fftpack (v4) as
 * found on netlib taking advantage of SIMD instructions found on CPUs such as
 * Intel x86 (SSE1), PowerPC (Altivec), and Arm (NEON).
 *
 * For architectures where SIMD instructions aren't available, the code falls
 * back to a scalar version.
 *
 * Restrictions:
 *
 * - 1D transforms only, with 32-bit single precision.
 *
 * - supports only transforms for inputs of length N of the form
 * N=(2^a)*(3^b)*(5^c), given a >= 5, b >=0, c >= 0 (32, 48, 64, 96, 128, 144,
 * 160, etc are all acceptable lengths). Performance is best for 128<=N<=8192.
 *
 * - all (float*) pointers for the functions below are expected to have a
 * "SIMD-compatible" alignment, that is 16 bytes.
 *
 * You can allocate such buffers with the pffft_aligned_malloc function, and
 * deallocate them with pffft_aligned_free (or with stuff like posix_memalign,
 * aligned_alloc, etc).
 *
 * Note that for the z-domain data of real transforms, when in the canonical
 * order (as interleaved complex numbers) both 0-frequency and half-frequency
 * components, which are real, are assembled in the first entry as
 * F(0)+i*F(n/2+1). The original fftpack placed F(n/2+1) at the end of the
 * arrays instead.
 */

#ifndef PFFFT_H
#define PFFFT_H

#include <cstddef>
#include <memory>

#include "almalloc.h"


/* opaque struct holding internal stuff (precomputed twiddle factors) this
 * struct can be shared by many threads as it contains only read-only data.
 */
struct PFFFT_Setup;

/* direction of the transform */
enum pffft_direction_t { PFFFT_FORWARD, PFFFT_BACKWARD };

/* type of transform */
enum pffft_transform_t { PFFFT_REAL, PFFFT_COMPLEX };

void pffft_destroy_setup(gsl::owner<PFFFT_Setup*> setup) noexcept;
struct PFFFTSetupDeleter {
    void operator()(gsl::owner<PFFFT_Setup*> setup) const noexcept { pffft_destroy_setup(setup); }
};
using PFFFTSetupPtr = std::unique_ptr<PFFFT_Setup,PFFFTSetupDeleter>;

/**
 * Prepare for performing transforms of size N -- the returned PFFFT_Setup
 * structure is read-only so it can safely be shared by multiple concurrent
 * threads.
 */
PFFFTSetupPtr pffft_new_setup(unsigned int N, pffft_transform_t transform);

/**
 * Perform a Fourier transform. The z-domain data is stored in the most
 * efficient order for transforming back or using for convolution, and as
 * such, there's no guarantee to the order of the values. If you need to have
 * its content sorted in the usual way, that is as an array of interleaved
 * complex numbers, either use pffft_transform_ordered, or call pffft_zreorder
 * after the forward fft and before the backward fft.
 *
 * Transforms are not scaled: PFFFT_BACKWARD(PFFFT_FORWARD(x)) = N*x. Typically
 * you will want to scale the backward transform by 1/N.
 *
 * The 'work' pointer must point to an area of N (2*N for complex fft) floats,
 * properly aligned. It cannot be NULL.
 *
 * The input and output parameters may alias.
 */
void pffft_transform(const PFFFT_Setup *setup, const float *input, float *output, float *work, pffft_direction_t direction);

/**
 * Similar to pffft_transform, but handles the complex values in the usual form
 * (interleaved complex numbers). This is similar to calling
 * pffft_transform(..., PFFFT_FORWARD) followed by
 * pffft_zreorder(..., PFFFT_FORWARD), or
 * pffft_zreorder(..., PFFFT_BACKWARD) followed by
 * pffft_transform(..., PFFFT_BACKWARD), for the given direction.
 *
 * The input and output parameters may alias.
 */
void pffft_transform_ordered(const PFFFT_Setup *setup, const float *input, float *output, float *work, pffft_direction_t direction);

/**
 * Reorder the z-domain data. For PFFFT_FORWARD, it reorders from the internal
 * representation to the "canonical" order (as interleaved complex numbers).
 * For PFFFT_BACKWARD, it reorders from the canonical order to the internal
 * order suitable for pffft_transform(..., PFFFT_BACKWARD) or
 * pffft_zconvolve_accumulate.
 *
 * The input and output parameters should not alias.
 */
void pffft_zreorder(const PFFFT_Setup *setup, const float *input, float *output, pffft_direction_t direction);

/**
 * Perform a multiplication of the z-domain data in dft_a and dft_b, and scale
 * and accumulate into dft_ab. The arrays should have been obtained with
 * pffft_transform(..., PFFFT_FORWARD) or pffft_zreorder(..., PFFFT_BACKWARD)
 * and should *not* be in the usual order (otherwise just perform the operation
 * yourself as the dft coeffs are stored as interleaved complex numbers).
 *
 * The operation performed is: dft_ab += (dft_a * dft_b)*scaling
 *
 * The dft_a, dft_b, and dft_ab parameters may alias.
 */
void pffft_zconvolve_scale_accumulate(const PFFFT_Setup *setup, const float *dft_a, const float *dft_b, float *dft_ab, float scaling);

/**
 * Perform a multiplication of the z-domain data in dft_a and dft_b, and
 * accumulate into dft_ab.
 *
 * The operation performed is: dft_ab += dft_a * dft_b
 *
 * The dft_a, dft_b, and dft_ab parameters may alias.
 */
void pffft_zconvolve_accumulate(const PFFFT_Setup *setup, const float *dft_a, const float *dft_b, float *dft_ab);


struct PFFFTSetup {
    PFFFTSetupPtr mSetup{};

    PFFFTSetup() = default;
    PFFFTSetup(const PFFFTSetup&) = delete;
    PFFFTSetup(PFFFTSetup&& rhs) noexcept = default;
    explicit PFFFTSetup(std::nullptr_t) noexcept { }
    explicit PFFFTSetup(unsigned int n, pffft_transform_t transform)
        : mSetup{pffft_new_setup(n, transform)}
    { }
    ~PFFFTSetup() = default;

    PFFFTSetup& operator=(const PFFFTSetup&) = delete;
    PFFFTSetup& operator=(PFFFTSetup&& rhs) noexcept = default;

    [[nodiscard]] explicit operator bool() const noexcept { return mSetup != nullptr; }

    void transform(const float *input, float *output, float *work, pffft_direction_t direction) const
    { pffft_transform(mSetup.get(), input, output, work, direction); }

    void transform_ordered(const float *input, float *output, float *work,
        pffft_direction_t direction) const
    { pffft_transform_ordered(mSetup.get(), input, output, work, direction); }

    void zreorder(const float *input, float *output, pffft_direction_t direction) const
    { pffft_zreorder(mSetup.get(), input, output, direction); }

    void zconvolve_scale_accumulate(const float *dft_a, const float *dft_b, float *dft_ab,
        float scaling) const
    { pffft_zconvolve_scale_accumulate(mSetup.get(), dft_a, dft_b, dft_ab, scaling); }

    void zconvolve_accumulate(const float *dft_a, const float *dft_b, float *dft_ab) const
    { pffft_zconvolve_accumulate(mSetup.get(), dft_a, dft_b, dft_ab); }
};

#endif // PFFFT_H
