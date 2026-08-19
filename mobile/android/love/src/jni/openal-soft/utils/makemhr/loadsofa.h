#ifndef LOADSOFA_H
#define LOADSOFA_H

#include <string_view>

#include "makemhr.h"


bool LoadSofaFile(const std::string_view filename, const uint numThreads, const uint fftSize,
    const uint truncSize, const uint outRate, const ChannelModeT chanMode, HrirDataT *hData);

#endif /* LOADSOFA_H */
