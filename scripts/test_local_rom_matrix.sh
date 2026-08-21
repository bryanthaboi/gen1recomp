#!/usr/bin/env bash
# Opt-in, ROM-backed release check. Nothing beneath the ROM directory or the
# generated temporary caches is copied into the checkout.

set -euo pipefail

cd "$(dirname "$0")/.."
repo_root=$PWD

rom_dir="${POKEPORT_ROM_DIR:-}"
keep=0
verify_only=0

usage() {
  cat <<'EOF'
Usage: scripts/test_local_rom_matrix.sh [options]

  --rom-dir DIR     directory containing legal US ROM dumps
  --verify-only     identify/check every ROM without importing it
  --keep            retain the isolated cache directory after the run
  -h, --help        show this help

POKEPORT_ROM_DIR may be used instead of --rom-dir. If neither is supplied,
the default is ~/.local/share/gen1recomp-test-roms.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --rom-dir)
      [ "$#" -ge 2 ] || { echo "--rom-dir needs a directory" >&2; exit 2; }
      rom_dir=$2
      shift 2
      ;;
    --verify-only) verify_only=1; shift ;;
    --keep) keep=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$rom_dir" ]; then
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    rom_dir="$XDG_DATA_HOME/gen1recomp-test-roms"
  else
    rom_dir="${HOME:-}/.local/share/gen1recomp-test-roms"
  fi
fi

[ -d "$rom_dir" ] || {
  echo "ROM directory does not exist: $rom_dir" >&2
  echo "Pass --rom-dir DIR or set POKEPORT_ROM_DIR." >&2
  exit 2
}

for command_name in sha1sum find sort; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "required command is missing: $command_name" >&2
    exit 2
  }
done

versions=(red blue yellow gold silver)
declare -A expected_hash=(
  [red]=ea9bcae617fdf159b045185467ae58b2e4a48b9a
  [blue]=d7037c83e1ae5b39bde3c30787637ba1d4c48ce2
  [yellow]=cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1
  [gold]=d8b8a3600a465308c9953dfa04f0081c05bdcb94
  [silver]=49b163f7e57702bc939d642a18f591de55d92dae
  [crystal]=f4cd194bdee0d04ca4eac29e09b8e4e9d818c133
)
declare -A hash_version=()
for version_name in "${versions[@]}" crystal; do
  hash_version["${expected_hash[$version_name]}"]=$version_name
done

declare -A rom_path=()
unknown=0
while IFS= read -r -d '' candidate; do
  digest=$(sha1sum "$candidate" | cut -d' ' -f1)
  version_name=${hash_version[$digest]:-}
  if [ -z "$version_name" ]; then
    echo "UNKNOWN  $digest  $candidate" >&2
    unknown=$((unknown + 1))
    continue
  fi
  if [ -n "${rom_path[$version_name]:-}" ]; then
    echo "duplicate canonical $version_name ROM:" >&2
    echo "  ${rom_path[$version_name]}" >&2
    echo "  $candidate" >&2
    exit 2
  fi
  rom_path[$version_name]=$candidate
  printf '%-7s %s  %s\n' "$version_name" "$digest" "$candidate"
done < <(find "$rom_dir" -type f \( -iname '*.gb' -o -iname '*.gbc' \) -print0 | sort -z)

missing=0
for version_name in "${versions[@]}" crystal; do
  if [ -z "${rom_path[$version_name]:-}" ]; then
    echo "MISSING  canonical $version_name ROM (${expected_hash[$version_name]})" >&2
    missing=$((missing + 1))
  fi
done
if [ "$unknown" -gt 0 ] || [ "$missing" -gt 0 ]; then
  echo "ROM verification failed: $missing missing, $unknown unsupported" >&2
  exit 1
fi

echo "ROM verification passed: five supported cartridges plus Crystal negative input"
[ "$verify_only" = "1" ] && exit 0

for command_name in love xvfb-run luajit cp; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "required command is missing: $command_name" >&2
    exit 2
  }
done

matrix_root=$(mktemp -d "${TMPDIR:-/tmp}/gen1recomp-rom-matrix.XXXXXX")
cleanup() {
  if [ "$keep" = "1" ]; then
    echo "kept isolated ROM matrix data at $matrix_root"
  else
    rm -rf "$matrix_root"
  fi
}
trap cleanup EXIT

data_home="$matrix_root/xdg-data"
logs="$matrix_root/logs"
mkdir -p "$data_home" "$logs"

run_love() {
  local log=$1
  shift
  set +e
  env ALSOFT_DRIVERS=null XDG_DATA_HOME="$data_home" "$@" \
    xvfb-run -a love . >"$log" 2>&1
  local status=$?
  set -e
  return "$status"
}

assert_cache() {
  local version_name=$1
  local cache=$2
  local required=(
    rom-cache.complete
    data/generated/constants.lua
    data/generated/maps.lua
    data/generated/pokemon.lua
    data/generated/moves.lua
    data/generated/audio.lua
    assets/generated
  )
  local rel
  for rel in "${required[@]}"; do
    [ -e "$cache/$rel" ] || {
      echo "$version_name import is incomplete: missing $cache/$rel" >&2
      return 1
    }
  done
}

make_content_overlay() {
  local cache=$1
  local destination=$2
  local entry base
  mkdir -p "$destination/data" "$destination/assets"
  for entry in "$repo_root"/*; do
    base=${entry##*/}
    case "$base" in
      data|assets|options.lua|options.lua.bak|options.lua.tmp) continue ;;
    esac
    # Two meta-suites recursively scan src/ and scripts/ without following
    # symlinks. Copy those small trees so the isolated aggregate cannot pass
    # vacuously; the much larger read-only trees remain linked.
    if [ "$base" = "src" ] || [ "$base" = "scripts" ]; then
      cp -a "$entry" "$destination/$base"
    else
      ln -s "$entry" "$destination/$base"
    fi
  done
  for entry in "$repo_root"/data/*; do
    base=${entry##*/}
    [ "$base" = "generated" ] || ln -s "$entry" "$destination/data/$base"
  done
  for entry in "$repo_root"/assets/*; do
    base=${entry##*/}
    [ "$base" = "generated" ] || ln -s "$entry" "$destination/assets/$base"
  done
  ln -s "$cache/data/generated" "$destination/data/generated"
  ln -s "$cache/assets/generated" "$destination/assets/generated"
}

set -e
for version_name in "${versions[@]}"; do
  identity="rom-matrix-$version_name-$$"
  save_root="$data_home/love/$identity"
  cache="$save_root/$version_name"
  import_log="$logs/$version_name-import.log"
  smoke_log="$logs/$version_name-smoke.log"

  echo
  echo "== $version_name: real LÖVE import"
  if ! run_love "$import_log" \
      POKEPORT_IDENTITY="$identity" \
      POKEPORT_VERSION="$version_name" \
      POKEPORT_IMPORT_ONLY=1 \
      POKEPORT_FORCE_IMPORT=1 \
      POKEPORT_IMPORT_ROM="${rom_path[$version_name]}"; then
    # Some headless OpenAL builds return 1 after a normal quit with the null
    # driver. The completed marker is the importer's atomic success receipt;
    # it is stronger evidence than that host-specific process status.
    if [ ! -f "$cache/rom-cache.complete" ]; then
      tail -80 "$import_log" >&2
      echo "$version_name importer failed" >&2
      exit 1
    fi
    echo "note: LÖVE returned non-zero after writing the complete cache"
  fi
  assert_cache "$version_name" "$cache"

  echo "== $version_name: cache-backed dataset probe"
  POKEPORT_DATA_DIR="$cache/data/generated" \
    POKEPORT_MATRIX_VERSION="$version_name" \
    luajit tests/local_rom_dataset_test.lua

  if [ "$version_name" = "red" ]; then
    content_log="$logs/red-content.log"
    content_root="$matrix_root/red-content-root"
    echo "== red: complete Gen 1 content aggregate"
    make_content_overlay "$cache" "$content_root"
    if ! (cd "$content_root" && \
        luajit tests/run_tests.lua >"$content_log" 2>&1); then
      tail -120 "$content_log" >&2
      echo "Red content aggregate failed" >&2
      exit 1
    fi
    tail -3 "$content_log"
  elif [ "$version_name" = "gold" ] || [ "$version_name" = "silver" ]; then
    gen2_log="$logs/$version_name-gen2.log"
    echo "== $version_name: 107 cache-backed Gen 2 suites"
    if ! GOLD_CACHE="$cache" luajit tests/run_gen2.lua >"$gen2_log" 2>&1; then
      tail -160 "$gen2_log" >&2
      echo "$version_name Gen 2 aggregate failed" >&2
      exit 1
    fi
    tail -3 "$gen2_log"
  fi

  echo "== $version_name: real LÖVE boot/render smoke"
  if ! run_love "$smoke_log" \
      POKEPORT_IDENTITY="$identity" \
      POKEPORT_GAME="$version_name" \
      POKEPORT_MATRIX_VERSION="$version_name" \
      POKEPORT_BOOT_OVERWORLD=1 \
      POKEPORT_TOUCH=0 \
      POKEPORT_DRIVER=tests/drivers/local_rom_matrix_smoke.lua; then
    if ! grep -qx "\[rom-matrix\] PASS $version_name" "$smoke_log"; then
      tail -100 "$smoke_log" >&2
      echo "$version_name real-LÖVE smoke failed" >&2
      exit 1
    fi
    echo "note: LÖVE returned non-zero after the smoke driver passed"
  fi
  grep -qx "\[rom-matrix\] PASS $version_name" "$smoke_log" || {
    tail -100 "$smoke_log" >&2
    echo "$version_name smoke did not emit its success receipt" >&2
    exit 1
  }
done

echo
echo "== crystal: unsupported-ROM negative path"
crystal_identity="rom-matrix-crystal-$$"
crystal_root="$data_home/love/$crystal_identity"
crystal_log="$logs/crystal-rejection.log"
if run_love "$crystal_log" \
    POKEPORT_IDENTITY="$crystal_identity" \
    POKEPORT_VERSION=crystal \
    POKEPORT_IMPORT_ONLY=1 \
    POKEPORT_FORCE_IMPORT=1 \
    POKEPORT_IMPORT_ROM="${rom_path[crystal]}"; then
  cat "$crystal_log" >&2
  echo "Crystal import unexpectedly succeeded" >&2
  exit 1
fi
if find "$crystal_root" -type f -name rom-cache.complete -print -quit \
    2>/dev/null | grep -q .; then
  echo "Crystal rejection left a completed cache behind" >&2
  exit 1
fi
if find "$crystal_root" -type f \( -path '*/data/generated/*' \
    -o -path '*/assets/generated/*' \) -print -quit 2>/dev/null | grep -q .; then
  echo "Crystal rejection left partial generated cartridge data behind" >&2
  exit 1
fi
grep -Eq "Unsupported ROM|unsupported ROM|import failed" "$crystal_log" || {
  tail -100 "$crystal_log" >&2
  echo "Crystal failed without the expected unsupported-ROM diagnostic" >&2
  exit 1
}
echo "Crystal was rejected and left no complete or partial cache"

echo
echo "LOCAL ROM MATRIX PASSED"
