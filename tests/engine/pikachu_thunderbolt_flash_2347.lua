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
Assets.exists = function(path)
  if path:find("pikapic_", 1, true) then return true end
  return realExists(path)
end

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
  local log = { frames = 0, bgp = {}, skippableAt = {} }
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
      log.bgp[#log.bgp + 1] = e.bgp or false
      log.skippableAt[#log.skippableAt + 1] = e.skippable and true or false
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
eq(#log.bgp - (46 + 80), 30 + 4, "WaitForSoundToFinish holds the box until the sound ends")

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

Sound.playMove, Sound.playPikaCry, Sound.playCry = realPlayMove, realPikaCry, realCry
Sound.moveSfxBusy, Music.duckForFanfare = realBusy, realDuck
Assets.exists = realExists
GameVersion.set("red")

T.finish("pikachu_thunderbolt_flash_2347")
