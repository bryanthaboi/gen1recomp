local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_battle_flow"

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
  local Ui = require("src.core.game3.battle.ui")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 6, 50)

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 45 }, { fade = false })
  result(ok == true, "wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local lastTap = 0
  local function pump_text(f)
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

  local f = 0
  for _ = 1, 3000 do
    f = f + 1
    if at_command() then break end
    if not pump_text(f) then U.wait(1) end
  end
  result(at_command(), "reached command menu")
  local st = Battle.getState()
  if not st then love.event.quit(1) return end
  st.enemy.mon.moves = { 150, 0, 0, 0 }
  st.enemy.mon.pp = { 40, 0, 0, 0 }
  st.enemy.mon.maxHp = 999
  st.enemy.mon.hp = 999

  local function cur_step()
    local s = AnimSeq._steps and AnimSeq._steps[AnimSeq._i]
    return s
  end

  local function step_is(kind, name)
    return function()
      local s = cur_step()
      if not s then return false end
      if s.kind ~= kind then return false end
      if name and s.data.name ~= name then return false end
      return true
    end
  end

  local pending = {}
  local function turn(moveId, shots, label)
    for _, sh in ipairs(shots or {}) do pending[#pending + 1] = sh end
    shots = pending
    local mon = st.player.mon
    mon.moves[1] = moveId
    mon.pp = mon.pp or {}
    mon.pp[1] = 10
    st.enemy.mon.hp = st.enemy.mon.maxHp
    local ep = Anim.present("enemy")
    if ep then ep.displayHp = st.enemy.mon.hp end
    Ui._pendingCommand = { kind = "move", move = moveId, slot = 1, user = "player" }
    Ui._mode = "none"
    local counts, taken = {}, {}
    for si, sh in ipairs(shots) do taken[si] = sh.taken end
    for i = 1, 4000 do
      f = f + 1
      local s = cur_step()
      for si, sh in ipairs(shots) do
        if not taken[si] and sh.match() then
          counts[si] = (counts[si] or 0) + 1
          if counts[si] >= (sh.delay or 12) then
            taken[si] = true
            sh.taken = true
            U.still(game, DIR .. "/" .. sh.file)
            print("shot " .. sh.file)
          end
        end
      end
      if not Battle.isActive() then break end
      if i > 5 and at_command() then break end
      local vmBusy = Anim.vm() and Anim.vm():busy()
      local PM = package.loaded["src.ui.game3.party_menu"]
      if PM and PM.isOpen and PM.isOpen() then
        U.wait(20)
        PM.cursor = (st.player.partyIndex == 1) and 2 or 1
        U.tap(game, "a")
        U.wait(12)
        U.tap(game, "a")
        U.wait(12)
      elseif vmBusy or (s and s.kind ~= "msg") then
        U.wait(1)
      elseif not pump_text(f) then
        U.wait(1)
      end
    end
    local log = Ui.log()
    for li = (st._flowLogI or 0) + 1, #log do print("  log: " .. tostring(log[li]):gsub("\n", " ")) end
    st._flowLogI = #log
    print(string.format("  turn %s done phase=%s php=%s ehp=%s", tostring(label), tostring(Battle._phase),
      tostring(st.player.mon.hp), tostring(st.enemy.mon.hp)))
  end

  local function report_shots()
    for _, sh in ipairs(pending) do
      result(sh.taken == true, "shot " .. sh.file)
    end
  end

  local function vm_active_for(kind, name)
    local m = step_is(kind, name)
    return function() return m() and Anim.vm() and Anim.vm():busy() end
  end

  turn(45, {
    { match = vm_active_for("anim", "STATS_CHANGE"), delay = 20, file = "flow_01_growl_stats_change.png" },
  }, "growl")
  result((st.enemy.stages.attack or 0) < 0, "growl lowered attack")

  turn(14, {
    { match = vm_active_for("move"), delay = 30, file = "flow_02_swords_dance_move.png" },
    { match = vm_active_for("anim", "STATS_CHANGE"), delay = 20, file = "flow_03_swords_dance_stats_up.png" },
  }, "swords dance")

  local wrapShot = { match = vm_active_for("anim", "TURN_TRAP"), delay = 14, file = "flow_04_wrap_turn_trap.png" }
  for attempt = 1, 4 do
    if (st.enemy.expTrapTurns or 0) > 0 or st.enemy.wrapped then break end
    turn(35, attempt == 1 and { wrapShot } or {}, "wrap")
  end
  result((st.enemy.expTrapTurns or 0) > 0 or st.enemy.wrapped ~= nil, "wrap applied")

  for _ = 1, 4 do
    if st.enemy.expSeeded then break end
    turn(73, {}, "leech seed")
  end
  result(st.enemy.expSeeded ~= nil, "leech seed applied")

  st.enemy.status = "PSN"
  st.enemy.mon.status = "PSN"
  turn(240, {
    { match = vm_active_for("anim", "POISON"), delay = 20, file = "flow_05_poison_tick.png" },
    { match = vm_active_for("anim", "LEECH_SEED_DRAIN"), delay = 25, file = "flow_06_leech_seed_drain.png" },
  }, "rain dance turn residuals")

  turn(150, {
    { match = vm_active_for("anim", "RAIN_CONTINUES"), delay = 20, file = "flow_07_rain_continues.png" },
  }, "rain continues")

  local pp = Anim.present("player")
  local flyTurn = st.turn
  local menuWhileFlying, hiddenSeen = false, false
  turn(19, {
    { match = function()
        if st.player.semiInvulnerable ~= nil and Ui._mode == "menu" then menuWhileFlying = true end
        local hidden = st.turn == flyTurn + 2 and st.player.semiInvulnerable ~= nil and pp.visible == false
        if hidden then hiddenSeen = true end
        return hidden
      end, delay = 1, file = "flow_08_fly_hidden.png" },
  }, "fly")
  result(hiddenSeen, "player hidden while flying")
  result(not menuWhileFlying, "no command menu on the fly charge turn")
  result(st.turn == flyTurn + 2, "fly strike ran without a menu pick")
  result(pp.visible ~= false, "player visible after fly strike")

  st.player.mon.item = 200
  st.player.item = 200
  st.player.mon.hp = math.floor(st.player.mon.maxHp / 2)
  pp.displayHp = st.player.mon.hp
  turn(150, {
    { match = vm_active_for("anim", "HELD_ITEM_EFFECT"), delay = 10, file = "flow_08b_leftovers.png" },
  }, "leftovers")
  result(st.player.mon.hp > math.floor(st.player.mon.maxHp / 2), "leftovers restored HP")

  turn(164, {}, "substitute")
  result((st.player.substituteHP or 0) > 0 and pp.substitute == true, "substitute doll shown")
  U.still(game, DIR .. "/flow_09_substitute_doll.png")

  turn(46, {
    { match = function() local s = cur_step() return s and s.kind == "switch_out" end, delay = 6, file = "flow_10_roar_switch_out.png" },
  }, "roar")
  result(not Battle.isActive() or Battle._phase == "ending" or Battle._phase == "fade_out", "roar ended the wild battle")
  local sawFlee = false
  for _, t in ipairs(Ui.log()) do if t:find("Got away safely", 1, true) then sawFlee = true end end
  result(not sawFlee, "no Got away safely after roar")
  U.wait(60)
  U.still(game, DIR .. "/flow_11_after_roar.png")

  for _ = 1, 600 do
    if not Battle.isActive() then break end
    U.wait(1)
  end
  U.wait(60)
  Party.giveMon(session, 25, 40)
  local ok2, err2 = BattleBridge.start(Runtime._mod, game,
    { trainerId = 326, party = { { species = 58, level = 30, ability = "INTIMIDATE" }, { species = 1, level = 30 } } },
    { wild = false, trainerId = 326, fade = false })
  result(ok2 == true, "trainer battle started " .. tostring(err2 or ""))
  if ok2 then
    local introShot = false
    for k = 1, 3000 do
      f = f + 1
      local s0 = cur_step()
      if not introShot and Battle._phase == "startfx" and s0 and s0.kind == "anim" and s0.data.name == "STATS_CHANGE"
          and Anim.vm() and Anim.vm():busy() then
        for _ = 1, 16 do U.wait(1) end
        U.still(game, DIR .. "/flow_11b_intimidate.png")
        introShot = true
      end
      if k % 300 == 0 then
        local Msg = require("src.ui.game3.message")
        print("  wait trainer", Battle.isActive(), Battle._phase, Ui._mode, Ui.dialogPending(), Anim.busy(), #Ui._queue,
          Ui._timed and "timed" or "-", Ui._linger, Ui._showing, Msg.isOpen(), Msg._stay, Msg.isWaiting(), tostring(Msg.currentPage()):gsub("\n", " "))
      end
      if at_command() then break end
      if not pump_text(f) then U.wait(1) end
    end
    result(at_command(), "trainer battle command menu")
    result(introShot, "intimidate stat drop played at battle start")
    st = Battle.getState()
    for _, m in ipairs(st.foeParty or {}) do
      m.moves = { 150, 0, 0, 0 }
      m.pp = { 40, 0, 0, 0 }
      m.maxHp, m.hp = 400, 400
    end
    st.enemy.mon.moves = { 150, 0, 0, 0 }
    local before = st.enemy.partyIndex
    turn(18, {
      { match = function() local s = cur_step() return s and s.kind == "switch_out" end, delay = 8, file = "flow_12_whirlwind_switch_out.png" },
      { match = function() local s = cur_step() return s and s.kind == "msg" and tostring(s.data.text):find("dragged out") end, delay = 1, file = "flow_13_whirlwind_dragged_in.png" },
    }, "whirlwind")
    result(st.enemy.partyIndex ~= before, "whirlwind dragged out the other foe")
    local pBefore = st.player.partyIndex
    turn(226, {
      { match = function() local SS = require("src.core.game3.battle.switch_seq") return AnimSeq._waitSwitch and SS.busy() end, delay = 30, file = "flow_15_baton_pass_in.png" },
    }, "baton pass")
    result(st.player.partyIndex ~= pBefore, "baton pass switched the player mon")
    U.still(game, DIR .. "/flow_16_after_baton_pass.png")
    turn(144, {
      { match = function() local p = Anim.present("player") return (p.mosaic or 0) > 6 end, delay = 1, file = "flow_17_transform_mosaic.png" },
    }, "transform")
    local ppl = Anim.present("player")
    result(st.player.expTransform ~= nil and ppl.transformSpecies == st.enemy.species, "transform swapped the player pic")
    U.still(game, DIR .. "/flow_18_after_transform.png")
  end

  report_shots()
  print(string.format("battle flow driver: %d failure(s)", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
