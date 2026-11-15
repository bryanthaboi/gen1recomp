-- Parity test: Giovanni's "WHAT! This cannot be!" is an end-battle line.
--
-- RocketHideoutB4FGiovanniText arms it with SaveEndBattleTextPointers
-- before EngageMapTrainer (scripts/RocketHideoutB4F.asm:99-120), so
-- PrintEndBattleText prints it on the battle screen between
-- TrainerDefeatedText and MoneyForWinningText.  The port pushed it as an
-- overworld TextBox from onFinish, i.e. after the map was back (#1817).
--
-- Self-contained; run via `luajit tests/parity_giovanni_end_battle.lua`.
-- Also picked up by tests/run_tests.lua's parity_* glob.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity giovanni end battle")
local check, eq = S.check, S.eq

local realTextBox = package.loaded["src.render.TextBox"]
local realBattleState = package.loaded["src.battle.BattleState"]

local pushed = {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, cb)
    local box = { text = text, cb = cb }
    table.insert(pushed, box)
    return box
  end,
  substitute = function(_, text) return text end,
  soundOpts = function(_, _, opts) return opts or {} end,
}
local battles = {}
package.loaded["src.battle.BattleState"] = {
  newTrainer = function(_, class, index)
    local b = { trainerClass = class, partyIndex = index }
    table.insert(battles, b)
    return b
  end,
}

local scripts = dofile("data/scripts/story3.lua")
local handler = scripts.ROCKET_HIDEOUT_B4F.talk.TEXT_ROCKETHIDEOUTB4F_GIOVANNI
check(handler ~= nil, "the Giovanni talk handler is registered")

local game = {
  data = { text = {
    _RocketHideoutB4FGiovanniImpressedYouGotHereText = "So! I must say, I\nam impressed you\ngot here!{DONE}",
    _RocketHideoutB4FGiovanniWhatCannotBeText = "WHAT!\nThis cannot be!{PROMPT}",
    _RocketHideoutB4FGiovanniHopeWeMeetAgainText = "I shall step\naside this time!\fI hope we meet\nagain...{DONE}",
  } },
  save = { defeatedTrainers = {}, flags = {}, player = { name = "RED" } },
  stack = { push = function() end },
}
local ow = {
  trainerDefeated = function() return false end,
  pushBattle = function() end,
  playTrainerMusic = function() end,
  afterBattle = function() end,
}

handler(game, ow, { id = 7 }, function() end)
eq(#pushed, 1, "the impressed line opens the scene")
pushed[1].cb()
eq(#battles, 1, "talking starts the Giovanni battle")
local battle = battles[1]
check(battle.endBattleText ~= nil,
  "the loss line is handed to the battle (SaveEndBattleTextPointers)")
check(battle.endBattleText:find("cannot be") ~= nil,
  "and it is the WHAT!/This cannot be! text")

pushed = {}
battle.onFinish("win")
eq(#pushed, 1, "victory pushes exactly one overworld box")
check(pushed[1].text:find("cannot be") == nil,
  "the cannot-be line no longer reprints on the map")
check(pushed[1].text:find("meet") ~= nil,
  "BeatGiovanniScript's hope-we-meet-again text follows instead")
eq(game.save.flags.EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI, true,
  "the beat-Giovanni event flag is set")

package.loaded["src.render.TextBox"] = realTextBox
package.loaded["src.battle.BattleState"] = realBattleState

S.finish()
