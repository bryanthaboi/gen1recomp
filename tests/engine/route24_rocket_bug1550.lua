-- The Nugget Bridge recruiter has no def_trainers header, so the port's
-- headerless engageTrainer fallback re-printed his contest line as the
-- pre-battle box (#1550) and his loss line never reached the battle
-- screen (#1551).  scripts/Route24.asm:120-134: .JoinTeamRocketText, then
-- SaveEndBattleTextPointers with .DefeatedText, then EngageMapTrainer with
-- no further box; Route24AfterRocketBattleScript (:62-78) prints
-- .YouCouldBecomeATopLeaderText on the map after the win.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()
local SaveData = require("src.core.SaveData")

Data.items.NUGGET = Data.items.NUGGET
  or { id = "NUGGET", index = 49, name = "NUGGET", price = 10000 }
Data.text._Route24CooltrainerM1YouBeatOurContestText =
  "Congratulations!\nYou beat our 5\ncontest trainers!"
Data.text._Route24CooltrainerM1YouJustEarnedAPrizeText = "You just earned\na prize!"
Data.text._Route24CooltrainerM1ReceivedNuggetText = "{PLAYER} got\n{RAM:wStringBuffer}!"
Data.text._Route24CooltrainerM1JoinTeamRocketText = "Want to join us?"
Data.text._Route24CooltrainerM1DefeatedText = "Arrgh!\nYou are good!"
Data.text._Route24CooltrainerM1YouCouldBecomeATopLeaderText =
  "With your ability,\nyou could become\na top leader!"

local pushed = {}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
  substitute = function(_, s) return s end,
  soundOpts = function(_, sound, opts)
    opts = opts or {}
    opts.auto = { sound = sound, wait = true, delay = 0 }
    return opts
  end,
}

local scripts = dofile("data/scripts/story4.lua")
local handler = scripts.ROUTE_24.talk.TEXT_ROUTE24_COOLTRAINER_M1
T.check(type(handler) == "function", "the recruiter has a hand-ported handler")

local game = {
  data = Data,
  save = SaveData.newGame(),
  stack = { push = function(_, box) pushed[#pushed + 1] = box end },
}

local defeated = false
local engaged
local ow = {
  trainerDefeated = function() return defeated end,
  engageTrainer = function(_, npc, onDone, endBattleText, skipBattleText)
    engaged = { npc = npc, onDone = onDone,
                endBattleText = endBattleText, skipBattleText = skipBattleText }
  end,
}
local npc = { id = "ROUTE24_ROCKET", def = { index = 1 } }

-- the prize has already been taken: the talk goes straight to the battle
game.save.flags.EVENT_GOT_NUGGET = true
local doneCalls = 0
handler(game, ow, npc, function() doneCalls = doneCalls + 1 end)

T.check(engaged ~= nil, "the recruiter engages")
T.eq(#pushed, 0, "no text box is pushed before the battle (#1550)")
T.eq(engaged.skipBattleText, true,
  "skipBattleText stops the map text becoming the pre-battle box")
T.eq(engaged.endBattleText, Data.text._Route24CooltrainerM1DefeatedText,
  "the loss line rides the battle, as SaveEndBattleTextPointers does (#1551)")

-- the win: Route24AfterRocketBattleScript prints the top-leader line
defeated = true
engaged.onDone()
T.eq(#pushed, 1, "the win prints exactly one box")
T.eq(pushed[1].text, Data.text._Route24CooltrainerM1YouCouldBecomeATopLeaderText,
  "and it is .YouCouldBecomeATopLeaderText")
pushed[1].onDone()
T.eq(doneCalls, 1, "control returns once the box closes")

-- the blackout arm: wIsInBattle == $ff rets before the DisplayTextID
pushed, defeated, doneCalls = {}, false, 0
handler(game, ow, npc, function() doneCalls = doneCalls + 1 end)
engaged.onDone()
T.eq(#pushed, 0, "a loss prints nothing")
T.eq(doneCalls, 1, "and just unfreezes the player")

T.finish("Nugget Bridge Rocket battle text (#1550, #1551)")
