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

#include <string_view>
#include <vector>

#include "AL/al.h"
#include "AL/alc.h"

#include "alc/context.h"
#include "alc/inprogext.h"
#include "alstring.h"
#include "direct_defs.h"
#include "opthelpers.h"


AL_API DECL_FUNC1(ALboolean, alIsExtensionPresent, const ALchar*,extName)
FORCE_ALIGN ALboolean AL_APIENTRY alIsExtensionPresentDirect(ALCcontext *context, const ALchar *extName) noexcept
{
    if(!extName) UNLIKELY
    {
        context->setError(AL_INVALID_VALUE, "NULL pointer");
        return AL_FALSE;
    }

    const std::string_view tofind{extName};
    for(std::string_view ext : context->mExtensions)
    {
        if(al::case_compare(ext, tofind) == 0)
            return AL_TRUE;
    }

    return AL_FALSE;
}


AL_API ALvoid* AL_APIENTRY alGetProcAddress(const ALchar *funcName) noexcept
{
    if(!funcName) return nullptr;
    return alcGetProcAddress(nullptr, funcName);
}

FORCE_ALIGN ALvoid* AL_APIENTRY alGetProcAddressDirect(ALCcontext*, const ALchar *funcName) noexcept
{
    if(!funcName) return nullptr;
    return alcGetProcAddress(nullptr, funcName);
}

AL_API ALenum AL_APIENTRY alGetEnumValue(const ALchar *enumName) noexcept
{
    if(!enumName) return ALenum{0};
    return alcGetEnumValue(nullptr, enumName);
}

FORCE_ALIGN ALenum AL_APIENTRY alGetEnumValueDirect(ALCcontext*, const ALchar *enumName) noexcept
{
    if(!enumName) return ALenum{0};
    return alcGetEnumValue(nullptr, enumName);
}
