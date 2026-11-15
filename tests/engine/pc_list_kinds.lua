-- Stable ListMenu identities for screen.render_visible and companion UIs.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()
Data.text._WhatDoYouWantText = "What do you want\nto do?{DONE}"

local SaveData = require("src.core.SaveData")
local BoxMenu = require("src.ui.BoxMenu")
local ListMenu = require("src.ui.ListMenu")
local PlayerPC = require("src.ui.PlayerPC")
local Boxes = require("src.pokemon.Boxes")

local pushed
local pressed = {}
local game = {
  data = Data,
  save = SaveData.newGame(),
  input = { wasPressed = function(_, key) return pressed[key] or false end },
  stack = { push = function(_, state) pushed = state end },
}

local species = T.fixtures.ids.species[1]
Data.items.POKE_FLUTE = { name = "POKE FLUTE", keyItem = true }
Data.items.HM_CUT = { name = "HM", keyItem = false }
Data.items.FIX_POTION = { name = "POTION", keyItem = false }
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
  T.eq(box.hollowIndex, box.index, "bills_pc.asm:176 " .. kind .. " parent row goes hollow")
  box.hollowIndex = nil
end

for _, kind in ipairs({ "pc_box_withdraw", "pc_box_deposit", "pc_box_release" }) do
  local idx = ({ pc_box_withdraw = 1, pc_box_deposit = 2, pc_box_release = 3 })[kind]
  pushed = nil
  box.items[idx].onSelect()
  local list = pushed
  T.eq(list.kind, kind, kind .. " list opens")
  local item = list.items[1]
  list.hollowIndex = nil
  list.index = 1
  list.onChoose(item, list)
  T.eq(list.hollowIndex, 1, "list_menu.asm:91 " .. kind .. " chosen row goes hollow")
end

local items = PlayerPC.new(game)
T.eq(items.title, nil, "player PC prompt is a bottom box, not a title")
do
  local realDraw = require("src.render.Font").draw
  local Font = require("src.render.Font")
  local ys = {}
  Font.draw = function(text, _, y) ys[text] = y return 8 end
  local ok, err = pcall(items.draw, items)
  Font.draw = realDraw
  if not ok then error(err, 0) end
  T.eq(ys["What do you want"], 112, "player PC prompt line 1 at y=112")
  T.eq(ys["to do?"], 128, "player PC prompt line 2 at y=128")
end
for i, kind in ipairs({ "pc_item_withdraw", "pc_item_deposit",
                         "pc_item_toss" }) do
  pushed = nil
  items.hollowIndex = nil
  items.index = i
  items.items[i].onSelect()
  T.eq(pushed and pushed.kind, kind, kind .. " is stable")
  T.eq(items.hollowIndex, i, "players_pc.asm:55 parent row goes hollow")
end

game.save.pcItems = { POKE_FLUTE = 1, HM_CUT = 1, FIX_POTION = 3 }
pushed = nil
items.items[1].onSelect()
local withdraw = pushed
local rows = {}
for _, item in ipairs(withdraw.items) do
  if item.value then rows[item.value] = item end
end
T.eq(rows.POKE_FLUTE.count, nil, "key item has no PC-list quantity")
T.eq(rows.HM_CUT.count, nil, "HM has no PC-list quantity")
T.eq(rows.FIX_POTION.count, 3, "stackable item retains its quantity")
T.check(type(withdraw.onChoose) == "function",
  "withdraw transfer callback remains attached to the list")

local originalPrompt = withdraw.footer
withdraw.onChoose(rows.FIX_POTION, withdraw)
local quantity = pushed
T.eq(withdraw.hollowIndex, withdraw.index, "list_menu.asm:91 chosen row goes hollow")
T.eq(withdraw.footer, Data.text._WithdrawHowManyText, "quantity selection replaces the PC prompt")
quantity.onDone(nil)
T.eq(withdraw.footer, originalPrompt,
  "canceling quantity restores the withdraw prompt")
withdraw:showCompletion("Withdrew\nPOKE FLUTE.{PROMPT}")
withdraw:update(0)
T.check(withdraw.pcCompletion,
  "PC completion message waits for an advance button")
pressed.a = true
withdraw:update(0)
pressed.a = nil
T.eq(withdraw.pcCompletion, nil,
  "advancing completion returns to the live item list")
T.eq(withdraw.footer, originalPrompt,
  "advancing completion restores the PC list prompt")

local function press(list)
  pressed.a = true
  list:update(0)
  pressed.a = nil
end

local function rowOf(list, id)
  for i, item in ipairs(list.items) do
    if item.value == id then return i, item end
  end
end

Data.items.ZINC = { name = "ZINC", keyItem = false }
game.save.inventory = {}
game.save.pcItems = { POKE_FLUTE = 1, HM_CUT = 1, ZINC = 3 }
pushed = nil
items.items[1].onSelect()
withdraw = pushed
local n = #withdraw.items
local potionRow = rowOf(withdraw, "ZINC")
withdraw.index = potionRow
withdraw.onChoose(withdraw.items[potionRow], withdraw)
pushed.onDone(1)
T.check(withdraw.pcCompletion, "partial withdraw shows its completion prompt")
T.eq(select(2, rowOf(withdraw, "ZINC")).count, 3,
  "players_pc.asm:191 partial withdraw count unchanged while message is up")
press(withdraw)
T.eq(select(2, rowOf(withdraw, "ZINC")).count, 2,
  "players_pc.asm:192 partial withdraw count repaints after the message")
T.eq(withdraw.index, potionRow, "partial withdraw keeps the cursor")

withdraw.scroll = 1
withdraw.onChoose(withdraw.items[potionRow], withdraw)
pushed.onDone(2)
T.eq(#withdraw.items, n, "players_pc.asm:191 emptied row stays while message is up")
T.eq(rowOf(withdraw, "ZINC"), potionRow, "emptied row still listed during message")
T.eq(withdraw.index, potionRow, "cursor stays on the emptied row during message")
press(withdraw)
T.eq(rowOf(withdraw, "ZINC"), nil, "emptied row removed after the message")
T.eq(#withdraw.items, n - 1, "list shrinks by one after the message")
T.eq(withdraw.index, 1, "inventory.asm:131 emptied stack resets cursor to top")
T.eq(withdraw.scroll, 0, "inventory.asm:131 emptied stack resets scroll to top")

pushed = nil
items.items[2].onSelect()
local dep = pushed
n = #dep.items
local depRow = rowOf(dep, "ZINC")
dep.index = depRow
dep.onChoose(dep.items[depRow], dep)
pushed.onDone(game.save.inventory.ZINC)
T.check(dep.pcCompletion, "deposit shows its completion prompt")
T.eq(#dep.items, n, "players_pc.asm:137 deposited row stays while message is up")
press(dep)
T.eq(rowOf(dep, "ZINC"), nil, "deposited row removed after the message")
T.eq(dep.index, 1, "deposit emptied stack resets cursor to top")

local realChoice = require("src.ui.ChoiceBox").new
require("src.ui.ChoiceBox").new = function(_, cb) return { choose = cb } end
game.save.pcItems.ZINC = 2
pushed = nil
items.items[3].onSelect()
local tossList = pushed
n = #tossList.items
potionRow = rowOf(tossList, "ZINC")
tossList.index = potionRow
tossList.onChoose(tossList.items[potionRow], tossList)
pushed.onDone(2)
pushed.choose(true)
require("src.ui.ChoiceBox").new = realChoice
T.check(tossList.pcCompletion, "toss shows its completion prompt")
T.eq(#tossList.items, n, "players_pc.asm:240 tossed row stays while message is up")
press(tossList)
T.eq(rowOf(tossList, "ZINC"), nil, "tossed row removed after the message")
T.eq(tossList.index, 1, "toss emptied stack resets cursor to top")

T.finish("pc_list_kinds")
