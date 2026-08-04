# Switch hardware evidence (Phase 0 + import + input)

> **Hardware evidence log.** Author passes below were recorded on **one
> Nintendo Switch OLED** with a **manual** Mac → DBI MTP deploy loop. A
> separate community row records Switch V1 / Erista boot. These rows do
> **not** claim Lite, docked soak, or automated install. See
> `docs/switch-development.md` for status and limitations.

**love-nx:** `11.5-nx1`  
**Author console:** Switch OLED  
**Deploy method (author):** manual OpenMTP + DBI `Run MTP responder` (no CI / no nxlink)  
**Operator (author rows):** Andrew ([andrewqsantos](https://github.com/andrewqsantos))  
**Date (author rows):** 2026-08-01  

Do **not** commit ROM dumps or private dump hashes. Do **not** mark a row **pass** without hardware notes for that row.

---

## Community — Switch V1 / Erista boot — pass (boot)

| Field | Value |
| ----- | ----- |
| Console | Nintendo Switch V1 (Erista) |
| Check | Prebuilt fused NRO boots under title override |
| Tester | [booshankles](https://github.com/booshankles) |
| Notes | Community confirmation only — not a full P0/P1 matrix re-run on V1 |

---

## Phase 0 — probe (T4) — pass

| Field | Value |
| ----- | ----- |
| Commit (import era) | `df7cea4` |
| `getOS()` / `love._os` | `NX` |
| Dimensions | 1280×720 |
| Save (probe) | `sdmc:/switch/gen1recomp/switch-probe` |
| Joy-Con | `joystickpressed` + `gamepadpressed` (Y→`#3`, X→`#4`) |

| Artifact | SHA-256 |
| -------- | ------- |
| `gen1recomp.nro` | `8290ac153d4c630e48c9b26ef9123f5204ed8ee0cef3042511707b5b645918f5` |

---

## T12 — Red import + Play — pass

Inbox MTP → “Scan again” → Play; Joy-Con launcher/gameplay (not touch-only).

---

# T16 — Joy-Con launcher + gameplay — pass (naming re-verify)

### Round 1 @ `7504753` — partial

| Check | Result |
| ----- | ------ |
| Launcher / overworld (Joy-Con only) | **pass** |
| Naming player/rival | **fail** (dual-path a+b; see below) |
| Touch required | **no** |
| `game.love` SHA-256 | `bd3a35461bf453c1f0465a5a289421aef3b5c72d3bf1f8d76e86231256829e0e` |

### Naming failure (root cause) — fixed in `efd81d8` + `2699c9a`

- love-nx fires **`gamepadpressed` + `joystickpressed` on the same physical press**.
- `NamingScreen` tested `wasPressed("b")` before `"a"` → if both true in one frame, always deletes.
- Dual-path fix: ignore raw when `isGamepad()` (`efd81d8`).
- SDL-only UX then had physical B confirm / A erase; NX face remap (`2699c9a`) restores Nintendo A=confirm / B=cancel.

### Round 2 @ `2699c9a` — pass (Nintendo UX)

| Field | Value |
| ----- | ----- |
| Commit tested | `2699c9a` |
| `game.love` SHA-256 | `a208b21e1f30b00e2e8c6fa6efe14f0e06d1db0ae1e50b810b16d9fb852926bc` |
| Touch required | **no** |

| Check | Result |
| ----- | ------ |
| Naming — player | **pass** — physical **A** confirms letter, **B** cancels/erases |
| Naming — rival | **pass** (same) |
| Launcher / overworld (prior round) | **pass** (unchanged mapping for d-pad/stick) |

T16 hardware gate: **closed**.

---

## T19 — save / suspend — pass

| Check | Result |
| ----- | ------ |
| Save in-game → full quit → title-override reopen → load save | **pass** (@ `7504753` / retained) |
| Suspend/resume ×10 (launcher / gameplay / mixed) | **pass** (operator 2026-08-01) |
| Full console reboot persistence | **pass** (operator 2026-08-01) |

T19 hardware gate: **closed**. No stuck input, duplicate audio, or crash reported.

---

## T24 — fused NRO alone + NRO-only update — **pass**

| Field | Value |
| ----- | ----- |
| First fused attempt | `6fb5602` (Blue Play failed — mount) |
| Fix commits | `b1ad7c7` (logs/generated overlay), `ac6dfe7` (Blue/Yellow mount) |
| Deploy | isolated folder, no adjacent `game.love` |
| Boot fused | **pass** |
| ROM import | **pass** |
| Play **Red** | **pass** |
| Play **Blue** (after `ac6dfe7`) | **pass** (operator 2026-08-01) |
| NRO-only replace | **pass** — saves retained; app still boots/plays |
| Touch required | no |

T24 hardware gate: **closed**.

---

## SWBLD — `build_switch.sh --fetch --fused` + install path — **pass**

Operator smoke for the switch-build-pipeline packaging CLI (closes matrix-deferred happy paths from validation).

| Field | Value |
| ----- | ----- |
| Command | `scripts/build_switch.sh --fetch --fused --version 0.0.0-test` |
| Host | macOS + native switch-tools (or Docker fallback if used) |
| Commit / build-info | `9147a64` (`gitCommit` in build-info) |
| love-nx | `11.5-nx1` (manifest checksums match) |
| Artifact | `dist/switch/gen1recomp-0.0.0-test-switch.nro` |
| NRO SHA-256 | `210efb884a8d27443dc1c64ed8f071b0f862d8d0c9b140ad8185093c4e4027db` |
| Install doc | `docs/switch-install.md` — at the time of this row: copy NRO under `sdmc:/switch/gen1recomp/` (releases now ship an SD-ready zip; same folder) |
| Console | Switch OLED |
| Operator | Andrew |
| Date | 2026-08-01 |

| Check | Result |
| ----- | ------ |
| `--fetch` + `--fused` produce NRO + `.sha256` | **pass** |
| Copy NRO to SD folder per install doc | **pass** (operator) |
| Title-override launch / play | treated as prior T24 path; this row records **packaging + deploy to folder** success |

SWBLD packaging smoke: **closed** for Mac fused build + file-to-SD install step.

---

## NXMOD-12 — Community mod zip OLED smoke — **pass**

Closed from existing OLED photo evidence on issue
[#531](https://github.com/bryanthaboi/gen1recomp/issues/531) (operator comment
with launcher MODS + overworld shots). Photos live on the orphan branch
[`switch-oled-photos`](https://github.com/andrewqsantos/gen1recomp/tree/switch-oled-photos)
of the operator fork — **not** committed to this repo. Do **not** commit
third-party mod `.zip` bytes. Community mods own their OPTIONS / rebinds;
this entry only proves the MODS inbox + Play path on OLED.

| Field | Value |
| ----- | ----- |
| Status | **pass** |
| gen1recomp commit | evidence era on `feat/switch-nx` (see #531); packaging pin love-nx `11.5-nx1` |
| love-nx tag | `11.5-nx1` |
| Console | Switch OLED |
| Mod | community release `.zip` (not vendored; not named here) |
| Zip committed to git? | **no** |
| Photo evidence | [#531 comment](https://github.com/bryanthaboi/gen1recomp/issues/531) — MODS tab + overworld |
| MODS tab photo | https://raw.githubusercontent.com/andrewqsantos/gen1recomp/switch-oled-photos/IMG_1766.jpg |
| Overworld photo | https://raw.githubusercontent.com/andrewqsantos/gen1recomp/switch-oled-photos/IMG_1771.jpg |
| Operator | Andrew |
| Date | 2026-08-01 |

### Checklist

| Step | Pass / fail / pending | Notes |
| ---- | --------------------- | ----- |
| MTP zip into save `imports/mods/` | **pass** | Photo evidence + prior inbox path |
| MODS → Scan again → mod listed | **pass** | IMG_1766 — community mod installed |
| Enable mod + Play Red boots without crash | **pass** | Overworld / Pallet / Oak lab photos on #531 |
| Overworld Select+A → visible colors change | **pass** | Stock COLORS chord path exercised |
| Overworld Select+B → visible tilt/perspective change | **pass** | Stock TILT chord path exercised (IMG_1771) |

### Evidence notes

```text
Operator: Andrew
Date: 2026-08-01
Commit tested: feat/switch-nx era documented on issue #531
Pass / fail summary: PASS — MODS zip install + Play on Switch OLED
Photo branch: andrewqsantos/gen1recomp@switch-oled-photos
```
