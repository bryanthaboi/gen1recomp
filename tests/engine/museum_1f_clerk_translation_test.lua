-- The museum 1F ticket clerk's take-your-time/not-enough-money/come-again
-- lines used to be bare English literals, invisible to game.data.text no
-- matter what a translation mod put there. tests/engine/museum_money_box_
-- bug1335.lua only ever runs with an empty game.data.text, so it can't
-- tell a properly-wired t._Key or "..." fallback apart from a literal that
-- never looked at t at all -- every assertion there passes either way.
-- This test populates game.data.text with translated values and checks
-- they actually reach the pushed TextBox, for all three lines.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
}

local M = assert(loadfile("data/scripts/story2.lua"))()
local clerk = M.MUSEUM_1F.talk.TEXT_MUSEUM1F_SCIENTIST1

local TRANSLATED = {
  _Museum1FScientist1TakePlentyOfTimeText = "Prends ton temps\net profite bien !",
  _Museum1FScientist1DontHaveEnoughMoneyText = "Tu n'as pas assez\nd'argent.",
  _Museum1FScientist1ComeAgainText = "Reviens vite !",
}

local pushed
local function mkGame(cash)
  pushed = {}
  return {
    data = { text = TRANSLATED },
    save = { money = cash, flags = {} },
    stack = { push = function(_, box) pushed[#pushed + 1] = box end },
  }
end

-- already ticketed: take-your-time line
local g = mkGame(3000)
g.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = true
clerk(g, nil, nil, function() end)
T.eq(pushed[1].text, TRANSLATED._Museum1FScientist1TakePlentyOfTimeText,
  "an existing ticket holder gets the translated take-your-time line")

-- YES but short on cash: not-enough-money line
g = mkGame(20)
clerk(g, nil, nil, function() end)
pushed[1].opts.choice(true)
T.eq(pushed[2].text, TRANSLATED._Museum1FScientist1DontHaveEnoughMoneyText,
  "short on cash opens the translated not-enough-money box")

-- NO: come-again line
g = mkGame(3000)
clerk(g, nil, nil, function() end)
pushed[1].opts.choice(false)
T.eq(pushed[2].text, TRANSLATED._Museum1FScientist1ComeAgainText,
  "declining opens the translated come-again box")

-- unpopulated game.data.text still falls back to the English literal
g = { data = { text = {} }, save = { money = 3000, flags = {} },
  stack = { push = function(_, box) pushed[#pushed + 1] = box end } }
pushed = {}
g.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = true
clerk(g, nil, nil, function() end)
T.check(tostring(pushed[1].text):find("Take your time", 1, true) ~= nil,
  "an empty catalog still falls back to the English take-your-time line")

T.finish("museum_1f_clerk_translation_test")
