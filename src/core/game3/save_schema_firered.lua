-- Native Fire Red save schema (engine SaveData JSON). No GBA Flash dumps.

local MapIds = require("src.core.game3.map_ids")
local Options = require("src.core.game3.options")
local Profile = require("src.core.game3.profile")
local ModRuntime = require("src.mods.Runtime")

local Schema = {}

Schema.VERSION = 1

local function empty_string_vars()
  return { [1] = "", [2] = "", [3] = "" }
end

local function empty_special_vars()
  local t = {}
  for i = 0x8000, 0x8014 do
    t[i] = 0
  end
  return t
end

-- pokefirered/include/constants/flags.h:1327
local FLAG_SYS_SAFARI_MODE = 0x800
-- pokefirered/include/constants/vars.h:162
local VAR_MAP_SCENE_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE = 0x406E

local function mail_module()
  local ok, Mail = pcall(require, "src.core.game3.mail")
  if ok and type(Mail) == "table" then return Mail end
  return nil
end

local function mail_export(session)
  local Mail = mail_module()
  if Mail and type(Mail.export) == "function" then return Mail.export(session) end
  return session.mail
end

local function mail_restore(save)
  local Mail = mail_module()
  if Mail and type(Mail.restore) == "function" then return Mail.restore(save.mail) end
  return save.mail
end

local function clear_saved_var(session, id)
  local vars = session.vars
  if type(vars) ~= "table" then return end
  local Flags = require("src.core.game3.scripting.flags")
  vars[tostring(id)] = nil
  vars[string.format("0x%X", id)] = nil
  local name = Flags.VAR_NAMES and Flags.VAR_NAMES[id]
  if name then vars[name] = nil end
  vars[id] = 0
end

-- pokefirered/src/overworld.c:345 Overworld_ResetStateOnContinue
local function reset_state_on_continue(session)
  local Flags = require("src.core.game3.scripting.flags")
  Flags.setFlag(session, nil, FLAG_SYS_SAFARI_MODE, false)
  clear_saved_var(session, VAR_MAP_SCENE_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE)
  session.safari = nil
  if type(session.map) == "string" and session.map:find("^FR_SAFARI_ZONE_")
      and not Flags.getFlag(session, nil, FLAG_SYS_SAFARI_MODE) then
    -- pokefirered/data/scripts/safari_zone.inc:7 SafariZone_EventScript_Exit
    local Safari = require("src.core.game3.safari")
    Flags.setVar(session, nil, VAR_MAP_SCENE_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE, 1)
    session.map, session.x, session.y = Safari.EXIT_MAP, Safari.EXIT_X, Safari.EXIT_Y
    session.facing = "down"
  end
end

-- pokefirered/include/save_location.h:5
local CONTINUE_GAME_WARP = 0x01
-- pokefirered/data/maps/PokemonLeague_HallOfFame/scripts.inc:40
local HALL_OF_FAME_MAP = "FR_POKEMON_LEAGUE_HALL_OF_FAME"

-- pokefirered/src/overworld.c:1706 CB2_ContinueSavedGame
local function use_continue_game_warp(session, mounted)
  local Bit = require("bit")
  local f = tonumber(session.specialSaveWarpFlags) or 0
  local w = session.continueGameWarp
  if Bit.band(f, CONTINUE_GAME_WARP) ~= 0 and type(w) == "table" and type(w.map) == "string" then
    session.specialSaveWarpFlags = Bit.band(f, Bit.bnot(CONTINUE_GAME_WARP))
    session.map, session.x, session.y, session.facing = w.map, tonumber(w.x), tonumber(w.y), "down"
    return
  end
  session._continueWarpDeferred = nil
  if session.map == HALL_OF_FAME_MAP then
    local Field = require("src.core.game3.field")
    if not mounted and not Field.flyDestinationsMounted() then
      session._continueWarpDeferred = true
      return
    end
    -- pokefirered/src/post_battle_event_funcs.c:33
    local dest = assert(Field.flyDestination("MAPSEC_PALLET_TOWN"),
      "no heal location for MAPSEC_PALLET_TOWN")
    session.map, session.x, session.y, session.facing = dest.map, dest.x, dest.y, "down"
  end
end

function Schema.useContinueGameWarp(session)
  return use_continue_game_warp(session, true)
end

-- pokefirered/include/constants/map_groups.h:9
local LINK_ROOMS = {
  FR_BATTLE_COLOSSEUM_2P = true,
  FR_TRADE_CENTER = true,
  FR_RECORD_CORNER = true,
  FR_BATTLE_COLOSSEUM_4P = true,
  FR_UNION_ROOM = true,
}

-- pokefirered/src/load_save.c:149 SetContinueGameWarpStatusToDynamicWarp
local function save_warp_fields(session)
  local f = tonumber(session.specialSaveWarpFlags) or 0
  local w = session.continueGameWarp
  local dw = session.dynamicWarp
  if LINK_ROOMS[session.map] and type(dw) == "table" and type(dw.map) == "string"
      and tonumber(dw.x) and tonumber(dw.y) then
    -- pokefirered/src/overworld.c:701 SetContinueGameWarpToDynamicWarp
    return require("bit").bor(f, CONTINUE_GAME_WARP), { map = dw.map, x = tonumber(dw.x), y = tonumber(dw.y) }
  end
  return f, w
end

-- pokefirered/include/constants/region_map_sections.h:211 KANTO_MAPSEC_START
local MAPSEC_PALLET_TOWN = 88

local function is_own_mon(session, mon)
  local otName = mon.otName or mon.ot or mon.originalTrainer
  local name = session.name or session.playerName
  if type(otName) == "string" and type(name) == "string" and otName ~= name then return false end
  local otId, tid = tonumber(mon.otId), tonumber(session.trainerId)
  if otId and tid and (otId % 0x10000) ~= (tid % 0x10000) then return false end
  return true
end

-- pokefirered/src/pokemon.c:1796 CreateBoxMon OT_ID_PLAYER_ID
local function repair_own_mon(session, mon)
  if type(mon) ~= "table" then return end
  if not is_own_mon(session, mon) then return end
  local stamped = mon.metLocationName
  if mon.metLocation == nil and not (type(stamped) == "string" and stamped ~= "") then
    mon.metLocation = MAPSEC_PALLET_TOWN
  end
  local secret = tonumber(session.secretId)
  if secret and tonumber(mon.otSecretId) ~= secret then
    mon.otSecretId = secret
  end
end

function Schema.repairOwnMons(session)
  for _, mon in ipairs(session.party or {}) do
    repair_own_mon(session, mon)
  end
  local storage = session.storage
  for _, box in pairs(storage and storage.boxes or {}) do
    for _, mon in pairs(type(box) == "table" and box.mons or {}) do
      repair_own_mon(session, mon)
    end
  end
end

-- pokefirered/src/union_room_chat.c:1430
local function registered_texts_restore(v)
  if type(v) ~= "table" then return nil end
  local Chat = require("src.core.game3.link.chat")
  local out = {}
  for i = 1, Chat.KB_ROWS do
    local s = v[i]
    if s ~= nil and type(s) ~= "string" then return nil end
    local tokens = Chat.tokens(s or "")
    while #tokens > Chat.REGISTER_CHARS do table.remove(tokens) end
    out[i] = table.concat(tokens)
  end
  return out
end

-- pokefirered/src/link_rfu_3.c:1178
local function trainer_name_records_restore(v)
  if type(v) ~= "table" then return nil end
  local Chat = require("src.core.game3.link.chat")
  local out = {}
  for _, r in ipairs(v) do
    if #out >= 20 then break end
    if type(r) == "table" and type(r.name) == "string" then
      out[#out + 1] = { name = Chat.cleanName(r.name), trainerId = (math.floor(tonumber(r.trainerId) or 0)) % 65536 }
    end
  end
  return out
end

--- Factory for a pristine New Game after Oak intro finishes.
function Schema.newGame(opts)
  opts = opts or {}
  local start = opts.start or MapIds.NEW_GAME_START
  local Flags = require("src.core.game3.scripting.flags")
  local Bag = require("src.core.game3.bag")
  local hide = {}
  for _, id in ipairs(Flags.NEW_GAME_HIDE_FLAGS or {}) do
    hide[tostring(id)] = true
  end
  local session = {
    schemaVersion = Schema.VERSION,
    engine = "game3",
    version = opts.version or ((require("src.core.GameVersion").get() == "leafgreen")
      and "leafgreen" or Profile.active().id),
    generation = 3,
    party = {},
    bag = Bag.new(),
    dex = { seen = {}, owned = {}, caught = {}, national = false },
    money = tonumber(opts.money) or 3000,
    coins = 0,
    -- include/global.h:354, src/berry_powder.c:50
    berryPowder = 0,
    name = opts.name or "RED",
    rivalName = opts.rivalName or "BLUE",
    gender = opts.gender or 0, -- 0 boy / 1 girl
    map = start.map,
    x = start.x,
    y = start.y,
    facing = start.facing or "down",
    healMap = start.healMap or start.map,
    healX = start.healX or start.x,
    healY = start.healY or start.y,
    stringVars = empty_string_vars(),
    specialVars = empty_special_vars(),
    flags = hide,
    vars = {},
    playtime = { hours = 0, minutes = 0, seconds = 0 },
    easyChatProfile = { 2601, 4128, 526, 2611 },
    options = nil,
    registeredItem = nil,
    monBoxId = nil,
    monBoxPos = nil,
    -- pokefirered/include/global.h:764
    dynamicWarp = nil,
    escapeWarp = nil,
    -- pokefirered/include/global.h:770
    flashLevel = 0,
    move_overlay = {},
    trainerId = nil,
    secretId = nil,
    rng = nil,
    vsSeeker = { steps = 0, charging = 0, rematches = {} },
    roamer = nil,
  }
  -- pret new_game.c: SeedWildEncounterRng(Random()) after title SeedRngAndSetTrainerId.
  local Rng = require("src.core.game3.rng")
  session.trainerId = Rng.seedNewGame({ seed = opts.rngSeed })
  -- pokefirered/src/new_game.c:56 InitPlayerTrainerId
  session.secretId = Rng.Random()
  session.id = session.trainerId
  session.playerId = session.trainerId
  Rng.captureToSession(session)
  local Storage = require("src.core.game3.storage")
  session.storage = Storage.new()
  session.storage.items[1] = { id = 13, qty = 1 } -- pokefirered/src/player_pc.c:100
  -- pokefirered/src/new_game.c:143 ResetTrainerFanClub
  require("src.core.game3.trainer_fan_club").reset(session)
  -- pokefirered/src/new_game.c:132 InitMagikarpSizeRecord
  local SizeRecord = require("src.core.game3.pokemon_size_record")
  SizeRecord.initMagikarpSizeRecord(session)
  SizeRecord.initHeracrossSizeRecord(session)
  Options.ensure(session)
  -- Plan naming: text_speed / l_equals_a aliases mirror Options fields.
  session.options.text_speed = session.options.textSpeed
  session.options.l_equals_a = (session.options.buttonMode == 2)
  if type(opts.engineOptions) == "table" then
    Options.bind(session, opts.engineOptions)
  end
  session.modData = {}
  if ModRuntime.wantsHook("save.new_game") then
    local hooked = ModRuntime.call("save.new_game", function(s) return s end, session)
    if type(hooked) == "table" then session = hooked end
  end
  return session
end

function Schema.toSaveTable(session)
  if type(session) ~= "table" then return nil end
  Options.ensure(session)
  local Rng = require("src.core.game3.rng")
  Rng.captureToSession(session)
  local warpFlags, continueWarp = save_warp_fields(session)
  return {
    schemaVersion = session.schemaVersion or Schema.VERSION,
    engine = "game3",
    version = session.version or Profile.active().id,
    generation = session.generation or 3,
    name = session.name,
    rivalName = session.rivalName,
    gender = session.gender,
    money = session.money,
    coins = session.coins,
    -- include/global.h:354, src/berry_powder.c:50
    berryPowder = session.berryPowder or 0,
    berryCrushPressingSpeeds = session.berryCrushPressingSpeeds,
    pokemonJumpRecords = session.pokemonJumpRecords,
    dodrioBerryPickingRecords = session.dodrioBerryPickingRecords,
    -- pokefirered/src/union_room_chat.c:1182
    registeredTexts = session.registeredTexts,
    -- pokefirered/src/link_rfu_3.c:1122
    trainerNameRecords = session.trainerNameRecords,
    party = session.party,
    bag = session.bag,
    inventory = session.bag, -- SaveData compatibility alias
    dex = session.dex,
    map = session.map,
    x = session.x,
    y = session.y,
    facing = session.facing,
    healMap = session.healMap,
    healX = session.healX,
    healY = session.healY,
    stringVars = session.stringVars or empty_string_vars(),
    specialVars = session.specialVars or empty_special_vars(),
    flags = session.flags or {},
    vars = session.vars or {},
    playTime = session.playtime or session.playTime or { hours = 0, minutes = 0, seconds = 0 },
    easyChatProfile = session.easyChatProfile,
    options = Options.engine(session) or session.options,
    storage = session.storage and require("src.core.game3.storage").serialize(session.storage) or nil,
    registeredItem = session.registeredItem,
    monBoxId = session.monBoxId,
    monBoxPos = session.monBoxPos,
    -- pokefirered/include/global.h:764
    dynamicWarp = session.dynamicWarp,
    escapeWarp = session.escapeWarp,
    continueGameWarp = continueWarp,
    specialSaveWarpFlags = warpFlags,
    -- pokefirered/include/global.h:348
    gcnLinkFlags = tonumber(session.gcnLinkFlags) or 0,
    -- pokefirered/include/global.h:770
    flashLevel = tonumber(session.flashLevel),
    move_overlay = session.move_overlay or {},
    trainerId = session.trainerId,
    secretId = session.secretId,
    secretId = session.secretId,
    rng = session.rng,
    vsSeeker = session.vsSeeker,
    roamer = session.roamer,
    -- GAME_STAT_* counters: slot-machine jackpots, hatched eggs, link W/L/D,
    -- link trades, and the sticker-man brags that read them.
    gameStats = session.gameStats or {},
    -- Link battle records (Record Corner / fan club) and the trainer card's
    -- link win/loss counters -- both read back by link and UI modules.
    linkBattleRecords = type(session.linkBattleRecords) == "table" and session.linkBattleRecords or {},
    trainerCard = type(session.trainerCard) == "table" and session.trainerCard or {},
    -- Hall of Fame induction (pret hall_of_fame.c): written by
    -- commit_clear_and_save, read by the trainer card and HOF viewers.
    game_cleared = session.game_cleared == true,
    hasHallOfFameRecords = session.hasHallOfFameRecords == true,
    hofDebutHours = tonumber(session.hofDebutHours),
    hofDebutMinutes = tonumber(session.hofDebutMinutes),
    hofDebutSeconds = tonumber(session.hofDebutSeconds),
    hofDebutTime = session.hofDebutTime,
    hallOfFameTeams = type(session.hallOfFameTeams) == "table" and session.hallOfFameTeams or {},
    mail = mail_export(session),
    questLog = require("src.core.game3.quest_log").export(session),
    modData = session.modData,
    meta = session.meta,
  }
end

function Schema.hasNoneItemSlot(bag)
  if type(bag) ~= "table" then return false end
  local ItemsData = require("src.core.game3.items_data")
  if type(bag.pockets) == "table" then
    for _, slots in pairs(bag.pockets) do
      if type(slots) == "table" then
        for _, slot in ipairs(slots) do
          if type(slot) == "table" and slot.id ~= nil and ItemsData.toNumericId(slot.id) == 0 then
            return true
          end
        end
      end
    end
  end
  if type(bag.stacks) == "table" then
    for id, qty in pairs(bag.stacks) do
      if ItemsData.toNumericId(id) == 0 and (tonumber(qty) or 0) > 0 then return true end
    end
  end
  return false
end

function Schema.fromSaveTable(save)
  if type(save) ~= "table" then return Schema.newGame() end
  local Bag = require("src.core.game3.bag")
  local bag = save.bag or save.inventory or {}
  if Schema.hasNoneItemSlot(bag) and type(save.flags) == "table" then
    -- pokefirered/include/constants/flags.h:1083
    for id = 0x3E8 + 51, 0x3E8 + 62 do
      save.flags[id] = nil
      save.flags[tostring(id)] = nil
    end
  end
  if type(bag) ~= "table" or not bag.pockets then
    bag = Bag.migrate(type(bag) == "table" and bag or {})
  else
    Bag.migrate(bag) -- ensure stacks mirror
  end
  local session = {
    schemaVersion = save.schemaVersion or Schema.VERSION,
    engine = save.engine or "game3",
    version = save.version or Profile.active().id,
    generation = tonumber(save.generation) or 3,
    party = save.party or {},
    bag = bag,
    dex = save.dex or {},
    money = save.money or 0,
    coins = save.coins or 0,
    berryPowder = tonumber(save.berryPowder) or 0,
    berryCrushPressingSpeeds = type(save.berryCrushPressingSpeeds) == "table" and save.berryCrushPressingSpeeds or nil,
    pokemonJumpRecords = type(save.pokemonJumpRecords) == "table" and save.pokemonJumpRecords or nil,
    dodrioBerryPickingRecords = type(save.dodrioBerryPickingRecords) == "table" and save.dodrioBerryPickingRecords or nil,
    registeredTexts = registered_texts_restore(save.registeredTexts),
    trainerNameRecords = trainer_name_records_restore(save.trainerNameRecords),
    name = save.name or "RED",
    rivalName = save.rivalName or "BLUE",
    gender = save.gender or 0,
    map = save.map or MapIds.NEW_GAME_START.map,
    x = save.x or MapIds.NEW_GAME_START.x,
    y = save.y or MapIds.NEW_GAME_START.y,
    facing = save.facing or "down",
    healMap = save.healMap,
    healX = save.healX,
    healY = save.healY,
    stringVars = save.stringVars or empty_string_vars(),
    specialVars = save.specialVars or empty_special_vars(),
    flags = save.flags or {},
    vars = save.vars or {},
    playtime = save.playTime or save.playtime or { hours = 0, minutes = 0, seconds = 0 },
    easyChatProfile = save.easyChatProfile or { 2601, 4128, 526, 2611 },
    options = nil,
    storage = require("src.core.game3.storage").restore(save.storage, save.pc, save.pcItems or save.pc_items),
    registeredItem = save.registeredItem,
    monBoxId = save.monBoxId,
    monBoxPos = save.monBoxPos,
    -- pokefirered/include/global.h:764
    dynamicWarp = type(save.dynamicWarp) == "table" and save.dynamicWarp or nil,
    escapeWarp = type(save.escapeWarp) == "table" and save.escapeWarp or nil,
    continueGameWarp = type(save.continueGameWarp) == "table" and save.continueGameWarp or nil,
    specialSaveWarpFlags = tonumber(save.specialSaveWarpFlags) or 0,
    -- pokefirered/include/global.h:348
    gcnLinkFlags = tonumber(save.gcnLinkFlags) or 0,
    -- pokefirered/include/global.h:770
    flashLevel = tonumber(save.flashLevel),
    move_overlay = save.move_overlay or {},
    trainerId = save.trainerId,
    secretId = save.secretId,
    id = save.trainerId,
    playerId = save.trainerId,
    rng = save.rng,
    vsSeeker = type(save.vsSeeker) == "table" and save.vsSeeker or { steps = 0, charging = 0, rematches = {} },
    roamer = type(save.roamer) == "table" and save.roamer or nil,
    -- Additive: a save written before this key exists loads as an empty table.
    gameStats = type(save.gameStats) == "table" and save.gameStats or {},
    -- Additive: older saves load these as empty tables.
    linkBattleRecords = type(save.linkBattleRecords) == "table" and save.linkBattleRecords or {},
    trainerCard = type(save.trainerCard) == "table" and save.trainerCard or {},
    -- Additive: older saves load these as defaults.
    game_cleared = save.game_cleared == true,
    hasHallOfFameRecords = save.hasHallOfFameRecords == true,
    hofDebutHours = tonumber(save.hofDebutHours),
    hofDebutMinutes = tonumber(save.hofDebutMinutes),
    hofDebutSeconds = tonumber(save.hofDebutSeconds),
    hofDebutTime = save.hofDebutTime,
    hallOfFameTeams = type(save.hallOfFameTeams) == "table" and save.hallOfFameTeams or {},
    mail = mail_restore(save),
    questLog = require("src.core.game3.quest_log").restore(save.questLog),
    modData = type(save.modData) == "table" and save.modData or {},
    meta = save.meta,
  }
  require("src.core.game3.save_mon").each(session, require("src.core.game3.save_mon").normalize)
  reset_state_on_continue(session)
  use_continue_game_warp(session)
  Schema.ensureMonBalls(session)
  Schema.repairOwnMons(session)
  local Flags = require("src.core.game3.scripting.flags")
  Flags.repairSaveState(session)
  Schema.repairRoamer(session)
  if type(save.options) == "table" then
    Options.bind(session, save.options)
  else
    Options.ensure(session)
  end
  return session
end

function Schema.repairRoamer(session)
  if not session or session.roamer then return end
  local FLAG_SYS_CAN_LINK_WITH_RS = 0x844
  local VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F = 0x4076
  local VAR_STARTER_MON = 0x4031
  local flags = session.flags or {}
  local hasLink = (flags[FLAG_SYS_CAN_LINK_WITH_RS] == true) or (flags["FLAG_SYS_CAN_LINK_WITH_RS"] == true)
  local vars = session.vars or {}
  local sceneVal = tonumber(vars[VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F] or vars["VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F"]) or 0
  if hasLink or sceneVal >= 6 then
    local Roamer = require("src.core.game3.roamer")
    local starter = tonumber(vars[VAR_STARTER_MON] or vars["VAR_STARTER_MON"]) or 0
    Roamer.init(session, starter)
  end
end

function Schema.ensureMonBall(mon)
  if type(mon) ~= "table" then return end
  -- pokefirered/src/pokemon.c:1820
  mon.pokeball = tonumber(mon.pokeball) or 4
end

function Schema.ensureMonNumbering(mon)
  if type(mon) ~= "table" then return end
  local Pokemon = require("src.core.game3.pokemon")
  if Pokemon.numberingOf(mon) then return end
  local raw = mon.species or mon.speciesId or mon.id
  if type(raw) == "string" or tonumber(raw) == nil then return end
  mon.speciesNumbering = Pokemon.NUMBERING_INTERNAL
end

function Schema.ensureMonBalls(session)
  for _, mon in ipairs(session.party or {}) do
    Schema.ensureMonBall(mon)
    Schema.ensureMonNumbering(mon)
  end
  local storage = session.storage
  for _, box in pairs(storage and storage.boxes or {}) do
    for _, mon in pairs(type(box) == "table" and box.mons or {}) do
      Schema.ensureMonBall(mon)
      Schema.ensureMonNumbering(mon)
    end
  end
end

return Schema
