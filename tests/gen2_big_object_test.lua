-- SPRITEMOVEDATA_BIGDOLLSYM: the 2x2 objects.
--
--   luajit tests/gen2_big_object_test.lua   (ROM-free; the map facts SKIP
--                                            without a gold cache)
--
-- The sleeping Snorlax on Route 11 outside Vermilion is movement 21, whose
-- SpriteMovementData row carries `STRENGTH_BOULDER | BIG_OBJECT`
-- (data/sprites/map_objects.asm).  BIG_OBJECT is the bit IsNPCAtCoord tests
-- before handing a coordinate to WillObjectIntersectBigObject
-- (engine/overworld/npc_movement.asm), which accepts anything inside
-- (x, y) .. (x+1, y+1) -- and IsNPCAtCoord is what BOTH `.CheckNPC` and
-- CheckFacingObject ask, so the blob blocks four cells and can be talked to
-- from any of them.
--
-- The port treated it as an ordinary one-cell NPC: the player could stand
-- inside the Snorlax on three of its four cells, and the sprite drew at a
-- quarter size.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 big object")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local World = require("src.world.gen2.World")
local NPC = require("src.world.gen2.Npc")
local Vm = require("src.script.gen2.Vm")
local Permissions = require("src.world.gen2.Permissions")

local COLL_FLOOR = 0x00
local SPRITEMOVEDATA_BIGDOLLSYM = 0x15
local SPRITEMOVEDATA_BIGDOLLASYM = 0x20
local SPRITEMOVEDATA_BIGDOLL = 0x21

local BIG_MOVEDATA = {
  [SPRITEMOVEDATA_BIGDOLLSYM] = true,
  [SPRITEMOVEDATA_BIGDOLLASYM] = true,
  [SPRITEMOVEDATA_BIGDOLL] = true,
}

-- trueColor short-circuits SpriteRenderer:resolveImage past the OBP bake, so a
-- draw here needs no canvases.
local BIG_SNORLAX_SHEET = {
  id = "SPRITE_BIG_SNORLAX", frames = 3, trueColor = true,
  image = "assets/generated/sprites/big_snorlax.png",
}
local BIG_ONIX_SHEET = {
  id = "SPRITE_BIG_ONIX", frames = 3, trueColor = true,
  image = "assets/generated/sprites/big_onix.png",
}

eq(NPC.MOVE.BIGDOLLSYM, SPRITEMOVEDATA_BIGDOLLSYM,
  "SPRITEMOVEDATA_BIGDOLLSYM is $15 in map_object_constants.asm")
eq(NPC.MOVE.BIGDOLLASYM, SPRITEMOVEDATA_BIGDOLLASYM, "_BIGDOLLASYM is $20")
eq(NPC.MOVE.BIGDOLL, SPRITEMOVEDATA_BIGDOLL, "and _BIGDOLL is $21")

-- ---- all three rows carry BIG_OBJECT --------------------------------------
--
-- data/sprites/map_objects.asm writes `STRENGTH_BOULDER | BIG_OBJECT` into the
-- palette-flags byte of BIGDOLLSYM, BIGDOLLASYM and BIGDOLL alike.
do
  local function build(movement, sheet)
    return NPC.new("TEST_MAP",
      { index = 1, movement = movement, x = 4, y = 4 }, sheet)
  end
  for _, movement in ipairs({ SPRITEMOVEDATA_BIGDOLLSYM,
      SPRITEMOVEDATA_BIGDOLLASYM, SPRITEMOVEDATA_BIGDOLL }) do
    check(build(movement, BIG_SNORLAX_SHEET).bigObject,
      string.format("movement $%02x is a BIG_OBJECT", movement))
  end
  check(not build(NPC.MOVE.STILL, BIG_SNORLAX_SHEET).bigObject,
    "SPRITEMOVEDATA_STILL is not")
  -- SPRITEMOVEDATA_STRENGTH_BOULDER ($19) carries STRENGTH_BOULDER on its own,
  -- which is the other half of the same palette-flags byte.
  check(not build(0x19, BIG_SNORLAX_SHEET).bigObject,
    "and neither is the plain strength boulder, which shares the other bit")

  -- SetFacingBigDoll (engine/overworld/map_object_action.asm).
  eq(NPC.bigFacing(SPRITEMOVEDATA_BIGDOLLSYM, "SPRITE_BIG_ONIX"), "sym",
    "$15 is always FacingBigDollSymmetric")
  eq(NPC.bigFacing(SPRITEMOVEDATA_BIGDOLLASYM, "SPRITE_BIG_SNORLAX"), "asym",
    "$20 is always FacingBigDollAsymmetric")
  eq(NPC.bigFacing(SPRITEMOVEDATA_BIGDOLL, "SPRITE_BIG_SNORLAX"), "sym",
    "$21 reads the doll: SNORLAX is symmetric")
  eq(NPC.bigFacing(SPRITEMOVEDATA_BIGDOLL, "SPRITE_BIG_LAPRAS"), "sym",
    "LAPRAS is symmetric")
  eq(NPC.bigFacing(SPRITEMOVEDATA_BIGDOLL, "SPRITE_BIG_ONIX"), "asym",
    "and ONIX is not")
  eq(NPC.bigFacing(NPC.MOVE.STILL, "SPRITE_BIG_ONIX"), nil,
    "everything else has no big-doll facing at all")
end

-- ---- FacingBigDollAsymmetric ----------------------------------------------
--
-- Fourteen 8x8 tiles over the same 32x32 square, two of them reused X-flipped,
-- and the lower left two cells left empty (data/sprites/facings.asm).
do
  local rows = NPC.BIG_DOLL_ASYM
  eq(#rows, 14, "the asymmetric doll is fourteen OAM entries")
  local seen, flips = {}, 0
  for _, row in ipairs(rows) do
    check(row[1] >= 0 and row[1] <= 24 and row[2] >= 0 and row[2] <= 24,
      "every entry lands inside the 32x32 square")
    if row[3] then flips = flips + 1 end
    seen[row[4]] = (seen[row[4]] or 0) + 1
  end
  eq(flips, 2, "with two of them X-flipped")
  for tile = 0x00, 0x0b do
    check(seen[tile] ~= nil, string.format("tile $%02x is placed", tile))
  end
  eq(seen[0x02], 2, "tile $02 is the one placed twice")
  eq(seen[0x04], 2, "and tile $04 the other")

  -- A tile index is four to a 16x16 sheet frame, row major, the way
  -- FacingStepDown0's $00..$03 read off the standing-down frame.
  local cases = {
    { 0x00, 0, 0 }, { 0x01, 8, 0 }, { 0x02, 0, 8 }, { 0x03, 8, 8 },
    { 0x04, 0, 16 }, { 0x07, 8, 24 }, { 0x08, 0, 32 }, { 0x0b, 8, 40 },
  }
  for _, row in ipairs(cases) do
    local sx, sy = NPC.bigDollTileRect(row[1])
    eq(sx, row[2], string.format("tile $%02x sits at sheet x %d", row[1], row[2]))
    eq(sy, row[3], string.format("and sheet y %d", row[3]))
  end
end

-- ---- and the draw picks the right table -----------------------------------
do
  local PaletteFX = require("src.render.PaletteFX")
  local savedColors = PaletteFX.mode
  PaletteFX.setMode("redpp")
  local G = love.graphics
  local realDraw = G.draw
  local blits
  G.draw = function(...) blits[#blits + 1] = { ... } end

  local function drawWith(movement, sheet)
    local npc = NPC.new("TEST_MAP",
      { index = 1, movement = movement, x = 0, y = 0 }, sheet)
    blits = {}
    npc:draw(0, 0, 1)
    return #blits
  end

  eq(drawWith(SPRITEMOVEDATA_BIGDOLLSYM, BIG_SNORLAX_SHEET), 4,
    "the symmetric doll is one half blitted twice, mirrored")
  eq(drawWith(SPRITEMOVEDATA_BIGDOLL, BIG_ONIX_SHEET), 14,
    "and the asymmetric one is its own fourteen tiles")
  eq(drawWith(SPRITEMOVEDATA_BIGDOLL, BIG_SNORLAX_SHEET), 4,
    "with the doll's own sprite deciding which, the way SetFacingBigDoll does")

  G.draw = realDraw
  PaletteFX.setMode(savedColors)
end

-- ---- WillObjectIntersectBigObject -----------------------------------------
do
  local doll = setmetatable({ cellX = 34, cellY = 8, bigObject = true }, NPC)
  check(doll:covers(34, 8), "its own cell")
  check(doll:covers(35, 8), "one to the right")
  check(doll:covers(34, 9), "one below")
  check(doll:covers(35, 9), "and the corner")
  check(not doll:covers(33, 8), "not the cell to its left")
  check(not doll:covers(36, 8), "not two to the right")
  check(not doll:covers(34, 7), "not the cell above")
  check(not doll:covers(34, 10), "and not two below")

  -- `sub [hl] / jr c, .nope`: the object's coordinates are the TOP LEFT, so
  -- the blob never reaches back up or left.
  local plain = setmetatable({ cellX = 34, cellY = 8 }, NPC)
  check(plain:covers(34, 8), "an ordinary object is its own cell")
  check(not plain:covers(35, 8), "and only that one")
end

-- ---- the world's two consumers --------------------------------------------
local MAP_W, MAP_H = 20, 20

local function fakeMap()
  local map
  map = {
    id = "VERMILION_CITY",
    width = MAP_W, height = MAP_H,
    def = { bgEvents = {}, objects = {}, width = MAP_W, height = MAP_H },
    cellCollision = function() return COLL_FLOOR end,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < MAP_W * 2 and y < MAP_H * 2
    end,
    isWalkable = function(_, x, y)
      return Permissions.isWalkable(map:cellCollision(x, y))
    end,
    warpAt = function() return nil end,
  }
  return map
end

local SNORLAX_SCRIPT = "4f:5291"

local function dollWorld(px, py, facing)
  local game = {
    data = {},
    save = { player = { name = "GOLD" }, party = {}, inventory = {} },
  }
  local world = World.new(game)
  game.world = world
  world.map = fakeMap()
  world.maps = { VERMILION_CITY = world.map.def }
  world.player = {
    cellX = px, cellY = py, px = px * 16, py = py * 16,
    facing = facing, moving = false, turnArmed = true, turnTimer = 0,
    update = function() return false end,
    setSprite = function() end,
    tryMove = function(self, dir, map, entities)
      -- The shipped Player:tryMove, narrowed to what this suite asks of it:
      -- bounds, the map's own answer, and the entity scan that only ever
      -- compares one cell per object.
      local d = { up = { 0, -1 }, down = { 0, 1 },
        left = { -1, 0 }, right = { 1, 0 } }
      local delta = d[dir]
      self.facing = dir
      local tx, ty = self.cellX + delta[1], self.cellY + delta[2]
      if not map:inBounds(tx, ty) then return "edge" end
      if not map:isWalkable(tx, ty) then return "blocked" end
      for _, e in ipairs(entities or {}) do
        if e ~= self and e.cellX == tx and e.cellY == ty then return "blocked" end
      end
      self.targetX, self.targetY = tx, ty
      self.moving = true
      return "moved"
    end,
  }
  world.pollTimeOfDay = function() end
  local started = {}
  world.vm = Vm.new({ [SNORLAX_SCRIPT] = { { op = "end" } } }, {},
    world.events, {})
  local realStart = world.vm.start
  world.vm.start = function(self, key)
    started[#started + 1] = key
    return realStart(self, key)
  end
  world.started = started
  local doll = setmetatable({
    def = { index = 4, movement = SPRITEMOVEDATA_BIGDOLLSYM,
      sprite = "SPRITE_BIG_SNORLAX", scriptKey = SNORLAX_SCRIPT,
      x = 34, y = 8 },
    id = "doll", cellX = 34, cellY = 8, homeX = 34, homeY = 8,
    px = 34 * 16, py = 8 * 16, facing = "down", moving = false,
    frozen = false, kind = "stand", radiusX = 0, radiusY = 0, timer = 1,
    bigObject = true,
  }, NPC)
  world.npcs = { doll }
  world.entities = { world.player, doll }
  return world, doll
end

-- World:npcAt is the port's IsNPCAtCoord.
do
  local world = dollWorld(33, 8, "right")
  for _, cell in ipairs({ { 34, 8 }, { 35, 8 }, { 34, 9 }, { 35, 9 } }) do
    check(world:npcAt(cell[1], cell[2]) ~= nil,
      string.format("npcAt finds the doll at (%d,%d)", cell[1], cell[2]))
  end
  check(world:npcAt(36, 8) == nil, "and not one cell past its right edge")
  check(world:npcAt(34, 10) == nil, "nor one below its bottom edge")
end

-- CheckFacingObject: an A press from any cell adjacent to any of the four
-- reaches the object's own script.  SnorlaxAwake's proximity list is what
-- decides whether it WAKES; being talkable at all is this.
do
  local cases = {
    { 33, 8, "right", "from its left" },
    { 36, 8, "left", "from its right" },
    { 36, 9, "left", "from the right of its lower half" },
    { 35, 10, "up", "from below its corner" },
    { 34, 7, "down", "from above" },
    { 33, 9, "right", "and from the left of its lower half" },
  }
  for _, row in ipairs(cases) do
    local world = dollWorld(row[1], row[2], row[3])
    check(world:interact(), "the A press is taken " .. row[4])
    eq(world.started[1], SNORLAX_SCRIPT, "and it runs the doll's own script")
    eq(world.vm.lastTalked, 5,
      "with hLastTalked set to the object const, whichever cell was faced")
  end
end

-- `.CheckNPC`: the three cells the doll overhangs are refused, not walked into.
do
  -- Only the first row is one the entity scan would have caught on its own;
  -- the other three are the cells the doll merely overhangs.
  local blocked = {
    { 34, 8, 33, 8, "right" },  -- its own cell, from the left
    { 35, 8, 35, 7, "down" },   -- the top right of the blob, from above
    { 34, 9, 33, 9, "right" },  -- the bottom left, from the left
    { 35, 9, 35, 10, "up" },    -- the bottom right, from below
  }
  for _, row in ipairs(blocked) do
    local world = dollWorld(row[3], row[4], row[5])
    eq(world:movePlayer(row[5]), "blocked",
      string.format("a step into (%d,%d) is refused", row[1], row[2]))
    check(not world.player.moving, "and no step is started")
  end
  -- The cells around it are still walkable, so the blob is a blob and not a
  -- wall across the beach.
  local world = dollWorld(33, 8, "left")
  eq(world:movePlayer("left"), "moved", "the cell to its left is still open")
end

-- ---- the map itself --------------------------------------------------------
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local chunk = loadfile(cache .. "/data/generated/maps.lua")
  if not chunk then
    check(true, "no gold cache: VERMILION_CITY object row (SKIP)")
  else
    local maps = chunk()
    local snorlax
    for _, obj in ipairs((maps.VERMILION_CITY or {}).objects or {}) do
      if obj.sprite == "SPRITE_BIG_SNORLAX" then snorlax = obj end
    end
    check(snorlax ~= nil, "VERMILION_CITY carries the big Snorlax object")
    eq(snorlax and snorlax.movement, SPRITEMOVEDATA_BIGDOLLSYM,
      "as SPRITEMOVEDATA_BIGDOLLSYM")
    eq(snorlax and snorlax.x, 34, "at x 34")
    eq(snorlax and snorlax.y, 8, "and y 8, so the blob is (34,8)..(35,9)")
    local doll = setmetatable({ cellX = snorlax and snorlax.x,
      cellY = snorlax and snorlax.y, bigObject = true }, NPC)
    -- The cave door at (34,7) is only walkable from the cell the object stands
    -- on, so widening the blob cannot open a way past the sleeping Snorlax.
    check(not doll:covers(34, 7),
      "the cave mouth above it is outside the blob, as the cart has it")

    -- Gold's BIG_OBJECT object_events, all of them: the Snorlax and
    -- PLAYERS_HOUSE_2F's big doll decoration.  Recognising only $15 left the
    -- second one an ordinary one-cell 16x16 NPC.
    local big = {}
    for id, map in pairs(maps) do
      for _, obj in ipairs(map.objects or {}) do
        if BIG_MOVEDATA[obj.movement] then
          big[#big + 1] = { map = id, obj = obj }
        end
      end
    end
    eq(#big, 2, "the cache carries exactly two BIG_OBJECT object_events")
    local byMap = {}
    for _, row in ipairs(big) do byMap[row.map] = row.obj end
    eq(byMap.VERMILION_CITY and byMap.VERMILION_CITY.movement,
      SPRITEMOVEDATA_BIGDOLLSYM, "VERMILION_CITY's is $15")
    local bigDoll = byMap.PLAYERS_HOUSE_2F
    check(bigDoll ~= nil, "PLAYERS_HOUSE_2F carries the other one")
    eq(bigDoll and bigDoll.movement, SPRITEMOVEDATA_BIGDOLL,
      "as SPRITEMOVEDATA_BIGDOLL")
    eq(bigDoll and bigDoll.x, 0, "at x 0")
    eq(bigDoll and bigDoll.y, 1, "and y 1, so the blob is (0,1)..(1,2)")
    -- Its sprite byte is a wVariableSprites SLOT, which is what
    -- src/core/gen2/Decorations.lua fills when a big doll is set up.
    eq(type(bigDoll and bigDoll.sprite), "number",
      "and its sprite is a wVariableSprites slot rather than a sheet")

    -- The real constructor, on the cache's own row: NPC.new is what decides
    -- bigObject, and the doll has to come out of it the same way the Snorlax
    -- does.
    local npc = NPC.new("PLAYERS_HOUSE_2F", bigDoll, BIG_SNORLAX_SHEET)
    check(npc.bigObject, "NPC.new gives the big doll a 2x2 footprint")
    for _, cell in ipairs({ { 0, 1 }, { 1, 1 }, { 0, 2 }, { 1, 2 } }) do
      check(npc:covers(cell[1], cell[2]),
        string.format("which covers (%d,%d)", cell[1], cell[2]))
    end
    check(not npc:covers(2, 1), "and stops at its right edge")
    check(not npc:covers(0, 0), "and never reaches back up")
  end
end

S.finish()
