local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_battle_gaps"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local AnimSeq = require("src.core.game3.battle.anim_seq")
  local IntroSeq = require("src.core.game3.battle.intro_seq")
  local Ui = require("src.core.game3.battle.ui")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Message = require("src.ui.game3.message")
  local session = Runtime.getSession()

  local f, lastTap = 0, 0
  local function pump_text()
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
      lastTap = f
      U.tap(game, "a")
      return true
    end
    return false
  end
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function cur_step()
    return AnimSeq._steps and AnimSeq._steps[AnimSeq._i]
  end
  local function vm_busy()
    return Anim.vm() and Anim.vm():busy()
  end
  local function page()
    return Message.isOpen() and tostring(Message.currentPage()) or ""
  end

  local function run_until(pred, shots, limit, choose)
    shots = shots or {}
    local counts = {}
    local menuFrames = 0
    for _ = 1, limit or 4000 do
      f = f + 1
      local holding = false
      for _, sh in ipairs(shots) do
        if not sh.taken and sh.match() then
          holding = true
          counts[sh] = (counts[sh] or 0) + 1
          if counts[sh] >= (sh.delay or 1) then
            sh.taken = U.shot(game, DIR .. "/" .. sh.file)
            print("shot " .. sh.file .. " text=" .. page():gsub("\n", " "))
          end
        end
      end
      if pred() then return true end
      if PartyMenu.isOpen() and choose then
        menuFrames = menuFrames + 1
        if menuFrames > 45 then
          menuFrames = 0
          choose()
        else
          U.wait(1)
        end
      elseif holding then
        U.wait(1)
      else
        local s = cur_step()
        if vm_busy() or (s and s.kind ~= "msg") or IntroSeq._waitingGen then
          U.wait(1)
        elseif not pump_text() then
          U.wait(1)
        end
      end
    end
    return false
  end

  local function report(shots)
    for _, sh in ipairs(shots) do result(sh.taken == true, "shot " .. sh.file) end
  end

  local function finish_battle()
    Battle.abort("run")
    for _ = 1, 120 do
      if not Battle.isActive() then break end
      U.wait(1)
    end
    U.wait(30)
  end

  local function command(cmd)
    Ui._pendingCommand = cmd
    Ui._mode = "none"
  end

  local function log_tail(from)
    local log = Ui.log()
    for i = from + 1, #log do print("  log: " .. tostring(log[i]):gsub("\n", " ")) end
    return #log
  end

  session.party = {}
  Party.giveMon(session, 6, 50)
  Party.giveMon(session, 25, 40)

  do
    local ok = BattleBridge.startWild(Runtime._mod, game, { species = 92, level = 20, ghost = true }, { fade = false })
    result(ok == true, "ghost battle started")
    local shots = {
      { match = function() return page():find("can't be ID'd", 1, true) ~= nil end, delay = 40, file = "gap_01_ghost_intro.png" },
    }
    run_until(at_command, shots, 3000)
    report(shots)
    result(at_command(), "ghost battle command menu")
    local st = Battle.getState()
    result(st and st.ghostBattle and not st.ghostUnveiled, "ghost battle flag")
    local li = log_tail(0)
    local turnShots = {
      { match = function() local s = cur_step() return s and s.kind == "anim" and s.data.name == "MON_SCARED" and vm_busy() end,
        delay = 24, file = "gap_02_too_scared.png" },
      { match = function() local s = cur_step() return s and s.kind == "anim" and s.data.name == "GHOST_GET_OUT" and vm_busy() end,
        delay = 60, file = "gap_03_get_out.png" },
    }
    command({ kind = "move", move = st.player.mon.moves[1], slot = 1, user = "player" })
    run_until(function() return f > 10 and at_command() end, turnShots, 4000)
    report(turnShots)
    li = log_tail(li)
    result(st.enemy.mon.hp == st.enemy.mon.maxHp, "ghost untouched")
    local Bag = require("src.core.game3.bag")
    Bag.add(session.bag, 4, 3)
    local ballShots = {
      { match = function() return page():find("dodged", 1, true) ~= nil end, delay = 20, file = "gap_04_ball_dodge.png" },
    }
    command({ kind = "bag", itemId = 4, user = "player" })
    run_until(function() return f > 10 and at_command() end, ballShots, 4000)
    report(ballShots)
    li = log_tail(li)
    command({ kind = "run", user = "player" })
    run_until(function() return not Battle.isActive() end, {}, 2000)
    log_tail(li)
    result(not Battle.isActive(), "ran from the ghost")
    U.wait(30)
  end

  do
    local ok = BattleBridge.startWild(Runtime._mod, game,
      { species = 105, level = 30, ghost = true, ghostUnveiled = true }, { fade = false })
    result(ok == true, "marowak battle started")
    local shots = {
      { match = function() return page():find("unveiled", 1, true) ~= nil and not vm_busy() end, delay = 10, file = "gap_05_scope_text.png" },
      { match = function() local p = Anim.present("enemy") return vm_busy() and (p.mosaic or 0) >= 6 end, delay = 1, file = "gap_06_scope_mosaic.png" },
      { match = function() return page():find("MAROWAK", 1, true) ~= nil end, delay = 30, file = "gap_07_ghost_was_marowak.png" },
    }
    run_until(at_command, shots, 4000)
    report(shots)
    local st = Battle.getState()
    result(Anim.present("enemy").ghostUnveiled == true and st.enemy.mon.nickname == nil, "marowak unveiled")
    log_tail(0)
    finish_battle()
  end

  do
    local ok = BattleBridge.start(Runtime._mod, game,
      { trainerId = 326, party = { { species = 58, level = 30, ability = "INTIMIDATE" }, { species = 1, level = 30 } } },
      { wild = false, trainerId = 326, fade = false })
    result(ok == true, "trainer battle started")
    local sawGo = false
    local shots = {
      { match = function()
          local s = cur_step()
          local hit = Battle._phase == "startfx" and s and s.kind == "anim" and s.data.name == "STATS_CHANGE" and vm_busy()
          if hit and page():find("Go!", 1, true) then sawGo = true end
          return hit
        end, delay = 16, file = "gap_08_intimidate_go_text.png" },
    }
    run_until(at_command, shots, 4000)
    report(shots)
    result(sawGo, "Go! text on screen during the intimidate stat drop")

    local st = Battle.getState()
    Party.giveMon(session, 12, 30)
    st.playerParty[3] = st.playerParty[3] or session.party[3]
    for _, m in ipairs(st.foeParty or {}) do
      m.moves = { 150, 0, 0, 0 }
      m.pp = { 40, 0, 0, 0 }
    end
    st.enemy.mon.moves = { 150, 0, 0, 0 }
    st.player.mon.moves[1] = 226
    st.player.mon.pp[1] = 10
    st.player.stages.attack = 2
    local chose = false
    local bpShots = {
      { match = function() return PartyMenu.isOpen() end, delay = 30, file = "gap_09_baton_pass_party_menu.png" },
      { match = function() return chose and page():find("Go!", 1, true) ~= nil end, delay = 10, file = "gap_10_baton_pass_go.png" },
    }
    local target = #st.playerParty
    command({ kind = "move", move = 226, slot = 1, user = "player" })
    run_until(function() return f > 10 and at_command() end, bpShots, 5000, function()
      PartyMenu.cursor = target
      U.tap(game, "a")
      U.wait(12)
      U.tap(game, "a")
      U.wait(12)
      chose = true
    end)
    report(bpShots)
    result(st.player.partyIndex == target and st.player.stages.attack == 2, "baton pass to the chosen slot kept +2 ATK")
    log_tail(0)
    finish_battle()
  end

  do
    session.party = {}
    Party.giveMon(session, 385, 40)
    local ok = BattleBridge.startWild(Runtime._mod, game,
      { species = 385, level = 40, moves = { 240, 0, 0, 0 }, pp = { 5, 0, 0, 0 } }, { fade = false })
    result(ok == true, "castform battle started")
    run_until(at_command, {}, 3000)
    local st = Battle.getState()
    st.player.mon.moves[1] = 241
    st.player.mon.pp[1] = 5
    st.player.mon.speed, st.enemy.mon.speed = 200, 10
    U.shot(game, DIR .. "/gap_11_castform_normal.png")
    local shots = {
      { match = function() local s = cur_step() return s and s.kind == "anim" and s.data.name == "CASTFORM_CHANGE"
          and (Anim.present(s.data.attacker).mosaic or 0) >= 10 end, delay = 1, file = "gap_12_castform_mosaic.png" },
      { match = function() return Anim.present("player").castformForm == 1 and Anim.present("enemy").castformForm == 1
          and page():find("transformed", 1, true) ~= nil end, delay = 20, file = "gap_13_castform_both_sunny.png" },
      { match = function() return Anim.present("player").castformForm == 2 end, delay = 40, file = "gap_14_castform_rainy.png" },
    }
    command({ kind = "move", move = 241, slot = 1, user = "player" })
    run_until(function() return f > 10 and at_command() end, shots, 6000)
    report(shots)
    result(Anim.present("player").castformForm == 2, "player castform ended in RAIN form")
    log_tail(0)
    finish_battle()
  end

  print(string.format("battle gaps driver: %d failure(s)", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
