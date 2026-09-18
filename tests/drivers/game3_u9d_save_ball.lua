local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

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
  local Schema = require("src.core.game3.save_schema_firered")
  local SaveData = require("src.core.SaveData")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local BallOpen = require("src.core.game3.battle.ball_open")

  local function reload(ball)
    local session = Runtime.getSession()
    session.party = {}
    Party.giveMon(session, 4, 5)
    session.party[1].pokeball = ball
    local str = SaveData.encode(Schema.toSaveTable(session))
    local loaded = Schema.fromSaveTable(SaveData.decode(str))
    game:_enterField(loaded, "continue")
    U.wait(120)
    return Runtime.getSession()
  end

  local function waitOpen(maxFrames)
    for _ = 1, maxFrames do
      if BallOpen._mon.player and BallOpen.particleCount() > 0 then return true end
      if Ui.dialogPending and Ui.dialogPending() then
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return false
  end

  local function sendOut(prefix, wantItem, wantBallId, shots)
    local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
    result(ok == true, prefix .. " wild battle started " .. tostring(err or ""))
    if not ok then return end
    local pm = Battle._st and Battle._st.player and Battle._st.player.mon
    result(pm and pm.pokeball == wantItem, prefix .. " battler mon ball item=" .. tostring(pm and pm.pokeball))
    local opened = waitOpen(1500)
    result(opened, prefix .. " player ball opened")
    if opened then
      local m = BallOpen._mon.player
      result(m.ballId == wantBallId, prefix .. " ball-open ballId=" .. tostring(m.ballId))
      local d = BallOpen.data()
      local want = d and d.fadeColors and d.fadeColors[wantBallId + 1]
      local c, r, g, b = BallOpen.monBlend("player")
      result(want and c == 16 and r == want[1] and g == want[2] and b == want[3],
        prefix .. " mon blended to that ball's color " .. tostring(r) .. "," .. tostring(g) .. "," .. tostring(b))
      U.wait(3)
      U.shot(game, DIR .. "/" .. shots[1])
      U.wait(10)
      U.shot(game, DIR .. "/" .. shots[2])
    end
    Battle.abort("win")
    U.wait(120)
    for _ = 1, 30 do U.tap(game, "a") U.wait(4) end
  end

  local s1 = reload(2)
  result(s1.party[1] and s1.party[1].pokeball == 2, "u9d save-loaded mon kept ITEM_ULTRA_BALL")
  sendOut("u9d ultra", 2, 3, { "u9d_01_save_loaded_ultra_ball_open.png", "u9d_02_save_loaded_ultra_particles.png" })

  local s2 = reload(nil)
  result(s2.party[1] and s2.party[1].pokeball == 4, "u9d old-save mon without a ball loads as ITEM_POKE_BALL")
  sendOut("u9d legacy", 4, 0, { "u9d_03_old_save_poke_ball_open.png", "u9d_04_old_save_poke_particles.png" })

  love.event.quit(fails == 0 and 0 or 1)
end
