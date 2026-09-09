-- Worker-safe capability for source-backed asset preprocessing.
--
-- A background job never receives love.filesystem or a host path. The engine
-- builds this facade from the owning mod's validated manifest and the same
-- ImportAccess implementation used by the main-thread mod.imports/mod.cache
-- APIs. The worker can therefore read only declared imports and can write only
-- its own installation-scoped generated cache.

local ImportAccess = require("src.mods.ImportAccess")
local SafePath = require("src.mods.SafePath")

local JobAssetIO = {}

-- Build the small, data-only descriptor that crosses the LÖVE thread boundary.
-- The caller still runs it through Job.plain before serialising, so a future
-- manifest field cannot accidentally smuggle userdata/functions to the worker.
function JobAssetIO.descriptor(manifest, modPath)
  if type(manifest) ~= "table" or type(manifest.id) ~= "string"
      or manifest.id == "" then
    return nil, "asset-I/O job has no owning mod manifest"
  end
  local path = modPath or manifest.path
  local okPath, safe = pcall(SafePath.require, path, "asset-I/O mod root")
  if not okPath then return nil, tostring(safe) end
  return {
    id = manifest.id,
    path = safe,
    required_imports = manifest.required_imports or {},
    optional_imports = manifest.optional_imports or {},
  }
end

local function facade(imports, cache)
  -- Deliberately copy only the narrow methods promised to worker scripts.
  -- ImportAccess also has cache:delete(), but destructive cache operations are
  -- not needed for the preprocessing contract and are therefore not exposed.
  return {
    imports = {
      info = function(_, id) return imports:info(id) end,
      read = function(_, id, offset, length)
        return imports:read(id, offset, length)
      end,
    },
    cache = {
      info = function(_, path) return cache:info(path) end,
      read = function(_, path) return cache:read(path) end,
      write = function(_, path, bytes) return cache:write(path, bytes) end,
      exists = function(_, path) return cache:exists(path) end,
    },
  }
end

-- Reconstruct the worker-local capability. expectedModId is supplied by the
-- engine's thread bootstrap, not by the mod, and prevents a malformed/tampered
-- descriptor from selecting another mod's cache namespace.
function JobAssetIO.open(descriptor, fs, expectedModId)
  if type(descriptor) ~= "table" then
    return nil, "asset-I/O descriptor is missing"
  end
  if type(descriptor.id) ~= "string" or descriptor.id == ""
      or (expectedModId and descriptor.id ~= expectedModId) then
    return nil, "asset-I/O descriptor owner mismatch"
  end
  local okPath, safe = pcall(SafePath.require, descriptor.path,
    "asset-I/O mod root")
  if not okPath then return nil, tostring(safe) end

  local manifest = {
    id = descriptor.id,
    path = safe,
    required_imports = type(descriptor.required_imports) == "table"
      and descriptor.required_imports or {},
    optional_imports = type(descriptor.optional_imports) == "table"
      and descriptor.optional_imports or {},
  }
  local imports, cache = ImportAccess.new(manifest, fs)
  return facade(imports, cache)
end

return JobAssetIO
