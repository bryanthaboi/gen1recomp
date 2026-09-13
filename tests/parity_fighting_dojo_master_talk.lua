-- ../pokered/scripts/FightingDojo.asm:106-136
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not Data.maps then Data:load() end

local S = require("tests.harness").suite("parity Fighting Dojo master talk")
local check, eq = S.check, S.eq

local realTextBox = package.loaded["src.render.TextBox"]
local shownTexts = {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone)
    shownTexts[#shownTexts + 1] = text
    if onDone then onDone() end
    return { text = text }
  end,
  soundOpts = function() return nil end,
}

package.loaded["data.scripts.story4"] = nil
local dojo = require("data.scripts.story4").FIGHTING_DOJO
local talk = dojo.talk.TEXT_FIGHTINGDOJO_KARATE_MASTER

local function saw(needle)
  for _, s in ipairs(shownTexts) do
    if s:find(needle, 1, true) then return true end
  end
  return false
end

local function run(flags, defeated)
  shownTexts = {}
  local states = {}
  local game = {
    data = Data,
    save = { flags = flags, defeatedTrainers = {} },
    stack = { push = function(_, s) states[#states + 1] = s end },
  }
  local master = { id = "FIGHTING_DOJO_obj_1",
                   def = { name = "FIGHTINGDOJO_KARATE_MASTER" } }
  local ow = {
    trainerDefeated = function() return defeated == true end,
    engageTrainer = function(self, npc, onDone, endText, skip, sound, isReward)
      self.engaged = { npc = npc, onDone = onDone, endText = endText,
                       skip = skip, isReward = isReward }
    end,
  }
  local doneCalled = false
  local onDone = function() doneCalled = true end
  talk(game, ow, master, onDone)
  return ow, doneCalled, onDone, master
end

check(type(talk) == "function",
      "the Karate Master has a hand-ported talk handler")

if type(talk) == "function" then
  do
    local ow, doneCalled = run({ EVENT_BEAT_KARATE_MASTER = true })
    check(saw("Indeed, I have"),
          "beaten but no prize taken repeats the prize offer")
    check(not saw("Stay and train"),
          "and not the post-prize 'Stay and train' line")
    check(ow.engaged == nil, "and does not re-engage him")
    check(doneCalled, "and releases the player")
  end

  do
    local ow, doneCalled = run({ EVENT_BEAT_KARATE_MASTER = true,
                                 EVENT_DEFEATED_FIGHTING_DOJO = true })
    check(saw("Stay and train"), "after the prize he says 'Stay and train'")
    check(not saw("Indeed, I have"), "and not the prize offer")
    check(ow.engaged == nil, "and does not re-engage him")
    check(doneCalled, "and releases the player")
  end

  do
    local ow, doneCalled = run({}, true)
    check(saw("Indeed, I have"),
          "a defeatedTrainers-only save still gets the prize offer")
    check(ow.engaged == nil, "and does not re-engage him")
    check(doneCalled, "and releases the player")
  end

  do
    local ow, doneCalled, onDone, master = run({})
    eq(#shownTexts, 0, "an unbeaten master prints no re-talk line")
    check(ow.engaged ~= nil, "an unbeaten master engages his battle")
    if ow.engaged then
      eq(ow.engaged.npc, master, "with himself as the trainer")
      eq(ow.engaged.onDone, onDone, "handing the talk's release to the battle")
      eq(ow.engaged.endText, Data.text._FightingDojoKarateMasterDefeatedText,
         "SaveEndBattleTextPointers .DefeatedText")
      eq(ow.engaged.isReward, false,
         "the armed line is not the victory reward dialogue")
    end
    check(not doneCalled, "and the player stays frozen until the battle ends")
  end
end

package.loaded["src.render.TextBox"] = realTextBox
S.finish()
