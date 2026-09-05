-- engine/events/prize_menu.asm (#1867)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local realFont = package.loaded["src.render.Font"]
local realTextBox = package.loaded["src.render.TextBox"]
local calls = {}
local FontStub
FontStub = {
  BORDER = { tl = 1, tr = 2, bl = 3, br = 4, h = 5, v = 6 },
  draw = function(text, x, y) calls[#calls + 1] = { "draw", text, x, y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { "code", code, x, y } end,
  drawBox = function(tx, ty, tw, th) calls[#calls + 1] = { "box", tx, ty, tw, th } end,
  width = function(text) return #tostring(text) * 8 end,
  split = function(text)
    local out = {}
    for i = 1, #tostring(text) do out[i] = i end
    return out
  end,
}
package.loaded["src.render.Font"] = FontStub
package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts, isTextBox = true }
  end,
}
package.loaded["src.core.Sound"] = { play = function() end }
local version = "red"
package.loaded["src.core.GameVersion"] = {
  isBlue = function() return version == "blue" end,
  isYellow = function() return version == "yellow" end,
}
package.loaded["src.ui.PrizeCounter"] = nil
package.loaded["src.ui.Theme"] = nil
local PrizeCounter = require("src.ui.PrizeCounter")

local M = assert(loadfile("data/scripts/story3.lua"))()
local counters = M.GAME_CORNER_PRIZE_ROOM.talk

local function found(kind, pred)
  for _, c in ipairs(calls) do
    if c[1] == kind and pred(c) then return c end
  end
  return nil
end

local pressed, done
local function mkGame(coins)
  done = false
  local mons = {}
  for _, n in ipairs({ "ABRA", "CLEFAIRY", "NIDORINA", "VULPIX",
                       "WIGGLYTUFF" }) do
    mons[n] = { name = n }
  end
  return {
    data = {
      text = {},
      pokemon = mons,
      items = {
        TM_DRAGON_RAGE = { name = "TM23" },
        TM_HYPER_BEAM = { name = "TM15" },
        TM_SUBSTITUTE = { name = "TM35" },
      },
    },
    save = { coins = coins, inventory = { COIN_CASE = 1 } },
    input = {
      wasPressed = function(_, b) return pressed == b end,
      isDown = function() return false end,
    },
    stack = {
      states = {},
      push = function(self, s) self.states[#self.states + 1] = s end,
      pop = function(self) return table.remove(self.states) end,
      top = function(self) return self.states[#self.states] end,
    },
  }
end

local function open(n, coins)
  local game = mkGame(coins or 5000)
  local ow = {}
  counters["TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_" .. n](
    game, ow, nil, function() done = true end)
  local exchange = game.stack:pop()
  exchange.onDone()
  local which = game.stack:top()
  which.opts.stay.onShown()
  return game, which, game.stack:top(), ow
end

do
  local game, which, window = open(1)
  check(tostring(which.text):find("Which prize", 1, true) ~= nil,
        "WhichPrizeText goes up before the window")
  check(which.opts.stay ~= nil and which.opts.stay.prompt == nil,
        "it ends in `done`: no prompt, and PrintText leaves it up")
  check(getmetatable(window) == PrizeCounter,
        "the prize window is the CeladonPrizeMenu overlay")
  check(window.isOpaque ~= true,
        "so the prize room keeps drawing around it")

  local names = {}
  for i, row in ipairs(window.prizes) do names[i] = row.name end
  eq(#window.prizes, 3, "one window is three prizes (#623)")
  eq(table.concat(names, ","), "ABRA,CLEFAIRY,NIDORINA",
     "Red's first window, by GetMonName")
  for _, row in ipairs(window.prizes) do
    check(tostring(row.name):find("L%d") == nil,
          row.name .. " carries no level: GetPrizeMonLevel is not menu chrome")
  end
  eq(window.prizes[1].cost, 180, "with prizes.asm's coin prices")
  eq(window.prizes[3].cost, 1200, "including the third row's")

  calls = {}
  window:draw()
  check(found("box", function(c)
    return c[2] == 11 and c[3] == 0 and c[4] == 9 and c[5] == 3
  end) ~= nil, "PrintPrizePrice's coin box is 9x3 at hlcoord 11,0")
  check(found("draw", function(c)
    return c[2] == "COIN" and c[3] == 96 and c[4] == 0
  end) ~= nil, "with COIN on its top border at hlcoord 12,0")
  local coins = found("draw", function(c) return c[2] == "5000" end)
  if check(coins ~= nil, "and the balance on the row below") then
    eq(coins[3] + FontStub.width("5000"), 136,
       "right-aligned through the BCD field (hlcoord 13,1)")
    eq(coins[4], 8, "on the box's middle row")
  end
  check(found("box", function(c)
    return c[2] == 0 and c[3] == 2 and c[4] == 18 and c[5] == 10
  end) ~= nil, "the prize box is 18x10 at hlcoord 0,2, clear of columns 18-19")
  for i, name in ipairs({ "ABRA", "CLEFAIRY", "NIDORINA" }) do
    local y = 32 + (i - 1) * 16
    check(found("draw", function(c)
      return c[2] == name and c[3] == 16 and c[4] == y
    end) ~= nil, name .. " sits at (16, " .. y .. ")")
    local cost = found("draw", function(c)
      return c[2] == tostring(window.prizes[i].cost)
    end)
    if check(cost ~= nil, "its price is drawn") then
      eq(cost[4], y + 8, "one tile row below the name (hlcoord 13, 5/7/9)")
      eq(cost[3] + FontStub.width(cost[2]), 136, "right-aligned with the coins")
    end
  end
  check(found("draw", function(c)
    return c[2] == "NO THANKS" and c[3] == 16 and c[4] == 80
  end) ~= nil, "NoThanksText is the fourth row at hlcoord 2,10")
  check(found("draw", function(c) return c[2] == "PRIZES (COINS)" end) == nil,
        "and there is no full-screen page title")

  pressed = "up"
  window:update(1 / 60)
  eq(window.index, 1, "Up on the first prize does nothing")
  pressed = "down"
  for _ = 1, 6 do window:update(1 / 60) end
  eq(window.index, 4, "Down stops on NO THANKS, the fourth row")
  pressed = "a"
  window:update(1 / 60)
  pressed = nil
  check(done, "A on NO THANKS ends the conversation (cp 3 -> .noChoice)")
  eq(#game.stack.states, 0,
     "with the window and WhichPrizeText both taken down")
end

do
  local game, _, window = open(3)
  calls = {}
  window:draw()
  eq(window.prizes[1].name, "TM23", "vendor 3 is GetItemName, not GetMonName")
  eq(window.prizes[3].cost, 7700, "PrizeMenuTMsEntries prices")
  check(found("draw", function(c)
    return c[2] == "3300" and c[4] == 40
  end) ~= nil, "TM prices sit on the row below their name too")
end

do
  version = "yellow"
  local game, _, window = open(1)
  local names = {}
  for i, row in ipairs(window.prizes) do names[i] = row.name end
  eq(table.concat(names, ","), "ABRA,VULPIX,WIGGLYTUFF",
     "pokeyellow/data/events/prizes.asm restocks window 1")
  eq(window.prizes[3].cost, 2680, "with Yellow's prices")
  version = "red"
end

do
  local game, _, window, ow = open(1, 5000)
  window.index = 1
  pressed = "a"
  window:update(1 / 60)
  pressed = nil
  local ask = game.stack:top()
  check(ask.isTextBox and tostring(ask.text):find("ABRA", 1, true) ~= nil,
        "SoYouWantPrizeText names the prize out of wNameBuffer")
  check(tostring(ask.text):find("wNameBuffer", 1, true) == nil,
        "with the token filled in")
  check(ask.opts.choice ~= nil, "and a YES/NO over it")
  -- engine/events/prize_menu.asm:24-28,42
  check(ow.prizeWindow ~= nil, "the overworld takes the window's pixels over")
  eq(ow.prizeWindow.prizes, window.prizes, "with the same three prizes")
  eq(ow.prizeWindow.index, 1, "and the cursor parked on the picked row")
  eq(#game.stack.states, 1, "the menu state itself is off the stack")
  eq(game.save.coins, 5000, "no coins move before the answer")

  ask.opts.choice(false)
  local oh = game.stack:top()
  check(oh.isTextBox and tostring(oh.text):find("fine then", 1, true) ~= nil,
        "answering NO prints OhFineThenText")
  check(ow.prizeWindow ~= nil, "with the window still drawn underneath it")
  check(not done, "and the conversation not over yet")
  oh.onDone()
  eq(ow.prizeWindow, nil, "only that box closing gives the rows back")
  check(done, "and ends the conversation")
end

do
  local _, _, window = open(1, 5000)
  calls = {}
  window:draw()
  local withCursor = #calls
  local cursors = 0
  for _, c in ipairs(calls) do if c[1] == "code" then cursors = cursors + 1 end end
  eq(cursors, 1, "the live menu draws the cursor")
  calls = {}
  PrizeCounter.drawWindow(window.game, window.prizes, nil)
  eq(#calls, withCursor - 1, "the persistent window draws the same boxes and rows")
  for _, c in ipairs(calls) do
    check(c[1] ~= "code", "minus the cursor, which the menu owns")
  end
end

package.loaded["src.render.Font"] = realFont
package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.core.Sound"] = nil
package.loaded["src.core.GameVersion"] = nil
package.loaded["src.ui.PrizeCounter"] = nil
package.loaded["src.ui.Theme"] = nil
require("src.ui.Screens").invalidate()

T.finish()
