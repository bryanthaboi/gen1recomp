-- Yellow's overworld companion Pikachu (pokeyellow engine/pikachu/
-- pikachu_follow.asm ShouldPikachuSpawn / SpawnPikachu_, plus the
-- talk-to-it mood beat of engine/pikachu/pikachu_emotions.asm
-- TalkToPikachu).  The follower is an NPC-shaped entity that lives in
-- ow.npcs (so the standard update/draw walk cycle runs) but never in
-- ow.entities -- like the original it does not block the player: walk
-- onto its cell and it simply trails to the cell you vacated.
--
-- Happiness rides in save.pikachuHappiness (wPikachuHappiness, seeded 90
-- by init_player_data.asm) and mood in save.pikachuMood (wPikachuMood,
-- neutral 128).  modifyHappiness below is the full ModifyPikachuHappiness
-- port (engine/events/pikachu_happiness.asm): the HappinessChangeTable
-- delta picked by the current happiness hundred-band, then the
-- PikachuMoods byte nudging the mood; onStep is poison.asm's
-- UpdatePikachuHappinessAndMood (256-step coin-flip WALKING bump, mood
-- converging by 1 per step toward 128).

local Collision = require("src.world.Collision")
local GameVersion = require("src.core.GameVersion")

local PikachuFollower = {}

local INDEX = 99 -- synthetic object index, clear of any map's real objects

local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

-- wPikachuHappiness boot value (engine/movie/oak_speech/
-- init_player_data.asm: happiness = 90)
local function happiness(save)
  if save.pikachuHappiness == nil then save.pikachuHappiness = 90 end
  return save.pikachuHappiness
end

function PikachuFollower.bumpHappiness(save, delta)
  save.pikachuHappiness =
    math.max(0, math.min(255, happiness(save) + delta))
end

-- HappinessChangeTable (engine/events/pikachu_happiness.asm): delta by
-- happiness band (<100 / <200 / rest), plus the PikachuMoods target byte
-- ($80 leaves the mood alone).  Keys mirror the PIKAHAPPY_* constants.
local HAPPINESS_CHANGES = {
  LEVELUP         = {   5,   3,   2, mood = 0x8a },
  USEDITEM        = {   5,   3,   2, mood = 0x83 },
  USEDXITEM       = {   1,   1,   0, mood = 0x80 },
  GYMLEADER       = {   3,   2,   1, mood = 0x80 },
  USEDTMHM        = {   1,   1,   0, mood = 0x94 },
  WALKING         = {   2,   1,   1, mood = 0x80 },
  DEPOSITED       = {  -3,  -3,  -5, mood = 0x62 },
  FAINTED         = {  -1,  -1,  -1, mood = 0x6c },
  PSNFNT          = {  -5,  -5, -10, mood = 0x62 },
  CARELESSTRAINER = {  -5,  -5, -10, mood = 0x6c },
  TRADE           = { -10, -10, -20, mood = 0x00 },
}

-- the companion mon: a healthy (or any) party PIKACHU stands in for the
-- original's OT-checked starter, same approximation as shouldSpawn
function PikachuFollower.starterInParty(save, needHealthy)
  for _, mon in ipairs(save.party or {}) do
    if mon.species == "PIKACHU"
       and (not needHealthy or (mon.hp or 0) > 0) then
      return mon
    end
  end
  return nil
end

function PikachuFollower.isStarterPikachu(save, mon)
  if not (mon and mon.species == "PIKACHU") then return false end
  local player = save.player or {}
  return mon.otId == player.id and mon.ot == player.name
end

function PikachuFollower.isFollowingDisabled(ow)
  return ow and (ow.pikachuBillsScene or ow.pikachuFanClubScene
    or ow.pikachuPewterSleepScene) and true or false
end

-- ModifyPikachuHappiness.  mon is the party mon the event applied to for
-- the per-mon reasons (IsThisPartyMonStarterPikachu); GYMLEADER and
-- WALKING instead require any healthy starter in the party
-- (IsStarterPikachuAliveInOurParty).
function PikachuFollower.modifyHappiness(save, reason, mon)
  if not GameVersion.isYellow() then return end
  local row = HAPPINESS_CHANGES[reason]
  if not row then return end
  if reason == "GYMLEADER" or reason == "WALKING" then
    if not PikachuFollower.starterInParty(save, true) then return end
  elseif not (mon and mon.species == "PIKACHU") then
    return
  end
  local h = happiness(save)
  local band = h < 100 and 1 or h < 200 and 2 or 3
  save.pikachuHappiness = math.max(0, math.min(255, h + row[band]))
  -- PikachuMoods: bytes above $80 only ever raise the mood (and defer to
  -- a pending scripted emotion modifier), bytes below only lower it
  local b = row.mood
  if b ~= 0x80 then
    local mood = save.pikachuMood or 128
    if b > 0x80 then
      if mood < b and not save.pikachuEmotionModifier then
        save.pikachuMood = b
      end
    elseif mood > b then
      save.pikachuMood = b
    end
  end
end

-- UpdatePikachuHappinessAndMood (engine/events/poison.asm): every 256th
-- step a coin flip on the WALKING bump; every step the mood converges by
-- 1 toward the neutral 128.
function PikachuFollower.onStep(save)
  if not GameVersion.isYellow() then return end
  save.pikachuWalkSteps = ((save.pikachuWalkSteps or 0) + 1) % 256
  local rand = love and love.math and love.math.random or math.random
  if save.pikachuWalkSteps == 0 and rand(0, 1) == 1 then
    PikachuFollower.modifyHappiness(save, "WALKING")
  end
  local mood = save.pikachuMood or 128
  if mood < 128 then
    save.pikachuMood = mood + 1
  elseif mood > 128 then
    save.pikachuMood = mood - 1
  end
end

-- ShouldPikachuSpawn, approximated: Yellow, the lab gift happened, and a
-- healthy Pikachu is in the party (the original checks the starter's OT
-- identity; a traded second Pikachu standing in is accepted here).
-- Surfing and biking hide the follower (BIT_PIKACHU_SPAWN flags).
local function shouldSpawn(game, ow)
  if not GameVersion.isYellow() then return false end
  local save = game.save
  if not (save.flags and save.flags.EVENT_GOT_STARTER) then return false end
  -- save.pikachuInBall mirrors DisablePikachuOverworldSpriteDrawing (pokeyellow
  -- scripts/OaksLab.asm); nil falls back to the rival-fight flag (#1009)
  if save.pikachuInBall == nil then
    if not save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB then return false end
  elseif save.pikachuInBall then
    return false
  end
  if save.onBike or (ow.player and ow.player.surfing) then return false end
  if not (game.data.sprites and game.data.sprites.SPRITE_PIKACHU) then
    return false
  end
  for _, mon in ipairs(save.party or {}) do
    if mon.species == "PIKACHU" and (mon.hp or 0) > 0 then return true end
  end
  return false
end

local function makeFollower(game, ow, x, y, facing)
  local NPC = require("src.world.NPC")
  local npc = NPC.new(game.data, ow.map.id, {
    index = INDEX, name = "PIKACHU_FOLLOWER", sprite = "SPRITE_PIKACHU",
    movement = "STAY", range = "NONE", x = x, y = y,
  })
  npc.pikachuFollower = true
  npc.wanders = false -- scripted facing only, never the STAY idle roll (#2117)
  -- pokeyellow engine/pikachu/pikachu_follow.asm:26
  npc.passable = true
  npc.facing = facing or "down"
  -- the idle animations below pose the walk cycle with no step under it,
  -- which NPC:walkPhase (moving-only) cannot express.  An instance field
  -- shadows the class method, so NPC:pose keeps working unchanged (#411).
  npc.walkPhase = function(self)
    local idle = self.idle
    if idle and idle.phase then return idle.phase % 2 end
    return NPC.walkPhase(self)
  end
  return npc
end

local function findFollower(ow)
  for i, npc in ipairs(ow.npcs or {}) do
    if npc.pikachuFollower then return npc, i end
  end
  return nil
end

local function remove(ow)
  local npc, i = findFollower(ow)
  if not npc then return end
  table.remove(ow.npcs, i)
  for j, e in ipairs(ow.entities or {}) do
    if e == npc then table.remove(ow.entities, j) break end
  end
end

-- pokeyellow engine/pikachu/pikachu_follow.asm:237
local OUTSIDE_BELOW = {
  VICTORY_ROAD_2F = true, ROUTE_7_GATE = true, ROUTE_8_GATE = true,
  ROUTE_16_GATE_1F = true, ROUTE_18_GATE_1F = true, ROUTE_15_GATE_1F = true,
  ROUTE_11_GATE_1F = true,
}
-- pokeyellow engine/pikachu/pikachu_follow.asm:247
local OUTSIDE_DOWN_ON_CELL = {
  VIRIDIAN_FOREST_NORTH_GATE = true, CERULEAN_BADGE_HOUSE = true,
  CERULEAN_TRASHED_HOUSE = true, VERMILION_DOCK = true,
  CELADON_MANSION_1F = true, ROUTE_2_GATE = true,
  FUCHSIA_GOOD_ROD_HOUSE = true,
}
-- pokeyellow engine/pikachu/pikachu_follow.asm:291
local INDOOR_RIGHT = {
  VIRIDIAN_FOREST = true, SAFARI_ZONE_CENTER_REST_HOUSE = true,
  SAFARI_ZONE_WEST_REST_HOUSE = true, SAFARI_ZONE_EAST_REST_HOUSE = true,
  SAFARI_ZONE_NORTH_REST_HOUSE = true, SAFARI_ZONE_SECRET_HOUSE = true,
  SILPH_CO_ELEVATOR = true, CELADON_MART_ELEVATOR = true,
  CINNABAR_LAB_TRADE_ROOM = true, CINNABAR_LAB_METRONOME_ROOM = true,
  CINNABAR_LAB_FOSSIL_ROOM = true,
}

-- pokeyellow home/overworld.asm:476,503,507
function PikachuFollower.warpSpawnState(fromOutside, fromMap, toMap, lastMap,
                                        facing)
  if fromOutside then
    -- pokeyellow engine/pikachu/pikachu_follow.asm:185
    if toMap == "OAKS_LAB" then return 6 end
    if toMap == "ROUTE_22_GATE" then return facing == "down" and 3 or 1 end
    if toMap == "MT_MOON_B1F" or toMap == "ROCK_TUNNEL_1F" then return 3 end
    if OUTSIDE_BELOW[toMap] then return 4 end
    if OUTSIDE_DOWN_ON_CELL[toMap] and facing == "down" then return 3 end
    return 1
  end
  if lastMap then
    -- pokeyellow engine/pikachu/pikachu_follow.asm:305
    if (fromMap == "ROUTE_22_GATE" or fromMap == "ROUTE_2_GATE")
       and facing == "up" then
      return 1
    end
    return 3
  end
  -- pokeyellow engine/pikachu/pikachu_follow.asm:257
  if toMap == "VIRIDIAN_FOREST_NORTH_GATE" then
    return facing == "up" and 1 or 0
  end
  if toMap == "VIRIDIAN_FOREST_SOUTH_GATE" then
    return facing == "down" and 0 or 1
  end
  if INDOOR_RIGHT[toMap] then return 1 end
  return 0
end

local BEHIND = { down = { 0, -1 }, up = { 0, 1 },
                 left = { 1, 0 }, right = { -1, 0 } }
local AHEAD = { down = { 0, 1 }, up = { 0, -1 },
                left = { -1, 0 }, right = { 1, 0 } }

-- pokeyellow engine/pikachu/pikachu_follow.asm:59
local function placementCell(ow, state)
  local p = ow.player
  local d
  if state == 1 then d = { 1, 0 }
  elseif state == 4 then d = { 0, 1 }
  elseif state == 5 then d = { 0, -1 }
  elseif state == 6 then d = { -1, 0 }
  elseif state == 2 then d = BEHIND[p.facing]
  elseif state == 7 then d = AHEAD[p.facing]
  else d = { 0, 0 } end
  d = d or { 0, 0 }
  local x, y = p.cellX + d[1], p.cellY + d[2]
  if (d[1] ~= 0 or d[2] ~= 0)
     and not (ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y)) then
    return p.cellX, p.cellY
  end
  return x, y
end

-- pokeyellow engine/pikachu/pikachu_follow.asm:148
local function placementFacing(ow, state)
  if state == 3 then return "down" end
  if state == 7 then return OPPOSITE[ow.player.facing] end
  return ow.player.facing
end

-- spawn cell: directly behind the player's facing when that cell is
-- walkable, else the player's own cell (it trails out on the next step)
local function spawnCell(ow)
  return placementCell(ow, 2)
end

-- pokeyellow engine/overworld/player_animations.asm:37
function PikachuFollower.placeAtSpawnState(ow, state)
  local npc = findFollower(ow)
  if not npc then return end
  npc.cellX, npc.cellY = placementCell(ow, state)
  npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
  npc.facing = placementFacing(ow, state)
  npc.targetX, npc.targetY = nil, nil
  npc.goalX, npc.goalY = nil, nil
  npc.moving = false
end

-- the live follower, for a caller that has to carry it across a setMap
-- that rebuilds ow.npcs (OverworldState:crossConnection, #427)
function PikachuFollower.current(ow)
  local npc = findFollower(ow)
  return npc
end

function PikachuFollower.onMapEntered(game, ow, opts, viaMapLoad)
  -- Bill's House owns a short scripted scene that deliberately keeps
  -- Pikachu off the normal trailing loop.  A new map instance ends it.
  ow.pikachuBillsScene = nil
  ow.pikachuFanClubScene = nil
  remove(ow)
  if not shouldSpawn(game, ow) then return end
  -- opts.keepPikachu is the follower a connection crossing kept alive:
  -- LoadMapHeader's connection path sets wPikachuSpawnState = 2 and bit 4
  -- of wPikachuOverworldStateFlags, so SchedulePikachuSpawnForAfterText
  -- takes .normal_spawn_state -- map coords rebased, sprite data and
  -- follow command buffer left alone.  Re-list the same instance and let
  -- rebase() shift its cell; a warp arrives without it and respawns
  -- under the player, the full spawn path of that same routine (the
  -- viaMapLoad spawn below, #863).
  local keep = opts and opts.keepPikachu
  if keep then
    table.insert(ow.npcs, keep)
    table.insert(ow.entities, keep)
    return
  end
  -- pokeyellow engine/pikachu/pikachu_follow.asm:52
  local state = opts and opts.pikachuSpawn
  if state == nil and viaMapLoad then state = 0 end
  local x, y, facing
  if state then
    x, y = placementCell(ow, state)
    facing = placementFacing(ow, state)
  else
    x, y = spawnCell(ow)
    facing = ow.player.facing
  end
  local npc = makeFollower(game, ow, x, y, facing)
  table.insert(ow.npcs, npc)
  -- entities is the draw list; passable keeps it out of collision
  table.insert(ow.entities, npc)
  ow.pikachuTrail = { x = ow.player.cellX, y = ow.player.cellY }
end

-- ---------------------------------------------------------------------
-- Idle behavior (pikachu_follow.asm Func_fc803 and the Func_fc842 roll it
-- hands off to).  Standing still, the follower burns down a frame
-- counter; at zero it either looks in a random direction (Random & $c,
-- another $20 frames later) or, when the buffered follow command puts it
-- two or more cells off the player (ComputePikachuFollowCommand's 5-8
-- band), rolls one of four in-place animations: a bounce, the walk cycle
-- on the spot, a two frame shuffle, or a clockwise spin.  Func_fc82e
-- drops whichever is running the moment the player takes a step.  Nothing
-- here plays a bubble or a cry -- those are TalkToPikachu's alone (#411).
-- ---------------------------------------------------------------------

local IDLE_LOOK = 0x20  -- Func_fc803's pause between random glances
local IDLE_REST = 0x10  -- Func_fc835's pause after an animation ends
local IDLE_FRAME = 8    -- frames per sprite frame in Func_fc8f8/92b/95d

local FACINGS = { "down", "up", "left", "right" }
-- Func_fc95d .Facings, the order the spin turns through
local CLOCKWISE = { down = "left", left = "up", up = "right", right = "down" }

-- Pointer_fc8d6, transposed to (dx, dy): the asm stores (y, x) and walks
-- the table backwards as the $11 counter runs down, so entry N here is
-- what counter N draws.  A sway four pixels right then four left with the
-- body bobbing up twice, netting zero displacement.
local BOUNCE = {
  {  0,  0 }, { -1, -2 }, { -2, -4 }, { -3, -2 }, { -4,  0 },
  { -3, -2 }, { -2, -4 }, { -1, -2 }, {  0,  0 }, {  1, -2 },
  {  2, -4 }, {  3, -2 }, {  4,  0 }, {  3, -2 }, {  2, -4 },
  {  1, -2 }, {  0,  0 },
}

local function randomInt(a, b)
  local rand = love and love.math and love.math.random or math.random
  return rand(a, b)
end

-- back onto the cell's own pixels: while the follower stands, nothing else
-- writes px/py, so the bounce offset has to be undone from here
local function idleReset(npc)
  npc.idle = nil
  npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
end

-- ComputePikachuFollowCommand: the command the idle state reads back is
-- 1-4 while the follower sits within a cell of the player and 5-8 once it
-- is two or more off, Y deciding whenever the rows differ.  Returns the
-- facing those 5-8 encode (Func_fc862 turns that way before it bounces),
-- or nil for the near band, which only ever glances.
local function strandedFacing(ow, npc)
  local p = ow.player
  local dy = p.cellY - npc.cellY
  if dy ~= 0 then
    if dy > -2 and dy < 2 then return nil end
    return dy > 0 and "down" or "up"
  end
  local dx = p.cellX - npc.cellX
  if dx > -2 and dx < 2 then return nil end
  return dx > 0 and "right" or "left"
end

-- Func_fc842: an even roll over the four PointerTable_fc85a entries
local function startIdleAnim(npc, facing)
  local roll = randomInt(0, 3)
  if roll == 0 then
    -- Func_fc862 turns toward the player, then asm_fc87f bounces
    npc.facing = facing or npc.facing
    npc.idle = { kind = "bounce", frames = 0x11 }
  elseif roll == 1 then
    npc.idle = { kind = "walk", frames = 0x30, tick = 0, phase = 0 }
  elseif roll == 2 then
    npc.idle = { kind = "shuffle", frames = 0x20, tick = 0, phase = 0 }
  else
    npc.idle = { kind = "spin", frames = 0x20, tick = 0 }
  end
end

local function idleTick(ow, npc)
  -- Func_fc82e: a step in progress ends the idle state outright
  if ow.player.moving then idleReset(npc) return end
  -- Every counter below burns one unit per UpdateSprites call, and a
  -- standing OverworldLoop spends two DelayFrames on each pass (home/
  -- overworld.asm: OverworldLoop delays, falls into OverworldLoopLessDelay
  -- which delays again, then .noDirectionButtonsPressed loops back), so the
  -- whole Func_fc803 family runs at half this port's 60Hz fixed step: the
  -- first glance is $20 CALLS, 64 frames, not 32 (#424).
  npc.idleClock = ((npc.idleClock or 0) + 1) % 2
  if npc.idleClock ~= 0 then return end
  local idle = npc.idle
  if not idle then
    idle = { kind = "wait", frames = IDLE_LOOK }
    npc.idle = idle
  end
  if idle.kind == "wait" then
    idle.frames = idle.frames - 1
    if idle.frames > 0 then return end
    local facing = strandedFacing(ow, npc)
    if facing then
      startIdleAnim(npc, facing)
    else
      npc.facing = FACINGS[randomInt(1, 4)]
      idle.frames = IDLE_LOOK
    end
    return
  end
  if idle.kind == "bounce" then
    local o = BOUNCE[idle.frames] or BOUNCE[1]
    npc.px = npc.cellX * 16 + o[1]
    npc.py = npc.cellY * 16 + o[2]
  else
    idle.tick = idle.tick + 1
    if idle.tick >= IDLE_FRAME then
      idle.tick = 0
      if idle.kind == "walk" then
        -- Func_fc8f8 runs the anim counter through all four frames; the
        -- top bit is the mirrored foot, which is our stepFlip
        idle.phase = (idle.phase + 1) % 4
        npc.stepFlip = idle.phase >= 2
      elseif idle.kind == "shuffle" then
        idle.phase = idle.phase == 0 and 1 or 0 -- Func_fc92b's xor $1
      else
        npc.facing = CLOCKWISE[npc.facing] or "down"
      end
    end
  end
  idle.frames = idle.frames - 1
  if idle.frames <= 0 then
    -- Func_fc835: a $10 frame rest, then the idle counter again
    idleReset(npc)
    npc.idle = { kind = "wait", frames = IDLE_REST }
  end
end

-- The cell ahead is a ledge the player just hopped (data/tilesets/
-- ledge_tiles.asm, the same row match OverworldState:checkLedgeHop makes).
-- The follower only ever retraces cells the player stood on, so a ledge
-- tile in the trail means the player jumped it (#409).
local function ledgeStep(game, ow, cx, cy, dir)
  local map = ow.map
  local d = Collision.DELTA[dir]
  local fx, fy = cx + d[1], cy + d[2]
  local lx, ly = cx + d[1] * 2, cy + d[2] * 2
  if not (map:inBounds(fx, fy) and map:inBounds(lx, ly)) then return false end
  local tileset = map.def.tileset
  local standing = map:cellTile(cx, cy)
  local front = map:cellTile(fx, fy)
  for _, ledge in ipairs(game.data.field.ledges or {}) do
    if (ledge.tileset or "OVERWORLD") == tileset
       and ledge.facing == dir and ledge.input == dir
       and ledge.standingTile == standing and ledge.ledgeTile == front then
      return true
    end
  end
  return false
end

-- Slide the follower into the connected map's coordinate frame by the
-- delta crossConnection applied to the player: the two maps are one
-- continuous world, so a seam is a pure translation.  MapX/MapY in
-- wSpritePikachuStateData2 are all .normal_spawn_state rewrites there,
-- never the pixel coords, which is why the original walks through a seam
-- instead of popping (#427).
function PikachuFollower.rebase(ow, dx, dy)
  local npc = findFollower(ow)
  if npc then
    npc.cellX, npc.cellY = npc.cellX + dx, npc.cellY + dy
    npc.px, npc.py = npc.px + dx * 16, npc.py + dy * 16
    if npc.targetX then npc.targetX = npc.targetX + dx end
    if npc.targetY then npc.targetY = npc.targetY + dy end
    if npc.goalX then npc.goalX = npc.goalX + dx end
    if npc.goalY then npc.goalY = npc.goalY + dy end
    -- Func_fc82e: the player is taking a step, so any idle pose is over
    if npc.idle then idleReset(npc) end
  end
  local trail = ow.pikachuTrail
  if trail then trail.x, trail.y = trail.x + dx, trail.y + dy end
end

local DIRS = { "up", "down", "left", "right" }

-- wPikachuCollisionCounter: 8 on a direction change (home/overworld.asm:189),
-- cleared with no d-pad held (:130) and once a step commits (:242)
local function tickCollisionCounter(game, ow, npc)
  local input = game.input
  local p = ow.player
  local dir
  if input then
    for _, d in ipairs(DIRS) do
      if input:isDown(d) then dir = d break end
    end
  end
  if not dir then
    ow.pikachuCollisionCounter = 0
    if ow.pikachuMovingDir then
      ow.pikachuLastStopDir = ow.pikachuMovingDir
      ow.pikachuMovingDir = nil
    end
    ow.pikachuTurnArmed = true
    return
  end
  if ow.pikachuTurnArmed and dir ~= ow.pikachuLastStopDir then
    ow.pikachuCollisionCounter = 8
    ow.pikachuTurnArmed = false
    ow.pikachuMovingDir = dir
    return
  end
  ow.pikachuMovingDir = dir
  if p.moving then
    ow.pikachuCollisionCounter = 0
    return
  end
  local n = ow.pikachuCollisionCounter or 0
  if n <= 0 then return end
  local tx, ty = Collision.target(p.cellX, p.cellY, dir)
  if p.facing == dir and npc.cellX == tx and npc.cellY == ty then
    ow.pikachuCollisionCounter = n - 1
  end
end

-- CollisionCheckOnLand's Pikachu branch -- home/overworld.asm:1234-1252
local function updatePassable(game, ow, npc)
  if PikachuFollower.isFollowingDisabled(ow) then
    npc.passable = false
    ow.pikachuCollisionCounter = 0
    return
  end
  tickCollisionCounter(game, ow, npc)
  if game.input and game.input:isDown("b") then
    npc.passable = true
    return
  end
  npc.passable = (ow.pikachuCollisionCounter or 0) <= 0
end

-- one follow step per frame: chase the cell the player last vacated
-- (pikachu_follow.asm keeps it one walk step behind)
function PikachuFollower.update(game, ow)
  if ow.pikaHop then return end -- the counter hop owns the follower (#417)
  local npc = findFollower(ow)
  -- home/overworld.asm:1238-1240
  if npc then updatePassable(game, ow, npc) end
  if PikachuFollower.isFollowingDisabled(ow) then return end
  if not npc then
    if shouldSpawn(game, ow) then PikachuFollower.onMapEntered(game, ow) end
    return
  end
  if not shouldSpawn(game, ow) then
    remove(ow)
    return
  end
  local p = ow.player
  local trail = ow.pikachuTrail
  if not trail then
    trail = { x = p.cellX, y = p.cellY }
    ow.pikachuTrail = trail
  end
  -- The follow command is queued the frame the player COMMITS a step, not
  -- the frame it lands: home/overworld.asm .noCollision sets wWalkCounter
  -- and calls Func_fcc08 (pikachu_follow.asm Func_fcc42 reads the direction
  -- of the step just started) before AdvancePlayerSprite, so Pikachu walks
  -- into the cell the player is vacating during that same step and rests
  -- exactly one cell behind.  Waiting for p.cellX to change put a whole
  -- extra step between them -- the two-tile gap of issue #410.  targetX/Y
  -- is the committed destination while a step is in flight and nil when
  -- standing, so a warp or teleport still registers here (and the far > 6
  -- snap below still catches it).
  local destX = p.targetX or p.cellX
  local destY = p.targetY or p.cellY
  if destX ~= trail.x or destY ~= trail.y then
    local stepDir = destY > trail.y and "down" or destY < trail.y and "up"
                    or destX > trail.x and "right" or "left"
    -- A ledge hop commits TWO steps (checkLedgeHop -> scriptMove(p, dir, 2),
    -- the two simulated presses of HandleLedges) but only ONE follow
    -- command: Func_fcc08 sees BIT_LEDGE_OR_FISHING and defers to
    -- Func_fcc64, which appends the $5-$8 hop on the takeoff step and
    -- appends nothing on the landing step (bit 6 of
    -- wPikachuOverworldStateFlags toggles between the two).  With no command
    -- behind it the hop cannot leave the buffer -- Func_fcc92 only pops once
    -- a second command is queued -- so Pikachu walks up to the cell the
    -- player took off from, waits there two cells behind (the Func_fc842
    -- idle rolls), and hops one player step later (#424, after #409).
    if trail.ledgeHop == stepDir then
      trail.ledgeHop = nil
      trail.x, trail.y = destX, destY
    else
      trail.ledgeHop = ledgeStep(game, ow, trail.x, trail.y, stepDir)
                       and stepDir or nil
      npc.goalX, npc.goalY = trail.x, trail.y
      trail.x, trail.y = destX, destY
    end
  end
  -- standing still with nothing to chase is the idle state (Func_fc803);
  -- once a step is under way NPC:update owns px/py, so only the idle
  -- record is dropped here -- never the interpolated pixels
  if npc.moving then npc.idle = nil return end
  if not npc.goalX then idleTick(ow, npc) return end
  local gx, gy = npc.goalX, npc.goalY
  if npc.cellX == gx and npc.cellY == gy then
    npc.goalX, npc.goalY = nil, nil
    idleTick(ow, npc)
    return
  end
  -- fell more than a screen behind (forced movement, warp math): snap
  local far = math.abs(npc.cellX - gx) + math.abs(npc.cellY - gy)
  if far > 6 then
    npc.cellX, npc.cellY = gx, gy
    npc.px, npc.py = gx * 16, gy * 16
    npc.goalX, npc.goalY = nil, nil
    npc.idle = nil -- the snap already rewrote px/py
    return
  end
  idleReset(npc) -- a real step overrides whatever the idle pose was
  local dir
  if npc.cellX < gx then dir = "right"
  elseif npc.cellX > gx then dir = "left"
  elseif npc.cellY < gy then dir = "down"
  else dir = "up" end
  npc.facing = dir
  npc.targetX = npc.cellX + (dir == "right" and 1 or dir == "left" and -1 or 0)
  npc.targetY = npc.cellY + (dir == "down" and 1 or dir == "up" and -1 or 0)
  -- the cell ahead is the ledge the player hopped: clear both cells in one
  -- step instead of stopping on the ledge (#409).  The trail above holds
  -- this back until the player commits a further step, so it fires from the
  -- cell on top of the ledge, a step late (#424).  pikachu_follow.asm
  -- Func_fcc08 appends the $5-$8 hop commands while BIT_LEDGE_OR_FISHING
  -- is set, and Func_fca0a runs them as two AddPikachuStepVector cells over
  -- one normal step's frames -- no arc and no shadow, the hop command only
  -- doubles the step vector (NPC:update's hopStep span).
  if ledgeStep(game, ow, npc.cellX, npc.cellY, dir) then
    local d = Collision.DELTA[dir]
    npc.targetX, npc.targetY = npc.cellX + d[1] * 2, npc.cellY + d[2] * 2
    npc.goalX, npc.goalY = npc.targetX, npc.targetY
    npc.hopStep = true
  end
  -- walk at the player's own step length (the bicycle is moot: shouldSpawn
  -- hides the follower on a bike, ShouldPikachuSpawn's wWalkBikeSurfState
  -- check), and halve it while more than one cell behind -- that is
  -- FastPikachuFollow, which pikachu_follow.asm picks whenever two or more
  -- steps are queued (AreThereAtLeastTwoStepsInPikachuFollowCommandBuffer:
  -- walk counter $4 instead of NormalPikachuFollow's $8).
  local stepLen = p.stepFramesCur or p.stepFrames or 16
  -- the hop is never a Fast step: Func_fc7aa jumps to Func_fca0a on the $4
  -- movement status BEFORE it asks AreThereAtLeastTwoSteps..., so its two
  -- cells ride one normal step's frames even though the goal is two away.
  if far > 1 and not npc.hopStep then
    stepLen = math.max(1, math.floor(stepLen / 2))
  end
  npc.stepFrames = stepLen
  npc.moving = true
  npc.progress = 0
  -- this frame's npc:update loop already ran (OverworldState:update walks
  -- self.npcs, then calls here), so burn the step's first frame now.
  -- Without it the step costs a frame more than the player's and Pikachu
  -- trails a pixel further every tile.
  npc:update(ow.map, ow.entities)
end

-- ---------------------------------------------------------------------
-- TalkToPikachu (engine/pikachu/pikachu_emotions.asm + data/pikachu/
-- pikachu_emotions.asm): pick a scripted emotion, then play its bubble
-- and voiced PCM clip, and raise the framed Pikachu picture the original
-- puts over the map (pikaemotion_pikapic -> pikachu_pic_animation.asm
-- PlacePikapicTextBoxBorder), drawn by OverworldController:drawUI.  Each
-- script's BASE 5x5 frame is ripped as pikachu/pikapic_N.png (#561); the
-- pikaframe overlays it alternates with are a second full-body pose out of
-- the same blob and are still unported, so picLift below stands in for
-- their motion and the battle front pic covers caches built before the
-- rip (#407).
-- ---------------------------------------------------------------------

-- PikachuEmotionTable, reduced to each entry's bubble + pikaemotion_pcm
-- clip (bubble names are the *_BUBBLE constants; nil cry = silent).
local EMOTIONS = {
  [1] = {},
  [2] = { bubble = "SMILE_BUBBLE", cry = 35 },
  [3] = { cry = 40 },
  [4] = { cry = 29 },
  [5] = { cry = 31 },
  [6] = { bubble = "SKULL_BUBBLE" },
  [7] = { cry = 1 },
  [8] = { cry = 39 },
  [9] = { bubble = "SKULL_BUBBLE", cry = 6, cryFirst = true },
  [10] = { bubble = "HEART_BUBBLE", cry = 5 },
  [11] = { bubble = "ZZZ_BUBBLE", cry = 37 },
  [12] = {},
  [13] = {},
  [14] = { bubble = "BOLT_BUBBLE", cry = 10 },
  [15] = { cry = 34 },
  [16] = { cry = 33 },
  [17] = { cry = 13 },
  [18] = {},
  [19] = { bubble = "HEART_BUBBLE", cry = 33 },
  [20] = { bubble = "HEART_BUBBLE", cry = 5 },
  [21] = { bubble = "FISH_BUBBLE" },
  [22] = { cry = 4 },
  [23] = { cry = 19 },
  [24] = { bubble = "EXCLAMATION_BUBBLE" },
  [25] = { bubble = "BOLT_BUBBLE", cry = 35 },
  [26] = { bubble = "ZZZ_BUBBLE", cry = 37 },
  [27] = { cry = 9 },
  [28] = { cry = 15 },
  [29] = { cry = 5 },
  [30] = { bubble = "HEART_BUBBLE", cry = 5, turnAway = true },
  [31] = { cry = 19 },
  [32] = { cry = 26 },
}

-- GetPikaPicAnimationScriptIndex (engine/pikachu/pikachu_pic_animation
-- .asm): mood picks the column (PikachuMoodLookupTable), happiness the
-- row (PikaPicAnimationScriptPointerLookupTable); the cell is the
-- emotion index.
local MOOD_THRESHOLDS = { 40, 127, 128, 210, 255 }
local MOOD_MATRIX = {
  { limit = 50,  14, 14, 6,  13, 13 },
  { limit = 100, 9,  9,  5,  12, 12 },
  { limit = 130, 3,  3,  1,  8,  8 },
  { limit = 160, 3,  3,  4,  15, 15 },
  { limit = 200, 17, 17, 7,  2,  2 },
  { limit = 250, 17, 17, 16, 10, 10 },
  { limit = 255, 17, 17, 19, 20, 20 },
}

-- wPikachuEmotionModifier values 1-5 (MapSpecificPikachuExpression
-- .Emotions): scripted one-shots -- 21 is the fishing-rod reaction
local MODIFIER_EMOTIONS = { 18, 21, 23, 24, 25 }

-- ExecutePikaPicAnimScript spends a Delay3 on every pass of its loop
-- (pikachu_pic_animation.asm PikaPicAnimTimerAndJoypad), so one script tick
-- is three 60Hz frames: the flat 50 frame hold this port used was under a
-- third of even the shortest script (#424).
local PIKAPIC_TICK = 3
local PIKAPIC_LIFT = 4 -- px the stand-in pic rises on an overlay run

-- pikaemotion_pikapic's script id per emotion: emotion N takes
-- PikaPicAnimScript N, except the four listed here (data/pikachu/
-- pikachu_emotions.asm).
local PIKAPIC_SCRIPT = { [29] = 10, [30] = 20, [31] = 23, [32] = 23 }

-- Per script: pikapic_setduration's tick count, and for the scripts whose
-- overlay is a whole second pose, that frameset's run lengths in ticks
-- (data/pikachu/pikachu_pic_objects.asm PikaPicAnimBGFrames_*, which script
-- N reaches as frameset N+5, or N+6 from script 10 up).  The list alternates
-- pikaframedelay (the base pic alone) and pikaframe (the overlay) starting
-- with a delay, so a frameset that opens on a pikaframe opens with a zero
-- here; the frameset restarts until pikapic_looptofinish runs the duration
-- out.  Scripts 1, 2, 3, 5, 6, 8 and 9 are left without a list on purpose:
-- their overlays (PikaAnimTilemap_14 to _22) only paint a few tiles over a
-- pic that otherwise stands still, so with no tiles to paint the port has
-- nothing to show for them and must not bob the whole picture instead.
local PIKAPIC = {
  [1]  = { dur = 40 },
  [2]  = { dur = 44 },
  [3]  = { dur = 80 },
  [4]  = { dur = 70,  seq = { 8, 8, 20, 8 } },
  [5]  = { dur = 32 },
  [6]  = { dur = 50 },
  [7]  = { dur = 58,  seq = { 0, 8, 2, 8, 2, 8 } },
  [8]  = { dur = 44 },
  [9]  = { dur = 56 },
  [10] = { dur = 56,  seq = { 8, 11, 5 } },
  [11] = { dur = 100, seq = { 20, 8, 20, 8 } },
  [12] = { dur = 50,  seq = { 13, 12, 100, 8 } },
  [13] = { dur = 50,  seq = { 5, 5, 5, 5, 100 } },
  [14] = { dur = 40,  seq = { 2, 2, 2, 2 } },
  [15] = { dur = 50,  seq = { 5, 5, 5, 5 } },
  [16] = { dur = 32,  seq = { 0, 8, 100 } },
  [17] = { dur = 100, seq = { 10, 3, 3, 3, 100 } },
  [18] = { dur = 32,  seq = { 3, 100, 8, 8 } },
  [19] = { dur = 44,  seq = { 0, 6, 6, 6, 6 } },
  [20] = { dur = 50,  seq = { 8, 12, 8, 12 } },
  [21] = { dur = 40,  seq = { 8, 104 } },
  [22] = { dur = 40,  seq = { 8, 100 } },
  [23] = { dur = 70,  seq = { 16, 16, 16, 16 } },
  [24] = { dur = 60,  seq = { 6, 6, 6, 6, 100 } },
  [25] = { dur = 50,  seq = { 6, 106 } },
  [26] = { dur = 100, seq = { 20, 8, 20, 116 } },
  [27] = { dur = 30,  seq = { 4, 100 } },
  [28] = { dur = 64,  seq = { 12, 12, 12, 100 } },
}

local function moodEmotion(save)
  local mood = save.pikachuMood or 128
  local column = 5
  for i, threshold in ipairs(MOOD_THRESHOLDS) do
    if mood <= threshold then column = i break end
  end
  local h = happiness(save)
  local row = MOOD_MATRIX[#MOOD_MATRIX]
  for _, r in ipairs(MOOD_MATRIX) do
    if h <= r.limit then row = r break end
  end
  return row[column]
end

-- MapSpecificPikachuExpression + TalkToPikachu's selection order
local function selectEmotion(game, ow, save)
  local mapId = ow.map.id
  -- engine/pikachu/pikachu_emotions.asm:303
  if mapId == "POKEMON_FAN_CLUB" then
    if not save.pikachuMapScriptActive then return 29 end
    if ow.pikachuFanClubScene then return 30 end
  elseif mapId == "PEWTER_POKECENTER" then
    -- engine/pikachu/pikachu_emotions.asm:320
    if ow.pikachuPewterSleepScene then return 26 end
  end
  -- BillsHouse_CheckPikachuEmotion -- scripts/BillsHouse_2.asm:88
  if mapId == "BILLS_HOUSE" then
    if ow.pikachuBillsScene
       and not save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR then
      return 23
    end
    return save.flags.EVENT_MET_BILL_2 and 31 or 32
  end
  local starter = PikachuFollower.starterInParty(save)
  if starter then
    if starter.status == "SLP" then return 11 end
    if starter.status then return 28 end
  end
  if mapId:find("POKEMON_TOWER_", 1, true) == 1 then return 22 end
  local modifier = save.pikachuEmotionModifier
  if modifier and MODIFIER_EMOTIONS[modifier] then
    save.pikachuEmotionModifier = nil
    return MODIFIER_EMOTIONS[modifier]
  end
  return moodEmotion(save)
end

local function bubbleIndex(game, name)
  local sheet = game.data.field and game.data.field.emotionBubbles
  for i, b in ipairs(sheet and sheet.bubbles or {}) do
    if b.name == name then return i end
  end
  return nil
end

local playEmotion

function PikachuFollower.talk(game, ow, npc, done)
  -- pikachu_follow.asm steps the follower on the player's own walk clock,
  -- so it is never mid-tile while the player stands and can always be
  -- addressed; this port's follow is a frame late, so land the step here
  -- rather than answer from between two cells (#407).  The emote hold
  -- returns before the npc update loop, so a follower left mid-step would
  -- freeze between cells for the whole beat.
  if npc.moving then
    npc.cellX, npc.cellY = npc.targetX or npc.cellX, npc.targetY or npc.cellY
    npc.targetX, npc.targetY = nil, nil
    npc.moving = false
    npc.progress = 0
    npc.hopStep = nil
  end
  idleReset(npc) -- the bubble anchor reads px/py, and the hold freezes it
  -- engine/pikachu/pikachu_emotions.asm:196
  local save = game.save
  local emotion = selectEmotion(game, ow, save)
  if ow.pikachuPewterSleepScene then
    local finish = done
    done = function()
      ow.pikachuPewterSleepScene = nil
      if finish then finish() end
    end
  end
  return playEmotion(game, ow, npc, emotion, { skippable = true, onDone = done })
end

-- engine/pikachu/pikachu_emotions.asm:14
function playEmotion(game, ow, npc, emotion, opts)
  opts = opts or {}
  local done = opts.onDone
  local e = EMOTIONS[emotion] or EMOTIONS[1]

  -- data/pikachu/pikachu_emotions.asm
  local function pikapic()
    local Sprites = require("src.pokemon.Sprites")
    local script = PIKAPIC_SCRIPT[emotion] or emotion
    local pic = "assets/generated/pikachu/pikapic_" .. script .. ".png"
    if not require("src.render.Assets").exists(pic) then
      pic = Sprites.path(game.data, "PIKACHU", "front",
                         { kind = "overworld" })
    end
    local anim = PIKAPIC[script] or PIKAPIC[1]
    local hold = anim.dur * PIKAPIC_TICK
    ow.emote = {
      npc = npc, frames = hold, bubble = false, pikaPic = pic,
      pikaSeq = anim.seq, pikaTotal = hold, skippable = opts.skippable,
      onDone = done,
    }
    return ow.emote
  end

  local function cry()
    if e.turnAway then
      -- engine/pikachu/pikachu_emotions.asm:203
      npc.facing = OPPOSITE[ow.player.facing] or npc.facing
    end
    local Sound = require("src.core.Sound")
    if e.cry then
      if not Sound.playPikaCry(game.data, e.cry) then
        Sound.playCry(game.data, "PIKACHU")
      end
    end
    return pikapic()
  end

  -- caches built before the Yellow bubble sheet only carry the three
  -- shared bubbles; a missing crop degrades to a silent hold
  local bi = e.bubble and bubbleIndex(game, e.bubble)
  -- engine/overworld/emotion_bubbles.asm:60
  -- data/pikachu/pikachu_emotions.asm:69
  local function bubbleHold(after)
    ow.emote = { npc = npc, frames = 60, bubble = bi, onDone = after }
    return ow.emote
  end
  if e.cryFirst then
    if not bi then return cry() end
    if e.cry then
      local Sound = require("src.core.Sound")
      if not Sound.playPikaCry(game.data, e.cry) then
        Sound.playCry(game.data, "PIKACHU")
      end
    end
    return bubbleHold(pikapic)
  end
  if bi then return bubbleHold(cry) end
  return cry()
end

-- Where the framed pic sits this frame.  The overlay a pikaframe run draws
-- is a second full-body pose (PikaAnimTilemap_23 and up replace all 5x5
-- tiles) out of gfx/pikachu/unknown_*, which the cache does not carry, so
-- the port lifts the one pic it has for the length of those runs -- the jump
-- the happy emotions make inside the box (#424, still on #407's stand-in).
function PikachuFollower.picLift(emote)
  local seq = emote and emote.pikaSeq
  if not seq then return 0 end
  local loop = 0
  for _, run in ipairs(seq) do loop = loop + run end
  if loop <= 0 then return 0 end
  local elapsed = math.max(0, (emote.pikaTotal or 0) - (emote.frames or 0))
  local tick = math.floor(elapsed / PIKAPIC_TICK) % loop
  for i, run in ipairs(seq) do
    if tick < run then return i % 2 == 0 and PIKAPIC_LIFT or 0 end
    tick = tick - run
  end
  return 0
end

-- Bill's House has three map-scripted Yellow companion beats
-- (BillsHouseScript0/2/5): Pikachu walks over to investigate Bill, waits at
-- the cell separator, then reacts when Bill reappears.  Keep it at the
-- machine until this map instance is discarded, just like the cartridge's
-- disabled following state.
-- (engine/overworld/emotion_bubbles.asm:60)
-- engine/pikachu/pikachu_emotions.asm:14
local function billsHouseEmotion(game, ow, npc, bubble, emotion, done)
  local function anim()
    playEmotion(game, ow, npc, emotion, { onDone = done })
  end
  if not bubble then return anim() end
  ow.emote = {
    npc = npc, frames = 60, bubble = bubbleIndex(game, bubble) or false,
    onDone = anim,
  }
end

-- pokeyellow engine/pikachu/pikachu_movement.asm:208-229
local PIKA_STEP_FRAMES = 16
-- pokeyellow engine/pikachu/pikachu_movement.asm:89,209
local PIKA_SLIDE_FRAMES = 32

local function movePikachu(ow, npc, steps, onDone)
  npc.goalX, npc.goalY = nil, nil
  npc.stepFrames = PIKA_STEP_FRAMES
  idleReset(npc)
  local function nextStep(i)
    local step = steps[i]
    if not step then
      if onDone then onDone() end
      return
    end
    npc.stepFrames = step[3] or PIKA_STEP_FRAMES
    ow:scriptMove(npc, step[1], step[2], function() nextStep(i + 1) end)
  end
  nextStep(1)
end

function PikachuFollower.onFanClubEntered(game, ow)
  if not (GameVersion.isYellow() and ow.map
      and ow.map.id == "POKEMON_FAN_CLUB") then return end
  if game.save.pikachuMapScriptActive then return end
  -- scripts/PokemonFanClub.asm:40
  local starter = PikachuFollower.starterInParty(game.save)
  local npc = findFollower(ow)
  if not npc or (starter and starter.status) then
    game.save.pikachuMapScriptActive = true
    return
  end
  ow.pikachuFanClubScene = true
  -- scripts/PokemonFanClub.asm:48-60
  ow.emote = {
    npc = npc, frames = 60,
    bubble = bubbleIndex(game, "EXCLAMATION_BUBBLE") or false,
    onDone = function()
      -- scripts/PokemonFanClub.asm:63
      local steps = { { "up", 1, PIKA_SLIDE_FRAMES }, { "right", 3 },
                      { "up", 1 } }
      movePikachu(ow, npc, steps, function()
        npc.facing = "up"
        -- data/maps/objects/PokemonFanClub.asm:21
        for _, other in ipairs(ow.npcs or {}) do
          if other.def and other.def.index == 3 then
            other.movementStatus = 2
            other.facing = "down"
            break
          end
        end
        -- engine/pikachu/pikachu_emotions.asm:309
        playEmotion(game, ow, npc, 29, { onDone = function()
          -- scripts/PokemonFanClub.asm:18
          game.save.pikachuMapScriptActive = true
        end })
      end)
    end,
  }
end

function PikachuFollower.onBillsHouseEnter(game, ow)
  if not (GameVersion.isYellow() and ow.map and ow.map.id == "BILLS_HOUSE") then
    return
  end
  -- BillsHouse_CheckMetBill (scripts/BillsHouse.asm:22-40) sets
  -- BIT_PIKACHU_MAP_SCRIPT_ACTIVE and rets nz before it looks at
  -- EVENT_MET_BILL_2; the bit rides sMainData, so a reload inside the house
  -- resumes at BillsHouseScript1's bare ret (#919).
  local active = game.save.pikachuMapScriptActive
  game.save.pikachuMapScriptActive = true
  if active then return end
  if game.save.flags.EVENT_MET_BILL_2 then return end
  -- BillsHouseScript0 (scripts/BillsHouse.asm:41-47) only runs the confused
  -- walk while CheckPikachuStatusCondition comes back clear
  -- (engine/pikachu/pikachu_status.asm:140, carry when the starter's status
  -- byte is nonzero); a statused starter keeps trailing the player instead,
  -- and that is the one state that lets onBillWalksAroundPlayer below fire,
  -- since the confused beat ends in DisablePikachuFollowingPlayer (#455).
  local starter = PikachuFollower.starterInParty(game.save)
  if starter and starter.status then return end
  local npc = findFollower(ow)
  if not npc then return end
  ow.pikachuBillsScene = true
  movePikachu(ow, npc, { { "right", 3 }, { "up", 1 } }, function()
    -- BillsHouse_CheckPikachuEmotion SCRIPT0 -- scripts/BillsHouse_2.asm:88
    billsHouseEmotion(game, ow, npc, "QUESTION_BUBBLE", 23)
  end)
end

-- BillsHousePikachuWatchPlayer (scripts/BillsHouse_2.asm:133-156), reached
-- from BillsHouseScript2 (scripts/BillsHouse.asm:58-69) only when the player
-- faces down -- so Bill has to walk around them -- and Pikachu is still
-- following, i.e. the confused beat above was skipped.  Both tables go
-- through TryApplyPikachuMovementData
-- (engine/events/try_pikachu_movement.asm:1-15), which keeps the data only
-- when the caller's b equals GetPikachuFacingDirectionAndReturnToE
-- (engine/pikachu/pikachu_follow.asm:1110-1151).  That byte is not the
-- sprite's facing: it is Pikachu's position relative to the player, UP when
-- Pikachu's MapY sits above the player's, DOWN below, and on a shared row
-- LEFT when west, RIGHT when east ($ff on the same cell).  So WatchPlayer1
-- (b = SPRITE_FACING_UP) means "Pikachu stands above the player" and
-- WatchPlayer2 (b = SPRITE_FACING_RIGHT) means "Pikachu stands level with
-- and east of the player".  ApplyPikachuMovementData_ walks a whole table
-- synchronously (engine/pikachu/pikachu_movement.asm:9-18), so the second
-- call does observe the finished walk; the two are mutually exclusive by
-- geometry rather than by timing, since both routes end at
-- (playerX - 1, playerY), west of the player, where the RIGHT test fails.
-- Each closes on PIKAMOVEMENT_LOOK_RIGHT, leaving Pikachu watching the
-- player while Bill talks; PIKAMOVEMENT_DELAY is dropped here as in the
-- beats above (#455).
function PikachuFollower.onBillWalksAroundPlayer(game, ow)
  if not (GameVersion.isYellow() and ow.map and ow.map.id == "BILLS_HOUSE")
     or ow.pikachuBillsScene then
    return
  end
  local npc = findFollower(ow)
  if not npc or not ow.player then return end
  local steps
  if npc.cellY < ow.player.cellY then       -- PikachuMovement_WatchPlayer1
    steps = { { "left", 1 }, { "down", 1 } }
  elseif npc.cellY == ow.player.cellY
     and npc.cellX > ow.player.cellX then   -- PikachuMovement_WatchPlayer2
    steps = { { "up", 1 }, { "left", 2 }, { "down", 1 } }
  else
    return
  end
  movePikachu(ow, npc, steps, function() npc.facing = "right" end)
end

function PikachuFollower.onBillEnteredMachine(game, ow)
  if not (GameVersion.isYellow() and ow.pikachuBillsScene) then return end
  local npc = findFollower(ow)
  if not npc then return end
  -- BillsHouseScript3 (pokeyellow scripts/BillsHouse.asm:100-115).  The two
  -- movement tables are named the wrong way round in the cartridge source:
  -- hl is seeded with ..._EnterCellSeparatorDown, then
  --   and a ; cp SPRITE_FACING_DOWN   (SPRITE_FACING_DOWN is 0)
  --   jr nz, .applyPikachuMovement
  -- keeps that seeded table when the player is NOT facing down, and only the
  -- fallthrough -- facing down -- swaps in ..._EnterCellSeparatorNotDown.
  -- So facing down takes the long way round the cell separator and every
  -- other facing walks straight up.  Following the label names instead of the
  -- branch inverts the scene (#455).
  local steps = ow.player.facing == "down"
      and { { "up", 1 }, { "left", 1 }, { "up", 2 }, { "right", 1 } }
      or { { "up", 3 } }
  movePikachu(ow, npc, steps, function()
    -- no EmotionBubble predef -- scripts/BillsHouse.asm:100
    npc.facing = "up"
    billsHouseEmotion(game, ow, npc, nil, 32)
  end)
end

function PikachuFollower.onBillExitedMachine(game, ow)
  if not (GameVersion.isYellow() and ow.pikachuBillsScene) then return end
  local npc = findFollower(ow)
  if not npc then return end
  idleReset(npc)
  npc.facing = "left"
  -- BillsHouse_CheckPikachuEmotion SCRIPT5 -- scripts/BillsHouse_2.asm:88
  billsHouseEmotion(game, ow, npc, "EXCLAMATION_BUBBLE", 27)
end

-- OaksLabPikachuMovementScript (pokeyellow scripts/OaksLab_2.asm): the
-- companion clears the cell the rival stops on (#1021)
function PikachuFollower.oaksLabMakeWay(game, ow, done)
  if not GameVersion.isYellow() then return false end
  local npc = findFollower(ow)
  if not npc or not ow.player then return false end
  local p = ow.player
  local steps, facing
  if p.cellY == 3 then -- .movement2, b = SPRITE_FACING_LEFT
    if not (npc.cellY == p.cellY and npc.cellX < p.cellX) then return false end
    steps, facing = { { "down", 1 }, { "right", 1 } }, "up"
  else -- OaksLabPikachuMovementData1, b = SPRITE_FACING_DOWN
    if npc.cellY <= p.cellY then return false end
    steps, facing = { { "left", 1 }, { "up", 1 } }, "right"
  end
  movePikachu(ow, npc, steps, function()
    npc.facing = facing -- PIKAMOVEMENT_LOOK_UP / _LOOK_RIGHT ends each table
    if done then done() end
  end)
  return true
end

-- ---------------------------------------------------------------------
-- PikachuWalksToNurseJoy (engine/pikachu/pikachu_emotions.asm, run by
-- engine/events/pokecenter.asm once the heal is accepted): the companion
-- looks up ($36) and hops onto the Poke Center counter.  The original
-- picks one of three movement scripts by where it stands -- below the
-- player (.PikaMovementData1: walk up left, hop up right), left of it
-- (.PikaMovementData2: hop up right) or right of it (.PikaMovementData3:
-- hop up left) -- and all three land on the counter tile directly in
-- front of the player.  Pikachu already above the player yields zero
-- movement bytes: no beat (#417).
-- ---------------------------------------------------------------------

local HOP_FRAMES = 32 -- engine/pikachu/pikachu_movement.asm:106
local HOP_HEIGHT = 8 -- engine/pikachu/pikachu_movement.asm:815

function PikachuFollower.hopToCounter(ow, done)
  local npc = GameVersion.isYellow() and findFollower(ow) or nil
  local p = ow.player
  local cx, cy = p:facingCell()
  -- the nurse is talked to across a counter tile (OverworldState:interact);
  -- anything else is the .pikachu_above_player no-op path
  if not npc or p.facing ~= "up" or not ow.map:isCounterCell(cx, cy) then
    if done then done() end
    return
  end
  local x, y = npc.cellX, npc.cellY
  local legs
  -- engine/pikachu/pikachu_emotions.asm:428
  if y > p.cellY then
    -- engine/pikachu/pikachu_emotions.asm:460
    legs = { { x = x - 1, y = y - 1 }, { x = x, y = y - 2, hop = true } }
  elseif y == p.cellY and p.cellX < x then
    -- engine/pikachu/pikachu_emotions.asm:473
    legs = { { x = x - 1, y = y - 1, hop = true } }
  elseif y == p.cellY then
    -- engine/pikachu/pikachu_emotions.asm:467
    legs = { { x = x + 1, y = y - 1, hop = true } }
  else
    if done then done() end
    return
  end
  npc.goalX, npc.goalY = nil, nil
  npc.targetX, npc.targetY = nil, nil
  npc.moving, npc.progress, npc.hopStep = false, 0, nil
  npc.hopShadowY = nil
  npc.idle = nil
  npc.facing = "up" -- $36, look up
  ow.pikaHop = {
    npc = npc, frames = 0, legs = legs, leg = 0, onDone = done,
    fromX = npc.px, fromY = npc.py,
  }
end

-- One frame of that hop.  OverworldState:update holds the world for it the
-- way it holds for the heal machine (only the top state updates, so this
-- has to sit between the two text boxes).
function PikachuFollower.updateHop(ow)
  local h = ow.pikaHop
  if not h then return end
  h.frames = h.frames + 1
  local leg = h.legs[h.leg]
  if leg then
    local t = math.min(1, h.frames / HOP_FRAMES)
    h.npc.px = h.fromX + (leg.x * 16 - h.fromX) * t
    h.npc.py = h.fromY + (leg.y * 16 - h.fromY) * t
    if leg.hop then
      local lift = math.floor(HOP_HEIGHT * math.sin(t * math.pi) + 0.5)
      -- pokeyellow engine/pikachu/pikachu_movement.asm:153,648
      h.npc.hopShadowY = lift > 0 and h.npc.py or nil
      h.npc.py = h.npc.py - lift
    else
      h.npc.hopShadowY = nil
    end
  end
  if h.frames < HOP_FRAMES then return end
  if leg then
    h.npc.cellX, h.npc.cellY = leg.x, leg.y
    h.npc.px, h.npc.py = leg.x * 16, leg.y * 16
    h.npc.hopShadowY = nil
  end
  h.leg, h.frames = h.leg + 1, 0
  if h.legs[h.leg] then
    h.fromX, h.fromY = h.npc.px, h.npc.py
    return
  end
  ow.pikaHop = nil
  h.npc.hopShadowY = nil
  -- the player has not moved, so the trail restarts under his feet and the
  -- follower only steps back off the counter once he walks away
  ow.pikachuTrail = { x = ow.player.cellX, y = ow.player.cellY }
  if h.onDone then h.onDone() end
end

-- Disable/EnablePikachuOverworldSpriteDrawing around the healing machine
-- (engine/events/pokecenter.asm): Pikachu goes behind the counter with the
-- party and comes back standing on it, facing the player -- the respawn is
-- wPikachuSpawnState = 5, which is .above_player in pikachu_follow.asm,
-- followed by `lb bc, 15, 0` (sprite struct 15 is Pikachu, image index 0
-- is facing down).  ow.entities is the draw list and ow.npcs the update
-- list, so dropping it from entities alone hides it in place (#417).
function PikachuFollower.setVisible(ow, visible)
  local npc = findFollower(ow)
  if not npc then return end
  for i, e in ipairs(ow.entities or {}) do
    if e == npc then table.remove(ow.entities, i) break end
  end
  if visible then
    npc.facing = "down"
    table.insert(ow.entities, npc)
  end
end

-- npc the player is facing, when it is the follower (interact hook)
function PikachuFollower.at(ow, cx, cy)
  local npc = findFollower(ow)
  if npc and not npc.moving and npc.cellX == cx and npc.cellY == cy then
    return npc
  end
  return nil
end

return PikachuFollower
