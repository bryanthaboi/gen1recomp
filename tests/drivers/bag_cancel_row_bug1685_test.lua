-- Eye check on the CANCEL row at the foot of the item list (#1685).
-- PrintListMenuEntries prints ListMenuCancelText on the $ff terminator and
-- returns there (pokered home/list_menu.asm:371-372, 523-528), so the '▼'
-- at :518-522 never shares a page with CANCEL; DisplayListMenuIDLoop treats
-- that row as ExitListMenu (:105-110).  No POKEPORT_SPEED: the arrow and
-- the cursor step are being judged frame by frame.
--   POKEPORT_DRIVER=tests/drivers/bag_cancel_row_bug1685_test.lua POKEPORT_IDENTITY=bug1685 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local ListMenu = require("src.ui.ListMenu")
  local Menu = require("src.ui.Menu")
  local Screens = require("src.ui.Screens")
  local Strings = require("src.core.Strings")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end

  -- pokered data/maps/objects/PalletTown.asm: the house doors sit at (5,5)
  -- and (13,5) and the lab's at (12,11), so (10,8) is open ground.
  local TOWN, TOWN_X, TOWN_Y = "PALLET_TOWN", 10, 8
  -- six items: page one fills all four printed rows (so the '▼' is there to
  -- lose), and CANCEL lands on the page after it
  local STOCK = { "POTION", "ANTIDOTE", "BURN_HEAL", "ICE_HEAL",
                  "AWAKENING", "PARLYZ_HEAL" }

  for _, id in ipairs(STOCK) do
    check(id .. " exists as an item", game.data.items[id] ~= nil)
  end
  check("CANCEL has a string", Strings("CANCEL") ~= nil and Strings("CANCEL") ~= "")
  check("renderer is up", game.renderer ~= nil)

  game.save.player.name = "SEBAS"
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.inventory = {}
  game.save.bagOrder = nil
  local Bag = require("src.inventory.Bag")
  for i, id in ipairs(STOCK) do Bag.add(game.save, id, i) end

  local function stationary()
    for _ = 1, 60 do
      if not (game.overworld and game.overworld.player.moving) then break end
      coroutine.yield()
    end
  end

  local function openBag(where)
    stationary()
    U.tap(game, "start")
    U.wait(20)
    local menu = game.stack:top()
    if getmetatable(menu) == Menu then
      local ITEM = Strings("ITEM")
      for _ = 1, 20 do
        if menu.items[menu.index].label == ITEM then break end
        U.tap(game, "down")
        U.wait(6)
      end
      U.tap(game, "a")
      U.wait(20)
    end
    local bag = game.stack:top()
    if getmetatable(bag) ~= ListMenu then
      U.log("START -> ITEM did not reach the bag " .. where
            .. ", pushing BagMenu directly")
      bag = Screens.push(game, "BagMenu")
      U.wait(20)
    end
    return getmetatable(bag) == ListMenu and bag or nil
  end

  local function toTop(bag)
    for _ = 1, #bag.items + 2 do
      if bag.index == 1 then break end
      U.tap(game, "up")
      U.wait(6)
    end
  end

  U.teleport(game, TOWN, TOWN_X, TOWN_Y, "down")
  U.wait(20)

  local bag = openBag("in Pallet Town")
  if check("the bag opened", bag ~= nil) then
    check("six items are in it", #bag.items == #STOCK + 1)
    local last = bag.items[#bag.items]
    check("the row after the last item is the terminator's CANCEL",
          last ~= nil and last.cancel == true)
    check("and it carries no item id", last ~= nil and last.value == nil)
    check("labelled CANCEL", last ~= nil and last.label == Strings("CANCEL"))

    toTop(bag)
    check("page one shot reached disk",
          U.shot(game, SHOT_DIR .. "/bug1685_page_one.png"))

    -- walk down until the cursor stops moving: it must stop ON the CANCEL
    -- row, not one row short of it
    local before
    for _ = 1, #bag.items + 4 do
      before = bag.index
      U.tap(game, "down")
      U.wait(6)
      if bag.index == before then break end
    end
    check("the cursor walked all the way onto the CANCEL row",
          bag.items[bag.index] ~= nil and bag.items[bag.index].cancel == true)
    check("and stops there", bag.index == #bag.items)
    check("with the list scrolled to its last page",
          bag.scroll == #bag.items - (bag.cursorRows or bag.rows))
    check("cancel row shot reached disk",
          U.shot(game, SHOT_DIR .. "/bug1685_cancel_row.png"))

    -- A on CANCEL is ExitListMenu: the same exit B takes
    U.tap(game, "a")
    U.wait(25)
    local stillUp = false
    for _, s in ipairs(game.stack.states) do
      if s == bag then stillUp = true end
    end
    check("A on CANCEL closed the item list", not stillUp)
    check("and left no box or submenu over it",
          getmetatable(game.stack:top()) ~= ListMenu)
    check("after-cancel shot reached disk",
          U.shot(game, SHOT_DIR .. "/bug1685_after_cancel.png"))
  end

  for _ = 1, 10 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "b")
    U.wait(12)
  end

  -- an empty bag is a box with CANCEL alone, which is what the cart shows;
  -- the port used to print an invented "Nothing here." instead
  game.save.inventory = {}
  game.save.bagOrder = nil
  local empty = openBag("with an empty bag")
  if check("the empty bag still opens a box", empty ~= nil) then
    check("holding exactly one row", #empty.items == 1)
    check("and that row is CANCEL",
          empty.items[1] ~= nil and empty.items[1].cancel == true)
    check("empty bag shot reached disk",
          U.shot(game, SHOT_DIR .. "/bug1685_empty_bag.png"))
  end

  U.log("")
  if ok then
    U.log("the bag has been opened, walked to the bottom and cancelled for you.")
    U.log("in bug1685_page_one.png the four item names fill the box and the")
    U.log("down arrow sits in the lower right corner. in bug1685_cancel_row.png")
    U.log("CANCEL is one row below the last item, at the same left edge as the")
    U.log("names, with the cursor on it -- and that corner arrow must be GONE.")
    U.log("an arrow still painted next to CANCEL is the near miss here: it is")
    U.log("easy to miss in a still and it is the exact thing the terminator's")
    U.log("tail jump settles.")
    U.log("bug1685_empty_bag.png is an empty bag: a box with CANCEL and nothing")
    U.log("else. that replaces the port's old \"Nothing here.\" line, which the")
    U.log("cart never printed, so it is a deliberate change, not a regression.")
    U.log("the empty bag is on screen now; A or B should both close it.")
    U.log("yellow shares this list code: rerun with POKEPORT_VERSION=yellow and")
    U.log("a yellow identity and the three shots should look the same.")
  else
    U.log("a check above failed, so nothing on screen is worth reading yet.")
  end

  while true do
    coroutine.yield()
  end
end
