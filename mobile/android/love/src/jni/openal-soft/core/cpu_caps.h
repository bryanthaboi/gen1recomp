#ifndef CORE_CPU_CAPS_H
#define CORE_CPU_CAPS_H

#include <optional>
#include <string>


extern int CPUCapFlags;
enum {
    CPU_CAP_SSE    = 1<<0,
    CPU_CAP_SSE2   = 1<<1,
    CPU_CAP_SSE3   = 1<<2,
    CPU_CAP_SSE4_1 = 1<<3,
    CPU_CAP_NEON   = 1<<4,
};

struct CPUInfo {
    std::string mVendor;
    std::string mName;
    int mCaps{0};
};

std::optional<CPUInfo> GetCPUInfo();

#endif /* CORE_CPU_CAPS_H */
