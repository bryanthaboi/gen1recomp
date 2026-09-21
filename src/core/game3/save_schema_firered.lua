-- Native Fire Red save schema (engine SaveData JSON). No GBA Flash dumps.

local MapIds = require("src.core.game3.map_ids")
local Options = require("src.core.game3.options")
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
    version = opts.version or "firered",
    generation = 3,
    party = {},
    bag = Bag.new(),
    dex = { seen = {}, owned = {}, national = false },
    money = tonumber(opts.money) or 3000,
    coins = 0,
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
  }
  -- pret new_game.c: SeedWildEncounterRng(Random()) after title SeedRngAndSetTrainerId.
  local Rng = require("src.core.game3.rng")
  session.trainerId = Rng.seedNewGame({ seed = opts.rngSeed })
  -- pokefirered/src/new_game.c:56 InitPlayerTrainerId
  session.secretId = Rng.Random()
  Rng.captureToSession(session)
  local Storage = require("src.core.game3.storage")
  session.storage = Storage.new()
  session.storage.items[1] = { id = 13, qty = 1 } -- pokefirered/src/player_pc.c:100
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
  return {
    schemaVersion = session.schemaVersion or Schema.VERSION,
    engine = "game3",
    version = "firered",
    name = session.name,
    rivalName = session.rivalName,
    gender = session.gender,
    money = session.money,
    coins = session.coins,
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
    -- pokefirered/include/global.h:764
    dynamicWarp = session.dynamicWarp,
    escapeWarp = session.escapeWarp,
    -- pokefirered/include/global.h:770
    flashLevel = tonumber(session.flashLevel),
    move_overlay = session.move_overlay or {},
    trainerId = session.trainerId,
    secretId = session.secretId,
    rng = session.rng,
    vsSeeker = session.vsSeeker,
    mail = mail_export(session),
    questLog = require("src.core.game3.quest_log").export(session),
    modData = session.modData,
    meta = session.meta,
  }
end

function Schema.fromSaveTable(save)
  if type(save) ~= "table" then return Schema.newGame() end
  local Bag = require("src.core.game3.bag")
  local bag = save.bag or save.inventory or {}
  if type(bag) ~= "table" or not bag.pockets then
    bag = Bag.migrate(type(bag) == "table" and bag or {})
  else
    Bag.migrate(bag) -- ensure stacks mirror
  end
  local session = {
    schemaVersion = save.schemaVersion or Schema.VERSION,
    party = save.party or {},
    bag = bag,
    dex = save.dex or {},
    money = save.money or 0,
    coins = save.coins or 0,
    name = save.name or save.playerName or "RED",
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
    -- pokefirered/include/global.h:764
    dynamicWarp = type(save.dynamicWarp) == "table" and save.dynamicWarp or nil,
    escapeWarp = type(save.escapeWarp) == "table" and save.escapeWarp or nil,
    -- pokefirered/include/global.h:770
    flashLevel = tonumber(save.flashLevel),
    move_overlay = save.move_overlay or {},
    trainerId = save.trainerId,
    secretId = save.secretId,
    rng = save.rng,
    vsSeeker = type(save.vsSeeker) == "table" and save.vsSeeker or { steps = 0, charging = 0, rematches = {} },
    mail = mail_restore(save),
    questLog = require("src.core.game3.quest_log").restore(save.questLog),
    modData = type(save.modData) == "table" and save.modData or {},
    meta = save.meta,
  }
  require("src.core.game3.save_mon").each(session, require("src.core.game3.save_mon").normalize)
  reset_state_on_continue(session)
  Schema.ensureMonBalls(session)
  Schema.repairOwnMons(session)
  if type(save.options) == "table" then
    Options.bind(session, save.options)
  else
    Options.ensure(session)
  end
  return session
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
