#!/usr/bin/env bash
# Build a PortMaster aarch64 port of gen1recomp for Linux ARM SBC handhelds.
# The package uses PortMaster control hooks and a self-contained LÖVE runtime,
# while keeping paths relative to the launcher for broad CFW compatibility.
#
# The launcher uses SHDIR-relative paths and bundles the LÖVE 11.5 aarch64
# runtime so the device does not need a separate runtime download on first launch.
#
# Usage:
#   ./build-linux-arm-sbc.sh [--version X.Y.Z]
#   GEN1RECOMP_SOURCE_DIR="$PWD" ./build-linux-arm-sbc.sh --version X.Y.Z
#   ./build-linux-arm-sbc.sh --source /path/to/gen1recomp --version X.Y.Z
#
# Output:
#   dist/linux-arm-sbc/gen1recomp-sbc-portmaster.zip
#
# Install on device:
#   1. Install PortMaster for the handheld firmware.
#   2. Unzip into the device's PortMaster ports folder so you have:
#        Roms/Ports (PORTS)/gen1recomp-sbc.sh
#        Roms/Ports (PORTS)/gen1recomp-sbc/...
#   3. Copy a legal US Red or Blue .gb into Roms/Ports (PORTS)/gen1recomp-sbc/lovegame/
#   4. Launch "gen1recomp-sbc" from the Ports list; press Choose ROM (scans that
#      folder when zenity is missing).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HERE="$ROOT/.bazinga"
CACHE="$HERE/cache/linux-arm-sbc"
WORK="$HERE/work/linux-arm-sbc"
DIST="$ROOT/dist/linux-arm-sbc"

APP_NAME="gen1recomp-sbc"
# Artifact suffix identifies this as the generic PortMaster SBC package.
# Release uploads stage it as gen1recomp-<ver>-sbc-portmaster.zip.
ARTIFACT_SUFFIX="portmaster"
PORT_DIR_NAME="gen1recomp-sbc"
LAUNCHER_NAME="gen1recomp-sbc.sh"
LOVE_VERSION="11.5"
# By default the pack is reproducible from the latest published GitHub release,
# not whatever happens to be in the caller's checkout.  Development builds can
# point this at a local checkout with GEN1RECOMP_SOURCE_DIR=/path/to/repo.
SOURCE_DIR_OVERRIDE="${GEN1RECOMP_SOURCE_DIR:-}"
SOURCE_TAG_OVERRIDE="${GEN1RECOMP_RELEASE_TAG:-}"
VERSION="${GEN1RECOMP_VERSION:-}"

# Official PortMaster LÖVE 11.5 aarch64 runtime (small love stub + liblove).
PM_RUNTIME_BASE="https://raw.githubusercontent.com/PortsMaster/PortMaster-GUI/main/PortMaster/runtimes/love_${LOVE_VERSION}"
RELEASES_LATEST_URL="https://github.com/bryanthaboi/gen1recomp/releases/latest"
RELEASE_TARBALL_BASE="https://github.com/bryanthaboi/gen1recomp/archive/refs/tags"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || fail "--version needs X.Y.Z"; VERSION="$2"; shift ;;
    --source) [ $# -ge 2 ] || fail "--source needs a directory"; SOURCE_DIR_OVERRIDE="$2"; shift ;;
    --release-tag) [ $# -ge 2 ] || fail "--release-tag needs a tag"; SOURCE_TAG_OVERRIDE="$2"; shift ;;
    -h|--help)
      sed -n '2,24p' "$0"
      exit 0
      ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift
done

command -v curl >/dev/null || fail "curl is required"
command -v zip  >/dev/null || fail "zip is required"
command -v unzip >/dev/null || fail "unzip is required"
command -v tar  >/dev/null || fail "tar is required"

mkdir -p "$CACHE" "$WORK" "$DIST"

download() {
  local url="$1" dest="$2"
  if [ -f "$dest" ] && [ -s "$dest" ]; then
    return 0
  fi
  say "downloading $(basename "$dest")"
  curl -fL --progress-bar "$url" -o "$dest.tmp" \
    || fail "download failed: $url"
  mv "$dest.tmp" "$dest"
}

# --------------------------------------------------------------- source + game tree
# Release builds use the latest published source archive. A local checkout is
# an explicit override for development and for CI's just-built release source.
if [ -n "$SOURCE_DIR_OVERRIDE" ]; then
  SOURCE_DIR_OVERRIDE="$(cd "$SOURCE_DIR_OVERRIDE" 2>/dev/null && pwd)" \
    || fail "source directory does not exist: $SOURCE_DIR_OVERRIDE"
  SOURCE_DIR="$SOURCE_DIR_OVERRIDE"
  SOURCE_TAG="${SOURCE_TAG_OVERRIDE:-local}"
  if [ "$SOURCE_TAG" != "local" ]; then
    printf '%s' "$SOURCE_TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' \
      || fail "release tag must look like vX.Y.Z: $SOURCE_TAG"
  fi
  if [ -z "$VERSION" ]; then
    VERSION="$(git -C "$SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo dev)"
  fi
else
  if [ -z "$SOURCE_TAG_OVERRIDE" ]; then
    latest_location="$(curl -fsSI "$RELEASES_LATEST_URL" \
      | awk 'tolower($1) == "location:" { print $2 }' | tail -1 | tr -d '\r')" \
      || fail "could not resolve latest published release"
    SOURCE_TAG_OVERRIDE="${latest_location##*/}"
  fi
  printf '%s' "$SOURCE_TAG_OVERRIDE" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    || fail "release tag must look like vX.Y.Z: $SOURCE_TAG_OVERRIDE"
  SOURCE_TAG="$SOURCE_TAG_OVERRIDE"
  SOURCE_ARCHIVE="$CACHE/gen1recomp-${SOURCE_TAG}.tar.gz"
  download "$RELEASE_TARBALL_BASE/$SOURCE_TAG.tar.gz" "$SOURCE_ARCHIVE"
  SOURCE_EXTRACT="$WORK/source-$SOURCE_TAG"
  rm -rf "$SOURCE_EXTRACT"
  mkdir -p "$SOURCE_EXTRACT"
  tar -xzf "$SOURCE_ARCHIVE" -C "$SOURCE_EXTRACT"
  SOURCE_DIR="$(find "$SOURCE_EXTRACT" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [ -n "$SOURCE_DIR" ] || fail "release archive had no source directory"
  if [ -z "$VERSION" ]; then VERSION="${SOURCE_TAG#v}"; fi
fi

say "staging lovegame/ from $SOURCE_TAG"
GAME_SRC="$WORK/lovegame"
rm -rf "$GAME_SRC"
mkdir -p "$GAME_SRC"

# Same payload as scripts/build.sh's game.love — never ship ROM-derived cache.
# tools/save-editor is part of that payload: the launcher's Edit button on a
# save row opens it in-process (main.lua).
(cd "$SOURCE_DIR" && zip -q -9 -r "$WORK/game-payload.zip" \
  main.lua conf.lua src libs data assets tools/save-editor \
  tools/rom_manifest.json tools/rom_manifest_blue.json \
  tools/rom_manifest_yellow.json tools/rom_manifest_gold.json \
  tools/rom_manifest_silver.json tools/rom_manifest_crystal.json \
  -x '*.DS_Store' 'data/generated/*' 'assets/generated/*')
if unzip -Z1 "$WORK/game-payload.zip" \
    | grep -Eq '^(data|assets)/generated/[^/]+|^(data|assets)/generated/.+/'; then
  fail "payload unexpectedly contains generated ROM data"
fi
unzip -q "$WORK/game-payload.zip" -d "$GAME_SRC"
rm -f "$WORK/game-payload.zip"

# Stamp release version into the staged tree only (never the working tree).
if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  say "stamping engine version $VERSION"
  sed -E "s/(engine[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1$VERSION\2/" \
    "$SOURCE_DIR/src/core/Version.lua" > "$GAME_SRC/src/core/Version.lua"
  version_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
  grep -Eq "engine[[:space:]]*=[[:space:]]*\"$version_re\"" \
    "$GAME_SRC/src/core/Version.lua" \
    || fail "version stamp failed"
else
  say "version '$VERSION' is not X.Y.Z — shipping default engine (no stamp)"
fi

# Portable marker: saves + ROM cache live next to the game on the SD card.
: > "$GAME_SRC/portable.txt"

# --------------------------------------------------------------- love runtime
say "fetching LÖVE $LOVE_VERSION aarch64 runtime"
LOVE_BIN="$CACHE/love.aarch64"
LOVE_LIB="$CACHE/liblove-11.5.so"
LUAJIT_LIB="$CACHE/libluajit-5.1.so.2"
MODPLUG_LIB="$CACHE/libmodplug.so.1"
OGG_LIB="$CACHE/libogg.so.0"

download "$PM_RUNTIME_BASE/love.aarch64" "$LOVE_BIN"
download "$PM_RUNTIME_BASE/libs.aarch64/liblove-11.5.so" "$LOVE_LIB"
download "$PM_RUNTIME_BASE/libs.aarch64/libluajit-5.1.so.2" "$LUAJIT_LIB"
download "$PM_RUNTIME_BASE/libs.aarch64/libmodplug.so.1" "$MODPLUG_LIB"
download "$PM_RUNTIME_BASE/libs.aarch64/libogg.so.0" "$OGG_LIB"

# Sanity: love stub must be an aarch64 ELF.
file "$LOVE_BIN" | grep -qi 'aarch64\|ARM aarch64' \
  || fail "love.aarch64 does not look like an aarch64 ELF (got: $(file "$LOVE_BIN"))"

# --------------------------------------------------------------- port tree
say "assembling port package"
PORT_ROOT="$WORK/port"
rm -rf "$PORT_ROOT"
mkdir -p "$PORT_ROOT/$PORT_DIR_NAME/bin" \
         "$PORT_ROOT/$PORT_DIR_NAME/libs.aarch64" \
         "$PORT_ROOT/$PORT_DIR_NAME/licenses" \
         "$PORT_ROOT/$PORT_DIR_NAME/conf"

cp -R "$GAME_SRC" "$PORT_ROOT/$PORT_DIR_NAME/lovegame"
cp "$LOVE_BIN" "$PORT_ROOT/$PORT_DIR_NAME/bin/love.aarch64"
chmod +x "$PORT_ROOT/$PORT_DIR_NAME/bin/love.aarch64"
cp "$LOVE_LIB" "$LUAJIT_LIB" "$MODPLUG_LIB" "$OGG_LIB" \
  "$PORT_ROOT/$PORT_DIR_NAME/libs.aarch64/"

BRIDGE_LIB="liblibrashader_bridge.so"
BRIDGE_SRC="${SHADERFX_BRIDGE_LINUX_ARM64:-}"
if [ -z "$BRIDGE_SRC" ] && [ -f "$ROOT/dist/native/linux-arm64/$BRIDGE_LIB" ]; then
  BRIDGE_SRC="$ROOT/dist/native/linux-arm64/$BRIDGE_LIB"
fi
if [ -n "$BRIDGE_SRC" ] && [ -f "$BRIDGE_SRC" ]; then
  cp "$BRIDGE_SRC" "$PORT_ROOT/$PORT_DIR_NAME/libs.aarch64/$BRIDGE_LIB"
  say "bundled $BRIDGE_LIB for SHADER FX preset conversion"
elif [ "${SHADERFX_BRIDGE_REQUIRED:-}" = "1" ]; then
  fail "$BRIDGE_LIB not found: set SHADERFX_BRIDGE_LINUX_ARM64 or stage it at dist/native/linux-arm64/$BRIDGE_LIB"
else
  warn "$BRIDGE_LIB not found: this port can run converted presets but not CONVERT new ones"
fi

# Drop a short license pointer for the bundled LÖVE bits.
cat > "$PORT_ROOT/$PORT_DIR_NAME/licenses/LICENSE.love2d.txt" <<'EOF'
This port bundles the LÖVE 11.5 aarch64 runtime from PortMaster
(https://github.com/PortsMaster/PortMaster-GUI). LÖVE is zlib-licensed;
see https://love2d.org/ for full terms.
EOF

# --------------------------------------------------------------- launcher
# Resolve the game directory from the launcher so this works with both
# PortMaster-managed ports directories.
cat > "$PORT_ROOT/$LAUNCHER_NAME" <<'EOF'
#!/usr/bin/env bash
# gen1recomp-sbc — High-Performance Native ARM64 Handheld Port Launcher
# Compatible with TrimUI Brick, TrimUI Smart Pro, Anbernic (H700/RK3566), muOS, Knulli, ArkOS, Stock OS

export HOME="${HOME:-/root}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
SHDIR="$(cd "$(dirname "$0")" && pwd)"
GAMEDIR="$SHDIR/gen1recomp-sbc"
CONFDIR="$GAMEDIR/conf"

mkdir -p "$CONFDIR"
cd "$GAMEDIR" || exit 1

# Setup POSIX logging (compatible with busybox ash/dash/bash)
exec 1>"$GAMEDIR/log.txt" 2>&1

echo "========================================="
echo "gen1recomp Handheld Native ARM64 Launcher"
echo "SHDIR: $SHDIR"
echo "GAMEDIR: $GAMEDIR"
echo "Date: $(date 2>/dev/null || echo 'N/A')"
echo "========================================="

# PortMaster's control.txt wants a home tree under /mnt/SDCARD/Data; on a
# fresh card that tree may not exist yet and its mkdir fails noisily (log.txt:
# "mkdir: can't create directory '/mnt/SDCARD/Data/home'"). Pre-create it
# before any PortMaster script runs so the failure cannot occur.
if [ -d /mnt/SDCARD ]; then
  mkdir -p /mnt/SDCARD/Data/home 2>/dev/null || true
fi

# 1. Locate PortMaster control directory if present
controlfolder=""
if [ -d "/mnt/SDCARD/Apps/PortMaster/PortMaster" ]; then
  controlfolder="/mnt/SDCARD/Apps/PortMaster/PortMaster"
elif [ -d "/mnt/SDCARD/PortMaster/PortMaster" ]; then
  controlfolder="/mnt/SDCARD/PortMaster/PortMaster"
elif [ -d "/mnt/SDCARD/PortMaster" ]; then
  controlfolder="/mnt/SDCARD/PortMaster"
elif [ -d "/mnt/SDCARD/Apps/PortMaster" ]; then
  controlfolder="/mnt/SDCARD/Apps/PortMaster"
elif [ -d "/mnt/SDCARD/Emus/PORTS/PortMaster" ]; then
  controlfolder="/mnt/SDCARD/Emus/PORTS/PortMaster"
elif [ -d "/mnt/SDCARD/Emus/PORTMASTER" ]; then
  controlfolder="/mnt/SDCARD/Emus/PORTMASTER"
elif [ -d "/mnt/SDCARD/Roms/ports/PortMaster" ]; then
  controlfolder="/mnt/SDCARD/Roms/ports/PortMaster"
elif [ -d "/mnt/SDCARD/Roms/PORTS/PortMaster" ]; then
  controlfolder="/mnt/SDCARD/Roms/PORTS/PortMaster"
elif [ -d "/mnt/SDCARD/Ports/PortMaster" ]; then
  controlfolder="/mnt/SDCARD/Ports/PortMaster"
elif [ -d "$SHDIR/PortMaster" ]; then
  controlfolder="$SHDIR/PortMaster"
elif [ -d "/opt/system/Tools/PortMaster" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
elif [ -d "/mnt/SDCARD/Emus/tg5040/PORTS.pak/PortMaster" ]; then
  controlfolder="/mnt/SDCARD/Emus/tg5040/PORTS.pak/PortMaster"
elif [ -d "/roms/PORTS/PortMaster" ]; then
  controlfolder="/roms/PORTS/PortMaster"
elif [ -d "/roms/ports/PortMaster" ]; then
  controlfolder="/roms/ports/PortMaster"
fi

if [ -n "$controlfolder" ] && [ -f "$controlfolder/control.txt" ]; then
  echo "Found PortMaster control folder: $controlfolder"
  # shellcheck disable=SC1090
  . "$controlfolder/control.txt"
  if type get_controls >/dev/null 2>&1; then
    get_controls
  fi
  if [ -n "${CFW_NAME:-}" ] && [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ]; then
    # shellcheck disable=SC1090
    . "${controlfolder}/mod_${CFW_NAME}.txt"
  fi
else
  echo "PortMaster control.txt not found, using standalone handheld configuration."
fi

# 2. CPU governor
# Pinning every core to performance keeps handhelds at peak clock even when gameplay
# uses only a fraction of CPU. Schedutil is the default; set POKEPORT_CPU_GOVERNOR=performance
# only for profiling or devices needing an extra boost.
CPU_GOVERNOR_OVERRIDE="${POKEPORT_CPU_GOVERNOR:-schedutil}"
CPU_GOVERNOR_STATE=""

write_cpu_governor() {
  local governor_path="$1"
  local governor="$2"
  if [ -n "${ESUDO:-}" ]; then
    printf '%s\n' "$governor" | $ESUDO tee "$governor_path" >/dev/null 2>&1 || true
  else
    printf '%s\n' "$governor" > "$governor_path" 2>/dev/null || true
  fi
}

restore_cpu_governors() {
  [ -n "$CPU_GOVERNOR_STATE" ] || return 0
  while IFS='|' read -r governor_path governor; do
    [ -n "$governor_path" ] || continue
    write_cpu_governor "$governor_path" "$governor"
  done <<< "$CPU_GOVERNOR_STATE"
  CPU_GOVERNOR_STATE=""
}

apply_cpu_governors() {
  [ -n "$CPU_GOVERNOR_OVERRIDE" ] || return 0
  for governor_path in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$governor_path" ] || continue
    old_governor=$(cat "$governor_path" 2>/dev/null || true)
    [ -n "$old_governor" ] || continue
    CPU_GOVERNOR_STATE="${CPU_GOVERNOR_STATE}${governor_path}|${old_governor}"$'\n'
    write_cpu_governor "$governor_path" "$CPU_GOVERNOR_OVERRIDE"
  done
  echo "CPU governor requested: $CPU_GOVERNOR_OVERRIDE"
}

# 3. Environment & Low-Level OS Tuning
export POKEPORT_HANDHELD=1
export HANDHELD=1
export PORTMASTER=1
# Release-target marker for the self-updater: a full-package fallback here must
# offer gen1recomp-<v>-sbc-portmaster.zip, never a desktop AppImage.
export POKEPORT_PORTMASTER=1
export NINTENDO_LAYOUT=1
export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"
export LD_LIBRARY_PATH="$GAMEDIR/libs.aarch64:$GAMEDIR/libs:/usr/trimui/lib:/mnt/SDCARD/System/lib:/usr/lib64:/usr/lib:${LD_LIBRARY_PATH:-}"
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-}"
export LOVE_GRAPHICS_USE_OPENGLES="${LOVE_GRAPHICS_USE_OPENGLES:-1}"

# Audio buffer size
export SDL_AUDIO_SAMPLES=1024

# Chip-synth sample rate. The audio worker is the dominant CPU cost while
# idle (music keeps playing when the screen is static), and synthesis cost
# scales linearly with the rate. 22050 Hz roughly halves audio CPU vs the
# 44100 Hz default; the Game Boy's own DAC content is well below 11 kHz, so
# the handheld speaker sounds effectively identical.
export POKEPORT_AUDIO_RATE=22050

# Idle-power render governor: after IDLE_AFTER seconds with no input on static
# screens, presentation drops to IDLE_FPS (game logic and audio stay full speed).
export POKEPORT_IDLE_AFTER=10
export POKEPORT_IDLE_FPS=6

# Memory allocator tuning (limit arena fragmentation on 1GB RAM SBCs)
export MALLOC_ARENA_MAX=2
export MALLOC_TRIM_THRESHOLD_=131072

# Process scheduling & CPU affinity
renice -n -5 -p $$ >/dev/null 2>&1 || true
taskset -cp 0-3 $$ >/dev/null 2>&1 || true
ionice -c 3 -p $$ >/dev/null 2>&1 || true

# Ensure executable permissions
if [ -n "${ESUDO:-}" ]; then
  $ESUDO chmod a+x ./bin/love.aarch64 2>/dev/null || true
  $ESUDO chmod 666 /dev/uinput 2>/dev/null || true
else
  chmod a+x ./bin/love.aarch64 2>/dev/null || true
fi

# 4. Platform helper
if type pm_platform_helper >/dev/null 2>&1; then
  echo "Running pm_platform_helper..."
  pm_platform_helper "$GAMEDIR/bin/love.aarch64"
fi

# Apply after PortMaster's helper: some firmware helpers reset cpufreq policy
# while preparing the runtime. The saved values are restored on exit.
apply_cpu_governors
trap restore_cpu_governors EXIT

# PulseAudio runtime: PortMaster's helper points it at conf/pulse on the vfat
# SD card, where the runtime symlink fails ("Operation not permitted" -- vfat
# has no symlinks). Force the runtime onto tmpfs (real dirs, no symlinks).
export PULSE_RUNTIME_PATH="/tmp/pulse-$PPID"
mkdir -p "$PULSE_RUNTIME_PATH" 2>/dev/null || true

echo "Launching ./bin/love.aarch64 $GAMEDIR/lovegame..."
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

# 5. Launch
./bin/love.aarch64 "$GAMEDIR/lovegame"
EXIT_CODE=$?

echo "Game exited with code: $EXIT_CODE"

# 6. Cleanup
restore_cpu_governors

if type pm_finish >/dev/null 2>&1; then
  pm_finish
fi

exit $EXIT_CODE
EOF
chmod +x "$PORT_ROOT/$LAUNCHER_NAME"

# --------------------------------------------------------------- metadata
cat > "$PORT_ROOT/port.json" <<EOF
{
  "version": 2,
  "name": "gen1recomp-sbc.zip",
  "items": [
    "$LAUNCHER_NAME",
    "$PORT_DIR_NAME"
  ],
  "items_opt": null,
  "attr": {
    "title": "gen1recomp-sbc",
    "desc": "Native LÖVE2D recreation of Pokemon Red and Blue. Supply your own legal US Red or Blue ROM.",
    "source": "https://github.com/bryanthaboi/gen1recomp/releases/tag/$SOURCE_TAG",
    "inst": "Requires a 64-bit Linux ARM handheld with PortMaster. Copy a canonical US Red or Blue .gb into gen1recomp-sbc/lovegame/, then launch and press Choose ROM.",
    "genres": ["adventure", "rpg"],
    "porter": ["gen1recomp-sbc"],
    "image": {},
    "rtr": true,
    "runtime": null,
    "reqs": [],
    "arch": ["aarch64"]
  }
}
EOF

cat > "$PORT_ROOT/gameinfo.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<gameList>
  <game>
    <path>./$LAUNCHER_NAME</path>
    <name>gen1recomp-sbc</name>
    <desc>Native LÖVE2D recreation of Pokemon Red and Blue. Requires your own legal US Red or Blue ROM.</desc>
    <releasedate>20250101T000000</releasedate>
    <developer>the bois club</developer>
    <publisher>the bois club</publisher>
    <genre>RPG</genre>
  </game>
</gameList>
EOF

cat > "$PORT_ROOT/README.md" <<'EOF'
## gen1recomp-sbc (Linux ARM SBC / PortMaster)

Native LÖVE 11.5 aarch64 PortMaster port of gen1recomp for compatible Linux ARM SBC handhelds, including H700-class devices. This pack was built from source release **__SOURCE_TAG__**.

### Install

1. Install PortMaster for your handheld firmware.
2. Unzip so `gen1recomp-sbc.sh` and the `gen1recomp-sbc/` folder are siblings in the device's PortMaster ports directory.
3. Copy a legal US Pokémon Red or Blue `.gb` into `gen1recomp-sbc/lovegame/`.
4. Refresh the launcher and launch **gen1recomp-sbc** from Ports.

### Controls

| Input | Action |
|--|--|
| D-pad | Move cursor |
| A | Click |
| L1 / R1 | Switch tabs |
| Start / Select | Play or choose ROM |

Controls use the normal PortMaster / SDL pad map. Device-specific power/suspend behavior is supplied by the firmware and PortMaster runtime.

### First run

Put the `.gb` in `lovegame/`, then press **Choose ROM**. After import, the ROM-derived cache and saves stay beside the game (`portable.txt`).

### Thanks

LÖVE runtime binaries from [PortMaster](https://portmaster.games/). PortMaster device support and runtime integration are maintained by the PortMaster team.
EOF
sed -i.bak "s/__SOURCE_TAG__/$SOURCE_TAG/g" "$PORT_ROOT/README.md"
rm -f "$PORT_ROOT/README.md.bak"

# --------------------------------------------------------------- zip
ZIP_OUT="$DIST/$APP_NAME-$ARTIFACT_SUFFIX.zip"
rm -f "$ZIP_OUT"
say "packing $ZIP_OUT"
(cd "$PORT_ROOT" && zip -q -9 -r "$ZIP_OUT" \
  "$LAUNCHER_NAME" "$PORT_DIR_NAME" port.json gameinfo.xml README.md)

say "done."
say "artifact: $ZIP_OUT ($(du -h "$ZIP_OUT" | cut -f1))"
say "copy into the device PortMaster ports folder, then drop your .gb into gen1recomp-sbc/lovegame/"
