#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

if [ $# -ne 2 ]; then
  echo "usage: $0 <liblibrashader_bridge.so> <libc++_shared.so>" >&2
  exit 2
fi
bridge="$1"
libcxx="$2"
if [ ! -f "$bridge" ]; then
  echo "no bridge at $bridge" >&2
  exit 2
fi

nm="${LLVM_NM:-}"
if [ -z "$nm" ]; then
  for ndk in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    [ -n "$ndk" ] || continue
    for cand in "$ndk"/toolchains/llvm/prebuilt/*/bin/llvm-nm; do
      if [ -x "$cand" ]; then
        nm="$cand"
        break 2
      fi
    done
  done
fi
if [ -z "$nm" ]; then
  nm="$(command -v llvm-nm || true)"
fi
if [ -z "$nm" ] || [ ! -x "$nm" ]; then
  echo "llvm-nm not found (set LLVM_NM or ANDROID_NDK_HOME)" >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$nm" -D --undefined-only "$bridge" > "$tmp/undefined"
awk '$(NF-1) == "U" { s = $NF; sub(/@.*/, "", s); if (s ~ /^_Z/) print s }' \
  "$tmp/undefined" | sort -u > "$tmp/need"

: > "$tmp/have"
if [ -f "$libcxx" ]; then
  "$nm" -D --defined-only "$libcxx" > "$tmp/defined"
  awk '{ s = $NF; sub(/@.*/, "", s); print s }' "$tmp/defined" | sort -u > "$tmp/have"
fi

comm -23 "$tmp/need" "$tmp/have" > "$tmp/missing"
if [ -s "$tmp/missing" ]; then
  count="$(wc -l < "$tmp/missing" | tr -d ' ')"
  echo "$(basename "$bridge") needs $count C++ runtime symbols that $libcxx does not define, so dlopen fails:"
  head -n 5 "$tmp/missing" | sed 's/^/  /'
  exit 1
fi
echo "$(basename "$bridge") links against $(basename "$libcxx")"
