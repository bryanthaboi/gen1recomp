local CacheFs = require("src.import.CacheFs")
local CartStore = require("src.carts.CartStore")
local Fingerprint = require("src.link.Fingerprint")
local GameVersion = require("src.core.GameVersion")
local Handshake = require("src.link.Handshake")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")
local Version = require("src.core.Version")

local ArenaData = {}

local rulesetMemo = {}
local speciesMemo = {}

local FIELDS = {
  { key = "engine", text = "engine differs" },
  { key = "engineVersion", text = "engine version differs" },
  { key = "apiVersion", text = "mod api differs" },
  { key = "kind", text = "arena kind differs" },
  { key = "rulesetId", text = "ruleset differs" },
  { key = "fingerprint", text = "data differs" },
}

local CART_FIELDS = {
  { key = "id", text = "cart differs" },
  { key = "version", text = "cart version differs" },
  { key = "hash", text = "cart hash differs" },
}

function ArenaData.cacheKey(version, kind, cartHash)
  return tostring(version) .. "|" .. tostring(kind) .. "|"
    .. (cartHash or "-") .. "|" .. tostring(Version.engine)
end

local function copyRule(rule)
  rule = type(rule) == "table" and rule or {}
  local size = tonumber(rule.partySize) or 3
  size = math.max(1, math.min(6, math.floor(size)))
  return {
    partySize = size,
    minLevel = tonumber(rule.minLevel) or nil,
    maxLevel = tonumber(rule.maxLevel) or nil,
    forceLevel = tonumber(rule.forceLevel) or nil,
  }
end

local function copyProfile(entry, rule)
  local out = {
    engine = entry.engine,
    version = entry.version,
    engineVersion = entry.engineVersion,
    apiVersion = entry.apiVersion,
    fingerprint = entry.fingerprint,
    rulesetId = entry.rulesetId,
    kind = entry.kind,
    rule = copyRule(rule),
  }
  if type(entry.cart) == "table" then
    out.cart = { id = entry.cart.id, version = entry.cart.version,
                 hash = entry.cart.hash }
  end
  return out
end

function ArenaData.equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for _, field in ipairs(FIELDS) do
    if a[field.key] ~= b[field.key] then return false end
  end
  local ca, cb = a.cart, b.cart
  if (ca == nil) ~= (cb == nil) then return false end
  if ca then
    for _, field in ipairs(CART_FIELDS) do
      if ca[field.key] ~= cb[field.key] then return false end
    end
  end
  return true
end

function ArenaData.describeMismatch(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return "no profile" end
  for _, field in ipairs(FIELDS) do
    if a[field.key] ~= b[field.key] then return field.text end
  end
  local ca, cb = a.cart, b.cart
  if (ca == nil) ~= (cb == nil) then return "cart differs" end
  if ca then
    for _, field in ipairs(CART_FIELDS) do
      if ca[field.key] ~= cb[field.key] then return field.text end
    end
  end
  return nil
end

local function cachedProfiles()
  local options = SaveData.loadOptions()
  local bucket = options.arenaProfiles
  return type(bucket) == "table" and bucket or {}, options
end

local function storeProfile(key, entry)
  local bucket = cachedProfiles()
  bucket[key] = entry
  pcall(SaveData.saveOptions, { arenaProfiles = bucket })
end

function ArenaData.forget(version)
  local bucket = cachedProfiles()
  local prefix = version and (tostring(version) .. "|") or nil
  for key in pairs(bucket) do
    if not prefix or key:sub(1, #prefix) == prefix then bucket[key] = nil end
  end
  pcall(SaveData.saveOptions, { arenaProfiles = bucket })
  if version then rulesetMemo[version] = nil else rulesetMemo = {} end
  if version then speciesMemo[version] = nil else speciesMemo = {} end
end

function ArenaData.speciesIds(version)
  if not GameVersion.VERSIONS[version] then return nil end
  local hit = speciesMemo[version]
  if hit then return hit end
  local Trade = require("src.online.Trade")
  if Trade.mounted() or Trade.gameIsLive() then return nil end
  local prevVersion, prevPrefix = GameVersion.get(), CacheFs.prefix
  local ok, rows = pcall(function()
    GameVersion.set(version)
    CacheFs.prefix = GameVersion.cachePrefix(version)
    CacheFs.mountVersion(version)
    return CacheFs.loadActive("data/generated/pokemon.lua")
  end)
  pcall(CacheFs.unmountVersion, version)
  GameVersion.set(prevVersion)
  CacheFs.prefix = prevPrefix
  if not ok or type(rows) ~= "table" then return nil end
  local out = {}
  for id in pairs(rows) do out[id] = true end
  if next(out) == nil then return nil end
  speciesMemo[version] = out
  return out
end

local function gen2Dataset()
  local data = {}
  local function load(name)
    return CacheFs.loadActive("data/generated/" .. name .. ".lua")
  end
  data.pokemon = load("pokemon") or {}
  data.items = load("items") or {}
  data.moves = load("moves") or {}
  data.type_chart = load("type_chart") or {}
  data.gen2Constants = load("constants")
  data.text = load("rom_text") or {}
  data.font = load("font")
  local chart = data.type_chart
  chart.matchups = chart.matchups or {}
  for _, row in ipairs(chart.foresightMatchups or {}) do
    chart.matchups[#chart.matchups + 1] = row
  end
  local ItemEffects = require("src.core.gen2.ItemEffects")
  data.gen2HeldItems = ItemEffects.heldItemsFrom(data.items)
  return data, ItemEffects.heldSnapshot(data.gen2HeldItems)
end

local function loadDataset(version, generation)
  if generation == 2 then
    local data, held = gen2Dataset()
    return data, function()
      require("src.core.gen2.ItemEffects").applyHeldItems(data, held)
    end
  end
  local Data = require("src.core.Data")
  Data:load()
  return Data, nil
end

local function busy()
  return require("src.online.Trade").gameIsLive()
end

local function compute(version, kind, cartId, cart, cartHash)
  local generation = GameVersion.generation(version)
  local prevVersion = GameVersion.get()
  local prevPrefix = CacheFs.prefix
  local saved = { events = Runtime.events, hooks = Runtime.hooks,
                  errors = Runtime.errors, safeMode = Runtime.safeMode }

  local function restore()
    pcall(function() require("src.core.Data"):unloadGenerated() end)
    pcall(CacheFs.unmountVersion, version)
    if Loader.endSession then pcall(Loader.endSession) end
    if Runtime.reset then pcall(Runtime.reset) end
    Runtime.events, Runtime.hooks = saved.events, saved.hooks
    Runtime.errors, Runtime.safeMode = saved.errors, saved.safeMode
    Runtime.currentMod = nil
    GameVersion.set(prevVersion)
    CacheFs.prefix = prevPrefix
  end

  local ok, result = pcall(function()
    GameVersion.set(version)
    CacheFs.prefix = GameVersion.cachePrefix(version)
    CacheFs.mountVersion(version)
    if not CacheFs.readActive("data/generated/pokemon.lua") then
      return { error = ("%s is not imported"):format(version) }
    end
    local data, after = loadDataset(version, generation)
    local loader = Loader.new({ generation = generation, cart = cart })
    local opts = kind == "cart"
      and { mode = "cartOnly", cartId = cartId }
      or { mode = "disableAll" }
    local loaded, reason = loader:load(data, opts)
    if loaded == false and reason then return { error = reason } end
    if after then after() end
    local mods = Handshake.mods({ mods = loader })
    local rulesetId = "gen2"
    if generation ~= 2 then
      rulesetId = Handshake.ruleset({ data = data })
      local ids = {}
      for id in pairs(data.rulesets or {}) do ids[#ids + 1] = id end
      table.sort(ids)
      rulesetMemo[version] = ids
    else
      rulesetMemo[version] = { "gen2" }
    end
    return {
      engine = generation,
      version = version,
      engineVersion = Version.engine,
      apiVersion = Handshake.apiVersion or Version.modApi,
      fingerprint = Fingerprint.compute(data, mods, generation),
      rulesetId = rulesetId,
      kind = kind,
      cart = cart and { id = cartId, version = cart.version, hash = cartHash }
        or nil,
    }
  end)

  restore()
  if not ok then return nil, tostring(result) end
  if type(result) ~= "table" then return nil, "could not read that game" end
  if result.error then return nil, result.error end
  return result
end

function ArenaData.profile(version, kind, cartId, rule)
  kind = kind or "vanilla"
  if not GameVersion.VERSIONS[version] then return nil, "unknown game" end
  if kind ~= "vanilla" and kind ~= "cart" then return nil, "unknown arena kind" end

  local cart, cartHash
  if kind == "cart" then
    local got, hash = CartStore.get(cartId)
    if not got then return nil, tostring(hash or "this cart is not installed") end
    cart, cartHash = got, hash
    if cart.base ~= version then return nil, "that cart is for another game" end
    if cart.seal ~= "sealed" then return nil, "that cart is not sealed" end
  end

  local key = ArenaData.cacheKey(version, kind, cartHash)
  local bucket = cachedProfiles()
  local hit = bucket[key]
  if type(hit) == "table" and hit.fingerprint then
    return copyProfile(hit, rule)
  end

  if busy() then return nil, "close the game first" end
  local entry, reason = compute(version, kind, cartId, cart, cartHash)
  if not entry then return nil, reason end
  storeProfile(key, entry)
  return copyProfile(entry, rule)
end

function ArenaData.rulesetIds(version)
  if rulesetMemo[version] then return rulesetMemo[version] end
  if GameVersion.generation(version) == 2 then
    rulesetMemo[version] = { "gen2" }
    return rulesetMemo[version]
  end
  local _, reason = ArenaData.profile(version, "vanilla", nil, nil)
  if rulesetMemo[version] then return rulesetMemo[version] end
  return { Handshake.DEFAULT_RULESET }, reason
end

return ArenaData
