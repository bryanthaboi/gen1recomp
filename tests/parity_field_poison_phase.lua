-- Parity test (#1519): wStepCounter is zeroed by ClearVariablesOnEnterMap
-- (engine/overworld/clear_variables.asm:7), reached from EnterMap on a warp
-- and from the post-battle tail jump (home/overworld.asm:353), but never from
-- CheckMapConnections (home/overworld.asm:675), so a seam crossing keeps phase.
-- Self-contained; run via `luajit tests/parity_field_poison_phase.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity field poison phase")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local Game       = require("src.core.Game")
local Input      = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer   = require("src.render.Renderer")
local SaveData   = require("src.core.SaveData")
local Pokemon    = require("src.pokemon.Pokemon")
local OW         = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.party = { Pokemon.new(Data, "SQUIRTLE", 12) }

Game.stack:push(OW, "PALLET_TOWN", 5, 6, "down")
local ow = Game.stack:top()
Game.overworld = ow

local mon = Game.save.party[1]
mon.status = "PSN"

-- Walk until the poison bites, and report which step it was.
local function stepsToTick(limit)
  for i = 1, limit or 12 do
    local before = mon.hp
    ow:applyFieldPoison()
    if mon.hp < before then return i end
  end
  return nil
end

local function reheal()
  mon.hp = mon.stats.hp
  mon.status = "PSN"
end

-- ---- the free-running four-step cycle ------------------------------------
Game.save.poisonSteps = 0
eq(stepsToTick(), 4, "a cleared counter bites on the fourth step")
reheal()
eq(stepsToTick(), 4, "and every fourth step after that")

reheal()
Game.save.poisonSteps = 2
eq(stepsToTick(), 2, "a counter two steps into the cycle bites two steps later")

-- ---- a real map load re-phases it ----------------------------------------
reheal()
Game.save.poisonSteps = 2
ow:setMap("PALLET_TOWN", 5, 6, "down", { via = "warp" })
eq(Game.save.poisonSteps, 0, "setMap clears the counter")
eq(stepsToTick(), 4, "so the first tick after a warp is four steps out")

-- ---- a connection crossing does not --------------------------------------
reheal()
Game.save.poisonSteps = 2
ow:setMap("ROUTE_1", 9, 33, "up", { seamless = true, keepMusic = true })
eq(Game.save.poisonSteps, 2, "a seamless crossing leaves the counter alone")
eq(stepsToTick(), 2, "so the seam does not delay the tick")

-- ---- a battle return re-phases it ----------------------------------------
reheal()
Game.save.poisonSteps = 2
ow:afterBattle("win", { kind = "wild" })
eq(Game.save.poisonSteps, 0, "afterBattle clears the counter")
eq(stepsToTick(), 4, "so poison always bites four steps after a battle")

reheal()
Game.save.poisonSteps = 3
ow:afterBattle("win", { kind = "trainer", oppClass = "OPP_YOUNGSTER" })
eq(stepsToTick(), 4, "trainer battles re-phase it the same way")

S.finish()
