local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/bug2460"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_ghost_trainer_sight_2460")
    love.event.quit(0)
  else
    print("FAIL game3_ghost_trainer_sight_2460 failures=" .. failures)
    love.event.quit(1)
  end
end

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
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Ghosts = require("src.core.game3.ghosts")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Battle = package.loaded["src.core.game3.battle"] or require("src.core.game3.battle")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.party = {}
  Party.giveMon(session, 7, 40)

  local engaged = {}
  local allowReal = false
  local realEngage = TrainerSight.engage
  TrainerSight.engage = function(g, eo, dist)
    engaged[#engaged + 1] = { eo = eo, dist = dist, live = Objects.find(eo and eo.localId) == eo,
      script = eo and eo.scriptKey }
    print(string.format("[2460] engage lid=%s dist=%s live=%s script=%s", tostring(eo and eo.localId),
      tostring(dist), tostring(engaged[#engaged].live), tostring(eo and eo.scriptKey)))
    if allowReal then return realEngage(g, eo, dist) end
  end

  local function place(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    game.session.x, game.session.y, game.session.facing = x, y, facing
    U.wait(20)
  end

  local function ghostTrainers()
    local list = {}
    for mapId, pool in pairs(Ghosts._pools or {}) do
      for _, lid in ipairs(pool.order or {}) do
        local eo = pool.byId[lid]
        if eo and (tonumber(eo.sight) or 0) > 0 and TrainerSight.isTrainerType(eo) then
          list[#list + 1] = { mapId = mapId, eo = eo }
        end
      end
    end
    return list
  end

  local function dwell(label, mapId, spots, frames, needCover)
    engaged = {}
    local cover, pools = 0, 0
    for _, s in ipairs(spots) do
      place(mapId, s[1], s[2], s[3])
      local list = ghostTrainers()
      pools = math.max(pools, #list)
      for _ = 1, frames do
        U.wait(1)
        if Player.cellX ~= s[1] or Player.cellY ~= s[2] then Player.reset(s[1], s[2], s[3]) end
        for _, t in ipairs(ghostTrainers()) do
          if not t.eo.hidden and TrainerSight.checkLineOfSight(t.eo, Player, game) then
            cover = cover + 1
          end
        end
      end
    end
    print(string.format("[2460] %s: %d neighbor-map trainers ticking, %d frames a ghost cone covered the player",
      label, pools, cover))
    result(pools > 0, label .. ": neighbor-map trainers are loaded and ticking")
    if needCover then
      result(cover > 0, label .. ": a neighbor-map trainer's local cone lined up with the player")
    end
    result(#engaged == 0, label .. ": no neighbor-map trainer engaged (engages=" .. #engaged .. ")")
    result(not Field.locked and not (Battle.isActive and Battle.isActive()), label .. ": field unlocked, no battle")
  end

  place("FR_VERMILION_CITY", 28, 12, "up")
  U.still(game, DIR .. "/2460_01_vermilion_under_dave_ghost.png")
  dwell("Vermilion vs Route 11 Dave", "FR_VERMILION_CITY",
    { { 28, 12, "up" }, { 29, 14, "up" }, { 28, 14, "up" } }, 400, true)
  U.still(game, DIR .. "/2460_02_vermilion_mart_no_engage.png")

  dwell("Fuchsia vs Route 17/18 bikers", "FR_FUCHSIA_CITY",
    { { 11, 17, "up" }, { 11, 19, "up" }, { 4, 20, "up" } }, 400, true)
  U.still(game, DIR .. "/2460_03_fuchsia_no_engage.png")

  engaged = {}
  allowReal = true
  place("FR_ROUTE_11", 28, 12, "up")
  local dave = Objects.find(4)
  result(dave ~= nil and dave.sight == 1 and TrainerSight.isTrainerType(dave),
    "control: Route 11 Dave (localId 4) loaded as a current-map trainer")
  local spotted = false
  for _ = 1, 1200 do
    if #engaged > 0 then spotted = true break end
    U.wait(1)
  end
  result(spotted and engaged[1].live and engaged[1].eo == dave and engaged[1].dist == 1,
    "control: Dave on Route 11 still spots the player after a pacing step")
  if spotted then
    U.wait(10)
    U.still(game, DIR .. "/2460_04_route11_dave_spots_player.png")
  end
  return finish()
end
