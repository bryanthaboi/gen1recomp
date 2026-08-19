/**
 * OpenAL cross platform audio library
 * Copyright (C) 1999-2007 by authors.
 * This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Library General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 *  License along with this library; if not, write to the
 *  Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 * Or go to http://www.gnu.org/copyleft/lgpl.html
 */

#include "config.h"

#include "ringbuffer.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>
#include <stdexcept>

#include "alnumeric.h"
#include "alspan.h"


auto RingBuffer::Create(std::size_t sz, std::size_t elem_sz, bool limit_writes) -> RingBufferPtr
{
    std::size_t power_of_two{0u};
    if(sz > 0)
    {
        power_of_two = sz - 1;
        power_of_two |= power_of_two>>1;
        power_of_two |= power_of_two>>2;
        power_of_two |= power_of_two>>4;
        power_of_two |= power_of_two>>8;
        power_of_two |= power_of_two>>16;
        if constexpr(sizeof(size_t) > sizeof(uint32_t))
            power_of_two |= power_of_two>>32;
    }
    ++power_of_two;
    if(power_of_two < sz || power_of_two > std::numeric_limits<std::size_t>::max()>>1
        || power_of_two > std::numeric_limits<std::size_t>::max()/elem_sz)
        throw std::overflow_error{"Ring buffer size overflow"};

    const std::size_t bufbytes{power_of_two * elem_sz};
    RingBufferPtr rb{new(FamCount(bufbytes)) RingBuffer{limit_writes ? sz : power_of_two,
        power_of_two-1, elem_sz, bufbytes}};

    return rb;
}

void RingBuffer::reset() noexcept
{
    mWriteCount.store(0, std::memory_order_relaxed);
    mReadCount.store(0, std::memory_order_relaxed);
    std::fill_n(mBuffer.begin(), (mSizeMask+1)*mElemSize, std::byte{});
}


auto RingBuffer::read(void *dest, std::size_t count) noexcept -> std::size_t
{
    const std::size_t w{mWriteCount.load(std::memory_order_acquire)};
    const std::size_t r{mReadCount.load(std::memory_order_relaxed)};
    const std::size_t readable{w - r};
    if(readable == 0) return 0;

    const std::size_t to_read{std::min(count, readable)};
    const std::size_t read_idx{r & mSizeMask};

    const std::size_t rdend{read_idx + to_read};
    const auto [n1, n2] = (rdend <= mSizeMask+1) ? std::array{to_read, 0_uz}
        : std::array{mSizeMask+1 - read_idx, rdend&mSizeMask};

    auto dstbytes = al::span{static_cast<std::byte*>(dest), count*mElemSize};
    auto outiter = std::copy_n(mBuffer.begin() + ptrdiff_t(read_idx*mElemSize), n1*mElemSize,
        dstbytes.begin());
    if(n2 > 0)
        std::copy_n(mBuffer.begin(), n2*mElemSize, outiter);
    mReadCount.store(r+n1+n2, std::memory_order_release);
    return to_read;
}

auto RingBuffer::peek(void *dest, std::size_t count) const noexcept -> std::size_t
{
    const std::size_t w{mWriteCount.load(std::memory_order_acquire)};
    const std::size_t r{mReadCount.load(std::memory_order_relaxed)};
    const std::size_t readable{w - r};
    if(readable == 0) return 0;

    const std::size_t to_read{std::min(count, readable)};
    const std::size_t read_idx{r & mSizeMask};

    const std::size_t rdend{read_idx + to_read};
    const auto [n1, n2] = (rdend <= mSizeMask+1) ? std::array{to_read, 0_uz}
        : std::array{mSizeMask+1 - read_idx, rdend&mSizeMask};

    auto dstbytes = al::span{static_cast<std::byte*>(dest), count*mElemSize};
    auto outiter = std::copy_n(mBuffer.begin() + ptrdiff_t(read_idx*mElemSize), n1*mElemSize,
        dstbytes.begin());
    if(n2 > 0)
        std::copy_n(mBuffer.begin(), n2*mElemSize, outiter);
    return to_read;
}

auto RingBuffer::write(const void *src, std::size_t count) noexcept -> std::size_t
{
    const std::size_t w{mWriteCount.load(std::memory_order_relaxed)};
    const std::size_t r{mReadCount.load(std::memory_order_acquire)};
    const std::size_t writable{mWriteSize - (w - r)};
    if(writable == 0) return 0;

    const std::size_t to_write{std::min(count, writable)};
    const std::size_t write_idx{w & mSizeMask};

    const std::size_t wrend{write_idx + to_write};
    const auto [n1, n2] = (wrend <= mSizeMask+1) ? std::array{to_write, 0_uz}
        : std::array{mSizeMask+1 - write_idx, wrend&mSizeMask};

    auto srcbytes = al::span{static_cast<const std::byte*>(src), count*mElemSize};
    std::copy_n(srcbytes.cbegin(), n1*mElemSize, mBuffer.begin() + ptrdiff_t(write_idx*mElemSize));
    if(n2 > 0)
        std::copy_n(srcbytes.cbegin() + ptrdiff_t(n1*mElemSize), n2*mElemSize, mBuffer.begin());
    mWriteCount.store(w+n1+n2, std::memory_order_release);
    return to_write;
}


auto RingBuffer::getReadVector() noexcept -> DataPair
{
    const std::size_t w{mWriteCount.load(std::memory_order_acquire)};
    const std::size_t r{mReadCount.load(std::memory_order_relaxed)};
    const std::size_t readable{w - r};
    const std::size_t read_idx{r & mSizeMask};

    const std::size_t rdend{read_idx + readable};
    if(rdend > mSizeMask+1)
    {
        /* Two part vector: the rest of the buffer after the current read ptr,
         * plus some from the start of the buffer.
         */
        return DataPair{{{mBuffer.data() + read_idx*mElemSize, mSizeMask+1 - read_idx},
            {mBuffer.data(), rdend&mSizeMask}}};
    }
    return DataPair{{{mBuffer.data() + read_idx*mElemSize, readable}, {}}};
}

auto RingBuffer::getWriteVector() noexcept -> DataPair
{
    const std::size_t w{mWriteCount.load(std::memory_order_relaxed)};
    const std::size_t r{mReadCount.load(std::memory_order_acquire)};
    const std::size_t writable{mWriteSize - (w - r)};
    const std::size_t write_idx{w & mSizeMask};

    const std::size_t wrend{write_idx + writable};
    if(wrend > mSizeMask+1)
    {
        /* Two part vector: the rest of the buffer after the current write ptr,
         * plus some from the start of the buffer.
         */
        return DataPair{{{mBuffer.data() + write_idx*mElemSize, mSizeMask+1 - write_idx},
            {mBuffer.data(), wrend&mSizeMask}}};
    }
    return DataPair{{{mBuffer.data() + write_idx*mElemSize, writable}, {}}};
}
