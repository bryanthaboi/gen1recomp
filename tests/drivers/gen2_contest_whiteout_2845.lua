-- ../pokecrystal/engine/events/whiteout.asm:9-25
-- ../pokecrystal/engine/events/std_scripts.asm:308-315
local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local BugContest = require("src.core.gen2.BugContest")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-contest-whiteout-2845"

return function(game)
  os.execute('mkdir -p "' .. SHOT_DIR .. '" 2>/dev/null')
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[2845] " .. (cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    print("[2845] " .. (fails == 0 and "all claims passed" or (fails .. " claims failed")))
    love.event.quit(fails == 0 and 0 or 1)
    while true do U.wait(60) end
  end
  local function mapId(world)
    return world.map and world.map.def and world.map.def.id
  end

  U.wait(45)
  local world, save = game.world, game.save
  if not ok(world and world.map and world.vm and save, "the world booted") then finish() end

  local lead = Mon.new(game.data, "SENTRET", 3)
  lead.hp = 1
  save.party = { lead }
  save.player = save.player or {}
  save.player.money = 3000
  BugContest.start(save)
  world:warpToMapId("NATIONAL_PARK", 10, 20, "down")
  U.wait(45)
  ok(mapId(world) == "NATIONAL_PARK", "standing in the park mid-contest")
  ok(BugContest.isActive(save), "the contest is running")

  local wild = Mon.new(game.data, "SCYTHER", 50)
  wild.moves = { { id = "QUICK_ATTACK", pp = 30, maxPp = 30 } }
  ok(world:startBattle({ wild = wild, contest = true }), "a contest battle started")
  local screen
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  if not ok(screen ~= nil and screen.contest, "the contest battle screen came up") then finish() end

  for _ = 1, 3000 do
    if game.stack:top() ~= screen then break end
    U.tap(game, "a")
    U.wait(3)
  end
  ok(screen.battle and screen.battle.outcome == "lose", "the battle ended in a loss")

  local atGate = false
  for _ = 1, 600 do
    if mapId(world) == "ROUTE_36_NATIONAL_PARK_GATE" then atGate = true break end
    U.wait(2)
  end
  ok(atGate, "the wipe warped to the national park gate, not a Pokecenter (map "
    .. tostring(mapId(world)) .. ")")
  U.wait(30)
  U.still(game, SHOT_DIR .. "/2845_01_gate_after_wipe.png")

  local deadline = love.timer.getTime() + 15
  while world.vm:running() and love.timer.getTime() < deadline do
    U.tap(game, "a")
    U.wait(3)
  end
  ok(not world.vm:running(), "the judging script ran to completion")
  ok(not BugContest.isActive(save), "the contest is over")
  ok(mapId(world) == "ROUTE_36_NATIONAL_PARK_GATE", "still at the gate after judging")
  ok(save.player.money == 3000, "the wallet was not halved")
  ok((save.party[1] and save.party[1].hp or 0) > 0, "the party was healed")
  U.wait(10)
  U.still(game, SHOT_DIR .. "/2845_02_judged_at_gate.png")
  finish()
end
