# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-08-13

### Removed

- The battle HUD owned-ball marker feature (Pokédex ball beside battler
  names) is gone — other mods already cover it, and the encounter guide is
  the unique part. Walking-HUD owned markers in species lists stay.

### Changed

- Display name is now **Encounters Guide** (mod id, repo, and update channel
  unchanged).

## [1.0.0] - 2026-08-12

Will's Mod is the single-mod merge of the Encounter Guide and Will's Battle
HUD: one install, one enable, both catch-'em-all tools.

### Added

- **Encounter Guide** (migrated from gen1recomp-encounter-guide v0.6.0):
  - START → PKMN MAP opens the imported ROM's own Kanto Town Map; D-pad
    between encounter-bearing locations, A drills into exact source maps.
  - Exact source identity: floors, caves, gates, buildings, and Pokémon
    Centers are never merged (`-- MT. MOON 1F` stays its own entry).
  - LAND and WATER as separate views; compact level ranges with exact
    per-step odds on drill-down.
  - Blinking white player-position marker, even where a location has no
    encounters.
  - Walking HUD (render.hud): per-area species + level ranges, top-right;
    modes AUTO / ALWAYS / OFF (options menu or H key) and sizes
    SMALL / MEDIUM / LARGE (options menu); visible under render-pipeline
    mods (voxel).
  - Owned-ball Pokédex markers in species lists and on the walking HUD.
  - SELECT opens the complete list, catching unmapped sources.
- **Will's Battle HUD** (migrated from wills_battle_hud v0.1.5):
  - Pokédex owned-ball markers below-left of battler names in battle,
    fixed per layout/side (classic and wide), independent of name length;
    hidden while the enemy is sending out and in safari/demo/back views.

### Changed

- Both features now live in one mod (id `wills_mod`) with one manifest,
  one `github` update channel, and one enable toggle.
- Options row keys and save keys are unchanged from the Encounter Guide
  (`encounterGuideHud`, `encounterGuideSize`), so existing saves keep
  their settings.

### Removed

- Standalone mods `encounter_guide` and `wills_battle_hud` are superseded.
