-- Parity: the beaten trainer's own loss line prints ON the battle screen,
-- between the pic scrolling back in and the prize money (#282).
-- TrainerBattleVictory (engine/battle/core.asm:915-949) runs TrainerDefeatedText,
-- ScrollTrainerPicAfterBattle, PrintEndBattleText, then MoneyForWinningText.
-- The scroll (scroll_draw_trainer_pic.asm:1-31) rewrites tilemap columns only,
-- so the pokeball row ClearSprites emptied does not come back with the pic.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity trainer victory text")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")

Sound.playCry = function() end
Sound.play = function() end
Sound.playMove = function() end
Sound.playMoveCry = function() end
Sound.stopLoop = function() end
Music.playBattle = function() end
Music.play = function() end

local press = {}
local function makeGame(party)
  local save = SaveData.newGame()
  save.party = party
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  -- isDown as well as wasPressed: battle text collapses PrintLetterDelay
  -- while A or B is held, and the typing path reads it every frame
  return { data = Data, save = save, stack = stack,
           input = { wasPressed = function(_, b) return press[b] == true end,
                     isDown = function(_, b) return press[b] == true end } }
end

-- A held: updateQueue only reads the button once a page is typed out, so an
-- early press is ignored and the queue drains at a player's pace.
local function step(battle)
  press.a = true
  battle:update(1 / 60)
  press.a = false
end

-- Fight a YOUNGSTER, wipe its party, and record every message row in the order
-- it reached the screen plus what the foe's pic slot was doing at the time.
local function fightAndWin(endBattleText)
  local game = makeGame({ Pokemon.new(Data, "BULBASAUR", 60) })
  local battle = BattleState.newTrainer(game, "OPP_YOUNGSTER", 1)
  battle.endBattleText = endBattleText
  local result, resultAt
  battle.onFinish = function(r) result = r end
  battle:enter()
  for _ = 1, 500 do
    step(battle)
    if battle.phase == "menu" then break end
  end

  -- the KO itself, through the real faint path (onFaint queues the slide,
  -- the faint text and the enemyMonFainted act)
  for _, mon in ipairs(battle.enemyParty) do mon.hp = 0 end
  battle.enemy.mon.hp = 0
  battle.phase = "messages"
  battle.nextInsert = 0
  battle:onFaint(battle.enemy)

  local pages, foeOffAt, foeShownAt = {}, {}, {}
  local ballRowsSeen, frame, foeMax, foeSteps = 0, 0, 0, 0
  local realRow = battle.drawBallRow
  battle.drawBallRow = function() ballRowsSeen = ballRowsSeen + 1 end
  local lastOff = battle:picOffset("foe")
  for f = 1, 2000 do
    frame = f
    step(battle)
    local cur = battle.current
    local text = cur and cur.text
    if text and pages[#pages] ~= text then
      pages[#pages + 1] = text
      foeOffAt[text] = battle:picOffset("foe")
      foeShownAt[text] = battle.showEnemyTrainer and true or false
    end
    local off = battle:picOffset("foe")
    if off > foeMax then foeMax = off end
    -- count only the inward frames; the jump from 0 to 64 is the program
    -- being armed off-screen, not a step of the scroll
    if off < lastOff then foeSteps = foeSteps + 1 end
    lastOff = off
    -- drawHUDs is the only place a ball row can come from; sample it while
    -- the beaten trainer is back on screen
    if battle.showEnemyTrainer then pcall(battle.drawHUDs, battle, 0) end
    if result then resultAt = f break end
  end
  battle.drawBallRow = realRow
  return {
    battle = battle, pages = pages, result = result, resultAt = resultAt,
    foeOffAt = foeOffAt, foeShownAt = foeShownAt, ballRowsSeen = ballRowsSeen,
    frames = frame, foeMax = foeMax, foeSteps = foeSteps,
  }
end

local function indexOf(pages, fragment)
  for i, p in ipairs(pages) do
    if p:find(fragment, 1, true) then return i end
  end
  return nil
end

-- ------------------------------------------------- the full victory order
local LOSS = "What a total\nwaste of time!"
local run = fightAndWin(LOSS)

eq(run.result, "win", "the battle resolves as a win")
local defeated = indexOf(run.pages, "defeated")
local loss = indexOf(run.pages, "waste of time")
local money = indexOf(run.pages, "for winning")
check(defeated ~= nil, "TrainerDefeatedText prints (\"RED defeated YOUNGSTER!\")")
check(loss ~= nil,
      "the trainer's own EndBattleText prints INSIDE the battle (#282)")
check(money ~= nil, "MoneyForWinningText prints")
check(defeated and loss and defeated < loss,
      "the defeat line comes before the trainer's loss line")
check(loss and money and loss < money,
      "PrintEndBattleText comes before MoneyForWinningText (core.asm:942-949)")
check(money == #run.pages,
      "the prize money is the LAST thing on the battle screen")

-- the pic is back, at rest, with no ball row beside it
if loss then
  local text = run.pages[loss]
  eq(run.foeShownAt[text], true,
     "the beaten trainer's pic is on screen for his loss line")
  eq(run.foeOffAt[text], 16,
     "the pic has come to rest two tiles right of the battle slot "
     .. "(_ScrollTrainerPicAfterBattle ends at hlcoord 14,0)")
end
eq(run.ballRowsSeen, 0,
   "no pokeball row comes back with the pic (ClearSprites emptied that OAM; "
   .. "_ScrollTrainerPicAfterBattle only rewrites tilemap columns)")
eq(run.battle.introBalls, nil, "the DrawAllPokeballs window stays closed")

-- The pic is on screen well before the LAST page: the plain act() this used to
-- ride appended to the end of the queue, so the trainer flashed up one row
-- before finish() popped the battle.
if money then
  eq(run.foeShownAt[run.pages[money]], true,
     "the trainer's pic is already back for the money line, not flashed up "
     .. "one row before the battle pops (#282)")
end

-- and it really scrolls rather than popping into place: 64px off the right
-- edge, then 2px a frame down to the resting 16
eq(run.foeMax, 64, "the scroll-in starts 8 tiles off the right edge")
eq(run.foeSteps, 24,
   "it takes 24 frames to walk in (six 4-frame columns, "
   .. "scroll_draw_trainer_pic.asm:1-31)")

-- ------------------------------------------------------ ordering vs onFinish
-- finish() pops the battle, so anything the overworld pushes afterwards is a
-- second screen cut.  Every trainer-victory row must be consumed before it.
check(run.resultAt ~= nil and run.resultAt >= run.frames,
      "onFinish fires only once the whole sequence has drained")

-- ------------------------------------------------------------- \f pages
-- Five EndBattleTexts carry a `para` (e.g. _Route9Youngster1EndBattleText).
-- BattleState:startMessage only splits \n and \v, so an unsplit \f would
-- render as a garbage glyph instead of starting a new page.
local para = fightAndWin("Oh well.\fI give up!")
check(indexOf(para.pages, "Oh well.") ~= nil,
      "a \\f EndBattleText prints its first page")
check(indexOf(para.pages, "I give up!") ~= nil,
      "a \\f EndBattleText prints its second page")
local p1, p2 = indexOf(para.pages, "Oh well."), indexOf(para.pages, "I give up!")
check(p1 and p2 and p2 == p1 + 1, "the two pages are consecutive rows")
for _, page in ipairs(para.pages) do
  check(page:find("\f", 1, true) == nil,
        "no page still carries a raw \\f: " .. (page:gsub("\n", " / ")))
end

-- --------------------------------------------------- scripted battles
-- Commands.start_battle never sets endBattleText; those scripts print their
-- own follow-up, so the sequence must simply skip the row.
local none = fightAndWin(nil)
eq(none.result, "win", "a battle with no EndBattleText still resolves")
local d2, m2 = indexOf(none.pages, "defeated"), indexOf(none.pages, "for winning")
check(d2 and m2 and d2 < m2,
      "defeat text then money, with nothing between them")
eq(m2, #none.pages, "the prize money is still last")

S.finish()
