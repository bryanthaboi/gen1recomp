/*
 * HRTF utility for producing and demonstrating the process of creating an
 * OpenAL Soft compatible HRIR data set.
 *
 * Copyright (C) 2011-2019  Christopher Fitzgerald
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Or visit:  http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 */

#include "loaddef.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "albit.h"
#include "almalloc.h"
#include "alnumeric.h"
#include "alspan.h"
#include "alstring.h"
#include "makemhr.h"
#include "polyphase_resampler.h"
#include "sofa-support.h"

#include "mysofa.h"

namespace {

using namespace std::string_view_literals;

// Constants for accessing the token reader's ring buffer.
constexpr uint TRRingBits{16};
constexpr uint TRRingSize{1 << TRRingBits};
constexpr uint TRRingMask{TRRingSize - 1};

// The token reader's load interval in bytes.
constexpr uint TRLoadSize{TRRingSize >> 2};

// Token reader state for parsing the data set definition.
struct TokenReaderT {
    std::istream &mIStream;
    std::string mName{};
    uint        mLine{};
    uint        mColumn{};
    std::array<char,TRRingSize> mRing{};
    std::streamsize mIn{};
    std::streamsize mOut{};

    TokenReaderT(std::istream &istream) noexcept : mIStream{istream} { }
    TokenReaderT(const TokenReaderT&) = default;
};


// The limits for the listener's head 'radius' in the data set definition.
constexpr double MinRadius{0.05};
constexpr double MaxRadius{0.15};

// The maximum number of channels that can be addressed for a WAVE file
// source listed in the data set definition.
constexpr uint MaxWaveChannels{65535};

// The limits to the byte size for a binary source listed in the definition
// file.
enum : uint {
    MinBinSize = 2,
    MaxBinSize = 4
};

// The limits to the number of significant bits for an ASCII source listed in
// the data set definition.
enum : uint {
    MinASCIIBits = 16,
    MaxASCIIBits = 32
};

// The four-character-codes for RIFF/RIFX WAVE file chunks.
enum : uint {
    FOURCC_RIFF = 0x46464952, // 'RIFF'
    FOURCC_RIFX = 0x58464952, // 'RIFX'
    FOURCC_WAVE = 0x45564157, // 'WAVE'
    FOURCC_FMT  = 0x20746D66, // 'fmt '
    FOURCC_DATA = 0x61746164, // 'data'
    FOURCC_LIST = 0x5453494C, // 'LIST'
    FOURCC_WAVL = 0x6C766177, // 'wavl'
    FOURCC_SLNT = 0x746E6C73, // 'slnt'
};

// The supported wave formats.
enum : uint {
    WAVE_FORMAT_PCM        = 0x0001,
    WAVE_FORMAT_IEEE_FLOAT = 0x0003,
    WAVE_FORMAT_EXTENSIBLE = 0xFFFE,
};


enum ByteOrderT {
    BO_NONE,
    BO_LITTLE,
    BO_BIG
};

// Source format for the references listed in the data set definition.
enum SourceFormatT {
    SF_NONE,
    SF_ASCII,  // ASCII text file.
    SF_BIN_LE, // Little-endian binary file.
    SF_BIN_BE, // Big-endian binary file.
    SF_WAVE,   // RIFF/RIFX WAVE file.
    SF_SOFA    // Spatially Oriented Format for Accoustics (SOFA) file.
};

// Element types for the references listed in the data set definition.
enum ElementTypeT {
    ET_NONE,
    ET_INT,  // Integer elements.
    ET_FP    // Floating-point elements.
};

// Source reference state used when loading sources.
struct SourceRefT {
    SourceFormatT mFormat;
    ElementTypeT  mType;
    uint mSize;
    int  mBits;
    uint mChannel;
    double mAzimuth;
    double mElevation;
    double mRadius;
    uint mSkip;
    uint mOffset;
    std::array<char,MAX_PATH_LEN+1> mPath;
};


/* Whitespace is not significant. It can process tokens as identifiers, numbers
 * (integer and floating-point), strings, and operators. Strings must be
 * encapsulated by double-quotes and cannot span multiple lines.
 */

// Setup the reader on the given file.  The filename can be NULL if no error
// output is desired.
void TrSetup(const al::span<const char> startbytes, const std::string_view filename,
    TokenReaderT *tr)
{
    std::string_view namepart;

    if(!filename.empty())
    {
        const auto fslashpos = filename.rfind('/');
        const auto bslashpos = filename.rfind('\\');
        const auto slashpos = (bslashpos >= filename.size()) ? fslashpos :
            (fslashpos >= filename.size()) ? bslashpos :
            std::max(fslashpos, bslashpos);
        if(slashpos < filename.size())
            namepart = filename.substr(slashpos+1);
    }

    tr->mName = namepart;
    tr->mLine = 1;
    tr->mColumn = 1;
    tr->mIn = 0;
    tr->mOut = 0;

    if(!startbytes.empty())
    {
        assert(startbytes.size() <= tr->mRing.size());
        std::copy(startbytes.cbegin(), startbytes.cend(), tr->mRing.begin());
        tr->mIn += std::streamsize(startbytes.size());
    }
}

// Prime the reader's ring buffer, and return a result indicating that there
// is text to process.
auto TrLoad(TokenReaderT *tr) -> int
{
    std::istream &istream = tr->mIStream;

    auto toLoad = std::streamsize{TRRingSize} - (tr->mIn - tr->mOut);
    if(toLoad >= TRLoadSize && istream.good())
    {
        // Load TRLoadSize (or less if at the end of the file) per read.
        toLoad = TRLoadSize;

        const auto in = tr->mIn&TRRingMask;
        std::streamsize count{TRRingSize - in};
        if(count < toLoad)
        {
            istream.read(al::to_address(tr->mRing.begin() + in), count);
            tr->mIn += istream.gcount();
            istream.read(tr->mRing.data(), toLoad-count);
            tr->mIn += istream.gcount();
        }
        else
        {
            istream.read(al::to_address(tr->mRing.begin() + in), toLoad);
            tr->mIn += istream.gcount();
        }

        if(tr->mOut >= TRRingSize)
        {
            tr->mOut -= TRRingSize;
            tr->mIn -= TRRingSize;
        }
    }
    if(tr->mIn > tr->mOut)
        return 1;
    return 0;
}

// Error display routine.  Only displays when the base name is not NULL.
void TrErrorVA(const TokenReaderT *tr, uint line, uint column, const char *format, va_list argPtr)
{
    if(tr->mName.empty())
        return;
    fprintf(stderr, "\nError (%s:%u:%u): ", tr->mName.c_str(), line, column);
    vfprintf(stderr, format, argPtr);
}

// Used to display an error at a saved line/column.
void TrErrorAt(const TokenReaderT *tr, uint line, uint column, const char *format, ...)
{
    /* NOLINTBEGIN(*-array-to-pointer-decay) */
    va_list argPtr;
    va_start(argPtr, format);
    TrErrorVA(tr, line, column, format, argPtr);
    va_end(argPtr);
    /* NOLINTEND(*-array-to-pointer-decay) */
}

// Used to display an error at the current line/column.
void TrError(const TokenReaderT *tr, const char *format, ...)
{
    /* NOLINTBEGIN(*-array-to-pointer-decay) */
    va_list argPtr;
    va_start(argPtr, format);
    TrErrorVA(tr, tr->mLine, tr->mColumn, format, argPtr);
    va_end(argPtr);
    /* NOLINTEND(*-array-to-pointer-decay) */
}

// Skips to the next line.
void TrSkipLine(TokenReaderT *tr)
{
    char ch;

    while(TrLoad(tr))
    {
        ch = tr->mRing[tr->mOut&TRRingMask];
        tr->mOut++;
        if(ch == '\n')
        {
            tr->mLine++;
            tr->mColumn = 1;
            break;
        }
        tr->mColumn ++;
    }
}

// Skips to the next token.
auto TrSkipWhitespace(TokenReaderT *tr) -> int
{
    while(TrLoad(tr))
    {
        char ch{tr->mRing[tr->mOut&TRRingMask]};
        if(isspace(ch))
        {
            tr->mOut++;
            if(ch == '\n')
            {
                tr->mLine++;
                tr->mColumn = 1;
            }
            else
                tr->mColumn++;
        }
        else if(ch == '#')
            TrSkipLine(tr);
        else
            return 1;
    }
    return 0;
}

// Get the line and/or column of the next token (or the end of input).
void TrIndication(TokenReaderT *tr, uint *line, uint *column)
{
    TrSkipWhitespace(tr);
    if(line) *line = tr->mLine;
    if(column) *column = tr->mColumn;
}

// Checks to see if a token is (likely to be) an identifier.  It does not
// display any errors and will not proceed to the next token.
auto TrIsIdent(TokenReaderT *tr) -> int
{
    if(!TrSkipWhitespace(tr))
        return 0;
    char ch{tr->mRing[tr->mOut&TRRingMask]};
    return ch == '_' || isalpha(ch);
}


// Checks to see if a token is the given operator.  It does not display any
// errors and will not proceed to the next token.
auto TrIsOperator(TokenReaderT *tr, const std::string_view op) -> int
{
    if(!TrSkipWhitespace(tr))
        return 0;
    auto out = tr->mOut;
    size_t len{0};
    while(len < op.size() && out < tr->mIn)
    {
        if(tr->mRing[out&TRRingMask] != op[len])
            break;
        ++len;
        ++out;
    }
    if(len == op.size())
        return 1;
    return 0;
}

/* The TrRead*() routines obtain the value of a matching token type.  They
 * display type, form, and boundary errors and will proceed to the next
 * token.
 */

// Reads and validates an identifier token.
auto TrReadIdent(TokenReaderT *tr) -> std::string
{
    auto ret = std::string{};
    auto col = tr->mColumn;
    if(TrSkipWhitespace(tr))
    {
        col = tr->mColumn;
        auto ch = char{tr->mRing[tr->mOut&TRRingMask]};
        if(ch == '_' || isalpha(ch))
        {
            do {
                ret += ch;
                tr->mColumn += 1;
                tr->mOut += 1;
                if(!TrLoad(tr))
                    break;
                ch = tr->mRing[tr->mOut&TRRingMask];
            } while(ch == '_' || std::isdigit(ch) || std::isalpha(ch));

            return ret;
        }
    }
    TrErrorAt(tr, tr->mLine, col, "Expected an identifier.\n");
    ret.clear();
    return ret;
}

// Reads and validates (including bounds) an integer token.
auto TrReadInt(TokenReaderT *tr, const int loBound, const int hiBound, int *value) -> int
{
    uint col{tr->mColumn};
    if(TrSkipWhitespace(tr))
    {
        col = tr->mColumn;
        uint len{0};
        std::array<char,64+1> temp{};
        char ch{tr->mRing[tr->mOut&TRRingMask]};
        if(ch == '+' || ch == '-')
        {
            temp[len] = ch;
            len++;
            tr->mOut++;
        }
        uint digis{0};
        while(TrLoad(tr))
        {
            ch = tr->mRing[tr->mOut&TRRingMask];
            if(!isdigit(ch)) break;
            if(len < 64)
                temp[len] = ch;
            len++;
            digis++;
            tr->mOut++;
        }
        tr->mColumn += len;
        if(digis > 0 && ch != '.' && !isalpha(ch))
        {
            if(len > 64)
            {
                TrErrorAt(tr, tr->mLine, col, "Integer is too long.");
                return 0;
            }
            temp[len] = '\0';
            *value = static_cast<int>(strtol(temp.data(), nullptr, 10));
            if(*value < loBound || *value > hiBound)
            {
                TrErrorAt(tr, tr->mLine, col, "Expected a value from %d to %d.\n", loBound, hiBound);
                return 0;
            }
            return 1;
        }
    }
    TrErrorAt(tr, tr->mLine, col, "Expected an integer.\n");
    return 0;
}

// Reads and validates (including bounds) a float token.
auto TrReadFloat(TokenReaderT *tr, const double loBound, const double hiBound, double *value) -> int
{
    uint col{tr->mColumn};
    if(TrSkipWhitespace(tr))
    {
        col = tr->mColumn;
        std::array<char,64+1> temp{};
        uint len{0};
        char ch{tr->mRing[tr->mOut&TRRingMask]};
        if(ch == '+' || ch == '-')
        {
            temp[len] = ch;
            len++;
            tr->mOut++;
        }

        uint digis{0};
        while(TrLoad(tr))
        {
            ch = tr->mRing[tr->mOut&TRRingMask];
            if(!isdigit(ch)) break;
            if(len < 64)
                temp[len] = ch;
            len++;
            digis++;
            tr->mOut++;
        }
        if(ch == '.')
        {
            if(len < 64)
                temp[len] = ch;
            len++;
            tr->mOut++;
        }
        while(TrLoad(tr))
        {
            ch = tr->mRing[tr->mOut&TRRingMask];
            if(!isdigit(ch)) break;
            if(len < 64)
                temp[len] = ch;
            len++;
            digis++;
            tr->mOut++;
        }
        if(digis > 0)
        {
            if(ch == 'E' || ch == 'e')
            {
                if(len < 64)
                    temp[len] = ch;
                len++;
                digis = 0;
                tr->mOut++;
                if(ch == '+' || ch == '-')
                {
                    if(len < 64)
                        temp[len] = ch;
                    len++;
                    tr->mOut++;
                }
                while(TrLoad(tr))
                {
                    ch = tr->mRing[tr->mOut&TRRingMask];
                    if(!isdigit(ch)) break;
                    if(len < 64)
                        temp[len] = ch;
                    len++;
                    digis++;
                    tr->mOut++;
                }
            }
            tr->mColumn += len;
            if(digis > 0 && ch != '.' && !isalpha(ch))
            {
                if(len > 64)
                {
                    TrErrorAt(tr, tr->mLine, col, "Float is too long.");
                    return 0;
                }
                temp[len] = '\0';
                *value = strtod(temp.data(), nullptr);
                if(*value < loBound || *value > hiBound)
                {
                    TrErrorAt(tr, tr->mLine, col, "Expected a value from %f to %f.\n", loBound, hiBound);
                    return 0;
                }
                return 1;
            }
        }
        else
            tr->mColumn += len;
    }
    TrErrorAt(tr, tr->mLine, col, "Expected a float.\n");
    return 0;
}

// Reads and validates a string token.
auto TrReadString(TokenReaderT *tr, const al::span<char> text) -> int
{
    assert(!text.empty());
    const size_t maxLen{text.size()-1};

    uint col{tr->mColumn};
    if(TrSkipWhitespace(tr))
    {
        col = tr->mColumn;
        if(char ch{tr->mRing[tr->mOut&TRRingMask]}; ch == '\"')
        {
            tr->mOut++;
            size_t len{0};
            while(TrLoad(tr))
            {
                ch = tr->mRing[tr->mOut&TRRingMask];
                tr->mOut++;
                if(ch == '\"')
                    break;
                if(ch == '\n')
                {
                    TrErrorAt(tr, tr->mLine, col, "Unterminated string at end of line.\n");
                    return 0;
                }
                if(len < maxLen)
                    text[len] = ch;
                len++;
            }
            if(ch != '\"')
            {
                tr->mColumn += static_cast<uint>(1 + len);
                TrErrorAt(tr, tr->mLine, col, "Unterminated string at end of input.\n");
                return 0;
            }
            tr->mColumn += static_cast<uint>(2 + len);
            if(len > maxLen)
            {
                TrErrorAt(tr, tr->mLine, col, "String is too long.\n");
                return 0;
            }
            text[len] = '\0';
            return 1;
        }
    }
    TrErrorAt(tr, tr->mLine, col, "Expected a string.\n");
    return 0;
}

// Reads and validates the given operator.
auto TrReadOperator(TokenReaderT *tr, const std::string_view op) -> int
{
    uint col{tr->mColumn};
    if(TrSkipWhitespace(tr))
    {
        col = tr->mColumn;
        size_t len{0};
        while(len < op.size() && TrLoad(tr))
        {
            if(tr->mRing[tr->mOut&TRRingMask] != op[len])
                break;
            ++len;
            tr->mOut += 1;
        }
        tr->mColumn += static_cast<uint>(len);
        if(len == op.size())
            return 1;
    }
    TrErrorAt(tr, tr->mLine, col, "Expected '%s' operator.\n", op);
    return 0;
}


/*************************
 *** File source input ***
 *************************/

// Read a binary value of the specified byte order and byte size from a file,
// storing it as a 32-bit unsigned integer.
auto ReadBin4(std::istream &istream, const char *filename, const ByteOrderT order,
    const uint bytes, uint32_t *out) -> int
{
    std::array<uint8_t,4> in{};
    istream.read(reinterpret_cast<char*>(in.data()), static_cast<int>(bytes));
    if(istream.gcount() != bytes)
    {
        fprintf(stderr, "\nError: Bad read from file '%s'.\n", filename);
        return 0;
    }
    uint32_t accum{0};
    switch(order)
    {
        case BO_LITTLE:
            for(uint i = 0;i < bytes;i++)
                accum = (accum<<8) | in[bytes - i - 1];
            break;
        case BO_BIG:
            for(uint i = 0;i < bytes;i++)
                accum = (accum<<8) | in[i];
            break;
        default:
            break;
    }
    *out = accum;
    return 1;
}

// Read a binary value of the specified byte order from a file, storing it as
// a 64-bit unsigned integer.
auto ReadBin8(std::istream &istream, const char *filename, const ByteOrderT order, uint64_t *out) -> int
{
    std::array<uint8_t,8> in{};
    istream.read(reinterpret_cast<char*>(in.data()), 8);
    if(istream.gcount() != 8)
    {
        fprintf(stderr, "\nError: Bad read from file '%s'.\n", filename);
        return 0;
    }

    uint64_t accum{};
    switch(order)
    {
    case BO_LITTLE:
        for(uint i{0};i < 8;++i)
            accum = (accum<<8) | in[8 - i - 1];
        break;
    case BO_BIG:
        for(uint i{0};i < 8;++i)
            accum = (accum<<8) | in[i];
        break;
    default:
        break;
    }
    *out = accum;
    return 1;
}

/* Read a binary value of the specified type, byte order, and byte size from
 * a file, converting it to a double.  For integer types, the significant
 * bits are used to normalize the result.  The sign of bits determines
 * whether they are padded toward the MSB (negative) or LSB (positive).
 * Floating-point types are not normalized.
 */
auto ReadBinAsDouble(std::istream &istream, const char *filename, const ByteOrderT order,
    const ElementTypeT type, const uint bytes, const int bits, double *out) -> int
{
    *out = 0.0;
    if(bytes > 4)
    {
        uint64_t val{};
        if(!ReadBin8(istream, filename, order, &val))
            return 0;
        if(type == ET_FP)
            *out = al::bit_cast<double>(val);
    }
    else
    {
        uint32_t val{};
        if(!ReadBin4(istream, filename, order, bytes, &val))
            return 0;
        if(type == ET_FP)
            *out = al::bit_cast<float>(val);
        else
        {
            if(bits > 0)
                val >>= (8*bytes) - (static_cast<uint>(bits));
            else
                val &= (0xFFFFFFFF >> (32+bits));

            if(val&static_cast<uint>(1<<(std::abs(bits)-1)))
                val |= (0xFFFFFFFF << std::abs(bits));
            *out = static_cast<int32_t>(val) / static_cast<double>(1<<(std::abs(bits)-1));
        }
    }
    return 1;
}

/* Read an ascii value of the specified type from a file, converting it to a
 * double.  For integer types, the significant bits are used to normalize the
 * result.  The sign of the bits should always be positive.  This also skips
 * up to one separator character before the element itself.
 */
auto ReadAsciiAsDouble(TokenReaderT *tr, const char *filename, const ElementTypeT type,
    const uint bits, double *out) -> int
{
    if(TrIsOperator(tr, ","))
        TrReadOperator(tr, ",");
    else if(TrIsOperator(tr, ":"))
        TrReadOperator(tr, ":");
    else if(TrIsOperator(tr, ";"))
        TrReadOperator(tr, ";");
    else if(TrIsOperator(tr, "|"))
        TrReadOperator(tr, "|");

    if(type == ET_FP)
    {
        if(!TrReadFloat(tr, -std::numeric_limits<double>::infinity(),
            std::numeric_limits<double>::infinity(), out))
        {
            fprintf(stderr, "\nError: Bad read from file '%s'.\n", filename);
            return 0;
        }
    }
    else
    {
        int v;
        if(!TrReadInt(tr, -(1<<(bits-1)), (1<<(bits-1))-1, &v))
        {
            fprintf(stderr, "\nError: Bad read from file '%s'.\n", filename);
            return 0;
        }
        *out = v / static_cast<double>((1<<(bits-1))-1);
    }
    return 1;
}

// Read the RIFF/RIFX WAVE format chunk from a file, validating it against
// the source parameters and data set metrics.
auto ReadWaveFormat(std::istream &istream, const ByteOrderT order, const uint hrirRate,
    SourceRefT *src) -> int
{
    uint32_t fourCC, chunkSize;
    uint32_t format, channels, rate, dummy, block, size, bits;

    chunkSize = 0;
    do {
        if(chunkSize > 0)
            istream.seekg(static_cast<int>(chunkSize), std::ios::cur);
        if(!ReadBin4(istream, src->mPath.data(), BO_LITTLE, 4, &fourCC)
            || !ReadBin4(istream, src->mPath.data(), order, 4, &chunkSize))
            return 0;
    } while(fourCC != FOURCC_FMT);
    if(!ReadBin4(istream, src->mPath.data(), order, 2, &format)
        || !ReadBin4(istream, src->mPath.data(), order, 2, &channels)
        || !ReadBin4(istream, src->mPath.data(), order, 4, &rate)
        || !ReadBin4(istream, src->mPath.data(), order, 4, &dummy)
        || !ReadBin4(istream, src->mPath.data(), order, 2, &block))
        return 0;
    block /= channels;
    if(chunkSize > 14)
    {
        if(!ReadBin4(istream, src->mPath.data(), order, 2, &size))
            return 0;
        size /= 8;
        if(block > size)
            size = block;
    }
    else
        size = block;
    if(format == WAVE_FORMAT_EXTENSIBLE)
    {
        istream.seekg(2, std::ios::cur);
        if(!ReadBin4(istream, src->mPath.data(), order, 2, &bits))
            return 0;
        if(bits == 0)
            bits = 8 * size;
        istream.seekg(4, std::ios::cur);
        if(!ReadBin4(istream, src->mPath.data(), order, 2, &format))
            return 0;
        istream.seekg(static_cast<int>(chunkSize - 26), std::ios::cur);
    }
    else
    {
        bits = 8 * size;
        if(chunkSize > 14)
            istream.seekg(static_cast<int>(chunkSize - 16), std::ios::cur);
        else
            istream.seekg(static_cast<int>(chunkSize - 14), std::ios::cur);
    }
    if(format != WAVE_FORMAT_PCM && format != WAVE_FORMAT_IEEE_FLOAT)
    {
        fprintf(stderr, "\nError: Unsupported WAVE format in file '%s'.\n", src->mPath.data());
        return 0;
    }
    if(src->mChannel >= channels)
    {
        fprintf(stderr, "\nError: Missing source channel in WAVE file '%s'.\n", src->mPath.data());
        return 0;
    }
    if(rate != hrirRate)
    {
        fprintf(stderr, "\nError: Mismatched source sample rate in WAVE file '%s'.\n",
            src->mPath.data());
        return 0;
    }
    if(format == WAVE_FORMAT_PCM)
    {
        if(size < 2 || size > 4)
        {
            fprintf(stderr, "\nError: Unsupported sample size in WAVE file '%s'.\n",
                src->mPath.data());
            return 0;
        }
        if(bits < 16 || bits > (8*size))
        {
            fprintf(stderr, "\nError: Bad significant bits in WAVE file '%s'.\n",
                src->mPath.data());
            return 0;
        }
        src->mType = ET_INT;
    }
    else
    {
        if(size != 4 && size != 8)
        {
            fprintf(stderr, "\nError: Unsupported sample size in WAVE file '%s'.\n",
                src->mPath.data());
            return 0;
        }
        src->mType = ET_FP;
    }
    src->mSize = size;
    src->mBits = static_cast<int>(bits);
    src->mSkip = channels;
    return 1;
}

// Read a RIFF/RIFX WAVE data chunk, converting all elements to doubles.
auto ReadWaveData(std::istream &istream, const SourceRefT *src, const ByteOrderT order,
    const al::span<double> hrir) -> int
{
    auto pre = static_cast<int>(src->mSize * src->mChannel);
    auto post = static_cast<int>(src->mSize * (src->mSkip - src->mChannel - 1));
    auto skip = 0;
    for(size_t i{0};i < hrir.size();++i)
    {
        skip += pre;
        if(skip > 0)
            istream.seekg(skip, std::ios::cur);
        if(!ReadBinAsDouble(istream, src->mPath.data(), order, src->mType, src->mSize, src->mBits,
            &hrir[i]))
            return 0;
        skip = post;
    }
    if(skip > 0)
        istream.seekg(skip, std::ios::cur);
    return 1;
}

// Read the RIFF/RIFX WAVE list or data chunk, converting all elements to
// doubles.
auto ReadWaveList(std::istream &istream, const SourceRefT *src, const ByteOrderT order,
    const al::span<double> hrir) -> int
{
    uint32_t fourCC, chunkSize, listSize, count;
    uint block, skip, offset, i;
    double lastSample;

    for(;;)
    {
        if(!ReadBin4(istream, src->mPath.data(), BO_LITTLE, 4, &fourCC)
            || !ReadBin4(istream, src->mPath.data(), order, 4, &chunkSize))
            return 0;

        if(fourCC == FOURCC_DATA)
        {
            block = src->mSize * src->mSkip;
            count = chunkSize / block;
            if(count < (src->mOffset + hrir.size()))
            {
                fprintf(stderr, "\nError: Bad read from file '%s'.\n", src->mPath.data());
                return 0;
            }
            using off_type = std::istream::off_type;
            istream.seekg(off_type(src->mOffset) * off_type(block), std::ios::cur);
            if(!ReadWaveData(istream, src, order, hrir))
                return 0;
            return 1;
        }
        if(fourCC == FOURCC_LIST)
        {
            if(!ReadBin4(istream, src->mPath.data(), BO_LITTLE, 4, &fourCC))
                return 0;
            chunkSize -= 4;
            if(fourCC == FOURCC_WAVL)
                break;
        }
        if(chunkSize > 0)
            istream.seekg(static_cast<long>(chunkSize), std::ios::cur);
    }
    listSize = chunkSize;
    block = src->mSize * src->mSkip;
    skip = src->mOffset;
    offset = 0;
    lastSample = 0.0;
    while(offset < hrir.size() && listSize > 8)
    {
        if(!ReadBin4(istream, src->mPath.data(), BO_LITTLE, 4, &fourCC)
            || !ReadBin4(istream, src->mPath.data(), order, 4, &chunkSize))
            return 0;
        listSize -= 8 + chunkSize;
        if(fourCC == FOURCC_DATA)
        {
            count = chunkSize / block;
            if(count > skip)
            {
                using off_type = std::istream::off_type;
                istream.seekg(off_type(skip) * off_type(block), std::ios::cur);
                chunkSize -= skip * block;
                count -= skip;
                skip = 0;
                if(count > (hrir.size() - offset))
                    count = static_cast<uint>(hrir.size() - offset);
                if(!ReadWaveData(istream, src, order, hrir.subspan(offset, count)))
                    return 0;
                chunkSize -= count * block;
                offset += count;
                lastSample = hrir[offset - 1];
            }
            else
            {
                skip -= count;
                count = 0;
            }
        }
        else if(fourCC == FOURCC_SLNT)
        {
            if(!ReadBin4(istream, src->mPath.data(), order, 4, &count))
                return 0;
            chunkSize -= 4;
            if(count > skip)
            {
                count -= skip;
                skip = 0;
                if(count > (hrir.size() - offset))
                    count = static_cast<uint>(hrir.size() - offset);
                for(i = 0; i < count; i ++)
                    hrir[offset + i] = lastSample;
                offset += count;
            }
            else
            {
                skip -= count;
                count = 0;
            }
        }
        if(chunkSize > 0)
            istream.seekg(static_cast<long>(chunkSize), std::ios::cur);
    }
    if(offset < hrir.size())
    {
        fprintf(stderr, "\nError: Bad read from file '%s'.\n", src->mPath.data());
        return 0;
    }
    return 1;
}

// Load a source HRIR from an ASCII text file containing a list of elements
// separated by whitespace or common list operators (',', ';', ':', '|').
auto LoadAsciiSource(std::istream &istream, const SourceRefT *src, const al::span<double> hrir) -> int
{
    TokenReaderT tr{istream};

    TrSetup({}, {}, &tr);
    for(uint i{0};i < src->mOffset;++i)
    {
        double dummy{};
        if(!ReadAsciiAsDouble(&tr, src->mPath.data(), src->mType, static_cast<uint>(src->mBits),
            &dummy))
            return 0;
    }
    for(size_t i{0};i < hrir.size();++i)
    {
        if(!ReadAsciiAsDouble(&tr, src->mPath.data(), src->mType, static_cast<uint>(src->mBits),
            &hrir[i]))
            return 0;
        for(uint j{0};j < src->mSkip;++j)
        {
            double dummy{};
            if(!ReadAsciiAsDouble(&tr, src->mPath.data(), src->mType,
                static_cast<uint>(src->mBits), &dummy))
                return 0;
        }
    }
    return 1;
}

// Load a source HRIR from a binary file.
auto LoadBinarySource(std::istream &istream, const SourceRefT *src, const ByteOrderT order,
    const al::span<double> hrir) -> int
{
    istream.seekg(static_cast<long>(src->mOffset), std::ios::beg);
    for(size_t i{0};i < hrir.size();++i)
    {
        if(!ReadBinAsDouble(istream, src->mPath.data(), order, src->mType, src->mSize, src->mBits,
            &hrir[i]))
            return 0;
        if(src->mSkip > 0)
            istream.seekg(static_cast<long>(src->mSkip), std::ios::cur);
    }
    return 1;
}

// Load a source HRIR from a RIFF/RIFX WAVE file.
auto LoadWaveSource(std::istream &istream, SourceRefT *src, const uint hrirRate,
    const al::span<double> hrir) -> int
{
    uint32_t fourCC, dummy;
    ByteOrderT order;

    if(!ReadBin4(istream, src->mPath.data(), BO_LITTLE, 4, &fourCC)
        || !ReadBin4(istream, src->mPath.data(), BO_LITTLE, 4, &dummy))
        return 0;
    if(fourCC == FOURCC_RIFF)
        order = BO_LITTLE;
    else if(fourCC == FOURCC_RIFX)
        order = BO_BIG;
    else
    {
        fprintf(stderr, "\nError: No RIFF/RIFX chunk in file '%s'.\n", src->mPath.data());
        return 0;
    }

    if(!ReadBin4(istream, src->mPath.data(), BO_LITTLE, 4, &fourCC))
        return 0;
    if(fourCC != FOURCC_WAVE)
    {
        fprintf(stderr, "\nError: Not a RIFF/RIFX WAVE file '%s'.\n", src->mPath.data());
        return 0;
    }
    if(!ReadWaveFormat(istream, order, hrirRate, src))
        return 0;
    if(!ReadWaveList(istream, src, order, hrir))
        return 0;
    return 1;
}


struct SofaEasyDeleter {
    void operator()(gsl::owner<MYSOFA_EASY*> sofa)
    {
        if(sofa->neighborhood) mysofa_neighborhood_free(sofa->neighborhood);
        if(sofa->lookup) mysofa_lookup_free(sofa->lookup);
        if(sofa->hrtf) mysofa_free(sofa->hrtf);
        delete sofa;
    }
};
using SofaEasyPtr = std::unique_ptr<MYSOFA_EASY,SofaEasyDeleter>;

struct SofaCacheEntry {
    std::string mName;
    uint mSampleRate{};
    SofaEasyPtr mSofa;
};
std::vector<SofaCacheEntry> gSofaCache;

// Load a Spatially Oriented Format for Accoustics (SOFA) file.
auto LoadSofaFile(SourceRefT *src, const uint hrirRate, const uint n) -> MYSOFA_EASY*
{
    const std::string_view srcname{src->mPath.data()};
    auto iter = std::find_if(gSofaCache.begin(), gSofaCache.end(),
        [srcname,hrirRate](SofaCacheEntry &entry) -> bool
        { return entry.mName == srcname && entry.mSampleRate == hrirRate; });
    if(iter != gSofaCache.end()) return iter->mSofa.get();

    SofaEasyPtr sofa{new(std::nothrow) MYSOFA_EASY{}};
    if(!sofa)
    {
        fprintf(stderr, "\nError:  Out of memory.\n");
        return nullptr;
    }
    sofa->lookup = nullptr;
    sofa->neighborhood = nullptr;

    int err;
    sofa->hrtf = mysofa_load(src->mPath.data(), &err);
    if(!sofa->hrtf)
    {
        fprintf(stderr, "\nError: Could not load source file '%s': %s (%d).\n",
            src->mPath.data(), SofaErrorStr(err), err);
        return nullptr;
    }
    /* NOTE: Some valid SOFA files are failing this check. */
    err = mysofa_check(sofa->hrtf);
    if(err != MYSOFA_OK)
        fprintf(stderr, "\nWarning: Supposedly malformed source file '%s': %s (%d).\n",
            src->mPath.data(), SofaErrorStr(err), err);
    if((src->mOffset + n) > sofa->hrtf->N)
    {
        fprintf(stderr, "\nError: Not enough samples in SOFA file '%s'.\n", src->mPath.data());
        return nullptr;
    }
    if(src->mChannel >= sofa->hrtf->R)
    {
        fprintf(stderr, "\nError: Missing source receiver in SOFA file '%s'.\n",src->mPath.data());
        return nullptr;
    }
    mysofa_tocartesian(sofa->hrtf);
    sofa->lookup = mysofa_lookup_init(sofa->hrtf);
    if(sofa->lookup == nullptr)
    {
        fprintf(stderr, "\nError:  Out of memory.\n");
        return nullptr;
    }
    gSofaCache.emplace_back(SofaCacheEntry{std::string{srcname}, hrirRate, std::move(sofa)});
    return gSofaCache.back().mSofa.get();
}

// Copies the HRIR data from a particular SOFA measurement.
void ExtractSofaHrir(const MYSOFA_HRTF *hrtf, const size_t index, const size_t channel,
    const size_t offset, const al::span<double> hrir)
{
    const auto irValues = al::span{hrtf->DataIR.values, hrtf->DataIR.elements}
        .subspan((index*hrtf->R + channel)*hrtf->N + offset);
    std::copy_n(irValues.cbegin(), hrir.size(), hrir.begin());
}

// Load a source HRIR from a Spatially Oriented Format for Accoustics (SOFA)
// file.
auto LoadSofaSource(SourceRefT *src, const uint hrirRate, const al::span<double> hrir) -> int
{
    MYSOFA_EASY *sofa{LoadSofaFile(src, hrirRate, static_cast<uint>(hrir.size()))};
    if(sofa == nullptr) return 0;

    /* NOTE: At some point it may be beneficial or necessary to consider the
             various coordinate systems, listener/source orientations, and
             directional vectors defined in the SOFA file.
    */
    std::array target{
        static_cast<float>(src->mAzimuth),
        static_cast<float>(src->mElevation),
        static_cast<float>(src->mRadius)
    };
    mysofa_s2c(target.data());

    int nearest{mysofa_lookup(sofa->lookup, target.data())};
    if(nearest < 0)
    {
        fprintf(stderr, "\nError: Lookup failed in source file '%s'.\n", src->mPath.data());
        return 0;
    }

    al::span<float,3> coords = al::span{sofa->hrtf->SourcePosition.values, sofa->hrtf->M*3_uz}
        .subspan(static_cast<uint>(nearest)*3_uz).first<3>();
    if(std::abs(coords[0] - target[0]) > 0.001 || std::abs(coords[1] - target[1]) > 0.001
        || std::abs(coords[2] - target[2]) > 0.001)
    {
        fprintf(stderr, "\nError: No impulse response at coordinates (%.3fr, %.1fev, %.1faz) in file '%s'.\n",
            src->mRadius, src->mElevation, src->mAzimuth, src->mPath.data());
        target[0] = coords[0];
        target[1] = coords[1];
        target[2] = coords[2];
        mysofa_c2s(target.data());
        fprintf(stderr, "       Nearest candidate at (%.3fr, %.1fev, %.1faz).\n", target[2],
            target[1], target[0]);
        return 0;
    }

    ExtractSofaHrir(sofa->hrtf, static_cast<uint>(nearest), src->mChannel, src->mOffset, hrir);

    return 1;
}

// Load a source HRIR from a supported file type.
auto LoadSource(SourceRefT *src, const uint hrirRate, const al::span<double> hrir) -> int
{
    std::unique_ptr<std::istream> istream;
    if(src->mFormat != SF_SOFA)
    {
        if(src->mFormat == SF_ASCII)
            istream = std::make_unique<std::ifstream>(std::filesystem::u8path(src->mPath.data()));
        else
            istream = std::make_unique<std::ifstream>(std::filesystem::u8path(src->mPath.data()),
                std::ios::binary);
        if(!istream->good())
        {
            fprintf(stderr, "\nError: Could not open source file '%s'.\n", src->mPath.data());
            return 0;
        }
    }

    switch(src->mFormat)
    {
        case SF_ASCII: return LoadAsciiSource(*istream, src, hrir);
        case SF_BIN_LE: return LoadBinarySource(*istream, src, BO_LITTLE, hrir);
        case SF_BIN_BE: return LoadBinarySource(*istream, src, BO_BIG, hrir);
        case SF_WAVE: return LoadWaveSource(*istream, src, hrirRate, hrir);
        case SF_SOFA: return LoadSofaSource(src, hrirRate, hrir);
        case SF_NONE: break;
    }
    return 0;
}


// Match the channel type from a given identifier.
auto MatchChannelType(const std::string_view ident) -> ChannelTypeT
{
    if(al::case_compare(ident, "mono"sv) == 0)
        return CT_MONO;
    if(al::case_compare(ident, "stereo"sv) == 0)
        return CT_STEREO;
    return CT_NONE;
}


// Process the data set definition to read and validate the data set metrics.
auto ProcessMetrics(TokenReaderT *tr, const uint fftSize, const uint truncSize,
    const ChannelModeT chanMode, HrirDataT *hData) -> int
{
    int hasRate = 0, hasType = 0, hasPoints = 0, hasRadius = 0;
    int hasDistance = 0, hasAzimuths = 0;
    uint line, col;
    double fpVal;
    uint points;
    int intVal;
    std::array<double,MAX_FD_COUNT> distances{};
    uint fdCount = 0;
    std::array<uint,MAX_FD_COUNT> evCounts{};
    auto azCounts = std::vector<std::array<uint,MAX_EV_COUNT>>(MAX_FD_COUNT);
    for(auto &azs : azCounts) azs.fill(0u);

    TrIndication(tr, &line, &col);
    while(TrIsIdent(tr))
    {
        TrIndication(tr, &line, &col);
        const auto ident = TrReadIdent(tr);
        if(ident.empty())
            return 0;
        if(al::case_compare(ident, "rate"sv) == 0)
        {
            if(hasRate)
            {
                TrErrorAt(tr, line, col, "Redefinition of 'rate'.\n");
                return 0;
            }
            if(!TrReadOperator(tr, "="))
                return 0;
            if(!TrReadInt(tr, MIN_RATE, MAX_RATE, &intVal))
                return 0;
            hData->mIrRate = static_cast<uint>(intVal);
            hasRate = 1;
        }
        else if(al::case_compare(ident, "type"sv) == 0)
        {
            if(hasType)
            {
                TrErrorAt(tr, line, col, "Redefinition of 'type'.\n");
                return 0;
            }
            if(!TrReadOperator(tr, "="))
                return 0;

            const auto type = TrReadIdent(tr);
            if(type.empty())
                return 0;
            hData->mChannelType = MatchChannelType(type);
            if(hData->mChannelType == CT_NONE)
            {
                TrErrorAt(tr, line, col, "Expected a channel type.\n");
                return 0;
            }
            if(hData->mChannelType == CT_STEREO)
            {
                if(chanMode == CM_ForceMono)
                    hData->mChannelType = CT_MONO;
            }
            hasType = 1;
        }
        else if(al::case_compare(ident, "points"sv) == 0)
        {
            if(hasPoints)
            {
                TrErrorAt(tr, line, col, "Redefinition of 'points'.\n");
                return 0;
            }
            if(!TrReadOperator(tr, "="))
                return 0;
            TrIndication(tr, &line, &col);
            if(!TrReadInt(tr, MIN_POINTS, MAX_POINTS, &intVal))
                return 0;
            points = static_cast<uint>(intVal);
            if(fftSize > 0 && points > fftSize)
            {
                TrErrorAt(tr, line, col, "Value exceeds the overridden FFT size.\n");
                return 0;
            }
            if(points < truncSize)
            {
                TrErrorAt(tr, line, col, "Value is below the truncation size.\n");
                return 0;
            }
            hData->mIrPoints = points;
            hData->mFftSize = fftSize;
            hData->mIrSize = 1 + (fftSize / 2);
            if(points > hData->mIrSize)
                hData->mIrSize = points;
            hasPoints = 1;
        }
        else if(al::case_compare(ident, "radius"sv) == 0)
        {
            if(hasRadius)
            {
                TrErrorAt(tr, line, col, "Redefinition of 'radius'.\n");
                return 0;
            }
            if(!TrReadOperator(tr, "="))
                return 0;
            if(!TrReadFloat(tr, MinRadius, MaxRadius, &fpVal))
                return 0;
            hData->mRadius = fpVal;
            hasRadius = 1;
        }
        else if(al::case_compare(ident, "distance"sv) == 0)
        {
            auto count = uint{0};

            if(hasDistance)
            {
                TrErrorAt(tr, line, col, "Redefinition of 'distance'.\n");
                return 0;
            }
            if(!TrReadOperator(tr, "="))
                return 0;

            for(;;)
            {
                if(!TrReadFloat(tr, MIN_DISTANCE, MAX_DISTANCE, &fpVal))
                    return 0;
                if(count > 0 && fpVal <= distances[count - 1])
                {
                    TrError(tr, "Distances are not ascending.\n");
                    return 0;
                }
                distances[count++] = fpVal;
                if(!TrIsOperator(tr, ","))
                    break;
                if(count >= MAX_FD_COUNT)
                {
                    TrError(tr, "Exceeded the maximum of %d fields.\n", MAX_FD_COUNT);
                    return 0;
                }
                TrReadOperator(tr, ",");
            }
            if(fdCount != 0 && count != fdCount)
            {
                TrError(tr, "Did not match the specified number of %d fields.\n", fdCount);
                return 0;
            }
            fdCount = count;
            hasDistance = 1;
        }
        else if(al::case_compare(ident, "azimuths"sv) == 0)
        {
            auto count = uint{0};

            if(hasAzimuths)
            {
                TrErrorAt(tr, line, col, "Redefinition of 'azimuths'.\n");
                return 0;
            }
            if(!TrReadOperator(tr, "="))
                return 0;

            evCounts[0] = 0;
            for(;;)
            {
                if(!TrReadInt(tr, MIN_AZ_COUNT, MAX_AZ_COUNT, &intVal))
                    return 0;
                azCounts[count][evCounts[count]++] = static_cast<uint>(intVal);
                if(TrIsOperator(tr, ","))
                {
                    if(evCounts[count] >= MAX_EV_COUNT)
                    {
                        TrError(tr, "Exceeded the maximum of %d elevations.\n", MAX_EV_COUNT);
                        return 0;
                    }
                    TrReadOperator(tr, ",");
                }
                else
                {
                    if(evCounts[count] < MIN_EV_COUNT)
                    {
                        TrErrorAt(tr, line, col, "Did not reach the minimum of %d azimuth counts.\n", MIN_EV_COUNT);
                        return 0;
                    }
                    if(azCounts[count][0] != 1 || azCounts[count][evCounts[count] - 1] != 1)
                    {
                        TrError(tr, "Poles are not singular for field %d.\n", count - 1);
                        return 0;
                    }
                    count++;
                    if(!TrIsOperator(tr, ";"))
                        break;

                    if(count >= MAX_FD_COUNT)
                    {
                        TrError(tr, "Exceeded the maximum number of %d fields.\n", MAX_FD_COUNT);
                        return 0;
                    }
                    evCounts[count] = 0;
                    TrReadOperator(tr, ";");
                }
            }
            if(fdCount != 0 && count != fdCount)
            {
                TrError(tr, "Did not match the specified number of %d fields.\n", fdCount);
                return 0;
            }
            fdCount = count;
            hasAzimuths = 1;
        }
        else
        {
            TrErrorAt(tr, line, col, "Expected a metric name.\n");
            return 0;
        }
        TrSkipWhitespace(tr);
    }
    if(!(hasRate && hasPoints && hasRadius && hasDistance && hasAzimuths))
    {
        TrErrorAt(tr, line, col, "Expected a metric name.\n");
        return 0;
    }
    if(distances[0] < hData->mRadius)
    {
        TrError(tr, "Distance cannot start below head radius.\n");
        return 0;
    }
    if(hData->mChannelType == CT_NONE)
        hData->mChannelType = CT_MONO;
    const auto azs = al::span{azCounts}.first<MAX_FD_COUNT>();
    if(!PrepareHrirData(al::span{distances}.first(fdCount), evCounts, azs, hData))
    {
        fprintf(stderr, "Error:  Out of memory.\n");
        exit(-1);
    }
    return 1;
}

// Parse an index triplet from the data set definition.
auto ReadIndexTriplet(TokenReaderT *tr, const HrirDataT *hData, uint *fi, uint *ei, uint *ai)->int
{
    int intVal;

    if(hData->mFds.size() > 1)
    {
        if(!TrReadInt(tr, 0, static_cast<int>(hData->mFds.size()-1), &intVal))
            return 0;
        *fi = static_cast<uint>(intVal);
        if(!TrReadOperator(tr, ","))
            return 0;
    }
    else
    {
        *fi = 0;
    }
    if(!TrReadInt(tr, 0, static_cast<int>(hData->mFds[*fi].mEvs.size()-1), &intVal))
        return 0;
    *ei = static_cast<uint>(intVal);
    if(!TrReadOperator(tr, ","))
        return 0;
    if(!TrReadInt(tr, 0, static_cast<int>(hData->mFds[*fi].mEvs[*ei].mAzs.size()-1), &intVal))
        return 0;
    *ai = static_cast<uint>(intVal);
    return 1;
}

// Match the source format from a given identifier.
auto MatchSourceFormat(const std::string_view ident) -> SourceFormatT
{
    if(al::case_compare(ident, "ascii"sv) == 0)
        return SF_ASCII;
    if(al::case_compare(ident, "bin_le"sv) == 0)
        return SF_BIN_LE;
    if(al::case_compare(ident, "bin_be"sv) == 0)
        return SF_BIN_BE;
    if(al::case_compare(ident, "wave"sv) == 0)
        return SF_WAVE;
    if(al::case_compare(ident, "sofa"sv) == 0)
        return SF_SOFA;
    return SF_NONE;
}

// Match the source element type from a given identifier.
auto MatchElementType(const std::string_view ident) -> ElementTypeT
{
    if(al::case_compare(ident, "int"sv) == 0)
        return ET_INT;
    if(al::case_compare(ident, "fp"sv) == 0)
        return ET_FP;
    return ET_NONE;
}

// Parse and validate a source reference from the data set definition.
auto ReadSourceRef(TokenReaderT *tr, SourceRefT *src) -> int
{
    uint line, col;
    double fpVal;
    int intVal;

    TrIndication(tr, &line, &col);
    auto ident = TrReadIdent(tr);
    if(ident.empty())
        return 0;
    src->mFormat = MatchSourceFormat(ident);
    if(src->mFormat == SF_NONE)
    {
        TrErrorAt(tr, line, col, "Expected a source format.\n");
        return 0;
    }
    if(!TrReadOperator(tr, "("))
        return 0;
    if(src->mFormat == SF_SOFA)
    {
        if(!TrReadFloat(tr, MIN_DISTANCE, MAX_DISTANCE, &fpVal))
            return 0;
        src->mRadius = fpVal;
        if(!TrReadOperator(tr, ","))
            return 0;
        if(!TrReadFloat(tr, -90.0, 90.0, &fpVal))
            return 0;
        src->mElevation = fpVal;
        if(!TrReadOperator(tr, ","))
            return 0;
        if(!TrReadFloat(tr, -360.0, 360.0, &fpVal))
            return 0;
        src->mAzimuth = fpVal;
        if(!TrReadOperator(tr, ":"))
            return 0;
        if(!TrReadInt(tr, 0, MaxWaveChannels, &intVal))
            return 0;
        src->mType = ET_NONE;
        src->mSize = 0;
        src->mBits = 0;
        src->mChannel = static_cast<uint>(intVal);
        src->mSkip = 0;
    }
    else if(src->mFormat == SF_WAVE)
    {
        if(!TrReadInt(tr, 0, MaxWaveChannels, &intVal))
            return 0;
        src->mType = ET_NONE;
        src->mSize = 0;
        src->mBits = 0;
        src->mChannel = static_cast<uint>(intVal);
        src->mSkip = 0;
    }
    else
    {
        TrIndication(tr, &line, &col);
        ident = TrReadIdent(tr);
        if(ident.empty())
            return 0;
        src->mType = MatchElementType(ident);
        if(src->mType == ET_NONE)
        {
            TrErrorAt(tr, line, col, "Expected a source element type.\n");
            return 0;
        }
        if(src->mFormat == SF_BIN_LE || src->mFormat == SF_BIN_BE)
        {
            if(!TrReadOperator(tr, ","))
                return 0;
            if(src->mType == ET_INT)
            {
                if(!TrReadInt(tr, MinBinSize, MaxBinSize, &intVal))
                    return 0;
                src->mSize = static_cast<uint>(intVal);
                if(!TrIsOperator(tr, ","))
                    src->mBits = static_cast<int>(8*src->mSize);
                else
                {
                    TrReadOperator(tr, ",");
                    TrIndication(tr, &line, &col);
                    if(!TrReadInt(tr, -2147483647-1, 2147483647, &intVal))
                        return 0;
                    if(std::abs(intVal) < int{MinBinSize}*8 || static_cast<uint>(std::abs(intVal)) > (8*src->mSize))
                    {
                        TrErrorAt(tr, line, col, "Expected a value of (+/-) %d to %d.\n", MinBinSize*8, 8*src->mSize);
                        return 0;
                    }
                    src->mBits = intVal;
                }
            }
            else
            {
                TrIndication(tr, &line, &col);
                if(!TrReadInt(tr, -2147483647-1, 2147483647, &intVal))
                    return 0;
                if(intVal != 4 && intVal != 8)
                {
                    TrErrorAt(tr, line, col, "Expected a value of 4 or 8.\n");
                    return 0;
                }
                src->mSize = static_cast<uint>(intVal);
                src->mBits = 0;
            }
        }
        else if(src->mFormat == SF_ASCII && src->mType == ET_INT)
        {
            if(!TrReadOperator(tr, ","))
                return 0;
            if(!TrReadInt(tr, MinASCIIBits, MaxASCIIBits, &intVal))
                return 0;
            src->mSize = 0;
            src->mBits = intVal;
        }
        else
        {
            src->mSize = 0;
            src->mBits = 0;
        }

        if(!TrIsOperator(tr, ";"))
            src->mSkip = 0;
        else
        {
            TrReadOperator(tr, ";");
            if(!TrReadInt(tr, 0, 0x7FFFFFFF, &intVal))
                return 0;
            src->mSkip = static_cast<uint>(intVal);
        }
    }
    if(!TrReadOperator(tr, ")"))
        return 0;
    if(TrIsOperator(tr, "@"))
    {
        TrReadOperator(tr, "@");
        if(!TrReadInt(tr, 0, 0x7FFFFFFF, &intVal))
            return 0;
        src->mOffset = static_cast<uint>(intVal);
    }
    else
        src->mOffset = 0;
    if(!TrReadOperator(tr, ":"))
        return 0;
    if(!TrReadString(tr, src->mPath))
        return 0;
    return 1;
}

// Parse and validate a SOFA source reference from the data set definition.
auto ReadSofaRef(TokenReaderT *tr, SourceRefT *src) -> int
{
    uint line, col;
    int intVal;

    TrIndication(tr, &line, &col);
    const auto ident = TrReadIdent(tr);
    if(ident.empty())
        return 0;
    src->mFormat = MatchSourceFormat(ident);
    if(src->mFormat != SF_SOFA)
    {
        TrErrorAt(tr, line, col, "Expected the SOFA source format.\n");
        return 0;
    }

    src->mType = ET_NONE;
    src->mSize = 0;
    src->mBits = 0;
    src->mChannel = 0;
    src->mSkip = 0;

    if(TrIsOperator(tr, "@"))
    {
        TrReadOperator(tr, "@");
        if(!TrReadInt(tr, 0, 0x7FFFFFFF, &intVal))
            return 0;
        src->mOffset = static_cast<uint>(intVal);
    }
    else
        src->mOffset = 0;
    if(!TrReadOperator(tr, ":"))
        return 0;
    if(!TrReadString(tr, src->mPath))
        return 0;
    return 1;
}

// Match the target ear (index) from a given identifier.
auto MatchTargetEar(const std::string_view ident) -> std::optional<uint8_t>
{
    if(al::case_compare(ident, "left"sv) == 0)
        return 0u;
    if(al::case_compare(ident, "right"sv) == 0)
        return 1u;
    return std::nullopt;
}

// Calculate the onset time of an HRIR and average it with any existing
// timing for its field, elevation, azimuth, and ear.
constexpr int OnsetRateMultiple{10};
auto AverageHrirOnset(PPhaseResampler &rs, al::span<double> upsampled, const uint rate,
    const al::span<const double> hrir, const double f, const double onset) -> double
{
    rs.process(hrir, upsampled);

    auto abs_lt = [](const double lhs, const double rhs) -> bool
    { return std::abs(lhs) < std::abs(rhs); };
    auto iter = std::max_element(upsampled.cbegin(), upsampled.cend(), abs_lt);
    return Lerp(onset, static_cast<double>(std::distance(upsampled.cbegin(), iter))/(10*rate), f);
}

// Calculate the magnitude response of an HRIR and average it with any
// existing responses for its field, elevation, azimuth, and ear.
void AverageHrirMagnitude(const uint fftSize, const al::span<const double> hrir, const double f,
    const al::span<double> mag)
{
    const uint m{1 + (fftSize/2)};
    std::vector<complex_d> h(fftSize);
    std::vector<double> r(m);

    auto hiter = std::copy(hrir.cbegin(), hrir.cend(), h.begin());
    std::fill(hiter, h.end(), 0.0);
    forward_fft(h);
    MagnitudeResponse(h, r);
    for(uint i{0};i < m;++i)
        mag[i] = Lerp(mag[i], r[i], f);
}

// Process the list of sources in the data set definition.
auto ProcessSources(TokenReaderT *tr, HrirDataT *hData, const uint outRate) -> int
{
    const uint channels{(hData->mChannelType == CT_STEREO) ? 2u : 1u};
    hData->mHrirsBase.resize(size_t{channels} * hData->mIrCount * hData->mIrSize);
    const auto hrirs = al::span<double>{hData->mHrirsBase};
    auto hrir = std::vector<double>(hData->mIrSize);
    uint line, col, fi, ei, ai;

    std::vector<double> onsetSamples(size_t{OnsetRateMultiple} * hData->mIrPoints);
    PPhaseResampler onsetResampler;
    onsetResampler.init(hData->mIrRate, OnsetRateMultiple*hData->mIrRate);

    std::optional<PPhaseResampler> resampler;
    if(outRate && outRate != hData->mIrRate)
        resampler.emplace().init(hData->mIrRate, outRate);
    const double rateScale{outRate ? static_cast<double>(outRate) / hData->mIrRate : 1.0};
    const uint irPoints{outRate
        ? std::min(static_cast<uint>(std::ceil(hData->mIrPoints*rateScale)), hData->mIrPoints)
        : hData->mIrPoints};

    printf("Loading sources...");
    fflush(stdout);
    int count{0};
    while(TrIsOperator(tr, "["))
    {
        std::array factor{1.0, 1.0};

        TrIndication(tr, &line, &col);
        TrReadOperator(tr, "[");

        if(TrIsOperator(tr, "*"))
        {
            TrReadOperator(tr, "*");
            if(!TrReadOperator(tr, "]") || !TrReadOperator(tr, "="))
                return 0;

            TrIndication(tr, &line, &col);
            SourceRefT src{};
            if(!ReadSofaRef(tr, &src))
                return 0;

            if(hData->mChannelType == CT_STEREO)
            {
                const auto type = TrReadIdent(tr);
                if(type.empty())
                    return 0;

                switch(MatchChannelType(type))
                {
                case CT_NONE:
                    TrErrorAt(tr, line, col, "Expected a channel type.\n");
                    return 0;
                case CT_MONO:
                    src.mChannel = 0;
                    break;
                case CT_STEREO:
                    src.mChannel = 1;
                    break;
                }
            }
            else
            {
                const auto type = TrReadIdent(tr);
                if(type.empty())
                    return 0;

                if(MatchChannelType(type) != CT_MONO)
                {
                    TrErrorAt(tr, line, col, "Expected a mono channel type.\n");
                    return 0;
                }
                src.mChannel = 0;
            }

            MYSOFA_EASY *sofa{LoadSofaFile(&src, hData->mIrRate, hData->mIrPoints)};
            if(!sofa) return 0;

            const auto srcPosValues = al::span{sofa->hrtf->SourcePosition.values,
                sofa->hrtf->M*3_uz};
            for(uint si{0};si < sofa->hrtf->M;++si)
            {
                printf("\rLoading sources... %d of %d", si+1, sofa->hrtf->M);
                fflush(stdout);

                std::array aer{srcPosValues[3_uz*si], srcPosValues[3_uz*si + 1],
                    srcPosValues[3_uz*si + 2]};
                mysofa_c2s(aer.data());

                if(std::fabs(aer[1]) >= 89.999f)
                    aer[0] = 0.0f;
                else
                    aer[0] = std::fmod(360.0f - aer[0], 360.0f);

                auto field = std::find_if(hData->mFds.cbegin(), hData->mFds.cend(),
                    [&aer](const HrirFdT &fld) -> bool
                    { return (std::abs(aer[2] - fld.mDistance) < 0.001); });
                if(field == hData->mFds.cend())
                    continue;
                fi = static_cast<uint>(std::distance(hData->mFds.cbegin(), field));

                const double evscale{180.0 / static_cast<double>(field->mEvs.size()-1)};
                double ef{(90.0 + aer[1]) / evscale};
                ei = static_cast<uint>(std::round(ef));
                ef = (ef - ei) * evscale;
                if(std::abs(ef) >= 0.1)
                    continue;

                const double azscale{360.0 / static_cast<double>(field->mEvs[ei].mAzs.size())};
                double af{aer[0] / azscale};
                ai = static_cast<uint>(std::round(af));
                af = (af - ai) * azscale;
                ai %= static_cast<uint>(field->mEvs[ei].mAzs.size());
                if(std::abs(af) >= 0.1)
                    continue;

                HrirAzT *azd = &field->mEvs[ei].mAzs[ai];
                if(!azd->mIrs[0].empty())
                {
                    TrErrorAt(tr, line, col, "Redefinition of source [ %d, %d, %d ].\n", fi, ei, ai);
                    return 0;
                }

                const auto hrirPoints = al::span{hrir}.first(hData->mIrPoints);
                ExtractSofaHrir(sofa->hrtf, si, 0, src.mOffset, hrirPoints);
                azd->mIrs[0] = hrirs.subspan(size_t{hData->mIrSize}*azd->mIndex, hData->mIrSize);
                azd->mDelays[0] = AverageHrirOnset(onsetResampler, onsetSamples, hData->mIrRate,
                    hrirPoints, 1.0, azd->mDelays[0]);
                if(resampler)
                    resampler->process(hrirPoints, hrir);
                AverageHrirMagnitude(hData->mFftSize, al::span{hrir}.first(irPoints), 1.0,
                    azd->mIrs[0]);

                if(src.mChannel == 1)
                {
                    ExtractSofaHrir(sofa->hrtf, si, 1, src.mOffset, hrirPoints);
                    azd->mIrs[1] = hrirs.subspan(
                        (size_t{hData->mIrCount}+azd->mIndex) * hData->mIrSize, hData->mIrSize);
                    azd->mDelays[1] = AverageHrirOnset(onsetResampler, onsetSamples,
                        hData->mIrRate, hrirPoints, 1.0, azd->mDelays[1]);
                    if(resampler)
                        resampler->process(hrirPoints, hrir);
                    AverageHrirMagnitude(hData->mFftSize, al::span{hrir}.first(irPoints), 1.0,
                        azd->mIrs[1]);
                }

                // TODO: Since some SOFA files contain minimum phase HRIRs,
                // it would be beneficial to check for per-measurement delays
                // (when available) to reconstruct the HRTDs.
            }

            continue;
        }

        if(!ReadIndexTriplet(tr, hData, &fi, &ei, &ai))
            return 0;
        if(!TrReadOperator(tr, "]"))
            return 0;
        HrirAzT *azd = &hData->mFds[fi].mEvs[ei].mAzs[ai];

        if(!azd->mIrs[0].empty())
        {
            TrErrorAt(tr, line, col, "Redefinition of source.\n");
            return 0;
        }
        if(!TrReadOperator(tr, "="))
            return 0;

        while(true)
        {
            SourceRefT src{};
            if(!ReadSourceRef(tr, &src))
                return 0;

            // TODO: Would be nice to display 'x of y files', but that would
            // require preparing the source refs first to get a total count
            // before loading them.
            ++count;
            printf("\rLoading sources... %d file%s", count, (count==1)?"":"s");
            fflush(stdout);

            if(!LoadSource(&src, hData->mIrRate, al::span{hrir}.first(hData->mIrPoints)))
                return 0;

            auto ti = uint{0};
            if(hData->mChannelType == CT_STEREO)
            {
                const auto ident = TrReadIdent(tr);
                if(ident.empty())
                    return 0;

                if(auto earopt = MatchTargetEar(ident))
                    ti = *earopt;
                else
                {
                    TrErrorAt(tr, line, col, "Expected a target ear.\n");
                    return 0;
                }
            }
            const auto hrirPoints = al::span{hrir}.first(hData->mIrPoints);
            azd->mIrs[ti] = hrirs.subspan((ti*size_t{hData->mIrCount}+azd->mIndex)*hData->mIrSize,
                hData->mIrSize);
            azd->mDelays[ti] = AverageHrirOnset(onsetResampler, onsetSamples, hData->mIrRate,
                hrirPoints, 1.0/factor[ti], azd->mDelays[ti]);
            if(resampler)
                resampler->process(hrirPoints, hrir);
            AverageHrirMagnitude(hData->mFftSize, al::span{hrir}.first(irPoints), 1.0/factor[ti],
                azd->mIrs[ti]);
            factor[ti] += 1.0;
            if(!TrIsOperator(tr, "+"))
                break;
            TrReadOperator(tr, "+");
        }
        if(hData->mChannelType == CT_STEREO)
        {
            if(azd->mIrs[0].empty())
            {
                TrErrorAt(tr, line, col, "Missing left ear source reference(s).\n");
                return 0;
            }
            if(azd->mIrs[1].empty())
            {
                TrErrorAt(tr, line, col, "Missing right ear source reference(s).\n");
                return 0;
            }
        }
    }
    printf("\n");
    hrir.clear();
    if(resampler)
    {
        hData->mIrRate = outRate;
        hData->mIrPoints = irPoints;
        resampler.reset();
    }
    for(fi = 0;fi < hData->mFds.size();fi++)
    {
        for(ei = 0;ei < hData->mFds[fi].mEvs.size();ei++)
        {
            for(ai = 0;ai < hData->mFds[fi].mEvs[ei].mAzs.size();ai++)
            {
                HrirAzT *azd = &hData->mFds[fi].mEvs[ei].mAzs[ai];
                if(!azd->mIrs[0].empty())
                    break;
            }
            if(ai < hData->mFds[fi].mEvs[ei].mAzs.size())
                break;
        }
        if(ei >= hData->mFds[fi].mEvs.size())
        {
            TrError(tr, "Missing source references [ %d, *, * ].\n", fi);
            return 0;
        }
        hData->mFds[fi].mEvStart = ei;
        for(;ei < hData->mFds[fi].mEvs.size();ei++)
        {
            for(ai = 0;ai < hData->mFds[fi].mEvs[ei].mAzs.size();ai++)
            {
                HrirAzT *azd = &hData->mFds[fi].mEvs[ei].mAzs[ai];

                if(azd->mIrs[0].empty())
                {
                    TrError(tr, "Missing source reference [ %d, %d, %d ].\n", fi, ei, ai);
                    return 0;
                }
            }
        }
    }
    for(uint ti{0};ti < channels;ti++)
    {
        for(fi = 0;fi < hData->mFds.size();fi++)
        {
            for(ei = 0;ei < hData->mFds[fi].mEvs.size();ei++)
            {
                for(ai = 0;ai < hData->mFds[fi].mEvs[ei].mAzs.size();ai++)
                {
                    HrirAzT *azd = &hData->mFds[fi].mEvs[ei].mAzs[ai];
                    azd->mIrs[ti] = hrirs.subspan(
                        (ti*size_t{hData->mIrCount} + azd->mIndex) * hData->mIrSize,
                        hData->mIrSize);
                }
            }
        }
    }
    if(!TrLoad(tr))
    {
        gSofaCache.clear();
        return 1;
    }

    TrError(tr, "Errant data at end of source list.\n");
    gSofaCache.clear();
    return 0;
}

} /* namespace */

bool LoadDefInput(std::istream &istream, const al::span<const char> startbytes,
    const std::string_view filename, const uint fftSize, const uint truncSize, const uint outRate,
    const ChannelModeT chanMode, HrirDataT *hData)
{
    TokenReaderT tr{istream};

    TrSetup(startbytes, filename, &tr);
    if(!ProcessMetrics(&tr, fftSize, truncSize, chanMode, hData)
        || !ProcessSources(&tr, hData, outRate))
        return false;

    return true;
}
