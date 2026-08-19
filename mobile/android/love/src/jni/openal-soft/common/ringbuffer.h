#ifndef RINGBUFFER_H
#define RINGBUFFER_H

#include <atomic>
#include <cassert>
#include <cstddef>
#include <memory>
#include <utility>

#include "almalloc.h"
#include "flexarray.h"


/* NOTE: This lockless ringbuffer implementation is copied from JACK, extended
 * to include an element size. Consequently, parameters and return values for a
 * size or count are in 'elements', not bytes. Additionally, it only supports
 * single-consumer/single-provider operation.
 */

struct RingBuffer {
private:
#if defined(__cpp_lib_hardware_interference_size) && !defined(_LIBCPP_VERSION)
    static constexpr std::size_t sCacheAlignment{std::hardware_destructive_interference_size};
#else
    /* Assume a 64-byte cache line, the most common/likely value. */
    static constexpr std::size_t sCacheAlignment{64};
#endif
    alignas(sCacheAlignment) std::atomic<std::size_t> mWriteCount{0u};
    alignas(sCacheAlignment) std::atomic<std::size_t> mReadCount{0u};

    alignas(sCacheAlignment) const std::size_t mWriteSize;
    const std::size_t mSizeMask;
    const std::size_t mElemSize;

    al::FlexArray<std::byte, 16> mBuffer;

public:
    struct Data {
        std::byte *buf;
        std::size_t len;
    };
    using DataPair = std::array<Data,2>;

    RingBuffer(const std::size_t writesize, const std::size_t mask, const std::size_t elemsize,
        const std::size_t numbytes)
        : mWriteSize{writesize}, mSizeMask{mask}, mElemSize{elemsize}, mBuffer{numbytes}
    { }

    /** Reset the read and write pointers to zero. This is not thread safe. */
    auto reset() noexcept -> void;

    /**
     * Return the number of elements available for reading. This is the number
     * of elements in front of the read pointer and behind the write pointer.
     */
    [[nodiscard]] auto readSpace() const noexcept -> std::size_t
    {
        const std::size_t w{mWriteCount.load(std::memory_order_acquire)};
        const std::size_t r{mReadCount.load(std::memory_order_acquire)};
        /* mWriteCount is never more than mWriteSize greater than mReadCount. */
        return w - r;
    }

    /**
     * The copying data reader. Copy at most `count' elements into `dest'.
     * Returns the actual number of elements copied.
     */
    [[nodiscard]] auto read(void *dest, std::size_t count) noexcept -> std::size_t;
    /**
     * The copying data reader w/o read pointer advance. Copy at most `count'
     * elements into `dest'. Returns the actual number of elements copied.
     */
    [[nodiscard]] auto peek(void *dest, std::size_t count) const noexcept -> std::size_t;

    /**
     * The non-copying data reader. Returns two ringbuffer data pointers that
     * hold the current readable data. If the readable data is in one segment
     * the second segment has zero length.
     */
    [[nodiscard]] auto getReadVector() noexcept -> DataPair;
    /** Advance the read pointer `count' places. */
    auto readAdvance(std::size_t count) noexcept -> void
    {
        const std::size_t w{mWriteCount.load(std::memory_order_acquire)};
        const std::size_t r{mReadCount.load(std::memory_order_relaxed)};
        [[maybe_unused]] const std::size_t readable{w - r};
        assert(readable >= count);
        mReadCount.store(r+count, std::memory_order_release);
    }


    /**
     * Return the number of elements available for writing. This is the total
     * number of writable elements excluding what's readable (already written).
     */
    [[nodiscard]] auto writeSpace() const noexcept -> std::size_t
    { return mWriteSize - readSpace(); }

    /**
     * The copying data writer. Copy at most `count' elements from `src'. Returns
     * the actual number of elements copied.
     */
    [[nodiscard]] auto write(const void *src, std::size_t count) noexcept -> std::size_t;

    /**
     * The non-copying data writer. Returns two ringbuffer data pointers that
     * hold the current writeable data. If the writeable data is in one segment
     * the second segment has zero length.
     */
    [[nodiscard]] auto getWriteVector() noexcept -> DataPair;
    /** Advance the write pointer `count' places. */
    auto writeAdvance(std::size_t count) noexcept -> void
    {
        const std::size_t w{mWriteCount.load(std::memory_order_relaxed)};
        const std::size_t r{mReadCount.load(std::memory_order_acquire)};
        [[maybe_unused]] const std::size_t writable{mWriteSize - (w - r)};
        assert(writable >= count);
        mWriteCount.store(w+count, std::memory_order_release);
    }

    [[nodiscard]] auto getElemSize() const noexcept -> std::size_t { return mElemSize; }

    /**
     * Create a new ringbuffer to hold at least `sz' elements of `elem_sz'
     * bytes. The number of elements is rounded up to a power of two. If
     * `limit_writes' is true, the writable space will be limited to `sz'
     * elements regardless of the rounded size.
     */
    [[nodiscard]] static
    auto Create(std::size_t sz, std::size_t elem_sz, bool limit_writes) -> std::unique_ptr<RingBuffer>;

    DEF_FAM_NEWDEL(RingBuffer, mBuffer)
};
using RingBufferPtr = std::unique_ptr<RingBuffer>;

#endif /* RINGBUFFER_H */
