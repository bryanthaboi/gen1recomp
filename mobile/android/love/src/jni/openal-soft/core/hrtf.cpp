
#include "config.h"

#include "hrtf.h"

#include <algorithm>
#include <array>
#include <cassert>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <memory>
#include <mutex>
#include <numeric>
#include <optional>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

#include "albit.h"
#include "almalloc.h"
#include "alnumbers.h"
#include "alnumeric.h"
#include "alspan.h"
#include "alstring.h"
#include "ambidefs.h"
#include "filters/splitter.h"
#include "helpers.h"
#include "logging.h"
#include "mixer/hrtfdefs.h"
#include "opthelpers.h"
#include "polyphase_resampler.h"


namespace {

using namespace std::string_view_literals;

struct HrtfEntry {
    std::string mDispName;
    std::string mFilename;

    template<typename T, typename U>
    HrtfEntry(T&& dispname, U&& fname)
        : mDispName{std::forward<T>(dispname)}, mFilename{std::forward<U>(fname)}
    { }
    /* GCC warns when it tries to inline this. */
    ~HrtfEntry();
};
HrtfEntry::~HrtfEntry() = default;

struct LoadedHrtf {
    std::string mFilename;
    uint mSampleRate{};
    std::unique_ptr<HrtfStore> mEntry;

    template<typename T, typename U>
    LoadedHrtf(T&& name, uint srate, U&& entry)
        : mFilename{std::forward<T>(name)}, mSampleRate{srate}, mEntry{std::forward<U>(entry)}
    { }
    LoadedHrtf(LoadedHrtf&&) = default;
    /* GCC warns when it tries to inline this. */
    ~LoadedHrtf();

    LoadedHrtf& operator=(LoadedHrtf&&) = default;
};
LoadedHrtf::~LoadedHrtf() = default;


/* Data set limits must be the same as or more flexible than those defined in
 * the makemhr utility.
 */
constexpr uint MinFdCount{1};
constexpr uint MaxFdCount{16};

constexpr uint MinFdDistance{50};
constexpr uint MaxFdDistance{2500};

constexpr uint MinEvCount{5};
constexpr uint MaxEvCount{181};

constexpr uint MinAzCount{1};
constexpr uint MaxAzCount{255};

constexpr uint MaxHrirDelay{HrtfHistoryLength - 1};

constexpr uint HrirDelayFracBits{2};
constexpr uint HrirDelayFracOne{1 << HrirDelayFracBits};
constexpr uint HrirDelayFracHalf{HrirDelayFracOne >> 1};

/* The sample rate is stored as a 24-bit integer, so 16MHz is the largest
 * supported.
 */
constexpr uint MaxSampleRate{0xff'ff'ff};

static_assert(MaxHrirDelay*HrirDelayFracOne < 256, "MAX_HRIR_DELAY or DELAY_FRAC too large");


[[nodiscard]] constexpr auto GetMarker00Name() noexcept { return "MinPHR00"sv; }
[[nodiscard]] constexpr auto GetMarker01Name() noexcept { return "MinPHR01"sv; }
[[nodiscard]] constexpr auto GetMarker02Name() noexcept { return "MinPHR02"sv; }
[[nodiscard]] constexpr auto GetMarker03Name() noexcept { return "MinPHR03"sv; }


/* First value for pass-through coefficients (remaining are 0), used for omni-
 * directional sounds. */
constexpr auto PassthruCoeff = static_cast<float>(1.0/al::numbers::sqrt2);

std::mutex LoadedHrtfLock;
std::vector<LoadedHrtf> LoadedHrtfs;

std::mutex EnumeratedHrtfLock;
std::vector<HrtfEntry> EnumeratedHrtfs;


/* NOLINTBEGIN(cppcoreguidelines-pro-bounds-pointer-arithmetic)
 * To access a memory buffer through the std::istream interface, a custom
 * std::streambuf implementation is needed that has to do pointer manipulation
 * for seeking. With C++23, we may be able to use std::spanstream instead.
 */
class databuf final : public std::streambuf {
    int_type underflow() override
    { return traits_type::eof(); }

    pos_type seekoff(off_type offset, std::ios_base::seekdir whence, std::ios_base::openmode mode) override
    {
        if((mode&std::ios_base::out) || !(mode&std::ios_base::in))
            return traits_type::eof();

        switch(whence)
        {
        case std::ios_base::beg:
            if(offset < 0 || offset > egptr()-eback())
                return traits_type::eof();
            setg(eback(), eback()+offset, egptr());
            break;

        case std::ios_base::cur:
            if((offset >= 0 && offset > egptr()-gptr()) ||
                (offset < 0 && -offset > gptr()-eback()))
                return traits_type::eof();
            setg(eback(), gptr()+offset, egptr());
            break;

        case std::ios_base::end:
            if(offset > 0 || -offset > egptr()-eback())
                return traits_type::eof();
            setg(eback(), egptr()+offset, egptr());
            break;

        default:
            return traits_type::eof();
        }

        return gptr() - eback();
    }

    pos_type seekpos(pos_type pos, std::ios_base::openmode mode) override
    {
        // Simplified version of seekoff
        if((mode&std::ios_base::out) || !(mode&std::ios_base::in))
            return traits_type::eof();

        if(pos < 0 || pos > egptr()-eback())
            return traits_type::eof();

        setg(eback(), eback()+static_cast<size_t>(pos), egptr());
        return pos;
    }

public:
    databuf(const al::span<char_type> data) noexcept
    {
        setg(data.data(), data.data(), al::to_address(data.end()));
    }
};
/* NOLINTEND(cppcoreguidelines-pro-bounds-pointer-arithmetic) */

class idstream final : public std::istream {
    databuf mStreamBuf;

public:
    idstream(const al::span<char_type> data) : std::istream{nullptr}, mStreamBuf{data}
    { init(&mStreamBuf); }
};


struct IdxBlend { uint idx; float blend; };
/* Calculate the elevation index given the polar elevation in radians. This
 * will return an index between 0 and (evcount - 1).
 */
IdxBlend CalcEvIndex(uint evcount, float ev)
{
    ev = (al::numbers::pi_v<float>*0.5f + ev) * static_cast<float>(evcount-1) *
        al::numbers::inv_pi_v<float>;
    uint idx{float2uint(ev)};

    return IdxBlend{std::min(idx, evcount-1u), ev-static_cast<float>(idx)};
}

/* Calculate the azimuth index given the polar azimuth in radians. This will
 * return an index between 0 and (azcount - 1).
 */
IdxBlend CalcAzIndex(uint azcount, float az)
{
    az = (al::numbers::pi_v<float>*2.0f + az) * static_cast<float>(azcount) *
        (al::numbers::inv_pi_v<float>*0.5f);
    uint idx{float2uint(az)};

    return IdxBlend{idx%azcount, az-static_cast<float>(idx)};
}

} // namespace


/* Calculates static HRIR coefficients and delays for the given polar elevation
 * and azimuth in radians. The coefficients are normalized.
 */
void HrtfStore::getCoeffs(float elevation, float azimuth, float distance, float spread,
    const HrirSpan coeffs, const al::span<uint,2> delays) const
{
    const float dirfact{1.0f - (al::numbers::inv_pi_v<float>/2.0f * spread)};

    size_t ebase{0};
    auto match_field = [&ebase,distance](const Field &field) noexcept -> bool
    {
        if(distance >= field.distance)
            return true;
        ebase += field.evCount;
        return false;
    };
    auto field = std::find_if(mFields.begin(), mFields.end()-1, match_field);

    /* Calculate the elevation indices. */
    const auto elev0 = CalcEvIndex(field->evCount, elevation);
    const size_t elev1_idx{std::min(elev0.idx+1u, field->evCount-1u)};
    const size_t ir0offset{mElev[ebase + elev0.idx].irOffset};
    const size_t ir1offset{mElev[ebase + elev1_idx].irOffset};

    /* Calculate azimuth indices. */
    const auto az0 = CalcAzIndex(mElev[ebase + elev0.idx].azCount, azimuth);
    const auto az1 = CalcAzIndex(mElev[ebase + elev1_idx].azCount, azimuth);

    /* Calculate the HRIR indices to blend. */
    const std::array<size_t,4> idx{{
        ir0offset + az0.idx,
        ir0offset + ((az0.idx+1) % mElev[ebase + elev0.idx].azCount),
        ir1offset + az1.idx,
        ir1offset + ((az1.idx+1) % mElev[ebase + elev1_idx].azCount)
    }};

    /* Calculate bilinear blending weights, attenuated according to the
     * directional panning factor.
     */
    const std::array<float,4> blend{{
        (1.0f-elev0.blend) * (1.0f-az0.blend) * dirfact,
        (1.0f-elev0.blend) * (     az0.blend) * dirfact,
        (     elev0.blend) * (1.0f-az1.blend) * dirfact,
        (     elev0.blend) * (     az1.blend) * dirfact
    }};

    /* Calculate the blended HRIR delays. */
    float d{float(mDelays[idx[0]][0])*blend[0] + float(mDelays[idx[1]][0])*blend[1]
        + float(mDelays[idx[2]][0])*blend[2] + float(mDelays[idx[3]][0])*blend[3]};
    delays[0] = fastf2u(d * float{1.0f/HrirDelayFracOne});
    d = float(mDelays[idx[0]][1])*blend[0] + float(mDelays[idx[1]][1])*blend[1]
        + float(mDelays[idx[2]][1])*blend[2] + float(mDelays[idx[3]][1])*blend[3];
    delays[1] = fastf2u(d * float{1.0f/HrirDelayFracOne});

    /* Calculate the blended HRIR coefficients. */
    auto coeffout = coeffs.begin();
    coeffout[0][0] = PassthruCoeff * (1.0f-dirfact);
    coeffout[0][1] = PassthruCoeff * (1.0f-dirfact);
    std::fill_n(coeffout+1, size_t{HrirLength-1}, std::array{0.0f, 0.0f});
    for(size_t c{0};c < 4;c++)
    {
        const float mult{blend[c]};
        auto blend_coeffs = [mult](const float2 &src, const float2 &coeff) noexcept -> float2
        { return float2{{src[0]*mult + coeff[0], src[1]*mult + coeff[1]}}; };
        std::transform(mCoeffs[idx[c]].cbegin(), mCoeffs[idx[c]].cend(), coeffout, coeffout,
            blend_coeffs);
    }
}


std::unique_ptr<DirectHrtfState> DirectHrtfState::Create(size_t num_chans)
{ return std::unique_ptr<DirectHrtfState>{new(FamCount(num_chans)) DirectHrtfState{num_chans}}; }

void DirectHrtfState::build(const HrtfStore *Hrtf, const uint irSize, const bool perHrirMin,
    const al::span<const AngularPoint> AmbiPoints,
    const al::span<const std::array<float,MaxAmbiChannels>> AmbiMatrix,
    const float XOverFreq, const al::span<const float,MaxAmbiOrder+1> AmbiOrderHFGain)
{
    using double2 = std::array<double,2>;
    struct ImpulseResponse {
        const ConstHrirSpan hrir;
        uint ldelay, rdelay;
    };

    const double xover_norm{double{XOverFreq} / Hrtf->mSampleRate};
    mChannels[0].mSplitter.init(static_cast<float>(xover_norm));
    mChannels[0].mHfScale = AmbiOrderHFGain[0];
    for(size_t i{1};i < mChannels.size();++i)
    {
        const size_t order{AmbiIndex::OrderFromChannel[i]};
        mChannels[i].mSplitter = mChannels[0].mSplitter;
        mChannels[i].mHfScale = AmbiOrderHFGain[order];
    }

    uint min_delay{HrtfHistoryLength*HrirDelayFracOne}, max_delay{0};
    std::vector<ImpulseResponse> impres; impres.reserve(AmbiPoints.size());
    auto calc_res = [Hrtf,&max_delay,&min_delay](const AngularPoint &pt) -> ImpulseResponse
    {
        auto &field = Hrtf->mFields[0];
        const auto elev0 = CalcEvIndex(field.evCount, pt.Elev.value);
        const size_t elev1_idx{std::min(elev0.idx+1u, field.evCount-1u)};
        const size_t ir0offset{Hrtf->mElev[elev0.idx].irOffset};
        const size_t ir1offset{Hrtf->mElev[elev1_idx].irOffset};

        const auto az0 = CalcAzIndex(Hrtf->mElev[elev0.idx].azCount, pt.Azim.value);
        const auto az1 = CalcAzIndex(Hrtf->mElev[elev1_idx].azCount, pt.Azim.value);

        const std::array<size_t,4> idx{
            ir0offset + az0.idx,
            ir0offset + ((az0.idx+1) % Hrtf->mElev[elev0.idx].azCount),
            ir1offset + az1.idx,
            ir1offset + ((az1.idx+1) % Hrtf->mElev[elev1_idx].azCount)
        };

        /* The largest blend factor serves as the closest HRIR. */
        const size_t irOffset{idx[(elev0.blend >= 0.5f)*2 + (az1.blend >= 0.5f)]};
        ImpulseResponse res{Hrtf->mCoeffs[irOffset],
            Hrtf->mDelays[irOffset][0], Hrtf->mDelays[irOffset][1]};

        min_delay = std::min(min_delay, std::min(res.ldelay, res.rdelay));
        max_delay = std::max(max_delay, std::max(res.ldelay, res.rdelay));

        return res;
    };
    std::transform(AmbiPoints.begin(), AmbiPoints.end(), std::back_inserter(impres), calc_res);
    auto hrir_delay_round = [](const uint d) noexcept -> uint
    { return (d+HrirDelayFracHalf) >> HrirDelayFracBits; };

    TRACE("Min delay: %.2f, max delay: %.2f, FIR length: %u\n",
        min_delay/double{HrirDelayFracOne}, max_delay/double{HrirDelayFracOne}, irSize);

    auto tmpres = std::vector<std::array<double2,HrirLength>>(mChannels.size());
    max_delay = 0;
    auto matrixline = AmbiMatrix.cbegin();
    for(auto &impulse : impres)
    {
        const ConstHrirSpan hrir{impulse.hrir};
        const uint base_delay{perHrirMin ? std::min(impulse.ldelay, impulse.rdelay) : min_delay};
        const uint ldelay{hrir_delay_round(impulse.ldelay - base_delay)};
        const uint rdelay{hrir_delay_round(impulse.rdelay - base_delay)};
        max_delay = std::max(max_delay, std::max(impulse.ldelay, impulse.rdelay) - base_delay);

        auto gains = matrixline->cbegin();
        ++matrixline;
        for(auto &result : tmpres)
        {
            const double mult{*(gains++)};
            const size_t numirs{HrirLength - std::max(ldelay, rdelay)};
            size_t lidx{ldelay}, ridx{rdelay};
            for(size_t j{0};j < numirs;++j)
            {
                result[lidx++][0] += hrir[j][0] * mult;
                result[ridx++][1] += hrir[j][1] * mult;
            }
        }
    }
    impres.clear();

    auto output = mChannels.begin();
    for(auto &result : tmpres)
    {
        auto cast_array2 = [](const double2 &in) noexcept -> float2
        { return float2{{static_cast<float>(in[0]), static_cast<float>(in[1])}}; };
        std::transform(result.cbegin(), result.cend(), output->mCoeffs.begin(), cast_array2);
        ++output;
    }
    tmpres.clear();

    const uint max_length{std::min(hrir_delay_round(max_delay) + irSize, HrirLength)};
    TRACE("New max delay: %.2f, FIR length: %u\n", max_delay/double{HrirDelayFracOne},
        max_length);
    mIrSize = max_length;
}


namespace {

std::unique_ptr<HrtfStore> CreateHrtfStore(uint rate, uint8_t irSize,
    const al::span<const HrtfStore::Field> fields,
    const al::span<const HrtfStore::Elevation> elevs, const HrirArray *coeffs,
    const ubyte2 *delays)
{
    static_assert(alignof(HrtfStore::Field) <= alignof(HrtfStore));
    static_assert(alignof(HrtfStore::Elevation) <= alignof(HrtfStore));
    static_assert(16 <= alignof(HrtfStore));

    if(rate > MaxSampleRate)
        throw std::runtime_error{"Sample rate is too large (max: "+std::to_string(MaxSampleRate)+"hz)"};

    const size_t irCount{size_t{elevs.back().azCount} + elevs.back().irOffset};
    size_t total{sizeof(HrtfStore)};
    total  = RoundUp(total, alignof(HrtfStore::Field)); /* Align for field infos */
    total += sizeof(std::declval<HrtfStore&>().mFields[0])*fields.size();
    total  = RoundUp(total, alignof(HrtfStore::Elevation)); /* Align for elevation infos */
    total += sizeof(std::declval<HrtfStore&>().mElev[0])*elevs.size();
    total  = RoundUp(total, 16); /* Align for coefficients using SIMD */
    total += sizeof(std::declval<HrtfStore&>().mCoeffs[0])*irCount;
    total += sizeof(std::declval<HrtfStore&>().mDelays[0])*irCount;

    static constexpr auto AlignVal = std::align_val_t{alignof(HrtfStore)};
    std::unique_ptr<HrtfStore> Hrtf{::new(::operator new[](total, AlignVal)) HrtfStore{}};
    Hrtf->mRef.store(1u, std::memory_order_relaxed);
    Hrtf->mSampleRate = rate & 0xff'ff'ff;
    Hrtf->mIrSize = irSize;

    /* Set up pointers to storage following the main HRTF struct. */
    auto storage = al::span{reinterpret_cast<char*>(Hrtf.get()), total};
    auto base = storage.begin();
    ptrdiff_t offset{sizeof(HrtfStore)};

    offset = RoundUp(offset, alignof(HrtfStore::Field)); /* Align for field infos */
    auto field_ = al::span{reinterpret_cast<HrtfStore::Field*>(al::to_address(base + offset)),
        fields.size()};
    offset += ptrdiff_t(sizeof(field_[0])*fields.size());

    offset = RoundUp(offset, alignof(HrtfStore::Elevation)); /* Align for elevation infos */
    auto elev_ = al::span{reinterpret_cast<HrtfStore::Elevation*>(al::to_address(base + offset)),
        elevs.size()};
    offset += ptrdiff_t(sizeof(elev_[0])*elevs.size());

    offset = RoundUp(offset, 16); /* Align for coefficients using SIMD */
    auto coeffs_ = al::span{reinterpret_cast<HrirArray*>(al::to_address(base + offset)), irCount};
    offset += ptrdiff_t(sizeof(coeffs_[0])*irCount);

    auto delays_ = al::span{reinterpret_cast<ubyte2*>(al::to_address(base + offset)), irCount};
    offset += ptrdiff_t(sizeof(delays_[0])*irCount);

    if(size_t(offset) != total)
        throw std::runtime_error{"HrtfStore allocation size mismatch"};

    /* Copy input data to storage. */
    std::uninitialized_copy(fields.cbegin(), fields.cend(), field_.begin());
    std::uninitialized_copy(elevs.cbegin(), elevs.cend(), elev_.begin());
    std::uninitialized_copy_n(coeffs, irCount, coeffs_.begin());
    std::uninitialized_copy_n(delays, irCount, delays_.begin());

    /* Finally, assign the storage pointers. */
    Hrtf->mFields = field_;
    Hrtf->mElev = elev_;
    Hrtf->mCoeffs = coeffs_;
    Hrtf->mDelays = delays_;

    return Hrtf;
}

void MirrorLeftHrirs(const al::span<const HrtfStore::Elevation> elevs, al::span<HrirArray> coeffs,
    al::span<ubyte2> delays)
{
    for(const auto &elev : elevs)
    {
        const ushort evoffset{elev.irOffset};
        const ushort azcount{elev.azCount};
        for(size_t j{0};j < azcount;j++)
        {
            const size_t lidx{evoffset + j};
            const size_t ridx{evoffset + ((azcount-j) % azcount)};

            const size_t irSize{coeffs[ridx].size()};
            for(size_t k{0};k < irSize;k++)
                coeffs[ridx][k][1] = coeffs[lidx][k][0];
            delays[ridx][1] = delays[lidx][0];
        }
    }
}


template<size_t num_bits, typename T>
constexpr std::enable_if_t<std::is_signed<T>::value && num_bits < sizeof(T)*8,
T> fixsign(T value) noexcept
{
    constexpr auto signbit = static_cast<T>(1u << (num_bits-1));
    return static_cast<T>((value^signbit) - signbit);
}

template<size_t num_bits, typename T>
constexpr std::enable_if_t<!std::is_signed<T>::value || num_bits == sizeof(T)*8,
T> fixsign(T value) noexcept
{ return value; }

template<typename T, size_t num_bits=sizeof(T)*8>
inline std::enable_if_t<al::endian::native == al::endian::little,
T> readle(std::istream &data)
{
    static_assert((num_bits&7) == 0, "num_bits must be a multiple of 8");
    static_assert(num_bits <= sizeof(T)*8, "num_bits is too large for the type");

    alignas(T) std::array<char,sizeof(T)> ret{};
    if(!data.read(ret.data(), num_bits/8))
        return static_cast<T>(EOF);

    return fixsign<num_bits>(al::bit_cast<T>(ret));
}

template<typename T, size_t num_bits=sizeof(T)*8>
inline std::enable_if_t<al::endian::native == al::endian::big,
T> readle(std::istream &data)
{
    static_assert((num_bits&7) == 0, "num_bits must be a multiple of 8");
    static_assert(num_bits <= sizeof(T)*8, "num_bits is too large for the type");

    alignas(T) std::array<char,sizeof(T)> ret{};
    if(!data.read(ret.data(), num_bits/8))
        return static_cast<T>(EOF);
    std::reverse(ret.begin(), ret.end());

    return fixsign<num_bits>(al::bit_cast<T>(ret));
}

template<>
inline uint8_t readle<uint8_t,8>(std::istream &data)
{ return static_cast<uint8_t>(data.get()); }


std::unique_ptr<HrtfStore> LoadHrtf00(std::istream &data)
{
    uint rate{readle<uint32_t>(data)};
    ushort irCount{readle<uint16_t>(data)};
    ushort irSize{readle<uint16_t>(data)};
    ubyte evCount{readle<uint8_t>(data)};
    if(!data || data.eof())
        throw std::runtime_error{"Premature end of file"};

    if(irSize < MinIrLength || irSize > HrirLength)
    {
        ERR("Unsupported HRIR size, irSize=%d (%d to %d)\n", irSize, MinIrLength, HrirLength);
        return nullptr;
    }
    if(evCount < MinEvCount || evCount > MaxEvCount)
    {
        ERR("Unsupported elevation count: evCount=%d (%d to %d)\n",
            evCount, MinEvCount, MaxEvCount);
        return nullptr;
    }

    auto elevs = std::vector<HrtfStore::Elevation>(evCount);
    for(auto &elev : elevs)
        elev.irOffset = readle<uint16_t>(data);
    if(!data || data.eof())
        throw std::runtime_error{"Premature end of file"};

    for(size_t i{1};i < evCount;i++)
    {
        if(elevs[i].irOffset <= elevs[i-1].irOffset)
        {
            ERR("Invalid evOffset: evOffset[%zu]=%d (last=%d)\n", i, elevs[i].irOffset,
                elevs[i-1].irOffset);
            return nullptr;
        }
    }
    if(irCount <= elevs.back().irOffset)
    {
        ERR("Invalid evOffset: evOffset[%zu]=%d (irCount=%d)\n",
            elevs.size()-1, elevs.back().irOffset, irCount);
        return nullptr;
    }

    for(size_t i{1};i < evCount;i++)
    {
        elevs[i-1].azCount = static_cast<ushort>(elevs[i].irOffset - elevs[i-1].irOffset);
        if(elevs[i-1].azCount < MinAzCount || elevs[i-1].azCount > MaxAzCount)
        {
            ERR("Unsupported azimuth count: azCount[%zd]=%d (%d to %d)\n",
                i-1, elevs[i-1].azCount, MinAzCount, MaxAzCount);
            return nullptr;
        }
    }
    elevs.back().azCount = static_cast<ushort>(irCount - elevs.back().irOffset);
    if(elevs.back().azCount < MinAzCount || elevs.back().azCount > MaxAzCount)
    {
        ERR("Unsupported azimuth count: azCount[%zu]=%d (%d to %d)\n",
            elevs.size()-1, elevs.back().azCount, MinAzCount, MaxAzCount);
        return nullptr;
    }

    auto coeffs = std::vector<HrirArray>(irCount, HrirArray{});
    auto delays = std::vector<ubyte2>(irCount);
    for(auto &hrir : coeffs)
    {
        for(auto &val : al::span{hrir}.first(irSize))
            val[0] = float(readle<int16_t>(data)) / 32768.0f;
    }
    for(auto &val : delays)
        val[0] = readle<uint8_t>(data);
    if(!data || data.eof())
        throw std::runtime_error{"Premature end of file"};

    for(size_t i{0};i < irCount;i++)
    {
        if(delays[i][0] > MaxHrirDelay)
        {
            ERR("Invalid delays[%zd]: %d (%d)\n", i, delays[i][0], MaxHrirDelay);
            return nullptr;
        }
        delays[i][0] <<= HrirDelayFracBits;
    }

    /* Mirror the left ear responses to the right ear. */
    MirrorLeftHrirs(elevs, coeffs, delays);

    const std::array field{HrtfStore::Field{0.0f, evCount}};
    return CreateHrtfStore(rate, static_cast<uint8_t>(irSize), field, elevs, coeffs.data(),
        delays.data());
}

std::unique_ptr<HrtfStore> LoadHrtf01(std::istream &data)
{
    uint rate{readle<uint32_t>(data)};
    uint8_t irSize{readle<uint8_t>(data)};
    ubyte evCount{readle<uint8_t>(data)};
    if(!data || data.eof())
        throw std::runtime_error{"Premature end of file"};

    if(irSize < MinIrLength || irSize > HrirLength)
    {
        ERR("Unsupported HRIR size, irSize=%d (%d to %d)\n", irSize, MinIrLength, HrirLength);
        return nullptr;
    }
    if(evCount < MinEvCount || evCount > MaxEvCount)
    {
        ERR("Unsupported elevation count: evCount=%d (%d to %d)\n",
            evCount, MinEvCount, MaxEvCount);
        return nullptr;
    }

    auto elevs = std::vector<HrtfStore::Elevation>(evCount);
    for(auto &elev : elevs)
        elev.azCount = readle<uint8_t>(data);
    if(!data || data.eof())
        throw std::runtime_error{"Premature end of file"};

    for(size_t i{0};i < evCount;++i)
    {
        if(elevs[i].azCount < MinAzCount || elevs[i].azCount > MaxAzCount)
        {
            ERR("Unsupported azimuth count: azCount[%zd]=%d (%d to %d)\n", i, elevs[i].azCount,
                MinAzCount, MaxAzCount);
            return nullptr;
        }
    }

    elevs[0].irOffset = 0;
    for(size_t i{1};i < evCount;i++)
        elevs[i].irOffset = static_cast<ushort>(elevs[i-1].irOffset + elevs[i-1].azCount);
    const ushort irCount{static_cast<ushort>(elevs.back().irOffset + elevs.back().azCount)};

    auto coeffs = std::vector<HrirArray>(irCount, HrirArray{});
    auto delays = std::vector<ubyte2>(irCount);
    for(auto &hrir : coeffs)
    {
        for(auto &val : al::span{hrir}.first(irSize))
            val[0] = float(readle<int16_t>(data)) / 32768.0f;
    }
    for(auto &val : delays)
        val[0] = readle<uint8_t>(data);
    if(!data || data.eof())
        throw std::runtime_error{"Premature end of file"};

    for(size_t i{0};i < irCount;i++)
    {
        if(delays[i][0] > MaxHrirDelay)
        {
            ERR("Invalid delays[%zd]: %d (%d)\n", i, delays[i][0], MaxHrirDelay);
            return nullptr;
        }
        delays[i][0] <<= HrirDelayFracBits;
    }

    /* Mirror the left ear responses to the right ear. */
    MirrorLeftHrirs(elevs, coeffs, delays);

    const std::array field{HrtfStore::Field{0.0f, evCount}};
    return CreateHrtfStore(rate, irSize, field, elevs, coeffs.data(), delays.data());
}

std::unique_ptr<HrtfStore> LoadHrtf02(std::istream &data)
{
    static constexpr ubyte SampleType_S16{0};
    static constexpr ubyte SampleType_S24{1};
    static constexpr ubyte ChanType_LeftOnly{0};
    static constexpr ubyte ChanType_LeftRight{1};

    uint rate{readle<uint32_t>(data)};
    ubyte sampleType{readle<uint8_t>(data)};
    ubyte channelType{readle<uint8_t>(data)};
    uint8_t irSize{readle<uint8_t>(data)};
    ubyte fdCount{readle<uint8_t>(data)};
    if(!data || data.eof())
        throw std::runtime_error{"Premature end of file"};

    if(sampleType > SampleType_S24)
    {
        ERR("Unsupported sample type: %d\n", sampleType);
        return nullptr;
    }
    if(channelType > ChanType_LeftRight)
    {
        ERR("Unsupported channel type: %d\n", channelType);
        return nullptr;
    }

    if(irSize < MinIrLength || irSize > HrirLength)
    {
        ERR("Unsupported HRIR size, irSize=%d (%d to %d)\n", irSize, MinIrLength, HrirLength);
        return nullptr;
    }
    if(fdCount < 1 || fdCount > MaxFdCount)
    {
        ERR("Unsupported number of field-depths: fdCount=%d (%d to %d)\n", fdCount, MinFdCount,
            MaxFdCount);
        return nullptr;
    }

    auto fields = std::vector<HrtfStore::Field>(fdCount);
    auto elevs = std::vector<HrtfStore::Elevation>{};
    for(size_t f{0};f < fdCount;f++)
    {
        const ushort distance{readle<uint16_t>(data)};
        const ubyte evCount{readle<uint8_t>(data)};
        if(!data || data.eof())
            throw std::runtime_error{"Premature end of file"};

        if(distance < MinFdDistance || distance > MaxFdDistance)
        {
            ERR("Unsupported field distance[%zu]=%d (%d to %d millimeters)\n", f, distance,
                MinFdDistance, MaxFdDistance);
            return nullptr;
        }
        if(evCount < MinEvCount || evCount > MaxEvCount)
        {
            ERR("Unsupported elevation count: evCount[%zu]=%d (%d to %d)\n", f, evCount,
                MinEvCount, MaxEvCount);
            return nullptr;
        }

        fields[f].distance = float(distance) / 1000.0f;
        fields[f].evCount = evCount;
        if(f > 0 && fields[f].distance <= fields[f-1].distance)
        {
            ERR("Field distance[%zu] is not after previous (%f > %f)\n", f, fields[f].distance,
                fields[f-1].distance);
            return nullptr;
        }

        const size_t ebase{elevs.size()};
        elevs.resize(ebase + evCount);
        for(auto &elev : al::span{elevs}.subspan(ebase, evCount))
            elev.azCount = readle<uint8_t>(data);
        if(!data || data.eof())
            throw std::runtime_error{"Premature end of file"};

        for(size_t e{0};e < evCount;e++)
        {
            if(elevs[ebase+e].azCount < MinAzCount || elevs[ebase+e].azCount > MaxAzCount)
            {
                ERR("Unsupported azimuth count: azCount[%zu][%zu]=%d (%d to %d)\n", f, e,
                    elevs[ebase+e].azCount, MinAzCount, MaxAzCount);
                return nullptr;
            }
        }
    }

    elevs[0].irOffset = 0;
    std::partial_sum(elevs.cbegin(), elevs.cend(), elevs.begin(),
        [](const HrtfStore::Elevation &last, const HrtfStore::Elevation &cur)
            -> HrtfStore::Elevation
        {
            return HrtfStore::Elevation{cur.azCount,
                static_cast<ushort>(last.azCount + last.irOffset)};
        });
    const auto irTotal = static_cast<ushort>(elevs.back().azCount + elevs.back().irOffset);

    auto coeffs = std::vector<HrirArray>(irTotal, HrirArray{});
    auto delays = std::vector<ubyte2>(irTotal);
    if(channelType == ChanType_LeftOnly)
    {
        if(sampleType == SampleType_S16)
        {
            for(auto &hrir : coeffs)
            {
                for(auto &val : al::span{hrir}.first(irSize))
                    val[0] = float(readle<int16_t>(data)) / 32768.0f;
            }
        }
        else if(sampleType == SampleType_S24)
        {
            for(auto &hrir : coeffs)
            {
                for(auto &val : al::span{hrir}.first(irSize))
                    val[0] = static_cast<float>(readle<int,24>(data)) / 8388608.0f;
            }
        }
        for(auto &val : delays)
            val[0] = readle<uint8_t>(data);
        if(!data || data.eof())
            throw std::runtime_error{"Premature end of file"};

        for(size_t i{0};i < irTotal;++i)
        {
            if(delays[i][0] > MaxHrirDelay)
            {
                ERR("Invalid delays[%zu][0]: %d (%d)\n", i, delays[i][0], MaxHrirDelay);
                return nullptr;
            }
            delays[i][0] <<= HrirDelayFracBits;
        }

        /* Mirror the left ear responses to the right ear. */
        MirrorLeftHrirs(elevs, coeffs, delays);
    }
    else if(channelType == ChanType_LeftRight)
    {
        if(sampleType == SampleType_S16)
        {
            for(auto &hrir : coeffs)
            {
                for(auto &val : al::span{hrir}.first(irSize))
                {
                    val[0] = float(readle<int16_t>(data)) / 32768.0f;
                    val[1] = float(readle<int16_t>(data)) / 32768.0f;
                }
            }
        }
        else if(sampleType == SampleType_S24)
        {
            for(auto &hrir : coeffs)
            {
                for(auto &val : al::span{hrir}.first(irSize))
                {
                    val[0] = static_cast<float>(readle<int,24>(data)) / 8388608.0f;
                    val[1] = static_cast<float>(readle<int,24>(data)) / 8388608.0f;
                }
            }
        }
        for(auto &val : delays)
        {
            val[0] = readle<uint8_t>(data);
            val[1] = readle<uint8_t>(data);
        }
        if(!data || data.eof())
            throw std::runtime_error{"Premature end of file"};

        for(size_t i{0};i < irTotal;++i)
        {
            if(delays[i][0] > MaxHrirDelay)
            {
                ERR("Invalid delays[%zu][0]: %d (%d)\n", i, delays[i][0], MaxHrirDelay);
                return nullptr;
            }
            if(delays[i][1] > MaxHrirDelay)
            {
                ERR("Invalid delays[%zu][1]: %d (%d)\n", i, delays[i][1], MaxHrirDelay);
                return nullptr;
            }
            delays[i][0] <<= HrirDelayFracBits;
            delays[i][1] <<= HrirDelayFracBits;
        }
    }

    if(fdCount > 1)
    {
        auto fields_ = std::vector<HrtfStore::Field>(fields.size());
        auto elevs_ = std::vector<HrtfStore::Elevation>(elevs.size());
        auto coeffs_ = std::vector<HrirArray>(coeffs.size());
        auto delays_ = std::vector<ubyte2>(delays.size());

        /* Simple reverse for the per-field elements. */
        std::reverse_copy(fields.cbegin(), fields.cend(), fields_.begin());

        /* Each field has a group of elevations, which each have an azimuth
         * count. Reverse the order of the groups, keeping the relative order
         * of per-group azimuth counts.
         */
        auto elevs_end = elevs_.end();
        auto copy_azs = [&elevs,&elevs_end](const ptrdiff_t ebase, const HrtfStore::Field &field)
            -> ptrdiff_t
        {
            auto elevs_src = elevs.begin()+ebase;
            elevs_end = std::copy_backward(elevs_src, elevs_src+field.evCount, elevs_end);
            return ebase + field.evCount;
        };
        std::ignore = std::accumulate(fields.cbegin(), fields.cend(), ptrdiff_t{0}, copy_azs);
        assert(elevs_.begin() == elevs_end);

        /* Reestablish the IR offset for each elevation index, given the new
         * ordering of elevations.
         */
        elevs_[0].irOffset = 0;
        std::partial_sum(elevs_.cbegin(), elevs_.cend(), elevs_.begin(),
            [](const HrtfStore::Elevation &last, const HrtfStore::Elevation &cur)
                -> HrtfStore::Elevation
            {
                return HrtfStore::Elevation{cur.azCount,
                    static_cast<ushort>(last.azCount + last.irOffset)};
            });

        /* Reverse the order of each field's group of IRs. */
        auto coeffs_end = coeffs_.end();
        auto delays_end = delays_.end();
        auto copy_irs = [&elevs,&coeffs,&delays,&coeffs_end,&delays_end](
            const ptrdiff_t ebase, const HrtfStore::Field &field) -> ptrdiff_t
        {
            auto accum_az = [](const ptrdiff_t count, const HrtfStore::Elevation &elev) noexcept
                -> ptrdiff_t
            { return count + elev.azCount; };
            const auto elev_mid = elevs.cbegin() + ebase;
            const auto abase = std::accumulate(elevs.cbegin(), elev_mid, ptrdiff_t{0}, accum_az);
            const auto num_azs = std::accumulate(elev_mid, elev_mid + field.evCount, ptrdiff_t{0},
                accum_az);

            coeffs_end = std::copy_backward(coeffs.cbegin() + abase,
                coeffs.cbegin() + (abase+num_azs), coeffs_end);
            delays_end = std::copy_backward(delays.cbegin() + abase,
                delays.cbegin() + (abase+num_azs), delays_end);

            return ebase + field.evCount;
        };
        std::ignore = std::accumulate(fields.cbegin(), fields.cend(), ptrdiff_t{0}, copy_irs);
        assert(coeffs_.begin() == coeffs_end);
        assert(delays_.begin() == delays_end);

        fields = std::move(fields_);
        elevs = std::move(elevs_);
        coeffs = std::move(coeffs_);
        delays = std::move(delays_);
    }

    return CreateHrtfStore(rate, irSize, fields, elevs, coeffs.data(), delays.data());
}

std::unique_ptr<HrtfStore> LoadHrtf03(std::istream &data)
{
    static constexpr ubyte ChanType_LeftOnly{0};
    static constexpr ubyte ChanType_LeftRight{1};

    uint rate{readle<uint32_t>(data)};
    ubyte channelType{readle<uint8_t>(data)};
    uint8_t irSize{readle<uint8_t>(data)};
    ubyte fdCount{readle<uint8_t>(data)};
    if(!data || data.eof())
        throw std::runtime_error{"Premature end of file"};

    if(channelType > ChanType_LeftRight)
    {
        ERR("Unsupported channel type: %d\n", channelType);
        return nullptr;
    }

    if(irSize < MinIrLength || irSize > HrirLength)
    {
        ERR("Unsupported HRIR size, irSize=%d (%d to %d)\n", irSize, MinIrLength, HrirLength);
        return nullptr;
    }
    if(fdCount < 1 || fdCount > MaxFdCount)
    {
        ERR("Unsupported number of field-depths: fdCount=%d (%d to %d)\n", fdCount, MinFdCount,
            MaxFdCount);
        return nullptr;
    }

    auto fields = std::vector<HrtfStore::Field>(fdCount);
    auto elevs = std::vector<HrtfStore::Elevation>{};
    for(size_t f{0};f < fdCount;f++)
    {
        const ushort distance{readle<uint16_t>(data)};
        const ubyte evCount{readle<uint8_t>(data)};
        if(!data || data.eof())
            throw std::runtime_error{"Premature end of file"};

        if(distance < MinFdDistance || distance > MaxFdDistance)
        {
            ERR("Unsupported field distance[%zu]=%d (%d to %d millimeters)\n", f, distance,
                MinFdDistance, MaxFdDistance);
            return nullptr;
        }
        if(evCount < MinEvCount || evCount > MaxEvCount)
        {
            ERR("Unsupported elevation count: evCount[%zu]=%d (%d to %d)\n", f, evCount,
                MinEvCount, MaxEvCount);
            return nullptr;
        }

        fields[f].distance = float(distance) / 1000.0f;
        fields[f].evCount = evCount;
        if(f > 0 && fields[f].distance > fields[f-1].distance)
        {
            ERR("Field distance[%zu] is not before previous (%f <= %f)\n", f, fields[f].distance,
                fields[f-1].distance);
            return nullptr;
        }

        const size_t ebase{elevs.size()};
        elevs.resize(ebase + evCount);
        for(auto &elev : al::span{elevs}.subspan(ebase, evCount))
            elev.azCount = readle<uint8_t>(data);
        if(!data || data.eof())
            throw std::runtime_error{"Premature end of file"};

        for(size_t e{0};e < evCount;e++)
        {
            if(elevs[ebase+e].azCount < MinAzCount || elevs[ebase+e].azCount > MaxAzCount)
            {
                ERR("Unsupported azimuth count: azCount[%zu][%zu]=%d (%d to %d)\n", f, e,
                    elevs[ebase+e].azCount, MinAzCount, MaxAzCount);
                return nullptr;
            }
        }
    }

    elevs[0].irOffset = 0;
    std::partial_sum(elevs.cbegin(), elevs.cend(), elevs.begin(),
        [](const HrtfStore::Elevation &last, const HrtfStore::Elevation &cur)
            -> HrtfStore::Elevation
        {
            return HrtfStore::Elevation{cur.azCount,
                static_cast<ushort>(last.azCount + last.irOffset)};
        });
    const auto irTotal = static_cast<ushort>(elevs.back().azCount + elevs.back().irOffset);

    auto coeffs = std::vector<HrirArray>(irTotal, HrirArray{});
    auto delays = std::vector<ubyte2>(irTotal);
    if(channelType == ChanType_LeftOnly)
    {
        for(auto &hrir : coeffs)
        {
            for(auto &val : al::span{hrir}.first(irSize))
                val[0] = static_cast<float>(readle<int,24>(data)) / 8388608.0f;
        }
        for(auto &val : delays)
            val[0] = readle<uint8_t>(data);
        if(!data || data.eof())
            throw std::runtime_error{"Premature end of file"};

        for(size_t i{0};i < irTotal;++i)
        {
            if(delays[i][0] > MaxHrirDelay<<HrirDelayFracBits)
            {
                ERR("Invalid delays[%zu][0]: %f (%d)\n", i,
                    delays[i][0] / float{HrirDelayFracOne}, MaxHrirDelay);
                return nullptr;
            }
        }

        /* Mirror the left ear responses to the right ear. */
        MirrorLeftHrirs(elevs, coeffs, delays);
    }
    else if(channelType == ChanType_LeftRight)
    {
        for(auto &hrir : coeffs)
        {
            for(auto &val : al::span{hrir}.first(irSize))
            {
                val[0] = static_cast<float>(readle<int,24>(data)) / 8388608.0f;
                val[1] = static_cast<float>(readle<int,24>(data)) / 8388608.0f;
            }
        }
        for(auto &val : delays)
        {
            val[0] = readle<uint8_t>(data);
            val[1] = readle<uint8_t>(data);
        }
        if(!data || data.eof())
            throw std::runtime_error{"Premature end of file"};

        for(size_t i{0};i < irTotal;++i)
        {
            if(delays[i][0] > MaxHrirDelay<<HrirDelayFracBits)
            {
                ERR("Invalid delays[%zu][0]: %f (%d)\n", i,
                    delays[i][0] / float{HrirDelayFracOne}, MaxHrirDelay);
                return nullptr;
            }
            if(delays[i][1] > MaxHrirDelay<<HrirDelayFracBits)
            {
                ERR("Invalid delays[%zu][1]: %f (%d)\n", i,
                    delays[i][1] / float{HrirDelayFracOne}, MaxHrirDelay);
                return nullptr;
            }
        }
    }

    return CreateHrtfStore(rate, irSize, fields, elevs, coeffs.data(), delays.data());
}


bool checkName(const std::string_view name)
{
    auto match_name = [name](const HrtfEntry &entry) -> bool { return name == entry.mDispName; };
    auto &enum_names = EnumeratedHrtfs;
    return std::find_if(enum_names.cbegin(), enum_names.cend(), match_name) != enum_names.cend();
}

void AddFileEntry(const std::string_view filename)
{
    /* Check if this file has already been enumerated. */
    auto enum_iter = std::find_if(EnumeratedHrtfs.cbegin(), EnumeratedHrtfs.cend(),
        [filename](const HrtfEntry &entry) -> bool
        { return entry.mFilename == filename; });
    if(enum_iter != EnumeratedHrtfs.cend())
    {
        TRACE("Skipping duplicate file entry %.*s\n", al::sizei(filename), filename.data());
        return;
    }

    /* TODO: Get a human-readable name from the HRTF data (possibly coming in a
     * format update). */
    size_t namepos{filename.rfind('/')+1};
    if(!namepos) namepos = filename.rfind('\\')+1;

    size_t extpos{filename.rfind('.')};
    if(extpos <= namepos) extpos = std::string::npos;

    const std::string_view basename{(extpos == std::string::npos) ?
        filename.substr(namepos) : filename.substr(namepos, extpos-namepos)};
    std::string newname{basename};
    int count{1};
    while(checkName(newname))
    {
        newname = basename;
        newname += " #";
        newname += std::to_string(++count);
    }
    const HrtfEntry &entry = EnumeratedHrtfs.emplace_back(newname, filename);

    TRACE("Adding file entry \"%s\"\n", entry.mFilename.c_str());
}

/* Unfortunate that we have to duplicate AddFileEntry to take a memory buffer
 * for input instead of opening the given filename.
 */
void AddBuiltInEntry(const std::string_view dispname, uint residx)
{
    std::string filename{'!'+std::to_string(residx)+'_'};
    filename += dispname;

    auto enum_iter = std::find_if(EnumeratedHrtfs.cbegin(), EnumeratedHrtfs.cend(),
        [&filename](const HrtfEntry &entry) -> bool
        { return entry.mFilename == filename; });
    if(enum_iter != EnumeratedHrtfs.cend())
    {
        TRACE("Skipping duplicate file entry %s\n", filename.c_str());
        return;
    }

    /* TODO: Get a human-readable name from the HRTF data (possibly coming in a
     * format update). */

    std::string newname{dispname};
    int count{1};
    while(checkName(newname))
    {
        newname = dispname;
        newname += " #";
        newname += std::to_string(++count);
    }
    const HrtfEntry &entry = EnumeratedHrtfs.emplace_back(std::move(newname), std::move(filename));

    TRACE("Adding built-in entry \"%s\"\n", entry.mFilename.c_str());
}


#define IDR_DEFAULT_HRTF_MHR 1

#ifndef ALSOFT_EMBED_HRTF_DATA

al::span<const char> GetResource(int /*name*/)
{ return {}; }

#else

/* NOLINTNEXTLINE(*-avoid-c-arrays) */
constexpr unsigned char hrtf_default[]{
#include "default_hrtf.txt"
};

al::span<const char> GetResource(int name)
{
    if(name == IDR_DEFAULT_HRTF_MHR)
        return {reinterpret_cast<const char*>(hrtf_default), sizeof(hrtf_default)};
    return {};
}
#endif

} // namespace


std::vector<std::string> EnumerateHrtf(std::optional<std::string> pathopt)
{
    std::lock_guard<std::mutex> enumlock{EnumeratedHrtfLock};
    EnumeratedHrtfs.clear();

    for(const auto &fname : SearchDataFiles(".mhr"sv))
        AddFileEntry(fname);

    bool usedefaults{true};
    if(pathopt)
    {
        std::string_view pathlist{*pathopt};
        while(!pathlist.empty())
        {
            while(!pathlist.empty() && (std::isspace(pathlist.front()) || pathlist.front() == ','))
                pathlist.remove_prefix(1);
            if(pathlist.empty())
                break;

            auto endpos = std::min(pathlist.find(','), pathlist.size());
            auto entry = pathlist.substr(0, endpos);
            if(endpos < pathlist.size())
                pathlist.remove_prefix(++endpos);
            else
            {
                pathlist.remove_prefix(endpos);
                usedefaults = false;
            }

            while(!entry.empty() && std::isspace(entry.back()))
                entry.remove_suffix(1);
            if(!entry.empty())
            {
                for(const auto &fname : SearchDataFiles(".mhr"sv, entry))
                    AddFileEntry(fname);
            }
        }
    }

    if(usedefaults)
    {
        for(const auto &fname : SearchDataFiles(".mhr"sv, "openal/hrtf"sv))
            AddFileEntry(fname);

        if(!GetResource(IDR_DEFAULT_HRTF_MHR).empty())
            AddBuiltInEntry("Built-In HRTF", IDR_DEFAULT_HRTF_MHR);
    }

    std::vector<std::string> list;
    list.reserve(EnumeratedHrtfs.size());
    for(auto &entry : EnumeratedHrtfs)
        list.emplace_back(entry.mDispName);

    return list;
}

HrtfStorePtr GetLoadedHrtf(const std::string_view name, const uint devrate)
try {
    if(devrate > MaxSampleRate)
    {
        WARN("Device sample rate too large for HRTF (%uhz > %uhz)\n", devrate, MaxSampleRate);
        return nullptr;
    }
    std::lock_guard<std::mutex> enumlock{EnumeratedHrtfLock};
    auto entry_iter = std::find_if(EnumeratedHrtfs.cbegin(), EnumeratedHrtfs.cend(),
        [name](const HrtfEntry &entry) -> bool { return entry.mDispName == name; });
    if(entry_iter == EnumeratedHrtfs.cend())
        return nullptr;
    const std::string &fname = entry_iter->mFilename;

    std::lock_guard<std::mutex> loadlock{LoadedHrtfLock};
    auto hrtf_lt_fname = [devrate](LoadedHrtf &hrtf, const std::string_view filename) -> bool
    {
        return hrtf.mSampleRate < devrate
            || (hrtf.mSampleRate == devrate && hrtf.mFilename < filename);
    };
    auto handle = std::lower_bound(LoadedHrtfs.begin(), LoadedHrtfs.end(), fname, hrtf_lt_fname);
    if(handle != LoadedHrtfs.end() && handle->mSampleRate == devrate && handle->mFilename == fname)
    {
        if(HrtfStore *hrtf{handle->mEntry.get()})
        {
            assert(hrtf->mSampleRate == devrate);
            hrtf->add_ref();
            return HrtfStorePtr{hrtf};
        }
    }

    std::unique_ptr<std::istream> stream;
    int residx{};
    char ch{};
    if(sscanf(fname.c_str(), "!%d%c", &residx, &ch) == 2 && ch == '_')
    {
        TRACE("Loading %s...\n", fname.c_str());
        al::span<const char> res{GetResource(residx)};
        if(res.empty())
        {
            ERR("Could not get resource %u, %.*s\n", residx, al::sizei(name), name.data());
            return nullptr;
        }
        /* NOLINTNEXTLINE(*-const-cast) */
        stream = std::make_unique<idstream>(al::span{const_cast<char*>(res.data()), res.size()});
    }
    else
    {
        TRACE("Loading %s...\n", fname.c_str());
        auto fstr = std::make_unique<std::ifstream>(std::filesystem::u8path(fname),
            std::ios::binary);
        if(!fstr->is_open())
        {
            ERR("Could not open %s\n", fname.c_str());
            return nullptr;
        }
        stream = std::move(fstr);
    }

    std::unique_ptr<HrtfStore> hrtf;
    std::array<char,GetMarker03Name().size()> magic{};
    stream->read(magic.data(), magic.size());
    if(stream->gcount() < static_cast<std::streamsize>(GetMarker03Name().size()))
        ERR("%.*s data is too short (%zu bytes)\n", al::sizei(name),name.data(), stream->gcount());
    else if(GetMarker03Name() == std::string_view{magic.data(), magic.size()})
    {
        TRACE("Detected data set format v3\n");
        hrtf = LoadHrtf03(*stream);
    }
    else if(GetMarker02Name() == std::string_view{magic.data(), magic.size()})
    {
        TRACE("Detected data set format v2\n");
        hrtf = LoadHrtf02(*stream);
    }
    else if(GetMarker01Name() == std::string_view{magic.data(), magic.size()})
    {
        TRACE("Detected data set format v1\n");
        hrtf = LoadHrtf01(*stream);
    }
    else if(GetMarker00Name() == std::string_view{magic.data(), magic.size()})
    {
        TRACE("Detected data set format v0\n");
        hrtf = LoadHrtf00(*stream);
    }
    else
        ERR("Invalid header in %.*s: \"%.8s\"\n", al::sizei(name), name.data(), magic.data());
    stream.reset();

    if(!hrtf)
        return nullptr;

    if(hrtf->mSampleRate != devrate)
    {
        TRACE("Resampling HRTF %.*s (%uhz -> %uhz)\n", al::sizei(name), name.data(),
            hrtf->mSampleRate, devrate);

        /* Calculate the last elevation's index and get the total IR count. */
        const size_t lastEv{std::accumulate(hrtf->mFields.begin(), hrtf->mFields.end(), 0_uz,
            [](const size_t curval, const HrtfStore::Field &field) noexcept -> size_t
            { return curval + field.evCount; }
        ) - 1};
        const size_t irCount{size_t{hrtf->mElev[lastEv].irOffset} + hrtf->mElev[lastEv].azCount};

        /* Resample all the IRs. */
        std::array<std::array<double,HrirLength>,2> inout{};
        PPhaseResampler rs;
        rs.init(hrtf->mSampleRate, devrate);
        for(size_t i{0};i < irCount;++i)
        {
            /* NOLINTNEXTLINE(*-const-cast) */
            auto coeffs = al::span{const_cast<HrirArray&>(hrtf->mCoeffs[i])};
            for(size_t j{0};j < 2;++j)
            {
                std::transform(coeffs.cbegin(), coeffs.cend(), inout[0].begin(),
                    [j](const float2 &in) noexcept -> double { return in[j]; });
                rs.process(inout[0], inout[1]);
                for(size_t k{0};k < HrirLength;++k)
                    coeffs[k][j] = static_cast<float>(inout[1][k]);
            }
        }
        rs = {};

        /* Scale the delays for the new sample rate. */
        float max_delay{0.0f};
        auto new_delays = std::vector<float2>(irCount);
        const float rate_scale{static_cast<float>(devrate)/static_cast<float>(hrtf->mSampleRate)};
        for(size_t i{0};i < irCount;++i)
        {
            for(size_t j{0};j < 2;++j)
            {
                const float new_delay{std::round(float(hrtf->mDelays[i][j]) * rate_scale) /
                    float{HrirDelayFracOne}};
                max_delay = std::max(max_delay, new_delay);
                new_delays[i][j] = new_delay;
            }
        }

        /* If the new delays exceed the max, scale it down to fit (essentially
         * shrinking the head radius; not ideal but better than a per-delay
         * clamp).
         */
        float delay_scale{HrirDelayFracOne};
        if(max_delay > MaxHrirDelay)
        {
            WARN("Resampled delay exceeds max (%.2f > %d)\n", max_delay, MaxHrirDelay);
            delay_scale *= float{MaxHrirDelay} / max_delay;
        }

        for(size_t i{0};i < irCount;++i)
        {
            /* NOLINTNEXTLINE(*-const-cast) */
            auto delays = al::span{const_cast<ubyte2&>(hrtf->mDelays[i])};
            std::transform(new_delays[i].cbegin(), new_delays[i].cend(), delays.begin(),
                [delay_scale](const float delay)
                { return static_cast<ubyte>(float2int(delay*delay_scale + 0.5f)); });
        }

        /* Scale the IR size for the new sample rate and update the stored
         * sample rate.
         */
        const float newIrSize{std::round(static_cast<float>(hrtf->mIrSize) * rate_scale)};
        hrtf->mIrSize = static_cast<uint8_t>(std::min(float{HrirLength}, newIrSize));
        hrtf->mSampleRate = devrate & 0xff'ff'ff;
    }

    handle = LoadedHrtfs.emplace(handle, fname, devrate, std::move(hrtf));
    TRACE("Loaded HRTF %.*s for sample rate %uhz, %u-sample filter\n", al::sizei(name),name.data(),
        handle->mEntry->mSampleRate, handle->mEntry->mIrSize);

    return HrtfStorePtr{handle->mEntry.get()};
}
catch(std::exception& e) {
    ERR("Failed to load %.*s: %s\n", al::sizei(name), name.data(), e.what());
    return nullptr;
}


void HrtfStore::add_ref()
{
    auto ref = IncrementRef(mRef);
    TRACE("HrtfStore %p increasing refcount to %u\n", decltype(std::declval<void*>()){this}, ref);
}

void HrtfStore::dec_ref()
{
    auto ref = DecrementRef(mRef);
    TRACE("HrtfStore %p decreasing refcount to %u\n", decltype(std::declval<void*>()){this}, ref);
    if(ref == 0)
    {
        std::lock_guard<std::mutex> loadlock{LoadedHrtfLock};

        /* Go through and remove all unused HRTFs. */
        auto remove_unused = [](LoadedHrtf &hrtf) -> bool
        {
            HrtfStore *entry{hrtf.mEntry.get()};
            if(entry && entry->mRef.load() == 0)
            {
                TRACE("Unloading unused HRTF %s\n", hrtf.mFilename.c_str());
                hrtf.mEntry = nullptr;
                return true;
            }
            return false;
        };
        auto iter = std::remove_if(LoadedHrtfs.begin(), LoadedHrtfs.end(), remove_unused);
        LoadedHrtfs.erase(iter, LoadedHrtfs.end());
    }
}
