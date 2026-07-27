-- Driver: Pokedex owned-ball alignment for NIDORAN (#285).  A manual eye
-- check, not a pass/fail run.
--
-- The list draws each owned entry's pokeball marker one blank glyph after
-- the name.  ListMenu measured that gap with `#item.label`, the Lua string's
-- BYTE length, but the charmap's gender symbols are multi-byte UTF-8: the
-- eight glyphs of "NIDORAN<male>" occupy ten bytes, so those two rows put
-- their ball 16px further right than every other species.
--
-- src/render/Font.lua already says this out loud in Font.width's own
-- docstring ("callers that right-align with `#text * 8` mis-place them"),
-- which is exactly the call this fix switches to.
--
-- This one has a built-in control case: NIDORINA, NIDORINO and NIDOKING sit
-- immediately around the two Nidoran rows in dex order and carry no gender
-- symbol, so a correct fix leaves all five balls in one vertical column.
--
-- Do NOT run this under POKEPORT_SPEED: fast-forward scales only the logic
-- clock, so a sped-up run can capture a half-drawn frame.
--
--   POKEPORT_DRIVER=tests/drivers/pokedex_nidoran_bug285_test.lua POKEPORT_IDENTITY=bug285 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Font = require("src.render.Font")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot separate from the bug ----------------
  -- A dex with nothing owned shows no balls at all, which looks the same as
  -- balls in the wrong place.  Seed the neighbourhood and prove the premise.

  local dexRow = { "NIDORAN_F", "NIDORINA", "NIDOQUEEN",
                   "NIDORAN_M", "NIDORINO", "NIDOKING" }

  game.save.pokedex = game.save.pokedex or { seen = {}, owned = {} }
  for _, id in ipairs(dexRow) do
    game.save.pokedex.seen[id] = true
    game.save.pokedex.owned[id] = true
  end
  game.save.party = { Pokemon.new(game.data, "NIDORAN_M", 10) }
  game.save.player.name = "bryan"

  for _, id in ipairs(dexRow) do
    check("owned: " .. id, game.save.pokedex.owned[id] == true)
  end

  -- the premise itself: the gender names really are multi-byte, so byte
  -- length and glyph width really do disagree for exactly these two rows
  local male = game.data.pokemon.NIDORAN_M.name
  local plain = game.data.pokemon.NIDORINO.name
  U.log("NIDORAN male name:", male, "bytes:", #male, "glyph width:", Font.width(male))
  check("gender name is multi-byte (this is the whole bug)",
        #male > Font.width(male) / 8)
  check("a plain neighbour agrees byte-for-glyph",
        #plain == Font.width(plain) / 8)

  check("renderer is up", game.renderer ~= nil)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)

  Screens.push(game, "PokedexMenu")
  U.wait(30)

  -- Walk down far enough that the whole Nidoran block is on screen at once.
  -- The list shows seven rows with the cursor on the last, so stopping at
  -- dex 29 would leave NIDORAN female alone above six empty rows and there
  -- would be nothing to compare her ball against.  Dex 35 puts 029-035 in
  -- view: both Nidoran rows plus four gender-free neighbours.
  for _ = 1, 34 do
    U.tap(game, "down")
    U.wait(2)
  end
  U.wait(20)
  U.shot(game, "bug285_pokedex_nidoran.png")

  U.log("........................................................")
  U.log("LOOK NOW: the Pokedex list is parked on the NIDORAN block.")
  U.log("  Screenshot: bug285_pokedex_nidoran.png in the LOVE save dir.")
  U.log("  RIGHT: every owned row's pokeball sits one blank space after its")
  U.log("         name, so NIDORAN<f>, NIDORINA, NIDOQUEEN, NIDORAN<m>,")
  U.log("         NIDORINO and NIDOKING all show a ragged-but-consistent gap")
  U.log("         of exactly one space.")
  U.log("  BUG #285 looks like: the two NIDORAN rows alone kicking their")
  U.log("         ball two extra characters to the right, out of line with")
  U.log("         the four neighbours that have no gender symbol.")
  U.log("  ALSO WRONG: every ball moving together (that would mean the base")
  U.log("         offset changed, not the measurement), or the ball landing")
  U.log("         on top of the last letter with no gap at all.")
  U.log("Compare against the screenshot in issue #285. Input is yours from")
  U.log("here: up/down scrolls, and any other owned species is a control.")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
