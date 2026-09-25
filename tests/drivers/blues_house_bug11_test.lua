-- Driver: issue #11 -- Blue's House wall Town Map phantom pickup + the
-- sell crash it causes.
--
-- In pokered the framed Town Map on the wall of Blue's House
-- (data/maps/objects/BluesHouse.asm BLUESHOUSE_TOWN_MAP) is a plain
-- text object -- talking to it prints _BluesHouseTownMapText
-- ("It's a big map! This is useful!") and nothing enters the bag.
-- The ROM object carries the 0x80 "has item payload" bit with a payload
-- id of 0 (ITEM_NONE), which our extractor copies through as item="0".
-- The engine's item-ball branch treated the truthy string "0" as a real
-- item, so pressing A picked up a bogus item "0" -- and selling that
-- unknown id later hard-crashed ShopMenu.sell (nil item def).
--
-- This driver reproduces both halves and asserts the correct Gen1
-- behavior, so it fails while the bug exists and passes once fixed.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Bag = require("src.inventory.Bag")
  local Screens = require("src.ui.Screens")

  local pass, fail = 0, 0
  local function check(ok, label)
    if ok then pass = pass + 1; U.log("PASS", label)
    else fail = fail + 1; U.log("FAIL", label) end
  end

  -- defensive: keep the pre-fix "<name> found 0!" box from erroring on a
  -- nil player name (the box never appears after the fix)
  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "RED"

  -- ---- Part 1: talking to the wall Town Map must not pick anything up ----
  U.teleport(game, "BLUES_HOUSE", 2, 6, "up")
  U.wait(5)
  local wallmap
  for _, n in ipairs(game.overworld.npcs) do
    if n.def and n.def.name == "BLUESHOUSE_TOWN_MAP" then wallmap = n end
  end
  check(wallmap ~= nil, "wall Town Map object present")
  if wallmap then
    game.overworld:talkTo(wallmap)
    U.wait(8)
    U.shot(game, DIR .. "/bh_1_wallmap.png")
    -- correct Gen1 behavior: nothing enters the bag
    check(game.save.inventory["0"] == nil, "no phantom item '0' in bag")
    check((game.save.inventory["0"] == nil) and (game.save.bagOrder == nil
          or not (function()
              for _, id in ipairs(game.save.bagOrder) do
                if id == "0" then return true end
              end
              return false
            end)()), "bag order has no '0' entry")
    -- dismiss whatever box is up
    for _ = 1, 4 do U.tap(game, "b"); U.wait(3) end
  end

  -- ---- Part 2: selling an unknown id must not crash ----------------------
  -- Seed a corrupted bag (a save that already picked up "0" before the fix,
  -- or any legacy/unknown id) and drive the mart SELL path over it.
  while game.stack:top() do game.stack:pop() end
  U.teleport(game, "PEWTER_MART", 2, 5, "left")
  U.wait(5)
  game.save.money = 3000
  -- known bag state regardless of whether part 1 leaked a phantom "0"
  game.save.inventory = {}
  game.save.bagOrder = nil
  Bag.add(game.save, "0", 1)
  check(game.save.inventory["0"] == 1, "seeded unknown item '0' in bag")

  -- open the clerk's BUY/SELL/QUIT menu exactly as the mart interaction does
  local Menu = require("src.ui.Menu")
  local ListMenu = require("src.ui.ListMenu")
  local TextBox = require("src.render.TextBox")
  local function waitTop(pred)
    for _ = 1, 600 do
      local top = game.stack:top()
      if top and pred(top) then return top end
      U.wait(1)
    end
  end
  Screens.push(game, "ShopMenu", {})
  local shop = waitTop(function(t)
    return getmetatable(t) == Menu and not t.hidden
  end)
  check(shop ~= nil, "clerk menu up after the greeting")
  U.wait(2)
  U.tap(game, "down") -- BUY -> SELL
  U.wait(4)
  U.tap(game, "a")    -- open the SELL list
  local sellList = waitTop(function(t) return getmetatable(t) == ListMenu end)
  U.wait(2)
  check(sellList and sellList.items ~= nil, "SELL list opened")
  U.shot(game, DIR .. "/bh_2_sell_list.png")

  if sellList and sellList.items then
    -- find the bogus "0" row
    local item, idx
    for i, it in ipairs(sellList.items) do
      if it.value == "0" then item, idx = it, i end
    end
    check(item ~= nil, "bogus '0' row present in sell list")
    if item then
      sellList.index = idx
      -- Invoke the real onChoose the ListMenu would call on A.  Before the
      -- fix this throws at math.floor(def.price/2) with def=nil; we catch
      -- it so the run reports the crash instead of hanging on love's error
      -- screen.
      local ok, err = pcall(sellList.onChoose, item, sellList)
      if not ok then
        fail = fail + 1
        U.log("FAIL", "selling '0' CRASHED: " .. tostring(err))
      else
        check(true, "selling '0' did not crash")
        -- nothing may be sold: the guard returns before any QuantityBox
        check(game.save.inventory["0"] == 1, "unknown item still in bag (not sold)")
        local box = game.stack:top()
        local said = {}
        if getmetatable(box) == TextBox then
          for _, page in ipairs(box.pages) do
            for _, line in ipairs(page) do said[#said + 1] = line end
          end
        end
        check(table.concat(said, " "):find("price") ~= nil,
              "clerk says the unsellable line")
      end
      U.wait(4)
      U.shot(game, DIR .. "/bh_3_sell_choose.png")
    end
  end

  U.log("RESULT", ("pass=%d fail=%d"):format(pass, fail))
  if fail == 0 then U.log("RESULT", "ALL PASS") else U.log("RESULT", "HAS FAILURES") end
  love.event.quit(fail == 0 and 0 or 1)
end
