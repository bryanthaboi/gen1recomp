local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR")

return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print("RESULT native_surf_reload failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
  end
  local phase = os.getenv("BSA2759_PHASE") or "setup"
  local identity = os.getenv("POKEPORT_IDENTITY")
  if not check(identity and identity ~= "pokemon-love2d", "dedicated identity") then return finish() end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.phase == "boot", "boot reached") then return finish() end
  local SaveData = require("src.core.SaveData")
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Field = require("src.core.game3.field")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Sprites = require("src.core.game3.ow_sprites")
  local version = game.version or require("src.core.GameVersion").get()
  local rse = require("src.core.game3.profile").family(version) == "rse"
  local function stopScript()
    if Space.vm and Space.vm.stop then Space.vm:stop() end
    Field.unlock()
  end
  local function trace(label)
    print(string.format("STATE %s map=%s x=%s y=%s water=%s surfing=%s gfx=%s avatar=%s",
      label, tostring(Map.current), tostring(Player.cellX), tostring(Player.cellY),
      tostring(Collision.isWater(Player.cellX, Player.cellY)), tostring(Player.surfing),
      tostring(Sprites.playerGraphicsId(game, Player)), tostring(Sprites.avatarState(Player))))
  end
  if phase == "setup" then
    game:_handleBootAction({ action = "new_game", name = "RELOAD", gender = 0 })
    U.wait(240)
    local mapId
    for key in pairs(game.data.maps) do
      if key:find(rse and "SEAFLOOR_CAVERN_ENTRANCE" or "BERRY_FOREST", 1, true) then mapId = key break end
    end
    if not check(mapId ~= nil, "avatar water map present in ROM cache") then return finish() end
    require("src.core.game3.encounters").onStep = function() return nil end
    require("src.core.game3.trainer_sight").check = function() return false end
    Map.load(Runtime._mod, game, mapId, { x = 0, y = 0, facing = "down" })
    U.wait(90)
    stopScript()
    local layout = game.data.maps[mapId].midLayout
    local shore, water
    local dirs = { { "right", 1, 0 }, { "left", -1, 0 }, { "down", 0, 1 }, { "up", 0, -1 } }
    for y = 1, layout.height - 2 do
      for x = 1, layout.width - 2 do
        if Collision.isWater(x, y) then
          for _, dir in ipairs(dirs) do
            local sx, sy = x - dir[2], y - dir[3]
            if Collision.isWalkable(sx, sy) and not Collision.isWater(sx, sy) then
              shore, water = { x = sx, y = sy, facing = dir[1] }, { x = x, y = y }
              break
            end
          end
        end
        if shore then break end
      end
      if shore then break end
    end
    if not check(shore ~= nil, "water with adjacent walkable shore") then return finish() end
    if rse then
      Map.load(Runtime._mod, game, mapId, { x = water.x, y = water.y, facing = shore.facing })
      U.wait(90)
      stopScript()
      check(Player.surfing and not Player.underwater, "RSE ordinary cave water arrival restores Surf")
      check(U.still(game, DIR .. "/2761_01_cave_water_entry.png"), "cave-entry shot")
      local nextDir
      for _, dir in ipairs(dirs) do
        if Collision.isWater(water.x + dir[2], water.y + dir[3]) then nextDir = dir[1] break end
      end
      if not check(nextDir ~= nil, "cave water has next Surf cell") then return finish() end
      Player.facing, Player.turnArmed = nextDir, false
      check(Player.tryMove(nextDir, game, false) == "step", "RSE cave arrival moves without another Surf prompt")
      Player._onStepDone = function() end
      U.wait(40)
      check(Player.surfing, "RSE cave next step retains Surf")
      Map.load(Runtime._mod, game, mapId, shore)
      U.wait(90)
      stopScript()
      check(not Player.surfing and not Player.underwater, "RSE ordinary cave land arrival is on foot")
    end
    Map.load(Runtime._mod, game, mapId, shore)
    U.wait(90)
    stopScript()
    if not check(Player.startSurfing(game), "real player Surf hop starts") then return finish() end
    U.wait(90)
    trace("before_save")
    if not check(Player.surfing and Player.cellX == water.x and Player.cellY == water.y,
        "finished Surf hop is on selected water") then return finish() end
    check(U.still(game, DIR .. "/2759_01_before_save_surf.png"), "before-save shot")
    if not check(game:saveGame() == true, "Game3 native save succeeds") then return finish() end
    local saved = SaveData.load()
    check(saved and saved.engine == "game3" and saved.map == mapId
      and saved.x == water.x and saved.y == water.y, "native disk save retains exact water location")
    print("SAVE surfing=" .. tostring(saved and saved.surfing) .. " biking=" .. tostring(saved and saved.biking))
    check(saved and saved.surfing == true and saved.underwater == false, "native disk save captures completed Surf mode")
    check(love.filesystem.write("2759_witness.lua", SaveData.encode({ map = mapId,
      x = water.x, y = water.y, gfx = Sprites.playerGraphicsId(game, Player) })), "restart witness saved")
  else
    local witness = SaveData.decode(love.filesystem.read("2759_witness.lua"))
    if not check(witness ~= nil, "previous process supplied witness") then return finish() end
    game:_handleBootAction({ action = "continue" })
    for _ = 1, 4000 do
      if game.phase == "field" then break end
      U.wait(1)
    end
    if not check(game.phase == "field", "fresh process Continue reaches field") then return finish() end
    U.wait(240)
    trace("after_continue")
    check(Map.current == witness.map and Player.cellX == witness.x and Player.cellY == witness.y,
      "native Continue restores saved location")
    check(Collision.isWater(Player.cellX, Player.cellY), "saved location remains water")
    check(U.still(game, DIR .. "/2759_02_after_continue_surf.png"), "after-Continue shot")
    check(Player.surfing, "native Continue restores Surf flag")
    check(Sprites.playerGraphicsId(game, Player) == witness.gfx, "native Continue restores Surf graphics")
  end
  finish()
end
