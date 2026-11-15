local CacheBlob = require("src.import.CacheBlob")
local M = {}

local function readable(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function push(list, seen, path)
  if path and path ~= "" and not seen[path] then
    seen[path] = true
    list[#list + 1] = path
  end
end

local IS_GBA = { firered = true, leafgreen = true, ruby = true, sapphire = true, emerald = true }
local LABEL = { firered = "FireRed", leafgreen = "LeafGreen", ruby = "Ruby", sapphire = "Sapphire", emerald = "Emerald" }

M.pinned = nil

function M.use(version)
  if not IS_GBA[version] then
    error("tests.game3_cache: not a GBA version id: " .. tostring(version), 2)
  end
  M.pinned = version
  return M
end

function M.version()
  return M.pinned or "firered"
end

local function takeVersion(marker, opts, extra)
  if IS_GBA[marker] then
    M.use(marker)
    return opts, extra
  end
  return marker, opts
end

local function saveRoots()
  local home = os.getenv("HOME")
  if not home then return {} end
  return {
    home .. "/Library/Application Support/LOVE",
    home .. "/.local/share/love",
  }
end

local function identityNames()
  local names = {}
  local identity = os.getenv("POKEPORT_IDENTITY")
  if identity and identity ~= "" then names[#names + 1] = identity end
  if M.pinned then names[#names + 1] = "g1r-" .. M.pinned end
  return names
end

local function candidates()
  local list, seen = {}, {}
  local version = M.version()
  local suffix = "/" .. version .. "/data/generated/gba"
  for _, name in ipairs(identityNames()) do
    for _, saveRoot in ipairs(saveRoots()) do
      push(list, seen, saveRoot .. "/" .. name .. suffix)
    end
  end
  if version == "firered" then
    push(list, seen, os.getenv("POKEPORT_GBA_CACHE"))
    push(list, seen, "data/generated/gba")
  end
  return list
end

local function metaVersions(root)
  local f = io.open(root .. "/meta.json", "rb")
  if not f then return nil end
  local src = CacheBlob.decode(root .. "/meta.json", f:read("*a")) or ""
  f:close()
  return tonumber(src:match('"cache_version"%s*:%s*(%d+)')) or 0,
    tonumber(src:match('"native_version"%s*:%s*(%d+)')) or 0
end

local function gameVersions()
  return require("src.import.gba.versions").forGame(M.version())
end

local function isCurrent(root, needNative)
  local Versions = gameVersions()
  local cacheV, nativeV = metaVersions(root)
  if not cacheV then return false, "no meta.json" end
  if cacheV ~= Versions.CACHE_VERSION then
    return false, ("cache v%d, importer is v%d"):format(cacheV, Versions.CACHE_VERSION)
  end
  if needNative and nativeV ~= Versions.NATIVE_VERSION then
    return false, ("native v%d, importer is v%d"):format(nativeV, Versions.NATIVE_VERSION)
  end
  return true
end

M._roots = {}
M.reason = nil

function M.root(marker, opts)
  marker, opts = takeVersion(marker, opts)
  marker = marker or "meta.json"
  local needNative = type(opts) == "table" and opts.native == true
  local label = LABEL[M.version()]
  local memoKey = M.version() .. "|" .. marker .. (needNative and "|native" or "")
  local memo = M._roots[memoKey]
  if memo ~= nil then
    if memo == false then return nil end
    return memo
  end
  local stale = 0
  local function pick(roots)
    for _, root in ipairs(roots) do
      if readable(root .. "/" .. marker) then
        if isCurrent(root, needNative) then return root end
        stale = stale + 1
      end
    end
    return nil
  end
  local root = pick(candidates())
  if root then
    M._roots[memoKey] = root
    M.reason = nil
    return root
  end
  local Versions = gameVersions()
  if stale > 0 then
    M.reason = ("%d imported %s cache(s) found, none at cache v%d%s"):format(
      stale, label, Versions.CACHE_VERSION,
      needNative and (" / native v" .. tostring(Versions.NATIVE_VERSION)) or "")
  else
    M.reason = "no imported " .. label .. " cache found"
  end
  M._roots[memoKey] = false
  return nil
end

function M.gameDir(marker, opts)
  local root = M.root(marker, opts)
  return root and (root:gsub("/data/generated/gba$", "")) or nil
end

function M.cache(root)
  local function path(rel)
    if root then return root .. "/" .. (rel:gsub("^data/generated/gba/", "")) end
    return rel
  end
  return {
    read = function(_, rel)
      rel = path(rel)
      local f = io.open(rel, "rb")
      if not f then return nil end
      local data = CacheBlob.decode(rel, f:read("*a"))
      f:close()
      if type(data) == "string" and #data > 0 then return data end
      return nil
    end,
    exists = function(_, rel)
      return readable(path(rel))
    end,
  }
end

function M.rootOrSkip(label, marker, opts)
  local root = M.root(marker, opts)
  if not root then
    print("[skip] " .. tostring(label) .. ": " .. tostring(M.reason))
    os.exit(0)
  end
  return root
end

function M.mount(marker, opts)
  marker, opts = takeVersion(marker, opts)
  local root = M.root(marker, opts)
  if not root then return nil end
  if M.pinned then
    local GameVersion = require("src.core.GameVersion")
    if GameVersion.current ~= M.pinned then GameVersion.set(M.pinned) end
    require("src.import.gba.versions").selectCache(M.pinned, M.cache(root))
    require("src.core.game3.profile").reset()
  end
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = root
  Dataset.mountExtractRoots()
  return root
end

function M.mountOrSkip(label, marker, opts)
  local root = M.mount(marker, opts)
  if not root then
    print("[skip] " .. tostring(label) .. ": " .. tostring(M.reason))
    os.exit(0)
  end
  print("[info] " .. LABEL[M.version()] .. " cache at " .. root)
  return root
end

local function datasetRoots()
  local roots = { "." }
  for _, name in ipairs(identityNames()) do
    for _, saveRoot in ipairs(saveRoots()) do
      roots[#roots + 1] = saveRoot .. "/" .. name .. "/" .. M.version()
    end
  end
  return roots
end

function M.requireData(label, marker)
  marker = takeVersion(marker)
  marker = marker or "meta.json"
  if M.mount(marker) then return end
  for _, root in ipairs(datasetRoots()) do
    if readable(root .. "/data/generated/gba/" .. marker) then return end
  end
  print("[skip] " .. tostring(label) .. ": " .. tostring(M.reason or ("no imported " .. LABEL[M.version()] .. " cache found")))
  os.exit(0)
end

function M.stubSpeciesNames()
  if M.mount() then return false end
  local Pokemon = require("src.core.game3.pokemon")
  Pokemon.name = function(species) return "SPECIES " .. tostring(species) end
  return true
end

function M.bundle(marker, opts)
  local root = M.mount(marker, opts)
  if not root then return nil end
  local ExtractScripts = require("src.import.gba.extract_scripts")
  local Space = require("src.core.game3.scripting.space")
  local bundle = ExtractScripts.loadBundle(M.cache(), root, { allowIncomplete = true })
  Space.bundle = bundle
  return bundle, root
end

return M
