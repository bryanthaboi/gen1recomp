package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity Yellow disabled Pikachu")
local check, eq = S.check, S.eq
local Data = require("src.core.Data")
Data:load()
local GameVersion = require("src.core.GameVersion")
local Follower = require("src.world.PikachuFollower")
local ItemEffects = require("src.inventory.ItemEffects")
local PartyMenu = require("src.ui.PartyMenu")
local BoxMenu = require("src.ui.BoxMenu")
local TextBox = require("src.render.TextBox")

local oldVersion = GameVersion.get()
GameVersion.set("yellow")

local save = {
  player = { id = 7, name = "RED" },
  party = {
    { species = "PIKACHU", otId = 7, ot = "RED", hp = 20 },
    { species = "PIDGEY", otId = 7, ot = "RED", hp = 20 },
  },
}

check(Follower.isStarterPikachu(save, save.party[1]), "the player Pikachu is identified")
check(not Follower.isStarterPikachu(save, save.party[2]), "other party members are not starter Pikachu")

local pika = { pikachuFollower = true, cellX = 3, cellY = 4, facing = "up" }
local clefairy = { def = { index = 3, name = "POKEMONFANCLUB_CLEFAIRY" },
                   cellX = 6, cellY = 4 }
local seel = { def = { index = 4, name = "POKEMONFANCLUB_SEEL" },
               cellX = 1, cellY = 4 }
local moves = {}
local ow = {
  map = { id = "POKEMON_FAN_CLUB" },
  player = { cellX = 2, cellY = 7, facing = "up" },
  npcs = { pika, clefairy, seel },
  scriptMove = function(_, npc, dir, tiles, done)
    moves[#moves + 1] = { dir, tiles, npc.stepFrames }
    npc.facing = dir
    if done then done() end
  end,
}

local fanGame = { save = save, data = Data }
Follower.onFanClubEntered(fanGame, ow)
check(ow.pikachuFanClubScene, "Fan Club disables normal Pikachu following")
check(not save.pikachuMapScriptActive,
  "the map-script bit is still clear while the scene runs")
eq(ow.player.facing, "up", "the Fan Club scene leaves the player's facing alone")
eq(#moves, 0, "the walk waits for the bubble instead of starting with it")
check(ow.emote and ow.emote.frames == 60 and type(ow.emote.bubble) == "number"
      and not ow.emote.pikaPic,
  "the exclamation bubble holds 60 frames on its own")

ow.emote.onDone()
eq(moves[1] and moves[1][1], "up", "Fan Club starts with slide-up displacement")
eq(moves[1] and moves[1][2], 1, "Fan Club slide-up spans one tile")
eq(moves[1] and moves[1][3], 32, "the $26 slide costs 32 frames, not 16")
eq(moves[2] and moves[2][1], "right", "Fan Club then walks right")
eq(moves[2] and moves[2][2], 3, "Fan Club walks right three tiles")
eq(moves[2] and moves[2][3], 16, "the $20 steps stay at 16 frames")
eq(moves[3] and moves[3][1], "up", "Fan Club ends walking up")
eq(moves[3] and moves[3][2], 1, "Fan Club final up spans one tile")
eq(moves[3] and moves[3][3], 16, "and the closing $1e is 16 frames too")
eq(clefairy.movementStatus, 2, "Fan Club puts the Clefairy into movement delay")
eq(clefairy.facing, "down", "Fan Club turns the Clefairy down")
eq(seel.movementStatus, nil, "the Seel is left alone")
check(ow.emote and ow.emote.pikaPic and ow.emote.bubble == false,
  "emotion 29 raises the framed pic with no bubble of its own")
check(not save.pikachuMapScriptActive,
  "and the map-script bit waits for the emotion to finish")
ow.emote.onDone()
check(save.pikachuMapScriptActive, "Fan Club sets the map-script flag at the end")
check(Follower.isFollowingDisabled(ow), "disabled Fan Club follower blocks starter selection")

-- engine/pikachu/pikachu_emotions.asm:303
local Sound = require("src.core.Sound")
local realCry = Sound.playPikaCry
local cry
Sound.playPikaCry = function(_, index) cry = index return true end
save.pikachuMapScriptActive = nil
pika.facePlayer = function(self) self.facing = "down" end
Follower.talk(fanGame, ow, pika)
eq(cry, 5, "before the scene bit is set a press is emotion 29")
check(ow.emote and ow.emote.pikaPic and not ow.emote.bubble,
  "and emotion 29 has no bubble to hold first")

local bubbles = Data.field.emotionBubbles.bubbles
bubbles[#bubbles + 1] = { name = "HEART_BUBBLE", x = 0, y = 0, w = 8, h = 8 }
save.pikachuMapScriptActive = true
pika.facing = "up"
Follower.talk(fanGame, ow, pika)
check(ow.emote and ow.emote.frames == 60 and type(ow.emote.bubble) == "number"
      and not ow.emote.pikaPic,
  "afterwards emotion 30 opens with the heart bubble alone")
eq(pika.facing, "up", "pikaemotion_9's turn has not happened yet")
ow.emote.onDone()
eq(pika.facing, "down",
  "the turn toward the player lands with the cry, facing player XOR 4")
eq(cry, 5, "emotion 30 cries after its bubble")
check(ow.emote and ow.emote.pikaPic, "and only then raises the pic")
Sound.playPikaCry = realCry
bubbles[#bubbles] = nil
save.pikachuMapScriptActive = true
ow.emote = nil

local sleepOw = {
  map = { id = "PEWTER_POKECENTER" },
  player = { cellX = 3, cellY = 5 },
  npcs = { pika },
  pikachuPewterSleepScene = true,
}
local result = ItemEffects.use(Data, save, "POKE_FLUTE", nil, nil, nil, sleepOw)
eq(result, "flute_wake_pikachu", "Poké Flute is allowed next to sleeping Pikachu")
check(Follower.isFollowingDisabled(sleepOw), "sleeping Pikachu disables normal follower actions")

local pushed = {}
local partyGame = {
  save = save,
  overworld = sleepOw,
  stack = { push = function(_, state) pushed[#pushed + 1] = state end },
  input = { wasPressed = function(_, key) return key == "a" end },
}
PartyMenu.new(partyGame):update()
check(getmetatable(pushed[#pushed]) == TextBox,
  "sleeping Pikachu cannot be selected from the party menu")

local boxGame = {
  save = save,
  overworld = sleepOw,
  data = { pokemon = { PIKACHU = { name = "PIKACHU" }, PIDGEY = { name = "PIDGEY" } }, text = {} },
  stack = { push = function(_, state) pushed[#pushed + 1] = state end },
}
local pc = BoxMenu.new(boxGame)
pc.items[2].onSelect()
local depositList = pushed[#pushed]
depositList.onChoose(depositList.items[1], depositList)
check(getmetatable(pushed[#pushed]) == TextBox,
  "sleeping Pikachu cannot be deposited into Bill's PC")
eq(#save.party, 2, "PC refusal leaves the party unchanged")

GameVersion.set(oldVersion)
S.finish()
