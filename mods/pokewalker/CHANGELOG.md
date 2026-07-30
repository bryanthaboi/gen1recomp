# Changelog

All notable changes to this mod are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-07-30

### Added

- Opt-in SYNC STEPS option: Apple Health step counts (delivered by the iOS
  build's native bridge as `steps_pending.json`) convert to EXP.
- STEPS PER EXP option (10 / 20 / 50, default 20).
- GIVE EXP TO option: lead mon (default) or whole party split.
- Level-ups applied with the engine's growth curves and rare-candy stat
  math; walk-report textbox at quiet moments.
- Guardrails: steps anchored to the last sync (never credited twice),
  50,000-step clamp per sync, engine `levelCap` respected.
