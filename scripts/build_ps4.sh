#!/usr/bin/env bash
# PlayStation 4 packaging entry point (homebrew, GoldHEN).
#
# Usage:
#   scripts/build_ps4.sh --fetch
#   scripts/build_ps4.sh --loose
#   scripts/build_ps4.sh --fused [--version X.Y.Z]
#   scripts/build_ps4.sh --fetch --fused [--version X.Y.Z]
#
# Modes:
#   --fetch   Download the pinned LÖVE for PS4 runtime zip into
#             .bazinga/love-ps4/<tag>/ and verify SHA-256 against
#             scripts/ps4/love-ps4-runtime.sha256.
#
#   --loose   Pack game.love into dist/ps4/loose/ for players who already have
#             the generic "LÖVE for PS4" package installed: they copy it to
#             /data/love/game.love over FTP. Does not need the runtime.
#
#   --fused   Build gen1recomp-<ver>-ps4.pkg: runtime + game.love in one
#             installable package (title id GENR00001; its own tile and saves).
#             Requires the pin (run --fetch or combine) and the OpenOrbis
#             packaging tools: OO_PS4_TOOLCHAIN pointing at an unpacked
#             OpenOrbis PS4 Toolchain v0.5.4 (bin/linux or bin/macos with
#             PkgTool.Core and create-gp4), plus bash 4+.
#
# The runtime is LÖVE 11.5 for PS4 by Tomas Morello
# (https://github.com/tomasmorello/love-ps4), pinned the way love-nx is pinned
# for the Switch.
#
# Non-goals: installing on a console, FTP uploads, ROM handling.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.bazinga/work"
DIST="$ROOT/dist/ps4"
MANIFEST="$ROOT/scripts/ps4/love-ps4-runtime.sha256"
TITLE_ID="${GEN1_PS4_TITLE_ID:-GENR00001}"
FETCH=0; LOOSE=0; FUSED=0
VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --fetch) FETCH=1; shift ;;
    --loose) LOOSE=1; shift ;;
    --fused) FUSED=1; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[ $((FETCH + LOOSE + FUSED)) -gt 0 ] || fail "specify --fetch, --loose and/or --fused (see --help)"
[ $((LOOSE + FUSED)) -le 1 ] || fail "--loose and --fused cannot be combined"

manifest_field() { # manifest_field <key>
  local v
  v="$(awk -v k="$1" '$1 == k { print $2; exit }' "$MANIFEST")"
  [ -n "$v" ] || fail "$MANIFEST has no '$1' entry"
  printf '%s' "$v"
}
TAG="$(manifest_field tag)"
ZIP_NAME="love-ps4-${TAG#v}-runtime.zip"
RUNTIME_DIR="$ROOT/.bazinga/love-ps4/$TAG"
ZIP="$RUNTIME_DIR/$ZIP_NAME"
BASE_URL="${GEN1_LOVE_PS4_BASE_URL:-https://github.com/tomasmorello/love-ps4/releases/download/$TAG}"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

fetch_runtime() {
  local want have
  want="$(manifest_field "$ZIP_NAME")"
  mkdir -p "$RUNTIME_DIR"
  if [ -f "$ZIP" ] && [ "$(sha256_of "$ZIP")" = "$want" ]; then
    say "runtime $TAG already fetched"
  else
    say "downloading $BASE_URL/$ZIP_NAME"
    curl -fL --retry 3 --retry-delay 1 -o "$ZIP.part" "$BASE_URL/$ZIP_NAME" \
      || { rm -f "$ZIP.part"; fail "download failed: $BASE_URL/$ZIP_NAME"; }
    have="$(sha256_of "$ZIP.part")"
    [ "$have" = "$want" ] || { rm -f "$ZIP.part"; fail "SHA-256 mismatch for $ZIP_NAME: got $have, pinned $want"; }
    mv "$ZIP.part" "$ZIP"
  fi
  rm -rf "$RUNTIME_DIR/unpacked"
  mkdir -p "$RUNTIME_DIR/unpacked"
  (cd "$RUNTIME_DIR/unpacked" && unzip -q "$ZIP")
}

pack_game_love() {
  mkdir -p "$WORK"
  local love_out="$WORK/game.love"
  # pack_love.sh only accepts X.Y.Z; dev builds (a commit hash) stay unstamped.
  if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    "$ROOT/scripts/pack_love.sh" --output "$love_out" --listing "$WORK/love-listing.txt" \
      --version "$VERSION" >/dev/null
  else
    "$ROOT/scripts/pack_love.sh" --output "$love_out" --listing "$WORK/love-listing.txt" >/dev/null
  fi
  printf '%s' "$love_out"
}

# X.Y.Z -> PS4 APP_VER "NN.NN" as (10*X+Y).Z: 0.3.1 -> 03.01, 1.0.0 -> 10.00.
# Monotonic while Y < 10 and Z < 100, so a newer release installs over an older one.
app_ver() {
  if printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]\.[0-9]{1,2}$'; then
    local x y z
    IFS=. read -r x y z <<EOF
$1
EOF
    printf '%02d.%02d' "$((10 * x + y))" "$z"
  else
    printf '00.00'   # dev builds: always older than any release
  fi
}

[ "$FETCH" -eq 1 ] && fetch_runtime

if [ "$LOOSE" -eq 1 ]; then
  mkdir -p "$DIST/loose"
  cp "$(pack_game_love)" "$DIST/loose/game.love"
  say "dist/ps4/loose/game.love -> copy to /data/love/game.love on the console"
fi

if [ "$FUSED" -eq 1 ]; then
  [ -f "$ZIP" ] || fail "runtime not fetched: run with --fetch"
  [ -d "$RUNTIME_DIR/unpacked" ] || fetch_runtime
  [ -n "${OO_PS4_TOOLCHAIN:-}" ] || fail "OO_PS4_TOOLCHAIN is not set (OpenOrbis PS4 Toolchain v0.5.4)"
  fuse="$(ls "$RUNTIME_DIR"/unpacked/*/fuse-pkg.sh)"
  love="$(pack_game_love)"
  icon="$ROOT/scripts/ps4/icon0.png"
  [ -f "$icon" ] || icon=""
  mkdir -p "$DIST"
  "$fuse" --love "$love" --title-id "$TITLE_ID" --title "Gen1Recomp" \
    --version "$(app_ver "$VERSION")" --content-label GEN1RECOMP --out-dir "$WORK/ps4-pkg" \
    ${icon:+--icon "$icon"}
  cp "$WORK"/ps4-pkg/IV0000-"$TITLE_ID"_00-*.pkg "$DIST/gen1recomp-$VERSION-ps4.pkg"
  (cd "$DIST" && sha256_of "gen1recomp-$VERSION-ps4.pkg" > "gen1recomp-$VERSION-ps4.pkg.sha256")
  say "dist/ps4/gen1recomp-$VERSION-ps4.pkg"
fi
