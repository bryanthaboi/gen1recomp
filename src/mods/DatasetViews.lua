-- Read-only, bounded views over version-scoped generated datasets.

local CacheContract = require("src.import.CacheContract")
local DatasetHydration = require("src.core.DatasetHydration")
local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")
local SaveSerializer = require("src.core.SaveSerializer")
local Builtins = require("src.mods.Builtins")
local Registry = require("src.mods.Registry")
local Schemas = require("src.mods.Schemas")

local DatasetViews = {}
DatasetViews.__index = DatasetViews

-- A generated module is ROM-sized data, never an arbitrary program. These
-- caps bound both one malicious file and the aggregate work one open performs.
local DECODE_LIMITS = {
  allowArray = true,
  allowComments = true,
  maxBytes = 8 * 1024 * 1024,
  maxDepth = 64,
  maxNodes = 500000,
  maxStringBytes = 2 * 1024 * 1024,
  maxTableEntries = 250000,
  rootName = "generated data",
}
local MAX_AGGREGATE_BYTES = 48 * 1024 * 1024

local GEN1_ROOTS = {
  constants = "constants", maps = "maps", tilesets = "tilesets",
  text = "text", text_pointers = "text_pointers",
  trainer_headers = "trainer_headers", font = "font", sprites = "sprites",
  pokemon = "pokemon", moves = "moves", items = "items",
  type_chart = "type_chart", trainers = "trainers",
  encounters = "encounters", field = "field",
  battle_anims = "battle_anims", audio = "audio",
  palettes = "palettes", icons = "icons",
}

local GEN2_ROOTS = {
  pokemon = "pokemon", moves = "moves", items = "items",
  type_chart = "type_chart", audio = "audio", font = "font",
  gen2Maps = "maps", gen2Tilesets = "tilesets", gen2Text = "text",
  gen2Trainers = "trainers", gen2Encounters = "encounters",
  gen2Sprites = "sprites", gen2Palettes = "palettes",
  gen2Icons = "icons", gen2BattleAnims = "battle_anims",
  gen2Constants = "constants", gen2Landmarks = "landmarks",
}

local function resolvePath(root, suffix)
  local node = root
  for key in suffix:gmatch("[^.]+") do
    if type(node) ~= "table" then return nil end
    node = node[key]
  end
  return node
end

local function assetRelative(path)
  if type(path) ~= "string" or path == "" then
    error("dataset asset path is required", 3)
  end
  if path:find("\\", 1, true) or path:sub(1, 1) == "/"
      or path:find("[%z\1-\31]") then
    error("dataset asset path must be a generated relative path", 3)
  end
  if path:sub(1, 17) ~= "assets/generated/" then
    error("dataset assets are limited to assets/generated/", 3)
  end
  for segment in path:gmatch("[^/]+") do
    if segment == "." or segment == ".." then
      error("dataset asset path may not traverse directories", 3)
    end
  end
  return path
end

local function copyData(value, state, depth)
  state = state or { seen = {}, nodes = 0 }
  state.nodes = state.nodes + 1
  if state.nodes > DECODE_LIMITS.maxNodes then return nil, false end
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "number" then return value end
  if kind == "string" then
    if #value > DECODE_LIMITS.maxStringBytes then return nil, false end
    return value
  end
  if kind ~= "table" or getmetatable(value) ~= nil then return nil, false end
  depth = (depth or 0) + 1
  if depth > DECODE_LIMITS.maxDepth or state.seen[value] then return nil, false end
  state.seen[value] = true
  local out, entries = {}, 0
  for key, child in pairs(value) do
    entries = entries + 1
    if entries > DECODE_LIMITS.maxTableEntries then return nil, false end
    local keyCopy, keyOk = copyData(key, state, depth)
    local childCopy, childOk = copyData(child, state, depth)
    if keyOk == false or childOk == false or keyCopy == nil then return nil, false end
    out[keyCopy] = childCopy
  end
  state.seen[value] = nil
  return out, true
end

local function isDataOnly(value, state, depth)
  state = state or { seen = {}, nodes = 0 }
  state.nodes = state.nodes + 1
  if state.nodes > DECODE_LIMITS.maxNodes then return false end
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "number" then return true end
  if kind == "string" then return #value <= DECODE_LIMITS.maxStringBytes end
  if kind ~= "table" or getmetatable(value) ~= nil then return false end
  depth = (depth or 0) + 1
  if depth > DECODE_LIMITS.maxDepth or state.seen[value] then return false end
  state.seen[value] = true
  local entries = 0
  for key, child in pairs(value) do
    entries = entries + 1
    if entries > DECODE_LIMITS.maxTableEntries
        or not isDataOnly(key, state, depth)
        or not isDataOnly(child, state, depth) then
      return false
    end
  end
  state.seen[value] = nil
  return true
end

function DatasetViews.new(fs, engineRequire, decoder)
  assert(fs and fs.read and fs.getInfo,
    "DatasetViews.new requires a readable filesystem")
  return setmetatable({ fs = fs, engineRequire = engineRequire or require,
    decoder = decoder or SaveSerializer.decode, datasets = {} }, DatasetViews)
end

function DatasetViews:_preflight(version, inspected)
  local paths, aggregate = {}, 0
  local modules = CacheContract.semanticModules(version)
  for _, name in ipairs(CacheContract.optionalSemanticModules(version)) do
    local path = inspected.prefix .. "data/generated/" .. name .. ".lua"
    if self.fs.getInfo(path, "file") then modules[#modules + 1] = name end
  end
  for _, name in ipairs(modules) do
    local path = inspected.prefix .. "data/generated/" .. name .. ".lua"
    local info = self.fs.getInfo(path, "file")
    local size = info and info.size
    if size and size > DECODE_LIMITS.maxBytes then return nil, name .. ": size limit" end
    aggregate = aggregate + (size or 0)
    if aggregate > MAX_AGGREGATE_BYTES then return nil, "aggregate size limit" end
    paths[name] = path
  end
  return { paths = paths, key = table.concat(modules, "\n") }
end

local function resetInternal(view)
  view.moduleCache, view.data, view.registries = {}, nil, nil
end

function DatasetViews:_reject(view, moduleName, source, detail)
  view.invalid = { module = moduleName, source = source, detail = detail }
  view.data, view.registries = nil, nil
  Logger.warn("dataset %s cache rejected: %s", view.version, tostring(detail))
  return nil
end

function DatasetViews:_ready(view)
  if view.invalid or view.unavailable then return false end
  local inspected, _, detail = CacheContract.inspect(view.version, self.fs, {
    allowSource = true, semantic = true,
  })
  if not inspected then
    view.unavailable = true
    if self.datasets[view.version] == view then self.datasets[view.version] = nil end
    Logger.warn("dataset %s unavailable: %s", view.version, detail)
    return false
  end
  local plan, invalid = self:_preflight(view.version, inspected)
  if not plan then
    self:_reject(view, nil, nil, invalid)
    return false
  end
  if view.prefix ~= inspected.prefix or view.plan.key ~= plan.key then
    view.prefix, view.plan = inspected.prefix, plan
    resetInternal(view)
  else
    view.plan = plan
  end
  for name, cached in pairs(view.moduleCache) do
    local source = self.fs.read(plan.paths[name])
    if type(source) ~= "string" then
      self:_reject(view, name, source, name .. ": unreadable generated module")
      return false
    end
    if source ~= cached.source then
      resetInternal(view)
      break
    end
  end
  return not view.invalid
end

function DatasetViews:_module(view, root)
  local moduleName = view.modules[root]
  if not moduleName then return nil end
  local cached = view.moduleCache[moduleName]
  if cached then return cached.value end
  local path = view.plan.paths[moduleName]
  if not path then return nil end
  local source = self.fs.read(path)
  if type(source) ~= "string" then
    return self:_reject(view, moduleName, source,
      moduleName .. ": unreadable generated module")
  end
  local aggregate = #source
  for _, loaded in pairs(view.moduleCache) do aggregate = aggregate + #loaded.source end
  if aggregate > MAX_AGGREGATE_BYTES then
    return self:_reject(view, moduleName, source, "aggregate size limit")
  end
  local value, err = self.decoder(source, DECODE_LIMITS)
  if type(value) ~= "table" then
    return self:_reject(view, moduleName, source,
      moduleName .. ": " .. tostring(err or "non-table root"))
  end
  view.moduleCache[moduleName] = { source = source, value = value }
  return value
end

function DatasetViews:_data(view)
  if view.data then return view.data end
  local data = {}
  setmetatable(data, {
    __index = function(target, root)
      local value = self:_module(view, root)
      if value ~= nil then rawset(target, root, value) end
      return value
    end,
  })
  DatasetHydration.apply(data, view.version, self.engineRequire)
  if view.invalid then error(view.invalid.detail, 0) end
  view.data = data
  return data
end

local function registryBase(data, target)
  return function() return resolvePath(data, target) end
end

function DatasetViews:_registries(view)
  if view.registries then return view.registries end
  local data = self:_data(view)
  local registries = {}
  for name, catalogSpec in pairs(Schemas.REGISTRIES) do
    local spec = Schemas.shapeFor(name, catalogSpec, view.generation)
    local registry = Registry.new(name, spec)
    local target = Schemas.targetFor(name, catalogSpec, view.generation)
    if target then registry.base = registryBase(data, target) end
    registries[name] = registry
  end
  Builtins.install(registries, data, view.generation, self.engineRequire)
  for _, registry in pairs(registries) do registry:freeze() end
  view.registries = registries
  return registries
end

function DatasetViews:_registry(view, name)
  local service = self
  local function registryForRead()
    if not service:_ready(view) then return nil end
    local ok, registries = pcall(service._registries, service, view)
    if not ok then
      if not view.invalid then service:_reject(view, nil, nil, registries) end
      return nil
    end
    if view.invalid then return nil end
    return registries[name]
  end
  local function validate(registry, id, value)
    if value == nil then return true end
    local ok, detail = Schemas.check(registry.spec, registry.name, id,
      value, "override")
    if ok then return true end
    local target = registry.spec.target
      or Schemas.targetFor(registry.name, registry.spec, view.generation)
    local root = target and target:match("^[^%.]+")
    local moduleName = root and view.modules[root]
    if root == "gen2HeldItems" then moduleName = "items" end
    local cached = moduleName and view.moduleCache[moduleName]
    service:_reject(view, moduleName, cached and cached.source,
      "invalid " .. registry.name .. " record: " .. detail)
    return false
  end
  local function rawAt(id)
    local registry = registryForRead()
    local value = registry and registry:get(id)
    if value == nil or not validate(registry, id, value)
        or not isDataOnly(value) then return nil end
    return value
  end
  local function valueAt(id)
    local value = rawAt(id)
    if value == nil then return nil end
    return (copyData(value))
  end
  return {
    get = function(_, id)
      if type(id) ~= "string" or id == "" then return nil end
      return valueAt(id)
    end,
    has = function(_, id)
      if type(id) ~= "string" or id == "" then return false end
      return rawAt(id) ~= nil
    end,
    each = function()
      local ids = {}
      local registry = registryForRead()
      if registry then
        for id, value in registry:each() do
          if not validate(registry, id, value) then
            ids = {}
            break
          end
          if type(id) == "string" and isDataOnly(value) then
            ids[#ids + 1] = id
          end
        end
      end
      table.sort(ids)
      local index = 0
      return function()
        index = index + 1
        local id = ids[index]
        if id == nil then return nil end
        return id, valueAt(id)
      end
    end,
  }
end

function DatasetViews:_assets(view)
  local service = self
  local assets = {}
  function assets:path(path)
    if not service:_ready(view) then return nil end
    return view.prefix .. assetRelative(path)
  end
  function assets:info(path)
    local full = self:path(path)
    if not full then return nil end
    local info = service.fs.getInfo and service.fs.getInfo(full, "file")
    if not info or (info.type and info.type ~= "file") then return nil end
    local out = { type = "file" }
    if info.size ~= nil then out.size = info.size end
    return out
  end
  return assets
end

function DatasetViews:open(version)
  if type(version) ~= "string" or not GameVersion.VERSIONS[version] then
    return nil, "unknown_version"
  end
  local inspected, reason = CacheContract.inspect(version, self.fs, {
    allowSource = true, semantic = true,
  })
  if not inspected then
    self.datasets[version] = nil
    return nil, reason
  end
  local plan, invalid = self:_preflight(version, inspected)
  if not plan then
    Logger.warn("dataset %s cache rejected: %s", version, invalid)
    return nil, "invalid_cache"
  end

  local internal = self.datasets[version]
  if internal and internal.invalid then
    local bad = internal.invalid
    local path = bad.module and plan.paths[bad.module]
    local source = path and self.fs.read(path)
    if source == bad.source then return nil, "invalid_cache" end
    internal = nil
    self.datasets[version] = nil
  end
  local changed = not internal or internal.prefix ~= inspected.prefix
    or internal.plan.key ~= plan.key
  if changed then
    if internal then internal.unavailable = true end
    internal = {
      version = version,
      generation = GameVersion.generation(version),
      prefix = inspected.prefix,
      plan = plan,
      modules = GameVersion.generation(version) == 2 and GEN2_ROOTS or GEN1_ROOTS,
      moduleCache = {},
    }
    self.datasets[version] = internal
  else
    internal.plan = plan
  end

  local view = { version = version, generation = internal.generation, content = {} }
  for name in pairs(Schemas.REGISTRIES) do
    view.content[name] = self:_registry(internal, name)
  end
  for alias, canonical in pairs(Schemas.ALIASES) do
    view.content[alias] = view.content[canonical]
  end
  view.assets = self:_assets(internal)
  return view
end

return DatasetViews
