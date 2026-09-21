local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_cerulean_block_exits"

local CITY = "FR_CERULEAN_CITY"
local HOUSE2 = "FR_CERULEAN_CITY_HOUSE2"
local ROUTE4 = "FR_ROUTE_4"

local LID_POLICEMAN, LID_GRUNT, LID_SLOWBRO, LID_LASS = 1, 2, 5, 6
local FLAG_GOT_SS_TICKET = 0x234
local FLAG_GOT_SS_TICKET_DUP = 0x235
local FLAG_HELPED_BILL = 0x233
local FLAG_HIDE_NUGGET_BRIDGE_ROCKET = 0x31
local FLAG_SYS_NOT_SOMEONES_PC = 0x834
local FLAG_BADGE02_GET = 0x821
local FLAG_HIDE_CERULEAN_ROCKET = 0x3B
local VAR_MAP_SCENE_CERULEAN_CITY_ROCKET = 0x407D
local TRAINER_TEAM_ROCKET_GRUNT_5 = 355

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS cerulean_softlock")
    love.event.quit(0)
  else
    print("FAIL cerulean_softlock failures=" .. failures)
    love.event.quit(1)
  end
end

local function posOf(Objects, lid)
  local eo = Objects.find(lid)
  if not eo then return nil end
  return eo.cellX, eo.cellY, eo
end

local function report(Objects, tag)
  for _, row in ipairs({ { LID_POLICEMAN, "policeman" }, { LID_SLOWBRO, "slowbro" },
                         { LID_LASS, "lass" }, { LID_GRUNT, "grunt" } }) do
    local x, y, eo = posOf(Objects, row[1])
    print(string.format("[driver] %s %s = (%s,%s) hidden=%s visible=%s",
      tag, row[2], tostring(x), tostring(y),
      tostring(eo and eo.hidden), tostring(eo and eo.visible)))
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
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function setFlag(id, on)
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, id, on ~= false)
  end
  local function getFlag(id)
    return Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, id)
  end
  local function setVar(id, v)
    Flags.setVar(Space.store, Space.vm and Space.vm.ctx, id, v)
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  goTo(CITY, 30, 14, "up")
  report(Objects, "no-ticket")
  local px, py = posOf(Objects, LID_POLICEMAN)
  result(px == 30 and py == 12,
    string.format("no ticket: ON_TRANSITION BlockExits put the cop at (30,12), got (%s,%s)",
      tostring(px), tostring(py)))
  local sx, sy = posOf(Objects, LID_SLOWBRO)
  local lx, ly = posOf(Objects, LID_LASS)
  result(sx == 26 and sy == 31 and lx == 27 and ly == 31,
    string.format("no ticket: slowbro/lass block the Route 5 road, got (%s,%s)/(%s,%s)",
      tostring(sx), tostring(sy), tostring(lx), tostring(ly)))
  U.shot(game, DIR .. "/cerulean_01_no_ticket_cop_at_door.png")

  -- pret Route25_SeaCottage/scripts.inc:101-105 and :157.
  setFlag(FLAG_BADGE02_GET)
  setFlag(FLAG_HELPED_BILL)
  setFlag(FLAG_GOT_SS_TICKET_DUP)
  setFlag(FLAG_HIDE_NUGGET_BRIDGE_ROCKET)
  setFlag(FLAG_GOT_SS_TICKET)
  setFlag(FLAG_SYS_NOT_SOMEONES_PC)
  result(getFlag(FLAG_GOT_SS_TICKET) == true, "FLAG_GOT_SS_TICKET reads back set")

  goTo(ROUTE4, 20, 6, "down")
  goTo(CITY, 30, 14, "up")
  report(Objects, "with-ticket")
  px, py = posOf(Objects, LID_POLICEMAN)
  local copMoved = (px == 31 and py == 12)
  result(copMoved,
    string.format("DOES THE COP MOVE: want (31,12) got (%s,%s)", tostring(px), tostring(py)))
  sx, sy = posOf(Objects, LID_SLOWBRO)
  lx, ly = posOf(Objects, LID_LASS)
  result(sx == 32 and sy == 29 and lx == 33 and ly == 29,
    string.format("slowbro/lass cleared the Route 5 road, got (%s,%s)/(%s,%s)",
      tostring(sx), tostring(sy), tostring(lx), tostring(ly)))
  U.shot(game, DIR .. "/cerulean_02_with_ticket_cop_aside.png")

  result(not Objects.blocks(30, 12), "the house-door tile (30,12) is not blocked by an NPC")
  result(Collision.canEnter(game, 30, 12, {}) ~= false, "collision lets the player onto (30,12)")
  result(Collision.warpAt(30, 11) ~= nil, "a warp exists on the house door (30,11)")

  U.hold(game, "up", 40)
  U.wait(20)
  U.hold(game, "up", 40)
  U.wait(60)
  print(string.format("[driver] after walking up: map=%s player=(%d,%d)",
    tostring(Map.current), Player.cellX, Player.cellY))
  local inHouse = (Map.current == HOUSE2)
  result(inHouse, "walked north through the cop into the burgled house (" ..
    tostring(Map.current) .. ")")
  U.shot(game, DIR .. "/cerulean_03_inside_house.png")

  if not inHouse then
    goTo(HOUSE2, 4, 7, "up")
  end
  local backWarp = nil
  do
    local def = Map._def or Map._currentDef
    local warps = (def and def.warps) or {}
    for i, w in ipairs(warps) do
      print(string.format("[driver] house2 warp %d = (%s,%s) -> %s",
        i, tostring(w.x), tostring(w.y), tostring(w.destMap or w.dest_map)))
      if tonumber(w.y) and tonumber(w.y) <= 1 then backWarp = w end
    end
  end
  result(backWarp ~= nil, "the burgled house has a back door warp")
  if backWarp then
    goTo(HOUSE2, tonumber(backWarp.x), tonumber(backWarp.y) + 1, "up")
    U.hold(game, "up", 40)
    U.wait(60)
    print(string.format("[driver] after back door: map=%s player=(%d,%d)",
      tostring(Map.current), Player.cellX, Player.cellY))
    result(Map.current == CITY, "back door dropped the player back into Cerulean City")
    U.shot(game, DIR .. "/cerulean_04_behind_house.png")
  end

  goTo(CITY, 31, 8, "up")
  report(Objects, "yard")
  local gx, gy, grunt = posOf(Objects, LID_GRUNT)
  result(grunt ~= nil and not grunt.hidden,
    string.format("the Rocket grunt is present in the yard at (%s,%s) hidden=%s",
      tostring(gx), tostring(gy), tostring(grunt and grunt.hidden)))
  result(getFlag(FLAG_HIDE_CERULEAN_ROCKET) ~= true,
    "FLAG_HIDE_CERULEAN_ROCKET is clear so the grunt can spawn")
  U.shot(game, DIR .. "/cerulean_05_yard_grunt.png")

  Flags.setTrainerDefeated(Space.store, session, TRAINER_TEAM_ROCKET_GRUNT_5, true)
  setVar(VAR_MAP_SCENE_CERULEAN_CITY_ROCKET, 1)
  goTo(ROUTE4, 20, 6, "down")
  goTo(CITY, 31, 8, "up")
  report(Objects, "yard-after-defeat")
  U.shot(game, DIR .. "/cerulean_06_yard_after_defeat.png")

  goTo(CITY, 26, 30, "down")
  result(not Objects.blocks(26, 31) and not Objects.blocks(27, 31),
    "the Route 5 road tiles (26,31)/(27,31) are clear of NPCs")
  result(Objects.blocks(26, 32), "the Cut tree still guards (26,32) as on the cart")
  goTo(CITY, 39, 30, "down")
  for _ = 1, 8 do
    U.hold(game, "down", 60)
    U.wait(20)
    if Map.current ~= CITY then break end
  end
  U.wait(60)
  print(string.format("[driver] after walking south: map=%s player=(%d,%d)",
    tostring(Map.current), Player.cellX, Player.cellY))
  result(Player.cellY >= 33 or Map.current ~= CITY,
    string.format("walked south out of the plaza, y=%d map=%s",
      Player.cellY, tostring(Map.current)))
  U.shot(game, DIR .. "/cerulean_07_route5.png")

  goTo(CITY, 30, 14, "up")
  px, py = posOf(Objects, LID_POLICEMAN)
  result(px == 31 and py == 12,
    string.format("re-entry keeps the cop aside, got (%s,%s)", tostring(px), tostring(py)))
  U.shot(game, DIR .. "/cerulean_08_reentry.png")

  finish()
end
