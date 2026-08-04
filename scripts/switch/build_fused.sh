#!/usr/bin/env bash
# Build fused gen1recomp Switch NRO (romfs game.love + nacp + icon).
#
# Usage: scripts/switch/build_fused.sh GAME_LOVE VERSION OUT_NRO
#
# Prefers native nacptool/elf2nro (PATH or $DEVKITPRO/tools/bin).
# Falls back to Docker using GEN1_DKP_IMAGE or scripts/switch/dkp-docker.image.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

LOVE_NX_TAG="11.5-nx1"
LOVE_NX_DIR="$ROOT/.bazinga/love-nx/$LOVE_NX_TAG"
LOVE_ELF="$LOVE_NX_DIR/love.elf"
ICON="$ROOT/assets/switch/icon.jpg"
APP_NAME="gen1recomp"
APP_AUTHOR="bryanthaboi, port by andrewqsantos"
DKP_IMAGE_FILE="$ROOT/scripts/switch/dkp-docker.image"

GAME_LOVE="${1:-}"
VERSION="${2:-}"
OUT_NRO="${3:-}"

[ -n "$GAME_LOVE" ] && [ -n "$VERSION" ] && [ -n "$OUT_NRO" ] \
  || fail "usage: $0 GAME_LOVE VERSION OUT_NRO"

[ -f "$GAME_LOVE" ] || fail "missing game.love at $GAME_LOVE"

"$ROOT/scripts/switch/verify_love_nx.sh"

[ -f "$ICON" ] || fail "missing Switch icon at $ICON"

ensure_dkp_tools_path

resolve_dkp_image() {
  if [ -n "${GEN1_DKP_IMAGE:-}" ]; then
    printf '%s' "$GEN1_DKP_IMAGE"
    return 0
  fi
  [ -f "$DKP_IMAGE_FILE" ] || fail "missing Docker image pin: $DKP_IMAGE_FILE"
  local line
  line="$(grep -v '^[[:space:]]*#' "$DKP_IMAGE_FILE" | grep -v '^[[:space:]]*$' | head -1 || true)"
  [ -n "$line" ] || fail "empty Docker image pin: $DKP_IMAGE_FILE"
  printf '%s' "$line"
}

run_fused_native() {
  local work romfs_dir nacp
  work="$(mktemp -d "${TMPDIR:-/tmp}/gen1recomp-fused.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT

  romfs_dir="$work/romfs"
  mkdir -p "$romfs_dir" "$(dirname "$OUT_NRO")"
  cp "$GAME_LOVE" "$romfs_dir/game.love"

  nacp="$work/control.nacp"
  nacptool --create "$APP_NAME" "$APP_AUTHOR" "$VERSION" "$nacp"

  say "building fused NRO with pinned love.elf (native)"
  elf2nro "$LOVE_ELF" "$OUT_NRO" \
    --icon="$ICON" \
    --nacp="$nacp" \
    --romfsdir="$romfs_dir"
}

run_fused_docker() {
  local image stage out_dir out_base
  image="$(resolve_dkp_image)"
  command -v docker >/dev/null 2>&1 || fail_fused_toolchain

  # Stage under ROOT so a single repo bind-mount covers love.elf, icon, and romfs.
  stage="$ROOT/.bazinga/work/fused-docker-$$"
  mkdir -p "$stage/romfs" "$(dirname "$OUT_NRO")"
  cp "$GAME_LOVE" "$stage/romfs/game.love"
  # shellcheck disable=SC2064
  trap "rm -rf '$stage'" EXIT

  out_dir="$(cd "$(dirname "$OUT_NRO")" && pwd)"
  out_base="$(basename "$OUT_NRO")"

  say "building fused NRO with pinned love.elf (Docker: $image)"
  docker run --rm \
    -v "$ROOT:/src:ro" \
    -v "$stage:/work" \
    -v "$out_dir:/out" \
    -w /work \
    "$image" \
    bash -c "
      set -euo pipefail
      nacptool --create '$APP_NAME' '$APP_AUTHOR' '$VERSION' /work/control.nacp
      elf2nro /src/.bazinga/love-nx/$LOVE_NX_TAG/love.elf /out/$out_base \
        --icon=/src/assets/switch/icon.jpg \
        --nacp=/work/control.nacp \
        --romfsdir=/work/romfs
    "
}

if command -v nacptool >/dev/null 2>&1 && command -v elf2nro >/dev/null 2>&1; then
  run_fused_native
elif command -v docker >/dev/null 2>&1; then
  run_fused_docker
else
  fail_fused_toolchain
fi

[ -f "$OUT_NRO" ] || fail "fused NRO was not produced at $OUT_NRO"
sha256_file "$OUT_NRO" > "${OUT_NRO}.sha256"
say "fused NRO: $OUT_NRO"
say "sha256: $(cat "${OUT_NRO}.sha256")"
