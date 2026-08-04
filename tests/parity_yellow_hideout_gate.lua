-- Parity (#650): Yellow's Rocket Hideout B4F lift gate is never barred.
--
-- Oracle: pokeyellow scripts/RocketHideoutB4F.asm has no
-- RocketHideoutB4FDoorCallbackScript at all -- the map script header goes
-- straight to EnableAutoTextBoxDrawing -- and the floor's two guard slots
-- are Jessie & James (data/maps/objects/RocketHideoutB4F.asm, object_event
-- 24, 10, SPRITE_JESSIE), who set EVENT_BEAT_ROCKET_HIDEOUT_4_JESSIE_JAMES.
-- EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0 / _1 do not exist in Yellow, so the
-- Red/Blue closedDoors row from #372 stamped a $2d block over a doorway
-- nothing in the game could ever re-open: Giovanni was unreachable.
-- pokeyellow scripts/RocketHideoutB1F.asm still calls its own
-- RocketHideoutB1FDoorCallbackScript, so only B4F is skipped.
--
-- The Red-imported cache is what this process has, and the two floors'
-- block layouts are the same in Yellow, so the version switch alone
-- reproduces the bug: what changes between the sections below is
-- GameVersion.get(), nothing else.
--
-- Self-contained: `luajit tests/parity_yellow_hideout_gate.lua`; also
-- globbed by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.ROCKET_HIDEOUT_B4F) then Data:load() end
local S = require("tests.harness").suite("parity Yellow hideout gate (#650)")
local check, eq = S.check, S.eq

local FieldDefaults = require("src.world.FieldDefaults")
local GameVersion   = require("src.core.GameVersion")

local B4F, B1F = "ROCKET_HIDEOUT_B4F", "ROCKET_HIDEOUT_B1F"
local GUARD_0 = "EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0"
local GUARD_1 = "EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_1"
local B1F_GUARD = "EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4"
-- the flag Yellow's pair actually writes (SetEvent at scripts/
-- RocketHideoutB4F.asm:274); no closedDoors row names it, by design
local JESSIE_JAMES = "EVENT_BEAT_ROCKET_HIDEOUT_4_JESSIE_JAMES"

-- ---- the skip row --------------------------------------------------------
-- through fieldValue, so a cache that carries closedDoors from an older
-- manifest but no skipMaps still resolves the built-in table
local skipMaps = FieldDefaults.fieldValue(Data, "cardKeyDoors", "skipMaps")
check(skipMaps and skipMaps.yellow and skipMaps.yellow[B4F],
      "Yellow skips the B4F lift gate")
check(not (skipMaps and skipMaps.yellow and skipMaps.yellow[B1F]),
      "and keeps B1F, which Yellow still has a callback for")

-- ---- the live floor, on a Yellow boot ------------------------------------
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

-- Map:setBlock writes through to the shared Data record every later suite
-- in this process reads, so both doorways are put back at the bottom
local restore = {}
local function remember(mapId, bx, by)
  local def = Data.maps[mapId]
  restore[#restore + 1] = { mapId, bx, by, def.blocks[by * def.width + bx + 1] }
end
remember(B4F, 12, 5)
remember(B1F, 12, 8)

local function arrive(mapId, x, y)
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, mapId, x, y, "up")
  return Game.stack:top()
end

local oldVersion = GameVersion.get()
GameVersion.set("yellow")

-- one cell south of the doorway, where the lift corridor starts
local ow = arrive(B4F, 24, 13)
eq(ow.map:blockAt(12, 5), 0x0e, "Yellow arrives on B4F with the gate open")
check(ow.map:isWalkableCell(24, 11) and ow.map:isWalkableCell(25, 11),
      "both doorway cells are floor from the first visit")
eq(goInsides(), 0, "and nothing plays the door sound on arrival")

-- beating the pair: the flag Yellow sets is not one the Red/Blue row
-- names, and afterBattle re-runs the callback on the same map instance
-- (home/trainers.asm EndTrainerBattle), which is where the stamp used to
-- slam the doorway shut without a warp anywhere near it
Game.save.flags[JESSIE_JAMES] = true
ow:afterBattle("win", {})
check(not Game.save.flags[GUARD_0] and not Game.save.flags[GUARD_1],
      "Jessie & James set neither Red/Blue guard flag")
eq(ow.map:blockAt(12, 5), 0x0e, "beating them leaves the gate open")
check(ow.map:isWalkableCell(24, 11) and ow.map:isWalkableCell(25, 11),
      "and the way through to Giovanni stays walkable")
eq(goInsides(), 0, "a gate that was never barred needs no door sound")

-- no map reload in between: the same OverworldState the battle returned
-- to is the one being read, and a reload does not change the answer
ow:stampClosedDoors()
eq(ow.map:blockAt(12, 5), 0x0e, "a direct callback run on the live floor is a no-op")
ow = arrive(B4F, 24, 13)
eq(ow.map:blockAt(12, 5), 0x0e, "re-entering the floor still finds it open")

-- ---- B1F, which Yellow did keep -----------------------------------------
sfx = {}
ow = arrive(B1F, 24, 17)
eq(ow.map:blockAt(12, 8), 0x54, "Yellow's B1F is still barred until the grunt")
Game.save.flags[B1F_GUARD] = true
ow:afterBattle("win", {})
eq(ow.map:blockAt(12, 8), 0x0e, "beating him opens it on the spot")
eq(goInsides(), 1, "with SFX_GO_INSIDE")

-- ---- the control: Red still stamps B4F ----------------------------------
-- without this the section above would pass just as well against a
-- closedDoors table someone had emptied outright
GameVersion.set("red")
sfx = {}
Game.save.flags[JESSIE_JAMES] = nil
ow = arrive(B4F, 24, 13)
eq(ow.map:blockAt(12, 5), 0x2d, "Red arrives on B4F with the gate barred")
Game.save.flags[GUARD_0] = true
Game.save.flags[GUARD_1] = true
ow:afterBattle("win", {})
eq(ow.map:blockAt(12, 5), 0x0e, "and its two guards still open it")
eq(goInsides(), 1, "with the door sound Yellow has no script for")

for _, r in ipairs(restore) do
  local def = Data.maps[r[1]]
  def.blocks[r[3] * def.width + r[2] + 1] = r[4]
end
Sound.play = realPlay
GameVersion.set(oldVersion)
while Game.stack:top() do Game.stack:pop() end

return S:finish()
