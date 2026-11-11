local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_quest_log_surf_3126"
local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "3126 quest log surf and fly failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "3126 boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not check(session ~= nil, "3126 field reached") then return finish() end
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local Fade = require("src.ui.game3.fade")
  local Party = require("src.core.game3.party")
  local FE = require("src.core.game3.field_effects")
  local Ow = require("src.core.game3.ow_sprites")
  local QuestLog = require("src.ui.game3.quest_log")
  local QuestRecorder = require("src.core.game3.quest_log_recorder")
  local C = require("src.core.game3.constants").of(session.version)
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  local function waitFor(pred, limit)
    for _ = 1, limit do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function holdUntil(dir, pred, limit)
    local reached = false
    for _ = 1, limit do
      if pred() then reached = true break end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      U.wait(1)
    end
    game.input.state[dir] = false
    return reached or pred()
  end

  session.party = {}
  Party.giveMon(session, C:require("species", "SPECIES_PIDGEOT"), 40)

  local route = "FR_ROUTE_21_NORTH"
  Map.load(nil, game, route, { x = 10, y = 10, facing = "left" })
  local layout = game.data.maps[route].midLayout
  local occupied = {}
  for _, o in ipairs(Objects.forDraw()) do occupied[(o.cellX or -1) .. "," .. (o.cellY or -1)] = true end
  local wx, wy
  for y = 4, layout.height - 4 do
    for x = 8, layout.width - 4 do
      local ok = true
      for dx = -5, 0 do
        for dy = -2, 2 do
          if not Collision.isWater(x + dx, y + dy) or occupied[(x + dx) .. "," .. (y + dy)] then ok = false end
        end
      end
      if ok then wx, wy = x, y break end
    end
    if wx then break end
  end
  if not check(wx ~= nil, "3126 open water found on " .. route) then return finish() end
  Player.reset(wx, wy, "left")
  Player.surfing, Player.currentElevation, Player.elevation = true, 1, 1
  for _, o in ipairs(Objects.forDraw()) do o.sight = 0 end
  U.wait(30)
  if not check(holdUntil("left", function() return Player.cellX <= wx - 3 and not Player.moving end, 240),
      "3126 surfing three cells left") then return finish() end
  U.wait(40)
  local blobX, blobY = FE.surfBlobWorldPos()
  local liveDx, liveDy = blobX and blobX - Player.px, blobY and blobY - (Player.py + (Player.spriteYOffset or 0))
  check(U.still(game, DIR .. "/3126_01_overworld_surf_blob.png"), "3126 overworld surf shot")

  local function sceneFor(map)
    local scenes = session.questLog and session.questLog.scenes or {}
    for i = #scenes, 1, -1 do if scenes[i].map == map then return scenes[i], i end end
  end
  local surfScene = sceneFor(route)
  check(surfScene ~= nil and #surfScene.frames > 10, "3126 surf scene recorded")
  local framesAtFlyOut
  local realFlyOut = FE.startFlyOut
  FE.startFlyOut = function(...)
    local s = sceneFor(route)
    framesAtFlyOut = s and #s.frames
    return realFlyOut(...)
  end
  local dest = assert(Field.flyDestination("MAPSEC_PALLET_TOWN"))
  check(Field.flyTo("MAPSEC_PALLET_TOWN", session.party[1]), "3126 Fly starts")
  if not check(waitFor(function()
      return session.map == dest.map and not Field._flyLanding and not Field.locked and not Fade.active
    end, 3000), "3126 Fly landing finishes") then FE.startFlyOut = realFlyOut return finish() end
  FE.startFlyOut = realFlyOut
  U.wait(60)
  QuestRecorder.save(game)

  surfScene = sceneFor(route)
  local surfFrames, blobFrames, aligned = 0, 0, 0
  for _, f in ipairs(surfScene and surfScene.frames or {}) do
    local a = f.actors[1]
    if a and a.id == 255 then
      surfFrames = surfFrames + 1
      if a.surf then
        blobFrames = blobFrames + 1
        if a.surf.x == a.x - 8 then aligned = aligned + 1 end
      end
    end
  end
  check(surfFrames > 0 and blobFrames == surfFrames, "3126 every surfing sample carries the blob " .. blobFrames .. "/" .. surfFrames)
  check(aligned == blobFrames, "3126 recorded blob sits 8px left of the player like the overworld " .. aligned .. "/" .. blobFrames)
  check(liveDx == -8, "3126 overworld blob offset x=" .. tostring(liveDx) .. " y=" .. tostring(liveDy))
  local usedFly = false
  for _, e in ipairs(surfScene and surfScene.events or {}) do if e.key == "UsedFly" then usedFly = true end end
  check(usedFly, "3126 UsedFly event in the surf scene")
  check(framesAtFlyOut ~= nil and #surfScene.frames == framesAtFlyOut,
    "3126 no samples during fly-out " .. tostring(framesAtFlyOut) .. "->" .. tostring(surfScene and #surfScene.frames))

  local arrived = sceneFor(dest.map)
  local walkGid = Ow.playerGraphicsId(game)
  local first = arrived and arrived.frames[1] and arrived.frames[1].actors[1]
  check(arrived ~= nil and arrived.events[1].key == "ArrivedInLocation", "3126 Arrived scene recorded")
  check(first ~= nil and first.id == 255 and first.x == dest.x * 16 and first.y == dest.y * 16,
    "3126 first Arrived frame has the player standing on the landing cell")
  local rider = 0
  for _, f in ipairs(arrived and arrived.frames or {}) do
    local a = f.actors[1]
    if not a or a.id ~= 255 or a.graphicsId ~= walkGid or a.surf then rider = rider + 1 end
  end
  check(arrived ~= nil and rider == 0, "3126 Arrived scene has no rider or missing-player frames " .. rider)

  local playback = QuestLog.begin(session)
  if not check(playback ~= nil, "3126 recap playback begins") then return finish() end
  local surfIndex, arrivedIndex
  for i, s in ipairs(playback.scenes) do
    if s.map == route then surfIndex = i end
    if s.map == dest.map then arrivedIndex = i end
  end
  check(surfIndex ~= nil and arrivedIndex ~= nil, "3126 recap has the surf and Arrived scenes")
  local phase = game.phase
  game.questPlayback = playback
  game.phase = "quest_log"
  playback.index, playback.ticks = surfIndex or 1, 60
  local recapFrame = playback:frame()
  check(recapFrame and recapFrame.actors[1].surf ~= nil, "3126 recap frame carries the blob")
  local blobs = 0
  local realDraw = FE.drawSurfBlob
  FE.drawSurfBlob = function(...) blobs = blobs + 1 return realDraw(...) end
  check(U.still(game, DIR .. "/3126_02_recap_surf_blob.png"), "3126 recap surf shot")
  FE.drawSurfBlob = realDraw
  check(blobs > 0, "3126 recap draws the surf blob")
  playback.index, playback.ticks = arrivedIndex or 1, 0
  check(U.still(game, DIR .. "/3126_03_recap_arrived_no_rider.png"), "3126 recap Arrived shot")
  game.questPlayback = nil
  game.phase = phase
  finish()
end
