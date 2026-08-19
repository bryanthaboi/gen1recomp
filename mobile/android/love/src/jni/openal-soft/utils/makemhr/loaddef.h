#ifndef LOADDEF_H
#define LOADDEF_H

#include <istream>
#include <string_view>

#include "alspan.h"

#include "makemhr.h"


bool LoadDefInput(std::istream &istream, const al::span<const char> startbytes,
    const std::string_view filename, const uint fftSize, const uint truncSize, const uint outRate,
    const ChannelModeT chanMode, HrirDataT *hData);

#endif /* LOADDEF_H */
