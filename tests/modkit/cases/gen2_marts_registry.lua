package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Mart = require("src.ui.gen2.MartMenu")
local Unified = require("src.mods.UnifiedContent")

local BODY = [[local mod = ...
local marts = mod.content.marts
assert(marts:get("0")[1] == "POTION")
marts:patch("0", { "ULTRA_BALL" })
assert(#marts:get("0") == 1 and marts:get("0")[1] == "ULTRA_BALL")
marts:patch("1", {})
assert(#marts:get("1") == 0)
marts:remove("33")
assert(marts:get("33") == nil)
marts:patch("bargain", { { item = "NUGGET", price = 500 } })
assert(#marts:get("bargain") == 1 and marts:get("bargain")[1].price == 500)
for _, id in ipairs({ "00", "-1", "34", "MART_CHERRYGROVE", "generation" }) do
  assert(not pcall(function() marts:patch(id, {}) end))
end
assert(not pcall(function() marts:patch("0", { [2] = "POTION" }) end))
assert(not pcall(function() marts:patch("0", { __append = { "POTION" } }) end))
assert(not pcall(function() marts:patch("bargain", { { item = "NUGGET", price = -1 } }) end))
assert(not pcall(function() marts:patch("bargain", { "NUGGET" }) end))
for id in marts:each() do assert(id ~= "generation" and id ~= "source") end
]]

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  for _, api in ipairs({ 2, 3 }) do
    T.sdk.captureRuntime()
    local files = {}
    local function add(id, body)
      files["mods/" .. id .. "/manifest.json"] = ('{"id":"%s","name":"%s",'
        .. '"version":"1.0.0","api":%d,"games":["all"],"entry":"main.lua"}')
        :format(id, id, api)
      files["mods/" .. id .. "/main.lua"] = body
    end
    add("a_good", BODY)
    add("b_failed", 'local mod = ...; mod.content.marts:patch("0", {"POKE_BALL"}); error("rollback fixture")')
    local stock = { generation = 2, source = "fixture", lists = {
      [1] = { "POTION", "ANTIDOTE" }, [2] = { "POKE_BALL" }, [34] = { "POTION" },
    }, bargain = { { item = "NUGGET", price = 4500 }, { item = "PEARL", price = 650 } } }
    local data = { gen2Marts = stock, items = {} }
    for _, id in ipairs({ "POTION", "ANTIDOTE", "POKE_BALL", "ULTRA_BALL", "NUGGET", "PEARL" }) do
      data.items[id] = { id = id, name = id, price = 1200, pocket = "ITEM" }
    end
    local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = version, dev = true })
    loader:load(data)
    local label = version .. " API " .. api .. " "
    T.eq(loader.mods.a_good.failed, nil, label .. "mart writes load")
    T.eq(loader.mods.b_failed.failed, true, label .. "rollback owner fails")
    T.eq(data.gen2Marts, stock, label .. "retains mounted table")
    T.same(Mart.inventory(stock, 0), { "ULTRA_BALL" }, label .. "stock replaces and rollback restores")
    T.same(Mart.inventory(stock, 1), {}, label .. "empty patch clears stock")
    T.same(Mart.inventory(stock, 33), {}, label .. "remove clears without fallback or shifting")
    T.eq(stock.source, "fixture", label .. "metadata retained")
    T.same(Mart.bargainRows(stock), { { item = "NUGGET", price = 500 } }, label .. "bargain replaces")
    local save = { player = { money = 10000 }, inventory = {} }
    local game = { data = data, save = save,
      world = { text = require("tests.fixtures.gen2_common_text").text() } }
    local menu = Mart.new(game, { martId = 0 })
    T.eq(menu.entries[1] and menu.entries[1].price, 1200, label .. "normal shelf uses item price")
    menu.qtyItem, menu.qty = menu.entries[1], 2
    menu:completePurchase(2400)
    T.eq(save.inventory.ULTRA_BALL, 2, label .. "normal purchase grants item")
    T.eq(save.player.money, 7600, label .. "normal purchase deducts money")
    local bargain = Mart.new(game, { martType = "BARGAIN" })
    bargain.qtyItem, bargain.qty = bargain.entries[1], 1
    bargain:completePurchase(500)
    T.eq(save.player.money, 7100, label .. "bargain purchase uses row price")
    T.eq(save.bargainShop and save.bargainShop.NUGGET, true, label .. "bargain sold state uses item id")
    T.sdk.restoreRuntime()
  end
end
for _, version in ipairs({ "red", "firered" }) do
  T.eq(Unified.supports("marts", version == "red" and 1 or 3, version), false,
    version .. " has no Gen2 mart surface")
end
T.finish("Gen 2 mart registry")
