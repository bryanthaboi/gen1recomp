
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
FieldMoves.SYS_FLAGS = {
  FLASH_ACTIVE  = 0x803, -- FLAG_SYS_FLASH_ACTIVE
  USE_STRENGTH  = 0x804, -- FLAG_SYS_USE_STRENGTH
  USE_SURF      = 0x805, -- FLAG_SYS_USE_SURF
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
  WARP_OUT    = 40,  -- SE_WARP_OUT
  CUT         = 143, -- SE_M_CUT
  ROCK_SMASH  = 146, -- SE_M_ROCK_THROW
  FLASH       = 175, -- SE_M_REFLECT
  SWEET_SCENT = 197, -- SE_M_SWEET_SCENT
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
}

-- Metatile terrain / collision behaviors
FieldMoves.BEHAVIORS = {
  GRASS      = { [0x01] = true, [0x02] = true, [0x03] = true },
  WATER      = { [0x10] = true, [0x11] = true, [0x12] = true, [0x13] = true, [0x14] = true, [0x15] = true },
  WATERFALL  = { [0x13] = true, [0x21] = true },
  DEEP_WATER = { [0x14] = true, [0x22] = true },
}

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

-- Standard Text Strings
FieldMoves.TEXT = {
  CANT_USE_HERE         = "Can't use that here.",
  BADGE_REQUIRED        = "Sorry! A new BADGE is required.",
  NOT_ENOUGH_HP         = "Not enough HP!",
  CANT_BE_USED_ON_PKMN  = "It won't have any effect.",

  -- Cut
  ASK_CUT_TREE          = "This tree looks like it can be CUT\ndown!\nWould you like to CUT it?",
  TREE_CAN_BE_CUT       = "This tree looks like it can be CUT\ndown!",
  USED_CUT              = "{STR_VAR_1} used CUT!",
  CUT_NOTHING           = "There's nothing to CUT here.",

  -- Rock Smash
  ASK_ROCK_SMASH        = "This rock appears to be breakable.\nWould you like to use ROCK SMASH?",
  MON_MAY_SMASH_ROCK    = "It's a rugged rock, but a POKéMON\nmay be able to smash it.",
  USED_ROCK_SMASH       = "{STR_VAR_1} used ROCK SMASH!",

  -- Strength
  ASK_STRENGTH          = "It's a big boulder, but a POKéMON\nmay be able to push it aside.\nWould you like to use STRENGTH?",
  MON_MAY_PUSH_BOULDER  = "It's a big boulder, but a POKéMON\nmay be able to push it aside.",
  USED_STRENGTH         = "{STR_VAR_1} used STRENGTH!\n{STR_VAR_1}'s STRENGTH made it\npossible to move boulders around!",
  STRENGTH_ACTIVE       = "STRENGTH made it possible to move\nboulders around.",

  -- Surf
  ASK_SURF              = "The water is dyed a deep blue…\nWould you like to SURF?",
  USED_SURF             = "{STR_VAR_1} used SURF!",
  CANT_SURF_CURRENT     = "The current is much too fast!\nSURF can't be used here…",
  ALREADY_SURFING       = "You're already SURFING.",

  -- Flash
  USED_FLASH            = "{STR_VAR_1} used FLASH!\nA blinding light illuminates\nthe area!",

  -- Waterfall
  ASK_WATERFALL         = "It's a large waterfall.\nWould you like to use WATERFALL?",
  USED_WATERFALL        = "{STR_VAR_1} used WATERFALL.",
  CANT_WATERFALL        = "A wall of water is crashing down\nwith a mighty roar.",

  -- Dive
  ASK_DIVE              = "The sea is deep here.\nWould you like to use DIVE?",
  ASK_SURFACE           = "Light is filtering down from above.\nWould you like to use DIVE?",
  USED_DIVE             = "{STR_VAR_1} used DIVE.",
  CANT_DIVE             = "The sea is deep here. A POKéMON\nmay be able to go underwater.",
  CANT_SURFACE          = "Light is filtering down from above.\nA POKéMON may be able to surface.",
  DIVE_OBSTACLE         = "There is an obstacle above.\nDIVE can't be used here.",

  -- Teleport & Dig
  TELEPORT_RETURN       = "Return to the last POKéMON CENTER.",
  USED_DIG              = "{STR_VAR_1} used DIG!",
  USED_ESCAPE_ROPE      = "{PLAYER} used an ESCAPE ROPE.",

  -- Sweet Scent
  USED_SWEET_SCENT      = "{STR_VAR_1} used SWEET SCENT!",
  NO_SWEET_SCENT_MONS   = "Looks like there's nothing here…",
}

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
function FieldMoves.getMonName(mon)
  if not mon then return "POKéMON" end
  return mon.nickname or mon.name or mon.species or "POKéMON"
end

-- ---------------------------------------------------------------- menu paths (SetUpFieldMove_*)

--- Cut from Party Menu
function FieldMoves.cutFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "CUT") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "CUT" }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "CUT")
  local monName = FieldMoves.getMonName(mon)

  -- 1) Check facing Cut Tree object
  if ctx.facingObject and (ctx.facingObject.gfx == FieldMoves.GFX_IDS.CUT_TREE
      or ctx.facingObject.graphicsId == FieldMoves.GFX_IDS.CUT_TREE) then
    return {
      ok = true,
      action = "cut_tree",
      target = ctx.facingObject,
      mon = mon,
      se = FieldMoves.SE.CUT,
      text = FieldMoves.TEXT.USED_CUT:gsub("{STR_VAR_1}", monName),
    }
  end

  -- 2) Check facing / standing 3x3 grass
  if ctx.hasCuttableGrass then
    return {
      ok = true,
      action = "cut_grass",
      mon = mon,
      se = FieldMoves.SE.CUT,
      text = FieldMoves.TEXT.USED_CUT:gsub("{STR_VAR_1}", monName),
    }
  end

  -- 3) Check Dotted Hole door check
  if ctx.isDottedHoleDoor then
    return {
      ok = true,
      action = "dotted_hole",
      mon = mon,
      se = FieldMoves.SE.CUT,
      text = FieldMoves.TEXT.USED_CUT:gsub("{STR_VAR_1}", monName),
    }
  end

  return { ok = false, text = FieldMoves.TEXT.CUT_NOTHING }
end

--- Flash from Party Menu
function FieldMoves.flashFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "FLASH") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "FLASH" }
  end

  if not ctx.isDarkCave and not ctx.isCave then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  if ctx.isFlashActive or (ctx.store and Flags.getFlag(ctx.store, ctx.ctx, FieldMoves.SYS_FLAGS.FLASH_ACTIVE)) then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "FLASH")
  local monName = FieldMoves.getMonName(mon)

  return {
    ok = true,
    action = "flash",
    mon = mon,
    se = FieldMoves.SE.FLASH,
    flag = FieldMoves.SYS_FLAGS.FLASH_ACTIVE,
    text = FieldMoves.TEXT.USED_FLASH:gsub("{STR_VAR_1}", monName),
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

  if ctx.isFastCurrent then
    return { ok = false, text = FieldMoves.TEXT.CANT_SURF_CURRENT }
  end

  if not ctx.isFacingWater then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "SURF")
  local monName = FieldMoves.getMonName(mon)

  return {
    ok = true,
    action = "surf",
    mon = mon,
    text = FieldMoves.TEXT.USED_SURF:gsub("{STR_VAR_1}", monName),
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
    text = FieldMoves.TEXT.USED_STRENGTH:gsub("{STR_VAR_1}", monName),
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
  local monName = FieldMoves.getMonName(mon)

  return {
    ok = true,
    action = "rock_smash",
    target = ctx.facingObject,
    mon = mon,
    se = FieldMoves.SE.ROCK_SMASH,
    text = FieldMoves.TEXT.USED_ROCK_SMASH:gsub("{STR_VAR_1}", monName),
  }
end

--- Waterfall from Party Menu
function FieldMoves.waterfallFromMenu(ctx)
  if not FieldMoves.hasBadge(ctx, "WATERFALL") then
    return { ok = false, text = FieldMoves.TEXT.BADGE_REQUIRED, badge = "WATERFALL" }
  end

  if not ctx.isSurfing or not ctx.isFacingWaterfall or ctx.facing ~= "up" then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end

  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "WATERFALL")
  local monName = FieldMoves.getMonName(mon)

  return {
    ok = true,
    action = "waterfall",
    mon = mon,
    text = FieldMoves.TEXT.USED_WATERFALL:gsub("{STR_VAR_1}", monName),
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
  local monName = FieldMoves.getMonName(mon)

  return {
    ok = true,
    action = "dig",
    mon = mon,
    se = FieldMoves.SE.WARP_OUT,
    text = FieldMoves.TEXT.USED_DIG:gsub("{STR_VAR_1}", monName),
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
    text = FieldMoves.TEXT.TELEPORT_RETURN,
    warp = ctx.lastHealWarp or ctx.respawnPoint,
  }
end

--- Sweet Scent from Party Menu
function FieldMoves.sweetScentFromMenu(ctx)
  local mon = ctx.mon or FieldMoves.partyMoveUser(ctx.party, "SWEET_SCENT")
  local monName = FieldMoves.getMonName(mon)

  return {
    ok = true,
    action = "sweet_scent",
    mon = mon,
    se = FieldMoves.SE.SWEET_SCENT,
    text = FieldMoves.TEXT.USED_SWEET_SCENT:gsub("{STR_VAR_1}", monName),
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
    text = FieldMoves.TEXT.USED_CUT:gsub("{STR_VAR_1}", monName),
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
    text = FieldMoves.TEXT.USED_ROCK_SMASH:gsub("{STR_VAR_1}", monName),
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
    text = FieldMoves.TEXT.USED_STRENGTH:gsub("{STR_VAR_1}", monName),
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
    text = FieldMoves.TEXT.USED_SURF:gsub("{STR_VAR_1}", monName),
  }
end

--- Waterfall Collision Interaction (EventScript_Waterfall)
function FieldMoves.tryWaterfallOW(ctx)
  if not ctx.isSurfing or not ctx.isFacingWaterfall or ctx.facing ~= "up" then
    return { ok = false }
  end

  local mon, slot = FieldMoves.partyMoveUser(ctx.party, "WATERFALL")
  local hasBadge = FieldMoves.hasBadge(ctx, "WATERFALL")

  if not mon or not hasBadge then
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
    text = FieldMoves.TEXT.USED_WATERFALL:gsub("{STR_VAR_1}", monName),
  }
end

-- ---------------------------------------------------------------- map & metatile modifications

--- Mows grass in a 3x3 grid centered on (cx, cy)
-- `getMetatileFn(x, y)`: returns numeric metatileId
-- `setMetatileFn(x, y, newMetatileId)`: applies new metatileId
-- Returns count of cut tiles
function FieldMoves.mowGrass3x3(cx, cy, getMetatileFn, setMetatileFn, isGrassFn)
  if not getMetatileFn or not setMetatileFn then return 0 end
  local count = 0

  for dy = -1, 1 do
    for dx = -1, 1 do
      local x = cx + dx
      local y = cy + dy
      local mid = getMetatileFn(x, y)
      if mid then
        local newMid = FieldMoves.CUT_GRASS_METATILES[mid]
        if not newMid and isGrassFn and isGrassFn(x, y) then
          -- Default flat-ground replacement in general tileset
          newMid = 0x001
        end
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
-- `boulderObj`: { x = ..., y = ... }
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

  local targetX = boulderObj.x + d[1]
  local targetY = boulderObj.y + d[2]

  return isPassableFn(targetX, targetY), targetX, targetY
end

return FieldMoves
