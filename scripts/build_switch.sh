#!/usr/bin/env bash
# Nintendo Switch packaging entry point.
#
# Usage:
#   scripts/build_switch.sh --fetch
#   scripts/build_switch.sh --loose [path/to/game.love]
#   scripts/build_switch.sh --fused [--version X.Y.Z]
#   scripts/build_switch.sh --fetch --loose
#   scripts/build_switch.sh --fetch --fused [--version X.Y.Z]
#
# Modes:
#   --fetch   Download pinned love.nro + love.elf into
#             .bazinga/love-nx/11.5-nx1/ and verify SHA-256 against
#             scripts/switch/love-nx-11.5-nx1.sha256.
#             Auto-downloads those two release assets only.
#             Does NOT install devkitPro / dkp-pacman.
#
#   --loose   Pack game.love and copy pinned love.nro → dist/switch/loose/
#             (gen1recomp.nro + game.love side by side). Requires the pin
#             (run --fetch first, or combine --fetch --loose).
#
#   --fused   Build a single gen1recomp-<ver>-switch.nro via nacptool+elf2nro,
#             then pack dist/switch/gen1recomp-<ver>-switch.zip (SD-ready
#             tree under switch/gen1recomp/). Uses native tools (PATH or
#             $DEVKITPRO/tools/bin) first; else Docker from
#             scripts/switch/dkp-docker.image (override GEN1_DKP_IMAGE).
#             Requires the pin (run --fetch or combine). GitHub Releases
#             publish the zip only; the versioned .nro stays local / PR CI.
#
# Combinable: --fetch alone, or --fetch with --loose / --fused.
# XOR: --loose and --fused cannot be used together.
#
# Non-goals (never done by this script):
#   MTP push, ROM install, dkp-pacman auto-install.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.bazinga/work"
DIST="$ROOT/dist/switch"
LOOSE=0
FUSED=0
FETCH=0
GAME_LOVE=""
VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"

# Progress on stderr so command-substitution of pack_game_love stays a bare path.
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --loose) LOOSE=1; shift ;;
    --fused) FUSED=1; shift ;;
    --fetch) FETCH=1; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [ -z "$GAME_LOVE" ]; then
        GAME_LOVE="$1"
      else
        fail "unknown argument: $1"
      fi
      shift
      ;;
  esac
done

if [ "$LOOSE" -eq 1 ] && [ "$FUSED" -eq 1 ]; then
  fail "choose one of --loose or --fused (XOR)"
fi

if [ "$FETCH" -eq 0 ] && [ "$LOOSE" -eq 0 ] && [ "$FUSED" -eq 0 ]; then
  fail "specify --fetch, --loose, and/or --fused (see --help)"
fi

if [ "$FETCH" -eq 1 ]; then
  "$ROOT/scripts/switch/fetch_love_nx.sh"
fi

pack_game_love() {
  mkdir -p "$WORK" "$DIST"
  local build_info="$WORK/build-info.json"
  "$ROOT/scripts/switch/write_build_info.sh" "$build_info" "$VERSION"
  local love_out="$WORK/game.love"
  local listing="$WORK/love-listing.txt"
  "$ROOT/scripts/pack_love.sh" \
    --output "$love_out" \
    --listing "$listing" \
    --build-info "$build_info" >/dev/null
  # Stamp release version into the archive (same as build.sh / build_android.sh).
  # Working tree keeps 0.0.0-dev; only X.Y.Z --version patches Version.lua in-place.
  if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    say "stamping engine version $VERSION into game.love"
    local stamp_dir="$WORK/stamp"
    rm -rf "$stamp_dir"
    mkdir -p "$stamp_dir/src/core"
    sed -E "s/(engine[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1$VERSION\2/" \
      "$ROOT/src/core/Version.lua" > "$stamp_dir/src/core/Version.lua"
    (cd "$stamp_dir" && zip -q "$love_out" src/core/Version.lua)
    local version_re
    version_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
    unzip -p "$love_out" src/core/Version.lua \
      | grep -Eq "engine[[:space:]]*=[[:space:]]*\"$version_re\"" \
      || fail "version stamp failed: game.love does not report engine $VERSION"
    say "stamped engine version: $VERSION"
  else
    say "version '$VERSION' is not X.Y.Z, shipping default engine (no stamp)"
  fi
  cp "$build_info" "$DIST/build-info.json"
  cp "$build_info" "$DIST/gen1recomp-${VERSION}-build-info.json"
  printf '%s' "$love_out"
}

if [ "$LOOSE" -eq 1 ]; then
  if [ -z "$GAME_LOVE" ]; then
    GAME_LOVE="$(pack_game_love)"
  else
    pack_game_love >/dev/null
  fi
  exec "$ROOT/scripts/switch/assemble_loose.sh" "$GAME_LOVE"
fi

if [ "$FUSED" -eq 1 ]; then
  GAME_LOVE="$(pack_game_love)"
  OUT_NRO="$DIST/gen1recomp-${VERSION}-switch.nro"
  OUT_ZIP="$DIST/gen1recomp-${VERSION}-switch.zip"
  "$ROOT/scripts/switch/build_fused.sh" "$GAME_LOVE" "$VERSION" "$OUT_NRO"
  "$ROOT/scripts/switch/pack_sd_zip.sh" "$OUT_NRO" "$VERSION" "$OUT_ZIP"
  cp "$WORK/build-info.json" "$DIST/gen1recomp-${VERSION}-build-info.json"
  say "done. See $DIST/"
  exit 0
fi

# --fetch alone
if [ "$FETCH" -eq 1 ]; then
  say "fetch complete"
  exit 0
fi

fail "specify --fetch, --loose, and/or --fused (see --help)"
