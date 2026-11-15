-- The Pewter museum ticket clerk's money box (#1335): the closure re-reads
-- the balance, so the thank-you box shows 50 less than the ask did, and
-- the decline boxes keep the box up too (scripts/Museum1F.asm:71-112).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
}

local M = assert(loadfile("data/scripts/story2.lua"))()
local clerk = M.MUSEUM_1F.talk.TEXT_MUSEUM1F_SCIENTIST1

local MUSEUM_TEXT = {
  _Museum1FScientist1AmberIsFossilizedTreeSapText = "AMBER is fossil-\nized tree sap.{DONE}",
  _Museum1FScientist1ComeAgainText = "Come again!{DONE}",
  _Museum1FScientist1DoYouKnowWhatAmberIsText = "You can't sneak\nin the back way!\fOh, whatever!\nDo you know what\vAMBER is?{DONE}",
  _Museum1FScientist1DontHaveEnoughMoneyText = "You don't have\nenough money.{PROMPT}",
  _Museum1FScientist1GoToOtherSideText = "Please go to the\nother side!{DONE}",
  _Museum1FScientist1TakePlentyOfTimeText = "Take plenty of\ntime to look!{DONE}",
  _Museum1FScientist1ThankYouText = "Right, ¥50!\nThank you!{DONE}",
  _Museum1FScientist1TheresALabSomewhereText = "There's a lab\nsomewhere trying\vto resurrect\vancient POKéMON\vfrom AMBER.{DONE}",
  _Museum1FScientist1WouldYouLikeToComeInText = "It's ¥50 for a\nchild's ticket.\fWould you like to\ncome in?{DONE}",
}

local pushed
local function mkGame(cash)
  pushed = {}
  return {
    data = { text = MUSEUM_TEXT },
    save = { money = cash, flags = {} },
    stack = { push = function(_, box) pushed[#pushed + 1] = box end },
  }
end

-- YES with enough money: the prompt carries the money closure and reads
-- the pre-payment balance; the thank-you box re-reads the reduced one
local g = mkGame(3000)
local doneFired = false
clerk(g, nil, nil, function() doneFired = true end)
local ask = pushed[1]
T.check(ask.opts ~= nil and ask.opts.money ~= nil and ask.opts.choice ~= nil,
  "the ask box carries both a money closure and the YES/NO choice")
T.eq(ask.opts.money(), 3000, "the ask box reads 3000 before paying")
ask.opts.choice(true)
local thanks = pushed[2]
T.check(tostring(thanks.text):find("Thank you", 1, true) ~= nil,
  "YES opens the thank-you box")
T.check(thanks.opts ~= nil and thanks.opts.money ~= nil,
  "the thank-you box carries a money closure")
T.eq(thanks.opts.money(), 2950,
  "the thank-you box re-reads the balance, 50 less than the ask")
T.check(g.save.flags.EVENT_BOUGHT_MUSEUM_TICKET, "the ticket flag is set")
thanks.onDone()
T.check(doneFired, "the done callback still chains through")

-- YES but short on cash: the decline box also carries the money opt now
-- (Part 1: scripts/Museum1F.asm keeps MONEY_BOX up on the whole exchange)
g = mkGame(20)
clerk(g, nil, nil, function() end)
pushed[1].opts.choice(true)
local broke = pushed[2]
T.check(tostring(broke.text):find("enough money", 1, true) ~= nil,
  "short on cash opens the not-enough-money box")
T.check(broke.opts ~= nil and broke.opts.money ~= nil,
  "the not-enough-money box carries the money opt")
T.eq(broke.opts.money(), 20, "and its closure reads the untouched balance")
T.eq(g.save.money, 20, "money is not spent on the broke path")

-- NO: the come-again box keeps the money opt too
g = mkGame(3000)
clerk(g, nil, nil, function() end)
pushed[1].opts.choice(false)
local decline = pushed[2]
T.check(tostring(decline.text):find("Come again", 1, true) ~= nil,
  "declining opens the come-again box")
T.check(decline.opts ~= nil and decline.opts.money ~= nil,
  "the come-again box carries the money opt")
T.eq(decline.opts.money(), 3000, "and its closure reads the unspent balance")

-- already ticketed: take-your-time only, no money box (a ticket holder
-- is already inside, past the rope)
g = mkGame(3000)
g.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = true
clerk(g, nil, nil, function() end)
T.check(tostring(pushed[1].text):find("Take plenty", 1, true) ~= nil,
  "an existing ticket holder gets the take-your-time line")
T.check(pushed[1].opts == nil, "and no money box on that branch")

T.finish("museum_money_box_bug1335")
