-- The Pewter museum ticket clerk dispatches on the player's coordinates
-- before it looks at the ticket flag (#1690).  scripts/Museum1F.asm:45
-- reads wYCoord/wXCoord first: (13,4) and (12,3) are behind the counter
-- (the AMBER question), Y==4 otherwise is the ticket path, and anything
-- else is the "go to the other side" brush-off.  The port only ever had
-- the middle branch, so two thirds of the NPC never fired.
--
-- tests/engine/museum_money_box_bug1335.lua and museum_1f_clerk_
-- translation_test.lua both call the clerk with ow == nil, which stays on
-- the ticket path either way, so neither can see the coordinate branches.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

package.loaded["src.render.TextBox"] = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
}

local M = assert(loadfile("data/scripts/story2.lua"))()
local clerk = M.MUSEUM_1F.talk.TEXT_MUSEUM1F_SCIENTIST1

-- data/maps/objects/Museum1F.asm: MUSEUM1F_SCIENTIST1 stands at (12,4)
-- with the counter column at x==11.  (13,4) is the cell east of him and
-- (12,3) the cell north of him, both reachable only from the back door;
-- (10,4) talks to him across the counter from the public side.
local BEHIND = { { 13, 4 }, { 12, 3 } }
local FRONT = { 10, 4 }

local pushed
local function mkGame(cash)
  pushed = {}
  return {
    data = { text = {} },
    save = { money = cash, flags = {} },
    stack = { push = function(_, box) pushed[#pushed + 1] = box end },
  }
end

local function mkOw(x, y)
  return { player = { cellX = x, cellY = y } }
end

-- nil-tolerant: a branch that pushes nothing at all is a failure to
-- report, not a crash that hides every check after it
local function has(box, needle)
  return box ~= nil and tostring(box.text):find(needle, 1, true) ~= nil
end

-- answering a box that never offered a choice is the failure mode itself,
-- so report it rather than dying on a nil index and hiding the rest
local function answer(box, yes)
  if box and box.opts and box.opts.choice then box.opts.choice(yes) end
end

-- ------------------------------------------------ behind the counter
for _, cell in ipairs(BEHIND) do
  local where = ("(%d,%d)"):format(cell[1], cell[2])

  local g = mkGame(3000)
  clerk(g, mkOw(cell[1], cell[2]), nil, function() end)
  local ask = pushed[1]
  T.check(has(ask, "sneak"),
    where .. " opens the can't-sneak-in-the-back-way box")
  T.check(ask.opts ~= nil and ask.opts.choice ~= nil,
    where .. " carries the AMBER yes/no choice")
  T.check(ask.opts.money == nil,
    where .. " raises no money window behind the AMBER question")
  T.check(ask.onDone == nil, where .. " chains through the choice, not onDone")

  -- YES: .TheresALabSomewhereText
  answer(ask, true)
  T.check(has(pushed[2], "lab"), where .. " YES gives the resurrection lab line")

  -- NO: .AmberIsFossilizedTreeSapText
  g = mkGame(3000)
  clerk(g, mkOw(cell[1], cell[2]), nil, function() end)
  answer(pushed[1], false)
  T.check(has(pushed[2], "tree sap"), where .. " NO explains AMBER is tree sap")

  T.eq(g.save.money, 3000, where .. " never charges the player")
  T.check(not g.save.flags.EVENT_BOUGHT_MUSEUM_TICKET,
    where .. " never hands out a ticket")
end

-- the coordinate check runs BEFORE the ticket check, so a ticket holder
-- who wanders round the back still gets told off (asm:45 precedes asm:59)
for _, cell in ipairs(BEHIND) do
  local where = ("(%d,%d)"):format(cell[1], cell[2])
  local g = mkGame(3000)
  g.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = true
  clerk(g, mkOw(cell[1], cell[2]), nil, function() end)
  T.check(has(pushed[1], "sneak"),
    where .. " with a ticket is still the back-way box, not take-your-time")
  answer(pushed[1], false)
  T.check(has(pushed[2], "tree sap"),
    where .. " with a ticket still answers NO with the tree sap line")
end

-- the done callback reaches the second box on both answers
local g = mkGame(3000)
local doneFired = false
clerk(g, mkOw(13, 4), nil, function() doneFired = true end)
answer(pushed[1], true)
T.check(pushed[2].onDone ~= nil, "the AMBER answer box carries the done callback")
pushed[2].onDone()
T.check(doneFired, "and it chains back out of the conversation")

-- ------------------------------------------------ the brush-off
-- scripts/Museum1F.asm:58: no ticket and not on row 4 means "other side"
local OFF_ROW = { { 12, 5 }, { 13, 3 }, { 12, 2 }, { 11, 3 } }
for _, cell in ipairs(OFF_ROW) do
  local where = ("(%d,%d)"):format(cell[1], cell[2])
  local gg = mkGame(3000)
  clerk(gg, mkOw(cell[1], cell[2]), nil, function() end)
  T.check(has(pushed[1], "other side"), where .. " gets the brush-off line")
  T.check(pushed[1].opts == nil, where .. " raises no money window")
  T.eq(gg.save.money, 3000, where .. " never charges the player")
end

-- with a ticket, off-row talk falls through to take-your-time instead
-- (asm:59 CheckEvent gates the brush-off)
local g2 = mkGame(3000)
g2.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = true
clerk(g2, mkOw(12, 5), nil, function() end)
T.check(has(pushed[1], "Take your time"),
  "(12,5) with a ticket gets take-your-time, not the brush-off")

-- ------------------------------------------------ the ticket path holds
-- across the counter from the public side is row 4: the money box
local g3 = mkGame(3000)
clerk(g3, mkOw(FRONT[1], FRONT[2]), nil, function() end)
T.check(has(pushed[1], "50"), "(10,4) still opens the child's ticket ask")
T.check(pushed[1].opts ~= nil and pushed[1].opts.money ~= nil,
  "and the ask still raises the money window")
answer(pushed[1], true)
T.eq(g3.save.money, 2950, "buying from the front still costs 50")
T.check(g3.save.flags.EVENT_BOUGHT_MUSEUM_TICKET, "and still sets the ticket flag")

local g4 = mkGame(3000)
g4.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = true
clerk(g4, mkOw(FRONT[1], FRONT[2]), nil, function() end)
T.check(has(pushed[1], "Take your time"),
  "(10,4) with a ticket still gets take-your-time")
T.check(pushed[1].opts == nil, "and no money window on that branch")

-- a caller with no overworld (the two older suites, and any script that
-- talks to the clerk out of band) must keep the pre-#1690 ticket path
local g5 = mkGame(3000)
clerk(g5, nil, nil, function() end)
T.check(has(pushed[1], "50"), "ow == nil still opens the ticket ask")
T.check(pushed[1].opts ~= nil and pushed[1].opts.money ~= nil,
  "ow == nil still raises the money window")

-- ------------------------------------------------ the rope onStep path
-- Museum1FDefaultScript calls the clerk over when the player steps onto
-- (9,4) or (10,4); OverworldController passes the player's own cell, so
-- the brush-off must not swallow the ask there
for _, x in ipairs({ 9, 10 }) do
  local where = ("(%d,4)"):format(x)
  local g6 = mkGame(3000)
  local moved = false
  local ow = mkOw(x, 4)
  ow.scriptMove = function() moved = true end
  local handled = M.MUSEUM_1F.onStep(g6, ow, x, 4)
  T.check(handled, where .. " on the rope is handled by onStep")
  T.check(has(pushed[1], "50"), where .. " on the rope opens the ticket ask")
  T.check(pushed[1].opts ~= nil and pushed[1].opts.money ~= nil,
    where .. " on the rope keeps the money window")
  answer(pushed[1], false)
  T.check(has(pushed[2], "Come again"), where .. " declining says come again")
  pushed[2].onDone()
  T.check(moved, where .. " declining still shoves the player back south (#151)")
end

-- a ticket holder walking the rope is not stopped at all
local g7 = mkGame(3000)
g7.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = true
local ow7 = mkOw(9, 4)
ow7.scriptMove = function() end
T.check(not M.MUSEUM_1F.onStep(g7, ow7, 9, 4),
  "a ticket holder crosses the rope without being stopped")
T.eq(#pushed, 0, "and no box is pushed")

-- ------------------------------------------------ translation reaches it
-- the two new branches must read game.data.text, not bare literals
local TRANSLATED = {
  _Museum1FScientist1DoYouKnowWhatAmberIsText = "Pas par derriere !\nL'AMBRE, tu connais ?",
  _Museum1FScientist1TheresALabSomewhereText = "Un labo essaie de\nles ressusciter.",
  _Museum1FScientist1AmberIsFossilizedTreeSapText = "C'est de la resine\nfossilisee.",
  _Museum1FScientist1GoToOtherSideText = "Passe de l'autre\ncote !",
}
local function mkTranslated()
  pushed = {}
  return {
    data = { text = TRANSLATED },
    save = { money = 3000, flags = {} },
    stack = { push = function(_, box) pushed[#pushed + 1] = box end },
  }
end

local g8 = mkTranslated()
clerk(g8, mkOw(13, 4), nil, function() end)
T.eq(pushed[1].text, TRANSLATED._Museum1FScientist1DoYouKnowWhatAmberIsText,
  "the back-way box uses the translated AMBER question")
answer(pushed[1], true)
T.eq(pushed[2].text, TRANSLATED._Museum1FScientist1TheresALabSomewhereText,
  "YES uses the translated lab line")

g8 = mkTranslated()
clerk(g8, mkOw(12, 3), nil, function() end)
answer(pushed[1], false)
T.eq(pushed[2].text, TRANSLATED._Museum1FScientist1AmberIsFossilizedTreeSapText,
  "NO uses the translated tree sap line")

g8 = mkTranslated()
clerk(g8, mkOw(12, 5), nil, function() end)
T.eq(pushed[1].text, TRANSLATED._Museum1FScientist1GoToOtherSideText,
  "the brush-off uses the translated other-side line")

T.finish("museum_clerk_back_entrance_bug1690")
