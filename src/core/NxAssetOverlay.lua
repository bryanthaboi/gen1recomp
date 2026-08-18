-- NX-only asset overlay: fused love-nx cannot reliably mount
-- blue|yellow|gold/{assets,data}/generated onto the un-prefixed paths, so
-- instead of teaching every call site about versioned caches, this module
-- wraps EVERY read-side love entry point that accepts a filesystem path
-- once at boot: any string path under assets/generated/ or data/generated/
-- prefers the active version's prefixed copy (yellow|blue|gold/...) when
-- that file exists, so leftover unprefixed Red cache cannot shadow it.
-- Covering the whole read surface --
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
--   * Gen 1 Data:load and Gold Game2/World go through CacheFs.readActive /
--     CacheFs.loadActive, which implement the same fallback for Lua bytes.
--     data/generated is still rewritten here so any leftover
--     love.filesystem.load("data/generated/...") call (the Gold intro /
--     naming / maps hole on 0.2.4) stays inside the overlay.

local GameVersion = require("src.core.GameVersion")

local GENERATED_PREFIXES = {
  "assets/generated/",
  "data/generated/",
}

local NxAssetOverlay = {}

local originals -- raw love functions, non-nil while installed

-- Resolve `path` to the active version's prefixed copy when that file
-- exists (gold|yellow|blue|red/{assets,data}/generated/...).  The versioned
-- tree wins over a leftover un-prefixed file so a pre-#899 Red root cache
-- (assets/generated/font.png in the save dir) cannot shadow Gold/Blue/
-- Yellow art that shares a name.  Returns nil when the caller's path
-- should be used untouched (non-generated path, empty prefix, or no
-- versioned copy).
local function versioned(path)
  if type(path) ~= "string" then return nil end
  local generated = false
  for i = 1, #GENERATED_PREFIXES do
    local gen = GENERATED_PREFIXES[i]
    if path:sub(1, #gen) == gen then
      generated = true
      break
    end
  end
  if not generated then return nil end
  local prefix = GameVersion.cachePrefix()
  if prefix == "" then return nil end
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
