-- Assertion driver: a KEY ITEM and an HM through the player's item PC.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1486_test.lua \
--     perl -e 'alarm 300; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- Issue #1486.  What the unit tier cannot show: the two screens a player
-- actually looks at.  .DepositItem (engine/events/pokecenter_pc.asm:504) reads
-- CANT_TOSS only to force x1 and skip .AskQuantity, and PlaceMenuItemQuantity
-- (engine/menus/menu_2.asm:18) draws no ×NN under such a row.
--
-- Shots land in /tmp/gold-bug1486:
--
--   01-key-items-pocket.png  the DEPOSIT chooser on the KEY ITEMS pocket
--   02-deposited.png         "Deposited 1 BICYCLE(S)." -- before the fix this
--                            is the unchanged pocket with no message at all
--   03-pc-list.png           the PC list: POTION with its ×03, BICYCLE and
--                            HM01 with no ×NN at all
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1486"
  local fails = 0

  local function ok(cond, msg)
    if cond then print("[1486] ok   " .. msg)
    else fails = fails + 1 print("[1486] FAIL " .. msg) end
    return cond
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  U.wait(45)
  local w = game.world
  assert(w and w.map, "gold world did not boot")
  local save = game.save

  local Bag = require("src.inventory.Bag")
  local Mon = require("src.battle.gen2.Mon")
  save.party = { Mon.new(game.data, "CYNDAQUIL", 10) }
  save.inventory = {}
  save.pcItems = { POTION = 3 }
  assert(Bag.add(save, "BICYCLE", 1, game.data), "BICYCLE into the bag")
  assert(Bag.add(save, "HM_CUT", 1, game.data), "HM01 into the bag")

  local function topId()
    local top = game.stack:top()
    return top and top.screenId or nil
  end

  assert(w:setMap("CHERRYGROVE_POKECENTER_1F", 4, 4, "up"),
    "setMap CHERRYGROVE_POKECENTER_1F failed")
  U.wait(5)
  local pcX, pcY
  for cy = 0, w.map.heightCells - 1 do
    for cx = 0, w.map.widthCells - 1 do
      if w.map:cellCollision(cx, cy) == 0x93 then pcX, pcY = cx, cy end
    end
  end
  assert(pcX, "no COLL_PC tile in the Pokecenter")
  assert(w:setMap("CHERRYGROVE_POKECENTER_1F", pcX, pcY + 1, "up"),
    "setMap onto the PC tile failed")
  U.wait(5)

  tap("a", 8)  -- PCScript
  tap("a", 4)  -- the turn-on line
  tap("down", 4)
  tap("a", 4)  -- <PLAYER>'s PC
  tap("a", 4)
  tap("a", 6)  -- both PokecenterPlayersPCText pages
  ok(topId() == "Gen2ItemPcMenu",
    "<PLAYER>'s PC opens the item PC (top: " .. tostring(topId()) .. ")")

  -- DEPOSIT ITEM -> the PACK chooser -> the KEY ITEMS pocket.
  tap("down", 4)
  tap("a", 6)
  tap("right", 4)  -- ITEM -> BALL
  tap("right", 4)  -- BALL -> KEY ITEMS
  U.shot(game, out .. "/01-key-items-pocket.png")
  tap("a", 6)      -- the BICYCLE row: x1, no prompt
  ok(save.pcItems.BICYCLE == 1,
    "the BICYCLE landed in the PC (" .. tostring(save.pcItems.BICYCLE) .. ")")
  ok(save.inventory.BICYCLE == nil,
    "and left the bag (" .. tostring(save.inventory.BICYCLE) .. ")")
  U.shot(game, out .. "/02-deposited.png")
  tap("a", 4)      -- the Deposited line

  -- The same, one pocket over: an HM.
  tap("right", 4)  -- KEY ITEMS -> TM/HM
  tap("a", 6)
  ok(save.pcItems.HM_CUT == 1,
    "HM01 landed in the PC (" .. tostring(save.pcItems.HM_CUT) .. ")")
  ok(save.inventory.HM_CUT == nil,
    "and left the bag (" .. tostring(save.inventory.HM_CUT) .. ")")
  tap("a", 4)
  tap("b", 6)      -- close the PACK

  -- WITHDRAW ITEM: the list is where PlaceMenuItemQuantity shows.
  tap("up", 4)
  tap("a", 6)
  U.shot(game, out .. "/03-pc-list.png")
  tap("a", 6)      -- the first row, x1 or the selector
  print(("[1486] %d failures"):format(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
