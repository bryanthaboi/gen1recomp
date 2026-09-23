local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_vs_seeker_bike_2419"

-- pokefirered/include/constants/items.h:434
local ITEM_VS_SEEKER = 362
local LASS_MEGAN, TWINS_ELI_ANNE = 130, 484
local IVYSAUR = 2
local FLAG_GOT_VS_SEEKER, FLAG_CELADON, FLAG_FUCHSIA = 0x292, 0x896, 0x897

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS vs_seeker_bike_2419")
    love.event.quit(0)
  else
    print("FAIL vs_seeker_bike_2419 failures=" .. failures)
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
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Player = require("src.core.game3.player")
  local VsSeeker = require("src.core.game3.vs_seeker")
  local OwSprites = require("src.core.game3.ow_sprites")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end

  session.party = {}
  Party.giveMon(session, IVYSAUR, 45)
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_VS_SEEKER, 1)
  local function setFlag(id) Flags.setFlag(Space.store, nil, id, true) end
  setFlag(FLAG_GOT_VS_SEEKER)
  setFlag(FLAG_CELADON)
  setFlag(FLAG_FUCHSIA)

  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  local mapId = (okC and MapCatalog.pretToEngine and MapCatalog.pretToEngine("Route8")) or "FR_ROUTE_8"
  Map.load(nil, game, mapId, { x = 40, y = 6, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 40, 6, "up"
  U.wait(90)
  session = Runtime.getSession()
  setFlag(Flags.trainerFlagId(LASS_MEGAN))
  setFlag(Flags.trainerFlagId(TWINS_ELI_ANNE))

  Player.biking = true
  U.wait(10)
  result(OwSprites.playerGraphicsId(game) == 1, "riding the bike (gid 1)")

  VsSeeker.setBattery(session, VsSeeker.MAX_CHARGE)
  local done = false
  local used, code = VsSeeker.use(session, game, function() done = true end)
  print("DIAG use=" .. tostring(used) .. " code=" .. tostring(code) .. " battery=" .. tostring(VsSeeker.getBattery(session)))

  local function poseNow()
    local gid = OwSprites.playerGraphicsId(game)
    local spr = OwSprites.getDraw(gid)
    local mf = OwSprites.fieldMoveFrame((Player.fieldMoveTotal or 0) - (Player.fieldMoveAnim or 0), Player.fieldMoveKind)
    local f = spr and OwSprites.pose(spr, Player.facing, 0, false, { fieldMove = true, fieldMoveFrame = mf })
    return gid, f, spr and spr.frameCount
  end

  U.wait(22)
  local gid, f, n = poseNow()
  result(Player.fieldMoveKind == "vs_seeker_bike", "VS Seeker started the bike anim (kind " .. tostring(Player.fieldMoveKind) .. ")")
  result(gid == 6 and n == 6, "male bike VS Seeker sheet gid 6 (got " .. tostring(gid) .. ", " .. tostring(n) .. " frames)")
  result(f == 4 or f == 5, "male raising the seeker on frame 4/5 (got " .. tostring(f) .. ")")
  U.shot(game, DIR .. "/2419_male_bike_vs_seeker.png")

  session.gender = "female"
  if game.save then game.save.gender = "female" end
  U.wait(8)
  gid, f, n = poseNow()
  result(gid == 13 and n == 6, "female bike VS Seeker sheet gid 13 (got " .. tostring(gid) .. ", " .. tostring(n) .. " frames)")
  result(f == 4 or f == 5, "female raising the seeker on frame 4/5 (got " .. tostring(f) .. ")")
  U.shot(game, DIR .. "/2419_female_bike_vs_seeker.png")

  for _ = 1, 600 do
    if done then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(1)
  end
  result(done, "VS Seeker sequence finished")
  result(OwSprites.playerGraphicsId(game) == 8, "back on the bike sheet afterwards (got " .. tostring(OwSprites.playerGraphicsId(game)) .. ")")
  finish()
end
