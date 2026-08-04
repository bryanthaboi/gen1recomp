# Switch file transfer (MTP / SD / FTP)

Canonical ways to put Gen1Recomp artifacts and inbox files onto a Nintendo
Switch. **Any method is valid** if the bytes land in the destinations below.

This is the home runbook for contributors on **macOS, Linux, and Windows**.
Player install (what to download, title override) stays in
[switch-install.md](switch-install.md). Packaging stays in
[switch-build.md](switch-build.md). Hardware evidence lives in
[switch-hardware-evidence.md](switch-hardware-evidence.md).

> **Not supported yet:** `nxlink` / hbmenu netloader automation. Useful later
> for a fast contrib rebuild loop; deferred on purpose (AD-009). Do not treat
> netloader as the release or ROM/mod install path.

---

## Destinations (shared by every method)

| What | Where on the console |
| ---- | -------------------- |
| SD-ready release zip | Extract at microSD **root** → `sdmc:/switch/gen1recomp/gen1recomp.nro` plus `pokemon-love2d/` inbox folders. Install and update use the same merge; do **not** delete `pokemon-love2d/` |
| Loose iteration pair | `sdmc:/switch/gen1recomp/gen1recomp.nro` **and** `game.love` beside it |
| ROM inbox | LÖVE save dir → `imports/` (launcher shows the live `getSaveDirectory()` path; under MTP often `1: SD Card/<save identity>/imports/`) |
| Mod zip inbox | Same save dir → `imports/mods/` then MODS → **Scan again** |
| Save `.sav` inbox | Same save dir → `imports/saves/red\|blue\|yellow/` then that game’s SAVE FILES → **Import save** |
| Save exports | Same save dir → `exports/red\|blue\|yellow/` (pull after **Export save**; MTP / SD / FTP) |
| Opt-in diagnostics | Empty `switch-debug.txt` in the save dir → `switch.log` |
| Lua error log | `lua-error.log` in the save dir |

Saves persist across zip re-extract / NRO replacements as long as
`pokemon-love2d/` is left in place. Never commit ROM dumps, `.sav`
files, or third-party mod zips to git.

---

## Canonical methods

### 1. MTP (DBI responder + host client)

On the Switch: close Gen1Recomp → open **DBI** → **Run MTP responder** (often
**X** on the main screen) → keep that screen up → USB-C data cable to the host.

On the host: open **one** MTP client, navigate to **`1: SD Card`**, then the
paths above. Wait for the transfer queue; refresh; exit MTP on the Switch
before launching.

#### macOS (example: OpenMTP)

[OpenMTP](https://github.com/ganeshrvel/openmtp) is the loop used for OLED
hardware evidence — **one contributor example**, not a Mac-only product rule.

1. Quit other MTP clients.
2. Open OpenMTP → select the DBI device → **`1: SD Card`**.
3. Create `switch/gen1recomp/` if needed; extract the release zip at SD root
   (or copy NRO / `game.love` for loose).
4. For ROMs/mods/saves, open the save-dir `imports/`, `imports/mods/`,
   `imports/saves/<red|blue|yellow>/`, or `exports/<red|blue|yellow>/` path the
   launcher prints.
5. Wait for the queue; refresh; exit MTP responder; title-override launch.

macOS clients often create AppleDouble sidecars (`._Something.zip`,
`._cart.gb`, `._foo.sav`). Those are not real archives or saves — the
launcher skips hidden `.*` names. Delete `._*` junk if a zip/ROM/`.sav`
fails to open.

#### Linux

1. Install desktop MTP support if needed (e.g. `gvfs-mtp` on GNOME/GTK
   desktops, or your distro’s KDE MTP stack).
2. With DBI MTP active, open **Files** / **Dolphin** / **Thunar** and select
   the Switch / DBI device → **`1: SD Card`**.
3. Extract the release zip at SD root (merge), or copy into `switch/gen1recomp/`
   and the save-dir inboxes as above.
4. Use **only one** MTP accessor at a time. If `mtp-tools` / `mtpfs` reports
   “device is busy”, close the file manager’s MTP mount (or the CLI mount)
   and retry with a single client.
5. Eject/unmount cleanly; exit MTP on the Switch; title-override launch.

If MTP is unavailable or flaky on Linux, use **direct SD** (Hekate UMS or a
card reader) or **FTP** instead — same destinations in the table above.

#### Windows

1. With DBI MTP active, open **This PC** / **File Explorer** and look under
   **Portable Devices** for the Switch / DBI MTP volume → **`1: SD Card`**.
2. Copy / extract into `switch\gen1recomp\` and the save-dir inboxes.
3. Optional: [OpenMTP](https://github.com/ganeshrvel/openmtp) on Windows if
   Explorer is flaky.
4. If Windows does not show an MTP device: Device Manager → find DBI / Switch
   → Update driver → **MTP USB Device** (or Standard MTP Device). Prefer a
   data-capable USB-C cable and a direct port.
5. Safely disconnect; exit MTP on the Switch; title-override launch.

If MTP is unavailable or flaky on Windows, use **direct SD** (Hekate UMS or a
card reader) or **FTP** instead — same destinations in the table above.

### 2. Direct SD (Hekate UMS or card reader)

Same destinations; no MTP client required.

- **Hekate UMS** (preferred when available): expose the microSD to the host
  while the card stays in the console; mount the volume; copy files; **cleanly
  unmount** before leaving UMS.
- **Physical reader**: power off / remove the microSD, copy on the host,
  **eject safely**, reinsert, boot CFW, title-override launch.

Do not yank the card or unplug UMS mid-write.

### 3. FTP (any SD-exposing Switch FTP)

Any homebrew FTP server that can write the microSD is fine — for example
**DBI’s own FTP**, **sys-ftpd-light**, or **Sphaira** (names are illustrations
only; pick what your CFW setup already uses).

1. Start the FTP server on the Switch; note IP/port/credentials from that app.
2. From the host, connect with any FTP client and upload to the same
   `switch/gen1recomp/`, `imports/`, `imports/mods/`, `imports/saves/<game>/`,
   and `exports/<game>/` paths.
3. Stop the FTP server cleanly before launching Gen1Recomp.

If credentials or chroots differ by app, trust the **destination paths**, not
a single vendor tutorial.

---

## After every transfer

1. Exit MTP / unmount SD / stop FTP cleanly.
2. Launch via **title override** (hold **R** on a title → hbmenu). **Applet
   Mode is not supported** (not enough memory).
3. For ROMs: open the matching game tab → **Scan again** if the file was
   added after boot (SHA-1 must match that tab; other dumps in `imports/`
   stay for their own tabs). For mods: MODS → **Scan again** → enable →
   Play. For saves: SAVE FILES → **Import save** (rescans
   `imports/saves/<game>/`). Pull exported `.sav` files from
   `exports/<game>/`. Joy-Con display chords (stock engine):
   [switch-install.md](switch-install.md#joy-con-shortcuts-select--face).

### Optional NRO integrity check

For the first deploy of a given artifact (or after a flaky cable):

```bash
shasum -a 256 path/to/gen1recomp.nro   # or sha256sum
```

Copy the file back from the SD and compare hashes. Round-trip must match.

---

## Failure modes (quick)

| Symptom | What to try |
| ------- | ----------- |
| Device busy / no MTP volume | One client only; different cable/port; Windows MTP USB Device driver; alternate method (SD or FTP) |
| Zip/ROM/`.sav` “could not be opened” | Delete `._*` sidecars (including `._*.sav`); confirm real zip starts with `PK` |
| Half-copied NRO / crash on boot | Re-copy; verify SHA-256; exit transfer mode before launch |
| App opens in Applet Mode | Use title override (hold **R**), not Album |

---

## Related

- Players: [switch-install.md](switch-install.md)
- Builders: [switch-build.md](switch-build.md)
- Status / hardware matrix: [switch-development.md](switch-development.md)
- Evidence log: [switch-hardware-evidence.md](switch-hardware-evidence.md)
