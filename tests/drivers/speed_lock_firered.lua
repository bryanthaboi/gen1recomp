local U = require("tests.drivers.util")
local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"

local UNION_ROOM = "FR_UNION_ROOM"
local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
-- pokefirered/data/specials.inc:12
local SET_CABLE_CLUB_WARP = 0x01
-- pokefirered/include/constants/vars.h:163
local VAR_CABLE_CLUB_STATE = 0x406F
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829

local function key(k)
  love.keypressed(k, k, false)
  love.keyreleased(k, k)
end

return function(game)
  local function fail(msg)
    error("FAIL speed lock: " .. msg, 0)
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  if game.phase ~= "field" then fail("never reached the field") end

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Union = require("src.core.game3.link.union_room")
  local o = game.options

  game.speedOverride = nil
  o.speedOverworld, o.speedBattle, o.speedMenu = 10, 4, 1
  U.wait(2)
  if game:logicSpeed() ~= 10 then
    fail(("field at OVERWORLD SPEED 10 reads %s"):format(tostring(game:logicSpeed())))
  end

  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 6, 50)
  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 2 }, { fade = false })
  if not ok then fail("wild battle did not start " .. tostring(err)) end

  local checked, shot = 0, false
  local Ui = require("src.core.game3.battle.ui")
  for f = 1, 20000 do
    if not Battle.isActive() then break end
    if game:logicSpeed() ~= 4 then
      fail(("local battle ran at %sX with speedBattle 4"):format(tostring(game:logicSpeed())))
    end
    checked = checked + 1
    if checked == 30 then
      local st = Battle.getState()
      st.link = true
      key("1")
      game:gamepadaxis(nil, "triggerright", 1)
      game:gamepadaxis(nil, "triggerright", 0)
      if o.speedOverworld ~= 10 or o.speedBattle ~= 4 or o.speedMenu ~= 1 then
        fail(("speed presses in a link battle changed options (%s/%s/%s)"):format(
          tostring(o.speedOverworld), tostring(o.speedBattle), tostring(o.speedMenu)))
      end
      game.speedOverride = 200
      if game:logicSpeed() ~= 1 then fail("a link battle was not locked to 1X") end
      game.speedOverride = nil
      st.link = false
    end
    if checked == 200 and not shot then
      shot = U.shot(game, DIR .. "/firered_battle_speed.png")
    end
    local st = Battle.getState and Battle.getState()
    if st and Battle._phase == "command" and Ui._mode == "menu" and not Ui._pendingCommand then
      local mon = st.player.mon
      mon.moves[1] = 33
      mon.pp = mon.pp or {}
      mon.pp[1] = 10
      st.enemy.mon.hp = 1
      Ui._pendingCommand = { kind = "move", move = 33, slot = 1, user = "player" }
      Ui._mode = "none"
      U.wait(1)
    elseif f % 14 == 0 then
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  if Battle.isActive() then
    fail(("battle never ended (phase %s, ui %s)"):format(tostring(Battle._phase), tostring(Ui._mode)))
  end
  U.log("battle frames checked at 4X", checked)
  U.wait(120)
  if game:logicSpeed() ~= 10 then
    fail(("after the battle logic speed is %s, want 10"):format(tostring(game:logicSpeed())))
  end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end
  -- pokefirered/data/scripts/cable_club.inc:743
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  Map.load(nil, game, CENTER_2F, { x = 5, y = 2, facing = "up" })
  place(5, 2, "up")
  U.wait(60)
  if game:logicSpeed() ~= 10 then
    fail(("the cable club counter room reads %s, want 10"):format(tostring(game:logicSpeed())))
  end
  place(5, 1, "up")
  U.wait(10)
  local Natives = require("src.core.game3.scripting.natives")
  Natives.special(ctx(), SET_CABLE_CLUB_WARP, Space.vm and Space.vm.adapters)
  Flags.setVar(Space.store, ctx(), VAR_CABLE_CLUB_STATE, 6)
  Map.load(nil, game, UNION_ROOM, { x = 7, y = 11, facing = "up" })
  place(7, 11, "up")
  local seen = 0
  for _ = 1, 120 do
    U.wait(1)
    if game:logicSpeed() ~= 1 then
      fail(("the Union Room ran at %sX with OVERWORLD SPEED 10"):format(tostring(game:logicSpeed())))
    end
    seen = seen + 1
  end
  if not Union.isActive() then U.log("note: union session not active, locked by map") end
  key("1")
  game:gamepadaxis(nil, "triggerright", 1)
  game:gamepadaxis(nil, "triggerright", 0)
  if o.speedOverworld ~= 10 then
    fail(("speed presses in the Union Room moved OVERWORLD SPEED to %s"):format(tostring(o.speedOverworld)))
  end
  U.shot(game, DIR .. "/firered_union_locked.png")
  U.log("union room frames checked at 1X", seen, "union state", tostring(Union.state))
  U.log("PASS firered local battle at BATTLE SPEED 4, link battle and Union Room locked to 1X")
  love.event.quit(0)
end
