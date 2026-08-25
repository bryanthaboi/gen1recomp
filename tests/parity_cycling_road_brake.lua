-- Regression: holding A or B on Cycling Road stops the downhill roll (#255).
-- home/overworld.asm:1825 JoypadOverworld masks PAD_CTRL_PAD | PAD_B | PAD_A
-- before forcing PAD_DOWN, so a HELD A or B brakes the bike just like a held
-- direction.  The port read only the four directions, and A reached the roll
-- through an edge-only wasPressed, so it stalled for one fixed step and rolled
-- on.  Every case below holds the button with no press edge queued.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.ROUTE_17) then Data:load() end

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("parity cycling road brake")
local check, eq = S.check, S.eq

-- ground truth for the map the rule is keyed on
local fm = Data.field.forcedMovement
local slope = {}
for _, id in ipairs((fm and fm.slopeMaps) or {}) do slope[id] = true end
check(slope.ROUTE_17, "field.forcedMovement.slopeMaps names ROUTE_17")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.overworld = OW

-- (1,20) and the two cells below it are open road, so nothing but the brake
-- can explain a stalled roll.
local START_X, START_Y = 1, 20

-- Every case starts from a fresh state: a half-finished step would carry into
-- the next one and read as a roll that never stopped.
local function freshRoad()
  Input:reset()
  Game.save.onBike = true
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, "ROUTE_17", START_X, START_Y, "down")
  local ow = Game.stack:top()
  ow.player.moving = false
  ow.player.turnTimer = 0
  return ow
end

local ow = freshRoad()
eq(ow.map.id, "ROUTE_17", "standing on Cycling Road")
check(ow.map:isWalkableCell(START_X, START_Y + 1), "the cell south is open road")
check(ow.map:isWalkableCell(START_X, START_Y + 2), "and the one after it")

-- Hands off the pad: the bike rolls south on its own.
do
  local o = freshRoad()
  o:handleInput()
  check(o.player.moving, "no buttons held: the bike starts a step")
  eq(o.player.facing, "down", "the forced step faces south")
  eq(o.player.targetY, START_Y + 1, "and targets the cell below")
end

-- Held A / held B brake and keep braking.  120 fixed steps is ~2 seconds, far
-- past the single-step stall the old wasPressed edge gave.
local function heldBrakes(btn)
  local o = freshRoad()
  Input.state[btn] = true
  Input.pressed = {} -- HELD, with no press edge: the case A got wrong
  check(not Input:wasPressed(btn),
        ("holding %s queues no press edge"):format(btn:upper()))
  check(Input:isDown(btn), ("Input:isDown reports %s held"):format(btn:upper()))
  local moved = false
  for _ = 1, 120 do
    o:handleInput()
    o.player:update()
    if o.player.cellY ~= START_Y or o.player.moving then moved = true end
  end
  check(not moved,
        ("holding %s stops the roll for as long as it is held"):format(btn:upper()))
  eq(o.player.cellY, START_Y, ("player has not drifted south under %s"):format(btn:upper()))

  -- ...and letting go hands the hill back
  Input.state[btn] = false
  o:handleInput()
  check(o.player.moving,
        ("releasing %s resumes the roll immediately"):format(btn:upper()))
  Input:reset()
end

heldBrakes("a")
heldBrakes("b")

-- A held direction still wins: pokered's mask suppresses the simulated
-- PAD_DOWN, never the player's own step.
do
  local o = freshRoad()
  Input.state.a = true
  Input.state.up = true
  Input.pressed = {}
  o:handleInput()      -- first press turns; pokered turns in place too
  o.player.turnTimer = 0
  o:handleInput()
  check(o.player.moving, "holding A + UP still walks north")
  eq(o.player.facing, "up", "the held direction, not the forced south, wins")
  Input:reset()
end

-- Off the bike there is no roll to brake: the whole block is gated on
-- save.onBike, and Route 17 force-bikes anyway.
do
  local o = freshRoad()
  Game.save.onBike = false
  o:handleInput()
  check(not o.player.moving, "on foot the hill does not push at all")
  Game.save.onBike = true
end

-- Any other map is untouched: no forced step with or without the brake.
do
  Input:reset()
  Game.save.onBike = true
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, "PALLET_TOWN", 10, 8, "down")
  local o = Game.stack:top()
  o:handleInput()
  check(not o.player.moving, "PALLET_TOWN has no downhill pull")
  Input.state.a = true
  Input.pressed = {}
  o:handleInput()
  check(not o.player.moving, "and holding A there changes nothing")
  Input:reset()
  -- a scripted step now reads the live bike state (#1754), so do not leak
  -- the mount into whatever suite runs next
  Game.save.onBike = false
end

S.finish()
