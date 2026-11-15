
-- Game 3 (FRLG / pokefirered) Field Moves Engine
-- Handles all HM and utility field moves: Cut, Fly, Surf, Strength, Flash,
-- Rock Smash, Waterfall, Dive, Dig, Teleport, Sweet Scent, Softboiled/Milk Drink.
-- Supports dual-trigger architecture:
--   1. Party Menu Submenu (SetUpFieldMove_* / fromMenu)
--   2. Overworld A-Press Collision / Object Interaction (tryOW / EventScript_*)

local function lazyReq(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  return require(name)
end

local Flags = require("src.core.game3.scripting.flags")
local ModRuntime = require("src.mods.Runtime")

local FieldMoves = {}

-- ---------------------------------------------------------------- constants
-- Move IDs (matching pret include/constants/moves.h)
FieldMoves.MOVES = {
  CUT         = 15,
  FLY         = 19,
  SURF        = 57,
  STRENGTH    = 70,
  FLASH       = 148,
  ROCK_SMASH  = 249,
  WATERFALL   = 127,
  DIVE        = 291,
  DIG         = 91,
  TELEPORT    = 100,
  SOFTBOILED  = 135,
  MILK_DRINK  = 208,
  SWEET_SCENT = 230,
  HEADBUTT    = 29,
  SECRET_POWER = 290,
}

-- Move ID reverse lookup table
FieldMoves.MOVE_NAME_BY_ID = {}
for name, id in pairs(FieldMoves.MOVES) do
  FieldMoves.MOVE_NAME_BY_ID[id] = name
end

-- Badge requirement flags in FRLG (matching pret include/constants/flags.h)
-- Boulder=Flash, Cascade=Cut, Thunder=Fly, Rainbow=Strength,
-- Soul=Surf, Marsh=Rock Smash, Volcano=Waterfall, Earth=All Obey / Dive
FieldMoves.BADGE_FLAGS = {
  FLASH      = 0x820, -- FLAG_BADGE01_GET (Boulder Badge)
  CUT        = 0x821, -- FLAG_BADGE02_GET (Cascade Badge)
  FLY        = 0x822, -- FLAG_BADGE03_GET (Thunder Badge)
  STRENGTH   = 0x823, -- FLAG_BADGE04_GET (Rainbow Badge)
  SURF       = 0x824, -- FLAG_BADGE05_GET (Soul Badge)
  ROCK_SMASH = 0x825, -- FLAG_BADGE06_GET (Marsh Badge)
  WATERFALL  = 0x826, -- FLAG_BADGE07_GET (Volcano Badge)
  DIVE       = 0x827, -- FLAG_BADGE08_GET (Earth Badge / RSE Dive)
}

local function activeProfile()
  return lazyReq("src.core.game3.profile").forSession(nil)
end

local function isRse()
  local P = activeProfile()
  return P ~= nil and P.family == "rse"
end
FieldMoves.isRse = isRse

-- System flags
-- include/constants/flags.h:1330
local FRLG_SYS_FLAGS = {
  WHITE_FLUTE_ACTIVE = 0x803,
  BLACK_FLUTE_ACTIVE = 0x804,
  USE_STRENGTH  = 0x805,
  FLASH_ACTIVE  = 0x806,
}

-- pokeemerald/include/constants/flags.h:1398
local RSE_SYS_FLAGS = {
  WHITE_FLUTE_ACTIVE = "FLAG_SYS_ENC_UP_ITEM",
  BLACK_FLUTE_ACTIVE = "FLAG_SYS_ENC_DOWN_ITEM",
  USE_STRENGTH = "FLAG_SYS_USE_STRENGTH",
  FLASH_ACTIVE = "FLAG_SYS_USE_FLASH",
}

FieldMoves.SYS_FLAGS = setmetatable({}, {
  __index = function(_, key)
    local P = activeProfile()
    if P.family ~= "rse" then return FRLG_SYS_FLAGS[key] end
    local name = RSE_SYS_FLAGS[key]
    return name and Flags.forVersion(P.id).IDS[name] or nil
  end,
})

-- src/event_data.c:49
local FRLG_TEMP_SYS_FLAGS = { "WHITE_FLUTE_ACTIVE", "BLACK_FLUTE_ACTIVE", "USE_STRENGTH" }

-- pokeemerald/src/event_data.c:39
local RSE_TEMP_SYS_FLAGS = { "WHITE_FLUTE_ACTIVE", "BLACK_FLUTE_ACTIVE", "USE_STRENGTH", "FLAG_SYS_CTRL_OBJ_DELETE",
  "FLAG_NURSE_UNION_ROOM_REMINDER" }

function FieldMoves.tempSysFlags()
  local P = activeProfile()
  local rse = P.family == "rse"
  local IDS = rse and Flags.forVersion(P.id).IDS or nil
  local out = {}
  for _, key in ipairs(rse and RSE_TEMP_SYS_FLAGS or FRLG_TEMP_SYS_FLAGS) do
    local id = FieldMoves.SYS_FLAGS[key] or (IDS and IDS[key])
    if id then out[#out + 1] = id end
  end
  return out
end

-- Graphics IDs for interactable field objects
local FRLG_GFX_IDS = {
  CUT_TREE          = 95, -- OBJ_EVENT_GFX_CUT_TREE
  ROCK_SMASH_ROCK   = 96, -- OBJ_EVENT_GFX_ROCK_SMASH_ROCK
  PUSHABLE_BOULDER  = 97, -- OBJ_EVENT_GFX_PUSHABLE_BOULDER
}

FieldMoves.GFX_IDS = setmetatable({}, {
  __index = function(_, key)
    local P = lazyReq("src.core.game3.profile").forSession(nil)
    local names = P.field and P.field.fieldMoveGfx
    if not names then return FRLG_GFX_IDS[key] end
    local name = names[key]
    return name and lazyReq("src.core.game3.constants").of(P.id):require("event_objects", name) or nil
  end,
})

function FieldMoves.badgeFlag(badgeKey)
  local Profile = lazyReq("src.core.game3.profile")
  local P = Profile.forSession(nil)
  if (P.family or "frlg") == "frlg" then return FieldMoves.BADGE_FLAGS[badgeKey] end
  for _, b in ipairs(Flags.forVersion(P.id).BADGES) do
    if b.fieldMove == badgeKey then return b.flag end
  end
  return nil
end

-- Sound Effect IDs (matching pret include/constants/songs.h)
local SE_NAMES = {
  USE_ITEM    = "SE_USE_ITEM",
  BANG        = "SE_BANG",
  WARP_OUT    = "SE_WARP_OUT",
  CUT         = "SE_M_CUT",
  ROCK_SMASH  = "SE_M_ROCK_THROW",
  FLASH       = "SE_M_REFLECT",
  SWEET_SCENT = "SE_M_SWEET_SCENT",
  DIVE        = "SE_M_DIVE",
}
FieldMoves.SE = setmetatable({}, {
  __index = function(_, key)
    local name = SE_NAMES[key]
    return name and lazyReq("src.core.game3.se_ids")[name] or nil
  end,
})

-- pokefirered/src/field_specials.c:2296 CutMoveRuinValleyCheck
FieldMoves.RUIN_VALLEY = {
  map = "FR_SIX_ISLAND_RUIN_VALLEY",
  x = 24,
  y = 25,
  facing = "up",
  -- pokefirered/include/constants/flags.h:766
  flag = 0x2E3,
  -- pokefirered/src/field_specials.c:2312
  doorX = 24,
  doorY = 24,
  -- pokefirered/include/constants/metatile_labels.h:207
  doorOpen = 0x358,
}

-- Metatile ID replacement mapping for Cut on grass (fldeff_cut.c sCutGrassMetatileMapping)
FieldMoves.CUT_GRASS_METATILES = {
  [0x00D] = 0x001, -- General: Plain_Grass -> Plain_Mowed
  [0x00A] = 0x013, -- General: ThinTreeTop_Grass -> ThinTreeTop_Mowed
  [0x00B] = 0x00E, -- General: WideTreeTopLeft_Grass -> WideTreeTopLeft_Mowed
  [0x00C] = 0x00F, -- General: WideTreeTopRight_Grass -> WideTreeTopRight_Mowed
  [0x352] = 0x33E, -- CeladonCity: CyclingRoad_Grass -> CyclingRoad_Mowed
  [0x300] = 0x310, -- FuchsiaCity: SafariZoneTreeTopLeft_Grass -> SafariZoneTreeTopLeft_Mowed
  [0x301] = 0x311, -- FuchsiaCity: SafariZoneTreeTopMiddle_Grass -> SafariZoneTreeTopMiddle_Mowed
  [0x302] = 0x312, -- FuchsiaCity: SafariZoneTreeTopRight_Grass -> SafariZoneTreeTopRight_Mowed
  -- pokefirered/include/constants/metatile_labels.h:295
  [0x284] = 0x281,
}

-- Metatile terrain / collision behaviors
-- include/constants/metatile_behaviors.h:14
FieldMoves.BEHAVIORS = {
  GRASS      = { [0x01] = true, [0x02] = true, [0x03] = true },
  WATER      = { [0x10] = true, [0x11] = true, [0x12] = true, [0x13] = true, [0x15] = true },
  WATERFALL  = { [0x13] = true },
  DEEP_WATER = { [0x12] = true },
}

-- src/metatile_behavior.c:594
function FieldMoves.isWaterfallBehavior(beh)
  return beh ~= nil and FieldMoves.BEHAVIORS.WATERFALL[beh] == true
end

-- Map Types (matching pret include/constants/map_types.h)
FieldMoves.MAP_TYPES = {
  TOWN        = 1,
  CITY        = 2,
  ROUTE       = 3,
  UNDERGROUND = 4,
  UNDERWATER  = 5,
  OCEAN_ROUTE = 6,
  UNKNOWN     = 7,
  INDOOR      = 8,
  SECRET_BASE = 9,
}

local TEXT_ROM = {
  -- src/data/party_menu.h:603
  CANT_USE_HERE         = "gText_CantUseHere",
  ALREADY_SURFING       = "gText_AlreadySurfing",
  CUT_NOTHING           = "gText_NothingToCut",
  CANT_SURF_HERE        = "gText_CantSurfHere",
  CURRENT_TOO_FAST      = "gText_CurrentIsTooFast",
  ENJOY_CYCLING         = "gText_EnjoyCycling",
  FLASH_IN_USE          = "gText_InUseAlready_PM",
  NOT_ENOUGH_HP         = "gText_NotEnoughHp",
  -- src/party_menu.c:3928
  BADGE_REQUIRED        = "gText_CantUseUntilNewBadge",

  -- data/scripts/field_moves.inc:47
  ASK_CUT_TREE          = "Text_CutTreeDown",
  TREE_CAN_BE_CUT       = "Text_TreeCanBeCutDown",
  USED_MOVE             = "Text_MonUsedMove",
  ASK_ROCK_SMASH        = "Text_UseRockSmash",
  MON_MAY_SMASH_ROCK    = "Text_MonMaySmashRock",
  ASK_STRENGTH          = "Text_UseStrength",
  MON_MAY_PUSH_BOULDER  = "Text_MonMayPushBoulder",
  USED_STRENGTH         = "Text_MonUsedStrengthCanMoveBoulders",
  STRENGTH_ACTIVE       = "Text_StrengthMadeMovingBouldersPossible",
  ASK_WATERFALL         = "Text_UseWaterfall",
  USED_WATERFALL        = "Text_MonUsedWaterfall",
  CANT_WATERFALL        = "Text_WallOfWaterCrashingDown",
  NO_SWEET_SCENT_MONS   = "Text_LooksLikeNothingHere",

  -- data/text/surf.inc:1
  ASK_SURF              = "Text_WantToSurf",
  USED_SURF             = "Text_UsedSurf",
  CANT_SURF_CURRENT     = "Text_CurrentTooFast",
}
-- pokeemerald/data/scripts/field_move_scripts.inc:2
local TEXT_RSE = {
  ASK_CUT_TREE          = "Text_WantToCut",
  TREE_CAN_BE_CUT       = "Text_CantCut",
  USED_MOVE             = "Text_MonUsedFieldMove",
  ASK_ROCK_SMASH        = "Text_WantToSmash",
  MON_MAY_SMASH_ROCK    = "Text_CantSmash",
  ASK_STRENGTH          = "Text_WantToStrength",
  MON_MAY_PUSH_BOULDER  = "Text_CantStrength",
  USED_STRENGTH         = "Text_MonUsedStrength",
  STRENGTH_ACTIVE       = "Text_StrengthActivated",
  ASK_WATERFALL         = "Text_WantToWaterfall",
  USED_WATERFALL        = "Text_MonUsedWaterfall",
  CANT_WATERFALL        = "Text_CantWaterfall",
  NO_SWEET_SCENT_MONS   = "Text_FailSweetScent",
  ASK_DIVE              = "Text_WantToDive",
  CANT_DIVE             = "Text_CantDive",
  USED_DIVE             = "Text_MonUsedDive",
  ASK_SURFACE           = "Text_WantToSurface",
  CANT_SURFACE          = "Text_CantSurface",
  -- pokeemerald/data/text/surf.inc:1
  ASK_SURF              = "gText_WantToUseSurf",
  USED_SURF             = "gText_PlayerUsedSurf",
}

local function textKey(key)
  if isRse() and TEXT_RSE[key] then return TEXT_RSE[key] end
  return TEXT_ROM[key]
end
FieldMoves.textKey = textKey

FieldMoves.TEXT = setmetatable({}, {
  __index = function(_, key)
    local k = textKey(key)
    if not k then return nil end
    return lazyReq("src.core.game3.rom_text").ascii(k)
  end,
})

-- data/scripts/field_moves.inc:8 bufferpartymonnick STR_VAR_1, buffermovename STR_VAR_2
function FieldMoves.monText(key, monName, moveId)
  local moveName = moveId and lazyReq("src.core.game3.pokemon").moveName(moveId) or nil
  return lazyReq("src.core.game3.rom_text").ascii(textKey(key), { stringVars = { monName, moveName } })
end

-- ---------------------------------------------------------------- helpers
--- Normalize move identifier to numeric ID
function FieldMoves.normalizeMoveId(move)
  if type(move) == "number" then return move end
  if type(move) == "string" then
    local upper = move:upper():gsub("%s+", "_"):gsub("%-", "_")
    if FieldMoves.MOVES[upper] then return FieldMoves.MOVES[upper] end
    if upper == "SOFT_BOILED" or upper == "SOFTBOILED" then return FieldMoves.MOVES.SOFTBOILED end
    if upper == "ROCKSMASH" or upper == "ROCK_SMASH" then return FieldMoves.MOVES.ROCK_SMASH end
    if upper == "SWEETSCENT" or upper == "SWEET_SCENT" then return FieldMoves.MOVES.SWEET_SCENT end
    if upper == "MILKDRINK" or upper == "MILK_DRINK" then return FieldMoves.MOVES.MILK_DRINK end
  end
  if type(move) == "table" and move.id then
    return FieldMoves.normalizeMoveId(move.id)
  end
  return nil
end

--- Check if the party has a mon knowing the given move
-- Returns: monTable, slotIndex (0-based) or nil, 6
local function findMoveUser(party, moveIdentifier)
  local targetId = FieldMoves.normalizeMoveId(moveIdentifier)
  if not targetId or not party then return nil, 6 end

  for slot = 1, #party do
    local mon = party[slot]
    if mon and not mon.isEgg and not mon.egg then
      local moves = mon.moves or {}
      for _, m in ipairs(moves) do
        local mId = FieldMoves.normalizeMoveId(m)
        if mId == targetId then
          return mon, slot - 1
        end
      end
    end
  end
  return nil, 6
end

local function partyMoveUserVanilla(moveId, ctx)
  return (findMoveUser(ctx and ctx.party, moveId))
end

function FieldMoves.partyMoveUser(party, moveIdentifier, fieldCtx)
  if not ModRuntime.wantsHook("fieldmove.eligibility") then
    return findMoveUser(party, moveIdentifier)
  end
  local moveId = FieldMoves.normalizeMoveId(moveIdentifier)
  if not moveId or not party then return nil, 6 end
  local runtime = package.loaded["src.core.game3.runtime"]
  local game = fieldCtx and fieldCtx.game or runtime and runtime._game
  local mon = ModRuntime.call("fieldmove.eligibility", partyMoveUserVanilla, moveId, {
    save = fieldCtx and fieldCtx.save or game and game.save,
    data = fieldCtx and fieldCtx.data or game and game.data,
    party = party,
    moveId = moveId,
  })
  if type(mon) == "table" and not mon.isEgg and not mon.egg then
    for slot = 1, #party do
      if rawequal(party[slot], mon) then return mon, slot - 1 end
    end
  end
  return nil, 6
end

--- Check if badge is owned in store / session / save
function FieldMoves.hasBadge(ctxOrStore, badgeKey)
  local flagId = FieldMoves.badgeFlag(badgeKey)
  if not flagId then return true end

  -- Direct flag store check
  if ctxOrStore and ctxOrStore.flags then
    return Flags.getFlag(ctxOrStore, nil, flagId)
  end

  -- Context table with store or session
  if ctxOrStore and ctxOrStore.store then
    return Flags.getFlag(ctxOrStore.store, ctxOrStore.ctx, flagId)
  end

  -- Session with badges / flags
  if ctxOrStore and ctxOrStore.session then
    local s = ctxOrStore.session
    if s.flags and s.flags[flagId] ~= nil then return s.flags[flagId] == true end
    if s.badges and type(s.badges) == "table" then
      return s.badges[badgeKey] == true or s.badges[flagId] == true
    end
  end

  -- Host save check (player.badges or engineFlags)
  local save = ctxOrStore and (ctxOrStore.save or ctxOrStore)
  if save and save.player and save.player.badges then
    local b = save.player.badges
    if b[badgeKey] ~= nil then return b[badgeKey] == true end
    if b[flagId] ~= nil then return b[flagId] == true end
  end

  return false
end

--- Check if outdoors (Fly / Teleport allowed)
function FieldMoves.isOutdoors(mapType)
  local mt = tonumber(mapType) or 0
  return mt == FieldMoves.MAP_TYPES.TOWN
      or mt == FieldMoves.MAP_TYPES.CITY
      or mt == FieldMoves.MAP_TYPES.ROUTE
      or mt == FieldMoves.MAP_TYPES.OCEAN_ROUTE
end

--- Check if dungeon / cave map (Dig / Escape Rope allowed)
function FieldMoves.isDungeon(mapType, isCave)
  local mt = tonumber(mapType) or 0
  return isCave == true or mt == FieldMoves.MAP_TYPES.UNDERGROUND
end

--- Get mon nickname for text formatting
-- pokefirered/src/party_menu.c:1511 GetMonNickname
function FieldMoves.getMonName(mon)
  if not mon then return "POKéMON" end
  local okP, Pokemon = pcall(lazyReq, "src.core.game3.pokemon")
  if okP and Pokemon and Pokemon.displayMonName then
    return Pokemon.displayMonName(mon)
  end
  local nick = mon.nickname
  if type(nick) == "string" and nick ~= "" then return nick end
  if type(mon.name) == "string" and mon.name ~= "" then return mon.name end
  return mon.species or "POKéMON"
end

-- ---------------------------------------------------------------- menu paths (SetUpFieldMove_*)

-- pokefirered/src/field_specials.c:2296 CutMoveRuinValleyCheck
function FieldMoves.ruinValleyCutCheck(ctx)
  ctx = ctx or {}
  local RV = FieldMoves.RUIN_VALLEY
  local store = ctx.store
  if store and Flags.getFlag(store, ctx.ctx, RV.flag) == true then return false end
  local session = ctx.session
  if session and session.flags and session.flags[RV.flag] then return false end
  local mapId = ctx.mapId or (session and session.map)
  if mapId ~= RV.map then return false end
  local x, y, facing = ctx.x, ctx.y, ctx.facing
  if x == nil or y == nil or facing == nil then
    local P = package.loaded["src.core.game3.player"]
    if not P then return false end
    x, y, facing = P.cellX, P.cellY, P.facing
  end
  return x == RV.x and y == RV.y and facing == RV.facing
end

--- Cut from Party Menu
function FieldMoves.cutFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "CUT") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "CUT" }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "CUT", ctx)

  -- pokefirered/src/fldeff_cut.c:123 SetUpFieldMove_Cut
  if ctx.isDottedHoleDoor or FieldMoves.ruinValleyCutCheck(ctx) then
    return {
      ok = true,
      action = "dotted_hole",
      mon = mon,
      se = FieldMoves.SE.CUT,
    }
  end

  -- 1) Check facing Cut Tree object
  if ctx.facingObject and (ctx.facingObject.gfx == FieldMoves.GFX_IDS.CUT_TREE
      or ctx.facingObject.graphicsId == FieldMoves.GFX_IDS.CUT_TREE) then
    return {
      ok = true,
      action = "cut_tree",
      target = ctx.facingObject,
      mon = mon,
      se = FieldMoves.SE.CUT,
    }
  end

  -- pokeemerald/src/fldeff_cut.c:156
  if isRse() and ctx.cutGrassQuery then
    local plan = FieldMoves.cutGrassPlan(ctx.cutGrassQuery, ctx.hyperCutter == true)
    if plan then
      return { ok = true, action = "cut_grass", mon = mon, se = FieldMoves.SE.CUT, cutPlan = plan }
    end
    return { ok = false, text = FieldMoves.TEXT.CUT_NOTHING }
  end

  -- 2) Check facing / standing 3x3 grass
  if ctx.hasCuttableGrass then
    return {
      ok = true,
      action = "cut_grass",
      mon = mon,
      se = FieldMoves.SE.CUT,
    }
  end

  return { ok = false, text = FieldMoves.TEXT.CUT_NOTHING }
end

--- Flash from Party Menu
function FieldMoves.flashFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "FLASH") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "FLASH" }
  end

  -- pokeemerald/src/fldeff_flash.c:76
  if lazyReq("src.core.game3.constants").versionOf(ctx.session) == "emerald"
      and lazyReq("src.core.game3.braille_field").shouldDoRegisteel(ctx.session) then
    return { ok = true, action = "braille_registeel", mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "FLASH", ctx) }
  end

  -- src/party_menu.c:4047 DisplayCantUseFlashMessage
  if ctx.isFlashActive or (ctx.store and Flags.getFlag(ctx.store, ctx.ctx, FieldMoves.SYS_FLAGS.FLASH_ACTIVE)) then
    return { ok = false, text = FieldMoves.TEXT.FLASH_IN_USE }
  end

  if not ctx.isDarkCave and not ctx.isCave then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "FLASH", ctx)

  -- data/scripts/flash.inc:1 EventScript_FldEffFlash
  return {
    ok = true,
    action = "flash",
    mon = mon,
    se = FieldMoves.SE.FLASH,
    flag = FieldMoves.SYS_FLAGS.FLASH_ACTIVE,
  }
end

--- Surf from Party Menu
function FieldMoves.surfFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "SURF") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "SURF" }
  end

  if ctx.isSurfing then
    return { ok = false, text = FieldMoves.TEXT.ALREADY_SURFING }
  end

  -- src/party_menu.c:4077 DisplayCantUseSurfMessage
  if ctx.isFastCurrent then
    return { ok = false, text = FieldMoves.TEXT.CURRENT_TOO_FAST }
  end

  if not ctx.isFacingWater then
    local MapCatalog = lazyReq("src.import.gba.map_catalog")
    local map = ctx.mapId or (ctx.session and ctx.session.map)
    if map == MapCatalog.pretToEngine("Route17") or map == MapCatalog.pretToEngine("Route18") then
      return { ok = false, text = FieldMoves.TEXT.ENJOY_CYCLING }
    end
    return { ok = false, text = FieldMoves.TEXT.CANT_SURF_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "SURF", ctx)

  -- src/party_menu.c:4055 FieldCallback_Surf
  return {
    ok = true,
    action = "surf",
    mon = mon,
  }
end

--- Strength from Party Menu
function FieldMoves.strengthFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "STRENGTH") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "STRENGTH" }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "STRENGTH", ctx)
  local RsBraille = lazyReq("src.core.game3.braille_field_rs")
  if RsBraille.isRs(ctx.session) then
    -- pokeruby/src/fldeff_strength.c:47
    if RsBraille.shouldDoStrength(ctx.session) then
      return { ok = true, action = "braille_rs_strength", mon = mon }
    end
    if not ctx.facingObject or (ctx.facingObject.gfx ~= FieldMoves.GFX_IDS.PUSHABLE_BOULDER
        and ctx.facingObject.graphicsId ~= FieldMoves.GFX_IDS.PUSHABLE_BOULDER) then
      return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
    end
  end
  local monName = FieldMoves.getMonName(mon)

  return {
    ok = true,
    action = "strength",
    mon = mon,
    flag = FieldMoves.SYS_FLAGS.USE_STRENGTH,
    text = FieldMoves.monText("USED_STRENGTH", monName),
  }
end

--- Rock Smash from Party Menu
function FieldMoves.rockSmashFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "ROCK_SMASH") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "ROCK_SMASH" }
  end

  -- pokeemerald/src/fldeff_rocksmash.c:125
  if lazyReq("src.core.game3.constants").versionOf(ctx.session) == "emerald"
      and lazyReq("src.core.game3.braille_field").shouldDoRegirock(ctx.session) then
    return { ok = true, action = "braille_regirock", mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "ROCK_SMASH", ctx) }
  end

  if not ctx.facingObject or (ctx.facingObject.gfx ~= FieldMoves.GFX_IDS.ROCK_SMASH_ROCK
      and ctx.facingObject.graphicsId ~= FieldMoves.GFX_IDS.ROCK_SMASH_ROCK) then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "ROCK_SMASH", ctx)

  return {
    ok = true,
    action = "rock_smash",
    target = ctx.facingObject,
    mon = mon,
    se = FieldMoves.SE.ROCK_SMASH,
  }
end

--- Waterfall from Party Menu
-- src/party_menu.c:4118
function FieldMoves.waterfallFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "WATERFALL") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "WATERFALL" }
  end

  if not ctx.isSurfing or not ctx.isFacingWaterfall or ctx.facing ~= "up" then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "WATERFALL", ctx)

  return {
    ok = true,
    action = "waterfall",
    mon = mon,
  }
end

--- Fly from Party Menu
function FieldMoves.flyFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "FLY") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "FLY" }
  end

  -- pokeruby/src/pokemon_menu.c:833
  local RsBraille = lazyReq("src.core.game3.braille_field_rs")
  if RsBraille.isRs(ctx.session) and RsBraille.shouldDoFly(ctx.session) then
    return { ok = true, action = "braille_rs_fly", mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "FLY", ctx) }
  end

  if not FieldMoves.isOutdoors(ctx.mapType) then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "FLY", ctx)

  return {
    ok = true,
    action = "fly",
    mon = mon,
  }
end

--- Dig from Party Menu
function FieldMoves.digFromMenu(ctx)
  if not FieldMoves.isDungeon(ctx.mapType, ctx.isCave) or not ctx.canEscapeRope then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "DIG", ctx)
  local RsBraille = lazyReq("src.core.game3.braille_field_rs")
  if RsBraille.isRs(ctx.session) and RsBraille.shouldDoDig(ctx.session) then
    return { ok = true, action = "braille_rs_dig", mon = mon, warp = ctx.escapeWarp }
  end

  return {
    ok = true,
    action = "dig",
    mon = mon,
    warp = ctx.escapeWarp,
  }
end

--- Teleport from Party Menu
function FieldMoves.teleportFromMenu(ctx)
  if not FieldMoves.isOutdoors(ctx.mapType) then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "TELEPORT", ctx)

  return {
    ok = true,
    action = "teleport",
    mon = mon,
    se = FieldMoves.SE.WARP_OUT,
    warp = ctx.lastHealWarp or ctx.respawnPoint,
  }
end

local function hasMovePp(mon, moveIdentifier)
  if not mon then return false end
  local targetId = FieldMoves.normalizeMoveId(moveIdentifier)
  local moves = mon.moves or {}
  for idx, m in ipairs(moves) do
    local mId = FieldMoves.normalizeMoveId(m)
    if mId == targetId then
      if type(m) == "table" and m.pp ~= nil then
        return (tonumber(m.pp) or 0) > 0
      end
      if type(mon.pp) == "table" and mon.pp[idx] ~= nil then
        return (tonumber(mon.pp[idx]) or 0) > 0
      end
      return true
    end
  end
  return false
end
FieldMoves.hasMovePp = hasMovePp

--- Sweet Scent from Party Menu
function FieldMoves.sweetScentFromMenu(ctx)
  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "SWEET_SCENT", ctx)
  if not mon then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  if not hasMovePp(mon, "SWEET_SCENT") then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  return {
    ok = true,
    action = "sweet_scent",
    mon = mon,
    se = FieldMoves.SE.SWEET_SCENT,
    hasEncounter = ctx.hasWildEncounters == true,
    failKey = FieldMoves.textKey("NO_SWEET_SCENT_MONS"),
  }
end

--- Softboiled / Milk Drink from Party Menu
function FieldMoves.softboiledFromMenu(ctx)
  local mon = ctx.mon
  if not mon then return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE } end

  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 0
  local curHp = mon.hp or 0
  local cost = math.floor(maxHp / 5)

  if curHp <= cost or cost <= 0 then
    return { ok = false, text = FieldMoves.TEXT.NOT_ENOUGH_HP }
  end

  return {
    ok = true,
    action = "softboiled",
    mon = mon,
    cost = cost,
  }
end

--- Validate softboiled recipient mon
function FieldMoves.softboiledTargetOk(userMon, targetMon)
  if not userMon or not targetMon then return false end
  if userMon == targetMon then return false end
  if targetMon.isEgg or targetMon.egg then return false end

  local curHp = targetMon.hp or 0
  local maxHp = targetMon.maxHp or (targetMon.stats and targetMon.stats.hp) or 0
  return curHp > 0 and curHp < maxHp
end

--- Execute softboiled HP transfer
function FieldMoves.softboiledTransfer(userMon, targetMon, cost)
  if not FieldMoves.softboiledTargetOk(userMon, targetMon) then
    return false, nil, nil
  end

  cost = cost or math.floor((userMon.maxHp or 1) / 5)
  local userHpBefore = userMon.hp or 0
  local targetHpBefore = targetMon.hp or 0
  local targetMaxHp = targetMon.maxHp or (targetMon.stats and targetMon.stats.hp) or targetHpBefore

  userMon.hp = math.max(0, userHpBefore - cost)
  targetMon.hp = math.min(targetMaxHp, targetHpBefore + cost)

  return true, userMon.hp, targetMon.hp
end

-- pokeemerald/src/party_menu.c:3916 SetUpFieldMove_Dive
function FieldMoves.diveFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "DIVE") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "DIVE" }
  end
  local Dive = lazyReq("src.core.game3.dive")
  local code, dest = Dive.trySetDiveWarp(ctx.session)
  if code == 0 then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  local mon, slot = ctx.mon, nil
  if not mon then mon, slot = FieldMoves.partyMoveUser(ctx.party, "DIVE", ctx) end
  return { ok = true, action = "dive", mon = mon, slot = slot, diveCode = code, dest = dest }
end

-- pokeemerald/src/fldeff_misc.c:547 SetUpFieldMove_SecretPower
function FieldMoves.secretPowerFromMenu(ctx)
  local Rse = lazyReq("src.core.game3.rse.init")
  local r, handled = Rse.call("secretBaseField", "setUpFieldMove", "SetUpFieldMove_SecretPower", nil, ctx)
  if handled and type(r) == "table" and r.ok then
    r.action = r.action or "secret_power"
    r.mon = r.mon or ctx.mon
    return r
  end
  return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
end

-- pokeemerald/src/party_menu.c:120
local RSE_MENU_ORDER = {
  "CUT", "FLASH", "ROCK_SMASH", "STRENGTH", "SURF", "FLY", "DIVE", "WATERFALL",
  "TELEPORT", "DIG", "SECRET_POWER", "MILK_DRINK", "SOFTBOILED", "SWEET_SCENT",
}

function FieldMoves.menuOrder()
  if isRse() then return RSE_MENU_ORDER end
  return nil
end

-- pokeemerald/src/party_menu.c:3725
function FieldMoves.menuBadgeKey(moveName)
  if not isRse() then return nil end
  for i = 1, 8 do
    if RSE_MENU_ORDER[i] == moveName then return moveName end
  end
  return nil
end

-- Jumptable of menu field move handlers
FieldMoves.MENU_HANDLERS = {
  [FieldMoves.MOVES.CUT]         = FieldMoves.cutFromMenu,
  [FieldMoves.MOVES.FLY]         = FieldMoves.flyFromMenu,
  [FieldMoves.MOVES.SURF]        = FieldMoves.surfFromMenu,
  [FieldMoves.MOVES.STRENGTH]    = FieldMoves.strengthFromMenu,
  [FieldMoves.MOVES.FLASH]       = FieldMoves.flashFromMenu,
  [FieldMoves.MOVES.ROCK_SMASH]  = FieldMoves.rockSmashFromMenu,
  [FieldMoves.MOVES.WATERFALL]   = FieldMoves.waterfallFromMenu,
  [FieldMoves.MOVES.DIG]         = FieldMoves.digFromMenu,
  [FieldMoves.MOVES.TELEPORT]    = FieldMoves.teleportFromMenu,
  [FieldMoves.MOVES.SWEET_SCENT] = FieldMoves.sweetScentFromMenu,
  [FieldMoves.MOVES.SOFTBOILED]  = FieldMoves.softboiledFromMenu,
  [FieldMoves.MOVES.MILK_DRINK]  = FieldMoves.softboiledFromMenu,
  [FieldMoves.MOVES.DIVE]        = FieldMoves.diveFromMenu,
  [FieldMoves.MOVES.SECRET_POWER] = FieldMoves.secretPowerFromMenu,
}

--- Universal entry point for party menu field move execution
function FieldMoves.fromMenu(moveIdentifier, ctx)
  local moveId = FieldMoves.normalizeMoveId(moveIdentifier)
  local handler = moveId and FieldMoves.MENU_HANDLERS[moveId]
  if not handler then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return handler(ctx)
end

-- ---------------------------------------------------------------- overworld A-press (EventScript_*)

--- Cut Tree Interaction (EventScript_CutTree)
function FieldMoves.tryCutOW(ctx)
  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "CUT", ctx)
  local hasBadge = FieldMoves.hasBadge(ctx, "CUT")

  if not mon or not hasBadge then
    return {
      ok = false,
      text = FieldMoves.TEXT.TREE_CAN_BE_CUT,
    }
  end

  local monName = FieldMoves.getMonName(mon)
  return {
    ok = true,
    ask = FieldMoves.TEXT.ASK_CUT_TREE,
    action = "cut_tree",
    mon = mon,
    slot = slot,
    se = FieldMoves.SE.CUT,
    target = ctx.facingObject,
    text = FieldMoves.monText("USED_MOVE", monName, FieldMoves.MOVES.CUT),
  }
end

--- Rock Smash Interaction (EventScript_RockSmash)
function FieldMoves.tryRockSmashOW(ctx)
  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "ROCK_SMASH", ctx)
  local hasBadge = FieldMoves.hasBadge(ctx, "ROCK_SMASH")

  if not mon or not hasBadge then
    return {
      ok = false,
      text = FieldMoves.TEXT.MON_MAY_SMASH_ROCK,
    }
  end

  local monName = FieldMoves.getMonName(mon)
  return {
    ok = true,
    ask = FieldMoves.TEXT.ASK_ROCK_SMASH,
    action = "rock_smash",
    mon = mon,
    slot = slot,
    se = FieldMoves.SE.ROCK_SMASH,
    target = ctx.facingObject,
    text = FieldMoves.monText("USED_MOVE", monName, FieldMoves.MOVES.ROCK_SMASH),
  }
end

--- Strength Boulder Interaction (EventScript_StrengthBoulder)
function FieldMoves.tryStrengthOW(ctx)
  -- pokeemerald/data/scripts/field_move_scripts.inc:122
  if isRse() and not FieldMoves.hasBadge(ctx, "STRENGTH") then
    return { ok = false, text = FieldMoves.TEXT.MON_MAY_PUSH_BOULDER }
  end
  local isStrengthActive = ctx.isStrengthActive or (ctx.store and Flags.getFlag(ctx.store, ctx.ctx, FieldMoves.SYS_FLAGS.USE_STRENGTH))
  if isStrengthActive then
    return {
      ok = false,
      alreadyActive = true,
      text = FieldMoves.TEXT.STRENGTH_ACTIVE,
    }
  end

  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "STRENGTH", ctx)
  local hasBadge = FieldMoves.hasBadge(ctx, "STRENGTH")

  if not mon or not hasBadge then
    return {
      ok = false,
      text = FieldMoves.TEXT.MON_MAY_PUSH_BOULDER,
    }
  end

  local monName = FieldMoves.getMonName(mon)
  return {
    ok = true,
    ask = FieldMoves.TEXT.ASK_STRENGTH,
    action = "strength",
    mon = mon,
    slot = slot,
    flag = FieldMoves.SYS_FLAGS.USE_STRENGTH,
    text = FieldMoves.monText("USED_STRENGTH", monName),
  }
end

--- Surf Collision Interaction
function FieldMoves.trySurfOW(ctx)
  if ctx.isSurfing then return { ok = false } end
  if ctx.isFastCurrent then
    return { ok = false, text = FieldMoves.TEXT.CANT_SURF_CURRENT }
  end
  if not ctx.isFacingWater then return { ok = false } end

  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "SURF", ctx)
  local hasBadge = FieldMoves.hasBadge(ctx, "SURF")

  if not mon or not hasBadge then
    -- Silent failure in GBA / Gen2 for pressing A on water without Surf
    return { ok = false }
  end

  local monName = FieldMoves.getMonName(mon)
  return {
    ok = true,
    ask = FieldMoves.TEXT.ASK_SURF,
    action = "surf",
    mon = mon,
    slot = slot,
    text = FieldMoves.monText("USED_SURF", monName),
  }
end

--- Waterfall Collision Interaction (EventScript_Waterfall)
-- src/field_control_avatar.c:608, data/scripts/field_moves.inc:178
function FieldMoves.tryWaterfallOW(ctx)
  if not ctx.isFacingWaterfall then
    return { ok = false }
  end

  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "WATERFALL", ctx)
  local hasBadge = FieldMoves.hasBadge(ctx, "WATERFALL")
  local surfingNorth = ctx.isSurfing and ctx.facing == "up"

  if not mon or not hasBadge or not surfingNorth then
    return {
      ok = false,
      text = FieldMoves.TEXT.CANT_WATERFALL,
    }
  end

  local monName = FieldMoves.getMonName(mon)
  return {
    ok = true,
    ask = FieldMoves.TEXT.ASK_WATERFALL,
    action = "waterfall",
    mon = mon,
    slot = slot,
    text = FieldMoves.monText("USED_WATERFALL", monName),
  }
end

-- ---------------------------------------------------------------- map & metatile modifications

--- Mows grass in a 3x3 grid centered on (cx, cy)
-- `getMetatileFn(x, y)`: returns numeric metatileId
-- `setMetatileFn(x, y, newMetatileId)`: applies new metatileId
-- Returns count of cut tiles
-- pokefirered/src/fldeff_cut.c:200
function FieldMoves.mowGrass3x3(cx, cy, getMetatileFn, setMetatileFn, sameElevationFn)
  if not getMetatileFn or not setMetatileFn then return 0 end
  local count = 0

  for dy = -1, 1 do
    for dx = -1, 1 do
      local x = cx + dx
      local y = cy + dy
      if not sameElevationFn or sameElevationFn(x, y) then
        local mid = getMetatileFn(x, y)
        -- pokefirered/src/fldeff_cut.c:237
        local newMid = mid and FieldMoves.CUT_GRASS_METATILES[mid]
        if newMid then
          setMetatileFn(x, y, newMid)
          count = count + 1
        end
      end
    end
  end

  return count
end

-- pokeemerald/src/fldeff_cut.c:71
local HYPER_CUT = {
  { -2, -2, { 1 } }, { -1, -2, { 1 } }, { 0, -2, { 2 } }, { 1, -2, { 3 } }, { 2, -2, { 3 } },
  { -2, -1, { 1 } }, { 2, -1, { 3 } }, { -2, 0, { 4 } }, { 2, 0, { 6 } }, { -2, 1, { 7 } },
  { 2, 1, { 9 } }, { -2, 2, { 7 } }, { -1, 2, { 7 } }, { 0, 2, { 8 } }, { 1, 2, { 9 } }, { 2, 2, { 9 } },
}

local function mbIs(beh, ...)
  if beh == nil then return false end
  local MB = lazyReq("src.core.game3.mb")
  for i = 1, select("#", ...) do
    local id = MB.id((select(i, ...)))
    if id ~= nil and beh == id then return true end
  end
  return false
end

-- pokeemerald/src/metatile_behavior.c:175
function FieldMoves.isPokeGrass(beh) return mbIs(beh, "TALL_GRASS", "LONG_GRASS") end
-- pokeemerald/src/metatile_behavior.c:753
function FieldMoves.isAshGrass(beh) return mbIs(beh, "ASHGRASS") end
-- pokeemerald/src/metatile_behavior.c:1269
function FieldMoves.isCuttableGrass(beh)
  return mbIs(beh, "TALL_GRASS", "LONG_GRASS", "ASHGRASS", "LONG_GRASS_SOUTH_EDGE")
end

-- pokeemerald/src/fldeff_cut.c:138 SetUpFieldMove_Cut
function FieldMoves.cutGrassPlan(q, hyper)
  local tiles = {}
  local cutTiles = {}
  local found = false
  for i = 0, 2 do
    local y = i - 1 + q.y
    for j = 0, 2 do
      local x = j - 1 + q.x
      if q.elevationAt(x, y) == q.elevation then
        local beh = q.behavior(x, y)
        if FieldMoves.isPokeGrass(beh) or FieldMoves.isAshGrass(beh) then
          tiles[6 + i * 5 + j] = true
          found = true
        end
        if q.impassable(x, y) then
          cutTiles[i * 3 + j] = false
        else
          cutTiles[i * 3 + j] = true
          if FieldMoves.isCuttableGrass(beh) then tiles[6 + i * 5 + j] = true end
        end
      else
        cutTiles[i * 3 + j] = false
      end
    end
  end
  if hyper then
    for _, h in ipairs(HYPER_CUT) do
      local x, y = q.x + h[1], q.y + h[2]
      local ok = true
      for _, need in ipairs(h[3]) do
        if not cutTiles[need - 1] then ok = false break end
      end
      if ok and q.elevationAt(x, y) == q.elevation then
        local id = h[2] * 5 + 12 + h[1]
        local beh = q.behavior(x, y)
        if FieldMoves.isPokeGrass(beh) or FieldMoves.isAshGrass(beh) then
          tiles[id] = true
          found = true
        elseif FieldMoves.isCuttableGrass(beh) then
          tiles[id] = true
        end
      end
    end
  end
  if not found then return nil end
  local out = { side = hyper and 5 or 3, reach = hyper and 2 or 1, cells = {} }
  for i = 0, 24 do
    if tiles[i] then out.cells[#out.cells + 1] = { x = q.x + (i % 5) - 2, y = q.y + math.floor(i / 5) - 2 } end
  end
  return out
end

local function label(name)
  local P = activeProfile()
  return lazyReq("src.core.game3.constants").of(P.id):require("metatile_labels", "METATILE_" .. name)
end

-- pokeemerald/src/fldeff_cut.c:354 SetCutGrassMetatile
local RSE_CUT_GRASS = {
  { { "Fortree_LongGrass_Root", "General_LongGrass", "General_TallGrass" }, "General_Grass" },
  { { "General_TallGrass_TreeLeft" }, "General_Grass_TreeLeft" },
  { { "General_TallGrass_TreeRight" }, "General_Grass_TreeRight" },
  { { "Fortree_SecretBase_LongGrass_BottomLeft" }, "Fortree_SecretBase_LongGrass_TopLeft" },
  { { "Fortree_SecretBase_LongGrass_BottomMid" }, "Fortree_SecretBase_LongGrass_TopMid" },
  { { "Fortree_SecretBase_LongGrass_BottomRight" }, "Fortree_SecretBase_LongGrass_TopRight" },
  { { "Lavaridge_NormalGrass", "Lavaridge_AshGrass" }, "Lavaridge_LavaField" },
  { { "Fallarbor_NormalGrass", "Fallarbor_AshGrass" }, "Fallarbor_AshField" },
  { { "General_TallGrass_TreeUp" }, "General_Grass_TreeUp" },
}

function FieldMoves.cutGrassMetatile(mid)
  for _, row in ipairs(RSE_CUT_GRASS) do
    for _, from in ipairs(row[1]) do
      if mid == label(from) then return label(row[2]) end
    end
  end
  return nil
end

-- pokeemerald/src/fldeff_cut.c:417 SetCutGrassMetatiles
function FieldMoves.fixLongGrass(x, y, side, getMid, setMid)
  local longGrass, grass, root = label("General_LongGrass"), label("General_Grass"), label("Fortree_LongGrass_Root")
  local topL, topM, topR = label("Fortree_SecretBase_LongGrass_TopLeft"), label("Fortree_SecretBase_LongGrass_TopMid"),
    label("Fortree_SecretBase_LongGrass_TopRight")
  local botL, botM, botR = label("Fortree_SecretBase_LongGrass_BottomLeft"),
    label("Fortree_SecretBase_LongGrass_BottomMid"), label("Fortree_SecretBase_LongGrass_BottomRight")
  local lowerY = y + side
  for i = 0, side - 1 do
    local cx = x + i
    if getMid(cx, y) == longGrass then
      local below = getMid(cx, y + 1)
      if below == grass then setMid(cx, y + 1, root)
      elseif below == topL then setMid(cx, y + 1, botL)
      elseif below == topM then setMid(cx, y + 1, botM)
      elseif below == topR then setMid(cx, y + 1, botR) end
    end
    if getMid(cx, lowerY) == grass then
      if getMid(cx, lowerY + 1) == root then setMid(cx, lowerY + 1, grass) end
      if getMid(cx, lowerY + 1) == botL then setMid(cx, lowerY + 1, topL) end
      if getMid(cx, lowerY + 1) == botM then setMid(cx, lowerY + 1, topM) end
      if getMid(cx, lowerY + 1) == botR then setMid(cx, lowerY + 1, topR) end
    end
  end
end

--- Check if boulder can be pushed in direction `dir`
-- `boulderObj`: { x = ..., y = ... } or a live EventObject { cellX = ..., cellY = ... }
-- `isPassableFn(x, y)`: returns true if cell (x, y) has no solid collision and no blocking object
function FieldMoves.canPushBoulder(boulderObj, dir, isPassableFn)
  if not boulderObj or not dir or not isPassableFn then return false end

  local DELTA = {
    up = { 0, -1 },
    down = { 0, 1 },
    left = { -1, 0 },
    right = { 1, 0 },
  }

  local d = DELTA[dir]
  if not d then return false end

  local baseX = tonumber(boulderObj.x) or tonumber(boulderObj.cellX)
  local baseY = tonumber(boulderObj.y) or tonumber(boulderObj.cellY)
  if not baseX or not baseY then return false end

  local targetX = baseX + d[1]
  local targetY = baseY + d[2]

  return isPassableFn(targetX, targetY), targetX, targetY
end

return FieldMoves
