-- Driver: the trainer-battle run refusal prints its third line (#239).
-- A manual eye check, not a pass/fail run.
--
-- pokered evidence.  The string is three lines wide in a two-line box, and
-- data/generated/text.lua keeps the original's markers:
--
--   _NoRunningText = "No! There's no\nrunning from a\011trainer battle!"
--
-- \011 is \v, which src/render/TextBox.lua treats as ContText: show the
-- down-arrow, wait for a button, then scroll the third line in.  The port
-- had hard-coded the same words with three \n instead, so all three lines
-- were queued onto a page that only shows two, "trainer battle!" was never
-- reached, and the command menu came straight back.
--
-- The fix reads _NoRunningText from the generated data, with a correctly
-- marked literal as the fallback for an older cache.
--
-- Do NOT run this under POKEPORT_SPEED.  Fast-forward scales only the logic
-- clock while the typewriter runs on its own real-time accumulator
-- (src/core/Game.lua), so the pause being judged here would desynchronize.
--
--   POKEPORT_DRIVER=tests/drivers/trainer_run_bug239_test.lua POKEPORT_IDENTITY=bug239 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local TextBox = require("src.render.TextBox")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot separate from the bug ----------------
  -- A wild battle instead of a trainer one shows no refusal at all, which
  -- is not the same failure as a refusal that truncates.

  local text = game.data.text and game.data.text._NoRunningText
  check("_NoRunningText is in the generated text", type(text) == "string")
  if type(text) == "string" then
    local pages = TextBox.paginate(text)
    check("the refusal is one page of three lines",
          #pages == 1 and #pages[1] == 3)
    check("line 3 waits for a button (\\v, not \\n)",
          pages.contBefore and pages.contBefore[1]
          and pages.contBefore[1][3] == true)
    check("line 3 really is 'trainer battle!'",
          pages[1][3] and pages[1][3]:find("trainer battle!", 1, true) ~= nil)
  end

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.player.name = "bryan"

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)

  -- any trainer class works; the refusal is keyed on kind == "trainer",
  -- not on who the trainer is
  local OPP = "OPP_YOUNGSTER"
  check("trainer class " .. OPP .. " exists in the data",
        game.data.trainers and game.data.trainers[OPP] ~= nil)

  local ok, battle = pcall(BattleState.newTrainer, game, OPP, 1)
  check("trainer battle constructed", ok and battle ~= nil)
  if not ok then
    U.log("could not start", OPP, "->", tostring(battle))
    U.log("pick another class from game.data.trainers and re-run")
  else
    check("battle kind is trainer (wild battles let you run)",
          battle.kind == "trainer")
    game.stack:push(battle)
    U.wait(120) -- let the intro text and the throw settle
  end

  U.log("........................................................")
  U.log("READ NOW: choose RUN from the battle command menu.")
  U.log("  RIGHT: 'No! There's no / running from a' fills the box, it holds")
  U.log("         with a down-arrow until you press a button, and only then")
  U.log("         does 'trainer battle!' scroll in. The command menu comes")
  U.log("         back after that.")
  U.log("  BUG #239 looks like: the box showing the first two lines and the")
  U.log("         command menu snapping straight back, so the sentence ends")
  U.log("         mid-phrase at 'running from a'.")
  U.log("  ALSO WRONG: all three lines appearing at once with no pause (the")
  U.log("         box only holds two, so something is overflowing), or the")
  U.log("         third line arriving on a cleared page (that is \\f, not")
  U.log("         \\v -- the original scrolls, it does not blank the box).")
  U.log("Control case: run from a WILD battle and you should get the escape")
  U.log("  roll instead, with no refusal text at all.")
  U.log("Input is yours from here, so RUN can be re-selected as often as")
  U.log("you like.")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
