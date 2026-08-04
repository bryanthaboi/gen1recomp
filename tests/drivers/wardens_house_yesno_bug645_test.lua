-- Driver: #645 Warden's House YES/NO.
--
-- WardensHouseWardenText prints Gibberish1, calls YesNoChoice, and answers
-- with Gibberish2 on yes / Gibberish3 on no (scripts/WardensHouse.asm).  The
-- port printed the question and ended the script, so the box just closed.
--
-- Runs the conversation twice against the live script: once answering YES,
-- once walking the cursor down to NO, shooting the YES/NO box and each reply.
--   POKEPORT_DRIVER=tests/drivers/wardens_house_yesno_bug645_test.lua \
--   POKEPORT_SPEED=2 lovec .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- record what the script actually prints, so the log is checkable on its
  -- own and does not depend on reading the shots
  local Commands = require("src.script.Commands")
  local shown = {}
  local origShow = Commands.show_text
  -- forward every argument: the 4th is extraOpts, which is how Commands.ask
  -- passes its `choice` callback -- drop it and the YES/NO box never appears
  Commands.show_text = function(ctx, textId, ...)
    shown[#shown + 1] = textId
    U.log("text:", textId)
    return origShow(ctx, textId, ...)
  end

  local ChoiceBox = require("src.ui.ChoiceBox")
  local function choiceUp()
    local top = game.stack:top()
    return top and getmetatable(top) == ChoiceBox and top or nil
  end

  -- mash A until the YES/NO box is up, then hand it back
  local function talkUntilChoice()
    U.tap(game, "a")
    for _ = 1, 600 do
      local box = choiceUp()
      if box then return box end
      U.tap(game, "a")
      U.wait(3)
    end
    return nil
  end

  local function talkDone()
    for _ = 1, 600 do
      if game.stack:top() == game.overworld then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return false
  end

  -- the warden stands at (2,3); face him from the tile below
  U.teleport(game, "WARDENS_HOUSE", 2, 4, "up")
  -- Lead-in: this is meant to be WATCHED, not just logged.  At SPEED=2 the
  -- driver runs two iterations per rendered frame, so a wait of N is N/120
  -- seconds on screen -- long enough here to find the window before anything
  -- happens.  Every beat below is held the same way.
  U.log("watch now: talking to the WARDEN in 5 seconds")
  U.wait(600)
  U.shot(game, DIR .. "/warden_0_before.png")

  -- ---------------------------------------------------------------- YES
  shown = {}
  local box = talkUntilChoice()
  if not box then
    U.log("FAIL no YES/NO box appeared after the gibberish line")
  else
    U.log("YES/NO box is up, cursor on", box.index == 1 and "YES" or "NO")
    U.wait(360) -- hold the box on screen for 3s
    U.shot(game, DIR .. "/warden_1_yesno_box.png")
    U.tap(game, "a") -- take the default, YES
    U.wait(360)
    U.shot(game, DIR .. "/warden_2_yes_reply.png")
  end
  talkDone()
  U.log("YES branch printed:", table.concat(shown, ","))
  U.log("now the same conversation again, answering NO")
  U.wait(360)

  -- ----------------------------------------------------------------- NO
  shown = {}
  box = talkUntilChoice()
  if not box then
    U.log("FAIL no YES/NO box on the second talk")
  else
    U.wait(240)
    U.tap(game, "down") -- walk the cursor onto NO, on screen
    U.wait(360)
    U.log("cursor now on", box.index == 1 and "YES" or "NO")
    U.shot(game, DIR .. "/warden_3_yesno_on_no.png")
    U.tap(game, "a")
    U.wait(360)
    U.shot(game, DIR .. "/warden_4_no_reply.png")
  end
  talkDone()
  U.log("NO branch printed:", table.concat(shown, ","))

  U.wait(360)
  Commands.show_text = origShow
end
