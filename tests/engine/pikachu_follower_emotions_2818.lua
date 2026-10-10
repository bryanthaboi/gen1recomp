-- pokeyellow engine/pikachu/pikachu_follow.asm:436
-- pokeyellow engine/pikachu/pikachu_follow.asm:544
-- pokeyellow engine/pikachu/pikachu_follow.asm:1389
-- pokeyellow data/pikachu/pikachu_emotions.asm:54
-- pokeyellow engine/pikachu/pikachu_pic_animation.asm:782

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check = T.check

local GameVersion = require("src.core.GameVersion")
local Sound = require("src.core.Sound")
local field = require("tests.yellow_field_cache")()
local PikachuFollower = require("src.world.PikachuFollower")
GameVersion.set("yellow")

local cries = {}
local realPlay, realWait = Sound.playPikaCry, Sound.waitFrames
Sound.playPikaCry = function(_, n)
  cries[#cries + 1] = n
  return { fake = n }
end
Sound.waitFrames = function() return 20 end

local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

local function newWorld(happy, mood)
  local npc = {
    pikachuFollower = true, cellX = 6, cellY = 5, px = 96, py = 80,
    facing = "left", passable = true,
    update = function() end,
  }
  local ow = {
    map = { id = "PALLET_TOWN" },
    npcs = { npc }, entities = { npc },
    player = { cellX = 5, cellY = 5, facing = "right", moving = false },
  }
  local game = {
    save = {
      flags = {}, party = { { species = "PIKACHU", hp = 20 } },
      pikachuHappiness = happy, pikachuMood = mood,
    },
    data = { field = field },
  }
  return game, ow, npc
end

local function drive(ow, onFrame)
  local frames = 0
  while ow.emote and frames < 5000 do
    frames = frames + 1
    local e = ow.emote
    e.frames = e.frames - 1
    if onFrame then onFrame(frames, e) end
    if e.frames <= 0 then
      ow.emote = nil
      if e.onDone then e.onDone() end
    end
  end
  return frames
end

if not field then
  print("[skip] talk checks: no Yellow cache with field.pikachu")
else
do
  local game, ow, npc = newWorld(140, 180)
  npc.facing = "down"
  PikachuFollower.talk(game, ow, npc)
  check(npc.facing == "left", "talking turns the follower to face the player",
    npc.facing)
  ow.player.facing = "up"
  npc.facing = "left"
  ow.pikachuBillsScene = true
  PikachuFollower.talk(game, ow, npc)
  check(npc.facing == "left", "a disabled follower keeps its facing", npc.facing)
  ow.emote = nil
end

do
  local game, ow, npc = newWorld(40, 128)
  check(PikachuFollower.moodEmotion(game.save, field.pikachu) == 6, "happiness 40 mood 128 is emotion 6")
  npc.facing = "up"
  PikachuFollower.talk(game, ow, npc)
  local faced = npc.facing
  check(faced == OPPOSITE[ow.player.facing], "emotion 6 starts facing the player")
  local turnedAt, turnedTo, restored, sawSkull
  drive(ow, function(f, e)
    if not turnedAt and npc.facing ~= faced then
      turnedAt, turnedTo = f, npc.facing
    end
    if e.bubble == 4 then sawSkull = true end
    if e.pikaPic and npc.facing == faced then restored = true end
  end)
  check(turnedTo == "up", "PikachuMovementData_fd21e turns one step clockwise",
    tostring(turnedTo))
  check(turnedAt and turnedAt <= 4, "the turn lands on the first movement pass",
    tostring(turnedAt))
  check(sawSkull, "the skull bubble follows the turn")
  check(restored, "the pic box restores the facing")
end

do
  local game, ow, npc = newWorld(90, 100)
  check(PikachuFollower.moodEmotion(game.save, field.pikachu) == 9, "happiness 90 mood 100 is emotion 9")
  cries = {}
  PikachuFollower.talk(game, ow, npc)
  local faced = npc.facing
  local seen = {}
  drive(ow, function() seen[npc.facing] = true end)
  check(seen[OPPOSITE[faced]], "PikachuMovementData_fd218 turns it away from the player")
  check(cries[1] == 6, "emotion 9 cries PikachuCry6 before it turns", tostring(cries[1]))
end

do
  local game, ow, npc = newWorld(90, 140)
  check(PikachuFollower.moodEmotion(game.save, field.pikachu) == 12, "happiness 90 mood 140 is emotion 12")
  cries = {}
  local first = PikachuFollower.talk(game, ow, npc)
  check(cries[1] == 25, "PikaPicAnimScript12 plays PikachuCry25", tostring(cries[1]))
  check(first and first.pikaPic and not first.skippable,
    "the cry holds the pic box up and cannot be skipped")
  drive(ow)
end

do
  local lifts = {}
  for i = 1, 8 do lifts[i] = PikachuFollower.hopLift(field.pikachu, i * 4, 0x2f) end
  check(table.concat(lifts, ",") == "6,11,14,16,14,11,6,0",
    "the fd224 hop arcs 16px up and lands", table.concat(lifts, ","))
  local game, ow, npc = newWorld(180, 128)
  check(PikachuFollower.moodEmotion(game.save, field.pikachu) == 7, "happiness 180 mood 128 is emotion 7")
  PikachuFollower.talk(game, ow, npc)
  local peak = 0
  drive(ow, function()
    local lift = npc.cellY * 16 - npc.py
    if lift > peak then peak = lift end
  end)
  check(peak == 16, "emotion 7 hops the follower", tostring(peak))
  check(npc.py == npc.cellY * 16 and npc.hopShadowY == nil, "and sets it back down")
end
end

do
  local game, ow, npc = newWorld(140, 128)
  local prev = PikachuFollower.setShouldSpawn(function() return true end)
  ow.pikachuTrail = { x = ow.player.cellX, y = ow.player.cellY }
  npc.idle = nil
  local glanceAt, last
  for f = 1, 700 do
    PikachuFollower.update(game, ow)
    local idle = npc.idle
    if f == 2 then
      check(idle and idle.kind == "wait" and idle.frames == 0xff,
        "the first wait after a step starts at $100", idle and idle.frames)
    end
    local now = idle and idle.frames
    if not glanceAt and now and last and now > last then glanceAt = f end
    last = now or last
  end
  check(glanceAt == 512, "the first glance lands after 512 frames", tostring(glanceAt))

  ow.player.cellX, ow.player.cellY = 6, 3
  npc.goalX, npc.goalY = npc.cellX, npc.cellY
  npc.facing = "down"
  ow.pikachuTrail = { x = ow.player.cellX, y = ow.player.cellY }
  PikachuFollower.update(game, ow)
  check(npc.facing == "up", "a landed step with nothing queued faces the player",
    npc.facing)
  PikachuFollower.setShouldSpawn(prev)
end

Sound.playPikaCry, Sound.waitFrames = realPlay, realWait
GameVersion.set("red")
T.finish("pikachu_follower_emotions_2818")
