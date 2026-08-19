/*
 * OpenAL Debug Context Example
 *
 * Copyright (c) 2024 by Chris Robinson <chris.kcat@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

/* This file contains an example for using the debug extension. */

#include <algorithm>
#include <array>
#include <cassert>
#include <cstdio>
#include <iostream>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "AL/al.h"
#include "AL/alc.h"
#include "AL/alext.h"

#include "alspan.h"
#include "alstring.h"

#include "win_main_utf8.h"

namespace {

struct DeviceCloser {
    void operator()(ALCdevice *device) const noexcept { alcCloseDevice(device); }
};
using DevicePtr = std::unique_ptr<ALCdevice,DeviceCloser>;

struct ContextDestroyer {
    void operator()(ALCcontext *context) const noexcept { alcDestroyContext(context); }
};
using ContextPtr = std::unique_ptr<ALCcontext,ContextDestroyer>;


constexpr auto GetDebugSourceName(ALenum source) noexcept -> const char*
{
    switch(source)
    {
    case AL_DEBUG_SOURCE_API_EXT: return "API";
    case AL_DEBUG_SOURCE_AUDIO_SYSTEM_EXT: return "Audio System";
    case AL_DEBUG_SOURCE_THIRD_PARTY_EXT: return "Third Party";
    case AL_DEBUG_SOURCE_APPLICATION_EXT: return "Application";
    case AL_DEBUG_SOURCE_OTHER_EXT: return "Other";
    }
    return "<invalid source>";
}

constexpr auto GetDebugTypeName(ALenum type) noexcept -> const char*
{
    switch(type)
    {
    case AL_DEBUG_TYPE_ERROR_EXT: return "Error";
    case AL_DEBUG_TYPE_DEPRECATED_BEHAVIOR_EXT: return "Deprecated Behavior";
    case AL_DEBUG_TYPE_UNDEFINED_BEHAVIOR_EXT: return "Undefined Behavior";
    case AL_DEBUG_TYPE_PORTABILITY_EXT: return "Portability";
    case AL_DEBUG_TYPE_PERFORMANCE_EXT: return "Performance";
    case AL_DEBUG_TYPE_MARKER_EXT: return "Marker";
    case AL_DEBUG_TYPE_PUSH_GROUP_EXT: return "Push Group";
    case AL_DEBUG_TYPE_POP_GROUP_EXT: return "Pop Group";
    case AL_DEBUG_TYPE_OTHER_EXT: return "Other";
    }
    return "<invalid type>";
}

constexpr auto GetDebugSeverityName(ALenum severity) noexcept -> const char*
{
    switch(severity)
    {
    case AL_DEBUG_SEVERITY_HIGH_EXT: return "High";
    case AL_DEBUG_SEVERITY_MEDIUM_EXT: return "Medium";
    case AL_DEBUG_SEVERITY_LOW_EXT: return "Low";
    case AL_DEBUG_SEVERITY_NOTIFICATION_EXT: return "Notification";
    }
    return "<invalid severity>";
}

auto alDebugMessageCallbackEXT = LPALDEBUGMESSAGECALLBACKEXT{};
auto alDebugMessageInsertEXT = LPALDEBUGMESSAGEINSERTEXT{};
auto alDebugMessageControlEXT = LPALDEBUGMESSAGECONTROLEXT{};
auto alPushDebugGroupEXT = LPALPUSHDEBUGGROUPEXT{};
auto alPopDebugGroupEXT = LPALPOPDEBUGGROUPEXT{};
auto alGetDebugMessageLogEXT = LPALGETDEBUGMESSAGELOGEXT{};
auto alObjectLabelEXT = LPALOBJECTLABELEXT{};
auto alGetObjectLabelEXT = LPALGETOBJECTLABELEXT{};
auto alGetPointerEXT = LPALGETPOINTEREXT{};
auto alGetPointervEXT = LPALGETPOINTERVEXT{};


int main(al::span<std::string_view> args)
{
    /* Print out usage if -h was specified */
    if(args.size() > 1 && (args[1] == "-h" || args[1] == "--help"))
    {
        std::cerr<< "Usage: "<<args[0]<<" [-device <name>] [-nodebug]\n";
        return 1;
    }

    /* Initialize OpenAL. */
    args = args.subspan(1);

    auto device = DevicePtr{};
    if(args.size() > 1 && args[0] == "-device")
    {
        device = DevicePtr{alcOpenDevice(std::string{args[1]}.c_str())};
        if(!device)
            std::cerr<< "Failed to open \""<<args[1]<<"\", trying default\n";
        args = args.subspan(2);
    }
    if(!device)
        device = DevicePtr{alcOpenDevice(nullptr)};
    if(!device)
    {
        std::cerr<< "Could not open a device!\n";
        return 1;
    }

    if(!alcIsExtensionPresent(device.get(), "ALC_EXT_debug"))
    {
        std::cerr<< "ALC_EXT_debug not supported on device\n";
        return 1;
    }

    /* Load the Debug API functions we're using. */
#define LOAD_PROC(N) N = reinterpret_cast<decltype(N)>(alcGetProcAddress(device.get(), #N))
    LOAD_PROC(alDebugMessageCallbackEXT);
    LOAD_PROC(alDebugMessageInsertEXT);
    LOAD_PROC(alDebugMessageControlEXT);
    LOAD_PROC(alPushDebugGroupEXT);
    LOAD_PROC(alPopDebugGroupEXT);
    LOAD_PROC(alGetDebugMessageLogEXT);
    LOAD_PROC(alObjectLabelEXT);
    LOAD_PROC(alGetObjectLabelEXT);
    LOAD_PROC(alGetPointerEXT);
    LOAD_PROC(alGetPointervEXT);
#undef LOAD_PROC

    /* Create a debug context and set it as current. If -nodebug was specified,
     * create a non-debug context (to see how debug messages react).
     */
    auto flags = ALCint{ALC_CONTEXT_DEBUG_BIT_EXT};
    if(!args.empty() && args[0] == "-nodebug")
        flags &= ~ALC_CONTEXT_DEBUG_BIT_EXT;

    const auto attribs = std::array<ALCint,3>{{
        ALC_CONTEXT_FLAGS_EXT, flags,
        0 /* end-of-list */
    }};
    auto context = ContextPtr{alcCreateContext(device.get(), attribs.data())};
    if(!context || alcMakeContextCurrent(context.get()) == ALC_FALSE)
    {
        std::cerr<< "Could not create and set a context!\n";
        return 1;
    }

    /* Enable low-severity debug messages, which are disabled by default. */
    alDebugMessageControlEXT(AL_DONT_CARE_EXT, AL_DONT_CARE_EXT, AL_DEBUG_SEVERITY_LOW_EXT, 0,
        nullptr, AL_TRUE);

    printf("Context flags: 0x%08x\n", alGetInteger(AL_CONTEXT_FLAGS_EXT));

    /* A debug context has debug output enabled by default. But in case this
     * isn't a debug context, explicitly enable it (probably won't get much, if
     * anything, in that case).
     */
    printf("Default debug state is: %s\n",
        alIsEnabled(AL_DEBUG_OUTPUT_EXT) ? "enabled" : "disabled");
    alEnable(AL_DEBUG_OUTPUT_EXT);

    /* The max debug message length property will allow us to define message
     * storage of sufficient length. This includes space for the null
     * terminator.
     */
    const auto maxloglength = alGetInteger(AL_MAX_DEBUG_MESSAGE_LENGTH_EXT);
    printf("Max debug message length: %d\n", maxloglength);

    fputs("\n", stdout);

    /* Doppler Velocity is deprecated since AL 1.1, so this should generate a
     * deprecation debug message. We'll first handle debug messages through the
     * message log, meaning we'll query for and read it afterward.
     */
    printf("Calling alDopplerVelocity(0.5f)...\n");
    alDopplerVelocity(0.5f);

    for(auto numlogs = alGetInteger(AL_DEBUG_LOGGED_MESSAGES_EXT);numlogs > 0;--numlogs)
    {
        auto message = std::vector<char>(static_cast<ALuint>(maxloglength), '\0');
        auto source = ALenum{};
        auto type = ALenum{};
        auto id = ALuint{};
        auto severity = ALenum{};
        auto msglength = ALsizei{};

        /* Getting the message removes it from the log. */
        const auto read = alGetDebugMessageLogEXT(1, maxloglength, &source, &type, &id, &severity,
            &msglength, message.data());
        if(read != 1)
        {
            fprintf(stderr, "Read %d debug messages, expected to read 1\n", read);
            break;
        }

        /* The message lengths returned by alGetDebugMessageLogEXT include the
         * null terminator, so subtract one for the string_view length. If we
         * read more than one message at a time, the length could be used as
         * the offset to the next message.
         */
        const auto msgstr = std::string_view{message.data(),
            static_cast<ALuint>(msglength ? msglength-1 : 0)};
        printf("Got message from log:\n"
            "  Source: %s\n"
            "  Type: %s\n"
            "  ID: %u\n"
            "  Severity: %s\n"
            "  Message: \"%.*s\"\n", GetDebugSourceName(source), GetDebugTypeName(type), id,
            GetDebugSeverityName(severity), al::sizei(msgstr), msgstr.data());
    }
    fputs("\n", stdout);

    /* Now set up a callback function. This lets us print the debug messages as
     * they happen without having to explicitly query and get them.
     */
    static constexpr auto debug_callback = [](ALenum source, ALenum type, ALuint id,
        ALenum severity, ALsizei length, const ALchar *message, void *userParam [[maybe_unused]])
        noexcept -> void
    {
        /* The message length provided to the callback does not include the
         * null terminator.
         */
        const auto msgstr = std::string_view{message, static_cast<ALuint>(length)};
        printf("Got message from callback:\n"
            "  Source: %s\n"
            "  Type: %s\n"
            "  ID: %u\n"
            "  Severity: %s\n"
            "  Message: \"%.*s\"\n", GetDebugSourceName(source), GetDebugTypeName(type), id,
            GetDebugSeverityName(severity), al::sizei(msgstr), msgstr.data());
    };
    alDebugMessageCallbackEXT(debug_callback, nullptr);

    if(const auto numlogs = alGetInteger(AL_DEBUG_LOGGED_MESSAGES_EXT))
        fprintf(stderr, "%d left over logged message%s!\n", numlogs, (numlogs==1)?"":"s");

    /* This should also generate a deprecation debug message, which will now go
     * through the callback.
     */
    printf("Calling alGetInteger(AL_DOPPLER_VELOCITY)...\n");
    auto dv [[maybe_unused]] = alGetInteger(AL_DOPPLER_VELOCITY);
    fputs("\n", stdout);

    /* These functions are notoriously unreliable for their behavior, they will
     * likely generate portability debug messages.
     */
    printf("Calling alcSuspendContext and alcProcessContext...\n");
    alcSuspendContext(context.get());
    alcProcessContext(context.get());
    fputs("\n", stdout);

    printf("Pushing a debug group, making some invalid calls, and popping the debug group...\n");
    alPushDebugGroupEXT(AL_DEBUG_SOURCE_APPLICATION_EXT, 0, -1, "Error test group");
    alSpeedOfSound(0.0f);
    /* Can't set the label of the null buffer. */
    alObjectLabelEXT(AL_BUFFER, 0, -1, "The null buffer");
    alPopDebugGroupEXT();
    fputs("\n", stdout);

    /* All done, insert a custom message and unset the callback. The context
     * and device will clean themselves up.
     */
    alDebugMessageInsertEXT(AL_DEBUG_SOURCE_APPLICATION_EXT, AL_DEBUG_TYPE_MARKER_EXT, 0,
        AL_DEBUG_SEVERITY_NOTIFICATION_EXT, -1, "End of run, cleaning up");
    alDebugMessageCallbackEXT(nullptr, nullptr);

    return 0;
}

} // namespace

int main(int argc, char **argv)
{
    assert(argc >= 0);
    auto args = std::vector<std::string_view>(static_cast<unsigned int>(argc));
    std::copy_n(argv, args.size(), args.begin());
    return main(al::span{args});
}
