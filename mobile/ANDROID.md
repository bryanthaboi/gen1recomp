# Android (love-android 11.5a)

`mobile/android/` is a **vendored copy** of
[love2d/love-android](https://github.com/love2d/love-android) at tag
**11.5a** (matches `conf.lua` `t.version = "11.5"`), tracked directly in
this repo,  no git submodules involved. Nested `love` sources live at
`mobile/android/love/src/jni/love` (also vendored). Build outputs
(`app/build/`, `love/build/`, `.gradle/`, `local.properties`) stay
gitignored.

## Refreshing the vendored tree

To pick up a newer love-android release, replace the tree and re-vendor:

```bash
rm -rf mobile/android
git clone --depth 1 --branch <new-tag> --recurse-submodules --shallow-submodules \
  https://github.com/love2d/love-android.git mobile/android
rm -rf mobile/android/.git mobile/android/love/src/jni/love/.git \
       mobile/android/.gitmodules
```

`scripts/build_android.sh` re-applies project branding on every run
(`gradle.properties` app id / name / portrait, plus permission trims), so a
refresh is safe,  just rebuild.

## Build

```bash
# Build the APK
scripts/build_android.sh

# Build the APK, setting app.version_name/app.version_code to match a release
scripts/build_android.sh --version 0.2.5

# Zip game.love + branding only (no Android SDK required)
scripts/build_android.sh --package-only
```

Or via `scripts/build.sh android [--version X.Y.Z]`.

The embedded `game.love` deliberately excludes `data/generated/`,
`assets/generated/`, and any ROM. It contains the first-boot Lua importer and
`tools/rom_manifest.json`.

ROM / mod / save import on Android uses `love.system.pickFile([kind])` →
`GameActivity.showFilePicker` (Storage Access Framework), which copies the
chosen file under the app save directory as `picked_rom.gb`,
`picked_mod.zip`, or `picked_save.sav`. `RomImporter` imports pending files
from that folder on Choose / refocus; see `docs/launcher.md`. The APK payload
itself remains data-free (no embedded ROM or generated cache).

### Step bridge (Pokéwalker mod)

`love.system.syncHealthSteps()` → `GameActivity.syncHealthSteps` (same
JNI route as the picker: `common/android.cpp` →
`modules/system/System.cpp` → `wrap_System.cpp`). The Java side does a
one-shot read of the hardware `TYPE_STEP_COUNTER` sensor (cumulative
since boot, counted by the OS whether or not any app runs), anchors the
reading in `SharedPreferences` so a walk is never credited twice
(a reading below the anchor means the phone rebooted → re-anchor without
crediting), and stages the delta as `steps_pending.json` in the save
identity dir — the same contract as the iOS `GRHealthBridge`. Nothing in
the base game calls it; the consumer is the
[Pokéwalker mod](https://github.com/mresnick67/Gen1ReComp-Pokewalker),
installed as a mod `.zip` at runtime (its SYNC STEPS option defaults
off).

Android 10+ gates the sensor behind the `ACTIVITY_RECOGNITION` runtime
permission (declared in `app/src/main/AndroidManifest.xml`; keep it out
of the build script's permission trim). The first
`syncHealthSteps()` call shows the system prompt; on grant the sensor
read runs immediately (`onRequestPermissionsResult`,
`STEP_PERMISSION_REQUEST_CODE`).

### Network transport (mod index / mod updates)

`love.system.httpDownload(url, absPath [, userAgent [, accept]])` ->
`GameActivity.httpDownload` (same JNI route as the picker and the step
bridge: `common/android.cpp` -> `modules/system/System.cpp` ->
`wrap_System.cpp`). Android ships no `curl`, which is what the desktop
builds fetch the mod index, mod release lists and mod zips with, so the
"Find mods" tab used to fail with "curl is not available on this
platform" (#597). The Java side is a blocking `HttpsURLConnection` GET
(https only, redirects followed by hand, body renamed into place only
once complete) and runs on LOVE's Lua thread, never the UI thread.
`src/core/HostShell.lua` picks the transport: curl when present,
otherwise this bridge; an APK older than the bridge simply reports no
transport, exactly as a missing curl does.

### SDK / NDK

love-android 11.5a expects:

- **JDK 17**
- Android SDK with **API 34**
- NDK **25.2.9519653** (Apple Silicon host supported)

Set `ANDROID_SDK_ROOT` (or `ANDROID_HOME`), or let the script write
`local.properties` when it finds `~/Library/Android/sdk`.

Gradle flavor used: **`embedNoRecord`** (game fused into the APK, no microphone).
Build task: `assembleEmbedNoRecordDebug`.

The APK lands under `app/build/outputs/apk/embedNoRecord/debug/`.
`scripts/build_android.sh` also copies it to `dist/android/debug/`.

### Payload path

`app/src/embed/assets/game.love` - zip of `main.lua`, `conf.lua`, `src/`,
`libs/` (the vendored FlexLove toolkit the launcher UI needs), `data/`,
`assets/`, and the Red, Blue, and Yellow ROM manifests. The Android
packer verifies the Yellow manifest before it packages; if a partial source
export omitted it, it restores the file from this checkout's Git data and then
falls back to the project's GitHub copy. Generated game data,
scripts, tests, and mobile build sources are excluded.

## Branding (applied by the build script)

| Setting | Value |
| --- | --- |
| `app.application_id` | `com.theboisclub.pokemonred` |
| `app.name` | Pokemon Red |
| `app.orientation` | `fullUser`. This is only the manifest default: SDL requests FULL_SENSOR at window creation (resizable window, no `SDL_HINT_ORIENTATIONS`), and `GameActivity.setOrientationBis` remaps that to FULL_USER so the device's rotation lock is honoured. |
| `app.version_name` / `app.version_code` | set from `--version X.Y.Z` (code = major*10000 + minor*100 + patch); left as-is if `--version` is omitted |
| Permissions | RECORD_AUDIO / WRITE_EXTERNAL_STORAGE stripped; VIBRATE + BLUETOOTH + INTERNET (link play, mod index) + ACTIVITY_RECOGNITION (step bridge) kept |

## Releases

`.github/workflows/release.yml` builds the APK with `--version` set to the
release version and publishes it alongside the macOS/Windows/Linux builds as
`PokemonRed-<version>-android.apk`.

## Signing

Signed with the default Android keystore (no setup required).
