package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end
love.graphics.polygon = love.graphics.polygon or function() end

local clock = 5000
love.timer.getTime = function() return clock end

local Kit = require("src.ui.kit.Kit")
local CartManifest = require("src.carts.CartManifest")
local CartStore = require("src.carts.CartStore")
local ModIndex = require("src.mods.ModIndex")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

local SHA = ("a1b2c3d4"):rep(8)

love.graphics.getDimensions = function() return 1280, 720 end
love.graphics.getPixelDimensions = function() return 1280, 720 end

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
  local cart, perr = CartManifest.parse(CART)
  check(cart ~= nil, "fixture parses: " .. tostring(perr))
  local ok, err = CartStore.install(CartManifest.encode(cart))
  check(ok ~= nil, "fixture installs: " .. tostring(err))
end

local Json = require("src.link.Json")
local ENTRY_RAW = {
  id = "wild_green", title = "Wild Green", author = "wild1walker",
  version = "1.75.0", base = "red", seal = "sealed",
  repo = "https://github.com/wild1walker/Gen1WildGreen",
  github = "wild1walker/Gen1WildGreen",
  mods = CART.mods, update_check = "ok",
  latest = { version = "1.75.0", tag = "v1.75.0",
             zip = { name = "wild_green-1.75.0.g1rcart",
                     url = "https://example.test/wild_green-1.75.0.g1rcart" } },
}
local FEED = ModIndex.parse(Json.encode({
  schema_version = 1, categories = { "GAMEPLAY" }, base_games = { "red" },
  mods = {}, carts = { ENTRY_RAW },
}))
check(FEED ~= nil and FEED.carts and FEED.carts[1] ~= nil, "the feed parses")
local ENTRY = FEED.carts[1]
check(ModIndex.isCart(ENTRY), "the index entry is a cart")

local realButton = Kit.button
local function drawButtons(imp)
  local byId = {}
  Kit.button = function(x, y, w, h, label, opts)
    if opts and opts.id then
      byId[opts.id] = { label = tostring(label), opts = opts,
                        x = x, y = y, w = w, h = h }
    end
    return realButton(x, y, w, h, label, opts)
  end
  local ok, err = pcall(LauncherView.draw, imp)
  Kit.button = realButton
  check(ok, "the frame draws: " .. tostring(err))
  return byId
end

local function press(imp, b)
  imp:runActions({ { key = b.opts.id, fn = b.opts.action,
                     keepArm = b.opts.keepArm } })
end

local function findLauncher()
  local imp = RomImporter.new(function() end, { launcher = true })
  imp.tab = "find"
  imp.modScope = nil
  imp.findLoaded = true
  imp._findFetch = nil
  imp.findSources = { { feed = "https://example.test/data/index.json",
                        base = "https://example.test/",
                        label = "example/index" } }
  imp.findIndex = { mods = FEED.mods, carts = FEED.carts, categories = {},
                    baseGames = ModIndex.baseGamesIn(FEED) }
  imp:_setFindKind("carts")
  return imp
end

do
  love.filesystem.createDirectory("mods/wild_green")
  love.filesystem.write("mods/wild_green/manifest.lua",
    "return { id = \"wild_green\", name = \"Wild Green\", version = \"1.0.0\" }")
  installCart()
  local imp = findLauncher()
  imp.ready.red = nil
  check(imp:_findInstalledCarts().wild_green ~= nil,
    "FIND reads the cart as installed")
  imp._findEntry = ENTRY

  local b = drawButtons(imp)
  check(b["findpop-inst"] ~= nil, "the popup keeps its install row")
  eq(b["findpop-inst"] and b["findpop-inst"].label, "Reinstall",
    "which reads Reinstall for the installed version")
  local del = b["findpop-del"]
  check(del ~= nil, "an installed cart's FIND popup offers Delete")
  if del then
    eq(del.label, "Delete", "the chip starts unarmed")
    eq(del.opts.kind, "danger", "and is drawn as a danger control")
    check(del.y == b["findpop-inst"].y, "it shares the install row")
    check(del.x >= b["findpop-inst"].x + b["findpop-inst"].w,
      "beside the install button, not over it")

    press(imp, del)
    check(CartStore.get("wild_green") ~= nil, "the first press does not delete")
    check(imp._findEntry == ENTRY, "and the popup stays open")
    local armed = drawButtons(imp)["findpop-del"]
    eq(armed and armed.label, "Sure?", "the chip asks to confirm")

    clock = clock + 0.5
    press(imp, armed or del)
    check(CartStore.get("wild_green") == nil, "the second press deletes the cart")
    eq(love.filesystem.getInfo(CartStore.fileFor("wild_green")), nil,
      "and its file is gone")
    eq(imp:_findInstalledCarts().wild_green, nil,
      "FIND no longer reads it as installed")
    eq(#imp:_ensureCarts("red"), 0, "the red cart list is empty")
    eq(imp._findEntry, nil, "the popup closes")
    eq(imp._cartPopup, nil, "no Custom Carts popup opens for an unready game")
    check(imp.findNotice ~= nil and imp.findNotice.ok == true,
      "FIND reports the delete")
    check(imp.findNotice and tostring(imp.findNotice.text)
      :find("Cart deleted", 1, true) ~= nil, "with the delete notice")
    check(love.filesystem.getInfo("mods/wild_green/manifest.lua") ~= nil,
      "the MODS-side mod sharing the id is untouched")

    imp._findEntry = ENTRY
    local after = drawButtons(imp)
    eq(after["findpop-inst"] and after["findpop-inst"].label, "Install",
      "the listing offers Install again")
    eq(after["findpop-del"], nil, "and no Delete for a cart that is gone")
  end
end

do
  local imp = findLauncher()
  imp._findEntry = ENTRY
  local b = drawButtons(imp)
  eq(b["findpop-del"], nil, "a cart that is not installed has no Delete")
end

do
  installCart()
  local imp = findLauncher()
  local realUninstall = CartStore.uninstall
  CartStore.uninstall = function() return nil, "could not delete the cart: busy" end
  imp:deleteCart("red", "wild_green", { from = "find" })
  CartStore.uninstall = realUninstall
  check(imp.findNotice ~= nil and imp.findNotice.ok == false,
    "a failed delete from FIND reports the error there")
  eq(imp._cartNotice, nil, "not on the Custom Carts popup")
  check(CartStore.get("wild_green") ~= nil, "and the cart is still installed")
  imp:deleteCart("red", "wild_green", { from = "find" })
  check(CartStore.get("wild_green") == nil, "cleanup")
end

do
  installCart()
  local imp = findLauncher()
  imp.tab = "red"
  imp.ready.red = true
  imp:_selectCart("red", "wild_green")
  eq(imp.activeCart.red, "wild_green", "the cart is selected for red")
  imp._cartPopup = "red"
  local b = drawButtons(imp)
  local del = b["cartpop-id-wild_green-delete"]
  check(del ~= nil, "the Custom Carts popup draws the cart's Delete chip")
  if del then
    clock = clock + 10
    press(imp, del)
    check(CartStore.get("wild_green") ~= nil, "one press only arms")
    clock = clock + 0.5
    press(imp, del)
    check(CartStore.get("wild_green") == nil, "the second press deletes it")
    eq(imp.activeCart.red, nil, "and deselects it")
    eq(imp._cartPopup, "red", "the popup reopens on that game")
    check(tostring(imp._cartNotice):find("Cart deleted", 1, true) ~= nil,
      "with the delete notice")
  end
end

do
  installCart()
  local imp = findLauncher()
  imp.ready.red = nil
  imp._findEntry = ENTRY
  imp.workState = "working"
  local del = drawButtons(imp)["findpop-del"]
  check(del ~= nil, "Delete is drawn during an import")
  if del then
    clock = clock + 10
    press(imp, del)
    clock = clock + 0.5
    press(imp, del)
    check(CartStore.get("wild_green") ~= nil,
      "a delete confirmed mid-import leaves the cart")
    check(imp.findNotice ~= nil and imp.findNotice.ok == false,
      "and says why on FIND instead of closing silently")
    check(imp.findNotice and tostring(imp.findNotice.text)
      :find("import", 1, true) ~= nil, "naming the running import")
  end
  imp.findNotice = nil
  imp._cartNotice = nil
  eq(imp:deleteCart("red", "wild_green"), false,
    "the popup path refuses mid-import too")
  check(imp._cartNotice ~= nil, "with a Custom Carts notice")
  imp.workState = nil

  local stale = { image = {}, width = 1, height = 1 }
  imp._cartridgeLabels = { ["cart:wild_green"] = stale,
                           ["gba:cart:wild_green"] = stale, red = stale }
  imp._gbaLabels = { ["gba:cart:wild_green"] = stale }
  eq(imp:deleteCart("red", "wild_green", { from = "find" }), true,
    "the delete runs once the import is done")
  eq(imp._cartridgeLabels["cart:wild_green"], nil,
    "the deleted cart's label art is dropped")
  eq(imp._cartridgeLabels["gba:cart:wild_green"], nil,
    "in the GBA shell cache key too")
  eq(imp._gbaLabels["gba:cart:wild_green"], nil, "and the GBA label cache")
  check(imp._cartridgeLabels.red == stale, "stock labels stay cached")
end

T.finish("cart delete from FIND (#2367)")
