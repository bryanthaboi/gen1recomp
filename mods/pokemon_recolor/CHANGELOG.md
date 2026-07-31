# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Headings match `manifest.version`.

## [1.0.0] - 2026-07-31

### Added

- Per-species four-shade colour ramps derived from Gen 3 artwork by
  luminance matching, applied to the player's own battle pics through
  `transforms.lua`. No pixels are distributed.
- Per-species algorithm choice (`kmeans`, `histogram`, or vanilla) recorded
  in `ramps.lua` itself and read back on regeneration, reviewed by eye
  across all 151.
- `pokemon.sprite` hook so the Pokedex picks up the repaint; unlike every
  other pic consumer, `DexEntryMenu` does not resolve through `Assets`.
