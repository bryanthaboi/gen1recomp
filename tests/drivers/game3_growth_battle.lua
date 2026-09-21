local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_growth_battle"

local CHARMANDER, MAGIKARP = 4, 129
local MOVE_SCRATCH = 10
local MOVE_SPLASH = 150

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS growth_battle")
    love.event.quit(0)
  else
    print("FAIL growth_battle failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.party = {}
  Party.giveMon(session, CHARMANDER, 2)
  local mine = session.party[1]
  if not result(mine ~= nil, "party holds CHARMANDER") then return finish() end
  result(Pokemon.evCount(mine) == 0, "it starts on 0 EVs")
  local beforeFriendship = Pokemon.friendshipOf(mine)
  local beforeLevel = tonumber(mine.level)
  result(Pokemon.evYield(MAGIKARP).spe == 1, "MAGIKARP's ROM yield is 1 SPEED EV")

  local ok, err = BattleBridge.startWild(Runtime._mod, game,
    { species = MAGIKARP, level = 30 }, { fade = false })
  if not result(ok == true, "wild MAGIKARP battle started " .. tostring(err or "")) then
    return finish()
  end

  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local lastTap = 0
  local f = 0
  local shotTaken = false
  for i = 1, 9000 do
    f = f + 1
    if i % 600 == 0 then
      local s = Battle.getState()
      print(string.format("[driver] i=%d phase=%s uiMode=%s ehp=%s php=%s",
        i, tostring(Battle._phase), tostring(Ui._mode),
        tostring(s and s.enemy and s.enemy.mon and s.enemy.mon.hp),
        tostring(s and s.player and s.player.mon and s.player.mon.hp)))
    end
    if not Battle.isActive() then break end
    if at_command() then
      if not shotTaken then
        shotTaken = true
        U.shot(game, DIR .. "/growth_battle_01_command.png")
      end
      local est = Battle.getState() and Battle.getState().enemy
      if est and est.mon then
        est.mon.moves = { MOVE_SPLASH, 0, 0, 0 }
        est.mon.pp = { 40, 0, 0, 0 }
        est.mon.hp = 1
        local ep = Anim.present("enemy")
        if ep then ep.displayHp = est.mon.hp end
      end
      local pm = Battle.getState() and Battle.getState().player
      if pm and pm.mon then
        pm.mon.moves = pm.mon.moves or {}
        pm.mon.moves[1] = MOVE_SCRATCH
        pm.mon.pp = pm.mon.pp or {}
        pm.mon.pp[1] = 35
      end
      Ui._pendingCommand = { kind = "move", move = MOVE_SCRATCH, slot = 1, user = "player" }
      Ui._mode = "none"
      U.wait(2)
    elseif Anim.vm() and Anim.vm():busy() then
      U.wait(1)
    elseif f - lastTap >= 12 then
      lastTap = f
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  if not result(not Battle.isActive(), "the battle ended") then return finish() end

  U.wait(120)
  local after = session.party[1]
  result(after ~= nil and tonumber(after.species or after.speciesId) == CHARMANDER,
    "CHARMANDER is still slot 1 after the writeback")
  local evs = after and after.evs or {}
  result(tonumber(evs.spe) == 1,
    "MonGainEVs gave 1 SPEED EV and it survived into the save ("
      .. tostring(evs.spe) .. ")")
  result(Pokemon.evCount(after) == 1, "and nothing else moved")
  local grew = (tonumber(after.level) or 0) > beforeLevel
  if grew then
    result(Pokemon.friendshipOf(after) > beforeFriendship,
      "FRIENDSHIP_EVENT_GROW_LEVEL fired on the level up ("
        .. tostring(beforeFriendship) .. " -> " .. tostring(Pokemon.friendshipOf(after)) .. ")")
  else
    result(Pokemon.friendshipOf(after) == beforeFriendship,
      "no level up, so friendship is unchanged")
  end

  finish()
end
