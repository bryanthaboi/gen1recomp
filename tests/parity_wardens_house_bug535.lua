-- Regression (#535): after handing over the GOLD TEETH and receiving
-- HM04, every later talk to the Warden must still say something.
--
-- data/scripts/story.lua's TEXT_WARDENSHOUSE_WARDEN pointed the
-- EVENT_GOT_HM04 branch (row 3, jump_if_true) at the same silent-end jump
-- the give-then-thank fallthrough uses (row 13), so ScriptRunner's pc ran
-- straight past the end of the row list with zero show_text calls -- the
-- Warden went mute on every visit after the trade. pokered's .got_item
-- branch (scripts/WardensHouse.asm) instead prints .HM04ExplanationText
-- (text/WardensHouse.asm: "HM04 teaches STRENGTH ... SECRET HOUSE in
-- SAFARI ZONE") on every subsequent talk.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity wardens house (#535)")
local check, eq = S.check, S.eq

local Commands = require("src.script.Commands")
local Flags = require("src.script.Flags")
local Game = require("src.core.Game")
local Input = require("src.core.Input")
local SaveData = require("src.core.SaveData")
local ScriptRunner = require("src.script.ScriptRunner")
local StateStack = require("src.core.StateStack")

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
require("src.render.Font").load(Data)

local story = require("data.scripts.story")
local script = story.WARDENS_HOUSE.talk.TEXT_WARDENSHOUSE_WARDEN

-- instrument show_text the way parity_gift_atomicity.lua does, to record
-- exactly which text ids actually printed
local shown = {}
-- forward EVERY argument: the 4th is extraOpts, which is how Commands.ask
-- hands down its `choice` callback.  A wrapper that stops at `subs` silently
-- turns every ask in the script back into a plain show_text -- no YES/NO box,
-- and ctx.lastCheck left holding whatever the previous check_* put there.
local origShow = Commands.show_text
Commands.show_text = function(ctx, textId, ...)
  shown[#shown + 1] = textId
  return origShow(ctx, textId, ...)
end

-- `button` drives the whole conversation: both A and B page a text box, and
-- on the YES/NO box A takes the cursor's default (YES) while B snaps to NO
-- and answers false (ChoiceBox:update, .choseSecondMenuItem).  So holding A
-- runs the yes branch and holding B runs the no branch, with no reaching
-- into the choice box from the test.
local function runScript(button)
  shown = {}
  StateStack:init()
  local ow = { map = { id = "WARDENS_HOUSE", def = { label = "WardensHouse" } },
               npcs = {}, entities = {} }
  local r = ScriptRunner.new(Game, ow)
  r:run(script, { npc = { def = {}, facePlayer = function() end },
                  overworld = ow })
  local guard = 0
  while r:isRunning() and guard < 3000 do
    guard = guard + 1
    Input.pressed = { [button or "a"] = true }
    StateStack:update(1 / 60)
    r:update()
  end
  Input.pressed = {}
  return not r:isRunning()
end

-- === 1) first talk, holding the GOLD TEETH: gives HM04, sets the flag ===
Game.save = SaveData.newGame()
Game.save.inventory.GOLD_TEETH = 1
check(runScript(), "give-the-teeth talk completes")
eq(table.concat(shown, ","),
   "_WardensHouseWardenGaveTheGoldTeethText,_WardensHouseWardenThanksText,"
   .. "_WardensHouseWardenReceivedHM04Text",
   "handing over the teeth shows the give/thanks/received sequence, nothing after")
check(Flags.get(Game.save, "EVENT_GOT_HM04"), "EVENT_GOT_HM04 is set")
check(Flags.get(Game.save, "EVENT_GAVE_GOLD_TEETH"), "EVENT_GAVE_GOLD_TEETH is set")
check(Game.save.inventory.HM_STRENGTH ~= nil, "HM04 (Strength) lands in the bag")
check(not Game.save.inventory.GOLD_TEETH, "the GOLD TEETH is taken")

-- === 2) the regression itself: every later talk, once EVENT_GOT_HM04 is
--        set, must print the explanation text instead of nothing ===
check(runScript(), "post-gift talk completes")
eq(table.concat(shown, ","), "_WardensHouseWardenHM04ExplanationText",
   "every subsequent talk now prints the HM04/Safari Zone explanation (#535)")

-- run it again to confirm this is not a one-shot: it repeats every visit
check(runScript(), "a third talk completes")
eq(table.concat(shown, ","), "_WardensHouseWardenHM04ExplanationText",
   "the explanation text repeats on every later talk, not just the first")

-- === 3) no GOLD TEETH yet: the gibberish question, then a YES/NO, then the
--        warden's answer -- Gibberish2 on yes, Gibberish3 on no (#645).
--        The port used to stop dead after the question. ===
Game.save = SaveData.newGame()
check(runScript("a"), "empty-handed talk completes on yes")
eq(table.concat(shown, ","),
   "_WardensHouseWardenGibberish1Text,_WardensHouseWardenGibberish2Text",
   "answering YES gets the warden's reply, not silence (#645)")
check(not Flags.get(Game.save, "EVENT_GOT_HM04"), "no HM04 yet")

Game.save = SaveData.newGame()
check(runScript("b"), "empty-handed talk completes on no")
eq(table.concat(shown, ","),
   "_WardensHouseWardenGibberish1Text,_WardensHouseWardenGibberish3Text",
   "and answering NO gets the other reply (#645)")

-- the question is asked, not just printed: `ask` is what puts the YES/NO box
-- up, so a future edit that downgrades it back to show_text fails here
local askRow
for _, row in ipairs(script) do
  if row[2] == "_WardensHouseWardenGibberish1Text" then askRow = row[1] end
end
eq(askRow, "ask", "the gibberish line is asked with a YES/NO, not just shown")

-- neither answer touches the teeth trade
check(not Flags.get(Game.save, "EVENT_GAVE_GOLD_TEETH"),
      "and neither answer hands over teeth the player does not have")

Commands.show_text = origShow

S.finish()
