local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_oak_first_battle"

local VAR_OAKS_LAB_SCENE = 0x4055
local BULBASAUR_BALL = 5

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    print("driver done fails=" .. tostring(fails))
    love.event.quit(fails == 0 and 0 or 1)
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local FieldFlags = require("src.core.game3.scripting.flags")
  local Objects = require("src.core.game3.objects")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local Anim = require("src.core.game3.battle.anim")
  local PartyMenu = require("src.ui.game3.party_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.party = {}

  local function place(x, y, facing)
    Map.load(nil, game, "FR_OAKS_LAB", { x = x, y = y, facing = facing })
    game.session.x, game.session.y, game.session.facing = x, y, facing
    U.wait(60)
    session = Runtime.getSession()
  end

  local function scene()
    if not (Space.store and Space.vm) then return nil end
    return FieldFlags.getVar(Space.store, Space.vm.ctx, VAR_OAKS_LAB_SCENE)
  end

  -- pokefirered/data/maps/PalletTown_ProfessorOaksLab/scripts.inc:333
  place(8, 5, "up")
  if not result(Space.vm ~= nil and Space.store ~= nil, "script VM active in FR_OAKS_LAB") then
    return finish()
  end
  FieldFlags.setVar(Space.store, Space.vm.ctx, VAR_OAKS_LAB_SCENE, 2)
  local ball = Objects.find(BULBASAUR_BALL)
  if not result(ball ~= nil, "BULBASAUR ball on the table") then return finish() end
  place(ball.cellX, ball.cellY + 1, "up")
  FieldFlags.setVar(Space.store, Space.vm.ctx, VAR_OAKS_LAB_SCENE, 2)

  U.tap(game, "a")
  U.wait(10)
  for _ = 1, 900 do
    if session.party and session.party[1] then break end
    U.tap(game, "a")
    U.wait(3)
  end
  if not result(session.party and session.party[1] ~= nil,
      "starter picked through the real Oak's Lab script") then
    return finish()
  end
  for _ = 1, 1500 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    U.tap(game, "b")
    U.wait(3)
  end
  result(scene() == 3, "VAR_OAKS_LAB_SCENE advanced to 3 (got " .. tostring(scene()) .. ")")

  -- pokefirered/data/maps/PalletTown_ProfessorOaksLab/scripts.inc:270
  place(6, 7, "down")
  for _ = 1, 400 do
    if Battle.isActive() then break end
    if Space.vm and Space.vm:isRunning() then
      U.tap(game, "a")
      U.wait(4)
    elseif (game.session.y or 0) < 8 then
      U.hold(game, "down", 18)
      U.wait(4)
    else
      U.wait(4)
    end
  end
  if not result(Battle.isActive(), "trainerbattle_earlyrival started from the map script") then
    return finish()
  end

  local st = Battle.getState()
  if not st then return finish() end
  result(st.firstBattle == true, "st.firstBattle set from the script operand")
  result(st.earlyRival == true and st.rivalFlags == 3,
    "RIVAL_BATTLE_TUTORIAL carried through (flags " .. tostring(st.rivalFlags) .. ")")
  result(st.aiFlags == 7, "rival keeps aiFlags 7 (got " .. tostring(st.aiFlags) .. ")")
  result(st.trainerId == 326 or st.trainerId == 327 or st.trainerId == 328,
    "a legal Oak's Lab rival (trainer " .. tostring(st.trainerId) .. ")")
  result(st.victoryText ~= nil and st.victoryText ~= "",
    "the script's victory_text reached the battle")

  local function page_text()
    if not (Message and Message.isOpen and Message.isOpen()) then return nil end
    local pages = Message._pages or {}
    return pages[Message._page or 1]
  end

  local function showing(needle)
    local p = page_text()
    return p ~= nil and tostring(p):find(needle, 1, true) ~= nil
  end

  local shots = {}
  local function want(needle, file, label)
    local sh = { needle = needle, file = file, label = label, held = 0 }
    shots[#shots + 1] = sh
    return sh
  end

  local function poll_shots()
    for _, sh in ipairs(shots) do
      if not sh.taken then
        local inVoiceover = (Message.frameKind and Message.frameKind() == "voiceover")
        if showing(sh.needle) and Message.isWaiting and Message.isWaiting()
            and inVoiceover == (sh.voiceover == true) then
          sh.held = sh.held + 1
          if sh.held >= 6 then
            sh.taken = true
            U.shot(game, DIR .. "/" .. sh.file)
            print("shot " .. sh.file)
          end
        else
          sh.held = 0
        end
      end
    end
  end

  local function shot_pending_here()
    for _, sh in ipairs(shots) do
      if not sh.taken and showing(sh.needle) then return true end
    end
    return false
  end

  local lastTap = 0
  local f = 0
  local undimShot = false
  local closedEarly = false
  local lastDim = 0
  local function poll_undim()
    local dim = Ui.voiceoverDim()
    if dim < lastDim and dim > 0 and not (Message.isOpen() and Message.frameKind() == "voiceover") then
      closedEarly = true
    end
    if not undimShot and Message.isHeld and Message.isHeld() and dim > 0 and dim < 0.5 then
      undimShot = true
      U.shot(game, DIR .. "/2310_09_oak_voiceover_undim.png")
      print("shot 2310_09_oak_voiceover_undim.png")
    end
    lastDim = dim
  end
  local function pump(frames, stop)
    for _ = 1, frames do
      f = f + 1
      poll_shots()
      poll_undim()
      if stop and stop() then return true end
      if shot_pending_here() then
        U.wait(1)
      elseif Ui.dialogPending and Ui.dialogPending() and not Anim.busy() and f - lastTap >= 16 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return false
  end

  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  -- pokefirered/src/battle_controller_oak_old_man.c:626
  local introShot = want("for Pete's sake", "2310_01_oak_voiceover_intro.png", "opening Oak speech")
  introShot.voiceover = true
  local trainerShot = want("The TRAINER that makes", "2310_02_oak_voiceover_trainer_that.png", "second opening page")
  trainerShot.voiceover = true
  pump(4000, at_command)
  result(at_command(), "reached the command menu after Oak's opening speech")
  result(introShot.taken == true, "Oak's opening speech uses B_WIN_OAK_OLD_MAN")

  -- pokefirered/src/party_menu.c:5832
  Ui._menuIndex = 3
  U.tap(game, "a")
  for _ = 1, 400 do
    if PartyMenu.isOpen() and PartyMenu.mode == "oak" then break end
    U.wait(1)
  end
  result(PartyMenu.isOpen() and PartyMenu.mode == "oak",
    "the first in-battle party menu opens on Oak's advice")
  local function oak_fx() return PartyMenu._oakFx or {} end
  result(oak_fx().phase == "darken" and (oak_fx().y or 0) < 6, "the party menu darkens from 0, not instantly")
  for _ = 1, 120 do
    if oak_fx().phase == "text" then break end
    U.wait(1)
  end
  result(oak_fx().phase == "text" and oak_fx().y == 6, "msg 1 prints once the dim reaches 6")
  U.wait(4)
  U.shot(game, DIR .. "/2310_03_oak_party_menu.png")
  result(true, "shot 2310_03_oak_party_menu.png (party-menu advice)")
  -- pokefirered/src/party_menu.c:1970
  U.tap(game, "a")
  for _ = 1, 120 do
    if oak_fx().phase == "text" and PartyMenu._oakPage == 2 then break end
    U.wait(1)
  end
  result(PartyMenu._oakPage == 2 and oak_fx().slot == 0 and oak_fx().y == 6,
    "the first slot lightens before msg 2")
  U.wait(4)
  U.shot(game, DIR .. "/2310_08_oak_party_menu_slot_lit.png")
  result(true, "shot 2310_08_oak_party_menu_slot_lit.png (first slot lit, msg 2)")
  for _ = 1, 40 do
    if not (PartyMenu.isOpen() and PartyMenu.mode == "oak") then break end
    U.tap(game, "a")
    U.wait(10)
  end
  result(not (PartyMenu.isOpen() and PartyMenu.mode == "oak"), "the advice pages all dismiss")
  for _ = 1, 300 do
    if at_command() then break end
    U.tap(game, "b")
    U.wait(6)
  end
  result(at_command(), "back at the command menu after the party menu")
  local Oak = require("src.core.game3.battle.oak_advice")
  result(Oak.testFlag(st, Oak.FLAG_PARTY_MENU), "FIRST_BATTLE_MSG_FLAG_PARTY_MENU latched")

  -- pokefirered/src/battle_main.c:3053
  local runShot = want("no running away", "2310_04_oak_no_running.png", "Oak's no-running line")
  runShot.voiceover = true
  Ui._menuIndex = 4
  U.tap(game, "a")
  pump(900, function() return runShot.taken == true end)
  pump(600, at_command)
  result(runShot.taken == true, "RUN in the tutorial battle prints Oak's no-running line")

  -- pokefirered/src/battle_controller_opponent.c:304
  local dmgShot = want("Inflicting damage on the foe", "2310_05_oak_inflicting_damage.png", "first-damage advice")
  dmgShot.voiceover = true
  for _ = 1, 3 do
    if dmgShot.taken then break end
    if at_command() then
      Ui._menuIndex = 1
      U.tap(game, "a")
      U.wait(20)
      Ui._moveIndex = 1
      U.tap(game, "a")
    end
    pump(1200, function() return dmgShot.taken == true or not Battle.isActive() end)
    if not Battle.isActive() then break end
  end
  result(dmgShot.taken == true, "first damage on the foe prints Oak's damage advice")
  pump(1500, at_command)

  -- pokefirered/data/maps/PalletTown_ProfessorOaksLab/text.inc:40
  want("Am I great or what?", "2310_06_rival_victory_text.png", "rival victory speech")
  local lossShot = want("How disappointing", "2310_07_oak_how_disappointing.png", "Oak's loss speech")
  lossShot.voiceover = true
  local pp = Anim.present("player")
  st.enemy.mon.moves = { 33, 0, 0, 0 }
  st.enemy.mon.pp = { 35, 0, 0, 0 }
  st.enemy.mon.level = 80
  for _ = 1, 4 do
    if not Battle.isActive() then break end
    if at_command() then
      st.player.mon.hp = 1
      st.player.hp = 1
      if pp then pp.displayHp = 1 end
      Ui._menuIndex = 1
      U.tap(game, "a")
      U.wait(20)
      Ui._moveIndex = 1
      U.tap(game, "a")
    end
    pump(1200, function() return lossShot.taken == true or not Battle.isActive() end)
    if lossShot.taken then break end
  end
  pump(900, function() return not Battle.isActive() end)

  local sawWhiteout = false
  for _, t in ipairs(Ui.log() or {}) do
    if tostring(t):find("blacked out", 1, true) then sawWhiteout = true end
  end
  result(sawWhiteout == false, "no white-out pair on the tutorial loss")

  for _, sh in ipairs(shots) do
    result(sh.taken == true, "shot " .. sh.file .. " (" .. sh.label .. ")")
  end
  -- pokefirered/src/battle_controller_oak_old_man.c:793
  result(closedEarly == false, "the voiceover frame is never removed before the undim ends")
  result(undimShot == true, "shot 2310_09_oak_voiceover_undim.png (frame up during the 8 -> 0 fade)")

  finish()
end
