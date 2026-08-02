-- Parity port: Yellow's IsSurfingPikachuInParty (home/map_objects.asm).
-- When the party mon that knows SURF is a Pikachu, the player's surf sprite
-- swaps from the default (the Seel) to a Pikachu overworld sheet.  This
-- mirrors vanilla Yellow, which repoints wSpritePlayerStatePtr at the
-- surfing-Pikachu sheet during the ride.
--
-- Covers the engine change that adds field.playerSprites.surfPikachu,
-- Player.surfPikachuSprite, OverworldState:syncSurfingPikachu, and the
-- pose() sprite-pick switch.  No sprite bytes are read -- the assertions
-- compare the chosen SpriteRenderer's backing def, so the test is ROM-free
-- against the fixture dataset and runs in CI without an import.
--
-- Self-contained; run via:
--   luajit tests/parity_surfing_pikachu_sprite.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.CINNABAR_ISLAND) then Data:load() end

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("parity surfing-pikachu sprite")
local check, eq = S.check, S.eq

-- field default: the new key is seeded alongside the existing surf sprite,
-- so a mod-free boot gets the Pikachu overworld sheet by default
check(Data.field.playerSprites.surfPikachu == "SPRITE_SURFING_PIKACHU",
  "field.playerSprites.surfPikachu defaults to SPRITE_SURFING_PIKACHU (RFC 0001; Yellow ride)")
check(Data.field.playerSprites.surf == "SPRITE_SEEL",
  "the default surf sprite is still the Seel (no behavior change)")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack
StateStack:init()
Game.overworld = OW

local function mkMon(species, ...)
  local moves = {}
  for _, id in ipairs({ ... }) do
    table.insert(moves, { id = id, pp = 10, ppUp = 0 })
  end
  return {
    species = species, level = 30, hp = 50, maxHp = 50,
    status = 0, moves = moves,
  }
end

local function freshOw(party)
  Game.save = SaveData.newGame()
  Game.save.party = party
  Game.save.inventory = { SOULBADGE = true }
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, "CINNABAR_ISLAND", 19, 8, "right")
  local ow = Game.stack:top()
  -- the mount itself goes through trySurf (TextBox + whiteFlash + step),
  -- so arm the surf state directly and let syncSurfingPikachu derive
  -- the sprite pick -- the unit under test.
  ow.player.surfing = true
  ow:syncSurfingPikachu()
  -- the real SPRITE_SURFING_PIKACHU art only exists after an Yellow
  -- import + the RFC 0001 extractor path; inject a sentinel surf sprite
  -- so pose()'s selection rule is testable in the fixture dataset.
  ow.player.surfPikachuSprite = { def = { id = "SPRITE_TEST_SURF_PIKA" } }
  return ow
end

-- the sprite def backing a Player:surfSprite / surfPikachuSprite, so the
-- assertion can compare identities without drawing
local function surfSpriteId(player)
  local sprite, _px, _py = player:pose()
  return sprite and sprite.def and sprite.def.id or nil
end

-- -------------------------------------------------- Pikachu knows SURF
do
  local ow = freshOw({ mkMon("PIKACHU", "SURF"), mkMon("SQUIRTLE") })
  check(ow.player.surfing, "player is now surfing")
  check(ow.player.surfingPikachu == true,
    "surfingPikachu set when a Pikachu knows SURF")
  eq(surfSpriteId(ow.player), "SPRITE_TEST_SURF_PIKA",
    "pose() draws the surf-pikachu sprite, not the Seel (when set)")

  -- dismount flips it off again: set surfing false and re-sync, the way
  -- the dismount paths in OverworldController do
  ow.player.surfing = false
  ow:syncSurfingPikachu()
  check(ow.player.surfingPikachu == false,
    "syncSurfingPikachu clears the flag when dismounted")
end

-- -------------------------------------------------- no Pikachu, no swap
do
  local ow = freshOw({ mkMon("SQUIRTLE", "SURF") })
  check(ow.player.surfing, "player is surfing")
  check(ow.player.surfingPikachu == false,
    "no Pikachu in the SURF-mon: surfingPikachu stays false")
  eq(surfSpriteId(ow.player), "SPRITE_SEEL",
    "pose() keeps the default Seel surf sprite")
end

-- -------------------------------------------------- SURF-knower is the
-- Pikachu's species, not a slot position: a Pikachu without SURF behind a
-- Squirtle that has SURF must NOT trigger the swap
do
  local ow = freshOw({ mkMon("SQUIRTLE", "SURF"), mkMon("PIKACHU", "THUNDER_SHOCK") })
  check(ow.player.surfingPikachu == false,
    "Pikachu present but not the SURF-mon: no swap")
  eq(surfSpriteId(ow.player), "SPRITE_SEEL",
    "pose() keeps the Seel when the SURF-mon is not a Pikachu")
end

-- -------------------------------------------------- not surfing: no swap
do
  local ow = freshOw({ mkMon("PIKACHU", "SURF") })
  ow.player.surfing = false
  ow:syncSurfingPikachu()
  check(ow.player.surfingPikachu == false,
    "syncSurfingPikachu is a no-op swap when not surfing")
end

S.finish()