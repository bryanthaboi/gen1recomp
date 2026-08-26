# iOS build

This directory contains the macOS/Xcode build used to package Gen1 Recomp as
an iOS app with LÖVE 12.0.

## User data location

The app uses the public iOS Documents directory as its LÖVE save directory.
There is no `pokemon-love2d` subdirectory and the app does not create a
README file there. When browsing `On My iPhone > gen1recomp++` in Files, the
directory contains the app's runtime data directly, including:

- installed mods and downloaded ROMs
- save files and save-state data
- options, caches, logs, and other files created by the game

The build enables `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace`, so the same directory is available in
Files and Finder. Files copied into the app's Documents directory are used by
the game on its next activation.

Existing installations are migrated automatically. Files from the old
private `Application Support/pokemon-love2d` directory are merged into
Documents on launch; conflicts are retained with a `.legacy` suffix.

## Build

Run these commands from the repository root:

```bash
scripts/build_ios.sh --fetch
scripts/build_ios.sh
```

`--fetch` downloads the pinned LÖVE source and matching Apple dependencies
into the gitignored `love-src/` directory. It is only needed when that tree is
missing. The default build targets the iOS Simulator in Debug configuration.

For a physical device or a release build:

```bash
scripts/build_ios.sh --device --install
scripts/build_ios.sh --device --release --install
```

Device builds require a paired, unlocked device and a valid Apple signing
identity. Set `DEVELOPMENT_TEAM` or `CODE_SIGN_IDENTITY` when automatic
signing cannot select the intended account. Add `--ipa` to create
`dist/ios/gen1recomp++.ipa`.

The script verifies the final app before packaging it:

- the public Documents plist settings are present
- the native picker bridge is present
- the SHADER FX librashader bridge is linked into the app binary, when this build produced one
- `game.love` exists and is non-empty

If the payload is missing, the build fails instead of producing a blank app.

## Useful options

| Option | Purpose |
| --- | --- |
| `--fetch` | Fetch LÖVE 12.0 and Apple dependencies when `love-src/` is missing |
| `--device` | Build for `iphoneos` instead of the Simulator |
| `--release` | Use the Release configuration |
| `--install` | Install a device build on the first connected device |
| `--ipa` | Create an IPA after a device build |
| `--version X.Y.Z` | Stamp the engine and app version |
| `--package-only` | Package `game.love` and apply the iOS plist overlay without Xcode |

`scripts/build.sh ios` delegates to this script and forwards the iOS release
option.

## Output

Simulator and device app bundles are copied to:

```text
dist/ios/Debug-iphonesimulator/gen1recomp++.app
dist/ios/Release-iphonesimulator/gen1recomp++.app
dist/ios/Debug-iphoneos/gen1recomp++.app
dist/ios/Release-iphoneos/gen1recomp++.app
```

The intermediate Xcode products are under `mobile/ios/build/`. Both locations
are gitignored.

The bundled game payload is staged at
`love-src/platform/xcode/ios/resources/game.love` and copied into the final
app bundle. The payload contains the game, not user-generated ROMs, mods, or
saves; those are created at runtime in Documents.

## App identity

| Field | Default |
| --- | --- |
| Display name | `gen1recomp++` |
| Product name | `gen1recomp++` |
| Bundle identifier | `com.theboisclub.gen1recompplusplus` |
| Save directory | Public `Documents` root |
| Orientation | Portrait |

Set `GEN1_BUNDLE_ID` to use a different bundle identifier for local device
builds.

## Prerequisites

- macOS with Xcode and `xcodebuild`
- the iOS and iOS Simulator platforms installed in Xcode
- a fetched `love-src/` tree, or the `--fetch` option
- the matching iOS libraries and SDL3 framework under `love-src/`

Use `xcodebuild -showsdks` to confirm that the required SDKs are installed.
