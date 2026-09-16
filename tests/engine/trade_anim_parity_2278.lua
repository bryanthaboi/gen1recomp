-- engine/movie/trade.asm
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()
local ids = T.fixtures.ids

local S = require("tests.harness").suite("trade anim parity 2278")
local check, eq = S.check, S.eq

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local Sound = require("src.core.Sound")
local PaletteFX = require("src.render.PaletteFX")
local TradeAnim = require("src.ui.TradeAnim")

Data.text._TradeWentToText = "{RAM:wStringBuffer} went to\n{RAM:wLinkEnemyTrainerName}."
Data.text._TradeForText = "For {RAM:wStringBuffer},"
Data.text._TradeSendsText = "{RAM:wLinkEnemyTrainerName} sends\n{RAM:wNameBuffer}."
Data.text._TradeWavesFarewellText = "{RAM:wLinkEnemyTrainerName} waves."
Data.text._TradeTransferredText = "{RAM:wNameBuffer} is\ntransferred."
Data.text._TradeTakeCareText = "Take good care of\n{RAM:wNameBuffer}."

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
require("src.render.Font").load(Data)

local sent = Pokemon.new(Data, ids.species[1], 10)
local recv = Pokemon.new(Data, ids.species[2], 10)
recv.nickname = "DUX"
recv.ot = "TRAINER"
recv.otId = 8193
local recvName = Data.pokemon[recv.species].name

local sounds = {}
local realPlay, realCry = Sound.play, Sound.playCry
Sound.play = function(_, name) sounds[#sounds + 1] = { name = name } end
Sound.playCry = function() end

local done = false
local anim = TradeAnim.new(Game, {
  sent = sent, received = recv, enemyName = "TRAINER",
  onDone = function() done = true end,
})
Game.stack:push(anim)
if anim.enter then anim:enter() end
eq(#sounds, 0, "enter() plays no SFX")

local texts, subs = {}, {}
local monVisibleInPoof, boxInRest, ballInRest = false, true, true
local lastSub = nil
local guard = 0
while not done and guard < 20000 do
  guard = guard + 1
  for i = #sounds, 1, -1 do sounds[i].phase = sounds[i].phase or anim.phase end
  StateStack:update(1 / 60)
  if anim.dialogText then texts[anim.dialogText] = true end
  if anim.phase == "show_enemy" and anim.sub and anim.sub ~= lastSub then
    subs[#subs + 1] = anim.sub
    lastSub = anim.sub
  end
  if anim.phase == "show_enemy" and anim.sub == "poof" then
    monVisibleInPoof = monVisibleInPoof or anim.monVisible
  end
  if anim.phase == "show_enemy" and anim.sub == "ball_rest" then
    boxInRest = boxInRest and anim.boxVisible == true
    ballInRest = ballInRest and anim.activeBallBlock ~= nil
    monVisibleInPoof = monVisibleInPoof or anim.monVisible
  end
end
Sound.play, Sound.playCry = realPlay, realCry
check(done, "TradeAnim reaches onDone")

-- data/moves/animations.asm:1198, data/battle_anims/special_effects.asm:24
local firstMachine
for _, s in ipairs(sounds) do
  check(s.name ~= "Ball_Poof", "no Ball_Poof SFX (" .. tostring(s.name) .. ")")
  if s.name == "Trade_Machine" and not firstMachine then firstMachine = s.phase end
end
eq(firstMachine, "ball_enter", "Trade_Machine only once the ball is sucked in")

-- engine/movie/trade.asm:186
local sawSends, sawTransferred, sawTakeCare = false, false, false
for text in pairs(texts) do
  check(not text:find("DUX", 1, true), "no nickname in dialog: " .. text)
  if text:find("sends", 1, true) then sawSends = true end
  if text:find("transferred", 1, true) then sawTransferred = true end
  if text:find("Take good care", 1, true) then sawTakeCare = true end
  if text:find("sends", 1, true) or text:find("transferred", 1, true)
     or text:find("Take good care", 1, true) then
    check(text:find(recvName, 1, true) ~= nil,
          "species name in dialog: " .. text)
  end
end
check(sawSends and sawTransferred and sawTakeCare, "all three name lines printed")

-- engine/movie/trade.asm:354
local order = table.concat(subs, ",")
eq(order:sub(1, #"ball_bounce,ball_rest,poof,cry"),
   "ball_bounce,ball_rest,poof,cry", "ball rests on the box before the poof")
check(boxInRest, "info box is up while the ball rests")
check(ballInRest, "ball is drawn while it rests")
check(not monVisibleInPoof, "mon stays hidden until the poof ends")

-- engine/movie/trade.asm:602
PaletteFX.setMode("ogred")
local flash = TradeAnim.new(Game, { sent = sent, received = recv })
flash.phase = "transfer_lr"
flash.cableFlash = false
local base = flash:sgbPalettes(Game)
flash.cableFlash = true
local swapped = flash:sgbPalettes(Game)
check(base and base[1] and base[1].colors, "cable zone exists")
eq(swapped[1].colors[2], base[1].colors[3], "shade 1 shows shade 2 on flash")
eq(swapped[1].colors[3], base[1].colors[2], "shade 2 shows shade 1 on flash")
eq(swapped[1].colors[1], base[1].colors[1], "shade 0 unchanged")
eq(swapped[1].colors[4], base[1].colors[4], "shade 3 unchanged")

-- engine/link/cable_club.asm:145
local linkSrc = assert(io.open("src/link/LinkState.lua", "rb")):read("*a")
check(not linkSrc:find("Trade_Machine", 1, true),
      "LinkState plays no Trade_Machine before the cinematic")

S.finish()
