#!/usr/bin/env bash
# Sourceable download/hash/container helpers. No side effects on source.
# The caller must define say, warn and fail.

# Print SHA-256 hex digest of PATH. Prefers sha256sum, falls back to shasum
# (same order-agnostic pair scripts/switch/common.sh uses).
sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    fail "need sha256sum or shasum (install coreutils)"
  fi
}

# download_pinned URL DEST EXPECTED_SHA256
#
# A cache hit is only trusted if it still hashes to the pin: a download
# truncated by a network drop would otherwise be reused forever, which is the
# same trap scripts/build.sh guards for the win64 zip and the x86_64 AppImage.
download_pinned() {
  local url="$1" dest="$2" want="$3" got=""
  if [ -f "$dest" ]; then
    got="$(sha256_file "$dest")"
    if [ "$got" = "$want" ]; then
      return 0
    fi
    warn "cached $(basename "$dest") has the wrong digest, re-downloading"
    rm -f "$dest"
  fi
  say "downloading $(basename "$dest")"
  # --retry-all-errors because plain --retry skips TLS handshake failures,
  # which is how xiph.org drops these tarballs; the pin below still gates it.
  # curl < 7.71 lacks the flag and rejects it, so it is only passed if offered.
  local retry_all=()
  # No grep -q: it would exit early and SIGPIPE curl, which pipefail reports.
  if curl --help all 2>/dev/null | grep -- --retry-all-errors >/dev/null; then
    retry_all=(--retry-all-errors)
  fi
  curl -fL --retry 5 --retry-delay 2 ${retry_all[@]+"${retry_all[@]}"} --progress-bar \
    "$url" -o "$dest.tmp" || fail "download failed: $url"
  got="$(sha256_file "$dest.tmp")"
  [ "$got" = "$want" ] || fail "$(printf '%s\n  expected %s\n  got      %s' \
    "checksum mismatch for $(basename "$dest")" "$want" "$got")"
  mv "$dest.tmp" "$dest"
}

# Echo the container runtime to use: docker, else podman.
container_runtime() {
  if [ -n "${GEN1_CONTAINER_RUNTIME:-}" ]; then
    printf '%s' "$GEN1_CONTAINER_RUNTIME"
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    printf 'docker'
  elif command -v podman >/dev/null 2>&1; then
    printf 'podman'
  else
    return 1
  fi
}
