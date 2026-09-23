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

local SUFFIX = "/firered/data/generated/gba"

local function candidates()
  local list, seen = {}, {}
  local home = os.getenv("HOME")
  local saveRoots = home and {
    home .. "/Library/Application Support/LOVE",
    home .. "/.local/share/love",
  } or {}

  local identity = os.getenv("POKEPORT_IDENTITY")
  if identity and identity ~= "" then
    for _, saveRoot in ipairs(saveRoots) do
      push(list, seen, saveRoot .. "/" .. identity .. SUFFIX)
    end
  end
  push(list, seen, os.getenv("POKEPORT_GBA_CACHE"))
  push(list, seen, "data/generated/gba")
  return list
end

local function metaVersions(root)
  local f = io.open(root .. "/meta.json", "rb")
  if not f then return nil end
  local src = f:read("*a") or ""
  f:close()
  return tonumber(src:match('"cache_version"%s*:%s*(%d+)')) or 0,
    tonumber(src:match('"native_version"%s*:%s*(%d+)')) or 0
end

local function isCurrent(root, needNative)
  local Versions = require("src.import.gba.versions")
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
  marker = marker or "meta.json"
  local needNative = type(opts) == "table" and opts.native == true
  local memoKey = marker .. (needNative and "|native" or "")
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
  local Versions = require("src.import.gba.versions")
  if stale > 0 then
    M.reason = ("%d imported FireRed cache(s) found, none at cache v%d%s"):format(
      stale, Versions.CACHE_VERSION,
      needNative and (" / native v" .. tostring(Versions.NATIVE_VERSION)) or "")
  else
    M.reason = "no imported FireRed cache found"
  end
  M._roots[memoKey] = false
  return nil
end

function M.cache()
  return {
    read = function(_, rel)
      local f = io.open(rel, "rb")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      if type(data) == "string" and #data > 0 then return data end
      return nil
    end,
    exists = function(_, rel)
      return readable(rel)
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
  local root = M.root(marker, opts)
  if not root then return nil end
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
  print("[info] FireRed cache at " .. root)
  return root
end

local function datasetRoots()
  local roots = { "." }
  local home = os.getenv("HOME")
  local identity = os.getenv("POKEPORT_IDENTITY") or ""
  if home and identity ~= "" then
    roots[#roots + 1] = home .. "/Library/Application Support/LOVE/" .. identity .. "/firered"
    roots[#roots + 1] = home .. "/.local/share/love/" .. identity .. "/firered"
  end
  return roots
end

function M.requireData(label, marker)
  marker = marker or "meta.json"
  if M.mount(marker) then return end
  for _, root in ipairs(datasetRoots()) do
    if readable(root .. "/data/generated/gba/" .. marker) then return end
  end
  print("[skip] " .. tostring(label) .. ": " .. tostring(M.reason or "no imported FireRed cache found"))
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
