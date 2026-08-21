#!/usr/bin/env bash
# Build a PortMaster-style aarch64 port of gen1recomp for Anbernic RG34XXSP
# on Stock OS 64-bit MOD (H700; cbepx-me StockOS MOD / official V1.0.6 base
# + PortMaster).
#
# The stock Anbernic firmware resolves ports relative to the launch script
# (roms/PORTS/...), not PortMaster's /$directory/ports/... path. This pack
# uses SHDIR-relative paths and bundles the LÖVE 11.5 aarch64 runtime so the
# device does not need a separate love_11.5 runtime download on first launch.
#
# Usage:
#   ./build-rg34xxsp.sh [--version X.Y.Z]
#
# Output:
#   dist/rg34xxsp/gen1recomp-rg34xxsp-stockos64-mod.zip
#
# Install on device:
#   1. Flash / run Stock OS 64-bit MOD with PortMaster installed.
#   2. Unzip into the SD card's roms/PORTS/ folder so you have:
#        roms/PORTS/Gen1recomp.sh
#        roms/PORTS/gen1recomp/...
#   3. Copy a legal US Red or Blue .gb into roms/PORTS/gen1recomp/lovegame/
#   4. Launch "Gen1recomp" from the Ports list; press Choose ROM (scans that
#      folder when zenity is missing).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
HERE="$ROOT/.bazinga"
CACHE="$HERE/cache/rg34xxsp"
WORK="$HERE/work/rg34xxsp"
DIST="$ROOT/dist/rg34xxsp"

APP_NAME="gen1recomp"
# Artifact suffix matches the CFW this port targets (Anbernic H700 Stock OS
# 64-bit MOD for RG34XXSP). Release uploads stage it as
# gen1recomp-<ver>-rg34xxsp-stockos64-mod.zip.
ARTIFACT_SUFFIX="rg34xxsp-stockos64-mod"
PORT_DIR_NAME="gen1recomp"
LAUNCHER_NAME="Gen1recomp.sh"
LOVE_VERSION="11.5"
VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"

# Official PortMaster LÖVE 11.5 aarch64 runtime (small love stub + liblove).
PM_RUNTIME_BASE="https://raw.githubusercontent.com/PortsMaster/PortMaster-GUI/main/PortMaster/runtimes/love_${LOVE_VERSION}"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
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

# --------------------------------------------------------------- game tree
# Unpacked directory (not a .love zip) so the player can drop a .gb next to
# main.lua and RomImporter can scan it without zenity/kdialog.
say "staging lovegame/"
GAME_SRC="$WORK/lovegame"
rm -rf "$GAME_SRC"
mkdir -p "$GAME_SRC"

# Same payload as scripts/build.sh's game.love — never ship ROM-derived cache.
# tools/save-editor is part of that payload: the launcher's Edit button on a
# save row opens it in-process (main.lua).
(cd "$ROOT" && zip -q -9 -r "$WORK/game-payload.zip" \
  main.lua conf.lua src libs data assets tools/save-editor \
  tools/rom_manifest.json tools/rom_manifest_blue.json \
  tools/rom_manifest_yellow.json tools/rom_manifest_gold.json \
  tools/rom_manifest_silver.json \
  -x '*.DS_Store' 'data/generated/*' 'assets/generated/*')
payload_list="$(unzip -Z1 "$WORK/game-payload.zip")"
printf '%s\n' "$payload_list" \
  | grep -Eq '^(data|assets)/generated/[^/]+|^(data|assets)/generated/.+/' \
  && fail "payload unexpectedly contains generated ROM data"
printf '%s\n' "$payload_list" | grep -qxF "tools/rom_manifest_gold.json" \
  || fail "payload is missing tools/rom_manifest_gold.json"
printf '%s\n' "$payload_list" | grep -qxF "tools/rom_manifest_silver.json" \
  || fail "payload is missing tools/rom_manifest_silver.json"
unzip -q "$WORK/game-payload.zip" -d "$GAME_SRC"
rm -f "$WORK/game-payload.zip"

# Stamp release version into the staged tree only (never the working tree).
if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  say "stamping engine version $VERSION"
  sed -E "s/(engine[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1$VERSION\2/" \
    "$ROOT/src/core/Version.lua" > "$GAME_SRC/src/core/Version.lua"
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

# Drop a short license pointer for the bundled LÖVE bits.
cat > "$PORT_ROOT/$PORT_DIR_NAME/licenses/LICENSE.love2d.txt" <<'EOF'
This port bundles the LÖVE 11.5 aarch64 runtime from PortMaster
(https://github.com/PortsMaster/PortMaster-GUI). LÖVE is zlib-licensed;
see https://love2d.org/ for full terms.
EOF

# --------------------------------------------------------------- launcher
# Stock OS fix: resolve GAMEDIR from this script's directory (SHDIR), not
# PortMaster's $directory variable — Anbernic uses roms/PORTS with different
# casing and mount points (mmc / sdcard / TF1 / TF2).
cat > "$PORT_ROOT/$LAUNCHER_NAME" <<'EOF'
#!/bin/bash
# gen1recomp — Anbernic RG34XXSP stock OS / PortMaster launcher
# Uses SHDIR-relative paths so stock firmware finds the game folder.

export HOME="${HOME:-/root}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
elif [ -d "/mnt/mmc/Roms/PORTS/PortMaster" ]; then
  controlfolder="/mnt/mmc/Roms/PORTS/PortMaster"
elif [ -d "/mnt/sdcard/Roms/PORTS/PortMaster" ]; then
  controlfolder="/mnt/sdcard/Roms/PORTS/PortMaster"
elif [ -d "/roms/ports/PortMaster" ]; then
  controlfolder="/roms/ports/PortMaster"
else
  controlfolder="/roms/PORTS/PortMaster"
fi

SHDIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090
source "$controlfolder/control.txt"
get_controls
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

GAMEDIR="$SHDIR/gen1recomp"
# Anbernic stock keeps the launcher and the game folder side by side, so the
# SHDIR-relative path above is correct there and is tried first.
#
# Other firmwares (muOS, and PortMaster's layout on several devices) keep
# launcher scripts and port data in SEPARATE trees -- scripts under roms/ports,
# data under ports -- so the sibling folder holds no game.
#
# Probe for the BINARY, not the directory: on a split layout this script has
# usually already created "$SHDIR/gen1recomp/conf" and log.txt on an earlier
# failed run (see mkdir/tee below), so an existence test matches a decoy of our
# own making. Stock is unaffected -- its sibling holds the real binary and wins
# on the first test.
if [ ! -f "$GAMEDIR/bin/love.aarch64" ]; then
  for candidate in "/$directory/ports/gen1recomp" \
                   "/mnt/sdcard/ports/gen1recomp" \
                   "/mnt/mmc/ports/gen1recomp" \
                   "/roms/ports/gen1recomp"; do
    if [ -f "$candidate/bin/love.aarch64" ]; then GAMEDIR="$candidate"; break; fi
  done
fi
CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR"

cd "$GAMEDIR" || exit 1
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

export XDG_DATA_HOME="$CONFDIR"
export XDG_CONFIG_HOME="$CONFDIR"
export LD_LIBRARY_PATH="$GAMEDIR/libs.aarch64:${LD_LIBRARY_PATH:-}"
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-}"
# Mali / H700: prefer GLES where available
export LOVE_GRAPHICS_USE_OPENGLES="${LOVE_GRAPHICS_USE_OPENGLES:-1}"
# Same GPU class as a phone, but getOS() here says "Linux", so the Android
# gate (issue #136) would not fire on its own: refuse GBC FX explicitly.
# Hides the OPTIONS row, pins the level to OFF, and heals a level already
# persisted in options.lua.
export POKEPORT_GBCFX="${POKEPORT_GBCFX:-0}"

$ESUDO chmod a+x ./bin/love.aarch64 2>/dev/null || chmod a+x ./bin/love.aarch64
$ESUDO chmod 666 /dev/uinput 2>/dev/null || true

if [ -n "${GPTOKEYB:-}" ]; then
  $GPTOKEYB "love.aarch64" &
fi
if type pm_platform_helper >/dev/null 2>&1; then
  pm_platform_helper "$GAMEDIR/bin/love.aarch64"
fi

./bin/love.aarch64 "$GAMEDIR/lovegame"

if type pm_finish >/dev/null 2>&1; then
  pm_finish
else
  if [ -n "${ESUDO:-}" ]; then
    $ESUDO kill -9 $(pidof gptokeyb) 2>/dev/null || true
  else
    kill -9 $(pidof gptokeyb) 2>/dev/null || true
  fi
fi
EOF
chmod +x "$PORT_ROOT/$LAUNCHER_NAME"

# --------------------------------------------------------------- metadata
cat > "$PORT_ROOT/port.json" <<EOF
{
  "version": 2,
  "name": "gen1recomp.zip",
  "items": [
    "$LAUNCHER_NAME",
    "$PORT_DIR_NAME"
  ],
  "items_opt": null,
  "attr": {
    "title": "gen1recomp",
    "desc": "Native LÖVE2D recreation of Pokemon Red and Blue. Supply your own legal US Red or Blue ROM.",
    "inst": "Requires Anbernic RG34XXSP Stock OS 64-bit MOD with PortMaster. Copy a canonical US Red or Blue .gb into gen1recomp/lovegame/, then launch and press Choose ROM.",
    "genres": ["adventure", "rpg"],
    "porter": ["gen1recomp"],
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
    <name>gen1recomp</name>
    <desc>Native LÖVE2D recreation of Pokemon Red and Blue. Requires your own legal US Red or Blue ROM.</desc>
    <releasedate>20250101T000000</releasedate>
    <developer>the bois club</developer>
    <publisher>the bois club</publisher>
    <genre>RPG</genre>
  </game>
</gameList>
EOF

cat > "$PORT_ROOT/README.md" <<'EOF'
## gen1recomp (RG34XXSP / Stock OS 64-bit MOD)

Native LÖVE 11.5 port of gen1recomp for Anbernic RG34XXSP on
**Stock OS 64-bit MOD** (H700, PortMaster).

### Install

1. Use **Stock OS 64-bit MOD** with PortMaster installed (TF1).
2. Unzip so `Gen1recomp.sh` and the `gen1recomp/` folder sit in `roms/PORTS/`.
3. Copy a legal US Pokemon Red or Blue `.gb` into `gen1recomp/lovegame/`.
4. Refresh Ports / restart EmulationStation and launch **Gen1recomp**.

### Controls (launcher)

| Input | Action |
|--|--|
| D-pad / left stick | Move cursor |
| A | Click |
| L1 / R1 | Switch tabs |
| Right stick | Scroll lists |
| Start / Select | Play or Choose ROM |

In-game controls use the normal PortMaster / SDL pad map (rebind under OPTIONS → CONTROLS).

### Display options

GBC FX is disabled on this device (the H700's Mali GPU compiles that present
pass and then shows a black frame), so the OPTIONS row is hidden. COLORS,
TILT, ZOOM, VOID FILL and MAX FPS all work. To try it anyway, launch with
`POKEPORT_GBCFX=1`.

### First run

Stock OS has no zenity file picker. Put the `.gb` in `lovegame/`, then press
**Choose ROM** — the game scans that folder. After import, the ROM-derived
cache and saves stay beside the game (`portable.txt`).

Canonical SHA-1 (1 MiB US carts only):

- Red: `ea9bcae617fdf159b045185467ae58b2e4a48b9a`
- Blue: `d7037c83e1ae5b39bde3c30787637ba1d4c48ce2`

### Thanks

LÖVE runtime binaries from [PortMaster](https://portmaster.games/).
Stock OS 64-bit MOD: [cbepx-me](https://github.com/cbepx-me/Anbernic-H700-RG-xx-StockOS-Modification).
EOF

# --------------------------------------------------------------- zip
ZIP_OUT="$DIST/$APP_NAME-$ARTIFACT_SUFFIX.zip"
rm -f "$ZIP_OUT" "$DIST/$APP_NAME-rg34xxsp.zip"
say "packing $ZIP_OUT"
(cd "$PORT_ROOT" && zip -q -9 -r "$ZIP_OUT" \
  "$LAUNCHER_NAME" "$PORT_DIR_NAME" port.json gameinfo.xml README.md)

say "done."
say "artifact: $ZIP_OUT ($(du -h "$ZIP_OUT" | cut -f1))"
say "copy onto the RG34XXSP SD card under roms/PORTS/ (Stock OS 64-bit MOD), then drop your .gb into gen1recomp/lovegame/"
