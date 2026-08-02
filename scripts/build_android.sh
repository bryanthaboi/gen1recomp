#!/usr/bin/env bash
# Packages the LÖVE2D Pokémon Red port into an Android APK via love-android 11.5a.
#
# Usage: scripts/build_android.sh [--version X.Y.Z] [--package-only]
#
#   --version X.Y.Z  set app.version_name / app.version_code (else left as-is)
#   --package-only   zip game.love + apply branding; skip gradle
#
# Prerequisites:
#   - mobile/android vendored love-android tree at tag 11.5a (in-repo; see mobile/ANDROID.md)
#   - Android SDK + NDK (SDK API 34, NDK 25.2.9519653)
#   - JDK 17
#
# Output (after gradle):
#   dist/android/debug/*.apk (convenience copy)
#   mobile/android/app/build/outputs/apk/embedNoRecord/debug/*.apk

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
YELLOW_MANIFEST_RELATIVE="tools/rom_manifest_yellow.json"
# A fresh source checkout normally supplies this through Git.  This URL is
# deliberately only a last resort for incomplete source exports: the manifest
# contains extraction metadata, never a ROM or extracted game data.
YELLOW_MANIFEST_URL="${YELLOW_MANIFEST_URL:-https://raw.githubusercontent.com/bryanthaboi/gen1recomp/main/tools/rom_manifest_yellow.json}"

VERSION=""
PACKAGE_ONLY=false

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --package-only) PACKAGE_ONLY=true ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) fail "unknown argument: $1 (try --version X.Y.Z or --package-only)" ;;
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
  mkdir -p "$EMBED_ASSETS"
  rm -f "$LOVE_FILE"
  # tools/save-editor ships with the app: the launcher's Edit button on a save
  # row opens it in-process, so it must be inside the archive (see build.sh).
  # Deliberately NO fused mods: a mod inside game.love sits in the read-only
  # APK, so the mod manager's Delete can't remove it and it reappears every
  # launch.  Pokewalker ships as an importable .zip instead, which gives it
  # a real install/upgrade/delete lifecycle.
  (cd "$ROOT" && zip -q -9 -r "$LOVE_FILE" \
    main.lua conf.lua src data assets tools/save-editor \
    tools/rom_manifest.json tools/rom_manifest_blue.json \
    tools/rom_manifest_yellow.json \
    tools/rom_manifest_red_es.json tools/rom_manifest_blue_es.json \
    -x '*.DS_Store' -x '*/.git/*' -x '*/.DS_Store' \
    -x 'data/generated/*' -x 'assets/generated/*')
  if unzip -Z1 "$LOVE_FILE" \
      | grep -Eq '^(data|assets)/generated/[^/]+|^(data|assets)/generated/.+/'; then
    fail "game.love unexpectedly contains generated ROM data"
  fi
  # Do not pipe unzip straight into grep here: on a large archive grep can
  # finish early and make unzip report SIGPIPE under `set -o pipefail`.
  local archive_entries
  archive_entries="$(unzip -Z1 "$LOVE_FILE")"
  grep -qx 'tools/save-editor/App.lua' <<< "$archive_entries" \
    || fail "game.love is missing the save editor (Edit on a save row would crash)"
  grep -qx "$YELLOW_MANIFEST_RELATIVE" <<< "$archive_entries" \
    || fail "game.love is missing the Yellow ROM import manifest"
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
  love-android $LOVE_ANDROID_VERSION expects SDK API 34 and NDK $NDK_VERSION
  (see mobile/ANDROID.md)."
  fi

  export ANDROID_SDK_ROOT="$sdk"
  export ANDROID_HOME="$sdk"

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
  local task="assembleEmbedNoRecordDebug"
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

  local out_dir="$build_dir/app/build/outputs/apk/embedNoRecord/debug"
  if [ -d "$out_dir" ]; then
    say "APK output:"
    find "$out_dir" -name '*.apk' -exec ls -lh {} \;

    local dist_dir="$DIST/debug"
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
run_gradle
say "done"
