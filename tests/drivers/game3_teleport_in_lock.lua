local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_teleport_in_lock"

local PALLET = "FR_PALLET_TOWN"
local FLAG_BADGE03_GET = 0x822
local FLAG_SYS_POKEMON_GET = 0x828

local failures = 0

local function say(line)
  print(line)
end

local function result(ok, label)
  say((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    say("PASS game3_teleport_in_lock")
    love.event.quit(0)
  else
    say("FAIL game3_teleport_in_lock failures=" .. failures)
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
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local Field = require("src.core.game3.field")
  local Fade = require("src.ui.game3.fade")
  local FieldEffects = require("src.core.game3.field_effects")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_BADGE03_GET, true)
  Flags.setFlag(Space.store, nil, FLAG_SYS_POKEMON_GET, true)
  session.party = {}
  Party.giveMon(session, 6, 40)
  local mon = session.party[1]
  mon.moves = { "TELEPORT", "EMBER", "FLY", "DIG" }
  mon.pp = { 20, 25, 15, 10 }

  Map.load(nil, game, PALLET, { x = 10, y = 6, facing = "down" })
  session.x, session.y, session.facing = 10, 6, "down"
  Player.cellX, Player.cellY = 10, 6
  Player.px, Player.py = 160, 96
  Player.targetX, Player.targetY = 10, 6
  Player.facing = "down"
  U.wait(90)

  local function openParty()
    for _ = 1, 40 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      if StartMenu.isOpen and StartMenu.isOpen() then break end
      U.tap(game, "start")
      U.wait(8)
    end
    for _ = 1, 20 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "pokemon" then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    for _ = 1, 60 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      U.wait(4)
    end
    return false
  end

  local function chooseAction(label)
    U.tap(game, "a")
    U.wait(12)
    local target = nil
    for i, name in ipairs(PartyMenu.ACTIONS or {}) do
      if name == label then target = i end
    end
    if not target then return false end
    for _ = 1, 12 do
      if PartyMenu.actionCursor == target then break end
      U.tap(game, "down")
      U.wait(6)
    end
    return PartyMenu.actionCursor == target
  end

  local function fxAnim(kind)
    for _, a in ipairs(FieldEffects._anims or {}) do
      if a.kind == kind then return a end
    end
  end

  local function waitFor(pred, frames)
    for _ = 1, frames do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end

  if not result(openParty(), "party menu opens in Pallet Town") then return finish() end
  if not result(chooseAction("TELEPORT"), "TELEPORT is on the action list") then return finish() end
  U.tap(game, "a")
  U.wait(20)
  U.tap(game, "a")
  U.wait(6)
  waitFor(function() return fxAnim("teleport_out") ~= nil end, 400)
  if not result(fxAnim("teleport_out") ~= nil, "teleport_out started") then return finish() end
  waitFor(function() return session.map ~= PALLET end, 900)
  if not result(session.map ~= PALLET, "the heal map loaded (map=" .. tostring(session.map) .. ")") then
    return finish()
  end

  local dirs = { "left", "down", "right", "up" }
  local startCell = { Player.cellX, Player.cellY }
  local st = {
    f = 0, firstUnlock = nil, firstFadeDone = nil, firstIn = nil, inDone = nil,
    movedDuringFade = false, movedDuringIn = false, claimEarly = false,
  }

  local function step()
    st.f = st.f + 1
    local f = st.f
    local btn = dirs[(math.floor((f - 1) / 12) % #dirs) + 1]
    table.insert(game.input.pressQueue, btn)
    game.input.state[btn] = true
    U.wait(1)
    game.input.state[btn] = false
    local tin = fxAnim("teleport_in")
    if not st.firstUnlock and Field.locked == false then st.firstUnlock = f end
    if not st.firstFadeDone and not Fade.active then st.firstFadeDone = f end
    if not st.firstIn and tin then st.firstIn = f end
    if st.firstIn and not st.inDone and not tin then st.inDone = f end
    if not st.inDone and Space._pendingOnFrame ~= true then st.claimEarly = true end
    local moved = Player.moving or Player.cellX ~= startCell[1] or Player.cellY ~= startCell[2]
    if moved then
      if tin then st.movedDuringIn = true end
      if Fade.active then st.movedDuringFade = true end
    end
    return tin
  end

  for _ = 1, 300 do
    local tin = step()
    if tin and tin.y2 >= -40 then break end
  end
  local mid = fxAnim("teleport_in")
  result(mid ~= nil and Field.locked == true,
    "the field is locked mid teleport-in spin (y2=" .. tostring(mid and mid.y2) .. ")")
  U.still(game, DIR .. "/teleport_in_locked_mid_spin.png")

  for _ = 1, 300 do
    step()
    if st.inDone and st.f > st.inDone + 30 then break end
  end
  say(string.format("[driver] firstUnlock=%s firstFadeDone=%s firstIn=%s inDone=%s",
    tostring(st.firstUnlock), tostring(st.firstFadeDone), tostring(st.firstIn), tostring(st.inDone)))
  result(st.firstIn ~= nil and st.inDone ~= nil, "the heal map ran the teleport-in effect")
  result(not (st.firstUnlock and st.firstFadeDone and st.firstUnlock < st.firstFadeDone),
    "the field stays locked through the fade-in (unlock f=" .. tostring(st.firstUnlock)
    .. ", fade done f=" .. tostring(st.firstFadeDone) .. ")")
  result(st.firstUnlock ~= nil and st.inDone ~= nil and st.firstUnlock >= st.inDone,
    "the field stays locked until TeleportInFieldEffectTask3 unlocks it (unlock f=" .. tostring(st.firstUnlock)
    .. ", spin done f=" .. tostring(st.inDone) .. ")")
  result(not st.movedDuringFade, "the player cannot walk during the fade-in")
  result(not st.movedDuringIn, "the player cannot walk during the teleport-in spin")
  result(not st.claimEarly, "the heal map ON_FRAME claim waits for the teleport-in spin")
  result(Space._pendingOnFrame ~= true and Field.locked == false,
    "after the spin the ON_FRAME claim runs and the field unlocks")
  U.still(game, DIR .. "/teleport_in_after_spin.png")
  finish()
end

return run
