-- Driver: regression coverage for #218 "Blue mentions Oak being absent".
--
-- TEXT_OAKSLAB_RIVAL (data/scripts/oaks_lab.lua) picks the pre-starter line.
-- pret/pokered scripts/OaksLab.asm gates that line on EVENT_FOLLOWED_OAK_INTO_LAB:
--   * flag CLEAR (Oak has not escorted you in yet) -> "Yo {PLAYER}! Gramps
--     isn't around!"  (_OaksLabRivalGrampsIsntAroundText)
--   * flag SET (Oak present, three balls on the table) -> "Heh, I don't need
--     to be greedy... Go ahead and choose, {PLAYER}!"  (_OaksLabRivalGoAheadAndChooseText)
-- The buggy handler jumped straight to GrampsIsntAround for any no-starter
-- state, so the rival wrongly claimed Oak was gone while Oak stood in the lab.
--
-- We read the RAW text handed to TextBox.new (before pagination and {PLAYER}/
-- {RIVAL} substitution) so the distinctive words "greedy"/"Gramps" survive.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- Capture the raw text the next TextBox is built with.
  local TextBox = require("src.render.TextBox")
  local origNew = TextBox.new
  local lastText
  TextBox.new = function(g, text, ...)
    lastText = text
    return origNew(g, text, ...)
  end

  -- fresh overworld in Oak's lab, player standing one cell right of the
  -- rival (object 1 at cell 4,3) and facing him.
  local function setup(followed)
    U.teleport(game, "OAKS_LAB", 5, 3, "left")
    local flags = game.save.flags or {}
    game.save.flags = flags
    flags.EVENT_FOLLOWED_OAK_INTO_LAB = followed or nil
    flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = followed or nil
    flags.EVENT_GOT_STARTER = nil
    flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = nil
    U.wait(6)
  end

  -- face the rival and press A until his text box opens (lastText set).
  local function talkToRival()
    lastText = nil
    U.tap(game, "left"); U.wait(2)
    for _ = 1, 5 do
      U.tap(game, "a")
      for _ = 1, 60 do
        if lastText then return end
        U.wait(1)
      end
    end
  end

  -- close any open text box before the next scenario.
  local function dismiss()
    for _ = 1, 20 do U.tap(game, "a"); U.wait(2) end
  end

  -- ---- Scenario A: Oak has escorted the player in, no starter chosen.
  --      Correct Gen1 line: the greedy / "go ahead and choose" taunt.
  setup(true)
  U.shot(game, DIR .. "/a_before.png")
  talkToRival()
  U.wait(20)
  U.shot(game, DIR .. "/a_after.png")
  local aText = lastText or "<none>"
  local aPass = (aText:find("greedy") ~= nil) and (aText:find("Gramps") == nil)
  U.log("SCENARIO A (FOLLOWED_OAK set) text:", aText)
  U.log("SCENARIO A", aPass and "PASS" or "FAIL")

  dismiss()

  -- ---- Scenario B: very early game, Oak has not walked you in yet.
  --      Correct Gen1 line: "Gramps isn't around".  Guards the appended
  --      jump_if_false path so the fix keeps the true-early-game text.
  setup(false)
  talkToRival()
  U.wait(20)
  U.shot(game, DIR .. "/b_after.png")
  local bText = lastText or "<none>"
  local bPass = (bText:find("Gramps") ~= nil)
  U.log("SCENARIO B (FOLLOWED_OAK clear) text:", bText)
  U.log("SCENARIO B", bPass and "PASS" or "FAIL")

  -- restore before any assert so a failure can't leave the hook installed
  TextBox.new = origNew

  U.log("RESULT bug218", (aPass and bPass) and "PASS" or "FAIL")
  assert(aPass,
    "Scenario A: rival must give the greedy/choose line while Oak is in the lab, got: " .. aText)
  assert(bPass,
    "Scenario B: rival must say Gramps isn't around before Oak escorts you, got: " .. bText)
end
