-- Parity (#552): the Game Corner coin clerk asks before he sells.
--
-- Oracle: scripts/GameCorner.asm GameCornerClerk1Text -- the offer, a
-- YesNoChoice, then ¥1000 off the wallet for 50 coins, with the COIN CASE
-- and Has9990Coins gates in between.  Yellow spells the same object and
-- the same six text labels without the "1" (GameCornerClerkText,
-- pokeyellow/scripts/GameCorner.asm), so the Red/Blue text id never
-- matched there: the clerk fell through to his extracted offer line with
-- no prompt behind it, and no coins ever changed hands.
--
-- Drives the real StateStack and Input, so the YES/NO box under test is
-- the one the player sees rather than a stand-in.
--
-- Self-contained: `luajit tests/parity_game_corner_clerk_bug552.lua`; also
-- globbed by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity game corner clerk (#552)")
local check, eq = S.check, S.eq

local ChoiceBox = require("src.ui.ChoiceBox")
local Game = require("src.core.Game")
local Input = require("src.core.Input")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local TextBox = require("src.render.TextBox")
local mapScripts = require("data.scripts.init")

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
require("src.render.Font").load(Data)

local red = mapScripts.talkScript("GAME_CORNER", "TEXT_GAMECORNER_CLERK1")
local yellow = mapScripts.talkScript("GAME_CORNER", "TEXT_GAMECORNER_CLERK")
check(type(red) == "function", "the Red/Blue clerk has a hand-ported handler")
check(yellow == red,
      "Yellow's TEXT_GAMECORNER_CLERK resolves to the same handler (#552)")

-- record what each box was built with; the handler resolves its labels at
-- call time, so wrapping .new sees exactly the string that reached the box
local shown = {}
local realNew = TextBox.new
TextBox.new = function(game, text, onDone, opts)
  shown[#shown + 1] = text
  return realNew(game, text, onDone, opts)
end

local sawChoice = false

-- One conversation, start to finish.  `answer` is which row of the YES/NO
-- box to take; the loop mashes A the way a player does and nudges the
-- cursor down once when the choice box comes up.  The MONEY/COIN box is a
-- plain draw-only table under the text boxes (#624), so it is the one
-- stack entry with a draw and no metatable.
local function talk(save, answer)
  Game.save = save
  StateStack:init()
  shown, sawChoice = {}, false
  local sawCoinBox = false
  local done = false
  local ow = { map = { id = "GAME_CORNER", def = Data.maps.GAME_CORNER },
               npcs = {}, entities = {} }
  yellow(Game, ow, { def = {} }, function() done = true end)

  local moved = false
  for _ = 1, 2000 do
    local top = StateStack:top()
    if not top then break end
    for _, state in ipairs(StateStack.states) do
      if type(state.draw) == "function" and getmetatable(state) == nil then
        sawCoinBox = true
      end
    end
    if getmetatable(top) == ChoiceBox then
      sawChoice = true
      if answer == "no" and not moved then
        moved = true
        Input.pressed = { down = true }
      else
        Input.pressed = { a = true }
      end
    else
      Input.pressed = { a = true }
    end
    StateStack:update(1 / 60)
  end
  Input.pressed = {}
  return done, sawCoinBox
end

local function newSave(money, coins, caseToo)
  local save = SaveData.newGame()
  save.money = money
  save.coins = coins
  if caseToo ~= false then save.inventory.COIN_CASE = 1 end
  return save
end

local function said(fragment)
  for _, text in ipairs(shown) do
    if type(text) == "string" and text:find(fragment, 1, true) then return true end
  end
  return false
end

-- ------------------------------------------------------- the sale itself
do
  local save = newSave(1000, 0)
  local finished, sawCoinBox = talk(save, "yes")
  check(finished, "the buy conversation runs to the end")
  check(sawChoice, "the clerk opens a real YES/NO box, not just a line (#552)")
  check(sawCoinBox, "the MONEY/COIN box rides the exchange (#624)")
  eq(#shown, 2, "two boxes: the offer and the receipt")
  check(said("¥1000 for 50"), "the offer quotes ¥1000 for 50 coins")
  eq(save.money, 0, "¥1000 leaves the wallet")
  eq(save.coins, 50, "50 coins land in the case")
  check(not said("COINS: 50"),
    "the receipt skips the coin tally; the coin box already shows it")
end

-- ---------------------------------------------------------------- saying no
do
  local save = newSave(1000, 0)
  check(talk(save, "no"), "declining runs to the end")
  check(sawChoice, "NO is a choice the player actually makes")
  check(said("play sometime"), "he sees you out with the come-play-sometime line")
  eq(save.money, 1000, "declining costs nothing")
  eq(save.coins, 0, "and buys nothing")
end

-- ------------------------------------------------------------- the gates
do
  local save = newSave(999, 0)
  talk(save, "yes")
  check(said("afford"), "under ¥1000 he says you can't afford it")
  eq(save.money, 999, "and takes nothing")
  eq(save.coins, 0, "and gives nothing")
end

do
  local save = newSave(1000, 9990)
  talk(save, "yes")
  check(said("full"), "a case at 9990 coins is full (Has9990Coins)")
  eq(save.money, 1000, "a full case costs nothing")
  eq(save.coins, 9990, "and adds nothing")
end

do
  local save = newSave(1000, 0, false)
  talk(save, "yes")
  check(said("COIN CASE"), "no COIN CASE, no sale")
  eq(save.money, 1000, "and no money changes hands")
end

-- ------------------------------------------------- Yellow's label spelling
-- Yellow's six labels drop the "1" and the port falls back to them, so a
-- Yellow cache reaches the same prompt.  Swap the cache's strings to the
-- Yellow spelling to prove the fallback is the one doing the work.
do
  local SUFFIXES = {
    "DoYouNeedSomeGameCoinsText", "ThanksHereAre50CoinsText",
    "PleaseComePlaySometimeText", "CantAffordTheCoinsText",
    "CoinCaseIsFullText", "DontHaveCoinCaseText",
  }
  local saved = {}
  for _, suffix in ipairs(SUFFIXES) do
    saved[suffix] = Data.text["_GameCornerClerk1" .. suffix]
    Data.text["_GameCornerClerk" .. suffix] =
      "YELLOW " .. suffix .. "\n¥1000 for 50."
    Data.text["_GameCornerClerk1" .. suffix] = nil
  end

  local save = newSave(1000, 0)
  check(talk(save, "yes"), "the Yellow-spelled clerk runs to the end")
  check(sawChoice, "and still opens the YES/NO box")
  check(said("YELLOW DoYouNeedSomeGameCoinsText"),
        "the offer comes from _GameCornerClerkDoYouNeedSomeGameCoinsText")
  check(said("YELLOW ThanksHereAre50CoinsText"),
        "so does the receipt")
  eq(save.money, 0, "Yellow's clerk takes the ¥1000")
  eq(save.coins, 50, "and hands over the 50 coins")

  for _, suffix in ipairs(SUFFIXES) do
    Data.text["_GameCornerClerk1" .. suffix] = saved[suffix]
    Data.text["_GameCornerClerk" .. suffix] = nil
  end
end

TextBox.new = realNew
S.finish()
