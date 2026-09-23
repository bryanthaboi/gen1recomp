local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_battle_rom_text"

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
            sh.taken = U.still(game, DIR .. "/" .. sh.file)
            print("shot " .. sh.file .. " text=" .. page():gsub("\n", " "))
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

  session.party = {}
  Party.giveMon(session, 6, 50)
  local lead = session.party[1]
  lead.item = 200
  lead.hp = math.floor(lead.maxHp / 2)

  local ok = BattleBridge.startWild(Runtime._mod, game,
    { species = 248, level = 50, ability = "SAND_STREAM", moves = { 150, 0, 0, 0 }, pp = { 40, 0, 0, 0 } },
    { fade = false })
  result(ok == true, "wild battle started")
  local intro = {
    { match = has_page("SAND STREAM"), delay = 30, file = "b1_sand_stream_wild_prefix.png" },
  }
  run_until(at_command, intro, 4000)
  result(intro[1].taken == true, "Wild TYRANITAR's SAND STREAM line shown")

  local st = Battle.getState()
  st.player.mon.speed, st.enemy.mon.speed = 200, 10
  local turn = {
    { match = has_page("used"), delay = 20, file = "b1_used_move.png" },
    { match = has_page("buffeted"), delay = 20, file = "b1_sandstorm_buffeted.png" },
    { match = has_page("LEFTOVERS"), delay = 20, file = "b1_leftovers_hp.png" },
  }
  Ui._pendingCommand = { kind = "move", move = st.player.mon.moves[1], slot = 1, user = "player" }
  Ui._mode = "none"
  run_until(function() return f > 10 and at_command() end, turn, 6000)
  for _, sh in ipairs(turn) do result(sh.taken == true, "shot " .. sh.file) end

  local sawWild = false
  for _, line in ipairs(Ui.log()) do
    print("  log: " .. tostring(line):gsub("\n", " "))
    if tostring(line):find("Wild TYRANITAR", 1, true) then sawWild = true end
  end
  result(sawWild, "wild foe named with the ROM Wild prefix")

  Battle.abort("run")
  for _ = 1, 120 do
    if not Battle.isActive() then break end
    U.wait(1)
  end
  print(string.format("battle rom text driver: %d failure(s)", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
