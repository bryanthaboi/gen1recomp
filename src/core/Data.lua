-- Loads generated data from either the private first-boot cache or the
-- optional source-tree developer build.

local Logger = require("src.core.Logger")

local Data = {}

local MODULES = {
  "constants", "maps", "tilesets", "text", "text_pointers",
  "trainer_headers", "font", "sprites", "pokemon", "moves", "items",
  "type_chart", "trainers", "encounters", "field", "battle_anims",
}

-- Optional for compatibility with developer and stale caches.
local OPTIONAL = { "audio", "palettes", "icons" }

-- Vanilla defaults for rules exposed through the constants registry.  A
-- value has to exist before a mod can patch it; each one matches the
-- engine's no-mod behavior, so seeding them changes nothing on a vanilla
-- boot.
local CONSTANT_DEFAULTS = {
  bagSize = 20,                 -- BAG_ITEM_CAPACITY (Bag.capacity fallback)
  partyMax = 6,                 -- PARTY_LENGTH (src/pokemon/Party.lua)
  boxCount = 12, boxSize = 20,  -- Bill's PC (src/pokemon/Boxes.lua)
  moveMax = 4,
  levelCap = 100,
  coinCap = 9999,               -- MAX_COINS (src/ui/SlotMachine.lua)
  -- move-slot repair when a scrub empties a mon (src/core/SaveData.lua);
  -- a total conversion without TACKLE patches this to its own floor
  fallbackMove = "TACKLE",
  hmMoves = { "CUT", "FLY", "SURF", "STRENGTH", "FLASH" }, -- IsMoveHM
  -- gym order (data/scripts/victories.lua); list position is the badge
  -- number the trainer card draws
  badges = {
    { id = "BOULDERBADGE" }, { id = "CASCADEBADGE" }, { id = "THUNDERBADGE" },
    { id = "RAINBOWBADGE" }, { id = "SOULBADGE" },    { id = "MARSHBADGE" },
    { id = "VOLCANOBADGE" }, { id = "EARTHBADGE" },
  },
}

-- data/events/trades.asm in Pokemon Yellow has its own TradeMons table.
-- Old Yellow imports were built from the Red manifest, so correct that
-- table after loading as well as in the fixed import manifest below.
local YELLOW_TRADES = {
  { give = "LICKITUNG", get = "DUGTRIO", dialogset = 1, nickname = "GURIO" },
  { give = "CLEFAIRY", get = "MR_MIME", dialogset = 1, nickname = "MILES" },
  { give = "BUTTERFREE", get = "BEEDRILL", dialogset = 3, nickname = "STINGER" },
  { give = "KANGASKHAN", get = "MUK", dialogset = 1, nickname = "STICKY" },
  { give = "MEW", get = "MEW", dialogset = 3, nickname = "BART" },
  { give = "TANGELA", get = "PARASECT", dialogset = 1, nickname = "SPIKE" },
  { give = "PIDGEOT", get = "PIDGEOT", dialogset = 2, nickname = "MARTY" },
  { give = "GOLDUCK", get = "RHYDON", dialogset = 2, nickname = "BUFFY" },
  { give = "GROWLITHE", get = "DEWGONG", dialogset = 3, nickname = "CEZANNE" },
  { give = "CUBONE", get = "MACHOKE", dialogset = 3, nickname = "RICKY" },
}

-- field.boot is the total-conversion override point for the new game; the
-- values match what SaveData.newGame and the Oak speech used to inline.
local BOOT_DEFAULTS = {
  -- special_warps.asm NewGameWarp: REDS_HOUSE_2F, 3, 6 -- the bedroom, not
  -- the tile outside the house. lastHeal is deliberately absent: SaveData
  -- derives the vanilla blackout point, and seeding it here would leak into
  -- total conversions that patch the spawn without naming a heal point.
  startMap = "REDS_HOUSE_2F", startX = 3, startY = 6, startFacing = "down",
  playerName = "RED", rivalName = "BLUE",
  startMoney = 3000,
  screens = { splash = "IntroMovie", title = "TitleState", newGame = "OakSpeech" },
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

function Data:applyVersionedFieldData()
  if require("src.core.GameVersion").isYellow() then
    self.field.trades = copy(YELLOW_TRADES)
    -- The old man's catch demo is a RATTATA in Yellow
    -- (scripts/ViridianCity.asm ViridianCityOldManStartCatchTrainingScript
    -- .SetupBattle: ld a, RATTATA / ld [wCurOpponent], a) but the Yellow
    -- manifest inherited Red's WEEDLE field.oldManBattle (#617), so old
    -- Yellow caches carry the wrong demo species too.  The fixed import
    -- manifest below stamps RATTATA for fresh imports.
    self.field.oldManBattle = { species = "RATTATA", level = 5 }
    -- The Oak-speech show-off mon is the player's Pikachu in Yellow
    -- (engine/battle/core.asm BATTLE_TYPE_PIKACHU / the ProfOak demo)
    -- but caches imported before the manifest carried demoSpecies fell
    -- back to Red's NIDORINO (#915).  The fixed import manifest below
    -- stamps PIKACHU for fresh imports; fill it here for stale caches.
    local oakSpeech = self.field.oakSpeech
    if type(oakSpeech) == "table" and not oakSpeech.demoSpecies then
      oakSpeech.demoSpecies = "PIKACHU"
    end
  end
end

-- Fills only what the cache is missing, so an importer that learns to
-- stamp one of these keys silently takes over from the engine.
function Data:seedDefaults()
  local constants = self.constants
  for key, value in pairs(CONSTANT_DEFAULTS) do
    if constants[key] == nil then constants[key] = copy(value) end
  end
  -- derived, not literal: a dataset with a different roster gets the right
  -- upper bound without 151 being written down anywhere
  if constants.dexSize == nil then
    local highest = 0
    for _, def in pairs(self.pokemon) do
      if def.dex and def.dex > highest then highest = def.dex end
    end
    constants.dexSize = highest
  end
  if constants.dexDigits == nil then
    constants.dexDigits = math.max(3, #tostring(constants.dexSize))
  end
  self:applyVersionedFieldData()
  local boot = self.field.boot
  if boot == nil then
    boot = {}
    self.field.boot = boot
  end
  for key, value in pairs(BOOT_DEFAULTS) do
    if boot[key] == nil then boot[key] = copy(value) end
  end
  -- Yellow boots its own attract movie (engine/movie/intro_yellow.asm);
  -- only the un-overridden default flips, so a total conversion that set
  -- field.boot.screens.splash keeps its choice on any version.
  if boot.screens.splash == BOOT_DEFAULTS.screens.splash
     and require("src.core.GameVersion").isYellow() then
    boot.screens.splash = "YellowIntro"
  end
  -- the naming screen presets the importer already extracts but nothing
  -- ever read (field.presetNames)
  if boot.namePresets == nil then
    local presets = self.field.presetNames or {}
    boot.namePresets = {
      player = copy(presets.player) or { "RED", "ASH", "JACK" },
      rival = copy(presets.rival) or { "BLUE", "GARY", "JOHN" },
    }
  end
  -- the overworld's Kanto literals, same fill-if-absent contract; required
  -- here rather than at the top so core keeps out of src/world at load time
  require("src.world.FieldDefaults").seed(self)
  -- Cinnabar's quiz trainers are text_asm (no def_trainers), so the
  -- extractor never writes headers for them.  Seed the EVENT_BEAT_* /
  -- after-battle rows so Blaine's SetEventRange deactivation and talk
  -- after-text work like the other gyms (scripts/CinnabarGym.asm).
  self:seedCinnabarGymTrainerHeaders()
  -- #197: the Fighting Dojo Karate Master is text_asm, so the extractor
  -- writes no header for him -- seed one so he engages on sight and has
  -- his defeat / re-talk lines (same idea as the Cinnabar seed above).
  self:seedFightingDojoKarateMaster()
  -- #189: 1F cabin door order vs rooms map (survey zoom)
  require("src.world.SsAnneLayout").apply(self.maps)
end

-- The Karate Master (FightingDojo.asm) is a text_asm object: his object has
-- no def_trainers row (DisplayTextID routes to his ASM script), so the
-- extractor emits headers only for the four blackbelts ([2]..[5]).  Seed
-- object index [1] so he behaves like the real leader:
--   * range 0: FightingDojoDefaultScript, not trainer sight, starts his
--     battle from the single tile to his left (#495),
--   * battle = his pre-battle challenge, won = "Hwa! Arrgh! Beaten!",
--   * after = the "Stay and train at Karate with us!" re-talk line.
-- Deliberately NO `event`: EVENT_BEAT_KARATE_MASTER is owned by
-- victories.lua (OPP_BLACKBELT#1) exactly like the gym leaders, and
-- engageTrainer sets header.event *before* checkVictoryRewards runs -- if
-- this header also set it, the reward's flag guard would early-return and
-- swallow the prize dialogue.  trainerDefeated tracks him via
-- defeatedTrainers[npc.id] like the leaders.
function Data:seedFightingDojoKarateMaster()
  local headers = self.trainer_headers
  if not headers then return end
  headers.FightingDojo = headers.FightingDojo or {}
  if headers.FightingDojo[1] then return end
  headers.FightingDojo[1] = {
    range = 0,
    battle = "_FightingDojoKarateMasterText",
    won = "_FightingDojoKarateMasterDefeatedText",
    after = "_FightingDojoKarateMasterStayAndTrainWithUsText",
  }
end

function Data:seedCinnabarGymTrainerHeaders()
  local headers = self.trainer_headers
  if not headers or headers.CinnabarGym then return end
  local gym = {}
  for i = 0, 6 do
    local n = i + 1
    -- object indices 2..8 are SUPER_NERD1..7; range 0 -- they only
    -- engage via talk / wrong quiz answer, never sight lines
    gym[i + 2] = {
      event = "EVENT_BEAT_CINNABAR_GYM_TRAINER_" .. i,
      range = 0,
      battle = "_CinnabarGymSuperNerd" .. n .. "BattleText",
      won = "_CinnabarGymSuperNerd" .. n .. "EndBattleText",
      after = "_CinnabarGymSuperNerd" .. n .. "AfterBattleText",
    }
  end
  headers.CinnabarGym = gym
end

-- POKEPORT_DATA_DIR points a test runner at another dataset root (the
-- ROM-free fixture set, tests/fixture_data); unset -- every shipped build
-- -- the generated modules load exactly as before.  loadfile skips the
-- require cache, so each overridden load hands back fresh tables.
local function loadModule(dir, name)
  if dir then
    local chunk, err = loadfile(dir .. "/" .. name .. ".lua")
    if not chunk then return false, err end
    return pcall(chunk)
  end
  local ok, mod = pcall(require, "data.generated." .. name)
  if ok then return true, mod end
  -- Fused PhysFS / Blue|Yellow prefix: load bytes from the active version's
  -- cache explicitly when require cannot see the mounted tree.
  local CacheFs = require("src.import.CacheFs")
  local GameVersion = require("src.core.GameVersion")
  local path = "data/generated/" .. name .. ".lua"
  local bytes = CacheFs.readActive(path)
  if type(bytes) == "string" then
    local chunk, err = loadstring(bytes, "@" .. GameVersion.cachePrefix() .. path)
    if not chunk then return false, err or mod end
    return pcall(chunk)
  end
  return false, mod
end

function Data:load()
  local dir = os.getenv("POKEPORT_DATA_DIR")
  for _, name in ipairs(MODULES) do
    local ok, mod = loadModule(dir, name)
    if not ok then
      if dir then
        error(("missing data module '%s/%s.lua' (POKEPORT_DATA_DIR).\n(%s)")
              :format(dir, name, mod))
      end
      error(("missing generated data module 'data/generated/%s.lua'.\n" ..
             "Import the ROM again or rebuild developer data.\n(%s)")
            :format(name, mod))
    end
    self[name] = mod
  end
  for _, name in ipairs(OPTIONAL) do
    local ok, mod = loadModule(dir, name)
    self[name] = ok and mod or nil
    if not ok then
      Logger.warn("optional data module '%s' missing (feature disabled)", name)
    end
  end
  -- before the mod loader runs: the deep registries fold over these
  self:seedDefaults()
  -- the top-level keys a pristine load leaves behind, so reloadGenerated can
  -- strip whatever a mod merge added since; kept on self (assigned before the
  -- scan so it counts itself) because tests load other tables through this
  -- method, and a shared upvalue would let them clobber the singleton's set
  local pristine = {}
  self._pristineKeys = pristine
  for key in pairs(self) do pristine[key] = true end
  Logger.info("generated data loaded (%d maps, %d species, %d moves)",
              (function() local n = 0 for _ in pairs(self.maps) do n = n + 1 end return n end)(),
              (function() local n = 0 for _ in pairs(self.pokemon) do n = n + 1 end return n end)(),
              (function() local n = 0 for _ in pairs(self.moves) do n = n + 1 end return n end)())
end

-- Drop every namespace the mod merge created and evict the generated modules
-- from package.loaded, so the next load() re-reads them off disk instead of
-- handing back the cached tables.  Two callers:
--   * reloadGenerated below (dev hot reload)
--   * main.lua, when the launcher closes the save editor -- the editor may
--     have loaded the OTHER game's cache, and require would otherwise serve
--     those modules to a subsequent Play (see CacheFs.unmountVersion, which
--     clears the matching read-path overlay).
function Data:unloadGenerated()
  local pristine = self._pristineKeys
  if pristine then
    for key in pairs(self) do
      if not pristine[key] then self[key] = nil end
    end
  end
  self._pristineKeys = nil
  for _, name in ipairs(MODULES) do
    package.loaded["data.generated." .. name] = nil
    self[name] = nil
  end
  for _, name in ipairs(OPTIONAL) do
    package.loaded["data.generated." .. name] = nil
    self[name] = nil
  end
end

-- dev-mode hot reload only (src/dev/HotReload.lua): drop every namespace the
-- mod merge created, then re-require the generated modules so base records
-- return to their on-disk values even where a mod edited them in place
function Data:reloadGenerated()
  self:unloadGenerated()
  self:load()
end

-- Resolve a dotted target path, creating empty tables on the way.  Only the
-- mod merge calls this; a vanilla boot never does, so an unmodded Data
-- table is byte-identical to a pre-registry-v2 one.
function Data.ensure(data, path)
  local node = data
  for key in path:gmatch("[^%.]+") do
    if node[key] == nil then node[key] = {} end
    node = node[key]
  end
  return node
end

-- Resolve a TEXT_* constant on a map to a plain string (or nil if the text
-- needs a hand-ported script; see data/scripts/).
function Data:resolveText(mapLabel, textConst)
  local entry = self:textEntry(mapLabel, textConst)
  if not entry then return nil end
  if entry.text then
    local s = self.text[entry.text]
    if s then return s, entry.asm end
  end
  -- A text_asm entry names its wrapper label but carries no string, because
  -- the extractor cannot follow asm.  A handful of those wrappers are plain
  -- `text_far <label> / text_end` pairs with no logic at all -- BoulderText
  -- (home/overworld_text.asm:16), MartSignText, PokeCenterSignText -- and
  -- for those the extracted _Label string IS the whole behavior, so the
  -- boulders and signs printed nothing at all (#318).  Wrappers that really
  -- do run logic have no _Label string to find, so they still fall through
  -- to their hand-ported script in data/scripts/.
  -- needsAsm comes back false here on purpose: showMapText's warning tells
  -- the reader to go port a script, and for these there is nothing to port.
  if entry.label then
    local s = self.text["_" .. entry.label]
    if s then return s, false end
  end
  return nil, entry.asm
end

-- The raw text-pointer entry (carries mart/nurse/pc markers and the label).
function Data:textEntry(mapLabel, textConst)
  local perMap = self.text_pointers[mapLabel]
  return perMap and perMap[textConst] or nil
end

-- Trainer sight/dialogue header for a map object (or nil).
function Data:trainerHeader(mapLabel, objIndex)
  local perMap = self.trainer_headers[mapLabel]
  return perMap and perMap[objIndex] or nil
end

return Data
