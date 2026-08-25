-- Engine-owned contract for generated ROM caches.
--
-- A cache is playable only when its versioned marker matches the ROM and every
-- required output for that version exists. Extraction writers may differ by
-- platform, but they must publish through this contract so partial staging
-- cannot look ready to the runtime.
local GameVersion = require("src.core.GameVersion")

local CacheContract = {}

CacheContract.FORMAT = "rom-cache-v10:"
CacheContract.VERSION_FORMAT = {
  crystal = "rom-cache-v10-crystal3:",
}
CacheContract.MARKER_PATH = "rom-cache.complete"

CacheContract.REQUIRED_FILES = {
  "data/generated/constants.lua",
  "data/generated/maps.lua",
  "data/generated/text.lua",
  "data/generated/field.lua",
  "data/generated/battle_anims.lua",
  "assets/generated/title/pokemon_logo.png",
  "assets/generated/fonts/font.png",
  "assets/generated/battle/front/pikachu.png",
  "assets/generated/battle/anims/move_anim_0.png",
  "assets/generated/battle/anims/move_anim_1.png",
  "assets/generated/audio/programs.bin",
  "assets/generated/trade/game_boy.png",
}

CacheContract.VERSION_REQUIRED_FILES = {
  yellow = {
    "assets/generated/battle/trainers/jessie_james.png",
    "assets/generated/battle/profoakb.png",
    "assets/generated/pikachu/pikapic_1.png",
    "assets/generated/minigame/surf_1a.png",
    "assets/generated/minigame/surf_1b.png",
    "assets/generated/minigame/surf_1c.png",
    "assets/generated/minigame/title_bg.png",
    "assets/generated/minigame/intro_pika_0.png",
  },
}

CacheContract.VERSION_REQUIRED_FILES_OVERRIDE = {
  gold = {
    "data/generated/constants.lua",
    "data/generated/maps.lua",
    "data/generated/roofs.lua",
    "data/generated/sprites.lua",
    "data/generated/scripts.lua",
    "data/generated/text.lua",
    -- The engine's label-keyed strings are separate from Gen 2 script text.
    -- Caches made before RomExtractorGen2:extractText must be rebuilt so
    -- src/core/RomText.lua does not silently fall back to built-in wording.
    "data/generated/rom_text.lua",
    "data/generated/pokemon.lua",
    "data/generated/tilesets.lua",
    "data/generated/audio.lua",
    "data/generated/marts.lua",
    "assets/generated/fonts/font.png",
    "assets/generated/fonts/frames.png",
    "assets/generated/title/pokemon_logo.png",
    "assets/generated/title/title_screen.png",
    "assets/generated/title/hooh.png",
    "assets/generated/title/hooh_5.png",
    "assets/generated/title/clouds.png",
    "assets/generated/title/copyright_splash.png",
    "data/generated/oak_speech.lua",
    "assets/generated/intro/oak.png",
    "assets/generated/intro/cal.png",
    "assets/generated/tilesets/johto.png",
    "assets/generated/tilesets/roofs/new_bark.png",
    "assets/generated/sprites/chris.png",
    "assets/generated/battle/front/chikorita.png",
    "assets/generated/battle/front/pikachu.png",
    "assets/generated/battle/front/marill.png",
    "assets/generated/battle/trainers/falkner.png",
    "assets/generated/battle/hud/balls.png",
    "assets/generated/audio/programs.bin",
    "assets/generated/slots/gold_slots_1.png",
    "assets/generated/card_flip/card_flip_1.png",
    "assets/generated/pc/mail_item.png",
    -- engine/events/fishing_gfx.asm:23
    "assets/generated/emotes/fishing.png",
  },
  crystal = {
    "data/generated/constants.lua",
    "data/generated/maps.lua",
    "data/generated/roofs.lua",
    "data/generated/sprites.lua",
    "data/generated/scripts.lua",
    "data/generated/text.lua",
    "data/generated/rom_text.lua",
    "data/generated/pokemon.lua",
    "data/generated/encounters.lua",
    "data/generated/tilesets.lua",
    "data/generated/landmarks.lua",
    "data/generated/audio.lua",
    "data/generated/marts.lua",
    "data/generated/oak_speech.lua",
    "data/generated/title.lua",
    "data/generated/intro.lua",
    "assets/generated/fonts/font.png",
    "assets/generated/fonts/frames.png",
    "assets/generated/title/crystal_logo.png",
    "assets/generated/title/crystal_wordmark.png",
    "assets/generated/title/crystal_suicune.png",
    "assets/generated/title/copyright_splash.png",
    "assets/generated/splash/ditto.png",
    "assets/generated/intro/chris.png",
    "assets/generated/intro/kris.png",
    "assets/generated/intro/suicune_run_sprites.png",
    "assets/generated/intro/unowns_tiles.png",
    "assets/generated/intro/oak.png",
    "assets/generated/tilesets/johto.png",
    "assets/generated/tilesets/roofs/new_bark.png",
    "assets/generated/sprites/chris.png",
    "assets/generated/sprites/kris.png",
    "assets/generated/battle/front/chikorita.png",
    "assets/generated/battle/front/wooper.png",
    "assets/generated/battle/front/pikachu.png",
    "assets/generated/battle/trainers/falkner.png",
    "assets/generated/battle/hud/balls.png",
    "assets/generated/audio/programs.bin",
    "assets/generated/slots/gold_slots_1.png",
    "assets/generated/card_flip/card_flip_1.png",
    "assets/generated/pc/mail_item.png",
    "assets/generated/trainer_card/card_f.png",
    "data/generated/mobile_gfx.lua",
    "assets/generated/battle/player_back_female.png",
    "assets/generated/battle/trainers/kris.png",
    "assets/generated/battle/trainers/chris.png",
    -- ../pokecrystal/engine/events/fishing_gfx.asm:38-42
    "assets/generated/emotes/fishing.png",
  },
}
CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.silver =
  CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.gold

local SEMANTIC_MODULES = {
  [1] = {
    "constants", "maps", "tilesets", "text", "text_pointers",
    "trainer_headers", "font", "sprites", "pokemon", "moves", "items",
    "type_chart", "trainers", "encounters", "field", "battle_anims",
  },
  [2] = {
    "pokemon", "moves", "items", "type_chart", "audio", "font", "maps",
    "tilesets", "text", "trainers", "encounters", "sprites", "palettes",
    "icons", "battle_anims", "constants", "landmarks",
  },
}

local OPTIONAL_SEMANTIC_MODULES = {
  [1] = { "audio", "palettes", "icons" },
  [2] = {},
}

local function copy(values)
  local out = {}
  for index, value in ipairs(values or {}) do out[index] = value end
  return out
end

function CacheContract.requiredFilesFor(version)
  local override = CacheContract.VERSION_REQUIRED_FILES_OVERRIDE[version]
  if override then return override, true end
  return CacheContract.REQUIRED_FILES, false
end

-- A detached, version-specific inventory for read-only consumers. Semantic
-- consumers additionally require every generated module that backs the public
-- registry surface; optional semantic roots are discovered lazily.
function CacheContract.requiredFiles(version, semantic)
  local base, isOverride = CacheContract.requiredFilesFor(version)
  local files = copy(base)
  if not isOverride then
    for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
      files[#files + 1] = path
    end
  end
  if semantic then
    for _, name in ipairs(SEMANTIC_MODULES[GameVersion.generation(version)] or {}) do
      files[#files + 1] = "data/generated/" .. name .. ".lua"
    end
  end
  local seen, out = {}, {}
  for _, path in ipairs(files) do
    if not seen[path] then
      seen[path] = true
      out[#out + 1] = path
    end
  end
  return out
end

function CacheContract.semanticModules(version)
  return copy(SEMANTIC_MODULES[GameVersion.generation(version)])
end

function CacheContract.optionalSemanticModules(version)
  return copy(OPTIONAL_SEMANTIC_MODULES[GameVersion.generation(version)])
end

function CacheContract.formatFor(version)
  return CacheContract.VERSION_FORMAT[version] or CacheContract.FORMAT
end

function CacheContract.markerFor(version, sha1)
  return CacheContract.formatFor(version)
    .. (sha1 or GameVersion.info(version).sha1)
end

function CacheContract.markerMatches(version, marker)
  for _, revision in ipairs(GameVersion.revisions(version)) do
    if marker == CacheContract.markerFor(version, revision.sha1) then return true end
  end
  return false
end

-- Keep the process-global CacheFs prefix isolated even when a filesystem
-- adapter raises while probing or publishing.  The real CacheFs methods
-- return errors, but this also makes the contract safe for platform adapters
-- that surface I/O failures as Lua errors.
local function withVersionPrefix(version, fs, action)
  local saved = fs.prefix
  fs.prefix = GameVersion.cachePrefix(version)
  local ok, first, second = pcall(action)
  fs.prefix = saved
  if not ok then return false, first end
  return true, first, second
end

function CacheContract.allRequiredFilesExist(version, fs)
  fs = fs or require("src.import.CacheFs")
  local ok, complete, missing = withVersionPrefix(version, fs, function()
    local required, isOverride = CacheContract.requiredFilesFor(version)
    local missingPath
    for _, path in ipairs(required) do
      if not fs.exists(path) then missingPath = path; break end
    end
    if not missingPath and not isOverride then
      for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
        if not fs.exists(path) then missingPath = path; break end
      end
    end
    return missingPath == nil, missingPath
  end)
  if not ok then return false, complete end
  return complete, missing
end

function CacheContract.readMarker(version, fs)
  fs = fs or require("src.import.CacheFs")
  local ok, marker, readError = withVersionPrefix(version, fs, function()
    return fs.read(CacheContract.MARKER_PATH)
  end)
  if not ok then return nil, marker end
  -- LÖVE may return contents plus a byte count; only a nil contents result
  -- makes the auxiliary value an error.  CacheFs' portable reader returns
  -- just the contents, so this remains adapter-neutral.
  if marker == nil then return nil, readError end
  return marker
end

function CacheContract.isReady(version, fs)
  fs = fs or require("src.import.CacheFs")
  if CacheContract.sourceTreeHasData(version) then return true end
  local marker, readError = CacheContract.readMarker(version, fs)
  if readError or not CacheContract.markerMatches(version, marker) then return false end
  return CacheContract.allRequiredFilesExist(version, fs)
end

function CacheContract.publish(version, fs, sha1)
  fs = fs or require("src.import.CacheFs")
  local complete, missing = CacheContract.allRequiredFilesExist(version, fs)
  if not complete then
    -- A caller may be retrying over a partially replaced cache.  Do not
    -- leave its old marker advertising readiness after this failed check.
    local removed, removeError = withVersionPrefix(version, fs, function()
      if not fs.remove then
        error("cache filesystem cannot remove the completion marker")
      end
      return fs.remove(CacheContract.MARKER_PATH)
    end)
    if not removed then
      return false, "cache is incomplete; missing " .. tostring(missing)
        .. "; could not remove completion marker: " .. tostring(removeError)
    end
    return false, "cache is incomplete; missing " .. tostring(missing)
  end
  local changed, ok, err = withVersionPrefix(version, fs, function()
    return fs.write(CacheContract.MARKER_PATH, CacheContract.markerFor(version, sha1))
  end)
  if not changed then return false, tostring(ok) end
  return ok, err
end

function CacheContract.sourceTreeHasData(version)
  if not (love and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getRealDirectory and love.filesystem.getSource) then
    return false
  end
  local prefix = version == "red" and "" or GameVersion.cachePrefix(version)
  local required, isOverride = CacheContract.requiredFilesFor(version)
  local source = love.filesystem.getSource()
  for _, path in ipairs(required) do
    local fullPath = prefix .. path
    if love.filesystem.getInfo(fullPath, "file") == nil
        or love.filesystem.getRealDirectory(fullPath) ~= source then
      return false
    end
  end
  if not isOverride then
    for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
      local fullPath = prefix .. path
      if love.filesystem.getInfo(fullPath, "file") == nil
          or love.filesystem.getRealDirectory(fullPath) ~= source then
        return false
      end
    end
  end
  return true
end

-- Inspect another version without mutating CacheFs.prefix, GameVersion, mounts,
-- or the active Data table. The injected filesystem addresses exact paths.
local function readAt(fs, path)
  if fs.readAt then return fs.readAt(path) end
  if fs.read then return fs.read(path) end
  return nil
end

local function isFileAt(fs, path)
  if fs.getInfo then
    local info = fs.getInfo(path, "file")
    return info ~= nil and (info.type == nil or info.type == "file")
  end
  if fs.existsAt then return fs.existsAt(path) == true end
  return false
end

local function hasExactFiles(version, fs, prefix, semantic)
  for _, path in ipairs(CacheContract.requiredFiles(version, semantic)) do
    if not isFileAt(fs, prefix .. path) then return false, path end
  end
  return true
end

local function sourceReady(version, fs, semantic)
  if not (fs.getInfo and fs.getRealDirectory and fs.getSource) then return nil end
  local prefix = version == "red" and "" or GameVersion.cachePrefix(version)
  local complete = hasExactFiles(version, fs, prefix, semantic)
  if not complete then return nil end
  local first = prefix .. CacheContract.requiredFiles(version, semantic)[1]
  if fs.getRealDirectory(first) ~= fs.getSource() then return nil end
  return { kind = "source", prefix = prefix }
end

function CacheContract.inspect(version, fs, opts)
  opts = opts or {}
  if not (GameVersion.VERSIONS[version] and fs) then
    return nil, "not_imported", "unsupported cache inspection"
  end
  if opts.allowSource then
    local source = sourceReady(version, fs, opts.semantic)
    if source then return source end
  end
  local prefix = GameVersion.cachePrefix(version)
  local marker = readAt(fs, prefix .. CacheContract.MARKER_PATH)
  if not CacheContract.markerMatches(version, marker) then
    return nil, "not_imported", "completion marker is missing or stale"
  end
  local complete, missing = hasExactFiles(version, fs, prefix, opts.semantic)
  if not complete then
    return nil, "not_imported", "required cache file is missing: " .. tostring(missing)
  end
  return { kind = "cache", prefix = prefix, marker = marker }
end

return CacheContract
