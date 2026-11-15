local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_party_mod_cut_f19",
  os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_party_mod_cut_f19")

local MOD = {
  ["mods/party_cut_row/manifest.json"] = [[{
    "id": "party_cut_row",
    "name": "party CUT row",
    "version": "1.0.0",
    "api": 2,
    "entry": "main.lua",
    "games": ["gen1", "gen2", "gen3"]
  }]],
  ["mods/party_cut_row/main.lua"] = [[
return function(mod)
  mod.exports.calls = 0
  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    items = next(game, items, mon, ctx)
    if not ctx.battle then
      mod.exports.calls = mod.exports.calls + 1
      table.insert(items, 2, { label = "CUT", move = "CUT" })
    end
    return items
  end)
end
]],
}

local MAPS = { rse = "Route116", frlg = "Route2" }
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local FieldMoves = require("src.core.game3.field_moves")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local Field = require("src.core.game3.field")
  local MapCatalog = require("src.import.gba.map_catalog")
  local Screens = require("src.ui.game3.screens")
  local Loader = require("src.mods.Loader")
  local Sdk = require("tests.modkit.sdk")
  local session = Runtime.getSession()
  local version = session.version
  local family = require("src.core.game3.profile").family(session) == "rse" and "rse" or "frlg"
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end

  local loader = Loader.new({ fs = Sdk.memfs(MOD), generation = 3, version = version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data or {}) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(3)) do data[key] = nil end
  loader:load(data)
  local mod = loader.mods.party_cut_row
  if not S.check(mod and not mod.failed, "f19 " .. version .. " party CUT row mod loaded") then
    for _, e in ipairs(loader.errors) do S.note("loader error: " .. tostring(e)) end
    return S.finish()
  end

  local C = require("src.core.game3.constants").of(version)
  session.party = {}
  Party.giveMon(session, C:require("species", family == "rse" and "SPECIES_ZIGZAGOON" or "SPECIES_RATTATA"), 30)
  local mon = session.party[1]
  mon.moves = { C:require("moves", "MOVE_TACKLE"), 0, 0, 0 }
  mon.pp = { 35, 0, 0, 0 }
  Flags.setFlag(Space.store, nil, FieldMoves.badgeFlag("CUT"), true)

  local mapId = MapCatalog.pretToEngine(MAPS[family])
  F.goTo(game, mapId, 5, 5, "down")
  local gfx = FieldMoves.GFX_IDS.CUT_TREE
  local tree, sx, sy, dir
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if not tree and eo and tonumber(eo.graphicsId) == gfx and eo.visible and not eo.hidden and not eo.invisible then
      for d, v in pairs(DELTA) do
        local x, y = eo.cellX - v[1], eo.cellY - v[2]
        if not tree and Collision.isWalkable(x, y) and not Objects.at(x, y) then tree, sx, sy, dir = eo, x, y, d end
      end
    end
  end
  if not S.check(tree ~= nil, "f19 " .. version .. " cut tree found on " .. tostring(mapId)) then return S.finish() end
  F.goTo(game, mapId, sx, sy, dir)
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  Field.unlock()
  local lid = tree.localId

  local PartyMenu = Screens.get("party", session)
  PartyMenu.show(session.party, session.move_overlay, { session = session })
  U.wait(30)
  PartyMenu.cursor = 1
  U.tap(game, "a")
  U.wait(10)
  local row = PartyMenu.ACTIONS and PartyMenu.ACTIONS[2]
  S.check(PartyMenu.mode == "action", "f19 " .. version .. " submenu open")
  S.check(type(row) == "table" and row.action ~= nil and PartyMenu._fieldMoveNames
    and PartyMenu._fieldMoveNames[row.action] == true,
    "f19 " .. version .. " hook CUT row kept as a field move for a mon without CUT")
  local knows = false
  for _, m in ipairs(mon.moves) do if m == C:require("moves", "MOVE_CUT") then knows = true end end
  S.check(not knows, "f19 " .. version .. " mon does not know CUT")
  S.still(game, "f19_" .. version .. "_01_submenu_cut_row.png")
  PartyMenu.actionCursor = 2
  U.tap(game, "a")

  local shown, removed = 0, false
  for _ = 1, 1800 do
    if ShowMon.isActive() then shown = shown + 1 end
    if shown == 64 then S.still(game, "f19_" .. version .. "_02_cut_show_mon.png") end
    local cur = Objects.find(lid)
    if shown > 0 and (not cur or cur.hidden or not cur.visible) then removed = true break end
    U.wait(1)
  end
  S.check(shown > 0, "f19 " .. version .. " CUT show-mon cut-in played")
  S.check(removed, "f19 " .. version .. " tree cut by the hook CUT row")
  S.finish()
end
