local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_fishing_pose_2419"

-- pokefirered/src/item_use.c:286 FieldUseFunc_Rod
local ITEM_OLD_ROD = 262
local MAPS = { "FR_PALLET_TOWN", "FR_VIRIDIAN_CITY", "FR_ROUTE_21_NORTH", "FR_VERMILION_CITY",
  "FR_CINNABAR_ISLAND", "FR_ROUTE_22", "FR_ROUTE_20" }

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS fishing_pose_2419")
    love.event.quit(0)
  else
    print("FAIL fishing_pose_2419 failures=" .. failures)
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

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  local Encounters = require("src.core.game3.encounters")
  local Message = require("src.ui.game3.message")
  local OwSprites = require("src.core.game3.ow_sprites")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local Party = require("src.core.game3.party")
  if not (session.party and session.party[1]) then
    session.party = {}
    Party.giveMon(session, 7, 15)
  end
  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_OLD_ROD, 1)
  session.registeredItem = ITEM_OLD_ROD

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

  local function findSpot(facing)
    for _, mapId in ipairs(MAPS) do
      local ok = pcall(Map.load, nil, game, mapId, { x = 5, y = 5, facing = facing })
      if ok then
        U.wait(20)
        local w, h = Collision._widthCells or 0, Collision._heightCells or 0
        for y = 4, h - 5 do
          for x = 5, w - 6 do
            if Collision.isWalkable(x, y) and not Collision.isWater(x, y)
                and not (Objects.blocks and Objects.blocks(x, y)) then
              place(x, y, facing)
              if ItemUse.canFish() then return mapId, x, y end
            end
          end
        end
      end
    end
    return nil
  end

  local realHasMons = Encounters.hasFishingMons
  Encounters.hasFishingMons = function() return false end

  local EXPECT = { down = 11, up = 7, left = 3, right = 3 }

  local function cast(facing, tag)
    local mapId, x, y = findSpot(facing)
    if not result(mapId ~= nil, tag .. " found fishable water facing " .. facing) then return end
    place(x, y, facing)
    U.wait(30)
    U.tap(game, "select")
    U.wait(2)
    if not result(Field.isFishing() == true, tag .. " cast started on " .. mapId .. " (" .. x .. "," .. y .. ")") then
      return
    end
    U.wait(24)
    local g, x2, y2 = Field.fishingPose()
    local abs = g and OwSprites.fishingAbsFrame(facing, g)
    result(abs == EXPECT[facing], string.format("%s rod out on frame %s (want %d)", tag, tostring(abs), EXPECT[facing]))
    local wx2, wy2 = OwSprites.fishingOffset(EXPECT[facing], facing)
    result(x2 == wx2 and y2 == wy2, string.format("%s aligned by (%s,%s)", tag, tostring(x2), tostring(y2)))
    U.shot(game, DIR .. "/2419_" .. tag .. "_rod_out.png")

    for _ = 1, 900 do
      U.wait(1)
      if Message.isOpen() and Message.currentPage():find("nibble", 1, true) then break end
    end
    result(Message.isOpen() and Message.currentPage():find("nibble", 1, true) ~= nil,
      tag .. " no-bite text is up")
    U.wait(8)
    U.shot(game, DIR .. "/2419_" .. tag .. "_put_away.png")
    U.wait(30)
    result(Player.fishing == false and Field.isFishing() == true,
      tag .. " rod put away while the text is still up")
    for _ = 1, 60 do
      if not Field.isFishing() then break end
      U.tap(game, "a")
      U.wait(6)
    end
    result(Field.isFishing() == false and Field.locked == false, tag .. " fishing ended, controls free")
  end

  for _, facing in ipairs({ "down", "up", "left", "right" }) do
    cast(facing, "male_" .. facing)
  end

  session.gender = "female"
  if game.save then game.save.gender = "female" end
  for _, facing in ipairs({ "down", "up", "left", "right" }) do
    cast(facing, "female_" .. facing)
  end
  local gid
  Field.startFishing(0)
  gid = OwSprites.playerGraphicsId(game)
  Field._fishing = nil
  Player.fishing = false
  Field.locked = false
  result(gid == 11, "female rod sheet is gid 11 (got " .. tostring(gid) .. ")")

  Encounters.hasFishingMons = realHasMons
  finish()
end
