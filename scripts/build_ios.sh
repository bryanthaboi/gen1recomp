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
# Output: dist/ios/<Config>-<sdk>/gen1recomp.app (convenience copy)
#         dist/ios/gen1recomp.ipa                 (device builds only)
#         mobile/ios/build/Build/Products/<Config>-<sdk>/gen1recomp.app

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

APP_NAME="gen1recomp"
DISPLAY_NAME="gen1recomp"
# Bundle ID resolution, most specific wins:
#   1. GEN1_BUNDLE_ID env var
#   2. mobile/ios/bundle_id.local (one line, gitignored — pins YOUR install
#      so rebuilds keep updating the same app on your phone)
#   3. device builds: com.gen1recomp.t<your team id> — explicit App IDs are
#      globally unique across ALL Apple accounts (and required once
#      capabilities like HealthKit are involved), so a per-team default
#      lets anyone build without colliding with someone else's app
#   4. simulator: the project default (no App ID registration involved)
BUNDLE_ID="${GEN1_BUNDLE_ID:-com.theboisclub.gen1recomp}"
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
  if $DEVICE; then
    BUNDLE_ID="com.gen1recomp.t$(printf '%s' "$DEVELOPMENT_TEAM" | tr '[:upper:]' '[:lower:]')"
  else
    BUNDLE_ID="com.theboisclub.pokemonred"
  fi
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

apply_ios_icon() {
  local source="$ROOT/assets/logo/logo.png"
  local target="$XCODE_DIR/Images.xcassets/iOS AppIcon.appiconset"
  [ -f "$source" ] || fail "missing iOS icon source: $source"
  [ -d "$target" ] || fail "missing iOS app icon set: $target"
  local entry name size
  while IFS=: read -r name size; do
    sips -z "$size" "$size" "$source" --out "$target/$name" >/dev/null
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
  archive_entries="$(unzip -Z1 "$LOVE_FILE")"
  # shellcheck disable=SC2086  # MANIFESTS is a deliberate word list
  for required in src/update/Boot.lua tools/save-editor/App.lua \
                  tools/save-editor/Kit.lua tools/save-editor/panels/Party.lua \
                  $MANIFESTS; do
    printf '%s\n' "$archive_entries" | grep -qx "$required" \
      || fail "game.love is missing $required"
  done
  say "game.love: $(du -h "$LOVE_FILE" | cut -f1) -> $LOVE_FILE"

  # This script packs its own game.love (it does not reuse build.sh's), so it
  # stamps the release version the same way build.sh and build_android.sh do:
  # patch a copy of Version.lua (engine set to $VERSION) under a throwaway
  # staging dir and replace the entry inside the archive in place -- never the
  # source tree. Stamping the Info.plist alone is not enough: the mod loader
  # reads Version.engine out of game.love (src/mods/Loader.lua game_version
  # gate), so an unstamped archive reports "0.0.0-dev" and every mod with a
  # version floor is rejected on iOS while it loads on desktop (#613).
  # VERSION is already validated as X.Y.Z above; when it is empty the packaged
  # game keeps the "0.0.0-dev" default so a dev build cannot pass for a
  # release. The stamp is read back out and the build fails if it did not take.
  if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    say "stamping engine version $VERSION into game.love"
    local stamp_dir
    stamp_dir="$(mktemp -d)"
    mkdir -p "$stamp_dir/src/core"
    sed -E "s/(engine[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1$VERSION\2/" \
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
    ONLY_ACTIVE_ARCH=NO
  )

  if ! $DEVICE; then
    # Simulator: ad-hoc signing (no certificate needed). A plain unsigned
    # build would drop the entitlements file, and HealthKit refuses to run
    # without the com.apple.developer.healthkit entitlement even in the
    # simulator.
    args+=(CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-)
  else
    warn "device build: configure signing in Xcode or set DEVELOPMENT_TEAM / CODE_SIGN_IDENTITY"
    if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
      # Automatic signing + provisioning updates lets xcodebuild register the
      # bundle ID / create a development profile from the CLI, so a device
      # build works without ever opening the project in Xcode.
      args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
             CODE_SIGN_STYLE=Automatic
             -allowProvisioningUpdates)
    fi
    if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
      args+=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY")
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
  local app="$products/$APP_NAME.app"
  if [ ! -d "$app" ]; then
    # PRODUCT_NAME override can still leave love.app on older projects
    if [ -d "$products/love.app" ]; then
      app="$products/love.app"
      warn "built app is love.app (PRODUCT_NAME override not applied); fusing game.love anyway"
    else
      warn "xcodebuild finished but no .app under $products"
      find "$BUILD_DIR/Build/Products" -name '*.app' 2>/dev/null | head -20 || true
      return 0
    fi
  fi

  # Fuse even if the pbxproj wire-up failed,  LÖVE runs any bundled *.love.
  if [ ! -f "$app/game.love" ]; then
    say "fusing game.love into $(basename "$app")"
    cp "$LOVE_FILE" "$app/game.love"
  fi

  verify_native_bridge "$app"

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

# Pack Payload/<app>.app into dist/ios/gen1recomp.ipa for release / sideload tools.
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
apply_ios_icon
say "applying iOS native bridge patches (picker/Files support)"
python3 "$IOS_DIR/patch_love_src.py" || fail "patch_love_src.py failed"
ensure_manifests
pack_game_love
ensure_game_love_in_xcode

if $PACKAGE_ONLY; then
  say "package-only: skipping xcodebuild (game.love + plist ready under mobile/ios/love-src/)"
  exit 0
fi

run_xcodebuild
say "done"
