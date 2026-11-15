-- The ornaments in the player's bedroom: what the player owns, what is set up
-- where, and the two routines that put both on the map.
-- engine/overworld/decorations.asm, with data/decorations/attributes.asm,
-- names.asm and decorations.asm beside it.
--
-- Three separate pieces of state, and keeping them apart is the whole model:
--
--   OWNED     one wEventFlags bit per decoration (DECOATTR_EVENT_FLAG).  Set
--             means the player has it; nothing else ever clears one.  This is
--             the same bitfield `setevent` writes, which is why owning a
--             decoration survives in the save with no new field.
--   PLACED    eight bytes (wDecoBed .. wDecoRightOrnament), each holding the
--             DECO_* id standing in that slot or 0 for nothing.  A slot holds
--             ONE thing: setting up a second bed puts the first away.
--   VISIBLE   what the map shows, which is neither of the above.  It is
--             rebuilt from PLACED by ToggleDecorationsVisibility (the four
--             object slots) and ToggleMaptileDecorations (the four blocks) --
--             and only ever on a MAP LOAD, because those are the
--             PLAYERS_HOUSE_2F NEWMAP and TILES callbacks.  A flag a running
--             script sets does not move an object; the object list is read
--             when the map loads and not again, which is why the PC's own
--             `warp NONE, 0, 0` (Script_warp's MAPSETUP_BADWARP arm) is what
--             makes a placement appear.
--
-- Everything here is love-free and takes its state by argument, so the menu on
-- top of it (src/ui/gen2/DecorationMenu.lua) and the tests can drive the same
-- routines the map callbacks do.

local CommonText = require("src.core.gen2.CommonText")
local RomText = require("src.core.RomText")

local Decorations = {}

local romData = nil

local function romLine(label, ...)
  return CommonText.plain(RomText(romData, label, nil, ...))
end

-- constants/deco_constants.asm, decoration types.  The type decides how
-- GetDecoName spells the row and, for the four maptile kinds, that
-- DECOATTR_SPRITE is a BLOCK id rather than a sprite one.
local PLANT, BED, CARPET, POSTER, DOLL, BIGDOLL = 1, 2, 3, 4, 5, 6

-- The eight wDeco* bytes.  `slot` on an action names one of these.
Decorations.SLOTS = {
  "bed", "carpet", "plant", "poster", "console", "bigDoll",
  "leftOrnament", "rightOrnament",
}

-- DoDecorationAction2.DecoActions, as a slot plus a direction rather than a
-- jumptable index: the fourteen entries are seven pairs, and the pair is the
-- only thing any caller cares about.  The ornament pair is the odd one out --
-- it asks which side first, so its slot is decided at run time.
local ACTIONS = {
  SET_UP_BED = { slot = "bed" },
  PUT_AWAY_BED = { slot = "bed", put = true },
  SET_UP_CARPET = { slot = "carpet" },
  PUT_AWAY_CARPET = { slot = "carpet", put = true },
  SET_UP_PLANT = { slot = "plant" },
  PUT_AWAY_PLANT = { slot = "plant", put = true },
  SET_UP_POSTER = { slot = "poster" },
  PUT_AWAY_POSTER = { slot = "poster", put = true },
  SET_UP_CONSOLE = { slot = "console" },
  PUT_AWAY_CONSOLE = { slot = "console", put = true },
  SET_UP_BIG_DOLL = { slot = "bigDoll" },
  PUT_AWAY_BIG_DOLL = { slot = "bigDoll", put = true },
  SET_UP_DOLL = { ornament = true },
  PUT_AWAY_DOLL = { ornament = true, put = true },
}
Decorations.ACTIONS = ACTIONS

-- wEventFlags bit numbers, from constants/event_flags.asm.  Numbers rather
-- than names because that is what the bitfield is keyed by everywhere else in
-- this port (src/world/gen2/Events.lua), and because the extracted scripts
-- that share these bits carry numbers too.
local EVENT_TEMPORARY_UNTIL_MAP_RELOAD_1 = 0
local EVENT_DECO_BED_1 = 676
local EVENT_DECO_CARPET_1 = 680
local EVENT_DECO_PLANT_1 = 684
local EVENT_DECO_POSTER_1 = 687
local EVENT_DECO_FAMICOM = 691
local EVENT_DECO_PIKACHU_DOLL = 695
local EVENT_PLAYERS_ROOM_POSTER = 716
local EVENT_DECO_GOLD_TROPHY = 717
local EVENT_DECO_SILVER_TROPHY = 718
local EVENT_DECO_BIG_SNORLAX_DOLL = 719

Decorations.EVENT_PLAYERS_ROOM_POSTER = EVENT_PLAYERS_ROOM_POSTER

-- The four objects PLAYERS_HOUSE_2F hangs its decorations off.  Each is a
-- wVariableSprites slot (SPRITE_VARS-relative, the way `variablesprite`'s byte
-- already is) paired with the object's own event flag, and
-- ToggleDecorationVisibility writes both: the sprite byte says WHAT stands
-- there and the flag says WHETHER it stands there at all.
Decorations.OBJECT_SLOTS = {
  { slot = "console", sprite = 0, flag = 1857 },        -- SPRITE_CONSOLE
  { slot = "leftOrnament", sprite = 1, flag = 1858 },   -- SPRITE_DOLL_1
  { slot = "rightOrnament", sprite = 2, flag = 1859 },  -- SPRITE_DOLL_2
  { slot = "bigDoll", sprite = 3, flag = 1860 },        -- SPRITE_BIG_DOLL
}

-- data/decorations/attributes.asm, verbatim and in its order: row 0 is the
-- unnamed CANCEL row every category menu ends on, and the seven rows whose
-- name is PUT_IT_AWAY are the category headers the deco constants share their
-- numbering with (BEDS = 1, CARPETS = 6, ...).  So this table is indexed by
-- DECO_*, and `wMenuSelection` on the cart is an index straight into it.
--
-- `sprite` is one byte with two meanings, exactly as DECOATTR_SPRITE is: a
-- BLOCK id for the four kinds ToggleMaptileDecorations paints, and a SPRITE_*
-- byte for the four an object stands on.  The SPRITE_* names are in comments
-- because the value the cart stores IS the byte -- wVariableSprites holds it
-- raw and World:resolveSprite looks it up in constants.spriteOrder.
local function decoNameLabel(index)
  return "DecorationNames#" .. (index + 1)
end

local function deco(kind, name, action, flag, sprite)
  if type(name) == "number" then name = decoNameLabel(name) end
  return { type = kind, name = name, action = action, flag = flag,
           sprite = sprite }
end

local TEMP = EVENT_TEMPORARY_UNTIL_MAP_RELOAD_1

-- constants/deco_constants.asm:21
local CANCEL_DECO, PUT_IT_AWAY = 0, 1
local MAGNAPLANT, TROPICPLANT, JUMBOPLANT, TOWN_MAP_POSTER = 2, 3, 4, 5
local FAMICOM, SUPER_NES, NINTENDO_64, VIRTUAL_BOY = 6, 7, 8, 9
local GOLD_TROPHY, SILVER_TROPHY, SURF_PIKA_DOLL = 10, 11, 12
local NAME_BED, NAME_CARPET, NAME_POSTER, NAME_DOLL, NAME_BIG = 13, 14, 15, 16, 17
local FEATHERY_BED, PIKACHU_BED, PINK_BED, POLKADOT_BED = 18, 19, 20, 21
local RED_CARPET, BLUE_CARPET, YELLOW_CARPET, GREEN_CARPET = 22, 23, 24, 25

local ATTRIBUTES = {
  [0] = deco(PLANT, CANCEL_DECO, nil, TEMP, 0),
  deco(PLANT, PUT_IT_AWAY, "PUT_AWAY_BED", TEMP, 0), -- BEDS
  deco(BED, FEATHERY_BED, "SET_UP_BED", EVENT_DECO_BED_1 + 0, 0x1b),
  deco(BED, PINK_BED, "SET_UP_BED", EVENT_DECO_BED_1 + 1, 0x1c),
  deco(BED, POLKADOT_BED, "SET_UP_BED", EVENT_DECO_BED_1 + 2, 0x1d),
  deco(BED, PIKACHU_BED, "SET_UP_BED", EVENT_DECO_BED_1 + 3, 0x1e),
  deco(PLANT, PUT_IT_AWAY, "PUT_AWAY_CARPET", TEMP, 0), -- CARPETS
  deco(CARPET, RED_CARPET, "SET_UP_CARPET", EVENT_DECO_CARPET_1 + 0, 0x08),
  deco(CARPET, BLUE_CARPET, "SET_UP_CARPET", EVENT_DECO_CARPET_1 + 1, 0x0b),
  deco(CARPET, YELLOW_CARPET, "SET_UP_CARPET", EVENT_DECO_CARPET_1 + 2, 0x0e),
  deco(CARPET, GREEN_CARPET, "SET_UP_CARPET", EVENT_DECO_CARPET_1 + 3, 0x11),
  deco(PLANT, PUT_IT_AWAY, "PUT_AWAY_PLANT", TEMP, 0), -- PLANTS
  deco(PLANT, MAGNAPLANT, "SET_UP_PLANT", EVENT_DECO_PLANT_1 + 0, 0x20),
  deco(PLANT, TROPICPLANT, "SET_UP_PLANT", EVENT_DECO_PLANT_1 + 1, 0x21),
  deco(PLANT, JUMBOPLANT, "SET_UP_PLANT", EVENT_DECO_PLANT_1 + 2, 0x22),
  deco(PLANT, PUT_IT_AWAY, "PUT_AWAY_POSTER", TEMP, 0), -- POSTERS
  -- The TOWN MAP poster is a DECO_PLANT: its name is a DecorationNames entry
  -- rather than a species, so GetDecoName must not append " POSTER" to it.
  deco(PLANT, TOWN_MAP_POSTER, "SET_UP_POSTER", EVENT_DECO_POSTER_1 + 0, 0x1f),
  deco(POSTER, "PIKACHU", "SET_UP_POSTER", EVENT_DECO_POSTER_1 + 1, 0x23),
  deco(POSTER, "CLEFAIRY", "SET_UP_POSTER", EVENT_DECO_POSTER_1 + 2, 0x24),
  deco(POSTER, "JIGGLYPUFF", "SET_UP_POSTER", EVENT_DECO_POSTER_1 + 3, 0x25),
  deco(PLANT, PUT_IT_AWAY, "PUT_AWAY_CONSOLE", TEMP, 0), -- CONSOLES
  deco(PLANT, FAMICOM, "SET_UP_CONSOLE", EVENT_DECO_FAMICOM + 0, 0x5c), -- SPRITE_FAMICOM
  deco(PLANT, SUPER_NES, "SET_UP_CONSOLE", EVENT_DECO_FAMICOM + 1, 0x5b),
  deco(PLANT, NINTENDO_64, "SET_UP_CONSOLE", EVENT_DECO_FAMICOM + 2, 0x51),
  deco(PLANT, VIRTUAL_BOY, "SET_UP_CONSOLE", EVENT_DECO_FAMICOM + 3, 0x57),
  deco(PLANT, PUT_IT_AWAY, "PUT_AWAY_BIG_DOLL", TEMP, 0), -- BIG_DOLLS
  deco(BIGDOLL, "SNORLAX", "SET_UP_BIG_DOLL", EVENT_DECO_BIG_SNORLAX_DOLL + 0, 0x33),
  deco(BIGDOLL, "ONIX", "SET_UP_BIG_DOLL", EVENT_DECO_BIG_SNORLAX_DOLL + 1, 0x50),
  deco(BIGDOLL, "LAPRAS", "SET_UP_BIG_DOLL", EVENT_DECO_BIG_SNORLAX_DOLL + 2, 0x47),
  deco(PLANT, PUT_IT_AWAY, "PUT_AWAY_DOLL", TEMP, 0), -- DOLLS
  deco(DOLL, "PIKACHU", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 0, 0x8e),
  -- The surfing Pikachu doll is a DECO_PLANT too, and for the same reason:
  -- "SURF PIKACHU DOLL" is one DecorationNames string, not a mon plus " DOLL".
  deco(PLANT, SURF_PIKA_DOLL, "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 1, 0x34),
  deco(DOLL, "CLEFAIRY", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 2, 0x8f),
  deco(DOLL, "JIGGLYPUFF", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 3, 0x94),
  deco(DOLL, "BULBASAUR", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 4, 0x93),
  deco(DOLL, "CHARMANDER", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 5, 0x90),
  deco(DOLL, "SQUIRTLE", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 6, 0x89),
  deco(DOLL, "POLIWAG", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 7, 0x8d),
  deco(DOLL, "DIGLETT", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 8, 0x8c),
  -- STARYU's doll stands on SPRITE_STARMIE; the cart's own row says so.
  deco(DOLL, "STARYU", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 9, 0x92),
  deco(DOLL, "MAGIKARP", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 10, 0x88),
  deco(DOLL, "ODDISH", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 11, 0x85),
  deco(DOLL, "GENGAR", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 12, 0x86),
  deco(DOLL, "SHELLDER", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 13, 0x84),
  deco(DOLL, "GRIMER", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 14, 0x95),
  deco(DOLL, "VOLTORB", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 15, 0x9b),
  deco(DOLL, "WEEDLE", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 16, 0x83),
  deco(DOLL, "UNOWN", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 17, 0x80),
  deco(DOLL, "GEODUDE", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 18, 0x81),
  deco(DOLL, "MACHOP", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 19, 0x9a),
  deco(DOLL, "TENTACOOL", "SET_UP_DOLL", EVENT_DECO_PIKACHU_DOLL + 20, 0x98),
  -- Both trophies are SET_UP_DOLL: a trophy stands in an ornament slot.
  deco(PLANT, GOLD_TROPHY, "SET_UP_DOLL", EVENT_DECO_GOLD_TROPHY, 0x5e),
  deco(PLANT, SILVER_TROPHY, "SET_UP_DOLL", EVENT_DECO_SILVER_TROPHY, 0x5f),
}
Decorations.ATTRIBUTES = ATTRIBUTES

-- The seven category menus, in _PlayerDecorationMenu's .owned_pointers order.
-- `id` is the DECO_* of the category's own PUT_IT_AWAY row, which is exactly
-- what FindOwnedDecosInCategory appends to its list, and `members` is that
-- routine's own db list -- transcribed rather than derived from a range,
-- because the doll list runs past the two trophies and the big dolls do not
-- sit next to the small ones.
local function range(first, last)
  local out = {}
  for id = first, last do out[#out + 1] = id end
  return out
end

Decorations.CATEGORIES = {
  { id = 1, members = range(2, 5) },
  { id = 6, members = range(7, 10) },
  { id = 11, members = range(12, 14) },
  { id = 15, members = range(16, 19) },
  { id = 20, members = range(21, 24) },
  { id = 29, members = range(30, 52) },
  { id = 25, members = range(26, 28) },
}

-- data/decorations/decorations.asm DecorationIDs: DECOFLAG_* -> DECO_*.  The
-- only thing that reads it is GetDecorationID, i.e. the routines that GIVE a
-- decoration, which name what they hand over by DECOFLAG.
local DECORATION_IDS = {}
do
  local order = {
    range(2, 5), range(7, 10), range(12, 14), range(16, 19), range(21, 24),
    range(30, 50), range(26, 28), { 51, 52 },
  }
  for _, group in ipairs(order) do
    for _, id in ipairs(group) do
      DECORATION_IDS[#DECORATION_IDS + 1] = id
    end
  end
end
-- DECOFLAG_* is a `const_def` block, so it is 0-based: shift the 1-based Lua
-- list rather than leaving a caller to guess.
function Decorations.idForFlag(decoFlag)
  return DECORATION_IDS[(decoFlag or 0) + 1]
end

-- constants/deco_constants.asm DECOFLAG_*, for the two callers that name one.
Decorations.DECOFLAG_GOLD_TROPHY_DOLL = 43
Decorations.DECOFLAG_SILVER_TROPHY_DOLL = 44

-- DescribeDecoration's five arms and the wDeco* byte each one reads
-- (constants/script_constants.asm DECODESC_*, which is what the cache's
-- decorationOrder carries).  Only the three that share
-- DecorationDesc_OrnamentOrConsole put a NAME in wStringBuffer3; the poster
-- arm picks a different script instead, and the giant ornament's says the same
-- thing whatever is standing there.
Decorations.DESC_SLOTS = {
  DECODESC_POSTER = { slot = "poster" },
  DECODESC_LEFT_DOLL = { slot = "leftOrnament", named = true },
  DECODESC_RIGHT_DOLL = { slot = "rightOrnament", named = true },
  DECODESC_BIG_DOLL = { slot = "bigDoll" },
  DECODESC_CONSOLE = { slot = "console", named = true },
}

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

-- The eight wDeco* bytes, on the save.  InitDecorations (called from
-- intro_menu.asm at New Game) is the two defaults below: the feathery bed and
-- the TOWN MAP poster are set up before the player has chosen anything, which
-- is why a new game's room already has a bed in it.  Filling them in lazily
-- rather than in Save.newGame means an older save gets the same room.
function Decorations.state(save)
  if type(save) ~= "table" then return {} end
  local state = save.decorations
  if not state then
    state = { bed = 2, poster = 16 } -- DECO_FEATHERY_BED, DECO_TOWN_MAP
    save.decorations = state
  end
  return state
end

-- ------------------------------------------------------------ the registry
--
-- The `decorations` registry (src/mods/Schemas.lua), one of the Gen 2-only
-- six: Red's bedroom has no PC decoration menu, so the name is gated under
-- Gen 1 and routed to data.gen2Decorations under Gen 2.  src/mods/Builtins.lua
-- seeds it with the ATTRIBUTES rows above, engine-owned.
--
-- Ids are "deco:<n>", where n is the attribute row's index -- the DECO_* byte,
-- which is what wMenuSelection holds and what every caller passes.  The cart's
-- decoration constants are a bare const_def block with no name table in the
-- ROM behind it, so there is nothing to spell them by; battle_anims addresses
-- its unnamed rows the same way ("subanim:<n>").
-- data/decorations/names.asm:1
local function nameText(data, index)
  return RomText(data, decoNameLabel(index), nil)
end

local function baseName(data, name)
  if type(name) == "string" and name:match("^DecorationNames#%d+$") then
    return RomText(data, name, nil)
  end
  return name
end

local DECO_ID_PREFIX = "deco:"
local registryRows = nil

function Decorations.idFor(decoId)
  return DECO_ID_PREFIX .. tostring(decoId)
end

-- One read point for the attribute row, so the merged record reaches every
-- caller: name/owns/give/apply/visibility/tiles below all come through here,
-- as do src/ui/gen2/DecorationMenu.lua and the two DECO_* screens.  Falls back
-- to the module's own table, which is what a headless test and a boot with no
-- loader get.
function Decorations.attributes(decoId)
  if decoId == nil then return nil end
  local merged = registryRows and registryRows[DECO_ID_PREFIX .. tostring(decoId)]
  return merged or ATTRIBUTES[decoId]
end

-- vanilla registrations, engine-owned
function Decorations.registerInto(registry, _, owner)
  local count = 0
  for decoId, attr in pairs(ATTRIBUTES) do
    registry:register(Decorations.idFor(decoId), attr, owner)
    count = count + 1
  end
  return count
end

-- the merged table, held by reference; nil forgets it
function Decorations.useRegistry(data)
  romData = data
  registryRows = data and data.gen2Decorations or nil
  return registryRows ~= nil
end

-- GetDecoName: the display name, built from the type and the name column.  The
-- four types that name a SPECIES read the mon's name out of the data table,
-- which is what `monName` is for; with no resolver the constant is already the
-- English name for all twenty-four of them.
function Decorations.name(decoId, monName)
  local attr = Decorations.attributes(decoId)
  if not attr then return "" end
  local base = baseName(romData, attr.name)
  if attr.type == BED then return base .. nameText(romData, NAME_BED) end
  if attr.type == CARPET then return base .. nameText(romData, NAME_CARPET) end
  local mon = (monName and monName(base)) or base
  if attr.type == POSTER then return mon .. nameText(romData, NAME_POSTER) end
  if attr.type == DOLL then return mon .. nameText(romData, NAME_DOLL) end
  if attr.type == BIGDOLL then return nameText(romData, NAME_BIG) .. mon end
  return base
end

--------------------------------------------------------------------------
-- Owning
--------------------------------------------------------------------------

-- DecorationFlagAction CHECK_FLAG.  `events` is the src/world/gen2/Events.lua
-- bitfield the rest of the port keys by number.
function Decorations.owns(events, decoId)
  local attr = Decorations.attributes(decoId)
  if not (events and attr and attr.flag) then return false end
  return events:get(attr.flag) and true or false
end

-- SetSpecificDecorationFlag, i.e. how a decoration is acquired at all: the
-- NORMAL_BOX / GORGEOUS_BOX trophies (engine/items/item_effects.asm), Mom's
-- doll purchases (engine/events/mom_phone.asm Mom_GiveItemOrDoll) and Mystery
-- Gift all end here.  Named by DECOFLAG_*, because that is what every caller
-- passes.
function Decorations.giveFlag(events, decoFlag)
  return Decorations.give(events, Decorations.idForFlag(decoFlag))
end

function Decorations.give(events, decoId)
  local attr = Decorations.attributes(decoId)
  if not (events and attr and attr.flag) then return false end
  events:set(attr.flag, true)
  return true
end

-- .FindOwnedDecos: the categories with at least one owned decoration, in the
-- .owned_pointers order.  EXIT is not in that list -- DecoExitMenu is the
-- eighth .category_pointers row and is always on the menu -- so the caller
-- appends it, the way .FindCategoriesWithOwnedDecos appends its own 7.
function Decorations.ownedCategories(events)
  local out = {}
  for _, category in ipairs(Decorations.CATEGORIES) do
    for _, id in ipairs(category.members) do
      if Decorations.owns(events, id) then
        out[#out + 1] = category
        break
      end
    end
  end
  return out
end

-- FindOwnedDecosInCategory: every owned decoration in the category, then the
-- category's own PUT_IT_AWAY row, then row 0 (CANCEL).  An empty category
-- answers an empty list and PopulateDecoCategoryMenu prints "There's nothing
-- to choose." instead of opening a menu.
function Decorations.rows(events, category)
  local out = {}
  for _, id in ipairs(category and category.members or {}) do
    if Decorations.owns(events, id) then out[#out + 1] = id end
  end
  if #out == 0 then return out end
  out[#out + 1] = category.id
  out[#out + 1] = 0
  return out
end

--------------------------------------------------------------------------
-- Placing
--------------------------------------------------------------------------

-- data/text/common_1.asm:316
local SET_UP = "_SetUpTheDecoText"
local PUT_AWAY = "_PutAwayTheDecoText"
local NOTHING_TO_PUT_AWAY = "_NothingToPutAwayText"
local ALREADY_SET_UP = "_AlreadySetUpText"
local PUT_AWAY_AND_SET_UP = "_PutAwayAndSetUpText"

local function pages(body)
  local out = {}
  for page in (body .. "\f"):gmatch("(.-)\f") do out[#out + 1] = page end
  return out
end

-- DoDecorationAction2 for one menu row.  Returns
--   changed  wChangedDecorations: TRUE only when the room actually changed,
--            which is what makes the PC reload the map on the way out
--   pages    the text to print, in order
-- `side` is "left" or "right" and only an ornament row reads it; a nil side on
-- an ornament row is DecoAction_AskWhichSide's cancel (`scf`), which changes
-- nothing and prints nothing.
function Decorations.apply(state, decoId, side, monName)
  local attr = Decorations.attributes(decoId)
  if not (state and attr) then return false, {} end
  local action = attr.action and ACTIONS[attr.action]
  -- DecoAction_nothing: row 0, the CANCEL row.  `scf` and no text.
  if not action then return false, {} end

  local slot = action.slot
  if action.ornament then
    if side ~= "left" and side ~= "right" then return false, {} end
    slot = (side == "right") and "rightOrnament" or "leftOrnament"
  end

  local current = state[slot] or 0
  local name = function(id) return Decorations.name(id, monName) end

  if action.put then
    -- DecoAction_TryPutItAway clears the slot BEFORE it checks what was in it,
    -- so putting away an empty slot still writes a 0 over the 0.
    state[slot] = 0
    if current == 0 then return false, { romLine(NOTHING_TO_PUT_AWAY) } end
    -- DecoAction_PutItAway_Ornament names the thing that WAS out, not the row
    -- the player picked (the row is the PUT IT AWAY row and has no name).
    return true, { romLine(PUT_AWAY, name(current)) }
  end

  if current == decoId then
    -- .alreadythere: carry, so nothing is written and nothing changed.
    return false, { romLine(ALREADY_SET_UP) }
  end

  state[slot] = decoId
  if current == 0 then
    return true, { romLine(SET_UP, name(decoId)) }
  end
  return true, pages(romLine(PUT_AWAY_AND_SET_UP, name(current), name(decoId)))
end

-- DecoAction_SetItUp_Ornament .getwhichside: setting a doll up on one side
-- when the SAME doll is already on the other takes it off the other side --
-- there is only one of each.  Called by the menu right after apply() on an
-- ornament row, because the cart does it inside the same action.
function Decorations.clearOtherSide(state, decoId, side)
  if not (state and decoId and decoId ~= 0) then return end
  local other = (side == "right") and "leftOrnament" or "rightOrnament"
  if state[other] == decoId then state[other] = 0 end
end

--------------------------------------------------------------------------
-- Showing: the two map callbacks
--------------------------------------------------------------------------

-- ToggleDecorationsVisibility (the PLAYERS_HOUSE_2F MAPCALLBACK_NEWMAP).  One
-- row per object slot: an empty slot SETS the object's event flag, which hides
-- it, and a filled one clears the flag and writes the decoration's sprite byte
-- into wVariableSprites.
--
-- Answers a plain list so the caller can apply it to a live world or a test
-- table; nothing here touches love or the map.
function Decorations.visibility(state)
  local out = {}
  for _, row in ipairs(Decorations.OBJECT_SLOTS) do
    local decoId = state and state[row.slot] or 0
    local attr = Decorations.attributes(decoId)
    if decoId ~= 0 and attr then
      out[#out + 1] = { sprite = row.sprite, byte = attr.sprite,
                        flag = row.flag, hidden = false }
    else
      out[#out + 1] = { sprite = row.sprite, flag = row.flag, hidden = true }
    end
  end
  return out
end

-- ToggleMaptileDecorations (the MAPCALLBACK_TILES one).  Its coordinates "work
-- the same way as for changeblock": PadCoords_de adds 4 to each and
-- GetBlockLocation halves them, so the pairs in the asm are CELL coordinates
-- and the block written is (x / 2, y / 2) -- the same halving
-- src/script/gen2/Vm.lua does for `changeblock`.
--
--   bed    cell (0, 4) -> block (0, 2)
--   plant  cell (7, 4) -> block (3, 2)
--   poster cell (6, 0) -> block (3, 0)
--   carpet cell (0, 0) -> block (0, 0), and cell (0, 2) -> block row (0, 1)
--
-- The carpet is the only one that writes more than one block: its top-left
-- block is the sprite byte and the row under it is +1, +2, +1.  An empty slot
-- writes NOTHING (SetDecorationTile's `and a / ret z`), so the map keeps the
-- bare block it was loaded with.
function Decorations.tiles(state)
  local out = {}
  local function put(slot, blockX, blockY)
    local attr = Decorations.attributes(state and state[slot])
    if attr and attr.sprite and attr.sprite ~= 0 then
      out[#out + 1] = { x = blockX, y = blockY, block = attr.sprite }
      return attr.sprite
    end
    return nil
  end
  put("bed", 0, 2)
  put("plant", 3, 2)
  put("poster", 3, 0)
  local carpet = put("carpet", 0, 0)
  if carpet then
    out[#out + 1] = { x = 0, y = 1, block = carpet + 1 }
    out[#out + 1] = { x = 1, y = 1, block = carpet + 2 }
    out[#out + 1] = { x = 2, y = 1, block = carpet + 1 }
  end
  return out
end

-- SetPosterVisibility, which rides along inside ToggleMaptileDecorations: the
-- bedroom's poster bg_event is BGEVENT_IFSET on EVENT_PLAYERS_ROOM_POSTER, so
-- a bare wall must not be readable at all.
function Decorations.posterVisible(state)
  return ((state and state.poster) or 0) ~= 0
end

return Decorations
