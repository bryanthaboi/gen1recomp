-- Gen 2 save file.
--
-- Deliberately separate from src/core/SaveData.lua rather than a branch inside
-- it: that module's shape is Gen 1's SRAM (Kanto badges, 12 boxes of 20,
-- pikachu happiness, the Gen 1 party struct with one `special` stat), and its
-- validate/migration chain asserts against that shape.  A Gold save has a
-- different party struct (SpA/SpD, held item, happiness, pokerus), different
-- boxes, a phone book, a Pokedex with two orderings, and an RTC.
--
-- What IS shared, on purpose:
--   * SaveSerializer, so both generations' files are the same Lua-table format
--     and the standalone save editor can read either
--   * the save-file naming convention (GameVersion.saveSuffix -> save_gold.lua
--     plus .bak / .tmp), so Gold sits beside Red/Blue/Yellow without touching
--     them, and the same atomic write dance protects it
--   * options.lua, which is version-independent and survives New Game
--
-- Layout notes taken from the cart: a New Game starts at SPAWN_HOME
-- (PLAYERS_HOUSE_2F 3,3 -- engine/menus/intro_menu.asm NewGame), the money cap
-- is 999999, and playtime is kept as h/m/s/frames the way wGameTime* is.

local GameVersion = require("src.core.GameVersion")
local HallOfFame = require("src.core.gen2.HallOfFame")
local Mail = require("src.core.gen2.Mail")
local MomShopping = require("src.core.gen2.MomShopping")
local Logger = require("src.core.Logger")
-- The mod hook bus.  Same module the Gen 1 save reaches for
-- (src/core/SaveData.lua), because the hook NAMES are shared across
-- generations: a mod that wraps save.new_game reshapes either game's skeleton
-- without knowing which one it is running under.  Null objects until a loader
-- installs the live buses, so a mod-free boot and every headless test pay
-- nothing for the call.
local Runtime = require("src.mods.Runtime")
local SaveSerializer = require("src.core.SaveSerializer")

local function rand(a, b)
  if love and love.math and love.math.random then
    return love.math.random(a, b)
  end
  return math.random(a, b)
end

local Save = {}

-- Bumped whenever a field's meaning changes; migrations key off it.
--
--   1 -> 2  the Hall of Fame roster (sHallOfFame + wHallOfFameCount) and
--           wSpawnAfterChampion.  A format-1 save predates the endgame, so it
--           has neither and the migration is the empty roster.
--   2 -> 3  scriptMem, the script VM's sparse WRAM store.  A format-2 save
--           kept those bytes per-session, so the migration is the empty table:
--           every address reads back as 0, which is what the cart's own
--           zero-filled WRAM gives a save that never touched one.
--   3 -> 4  mail: sPartyMail (six `mailmsg` structs keyed by PARTY SLOT) and
--           sMailboxes + sMailboxCount (the PC's MAILBOX).  A format-3 save
--           has neither and cannot have a letter anywhere, so the upgrade is
--           the empty pair -- and a mon in one of those saves carrying a MAIL
--           item is exactly the case Mail.sendToPc's blank-struct fallback
--           covers.
--   4 -> 5  `events` (wEventFlags) and `mapScenes` (the w<Map>SceneID block)
--           became LOAD BEARING.  Both fields existed in format 4 and both
--           were written on every save, but nothing ever read them back --
--           World:loadPlayerData is what does now -- so a format-4 file's
--           copies had never been validated by anything.  The migration is
--           the pair of tables; Save.validate is what scrubs them from here
--           on, the same way it always has for scriptMem.
--   5 -> 6  `playerState` (wPlayerState), which sits in the same sPlayerData
--           block the two fields above do and had never been written at all:
--           a format-5 save made on the BICYCLE or aboard a Lapras came back
--           on foot.  There is nothing to carry across, so the upgrade is
--           PLAYER_NORMAL -- the cart's own zero byte, and what those files
--           have effectively been loading as all along.
--   6 -> 7  `mom.whichItem` (wWhichMomItem) and `mom.triggerBalance`
--           (wMomItemTriggerBalance), the two bytes MomTriesToBuySomething
--           walks (src/core/gen2/MomShopping.lua).  NewGame seeds them in
--           engine/menus/intro_menu.asm, so a file made before Mom could
--           spend anything upgrades to exactly those seeds: the ladder on its
--           first rung and the consolation threshold at MOM_MONEY.  A save
--           that already has savings banked therefore starts buying from the
--           bottom of the list, which is what a cartridge whose owner had
--           saved that much would also do.
--   7 -> 8  Crystal caught data: a mon carrying a caught level but no landmark
--           is zeroed, so the Seer takes ReadCaughtData's `.error` arm
--           (../pokecrystal/engine/events/poke_seer.asm:103-104) instead of
--           GetCaughtLocation's "Unknown".  #1929
Save.FORMAT = 8

Save.MAX_MONEY = 999999
Save.MAX_COINS = 9999
-- constants/pokemon_data_constants.asm: 6 party slots, 14 boxes of 20.
Save.PARTY_SIZE = 6
Save.NUM_BOXES = 14
Save.MONS_PER_BOX = 20
-- wEventFlags is `flag_array NUM_EVENTS` (ram/wram.asm) and NUM_EVENTS is
-- $800, so the bitfield is 256 bytes and a byte index past the last one cannot
-- have come from the cart.
Save.EVENT_BYTES = 256
-- wPlayerState (constants/ram_constants.asm), kept by NAME rather than as the
-- raw byte so a save that round-trips one stays readable.  These are the four
-- strings src/world/gen2/FieldMoves.lua names the states by, and this is the
-- set World:loadPlayerData tests a restored value against as well, so the two
-- ends of the round trip cannot drift apart.  PLAYER_SKATE has no entry for
-- the same reason FieldMoves has no name for it: nothing in Gold writes it.
Save.PLAYER_NORMAL = "normal"
Save.PLAYER_STATES = {
  normal = true, bike = true, surf = true, surf_pika = true,
}

local function saveNames(version)
  version = version or GameVersion.get()
  -- Resolve the ACTIVE SLOT the same way SaveData does, and only fall back to
  -- the flat save_<version>.lua when no slot is registered.
  --
  -- The launcher's slot system (src/core/SaveData.lua) migrates a flat
  -- save_gold.lua into saves/<version>/<slot>.lua the first time it lists the
  -- version's slots -- and DELETES the flat file.  This module read the flat
  -- name unconditionally, so after that migration the Gold title screen found
  -- no save and dropped CONTINUE (and a following SAVE wrote a second copy to
  -- the flat path the launcher no longer looks at).  Reading through the same
  -- slot resolution keeps the in-game load/save and the launcher on one file.
  --
  -- Resolve the SCOPE the same way as well.  A cart's saves are keyed by cart
  -- id rather than by version: SaveData resolves every path through
  -- `activeScopeKey`, which answers `cart_<id>` while one is active, and the
  -- launcher lists, creates and selects a cart's slots from the `cartSlots`
  -- registry (RomImporter._refreshSlots / _selectSlot / _newSlot).  This
  -- module asked in the version's name alone, so a Gen 2 cart read and wrote
  -- the BASE GAME's playthrough.  Gen 1 was unaffected because it saves
  -- through SaveData, which is already cart-scoped.
  local ok, SaveData = pcall(require, "src.core.SaveData")
  SaveData = ok and SaveData or nil
  local cart = SaveData and SaveData.getCart and SaveData.getCart() or nil
  if type(cart) ~= "string" or cart == "" then cart = nil end
  local slot
  if cart then
    slot = SaveData.activeCartSlot and SaveData.activeCartSlot(cart) or nil
  elseif SaveData then
    slot = SaveData.activeSlot and SaveData.activeSlot(version) or nil
  end
  if slot then
    local scope = cart and ("cart_" .. cart) or version
    local main = "saves/" .. scope .. "/" .. slot .. ".lua"
    return main, main .. ".bak", main .. ".tmp"
  end
  -- SaveData.legacyNames names a cart "save_cart_<id>.lua" and a version by
  -- its own suffix; this is that, so the two ends agree before slots exist.
  local suffix = cart and ("_cart_" .. cart) or GameVersion.saveSuffix(version)
  local main = "save" .. suffix .. ".lua"
  return main, main .. ".bak", main .. ".tmp"
end

Save.filenames = saveNames

local function fs()
  -- portable.txt: same standard/portable root as Gen 1 (SaveData.persistenceFs).
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if ok and SaveData.persistenceFs then return SaveData.persistenceFs() end
  return love.filesystem
end

-- The first PlayerNameArray row -- pokegold data/player_names.asm:12-22, and
-- Crystal's gender-split arrays at data/player_names.asm:12-16, :31-35.
Save.DEFAULT_PLAYER_NAMES = {
  gold = "GOLD",
  silver = "SILVER",
  crystal = "CHRIS",
}

-- FemalePlayerNameArray's first row, the `.Kris` dname NamePlayer falls back to
-- (data/player_names.asm:31-32, engine/menus/intro_menu.asm:768-781).
Save.DEFAULT_PLAYER_NAMES_FEMALE = {
  crystal = "KRIS",
}

-- wPlayerGender as this save spells it (constants/ram_constants.asm:176-177).
function Save.isFemale(save)
  local player = type(save) == "table" and save.player
  return (player and player.gender) == "female"
end

function Save.defaultPlayerName(version, gender)
  version = version or GameVersion.get()
  if gender == "female" then
    local female = Save.DEFAULT_PLAYER_NAMES_FEMALE[version]
    if female then return female end
  end
  return Save.DEFAULT_PLAYER_NAMES[version] or "GOLD"
end

-- A fresh Gen 2 save.  `opts` carries what the intro collected: player name,
-- rival name, and the options the OPTION screen was left on.
function Save.newGame(opts)
  opts = opts or {}
  local save = {
    format = Save.FORMAT,
    version = GameVersion.get(),
    generation = 2,
    player = {
      name = opts.playerName
        or Save.defaultPlayerName(nil, opts.gender or "male"),
      -- _ResetWRAM rolls wPlayerID out of hRandomSub/hRandomAdd
      -- (engine/menus/intro_menu.asm:41-49).
      id = opts.trainerId or rand(0, 65535),
      -- InitCrystalData zeroes wPlayerGender before InitGender is even offered
      -- (engine/menus/init_gender.asm:1-6).
      gender = opts.gender or "male",
      money = 3000,
      coins = 0,
      badges = {},
      kantoBadges = {},
    },
    -- NewGame seeds wRivalName with "???", not with SILVER: _ResetWRAM calls
    -- InitializeNPCNames (engine/menus/intro_menu.asm:131, :193-214), whose
    -- .Rival row is literally `db "???@"`.  SILVER is NameRival's InitName
    -- FALLBACK (engine/events/specials.asm:80-91), copied in only after the
    -- naming screen has closed on a blank entry, so the rival is "???" for
    -- every {RIVAL} line and every RIVAL1 battle before the officer scene --
    -- the Cherrygrove fight included.
    rival = { name = opts.rivalName or "???" },
    -- wMomSavingMoney's two bits BankOfMom actually flips (MOM_ACTIVE_F,
    -- MOM_SAVING_SOME_MONEY_F -- src/script/gen2/Specials.lua H.BankOfMom):
    -- `active` is "the bank conversation has happened at least once", which
    -- gates whether a later visit opens on InitializeBank or on
    -- IsThisAboutYourMoney; `savingMoney` is only meaningful once active.
    --
    -- `whichItem` and `triggerBalance` are wWhichMomItem and
    -- wMomItemTriggerBalance, both written by NewGame itself
    -- (engine/menus/intro_menu.asm): the MomItems_2 ladder starts on its
    -- first rung and the consolation threshold starts at MOM_MONEY.
    mom = { name = opts.momName or "MOM", active = false, savingMoney = false,
      savedMoney = 0, whichItem = 0,
      triggerBalance = MomShopping.MOM_MONEY },
    -- Where the world resumes.  nil means "use SPAWN_HOME".
    position = nil,
    -- Last Pokecenter, for a whiteout warp.
    spawn = "SPAWN_HOME",
    -- wPlayerState.  A New Game starts on foot; the BICYCLE and SURF are what
    -- write it, and it rides the save because the sprite, the step duration
    -- and the tiles a step may land on all follow from it
    -- (World:loadPlayerData).
    playerState = Save.PLAYER_NORMAL,
    -- sHallOfFame + wHallOfFameCount: `count` is how many times the champion
    -- has been beaten (capped at HOF_MASTER_COUNT) and `teams` is the roster,
    -- newest first, NUM_HOF_TEAMS deep.  src/core/gen2/HallOfFame.lua owns
    -- every read and write of it.
    hallOfFame = { count = 0, teams = {} },
    -- wSpawnAfterChampion, a one-shot: set by the induction, consumed by the
    -- next CONTINUE (HallOfFame.consumePostGameSpawn).  nil means "resume
    -- where the save says", which is every ordinary load.
    spawnAfterChampion = nil,
    party = {},
    boxes = {},
    currentBox = 1,
    boxNames = {},
    inventory = {},
    -- Gen 2 splits the bag into four pockets (ITEM / KEY_ITEM / BALL / TM_HM);
    -- `inventory` stays the flat id->count map Gen 1's Bag uses, and PackMenu
    -- buckets it by each item's extracted `pocket`.
    --
    -- wWhichRegisteredItem/wRegisteredItem (engine/overworld/select_menu.asm):
    -- the item the SELECT button dispatches, set from the PACK
    -- (World:registerItem) and re-validated against the live inventory on
    -- every SELECT press (World:registeredItemId).  nil means nothing is
    -- registered, the same as the cart's byte being 0.
    registeredItem = nil,
    -- MAIL, both SRAM regions (src/core/gen2/Mail.lua): `party` is sPartyMail
    -- keyed by party slot and `box` is sMailboxes, with sMailboxCount implied
    -- by its length.
    mail = { party = {}, box = {} },
    pcItems = {},
    phoneContacts = {},
    tradeFlags = {},
    pokedex = { seen = {}, caught = {} },
    -- wLastDexMode (engine/pokedex/pokedex.asm:59-61): the sort mode the
    -- #DEX reopens in.  NEW_MODE is the cart's zero byte.
    lastDexMode = "NEW",
    -- wUnownDex: the distinct Unown FORMS caught, in catching order.  A second
    -- record beside the #DEX because the #DEX knows only the species
    -- (src/core/gen2/Unown.lua).
    unownDex = {},
    -- wFirstUnownSeen (ram/wram.asm:2703): the form letter of the FIRST Unown
    -- the player ever met, latched once (engine/battle/core.asm:7894-7902) and
    -- read back by the #DEX entry.  0 means "none yet", the cart's zero byte.
    firstUnownSeen = 0,
    events = {},
    flags = {},
    mapScenes = {},
    -- The script VM's sparse WRAM store (src/script/gen2/Vm.lua `mem`):
    -- address -> byte, for the addresses Script_readmem / Script_writemem
    -- (engine/overworld/scripting.asm) poke that the port has nowhere else to
    -- keep -- wUndergroundSwitchPositions in the Goldenrod underground and
    -- wMooMooBerries at the Route 39 barn.  Sparse on purpose: the cart's WRAM
    -- is 8K and a save has no business carrying a dense image of it, only the
    -- handful of bytes a script actually wrote.
    scriptMem = {},
    playTime = { hours = 0, minutes = 0, seconds = 0, frames = 0 },
    -- RTC bookkeeping: which real day the save last saw, so daily events can
    -- roll over (engine/rtc/rtc.asm StageRTCTimeForSave).
    rtc = { day = tonumber(os.date("%j")) or 1, hour = tonumber(os.date("%H")) or 0,
            minute = tonumber(os.date("%M")) or 0 },
    options = nil, -- lives in options.lua; see SaveData.saveOptions
    createdAt = os.time(),
  }
  -- Same hook, same name, same contract as Gen 1's SaveData.newGame: a total
  -- conversion reshapes the skeleton (spawn, party, money) before anything
  -- reads it.  Unhooked this returns save unchanged, and it is the SAME table
  -- so a caller holding the literal is never left behind.
  return Runtime.call("save.new_game", function(s) return s end, save)
end

-- Gen 2's OPTION screen (engine/menus/options_menu.asm StringOptions).
-- Values are stored as names so a save stays readable and a changed enum
-- ordering cannot silently repoint an option.
Save.DEFAULT_OPTIONS = {
  textSpeed = "MID",        -- FAST / MID / SLOW
  battleScene = true,       -- animations on
  battleStyle = "SHIFT",    -- SHIFT / SET
  sound = "MONO",           -- MONO / STEREO
  print = "NORMAL",         -- LIGHTEST..DARKEST
  menuAccount = true,       -- show the start menu's description box
  frame = 1,                -- textbox frame 1-8
  -- Port options, not the cart's.  These are the same keys the Gen 1 save
  -- uses (src/core/SaveData.lua) and they drive the same shared modules, so
  -- a player's display and speed choices mean the same thing in both games.
  speed = 1,                -- GameSpeed.LEVELS multiplier, logic only
  -- graphics performance tier: auto | high | balanced | low.  "auto" is the
  -- Gen 1 save's own default (src/core/SaveData.lua); same key, same module.
  performance = "auto",
  zoom = 0,                 -- Zoom offset from the window's fit scale
  tilt = 0,                 -- Tilt.LEVELS degrees, 0 = off
  -- COLOR: GbcPalette.MODES.  "gbc" is the cart's own palettes and the
  -- default -- this is a Game Boy Color game, so colour is ON out of the box
  -- and the other two rungs are the deliberate step DOWN to a grey or green
  -- Game Boy.  The Gen 1 save's equivalent key is `colors` (SGB packs), which
  -- means something different, hence the different name.
  color = "gbc",
  palette = "",
  videoMode = "windowed",
  fpsCap = 60,
  battleLayout = "og",
  -- BATTLE SIZE (#1709): fixed | fill
  battleFit = "fixed",
  battleBg = "white",
  -- VOID FILL: fade | water | trees | black.  fade is each map header's own
  -- border block with the dissolve across a boundary (#1418).
  voidFill = "fade",
  uiLetterbox = "auto",
  musicVol = 7,             -- 0-7, like the GB's NR50 master volume
  sfxVol = 7,               -- 0-7
  musicFilter = 0,          -- low-pass steps, 0 = off
  haptics = "light",
  touchControls = { enabled = true },
  screenPos = "center",
}

function Save.defaultOptions()
  local out = {}
  for key, value in pairs(Save.DEFAULT_OPTIONS) do out[key] = value end
  return out
end

-- ------- options.lua
--
-- Gold's options live in the shared options.lua under their own `gold` key,
-- not on the flat path the Gen 1 keys use.  Several names collide across the
-- two generations with DIFFERENT types -- battleStyle is "shift" in Gen 1 and
-- "SHIFT" here, textSpeed a frame delay there and a label here -- so sharing
-- the flat namespace would have each game quietly corrupting the other's
-- settings.  The file itself is shared, which is what lets the launcher's
-- gear edit these before the game starts (src/import/LauncherSettings.lua).
Save.OPTIONS_KEY = "gold"

local SHARED_KEYS = {
  touchControls = true, haptics = true, screenPos = true,
  videoMode = true,
  mods = true, modsByVersion = true, modsGen2 = true,
  modOptions = true, modProfiles = true, modProfilesSeeded = true,
  activeProfile = true,
}

function Save.loadOptions(fs)
  local options = Save.defaultOptions()
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if not ok then return options end
  local loaded = SaveData.loadOptions(fs)
  local stored = loaded and loaded[Save.OPTIONS_KEY]
  if type(stored) == "table" then
    for key, value in pairs(stored) do
      if not SHARED_KEYS[key] then options[key] = value end
    end
  end
  if type(loaded) == "table" then
    for key in pairs(SHARED_KEYS) do
      if loaded[key] ~= nil then
        options[key] = loaded[key]
      elseif type(stored) == "table" and stored[key] ~= nil then
        options[key] = stored[key]
      end
    end
  end
  return options
end

-- Read-modify-write, so writing Gold's block never drops the Gen 1 keys (or
-- the slot registry, or modOptions) sitting beside it.
function Save.saveOptions(options, fs)
  if type(options) ~= "table" then return false end
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if not ok then return false end
  local file = SaveData.loadOptions(fs) or {}
  local block = {}
  for key, value in pairs(options) do
    if SHARED_KEYS[key] then
      file[key] = value
    else
      block[key] = value
    end
  end
  file[Save.OPTIONS_KEY] = block
  SaveData.saveOptions(file, fs)
  return true
end

-- MON_PKRS is one byte in the party and box structs, and every reader of it
-- (src/core/gen2/Pokerus.lua) splits it into two nybbles -- so a file that
-- somehow grew a float, a negative or a value past 255 there would hand out a
-- strain and a day count that no cartridge could produce.  Folded rather than
-- dropped, the way the money and coin caps above are clamped rather than reset.
local function normalizePokerus(mons)
  for _, mon in ipairs(mons or {}) do
    if type(mon) == "table" and mon.pokerus ~= nil then
      local value = tonumber(mon.pokerus) or 0
      if value < 0 then value = 0 end
      mon.pokerus = math.floor(value) % 256
    end
  end
end

-- constants/pokemon_data_constants.asm:79, :90
local function normalizeMoves(mons)
  for _, mon in ipairs(mons or {}) do
    if type(mon) == "table" and type(mon.moves) == "table" then
      local rebuilt = false
      for i, entry in ipairs(mon.moves) do
        if type(entry) ~= "table" then
          mon.moves[i] = { id = entry, pp = (mon.pp or {})[i] }
          rebuilt = true
        end
      end
      if rebuilt then mon.pp = nil end
    end
  end
end

-- ../pokecrystal/ram/sram.asm:140 sGSBallFlag.  nil is the cleared byte.
Save.GS_BALL_STATES = { have = true, given = true, used = true }

local function counter(value)
  return math.max(0, math.floor(tonumber(value) or 0))
end

-- ../pokecrystal/ram/sram.asm:138 "SRAM Crystal Data", created on demand the
-- way Mail.state creates sPartyMail, so a Crystal handler can index freely.
function Save.crystalState(save)
  local crystal = save.crystal or {}
  save.crystal = crystal
  if crystal.celebiCaught == nil then crystal.celebiCaught = false end
  crystal.beasts = crystal.beasts or {}
  -- ../pokecrystal/ram/wram.asm:3342 wBuenasPassword, :3343 wBlueCardBalance.
  local buena = crystal.buenaPassword or {}
  crystal.buenaPassword = buena
  buena.prizesToday = counter(buena.prizesToday)
  buena.streak = counter(buena.streak)
  -- ../pokecrystal/engine/events/move_tutor.asm:1 MoveTutor.
  crystal.moveTutor = crystal.moveTutor or {}
  if crystal.moveTutor.used == nil then crystal.moveTutor.used = false end
  -- ../pokecrystal/ram/wram.asm:3445 wUnlockedUnowns.
  crystal.unownWords = crystal.unownWords or {}
  -- ../pokecrystal/engine/menus/intro_menu.asm:69-70
  crystal.mapSign = crystal.mapSign or { prev = "LANDMARK_NEW_BARK_TOWN" }
  return crystal
end

-- ../pokecrystal/ram/sram.asm:147 "SRAM Battle Tower".  `reward` stays nil
-- until one is won, which is sBattleTowerReward's zero byte (:160).
function Save.battleTowerState(save)
  local tower = save.battleTower or {}
  save.battleTower = tower
  -- ../pokecrystal/ram/sram.asm:155 sNrOfBeatenBattleTowerTrainers.
  tower.streak = counter(tower.streak)
  tower.best = counter(tower.best)
  -- ../pokecrystal/ram/sram.asm:150 sBattleTowerChallengeState: 0 normal, 2 tower.
  tower.challenge = counter(tower.challenge)
  -- ../pokecrystal/ram/sram.asm:162 sBTMonOfTrainers.
  tower.prevTeams = tower.prevTeams or {}
  if tower.inChallenge == nil then tower.inChallenge = false end
  return tower
end

-- Fill in anything a save (or an older save) is missing, so callers can index
-- freely.  Runs on both newGame and load.
function Save.normalize(save)
  if type(save) ~= "table" then return nil end
  save.format = save.format or Save.FORMAT
  if not (GameVersion.VERSIONS[save.version]
      and GameVersion.generation(save.version) == 2) then
    save.version = GameVersion.get()
  end
  save.generation = 2
  save.player = save.player or {}
  -- _ResetWRAM leaves wPlayerGender at 0, PLAYERGENDER_MALE, and Gold never
  -- writes it -- constants/ram_constants.asm:177.
  save.player.gender = save.player.gender or "male"
  save.player.name = save.player.name
    or Save.defaultPlayerName(save.version, save.player.gender)
  save.player.id = save.player.id or rand(0, 65535)
  save.player.money = math.max(0, math.min(save.player.money or 0, Save.MAX_MONEY))
  save.player.coins = math.max(0, math.min(save.player.coins or 0, Save.MAX_COINS))
  save.player.badges = save.player.badges or {}
  save.player.kantoBadges = save.player.kantoBadges or {}
  -- Same InitializeNPCNames seed as newGame: a save carrying no rival field is
  -- a save that has not reached the officer, so it reads "???" rather than
  -- NameRival's post-screen default.
  save.rival = save.rival or { name = "???" }
  save.mom = save.mom or {}
  save.mom.name = save.mom.name or "MOM"
  -- An older save (or one normalized before H.BankOfMom existed) has a `mom`
  -- table with no `active`/`savingMoney` at all; both default to unset the
  -- same way a cartridge that has never run BankOfMom reads wMomSavingMoney
  -- as zero -- the bank has never been talked to and nothing is being saved.
  if save.mom.active == nil then save.mom.active = false end
  if save.mom.savingMoney == nil then save.mom.savingMoney = false end
  save.mom.savedMoney = math.max(0, math.min(
    tonumber(save.mom.savedMoney) or 0, Save.MAX_MONEY))
  -- wWhichMomItem indexes MomItems_2 and wMomItemTriggerBalance is a money
  -- field, so both are folded the way every other counter here is: an index
  -- past the end of the ladder is what CheckBalance_MomItem2's own `cp
  -- (MomItems_2.End - MomItems_2) / MOMITEM_SIZE` treats as "no rung left",
  -- which is a legal resting state and not a value to clamp away.
  save.mom.whichItem = math.max(0, math.floor(tonumber(save.mom.whichItem) or 0))
  save.mom.triggerBalance = math.max(0, math.min(
    math.floor(tonumber(save.mom.triggerBalance) or MomShopping.MOM_MONEY),
    Save.MAX_MONEY + MomShopping.MOM_MONEY))
  save.party = save.party or {}
  save.boxes = save.boxes or {}
  save.boxNames = save.boxNames or {}
  save.currentBox = save.currentBox or 1
  save.inventory = save.inventory or {}
  -- Mail.state creates both SRAM regions on demand, so an older save (or one a
  -- driver built by hand) can be indexed freely from the first letter on.
  Mail.state(save)
  save.pcItems = save.pcItems or {}
  save.phoneContacts = save.phoneContacts or {}
  -- wTradeFlags: one bit per NPC_TRADE_*, so a trade only ever happens once.
  -- A set here, keyed by the trade's own id (src/core/gen2/NpcTrade.lua).
  save.tradeFlags = save.tradeFlags or {}
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.caught = save.pokedex.caught or {}
  -- wUnownDex is NUM_UNOWN bytes; a file that somehow grew past that is
  -- trimmed for the same reason an over-long party is.
  save.unownDex = save.unownDex or {}
  while #save.unownDex > 26 do table.remove(save.unownDex) end
  -- wFirstUnownSeen is one byte holding a letter index 1..NUM_UNOWN, or 0
  -- before any Unown has been met; anything else is a file that was edited.
  local firstUnown = tonumber(save.firstUnownSeen) or 0
  firstUnown = math.floor(firstUnown)
  if firstUnown < 0 or firstUnown > 26 then firstUnown = 0 end
  save.firstUnownSeen = firstUnown
  -- wEventFlags, as the SERIALIZED BITFIELD src/world/gen2/Events.lua writes:
  -- byte index -> byte value, sparse, keyed by NUMBER and not by name.  Empty
  -- means the file predates InitializeEventsScript ever running, which is what
  -- World:loadPlayerData falls back to the seed on.
  save.events = save.events or {}
  save.flags = save.flags or {}
  -- The w<Map>SceneID block (ram/wram.asm), as map id -> scene id.  A map with
  -- no entry is on scene 0, the same as the cart's zero-filled byte.
  save.mapScenes = save.mapScenes or {}
  -- wPlayerState.  A file that predates the field reads as PLAYER_NORMAL, the
  -- same as the cart's zero byte; Save.validate is what rejects a name no
  -- cartridge could have produced.
  save.playerState = save.playerState or Save.PLAYER_NORMAL
  save.scriptMem = save.scriptMem or {}
  save.playTime = save.playTime
    or { hours = 0, minutes = 0, seconds = 0, frames = 0 }
  save.rtc = save.rtc or {}
  -- ../pokecrystal/ram/sram.asm:138,147: both regions are Crystal's own, so a
  -- Gold or Silver file never grows either key.
  if GameVersion.engine(save.version) == "crystal" then
    Save.crystalState(save)
    Save.battleTowerState(save)
  end
  -- HallOfFame.record fills in the count and the roster list, and trims a
  -- roster that a corrupt file grew past NUM_HOF_TEAMS -- the same guard the
  -- party gets below, for the same reason.
  local hof = HallOfFame.record(save)
  while #hof.teams > HallOfFame.NUM_TEAMS do
    table.remove(hof.teams)
  end
  -- Trim an over-long party rather than letting a corrupt file feed a
  -- seventh mon into battle.
  while #save.party > Save.PARTY_SIZE do
    table.remove(save.party)
  end
  normalizePokerus(save.party)
  normalizeMoves(save.party)
  for _, box in pairs(save.boxes) do
    if type(box) == "table" then
      normalizePokerus(box)
      normalizeMoves(box)
    end
  end
  -- move_mon.asm:143-149: a mon the player owns carries wPlayerID; saves
  -- written before the stamp existed get it here.
  local Mon = require("src.battle.gen2.Mon")
  for _, mon in ipairs(save.party) do Mon.stampOT(save, mon) end
  for _, box in pairs(save.boxes) do
    if type(box) == "table" then
      for _, mon in ipairs(box) do Mon.stampOT(save, mon) end
    end
  end
  return save
end

-- Migrations, oldest first.  Each entry upgrades a save at `from` to `from+1`.
Save.MIGRATIONS = {
  -- 1 -> 2: the endgame landed.  A format-1 save was written before the Hall
  -- of Fame existed, so it has no roster and cannot have been inducted; the
  -- upgrade is the empty block, and wSpawnAfterChampion stays nil so the first
  -- load after the upgrade is an ordinary CONTINUE rather than a warp to New
  -- Bark Town.
  [1] = function(save)
    save.hallOfFame = save.hallOfFame or { count = 0, teams = {} }
    save.spawnAfterChampion = nil
  end,
  -- 2 -> 3: the script VM's readmem / writemem bytes started riding the save.
  -- Nothing to carry across (a format-2 file never wrote them down), so the
  -- upgrade is the empty store and every address reads back 0.
  [2] = function(save)
    save.scriptMem = save.scriptMem or {}
  end,
  -- 3 -> 4: MAIL.  A format-3 file predates sPartyMail and sMailboxes
  -- entirely, so there is nothing to carry across and the upgrade is the empty
  -- pair.  A mon in one of those saves may still be HOLDING a mail item
  -- (`givepokemail` used to hand one over with no struct behind it), and that
  -- mon reads back as holding a blank letter rather than as holding nothing --
  -- which is what the cart's own zero-filled struct would say too.
  [3] = function(save)
    save.mail = save.mail or { party = {}, box = {} }
  end,
  -- 4 -> 5: the world state started being read back.  A format-4 file already
  -- carries both tables (the snapshot has always written them), so this is not
  -- a conversion -- it is the point at which they stop being write-only, and a
  -- file that never had them gets the empty pair.  An empty `events` is the
  -- honest answer for a save whose world never ran: World:loadPlayerData reads
  -- it as "InitializeEventsScript has not happened yet" and applies the seed,
  -- which is the same branch PlayersHouse2FInitializeRoomCallback takes.
  [4] = function(save)
    save.events = save.events or {}
    save.mapScenes = save.mapScenes or {}
  end,
  -- 5 -> 6: wPlayerState.  Unlike the pair above, this field was never written
  -- by anything, so there is genuinely nothing to carry across and every
  -- format-5 file upgrades to PLAYER_NORMAL -- which is exactly what those
  -- saves already came back as, because a world that read no state started on
  -- foot.  The `or` is for a file some other tool put a state in.
  [5] = function(save)
    save.playerState = save.playerState or Save.PLAYER_NORMAL
  end,
  -- 6 -> 7: Mom's shopping pair.  Nothing could have written either byte
  -- before MomTriesToBuySomething existed, so the upgrade is NewGame's own
  -- seed and a file that somehow carries one keeps it.
  [6] = function(save)
    save.mom = save.mom or {}
    if save.mom.whichItem == nil then save.mom.whichItem = 0 end
    if save.mom.triggerBalance == nil then
      save.mom.triggerBalance = MomShopping.MOM_MONEY
    end
  end,
  -- ../pokecrystal/engine/events/poke_seer.asm:103-104
  [7] = function(save)
    local Mon = require("src.battle.gen2.Mon")
    if not Mon.hasCaughtData(save.version) then return end
    local function clear(mon)
      if type(mon) ~= "table" or mon.isEgg then return end
      if (tonumber(mon.caughtLocation) or 0) ~= 0 then return end
      mon.caughtTime, mon.caughtLevel = 0, 0
      mon.caughtLocation, mon.caughtByGender = 0, "boy"
    end
    for _, mon in ipairs(save.party or {}) do clear(mon) end
    for _, box in pairs(save.boxes or {}) do
      if type(box) == "table" then
        for _, mon in ipairs(box) do clear(mon) end
      end
    end
    local dc = save.dayCare
    if type(dc) == "table" then
      for _, which in ipairs({ "man", "lady" }) do
        local side = dc[which]
        if type(side) == "table" then clear(side.mon) end
      end
    end
  end,
}

function Save.migrate(save)
  local format = tonumber(save.format) or 1
  while format < Save.FORMAT do
    local step = Save.MIGRATIONS[format]
    if not step then break end
    step(save)
    format = format + 1
    save.format = format
  end
  return save
end

-- ------- validation and quarantine
--
-- Same discipline as src/core/SaveData.lua's validate: a value play would
-- nil-index or wrap on never reaches the game, and whatever had to be dropped
-- is reported rather than vanishing silently.  scriptMem is the field that
-- needs it most, because its keys are raw WRAM addresses rather than ids out
-- of a table this port owns, so nothing else can vouch for them.

-- Script_readmem / Script_writemem (engine/overworld/scripting.asm) read a
-- two-byte address and move a single byte through wScriptVar, so an entry
-- outside 0..$ffff / 0..255 cannot have come from a script running here.
-- Keys survive the serializer as strings in some files, hence the tonumber.
local function scrubScriptMem(save, report)
  local mem = save.scriptMem
  if type(mem) ~= "table" then
    if mem ~= nil then
      report.lostScriptMem[#report.lostScriptMem + 1] =
        { addr = nil, value = mem }
    end
    save.scriptMem = {}
    return
  end
  local clean = {}
  for key, value in pairs(mem) do
    local addr, byte = tonumber(key), tonumber(value)
    local okAddr = addr and addr == math.floor(addr)
      and addr >= 0 and addr <= 0xFFFF
    local okByte = byte and byte == math.floor(byte)
      and byte >= 0 and byte <= 255
    if okAddr and okByte then
      clean[addr] = byte
    else
      report.lostScriptMem[#report.lostScriptMem + 1] =
        { addr = key, value = value }
    end
  end
  save.scriptMem = clean
end

-- wEventFlags is 256 bytes of bitfield and nothing else in the save vouches
-- for a byte index, so it gets the same treatment scriptMem does: an index
-- past the last byte or a value that is not a byte could not have come from
-- the cart's array, and handing one to Events:restore would put a flag id no
-- object can ever name into the live bitfield.  Keys survive the serializer as
-- strings in some files, hence the tonumber.
local function scrubEvents(save, report)
  local flags = save.events
  if type(flags) ~= "table" then
    if flags ~= nil then
      report.lostEvents[#report.lostEvents + 1] = { byte = nil, value = flags }
    end
    save.events = {}
    return
  end
  local clean = {}
  for key, value in pairs(flags) do
    local index, byte = tonumber(key), tonumber(value)
    local okIndex = index and index == math.floor(index)
      and index >= 0 and index < Save.EVENT_BYTES
    local okByte = byte and byte == math.floor(byte)
      and byte >= 0 and byte <= 255
    if okIndex and okByte then
      clean[index] = byte
    else
      report.lostEvents[#report.lostEvents + 1] = { byte = key, value = value }
    end
  end
  save.events = clean
end

-- The w<Map>SceneID block: one BYTE per map, keyed here by the map id the
-- cache uses rather than by the WRAM address, because that is what
-- World:mapSceneOf looks up.  An id this cache does not know is left alone --
-- nothing ever reads it, the same way an unused scene byte sits in WRAM -- but
-- a key that is not a map id at all, or a scene that is not a byte, is dropped
-- rather than handed to a scene-script lookup that would index past its arms.
local function scrubMapScenes(save, report)
  local scenes = save.mapScenes
  if type(scenes) ~= "table" then
    if scenes ~= nil then
      report.lostMapScenes[#report.lostMapScenes + 1] =
        { map = nil, scene = scenes }
    end
    save.mapScenes = {}
    return
  end
  local clean = {}
  for key, value in pairs(scenes) do
    local scene = tonumber(value)
    local okMap = type(key) == "string" and key ~= ""
    local okScene = scene and scene == math.floor(scene)
      and scene >= 0 and scene <= 255
    if okMap and okScene then
      clean[key] = scene
    else
      report.lostMapScenes[#report.lostMapScenes + 1] =
        { map = key, scene = value }
    end
  end
  save.mapScenes = clean
end

-- wPlayerState is one byte on the cart and one of four names here, so anything
-- else -- a raw byte out of a hand-edited file, a state this port has never
-- had -- is dropped back to PLAYER_NORMAL.  Left alone it would give the
-- player a sprite lookup with no row of its own and step rules that belong to
-- nobody: neither isBiking nor isSurfing would answer true, so they would walk
-- at walking pace over land while the save insisted they were somewhere else.
local function scrubPlayerState(save, report)
  local state = save.playerState
  if Save.PLAYER_STATES[state] then return end
  if state ~= nil then
    report.lostPlayerState[#report.lostPlayerState + 1] = { state = state }
  end
  save.playerState = Save.PLAYER_NORMAL
end

function Save.validate(save)
  local report = { lostScriptMem = {}, lostMail = {}, lostEvents = {},
    lostMapScenes = {}, lostPlayerState = {} }
  if type(save) ~= "table" then return report end
  scrubScriptMem(save, report)
  -- The world state World:loadPlayerData hands back to the live game: the
  -- event bitfield, the per-map scene ids and wPlayerState.  All three are
  -- read on every load, so all three have to be trustworthy before the first
  -- map comes up.
  scrubEvents(save, report)
  scrubMapScenes(save, report)
  scrubPlayerState(save, report)
  -- wLastDexMode: only the three modes the #DEX has (PokedexMenu MODES);
  -- a hand-edited value falls back to NEW_MODE, the cart's zero byte
  if save.lastDexMode ~= "NEW" and save.lastDexMode ~= "OLD"
     and save.lastDexMode ~= "A-Z" then
    save.lastDexMode = "NEW"
  end
  -- The `mailmsg` structs get the same treatment for the same reason: their
  -- `type` byte is an item id nothing else in the save vouches for, and a
  -- party key outside 1..6 or a MAILBOX past MAILBOX_CAPACITY is a region the
  -- cart could not have written.  Mail.validate owns the rules; this is only
  -- where the ledger is collected (src/core/gen2/Mail.lua).
  Mail.validate(save, report)
  return report
end

-- True when nothing was quarantined, so a vanilla save loads without a word.
function Save.emptyReport(report)
  if type(report) ~= "table" then return true end
  return #(report.lostScriptMem or {}) == 0
    and #(report.lostMail or {}) == 0
    and #(report.lostEvents or {}) == 0
    and #(report.lostMapScenes or {}) == 0
    and #(report.lostPlayerState or {}) == 0
end

-- Does a Gold save exist?  This is what decides whether the intro menu offers
-- CONTINUE (engine/menus/main_menu.asm MainMenu_GetWhichMenu reads
-- wSaveFileExists for exactly this).
function Save.exists(version)
  local main, backup = saveNames(version)
  local f = fs()
  if not f then return false end
  return (f.getInfo(main) ~= nil) or (f.getInfo(backup) ~= nil)
end

local function readTable(path)
  local f = fs()
  if not f or not f.getInfo(path) then return nil, "missing" end
  local raw = f.read(path)
  if not raw then return nil, "unreadable" end
  local ok, value = pcall(SaveSerializer.decode, raw)
  if not ok or type(value) ~= "table" then
    return nil, "corrupt: " .. tostring(value)
  end
  return value
end

-- Returns save, recovered ("bak"/"tmp" when a staged or backup copy had to be
-- promoted), err, report (the quarantine ledger from Save.validate; empty for
-- any save this port wrote itself).
function Save.load(version)
  local main, backup, tmp = saveNames(version)
  local data, err = readTable(main)
  local recovered
  if not data then
    local staged = readTable(tmp)
    if staged then
      data, recovered = staged, "tmp"
    else
      local prev = readTable(backup)
      if prev then data, recovered = prev, "bak" end
    end
  end
  if not data then return nil, nil, err end
  Save.migrate(data)
  Save.normalize(data)
  local report = Save.validate(data)
  if not Save.emptyReport(report) then
    -- Gold has no report screen of its own yet; the log is what keeps a
    -- quarantine from being invisible, the way Game.lua falls back for Gen 1.
    Logger.warn(
      "gold load report: %d script memory byte(s), %d MAIL struct(s), " ..
      "%d event byte(s), %d map scene(s) and %d player state(s) dropped",
      #report.lostScriptMem, #report.lostMail, #report.lostEvents,
      #report.lostMapScenes, #report.lostPlayerState)
  end
  return data, recovered, nil, report
end

-- Atomic-ish write, matching SaveData.save: back the old file up, stage a
-- .tmp, replace, drop the .tmp.  love.filesystem has no rename, so the .tmp
-- copy is the witness that survives a crash mid-replace.
function Save.save(save)
  if type(save) ~= "table" then return false, "no save" end
  Save.normalize(save)
  local version = save.version
  do
    local ok, SaveData = pcall(require, "src.core.SaveData")
    -- In the CART's registry when one is active, for the same reason
    -- saveNames resolves the cart's scope: otherwise the first save inside a
    -- cart registers a slot against the base game and makes it active, so the
    -- cart's playthrough appears in the launcher's list for the base version
    -- and the player's own save there is what it overwrites.
    local cart = ok and SaveData.getCart and SaveData.getCart() or nil
    if type(cart) ~= "string" or cart == "" then cart = nil end
    if ok and cart then
      if SaveData.activeCartSlot and not SaveData.activeCartSlot(cart) then
        local id = SaveData.createCartSlot and SaveData.createCartSlot(cart)
        if id and SaveData.setActiveCartSlot then
          SaveData.setActiveCartSlot(cart, id)
        end
      end
    elseif ok and SaveData.activeSlot and not SaveData.activeSlot(version) then
      local id = SaveData.createSlot and SaveData.createSlot(version)
      if id and SaveData.setActiveSlot then
        SaveData.setActiveSlot(version, id)
      end
    end
  end
  local main, backup, tmp = saveNames(version)
  local f = fs()
  if not f then return false, "no filesystem" end
  -- saveNames may now return a saves/<version>/<slot>.lua path, and
  -- love.filesystem.write does not create missing parent directories.
  local dir = main:match("^(.*)/[^/]+$")
  if dir and f.createDirectory then f.createDirectory(dir) end
  save.savedAt = os.time()
  local encoded = SaveSerializer.encode(save)
  if f.getInfo(main) then
    local prev = f.read(main)
    if prev then f.write(backup, prev) end
  end
  local ok, err = f.write(tmp, encoded)
  if not ok then
    Logger.error("gold save failed: %s", tostring(err))
    return false, err
  end
  f.remove(main)
  ok, err = f.write(main, encoded)
  if not ok then
    Logger.error("gold save failed: %s", tostring(err))
    return false, err
  end
  f.remove(tmp)
  Logger.info("saved gold game")
  return true
end

-- The three lines Gold's CONTINUE panel shows before you confirm
-- (DisplaySaveInfoOnContinue): who, how many badges, how much of the dex, and
-- how long.  Returned as data so the screen can lay it out.
function Save.summary(save)
  if type(save) ~= "table" then return nil end
  local badges = 0
  -- Continue_DisplayBadgeCount counts TWO bytes, wJohtoBadges then wKantoBadges
  -- (engine/menus/intro_menu.asm:461-469).
  for _, has in pairs(save.player and save.player.badges or {}) do
    if has then badges = badges + 1 end
  end
  for _, has in pairs(save.player and save.player.kantoBadges or {}) do
    if has then badges = badges + 1 end
  end
  local caught = 0
  for _, has in pairs(save.pokedex and save.pokedex.caught or {}) do
    if has then caught = caught + 1 end
  end
  local time = save.playTime or {}
  return {
    name = save.player and save.player.name or "?",
    badges = badges,
    caught = caught,
    hours = time.hours or 0,
    minutes = time.minutes or 0,
    map = save.position and save.position.map or save.spawn,
  }
end

-- Advance the play clock one logic tick.  Called from the fixed step, so 60
-- calls is one second, the same rate wGameTimeFrames counts at.
function Save.tickPlayTime(save)
  local t = save and save.playTime
  if not t then return end
  t.frames = (t.frames or 0) + 1
  if t.frames < 60 then return end
  t.frames = 0
  t.seconds = (t.seconds or 0) + 1
  if t.seconds < 60 then return end
  t.seconds = 0
  t.minutes = (t.minutes or 0) + 1
  if t.minutes < 60 then return end
  t.minutes = 0
  -- The cart caps at 999:59 and stops counting; do the same rather than
  -- letting the trainer card overflow its field.
  t.hours = math.min((t.hours or 0) + 1, 999)
end

return Save
