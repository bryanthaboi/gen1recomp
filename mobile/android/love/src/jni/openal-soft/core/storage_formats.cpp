
#include "config.h"

#include "storage_formats.h"

#include <cstdint>


const char *NameFromFormat(FmtType type) noexcept
{
    switch(type)
    {
    case FmtUByte: return "UInt8";
    case FmtShort: return "Int16";
    case FmtInt: return "Int32";
    case FmtFloat: return "Float";
    case FmtDouble: return "Double";
    case FmtMulaw: return "muLaw";
    case FmtAlaw: return "aLaw";
    case FmtIMA4: return "IMA4 ADPCM";
    case FmtMSADPCM: return "MS ADPCM";
    }
    return "<internal error>";
}

const char *NameFromFormat(FmtChannels channels) noexcept
{
    switch(channels)
    {
    case FmtMono: return "Mono";
    case FmtStereo: return "Stereo";
    case FmtRear: return "Rear";
    case FmtQuad: return "Quadraphonic";
    case FmtX51: return "Surround 5.1";
    case FmtX61: return "Surround 6.1";
    case FmtX71: return "Surround 7.1";
    case FmtBFormat2D: return "B-Format 2D";
    case FmtBFormat3D: return "B-Format 3D";
    case FmtUHJ2: return "UHJ2";
    case FmtUHJ3: return "UHJ3";
    case FmtUHJ4: return "UHJ4";
    case FmtSuperStereo: return "Super Stereo";
    case FmtMonoDup: return "Mono (dup)";
    }
    return "<internal error>";
}

uint BytesFromFmt(FmtType type) noexcept
{
    switch(type)
    {
    case FmtUByte: return sizeof(std::uint8_t);
    case FmtShort: return sizeof(std::int16_t);
    case FmtInt: return sizeof(std::int32_t);
    case FmtFloat: return sizeof(float);
    case FmtDouble: return sizeof(double);
    case FmtMulaw: return sizeof(std::uint8_t);
    case FmtAlaw: return sizeof(std::uint8_t);
    case FmtIMA4: break;
    case FmtMSADPCM: break;
    }
    return 0;
}

uint ChannelsFromFmt(FmtChannels chans, uint ambiorder) noexcept
{
    switch(chans)
    {
    case FmtMono: return 1;
    case FmtStereo: return 2;
    case FmtRear: return 2;
    case FmtQuad: return 4;
    case FmtX51: return 6;
    case FmtX61: return 7;
    case FmtX71: return 8;
    case FmtBFormat2D: return (ambiorder*2) + 1;
    case FmtBFormat3D: return (ambiorder+1) * (ambiorder+1);
    case FmtUHJ2: return 2;
    case FmtUHJ3: return 3;
    case FmtUHJ4: return 4;
    case FmtSuperStereo: return 2;
    case FmtMonoDup: return 1;
    }
    return 0;
}
