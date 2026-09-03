-- Talking to overworld objects: the Route 30 roadblock's Rattata turn to face
-- the player (ObjectEvent is `jumptextfaceplayer`, home/map.asm, and
-- SPRITE_MONSTER is a WALKING_SPRITE so ApplyObjectFacing really turns it),
-- and the talked-to / engaged object holds still for the conversation the way
-- FreezeAllOtherObjects + EndScript's UnfreezeAllObjects bracket it on the
-- cart -- a SPINRANDOM trainer must not roll a new facing under his own
-- sighting text.
--
--   luajit tests/gen2_npc_interact_test.lua   (ROM-free)
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 npc interact")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local World = require("src.world.gen2.World")
local NPC = require("src.world.gen2.Npc")
local Vm = require("src.script.gen2.Vm")
local Permissions = require("src.world.gen2.Permissions")

local COLL_FLOOR = 0x00

-- The gen2_world_test rig, trimmed: a flat map, a fake player, and NPCs built
-- as NPC-shaped tables (a real NPC.new needs a sprite sheet and a graphics
-- device) so facePlayer / update / scriptFace are the shipped methods.
local MAP_W, MAP_H = 10, 10

local function fakeMap()
  local map
  map = {
    id = "TEST_MAP",
    width = MAP_W, height = MAP_H,
    def = { bgEvents = {}, objects = {}, width = MAP_W, height = MAP_H },
    cellCollision = function() return COLL_FLOOR end,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < MAP_W * 2 and y < MAP_H * 2
    end,
    isWalkable = function() return true end,
    warpAt = function() return nil end,
  }
  return map
end

local function fakePlayer(x, y, facing)
  return {
    cellX = x, cellY = y, px = x * 16, py = y * 16,
    facing = facing, moving = false, turnArmed = true,
    update = function() return false end,
    setSprite = function() end,
  }
end

local function npcAt(def, x, y, facing, kind)
  return setmetatable({
    def = def, id = "npc_" .. tostring(def.index),
    cellX = x, cellY = y, homeX = x, homeY = y,
    px = x * 16, py = y * 16,
    facing = facing, moving = false, progress = 0, stepFlip = false,
    frozen = false, kind = kind or "stand",
    roamDirs = { "up", "down", "left", "right" },
    radiusX = 0, radiusY = 0, spinLo = 1, spinHi = 1, timer = 1,
  }, NPC)
end

local function talkWorld(opts)
  opts = opts or {}
  local game = {
    data = {},
    save = { player = { name = "GOLD" }, party = opts.party or {},
      inventory = {} },
  }
  local world = World.new(game)
  game.world = world
  world.map = fakeMap()
  world.maps = { TEST_MAP = world.map.def }
  world.player = fakePlayer(opts.px or 4, opts.py or 5, opts.facing or "right")
  world.pollTimeOfDay = function() end
  local log = {}
  world.log = log
  world.showText = function(self, body, onDone)
    log[#log + 1] = body
    self.textbox = true
    self.pendingText = function()
      self.textbox = nil
      if onDone then onDone() end
    end
  end
  world.vm = Vm.new(opts.scripts or {}, opts.texts or {}, world.events, {
    showText = function(body, onDone) world:showText(body, onDone) end,
    -- The shipped hook body from World:load, restated over this rig: the
    -- talked-to NPC turns through the real NPC:facePlayer.
    facePlayer = function()
      if world.talkNpc and world.player then
        world.talkNpc:facePlayer(world.player)
      end
    end,
    showEmote = function() end,
    encounterMusic = function() end,
    trainerApproach = function(onDone) world:trainerApproach(onDone) end,
    lookupTrainer = function()
      return { name = "DON", class = 36, member = 1 }
    end,
    startBattle = function(_, _, onDone) onDone("win") end,
    reloadMap = function() end,
  })
  return world
end

local function advanceText(world)
  local fn = world.pendingText
  world.pendingText = nil
  if fn then fn() end
end

-- ---- the roadblock monsters turn to the player -----------------------------
-- maps/Route30.asm: both SPRITE_MONSTER rows point at ObjectEvent, one
-- STANDING_DOWN and one STANDING_UP -- they face each other until spoken to.
do
  local OBJECT_EVENT = "00:2812"
  local monster = { index = 7, sprite = "SPRITE_MONSTER", movement = 7,
    scriptKey = OBJECT_EVENT }
  local world = talkWorld({
    scripts = { [OBJECT_EVENT] = {
      { op = "jumptextfaceplayer", text = "00:2815" },
    } },
    texts = { ["00:2815"] = "Object event." },
  })
  eq(NPC.new and select(1, "x"), "x", "NPC module loaded")
  local rattata = npcAt(monster, 5, 5, "up")
  world.npcs = { rattata }
  world.entities = { world.player, rattata }
  check(world:interact(), "A from the west starts the ObjectEvent script")
  eq(rattata.facing, "left", "the spoken-to Rattata turns to face the player")
  eq(world.log[1], "Object event.", "and its line prints")
  check(rattata.frozen, "it holds still while its text is up")
  advanceText(world)
  for _ = 1, 3 do world:step() end
  check(not rattata.frozen, "and is released when the interaction ends")
end

-- ---- a spinning trainer cannot spin under his own sighting text ------------
local BEAT_FLAG = 1000
local record = { event = BEAT_FLAG, class = 36, member = 1,
  seenText = "t:seen", winText = "t:win", scriptKey = "s:after" }

local function trainerWorld(px, py, facing, npcFacing)
  local world = talkWorld({
    px = px, py = py, facing = facing,
    party = { { species = "RATTATA", hp = 10 } },
    scripts = { ["s:after"] = { { op = "end" } } },
    texts = {
      ["t:seen"] = "Instead of a bug\nPOKéMON, I found\va trainer!",
      ["t:win"] = "Deary me.",
    },
  })
  local don = { index = 4, sprite = "SPRITE_BUG_CATCHER", movement = 10,
    trainer = record, sight = 3 }
  local npc = npcAt(don, 4, 7, npcFacing, "spin")
  world.npcs = { npc }
  world.entities = { world.player, npc }
  return world, npc
end

do
  -- Player one cell below the trainer, trainer facing down: engagement.
  local world, npc = trainerWorld(4, 8, "up", "down")
  check(world:checkTrainerBattle(), "inside the cone the trainer engages")
  check(npc.frozen, "and freezes for the whole engagement")
  local before = npc.facing
  npc.timer = 1
  for _ = 1, 30 do world:updatePeople() end
  eq(npc.facing, before, "his spin cannot roll a new facing mid-script")
  -- Drain the engagement: the emote's 30-frame hold, the seen text, the
  -- battle, the reload's FadeInFromWhite, the after script.  updatePeople
  -- keeps running under it, which is exactly when an unfrozen spinner would
  -- drift.
  local drifted = false
  for _ = 1, 90 do
    world:step()
    world:updatePeople()
    if world.vm:running() and npc.facing ~= before then drifted = true end
    advanceText(world)
  end
  eq(world.log[1], "Instead of a bug\nPOKéMON, I found\va trainer!",
    "the sighting text is the struct's seen text, verbatim")
  check(not drifted, "and the spin never rolled while the script ran")
  check(not world.vm:running(), "the engagement script finished")
  check(world.events:get(BEAT_FLAG), "and the trainer is marked beaten")
  for _ = 1, 3 do world:step() end
  check(not npc.frozen, "the freeze lifts once everything settles")
end

do
  -- Player BEHIND the trainer (he faces down, player stands above): nothing.
  local world = trainerWorld(4, 6, "down", "down")
  check(not world:checkTrainerBattle(),
    "standing behind his facing never engages")
  eq(#world.log, 0, "and no sighting text prints")
end

do
  -- Off his column entirely: nothing, whatever the range.
  local world = trainerWorld(6, 8, "up", "down")
  check(not world:checkTrainerBattle(), "off the sight line never engages")
end

do
  -- Facing him but beyond sight 3: nothing.
  local world, npc = trainerWorld(4, 11, "up", "down")
  npc.cellY = 7
  check(not world:checkTrainerBattle(), "past the sight range never engages")
end

do
  -- CheckTrainerEvent is PlayerEvents' FIRST test (engine/overworld/events.asm:
  -- 245) and, unlike every arm of CheckTileEvent, it is NOT behind
  -- wEnabledPlayerEvents -- MapEvents clears that byte every pass
  -- (events.asm:168) and CheckPlayerState only re-sets it on a step that
  -- landed (events.asm:210-221).  So the sight cone is polled on every
  -- overworld frame, not only on the frame a step lands: a spinner that
  -- rotates onto a STANDING player engages there and then.  Nothing is called
  -- directly here -- that is the point, the call SITE is what was wrong.
  local world, npc = trainerWorld(4, 8, "up", "up")
  world.updatePeople = function() end
  world:step()
  check(not world.vm:running(),
    "a trainer facing away leaves the standing player alone")
  npc.facing = "down"
  for _ = 1, 3 do world:step() end
  check(world.vm:running(),
    "and the frame he turns onto the player's line, he engages -- no step needed")
  check(npc.frozen, "the engagement freezes him the same way")
end

S.finish()
