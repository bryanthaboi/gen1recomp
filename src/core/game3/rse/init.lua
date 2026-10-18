local function lazyReq(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  return require(name)
end

local Profile = require("src.core.game3.profile")

local Rse = {}

Rse._systems = {}
Rse._logged = {}
Rse._data = {}

local function session()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end
Rse.session = session

function Rse.profile(sess)
  local ok, row = pcall(Profile.forSession, sess or session())
  if ok and type(row) == "table" then return row end
  return nil
end

function Rse.isRse(sess)
  local row = Rse.profile(sess)
  return row ~= nil and row.family == "rse"
end

local function loadCache(rel)
  local src = lazyReq("src.core.game3.dataset").cache():read(rel)
  local chunk = src and load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok and type(t) == "table" then return t end
  return nil
end

function Rse.data(sess, system)
  local row = Rse.profile(sess)
  local block = row and type(row.rse) == "table" and row.rse[system] or nil
  if type(block) ~= "table" then return block end
  local key = tostring(row.id) .. ":" .. tostring(system)
  local hit = Rse._data[key]
  if hit then return hit end
  local out = {}
  for k, v in pairs(block) do out[k] = v end
  if type(block.cache) == "string" then
    local t = loadCache(block.cache)
    if t then for k, v in pairs(t) do if out[k] == nil then out[k] = v end end end
  end
  Rse._data[key] = out
  return out
end

function Rse.register(name, impl)
  Rse._systems[name] = impl
end

function Rse.missing(name, what, logger)
  local key = tostring(name) .. ":" .. tostring(what)
  if Rse._logged[key] then return end
  Rse._logged[key] = true
  local msg = string.format("[game3] rse system %s not ported (%s)", tostring(name), tostring(what))
  if logger then logger(msg) else print(msg) end
end

Rse.MODULES = {
  berryTrees = "src.core.game3.rse.berry_trees",
  rotatingTilePuzzle = "src.core.game3.rotating_tile_puzzle",
  pokenav = "src.core.game3.rse.match_call",
  rematch = "src.core.game3.rse.rematch",
  pokeblock = "src.core.game3.rse.pokeblock",
  berryBlender = "src.core.game3.rse.berry_blender",
  contest = "src.core.game3.scripting.natives_contest",
  contestPainting = "src.core.game3.scripting.natives_contest",
  secretBase = "src.core.game3.rse.secret_base",
  pyramid = "src.core.game3.rse.frontier.pyramid",
  trainerHill = "src.core.game3.rse.trainer_hill",
  eventIslands = "src.core.game3.rse.event_islands",
  tv = "src.core.game3.rse.tv",
  bag = "src.ui.game3.rse.bag_menu",
  recordedBattle = "src.core.game3.rse.recorded_battle",
}

function Rse.system(name, what, logger)
  local impl = Rse._systems[name]
  if impl then return impl end
  local path = Rse.MODULES[name]
  if path then
    local ok, mod = pcall(require, path)
    if ok and type(mod) == "table" then
      if Rse._systems[name] then return Rse._systems[name] end
      Rse._systems[name] = mod
      return mod
    end
  end
  if what then Rse.missing(name, what, logger) end
  return nil
end

function Rse.call(name, fn, what, logger, ...)
  local impl = Rse.system(name, what or fn, logger)
  local f = impl and impl[fn]
  if type(f) ~= "function" then
    if impl then Rse.missing(name, what or fn, logger) end
    return nil, false
  end
  return f(...), true
end

function Rse.reset()
  Rse._logged = {}
  Rse._data = {}
end

local function flagsMod()
  return lazyReq("src.core.game3.scripting.flags")
end

local function tables(sess)
  local Constants = lazyReq("src.core.game3.constants")
  return flagsMod().forVersion(Constants.versionOf(sess or session()))
end

function Rse.store()
  local Space = package.loaded["src.core.game3.scripting.space"]
  return Space and Space.store or nil
end

function Rse.flagId(name, sess)
  return tables(sess).IDS[name]
end

function Rse.varId(name, sess)
  return tables(sess).VAR_IDS[name]
end

function Rse.flag(name, sess)
  local id = assert(Rse.flagId(name, sess), "unknown flag " .. tostring(name))
  return flagsMod().getFlag(Rse.store(), nil, id) == true
end

function Rse.setFlag(name, on, sess)
  local id = assert(Rse.flagId(name, sess), "unknown flag " .. tostring(name))
  flagsMod().setFlag(Rse.store(), nil, id, on ~= false)
end

function Rse.var(nameOrId, sess)
  local id = type(nameOrId) == "number" and nameOrId or assert(Rse.varId(nameOrId, sess), "unknown var " .. tostring(nameOrId))
  return tonumber(flagsMod().getVar(Rse.store(), nil, id)) or 0
end

function Rse.setVar(nameOrId, value, sess)
  local id = type(nameOrId) == "number" and nameOrId or assert(Rse.varId(nameOrId, sess), "unknown var " .. tostring(nameOrId))
  flagsMod().setVar(Rse.store(), nil, id, value)
end

function Rse.specialVar(ctx, id)
  local v = tonumber(flagsMod().getVar(nil, ctx, id)) or 0
  if v == 0 and ctx and type(ctx.getVar) == "function" then v = tonumber(ctx:getVar(id)) or 0 end
  return v
end

function Rse.setSpecialVar(ctx, id, value)
  flagsMod().setVar(Rse.store(), ctx, id, value)
  if ctx and type(ctx.setVar) == "function" then ctx:setVar(id, value) end
end

function Rse.mapGroupNum(mapId, sess)
  if type(mapId) ~= "string" then return nil end
  local row = Rse.profile(sess)
  local prefix = row and row.map and row.map.enginePrefix or ""
  local Constants = lazyReq("src.core.game3.constants")
  local C = Constants.of(Constants.versionOf(sess or session()))
  -- pokeemerald/include/constants/map_groups.h: normalize map aliases against pret names.
  local okCatalog, MapCatalog = pcall(lazyReq, "src.import.gba.map_catalog")
  local slot = okCatalog and MapCatalog.slotKeyFor and MapCatalog.slotKeyFor(mapId)
  if type(slot) == "string" then
    local group, num = slot:match("^(%d+)_(%d+)$")
    if group and num then return tonumber(group), tonumber(num) end
  end
  local name = "MAP_" .. mapId:sub(#prefix + 1)
  local e = C.map_groups.byName[name]
  if not e then
    local suffix = mapId:sub(#prefix + 1):upper():gsub("[^A-Z0-9]", "")
    for constName, candidate in pairs(C.map_groups.byName) do
      local constantSuffix = constName:gsub("^MAP_", ""):upper():gsub("[^A-Z0-9]", "")
      local pretName = tostring(candidate.name or ""):upper():gsub("[^A-Z0-9]", "")
      if suffix == constantSuffix or suffix == pretName then e = candidate break end
    end
  end
  if not e then return nil end
  return tonumber(e.group), tonumber(e.num)
end

function Rse.text(key)
  local RomText = lazyReq("src.core.game3.rom_text")
  return RomText.plain(key)
end

return Rse
