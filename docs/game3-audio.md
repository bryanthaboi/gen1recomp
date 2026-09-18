# Game3 (FireRed) audio

Self-contained M4A/MP2K path: Lua extract during ROM import, in-process player at runtime. No Python, ffmpeg, or host CLI.

## Extract

`src/import/gba/extract_audio.lua` (Intro+Audio stage) writes:

```
data/generated/gba/audio/
  meta.json index.lua songtable.bin
  samples.bin samples.lua
  cries.lua crytable.bin
  songs/<id>.bin
```

DirectSound PCM is stored as raw **s8**. WaveData.type `1` is **GameFreak DPCM** — the extractor decompresses it to linear s8 (agbplay-compatible). Playing compressed bytes as PCM sounds shrieky/garbled.

Offsets for FireRed USA 1.0 are in `Versions.AUDIO` (`song_table`, `cry_table`). The extractor also structurally scans for `gSongTable` if needed.

## Runtime

| Module | Role |
|--------|------|
| `game3/audio.lua` | Numeric ID API (`playSong` / `playSe` / `playCry` / fanfare / map) |
| `m4a_sample.lua` | s8 → SoundData |
| `m4a_mix.lua` | DirectSound + CGB (ChipSynth-compatible oscillators) |
| `m4a_seq.lua` | Track bytecode; **GOTO = loop** |
| `m4a_player.lua` | Pack load + 4 players |
| `m4a_worker.lua` | Lock-free BGM buffer pump (`love.thread` Channels) |

Install uses explicit root `data/generated/gba/audio` (never Sevii `Extract.CACHE_ROOT`).

## Manual check

1. Import FireRed → cache has `samples.bin` / `index.lua`
2. Title / boot SE_SELECT (5)
3. Oak / mon pic cry
4. Start menu open/move/confirm SE
5. Field map BGM on enter; warp keeps or changes song
6. Wild battle BGM → victory → map restore
7. Level-up fanfare blocks `waitfanfare`

## Dev A/B (optional)

Desktop-only comparison against agbplay is fine for tuning. Never required for user import.
