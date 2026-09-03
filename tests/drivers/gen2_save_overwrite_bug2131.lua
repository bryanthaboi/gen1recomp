-- ../pokecrystal/engine/menus/save.asm:209 SaveTheGame_yesorno
-- ../pokecrystal/data/text/common_3.asm:202 _AlreadyASaveFileText
local U = require("tests.drivers.util")

local SaveMenu = require("src.ui.gen2.SaveMenu")
local PcMenu = require("src.ui.gen2.PcMenu")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-save-overwrite-2131"
  local failed = 0

  local function pass(ok, line)
    if not ok then failed = failed + 1 end
    U.log((ok and "PASS " or "FAIL ") .. line)
  end

  local function settle(menu)
    for _ = 1, 600 do
      if menu.typer and menu.typedPhase == menu.phase and menu.typer:done() then break end
      U.wait(1)
    end
    U.wait(2)
  end

  U.wait(45)
  assert(game.world and game.world.map, "gen2 world did not boot")

  local closed = false
  local menu = SaveMenu.new(game, {
    existed = true,
    writer = function() return true end,
    onDone = function()
      closed = true
      game.stack:pop()
    end,
  })
  game.stack:push(menu)
  settle(menu)
  pass(menu:yesNoVisible(), "confirm YES/NO is up after the question")
  U.shot(game, out .. "/01-confirm.png")

  U.tap(game, "a")
  U.wait(2)
  pass(menu.phase == "overwrite", "YES on an existing file opens the overwrite prompt")
  settle(menu)
  pass(menu.page == 1 and #menu.pages == 2,
    ("overwrite prompt is on page 1 of 2 (page %s of %s)"):format(
      tostring(menu.page), tostring(menu.pages and #menu.pages)))
  pass(not menu:yesNoVisible(), "no YES/NO while the cont page waits")
  U.log("02-overwrite-page1: 'There is already a / save file. Is it' with the")
  U.log("blinking arrow at the bottom right and NO yes/no box yet.")
  U.shot(game, out .. "/02-overwrite-page1.png")

  U.tap(game, "a")
  U.wait(2)
  pass(menu.page == 2, "A turns to the cont page")
  pass(menu.phase == "overwrite", "without answering the question")
  settle(menu)
  pass(menu:yesNoVisible(), "YES/NO goes up once 'OK to overwrite?' has printed")
  U.log("03-overwrite-page2: 'save file. Is it / OK to overwrite?' with the")
  U.log("YES/NO box at (0,7) over the summary panel, as on the cart.")
  U.shot(game, out .. "/03-overwrite-page2.png")

  U.tap(game, "b")
  U.wait(5)
  pass(closed, "B on the overwrite YES/NO closes without saving")

  local Mon = require("src.battle.gen2.Mon")
  if not (game.save.party and #game.save.party > 0) then
    game.save.party = { Mon.new(game.data, "CYNDAQUIL", 10) }
  end
  local pc = PcMenu.new(game, {
    save = game.save,
    saveExists = true,
    bills = true,
    writer = function() return true end,
    onClose = function() game.stack:pop() end,
  })
  game.stack:push(pc)
  U.wait(3)
  pc.picking = true
  pc.pickIndex = ((game.save.currentBox or 1) % 14) + 1
  pc:beginChangeBox(pc.pickIndex)
  local function settlePc()
    for _ = 1, 600 do
      if not (pc.typer and not pc.typer:done()) then break end
      U.wait(1)
    end
    U.wait(2)
  end
  settlePc()
  pass(pc.savePhase == "confirm" and pc.savePage == 1 and not pc:saveYesNoVisible(),
    "CHANGE BOX asks 'When you change a / #MON BOX, data' with the arrow first")
  U.tap(game, "a")
  U.wait(1)
  settlePc()
  pass(pc.savePhase == "confirm" and pc.savePage == 2 and pc:saveYesNoVisible(),
    "then '#MON BOX, data / will be saved. OK?' with YES/NO up")
  U.shot(game, out .. "/04-changebox-confirm.png")

  U.tap(game, "a")
  U.wait(1)
  pass(pc.savePhase == "overwrite" and pc.savePage == 1,
    "YES on an existing file opens the overwrite prompt on page 1")
  settlePc()
  pass(not pc:saveYesNoVisible(), "no YES/NO while the cont page waits")
  U.log("05-changebox-page1: 'There is already a / save file. Is it', arrow,")
  U.log("no yes/no box.")
  U.shot(game, out .. "/05-changebox-page1.png")

  U.tap(game, "a")
  U.wait(1)
  pass(pc.savePhase == "overwrite" and pc.savePage == 2,
    "A turns to the cont page without answering")
  settlePc()
  pass(pc:saveYesNoVisible(), "YES/NO is up on 'OK to overwrite?'")
  U.log("06-changebox-page2: 'save file. Is it / OK to overwrite?' with the")
  U.log("YES/NO box at (14,7).")
  U.shot(game, out .. "/06-changebox-page2.png")

  U.tap(game, "b")
  U.wait(3)
  pass(pc.savePhase == nil and pc.picking,
    "B on the overwrite YES/NO drops the change and keeps the box picker")
  U.tap(game, "b")
  U.wait(3)
  U.tap(game, "b")
  U.wait(5)

  U.log(("%d check(s) failed"):format(failed))
  U.log((failed == 0 and "PASS" or "FAIL") .. " gen2 save overwrite cont page (#2131) shots in " .. out)

  while true do coroutine.yield() end
end
