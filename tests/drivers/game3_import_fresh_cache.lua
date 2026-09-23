local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import_fresh_cache"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS import_fresh_cache")
    love.event.quit(0)
  else
    print("FAIL import_fresh_cache failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  result(game.phase == "boot" and game.boot ~= nil,
    "the fresh cache booted past the launcher, phase=" .. tostring(game.phase))

  local Versions = require("src.import.gba.versions")
  local CacheContract = require("src.import.CacheContract")
  local CacheFs = require("src.import.CacheFs")

  result(type(Versions.CACHE_VERSION) == "number",
    "the importer is at cache version " .. tostring(Versions.CACHE_VERSION))
  result(CacheContract.cacheVersionCurrent("firered", CacheFs) == true,
    "the mounted cache is stamped at the current version")
  local complete, missing = CacheContract.allRequiredFilesExist("firered", CacheFs)
  result(complete == true,
    "every required key is in the mounted cache, missing=" .. tostring(missing))
  result(CacheContract.isReady("firered", CacheFs) == true,
    "CacheContract calls the mounted cache ready")

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Dataset = require("src.core.game3.dataset")
  local Player = require("src.core.game3.player")
  local Map = require("src.core.game3.map")
  local StartMenu = require("src.ui.game3.start_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  print("[driver] new game: map=" .. tostring(Map.current) ..
    " at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(Map.current ~= nil, "the player stands on a map, map=" .. tostring(Map.current))

  U.wait(30)
  result(U.shot(game, DIR .. "/import_fresh_cache_01_players_room.png"),
    "the bedroom shot reached disk")

  local function walkTo(tx, ty, limit)
    local stuck = 0
    for _ = 1, limit or 40 do
      local x, y = Player.cellX, Player.cellY
      if x == tx and y == ty then return true end
      local dir
      if x ~= tx and (stuck % 2 == 0 or y == ty) then
        dir = (tx > x) and "right" or "left"
      elseif y ~= ty then
        dir = (ty > y) and "down" or "up"
      else
        dir = (tx > x) and "right" or "left"
      end
      U.hold(game, dir, 12)
      for _ = 1, 20 do
        if not Player.moving then break end
        U.wait(2)
      end
      U.wait(4)
      if Player.cellX == x and Player.cellY == y then
        stuck = stuck + 1
        if stuck > 10 then return false end
      else
        stuck = 0
      end
    end
    return Player.cellX == tx and Player.cellY == ty
  end

  local function stepThrough(dir, id, tries)
    for _ = 1, tries or 12 do
      if Map.current == id then break end
      U.hold(game, dir, 12)
      U.wait(30)
    end
    U.wait(40)
    return Map.current == id
  end

  -- src/field_control_avatar.c:924
  walkTo(10, 2, 30)
  stepThrough("left", "FR_PLAYERS_HOUSE_1F", 10)
  print("[driver] down the stairs: map=" .. tostring(Map.current) ..
    " at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(Map.current == "FR_PLAYERS_HOUSE_1F",
    "the stairs warped to the ground floor, map=" .. tostring(Map.current))

  -- src/field_control_avatar.c:825
  walkTo(9, 8, 30)
  walkTo(4, 8, 30)
  stepThrough("down", "FR_PALLET_TOWN", 10)
  print("[driver] out the front door: map=" .. tostring(Map.current) ..
    " at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(Map.current == "FR_PALLET_TOWN",
    "the front door warped to Pallet Town, map=" .. tostring(Map.current))
  U.wait(30)
  result(U.shot(game, DIR .. "/import_fresh_cache_02_pallet_town.png"),
    "the Pallet Town shot reached disk")

  local cache = Dataset.cache()
  local function sized(rel)
    local ok, data = pcall(function() return cache:read("data/generated/gba/" .. rel) end)
    if ok and type(data) == "string" then return #data end
    return 0
  end
  -- src/text.c:227 the Japanese normal font
  result(sized("chrome/fonts/japanese_normal_fg.rgba") == 256 * 512 * 4,
    "the engine reads the Japanese font out of the fresh cache")
  -- src/braille_text.c:15
  result(sized("chrome/fonts/braille_fg.rgba") == 256 * 64 * 4,
    "the engine reads the braille sheet out of the fresh cache")
  -- src/seagallop.c:41
  result(sized("seagallop/wb.rgba") == 256 * 256 * 4,
    "the engine reads the seagallop water out of the fresh cache")
  -- src/pokedex_screen.c:2901
  result(sized("pokemon/pokedex/footprints/1.rgba") > 0,
    "the engine reads a dex footprint out of the fresh cache")
  -- src/script_menu.c:505
  result(sized("scripts/multichoice.lua") > 0,
    "the engine reads the multichoice lists out of the fresh cache")

  U.tap(game, "start")
  U.wait(45)
  result(StartMenu.isOpen(), "the start menu drew from the fresh cache chrome")
  result(U.shot(game, DIR .. "/import_fresh_cache_03_start_menu.png"),
    "the start menu shot reached disk")
  U.tap(game, "b")
  U.wait(20)

  finish()
end
