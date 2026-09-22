-- engine/events/pokemart.asm:159-169
-- engine/events/pokemart.asm:84-91
--   POKEPORT_DRIVER=tests/drivers/route_shop_buy_sell_bug2291.lua POKEPORT_VERSION=red love .
return function(game)
  local U = require("tests.drivers.util")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Menu = require("src.ui.Menu")

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function finish()
    U.log(failures == 0 and "PASS route_shop_buy_sell_bug2291"
          or ("FAIL route_shop_buy_sell_bug2291 (" .. failures .. " failures)"))
    love.event.quit(failures == 0 and 0 or 1)
    U.wait(600)
  end

  local function loadRouteShop()
    local f = assert(io.open("tests/drivers/route.lua", "r"))
    local src = f:read("*a")
    f:close()
    local function slice(from, to)
      local a = assert(src:find(from, 1, true), from)
      local b = assert(src:find(to, a, true), to)
      return src:sub(a, b - 1)
    end
    local body = table.concat({
      "local G, U, press, say, note, WD = ...",
      slice("local function top() return G.stack:top() end",
            "-- PokeBotBad's shop lists"),
      slice("local function qtyTo(want, tries)", "-- Free up bag slots"),
      slice("local function buyItem(id, qty, where)", "-- Back all the way out"),
      "return { buyItem = buyItem, sellItem = sellItem, isMenu = isMenu,",
      "  isList = isList, cursorTo = cursorTo, pressUntil = pressUntil }",
    }, "\n")
    local chunk = assert(loadstring(body, "=route.lua shops"))
    local said = {}
    local function say(...)
      local parts = { ... }
      for i = 1, #parts do parts[i] = tostring(parts[i]) end
      said[#said + 1] = table.concat(parts, " ")
      U.log("[route]", said[#said])
    end
    local function press(btn) U.tap(game, btn) end
    local function note() end
    return chunk(game, U, press, say, note, { keepItems = {} }), said
  end

  local ok, err = pcall(function()
    local R = loadRouteShop()
    game.save.money = 3000
    game.save.inventory = game.save.inventory or {}
    U.teleport(game, "PEWTER_MART", 2, 5, "left")
    U.wait(10)
    U.tap(game, "a")
    for _ = 1, 60 do
      if getmetatable(game.stack:top()) == Menu then break end
      U.tap(game, "a")
      U.wait(4)
    end
    if not check("the mart menu opens", R.isMenu()) then return end

    check("cursor on BUY", R.cursorTo("index", 1))
    U.tap(game, "a")
    U.wait(10)
    if not check("the buy list opens", R.pressUntil(R.isList, "a", 30)) then return end
    local money0 = game.save.money
    local have0 = (game.save.inventory or {}).POKE_BALL or 0
    local bought = R.buyItem("POKE_BALL", 3, "PEWTER_MART")
    U.shot(game, DIR .. "/2291_route_after_buy.png")
    check("route buyItem reports success", bought)
    check("route buyItem put 3 POKe BALLs in the bag",
          ((game.save.inventory or {}).POKE_BALL or 0) == have0 + 3)
    check("route buyItem paid 600", game.save.money == money0 - 600)
    check("route buyItem leaves the buy list on top", R.isList())

    for _ = 1, 10 do
      if R.isMenu() then break end
      U.tap(game, "b")
      U.wait(6)
    end
    if not check("back on the BUY/SELL menu", R.isMenu()) then return end
    local money1 = game.save.money
    local sold = R.sellItem("POKE_BALL")
    U.shot(game, DIR .. "/2291_route_after_sell.png")
    check("route sellItem reports success", sold)
    check("route sellItem emptied the POKe BALL stack",
          ((game.save.inventory or {}).POKE_BALL or 0) == 0)
    check("route sellItem was paid 300", game.save.money == money1 + 300)
    check("route sellItem returns to the BUY/SELL menu", R.isMenu())
  end)
  if not ok then check("driver error: " .. tostring(err), false) end
  finish()
end
