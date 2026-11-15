-- The new-game seed has to fill wVariableSprites, not just the event flags.
--
--   luajit tests/gen2_variable_sprites_test.lua
--
-- Found by the Gold route bot (tests/drivers/gold_bot.lua): it walked to the
-- Sudowoodo on Route 36 with the SQUIRTBOTTLE in the bag, faced (35,9), pressed
-- A and nothing happened -- because there was nothing there.
--
-- SPRITE_WEIRD_TREE is $f4, and everything from $f0 up is a wVariableSprites
-- SLOT rather than a sheet (constants/sprite_constants.asm:147).  An object
-- carrying one is extracted with a NUMBER in `sprite`, World:resolveSprite
-- answers nil until the slot is filled, and World:pooledNpc spawns nothing --
-- which is faithful, because on the cart the slots are filled by
-- InitializeEventsScript, whose last nine commands are `variablesprite`.
--
-- The port's seed replayed that script's `setevent` list and dropped the rest,
-- so a new game had no Sudowoodo -- and therefore no TM08 ROCK SMASH, no
-- Burned Tower, no Morty, no FOGBADGE and no SURF -- plus no Olivine rival, no
-- Azalea Rocket, no Fuchsia Gym Janines, no Copycat and no Janine
-- impersonator.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 variable sprites")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")

do
  check(World.findInitialSprites == nil,
    "no scripts.lua scan stands in for initial_events.sprites")
end

-- resolveSprite is the half that reads it back, and the reason an unfilled
-- slot is invisible rather than merely wrong.
do
  local w = setmetatable({
    variableSprites = {},
    constants = { spriteOrder = { [55] = "SPRITE_SUDOWOODO" } },
  }, { __index = World })
  eq(w:resolveSprite(0xf4), nil, "an unfilled slot resolves to nothing")
  w.variableSprites[0xf4 - 0xf0] = 55
  eq(w:resolveSprite(0xf4), "SPRITE_SUDOWOODO", "a filled slot names a sheet")
  eq(w:resolveSprite("SPRITE_NURSE"), "SPRITE_NURSE",
     "an ordinary sprite name passes straight through")
end

S.finish()
