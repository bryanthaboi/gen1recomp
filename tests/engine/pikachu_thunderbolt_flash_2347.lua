-- pokeyellow data/pikachu/pikachu_pic_animation.asm:281
-- pokeyellow engine/pikachu/pikachu_pic_animation.asm:790
-- pokeyellow data/pikachu/pikachu_pic_animation.asm:1
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local PikachuFollower = require("src.world.PikachuFollower")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local Assets = require("src.render.Assets")

GameVersion.set("yellow")

local moveCalls, cryCalls, ducks = {}, {}, {}
local busyFrames = 0
local realPlayMove, realPikaCry, realCry = Sound.playMove, Sound.playPikaCry, Sound.playCry
local realBusy, realDuck = Sound.moveSfxBusy, Music.duckForFanfare
Sound.playMove = function(_, anim) moveCalls[#moveCalls + 1] = anim end
Sound.playPikaCry = function(_, n) cryCalls[#cryCalls + 1] = n return true end
Sound.playCry = function() return nil end
Sound.moveSfxBusy = function()
  if busyFrames > 0 then busyFrames = busyFrames - 1 return true end
  return false
end
Music.duckForFanfare = function(src) ducks[#ducks + 1] = src end
local realExists = Assets.exists
Assets.exists = function() return false end

local tbAnim = { sound = "Battle_2F", pitch = 32, tempo = 128 }
local game = {
  data = {
    moves = { THUNDERBOLT = { anim = tbAnim } },
    field = { emotionBubbles = { bubbles = {
      { name = "EXCLAMATION_BUBBLE" }, { name = "QUESTION_BUBBLE" },
      { name = "SMILE_BUBBLE" }, { name = "BOLT_BUBBLE" },
    } } },
  },
  save = {
    player = { name = "YELLOW", id = 1234 },
    party = { { species = "PIKACHU", hp = 40, ot = "YELLOW", otId = 1234 } },
    pikachuHappiness = 120, pikachuMood = 128, flags = {},
  },
}

PikachuFollower.onMoveLearned(game.save, game.save.party[1], "THUNDERBOLT")
eq(game.save.pikachuEmotionModifier, 5, "learning THUNDERBOLT arms modifier 5")

local function newOw()
  return {
    map = { id = "ROCK_TUNNEL_1F" },
    player = { facing = "up" },
  }
end

local function runPress(ow, pressAt)
  local log = { frames = 0, bgp = {}, skippableAt = {}, pics = {}, lifts = {},
                close = {} }
  local guard = 0
  while ow.emote and guard < 2000 do
    guard = guard + 1
    local e = ow.emote
    if e.boltAt then PikachuFollower.tickBolt(game, ow, e) end
    e.frames = e.frames - 1
    local pressed = pressAt and log.frames + 1 == pressAt
    log.frames = log.frames + 1
    if e.pikaPic then
      log.pic = log.pic or e
      local path, lift = PikachuFollower.picFrame(e)
      log.pics[#log.bgp + 1] = path and path:match("([^/]+)%.png$") or false
      log.lifts[#log.bgp + 1] = lift
      log.bgp[#log.bgp + 1] = e.bgp or false
      log.skippableAt[#log.skippableAt + 1] = e.skippable and true or false
      if e.boltDone and e.frames > 0 then
        log.close[#log.close + 1] = tostring(log.pics[#log.pics])
      end
    end
    if (e.skippable and pressed) or e.frames <= 0 then
      local done = e.onDone
      ow.emote = nil
      if done then done() end
    end
  end
  return log
end

local function newNpc()
  return { cellX = 5, cellY = 5, px = 80, py = 80, facing = "down" }
end

local ow = newOw()
PikachuFollower.talk(game, ow, newNpc(), function() end)
check(ow.emote ~= nil, "talking to Pikachu opens an emote")
eq(ow.emote.bubble, 4, "modifier 5 opens with the BOLT bubble (PikachuEmotion25)")
eq(ow.emote.pikaPic, nil, "the bubble comes before the pikapic")

local log = runPress(ow)
check(log.pic ~= nil, "the pikapic box follows the bubble")
eq(log.pic.boltAt, 45, "the bolt fires after 2 setup ticks + writebyte 13 (45 frames)")
eq(#cryCalls >= 1 and cryCalls[1], 35, "PikachuCry35 plays")
eq(#moveCalls, 1, "the THUNDERBOLT move sound plays once")
check(moveCalls[1] == tbAnim, "it is THUNDERBOLT's MoveSoundTable entry (Battle_2F)")
eq(#ducks, 1, "music is muted for the bolt")

local pre = 0
for i = 1, #log.bgp do
  if log.bgp[i] then break end
  pre = pre + 1
end
eq(pre, 46, "no palette write until the mute DelayFrame has passed")
local strobeOk = true
for row = 1, 20 do
  local want = (row % 2 == 1) and 0xC0 or 0xE4
  for f = 1, 4 do
    if log.bgp[pre + (row - 1) * 4 + f] ~= want then strobeOk = false end
  end
end
check(strobeOk, "20 rows of 4 frames alternate %11000000 / %11100100")
local tail = #log.bgp - (pre + 80)
check(tail >= 1, "the box stays up after the strobe")
local tailLit = true
for i = pre + 81, #log.bgp do
  if log.bgp[i] ~= 0xE4 then tailLit = false end
end
check(tailLit, "the lit %11100100 BGP holds until the box closes")

eq(log.pic.pikaPic, "assets/generated/pikachu/pikapic_25.png",
   "the base pic is the cache rip even when Assets.exists says no (no fallback)")
local function runOf(from, to, want)
  for i = from, to do
    if log.pics[i] ~= want or log.lifts[i] ~= 0 then return false end
  end
  return true
end
check(runOf(1, 17, "pikapic_25"), "ticks 0-5: the base frown Pic_e77cf alone (pikaframedelay 6)")
check(runOf(18, 35, "gfx_e7863"), "ticks 6-11: PikaAnimTilemap_9 draws GFX_e7863")
check(runOf(36, pre, "gfx_e79f3"), "tick 12 on: PikaAnimTilemap_10 draws GFX_e79f3")
local strobePose = true
for i = pre + 1, pre + 80 do
  if log.pics[i] ~= "gfx_e79f3" or log.lifts[i] ~= 0 then strobePose = false end
end
check(strobePose, "the Thunderbolt pose GFX_e79f3 holds through every strobe frame, unlifted")
local tailPose, blank = true, 0
for i = pre + 81, #log.pics do
  if log.pics[i] == false then blank = blank + 1
  elseif blank > 0 or log.pics[i] ~= "gfx_e79f3" then tailPose = false end
end
check(tailPose, "and through the lit tail")
check(blank >= 1, "the box is emptied before it closes (.RunPikapic PlacePikapicTextBoxBorder)")
eq(table.concat(log.close, ",", 1, math.min(#log.close, 6)) .. "|" .. #log.close,
   "gfx_e79f3,gfx_e79f3,gfx_e79f3,false,false,false|6",
   "PlacePikapicTextBoxBorder: the pose stays up for the first Delay3, the empty box for the second")
eq(log.skippableAt[45], true, "A/B can still cut the pic before the bolt")
eq(log.skippableAt[46], false, "the bolt itself is not skippable")
check(not ducks[1].isPlaying(), "the mute releases once the box closes")

eq(game.save.pikachuEmotionModifier, 5, "the talk keeps the modifier")
moveCalls, ducks = {}, {}
ow = newOw()
PikachuFollower.talk(game, ow, newNpc(), function() end)
eq(ow.emote and ow.emote.bubble, 4, "a second talk inside the window replays PikachuEmotion25")
busyFrames = 30
log = runPress(ow)
eq(#moveCalls, 1, "the second talk bolts again")
eq(#log.bgp - (46 + 80), 30 + 7, "WaitForSoundToFinish holds the box until the sound ends")

moveCalls, ducks = {}, {}
ow = newOw()
PikachuFollower.talk(game, ow, newNpc(), function() end)
local bubbleFrames = ow.emote.frames
log = runPress(ow, bubbleFrames + 10)
eq(#moveCalls, 0, "cutting the pic short before the bolt skips the flash")
eq(#ducks, 0, "and never mutes the music")

for _ = 1, 5 do PikachuFollower.onStep(game.save) end
eq(game.save.pikachuEmotionModifier, nil, "five steps from $85 clear the modifier")
ow = newOw()
PikachuFollower.talk(game, ow, newNpc(), function() end)
moveCalls = {}
log = runPress(ow)
eq(#moveCalls, 0, "a plain mood talk has no bolt")
check(log.pic == nil or log.pic.boltAt == nil, "and no bolt spec")

local function poseAt(e, tick)
  e.frames = e.pikaTotal - tick * 3
  local path, lift = PikachuFollower.picFrame(e)
  return path and path:match("([^/]+)%.png$") or false, lift
end
game.save.pikachuHappiness, game.save.pikachuMood = 255, 255
ow = newOw()
PikachuFollower.talk(game, ow, newNpc(), function() end)
local e20 = ow.emote
check(e20 and e20.pikaPoses ~= nil, "emotion 20 plays PikaPicAnimBGFrames_26 from ripped poses")
if e20 and e20.pikaPoses then
  eq(poseAt(e20, 0), "pikapic_20", "script 20 opens on its base pic (pikaframedelay 8)")
  eq(poseAt(e20, 8), "gfx_e6646", "tick 8: PikaAnimTilemap_34 draws GFX_e6646")
  eq(poseAt(e20, 20), "pikapic_20", "tick 20: back to the base")
  eq(poseAt(e20, 28), "gfx_e6646", "tick 28: the pose again")
  eq(poseAt(e20, 40), "pikapic_20", "tick 40: the frameset restarts at pikaframeend")
  local _, lift = poseAt(e20, 8)
  eq(lift, 0, "a ripped pose is drawn in place, not lifted")
  eq(PikachuFollower.picLift(e20), 0, "picLift stays 0 for a pose script")
end

local P = PikachuFollower.PIKAPIC
local function fakeEmote(script)
  local a = P[script]
  local poses
  if a.poses then
    poses = {}
    for i = 1, #a.seq do
      poses[i] = a.poses[i] and ("assets/generated/pikachu/gfx_" .. a.poses[i] .. ".png") or false
    end
  end
  return { pikaPic = "assets/generated/pikachu/pikapic_" .. script .. ".png",
           pikaSeq = a.seq, pikaPoses = poses, pikaTotal = a.dur * 3, frames = a.dur * 3 }
end
local e21 = fakeEmote(21)
eq(poseAt(e21, 8), "gfx_e682f", "script 21 tick 8: PikaAnimTilemap_9 -> GFX_e682f")
eq(poseAt(e21, 10), "gfx_e69bf", "script 21 tick 10: PikaAnimTilemap_10 -> GFX_e69bf")
eq(poseAt(e21, 11), "gfx_e6b4f", "script 21 tick 11: PikaAnimTilemap_11 -> GFX_e6b4f")
eq(poseAt(e21, 12), "gfx_e6cdf", "script 21 tick 12: PikaAnimTilemap_12 -> GFX_e6cdf")
local e26 = fakeEmote(26)
eq(poseAt(e26, 56), "gfx_e7b83", "script 26 tick 56: GFX_e7b83")
eq(poseAt(e26, 64), "gfx_e7d13", "script 26 tick 64: GFX_e7d13 holds")
local e7 = fakeEmote(7)
eq(poseAt(e7, 0), "gfx_e4841", "script 7 opens on PikaAnimTilemap_20 (GFX_e4841)")
eq(poseAt(e7, 8), "pikapic_7", "script 7 tick 8: base")
local e4 = fakeEmote(4)
local p4, l4 = poseAt(e4, 8)
check(p4 == "pikapic_4" and l4 > 0, "script 4 (20-tile GFX_e444b overlay) keeps the picLift stand-in")

local CacheContract = require("src.import.CacheContract")
local required = {}
for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES.yellow or {}) do required[path] = true end
local listed, missing = 0, {}
for script, a in pairs(P) do
  for _, id in ipairs(a.poses or {}) do
    if id then
      local path = "assets/generated/pikachu/gfx_" .. id .. ".png"
      if required[path] then listed = listed + 1 else missing[#missing + 1] = script .. ":" .. id end
    end
  end
  if a.poses then eq(#a.poses, #a.seq, "script " .. script .. " has one pose slot per run") end
end
check(listed > 0, "the frameset table names ripped poses")
check(#missing == 0, "every pose the frameset table draws is a required yellow cache file "
      .. table.concat(missing, ","))

Sound.playMove, Sound.playPikaCry, Sound.playCry = realPlayMove, realPikaCry, realCry
Sound.moveSfxBusy, Music.duckForFanfare = realBusy, realDuck
Assets.exists = realExists
GameVersion.set("red")

T.finish("pikachu_thunderbolt_flash_2347")
