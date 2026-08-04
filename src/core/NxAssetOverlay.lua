-- NX-only asset overlay: fused love-nx cannot reliably mount
-- blue|yellow/assets/generated onto the un-prefixed assets/generated, so
-- instead of teaching every call site about versioned caches, this module
-- wraps EVERY read-side love entry point that accepts a filesystem path
-- once at boot: any string path under assets/generated/ that does not
-- resolve falls back to the active version's prefixed copy
-- (yellow|blue/assets/generated/...).  Covering the whole read surface --
-- not just the loaders we happened to need -- is what keeps future states
-- and mods inside the fallback without anyone updating this file.
--
-- main.lua installs it only when Platform.isNX(); desktop/Android/iOS never
-- install it, so their mountVersion overlay stays the single mechanism and
-- their loaders keep stock behavior.  Write-side functions (write, remove,
-- createDirectory, mount, ...) are deliberately NOT wrapped: the importer
-- must keep targeting the versioned tree explicitly.
--
-- Two intentional exceptions stay outside this module:
--   * the chip-audio worker (src/core/chip_worker.lua) is a separate Lua
--     state without these wrappers; ChipAudio.slimAudio hands it the prefix
--     explicitly as audio.programPrefix.
--   * data/generated module loads go through CacheFs.readActive, which
--     already implements the same fallback for require bytes.

local GameVersion = require("src.core.GameVersion")

local GENERATED = "assets/generated/"

local NxAssetOverlay = {}

local originals -- raw love functions, non-nil while installed

-- Resolve `path` to the versioned copy when the un-prefixed file is missing
-- and the active version (Blue/Yellow) carries it.  Returns nil when the
-- caller's path should be used untouched (non-generated path, Red, the real
-- file exists, or no versioned copy).
local function versioned(path)
  if type(path) ~= "string" then return nil end
  if path:sub(1, #GENERATED) ~= GENERATED then return nil end
  local prefix = GameVersion.cachePrefix()
  if prefix == "" then return nil end
  if originals.getInfo(path) then return nil end
  local candidate = prefix .. path
  if originals.getInfo(candidate) then return candidate end
  return nil
end

local function wrapLoader(fn)
  return function(path, ...)
    local alt = versioned(path)
    if alt then return fn(alt, ...) end
    return fn(path, ...)
  end
end

-- Every read-side love function that can take an assets/generated path.
-- getInfo is wrapped separately (it must return the versioned file's info,
-- not just forward a rewritten argument list).
local WRAP_SPEC = {
  { "filesystem", "read" },
  { "filesystem", "load" },
  { "filesystem", "lines" },
  { "filesystem", "newFileData" },
  { "graphics", "newImage" },
  { "graphics", "newFont" },
  { "image", "newImageData" },
  { "audio", "newSource" },
  { "sound", "newSoundData" },
  { "font", "newFontData" },
}

function NxAssetOverlay.isInstalled()
  return originals ~= nil
end

function NxAssetOverlay.install()
  if originals then return end
  if not (love and love.filesystem) then return end
  originals = {}
  for _, spec in ipairs(WRAP_SPEC) do
    local ns, name = spec[1], spec[2]
    local fn = love[ns] and love[ns][name]
    if fn then
      originals[ns .. "." .. name] = fn
      love[ns][name] = wrapLoader(fn)
    end
  end
  originals.getInfo = love.filesystem.getInfo
  love.filesystem.getInfo = function(path, ...)
    local alt = versioned(path)
    if alt then return originals.getInfo(alt, ...) end
    return originals.getInfo(path, ...)
  end
end

-- Tests restore the stock loaders between cases; the game never uninstalls.
function NxAssetOverlay.uninstall()
  if not originals then return end
  for _, spec in ipairs(WRAP_SPEC) do
    local ns, name = spec[1], spec[2]
    local key = ns .. "." .. name
    if originals[key] then love[ns][name] = originals[key] end
  end
  love.filesystem.getInfo = originals.getInfo
  originals = nil
end

return NxAssetOverlay
