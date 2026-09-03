-- ../pokecrystal/engine/menus/save.asm:40 ChangeBoxSaveGame
-- ../pokecrystal/data/text/common_3.asm:219 _ChangeBoxSaveText
-- ../pokecrystal/home/print_text.asm:1 PrintLetterDelay
local U = require("tests.drivers.util")

local PcMenu = require("src.ui.gen2.PcMenu")
local Typer = require("src.ui.gen2.Typer")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-changebox-text-speed-2143"
  local failed = 0

  local function pass(ok, line)
    if not ok then failed = failed + 1 end
    U.log((ok and "PASS " or "FAIL ") .. line)
  end

  local function settle(pc)
    local n = 0
    for _ = 1, 600 do
      if not (pc.typer and not pc.typer:done()) then break end
      U.wait(1)
      n = n + 1
    end
    U.wait(2)
    return n
  end

  U.wait(45)
  assert(game.world and game.world.map, "gen2 world did not boot")

  local Mon = require("src.battle.gen2.Mon")
  if not (game.save.party and #game.save.party > 0) then
    game.save.party = { Mon.new(game.data, "CYNDAQUIL", 10) }
  end
  game.save.options = game.save.options or {}
  local optionSpeed = game.save.options.textSpeed
  game.save.options.textSpeed = "SLOW"

  local function openChangeBox(saveExists)
    local pc = PcMenu.new(game, {
      save = game.save,
      saveExists = saveExists,
      bills = true,
      writer = function() return true end,
      onClose = function() game.stack:pop() end,
    })
    game.stack:push(pc)
    U.wait(3)
    pc.picking = true
    pc.pickIndex = ((game.save.currentBox or 1) % 14) + 1
    pc:beginChangeBox(pc.pickIndex)
    U.wait(1)
    return pc
  end

  local pc = openChangeBox(true)
  pass(pc.savePhase == "confirm" and Typer.typing(pc),
    "CHANGE BOX confirm prompt types letter by letter")
  pass(not pc:saveYesNoVisible(), "no YES/NO while it types")
  U.wait(20)
  U.log("01-confirm-typing: 'When you change a' part way through, no yes/no box")
  U.shot(game, out .. "/01-confirm-typing.png")
  local slowFrames = settle(pc)
  pass(pc.savePage == 1 and #pc:savePages() == 2,
    ("confirm prompt is page 1 of 2 (page %s of %s)"):format(
      tostring(pc.savePage), tostring(#pc:savePages())))
  pass(not pc:saveYesNoVisible(), "no YES/NO on 'When you change a / #MON BOX, data'")
  U.log("02-confirm-page1: 'When you change a / #MON BOX, data' with the arrow")
  U.shot(game, out .. "/02-confirm-page1.png")

  U.tap(game, "a")
  U.wait(1)
  pass(pc.savePhase == "confirm" and pc.savePage == 2,
    "A on the arrow turns to the cont page without answering")
  pass(Typer.typing(pc), "and the cont line types")
  U.wait(12)
  U.log("03-confirm-cont-typing: '#MON BOX, data' whole, 'will be saved. OK?' part way")
  U.shot(game, out .. "/03-confirm-cont-typing.png")
  settle(pc)
  pass(pc:saveYesNoVisible(), "YES/NO goes up once 'will be saved. OK?' has printed")
  U.log("04-confirm-page2: '#MON BOX, data / will be saved. OK?' with YES/NO at (14,7)")
  U.shot(game, out .. "/04-confirm-page2.png")

  U.tap(game, "b")
  U.wait(3)
  pass(pc.savePhase == nil and pc.picking and pc.typer == nil,
    "B on the YES/NO is NO and keeps the box picker")
  U.tap(game, "b")
  U.wait(3)
  U.tap(game, "b")
  U.wait(5)

  game.save.options.textSpeed = "FAST"
  pc = openChangeBox(false)
  local fastFrames = settle(pc)
  pass(fastFrames < slowFrames,
    ("the OPTIONS text speed drives the prompt (FAST %d frames < SLOW %d)"):format(
      fastFrames, slowFrames))
  U.tap(game, "a")
  U.wait(1)
  settle(pc)
  pass(pc:saveYesNoVisible(), "YES/NO up on the cont page at FAST")
  U.tap(game, "a")
  U.wait(1)
  pass(pc.savePhase == "saving", "YES with no save file goes straight to SAVING")
  pass(pc.typer and pc.typer.speed == "MID" and Typer.typing(pc),
    "SAVING… DON'T TURN OFF THE POWER. types at MID even with FAST set")
  U.wait(15)
  U.log("05-saving-typing: 'SAVING… DON'T TURN' part way through")
  U.shot(game, out .. "/05-saving-typing.png")
  local savingFrames = settle(pc)
  pass(savingFrames > fastFrames, ("SAVING… took %d frames at MID, the FAST prompt %d"):format(
    savingFrames, fastFrames))
  for _ = 1, 60 do
    if pc.savePhase == "done" then break end
    U.wait(1)
  end
  pass(pc.savePhase == "done", "the write lands after the 16-frame hold")
  pass(pc.typer and pc.typer.speed == "MID" and Typer.typing(pc),
    "'<PLAYER> saved the game.' types at MID too")
  U.wait(10)
  U.log("06-saved-typing: '<PLAYER> saved' part way through")
  U.shot(game, out .. "/06-saved-typing.png")
  settle(pc)
  U.shot(game, out .. "/07-saved.png")
  for _ = 1, 120 do
    if pc.savePhase == nil then break end
    U.wait(1)
  end
  pass(pc.savePhase == nil and not pc.picking and pc.typer == nil,
    "the saved message clears back to the PC menu")
  U.tap(game, "b")
  U.wait(5)

  game.save.options.textSpeed = optionSpeed

  U.log(("%d check(s) failed"):format(failed))
  U.log((failed == 0 and "PASS" or "FAIL") .. " gen2 CHANGE BOX text speed (#2143) shots in " .. out)

  while true do coroutine.yield() end
end
