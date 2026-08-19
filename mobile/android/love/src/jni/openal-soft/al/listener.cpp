/**
 * OpenAL cross platform audio library
 * Copyright (C) 1999-2000 by authors.
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

#include "listener.h"

#include <algorithm>
#include <cmath>
#include <mutex>

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/efx.h"

#include "alc/context.h"
#include "alnumeric.h"
#include "alspan.h"
#include "direct_defs.h"
#include "error.h"


namespace {

inline void UpdateProps(ALCcontext *context)
{
    if(!context->mDeferUpdates)
    {
        UpdateContextProps(context);
        return;
    }
    context->mPropsDirty = true;
}

inline void CommitAndUpdateProps(ALCcontext *context)
{
    if(!context->mDeferUpdates)
    {
#if ALSOFT_EAX
        if(context->eaxNeedsCommit())
        {
            context->mPropsDirty = true;
            context->applyAllUpdates();
            return;
        }
#endif
        UpdateContextProps(context);
        return;
    }
    context->mPropsDirty = true;
}

} // namespace

AL_API DECL_FUNC2(void, alListenerf, ALenum,param, ALfloat,value)
FORCE_ALIGN void AL_APIENTRY alListenerfDirect(ALCcontext *context, ALenum param, ALfloat value) noexcept
try {
    ALlistener &listener = context->mListener;
    std::lock_guard<std::mutex> proplock{context->mPropLock};
    switch(param)
    {
    case AL_GAIN:
        if(!(value >= 0.0f && std::isfinite(value)))
            throw al::context_error{AL_INVALID_VALUE, "Listener gain out of range"};
        listener.Gain = value;
        UpdateProps(context);
        return;

    case AL_METERS_PER_UNIT:
        if(!(value >= AL_MIN_METERS_PER_UNIT && value <= AL_MAX_METERS_PER_UNIT))
            throw al::context_error{AL_INVALID_VALUE, "Listener meters per unit out of range"};
        listener.mMetersPerUnit = value;
        UpdateProps(context);
        return;
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener float property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC4(void, alListener3f, ALenum,param, ALfloat,value1, ALfloat,value2, ALfloat,value3)
FORCE_ALIGN void AL_APIENTRY alListener3fDirect(ALCcontext *context, ALenum param, ALfloat value1,
    ALfloat value2, ALfloat value3) noexcept
try {
    ALlistener &listener = context->mListener;
    std::lock_guard<std::mutex> proplock{context->mPropLock};
    switch(param)
    {
    case AL_POSITION:
        if(!(std::isfinite(value1) && std::isfinite(value2) && std::isfinite(value3)))
            throw al::context_error{AL_INVALID_VALUE, "Listener position out of range"};
        listener.Position[0] = value1;
        listener.Position[1] = value2;
        listener.Position[2] = value3;
        CommitAndUpdateProps(context);
        return;

    case AL_VELOCITY:
        if(!(std::isfinite(value1) && std::isfinite(value2) && std::isfinite(value3)))
            throw al::context_error{AL_INVALID_VALUE, "Listener velocity out of range"};
        listener.Velocity[0] = value1;
        listener.Velocity[1] = value2;
        listener.Velocity[2] = value3;
        CommitAndUpdateProps(context);
        return;
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener 3-float property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC2(void, alListenerfv, ALenum,param, const ALfloat*,values)
FORCE_ALIGN void AL_APIENTRY alListenerfvDirect(ALCcontext *context, ALenum param,
    const ALfloat *values) noexcept
try {
    if(!values)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    case AL_GAIN:
    case AL_METERS_PER_UNIT:
        alListenerfDirect(context, param, *values);
        return;

    case AL_POSITION:
    case AL_VELOCITY:
        auto vals = al::span<const float,3>{values, 3_uz};
        alListener3fDirect(context, param, vals[0], vals[1], vals[2]);
        return;
    }

    ALlistener &listener = context->mListener;
    std::lock_guard<std::mutex> proplock{context->mPropLock};
    switch(param)
    {
    case AL_ORIENTATION:
        auto vals = al::span<const float,6>{values, 6_uz};
        if(!std::all_of(vals.cbegin(), vals.cend(), [](float f) { return std::isfinite(f); }))
            return context->setError(AL_INVALID_VALUE, "Listener orientation out of range");
        /* AT then UP */
        std::copy_n(vals.cbegin(), 3, listener.OrientAt.begin());
        std::copy_n(vals.cbegin()+3, 3, listener.OrientUp.begin());
        CommitAndUpdateProps(context);
        return;
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener float-vector property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


AL_API DECL_FUNC2(void, alListeneri, ALenum,param, ALint,value)
FORCE_ALIGN void AL_APIENTRY alListeneriDirect(ALCcontext *context, ALenum param, ALint /*value*/) noexcept
try {
    std::lock_guard<std::mutex> proplock{context->mPropLock};
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener integer property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC4(void, alListener3i, ALenum,param, ALint,value1, ALint,value2, ALint,value3)
FORCE_ALIGN void AL_APIENTRY alListener3iDirect(ALCcontext *context, ALenum param, ALint value1,
    ALint value2, ALint value3) noexcept
try {
    switch(param)
    {
    case AL_POSITION:
    case AL_VELOCITY:
        alListener3fDirect(context, param, static_cast<ALfloat>(value1),
            static_cast<ALfloat>(value2), static_cast<ALfloat>(value3));
        return;
    }

    std::lock_guard<std::mutex> proplock{context->mPropLock};
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener 3-integer property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC2(void, alListeneriv, ALenum,param, const ALint*,values)
FORCE_ALIGN void AL_APIENTRY alListenerivDirect(ALCcontext *context, ALenum param,
    const ALint *values) noexcept
try {
    if(!values)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    al::span<const ALint> vals;
    switch(param)
    {
    case AL_POSITION:
    case AL_VELOCITY:
        vals = {values, 3_uz};
        alListener3fDirect(context, param, static_cast<ALfloat>(vals[0]),
            static_cast<ALfloat>(vals[1]), static_cast<ALfloat>(vals[2]));
        return;

    case AL_ORIENTATION:
        vals = {values, 6_uz};
        const std::array fvals{static_cast<ALfloat>(vals[0]), static_cast<ALfloat>(vals[1]),
            static_cast<ALfloat>(vals[2]), static_cast<ALfloat>(vals[3]),
            static_cast<ALfloat>(vals[4]), static_cast<ALfloat>(vals[5]),
        };
        alListenerfvDirect(context, param, fvals.data());
        return;
    }

    std::lock_guard<std::mutex> proplock{context->mPropLock};
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener integer-vector property 0x%x",
        param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


AL_API DECL_FUNC2(void, alGetListenerf, ALenum,param, ALfloat*,value)
FORCE_ALIGN void AL_APIENTRY alGetListenerfDirect(ALCcontext *context, ALenum param,
    ALfloat *value) noexcept
try {
    if(!value)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    ALlistener &listener = context->mListener;
    std::lock_guard<std::mutex> proplock{context->mPropLock};
    switch(param)
    {
    case AL_GAIN: *value = listener.Gain; return;
    case AL_METERS_PER_UNIT: *value = listener.mMetersPerUnit; return;
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener float property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC4(void, alGetListener3f, ALenum,param, ALfloat*,value1, ALfloat*,value2, ALfloat*,value3)
FORCE_ALIGN void AL_APIENTRY alGetListener3fDirect(ALCcontext *context, ALenum param,
    ALfloat *value1, ALfloat *value2, ALfloat *value3) noexcept
try {
    if(!value1 || !value2 || !value3)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    ALlistener &listener = context->mListener;
    std::lock_guard<std::mutex> proplock{context->mPropLock};
    switch(param)
    {
    case AL_POSITION:
        *value1 = listener.Position[0];
        *value2 = listener.Position[1];
        *value3 = listener.Position[2];
        return;

    case AL_VELOCITY:
        *value1 = listener.Velocity[0];
        *value2 = listener.Velocity[1];
        *value3 = listener.Velocity[2];
        return;
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener 3-float property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC2(void, alGetListenerfv, ALenum,param, ALfloat*,values)
FORCE_ALIGN void AL_APIENTRY alGetListenerfvDirect(ALCcontext *context, ALenum param,
    ALfloat *values) noexcept
try {
    if(!values)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    case AL_GAIN:
    case AL_METERS_PER_UNIT:
        alGetListenerfDirect(context, param, values);
        return;

    case AL_POSITION:
    case AL_VELOCITY:
        auto vals = al::span<ALfloat,3>{values, 3_uz};
        alGetListener3fDirect(context, param, &vals[0], &vals[1], &vals[2]);
        return;
    }

    ALlistener &listener = context->mListener;
    std::lock_guard<std::mutex> proplock{context->mPropLock};
    switch(param)
    {
    case AL_ORIENTATION:
        al::span<ALfloat,6> vals{values, 6_uz};
        // AT then UP
        std::copy_n(listener.OrientAt.cbegin(), 3, vals.begin());
        std::copy_n(listener.OrientUp.cbegin(), 3, vals.begin()+3);
        return;
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener float-vector property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}


AL_API DECL_FUNC2(void, alGetListeneri, ALenum,param, ALint*,value)
FORCE_ALIGN void AL_APIENTRY alGetListeneriDirect(ALCcontext *context, ALenum param, ALint *value) noexcept
try {
    if(!value) throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};
    std::lock_guard<std::mutex> proplock{context->mPropLock};
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener integer property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC4(void, alGetListener3i, ALenum,param, ALint*,value1, ALint*,value2, ALint*,value3)
FORCE_ALIGN void AL_APIENTRY alGetListener3iDirect(ALCcontext *context, ALenum param,
    ALint *value1, ALint *value2, ALint *value3) noexcept
try {
    if(!value1 || !value2 || !value3)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    ALlistener &listener = context->mListener;
    std::lock_guard<std::mutex> proplock{context->mPropLock};
    switch(param)
    {
    case AL_POSITION:
        *value1 = static_cast<ALint>(listener.Position[0]);
        *value2 = static_cast<ALint>(listener.Position[1]);
        *value3 = static_cast<ALint>(listener.Position[2]);
        return;

    case AL_VELOCITY:
        *value1 = static_cast<ALint>(listener.Velocity[0]);
        *value2 = static_cast<ALint>(listener.Velocity[1]);
        *value3 = static_cast<ALint>(listener.Velocity[2]);
        return;
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener 3-integer property 0x%x", param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}

AL_API DECL_FUNC2(void, alGetListeneriv, ALenum,param, ALint*,values)
FORCE_ALIGN void AL_APIENTRY alGetListenerivDirect(ALCcontext *context, ALenum param,
    ALint *values) noexcept
try {
    if(!values)
        throw al::context_error{AL_INVALID_VALUE, "NULL pointer"};

    switch(param)
    {
    case AL_POSITION:
    case AL_VELOCITY:
        auto vals = al::span<ALint,3>{values, 3_uz};
        alGetListener3iDirect(context, param, &vals[0], &vals[1], &vals[2]);
        return;
    }

    ALlistener &listener = context->mListener;
    std::lock_guard<std::mutex> proplock{context->mPropLock};

    static constexpr auto f2i = [](const float val) noexcept { return static_cast<ALint>(val); };
    switch(param)
    {
    case AL_ORIENTATION:
        auto vals = al::span<ALint,6>{values, 6_uz};
        // AT then UP
        std::transform(listener.OrientAt.cbegin(), listener.OrientAt.cend(), vals.begin(), f2i);
        std::transform(listener.OrientUp.cbegin(), listener.OrientUp.cend(), vals.begin()+3, f2i);
        return;
    }
    throw al::context_error{AL_INVALID_ENUM, "Invalid listener integer-vector property 0x%x",
        param};
}
catch(al::context_error& e) {
    context->setError(e.errorCode(), "%s", e.what());
}
