-- Gen 2 overworld vertical slice: COLL_* collision, warps, connected
-- neighbor strips (RBY-style), seamless edge crossings, survey zoom,
-- OW sprites + SPRITEMOVEDATA walk/spin paths on current map and neighbor
-- strips.  Mounted from Game2; leaves Gen 1 Map.lua alone.

local Apricorns = require("src.core.gen2.Apricorns")
-- The mod-override choke point: every generated-cache path a mod can shadow
-- with overrides/ or an AssetTransform output has to be resolved through here
-- (src/render/Assets.lua:33), which a raw love.graphics.newImage bypasses.
local Assets = require("src.render.Assets")
local Bag = require("src.inventory.Bag")
local Battle = require("src.battle.gen2.Battle")
local BattleMusic = require("src.battle.gen2.BattleMusic")
local Bike = require("src.world.gen2.Bike")
local BorderFill = require("src.world.gen2.BorderFill")
local Boxes = require("src.core.gen2.Boxes")
local Breeding = require("src.core.gen2.Breeding")
local BugContest = require("src.core.gen2.BugContest")
local CallAsm = require("src.script.gen2.CallAsm")
local Camera = require("src.render.Camera")
local Clock = require("src.core.gen2.Clock")
local CatchTutorial = require("src.core.gen2.CatchTutorial")
local Decorations = require("src.core.gen2.Decorations")
local MomShopping = require("src.core.gen2.MomShopping")
local CmdQueue = require("src.world.gen2.CmdQueue")
local Encounter = require("src.battle.gen2.Encounter")
local ChoiceBox = require("src.ui.ChoiceBox")
local Events = require("src.world.gen2.Events")
local FieldMoves = require("src.world.gen2.FieldMoves")
local FixedStep = require("src.core.FixedStep")
local Follower = require("src.world.gen2.Follower")
local Font = require("src.render.Font")
-- Two call sites only (World:step's tail, World:interact), both no-ops until
-- a mod has taken a facade (src/mods/Gen2Compat.lua).
local Gen1Facade = require("src.mods.Gen2Compat")
local GbcPalette = require("src.render.GbcPalette")
local Playfield = require("src.render.Playfield")
local Gen2Save = require("src.core.gen2.Save")
local HallOfFame = require("src.core.gen2.HallOfFame")
local HiddenItems = require("src.world.gen2.HiddenItems")
local Mail = require("src.core.gen2.Mail")
local Map = require("src.world.gen2.Map")
local Palettes = require("src.world.gen2.Palettes")
local Mon = require("src.battle.gen2.Mon")
local Movement = require("src.script.gen2.Movement")
local Music = require("src.core.Music")
local NPC = require("src.world.gen2.Npc")
local Party = require("src.pokemon.Party")
local Permissions = require("src.world.gen2.Permissions")
local Pipelines = require("src.render.Pipelines")
local PixelCanvas = require("src.render.PixelCanvas")
local Player = require("src.world.gen2.Player")
local Pokerus = require("src.core.gen2.Pokerus")
local Roamers = require("src.core.gen2.Roamers")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local StepEvents = require("src.world.gen2.StepEvents")
local Tilt = require("src.render.Tilt")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local TrainerHouse = require("src.world.gen2.TrainerHouse")
local Trainers = require("src.world.gen2.Trainers")
local Unown = require("src.core.gen2.Unown")
local Vm = require("src.script.gen2.Vm")
local Zoom = require("src.render.Zoom")

-- SFX_* indices from audio/sfx_pointers.asm (constants.sfxOrder).
local SFX = {
  ITEM = 1,
  GET_TM = 0x9b,
  READ_TEXT_2 = 8,
  SECOND_PART_OF_ITEMFINDER = 0x12,
  GAME_FREAK_LOGO_GS = 0xaa,
  BOOT_PC = 0x0d,
  SANDSTORM = 0x6d,
  STRENGTH = 27,
  PLACE_PUZZLE_PIECE_DOWN = 30,
  BUBBLEBEAM = 81,
  SURF = 83,
  FLASH = 169,
  ENTER_DOOR = 31,
  WARP_TO = 19,
  EXIT_BUILDING = 35,
  JUMP_OVER_LEDGE = 0x16,
}
local EMOTE_SHOCK = 0

local World = {}
World.__index = World

-- Movement direction → map.connections key.
local DIR_CONN = { up = "north", down = "south", left = "west", right = "east" }
local FACING_ID = { down = 0, up = 1, left = 2, right = 3 }
local NEIGHBOR_HOPS = 2

local VAR = {
  PARTYCOUNT = 0x01,
  BATTLERESULT = 0x02,
  BATTLETYPE = 0x03,
  TIMEOFDAY = 0x04,
  DEXCAUGHT = 0x05,
  DEXSEEN = 0x06,
  BADGES = 0x07,
  MOVEMENT = 0x08,
  FACING = 0x09,
  HOUR = 0x0a,
  WEEKDAY = 0x0b,
  MAPGROUP = 0x0c,
  MAPNUMBER = 0x0d,
  UNOWNCOUNT = 0x0e,
  ENVIRONMENT = 0x0f,
  BOXSPACE = 0x10,
  CONTESTMINUTES = 0x11,
  XCOORD = 0x12,
  YCOORD = 0x13,
  SPECIALPHONECALL = 0x14,
}

-- constants/ram_constants.asm:293 wPlayerState.  PLAYER_SKATE (2) has no row:
-- nothing writes it, and FieldMoves has no string for it either.
local PLAYER_STATE_BY_ID = {
  [0] = FieldMoves.PLAYER_NORMAL,
  [1] = FieldMoves.PLAYER_BIKE,
  [4] = FieldMoves.PLAYER_SURF,
  [8] = FieldMoves.PLAYER_SURF_PIKA,
}

-- engine/overworld/variables.asm:49 VAR_MOVEMENT reads wPlayerState back
local PLAYER_STATE_ID = {}
for id, state in pairs(PLAYER_STATE_BY_ID) do PLAYER_STATE_ID[state] = id end

local BATTLETYPE = {
  CANLOSE = 1,
  FORCESHINY = 7,
  FORCEITEM = 10,
}

-- constants/collision_constants.asm, for GetWarpSFX below.
local COLL = {
  DOOR = 0x71,
  WARP_PANEL = 0x7c,
}

local SPRITE = {
  VARS = 0xf0,
  DAY_CARE_MON_1 = 0xe0,
  DAY_CARE_MON_2 = 0xe1,
}

local ENGINE = {
  DAY_CARE_MAN_HAS_EGG = 5,
  DAY_CARE_MAN_HAS_MON = 6,
  DAY_CARE_LADY_HAS_MON = 7,
}

local MAPSETUP = {
  WARP = 0xf1,
  CONTINUE = 0xf2,
  RELOADMAP = 0xf3,
  TELEPORT = 0xf4,
  DOOR = 0xf5,
  FALL = 0xf6,
  CONNECTION = 0xf7,
  LINKRETURN = 0xf8,
  TRAIN = 0xf9,
  SUBMENU = 0xfa,
  BADWARP = 0xfb,
}

local MAPSETUP_FADE_OUT = {
  [MAPSETUP.DOOR] = true, [MAPSETUP.FALL] = true, [MAPSETUP.TELEPORT] = true,
}
local MAPSETUP_FADE_IN = {
  [MAPSETUP.DOOR] = true, [MAPSETUP.FALL] = true, [MAPSETUP.TELEPORT] = true,
  [MAPSETUP.WARP] = true, [MAPSETUP.BADWARP] = true, [MAPSETUP.TRAIN] = true,
  [MAPSETUP.LINKRETURN] = true, [MAPSETUP.CONTINUE] = true,
  [MAPSETUP.RELOADMAP] = true,
}
-- MapSetupScript_Connection and _Submenu are the two with no FadeInFromWhite;
-- naming them keeps the table above readable as the whole eleven-row set.
local MAPSETUP_NO_FADE = {
  [MAPSETUP.CONNECTION] = true, [MAPSETUP.SUBMENU] = true,
}

-- MapSetupCommands $26 UpdateRoamMons and $27 JumpRoamMons, read off the same
-- eleven scripts with the same fallthroughs honoured.  This is the ONLY thing
-- that moves the three legendary beasts around Johto, and where each sits in
-- its script decides which map "the player's map" means:
--
--   UpdateRoamMons is the tail of MapSetupScript_Train, and _Fall drops into
--   _Door drops into _Train -- so a door warp, a fall and a train ride all
--   nudge each beast one connection along.  _Connection names it too.  It runs
--   AFTER the load, so the map it avoids putting them on is the NEW one.
--
--   JumpRoamMons is the third row of MapSetupScript_Teleport, BEFORE that
--   script falls into _Warp -- so it runs before the load, and it scatters
--   every beast to a random roam map.  Flying across Johto shuffles them;
--   walking through a door does not.
--
-- A plain MAPSETUP.WARP names neither, which is why warping between two floors
-- of a building leaves them where they were.
local MAPSETUP_ROAM_UPDATE = {
  [MAPSETUP.CONNECTION] = true, [MAPSETUP.DOOR] = true,
  [MAPSETUP.FALL] = true, [MAPSETUP.TRAIN] = true,
}
local MAPSETUP_ROAM_JUMP = { [MAPSETUP.TELEPORT] = true }

-- FadeOutToWhite / FadeInFromWhite (engine/tilesets/timeofday_pals.asm) are
-- `ld b, $4` steps of ConvertTimePalsIncHL / .DecHL, each followed by
-- `DelayFrames 2`: four steps, eight frames, per half.  The port draws the
-- overworld with its colours already baked in and has no four-entry palette
-- left to rotate, so the four steps become four levels of the flat sheet
-- World:draw already holds for the fade specials.
local FADE_STEPS = 4
local FADE_STEP_FRAMES = 2

-- A New Game starts in the bedroom, not outside: engine/menus/intro_menu.asm
-- NewGame sets wDefaultSpawnpoint = SPAWN_HOME and warps there, and
-- data/maps/spawn_points.asm puts SPAWN_HOME at PLAYERS_HOUSE_2F (3,3).
-- landmarks.lua carries the real table; these are the fallback for a cache
-- imported before the spawn table existed.
local SPAWN_HOME = "SPAWN_HOME"
local START_MAP = "PLAYERS_HOUSE_2F"
local START_X, START_Y, START_FACING = 3, 3, "down"
local PLAYER_SPRITE = "SPRITE_CHRIS"

-- constants/event_flags.asm.  HatchEggs sets this one by hand, for exactly one
-- species, right after SetSeenAndCaughtMon.  wEventFlags is keyed by NUMBER
-- here (that is what the extractor emits), so the constant lives at the call
-- site rather than as a string the Events store would refuse to compare.
local EVENT_TOGEPI_HATCHED = 84

-- The last flag InitializeEventsScript sets (engine/events/std_scripts.asm),
-- and the one PlayersHouse2FInitializeRoomCallback checks before jumping to
-- it: once it is set the seed never runs again for that save file.  Numbered
-- for the same reason as the one above.
local EVENT_INITIALIZED_EVENTS = 54

-- SPRITEMOVEDATA_STRENGTH_BOULDER, $19 in constants/map_object_constants.asm.
-- The push looks for this on the object, not for SPRITE_BOULDER: the sprite is
-- shared with the immovable scenery rocks and the movement data is what tells
-- the two apart (data/sprites/map_objects.asm gives only this row the
-- STRENGTH_BOULDER palette flag .CheckStrengthBoulder tests).
local SPRITEMOVEDATA_STRENGTH_BOULDER = 0x19

-- Script_UsedStrength's `pause 3` between the cry and MoveBoulderText, and
-- Script_UsedWaterfall's per-cell climb; both are frames at 60 Hz.
local STRENGTH_PAUSE_FRAMES = 3

-- The four field-move / field-item strings this file prints, in the port's own
-- TextBox markers (\n = second line, \f = page break, {STRBUF} = the shared
-- wStringBuffer2 token, which TextBox fills from game.stringBuffer).
--
-- They are transcribed rather than looked up because nothing in the ROM's
-- script bytecode points at them: engine/events/overworld.asm names each label
-- directly, so the extractor -- which only walks reachable script pointers --
-- never sees them and data/generated/text.lua has no key for them.  Bodies
-- from data/text/common_2.asm; `#` is the four-tile POKé compression byte, so
-- "POKéMON" here is the same seven tiles the cart draws.
--
-- Strings.source marks them for the catalog generator without translating
-- them here: the table is built at require time and Strings.load has no
-- catalog yet, so the lookup happens at the showText call sites below --
-- the same arrangement src/world/gen2/FieldMoves.lua uses for the other
-- twenty-odd lines engine/events/overworld.asm names directly.
local TEXT_ASK_HEADBUTT = Strings.source(
  "A POKéMON could be\nin this tree.\fWant to HEADBUTT\nit?")
local TEXT_USE_HEADBUTT = Strings.source("{STRBUF} did a\nHEADBUTT!")
local TEXT_HEADBUTT_NOTHING = Strings.source("Nope. Nothing…")
local TEXT_ROD_BITE = Strings.source("Oh!\nA bite!")
local TEXT_ROD_NOTHING = Strings.source("Not even a nibble!")
-- _UseSweetScentText / _SweetScentNothingText (data/text/common_2.asm).
-- GetPartyNickname leaves the same name in wStringBuffer1-3, so {STRBUF}
-- (wStringBuffer2) reads back the text_ram wStringBuffer3 line just as well.
local TEXT_USE_SWEET_SCENT = Strings.source("{STRBUF} used\nSWEET SCENT!")
local TEXT_SWEET_SCENT_NOTHING =
  Strings.source("Looks like there's\nnothing here…")
-- _UseSacredAshText (data/text/common_2.asm), hung off SacredAshScript's own
-- `text_far` and never reached through a script pointer the extractor walks,
-- same reason the itemfinder pair above needs Strings.source instead of a
-- text.lua key.
local TEXT_USE_SACRED_ASH = Strings.source(
  "{PLAYER}'s POKéMON\nwere all healed!")

-- CheckHeadbuttTreeTile (home/map_objects.asm) compares the facing tile's
-- collision against COLL_HEADBUTT_TREE and its unused $1d alias
-- (constants/collision_constants.asm).  Both sit at permission $0f, so a tree
-- blocks a step like any other wall and only the A press tells them apart --
-- which is why this is a collision test and not a tile-graphic one.  Same
-- shape as Permissions.isGrass, and it belongs beside it.
local HEADBUTT_TREE = { [0x15] = true, [0x1d] = true }

-- TryHeadbuttOW's `ld d, HEADBUTT / call CheckPartyMove`; moves.lua keys the
-- move by its own constant name.
local MOVE_HEADBUTT = "HEADBUTT"

-- The three fishing rods, keyed the way items.lua keys them so a call site
-- names an item rather than a byte.  Indices from constants/item_constants.asm
-- (OLD_ROD $3a, GOOD_ROD $3b, SUPER_ROD $3d); data/items/attributes.asm gives
-- all three KEY_ITEM, ITEMMENU_CLOSE in the field and ITEMMENU_NOUSE in
-- battle, i.e. a rod is a field-only item and the battle PACK must refuse it.
local ROD_INDEX = { OLD_ROD = 0x3a, GOOD_ROD = 0x3b, SUPER_ROD = 0x3d }

-- RepelEffect / SuperRepelEffect / MaxRepelEffect (engine/items/item_effects.asm):
-- each is a bare `ld b, <steps>` into the shared UseRepel, so the step count is
-- the only thing that differs between the three items. wRepelEffect is
-- save.repelSteps, ticked down by StepEvents.repelStep on every footfall.
local REPEL_STEPS = { REPEL = 100, SUPER_REPEL = 200, MAX_REPEL = 250 }

-- NormalBoxEffect / GorgeousBoxEffect: the item -> DECOFLAG_* it opens on.
-- The pairing is crossed on purpose -- the NORMAL BOX holds the SILVER trophy
-- and the GORGEOUS BOX the GOLD one, exactly as the asm reads.
local TROPHY_BOXES = {
  NORMAL_BOX = Decorations.DECOFLAG_SILVER_TROPHY_DOLL,
  GORGEOUS_BOX = Decorations.DECOFLAG_GOLD_TROPHY_DOLL,
}

-- Script_FishCastRod ends on `pause 40`, and Script_GotABite pauses another 40
-- over the bobbing rod before the text lands.
-- All are frames at 60 Hz, which is the same clock World:step runs on.
local FISH_CAST_FRAMES = 40
local FISH_BITE_FRAMES = 40
local HEADBUTT_SHAKE_FRAMES = 32

-- The vanilla links the two encounter chains wrap (World:rollEncounter, below),
-- hoisted here so an empty chain allocates no closure and so every caller --
-- the step roll, `randomwildmon`, the Bug Contest and SWEET SCENT -- can see
-- them.  Each takes the piped value (the wild tables the roll is made against)
-- and the ctx, and answers { species, level } or nil.
local function rollGrassVanilla(tables, ctx)
  return Encounter.grassSlot(tables, ctx.mapId, ctx.daytime, nil)
end

local function rollWaterVanilla(tables, ctx)
  return Encounter.waterSlot(tables, ctx.mapId, nil)
end

local function rollContestVanilla(_, ctx)
  return BugContest.chooseWild(ctx.data)
end

local function sameEncounter(enc) return enc end

-- The encounter.fishing chain's vanilla link.  Encounter.fishSlot's own rod
-- mapping, and then Encounter.fish over whatever candidate row the chain handed
-- down -- routed back through Encounter.fish rather than re-rolled here, so a
-- mod that only inspected the list gets the cart's cumulative-chance walk
-- (engine/events/fish.asm Fish) byte for byte.
local FISH_ROD_KEY = { OLD_ROD = "old", GOOD_ROD = "good", SUPER_ROD = "super" }

local function fishVanilla(rod, _mapId, candidates, ctx)
  if not candidates then return nil end
  local tod = ctx and (ctx.tod or ctx.daytime)
  return Encounter.fish({ fishGroups = { hooked = candidates },
                          timeFishGroups = ctx and ctx.encounters and ctx.encounters.timeFishGroups },
    "hooked", FISH_ROD_KEY[rod] or rod or "old", tod, nil)
end

local function speciesByIndex(pokemon, index)
  if not pokemon or not index then return nil end
  for id, def in pairs(pokemon) do
    if type(def) == "table" and def.index == index then return id, def end
  end
  return nil
end

local function itemByIndex(items, index)
  if not items or not index or index == 0 then return nil end
  for id, def in pairs(items) do
    if type(def) == "table" and def.index == index then return id, def end
  end
  return nil
end

-- CountSetBits over a { key = true } flag table: VAR.DEXCAUGHT, VAR.DEXSEEN
-- and VAR.BADGES are all "how many of these are set" reads off one.
local function countFlags(flags)
  if not flags then return 0 end
  local n = 0
  for _, has in pairs(flags) do
    if has then n = n + 1 end
  end
  return n
end

-- `givepoke` builds the same record a caught wild mon does, through
-- src/battle/gen2/Mon.lua.  It used to go through Gen 1's Pokemon.new with a
-- hand-adapted base-stat block, and that adapter handed it `level1Moves = {}`
-- and `learnset = {}` -- fields the Gen 2 extractor does not write, because a
-- Gen 2 moveset lives in `levelMoves` (EvosAttacks).  So every scripted gift,
-- the STARTER included, arrived knowing nothing: FIGHT listed no moves and the
-- battle had no legal action left in it.
local function givePokeMon(data, speciesIndex, level, itemIndex, opts)
  local id = speciesByIndex(data.pokemon, speciesIndex)
  if not id then return nil end
  return Mon.new(data, id, level or 5, {
    item = itemIndex and itemIndex ~= 0
      and itemByIndex(data.items, itemIndex) or nil,
    nickname = opts and opts.nickname or nil,
  })
end

-- GivePoke's trainer arm (engine/pokemon/move_mon.asm:1698-1736)
local RANDY_OT_ID = 1001

local function loadGenerated(path)
  -- Same NX gold/ fallback Game2 uses. World:load is what surfaces
  -- "Gold cache incomplete" when maps.lua is invisible at the unprefixed path.
  local CacheFs = require("src.import.CacheFs")
  return CacheFs.loadActive(path)
end

-- Paste the 9-tile roof sheet over atlas tiles $0a-$12.
local function applyRoofOverlay(atlasPath, roofPath, tilesPerRow)
  -- Assets.resolve, not the raw path: an overrides/ file or an AssetTransform
  -- output has to feed the derivation rather than be bypassed by it.
  local atlasData = love.image.newImageData(Assets.resolve(atlasPath))
  local roofData = love.image.newImageData(Assets.resolve(roofPath))
  for t = 0, 8 do
    local destId = 0x0a + t
    local dx = (destId % tilesPerRow) * 8
    local dy = math.floor(destId / tilesPerRow) * 8
    local sx = t * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local r, g, b, a = roofData:getPixel(sx + x, y)
        atlasData:setPixel(dx + x, dy + y, r, g, b, a)
      end
    end
  end
  local image = love.graphics.newImage(atlasData)
  image:setFilter("nearest", "nearest")
  return image
end

-- Gen 2 connections use mapId (name); offsets are in blocks (32 px),
-- same strip math as Gen 1 OverworldState.computeNeighbors.
function World.computeNeighbors(maps, rootId, hops, reachW, reachH)
  local out = {}
  local rootDef = maps[rootId]
  if not rootDef then return out end
  local placed = { [rootId] = true }
  local queue = { { def = rootDef, ox = 0, oy = 0, hops = 0 } }
  local qi = 1
  local function inReach(def, ox, oy)
    if not (reachW and reachH and rootDef) then return false end
    return ox + def.width * 32 > -reachW
       and ox < rootDef.width * 32 + reachW
       and oy + def.height * 32 > -reachH
       and oy < rootDef.height * 32 + reachH
  end
  while queue[qi] do
    local cur = queue[qi]
    qi = qi + 1
    for dir, side in pairs(cur.def.connections or {}) do
      -- A side may hold a single connection object or an array (editor-only
      -- extra connections); iterate either form.
      local conns
      if type(side) == "table" and (side.map or side.mapId) then
        conns = { side }
      else
        conns = side
      end
      if type(conns) == "table" then
        for _, conn in ipairs(conns) do
          local destId = conn.mapId or conn.map
          local destDef = type(destId) == "string" and maps[destId] or nil
      if destDef and not placed[destId] then
        placed[destId] = true
        local offset = conn.offset or 0
        if offset == 0 then offset = 0 end -- squash signed-zero
        local ox, oy
        if dir == "north" then
          ox, oy = offset * 32, -destDef.height * 32
        elseif dir == "south" then
          ox, oy = offset * 32, cur.def.height * 32
        elseif dir == "west" then
          ox, oy = -destDef.width * 32, offset * 32
        else
          ox, oy = cur.def.width * 32, offset * 32
        end
        ox, oy = cur.ox + ox, cur.oy + oy
        if cur.hops + 1 <= hops or inReach(destDef, ox, oy) then
          table.insert(out, { id = destId, ox = ox, oy = oy })
          if cur.hops + 1 < hops or inReach(destDef, ox, oy) then
            table.insert(queue, {
              def = destDef, ox = ox, oy = oy, hops = cur.hops + 1,
            })
          end
        end
      end
      end
    end
    end
  end
  return out
end

function World.new(game)
  local self = setmetatable({
    game = game,
    status = nil,
    maps = nil,
    tilesets = nil,
    roofs = nil,
    sprites = nil,
    scripts = nil,
    text = nil,
    constants = nil,
    events = Events.new(),
    mapScenes = {}, -- [mapId] = sceneId
    -- wCmdQueue: four slots, refilled from the map's MAPCALLBACK_CMDQUEUE on
    -- every load and polled once a frame (engine/overworld/cmd_queue.asm).
    cmdQueue = CmdQueue.new(),
    vm = nil,
    map = nil,
    player = nil,
    mapImage = nil,
    mapImages = {},
    -- _AnimateTileset's two counters (engine/tilesets/tileset_anims.asm:11,
    -- :57), plus the per-bake cell lists and palettes the frames draw with.
    animClock = 0,
    animTimer = 0,
    animCells = {},
    bgSets = {},
    neighbors = {},
    atlasCache = {},
    npcPool = {},
    npcs = {},
    ghosts = {},
    entities = {},
    talkNpc = nil,
    camera = Camera.new(),
    heldDir = nil,
    -- wPlayerTurningDirection's useful half: the direction a STEP latched via
    -- .FinishFacing.  CheckStandingOnIce + .CheckForced re-inject it as the
    -- d-pad while the tile underfoot is COLL_ICE, which is the whole ice-slide
    -- rule (engine/overworld/player_movement.asm).  Nil means "standing".
    turningDirection = nil,
    viewW = 160,
    viewH = 144,
    moveState = nil,
    lastSfx = nil,
    pokePic = nil,
    pendingSceneScript = false,
    -- GBC color state (engine/gfx/color.asm).  `daytime` is the resolved
    -- MORN/DAY/NITE/DARK the map is currently lit by; clockHour overrides
    -- World:hour for drivers and tests, so the palette, the hour windows and
    -- VAR.HOUR all move together; flashUsed lifts PALETTE_DARK maps.
    palettes = nil,
    daytime = nil,
    clockHour = nil,
    -- wCurDay, SUNDAY 0 .. SATURDAY 6, when something wants to pin it; nil
    -- reads the host clock.  See World:weekday.
    clockDay = nil,
    flashUsed = false,
    paletteClock = 0,
    -- FlickeringCaveEntrancePalette's frame counter: only a DARKNESS_PALSET
    -- map reads it, and only to decide which of two baked canvases is up.
    flickerClock = 0,
    flickerPhase = 1,
    -- wPlayerState (constants/ram_constants.asm), as FieldMoves names it.
    playerState = FieldMoves.PLAYER_NORMAL,
    -- BIKEFLAGS_STRENGTH_ACTIVE_F.  ResetBikeFlags clears the whole byte on
    -- every map load, which is why STRENGTH has to be used again in the next
    -- room.
    strengthActive = false,
    -- STATUSFLAGS_NO_WILD_ENCOUNTERS_F, driven by the `wildoff` / `wildon`
    -- script commands.
    noWildEncounters = false,
    -- Blocks CUT and WHIRLPOOL have swapped out on the loaded map, as
    -- { mapId = { [index] = original } }.  The cart edits wOverworldMapBlocks,
    -- a BUFFER, and LoadMapAttributes refills it from ROM on every map load --
    -- which is why a cut tree is back the next time you walk in.  Restoring
    -- these at the top of setMap is that refill.
    blockEdits = {},
    -- engine/overworld/map_setup.asm:78
    objectSpawns = {},
    -- A field move that is mid-flow (the used-X text, then its effect).
    fieldMove = nil,
    -- ---- state the script VM owns ------------------------------------------
    -- wVariableSprites (ram/wram.asm), indexed from SPRITE.VARS: slot -> plain
    -- OverworldSprites byte.  Cleared on a map load the way the cart's copy is
    -- not -- it is real WRAM that survives -- so this one survives too, and
    -- every map that needs a slot filled sets it from its own scene script.
    variableSprites = {},
    -- The VAR_* slots `writevar` / `loadvar` write.  Only VAR.BATTLETYPE is
    -- read back today, by the next startbattle.
    scriptVars = {},
    -- WarpCheck's find.  A script that ends standing on a warp tile must not
    -- warp INSIDE the command: the commands queued behind it would run with the
    -- map pulled out from under them, so the destination waits here until
    -- World:step sees the VM go idle.
    pendingWarp = nil,
    -- ShakeScreen's live wPlayerStepVectorY offset (`earthquake`).
    shake = nil,
    -- wDontPlayMapMusicOnReload: one shot, consumed by the next map reload.
    dontRestartMusic = false,
    -- FadeOutToWhite / FadeOutToBlack's sheet, until a FadeInFrom* lifts it.
    fade = nil,
    -- A `musicfadeout` whose ramp still has frames left, plus the label queued
    -- underneath it.
    pendingMusic = nil,
    showDebugHud = os.getenv("POKEPORT_DEV") == "1",
  }, World)
  -- ow.runner under the Gen 1 name (src/world/OverworldController.lua:216).
  -- A mod guards with `ow.runner and ow.runner:isRunning()` before acting;
  -- nil there is FALSEY, so the mod concludes no script is running while one
  -- is and acts mid-cutscene.  Gold's frame is self.vm, so this is the query
  -- half of it and nothing else.
  self.runner = setmetatable(
    { isRunning = function() return self:scriptRunning() end },
    { __index = function(_, key)
        if key == "vm" then return self.vm end
        if key == "co" then return self.vm and self.vm.co end
        if key == "ctx" then return self.vm and self.vm.ctx end
        return nil
      end })
  return self
end

-- LoadPlayerData (engine/menus/save.asm) copies sPlayerData straight back over
-- wPlayerData, and ALL THREE of the things this restores live inside that
-- region (ram/wram.asm): wEventFlags, the block of w<Map>SceneID bytes above
-- it, and wPlayerState below them.
-- That is why a cartridge reload comes back with every flag the player set and
-- with each map still on the scene it had been advanced to.  MeetMomScript
-- (maps/PlayersHouse1F.asm) needs both halves at once: it ends on `setscene
-- SCENE_PLAYERSHOUSE1F_NOOP` plus a setevent/clearevent pair, so talk to MOM,
-- save, reload, and she must NOT play her first-time scene again.
--
-- `save.events` is the serialized bitfield src/world/gen2/Events.lua writes
-- (byte index -> byte value, keyed by NUMBER) and `save.mapScenes` is map id ->
-- scene id; src/core/gen2/Save.lua has already scrubbed both by the time this
-- runs.  The restore REPLACES the seed rather than merging with it: a script
-- that CLEARED one of InitializeEventsScript's flags (MeetMomScript clears
-- EVENT_PLAYERS_HOUSE_MOM_2 on its way out) has to stay cleared across a
-- reload, and an OR would set it again on every boot.
--
-- Called from World:load BEFORE the first setMap, because the object list is
-- only re-read when a map loads (RefreshMapSprites): a flag restored after the
-- load would leave the wrong people standing on the first map until the player
-- walked into the next one.
function World:loadPlayerData(save)
  self.events = Events.new()
  self.mapScenes = {}
  if type(save) == "table" then
    if type(save.events) == "table" then
      self.events:restore(save.events)
    end
    if type(save.mapScenes) == "table" then
      for mapId, scene in pairs(save.mapScenes) do
        self.mapScenes[mapId] = tonumber(scene) or 0
      end
    end
  end
  -- PlayersHouse2FInitializeRoomCallback (maps/PlayersHouse2F.asm) jumps to
  -- InitializeEventsScript only while EVENT_INITIALIZED_EVENTS is still clear,
  -- and the script sets that flag last.  So a save that has never had the seed
  -- gets it here -- a brand new game, or one whose world never ran -- and a
  -- save that has keeps exactly the bitfield it was written with.
  if not self.events:get(EVENT_INITIALIZED_EVENTS) then
    for _, id in ipairs(self.initialEvents or {}) do
      self.events:set(id, true)
    end
    for _, id in ipairs(self.initialEngineFlags or {}) do
      self:setEngineFlag(id, true)
    end
  end
  -- Variable sprites: seed any slot the save does not already carry.
  --
  -- Seeding only on a fresh game would be the cart's own behaviour, and the
  -- cart gets away with it because wVariableSprites is WRAM that is never
  -- reloaded mid-session.  This port rebuilds the World on every CONTINUE, so
  -- "only on a fresh game" would mean an empty slot -- and an empty slot is an
  -- object that does not spawn.  Filling only what is missing keeps a later
  -- `variablesprite` (Route 36 swaps the tree for a TWIN once Sudowoodo is
  -- beaten, reusing the same slot) intact across a save and reload.
  local saved = (self.game and self.game.save and self.game.save.variableSprites)
  if type(saved) == "table" then
    for slot, sprite in pairs(saved) do
      if type(slot) == "number" then self.variableSprites[slot] = sprite end
    end
  end
  for _, row in ipairs(self.initialSprites or {}) do
    if row.slot and row.sprite and not self.variableSprites[row.slot] then
      self.variableSprites[row.slot] = row.sprite
    end
  end
  -- wPlayerState, the third member of the block.  Everything the state decides
  -- follows from this one field: UpdatePlayerSprite picks the sheet off it,
  -- .DoStep picks STEP_BIKE or STEP_WALK off it, and .TranslateIntoMovement
  -- picks .CheckLandPerms or .CheckSurfPerms off it -- so a save made on the
  -- BICYCLE that came back on foot was not just wearing the wrong sprite, it
  -- was walking at the wrong speed over a different set of tiles.
  --
  -- Only a name Save.PLAYER_STATES vouches for is taken; anything else is
  -- PLAYER_NORMAL, which is where Save.validate has already put it and is the
  -- cart's own zero byte.  applyPlayerState rather than a bare assignment so a
  -- world that already has a player repaints them on the spot; on the boot
  -- path there is no player yet and the first setMap's CheckUpdatePlayerSprite
  -- is what puts the sprite on.
  local state = type(save) == "table" and save.playerState or nil
  self:applyPlayerState(Gen2Save.PLAYER_STATES[state] and state or nil)
  -- wBackupWarpNumber / wBackupMapGroup / wBackupMapNumber, the triple a -1
  -- warp destination resolves through (home/map.asm CopyWarpData).  On the
  -- cart it sits in the same saved WRAM block as wPlayerState, so a save made
  -- on POKECENTER_2F still knows which centre's stairs lead back down after a
  -- reload; this port rebuilds the World on every CONTINUE, so the triple has
  -- to ride the save the same way wPlayerState does.
  local backup = type(save) == "table" and save.backupWarp or nil
  if type(backup) == "table" and backup.map and backup.warp then
    self.backupWarp = { warp = backup.warp, map = backup.map }
  end
  return self.events
end

-- The Gen 2 content tables come off game.data rather than off disk.
-- src/core/Game2.lua:load reads every one of them into self.data BEFORE it
-- calls mods:load(self.data), so what this hands back is the merged table: a
-- registry that targets data.gen2Maps has somewhere to write, and the world
-- walks what it wrote.  Held by reference on purpose: a copy here would
-- silently un-merge every one of them.
--
-- The on-disk fallback covers a World built without a Game2 behind it:
-- the stub-game worlds in tests/gen2_*_test.lua set the fields they need
-- straight onto the world and never call :load, but a driver or tool that does
-- call it with a bare game table still has to boot.  Nothing merges mods on
-- that path, so reading the cache directly reaches the same table by another
-- route; the read is cached back into game.data so a later reader (MartMenu's
-- data.gen2Marts, Pokegear's data.gen2Landmarks) sees the same one table.
function World:dataTable(key, path)
  local data = self.game and self.game.data
  local held = data and data[key]
  if held ~= nil then return held end
  local value, err = loadGenerated(path)
  if value ~= nil and data then data[key] = value end
  return value, err
end

function World:load()
  local maps, mapsErr = self:dataTable("gen2Maps", "data/generated/maps.lua")
  local tilesets, tilesErr =
    self:dataTable("gen2Tilesets", "data/generated/tilesets.lua")
  if not maps or not tilesets then
    self.status = Strings("Gold cache incomplete:\n%s",
      tostring(mapsErr or tilesErr))
    return false
  end
  self.maps = maps
  self.tilesets = tilesets
  self.roofs = self:dataTable("gen2Roofs", "data/generated/roofs.lua")
  self.sprites = self:dataTable("gen2Sprites", "data/generated/sprites.lua")
  -- A cache from before the palette stage existed simply has no palettes.lua;
  -- everything below falls back to the grayscale path rather than failing.
  self.palettes = self:dataTable("gen2Palettes", "data/generated/palettes.lua")
  -- Town-map landmarks for the Pokegear, and the SPAWN_* table that decides
  -- where a New Game and every Pokecenter respawn start.
  self.landmarks =
    self:dataTable("gen2Landmarks", "data/generated/landmarks.lua")
  self.encounters =
    self:dataTable("gen2Encounters", "data/generated/encounters.lua")
  self.stdScripts =
    self:dataTable("gen2StdScripts", "data/generated/std_scripts.lua")
  self.trainers = self:dataTable("gen2Trainers", "data/generated/trainers.lua")
  -- data.trainers is the second name the Gen 2 code reads this same table by
  -- (World:trainerParty, BugContest, Palettes.trainerPalette).  The two keys
  -- are aliased in Game2 before the merge; this line only has to catch the
  -- fallback path above, and assigns the same reference either way.
  if self.game and self.game.data and self.trainers then
    self.game.data.trainers = self.trainers
  end
  -- Mart shelves (data/items/marts.asm).  A cache from before the mart stage
  -- has no marts.lua at all; MartMenu treats that as an empty shelf rather
  -- than inventing stock, so a clerk still opens and still says his lines.
  self.marts = self:dataTable("gen2Marts", "data/generated/marts.lua")
  -- showemote's bubbles.  Loaded here rather than at draw time so a missing
  -- sheet (a cache from before the emote stage) just means no bubble.
  local menuGfx = self:dataTable("gen2MenuGfx", "data/generated/menu_gfx.lua")
  local emotes = menuGfx and menuGfx.emotes
  if emotes then
    self.emoteOrder = emotes.order
    self.emoteImages = {}
    for _, key in ipairs(emotes.order or {}) do
      local path = emotes[key]
      if path then
        local okImg, img = pcall(Assets.image, path)
        if okImg then self.emoteImages[key] = img end
      end
    end
    -- ShakeGrass' one tile (data/sprites/emotes.asm:22).  A cache from before
    -- it was extracted simply has no rustle.
    if emotes.grassRustle then
      local okImg, img = pcall(Assets.image, emotes.grassRustle)
      if okImg then self.grassRustleImage = img end
    end
  end
  -- The heal machine's two OBJ tiles and their CGB palette, for the
  -- Pokecenter light show (World:startHealMachineAnim).  A cache from before
  -- the sheet existed just has no entry, and the anim degrades to its sounds.
  local healMachine = menuGfx and menuGfx.healMachine
  if healMachine and healMachine.sheet then
    local okImg, img = pcall(Assets.image, healMachine.sheet)
    if okImg then
      self.healMachineImage = img
      self.healMachinePalette = healMachine.palette
    end
  end
  -- POKEPORT_GOLD_HOUR pins the clock so a driver's screenshots are stable and
  -- a reviewer can look at any time of day on demand.
  local forcedHour = tonumber(os.getenv("POKEPORT_GOLD_HOUR") or "")
  if forcedHour then self.clockHour = forcedHour end
  -- POKEPORT_GOLD_DAY pins wCurDay (SUNDAY 0 .. SATURDAY 6) for the same
  -- reason: the day-of-week map callbacks put a different NPC on seven routes,
  -- and a driver that only ever sees today's cannot check the other six.
  local forcedDay = tonumber(os.getenv("POKEPORT_GOLD_DAY") or "")
  if forcedDay then self.clockDay = forcedDay end
  self.scripts = self:dataTable("gen2Scripts", "data/generated/scripts.lua")
    or {}
  self.text = self:dataTable("gen2Text", "data/generated/text.lua") or {}
  self.constants =
    self:dataTable("gen2Constants", "data/generated/constants.lua") or {}
  -- The side tables a script command NAMES rather than carries: the phone
  -- book, the in-game trades, the elevator's floor labels and the decoration
  -- descriptions.  A cache built before the extractor reached them has no
  -- events.lua at all, so every reader treats it as optional.
  self.eventTables =
    self:dataTable("gen2EventTables", "data/generated/events.lua") or {}
  -- Take the phone book off the cache when it has one; src/core/gen2/Phone.lua
  -- keeps its transcribed tables as the fallback for an older cache.
  require("src.core.gen2.Phone").useExtracted(self.eventTables)
  -- data.pokemon and data.items keep the SHARED Gen 1 keys: both registries
  -- route to their Gen 1 target under Gen 2, so Game2 already has them
  -- loaded and merged.  Going through dataTable is what makes that hold
  -- -- the old unconditional re-read overwrote both with a fresh copy off the
  -- cache and threw away every `pokemon` and `items` merge a mod had made.
  self:dataTable("pokemon", "data/generated/pokemon.lua")
  self:dataTable("items", "data/generated/items.lua")
  if self.game and self.game.save then
    local save = self.game.save
    save.party = save.party or {}
    save.inventory = save.inventory or {}
    save.phoneContacts = save.phoneContacts or {}
  end
  -- Retail Gold hides story NPCs (lab cop, rivals, etc.) via
  -- InitializeEventsScript's setevent list -- apply before spawning people.
  local initial =
    self:dataTable("gen2InitialEvents", "data/generated/initial_events.lua")
  self.initialEvents = (initial and initial.flags) or {}
  self.initialEngineFlags = (initial and initial.engineFlags) or {}
  -- InitializeEventsScript does not only `setevent`.  It ends with nine
  -- `variablesprite` assignments, and SPRITE_WEIRD_TREE ($f4) and friends are
  -- wVariableSprites SLOTS rather than sheets -- so until the slot is filled,
  -- World:resolveSprite answers nil and World:pooledNpc spawns NOTHING.  The
  -- seed used to carry the setevent list alone, which meant the Sudowoodo on
  -- Route 36 was simply absent from a new game, and with it TM08 ROCK SMASH,
  -- the Burned Tower, Morty, FOGBADGE and SURF; likewise the Olivine rival,
  -- the Azalea Rocket, the four Fuchsia Gym Janines, the Copycat and the
  -- Janine impersonator.
  --
  -- The extractor now writes them (`sprites`).  The fallback finds the same
  -- script in scripts.lua for a cache written before it did -- the script is
  -- the one whose setevent ids ARE this flag list -- so an existing cache does
  -- not have to be rebuilt for the tree to come back.
  self.initialSprites = (initial and initial.sprites)
    or self:findInitialSprites()
  -- wEventFlags and the per-map scene ids off the save, with the seed above as
  -- the fallback for a file that has never had it.  Both are back before the
  -- VM is built and long before the first setMap below.
  self:loadPlayerData(self.game and self.game.save)
  -- Font.load expects the Gen 1 Data shape: data.font = font.lua table.  The
  -- `font` registry keeps its Gen 1 target under Gen 2, so data.font is
  -- already the merged table by the time we get here -- a second disk read
  -- would put the stock glyphs back over a font mod's.
  local font = self:dataTable("font", "data/generated/font.lua")
  if font then
    local okFont, fontErr = pcall(Font.load, { font = font })
    if not okFont then
      self.status = Strings("Font load failed:\n%s", tostring(fontErr))
      return false
    end
  end

  self.vm = Vm.new(self.scripts, self.text, self.events, {
    eventTables = self.eventTables,
    -- The `commands` registry as merged into data.commands, which is the
    -- shared Gen 1 target (it is absent from Schemas.GEN2 on purpose).  The
    -- VM resolves a mod-authored `modcommand` row's verb out of this table
    -- (src/script/gen2/Vm.lua:runModCommand); a cart row never reaches it.
    -- Read straight off game.data rather than through dataTable: there is no
    -- data/generated/commands.lua to fall back to, and nil here is the honest
    -- answer for a mod-free boot -- the only check the dispatch arm pays.
    commands = self.game and self.game.data and self.game.data.commands,
    -- Vm:resume hands the one-command lookahead through as the third argument
    -- (Vm:textStays): the next row is `yesorno`, so this text ended in `done`
    -- and the cart never took the box down before YesNoBox went up over it
    -- (home/text.asm:484 DoneText returns with no PromptButton, unlike
    -- PromptText).  Dropping the argument here left World:showText's `stay`
    -- branch and World:askYesNo's held arm unreachable, which cost a button
    -- press the cart never asks for and re-printed the question under the
    -- prompt.
    -- `hold` is the same story one argument along: the cart `pause` a held box
    -- stands through (FindItemInBallScript's `pause 60`).  Dropping it made the
    -- box hand back the instant it finished typing.
    showText = function(body, onDone, stay, hold)
      self:showText(body, onDone, stay, hold)
    end,
    facePlayer = function()
      if self.talkNpc and self.player then
        self.talkNpc:facePlayer(self.player)
      end
    end,
    onFlagsChanged = function()
      -- A flag set MID-SCRIPT must not change which objects are on the map.
      -- The cart only re-reads the object list when the map loads
      -- (RefreshMapSprites, after a warp or a scene change), so a script that
      -- sets an object's event flag halfway through -- MeetMomScript sets
      -- EVENT_PLAYERS_HOUSE_MOM_1 and clears MOM_2 while Mom is still
      -- standing next to the player -- would otherwise swap the standing Mom
      -- for the sitting one on the spot, which reads as her teleporting into
      -- her chair mid-sentence.  Deferred to the end of the script instead.
      if self:scriptRunning() then
        self.peopleDirty = true
        return
      end
      self:rebuildPeople({ seamless = true })
    end,
    setScene = function(scene)
      if self.map then self.mapScenes[self.map.id] = scene or 0 end
    end,
    getScene = function()
      return self.map and (self.mapScenes[self.map.id] or 0) or 0
    end,
    setMapScene = function(group, mapNum, scene)
      local mapId = self:mapIdByGroupMap(group, mapNum)
      if mapId then self.mapScenes[mapId] = scene or 0 end
    end,
    turnObject = function(objectId, facing)
      self:turnObject(objectId, facing)
    end,
    applyMovement = function(objectId, bytes, onDone)
      self:beginMovement(objectId, bytes, onDone)
    end,
    follow = function(leader, follower)
      self:startFollow(leader, follower)
    end,
    stopFollow = function() self:stopFollow() end,
    -- StartAutoInput / StopAutoInput (home/joypad.asm).  The ring itself lives
    -- on the game so it outlives a map load, and it is stepped once per fixed
    -- step ahead of Input:step; see src/core/gen2/AutoInput.lua.
    autoInput = function(bank, address)
      local ring = self.game and self.game.autoInput
      if ring then ring:startPointer(bank, address, self.game.input) end
    end,
    autoInputStream = function(name)
      local ring = self.game and self.game.autoInput
      if ring then ring:start(name, self.game.input) end
    end,
    stopAutoInput = function()
      local ring = self.game and self.game.autoInput
      if ring then ring:stop(self.game.input) end
    end,
    yesorno = function(onChoose)
      self:askYesNo(onChoose)
    end,
    disappear = function(objectId)
      self:disappearObject(objectId)
    end,
    showPic = function(speciesIndex)
      self:showPokePic(speciesIndex)
    end,
    hidePic = function()
      self.pokePic = nil
    end,
    -- WaitButton (home/text.asm), for the `waitbutton` that sits under an open
    -- `pokepic` window and so has no text box to have taken the press for it.
    -- See World:waitForButton.
    waitButton = function(done)
      self:waitForButton(done)
    end,
    getMonName = function(speciesIndex)
      local id, def = speciesByIndex(
        self.game and self.game.data and self.game.data.pokemon,
        speciesIndex)
      return (def and def.name) or id or "?"
    end,
    getItemName = function(itemIndex)
      local id, def = itemByIndex(
        self.game and self.game.data and self.game.data.items, itemIndex)
      if def and def.name then return def.name end
      return id or ("ITEM" .. tostring(itemIndex))
    end,
    -- CheckItemPocket (engine/items/items.asm) on wCurItem: the pocket id
    -- behind ItemPocketNames, which GetPocketName copies into wStringBuffer3
    -- for _PutItemInPocketText and _PocketIsFullText.  Same lookup
    -- World:specialSound already makes for the TM/HM jingle.
    getItemPocket = function(itemIndex)
      local _, def = itemByIndex(
        self.game and self.game.data and self.game.data.items, itemIndex)
      return def and def.pocket or nil
    end,
    -- GetTrainerName, not Battle_GetTrainerName: the operand pair IS the
    -- class and member, so nothing here reads wOtherTrainer*.  CAL takes its
    -- own arm before the table is touched (src/world/gen2/TrainerHouse.lua).
    getTrainerName = function(group, index)
      return TrainerHouse.name(self.game and self.game.data
        and self.game.data.trainers, self.game and self.game.save,
        group, index)
    end,
    -- Mirror wStringBuffer2 onto the game so the shared {STRBUF} token can
    -- fill any page the VM itself did not build.
    setStringBuffer = function(value)
      if self.game then self.game.stringBuffer = value end
    end,
    givePoke = function(speciesIndex, level, item, opts)
      local data = self.game and self.game.data
      local save = self.game and self.game.save
      if not (data and save) then return end
      save.party = save.party or {}
      local mon = givePokeMon(data, speciesIndex, level, item, opts)
      if mon then
        if opts and opts.otName then
          mon.ot = opts.otName
          mon.otName = opts.otName
          mon.otId = RANDY_OT_ID
        end
        -- GivePoke -> TryAddMonToParty -> AddPartyMon (move_mon.asm:44-56, :143-149).
        Mon.stampOT(save, mon)
        Party.add(save.party, mon)
        -- GivePoke ends in SetSeenAndCaughtMon, which is why the STARTER is
        -- already ticked off in the #DEX before the first battle.
        save.pokedex = save.pokedex or { seen = {}, caught = {} }
        save.pokedex.seen[mon.species] = true
        save.pokedex.caught[mon.species] = true
        -- AddPartyMon's `.registerunowndex` runs on the same path, so a
        -- gifted Unown lands in the form list too (move_mon.asm:347).
        Unown.registerCatch(save, mon)
      end
      -- engine/pokemon/move_mon.asm:1632-1645
      return mon
    end,
    giveItem = function(itemIndex, qty)
      local data = self.game and self.game.data
      local save = self.game and self.game.save
      if not save then return false end
      save.inventory = save.inventory or {}
      local id = itemByIndex(data and data.items, itemIndex)
      if not id then
        id = "ITEM_" .. tostring(itemIndex)
      end
      return Bag.add(save, id, qty or 1, data)
    end,
    addCell = function(phone)
      local save = self.game and self.game.save
      if not save then return end
      save.phoneContacts = save.phoneContacts or {}
      save.phoneContacts[phone] = true
    end,
    delCell = function(phone)
      local save = self.game and self.game.save
      if not save or not save.phoneContacts then return end
      save.phoneContacts[phone] = nil
    end,
    hasCell = function(phone)
      local save = self.game and self.game.save
      return save and save.phoneContacts and save.phoneContacts[phone] == true
    end,
    cry = function(speciesIndex)
      self:playCry(speciesIndex)
    end,
    playSound = function(sfxId)
      self:playSfx(sfxId)
    end,
    playMusic = function(musicId)
      self:playMusicId(musicId)
    end,
    specialSound = function(itemIndex) self:specialSound(itemIndex) end,
    -- WaitSFX is `call CheckSFX / jr c, WaitSFX` on wCurSFX, so it waits on
    -- WHATEVER sound is on the channels, not only on the ones a script
    -- started.  Phone_StartRinging (engine/phone/phone.asm:564) is the caller
    -- that needs the wider reading: the A-press beep that dismissed the box
    -- before the call is the sound most likely to still be running, and
    -- SFX_CALL ($6a) is quiet enough that the priority gate drops the ring if
    -- it fires over one.  Sound.sfxBusy() is that wCurSFX; World.lastSfx only
    -- covers the sounds World itself started.
    waitSfx = function()
      if require("src.core.Sound").sfxBusy() then return false end
      local src = self.lastSfx
      if not src then return true end
      local ok, playing = pcall(src.isPlaying, src)
      return not (ok and playing)
    end,
    readVar = function(varId)
      return self:readVar(varId)
    end,
    -- `special` ids resolve through the extracted SpecialsPointers order.
    specialOrder = self.constants and self.constants.specialOrder,
    lookupTrainer = function(class, member)
      return self:trainerParty(class, member)
    end,
    startBattle = function(trainer, wild, onDone)
      self:startScriptedBattle(trainer, wild, onDone)
    end,
    catchTutorial = function(wild, battleType, onDone)
      self:startCatchTutorial(wild, battleType, onDone)
    end,
    -- `setup` is true for the ops that run a map SETUP script (`reloadmap`,
    -- `reloadmapafterbattle`), false for `refreshmap`, which is only
    -- LoadOverworldTilemapAndAttrmapPals / ApplyTilemap / UpdateSprites and
    -- runs no setup script at all (engine/overworld/scripting.asm:2044).  Only
    -- the setup arm carries the music row, and it runs BEFORE the deferral
    -- below so a reload mid-scene still consumes wDontPlayMapMusicOnReload.
    reloadMap = function(setup)
      if setup then
        self:forceMapMusic()
        -- Script_reloadmap re-enters through MAPSTATUS_ENTER (engine/overworld/
        -- scripting.asm:1108-1116), so a wild battle re-arms EnterMap's cooldown.
        self.wildCooldown = 5
      end
      -- MapSetupScript_ReloadMap (data/maps/setup_scripts.asm:124) has NO
      -- LoadMapObjects: `reloadmap` / `reloadmapafterbattle` reload blocks,
      -- graphics, palettes and music and leave the object structs standing.
      -- So a flag a script set BEFORE the battle must not cull anybody
      -- mid-scene: AzaleaTownRivalBattleScript sets EVENT_RIVAL_AZALEA_TOWN at
      -- maps/AzaleaTown.asm:57, well before `startbattle`, and only
      -- `disappear`s the rival after the after-battle text and his exit walk.
      -- Same deferral onFlagsChanged uses above, for the same reason.
      if self:scriptRunning() then
        self.peopleDirty = true
        return
      end
      self:rebuildPeople({ seamless = true })
    end,
    -- `warp NONE, 0, 0`, Script_warp's own group-0 arm.  A different thing
    -- from `reloadmap` above: MapSetupScript_BadWarp carries HandleNewMap and
    -- LoadMapObjects, MapSetupScript_ReloadMap carries neither, and it is
    -- precisely the callbacks in HandleNewMap that the bedroom PC's warp is
    -- there to re-run.
    badWarp = function() self:reloadMapBadWarp("bad_warp") end,
    encounterMusic = function(class)
      self:playTrainerEncounterMusic(class)
    end,
    showEmote = function(emote, object, frames)
      self:showEmote(emote, object, frames)
    end,
    trainerApproach = function(onDone) self:trainerApproach(onDone) end,
    faceObject = function(a, b)
      -- faceobject PLAYER, LAST_TALKED: PLAYER is 0, LAST_TALKED is -1/$fe,
      -- and only the player-turns-to-trainer case is ever scripted here.
      if (a or 0) == 0 and self.player and self.trainerNpc then
        local dx = self.trainerNpc.cellX - self.player.cellX
        local dy = self.trainerNpc.cellY - self.player.cellY
        if math.abs(dx) > math.abs(dy) then
          self.player.facing = dx > 0 and "right" or "left"
        elseif dy ~= 0 then
          self.player.facing = dy > 0 and "down" or "up"
        end
      end
      local _ = b
    end,
    openPc = function() self:openPc() end,
    -- engine/menus/menu_2.asm's three balance boxes.  Each is a `special` that
    -- draws a box and RETURNS, and every one of the 23 calls in the game is
    -- followed straight away by `loadmenu` -- the Game Corner prize counters
    -- and the coin vendor, the vending machines -- so the box belongs to the
    -- static menu that answers.  Remembered here and handed to that screen
    -- rather than drawn on the spot, because the menu is what owns the frame.
    showCoins = function() self.scriptBalance = "coins" end,
    showMoney = function(kind) self.scriptBalance = kind or "money" end,
    openMart = function(martType, martId, onDone)
      self:openMart(martType, martId, onDone)
    end,
    openMenu = function(header, style, onChoose)
      self:openScriptMenu(header, style, onChoose)
    end,
    elevator = function(floors, onDone)
      self:openElevator(floors, onDone)
    end,
    npcTrade = function(id, onDone)
      self:openNpcTrade(id, onDone)
    end,
    -- Script_wildoff / Script_wildon (engine/overworld/scripting.asm), which
    -- set and clear STATUSFLAGS_NO_WILD_ENCOUNTERS_F.  Wired from this side
    -- ahead of the VM opcodes so the gate is honoured the moment they land.
    setWildEncounters = function(on)
      self.noWildEncounters = not on
    end,
    healParty = function() self:healParty() end,
    healAnim = function(animType, onDone)
      self:startHealMachineAnim(animType, onDone)
    end,
    nameRival = function(onDone) self:nameRival(onDone) end,
    warpToSpawn = function() self:warpToSpawn() end,

    -- ---- scene, clock, cartridge -------------------------------------------
    getMapScene = function(group, mapNum)
      return self:mapSceneOf(group, mapNum)
    end,
    getTimeOfDay = function() return self:timeOfDayId() end,
    gsVersion = function() return self:gsVersion() end,

    -- ---- ENGINE_* flags ----------------------------------------------------
    -- A DIFFERENT namespace from `setevent`'s wEventFlags: badges, the Pokegear
    -- cards, ENGINE_POKEDEX and the Bug Contest timer live here, and none of
    -- them decides whether an object is on the map, which is why neither hook
    -- touches onFlagsChanged.
    getEngineFlag = function(flag) return self:engineFlag(flag) end,
    setEngineFlag = function(flag, value) self:setEngineFlag(flag, value) end,

    -- ---- vars --------------------------------------------------------------
    writeVar = function(varId, value) self:writeVar(varId, value) end,
    -- `callasm` / `memcallasm`: raw GB code at bank:addr.  The importer does
    -- not resolve the pair against pokegold-symbols/pokegold.sym, so `label` is
    -- nil and the ADDRESS is what dispatches -- which is why
    -- src/script/gen2/CallAsm.lua keys on it.  A nil back leaves wScriptVar
    -- alone, the answer for every routine whose asm does not write it.
    callAsm = function(label, bank, addr)
      return self:callAsm(label, bank, addr)
    end,

    -- ---- map objects -------------------------------------------------------
    appear = function(objectId) self:appearObject(objectId) end,
    moveObject = function(objectId, cx, cy)
      self:moveObject(objectId, cx, cy)
    end,
    variableSprite = function(slot, sprite)
      self:setVariableSprite(slot, sprite)
    end,
    -- DescribeDecoration's read of the wDeco* byte its arm names, plus
    -- GetDecorationName_c_de's wStringBuffer3 for the three arms that print it.
    decorationSlot = function(descName)
      local desc = Decorations.DESC_SLOTS[descName or ""]
      if not desc then return nil end
      local state = Decorations.state(self.game and self.game.save)
      local decoId = state[desc.slot] or 0
      if decoId == 0 then return 0, nil end
      return decoId, desc.named and Decorations.name(decoId) or nil
    end,
    -- LoadEmote is a VRAM preload; World:showEmote picks the sheet by index at
    -- draw time, so there is nothing to warm up.  The VM keeps its own
    -- `loadedEmote` for the movement byte that carries no id.

    -- ---- map blocks and warps ----------------------------------------------
    changeBlock = function(bx, by, blockId)
      self:changeBlock(bx, by, blockId)
    end,
    changeMapBlocks = function(bank, address)
      return self:changeMapBlocks(bank, address)
    end,
    earthquake = function(displacement, frames)
      self:earthquake(displacement, frames)
    end,
    warpTo = function(group, mapNum, cx, cy, facing)
      self:warpTo(group, mapNum, cx, cy, facing)
    end,
    warpCheck = function() self:armWarpCheck() end,
    warpSound = function() self:warpSound() end,
    writeCmdQueue = function() return self:writeCmdQueue() end,
    delCmdQueue = function(kind) return self:delCmdQueue(kind) end,
    newLoadMap = function(method) self:newLoadMap(method) end,
    setWarpMod = function(warpId, group, mapNum)
      self:setWarpMod(warpId, group, mapNum)
    end,
    setBlackoutMap = function(group, mapNum)
      self:setBlackoutMap(group, mapNum)
    end,

    -- ---- encounters --------------------------------------------------------
    setSwarm = function(group, mapNum) self:setSwarm(group, mapNum) end,
    rollWild = function() return self:rollWild() end,
    -- The WRAM bytes the ENGINE owns rather than the script: nil means "not
    -- mine", and the VM falls back to its own sparse store.
    readMem = function(addr) return self:scriptReadMem(addr) end,

    -- ---- music -------------------------------------------------------------
    playMapMusic = function() self:playMapMusic() end,
    fadeOutMusic = function(musicId, fade) self:fadeOutMusic(musicId, fade) end,
    dontRestartMapMusic = function() self.dontRestartMusic = true end,

    -- ---- bag, money and coins ----------------------------------------------
    hasItem = function(itemIndex) return self:hasItem(itemIndex) end,
    takeItem = function(itemIndex, qty)
      return self:takeItem(itemIndex, qty)
    end,
    getMoney = function(account) return self:money(account) end,
    setMoney = function(account, value) self:setMoney(account, value) end,
    getCoins = function() return self:coins() end,
    setCoins = function(value) self:setCoins(value) end,

    -- ---- party -------------------------------------------------------------
    hasPoke = function(speciesIndex) return self:hasPoke(speciesIndex) end,
    giveEgg = function(speciesIndex, level)
      return self:giveEgg(speciesIndex, level)
    end,
    -- `givepokemail` and `checkpokemail` are script COMMANDS ($ea, $eb), not
    -- SpecialsPointers rows, so they belong on the VM's own hook table beside
    -- giveegg the way Vm.new reads them.  They are also listed in
    -- `specials` below, which is where a handler that wanted the same seam
    -- would find them; the command arm cannot see that sub-table.
    givePokeMail = function(mail) return self:givePokeMail(mail) end,
    checkPokeMail = function(mail, onDone) self:checkPokeMail(mail, onDone) end,
    getLandmarkName = function() return self:landmarkName() end,

    -- ---- field events ------------------------------------------------------
    fruitTreeItem = function(tree) return self:fruitTreeItem(tree) end,
    fruitTreeReset = function() return self:fruitTreeReset() end,
    fruitTreePicked = function(tree) return self:fruitTreePicked(tree) end,
    fruitTreePick = function(tree) self:fruitTreePick(tree) end,

    -- ---- phone -------------------------------------------------------------
    addPhoneNumber = function(contact) return self:addPhoneNumber(contact) end,
    setSpecialCall = function(id) self:setSpecialCall(id) end,
    getSpecialCall = function() return self:specialCall() end,

    -- ---- end of game -------------------------------------------------------
    -- Script_halloffame and Script_credits both end on ReturnFromCredits
    -- (Script_endall + MAPSTATUS_DONE), so the VM returns out of the script the
    -- moment either hook is present and neither callback resumes anything the
    -- script still needs.  They are here rather than in `specials` because both
    -- really are script COMMANDS ($9f, $a0), not SpecialsPointers rows.
    hallOfFame = function(onDone) self:hallOfFame(onDone) end,
    credits = function(onDone) self:credits(onDone) end,

    -- ---- the specials ------------------------------------------------------
    -- Everything under src/script/gen2/Specials.lua that has to touch the
    -- world reaches it through this ONE sub-table rather than through a
    -- hundred more `xFn` fields on the VM: a special is an independent routine
    -- and the table is its whole surface, so a handler stays a description of
    -- the cart routine and the World keeps its own seams.
    specials = self:specialHooks(),
  })

  -- The readmem / writemem bytes a script owns outright (the Goldenrod
  -- underground switches, wMooMooBerries) ride the save under `scriptMem`, so
  -- hand them back before any script runs.  Without this the switch room and
  -- the barn silently reset every time the game is reloaded.
  local savedMem = self.game and self.game.save and self.game.save.scriptMem
  if savedMem then self.vm:restoreMem(savedMem) end

  -- Where to start: a restored save's own position, else SPAWN_HOME.
  local startMap, startX, startY, startFacing =
    START_MAP, START_X, START_Y, START_FACING
  local spawn = self.landmarks and self.landmarks.spawns
    and self.landmarks.spawns[SPAWN_HOME]
  if spawn and spawn.map and maps[spawn.map] then
    startMap, startX, startY = spawn.map, spawn.x, spawn.y
  end
  local saved = self.game and self.game.save and self.game.save.position
  -- Which map setup script this load is (engine/menus/intro_menu.asm): a file
  -- with a recorded position is CONTINUE, a New Game is the SPAWN_HOME warp.
  -- setMap reads it back to decide whether HandleNewMap's temporary-flag reset
  -- runs.
  local isContinue = false
  if saved and saved.map and maps[saved.map] then
    startMap, startX, startY = saved.map, saved.x, saved.y
    startFacing = saved.facing or startFacing
    isContinue = true
  end
  -- `farcall JumpRoamMons`, three lines above that same read: EVERY load of a
  -- save scatters the three beasts to random roam maps before the map comes
  -- back, which is what makes re-finding one the price of reloading after a
  -- failed catch.  The map the jump avoids is the one the save was written on,
  -- so this runs while startMap is still the SAVED position and not the
  -- post-credits spawn below.  A file with no InitRoamMons behind it has no
  -- save.roamers and Roamers.jumpAll leaves it that way.
  self:roamMonsOnContinue(startMap)
  -- Continue (engine/menus/intro_menu.asm): `ld a, [wSpawnAfterChampion]` is
  -- read BEFORE the saved position is honoured, and a pending value replaces
  -- it outright -- .SpawnAfterE4 / SpawnAfterRed write wDefaultSpawnpoint and
  -- enter through PostCreditsSpawn's MAPSETUP.WARP instead of
  -- MAPSETUP.CONTINUE.  So the champion whose induction saved them standing
  -- in the Hall of Fame continues in New Bark Town, not in a room whose only
  -- exit is sealed.
  local post = self:consumePostGameSpawn()
  if post then
    startMap, startX, startY, startFacing = post.map, post.x, post.y, "down"
    isContinue = false
  end

  if not maps[startMap] then
    self.status = Strings("%s is missing.\nRe-import the Gold ROM.",
      tostring(startMap))
    return false
  end
  local ok, err = pcall(function()
    self:setMap(startMap, startX, startY, startFacing,
      { continue = isContinue })
  end)
  if not ok then
    self.status = Strings("Failed to boot %s:\n%s",
      tostring(startMap), tostring(err))
    return false
  end
  return self.map ~= nil
end

-- Just the VM, not everything World:busy covers: a deferred object rebuild
-- has to wait for the SCRIPT, not for the text box that is showing its line.
function World:scriptRunning()
  return (self.vm and self.vm:running()) and true or false
end

function World:busy()
  return (self.vm and self.vm:running())
    -- The map setup script is a blocking call inside the cart's overworld loop
    -- (RunMapSetupScript, with the fades and the load inside it), so nothing
    -- else may run while it does -- least of all a step from a direction the
    -- player is still holding from before the warp.
    or self.mapSetup ~= nil
    or self.textbox ~= nil
    or self.moveState ~= nil
    or self.choicebox ~= nil
    -- The rod cast and the tree shake are frame counters with no text box up
    -- for part of their run; on the cart they are script commands, so the
    -- world is frozen for them too and the player cannot walk out from under
    -- the animation.
    or self.fishing ~= nil
    or self.headbutt ~= nil
    -- Same again for a field move's tail: the surf step, the STRENGTH pause
    -- and the waterfall climb are all applymovement / pause commands inside a
    -- queued script, so nothing else may run under them.
    or self.fieldMove ~= nil
end

-- CheckMenuOW (engine/overworld/events.asm:802) is the tail of OWPlayerInput,
-- and OWPlayerInput is only reached from PlayerEvents, which returns straight
-- away while wScriptRunning is non-zero (events.asm:238-243).  Two more gates
-- sit above it even with no script up: PlayerMovement answering
-- PLAYERMOVEMENT_CONTINUE, i.e. the player is mid-step (events.asm:474-477),
-- and CheckStandingOnIce carrying (events.asm:479-480).  START and SELECT are
-- read NOWHERE else in the overworld, so a press that arrives while any of
-- those hold is not queued or deferred, it is never read at all.
function World:acceptsMenuInput()
  if self.battleActive or self:busy() then return false end
  if self.player and self.player.moving then return false end
  -- The same latch pair World:step's slide uses: a latched direction on an ice
  -- tile is CheckStandingOnIce's carry.
  if self.turningDirection and Permissions.isIce(self:playerCollision()) then
    return false
  end
  return true
end

function World:mapIdByGroupMap(group, mapNum)
  if not self.maps then return nil end
  for id, def in pairs(self.maps) do
    if type(def) == "table" and def.group == group and def.map == mapNum then
      return id
    end
  end
  return nil
end

function World:scene()
  if not self.map then return 0 end
  return self.mapScenes[self.map.id] or 0
end

-- ---- the script VM's world hooks -------------------------------------------
--
-- Everything from here to World:specialHooks is one script command or one
-- special reaching into the world.  They are gathered rather than scattered
-- because they share one property: each is the WORLD half of a routine whose
-- other half is transcribed in src/script/gen2/Vm.lua or Specials.lua, and the
-- VM guards every call with `if self.xFn then`, so the interpreter stays
-- correct when a hook is missing and only stops being able to SHOW the result.

-- GetMapSceneID (engine/overworld/scripting.asm): a map with no `scene_var`
-- row at all leaves de = 0 and Script_checkmapscene answers $ff, which is what
-- nil means here.  A map that HAS scene scripts but has never been given a
-- scene is scene 0.
function World:mapSceneOf(group, mapNum)
  local mapId = self:mapIdByGroupMap(group, mapNum)
  if not mapId then return nil end
  local def = self.maps and self.maps[mapId]
  if not (def and def.sceneScripts) then return nil end
  return self.mapScenes[mapId] or 0
end

-- wTimeOfDay (constants/ram_constants.asm): MORN_F 0, DAY_F 1, NITE_F 2,
-- DARKNESS_F 3, off the RTC hour (engine/tilesets/timeofday_pals.asm:5-11)
local TIME_OF_DAY_ID = { MORN = 0, DAY = 1, NITE = 2, DARK = 3 }

function World:timeOfDayId()
  return TIME_OF_DAY_ID[self.tod or self.daytime or "DAY"] or 1
end

-- GetWeekday -> wCurDay, which the RTC counts SUNDAY 0 .. SATURDAY 6 -- the
-- same numbering os.date("%w") answers, so no remap.  `clockDay` overrides the
-- host clock the way `clockHour` overrides the hour, so a driver can stand on
-- Route 29 on a Tuesday and see Tuscany.
function World:weekday()
  if self.clockDay then return math.floor(self.clockDay) % 7 end
  -- Through the base InitDayOfWeek stored, not off the host clock raw: Mom's
  -- wheel is what decides which day the game is on (src/core/gen2/Clock.lua).
  return Clock.weekday(self.game and self.game.save)
end

-- hHours, which VAR.HOUR reads straight off: RTC hour 0..23.  `clockHour`
-- overrides the host clock the same way it does for the daytime palette.
function World:hour()
  if self.clockHour then return math.floor(self.clockHour) % 24 end
  -- CalcNSecsHoursDaysSince reads the RTC through wStartHour / wStartMinute,
  -- the base InitClock wrote when the player answered Oak; a save from before
  -- that screen existed has no base and reads the host clock straight through.
  return Clock.hour(self.game and self.game.save)
end

-- hMinutes, the other half of the same read.  The Pokegear clock card and the
-- DST confirmations are what want it.
function World:minute()
  return Clock.minute(self.game and self.game.save)
end

-- engine/overworld/variables.asm .VarActionTable, walked in order.  readVar
-- and writevar/loadvar share the id space (GetVarAction resolves both), but
-- only the handful of ADDR_DE rows (VAR.BATTLETYPE, VAR.MOVEMENT) are ever
-- written back through writeVar/self.scriptVars; the rest are RETVAR_EXECUTE
-- or RETVAR_STRBUF2 rows that just read state the engine already owns.
function World:readVar(varId)
  if varId == VAR.FACING and self.player then
    return FACING_ID[self.player.facing] or 0
  end
  if varId == VAR.WEEKDAY then return self:weekday() end
  if varId == VAR.BATTLETYPE then return self.scriptVars[VAR.BATTLETYPE] or 0 end
  local save = self.game and self.game.save
  if varId == VAR.PARTYCOUNT then
    return save and #(save.party or {}) or 0
  end
  if varId == VAR.BATTLERESULT then
    -- wBattleResult masked with ~BATTLERESULT_BITMASK (the box-full flag);
    -- the port never sets that bit, so the stored value already matches.
    return self.lastBattleResult or 0
  end
  if varId == VAR.TIMEOFDAY then return self:timeOfDayId() end
  if varId == VAR.DEXCAUGHT then
    return countFlags(save and save.pokedex and save.pokedex.caught)
  end
  if varId == VAR.DEXSEEN then
    return countFlags(save and save.pokedex and save.pokedex.seen)
  end
  if varId == VAR.BADGES then
    -- wBadges is TWO bytes (Johto then Kanto); CountSetBits walks both.
    local player = save and save.player
    return countFlags(player and player.badges)
      + countFlags(player and player.kantoBadges)
  end
  if varId == VAR.MOVEMENT then
    return PLAYER_STATE_ID[self.playerState] or 0
  end
  if varId == VAR.HOUR then return self:hour() end
  if varId == VAR.MAPGROUP then
    return (self.map and self.map.def and self.map.def.group) or 0
  end
  if varId == VAR.MAPNUMBER then
    return (self.map and self.map.def and self.map.def.map) or 0
  end
  if varId == VAR.UNOWNCOUNT then
    -- CountUnown walks wUnownDex, a list of the distinct Unown FORMS caught in
    -- catching order.  save.pokedex still only knows the SPECIES; the form list
    -- is its own record (save.unownDex, src/core/gen2/Unown.lua), written by
    -- the same two events the cart writes it on.
    return Unown.count(save)
  end
  if varId == VAR.ENVIRONMENT then
    return (self.map and self.map.def and self.map.def.environmentId) or 0
  end
  if varId == VAR.BOXSPACE then
    if not save then return 0 end
    return Boxes.MONS_PER_BOX - Boxes.count(save, save.currentBox)
  end
  if varId == VAR.CONTESTMINUTES then
    if not save then return 0 end
    local minutes = BugContest.timeLeft(save)
    return minutes
  end
  if varId == VAR.XCOORD then
    return (self.player and self.player.cellX) or 0
  end
  if varId == VAR.YCOORD then
    return (self.player and self.player.cellY) or 0
  end
  if varId == VAR.SPECIALPHONECALL then
    return self:specialCall()
  end
  return 0
end

-- Script_checkver: 0 for Gold, 1 for Silver (constants/misc_constants.asm
-- GS_VERSION).
function World:gsVersion()
  local GameVersion = require("src.core.GameVersion")
  local save = self.game and self.game.save
  local version = (save and save.version) or GameVersion.get()
  return version == "silver" and 1 or 0
end

-- ENGINE_* flags (data/events/engine_flags.asm), the namespace `setflag` /
-- `clearflag` / `checkflag` write.  Kept on the save under its own key rather
-- than merged into `events`, because the two tables index different arrays on
-- the cart (wEngineBuffer / wBadges / wPokegearFlags vs wEventFlags) and a
-- collision would have BADGE_ZEPHYR hide an NPC.
--
-- It deliberately does NOT rebuild the map's people: no engine flag names an
-- object's MAPOBJECT_EVENT_FLAG.
function World:engineFlags()
  local save = self.game and self.game.save
  if not save then return self._engineFlags or {} end
  save.engineFlags = save.engineFlags or {}
  return save.engineFlags
end

function World:engineFlag(flag)
  if flag == nil then return false end
  local save = self.game and self.game.save
  -- ENGINE_BUG_CONTEST_TIMER is not a bit of its own here: it IS
  -- save.bugContest.active, because that is what CheckTimeEvents polls and what
  -- RandomEncounter branches on.  Keeping a second copy in the flag table is
  -- how the two would come apart -- the officer's `setflag` and the results
  -- script's `clearflag` are the only writers, and both go through the pair
  -- below.
  if flag == BugContest.ENGINE_BUG_CONTEST_TIMER and save then
    return BugContest.isActive(save)
  end
  -- Badges live in save.player.badges, not in the flag table: on the cart the
  -- ENGINE_*BADGE ids ARE the bits of wJohtoBadges/wKantoBadges, so there is
  -- only one store and everything that asks (field moves, VAR.BADGES, the
  -- trainer card) has to see the same answer.  See FieldMoves.BADGE_FLAG.
  local badge = FieldMoves.BADGE_FLAG[flag]
  if badge and save then
    local player = save.player
    local owned = player and player[badge.store]
    return type(owned) == "table" and owned[badge.name] == true
  end
  -- Same one-store rule for the day care.  data/events/engine_flags.asm:18-20
  -- maps the three ids onto DAYCAREMAN_HAS_EGG_F / DAYCAREMAN_HAS_MON_F /
  -- DAYCARELADY_HAS_MON_F, i.e. they ARE the bits DayCare_InitBreeding,
  -- DayCareStep and the deposit/withdraw routines write, so `checkflag` reads
  -- the deposit state directly.  Route34EggCheckCallback branches on all three
  -- (maps/Route34.asm:21-49) to put the gramps in the yard and to un-hide the
  -- two day-care mon objects; a second copy in save.engineFlags is exactly how
  -- the yard stayed empty forever.
  if save then
    if flag == ENGINE.DAY_CARE_MAN_HAS_EGG then
      return Breeding.dayCare(save).hasEgg == true
    elseif flag == ENGINE.DAY_CARE_MAN_HAS_MON then
      return (Breeding.side(save, "man") or {}).mon ~= nil
    elseif flag == ENGINE.DAY_CARE_LADY_HAS_MON then
      return (Breeding.side(save, "lady") or {}).mon ~= nil
    end
  end
  return self:engineFlags()[flag] == true
end

function World:setEngineFlag(flag, value)
  if flag == nil then return end
  local save = self.game and self.game.save
  if flag == BugContest.ENGINE_BUG_CONTEST_TIMER and save then
    -- Route35NationalParkGate_OkayToProceed sets the flag BEFORE `special
    -- GiveParkBalls`, so starting here and starting again there is the cart's
    -- own order and the second start is what puts the balls on the counter.
    -- BugContestResultsScript's clearflag is the stop, and it deliberately
    -- leaves the caught mon alone: CheckPartyFullAfterContest runs after it.
    if value then BugContest.start(save) else BugContest.stop(save) end
    return
  end
  local badge = FieldMoves.BADGE_FLAG[flag]
  if badge and save then
    save.player = save.player or {}
    save.player[badge.store] = save.player[badge.store] or {}
    save.player[badge.store][badge.name] = value and true or nil
    return
  end
  -- The write half of the day-care aliases.  DayCareManScript_Outside's
  -- `clearflag ENGINE.DAY_CARE_MAN_HAS_EGG` (maps/Route34.asm) is the ONLY cart
  -- script that writes any of the three, and it is idempotent because
  -- DayCareManOutside already did `res DAYCAREMAN_HAS_EGG_F, [hl]`
  -- (engine/events/daycare.asm:393), which is Breeding.collectEgg here.  The
  -- two HAS_MON bits belong to the deposit/withdraw routines, so a script
  -- write to them would be a second store: swallow it.
  if save then
    if flag == ENGINE.DAY_CARE_MAN_HAS_EGG then
      Breeding.dayCare(save).hasEgg = value and true or false
      return
    elseif flag == ENGINE.DAY_CARE_MAN_HAS_MON
        or flag == ENGINE.DAY_CARE_LADY_HAS_MON then
      return
    end
  end
  local flags = self:engineFlags()
  flags[flag] = value and true or nil
end

-- Script_writevar / Script_loadvar.  VAR.BATTLETYPE is the only slot anything
-- reads BACK out of scriptVars today, and startScriptedBattle is where it is
-- consumed.
--
-- VAR.MOVEMENT is the exception, and it is not a stored value at all: its row
-- in .VarActionTable is the ADDRESS of wPlayerState, so `loadvar VAR.MOVEMENT,
-- PLAYER_BIKE` changes the player's state outright.  That is the whole of
-- Script_GetOnBike -- the `special UpdatePlayerSprite` after it only reloads
-- the sheet applyPlayerState has already picked.
function World:writeVar(varId, value)
  if varId == nil then return end
  self.scriptVars[varId] = value or 0
  if varId == VAR.MOVEMENT then
    local state = PLAYER_STATE_BY_ID[value or 0]
    if state then self:applyPlayerState(state) end
  end
end

function World:battleType()
  return self.scriptVars[VAR.BATTLETYPE] or 0
end

-- Script_callasm / Script_memcallasm: a bank:address into raw GB code.  The
-- pair is resolved against pokegold-symbols/pokegold.sym in
-- src/script/gen2/CallAsm.lua, which is where the routines themselves are
-- ported; a site that is not in its table answers nil, and so does a routine
-- whose asm writes no wScriptVar.  Either way the VM leaves wScriptVar alone
-- rather than picking a branch at random for the `callasm` / `iffalse` pairs.
--
-- Nothing in the cache dispatches through here.  The thirty-eight rows that
-- used to carry one of the four opcodes all sat inside keys the extractor had
-- made out of three-byte `hiddenitem` bg_event operands, so their addresses
-- were noise, and a cache built since that decode landed has none at all.  The
-- table is reached through CallAsm.run from the hand-ported engine flows
-- instead -- countStep's hatch and poison arms, and whiteOut.
function World:callAsm(label, bank, addr)
  return CallAsm.dispatch(self, label, bank, addr)
end

-- Script_appear: the mirror of World:disappearObject.  Both halves have to
-- come off, or a disappear/appear pair is one-way: the event flag AND the
-- synthetic hide the flagless path wrote under the same key.
--
-- The rebuild is immediate rather than deferred through peopleDirty, because
-- ApplyEventActionAppearDisappear respawns the object struct inside the
-- command -- unlike a plain `setevent`, which the cart only reads back on the
-- next map load.
function World:appearObject(objectId)
  local index = (objectId or 0) - 1
  local def = self.map and self.map.def
  local obj = def and def.objects and def.objects[index]
  if not obj then return end
  if obj.eventFlag and obj.eventFlag ~= 0xFFFF then
    self.events:set(obj.eventFlag, false)
  end
  -- UnmaskObject (home/map.asm:1548) clears exactly ONE byte of wObjectMasks,
  -- this object's, and NOTHING re-reads the event flag until the next
  -- LoadObjectMasks at map load.  Objects sharing one MAPOBJECT_EVENT_FLAG are
  -- ordinary -- the three animated Burned Tower beasts all carry
  -- EVENT_BURNED_TOWER_B1F_BEASTS_1 (maps/BurnedTowerB1F.asm:152) and
  -- ReleaseTheBeasts `appear`s them one at a time (:27, :33, :39) -- so the
  -- flag alone must not put the other two on the map with this one.
  self:setObjectMask(obj, index, false)
  -- Script_appear RESPAWNS the object struct out of the MAP object
  -- (UnmaskCopyMapObjectStruct, home/map_objects.asm:309 -> CopyObjectStruct ->
  -- CopyMapObjectToObjectStruct, engine/overworld/player_object.asm:207-215,
  -- which re-seeds the struct's X/Y from MAPOBJECT_X_COORD/MAPOBJECT_Y_COORD),
  -- so an `appear` takes the cell a preceding `moveobject` wrote.  The pooled
  -- NPC is the OLD struct: keeping it is what left Kurt standing at the well
  -- entrance after `moveobject SLOWPOKEWELLB1F_KURT, 11, 6` and sent his
  -- victory walk off from the wrong cell.  Dropping it is the literal port of
  -- the respawn -- pooledNpc rebuilds from the def on the next pass.
  if self.npcPool then
    self.npcPool[string.format("%s_obj_%d", self.map.id, obj.index or 0)] = nil
  end
  self:rebuildPeople({ seamless = true })
end

-- Script_moveobject: MAPOBJECT_X_COORD / MAPOBJECT_Y_COORD, in plain map
-- cells.  It nearly always names an object that is still HIDDEN (the pairing is
-- `moveobject` then `appear`), so the def is written first and the live NPC
-- second: a rebuild that has not happened yet must still find the new cell.
function World:moveObject(objectId, cellX, cellY)
  local index = (objectId or 0) - 1
  local def = self.map and self.map.def
  local obj = def and def.objects and def.objects[index]
  if not (obj and cellX and cellY) then return end
  local mapId = self.map and self.map.id
  local key = obj.index or index
  if mapId then
    self.objectSpawns = self.objectSpawns or {}
    self.objectSpawns[mapId] = self.objectSpawns[mapId] or {}
    if not self.objectSpawns[mapId][key] then
      self.objectSpawns[mapId][key] = { obj.x, obj.y }
    end
  end
  obj.x, obj.y = cellX, cellY
  local npc = self:objectEntity(objectId)
  if npc and npc ~= self.player then
    npc.cellX, npc.cellY = cellX, cellY
    npc.px, npc.py = cellX * 16, cellY * 16
    npc.moving = false
    npc.progress = 0
    npc.targetX, npc.targetY = nil, nil
    -- The anim path is anchored on where the object was placed, so a teleported
    -- NPC that walks a radius has to take its home with it.
    npc.homeX, npc.homeY = cellX, cellY
    -- The `appear` beside it re-runs StepFunction_Reset, which re-reads the
    -- object's own tile (engine/overworld/map_objects.asm:498-511, :196-208).
    npc.inGrass = self:grassAt(cellX, cellY)
    npc.grassShake = nil
  end
end

-- Every POOLED object whose `sprite` is the SPRITE.VARS byte for `slot`, handed
-- the sheet the slot now names -- `special LoadUsedSpritesGFX`, which is the
-- command that sits beside `variablesprite` at every one of its four call sites
-- (maps/Route36.asm:71, FuchsiaGym.asm:36 and :66, CopycatsHouse2F.asm:24).
--
-- The pool is keyed `<mapId>_obj_<index>` and an NPC holds the SpriteRenderer it
-- was created with, so a pooled object otherwise keeps whatever sheet the slot
-- held when it was first built.  On the cart that cannot happen: LoadUsedSpritesGFX
-- and the LoadMapObjects every map load runs both re-read wVariableSprites, and a
-- connected map's objects are not loaded at all until the seam crossing loads
-- them.  This port keeps the neighbor strips' objects pooled as ghosts and
-- crosses a connection SEAMLESSLY (World:tryConnection -> setMap{ seamless =
-- true }, which keeps npcPool), so without this the pair of TWINS on Route 37 --
-- both SPRITE_WEIRD_TREE, maps/Route37.asm:237-238 -- keep the SPRITE_SUDOWOODO
-- sheet they were pooled with while the player was still on Route 36, for the
-- whole rest of the visit.  Walk north out of the Sudowoodo fight and Ann and
-- Anne are two Sudowoodo.
--
-- The repaint is in place (NPC:setSpriteDef) and not a retire-and-rebuild.  Two
-- of the four call sites run with the object standing in front of the player
-- mid-conversation -- LassAliceScript is `applymovement FUCHSIAGYM_FUCHSIA_GYM_1,
-- Movement_NinjaSpin / faceplayer / variablesprite / special LoadUsedSpritesGFX /
-- faceplayer` (FuchsiaGym.asm:61-66) -- and the cart touches no part of the
-- object struct there.  A fresh NPC table would strand World.talkNpc, .trainerNpc,
-- .followState and any live moveState on an object no longer on the map, and
-- would drop the ninja back to her map-def cell, facing and unfrozen state
-- halfway through unmasking.
--
-- An emptied slot is the one case that DOES retire: resolveSprite answers nil,
-- nothing can be drawn, and World:pooledNpc is the gate that keeps the object
-- off the map until the slot is filled again.
function World:repaintVariableSpritePool(slot)
  if not self.npcPool then return end
  local byte = SPRITE.VARS + slot
  for key, npc in pairs(self.npcPool) do
    if npc.def and npc.def.sprite == byte then
      local name = self:resolveSprite(byte)
      local spriteDef = type(name) == "table" and name
        or (name and self.sprites and self.sprites[name])
      if spriteDef then
        if npc:setSpriteDef(spriteDef) then self:applySpritePalette(npc) end
      else
        self.npcPool[key] = nil
      end
    end
  end
end

-- Script_variablesprite: wVariableSprites[slot] = sprite byte.  Filling the
-- slot is what puts the Sudowoodo, the Copycat, the Olivine rival and the four
-- Fuchsia Gym Janines on the map at all -- their objects carry a NUMBER in
-- `sprite` ($f0..$fc) and World:pooledNpc finds no sheet for one until here.
--
-- REFILLING it is the other half, and it is what Route 36 does: the slot holds
-- SPRITE_SUDOWOODO from InitializeEventsScript until the fight, and
-- WateredWeirdTreeScript's `variablesprite SPRITE_WEIRD_TREE, SPRITE_TWIN`
-- (maps/Route36.asm:58, and again at :70 on the DidntCatchSudowoodo arm) hands
-- the same slot to the Route 37 twins.  So the pooled objects that read
-- through the slot have to go with it.
function World:setVariableSprite(slot, spriteIndex)
  if slot == nil then return end
  self.variableSprites[slot] = spriteIndex
  self:repaintVariableSpritePool(slot)
  self:rebuildPeople({ seamless = true })
end

-- The other half of the above: an object whose `sprite` is a SPRITE.VARS byte
-- resolves through the slot table and constants.spriteOrder (1-based, because
-- sprite_constants.asm's block is `const_def 1`).  An unfilled slot answers nil
-- and the object simply does not spawn, which is the cart's behaviour too.
-- InitializeEventsScript's `variablesprite` list, recovered from scripts.lua.
--
-- Only needed for a cache written before the extractor learned to record them;
-- `initial_events.sprites` is the direct answer once one is rebuilt.  The
-- script is identified by its content rather than by a symbol, which the
-- runtime does not have: it is the one whose `setevent` ids are exactly the
-- seed list this same file already trusts.
function World:findInitialSprites()
  local wanted = {}
  local count = 0
  for _, id in ipairs(self.initialEvents or {}) do
    wanted[id] = true
    count = count + 1
  end
  if count == 0 or type(self.scripts) ~= "table" then return {} end
  for key, list in pairs(self.scripts) do
    if type(key) == "string" and type(list) == "table" then
      local hits, sprites = 0, {}
      for _, cmd in ipairs(list) do
        if type(cmd) == "table" then
          if cmd.op == "setevent" then
            local id = cmd.event or (cmd.args and cmd.args[1])
            if id and wanted[id] then hits = hits + 1 end
          elseif cmd.op == "variablesprite" then
            local args = cmd.args or {}
            local slot = cmd.slot or args[1]
            local sprite = cmd.sprite or args[2]
            if slot and sprite then
              sprites[#sprites + 1] = { slot = slot, sprite = sprite }
            end
          end
        end
      end
      if hits == count and #sprites > 0 then return sprites end
    end
  end
  return {}
end

-- GetMonSprite's .BreedMon1 / .BreedMon2 tail (engine/overworld/overworld.asm:
-- 279-305): both arms fall into .Mon, which is LoadOverworldMonIcon of the
-- deposited species.  There is no sprites.lua row to name here -- the species
-- is whatever the player left in the day care -- so the def is built in the
-- shape RomExtractorGen2:extractMonSprites emits for every other
-- POKEMON_SPRITE row and World:pooledNpc takes it directly.
--
-- Keyed on species and cached, which is safe because World.npcPool is keyed
-- `<mapId>_obj_<index>` only: a swap in the day care while the pool is warm
-- would otherwise leave the old icon standing.  rebuildPeople empties the pool
-- on map entry, which is exactly when the cart reloads the sprite too
-- (LoadMapObjects), so there is nothing further to invalidate.
function World:breedmonSpriteDef(species)
  if not species then return nil end
  self.breedmonSprites = self.breedmonSprites or {}
  local hit = self.breedmonSprites[species]
  if hit ~= nil then return hit or nil end
  local icons = self.game and self.game.data and self.game.data.gen2Icons
  local iconId = icons and icons.species and icons.species[species]
  local entry = iconId and icons.icons and icons.icons[iconId]
  if not (entry and entry.image) then
    self.breedmonSprites[species] = false
    return nil
  end
  local def = {
    id = "SPRITE_DAY_CARE_MON",
    image = entry.image,
    frames = 1,
    walker = false,
    spriteType = "POKEMON_SPRITE",
    palette = "PAL_OW_RED",
    paletteId = 0,
    species = species,
    icon = iconId,
  }
  self.breedmonSprites[species] = def
  return def
end

function World:resolveSprite(sprite)
  if type(sprite) ~= "number" then return sprite end
  -- GetMonSprite tests the two day-care bytes ABOVE the SPRITE.VARS range, so
  -- they must never reach the wVariableSprites arm.  .NoBreedmon answers sprite
  -- 1 for an empty slot; nil is the honest port, because an empty slot leaves
  -- the object's own event flag (EVENT_DAY_CARE_MON_1/2) set and
  -- Route34EggCheckCallback only clears it once checkflag says a mon is there.
  if sprite == SPRITE.DAY_CARE_MON_1 or sprite == SPRITE.DAY_CARE_MON_2 then
    local save = self.game and self.game.save
    local slot = save and Breeding.side(save,
      sprite == SPRITE.DAY_CARE_MON_1 and "man" or "lady")
    local mon = slot and slot.mon
    return mon and self:breedmonSpriteDef(mon.species) or nil
  end
  if sprite < SPRITE.VARS then return nil end
  local byte = self.variableSprites[sprite - SPRITE.VARS]
  if not byte or byte == 0 then return nil end
  local order = self.constants and self.constants.spriteOrder
  return order and order[byte] or nil
end

-- Script_changeblock.  The VM has already halved the script's cell coords into
-- block coords; replaceBlock is the same buffer edit CUT and WHIRLPOOL make,
-- which means the change is undone by the next LoadMapAttributes (World:setMap
-- calls restoreBlocks) exactly as it is on the cart, and the shared maps.lua
-- table never keeps a script's edit across a New Game.
function World:changeBlock(blockX, blockY, blockId)
  local map = self.map
  if not (map and blockX and blockY and blockId) then return false end
  if blockX < 0 or blockY < 0 or blockX >= map.width or blockY >= map.height then
    return false
  end
  return self:replaceBlock(blockY * map.width + blockX + 1, blockId)
end

-- Resolve a raw ROM blockdata pointer (bank + address, as a `dba` writes into
-- wMapBlocksBank / wMapBlocksPointer) to the blocks a cache actually holds.
-- Every map's attributes name the bank and address of its own blockdata, and
-- RomExtractorGen2 records that pair as def.blockdata, so a pointer is found by
-- the array it lands IN: `address` may sit part way through one, which is how
-- the cart names a sub-rectangle of a bigger map's data.  Returns the source
-- block array and a 0-based offset into it, or nothing when no array covers the
-- address (an older cache, whose maps carry no `blockdata`, always answers
-- nothing rather than guessing).
function World:blockdataAt(bank, address)
  if not (bank and address) then return nil end
  for _, def in pairs(self.maps or {}) do
    local bd = def.blockdata
    if bd and bd.bank == bank and bd.address and def.blocks
        and address >= bd.address and address < bd.address + #def.blocks then
      return def.blocks, address - bd.address
    end
  end
  return nil
end

-- Script_changemapblocks: a `dba` into wMapBlocksBank / wMapBlocksPointer, then
-- ChangeMap and BufferScreen.  ChangeMap refills the WHOLE overworld buffer
-- from a second copy of the blockdata -- wMapWidth bytes a row for wMapHeight
-- rows, read as one flat run off the pointer -- so the amount copied is decided
-- by the map standing on screen and not by whichever array the pointer names.
--
-- The edits are recorded the way replaceBlock records a CUT so restoreBlocks
-- puts the map back on the next load, and BufferScreen is refreshMapImages: a
-- baked canvas is keyed by map and daytime and knows nothing about the blocks
-- it came from, so leaving it up would keep showing the map as it was first
-- baked.
--
-- A pointer this cache cannot place is a no-op rather than a guess, and so is a
-- run that would read off the end of the source array (the cart would happily
-- read into whatever data follows it).  Nothing in pokegold reaches the command
-- -- 0 hits across maps/ and engine/, it is a Crystal-era path -- so a script
-- that does is by definition one this port has never seen.
function World:changeMapBlocks(bank, address)
  local map = self.map
  local blocks = map and map.def and map.def.blocks
  if not (map and blocks and map.width and map.height) then return false end
  local src, offset = self:blockdataAt(bank, address)
  if not src then return false end
  local count = map.width * map.height
  if offset + count > #src then return false end
  -- Read the run out first: the pointer is allowed to name the loaded map's own
  -- blockdata, and at a non-zero offset an in-place copy would overwrite the
  -- bytes it is still reading.
  local run = {}
  for i = 1, count do run[i] = src[offset + i] end
  local edits = self.blockEdits[map.id]
  if not edits then
    edits = {}
    self.blockEdits[map.id] = edits
  end
  for i = 1, count do
    if edits[i] == nil then edits[i] = blocks[i] end
    blocks[i] = run[i]
  end
  map.blocks = blocks
  self:refreshMapImages()
  return true
end

-- Script_earthquake -> ShakeScreen.  ONE byte carries two numbers
-- (MovementFunction_ScreenShake .GetDurationAndField1e): the low six bits are
-- the duration in frames, and the top two pick an amplitude of 1 << bits, which
-- StepFunction_ScreenShake adds to and subtracts from wPlayerStepVectorY on
-- alternate frames.  `earthquake 80` ($50) is therefore two pixels for sixteen
-- frames, not eighty of anything.
--
-- This starts the shake and returns AT ONCE: the VM holds the script for the
-- frames itself, so blocking here would count them twice.
function World:earthquake(displacement, frames)
  local byte = displacement or 0
  local amplitude = 2 ^ (math.floor(byte / 64) % 4)
  self.shake = { left = frames or (byte % 64), amplitude = amplitude, phase = 0 }
end

function World:updateShake()
  local shake = self.shake
  if not shake then return end
  shake.left = shake.left - 1
  if shake.left <= 0 then
    self.shake = nil
    return
  end
  -- `.GetSign`: the offset flips with the parity of the frames left.
  shake.phase = (shake.left % 2 == 0) and shake.amplitude or -shake.amplitude
end

-- engine/events/poisonstep_pals.asm:9
function World:poisonBGFlash()
  self.poisonFlash = 4
end

-- Script_warp / Script_warpfacing: a raw destination CELL, distinct from the
-- warp_events World:takeWarp follows.  `facing` is nil for `warp` and a
-- Movement direction for `warpfacing` (PLAYERSPRITESETUP_CUSTOM_FACING).  A
-- group/map pair this cache cannot resolve is a silent no-op rather than a
-- crash, the same way Script_warp's own group-0 arm goes nowhere.
--
-- Script_warp's own entry method is MAPSETUP.WARP, whose script opens on
-- DisableLCD rather than on a FadeOutToWhite: the screen goes at once and only
-- the way back in is a fade.  A `warpfacing` byte is PLAYERSPRITESETUP_CUSTOM_
-- FACING, which SpawnInCustomFacing applies INSTEAD of SpawnInFacingDown, so a
-- custom facing skips World:spawnFacing rather than being overridden by it.
function World:warpTo(group, mapNum, cellX, cellY, facing)
  local mapId = self:mapIdByGroupMap(group, mapNum)
  if not mapId then return false end
  return self:warpToMapId(mapId, cellX, cellY, facing)
end

-- The same warp addressed by map id instead of the cart's group/map pair.
-- Script code always has the pair; mod.world:warpTo (src/world/gen2/
-- WorldAPI.lua) and anything else holding a maps[] key comes in here, so both
-- run one body and a warp from a mod is indistinguishable from a scripted one.
function World:warpToMapId(mapId, cellX, cellY, facing)
  if not (mapId and cellX and cellY) then return false end
  return self:runMapSetup(MAPSETUP.WARP, function()
    local ok = self:setMap(mapId, cellX, cellY,
      facing or (self.player and self.player.facing) or "down")
    if ok and not facing then self:spawnFacing() end
    return ok
  end)
end

-- Script_warp's group-0 arm: `warp NONE, 0, 0`.  wDefaultSpawnpoint is
-- SPAWN_N_A, and EnterMapSpawnPoint leaves the map and the coordinates alone
-- when it reads that, so MAPSETUP.BADWARP is a full load of the map the player
-- is already standing on -- HandleNewMap, LoadBlockData and LoadMapObjects
-- included.  That is what PlayersHousePCScript's `.Warp` is for: the bedroom's
-- decorations only move when the map is loaded again.
-- `reason` is the map.reloaded payload's own field and doubles as the emit
-- gate: src/world/gen2/WorldAPI.lua's invalidateMap calls this with NO reason
-- and raises the event itself with "invalidate", so passing one here is how an
-- engine-side reload says "nobody else is announcing this one".  Without that
-- split a mod calling mod.world:invalidateMap would see the event twice.
function World:reloadMapBadWarp(reason)
  local map = self.map
  local p = self.player
  if not (map and p) then return false end
  local mapId = map.id
  local cx, cy, facing = p.cellX, p.cellY, p.facing
  local ok = self:runMapSetup(MAPSETUP.BADWARP, function()
    return self:setMap(mapId, cx, cy, facing)
  end)
  if ok and reason then
    Runtime.emit("map.reloaded", { mapId = mapId, reason = reason })
  end
  return ok
end

-- Script_warpcheck -> WarpCheck.  It does NOT warp: it notices that the player
-- is standing on a warp tile and lets the overworld loop take it once the
-- script is done, which is why every use sits at the end of a scripted walk.
function World:armWarpCheck()
  local p = self.player
  if not (self.map and p) then return false end
  local entry = self.map:warpAt(p.cellX, p.cellY)
  if not entry then return false end
  self.pendingWarp = entry.def
  return true
end

-- The drain, from World:step.  Deliberately gated on the SCRIPT rather than on
-- World:busy: the text box that is still showing the last line belongs to the
-- script that armed this, and the cart takes the warp the moment the script
-- ends.
function World:takePendingWarp()
  local warp = self.pendingWarp
  if not warp then return false end
  self.pendingWarp = nil
  return self:takeWarp(warp)
end

-- Script_warpsound -> GetWarpSFX (home/map.asm): which of three sounds a warp
-- makes is decided by the tile the player is STANDING on, not by the
-- destination.  Looked up by name so a cache whose sfx table sits at other
-- indices still finds them.
local WARP_SFX_NAME = {
  [SFX.ENTER_DOOR] = "Sfx_EnterDoor",
  [SFX.WARP_TO] = "Sfx_WarpTo",
  [SFX.EXIT_BUILDING] = "Sfx_ExitBuilding",
}

-- Play an sfx by its pokegold LABEL, falling back to the index this cache
-- happened to have when the constant above was written.  A repointed sfx table
-- would otherwise play whatever now sits at the old index.
function World:sfxIdNamed(want, fallbackId)
  local audio = self.game and self.game.data and self.game.data.audio
  local order = audio and audio.sfxOrder
  local id = fallbackId
  if order and want then
    for i, name in ipairs(order) do
      if name == want then id = i - 1 break end
    end
  end
  return id
end

function World:playSfxNamed(want, fallbackId)
  self:playSfx(self:sfxIdNamed(want, fallbackId))
end

-- Script_specialsound (engine/overworld/scripting.asm:476) is not a fixed cue:
-- it farcalls CheckItemPocket (engine/items/items.asm:512), which writes
-- wCurItem's pocket into wItemAttributeValue, and rings SFX.GET_TM for the
-- TM/HM pocket, SFX.ITEM for every other one.  It is the sound inside
-- GiveItemScript, so every `verbosegiveitem` runs through it -- Sage Li's
-- `verbosegiveitem HM_FLASH` and every gym leader's TM included, all of which
-- rang the ordinary item jingle while the item argument was thrown away.  An
-- item the cache cannot name takes the `cp TM_HM / jr z` fall-through, SFX.ITEM.
function World:specialSound(itemIndex)
  local id = itemIndex and self:itemIdByIndex(itemIndex)
  local items = self.game and self.game.data and self.game.data.items
  local def = id and items and items[id]
  if def and def.pocket == "TM_HM" then
    self:playSfxNamed("Sfx_GetTm", SFX.GET_TM)
  else
    self:playSfxNamed("Sfx_Item", SFX.ITEM)
  end
end

function World:warpSound()
  local p = self.player
  if not (self.map and p) then return end
  local coll = self.map:cellCollision(p.cellX, p.cellY)
  local id = SFX.EXIT_BUILDING
  if coll == COLL.DOOR then
    id = SFX.ENTER_DOOR
  elseif coll == COLL.WARP_PANEL then
    id = SFX.WARP_TO
  end
  self:playSfxNamed(WARP_SFX_NAME[id], id)
end

-- Script_newloadmap: hMapEntryMethod, then MAPSTATUS_ENTER on the CURRENT map.
-- The port has one map load, so the reload itself is a setMap onto the cell the
-- player is already standing on, which is what puts the magnet train and a link
-- return back on their feet; the MAPSETUP_* byte picks which setup script the
-- load is wrapped in.
--
-- It plays NO sound: Script_newloadmap is four lines and none of them is a
-- PlaySFX.  Where the cart wants one it writes the separate `warpsound` command
-- in front (WarpToNewMapScript is exactly that pair), so inventing one here rang
-- a door bell over every scripted re-entry that has none.
--
-- A load that a `warpcheck` armed goes to the DESTINATION, not back onto the
-- current cell.  MapSetupScript_Train opens `mapsetup EnterMapWarp` /
-- `mapsetup GetWarpDestCoords` (data/maps/setup_scripts.asm), and EnterMapWarp
-- copies wNextWarp / wNextMapGroup / wNextMapNumber -- the triple CopyWarpData
-- wrote when warpcheck found the player on a warp tile -- into wWarpNumber and
-- the map pair.  That pairing is the Magnet Train and nothing else: the two
-- station scripts are the only `warpcheck` in the game followed by a
-- `newloadmap` rather than by a bare `end`, so every other caller still
-- re-enters the map it is standing on.
--
-- MapSetupScript_Train has no SpawnInFacingDown, unlike _Warp and _Door, so the
-- player steps off the train still facing the way they walked onto it.
--
-- The arrival cell is the destination `warp_event`'s own cell and nothing else.
-- Both stations land the player in the train doorway at (11,5) while their
-- single `coord_event` sits at (11,6), which reads like an off-by-one until the
-- block data is checked: TILESET_TRAIN_STATION block $12 is `tilecoll WALL,
-- WALL, WALL, DOOR`, so (10,5), (12,5) and (11,4) are all wall and SOUTH is the
-- only step there is.  Script_ArriveFromGoldenrod is reached by that one forced
-- step, the same way the cart reaches it -- EnterMap runs DisableEvents, and
-- CheckPlayerState only turns player events back on once a step finishes, so
-- no coord event can fire on the load's own frame however the spawn is placed.
-- Nudging the spawn onto the coord_event would also walk the player into the
-- officer: the arrival movement is `left left down down down down`, which ends
-- at (9,10) from (11,6) but at (9,9) from (11,5), and (9,9) is the boarding
-- gate the officer's own return movement ends on.
-- Locked by tests/gen2_magnet_train_test.lua.
function World:newLoadMap(method)
  local p = self.player
  if not (self.map and p) then return false end
  local armed = self.pendingWarp
  if armed then
    self.pendingWarp = nil
    local destMapId, destWarpNumber = self:resolveWarp(armed)
    local dest = self.maps[destMapId]
    local destWarp = dest and dest.warps and dest.warps[destWarpNumber]
    if destWarp then
      self.backupMapId = self.map.id
      -- CopyWarpData ran when `warpcheck` found the player on the tile, so
      -- this take carries the same wPrevWarp bookkeeping as a walked warp.
      local prevMapId = self.map.id
      local prevWarpIndex = self:warpIndexOf(armed)
      return self:runMapSetup(method, function()
        local ok = self:setMap(destMapId, destWarp.x, destWarp.y, p.facing)
        if ok then
          self:recordWarpBackup(prevMapId, prevWarpIndex, destWarp, destMapId)
        end
        return ok
      end)
    end
  end
  return self:runMapSetup(method, function()
    return self:setMap(self.map.id, p.cellX, p.cellY, p.facing)
  end)
end

-- Script_warpmod: wBackupWarpNumber / wBackupMapGroup / wBackupMapNumber, the
-- triple that says where the game believes you came IN from.  Elevator's
-- .FindCurrentFloor and the dig / escape-rope return are what read it back;
-- neither exists yet, so STORING it is the whole point.
function World:setWarpMod(warpId, group, mapNum)
  local save = self.game and self.game.save
  if not save then return end
  save.warpMod = {
    warp = warpId,
    map = self:mapIdByGroupMap(group, mapNum),
    group = group, mapNumber = mapNum,
  }
end

-- Script_blackoutmod: wLastSpawnMapGroup / wLastSpawnMapNumber.  The S.S. Aqua
-- and Mr. Pokemon's house set it so that losing at sea does not respawn you
-- somewhere you cannot leave, so World:warpToSpawn has to prefer it over the
-- SPAWN_* landmark lookup, and it has to survive a save.
function World:setBlackoutMap(group, mapNum)
  local save = self.game and self.game.save
  if not save then return end
  save.blackoutMap = self:mapIdByGroupMap(group, mapNum)
end

-- Script_swarm -> StoreSwarmMapIndices, which FALLS THROUGH into SetSwarmFlag:
-- the map pair and DAILYFLAGS1_SWARM are set by the one command.  A port that
-- stored only the map would leave the Dunsparce call live forever, because
-- CheckSwarmFlag answers off the flag and clears the pair itself.
function World:setSwarm(group, mapNum)
  local save = self.game and self.game.save
  if not save then return end
  save.dailyFlags = save.dailyFlags or {}
  save.dailyFlags.swarm = true
  save.swarmMap = self:mapIdByGroupMap(group, mapNum)
end

-- Script_loadwildmon's other half: roll the CURRENT map's own table the way a
-- step would, and hand it to the startbattle that follows.  nil is fine --
-- startScriptedBattle answers "win" rather than hanging when there is no mon.
function World:rollWild()
  local map = self.map
  if not (map and self.encounters and self.player) then return nil end
  -- Script_randomwildmon only clears wBattleScriptFlags; the pair `startbattle`
  -- then fights is whatever last wrote wTempWildMonSpecies / wCurPartyLevel.
  -- RockMonEncounter is the one routine in this port that writes it ahead of a
  -- `randomwildmon`, and its mon comes from TREEMON_SET_ROCK rather than from
  -- the map's grass list, so it is consumed here rather than rolled over.
  local pending = self.tempWildMon
  self.tempWildMon = nil
  if pending then return pending end
  local tables = self:wildTables()
  local collision = map:cellCollision(self.player.cellX, self.player.cellY)
  local onWater = FieldMoves.encounterTable(collision) == "water"
  -- kind "script": a `randomwildmon` the VM asked for, not a step's roll.
  local roll = self:rollEncounter("script", onWater and "water" or "grass",
    tables, onWater and rollWaterVanilla or rollGrassVanilla)
  if not roll then return nil end
  -- The encounter tables name a species by ID; a `loadwildmon` pair is a
  -- SPECIES INDEX, and startScriptedBattle reads the index, so the roll is
  -- translated here rather than at the battle seam.
  local pokemon = self.game and self.game.data and self.game.data.pokemon
  local def = pokemon and pokemon[roll.species]
  if not (def and def.index) then return nil end
  return { species = def.index, level = roll.level }
end

-- GetMapMusic (home/map.asm:2550)
function World.mapMusicLabel(audio, musicByte, rocketsMahogany, rocketsRadioTower)
  if type(musicByte) ~= "number" then return nil end
  local MUSIC_MAHOGANY_MART = 100 -- constants/music_constants.asm:100
  local RADIO_TOWER_MUSIC = 0x80 -- constants/music_constants.asm:109
  local order = audio and audio.musicOrder
  local songs = audio and audio.songs
  local label
  if musicByte == MUSIC_MAHOGANY_MART then
    label = rocketsMahogany and "Music_RocketHideout" or "Music_CherrygroveCity"
  elseif musicByte >= RADIO_TOWER_MUSIC then
    label = rocketsRadioTower and "Music_RocketTheme"
      or (order and order[(musicByte - RADIO_TOWER_MUSIC) + 1])
  else
    return nil
  end
  if label and label ~= "Music_Nothing" and songs and songs[label] then
    return label
  end
  return nil
end

function World:mapMusicSong(mapId)
  local audio = self.game and self.game.data and self.game.data.audio
  local def = self.maps and self.maps[mapId]
  -- ENGINE_ROCKETS_IN_MAHOGANY / _RADIO_TOWER (data/events/engine_flags.asm:40,:36)
  return World.mapMusicLabel(audio, def and def.music,
    self:engineFlag(22), self:engineFlag(18))
end

function World:playMapMusic()
  local data = self.game and self.game.data
  if data and data.audio and data.audio.runtime and self.map then
    -- SpecialMapMusic (home/audio.asm:397)
    Music.playMap(data, self.map.id, nil,
                  FieldMoves.isSurfing(self.playerState), nil,
                  self:mapMusicSong(self.map.id))
  end
end

-- RestartMapMusic, which replays wMapMusic -- and wMapMusic is MUSIC_BICYCLE
-- for as long as the player is riding (.GetOnBike writes it there).  So a
-- battle, a hatch or a menu that owned the sound gives the BIKE theme back,
-- not the map's own song.
function World:restoreMapMusic()
  local data = self.game and self.game.data
  if not data then return end
  if FieldMoves.isBiking(self.playerState) and self:playBikeMusic() then
    return
  end
  Music.restoreMap(data)
end

-- ForceMapMusic (engine/overworld/map_setup.asm:201), the music row every
-- MapSetupScript_ReloadMap ends on (data/maps/setup_scripts.asm:136), and
-- TryRestartMapMusic (home/audio.asm:366) under it.  wDontPlayMapMusicOnReload
-- is consumed HERE, at the reload, not at the end of the battle in front of it:
-- every scripted battle is written `startbattle / dontrestartmapmusic /
-- reloadmap` (maps/CherrygroveCity.asm:124), so the flag is not even set yet
-- while the battle screen is closing.  Set, the cart plays MUSIC_NONE, zeroes
-- wMapMusic and clears the flag; that zeroed wMapMusic is why the theme does
-- not creep back on the next restore either.
function World:forceMapMusic()
  if self.dontRestartMusic then
    self.dontRestartMusic = false
    Music.setMapSong(nil) -- `xor a / ld [wMapMusic], a`
    Music.stop()
    return
  end
  self:restoreMapMusic()
end

-- Script_musicfadeout: the ramp, and then the song underneath it.  The VM has
-- already masked MUSIC_FADE_IN_F off the control byte, so `fade` is the number
-- of frames the ramp holds each volume step; a musicId of 0 (MUSIC_NONE) is a
-- fade to silence and queues nothing.
--
-- Music.fadeOut steps rAUDVOL's level 7 -> 0 one notch every `control` frames
-- and stops the song at the bottom, so the queued label starts control * 7
-- frames later.  Counted here rather than polled, because Music keeps its ramp
-- state module-local.
function World:fadeOutMusic(musicId, fadeControl)
  local control = math.max(1, fadeControl or 10)
  Music.fadeOut(control)
  local data = self.game and self.game.data
  local audio = data and data.audio
  local order = audio and audio.musicOrder
  local name = order and order[(musicId or 0) + 1]
  if name and name ~= "Music_Nothing" and audio.songs and audio.songs[name] then
    self.pendingMusic = { name = name, left = control * 7 }
  else
    self.pendingMusic = nil
  end
end

-- The fade's tail, ticked from World:step: the queued song starts the frame the
-- ramp reaches the bottom, which is what makes a `musicfadeout` read as one
-- cross-fade rather than as a cut.
function World:updateMusicFade()
  local pending = self.pendingMusic
  if not pending then return end
  pending.left = pending.left - 1
  if pending.left > 0 then return end
  self.pendingMusic = nil
  local data = self.game and self.game.data
  if data then
    Music.play(data, pending.name, true, { reason = "script_fadeout" })
  end
end

-- `checkitem` and `takeitem`, over the same Bag the PACK reads.
function World:itemIdByIndex(itemIndex)
  local items = self.game and self.game.data and self.game.data.items
  return (itemByIndex(items, itemIndex))
end

function World:hasItem(itemIndex)
  local save = self.game and self.game.save
  local id = self:itemIdByIndex(itemIndex)
  if not (save and id) then return false end
  return (save.inventory and (save.inventory[id] or 0) > 0) or false
end

function World:takeItem(itemIndex, qty)
  local save = self.game and self.game.save
  local id = self:itemIdByIndex(itemIndex)
  if not (save and id) then return false end
  save.inventory = save.inventory or {}
  local have = save.inventory[id] or 0
  qty = qty or 1
  -- TossItem takes nothing at all when the pack holds fewer than asked.
  if have < qty then return false end
  local left = have - qty
  save.inventory[id] = left > 0 and left or nil
  return true
end

-- YOUR_MONEY 0 / MOMS_MONEY 1 (constants/script_constants.asm).  The VM does
-- the 0..999999 clamp; this is only where the number lives.
function World:money(account)
  local save = self.game and self.game.save
  if not save then return 0 end
  if (account or 0) == 1 then
    return (save.mom and save.mom.savedMoney) or 0
  end
  return (save.player and save.player.money) or 0
end

function World:setMoney(account, value)
  local save = self.game and self.game.save
  if not save then return end
  if (account or 0) == 1 then
    save.mom = save.mom or {}
    save.mom.savedMoney = value or 0
    return
  end
  save.player = save.player or {}
  save.player.money = value or 0
end

function World:coins()
  local save = self.game and self.game.save
  return (save and save.player and save.player.coins) or 0
end

function World:setCoins(value)
  local save = self.game and self.game.save
  if not save then return end
  save.player = save.player or {}
  save.player.coins = value or 0
end

-- `checkpoke`: the PARTY only.  CheckPartyOrBoxMon is a different routine and
-- no script calls it.
function World:hasPoke(speciesIndex)
  local save = self.game and self.game.save
  local id = speciesByIndex(
    self.game and self.game.data and self.game.data.pokemon, speciesIndex)
  if not (save and id) then return false end
  for _, mon in ipairs(save.party or {}) do
    if mon.species == id then return true end
  end
  return false
end

-- `giveegg`: the same builder every other party member goes through, marked
-- and counted down the way src/core/gen2/Breeding.lua marks a Day-Care egg, so
-- the ODD_EGG and the Togepi egg hatch through DoEggStep like any other.
-- False when the party is full; the VM turns true into wScriptVar = 2.
function World:giveEgg(speciesIndex, level)
  local Breeding = require("src.core.gen2.Breeding")
  local data = self.game and self.game.data
  local save = self.game and self.game.save
  if not (data and save) then return false end
  save.party = save.party or {}
  if #save.party >= Breeding.PARTY_SIZE then return false end
  local id, def = speciesByIndex(data.pokemon, speciesIndex)
  if not id then return false end
  local mon = Mon.new(data, id, level or Breeding.EGG_LEVEL)
  if not mon then return false end
  mon.isEgg = true
  -- `ld de, String_Egg / call CopyName2`: the slot's nickname IS "EGG", and the
  -- box list prints it verbatim (engine/pokemon/move_mon.asm:1193-1194, :1220).
  mon.nickname = Breeding.EGG_NAME
  -- DayCare_InitBreeding's `ld [hl], EGG_STEPS`: the counter is the species'
  -- own eggSteps in 256-step cycles, and DayCare_GiveEgg zeroes the HP.
  mon.eggSteps = (def and def.eggSteps) or 0
  mon.hp = 0
  -- GiveEgg goes through TryAddMonToParty too (move_mon.asm:1121-1139).
  Mon.stampOT(save, mon)
  save.party[#save.party + 1] = mon
  return true
end

-- `landmarktotext`: the town-map name of the map the player is on, newline and
-- all (landmarks.lua keeps the cart's own two-line names).
function World:landmarkName()
  local id = self:currentLandmarkId()
  local entry = id and self.landmarks and self.landmarks.landmarks
    and self.landmarks.landmarks[id]
  return (entry and entry.name) or nil
end

-- The fruit trees.  data/items/fruit_trees.asm (FruitTreeItems, one byte per
-- FRUITTREE_*) is NOT extracted -- nothing in the ROM's bytecode points at it,
-- the same reason FruitTreeScript itself had to be transcribed into the VM --
-- so the table lives in src/core/gen2/Apricorns.lua beside the seven apricorn
-- trees it feeds, and this is the half that turns its item ids into the
-- indices the script side speaks in.
--
-- Which trees have been picked is per-day state on the save, and it is
-- Apricorns.checkDailyResetTimer (World:checkTimeEvents) that clears
-- ENGINE_ALL_FRUIT_TREES overnight so TryResetFruitTrees will refill them.
function World:fruitTreeItem(treeId)
  -- FRUITTREE_* is 1-based (`const_def 1`), which is also how a Lua array
  -- indexes, so the id needs no shift: GetCurTreeFruit's `dec a` is the cart
  -- converting the same id into a 0-based offset.
  local id = Apricorns.treeFruit(treeId)
  local items = self.game and self.game.data and self.game.data.items
  local def = id and items and items[id]
  return (def and def.index) or 0
end

-- callasm TryResetFruitTrees, at the top of FruitTreeScript: the FIRST tree
-- examined after the daily rollover refills every tree in the game at once.
function World:fruitTreeReset()
  local save = self.game and self.game.save
  if not save then return false end
  return Apricorns.tryResetFruitTrees(save)
end

function World:fruitTreePicked(treeId)
  local save = self.game and self.game.save
  return save and Apricorns.treePicked(save, treeId) or false
end

function World:fruitTreePick(treeId)
  local save = self.game and self.game.save
  if not (save and treeId) then return end
  Apricorns.pickTree(save, treeId)
end

-- `askforphonenumber`.  Phone.addContact is the whole rule: _CheckCellNum runs
-- first and returns the same carry for "already stored" as for "full", so both
-- refusals come back as false here.
function World:addPhoneNumber(contact)
  local Phone = require("src.core.gen2.Phone")
  local save = self.game and self.game.save
  if not (save and contact) then return false end
  if Phone.hasContact(save, contact) then return false end
  return Phone.addContact(save, contact) and true or false
end

-- `specialphonecall` / `checkphonecall`: wSpecialPhoneCallID, which the next
-- Phone.checkSpecialCall consumes.
function World:setSpecialCall(id)
  local Phone = require("src.core.gen2.Phone")
  local save = self.game and self.game.save
  if not save then return end
  if (id or 0) == Phone.SPECIALCALL_NONE then
    Phone.clearSpecialCall(save)
  else
    Phone.queueSpecialCall(save, id)
  end
end

function World:specialCall()
  local Phone = require("src.core.gen2.Phone")
  local save = self.game and self.game.save
  return save and Phone.specialCallVar(save) or 0
end

-- ---- the specials' world half ----------------------------------------------
--
-- data/events/special_pointers.asm is 112 routines and most of them are one
-- reach into the world apiece, so they share one table rather than one `xFn`
-- field on the VM each.  src/script/gen2/Specials.lua is the other half: every
-- handler there is the cart routine, and everything it cannot do without the
-- game (a screen, the save, the party) is a call into here.

-- FadeToMenu / ExitAllMenus wrap a dozen specials.  A screen id that is not
-- registered in src/ui/Screens.lua yet must not take the game down with it, so
-- every push goes through here: an unknown id is a no-op that answers false,
-- and the special's own degrade takes over.
function World:pushScreen(id, opts)
  local game = self.game
  if not (game and game.stack) then return false end
  local ok = pcall(Screens.push, game, id, opts)
  return ok
end

-- SelectMonFromParty (engine/pokemon/party_menu.asm), the one blocking piece a
-- dozen specials share: BillsGrandfather, the two haircut brothers, Daisy,
-- CheckMagikarpLength, ReturnShuckie and the move deleter all open the same
-- list and all read wCurPartySpecies out of it.  `onDone(index, mon)` with nil
-- for the B press, exactly the shape the ASM's carry flag has.
function World:selectPartyMon(prompt, onDone)
  local game = self.game
  local save = game and game.save
  if not (game and game.stack and save and save.party and #save.party > 0) then
    if onDone then onDone(nil) end
    return false
  end
  local finished = false
  local function finish(index, mon)
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone(index, mon) end
  end
  local ok = self:pushScreen("Gen2PartyMenu", {
    save = save,
    party = save.party,
    prompt = prompt or "choose",
    onChoose = function(index, mon) finish(index, mon) end,
    onCancel = function() finish(nil, nil) end,
  })
  if not ok then
    if onDone then onDone(nil) end
    return false
  end
  return true
end

-- GivePokeMail (engine/pokemon/mail.asm), the `givepokemail` opcode's body:
-- the letter behind the script's pointer is hung on the LAST party member, the
-- one the `givepoke` immediately before it just added.  One call site in the
-- whole game -- RandyScript in maps/Route35GoldenrodGate.asm, KENYA's
-- FLOWER_MAIL -- and the extractor resolves the operand into
-- { item = "FLOWER_MAIL", message = "..." } (RomExtractorGen2).
--
-- A cache built before that resolution leaves the raw pointer word instead;
-- there is no way to invent the item or the message from a number, so nothing
-- is given rather than a blank letter being hung on the mon.
function World:givePokeMail(mail)
  local save = self.game and self.game.save
  if not (save and type(mail) == "table" and mail.item) then return false end
  return Mail.give(save, mail.item, mail.message)
end

-- CheckPokeMail (engine/pokemon/mail.asm): the party list, then the five-way
-- answer, then -- on POKEMAIL_CORRECT only -- the mon leaving the party for
-- good.  The rules are src/core/gen2/Mail.lua; this is the list and the
-- wScriptVar the VM parks on.
--
-- The one call site is Route31MailRecipientScript, whose `ifequal` ladder
-- covers all five values, so answering the wrong one picks a random branch of
-- somebody's quest.  Backing out of the list is REFUSED and an unresolved
-- expected message is WRONG_MAIL: both leave the mon exactly where it was.
function World:checkPokeMail(mail, onDone)
  local save = self.game and self.game.save
  local expected = (type(mail) == "table") and mail.message or nil
  -- selectPartyMon answers onDone(nil) AND returns false when it cannot open a
  -- list at all, so the resume is guarded: a second one would drive the script
  -- coroutine twice off one opcode.
  local answered = false
  local function answer(value)
    if answered then return end
    answered = true
    if onDone then onDone(value) end
  end
  if not save then return answer(Mail.POKEMAIL_REFUSED) end
  local ok = self:selectPartyMon("choose", function(index)
    answer(Mail.checkPokeMail(save, index, expected))
  end)
  if not ok then answer(Mail.POKEMAIL_REFUSED) end
end

-- The Day-Care conversation, all three doors of it.  The model is
-- src/core/gen2/Breeding.lua and the screen is src/ui/gen2/DayCareMenu.lua;
-- this is only the push, and the scriptVar the outside man's branch answers
-- with (TRUE = "no room, come back") rides back through onDone.
function World:dayCare(side, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone(0) end
    return false
  end
  local finished = false
  local function finish(scriptVar)
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone(scriptVar or 0) end
  end
  local ok = self:pushScreen("Gen2DayCareMenu", {
    save = game.save,
    side = side,
    -- text.lua carries the whole Day-Care block, seeded by name.
    text = self.text,
    onClose = finish,
  })
  if not ok then
    if onDone then onDone(0) end
    return false
  end
  return true
end

-- ChooseMoveToDelete (engine/pokemon/mon_menu.asm), the move-list half of the
-- Blackthorn move deleter (src/script/gen2/Specials.lua H.MoveDeletion).  The
-- caller has already refused a mon with only one move, so this only has to
-- put the list up and hand back a 1-based slot or nil for B.
function World:chooseMoveToDelete(mon, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone(nil) end
    return false
  end
  local finished = false
  local function finish(index)
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone(index) end
  end
  local ok = self:pushScreen("Gen2MoveDeleter", {
    mon = mon,
    moves = game.data and game.data.moves,
    onChoose = function(index) finish(index) end,
    onCancel = function() finish(nil) end,
  })
  if not ok then
    if onDone then onDone(nil) end
    return false
  end
  return true
end

-- Mom_SetUpWithdrawMenu / Mom_SetUpDepositMenu / Mom_WithdrawDepositMenuJoypad
-- (engine/events/mom.asm), the six-digit money keypad BankOfMom's GET and SAVE
-- both put up.  `kind` is "deposit" or "withdraw", only for the screen's own
-- DEPOSIT@/WITHDRAW@ label; `onDone(amount)` gets the typed 0..999999 or nil
-- for B, and H.BankOfMom (src/script/gen2/Specials.lua) is what turns that
-- into an actual GiveMoney/TakeMoney pair against the two accounts.
function World:bankOfMomAmount(kind, saved, held, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone(nil) end
    return false
  end
  local finished = false
  local function finish(amount)
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone(amount) end
  end
  local ok = self:pushScreen("Gen2BankOfMom", {
    kind = kind,
    saved = saved,
    held = held,
    onDone = function(amount) finish(amount) end,
    onCancel = function() finish(nil) end,
  })
  if not ok then
    if onDone then onDone(nil) end
    return false
  end
  return true
end

-- The rename half of the Goldenrod NAME RATER (engine/events/name_rater.asm,
-- src/script/gen2/Specials.lua H.NameRater).  Same keyboard World:nameHatchling
-- opens for a freshly-hatched egg, but the header is the species name loaded
-- by GetBaseData (`ld b, NAME_MON / ld de, wStringBuffer2 / farcall
-- _NamingScreen`), not a fixed prompt -- BoxMenu:askNickname's screen is the
-- same shape for the same reason.  `onDone(name)` gets the typed string or nil
-- for B; IsNewNameEmpty/CompareNewToOld both live in the special, not here.
-- SetDayOfWeek's wheel (src/ui/gen2/InitClock.lua day mode).  `onDone(day)` is
-- the special's own resume, the same shape World:nameRival hands H.NameRival:
-- the screen's close is what starts the script again.
function World:setDayOfWeek(onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone(nil) end
    return false
  end
  local ok = self:pushScreen("Gen2InitClock", {
    mode = "day",
    save = game.save,
    onDone = function(day)
      game.stack:pop()
      if onDone then onDone(day) end
    end,
  })
  if not ok and onDone then onDone(nil) end
  return ok
end

-- `opts.blank` is the fresh-catch entry: GiveANickname_YesNo's keyboard opens
-- empty (wMonOrItemNameBuffer holds the species name for InitNickname to copy
-- back, it is not typed into the field), where the Name Rater's opens on the
-- name it is replacing.
function World:renameMon(mon, onDone, opts)
  local game = self.game
  if not (game and game.stack and mon) then
    if onDone then onDone(nil) end
    return false
  end
  local finished = false
  local function finish(name)
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone(name) end
  end
  local ok = self:pushScreen("Gen2NamingScreen", {
    type = "nickname",
    monName = mon.name or mon.species,
    initial = (opts and opts.blank) and ""
      or (mon.nickname or mon.name or mon.species or ""),
    onDone = function(name) finish(name) end,
    onCancel = function() finish(nil) end,
  })
  if not ok then
    if onDone then onDone(nil) end
    return false
  end
  return true
end

-- The #DEX-completion diploma (engine/events/diploma.asm, src/ui/gen2/
-- Diploma.lua, src/script/gen2/Specials.lua H.Diploma).  `special Diploma`
-- itself never writes wScriptVar, so `onDone` here takes no argument -- it is
-- only the "the player pressed A or B, close and carry on" signal the
-- coroutine in Specials.block is parked on.
function World:showDiploma(onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone() end
    return false
  end
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone() end
  end
  local ok = self:pushScreen("Gen2Diploma", {
    playerName = game.save and game.save.player and game.save.player.name,
    onClose = finish,
  })
  if not ok then
    if onDone then onDone() end
    return false
  end
  return true
end

-- The Magnet Train ride (engine/events/magnet_train.asm, src/core/gen2/
-- MagnetTrain.lua, src/ui/gen2/MagnetTrainRide.lua, src/script/gen2/
-- Specials.lua H.MagnetTrain).  `special MagnetTrain` never writes wScriptVar
-- -- it READS the one the officer's `setval` left there -- so `onDone` takes
-- no argument and is only the "the cutscene reached JUMPTABLE_EXIT" signal the
-- coroutine in Specials.block is parked on.  The `warpcheck` and the
-- `newloadmap MAPSETUP.TRAIN` that follow it are the script's, not this.
function World:magnetTrain(toGoldenrod, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone() end
    return false
  end
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone() end
  end
  local ok = self:pushScreen("Gen2MagnetTrainRide", {
    toGoldenrod = toGoldenrod,
    onDone = finish,
  })
  if not ok then
    if onDone then onDone() end
    return false
  end
  return true
end

-- The Cianwood photo studio's portrait card (engine/printer/print_party.asm
-- PrintPartyMonPage1, src/ui/gen2/PhotoStudio.lua, src/script/gen2/
-- Specials.lua H.PhotoStudio).  `onDone` takes no argument, the same as
-- showDiploma above -- it is only the "player pressed A or B, close and
-- carry on" signal Specials.block is parked on.
function World:showPhotoStudio(mon, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone() end
    return false
  end
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone() end
  end
  local ok = self:pushScreen("Gen2PhotoStudio", {
    mon = mon,
    playerName = game.save and game.save.player and game.save.player.name,
    onClose = finish,
  })
  if not ok then
    if onDone then onDone() end
    return false
  end
  return true
end

-- The ALPH RUINS STAMP viewer (engine/events/print_unown.asm _UnownPrinter,
-- src/ui/gen2/UnownPrinter.lua, src/script/gen2/Specials.lua
-- H.UnownPrinter).  Same shape as showPhotoStudio above, and for the same
-- reason: the screen is the whole special, and `onDone` is only the "B was
-- pressed, close and carry on" signal Specials.block is parked on.
function World:showUnownPrinter(onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone() end
    return false
  end
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone() end
  end
  local ok = self:pushScreen("Gen2UnownPrinter", { onClose = finish })
  if not ok then
    if onDone then onDone() end
    return false
  end
  return true
end

-- PostCreditsSpawn (engine/menus/intro_menu.asm): read wSpawnAfterChampion,
-- clear it, and answer the spawn point CONTINUE warps to instead of the saved
-- position -- SPAWN_NEW_BARK after the Elite Four, SPAWN_MT_SILVER after Red.
-- HallOfFame.consumePostGameSpawn owns the byte and the mapping; this half
-- resolves the SPAWN_* row against the extracted landmarks table, and answers
-- nil both for an ordinary continue and for a cache whose spawn cannot be
-- found, which leaves the saved position in charge exactly as `xor a` does.
function World:consumePostGameSpawn()
  local save = self.game and self.game.save
  local spawnId = HallOfFame.consumePostGameSpawn(save)
  if not spawnId then return nil end
  local spawn = self.landmarks and self.landmarks.spawns
    and self.landmarks.spawns[spawnId]
  if not (spawn and spawn.map and self.maps and self.maps[spawn.map]) then
    return nil
  end
  return spawn
end

-- `halloffame` ($9f) -> Script_halloffame (engine/overworld/scripting.asm),
-- which stops the game timer and farcalls HallOfFame
-- (engine/events/halloffame.asm).  That routine is TWO screens, not one:
--
--   ld a, [wStatusFlags]   ; the PRE-induction flags
--   push af
--   ...set STATUSFLAGS_HALL_OF_FAME_F, bump the count, SaveGameData,
--      GetHallOfFameParty, AddHallOfFameEntry...
--   call AnimateHallOfFame
--   pop af
--   jp Credits
--
-- so the roster ceremony runs and then falls straight into the credits, and
-- the `a` Credits receives is the copy pushed BEFORE the bit was set.  Credits
-- reads exactly that bit (`bit STATUSFLAGS_HALL_OF_FAME_F, b`) to decide
-- ALLOW_SKIPPING_CREDITS_F, which is why a first-time champion has to sit
-- through the roll and a repeat one can hold B: the answer has to be sampled
-- before the induction or every champion after the first would look like the
-- first.  HallOfFame.induct returns that pre-value second for this reason.
--
-- The save really does happen inside the ceremony (farcall SaveGameData), so
-- it goes through the same writer SaveMenu uses rather than waiting for the
-- player to save afterwards.
function World:hallOfFame(onDone)
  local game = self.game
  local save = game and game.save
  if not (game and game.stack and save) then
    if onDone then onDone() end
    return false
  end

  -- SaveGameData saves the whole of sPlayerData, not just the roster, so the
  -- live world has to be folded in first: wEventFlags, the w<Map>SceneID block
  -- and wPlayerState are read back by World:loadPlayerData, and a write that
  -- skipped the snapshot would hand the next CONTINUE the flags of whenever
  -- the player last stood in front of a SAVE menu.
  local _, wasEntered = HallOfFame.induct(save, save.party, {
    saveFn = function(data)
      if game.snapshotSave then pcall(game.snapshotSave, game) end
      pcall(Gen2Save.save, data)
    end,
  })

  local finished = false
  local function finish()
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone() end
    -- ReturnFromCredits (engine/overworld/scripting.asm) is Script_endall
    -- plus MAPSTATUS_DONE: the script and the overworld loop both end.  And
    -- FinishContinueFunction (engine/menus/intro_menu.asm) answers anything
    -- but SPAWN_RED in wSpawnAfterChampion with `jp Reset`, so the champion's
    -- credits end on the title screen -- the induction's own SaveGameData is
    -- already on disk with SPAWN_LANCE in it, and the next CONTINUE spawns at
    -- New Bark Town through World:consumePostGameSpawn.
    if game.returnToTitle then game:returnToTitle() end
  end

  -- `pop af / jp Credits`: the roll follows the ceremony on the same call, and
  -- only the credits' own end returns to the script.
  local function toCredits()
    game.stack:pop()
    local ok = self:pushScreen("Gen2Credits", {
      allowSkip = wasEntered,
      onDone = finish,
    })
    if not ok then finished = true if onDone then onDone() end end
  end

  local ok = self:pushScreen("Gen2HallOfFame", {
    save = save,
    mode = "induct",
    -- text.lua carries the three header strings the extractor seeds by name.
    text = self.text,
    onDone = toCredits,
  })
  if not ok then
    if onDone then onDone() end
    return false
  end
  return true
end

-- `credits` ($a0) -> Script_credits, a bare `farcall RedCredits`.  RedCredits
-- is the post-Red roll and skips the ceremony entirely: it fades to white,
-- sets SPAWN_RED (not SPAWN_LANCE, which is the whole difference between the
-- two endings' CONTINUE) and reaches Credits with `ld a, [wStatusFlags]` read
-- LIVE.  Anyone who has beaten Red has necessarily entered the Hall of Fame
-- already, so that live read is why this roll is always skippable while the
-- champion's first one is not.
function World:credits(onDone)
  local game = self.game
  local save = game and game.save
  if not (game and game.stack) then
    if onDone then onDone() end
    return false
  end
  HallOfFame.markRedCredits(save)
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone() end
    -- FinishContinueFunction's .AfterRed (engine/menus/intro_menu.asm):
    -- SPAWN_RED is the one wSpawnAfterChampion value that does not `jp
    -- Reset`.  SpawnAfterRed writes wDefaultSpawnpoint = SPAWN_MT_SILVER,
    -- PostCreditsSpawn clears the byte, and the loop re-enters the overworld
    -- through MAPSETUP.WARP -- play resumes outside Silver Cave, in session,
    -- with no trip through the title screen.
    local spawn = self:consumePostGameSpawn()
    if spawn then
      self:runMapSetup(MAPSETUP.WARP, function()
        return self:setMap(spawn.map, spawn.x, spawn.y, "down")
      end)
    end
  end
  local ok = self:pushScreen("Gen2Credits", {
    allowSkip = HallOfFame.hasEntered(save),
    onDone = finish,
  })
  if not ok then
    if onDone then onDone() end
    return false
  end
  return true
end

-- The two Game Corner machines.  Both are StartGameCornerGame, which is
-- CheckCoinsAndCoinCase and then the game itself; the coin-case refusal is
-- transcribed in Specials because it prints text the VM already knows how to
-- show, so this is only the push.
function World:gameCornerGame(kind, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone() end
    return false
  end
  local id = (kind == "cardflip") and "Gen2CardFlip" or "Gen2SlotMachine"
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone() end
  end
  local ok = self:pushScreen(id, { save = game.save, onClose = finish })
  if not ok then
    if onDone then onDone() end
    return false
  end
  return true
end

-- The Ruins of Alph sliding-panel puzzle.  `special UnownPuzzle` is
-- FadeToMenu / _UnownPuzzle / `ld a, [wSolvedUnownPuzzle] / ld [wScriptVar], a`
-- / ExitAllMenus, so the only thing this owes the script is the screen and the
-- one byte it answers with.
--
-- `puzzleId` is the UNOWNPUZZLE_* the chamber's `setval` parked in wScriptVar
-- just before the special, which is also what LoadUnownPuzzlePiecesGFX masks to
-- pick the picture.  A push that cannot happen answers "not solved" rather than
-- leaving the script parked forever.
function World:unownPuzzle(puzzleId, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone(false) end
    return false
  end
  local finished = false
  local function finish(solved)
    if finished then return end
    finished = true
    game.stack:pop()
    if onDone then onDone(solved and true or false) end
  end
  local ok = self:pushScreen("Gen2UnownPuzzle", {
    puzzle = puzzleId or 0,
    save = game.save,
    onClose = finish,
  })
  if not ok then
    if onDone then onDone(false) end
    return false
  end
  return true
end

-- SurfStartStep (engine/overworld/player_object.asm): the player goes into
-- PLAYER_SURF and takes one step forward onto the water.  Called by the
-- special rather than by the field move, because Script_UsedSurf's `special
-- SurfStartStep` is what actually puts them on the Lapras.
-- SurfStartStep (engine/overworld/player_object.asm) is the `special` half of
-- the same three lines World:runSurf runs when SURF is chosen from the party
-- menu: the state change, the map's surfing theme, and one scripted step off
-- the bank.  Script_UsedSurf calls it, so both routes have to land in the same
-- place -- if they did not, surfing from a script would leave the player
-- walking on water.
function World:surfStartStep(mon)
  local p = self.player
  if not p then return false end
  self:applyPlayerState(FieldMoves.surfType(mon))
  local audio = self.game and self.game.data and self.game.data.audio
  if audio and audio.runtime and self.map then
    -- SpecialMapMusic (home/audio.asm:397)
    Music.playMap(self.game.data, self.map.id, nil,
                  FieldMoves.isSurfing(self.playerState), nil,
                  self:mapMusicSong(self.map.id))
  end
  if p.scriptStep then p:scriptStep(p.facing) end
  self.fieldMove = { phase = "step" }
  return true
end

-- The eight ROM-0 presentation specials (FadeOutToWhite .. UpdatePlayerSprite).
-- None of them is state: they are the fade, the palette reload and the sprite
-- refresh a scripted cutscene brackets itself with.  The port has one map
-- image and rebuilds people from one list, so `sprites` and `palettes` are a
-- rebuild and a re-bake, and the fades are a flat overlay World:draw honours.
function World:screenFade(kind)
  -- kind: "outWhite" | "outBlack" | "inWhite" | "inBlack"
  if kind == "inWhite" or kind == "inBlack" then
    self.fade, self.fadeLevel = nil, nil
    return
  end
  self.fade = (kind == "outWhite") and "white" or "black"
  self.fadeLevel = 1
end

-- RunMapSetupScript (engine/overworld/map_setup.asm): every map entry runs one
-- of the eleven MapSetupScripts, and the load itself sits in the MIDDLE of it.
-- The port loads a map in a single World:setMap call, so what is left of the
-- script is the pair of fades it is wrapped in -- and running the load between
-- them rather than instead of them is the whole difference between a door that
-- opens and a cut.
--
-- The chain OWNS the frames it runs for: World:busy() is true throughout, which
-- is what stops a still-held direction from stepping the player on the far side
-- before the map's own deferred scene script gets to run.  On the cart that
-- falls out of the setup script being a blocking call inside the overworld
-- loop; here it has to be said out loud.
function World:runMapSetup(method, load)
  -- JumpRoamMons sits above the load in MapSetupScript_Teleport; UpdateRoamMons
  -- below it in _Connection and _Train.  Wrapping the load rather than editing
  -- setMap keeps both on the right side of it, and keeps the roam walk where
  -- the cart puts it -- in the setup SCRIPT, not in the map load.
  self:roamMonsBeforeLoad(method)
  local wrapped = function()
    local ok = load()
    self:roamMonsAfterLoad(method)
    return ok
  end
  if MAPSETUP_NO_FADE[method] then return wrapped() end
  if not MAPSETUP_FADE_OUT[method] then
    -- MAPSETUP.WARP and friends open on DisableLCD: the screen simply goes, and
    -- only the way back in is a fade.
    local ok = wrapped()
    self.fade, self.fadeLevel = "white", 1
    self.mapSetup = { phase = "in", step = FADE_STEPS, wait = FADE_STEP_FRAMES }
    return ok
  end
  self.mapSetup = {
    phase = "out", step = 0, wait = FADE_STEP_FRAMES, load = wrapped,
  }
  return true
end

-- ---------------------------------------------------------------------------
-- The three roaming beasts (engine/overworld/wildmons.asm).
-- ---------------------------------------------------------------------------
--
-- src/core/gen2/Roamers.lua is the whole model and the ONE writer of
-- save.roamers -- the walk, the encounter roll, the HP bank and the flee
-- tables.  Everything here is a call site, because until now there were none:
-- `special InitRoamMons` put the three structs on the save when the Burned
-- Tower floor gave way and then nothing ever moved them, rolled for them or
-- banked them, so a beast sat on its starting route forever and could not be
-- met even there.
--
-- The four sites are the four the cart has: two map setup commands, one gate at
-- the top of ChooseWildEncounter, and BattleEnd_HandleRoamMons.

-- Random(n) for the roam walk.  Injectable so a test and a driver can pin it;
-- nil means the ambient stream, which is what the game plays on.
function World:roamRandom()
  return self.roamerRandom
end

function World:roamMonsBeforeLoad(method)
  if not MAPSETUP_ROAM_JUMP[method] then return false end
  local save = self.game and self.game.save
  if not (save and Roamers.list(save)) then return false end
  -- The map the player is LEAVING: JumpRoamMons runs above the load.
  return Roamers.jumpAll(save, self.map and self.map.id, self:roamRandom(),
    self.encounters)
end

-- The CONTINUE menu's own `farcall JumpRoamMons`, which is not a map setup
-- script at all: it fires once per load of a save file, from World:load, with
-- no map yet built -- so the map the scatter avoids has to be passed in.
function World:roamMonsOnContinue(playerMapId)
  local save = self.game and self.game.save
  if not (save and Roamers.list(save)) then return false end
  return Roamers.jumpAll(save, playerMapId, self:roamRandom(), self.encounters)
end

function World:roamMonsAfterLoad(method)
  if not MAPSETUP_ROAM_UPDATE[method] then return false end
  local save = self.game and self.game.save
  if not (save and Roamers.list(save)) then return false end
  -- The map the player has ARRIVED on: UpdateRoamMons is the script's tail.
  return Roamers.update(save, self.map and self.map.id, self:roamRandom(),
    self.encounters)
end

-- BattleEnd_HandleRoamMons.  A roaming battle banks the beast's HP and moves
-- it (or clears the slot if it was caught or beaten); ANY other wild battle
-- takes the `.not_roaming` tail, which is a 1-in-16 roll that moves them all --
-- which is why the beasts drift while you grind, not only while you walk.
function World:roamMonsAfterBattle(roaming, outcome, enemyHp)
  local save = self.game and self.game.save
  if not (save and Roamers.list(save)) then return false end
  local mapId = self.map and self.map.id
  if roaming then
    return Roamers.endBattle(save, roaming, outcome, enemyHp, mapId,
      self:roamRandom(), self.encounters)
  end
  return Roamers.afterWildBattle(save, mapId, self:roamRandom(),
    self.encounters)
end

function World:updateMapSetup()
  local ms = self.mapSetup
  ms.wait = ms.wait - 1
  if ms.wait > 0 then return end
  ms.wait = FADE_STEP_FRAMES
  if ms.phase == "out" then
    ms.step = ms.step + 1
    self.fade, self.fadeLevel = "white", ms.step / FADE_STEPS
    -- FlyFromAnim carries the player up and off the map under the fade.  The
    -- bird's own frames are not in the cache, but the lift is: it is the same
    -- OBJECT_SPRITE_Y_OFFSET sine the teleport step type walks
    -- (src/script/gen2/Movement.lua), stepped over the fade's four levels.
    if ms.lift and self.player then
      self.player.spriteYOffset = Movement.teleportYOffset(
        Movement.TELEPORT_RISE_HEIGHT + ms.step * FADE_STEPS)
    end
    if ms.step >= FADE_STEPS then
      -- setMap clears self.fade (a map load repaints everything), so the sheet
      -- has to be re-armed at full strength on the far side for the fade in to
      -- take back down.
      ms.load()
      ms.phase = "in"
      self.fade, self.fadeLevel = "white", 1
    end
    return
  end
  ms.step = ms.step - 1
  -- FlyToAnim, the same curve read backwards: the player comes down onto the
  -- destination tile as the fade lets go of the screen.
  if ms.lift and self.player then
    self.player.spriteYOffset = Movement.teleportYOffset(
      Movement.TELEPORT_RISE_HEIGHT + ms.step * FADE_STEPS)
  end
  if ms.step <= 0 then
    self.fade, self.fadeLevel = nil, nil
    self.mapSetup = nil
    if ms.lift and self.player then self.player.spriteYOffset = 0 end
    return
  end
  self.fadeLevel = ms.step / FADE_STEPS
end

function World:reloadSprites(withPalettes)
  self:rebuildPeople({ seamless = true })
  if withPalettes ~= false then self:applyPalettes() end
end

-- Every hook Specials.lua may reach for, in one place so the module's whole
-- surface is readable at a glance and a test can stub it wholesale.
function World:specialHooks()
  return {
    world = self,
    healParty = function() self:healParty() end,
    warpToSpawn = function() self:warpToSpawn() end,
    openPc = function() self:openPc() end,
    -- _PlayersHousePC: the same screen with the DECORATION row, and an answer.
    playersHousePc = function(onDone)
      self:openPc({ house = true, onDone = onDone })
    end,
    toggleDecorationsVisibility = function()
      self:toggleDecorationsVisibility()
    end,
    toggleMaptileDecorations = function() self:toggleMaptileDecorations() end,
    nameRival = function(onDone) self:nameRival(onDone) end,
    playSfx = function(id) self:playSfx(id) end,
    -- The same sound by its pokegold LABEL, for a handler porting a `ld de,
    -- SFX_x / call PlaySFX` pair: the Gold sfx table is keyed by label, and an
    -- index written down in Lua is only right until the table moves.
    playSfxNamed = function(name, fallbackId)
      self:playSfxNamed(name, fallbackId)
    end,
    playCry = function(index) self:playCry(index) end,
    playMapMusic = function() self:playMapMusic() end,
    restartMapMusic = function() self:restoreMapMusic() end,
    fadeOutMusic = function() Music.fadeOut(2) end,
    stopMusic = function() Music.stop() end,
    currentMusic = function() return Music.current() end,
    fade = function(kind) self:screenFade(kind) end,
    reloadSprites = function(withPalettes) self:reloadSprites(withPalettes) end,
    updatePlayerSprite = function() self:applyPlayerState(self.playerState) end,
    surfStartStep = function(mon) return self:surfStartStep(mon) end,
    save = function() return self.game and self.game.save end,
    data = function() return self.game and self.game.data end,
    party = function()
      local save = self.game and self.game.save
      return (save and save.party) or {}
    end,
    playerCell = function()
      local p = self.player
      return p and p.cellX or 0, p and p.cellY or 0
    end,
    mapId = function() return self.map and self.map.id end,
    coins = function() return self:coins() end,
    setCoins = function(value) self:setCoins(value) end,
    money = function(account) return self:money(account) end,
    setMoney = function(account, value) self:setMoney(account, value) end,
    -- Mom_SetUpWithdrawMenu / Mom_SetUpDepositMenu's six-digit money keypad
    -- (src/script/gen2/Specials.lua H.BankOfMom).  `onDone` gets the typed
    -- amount or nil for B; the special itself owns the balance checks that
    -- follow, the same split ChooseMoveToDelete keeps with H.MoveDeletion.
    bankOfMomAmount = function(kind, saved, held, onDone)
      return self:bankOfMomAmount(kind, saved, held, onDone)
    end,
    hasItem = function(index) return self:hasItem(index) end,
    takeItem = function(index, qty) return self:takeItem(index, qty) end,
    engineFlag = function(flag) return self:engineFlag(flag) end,
    setEngineFlag = function(flag, v) self:setEngineFlag(flag, v) end,
    setSwarm = function(group, mapNum) self:setSwarm(group, mapNum) end,
    dayCare = function(side, onDone) self:dayCare(side, onDone) end,
    givePokeMail = function(mail) return self:givePokeMail(mail) end,
    checkPokeMail = function(mail, onDone) self:checkPokeMail(mail, onDone) end,
    gameCornerGame = function(kind, onDone)
      self:gameCornerGame(kind, onDone)
    end,
    unownPuzzle = function(puzzleId, onDone)
      self:unownPuzzle(puzzleId, onDone)
    end,
    selectPartyMon = function(prompt, onDone)
      self:selectPartyMon(prompt, onDone)
    end,
    chooseMoveToDelete = function(mon, onDone)
      self:chooseMoveToDelete(mon, onDone)
    end,
    renameMon = function(mon, onDone, opts)
      self:renameMon(mon, onDone, opts)
    end,
    setDayOfWeek = function(onDone) self:setDayOfWeek(onDone) end,
    showDiploma = function(onDone)
      self:showDiploma(onDone)
    end,
    showPhotoStudio = function(mon, onDone)
      self:showPhotoStudio(mon, onDone)
    end,
    showUnownPrinter = function(onDone)
      self:showUnownPrinter(onDone)
    end,
    magnetTrain = function(toGoldenrod, onDone)
      self:magnetTrain(toGoldenrod, onDone)
    end,
    pushScreen = function(id, opts) return self:pushScreen(id, opts) end,
    monName = function(index)
      local id, def = speciesByIndex(
        self.game and self.game.data and self.game.data.pokemon, index)
      return (def and def.name) or id
    end,
    monIndex = function(species)
      local pokemon = self.game and self.game.data and self.game.data.pokemon
      local def = pokemon and pokemon[species]
      return def and def.index or nil
    end,
    -- The item pair, the way monName / monIndex are the species pair: a
    -- handler that builds a menu needs the printed name, and one that leaves
    -- an item in wScriptVar needs the CONSTANT the following `ifequal` ladder
    -- compares against (Kurt's is `ifequal BLU_APRICORN`).
    itemName = function(id)
      local items = self.game and self.game.data and self.game.data.items
      local def = items and items[id]
      return (def and def.name) or id
    end,
    itemIndex = function(id)
      local items = self.game and self.game.data and self.game.data.items
      local def = items and items[id]
      return def and def.index or nil
    end,
    -- The same static menu `loadmenu` / `verticalmenu` opens, for the handlers
    -- whose menu is compiled into a routine instead of into a MenuHeader the
    -- extractor can follow (Kurt_SelectApricorn builds its rows at run time
    -- out of the pack).
    scriptMenu = function(header, onChoose)
      self:openScriptMenu(header, "vertical", onChoose)
    end,
    rareWildMon = function() return self:rareWildMon() end,
  }
end

-- RandomUnseenWildMon's lookup half.  The routine picks one of the THREE
-- RAREST grass slots on the map (`and %11 / jr z` rerolls 0, so it is slots 5,
-- 6 or 7 of the seven) and drops it if that species is also one of the FOUR
-- COMMONEST -- which is what stops the caller reporting a Rattata as a rarity.
-- The time of day picks which of the three lists is read, exactly as a step
-- would.
function World:rareWildMon()
  local map = self.map
  local entry = self.encounters and self.encounters.grass
    and map and self.encounters.grass[map.id]
  if not entry or not entry.slots then return nil end
  local key = self.tod or "DAY"
  local slots = entry.slots[key] or entry.slots.DAY
  if not slots then return nil end
  local rare = slots[4 + math.random(3)]
  if not (rare and rare.species) then return nil end
  for i = 1, 4 do
    local common = slots[i]
    if common and common.species == rare.species then return nil end
  end
  return rare.species
end

function World:objectEntity(objectId)
  if objectId == 0 then return self.player end
  -- object_const_def starts at 2; extracted objects are 1-based.
  local index = (objectId or 0) - 1
  if index < 1 then return self.talkNpc end
  for _, npc in ipairs(self.npcs) do
    if npc.def and npc.def.index == index then return npc end
  end
  return nil
end

function World:turnObject(objectId, facing)
  local ent = self:objectEntity(objectId)
  if ent and ent.scriptFace then ent:scriptFace(facing) end
end

function World:disappearObject(objectId)
  local index = (objectId or 0) - 1
  local def = self.map and self.map.def
  local obj = def and def.objects and def.objects[index]
  if not obj then return end
  -- Script_disappear does TWO separate stores, and only one of them is the
  -- flag.  DeleteObjectStruct -> MaskObject (home/map_objects.asm:347,
  -- home/map.asm:1542) writes the byte of wObjectMasks for THIS object and
  -- nothing else, which is what takes it off the map now; the flag
  -- ApplyEventActionAppearDisappear sets afterwards is only what the next
  -- LoadObjectMasks reads back at map load.  Objects sharing one
  -- MAPOBJECT_EVENT_FLAG are ordinary (maps/BurnedTowerB1F.asm:152 gives all
  -- three animated beasts EVENT_BURNED_TOWER_B1F_BEASTS_1 and jumps them away
  -- one at a time), so the mask is per object even when the flag is not.
  --
  -- ApplyEventActionAppearDisappear returns WITHOUT touching anything when the
  -- flag word is -1 ($ffff), and MaskObject has already pulled the struct by
  -- then -- so an object with no real flag still vanishes for the rest of the
  -- map's visit.  The port's Events:objectVisible reads $ffff as "always
  -- visible", so setting it would have been a no-op; the mask is what hides
  -- the flagless ones, and the next load re-derives every mask from the flags.
  if obj.eventFlag and obj.eventFlag ~= 0xFFFF then
    self.events:set(obj.eventFlag, true)
  end
  self:setObjectMask(obj, index, true)
  self:rebuildPeople({ seamless = true })
end

-- StartFollow: the follower's movement type becomes SPRITEMOVEDATA_FOLLOWING
-- and it walks the leader's own path one cell behind.  Only one pair exists at
-- a time (wObjectFollow_Leader / _Follower are single bytes), so a second
-- `follow` replaces the first.
function World:startFollow(leaderId, followerId)
  local leader = self:objectEntity(leaderId)
  local follower = self:objectEntity(followerId)
  if not (leader and follower) or leader == follower then
    self.followState = nil
    return
  end
  self.followState = { leader = leader, follower = follower }
end

function World:stopFollow()
  self.followState = nil
end

-- The leader has just committed to a step out of (fromX, fromY); the follower
-- takes that cell if it is standing next to it.  A follower that is somewhere
-- else entirely simply does not move, the way CheckObjectVisibility drops a
-- pairing it cannot make sense of.
function World:followStep(leader, fromX, fromY)
  local state = self.followState
  if not (state and state.leader == leader) then return end
  local follower = state.follower
  if not follower or follower.moving or not follower.scriptStep then return end
  local dx, dy = fromX - follower.cellX, fromY - follower.cellY
  local dir
  if dy == 0 and dx == 1 then dir = "right"
  elseif dy == 0 and dx == -1 then dir = "left"
  elseif dx == 0 and dy == 1 then dir = "down"
  elseif dx == 0 and dy == -1 then dir = "up" end
  if dir then follower:scriptStep(dir) end
end

-- FreezeAllObjects + the caller's `res FROZEN_F` on the moved one
-- (engine/overworld/map_objects.asm FreezeAllOtherObjects, :2529-2544), plus
-- UnfreezeFollowerObject (scripting.asm:758): a follower is walked by
-- World:followStep and must not be held.
--
-- The pool is walked rather than self.npcs because a rebuild mid-script can
-- leave an object in one list and not the other, which is the same pair
-- World:step's unfreeze walks.
function World:freezeAllOtherNpcs(objectId)
  local moved = self:objectEntity(objectId)
  local follower = self.followState and self.followState.follower
  local function hold(npc)
    if npc and npc ~= moved and npc ~= follower and npc ~= self.player then
      npc.frozen = true
    end
  end
  for _, npc in pairs(self.npcPool or {}) do hold(npc) end
  for _, npc in ipairs(self.npcs or {}) do hold(npc) end
end

function World:beginMovement(objectId, bytes, onDone)
  -- ApplyMovement's FIRST act, before it has even read the movement pointer:
  -- `ld a, c / farcall FreezeAllOtherObjects` (engine/overworld/scripting.asm
  -- :751-755).  FreezeAllObjects sets FROZEN_F on every struct and the caller
  -- then clears it on the one being moved (map_objects.asm:2529-2544), so from
  -- the first applymovement of a script until EndScript's UnfreezeAllObjects
  -- NOBODY on the map moves under their own movement function.
  --
  -- The port used to freeze only the object a command actually touched
  -- (NPC:scriptStep / :scriptFace set `frozen` themselves), so every OTHER
  -- wanderer and spinner kept going for the whole exchange: a beaten spinner
  -- carried on rolling new facings through his own after-battle text, and the
  -- Rocket hideout's spin trainers -- the ones whose facing is the puzzle --
  -- turned under every text box in the room.  SeenByTrainerScript's
  -- `applymovementlasttalked` (engine/events/trainer_scripts.asm:14) is the
  -- freeze that covers the seen text, the battle and the talk-after.
  --
  -- `frozeNpcs` is the release latch: World:step drops it the frame the whole
  -- interaction settles, which is where the cart runs UnfreezeAllObjects.
  self:freezeAllOtherNpcs(objectId)
  self.frozeNpcs = true
  self.moveState = {
    objectId = objectId,
    bytes = bytes or {},
    i = 1,
    sleep = 0,
    onDone = onDone,
  }
end

function World:updateMovement()
  local st = self.moveState
  if not st then return end
  local ent = self:objectEntity(st.objectId)
  if not ent then
    local cb = st.onDone
    self.moveState = nil
    if cb then cb() end
    return
  end
  if st.sleep and st.sleep > 0 then
    st.sleep = st.sleep - 1
    return
  end
  if ent.moving then return end
  -- StepFunction_NPCJump's `.Land` beat (engine/overworld/map_objects.asm:1150):
  -- `.Jump` already walked one cell and ran GetNextTile again, so the second
  -- cell belongs to the jump and not to the next movement byte.
  if st.pendingStep then
    local dir = st.pendingStep
    st.pendingStep = nil
    local fromX, fromY = ent.cellX, ent.cellY
    if ent:scriptStep(dir) then self:followStep(ent, fromX, fromY) end
    return
  end
  while st.i <= #st.bytes do
    local b = st.bytes[st.i]
    st.i = st.i + 1
    -- engine/overworld/movement.asm:163
    if b == 0x57 then
      local duration = st.bytes[st.i] or 0
      st.i = st.i + 1
      if ent.scriptRockSmash then
        ent:scriptRockSmash(duration)
      end
      st.sleep = duration
      return
    end
    local act = Movement.decodeByte(b)
    if act.kind == "end" then
      -- SLIDING_F is an object flag, not a stream one, so a stream that never
      -- ran remove_sliding would otherwise leave the object stuck holding its
      -- facing and step frame forever.
      ent.sliding = nil
      local cb = st.onDone
      self.moveState = nil
      if cb then cb() end
      return
    elseif act.kind == "turn" then
      ent:scriptFace(act.dir)
    elseif act.kind == "step" then
      local fromX, fromY = ent.cellX, ent.cellY
      if ent:scriptStep(act.dir) then
        self:followStep(ent, fromX, fromY)
      end
      return
    elseif act.kind == "jump" then
      -- JumpStep (engine/overworld/movement.asm:741) hands the object to
      -- StepFunction_NPCJump, which runs TWO beats and advances OBJECT_MAP_X/Y
      -- on each, so a jump crosses two cells.  No collision test: InitStep and
      -- GetNextTile only record the tile for the grass flag and never block
      -- scripted movement.
      local fromX, fromY = ent.cellX, ent.cellY
      if ent:scriptStep(act.dir) then
        st.pendingStep = act.dir
        self:followStep(ent, fromX, fromY)
      end
      return
    elseif act.kind == "sleep" then
      st.sleep = act.frames or 0
      return
    elseif act.kind == "teleport" then
      -- teleport_from / teleport_to hand the object to their own step type for
      -- a fixed number of frames (NPC:scriptTeleport); the movement stream
      -- waits them out on the same counter step_sleep uses.
      if ent.scriptTeleport then
        ent:scriptTeleport(act.mode, act.frames)
        st.sleep = act.frames or 0
      end
      return
    elseif act.kind == "sliding" then
      -- Movement_set_sliding / _remove_sliding (engine/overworld/movement.asm
      -- :353-363) toggle SLIDING_F; SetFacingStepAction and SetFacingBumpAction
      -- both bail to SetFacingCurrent while it is set
      -- (engine/overworld/map_object_action.asm:48, :74), so the object holds
      -- its facing AND its step frame for the whole stream.  Both handlers end
      -- in `jp ContinueReadingMovement`, so no frame is consumed and the next
      -- byte is read in this same pass: fall through the while loop.
      ent.sliding = act.on
    elseif act.kind == "fixfacing" then
      -- FIXED_FACING_F: InitStep jumps past the OBJECT_DIRECTION write
      -- (engine/overworld/map_objects.asm:284-294), so the object steps
      -- without turning.  ContinueReadingMovement again, so no frame here.
      ent.fixedFacing = act.fixed
    elseif act.kind == "treeshake" then
      -- Movement_tree_shake: 24 frames of STEP_TYPE_SLEEP with OBJECT_ACTION
      -- set to OBJECT_ACTION_WEIRD_TREE (engine/overworld/movement.asm:334).
      if ent.scriptTreeShake then
        ent:scriptTreeShake(act.frames)
        st.sleep = act.frames or 0
      end
      return
    end
  end
  -- A stream that walked off the end of its bytes without an `end` byte still
  -- has to drop SLIDING_F: the flag lives on the object, and leaving it set
  -- freezes that NPC's facing and step frame for the rest of the map.
  ent.sliding = nil
  local cb = st.onDone
  self.moveState = nil
  if cb then cb() end
end

function World:askYesNo(onChoose)
  local game = self.game
  if not (game and game.stack) then
    if onChoose then onChoose(true) end
    return
  end
  self.choicebox = true
  -- The box World:showText left standing because this very command was the next
  -- one in the list.  Handing it the shared TextBox's own `choice` hook is what
  -- puts the prompt over it: the stay latch has to come off first, since a
  -- staying box short-circuits before the choice branch (src/render/TextBox.lua
  -- :238).  Nothing is re-printed, so the page keeps the exact two lines it
  -- typed -- including a `cont`'s scrolled pair.
  local held = self.stayedTextBox
  if held then
    self.stayedTextBox = nil
    held.stay = nil
    held.choice = function(yes)
      self.textbox = nil
      self.choicebox = nil
      if onChoose then onChoose(yes) end
    end
    return
  end
  -- `yesorno` on the cart puts the YES/NO box ABOVE the text box that is
  -- still holding the question (InitYesNoTextBoxParameters); the port used to
  -- push a bare choice box, so the question vanished the moment the answer
  -- appeared.  The last page is re-shown instantly underneath and the shared
  -- TextBox's own `choice` hook stacks the prompt on it, which is the same
  -- pairing every Gen 1 prompt already uses.
  local question = self.lastText
  if question then
    game.stack:push(TextBox.new(game, question, nil, {
      instant = true,
      choice = function(yes)
        self.choicebox = nil
        if onChoose then onChoose(yes) end
      end,
    }))
    return
  end
  game.stack:push(ChoiceBox.new(game, function(yes)
    self.choicebox = nil
    if onChoose then onChoose(yes) end
  end))
end

-- engine/events/pokepic.asm:44-48 PokepicMenuHeader `menu_coords 6, 4, 14, 13`,
-- and PadFrontpic (engine/gfx/load_pics.asm:342) fitting 5x5/6x6 into the 7x7.
local POKEPIC = {
  left = 6, top = 4, w = 9, h = 10,
  pad = { [7] = { 0, 0 }, [6] = { 1, 1 }, [5] = { 1, 2 } },
}

function World:showPokePic(speciesIndex)
  local id, def = speciesByIndex(
    self.game and self.game.data and self.game.data.pokemon, speciesIndex)
  local path = def and def.spriteFront
  if not path then self.pokePic = nil return end
  local ok, img = pcall(Assets.image, path)
  self.pokePic = ok and img or nil
  self.pokePicName = id
  -- _CGB_Pokepic (engine/gfx/cgb_layouts.asm:744) fills the whole menu box with
  -- PAL_BG_GRAY, so the window is the map's grey ramp, not the mon's colors.
  local set = self.palettes and self.map and self.map.def
    and Palettes.bgSet(self.palettes, self.map.def, self.daytime or "DAY")
  self.pokePicColors = set and set[1] or nil
end

-- WaitButton (home/text.asm), which Script_waitbutton farcalls: hold the frame
-- until the player presses A or B.  Only the `waitbutton` under an open
-- `pokepic` window reaches here -- every other one follows a `writetext` whose
-- last page has already taken the press (src/script/gen2/Vm.lua) -- and it is
-- what puts the starter's pic on screen long enough to look at before the
-- yes/no (#911).
--
-- `fresh` skips the tick the wait was armed on.  Game2's fixed step reads
-- `wasPressed("a")` for World:interact ABOVE World:step, so the press that
-- opened the ball script is still this tick's edge when the poll first runs;
-- without the skip that single press would both raise the pic and dismiss it.
function World:waitForButton(done)
  self.waitButton = { done = done, fresh = true }
end

function World:pollWaitButton()
  local wb = self.waitButton
  if not wb then return end
  if wb.fresh then wb.fresh = false return end
  local input = self.game and self.game.input
  -- A headless build with no pad cannot answer, so it answers at once rather
  -- than parking the script forever.
  if input and not (input:wasPressed("a") or input:wasPressed("b")) then
    return
  end
  self.waitButton = nil
  if wb.done then wb.done() end
end

-- A step rolls for a wild encounter, using the map's own rate and the slot
-- list for the current time of day -- which is why the same patch of Route 29
-- gives Pidgey at 8am and Hoothoot at 8pm.
-- Returns true when a battle started, so the caller stops the step.
--
-- WHETHER a step may roll at all is CanEncounterWildMon
-- (engine/overworld/events.asm), and the port used to get that wrong in a way
-- that emptied whole dungeons: it asked only "is this tall grass or water",
-- while the cart SKIPS the grass array entirely on a CAVE or DUNGEON map and
-- lets any non-ice walkable tile roll.  Dark Cave and Union Cave gave zero
-- encounters because of it.  FieldMoves.canEncounterWildMon is the whole
-- routine, ice check and wildoff flag included.
--
-- WHICH list is rolled is a separate question with a separate answer:
-- ChooseWildEncounter (engine/overworld/wildmons.asm) reads CheckOnWater, the
-- PERMISSION of the tile underfoot.  So a surfing step in a cave rolls the
-- water list and a walking step on the same map rolls the grass one.
-- The wild pick, wrapped in encounter.roll (return nil to suppress, a table
-- without calling next_ to force) and then encounter.species (which transforms
-- a non-nil roll before the Unown and repel filters).  Same two names, same
-- order and same { species, level } shape as Gen 1.
--
-- ctx keeps Gen 1's mapId / terrain / rng and adds what a Gen 2 roll genuinely
-- depends on and Gen 1 has no equivalent of: `daytime` (grass slots are per
-- time of day), `environment` (a CAVE or DUNGEON encounters on every walkable
-- tile), `kind` -- which of Gold's roll paths this is: "wild", "contest" or
-- "script" -- and `tables`, the swarm-substituted lists the engine really
-- rolled from, so a mod sees the same table _SwarmWildmonCheck picked.
--
-- Not the per-step hot path Gen 1 guards: every caller is already past the
-- encounter-rate gate, so ctx is built once per encounter that actually
-- triggers and the wants check only skips the two chains.
function World:rollEncounter(kind, terrain, tables, vanilla)
  local map = self.map
  local ctx = {
    mapId = map and map.id,
    terrain = terrain,
    -- Same guard World:rockRandom uses: a headless suite has no love global.
    rng = (love and love.math and love.math.random) or math.random,
    kind = kind,
    daytime = self.tod,
    environment = map and map.def and map.def.environment,
    tables = tables,
    data = self.game and self.game.data,
  }
  if not (Runtime.wantsHook("encounter.roll")
          or Runtime.wantsHook("encounter.species")) then
    return vanilla(tables, ctx)
  end
  local enc = Runtime.call("encounter.roll", vanilla, tables, ctx)
  if enc then
    enc = Runtime.call("encounter.species", sameEncounter, enc, ctx)
  end
  return enc
end

-- ApplyMusicEffectOnEncounterRate (engine/overworld/wildmons.asm:233-248):
-- POKEMON MARCH and the RUINS OF ALPH station double the rate, POKEMON LULLABY
-- halves it.  It reads wMapMusic, so a radio station left playing counts.
local MUSIC_RATE = {
  Music_PokemonMarch = "double",
  Music_RuinsOfAlphRadio = "double",
  Music_PokemonLullaby = "half",
}

function World.musicEncounterRate(rate, song)
  local effect = rate and song and MUSIC_RATE[song]
  if not effect then return rate end
  -- `sla b` / `srl b`, so the double wraps at a byte like the cart's does.
  if effect == "half" then return math.floor(rate / 2) end
  return (rate * 2) % 256
end

function World:tryWildEncounter()
  local game, player, map = self.game, self.player, self.map
  if not (game and player and map and self.encounters) then return false end
  if self:wildCooldownStep() then return false end
  local save = game.save
  if not (save and save.party and #save.party > 0) then return false end
  local collision = map:cellCollision(player.cellX, player.cellY)
  local environment = map.def and map.def.environment
  if not FieldMoves.canEncounterWildMon(
      environment, collision, self.noWildEncounters) then
    return false
  end
  -- RandomEncounter's `bit STATUSFLAGS2_BUG_CONTEST_TIMER_F` gate sits between
  -- CanEncounterWildMon and TryWildEncounter, and it takes a WHOLE different
  -- path: the park's own table, its own two encounter rates, and no roamer
  -- check at all -- ChooseWildEncounter_BugContest never calls
  -- CheckEncounterRoamMon, which is why no beast can turn up in the contest.
  if BugContest.isActive(save) then
    return self:tryContestEncounter(collision)
  end
  -- TryWildEncounter's own order: `.EncounterRate` FIRST, and
  -- ChooseWildEncounter -- roamer check included -- only on a pass.  The port
  -- rolled for a beast above the rate gate, which on a 10 percent route made
  -- one turn up about ten times as often per grass step as the cart does.
  local tables = self:wildTables()
  local onWater = FieldMoves.encounterTable(collision) == "water"
  local rate
  if onWater then
    rate = Encounter.waterRate(tables, map.id)
  else
    -- engine/overworld/wildmons.asm:283
    rate = Encounter.grassRate(tables, map.id, self.tod)
  end
  -- ApplyMusicEffectOnEncounterRate runs first (wildmons.asm:213-215).
  rate = World.musicEncounterRate(rate, Music.mapSong())
  -- ApplyCleanseTagEffectOnEncounterRate (engine/overworld/wildmons.asm:250-267):
  -- one `srl b`, however many mons are holding one.
  for _, mon in ipairs(save.party or {}) do
    if rate and mon.item == "CLEANSE_TAG" then
      rate = math.floor(rate / 2)
      break
    end
  end
  if not Encounter.triggers(rate, nil) then return false end
  -- CheckEncounterRoamMon is the FIRST thing ChooseWildEncounter does, before
  -- it reaches for the map's own slot list -- so a beast REPLACES the map's
  -- encounter rather than adding to it, and only on a map that has a table at
  -- all (LoadWildMonDataPointer has already answered, which is what the
  -- `self.encounters` guard above is).  Roamers.checkEncounter refuses while
  -- surfing, which is what keeps Suicune out of the water.
  local met = Roamers.checkEncounter(save, map.id, onWater, self:roamRandom())
  if met then
    -- CheckEncounterRoamMon writes wCurPartyLevel like any other pick, so the
    -- repel filter below applies to a beast too: a level 41 lead repels it.
    if self:repelSuppresses(met.level) then return false end
    local beast = Roamers.beginBattle(save, met.index, game.data)
    if beast then
      save.pokedex = save.pokedex or { seen = {}, caught = {} }
      save.pokedex.seen[beast.species] = true
      self:startBattle({ wild = beast, roaming = met.index })
      return true
    end
  end
  local roll = self:rollEncounter("wild", onWater and "water" or "grass",
    tables, onWater and rollWaterVanilla or rollGrassVanilla)
  if not roll then return false end
  -- ChooseWildEncounter's Unown arm (engine/overworld/wildmons.asm): an UNOWN
  -- slot on a map whose puzzles are all unsolved is NO ENCOUNTER, not a
  -- different one -- `ld a, [wUnlockedUnowns] / and a / jr z, .nowildbattle`.
  -- That is what keeps the Ruins chambers empty until a wall has been solved.
  local monOpts = nil
  if roll.species == Unown.SPECIES then
    local flags = self:engineFlags()
    if not Unown.anyUnlocked(flags) then return false end
    -- LoadEnemyMon's .GenerateDVs loop rerolls until CheckUnownLetter clears
    -- the form, so a chamber only ever produces letters its own puzzle
    -- unlocked.
    monOpts = { dvs = Unown.wildDVs(flags, Mon.randomDVs) }
  end
  -- CheckRepelEffect, the last gate TryWildEncounter runs, and it runs AFTER
  -- the mon has been chosen -- which is why a repel filters on the level that
  -- was rolled rather than on anything about the map.
  if self:repelSuppresses(roll.level) then return false end
  local wild = Mon.new(game.data, roll.species, roll.level, monOpts)
  if not wild then return false end

  save.pokedex = save.pokedex or { seen = {}, caught = {} }
  save.pokedex.seen[roll.species] = true
  self:startBattle({ wild = wild })
  return true
end

-- CheckRepelEffect (engine/overworld/wildmons.asm).  With wRepelEffect
-- (save.repelSteps) still ticking, the chosen encounter is dropped when its
-- level is BELOW the first party member that is not fainted:
-- `ld a, [wCurPartyLevel] / cp [hl] / jr nc, .encounter` takes the encounter
-- on greater-or-equal, so a lead at the wilds' own level repels nothing.
--
-- The walk starts at wPartyMon1HP and skips every slot whose two HP bytes are
-- zero, so an EGG (DayCare_GiveEgg zeroes its HP) is never the mon a repel
-- measures against.  The counter is StepEvents.repelStep's; nothing here
-- touches it.
function World:repelSuppresses(level)
  local save = self.game and self.game.save
  if not save then return false end
  if (save.repelSteps or 0) <= 0 then return false end
  if not level then return false end
  local lead
  for _, mon in ipairs(save.party or {}) do
    if (mon.hp or 0) > 0 then
      lead = mon
      break
    end
  end
  if not (lead and lead.level) then return false end
  return level < lead.level
end

-- CheckWildEncounterCooldown (engine/overworld/events.asm:357-365), the first
-- thing RandomEncounter runs (events.asm:1122): zero is a free step, otherwise
-- the counter ticks and only the step that lands on zero may roll.
function World:wildCooldownStep()
  local left = self.wildCooldown or 0
  if left <= 0 then return false end
  left = left - 1
  self.wildCooldown = left
  return left > 0
end

-- LoadWildMonDataPointer's first move, for the grass list and the water one
-- alike: _SwarmWildmonCheck searches SwarmGrassWildMons / SwarmWaterWildMons
-- ahead of the Johto and Kanto tables, and only while the player is standing
-- on the swarm's own map.  Roamers.Swarm.tables hands the ORIGINAL table back
-- when no swarm applies, so an ordinary step pays nothing for this.
function World:wildTables()
  local save = self.game and self.game.save
  if not (save and self.map and self.encounters) then return self.encounters end
  return Roamers.Swarm.tables(save, self.encounters, self.map.id)
end

-- ---------------------------------------------------------------------------
-- The Bug Catching Contest (engine/events/bug_contest/).
-- ---------------------------------------------------------------------------
--
-- src/core/gen2/BugContest.lua is the whole model -- the park's encounter
-- table, the twenty minute clock, the park balls, the one held catch, the
-- scoring and the podium -- and every rule below is one call into it.  What
-- lives here is the four CALL SITES the cart has and the port had none of:
--
--   RandomEncounter's contest branch          World:tryContestEncounter
--   CheckTimeEvents' CheckBugContestTimer     World:checkTimeEvents
--   BugCatchingContestBattleScript's tail     World:bugContestBattleOver
--   BugCatchingContestOverScript              World:bugContestOver
--
-- The gate conversation itself is extracted script bytecode and needs nothing
-- here: Route35NationalParkGate's officer runs through the same VM every other
-- NPC does, and its six `special`s are handled in src/script/gen2/Specials.lua.

-- _TryWildEncounter_BugContest: the rate is the tile's (40 percent in the
-- park's long grass, 20 in the ordinary kind), the row comes from ContestMons
-- and the level from that row's span.  The mon is built through
-- src/battle/gen2/Mon.lua like any other wild encounter, so it arrives with a
-- Gen 2 moveset and DVs the judge can score.
function World:tryContestEncounter(collision)
  local game, save = self.game, self.game and self.game.save
  if not (game and save) then return false end
  if not BugContest.triggers(Permissions.isSuperTallGrass(collision)) then
    return false
  end
  local roll = self:rollEncounter("contest", "grass", nil, rollContestVanilla)
  if not roll then return false end
  local wild = Mon.new(game.data, roll.species, roll.level)
  if not wild then return false end
  save.pokedex = save.pokedex or { seen = {}, caught = {} }
  save.pokedex.seen[roll.species] = true
  -- BATTLETYPE_CONTEST, which is what puts PARKBALL in the battle menu and
  -- sends a caught mon to wContestMon instead of to the party.
  self:startBattle({ wild = wild, contest = true })
  return true
end

-- CheckTimeEvents (engine/overworld/events.asm), the clock half of the
-- player-event chain.  While ENGINE_BUG_CONTEST_TIMER is set it polls
-- CheckBugContestTimer and NOTHING else -- the daily reset, the swarm and the
-- phone call are all on the `.do_daily` arm the contest skips.  A carry out of
-- it is BugCatchingContestOverScript.
--
-- `.do_daily` is CheckDailyResetTimer, CheckSwarmFlag, CheckPokerusTick and
-- CheckPhoneCall here, in the cart's order.  The reset is what clears
-- wDailyFlags1, so it is what makes the
-- contest a ONCE A DAY thing -- BugContestResults_CleanUp's `setflag
-- ENGINE_DAILY_BUG_CONTEST` is the bit the officer refuses on, and nothing
-- else ever takes it back down.  The Pokerus tick counts down every infected
-- party slot by the days since it last ran.  CheckPhoneCall is the random
-- incoming ring: the whole five-test gate (the entrance tile underfoot, the
-- 20/10/5/3 minute countdown, the coin flip, the signal, an available
-- caller) is src/core/gen2/Phone.lua's tryRandomCall, and its carry is
-- Script_ReceivePhoneCall, so a landed call answers true the same way the
-- contest's over-script does.  What belongs here is only what the gate reads
-- off the world: CheckStandingOnEntrance (home/map_objects.asm) is COLL.DOOR
-- / COLL_DOOR_79 / COLL_STAIRCASE / COLL_CAVE under the player's feet.
function World:checkTimeEvents()
  local save = self.game and self.game.save
  if not save then return false end
  if not BugContest.isActive(save) then
    Apricorns.checkDailyResetTimer(save)
    -- CheckSwarmFlag, second on `.do_daily` and the ONLY thing that ever ends
    -- a swarm: the reset above takes DAILYFLAGS1_SWARM down, and this is what
    -- notices and clears wSwarmMapGroup/Number and wFishingSwarmFlag with it.
    -- Without it a Dunsparce call would leave Dark Cave swarming forever.
    Roamers.Swarm.check(save)
    Pokerus.checkTick(save)
    local ctx = self:stepContext().phone
    local coll = self.map and self.player
      and self.map:cellCollision(self.player.cellX, self.player.cellY)
    ctx.standingOnEntrance = coll == 0x71 or coll == 0x79
      or coll == 0x7a or coll == 0x7b
    local call = require("src.core.gen2.Phone").checkPhoneCall(save, ctx)
    if call then return self:receivePhoneCall(call) end
    return false
  end
  if not BugContest.tickTimer(save) then return false end
  return self:bugContestOver("time")
end

-- BugCatchingContestOverScript and BugCatchingContestOutOfBallsScript: the same
-- two commands over a different line, and both fall into
-- BugCatchingContestReturnToGateScript.  Neither is a std script (they sit in
-- engine/events/bug_contest/contest.asm, which nothing points at), so the text
-- is authored here the way World:repelWoreOff's is.
local BUG_CONTEST_TIME_UP = Strings.source("ANNOUNCER: BEEEP!\fTime's up!")
local BUG_CONTEST_IS_OVER =
  Strings.source("ANNOUNCER: The\nContest is over!")
local SFX_ELEVATOR_END = 39

function World:bugContestOver(reason)
  if self.bugContestEnding then return false end
  self.bugContestEnding = true
  self:playSfxNamed("Sfx_ElevatorEnd", SFX_ELEVATOR_END)
  local line = (reason == "balls") and BUG_CONTEST_IS_OVER or BUG_CONTEST_TIME_UP
  self:showText(Strings(line), function()
    self.bugContestEnding = nil
    self:bugContestResults()
  end)
  return true
end

-- `jumpstd BugContestResultsWarpScript`, run the way the cart runs it: the std
-- script itself does the warp to the north gate, the walk in, the judging, the
-- prize and the party hand-back, so this hands control back to the VM rather
-- than reimplementing any of it.  A cache without that std script leaves the
-- contest state alone -- stopping the clock here would strand the player in the
-- park with no way to be judged.
function World:bugContestResults()
  local entry = self.stdScripts and self.stdScripts.scripts
    and self.stdScripts.scripts.BugContestResultsWarpScript
  local key = entry and entry.key
  if not (key and self.vm) then return false end
  return self.vm:start(key)
end

-- BugCatchingContestBattleScript's tail: `readmem wParkBallsRemaining /
-- iffalse BugCatchingContestOutOfBallsScript`, checked on the way out of every
-- contest battle.  CheckContestBattleOver has already turned the last ball into
-- a DRAW, so the battle is over either way by the time this runs.
function World:bugContestBattleOver()
  local save = self.game and self.game.save
  if not save then return false end
  if not BugContest.isActive(save) then return false end
  if not BugContest.isOver(save) then return false end
  return self:bugContestOver("balls")
end

-- True when `itemId` is one of the three rods.  The item table is consulted
-- when the caller has one, so a cache whose ItemNames sit at other indices (a
-- different Gen 2 ROM) refuses rather than fishing with a BICYCLE.
function World.isRod(itemId, items)
  local index = ROD_INDEX[itemId]
  if not index then return false end
  local def = items and items[itemId]
  if def and def.index and def.index ~= index then return false end
  return true
end

-- FishFunction's .TryFish (engine/events/overworld.asm): the roll on its own,
-- with no animation and no battle.  `rod` is the item id; the group comes from
-- the map's own MAP_FISHGROUP and the rod picks which of that group's three
-- lists is rolled.  Returns the jumptable case the cart lands on, plus the
-- hooked mon on "battle":
--
--   "nowhere"  $3 .FailFish          surfing, or not facing water
--   "nofish"   $4 .FishNoFish        facing water the map has no group for
--   "nibble"   $1 .FishNoBite        the group's own roll came up empty
--   "battle"   $2 .FishGotSomething
--
-- Split out of World:tryFishing because Script_GotABite writes RodBiteText
-- BEFORE its startbattle, so the cast has to run between the roll and the
-- battle rather than after it.
function World:rollFishing(rod)
  local game, player, map = self.game, self.player, self.map
  if not (game and player and map and self.encounters) then return "nowhere" end
  -- .TryFish reads wPlayerState first and drops straight to $3 .FailFish while
  -- the player is PLAYER_SURF / PLAYER_SURF_PIKA: you cannot fish from the
  -- back of a Lapras, only from the bank.
  if FieldMoves.isSurfing(self.playerState) then return "nowhere" end
  -- The cart requires the tile the player is FACING to be water, not the one
  -- they stand on.
  local d = Map.DELTA[player.facing or "down"] or Map.DELTA.down
  local cx, cy = player.cellX + d[1], player.cellY + d[2]
  if not Permissions.isWater(map:cellCollision(cx, cy)) then return "nowhere" end
  -- GetFishingGroup (home/map.asm) is MAP_FISHGROUP off the map header, and
  -- .facingwater's `and a / jr nz` sends FISHGROUP_NONE to .FishNoFish.  The
  -- Encounter helper defaults an unknown map to the pond, so the header is
  -- read here rather than left to it.
  local def = self.maps and self.maps[map.id]
  local group = def and def.fishGroup
  if not group or group == 0 or group == "FISHGROUP_NONE" then
    return "nofish"
  end
  -- GetFishGroupIndex reads wFishingSwarmFlag between the header and the
  -- FishGroups index, which is how the Route 32 Qwilfish and Route 44 Remoraid
  -- swarms reach the rods at all: the phone call's ActivateFishingSwarm writes
  -- the flag and nothing about the map changes.  Roamers.Swarm.fishing is the
  -- same store CheckSwarmFlag clears when the swarm expires.
  local swarm = Roamers.Swarm.fishing(game.save)
  -- engine/events/fish.asm:24-30
  local groupRow = self.encounters.fishGroups
    and self.encounters.fishGroups[
      Encounter.fishGroupFor(self.encounters, group, swarm)]
  if groupRow and groupRow.chance
      and not Encounter.triggers(groupRow.chance, nil) then
    return "nibble"
  end
  local roll
  local tod = self.tod or "DAY"
  if Runtime.wantsHook("encounter.fishing") then
    -- Gen 1's three arguments, in Gen 1's order: the rod, the map, and the
    -- candidate list the chain may inspect or replace before the roll.  Gold's
    -- candidates are the FishGroups row the map header (plus any swarm swap)
    -- resolves to, so the third argument is that row rather than Gen 1's
    -- extracted fishing group -- same role, same position.  ctx is the fourth
    -- argument and is Gen 2's alone; nothing before it moved.
    local group = Encounter.fishGroupFor(self.encounters,
      (def and def.fishGroup) or "FISHGROUP_POND", swarm)
    local groups = self.encounters and self.encounters.fishGroups
    roll = Runtime.call("encounter.fishing", fishVanilla, rod, map.id,
      groups and groups[group],
      { fishGroup = group, swarm = swarm, encounters = self.encounters,
        maps = self.maps, data = game.data, tod = tod, daytime = tod })
  else
    roll = Encounter.fishSlot(self.encounters, map.id, rod, nil, self.maps,
      swarm, tod)
  end
  if not roll or not roll.species then return "nibble" end
  local wild = Mon.new(game.data, roll.species, roll.level)
  if not wild then return "nibble" end
  local save = game.save
  if save then
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen[roll.species] = true
  end
  return "battle", wild
end

-- Roll and start the battle in one call, for a caller that wants the outcome
-- without the cast animation.  The PACK goes through World:useRod instead.
--
-- The return widened when the input path landed: it used to be
-- "battle"/"nibble"/nil, and nil could not tell the two failures apart -- the
-- PACK has to keep itself open for one ("nowhere") and quit for the other
-- ("nofish"), which is the whole difference between UseItem's .Oak and its
-- PACKSTATE_QUITRUNSCRIPT.
function World:tryFishing(rod)
  local outcome, wild = self:rollFishing(rod)
  if outcome == "battle" and wild then
    self:startBattle({ wild = wild })
  end
  return outcome
end

-- UseRod (engine/items/item_effects.asm), which is a bare `farcall
-- FishFunction` after OldRodEffect / GoodRodEffect / SuperRodEffect have
-- chosen rod 0/1/2.  Rolls first, then hands the outcome to the cast.
--
-- A rod is ITEMMENU_NOUSE in battle, and a running script owns the world, so
-- both answer "nowhere" -- which is the cart's own "This isn't the time to use
-- that!", the case where the PACK stays open.
function World:useRod(rodId)
  if self.battleActive or self:busy() then return "nowhere" end
  local outcome, wild = self:rollFishing(rodId)
  if outcome == "nowhere" then return "nowhere" end
  self:beginFishing(outcome, wild)
  return outcome
end

-- The field half of engine/items/pack.asm UseItem: an item used from the PACK
-- in the overworld.  Returns nil for anything this world does not handle, so
-- the PACK falls through to its own onChoose (TM teaching lives there);
-- otherwise the FishFunction outcome, where "nowhere" means the PACK must stay
-- open and print OakThisIsntTheTimeText.
function World:useFieldItem(itemId)
  local items = self.game and self.game.data and self.game.data.items
  if itemId == "ITEMFINDER" then return self:useItemfinder() end
  if itemId == "BICYCLE" then return self:useBike(itemId) end
  if itemId == "SACRED_ASH" then return self:useSacredAsh() end
  if itemId == "ESCAPE_ROPE" then return self:useEscapeRope(itemId) end
  if itemId == "SQUIRTBOTTLE" then return self:useSquirtbottle() end
  -- CoinCaseEffect (engine/items/item_effects.asm:2243).
  if itemId == "COIN_CASE" then return "coin_case", self:coins() end
  if REPEL_STEPS[itemId] then return self:useRepel(itemId) end
  if TROPHY_BOXES[itemId] then return self:openTrophyBox(itemId) end
  if not World.isRod(itemId, items) then return nil end
  return self:useRod(itemId)
end

-- EscapeRopeOrDig's .CheckCanDig (engine/events/overworld.asm): the map's
-- environment must be CAVE or DUNGEON and the banked warp triple must name a
-- real warp.  The cart reads wDigWarpNumber / wDigMapGroup / wDigMapNumber
-- there; this port keeps one banked triple -- backupWarp, the same store a -1
-- warp destination resolves through and the one the save carries -- so the
-- rope pays out to the last warp that banked it rather than to a second
-- register.  A triple that names a map or warp the cache does not carry is
-- the cart's zeroed-triple `.fail` arm.
function World:escapeRopeTarget()
  local env = self.map and self.map.def and self.map.def.environment
  if env ~= "CAVE" and env ~= "DUNGEON" then return nil end
  local backup = self.backupWarp
  local dest = backup and backup.map and self.maps and self.maps[backup.map]
  local destWarp = dest and dest.warps and backup.warp
    and dest.warps[backup.warp]
  if not destWarp then return nil end
  return backup.map, destWarp
end

-- The shared tail of .UsedEscapeRopeScript / .UsedDigScript: SFX.WARP_TO,
-- `loadvar VAR.MOVEMENT, PLAYER_NORMAL`, then `newloadmap MAPSETUP.DOOR` with
-- the triple already in wNextWarp -- EnterMapWarp and GetWarpDestCoords land
-- the player on the destination warp's own tile.  The dig-spin sprite work is
-- not ported, the same standing decision World:flyTo records for the two fly
-- animations.
function World:runEscapeWarp(destMapId, destWarp)
  self:playSfxNamed("Sfx_WarpTo", SFX.WARP_TO)
  self:applyPlayerState(FieldMoves.PLAYER_NORMAL)
  return self:runMapSetup(MAPSETUP.DOOR, function()
    local ok = self:setMap(destMapId, destWarp.x, destWarp.y, "down")
    if ok then self:spawnFacing() end
    return ok
  end)
end

-- EscapeRopeEffect (engine/items/item_effects.asm): EscapeRopeFunction, and
-- UseDisposableItem only when it succeeded -- a refusal costs nothing.  The
-- ESCAPE_ROPE is ITEMMENU_CLOSE, so "nowhere" sends UseItem's .Field arm to
-- .Oak (the PACK prints OakThisIsntTheTimeText and stays open) and a success
-- quits the PACK, with the queued script -- the used-rope line and the warp
-- -- running once the overworld owns the frame, exactly the QueueScript
-- placement the cart gives .UsedEscapeRopeScript.
function World:useEscapeRope(itemId)
  if self.battleActive or self:busy() then return "nowhere" end
  local destMapId, destWarp = self:escapeRopeTarget()
  if not destMapId then return "nowhere" end
  local items = self.game and self.game.data and self.game.data.items
  local def = items and items[itemId or "ESCAPE_ROPE"]
  self:takeItem(def and def.index, 1)
  self.queuedFieldMove = {
    ok = true, action = "escaperope",
    destMap = destMapId, destWarp = destWarp,
    text = FieldMoves.TEXT.USE_ESCAPE_ROPE,
  }
  return "escape_rope"
end

-- _Squirtbottle (engine/events/squirtbottle.asm): the script is QUEUED and
-- wItemEffectSucceeded is set to 1 unconditionally, so the PACK always quits;
-- .CheckCanUseSquirtbottle then picks between WateredWeirdTreeScript and the
-- "nothing happened" line over the overworld.  The check is run here, at
-- queue time, because the player cannot turn between the press and the drain.
--
-- The watered-tree body is not invented: it is sliced out of the extracted
-- Sudowoodo talk script (maps/Route36.asm SudowoodoScript), whose .Fight arm
-- falls through into the exported WateredWeirdTreeScript right after its
-- yesorno's `iffalse` + `closetext` pair -- so the PACK use and the talk path
-- run the very same decoded rows, battle and TWIN swap included.
local SPRITEMOVEDATA_SUDOWOODO = 0x17
local TEXT_SQUIRTBOTTLE_NOTHING = Strings.source(
  "{PLAYER} sprinkled\nwater.\fBut nothing\nhappened…")

function World:squirtbottleTreeScript()
  local p, map = self.player, self.map
  if not (p and map and map.id == "ROUTE_36") then return nil end
  local d = Map.DELTA[p.facing or "down"] or Map.DELTA.down
  local npc = self:npcAt(p.cellX + d[1], p.cellY + d[2])
  local def = npc and npc.def
  if not (def and def.movement == SPRITEMOVEDATA_SUDOWOODO
      and def.scriptKey) then
    return nil
  end
  local talk = self.scripts and self.scripts[def.scriptKey]
  local armKey
  for _, cmd in ipairs(talk or {}) do
    if cmd.op == "iftrue" and cmd.script then armKey = cmd.script break end
  end
  local arm = armKey and self.scripts and self.scripts[armKey]
  if not arm then return nil end
  for i, cmd in ipairs(arm) do
    if cmd.op == "iffalse" then
      -- WateredWeirdTreeScript starts past the yesorno's own closetext.
      local start = i + 1
      if arm[start] and arm[start].op == "closetext" then start = start + 1 end
      if not arm[start] then return nil end
      local rows = {}
      for j = start, #arm do rows[#rows + 1] = arm[j] end
      return rows
    end
  end
  return nil
end

function World:useSquirtbottle()
  if self.battleActive or self:busy() then return "nowhere" end
  local tree = self:squirtbottleTreeScript()
  if tree then
    self.queuedScript = tree
  else
    self.queuedScript = {
      { op = "opentext" },
      { op = "rawtext", text = TEXT_SQUIRTBOTTLE_NOTHING },
      { op = "waitbutton" },
      { op = "closetext" },
      { op = "end" },
    }
  end
  return "squirtbottle"
end

-- CheckRegisteredItem (engine/overworld/select_menu.asm), re-run on every
-- SELECT press rather than only when the item was registered: tossing the
-- last copy, trading it away or a TM losing CANT_SELECT_F retroactively (it
-- never does, but the pack does run out) all answer the same
-- ".NoRegisteredItem" way the cart does -- silently clearing the slot instead
-- of holding a stale pointer.  wWhichRegisteredItem packs a pocket and a
-- quantity so a KEY_ITEM's count never underflows and an ITEM/BALL's does;
-- this port keeps only the item id and re-reads the live inventory count,
-- which answers the same "not enough left" case for zero without needing the
-- packed field at all.
function World:registeredItemId()
  local save = self.game and self.game.save
  local reg = save and save.registeredItem
  local id = reg and reg.id
  if not id then return nil end
  local items = self.game and self.game.data and self.game.data.items
  local def = items and items[id]
  local count = save.inventory and save.inventory[id]
  if not def or def.canSelect == false or not count or count <= 0 then
    save.registeredItem = nil
    return nil
  end
  return id
end

-- RegisterItem (engine/items/pack.asm): CheckSelectableItem gates it, the
-- same ITEMATTR_PERMISSIONS bit `registeredItemId` re-checks on use, so a
-- TM/HM or anything else with CANT_SELECT_F set refuses.  The cart reaches
-- this from the PACK's own USE/GIVE/TOSS/SEL/QUIT row submenu, which this
-- port has not built; PackMenu instead calls it straight off the highlighted
-- row on a SELECT press, the one PACK button this port left unbound.
function World:registerItem(itemId)
  local items = self.game and self.game.data and self.game.data.items
  local def = items and items[itemId]
  local save = self.game and self.game.save
  if not save or not def or def.canSelect == false then return false end
  save.registeredItem = { id = itemId }
  return true
end

-- SelectMenu (engine/overworld/select_menu.asm): the SELECT press in the
-- overworld.  UseRegisteredItem's four ITEMMENU_* arms (.CantUse / .Current /
-- .Party / .Overworld) are exactly the switch `useFieldItem` already runs for
-- the PACK's own UseItem -- a rod, the ITEMFINDER, a REPEL, a trophy box --
-- so this is that same dispatch with "no registered item" and "no field
-- handler for this one yet" as the two extra outcomes CantUseItem's own two
-- call sites (.NotRegistered and .CantUse) cover on the cart.
function World:useSelectItem()
  if self.battleActive or self:busy() then return "nowhere" end
  local id = self:registeredItemId()
  if not id then return "not_registered" end
  -- wUsingItemWithSelect, set for exactly the length of the effect: the
  -- BICYCLE is the one item whose effect reads it (.CheckIfRegistered), and it
  -- is what makes a SELECT press get on the bike without a line of text.
  self.usingItemWithSelect = true
  local outcome = self:useFieldItem(id)
  self.usingItemWithSelect = nil
  if outcome == nil then return "cant_use" end
  return outcome, id
end

-- UseRepel (engine/items/item_effects.asm): a REPEL's ItemAttributes give it
-- ITEMMENU_CURRENT, so UseItem's `.Current` arm runs DoItemEffect and returns
-- with no wItemEffectSucceeded check at all -- the PACK never quits for this
-- item, win or lose. wRepelEffect already set (`and a / jp nz`) prints
-- RepelUsedEarlierIsStillInEffectText and leaves the counter and the bag
-- alone; otherwise the new count is written and UseItemText's tail
-- (UseDisposableItem) is the one place a REPEL gets removed from the bag.
--
-- The caller is PackMenu, which owns both messages ("repel_used" builds its
-- own from the row's item name; "repel_active" is the fixed three-line text
-- the cart shows) so this stays a plain sentinel like useRod's outcomes.
--
-- ItemAttributes gives a REPEL ITEMMENU_NOUSE in battle, same as a rod, so
-- the in-battle PACK (BattleState:openPack, which shares this same World
-- instance) has to be refused here too rather than only from the overworld.
function World:useRepel(itemId)
  local save = self.game and self.game.save
  if not save then return nil end
  if self.battleActive or self:busy() then return "nowhere" end
  if (save.repelSteps or 0) > 0 then return "repel_active" end
  save.repelSteps = REPEL_STEPS[itemId]
  if save.inventory then
    local left = (save.inventory[itemId] or 1) - 1
    save.inventory[itemId] = left > 0 and left or nil
  end
  return "repel_used"
end

-- NormalBoxEffect / GorgeousBoxEffect (engine/items/item_effects.asm), which
-- are the same three lines with a different DECOFLAG: SetSpecificDecorationFlag,
-- _SentTrophyHomeText, UseDisposableItem.  Both items are ITEMMENU_CURRENT, so
-- the PACK prints and stays open rather than quitting to the field.
--
-- This is the one path in Gold that can hand the player a decoration and that
-- this port can actually reach; the other two (Mom's doll purchases, which
-- need her savings account, and Mystery Gift, which needs a second cart) are
-- not built.
--
-- Both boxes are ITEMMENU_NOUSE in battle, so BattlePack answers .Oak for them
-- and the flag is never granted nor the box spent mid-fight.
function World:openTrophyBox(itemId)
  local decoFlag = TROPHY_BOXES[itemId]
  if not decoFlag then return nil end
  if self.battleActive then return "nowhere" end
  Decorations.giveFlag(self.events, decoFlag)
  local items = self.game and self.game.data and self.game.data.items
  local def = items and items[itemId]
  self:takeItem(def and def.index, 1)
  return "trophy_sent"
end

-- ItemFinder (engine/items/itemfinder.asm): CheckForHiddenItems, then one of
-- two scripts is QUEUED and wItemEffectSucceeded is set unconditionally.  In
-- the FIELD there is no "you can't use that here" arm -- the ITEMFINDER always
-- quits the PACK.  The item is ITEMMENU_NOUSE in battle, where BattlePack's
-- .Oak answers instead and no script is queued: quitting the PACK there would
-- take the battle off the stack with it.
--
-- QueueScript, not CallScript: the PACK (and the START menu under it) is still
-- on the screen at this point, and the beeps and the line belong over the
-- overworld.  World:runQueuedScript is the other half.
function World:useItemfinder()
  if self.battleActive then return "nowhere" end
  local p = self.player
  local found = p and HiddenItems.nearby(
    self.map and self.map.def, p.cellX, p.cellY, self.events) or nil
  self.queuedScript = HiddenItems.itemfinderScript(found, function(want, id)
    return self:sfxIdNamed(want, id)
  end)
  return "itemfinder"
end

-- ---------------------------------------------------------------- the bike
--
-- src/world/gen2/Bike.lua owns every decision; this is the world state those
-- decisions read and the presentation they end in.

-- wBikeFlags' three bits are ENGINE_* ids like any other flag, so the map
-- callbacks that set them (Route16AlwaysOnBikeCallback,
-- Route17AlwaysOnBikeCallback) already land on save.engineFlags.
function World:alwaysOnBike()
  return self:engineFlag(Bike.ENGINE_ALWAYS_ON_BIKE)
end

function World:downhill()
  return self:engineFlag(Bike.ENGINE_DOWNHILL)
end

-- GetPlayerTilePermission's operand: the collision under the player's feet.
function World:playerCollision()
  local p = self.player
  if not (p and self.map) then return nil end
  return self.map:cellCollision(p.cellX, p.cellY)
end

-- BikeFunction (engine/events/overworld.asm), reached from BicycleEffect.
--
-- The BICYCLE is ITEMMENU_CLOSE, so UseItem takes its .Field arm: a non-zero
-- wFieldMoveSucceeded quits the PACK and lets the queued script run in the
-- overworld, and a zero drops into .Oak instead.  "nowhere" is that zero --
-- PackMenu already prints OakThisIsntTheTimeText for it -- and the three other
-- answers all queue a script and let the PACK close.
--
-- .GetOnBike's music is not the outdoor-song override Gen 1 uses: it silences
-- the current song, plays MUSIC_BICYCLE and writes it into wMapMusic, so the
-- bike theme survives until the dismount's `special PlayMapMusic` or the next
-- map load puts the map's own song back.
function World:useBike(itemId)
  if self.battleActive or self:busy() then return "nowhere" end
  local items = self.game and self.game.data and self.game.data.items
  local def = items and items[itemId or "BICYCLE"]
  local item = def and def.index
  local specialId = function(name) return self:specialIdNamed(name) end
  local action = Bike.tryBike({
    state = self.playerState,
    environment = self.map and self.map.def and self.map.def.environment,
    collision = self:playerCollision(),
    alwaysOnBike = self:alwaysOnBike(),
  })
  -- wUsingItemWithSelect, which .CheckIfRegistered reads to pick the silent
  -- pair of scripts.
  local silent = self.usingItemWithSelect and true or false
  if action == "mount" then
    self.queuedScript = Bike.mountScript(item, specialId, silent)
    self:playBikeMusic()
    return "bike_on"
  elseif action == "dismount" then
    self.queuedScript = Bike.dismountScript(item, specialId, silent)
    return "bike_off"
  elseif action == "cant_get_off" then
    self.queuedScript = Bike.cantGetOffScript()
    return "bike_stuck"
  end
  return "nowhere"
end

function World:playBikeMusic()
  local data = self.game and self.game.data
  local audio = data and data.audio
  if not (audio and audio.runtime) then return false end
  if not (audio.songs and audio.songs[Bike.MUSIC_BICYCLE]) then return false end
  Music.play(data, Bike.MUSIC_BICYCLE, true, { reason = "bike" })
  return true
end

-- `special` names resolve through the cache's own SpecialsPointers order
-- (constants.specialOrder), same as Vm:specialName but starting from the
-- name instead of the decoded id -- a hand-built script has a label to write
-- and no counted index to have copied down.
function World:specialIdNamed(name)
  local order = self.constants and self.constants.specialOrder
  if not order or not name then return nil end
  for i, n in ipairs(order) do
    if n == name then return i - 1 end
  end
  return nil
end

-- SacredAshEffect / _SacredAsh (engine/items/item_effects.asm,
-- engine/events/sacred_ash.asm).  CheckAnyFaintedMon gates the whole effect
-- on carry: an empty party or one with nothing fainted never sets
-- wItemEffectSucceeded, so UseItem's .Field falls through to .Oak
-- (OakThisIsntTheTimeText) with the item untouched -- PackMenu already has
-- that message under "nowhere", the same answer a rod gives with no water in
-- front of the player.
--
-- On success SacredAshScript runs a single HealParty (revives AND fully
-- heals every party member in one pass, see World:healParty) behind three
-- Pokecenter-style fade cycles and the "all healed" line, then
-- UseDisposableItem removes the one Ash from the bag.
function World:useSacredAsh()
  if self.battleActive or self:busy() then return "nowhere" end
  local save = self.game and self.game.save
  local party = (save and save.party) or {}
  local anyFainted = false
  for _, mon in ipairs(party) do
    if not Breeding.isEgg(mon) and (mon.hp or 0) <= 0 then
      anyFainted = true
      break
    end
  end
  if not anyFainted then return "nowhere" end

  if save.inventory then
    local left = (save.inventory.SACRED_ASH or 1) - 1
    save.inventory.SACRED_ASH = left > 0 and left or nil
  end

  local script = {
    { op = "special", id = self:specialIdNamed("HealParty") },
    { op = "refreshmap" },
    { op = "playsound", id = self:sfxIdNamed("Sfx_WarpTo", SFX.WARP_TO) },
  }
  for _ = 1, 3 do
    script[#script + 1] = { op = "special", id = self:specialIdNamed("FadeOutToWhite") }
    script[#script + 1] = { op = "special", id = self:specialIdNamed("FadeInFromWhite") }
  end
  script[#script + 1] = { op = "waitsfx" }
  script[#script + 1] = { op = "opentext" }
  script[#script + 1] = { op = "rawtext", text = TEXT_USE_SACRED_ASH }
  script[#script + 1] = { op = "playsound", id = self:sfxIdNamed("Sfx_CaughtMon", 2) }
  script[#script + 1] = { op = "waitsfx" }
  script[#script + 1] = { op = "waitbutton" }
  script[#script + 1] = { op = "closetext" }
  script[#script + 1] = { op = "end" }
  self.queuedScript = script
  return "sacredash"
end

-- QueueScript's drain, on the same clock as the field move one below it: the
-- first frame the overworld owns after the menus are gone.
function World:runQueuedScript()
  local script = self.queuedScript
  if not script or self:busy() then return false end
  self.queuedScript = nil
  self.talkNpc = nil
  return self.vm and self.vm:start(script) or false
end

-- Script_FishCastRod, then Script_NotEvenANibble or Script_GotABite.  Held as
-- an exact frame counter matching 60 Hz engine ticks.
function World:beginFishing(outcome, wild)
  local p = self.player
  local d = Map.DELTA[p and p.facing or "down"] or Map.DELTA.down
  local targetCellX = p and (p.cellX + d[1]) or 0
  local targetCellY = p and (p.cellY + d[2]) or 0
  local bobber = {
    cellX = targetCellX,
    cellY = targetCellY,
    px = targetCellX * 16,
    py = targetCellY * 16,
  }
  self.fishing = {
    phase = "cast",
    timer = FISH_CAST_FRAMES,
    outcome = outcome,
    wild = wild,
    bobber = bobber,
    facing = p and p.facing or "down",
  }
  if self.player then
    self.player.fishing = true
    self.player.fishingState = self.fishing
  end
end

function World:updateFishing()
  local st = self.fishing
  if not st then return end
  if self.player then self.player.fishingState = st end
  -- A text box owns the frame while it is up; the script only moves on when
  -- its own callback fires.
  if self.textbox or self.choicebox then return end
  if st.timer > 0 then
    st.timer = st.timer - 1
    -- StepFunction_GotBite (engine/overworld/map_objects.asm:1430) is one byte
    -- of animation: OBJECT_SPRITE_Y_OFFSET flipped between 0 and 1 once a
    -- frame for the length of the bite, which is the rod jerking in the
    -- player's hands.
    if self.player then
      self.player.spriteYOffset =
        (st.phase == "bite" and st.timer % 2 == 1) and 1 or 0
    end
    return
  end
  if self.player then self.player.spriteYOffset = 0 end
  if st.phase == "cast" then
    if st.outcome == "battle" then
      st.phase = "bite"
      st.timer = FISH_BITE_FRAMES
      self:showEmote(EMOTE_SHOCK, 0, FISH_BITE_FRAMES)
      return
    end
    st.phase = "done"
    self:showText(Strings(TEXT_ROD_NOTHING), function()
      self.fishing = nil
      if self.player then
        self.player.fishing = nil
        self.player.fishingState = nil
      end
    end)
    return
  end
  if st.phase == "bite" then
    st.phase = "done"
    self:showText(Strings(TEXT_ROD_BITE), function()
      local wild = st.wild
      self.fishing = nil
      if self.player then
        self.player.fishing = nil
        self.player.fishingState = nil
      end
      if wild then self:startBattle({ wild = wild, battleType = "fish" }) end
    end)
    return
  end
end

-- CheckHeadbuttTreeTile (home/map_objects.asm).
function World.isHeadbuttTree(coll)
  if coll == nil then return false end
  return HEADBUTT_TREE[coll % 256] == true
end

-- CheckPartyMove (engine/events/overworld.asm): the first party mon that knows
-- move `moveId`.  The cart leaves that mon's slot in wCurPartyMon, which
-- GetPartyNickname then reads for "<nickname> did a HEADBUTT!", so the mon
-- itself is returned rather than a bare yes/no.
--
-- The cart also skips EGG slots; the port has no egg state yet, so there is
-- nothing to skip.
-- HEADBUTT's and ROCK SMASH's CheckPartyMove, and the one the route bot asks.
-- Wrapped in the same fieldmove.eligibility chain FieldMoves.partyMoveUser
-- offers -- two separate walks of the party, so a mod sees each site once --
-- and with the full Gen 1 ctx, because a World has the Game the love-free
-- module does not.
function World:partyMoveUser(moveId)
  local save = self.game and self.game.save
  local party = (save and save.party) or {}
  return FieldMoves.partyMoveUser(party, moveId,
    { save = save, data = self.game and self.game.data })
end

-- TryHeadbuttOW (engine/events/overworld.asm), reached from
-- TryTileCollisionEvent's .headbutt arm once the facing tile is a tree.  With
-- no party mon that knows HEADBUTT the whole event is skipped -- TryHeadbuttOW
-- returns nc and TryTileCollisionEvent jumps to .noevent, so the A press does
-- nothing at all, not even a line of text.  With one, AskHeadbuttScript opens.
--
-- Returns true when the event took the A press.
function World:tryHeadbuttOW(cx, cy)
  if not (self.map and self.player) then return false end
  if not World.isHeadbuttTree(self.map:cellCollision(cx, cy)) then
    return false
  end
  local mon = self:partyMoveUser(MOVE_HEADBUTT)
  if not mon then return false end
  -- AskHeadbuttScript: opentext, writetext AskHeadbuttText, yesorno,
  -- iftrue HeadbuttScript.  The port's yesorno re-shows the page it is
  -- answering underneath the prompt, which is what World:askYesNo does with
  -- the body World:showText just kept.
  self:showText(Strings(TEXT_ASK_HEADBUTT), function()
    self:askYesNo(function(yes)
      if yes then self:runHeadbutt(cx, cy, mon) end
    end)
  end)
  return true
end

-- HeadbuttScript: GetPartyNickname, UseHeadbuttText, ShakeHeadbuttTree, and
-- only then TreeMonEncounter.  The roll comes AFTER the shake, which is why
-- the tree rattles even when nothing is home.
function World:runHeadbutt(cx, cy, mon)
  if self.game then
    -- callasm GetPartyNickname: wStringBuffer2 is the nickname of the mon
    -- CheckPartyMove left in wCurPartyMon, and {STRBUF} is how TextBox reads
    -- it back.
    self.game.stringBuffer =
      (mon and (mon.nickname or mon.name or mon.species)) or ""
  end
  self:showText(Strings(TEXT_USE_HEADBUTT), function()
    self.headbutt = { x = cx, y = cy, timer = HEADBUTT_SHAKE_FRAMES }
    -- ShakeHeadbuttTree (engine/events/field_moves.asm:23) hides the BG tree
    -- and wobbles an OBJ copy of it -- Frameset_HeadbuttTree alternates two
    -- frames, the second X-flipped, every two frames for the 32 the counter
    -- runs.  There is no per-block OBJ layer here (the map is one baked
    -- canvas), so the wobble is the frame's, on the same clock and for the
    -- same 32 frames as the SFX that goes with it.
    self:earthquake(0x40, HEADBUTT_SHAKE_FRAMES)
    self:playSfx(SFX.SANDSTORM)
  end)
end

function World:updateHeadbutt()
  local st = self.headbutt
  if not st then return end
  if self.textbox or self.choicebox then return end
  if st.timer > 0 then
    st.timer = st.timer - 1
    return
  end
  -- callasm TreeMonEncounter, iffalse .no_battle.  Cleared first for the same
  -- reason the fishing state is: startBattle must not see a busy world.
  self.headbutt = nil
  if self:tryHeadbutt(st.x, st.y) == "battle" then return end
  self:showText(Strings(TEXT_HEADBUTT_NOTHING))
end

-- Headbutt.  A tree's own map entry decides which of the two tree sets is
-- rolled, and whether anything is home at all (engine/events/treemons.asm
-- TreeMonEncounter).  Returns "battle", "nothing" or nil.
function World:tryHeadbutt(cx, cy)
  local game, map = self.game, self.map
  if not (game and map and self.encounters) then return nil end
  local roll = Encounter.treeSlot(self.encounters, map.id, cx, cy, nil)
  if not roll or not roll.species then return "nothing" end
  local wild = Mon.new(game.data, roll.species, roll.level)
  if not wild then return "nothing" end
  local save = game.save
  if save then
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen[roll.species] = true
  end
  self:startBattle({ wild = wild })
  return "battle"
end

-- ROCK SMASH's wild mon (engine/events/treemons.asm RockMonEncounter), which
-- is TreeMonEncounter's twin over a different map table and with a flat roll
-- where the tree has its coordinate score:
--
--   GetTreeMonSet RockMonMaps   the four maps whose rocks hold anything at all
--   GetTreeMons                 that row's TREEMON_SET_* table
--   RandomRange 10, cp 4        40 percent, and it sits BETWEEN the two
--   SelectTreeMon               the set's FIRST list, walked by a 0..99 roll
--
-- Two things the twin does NOT do: it writes no wScriptVar (RockSmashScript
-- reads its answer back with `readmem wTempWildMonSpecies / iffalse`), and it
-- never reaches GetTreeMon's `.rare` skip past the -1, so the second half of
-- TREEMON_SET_ROCK is unreachable and only the 90/10 KRABBY / SHUCKLE list can
-- come out of a rock.
--
-- `random` is injectable for the same reason World:roamRandom is: a driver and
-- a test have to be able to pin the 40 percent.  Returns the species INDEX the
-- cart leaves in wTempWildMonSpecies, or 0 for nothing -- which is exactly what
-- the `readmem` below hands back to the script.
function World:rockRandom(n)
  if self.rockmonRandom then return self.rockmonRandom(n) end
  if love and love.math and love.math.random then
    return love.math.random(n) - 1
  end
  return math.random(n) - 1
end

function World:rockMonEncounter()
  -- `xor a / ld [wTempWildMonSpecies], a / ld [wCurPartyLevel], a` opens the
  -- routine, so a second smash never inherits the first one's mon.
  self.tempWildMon = nil
  local game, map = self.game, self.map
  if not (game and map and self.encounters) then return 0 end
  local setName = self.encounters.rocks and self.encounters.rocks[map.id]
  if not setName then return 0 end
  local set = self.encounters.treeSets and self.encounters.treeSets[setName]
  local list = set and set.common
  if not (list and #list > 0) then return 0 end
  if self:rockRandom(10) >= 4 then return 0 end
  -- SelectTreeMon's `.loop: sub [hl] / jr c, .ok`: the chance column is walked
  -- as a running total until the roll borrows.
  local value = self:rockRandom(100)
  local total = 0
  local pick
  for _, row in ipairs(list) do
    total = total + (row.chance or 0)
    if value < total then
      pick = row
      break
    end
  end
  -- `.ok`'s own `cp -1 / jr z, NoTreeMon`: a list walked off the end is nothing.
  if not (pick and pick.species) then return 0 end
  local pokemon = game.data and game.data.pokemon
  local def = pokemon and pokemon[pick.species]
  if not (def and def.index) then return 0 end
  self.tempWildMon = { species = def.index, level = pick.level }
  return def.index
end

-- readmem's engine seam.  The VM keeps a sparse byte store for the addresses a
-- script owns outright (the Goldenrod switches, wMooMooBerries); these are the
-- ones the ENGINE writes, where answering out of that store would read back a
-- stale 0.  RockSmashScript's `readmem wTempWildMonSpecies / iffalse` is the
-- whole reason this exists: the byte is written by the callasm one row above.
local WRAM_TEMP_WILD_MON_SPECIES = 0xd117

function World:scriptReadMem(addr)
  if addr == WRAM_TEMP_WILD_MON_SPECIES then
    return (self.tempWildMon and self.tempWildMon.species) or 0
  end
  return nil
end

-- .SweetScent (engine/events/sweet_scent.asm): UseSweetScentText, then
-- SweetScentEncounter's roll.  wFieldMoveSucceeded was already set
-- unconditionally by FieldMoves.sweetScentFromMenu, so runFieldMove has no
-- refusal branch of its own -- the only question left is whether the
-- encounter turns anything up, and that is answered after the button press,
-- same as HEADBUTT's shake.
function World:runSweetScent(result)
  local mon = result and result.mon
  if self.game then
    -- callasm GetPartyNickname: wStringBuffer2 (and 1 and 3) all hold the
    -- same nickname, so {STRBUF} reads back UseSweetScentText's
    -- text_ram wStringBuffer3 line correctly.
    self.game.stringBuffer =
      (mon and (mon.nickname or mon.name or mon.species)) or ""
  end
  self:showText(Strings(TEXT_USE_SWEET_SCENT), function()
    if self:sweetScentEncounter() then return end
    self:showText(Strings(TEXT_SWEET_SCENT_NOTHING))
  end)
end

-- SweetScentEncounter (engine/events/sweet_scent.asm): the same
-- CanEncounterWildMon gate a step takes -- grass/water tile, ice, wildoff,
-- the CAVE/DUNGEON exemption -- but everything downstream skips its own
-- percentage roll.  GetMapEncounterRate only has to come back NONZERO, and
-- ChooseWildEncounter / ChooseWildEncounter_BugContest then run
-- unconditionally: no Encounter.triggers, no BugContest.triggers.
-- CheckRepelEffect is never reached at all here -- a REPEL stops a STEP from
-- encountering, not the player from choosing to use SWEET SCENT.
function World:sweetScentEncounter()
  local game, player, map = self.game, self.player, self.map
  if not (game and player and map and self.encounters) then return false end
  local save = game.save
  if not (save and save.party and #save.party > 0) then return false end
  local collision = map:cellCollision(player.cellX, player.cellY)
  local environment = map.def and map.def.environment
  if not FieldMoves.canEncounterWildMon(
      environment, collision, self.noWildEncounters) then
    return false
  end
  -- .BugCatchingContest: `checkflag ENGINE_BUG_CONTEST_TIMER` skips
  -- GetMapEncounterRate entirely and goes straight to the park's own table,
  -- same as RandomEncounter's own contest arm above -- and, like that arm,
  -- ChooseWildEncounter_BugContest never calls CheckEncounterRoamMon.
  if BugContest.isActive(save) then
    local roll = self:rollEncounter("contest", "grass", nil, rollContestVanilla)
    if not roll then return false end
    local wild = Mon.new(game.data, roll.species, roll.level)
    if not wild then return false end
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen[roll.species] = true
    self:startBattle({ wild = wild, contest = true })
    return true
  end
  -- SweetScentEncounter goes through ChooseWildEncounter like a step does, so
  -- a swarm overrides the map's list here too -- and, unlike a step, it never
  -- reaches CheckRepelEffect, which is why SWEET SCENT works through a REPEL.
  local tables = self:wildTables()
  local onWater = FieldMoves.encounterTable(collision) == "water"
  local rate = onWater and Encounter.waterRate(tables, map.id)
    or Encounter.grassRate(tables, map.id, self.tod)
  if not (rate and rate > 0) then return false end
  -- CheckEncounterRoamMon, the first thing ChooseWildEncounter itself does:
  -- a beast REPLACES the map's own slot rather than adding to it.
  local met = Roamers.checkEncounter(save, map.id, onWater, self:roamRandom())
  if met then
    local beast = Roamers.beginBattle(save, met.index, game.data)
    if beast then
      save.pokedex = save.pokedex or { seen = {}, caught = {} }
      save.pokedex.seen[beast.species] = true
      self:startBattle({ wild = beast, roaming = met.index })
      return true
    end
  end
  local roll = self:rollEncounter("sweet_scent", onWater and "water" or "grass",
    tables, onWater and rollWaterVanilla or rollGrassVanilla)
  if not roll then return false end
  -- ChooseWildEncounter's Unown arm: a chamber with no puzzle solved yet
  -- stays empty for SWEET SCENT too.
  local monOpts = nil
  if roll.species == Unown.SPECIES then
    local flags = self:engineFlags()
    if not Unown.anyUnlocked(flags) then return false end
    monOpts = { dvs = Unown.wildDVs(flags, Mon.randomDVs) }
  end
  local wild = Mon.new(game.data, roll.species, roll.level, monOpts)
  if not wild then return false end
  save.pokedex = save.pokedex or { seen = {}, caught = {} }
  save.pokedex.seen[roll.species] = true
  self:startBattle({ wild = wild })
  return true
end

-- ---- field moves ----------------------------------------------------------
--
-- The world half of engine/events/overworld.asm.  src/world/gen2/FieldMoves.lua
-- holds every decision (badge, party move, tile, refusal line); this holds the
-- effects, because those are the only part that needs a map, a sprite and a
-- frame clock.  The split is exactly the ASM's own: the *Function routines are
-- pure jumptable arithmetic over wFieldMoveData and then hand a SCRIPT to
-- QueueScript, and it is the script that touches the world.

-- The index of the block cell (cx, cy) sits in, inside map.def.blocks, plus
-- the block id there.  GetBlockLocation, minus the WRAM border arithmetic the
-- port has no buffer for.
function World:blockIndexAt(cx, cy)
  local map = self.map
  if not (map and map.width and map.height and map.def) then return nil end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  if bx < 0 or by < 0 or bx >= map.width or by >= map.height then return nil end
  local index = by * map.width + bx + 1
  return index, (map.def.blocks or {})[index]
end

-- Everything a FieldMoves routine reads, gathered once.  GetFacingTileCoord is
-- folded in: the facing cell is the player's own plus their direction, and
-- wTileUp is the cell above them whichever way they face.
function World:fieldContext(mon)
  local p, map = self.player, self.map
  local save = self.game and self.game.save
  local facing = (p and p.facing) or "down"
  local d = Map.DELTA[facing] or Map.DELTA.down
  local fx, fy = p.cellX + d[1], p.cellY + d[2]
  local blockIndex, blockId = self:blockIndexAt(fx, fy)
  return {
    save = save,
    party = (save and save.party) or {},
    mon = mon,
    facing = facing,
    facingX = fx, facingY = fy,
    facingColl = map:cellCollision(fx, fy),
    playerColl = map:cellCollision(p.cellX, p.cellY),
    upColl = map:cellCollision(p.cellX, p.cellY - 1),
    tileset = map.def and map.def.tileset,
    facingBlock = blockId,
    facingBlockIndex = blockIndex,
    environment = map.def and map.def.environment,
    -- EscapeRopeOrDig's .CheckCanDig also refuses on a zeroed dig triple;
    -- digFromMenu reads this rather than re-deriving the banked warp.
    canEscapeRope = self:escapeRopeTarget() ~= nil,
    playerState = self.playerState,
    strengthActive = self.strengthActive,
    -- FlashFunction tests wTimeOfDayPalset, not the map header, so a
    -- PALETTE_DARK map that FLASH has already lit refuses a second FLASH.
    dark = Palettes.isDarkness(map.def, self:hour(), self.flashUsed),
  }
end

-- CutDownTreeOrGrass / DisappearWhirlpool: one entry of the loaded map's block
-- buffer is overwritten, the tilemap is redrawn from it and GetMovementPermissions
-- reruns -- which is why a cut tree stops blocking the step immediately.
--
-- The original id is kept so setMap can put it back: the cart's buffer is
-- refilled from ROM by LoadMapAttributes on every map load, so a cut tree is
-- standing again the next time the map is walked into.
function World:replaceBlock(index, blockId)
  local map = self.map
  if not (map and index and blockId) then return false end
  local blocks = map.def and map.def.blocks
  if not (blocks and blocks[index]) then return false end
  local mapId = map.id
  local edits = self.blockEdits[mapId]
  if not edits then
    edits = {}
    self.blockEdits[mapId] = edits
  end
  if edits[index] == nil then edits[index] = blocks[index] end
  blocks[index] = blockId
  map.blocks = blocks
  self:refreshMapImages()
  -- Gen 1's four payload keys off OverworldState:replaceBlock.  Every Gen 2
  -- block edit lands here -- World:changeBlock's script `changeblock`, CUT,
  -- WHIRLPOOL and the map callbacks all call through it -- so bx/by are
  -- recovered from the flat buffer index the cart addresses blocks by, and
  -- `index` is carried alongside for a listener that wants the raw one.
  if Runtime.wants("world.block_replaced") then
    local zero = index - 1
    Runtime.emit("world.block_replaced", {
      mapId = mapId, bx = zero % map.width,
      by = math.floor(zero / map.width), block = blockId, index = index,
    })
  end
  return true
end

-- Drop every baked canvas of ONE map.  imageFor keys by map, daytime, COLOR
-- mode and cave-flicker phase, so a block edit invalidates a handful of entries
-- and there is no reason to throw the neighbours' bakes away with them.
function World:dropMapImages(mapId)
  if not mapId then return end
  local prefix = mapId .. "|"
  for key in pairs(self.mapImages) do
    if key:sub(1, #prefix) == prefix then self.mapImages[key] = nil end
  end
  -- The anim cell lists and the bake palettes ride the same keys.
  for _, store in ipairs({ self.animCells, self.bgSets }) do
    for key in pairs(store) do
      if key:sub(1, #prefix) == prefix then store[key] = nil end
    end
  end
  if self.connectionMaps then self.connectionMaps[mapId] = nil end
end

-- LoadMapAttributes' refill, for every map the session has edited.  Neighbour
-- strips share the same buffer on the cart, so a connection crossing reloads
-- them too: this runs on any setMap, seamless or not.
--
-- The bakes go with the blocks.  A canvas is baked off map.def.blocks and
-- cached under a key that knows nothing about them, so putting a CUT tree back
-- without dropping the stump's bake left the tree cut for the rest of the
-- session -- and a MAPCALLBACK_TILES map, whose blocks are rewritten on every
-- single load, would have frozen on whichever answer it baked first.
function World:restoreBlocks()
  local any = false
  for mapId, edits in pairs(self.blockEdits) do
    local def = self.maps and self.maps[mapId]
    local blocks = def and def.blocks
    if blocks then
      for index, original in pairs(edits) do
        blocks[index] = original
        any = true
      end
      self:dropMapImages(mapId)
    end
    self.blockEdits[mapId] = nil
  end
  return any
end

function World:restoreObjectSpawns()
  -- engine/overworld/map_setup.asm:78
  local spawns = self.objectSpawns
  if not spawns then return end
  for mapId, byIndex in pairs(spawns) do
    local def = self.maps and self.maps[mapId]
    local objects = def and def.objects
    if objects then
      for key, xy in pairs(byIndex) do
        local obj
        for _, row in ipairs(objects) do
          if (row.index or 0) == key then obj = row break end
        end
        if obj then
          obj.x, obj.y = xy[1], xy[2]
        end
        local npc = self.npcPool
          and self.npcPool[string.format("%s_obj_%d", mapId, key)]
        if npc then
          npc.cellX, npc.cellY = xy[1], xy[2]
          npc.px, npc.py = xy[1] * 16, xy[2] * 16
          npc.homeX, npc.homeY = xy[1], xy[2]
          npc.moving = false
          npc.progress = 0
          npc.targetX, npc.targetY = nil, nil
        end
      end
    end
    spawns[mapId] = nil
  end
end

-- Drop the loaded map's baked canvases and bake again.  Same shape as what
-- pollTimeOfDay does when the clock rolls the palette over; a block edit
-- invalidates the bake for the same reason a palette change does.  A world with
-- nothing baked yet (a headless test, or the first load of a session) has
-- nothing to refresh, and the one bake setMap is about to do covers it.
function World:refreshMapImages()
  if not self.mapImage then return false end
  self:dropMapImages(self.map and self.map.id)
  self.mapImage = self:imageFor(self.map.id)
  self:rebuildNeighbors()
  return true
end

-- UpdatePlayerSprite (data/sprites/player_sprites.asm ChrisStateSprites): the
-- player's sprite is a pure function of wPlayerState, which is what makes
-- getting on and off a Lapras a one-byte change rather than an animation.
function World:applyPlayerState(state)
  self.playerState = state or FieldMoves.PLAYER_NORMAL
  local name = FieldMoves.STATE_SPRITE[self.playerState] or PLAYER_SPRITE
  local def = self.sprites and self.sprites[name]
  if def and self.player then
    self.player:setSprite(def)
    self:applySpritePalette(self.player)
  end
end

-- ---- the seven effects ----------------------------------------------------

-- Script_Cut: GetPartyNickname, UseCutText, then CutDownTreeOrGrass.  The
-- block swap happens when the box closes, not when it opens, so the tree is
-- still standing behind the line that says it was cut.
function World:runCut(result)
  self:setNickname(result.mon)
  self:showText(Strings(result.text), function()
    self:replaceBlock(result.blockIndex, result.replacement)
    self:playSfx(SFX.PLACE_PUZZLE_PIECE_DOWN)
  end)
end

-- Script_UsedWhirlpool, which is Script_Cut with DisappearWhirlpool and
-- PlayWhirlpoolSound (a bare SFX.SURF) in place of the snip.
function World:runWhirlpool(result)
  self:setNickname(result.mon)
  self:showText(Strings(result.text), function()
    self:replaceBlock(result.blockIndex, result.replacement)
    self:playSfx(SFX.SURF)
  end)
end

-- Script_UseFlash: the text plays SFX.FLASH from inside itself
-- (UseFlashTextScript's text_asm), and BlindingFlash then sets
-- STATUSFLAGS_FLASH_F and reloads the palettes.  Setting the flag is all there
-- is to it: Palettes.daytimeFor already turns a flashed PALETTE_DARK map into
-- a NITE one, which is the cart's own .UsedFlash arm.
function World:runFlash(result)
  self:playSfx(SFX.FLASH)
  self:showText(Strings(result.text), function()
    self.flashUsed = true
    if self:applyPalettes() then self:refreshMapImages() end
  end)
end

-- UsedSurfScript: the line, then wPlayerState becomes the surf state, the
-- sprite follows it, the map music restarts (surfing has its own theme) and
-- SurfStartStep walks one slow step into the water.  Getting ON is a scripted
-- step, which is why it never rolls an encounter.
function World:runSurf(result)
  self:setNickname(result.mon)
  self:showText(Strings(result.text), function()
    self:applyPlayerState(result.state)
    local audio = self.game and self.game.data and self.game.data.audio
    if audio and audio.runtime and self.map then
      -- SpecialMapMusic (home/audio.asm:397)
      Music.playMap(self.game.data, self.map.id, nil,
                    FieldMoves.isSurfing(self.playerState), nil,
                    self:mapMusicSong(self.map.id))
    end
    if self.player and self.player.scriptStep then
      self.player:scriptStep(self.player.facing)
    end
    self.fieldMove = { phase = "step" }
  end)
end

-- Script_UsedStrength: SetStrengthFlag runs FIRST (callasm, before the text),
-- then "<mon> used STRENGTH!", the mon's cry, `pause 3`, and
-- "<mon> can move boulders."
function World:runStrength(result)
  self.strengthActive = true
  self.strengthMon = result.mon
  self:setNickname(result.mon)
  self:showText(Strings(result.text), function()
    self:playMonCry(result.mon)
    self.fieldMove = {
      phase = "strength", timer = STRENGTH_PAUSE_FRAMES, text = result.after,
    }
  end)
end

-- Script_UsedWaterfall: the line, SFX.BUBBLEBEAM, and then a loop of one
-- turn_waterfall UP step at a time.
--
-- .CheckContinueWaterfall writes wScriptVar = 0 while the player is STILL on a
-- waterfall tile and 1 once they are off it, and the script's `iffalse .loop`
-- loops on 0.  Read the flag the other way round and the climb stops on the
-- first step.
function World:runWaterfall(result)
  self:setNickname(result.mon)
  self:showText(Strings(result.text), function()
    self:playSfx(SFX.BUBBLEBEAM)
    self.fieldMove = { phase = "waterfall" }
    self:waterfallStep()
  end)
end

function World:waterfallStep()
  local p = self.player
  if not p then return end
  p.facing = "up"
  if p.scriptStep then p:scriptStep("up") end
end

-- callasm GetPartyNickname: {STRBUF} is the nickname of the mon CheckPartyMove
-- picked, and TextBox reads it back off game.stringBuffer.
function World:setNickname(mon)
  if not self.game then return end
  local name = (mon and (mon.nickname or mon.name or mon.species)) or ""
  self.game.stringBuffer = name
  -- engine/events/overworld.asm:1339
  if self.vm then self.vm.stringBuffer = name end
end

function World:playMonCry(mon)
  local data = self.game and self.game.data
  local cries = data and data.audio and data.audio.cries
  local species = mon and mon.species
  if not (cries and species and cries[species]) then return end
  self.lastSfx = Sound.playCry(data, species)
end

-- ---- the boulder ----------------------------------------------------------

function World.isStrengthBoulder(npc)
  local def = npc and npc.def
  return def ~= nil and def.movement == SPRITEMOVEDATA_STRENGTH_BOULDER
end

-- .CheckStrengthBoulder (engine/overworld/player_movement.asm), reached from
-- .CheckNPC when something is standing in the way.  With
-- BIKEFLAGS_STRENGTH_ACTIVE set and the object standing still, its facing is
-- pointed the way the player walked and BOULDER_MOVING_F goes up;
-- MovementFunction_Strength then steps it, but only if
-- CanObjectMoveInDirection agrees.
--
-- The player BUMPS either way: .CheckNPC's "2" is treated exactly like a
-- solid NPC, so the boulder moves and the player stays where they were.
function World:tryPushBoulder(dir, cx, cy)
  if not self.strengthActive then return false end
  local npc = self:npcAt(cx, cy)
  if not (npc and World.isStrengthBoulder(npc)) or npc.moving then
    return false
  end
  local d = Map.DELTA[dir]
  local tx, ty = cx + d[1], cy + d[2]
  if not self.map:isWalkable(tx, ty) then return false end
  for _, e in ipairs(self.entities or {}) do
    if e ~= npc and e.cellX == tx and e.cellY == ty then return false end
  end
  npc:scriptStep(dir)
  self:playSfx(SFX.STRENGTH)
  -- Gen 1's four payload keys.  Divergence, deliberate: Gen 1 emits from the
  -- scriptMove completion callback, once the boulder has settled; Gold's
  -- MovementFunction_Strength has no such callback, so this fires as the push
  -- is committed and x/y are the cell the boulder is stepping ONTO -- which is
  -- the same pair Gen 1's listener eventually sees.
  if Runtime.wants("world.boulder_moved") then
    Runtime.emit("world.boulder_moved", { mapId = self.map.id,
      npcId = (npc.def and npc.def.index or 0) + 1, x = tx, y = ty })
  end
  return true
end

-- ---- running one --------------------------------------------------------

-- QueueScript, as far as the port is concerned: the result the model handed
-- back is turned into the script that carries it out.
function World:runFieldMove(result)
  local action = result and result.action
  if action == "cut" then
    self:runCut(result)
  elseif action == "whirlpool" then
    self:runWhirlpool(result)
  elseif action == "flash" then
    self:runFlash(result)
  elseif action == "surf" then
    self:runSurf(result)
  elseif action == "strength" then
    self:runStrength(result)
  elseif action == "waterfall" then
    self:runWaterfall(result)
  elseif action == "fly" then
    self:openFlyMap()
  elseif action == "headbutt" then
    self:runHeadbutt(result.facingX, result.facingY, result.mon)
  elseif action == "sweetscent" then
    self:runSweetScent(result)
  elseif action == "escaperope" or action == "dig" then
    self:runDigEscape(result)
  elseif action == "teleport" then
    self:runTeleport(result)
  else
    return false
  end
  return true
end

-- .UsedEscapeRopeScript / .UsedDigScript (engine/events/overworld.asm
-- EscapeRopeOrDig): the used-item line -- GetPartyNickname fills {STRBUF} for
-- DIG, the rope addresses {PLAYER} -- then the shared warp tail.  The target
-- was resolved when the action was queued; a load the map churn has since
-- invalidated falls back to re-resolving, and to nothing at worst.
function World:runDigEscape(result)
  self:setNickname(result.mon)
  self:showText(Strings(result.text), function()
    local destMapId, destWarp = result.destMap, result.destWarp
    if not (destMapId and destWarp) then
      destMapId, destWarp = self:escapeRopeTarget()
    end
    if destMapId then self:runEscapeWarp(destMapId, destWarp) end
  end)
end

-- TeleportFunction's .TeleportScript: the return line, then WarpToSpawnPoint
-- with `newloadmap MAPSETUP.TELEPORT` -- the same landing a whiteout takes,
-- which is exactly what World:warpToSpawn resolves (blackoutmod override
-- first, then the SPAWN_* table).  PLAYER_NORMAL first, so a teleport off a
-- bike arrives on foot the way `loadvar VAR.MOVEMENT, PLAYER_NORMAL` leaves
-- it.  The teleport spin, like the dig spin, is sprite work and not ported.
function World:runTeleport(result)
  self:setNickname(result.mon)
  self:showText(Strings(result.text), function()
    self:playSfxNamed("Sfx_WarpTo", SFX.WARP_TO)
    self:applyPlayerState(FieldMoves.PLAYER_NORMAL)
    self:runMapSetup(MAPSETUP.TELEPORT, function()
      self:warpToSpawn()
      return true
    end)
  end)
end

-- The block a cut or whirlpool result edits.  The model works in block IDs
-- because that is what field_move_blocks.asm is written in; the index comes
-- from the context that produced the result, so it is stapled on here rather
-- than threaded through the pure half.
local function withBlockIndex(result, ctx)
  if result and result.replacement then
    result.blockIndex = ctx.facingBlockIndex
  end
  if result then
    result.facingX, result.facingY = ctx.facingX, ctx.facingY
  end
  return result
end

-- PokemonActionSubmenu's MONMENU_FIELD_MOVE arm: the party list has already
-- chosen the mon, so the badge is checked with the noisy CheckBadge and the
-- move itself is taken on trust.  Returns the result so the caller (the party
-- menu) knows whether it was refused.
--
-- A success is QUEUED, not run.  Every *Function ends in QueueScript and the
-- queued script only runs once the menus are gone -- which is the whole point:
-- the party list is still on the screen at the moment CUT is chosen, and
-- "<mon> used CUT!" belongs over the overworld.  Try*OW is the other half of
-- that distinction and uses CallScript, which runs on the spot.
function World:useFieldMove(moveId, mon)
  if not (self.map and self.player) then return nil end
  if self.battleActive or self:busy() then
    return { ok = false, text = FieldMoves.TEXT.CANT_USE_HERE }
  end
  local ctx = self:fieldContext(mon)
  local result = withBlockIndex(FieldMoves.fromMenu(moveId, ctx), ctx)
  result.mon = result.mon or mon
  if result.ok then
    self.queuedFieldMove = result
  elseif result.text then
    self:showText(Strings(result.text))
  end
  return result
end

-- The queued script, once the world owns the frame again.
function World:runQueuedFieldMove()
  local queued = self.queuedFieldMove
  if not queued or self:busy() then return false end
  self.queuedFieldMove = nil
  return self:runFieldMove(queued)
end

-- TryTileCollisionEvent's arms, in its order, each one a "did this take the A
-- press" answer.  A result with `ask` opens AskXScript's yesorno first; one
-- without runs (or refuses) straight away.
function World:runOverworldFieldMove(result)
  if not result or not result.took then return false end
  if not result.ok then
    if result.text then self:showText(Strings(result.text)) end
    return true
  end
  if result.ask then
    self:showText(Strings(result.ask), function()
      self:askYesNo(function(yes)
        -- AskCutScript's `iffalse .declined` and friends: NO is a plain
        -- closetext, and CUT's own map check only happens after the YES.
        if yes and result.action then self:runFieldMove(result) end
      end)
    end)
    return true
  end
  self:runFieldMove(result)
  return true
end

function World:tryCutOW()
  local ctx = self:fieldContext()
  if not Permissions.isCutTree(ctx.facingColl) then return false end
  return self:runOverworldFieldMove(
    withBlockIndex(FieldMoves.tryCutOW(ctx), ctx))
end

function World:tryWhirlpoolOW()
  local ctx = self:fieldContext()
  if not Permissions.isWhirlpool(ctx.facingColl) then return false end
  return self:runOverworldFieldMove(
    withBlockIndex(FieldMoves.tryWhirlpoolOW(ctx), ctx))
end

function World:tryWaterfallOW()
  local ctx = self:fieldContext()
  if not Permissions.isWaterfall(ctx.facingColl) then return false end
  return self:runOverworldFieldMove(
    withBlockIndex(FieldMoves.tryWaterfallOW(ctx), ctx))
end

-- TrySurfOW is the last arm and the only one with no tile test of its own:
-- anything the earlier arms did not claim reaches it, and it fails silently
-- unless the facing tile really is water.
function World:trySurfOW()
  local ctx = self:fieldContext()
  return self:runOverworldFieldMove(
    withBlockIndex(FieldMoves.trySurfOW(ctx), ctx))
end

-- AskStrengthScript, which a boulder's own script jumps to (jumpstd
-- StrengthBoulderScript).  Reached by talking to a boulder, not by walking
-- into one -- the walk is the push, and this is the offer to switch STRENGTH
-- on in the first place.
function World:tryStrengthOW()
  local ctx = self:fieldContext()
  return self:runOverworldFieldMove(
    withBlockIndex(FieldMoves.tryStrengthOW(ctx), ctx))
end

-- ---- fly ------------------------------------------------------------------

-- FlyMap's region split, which reads the PLAYER's landmark and nothing else:
-- the first 46 landmarks are Johto, the rest Kanto.
function World:region()
  local landmarks = self.landmarks and self.landmarks.landmarks
  local id = self.map and self.map.def and self.map.def.landmark
  local entry
  if type(id) == "string" then
    entry = landmarks and landmarks[id]
  elseif type(id) == "number" then
    local order = self.landmarks and self.landmarks.order
    entry = order and landmarks and landmarks[order[id + 1]]
  end
  local index = (entry and entry.index) or (type(id) == "number" and id) or 0
  if index == 94 then return "johto" end -- LANDMARK_FAST_SHIP
  return index >= 46 and "kanto" or "johto"
end

function World:flyPoints()
  return FieldMoves.flyPoints(
    self.game and self.game.save, self.landmarks, self:region())
end

-- .FlyScript: WarpToSpawnPoint, then `newloadmap MAPSETUP.TELEPORT` brings the
-- map up with the player back in PLAYER_NORMAL.  MapSetupScript_Teleport opens
-- on FadeOutToWhite and falls through into _Warp, so flying is bracketed by the
-- same pair of fades a door is, which is where the two fly animations ride:
-- `lift` below hands them to World:updateMapSetup.
function World:flyTo(spawnId)
  local spawn = self.landmarks and self.landmarks.spawns
    and self.landmarks.spawns[spawnId]
  if not (spawn and spawn.map and self.maps and self.maps[spawn.map]) then
    return false
  end
  self:applyPlayerState(FieldMoves.PLAYER_NORMAL)
  local ok = self:runMapSetup(MAPSETUP.TELEPORT, function()
    return self:setMap(spawn.map, spawn.x, spawn.y, "down")
  end)
  -- FlyFromAnim / FlyToAnim ride the setup script's own two fades: the take-off
  -- lift under the fade out, the landing under the fade in.
  if self.mapSetup then self.mapSetup.lift = true end
  return ok
end

-- _FlyMap: the town map with the cursor locked to visited flypoints, A takes
-- the one under it and B leaves.
--
-- The screen itself is src/ui/gen2/Pokegear.lua's fly mode (Pokegear.FLY_MAP),
-- which draws the same town map the MAP card does with TownMapBubble's
-- "Where?" plate over it instead of the card strip.  A run with no love at all
-- (a headless probe) has no screen to push, so the destinations are offered
-- one at a time through the same yesorno box every other field move uses.
function World:openFlyMap()
  local points = self:flyPoints()
  if #points == 0 then return false end
  -- Loaded on demand and through pcall: a headless run has no love, and this
  -- is the only place in the world that reaches for a screen module by hand.
  local okGear, Pokegear = pcall(require, "src.ui.gen2.Pokegear")
  if okGear and Pokegear.FLY_MAP and self.game and self.game.stack then
    Screens.push(self.game, "Gen2Pokegear", {
      save = self.game.save,
      currentLandmark = self:currentLandmarkId(),
      fly = points,
      onFly = function(spawnId)
        self.game.stack:pop()
        self:flyTo(spawnId)
      end,
      onClose = function() self.game.stack:pop() end,
    })
    return true
  end
  self:askFlyPoint(points, 1)
  return true
end

function World:askFlyPoint(points, index)
  local row = points[index]
  if not row then return end
  local name = (row.name or row.landmark):gsub("\n", " ")
  self:showText(Strings(FieldMoves.TEXT.ASK_FLY_TO, name), function()
    self:askYesNo(function(yes)
      if yes then
        self:flyTo(row.spawn)
      else
        self:askFlyPoint(points, index + 1)
      end
    end)
  end)
end

function World:currentLandmarkId()
  local def = self.map and self.map.def
  local id = def and def.landmark
  if type(id) == "string" then return id end
  local order = self.landmarks and self.landmarks.order
  return order and id and order[id + 1] or nil
end

-- ---- the per-frame half ---------------------------------------------------

-- The tail of the scripts above: a `pause`, the surf step landing, and the
-- waterfall climb's loop.  Ticked alongside the fishing cast and the tree
-- shake for the same reason they are -- on the cart these are script commands,
-- so the world is frozen for them.
function World:updateFieldMove()
  local st = self.fieldMove
  if not st then return end
  if self.textbox or self.choicebox then return end
  if st.timer and st.timer > 0 then
    st.timer = st.timer - 1
    return
  end
  if st.phase == "strength" then
    self.fieldMove = nil
    if st.text then self:showText(Strings(st.text)) end
    return
  end
  if self.player and self.player.moving then return end
  if st.phase == "waterfall" then
    -- Still on a waterfall tile: another turn_waterfall UP.
    local coll = self.map:cellCollision(self.player.cellX, self.player.cellY)
    if FieldMoves.waterfallContinues(coll) then
      self:waterfallStep()
      return
    end
  end
  self.fieldMove = nil
end

-- Which song this battle fights to (engine/battle/start_battle.asm
-- PlayBattleMusic), and the facts BattleMusic needs to pick it: the class the
-- opponent belongs to, the member inside it (only RIVAL2 reads that), the
-- map's landmark for RegionCheck, and the clock.
function World:battleMusicContext(opts)
  local members = self.constants and self.constants.trainerClassMembers
  local trainer = opts and opts.trainer
  return {
    class = trainer and trainer.classId,
    member = trainer and trainer.memberId,
    members = trainer and trainer.classId and members
      and members[trainer.classId] or nil,
    landmark = self.map and self.map.def and self.map.def.landmark,
    -- PlayBattleMusic reads wTimeOfDay (engine/battle/start_battle.asm:24),
    -- not the map's pinned palette set.
    daytime = self.tod,
  }
end

function World:playBattleMusic(opts)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if not (audio and audio.songs) then return nil end
  local song = BattleMusic.battleSong(self:battleMusicContext(opts))
  if not (song and audio.songs[song]) then return nil end
  Music.play(data, song, true, { reason = "battle" })
  return song
end

-- DoBattleTransition.  Returns true when the wipe took the screen, false when
-- there is nothing to wipe (a headless run, or a battle started before the map
-- is up) and the battle should just come straight in.
function World:pushBattleTransition(battle, opts, onDone)
  local game = self.game
  if not (game and game.stack and self.map) then return false end
  Screens.push(game, "Gen2BattleTransition", {
    world = self,
    trainer = opts and opts.trainer and true or false,
    environment = self.map.def and self.map.def.environment,
    playerLevel = battle and battle.player and battle.player.level,
    enemyLevel = battle and battle.enemy and battle.enemy.level,
    onDone = onDone,
  })
  return true
end

-- Push the battle screen.  Kept here rather than in Game2 so a trainer
-- script and a grass step start a battle the same way.
--
-- The order is the cart's: DoBattleTransition owns the screen first, and only
-- when it has finished blacking the overworld out does the battle screen come
-- up.  PlayBattleMusic runs BEFORE the transition, which is why the battle
-- theme is already going while the wipe is still spinning.
function World:startBattle(opts, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone("win") end
    return false
  end
  local battle = Battle.new({
    data = game.data,
    -- BATTLETYPE_TUTORIAL fights with an EMPTY party: engine/battle/core.asm
    -- jumps straight to BattleMenu without a send-out, so the DUDE's demo has
    -- no player mon at all and the caller passes its own party in.
    party = opts.party or (game.save and game.save.party) or {},
    wild = opts.wild,
    trainer = opts.trainer,
    -- wMoney and wMomsMoney, for WinTrainerBattle's payout
    -- (src/battle/gen2/Prize.lua).  The battle writes both accounts itself,
    -- the way the cart's own trainer-defeated arm does, so a fight that never
    -- comes back through the script still pays.
    save = game.save,
    -- BATTLETYPE_ROAMING: the save slot whose HP byte the end of the battle
    -- writes back.  Only World:tryWildEncounter sets it.
    roaming = opts.roaming,
    -- wBattleType, when the script armed one: the FORCESHINY / TRAP
    -- no-escape rules live in Battle:tryRun and the force-switch handler.
    battleType = opts.battleType,
  })
  self:playBattleMusic(opts)
  local function pushBattle()
    -- wBattleMode, as far as the overworld is concerned: a battle screen this
    -- world pushed is up.  The PACK opened from inside one must not take the
    -- field path, because a rod is ITEMMENU_NOUSE in battle
    -- (data/items/attributes.asm) and the field path would fish from under it.
    self.battleActive = true
    Screens.push(game, "Gen2BattleState", {
      battle = battle,
      save = game.save,
      music = self:battleMusicContext(opts),
      -- BATTLETYPE_CONTEST: the park ball menu, the held catch and the draw on
      -- the last ball.  Only World:tryContestEncounter sets it.
      contest = opts.contest,
      -- BATTLETYPE_TUTORIAL: the DUDE's back-pic, no player HUD, the forced
      -- POKE BALL and the throw that cannot fail.  Only
      -- World:startCatchTutorial sets it.
      tutorial = opts.tutorial,
      onDone = function(outcome)
        -- WildBattleScript's reloadmapafterbattle (engine/overworld/events.asm:1158-1162)
        self.wildCooldown = 5
        self.battleActive = nil
        game.stack:pop()
        -- wBattleResult (constants/battle_constants.asm): WIN 0, LOSE 1, DRAW 2.
        -- The port never forfeits or draws a battle, so "lose" is the only
        -- other outcome startBattle's onDone hands back; VAR.BATTLERESULT
        -- reads this back masked with ~BATTLERESULT_BITMASK, same as the cart.
        self.lastBattleResult = (outcome == "lose") and 1 or 0
        -- BattleEnd_HandleRoamMons, which runs on the way out of EVERY wild
        -- battle: this one banks the beast's HP and moves it, and any other
        -- wild battle takes the 1-in-16 `.not_roaming` roll that moves them
        -- anyway.  Before the loss warp, because the walk is computed against
        -- the map the player is standing on and the warp is about to change it
        -- to the spawn point.
        if battle.wild then
          self:roamMonsAfterBattle(battle.roaming, outcome,
            battle.enemy and battle.enemy.hp)
          -- Script_reloadmapafterbattle's `.was_wild` arm: `bit
          -- BATTLERESULT_BOX_FULL, a / jr z, .done`, then a LoadMemScript of
          -- Script_SpecialBillCall (engine/overworld/scripting.asm:1097-1104),
          -- which is `callasm .LoadBillScript` -- LoadCallerScript with
          -- e = PHONE_BILL -- falling into Script_ReceivePhoneCall
          -- (engine/phone/phone.asm:441-446).  BattleState sets boxFilled
          -- exactly where .SendToPC sets the bit.
          --
          -- NOT one of the SPECIALCALL_* rows, so Phone.queueSpecialCall is the
          -- wrong door: this is a received call wearing Bill's own contact and
          -- his CALLER script.  LoadMemScript is a deferral, which is what
          -- World:queuedScript is here: the ring lands on the first overworld
          -- frame after the reload rather than over the battle screen.  It also
          -- carries no `pause 30`, unlike the special-call wrappers.
          if battle.boxFilled then
            local Phone = require("src.core.gen2.Phone")
            local call = Phone.loadCallerScript(
              Phone.PHONECONTACT_BILL, "incoming", "caller")
            if self.vm and call.scriptKey
                and self.vm.scripts[call.scriptKey] then
              self.vm.curPhoneCaller = call.contact
              local name, className = Phone.contactName(call.contact,
                game.data and game.data.trainers)
              self.queuedScript =
                require("src.core.gen2.PhoneRing").script(call, name, className)
            end
          end
        end
        -- A loss warps home with a healed party, the way a whiteout does --
        -- because it IS one: Script_reloadmapafterbattle's `cp LOSE` jumps
        -- into Script_BattleWhiteout (engine/events/whiteout.asm), which is
        -- Script_Whiteout with a different BG map call in front of it.  So
        -- the losing half of the wallet goes here too, in the cart's order:
        -- HealParty, then HalveMoney, then GetWhiteoutSpawn, then the warp.
        -- The Bug Contest is the one exception the script itself carries
        -- (`checkflag ENGINE_BUG_CONTEST_TIMER / iftrue .bug_contest` skips
        -- both callasms), so a wipe in the park costs nothing.
        --
        -- BATTLETYPE.CANLOSE is the other exception, and it is the battle
        -- engine's own: LostBattle (engine/battle/core.asm) prints the loss
        -- text for this type and returns with the player exactly where they
        -- fought, and maps/CherrygroveCity.asm follows the battle with
        -- `reloadmap` and its .AfterYourDefeat arm -- the rival's shove and
        -- walk-off play at the battle site, and `special HealParty` at
        -- .FinishRival is what heals the party, not a whiteout.  Warping here
        -- moved the loser to the spawn point and then ran that walk-off over
        -- whatever stood there.
        if outcome == "lose" and opts.battleType ~= BATTLETYPE.CANLOSE then
          self:healParty()
          if not BugContest.isActive(game.save) then
            CallAsm.run(self, "HalveMoney")
            CallAsm.run(self, "GetWhiteoutSpawn")
          end
          -- The second of the two blackout seams, same as Gen 1's pair (the
          -- poison walk in World:whiteOut is the other), and guarded for the
          -- same reason its twin is.
          if Runtime.wants("world.blacked_out") then
            Runtime.emit("world.blacked_out",
              { save = game.save, healTarget = self:healPoint() })
          end
          self:warpToSpawn()
        end
        -- RestartMapMusic: the map theme comes back with the overworld, over
        -- whatever the battle left playing (the victory jingle loops until
        -- exactly here).  Unconditional, because the one-shot
        -- wDontPlayMapMusicOnReload the Sudowoodo and Snorlax battles set is
        -- not consumed here at all: `dontrestartmapmusic` is the command AFTER
        -- `startbattle` (maps/CherrygroveCity.asm:124-126), so it has not even
        -- run yet, and it is the `reloadmap` behind it that owns the silence
        -- (World:forceMapMusic).  Reading the flag here instead left it set
        -- with nothing to consume it, and the NEXT battle -- very often the
        -- repeatable Route 29 catch tutorial -- ended with the map music
        -- stopped for good.  A wild encounter has no reload behind it and
        -- still needs this restore.
        self:restoreMapMusic()
        -- BugCatchingContestBattleScript's own tail, which runs after
        -- `reloadmapafterbattle`: out of park balls sends the player back to
        -- the gate rather than back into the grass.
        if opts.contest and self:bugContestBattleOver() then return end
        -- Script_reloadmapafterbattle's .notblackedout arm: `bit
        -- BATTLESCRIPT_WILD_F, d` is SET for a trainer (Script_loadtrainer
        -- writes (1 << 7) | 1, Script_loadwildmon only (1 << 7) -- the flag's
        -- name reads backwards), so it is a won TRAINER battle and nothing
        -- else that gives Mom a chance to spend the savings.
        if opts.trainer and outcome ~= "lose" then self:momTriesToBuy() end
        -- A scripted battle resumes the VM here; the trainer flag and the
        -- after-battle text are the commands waiting on the other side.
        if onDone then onDone(outcome) end
      end,
    })
  end
  local transition = self:pushBattleTransition(battle, opts, pushBattle)
  if not transition then pushBattle() end
  return true
end

-- wWinTextPointer / wLossTextPointer (home/trainers.asm:120), overwritten by
-- `winlosstext` (engine/overworld/scripting.asm:651)
function World:trainerWinLossText()
  local vm = self.vm
  if not vm then return nil, nil end
  local obj = vm.trainerObject or {}
  local text = self.text or {}
  -- `winlosstext` writes BOTH pointers; a 0 argument destroys the struct
  -- value rather than falling back to it (engine/overworld/scripting.asm:651)
  local winKey, lossKey
  if vm.winLossArmed then
    winKey, lossKey = vm.winTextOverride, vm.lossTextOverride
  else
    winKey, lossKey = obj.winText, obj.lossText
  end
  return winKey and text[winKey] or nil, lossKey and text[lossKey] or nil
end

-- `startbattle` from a script: a trainer record (class + member) or a
-- loadwildmon pair.  The VM is parked on the yield until onDone fires, so the
-- rest of the trainer script (flag set, after-battle text) runs on return.
function World:startScriptedBattle(record, wild, onDone)
  local data = self.game and self.game.data
  local opts = {}
  if record then
    -- The battle screen names a trainer the way the cart does: class then
    -- name, "YOUNGSTER JOEY".
    local display = record.name
    if record.className and record.className ~= "" then
      display = record.className .. " " .. (record.name or "")
    end
    local bareName = record.name
    -- PlaceEnemysName (home/text.asm:327), which is what the <ENEMY> character
    -- resolves to: with wTrainerClass RIVAL1 or RIVAL2 it prints wRivalName
    -- ALONE, no class prefix and no parties-table name, because every rival row
    -- in data/trainers/parties.asm literally carries `db "?@"`.  wRivalName is
    -- what `special NameRival` (maps/ElmsLab.asm:515) wrote; before that screen
    -- has been through it still holds InitializeNPCNames' "???", which is the
    -- name the Cherrygrove theft battle prints, so "???" is the fallback here
    -- and NOT NameRival's own SILVER default.
    -- record.className is deliberately left alone: it is the class key
    -- Palettes.trainerColors and BattleMusic read, not a display string.  So is
    -- Trainers.lookup's own name -- GetTrainerName (engine/battle/
    -- read_trainer_party.asm:326) has no rival arm, so `gettrainername` really
    -- does answer "?".
    if record.classId == "RIVAL1" or record.classId == "RIVAL2" then
      local save = self.game and self.game.save
      display = (save and save.rival and save.rival.name) or "???"
      bareName = display
    end
    opts.trainer = {
      class = record.class,
      -- The class and member CONSTANTS (RIVAL2, RIVAL2_2_CHIKORITA), which is
      -- what PlayBattleMusic's ladder compares against.
      classId = record.classId,
      memberId = record.id,
      name = display,
      trainerName = bareName,
      className = record.className,
      party = Trainers.party(data, record),
      -- TRNATTR_BASE_REWARD, the third byte of the class's seven-byte
      -- attributes row.  ComputeTrainerReward multiplies it by the LAST
      -- party row's level, which is why the party above and this byte have
      -- to travel together.
      baseMoney = record.baseMoney,
      -- The rest of the class's attributes row (data/trainers/attributes.asm):
      -- the AI personality bytes AIActionCount / TRNATTR_AI_MOVE_WEIGHTS reads
      -- through Ai.flagsOf, and the two TRNATTR_ITEM slots AI_TryItem may
      -- reach for.  Trainers.lookup already builds both -- `items` as a fresh
      -- copy, precisely so a battle using one up does not empty the class
      -- record -- and this is the only place a scripted battle is built, so
      -- leaving them off here is what made every trainer in the game fight
      -- with no personality and no potions.
      attributes = record.attributes,
      items = record.items,
    }
    -- wWinTextPointer / wLossTextPointer, read by PrintWinLossText on the
    -- battle screen (home/trainers.asm:230) (#1512)
    opts.trainer.winText, opts.trainer.lossText = self:trainerWinLossText()
  elseif wild and wild.species then
    local id, def = speciesByIndex(data and data.pokemon, wild.species)
    -- InitEnemyMon `.NotRoaming` / BATTLETYPE.FORCESHINY: the DV pair is
    -- forced to ATKDEFDV_SHINY $EA / SPDSPCDV_SHINY $AA (Attack 14, the
    -- rest 10) before stats are built, which is the whole of what makes the
    -- Red Gyarados red -- and caught, it keeps the DVs and stays shiny.
    local monOpts
    if self:battleType() == BATTLETYPE.FORCESHINY then
      monOpts = { dvs = { attack = 14, defense = 10, speed = 10,
        special = 10 } }
    end
    opts.wild = id and Mon.new(data, id, wild.level or 5, monOpts) or nil
    -- InitEnemyMon's `.WildItem` / BATTLETYPE.FORCEITEM: Item1 is handed over
    -- unconditionally, no roll, which is the only wild-item path modeled --
    -- see Mon.new's own note on why the general 25%/8% roll is not.  Read
    -- here rather than after startBattle, because scriptVars[VAR.BATTLETYPE]
    -- is cleared the moment this function hands off to it.
    if opts.wild and self:battleType() == BATTLETYPE.FORCEITEM then
      local given = def and def.items and def.items[1]
      if given then opts.wild.item = given end
    end
  end
  if not (opts.trainer and #opts.trainer.party > 0) and not opts.wild then
    if onDone then onDone("win") end
    return false
  end
  -- wBattleType, which `writevar VAR.BATTLETYPE / loadvar BATTLETYPE_*` armed:
  -- FORCEITEM 10 (Lugia, Ho-Oh, the Red Gyarados), FORCESHINY 7 (Lake of Rage),
  -- TRAP 9 (the Rocket base), CANLOSE 1 (the Cherrygrove rival).  It is a
  -- ONE-SHOT on the cart -- BattleStart_TrainerBattle / StartWildBattle reset
  -- it -- so the value is taken and cleared here and handed to the battle,
  -- which is the half that still has to act on each case.
  opts.battleType = self:battleType()
  self.scriptVars[VAR.BATTLETYPE] = nil
  return self:startBattle(opts, onDone)
end

-- `catchtutorial BATTLETYPE_TUTORIAL`: CatchTutorial (engine/events/
-- catch_tutorial.asm) around a real battle.  The name swap, the DUDE's pack
-- and the option override live in src/core/gen2/CatchTutorial.lua; the battle
-- itself is the ordinary wild path with an empty party, which is what makes it
-- start on the battle menu with no mon out.
--
-- The wild mon is the one the `loadwildmon RATTATA, 5` in front of the command
-- left behind, and it is built through Mon.new like every other Gen 2 party
-- member so it arrives with a real moveset and real stats.
function World:startCatchTutorial(wild, battleType, onDone)
  local game = self.game
  local data = game and game.data
  local save = game and game.save
  local mon
  if wild and wild.species then
    local id = speciesByIndex(data and data.pokemon, wild.species)
    mon = id and Mon.new(data, id, wild.level or 5) or nil
  end
  if not mon then
    -- No wild mon means the script never ran `loadwildmon`, which no reachable
    -- `catchtutorial` does.  Hand the script straight back rather than opening
    -- an empty battle.
    if onDone then onDone() end
    return false
  end
  local state = CatchTutorial.begin(save, game and game.options)
  return self:startBattle({
    wild = mon,
    -- The DUDE has no mon of his own: the battle opens on the menu.
    party = {},
    tutorial = true,
    battleType = battleType or CatchTutorial.BATTLETYPE_TUTORIAL,
  }, function()
    CatchTutorial.finish(save, game and game.options, state)
    if onDone then onDone() end
  end)
end

-- Every `loadtrainer` and every `gettrainername` comes through here, which is
-- why the CAL2 redirect lives in TrainerHouse.lookup rather than at the
-- Trainer House's own call site: ReadTrainerParty tests the class before it
-- indexes the parties table, so the redirect has to sit in front of the table
-- for anything that can name CAL2, not just for that one script.
function World:trainerParty(class, member)
  return TrainerHouse.lookup(self.game and self.game.data
    and self.game.data.trainers, self.game and self.game.save, class, member)
end

-- MomTriesToBuySomething (engine/events/mom_phone.asm), reached from the
-- trainer arm of `reloadmapafterbattle`.  src/core/gen2/MomShopping.lua owns
-- the two shopping lists and the balance walk; this is the map half plus the
-- call itself.
--
-- The cart does not SPEAK here: it `LoadMemScript`s the phone call and lets
-- the overworld pick it up, which is what wMapReentryScriptQueueFlag at the
-- top of the routine is guarding against.  World:queuedScript is that same
-- deferral -- runQueuedScript drains it on the first frame the overworld owns
-- with no text box open -- so the four lines land after the trainer's own
-- after-battle script has finished rather than on top of it.
--
-- The ring is the call's own: MomTriesToBuySomething's .Script is `callasm
-- .ASMFunction / farsjump Script_ReceivePhoneCall` with Mom's pages queued in
-- wCallerContact, so the queued rows here ride the same ring chrome every
-- other incoming call does (src/core/gen2/PhoneRing.lua) with PHONE_MOM as
-- the caller.  The four writetexts are the whole of Mom_GetScriptPointer's
-- script either way.
function World:momTriesToBuy()
  local save = self.game and self.game.save
  if not save then return nil end
  local def = self.map and self.map.def
  local purchase = MomShopping.tryBuy(save, {
    events = self.events,
    data = self.game and self.game.data,
    -- RandomRange returns 0..n-1.
    random = function(n) return math.random(n) - 1 end,
    -- GetMapPhoneService: a map with no reception `ret`s before the balance
    -- is looked at, so Mom simply tries again after the next trainer.
    phoneService = (def == nil) or (def.phoneService ~= false),
  })
  if not purchase then return nil end
  local script = {}
  for _, page in ipairs(MomShopping.pages(purchase)) do
    -- `rawtext`, not `writetext`: these six strings sit in data/text/
    -- common_1.asm behind a phone script the extractor never walks, so there
    -- is no text.lua key to name them by.
    script[#script + 1] = { op = "rawtext", text = page }
  end
  script[#script + 1] = { op = "end" }
  local Phone = require("src.core.gen2.Phone")
  if self.vm then self.vm.curPhoneCaller = Phone.PHONECONTACT_MOM end
  self.queuedScript = require("src.core.gen2.PhoneRing").script(
    { scriptKey = script },
    Phone.NON_TRAINER_NAMES[Phone.PHONECONTACT_MOM])
  -- A doll changes what stands in the bedroom, and the room is rebuilt from
  -- the flags on a MAP LOAD -- so nothing has to be dropped here, the same
  -- way Decorations' own menu leaves it to the PC's warp.
  return purchase
end

-- PlayTrainerEncounterMusic: the short jingle that plays while the trainer
-- walks up to you, one per class out of data/trainers/encounter_music.asm.
-- It is NOT the battle theme -- PlayBattleMusic replaces it a moment later
-- when the transition starts.
--
-- A cache built before the table was extracted has no `encounterMusic`, so the
-- old behaviour (the shared Johto trainer battle theme) is the fallback.
function World:playTrainerEncounterMusic(class)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if not (audio and audio.songs) then return end
  local entry = Trainers.classIndex(data.trainers)[class]
  local song = entry and entry.encounterMusic
  if song and song ~= "Music_Nothing" and audio.songs[song] then
    Music.play(data, song, true, { reason = "trainer_encounter" })
    return
  end
  for _, name in ipairs({ "Music_JohtoTrainerBattle",
      "Music_KantoTrainerBattle" }) do
    if audio.songs[name] then
      Music.play(data, name, true, { reason = "trainer_encounter" })
      return
    end
  end
end

-- showemote: the bubble sits one cell above the object for `frames` frames.
-- Drawn by World:draw over the map, so it rides the same camera as the NPC.
function World:showEmote(emote, object, frames)
  local sheet = self.emoteImages and self.emoteImages[
    self.emoteOrder and self.emoteOrder[(emote or 0) + 1]]
  -- LAST_TALKED (-2) is the object the script is about; everything else is a
  -- plain object id.
  local ent = (object == -2) and (self.talkNpc or self.trainerNpc)
    or self:objectEntity(object or 0)
  if not (sheet and ent) then return end
  self.emote = { image = sheet, entity = ent, left = frames or 30 }
end

-- HealMachineAnim (engine/events/heal_machine_anim.asm), the light show the
-- nurse runs between "we'll need your POKeMON" and "thank you for waiting".
--
-- .PC_ElmsLab_OAM / .HOF_OAM transcribed as screen positions (each dbsprite's
-- raw OAM bytes minus the hardware's 8/16 OAM origin).  The cart lays them
-- out at fixed screen coordinates because the player is always standing on
-- the machine's own talk cell, BG-aligned at (64,64) -- the same anchor
-- Camera:follow keeps -- so each element's world position is the player's
-- cell corner plus (sx - 64, sy - 64), and the overlay stays glued to the
-- machine at any zoom.
--
-- `machine` is the two $7c tiles .PC_LoadBallsOntoMachine places before the
-- party loop; `balls` fill one per party member in OAM order (top pair
-- first), the right column OAM_XFLIPped.  wScriptVar picks the table --
-- HEALMACHINE_POKECENTER 0, HEALMACHINE_ELMS_LAB 1 (the same table shifted
-- by `bcpixel 2, 4`), HEALMACHINE_HALL_OF_FAME 2 (all balls, fanning out
-- from the machine's centre line).
local HEAL_MACHINE_LAYOUT = {
  [0] = {
    machine = { { 26, 16 }, { 30, 16 } },
    balls = { { 24, 22 }, { 32, 22, true }, { 24, 27 }, { 32, 27, true },
      { 24, 32 }, { 32, 32, true } },
  },
  [2] = {
    balls = { { 73, 44 }, { 78, 44 }, { 69, 43 }, { 82, 43 },
      { 65, 41 }, { 85, 41 } },
  },
}
do
  local pc = HEAL_MACHINE_LAYOUT[0]
  local elm = { machine = {}, balls = {} }
  for i, t in ipairs(pc.machine) do
    elm.machine[i] = { t[1] + 16, t[2] + 32 }
  end
  for i, b in ipairs(pc.balls) do
    elm.balls[i] = { b[1] + 16, b[2] + 32, b[3] }
  end
  HEAL_MACHINE_LAYOUT[1] = elm
end

-- The special is BLOCKING: `onDone` is what resumes the script, so the
-- nurse's next line never comes up over the machine still running.  The
-- cart's first guard is `ld a, [wPartyCount] / and a / ret z`, and a cache
-- with no sheet (from before the extractor carried it) resumes the same way
-- rather than hanging the script.
function World:startHealMachineAnim(animType, onDone)
  local party = self.game and self.game.save and self.game.save.party
  local layout = HEAL_MACHINE_LAYOUT[animType or 0] or HEAL_MACHINE_LAYOUT[0]
  if not (party and #party > 0 and self.healMachineImage) then
    if onDone then onDone() end
    return
  end
  local p = self.player
  self.healAnim = {
    layout = layout,
    hof = animType == 2,
    balls = math.min(#party, #layout.balls),
    lit = 0, timer = 0, phase = "balls", flashes = 0, rotation = 0,
    px = p and p.cellX * 16 or 0,
    py = p and p.cellY * 16 or 0,
    onDone = onDone,
  }
end

-- One frame of the machine, on the cart's own timeline: each party member's
-- ball lands with SFX.SECOND_PART_OF_ITEMFINDER then DelayFrames 30, then
-- MUSIC_HEAL plays over .FlashPalettes8Times -- eight rotations of the OBJ
-- palette ten frames apart.  The Hall of Fame arm swaps the jingle for
-- SFX.GAME_FREAK_LOGO_GS and rings SFX.BOOT_PC once the flashing stops.
-- The special returns after the last flash's delay, which is when the balls
-- clear -- the cart leaves its OAM to the overworld redraw the ended script
-- allows, and this is that same moment.
function World:stepHealAnim()
  local ha = self.healAnim
  if not ha then return end
  ha.timer = ha.timer + 1
  if ha.phase == "balls" then
    if ha.lit == 0 or ha.timer >= 30 then
      ha.timer = 0
      if ha.lit < ha.balls then
        ha.lit = ha.lit + 1
        self:playSfxNamed("Sfx_SecondPartOfItemfinder",
          SFX.SECOND_PART_OF_ITEMFINDER)
      else
        ha.phase = "flash"
        if ha.hof then
          self:playSfxNamed("Sfx_GameFreakLogoGs", SFX.GAME_FREAK_LOGO_GS)
        else
          -- .PlayHealMusic.  playOnce hands the map its theme back when the
          -- jingle ends; the script's own `pause 30` + RestartMapMusic
          -- behind the special covers a cache whose song is missing.
          Music.playOnce(self.game.data, "Music_HealPokemon")
        end
      end
    end
  elseif ha.phase == "flash" then
    -- FlashPalettes8Times flashes FIRST and then delays, so the first
    -- rotation lands on the same frame the jingle starts.
    if ha.flashes == 0 or ha.timer >= 10 then
      ha.timer = 0
      if ha.flashes >= 8 then
        if ha.hof then
          self:playSfxNamed("Sfx_BootPc", SFX.BOOT_PC)
        end
        local done = ha.onDone
        self.healAnim = nil
        if done then done() end
        return
      end
      ha.flashes = ha.flashes + 1
      -- The CGB arm of .FlashPalettes rotates the four colours one slot per
      -- flash; 8 % 4 lands the palette back where it started, exactly the
      -- way the DMG arm's XOR does after an even count.
      ha.rotation = ha.flashes % 4
    end
  end
end

-- The overlay: OBJs on the cart, drawn over everyone the same way the emote
-- bubble is.  The flash is the palette rotation expressed as an rBGP-shaped
-- byte through GbcPalette.remap, so the DMG and CLASSIC colour modes keep a
-- visible flash instead of collapsing to their fixed shades.
function World:drawHealAnim(s, billboard)
  local ha = self.healAnim
  local img = self.healMachineImage
  if not (ha and img) then return end
  local G = love.graphics
  if not self.healMachineQuads then
    local w, h = img:getWidth(), img:getHeight()
    self.healMachineQuads = {
      machine = G.newQuad(0, 0, 8, 8, w, h), -- $7c, the machine's light
      ball = G.newQuad(8, 0, 8, 8, w, h),    -- $7d, one ball
    }
  end
  local cam = self.camera
  local ox, oy = ha.px - 64, ha.py - 64
  local function screen(sx, sy)
    return math.floor((ox + sx - cam.x) * s), math.floor((oy + sy - cam.y) * s)
  end
  local function body()
    local shaded = false
    local pal = self.healMachinePalette
    if pal and GbcPalette.available() then
      local byte = 0
      for i = 0, 3 do byte = byte + ((i + ha.rotation) % 4) * (4 ^ i) end
      shaded = GbcPalette.useRaw(
        GbcPalette.remap(GbcPalette.resolve(pal), byte))
    end
    G.setColor(1, 1, 1, 1)
    for _, t in ipairs(ha.layout.machine or {}) do
      local tx, ty = screen(t[1], t[2])
      G.draw(img, self.healMachineQuads.machine, tx, ty, 0, s, s)
    end
    for i = 1, ha.lit do
      local b = ha.layout.balls[i]
      if b then
        local bx, by = screen(b[1] + (b[3] and 8 or 0), b[2])
        G.draw(img, self.healMachineQuads.ball, bx, by, 0,
          b[3] and -s or s, s)
      end
    end
    if shaded then GbcPalette.clear() end
  end
  if billboard then
    local anchor = (ha.layout.machine or ha.layout.balls)[1]
    local fx, fy = screen(anchor[1] + 4, anchor[2] + 8)
    billboard(fx, fy, body)
  else
    body()
  end
end

-- The PokemonCenterPC / PlayersHousePC specials: push that PC's screen.
-- The script is parked on the VM's own resume, so the PC's own B closes it and
-- the rest of the script continues.
-- `opts.house` is _PlayersHousePC rather than PokemonCenterPC, and the two
-- are different screens on the cart: the center's is the whose-PC top menu
-- (src/ui/gen2/CenterPcMenu.lua), the bedroom's is the item PC alone
-- (src/ui/gen2/ItemPcMenu.lua, PLAYERSPC_HOUSE) with PLAYERSPCITEM_DECORATION
-- on its list and no box access.  The bedroom's `onDone` gets the c the cart
-- returns -- TRUE only if a decoration moved, which is what makes
-- PlayersHousePCScript take its `.Warp` arm.
function World:openPc(opts)
  opts = opts or {}
  local game = self.game
  if not (game and game.stack) then
    if opts.onDone then opts.onDone(false) end
    return false
  end
  Screens.push(game, opts.house and "Gen2ItemPcMenu" or "Gen2CenterPcMenu", {
    save = game.save,
    house = opts.house,
    events = self.events,
    onClose = function(changed)
      game.stack:pop()
      if opts.onDone then opts.onDone(changed and true or false) end
    end,
  })
  return true
end

-- ToggleDecorationsVisibility (PLAYERS_HOUSE_2F's MAPCALLBACK_NEWMAP).  Both
-- halves of each row land here: the sprite byte in wVariableSprites and the
-- object's own event flag, which is what decides whether the object is built
-- at all.
--
-- Called from a map callback, so it must not rebuild anything itself: setMap
-- has not laid the objects out yet when NEWMAP runs, and World:setVariableSprite
-- would rebuild people against the map being LEFT.
function World:toggleDecorationsVisibility()
  local state = Decorations.state(self.game and self.game.save)
  for _, row in ipairs(Decorations.visibility(state)) do
    self.events:set(row.flag, row.hidden)
    if not row.hidden then self.variableSprites[row.sprite] = row.byte end
  end
end

-- ToggleMaptileDecorations (the MAPCALLBACK_TILES one).  The blocks go through
-- World:changeBlock, so the bake this map already has is dropped and the edit
-- is undone by the next LoadMapAttributes -- which is right: the callback runs
-- again on every load and repaints from the same eight bytes.
function World:toggleMaptileDecorations()
  local state = Decorations.state(self.game and self.game.save)
  for _, tile in ipairs(Decorations.tiles(state)) do
    self:changeBlock(tile.x, tile.y, tile.block)
  end
  -- SetPosterVisibility, inline in the same routine: a bare wall is not
  -- readable, so the poster's BGEVENT_IFSET flag follows the slot.
  self.events:set(Decorations.EVENT_PLAYERS_ROOM_POSTER,
    Decorations.posterVisible(state))
end

-- Script_pokemart -> OpenMartDialog (engine/items/mart.asm).  The clerk's whole
-- conversation is one blocking screen on the cart, so the script parks on the
-- VM's resume and the mart's own QUIT is what lets the next command run --
-- exactly the arrangement openPc uses for the storage system.
function World:openMart(martType, martId, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone() end
    return false
  end
  Screens.push(game, "Gen2MartMenu", {
    save = game.save,
    items = game.data and game.data.items,
    marts = self.marts,
    martType = martType,
    martId = martId,
    -- text.lua carries the clerk's whole conversation, seeded by name.
    text = self.text,
    onClose = function()
      game.stack:pop()
      if onDone then onDone() end
    end,
  })
  return true
end

-- `loadmenu` then `verticalmenu` / `_2dmenu`: the static menu a script puts up.
-- The extractor follows the MenuHeader pointer now, so the header arrives with
-- its box, its flags and its item strings; a cache built before that has only
-- the raw address, and with nothing to draw the honest answer is the one
-- StaticMenuJoypad gives for B.
--
-- The menu is NOT opaque: the cart leaves the text box the script opened
-- underneath it (`opentext` / `writetext` / `loadmenu`), which is why the
-- vending machines read as a price list over a speech line.
function World:openScriptMenu(header, style, onChoose)
  local game = self.game
  local items = header and (header.items or header.gridItems)
  -- The balance box a `special` left standing (showCoins / showMoney above).
  -- Consumed here whether or not the menu opens: CloseWindow takes the box down
  -- with the menu, so it must not survive into the next one.
  local balance = self.scriptBalance
  self.scriptBalance = nil
  if not (game and game.stack) or not items or #items == 0 then
    if onChoose then onChoose(0) end
    return false
  end
  Screens.push(game, "Gen2ScriptMenu", {
    header = header,
    style = style,
    balance = balance,
    save = game.save,
    onChoose = function(index)
      game.stack:pop()
      if onChoose then onChoose(index) end
    end,
  })
  return true
end

-- `trade trade_id` -> NPCTrade (engine/events/npc_trade.asm), the whole
-- blocking conversation off data/events/npc_trades.asm.  The extractor emits
-- that table and the 5x3 TradeTexts block now, so all six trades have both
-- their rules and their lines; before, the command was a no-op.
--
-- NPCTrade writes no wScriptVar, so the script carries on either way and there
-- is nothing to answer.
function World:openNpcTrade(id, onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone() end
    return false
  end
  Screens.push(game, "Gen2TradeMenu", {
    trade = id,
    save = game.save,
    eventTables = self.eventTables,
    onClose = function()
      game.stack:pop()
      if onDone then onDone() end
    end,
  })
  return true
end

-- `elevator floor_list` -> Elevator (engine/events/elevator.asm).
--
-- Three things in order: find the row for the floor the player got in on
-- (wBackupMapNumber, which is the map they warped in FROM), ask which floor,
-- and then Elevator_GoToFloor -- which does not warp.  It writes the chosen
-- row's warp number and map into wBackupWarpNumber / wBackupMapGroup /
-- wBackupMapNumber, and the elevator's own door, a `warp_event` whose
-- destination warp is -1, reads them when the player walks out.
--
-- `.FindCurrentFloor` failing is `scf`: the command quits with no menu at all,
-- which is what happens if a script ever runs `elevator` somewhere that is not
-- in its own list.
function World:openElevator(floors, onDone)
  local game = self.game
  local rows = {}
  for _, row in ipairs(floors or {}) do
    if row.destMap and self.maps[row.destMap] then rows[#rows + 1] = row end
  end
  local origin
  for _, row in ipairs(rows) do
    if row.destMap == self.backupMapId then origin = row break end
  end
  if not (game and game.stack) or not origin then
    if onDone then onDone(nil) end
    return false
  end
  Screens.push(game, "Gen2ElevatorMenu", {
    floors = rows,
    currentMap = self.backupMapId,
    floorNames = self.eventTables.floorNames,
    onDone = function(row)
      game.stack:pop()
      if row then
        self.backupWarp = { warp = row.destWarp, map = row.destMap }
      end
      if onDone then onDone(row) end
    end,
  })
  return true
end

-- Pokecenter heal (the HealParty special): full HP, full PP, no status, for
-- every party member.  The cart does this in one pass over wPartyMons, and it
-- is also what a whiteout does before warping home.
function World:healParty()
  local save = self.game and self.game.save
  for _, mon in ipairs((save and save.party) or {}) do
    mon.hp = mon.maxHp or mon.hp
    mon.status = nil
    mon.statusTurns = nil
    for _, move in ipairs(mon.moves or {}) do
      if type(move) == "table" then move.pp = move.maxPp or move.pp end
    end
  end
end

-- The rival naming screen (the NameRival special, engine/events/specials.asm):
-- `farcall _NamingScreen` does not return until the keyboard closes, and only
-- then does InitName fall back to the version default for an empty entry -- so
-- the officer's "OK! So <RIVAL>" line always prints the freshly typed name.
-- `onDone` is that return: H.NameRival parks the script on it, and the screen's
-- close is what resumes the officer.
function World:nameRival(onDone)
  local game = self.game
  if not (game and game.stack) then
    if onDone then onDone() end
    return
  end
  local data = game.data or {}
  local sprites = data.gen2Sprites
  local rival = sprites and sprites.SPRITE_RIVAL
  Screens.push(game, "Gen2NamingScreen", {
    type = "rival",
    menuGfx = data.gen2MenuGfx,
    iconPath = rival and rival.image or nil,
    iconColors = data.gen2Palettes
      and Palettes.spritePalette(data.gen2Palettes, self.daytime or "DAY", rival)
      or nil,
    onDone = function(name)
      game.stack:pop()
      local save = game.save
      if save then
        save.rival = save.rival or {}
        -- NameRival ends on `ld hl, wRivalName / ld de, .DefaultName / call
        -- InitName`, and .DefaultName is "SILVER@" on Gold and "GOLD@" on
        -- Silver (engine/events/specials.asm:80-94).  The default has to be
        -- written
        -- HERE rather than ridden in from the seed: wRivalName starts as
        -- InitializeNPCNames' "???" (src/core/gen2/Save.lua), which is what the
        -- pre-naming Cherrygrove battle prints.
        --
        -- _InitString defines blank as "zero or more spaces followed by a
        -- null" (home/string.asm:6-30), so an entry of nothing but spaces --
        -- typeable, since the keyboard's blank cells are real characters --
        -- falls back exactly the same way an empty one does.
        if name and name:gsub(" ", "") ~= "" then
          save.rival.name = name
        else
          save.rival.name = self:gsVersion() == 1 and "GOLD" or "SILVER"
        end
      end
      if onDone then onDone(name) end
    end,
  })
end

-- home/map.asm LoadMapAttributes .SetSpawn, ported.  See the call site in
-- setMap for why it was missing and what that cost.  `def` is the map being
-- loaded; self.map is still the one being left.
function World:updateWhiteoutSpawn(def, mapId)
  if not def then return end
  local prev = self.map and self.map.def
  if not prev then return end
  -- CheckOutdoorMap on the map being left, CheckIndoorMap on the one being
  -- entered, then its tileset.  All three, in that order.
  if not (prev.environment == "ROUTE" or prev.environment == "TOWN") then
    return
  end
  if def.environment ~= "INDOOR" then return end
  if def.tileset ~= "TILESET_POKECENTER" then return end
  -- `ld a, [wPrevMapGroup] / ld [wLastSpawnMapGroup], a`: what is stored is the
  -- map being LEFT -- the town or route outside the door -- not the Pokecenter.
  -- data/maps/spawn_points.asm is keyed that way (`spawn PALLET_TOWN, 5, 6`),
  -- and it is what makes the Indigo Plateau centre work: it is entered from
  -- ROUTE_23, and SPAWN_INDIGO is ROUTE_23 (9,6).
  local save = self.game and self.game.save
  if save then save.blackoutMap = prev.id or mapId end
end

-- GetWhiteoutSpawn's answer WITHOUT taking it: where a whiteout would land,
-- as { map, x, y, spawn }, or nil when nothing resolves.  Split out of
-- warpToSpawn (which is now its only other caller) so world.blacked_out can
-- carry the same healTarget key Gen 1's OverworldState:healPoint fills, read
-- from one place rather than two that can drift.
function World:healPoint()
  local save = self.game and self.game.save
  -- wLastSpawnMapGroup / wLastSpawnMapNumber, written by `blackoutmod`, are
  -- read BEFORE the SPAWN_* table: the Fast Ship and Mr. Pokemon's house set
  -- them so that losing at sea or out past Cherrygrove does not respawn the
  -- player somewhere they cannot leave.
  local override = save and save.blackoutMap
  if override then
    -- GetWhiteoutSpawn's own lookup: the stored map is matched against
    -- SpawnPoints, and it is that row which carries the coordinates.  The table
    -- is keyed by the OUTDOOR map (`spawn PALLET_TOWN, 5, 6`), which is exactly
    -- what World:updateWhiteoutSpawn stores, so this resolves a Pokecenter
    -- visit to the right doorstep -- SPAWN_INDIGO is ROUTE_23 (9,6), the
    -- approach to the Plateau centre.
    local spawns = self.landmarks and self.landmarks.spawns
    if type(spawns) == "table" then
      for id, row in pairs(spawns) do
        if type(row) == "table" and row.map == override and self.maps[row.map]
        then
          return { map = row.map, x = row.x, y = row.y, spawn = id }
        end
      end
    end
    -- Not a spawn point: `blackoutmod`'s other users (the Fast Ship cabins)
    -- name maps that are not in the table at all, so fall back to the map
    -- itself rather than sending the player home from the middle of the sea.
    if self.maps[override] then
      local def = self.maps[override]
      local warp = def.warps and def.warps[1]
      return { map = override, x = (warp and warp.x) or 0,
               y = (warp and warp.y) or 0 }
    end
  end
  local spawnId = (save and save.spawn) or SPAWN_HOME
  local spawn = self.landmarks and self.landmarks.spawns
    and self.landmarks.spawns[spawnId]
  if not (spawn and spawn.map and self.maps[spawn.map]) then return nil end
  return { map = spawn.map, x = spawn.x, y = spawn.y, spawn = spawnId }
end

-- WarpToSpawnPoint: back to the last Pokecenter (or the bedroom before one is
-- visited), which is where a whiteout lands.
function World:warpToSpawn()
  local target = self:healPoint()
  if not target then return end
  self:setMap(target.map, target.x, target.y, "down")
end

function World:playCry(speciesIndex)
  local data = self.game and self.game.data
  if not data then return end
  local id = speciesByIndex(data.pokemon, speciesIndex)
  if id then
    self.lastSfx = Sound.playCry(data, id)
  end
end

function World:playSfx(sfxId)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if not audio then return end
  local name = audio.sfxOrder and audio.sfxOrder[(sfxId or 0) + 1]
  if name and audio.sfx and audio.sfx[name] then
    self.lastSfx = Sound.play(data, name)
  end
end

function World:playMusicId(musicId)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if not (audio and audio.runtime) then return end
  local name = audio.musicOrder and audio.musicOrder[(musicId or 0) + 1]
  -- Script_playmusic with MUSIC_NONE is how a script silences the map ahead
  -- of its own cue -- the nurse's `playmusic MUSIC_NONE` right before the
  -- heal machine -- so it is a real stop, not a skipped play.
  if (musicId or 0) == 0 or name == "Music_Nothing" then
    Music.stop()
    return
  end
  if name and audio.songs and audio.songs[name] then
    Music.play(data, name, true, { reason = "script_playmusic" })
  end
end

function World:tryCoordScript()
  if self:busy() or not self.map or not self.player or not self.vm then
    return false
  end
  if self.player.moving then return false end
  local scene = self:scene()
  local x, y = self.player.cellX, self.player.cellY
  for _, ev in ipairs(self.map.def.coordEvents or {}) do
    if ev.x == x and ev.y == y and (ev.sceneId or 0) == scene
        and ev.scriptKey then
      self.talkNpc = nil
      return self.vm:start(ev.scriptKey)
    end
  end
  return false
end

function World:trySceneScript()
  if not self.map or not self.vm then return false end
  local scene = self:scene()
  local scenes = self.map.def.sceneScripts
  local entry = scenes and scenes[scene]
  if not entry then
    -- Lua arrays are 1-based; scene 0 may live at scenes[0] or scenes[1] if
    -- extracted as a list.  Prefer explicit sceneId field.
    if type(scenes) == "table" then
      for _, s in pairs(scenes) do
        if type(s) == "table" and s.sceneId == scene and s.scriptKey then
          entry = s
          break
        end
      end
    end
  end
  local key = entry and (entry.scriptKey or entry.script)
  if type(key) == "number" then return false end
  if key then
    self.talkNpc = nil
    return self.vm:start(key)
  end
  return false
end

-- `stay` is the VM's one-command lookahead (Vm:textStays): the next script
-- command is `yesorno`, so this text ends in `done` and the cart never took the
-- box down before InitYesNoTextBoxParameters put the prompt over it.  The box
-- is left standing and World:askYesNo stacks the choice on THIS box, instead of
-- the box popping on a button press the cart never asked for and the question
-- being re-printed underneath the prompt.
--
-- `hold` is the cart's `pause` when that pause sits INSIDE the box rather than
-- after it: FindItemInBallScript is `writetext .FoundItemText / playsound
-- SFX.ITEM / pause 60 / itemnotify` (engine/events/misc_scripts.asm:13-17) and
-- none of those commands takes the box down.  It cannot be run as a VM `pause`
-- here, because Game2:update stops at the top state -- while ANY box is on the
-- stack the overworld and the VM under it do not tick at all -- so the wait has
-- to be counted by the box itself.  Frames, already doubled by Vm:pauseFrames
-- the way Script_pause's `ld c, 2 / call DelayFrames` doubles the operand.
function World:showText(body, onDone, stay, hold)
  local game = self.game
  -- The box a PREVIOUS `stay` left standing (TextBox's contract is "whoever
  -- pushed it owns the pop", src/render/TextBox.lua:40).  `yesorno` consumes it
  -- in World:askYesNo; the other consumer is the next page of the same cart
  -- MapTextbox -- FindItemInBallScript's itemnotify line, after the box has
  -- held through `playsound / pause 60`.  The pop and the push happen inside
  -- ONE frame, so no frame ever renders the bare overworld between two pages
  -- the cart never took a box down between; a frame that did would both tear
  -- the box down visibly and let Game2's play clock, which only pauses while a
  -- state is on the stack, come off pause mid-pickup.
  local held = self.stayedTextBox
  self.stayedTextBox = nil
  if not game or not game.stack then
    if onDone then onDone() end
    return
  end
  if held and game.stack:top() == held then game.stack:pop() end
  self.textbox = true
  -- Kept for `yesorno`, which re-shows this page under the prompt.
  self.lastText = body
  if stay then
    local box
    local left = (hold or 0) > 0 and hold or nil
    box = TextBox.new(game, body, nil, {
      -- stay.onShown fires on the frame the last page finishes typing, which is
      -- where PrintText returns on the cart (#591).
      stay = { onShown = function()
        self.stayedTextBox = box
        -- The `hold` above.  TextBox's own page/CONT block counter is the one
        -- per-frame gate a finished box already has (src/render/TextBox.lua
        -- :237), and clearing `stayShown` re-arms this hook for the frame it
        -- drains on -- so the box sits there, read, for the length of the
        -- cart's pause and THEN hands the script back.  Dropping the latch is
        -- safe because a stay box reads no input and pops for nothing.
        if left then
          box.holdFrames = left
          box.stayShown = false
          left = nil
          return
        end
        if onDone then onDone() end
      end },
    })
    game.stack:push(box)
    return
  end
  game.stack:push(TextBox.new(game, body, function()
    self.textbox = nil
    if onDone then onDone() end
  end))
end

function World:pooledNpc(mapId, obj)
  if not self.sprites or not obj or not obj.sprite then return nil end
  -- An object whose `sprite` is a NUMBER names a wVariableSprites slot rather
  -- than a sheet (Route 36's Sudowoodo carries $f4), and only `variablesprite`
  -- can say what stands there.  Unfilled, it stays nil and nothing spawns --
  -- which is exactly what the cart draws before the scene script runs.
  local name = self:resolveSprite(obj.sprite)
  if not name then return nil end
  -- The SPRITE_POKEMON ids DO have a row (the extractor follows SpriteMons and
  -- points them at the mon's menu icon).  The day-care pair cannot have one --
  -- its species is whatever is being bred -- so resolveSprite answers with the
  -- built def itself rather than a name.
  local spriteDef = type(name) == "table" and name or self.sprites[name]
  if not spriteDef then return nil end
  local key = string.format("%s_obj_%d", mapId, obj.index or 0)
  local npc = self.npcPool[key]
  if not npc then
    npc = NPC.new(mapId, obj, spriteDef)
    self.npcPool[key] = npc
    -- applyPalettes only runs on map entry and once a second
    -- (PALETTE_POLL_STEPS), so an NPC created after that -- anything an event
    -- flag reveals part way through a map's life -- would draw with an
    -- unbaked sheet until the next poll came round.  That is a full second of
    -- a grey character standing in a coloured room.
    self:applySpritePalette(npc)
    -- Gen 1's pooledNPC emits the same three keys from the same place -- the
    -- pool miss, so one object announces itself once per run and not on every
    -- seam crossing.  `runtime` is always false here: Gold has no runtime-object
    -- system (see WorldAPI:spawnNpc), so every object came out of the map def.
    if Runtime.wants("world.npc_spawned") then
      Runtime.emit("world.npc_spawned",
        { mapId = mapId, npcId = key, runtime = false })
    end
  end
  return npc
end

-- CheckObjectTime (home/map_objects.asm), the mask LoadObjectMasks computes
-- beside CheckObjectFlag: an object_event's two hour bytes decide whether it
-- is on the map AT ALL right now.  macros/scripts/maps.asm spells the encoding
-- out: h1 < h2 shows the object from h1 to h2 (inclusive both ends), h1 > h2
-- HIDES it strictly between h2 and h1, h1 == h2 always shows, and h1 == -1
-- turns h2 into a MORN/DAY/NITE bitmask (-1 = always).  This is what keeps the
-- Goldenrod pharmacist single (two rows on one tile, one DAY one NITE), what
-- empties the Mt Moon gift shop at night, and what keeps exactly one of the
-- three time-of-day Moms in the kitchen.
--
-- The mask compares against the CLOCK's time of day (GetTimeOfDay reads
-- hHours), never wTimeOfDayPalset -- an indoor map pinned to PALETTE_DAY still
-- swaps its night staff -- which is why this reads World:hour and not
-- World:timeOfDayId.
local MORN_MASK, DAY_MASK, NITE_MASK = 1, 2, 4

function World:clockTimeMask()
  -- TimesOfDay (engine/rtc/rtc.asm): 0400-0959 morn, 1000-1759 day, else nite.
  local hour = self:hour()
  if hour >= 4 and hour < 10 then return MORN_MASK end
  if hour >= 10 and hour < 18 then return DAY_MASK end
  return NITE_MASK
end

function World:objectTimeVisible(obj)
  local hours = obj and obj.hours
  if not hours then return true end
  local h1 = hours[1] or -1
  local h2 = hours[2] or -1
  if h1 == -1 then
    if h2 == -1 then return true end
    local mask = self:clockTimeMask()
    return h2 % (mask * 2) >= mask
  end
  if h1 == h2 then return true end
  local hour = self:hour()
  if h1 < h2 then
    return hour >= h1 and hour <= h2
  end
  return hour >= h1 or hour <= h2
end

-- wObjectMasks, one byte per object_event (home/map.asm:1534 CheckObjectMask).
-- Tri-state here: true masked, false unmasked, nil "no mask loaded", which is
-- the only case that falls back to deriving visibility from the event flag.
function World:objectMaskKey(obj, index)
  return string.format("%s:%d", self.map.id, (obj and obj.index) or index or 0)
end

-- MaskObject / UnmaskObject (home/map.asm:1542, :1548): ONE byte, this
-- object's.  `maskScripted` remembers that a script wrote it, so the hour poll
-- below cannot resurrect somebody a scene took off the map.
function World:setObjectMask(obj, index, masked)
  self.objectMasks = self.objectMasks or {}
  self.maskScripted = self.maskScripted or {}
  local key = self:objectMaskKey(obj, index)
  self.objectMasks[key] = masked and true or false
  self.maskScripted[key] = true
end

-- LoadObjectMasks (engine/overworld/map_objects_2.asm:1): ByteFill over the
-- whole array, then one GetObjectTimeMask / CheckObjectFlag per object.  This
-- is the ONLY place the event flags decide who is on the map; after it, an
-- `appear` or `disappear` moves its own byte and a plain `setflag` moves
-- nobody until the next load.
--
-- LoadMapObjects runs it AFTER MAPCALLBACK_OBJECTS (engine/overworld/
-- map_setup.asm:78-82), so a callback's appear/disappear counts only through
-- the flag it sets -- which is why the reset is unconditional here.  The hour
-- poll passes keepScripted, since it stands in for a reload the cart does not
-- actually run.
function World:loadObjectMasks(opts)
  opts = opts or {}
  local scripted = (opts.keepScripted and self.maskScripted) or {}
  local masks = opts.keepScripted and (self.objectMasks or {}) or {}
  local def = self.map and self.map.def
  for index, obj in ipairs((def and def.objects) or {}) do
    local key = self:objectMaskKey(obj, index)
    if not scripted[key] then
      masks[key] = not (self.events:objectVisible(obj.eventFlag)
        and self:objectTimeVisible(obj))
    end
  end
  self.objectMasks = masks
  self.maskScripted = scripted
end

-- Current-map NPCs + visual-only ghosts on neighbor strips (Gen 1 pattern).
function World:rebuildPeople(opts)
  opts = opts or {}
  -- Anything this function did not put in the list is a GUEST: the follower
  -- (src/world/gen2/Follower.lua) or a mod's own entity.  A rebuild runs on
  -- every zoom and time-of-day roll, so wiping guests loses a follower at the
  -- top of the hour; Gen 1 rebuilds on map load only and never had to say it.
  local made = self.peopleFromMap or {}
  local guests
  for _, npc in ipairs(self.npcs or {}) do
    -- Only this map's: a warp respawns rather than dragging one across a seam.
    if not made[npc] and (npc.mapId == nil or npc.mapId == self.map.id) then
      guests = guests or {}
      guests[#guests + 1] = npc
    end
  end
  local fromMap = {}
  self.peopleFromMap = fromMap
  if not opts.seamless or not self.npcPool then
    self.npcPool = {}
  end
  self.npcs = {}
  self.entities = {}
  if self.player then
    table.insert(self.entities, self.player)
  end
  for _, obj in ipairs(self.map.def.objects or {}) do
    -- wObjectMasks is what says who is standing here (CheckObjectMask,
    -- home/map.asm:1534): the flags only reach it through LoadObjectMasks, at
    -- map load.  A world that never ran setMap has no masks at all, so nil
    -- falls back to the derivation LoadObjectMasks would have done.
    local masked = self.objectMasks and self.objectMasks[self:objectMaskKey(obj)]
    if masked == nil then
      masked = not (self.events:objectVisible(obj.eventFlag)
        and self:objectTimeVisible(obj))
    end
    if not masked then
      local npc = self:pooledNpc(self.map.id, obj)
      if npc then
        fromMap[npc] = true
        table.insert(self.npcs, npc)
        table.insert(self.entities, npc)
      end
    end
  end
  for _, npc in ipairs(guests or {}) do
    table.insert(self.npcs, npc)
    table.insert(self.entities, npc)
  end
  self.ghosts = {}
  for _, nb in ipairs(self.neighbors) do
    local def = self.maps[nb.id]
    if def then
      local tileset = self.tilesets[def.tileset]
      local ghostMap = tileset and Map.new(def, tileset) or nil
      local peers = {}
      for _, obj in ipairs(def.objects or {}) do
        if self.events:objectVisible(obj.eventFlag)
            and self:objectTimeVisible(obj) then
          local npc = self:pooledNpc(nb.id, obj)
          if npc and ghostMap then
            table.insert(peers, npc)
            table.insert(self.ghosts, {
              npc = npc, map = ghostMap, ox = nb.ox, oy = nb.oy, peers = peers,
            })
          end
        end
      end
    end
  end
end

-- Mod-spawned map objects.  The Gen 1 arm (OverworldState:addRuntimeObject)
-- appends straight onto the map def's object list, and the same move works
-- here: World.maps is one table for the whole run and rebuildPeople reads
-- self.map.def.objects, so an appended object is pooled, drawn, walked and
-- talked to like an extracted one, and survives a map reload.  Not serialized:
-- a permanent NPC belongs in a maps patch, this is for actors the mod respawns
-- on map.entered.  A runtime object carries no eventFlag, so LoadObjectMasks'
-- derivation leaves it visible.
function World:addRuntimeObject(mapId, objDef, owner)
  local def = self.maps and self.maps[mapId]
  if not def then return nil, "unknown map: " .. tostring(mapId) end
  def.objects = def.objects or {}
  local index = 0
  for _, obj in ipairs(def.objects) do
    if (obj.index or 0) > index then index = obj.index end
  end
  objDef.index = index + 1
  objDef.runtime = true
  objDef.owner = owner
  table.insert(def.objects, objDef)
  local npcId = mapId .. "_obj_" .. objDef.index
  if self.map and self.map.id == mapId then
    self:rebuildPeople({ seamless = true })
  end
  return npcId
end

-- Imported objects are refused, and so is another mod's.
function World:removeRuntimeObject(npcId, owner)
  for mapId, def in pairs(self.maps or {}) do
    for i, obj in ipairs(def.objects or {}) do
      if obj.runtime and mapId .. "_obj_" .. obj.index == npcId then
        if owner ~= nil and obj.owner ~= owner then
          return nil, "not owned by " .. tostring(owner)
        end
        table.remove(def.objects, i)
        if self.npcPool then
          self.npcPool[string.format("%s_obj_%d", mapId, obj.index)] = nil
        end
        if self.map and self.map.id == mapId then
          self:rebuildPeople({ seamless = true })
        end
        return true
      end
    end
  end
  return nil, "no such runtime object: " .. tostring(npcId)
end

-- IsNPCAtCoord (engine/overworld/npc_movement.asm), which is what BOTH the
-- step's `.CheckNPC` and the A press's CheckFacingObject ask -- so a BIG_OBJECT
-- fills its whole 2x2 blob for collision and for talking alike, and the
-- Vermilion Snorlax can be woken from any cell adjacent to any of its four.
-- NPC:covers is WillObjectIntersectBigObject; every ordinary object answers it
-- with the plain one-cell compare.
function World:npcAt(cx, cy)
  for _, npc in ipairs(self.npcs) do
    if NPC.covers(npc, cx, cy) then return npc end
  end
  return nil
end

-- Gen 1's spelling (src/world/OverworldController.lua), for the reason the
-- Map vocabulary aliases exist: a mod holds one name.
function World:npcAtCell(cx, cy)
  return self:npcAt(cx, cy)
end

-- CheckIfFacingTileCoordIsBGEvent (home/map.asm) matches on the COORDINATES
-- alone and leaves the function byte to BGEventJumptable; this narrows to
-- BGEVENT_READ, the one arm that is a plain script pointer.  BGEVENT_ITEM is
-- src/world/gen2/HiddenItems.lua, off the same cell.
-- BGEventJumptable, ported past its first arm.
--
-- This matched `kind == 0` (BGEVENT_READ) only, which silently dropped five of
-- the nine kinds. The one that mattered is BGEVENT_IFNOTSET: TeamRocketBaseB3F's
-- locked door is two of them, so pressing A at Giovanni's door did nothing at
-- all, EVENT_OPENED_DOOR_TO_GIOVANNIS_OFFICE could never be set, and the Rocket
-- hideout dead-ended one room short of its boss.
--
--   0 READ        a plain script pointer
--   1-4 UP/DOWN/RIGHT/LEFT  .checkdir -- read only when facing that way
--   5 IFSET       run the script only while the event IS set
--   6 IFNOTSET    run it only while the event is NOT set
--   7 ITEM        hidden item, handled by src/world/gen2/HiddenItems.lua
--   8 COPY        copies data without reading; nothing to run
--
-- The cart's facing test is `and %1100`, i.e. the direction's top two bits, so
-- it compares the FACING and not the button that produced it.
local BGEVENT_FACING = { [1] = "up", [2] = "down", [3] = "right", [4] = "left" }

function World:bgEventAt(cx, cy)
  for _, ev in ipairs(self.map.def.bgEvents or {}) do
    if ev.x == cx and ev.y == cy then
      local kind = ev.kind or 0
      if kind == 0 then
        return ev
      elseif BGEVENT_FACING[kind] then
        if self.player and self.player.facing == BGEVENT_FACING[kind] then
          return ev
        end
      elseif kind == 5 or kind == 6 then
        -- CheckBGEventFlag, then `.ifset` reads when set and `.ifnotset` when
        -- clear. An extraction that predates the conditional_event fix has no
        -- `event` field; refusing to guess is better than running the door
        -- script unconditionally.
        if ev.event and ev.scriptKey then
          local set = self.events and self.events:get(ev.event) or false
          if (kind == 5) == (set and true or false) then return ev end
        end
      end
    end
  end
  return nil
end

-- ---- trainers -------------------------------------------------------------
-- engine/events/trainer_scripts.asm, as inline command lists: nothing in the
-- ROM points at these two, so the extractor never sees them and the VM has to
-- be handed the list.  Kept command-for-command so the ordering (music before
-- the seen text, flag set after the battle, after-script as a tail call) stays
-- checkable against the source.
local SEEN_BY_TRAINER_SCRIPT = {
  { op = "loadtemptrainer" },
  { op = "encountermusic" },
  -- showemote EMOTE_SHOCK, LAST_TALKED, 30
  { op = "showemote", emote = 0, object = -2, frames = 30 },
  { op = "trainerapproach" },
  { op = "faceobject", a = 0, b = 1 },
  { op = "opentext" },
  { op = "trainertext", index = 0 }, -- TRAINERTEXT_SEEN
  { op = "waitbutton" },
  { op = "closetext" },
  { op = "loadtemptrainer" },
  { op = "startbattle" },
  { op = "reloadmapafterbattle" },
  { op = "trainerflagaction", action = 1 }, -- SET_FLAG
  { op = "scripttalkafter" },
}

-- TalkToTrainerScript: an already-beaten trainer skips straight to its
-- after-battle script, which is why a beaten rival still has a line.
local TALK_TO_TRAINER_SCRIPT = {
  { op = "faceplayer" },
  { op = "trainerflagaction", action = 2 }, -- CHECK_FLAG
  { op = "iftrue", script = { { op = "scripttalkafter" } } },
  { op = "loadtemptrainer" },
  { op = "encountermusic" },
  { op = "opentext" },
  { op = "trainertext", index = 0 },
  { op = "waitbutton" },
  { op = "closetext" },
  { op = "loadtemptrainer" },
  { op = "startbattle" },
  { op = "reloadmapafterbattle" },
  { op = "trainerflagaction", action = 1 },
  { op = "scripttalkafter" },
}

function World:trainerBeaten(record)
  if not (record and record.event) then return false end
  return self.events:get(record.event) and true or false
end

-- _CheckTrainerBattle: every visible, unbeaten trainer object that is facing
-- the player along a shared row or column, within its own sight range.
function World:checkTrainerBattle()
  if self:busy() or not self.player or not self.vm then return false end
  if self.player.moving then return false end
  local save = self.game and self.game.save
  if not (save and save.party and #save.party > 0) then return false end
  for _, npc in ipairs(self.npcs) do
    local record = npc.def and npc.def.trainer
    if record and not self:trainerBeaten(record) then
      local distance, dir = Trainers.sees(npc, self.player, npc.def.sight)
      if distance then
        return self:startTrainerScript(npc, SEEN_BY_TRAINER_SCRIPT, {
          distance = distance, dir = dir,
        })
      end
    end
  end
  return false
end

-- Both entries to a map trainer -- the sight cone and an A press on one -- come
-- through here, which is why world.trainer_engaged sits at this seam rather
-- than at checkTrainerBattle.  Gen 1's three payload keys are unchanged;
-- trainerClass and partyIndex hold the `trainer` struct's numeric class
-- constant and member number (macros/scripts/maps.asm) where Gen 1 holds its
-- own class name and party index -- same role, same key.  `trainerEvent` and
-- `sight` are Gen 2 additions: the beaten-flag the struct carries, and the
-- distance/direction when it was the eyesight test that engaged.
function World:startTrainerScript(npc, script, sight)
  local record = npc and npc.def and npc.def.trainer
  if record and Runtime.wants("world.trainer_engaged") then
    Runtime.emit("world.trainer_engaged", {
      npc = npc, trainerClass = record.class, partyIndex = record.member,
      trainerEvent = record.event, sight = sight,
    })
  end
  self.talkNpc = npc
  self:freezeNpc(npc)
  self.vm.trainerObject = npc.def.trainer
  self.trainerSight = sight
  self.trainerNpc = npc
  return self.vm:start(script)
end

-- The engaged / talked-to object holds still for the whole conversation.  On
-- the cart the seen-by script's own movement freezes everything
-- (Script_applymovement -> FreezeAllOtherObjects, engine/overworld/
-- scripting.asm), and a talked-to wanderer stops because its struct is the
-- script's LAST_TALKED; either way a SPINRANDOM trainer must not keep rolling
-- new facings under his own sighting text.  World:step unfreezes the pool the
-- frame the interaction is over, which is EndScript's UnfreezeAllObjects.
function World:freezeNpc(npc)
  if npc then npc.frozen = true end
  self.frozeNpcs = true
end

-- TrainerWalkToPlayer: close to one cell short of the player, then hand the
-- VM back control.  A trainer spotted from one cell away never moves.
function World:trainerApproach(onDone)
  local sight = self.trainerSight
  local npc = self.trainerNpc
  if not (sight and npc) then
    if onDone then onDone() end
    return
  end
  local steps = Trainers.approach(sight.distance, sight.dir)
  if #steps == 0 then
    if onDone then onDone() end
    return
  end
  local bytes = {}
  for _, dir in ipairs(steps) do
    bytes[#bytes + 1] = Movement.stepByte(dir)
  end
  bytes[#bytes + 1] = Movement.STEP_END
  self:beginMovement(npc.def.index + 1, bytes, onDone)
end

-- TileCollisionStdScripts (data/collision/collision_stdscripts.asm),
-- verbatim: collision byte -> the StdScripts label the extractor resolved
-- into std_scripts.lua (RomExtractorGen2:extractStdScripts).  This is how
-- every Pokecenter PC, house radio, town map poster and bookshelf in the
-- game is read -- none of them is a bg event.
local TILE_COLLISION_STD_SCRIPTS = {
  [0x91] = "MagazineBookshelfScript", -- COLL_BOOKSHELF
  [0x93] = "PCScript",                -- COLL_PC
  [0x94] = "Radio1Script",            -- COLL_RADIO
  [0x95] = "TownMapScript",           -- COLL_TOWN_MAP
  [0x96] = "MerchandiseShelfScript",  -- COLL_MART_SHELF
  [0x97] = "TVScript",                -- COLL_TV
  [0x9d] = "WindowScript",            -- COLL_WINDOW
  [0x9f] = "IncenseBurnerScript",     -- COLL_INCENSE_BURNER
}

-- what the A press resolved to, for world.interacted's listeners.  Same four
-- payload keys as Gen 1 and the same `kind` vocabulary where the two engines
-- share an arm: "npc", "sign", "hidden", "script", "none".  Gold's arms that
-- Gen 1 has no equivalent of get their own words -- "trainer", "boulder",
-- "itemball", "std" (the TileCollisionStdScripts table: PCs, radios, TVs,
-- bookshelves) and "fieldmove" -- rather than being folded into one of Gen 1's.
local function interacted(self, fx, fy, kind, target)
  if not Runtime.wants("world.interacted") then return end
  Runtime.emit("world.interacted", { mapId = self.map and self.map.id,
                                     x = fx, y = fy, kind = kind,
                                     target = target })
end

-- A-press: talk to facing NPC, read a sign (BGEVENT_READ) or dig up a hidden
-- item (BGEVENT_ITEM).
--
-- Split so a replaced `OverworldController.interact` sits in front of the
-- body (src/mods/Gen2Compat.lua); unpatched, this is one comparison.
function World:interact()
  local wrapped = Gen1Facade.interactWrapper()
  if wrapped then return wrapped(self) end
  return self:interactBody()
end

function World:interactBody()
  if self:busy() or not self.player or not self.vm then return false end
  local p = self.player
  if p.moving then return false end
  local d = Map.DELTA[p.facing]
  local fx, fy = p.cellX + d[1], p.cellY + d[2]
  -- CheckFacingObject (engine/overworld/npc_movement.asm:229): "Double the
  -- distance for counter tiles."  A Pokecenter nurse and a Mart clerk stand
  -- BEHIND a COLL_COUNTER tile, so the cell the player faces is the counter
  -- itself and the object is one further on.  Without this the press finds an
  -- empty wall and nothing happens -- which is to say no nurse and no clerk in
  -- the game could be talked to at all.
  --
  -- Only the OBJECT lookup is doubled, exactly as the cart does it: bg events
  -- and the tile-collision events below still read the tile actually faced.
  local ox, oy = fx, fy
  if self.map and Permissions.isCounter(self.map:cellCollision(fx, fy)) then
    ox, oy = p.cellX + d[1] * 2, p.cellY + d[2] * 2
  end
  local npc = self:npcAt(ox, oy)
  -- TryObjectEvent writes hLastTalked for EVERY A-press dispatch; scripts
  -- then use LAST_TALKED (`disappear`, `applymovementlasttalked`) without any
  -- setlasttalked of their own.  The port only wrote it from the explicit
  -- command, so SmashRockScript's `disappear LAST_TALKED` hid whichever
  -- object some earlier conversation had named -- the Burned Tower rock
  -- played its whole smash and stayed standing in any session where anybody
  -- had been talked to first.  Object consts are index + 1, the same mapping
  -- disappearObject decodes.
  if npc and npc.def and self.vm then
    self.vm.lastTalked = (npc.def.index or 0) + 1
  end
  -- The Gen 1 dispatch a follower mod wraps is OverworldState:talkTo(npc)
  -- (src/world/OverworldController.lua:2564), which has no single Gen 2
  -- method: Gold dispatches inline from here.  Same shape as
  -- interactWrapper -- nil unless something replaced it, and a true return
  -- suppresses the built-in path.
  if npc then
    local talkTo = Gen1Facade.talkToWrapper()
    if talkTo and talkTo(self, npc) then return true end
  end
  if npc and npc.def and npc.def.trainer then
    interacted(self, fx, fy, "trainer", npc)
    return self:startTrainerScript(npc, TALK_TO_TRAINER_SCRIPT, nil)
  end
  -- Any other object an A press lands on holds still too (see freezeNpc).
  if npc then self:freezeNpc(npc) end
  -- Every strength boulder in the game carries the same script -- `jumpstd
  -- StrengthBoulderScript`, which is a bare `farsjump AskStrengthScript` into
  -- ASM.  There is no bytecode behind that label for the extractor to have
  -- found, so the boulder arm is handled here rather than through the VM,
  -- which would otherwise walk into a script key with nothing on the far side.
  if npc and World.isStrengthBoulder(npc) then
    self.talkNpc = npc
    interacted(self, fx, fy, "boulder", npc)
    return self:tryStrengthOW()
  end
  -- OBJECTTYPE_ITEMBALL: no scriptKey to start -- the object's pointer is the
  -- raw (item, quantity) pair, read by the extractor into `itemball`.  Every
  -- plain Poke Ball on the floor comes through here; without this arm the
  -- press found the object, matched no branch, and fell through to the tile
  -- events -- no ball in the game could be picked up.
  if npc and npc.def and npc.def.itemball then
    self.talkNpc = npc
    interacted(self, fx, fy, "itemball", npc)
    return self.vm:start(HiddenItems.ballPickupScript(
      npc.def.itemball.item, npc.def.itemball.quantity,
      (npc.def.index or 0) + 1,
      -- The same resolver the itemfinder gets: the script names its sfx by
      -- pokegold LABEL and this looks it up in THIS cache's sfx table, rather
      -- than trusting a numeric id that only holds for the shipped Gold cache.
      function(want, id) return self:sfxIdNamed(want, id) end))
  end
  if npc and npc.def and npc.def.scriptKey then
    self.talkNpc = npc
    interacted(self, fx, fy, "npc", npc)
    return self.vm:start(npc.def.scriptKey)
  end
  local sign = self:bgEventAt(fx, fy)
  if sign and sign.scriptKey then
    self.talkNpc = nil
    interacted(self, fx, fy, "sign", sign)
    return self.vm:start(sign.scriptKey)
  end
  -- BGEVENT_ITEM, the `.itemifset` arm of the same jumptable: a hidden item.
  -- Its operand is `hiddenitem` data rather than a script, so there is no
  -- scriptKey for the arm above to have found and the list is built here.  An
  -- item already taken has its flag set, and `.itemifset` jumps to `.dontread`
  -- on that -- no carry, so the press falls through to the tile events below
  -- exactly as if the bg event were not there.
  local hidden = HiddenItems.at(self.map and self.map.def, fx, fy, self.events)
  if hidden then
    self.talkNpc = nil
    -- PlayTalkObject, the SFX every read of a bg event opens on.
    self:playSfxNamed("Sfx_ReadText2", SFX.READ_TEXT_2)
    interacted(self, fx, fy, "hidden", hidden)
    return self.vm:start(HiddenItems.pickupScript(hidden.item, hidden.event))
  end
  -- CheckAPressOW's third and last try (engine/overworld/events.asm):
  -- TryObjectEvent, then TryBGEvent, then TryTileCollisionEvent -- the facing
  -- TILE's own events.  TryTileCollisionEvent's own order is fixed and load
  -- bearing: CheckFacingTileForStdScript first, then cut tree, whirlpool,
  -- waterfall, headbutt tree, and SURF last as the catch-all.  Each arm
  -- claims the press only if the facing tile matches its collision, which is
  -- what keeps a tree from stealing a sign's press and what makes SURF the
  -- one arm allowed to be silent.
  --
  -- CheckFacingTileForStdScript (engine/events/std_collision.asm): a facing
  -- collision with a TileCollisionStdScripts row runs that std script and
  -- returns carry.  The bodies come out of the cache's std_scripts table and
  -- run through the VM like any map script -- PCScript is `opentext /
  -- special PokemonCenterPC / closetext / end`.
  local std = TILE_COLLISION_STD_SCRIPTS[
    self.map and self.map:cellCollision(fx, fy)]
  if std then
    local entry = self.stdScripts and self.stdScripts.scripts
      and self.stdScripts.scripts[std]
    if entry and entry.key then
      self.talkNpc = nil
      interacted(self, fx, fy, "std", std)
      return self.vm:start(entry.key)
    end
  end
  if self:tryCutOW() then
    interacted(self, fx, fy, "fieldmove", "CUT")
    return true
  end
  if self:tryWhirlpoolOW() then
    interacted(self, fx, fy, "fieldmove", "WHIRLPOOL")
    return true
  end
  if self:tryWaterfallOW() then
    interacted(self, fx, fy, "fieldmove", "WATERFALL")
    return true
  end
  if self:tryHeadbuttOW(fx, fy) then
    interacted(self, fx, fy, "fieldmove", "HEADBUTT")
    return true
  end
  if self:trySurfOW() then
    interacted(self, fx, fy, "fieldmove", "SURF")
    return true
  end
  interacted(self, fx, fy, "none")
  return false
end

function World:fitScale()
  local w, h = Playfield.dimensions()
  return math.max(1, math.floor(math.min(w / 160, h / 144)))
end

function World:zoomScale()
  return Zoom.scale(self:fitScale())
end

-- home/map.asm:1739 LoadTilesetGFX
local ROOF_TILESETS = {
  TILESET_JOHTO = true,
  TILESET_JOHTO_MODERN = true,
}

function World:atlasFor(mapDef)
  local tileset = self.tilesets[mapDef.tileset]
  if not tileset then return nil end
  local cacheKey = mapDef.tileset
  local roofName = nil
  if ROOF_TILESETS[mapDef.tileset] then
    roofName = self.roofs and self.roofs.mapGroupRoofs
      and self.roofs.mapGroupRoofs[mapDef.group]
  end
  if roofName then cacheKey = cacheKey .. "|" .. roofName end
  local cached = self.atlasCache[cacheKey]
  if cached then return cached, tileset end

  local tilesPerRow = tileset.tilesPerRow or 16
  local atlas
  local roofSpec = roofName and self.roofs.roofs and self.roofs.roofs[roofName]
  if roofSpec and roofSpec.image then
    local ok, img = pcall(applyRoofOverlay, tileset.image, roofSpec.image, tilesPerRow)
    if ok then atlas = img end
  end
  if not atlas then
    local ok, img = pcall(Assets.image, tileset.image)
    if not ok then return nil, tileset end
    atlas = img
    atlas:setFilter("nearest", "nearest")
  end
  self.atlasCache[cacheKey] = atlas
  return atlas, tileset
end

-- Bakes one map's 32px blocks into a single canvas.
--
-- With palettes available this is a GBC-accurate render, not a grayscale one:
-- a tile's four colors come from its tileset PalMap slot inside the eight BG
-- palettes LoadMapPals would have loaded for this map's environment, time of
-- day and map group.  The bake walks slot 0..7 and draws only the tiles that
-- belong to each, so the shader's palette uniform changes eight times per map
-- instead of once per tile -- tiles never overlap, so the pass order is free.
--
-- `daytime` is baked in, which is why mapImages is keyed by map *and* daytime:
-- a night-to-morning rollover re-bakes rather than tinting, exactly like the
-- cart reloading wBGPals1.
function World:bakeMapImage(map, daytime, flicker)
  local atlas, tileset = self:atlasFor(map.def)
  if not atlas or not tileset then return nil end
  local blocks = tileset.blocks
  local tilesPerRow = tileset.tilesPerRow or 16
  local pw, ph = map.width * 32, map.height * 32
  -- Map pixels, not the screen's: a DPI-scaled canvas bakes them non-square
  -- (#208, see src/render/PixelCanvas.lua).
  local canvas = PixelCanvas.new(pw, ph, "nearest")
  local quads = {}
  local function quadFor(tile)
    local q = quads[tile]
    if q then return q end
    local sx = (tile % tilesPerRow) * 8
    local sy = math.floor(tile / tilesPerRow) * 8
    q = love.graphics.newQuad(sx, sy, 8, 8, atlas:getDimensions())
    quads[tile] = q
    return q
  end

  local tilePalettes = tileset.tilePalettes
  local bgSet = self.palettes and daytime
    and Palettes.bgSet(self.palettes, map.def, daytime) or nil
  -- FlickeringCaveEntrancePalette: on a DARKNESS_PALSET map, PAL_BG_YELLOW's
  -- color 0 is rewritten every VBlank from either its own color 0 or its
  -- color 1.  In the dark palette row those are RGB 30,30,11 and black, so
  -- the cave entrance blinks and nothing else in the map does.  Both phases
  -- are baked and cached, and World:pollCaveFlicker swaps between them --
  -- flipping a whole canvas is what a palette write costs here.
  if bgSet and daytime == "DARK" then
    bgSet = Palettes.withCaveFlicker(bgSet, flicker or 1)
  end
  local colored = bgSet and tilePalettes and GbcPalette.available()

  -- Slot 0 color 0 is the map's background wash; falling back to a flat green
  -- only matters for a pre-palette cache.
  local clearColor = { 0.15, 0.55, 0.25 }
  if bgSet and bgSet[1] and bgSet[1][1] then
    -- Through GbcPalette.color so the COLOR option reaches the wash too: it
    -- is a palette colour drawn as a plain fill, so nothing else would
    -- substitute it and a DMG-mode map would sit on a green field.
    local c = GbcPalette.color(bgSet[1], 1)
    clearColor = { c[1] / 255, c[2] / 255, c[3] / 255 }
  end

  local function drawTiles(slot)
    for by = 0, map.height - 1 do
      for bx = 0, map.width - 1 do
        -- LoadMetatiles reads block id 0 as the map header's border block,
        -- not as tileset block 0 (see src/world/gen2/BorderFill.lua), so a
        -- hole in the block list paints the same wall the margin does.
        local blockId = BorderFill.blockFor(
          map.blocks[by * map.width + bx + 1], map.borderBlock)
        local block = blocks and blocks[(blockId or 0) + 1]
        if block then
          for i = 0, 15 do
            local tile = block[i + 1] or 0
            -- tilePalettes is 1-based over the 96 sheet tiles; anything past
            -- the sheet (window/text tiles) has no entry and takes slot 1.
            local tileSlot = tilePalettes and tilePalettes[tile + 1] or 1
            if not slot or tileSlot == slot then
              local tx = bx * 32 + (i % 4) * 8
              local ty = by * 32 + math.floor(i / 4) * 8
              love.graphics.draw(atlas, quadFor(tile), tx, ty)
            end
          end
        end
      end
    end
  end

  canvas:renderTo(function()
    love.graphics.clear(clearColor[1], clearColor[2], clearColor[3], 1)
    love.graphics.setColor(1, 1, 1, 1)
    -- A LOVE canvas does not reset the transform, and this bake is NOT only
    -- reached from the fixed step: World:refreshColorMode runs at the top of
    -- World:draw, so the first bake after the OPTION screen changes COLOR
    -- happens under whatever scale and offset the Renderer had already pushed
    -- for the world canvas.  Without the origin the whole map is baked at that
    -- transform and then CACHED under its mapImages key, so one mis-timed bake
    -- keeps a wrong canvas until the time of day rolls over.  Same guard as
    -- World:drawTilted below and BattleAnimView's panel.
    love.graphics.push()
    love.graphics.origin()
    if colored then
      for slot = 1, 8 do
        GbcPalette.with(bgSet[slot], function() drawTiles(slot) end)
      end
    else
      drawTiles(nil)
    end
    love.graphics.pop()
  end)
  return canvas, bgSet
end

-- The functions whose frame strip the extractor already resolved, keyed to the
-- rule World:animRow reads them back with.
local ANIM_KINDS = {
  AnimateWhirlpoolTile = "whirlpool",
  AnimateTowerPillarTile = "tower",
  AnimateLavaBubbleTile1 = "lava1",
  AnimateLavaBubbleTile2 = "lava2",
}

-- Every VRAM tile a tileset's program rewrites, and where each one's frames
-- come from (engine/tilesets/tileset_anims.asm:167 water, :197 flower, :231
-- and :259 lava, :290 tower pillar, :350 whirlpool, plus the buffer scrolls
-- at :65 and :139).
function World:animLayers(tileset)
  local anim = tileset and tileset.anim
  if not (anim and anim.frames) then return nil end
  local defs = self.tilesets
  local wanted = nil
  local function add(tile, layer)
    -- A cache built before the strips were extracted has no sheet to draw
    -- from, so that tile is left to the bake.
    if not tile or (layer.kind ~= "scroll" and not layer.sheet) then return end
    wanted = wanted or {}
    wanted[tile] = layer
  end
  for _, frame in ipairs(anim.frames) do
    local func = frame.func
    if func == "AnimateWaterTile" then
      add(frame.tile,
        { kind = "water", sheet = defs and defs.waterFrames, frames = 4 })
    elseif func == "AnimateFlowerTile" then
      -- AnimateFlowerTile takes no argument: it hardcodes vTiles2 tile $03
      -- (engine/tilesets/tileset_anims.asm:222).
      add(0x03,
        { kind = "flower", sheet = defs and defs.flowerFrames, frames = 4 })
    elseif ANIM_KINDS[func] then
      add(frame.tile, { kind = ANIM_KINDS[func], sheet = frame.sheet,
        frames = frame.frames })
    elseif func == "WriteTileFromAnimBuffer" and frame.scroll then
      add(frame.tile, { kind = "scroll", scroll = frame.scroll, frames = 8 })
    end
  end
  return wanted
end

-- The cells a tileset's anim program repaints, gathered once per bake and
-- keyed by tile id: the map canvas is baked and never rewritten, so the frames
-- _AnimateTileset would have written into VRAM are drawn over it instead.
function World:animCellsFor(map, tileset)
  local wanted = self:animLayers(tileset)
  if not wanted then return nil end
  local blocks = tileset.blocks
  local tilePalettes = tileset.tilePalettes
  local out = nil
  for by = 0, map.height - 1 do
    for bx = 0, map.width - 1 do
      local blockId = BorderFill.blockFor(
        map.blocks[by * map.width + bx + 1], map.borderBlock)
      local block = blocks and blocks[(blockId or 0) + 1]
      if block then
        for i = 0, 15 do
          local tile = block[i + 1] or 0
          local layer = wanted[tile]
          if layer then
            out = out or {}
            local list = out[tile]
            if not list then
              list = {
                layer = layer,
                tile = tile,
                slot = tilePalettes and tilePalettes[tile + 1] or 1,
                cells = {},
              }
              out[tile] = list
            end
            local cells = list.cells
            cells[#cells + 1] = bx * 32 + (i % 4) * 8
            cells[#cells + 1] = by * 32 + math.floor(i / 4) * 8
          end
        end
      end
    end
  end
  return out
end

-- The key imageFor caches a map's bake under, shared with the anim cell lists
-- and the palettes so the draw pass can find them from a map id alone.
function World:mapCacheKey(mapId)
  local daytime = self.daytime
  local flicker = (daytime == "DARK") and self.flickerPhase or 1
  return mapId .. "|" .. tostring(daytime)
    .. "|" .. tostring(GbcPalette.mode) .. "|" .. tostring(flicker)
end

function World:imageFor(mapId)
  local daytime = self.daytime
  -- The COLOR mode is baked in alongside the daytime -- the palettes go on
  -- when the map canvas is drawn, not when it is sampled -- so it belongs in
  -- the key.  Keying by it rather than flushing on a mode change also means
  -- switching back and forth costs nothing after the first bake of each.
  -- ...and so is the cave-entrance flicker phase, for the same reason: a dark
  -- map has two bakes, not one, and they differ by a single palette colour.
  local flicker = (daytime == "DARK") and self.flickerPhase or 1
  local cacheKey = self:mapCacheKey(mapId)
  local cached = self.mapImages[cacheKey]
  if cached then return cached end
  local def = self.maps[mapId]
  if not def then return nil end
  local tileset = self.tilesets[def.tileset]
  if not tileset then return nil end
  local map = Map.new(def, tileset)
  local img, bgSet = self:bakeMapImage(map, daytime, flicker)
  self.mapImages[cacheKey] = img
  -- Under the same key as the bake: the overlay needs both the cell list and
  -- the palettes the bake resolved.
  self.animCells[cacheKey] = self:animCellsFor(map, tileset) or false
  self.bgSets[cacheKey] = bgSet or false
  return img
end

-- SetTallGrassFlags' own test (engine/overworld/map_objects.asm:247):
-- CheckSuperTallGrassTile first, then CheckGrassTile.
function World:grassAt(cx, cy)
  local map = self.map
  if not map then return false end
  local coll = map:cellCollision(cx, cy)
  return Permissions.isSuperTallGrass(coll) or Permissions.isGrass(coll)
end

-- The tileset atlas with BG colour 0 keyed to alpha.  The grass tile is about
-- two-fifths colour 0 and those pixels are the gaps the legs show through, so
-- the redraw over a sprite needs the key -- same `r > 0.83` rule
-- src/render/SpriteRenderer.lua uses on OBJ sheets.
function World:grassAtlasFor(mapDef)
  local tileset = self.tilesets and self.tilesets[mapDef and mapDef.tileset]
  if not (tileset and tileset.image) then return nil end
  self.grassAtlases = self.grassAtlases or {}
  local cached = self.grassAtlases[tileset.image]
  if cached ~= nil then return cached or nil, tileset end
  local made = false
  if love.image and love.image.newImageData then
    local ok, data = pcall(Assets.imageData, tileset.image)
    if ok and data and data.mapPixel then
      data:mapPixel(function(_, _, r, g, b, a)
        if r > 0.83 then return r, g, b, 0 end
        return r, g, b, a
      end)
      local okImg, img = pcall(love.graphics.newImage, data)
      if okImg and img then
        img:setFilter("nearest", "nearest")
        made = img
      end
    end
  end
  self.grassAtlases[tileset.image] = made
  return made or nil, tileset
end

-- The 8x8 BG tile at a map pixel, through LoadMetatiles' border-block rule.
function World:bgTileAt(map, tileset, mx, my)
  local bx, by = math.floor(mx / 32), math.floor(my / 32)
  if bx < 0 or by < 0 or bx >= map.width or by >= map.height then return nil end
  local blockId = BorderFill.blockFor(
    map.blocks[by * map.width + bx + 1], map.borderBlock)
  local block = tileset.blocks and tileset.blocks[(blockId or 0) + 1]
  if not block then return nil end
  local i = math.floor((my % 32) / 8) * 4 + math.floor((mx % 32) / 8)
  return block[i + 1]
end

-- IN_GRASS puts OAM_PRIO on the sprite's lower 16x8 only: .InitSprite ORs it
-- into hCurSpriteOAMFlags (engine/overworld/map_objects.asm:2850) and only the
-- bottom two OAM entries of a walking facing carry RELATIVE_ATTRIBUTES
-- (data/sprites/facings.asm:45-56).  The strip starts at py+4 because a sprite
-- draws 4 px above its cell (map_objects.asm:2876).
function World:drawGrassOver(entity, ox, oy, s)
  local map = self.map
  if not (entity and entity.inGrass and map) then return end
  local atlas, tileset = self:grassAtlasFor(map.def)
  if not (atlas and tileset) then return end
  local G = love.graphics
  local bgSet = self.bgSets[self:mapCacheKey(map.id)] or nil
  local tilePalettes = tileset.tilePalettes
  local tilesPerRow = tileset.tilesPerRow or 16
  local aw, ah = atlas:getDimensions()
  -- Only draw the bottom 8px tile row of the cell (ty = py + 8) over the feet,
  -- matching Gen 1's drawCellBottomRaw.  Starting at py + 4 sampled the top
  -- tile row and drew grass tufts over the face and torso.
  local rx, ry = entity.px, entity.py + 8
  self.grassQuad = self.grassQuad or G.newQuad(0, 0, 8, 8, aw, ah)
  local quad = self.grassQuad
  G.setColor(1, 1, 1, 1)
  for ty = math.floor(ry / 8) * 8, math.floor((ry + 7) / 8) * 8, 8 do
    for tx = math.floor(rx / 8) * 8, math.floor((rx + 15) / 8) * 8, 8 do
      local tile = self:bgTileAt(map, tileset, tx, ty)
      if tile then
        local cx0, cy0 = math.max(rx, tx), math.max(ry, ty)
        local cx1 = math.min(rx + 16, tx + 8)
        local cy1 = math.min(ry + 8, ty + 8)
        if cx1 > cx0 and cy1 > cy0 then
          quad:setViewport(
            (tile % tilesPerRow) * 8 + (cx0 - tx),
            math.floor(tile / tilesPerRow) * 8 + (cy0 - ty),
            cx1 - cx0, cy1 - cy0, aw, ah)
          local set = bgSet and bgSet[tilePalettes
            and tilePalettes[tile + 1] or 1]
          local function blit()
            G.draw(atlas, quad,
              math.floor(ox + cx0 * s), math.floor(oy + cy0 * s), 0, s, s)
          end
          if set and GbcPalette.available() then
            GbcPalette.with(set, blit)
          else
            blit()
          end
        end
      end
    end
  end
end

-- ShakeGrass' object (engine/overworld/map_objects.asm:2031): FacingGrass1 is
-- the tile at (0,+8) and (+8,+8) from the sprite's origin, FacingGrass2 at
-- (-1,+9) and (+9,+9), and SetFacingGrassShake's `and 4` alternates them every
-- four frames (data/sprites/facings.asm:230-239, map_object_action.asm:257).
function World:drawGrassShake(entity, ox, oy, s)
  local sheet = self.grassRustleImage
  if not (sheet and entity and entity.grassShake and entity.moving) then
    return
  end
  local frames = entity.stepFrames or Player.STEP_FRAMES
  local progress = entity.progress or 0
  -- MovementFunction_ShakingGrass takes the tracked object's STEP_DURATION
  -- minus one (map_objects.asm:965), so it dies a frame before the step lands.
  if progress >= frames then return end
  local G = love.graphics
  local x1, x2, dy = 0, 8, 4
  if progress % 8 >= 4 then x1, x2, dy = -1, 9, 5 end
  local colors = Palettes.spritePalette(self.palettes,
    self.daytime or Palettes.daytimeFor(self.map and self.map.def,
      self:hour(), self.flashUsed),
    { paletteId = 6 })
  local function blit()
    G.setColor(1, 1, 1, 1)
    local y = math.floor(oy + (entity.py + dy) * s)
    G.draw(sheet, math.floor(ox + (entity.px + x1) * s), y, 0, s, s)
    -- OAM_XFLIP on the second entry of both facings, so it draws right to left.
    G.draw(sheet, math.floor(ox + (entity.px + x2 + 8) * s), y, 0, -s, s)
  end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, blit)
  else
    blit()
  end
end

-- This frame's AnimateWaterTile graphic for a map's border block, or nil when
-- the block holds no water at all (engine/tilesets/tileset_anims.asm:167).
function World:borderWaterFrame(def, tileset)
  local anim = tileset and tileset.anim
  if not (anim and anim.frames) then return nil end
  local tile
  for _, frame in ipairs(anim.frames) do
    if frame.func == "AnimateWaterTile" and frame.tile then
      tile = frame.tile
      break
    end
  end
  if not tile then return nil end
  local fill = BorderFill.fillBlock(def)
  if fill == false then return nil end
  local block = tileset.blocks
    and tileset.blocks[BorderFill.blockFor(0, fill) + 1]
  if not block then return nil end
  local found = false
  for i = 1, 16 do
    if block[i] == tile then
      found = true
      break
    end
  end
  if not found then return nil end
  local sheets = self:animSheets()
  if not (sheets and sheets.water) then return nil end
  return {
    image = sheets.water,
    row = World.waterFrameFor(self.animTimer),
    tile = tile,
    slot = tileset.tilePalettes and tileset.tilePalettes[tile + 1] or 1,
  }
end

-- The 32x32 border-block bake for a map, cached under the same key its canvas
-- is (plus a suffix), so the daytime rollover, the COLOR option, the flicker
-- phase and World:dropMapImages' prefix sweep all reach it.  The palettes are
-- the map's own, because the border block comes out of the map's tileset and
-- LoadMapPals colours it with everything else on screen.
function World:borderImageFor(mapId)
  local daytime = self.daytime
  local flicker = (daytime == "DARK") and self.flickerPhase or 1
  local def = self.maps and self.maps[mapId]
  if not def then return nil end
  local tileset = self.tilesets and self.tilesets[def.tileset]
  if not tileset then return nil end
  -- VOID FILL black skips the tiled bake; drawGround paints a flat void.
  local fill = BorderFill.fillBlock(def)
  if fill == false then return nil end
  local blockId = BorderFill.blockFor(0, fill)
  -- A border block made of water animates with the rest of the map, so this
  -- frame's row joins the key: four bakes per map instead of one.  The VOID
  -- FILL mode is in the key so switching FADE/WATER/TREES does not keep a
  -- stale bake (#1418).
  local waterFrame = self:borderWaterFrame(def, tileset)
  local cacheKey = BorderFill.cacheKey(mapId .. "|" .. tostring(daytime)
    .. "|" .. tostring(GbcPalette.mode) .. "|" .. tostring(flicker)
    .. "|" .. tostring(BorderFill.voidFill or "fade")
    .. "|" .. tostring(blockId)
    .. "|" .. tostring(waterFrame and waterFrame.row or 0))
  local cached = self.mapImages[cacheKey]
  if cached ~= nil then return cached or nil end
  local atlas = self:atlasFor(def)
  if not atlas then return nil end
  local bgSet = self.palettes and daytime
    and Palettes.bgSet(self.palettes, def, daytime) or nil
  if bgSet and daytime == "DARK" then
    bgSet = Palettes.withCaveFlicker(bgSet, flicker or 1)
  end
  local ok, img = pcall(BorderFill.bake, atlas, tileset,
    blockId, bgSet, waterFrame)
  -- `false` rather than nil: a bake that cannot be made (a headless run with
  -- no canvas support) must not be retried once per frame forever.
  self.mapImages[cacheKey] = (ok and img) or false
  return (ok and img) or nil
end

-- FlickeringCaveEntrancePalette runs on the VBlank clock, so this runs on the
-- fixed step: two frames on, two frames off, and only on a DARKNESS_PALSET
-- map.  A phase change swaps the baked canvas rather than re-baking -- both
-- phases stay in mapImages once they have been drawn once.
function World:pollCaveFlicker()
  if self.daytime ~= "DARK" or not self.mapImage then return false end
  self.flickerClock = (self.flickerClock + 1) % Palettes.FLICKER_PERIOD
  local phase = Palettes.caveFlickerSource(self.flickerClock)
  if phase == self.flickerPhase then return false end
  self.flickerPhase = phase
  self.mapImage = self:imageFor(self.map.id)
  for _, nb in ipairs(self.neighbors) do
    nb.image = self:imageFor(nb.id) or nb.image
  end
  return true
end

-- `wTileAnimationTimer and %110` (engine/tilesets/tileset_anims.asm:172-174):
-- four water frames, each held for two ticks of the 0..7 timer.  1-based, so
-- it indexes the four rows of the water sheet directly.
function World.waterFrameFor(timer)
  return math.floor(((timer or 0) % 8) / 2) + 1
end

-- AnimateFlowerTile's `and %10` plus hCGB (tileset_anims.asm:204-212): on CGB
-- only cgb_1 and cgb_2 are ever written, alternating every two timer ticks.
function World:flowerFrameFor(timer)
  local rows = self.tilesets and self.tilesets.flowerCgbFrames
  local first, second = 2, 4
  if rows and rows[1] and rows[2] then first, second = rows[1], rows[2] end
  return ((timer or 0) % 4 < 2) and first or second
end

-- _AnimateTileset (engine/tilesets/tileset_anims.asm:11) runs ONE row of the
-- tileset's program per frame and DoneTileAnimation (:48) wraps the index, so
-- a whole pass is `period` frames; StandingTileFrame8 (:57) ticks the 0..7
-- timer once per pass.  Same VBlank clock the cave flicker runs on.
function World:pollTileAnim()
  local tileset = self.map and self.map.def
    and self.tilesets and self.tilesets[self.map.def.tileset]
  local anim = tileset and tileset.anim
  if not (anim and anim.period and anim.period > 0) then return false end
  self.animClock = (self.animClock or 0) + 1
  if self.animClock < anim.period then return false end
  self.animClock = 0
  self.animTimer = ((self.animTimer or 0) + 1) % 8
  return true
end

-- AnimateTowerPillarTile's own offsets table (tileset_anims.asm:334-342),
-- 1-based: five frames walked up and back down over the 0..7 timer.
local TOWER_ROWS = { [0] = 1, 2, 3, 4, 5, 4, 3, 2 }

-- Which row of a layer's strip this timer value shows.  Whirlpool `and %11`
-- (tileset_anims.asm:368); lava `and %110` halved, with tile $5b running two
-- frames ahead of tile $38 (:238-245, :266-270).
function World:animRow(layer)
  local timer = (self.animTimer or 0) % 8
  local kind = layer.kind
  if kind == "water" then return World.waterFrameFor(timer) end
  if kind == "flower" then return self:flowerFrameFor(timer) end
  if kind == "whirlpool" then return (timer % 4) + 1 end
  if kind == "tower" then return TOWER_ROWS[timer] end
  if kind == "lava2" then return math.floor(timer / 2) + 1 end
  if kind == "lava1" then return ((math.floor(timer / 2) + 2) % 4) + 1 end
  -- A scroll strip is baked one row per timer value.
  return timer + 1
end

-- One frame strip, loaded once.  `false` after a miss so a cache from before
-- it was extracted costs one pcall rather than one a frame.
function World:animSheet(path)
  if not path then return nil end
  self.animSheetPaths = self.animSheetPaths or {}
  local cached = self.animSheetPaths[path]
  if cached ~= nil then return cached or nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then img:setFilter("nearest", "nearest") end
  self.animSheetPaths[path] = (ok and img) or false
  return (ok and img) or nil
end

-- The two strips the border-block bake reaches for by name
-- (assets/generated/tilesets/*_frames.png), memoized as a pair.
function World:animSheets()
  if self.animSheetCache ~= nil then return self.animSheetCache or nil end
  local defs = self.tilesets
  local sheets = nil
  for kind, path in pairs({ water = defs and defs.waterFrames,
      flower = defs and defs.flowerFrames }) do
    local img = self:animSheet(path)
    if img then
      sheets = sheets or {}
      sheets[kind] = img
    end
  end
  self.animSheetCache = sheets or false
  return sheets
end

-- ScrollTileRightLeft (tileset_anims.asm:65) scrolls right for four ticks then
-- left for four, one call per pass in every program that uses it: the offset
-- the buffer has reached at each value of the 0..7 timer.
local SCROLL_H = { [0] = 0, 1, 2, 3, 2, 1, 0, -1 }

-- One tile's eight scroll positions stacked into an 8x64 strip.  The cart
-- rotates the tile in VRAM (ScrollTileRightLeft, ScrollTileDown :139) and the
-- map canvas is already baked, so the rotations are baked off the atlas once
-- and drawn over it like any other frame strip.
function World:scrollStrip(mapDef, tileset, tile, scroll)
  local key = tostring(mapDef.tileset) .. "|" .. tile .. "|"
    .. tostring(scroll.h) .. "," .. tostring(scroll.v)
  self.scrollStrips = self.scrollStrips or {}
  local cached = self.scrollStrips[key]
  if cached ~= nil then return cached or nil end
  local atlas = self:atlasFor(mapDef)
  local ok, canvas = pcall(PixelCanvas.new, 8, 8 * 8, "nearest")
  if not (atlas and ok and canvas) then
    self.scrollStrips[key] = false
    return nil
  end
  local perRow = tileset.tilesPerRow or 16
  local sx, sy = (tile % perRow) * 8, math.floor(tile / perRow) * 8
  local aw, ah = atlas:getDimensions()
  local G = love.graphics
  local drawn = pcall(function()
    canvas:renderTo(function()
      -- Same origin guard the map bake takes: this can run under whatever
      -- transform World:draw had already pushed.
      G.push()
      G.origin()
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      for timer = 0, 7 do
        local dx = ((scroll.h or 0) > 0) and (SCROLL_H[timer] % 8) or 0
        local dy = (timer * (scroll.v or 0)) % 8
        -- The tile wraps, so each position draws as up to four pieces:
        -- { destination, source, size }.
        for _, col in ipairs({ { dx, 0, 8 - dx }, { 0, 8 - dx, dx } }) do
          for _, row in ipairs({ { dy, 0, 8 - dy }, { 0, 8 - dy, dy } }) do
            if col[3] > 0 and row[3] > 0 then
              G.draw(atlas, G.newQuad(
                sx + col[2], sy + row[2], col[3], row[3], aw, ah),
                col[1], timer * 8 + row[1])
            end
          end
        end
      end
      G.pop()
    end)
  end)
  self.scrollStrips[key] = drawn and canvas or false
  return drawn and canvas or nil
end

-- One 8x8 row of a frame strip, reused: this runs every overworld frame and a
-- fresh Quad per cell would churn the GC.
function World:animQuad(key, row, frames)
  self.animQuads = self.animQuads or {}
  local id = key .. "#" .. row
  local q = self.animQuads[id]
  if not q then
    q = love.graphics.newQuad(0, (row - 1) * 8, 8, 8, 8, (frames or 4) * 8)
    self.animQuads[id] = q
  end
  return q
end

-- Draw this frame's animated tiles over one baked canvas.  Culled to the
-- view: a sea route names every water cell on the map and only a screenful of
-- them is ever visible.
function World:drawAnimCells(mapId, ox, oy, s)
  if not mapId then return end
  local key = self:mapCacheKey(mapId)
  local cells = self.animCells[key]
  if not cells then return end
  local def = self.maps and self.maps[mapId]
  local tileset = def and self.tilesets and self.tilesets[def.tileset]
  local G = love.graphics
  local cam = self.camera
  local bgSet = self.bgSets[key] or nil
  local left = cam.x - ox - 8
  local top = cam.y - oy - 8
  local right = left + (self.viewW or 160) + 16
  local bottom = top + (self.viewH or 144) + 16
  for _, list in pairs(cells) do
    local layer = list.layer
    local sheet
    if layer.kind == "scroll" then
      sheet = tileset
        and self:scrollStrip(def, tileset, list.tile, layer.scroll)
    else
      sheet = self:animSheet(layer.sheet)
    end
    if sheet then
      local row = self:animRow(layer)
      local quad = self:animQuad(
        layer.sheet or ("scroll|" .. list.tile), row, layer.frames)
      local xy = list.cells
      local function blit()
        G.setColor(1, 1, 1, 1)
        for i = 1, #xy, 2 do
          local tx, ty = xy[i], xy[i + 1]
          if tx >= left and tx <= right and ty >= top and ty <= bottom then
            G.draw(sheet, quad,
              math.floor((tx + ox - cam.x) * s),
              math.floor((ty + oy - cam.y) * s), 0, s, s)
          end
        end
      end
      -- All cells of one tile id share a PalMap slot, so the palette is set
      -- once per id rather than once per cell.
      local set = bgSet and bgSet[list.slot]
      if set and GbcPalette.available() then
        GbcPalette.with(set, blit)
      else
        blit()
      end
    end
  end
end

-- Recompute the active time of day and hand every drawable its colors.
-- Called on map entry and once a second while walking, so a real-clock
-- rollover repaints the world the way ReplaceTimeOfDayPals does on the cart.
--
-- Returns true when the daytime actually changed, i.e. the baked map images
-- are stale and callers must drop them.
-- One entity's OW palette.  SpriteRenderer bakes the sheet against these
-- colours and keys OBJ colour 0 to alpha; the group string keeps one bake per
-- (daytime, PAL_OW_*) pair, so two NPCs on the same palette share it.
function World:applySpritePalette(entity)
  if not (self.palettes and entity and entity.sprite and entity.spriteDef) then
    return
  end
  local daytime = self.daytime
    or Palettes.daytimeFor(self.map and self.map.def, self:hour(),
      self.flashUsed)
  -- entity.def is the object_event, whose own palette field OVERRIDES the
  -- sprite's (Palettes.objectPaletteId; AddMapObject, player_object.asm:187).
  -- The player has no object_event here, so it falls through to the sheet.
  local colors = Palettes.spritePalette(self.palettes, daytime,
    entity.spriteDef, entity.def)
  if not colors then return end
  -- The bake cache key has to be the palette actually chosen, or the three
  -- beasts -- one sheet, three object palettes -- would all share the first
  -- bake taken.
  local id = Palettes.objectPaletteId(entity.def)
    or entity.spriteDef.paletteId or 0
  entity.sprite:setObjPalette(colors,
    ("gen2:%s:%d"):format(tostring(daytime), id))
end

-- the two vanilla links the time-of-day chains wrap, hoisted so an empty
-- chain allocates no closure (src/world/OverworldController.lua does the same
-- for the Gen 1 pair)
local function sameTod(tod) return tod end
local function samePalette(name) return name end

-- world.tod, the same name and the same period strings Gen 1's
-- OverworldState:timeOfDay wraps, and the same job: answer what time of day
-- the WORLD is in.  It carries more here because Gold has a real clock behind
-- it (src/core/gen2/Clock.lua), so this is the one write everything downstream
-- reads -- World:timeOfDayId's VAR.TIMEOFDAY, the encounter slots, the object
-- hour windows and the palette bake all follow whatever comes back.
--
-- Gen 1's ctx keys (map, mapId, x, y, steps) are kept verbatim; `hour` and
-- `weekday` are added, because on Gold a day/night mod has a real hour to
-- reason about instead of a step counter.
function World:timeOfDay(hour)
  local clock = Palettes.clockDaytime(hour)
  if not Runtime.wantsHook("world.tod") then return clock end
  local map = self.map
  local p = self.player
  local save = self.game and self.game.save
  local next_ = Runtime.call("world.tod", sameTod, clock, {
    map = map,
    mapId = map and map.id,
    x = p and p.cellX,
    y = p and p.cellY,
    steps = (save and save.stepCount) or 0,
    hour = hour,
    weekday = self:weekday(),
  })
  if type(next_) ~= "string" or next_ == "" then return clock end
  return next_
end

function World:applyPalettes()
  if not self.map then return false end
  local previous = self.daytime
  local previousTod = self.tod
  -- GetTimeOfDay reads hHours, the one clock UpdateTime writes (home/time.asm):
  -- the palette, the object hour windows (World:objectTimeVisible), the
  -- day/night encounter slots and VAR.HOUR are all the same read, so this goes
  -- through World:hour rather than round-tripping the host clock inside
  -- Palettes.clockDaytime.
  local hour = self:hour()
  local tod = self:timeOfDay(hour)
  self.tod = tod
  -- ReplaceTimeOfDayPals.BrightnessLevels: a map header that pins a PALETTE_*
  -- overrides the clock outright, and PALETTE_DARK additionally becomes NITE
  -- once FLASH has been used.  Only the maps that FOLLOW the clock take the
  -- hooked answer -- pinning is the map saying it does not care what hour it
  -- is, and a world.tod mod must not unpin Union Cave.
  local def = self.map.def
  local pinned = def and def.palette and def.palette ~= "PALETTE_AUTO"
  local daytime = pinned
    and Palettes.daytimeFor(def, hour, self.flashUsed)
    or tod
  -- map.palette, the same name Gen 1 wraps around a map's resolved palette
  -- name.  Gold has no palette-name table: which four-colour set a map loads is
  -- named by its DAYTIME, so that is the value in the chain here.  The
  -- arguments are Gen 1's -- value, map, ctx -- and ctx keeps `tod` and adds
  -- the two Gen 2 facts behind the answer.
  if Runtime.wantsHook("map.palette") then
    local hooked = Runtime.call("map.palette", samePalette, daytime, self.map,
      { tod = tod, environment = def and def.environment,
        pinned = pinned and def.palette or nil, hour = hour,
        flashUsed = self.flashUsed and true or false })
    if type(hooked) == "string" and Palettes.DAYTIME_ID[hooked] then
      daytime = hooked
    end
  end
  self.daytime = daytime
  local changed = previous ~= self.daytime

  -- Gen 1 fires world.tod_changed off the same transition; `daytime` is the
  -- addition, because on Gold the period the world is in and the palette set a
  -- pinned map loads are not always the same string.
  if previousTod ~= nil and previousTod ~= tod
      and Runtime.wants("world.tod_changed") then
    Runtime.emit("world.tod_changed", {
      tod = tod, previous = previousTod, mapId = self.map.id,
      daytime = self.daytime,
    })
  end

  if self.palettes then
    self:applySpritePalette(self.player)
    for _, npc in pairs(self.npcPool or {}) do self:applySpritePalette(npc) end
  end
  return changed
end

function World:rebuildNeighbors()
  self.neighbors = {}
  if not self.map then return end
  local s = self:zoomScale()
  local ww, wh = Playfield.dimensions()
  local vw = math.ceil(ww / s)
  local vh = math.ceil(wh / s)
  if vw % 2 ~= 0 then vw = vw + 1 end
  if vh % 2 ~= 0 then vh = vh + 1 end
  self.viewW, self.viewH = vw, vh
  local list = World.computeNeighbors(
    self.maps, self.map.id, NEIGHBOR_HOPS, vw, vh)
  for _, n in ipairs(list) do
    local img = self:imageFor(n.id)
    if img then
      table.insert(self.neighbors, { id = n.id, ox = n.ox, oy = n.oy, image = img })
    end
  end
end

function World:setMap(mapId, cx, cy, facing, opts)
  opts = opts or {}
  local def = self.maps[mapId]
  if not def then
    self.status = "Unknown map " .. tostring(mapId)
    return false
  end
  local tileset = self.tilesets[def.tileset]
  if not tileset then
    self.status = "Missing tileset " .. tostring(def.tileset)
    return false
  end
  -- map.exited / map.entered are the Gen 1 pair (src/world/OverworldController
  -- setMap), same names and same payload keys.  Divergence, deliberate: the
  -- exit is emitted BELOW the two guards above rather than at the top of the
  -- function, because Gold's setMap can refuse a load Gen 1's would have
  -- asserted on, and an "exited" that is followed by no "entered" reads to a
  -- listener as a map that vanished.
  local fromMapId = self.map and self.map.id
  if fromMapId then
    Runtime.emit("map.exited", { mapId = fromMapId, toMapId = mapId })
  end
  -- LoadMapAttributes refills wOverworldMapBlocks from ROM, so every block CUT
  -- and WHIRLPOOL swapped out goes back: a cut tree is standing again the next
  -- time the map is loaded, and this has to happen before Map.new reads them.
  self:restoreBlocks()
  self:restoreObjectSpawns()
  -- HandleNewMap (home/map.asm:216-228) runs ResetMapBufferEventFlags before
  -- anything else that touches state: event flags 0-7
  -- (EVENT_TEMPORARY_UNTIL_MAP_RELOAD) die on every map load, which is what
  -- lets Bill's grandpa hand out his next evolution stone on re-entry and
  -- re-arms every other once-per-visit latch (Kurt's house, the ship ports,
  -- Dragon's Den B1F, the Park gate).
  --
  -- MapSetupScript_Continue is the one entry that does NOT: it runs
  -- HandleContinueMap, which is the label BELOW that reset, so loading a save
  -- keeps the byte SRAM was holding (data/maps/setup_scripts.asm).  Without
  -- that exemption, saving inside Kurt's house and continuing re-arms the
  -- latch and he repeats the branch the player already saw.  The post-credits
  -- spawn is not a continue: SpawnAfterE4 / PostCreditsSpawn set
  -- MAPSETUP.WARP, so it takes the reset (engine/menus/intro_menu.asm).
  if not opts.continue then
    self.events:resetMapBuffer()
  end
  -- ResetBikeFlags (home/flag.asm) zeroes the whole byte on a map load, and
  -- BIKEFLAGS_STRENGTH_ACTIVE_F is in it -- STRENGTH has to be used again in
  -- the next room, which is the whole shape of the Blackthorn Gym puzzle.
  self.strengthActive = false
  self.strengthMon = nil
  -- The other two bits of the same byte.  They have to go BEFORE
  -- MAPCALLBACK_NEWMAP runs, because the Cycling Road's callback is what sets
  -- them straight back again: leaving them set is how one visit to Route 17
  -- would keep the player glued to the bike for the rest of the game.
  self:setEngineFlag(Bike.ENGINE_ALWAYS_ON_BIKE, false)
  self:setEngineFlag(Bike.ENGINE_DOWNHILL, false)
  -- "Respawn in Pokemon Centers" (home/map.asm, LoadMapAttributes' .SetSpawn):
  -- walking from an OUTDOOR map into an INDOOR one whose tileset is
  -- TILESET_POKECENTER rewrites wLastSpawnMapGroup / wLastSpawnMapNumber, and
  -- that pair is what a whiteout reads.  It is the only thing in the game that
  -- moves the respawn point, and it has to run on the map load rather than on
  -- the heal: the cart moves your spawn when you walk in the DOOR, whether or
  -- not you talk to the nurse.
  --
  -- Missing this was not a small divergence.  MrPokemonsHouse.asm does
  -- `blackoutmod CHERRYGROVE_CITY` in the first half hour of the game, so with
  -- no other writer the respawn point was pinned to Cherrygrove for the entire
  -- rest of the run: every whiteout at the Elite Four teleported the player
  -- back across Johto.  (Found by the Gold route bot, which spent about 40k
  -- frames per Elite Four attempt walking home from Cherrygrove.)
  --
  -- Divergence, deliberate: the cart stores the OUTDOOR map and resolves it
  -- through data/maps/spawn_points.asm to get coordinates inside that town's
  -- Pokecenter.  No spawn table is emitted into the cache, and World:warpToSpawn
  -- already prefers a stored map id over the SPAWN_* lookup, so store the
  -- Pokecenter itself.  Same building, same town; the landing tile is its door
  -- rather than the mat in front of the counter.
  --
  -- A named method rather than eight inline lines so that
  -- tests/gen2_pokecenter_spawn_test.lua can drive the shipped rule instead of
  -- restating it: setMap needs a tileset, a Map and the callback machinery
  -- before it will run at all, which is more world than the rule needs.
  self:updateWhiteoutSpawn(def, mapId)

  -- ResetFlashIfOutOfCave: the FLASH flag survives a warp between two cave
  -- floors and dies the moment you step out onto a ROUTE or a TOWN.
  if def.environment == "ROUTE" or def.environment == "TOWN" then
    self.flashUsed = false
  end
  -- No noteFlypoint call here anymore: MAPCALLBACK_NEWMAP (run below, once
  -- the map is actually loaded) is a town's own `setflag ENGINE_FLYPOINT_*`,
  -- and FieldMoves.hasVisitedSpawn now reads that flag straight off
  -- save.engineFlags instead of a second write this function used to make.
  -- The map load repaints everything, so a fade sheet and a screen shake left
  -- over from the script that warped cannot survive it -- LoadMapPalettes and
  -- DeleteMapObject are what end both on the cart.
  self.fade = nil
  self.shake = nil
  self.map = Map.new(def, tileset)
  -- A follow pairing points at two live objects, and a map load rebuilds them
  -- (RefreshMapSprites); nothing on the cart survives that either.
  self.followState = nil
  -- EnterMap's SetUpFiveStepWildEncounterCooldown (engine/overworld/events.asm:
  -- 110, :367-370): four encounter-free steps after every map entry.
  self.wildCooldown = 5
  -- Resolve colors before baking: an indoor map pinned to PALETTE_DAY and the
  -- town outside it are lit differently, so the daytime has to be settled
  -- before imageFor picks a cache key -- and before a TILES callback's
  -- `changeblock` re-bakes through World:refreshMapImages, which would
  -- otherwise spend that bake on the daytime of the map being LEFT.
  self:applyPalettes()
  -- GetWarpDestCoords / EnterMapConnection / EnterMapSpawnPoint write wXCoord
  -- and wYCoord BEFORE HandleNewMap (data/maps/setup_scripts.asm:79-106).
  local face = facing or (self.player and self.player.facing) or "down"
  local chris = self.sprites and self.sprites[PLAYER_SPRITE]
  if self.player then
    self.player.cellX, self.player.cellY = cx, cy
    self.player.px, self.player.py = cx * 16, cy * 16
    self.player.facing = face
    if chris and not self.player.sprite then
      self.player:setSprite(chris)
    end
    if not opts.seamless then
      self.player.moving = false
      self.player.progress = 0
      self.player.targetX, self.player.targetY = nil, nil
    end
  else
    self.player = Player.new(cx, cy, face, chris)
  end
  -- LoadMapObjects rebuilds OBJECT_FLAGS2 from scratch, so IN_GRASS is decided
  -- by the cell the player arrives on (engine/overworld/map_objects.asm:247).
  self.player.inGrass = self:grassAt(cx, cy)
  self.player.grassShake = nil
  -- HandleNewMap (home/map.asm), in its own order: MAPCALLBACK_NEWMAP, then
  -- ClearCmdQueue, then MAPCALLBACK_CMDQUEUE.  The queue never survives a map
  -- load on the cart either, which is why both maps that use one write it back
  -- from a callback rather than once at the start of the game.
  --
  -- Every setup script that reaches this port's setMap -- Warp, BadWarp, Door,
  -- Fall, Teleport, Train, Connection -- carries HandleNewMap, LoadBlockData
  -- and LoadMapObjects, so all four callbacks belong here.  The three that
  -- carry fewer are not setMap calls: `reloadmap` is World:rebuildPeople (no
  -- load at all), ReturnToMapFromSubmenu has no port equivalent, and the
  -- Continue script's exemptions (no NEWMAP, no OBJECTS) exist because the cart
  -- restores wMapObjects from the save -- the port derives object visibility
  -- from the flags instead, so a continue has to build it like any other load.
  self:runMapCallback("MAPCALLBACK_NEWMAP")
  CmdQueue.clear(self.cmdQueue)
  self:writeCmdQueue()
  -- LoadBlockData: MAPCALLBACK_TILES, with the block buffer already refilled
  -- from ROM by restoreBlocks above and nothing baked off it yet.
  self:runMapCallback("MAPCALLBACK_TILES")
  -- LoadMapGraphics has no failure arm (data/maps/setup_scripts.asm:41): a
  -- failed bake reports through self.status and the rest of the setup runs.
  self.mapImage = self:imageFor(mapId)
  if not self.mapImage then
    self.status = "Could not bake " .. tostring(mapId)
  end
  if opts.seamless then
    self.warpCooldown = nil
  else
    -- Don't re-trigger the arrival warp until the player steps off.
    self.warpCooldown = { x = cx, y = cy }
  end
  self:rebuildNeighbors()
  -- LoadMapObjects (engine/overworld/map_setup.asm): MAPCALLBACK_OBJECTS, and
  -- only THEN LoadObjectMasks / InitializeVisibleSprites.  The callback's
  -- `appear` and `disappear` decide which objects the rebuild below finds --
  -- which day of the week's traveller is standing on Route 29, whether Lugia is
  -- in its chamber -- so running it after the rebuild would show the previous
  -- day's answer until something else rebuilt.
  self:runMapCallback("MAPCALLBACK_OBJECTS")
  -- LoadObjectMasks itself, the load this map visit's masks come from.  Every
  -- appear/disappear after it moves one byte of its own.
  self:loadObjectMasks()
  -- CheckUpdatePlayerSprite (engine/overworld/map_setup.asm), which every map
  -- setup script runs: the Cycling Road puts the player ON the bike, an
  -- INDOOR / DUNGEON map takes them off it, and the surf arms follow
  -- CheckOnWater -- the permission of the tile the player is STANDING on, which
  -- is why a load that lands on water is a surfing load and a warp out of the
  -- sea onto a beach is not.  It has to be after MAPCALLBACK_NEWMAP, because
  -- that callback is where ENGINE_ALWAYS_ON_BIKE is set, and before the music
  -- below, which reads the state back.
  self:applyPlayerState(Bike.mapSetupState(
    self.playerState, def.environment, self:alwaysOnBike(),
    Permissions.isWater(self.map:cellCollision(cx, cy))))
  self:rebuildPeople({ seamless = opts.seamless })
  -- rebuildPeople may have pooled fresh NPCs; give them their colors too.
  self:applyPalettes()
  local audio = self.game and self.game.data and self.game.data.audio
  -- PlayMapMusicBike / SpecialMapMusic (home/audio.asm:335, :397): a biking
  -- player keeps the bike theme; Music.play dedupes seamless edge crossings.
  if audio and audio.runtime then
    if not (FieldMoves.isBiking(self.playerState) and self:playBikeMusic()) then
      Music.playMap(self.game.data, mapId, nil,
                    FieldMoves.isSurfing(self.playerState), nil,
                    self:mapMusicSong(mapId))
    end
  end
  -- Fires with the map fully built and BEFORE the map's own scene script, so a
  -- listener sees exactly the state that script does -- the position Gen 1's
  -- emit takes ahead of its onEnter chain.  `via` carries the same four words
  -- Gen 1 uses plus "continue", which is the one map load Gen 2 has and Gen 1
  -- does not (MapSetupScript_Continue, the save being resumed).
  -- Ahead of the emit, so a map.entered listener already sees this load's
  -- follower (src/world/OverworldController.lua:446's position).
  Follower.onMapEntered(self.game, self, opts, true)
  Runtime.emit("map.entered", {
    mapId = mapId, map = self.map, fromMapId = fromMapId,
    via = opts.via
          or (opts.continue and "continue")
          or (opts.seamless and "connection")
          or (fromMapId and "warp" or "boot"),
  })
  -- Map-enter scene scripts (e.g. Elm lab walk-up at scene 0).
  if not opts.seamless then
    self.pendingSceneScript = true
  end
  -- StartMap (engine/overworld/events.asm): `farcall InitCallReceiveDelay` on
  -- every map entry, connections included -- which is why a player who keeps
  -- warping is never rung (src/core/gen2/Phone.lua's receive timer).
  if self.game and self.game.save then
    require("src.core.gen2.Phone").onMapLoad(self.game.save,
      self:stepContext().phone)
  end
  -- The setup script runs to its `db -1` either way, so the load reports true
  -- and only self.status carries a failed bake (data/maps/setup_scripts.asm:53).
  if self.mapImage then self.status = nil end
  return true
end

local function heldDirection(input)
  if input then
    if input:isDown("up") then return "up" end
    if input:isDown("down") then return "down" end
    if input:isDown("left") then return "left" end
    if input:isDown("right") then return "right" end
    return nil
  end
  if love.keyboard.isDown("up", "w") then return "up" end
  if love.keyboard.isDown("down", "s") then return "down" end
  if love.keyboard.isDown("left", "a") then return "left" end
  if love.keyboard.isDown("right", "d") then return "right" end
  return nil
end

-- PLAYEREVENT_WARP -> WarpToNewMapScript (engine/overworld/events.asm):
--
--   WarpToNewMapScript:
--       warpsound
--       newloadmap MAPSETUP.DOOR
--       end
--
-- so a warp taken by walking onto the tile is two things, in that order: the
-- sound GetWarpSFX picks off the tile the player is STANDING on (which is why
-- it has to be read before the load), and the MAPSETUP.DOOR setup script with
-- the map load inside it.  This used to be five lines that called setMap
-- directly, which is why doors were silent and instant.
-- home/map.asm GetDestinationWarpNumber: a `warp_event` whose destination warp
-- number is -1 ($ff) does NOT name its own destination.  It takes the whole
-- triple -- warp number, map group, map number -- out of wBackupWarpNumber and
-- friends, which is how one elevator door leads to seven different floors and
-- why Elevator_GoToFloor rides without warping.  A $ff warp with nothing
-- written there yet keeps the destination the map declared.
function World:resolveWarp(warpDef)
  if warpDef.destWarp ~= 0xff then
    return warpDef.destMap, warpDef.destWarp
  end
  local backup = self.backupWarp
  if not (backup and backup.map and self.maps[backup.map]) then
    return warpDef.destMap, warpDef.destWarp
  end
  return backup.map, backup.warp
end

-- The other half of the -1 contract, from the arrival side.  CopyWarpData
-- (home/map.asm) stores the warp stepped ON and the map being left in
-- wPrevWarp / wPrevMapGroup / wPrevMapNumber on every warp taken, and
-- LoadMapAttributes' warp-coordinate read copies that triple into
-- wBackupWarpNumber / wBackupMapGroup / wBackupMapNumber whenever the warp
-- ARRIVED ON declares destination warp -1.  That refresh is what lets the one
-- shared POKECENTER_2F staircase lead back down into whichever centre's
-- stairs were climbed, and what tells an elevator door which floor it was
-- entered from before Elevator_GoToFloor overwrites the triple with the
-- chosen row.  Without it the -1 warp resolves to nothing and the tile is
-- simply dead -- the player is trapped upstairs in every Pokemon Center.
--
-- EnterMapWarp's `.SaveDigWarp` (home/map.asm) is the second writer, and it
-- writes the same triple: walking through a door out of an OUTDOOR map
-- (CheckOutdoorMap -- ROUTE or TOWN) into an INDOOR one (CheckIndoorMap --
-- INDOOR, CAVE, DUNGEON or GATE) records the door used, so Dig and Escape Rope
-- pay out to THAT entrance rather than to whichever one banked the triple
-- last.  MOUNT_MOON_SQUARE and TIN_TOWER_ROOF are the routine's own two
-- exceptions: outdoor maps sitting inside indoor ones, which the rope must
-- never drop the player onto.  The cart keeps this in wDigWarpNumber and
-- friends; this port banks one triple for both readers, which is what
-- World:escapeRopeTarget resolves through.
local DIG_WARP_OUTDOOR = { ROUTE = true, TOWN = true }
local DIG_WARP_INDOOR = {
  INDOOR = true, CAVE = true, DUNGEON = true, GATE = true,
}
local DIG_WARP_EXCLUDED = {
  MOUNT_MOON_SQUARE = true, TIN_TOWER_ROOF = true,
}

function World:recordWarpBackup(prevMapId, prevWarpIndex, arrivalWarp,
    destMapId)
  if not (prevMapId and prevWarpIndex) then return end
  if arrivalWarp and arrivalWarp.destWarp == 0xff then
    self.backupWarp = { warp = prevWarpIndex, map = prevMapId }
    return
  end
  if DIG_WARP_EXCLUDED[prevMapId] then return end
  local from = self.maps and self.maps[prevMapId]
  local into = destMapId and self.maps and self.maps[destMapId]
  if not (from and into) then return end
  if not DIG_WARP_OUTDOOR[from.environment] then return end
  if not DIG_WARP_INDOOR[into.environment] then return end
  self.backupWarp = { warp = prevWarpIndex, map = prevMapId }
end

-- wPrevWarp's find: the index of the warp event being stepped on, in the map
-- that declared it.  Warp defs are shared tables, so identity is the match.
function World:warpIndexOf(warpDef)
  local warps = self.map and self.map.def and self.map.def.warps
  for index, row in ipairs(warps or {}) do
    if row == warpDef then return index end
  end
  return nil
end

-- the resolved destination passes through warp.destination, so a mod can
-- reroute one door without owning the warp table -- the same three returns and
-- the same vanilla link src/world/Warp.lua uses under Gen 1
local function warped(mapId, x, y) return mapId, x, y end

function World:takeWarp(warpDef)
  if not warpDef or not warpDef.destMap then return false end
  local destMapId, destWarpNumber = self:resolveWarp(warpDef)
  local dest = self.maps[destMapId]
  if not dest then return false end
  local destWarp = dest.warps and dest.warps[destWarpNumber]
  if not destWarp then return false end
  local destX, destY = destWarp.x, destWarp.y
  -- ctx keeps Gen 1's three keys.  `lastMap` is the -1 backup triple
  -- (World:recordWarpBackup), which is Gen 2's version of the remembered
  -- outdoor side Gen 1 resolves LAST_MAP through; `destWarp` is the warp
  -- NUMBER the resolve landed on, which Gen 1's warp table has no equivalent
  -- of.  A reroute onto a map this cache does not hold is refused here rather
  -- than left for setMap, so the sound and the backup writes never happen for
  -- a warp that cannot be taken.
  if Runtime.wantsHook("warp.destination") then
    destMapId, destX, destY = Runtime.call("warp.destination", warped,
      destMapId, destX, destY,
      { warp = warpDef, lastMap = self.backupWarp, destWarp = destWarpNumber,
        data = self.game and self.game.data, maps = self.maps })
    if not (destMapId and self.maps[destMapId] and destX and destY) then
      return false
    end
  end
  self:warpSound()
  -- wBackupMapGroup / wBackupMapNumber: the map being LEFT.  The elevator's
  -- .FindCurrentFloor is the only thing that reads it, and it is what makes
  -- "Now on:" say the floor you got in from.
  self.backupMapId = self.map and self.map.id
  -- wPrevWarp / wPrevMapGroup / wPrevMapNumber, read before the load pulls
  -- the source map out from underfoot.
  local prevMapId = self.map and self.map.id
  local prevWarpIndex = self:warpIndexOf(warpDef)
  -- Gen 1's five payload keys, unchanged, and the coordinates are the HOOKED
  -- ones so a listener and a warp.destination wrapper never disagree about
  -- where the player went.  `toWarp` is the destination warp number, which the
  -- Gen 1 warp record has no field for.
  Runtime.emit("player.warped", { fromMap = prevMapId, toMap = destMapId,
                                  x = destX, y = destY, warp = warpDef,
                                  toWarp = destWarpNumber })
  return self:runMapSetup(MAPSETUP.DOOR, function()
    local ok = self:setMap(destMapId, destX, destY,
      (self.player and self.player.facing) or "down")
    if ok then
      self:spawnFacing()
      self:recordWarpBackup(prevMapId, prevWarpIndex, destWarp, destMapId)
    end
    return ok
  end)
end

-- RefreshPlayerSprite (engine/overworld/map_objects.asm) is the whole rule for
-- which way a map load leaves the player pointing: CheckWarpFacingDown against
-- the tile they ARRIVE on, then `call c, SpawnInFacingDown`.  A tile that is
-- not in that array keeps the facing they walked in with -- so you enter a
-- building still facing up (the mat inside is a COLL_WARP_CARPET_*) and step
-- out of one facing the street (the doorway outside is COLL.DOOR).
--
-- It runs AFTER the load for the same reason the cart's does: the array is
-- indexed by wPlayerTileCollision, which is the DESTINATION map's tile.
--
-- This replaces a guess that compared the destination Y against the map height.
-- That agreed with the cart at New Bark Town's two ends by luck and had no
-- reason to anywhere else: a ladder in the middle of a cave floor is neither
-- the top row nor the bottom one.
function World:spawnFacing()
  local p = self.player
  if not (self.map and p) then return end
  if Permissions.warpFacesDown(self.map:cellCollision(p.cellX, p.cellY)) then
    p.facing = "down"
  end
end

-- A neighbour map, built once and kept for its collision alone: the seam
-- queries below run on the per-step path.
function World:connectionMap(mapId)
  self.connectionMaps = self.connectionMaps or {}
  local cached = self.connectionMaps[mapId]
  if cached ~= nil then return cached or nil end
  local def = self.maps[mapId]
  local tileset = def and self.tilesets[def.tileset]
  local map = (def and tileset) and Map.new(def, tileset) or false
  self.connectionMaps[mapId] = map
  return map or nil
end

-- home/map.asm:1908 GetMovementPermissions
function World:cellCollisionAcross(map, cx, cy)
  if map:inBounds(cx, cy) then return map:cellCollision(cx, cy) end
  local dir
  if cy < 0 then dir = "up"
  elseif cy >= map.heightCells then dir = "down"
  elseif cx < 0 then dir = "left"
  elseif cx >= map.widthCells then dir = "right"
  end
  local conn = dir and map:connection(DIR_CONN[dir])
  local dest = conn and conn.mapId and self.maps[conn.mapId]
  local destMap = dest and self:connectionMap(conn.mapId)
  if destMap then
    local x, y = Map.connectionLanding(dest, conn, dir, cx, cy)
    local vertical = dir == "up" or dir == "down"
    local want = (vertical and cx or cy) - (conn.offset or 0) * 2
    -- connectionLanding clamps into the destination; past the end of the strip
    -- the buffer still holds this map's own border block
    if x and (vertical and x or y) == want then
      return destMap:cellCollision(x, y)
    end
  end
  return map:cellCollision(cx, cy)
end

-- Seamless edge cross: swap map data, park the player one cell before the
-- landing (same world pixels the neighbor strip already showed), and keep
-- the step running so the seam does not hitch.
function World:tryConnection(dir)
  local connKey = DIR_CONN[dir]
  local side = self.map:connection(connKey)
  -- A side may hold several connections (editor-only extras); pick the one
  -- whose seam sits under the player's position along the edge.
  local conn = side
  if type(side) == "table" and not (side.mapId or side.map) then
    local isH = (connKey == "north" or connKey == "south")
    local cell = isH and self.player.cellX or self.player.cellY
    conn = nil
    for _, c in ipairs(side) do
      if c and (c.mapId or c.map) then
        local destDef = self.maps[c.mapId or c.map]
        local along = cell - (c.offset or 0) * 2
        local dim = destDef
          and (((isH and destDef.width) or destDef.height) * 2) or math.huge
        if along >= 0 and along < dim then conn = c; break end
      end
    end
    conn = conn or side[1]
  end
  if not conn or not conn.mapId then return false end
  local dest = self.maps[conn.mapId]
  if not dest then return false end
  local x, y = Map.connectionLanding(
    dest, conn, dir, self.player.cellX, self.player.cellY)
  if not x then return false end
  local destMap = self:connectionMap(conn.mapId)
  if not destMap then return false end
  -- home/map.asm:1946 GetMovementPermissions side-wall arm
  if dir == "down"
     and Permissions.neighborBlocksDown(dir, destMap:cellCollision(x, y)) then
    return false
  end
  -- A surfing crossing lands on water, which isWalkable refuses; the arm the
  -- step would have taken is what decides, the same as it does inside the map.
  local landable
  if FieldMoves.isSurfing(self.playerState) then
    landable = Permissions.surfable(destMap:cellCollision(x, y)) ~= nil
  else
    landable = destMap:isWalkable(x, y)
  end
  if not landable then return false end

  local p = self.player
  local d = Map.DELTA[dir]
  self:setMap(conn.mapId, x, y, dir, { seamless = true })
  p.cellX, p.cellY = x - d[1], y - d[2]
  p.px, p.py = p.cellX * 16, p.cellY * 16
  p.facing = dir
  p.targetX, p.targetY = x, y
  p.moving = true
  p.progress = 0
  FixedStep:discardCatchup()
  return true
end

-- .TranslateIntoMovement (engine/overworld/player_movement.asm) picks the arm
-- off wPlayerState, and .Normal and .Surf differ in exactly two things: which
-- permission test the step runs (.CheckLandPerms against LAND_TILE versus
-- .CheckSurfPerms, which takes LAND and WATER alike), and what a LAND answer
-- means -- an ordinary step for one, .ExitWater for the other.
--
-- Player:tryMove owns the turn-in-place timing and the step bookkeeping, and
-- none of that changes between the two arms; only the map's answer does.  So
-- the surf arm hands tryMove a proxy that answers .CheckSurfPerms rather than
-- growing a second copy of the timing.
function World:surfMap(map)
  map = map or self.map
  return {
    inBounds = function(_, x, y) return map:inBounds(x, y) end,
    isWalkable = function(_, x, y)
      return Permissions.surfable(map:cellCollision(x, y)) ~= nil
    end,
  }
end

-- A map proxy that refuses every step but keeps bounds honest.  Handed to
-- tryMove when GetMovementPermissions forbids the direction: the press still
-- has to TURN the player (the cart's .bump path runs after the facing is
-- written), so the refusal cannot short-circuit above tryMove.
local function refusingMap(map)
  return {
    inBounds = function(_, x, y) return map:inBounds(x, y) end,
    isWalkable = function() return false end,
  }
end

-- the movement.speed chain's vanilla link, hoisted so an empty chain allocates
-- no closure on a per-step path
local function sameFrames(frames) return frames end

-- .TryJump: the refused step becomes a two-cell STEP_LEDGE when the player
-- STANDS on a ledge tile whose .ledge_table row includes the facing.  The cart
-- runs it after .TryStep fails for any reason (permission or NPC alike).  The
-- landing tile is checked here where the cart does not bother -- no real map
-- has a blocked landing, and a hop into scenery would strand the player.
function World:tryLedgeJump(dir)
  local p, map = self.player, self.map
  local facings = Permissions.ledgeFacings(
    map:cellCollision(p.cellX, p.cellY))
  if not (facings and facings[dir]) then return false end
  local d = Map.DELTA[dir]
  local tx, ty = p.cellX + d[1] * 2, p.cellY + d[2] * 2
  if not map:inBounds(tx, ty) then return false end
  if not map:isWalkable(tx, ty) then return false end
  for _, e in ipairs(self.entities or {}) do
    if e ~= p then
      if e.cellX == tx and e.cellY == ty then return false end
      if e.moving and e.targetX == tx and e.targetY == ty then return false end
    end
  end
  p.targetX, p.targetY = tx, ty
  p.moving = true
  p.jumping = true
  -- JumpStep res IN_GRASS_F and calls neither UpdateTallGrassFlags nor
  -- ShakeGrass (engine/overworld/movement.asm:741-770).
  p.inGrass, p.grassShake = false, nil
  p.progress = 0
  -- engine/overworld/map_objects.asm:1163
  p.stepFrames = Player.STEP_FRAMES * 2
  self:playSfxNamed("Sfx_JumpOverLedge", SFX.JUMP_OVER_LEDGE)
  return true
end

-- NormalStep's begin-of-step grass work (engine/overworld/movement.asm:657-674);
-- UpdateTallGrassFlags only RE-tests while IN_GRASS is set (map_objects.asm:226).
function World:playerStepGrass()
  local p = self.player
  if not (p and p.moving) or p.jumping or (p.progress or 0) ~= 0 then return end
  local grass = self:grassAt(p.targetX or p.cellX, p.targetY or p.cellY)
  if p.inGrass then p.inGrass = grass end
  p.grassShake = grass or nil
end

function World:movePlayer(dir)
  local p, map = self.player, self.map
  -- .DoStep's choice between STEP_WALK and STEP_BIKE, made fresh for every
  -- step: a step already under way keeps the duration it started with, and the
  -- downhill exception means the answer can change from cell to cell.
  p.stepFrames = Bike.stepFrames(
    self.playerState, dir, self:downhill(), Player.STEP_FRAMES)
  -- movement.speed, the same name and the same ctx keys src/world/Player.lua
  -- offers under Gen 1 (running shoes, dash, a bike that is not the bike).
  -- Gen 2 adds `downhill` and `playerState`, because Gold's own answer already
  -- depends on both: the Cycling Road forces a step whose duration changes from
  -- cell to cell.  Per-step hot path, so the ctx is only built when a chain
  -- exists.
  if Runtime.wantsHook("movement.speed") then
    local save = self.game and self.game.save
    local frames = Runtime.call("movement.speed", sameFrames, p.stepFrames, {
      onBike = FieldMoves.isBiking(self.playerState),
      surfing = FieldMoves.isSurfing(self.playerState),
      downhill = self:downhill() and true or false,
      playerState = self.playerState,
      player = p,
      input = self.game and self.game.input,
      save = save,
    })
    p.stepFrames = math.max(1, math.floor(tonumber(frames) or p.stepFrames))
  end
  -- GetMovementPermissions: the standing tile's side-wall kind and Gold's
  -- neighbour arms veto the direction before any walkable test runs.  Both
  -- .CheckLandPerms and .CheckSurfPerms read the same wTilePermissions, so the
  -- veto applies to walking and surfing alike.
  local permitted = Permissions.stepPermitted(
    function(x, y) return self:cellCollisionAcross(map, x, y) end,
    p.cellX, p.cellY, dir)
  -- `.CheckNPC`'s IsNPCAtCoord answers for a BIG_OBJECT's whole 2x2 blob, and
  -- Player:tryMove's entity scan only ever compares the one cell an object
  -- stands on -- so the three cells the Vermilion Snorlax overhangs are vetoed
  -- here instead.  Same refusal shape as the permission veto above: the press
  -- still has to turn the player, so it cannot short-circuit tryMove.
  if permitted then
    local d = Map.DELTA[dir]
    local npc = d and self:npcAt(p.cellX + d[1], p.cellY + d[2])
    if npc and npc.bigObject then permitted = false end
  end
  local result
  if not FieldMoves.isSurfing(self.playerState) then
    result = p:tryMove(dir, permitted and map or refusingMap(map),
                       self.entities)
    if result == "blocked" and self:tryLedgeJump(dir) then
      result = "moved"
    end
  else
    result = p:tryMove(dir, permitted and self:surfMap(map)
                            or refusingMap(map), self.entities)
    if result == "moved"
        and Permissions.surfable(map:cellCollision(p.targetX, p.targetY))
          == "land" then
      -- .ExitWater: GetOutOfWater writes PLAYER_NORMAL before .DoStep, then
      -- PlayMapMusic swaps the surf theme back (home/audio.asm:308)
      self:applyPlayerState(FieldMoves.PLAYER_NORMAL)
      local audio = self.game and self.game.data and self.game.data.audio
      if audio and audio.runtime then
        Music.playMap(self.game.data, map.id, nil,
                      FieldMoves.isSurfing(self.playerState), nil,
                      self:mapMusicSong(map.id))
      end
    end
  end
  -- .DoStep's .FinishFacing latch, and .StandInPlace / ._WalkInPlace clearing
  -- it.  A successful step OR turn records the direction; a bump (blocked /
  -- edge) is what ends an ice slide.
  if result == "moved" or result == "turned" then
    self.turningDirection = dir
  elseif result == "blocked" or result == "edge" then
    self.turningDirection = nil
  end
  -- NormalStep, in order (engine/overworld/movement.asm:657-674): InitStep has
  -- already moved OBJECT_TILE_COLLISION onto the destination.
  if result == "moved" then self:playerStepGrass() end
  return result
end

function World:clearWarpCooldownIfLeft()
  local cool = self.warpCooldown
  if not cool then return end
  local p = self.player
  if p.cellX ~= cool.x or p.cellY ~= cool.y then
    self.warpCooldown = nil
  end
end

function World:warpsSuppressed()
  local cool = self.warpCooldown
  if not cool then return false end
  local p = self.player
  return p.cellX == cool.x and p.cellY == cool.y
end

-- Answers whether it TOOK a warp, and World:step has to end the step on a true.
-- Stepping onto a warp tile is PLAYEREVENT_WARP: the cart writes wScriptRunning
-- and DoPlayerEvent hands the frame to WarpToNewMapScript, so the rest of that
-- frame's overworld loop -- including DoPlayerMovement -- never runs.  Falling
-- through to World:movePlayer instead is what let a still-held direction take
-- one free step on the far side of the door, which put the player one cell too
-- far into Elm's Lab before the map's own scene script could start walking them
-- (ElmsLab_WalkUpToElmMovement is nine steps from the mat and ended at (4,1)
-- rather than (4,2)).
function World:checkWarpOnArrive()
  local p = self.player
  local coll = self.map:cellCollision(p.cellX, p.cellY)
  if not Permissions.isWarpCollision(coll) then return false end
  local entry = self.map:warpAt(p.cellX, p.cellY)
  if not entry then return false end
  if Permissions.isImmediateWarp(coll) then
    if self:warpsSuppressed() then return false end
    return self:takeWarp(entry.def) and true or false
  end
  local need = Permissions.carpetDirection(coll)
  if need and self.heldDir == need then
    return self:takeWarp(entry.def) and true or false
  end
  return false
end

function World:checkCarpetWhileStanding()
  local p = self.player
  if p.moving or not self.heldDir then return false end
  local coll = self.map:cellCollision(p.cellX, p.cellY)
  local need = Permissions.carpetDirection(coll)
  if need and self.heldDir == need then
    local entry = self.map:warpAt(p.cellX, p.cellY)
    if entry then
      self:takeWarp(entry.def)
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Map callbacks (home/map.asm RunMapCallback).
-- ---------------------------------------------------------------------------

-- RunMapCallback.FindCallback: walk the map's callback list and take the FIRST
-- row whose execution index matches.  A second row of the same type is dead on
-- the cart, so it is dead here.
function World:mapCallbackScript(kind)
  local def = self.map and self.map.def
  for _, cb in ipairs((def and def.callbacks) or {}) do
    if cb.callback == kind and cb.scriptKey then return cb.scriptKey end
  end
  return nil
end

-- RunMapCallback proper.  Every one of these is a script, run through the same
-- interpreter every other script goes through -- see Vm:runCallback for why it
-- is a nested run rather than Vm:start, and why it cannot block.
--
-- The five types and where the cart runs each:
--
--   MAPCALLBACK_NEWMAP    HandleNewMap, before the block buffer is filled
--   MAPCALLBACK_CMDQUEUE  HandleContinueMap, right after ClearCmdQueue
--   MAPCALLBACK_TILES     LoadBlockData, after the buffer is refilled from ROM
--   MAPCALLBACK_OBJECTS   LoadMapObjects, before the object list goes live
--   MAPCALLBACK_SPRITES   LoadUsedSpritesGFX -- no Gold map has one
--
-- Gold's 84 callbacks are 39 NEWMAP, 24 OBJECTS, 19 TILES and 2 CMDQUEUE, and
-- between them they are the flypoint flags, Mom's worried phone call, the day
-- of the week's travelling NPCs, the Elite Four doors sealing behind you, the
-- Ruins of Alph floors, the Goldenrod underground doors, and the slot that puts
-- Sudowoodo on the map at all.
function World:runMapCallback(kind)
  local key = self:mapCallbackScript(kind)
  if not (key and self.vm) then return false end
  return self.vm:runCallback(key) and true or false
end

-- ---------------------------------------------------------------------------
-- wCmdQueue (engine/overworld/cmd_queue.asm, home/stone_queue.asm).
-- ---------------------------------------------------------------------------

-- MAPCALLBACK_CMDQUEUE, and the `writecmdqueue` command that is its whole body
-- on both maps that have one.
--
-- The extracted callback is preferred: maps.lua now carries the map's callback
-- list and the extractor follows `writecmdqueue`'s operand through the cmdqueue
-- struct into the stonetable, so the rows and their per-boulder scripts come
-- out of the cart.  CmdQueue.STONE_TABLES stays as the fallback for a cache
-- built before that, and is what the pins in tests/gen2_world_test.lua compare
-- the extracted rows against.
--
-- This READS the callback script rather than running it, which is enough
-- because `writecmdqueue` / `endcallback` is the whole body on both maps -- and
-- it has to, because CmdQueue.write wants the entry back as a value while the
-- command's own hook only answers a boolean.  World:writeCmdQueue is what the
-- callback would have called; running the body as well would write the queue
-- twice into two of its four slots.
function World:extractedCmdQueue()
  local key = self:mapCallbackScript("MAPCALLBACK_CMDQUEUE")
  if not key then return nil end
  for _, cmd in ipairs(self.scripts[key] or {}) do
    if cmd.op == "writecmdqueue" then
      local entry = CmdQueue.fromExtracted(cmd.queue, self.map.id)
      if entry then return entry end
    end
  end
  return nil
end

function World:writeCmdQueue()
  if not self.map then return false end
  local entry = self:extractedCmdQueue() or CmdQueue.mapEntry(self.map.id)
  if not entry then return false end
  return CmdQueue.write(self.cmdQueue, entry) ~= nil
end

function World:delCmdQueue(kind)
  return CmdQueue.delete(self.cmdQueue, kind)
end

-- HandleCmdQueue, once a frame from the overworld loop -- so not while a script
-- is up, which is also what stops the queue re-firing on the boulder it is
-- already busy removing.
--
-- The objects handed over are the port's NPCs, wearing the CART's object ids
-- (`object_const_def` is `const_def 2`, and `disappear` already speaks that
-- numbering), because those are what a stonetable row names.
function World:handleCmdQueue()
  if not (self.map and self.vm) then return false end
  if self:busy() then return false end
  if CmdQueue.count(self.cmdQueue) == 0 then return false end
  local objects = {}
  for _, npc in ipairs(self.npcs) do
    local obj = npc.def
    if obj and obj.index then
      objects[#objects + 1] = {
        id = obj.index + 1,
        movement = obj.movement,
        cellX = npc.cellX, cellY = npc.cellY,
        moving = npc.moving and true or false,
      }
    end
  end
  local map = self.map
  local row = CmdQueue.poll(self.cmdQueue, {
    objects = objects,
    warps = (map.def and map.def.warps) or {},
    collisionAt = function(x, y) return map:cellCollision(x, y) end,
  })
  if not row then return false end
  -- CallMapScript + EnableScriptMode: the row's script runs like any other.
  return self.vm:start(row.script)
end

-- ---------------------------------------------------------------------------
-- The per-step event chain (engine/overworld/events.asm CountStep).
--
-- src/world/gen2/StepEvents.lua owns the ORDER and the counters; everything
-- here is the presentation the cart's player-event scripts put over it.
-- ---------------------------------------------------------------------------

local function monName(mon)
  if type(mon) ~= "table" then return "?" end
  return mon.nickname or mon.name or mon.species or "?"
end

-- What CountStep's routines need from outside the save.
function World:stepContext()
  local def = self.map and self.map.def
  return {
    data = self.game and self.game.data,
    -- CheckTime reads wTimeOfDay (engine/events/checktime.asm:2), so the
    -- caller windows follow the clock even inside a pinned-palette room.
    phone = {
      map = def, maps = self.maps, daytime = self.tod,
      clock = self.game and self.game.clock,
    },
    -- GetMapPhoneService: zero means the map HAS service, which maps.lua has
    -- already decoded into a boolean.
    phoneService = def and def.phoneService,
    playerState = self.playerState,
    -- "Don't count steps in link communication rooms."  This port has link
    -- play but no link overworld room, so the gate can only ever be false --
    -- it is written out so the day one is added nobody has to rediscover it.
    linkMode = false,
  }
end

-- CheckTileEvent calls this between the coord events and the wild roll, and a
-- CARRY out of it queues a player event.  Answers true when the caller must
-- stop the step: an egg that hatched or a mon that dropped to poison does not
-- also walk into a Rattata.
function World:countStep()
  local save = self.game and self.game.save
  if not save then return false end
  local event = StepEvents.count(save, self:stepContext())
  if not event then return false end
  if event.kind == "hatch" then
    -- PLAYEREVENT_HATCH is HatchEggScript, and HatchEggScript is one command:
    -- `callasm OverworldHatchEgg / end`.  Routed through the callasm registry
    -- rather than called straight so the routine has exactly one port, whether
    -- it is reached from here or from a script that hits its address.
    CallAsm.run(self, "OverworldHatchEgg")
  elseif event.kind == "poisonFaint" then
    self:poisonFaintScript(event)
  elseif event.kind == "poisonHurt" then
    -- .PlayPoisonSFX alone: the sound and the four-frame BG flash, no script.
    CallAsm.run(self, "PlayPoisonSFX")
  elseif event.kind == "repel" then
    self:repelWoreOff()
  elseif event.kind == "phoneCall" then
    self:receivePhoneCall(event.call)
  end
  return event.blocks and true or false
end

-- RepelWoreOffScript (engine/events/repel.asm): opentext, one line, waitbutton.
function World:repelWoreOff()
  self:showText(Strings("REPEL's effect\nwore off."))
end

-- .Script_MonFaintedToPoison, via .CheckWhitedOut.  One line per mon that
-- actually dropped, HAPPINESS_POISONFAINT applied to each, and then
-- CheckPlayerPartyForFitMon decides between closing the box and the whiteout.
--
-- The order is the cart's: the happiness hit lands BEFORE the text, and the
-- whiteout only after every fainted mon has been named.
function World:poisonFaintScript(event)
  local save = self.game and self.game.save
  local party = (save and save.party) or {}
  local Happiness = require("src.core.gen2.Happiness")
  local lines = {}
  for _, index in ipairs(event.fainted or {}) do
    local mon = party[index]
    if mon then
      Happiness.change(mon, "HAPPINESS_POISONFAINT")
      lines[#lines + 1] = Strings("%s\nfainted!", monName(mon))
    end
  end
  CallAsm.run(self, "PlayPoisonSFX")
  local i = 0
  local function next()
    i = i + 1
    if lines[i] then
      self:showText(lines[i], next)
      return
    end
    if event.whiteout then self:whiteOut() end
  end
  next()
end

-- OverworldWhiteoutScript's tail, for the poison path only: the Bug Contest
-- abort belongs to the script and is not modelled here, so this is
-- HalveMoney (the wallet only -- Mom's savings, if any, are untouched: the
-- cart's own HalveMoney shifts wMoney alone) plus the trip back to the spawn
-- point.
--
-- Both callasm halves go through the registry: HalveMoney is the 24-bit
-- `srl a / rra / rra` and GetWhiteoutSpawn is the IsSpawnPoint check that
-- falls back to SPAWN_HOME.  Only the first has an effect today --
-- World:warpToSpawn prefers the `blackoutmod` map itself over the SPAWN_* row
-- it matches -- but running the pair keeps the script order honest.
function World:whiteOut()
  self:showText(
    Strings("You have no more\nPOKéMON that can\011fight!"), function()
    CallAsm.run(self, "HalveMoney")
    CallAsm.run(self, "GetWhiteoutSpawn")
    self:healParty()
    -- Guarded because healPoint walks the spawn table to answer: with nobody
    -- listening the blackout must not pay for a lookup warpToSpawn is about to
    -- make again anyway.
    if Runtime.wants("world.blacked_out") then
      Runtime.emit("world.blacked_out",
        { save = self.game and self.game.save, healTarget = self:healPoint() })
    end
    self:warpToSpawn()
  end)
end

-- HatchEggs (engine/pokemon/breeding.asm).  One slot at a time, in party order,
-- for every egg whose counter has reached zero:
--
--   "Huh?" (a `para "@"`, so the box clears and waits)
--   EggHatch_AnimationSequence
--   an empty box (_BreedClearboxText)
--   "<NAME> came<LINE>out of its EGG!" with sound_caught_mon
--   "Give a nickname to<LINE><NAME>?" -> the naming screen, or not
--
-- These four strings are hand-written from data/text/common_2.asm rather than
-- read out of text.lua, for the same reason the Pokegear's radio lines are:
-- the extractor only follows text a SCRIPT points at, and nothing points at
-- this block.  The animation itself is src/ui/gen2/EggHatchAnim.lua.
function World:hatchEggs()
  local save = self.game and self.game.save
  local data = self.game and self.game.data
  if not (save and data) then return end
  local Breeding = require("src.core.gen2.Breeding")
  local queue = Breeding.readyToHatch(save)
  local at = 0
  local function nextEgg()
    at = at + 1
    local index = queue[at]
    if not index then
      -- RestartMapMusic: the standard menu header the hatch ran under is gone.
      self:restoreMapMusic()
      return
    end
    self:showText("Huh?", function()
      local hatched, effects = Breeding.hatch(data, save, index)
      if not hatched then return nextEgg() end
      -- Breeding.hatch already ran SetSeenAndCaughtMon; the Togepi flag is the
      -- one side effect it hands back rather than setting, because wEventFlags
      -- belongs to the world.  Events are keyed by NUMBER, the way the
      -- extractor emits them, so the constant is resolved here.
      if effects and effects.togepi and self.events then
        self.events:set(EVENT_TOGEPI_HATCHED, true)
        self.peopleDirty = true
      end
      local name = monName(hatched)
      local function announce()
        -- `sound_caught_mon` sits inside _BreedEggHatchText, before its
        -- text_promptbutton: the jingle plays as the line lands, not after it.
        self:playSfxNamed("Sfx_CaughtMon", 2)
        self:showText(Strings("%s came\nout of its EGG!", name), function()
          -- _BreedAskNicknameText ends `done`, not `prompt`, so YesNoBox opens
          -- over the question with no button press in between.  That is exactly
          -- what askYesNo's instant re-show of lastText does.
          self.lastText = Strings("Give a nickname to\n%s?", name)
          self:askYesNo(function(yes)
            if not yes then return nextEgg() end
            self:nameHatchling(hatched, nextEgg)
          end)
        end)
      end
      -- EggHatch_AnimationSequence sits between the "Huh?" box and the line
      -- above (engine/pokemon/breeding.asm:664).  It is a whole screen -- it
      -- blanks the map and takes the music -- so it goes on the stack; with no
      -- stack to push onto (a headless run) the beat is simply skipped, the
      -- way every other Gold cutscene degrades.
      local game = self.game
      if game and game.stack then
        Screens.push(game, "Gen2EggHatchAnim", {
          mon = hatched,
          species = hatched.species,
          menuGfx = data.gen2MenuGfx,
          onDone = function()
            game.stack:pop()
            announce()
          end,
        })
      else
        announce()
      end
    end)
  end
  nextEgg()
end

-- `ld b, NAME_MON / farcall NamingScreen`, with wStringBuffer1 (the species
-- name) already in the header slot.  A cancelled screen is the same as "no
-- thanks": InitName copies the species name back over the nickname either way.
function World:nameHatchling(mon, onDone)
  local game = self.game
  if not (game and game.stack) then return onDone() end
  local data = game.data or {}
  local icons = data.gen2Icons
  local iconId = icons and icons.species and icons.species[mon.species]
  local entry = iconId and icons.icons and icons.icons[iconId]
  local done = function(name)
    game.stack:pop()
    -- _InitString's blank test, not a length one: "zero or more spaces
    -- followed by a null" (home/string.asm:6-30), and the keyboard's blank
    -- cells are real typeable characters, so an all-space entry reaches here
    -- and has to fall back to the species name the same way an empty one does.
    if name and name:gsub(" ", "") ~= "" then mon.nickname = name end
    onDone()
  end
  Screens.push(game, "Gen2NamingScreen", {
    type = "nickname",
    monName = mon.name or mon.species,
    iconPath = entry and entry.image or nil,
    menuGfx = data.gen2MenuGfx,
    onDone = done,
    onCancel = function() done(nil) end,
  })
end

-- Script_ReceivePhoneCall's overworld half.  The caller's script lives in ROM
-- bank $41, which the extractor reaches by seeding its queue from PhoneContacts
-- and SpecialPhoneCallList -- no map points into that bank, so those two tables
-- are the only way in.  The script runs inside the ring chrome
-- (src/core/gen2/PhoneRing.lua: the SFX_CALL page, the Click!, the countdown
-- restart), and wCurCaller is parked on the VM first so GetCallerLocation's
-- two specials (RandomPhoneMon / RandomPhoneWildMon) know who is talking.
--
-- The drop path below is kept for a cache built before that.  Clearing the
-- queue when a call has no body is not tidying-up, it is required: the cart
-- does NOT count a step on which a special call fires, so a call that can never
-- run would freeze wStepCount forever and stop eggs hatching outright -- the
-- exact bug this chain exists to fix.
World.unrunnableCalls = nil

function World:receivePhoneCall(call)
  local key = call and call.scriptKey
  if key and self.vm and self.vm.scripts[key] then
    local Phone = require("src.core.gen2.Phone")
    local name, className = Phone.contactName(call.contact,
      self.game and self.game.data and self.game.data.trainers)
    self.vm.curPhoneCaller = call.contact
    local rows = require("src.core.gen2.PhoneRing").script(call, name,
      className)
    if self.vm:start(rows) then return true end
  end
  local save = self.game and self.game.save
  if save then require("src.core.gen2.Phone").clearSpecialCall(save) end
  self.unrunnableCalls = (self.unrunnableCalls or 0) + 1
  if self.unrunnableCalls == 1 then
    print(("[gold] special phone call %s has no script in this cache " ..
      "(re-import: bank $41 is reached from PhoneContacts); dropped so the " ..
      "step counter keeps running")
      :format(tostring(call and call.specialName)))
  end
  return false
end

function World:updatePeople()
  for _, npc in ipairs(self.npcs) do
    npc:update(self.map, self.entities)
  end
  for _, g in ipairs(self.ghosts) do
    g.npc:update(g.map, g.peers)
  end
end

-- Once a second, ask whether the clock rolled into a new time of day; if it
-- did, drop the baked map images so they come back in the new palette.  The
-- cart does this from UpdateTimePals on the same cadence.
local PALETTE_POLL_STEPS = 60

function World:pollTimeOfDay()
  self.paletteClock = (self.paletteClock or 0) + 1
  if self.paletteClock < PALETTE_POLL_STEPS then return end
  self.paletteClock = 0
  if self:applyPalettes() then
    self.mapImages = {}
    self.mapImage = self:imageFor(self.map.id)
    self:rebuildNeighbors()
  end
  -- The hour-window objects (World:objectTimeVisible) key off the raw hour,
  -- not just the palette daytime, so their respawn rides the same poll: on the
  -- cart a reload is what refreshes wObjectMasks, and this poll is the port's
  -- stand-in for the player never being handed a stale mask for long.
  local hour = self:hour()
  if hour == self.lastMaskHour then return end
  -- The first poll only arms the latch; there is nothing to respawn yet.
  if self.lastMaskHour == nil then
    self.lastMaskHour = hour
    return
  end
  -- A rollover that lands while the world is busy is NOT consumed: the latch
  -- stays on the old hour so the next poll tries again.  Advancing it here
  -- would swallow the only edge this hour has, leaving the map with the
  -- previous hour's masks until the next boundary or a map reload.
  if self:busy() then return end
  self.lastMaskHour = hour
  -- The hour half of LoadObjectMasks (GetObjectTimeMask), and only that half:
  -- keepScripted leaves every byte a scene wrote alone, so a beast that jumped
  -- away or an NPC a script sent home does not walk back in at the top of the
  -- hour.
  self:loadObjectMasks({ keepScripted = true })
  self:rebuildPeople({ seamless = true })
end

-- Both tick once per logic frame AFTER the body -- where
-- src/world/OverworldController.lua:1039 drives the Gen 1 pair.  The body has
-- a dozen early returns, so the tail cannot live inside it.
function World:step()
  self:stepBody()
  if not self.map or not self.player then return end
  Follower.update(self.game, self)
  Gen1Facade.worldTick(self, 1 / 60)
end

function World:stepBody()
  if not self.map or not self.player then return end
  self:pollTimeOfDay()
  -- ShakeScreen and the `musicfadeout` tail both run UNDER a script (the VM is
  -- parked on the earthquake's own waitFrames while the screen is still
  -- rattling), so both tick above the busy() gate rather than below it.
  if self.shake then self:updateShake() end
  -- The map setup chain ticks above the busy() gate for the same reason: it IS
  -- what closes that gate, so nothing below can be allowed to advance it.
  if self.mapSetup then
    self:updateMapSetup()
    return
  end
  if self.pendingMusic then self:updateMusicFade() end
  if self.moveState then self:updateMovement() end
  -- Above the VM tick: a `waitbutton` under a `pokepic` is parked on this
  -- poll, and its resume has to run inside the same frame the press lands on.
  if self.waitButton then self:pollWaitButton() end
  if self.vm then self.vm:update() end
  -- ExitAllMenus takes the balance box down with everything else the script
  -- opened, so a box asked for by a script that then ended without a menu must
  -- not be waiting for the NEXT script's menu to inherit it.
  if self.scriptBalance and self.vm and not self.vm:running() then
    self.scriptBalance = nil
  end
  -- ExitAllMenus again, for the box a `stay` left standing: the two consumers
  -- (World:askYesNo, and the next page of the same MapTextbox in World:showText)
  -- both clear the latch before the script ends, so a box still held here is one
  -- whose script stopped early -- a `sjump` out of the arm, or an `end` a mod
  -- inserted.  Without this it would sit there forever with self.textbox set,
  -- and World:busy() would never let the player move again.
  if self.stayedTextBox and self.vm and not self.vm:running() then
    local held = self.stayedTextBox
    self.stayedTextBox = nil
    self.textbox = nil
    if self.game and self.game.stack and self.game.stack:top() == held then
      self.game.stack:pop()
    end
  end
  -- The rod cast and the tree shake tick alongside the VM rather than under
  -- the busy() gate below, because that gate is what they themselves close.
  if self.fishing then self:updateFishing() end
  if self.headbutt then self:updateHeadbutt() end
  if self.fieldMove then self:updateFieldMove() end
  -- QueueScript's own drain: a field move chosen from the party menu runs the
  -- first frame the overworld is back on top.
  if self.queuedFieldMove then self:runQueuedFieldMove() end
  -- The same drain for the ITEMFINDER's queued script.
  if self.queuedScript then self:runQueuedScript() end
  self:pollCaveFlicker()
  self:pollTileAnim()
  -- Any object visibility a running script changed lands here, once the
  -- script is over: RefreshMapSprites' timing, not the flag write's.
  if self.peopleDirty and not self:scriptRunning() then
    self.peopleDirty = nil
    self:rebuildPeople({ seamless = true })
  end
  -- UnfreezeAllObjects (engine/overworld/map_objects.asm), which EndScript
  -- runs: the talked-to object and every scripted stepper get their movement
  -- functions back the frame the whole interaction -- script, text boxes,
  -- pending movement -- has settled.
  if self.frozeNpcs and not self:busy() then
    self.frozeNpcs = nil
    -- The pool is the superset of the live lists, but a rebuild between the
    -- freeze and here can leave a frozen NPC only in self.npcs, so both walk.
    for _, npc in pairs(self.npcPool or {}) do npc.frozen = false end
    for _, npc in ipairs(self.npcs or {}) do npc.frozen = false end
  end
  -- WarpCheck's find, for the same reason and on the same clock: a script that
  -- ends standing on a warp tile takes it once the script is over, never
  -- inside the command that noticed it.
  if self.pendingWarp and not self:scriptRunning() then
    if self:takePendingWarp() then return end
  end
  if self.emote then
    self.emote.left = self.emote.left - 1
    if self.emote.left <= 0 then self.emote = nil end
  end
  -- The heal machine runs while the script is parked on its specialwait, so
  -- it ticks here above the input gate the same way the emote does; its
  -- last flash's onDone is what resumes the nurse.
  if self.healAnim then self:stepHealAnim() end

  -- HandleCmdQueue sits in the overworld loop, once a frame, above the input
  -- gate: it is what drops a boulder that is already sitting on a hole, and it
  -- has to see the frame the push finishes on.
  if self:handleCmdQueue() then return end

  -- Fire map-enter scene script once the warp settles.
  if self.pendingSceneScript and not self:busy() then
    self.pendingSceneScript = false
    if self:trySceneScript() then return end
  end

  -- CheckTimeEvents, from the player-event chain: the Bug Contest clock is the
  -- only thing it polls while the contest is up, and its carry is a script, so
  -- it goes above the input gate and below the one that says a script is
  -- already running.
  if not self:busy() and self:checkTimeEvents() then return end

  -- Freeze player input while a script / textbox / cutscene move is up.
  if self:busy() then
    -- Keep scripted entities animating mid-step.
    if self.player and self.player.moving then
      self:playerStepGrass()
      if self.player:update() then
        self.player.inGrass =
          self:grassAt(self.player.cellX, self.player.cellY)
      end
    end
    self:updatePeople()
    return
  end

  local p = self.player
  self:playerStepGrass()
  local landed = p:update()
  -- CopyCoordsTileToLastCoordsTile -> SetTallGrassFlags, which is what a step
  -- ENDS on (engine/overworld/map_objects.asm:196-208, :247).
  if landed then p.inGrass = self:grassAt(p.cellX, p.cellY) end
  -- CheckTrainerEvent is PlayerEvents' FIRST test (engine/overworld/events.asm:
  -- 245) and, unlike every arm of CheckTileEvent, it is not behind
  -- wEnabledPlayerEvents: MapEvents clears that byte on every pass
  -- (events.asm:168) and CheckPlayerState only re-sets it on a step that
  -- actually landed (events.asm:210-221).  So the sight cone is sampled EVERY
  -- overworld frame -- a spinner that rotates onto a standing player engages,
  -- and a sighting that arrived while a script held the world fires the frame
  -- the script ends.  It stays after p:update(), which is what commits
  -- cellX/cellY, and above the `landed` block so the cart's CheckTrainerEvent
  -- before CheckTileEvent (events.asm:249) ordering survives: a trainer whose
  -- line crosses a warp or a coord-event tile wins, as on hardware.
  if self:checkTrainerBattle() then return end
  if landed then
    -- hot path: the payload is only built when something is listening, exactly
    -- as OverworldState:onStepComplete guards it under Gen 1.  `tile` is the
    -- COLLISION byte here -- Gold's map has no per-cell tile id, and the
    -- collision byte is the value every one of the engine's own step tests
    -- reads -- and `daytime` is the palette set beside Gen 1's `tod`.
    if Runtime.wants("world.stepped") then
      Runtime.emit("world.stepped", {
        mapId = self.map.id, x = p.cellX, y = p.cellY,
        tile = self.map:cellCollision(p.cellX, p.cellY),
        tod = self.tod, daytime = self.daytime,
      })
    end
    self:clearWarpCooldownIfLeft()
    if self:checkWarpOnArrive() then return end
    if not self.map then return end
    if self:tryCoordScript() then return end
    -- CheckTileEvent's own order: the coord events, then CountStep, then
    -- RandomEncounter.  A carry out of CountStep queues a player event, so the
    -- step that hatches an egg or drops a poisoned mon never also walks into a
    -- wild battle.
    if self:countStep() then return end
    -- Grass rolls after the warp and coord checks, so stepping onto a door
    -- inside grass still warps rather than starting a battle.
    if self:tryWildEncounter() then return end
  end

  -- People keep their anim paths even while the player is idle / mid-step.
  self:updatePeople()

  -- .CheckForced / CheckStandingOnIce: while the tile underfoot is ice and a
  -- prior step latched .FinishFacing, THIS frame's d-pad is forced to that
  -- direction so one press slides until a non-ice landing or a bump.  The
  -- override is local -- writing it into heldDir would survive onto the floor
  -- after the slide (pollInput is what refreshes heldDir from real input) and
  -- keep the player walking.  StandInPlace clears the latch when idle off ice.
  --
  -- .CheckTile runs ABOVE both of those, and its HI_NYBBLE_CURRENT arm is
  -- stronger than either: a $3x tile underfoot picks the direction outright,
  -- with no d-pad and no latch involved.  On COLL_WATERFALL $33 that is one
  -- DOWN per frame, which is both the automatic plunge and the reason a
  -- waterfall column cannot be climbed by walking into it -- HM07's own climb
  -- is a scripted step under World:busy, which returns above this line.
  local dir = self.heldDir
  if not p.moving then
    local coll = self:playerCollision()
    local current = Permissions.currentDirection(coll)
      or Permissions.doorForcedDirection(coll)
    if current then
      dir = current
    elseif self.turningDirection
        and Permissions.isIce(coll) then
      dir = self.turningDirection
    elseif not dir then
      self.turningDirection = nil
    end
  end
  if not dir then
    p.turnArmed = true
    return
  end
  if p.moving then return end

  if self:checkCarpetWhileStanding() then return end

  local result = self:movePlayer(dir)
  if result == "edge" then
    self:tryConnection(dir)
  elseif result == "blocked" and p.facing == dir then
    -- .CheckNPC came back 2: something movable is in the way.  The step is
    -- lost either way, and the boulder is what moves.
    local d = Map.DELTA[dir]
    self:tryPushBoulder(dir, p.cellX + d[1], p.cellY + d[2])
  end
end

function World:pollInput(input)
  -- DoPlayerMovement .GetDPad: a DOWNHILL map with no direction held reads as
  -- DOWN, which is the Cycling Road rolling the player along on its own.
  self.heldDir = Bike.forcedDirection(heldDirection(input), self:downhill())
end

function World:zoomStep(delta)
  Zoom.step(delta, self:fitScale())
  self:rebuildNeighbors()
  self:rebuildPeople({ seamless = true })
end

function World:zoomCycle()
  Zoom.cycle(self:fitScale())
  self:rebuildNeighbors()
  self:rebuildPeople({ seamless = true })
end

-- The world pass, split in two because TILT projects only one of them: the
-- ground (the neighbor strips and this map) goes onto the perspective plane,
-- while everything standing on it draws upright.
function World:drawGround(s)
  local G = love.graphics
  local cam = self.camera
  G.setColor(1, 1, 1, 1)
  -- The border block first, tiled over the whole view: the map canvas is
  -- exactly the map's own blocks, so on anything smaller than the viewport
  -- (GOLDENROD_DEPT_STORE_ELEVATOR is 2x2) the rest of the screen was the
  -- clear colour.  LoadMetatiles fills it with wMapBorderBlock instead, and
  -- the connection strips and the map draw straight over the top of it.
  if self.map then
    -- Destination size must be the CURRENT canvas (tilt grows it past the
    -- window).  getDimensions() is always the window, so a grown tilt capture
    -- used to tile the void against the wrong view and the fill drifted off
    -- the map grid as the camera moved.
    local canvas = G.getCanvas()
    local bw, bh
    if canvas then
      bw, bh = canvas:getDimensions()
    else
      bw, bh = Playfield.dimensions()
    end
    if BorderFill.fillBlock(self.map.def) == false then
      -- BLACK: World:draw clears to a brown letterbox, so the void itself
      -- has to be an actual black sheet or the map sits on that colour.
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, bw, bh)
      G.setColor(1, 1, 1, 1)
    else
      BorderFill.draw(self, self:borderImageFor(self.map.id),
        cam.x, cam.y, bw, bh, s, BorderFill.fillKey(self.map.def))
    end
  end
  for _, nb in ipairs(self.neighbors) do
    G.draw(nb.image,
      math.floor((nb.ox - cam.x) * s),
      math.floor((nb.oy - cam.y) * s),
      0, s, s)
    self:drawAnimCells(nb.id, nb.ox, nb.oy, s)
  end
  G.draw(self.mapImage,
    math.floor((0 - cam.x) * s),
    math.floor((0 - cam.y) * s),
    0, s, s)
  -- _AnimateTileset's VRAM writes, as an overlay: the map canvas is baked
  -- once and the four water / two flower frames go over the top of it
  -- (engine/tilesets/tileset_anims.asm:167, :197).
  self:drawAnimCells(self.map and self.map.id, 0, 0, s)
end

-- Everyone on the map, Y-sorted with the player, plus the emote bubble over
-- the top -- it is an OBJ at OAM priority on the cart, and nothing walks in
-- front of it in the half-second it is up.
--
-- `billboard` is nil on the flat path.  With TILT on it is a function that
-- takes a foot point in flat screen pixels and a draw callback, and slides the
-- draw onto that point's projection: only the ground tilts, so a standing
-- thing stays upright and unscaled and the one thing that moves is its anchor.
function World:drawPeople(s, billboard)
  local G = love.graphics
  local p = self.player
  local cam = self.camera
  local drawList = {
    { kind = "player", py = p.py, ox = 0, oy = 0 },
  }
  for _, npc in ipairs(self.npcs) do
    drawList[#drawList + 1] = {
      kind = "npc", npc = npc, ox = 0, oy = 0, py = npc.py,
    }
  end
  for _, g in ipairs(self.ghosts) do
    drawList[#drawList + 1] = {
      kind = "npc", npc = g.npc, ox = g.ox, oy = g.oy, py = g.oy + g.npc.py,
    }
  end
  table.sort(drawList, function(a, b) return a.py < b.py end)

  for _, entry in ipairs(drawList) do
    local ox = math.floor((entry.ox - cam.x) * s)
    local oy = math.floor((entry.oy - cam.y) * s)
    local entity = entry.kind == "player" and p or entry.npc
    local function body()
      if entry.kind == "player" then
        self.player:draw(ox, oy, s)
      else
        entry.npc:draw(ox, oy, s)
      end
      -- ShakeGrass rustle only while moving; drawGrassOver when standing/in grass
      -- so the BG tuft covers the feet.
      -- Only the current map's own entities: a ghost's cells belong to a
      -- neighbour's block list.
      if entry.ox == 0 and entry.oy == 0 then
        if entity.inGrass and not (entity.grassShake and entity.moving) then
          self:drawGrassOver(entity, ox, oy, s)
        end
        self:drawGrassShake(entity, ox, oy, s)
      end
    end
    if billboard then
      -- The foot is the baseline centre of the sprite's own cell.
      billboard(ox + (entity.px + 8) * s, oy + (entity.py + 16) * s, body)
    else
      body()
    end
  end

  self:drawEmote(s, billboard)
  self:drawHealAnim(s, billboard)
end

-- Split out of drawPeople so World:drawPipeline composites the one copy the
-- flat and tilt paths draw, not a second transcription of it.
function World:drawEmote(s, billboard)
  if not (self.emote and self.emote.image) then return end
  local G = love.graphics
  local cam = self.camera
  local e = self.emote
  local ex = math.floor((e.entity.px - cam.x) * s)
  local ey = math.floor((e.entity.py - 16 - cam.y) * s)
  -- SpawnEmote.EmoteObject (engine/overworld/map_objects.asm:2029) spawns the
  -- bubble as an OBJ on PAL_OW_EMOTE, which LoadMapPals resolves to the
  -- "silver" row of gfx/overworld/npc_sprites.pal (white / white / RGB
  -- 13,13,13 / black).  That row is byte-identical in all four daytime
  -- blocks, so the bubble is the same at any hour, but it still goes through
  -- the daytime lookup because that is what LoadMapPals does and it keeps the
  -- emote on the same path as every other OW sprite.  Blitting the extracted
  -- sheet raw left the interior at the DMG ramp's shade 1 (170 grey) instead
  -- of white: the Gen 2 repeat of #505.
  local emoteColors = Palettes.spritePalette(self.palettes,
    self.daytime or Palettes.daytimeFor(self.map and self.map.def,
      self:hour(), self.flashUsed),
    { paletteId = 5 })
  local function blit()
    G.setColor(1, 1, 1, 1)
    G.draw(e.image, ex, ey, 0, s, s)
  end
  local function body()
    -- GbcPalette.with, not useRaw: the DMG and CLASSIC colour modes still
    -- have to collapse the row to their own ramps, and it restores whatever
    -- shader the billboard pass had set rather than assuming none.
    if emoteColors and GbcPalette.available() then
      GbcPalette.with(emoteColors, blit)
    else
      blit()
    end
  end
  if billboard then
    billboard(ex + 8 * s, ey + 32 * s, body)
  else
    body()
  end
end

function World:drawWorldBody(s)
  self:drawGround(s)
  self:drawPeople(s)
end

-- Gold's half of the world-pipeline seam: same ctx keys, same order and the
-- same nil-falls-back-to-2D rule as src/world/OverworldController.lua:4867.
function World:drawPipeline(id, w, h, s)
  local G = love.graphics
  local cam = self.camera
  local ctx = {
    state = self, cam = cam,
    vw = self.viewW, vh = self.viewH,
    -- No BG-only shake here: World:draw slides the whole frame through
    -- camera.y, so the ground row IS the camera row.
    bgY = cam.y,
    width = w, height = h, scale = s,
    level = Pipelines.level(id),
    -- imageFor keys its bakes by GbcPalette.mode, so the colour is already in
    -- the art: nil, like Gen 1 returns in its true-colour modes.
    paletteFor = function() return nil end,
    spriteColors = function() return nil end,
    -- Gold's only standing effects; it has no dust/cutTree/bird/rod overlay,
    -- and Gen 1's `at` skips a nil body, so those keys are simply absent.
    fx = {
      emote = function() self:drawEmote(1, nil) end,
      heal = function() self:drawHealAnim(1, nil) end,
    },
  }
  -- `project(wx, wy)` -> canvas pixels, nil behind the camera.  s = 1 lays the
  -- closures out in world pixels off the flat foot, the unit Gen 1 uses.
  ctx.drawFx = function(project, scale)
    scale = scale or s
    local function at(fx, fy, body)
      local sx, sy = project(fx + cam.x, fy + cam.y)
      if not sx then return end          -- behind the camera
      G.push()
      G.scale(scale, scale)
      G.translate(sx / scale - fx, sy / scale - fy)
      body()
      G.pop()
    end
    self:drawEmote(1, at)
    self:drawHealAnim(1, at)
  end
  local override = Pipelines.drawWorld(id, ctx)
  -- world post-processes fold in here, so they never touch the text box on top
  if override then override = Pipelines.worldPresent(override, ctx) end
  return override
end

-- The perspective quad TILT draws the ground onto.  The shader and the
-- 4-vertex mesh are the renderer's -- the projection is the same one the Gen 1
-- world pass uses, so there is no reason for a second copy of either.
function World:tiltMesh()
  local Renderer = require("src.render.Renderer")
  local shader = Renderer.tiltShader and Renderer:tiltShader()
  local mesh = Renderer.tiltMesh and Renderer:tiltMesh()
  if not (shader and mesh) then return nil end
  return mesh, shader
end

-- `gw, gh` are the grown capture size from World:draw (Tilt.viewGrowth),
-- matching Renderer:worldViewSize.  Camera is already followed for that view.
function World:drawTilted(w, h, s, gw, gh)
  local mesh, shader = self:tiltMesh()
  if not mesh then
    self:drawWorldBody(s)
    return
  end
  local G = love.graphics
  gw = gw or w
  gh = gh or h
  -- Linear sampling on the tilt canvas softens the shimmer the perspective
  -- warp would otherwise put on every pixel edge; the flat path keeps nearest.
  if not self.tiltCanvas or self.tiltCanvas:getWidth() ~= gw
      or self.tiltCanvas:getHeight() ~= gh then
    if self.tiltCanvas and self.tiltCanvas.release then
      self.tiltCanvas:release()
    end
    self.tiltCanvas = PixelCanvas.new(gw, gh, "linear")
  end

  local previous = G.getCanvas()
  G.setCanvas(self.tiltCanvas)
  G.clear(0, 0, 0, 0)
  -- A canvas does not reset the transform, so anything drawn into one from
  -- inside a draw call needs push()/origin() around it.
  G.push()
  G.origin()
  self:drawGround(s)
  G.pop()
  G.setCanvas(previous)

  mesh:setTexture(self.tiltCanvas)
  mesh:setVertices(Tilt.meshCorners(gw, gh))
  G.push()
  G.translate((w - gw) / 2, (h - gh) / 2)
  G.setColor(1, 1, 1, 1)
  G.setShader(shader)
  G.draw(mesh)
  G.setShader()
  G.pop()

  -- ...and the standing things over it, each translated from its flat foot
  -- onto that foot's projection.  Nothing here is sheared or resized: tilt
  -- changes where a sprite stands, not what it looks like.
  self:drawPeople(s, function(fx, fy, body)
    -- The ground quad carries the flat canvas and nothing else, so a foot
    -- outside it has no ground under it; drawing it anyway put NPCs from two
    -- screens away over the border fill, where the map stops being drawn.
    if not Tilt.onGround(fx, fy, gw, gh, 32 * s) then return end
    local sx, sy = Tilt.groundPoint(fx, fy, gw, gh)
    G.push()
    G.translate(sx - fx + (w - gw) / 2, sy - fy + (h - gh) / 2)
    body()
    G.pop()
  end)
end

-- The COLOR option can change under a standing world (the hotkey, or the
-- OPTION screen closing), and the map is a baked canvas rather than a live
-- draw -- so the cached references have to be re-fetched when it does.  The
-- bakes themselves are keyed by mode in imageFor, so this is a pointer swap
-- after the first time each mode is seen, not a re-bake.
function World:refreshColorMode()
  local mode = GbcPalette.mode
  if self.colorMode == mode then return end
  self.colorMode = mode
  if not self.map then return end
  self.mapImage = self:imageFor(self.map.id)
  self:rebuildNeighbors()
end

function World:draw()
  local G = love.graphics
  local w, h = Playfield.dimensions()
  self:refreshColorMode()
  G.clear(0.07, 0.05, 0.02, 1)

  if not self.mapImage or not self.player then
    local silver = self:gsVersion() == 1
    if silver then G.setColor(0.74, 0.78, 0.83, 1)
    else G.setColor(0.85, 0.57, 0.13, 1) end
    G.printf(silver and "POKEMON SILVER" or "POKEMON GOLD",
      0, math.floor(h * 0.38), w, "center")
    G.setColor(0.92, 0.90, 0.82, 1)
    G.printf(self.status or "No map.",
      0, math.floor(h * 0.48), w, "center")
    G.printf("Press Escape to quit.", 0, math.floor(h * 0.62), w, "center")
    G.setColor(1, 1, 1, 1)
    return
  end

  local s = self:zoomScale()
  -- Decided before sizing the view: a world pipeline wins over tilt, and tilt
  -- grows the capture the way Renderer:worldViewSize does on Gen 1 so the
  -- camera, BorderFill and tilt canvas all share one grid.
  local pipelineId = Pipelines.worldPipeline()
  local tilt = (not pipelineId) and Tilt.active() and self:tiltMesh() ~= nil
  local gw, gh = w, h
  if tilt then
    local g = Tilt.viewGrowth()
    gw, gh = math.ceil(w * g), math.ceil(h * g)
  end
  local vw = math.ceil(gw / s)
  local vh = math.ceil(gh / s)
  if vw % 2 ~= 0 then vw = vw + 1 end
  if vh % 2 ~= 0 then vh = vh + 1 end
  if vw ~= self.viewW or vh ~= self.viewH then
    self:rebuildNeighbors()
    self:rebuildPeople({ seamless = true })
  end
  self.viewW, self.viewH = vw, vh

  local p = self.player
  self.camera:follow(p.px, p.py, vw, vh)
  -- StepFunction_ScreenShake adds its offset to wPlayerStepVectorY, i.e. the
  -- whole frame slides vertically while the ground stays put underneath.
  if self.shake then
    self.camera.y = self.camera.y + (self.shake.phase or 0)
  end
  local ScreenPosition = require("src.core.ScreenPosition")
  local posLift = 0
  if not ScreenPosition.skinActive(w, h) then
    posLift = ScreenPosition.lift(h, 144 * self:fitScale(),
      ScreenPosition.safeTop())
  end
  if posLift > 0 then
    self.camera.y = self.camera.y + posLift / s
  end

  local override = pipelineId and self:drawPipeline(pipelineId, w, h, s) or nil

  -- TILT projects the finished world frame, so with it on the map, people and
  -- emote go into a canvas first and that canvas is drawn as a perspective
  -- quad.  Everything after -- the encounter pic and the survey HUD -- stays
  -- flat, the same split the Gen 1 renderer makes; a pipeline's finished image
  -- lands in exactly the same place.
  if override then
    G.setColor(1, 1, 1, 1)
    G.draw(override, 0, 0)
  elseif tilt then
    self:drawTilted(w, h, s, gw, gh)
  else
    self:drawWorldBody(s)
  end

  -- Pokepic (engine/events/pokepic.asm:1-28): MenuBox at the header's coords,
  -- then the padded 7x7 frontpic at top+1, left+1.  UI, so fitScale not zoom.
  if self.pokePic then
    local sPic = self:fitScale()
    local pw = self.pokePic:getDimensions()
    local pad = POKEPIC.pad[math.floor(pw / 8)] or POKEPIC.pad[7]
    G.push()
    G.translate(math.floor((w - 160 * sPic) / 2),
      math.floor((h - 144 * sPic) / 2) - posLift)
    G.scale(sPic, sPic)
    G.setColor(1, 1, 1, 1)
    local function body()
      Font.drawBox(POKEPIC.left, POKEPIC.top, POKEPIC.w, POKEPIC.h)
      G.draw(self.pokePic, (POKEPIC.left + 1 + pad[1]) * 8,
        (POKEPIC.top + 1 + pad[2]) * 8)
    end
    if self.pokePicColors then
      GbcPalette.with(self.pokePicColors, body)
    else
      body()
    end
    G.pop()
    G.setColor(1, 1, 1, 1)
  end

  -- engine/events/poisonstep_pals.asm:9-42
  if self.poisonFlash and self.poisonFlash > 0 then
    self.poisonFlash = self.poisonFlash - 1
    if GbcPalette.mode == "gbc" then
      G.setColor(28 / 31, 21 / 31, 1, 0.55)
    else
      G.setColor(0, 0, 0, 0.45)
    end
    G.rectangle("fill", 0, 0, w, h)
    G.setColor(1, 1, 1, 1)
  end

  -- FadeOutToWhite / FadeOutToBlack, held until a FadeInFrom* clears it.  On
  -- the cart the pair brackets a scripted cutscene's set change (the Elite Four
  -- doors, the Radio Tower takeover, Lugia's chamber); the port has no
  -- palette-cycle fade, so the honest stand-in is the flat sheet the cart's own
  -- fade ends on, over the world and under the text box the script is running.
  if self.fade then
    -- fadeLevel is the map setup chain's four-step ramp; a fade special sets it
    -- to 1 because RotateThreePalettes* has already finished by the time the
    -- script that called it runs on.
    local a = self.fadeLevel or 1
    if self.fade == "white" then
      G.setColor(1, 1, 1, a)
    else
      G.setColor(0, 0, 0, a)
    end
    G.rectangle("fill", 0, 0, w, h)
    G.setColor(1, 1, 1, 1)
  end

  -- The survey overlay is a developer aid, not part of the game: POKEPORT_DEV
  -- (or the F3 toggle) shows it, a normal boot does not.
  if self.showDebugHud then
    local silver = self:gsVersion() == 1
    if silver then G.setColor(0.74, 0.78, 0.83, 1)
    else G.setColor(0.85, 0.57, 0.13, 1) end
    G.printf(silver and "POKEMON SILVER" or "POKEMON GOLD", 0, 10, w, "center")
    G.setColor(0.92, 0.90, 0.82, 1)
    local label = string.format("%s  (%d,%d)  %s  ·  %s  ·  zoom %s",
      self.map.id, p.cellX, p.cellY, p.facing,
      tostring(self.daytime), Zoom.offsetLabel(Zoom.offset))
    G.printf(label, 0, 28, w, "center")
    G.printf("Arrows move · wheel/-/= zoom · 4 cycle zoom · Escape quits",
      0, h - 28, w, "center")
    G.setColor(1, 1, 1, 1)
  end
end

-- exported for the Gen 1 FieldDefaults facade (src/mods/Gen2Compat.lua)
-- rather than duplicated there
World.PLAYER_SPRITE = PLAYER_SPRITE

return World
