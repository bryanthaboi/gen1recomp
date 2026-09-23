local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchimp_chrome_keys"

local PALLET = "FR_PALLET_TOWN"
local FLY = 19
local FLAG_BADGE03_GET = 0x822
local TOWNS = {
  { "FR_VIRIDIAN_CITY", 23, 28 },
  { "FR_PEWTER_CITY", 17, 26 },
  { "FR_CERULEAN_CITY", 22, 20 },
  { "FR_VERMILION_CITY", 21, 32 },
  { "FR_LAVENDER_TOWN", 8, 6 },
}

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchimp_chrome_keys")
    love.event.quit(0)
  else
    print("FAIL stitchimp_chrome_keys failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Field = require("src.core.game3.field")
  local FieldMoves = require("src.core.game3.field_moves")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local RegionMap = require("src.ui.game3.region_map")
  local SummaryChrome = require("src.ui.game3.summary_chrome")
  local CacheContract = require("src.import.CacheContract")
  local CacheFs = require("src.import.CacheFs")
  local Versions = require("src.import.gba.versions")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  result(CacheContract.cacheVersionCurrent("firered", CacheFs) == true,
    "the mounted cache is at Versions.CACHE_VERSION (" .. tostring(Versions.CACHE_VERSION) .. ")")
  local complete, missing = CacheContract.allRequiredFilesExist("firered", CacheFs)
  result(complete == true, "every firered required file is in the mounted cache"
    .. (complete and "" or ", missing " .. tostring(missing)))

  local function placeAt(mapId, x, y)
    Map.load(nil, game, mapId, { x = x, y = y, facing = "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.targetX, Player.targetY = x, y
    U.wait(60)
  end

  for _, town in ipairs(TOWNS) do
    placeAt(town[1], town[2], town[3])
  end
  placeAt(PALLET, 10, 6)
  result(RegionMap.isFlagSet("FLAG_WORLD_MAP_PEWTER_CITY") == true,
    "walking into the towns ran their setworldmapflag")

  -- pokefirered/src/party_menu.c:4118 FLY needs FLAG_BADGE03_GET
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_BADGE03_GET, true)
  if #(session.party or {}) == 0 then Party.giveMon(session, 18, 40) end
  local flyer = session.party[1]
  flyer.moves = { FLY }
  result(FieldMoves.partyMoveUser(session.party, "FLY") ~= nil, "the lead knows FLY")

  local mapDef = Map.currentDef()
  local res = FieldMoves.fromMenu(FLY, {
    party = session.party,
    mon = flyer,
    store = Space.store,
    session = session,
    facing = Player.facing,
    mapType = mapDef and mapDef.mapType,
  })
  if not result(res ~= nil and res.ok == true and res.action == "fly",
    "the party menu offers FLY on Pallet Town") then
    return finish()
  end

  Field.executeFieldMove(res)
  U.wait(60)
  if not result(RegionMap.isOpen() == true, "FLY opened the region map") then return finish() end
  result(RegionMap.isFlyMode() == true, "the region map is in fly mode")

  local targets = RegionMap.flyTargets()
  result(#targets >= 5, "the visited towns are fly targets (" .. #targets .. ")")
  result(RegionMap._images and RegionMap._images["fly_icon"] ~= false,
    "the fly icon loaded out of the cache")

  for _ = 1, 90 do
    if RegionMap.flyIconFrame() == 0 then break end
    U.wait(1)
  end
  result(RegionMap.flyIconFrame() == 0, "the fly icon is on its first animation frame")
  result(U.shot(game, DIR .. "/stitchimp_chrome_keys_01_fly_map.png"), "screenshot of the fly map")

  for _ = 1, 40 do
    if not RegionMap.isOpen() then break end
    U.tap(game, "b")
    U.wait(8)
  end
  U.wait(30)

  -- src/pokemon_summary_screen.c:4800, :4830, :4716
  local coords = (SummaryChrome.manifest() or {}).coords or {}
  local function coordIs(key, x, y)
    local c = coords[key]
    result(c ~= nil and c.x == x and c.y == y, "summary coords." .. key .. " is ("
      .. x .. "," .. y .. "), got " .. (c and (tostring(c.x) .. "," .. tostring(c.y)) or "nil"))
  end
  coordIs("shinyStar", 102, 36)
  coordIs("shinyStarMovesInfo", 4, 20)
  coordIs("pokerus", 110, 88)

  -- src/battle_interface.c:615 CreateSafariPlayerHealthboxSprites
  local raw = CacheFs.readActive("data/generated/gba/pokemon/battle/healthbox_safari.rgba")
  result(type(raw) == "string" and #raw == 128 * 64 * 4,
    "the cache carries the 128x64 safari healthbox sheet")
  if type(raw) == "string" and #raw == 128 * 64 * 4 then
    local data = love.image.newImageData(128, 64, "rgba8", raw)
    local _, _, _, a = data:getPixel(56, 24)
    result(a > 0, "the safari sheet has an opaque pixel inside the box frame")
  end

  finish()
end
