#!/usr/bin/env bash
# Packages the LÖVE2D Pokémon Red port into distributable macOS, Windows,
# and Linux builds. Runs entirely on macOS (no cross-compiling needed,
# the Windows and Linux builds reuse LÖVE's prebuilt win64 / AppImage
# binaries, fusing our game.love onto them the same way love.exe does).
#
# Usage: scripts/build.sh [mac|win|linux|android|ios|all] [--version X.Y.Z] [--identity "Developer ID Application: ..."]
#                          [--notary-profile NAME] [--no-notarize]
#                          [--game-love PATH]  # fuse a prebuilt payload (scripts/pack_love.sh) instead of packing one
#                          [--release]   # ios only: release config instead of debug
#
# Output: dist/mac/gen1recomp-macos.zip
#         dist/win/gen1recomp-win64.zip
#         dist/linux/gen1recomp-linux.zip (fused x86_64 AppImage)
#         dist/android/debug/*.apk (full gradle output stays under
#           mobile/android/app/build/outputs/apk/embedNoRecord/)
#         dist/ios/<Config>-<sdk>/gen1recomp++.app (full xcodebuild output stays
#           under mobile/ios/build/Build/Products/)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$ROOT/.bazinga"
CACHE="$HERE/cache"
WORK="$HERE/work"
DIST="$ROOT/dist"
ENTITLEMENTS="$ROOT/scripts/macos-entitlements.plist"

APP_NAME="gen1recomp"
BUNDLE_ID="com.theboisclub.pokemonred"
LOVE_VERSION="11.5"
VERSION="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo dev)"
VERSION_EXPLICIT=false
IDENTITY=""
TARGET="all"
NOTARY_PROFILE="notary-profile"
NOTARIZE=true
IOS_RELEASE=false
IOS_IPA=false
GAME_LOVE_IN=""

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    mac|win|linux|android|ios|all) TARGET="$1" ;;
    --version) VERSION="$2"; VERSION_EXPLICIT=true; shift ;;
    --identity) IDENTITY="$2"; shift ;;
    --notary-profile) NOTARY_PROFILE="$2"; shift ;;
    --no-notarize) NOTARIZE=false ;;
    --game-love) GAME_LOVE_IN="${2:?--game-love needs a path}"; shift ;;
    --release) IOS_RELEASE=true ;;
    --ipa) IOS_IPA=true ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift
done

mkdir -p "$CACHE" "$WORK" "$DIST/mac" "$DIST/win" "$DIST/linux"

# --------------------------------------------------------------- game.love
# tools/save-editor is part of the shipped app, not a dev-only script: the
# launcher's Edit button on a save row opens it in-process (main.lua), and
# `--editor` / POKEPORT_EDITOR=1 opens it standalone.  It is required through
# love.filesystem's require path, so it has to live inside the archive.
LOVE_FILE="$WORK/game.love"
rm -f "$LOVE_FILE"
if [ -n "$GAME_LOVE_IN" ]; then
  [ -f "$GAME_LOVE_IN" ] || fail "--game-love: no such file: $GAME_LOVE_IN"
  say "using prebuilt payload: $GAME_LOVE_IN"
  cp "$GAME_LOVE_IN" "$LOVE_FILE"
else
  say "packing game.love"
  # The launcher UI kit lives at src/ui/kit (inside src/, packed wholesale);
  # the vendored libs/flexlove tree it replaced is gone.
  (cd "$ROOT" && zip -q -9 -r "$LOVE_FILE" \
    main.lua conf.lua src data assets tools/save-editor \
    tools/rom_manifest.json tools/rom_manifest_blue.json \
    tools/rom_manifest_yellow.json tools/rom_manifest_gold.json \
    tools/rom_manifest_silver.json \
    -x '*.DS_Store' 'data/generated/*' 'assets/generated/*')
fi
# Materialize the listing once and grep the file: piping unzip straight into
# grep -q under `set -o pipefail` SIGPIPEs unzip when grep exits early on a
# match, and the pipeline's failure reads as "missing <file>" for whichever
# entry happened to match first (see the same fix in pack_love.sh).
LOVE_LISTING="$WORK/love-listing.txt"
unzip -Z1 "$LOVE_FILE" > "$LOVE_LISTING"
if grep -Eq '^(data|assets)/generated/[^/]+|^(data|assets)/generated/.+/' "$LOVE_LISTING"; then
  fail "game.love unexpectedly contains generated ROM data"
fi
# The editor is only reachable if its entry point and both module directories
# made it in, and every version's import manifest has to ship or that game's
# ROM import fails in the built app (dev reads them off the source tree, so
# the miss only ever shows up in a build -- the Yellow manifest shipped this
# way once).
for required in tools/save-editor/App.lua tools/save-editor/Kit.lua \
                tools/save-editor/panels/Party.lua \
                src/ui/kit/Kit.lua \
                tools/rom_manifest.json tools/rom_manifest_blue.json \
                tools/rom_manifest_yellow.json tools/rom_manifest_gold.json \
                tools/rom_manifest_silver.json; do
  grep -qxF "$required" "$LOVE_LISTING" \
    || fail "game.love is missing $required"
done
say "game.love: $(du -h "$LOVE_FILE" | cut -f1)"

# ------------------------------------------------------- stamp release version
# The working tree ships Version.lua with engine "0.0.0-dev"; the real release
# number only ever lives inside the packed archive. When --version is a strict
# X.Y.Z, patch a copy of Version.lua (engine set to that number) under a staging
# dir and replace the entry inside game.love in place -- never the source tree.
# Short-hash / "dev" builds are left with the "-dev" default so they cannot be
# mistaken for a release. The stamp is then read back out of the archive and the
# build fails if it did not take.
if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  if [ -n "$GAME_LOVE_IN" ]; then
    version_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
    unzip -p "$LOVE_FILE" src/core/Version.lua \
      | grep -Eq "engine[[:space:]]*=[[:space:]]*\"$version_re\"" \
      || fail "prebuilt payload does not report engine $VERSION (pack it with pack_love.sh --version $VERSION)"
    say "prebuilt payload already stamped: $VERSION"
  else
    say "stamping engine version $VERSION into game.love"
    stamp_dir="$WORK/stamp"
    rm -rf "$stamp_dir"
    mkdir -p "$stamp_dir/src/core"
    sed -E "s/(engine[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\1$VERSION\2/" \
      "$ROOT/src/core/Version.lua" > "$stamp_dir/src/core/Version.lua"
    (cd "$stamp_dir" && zip -q "$LOVE_FILE" src/core/Version.lua)
    version_re="$(printf '%s' "$VERSION" | sed 's/\./\\./g')"
    unzip -p "$LOVE_FILE" src/core/Version.lua \
      | grep -Eq "engine[[:space:]]*=[[:space:]]*\"$version_re\"" \
      || fail "version stamp failed: game.love does not report engine $VERSION"
    say "stamped engine version: $VERSION"
  fi
else
  say "version '$VERSION' is not X.Y.Z,  shipping default engine (no stamp)"
fi

# --------------------------------------------------------------- app icon
# One source of truth for every platform's launcher icon; iOS resizes the
# same file in scripts/build_ios.sh (apply_ios_icon) and the Android res/
# drawables are generated from it too.
ICON_SRC="$ROOT/assets/logo/gen1recomp_cover.png"

# pipx installs peresed (Windows exe icon patcher) here, off the default PATH.
PATH="$PATH:$HOME/.local/bin"

make_icns() { # $1 = output .icns path
  [ -f "$ICON_SRC" ] || fail "missing icon source: $ICON_SRC"
  local iconset="$WORK/GameIcon.iconset" size scaled
  rm -rf "$iconset"; mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    scaled=$((size * 2))
    sips -z "$scaled" "$scaled" "$ICON_SRC" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$1"
}

make_ico() { # $1 = output .ico path
  [ -f "$ICON_SRC" ] || fail "missing icon source: $ICON_SRC"
  magick "$ICON_SRC" -define icon:auto-resize=256,128,64,48,32,16 "$1"
}

# --------------------------------------------------------------- macOS
build_mac() {
  say "building macOS app"
  local love_app="${LOVE_APP:-/Applications/love.app}"
  [ -d "$love_app" ] || fail "LÖVE.app not found at $love_app (install it or set LOVE_APP=/path/to/love.app)"

  local out_app="$WORK/$APP_NAME.app"
  rm -rf "$out_app"
  cp -R "$love_app" "$out_app"

  # drop any bundled placeholder .love and fuse ours in
  find "$out_app/Contents/Resources" -maxdepth 1 -name '*.love' -delete
  cp "$LOVE_FILE" "$out_app/Contents/Resources/game.love"

  local plist="$out_app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$plist"

  # Brand the app icon. LÖVE.app resolves its icon through CFBundleIconName ->
  # Assets.car first, so overwriting the loose .icns files alone changes
  # nothing; the compiled asset catalog has to go and the plist has to fall
  # back to CFBundleIconFile.
  local icns="$ROOT/assets/icon.icns"
  if [ ! -f "$icns" ]; then
    icns="$WORK/GameIcon.icns"
    make_icns "$icns"
  fi
  cp "$icns" "$out_app/Contents/Resources/GameIcon.icns"
  cp "$icns" "$out_app/Contents/Resources/OS X AppIcon.icns"
  rm -f "$out_app/Contents/Resources/Assets.car"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile OS X AppIcon" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string 'OS X AppIcon'" "$plist"

  local id="$IDENTITY"
  if [ -z "$id" ]; then
    id="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed -E 's/^[^"]*"(.*)"$/\1/' || true)"
  fi
  if [ -n "$id" ]; then
    say "codesigning with: $id"
    codesign --deep --force --options runtime --timestamp \
      --entitlements "$ENTITLEMENTS" --sign "$id" "$out_app"
    codesign --verify --deep --strict --verbose=2 "$out_app"
  else
    warn "no 'Developer ID Application' identity found,  shipping unsigned."
    warn "install your cert in Keychain Access, then re-run (or pass --identity \"Developer ID Application: Name (TEAMID)\")."
    warn "unsigned builds will be Gatekeeper-blocked on other Macs; notarize with 'xcrun notarytool submit' once signed."
    NOTARIZE=false
  fi

  if [ "$NOTARIZE" = true ]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
      warn "keychain profile '$NOTARY_PROFILE' not found/working,  skipping notarization."
      warn "set it up with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id ... --team-id ... --password ..."
    else
      local notarize_zip="$WORK/$APP_NAME-notarize.zip"
      rm -f "$notarize_zip"
      (cd "$WORK" && ditto -c -k --keepParent "$APP_NAME.app" "$notarize_zip")
      say "submitting to Apple notary service (this can take a few minutes)"
      xcrun notarytool submit "$notarize_zip" --keychain-profile "$NOTARY_PROFILE" --wait
      say "stapling notarization ticket"
      xcrun stapler staple "$out_app"
      rm -f "$notarize_zip"
    fi
  fi

  local zip_out="$DIST/mac/$APP_NAME-macos.zip"
  rm -f "$zip_out"
  (cd "$WORK" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$zip_out")
  say "macOS build: $zip_out"
}

# --------------------------------------------------------------- Windows
build_win() {
  say "building Windows (win64) app"
  local zip_name="love-$LOVE_VERSION-win64.zip"
  local love_zip="$CACHE/$zip_name"
  # A cache hit only checks existence, not validity -- a prior run truncated
  # by a network drop mid-download (curl still leaves the partial file if
  # the exit code slips through) would otherwise be reused forever.
  if [ -f "$love_zip" ] && ! unzip -tqq "$love_zip" >/dev/null 2>&1; then
    warn "cached $zip_name is not a valid zip,  removing and re-downloading"
    rm -f "$love_zip"
  fi
  if [ ! -f "$love_zip" ]; then
    say "downloading LÖVE $LOVE_VERSION win64 binaries"
    curl -fL --progress-bar \
      "https://github.com/love2d/love/releases/download/$LOVE_VERSION/$zip_name" \
      -o "$love_zip" || fail "download failed,  check LOVE_VERSION or your network"
    unzip -tqq "$love_zip" >/dev/null 2>&1 \
      || fail "downloaded $zip_name is not a valid zip (truncated download?)"
  fi

  local extract_dir="$WORK/love-win64"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  unzip -q "$love_zip" -d "$extract_dir"
  local love_dir
  love_dir="$(find "$extract_dir" -maxdepth 1 -mindepth 1 -type d | head -1)"

  local out_dir="$WORK/$APP_NAME-win64"
  rm -rf "$out_dir"
  mkdir -p "$out_dir"
  cp "$love_dir"/*.dll "$out_dir"/
  cp "$love_dir"/license.txt "$out_dir"/ 2>/dev/null || true

  # Native AOT TLS dialer for outbound wss:// (e.g. Archipelago hosted rooms).
  # Release CI builds this on windows-2022 (Native AOT can't cross-compile
  # win-x64 from the Mac runner) and either exports GEN1TLS_DLL or drops the
  # file at dist/native/win-x64/gen1tls.dll before calling build.sh.
  local tls_dll="${GEN1TLS_DLL:-}"
  if [ -z "$tls_dll" ] && [ -f "$DIST/native/win-x64/gen1tls.dll" ]; then
    tls_dll="$DIST/native/win-x64/gen1tls.dll"
  fi
  if [ -n "$tls_dll" ] && [ -f "$tls_dll" ]; then
    cp "$tls_dll" "$out_dir/gen1tls.dll"
    say "bundled gen1tls.dll for Windows TLS (wss://)"
  else
    warn "gen1tls.dll not found — Windows zip will not support wss:// (set GEN1TLS_DLL or build native/tls_dial)"
  fi

  # The exe's icon lives in love.exe's PE resources, so it must be patched
  # BEFORE the .love is appended: peresed rewrites the whole file and would
  # drop the fused bytes. peresed (pipx install pe_tools) has no .ico input,
  # only raw --set-resource, so split the .ico into RT_ICON blobs plus a
  # GRPICONDIR that reuses love.exe's existing resource ids (1..N, lang 1033).
  local ico="$WORK/$APP_NAME.ico"
  make_ico "$ico"
  if command -v peresed >/dev/null 2>&1; then
    local ico_parts="$WORK/ico-parts"
    rm -rf "$ico_parts"; mkdir -p "$ico_parts"
    python3 - "$ico" "$ico_parts" <<'PY'
import struct, sys
data = open(sys.argv[1], "rb").read()
outdir = sys.argv[2]
count = struct.unpack_from("<H", data, 4)[0]
group = struct.pack("<HHH", 0, 1, count)
for i in range(count):
    w, h, colors, res, planes, bpp, size, off = struct.unpack_from("<BBBBHHII", data, 6 + 16 * i)
    open("%s/icon_%d.bin" % (outdir, i + 1), "wb").write(data[off:off + size])
    group += struct.pack("<BBBBHHIH", w, h, colors, res, planes, bpp, size, i + 1)
open(outdir + "/group.bin", "wb").write(group)
print(count)
PY
    local n_icons args=()
    n_icons=$(ls "$ico_parts" | grep -c '^icon_')
    for i in $(seq 1 "$n_icons"); do
      args+=(-R RT_ICON "#$i" 1033 "$ico_parts/icon_$i.bin")
    done
    args+=(-R RT_GROUP_ICON "#1" 1033 "$ico_parts/group.bin")
    local exe_branded="$WORK/love-branded.exe"
    cp "$love_dir/love.exe" "$exe_branded"
    if peresed "${args[@]}" "$exe_branded" >/dev/null; then
      cat "$exe_branded" "$LOVE_FILE" > "$out_dir/$APP_NAME.exe"
    else
      warn "peresed failed to patch the exe icon,  shipping stock LÖVE icon"
      cat "$love_dir/love.exe" "$LOVE_FILE" > "$out_dir/$APP_NAME.exe"
    fi
  else
    warn "peresed not found (pipx install pe_tools),  shipping stock LÖVE exe icon"
    cat "$love_dir/love.exe" "$LOVE_FILE" > "$out_dir/$APP_NAME.exe"
  fi

  local zip_out="$DIST/win/$APP_NAME-win64.zip"
  rm -f "$zip_out"
  (cd "$WORK" && zip -q -9 -r "$zip_out" "$APP_NAME-win64")
  say "Windows build: $zip_out"
}

# --------------------------------------------------------------- Linux
build_linux() {
  say "building Linux (x86_64 AppImage) app"
  local appimage_name="love-$LOVE_VERSION-x86_64.AppImage"
  local love_appimage="$CACHE/$appimage_name"
  # Same cache-validity gap as the win64 zip above: an AppImage is just an
  # ELF, so check the magic bytes before trusting a cached copy is complete.
  if [ -f "$love_appimage" ] && [ "$(head -c 4 "$love_appimage" | od -An -tx1 | tr -d ' \n')" != "7f454c46" ]; then
    warn "cached $appimage_name is not a valid ELF binary,  removing and re-downloading"
    rm -f "$love_appimage"
  fi
  if [ ! -f "$love_appimage" ]; then
    say "downloading LÖVE $LOVE_VERSION Linux AppImage"
    curl -fL --progress-bar \
      "https://github.com/love2d/love/releases/download/$LOVE_VERSION/$appimage_name" \
      -o "$love_appimage" || fail "download failed,  check LOVE_VERSION or your network"
    [ "$(head -c 4 "$love_appimage" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] \
      || fail "downloaded $appimage_name is not a valid ELF binary (truncated download?)"
  fi
  chmod +x "$love_appimage"

  # The Windows-style `cat love.exe game.love` fusion does NOT work here:
  # an AppImage is a small runtime ELF with a squashfs appended, and at
  # launch the runtime mounts the squashfs and executes bin/love from
  # *inside* it -- bytes appended to the outer file are never read, so
  # users would just get vanilla LÖVE's no-game screen. Instead, unpack
  # the squashfs, drop game.love in, point AppRun's FUSE_PATH hook at it
  # (the hook ships commented-out in LÖVE's official AppImage), and glue
  # runtime + repacked squashfs back together.
  command -v unsquashfs >/dev/null && command -v mksquashfs >/dev/null \
    || fail "squashfs tools not found; install with: brew install squashfs"

  # The squashfs starts right where the ELF ends:
  # e_shoff + e_shnum * e_shentsize (all little-endian in the ELF64 header).
  local e_shoff e_shentsize e_shnum sfs_offset
  e_shoff=$(od -An -j40 -N8 -tu8 "$love_appimage" | tr -d ' ')
  e_shentsize=$(od -An -j58 -N2 -tu2 "$love_appimage" | tr -d ' ')
  e_shnum=$(od -An -j60 -N2 -tu2 "$love_appimage" | tr -d ' ')
  sfs_offset=$((e_shoff + e_shentsize * e_shnum))
  [ "$(dd if="$love_appimage" bs=1 skip="$sfs_offset" count=4 2>/dev/null)" = "hsqs" ] \
    || fail "no squashfs superblock at computed offset $sfs_offset (unexpected AppImage layout)"

  local appdir="$WORK/linux-appdir"
  rm -rf "$appdir"
  unsquashfs -q -no-xattrs -o "$sfs_offset" -d "$appdir" "$love_appimage" >/dev/null

  cp "$LOVE_FILE" "$appdir/game.love"

  # Replace LÖVE's own desktop entry rather than keeping it: it says
  # Name=LÖVE / Icon=love, which is what appimaged, app menus and file
  # managers displayed this image as. Same file as the arm64 build writes,
  # so both architectures integrate under the game's name.
  local stock_desktop
  stock_desktop="$(find "$appdir" -maxdepth 1 -name '*.desktop' | wc -l | tr -d ' ')"
  [ "$stock_desktop" = 1 ] \
    || fail "expected exactly one .desktop at the AppDir root, found $stock_desktop"
  rm -f "$appdir"/*.desktop

  # share/ carries a second, NoDisplay copy of the same entry plus the .love
  # file-type icons and mime rule, all left over from LÖVE's `make install`
  # (its Exec even points at the CI runner that built it). Nothing at runtime
  # reads them -- only share/lua and share/luajit-* are on LUA_PATH -- but
  # AppRun puts $APPDIR/share on XDG_DATA_DIRS, so anyone extracting the image
  # gets a "LÖVE" entry back. The arm64 AppDir never had them.
  rm -rf "$appdir/share/applications" "$appdir/share/pixmaps" \
         "$appdir/share/mime" "$appdir/share/icons"

  cat > "$appdir/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=gen1recomp
Comment=Pokémon Gen 1 recompilation
Exec=$APP_NAME
Icon=$APP_NAME
StartupWMClass=love
Categories=Game;
Terminal=false
EOF

  # Icon= resolves against the AppDir root by basename, so the PNG has to be
  # named after the desktop entry; .DirIcon is what appimaged and
  # file-manager thumbnailers show for the file itself.
  [ -f "$ICON_SRC" ] || fail "missing icon source: $ICON_SRC"
  rm -f "$appdir/love.svg" "$appdir/love.png" "$appdir/.DirIcon"
  sips -z 512 512 "$ICON_SRC" --out "$appdir/$APP_NAME.png" >/dev/null
  cp "$appdir/$APP_NAME.png" "$appdir/.DirIcon"

  sed -i '' 's|^#FUSE_PATH="$APPDIR/my_game.love"$|FUSE_PATH="$APPDIR/game.love"|' "$appdir/AppRun"
  grep -q '^FUSE_PATH="\$APPDIR/game.love"$' "$appdir/AppRun" \
    || fail "failed to enable FUSE_PATH in AppRun (upstream AppRun changed?)"

  sed -i '' 's|^exec "\$APPDIR/bin/love"|if [ -n "$WAYLAND_DISPLAY" ] \&\& [ -z "$SDL_VIDEODRIVER" ]; then export SDL_VIDEODRIVER=x11; fi\
exec "$APPDIR/bin/love"|' "$appdir/AppRun"

  # Match the upstream image's compression (gzip, 128K blocks) so the
  # bundled runtime can read it.
  local sfs_out="$WORK/game.squashfs"
  rm -f "$sfs_out"
  mksquashfs "$appdir" "$sfs_out" \
    -comp gzip -b 131072 -noappend -all-root -no-xattrs -quiet >/dev/null

  local out_bin="$WORK/$APP_NAME-x86_64.AppImage"
  rm -f "$out_bin"
  head -c "$sfs_offset" "$love_appimage" > "$out_bin"
  cat "$sfs_out" >> "$out_bin"
  chmod +x "$out_bin"

  local zip_out="$DIST/linux/$APP_NAME-linux.zip"
  rm -f "$zip_out"
  (cd "$WORK" && zip -q -9 -j "$zip_out" "$(basename "$out_bin")")
  say "Linux build: $zip_out"
}

# --------------------------------------------------------------- Android
build_android() {
  say "building Android (delegating to scripts/build_android.sh)"
  local args=()
  if [ "$VERSION_EXPLICIT" = true ]; then
    args+=(--version "$VERSION")
  fi
  if [ "$IOS_IPA" = true ]; then
    args+=(--ipa)
  fi
  "$ROOT/scripts/build_android.sh" ${args[@]+"${args[@]}"}
}

# --------------------------------------------------------------- iOS
build_ios() {
  say "building iOS (delegating to scripts/build_ios.sh)"
  local args=()
  if [ "$IOS_RELEASE" = true ]; then
    args+=(--release)
  fi
  if [ "$VERSION_EXPLICIT" = true ]; then
    args+=(--version "$VERSION")
  fi
  "$ROOT/scripts/build_ios.sh" ${args[@]+"${args[@]}"}
}

case "$TARGET" in
  mac) build_mac ;;
  win) build_win ;;
  linux) build_linux ;;
  android) build_android ;;
  ios) build_ios ;;
  all) build_mac; build_win; build_linux ;;
esac

case "$TARGET" in
  android) say "done. See $DIST/android/" ;;
  ios) say "done. See $DIST/ios/" ;;
  *) say "done. Artifacts in $DIST" ;;
esac
