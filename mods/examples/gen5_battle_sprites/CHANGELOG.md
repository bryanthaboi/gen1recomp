# Changelog

## [2.0.0] - 2026-10-01

### Changed

- Provider API and capability contract version 2 return the original animation
  union dimensions for every atlas and complete part-track frame. All source
  pixels and transparent margins are preserved; the 64×64 sampling path is removed.
- Frames report actual width and height with `groundOffset = height / 2` for
  the bottom anchor relative to image center. Renderers must accept API version
  2 and use variable frame dimensions when choosing display scale.
- Capabilities advertise `nativeResolution`, `variableDimensions`, and maximum
  frame dimensions of 256×256. Fixed `frameWidth`/`frameHeight` fields are removed.
- Existing exporter 1.1 packs already contain the original pixels and need no
  ROM reimport. Shared-clock timing, bounded caches and fallback remain intact.

## [1.3.0] - 2026-10-01

### Added

- Complete playback for long idle animations from exporter 1.1 part tracks.
  Each multicell record keeps its own intro and loop on the shared 60 Hz
  tick; frames are composed on demand in the source compositor's OAM order.
- Bounded caches for part plans (16), unpacked part pixels (6) and composed
  frames (16), with composed-frame reuse while the state combination holds.

### Changed

- Capped entries with part tracks now play instead of keeping native art.
  Capped entries without them (1.0 packs) keep native art as before.

## [1.2.0] - 2026-09-30

### Added

- Native optional `gen5_bw/battle_sprites` pack consumer using the scoped mod API.
- API version 1 renderer contract, bounded graphics caches, and shared simulation clock.
- Integer tick timing with one-time animation intros and suffix loops.
- ROM-free loader and playback regression tests.
