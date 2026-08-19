#ifndef CORE_STORAGE_FORMATS_H
#define CORE_STORAGE_FORMATS_H

using uint = unsigned int;

/* Storable formats */
enum FmtType : unsigned char {
    FmtUByte,
    FmtShort,
    FmtInt,
    FmtFloat,
    FmtDouble,
    FmtMulaw,
    FmtAlaw,
    FmtIMA4,
    FmtMSADPCM,
};
enum FmtChannels : unsigned char {
    FmtMono,
    FmtStereo,
    FmtRear,
    FmtQuad,
    FmtX51, /* (WFX order) */
    FmtX61, /* (WFX order) */
    FmtX71, /* (WFX order) */
    FmtBFormat2D,
    FmtBFormat3D,
    FmtUHJ2, /* 2-channel UHJ, aka "BHJ", stereo-compatible */
    FmtUHJ3, /* 3-channel UHJ, aka "THJ" */
    FmtUHJ4, /* 4-channel UHJ, aka "PHJ" */
    FmtSuperStereo, /* Stereo processed with Super Stereo. */
    FmtMonoDup, /* Mono duplicated for left/right separation */
};

enum class AmbiLayout : unsigned char {
    FuMa,
    ACN,
};
enum class AmbiScaling : unsigned char {
    FuMa,
    SN3D,
    N3D,
    UHJ,
};

const char *NameFromFormat(FmtType type) noexcept;
const char *NameFromFormat(FmtChannels channels) noexcept;

uint BytesFromFmt(FmtType type) noexcept;
uint ChannelsFromFmt(FmtChannels chans, uint ambiorder) noexcept;
inline uint FrameSizeFromFmt(FmtChannels chans, FmtType type, uint ambiorder) noexcept
{ return ChannelsFromFmt(chans, ambiorder) * BytesFromFmt(type); }

#endif /* CORE_STORAGE_FORMATS_H */
