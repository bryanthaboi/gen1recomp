-- FireRed Gen 3 extractor: GBA ROM → firered/ cache under CacheFs.prefix.
-- Parallel to RomExtractor / RomExtractorGen2.  Full Island-1 demake lives in
-- src/import/gba/extract_island1.lua; this module publishes the CacheContract
-- override files and, when possible, runs that extract under
-- data/generated/gba/.

local CacheFs = require("src.import.CacheFs")
local LuaWriter = require("src.import.LuaWriter")

local RomExtractorGen3 = {}
RomExtractorGen3.__index = RomExtractorGen3

local STAGE_COUNT = 5
local GBA_ROOT = "data/generated/gba"

local function hexSha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

local function writeText(rel, body)
  local ok, err = CacheFs.write(rel, body)
  if not ok then
    error("could not write " .. rel .. ": " .. tostring(err))
  end
end

local function writeJson(rel, obj)
  local Json = require("src.link.Json")
  writeText(rel, Json.encode(obj) .. "\n")
end

local function makeImports(romData, sha1)
  return {
    info = function(_, id)
      if id ~= "firered" and id ~= "leafgreen" then
        return nil, "undeclared"
      end
      return {
        id = "firered",
        size = #romData,
        -- versions.lua looks up by SHA-1 (legacy field name is md5).
        md5 = sha1,
        file = "memory",
      }
    end,
    read = function(_, id, offset, length)
      if id ~= "firered" and id ~= "leafgreen" then
        return nil, "undeclared"
      end
      if offset < 0 or length < 0 or offset + length > #romData then
        return nil, "short read"
      end
      return romData:sub(offset + 1, offset + length)
    end,
  }
end

local function makeCache()
  return {
    write = function(_, rel, bytes)
      return CacheFs.write(rel, bytes)
    end,
    read = function(_, rel)
      return CacheFs.read(rel)
    end,
    exists = function(_, rel)
      return CacheFs.exists(rel)
    end,
    info = function(_, rel)
      if CacheFs.exists(rel) then return { type = "file" } end
      return nil
    end,
  }
end

local SUBTASK_RANGES = {
  ["pokemon"]           = { min = 0.42, max = 0.52, label = "Pokémon Species & Icons" },
  ["learnsets"]         = { min = 0.52, max = 0.57, label = "Move Learnsets" },
  ["battle_moves"]      = { min = 0.57, max = 0.60, label = "Battle Moves Data" },
  ["party_chrome"]      = { min = 0.60, max = 0.63, label = "Party UI Graphics" },
  ["battle_chrome"]     = { min = 0.63, max = 0.66, label = "Battle UI Graphics" },
  ["pokedex_entries"]   = { min = 0.66, max = 0.68, label = "Pokédex Database" },
  ["pokedex_categories"]= { min = 0.68, max = 0.69, label = "Pokédex Categories" },
  ["pokedex_orders"]    = { min = 0.69, max = 0.70, label = "Pokédex Sorting" },
  ["pokedex_done"]      = { min = 0.70, max = 0.71, label = "Pokédex Complete" },
  ["storage_chrome"]    = { min = 0.71, max = 0.74, label = "PC Storage Chrome" },
  ["battle_transition"] = { min = 0.74, max = 0.77, label = "Battle Transitions" },
  ["summary_chrome"]    = { min = 0.77, max = 0.80, label = "Summary Screen Graphics" },
  ["bag_chrome"]        = { min = 0.80, max = 0.83, label = "Bag & Items Graphics" },
  ["shop_chrome"]       = { min = 0.83, max = 0.85, label = "Mart & Shop Graphics" },
  ["trainers"]          = { min = 0.85, max = 0.86, label = "Trainer Data & Parties" },
  ["battle_ai"]         = { min = 0.86, max = 0.88, label = "Battle AI Scripts" },
}

function RomExtractorGen3.new(romData, manifest, progressCb, romSha1)
  return setmetatable({
    romData = romData,
    manifest = manifest,
    progress = progressCb,
    romSha1 = romSha1,
    stage = 0,
    _lastPct = 0,
  }, RomExtractorGen3)
end

function RomExtractorGen3:ensureSha1()
  if type(self.romSha1) == "string" and self.romSha1 ~= "" then
    return self.romSha1
  end
  self.romSha1 = hexSha1(self.romData)
  return self.romSha1
end

function RomExtractorGen3:report(pct, stageName, current, stageTotal)
  pct = math.max(self._lastPct or 0, math.min(1.0, pct or 0))
  self._lastPct = pct
  if self.progress then
    self.progress(math.floor(pct * 1000), 1000, stageName or "Extracting", current or 0, stageTotal or 1)
  end
end

function RomExtractorGen3:beginStage(name)
  self.stage = self.stage + 1
  self:report((self.stage - 1) / STAGE_COUNT, name, 0, 1)
end

function RomExtractorGen3:tick(name, current, total)
  local st = SUBTASK_RANGES[name]
  if st then
    local frac = (current or 0) / math.max(total or 1, 1)
    local pct = st.min + frac * (st.max - st.min)
    self:report(pct, st.label, current, total)
  else
    local frac = (current or 0) / math.max(total or 1, 1)
    self:report((self.stage - 1 + frac) / STAGE_COUNT, name, current, total)
  end
end

-- Minimal trees CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.firered needs,
-- plus semantic module stubs for SEMANTIC_MODULES[3].
function RomExtractorGen3:writeRequiredMarkers(sha1)
  local Versions = require("src.import.gba.versions")
  local cache = makeCache()
  local metaRaw = cache:read(GBA_ROOT .. "/meta.json")
  if not metaRaw or not metaRaw:find('"md5"%s*:%s*"' .. sha1 .. '"') or not metaRaw:find('"cache_version"%s*:%s*' .. tostring(Versions.CACHE_VERSION)) then
    writeJson(GBA_ROOT .. "/meta.json", {
      romSha1 = sha1,
      md5 = sha1,
      version = "firered",
      cache_version = Versions.CACHE_VERSION,
      native_version = Versions.NATIVE_VERSION or 5,
      stub = false,
    })
  end
  if not CacheFs.exists(GBA_ROOT .. "/maps.json") then
    writeJson(GBA_ROOT .. "/maps.json", {
      maps = {},
      stub = true,
    })
  end
  if not CacheFs.exists(GBA_ROOT .. "/intro/meta.json") then
    writeJson(GBA_ROOT .. "/intro/meta.json", {
      stub = true,
    })
  end
  if not CacheFs.exists(GBA_ROOT .. "/audio/meta.json") then
    writeJson(GBA_ROOT .. "/audio/meta.json", {
      stub = true,
    })
  end
  if not CacheFs.exists("data/generated/maps.lua") then
    LuaWriter.write("data/generated/maps.lua", { stub = true, maps = {} })
  end
  if not CacheFs.exists("data/generated/intro.lua") then
    LuaWriter.write("data/generated/intro.lua", {
      stub = true,
      generation = 3,
      version = "firered",
    })
  end
  if not CacheFs.exists("data/generated/audio.lua") then
    LuaWriter.write("data/generated/audio.lua", { stub = true })
  end
end

function RomExtractorGen3:runGbaExtract(sha1)
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot, prevNative = Extract.CACHE_ROOT, Extract.NATIVE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT
  Extract.NATIVE_ROOT = GBA_ROOT .. "/native"

  local imports = makeImports(self.romData, sha1)
  local cache = makeCache()
  local runOk, runDetail = false, "extract did not run"
  local callOk, err = pcall(function()
    runOk, runDetail = Extract.run(imports, cache, function(stage, n, name, cur, total)
      local curFrac = (cur or 0) / math.max(total or 1, 1)
      local frac = ((stage or 0) + curFrac) / math.max(n or Extract.STAGE_COUNT or 7, 1)
      local pct = 0.03 + math.min(frac, 1.0) * 0.39
      self:report(pct, name or "World & Maps", cur or 0, total or 1)
    end)
  end)

  Extract.CACHE_ROOT = prevRoot
  Extract.NATIVE_ROOT = prevNative

  if not callOk then
    return false, err
  end
  return runOk, runDetail
end

--- Species pack + party chrome into data/generated/gba/pokemon/.
function RomExtractorGen3:runPokemonExtract(sha1)
  local Rom = require("src.import.gba.rom")
  local PokemonExtract = require("src.import.gba.pokemon_extract")
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot = Extract.CACHE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT

  local cache = makeCache()
  if PokemonExtract.ready(cache, GBA_ROOT) then
    Extract.CACHE_ROOT = prevRoot
    return true, { skipped = true }
  end

  local imports = makeImports(self.romData, sha1)
  local rom, openErr = Rom.open(imports, "firered")
  if not rom then
    Extract.CACHE_ROOT = prevRoot
    return false, openErr or "rom open failed"
  end

  local ok, detail = pcall(function()
    local pRes = PokemonExtract.run(rom, cache, {
      cacheRoot = GBA_ROOT,
      progress = function(name, cur, total)
        self:tick(name or "pokemon", cur or 0, total or 1)
      end,
    })
    local ItemsExtract = require("src.import.gba.items_extract")
    ItemsExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    local PokedexExtract = require("src.import.gba.pokedex_chrome_extract")
    PokedexExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    local StorageExtract = require("src.import.gba.storage_chrome_extract")
    StorageExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    local TextChromeExtract = require("src.import.gba.text_chrome_extract")
    TextChromeExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    local TrainerCardExtract = require("src.import.gba.trainer_card_extract")
    TrainerCardExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    return pRes
  end)

  Extract.CACHE_ROOT = prevRoot
  if not ok then
    return false, detail
  end
  return true, detail
end

function RomExtractorGen3:runIntroAudio(sha1)
  self:report(0.88, "Intro Cutscene & Audio", 0, 1)
  local cache = makeCache()
  if cache:exists(GBA_ROOT .. "/intro/meta.json") and cache:exists(GBA_ROOT .. "/audio/meta.json") then
    local im = cache:read(GBA_ROOT .. "/intro/meta.json")
    if im and not im:find('"stub"%s*:%s*true') then
      self:report(0.98, "Audio Streams Ready", 1, 1)
      return true, true
    end
  end

  local romShim = { data = self.romData }
  local Intro = require("src.import.gba.extract_intro")
  local Naming = require("src.import.gba.extract_naming")
  local AudioExt = require("src.import.gba.extract_audio")
  self:report(0.90, "Intro Cutscene", 0, 1)
  local okI, metaI = Intro.run(romShim, cache, { sha1 = sha1, root = GBA_ROOT .. "/intro" })
  self:report(0.93, "Naming Screen", 0, 1)
  local okN = Naming.run(romShim, cache, { sha1 = sha1, root = GBA_ROOT .. "/naming" })
  self:report(0.95, "Audio Sequences & Streams", 0, 1)
  local okA, metaA = AudioExt.run(romShim, cache, { sha1 = sha1, root = GBA_ROOT .. "/audio" })
  writeJson(GBA_ROOT .. "/intro/extract_status.json", { ok = okI == true })
  writeJson(GBA_ROOT .. "/naming/extract_status.json", { ok = okN == true })
  writeJson(GBA_ROOT .. "/audio/extract_status.json", { ok = okA == true })
  self:report(0.98, "Audio Streams Ready", 1, 1)
  return okI, okA, metaI, metaA
end

function RomExtractorGen3:run()
  local sha1 = self:ensureSha1()

  self:report(0.01, "Initializing Markers", 0, 1)
  self:writeRequiredMarkers(sha1)
  self:report(0.03, "Markers Ready", 1, 1)

  local ok, detail = self:runGbaExtract(sha1)
  if ok then
    if not CacheFs.exists(GBA_ROOT .. "/maps.json") then
      writeJson(GBA_ROOT .. "/maps.json", { maps = {}, from_extract = true })
    end
  else
    writeJson(GBA_ROOT .. "/extract_status.json", {
      ok = false,
      error = tostring(detail),
      romSha1 = sha1,
    })
    error("GBA extract failed: " .. tostring(detail))
  end
  self:report(0.42, "World Maps Ready", 1, 1)

  local okPoke, pokeDetail = self:runPokemonExtract(sha1)
  writeJson(GBA_ROOT .. "/pokemon/extract_status.json", {
    ok = okPoke == true,
    error = okPoke and nil or tostring(pokeDetail),
  })
  if not okPoke then
    error("Pokemon extract failed: " .. tostring(pokeDetail))
  end
  self:report(0.88, "Game Data & Chrome Ready", 1, 1)

  self:runIntroAudio(sha1)
  self:report(0.98, "Finalizing Cache", 1, 1)

  self:report(1.00, "Ready", 1, 1)
  return {
    romSha1 = sha1,
    extractOk = ok == true,
    pokemonOk = okPoke == true,
    detail = detail,
  }
end

return RomExtractorGen3
