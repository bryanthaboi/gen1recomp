local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_fishing"

-- pokefirered/src/item_use.c:286 FieldUseFunc_Rod
local ITEM_OLD_ROD = 262
local PALLET = "FR_PALLET_TOWN"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS field_fishing")
    love.event.quit(0)
  else
    print("FAIL field_fishing failures=" .. failures)
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
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local Message = require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

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

  local Party = require("src.core.game3.party")
  if not (session.party and session.party[1]) then
    session.party = {}
    Party.giveMon(session, 7, 15)
  end

  -- pokefirered/src/item_use.c:324 ItemUseOnFieldCB_Rod
  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_OLD_ROD, 1)
  session.registeredItem = ITEM_OLD_ROD
  result(Bag.has(session.bag, ITEM_OLD_ROD, 1) == true, "the OLD ROD is in the bag")

  Map.load(nil, game, PALLET, { x = 7, y = 16, facing = "down" })
  place(7, 16, "down")
  U.wait(90)
  result(Space.mapId == PALLET, "stood on the Pallet Town beach, map=" .. tostring(Space.mapId))
  result(ItemUse.canFish() == true, "facing the sea, CanFish passes")
  U.shot(game, DIR .. "/field_fishing_01_before.png")

  U.tap(game, "select")
  U.wait(4)
  result(Field.isFishing() == true, "SELECT started the fishing task")
  result(Player.fishing == true, "the player has the rod out")
  U.wait(30)
  U.shot(game, DIR .. "/field_fishing_02_cast.png")

  for _ = 1, 400 do
    U.wait(1)
    local f = Field._fishing
    if Message.isOpen() and f and f.step == "dots" and f.dots >= math.min(3, f.required) then break end
  end
  result(Message.isOpen(), "the dot game box is open")
  local _, dotCount = Message.currentPage():gsub("·", "")
  local FrlgFont = require("src.ui.game3.frlg_font")
  -- pokefirered/src/field_player_avatar.c:1769
  result(dotCount >= 2 and FrlgFont.measure(Message.currentPage()) == (dotCount - 1) * 12 + FrlgFont.measure("·"),
    "dots sit 12 px apart: " .. dotCount .. " dots, width " .. FrlgFont.measure(Message.currentPage()))
  U.shot(game, DIR .. "/field_fishing_03_dots.png")

  local page = ""
  for _ = 1, 900 do
    U.wait(1)
    page = Message.currentPage()
    if page:find("nibble", 1, true) or page:find("hook", 1, true) then break end
  end
  -- pokefirered/src/field_player_avatar.c:1777 Fishing6
  local nibble = page:find("nibble", 1, true) ~= nil
  local hooked = page:find("hook", 1, true) ~= nil
  result(nibble or hooked, "the cast resolved (" .. tostring(page) .. ")")
  for _ = 1, 240 do
    if Message.isWaiting() then break end
    U.wait(1)
  end
  U.shot(game, DIR .. "/field_fishing_04_result.png")

  U.tap(game, "a")
  U.wait(30)
  if hooked then
    local Battle = require("src.core.game3.battle")
    for _ = 1, 240 do
      U.wait(2)
      if Battle.isActive() then break end
    end
    result(Battle.isActive() == true, "the bite started a wild battle")
    U.wait(180)
    U.shot(game, DIR .. "/field_fishing_05_battle.png")
  else
    result(Field.isFishing() == false, "the miss ended the task")
    result(Player.fishing == false, "the rod is put away")
    result(Field.locked == false, "field controls are free again")
  end

  finish()
end
