local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_gym_music"

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
  local Audio = require("src.core.game3.audio")
  local Trainers = require("src.core.game3.scripting.trainers")
  local Ui = require("src.core.game3.battle.ui")

  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 6, 100)

  local lastTap = 0
  local function pump_text(f)
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 12 then
      lastTap = f
      U.tap(game, "a")
      return true
    end
    return false
  end

  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local function run_fight(trainerId, label, wantBgm, shotFile)
    local foe = Trainers.foeFromId(trainerId)
    if not foe then
      result(false, label .. " trainer row missing from cache")
      return nil
    end
    local ok, err = BattleBridge.start(Runtime._mod, game, foe,
      { wild = false, trainerId = trainerId, fade = false })
    result(ok == true, label .. " battle started " .. tostring(err or ""))
    if not ok then return nil end

    local cur = Audio.currentSong()
    local gotStart = cur and cur.id
    result(gotStart == wantBgm,
      string.format("%s transition BGM %s (want %d)", label, tostring(gotStart), wantBgm))

    local f = 0
    for _ = 1, 20000 do
      f = f + 1
      if at_command() then break end
      if not pump_text(f) then U.wait(1) end
    end
    local reached = at_command()
    result(reached, label .. " reached command menu")

    cur = Audio.currentSong()
    local gotBattle = cur and cur.id
    result(gotBattle == wantBgm,
      string.format("%s in-battle BGM %s (want %d)", label, tostring(gotBattle), wantBgm))
    if shotFile and reached and gotBattle == wantBgm then
      U.shot(game, DIR .. "/" .. shotFile)
      print("shot " .. shotFile)
    end
    return f
  end

  local function win_now(label, wantVictory)
    local st = Battle.getState()
    if not st then
      result(false, label .. " no battle state")
      return
    end
    st.player.mon.moves = { 10, 0, 0, 0 }
    st.player.mon.pp = { 60, 0, 0, 0 }

    local seen = nil
    local f = 0
    for _ = 1, 12000 do
      f = f + 1
      for _, m in ipairs(st.foeParty or {}) do
        m.maxHp = math.max(1, m.maxHp or 1)
        m.hp = math.min(m.hp or 1, 1)
      end
      st.enemy.mon.hp = math.min(st.enemy.mon.hp or 1, 1)
      st.player.mon.hp = st.player.mon.maxHp
      if at_command() then
        st.player.mon.pp[1] = 60
        Ui._pendingCommand = { kind = "move", move = 10, slot = 1, user = "player" }
        Ui._mode = "none"
      end
      if Battle._pendingEnd == "win" and not seen then
        local cur = Audio.currentSong()
        seen = cur and cur.id
      end
      if not Battle.isActive() then break end
      local LM = package.loaded["src.core.game3.battle.learn_move"]
      local PM = package.loaded["src.ui.game3.party_menu"]
      if PM and PM.isOpen and PM.isOpen() then
        U.wait(10)
        U.tap(game, "b")
        U.wait(10)
      elseif Ui.choiceActive and Ui.choiceActive() then
        U.wait(6)
        U.tap(game, "b")
        U.wait(6)
      elseif LM and LM.waitingChoice and LM.waitingChoice() then
        U.wait(10)
        U.tap(game, "b")
        U.wait(10)
      elseif not pump_text(f) then
        U.wait(1)
      end
      if f % 900 == 0 then
        print(string.format("  %s waiting phase=%s mode=%s ehp=%s pend=%s",
          label, tostring(Battle._phase), tostring(Ui._mode),
          tostring(st.enemy.mon.hp), tostring(Battle._pendingEnd)))
      end
    end
    result(seen == wantVictory,
      string.format("%s victory jingle %s (want %d)", label, tostring(seen), wantVictory))
  end

  if run_fight(414, "LEADER BROCK", 296, "2303_01_brock_gym_bgm.png") then
    win_now("LEADER BROCK", 312)
  end
  Battle.abort("win")
  U.wait(90)

  session.party = {}
  Party.giveMon(session, 6, 100)
  if run_fight(410, "ELITE FOUR LORELEI", 296, "2303_02_lorelei_gym_bgm.png") then
    win_now("ELITE FOUR LORELEI", 310)
  end
  Battle.abort("win")
  U.wait(90)

  session.party = {}
  Party.giveMon(session, 6, 100)
  if run_fight(438, "CHAMPION TERRY", 299, "2303_03_champion_bgm.png") then
    win_now("CHAMPION TERRY", 312)
  end
  Battle.abort("win")
  U.wait(90)

  session.party = {}
  Party.giveMon(session, 6, 100)
  if run_fight(326, "RIVAL OAKS LAB", 297, nil) then
    win_now("RIVAL OAKS LAB", 310)
  end
  Battle.abort("win")
  U.wait(60)

  print(string.format("gym music driver: %d failure(s)", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
