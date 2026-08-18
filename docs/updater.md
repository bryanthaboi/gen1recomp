# Updater

A fused build (`love.filesystem.isFused()` true) ships a bundled `game.love`
baked into the executable, but that bundled copy is only ever the *fallback*.
On every launch, before anything else runs, `Boot.run` (`src/update/Boot.lua`)
looks in the save directory's `updates/` folder for a downloaded
`gen1recomp-X.Y.Z.love` payload that is both strictly newer than the bundled
engine version and runnable on this shell. If one qualifies, it is mounted
over `/` (so its files win over the fused source for every subsequent
`require`) and chainloaded in place: the payload's `main.lua` and `love.load`
run as if they had shipped in the executable. A dev/source checkout is never
fused, so `Boot.run` no-ops there and the working tree always runs itself.

The pieces are deliberately layered so the risky part is small. `Boot.select`
is a pure function (no `love.*` calls) that, given probed candidates and the
bundled `engine`/`shell`, decides what to run and what stale payloads to
delete. `Boot.probePayload` mounts one archive at an isolated mountpoint and
reads its `src/core/Version.lua` with `loadstring` (never `require`, so it is
never cached as a module) to learn its `engine` and `minShell`. `Boot.run`
orchestrates the crash guard, enumeration, selection, and the mount +
chainload, with full rollback on any failure. Checking for and fetching a
new payload is a separate, slower path: `src/update/Check.lua` is a thin
main-thread state machine the launcher screen polls, while the curl calls,
JSON parsing, and sha256 verification run on a background `love.thread`
(`src/update/check_worker.lua`) so a hung network call never blocks a frame.

## Version.lua fields

`src/core/Version.lua` carries four fields the updater reads directly (the
existing `modApi`, `linkProtocol`, `saveFormat`, and `cache` fields are
untouched):

- `engine` - the semver release, e.g. `"1.4.0"`. The repo default is the
  `"0.0.0-dev"` placeholder; CI stamps the real `X.Y.Z` into the packed
  `game.love` only, never the working tree. A `"0.0.0-dev"` engine always
  reports itself up to date (it never chases a release, and it never counts
  as a valid payload to chainload).
- `shell` - the native-shell contract this build's fused executable
  implements.
- `payloadHost` - the native host family an in-place payload targets. Ordinary
  LÖVE packages use `"love"`. A specialized native package uses a distinct,
  stable identifier and accepts only payloads carrying that same identifier.
  A missing field defaults to `"love"`, preserving compatibility with payloads
  released before this field existed.
- `minShell` - the lowest shell contract required to *run* this payload.

Bump `minShell` only when a payload needs something the currently-shipped
native shell cannot provide, for example a LOVE version bump, a new required
system binary, or a change to `love.run` itself (see Known limitations
below). An older shell refuses to chainload a payload whose `minShell`
exceeds the shell it provides; `Boot.select` keeps that payload in `updates/`
rather than deleting it, in case a future shell upgrade can run it, and
`Check`'s worker reports `needs_full` so the player is pointed at a full
installer instead. Do not bump `minShell` for an ordinary Lua/data release;
that is exactly the case the updater exists to avoid a reinstall for.

Change `payloadHost` only when the packaged Lua depends on a different native
host family. This is separate from `minShell`: the host name answers *which*
native integration the payload targets, while the shell number answers *which
revision* of that integration it requires. A mismatched-host payload is never
mounted or deleted as stale; the launcher directs the player to a full package.

## Release assets

Each tagged release `vX.Y.Z` carries the existing per-platform archives
(`gen1recomp-X.Y.Z-macos.zip`, `-windows.zip`, `-linux.zip`,
`-android.apk`) plus two assets the updater itself consumes:

- `gen1recomp-X.Y.Z.love` - the payload, matched by the exact pattern
  `gen1recomp-<version>.love` (see `isPayloadName` in `Boot.lua` and
  `Check.parseRelease`).
- `sha256sums.txt` - `shasum -a 256` output (`<hex>  <filename>`, bare
  filenames) covering at least the `.love` payload. `Check.parseSums`
  tolerates a leading `*` binary marker and a `./` prefix but expects the
  filename otherwise to match the asset name exactly.

A release missing either asset is treated as "no in-place update available":
`Check` reports `needs_full` and sends the player to `Check.releaseUrl()`
(`https://github.com/bryanthaboi/gen1recomp/releases/latest`).

## Save-directory layout

Under the save directory (identity `pokemon-love2d`):

```
updates/gen1recomp-<X.Y.Z>.love   downloaded payload(s)
updates/pending.txt                crash-guard marker
```

`pending.txt` holds the filename of the payload currently being chainloaded.
`Boot.run`'s `chainload` writes it immediately before mounting, and removes it
on both a successful handoff and a clean rollback. If it is still present the
*next* time `Boot.run` starts, the previous boot died mid-handoff, so that
named payload is distrusted: it and the marker are deleted before candidates
are enumerated. Boot may still fall back to an older valid payload, or to the
bundled game, in that case.

## Update flow

1. **Boot** (every launch, fused builds only): crash-guard check, enumerate
   and probe every `updates/*.love`, pick the highest engine that is
   strictly newer than the bundled one and whose `minShell` this shell
   satisfies, delete stale payloads, chainload the winner (or run the
   bundled game if none qualifies).
2. **Check** (launcher screen): `Check.start()` kicks off an async check
   against the GitHub releases API; safe to call every frame, it is a no-op
   once a check is in flight or has reached a terminal state. `Check.state()`
   reports `idle | checking | uptodate | available | downloading | ready |
   needs_full | error` plus the latest version and download progress.
3. **Download + verify**: on `available`, `Check.download()` tells the
   worker to fetch the payload, polling the growing `.part` file for
   progress. On completion the worker re-fetches `sha256sums.txt`, verifies
   the payload's sha256, and probes it with `Boot.probePayload` to gate its
   `minShell` against this shell's `shell`. A verified, runnable payload is
   renamed into place and reported as `ready`; anything else reports
   `error` or `needs_full` and leaves `updates/` clean.
4. **Restart to apply**: a `ready` payload just sits in `updates/` until the
   player relaunches; the next launch's Boot step (1) is what actually
   mounts and runs it. There is no in-session hot-swap.

## Known limitations


- **`love.run` persists across handoff.** By the time `chainload` runs, the
  bundled `love.run` has already returned its stepper to LOVE; redefining the
  global `love.run` from the payload's `main.lua` does not affect the loop
  already driving the frame. A payload that must change `love.run` itself
  needs a `minShell` bump so an older shell refuses to chainload it rather
  than running with half its intended behavior.
- **Android and iOS use the native download bridge, not curl.** Neither
  platform ships curl, so the old `check_worker.lua` path (shell out to curl)
  always landed on `error` and the launcher chip's "Check for updates" tap
  was a no-op. The worker now talks through `HostShell`, the same transport
  as the mod catalog: curl on desktop, `love.system.httpDownload` on mobile.
  On Android that is the GameActivity JNI/`HttpsURLConnection` bridge; on
  iOS it is `GRPickerBridge.httpDownload` (`URLSession`). A fused sideloaded
  APK or IPA can therefore check GitHub and fetch the `.love` payload
  in-app. If neither transport exists, the worker reports `needs_full` and
  the launcher chip opens `Check.releaseUrl()`. Native package-only changes
  still need a full reinstall (`minShell` / `payloadHost` gate →
  `needs_full`). Applying a downloaded payload on Android relaunches via
  `love.system.restartApp`; iOS still uses in-process `quit("restart")`.
- **Dev/source runs never self-update.** `Boot.run` returns immediately when
  `love.filesystem.isFused()` is false, and a working tree's `engine` is the
  `"0.0.0-dev"` placeholder that always reports up to date, so a source
  checkout is always "the game" itself; updating it means pulling the repo.
- **Nintendo Switch does not use this LÖVE self-updater.** On NX,
  `Platform.networkValidated()` is `false`, so `Boot.run` / `Check` never
  download `.love` payloads. In-console OTA uses the **native OTA launcher**
  (DEVKITPRO), documented in [switch-install.md](switch-install.md). Wire
  format: `src/update/SwitchOta.lua`. Manual zip install remains the fallback.
