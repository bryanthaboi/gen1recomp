local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import2_fresh_cache"

local PALLET = "FR_PALLET_TOWN"
local BEDROOM = "FR_PLAYERS_HOUSE_2F"
local HOUSE_1F = "FR_PLAYERS_HOUSE_1F"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS import2_fresh_cache")
    love.event.quit(0)
  else
    print("FAIL import2_fresh_cache failures=" .. failures)
    love.event.quit(1)
  end
end

local ROUND2_SAMPLE = {
  "data/generated/gba/slot_machine/reel_icons.rgba",
  "data/generated/gba/slot_machine/bg.rgba",
  "data/generated/gba/trade/gba_screen.rgba",
  "data/generated/gba/trade/ball.rgba",
  "data/generated/gba/union_room/chat_bg.rgba",
  "data/generated/gba/wireless_status/bg.rgba",
  "data/generated/gba/fame_checker/bg.rgba",
  "data/generated/gba/fame_checker/0.rgba",
  "data/generated/gba/teachy_tv/screen.rgba",
  "data/generated/gba/mystery_gift/card_bg0.rgba",
  "data/generated/gba/trainer_tower.lua",
  "data/generated/gba/trainer_tower/records_bg.rgba",
  "data/generated/gba/pokemon/tutor.lua",
  "data/generated/gba/museum/kabutops.rgba",
  "data/generated/gba/museum/aerodactyl.rgba",
  "data/generated/gba/region_map/dungeon_icon_visited.rgba",
  "data/generated/gba/move_relearner/bg.rgba",
  "data/generated/gba/pokemon/egg/hatch.rgba",
  "data/generated/gba/pokemon/front/412.rgba",
  "data/generated/gba/pokemon/icons/412.rgba",
  "data/generated/gba/native/layouts/alt_366.mid",
}

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  local Versions = require("src.import.gba.versions")
  local CacheContract = require("src.import.CacheContract")
  local CacheFs = require("src.import.CacheFs")
  local Dataset = require("src.core.game3.dataset")

  local meta = CacheFs.readActive("data/generated/gba/meta.json")
  if not result(type(meta) == "string", "the mounted cache has a meta.json") then
    return finish()
  end
  local stampedCache = tonumber(meta:match('"cache_version"%s*:%s*(%d+)'))
  local stampedNative = tonumber(meta:match('"native_version"%s*:%s*(%d+)'))
  print("[driver] meta cache_version=" .. tostring(stampedCache)
    .. " native_version=" .. tostring(stampedNative)
    .. " importer=" .. tostring(Versions.CACHE_VERSION) .. "/"
    .. tostring(Versions.NATIVE_VERSION))
  result(stampedCache == Versions.CACHE_VERSION,
    "the booted cache is stamped at the importer's cache version")
  result(stampedNative == Versions.NATIVE_VERSION,
    "the booted cache is stamped at the importer's native version")
  result(CacheContract.cacheVersionCurrent("firered") == true,
    "the engine's own staleness gate accepts this cache")

  local complete, missing = CacheContract.allRequiredFilesExist("firered")
  result(complete == true,
    "zero missing required keys, first missing: " .. tostring(missing))
  result(CacheContract.isReady("firered") == true, "the firered cache reports ready")

  local cache = Dataset.cache()
  local absent = {}
  for _, rel in ipairs(ROUND2_SAMPLE) do
    local bytes = cache:read(rel)
    if type(bytes) ~= "string" or #bytes == 0 then absent[#absent + 1] = rel end
  end
  result(#absent == 0, "all " .. #ROUND2_SAMPLE
    .. " sampled round 2 assets read back from the booted cache, absent: "
    .. (absent[1] or "none"))

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then
    U.shot(game, DIR .. "/import2_fresh_cache_00_stuck.png")
    return finish()
  end

  for _ = 1, 600 do
    if Space.mapId then break end
    U.wait(1)
  end
  print("[driver] map=" .. tostring(Space.mapId) .. " at ("
    .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(Space.mapId == BEDROOM,
    "a new game starts in the player's bedroom, map=" .. tostring(Space.mapId))
  result(U.shot(game, DIR .. "/import2_fresh_cache_01_bedroom.png"),
    "the bedroom screenshot reached disk")

  local function stepOnce(dir)
    local x0, y0, m0 = Player.cellX, Player.cellY, Space.mapId
    U.hold(game, dir, 20)
    U.wait(10)
    return Player.cellX ~= x0 or Player.cellY ~= y0 or Space.mapId ~= m0
  end

  local function walkTo(targetX, targetY, budget)
    local from = Space.mapId
    for _ = 1, (budget or 40) do
      if Space.mapId ~= from then return true end
      if Player.cellX == targetX and Player.cellY == targetY then return true end
      local dir
      if Player.cellX < targetX then dir = "right"
      elseif Player.cellX > targetX then dir = "left"
      elseif Player.cellY < targetY then dir = "down"
      else dir = "up" end
      stepOnce(dir)
    end
    return Space.mapId ~= from
  end

  local function waitMap(target, frames)
    for _ = 1, (frames or 240) do
      if Space.mapId == target then break end
      U.wait(1)
    end
    U.wait(30)
  end

  -- pokefirered/src/field_control_avatar.c:924
  walkTo(10, 2, 30)
  if Space.mapId ~= HOUSE_1F then stepOnce("left") end
  waitMap(HOUSE_1F, 240)
  print("[driver] down the stairs: map=" .. tostring(Space.mapId) .. " at ("
    .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(Space.mapId == HOUSE_1F,
    "the stairs warp reached the ground floor, map=" .. tostring(Space.mapId))

  walkTo(10, 8, 20)
  walkTo(4, 8, 40)
  if Space.mapId == HOUSE_1F then stepOnce("down") end
  waitMap(PALLET, 300)
  U.wait(60)
  print("[driver] out the front door: map=" .. tostring(Space.mapId) .. " at ("
    .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(Space.mapId == PALLET,
    "the player walked out into Pallet Town, map=" .. tostring(Space.mapId))
  result(U.shot(game, DIR .. "/import2_fresh_cache_02_pallet_town.png"),
    "the Pallet Town screenshot reached disk")

  finish()
end
