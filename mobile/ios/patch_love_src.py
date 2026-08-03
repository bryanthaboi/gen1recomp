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
     love.system.createFile, and love.system.syncHealthSteps on iOS (each
     calls a GR*Bridge Swift class through the Objective-C runtime, so
     liblove never links against Swift directly).
  3. Patches love.xcodeproj so the love-ios app target compiles the native
     files (Swift 5, iOS 16 deployment -- Xcode 26+ refuses lower).
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
ENTITLEMENTS_SRC = IOS_DIR / "overlays" / "love-ios.entitlements"

NATIVE_FILES = ("GRPickerBridge.swift", "GRHealthBridge.swift", "GRBootstrap.m")

MARKER = "gen1recomp iOS picker bridge"

# Headers must land outside `namespace love { namespace system {`.
WRAP_INCLUDES = """
// %s: headers for the native-bridge functions below.
#ifdef LOVE_IOS
#include <objc/runtime.h>
#include <objc/message.h>
#include <string>
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
	{ "pickFile", w_pickFile },
	{ "createFile", w_createFile },
	{ "syncHealthSteps", w_syncHealthSteps },
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
	{ "syncHealthSteps", w_syncHealthSteps },
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


def pristine(path: Path) -> str:
    """Text of `path` before any of our patching: backed by a `.orig` stash.

    The stash is only trusted if it is itself unpatched; that protects
    against a stash accidentally taken after an earlier patch run.
    """
    orig = path.with_suffix(path.suffix + ".orig")
    if orig.is_file():
        text = orig.read_text()
        if MARKER not in text and ID_FILE_PICKER not in text:
            return text
    text = path.read_text()
    if MARKER in text or ID_FILE_PICKER in text:
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
    text = text.replace(anchor, (WRAP_SYNC_FUNCS if has_native_picker else WRAP_FUNCS) + anchor, 1)
    reg_anchor = '\t{ "vibrate", w_vibrate },\n'
    if reg_anchor not in text:
        fail(f"registration anchor not found in {WRAP_SYSTEM}")
    registration = WRAP_SYNC_REGISTRATION if has_native_picker else WRAP_REGISTRATION
    text = text.replace(reg_anchor, reg_anchor + registration, 1)
    WRAP_SYSTEM.write_text(text)
    print("patch_love_src: wrap_System.cpp patched "
          "(pickFile/createFile/syncHealthSteps)")


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

    # liblove.xcodeproj as well as the app target.
    #
    # Upstream leaves the static library at its historical 8.0.  Xcode 26 and
    # later refuse a deployment target below 12.0 outright, so patching only
    # the app project leaves the build failing inside liblove -- reported
    # against a project this script never touches, which is a confusing
    # place to land.
    lib_proj = PBXPROJ.parent.parent / "liblove.xcodeproj" / "project.pbxproj"
    if lib_proj.is_file():
        lib_text = lib_proj.read_text(encoding="utf-8")
        lib_new, n = re.subn(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;",
                             "IPHONEOS_DEPLOYMENT_TARGET = 16.0;", lib_text)
        if n and lib_new != lib_text:
            lib_proj.write_text(lib_new, encoding="utf-8")
            print(f"patch_love_src: liblove.xcodeproj deployment target "
                  f"-> 16.0 ({n} configuration(s))")

    # Swift + modern deployment target + HealthKit entitlements on the
    # love-ios app target only (UTType and forExporting need iOS 14;
    # liblove is raised alongside it, above).
    for config_id in IOS_APP_CONFIG_IDS:
        cfg_re = re.compile(
            re.escape(config_id) + r" /\* \w+ \*/ = \{.*?buildSettings = \{\n",
            re.S)
        m = cfg_re.search(text)
        if not m:
            fail(f"build configuration {config_id} not found")
        settings = (
            "\t\t\t\tSWIFT_VERSION = 5.0;\n"
            "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;\n"
            '\t\t\t\tCODE_SIGN_ENTITLEMENTS = "ios/native/love-ios.entitlements";\n'
        )
        text = text[: m.end()] + settings + text[m.end():]

    PBXPROJ.write_text(text)
    print("patch_love_src: love.xcodeproj patched (native sources + Swift + entitlements)")


def main():
    if not LOVE_SRC.is_dir():
        fail("love-src/ missing; run scripts/build_ios.sh --fetch first")
    copy_native_files()
    patch_wrap_system()
    patch_pbxproj()


if __name__ == "__main__":
    main()
