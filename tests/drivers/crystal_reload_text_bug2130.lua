local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2130] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map and world.vm and game.save) then
    say("FAIL the crystal world did not boot")
    love.event.quit(1)
    return
  end

  game.save.party = { Mon.new(game.data, "TYPHLOSION", 90) }
  world.mapScenes = world.mapScenes or {}
  world.mapScenes.WILLS_ROOM = 1
  world:warpToMapId("WILLS_ROOM", 5, 8, "up")
  for _ = 1, 120 do if not world:busy() then break end U.wait(1) end
  U.wait(10)
  ok(world.map and world.map.id == "WILLS_ROOM", "standing in Will's room")
  U.shot(game, SHOT_DIR .. "/crystal_bug2130_00_room.png")

  local started = world.vm:start({
    { op = "loadtrainer", class = 11, member = 1 },
    { op = "startbattle" },
    { op = "reloadmapafterbattle" },
    { op = "opentext" },
    { op = "writetext", text = "60:4644" },
    { op = "waitbutton" },
    { op = "closetext" },
    { op = "end" },
  })
  ok(started, "the battle-then-text script started")

  local screen
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  ok(screen ~= nil, "the trainer battle opened")
  if not screen then
    love.event.quit(1)
    return
  end
  for _ = 1, 3000 do
    if game.stack:top() ~= screen then break end
    for _, m in ipairs(screen.battle.enemyParty or {}) do m.hp = 0 end
    if screen.battle.enemy then screen.battle.enemy.hp = 0 end
    U.tap(game, "a"); U.wait(2)
  end
  ok(game.stack:top() ~= screen, "the battle screen popped")
  say("battle popped at frame " .. U.frame() .. " fade=" .. tostring(world.fade)
    .. " mapSetup=" .. tostring(world.mapSetup and world.mapSetup.phase))

  local sawFade, boxFrame, boxFade, boxSetup = false, nil, nil, nil
  for _ = 1, 240 do
    if world.mapSetup then sawFade = true end
    local top = game.stack:top()
    if world.textbox or (top and top.text and not top.battle) then
      boxFrame = U.frame()
      boxFade, boxSetup = world.fade, world.mapSetup and world.mapSetup.phase
      break
    end
    U.wait(1)
  end
  ok(sawFade, "FadeInFromWhite ran after the battle")
  ok(boxFrame ~= nil, "the after-battle text box opened")
  ok(boxFade == nil, "no white sheet under the text box (fade="
    .. tostring(boxFade) .. ")")
  ok(boxSetup == nil, "the map setup chain finished before the box (phase="
    .. tostring(boxSetup) .. ")")
  U.wait(4)
  U.shot(game, SHOT_DIR .. "/crystal_bug2130_01_text.png")
  say("the shot must show Will's room and both sprites behind the text box")
  U.wait(20)
  U.shot(game, SHOT_DIR .. "/crystal_bug2130_02_text.png")

  for _ = 1, 300 do
    if not world.vm:running() then break end
    U.tap(game, "a")
    U.wait(4)
  end
  ok(not world.vm:running(), "the script ran to completion")
  U.shot(game, SHOT_DIR .. "/crystal_bug2130_03_end.png")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
