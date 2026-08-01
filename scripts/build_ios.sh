#!/usr/bin/env bash
# Packages the LÖVE2D Pokémon Red port into an iOS app via LÖVE 11.5's
# official iOS Xcode project (love-11.5-ios-source.zip).
#
# Usage: scripts/build_ios.sh [--fetch] [--device] [--release] [--install]
#                             [--version X.Y.Z] [--package-only]
#
#   (default)         Simulator Debug (ad-hoc signed)
#   --device          iphoneos SDK; signing team auto-detected from the
#                     keychain when DEVELOPMENT_TEAM is not set
#   --install         after a --device build, list iPhone/iPad devices
#                     (physical first) via xcrun devicectl and install.
#                     Non-interactive: GEN1_IOS_DEVICE='name-or-udid'
#   --release         Release configuration
#   --version X.Y.Z   stamp MARKETING_VERSION / CURRENT_PROJECT_VERSION
#   --fetch           Download love-11.5-ios-source.zip into mobile/ios/love-src/
#   --package-only    Zip game.love + apply plist overlay; skip xcodebuild
#
# Prerequisites:
#   - macOS + Xcode (xcodebuild)
#   - mobile/ios/love-src/ (see --fetch / mobile/ios/README.md)
#   - prebuilt iOS libraries under love-src/platform/xcode/ios/libraries/
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
BUNDLE_ID="${GEN1_BUNDLE_ID:-}"
if [ -z "$BUNDLE_ID" ] && [ -f "$IOS_DIR/bundle_id.local" ]; then
  BUNDLE_ID="$(tr -d '[:space:]' < "$IOS_DIR/bundle_id.local")"
fi
LOVE_VERSION="$(tr -d '[:space:]' < "$IOS_DIR/LOVE_VERSION" 2>/dev/null || echo 11.5)"
IOS_SOURCE_ZIP="love-${LOVE_VERSION}-ios-source.zip"
APPLE_LIBS_ZIP="love-${LOVE_VERSION}-apple-libraries.zip"
IOS_SOURCE_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/${IOS_SOURCE_ZIP}"
APPLE_LIBS_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/${APPLE_LIBS_ZIP}"

FETCH=false
DEVICE=false
RELEASE=false
PACKAGE_ONLY=false
INSTALL=false
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
    --version) VERSION="$2"; shift ;;
    -h|--help)
      sed -n '2,24p' "$0"
      exit 0
      ;;
    *) fail "unknown argument: $1 (try --fetch, --device, --release, --version, --install, or --package-only)" ;;
  esac
  shift
done

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
  local zip_path="$CACHE/$IOS_SOURCE_ZIP"
  if [ ! -f "$zip_path" ]; then
    say "downloading $IOS_SOURCE_ZIP (LÖVE $LOVE_VERSION iOS sources)"
    curl -fL --progress-bar "$IOS_SOURCE_URL" -o "$zip_path" \
      || fail "download failed: $IOS_SOURCE_URL"
  else
    say "using cached $zip_path"
  fi

  say "extracting into $LOVE_SRC"
  rm -rf "$LOVE_SRC"
  local tmp
  tmp="$(mktemp -d "$CACHE/extract.XXXXXX")"
  unzip -q "$zip_path" -d "$tmp"
  # Zip root is love-<version>-ios-source/
  local extracted
  extracted="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d ! -name '__MACOSX' | head -1)"
  [ -n "$extracted" ] || fail "unexpected layout inside $IOS_SOURCE_ZIP"
  mv "$extracted" "$LOVE_SRC"
  rm -rf "$tmp"
  say "love-src ready (LÖVE $LOVE_VERSION)"
}

if [ ! -d "$XCODE_DIR/love.xcodeproj" ]; then
  if $FETCH; then
    fetch_love_ios
  else
    fail "LÖVE $LOVE_VERSION iOS sources not found at mobile/ios/love-src/.
  Fetch them (documented download of love-${LOVE_VERSION}-ios-source.zip):
    scripts/build_ios.sh --fetch
  Or manually:
    mkdir -p mobile/ios/cache
    curl -fL -o mobile/ios/cache/$IOS_SOURCE_ZIP \\
      $IOS_SOURCE_URL
    unzip -q mobile/ios/cache/$IOS_SOURCE_ZIP -d mobile/ios/cache
    mv mobile/ios/cache/love-${LOVE_VERSION}-ios-source mobile/ios/love-src
  See mobile/ios/README.md."
  fi
elif $FETCH; then
  say "love-src already present; skipping download (delete mobile/ios/love-src to refresh)"
fi

[ -d "$XCODE_DIR/love.xcodeproj" ] \
  || fail "missing $PROJECT after fetch"

# --------------------------------------------------------------- apple libraries
require_ios_libraries() {
  if [ -d "$LIBS_DIR/SDL2.xcframework" ]; then
    return 0
  fi
  fail "prebuilt iOS libraries missing at:
  $LIBS_DIR
  love-ios expects SDL2.xcframework (and friends) there.

  The official love-${LOVE_VERSION}-ios-source.zip normally includes them.
  If they are absent, install love-${LOVE_VERSION}-apple-libraries.zip:

    mkdir -p mobile/ios/cache
    curl -fL -o mobile/ios/cache/$APPLE_LIBS_ZIP \\
      $APPLE_LIBS_URL
    unzip -q mobile/ios/cache/$APPLE_LIBS_ZIP -d mobile/ios/cache
    rm -rf mobile/ios/love-src/platform/xcode/ios/libraries
    cp -R mobile/ios/cache/love-apple-dependencies/iOS/libraries \\
      mobile/ios/love-src/platform/xcode/ios/libraries

  See mobile/ios/README.md (Apple libraries dependency)."
}

require_ios_libraries

# --------------------------------------------------------------- branding / plist
apply_ios_branding() {
  [ -f "$OVERLAY_PLIST" ] || fail "missing overlay plist: $OVERLAY_PLIST"
  local dest="$XCODE_DIR/ios/love-ios.plist"
  say "applying iOS branding (portrait + landscape Info.plist, display name)"
  cp "$OVERLAY_PLIST" "$dest"
}

# --------------------------------------------------------------- game.love
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
  (cd "$ROOT" && zip -q -9 -r "$LOVE_FILE" \
    main.lua conf.lua src data assets tools/save-editor \
    tools/rom_manifest.json tools/rom_manifest_blue.json \
    tools/rom_manifest_yellow.json \
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
  for required in tools/save-editor/App.lua tools/save-editor/Kit.lua \
                  tools/save-editor/panels/Party.lua \
                  tools/rom_manifest.json tools/rom_manifest_blue.json \
                  tools/rom_manifest_yellow.json; do
    printf '%s\n' "$archive_entries" | grep -qx "$required" \
      || fail "game.love is missing $required"
  done
  say "game.love: $(du -h "$LOVE_FILE" | cut -f1) -> $LOVE_FILE"
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
  (
    cd "$XCODE_DIR"
    xcodebuild "${args[@]}"
  )
  local xc_status=$?
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
# Lists iPhone/iPad devices via `xcrun devicectl` (ships with Xcode 15+),
# sorted with physical/usable first, then prompts. Simulators stay visible
# but are deprioritized. Pin with GEN1_IOS_DEVICE=name-or-udid.
# Only bash + Xcode CLI — no Homebrew tools. Device must be unlocked.
install_to_device() {
  local app="$1"
  local prefer="${GEN1_IOS_DEVICE:-}"
  local interactive=0
  [ -t 0 ] && [ -t 1 ] && interactive=1

  command -v xcrun >/dev/null 2>&1 \
    || fail "xcrun not found (install Xcode)"
  xcrun --find devicectl >/dev/null 2>&1 \
    || fail "devicectl not found. Need Xcode 15+ (xcrun --find devicectl)."

  # Table columns (widths vary): Name  Hostname  Identifier  State  Model  Reality
  # Parse is best-effort: bad rows are skipped so a format tweak can't abort install.
  local -a names udids states models realities scores usables
  local line name udid state model reality rest score usable is_physical
  local tmp_list
  tmp_list="$(mktemp -t gen1-ios-devices.XXXXXX 2>/dev/null)" \
    || tmp_list="/tmp/gen1-ios-devices.$$"

  if ! xcrun devicectl list devices >"$tmp_list" 2>/dev/null; then
    rm -f "$tmp_list"
    fail "devicectl list devices failed.
  Is Xcode installed and selected? (xcode-select -p)"
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    # Header / separator / blank
    case "$line" in
      ""|Name\ *|-----*) continue ;;
    esac
    # Only phone/tablet rows (Watch etc. ignored)
    printf '%s\n' "$line" | grep -Eq 'iPhone|iPad' || continue

    udid="$(printf '%s\n' "$line" \
      | grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
      | head -1 || true)"
    [ -n "$udid" ] || continue

    name="${line%%"$udid"*}"
    name="$(printf '%s' "$name" | sed -E 's/[[:space:]]+$//' 2>/dev/null || printf '%s' "$name")"
    [ -n "$name" ] || name="?"

    rest="${line#*"$udid"}"
    rest="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+//' 2>/dev/null || printf '%s' "$rest")"

    # Reality from the full row
    reality="unknown"
    case "$line" in
      *physical*) reality="physical" ;;
      *simulated*) reality="simulated" ;;
    esac
    rest="$(printf '%s' "$rest" \
      | sed -E 's/[[:space:]]+(physical|simulated)[[:space:]]*$//' 2>/dev/null \
      || printf '%s' "$rest")"

    # State: first token, or "available (paired)"
    state="unknown"
    if printf '%s' "$rest" | grep -Eq '^available \(paired\)'; then
      state="available (paired)"
      rest="${rest#available (paired)}"
    elif [ -n "$rest" ]; then
      state="${rest%%[[:space:]]*}"
      rest="${rest#"$state"}"
    fi
    rest="$(printf '%s' "$rest" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' 2>/dev/null \
      || printf '%s' "$rest")"
    model="$rest"
    [ -n "$model" ] || model="?"

    is_physical=0
    [ "$reality" = "physical" ] && is_physical=1

    # "Usable" for default auto-pick: physical + not unavailable/unknown.
    # Sims can still be chosen interactively (install may fail for iphoneos builds).
    usable=0
    score=0
    if [ "$is_physical" -eq 1 ]; then
      score=$((score + 1000))
      case "$state" in
        unavailable|unknown|"") ;;
        *) usable=1; score=$((score + 100)) ;;
      esac
    else
      # Booted sim slightly above shutdown sim
      case "$state" in
        boot*|available*|connected*) score=$((score + 20)) ;;
      esac
    fi
    case "$name $model" in
      *[Ii][Pp]hone*) score=$((score + 10)) ;;
    esac
    case "$state" in
      available*|connected*) score=$((score + 5)) ;;
    esac

    names+=("$name")
    udids+=("$udid")
    states+=("$state")
    models+=("$model")
    realities+=("$reality")
    scores+=("$score")
    usables+=("$usable")
  done <"$tmp_list"
  rm -f "$tmp_list"

  local count=${#udids[@]}
  if [ "$count" -eq 0 ]; then
    fail "no iPhone/iPad found via devicectl.
  Plug a phone in (or boot a simulator), unlock it, tap Trust if asked,
  then re-run: scripts/build_ios.sh --device --install"
  fi

  # Sort indices by score descending (insertion sort — bash 3.2 safe)
  local -a order
  local i j key
  i=0
  while [ "$i" -lt "$count" ]; do
    order+=("$i")
    i=$((i + 1))
  done
  i=1
  while [ "$i" -lt "$count" ]; do
    key="${order[$i]}"
    j=$((i - 1))
    while [ "$j" -ge 0 ] && [ "${scores[${order[$j]}]}" -lt "${scores[$key]}" ]; do
      order[$((j + 1))]="${order[$j]}"
      j=$((j - 1))
    done
    order[$((j + 1))]="$key"
    i=$((i + 1))
  done

  local pick=-1
  if [ -n "$prefer" ]; then
    local pref_lc blob
    pref_lc="$(printf '%s' "$prefer" | tr '[:upper:]' '[:lower:]')"
    for i in "${order[@]}"; do
      blob="$(printf '%s %s' "${names[$i]}" "${udids[$i]}" | tr '[:upper:]' '[:lower:]')"
      case "$blob" in
        *"$pref_lc"*) pick=$i; break ;;
      esac
    done
    if [ "$pick" -lt 0 ]; then
      fail "no device matching GEN1_IOS_DEVICE='$prefer'
$(for i in "${order[@]}"; do
  printf '  %s  [%s]  %s\n' "${names[$i]}" "${realities[$i]}" "${udids[$i]}"
done)"
    fi
  else
    # Default = first usable physical in sorted order; else first row
    local default_pos=0
    local idx
    for idx in "${!order[@]}"; do
      i="${order[$idx]}"
      if [ "${usables[$i]}" -eq 1 ]; then
        default_pos=$idx
        break
      fi
    done

    say "connected devices (* = default; physical preferred):"
    local pos=0 mark flag
    for i in "${order[@]}"; do
      pos=$((pos + 1))
      mark=" "
      [ $((pos - 1)) -eq "$default_pos" ] && mark="*"
      flag=""
      if [ "${realities[$i]}" = "simulated" ]; then
        flag="  [simulator — device .app may not install]"
      elif [ "${usables[$i]}" -eq 0 ]; then
        flag="  [may fail]"
      fi
      printf '  %s%d. %s  (%s, %s)  state=%s%s\n' \
        "$mark" "$pos" "${names[$i]}" "${realities[$i]}" "${models[$i]}" \
        "${states[$i]}" "$flag"
    done

    if [ "$interactive" -eq 1 ]; then
      local raw=""
      # Best-effort TTY prompt; fall back to stdin / default on Enter
      if [ -w /dev/tty ] 2>/dev/null; then
        printf 'Install onto which device? [%d]: ' "$((default_pos + 1))" >/dev/tty 2>/dev/null \
          || printf 'Install onto which device? [%d]: ' "$((default_pos + 1))" >&2
        IFS= read -r raw </dev/tty 2>/dev/null || raw=""
      else
        printf 'Install onto which device? [%d]: ' "$((default_pos + 1))" >&2
        IFS= read -r raw || raw=""
      fi
      if [ -z "$raw" ]; then
        pick="${order[$default_pos]}"
      else
        case "$raw" in
          *[!0-9]*)
            warn "invalid choice '$raw' — using default"
            pick="${order[$default_pos]}"
            ;;
          *)
            if [ "$raw" -lt 1 ] || [ "$raw" -gt "$count" ]; then
              warn "choice out of range ($raw) — using default"
              pick="${order[$default_pos]}"
            else
              pick="${order[$((raw - 1))]}"
            fi
            ;;
        esac
      fi
    else
      pick="${order[$default_pos]}"
      if [ "${usables[$pick]}" -eq 0 ]; then
        fail "no usable physical device for non-interactive install.
  Unlock/reconnect a phone, or pin one: GEN1_IOS_DEVICE='iPhone'
  Devices seen:
$(for i in "${order[@]}"; do
  printf '  %s  [%s]  state=%s\n' "${names[$i]}" "${realities[$i]}" "${states[$i]}"
done)"
      fi
      say "auto-selected (non-interactive): ${names[$pick]}"
    fi
  fi

  # Guard against empty pick (shouldn't happen)
  if [ -z "${pick:-}" ] || [ "$pick" -lt 0 ] 2>/dev/null; then
    fail "internal error: no device selected"
  fi

  name="${names[$pick]}"
  udid="${udids[$pick]}"
  [ -n "$udid" ] || fail "selected device has no identifier"

  if [ "${realities[$pick]}" = "simulated" ]; then
    warn "$name is a simulator — this is an iphoneos (device) build; install may fail"
  elif [ "${usables[$pick]}" -eq 0 ]; then
    warn "$name is ${states[$pick]} — install may fail (unlock / reconnect)"
  fi

  say "installing onto: $name ($udid)"
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
say "applying iOS native bridge patches (picker/Files support)"
python3 "$IOS_DIR/patch_love_src.py" || fail "patch_love_src.py failed"
pack_game_love
ensure_game_love_in_xcode

if $PACKAGE_ONLY; then
  say "package-only: skipping xcodebuild (game.love + plist ready under mobile/ios/love-src/)"
  exit 0
fi

run_xcodebuild
say "done"
