-- pokefirered/src/battle_bg.c:654
-- pokeruby/src/battle_bg.c:709
local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_entry_bg_2803", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_2803")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local game3 = require("src.core.game3.profile").forSession().id
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 1, 20)
  U.wait(30)
  S.check(Bridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false, terrain = 0 }) ~= nil,
    game3 .. " wild grass battle started")
  local e
  for _ = 1, 600 do
    e = Battle.isActive() and Anim.stage().entry
    if e then break end
    U.wait(1)
  end
  S.check(e and e.key == "grass" and e.kind == 1, game3 .. " grass entry layer armed")
  local shot = false
  for _ = 1, 200 do
    e = Anim.stage().entry
    if not e then break end
    if e.y <= -20 and not shot then shot = S.still(game, "2803_" .. game3 .. "_grass_entry.png") end
    U.wait(1)
  end
  S.check(shot, game3 .. " grass entry captured while sinking")
  S.check(Anim.stage().entry == nil, game3 .. " entry layer cleared after the slide")
  Battle.abort("run")
  for _ = 1, 600 do
    if not Battle.isActive() then break end
    U.wait(1)
  end
  S.finish()
end
