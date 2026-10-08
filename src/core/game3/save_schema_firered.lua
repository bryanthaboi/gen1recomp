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

local function empty_special_vars(version)
  local Ctx = require("src.core.game3.scripting.ctx")
  local t = {}
  for i = Ctx.SPECIAL_LO, Ctx.specialLayout(version).hi do
    t[i] = 0
  end
  return t
end

function Schema.rulesFor(version)
  local row = Profile.of(version)
  local path = row.saveRules
  if type(path) ~= "string" then
    error("game3 profile '" .. tostring(row.id) .. "' has no saveRules module", 0)
  end
  return require(path)
end

local function rules_of(session)
  return Schema.rulesFor(type(session) == "table" and session.version or nil)
end

local function copy_list(t)
  if type(t) ~= "table" then return nil end
  local out = {}
  for i, v in ipairs(t) do out[i] = v end
  return out
end

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

function Schema.useContinueGameWarp(session)
  return rules_of(session).useContinueGameWarp(session, true)
end

local function is_own_mon(session, mon)
  local otName = mon.otName or mon.ot or mon.originalTrainer
  local name = session.name or session.playerName
  if type(otName) == "string" and type(name) == "string" and otName ~= name then return false end
  local otId, tid = tonumber(mon.otId), tonumber(session.trainerId)
  if otId and tid and (otId % 0x10000) ~= (tid % 0x10000) then return false end
  local Identity = require("src.core.TrainerIdentity")
  local sid = Identity.u16(session.secretId)
  if mon.otSecretId ~= nil and sid and Identity.u16(mon.otSecretId) ~= sid then return false end
  return true
end

-- pokefirered/src/pokemon.c:1796 CreateBoxMon OT_ID_PLAYER_ID
local function repair_own_mon(session, mon)
  if type(mon) ~= "table" then return end
  if not is_own_mon(session, mon) then return end
  local stamped = mon.metLocationName
  local met = rules_of(session).OWN_MON_MET_LOCATION
  if met and mon.metLocation == nil and not (type(stamped) == "string" and stamped ~= "") then
    mon.metLocation = met
  end
  local secret = tonumber(session.secretId)
  if secret and mon.otSecretId == nil then
    local otId = tonumber(mon.otId)
    mon.otSecretId = otId and otId >= 0x10000 and math.floor(otId / 0x10000) % 0x10000 or secret
  end
end

local function each_held_mon(session, fn)
  local seen = {}
  local function visit(mon)
    if type(mon) ~= "table" or seen[mon] then return end
    seen[mon] = true
    fn(mon)
  end
  local function visit_list(list)
    if type(list) ~= "table" then return end
    for _, mon in pairs(list) do visit(mon) end
  end
  visit_list(session.party)
  local storage = session.storage
  for _, box in pairs(storage and storage.boxes or {}) do
    visit_list(type(box) == "table" and box.mons or nil)
  end
  local function visit_held(mon)
    if type(mon) == "table" and (tonumber(mon.species or mon.speciesId) or 0) ~= 0 then visit(mon) end
  end
  local function visit_held_list(list)
    if type(list) ~= "table" then return end
    for _, mon in pairs(list) do visit_held(mon) end
  end
  local md = type(session.modData) == "table" and session.modData or {}
  local okD, Daycare = pcall(require, "src.core.game3.daycare")
  local root = okD and md[Daycare.saveKey(session)] or nil
  -- pokefirered/include/global.h:549
  local dcs = { type(root) == "table" and root.daycare or false, rawget(session, "daycare") or false }
  for _, dc in ipairs(dcs) do
    if type(dc) == "table" then
      for i = 1, Daycare.DAYCARE_MON_COUNT do visit_held(dc[i]) end
      visit_held_list(dc.mons)
    end
  end
  -- pokefirered/src/daycare.c:1563
  local r5s = { type(root) == "table" and root.route5Daycare or false, rawget(session, "route5Daycare") or false }
  for _, r5 in ipairs(r5s) do
    if type(r5) == "table" then visit_held(r5.mon) end
  end
  -- pokefirered/src/load_save.c:160
  visit_held_list(session.savedPlayerParty)
  visit_held_list(md.savedPlayerParty)
end

function Schema.repairOwnMons(session)
  require("src.core.game3.pokemon").playerSecretId(session)
  each_held_mon(session, function(mon) repair_own_mon(session, mon) end)
end

function Schema.reseatLegacySecretIds(session)
  local Identity = require("src.core.TrainerIdentity")
  local sid = Identity.u16(session.secretId)
  local tid = Identity.u16(session.trainerId)
  local name = session.name or session.playerName
  if not sid or not tid or type(name) ~= "string" then return 0 end
  local moved = 0
  local function reseat(mon)
    if type(mon) ~= "table" or mon.otSecretId == nil then return end
    local otName = mon.otName or mon.ot or mon.originalTrainer
    if otName ~= name or Identity.u16(mon.otId) ~= tid then return end
    if Identity.u16(mon.otSecretId) == sid then return end
    local pid = Identity.personality(mon, { id = tid, sid = sid })
    if not pid then return end
    mon.personality, mon.otSecretId, mon.otId = pid, sid, tid
    moved = moved + 1
  end
  each_held_mon(session, reseat)
  return moved
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

-- pokeemerald/include/global.h:206
local function pokedex_view(v)
  if type(v) ~= "table" then return nil end
  local mode, order = math.floor(tonumber(v.mode) or 0), math.floor(tonumber(v.order) or 0)
  if mode < 0 or mode > 1 then mode = 0 end
  if order < 0 or order > 5 then order = 0 end
  return { mode = mode, order = order }
end

-- pokeemerald/src/load_save.c:196
local function object_events(session)
  local Objects = package.loaded["src.core.game3.objects"]
  local Runtime = package.loaded["src.core.game3.runtime"]
  if type(Objects) == "table" and Objects.snapshot and type(Runtime) == "table" and Runtime.getSession
      and Runtime.getSession() == session and Objects._mapId ~= nil and Objects._mapId == session.map then
    return Objects.snapshot()
  end
  local snap = session.objectEvents
  if type(snap) == "table" and snap.mapId == session.map then return snap end
  return nil
end

--- Factory for a pristine New Game after Oak intro finishes.
function Schema.newGame(opts)
  opts = opts or {}
  local version = opts.version or Profile.active().id
  local rules = Schema.rulesFor(version)
  local start = opts.start or MapIds.newGameStart(version)
  local Bag = require("src.core.game3.bag")
  local session = {
    schemaVersion = Schema.VERSION,
    engine = "game3",
    version = version,
    generation = 3,
    party = {},
    bag = Bag.new(),
    dex = { seen = {}, owned = {}, caught = {}, national = false },
    money = tonumber(opts.money) or rules.newGameMoney(),
    coins = 0,
    -- include/global.h:354, src/berry_powder.c:50
    berryPowder = 0,
    name = opts.name or rules.DEFAULT_NAME,
    rivalName = opts.rivalName or rules.DEFAULT_RIVAL,
    gender = opts.gender or 0, -- 0 boy / 1 girl
    map = start.map,
    x = start.x,
    y = start.y,
    facing = start.facing or "down",
    healMap = start.healMap or start.map,
    healX = start.healX or start.x,
    healY = start.healY or start.y,
    stringVars = empty_string_vars(),
    specialVars = empty_special_vars(version),
    flags = rules.newGameFlags(),
    vars = {},
    playtime = { hours = 0, minutes = 0, seconds = 0 },
    easyChatProfile = copy_list(rules.EASY_CHAT_PROFILE),
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
    vsSeeker = rules.newVsSeeker(),
    roamer = nil,
  }
  -- pret new_game.c: SeedWildEncounterRng(Random()) after title SeedRngAndSetTrainerId.
  local Rng = require("src.core.game3.rng")
  if rules.newGameTrainerIds then
    session.trainerId, session.secretId = rules.newGameTrainerIds(opts)
  elseif opts.trainerIdLower ~= nil then
    -- pokeemerald/src/new_game.c:84
    session.trainerId = math.floor(tonumber(opts.trainerIdLower) or 0) % 65536
  else
    session.trainerId = Rng.seedNewGame({ seed = opts.rngSeed })
  end
  -- pokefirered/src/new_game.c:56 InitPlayerTrainerId
  if not rules.newGameTrainerIds then session.secretId = Rng.Random() end
  session.id = session.trainerId
  session.playerId = session.trainerId
  Rng.captureToSession(session)
  local Storage = require("src.core.game3.storage")
  session.storage = Storage.new()
  rules.newGamePcItems(session.storage)
  rules.newGameInit(session, opts)
  require("src.core.game3.save_sections").newGame(session, version)
  if rules.finishNewGameInit then
    rules.finishNewGameInit(session, opts)
    Rng.captureToSession(session)
  end
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
  local warpFlags, continueWarp = rules_of(session).saveWarpFields(session)
  local out = {
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
    pokedex = pokedex_view(session.pokedex),
    map = session.map,
    x = session.x,
    y = session.y,
    facing = session.facing,
    biking = session.biking == true,
    surfing = session.surfing,
    underwater = session.underwater,
    elevation = session.elevation,
    bikeType = session.bikeType,
    healMap = session.healMap,
    healX = session.healX,
    healY = session.healY,
    stringVars = session.stringVars or empty_string_vars(),
    specialVars = session.specialVars or empty_special_vars(session.version),
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
    -- pokeemerald/include/global.h:1018
    objectEvents = object_events(session),
    move_overlay = session.move_overlay or {},
    trainerId = session.trainerId,
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
  require("src.core.game3.save_sections").export(session, out, session.version)
  return out
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
  local version = save.version or Profile.active().id
  local rules = Schema.rulesFor(version)
  local bag = save.bag or save.inventory or {}
  if rules.purgeNoneItemFlags and Schema.hasNoneItemSlot(bag) and type(save.flags) == "table" then
    rules.purgeNoneItemFlags(save)
  end
  if type(bag) ~= "table" or not bag.pockets then
    bag = Bag.migrate(type(bag) == "table" and bag or {})
  else
    Bag.migrate(bag) -- ensure stacks mirror
  end
  local session = {
    schemaVersion = save.schemaVersion or Schema.VERSION,
    engine = save.engine or "game3",
    version = version,
    generation = tonumber(save.generation) or 3,
    -- A party saved with gaps (older PC builds) is closed up on load.
    party = require("src.core.game3.storage").compactParty(save.party or {}),
    bag = bag,
    dex = save.dex or {},
    pokedex = pokedex_view(save.pokedex),
    money = save.money or 0,
    coins = save.coins or 0,
    berryPowder = tonumber(save.berryPowder) or 0,
    berryCrushPressingSpeeds = type(save.berryCrushPressingSpeeds) == "table" and save.berryCrushPressingSpeeds or nil,
    pokemonJumpRecords = type(save.pokemonJumpRecords) == "table" and save.pokemonJumpRecords or nil,
    dodrioBerryPickingRecords = type(save.dodrioBerryPickingRecords) == "table" and save.dodrioBerryPickingRecords or nil,
    registeredTexts = registered_texts_restore(save.registeredTexts),
    trainerNameRecords = trainer_name_records_restore(save.trainerNameRecords),
    name = save.name or rules.DEFAULT_NAME,
    rivalName = save.rivalName or rules.DEFAULT_RIVAL,
    gender = save.gender or 0,
    map = save.map or MapIds.newGameStart(version).map,
    x = save.x or MapIds.newGameStart(version).x,
    y = save.y or MapIds.newGameStart(version).y,
    facing = save.facing or "down",
    biking = save.biking == true,
    surfing = save.surfing,
    underwater = save.underwater,
    elevation = tonumber(save.elevation),
    bikeType = save.bikeType,
    healMap = save.healMap,
    healX = save.healX,
    healY = save.healY,
    stringVars = save.stringVars or empty_string_vars(),
    specialVars = save.specialVars or empty_special_vars(version),
    flags = save.flags or {},
    vars = save.vars or {},
    playtime = save.playTime or save.playtime or { hours = 0, minutes = 0, seconds = 0 },
    easyChatProfile = save.easyChatProfile or copy_list(rules.EASY_CHAT_PROFILE),
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
    -- pokeemerald/include/global.h:1018
    objectEvents = type(save.objectEvents) == "table" and save.objectEvents or nil,
    move_overlay = save.move_overlay or {},
    trainerId = save.trainerId,
    secretId = save.secretId,
    id = save.trainerId,
    playerId = save.trainerId,
    rng = save.rng,
    vsSeeker = rules.restoreVsSeeker(save.vsSeeker),
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
  require("src.core.game3.save_sections").restore(save, session, version)
  require("src.core.game3.save_mon").each(session, require("src.core.game3.save_mon").normalize)
  rules.resetStateOnContinue(session)
  session._savedAvatar = {
    map = session.map, x = session.x, y = session.y,
    surfing = session.surfing, underwater = session.underwater,
    biking = session.biking, bikeType = session.bikeType, elevation = session.elevation,
  }
  local warpFlags = session.specialSaveWarpFlags
  rules.useContinueGameWarp(session)
  if session.specialSaveWarpFlags ~= warpFlags or session._continueWarpDeferred then
    session._savedAvatar = nil
  end
  Schema.ensureMonBalls(session)
  local legacySecret = save.secretId == nil and session.secretId == nil
  Schema.repairOwnMons(session)
  if legacySecret then Schema.reseatLegacySecretIds(session) end
  if rules.repairSaveState then rules.repairSaveState(session) end
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
  local repair = rules_of(session).repairRoamer
  if repair then repair(session) end
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
