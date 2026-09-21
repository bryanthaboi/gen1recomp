-- mod.world for Gen 3 (FireRed): the Gen 1 / Gen 2 WorldAPI method set,
-- resolved against src/core/game3 at call time.

local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Gen3Compat = require("src.mods.Gen3Compat")

local WorldAPI = {}
WorldAPI.__index = WorldAPI

local NO_OVERWORLD = "no overworld"
local UNSUPPORTED = "not supported on FireRed yet"
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local warned = {}
local function warnOnce(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  Logger.warn(fmt, ...)
end

local function loaded(name)
  return package.loaded["src.core.game3." .. name]
end

local function g3(name)
  local ok, module = pcall(require, "src.core.game3." .. name)
  if ok then return module end
  return nil
end

local function session()
  local R = loaded("runtime")
  local s = R and R.getSession and R.getSession()
  return s
end

local function validPartySlot(party, slot)
  return type(slot) == "number" and slot == math.floor(slot)
    and party[slot] ~= nil
end

local function monInfo(mon, slot)
  local P = loaded("pokemon")
  local name = mon.nickname
  if name == nil or name == "" then name = mon.name end
  if (name == nil or name == "") and P and P.name then name = P.name(mon.species) end
  return { slot = slot, species = Gen3Compat.speciesName(mon.species) or mon.species,
    gen3Species = mon.species, name = name, level = mon.level, hp = mon.hp,
    maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp }
end

function WorldAPI.new(game, modId)
  return setmetatable({ game = game, modId = modId }, WorldAPI)
end

function WorldAPI:_field()
  local F = loaded("field")
  if not (F and F.running and session()) then return nil end
  local game = self.game
  if game and game.phase ~= nil and game.phase ~= "field" then return nil end
  return F
end

function WorldAPI:overworld()
  if not self:_field() then return nil end
  return Gen3Compat.resolve("src.world.OverworldController")
end

function WorldAPI:current()
  if not self:_field() then return nil, NO_OVERWORLD end
  local M = loaded("map")
  local P = loaded("player")
  local s = session()
  local mapId = (M and M.current) or s.map
  return { mapId = mapId, gen1MapId = Gen3Compat.gen1MapId(mapId),
           x = P and P.cellX or s.x, y = P and P.cellY or s.y,
           facing = P and P.facing or s.facing }
end

local function validCoordinate(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value)
end

function WorldAPI:activeBlockAt(mapId, bx, by)
  if not self:_field() then return nil, NO_OVERWORLD end
  local M = loaded("map")
  if not (M and M.current) then return nil, NO_OVERWORLD end
  if Gen3Compat.gen3MapId(mapId) ~= M.current then return nil, "map is not active" end
  if not validCoordinate(bx) or not validCoordinate(by) then
    return nil, "invalid block coordinates"
  end
  local C = loaded("collision")
  if not (C and C.inBounds(bx, by)) then return nil, "block coordinates out of bounds" end
  local behavior = C.behavior(bx, by)
  if not validCoordinate(behavior) then return nil, "block unavailable" end
  warnOnce("activeBlockAt",
    "[%s] mod.world:activeBlockAt on FireRed answers the 16px metatile's "
    .. "BEHAVIOUR byte; FireRed has no 32px blocks", tostring(self.modId))
  return behavior
end

function WorldAPI:canReorderParty()
  local s = session()
  local party = s and s.party or {}
  return #party > 1 and self:_field() ~= nil and not Gen3Compat.worldBusy()
end

function WorldAPI:reorderParty(fromSlot, toSlot)
  if not self:_field() then return nil, NO_OVERWORLD end
  if Gen3Compat.worldBusy() then return nil, "world is busy" end
  local s = session()
  local party = s.party or {}
  if not validPartySlot(party, fromSlot) or not validPartySlot(party, toSlot) then
    return nil, "invalid party slot"
  end
  if fromSlot ~= toSlot then
    party[fromSlot], party[toSlot] = party[toSlot], party[fromSlot]
    local overlay = s.move_overlay
    if type(overlay) == "table" then
      overlay[fromSlot], overlay[toSlot] = overlay[toSlot], overlay[fromSlot]
    end
    local A = loaded("audio")
    if A and A.playSe then pcall(A.playSe, 5) end
  end
  return true
end

local FIELD_ACTIONS = {
  { id = "cut", move = "CUT" },
  { id = "surf", move = "SURF" },
  { id = "strength", move = "STRENGTH" },
  { id = "flash", move = "FLASH" },
  { id = "rock_smash", move = "ROCK_SMASH" },
  { id = "waterfall", move = "WATERFALL" },
  { id = "dig", move = "DIG" },
  { id = "teleport", move = "TELEPORT" },
  { id = "sweet_scent", move = "SWEET_SCENT" },
}

local HEAL_ACTIONS = {
  { id = "softboiled", move = "SOFTBOILED" },
  { id = "milk_drink", move = "MILK_DRINK" },
}

local function fieldContext(mon)
  local P = loaded("player")
  local C = loaded("collision")
  local Objects = loaded("objects")
  local M = loaded("map")
  local S = package.loaded["src.core.game3.scripting.space"]
  local s = session()
  local d = DELTA[P and P.facing or "down"] or DELTA.down
  local fx, fy = P.cellX + d[1], P.cellY + d[2]
  local mapDef = M and M.currentDef and M.currentDef()
  return {
    party = s.party,
    mon = mon,
    store = S and S.store,
    session = s,
    facingObject = Objects and Objects.at(fx, fy),
    isFacingWater = C and C.isWater and C.isWater(fx, fy),
    isSurfing = P.surfing == true,
    hasCuttableGrass = C and C.isGrass
      and (C.isGrass(fx, fy) or C.isGrass(P.cellX, P.cellY)),
    mapType = mapDef and mapDef.type,
  }
end

local function moveResult(move)
  local FM = g3("field_moves")
  local s = session()
  if not (FM and s) then return nil end
  local mon = FM.partyMoveUser(s.party, move)
  if not mon then return nil end
  local ok, res = pcall(FM.fromMenu, move, fieldContext(mon))
  if ok and res and res.ok then return res, mon end
  return nil
end

local function healSources(move)
  local FM = g3("field_moves")
  local s = session()
  local out = {}
  if not (FM and s) then return out end
  local P = loaded("pokemon")
  local num = FM.MOVES[move]
  for sourceSlot, source in ipairs(s.party or {}) do
    local maxHp = source.maxHp or source.hp or 0
    local cost = math.floor(maxHp / 5)
    if P and num and P.knowsMove(source, num) and (source.hp or 0) > cost then
      local info = monInfo(source, sourceSlot)
      info.cost = cost
      info.targets = {}
      for targetSlot, target in ipairs(s.party) do
        if FM.softboiledTargetOk(source, target) then
          info.targets[#info.targets + 1] = monInfo(target, targetSlot)
        end
      end
      if #info.targets > 0 then out[#out + 1] = info end
    end
  end
  return out
end

local function bikeId()
  return Gen3Compat.itemId("BICYCLE") or 360
end

function WorldAPI:availableFieldActions()
  local out = {}
  if not self:_field() then return out, NO_OVERWORLD end
  if Gen3Compat.worldBusy() then return out, "world is busy" end
  local s = session()
  local Bag = g3("bag")
  local P = loaded("player")
  if Bag and s.bag and Bag.has(s.bag, bikeId(), 1) and not (P and P.surfing) then
    out[#out + 1] = { id = "bicycle",
      label = (P and P.biking) and "BIKE OFF" or "BICYCLE" }
  end
  for _, row in ipairs(FIELD_ACTIONS) do
    if moveResult(row.move) then
      out[#out + 1] = { id = row.id, label = (row.move:gsub("_", " ")) }
    end
  end
  for _, row in ipairs(HEAL_ACTIONS) do
    local sources = healSources(row.move)
    if #sources > 0 then
      out[#out + 1] = { id = row.id, label = (row.move:gsub("_", " ")),
        sources = sources }
    end
  end
  return out
end

function WorldAPI:useFieldAction(id, opts)
  local F = self:_field()
  if not F then return nil, NO_OVERWORLD end
  if Gen3Compat.worldBusy() then return nil, "world is busy" end
  local found
  for _, action in ipairs(self:availableFieldActions()) do
    if action.id == id then found = action break end
  end
  if not found then return nil, "field action unavailable" end
  local s = session()
  local Message = package.loaded["src.ui.game3.message"]
  if id == "bicycle" then
    local IU = g3("item_use")
    if not IU then return nil, "field action unavailable" end
    local ok, _, text = IU.useBike(s)
    if text and Message then Message.show(text, function() Message.close() end) end
    return ok and true or nil, (not ok) and "field action unavailable" or nil
  end
  if id == "softboiled" or id == "milk_drink" then
    local FM = g3("field_moves")
    local sourceSlot = opts and tonumber(opts.sourceSlot)
    local targetSlot = opts and tonumber(opts.targetSlot)
    local cost
    for _, source in ipairs(found.sources or {}) do
      if source.slot == sourceSlot then
        for _, target in ipairs(source.targets or {}) do
          if target.slot == targetSlot then cost = source.cost break end
        end
      end
    end
    if not (cost and FM) then return nil, "softboiled target unavailable" end
    local ok = FM.softboiledTransfer(s.party[sourceSlot], s.party[targetSlot], cost)
    if not ok then return nil, "softboiled target unavailable" end
    return true
  end
  for _, row in ipairs(FIELD_ACTIONS) do
    if row.id == id then
      local res = moveResult(row.move)
      if not (res and F.executeFieldMove) then return nil, "field action unavailable" end
      F.executeFieldMove(res)
      return true
    end
  end
  return nil, "field action unavailable"
end

function WorldAPI:canFly()
  if not self:_field() then return false end
  return moveResult("FLY") ~= nil
end

function WorldAPI:flyTo(mapId)
  if not self:_field() then return nil, NO_OVERWORLD end
  if not self:canFly() then return nil, "fly unavailable" end
  warnOnce("flyTo",
    "[%s] mod.world:flyTo(%s): FireRed's fly destinations are the region "
    .. "map's town spawn points (src/ui/game3/region_map.lua), which have no "
    .. "seam yet", tostring(self.modId), tostring(mapId))
  return nil, UNSUPPORTED
end

function WorldAPI:mapOverview()
  if not self:_field() then return nil, NO_OVERWORLD end
  local M = loaded("map")
  local C = loaded("collision")
  local def = M and M.currentDef and M.currentDef()
  if not (def and C) then return nil, NO_OVERWORLD end
  local view = {
    id = M.current,
    widthCells = tonumber(def.width) or 0,
    heightCells = tonumber(def.height) or 0,
  }
  function view:isWarpTileCell(x, y) return C.warpAt(x, y) ~= nil end
  function view:isWaterCell(x, y) return C.isWater(x, y) end
  function view:isWalkableCell(x, y) return C.isWalkable(x, y) end
  local markers = {}
  for _, warp in ipairs(def.warps or {}) do
    markers[#markers + 1] = { kind = "warp", x = warp.x, y = warp.y }
  end
  local Objects = loaded("objects")
  for _, lid in ipairs(Objects and Objects._order or {}) do
    local eo = Objects._byId[lid]
    local script = eo and eo.def and eo.def.scriptKey
    if eo and eo.visible and not eo.hidden and eo.def and eo.def.item then
      markers[#markers + 1] = { kind = "item", x = eo.cellX, y = eo.cellY,
        script = script }
    end
  end
  return require("src.world.MapOverview").build(view, markers)
end

function WorldAPI:warpTo(mapId, x, y, facing, opts)
  if not self:_field() then return nil, NO_OVERWORLD end
  local raw = Gen3Compat.gen3MapId(mapId)
  if not raw then return nil, "unknown map: " .. tostring(mapId) end
  if not (x and y) then return nil, "warpTo needs x and y" end
  local W = g3("warp")
  if not W then return nil, NO_OVERWORLD end
  local P = loaded("player")
  local warpOpts = {}
  if opts and opts.arrive == "teleport" then warpOpts.teleport = true end
  if opts and opts.fade == false then warpOpts.fade = false end
  local ok, err = W.request(nil, self.game, raw, x, y,
    facing or (P and P.facing) or "down", warpOpts)
  if not ok then return nil, err or "warp failed" end
  return true
end

function WorldAPI:toggleObject(mapId, objRef, visible)
  if not self:_field() then return nil, NO_OVERWORLD end
  local M = loaded("map")
  local raw = Gen3Compat.gen3MapId(mapId)
  if not (M and raw and M.current == raw) then
    return nil, "map is not active: " .. tostring(mapId)
  end
  local Objects = loaded("objects")
  if not Objects then return nil, "map has no objects" end
  local lid
  for _, def in ipairs(Objects._defs or {}) do
    local id = tonumber(def.localId or def.index)
    if id == objRef or def.name == objRef or def.id == objRef then lid = id break end
  end
  if not lid then return nil, "no such object: " .. tostring(objRef) end
  if visible then Objects.addObject(lid) else Objects.removeObject(lid) end
  Runtime.emit("world.object_toggled",
    { mapId = raw, objName = objRef, visible = visible and true or false })
  return true
end

function WorldAPI:setFlag(name, value)
  if not session() then return nil, "no save" end
  return Gen3Compat.setFlag(name, value)
end

function WorldAPI:getFlag(name)
  if not session() then return nil, "no save" end
  return Gen3Compat.getFlag(name)
end

local ENCOUNTER_TERRAIN = { grass = true, water = true, indoor = true }
local LAND_WEIGHTS = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
local WATER_WEIGHTS = { 60, 30, 5, 4, 1 }

function WorldAPI:effectiveEncounters(mapId, terrain, opts)
  if not ENCOUNTER_TERRAIN[terrain] then
    return nil, "invalid terrain: " .. tostring(terrain)
  end
  local E = g3("encounters")
  if not E then return { chance = 0, dist = {} } end
  if E.ensureLoaded then pcall(E.ensureLoaded) end
  local raw = Gen3Compat.gen3MapId(mapId) or mapId
  local tables = E._tables or {}
  local t = tables[raw] or tables[tostring(raw)]
  local keys = terrain == "water" and { "water" } or { "land", "grass" }
  local weights = terrain == "water" and WATER_WEIGHTS or LAND_WEIGHTS
  local area
  for _, key in ipairs(keys) do
    area = t and t[key]
    if area then break end
  end
  local slots = area and (area.slots or area.mons or (#area > 0 and area))
  local rate = tonumber(area and area.rate) or 0
  local dist = {}
  for i, weight in ipairs(weights) do
    local slot = slots and slots[i]
    local sp = type(slot) == "table" and (slot.species or slot[1])
    if sp then
      local name = Gen3Compat.speciesName(sp) or sp
      dist[name] = (dist[name] or 0) + weight
    end
  end
  if Runtime.wantsHook("encounter.table") then
    local transformed = Runtime.call("encounter.table",
      function(d) return d end, dist,
      { mapId = raw, terrain = terrain, preview = true, opts = opts })
    if type(transformed) == "table" then dist = transformed end
  end
  return { chance = math.min(rate * 16, 2880) / 2880, dist = dist }
end

function WorldAPI:replaceBlock(bx, by, block)
  local F = self:_field()
  if not F then return nil, NO_OVERWORLD end
  warnOnce("replaceBlock",
    "[%s] mod.world:replaceBlock on FireRed sets one 16px METATILE at (x, y); "
    .. "FireRed has no 32px blocks", tostring(self.modId))
  F.setMetatile(bx, by, block)
  local M = loaded("map")
  Runtime.emit("world.block_replaced",
    { mapId = M and M.current, bx = bx, by = by, block = block })
  return true
end

function WorldAPI:spawnNpc(_mapId, _objDef)
  warnOnce("spawnNpc",
    "[%s] mod.world:spawnNpc: FireRed event objects come from the map's "
    .. "extracted templates only", tostring(self.modId))
  return nil, UNSUPPORTED
end

function WorldAPI:liveMaps()
  if not self:_field() then return nil, NO_OVERWORLD end
  local M = loaded("map")
  local mapId = (M and M.current) or session().map
  if not mapId then return nil, NO_OVERWORLD end
  local out = { { mapId = mapId, ox = 0, oy = 0, active = true } }
  for _, e in ipairs((M and M.world) or {}) do
    if e.id ~= mapId then
      out[#out + 1] = { mapId = e.id, ox = e.ox, oy = e.oy, active = false }
    end
  end
  return out
end

function WorldAPI:removeNpc(npcId)
  if not self:_field() then return nil, NO_OVERWORLD end
  local Objects = loaded("objects")
  if not Objects then return nil, NO_OVERWORLD end
  warnOnce("removeNpc",
    "[%s] mod.world:removeNpc on FireRed hides a template object by localId "
    .. "and sets its hide flag", tostring(self.modId))
  return Objects.removeObject(npcId) and true or nil
end

local Handle = {}
Handle.__index = Handle

function Handle:scriptMove(dir, tiles, onDone)
  local Objects = loaded("objects")
  if not Objects then return nil, NO_OVERWORLD end
  if not DELTA[dir] then return nil, "unknown direction: " .. tostring(dir) end
  local actions = {}
  for _ = 1, math.max(0, tiles or 1) do
    actions[#actions + 1] = { kind = "step", dir = dir }
  end
  Objects.startTrack(self.id, actions, onDone)
  return true
end

function Handle:marchInPlace(onDone)
  local Objects = loaded("objects")
  if not Objects then return nil, NO_OVERWORLD end
  Objects.startTrack(self.id, { { kind = "turn", dir = self.npc.facing },
    { kind = "sleep", frames = 16 } }, onDone)
  return true
end

function Handle:face(dir)
  local Objects = loaded("objects")
  if not (Objects and DELTA[dir]) then return nil, "unknown direction" end
  Objects.scriptFace(self.npc, dir)
  return true
end

function Handle:position()
  return self.npc.cellX, self.npc.cellY
end

function Handle:stepNow(dir)
  local npc = self.npc
  local d = DELTA[dir]
  if not d then return nil, "bad direction: " .. tostring(dir) end
  if npc.moving then return nil, "already moving" end
  local Objects = loaded("objects")
  if not Objects then return nil, NO_OVERWORLD end
  local wasFrozen = npc.frozen
  Objects.scriptStep(npc, dir)
  npc.frozen = wasFrozen
  npc.scriptBusy = false
  return true
end

function Handle:canStep(dir)
  local d = DELTA[dir]
  local C = loaded("collision")
  if not (d and C) then return false end
  local npc = self.npc
  local tx, ty = npc.cellX + d[1], npc.cellY + d[2]
  -- pokefirered/src/event_object_movement.c:4830 GetCollisionAtCoords
  local onWater = C.isWater(npc.cellX, npc.cellY)
  if not C.canEnter(nil, tx, ty, { fromX = npc.cellX, fromY = npc.cellY,
      dir = dir, surfing = onWater }) then
    return false
  end
  -- pokefirered/src/event_object_movement.c:8346 IsElevationMismatchAt
  return C.isWater(tx, ty) == onWater
end

function Handle:placeAt(x, y, facing)
  local npc = self.npc
  npc.moving = false
  npc.progress = 0
  npc.cellX, npc.cellY = x, y
  npc.targetX, npc.targetY = x, y
  npc.px, npc.py = x * 16, y * 16
  if facing then npc.facing = facing end
  return true
end

function Handle:isMoving()
  return self.npc.moving and true or false
end

function Handle:setPassable(passable)
  self.npc.passable = passable and true or false
  return true
end

function WorldAPI:npc(mapId, indexOrName)
  if not self:_field() then return nil, NO_OVERWORLD end
  local M = loaded("map")
  local raw = Gen3Compat.gen3MapId(mapId)
  if not (M and M.current == raw) then return nil, "map is not active" end
  local Objects = loaded("objects")
  for _, lid in ipairs(Objects and Objects._order or {}) do
    local eo = Objects._byId[lid]
    local def = eo and eo.def
    if eo and (lid == indexOrName or (def and (def.name == indexOrName
        or def.id == indexOrName))) then
      return setmetatable({ npc = eo, id = lid }, Handle)
    end
  end
  return nil, "no such object: " .. tostring(indexOrName)
end

local VERBS = {}

function VERBS.start_battle(api, row, resume)
  if row[2] ~= "wild" then
    return nil, "only start_battle \"wild\" is supported on FireRed"
  end
  return api:startWildBattle(row[3], row[4], resume)
end

function VERBS.warp(api, row, resume)
  local ok, err = api:warpTo(row[2], row[3], row[4], row[5])
  if not ok then return nil, err end
  resume()
  return true
end

function VERBS.text(_api, row, resume)
  local Message = package.loaded["src.ui.game3.message"]
    or select(2, pcall(require, "src.ui.game3.message"))
  if type(Message) ~= "table" then return nil, NO_OVERWORLD end
  Message.show(tostring(row[2] or ""), function()
    Message.close()
    resume()
  end)
  return true
end

function VERBS.setflag(api, row, resume)
  local ok, err = api:setFlag(row[2], true)
  if not ok then return nil, err end
  resume()
  return true
end

function VERBS.clearflag(api, row, resume)
  local ok, err = api:setFlag(row[2], false)
  if not ok then return nil, err end
  resume()
  return true
end

function WorldAPI:queueScript(rows, extra)
  if not self:_field() then return nil, NO_OVERWORLD end
  if type(rows) ~= "table" then return nil, "queueScript wants a row list" end
  if self.queue then return nil, "a script is already running" end
  for i, row in ipairs(rows) do
    local name = type(row) == "table" and row[1]
    if not VERBS[name] then
      return nil, ("unsupported script command on FireRed: %s (row %d)")
        :format(tostring(name), i)
    end
  end
  self.queue = true
  local pc = 0
  local step
  local function finish(err)
    self.queue = nil
    if err then
      Logger.warn("[%s] queueScript stopped: %s", tostring(self.modId), err)
    end
    if extra and extra.onDone then extra.onDone(err == nil) end
  end
  step = function()
    pc = pc + 1
    local row = rows[pc]
    if not row then return finish(nil) end
    local ok, err = VERBS[row[1]](self, row, function() step() end)
    if not ok then finish(err or "row failed") end
  end
  step()
  return true
end

function WorldAPI:startWildBattle(species, level, onDone)
  if not self:_field() then return nil, NO_OVERWORLD end
  local sp = Gen3Compat.speciesId(species)
  local P = g3("pokemon")
  if not (sp and P and P.name and P._names and P._names[sp]) then
    return nil, "unknown species: " .. tostring(species)
  end
  level = tonumber(level)
  if not level or level % 1 ~= 0 or level < 1 or level > 100 then
    return nil, "level must be a whole number 1..100"
  end
  local B = package.loaded["src.core.game3.battle.init"]
  if B and B.isActive and B.isActive() then return nil, "a battle is already running" end
  local W = loaded("warp")
  if W and W.isBusy and W.isBusy() then return nil, "the world is mid-warp" end
  local s = session()
  local healthy = false
  for _, mon in ipairs(s.party or {}) do
    if (tonumber(mon.hp) or 0) > 0 then healthy = true break end
  end
  if not healthy then return nil, "no healthy party" end
  local BB = g3("battle_bridge")
  if not BB then return nil, NO_OVERWORLD end
  local ok, err = BB.startWild(nil, self.game, { species = sp, level = level },
    { done = onDone and function() onDone() end or nil })
  if not ok then return nil, err or "battle failed" end
  return true
end

function WorldAPI:invalidateMap(mapId)
  local raw = Gen3Compat.gen3MapId(mapId) or mapId
  local M = loaded("map")
  if not (self:_field() and M and M.current == raw) then
    Runtime.emit("map.reloaded", { mapId = raw, reason = "invalidate" })
    return true
  end
  local P = loaded("player")
  local ok, err = pcall(M.load, nil, self.game, raw, { x = P and P.cellX,
    y = P and P.cellY, facing = P and P.facing, depth1Connections = true })
  if not ok then
    Logger.warn("[%s] invalidateMap %s failed: %s", tostring(self.modId),
                tostring(mapId), tostring(err))
    return nil, tostring(err)
  end
  Runtime.emit("map.reloaded", { mapId = raw, reason = "invalidate" })
  return true
end

return WorldAPI
