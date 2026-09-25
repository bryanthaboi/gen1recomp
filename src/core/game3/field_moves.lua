
-- Game 3 (FRLG / pokefirered) Field Moves Engine
-- Handles all HM and utility field moves: Cut, Fly, Surf, Strength, Flash,
-- Rock Smash, Waterfall, Dive, Dig, Teleport, Sweet Scent, Softboiled/Milk Drink.
-- Supports dual-trigger architecture:
--   1. Party Menu Submenu (SetUpFieldMove_* / fromMenu)
--   2. Overworld A-Press Collision / Object Interaction (tryOW / EventScript_*)

local Flags = require("src.core.game3.scripting.flags")

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

-- System flags
-- include/constants/flags.h:1330
FieldMoves.SYS_FLAGS = {
  WHITE_FLUTE_ACTIVE = 0x803,
  BLACK_FLUTE_ACTIVE = 0x804,
  USE_STRENGTH  = 0x805,
  FLASH_ACTIVE  = 0x806,
}

-- src/event_data.c:49
FieldMoves.TEMP_SYS_FLAGS = {
  0x803, 0x804, 0x805,
}

-- Graphics IDs for interactable field objects
FieldMoves.GFX_IDS = {
  CUT_TREE          = 95, -- OBJ_EVENT_GFX_CUT_TREE
  ROCK_SMASH_ROCK   = 96, -- OBJ_EVENT_GFX_ROCK_SMASH_ROCK
  PUSHABLE_BOULDER  = 97, -- OBJ_EVENT_GFX_PUSHABLE_BOULDER
}

-- Sound Effect IDs (matching pret include/constants/songs.h)
FieldMoves.SE = {
  USE_ITEM    = 1,   -- SE_USE_ITEM
  BANG        = 20,
  WARP_OUT    = 40,  -- SE_WARP_OUT
  CUT         = 143, -- SE_M_CUT
  ROCK_SMASH  = 146, -- SE_M_ROCK_THROW
  FLASH       = 175, -- SE_M_REFLECT
  SWEET_SCENT = 197, -- SE_M_SWEET_SCENT
}

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
FieldMoves.TEXT = setmetatable({}, {
  __index = function(_, key)
    if TEXT_ROM[key] then return require("src.core.game3.rom_text").ascii(TEXT_ROM[key]) end
    return nil
  end,
})

-- data/scripts/field_moves.inc:8 bufferpartymonnick STR_VAR_1, buffermovename STR_VAR_2
function FieldMoves.monText(key, monName, moveId)
  local moveName = moveId and require("src.core.game3.pokemon").moveName(moveId) or nil
  return require("src.core.game3.rom_text").ascii(TEXT_ROM[key], { stringVars = { monName, moveName } })
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
function FieldMoves.partyMoveUser(party, moveIdentifier)
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

--- Check if badge is owned in store / session / save
function FieldMoves.hasBadge(ctxOrStore, badgeKey)
  local flagId = FieldMoves.BADGE_FLAGS[badgeKey]
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
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
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

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "CUT")

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

  -- src/party_menu.c:4047 DisplayCantUseFlashMessage
  if ctx.isFlashActive or (ctx.store and Flags.getFlag(ctx.store, ctx.ctx, FieldMoves.SYS_FLAGS.FLASH_ACTIVE)) then
    return { ok = false, text = FieldMoves.TEXT.FLASH_IN_USE }
  end

  if not ctx.isDarkCave and not ctx.isCave then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "FLASH")

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
    local MapCatalog = require("src.import.gba.map_catalog")
    local map = ctx.mapId or (ctx.session and ctx.session.map)
    if map == MapCatalog.pretToEngine("Route17") or map == MapCatalog.pretToEngine("Route18") then
      return { ok = false, text = FieldMoves.TEXT.ENJOY_CYCLING }
    end
    return { ok = false, text = FieldMoves.TEXT.CANT_SURF_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "SURF")

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

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "STRENGTH")
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

  if not ctx.facingObject or (ctx.facingObject.gfx ~= FieldMoves.GFX_IDS.ROCK_SMASH_ROCK
      and ctx.facingObject.graphicsId ~= FieldMoves.GFX_IDS.ROCK_SMASH_ROCK) then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "ROCK_SMASH")

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

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "WATERFALL")

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

  if not FieldMoves.isOutdoors(ctx.mapType) then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "FLY")

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

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "DIG")

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

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "TELEPORT")

  return {
    ok = true,
    action = "teleport",
    mon = mon,
    se = FieldMoves.SE.WARP_OUT,
    warp = ctx.lastHealWarp or ctx.respawnPoint,
  }
end

--- Sweet Scent from Party Menu
function FieldMoves.sweetScentFromMenu(ctx)
  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "SWEET_SCENT")

  return {
    ok = true,
    action = "sweet_scent",
    mon = mon,
    se = FieldMoves.SE.SWEET_SCENT,
    hasEncounter = ctx.hasWildEncounters == true,
    failText = FieldMoves.TEXT.NO_SWEET_SCENT_MONS,
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
  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "CUT")
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
  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "ROCK_SMASH")
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
  local isStrengthActive = ctx.isStrengthActive or (ctx.store and Flags.getFlag(ctx.store, ctx.ctx, FieldMoves.SYS_FLAGS.USE_STRENGTH))
  if isStrengthActive then
    return {
      ok = false,
      alreadyActive = true,
      text = FieldMoves.TEXT.STRENGTH_ACTIVE,
    }
  end

  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "STRENGTH")
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

  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "SURF")
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

  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "WATERFALL")
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
