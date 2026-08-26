#!/usr/bin/env bash
# Packages the LÖVE2D Pokémon Red port into an iOS app via LÖVE 12.0's
# iOS Xcode project.
#
# Usage: scripts/build_ios.sh [--fetch] [--device] [--release] [--install]
#                             [--version X.Y.Z] [--package-only]
#
#   (default)         Simulator Debug (ad-hoc signed)
#   --device          iphoneos SDK; signing team auto-detected from the
#                     keychain when DEVELOPMENT_TEAM is not set
#   --install         after a --device build, install the app onto the
#                     first connected iPhone/iPad (unlock it first)
#   --release         Release configuration
#   --version X.Y.Z   stamp the engine version into game.love plus
#                     MARKETING_VERSION / CURRENT_PROJECT_VERSION
#   --fetch           Fetch LÖVE 12.0 sources and Apple dependencies into mobile/ios/love-src/
#   --package-only    Zip game.love + apply plist overlay; skip xcodebuild
#
# Prerequisites:
#   - macOS + Xcode (xcodebuild)
#   - mobile/ios/love-src/ (see --fetch / mobile/ios/README.md)
#
# Output: dist/ios/<Config>-<sdk>/gen1recomp++.app (convenience copy)
#         dist/ios/gen1recomp++.ipa                 (device builds only)
#         mobile/ios/build/Build/Products/<Config>-<sdk>/gen1recomp++.app

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$ROOT/mobile/ios"
LOVE_SRC="$IOS_DIR/love-src"
CACHE="$IOS_DIR/cache"
BUILD_DIR="$IOS_DIR/build"
DIST="$ROOT/dist/ios"
OVERLAY_PLIST="$IOS_DIR/overlays/love-ios.plist"
XCODE_DIR="$LOVE_SRC/platform/xcode"
PROJECT="$XCODE_DIR/love.xcodeproj"
RESOURCES_DIR="$XCODE_DIR/ios/resources"
LOVE_FILE="$RESOURCES_DIR/game.love"
LIBS_DIR="$XCODE_DIR/ios/libraries"

APP_NAME="gen1recomp++"
DISPLAY_NAME="gen1recomp++"
PRODUCT_NAME="gen1recomp++"
# Bundle ID resolution, most specific wins:
#   1. GEN1_BUNDLE_ID env var
#   2. mobile/ios/bundle_id.local (one line, gitignored — pins YOUR install
#      so rebuilds keep updating the same app on your phone)
#   3. device builds: com.gen1recomp.t<your team id> — explicit App IDs are
#      globally unique across ALL Apple accounts (and required once
#      capabilities like HealthKit are involved), so a per-team default
#      lets anyone build without colliding with someone else's app
#   4. simulator: the project default (no App ID registration involved)
BUNDLE_ID="${GEN1_BUNDLE_ID:-}"
if [ -z "$BUNDLE_ID" ] && [ -f "$IOS_DIR/bundle_id.local" ]; then
  BUNDLE_ID="$(tr -d '[:space:]' < "$IOS_DIR/bundle_id.local")"
fi
LOVE_VERSION="$(tr -d '[:space:]' < "$IOS_DIR/LOVE_VERSION" 2>/dev/null || echo 12.0)"
LOVE_SOURCE_REF="${LOVE_SOURCE_REF:-main}"
APPLE_DEPENDENCIES_REF="${APPLE_DEPENDENCIES_REF:-main}"
LOVE_SOURCE_REPO="https://github.com/love2d/love.git"
APPLE_DEPENDENCIES_REPO="https://github.com/love2d/love-apple-dependencies.git"

FETCH=false
DEVICE=false
RELEASE=false
PACKAGE_ONLY=false
INSTALL=false
CREATE_IPA=false
# Last resort for an incomplete source export, mirroring build_android.sh.
MANIFEST_BASE_URL="${MANIFEST_BASE_URL:-https://raw.githubusercontent.com/bryanthaboi/gen1recomp/main}"
MANIFESTS=""

VERSION=""

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --fetch) FETCH=true ;;
    --device) DEVICE=true ;;
    --release) RELEASE=true ;;
    --package-only) PACKAGE_ONLY=true ;;
    --install) INSTALL=true ;;
    --ipa) CREATE_IPA=true ;;
    --version) VERSION="$2"; shift ;;
    -h|--help)
      sed -n '2,24p' "$0"
      exit 0
      ;;
    *) fail "unknown argument: $1 (try --fetch, --device, --release, --version, --install, or --package-only)" ;;
  esac
  shift
done

if $CREATE_IPA; then
  DEVICE=true
fi

VERSION_CODE=""
if [ -n "$VERSION" ]; then
  if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "invalid --version '$VERSION' (expected X.Y.Z)"
  fi
  major="${VERSION%%.*}"
  rest="${VERSION#*.}"
  minor="${rest%%.*}"
  patch="${rest##*.}"
  VERSION_CODE=$((major * 10000 + minor * 100 + patch))
fi

# ---------------------------------------------------------- signing identity
# Auto-detect the Apple Development team when the caller didn't set one.
# Prefer a *valid* identity from `find-identity` (the parenthetical there is
# the cert id, not the team), then read that cert's OU. Scanning every
# "Apple Development" certificate picks expired personal/work certs first.
detect_team() {
  local cn
  cn="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n -E 's/.*"Apple Development: ([^"]+)".*/\1/p' \
    | head -1)"
  [ -n "$cn" ] || return 1
  security find-certificate -c "Apple Development: $cn" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' \
    | head -1
}
if $DEVICE && [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  DEVELOPMENT_TEAM="$(detect_team || true)"
  if [ -n "$DEVELOPMENT_TEAM" ]; then
    say "signing team auto-detected from keychain: $DEVELOPMENT_TEAM"
  else
    fail "no Apple signing identity found.
  Open Xcode -> Settings -> Accounts, press +, and sign in with your
  Apple ID (a free account works). That creates the certificate this
  script signs with. Then re-run this command."
  fi
fi
if [ -z "$BUNDLE_ID" ]; then
  BUNDLE_ID="com.theboisclub.gen1recompplusplus"
fi

# --------------------------------------------------------------- host checks
if [ "$(uname -s)" != "Darwin" ]; then
  fail "iOS builds require macOS (Darwin). This host is $(uname -s).
  Run scripts/build_ios.sh on a Mac with Xcode installed."
fi

if ! $PACKAGE_ONLY; then
  command -v xcodebuild >/dev/null 2>&1 \
    || fail "xcodebuild not found. Install Xcode from the App Store, then run:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

# --------------------------------------------------------------- fetch love-src
fetch_love_ios() {
  mkdir -p "$CACHE"
  local tmp
  tmp="$(mktemp -d "$CACHE/extract.XXXXXX")"
  say "fetching LÖVE $LOVE_VERSION sources ($LOVE_SOURCE_REF)"
  git clone --depth 1 --branch "$LOVE_SOURCE_REF" "$LOVE_SOURCE_REPO" "$tmp/love" \
    || fail "failed to fetch LÖVE sources from $LOVE_SOURCE_REPO"
  say "fetching Apple dependencies ($APPLE_DEPENDENCIES_REF)"
  git clone --depth 1 --branch "$APPLE_DEPENDENCIES_REF" "$APPLE_DEPENDENCIES_REPO" "$tmp/dependencies" \
    || fail "failed to fetch Apple dependencies from $APPLE_DEPENDENCIES_REPO"
  rm -rf "$LOVE_SRC"
  mv "$tmp/love" "$LOVE_SRC"
  mkdir -p "$LIBS_DIR" "$XCODE_DIR/shared"
  cp -R "$tmp/dependencies/iOS/libraries/." "$LIBS_DIR"
  cp -R "$tmp/dependencies/shared/." "$XCODE_DIR/shared"
  rm -rf "$tmp"
  say "love-src ready (LÖVE $LOVE_VERSION)"
}

if [ ! -d "$XCODE_DIR/love.xcodeproj" ]; then
  if $FETCH; then
    fetch_love_ios
  else
    fail "LÖVE $LOVE_VERSION iOS sources not found at mobile/ios/love-src/.
  Fetch them:
    scripts/build_ios.sh --fetch
  See mobile/ios/README.md."
  fi
elif $FETCH; then
  say "love-src already present; skipping fetch (delete mobile/ios/love-src to refresh)"
fi

[ -d "$XCODE_DIR/love.xcodeproj" ] \
  || fail "missing $PROJECT after fetch"

# --------------------------------------------------------------- apple libraries
require_ios_libraries() {
  if [ -d "$LIBS_DIR/SDL2.xcframework" ] && [ -d "$XCODE_DIR/shared/Frameworks/SDL3.xcframework" ]; then
    return 0
  fi
  fail "prebuilt iOS libraries missing at:
  $LIBS_DIR
  and shared/Frameworks.

  Re-fetch the LÖVE $LOVE_VERSION source tree and its Apple dependencies:

    scripts/build_ios.sh --fetch"
}

require_ios_libraries

# --------------------------------------------------------------- branding / plist
apply_ios_branding() {
  [ -f "$OVERLAY_PLIST" ] || fail "missing overlay plist: $OVERLAY_PLIST"
  local dest="$XCODE_DIR/ios/love-ios.plist"
  say "applying iOS branding (portrait + landscape Info.plist, display name)"
  cp "$OVERLAY_PLIST" "$dest"
}

verify_documents_overlay() {
  local sharing in_place
  sharing="$(/usr/libexec/PlistBuddy -c 'Print :UIFileSharingEnabled' "$OVERLAY_PLIST" 2>/dev/null || true)"
  in_place="$(/usr/libexec/PlistBuddy -c 'Print :LSSupportsOpeningDocumentsInPlace' "$OVERLAY_PLIST" 2>/dev/null || true)"
  [ "$sharing" = "true" ] && [ "$in_place" = "true" ] \
    || fail "iOS plist overlay must enable UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace"
}

apply_ios_icon() {
  local source="$ROOT/assets/logo/logo.png"
  local target="$XCODE_DIR/Images.xcassets/iOS AppIcon.appiconset"
  [ -f "$source" ] || fail "missing iOS icon source: $source"
  [ -d "$target" ] || fail "missing iOS app icon set: $target"
  local icon="$BUILD_DIR/gen1recomp-ios-icon.png"
  mkdir -p "$BUILD_DIR"
  if command -v magick >/dev/null 2>&1; then
    magick -size 1024x1024 xc:black \
      \( "$source" -resize 900x900 \) -gravity center -composite \
      -alpha off "$icon" || fail "could not create iOS app icon: $source"
  else
    local scaled="$BUILD_DIR/gen1recomp-logo.png"
    sips -Z 900 "$source" --out "$scaled" >/dev/null \
      || fail "could not resize iOS app icon source: $source"
    sips -p 1024 1024 --padColor 000000 "$scaled" --out "$icon" >/dev/null \
      || fail "could not center iOS app icon source: $source"
  fi
  local entry name size
  while IFS=: read -r name size; do
    sips -z "$size" "$size" "$icon" --out "$target/$name" >/dev/null
  done <<'EOF'
icon-1024pt@1x.png:1024
icon-29pt@1x.png:29
icon-29pt@2x.png:58
icon-29pt@3x.png:87
icon-40pt@1x.png:40
icon-40pt@2x.png:80
icon-40pt@3x.png:120
icon-60pt@2x.png:120
icon-60pt@3x.png:180
icon-76pt@1x.png:76
icon-76pt@2x.png:152
icon-83.5pt@2x.png:167
EOF
}

# --------------------------------------------------------------- game.love
# Every version's import manifest has to ship or that game's ROM import fails in
# the built app: decodeManifest (src/import/RomImporter.lua) errors outright when
# one is absent, and dev reads them off the source tree, so the miss only ever
# shows up in a build.  iOS shipped without the Yellow one in 0.1.45 to 0.1.47
# for exactly that reason.
#
# The list is READ OUT OF src/core/GameVersion.lua rather than hand-kept here, so
# a fourth version cannot silently ship without its manifest, and a missing file
# is recovered from Git or the project repo the same way build_android.sh already
# recovers Yellow's.  Recovery is a last resort for an incomplete source export:
# a manifest carries extraction metadata only, never a ROM or game data.
manifest_paths() {
  python3 - "$ROOT/src/core/GameVersion.lua" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
print(" ".join(dict.fromkeys(re.findall(r'manifest\s*=\s*"([^"]+)"', src))))
PY
}

manifest_is_valid() {
  python3 - "$1" <<'PY'
import json, pathlib, sys
try:
    m = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, ValueError):
    raise SystemExit(1)
sha = m.get("romSha1")
raise SystemExit(0 if isinstance(sha, str) and len(sha) == 40 else 1)
PY
}

ensure_manifests() {
  MANIFESTS="$(manifest_paths)"
  [ -n "$MANIFESTS" ] \
    || fail "could not read any manifest path out of src/core/GameVersion.lua"
  local rel staged
  for rel in $MANIFESTS; do
    if manifest_is_valid "$ROOT/$rel"; then continue; fi
    warn "$rel is missing or invalid; recovering it before packaging"
    staged="$(mktemp)"
    if git -C "$ROOT" show "HEAD:$rel" > "$staged" 2>/dev/null \
        && manifest_is_valid "$staged"; then
      mkdir -p "$ROOT/$(dirname "$rel")"
      mv "$staged" "$ROOT/$rel"
      say "restored $rel from this checkout's Git data"
      continue
    fi
    if command -v curl >/dev/null 2>&1 \
        && curl --fail --location --retry 2 --connect-timeout 15 \
            --output "$staged" "$MANIFEST_BASE_URL/$rel" \
        && manifest_is_valid "$staged"; then
      mkdir -p "$ROOT/$(dirname "$rel")"
      mv "$staged" "$ROOT/$rel"
      say "downloaded $rel from the project repository"
      continue
    fi
    rm -f "$staged"
    fail "$rel is unavailable: Git recovery failed and $MANIFEST_BASE_URL/$rel could not be downloaded"
  done
  say "import manifests: $MANIFESTS"
}

pack_game_love() {
  say "packing game.love for love-ios resources"
  mkdir -p "$RESOURCES_DIR"
  rm -f "$LOVE_FILE"
  # Same payload as scripts/build.sh / build_android.sh: game sources plus
  # tools/save-editor, which the launcher's Edit button opens in-process.
  # Deliberately NO fused mods: a mod inside game.love sits in the
  # read-only app bundle, so the mod manager's Delete can't remove it and
  # it reappears every launch.  Mods install as .zips at runtime instead
  # (launcher -> MODS -> Import mod .zip), the same lifecycle as every
  # other platform.
  # The launcher UI kit lives at src/ui/kit (inside src/, packed wholesale);
  # the vendored libs/flexlove tree it replaced is gone.
  # shellcheck disable=SC2086  # MANIFESTS is a deliberate word list
  (cd "$ROOT" && zip -q -9 -r "$LOVE_FILE" \
    main.lua conf.lua src data assets tools/save-editor \
    $MANIFESTS \
    -x '*.DS_Store' -x '*/.git/*' -x '*/.DS_Store' \
    -x 'data/generated/*' -x 'assets/generated/*')
  # NOTE: grep -q here would race pipefail — it exits on first match, unzip
  # dies of SIGPIPE (141), and the pipeline "fails" nondeterministically.
  # >/dev/null keeps grep reading the whole stream instead.
  if unzip -Z1 "$LOVE_FILE" \
      | grep -E '^(data|assets)/generated/[^/]+|^(data|assets)/generated/.+/' >/dev/null; then
    fail "game.love unexpectedly contains generated ROM data"
  fi
  # Same required-file gate as scripts/build.sh and scripts/build_android.sh.
  # iOS only checked App.lua, which is why the Yellow manifest shipped missing
  # in 0.1.45 through 0.1.47: decodeManifest (src/import/RomImporter.lua) errors
  # outright when a version's manifest is absent, so Import ROM on Yellow died
  # in the built app while dev, which reads the source tree, stayed green.
  # src/ui/kit/Kit.lua is on the list for the same reason: the launcher's UI
  # toolkit once lived outside src/ (libs/flexlove) and shipped missing from
  # the mobile packagers, so the launcher threw before drawing its first
  # frame.  The kit is inside src/ now; the gate stays to catch a repeat.
  archive_entries="$(unzip -Z1 "$LOVE_FILE")"
  # shellcheck disable=SC2086  # MANIFESTS is a deliberate word list
  for required in src/update/Boot.lua tools/save-editor/App.lua \
                  tools/save-editor/Kit.lua tools/save-editor/panels/Party.lua \
                  src/ui/kit/Kit.lua \
                  $MANIFESTS; do
    printf '%s\n' "$archive_entries" | grep -qx "$required" \
      || fail "game.love is missing $required"
  done
  say "game.love: $(du -h "$LOVE_FILE" | cut -f1) -> $LOVE_FILE"

  if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    say "stamping engine version $VERSION into game.love"
    local stamp_dir
    stamp_dir="$(mktemp -d)"
    mkdir -p "$stamp_dir/src/core"
    sed -E "s/(engine[[:space:]]*=[[:space:]]*\")([^\"]*)(\")/\1$VERSION\3/" \
      "$ROOT/src/core/Version.lua" > "$stamp_dir/src/core/Version.lua"
    (cd "$stamp_dir" && zip -q "$LOVE_FILE" src/core/Version.lua)
    local version_re
    version_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
    unzip -p "$LOVE_FILE" src/core/Version.lua \
      | grep -Eq "engine[[:space:]]*=[[:space:]]*\"$version_re\"" \
      || fail "version stamp failed: game.love does not report engine $VERSION"
    rm -rf "$stamp_dir"
    say "stamped engine version: $VERSION"
  else
    say "no X.Y.Z --version,  shipping default engine (no stamp)"
  fi
}

# Ensure game.love is in the love-ios Copy Bundle Resources phase (idempotent).
ensure_game_love_in_xcode() {
  local pbx="$XCODE_DIR/love.xcodeproj/project.pbxproj"
  [ -f "$pbx" ] || fail "missing $pbx"

  if grep -q 'ios/resources/game.love' "$pbx"; then
    return 0
  fi

  say "wiring game.love into love-ios Copy Bundle Resources"
  python3 - "$pbx" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
if "ios/resources/game.love" in text:
    raise SystemExit(0)

file_ref = "A1B2C3D41E5F678901234567"
build_file = "A1B2C3D41E5F678901234568"

file_ref_entry = (
    f"\t\t{file_ref} /* game.love */ = {{isa = PBXFileReference; "
    f"lastKnownFileType = file; name = game.love; "
    f'path = ios/resources/game.love; sourceTree = "<group>"; }};\n'
)
build_file_entry = (
    f"\t\t{build_file} /* game.love in Resources */ = {{isa = PBXBuildFile; "
    f"fileRef = {file_ref} /* game.love */; }};\n"
)

# PBXBuildFile section
marker = "/* Begin PBXBuildFile section */\n"
if marker not in text:
    raise SystemExit("PBXBuildFile section not found")
text = text.replace(marker, marker + build_file_entry, 1)

# PBXFileReference section
marker = "/* Begin PBXFileReference section */\n"
if marker not in text:
    raise SystemExit("PBXFileReference section not found")
text = text.replace(marker, marker + file_ref_entry, 1)

# Add to love-ios Resources build phase (FA0B7F041A95AAF3000E1D17)
old = (
    "\t\tFA0B7F041A95AAF3000E1D17 /* Resources */ = {\n"
    "\t\t\tisa = PBXResourcesBuildPhase;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    "\t\t\tfiles = (\n"
    "\t\t\t\tFA5D249C1A96CF4300C6FC8F /* Images.xcassets in Resources */,\n"
    "\t\t\t\tFA7C636A1A9C49570000FD29 /* Launch Screen.xib in Resources */,\n"
    "\t\t\t);\n"
)
new = (
    "\t\tFA0B7F041A95AAF3000E1D17 /* Resources */ = {\n"
    "\t\t\tisa = PBXResourcesBuildPhase;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    "\t\t\tfiles = (\n"
    "\t\t\t\tFA5D249C1A96CF4300C6FC8F /* Images.xcassets in Resources */,\n"
    "\t\t\t\tFA7C636A1A9C49570000FD29 /* Launch Screen.xib in Resources */,\n"
    f"\t\t\t\t{build_file} /* game.love in Resources */,\n"
    "\t\t\t);\n"
)
if old not in text:
    # Fallback: insert before the closing of that files = ( list if markers differ slightly
    needle = "\t\tFA0B7F041A95AAF3000E1D17 /* Resources */ = {"
    if needle not in text:
        raise SystemExit("love-ios Resources build phase not found")
    # Insert build file line after "files = (" within that block
    idx = text.index(needle)
    files_idx = text.index("files = (", idx)
    insert_at = text.index("\n", files_idx) + 1
    text = (
        text[:insert_at]
        + f"\t\t\t\t{build_file} /* game.love in Resources */,\n"
        + text[insert_at:]
    )
else:
    text = text.replace(old, new, 1)

# Add file ref to the ios group if present
ios_group = "FA5D24961A96CE0A00C6FC8F /* ios */ = {"
if ios_group in text and file_ref not in text[text.index(ios_group):text.index(ios_group)+400]:
    # Prefer adding under Resources group,  skip if structure unknown; path is absolute enough via sourceTree
    pass

path.write_text(text)
print("patched project.pbxproj")
PY
}

suppress_love_dependency_warnings() {
  local liblove_pbx="$XCODE_DIR/liblove.xcodeproj/project.pbxproj"
  local love_pbx="$XCODE_DIR/love.xcodeproj/project.pbxproj"
  [ -f "$liblove_pbx" ] || fail "missing $liblove_pbx"
  [ -f "$love_pbx" ] || fail "missing $love_pbx"

  python3 - "$liblove_pbx" "$love_pbx" <<'PY'
import pathlib
import sys

def patch_configs(path, config_ids, settings):
    text = path.read_text()
    for config_id in config_ids:
        marker = f"\t\t{config_id}"
        start = text.find(marker)
        if start < 0:
            raise SystemExit(f"missing configuration {config_id}")
        settings_start = text.find("\t\t\tbuildSettings = {\n", start)
        block_end = text.find("\n\t\t};", settings_start)
        if settings_start < 0 or block_end < 0:
            raise SystemExit(f"invalid configuration {config_id}")
        block = text[settings_start:block_end]
        lines = block.splitlines(keepends=True)
        for setting in settings:
            key = setting.split(" = ", 1)[0].strip()
            prefix = f"{key} ="
            replaced = False
            normalized = []
            for line in lines:
                if line.startswith(f"\t\t\t\t{prefix}"):
                    if not replaced:
                        normalized.append(setting)
                        replaced = True
                else:
                    normalized.append(line)
            if not replaced:
                normalized.insert(1, setting)
            lines = normalized
        normalized_block = "".join(lines)
        if normalized_block != block:
            text = text[:settings_start] + normalized_block + text[block_end:]
    path.write_text(text)

patch_configs(
    pathlib.Path(sys.argv[1]),
    (
        "FA0B78EF1A958B90000E1D17",
        "FA0B78F01A958B90000E1D17",
        "FA0B78F11A958B90000E1D17",
    ),
    (
        "\t\t\t\tCLANG_WARN_UNINITIALIZED_AUTOS = NO;\n",
        "\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = NO;\n",
        "\t\t\t\tCLANG_WARN_UNUSED_PARAMETER = NO;\n",
        "\t\t\t\tGCC_WARN_CHECK_SWITCH_STATEMENTS = NO;\n",
        "\t\t\t\tGCC_WARN_SIGN_COMPARE = NO;\n",
        "\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = NO;\n",
        "\t\t\t\tGCC_WARN_UNUSED_FUNCTION = NO;\n",
        "\t\t\t\tGCC_WARN_UNUSED_PARAMETER = NO;\n",
        "\t\t\t\tGCC_WARN_UNUSED_VARIABLE = NO;\n",
        "\t\t\t\tOTHER_CFLAGS = \"$(inherited) -Wno-sign-compare -Wno-strict-prototypes -Wno-unused-but-set-variable -Wno-unused-function -Wno-unused-parameter -Wno-unused-variable\";\n",
        "\t\t\t\tOTHER_CPLUSPLUSFLAGS = \"$(inherited) -Wno-deprecated-declarations -Wno-non-c-typedef-for-linkage -Wno-sign-compare -Wno-switch -Wno-unguarded-availability-new -Wno-unused-but-set-variable -Wno-unused-function -Wno-unused-parameter -Wno-unused-private-field -Wno-unused-variable\";\n",
    ),
)
patch_configs(
    pathlib.Path(sys.argv[2]),
    (
        "FA0B7F261A95AAF4000E1D17",
        "FA0B7F271A95AAF4000E1D17",
        "FA0B7F281A95AAF4000E1D17",
    ),
    (
        "\t\t\t\tCLANG_WARN_UNDECLARED_SELECTOR = NO;\n",
        "\t\t\t\tCLANG_WARN_UNUSED_PARAMETER = NO;\n",
        "\t\t\t\tOTHER_CFLAGS = \"$(inherited) -Wno-undeclared-selector -Wno-unused-parameter\";\n",
    ),
)
PY
}

# --------------------------------------------------------------- xcodebuild
# love.system.pickFile and createFile are a native bridge compiled in by
# mobile/ios/patch_love_src.py, not part of LÖVE.  A build that skipped the
# patch still links and still runs, then finds the field nil the moment anyone
# taps Import ROM (#482).  #539 made that degrade to the copy-into-Files flow
# rather than crash, which is the right floor, but a build with no picker at all
# is a silent downgrade, so fail here instead of shipping one.
#
# Checked against the built binary rather than the source, because patching
# love-src proves nothing about what Xcode actually compiled: the shipped
# 0.1.45/0.1.46/0.1.47 IPAs all DO carry the bridge, so the reports that blamed
# a missing patch step were self-built IPAs, exactly the case this catches.
verify_native_bridge() {
  local app="$1"
  local exe bin missing=""
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
         "$app/Info.plist" 2>/dev/null || true)"
  bin="$app/${exe:-love}"
  [ -f "$bin" ] || bin="$app/love"
  if [ ! -f "$bin" ]; then
    warn "no executable inside $(basename "$app"); skipping native bridge check"
    return 0
  fi
  # grep -q here would race pipefail the same way pack_game_love documents:
  # it exits on first match, strings dies of SIGPIPE, the pipeline "fails"
  # nondeterministically.  >/dev/null keeps grep reading the whole stream.
  for sym in pickFile createFile; do
    strings -a "$bin" | grep -x "$sym" >/dev/null || missing="$missing $sym"
  done
  if [ -n "$missing" ]; then
    fail "built app has no native bridge (missing:$missing).
  Import ROM would fall back to copy-into-Files instead of opening the picker.
  mobile/ios/patch_love_src.py did not take. Re-run:
    scripts/build_ios.sh --fetch && scripts/build_ios.sh"
  fi
  say "native bridge present (pickFile, createFile)"
}

verify_documents_configuration() {
  local app="$1"
  local plist="$app/Info.plist"
  local sharing in_place
  [ -f "$plist" ] || fail "built iOS app is missing Info.plist: $plist"
  sharing="$(/usr/libexec/PlistBuddy -c 'Print :UIFileSharingEnabled' "$plist" 2>/dev/null || true)"
  in_place="$(/usr/libexec/PlistBuddy -c 'Print :LSSupportsOpeningDocumentsInPlace' "$plist" 2>/dev/null || true)"
  [ "$sharing" = "true" ] && [ "$in_place" = "true" ] \
    || fail "built iOS app does not expose its Documents folder in $(basename "$app")"
  say "public Documents exposure present (file sharing + in-place access)"
}

verify_game_payload() {
  local app="$1"
  [ -s "$app/game.love" ] \
    || fail "built iOS app is missing game.love: $app"
  say "game.love present ($(du -h "$app/game.love" | cut -f1))"
}

SHADER_BRIDGE_LIB=""
SHADER_BRIDGE_NAME="liblibrashader_bridge.a"
SHADER_BRIDGE_OBJ="librashader_bridge.o"

SHADER_BRIDGE_ARCHS=""

rust_targets_for_sdk() {
  if [ "$1" = "iphoneos" ]; then
    printf 'aarch64-apple-ios'
  else
    printf 'aarch64-apple-ios-sim x86_64-apple-ios'
  fi
}

build_shader_bridge_slice() {
  local rust_target="$1"
  local crate="$ROOT/tools/shaderfx-bridge"
  local built="$crate/target/$rust_target/release/$SHADER_BRIDGE_NAME"
  if [ -f "$built" ]; then
    printf '%s' "$built"
    return 0
  fi
  if command -v cargo >/dev/null 2>&1 \
      && rustup target list --installed 2>/dev/null \
         | grep -x "$rust_target" >/dev/null; then
    say "building the ShaderFX bridge with cargo ($rust_target)" >&2
    if (cd "$crate" && IPHONEOS_DEPLOYMENT_TARGET=15.0 \
        cargo build --release --target "$rust_target" >/dev/null 2>&1); then
      printf '%s' "$built"
      return 0
    fi
  fi
  return 1
}

prelink_shader_bridge_slice() {
  local archive="$1" sdk="$2" out="$3"
  local arch platform sdk_version syms objcopy tmp
  arch="$(lipo -archs "$archive" 2>/dev/null | awk '{print $1}')"
  [ -n "$arch" ] || return 1
  if [ "$sdk" = "iphoneos" ]; then platform="ios"; else platform="ios-simulator"; fi
  sdk_version="$(xcrun --sdk "$sdk" --show-sdk-version 2>/dev/null)"
  [ -n "$sdk_version" ] || return 1
  syms="$LIBS_DIR/librashader_bridge.exports"
  printf '_librashader_translate_preset\n_librashader_free_string\n' > "$syms"
  tmp="$out.tmp"
  xcrun ld -r -arch "$arch" -platform_version "$platform" 15.0 "$sdk_version" \
    -all_load -exported_symbols_list "$syms" -o "$tmp" "$archive" || return 1
  objcopy="$(ls "$(rustc --print sysroot 2>/dev/null)"/lib/rustlib/*/bin/rust-objcopy 2>/dev/null | head -1)"
  if [ -n "$objcopy" ] && "$objcopy" --remove-section __LLVM,__bitcode \
       --remove-section __LLVM,__cmdline "$tmp" "$out" 2>/dev/null; then
    rm -f "$tmp"
  else
    mv "$tmp" "$out"
  fi
}

bundle_shader_bridge_ios() {
  local rust_targets="$1" sdk="$2"
  local src="${SHADERFX_BRIDGE_IOS:-}"
  local slices=() objs=() target slice obj i
  SHADER_BRIDGE_LIB=""
  SHADER_BRIDGE_ARCHS=""
  rm -f "$LIBS_DIR/$SHADER_BRIDGE_NAME" "$LIBS_DIR/$SHADER_BRIDGE_OBJ" "$LIBS_DIR"/librashader_bridge.*.o
  if [ -n "$src" ]; then
    if [ -f "$src" ]; then
      slices+=("$src")
    else
      warn "SHADERFX_BRIDGE_IOS=$src does not exist"
    fi
  else
    for target in $rust_targets; do
      if slice="$(build_shader_bridge_slice "$target")"; then
        slices+=("$slice")
      fi
    done
  fi
  if [ "${#slices[@]}" -gt 0 ]; then
    mkdir -p "$LIBS_DIR"
    i=0
    for slice in "${slices[@]}"; do
      i=$((i + 1))
      obj="$LIBS_DIR/librashader_bridge.$i.o"
      if prelink_shader_bridge_slice "$slice" "$sdk" "$obj"; then
        objs+=("$obj")
      else
        warn "could not prelink $(basename "$slice") for $sdk"
      fi
    done
  fi
  if [ "${#objs[@]}" -eq 1 ]; then
    mv "${objs[0]}" "$LIBS_DIR/$SHADER_BRIDGE_OBJ"
  elif [ "${#objs[@]}" -gt 1 ]; then
    lipo -create "${objs[@]}" -output "$LIBS_DIR/$SHADER_BRIDGE_OBJ"
    rm -f "${objs[@]}"
  fi
  if [ -f "$LIBS_DIR/$SHADER_BRIDGE_OBJ" ]; then
    SHADER_BRIDGE_LIB="$LIBS_DIR/$SHADER_BRIDGE_OBJ"
    SHADER_BRIDGE_ARCHS="$(lipo -archs "$SHADER_BRIDGE_LIB" 2>/dev/null || true)"
    say "linking $SHADER_BRIDGE_OBJ for SHADER FX preset conversion (${SHADER_BRIDGE_ARCHS:-unknown arch})"
  else
    warn "$SHADER_BRIDGE_NAME not found: this build can run converted presets but not CONVERT new ones (set SHADERFX_BRIDGE_IOS, or install cargo plus one of: rustup target add $rust_targets)"
  fi
}

verify_shader_bridge() {
  local app="$1"
  local exe bin
  if [ -z "$SHADER_BRIDGE_LIB" ]; then
    warn "no SHADER FX bridge in this build: CONVERT stays unavailable, converted presets still run"
    return 0
  fi
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
         "$app/Info.plist" 2>/dev/null || true)"
  bin="$app/${exe:-love}"
  [ -f "$bin" ] || bin="$app/love"
  if [ ! -f "$bin" ]; then
    warn "no executable inside $(basename "$app"); skipping SHADER FX bridge check"
    return 0
  fi
  if nm "$bin" 2>/dev/null | grep -E ' _librashader_translate_preset$' >/dev/null \
     || xcrun dyld_info -exports "$bin" 2>/dev/null \
        | grep -E ' _librashader_translate_preset$' >/dev/null; then
    say "SHADER FX bridge present (librashader_translate_preset)"
    return 0
  fi
  fail "built app does not carry the SHADER FX bridge symbols.
  $SHADER_BRIDGE_OBJ was linked but librashader_translate_preset is absent,
  so SHADER FX CONVERT would fail at runtime.
  Rebuild after: rm -rf tools/shaderfx-bridge/target"
}

run_xcodebuild() {
  local config sdk destination
  if $RELEASE; then
    config="Release"
  else
    config="Debug"
  fi

  if $DEVICE; then
    sdk="iphoneos"
    destination="generic/platform=iOS"
  else
    sdk="iphonesimulator"
    destination="generic/platform=iOS Simulator"
  fi

  mkdir -p "$BUILD_DIR"

  bundle_shader_bridge_ios "$(rust_targets_for_sdk "$sdk")" "$sdk"

  # Prefer -target + SYMROOT over -derivedDataPath: modern Xcode requires
  # -scheme whenever -derivedDataPath is set, and love-ios ships no shared schemes.
  # Always stamp both: the overlay plist expands $(MARKETING_VERSION) /
  # $(CURRENT_PROJECT_VERSION), and love-ios has no project-level defaults.
  local marketing_version="$LOVE_VERSION"
  local project_version="1"
  if [ -n "$VERSION" ]; then
    marketing_version="$VERSION"
    project_version="$VERSION_CODE"
  fi

  local args=(
    -project "$PROJECT"
    -target love-ios
    -configuration "$config"
    -sdk "$sdk"
    -destination "$destination"
    SYMROOT="$BUILD_DIR/Build/Products"
    OBJROOT="$BUILD_DIR/Build/Intermediates"
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
    MARKETING_VERSION="$marketing_version"
    CURRENT_PROJECT_VERSION="$project_version"
    INFOPLIST_KEY_UIFileSharingEnabled=YES
    INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace=YES
    IPHONEOS_DEPLOYMENT_TARGET=15.0
    ONLY_ACTIVE_ARCH=NO
    DISABLE_MANUAL_TARGET_ORDER_BUILD_WARNING=YES
  )
  if [ -n "$SHADER_BRIDGE_LIB" ]; then
    args+=(OTHER_LDFLAGS="-Wl,-u,_librashader_translate_preset -Wl,-u,_librashader_free_string \"$SHADER_BRIDGE_LIB\" -lc++")
    if [ -n "$SHADER_BRIDGE_ARCHS" ]; then
      args+=(ARCHS="$SHADER_BRIDGE_ARCHS")
    fi
  fi

  if ! $DEVICE; then
    # Simulator: ad-hoc signing (no certificate needed). A plain unsigned
    # build would drop the entitlements file, and HealthKit refuses to run
    # without the com.apple.developer.healthkit entitlement even in the
    # simulator.
    args+=(CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-)
  else
    warn "device build: configure signing in Xcode or set DEVELOPMENT_TEAM / CODE_SIGN_IDENTITY"
    if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
      args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
             CODE_SIGN_STYLE=Automatic
             -allowProvisioningUpdates)
    fi
    if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
      args+=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY")
    fi
    if [ "${GEN1_DISABLE_HEALTHKIT:-0}" = "1" ]; then
      args+=(CODE_SIGN_ENTITLEMENTS=)
    fi
  fi

  if ! xcodebuild -showsdks 2>/dev/null | grep -q "$sdk"; then
    fail "Xcode SDK '$sdk' is not installed (xcodebuild -showsdks).
  Open Xcode → Settings → Platforms (or Components) and install iOS.
  Simulator builds need the iOS Simulator platform; device builds need iOS."
  fi

  say "xcodebuild love-ios ($config / $sdk)"
  set +e
  local xc_status
  if command -v xcbeautify >/dev/null 2>&1; then
    (
      cd "$XCODE_DIR"
      xcodebuild "${args[@]}"
    ) 2>&1 | xcbeautify
    local pipeline_status=("${PIPESTATUS[@]}")
    local xcode_status=${pipeline_status[0]}
    local beautify_status=${pipeline_status[1]}
    if [ "$xcode_status" -ne 0 ]; then
      xc_status=$xcode_status
    else
      xc_status=$beautify_status
    fi
  else
    (
      cd "$XCODE_DIR"
      xcodebuild "${args[@]}"
    )
    xc_status=$?
  fi
  set -e
  if [ "$xc_status" -ne 0 ]; then
    fail "xcodebuild failed (exit $xc_status).
  Common causes:
    - iOS platform/SDK not installed in Xcode (Settings → Platforms)
    - device build without DEVELOPMENT_TEAM / provisioning (see mobile/ios/README.md)
    - Xcode too new for LÖVE $LOVE_VERSION sources (try an older Xcode)
  Packaging still succeeded: $LOVE_FILE"
  fi

  local products="$BUILD_DIR/Build/Products/${config}-${sdk}"
  local app=""
  local candidate newest=0 mtime
  for candidate in "$products/$PRODUCT_NAME.app" "$products/$APP_NAME.app" "$products/love.app"; do
    if [ -d "$candidate" ]; then
      mtime="$(stat -f %m "$candidate" 2>/dev/null || echo 0)"
      if [ "$mtime" -gt "$newest" ]; then
        newest="$mtime"
        app="$candidate"
      fi
    fi
  done
  if [ -z "$app" ]; then
    warn "xcodebuild finished but no .app under $products"
    find "$BUILD_DIR/Build/Products" -name '*.app' 2>/dev/null | head -20 || true
    return 0
  fi
  if [ "$app" != "$products/$APP_NAME.app" ]; then
    rm -rf "$products/$APP_NAME.app"
    mv "$app" "$products/$APP_NAME.app"
    app="$products/$APP_NAME.app"
  fi

  verify_documents_configuration "$app"

  # Fuse even if the pbxproj wire-up failed,  LÖVE runs any bundled *.love.
  # Byte-compare, never just existence: xcodebuild's incremental Copy Bundle
  # Resources can leave a previous build's game.love in a surviving .app, and
  # an existence check shipped that stale payload in the .ipa (today's Lua
  # fixes present in ios/resources/ but absent from the installed app).
  if ! cmp -s "$LOVE_FILE" "$app/game.love"; then
    say "fusing game.love into $(basename "$app")"
    cp "$LOVE_FILE" "$app/game.love"
  fi

  verify_game_payload "$app"
  verify_native_bridge "$app"
  verify_shader_bridge "$app"

  local dist_dir="$DIST/${config}-${sdk}"
  rm -rf "$dist_dir"
  mkdir -p "$dist_dir"
  cp -R "$app" "$dist_dir/$APP_NAME.app"
  say "copied to $dist_dir/$APP_NAME.app"

  if $DEVICE; then
    package_ipa "$dist_dir/$APP_NAME.app"
  fi

  say "iOS app: $app"
  say "bundle id: $BUNDLE_ID  display: $DISPLAY_NAME"
  if $DEVICE; then
    if $INSTALL; then
      install_to_device "$app"
    else
      say "install with: scripts/build_ios.sh --device --install (iPhone plugged in + unlocked)"
    fi
  else
    say "simulator tip: xcrun simctl install booted \"$app\""
  fi
}

# Pack Payload/<app>.app into dist/ios/gen1recomp++.ipa for release / sideload tools.
package_ipa() {
  local app="$1"
  local ipa="$DIST/$APP_NAME.ipa"
  local tmp
  tmp="$(mktemp -d "$DIST/ipa.XXXXXX")"
  mkdir -p "$tmp/Payload"
  cp -R "$app" "$tmp/Payload/$(basename "$app")"
  rm -f "$ipa"
  (cd "$tmp" && zip -q -r "$ipa" Payload)
  rm -rf "$tmp"
  say "ipa: $ipa ($(du -h "$ipa" | cut -f1))"
}

# ------------------------------------------------------------ device install
# Installs the freshly built .app onto the first connected iPhone/iPad via
# devicectl. The phone must be paired (plugged in at least once + "Trust
# This Computer") and UNLOCKED during the install.
install_to_device() {
  local app="$1"
  local line udid
  line="$(xcrun devicectl list devices 2>/dev/null \
    | grep -E 'iPhone|iPad' | grep -v 'Watch' | head -1 || true)"
  udid="$(printf '%s' "$line" \
    | grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
    | head -1 || true)"
  if [ -z "$udid" ]; then
    fail "no iPhone/iPad found.
  Plug the phone in with a cable, unlock it, tap 'Trust This Computer'
  if asked, then re-run: scripts/build_ios.sh --device --install"
  fi
  say "installing onto: $(printf '%s' "$line" | sed 's/  .*//') ($udid)"
  if xcrun devicectl device install app --device "$udid" "$app"; then
    say "installed. On the phone: tap the new app on your Home Screen."
    say "first launch may ask you to enable Developer Mode (Settings ->"
    say "Privacy & Security -> Developer Mode) and to trust the developer"
    say "(Settings -> General -> VPN & Device Management)."
  else
    fail "install failed. Most common cause: the phone was locked.
  Unlock it, keep it plugged in, and re-run:
  scripts/build_ios.sh --device --install"
  fi
}

# --------------------------------------------------------------- main
apply_ios_branding
verify_documents_overlay
apply_ios_icon
say "applying iOS native bridge patches (picker/Files support)"
python3 "$IOS_DIR/patch_love_src.py" || fail "patch_love_src.py failed"
ensure_manifests
pack_game_love
ensure_game_love_in_xcode
suppress_love_dependency_warnings

if $PACKAGE_ONLY; then
  say "package-only: skipping xcodebuild (game.love + plist ready under mobile/ios/love-src/)"
  exit 0
fi

run_xcodebuild
say "done"
