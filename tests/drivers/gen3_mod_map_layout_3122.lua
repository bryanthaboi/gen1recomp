local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")

local NAME = "gen3_mod_map_layout_3122"
local S = F.new(NAME, os.getenv("POKEPORT_SHOT_DIR") or "/tmp/" .. NAME)

local MOD = "maplayout3122"
local ROOT = "mods/" .. MOD
local WITNESS = "3122_witness.lua"

local MAPS = {
  firered = { "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", "FR_PEWTER_CITY_POKEMON_CENTER_1F", "FR_MOD_ROOM_3122" },
  leafgreen = { "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", "FR_PEWTER_CITY_POKEMON_CENTER_1F", "FR_MOD_ROOM_3122" },
  emerald = { "EM_OLDALE_TOWN_POKEMON_CENTER_1F", "EM_PETALBURG_CITY_POKEMON_CENTER_1F", "EM_MOD_ROOM_3122" },
}

local Map = require("src.core.game3.map")
local Player = require("src.core.game3.player")
local Runtime = require("src.core.game3.runtime")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local CollPermissions = require("src.core.CollPermissions")
local NativeTileset = require("src.core.game3.tileset_native")
local NativePack = require("src.import.gba.native_pack")
local ScriptColl = require("src.core.game3.scripting.collision")

local function serialize(t)
  local parts = {}
  for k, v in pairs(t) do
    parts[#parts + 1] = type(v) == "number" and ("%s = %d,"):format(k, v) or ("%s = %q,"):format(k, v)
  end
  return "return {" .. table.concat(parts, " ") .. "}"
end

local function layoutOf(game, id)
  local def = game.data.maps[id]
  return def and Map.ensureMidLayout(game, id, def), def
end

local function occupied(def, x, y)
  for _, o in ipairs(def.objects or {}) do
    local ox, oy = tonumber(o.x), tonumber(o.y)
    if ox and oy and math.abs(ox - x) <= 1 and math.abs(oy - y) <= 1 then return true end
  end
  for _, w in ipairs(def.warps or {}) do
    if tonumber(w.x) == x and tonumber(w.y) == y then return true end
  end
  return false
end

local function walkable(layout, x, y)
  return CollPermissions.isWalkable(layout:collAt(x, y)) and layout:collAt(x, y) ~= 0xff
end

local function findPath(layout, def)
  local best
  for y = 2, layout.trueHeight - 3 do
    for x = 1, layout.trueWidth - 3 do
      if not walkable(layout, x, y) and walkable(layout, x, y + 1) and walkable(layout, x + 1, y + 1)
          and walkable(layout, x, y + 2) and not occupied(def, x, y) and not occupied(def, x, y + 1)
          and not occupied(def, x + 1, y + 1) then
        local score = math.abs(x - layout.trueWidth / 2) + math.abs(y - layout.trueHeight / 2)
        if not best or score < best.score then best = { x = x, y = y, score = score } end
      end
    end
  end
  return best
end

local function unusedMid(game, pair, def)
  local used = {}
  for id, d in pairs(game.data.maps) do
    if d.pair == pair and id:sub(1, 3) == def.id:sub(1, 3) then
      local l = Map.ensureMidLayout(game, id, d)
      if l then
        for _, c in ipairs(l.cells) do used[c.mid] = true end
        for _, m in ipairs(l.borderMids or {}) do used[m] = true end
      end
    end
  end
  local Extract = require("src.import.gba.extract_island1")
  local Dataset = require("src.core.game3.dataset")
  local idx = NativePack.decodeIdx(Dataset.cache():read(Extract.NATIVE_ROOT .. "/" .. pair .. "/mids.idx"))
  local slots = {}
  for i, mid in ipairs(idx and idx.midIds or {}) do slots[mid] = i - 1 end
  local pixels = idx and idx.pixels
  local best, bestScore = nil, -1
  local blocked = ScriptColl.seed("BLOCKED")
  for mid, beh in pairs(Interaction.behaviors[pair] or {}) do
    if not used[mid] and slots[mid] and pixels
        and NativePack.resolveLayoutColl((ScriptColl.fromCell(mid, 1, beh, def.kind)), 1, nil) == blocked then
      local seen, n = {}, 0
      for p = 1, 256 do
        local v = pixels[slots[mid] * 256 + p]
        if v and v ~= 0 and not seen[v] then seen[v] = true; n = n + 1 end
      end
      if n > bestScore or (n == bestScore and mid < best) then best, bestScore = mid, n end
    end
  end
  return best, bestScore, used
end

local function writeMod(w)
  love.filesystem.createDirectory(ROOT)
  love.filesystem.write(ROOT .. "/manifest.json",
    '{"id":"maplayout3122","name":"map layout 3122","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}')
  love.filesystem.write(ROOT .. "/main.lua", ([[
local mod = ...
local ok, err = mod.content.maps:patch("%s", { cells = {
  { x = %d, y = %d, metatile = %d, collision = 0, elevation = %d },
  { x = %d, y = %d, metatile = %d, collision = 1 },
} })
assert(ok, tostring(err))
local blocks = {}
for y = 0, 5 do
  for x = 0, 5 do
    if x == 0 or y == 0 or x == 5 or y == 5 then
      blocks[#blocks + 1] = { metatile = %d, collision = 1, elevation = %d }
    else
      blocks[#blocks + 1] = { metatile = %d, elevation = %d }
    end
  end
end
ok, err = mod.content.maps:register("%s", { width = 6, height = 6, blocks = blocks,
  pair = mod.content.maps:get("%s").pair, mapType = %d,
  warps = { { x = 2, y = 4, destMap = "%s", destWarp = 1 } } })
assert(ok, tostring(err))
]]):format(w.target, w.x, w.y, w.floor, w.elev, w.x + 1, w.y + 1, w.unused,
    w.wall, w.elev, w.floor, w.elev, w.room, w.target, w.mapType, w.target))
  love.filesystem.write(WITNESS, serialize(w))
end

local function readWitness()
  local raw = love.filesystem.read(WITNESS)
  local chunk = raw and load(raw, "witness", "t", {})
  return chunk and chunk() or nil
end

local function mapErrors(game)
  local out = {}
  for _, e in ipairs(game.mods and game.mods.errors or {}) do
    if tostring(e):find("maps", 1, true) then out[#out + 1] = e end
  end
  return out
end

local function stand(game, mapId, x, y, facing)
  return F.goTo(game, mapId, x, y, facing)
end

local function step(game, dir)
  U.hold(game, dir, 2)
  U.wait(40)
  F.settle(game, 120)
  return Player.cellX, Player.cellY
end

local function checkTarget(game, w, tag)
  local layout, def = layoutOf(game, w.target)
  S.check(layout ~= nil and rawget(def, "modLayout") ~= nil, tag .. " target map carries the mod layout")
  S.check(layout:midAt(w.x, w.y) == w.floor, tag .. " opened cell draws the floor metatile " .. w.floor)
  S.check(layout:midAt(w.x + 1, w.y + 1) == w.unused, tag .. " painted cell holds metatile " .. w.unused)
  S.check(walkable(layout, w.x, w.y), tag .. " opened cell collision is walkable")
  S.check(not walkable(layout, w.x + 1, w.y + 1), tag .. " painted cell collision is blocked")
  S.check(Map.worldMidAt(w.x + 1, w.y + 1, def) == w.unused, tag .. " field sampler reads the painted metatile")
  local ts = NativeTileset.get(def.pair)
  S.check(ts ~= nil and NativeTileset.hasMid(ts, w.unused), tag .. " the pair atlas packs metatile " .. w.unused)
  S.check(ts ~= nil and ts.midToSlot[w.unused] ~= ts.midToSlot[0],
    tag .. " metatile " .. w.unused .. " draws from its own atlas slot")
  S.check(stand(game, w.target, w.x, w.y + 1, "up"), tag .. " standing below the opened cell")
  local x, y = step(game, "up")
  S.check(x == w.x and y == w.y, tag .. " the player walks into the opened cell (" .. x .. "," .. y .. ")")
  S.check(stand(game, w.target, w.x, w.y + 1, "right"), tag .. " standing beside the painted cell")
  x, y = step(game, "right")
  S.check(x == w.x and y == w.y + 1, tag .. " the painted cell refuses the step (" .. x .. "," .. y .. ")")
end

local function checkSharer(game, w, tag)
  local layout = layoutOf(game, w.sharer)
  S.check(layout and layout:midAt(w.x, w.y) == w.wallMid,
    tag .. " the map sharing the layout keeps metatile " .. w.wallMid .. " at the opened cell")
  S.check(layout and not walkable(layout, w.x, w.y), tag .. " the map sharing the layout stays blocked there")
  S.check(layout and layout:midAt(w.x + 1, w.y + 1) == w.floor2, tag .. " the map sharing the layout keeps its floor")
end

local function checkRoom(game, w, tag)
  S.check(game.data.maps[w.room] ~= nil, tag .. " the new map is registered")
  S.check(stand(game, w.room, 2, 3, "left"), tag .. " the new map loads")
  local layout, def = layoutOf(game, w.room)
  S.check(layout and layout.width == 6 and layout.height == 6, tag .. " the new map is 6x6")
  S.check(layout and Map.worldMidAt(2, 2, def) == w.floor, tag .. " the new map draws its floor")
  S.check(layout and Map.worldMidAt(0, 2, def) == w.wall, tag .. " the new map draws its wall")
  local x, y = step(game, "left")
  S.check(x == 1 and y == 3, tag .. " the player walks across the new map floor (" .. x .. "," .. y .. ")")
  x, y = step(game, "left")
  S.check(x == 1 and y == 3, tag .. " the new map wall refuses the step (" .. x .. "," .. y .. ")")
end

local function bootPhase1(game, version)
  local names = MAPS[version]
  local w = { target = names[1], sharer = names[2], room = names[3] }
  local layout, def = layoutOf(game, w.target)
  local shared = layoutOf(game, w.sharer)
  if not S.check(layout ~= nil and shared ~= nil, "both Pokemon Center layouts load") then return nil end
  local same = layout.width == shared.width and layout.height == shared.height
  for i, c in ipairs(layout.cells) do
    if shared.cells[i].mid ~= c.mid then same = false end
  end
  S.check(same, w.target .. " and " .. w.sharer .. " share one layout")
  local path = findPath(layout, def)
  if not path then
    for y = 0, layout.trueHeight - 1 do
      local row = {}
      for x = 0, layout.trueWidth - 1 do
        row[#row + 1] = (walkable(layout, x, y) and "." or "#") .. (occupied(def, x, y) and "o" or " ")
      end
      S.note(table.concat(row))
    end
  end
  if not S.check(path ~= nil, "found a wall cell above open floor") then return nil end
  w.x, w.y = path.x, path.y
  w.wallMid = layout:midAt(w.x, w.y)
  w.wall = w.wallMid
  w.floor = layout:midAt(w.x, w.y + 1)
  w.floor2 = layout:midAt(w.x + 1, w.y + 1)
  w.elev = layout:elevAt(w.x, w.y + 1)
  w.mapType = def.mapType or 8
  local unused, richness, used = unusedMid(game, def.pair, def)
  if not S.check(unused ~= nil, "found a defined metatile no vanilla map of the pair uses") then return nil end
  S.check(not used[unused], ("metatile %d (%d colours) is unused on every %s map"):format(unused, richness, def.pair))
  w.unused = unused
  S.note(("target %s cell (%d,%d) wall %d floor %d elev %d unused %d"):format(w.target, w.x, w.y,
    w.wall, w.floor, w.elev, w.unused))
  S.check(stand(game, w.target, w.x, w.y + 1, "up"), "vanilla " .. w.target .. " loads")
  local x, y = step(game, "up")
  S.check(x == w.x and y == w.y + 1, "vanilla wall refuses the step (" .. x .. "," .. y .. ")")
  S.check(stand(game, w.target, w.x, w.y + 1, "up"), "back below the wall")
  S.check(S.still(game, "01_vanilla_wall_above_player.png"), "shot 01_vanilla_wall_above_player.png")
  writeMod(w)
  for _, key in ipairs({ "type_chart", "growth_rates", "evolution_methods" }) do game.data[key] = nil end
  local ok, err = pcall(function() game:_loadMods() end)
  S.check(ok, "mods reloaded: " .. tostring(err))
  S.check(game.mods and game.mods.mods[MOD] and game.mods.mods[MOD].state == "loaded", "the layout mod loaded")
  local errors = mapErrors(game)
  S.check(#errors == 0, "the maps merge has no errors: " .. table.concat(errors, "; "))
  return w
end

return function(game)
  local Profile = require("src.core.game3.profile")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local version = Profile.active().id
  if not S.check(MAPS[version] ~= nil, "driver covers " .. tostring(version)) then return S.finish() end
  local witness = readWitness()
  if witness then
    S.note("phase 2: mod on disk at boot")
    S.check(game.mods and game.mods.mods[MOD] and game.mods.mods[MOD].state == "loaded", "the layout mod loaded at boot")
    local errors = mapErrors(game)
    S.check(#errors == 0, "the boot maps merge has no errors: " .. table.concat(errors, "; "))
    S.check(game.data.maps[witness.room] ~= nil, "the mod map is registered at boot")
    game:_handleBootAction({ action = "continue" })
    for _ = 1, 1800 do
      if game.phase == "field" and Runtime.getSession() then break end
      U.wait(1)
    end
    U.wait(60)
    F.settle(game, 300)
    local session = Runtime.getSession()
    S.check(session and session.map == witness.target, "continue lands in " .. witness.target .. " ("
      .. tostring(session and session.map) .. ")")
    S.check(S.still(game, "05_continue_after_reload.png"), "shot 05_continue_after_reload.png")
    checkTarget(game, witness, "reload:")
    checkSharer(game, witness, "reload:")
    checkRoom(game, witness, "reload:")
    S.check(S.still(game, "06_mod_room_after_reload.png"), "shot 06_mod_room_after_reload.png")
    love.filesystem.remove(WITNESS)
    return S.finish()
  end

  if not F.boot(game, S) then return S.finish() end
  U.wait(30)
  local w = bootPhase1(game, version)
  if not w then return S.finish() end
  checkTarget(game, w, "live:")
  S.check(stand(game, w.target, w.x, w.y + 1, "up"), "back below the opened cell")
  S.check(S.still(game, "02_opened_path_and_painted_cell.png"), "shot 02_opened_path_and_painted_cell.png")
  S.check(stand(game, w.sharer, w.x, w.y + 1, "up"), "the sharing map loads")
  checkSharer(game, w, "live:")
  S.check(S.still(game, "03_sharing_map_untouched.png"), "shot 03_sharing_map_untouched.png")
  checkTarget(game, w, "re-entry:")
  checkRoom(game, w, "live:")
  S.check(S.still(game, "04_mod_room.png"), "shot 04_mod_room.png")
  S.check(stand(game, w.target, w.x, w.y + 1, "up"), "back in the target before saving")
  local saved = game:saveGame()
  S.check(saved ~= false, "game saved")
  U.wait(30)
  S.finish()
end
