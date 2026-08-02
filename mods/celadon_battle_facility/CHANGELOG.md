# Changelog

## 1.0.0

The full ladder.

- Three tiers -- BRONZE (3 rounds), SILVER (5), GOLD (7) -- run back to back
  with no healing between rounds. Each unlocks only once the tier before it
  has been cleared.
- Opponents are rebuilt at your party's average level through the engine's
  `trainer.party` hook, plus a per-tier bonus, so the facility stays
  meaningful from mid-game to post-game. The rosters ship placeholder levels
  that never reach a battle.
- Clearing a tier pays BATTLE PT, spendable at the prize counter for a FULL
  RESTORE, PP UP, RARE CANDY, or MASTER BALL.
- A records board tracks tier clears and your best run.
- Lobby cast: greeter, prize clerk, archivist, and a rookie.

## 0.1.0

Phase 1 -- the building exists.

- Celadon City gains a 4x2 building on its west lawn at block rows 9-10,
  columns 2-5, with doors at cells (6,21) and (8,21). Eight lawn blocks and
  two appended warps change; nothing else about the city moves.
- New `CELADON_BATTLE_FACILITY` interior on the FACILITY tileset, whose
  doorway round-trips back to whichever door you entered by.
- Footprint art avoids blocks 17 and 115, which draw **GYM** and **MART**
  signage baked into the tileset; the suite asserts neither can land in it.
