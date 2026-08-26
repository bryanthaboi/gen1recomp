#!/usr/bin/env bash
# Packages the LÖVE2D Pokémon Red port into an Android APK via love-android 11.5a.
#
# Usage: scripts/build_android.sh [--version X.Y.Z] [--release] [--package-only]
#                                 [--test-application-id ID]
#
#   --version X.Y.Z          set app.version_name / app.version_code (else left as-is)
#   --release                build the production-signed release APK (requires the
#                            GEN1RECOMP_ANDROID_* signing environment variables)
#   --package-only           zip game.love + apply branding; skip gradle
#   --test-application-id ID install under a distinct application id (e.g.
#                             com.theboisclub.pokemonred.shaderfxtest) so a
#                             test build installs side by side with a real
#                             played copy instead of overwriting it. App name
#                             gets a " (test)" suffix so it's distinguishable
#                             in the launcher too. Without this flag,
#                             apply_android_branding always writes back the
#                             real shipping identity, which previously had to
#                             be restored by hand in gradle.properties after
#                             every test build.
#
# Prerequisites:
#   - mobile/android vendored love-android tree at tag 11.5a (in-repo; see mobile/ANDROID.md)
#   - Android SDK + NDK (SDK API 36, NDK 25.2.9519653)
#   - JDK 17
#
# Output (after gradle):
#   dist/android/debug/*.apk (normal local build) or dist/android/release/*.apk

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/mobile/android"
EMBED_ASSETS="$ANDROID_DIR/app/src/embed/assets"
LOVE_FILE="$EMBED_ASSETS/game.love"
DIST="$ROOT/dist/android"
APP_NAME="gen1recomp"
APPLICATION_ID="com.theboisclub.pokemonred"
LOVE_ANDROID_VERSION="11.5a"
NDK_VERSION="25.2.9519653"
ANDROID_API="36"
YELLOW_MANIFEST_RELATIVE="tools/rom_manifest_yellow.json"
YELLOW_MANIFEST_URL="${YELLOW_MANIFEST_URL:-https://raw.githubusercontent.com/bryanthaboi/gen1recomp/main/tools/rom_manifest_yellow.json}"
GOLD_MANIFEST_RELATIVE="tools/rom_manifest_gold.json"
GOLD_MANIFEST_URL="${GOLD_MANIFEST_URL:-https://raw.githubusercontent.com/bryanthaboi/gen1recomp/main/tools/rom_manifest_gold.json}"
SILVER_MANIFEST_RELATIVE="tools/rom_manifest_silver.json"
SILVER_MANIFEST_URL="${SILVER_MANIFEST_URL:-https://raw.githubusercontent.com/bryanthaboi/gen1recomp/main/tools/rom_manifest_silver.json}"
CRYSTAL_MANIFEST_RELATIVE="tools/rom_manifest_crystal.json"
CRYSTAL_MANIFEST_URL="${CRYSTAL_MANIFEST_URL:-https://raw.githubusercontent.com/bryanthaboi/gen1recomp/main/tools/rom_manifest_crystal.json}"

VERSION=""
PACKAGE_ONLY=false
RELEASE=false
TEST_APPLICATION_ID=""

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --package-only) PACKAGE_ONLY=true ;;
    --release) RELEASE=true ;;
    --test-application-id) TEST_APPLICATION_ID="$2"; shift ;;
    -h|--help)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    *) fail "unknown argument: $1 (try --version X.Y.Z, --release, --package-only, or --test-application-id ID)" ;;
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
  # Reserve three digits for each lower component. This stays monotonic across
  # 1.0.100 -> 1.1.0, unlike the old two-digit encoding, and remains inside
  # Android's signed 32-bit versionCode range for normal release versions.
  if [ "$minor" -gt 999 ] || [ "$patch" -gt 999 ] || [ "$major" -gt 2099 ]; then
    fail "--version components exceed Android versionCode limits"
  fi
  VERSION_CODE=$((major * 1000000 + minor * 1000 + patch))
fi

if $RELEASE; then
  for var in GEN1RECOMP_ANDROID_KEYSTORE GEN1RECOMP_ANDROID_KEYSTORE_PASSWORD \
    GEN1RECOMP_ANDROID_KEY_ALIAS GEN1RECOMP_ANDROID_KEY_PASSWORD; do
    [ -n "${!var:-}" ] || fail "--release requires $var"
  done
  [ -f "$GEN1RECOMP_ANDROID_KEYSTORE" ] \
    || fail "Android signing keystore does not exist: $GEN1RECOMP_ANDROID_KEYSTORE"
fi

if [ -n "$TEST_APPLICATION_ID" ]; then
  if ! printf '%s' "$TEST_APPLICATION_ID" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$'; then
    fail "invalid --test-application-id '$TEST_APPLICATION_ID' (expected a dotted package id, e.g. com.theboisclub.pokemonred.shaderfxtest)"
  fi
  APPLICATION_ID="$TEST_APPLICATION_ID"
  APP_NAME="$APP_NAME (test)"
fi

# --------------------------------------------------------------- preconditions
if [ ! -f "$ANDROID_DIR/settings.gradle" ] || [ ! -f "$ANDROID_DIR/gradlew" ]; then
  fail "love-android not found at mobile/android/.
  The love-android $LOVE_ANDROID_VERSION tree is vendored in this repo,  your checkout
  looks incomplete. Re-clone or 'git checkout -- mobile/android'. See mobile/ANDROID.md."
fi

if [ ! -d "$ANDROID_DIR/love/src/jni/love/src" ]; then
  fail "liblove sources missing under mobile/android/love/src/jni/love/.
  They are vendored in this repo,  your checkout looks incomplete.
  Re-clone or 'git checkout -- mobile/android'. See mobile/ANDROID.md."
fi

# ------------------------------------------------------- Yellow import metadata
# Android packages game.love itself rather than reusing scripts/build.sh's
# archive.  Keep a partial source export from silently shipping an APK that can
# list Yellow but cannot import it.  Prefer the exact manifest from this
# checkout's Git object database; only then fall back to the public repository.
yellow_manifest_is_valid() {
  local path="$1"
  python3 - "$path" <<'PY'
import json, pathlib, sys

try:
    manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, ValueError):
    raise SystemExit(1)

raise SystemExit(0 if manifest.get("romSha1") ==
                 "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1" else 1)
PY
}

ensure_yellow_manifest() {
  local manifest="$ROOT/$YELLOW_MANIFEST_RELATIVE"
  local staged
  staged="$(mktemp)"

  if yellow_manifest_is_valid "$manifest"; then
    rm -f "$staged"
    return
  fi

  warn "Yellow import manifest is missing or invalid; recovering it before packaging"
  if git -C "$ROOT" show "HEAD:$YELLOW_MANIFEST_RELATIVE" > "$staged" 2>/dev/null \
      && yellow_manifest_is_valid "$staged"; then
    mkdir -p "$(dirname "$manifest")"
    mv "$staged" "$manifest"
    say "restored Yellow import manifest from this checkout's Git data"
    return
  fi

  if command -v curl >/dev/null 2>&1 \
      && curl --fail --location --retry 2 --connect-timeout 15 \
          --output "$staged" "$YELLOW_MANIFEST_URL" \
      && yellow_manifest_is_valid "$staged"; then
    mkdir -p "$(dirname "$manifest")"
    mv "$staged" "$manifest"
    say "downloaded Yellow import manifest from the project repository"
    return
  fi

  rm -f "$staged"
  fail "Yellow import manifest is unavailable. Git recovery failed and could not download $YELLOW_MANIFEST_URL"
}

gold_manifest_is_valid() {
  local path="$1"
  python3 - "$path" <<'PY'
import json, pathlib, sys

try:
    manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, ValueError):
    raise SystemExit(1)

raise SystemExit(0 if manifest.get("romSha1") ==
                 "d8b8a3600a465308c9953dfa04f0081c05bdcb94" else 1)
PY
}

ensure_gold_manifest() {
  local manifest="$ROOT/$GOLD_MANIFEST_RELATIVE"
  local staged
  staged="$(mktemp)"

  if gold_manifest_is_valid "$manifest"; then
    rm -f "$staged"
    return
  fi

  warn "Gold import manifest is missing or invalid; recovering it before packaging"
  if git -C "$ROOT" show "HEAD:$GOLD_MANIFEST_RELATIVE" > "$staged" 2>/dev/null \
      && gold_manifest_is_valid "$staged"; then
    mkdir -p "$(dirname "$manifest")"
    mv "$staged" "$manifest"
    say "restored Gold import manifest from this checkout's Git data"
    return
  fi

  if command -v curl >/dev/null 2>&1 \
      && curl --fail --location --retry 2 --connect-timeout 15 \
          --output "$staged" "$GOLD_MANIFEST_URL" \
      && gold_manifest_is_valid "$staged"; then
    mkdir -p "$(dirname "$manifest")"
    mv "$staged" "$manifest"
    say "downloaded Gold import manifest from the project repository"
    return
  fi

  rm -f "$staged"
  fail "Gold import manifest is unavailable. Git recovery failed and could not download $GOLD_MANIFEST_URL"
}

silver_manifest_is_valid() {
  local path="$1"
  python3 - "$path" <<'PY'
import json, pathlib, sys

try:
    manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, ValueError):
    raise SystemExit(1)

raise SystemExit(0 if manifest.get("romSha1") ==
                 "49b163f7e57702bc939d642a18f591de55d92dae" else 1)
PY
}

ensure_silver_manifest() {
  local manifest="$ROOT/$SILVER_MANIFEST_RELATIVE"
  local staged
  staged="$(mktemp)"

  if silver_manifest_is_valid "$manifest"; then
    rm -f "$staged"
    return
  fi

  warn "Silver import manifest is missing or invalid; recovering it before packaging"
  if git -C "$ROOT" show "HEAD:$SILVER_MANIFEST_RELATIVE" > "$staged" 2>/dev/null \
      && silver_manifest_is_valid "$staged"; then
    mkdir -p "$(dirname "$manifest")"
    mv "$staged" "$manifest"
    say "restored Silver import manifest from this checkout's Git data"
    return
  fi

  if command -v curl >/dev/null 2>&1 \
      && curl --fail --location --retry 2 --connect-timeout 15 \
          --output "$staged" "$SILVER_MANIFEST_URL" \
      && silver_manifest_is_valid "$staged"; then
    mkdir -p "$(dirname "$manifest")"
    mv "$staged" "$manifest"
    say "downloaded Silver import manifest from the project repository"
    return
  fi

  rm -f "$staged"
  fail "Silver import manifest is unavailable. Git recovery failed and could not download $SILVER_MANIFEST_URL"
}

crystal_manifest_is_valid() {
  local path="$1"
  python3 - "$path" <<'PY'
import json, pathlib, sys

try:
    manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
except (OSError, ValueError):
    raise SystemExit(1)

raise SystemExit(0 if manifest.get("romSha1") ==
                 "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133" else 1)
PY
}

ensure_crystal_manifest() {
  local manifest="$ROOT/$CRYSTAL_MANIFEST_RELATIVE"
  local staged
  staged="$(mktemp)"

  if crystal_manifest_is_valid "$manifest"; then
    rm -f "$staged"
    return
  fi

  warn "Crystal import manifest is missing or invalid; recovering it before packaging"
  if git -C "$ROOT" show "HEAD:$CRYSTAL_MANIFEST_RELATIVE" > "$staged" 2>/dev/null \
      && crystal_manifest_is_valid "$staged"; then
    mkdir -p "$(dirname "$manifest")"
    mv "$staged" "$manifest"
    say "restored Crystal import manifest from this checkout's Git data"
    return
  fi

  if command -v curl >/dev/null 2>&1 \
      && curl --fail --location --retry 2 --connect-timeout 15 \
          --output "$staged" "$CRYSTAL_MANIFEST_URL" \
      && crystal_manifest_is_valid "$staged"; then
    mkdir -p "$(dirname "$manifest")"
    mv "$staged" "$manifest"
    say "downloaded Crystal import manifest from the project repository"
    return
  fi

  rm -f "$staged"
  fail "Crystal import manifest is unavailable. Git recovery failed and could not download $CRYSTAL_MANIFEST_URL"
}

# --------------------------------------------------------------- branding
# love-android 11.5+ reads app id / name / orientation from gradle.properties.
# Manifest still gets permission trims. Re-applied every build so refreshing
# the vendored love-android tree does not lose project settings.
apply_android_branding() {
  local props="$ANDROID_DIR/gradle.properties"
  local manifest="$ANDROID_DIR/app/src/main/AndroidManifest.xml"
  [ -f "$props" ] || fail "missing $props"
  [ -f "$manifest" ] || fail "missing $manifest"

  say "applying Android branding (gradle.properties + permission trim)"

  python3 - "$props" "$APPLICATION_ID" "$APP_NAME" "$VERSION" "$VERSION_CODE" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
app_id, name, version, version_code = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
text = path.read_text()

def set_prop(text, key, value):
    pat = re.compile(rf"(?m)^{re.escape(key)}=.*$")
    line = f"{key}={value}"
    if pat.search(text):
        return pat.sub(line, text)
    return text.rstrip() + "\n" + line + "\n"

# Prefer plain app.name; clear byte-array form so it cannot win.
text = re.sub(r"(?m)^app\.name_byte_array=.*\n?", "", text)
text = set_prop(text, "app.name", name)
text = set_prop(text, "app.application_id", app_id)
text = set_prop(text, "app.orientation", "fullUser")
if version:
    text = set_prop(text, "app.version_name", version)
    text = set_prop(text, "app.version_code", version_code)
path.write_text(text)
PY

  python3 - "$manifest" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()

# Drop mic / legacy storage, not needed by this game.
# Keep VIBRATE (love.system.vibrate), BLUETOOTH (optional gamepads) and
# INTERNET: link play is not offline-only any more, and stripping INTERNET
# made every LAN host and every relay connect fail with EPERM (issue #287).
# Orientation / label come from gradle.properties placeholders.
for perm in (
    "android.permission.RECORD_AUDIO",
    "android.permission.WRITE_EXTERNAL_STORAGE",
):
    text = re.sub(
        rf'\s*<uses-permission android:name="{re.escape(perm)}"[^/]*/>\s*',
        "\n",
        text,
    )
text = re.sub(r'\s*android:usesCleartextTraffic="true"', "", text)
path.write_text(text)
PY
}

# --------------------------------------------------------------- game.love
pack_game_love() {
  say "packing game.love for love-android embed flavor"
  ensure_yellow_manifest
  ensure_gold_manifest
  ensure_silver_manifest
  ensure_crystal_manifest
  mkdir -p "$EMBED_ASSETS"
  rm -f "$LOVE_FILE"
  # tools/save-editor ships with the app: the launcher's Edit button on a save
  # row opens it in-process, so it must be inside the archive (see build.sh).
  # Deliberately NO fused mods: a mod inside game.love sits in the read-only
  # APK, so the mod manager's Delete can't remove it and it reappears every
  # launch.  Pokewalker ships as an importable .zip instead, which gives it
  # a real install/upgrade/delete lifecycle.
  # The launcher UI kit lives at src/ui/kit (inside src/, packed wholesale);
  # the vendored libs/flexlove tree it replaced is gone.
  (cd "$ROOT" && zip -q -9 -r "$LOVE_FILE" \
    main.lua conf.lua src data assets tools/save-editor \
    tools/rom_manifest.json tools/rom_manifest_blue.json \
    tools/rom_manifest_yellow.json tools/rom_manifest_gold.json \
    tools/rom_manifest_silver.json tools/rom_manifest_crystal.json \
    -x '*.DS_Store' -x '*/.git/*' -x '*/.DS_Store' \
    -x 'data/generated/*' -x 'assets/generated/*')
  # List once and match against the captured text: piping unzip straight into
  # grep under `set -o pipefail` SIGPIPEs unzip as soon as grep exits early,
  # and the pipeline's 141 outranks grep's own status.  For the generated-data
  # guard that inverted the test -- an archive that really did carry generated
  # ROM data made grep match, killed unzip, and the `if` read the 141 as "no
  # match" and let the build through (#774).  Same listing feeds the
  # required-file gates below, as in scripts/build.sh and scripts/pack_love.sh.
  local archive_entries
  archive_entries="$(unzip -Z1 "$LOVE_FILE")"
  if grep -Eq '^(data|assets)/generated/[^/]+|^(data|assets)/generated/.+/' \
      <<< "$archive_entries"; then
    fail "game.love unexpectedly contains generated ROM data"
  fi
  grep -qx 'tools/save-editor/App.lua' <<< "$archive_entries" \
    || fail "game.love is missing the save editor (Edit on a save row would crash)"
  grep -qx "$YELLOW_MANIFEST_RELATIVE" <<< "$archive_entries" \
    || fail "game.love is missing the Yellow ROM import manifest"
  grep -qx 'tools/rom_manifest_gold.json' <<< "$archive_entries" \
    || fail "game.love is missing the Gold ROM import manifest"
  grep -qx 'tools/rom_manifest_silver.json' <<< "$archive_entries" \
    || fail "game.love is missing the Silver ROM import manifest"
  grep -qx 'tools/rom_manifest_crystal.json' <<< "$archive_entries" \
    || fail "game.love is missing the Crystal ROM import manifest"
  # This gate exists because the launcher's UI toolkit once lived outside
  # src/ (libs/flexlove) and was added to scripts/build.sh's payload and to
  # no other packager, so Android and iOS built an APK/IPA whose launcher
  # threw before drawing anything.  The kit now lives inside src/, but the
  # gate stays: source runs read the working tree, so only a build can catch
  # a packaging miss.
  grep -qx 'src/ui/kit/Kit.lua' <<< "$archive_entries" \
    || fail "game.love is missing the launcher UI kit (launcher dies on frame 1)"
  say "game.love: $(du -h "$LOVE_FILE" | cut -f1) -> $LOVE_FILE"

  # This script packs its own game.love (it does not reuse build.sh's), so it
  # stamps the release version the same way: patch a copy of Version.lua
  # (engine set to $VERSION) under a throwaway staging dir and replace the
  # entry inside the archive in place -- never the source tree. VERSION is
  # already validated as X.Y.Z above; when it is empty the packaged game keeps
  # the "0.0.0-dev" default. The stamp is read back out and the build fails if
  # it did not take.
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

# --------------------------------------------------------------- ShaderFX bridge
SHADER_BRIDGE_LIB="liblibrashader_bridge.so"
SHADER_BRIDGE_ABIS="arm64-v8a armeabi-v7a"

shader_bridge_rust_target() {
  case "$1" in
    arm64-v8a)   printf 'aarch64-linux-android' ;;
    armeabi-v7a) printf 'armv7-linux-androideabi' ;;
    x86_64)      printf 'x86_64-linux-android' ;;
    x86)         printf 'i686-linux-android' ;;
    *)           printf '' ;;
  esac
}

shader_bridge_staged_count() {
  local jni="$1" abi count=0
  for abi in $SHADER_BRIDGE_ABIS; do
    [ -f "$jni/$abi/$SHADER_BRIDGE_LIB" ] && count=$((count + 1))
  done
  printf '%s' "$count"
}

bundle_shader_bridge_android() {
  local jni="$ANDROID_DIR/app/src/main/jniLibs"
  local crate="$ROOT/tools/shaderfx-bridge"
  local abi target

  for abi in $SHADER_BRIDGE_ABIS; do
    rm -f "$jni/$abi/$SHADER_BRIDGE_LIB"
  done

  local prebuilt="${SHADERFX_BRIDGE_ANDROID_DIR:-}"
  if [ -n "$prebuilt" ]; then
    for abi in $SHADER_BRIDGE_ABIS; do
      if [ -f "$prebuilt/$abi/$SHADER_BRIDGE_LIB" ]; then
        mkdir -p "$jni/$abi"
        cp "$prebuilt/$abi/$SHADER_BRIDGE_LIB" "$jni/$abi/$SHADER_BRIDGE_LIB"
      else
        warn "SHADERFX_BRIDGE_ANDROID_DIR has no $abi/$SHADER_BRIDGE_LIB"
      fi
    done
    if [ "$(shader_bridge_staged_count "$jni")" -gt 0 ]; then
      say "bundled $SHADER_BRIDGE_LIB for SHADER FX preset conversion (prebuilt)"
      return
    fi
  fi

  if [ ! -f "$crate/Cargo.toml" ]; then
    warn "$SHADER_BRIDGE_LIB not found: this build can run converted presets but not CONVERT new ones (tools/shaderfx-bridge is missing)"
    return
  fi

  if ! command -v cargo >/dev/null 2>&1 || ! cargo ndk --version >/dev/null 2>&1; then
    warn "$SHADER_BRIDGE_LIB not found: this build can run converted presets but not CONVERT new ones (set SHADERFX_BRIDGE_ANDROID_DIR or run 'cargo install cargo-ndk')"
    return
  fi

  local ndk="${ANDROID_NDK_HOME:-}"
  if [ -z "$ndk" ] || [ ! -d "$ndk" ]; then
    ndk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}/ndk/$NDK_VERSION"
  fi
  if [ ! -d "$ndk" ]; then
    warn "$SHADER_BRIDGE_LIB not built: NDK $NDK_VERSION not found (set ANDROID_NDK_HOME)"
    return
  fi

  local installed missing="" buildable=""
  installed="$(rustup target list --installed 2>/dev/null || true)"
  for abi in $SHADER_BRIDGE_ABIS; do
    target="$(shader_bridge_rust_target "$abi")"
    if grep -qx "$target" <<< "$installed"; then
      buildable="$buildable $abi"
    else
      missing="$missing $target"
    fi
  done
  if [ -n "$missing" ]; then
    warn "$SHADER_BRIDGE_LIB: skipping$missing. Run: rustup target add$missing"
  fi
  if [ -z "$buildable" ]; then
    warn "$SHADER_BRIDGE_LIB not built: this build can run converted presets but not CONVERT new ones (no Android Rust targets installed)"
    return
  fi

  local args=()
  for abi in $buildable; do
    args+=(-t "$abi")
  done

  say "building the ShaderFX bridge with cargo-ndk (${buildable# })"
  mkdir -p "$jni"
  if ! (
    cd "$crate"
    export ANDROID_NDK_HOME="$ndk"
    export ANDROID_NDK_ROOT="$ndk"
    export CARGO_PROFILE_RELEASE_STRIP="symbols"
    cargo ndk "${args[@]}" -o "$jni" build --release
  ); then
    warn "$SHADER_BRIDGE_LIB failed to cross-compile: this build can run converted presets but not CONVERT new ones"
    return
  fi

  if [ "$(shader_bridge_staged_count "$jni")" -gt 0 ]; then
    say "bundled $SHADER_BRIDGE_LIB for SHADER FX preset conversion"
  else
    warn "$SHADER_BRIDGE_LIB not found after cargo-ndk: this build can run converted presets but not CONVERT new ones"
  fi
}

# --------------------------------------------------------------- SDK check
require_android_sdk() {
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [ -z "$sdk" ]; then
    for candidate in \
      "$HOME/Library/Android/sdk" \
      "$HOME/Android/Sdk" \
      /usr/local/lib/android/sdk; do
      if [ -d "$candidate" ]; then
        sdk="$candidate"
        break
      fi
    done
  fi

  if [ -z "$sdk" ] || [ ! -d "$sdk" ]; then
    fail "Android SDK not found.
  Install Android Studio (or command-line tools), then either:
    export ANDROID_SDK_ROOT=\$HOME/Library/Android/sdk
  or create mobile/android/local.properties with:
    sdk.dir=/path/to/Android/sdk
  love-android $LOVE_ANDROID_VERSION expects SDK API $ANDROID_API and NDK $NDK_VERSION
  (see mobile/ANDROID.md)."
  fi

  export ANDROID_SDK_ROOT="$sdk"
  export ANDROID_HOME="$sdk"

  if [ ! -d "$sdk/platforms/android-$ANDROID_API" ]; then
    fail "Android SDK platform android-$ANDROID_API is not installed.
  Install Android $ANDROID_API (and the latest 36.x Build-Tools) in SDK Manager."
  fi

  local props="$ANDROID_DIR/local.properties"
  # Always rewrite so a leftover Docker sdk.dir=/opt/android-sdk cannot stick.
  printf 'sdk.dir=%s\n' "$sdk" > "$props"

  if ! command -v java >/dev/null 2>&1; then
    fail "java not found. Install JDK 17 (Android Studio's bundled JDK is fine)."
  fi

  if [ ! -d "$sdk/ndk/$NDK_VERSION" ]; then
    warn "NDK $NDK_VERSION not found under $sdk/ndk/"
    warn "Install via SDK Manager (Show Package Details → NDK $NDK_VERSION)."
  fi
}

# --------------------------------------------------------------- gradle
run_gradle() {
  local variant="debug"
  $RELEASE && variant="release"
  # Keep this compatible with macOS's bundled Bash 3.2 (no ${var^}).
  local variant_title="Debug"
  $RELEASE && variant_title="Release"
  local task="assembleEmbedNoRecord$variant_title"
  local build_dir="$ANDROID_DIR"

  # ndk-build is GNU make underneath and cannot cope with spaces anywhere in
  # the project path ("Your APP_BUILD_SCRIPT points to an unknown file").
  # When this checkout lives at a spaced path (e.g. "~/xCode Projects/..."),
  # shadow the android tree to a space-free location and build there; the
  # shadow persists across runs so gradle/ndk builds stay incremental.
  case "$ANDROID_DIR" in
    *" "*)
      build_dir="${TMPDIR:-/tmp}/gen1recomp-android-shadow"
      say "path contains spaces (ndk-build cannot handle them);"
      say "shadow-building in: $build_dir"
      mkdir -p "$build_dir"
      rsync -a --delete \
        --exclude=".gradle" --exclude="app/build" --exclude="love/build" \
        --exclude="local.properties" \
        "$ANDROID_DIR/" "$build_dir/"
      if [ -f "$ANDROID_DIR/local.properties" ]; then
        cp "$ANDROID_DIR/local.properties" "$build_dir/local.properties"
      fi
      ;;
  esac

  say "building APK ($task)"
  if ! (
    cd "$build_dir"
    ./gradlew --no-daemon "$task"
  ); then
    fail "gradle $task failed.
  Packaging already wrote: $LOVE_FILE
  Common causes: missing SDK/NDK $NDK_VERSION, or JDK ≠ 17. See mobile/ANDROID.md.
  You can still iterate on the .love payload with: scripts/build_android.sh --package-only"
  fi

  local out_dir="$build_dir/app/build/outputs/apk/embedNoRecord/$variant"
  if [ -d "$out_dir" ]; then
    say "APK output:"
    find "$out_dir" -name '*.apk' -exec ls -lh {} \;

    local dist_dir="$DIST/$variant"
    rm -rf "$dist_dir"
    mkdir -p "$dist_dir"
    find "$out_dir" -name '*.apk' -exec cp {} "$dist_dir/" \;
    say "copied to $dist_dir/"
  else
    warn "gradle finished but no APK dir at $out_dir,  check gradle logs above"
  fi
}

# --------------------------------------------------------------- main
apply_android_branding
pack_game_love

if $PACKAGE_ONLY; then
  say "package-only: skipping gradle (game.love + branding ready under mobile/android/)"
  exit 0
fi

require_android_sdk
bundle_shader_bridge_android
run_gradle
say "done"
