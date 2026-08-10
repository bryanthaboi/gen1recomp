-- Stable ListMenu identities for screen.render_visible and companion UIs.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

local SaveData = require("src.core.SaveData")
local BoxMenu = require("src.ui.BoxMenu")
local ListMenu = require("src.ui.ListMenu")
local PlayerPC = require("src.ui.PlayerPC")
local Boxes = require("src.pokemon.Boxes")

local pushed
local game = {
  data = Data,
  save = SaveData.newGame(),
  stack = { push = function(_, state) pushed = state end },
}

local species = T.fixtures.ids.species[1]
Boxes.ensure(game.save)[1][1] = { species = species, level = 5 }
game.save.party[1] = { species = species, level = 5 }
game.save.party[2] = { species = species, level = 6 }
game.save.pcItems = { FIX_POTION = 2 }
game.save.inventory.FIX_POTION = 2

local generic = ListMenu.new(game, "VISIBLE TITLE", {}, {})
T.eq(generic.kind, "VISIBLE TITLE", "generic lists fall back to their title")
local explicit = ListMenu.new(game, "Localized title", {}, { kind = "stable_id" })
T.eq(explicit.kind, "stable_id", "explicit list kind is preserved")

local box = BoxMenu.new(game)
for i, kind in ipairs({ "pc_box_withdraw", "pc_box_deposit",
                         "pc_box_release", "pc_box_change" }) do
  pushed = nil
  box.items[i].onSelect()
  T.eq(pushed and pushed.kind, kind, kind .. " is stable")
end

local items = PlayerPC.new(game)
for i, kind in ipairs({ "pc_item_withdraw", "pc_item_deposit",
                         "pc_item_toss" }) do
  pushed = nil
  items.items[i].onSelect()
  T.eq(pushed and pushed.kind, kind, kind .. " is stable")
end

T.finish("pc_list_kinds")
