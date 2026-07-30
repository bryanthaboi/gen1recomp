-- Parity: the Rocket Hideout lift gates (#372).
--
-- Oracle: scripts/RocketHideoutB4F.asm RocketHideoutB4FDoorCallbackScript
-- stamps $2d over the lift doorway (lb bc, 5, 12) until CheckBothEventsSet
-- EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0 / _1, then plays SFX_GO_INSIDE and
-- writes $e; scripts/RocketHideoutB1F.asm is the same shape with $54 at
-- lb bc, 8, 12 over EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4.  The callback
-- runs whenever BIT_CUR_MAP_LOADED_1 is set, which home/trainers.asm
-- EndTrainerBattle does, so the gate opens the moment the last guard falls
-- rather than on the next map load.
--
-- The .blk layouts ship both doorways open, so a cache whose closedDoors
-- predates the two rows left the gates open all game: FieldDefaults has to
-- seed them the way it seeds the PrintTrashText bins.
--
-- Self-contained: `luajit tests/parity_hideout_gate.lua`; also globbed by
-- tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.ROCKET_HIDEOUT_B4F) then Data:load() end
local S = require("tests.harness").suite("parity hideout gate")
local check, eq = S.check, S.eq

local FieldDefaults = require("src.world.FieldDefaults")

local B4F, B1F = "ROCKET_HIDEOUT_B4F", "ROCKET_HIDEOUT_B1F"
local GUARD_0 = "EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0"
local GUARD_1 = "EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_1"
local B1F_GUARD = "EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4"

-- ---- the shipped layout ---------------------------------------------------
-- ReplaceTileBlock only ever writes; nothing in the .blk closes these, which
-- is why a missing closedDoors row reads as a permanently open gate.
local function shippedBlock(mapId, bx, by)
  local def = Data.maps[mapId]
  return def.blocks[by * def.width + bx + 1]
end
eq(shippedBlock(B4F, 12, 5), 0x0e, "B4F ships the lift doorway open (block $e)")
eq(shippedBlock(B1F, 12, 8), 0x0e, "B1F ships its doorway open (block $e)")

-- ---- the door rows -------------------------------------------------------
local doors = FieldDefaults.fieldValue(Data, "cardKeyDoors", "closedDoors")
check(type(doors) == "table", "field.cardKeyDoors.closedDoors resolves")

local b4 = doors[B4F] and doors[B4F][1]
check(b4 ~= nil, "B4F has a closed-door row")
if b4 then
  eq(b4.bx, 12, "B4F door x (lb bc, 5, 12)")
  eq(b4.by, 5, "B4F door y (lb bc, 5, 12)")
  eq(b4.block, 0x2d, "B4F closed block is $2d")
  eq(b4.open, 0x0e, "B4F open block is $e")
  eq(b4.event, nil, "B4F is not gated on a single event")
  eq(b4.events and b4.events[1], GUARD_0, "CheckBothEventsSet arg 1")
  eq(b4.events and b4.events[2], GUARD_1, "CheckBothEventsSet arg 2")
end

local b1 = doors[B1F] and doors[B1F][1]
check(b1 ~= nil, "B1F has a closed-door row")
if b1 then
  eq(b1.bx, 12, "B1F door x (lb bc, 8, 12)")
  eq(b1.by, 8, "B1F door y (lb bc, 8, 12)")
  eq(b1.block, 0x54, "B1F closed block is $54")
  eq(b1.open, 0x0e, "B1F open block is $e")
  eq(b1.event, B1F_GUARD, "B1F waits on the fifth grunt")
end

-- the events the rows name have to be the ones the guards actually set:
-- interact() writes trainerHeader().event on a win
eq(Data:trainerHeader("RocketHideoutB4F", 2).event, GUARD_0,
   "the (23,12) guard sets trainer_0")
eq(Data:trainerHeader("RocketHideoutB4F", 3).event, GUARD_1,
   "the (26,12) guard sets trainer_1")
eq(Data:trainerHeader("RocketHideoutB1F", 5).event, B1F_GUARD,
   "B1F's fifth grunt sets trainer_4")

-- ---- the stale cache the reporters have ----------------------------------
-- closedDoors exists but holds only the Silph rows, so fieldValue's per-path
-- fallback resolves the cache's table and finds no hideout floors.  seed()
-- fills map keys in place, which is what heals it.
do
  local silph = { { block = 0x54, bx = 2, by = 2, open = 0x0e,
                    event = "EVENT_SILPH_CO_2_UNLOCKED_DOOR1" } }
  local stale = { field = { cardKeyDoors = { doorTiles = { 24 },
                                             closedDoors = { SILPH_CO_2F = silph } } } }
  check(FieldDefaults.fieldValue(stale, "cardKeyDoors", "closedDoors")[B4F] == nil,
        "the stale cache really is missing the B4F row")
  FieldDefaults.seed(stale)
  local healed = FieldDefaults.fieldValue(stale, "cardKeyDoors", "closedDoors")
  eq(healed[B4F] and healed[B4F][1].block, 0x2d, "seed fills the B4F gate")
  eq(healed[B1F] and healed[B1F][1].block, 0x54, "seed fills the B1F gate")
  eq(healed.SILPH_CO_2F, silph, "and leaves the cache's own rows alone")
  eq(stale.field.cardKeyDoors.doorTiles[1], 24, "including the card-key tiles")
end

-- ---- the live floor ------------------------------------------------------
require("src.render.Font").load(Data)
local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local Sound      = require("src.core.Sound")
local OW         = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.party = { Pokemon.new(Data, "CHARMANDER", 20) }

local sfx = {}
local realPlay = Sound.play
Sound.play = function(_, id) sfx[#sfx + 1] = id end
local function goInsides()
  local n = 0
  for _, id in ipairs(sfx) do if id == "Go_Inside" then n = n + 1 end end
  return n
end

-- Map:setBlock writes through to the shared Data record every later suite in
-- this process reads, so both gates are put back at the bottom of the file
local restore = {}
local function remember(mapId, bx, by)
  restore[#restore + 1] = { mapId, bx, by, shippedBlock(mapId, bx, by) }
end
remember(B4F, 12, 5)
remember(B1F, 12, 8)

local function arrive(mapId, x, y)
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, mapId, x, y, "up")
  return Game.stack:top()
end

-- one cell south of the gate, the way a player walks up to it
local ow = arrive(B4F, 24, 13)
eq(ow.map:blockAt(12, 5), 0x2d, "arriving with both guards alive bars the gate")
check(not ow.map:isWalkableCell(24, 11) and not ow.map:isWalkableCell(25, 11),
      "and neither doorway cell can be stepped into")

sfx = {}
Game.save.flags[GUARD_0] = true
ow:afterBattle("win", {})
eq(ow.map:blockAt(12, 5), 0x2d, "one guard down leaves the gate barred")
eq(goInsides(), 0, "and plays no door sound")

Game.save.flags[GUARD_1] = true
ow:afterBattle("win", {})
eq(ow.map:blockAt(12, 5), 0x0e,
   "the second guard opens the gate without leaving the floor")
eq(goInsides(), 1, "with one SFX_GO_INSIDE")
check(ow.map:isWalkableCell(24, 11) and ow.map:isWalkableCell(25, 11),
      "the doorway cells are floor now")

-- EVENT_ROCKET_HIDEOUT_4_DOOR_UNLOCKED: the stamp is a transition, not a
-- per-load sound
ow:afterBattle("win", {})
eq(goInsides(), 1, "a later battle on the open floor is silent")
ow = arrive(B4F, 24, 13)
eq(ow.map:blockAt(12, 5), 0x0e, "re-entering the floor keeps it open")
eq(goInsides(), 1, "and does not re-play the door sound")

-- ---- B1F, the same seed row ---------------------------------------------
sfx = {}
ow = arrive(B1F, 24, 17)
eq(ow.map:blockAt(12, 8), 0x54, "B1F is barred until the fifth grunt")
Game.save.flags[B1F_GUARD] = true
ow:afterBattle("win", {})
eq(ow.map:blockAt(12, 8), 0x0e, "beating him opens it on the spot")
eq(goInsides(), 1, "with its own door sound")

for _, r in ipairs(restore) do
  local def = Data.maps[r[1]]
  def.blocks[r[3] * def.width + r[2] + 1] = r[4]
end
Sound.play = realPlay
while Game.stack:top() do Game.stack:pop() end

S.finish()
