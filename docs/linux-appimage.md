# Linux AppImage packaging

Releases ship raw AppImages (no zip wrapper):

- `gen1recomp-<version>-linux-x86_64.AppImage`
- `gen1recomp-<version>-linux-arm64.AppImage`

```sh
chmod +x gen1recomp-*-linux-x86_64.AppImage
./gen1recomp-*-linux-x86_64.AppImage
```

Flatpak users should prefer the `.flatpak` bundle (see
[linux-flatpak.md](linux-flatpak.md)); it avoids host glibc / FUSE / curl
mismatches on immutable desktops.

## Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Won't start / `libfuse.so.2` | No FUSE | `sudo apt install libfuse2` (or `libfuse2t64`) **or** `./app.AppImage --appimage-extract-and-run` |
| Update check / mods / save sync fail | Host `curl` missing or broken by AppImage `LD_LIBRARY_PATH` | Install curl; current builds scrub `LD_LIBRARY_PATH` for **host** curl and keep it for a bundled AppDir curl |
| Settings / sync reset after quit | Portable mode next to a read-only AppImage parent (`/opt`, system dir) | Remove `portable.txt` or move the AppImage to a writable folder; the game falls back to the XDG save dir when the probe write fails |
| "Download AppImage update" | Shell/`minShell` gate needs a full native package | Download the new `.AppImage`, `chmod +x`, replace the old file. Handheld ports show **Download port update** and fetch their own package instead — see [linux-arm-sbc.md](linux-arm-sbc.md) |
| Steam / Game Mode weirdness after update | Overlay `LD_PRELOAD` / PID change | HostShell unsets `LD_PRELOAD` for children and `execv`s `$APPIMAGE` on restart |

## Network transport (HostShell)

Desktop Linux fetches go through host or bundled `curl`:

1. Flatpak `/app/bin/curl` (bundled, keep sandbox libs)
2. `$APPDIR/usr/bin/curl` or `$APPDIR/bin/curl` (keep `$APPDIR` on `LD_LIBRARY_PATH`)
3. Host `curl` (`env -u LD_LIBRARY_PATH`, and always `-u LD_PRELOAD`)

## Portable mode

Drop `portable.txt` beside the `.AppImage` to keep saves next to the binary.
The launcher probes writability with a unique `.write_probe_<time>_<rand>.tmp`
file. Read-only parents fail soft and use `love.filesystem` XDG saves instead.
Flatpak ignores `portable.txt`.

## Auto-update

In-place updates download `gen1recomp-X.Y.Z.love` into the save directory.
Full shell bumps open the matching AppImage (or Flatpak) download URL — there
is no silent in-place AppImage replace yet.

PortMaster-style ports (`linux-arm-sbc`, `rg34xxsp`) are unpacked Linux builds
too, so they apply the same `.love` payloads in place, but they have no browser
in which to open a download URL. On a handheld the full-package prompt fetches
the port's own zip into the save directory for the player to re-extract; the
port is identified by `POKEPORT_PORTMASTER` / `POKEPORT_RG34XXSP`. See
[updater.md](updater.md) for the whole contract.

## Building

```sh
# x86_64 (macOS or Linux host with squashfs-tools)
scripts/build.sh linux --version X.Y.Z

# arm64 (aarch64 host + docker/podman)
scripts/build_linux_arm64.sh --version X.Y.Z
```

See [linux-arm64-build.md](linux-arm64-build.md) for the arm64 builder.
