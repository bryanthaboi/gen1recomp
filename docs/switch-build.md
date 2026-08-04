# Build the Nintendo Switch NRO — contributor guide

Want to play a release build instead? Download the SD-ready zip and extract it
at your microSD root — see [switch-install.md](switch-install.md).

This guide is for contributors who build Gen1Recomp for Switch from source.
Hardware evidence, MTP operator loops, and deeper notes live in
[switch-development.md](switch-development.md).

> Releases ship `gen1recomp-*-switch.zip` (SD tree under `switch/gen1recomp/`;
> issue [#531](https://github.com/bryanthaboi/gen1recomp/issues/531)). Hardware
> evidence: **OLED** (author) and **V1 boot** (community). See
> [switch-development.md](switch-development.md) for known limitations.

---

## Prerequisites by OS

All packaging entrypoints are **bash**. On Windows, use Git Bash, MSYS2, or
WSL — not cmd.exe or PowerShell (AD-008).

### macOS / Linux

1. Install [devkitPro pacman](https://devkitpro.org/wiki/devkitPro_pacman).
2. Install Switch tools:

   ```sh
   sudo dkp-pacman -S switch-dev
   ```

3. Ensure `nacptool` and `elf2nro` are on `PATH` (or under
   `$DEVKITPRO/tools/bin` — the fused script prepends that when set).

**Optional:** Install [Docker](https://docs.docker.com/get-docker/) so fused
builds can fall back to the pinned image when native tools are missing.

### Windows (Git Bash / MSYS2 / WSL)

1. Use a bash environment:
   - **MSYS2** with the [devkitPro](https://devkitpro.org/wiki/devkitPro_pacman)
     packages (preferred for native `nacptool`/`elf2nro`), or
   - **WSL** (Ubuntu/etc.) with the Linux pacman flow above, or
   - **Git Bash** for `--fetch` / `--loose`; for `--fused` prefer MSYS2 or
     WSL if Docker bind-mounts from Git Bash paths misbehave.
2. Install `switch-dev` (or rely on Docker fallback — see below).
3. Do **not** expect `scripts/build_switch.sh` to run under cmd/PowerShell.

### What you must install yourself

| You install | Script does **not** install |
| ----------- | --------------------------- |
| bash, git, zip tooling the repo already expects | — |
| `dkp-pacman` + `switch-dev` (native fused) | `dkp-pacman -S …` |
| Docker (optional fused fallback) | Docker Engine |
| A legal `.gb` ROM (to play) | Any ROM or game data |

---

## Mode glossary

`scripts/build_switch.sh` supports three modes (combinable as noted):

| Mode | What it does |
| ---- | ------------ |
| `--fetch` | Downloads pinned **love.nro** + **love.elf** into `.bazinga/love-nx/11.5-nx1/` and verifies SHA-256 against `scripts/switch/love-nx-11.5-nx1.sha256`. |
| `--loose` | Packs `game.love`, copies pinned `love.nro` → `dist/switch/loose/` as `gen1recomp.nro` + `game.love` side by side. Needs the pin. |
| `--fused` | Builds `dist/switch/gen1recomp-<ver>-switch.nro` (game in romfs) via `nacptool` + `elf2nro`, then packs `dist/switch/gen1recomp-<ver>-switch.zip` (SD-ready tree). Needs the pin + toolchain (native or Docker). GitHub Releases publish the **zip only**. |

Rules:

- `--fetch` alone is fine; combine as `--fetch --loose` or `--fetch --fused`.
- `--loose` and `--fused` are **XOR** — pick one packaging path per run.
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

# Single fused NRO + SD-ready zip for a release-like artifact
scripts/build_switch.sh --fetch --fused --version 0.2.0
```

Outputs land under `dist/switch/` (and `dist/switch/loose/` for loose mode).
The fused path also writes `gen1recomp-<ver>-switch.nro.sha256` and
`gen1recomp-<ver>-switch.zip` (+ `.sha256` sidecar for the zip).

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
`tests/engine/switch_diagnostics_test.lua`, `tests/engine/platform_nx_*`,
or the Switch-related workflow YAML), CI runs:

1. **Offline selftest** on `ubuntu-latest` (forks **and** the canonical repo):
   `scripts/switch/selftest_build_switch.sh`,
   `scripts/switch/verify_payload.sh --self-test`,
   `luajit tests/switch_ci_workflows_test.lua`,
   `luajit tests/switch_transfer_docs_test.lua`, and the NX engine suites
   headlessly (`luajit tests/engine/assets_version_fallback_test.lua`,
   `luajit tests/engine/nx_generated_guard_test.lua`,
   `luajit tests/engine/nx_yellow_boot_test.lua`).
2. **Fused NRO build** only on the **canonical** repository
   (`bryanthaboi/gen1recomp`), on the self-hosted Mac runner
   (`scripts/build_switch.sh --fetch --fused`), and only when the workflow
   head is that repo (same-repo push/PR). **Fork repository** CI never runs
   fused. **Fork → canonical PRs** also skip Switch fused (offline selftest
   still runs) so untrusted head code is not executed on the self-hosted Mac;
   iOS device build eligibility is unchanged. Fused also waits for a successful
   offline selftest before starting on the Mac runner.
3. On successful PR fused builds, a follow-up workflow posts a PR comment
   linking the Actions artifact named `gen1recomp-switch-nro`
   (comment tag `switch-build-result`; see
   `.github/workflows/switch-artifact-comment.yml`).

Unrelated PRs do not burn the self-hosted Mac on Switch packaging.

### Release hard-fail (`.github/workflows/release.yml`)

GitHub Releases always build Switch on the same self-hosted Mac runner as the
other platforms — this is a **hard gate** (no `continue-on-error`):

```sh
scripts/build_switch.sh --fetch --fused --version "<release version>"
```

A Switch packaging failure fails the entire release job. The release asset is
`gen1recomp-<ver>-switch.zip` (SD-ready); the versioned `.nro` stays under
`dist/switch/` for the packer and for PR CI artifacts.

### Runner provisioning

The self-hosted Mac runner must have **native switch-tools** (`nacptool` /
`elf2nro`) **and/or Docker** available. CI and release do not silently run
`dkp-pacman -S`; keep the runner image/host provisioned per this guide.

---

## Limitations / non-goals

These scripts and this guide do **not**:

- Push files to the console (no automated MTP / FTP / SD scripting)
- Bundle or download any Pokémon ROM
- Install `dkp-pacman` / `switch-dev` for you
- Provide `nxlink` / netloader deploy (deferred — see [switch-transfer.md](switch-transfer.md))
- Validate **Applet Mode** — use title override (hold **R**) for full memory

Player install steps: [switch-install.md](switch-install.md).  
Manual transfer (MTP / SD / FTP, macOS / Linux / Windows):
[switch-transfer.md](switch-transfer.md).  
Hardware depth and evidence: [switch-development.md](switch-development.md),
[switch-hardware-evidence.md](switch-hardware-evidence.md).
