-- The seven HM field moves, as the love-free half of
-- engine/events/overworld.asm: "may this move be used from here", "what does
-- it do to the tile", and "which line does it print when it can't".
--
-- Every routine in that file comes in two flavours and the port needs both,
-- because they are not the same routine with a different caller:
--
--   *Function / Try*FromMenu   the PACK / party-submenu path.  Checks the
--                              BADGE first (CheckBadge, which prints
--                              "Sorry! A new BADGE is required." itself), and
--                              assumes the mon is already chosen, because the
--                              party list is what chose it.
--   Try*OW                     the A-press path out of TryTileCollisionEvent.
--                              Checks the MOVE first (CheckPartyMove), then
--                              the badge through CheckEngineFlag -- which is
--                              CheckBadge with the text stripped off, so a
--                              badgeless A press is silent, not a refusal.
--
-- The two orders are the reason a tree you cannot cut says "This tree can be
-- CUT!" and stops, while CUT off the menu with no HIVEBADGE says "Sorry! A new
-- BADGE is required."  Keep them apart.
--
-- Nothing here touches love, the save writer, or the map: a routine is handed
-- a context table (World:fieldContext builds it) and hands back a result the
-- caller acts on.  That is what lets tests drive all seven with a bare table.
--
-- Result shape:
--   { ok = false }                      the event is declined outright and
--                                       NOTHING is printed (TryHeadbuttOW's
--                                       `ret nc`, TrySurfOW's `.quit`)
--   { ok = false, text = ..., badge = } a refusal with a line, `badge` set
--                                       when it was CheckBadge that refused
--   { ok = true,  ask = ..., ... }      a yesorno first, then the action
--   { ok = true,  action = "cut", ... } run it now
--
-- `action` names the World method that carries it out; everything else in the
-- table is that action's argument.

local GameVersion = require("src.core.GameVersion")
local Permissions = require("src.world.gen2.Permissions")
local Runtime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")

local FieldMoves = {}

-- ---------------------------------------------------------------- text
--
-- data/text/common_1.asm and common_2.asm, in the port's own TextBox markers:
-- \n is the text box's second line (`line`), \f is a page break (`para`), and
-- {STRBUF} is the shared wStringBuffer2 token that `text_ram wStringBuffer2`
-- expands to -- GetPartyNickname is what fills it, so it is always the
-- nickname of the mon CheckPartyMove picked.
--
-- These are transcribed rather than looked up for the same reason the headbutt
-- lines in World.lua are: engine/events/overworld.asm names each label
-- directly, the extractor only walks reachable SCRIPT pointers, and so
-- data/generated/text.lua has no key for any of them.  `#` is the four-tile
-- POKé compression byte.
-- Each one is wrapped in Strings.source so the catalog generator harvests it:
-- this table is built at require time, long before Strings.load has a catalog,
-- so the lookup itself happens at the World call sites through Strings(...).
FieldMoves.TEXT = {
  BADGE_REQUIRED   = Strings.source("Sorry! A new BADGE\nis required."),
  CANT_USE_HERE    = Strings.source("Can't use that\nhere."),
  -- ../pokecrystal/data/text/common_2.asm:1516 _PokemonNotEnoughHPText
  NOT_ENOUGH_HP    = Strings.source("Not enough HP!"),

  USE_CUT          = Strings.source("{STRBUF} used\nCUT!"),
  CUT_NOTHING      = Strings.source("There's nothing to\nCUT here."),
  ASK_CUT          = Strings.source("This tree can be\nCUT!"
                     .. "\fWant to use CUT?"),
  CAN_CUT          = Strings.source("This tree can be\nCUT!"),

  BLINDING_FLASH   = Strings.source("A blinding FLASH\nlights the area!"),

  USED_SURF        = Strings.source("{STRBUF} used\nSURF!"),
  CANT_SURF        = Strings.source("You can't SURF\nhere."),
  ALREADY_SURFING  = Strings.source("You're already\nSURFING."),
  ASK_SURF         = Strings.source("The water is calm.\nWant to SURF?"),

  USE_WATERFALL    = Strings.source("{STRBUF} used\nWATERFALL!"),
  HUGE_WATERFALL   = Strings.source("Wow, it's a huge\nwaterfall."),
  ASK_WATERFALL    = Strings.source("Do you want to use\nWATERFALL?"),

  USE_STRENGTH     = Strings.source("{STRBUF} used\nSTRENGTH!"),
  MOVE_BOULDER     = Strings.source("{STRBUF} can\nmove boulders."),
  ASK_STRENGTH     = Strings.source("A #MON may be\nable to move this."
                     .. "\fWant to use\nSTRENGTH?"),
  BOULDERS_MOVE    = Strings.source("Boulders may now\nbe moved!"),
  BOULDERS_MAY_MOVE = Strings.source("A #MON may be\nable to move this."),

  -- EscapeRopeOrDig's three lines (engine/events/overworld.asm): _UseDigText
  -- and _UseEscapeRopeText open the shared warp, _CantUseDigText is DIG's own
  -- refusal (the rope's .FailDig arm prints nothing and leaves the PACK to
  -- its .Oak line).
  USE_DIG          = Strings.source("{STRBUF} used\nDIG!"),
  USE_ESCAPE_ROPE  = Strings.source("{PLAYER} used an\nESCAPE ROPE."),
  -- TeleportFunction: _TeleportReturnText on the way out, _CantUseTeleportText
  -- indoors.
  TELEPORT_RETURN  = Strings.source("Return to the last\n#MON CENTER."),

  USE_WHIRLPOOL    = Strings.source("{STRBUF} used\nWHIRLPOOL!"),
  MAY_PASS_WHIRLPOOL = Strings.source("It's a vicious\nwhirlpool!"
                     .. "\fA #MON may be\nable to pass it."),
  ASK_WHIRLPOOL    = Strings.source("A whirlpool is in\nthe way."
                     .. "\fWant to use\nWHIRLPOOL?"),
  -- Not a cart line: the prompt World:askFlyPoint falls back to when there is
  -- no screen at all to push -- a headless probe, never a real run.
  ASK_FLY_TO       = Strings.source("Fly to %s?"),
}

-- ---------------------------------------------------------------- badges
--
-- The ENGINE_*BADGE each Function passes to CheckBadge.  There is no pattern
-- to it -- CUT is the HIVEBADGE, SURF is the FOGBADGE, FLASH is the very first
-- badge in the game -- so it is a table, not a formula.
FieldMoves.BADGE = {
  CUT       = "HIVE",    -- CutFunction.CheckAble
  FLASH     = "ZEPHYR",  -- FlashFunction.CheckUseFlash
  SURF      = "FOG",     -- SurfFunction.TrySurf / TrySurfOW
  FLY       = "STORM",   -- FlyFunction.TryFly
  STRENGTH  = "PLAIN",   -- StrengthFunction.TryStrength / TryStrengthOW
  WHIRLPOOL = "GLACIER", -- WhirlpoolFunction.TryWhirlpool / TryWhirlpoolOW
  WATERFALL = "RISING",  -- WaterfallFunction.TryWaterfall / TryWaterfallOW
}

-- wJohtoBadges bit order, which is also the order src/ui/gen2/TrainerCard.lua
-- lists them in.  A save may key `player.badges` by name or by that position,
-- and the trainer card already reads it both ways; this is the same read, so
-- the two screens can never disagree about who owns what.
-- NOTE the order: MINERAL is bit 4 and STORM bit 5, which is NOT the order a
-- player earns them (Chuck's STORMBADGE comes before Jasmine's MINERALBADGE).
-- constants/engine_flags.asm:38-45 is the authority and this follows it; the
-- two used to be swapped here, which silently mapped SURF's gate onto the wrong
-- bit.
FieldMoves.JOHTO_BADGES = {
  "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING",
}

FieldMoves.KANTO_BADGES = {
  "BOULDER", "CASCADE", "THUNDER", "RAINBOW",
  "SOUL", "MARSH", "VOLCANO", "EARTH",
}

-- ENGINE_* id -> which badge store and which name.
--
-- On the cart these are not two things: ENGINE_ZEPHYRBADGE *is* bit 0 of
-- wJohtoBadges (constants/engine_flags.asm's "; wJohtoBadges" block), so
-- `setflag ENGINE_ZEPHYRBADGE` and "the player owns the Zephyr Badge" are the
-- same write.  The port had split them -- scripts wrote save.engineFlags while
-- hasBadge, VAR_BADGES, the trainer card and the save summary all read
-- save.player.badges, which nothing ever wrote.  The visible effect was that no
-- field move could EVER be used: Cut, Surf, Strength and Fly all refused with
-- "Sorry! A new BADGE is required" no matter how many gyms were cleared.
-- World:setEngineFlag / World:engineFlag route badge ids here so there is one
-- store again, the same way ENGINE_BUG_CONTEST_TIMER is routed to
-- save.bugContest rather than kept as a second copy.
-- Crystal declares 162 engine flags to Gold's 93 and the badge block sits one
-- higher (constants/engine_flags.asm:39 vs pokegold's :38), so the ids come
-- from the cache's engineFlagOrder when it has one.
-- Crystal only; pokegold constants/engine_flags.asm:4-111 has no such row.
FieldMoves.FEMALE_FLAG_NAME = "ENGINE_PLAYER_IS_FEMALE"

function FieldMoves.bindEngineFlags(order)
  local byName = {}
  if type(order) == "table" then
    -- pairs, not ipairs: a const_skip leaves a hole and ipairs would stop
    -- there, silently dropping every badge past it.
    for index, name in pairs(order) do
      if type(index) == "number" and type(name) == "string" then
        byName[name] = index - 1
      end
    end
  end
  local flags = {}
  local function place(names, store, goldBase)
    for index, name in ipairs(names) do
      local id = byName["ENGINE_" .. name .. "BADGE"] or (goldBase + index)
      flags[id] = { store = store, name = name }
    end
  end
  place(FieldMoves.JOHTO_BADGES, "badges", 25)
  place(FieldMoves.KANTO_BADGES, "kantoBadges", 33)
  FieldMoves.BADGE_FLAG = flags
  -- The flag IS wPlayerGender's bit 0, so World routes it to the gender byte
  -- (data/events/engine_flags.asm:131, constants/engine_flags.asm:121).
  FieldMoves.FEMALE_FLAG = byName[FieldMoves.FEMALE_FLAG_NAME]
  -- Crystal's ENGINE_MOBILE_SYSTEM (constants/engine_flags.asm:25) has no Gold
  -- row, so every id from BUG_CONTEST_TIMER up shifts one.
  FieldMoves.BUG_CONTEST_FLAG = byName["ENGINE_BUG_CONTEST_TIMER"] or 16
  FieldMoves.BIKE_SHOP_CALL_FLAG = byName["ENGINE_BIKE_SHOP_CALL_ENABLED"] or 19
  return flags
end

FieldMoves.bindEngineFlags(nil)

function FieldMoves.hasBadge(save, badge)
  if not badge then return true end
  local owned = save and save.player and save.player.badges
  if type(owned) ~= "table" then return false end
  if owned[badge] then return true end
  for index, name in ipairs(FieldMoves.JOHTO_BADGES) do
    if name == badge then return owned[index] == true end
  end
  return false
end

-- CheckPartyMove (engine/events/overworld.asm): the first party slot holding
-- move `moveId`.  The cart leaves that slot in wCurPartyMon and every caller
-- reads it back through GetPartyNickname, so the mon comes back with its
-- index rather than a bare yes/no.
--
-- EGG slots are skipped by the cart's `.next`; the port has no egg state, so
-- there is nothing to skip yet and a mon with an `egg` field is refused here
-- for whenever there is.
--
-- fieldmove.eligibility wraps it, exactly as it wraps OverworldState:partyKnows
-- under Gen 1: the vanilla link runs first, so a mod that unlocks a field move
-- another way (an HM in the bag, a rental mon) still loses to a party that
-- really knows it.  The chain is (moveId, ctx) -> mon, the Gen 1 signature; the
-- second return (the party slot) survives an empty chain but a wrapper that
-- returns one value drops it, which is why every caller here reads only `mon`.
local function findMoveUser(party, moveId)
  for index, mon in ipairs(party or {}) do
    if not mon.egg then
      for _, move in ipairs(mon.moves or {}) do
        local id = type(move) == "table" and move.id or move
        if id == moveId then return mon, index end
      end
    end
  end
  return nil
end

local function partyMoveUserVanilla(moveId, ctx)
  return findMoveUser(ctx and ctx.party, moveId)
end

-- `fieldCtx` is World:fieldContext's table when the caller has one; it is only
-- read for the hook's ctx, so the two-argument Gen 2 callers keep working.
function FieldMoves.partyMoveUser(party, moveId, fieldCtx)
  if not Runtime.wantsHook("fieldmove.eligibility") then
    return findMoveUser(party, moveId)
  end
  return Runtime.call("fieldmove.eligibility", partyMoveUserVanilla, moveId, {
    save = fieldCtx and fieldCtx.save,
    data = fieldCtx and fieldCtx.data,
    party = party,
    moveId = moveId,
  })
end

-- --------------------------------------------------------- encounter gate
--
-- CanEncounterWildMon (engine/overworld/events.asm).  The branch that matters
-- is the one in the middle: a CAVE or DUNGEON map jumps STRAIGHT to the ice
-- check, skipping CheckGrassCollision entirely, which is why every walkable
-- tile of Dark Cave and Union Cave is an encounter tile and why the port --
-- which only ever asked Permissions.isGrass -- gave those maps none at all.
--
-- `noWildEncounters` is STATUSFLAGS_NO_WILD_ENCOUNTERS_F, the flag the
-- `wildoff` / `wildon` script commands drive.
function FieldMoves.canEncounterWildMon(environment, playerColl, noWild)
  if noWild then return false end
  if environment ~= "CAVE" and environment ~= "DUNGEON" then
    if not Permissions.isEncounterCollision(playerColl) then return false end
  end
  -- .ice_check: shared by both arms, so an ice floor in a cave is as free of
  -- encounters as an ice floor on a route.
  if Permissions.isIce(playerColl) then return false end
  return true
end

-- ChooseWildEncounter picks its table off CheckOnWater, i.e. the PERMISSION of
-- the tile the player stands on, not off the grass array that let the roll
-- happen.  Standing in a cave rolls the grass list; surfing rolls the water
-- one, on a route and in a cave alike.
function FieldMoves.encounterTable(playerColl)
  return Permissions.isWater(playerColl) and "water" or "grass"
end

-- ------------------------------------------------------------ cut blocks
--
-- data/collision/field_move_blocks.asm, verbatim.  A row is
-- { facing block, replacement block, animation type }: CUT and WHIRLPOOL do
-- not edit tiles, they swap the whole 32x32 BLOCK the facing tile belongs to
-- for another block out of the same tileset, which is why one swing clears a
-- 2x2 patch of grass.
--
-- Animation type 1 is the grass swirl, 0 the falling tree
-- (OWCutAnimation reads it out of wCutWhirlpoolAnimationType).
FieldMoves.CUT_BLOCKS = {
  TILESET_JOHTO = {
    [0x03] = { 0x02, 1 }, -- grass
    [0x5b] = { 0x3c, 0 }, -- tree
    [0x5f] = { 0x3d, 0 }, -- tree
    [0x63] = { 0x3f, 0 }, -- tree
    [0x67] = { 0x3e, 0 }, -- tree
  },
  TILESET_JOHTO_MODERN = {
    [0x03] = { 0x02, 1 }, -- grass
  },
  TILESET_KANTO = {
    [0x0b] = { 0x0a, 1 }, -- grass
    [0x32] = { 0x6d, 0 }, -- tree
    [0x33] = { 0x6c, 0 }, -- tree
    [0x34] = { 0x6f, 0 }, -- tree
    [0x35] = { 0x4c, 0 }, -- tree
    [0x60] = { 0x6e, 0 }, -- tree
  },
  TILESET_PARK = {
    [0x13] = { 0x03, 1 }, -- grass
    [0x03] = { 0x04, 1 }, -- grass
  },
  TILESET_FOREST = {
    [0x0f] = { 0x17, 0 },
  },
}

FieldMoves.WHIRLPOOL_BLOCKS = {
  TILESET_JOHTO = {
    [0x07] = { 0x36, 0 },
  },
}

-- CheckOverworldTileArrays: the tileset has to be in the dictionary AND the
-- facing block has to be in that tileset's list, or the whole thing fails
-- (both `.nope` arms clear carry).  Returns replacement block, animation.
function FieldMoves.blockReplacement(table_, tileset, blockId)
  local rows = table_ and tileset and table_[tileset]
  local row = rows and blockId and rows[blockId]
  if not row then return nil end
  return row[1], row[2]
end

-- CheckMapForSomethingToCut: the facing tile's collision has to be cuttable
-- AND the block it sits in has to have a replacement.  Both halves are needed
-- -- a COLL_CUT_TREE in a tileset with no CutTreeBlockPointers row is the
-- cart's own "nothing to cut".
function FieldMoves.somethingToCut(ctx)
  if not Permissions.isCuttable(ctx.facingColl) then return nil end
  return FieldMoves.blockReplacement(
    FieldMoves.CUT_BLOCKS, ctx.tileset, ctx.facingBlock)
end

-- TryWhirlpoolMenu, which is CheckMapForSomethingToCut with CheckWhirlpoolTile
-- in place of CheckCutCollision.
function FieldMoves.somethingToWhirlpool(ctx)
  if not Permissions.isWhirlpool(ctx.facingColl) then return nil end
  return FieldMoves.blockReplacement(
    FieldMoves.WHIRLPOOL_BLOCKS, ctx.tileset, ctx.facingBlock)
end

-- CheckMapCanWaterfall: facing UP, and the tile ABOVE the player (wTileUp, not
-- the facing tile the A press found) is a waterfall.  Those are the same cell
-- while the player faces up, which is exactly why the routine gets away with
-- reading wTileUp -- but the menu path has no facing tile at all, so it must
-- be wTileUp there too.
function FieldMoves.canWaterfall(ctx)
  if ctx.facing ~= "up" then return false end
  return Permissions.isWaterfall(ctx.upColl)
end

-- .CheckContinueWaterfall: the climb keeps applying turn_waterfall UP for as
-- long as the tile the player is STANDING on is still a waterfall tile.
function FieldMoves.waterfallContinues(playerColl)
  return Permissions.isWaterfall(playerColl)
end

-- ------------------------------------------------------- player state
--
-- constants/ram_constants.asm wPlayerState.  Held as strings so a save that
-- round-trips one is readable, and mapped to ChrisStateSprites
-- (data/sprites/player_sprites.asm) on the way to the renderer.
--
-- PLAYER_SKATE (2) is the one wPlayerState value with no string here: nothing
-- in Gold ever writes it, and ChrisStateSprites has no row for it either.
FieldMoves.PLAYER_NORMAL = "normal"
FieldMoves.PLAYER_BIKE = "bike"
FieldMoves.PLAYER_SURF = "surf"
FieldMoves.PLAYER_SURF_PIKA = "surf_pika"

FieldMoves.STATE_SPRITE = {
  normal = "SPRITE_CHRIS",
  bike = "SPRITE_CHRIS_BIKE",
  surf = "SPRITE_SURF",
  surf_pika = "SPRITE_SURFING_PIKACHU",
}

-- data/sprites/player_sprites.asm:8-13 KrisStateSprites, the other half of the
-- table GetPlayerSprite picks between (engine/overworld/overworld.asm:55-64).
FieldMoves.STATE_SPRITE_FEMALE = {
  normal = "SPRITE_KRIS",
  bike = "SPRITE_KRIS_BIKE",
  surf = "SPRITE_SURF",
  surf_pika = "SPRITE_SURFING_PIKACHU",
}

-- wPlayerGender's PLAYERGENDER_FEMALE_F, as the save spells it
-- (constants/ram_constants.asm:176-177).
function FieldMoves.isFemale(gender)
  return gender == "female"
end

-- GetPlayerSprite's table pick and row walk
-- (engine/overworld/overworld.asm:57-64, :67-75).
function FieldMoves.stateSprite(state, gender)
  local table_ = FieldMoves.isFemale(gender)
    and FieldMoves.STATE_SPRITE_FEMALE or FieldMoves.STATE_SPRITE
  return table_[state] or table_[FieldMoves.PLAYER_NORMAL]
end

function FieldMoves.playerSprite(gender)
  return FieldMoves.stateSprite(FieldMoves.PLAYER_NORMAL, gender)
end

-- Whether the cache carries Kris at all; Gold and Silver have no
-- KrisStateSprites to extract (pokegold data/sprites/player_sprites.asm:1-6).
function FieldMoves.hasGenderChoice(sprites)
  return (sprites and sprites[FieldMoves.STATE_SPRITE_FEMALE.normal]) ~= nil
end

function FieldMoves.isBiking(state)
  return state == FieldMoves.PLAYER_BIKE
end

function FieldMoves.isSurfing(state)
  return state == FieldMoves.PLAYER_SURF
      or state == FieldMoves.PLAYER_SURF_PIKA
end

-- GetSurfType: the mon CheckPartyMove picked decides the sprite, and PIKACHU
-- is the one species that rides its own.
function FieldMoves.surfType(mon)
  local species = mon and (mon.species or mon.id)
  if species == "PIKACHU" then return FieldMoves.PLAYER_SURF_PIKA end
  return FieldMoves.PLAYER_SURF
end

-- CheckDirection: refuse to start surfing when the tile permissions already
-- block a step in the direction the player faces.  wTilePermissions is the
-- four-way "can I leave this tile" mask built by GetMovementPermissions, and
-- the port has no such mask -- but the thing it is guarding against is
-- surfing off a ledge or through a side wall, so the check is the same
-- question asked of the tile under the player.
local BLOCKED_BY = {
  -- COLL_RIGHT_WALL / LEFT / UP, the HI_NYBBLE_SIDE_WALLS rows that are
  -- actually used, plus the unused remainder of the block for completeness.
  [0xb0] = { right = true },
  [0xb1] = { left = true },
  [0xb2] = { up = true },
  [0xb3] = { down = true },
  [0xb4] = { down = true, right = true },
  [0xb5] = { down = true, left = true },
  [0xb6] = { up = true, right = true },
  [0xb7] = { up = true, left = true },
}

function FieldMoves.directionBlocked(playerColl, facing)
  local row = playerColl and BLOCKED_BY[playerColl % 256]
  return (row and row[facing]) == true
end

-- ------------------------------------------------------------------- fly
--
-- data/maps/flypoints.asm:1
local FLYPOINT_BY_SPAWN = {}

function FieldMoves.bindFlypoints(rows, spawns)
  local list, bySpawn = {}, {}
  for spawn, row in pairs(type(rows) == "table" and rows or {}) do
    if type(spawn) == "string" and type(row) == "table"
        and type(row.landmark) == "string"
        and (type(spawns) ~= "table" or type(spawns[spawn]) == "table") then
      local entry = { spawn = spawn, landmark = row.landmark, flag = row.flag,
        region = row.region == "kanto" and "kanto" or "johto",
        order = row.order }
      list[#list + 1] = entry
      bySpawn[spawn] = entry
    end
  end
  table.sort(list, function(a, b)
    if a.region ~= b.region then return a.region == "johto" end
    local oa, ob = a.order or math.huge, b.order or math.huge
    if oa ~= ob then return oa < ob end
    return a.spawn < b.spawn
  end)
  local kanto = #list + 1
  for i, entry in ipairs(list) do
    if entry.region == "kanto" then kanto = i break end
  end
  FieldMoves.FLYPOINTS, FLYPOINT_BY_SPAWN = list, bySpawn
  FieldMoves.KANTO_FLYPOINT = kanto
  return list
end

FieldMoves.bindFlypoints(nil)

function FieldMoves.noteVisit(save, mapId, spawns)
  if not (save and mapId and type(spawns) == "table") then return end
  for _, row in ipairs(FieldMoves.FLYPOINTS) do
    local spawn = spawns[row.spawn]
    if row.flag == nil and type(spawn) == "table" and spawn.map == mapId then
      save.visitedSpawns = save.visitedSpawns or {}
      save.visitedSpawns[row.spawn] = true
    end
  end
end

-- engine/pokegear/pokegear.asm:2189
function FieldMoves.hasVisitedSpawn(save, spawn)
  if not (save and spawn) then return false end
  local row = FLYPOINT_BY_SPAWN[spawn]
  local engine = save.engineFlags
  if row and type(engine) == "table" then
    local set = engine[row.flag]
    if set ~= nil then return set == true end
  end
  return (save.visitedSpawns or {})[spawn] == true
end

-- The rows FlyMap would actually let the cursor stop on: this region's half of
-- the table, minus every spawn CheckIfVisitedFlypoint rejects.
--
-- The Kanto half is withheld until SPAWN_INDIGO is visited (.KantoFlyMap's
-- HasVisitedSpawn gate), because with no Kanto flypoint enabled the cart's own
-- picker crashes; standing in Kanto before that shows the Johto map.
function FieldMoves.flyPoints(save, landmarks, region)
  local first, last = 1, FieldMoves.KANTO_FLYPOINT - 1
  local shown = "johto"
  if region == "kanto"
      and FieldMoves.hasVisitedSpawn(save, "SPAWN_INDIGO") then
    first, last = FieldMoves.KANTO_FLYPOINT, #FieldMoves.FLYPOINTS
    shown = "kanto"
  end
  local out = {}
  local table_ = landmarks and landmarks.landmarks
  for i = first, last do
    local row = FieldMoves.FLYPOINTS[i]
    if FieldMoves.hasVisitedSpawn(save, row.spawn) then
      local entry = table_ and table_[row.landmark]
      out[#out + 1] = {
        landmark = row.landmark,
        spawn = row.spawn,
        index = entry and entry.index or nil,
        name = entry and entry.name or row.landmark,
      }
    end
  end
  return out, shown
end

-- ------------------------------------------------------------ menu paths
--
-- The *Function routines, each in its own jumptable order.  A menu use has
-- already picked the mon, so `ctx.mon` is that mon and CheckPartyMove is not
-- run again; what these decide is the badge and the situation.

local function badgeGate(ctx, move)
  local badge = FieldMoves.BADGE[move]
  if FieldMoves.hasBadge(ctx.save, badge) then return nil end
  -- CheckBadge queues .BadgeRequiredText itself and every caller then exits
  -- the jumptable, so this is a refusal WITH a line even from the OW paths
  -- that use CheckEngineFlag -- those call the flag check, not this.
  return { ok = false, badge = badge, text = FieldMoves.TEXT.BADGE_REQUIRED }
end

-- CutFunction: .CheckAble (badge, then CheckMapForSomethingToCut), .DoCut,
-- .FailCut.
function FieldMoves.cutFromMenu(ctx)
  local refused = badgeGate(ctx, "CUT")
  if refused then return refused end
  local replacement, animation = FieldMoves.somethingToCut(ctx)
  if not replacement then
    return { ok = false, text = FieldMoves.TEXT.CUT_NOTHING }
  end
  return {
    ok = true, action = "cut",
    replacement = replacement, animation = animation,
    text = FieldMoves.TEXT.USE_CUT,
  }
end

-- FlashFunction.CheckUseFlash: badge, then wTimeOfDayPalset == DARKNESS_PALSET
-- -- so FLASH is refused in a lit cave and on a route alike, and the refusal
-- is FieldMoveFailed's generic "Can't use that here."
--
-- ../pokecrystal/engine/events/overworld.asm:284-287 puts SpecialAerodactylChamber
-- between the two, and its carry is a second way into `.useflash`.
function FieldMoves.flashFromMenu(ctx)
  local refused = badgeGate(ctx, "FLASH")
  if refused then return refused end
  local chamber = ctx.openAerodactylWall and ctx.openAerodactylWall()
  if not ctx.dark and not chamber then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return { ok = true, action = "flash", text = FieldMoves.TEXT.BLINDING_FLASH }
end

-- SurfFunction: .TrySurf, .DoSurf, .FailSurf, .AlreadySurfing.  Note the
-- order -- already-surfing is checked BEFORE the facing tile, which is why
-- surfing up to a shore and pressing SURF says "You're already SURFING."
-- rather than "You can't SURF here."
function FieldMoves.surfFromMenu(ctx)
  local refused = badgeGate(ctx, "SURF")
  if refused then return refused end
  if ctx.alwaysOnBike then
    return { ok = false, text = FieldMoves.TEXT.CANT_SURF }
  end
  if FieldMoves.isSurfing(ctx.playerState) then
    return { ok = false, text = FieldMoves.TEXT.ALREADY_SURFING }
  end
  if not Permissions.isWater(ctx.facingColl)
      or FieldMoves.directionBlocked(ctx.playerColl, ctx.facing) then
    return { ok = false, text = FieldMoves.TEXT.CANT_SURF }
  end
  -- Crystal's added `farcall CheckFacingObject`, which pokegold's :339 tags
  -- BUG (../pokecrystal/engine/events/overworld.asm:364-365).
  if ctx.facingObject and GameVersion.fixes().surfOntoNpc then
    return { ok = false, text = FieldMoves.TEXT.CANT_SURF }
  end
  return {
    ok = true, action = "surf",
    state = FieldMoves.surfType(ctx.mon),
    text = FieldMoves.TEXT.USED_SURF,
  }
end

-- FlyFunction.TryFly: badge, then CheckOutdoorMap -- ROUTE or TOWN and nothing
-- else, so a Pokecenter counts as indoors.  The picker itself is the caller's
-- job; this only says whether it may open.
function FieldMoves.flyFromMenu(ctx)
  local refused = badgeGate(ctx, "FLY")
  if refused then return refused end
  if ctx.environment ~= "ROUTE" and ctx.environment ~= "TOWN" then
    -- .indoors falls to .FailFly, which is FieldMoveFailed.
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return { ok = true, action = "fly" }
end

-- StrengthFunction.TryStrength is the shortest of the seven: the badge, and
-- nothing else.  STRENGTH from the menu always succeeds once the PLAINBADGE is
-- in, wherever the player is standing, because all it does is set
-- BIKEFLAGS_STRENGTH_ACTIVE and say so.
function FieldMoves.strengthFromMenu(ctx)
  local refused = badgeGate(ctx, "STRENGTH")
  if refused then return refused end
  return {
    ok = true, action = "strength",
    text = FieldMoves.TEXT.USE_STRENGTH,
    after = FieldMoves.TEXT.MOVE_BOULDER,
  }
end

-- WaterfallFunction.TryWaterfall: badge, then CheckMapCanWaterfall.
function FieldMoves.waterfallFromMenu(ctx)
  local refused = badgeGate(ctx, "WATERFALL")
  if refused then return refused end
  if not FieldMoves.canWaterfall(ctx) then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return {
    ok = true, action = "waterfall", text = FieldMoves.TEXT.USE_WATERFALL,
  }
end

-- WhirlpoolFunction: .TryWhirlpool (badge, TryWhirlpoolMenu), .DoWhirlpool,
-- .FailWhirlpool.
function FieldMoves.whirlpoolFromMenu(ctx)
  local refused = badgeGate(ctx, "WHIRLPOOL")
  if refused then return refused end
  local replacement, animation = FieldMoves.somethingToWhirlpool(ctx)
  if not replacement then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return {
    ok = true, action = "whirlpool",
    replacement = replacement, animation = animation,
    text = FieldMoves.TEXT.USE_WHIRLPOOL,
  }
end

-- TryHeadbuttFromMenu: no badge at all (HEADBUTT is a TM, not an HM), just the
-- facing tile.
function FieldMoves.headbuttFromMenu(ctx)
  if not Permissions.isHeadbuttTree(ctx.facingColl) then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return { ok = true, action = "headbutt" }
end

-- ../pokecrystal/constants/map_object_constants.asm:145
local SPRITEMOVEDATA_SMASHABLE_ROCK = 0x18

-- ../pokecrystal/engine/events/overworld.asm:1317 TryRockSmashFromMenu
function FieldMoves.rockSmashFromMenu(ctx)
  local object = ctx.facingObject
  local def = object and object.def
  if not def or def.movement ~= SPRITEMOVEDATA_SMASHABLE_ROCK then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return {
    ok = true, action = "rocksmash", object = object,
    lastTalked = (def.index or 0) + 1,
  }
end

-- ../pokecrystal/engine/events/std_scripts.asm:241 SmashRockScript
function FieldMoves.rockSmashScriptKey(stdScripts, scripts)
  local entry = stdScripts and stdScripts.scripts
    and stdScripts.scripts.SmashRockScript
  local smash = entry and entry.key and scripts and scripts[entry.key]
  local jump = smash and smash[1]
  local ask = jump and jump.op == "farsjump" and jump.script
    and scripts[jump.script]
  for _, cmd in ipairs(ask or {}) do
    if cmd.op == "iftrue" and cmd.script then return cmd.script end
  end
  return nil
end

-- ../pokecrystal/engine/events/overworld.asm:1357 RockSmashFromMenuScript
function FieldMoves.rockSmashFromMenuScript(stdScripts, scripts, specialId)
  local key = FieldMoves.rockSmashScriptKey(stdScripts, scripts)
  if not key then return nil end
  local script = { { op = "refreshmap" } }
  local id = specialId and specialId("UpdateTimePals")
  if id then script[#script + 1] = { op = "special", id = id } end
  script[#script + 1] = { op = "sjump", script = key }
  return script
end

-- SweetScentFromMenu (engine/events/sweet_scent.asm): QueueScript then an
-- unconditional `ld a, $1 / ld [wFieldMoveSucceeded], a` -- no badge, no
-- tile test, nothing that can refuse the press.  Whether anything actually
-- turns up is answered later, by the queued script itself
-- (World:sweetScentEncounter), the same way a failed HEADBUTT still shakes
-- the tree before coming up empty.
function FieldMoves.sweetScentFromMenu(_ctx)
  return { ok = true, action = "sweetscent" }
end

-- DigFunction (engine/events/overworld.asm EscapeRopeOrDig): no badge -- DIG
-- is a TM -- just .CheckCanDig's CAVE / DUNGEON environment and a live dig
-- triple, which the world hands in as ctx.canEscapeRope.  .FailDig prints
-- _CantUseDigText for the move (the rope shares the check but fails silent).
function FieldMoves.digFromMenu(ctx)
  local env = ctx.environment
  if (env ~= "CAVE" and env ~= "DUNGEON") or not ctx.canEscapeRope then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return { ok = true, action = "dig", text = FieldMoves.TEXT.USE_DIG }
end

-- TeleportFunction .TryTeleport: CheckOutdoorMap (TOWN or ROUTE), then the
-- last spawn pair; World:warpToSpawn already resolves that pair with the
-- bedroom fallback the port boots with, so the outdoor test is the whole
-- refusal here.
function FieldMoves.teleportFromMenu(ctx)
  local env = ctx.environment
  if env ~= "TOWN" and env ~= "ROUTE" then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return {
    ok = true, action = "teleport", text = FieldMoves.TEXT.TELEPORT_RETURN,
  }
end

-- ../pokecrystal/engine/pokemon/mon_menu.asm:744 .CheckMonHasEnoughHP
function FieldMoves.softboiledFromMenu(ctx)
  local mon = ctx.mon
  local maxHp = mon and (mon.maxHp or (mon.stats and mon.stats.hp)) or 0
  local cost = math.floor(maxHp / 5)
  if not mon or (mon.hp or 0) <= cost then
    return { ok = false, text = FieldMoves.TEXT.NOT_ENOUGH_HP }
  end
  return { ok = true, action = "softboiled", cost = cost, inMenu = true }
end

local function softboiledMaxHp(mon)
  return mon and (mon.maxHp or (mon.stats and mon.stats.hp)) or 0
end

-- ../pokecrystal/engine/items/item_effects.asm:2043 .cant_use
function FieldMoves.softboiledTargetOk(user, target)
  if not (user and target) or target == user or target.isEgg then return false end
  return (target.hp or 0) > 0 and (target.hp or 0) < softboiledMaxHp(target)
end

-- ../pokecrystal/engine/items/item_effects.asm:1997 RemoveHP / :2005 RestoreHealth
function FieldMoves.softboiledTransfer(user, target, cost)
  if not FieldMoves.softboiledTargetOk(user, target) then return nil end
  local before = target.hp or 0
  user.hp = math.max(0, (user.hp or 0) - (cost or 0))
  target.hp = math.min(softboiledMaxHp(target), before + (cost or 0))
  return before, target.hp
end

FieldMoves.FROM_MENU = {
  CUT = FieldMoves.cutFromMenu,
  FLASH = FieldMoves.flashFromMenu,
  SURF = FieldMoves.surfFromMenu,
  FLY = FieldMoves.flyFromMenu,
  STRENGTH = FieldMoves.strengthFromMenu,
  WATERFALL = FieldMoves.waterfallFromMenu,
  WHIRLPOOL = FieldMoves.whirlpoolFromMenu,
  HEADBUTT = FieldMoves.headbuttFromMenu,
  ROCK_SMASH = FieldMoves.rockSmashFromMenu,
  SWEET_SCENT = FieldMoves.sweetScentFromMenu,
  DIG = FieldMoves.digFromMenu,
  TELEPORT = FieldMoves.teleportFromMenu,
  -- ../pokecrystal/engine/pokemon/mon_menu.asm:138 MonMenu_Softboiled_MilkDrink
  SOFTBOILED = FieldMoves.softboiledFromMenu,
  MILK_DRINK = FieldMoves.softboiledFromMenu,
}

-- ../pokecrystal/engine/events/overworld.asm:1330 TryRockSmashFromMenu .no_rock
function FieldMoves.fromMenu(moveId, ctx)
  local fn = FieldMoves.FROM_MENU[moveId]
  if not fn then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  return fn(ctx)
end

-- -------------------------------------------------------------- OW paths
--
-- Try*OW, reached from TryTileCollisionEvent.  The tile has already been
-- matched by the caller (that is what picked which of these to run), so these
-- start at CheckPartyMove and the badge is CheckEngineFlag -- silent.

-- TryCutOW: no mon or no badge is NOT silent here, it is CantCutScript, so an
-- uncuttable tree still tells you it can be cut.  The map check happens after
-- the YES, inside AskCutScript's `callasm .CheckMap`, which is why answering
-- YES to a tree in a tileset with no replacement block simply closes the box.
function FieldMoves.tryCutOW(ctx)
  local mon = FieldMoves.partyMoveUser(ctx.party, "CUT", ctx)
  if not mon or not FieldMoves.hasBadge(ctx.save, FieldMoves.BADGE.CUT) then
    return { ok = false, text = FieldMoves.TEXT.CAN_CUT, took = true }
  end
  local replacement, animation = FieldMoves.somethingToCut(ctx)
  return {
    ok = true, took = true, mon = mon,
    ask = FieldMoves.TEXT.ASK_CUT,
    action = replacement and "cut" or nil,
    replacement = replacement, animation = animation,
    text = FieldMoves.TEXT.USE_CUT,
  }
end

-- TryWhirlpoolOW.  Unlike CUT, TryWhirlpoolMenu runs BEFORE the ask, so a
-- whirlpool in a tileset with no replacement block gets the refusal line.
function FieldMoves.tryWhirlpoolOW(ctx)
  local mon = FieldMoves.partyMoveUser(ctx.party, "WHIRLPOOL", ctx)
  local replacement, animation = FieldMoves.somethingToWhirlpool(ctx)
  if not mon
      or not FieldMoves.hasBadge(ctx.save, FieldMoves.BADGE.WHIRLPOOL)
      or not replacement then
    return {
      ok = false, took = true, text = FieldMoves.TEXT.MAY_PASS_WHIRLPOOL,
    }
  end
  return {
    ok = true, took = true, mon = mon,
    ask = FieldMoves.TEXT.ASK_WHIRLPOOL,
    action = "whirlpool",
    replacement = replacement, animation = animation,
    text = FieldMoves.TEXT.USE_WHIRLPOOL,
  }
end

-- TryWaterfallOW.
function FieldMoves.tryWaterfallOW(ctx)
  local mon = FieldMoves.partyMoveUser(ctx.party, "WATERFALL", ctx)
  if not mon
      or not FieldMoves.hasBadge(ctx.save, FieldMoves.BADGE.WATERFALL)
      or not FieldMoves.canWaterfall(ctx) then
    return { ok = false, took = true, text = FieldMoves.TEXT.HUGE_WATERFALL }
  end
  return {
    ok = true, took = true, mon = mon,
    ask = FieldMoves.TEXT.ASK_WATERFALL,
    action = "waterfall", text = FieldMoves.TEXT.USE_WATERFALL,
  }
end

-- TrySurfOW.  Every failure arm is `.quit` -- `xor a`, no script, no text --
-- so a shore with no SURF mon is a dead A press, not a refusal.  It is also
-- the LAST thing TryTileCollisionEvent tries, so it can afford to be silent.
function FieldMoves.trySurfOW(ctx)
  if FieldMoves.isSurfing(ctx.playerState) then return { ok = false } end
  if not Permissions.isWater(ctx.facingColl) then return { ok = false } end
  if FieldMoves.directionBlocked(ctx.playerColl, ctx.facing) then
    return { ok = false }
  end
  if not FieldMoves.hasBadge(ctx.save, FieldMoves.BADGE.SURF) then
    return { ok = false }
  end
  local mon = FieldMoves.partyMoveUser(ctx.party, "SURF", ctx)
  if not mon then return { ok = false } end
  if ctx.alwaysOnBike then return { ok = false } end
  return {
    ok = true, took = true, mon = mon,
    ask = FieldMoves.TEXT.ASK_SURF,
    action = "surf", state = FieldMoves.surfType(mon),
    text = FieldMoves.TEXT.USED_SURF,
  }
end

-- TryStrengthOW, which is a callasm inside AskStrengthScript rather than a
-- tile event: walking into a boulder runs the boulder's own script, and that
-- script asks this which of its three lines to print.  The three wScriptVar
-- values are transcribed as strings:
--
--   0  "already"  STRENGTH is already active   -> BouldersMoveText
--   1  "nope"     no mon / no PLAINBADGE       -> BouldersMayMoveText
--   2  "ask"      may be turned on right now   -> AskStrengthScript
--
-- Note the inversion in the cart: `bit BIKEFLAGS_STRENGTH_ACTIVE_F` jumps to
-- .already_using when the bit is CLEAR, so 2 is the not-yet case and 0 the
-- already-on one.  Reading that backwards swaps the two lines.
function FieldMoves.tryStrengthOW(ctx)
  local mon = FieldMoves.partyMoveUser(ctx.party, "STRENGTH", ctx)
  if not mon or not FieldMoves.hasBadge(ctx.save, FieldMoves.BADGE.STRENGTH) then
    return { ok = false, took = true, text = FieldMoves.TEXT.BOULDERS_MAY_MOVE }
  end
  if ctx.strengthActive then
    return { ok = false, took = true, text = FieldMoves.TEXT.BOULDERS_MOVE }
  end
  return {
    ok = true, took = true, mon = mon,
    ask = FieldMoves.TEXT.ASK_STRENGTH,
    action = "strength",
    text = FieldMoves.TEXT.USE_STRENGTH,
    after = FieldMoves.TEXT.MOVE_BOULDER,
  }
end

return FieldMoves
