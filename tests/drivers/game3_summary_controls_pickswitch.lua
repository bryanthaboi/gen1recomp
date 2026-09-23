local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_summary_controls_pickswitch"

local LARVITAR = 246
local TACKLE, GROWL, ROCK_SMASH = 33, 45, 249

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/summary_controls_pickswitch.log", "a")
  if fh then
    fh:write(line, "\n")
    fh:close()
  end
end

local function result(ok, label)
  say((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    say("PASS summary_controls_pickswitch")
    love.event.quit(0)
  else
    say("FAIL summary_controls_pickswitch failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local RomText = require("src.core.game3.rom_text")
  local SummaryMenu = require("src.ui.game3.summary_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  session.party = {}
  Party.giveMon(session, LARVITAR, 30)
  local mon = session.party[1]
  if not result(mon ~= nil, "a LARVITAR joined the party") then return end
  mon.moves = { TACKLE, GROWL, ROCK_SMASH }
  mon.pp = { 35, 40, 15 }
  mon.maxPp = { 35, 40, 15 }

  local PICK_SWITCH = RomText.plain("gText_PokeSum_Controls_PickSwitch")

  SummaryMenu.openMenu(session.party, 1, {
    mode = "select_move",
    forgetMove = true,
    onSelectMove = function() end,
  })
  U.wait(40)
  result(SummaryMenu.isOpen(), "forget-move summary opened")
  result(SummaryMenu.controlsString(SummaryMenu._page, false) == PICK_SWITCH,
    "forget-move mode shows PickSwitch outside battle")
  U.still(game, DIR .. "/pickswitch_forget_mode.png")
  SummaryMenu.close()
  U.wait(20)

  SummaryMenu.openMenu(session.party, 1, { mode = "party", page = 3 })
  U.wait(40)
  result(SummaryMenu.isOpen(), "party summary opened on the move detail page")
  result(SummaryMenu.controlsString(SummaryMenu._page, false) == PICK_SWITCH,
    "party move detail shows PickSwitch outside battle")
  U.still(game, DIR .. "/pickswitch_party_detail.png")
  SummaryMenu.close()
  U.wait(20)
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL summary_controls_pickswitch driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
