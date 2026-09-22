-- scripts/PewterPokecenter_2.asm:10-68

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SONG_POLLS = 16

local music = { polls = 0 }
package.loaded["src.core.Music"] = {
  ONE_SHOT_CEILING = 600,
  stop = function() end,
  restoreMap = function() end,
  play = function() end,
  playOnce = function() music.polls = 0; return true end,
  oneShotPlaying = function()
    music.polls = music.polls + 1
    return music.polls <= SONG_POLLS
  end,
}

local Sound = require("src.core.Sound")
local TextBox = require("src.render.TextBox")
local GameVersion = require("src.core.GameVersion")
local story5 = require("data.scripts.story5")

Sound.setRate(1)

local function newGame(party, player)
  local game = {
    save = { player = player or {}, flags = {}, options = { textSpeed = "FAST" },
             party = party },
    data = { audio = { fanfares = {}, sfx = {}, songs = {} }, text = {} },
    logicSpeed = function() return 1 end,
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function(self, btn) return self.queue[btn] or false end,
  }
  return game
end

local handler = story5.PEWTER_POKECENTER.talk.TEXT_PEWTERPOKECENTER_JIGGLYPUFF

local function dance(party, player)
  local game = newGame(party, player)
  local ow, npc = {}, { facing = "left" }
  local fired = false
  handler(game, ow, npc, function() fired = true end)
  local box = game.stack:top()
  local res = { turns = 0, held = 0, ow = ow, box = box }
  local last = npc.facing
  for _ = 1, 5000 do
    if game.stack:top() ~= box then break end
    box:update(1 / 60)
    if box.autoStarted then res.held = res.held + 1 end
    if npc.facing ~= last then
      res.turns = res.turns + 1
      last = npc.facing
    end
  end
  res.closed = game.stack:top() ~= box
  res.fired = fired
  return res
end

GameVersion.set("yellow")

do
  local r = dance({ { species = "PIKACHU", hp = 20 } })
  check(r.closed, "the dance box closes itself")
  check(r.fired, "the talk callback fires once the box pops")
  check(r.held >= 32 + (SONG_POLLS + 1) * 24 + 48,
    ("the box stays up for the whole song (held %d frames)"):format(r.held))
  eq(r.turns, SONG_POLLS, "one quarter turn per 24-frame poll while the song plays")
  check(r.turns >= 16, "at least four full spins")
  eq(r.ow.pikachuPewterSleepScene, true,
    "a healthy starter PIKACHU falls asleep once the dance ends")
end

do
  local r = dance({ { species = "PIKACHU", hp = 20, status = "PSN" } })
  check(r.closed, "statused: the dance still ends")
  eq(r.ow.pikachuPewterSleepScene, nil,
    "a statused starter PIKACHU stays awake and following")
end

do
  local r = dance({ { species = "BULBASAUR", hp = 20 } })
  eq(r.ow.pikachuPewterSleepScene, nil, "no PIKACHU in the party, no sleep scene")
end

do
  local player = { id = 1234, name = "YELLOW" }
  local r = dance({ { species = "PIKACHU", hp = 20, otId = 999, ot = "BRUNO" } }, player)
  eq(r.ow.pikachuPewterSleepScene, nil, "a traded PIKACHU is not the starter, no sleep scene")
  r = dance({ { species = "PIKACHU", hp = 20, otId = 999, ot = "BRUNO" },
              { species = "PIKACHU", hp = 20, otId = 1234, ot = "YELLOW" } }, player)
  eq(r.ow.pikachuPewterSleepScene, true, "the OT-matched starter behind a traded PIKACHU falls asleep")
  r = dance({ { species = "PIKACHU", hp = 20, otId = 999, ot = "BRUNO" },
              { species = "PIKACHU", hp = 20, otId = 1234, ot = "YELLOW", status = "SLP" } }, player)
  eq(r.ow.pikachuPewterSleepScene, nil, "the status check reads the starter, not a healthy traded PIKACHU")
end

GameVersion.set("red")

do
  local r = dance({ { species = "PIKACHU", hp = 20 } })
  check(r.turns >= 16, "Red: the same full-length dance")
  eq(r.ow.pikachuPewterSleepScene, nil, "Red: no sleep scene")
end

do
  local game = newGame({})
  local ow, npc = {}, { facing = "left" }
  handler(game, ow, npc, function() end)
  local gate = game.stack:top().auto.sound()
  check(Sound.waitFrames(gate) > 32 + 600 + 24 + 48,
    "the gate's wait budget covers the longest possible dance")
end

T.finish("jigglypuff_dance_gate_bug2335")
