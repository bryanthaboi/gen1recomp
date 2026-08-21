#!/usr/bin/env python3
"""Applies gen1recomp's iOS native-bridge patches to the fetched LÖVE 12.0
source tree (mobile/ios/love-src/). Idempotent AND re-appliable: the first
run stashes a pristine `.orig` copy of every file it rewrites, and later
runs always start over from that copy — so editing the patch content here
just works on the next build, no manual restore needed.

What it does:
  1. Copies mobile/ios/native/ (GRPickerBridge.swift, GRHealthBridge.swift,
     GRBootstrap.m) and the HealthKit entitlements into the LÖVE tree.
  2. Patches liblove's wrap_System.cpp to expose love.system.pickFile,
     love.system.createFile, love.system.syncHealthSteps,
     love.system.httpDownload and love.system.httpRequest on iOS (each
     calls a GR*Bridge Swift class through the Objective-C runtime, so
     liblove never links against Swift directly).
  3. Patches love.xcodeproj so the love-ios app target compiles the native
     files (Swift 5, iOS 14 deployment for UTType/forExporting APIs).
"""

import re
import shutil
import sys
from pathlib import Path

IOS_DIR = Path(__file__).resolve().parent
LOVE_SRC = IOS_DIR / "love-src"
NATIVE_SRC = IOS_DIR / "native"
NATIVE_DST = LOVE_SRC / "platform" / "xcode" / "ios" / "native"
WRAP_SYSTEM = LOVE_SRC / "src" / "modules" / "system" / "wrap_System.cpp"
PBXPROJ = LOVE_SRC / "platform" / "xcode" / "love.xcodeproj" / "project.pbxproj"
APPLE_MM = LOVE_SRC / "src" / "common" / "apple.mm"
FILESYSTEM_CPP = LOVE_SRC / "src" / "modules" / "filesystem" / "physfs" / "Filesystem.cpp"
IOS_MM = LOVE_SRC / "src" / "common" / "ios.mm"
IOS_H = LOVE_SRC / "src" / "common" / "ios.h"
SYSTEM_CPP = LOVE_SRC / "src" / "modules" / "system" / "System.cpp"
AUDIO_H = LOVE_SRC / "src" / "modules" / "audio" / "openal" / "Audio.h"
AUDIO_CPP = LOVE_SRC / "src" / "modules" / "audio" / "openal" / "Audio.cpp"
ENTITLEMENTS_SRC = IOS_DIR / "overlays" / "love-ios.entitlements"

NATIVE_FILES = ("GRPickerBridge.swift", "GRHealthBridge.swift", "GRBootstrap.m")

MARKER = "gen1recomp iOS picker bridge"

POOL_PAUSE_MARKER = "poolPaused"
AUDIO_EVENT_MARKER = "gr_pushAudioEvent"

# Headers must land outside `namespace love { namespace system {`.
WRAP_INCLUDES = """
// %s: headers for the native-bridge functions below.
#ifdef LOVE_IOS
#include <objc/runtime.h>
#include <objc/message.h>
#include <string>
#include <vector>
#include "filesystem/Filesystem.h"
#endif
""" % MARKER

WRAP_FUNCS = """
// --- %s -------------------------------------------------
// love.system.pickFile / createFile / syncHealthSteps for iOS. pickFile and
// createFile mirror the love-android extension this project's importer
// already targets; syncHealthSteps feeds the Pokéwalker mod. Implemented in
// Swift (GR*Bridge classes, love-ios app target); reached via the ObjC
// runtime so liblove itself needs no Swift interop.
#ifdef LOVE_IOS
static const char *gr_saveDirectory()
{
	static std::string saveDirectory;
	auto fs = Module::getInstance<love::filesystem::Filesystem>(Module::M_FILESYSTEM);
	if (fs == nullptr)
		return "";
	saveDirectory = fs->getSaveDirectory();
	return saveDirectory.c_str();
}

static int gr_callBridge(lua_State *L, const char *className,
                         const char *selector, const char *arg)
{
	Class cls = objc_getClass(className);
	if (cls == nullptr)
	{
		lua_pushboolean(L, 0);
		return 1;
	}
	typedef signed char (*GRMsg)(Class, SEL, const char *, const char *);
	signed char ok = ((GRMsg)objc_msgSend)(cls, sel_registerName(selector),
	                                       arg, gr_saveDirectory());
	lua_pushboolean(L, ok != 0);
	return 1;
}

int w_pickFile(lua_State *L)
{
	const char *kind = luaL_optstring(L, 1, "rom");
	return gr_callBridge(L, "GRPickerBridge", "presentPickerWithKind:saveDir:", kind);
}

// love.system.pickFileKinds() -> the comma-separated kinds supported by the
// Swift bridge (including required_import), or nil off iOS.
//
// So a caller can ask what this build's picker understands BEFORE opening it.
// An unknown kind is refused (GRPickerBridge), and a refusal looks exactly
// like a picker that would not open -- so a caller with a fallback worth
// showing needs to know which it is facing. A mod that guesses instead has
// no way back: before the refusal landed, an unrecognised kind wrote
// picked_rom.gb and the ROM importer deleted it.
//
// nil where there is no bridge at all, which reads the same as "no kinds".
int w_pickFileKinds(lua_State *L)
{
	Class cls = objc_getClass("GRPickerBridge");
	if (cls == nullptr)
	{
		lua_pushnil(L);
		return 1;
	}
	// Fetched through the runtime: wrap_System.cpp is compiled as C++ rather
	// than Objective-C++, so no Foundation type may be NAMED here -- writing
	// `NSString` alone breaks the whole translation unit. objc_msgSend is a
	// plain C entry point and `id` comes from objc/runtime.h, so the string
	// is asked for its UTF8 bytes without ever being typed.
	typedef id (*GRObj)(Class, SEL);
	id kinds = ((GRObj)objc_msgSend)(cls,
	                                 sel_registerName("supportedPickerKinds"));
	if (kinds == nullptr)
	{
		lua_pushnil(L);
		return 1;
	}
	typedef const char *(*GRUTF8)(id, SEL);
	const char *bytes = ((GRUTF8)objc_msgSend)(kinds,
	                                           sel_registerName("UTF8String"));
	if (bytes == nullptr || bytes[0] == '\\0')
	{
		lua_pushnil(L);
		return 1;
	}
	lua_pushstring(L, bytes);
	return 1;
}

int w_createFile(lua_State *L)
{
	const char *name = luaL_optstring(L, 1, "export.sav");
	return gr_callBridge(L, "GRPickerBridge", "presentExportWithName:saveDir:", name);
}

int w_syncHealthSteps(lua_State *L)
{
	return gr_callBridge(L, "GRHealthBridge", "syncStepsWithCommand:saveDir:", "sync");
}
#endif // LOVE_IOS
// ---------------------------------------------------------------------------

""" % MARKER

WRAP_REGISTRATION = """#ifdef LOVE_IOS
	{ "getDeviceModel", w_getDeviceModel },
	{ "pickFile", w_pickFile },
	{ "pickFileKinds", w_pickFileKinds },
	{ "createFile", w_createFile },
	{ "syncHealthSteps", w_syncHealthSteps },
	{ "httpDownload", w_httpDownload },
	{ "httpRequest", w_httpRequest },
#endif
"""

WRAP_SYNC_FUNCS = """
#ifdef LOVE_IOS
static const char *gr_saveDirectory()
{
	static std::string saveDirectory;
	auto fs = Module::getInstance<love::filesystem::Filesystem>(Module::M_FILESYSTEM);
	if (fs == nullptr)
		return "";
	saveDirectory = fs->getSaveDirectory();
	return saveDirectory.c_str();
}

static int gr_callBridge(lua_State *L, const char *className,
                         const char *selector, const char *arg)
{
	Class cls = objc_getClass(className);
	if (cls == nullptr)
	{
		lua_pushboolean(L, 0);
		return 1;
	}
	typedef signed char (*GRMsg)(Class, SEL, const char *, const char *);
	signed char ok = ((GRMsg)objc_msgSend)(cls, sel_registerName(selector),
	                                       arg, gr_saveDirectory());
	lua_pushboolean(L, ok != 0);
	return 1;
}

int w_syncHealthSteps(lua_State *L)
{
	return gr_callBridge(L, "GRHealthBridge", "syncStepsWithCommand:saveDir:", "sync");
}
#endif

"""

WRAP_SYNC_REGISTRATION = """#ifdef LOVE_IOS
	{ "getDeviceModel", w_getDeviceModel },
	{ "syncHealthSteps", w_syncHealthSteps },
	{ "httpDownload", w_httpDownload },
	{ "httpRequest", w_httpRequest },
#endif
"""

BRIDGE_EXTRA_FUNCS = """
#ifdef LOVE_IOS
int w_getDeviceModel(lua_State *L)
{
	Class cls = objc_getClass("GRDeviceBridge");
	if (cls == nullptr)
	{
		lua_pushnil(L);
		return 1;
	}
	typedef id (*GRObj)(Class, SEL);
	id value = ((GRObj)objc_msgSend)(cls, sel_registerName("deviceModel"));
	if (value == nullptr)
	{
		lua_pushnil(L);
		return 1;
	}
	typedef const char *(*GRUTF8)(id, SEL);
	const char *bytes = ((GRUTF8)objc_msgSend)(value,
	                                           sel_registerName("UTF8String"));
	if (bytes == nullptr || bytes[0] == '\\0')
	{
		lua_pushnil(L);
		return 1;
	}
	lua_pushstring(L, bytes);
	return 1;
}

int w_httpDownload(lua_State *L)
{
	const char *url = luaL_checkstring(L, 1);
	const char *destination = luaL_checkstring(L, 2);
	const char *userAgent = luaL_optstring(L, 3, "gen1recomp");
	const char *accept = luaL_optstring(L, 4, "");
	Class cls = objc_getClass("GRPickerBridge");
	if (cls == nullptr)
	{
		lua_pushboolean(L, 0);
		return 1;
	}
	typedef signed char (*GRDownload)(Class, SEL, const char *, const char *,
	                                  const char *, const char *);
	signed char ok = ((GRDownload)objc_msgSend)(
		cls, sel_registerName("httpDownloadWithUrl:destination:userAgent:accept:"),
		url, destination, userAgent, accept);
	lua_pushboolean(L, ok != 0);
	return 1;
}

// love.system.httpRequest(url, method, headers, body, userAgent) -> envelope
//
// The transport save sync needs: a chosen method, per-request auth headers,
// and the response body of a 4xx as well as a 2xx. `headers` is a flat array
// of alternating name and value strings, joined into "name: value" lines here
// because the Swift bridge takes C strings and no Foundation type may be
// NAMED in this translation unit (see w_pickFileKinds above).
//
// The single return is the response envelope -- a head line of
// "STATUS <code>" or "ERROR <text>", a newline, then the raw body -- or nil
// where the build carries no bridge at all, which src/core/HostShell.lua
// turns into an "update the app" notice rather than a failed request.
int w_httpRequest(lua_State *L)
{
	const char *url = luaL_checkstring(L, 1);
	const char *method = luaL_optstring(L, 2, "GET");

	std::string headerBlob;
	if (!lua_isnoneornil(L, 3))
	{
		luaL_checktype(L, 3, LUA_TTABLE);
		std::vector<std::string> fields;
		size_t count = luax_objlen(L, 3);
		for (size_t i = 1; i <= count; i++)
		{
			lua_rawgeti(L, 3, (int) i);
			const char *field = lua_tostring(L, -1);
			fields.push_back(field != nullptr ? field : "");
			lua_pop(L, 1);
		}
		for (size_t i = 0; i + 1 < fields.size(); i += 2)
			headerBlob += fields[i] + ": " + fields[i + 1] + "\\n";
	}

	size_t bodyLen = 0;
	const char *body = nullptr;
	if (!lua_isnoneornil(L, 4))
		body = luaL_checklstring(L, 4, &bodyLen);
	const char *ua = luaL_optstring(L, 5, "gen1recomp");

	Class cls = objc_getClass("GRPickerBridge");
	if (cls == nullptr)
	{
		lua_pushnil(L);
		return 1;
	}
	typedef id (*GRRequest)(Class, SEL, const char *, const char *,
	                        const char *, const unsigned char *, int,
	                        const char *);
	id reply = ((GRRequest)objc_msgSend)(
		cls,
		sel_registerName("httpRequestWithUrl:method:headers:body:bodyLength:userAgent:"),
		url, method, headerBlob.c_str(), (const unsigned char *) body,
		(int) bodyLen, ua);
	if (reply == nullptr)
	{
		lua_pushnil(L);
		return 1;
	}
	// NSData read through the runtime, for the same reason as above: the
	// bytes are copied out immediately, before any autorelease pool drains.
	typedef const void *(*GRBytes)(id, SEL);
	typedef unsigned long (*GRLength)(id, SEL);
	const void *bytes = ((GRBytes)objc_msgSend)(reply, sel_registerName("bytes"));
	unsigned long length = ((GRLength)objc_msgSend)(reply, sel_registerName("length"));
	if (bytes == nullptr || length == 0)
	{
		lua_pushnil(L);
		return 1;
	}
	lua_pushlstring(L, (const char *) bytes, (size_t) length);
	return 1;
}
#endif
"""

# Deterministic 24-hex-digit object IDs, chosen not to collide with the
# upstream project (grep-verified against love-11.5's pbxproj).
ID_FILE_PICKER = "6E1AC0DE0001000000000001"
ID_FILE_OBJC = "6E1AC0DE0001000000000002"
ID_FILE_HEALTH = "6E1AC0DE0001000000000003"
ID_BUILD_PICKER = "6E1AC0DE0002000000000001"
ID_BUILD_OBJC = "6E1AC0DE0002000000000002"
ID_BUILD_HEALTH = "6E1AC0DE0002000000000003"
SOURCES_PHASE_ID = "FA0B7F021A95AAF3000E1D17"  # love-ios Sources phase
IOS_APP_CONFIG_IDS = (
    "FA0B7F261A95AAF4000E1D17",  # Debug
    "FA0B7F271A95AAF4000E1D17",  # Release
    "FA0B7F281A95AAF4000E1D17",  # Distribution
)

PBX_SOURCES = (
    ("GRPickerBridge.swift", ID_FILE_PICKER, ID_BUILD_PICKER, "sourcecode.swift"),
    ("GRHealthBridge.swift", ID_FILE_HEALTH, ID_BUILD_HEALTH, "sourcecode.swift"),
    ("GRBootstrap.m", ID_FILE_OBJC, ID_BUILD_OBJC, "sourcecode.c.objc"),
)


def fail(msg):
    print(f"patch_love_src: error: {msg}", file=sys.stderr)
    sys.exit(1)


def pristine(path: Path, patched_markers=None) -> str:
    """Text of `path` before any of our patching: backed by a `.orig` stash.

    The stash is only trusted if it is itself unpatched; that protects
    against a stash accidentally taken after an earlier patch run.
    """
    patched_markers = tuple(patched_markers or (MARKER, ID_FILE_PICKER))
    orig = path.with_suffix(path.suffix + ".orig")
    if orig.is_file():
        text = orig.read_text()
        if not any(marker in text for marker in patched_markers):
            return text
    text = path.read_text()
    if any(marker in text for marker in patched_markers):
        fail(f"{path} is already patched and no pristine .orig stash exists;\n"
             f"  delete {LOVE_SRC} and re-run scripts/build_ios.sh --fetch")
    orig.write_text(text)
    return text


def copy_native_files():
    NATIVE_DST.mkdir(parents=True, exist_ok=True)
    for name in NATIVE_FILES:
        src = NATIVE_SRC / name
        if not src.is_file():
            fail(f"missing {src}")
        shutil.copy2(src, NATIVE_DST / name)
    if not ENTITLEMENTS_SRC.is_file():
        fail(f"missing {ENTITLEMENTS_SRC}")
    shutil.copy2(ENTITLEMENTS_SRC, NATIVE_DST / "love-ios.entitlements")
    print(f"patch_love_src: native files -> {NATIVE_DST}")


def patch_wrap_system():
    text = pristine(WRAP_SYSTEM)
    include_anchor = '#include "sdl/System.h"\n'
    if include_anchor not in text:
        fail(f"include anchor not found in {WRAP_SYSTEM}")
    text = text.replace(include_anchor, include_anchor + WRAP_INCLUDES, 1)
    anchor = "static const luaL_Reg functions[] ="
    if anchor not in text:
        fail(f"anchor not found in {WRAP_SYSTEM}")
    has_native_picker = re.search(r"\bint w_pickFile\s*\(", text) is not None
    bridge_funcs = WRAP_SYNC_FUNCS if has_native_picker else WRAP_FUNCS
    text = text.replace(anchor, bridge_funcs + BRIDGE_EXTRA_FUNCS + anchor, 1)
    reg_anchor = '\t{ "vibrate", w_vibrate },\n'
    if reg_anchor not in text:
        fail(f"registration anchor not found in {WRAP_SYSTEM}")
    registration = WRAP_SYNC_REGISTRATION if has_native_picker else WRAP_REGISTRATION
    text = text.replace(reg_anchor, reg_anchor + registration, 1)
    WRAP_SYSTEM.write_text(text)
    print("patch_love_src: wrap_System.cpp patched "
          "(pickFile/createFile/syncHealthSteps/httpDownload/httpRequest)")


def patch_public_documents():
    text = pristine(
        APPLE_MM,
        ("#ifdef LOVE_IOS\n"
         "\t\t\tnsdir = NSDocumentDirectory;\n"
         "#else\n",),
    )
    original = (
        "\t\tcase USER_DIRECTORY_APPSUPPORT:\n"
        "\t\t\tnsdir = NSApplicationSupportDirectory;\n"
        "\t\t\tbreak;"
    )
    replacement = (
        "\t\tcase USER_DIRECTORY_APPSUPPORT:\n"
        "#ifdef LOVE_IOS\n"
        "\t\t\tnsdir = NSDocumentDirectory;\n"
        "#else\n"
        "\t\t\tnsdir = NSApplicationSupportDirectory;\n"
        "#endif\n"
        "\t\t\tbreak;"
    )
    if original not in text:
        fail(f"iOS app-support path anchor not found in {APPLE_MM}")
    APPLE_MM.write_text(text.replace(original, replacement, 1))

    filesystem_text = pristine(
        FILESYSTEM_CPP,
        ("#ifdef LOVE_IOS\n"
         "\t\t\tsuffix.clear();\n"
         "#else\n",),
    )
    filesystem_original = (
        "\t\tstd::string suffix;\n"
        "\t\tif (isFused())\n"
        "\t\t\tsuffix = std::string(LOVE_PATH_SEPARATOR) + saveIdentity;\n"
        "\t\telse\n"
        "\t\t\tsuffix = std::string(LOVE_PATH_SEPARATOR LOVE_APPDATA_FOLDER LOVE_PATH_SEPARATOR) + saveIdentity;"
    )
    filesystem_replacement = (
        "\t\tstd::string suffix;\n"
        "#ifdef LOVE_IOS\n"
        "\t\t\tsuffix.clear();\n"
        "#else\n"
        "\t\tif (isFused())\n"
        "\t\t\tsuffix = std::string(LOVE_PATH_SEPARATOR) + saveIdentity;\n"
        "\t\telse\n"
        "\t\t\tsuffix = std::string(LOVE_PATH_SEPARATOR LOVE_APPDATA_FOLDER LOVE_PATH_SEPARATOR) + saveIdentity;\n"
        "#endif"
    )
    if filesystem_original not in filesystem_text:
        fail(f"iOS save directory suffix anchor not found in {FILESYSTEM_CPP}")
    FILESYSTEM_CPP.write_text(filesystem_text.replace(filesystem_original,
                                                       filesystem_replacement, 1))
    print("patch_love_src: iOS save directory routed to Documents root")


def patch_ios_haptics():
    text = pristine(IOS_MM, ("UIImpactFeedbackGenerator",))
    original = """void vibrate()
{
	@autoreleasepool
	{
		AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
	}
}
"""
    replacement = """void vibrate(double seconds)
{
	@autoreleasepool
	{
		UIImpactFeedbackStyle style = UIImpactFeedbackStyleLight;
		if (seconds >= 0.035)
			style = UIImpactFeedbackStyleHeavy;
		else if (seconds >= 0.02)
			style = UIImpactFeedbackStyleMedium;
		UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc]
			initWithStyle:style];
		[generator prepare];
		[generator impactOccurred];
	}
}
"""
    if original not in text:
        fail(f"iOS haptic anchor not found in {IOS_MM}")
    IOS_MM.write_text(text.replace(original, replacement, 1))

    header = pristine(IOS_H, ("void vibrate(double seconds);",))
    header_original = "void vibrate();"
    if header_original not in header:
        fail(f"iOS haptic declaration not found in {IOS_H}")
    IOS_H.write_text(header.replace(header_original, "void vibrate(double seconds);", 1))

    system = pristine(SYSTEM_CPP, ("love::ios::vibrate(seconds)",))
    system_original = "love::ios::vibrate();"
    if system_original not in system:
        fail(f"iOS haptic call site not found in {SYSTEM_CPP}")
    SYSTEM_CPP.write_text(system.replace(system_original, "love::ios::vibrate(seconds);", 1))
    print("patch_love_src: iOS haptics use Taptic Engine impact presets")


def patch_audio_pool_gate():
    header = pristine(AUDIO_H, (POOL_PAUSE_MARKER,))
    header_include_original = "#include <stack>\n#include <cmath>\n"
    header_include_replacement = "#include <stack>\n#include <cmath>\n#include <atomic>\n"
    if header_include_original not in header:
        fail(f"audio header include anchor not found in {AUDIO_H}")
    header = header.replace(header_include_original, header_include_replacement, 1)

    header_original = (
        "\tpublic:\n"
        "\t\tPoolThread(Pool *pool);\n"
        "\t\tvirtual ~PoolThread();\n"
        "\t\tvoid setFinish();\n"
        "\t\tvoid threadFunction();\n"
        "\t};\n"
    )
    header_replacement = (
        "\tpublic:\n"
        "\t\tPoolThread(Pool *pool);\n"
        "\t\tvirtual ~PoolThread();\n"
        "\t\tvoid setFinish();\n"
        "\t\tvoid setPoolPaused(bool paused);\n"
        "\t\tvoid threadFunction();\n"
        "\n"
        "\tprivate:\n"
        "\t\tstd::atomic<bool> poolPaused;\n"
        "\t\tbool poolUpdating;\n"
        "\t\tlove::thread::ConditionalRef poolCondition;\n"
        "\t};\n"
    )
    if header_original not in header:
        fail(f"PoolThread declaration anchor not found in {AUDIO_H}")
    AUDIO_H.write_text(header.replace(header_original, header_replacement, 1))

    text = pristine(AUDIO_CPP, (POOL_PAUSE_MARKER,))

    ctor_original = (
        "Audio::PoolThread::PoolThread(Pool *pool)\n"
        "\t: pool(pool)\n"
        "\t, finish(false)\n"
        "{\n"
    )
    ctor_replacement = (
        "Audio::PoolThread::PoolThread(Pool *pool)\n"
        "\t: pool(pool)\n"
        "\t, finish(false)\n"
        "\t, poolPaused(false)\n"
        "\t, poolUpdating(false)\n"
        "{\n"
    )
    if ctor_original not in text:
        fail(f"PoolThread constructor anchor not found in {AUDIO_CPP}")
    text = text.replace(ctor_original, ctor_replacement, 1)

    loop_original = "\t\tpool->update();\n\t\tsleep(5);\n"
    loop_replacement = (
        "\t\tbool updatePool = false;\n"
        "\t\t{\n"
        "\t\t\tthread::Lock lock(mutex);\n"
        "\t\t\tif (!poolPaused.load(std::memory_order_acquire))\n"
        "\t\t\t{\n"
        "\t\t\t\tpoolUpdating = true;\n"
        "\t\t\t\tupdatePool = true;\n"
        "\t\t\t}\n"
        "\t\t}\n"
        "\n"
        "\t\tif (updatePool)\n"
        "\t\t{\n"
        "\t\t\tpool->update();\n"
        "\n"
        "\t\t\tthread::Lock lock(mutex);\n"
        "\t\t\tpoolUpdating = false;\n"
        "\t\t\tpoolCondition->broadcast();\n"
        "\t\t}\n"
        "\n"
        "\t\tsleep(5);\n"
    )
    if loop_original not in text:
        fail(f"pool update loop anchor not found in {AUDIO_CPP}")
    text = text.replace(loop_original, loop_replacement, 1)

    finish_original = (
        "void Audio::PoolThread::setFinish()\n"
        "{\n"
        "\tthread::Lock lock(mutex);\n"
        "\tfinish = true;\n"
        "}\n"
    )
    finish_replacement = (
        "void Audio::PoolThread::setFinish()\n"
        "{\n"
        "\tthread::Lock lock(mutex);\n"
        "\tfinish = true;\n"
        "}\n"
        "\n"
        "void Audio::PoolThread::setPoolPaused(bool paused)\n"
        "{\n"
        "\tthread::Lock lock(mutex);\n"
        "\tpoolPaused.store(paused, std::memory_order_release);\n"
        "\tif (paused)\n"
        "\t{\n"
        "\t\twhile (poolUpdating)\n"
        "\t\t\tpoolCondition->wait(mutex);\n"
        "\t}\n"
        "}\n"
    )
    if finish_original not in text:
        fail(f"setFinish anchor not found in {AUDIO_CPP}")
    text = text.replace(finish_original, finish_replacement, 1)

    pause_original = (
        "#else\n"
        "\talcMakeContextCurrent(nullptr);\n"
        "#endif\n"
        "}\n"
        "\n"
        "void Audio::resumeContext()\n"
    )
    pause_replacement = (
        "#else\n"
        "\tif (poolThread)\n"
        "\t\tpoolThread->setPoolPaused(true);\n"
        "\talcMakeContextCurrent(nullptr);\n"
        "#endif\n"
        "}\n"
        "\n"
        "void Audio::resumeContext()\n"
    )
    if pause_original not in text:
        fail(f"pauseContext anchor not found in {AUDIO_CPP}")
    text = text.replace(pause_original, pause_replacement, 1)

    resume_original = (
        "#else\n"
        "\tif (context && alcGetCurrentContext() != context)\n"
        "\t\talcMakeContextCurrent(context);\n"
        "#endif\n"
    )
    resume_replacement = (
        "#else\n"
        "\tif (context && alcGetCurrentContext() != context)\n"
        "\t\talcMakeContextCurrent(context);\n"
        "\tif (poolThread)\n"
        "\t\tpoolThread->setPoolPaused(false);\n"
        "#endif\n"
    )
    if resume_original not in text:
        fail(f"resumeContext anchor not found in {AUDIO_CPP}")
    text = text.replace(resume_original, resume_replacement, 1)

    AUDIO_CPP.write_text(text)
    print("patch_love_src: audio pool thread gated while the context is paused")


IOS_AUDIO_EVENT_HELPER = """static void gr_pushAudioEvent(const char *name)
{
	auto ev = love::Module::getInstance<love::event::Event>(love::Module::M_EVENT);
	if (ev == nullptr)
		return;

	love::event::Message *msg = new love::event::Message(name);
	ev->push(msg);
	msg->release();
}

static bool gr_routeRecoveryPending = false;
static unsigned int gr_routeRecoveryAttempts = 0;

"""

IOS_ROUTE_CHANGE_METHOD = """
- (void)finishAudioRouteChange
{
	@synchronized (self)
	{
		NSError *err = nil;
		if (![[AVAudioSession sharedInstance] setActive:YES error:&err])
		{
			NSLog(@"Error reactivating AVAudioSession: %@", [err localizedDescription]);
			if (++gr_routeRecoveryAttempts < 8)
			{
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
				               dispatch_get_main_queue(), ^{
					[self finishAudioRouteChange];
				});
			}
			else
			{
				gr_routeRecoveryPending = false;
			}
			return;
		}

		gr_routeRecoveryPending = false;
		gr_routeRecoveryAttempts = 0;
		auto resumed = love::Module::getInstance<love::audio::Audio>(love::Module::M_AUDIO);
		if (!resumed)
			return;
		resumed->resumeContext();
		gr_pushAudioEvent("audioreset");
	}
}

- (void)audioSessionRouteChange:(NSNotification *)note
{
	@synchronized (self)
	{
		NSNumber *reason = note.userInfo[AVAudioSessionRouteChangeReasonKey];
		NSUInteger value = reason.unsignedIntegerValue;
		if (value != AVAudioSessionRouteChangeReasonOldDeviceUnavailable
			&& value != AVAudioSessionRouteChangeReasonNewDeviceAvailable)
			return;

		auto audio = love::Module::getInstance<love::audio::Audio>(love::Module::M_AUDIO);
		if (!audio)
		{
			NSLog(@"LoveAudioInterruptionListener could not get love audio module");
			return;
		}

		if (gr_routeRecoveryPending)
			return;
		gr_routeRecoveryPending = true;
		gr_routeRecoveryAttempts = 0;

		dispatch_async(dispatch_get_main_queue(), ^{
			@synchronized (self)
			{
				auto suspended = love::Module::getInstance<love::audio::Audio>(love::Module::M_AUDIO);
				if (!suspended)
				{
					gr_routeRecoveryPending = false;
					return;
				}
				gr_pushAudioEvent("audiosuspend");
				suspended->pauseContext();
			}
			[self finishAudioRouteChange];
		});
	}
}
"""

IOS_ROUTE_OBSERVER = """
		[center addObserver:[LoveAudioInterruptionListener shared]
			   selector:@selector(audioSessionRouteChange:)
			       name:AVAudioSessionRouteChangeNotification
			     object:session];
"""


def patch_ios_audio_route():
    text = IOS_MM.read_text()
    if AUDIO_EVENT_MARKER in text:
        print("patch_love_src: iOS audio route-change handling already present")
        return

    include_anchor = '#include "modules/audio/Audio.h"\n'
    if include_anchor not in text:
        fail(f"audio module include not found in {IOS_MM}")
    text = text.replace(
        include_anchor, include_anchor + '#include "modules/event/Event.h"\n', 1)

    listener_anchor = "@interface LoveAudioInterruptionListener : NSObject\n"
    if listener_anchor not in text:
        fail(f"audio listener interface not found in {IOS_MM}")
    listener_replacement = (
        IOS_AUDIO_EVENT_HELPER
        + listener_anchor
        + "- (void)finishAudioRouteChange;\n"
        + "@end\n"
    )
    text = text.replace(listener_anchor + "@end\n", listener_replacement, 1)

    interruption_original = (
        "\t\tNSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];\n"
        "\t\tif (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan)\n"
        "\t\t\taudio->pauseContext();\n"
        "\t\telse\n"
        "\t\t\taudio->resumeContext();\n"
        "\t}\n"
        "}\n"
    )
    interruption_replacement = (
        "\t\tNSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];\n"
        "\t\tif (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan)\n"
        "\t\t{\n"
        "\t\t\tgr_pushAudioEvent(\"audiosuspend\");\n"
        "\t\t\taudio->pauseContext();\n"
        "\t\t}\n"
        "\t\telse\n"
        "\t\t{\n"
        "\t\t\taudio->resumeContext();\n"
        "\t\t\tgr_pushAudioEvent(\"audioreset\");\n"
        "\t\t}\n"
        "\t}\n"
        "}\n"
        + IOS_ROUTE_CHANGE_METHOD
    )
    if interruption_original not in text:
        fail(f"audio interruption handler not found in {IOS_MM}")
    text = text.replace(interruption_original, interruption_replacement, 1)

    active_original = (
        "\t\t\tNSLog(@\"ERROR:could not get love audio module\");\n"
        "\t\t\treturn;\n"
        "\t\t}\n"
        "\t\taudio->resumeContext();\n"
        "\t}\n"
        "}\n"
    )
    active_replacement = (
        "\t\t\tNSLog(@\"ERROR:could not get love audio module\");\n"
        "\t\t\treturn;\n"
        "\t\t}\n"
        "\t\taudio->resumeContext();\n"
        "\t\tgr_pushAudioEvent(\"audioreset\");\n"
        "\t}\n"
        "}\n"
    )
    if active_original not in text:
        fail(f"applicationBecameActive handler not found in {IOS_MM}")
    text = text.replace(active_original, active_replacement, 1)

    observer_anchor = (
        "\t\t[center addObserver:[LoveAudioInterruptionListener shared]\n"
        "\t\t\t   selector:@selector(audioSessionInterruption:)\n"
        "\t\t\t       name:AVAudioSessionInterruptionNotification\n"
        "\t\t\t     object:session];\n"
    )
    if observer_anchor not in text:
        fail(f"audio interruption observer not found in {IOS_MM}")
    text = text.replace(observer_anchor, observer_anchor + IOS_ROUTE_OBSERVER, 1)

    IOS_MM.write_text(text)
    print("patch_love_src: iOS audio route changes suspend and rebuild playback")


def patch_pbxproj():
    text = pristine(PBXPROJ)

    build_files = "".join(
        f"\t\t{build_id} /* {name} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};\n"
        for name, file_id, build_id, _ in PBX_SOURCES
    )
    anchor = "/* Begin PBXBuildFile section */\n"
    if anchor not in text:
        fail("PBXBuildFile section not found")
    text = text.replace(anchor, anchor + build_files, 1)

    file_refs = "".join(
        f"\t\t{file_id} /* {name} */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = {ftype}; "
        f"name = {name}; path = ios/native/{name}; "
        f"sourceTree = SOURCE_ROOT; }};\n"
        for name, file_id, _, ftype in PBX_SOURCES
    )
    anchor = "/* Begin PBXFileReference section */\n"
    if anchor not in text:
        fail("PBXFileReference section not found")
    text = text.replace(anchor, anchor + file_refs, 1)

    # Add the files to the love-ios Sources phase.
    phase_re = re.compile(
        re.escape(SOURCES_PHASE_ID)
        + r" /\* Sources \*/ = \{.*?files = \(\n", re.S)
    m = phase_re.search(text)
    if not m:
        fail("love-ios Sources phase not found")
    insertion = "".join(
        f"\t\t\t\t{build_id} /* {name} in Sources */,\n"
        for name, _, build_id, _ in PBX_SOURCES
    )
    text = text[: m.end()] + insertion + text[m.end():]

    # Swift + modern deployment target + HealthKit entitlements on the
    # love-ios app target only (UTType and forExporting need iOS 14;
    # liblove stays as upstream).
    for config_id in IOS_APP_CONFIG_IDS:
        cfg_re = re.compile(
            re.escape(config_id) + r" /\* \w+ \*/ = \{.*?buildSettings = \{\n",
            re.S)
        m = cfg_re.search(text)
        if not m:
            fail(f"build configuration {config_id} not found")
        settings = (
            "\t\t\t\tSWIFT_VERSION = 5.0;\n"
            "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;\n"
            "\t\t\t\tPRODUCT_NAME = \"gen1recomp++\";\n"
            "\t\t\t\tEXECUTABLE_NAME = \"gen1recomp++\";\n"
            '\t\t\t\tCODE_SIGN_ENTITLEMENTS = "ios/native/love-ios.entitlements";\n'
        )
        text = text[: m.end()] + settings + text[m.end():]

    PBXPROJ.write_text(text)
    print("patch_love_src: love.xcodeproj patched (native sources + Swift + entitlements)")


def main():
    if not LOVE_SRC.is_dir():
        fail("love-src/ missing; run scripts/build_ios.sh --fetch first")
    copy_native_files()
    patch_public_documents()
    patch_ios_haptics()
    patch_ios_audio_route()
    patch_audio_pool_gate()
    patch_wrap_system()
    patch_pbxproj()


if __name__ == "__main__":
    main()
