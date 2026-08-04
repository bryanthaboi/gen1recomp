#!/usr/bin/env bash
# Download pinned love-nx 11.5-nx1 binaries (love.nro + love.elf) and verify SHA.
#
# Usage: scripts/switch/fetch_love_nx.sh
#
# Idempotent: if both files exist and match the manifest, exit 0 without download.
# Downloads only these two release assets — does NOT install devkitPro.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

LOVE_NX_TAG="11.5-nx1"
LOVE_NX_DIR="$ROOT/.bazinga/love-nx/$LOVE_NX_TAG"
MANIFEST="$ROOT/scripts/switch/love-nx-11.5-nx1.sha256"
# Override for offline selftests (never used in release/docs as the default).
BASE_URL="${GEN1_LOVE_NX_BASE_URL:-https://github.com/retronx-team/love-nx/releases/download/${LOVE_NX_TAG}}"

fail_download() {
  local url="$1"
  local detail="$2"
  rm -f "${3:-}"
  fail "download failed: $url
  detail: $detail
  retry: scripts/build_switch.sh --fetch
  See docs/switch-build.md (mode --fetch)."
}

read_manifest_hash() {
  local name="$1"
  local line hash
  line="$(grep -E "^${name}[[:space:]]+" "$MANIFEST" | head -1 || true)"
  [ -n "$line" ] || fail "manifest missing entry for $name"
  hash="$(printf '%s' "$line" | awk '{print $2}')"
  case "$hash" in
    TBD_*|"") fail "manifest hash for $name is not filled in ($hash)" ;;
  esac
  printf '%s' "$hash"
}

# Downloads url → dest. On failure prints structured error (URL, tool status, retry).
download_file() {
  local url="$1"
  local dest="$2"
  local rc=0 http_code errf

  if command -v curl >/dev/null 2>&1; then
    errf="$(mktemp "${TMPDIR:-/tmp}/love-nx-curl.XXXXXX")"
    http_code="$(curl -fL --retry 3 --retry-delay 1 -o "$dest" -w '%{http_code}' \
      "$url" 2>"$errf")" || rc=$?
    if [ "$rc" -ne 0 ]; then
      fail_download "$url" \
        "curl exit $rc; HTTP status ${http_code:-unknown}; $(tr '\n' ' ' <"$errf" | sed 's/[[:space:]]*$//')" \
        "$dest"
    fi
    rm -f "$errf"
  elif command -v wget >/dev/null 2>&1; then
    errf="$(mktemp "${TMPDIR:-/tmp}/love-nx-wget.XXXXXX")"
    wget -O "$dest" "$url" 2>"$errf" || rc=$?
    if [ "$rc" -ne 0 ]; then
      fail_download "$url" \
        "wget exit $rc; $(tr '\n' ' ' <"$errf" | sed 's/[[:space:]]*$//')" \
        "$dest"
    fi
    rm -f "$errf"
  else
    fail "need curl or wget to download love-nx
  retry: scripts/build_switch.sh --fetch
  See docs/switch-build.md (mode --fetch)."
  fi
}

fetch_one() {
  local name="$1"
  local expected actual
  local url="$BASE_URL/$name"
  local dest="$LOVE_NX_DIR/$name"
  local tmp

  expected="$(read_manifest_hash "$name")"

  if [ -f "$dest" ]; then
    actual="$(sha256_file "$dest")"
    if [ "$actual" = "$expected" ]; then
      return 0
    fi
    say "checksum mismatch for existing $name — re-downloading"
    rm -f "$dest"
  fi

  mkdir -p "$LOVE_NX_DIR"
  tmp="$(mktemp "${TMPDIR:-/tmp}/love-nx-${name}.XXXXXX")"
  say "downloading $name"
  # download_file fails the script with fail_download (URL + status + retry).
  download_file "$url" "$tmp"

  actual="$(sha256_file "$tmp")"
  if [ "$actual" != "$expected" ]; then
    rm -f "$tmp"
    fail "$name checksum mismatch (expected $expected, got $actual) — $url
  retry: scripts/build_switch.sh --fetch"
  fi

  mv "$tmp" "$dest"
  say "verified $name ($actual)"
}

[ -f "$MANIFEST" ] || fail "missing love-nx manifest: $MANIFEST"

EXPECTED_NRO="$(read_manifest_hash love.nro)"
EXPECTED_ELF="$(read_manifest_hash love.elf)"

if [ -f "$LOVE_NX_DIR/love.nro" ] && [ -f "$LOVE_NX_DIR/love.elf" ]; then
  ACTUAL_NRO="$(sha256_file "$LOVE_NX_DIR/love.nro")"
  ACTUAL_ELF="$(sha256_file "$LOVE_NX_DIR/love.elf")"
  if [ "$ACTUAL_NRO" = "$EXPECTED_NRO" ] && [ "$ACTUAL_ELF" = "$EXPECTED_ELF" ]; then
    say "love-nx $LOVE_NX_TAG already present and verified — skipping download"
    "$ROOT/scripts/switch/verify_love_nx.sh"
    exit 0
  fi
fi

fetch_one love.nro
fetch_one love.elf

"$ROOT/scripts/switch/verify_love_nx.sh"
say "love-nx $LOVE_NX_TAG ready at $LOVE_NX_DIR"
