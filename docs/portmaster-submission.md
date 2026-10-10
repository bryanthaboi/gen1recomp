# PortMaster submission

Status: testing candidate; not accepted into the catalogue.
Destination: https://github.com/PortsMaster-MV/PortMaster-MV-New
Current requirements: https://portmaster.games/packaging.html

## Permission

On 6 October 2026, project owner bryanthaboi replied “Explicit permission
granted” to Nexhas's request to permit PortMaster distribution of the proprietary
launcher. The supplied private-message screenshot is retained by the requester;
it is not bundled or published. LICENSE.MD records the narrow distribution
exception. The original attribution and other launcher restrictions remain.

## Build and validate

```sh
python3 scripts/portmaster/package.py --version X.Y.Z --screenshot /absolute/gameplay.png
python3 scripts/portmaster/test_launcher.py
luajit tests/engine/portmaster_managed_update_test.lua
```

Use a clean, committed source revision; SOURCE.txt records that revision and
whether tracked changes were present. X.Y.Z identifies the engine version, not
PortMaster approval. The ZIP is explicitly named `gen1recomp-testing.zip`.
The screenshot must show the actual unmodified base game or main function,
not a mod absent from the package. A desktop capture is presentation evidence,
not ARM device validation. Do not commit ROMs or extracted caches.

Copy `dist/portmaster/ports/gen1recomp/` into `ports/` in a sparse checkout of
PortMaster-MV-New. Run its `python3 tools/build_release.py --do-check` and
`python3 tools/build_release.py --quick-build gen1recomp`.
The repository-built ZIP is preferred for community testing.

## Hardware evidence

- Existing standalone SBC build: Nexhas reports it worked on TrimUI Brick.
- Firmware/version and exact build for that report: not yet recorded.
- Catalogue testing ZIP: Nexhas confirmed it works on TrimUI Brick on
  6 October 2026, after testing the candidate supplied in this chat.
- Tested candidate source: `fce5f08650618846ae35142475441ac65937fd2f`.
- Supplied ZIP SHA-256: `7298d2720cf4701f48d5fd31b5f27d03f1351375730e0d0c11cb47553c3ce519`.
- Firmware/version and individual import/save, exit and suspend checks for the
  catalogue test: not yet specified; the report confirms general operation.
- Discord #testing-n-dev thread: not yet created.

Record build SHA/checksum, firmware/version, device and resolution with each
result. Check cold launch, missing/wrong ROM handling, import, controls,
new game, save/reload, exit shortcut, suspend/resume, offline play, and an
update preserving saves. Test 640x480 and a higher resolution; request help
for AmberELEC, dArkOS/ArkOS, muOS, ROCKNIX (Libmali/Panfrost), and Knulli.
Keep untested cells unchecked. The Brick confirmation applies to the candidate
identified above; it does not establish compatibility with other firmware.

## Testing-thread draft

Title: Gen1Recomp — aarch64 LÖVE port testing

I'm preparing Gen1Recomp for PortMaster-MV. It is a native recreation which
extracts assets from a user-supplied supported US ROM; no ROMs or generated
cache are included. The project owner has explicitly permitted PortMaster
distribution of the launcher, recorded in the included license.

I tested this catalogue candidate on my TrimUI Brick and confirmed it works.
It uses PortMaster's LÖVE 11.5 runtime, including that runtime's LuaJIT
2.1.0-beta3 (unlike the release zips, which bundle a pinned modern LuaJIT; see
https://github.com/bryanthaboi/gen1recomp/blob/dev/docs/linux-arm-sbc.md#bundled-luajit), so the JIT must stay off. I'm looking
for testing on the firmware and resolutions listed above, especially import,
save/reload, controller exit and suspend/resume. Please include device,
firmware, package checksum, result and `gen1recomp/log.txt` when reporting a
problem. Do not upload ROMs, saves, or generated cache in reports.

Attach the validated testing ZIP and its SHA-256. Add the thread URL here once
posted. Submit the upstream PR after community testing, with the source
revision, build instructions, permission note and honest testing matrix.
