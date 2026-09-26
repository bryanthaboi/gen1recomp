local CacheFs = require("src.import.CacheFs")
local LuaWriter = require("src.import.LuaWriter")
local GameVersion = require("src.core.GameVersion")
local CachePaths = require("src.core.game3.cache_paths")

local RomExtractorGen3 = {}
RomExtractorGen3.__index = RomExtractorGen3

local STAGE_COUNT = 5
local GBA_ROOT = CachePaths.CACHE_ROOT

local function canonicalImportId(id)
  return id == "leafgreen" and "firered" or id
end

local function importVersion(sha1)
  return GameVersion.forSha1(sha1) or "firered"
end

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
  local Canon = require("src.import.canonical_json")
  writeText(rel, Canon.encode(obj) .. "\n")
end

local function makeImports(romData, sha1, version)
  version = version or importVersion(sha1)
  return {
    info = function(_, id)
      if canonicalImportId(id) ~= canonicalImportId(version) then
        return nil, "undeclared"
      end
      return {
        id = canonicalImportId(version),
        size = #romData,
        -- versions.lua looks up by SHA-1 (legacy field name is md5).
        md5 = sha1,
        file = "memory",
      }
    end,
    read = function(_, id, offset, length)
      if canonicalImportId(id) ~= canonicalImportId(version) then
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

local POKEMON_SUBTASKS = {
  ["pokemon"]           = { min = 0.00, max = 0.50, label = "Pokémon Species & Sprites" },
  ["learnsets"]         = { min = 0.50, max = 0.58, label = "Move Learnsets" },
  ["battle_moves"]      = { min = 0.58, max = 0.62, label = "Battle Moves Data" },
  ["party_chrome"]      = { min = 0.62, max = 0.68, label = "Party UI Graphics" },
  ["battle_chrome"]     = { min = 0.68, max = 0.74, label = "Battle UI Graphics" },
  ["pokedex_entries"]   = { min = 0.74, max = 0.78, label = "Pokédex Database" },
  ["pokedex_categories"]= { min = 0.78, max = 0.80, label = "Pokédex Categories" },
  ["pokedex_orders"]    = { min = 0.80, max = 0.82, label = "Pokédex Sorting" },
  ["pokedex_done"]      = { min = 0.82, max = 0.84, label = "Pokédex Complete" },
  ["storage_chrome"]    = { min = 0.84, max = 0.88, label = "PC Storage Chrome" },
  ["battle_transition"] = { min = 0.88, max = 0.92, label = "Battle Transitions" },
  ["summary_chrome"]    = { min = 0.92, max = 0.96, label = "Summary Screen Graphics" },
  ["bag_chrome"]        = { min = 0.96, max = 0.98, label = "Bag & Items Graphics" },
  ["shop_chrome"]       = { min = 0.98, max = 1.00, label = "Mart & Shop Graphics" },
}

function RomExtractorGen3.new(romData, manifest, progressCb, romSha1)
  local sha1 = romSha1 or (manifest and manifest.romSha1) or hexSha1(romData)
  require("src.import.gba.versions").select(sha1)
  return setmetatable({
    version = assert(require("src.core.GameVersion").forSha1(sha1), "unknown FRLG ROM"),
    romData = romData,
    manifest = manifest,
    progress = progressCb,
    romSha1 = romSha1,
    stage = 0,
    _lastPct = 0,
  }, RomExtractorGen3)
end

function RomExtractorGen3:sharedImports(sha1)
  if not self._imports then
    self._imports = makeImports(self.romData, sha1, importVersion(sha1))
  end
  return self._imports
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

function RomExtractorGen3:tickPokemon(name, current, total)
  local st = POKEMON_SUBTASKS[name]
  if st then
    local curFrac = (current or 0) / math.max(total or 1, 1)
    local frac = st.min + curFrac * (st.max - st.min)
    local label = st.label
    if total and total > 1 then
      label = label .. string.format(" (%d/%d)", current or 0, total)
    end
    self:report(frac, label, current, total)
  else
    local frac = (current or 0) / math.max(total or 1, 1)
    self:report(frac, name or "Pokémon Data", current, total)
  end
end

-- plus semantic module stubs for SEMANTIC_MODULES[3].
function RomExtractorGen3:writeRequiredMarkers(sha1)
  local Versions = require("src.import.gba.versions")
  local version = importVersion(sha1)
  local cache = makeCache()
  local metaRaw = cache:read(GBA_ROOT .. "/meta.json")
  if not metaRaw or not metaRaw:find('"md5"%s*:%s*"' .. sha1 .. '"') or not metaRaw:find('"cache_version"%s*:%s*' .. tostring(Versions.CACHE_VERSION)) then
    writeJson(GBA_ROOT .. "/meta.json", {
      romSha1 = sha1,
      md5 = sha1,
      version = version,
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
      version = version,
    })
  end
  if not CacheFs.exists("data/generated/audio.lua") then
    LuaWriter.write("data/generated/audio.lua", { stub = true })
  end

  local dirs = {
    GBA_ROOT,
    GBA_ROOT .. "/pokemon",
    GBA_ROOT .. "/pokemon/front",
    GBA_ROOT .. "/pokemon/back",
    GBA_ROOT .. "/pokemon/front_shiny",
    GBA_ROOT .. "/pokemon/back_shiny",
    GBA_ROOT .. "/pokemon/icons",
    GBA_ROOT .. "/pokemon/party",
    GBA_ROOT .. "/pokemon/storage",
    GBA_ROOT .. "/pokemon/battle",
    GBA_ROOT .. "/pokemon/pokedex",
    GBA_ROOT .. "/region_map",
    GBA_ROOT .. "/map_preview",
    GBA_ROOT .. "/items",
    GBA_ROOT .. "/items/bag",
    GBA_ROOT .. "/items/shop",
    GBA_ROOT .. "/items/tm_case",
    GBA_ROOT .. "/items/berry_pouch",
    GBA_ROOT .. "/battle_ai",
    GBA_ROOT .. "/intro",
    GBA_ROOT .. "/audio",
    GBA_ROOT .. "/chrome",
    GBA_ROOT .. "/chrome/fonts",
    GBA_ROOT .. "/ow",
    GBA_ROOT .. "/native",
  }
  for _, d in ipairs(dirs) do
    if love and love.filesystem and love.filesystem.createDirectory then
      local p = (CacheFs.prefix or "") .. d
      pcall(love.filesystem.createDirectory, p)
    end
  end
end

function RomExtractorGen3:runGbaExtract(sha1, skipScriptsAndOw)
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot, prevNative = Extract.CACHE_ROOT, Extract.NATIVE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT
  Extract.NATIVE_ROOT = GBA_ROOT .. "/native"

  local imports = self:sharedImports(sha1)
  local cache = makeCache()
  local runOk, runDetail = false, "extract did not run"
  local callOk, err = pcall(function()
    runOk, runDetail = Extract.run(imports, cache, function(stage, n, name, cur, total)
      local curFrac = (cur or 0) / math.max(total or 1, 1)
      local frac = ((stage or 0) + curFrac) / math.max(n or Extract.STAGE_COUNT or 7, 1)
      local label = "World Maps: " .. tostring(name or "Processing")
      if total and total > 1 then
        label = label .. string.format(" (%d/%d)", cur or 0, total)
      end
      self:report(math.min(frac, 1.0), label, cur or 0, total or 1)
    end, { skipScriptsAndOw = skipScriptsAndOw == true })
  end)

  Extract.CACHE_ROOT = prevRoot
  Extract.NATIVE_ROOT = prevNative

  if not callOk then
    return false, err
  end
  return runOk, runDetail
end

function RomExtractorGen3:runScriptsAndOwExtract(sha1)
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot = Extract.CACHE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT

  local imports = self:sharedImports(sha1)
  local cache = makeCache()
  local runOk, runDetail = false, "scripts_ow did not run"
  local callOk, err = pcall(function()
    runOk = Extract.runScriptsAndOw(imports, cache, function(cur, total, stageName)
      local frac = (cur or 0) / math.max(total or 4, 1)
      self:report(frac, "Scripts & OW: " .. tostring(stageName or "Processing"), cur or 0, total or 4)
    end)
    return runOk
  end)

  Extract.CACHE_ROOT = prevRoot
  if not callOk then return false, err end
  return runOk, runDetail
end

--- Species pack + party chrome into data/generated/gba/pokemon/.
function RomExtractorGen3:runPokemonExtract(sha1, spMin, spMax)
  local Rom = require("src.import.gba.rom")
  local PokemonExtract = require("src.import.gba.pokemon_extract")
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot = Extract.CACHE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT

  local cache = makeCache()
  if not spMin and PokemonExtract.ready(cache, GBA_ROOT) then
    Extract.CACHE_ROOT = prevRoot
    return true, { skipped = true }
  end

  local imports = self:sharedImports(sha1)
  local version = importVersion(sha1)
  local rom, openErr = Rom.open(imports, version)
  if not rom then
    Extract.CACHE_ROOT = prevRoot
    return false, openErr or "rom open failed"
  end

  local ok, detail = pcall(function()
    local pRes = PokemonExtract.run(rom, cache, {
      cacheRoot = GBA_ROOT,
      spMin = spMin or 0,
      spMax = spMax,
      progress = function(name, cur, total)
        self:tickPokemon(name or "pokemon", cur or 0, total or 1)
      end,
    })
    local SeagallopExtract = require("src.import.gba.seagallop_extract")
    SeagallopExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    require("src.import.gba.cave_transition_extract").run(rom, cache, { cacheRoot = GBA_ROOT })
    require("src.import.gba.weather_extract").run(rom, cache, { cacheRoot = GBA_ROOT })
    require("src.import.gba.ingame_trades_extract").run(rom, cache, { cacheRoot = GBA_ROOT })
    require("src.import.gba.union_room_classes_extract").run(rom, cache, { cacheRoot = GBA_ROOT })
    return pRes
  end)

  Extract.CACHE_ROOT = prevRoot
  if not ok then
    return false, detail
  end
  return true, detail
end

function RomExtractorGen3:runPokemonGfxExtract(sha1, spMin, spMax)
  local Rom = require("src.import.gba.rom")
  local PokemonExtract = require("src.import.gba.pokemon_extract")
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot = Extract.CACHE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT

  local imports = self:sharedImports(sha1)
  local version = importVersion(sha1)
  local rom, openErr = Rom.open(imports, version)
  if not rom then
    Extract.CACHE_ROOT = prevRoot
    return false, openErr or "rom open failed"
  end

  local cache = makeCache()
  local ok, detail = pcall(function()
    return PokemonExtract.run(rom, cache, {
      cacheRoot = GBA_ROOT,
      spMin = spMin or 0,
      spMax = spMax or 200,
      onlySpeciesGfx = true,
      progress = function(name, cur, total)
        self:tickPokemon(name or "pokemon", cur or 0, total or 1)
      end,
    })
  end)

  Extract.CACHE_ROOT = prevRoot
  if not ok then
    return false, detail
  end
  return true, detail
end

function RomExtractorGen3:runAuxExtracts(sha1)
  local GameVersion = require("src.core.GameVersion")
  local Profile = require("src.core.game3.profile")
  local wantedList = Profile.of(GameVersion.get()).extractors
  local wanted = nil
  if type(wantedList) == "table" and #wantedList > 0 then
    wanted = {}
    for _, name in ipairs(wantedList) do wanted[name] = true end
  end
  local function wantedExtractor(name)
    return wanted == nil or wanted[name] == true
  end
  local Rom = require("src.import.gba.rom")
  local RegionMapExtract = require("src.import.gba.region_map_extract")
  local MapSectionsExtract = require("src.import.gba.map_sections_extract")
  local MultichoiceExtract = require("src.import.gba.multichoice_extract")
  local HealLocationsExtract = require("src.import.gba.heal_locations_extract")
  local DoorAnimExtract = require("src.import.gba.door_anim_extract")
  local SlotMachineExtract = require("src.import.gba.slot_machine_extract")
  local TradeExtract = require("src.import.gba.trade_extract")
  local LinkArtExtract = require("src.import.gba.link_art_extract")
  local FameCheckerExtract = require("src.import.gba.fame_checker_extract")
  local TeachyTvExtract = require("src.import.gba.teachy_tv_extract")
  local MysteryGiftExtract = require("src.import.gba.mystery_gift_extract")
  local TrainerTowerExtract = require("src.import.gba.trainer_tower_extract")
  local TutorExtract = require("src.import.gba.tutor_extract")
  local MuseumExtract = require("src.import.gba.museum_extract")
  local MoveRelearnerExtract = require("src.import.gba.move_relearner_extract")
  local EggExtract = require("src.import.gba.egg_extract")
  local BattleAnimExtract = require("src.import.gba.battle_anim_extract")
  local BattleAiExtract = require("src.import.gba.battle_ai_extract")
  local CreditsExtract = require("src.import.gba.credits_extract")
  local LeagueExtract = require("src.import.gba.league_extract")
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot = Extract.CACHE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT

  local cache = makeCache()
  local needRegion = wantedExtractor("region_map_extract") and not (RegionMapExtract.ready and RegionMapExtract.ready(cache, GBA_ROOT))
  local needSections = wantedExtractor("map_sections_extract")
    and not CacheFs.exists(GBA_ROOT .. "/region_map/map_sections.lua")
  local needChoices = wantedExtractor("multichoice_extract") and not (MultichoiceExtract.ready and MultichoiceExtract.ready(cache, GBA_ROOT))
  local needHeal = wantedExtractor("heal_locations_extract") and not (HealLocationsExtract.ready and HealLocationsExtract.ready(cache, GBA_ROOT))
  local needDoors = wantedExtractor("door_anim_extract") and not (DoorAnimExtract.ready and DoorAnimExtract.ready(cache, GBA_ROOT))
  local needSlots = wantedExtractor("slot_machine_extract") and not (SlotMachineExtract.ready and SlotMachineExtract.ready(cache, GBA_ROOT))
  local needTrade = wantedExtractor("trade_extract") and not (TradeExtract.ready and TradeExtract.ready(cache, GBA_ROOT))
  local needLinkArt = wantedExtractor("link_art_extract") and not (LinkArtExtract.ready and LinkArtExtract.ready(cache, GBA_ROOT))
  local needFame = wantedExtractor("fame_checker_extract") and not (FameCheckerExtract.ready and FameCheckerExtract.ready(cache, GBA_ROOT))
  local needTeachy = wantedExtractor("teachy_tv_extract") and not (TeachyTvExtract.ready and TeachyTvExtract.ready(cache, GBA_ROOT))
  local needGift = wantedExtractor("mystery_gift_extract") and not (MysteryGiftExtract.ready and MysteryGiftExtract.ready(cache, GBA_ROOT))
  local needTower = wantedExtractor("trainer_tower_extract") and not (TrainerTowerExtract.ready and TrainerTowerExtract.ready(cache, GBA_ROOT))
  local needTutor = wantedExtractor("tutor_extract") and not (TutorExtract.ready and TutorExtract.ready(cache, GBA_ROOT))
  local needMuseum = wantedExtractor("museum_extract") and not (MuseumExtract.ready and MuseumExtract.ready(cache, GBA_ROOT))
  local needRelearner = wantedExtractor("move_relearner_extract") and not (MoveRelearnerExtract.ready and MoveRelearnerExtract.ready(cache, GBA_ROOT))
  local needEgg = wantedExtractor("egg_extract") and not (EggExtract.ready and EggExtract.ready(cache, GBA_ROOT))
  local needAnims = wantedExtractor("battle_anim_extract") and not (BattleAnimExtract.ready and BattleAnimExtract.ready(cache, GBA_ROOT))
  local needAi = wantedExtractor("battle_ai_extract") and not (BattleAiExtract.ready and BattleAiExtract.ready(cache, GBA_ROOT))
  local MapPreviewExtract = require("src.import.gba.map_preview_extract")
  local needPreview = wantedExtractor("map_preview_extract") and not (MapPreviewExtract.ready and MapPreviewExtract.ready(cache, GBA_ROOT))
  local needCredits = wantedExtractor("credits_extract") and not (CreditsExtract.ready and CreditsExtract.ready(cache, GBA_ROOT))
  local needLeague = wantedExtractor("league_extract") and not (LeagueExtract.ready and LeagueExtract.ready(cache, GBA_ROOT))

  if not (needRegion or needSections or needChoices or needHeal or needDoors
    or needSlots or needTrade or needLinkArt or needFame or needTeachy
    or needGift or needTower or needTutor or needMuseum or needRelearner
    or needEgg or needAnims or needAi or needPreview or needCredits or needLeague) then
    Extract.CACHE_ROOT = prevRoot
    return true, { skipped = true }
  end

  local rom, openErr = Rom.open(self:sharedImports(sha1), importVersion(sha1))
  if not rom then
    Extract.CACHE_ROOT = prevRoot
    return false, openErr or "rom open failed"
  end

  local ok, detail = pcall(function()
    local out = {}
    local step = 0
    local totalSteps = 20
    local function auxTick(name)
      step = step + 1
      self:report(step / totalSteps, "Game Data: " .. name, step, totalSteps)
    end

    if needRegion then
      out.regionMap = RegionMapExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    end
    auxTick("Town Map")

    if needSections then
      MapSectionsExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
      local rel = GBA_ROOT .. "/region_map/map_sections.lua"
      local body = cache:read(rel)
      if type(body) ~= "string" or #body < 1024 then
        error("map_sections extract wrote " .. tostring(body and #body or 0)
          .. " bytes to " .. rel)
      end
      out.mapSections = #body
    end
    auxTick("Map Sections")

    if needChoices then
      out.multichoice = MultichoiceExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    end
    auxTick("Dialog Menus")

    if needHeal then
      local okHl, detailHl = HealLocationsExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
      if not okHl then print("[heal_locations] warn: " .. tostring(detailHl)) end
      out.healLocations = detailHl
    end
    auxTick("Heal Locations")

    if needDoors then
      local okDr, detailDr = pcall(DoorAnimExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okDr then print("[door_extract] warn: " .. tostring(detailDr)) end
      out.doors = okDr and detailDr or false
    end
    auxTick("Door Animations")

    if needSlots then
      local okSl, detailSl = pcall(SlotMachineExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okSl then print("[slot_machine_extract] warn: " .. tostring(detailSl)) end
      out.slotMachine = okSl and detailSl or false
    end
    auxTick("Slot Machines")

    if needTrade then
      local okTr, detailTr = pcall(TradeExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okTr then print("[trade_extract] warn: " .. tostring(detailTr)) end
      out.trade = okTr and detailTr or false
    end
    auxTick("Link Trade")

    if needLinkArt then
      local okLk, detailLk = pcall(LinkArtExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okLk then print("[link_art_extract] warn: " .. tostring(detailLk)) end
      out.linkArt = okLk and detailLk or false
    end
    auxTick("Wireless Union")

    if needFame then
      local okFc, detailFc = pcall(FameCheckerExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okFc then print("[fame_checker_extract] warn: " .. tostring(detailFc)) end
      out.fameChecker = okFc and detailFc or false
    end
    auxTick("Fame Checker")

    if needTeachy then
      local okTv, detailTv = pcall(TeachyTvExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okTv then print("[teachy_tv_extract] warn: " .. tostring(detailTv)) end
      out.teachyTv = okTv and detailTv or false
    end
    auxTick("Teachy TV")

    if needGift then
      local okMg, detailMg = pcall(MysteryGiftExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okMg then print("[mystery_gift_extract] warn: " .. tostring(detailMg)) end
      out.mysteryGift = okMg and detailMg or false
    end
    auxTick("Mystery Gift")

    if needTower then
      local okTt, detailTt = pcall(TrainerTowerExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okTt then print("[trainer_tower_extract] warn: " .. tostring(detailTt)) end
      out.trainerTower = okTt and detailTt or false
    end
    auxTick("Trainer Tower")

    if needTutor then
      local okTu, detailTu = pcall(TutorExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okTu then print("[tutor_extract] warn: " .. tostring(detailTu)) end
      out.tutor = okTu and detailTu or false
    end
    auxTick("Move Tutors")

    if needMuseum then
      local okMu, detailMu = pcall(MuseumExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okMu then print("[museum_extract] warn: " .. tostring(detailMu)) end
      out.museum = okMu and detailMu or false
    end
    auxTick("Museum Exhibits")

    if needRelearner then
      local okMr, detailMr = pcall(MoveRelearnerExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okMr then print("[move_relearner_extract] warn: " .. tostring(detailMr)) end
      out.moveRelearner = okMr and detailMr or false
    end
    auxTick("Move Relearner")

    if needEgg then
      local okEg, detailEg = pcall(EggExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not okEg then print("[egg_extract] warn: " .. tostring(detailEg)) end
      out.egg = okEg and detailEg or false
    end
    auxTick("Egg & Hatching")

    if needAnims then
      local okAn, detailAn = pcall(BattleAnimExtract.run, rom, cache, { cacheRoot = GBA_ROOT, force = false })
      if not okAn then print("[battle_anim_extract] warn: " .. tostring(detailAn)) end
      out.battleAnims = okAn and detailAn or false
    end
    auxTick("Battle Animations")

    if needAi then
      out.battleAi = BattleAiExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    end
    auxTick("Battle AI Scripts")

    if needPreview then
      local mpOk, mpErr = pcall(MapPreviewExtract.run, rom, cache, { cacheRoot = GBA_ROOT })
      if not mpOk then print("[map_preview] warn: " .. tostring(mpErr)) end
      out.mapPreview = mpOk and mpErr or false
    end
    auxTick("Location Previews")

    if needCredits then
      out.credits = CreditsExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    end
    auxTick("Staff Credits")

    if needLeague then
      out.league = LeagueExtract.run(rom, cache, { cacheRoot = GBA_ROOT })
    end
    auxTick("League Lighting & Diploma")

    return out
  end)

  rom:clearCache()
  Extract.CACHE_ROOT = prevRoot
  if not ok then return false, detail end
  return true, detail
end

function RomExtractorGen3:runIntroAudio(sha1)
  self:report(0.05, "Audio & Intro: Initializing", 0, 3)
  local cache = makeCache()
  if cache:exists(GBA_ROOT .. "/intro/meta.json") and cache:exists(GBA_ROOT .. "/audio/meta.json") then
    local im = cache:read(GBA_ROOT .. "/intro/meta.json")
    if im and not im:find('"stub"%s*:%s*true') then
      self:report(1.00, "Audio Streams Ready", 3, 3)
      return true, true
    end
  end

  local RevisionView = require("src.import.gba.revision_view")
  local imports = self:sharedImports(sha1)
  local version = importVersion(sha1)
  local info = imports:info(version)
  local romShim = { data = RevisionView.forImports(imports, version, info) or self.romData }
  local Intro = require("src.import.gba.extract_intro")
  local Naming = require("src.import.gba.extract_naming")
  local AudioExt = require("src.import.gba.extract_audio")

  self:report(0.20, "Intro: Cutscene Sequence", 1, 3)
  local okI, metaI = Intro.run(romShim, cache, { sha1 = sha1, root = GBA_ROOT .. "/intro" })

  self:report(0.50, "Intro: Naming Screen Graphics", 2, 3)
  local okN = Naming.run(romShim, cache, { sha1 = sha1, root = GBA_ROOT .. "/naming" })

  self:report(0.75, "Audio: Music & Sound Streams", 3, 3)
  local okA, metaA = AudioExt.run(romShim, cache, { sha1 = sha1, root = GBA_ROOT .. "/audio" })

  writeJson(GBA_ROOT .. "/intro/extract_status.json", { ok = okI == true })
  writeJson(GBA_ROOT .. "/naming/extract_status.json", { ok = okN == true })
  writeJson(GBA_ROOT .. "/audio/extract_status.json", { ok = okA == true })
  self:report(1.00, "Audio & Intro Ready", 3, 3)
  return okI, okA, metaI, metaA
end

function RomExtractorGen3:runParallel(sha1)
  if os.getenv("POKEPORT_NO_THREAD") == "1" then
    return false, "POKEPORT_NO_THREAD set"
  end
  if not (love and love.thread and love.thread.newThread and love.timer) then
    return false, "love.thread unavailable"
  end

  local ch_name = "gba_extract_" .. tostring(love.timer.getTime()):gsub("%.", "") .. "_" .. tostring(math.random(10000, 99999))
  local ch = love.thread.getChannel(ch_name)

  local tasks = { "gba", "scripts_ow", "pokemon", "pokemon_gfx", "aux", "intro_audio" }
  local prefix = CacheFs.prefix or ""

  local workerCode = nil
  if love and love.filesystem and love.filesystem.read then
    workerCode = love.filesystem.read("src/import/gba/extract_worker.lua")
  end

  for _, t in ipairs(tasks) do
    local okTh, th = pcall(love.thread.newThread, workerCode or "src/import/gba/extract_worker.lua")
    if not okTh or not th then
      return false, "failed to spawn thread for " .. t .. ": " .. tostring(th)
    end
    th:start(t, prefix, self.romData, sha1, ch_name)
  end

  local done_count = 0
  local errors = {}
  local task_progress = { gba = 0, scripts_ow = 0, pokemon = 0, pokemon_gfx = 0, aux = 0, intro_audio = 0 }
  local weights = { gba = 0.20, scripts_ow = 0.20, pokemon = 0.20, pokemon_gfx = 0.15, aux = 0.15, intro_audio = 0.10 }

  while done_count < #tasks do
    local msg = ch:pop()
    if msg then
      if msg.type == "progress" then
        task_progress[msg.task] = math.max(task_progress[msg.task] or 0, math.min(1.0, msg.fraction or 0))
        local total_pct = 0.03
        for k, w in pairs(weights) do
          total_pct = total_pct + (task_progress[k] or 0) * w * 0.95
        end
        self:report(total_pct, msg.stage or "Extracting", msg.current or 0, msg.stageTotal or 1)
      elseif msg.type == "done" then
        done_count = done_count + 1
        task_progress[msg.task] = 1.0
        local total_pct = 0.03
        for k, w in pairs(weights) do
          total_pct = total_pct + (task_progress[k] or 0) * w * 0.95
        end
        self:report(total_pct, "Finalizing " .. tostring(msg.task), done_count, #tasks)
        if not msg.ok then
          errors[#errors + 1] = msg.task .. ": " .. tostring(msg.error)
        end
      end
    else
      love.timer.sleep(0.005)
    end
  end

  if #errors > 0 then
    return false, "Parallel extraction error:\n" .. table.concat(errors, "\n")
  end

  if not CacheFs.exists(GBA_ROOT .. "/maps.json") then
    writeJson(GBA_ROOT .. "/maps.json", { maps = {}, from_extract = true })
  end

  return true
end

function RomExtractorGen3:run()
  local sha1 = self:ensureSha1()

  self:report(0.01, "Initializing Markers", 0, 1)
  self:writeRequiredMarkers(sha1)
  self:report(0.03, "Markers Ready", 1, 1)

  local okPar, parRes, parErr = pcall(function()
    return self:runParallel(sha1)
  end)
  if okPar and parRes then
    writeJson(GBA_ROOT .. "/pokemon/extract_status.json", { ok = true, error = nil })
    writeJson(GBA_ROOT .. "/region_map/extract_status.json", { ok = true, error = nil })
    self:report(1.00, "Ready", 1, 1)
    collectgarbage("collect")
    return {
      romSha1 = sha1,
      extractOk = true,
      pokemonOk = true,
      auxOk = true,
    }
  end

  print("[RomExtractorGen3] Parallel extraction fell back to sequential: " .. tostring(parErr or parRes))

  -- Fallback sequential execution path
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
  collectgarbage("collect")

  local okPoke, pokeDetail = self:runPokemonExtract(sha1)
  writeJson(GBA_ROOT .. "/pokemon/extract_status.json", {
    ok = okPoke == true,
    error = (not okPoke) and tostring(pokeDetail) or nil,
  })
  if not okPoke then
    error("Pokemon extract failed: " .. tostring(pokeDetail))
  end
  self:report(0.88, "Game Data & Chrome Ready", 1, 1)
  collectgarbage("collect")

  local okAux, auxDetail = self:runAuxExtracts(sha1)
  writeJson(GBA_ROOT .. "/region_map/extract_status.json", {
    ok = okAux == true,
    error = (not okAux) and tostring(auxDetail) or nil,
  })
  if not okAux then
    error("Region map / script table extract failed: " .. tostring(auxDetail))
  end
  collectgarbage("collect")

  self:runIntroAudio(sha1)
  self:report(0.98, "Finalizing Cache", 1, 1)
  collectgarbage("collect")

  self:report(1.00, "Ready", 1, 1)
  return {
    romSha1 = sha1,
    extractOk = ok == true,
    pokemonOk = okPoke == true,
    auxOk = okAux == true,
    detail = detail,
  }
end

return RomExtractorGen3
