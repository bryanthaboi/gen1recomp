local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_fish_surf_bike_2781"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS fish_surf_bike_2781")
    love.event.quit(0)
  else
    print("FAIL fish_surf_bike_2781 failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local Encounters = require("src.core.game3.encounters")
  local FieldMoves = require("src.core.game3.field_moves")
  local Ow = require("src.core.game3.ow_sprites")

  local rse = FieldMoves.isRse()
  local tag = rse and "em" or "fr"
  local mapId = rse and "EM_ROUTE104" or "FR_ROUTE_21_NORTH"
  if not result(pcall(Map.load, nil, game, mapId, { x = 5, y = 5, facing = "down" }), tag .. " loaded " .. mapId) then
    return finish()
  end
  U.wait(30)

  local function place(x, y, facing)
    Player.moving = false
    Player.progress = 0
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function free(x, y) return not (Objects.blocks and Objects.blocks(x, y)) end

  local function findSpot(onWater)
    local w, h = Collision._widthCells or 0, Collision._heightCells or 0
    for y = 2, h - 3 do
      for x = 2, w - 3 do
        local here = Collision.isWater(x, y)
        if free(x, y) and ((onWater and here) or (not onWater and Collision.isWalkable(x, y) and not here))
            and Collision.isWater(x, y + 1) then
          return x, y
        end
      end
    end
  end

  local fishGid
  local avatars = Ow.avatars()
  if avatars then fishGid = Ow.avatarGraphicsId("FISHING", false, avatars) end
  fishGid = fishGid or (require("src.import.gba.versions").OW_PLAYER_MALE_FISH or 4)

  local realHasMons = Encounters.hasFishingMons
  Encounters.hasFishingMons = function() return false end

  local function cast(label, setup, before)
    local x, y = findSpot(label == "surf")
    if not result(x ~= nil, tag .. " " .. label .. " spot found") then return end
    place(x, y, "down")
    setup()
    U.wait(20)
    result(Ow.playerGraphicsId(game) == before, string.format("%s %s idle gid %s (want %s)", tag, label,
      tostring(Ow.playerGraphicsId(game)), tostring(before)))
    if not result(Field.startFishing(0), tag .. " " .. label .. " cast started") then return end
    for _ = 1, 40 do U.wait(1) end
    local gid = Ow.playerGraphicsId(game)
    result(gid == fishGid, string.format("%s %s rod out uses fishing gid %s (got %s)", tag, label,
      tostring(fishGid), tostring(gid)))
    U.still(game, DIR .. "/2781_" .. tag .. "_" .. label .. "_rod_out.png")
    for _ = 1, 900 do
      U.wait(1)
      if not Player.fishing then break end
    end
    U.wait(4)
    gid = Ow.playerGraphicsId(game)
    result(gid == before, string.format("%s %s rod away restores gid %s (got %s)", tag, label,
      tostring(before), tostring(gid)))
    for _ = 1, 60 do
      if not Field.isFishing() then break end
      U.tap(game, "a")
      U.wait(6)
    end
    result(not Field.isFishing() and not Field.locked, tag .. " " .. label .. " fishing ended")
  end

  Player.surfing = true
  local surfGid = Ow.playerGraphicsId(game)
  Player.surfing = false
  Player.biking = true
  Player.bikeType = "mach"
  local bikeGid = Ow.playerGraphicsId(game)
  Player.biking = false

  cast("surf", function() Player.surfing = true end, surfGid)
  Player.surfing = false
  cast("bike", function() Player.biking = true Player.bikeType = "mach" end, bikeGid)
  Player.biking = false

  Encounters.hasFishingMons = realHasMons
  finish()
end
