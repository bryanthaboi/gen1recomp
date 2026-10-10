-- pokeyellow data/pikachu/pikachu_emotions.asm:54
-- pokeyellow data/pikachu/pikachu_pic_animation.asm:77
-- pokeyellow data/pikachu/pikachu_pic_objects.asm:130
-- pokeyellow data/pikachu/pikachu_pic_tilemaps.asm:143

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check = T.check

local field, root = require("tests.yellow_field_cache")()
if not field then
  print("[skip] pikachu_pic_tables_2822: no Yellow cache with field.pikachu")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
local Sound = require("src.core.Sound")
local CacheContract = require("src.import.CacheContract")
local PikachuFollower = require("src.world.PikachuFollower")
GameVersion.set("yellow")

local P = field.pikachu

local function ops(list)
  local out = {}
  for i, c in ipairs(list) do
    local extra = c.cry or c.bubble or c.script or c.sub or ""
    out[i] = c.op .. (extra ~= "" and (":" .. tostring(extra)) or "")
  end
  return table.concat(out, ",")
end

local function cmds(movement)
  local out = {}
  for i, c in ipairs(movement) do out[i] = ("%02x/%d"):format(c.cmd, c.param1) end
  return table.concat(out, ",")
end

local function frames(pic)
  local out = {}
  for i, f in ipairs(pic.frames) do out[i] = f.tilemap .. "x" .. f.dur end
  return table.concat(out, ",")
end

check(P.emotions[32] and not P.emotions[33], "PikachuEmotionTable carries emotions 0-32")
check(ops(P.emotions[6]) == "subcmd:0,pcm,move,bubble:SKULL_BUBBLE,pikapic:6",
  "PikachuEmotion6 keeps every command", ops(P.emotions[6]))
check(ops(P.emotions[9]) == "subcmd:0,pcm:6,move,bubble:SKULL_BUBBLE,pikapic:9",
  "PikachuEmotion9 cries PikachuCry6", ops(P.emotions[9]))
check(ops(P.emotions[5]) == "pcm:31,pikapic:5", "PikachuEmotion5", ops(P.emotions[5]))
check(ops(P.emotions[29]) == "pcm:5,pikapic:10", "PikachuEmotion29 shows script 10",
  ops(P.emotions[29]))
check(ops(P.emotions[30]):sub(1, 8) == "turnaway", "PikachuEmotion30 turns away first")
check(cmds(P.emotions[6][3].movement) == "00/0,39/0,3e/30",
  "PikachuMovementData_fd21e", cmds(P.emotions[6][3].movement))
check(cmds(P.emotions[9][3].movement) == "00/0,39/1,3e/30",
  "PikachuMovementData_fd218", cmds(P.emotions[9][3].movement))

check(frames(P.pics[5]) == "0x2,18x2,0x2,18x64,0x3,18x64",
  "PikaPicAnimBGFrames_10 paints PikaAnimTilemap_18", frames(P.pics[5]))
check(frames(P.pics[6]) == "0x8,19x64,0x4,19x64",
  "PikaPicAnimBGFrames_11 paints PikaAnimTilemap_19", frames(P.pics[6]))
check(frames(P.pics[9]) == "0x2,22x2,0x2,22x2,0x20,22x2",
  "PikaPicAnimBGFrames_14 paints PikaAnimTilemap_22", frames(P.pics[9]))
check(P.pics[5].dur == 32 and P.pics[6].dur == 50 and P.pics[9].dur == 56,
  "pikapic_setduration 32 / 50 / 56")
check(P.pics[6].cry == 38 and P.pics[12].cry == 25 and P.pics[5].cry == nil,
  "pikapic_cry ids")
check(P.pics[25].boltDelay == 13 and P.pics[25].passes == 2,
  "PikaPicAnimScript25 waits writebyte 13 after two passes")
check(#P.moodRows == 7 and P.moodRows[2][3] == 5 and P.moodRows[2][1] == 9,
  "PikaPicAnimationScriptPointerLookupTable")
check(table.concat(P.modifierEmotions, ",") == "18,21,23,24,25",
  "MapSpecificPikachuExpression.Emotions")
check(#P.thunderboltPals == 20 and P.thunderboltPals[1].bgp == 0xc0,
  "PikaPicAnimThunderboltPals")
check(#P.sine == 32 and P.sine[17] == 0x100, "SineWave_3f")

local required = {}
for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES.yellow) do required[path] = true end
local missing = {}
for id, pic in pairs(P.pics) do
  local paths = { pic.image }
  for _, f in ipairs(pic.frames) do
    check((f.tilemap == 0) == (f.image == nil), "script " .. id .. " frame image matches its tilemap")
    if f.image then paths[#paths + 1] = f.image end
  end
  for _, path in ipairs(paths) do
    local handle = io.open(root .. path, "rb")
    if handle then handle:close() end
    if not handle or not required[path] then missing[#missing + 1] = path end
  end
end
check(#missing == 0, "every pikapic frame is a required cache file", table.concat(missing, " "))

local realPlay, realWait = Sound.playPikaCry, Sound.waitFrames
Sound.playPikaCry = function(_, n) return { fake = n } end
Sound.waitFrames = function() return 20 end

local function talk(happy, mood)
  local npc = {
    pikachuFollower = true, cellX = 6, cellY = 5, px = 96, py = 80,
    facing = "left", passable = true, update = function() end,
  }
  local ow = {
    map = { id = "PALLET_TOWN" }, npcs = { npc }, entities = { npc },
    player = { cellX = 5, cellY = 5, facing = "right", moving = false },
  }
  local game = {
    save = { flags = {}, party = { { species = "PIKACHU", hp = 20 } },
             pikachuHappiness = happy, pikachuMood = mood },
    data = { field = field },
  }
  PikachuFollower.talk(game, ow, npc)
  local guard = 0
  while ow.emote and not ow.emote.pikaSeq and guard < 100 do
    guard = guard + 1
    local done = ow.emote.onDone
    ow.emote = nil
    if done then done() end
  end
  return ow.emote
end

local function at(e, tick)
  e.frames = e.pikaTotal - tick * 3
  local path = PikachuFollower.picFrame(e)
  return path and path:match("([^/]+)%.png$") or tostring(path)
end

local e5 = talk(90, 128)
check(e5 and e5.pikaPic == "assets/generated/pikachu/pikapic_5.png", "low happiness raises pikapic 5")
if e5 then
  check(at(e5, 0) == "pikapic_5", "the ear starts still (pikaframedelay 2)", at(e5, 0))
  check(at(e5, 2) == "pikapic_5_18", "tick 2: the ear twitches (PikaAnimTilemap_18)", at(e5, 2))
  check(at(e5, 4) == "pikapic_5", "tick 4: back", at(e5, 4))
  check(at(e5, 6) == "pikapic_5_18", "tick 6: the ear holds bent for 64 ticks", at(e5, 6))
  check(at(e5, 31) == "pikapic_5_18", "and is still bent when the box closes", at(e5, 31))
end
local e9 = talk(90, 100)
check(e9 and e9.pikaPic == "assets/generated/pikachu/pikapic_9.png", "no happiness raises pikapic 9")
if e9 then
  check(at(e9, 2) == "pikapic_9_22", "tick 2: the tail twitches (PikaAnimTilemap_22)", at(e9, 2))
  check(at(e9, 4) == "pikapic_9", "tick 4: back", at(e9, 4))
  check(at(e9, 6) == "pikapic_9_22", "tick 6: twitch again", at(e9, 6))
  check(at(e9, 28) == "pikapic_9_22", "tick 28: the third twitch after the 20-tick rest", at(e9, 28))
  check(at(e9, 30) == "pikapic_9", "tick 30: the frameset restarts", at(e9, 30))
end
local e6 = talk(40, 128)
if e6 then
  check(at(e6, 8) == "pikapic_6_19", "pikapic 6 shuts its eye at tick 8 (PikaAnimTilemap_19)", at(e6, 8))
end

Sound.playPikaCry, Sound.waitFrames = realPlay, realWait
GameVersion.set("red")
T.finish("pikachu_pic_tables_2822")
