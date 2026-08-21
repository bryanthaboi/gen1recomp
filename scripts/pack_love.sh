#!/usr/bin/env bash
# Shared game.love packer for platform builds.
#
# Usage:
#   scripts/pack_love.sh [--output PATH] [--listing PATH] [--dry-run]
#                       [--build-info PATH] [--version X.Y.Z]
#
# Packs the same include/exclude set as the desktop release. Materializes a
# listing file once and greps it (avoids SIGPIPE from unzip|grep under pipefail).
#
# --build-info PATH   copy JSON into the love archive root before verification
# --version X.Y.Z     stamp the release version inside the archive
# --dry-run           pack + verify only (for CI gates; no platform artifacts)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.bazinga/work"
OUTPUT="$WORK/game.love"
LISTING="$WORK/love-listing.txt"
DRY_RUN=0
BUILD_INFO=""
VERSION=""

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --listing) LISTING="$2"; shift 2 ;;
    --build-info) BUILD_INFO="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

mkdir -p "$(dirname "$OUTPUT")" "$(dirname "$LISTING")"

say "packing game.love"
rm -f "$OUTPUT"
# The launcher UI kit lives at src/ui/kit (inside src/, packed wholesale);
# the vendored libs/flexlove tree it replaced is gone.
(cd "$ROOT" && zip -q -9 -r "$OUTPUT" \
  main.lua conf.lua src data assets tools/save-editor \
  tools/rom_manifest.json tools/rom_manifest_blue.json \
  tools/rom_manifest_yellow.json tools/rom_manifest_gold.json \
  tools/rom_manifest_silver.json \
  -x '*.DS_Store' 'data/generated/*' 'assets/generated/*')
if [ -f "$ROOT/PATCH_NOTES.md" ]; then
  (cd "$ROOT" && zip -q "$OUTPUT" PATCH_NOTES.md)
fi
if [ -f "$ROOT/mobile/ios/app-repo.json" ]; then
  (cd "$ROOT" && zip -q "$OUTPUT" mobile/ios/app-repo.json)
fi

if [ -n "$BUILD_INFO" ]; then
  [ -f "$BUILD_INFO" ] || fail "missing build-info: $BUILD_INFO"
  [ "$(basename "$BUILD_INFO")" = "build-info.json" ] \
    || fail "build-info file must be named build-info.json"
  (cd "$(dirname "$BUILD_INFO")" && zip -q "$OUTPUT" build-info.json)
fi

if [ -n "$VERSION" ]; then
  printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || fail "invalid version '$VERSION' (expected X.Y.Z)"
  stamp_dir="$(mktemp -d "$(dirname "$OUTPUT")/stamp-love.XXXXXX")"
  output_abs="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
  trap 'rm -rf "$stamp_dir"' EXIT
  mkdir -p "$stamp_dir/src/core"
  sed -E "s/(engine[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1$VERSION\2/" \
    "$ROOT/src/core/Version.lua" > "$stamp_dir/src/core/Version.lua"
  (cd "$stamp_dir" && zip -q "$output_abs" src/core/Version.lua)
  version_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
  unzip -p "$output_abs" src/core/Version.lua \
    | grep -Eq "engine[[:space:]]*=[[:space:]]*\"$version_re\"" \
    || fail "version stamp failed: game.love does not report engine $VERSION"
  say "stamped engine version: $VERSION"
fi

# Materialize the listing once. Piping unzip→grep -q under `set -o pipefail`
# SIGPIPEs unzip when grep exits early on a match and aborts the build.
unzip -Z1 "$OUTPUT" > "$LISTING"
if grep -Eq '^(data|assets)/generated/[^/]+|^(data|assets)/generated/.+/' "$LISTING"; then
  fail "game.love unexpectedly contains generated ROM data"
fi

for required in tools/save-editor/App.lua tools/save-editor/Kit.lua \
                tools/save-editor/PadInput.lua \
                tools/save-editor/panels/Party.lua \
                tools/rom_manifest.json tools/rom_manifest_blue.json \
                tools/rom_manifest_yellow.json tools/rom_manifest_gold.json \
                tools/rom_manifest_silver.json \
                src/ui/kit/Kit.lua \
                src/import/LauncherView.lua; do
  grep -qxF "$required" "$LISTING" \
    || fail "game.love is missing $required"
done

if [ -n "$BUILD_INFO" ]; then
  grep -qxF "build-info.json" "$LISTING" \
    || fail "game.love is missing build-info.json"
fi

"$ROOT/scripts/switch/verify_payload.sh" "$OUTPUT"

say "game.love: $(du -h "$OUTPUT" | cut -f1)"

if [ "$DRY_RUN" -eq 1 ]; then
  say "pack dry-run OK: $OUTPUT"
fi

printf '%s\n' "$OUTPUT"
