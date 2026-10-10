-- ../pokecrystal/engine/battle/core.asm:2607-2619
-- ../pokecrystal/engine/battle/core.asm:2915
-- ../pokecrystal/engine/events/whiteout.asm:1-21
local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-selfdestruct-2831"
  os.execute("mkdir -p '" .. out .. "'")
  local function shotPath(tag)
    return string.format("%s/2831_%s.png", out, tag)
  end
  local fails = 0
  local function ok(cond, msg)
    if not cond then fails = fails + 1 end
    print("[selfdestruct-2831] " .. (cond and "PASS " or "FAIL ") .. msg)
    return cond
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "the crystal world did not boot")
  local save, data = game.save, game.data
  local eevee = Mon.new(data, "EEVEE", 10)
  save.party = { eevee }

  world:warpToMapId("ROUTE_45", 10, 10, "down")
  for _ = 1, 120 do
    if not world:busy() then break end
    U.wait(1)
  end
  U.wait(10)
  local lossMap = world.map.id
  ok(lossMap == "ROUTE_45", "on route 45 (" .. tostring(lossMap) .. ")")

  local graveler = Mon.new(data, "GRAVELER", 30)
  graveler.moves = { { id = "SELFDESTRUCT", pp = 5, maxPp = 5 } }
  graveler.stats.speed = 999
  ok(world:startBattle({ wild = graveler }), "a wild graveler battle starts")
  local screen
  for _ = 1, 600 do
    U.wait(1)
    local top = game.stack:top()
    if top and top.battle then screen = top break end
  end
  if not ok(screen ~= nil, "the battle screen is up") then
    love.event.quit(1)
    return
  end

  local battle = screen.battle
  local faints, lastMessage, popped = {}, nil, false
  for _ = 1, 3000 do
    if game.stack:top() == screen then
      local message = screen.message
      if message ~= lastMessage then
        lastMessage = message
        local flat = message and message:gsub("%s+", " ")
        if flat and flat:find("fainted") then
          faints[#faints + 1] = flat
          U.wait(90)
          U.still(game, shotPath(("01_faint_%d"):format(#faints)))
        end
      end
      U.tap(game, "a")
      U.wait(2)
    else
      popped = true
      if not world:busy() and not world.mapSetup then break end
      U.wait(1)
    end
  end
  ok(battle.over, "the battle ended")
  ok(graveler.hp == 0, "the graveler fainted from selfdestruct")
  ok(battle.outcome == "lose",
    "outcome is a loss (" .. tostring(battle.outcome) .. ")")
  ok(popped, "the battle screen popped")
  ok(#faints == 2 and faints[1]:find("EEVEE") and faints[2]:find("GRAVELER"),
    "player faint line, then the graveler's (" .. table.concat(faints, " | ") .. ")")
  U.wait(20)
  ok(world.map.id ~= lossMap,
    "blacked out to the spawn point (" .. tostring(world.map.id) .. ")")
  ok((save.party[1].hp or 0) > 0, "the party was healed on whiteout")
  U.shot(game, shotPath("02_after_whiteout"))

  print("[selfdestruct-2831] " .. (fails == 0 and "PASS all claims" or
    (fails .. " claims failed")))
  love.event.quit(fails == 0 and 0 or 1)
end
