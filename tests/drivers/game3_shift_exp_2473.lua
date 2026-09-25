local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_shift_exp_2473"

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
  local Options = require("src.core.game3.options")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local SwitchSeq = require("src.core.game3.battle.switch_seq")
  local Ui = require("src.core.game3.battle.ui")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 4, 30)
  Party.giveMon(session, 7, 20)
  Options.ensure(session).battleStyle = 0
  result(Options.battleStyle(session) == "shift", "battle style is shift")

  local ok, err = BattleBridge.start(Runtime._mod, game,
    { trainerId = 326, party = { { species = 16, level = 5 }, { species = 19, level = 5 } } },
    { wild = false, trainerId = 326, fade = false })
  result(ok == true, "trainer battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local f, lastTap = 0, 0
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local shiftOrder, goShot, participantsAfter = nil, false, nil
  local function watch_shift()
    if not SwitchSeq.busy() or shiftOrder then return end
    local steps = SwitchSeq._steps or {}
    local order = {}
    for _, s in ipairs(steps) do
      if s.kind == "swap_data" then order[#order + 1] = s.data and s.data.side end
    end
    if #order == 2 then shiftOrder = order end
  end

  local function pump(stop, limit)
    for _ = 1, limit or 6000 do
      f = f + 1
      watch_shift()
      if stop() then return true end
      local cur = SwitchSeq.busy() and SwitchSeq._steps and SwitchSeq._steps[SwitchSeq._i]
      local bst = Battle.getState()
      if not goShot and cur and cur.kind == "sendout_player" and bst
          and bst.enemy and (tonumber(bst.enemy.mon.hp) or 0) <= 0 then
        U.wait(10)
        U.still(game, DIR .. "/2473_mon2_out_before_foe.png")
        goShot = true
      end
      local PM = package.loaded["src.ui.game3.party_menu"]
      if PM and PM.isOpen and PM.isOpen() then
        U.wait(20)
        PM.cursor = 2
        U.tap(game, "a")
        U.wait(12)
        U.tap(game, "a")
        U.wait(12)
      elseif Ui.choiceActive and Ui.choiceActive() then
        U.wait(8)
        U.tap(game, "a")
        U.wait(8)
      elseif Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return stop()
  end

  result(pump(at_command), "reached command menu vs foe 1")
  local st = Battle.getState()
  if not st then love.event.quit(1) return end
  for _, m in ipairs(st.foeParty or {}) do
    m.moves = { 150, 0, 0, 0 }
    m.pp = { 40, 0, 0, 0 }
    m.hp = 1
  end
  st.enemy.mon.hp = 1
  local ep = Anim.present("enemy")
  if ep then ep.displayHp = 1 end

  local function attack()
    local mon = st.player.mon
    mon.moves[1] = 129
    mon.pp = mon.pp or {}
    mon.pp[1] = 20
    Ui._pendingCommand = { kind = "move", move = 129, slot = 1, user = "player" }
    Ui._mode = "none"
  end

  attack()
  result(pump(function() return Battle._phase == "shift_prompt" end), "shift prompt offered after foe 1 fainted")
  result(pump(function() return at_command() and st.player.partyIndex == 2 end), "shift switched to party slot 2")
  result(shiftOrder ~= nil and shiftOrder[1] == "player" and shiftOrder[2] == "enemy",
    "player swap runs before enemy send-out (" .. table.concat(shiftOrder or {}, ",") .. ")")
  result(goShot, "shot 2473_mon2_out_before_foe.png")
  participantsAfter = {}
  for pi in pairs(st.enemy.participants or {}) do participantsAfter[#participantsAfter + 1] = pi end
  table.sort(participantsAfter)
  result(#participantsAfter == 1 and participantsAfter[1] == 2,
    "foe 2 sent mons = {" .. table.concat(participantsAfter, ",") .. "}")

  local expA = tonumber(st.playerParty[1].exp) or 0
  local expB = tonumber(st.playerParty[2].exp) or 0
  st.enemy.mon.hp = 1
  ep = Anim.present("enemy")
  if ep then ep.displayHp = 1 end
  attack()
  local expShot = false
  result(pump(function()
    if not expShot then
      for _, t in ipairs(Ui.log()) do
        if tostring(t):find("gained", 1, true) and (tonumber(st.playerParty[2].exp) or 0) > expB then
          U.wait(90)
          U.still(game, DIR .. "/2473_only_mon2_gains_exp.png")
          expShot = true
          break
        end
      end
    end
    return not Battle.isActive()
  end, 9000), "battle ended after foe 2 fainted")
  local party = session.party
  local aNow = tonumber(party[1] and party[1].exp) or 0
  local bNow = tonumber(party[2] and party[2].exp) or 0
  print(string.format("  exp A %d -> %d, B %d -> %d", expA, aNow, expB, bNow))
  result(aNow == expA, "switched-out mon 1 gained no EXP for foe 2")
  result(bNow > expB, "mon 2 gained EXP for foe 2")
  result(expShot, "shot 2473_only_mon2_gains_exp.png")
  for _, t in ipairs(Ui.log()) do print("  log: " .. tostring(t):gsub("\n", " ")) end

  print(string.format("shift exp 2473 driver: %d failure(s)", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
