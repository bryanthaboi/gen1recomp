local UnifiedWorld = {}
local unpack = table.unpack or unpack

UnifiedWorld.METHODS = {
  "overworld", "current", "activeBlockAt", "party", "canReorderParty",
  "reorderParty", "availableFieldActions", "useFieldAction", "canFly",
  "flyTo", "mapOverview", "warpTo", "toggleObject", "setFlag", "getFlag",
  "effectiveEncounters", "replaceBlock", "spawnNpc", "liveMaps", "removeNpc",
  "npc", "queueScript", "startWildBattle", "invalidateMap",
}

local METHOD_SET = {}
for _, name in ipairs(UnifiedWorld.METHODS) do METHOD_SET[name] = true end
local MODULES = {
  "src.world.WorldAPI", "src.world.gen2.WorldAPI", "src.world.game3.WorldAPI",
}
local DIRS = { up = true, down = true, left = true, right = true }
local SCRIPT_CANCEL = setmetatable({}, { __mode = "k" })
local MUTATES = {
  reorderParty = true, useFieldAction = true, flyTo = true, warpTo = true,
  toggleObject = true, replaceBlock = true, spawnNpc = true, removeNpc = true,
  queueScript = true, startWildBattle = true, invalidateMap = true,
}

local function integer(n, min, max)
  return type(n) == "number" and n == n and n ~= math.huge
    and n ~= -math.huge and n == math.floor(n)
    and (min == nil or n >= min) and (max == nil or n <= max)
end

local function identifier(s)
  return type(s) == "string" and #s > 0 and #s <= 256
    and not s:find("%c")
end

local function objectRef(value)
  return identifier(value) or integer(value, 0)
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
  return out
end

function UnifiedWorld.supports(name, generation, version)
  if not METHOD_SET[name] then return false, "unknown world method" end
  if not MODULES[generation] then return false, "unsupported generation" end
  return true
end

function UnifiedWorld.cancel(facade, reason)
  local cancel = SCRIPT_CANCEL[facade]
  if cancel then return cancel(reason) end
  return false
end

function UnifiedWorld.new(gameProvider, generation, version, modId, engineRequire)
  local req = engineRequire or require
  local Ids = req("src.mods.UnifiedIds")
  local facade = {}
  local queueFn

  local function g3(name) return req("src.core.game3." .. name) end

  local function saveOf(game)
    if generation == 3 then return game and game.session end
    return game and game.save
  end

  local function partyOf(game)
    local save = saveOf(game)
    return save and save.party or {}
  end

  local function metadata()
    return { tileSize = generation == 3 and 16 or 32, cellSize = 16,
      coordinateBase = 0, kind = generation == 3 and "metatile" or "block" }
  end

  local function resolve()
    local game = gameProvider()
    if not game then return nil, nil, "no game" end
    return game, req(MODULES[generation]).new(game, modId)
  end

  local function ready(game, api, ownToken)
    if generation == 3 then
      local field = api:_field()
      if not field then return nil, "no overworld" end
      if (field._modScriptLock and field._modScriptLock ~= ownToken)
          or req("src.mods.Gen3Compat").worldBusy(ownToken) then
        return nil, "world is busy"
      end
      return true
    end
    local ow = api:overworld()
    if not ow then return nil, "no overworld" end
    if ow._modScriptLock and ow._modScriptLock ~= ownToken then
      return nil, "world is busy"
    end
    local stack = game.stack
    if stack and stack.top then
      local top = stack:top()
      if generation == 1 and top ~= ow then return nil, "world is busy" end
      if generation == 2 and top and top ~= ow then
        return nil, "world is busy"
      end
    end
    if generation == 2 then
      if not ow:acceptsMenuInput(ownToken) then return nil, "world is busy" end
    else
      local runner = ow.runner
      if ow.transitioning or ow.flyAnim or ow.teleportOut or ow.engaging
          or ow.emote or ow.pikaHop or ow.healAnim
          or (ow.player and (ow.player.moving or ow.player.inputLocked))
          or (runner and runner.isRunning and runner:isRunning())
          or #(ow.scriptMoves or {}) > 0 then
        return nil, "world is busy"
      end
    end
    return true
  end

  local function mapDef(game, mapId)
    if generation == 3 then
      mapId = req("src.mods.Gen3Compat").gen3MapId(mapId) or mapId
    end
    local ow = generation == 2 and game.world
    local maps = ow and ow.maps or (game.data and game.data.maps)
    return maps and maps[mapId], mapId
  end

  local function warpArgs(game, mapId, x, y, facing, opts)
    if not identifier(mapId) then return nil, "invalid map id" end
    local def = mapDef(game, mapId)
    if not def then return nil, "unknown map: " .. mapId end
    if not integer(x, 0) or not integer(y, 0) then
      return nil, "invalid coordinates"
    end
    local layout = generation == 3 and def.midLayout
    local w = layout and layout.width or def.width
    local h = layout and layout.height or def.height
    local scale = generation == 3 and 1 or 2
    if (w and x >= w * scale) or (h and y >= h * scale) then
      return nil, "coordinates out of bounds"
    end
    if facing ~= nil and not DIRS[facing] then return nil, "invalid facing" end
    if opts ~= nil and type(opts) ~= "table" then return nil, "invalid options" end
    if opts then
      for k, v in pairs(opts) do
        if k == "arrive" then
          if v ~= "fly" and v ~= "teleport" then return nil, "invalid arrival" end
        elseif k == "onDone" then
          if type(v) ~= "function" then return nil, "invalid callback" end
        elseif k == "keepMusic" then
          if type(v) ~= "boolean" then return nil, "invalid options" end
        elseif k == "fade" then
          if type(v) ~= "boolean" then return nil, "invalid options" end
          if generation ~= 3 then return nil, "unsupported fade" end
        else return nil, "unknown warp option: " .. tostring(k) end
      end
    end
    return true
  end

  local function warp(game, api, mapId, x, y, facing, opts)
    local ok, err = warpArgs(game, mapId, x, y, facing, opts)
    if not ok then return nil, err end
    local accepted, pending, completed, retire
    if opts and opts.onDone then
      opts = copy(opts)
      local callback, save = opts.onDone, saveOf(game)
      local runtime = req("src.mods.Runtime")
      local hooks, events = runtime.hooks, runtime.events
      local epoch = hooks.ownerEpoch and hooks:ownerEpoch(modId)
      local ow = api:overworld()
      local field = generation == 3 and api:_field()
      local native = generation == 3 and g3("runtime")
      local nativeSession = native and native.getSession()
      local _, destination = mapDef(game, mapId)
      local unsubscribeMap, unsubscribeUpdate, entered
      retire = function()
        completed = true
        if unsubscribeMap then unsubscribeMap(); unsubscribeMap = nil end
        if unsubscribeUpdate then unsubscribeUpdate(); unsubscribeUpdate = nil end
      end
      local function currentApi()
        local current, live = resolve()
        if current ~= game or saveOf(current) ~= save or not live
            or runtime.hooks ~= hooks or runtime.events ~= events
            or hooks.ownerEpoch and hooks:ownerEpoch(modId) ~= epoch
            or live:overworld() ~= ow then return end
        if native and (g3("runtime") ~= native or native.getSession() ~= nativeSession
            or nativeSession ~= save or live:_field() ~= field
            or field._session and field._session ~= save) then return end
        return live
      end
      if generation == 1 and events.on and hooks.wrap then
        unsubscribeMap = events:on("map.entered", function(payload)
          if completed then return end
          if not currentApi() or entered or payload.mapId ~= destination then
            retire()
            return
          end
          entered = true
        end, math.huge, modId)
        unsubscribeUpdate = hooks:wrap("core.update", function(nextFn, ...)
          local function observed(ok, ...)
            if not completed then
              local valid, live = pcall(currentApi)
              if not valid or not live then retire() end
            end
            if not ok then retire(); error((...), 0) end
            return ...
          end
          return observed(pcall(nextFn, ...))
        end, math.huge, modId)
      end
      opts.onDone = function(...)
        if completed then return end
        if accepted == nil then
          if not pending then pending = { n = select("#", ...), ... } end
          return
        end
        retire()
        if not accepted then return end
        local previous = runtime.currentMod
        local called, why = pcall(function(...)
          local live = currentApi()
          if not live then return end
          local location = live:current()
          if not location or location.mapId ~= destination then return end
          runtime.currentMod = modId
          callback(...)
        end, ...)
        runtime.currentMod = previous
        if not called then
          runtime.reportError(modId, "world warp callback failed: " .. tostring(why))
        end
      end
    end
    local called, result, detail = pcall(api._warpToWith or api.warpTo, api, mapId, x, y, facing, opts)
    accepted = called and result ~= nil and result ~= false
    if not accepted then
      if retire then retire() else completed = true end
      if not called then return nil, "world operation failed: " .. tostring(result) end
      return nil, detail or "world operation failed"
    end
    if pending then opts.onDone(unpack(pending, 1, pending.n)) end
    return result, detail
  end

  local function blockAt(game, api, mapId, x, y)
    if not identifier(mapId) then return nil, "invalid map id" end
    if not integer(x, 0) or not integer(y, 0) then
      return nil, "invalid block coordinates"
    end
    local id
    if generation == 3 then
      if not api:_field() then return nil, "no overworld" end
      local M = g3("map")
      local raw = req("src.mods.Gen3Compat").gen3MapId(mapId) or mapId
      if raw ~= M.current then return nil, "map is not active" end
      local def = M.currentDef()
      local layout = def and def.midLayout
      if not (layout and layout.midAt and integer(layout.width, 1)
          and integer(layout.height, 1)) then return nil, "block unavailable" end
      if x >= layout.width or y >= layout.height then
        return nil, "block coordinates out of bounds"
      end
      local override = g3("field").metatileOverrideAt(raw, x, y)
      id = override and override.metatile or layout:midAt(x, y)
    elseif generation == 2 then
      local ow = api:overworld()
      if not ow then return nil, "no overworld" end
      local map = ow.map
      if map.id ~= mapId then return nil, "map is not active" end
      if not integer(map.width, 1) or not integer(map.height, 1) then
        return nil, "block unavailable"
      end
      if x >= map.width or y >= map.height then
        return nil, "block coordinates out of bounds"
      end
      id = map.blocks and map.blocks[y * map.width + x + 1]
    else
      local err
      id, err = api:activeBlockAt(mapId, x, y)
      if id == nil then return nil, err end
    end
    if not integer(id, 0) then return nil, "block unavailable" end
    return id, metadata()
  end

  local function flagId(name)
    if type(name) == "string" then
      local key = name:match("^mod:(.+)$")
      if not key and name:sub(1, 4) == "mod." then
        local prefix = "mod." .. tostring(modId) .. "."
        if name:sub(1, #prefix) ~= prefix then return nil, "foreign mod flag" end
        key = name:sub(#prefix + 1)
      end
      if key then
        if not identifier(key) or not identifier(modId) then
          return nil, "invalid mod flag"
        end
        return key, "mod"
      end
    end
    if generation == 1 then
      local suffix = version == "yellow" and "_yellow" or ""
      local names = req("src.save_convert.data.event_flags" .. suffix).byBit
      if integer(name, 0) and names[name] then return names[name], "native" end
      if identifier(name) then
        for _, symbol in pairs(names) do
          if symbol == name then return name, "native" end
        end
      end
    elseif generation == 2 then
      if integer(name, 0, 2047) then return name, "native" end
      if identifier(name) then
        if version == "crystal" then
          return nil, "symbolic event flags unavailable for Crystal; use native ids"
        end
        local id = req("src.core.gen2.FlagNames").events[name]
        if integer(id, 0, 2047) then return id, "native" end
      end
    else
      local flags = g3("scripting.flags").forVersion(version)
      local id = type(name) == "number" and name
        or (type(name) == "string" and flags.IDS[name])
      if integer(id, 1, (flags.FLAGS_COUNT or 0x900) - 1) then
        if type(name) == "number" or (flags.NAMES and flags.NAMES[id]) then
          return id, "native"
        end
      end
    end
    return nil, "invalid or unknown flag"
  end

  local function flag(game, api, name, value, write)
    if write and type(value) ~= "boolean" then return nil, "flag value must be boolean" end
    local id, kind = flagId(name)
    if id == nil then return nil, kind end
    local save = saveOf(game)
    if not save then return nil, "no save" end
    if kind == "mod" then
      if save.modData ~= nil and type(save.modData) ~= "table" then
        return nil, "invalid mod save store"
      end
      local bucket = save.modData and save.modData[modId]
      if bucket ~= nil and type(bucket) ~= "table" then return nil, "invalid mod save store" end
      local flags = bucket and bucket.worldFlags
      if flags ~= nil and type(flags) ~= "table" then return nil, "invalid mod flag store" end
      if not write then return flags ~= nil and flags[id] == true end
      local before = flags ~= nil and flags[id] == true
      save.modData = save.modData or {}
      bucket = bucket or {}
      save.modData[modId] = bucket
      flags = flags or {}
      bucket.worldFlags = flags
      flags[id] = value or nil
      if before ~= value then
        req("src.mods.Runtime").emit("flag.changed",
          { name = "mod." .. modId .. "." .. id, value = value })
      end
      return true
    end
    if write then return api:setFlag(id, value) end
    local result, err = api:getFlag(id)
    if err then return nil, err end
    return result == true
  end

  local function flyUser(game, api)
    if generation == 1 then return api:canFly() end
    if generation == 2 then
      local ow = api:overworld()
      if not ow then return nil end
      local FM = req("src.world.gen2.FieldMoves")
      local ctx = ow:fieldContext()
      local mon = FM.partyMoveUser(ctx.party, "FLY", ctx)
      if not mon then return nil end
      ctx.mon = mon
      local result = FM.flyFromMenu(ctx)
      return result.ok and mon or nil
    end
    if not api:_field() then return nil end
    local FM, M, P = g3("field_moves"), g3("map"), g3("player")
    local save = saveOf(game)
    local mon = FM.partyMoveUser(partyOf(game), "FLY")
    if not mon then return nil end
    local def = M.currentDef()
    local result = FM.flyFromMenu({ party = partyOf(game), mon = mon,
      session = save, store = g3("scripting.space").store,
      mapType = def and def.type, isSurfing = P.surfing == true })
    return result.ok and result.action == "fly" and mon or nil
  end

  local function fly(game, api, mapId)
    if not identifier(mapId) then return nil, "invalid map id" end
    local mon = flyUser(game, api)
    if not mon then return nil, "fly unavailable" end
    if generation == 1 then return api:flyTo(mapId) end
    if generation == 2 then
      local ow = api:overworld()
      for _, row in ipairs(ow:flyPoints()) do
        local spawn = ow.landmarks and ow.landmarks.spawns[row.spawn]
        if spawn and spawn.map == mapId and ow.maps[mapId] then
          if ow:flyTo(row.spawn, mon) then return true end
          return nil, "fly failed"
        end
      end
      return nil, "destination unavailable"
    end
    local def, raw = mapDef(game, mapId)
    if not def then return nil, "unknown map: " .. mapId end
    local F, save = g3("field"), saveOf(game)
    local C = g3("constants").of(version)
    for symbol, sec in pairs(C.region_map_sections.byName) do
      if symbol:sub(1, 7) == "MAPSEC_" then
        local dest, allowed
        if version == "firered" or version == "leafgreen" then
          local RM = req("src.ui.game3.region_map")
          allowed = RM.mapsecType(sec) == RM.MAPSECTYPE.VISITED
          if allowed then dest = F.flyDestination(symbol) end
        else
          local RM = req("src.ui.game3.rse.region_map")
          local kind = RM.mapSecType({ session = save }, sec)
          allowed = kind == RM.TYPE.CITY_CANFLY or kind == RM.TYPE.BATTLE_FRONTIER
          if allowed then
            dest = RM.flyWarpDestination(save, sec, 0)
            if not dest then
              local row = RM.flyHealLocation({ session = save }, sec, 0)
              local heal = type(row) == "table" and (row.healLocation or row.id) or row
              if type(heal) == "string" then heal = C.heal_locations.byName[heal] end
              if integer(heal, 1) then dest = g3("heal_locations").get(heal) end
            end
          end
        end
        if allowed and dest and dest.map == raw and integer(dest.x, 0)
            and integer(dest.y, 0) then
          return F.flyTo(sec, mon, { dest = copy(dest) })
        end
      end
    end
    return nil, "destination unavailable"
  end

  local function wildArgs(game, species, level, onDone)
    if not identifier(species) then return nil, "invalid species id" end
    if not integer(level, 1, 100) then return nil, "level must be a whole number 1..100" end
    if onDone ~= nil and type(onDone) ~= "function" then return nil, "invalid callback" end
    local pokemon = game.data and game.data.pokemon
    species = Ids.native(species, "species", generation, function(id)
      return pokemon and pokemon[id] ~= nil
    end)
    if generation == 3 then
      local id = req("src.mods.Gen3Compat").speciesId(species)
      local P = g3("pokemon")
      if not (id and P._names and P._names[id]) then return nil, "unknown species: " .. species end
    elseif not (game.data and game.data.pokemon and game.data.pokemon[species]) then
      return nil, "unknown species: " .. species
    end
    for _, mon in ipairs(partyOf(game)) do
      if (mon.hp or 0) > 0 and not mon.isEgg then return true, nil, species end
    end
    return nil, "no healthy party"
  end

  local function wild(game, api, species, level, onDone)
    local ok, err, nativeSpecies = wildArgs(game, species, level, onDone)
    if not ok then return nil, err end
    species = nativeSpecies
    if onDone then
      local callback, save, completed = onDone, saveOf(game), false
      onDone = function(...)
        if completed then return end
        completed = true
        if gameProvider() ~= game or saveOf(game) ~= save then return end
        local called, why = pcall(callback, ...)
        if not called then
          req("src.mods.Runtime").reportError(modId,
            "world battle callback failed: " .. tostring(why))
        end
      end
    end
    if generation == 3 then
      if not onDone then return api:startWildBattle(species, level) end
      ok, err = g3("battle_bridge").startWild(nil, game,
        { species = req("src.mods.Gen3Compat").speciesId(species), level = level },
        { done = onDone })
      if not ok then return nil, err or "battle failed" end
      return true
    end
    local ow = api:overworld()
    if generation == 1 then
      if not onDone then return api:startWildBattle(species, level) end
      local battle = req("src.battle.BattleState").newWild(game, species, level)
      battle.onFinish = function(result, ...)
        ow:afterBattle(result, battle)
        onDone(result, ...)
      end
      ow:pushBattle(battle)
      return true
    end
    if not game.stack then return nil, "no battle stack" end
    local mon = req("src.battle.gen2.Mon").new(game.data, species, level, { wild = true })
    if not mon then return nil, "unknown species: " .. species end
    local save = saveOf(game)
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen = save.pokedex.seen or {}
    save.pokedex.seen[species] = true
    if ow:startBattle({ wild = mon }, onDone) == false then return nil, "battle failed" end
    return true
  end

  local function queue(game, api, rows, extra)
    if not queueFn then
      local cancelFn
      queueFn, cancelFn = req("src.mods.UnifiedScripts").new({
        req = req, generation = generation, version = version, modId = modId,
        gameProvider = gameProvider, resolve = resolve, ready = ready,
        saveOf = saveOf, mapDef = mapDef, warpArgs = warpArgs,
        wildArgs = wildArgs, wild = wild, flagId = flagId, flag = flag,
      })
      SCRIPT_CANCEL[facade] = cancelFn
    end
    return queueFn(game, api, rows, extra)
  end

  local function dispatch(name, ...)
    local supported, reason = UnifiedWorld.supports(name, generation, version)
    if not supported then return nil, reason end
    local game, api, err = resolve()
    if not game then return nil, err end
    if MUTATES[name] then
      local ok
      ok, err = ready(game, api)
      if not ok then return nil, err end
    end
    local a, b, c, d, e = ...
    if name == "party" then
      if not saveOf(game) then return nil, "no save" end
      local records, out = req("src.mods.UnifiedRecords"), {}
      for i, mon in ipairs(partyOf(game)) do
        out[i] = records.mon(mon, generation, game.data, version)
      end
      return out
    elseif name == "activeBlockAt" then return blockAt(game, api, a, b, c)
    elseif name == "setFlag" then return flag(game, api, a, b, true)
    elseif name == "getFlag" then return flag(game, api, a)
    elseif name == "canFly" then
      local ok = ready(game, api)
      return ok ~= nil and not not flyUser(game, api)
    elseif name == "flyTo" then return fly(game, api, a)
    elseif name == "startWildBattle" then return wild(game, api, a, b, c)
    elseif name == "queueScript" then return queue(game, api, a, b)
    elseif name == "warpTo" then return warp(game, api, a, b, c, d, e)
    elseif name == "replaceBlock" then
      if not integer(c, 0, generation == 3 and 1023 or 255) then return nil, "invalid block id" end
      local current = api:current()
      if not current then return nil, "no overworld" end
      local id
      id, err = blockAt(game, api, current.mapId, a, b)
      if id == nil then return nil, err end
      if generation == 3 then
        local Field = g3("field")
        local ok
        ok, err = g3("mod_layout").checkMetatile(Field.currentPair(), c)
        if not ok then return nil, err end
        Field.setMetatile(a, b, c)
        return true
      end
      local ow = api:overworld()
      if not (ow.map.tileset and ow.map.tileset.blocks and ow.map.tileset.blocks[c + 1]) then
        return nil, "unknown block id"
      end
    elseif name == "reorderParty" then
      if not integer(a, 1) or not integer(b, 1)
          or not partyOf(game)[a] or not partyOf(game)[b] then return nil, "invalid party slot" end
    elseif name == "toggleObject" then
      if not identifier(a) or not objectRef(b) or type(c) ~= "boolean" then return nil, "invalid object toggle" end
      if not mapDef(game, a) then return nil, "unknown map: " .. a end
    elseif name == "spawnNpc" then
      if not identifier(a) or type(b) ~= "table" then return nil, "invalid NPC definition" end
      if not mapDef(game, a) then return nil, "unknown map: " .. a end
      if not integer(b.x, 0) or not integer(b.y, 0) then return nil, "invalid NPC coordinates" end
      return api:spawnNpc(a, copy(b))
    elseif name == "removeNpc" then
      if not objectRef(a) then return nil, "invalid NPC id" end
      if generation == 3 then
        if not identifier(a) then return nil, "invalid NPC id" end
        return api:removeRuntimeNpc(a)
      end
    elseif name == "invalidateMap" then
      if not identifier(a) or not mapDef(game, a) then return nil, "unknown map" end
    elseif name == "useFieldAction" then
      if not identifier(a) or (b ~= nil and type(b) ~= "table") then return nil, "invalid field action" end
      for key, value in pairs(b or {}) do
        if key == "rod" then
          if not identifier(value) then return nil, "invalid fishing rod" end
        elseif key == "sourceSlot" or key == "targetSlot" then
          if not integer(value, 1, #partyOf(game)) then return nil, "invalid party slot" end
        else return nil, "unknown field action option" end
      end
    elseif name == "effectiveEncounters" then
      if not identifier(a) then return nil, "invalid map id" end
      if b ~= "grass" and b ~= "water" and b ~= "indoor" then return nil, "invalid terrain" end
      if c ~= nil and type(c) ~= "table" then return nil, "invalid encounter options" end
      for key, value in pairs(c or {}) do
        if key ~= "daytime" or (value ~= "MORN" and value ~= "DAY" and value ~= "NITE" and value ~= "DARK") then
          return nil, "invalid encounter option"
        end
        if generation ~= 2 then return nil, "unsupported encounter daytime" end
      end
      local result
      result, err = api:effectiveEncounters(a, b == "indoor" and "grass" or b, c)
      if not result then return nil, err end
      result = Ids.record(result, generation, false)
      if type(result.dist) == "table" then
        local dist = {}
        for species, weight in pairs(result.dist) do
          local id = Ids.canonical(species, "species", generation)
          dist[id] = (dist[id] or 0) + weight
        end
        result.dist = dist
      end
      return result
    elseif name == "npc" then
      if not identifier(a) or not objectRef(b) then return nil, "invalid NPC reference" end
      local native
      native, err = api:npc(a, b)
      if not native then return nil, err end
      local handle = { id = native.id or (native.npc and native.npc.id) }
      local ref = handle.id or b
      local methods = { "scriptMove", "marchInPlace", "face", "position",
        "stepNow", "canStep", "placeAt", "isMoving", "setPassable" }
      if type(native.setAppearance) == "function" then
        methods[#methods + 1] = "setAppearance"
      end
      for _, method in ipairs(methods) do
        local operation = method
        handle[operation] = function(_, ...)
          local ok, result, detail = pcall(function(...)
            local liveGame, liveApi = resolve()
            if not liveGame then return nil, "no game" end
            local live, why = liveApi:npc(a, ref)
            if not live then return nil, why end
            local x, y, z = ...
            if operation == "scriptMove" or operation == "face" or operation == "stepNow" or operation == "canStep" then
              if not DIRS[x] then return nil, "invalid direction" end
            end
            if operation == "scriptMove" and ((y ~= nil and not integer(y, 1, 1024))
                or (z ~= nil and type(z) ~= "function")) then return nil, "invalid movement" end
            if operation == "marchInPlace" and x ~= nil and type(x) ~= "function" then return nil, "invalid callback" end
            if operation == "placeAt" and (not integer(x, 0) or not integer(y, 0)
                or (z ~= nil and not DIRS[z])) then return nil, "invalid coordinates" end
            if operation == "setPassable" and type(x) ~= "boolean" then return nil, "invalid passability" end
            if operation == "setAppearance" and not identifier(x) then return nil, "invalid sprite id" end
            if type(live[operation]) ~= "function" then return nil, "unsupported NPC operation" end
            if operation ~= "position" and operation ~= "canStep" and operation ~= "isMoving" then
              local free, whyBusy = ready(liveGame, liveApi)
              if not free then return nil, whyBusy end
            end
            return live[operation](live, ...)
          end, ...)
          if not ok then return nil, "world operation failed: " .. tostring(result) end
          if result == nil and detail == nil then return nil, "NPC operation failed" end
          return result, detail
        end
      end
      return handle
    elseif name == "canReorderParty" then
      local ok = ready(game, api)
      return ok ~= nil and #partyOf(game) > 1
    end
    local result, detail = api[name](api, ...)
    if name == "overworld" then
      if not result then return nil, "no overworld" end
      return result
    end
    if result == nil or (MUTATES[name] and result == false) then
      return nil, detail or "world operation failed"
    end
    if detail and name == "availableFieldActions" then return nil, detail end
    if name == "current" or name == "mapOverview" then
      result = copy(result)
      result.block = metadata()
    elseif type(result) == "table" then result = copy(result) end
    return result, detail
  end

  for _, name in ipairs(UnifiedWorld.METHODS) do
    local method = name
    facade[method] = function(_, ...)
      local ok, result, detail = pcall(dispatch, method, ...)
      if not ok then return nil, "world operation failed: " .. tostring(result) end
      return result, detail
    end
  end
  return facade
end

return UnifiedWorld
