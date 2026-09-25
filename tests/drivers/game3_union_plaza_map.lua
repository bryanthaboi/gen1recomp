local U = require("tests.drivers.util")
local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/union40/shots/map"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
-- pokefirered/data/specials.inc:12
local SET_CABLE_CLUB_WARP = 0x01
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829

return function(game)
  local function fail(msg)
    print("FAIL game3_union_plaza_map: " .. msg)
    love.event.quit(1)
    coroutine.yield()
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  if game.phase ~= "field" then return fail("never reached the field") end

  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Natives = require("src.core.game3.scripting.natives")
  local MapCatalog = require("src.import.gba.map_catalog")
  local Plaza = require("src.core.game3.link.union_plaza_map")

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

  local def = game.data and game.data.maps and game.data.maps[Plaza.MAP_ID]
  if not def then return fail("hydrate did not register " .. Plaza.MAP_ID) end

  -- pokefirered/data/scripts/cable_club.inc:743
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  Map.load(nil, game, CENTER_2F, { x = 5, y = 2, facing = "up" })
  place(5, 2, "up")
  U.wait(30)
  place(5, 1, "up")
  U.wait(10)
  Natives.special(ctx(), SET_CABLE_CLUB_WARP, Space.vm and Space.vm.adapters)
  local dw = game.session and game.session.dynamicWarp
  if not (dw and dw.map == CENTER_2F) then return fail("SetCableClubWarp did not record the way back") end

  local slot = MapCatalog.slotKeyFor("FR_UNION_ROOM") or ""
  local group, num = slot:match("(%d+)%D+(%d+)")
  group, num = tonumber(group), tonumber(num)
  if not (group and num) then return fail("no group/num for FR_UNION_ROOM (" .. slot .. ")") end

  local arrived = false
  -- pokefirered/data/scripts/cable_club.inc:797
  Space.vm.adapters.warp(group, num, 0xFF, 7, 11, function() arrived = true end, "warpspinenter")
  for _ = 1, 600 do
    if arrived and Map.current == Plaza.MAP_ID then break end
    U.wait(1)
  end
  if Map.current ~= Plaza.MAP_ID then
    return fail("warp to the Union Room landed on " .. tostring(Map.current))
  end
  local ex, ey = Plaza.entry()
  if Player.cellX ~= ex or Player.cellY ~= ey then
    return fail(("spawned at %s,%s want %d,%d"):format(tostring(Player.cellX), tostring(Player.cellY), ex, ey))
  end
  U.log("entered", Map.current, Player.cellX, Player.cellY)
  U.wait(120)
  U.still(game, DIR .. "/plaza_entrance.png")

  place(12, 18, "up")
  U.wait(30)
  U.still(game, DIR .. "/plaza_center.png")

  place(22, 3, "up")
  U.wait(30)
  U.still(game, DIR .. "/plaza_far_corner.png")

  place(3, 3, "up")
  U.wait(30)
  U.still(game, DIR .. "/plaza_counter.png")

  place(12, 22, "down")
  U.wait(30)
  U.hold(game, "down", 40)
  for _ = 1, 300 do
    if Map.current == CENTER_2F then break end
    U.wait(1)
  end
  if Map.current ~= CENTER_2F then
    return fail("exit landed on " .. tostring(Map.current) .. " want " .. CENTER_2F)
  end
  U.wait(60)
  U.still(game, DIR .. "/plaza_exit_center_2f.png")
  U.log("exit landed", Map.current, Player.cellX, Player.cellY)
  print("PASS game3_union_plaza_map")
  love.event.quit(0)
end
