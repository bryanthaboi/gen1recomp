package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")

local hooks = Hooks.new()
Runtime.install({ emit = function() end, removeOwner = function() end }, hooks, {})

local function newStack()
  local stack = { states = {} }
  function stack:push(state, ...)
    table.insert(self.states, state)
    if state.enter then state:enter(...) end
  end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return stack
end
local function newInput()
  local input = { queue = {} }
  function input:wasPressed(btn) return self.queue[btn] or false end
  return input
end
local function press(state, btn)
  state.game.input.queue = { [btn] = true }
  state:update(1 / 60)
  state.game.input.queue = {}
end

local inject = { { label = "CUT", move = "CUT" } }
hooks:wrap("ui.party.submenu", function(nextFn, game, items, mon, ctx)
  items = nextFn(game, items, mon, ctx)
  for i, row in ipairs(inject) do table.insert(items, i, row) end
  return items
end, 0, "field_move_case")

local PartyMenu1 = require("src.ui.PartyMenu")
local cutCalls = 0
local ow = {
  useCutFieldMove = function() cutCalls = cutCalls + 1; return "no_badge" end,
  partyKnows = function() return nil end,
  map = { def = {} },
}
local g1 = {
  data = { pokemon = { PIKACHU = { name = "PIKACHU" } }, text = { _NewBadgeRequiredText = "badge" } },
  save = { party = { { species = "PIKACHU", hp = 10, stats = { hp = 10 }, level = 5,
    moves = { { id = "TACKLE" } } } }, inventory = {}, options = {} },
  stack = newStack(), input = newInput(), overworld = ow,
}
local pm = PartyMenu1.new(g1)
pm.game = g1
g1.stack:push(pm)
press(pm, "a")
local first = pm.subItems and pm.subItems[1]
T.eq(first and first.action, "cut", "gen1 { label, move = \"CUT\" } row becomes the cut action")
pm.subIndex = 1
press(pm, "a")
T.eq(cutCalls, 1, "gen1 A on the hook CUT row reaches OverworldState:useCutFieldMove")

local battlePm = PartyMenu1.new(g1, { battle = { playerParty = g1.save.party } })
battlePm.game = g1
g1.stack:push(battlePm)
press(battlePm, "a")
local bfirst = battlePm.subItems and battlePm.subItems[1]
T.check(bfirst == nil or bfirst.action ~= "cut", "gen1 battle list does not turn a move row into a field move")
g1.stack:pop()

local picked1 = 0
inject = {
  { move = "CUT" },
  { label = "MINE", move = "SURF", onSelect = function() picked1 = picked1 + 1 end },
}
local pmEdge = PartyMenu1.new(g1)
pmEdge.game = g1
g1.stack:push(pmEdge)
press(pmEdge, "a")
local e1, e2 = pmEdge.subItems and pmEdge.subItems[1], pmEdge.subItems and pmEdge.subItems[2]
T.eq(e1 and e1.action, "cut", "gen1 a move row with no label still becomes the cut action")
T.check(e1 and type(e1.label) == "string" and e1.label ~= "", "gen1 a move row with no label is labelled with the move")
T.eq(e2 and e2.action, nil, "gen1 a move row with its own onSelect is not turned into a field move")
T.eq(e2 and type(e2.onSelect), "function", "gen1 and keeps its onSelect")
pmEdge.subIndex = 2
press(pmEdge, "a")
T.eq(picked1, 1, "gen1 A on that row runs the mod's onSelect")
g1.stack:pop()
inject = { { label = "CUT", move = "CUT" } }

local PartyMenu2 = require("src.ui.gen2.PartyMenu")
local mon2 = { species = "CYNDAQUIL", level = 5, hp = 20, maxHp = 20, moves = { { id = "TACKLE" } } }
local g2 = { save = { party = { mon2 }, options = {} }, data = { audio = {}, pokemon = {}, items = {},
    text = require("tests.fixture_data.gen2_rom_text_s7_e") },
  input = newInput(), stack = newStack() }
local self2 = setmetatable({ game = g2, moves = {}, wantsBattleSubmenu = false }, { __index = PartyMenu2 })
local items = PartyMenu2.submenuItems(self2, mon2)
T.eq(items[1].id, "CUT", "gen2 { label, move = \"CUT\" } row becomes the CUT field move")
T.eq(items[1].fieldMove, true, "gen2 move row is flagged fieldMove")
local used
self2.useFieldMove = function(_, id) used = id end
self2.closeSubmenu = function() end
self2.playSfx = function() end
self2.submenu = { items = items, index = 1, mon = mon2, slot = 1 }
PartyMenu2.updateSubmenu(self2, { wasPressed = function(_, k) return k == "a" end })
T.eq(used, "CUT", "gen2 A on the hook CUT row reaches PartyMenu:useFieldMove(\"CUT\")")

local battle2 = setmetatable({ game = g2, moves = {}, wantsBattleSubmenu = true }, { __index = PartyMenu2 })
local bitems = PartyMenu2.submenuItems(battle2, mon2)
T.check(bitems[1].fieldMove ~= true, "gen2 battle list does not turn a move row into a field move")

local picked2 = 0
inject = {
  { move = "CUT" },
  { label = "MINE", move = "SURF", onSelect = function() picked2 = picked2 + 1 end },
}
local edge2 = PartyMenu2.submenuItems(self2, mon2)
T.eq(edge2[1].id, "CUT", "gen2 a move row with no label still becomes the CUT field move")
T.eq(edge2[1].label, "CUT", "gen2 a move row with no label is labelled with the move")
T.check(edge2[2].fieldMove ~= true, "gen2 a move row with its own onSelect is not turned into a field move")
T.eq(type(edge2[2].onSelect), "function", "gen2 and keeps its onSelect")
used = nil
self2.submenu = { items = edge2, index = 2, mon = mon2, slot = 1 }
PartyMenu2.updateSubmenu(self2, { wasPressed = function(_, k) return k == "a" end })
T.eq(picked2, 1, "gen2 A on that row runs the mod's onSelect")
T.eq(used, nil, "gen2 and no field move")
inject = { { label = "CUT", move = "CUT" } }

hooks:removeOwner("field_move_case")
T.finish("ui.party.submenu field-move rows Gen 1/2")
