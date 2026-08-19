/*
 * SOFA info utility for inspecting SOFA file metrics and determining HRTF
 * utility compatible layouts.
 *
 * Copyright (C) 2018-2019  Christopher Fitzgerald
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

#include <cstdio>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "alnumeric.h"
#include "alspan.h"
#include "alstring.h"

#include "sofa-support.h"

#include "mysofa.h"

#include "win_main_utf8.h"

namespace {

using uint = unsigned int;

void PrintSofaAttributes(const char *prefix, MYSOFA_ATTRIBUTE *attribute)
{
    while(attribute)
    {
        printf("%s.%s: %s\n", prefix, attribute->name, attribute->value);
        attribute = attribute->next;
    }
}

void PrintSofaArray(const char *prefix, MYSOFA_ARRAY *array, bool showValues=true)
{
    PrintSofaAttributes(prefix, array->attributes);
    if(showValues)
    {
        const auto values = al::span{array->values, array->elements};
        for(size_t i{0u};i < values.size();++i)
            printf("%s[%zu]: %.6f\n", prefix, i, values[i]);
    }
    else
        printf("%s[...]: <%u values suppressed>\n", prefix, array->elements);
}

/* Attempts to produce a compatible layout.  Most data sets tend to be
 * uniform and have the same major axis as used by OpenAL Soft's HRTF model.
 * This will remove outliers and produce a maximally dense layout when
 * possible.  Those sets that contain purely random measurements or use
 * different major axes will fail.
 */
void PrintCompatibleLayout(const al::span<const float> xyzs)
{
    fputc('\n', stdout);

    auto fds = GetCompatibleLayout(xyzs);
    if(fds.empty())
    {
        fputs("No compatible field layouts in SOFA file.\n", stdout);
        return;
    }

    uint used_elems{0};
    for(size_t fi{0u};fi < fds.size();++fi)
    {
        for(uint ei{fds[fi].mEvStart};ei < fds[fi].mEvCount;++ei)
            used_elems += fds[fi].mAzCounts[ei];
    }

    printf("Compatible Layout (%u of %zu measurements):\n\ndistance = %.3f", used_elems,
        xyzs.size()/3, fds[0].mDistance);
    for(size_t fi{1u};fi < fds.size();fi++)
        printf(", %.3f", fds[fi].mDistance);

    fputs("\nazimuths = ", stdout);
    for(size_t fi{0u};fi < fds.size();++fi)
    {
        for(uint ei{0u};ei < fds[fi].mEvStart;++ei)
            printf("%d%s", fds[fi].mAzCounts[fds[fi].mEvCount - 1 - ei], ", ");
        for(uint ei{fds[fi].mEvStart};ei < fds[fi].mEvCount;++ei)
            printf("%d%s", fds[fi].mAzCounts[ei],
                (ei < (fds[fi].mEvCount - 1)) ? ", " :
                (fi < (fds.size() - 1)) ? ";\n           " : "\n");
    }
}

// Load and inspect the given SOFA file.
void SofaInfo(const std::string &filename)
{
    int err;
    MySofaHrtfPtr sofa{mysofa_load(filename.c_str(), &err)};
    if(!sofa)
    {
        printf("Error: Could not load source file '%s' (%s).\n", filename.c_str(),
            SofaErrorStr(err));
        return;
    }

    /* NOTE: Some valid SOFA files are failing this check. */
    err = mysofa_check(sofa.get());
    if(err != MYSOFA_OK)
        printf("Warning: Supposedly malformed source file '%s' (%s).\n", filename.c_str(),
            SofaErrorStr(err));

    mysofa_tocartesian(sofa.get());

    PrintSofaAttributes("Info", sofa->attributes);

    printf("Measurements: %u\n", sofa->M);
    printf("Receivers: %u\n", sofa->R);
    printf("Emitters: %u\n", sofa->E);
    printf("Samples: %u\n", sofa->N);

    PrintSofaArray("SampleRate", &sofa->DataSamplingRate);
    PrintSofaArray("DataDelay", &sofa->DataDelay);
    PrintSofaArray("SourcePosition", &sofa->SourcePosition, false);

    PrintCompatibleLayout(al::span{sofa->SourcePosition.values, sofa->M*3_uz});
}

int main(al::span<std::string_view> args)
{
    if(args.size() != 2)
    {
        printf("Usage: %.*s <sofa-file>\n", al::sizei(args[0]), args[0].data());
        return 0;
    }

    SofaInfo(std::string{args[1]});

    return 0;
}

} /* namespace */

int main(int argc, char **argv)
{
    assert(argc >= 0);
    auto args = std::vector<std::string_view>(static_cast<unsigned int>(argc));
    std::copy_n(argv, args.size(), args.begin());
    return main(al::span{args});
}
