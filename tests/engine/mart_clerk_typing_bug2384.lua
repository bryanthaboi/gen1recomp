-- home/text_script.asm:141-150
-- engine/events/pokemart.asm:7-19
-- engine/events/pokemart.asm:131-133
-- engine/events/pokemart.asm:199-206
-- engine/events/pokemart.asm:220-222
-- engine/menus/text_box.asm:168-176

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local function chars(text)
  local out = {}
  for s in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    out[#out + 1] = s
  end
  return out
end

local drawn = {}
local realFont = package.loaded["src.render.Font"]
package.loaded["src.render.Font"] = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text) drawn[#drawn + 1] = { "draw", tostring(text) } end,
  drawCode = function(code) drawn[#drawn + 1] = { "code", code } end,
  drawBox = function(tx, ty, tw, th) drawn[#drawn + 1] = { "box", tx, ty, tw, th } end,
  width = function(text) return #chars(text) * 8 end,
  split = chars,
  spansFitting = function(spans, pixels)
    return math.min(#spans, math.floor(pixels / 8))
  end,
  encode = chars,
  advanceOf = function() return 8 end,
}

local RELOAD = {
  "src.ui.QuantityBox", "src.ui.ShopMenu", "src.ui.ListMenu",
  "src.ui.ChoiceBox", "src.ui.Menu", "src.ui.Theme", "src.render.TextBox",
}
for _, m in ipairs(RELOAD) do package.loaded[m] = nil end

local ShopMenu = require("src.ui.ShopMenu")
local TextBox = require("src.render.TextBox")
local ListMenu = require("src.ui.ListMenu")
local Theme = require("src.ui.Theme")

local HI = "Hi there!\nMay I help you?"
local TAKE = "Take your time."
local SELL = "What would you\nlike to sell?"
local ELSE = "Is there anything\nelse I can do?"
local THANKS = "Thank you!"

local function newGame()
  local states, pressed = {}, {}
  local game = {
    data = {
      items = { POKE_BALL = { name = "POKe BALL", price = 200 } },
      text = {
        _PokemartGreetingText = HI,
        _PokemartBuyingGreetingText = TAKE,
        _PokemonSellingGreetingText = SELL,
        _PokemartAnythingElseText = ELSE,
        _PokemartThankYouText = THANKS,
      },
      constants = {},
    },
    save = { money = 3000, inventory = { POKE_BALL = 3 }, bagOrder = { "POKE_BALL" },
             options = { textSpeed = 3 } },
    input = {
      wasPressed = function(_, b) return pressed[b] == true end,
      isDown = function() return false end,
    },
  }
  game.stack = {
    states = states,
    push = function(_, s)
      states[#states + 1] = s
      if type(s.enter) == "function" then s:enter() end
    end,
    pop = function() return table.remove(states) end,
    top = function() return states[#states] end,
  }
  local function frame(btn)
    for k in pairs(pressed) do pressed[k] = nil end
    if btn then pressed[btn] = true end
    local top = states[#states]
    if top then top:update(1 / 60) end
    for k in pairs(pressed) do pressed[k] = nil end
  end
  return game, states, frame
end

local function until_(frame, pred)
  for _ = 1, 600 do
    if pred() then return true end
    frame()
  end
  return pred()
end

local function drewText(fn, text)
  drawn = {}
  fn()
  for _, c in ipairs(drawn) do
    if c[1] == "draw" and c[2] == text then return true end
  end
  return false
end

local function drewBox(fn, tx, ty, tw, th)
  drawn = {}
  fn()
  for _, c in ipairs(drawn) do
    if c[1] == "box" and c[2] == tx and c[3] == ty and c[4] == tw and c[5] == th then
      return true
    end
  end
  return false
end

local function cursorGlyph(menu)
  drawn = {}
  menu:draw()
  local last
  for _, c in ipairs(drawn) do
    if c[1] == "code" then last = c[2] end
  end
  return last
end

local function isSay(s, text)
  return getmetatable(s) == TextBox and s.stay ~= nil
    and table.concat(chars(s.pages and s.pages[1] and s.pages[1][1] or ""))
        == (tostring(text):match("^[^\n]*"))
end

do
  local game, states, frame = newGame()
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  game.stack:push(menu)
  local greet = states[#states]
  check(isSay(greet, HI), "greeting: a typing text box goes up first")
  eq(greet.done, false, "greeting: it is not instant")
  eq(menu.hidden, true, "greeting: BUY/SELL/QUIT is not up yet")
  check(not drewText(function() menu:draw() end, "BUY"), "greeting: no BUY row drawn")
  check(not drewBox(function() menu:draw() end, 11, 0, 9, 3), "greeting: no MONEY box drawn")
  for _ = 1, 6 do frame() end
  local typed = greet.shown[1] and #greet.shown[1] or 0
  check(typed > 0 and typed < #chars("Hi there!"), "greeting: typing mid-line")
  check(until_(frame, function() return states[#states] == menu end),
        "greeting: the menu takes over once the text is done")
  eq(menu.hidden, false, "greeting: BUY/SELL/QUIT is up")
  eq(menu.footer, HI, "greeting: the line stays in the box under the menu")
  check(drewText(function() menu:draw() end, "BUY"), "greeting: BUY drawn")
  eq(cursorGlyph(menu), Theme.cursor, "greeting: filled cursor on BUY")
end

do
  local game, states, frame = newGame()
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  game.stack:push(menu)
  until_(frame, function() return states[#states] == menu end)
  frame("a")
  eq(menu.hollowIndex, 1, "BUY: the chosen row goes hollow")
  eq(cursorGlyph(menu), Theme.cursorHollow, "BUY: hollow glyph drawn")
  local say = states[#states]
  check(isSay(say, TAKE), "BUY: Take your time. types before the list")
  eq(say.done, false, "BUY: the lead-in is typing")
  eq(states[#states - 1], menu, "BUY: BUY/SELL/QUIT stays under the lead-in")
  check(until_(frame, function() return getmetatable(states[#states]) == ListMenu end),
        "BUY: the list opens after the lead-in")
  local list = states[#states]
  eq(list.footer, TAKE, "BUY: the list keeps the lead-in in its box")
  eq(menu.hollowIndex, 1, "BUY: BUY stays hollow under the list")

  frame("b")
  local back = states[#states]
  check(isSay(back, ELSE), "B on the list: anything-else types")
  eq(back.done, false, "B on the list: it is typing")
  eq(menu.hollowIndex, 1, "B on the list: still hollow while it types")
  check(until_(frame, function() return states[#states] == menu end),
        "B on the list: back to BUY/SELL/QUIT")
  eq(menu.index, 1, "back: cursor on BUY")
  eq(menu.hollowIndex, nil, "back: cursor filled again")
  eq(menu.footer, ELSE, "back: anything-else stays in the box")
end

do
  local game, states, frame = newGame()
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  game.stack:push(menu)
  until_(frame, function() return states[#states] == menu end)
  frame("down")
  frame("a")
  eq(menu.hollowIndex, 2, "SELL: the chosen row goes hollow")
  check(isSay(states[#states], SELL), "SELL: the sell lead-in types first")
  check(until_(frame, function() return getmetatable(states[#states]) == ListMenu end),
        "SELL: the list opens after the lead-in")
  local list = states[#states]
  list.index = #list.items
  frame("a")
  check(isSay(states[#states], ELSE), "CANCEL: anything-else types")
  check(until_(frame, function() return states[#states] == menu end),
        "CANCEL: back to BUY/SELL/QUIT")
  eq(menu.index, 1, "CANCEL: the cursor resets to BUY, not SELL")
  eq(menu.hollowIndex, nil, "CANCEL: filled again")
end

for _, case in ipairs({ { name = "QUIT", keys = { "down", "down", "a" }, row = 3 },
                        { name = "B", keys = { "b" }, row = 1 } }) do
  local game, states, frame = newGame()
  local quits = 0
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() quits = quits + 1 end)
  game.stack:push(menu)
  until_(frame, function() return states[#states] == menu end)
  for _, k in ipairs(case.keys) do frame(k) end
  local bye = states[#states]
  check(getmetatable(bye) == TextBox, case.name .. ": Thank you! is up")
  eq(states[#states - 1], menu, case.name .. ": the menu stays under Thank you!")
  eq(menu.hollowIndex, case.row, case.name .. ": the chosen row is hollow")
  eq(quits, 0, case.name .. ": onQuit waits for the text")
  until_(frame, function() return bye.done end)
  frame("a")
  eq(#states, 0, case.name .. ": the box and the menu close together")
  eq(quits, 1, case.name .. ": onQuit fires once")
end

do
  local game, states, frame = newGame()
  game.save.inventory, game.save.bagOrder = {}, {}
  local menu = ShopMenu.new(game, { "POKE_BALL" }, function() end)
  game.stack:push(menu)
  until_(frame, function() return states[#states] == menu end)
  frame("down")
  frame("a")
  local empty = states[#states]
  check(getmetatable(empty) == TextBox and not empty.stay, "empty bag: the refusal prompt is up")
  until_(frame, function() return empty.done end)
  frame("a")
  check(isSay(states[#states], ELSE), "empty bag: anything-else types after the refusal")
  check(until_(frame, function() return states[#states] == menu end),
        "empty bag: back to BUY/SELL/QUIT")
  eq(menu.index, 1, "empty bag: cursor on BUY")
end

package.loaded["src.render.Font"] = realFont
for _, m in ipairs(RELOAD) do package.loaded[m] = nil end
require("src.ui.Screens").invalidate()

T.finish()
