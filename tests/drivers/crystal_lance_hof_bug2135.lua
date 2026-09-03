local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

local EVENT_LANCES_ROOM_ENTRANCE_CLOSED = 785
local EVENT_LANCES_ROOM_OAK_AND_MARY = 1887

return function(game)
  local fails = 0
  local function say(line) print("[2135] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map and world.vm and game.save) then
    say("FAIL the gen 2 world did not boot")
    love.event.quit(1)
    return
  end

  game.save.party = { Mon.new(game.data, "TYPHLOSION", 100) }
  world.events:set(EVENT_LANCES_ROOM_ENTRANCE_CLOSED, true)
  world.events:set(EVENT_LANCES_ROOM_OAK_AND_MARY, true)
  world.mapScenes = world.mapScenes or {}
  world.mapScenes.LANCES_ROOM = 1
  world:warpToMapId("LANCES_ROOM", 4, 6, "up")
  for _ = 1, 120 do if not world:busy() then break end U.wait(1) end
  U.wait(10)
  ok(world.map and world.map.id == "LANCES_ROOM", "standing in Lance's room")

  U.hold(game, "up", 8)
  for _ = 1, 120 do
    if world.vm:running() then break end
    U.wait(1)
  end
  ok(world.vm:running(), "the (4,5) coord event started the approach script")

  local screen
  for _ = 1, 1200 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.tap(game, "a")
    U.wait(2)
  end
  ok(screen ~= nil, "the Lance battle opened")
  if not screen then
    love.event.quit(1)
    return
  end
  for _ = 1, 6000 do
    if game.stack:top() ~= screen then break end
    for _, m in ipairs(screen.battle.enemyParty or {}) do m.hp = 0 end
    if screen.battle.enemy then screen.battle.enemy.hp = 0 end
    U.tap(game, "a"); U.wait(2)
  end
  ok(game.stack:top() ~= screen, "Lance went down")

  local masked, maskedShot, unmaskedInHof, shots = false, false, false, 0
  local frames = 0
  for _ = 1, 6000 do
    frames = frames + 1
    if world.map and world.map.id == "LANCES_ROOM" and world.playerMasked then
      masked = true
      if not maskedShot and not world.mapSetup then
        maskedShot = true
        U.shot(game, SHOT_DIR .. "/crystal_bug2135_01_player_gone.png")
        say("the shot must show an EMPTY doorway while Mary runs up")
      end
    end
    if world.map and world.map.id == "HALL_OF_FAME" then
      if not world.mapSetup then
        unmaskedInHof = not world.playerMasked
        U.wait(30)
        U.shot(game, SHOT_DIR .. "/crystal_bug2135_02_hof.png")
        break
      end
    elseif masked and shots < 3 and frames % 30 == 0 then
      shots = shots + 1
      U.shot(game, string.format("%s/crystal_bug2135_mary_%d.png", SHOT_DIR, shots))
    end
    if frames % 6 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  ok(masked, "disappear PLAYER masked the player before the warp")
  ok(world.map and world.map.id == "HALL_OF_FAME", "warpfacing reached HALL_OF_FAME")
  ok(unmaskedInHof, "and the load respawned the player there")

  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
