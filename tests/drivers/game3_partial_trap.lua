local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_partial_trap"

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
  local Rules = require("src.core.game3.battle.rules")

  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 6, 50)
  local pm = session.party[1]
  pm.moves = { 35, 150 }
  pm.pp = { 20, 40 }
  pm.maxPp = { 20, 40 }

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 129, level = 60 }, { fade = false })
  result(ok == true, "wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local function cur_step()
    return AnimSeq._steps and AnimSeq._steps[AnimSeq._i]
  end

  local function vm_active_for(animName)
    return function()
      local s = cur_step()
      if not s or s.kind ~= "anim" or s.data.name ~= animName then return false end
      return Anim.vm() and Anim.vm():busy()
    end
  end

  local function msg_says(needle)
    return function()
      local s = cur_step()
      if not s or s.kind ~= "msg" then return false end
      local Message = package.loaded["src.ui.game3.message"]
      if Message and Message.isTyping and Message.isTyping() then return false end
      if not (Ui.dialogPending and Ui.dialogPending()) then return false end
      return tostring(s.data.text or ""):find(needle, 1, true) ~= nil
    end
  end

  local SHOTS = {
    { match = msg_says("was WRAPPED by"), delay = 2, file = "partial_trap_01_wrapped.png" },
    { match = vm_active_for("TURN_TRAP"), delay = 14, file = "partial_trap_02_turn_trap.png" },
    { match = msg_says("is hurt"), delay = 2, file = "partial_trap_03_chip.png" },
    { match = msg_says("was freed"), delay = 2, file = "partial_trap_04_freed.png" },
  }
  local counts = {}

  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local f, lastTap = 0, 0
  local function pump()
    f = f + 1
    for si, sh in ipairs(SHOTS) do
      if not sh.taken and sh.match() then
        counts[si] = (counts[si] or 0) + 1
        if counts[si] >= sh.delay then
          sh.taken = true
          U.shot(game, DIR .. "/" .. sh.file)
          print("shot " .. sh.file)
        end
      end
    end
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
      lastTap = f
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end

  for _ = 1, 3000 do
    if at_command() then break end
    pump()
  end
  result(at_command(), "reached command menu")
  local st = Battle.getState()
  if not st then love.event.quit(1) return end

  local logI = 0
  local function turn(slot, label)
    U.tap(game, "a")
    for _ = 1, 120 do
      if Ui._mode == "moves" then break end
      U.wait(1)
    end
    if Ui._mode ~= "moves" then
      result(false, "move menu opened for " .. label)
      return
    end
    for _ = 1, 4 do
      if Ui._moveIndex == slot then break end
      U.tap(game, (Ui._moveIndex or 1) < slot and "right" or "left")
      U.wait(4)
    end
    result(Ui._moveIndex == slot, "cursor on move slot " .. slot .. " for " .. label)
    U.tap(game, "a")
    for i = 1, 4000 do
      if not Battle.isActive() then break end
      if i > 20 and at_command() then break end
      pump()
    end
    local log = Ui.log()
    for li = logI + 1, #log do print("  log: " .. tostring(log[li]):gsub("\n", " ")) end
    logI = #log
    print(string.format("  turn %s ehp=%s/%s php=%s trap=%s", label, tostring(st.enemy.mon.hp),
      tostring(st.enemy.mon.maxHp), tostring(st.player.mon.hp), tostring(st.enemy.expTrapTurns)))
  end

  -- pokefirered/src/battle_script_commands.c:2490
  for _ = 1, 6 do
    if (st.enemy.expTrapTurns or 0) > 0 or not Battle.isActive() then break end
    turn(1, "wrap")
  end
  local rolled = st.enemy.expTrapTurns or 0
  result(rolled >= 2 and rolled <= 5, "trap turns left after the first residual are 2..5, got " .. tostring(rolled))

  local wrapText = false
  for _, t in ipairs(Ui.log()) do
    if t:find("WRAPPED by", 1, true) then wrapText = true end
  end
  result(wrapText, "gWrappedStringIds message for MOVE_WRAP printed")

  -- pokefirered/src/battle_util.c:886
  local chip = Rules.partialTrap.chipAmount(st.enemy.mon.maxHp)
  local ticks, freed, freedText = 0, false, false
  for _ = 1, 8 do
    if not Battle.isActive() then break end
    local left = st.enemy.expTrapTurns
    if not left then freed = true break end
    local before = st.enemy.mon.hp
    local mark = #Ui.log()
    turn(2, "splash while trapped")
    local lost = before - st.enemy.mon.hp
    for li = mark + 1, #Ui.log() do
      if Ui.log()[li]:find("was freed", 1, true) then freedText = true end
    end
    if st.enemy.expTrapTurns then
      ticks = ticks + 1
      result(lost == chip, string.format("residual chip is exactly maxHP/16 (%d == %d)", lost, chip))
      result(st.enemy.expTrapTurns == left - 1, "trap counter ticked down by one")
    else
      result(lost == 0, "release turn deals no chip (" .. tostring(lost) .. ")")
      freed = true
    end
  end
  result(freed and freedText, "trap released on its own with the freed message")
  result(ticks == rolled - 1, string.format("chip turns (%d) == rolled remaining - 1 (%d)", ticks, rolled - 1))
  result(st.enemy.expTrapTurns == nil, "expTrapTurns cleared on release")
  result(Battle.isActive() and at_command(), "battle still live at the command menu after release")

  for _, sh in ipairs(SHOTS) do
    result(sh.taken == true, "shot " .. sh.file)
  end

  print((fails == 0) and "PARTIAL_TRAP DRIVER PASS" or ("PARTIAL_TRAP DRIVER FAIL " .. fails))
  love.event.quit(fails == 0 and 0 or 1)
end
