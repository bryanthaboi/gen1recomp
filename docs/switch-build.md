# Build Gen1Recomp for Nintendo Switch

Want to play a release build instead? Download the SD-ready zip and extract it
at your microSD root. See [switch-install.md](switch-install.md).

This guide is for contributors who build Gen1Recomp for Switch from source.

> Releases ship `gen1recomp-*-switch.zip` (SD tree under `switch/gen1recomp/`).
> Runtime target is pinned [love-nx](https://github.com/retronx-team/love-nx)
> `11.5-nx1`. Player install and limitations: [switch-install.md](switch-install.md).

---

## Prerequisites by OS

All packaging entrypoints are **bash**. On Windows, use Git Bash, MSYS2, or
WSL, not cmd.exe or PowerShell (AD-008).

### macOS / Linux

1. Install [devkitPro pacman](https://devkitpro.org/wiki/devkitPro_pacman).
2. Install Switch tools (**required for `--fused`**):

   ```sh
   sudo dkp-pacman -S switch-dev
   ```

3. OTA launcher toolchain, **native or Docker** (either is fine):

   ```sh
   bash scripts/switch/install_devkitpro_deps.sh   # native
   # or install Docker (same pin as fused builds)
   ```

4. Ensure `DEVKITPRO` is exported (typical macOS: `/opt/devkitpro`) and
   `nacptool` / `elf2nro` are on `PATH` (or under `$DEVKITPRO/tools/bin`).

Fused game builds can also use Docker when native `nacptool`/`elf2nro` are absent.

### Native OTA launcher (included in `--fused`)

In-console OTA uses a **separate DEVKITPRO NRO** (not LÖVE). The LÖVE
self-updater (`Check.lua`) is disabled on NX. Source:
`ports/switch/ota-launcher/`. Host protocol tests (no toolchain):

```sh
make -C ports/switch/ota-launcher host-test
# or
scripts/switch/build_ota_launcher.sh   # host-test first; NRO needs DEVKITPRO/Docker
```

`--fused` always builds the fused game, native OTA launcher, and dual-NRO SD
zip. The same `*-switch.zip` is the OTA download asset. **DEVKITPRO is
required.** OTA launcher: native packages **or** Docker. Both are supported.

Release-like build from repo root:

```sh
scripts/build_switch.sh --fetch --fused --version X.Y.Z
```

See `ports/switch/ota-launcher/README.md` and
`scripts/switch/ota_launcher.manifest`.

### Windows (Git Bash / MSYS2 / WSL)

1. Use a bash environment:
   - **MSYS2** with the [devkitPro](https://devkitpro.org/wiki/devkitPro_pacman)
     packages (preferred for native `nacptool`/`elf2nro`), or
   - **WSL** (Ubuntu/etc.) with the Linux pacman flow above, or
   - **Git Bash** for `--fetch` / `--loose`; for `--fused` prefer MSYS2 or
     WSL if Docker bind-mounts from Git Bash paths misbehave.
2. Install `switch-dev` (or rely on Docker fallback; see below).
3. Do **not** expect `scripts/build_switch.sh` to run under cmd/PowerShell.

### What you must install yourself

| You install | Script does **not** install |
| ----------- | --------------------------- |
| bash, git, zip tooling the repo already expects | (none) |
| `dkp-pacman` + `switch-dev` + OTA packages **or** Docker | `dkp-pacman -S …` |
| A legal `.gb` ROM (to play) | Any ROM or game data |

---

## Mode glossary

`scripts/build_switch.sh` supports three modes (combinable as noted):

| Mode | What it does |
| ---- | ------------ |
| `--fetch` | Downloads pinned **love.nro** + **love.elf** into `.bazinga/love-nx/11.5-nx1/` and verifies SHA-256 against `scripts/switch/love-nx-11.5-nx1.sha256`. |
| `--loose` | Packs `game.love`, copies pinned `love.nro` → `dist/switch/loose/` as `gen1recomp.nro` + `game.love` side by side. Needs the pin. |
| `--fused` | Builds fused game NRO, OTA launcher NRO, and dual-NRO SD zip. **Requires DEVKITPRO** + `switch-dev`. OTA launcher: native packages or Docker. GitHub Releases publish the **zip only**. |

Rules:

- `--fetch` alone is fine; combine as `--fetch --loose` or `--fetch --fused`.
- `--loose` and `--fused` are **XOR**. Pick one packaging path per run.
- `--version X.Y.Z` sets the NACP / filename version (defaults to short git SHA).

### What `--fetch` downloads

Only the two pinned love-nx release assets (`love.nro`, `love.elf`). It does
**not** install:

- devkitPro / `dkp-pacman` / `switch-dev`
- Docker
- ROMs, saves, or mods

---

## Native tools, then Docker

Fused packaging (`scripts/switch/build_fused.sh`):

1. Prefer native `nacptool` + `elf2nro` on `PATH` (or `$DEVKITPRO/tools/bin`).
2. Else fall back to Docker using:
   - `GEN1_DKP_IMAGE` if set, otherwise
   - the image named in `scripts/switch/dkp-docker.image` (default
     `devkitpro/devkita64:latest`).

If neither native tools nor Docker work, the script exits non-zero with
macOS / Linux / Windows / Docker hints and a pointer to this doc.

---

## Example commands

From the repo root:

```sh
# Download pinned love-nx only
scripts/build_switch.sh --fetch

# Loose pair for iteration (fetch + assemble)
scripts/build_switch.sh --fetch --loose

# Fused game + OTA launcher + dual-NRO SD zip for a release-like artifact
scripts/build_switch.sh --fetch --fused --version 0.2.0
```

Outputs land under `dist/switch/` (and `dist/switch/loose/` for loose mode).
The fused path also writes `gen1recomp-<ver>-switch.nro` (game),
`gen1recomp-<ver>-launcher.nro`, `gen1recomp-<ver>-game.nro`,
`gen1recomp-<ver>-switch.nro.sha256`, and `gen1recomp-<ver>-switch.zip`
(+ `.sha256` sidecar for the zip).

Offline packaging smoke (no network, no nacptool required):

```sh
bash scripts/switch/selftest_build_switch.sh
bash scripts/switch/verify_payload.sh --self-test
```

---

## CI and release

Switch packaging has three automated surfaces (same policy as AD-010):

### Path-gated PR / push CI (`.github/workflows/ci.yml`)

When a change touches Switch packaging / Switch docs / NX runtime paths
(`scripts/build_switch.sh`, `scripts/switch/**`, `docs/switch-*.md`,
`tests/switch_ci_workflows_test.lua`, `tests/switch_transfer_docs_test.lua`,
the NX runtime modules `src/core/NxAssetOverlay.lua`, `src/core/Platform.lua`,
`src/core/GameVersion.lua`, `src/import/CacheFs.lua`, the NX engine suites
`tests/engine/assets_version_fallback_test.lua`,
`tests/engine/nx_generated_guard_test.lua`,
`tests/engine/nx_yellow_boot_test.lua`,
`tests/engine/cache_fs_gold_nx_load_test.lua`,
`tests/engine/switch_diagnostics_test.lua`, `tests/engine/platform_nx_*`,
or the Switch-related workflow YAML), CI runs:

1. **Offline selftest** on `ubuntu-latest` (forks **and** the main repo):
   `scripts/switch/selftest_build_switch.sh`,
   `scripts/switch/verify_payload.sh --self-test`,
   `luajit tests/switch_ci_workflows_test.lua`,
   `luajit tests/switch_transfer_docs_test.lua`, and the NX engine suites
   headlessly (`luajit tests/engine/assets_version_fallback_test.lua`,
   `luajit tests/engine/nx_generated_guard_test.lua`,
   `luajit tests/engine/nx_yellow_boot_test.lua`,
   `luajit tests/engine/cache_fs_gold_nx_load_test.lua`).
2. **Fused NRO build** only on the **main** repository
   (`bryanthaboi/gen1recomp`), on the self-hosted Mac runner
   (`scripts/build_switch.sh --fetch --fused`), and only when the workflow
   head is that repo (same-repo push/PR). Fork CI never runs fused. Fork PRs into the main repo also skip Switch fused (offline selftest still runs) so untrusted head code is not executed on the self-hosted Mac; iOS device build eligibility is unchanged. Fused also waits for a successful offline selftest before starting on the Mac runner.
3. On successful PR fused builds, a follow-up workflow posts a PR comment
   linking the Actions artifact named `gen1recomp-switch-nro`
   (comment tag `switch-build-result`; see
   `.github/workflows/switch-artifact-comment.yml`).

Unrelated PRs do not burn the self-hosted Mac on Switch packaging.

### Release hard-fail (`.github/workflows/release.yml`)

GitHub Releases always build Switch on the same self-hosted Mac runner as the
other platforms. This is a **hard gate** (no `continue-on-error`):

```sh
scripts/build_switch.sh --fetch --fused --version "<release version>"
```

A Switch packaging failure fails the entire release job. The release asset is
`gen1recomp-<ver>-switch.zip` (SD-ready); the versioned `.nro` stays under
`dist/switch/` for the packer and for PR CI artifacts.

### Runner provisioning

The self-hosted Mac runner **must** have **DEVKITPRO** installed and exported.
`--fused` preflight fails early with setup steps if it is missing.

**One-time setup on the runner** (if not already present):

```sh
# devkitPro pacman installer from https://devkitpro.org/wiki/devkitPro_pacman
sudo dkp-pacman -S switch-dev
export DEVKITPRO=/opt/devkitpro
export PATH="$DEVKITPRO/tools/bin:$PATH"

# OTA launcher: pick one
bash scripts/switch/install_devkitpro_deps.sh   # native
# or ensure Docker is installed (same pin as fused builds)
```

CI and release still run `scripts/build_switch.sh --fetch --fused`. Preflight
requires DEVKITPRO and either native OTA packages or Docker. Without all of
that, the job fails with the setup steps above. Scripts never auto-run
`dkp-pacman -S` during CI.

---

## Limitations / non-goals

These scripts and this guide do **not**:

- Push files to the console (no automated MTP / FTP / SD scripting)
- Bundle or download any Pokémon ROM
- Install `dkp-pacman` / `switch-dev` for you
- Provide `nxlink` / netloader deploy (deferred; see [switch-transfer.md](switch-transfer.md))
- Validate **Applet Mode**. Use title override (hold **R**) for full memory

Player install steps: [switch-install.md](switch-install.md).  
Manual transfer (MTP / SD / FTP, macOS / Linux / Windows):
[switch-transfer.md](switch-transfer.md).
