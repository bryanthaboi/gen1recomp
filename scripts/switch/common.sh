#!/usr/bin/env bash
# Shared helpers for Switch packaging scripts.
# Source from other scripts:  . "$(dirname "$0")/common.sh"  (or similar)

# shellcheck disable=SC2034
if [ -z "${ROOT:-}" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
export ROOT

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Print SHA-256 hex digest of PATH. Prefers shasum, falls back to sha256sum.
sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    fail "need shasum or sha256sum (install coreutils / Xcode CLT)"
  fi
}

# If nacptool is missing but $DEVKITPRO/tools/bin exists, prepend it to PATH.
ensure_dkp_tools_path() {
  if command -v nacptool >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "${DEVKITPRO:-}" ] && [ -d "$DEVKITPRO/tools/bin" ]; then
    export PATH="$DEVKITPRO/tools/bin:$PATH"
  fi
}

# Missing love-nx pin — tell user to run --fetch.
fail_need_fetch() {
  fail "${1:-missing pinned love-nx} — run: scripts/build_switch.sh --fetch"
}

# Fused mode needs nacptool/elf2nro (native or Docker). Rich multi-OS hint.
fail_fused_toolchain() {
  fail "$(cat <<'EOF'
fused packaging needs nacptool and elf2nro (devkitPro switch-dev).

Install options:
  macOS:    https://devkitpro.org/wiki/devkitPro_pacman (installer / pacman)
  Linux:    https://devkitpro.org/wiki/devkitPro_pacman
  Windows:  Git Bash / MSYS2 / WSL with devkitPro tools on PATH
  Docker:   install Docker; build_fused.sh falls back to the pinned image

See docs/switch-build.md for details.
EOF
)"
}
