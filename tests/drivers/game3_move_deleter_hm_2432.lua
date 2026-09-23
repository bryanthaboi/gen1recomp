local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_move_deleter_hm_2432"

local HOUSE = "FR_FUCHSIA_CITY_HOUSE3"
local DELETER_X, DELETER_Y = 4, 4
local LARVITAR = 246
local TACKLE, GROWL, ROCK_SMASH = 33, 45, 249

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/move_deleter_hm_2432.log", "a")
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
    say("PASS move_deleter_hm_2432")
    love.event.quit(0)
  else
    say("FAIL move_deleter_hm_2432 failures=" .. failures)
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
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local PartyMenu = require("src.ui.game3.party_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  session.party = {}
  Party.giveMon(session, LARVITAR, 30)
  local mon = session.party[1]
  if not result(mon ~= nil, "a LARVITAR joined the party") then return end
  mon.moves = { TACKLE, GROWL, ROCK_SMASH }
  mon.pp = { 35, 40, 15 }
  mon.maxPp = { 35, 40, 15 }
  result(Pokemon.isHmMove(ROCK_SMASH), "ROCK SMASH is an HM move")
  result(Pokemon.moveSlotCount(mon) == 3, "it knows TACKLE, GROWL, ROCK SMASH")

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end

  Map.load(nil, game, HOUSE, { x = DELETER_X + 1, y = DELETER_Y, facing = "left" })
  Player.cellX, Player.cellY = DELETER_X + 1, DELETER_Y
  Player.px, Player.py = (DELETER_X + 1) * 16, DELETER_Y * 16
  Player.targetX, Player.targetY = DELETER_X + 1, DELETER_Y
  Player.facing = "left"
  if game.session then
    game.session.x, game.session.y, game.session.facing = DELETER_X + 1, DELETER_Y, "left"
  end
  U.wait(90)

  local function pumpUntil(cond, frames)
    for _ = 1, (frames or 300) do
      if cond() then return true end
      if Choice.active or (Message.isWaiting and Message.isWaiting()) then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    return cond() and true or false
  end

  U.tap(game, "a")
  U.wait(24)
  local picker = pumpUntil(function()
    return PartyMenu.isOpen and PartyMenu.isOpen()
  end, 400)
  if not result(picker, "the deleter opened the party picker") then return end
  U.tap(game, "a")
  U.wait(40)

  local summary = pumpUntil(function() return SummaryMenu.isOpen() end, 400)
  if not result(summary, "SelectMoveDeleterMove opened the summary screen") then return end
  U.wait(24)
  result(SummaryMenu._forgetMove == true, "the summary screen is in forget-move mode")

  U.tap(game, "down")
  U.wait(8)
  U.tap(game, "down")
  U.wait(8)
  result(SummaryMenu._moveCursor == 3, "cursor on ROCK SMASH, got " .. tostring(SummaryMenu._moveCursor))
  U.tap(game, "down")
  U.wait(8)
  result(SummaryMenu._moveCursor == 5,
    "down skips the empty 4th slot onto CANCEL, got " .. tostring(SummaryMenu._moveCursor))
  U.wait(16)
  U.still(game, DIR .. "/2432_cancel_row.png")
  U.tap(game, "up")
  U.wait(8)
  result(SummaryMenu._moveCursor == 3,
    "up from CANCEL returns to ROCK SMASH, got " .. tostring(SummaryMenu._moveCursor))
  U.wait(16)
  U.still(game, DIR .. "/2432_rock_smash_selected.png")

  U.tap(game, "a")
  U.wait(30)
  result(SummaryMenu._hmNotice ~= true, "no HM refusal text")
  result(not SummaryMenu.isOpen(), "the summary screen closed on the HM pick")
  result(getVar(0x8005) == 2, "VAR_0x8005 is ROCK SMASH's slot, got " .. tostring(getVar(0x8005)))

  local asked = false
  for _ = 1, 60 do
    if Choice.active then asked = true break end
    U.wait(6)
  end
  result(asked, "the script asks whether ROCK SMASH should be forgotten")
  U.wait(12)
  U.still(game, DIR .. "/2432_confirm_forget.png")

  pumpUntil(function() return not Pokemon.knowsMove(mon, ROCK_SMASH) end, 400)
  result(not Pokemon.knowsMove(mon, ROCK_SMASH), "LARVITAR forgot ROCK SMASH")
  result(Pokemon.moveSlotCount(mon) == 2, "two moves are left, got " .. tostring(Pokemon.moveSlotCount(mon)))

  pumpUntil(function() return not (Space.vm and Space.vm:isRunning()) end, 400)
  U.wait(30)
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL move_deleter_hm_2432 driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
