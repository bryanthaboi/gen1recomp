local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_gym_leader_intro_music"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_gym_leader_intro_music")
    love.event.quit(0)
  else
    print("FAIL game3_gym_leader_intro_music failures=" .. failures)
    love.event.quit(1)
  end
end

local ENCOUNTER = { [283] = true, [284] = true, [285] = true }

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Party = require("src.core.game3.party")
  local Audio = require("src.core.game3.audio")
  local Battle = require("src.core.game3.battle")
  local Objects = require("src.core.game3.objects")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")
  local MapCatalog = require("src.import.gba.map_catalog")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.party = {}
  Party.giveMon(session, 6, 100)

  local gym = MapCatalog.pretToEngine("PewterCity_Gym")
  Map.load(nil, game, gym, { x = 6, y = 6, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 6, 6, "up"
  U.wait(60)
  result(Map.current == gym, "loaded " .. tostring(gym))
  if not result(Objects.find(1) ~= nil, "Brock is in the gym") then return finish() end
  local before = Audio.currentSong() and Audio.currentSong().id
  result(before ~= nil and not ENCOUNTER[before], "gym BGM playing before the talk (" .. tostring(before) .. ")")

  U.tap(game, "a")
  local intro = false
  for _ = 1, 400 do
    if Message.isOpen() then intro = true break end
    U.wait(2)
  end
  if result(intro, "Brock's intro speech opened") then
    U.wait(30)
    local during = Audio.currentSong() and Audio.currentSong().id
    result(during == before, "NO_MUSIC mode keeps the gym BGM through the intro (" .. tostring(during) .. ")")
    Message.skipReveal()
    U.wait(4)
    result(U.shot(game, DIR .. "/spec_brock_intro_gym_bgm.png"), "screenshot spec_brock_intro_gym_bgm")
  end
  local started = false
  for _ = 1, 900 do
    if Battle.isActive() then started = true break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(2)
  end
  result(started, "Brock's battle still starts")
  return finish()
end
