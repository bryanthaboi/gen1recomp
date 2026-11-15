package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}
require("src.core.GameVersion").set("firered")
package.loaded["src.core.game3.audio"] = {
  playSe = function() end, playCry = function() end, playSong = function() end, stopAll = function() end,
}
package.loaded["src.core.game3.map"] = { currentDef = function() return {} end }
package.loaded["src.core.game3.collision"] = {
  isWater = function() return false end, isGrass = function() return false end,
  behavior = function() return 0 end,
}
package.loaded["src.core.game3.objects"] = { at = function() return nil end }
package.loaded["src.core.game3.scripting.space"] = { store = nil }
package.loaded["src.core.game3.field"] = { executeFieldMove = function() end }

local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local Logger = require("src.core.Logger")
local PartyMenu = require("src.ui.game3.party_menu")
local FieldMoves = require("src.core.game3.field_moves")
PartyMenu.heldItemSheet = function() return nil end

local calls = {}
FieldMoves.fromMenu = function(moveId, ctx)
  calls[#calls + 1] = { moveId = moveId, mon = ctx.mon }
  return { ok = false, text = "refused" }
end

local function input(key)
  return { wasPressed = function(_, k) return k == key end, isDown = function(_, k) return k == key end }
end
local function press(key) PartyMenu.handleInput(input(key)) end

local hooks = Hooks.new()
Runtime.install({ emit = function() end, removeOwner = function() end }, hooks, {})

local TACKLE = 33
local mon = { species = 6, level = 40, hp = 100, maxHp = 100, stats = { hp = 100 }, moves = { TACKLE }, pp = { 35 } }
local party = { mon, { species = 1, level = 5, hp = 10, maxHp = 10, stats = { hp = 10 }, moves = { TACKLE } } }

local row
hooks:wrap("ui.party.submenu", function(nextFn, game, items, m, ctx)
  items = nextFn(game, items, m, ctx)
  table.insert(items, 2, row)
  return items
end, 0, "field_move_case")

local function openField()
  PartyMenu.show(party, nil, { session = {} })
  press("a")
end
local function invalidLogged(fn)
  local before = #Logger.history
  fn()
  for i = before + 1, #Logger.history do
    if Logger.history[i]:find("ui.party.submenu returned an invalid", 1, true) then return true end
  end
  return false
end

row = { label = "CUT", move = "CUT" }
local logged = invalidLogged(openField)
local second = PartyMenu.ACTIONS[2]
T.check(not logged, "gen3 { label, move = \"CUT\" } row is accepted")
T.eq(type(second) == "table" and second.action, "CUT", "the move row is normalised to this game's CUT action")
T.eq(PartyMenu._fieldMoveNames and PartyMenu._fieldMoveNames.CUT, true, "the injected CUT joins the field-move set")
PartyMenu.actionCursor = 2
calls = {}
press("a")
T.eq(#calls, 1, "A on the injected CUT row reaches FieldMoves.fromMenu")
T.eq(calls[1] and calls[1].moveId, "CUT", "fromMenu gets CUT")
T.check(calls[1] and calls[1].mon == mon, "fromMenu gets the selected mon, which does not know CUT")
PartyMenu.close()

row = { label = "CUT", action = "CUT" }
logged = invalidLogged(openField)
T.check(not logged and type(PartyMenu.ACTIONS[2]) == "table" and PartyMenu.ACTIONS[2].action == "CUT",
  "a row naming the field-move label is accepted too")
PartyMenu.close()

row = { label = "MOVE_CUT", move = "MOVE_CUT" }
logged = invalidLogged(openField)
T.check(not logged and PartyMenu._fieldMoveNames.CUT == true, "move constants with the MOVE_ prefix resolve")
PartyMenu.close()

row = { label = "DIVE", move = "DIVE" }
logged = invalidLogged(openField)
T.check(logged, "a move with no FRLG field-move slot is rejected")
T.check(PartyMenu._fieldMoveNames.DIVE == nil, "rejected rows add no field move")
PartyMenu.close()

row = { label = "FOO", action = "FOO" }
logged = invalidLogged(openField)
T.check(logged, "an unknown action still keeps the vanilla list")
PartyMenu.close()

row = { move = "CUT" }
logged = invalidLogged(openField)
T.check(not logged and type(PartyMenu.ACTIONS[2]) == "table" and PartyMenu.ACTIONS[2].action == "CUT",
  "a move row with no label is accepted")
T.eq(type(PartyMenu.ACTIONS[2]) == "table" and PartyMenu.ACTIONS[2].label, "CUT",
  "and labelled with the field move")
PartyMenu.close()

local picked = 0
row = { label = "MINE", move = "CUT", onSelect = function() picked = picked + 1 end }
logged = invalidLogged(openField)
local mine = PartyMenu.ACTIONS[2]
T.check(not logged and type(mine) == "table" and mine.action == nil,
  "a move row with its own onSelect is not turned into a field move")
T.eq(type(mine) == "table" and type(mine.onSelect), "function", "and keeps its onSelect")
PartyMenu.actionCursor = 2
calls = {}
press("a")
T.eq(picked, 1, "A on that row runs the mod's onSelect")
T.eq(#calls, 0, "and no field move")
PartyMenu.close()

local bare = 0
row = { onSelect = function() bare = bare + 1 end }
logged = invalidLogged(openField)
local unlabelled = PartyMenu.ACTIONS[2]
T.check(not logged and type(unlabelled) == "table" and type(unlabelled.onSelect) == "function",
  "an onSelect row with no label keeps the hooked list")
T.eq(type(unlabelled) == "table" and type(unlabelled.label), "string", "and gets a label string")
PartyMenu.actionCursor = 2
press("a")
T.eq(bare, 1, "A on that row runs its onSelect")
PartyMenu.close()

row = { move = "CUT", onSelect = function() end }
logged = invalidLogged(openField)
T.eq(not logged and type(PartyMenu.ACTIONS[2]) == "table" and PartyMenu.ACTIONS[2].label, "CUT",
  "a label-less onSelect move row is labelled with the field move")
PartyMenu.close()

row = { label = "CUT", move = "CUT" }
PartyMenu.show(party, nil, { session = {}, mode = "battle_switch", battle = true })
logged = invalidLogged(function() press("a") end)
local hasCut = false
for _, act in ipairs(PartyMenu.ACTIONS) do
  if (type(act) == "table" and act.action or act) == "CUT" then hasCut = true end
end
T.check(logged and not hasCut, "the battle list stays strict: a field-move row is rejected")
T.check(PartyMenu._fieldMoveNames == nil, "the battle list carries no field-move set")
PartyMenu.close()

hooks:removeOwner("field_move_case")
T.finish("ui.party.submenu field-move rows Gen 3")
