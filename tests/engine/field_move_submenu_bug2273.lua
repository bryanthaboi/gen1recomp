package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local PartyMenu = require("src.ui.PartyMenu")

local function newGame(moveId, ow)
  local mon = { species = "MACHOP", hp = 50, stats = { hp = 50 },
                level = 30, moves = { { id = moveId, pp = 15 } } }
  ow.map = ow.map or { def = { tileset = "OVERWORLD" }, id = "PALLET_TOWN" }
  ow.dark = ow.dark or false
  ow.partyKnows = function() return mon end
  local game = {
    data = { pokemon = { MACHOP = { name = "MACHOP" } } },
    save = { party = { mon }, inventory = {}, options = {}, flags = {} },
    overworld = ow,
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function() return false end,
  }
  return game
end

local function press(pm, btn)
  pm.game.input.queue = { [btn] = true }
  pm:update(1 / 60)
  pm.game.input.queue = {}
end

local function choose(game, action)
  local pm = PartyMenu.new(game, {})
  game.stack:push(pm)
  press(pm, "a")
  check(pm.submenu, action .. ": A on the mon opens the submenu")
  local row
  for i, item in ipairs(pm.subItems or {}) do
    if item.action == action then row = i end
  end
  check(row ~= nil, action .. " is listed in the submenu")
  pm.subIndex = row or 1
  press(pm, "a")
  return pm
end

local function expectErased(label, game, pm, captured)
  check(captured.onClose ~= nil, label .. " reaches the overworld handler")
  check(not pm.submenu, label .. ": the options box is gone under the text")
  eq(game.stack:top(), pm, label .. ": the party list stays as the text backdrop")
  if captured.onClose then captured.onClose() end
  eq(#game.stack.states, 0, label .. ": the menu closes when the text ends")
end

do
  local captured = {}
  local game = newGame("STRENGTH", {
    useStrengthFieldMove = function(_, _, onClose) captured.onClose = onClose end,
  })
  expectErased("STRENGTH", game, choose(game, "strength"), captured)
end

do
  local captured = {}
  local game = newGame("SURF", {
    player = { facingCell = function() return 4, 14 end },
    useSurfFieldMove = function() return "ok" end,
    trySurf = function(_, _, _, onClose) captured.onClose = onClose end,
  })
  expectErased("SURF", game, choose(game, "surf"), captured)
end

do
  local captured = {}
  local game = newGame("FLASH", {
    dark = true,
    useFlashFieldMove = function(_, onClose) captured.onClose = onClose end,
  })
  expectErased("FLASH", game, choose(game, "flash"), captured)
end

T.finish()
