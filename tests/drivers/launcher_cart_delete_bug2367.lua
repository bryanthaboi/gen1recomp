return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local CartManifest = require("src.carts.CartManifest")
  local CartStore = require("src.carts.CartStore")
  local ModIndex = require("src.mods.ModIndex")
  local Json = require("src.link.Json")
  local Kit = require("src.ui.kit.Kit")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/cartdel2367"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(2)

  local failed = false
  local function pass(label) print("PASS " .. label) end
  local function fail(label, why)
    failed = true
    print("FAIL " .. label .. (why and (": " .. tostring(why)) or ""))
  end
  local function expect(cond, label, why)
    if cond then pass(label) else fail(label, why) end
  end

  local SHA = ("a1b2c3d4"):rep(8)
  local function pin(id, repo)
    return { id = id, source = "github", repo = repo, version = "1.0.0",
             sha256 = SHA }
  end
  local CART = {
    id = "wild_green", title = "Wild Green", version = "1.75.0",
    author = "wild1walker", shell = "#3a8f3a", base = "red", seal = "sealed",
    mods = { pin("wild_green", "wild1walker/Gen1MakeItGreen"),
             pin("wg_music", "wild1walker/wg-music"),
             pin("wg_items", "wild1walker/wg-items"),
             pin("wg_maps", "wild1walker/wg-maps") },
  }
  local function installCart()
    local cart = CartManifest.parse(CART)
    return cart and CartStore.install(CartManifest.encode(cart))
  end

  local FEED = ModIndex.parse(Json.encode({
    schema_version = 1, categories = { "GAMEPLAY" }, base_games = { "red" },
    mods = {},
    carts = { {
      id = "wild_green", title = "Wild Green", author = "wild1walker",
      version = "1.75.0", base = "red", seal = "sealed",
      repo = "https://github.com/wild1walker/Gen1WildGreen",
      mods = CART.mods, update_check = "ok",
      latest = { version = "1.75.0", tag = "v1.75.0",
                 zip = { name = "wild_green-1.75.0.g1rcart",
                         url = "https://example.invalid/wild_green.g1rcart" } },
    } },
  }))
  local ENTRY = FEED and FEED.carts and FEED.carts[1]

  pcall(CartStore.uninstall, "wild_green")
  expect(installCart(), "cart_installed")

  local imp = RomImporter.new(function() end, { launcher = true })
  imp._refreshFindSources = function() end
  imp._refreshFind = function() end
  imp._pumpFindFetch = function() end
  imp._findFetch = nil
  imp.findSources = { { feed = "https://example.invalid/data/index.json",
                        base = "https://example.invalid/",
                        label = "example/index" } }
  imp.findIndex = { schemaVersion = 1, categories = {}, mods = FEED.mods,
                    carts = FEED.carts, baseGames = ModIndex.baseGamesIn(FEED) }
  imp.findLoaded = true
  imp:_switchTab("find")
  imp:_setFindKind("carts")
  imp.ready.red = nil
  U.wait(3)

  local buttons = {}
  local realButton = Kit.button
  Kit.button = function(x, y, w, h, label, opts)
    if opts and opts.id then
      buttons[opts.id] = { label = tostring(label), opts = opts }
    end
    return realButton(x, y, w, h, label, opts)
  end

  local pending = nil
  love.draw = function()
    buttons = {}
    imp:draw()
    if pending then
      local path = pending
      pending = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then f:write(imagedata:encode("png"):getString()) f:close() end
      end)
    end
  end
  local function step(n)
    for _ = 1, n do
      imp:update(1 / 60)
      coroutine.yield()
    end
  end
  local function shot(name)
    pending = dir .. "/" .. name
    for _ = 1, 90 do
      if not pending then break end
      step(1)
    end
    step(3)
    local f = io.open(dir .. "/" .. name, "rb")
    U.log(f and "shot" or "FAIL shot", name)
    if f then f:close() end
  end
  local function press(id)
    local b = buttons[id]
    if not b then return false end
    imp:runActions({ { key = id, fn = b.opts.action, keepArm = b.opts.keepArm } })
    return true
  end

  imp._findEntry = ENTRY
  step(4)
  local del = buttons["findpop-del"]
  expect(del ~= nil and del.label == "Delete", "find_popup_has_delete",
    del and del.label)
  expect(buttons["findpop-inst"] and buttons["findpop-inst"].label == "Reinstall",
    "find_popup_keeps_reinstall")
  shot("2367_01_find_popup_delete.png")

  expect(press("findpop-del"), "find_delete_first_press")
  step(4)
  expect(buttons["findpop-del"] and buttons["findpop-del"].label == "Sure?",
    "find_delete_armed")
  expect(CartStore.get("wild_green") ~= nil, "find_first_press_keeps_cart")
  shot("2367_02_find_delete_armed.png")

  expect(press("findpop-del"), "find_delete_second_press")
  step(4)
  expect(CartStore.get("wild_green") == nil, "find_delete_removed_cart")
  expect(imp._findEntry == nil and imp._cartPopup == nil, "find_popup_closed")
  expect(imp.findNotice and imp.findNotice.ok == true, "find_notice_ok")
  step(40)
  shot("2367_03_find_cart_deleted.png")

  imp._findEntry = ENTRY
  step(4)
  expect(buttons["findpop-inst"] and buttons["findpop-inst"].label == "Install"
    and buttons["findpop-del"] == nil, "find_popup_back_to_install")
  imp._findEntry = nil

  expect(installCart(), "cart_reinstalled")
  imp:_refreshCarts("red")
  imp.ready.red = true
  imp:_switchTab("red")
  imp._cartPopup = "red"
  step(4)
  local cp = buttons["cartpop-id-wild_green-delete"]
  expect(cp ~= nil, "cart_popup_has_delete")
  step(40)
  shot("2367_04_cart_popup_delete.png")
  press("cartpop-id-wild_green-delete")
  step(4)
  press("cartpop-id-wild_green-delete")
  step(4)
  expect(CartStore.get("wild_green") == nil, "cart_popup_delete_removed_cart")
  shot("2367_05_cart_popup_after.png")

  Kit.button = realButton
  U.log("done")
  love.event.quit(failed and 1 or 0)
end
