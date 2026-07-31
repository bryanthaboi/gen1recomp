-- Overworld battles: where the fight is staged.
--
-- A battle in this mod happens ON THE MAP, so it needs a patch of ground
-- clear enough to stand two Pokemon on and point a camera down. This module
-- finds it: the nearest patch of open cells, in the shape below.
--
--     x x x
--     x O x        O   the enemy's mon
--     x x x
--     x x x
--     x P x        P   the player's mon
--     x x x
--
-- Every `x` is an OPEN cell -- one with no obstruction, i.e. one the player
-- could walk onto. The two mons stand three cells apart down the middle
-- column, with a one-cell apron all round so the camera looks across floor
-- rather than into a wall.
--
-- When no map has room for that -- a corridor, a cave, a shop floor -- the
-- search relaxes to the narrow shape, which is the same three-cell gap with
-- the apron given up:
--
--     O
--     x
--     x
--     P
--
-- and if even that will not fit, the caller gets nil and the battle draws
-- the way it always did. A mod that cannot find a stage does not invent
-- one.
--
-- Nothing here MOVES anybody: the arena is where the CAMERA goes and where
-- the two mons are staged for the shot. The player's own cell, the party,
-- every script and flag are exactly where the battle left them, which is
-- what keeps a trainer's post-battle dialogue talking to someone still
-- standing in front of them.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleArena = {}

-- ------- the authored spot
--
-- Every map gets ONE place its battles happen, chosen once and written down
-- in data/battle_arenas.lua, rather than whatever clearing happens to be
-- nearest to wherever the fight started. Two reasons.
--
-- A fight should look the same every time it happens somewhere. Picking the
-- nearest patch means Route 1 has a dozen different battle scenes depending
-- on which step of the grass you were on, some of them behind a tree.
--
-- And "open ground" is not the same question as "you can SEE the two of
-- them". The camera is low and a long way back, so a hedge, a ledge lip or a
-- building corner anywhere along that line hides a mon completely while the
-- cells it stands on are perfectly walkable. That is what `clearance` below
-- measures, and it is what the authored list is chosen against.
--
-- A map with no entry falls back to the search, so a mod that adds maps, or
-- an entry that goes stale, degrades to the old behaviour rather than to no
-- battle.
-- An entry may also name ANOTHER MAP to stage on:
--
--   ["MT_MOON_B2F"] = { map = "MT_MOON_1F", x = 12, y = 8, shape = "wide" }
--
-- because some maps simply have nowhere to put a fight. A cave's lower floor
-- can be nothing but two-cell-wide corridors between rock walls; a gym is a
-- room full of furniture. Rather than stage a battle there badly -- both
-- Pokemon behind a boulder -- the fight is shot on a floor of the SAME cave,
-- or a floor of the same building, that does have the room for it. It is the
-- same place, and no worse a fiction than a battle happening on ground the
-- player is not standing on, which is what every one of these already is.
local authored = nil
local overrides = {}

local function authoredFor(mapId)
  -- `~= nil`, not truthiness: `false` is a meaningful entry here (an
  -- authored refusal), so it has to reach the caller rather than read as
  -- "nothing set" and fall through to the data file
  local forced = overrides[mapId]
  if forced ~= nil then return forced end
  if authored == nil then
    local ok, list = pcall(V.data, "battle_arenas")
    authored = (ok and type(list) == "table") and list or false
  end
  if not authored then return nil end
  return authored[mapId]
end

BattleArena.authoredFor = authoredFor

-- Force one map's entry at runtime, ahead of the data file. The authoring
-- tool's handle: it is how a spot chosen by eye is staged and photographed
-- before it is written down, and the only way to check a cross-floor entry
-- without editing the shipped list first. Pass nil to drop it again.
function BattleArena.setOverride(mapId, entry)
  overrides[mapId] = entry
end

-- Cell size in world pixels, the unit every coordinate here is in when it
-- crosses into the renderer (Map's walk grid is 16px cells).
local CELL = 16

-- The two shapes, in preference order. `w`/`h` are in cells; `enemy` and
-- `player` are the offsets, from the shape's north-west corner, of the two
-- cells a mon stands on.
BattleArena.SHAPES = {
  { id = "wide",   w = 3, h = 6, enemy = { 1, 1 }, player = { 1, 4 } },
  { id = "narrow", w = 1, h = 4, enemy = { 0, 0 }, player = { 0, 3 } },
}

-- Whether a cell is open ground for the purpose above.
--
-- "Open" is the walk test the player themselves answer to, so an arena can
-- never be laid over a wall, a counter, a tree or a ledge face. Water counts
-- only for a surfer, which is the one case where the player is standing on
-- it too -- a sea battle staged on the beach half a route away would read as
-- a teleport.
--
-- Warp cells are excluded on top of that. They are walkable by definition
-- (they are the doormat), and a fight framed in a doorway both looks wrong
-- and puts the camera inside the building's geometry.
--
-- And TALL GRASS is excluded, which is the surprising one, because grass is
-- where wild battles come from and standing in it is the obvious place to
-- have one. It does not survive contact with the camera. Grass is real
-- geometry in this mode -- a row of tufts about knee height on a Pokemon --
-- drawn with the same camera-ward bias that lets it overdraw a walking
-- character's feet in the free-roam world. From a camera nearly level with
-- the floor that bias stops being feet-deep: the tufts on and around a mon's
-- own tile stand between it and the lens and eat most of the sprite.
--
-- So the arena is laid on bare ground -- the whole footprint, not just the
-- two cells a mon stands on, because the apron south of the near mon is
-- exactly the row whose grass would cover it. Grass FURTHER back toward the
-- camera is fine and stays: it is far enough forward to project low and wide
-- across the bottom of the frame, where it reads as a field rather than as
-- something in the way.
local function openCell(map, cx, cy, surfing)
  if not map:inBounds(cx, cy) then return false end
  if map:warpAtCell(cx, cy) then return false end
  if map:isWarpTileCell(cx, cy) then return false end
  if map.isGrassCell and map:isGrassCell(cx, cy) then return false end
  if map:isWalkableCell(cx, cy) then return true end
  return (surfing and map:isWaterCell(cx, cy)) or false
end

BattleArena.openCell = openCell

-- The map's open cells as one flat boolean grid, so the rectangle test
-- below is a lookup rather than a tileset walk per cell. Built once per
-- search; a battle asks for one.
local function openGrid(map, surfing)
  local w, h = map.widthCells, map.heightCells
  local grid = {}
  for cy = 0, h - 1 do
    local row = cy * w
    for cx = 0, w - 1 do
      grid[row + cx] = openCell(map, cx, cy, surfing)
    end
  end
  return grid, w, h
end

local function fits(grid, gw, x, y, w, h)
  for cy = y, y + h - 1 do
    local row = cy * gw
    for cx = x, x + w - 1 do
      if not grid[row + cx] then return false end
    end
  end
  return true
end

-- Build the record the renderer reads: the two mons' cells and, in world
-- pixels, the centre of each and of the pair.
local function place(shape, x, y)
  local ex, ey = x + shape.enemy[1], y + shape.enemy[2]
  local px, py = x + shape.player[1], y + shape.player[2]
  local arena = {
    shape = shape.id,
    x = x, y = y, w = shape.w, h = shape.h,
    enemyCell = { ex, ey },
    playerCell = { px, py },
    -- world-pixel centres of the two cells a mon stands on
    enemy = { ex * CELL + CELL / 2, ey * CELL + CELL / 2 },
    player = { px * CELL + CELL / 2, py * CELL + CELL / 2 },
  }
  arena.mid = { (arena.enemy[1] + arena.player[1]) / 2,
                (arena.enemy[2] + arena.player[2]) / 2 }
  return arena
end

-- ------- can the two of them actually be SEEN there
--
-- The camera sits low and far back on one side, so what hides a mon is not
-- what is on its own tile -- it is anything TALL between the camera and it.
-- A tree two cells to the south-east blocks the near mon completely while
-- every cell of the arena is open ground.
--
-- So the line from the eye to each mon is walked in short steps and the
-- terrain height under each step is compared with how high the line is
-- there. Three lines per mon -- to its feet, its middle and its head --
-- because a hedge that clears the head still cuts the body in half.
--
-- Grass and flowers are deliberately not obstacles: they stand at ankle
-- height, they are what a field looks like, and a mon standing in them
-- reads as standing in a field rather than as being hidden by one.
BattleArena.SAMPLE_STEP = 4      -- world pixels along the line
BattleArena.MON_H = 16           -- how tall a mon stands, in world pixels
BattleArena.CLEAR_EPS = 1.5      -- slack, so a flush kerb is not an obstacle

local function heightAt(map, wx, wz)
  local cx, cy = math.floor(wx / CELL), math.floor(wz / CELL)
  if not map:inBounds(cx, cy) then
    -- off the map the border ring is drawn, and on most outdoor maps that
    -- ring is trees; treat it as solid so an arena is never framed through it
    return 32
  end
  local ok, h = pcall(V.require("VoxelScene").groundAt, map, cx, cy)
  return (ok and h) or 0
end

-- Whether the segment from `eye` to (tx, ty, tz) clears the terrain.
local function lineClear(map, eye, tx, ty, tz)
  local dx, dy, dz = tx - eye[1], ty - eye[2], tz - eye[3]
  local len = math.sqrt(dx * dx + dy * dy + dz * dz)
  if len <= 1 then return true end
  local steps = math.ceil(len / BattleArena.SAMPLE_STEP)
  -- skip the ends: the eye is in open air by construction and the last step
  -- is the mon's own tile, which it is standing on
  for i = 1, steps - 1 do
    local t = i / steps
    local wx = eye[1] + dx * t
    local wy = eye[2] + dy * t
    local wz = eye[3] + dz * t
    if heightAt(map, wx, wz) > wy + BattleArena.CLEAR_EPS then return false end
  end
  return true
end

-- Whether both mons would be in plain view from the battle camera.
function BattleArena.clearance(map, arena)
  local BattleCam = V.require("BattleCam")
  local ok, rig = pcall(BattleCam.rig, arena, 0)
  if not (ok and rig and rig.eye) then return true end
  local eye = rig.eye
  local H = BattleArena.MON_H
  for _, mark in ipairs({ arena.player, arena.enemy }) do
    for _, hy in ipairs({ 1, H * 0.5, H }) do
      if not lineClear(map, eye, mark[1], hy, mark[2]) then return false end
    end
  end
  return true
end

-- The nearest arena to (fromX, fromY) -- the player's cell -- or nil when
-- the map has room for neither shape.
--
-- Distance is measured from the player to the arena's MIDPOINT, so "nearest"
-- means the fight is staged as close to where it was triggered as the ground
-- allows, rather than merely having a corner nearby.
--
-- Both shapes are searched over the whole map before the next one is tried:
-- a wide arena on the far side of a route still beats a narrow one
-- underfoot, because the wide one is the shot this mode is framed for.
function BattleArena.find(map, fromX, fromY, surfing)
  if not (map and map.widthCells) then return nil end

  -- the authored spot wins outright when the map has one and it still holds
  local pick = authoredFor(map.id)
  -- `false` is an authored REFUSAL: a map looked at and found to have nowhere
  -- a fight can be seen, with no other floor to borrow. Declining is the
  -- honest answer -- the battle draws on the plain screen -- and it has to be
  -- said explicitly, because the fallback search below would otherwise go and
  -- find one of the bad spots that were already rejected by eye.
  if pick == false then return nil end
  if pick then
    local shape = nil
    for _, s in ipairs(BattleArena.SHAPES) do
      if s.id == (pick.shape or "wide") then shape = s end
    end
    -- an entry may point at another floor of the same cave or building; the
    -- arena is then measured against THAT map, and carries it
    local host = map
    if shape and pick.map and pick.map ~= map.id then
      local ok, other = pcall(function()
        local Game = require("src.core.Game")
        return require("src.world.MapLoader").load(Game.data, pick.map)
      end)
      host = (ok and other) or nil
    end
    if shape and host then
      -- An authored spot is checked with WATER COUNTING AS GROUND, whatever
      -- the player is doing. The surfing test exists to stop the automatic
      -- search staging a walker's fight out at sea; an authored entry was
      -- chosen and looked at by a person, so if it is on water that is the
      -- point of it -- the surf routes fight in the middle of their own
      -- ocean rather than on a scrap of beach at the edge of the map. Land
      -- entries are unaffected: land passes the test either way.
      local grid, gw = openGrid(host, true)
      if fits(grid, gw, pick.x, pick.y, shape.w, shape.h) then
        local arena = place(shape, pick.x, pick.y)
        arena.map = host
        -- which camera rig this spot is framed for; nil is the default long
        -- lens, "close" the short one small rooms need (see BattleCam)
        arena.cam = pick.cam
        return arena
      end
    end
  end

  local found = BattleArena.search(map, fromX, fromY, surfing)
  if found then found.map = map end
  return found
end

-- The arena at a given north-west corner, whatever the map says about it.
-- The authoring tool's manual override: a spot chosen by eye rather than by
-- the search, so it can be photographed and judged before it is written down.
function BattleArena.at(x, y, shapeId)
  for _, shape in ipairs(BattleArena.SHAPES) do
    if shape.id == (shapeId or "wide") then return place(shape, x, y) end
  end
  return nil
end

-- The nearest arena the map can offer, preferring one the pair can be SEEN
-- in. Two passes rather than one score: a clear arena on the far side of a
-- route beats an obstructed one underfoot, because being able to see the
-- fight is the point, but an obstructed one still beats no battle at all.
function BattleArena.search(map, fromX, fromY, surfing, wantClear)
  local grid, gw, gh = openGrid(map, surfing)
  for _, shape in ipairs(BattleArena.SHAPES) do
    for _, needClear in ipairs({ true, false }) do
      local best, bestD = nil, nil
      for y = 0, gh - shape.h do
        for x = 0, gw - shape.w do
          if fits(grid, gw, x, y, shape.w, shape.h) then
            local mx = x + (shape.w - 1) / 2
            local my = y + (shape.h - 1) / 2
            local dx, dy = mx - fromX, my - fromY
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then
              local cand = place(shape, x, y)
              if not needClear or BattleArena.clearance(map, cand) then
                best, bestD = cand, d
              end
            end
          end
        end
      end
      if best then return best end
      if wantClear and needClear then return nil end
    end
  end
  return nil
end

return BattleArena
