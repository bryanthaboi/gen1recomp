local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_battle_flow_rom_text"

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
  local Bag = require("src.core.game3.bag")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local AnimSeq = require("src.core.game3.battle.anim_seq")
  local IntroSeq = require("src.core.game3.battle.intro_seq")
  local Catching = require("src.core.game3.battle.catching")
  local Experience = require("src.core.game3.battle.experience")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local session = Runtime.getSession()

  local f, lastTap = 0, 0
  local function page()
    return Message.isOpen() and tostring(Message.currentPage()) or ""
  end
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function run_until(pred, shots, limit)
    local counts = {}
    for _ = 1, limit or 4000 do
      f = f + 1
      local holding = false
      for _, sh in ipairs(shots) do
        if not sh.taken and sh.match() then
          holding = true
          if not Message.isTyping() then counts[sh] = (counts[sh] or 0) + 1 end
          if (counts[sh] or 0) >= (sh.delay or 1) then
            sh.text = page()
            sh.taken = U.still(game, DIR .. "/" .. sh.file)
            print("shot " .. sh.file .. " text=" .. sh.text:gsub("\n", " "))
          end
        end
      end
      if pred() then return true end
      local s = AnimSeq._steps and AnimSeq._steps[AnimSeq._i]
      if holding or (Anim.vm() and Anim.vm():busy()) or (s and s.kind ~= "msg") or IntroSeq._waitingGen then
        U.wait(1)
      elseif Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return false
  end
  local function has_page(s) return function() return page():find(s, 1, true) ~= nil end end
  local function command(cmd)
    Ui._pendingCommand = cmd
    Ui._mode = "none"
  end

  session.party = {}
  Party.giveMon(session, 4, 30)
  Party.giveMon(session, 7, 30)
  local lead = session.party[1]
  lead.exp = Experience.expForLevel(lead, 31) - 1
  Bag.add(session.bag, 4, 5)

  local ok = BattleBridge.startWild(Runtime._mod, game,
    { species = 16, level = 3, moves = { 33, 0, 0, 0 }, pp = { 35, 0, 0, 0 } }, { fade = false })
  result(ok == true, "wild battle started")
  local intro = {
    { match = has_page("appeared!"), delay = 20, file = "b3_wild_pkmn_appeared.png" },
    { match = has_page("Go! "), delay = 1, file = "b3_intro_go_pkmn.png" },
  }
  run_until(at_command, intro, 4000)
  result(intro[1].taken and intro[1].text:find("Wild PIDGEY appeared!", 1, true) ~= nil, "sText_WildPkmnAppeared")
  result(intro[2].taken and intro[2].text:find("Go! CHARMANDER!", 1, true) ~= nil, "sText_GoPkmn")
  U.wait(20)
  U.still(game, DIR .. "/b3_what_will_pkmn_do.png")
  result(at_command(), "action menu with gText_WhatWillPkmnDo / gText_BattleMenu")

  local st = Battle.getState()
  st.enemy.mon.speed = 1
  local switch = {
    { match = has_page("Come back!"), delay = 20, file = "b3_return_mon.png" },
    { match = has_page("Go! SQUIRTLE!"), delay = 1, file = "b3_switch_in_mon.png" },
  }
  command({ kind = "switch", user = "player", slot = 2 })
  run_until(function() return f > 10 and at_command() end, switch, 6000)
  result(switch[1].taken and switch[1].text:find("CHARMANDER, that's enough!", 1, true) ~= nil,
    "STRINGID_RETURNMON hpScale 0")
  result(switch[2].taken and switch[2].text:find("Go! SQUIRTLE!", 1, true) ~= nil, "STRINGID_SWITCHINMON hpScale 0")

  local realTry = Catching.tryCatch
  Catching.tryCatch = function() return false, 1 end
  local throw = {
    { match = has_page("used"), delay = 10, file = "b3_player_used_ball.png" },
    { match = has_page("appeared to be caught"), delay = 20, file = "b3_ball_escape_one_shake.png" },
  }
  command({ kind = "bag", user = "player", itemId = 4 })
  run_until(function() return f > 10 and at_command() end, throw, 6000)
  Catching.tryCatch = realTry
  result(throw[1].taken and throw[1].text:find("RED used", 1, true) ~= nil, "STRINGID_PLAYERUSEDITEM")
  result(throw[2].taken and throw[2].text:find("Aww!", 1, true) ~= nil, "STRINGID_ITAPPEAREDCAUGHT")

  st = Battle.getState()
  st.enemy.mon.hp = 1
  st.player.mon.exp = Experience.expForLevel(st.player.mon, 31) - 1
  local win = {
    { match = has_page("EXP. Points"), delay = 20, file = "b3_gained_exp.png" },
    { match = has_page("grew to"), delay = 20, file = "b3_grew_to_lv.png" },
  }
  command({ kind = "move", move = st.player.mon.moves[1], slot = 1, user = "player" })
  run_until(function() return not Battle.isActive() end, win, 8000)
  result(win[1].taken and win[1].text:find("CHARMANDER gained", 1, true) ~= nil, "STRINGID_PKMNGAINEDEXP")
  result(win[2].taken and win[2].text:find("CHARMANDER grew to\nLV. 31!", 1, true) ~= nil, "STRINGID_PKMNGREWTOLV")

  for _, line in ipairs(Ui.log()) do print("  log: " .. tostring(line):gsub("\n", " ")) end
  if Battle.isActive() then Battle.abort("run") end
  print(string.format("battle flow rom text driver: %d failure(s)", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
