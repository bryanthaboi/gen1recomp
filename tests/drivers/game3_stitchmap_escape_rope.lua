local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchmap_escape_rope"

-- pokefirered/src/item_use.c:622 ItemUseOutOfBattle_EscapeRope
-- pokefirered/src/item_use.c:634 ItemUseOnFieldCB_EscapeRope
local ITEM_ESCAPE_ROPE = 85
local CAVE = "FR_MT_MOON_1F"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchmap_escape_rope")
    love.event.quit(0)
  else
    print("FAIL stitchmap_escape_rope failures=" .. failures)
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
  local Bag = require("src.core.game3.bag")
  local Party = require("src.core.game3.party")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Message = require("src.ui.game3.message")
  local Field = require("src.core.game3.field")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 7, 15)
  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_ESCAPE_ROPE, 1)
  session.healMap = "FR_PLAYERS_HOUSE_1F"
  session.healX, session.healY = 8, 5

  Map.load(nil, game, CAVE, { x = 5, y = 5, facing = "down" })
  Player.moving = false
  Player.progress = 0
  Player.cellX, Player.cellY = 5, 5
  Player.px, Player.py = 5 * 16, 5 * 16
  Player.targetX, Player.targetY = 5, 5
  U.wait(90)
  if not result(Space.mapId == CAVE, "stood in Mt Moon 1F, map=" .. tostring(Space.mapId)) then
    return finish()
  end

  U.tap(game, "start")
  U.wait(30)
  for _ = 1, 12 do
    local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
    if e and e.id == "bag" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  U.tap(game, "a")
  U.wait(60)
  for _ = 1, 5 do
    if BagMenu.currentPocket() == "ITEMS" then break end
    U.tap(game, "left")
    U.wait(15)
  end
  for _ = 1, 24 do
    if not BagMenu.isOpen() then break end
    local want
    for i, r in ipairs(BagMenu.list() or {}) do
      if r.id == ITEM_ESCAPE_ROPE then want = i end
    end
    if not want or BagMenu.cursor == want then break end
    U.tap(game, (BagMenu.cursor > want) and "up" or "down")
    U.wait(8)
  end
  local row = BagMenu.isOpen() and BagMenu.list()[BagMenu.cursor]
  if not result(row and row.id == ITEM_ESCAPE_ROPE, "bag cursor on the ESCAPE ROPE") then
    return finish()
  end

  U.tap(game, "a")
  U.wait(25)
  U.tap(game, "a")
  for _ = 1, 300 do
    if not BagMenu.isOpen() and Message.isOpen() and not Message.isTyping() then break end
    U.wait(1)
  end

  -- pokefirered/src/new_menu_helpers.c:641 DisplayItemMessageOnField
  local page = (Message.isOpen() and Message.currentPage()) or ""
  result(BagMenu.isOpen() == false, "SetUpItemUseCallback faded the bag out first")
  result(StartMenu.isOpen() == false, "and the START menu went with it")
  result(Message.isOpen() == true and page:find("ESCAPE ROPE", 1, true) ~= nil,
    "gText_PlayerUsedVar2 is on the field box (" .. tostring(page) .. ")")
  result(Space.mapId == CAVE, "and nothing warped yet, map=" .. tostring(Space.mapId))
  U.shot(game, DIR .. "/escape_rope_01_message.png")

  -- pokefirered/src/item_use.c:642 Task_UseDigEscapeRopeOnField
  local CaveTransition = require("src.ui.game3.cave_transition")
  local realCaveStart = CaveTransition.start
  local caveKinds = {}
  CaveTransition.start = function(kind, ...)
    caveKinds[#caveKinds + 1] = kind
    return realCaveStart(kind, ...)
  end
  U.tap(game, "a")
  for _ = 1, 600 do
    if Space.mapId ~= CAVE and not Message.isOpen() then break end
    U.wait(1)
  end
  U.wait(90)
  result(Message.isOpen() == false, "the field box closed behind the warp")
  result(Space.mapId == "FR_PLAYERS_HOUSE_1F",
    "the rope warped to the last heal spot, map=" .. tostring(Space.mapId))
  result(Player.cellX == 8 and Player.cellY == 5,
    "at (8,5), got (" .. Player.cellX .. "," .. Player.cellY .. ")")
  result(Bag.get(session.bag, ITEM_ESCAPE_ROPE) == 0, "the rope was consumed")
  CaveTransition.start = realCaveStart
  -- pokefirered/src/fldeff_flash.c:236 TryDoMapTransition
  result(caveKinds[1] == "exit", "the rope out of Mt Moon played FlashTransition_Exit ("
    .. table.concat(caveKinds, ",") .. ")")
  U.shot(game, DIR .. "/escape_rope_02_landed.png")

  U.tap(game, "down")
  U.wait(40)
  result(Field.locked == false, "the field is unlocked again")

  finish()
end
