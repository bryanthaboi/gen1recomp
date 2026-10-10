-- engine/menus/players_pc.asm:151-173
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local Font = require("src.render.Font")
local ListMenu = require("src.ui.ListMenu")

local game = { data = { items = {} }, save = {}, input = { wasPressed = function() return false end } }

local realBox, realDraw, realCode = Font.drawBox, Font.draw, Font.drawCode
local boxes
Font.drawBox = function(tx, ty) boxes[#boxes + 1] = tx .. "," .. ty end
Font.draw = function() end
Font.drawCode = function() end

local list = ListMenu.new(game, nil, { { label = "POTION", count = 1 }, { label = "CANCEL", cancel = true } }, {
  messageBox = true,
  footer = "What do you want\nto withdraw?",
})

local function order()
  boxes = {}
  list:draw()
  return table.concat(boxes, " ")
end

eq(order(), "0,12 4,2", "prompt box drawn first, list border on top")
list.footer = "How many?"
eq(order(), "4,2 0,12", "How many? box drawn over the list")
list.footer = "Withdrew\nPOTION."
eq(order(), "4,2 0,12", "withdrew box drawn over the list")
list.footer = "What do you want\nto withdraw?"
eq(order(), "0,12 4,2", "back at the prompt the list is on top again")

local bag = ListMenu.new(game, "ITEMS", { { label = "CANCEL", cancel = true } }, { itemBox = true })
boxes = {}
bag:draw()
eq(table.concat(boxes, " "), "4,2", "bag list draws no bottom box")
bag.footer = "The party is full!"
boxes = {}
bag:draw()
eq(table.concat(boxes, " "), "4,2 0,12", "late message box goes over the list")

Font.drawBox, Font.draw, Font.drawCode = realBox, realDraw, realCode
T.finish("pc item box order bug 2840")
