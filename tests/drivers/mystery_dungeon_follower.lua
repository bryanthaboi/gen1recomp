local U = require("tests.drivers.util")
local Version = require("src.core.GameVersion")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/mystery_dungeon_follower"

return function(game)
  local gen = Version.generation()
  if gen == 3 then
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    game:_handleBootAction({ action = "new_game", name = "RED" })
    U.wait(240)
    local Party = require("src.core.game3.party")
    game.session.party = {}
    Party.giveMon(game.session, 25, 20)
    Party.giveMon(game.session, 1, 20)
  else
    U.wait(60)
    local Pokemon = require(gen == 2 and "src.battle.gen2.Mon" or "src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "PIKACHU", 20), Pokemon.new(game.data, "BULBASAUR", 20) }
    if gen == 1 then U.teleport(game, "PALLET_TOWN", 9, 9, "down") end
  end
  local Follower = require(gen == 3 and "src.world.game3.Follower"
    or gen == 2 and "src.world.gen2.Follower" or "src.world.PikachuFollower")
  local world = game.overworld or game.world
  local function current() return Follower.current(world) end
  local function check(ok, message)
    assert(ok, message)
    print("PASS " .. message)
  end
  U.wait(30)
  check(current() and current().sprite and current().sprite.pmdTicks ~= nil, "imported lead follower spawned")
  local startX, startY = current().px, current().py
  local moved = false
  -- Walk a small loop inside the starting room; one blocked side is harmless.
  for _, direction in ipairs({"left", "down", "right", "up"}) do
    U.hold(game, direction, 36)
    U.wait(20)
    local npc = current()
    if npc and (npc.px ~= startX or npc.py ~= startY) then moved = true end
  end
  check(current() ~= nil, "follower survived walking")
  check(moved, "follower actually traversed the trail")
  check(U.shot(game, DIR .. "/" .. Version.get() .. "_pikachu.png"), "Pikachu screenshot saved")
  local save = game.session or game.save
  save.party[1], save.party[2] = save.party[2], save.party[1]
  U.wait(10)
  check(current().sprite.def.image:find("bulbasaur.png", 1, true), "party reorder changed follower to Bulbasaur")
  check(U.shot(game, DIR .. "/" .. Version.get() .. "_bulbasaur.png"), "Bulbasaur screenshot saved")
  local party = save.party
  save.party = {}
  U.wait(5)
  check(current() == nil, "empty party removed follower")
  save.party = party
  U.wait(10)
  check(current() ~= nil, "party restoration respawned follower")
  print("PASS Mystery Dungeon Follower " .. Version.get())
  love.event.quit(0)
end
