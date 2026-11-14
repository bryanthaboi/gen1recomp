local U = require("tests.drivers.util")
local VERSION = os.getenv("POKEPORT_VERSION") or "firered"
local DIR = os.getenv("POKEPORT_SHOT_DIR")
  or (".bazinga/BSA/11-14-26-00-preissues/shots/game3_transition_terrain_frlg_" .. VERSION)

-- pokefirered/src/battle_setup.c:87
local NAME = { [0] = "BLUR", "SWIRL", "SHUFFLE", "BIG_POKEBALL", "POKEBALLS_TRAIL", "CLOCKWISE_WIPE",
  "RIPPLE", "WAVE", "SLICE", "WHITE_BARS_FADE", "GRID_SQUARES", "ANGLED_WIPES" }

local SCEN_FRLG = {
  { tag = "MtMoon_1F wild lead 20 vs 5", map = "MAP_MT_MOON_1F", lead = 20, foe = 5, want = 5,
    shot = "p1_01_mtmoon_cave_clockwise_wipe_mid" },
  { tag = "MtMoon_1F wild lead 5 vs 10", map = "MAP_MT_MOON_1F", lead = 5, foe = 10, want = 10,
    shot = "p1_02_mtmoon_cave_grid_squares_mid" },
  { tag = "RockTunnel_1F dark wild lead 20 vs 15", map = "MAP_ROCK_TUNNEL_1F", lead = 20, foe = 15, want = 0,
    shot = "p1_04_rocktunnel_dark_flash_blur_mid" },
  { tag = "RockTunnel_1F dark wild lead 10 vs 15", map = "MAP_ROCK_TUNNEL_1F", lead = 10, foe = 15, want = 10,
    shot = "p1_05_rocktunnel_dark_flash_grid_squares_mid" },
  { tag = "RockTunnel_1F lit by Flash wild lead 20 vs 15", map = "MAP_ROCK_TUNNEL_1F", lead = 20, foe = 15, want = 5,
    flashOff = true },
  { tag = "Route4 land wild lead 20 vs 5", map = "MAP_ROUTE4", lead = 20, foe = 5, want = 8 },
  { tag = "Route4 land wild lead 5 vs 10", map = "MAP_ROUTE4", lead = 5, foe = 10, want = 9 },
  { tag = "ViridianForest wild lead 20 vs 5", map = "MAP_VIRIDIAN_FOREST", lead = 20, foe = 5, want = 8 },
  { tag = "Route21_North surfing wild lead 30 vs 20", map = "MAP_ROUTE21_NORTH", lead = 30, foe = 20, want = 7,
    surf = true, shot = "p1_03_route21_surf_wave_mid" },
  { tag = "Route21_North surfing wild lead 10 vs 30", map = "MAP_ROUTE21_NORTH", lead = 10, foe = 30, want = 6,
    surf = true, shot = "p1_06_route21_surf_ripple_mid" },
  { tag = "SeafoamIslands_B3F surfing wild lead 40 vs 30", map = "MAP_SEAFOAM_ISLANDS_B3F", lead = 40, foe = 30,
    want = 7, surf = true },
  { tag = "MtMoon_1F trainer Hiker Marcos lead 20 vs L10", map = "MAP_MT_MOON_1F", lead = 20, trainer = 181, want = 2 },
  { tag = "MtMoon_1F trainer Hiker Marcos lead 5 vs L10", map = "MAP_MT_MOON_1F", lead = 5, trainer = 181, want = 3 },
  { tag = "Route21_North surfing trainer lead 60 vs L10", map = "MAP_ROUTE21_NORTH", lead = 60, trainer = 181,
    want = 1, surf = true, shot = "p1_07_route21_surf_trainer_swirl_mid" },
  { tag = "Route4 wild fainted L50 lead, L5 second vs 10", map = "MAP_ROUTE4", lead = 50, second = 5,
    faintLead = true, foe = 10, want = 9 },
}

local SCEN_RSE = {
  { tag = "RusturfTunnel wild lead 20 vs 5", map = "MAP_RUSTURF_TUNNEL", lead = 20, foe = 5, want = 5,
    shot = "p1_01_rusturf_cave_clockwise_wipe_mid" },
  { tag = "GraniteCave_B1F dark wild lead 20 vs 10", map = "MAP_GRANITE_CAVE_B1F", lead = 20, foe = 10, want = 0,
    shot = "p1_04_granitecave_dark_flash_blur_mid" },
  { tag = "Route105 surfing wild lead 10 vs 30", map = "MAP_ROUTE105", lead = 10, foe = 30, want = 6, surf = true,
    shot = "p1_06_route105_surf_ripple_mid" },
  { tag = "Route101 land wild lead 20 vs 5", map = "MAP_ROUTE101", lead = 20, foe = 5, want = 8 },
  { tag = "Route101 wild fainted L50 lead, L5 second vs 10", map = "MAP_ROUTE101", lead = 50, second = 5,
    faintLead = true, foe = 10, want = 9 },
}

local SCEN = SCEN_FRLG
if VERSION == "emerald" or VERSION == "ruby" or VERSION == "sapphire" then SCEN = SCEN_RSE end

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local BT = require("src.core.game3.battle_transition")
  local Map = require("src.core.game3.map")
  local MapIds = require("src.core.game3.map_ids")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local FieldView = require("src.core.game3.field_view")
  local Trainers = require("src.core.game3.scripting.trainers")
  local C = require("src.core.game3.constants").of(VERSION)
  local session = Runtime.getSession()

  local seenOpts, seenId
  local realPick, realStart = BT.pick, BT.start
  BT.pick = function(o)
    seenOpts = o
    seenId = realPick(o)
    return seenId
  end
  BT.start = function(_, _, cb)
    cb()
    return true
  end

  local function findCell(def, wantSurf)
    for y = 0, (def.height or 0) - 1 do
      for x = 0, (def.width or 0) - 1 do
        local b = Collision.behavior(x, y)
        if b and (Collision.isSurfable(b) == true) == wantSurf and (wantSurf or b ~= 0x01) then
          return x, y, b
        end
      end
    end
  end

  local leadSpecies = C.species.byName.SPECIES_CHARMANDER or C.species.byName.SPECIES_MUDKIP
  for _, sc in ipairs(SCEN) do
    local mapId = MapIds.forConst(sc.map, VERSION)
    local ok, err = pcall(function() Map.load(nil, game, mapId, { x = 5, y = 5, facing = "down" }) end)
    U.wait(30)
    local def = mapId and game.data.maps[mapId]
    local x, y, beh
    if ok and def then x, y, beh = findCell(def, sc.surf == true) end
    if not (ok and def and x) then
      result(false, string.format("%s: map %s load=%s cell=%s", sc.tag, sc.map, tostring(err or ok), tostring(x)))
    else
      Player.cellX, Player.cellY, Player.moving = x, y, false
      Player.surfing = sc.surf == true
      if sc.flashOff then FieldView.setFlashLevel(0) end
      session.party = {}
      Party.giveMon(session, leadSpecies, sc.lead, "LEAD")
      if sc.second then Party.giveMon(session, C.species.byName.SPECIES_PIDGEY, sc.second, "TWO") end
      if sc.faintLead then session.party[1].hp = 0 end
      seenOpts, seenId = nil, nil
      if sc.trainer then
        BattleBridge.start(Runtime._mod, game, Trainers.foeFromId(sc.trainer), { wild = false, trainerId = sc.trainer })
      else
        BattleBridge.startWild(Runtime._mod, game, { species = C.species.byName.SPECIES_ZUBAT, level = sc.foe }, {})
      end
      local o = seenOpts or {}
      print(string.format("[terrain] %s mapType=%s cell=(%d,%d) beh=0x%02X flashLevel=%s playerLevel=%s enemyLevel=%s",
        sc.tag, tostring(o.mapType), x, y, beh, tostring(o.flashLevel), tostring(o.playerLevel),
        tostring(o.enemyLevel)))
      result(seenId == sc.want, string.format("%s: picked %s(%s) want %s(%s)", sc.tag,
        NAME[seenId] or "?", tostring(seenId), NAME[sc.want], sc.want))
      Battle.abort("run")
      for _ = 1, 600 do
        if not Battle.isActive() then break end
        U.wait(1)
      end
      U.wait(30)
    end
  end

  BT.pick, BT.start = realPick, realStart

  local function centerCell(def, wantSurf)
    local cx, cy = (def.width or 0) / 2, (def.height or 0) / 2
    local best, bx, by, bb
    for y = 0, (def.height or 0) - 1 do
      for x = 0, (def.width or 0) - 1 do
        local b = Collision.behavior(x, y)
        if b and (Collision.isSurfable(b) == true) == wantSurf and (wantSurf or b ~= 0x01) then
          local d = (x - cx) ^ 2 + (y - cy) ^ 2
          if not best or d < best then best, bx, by, bb = d, x, y, b end
        end
      end
    end
    return bx, by, bb
  end

  local function stage(sc)
    local mapId = MapIds.forConst(sc.map, VERSION)
    local ok = pcall(function() Map.load(nil, game, mapId, { x = 5, y = 5, facing = "down" }) end)
    U.wait(30)
    local def = mapId and game.data.maps[mapId]
    if not (ok and def) then return nil end
    local x, y = centerCell(def, sc.surf == true)
    if not x then return nil end
    Player.reset(x, y, "down")
    Player.surfing = sc.surf == true
    session.party = {}
    Party.giveMon(session, leadSpecies, sc.lead, "LEAD")
    U.wait(300)
    return x, y
  end

  local function play(sc, shootAt)
    if sc.trainer then
      BattleBridge.start(Runtime._mod, game, Trainers.foeFromId(sc.trainer), { wild = false, trainerId = sc.trainer })
    else
      BattleBridge.startWild(Runtime._mod, game, { species = C.species.byName.SPECIES_ZUBAT, level = sc.foe }, {})
    end
    local picked = BT._transitionId
    local frames, mainAt, shot = 0, nil, nil
    while frames < 900 do
      U.wait(1)
      frames = frames + 1
      if BT._phase == "main" and not mainAt then mainAt = frames end
      if shootAt and mainAt and BT._phase == "main" and frames - mainAt == shootAt then
        shot = string.format("%s/%s.png", DIR, sc.shot)
        U.still(game, shot)
      end
      if not BT.isActive() or Battle.isActive() then break end
    end
    local mainFrames = mainAt and (frames - mainAt) or 0
    Battle.abort("run")
    for _ = 1, 600 do
      if not Battle.isActive() then break end
      U.wait(1)
    end
    U.wait(30)
    return picked, mainFrames, shot
  end

  for _, sc in ipairs(SCEN) do
    if sc.shot then
      local x, y = stage(sc)
      if not x then
        result(false, sc.shot .. ": no cell on " .. sc.map)
      else
        local picked, n = play(sc, nil)
        result(picked == sc.want and n > 1, string.format("%s: %s(%s) plays %d main frames at (%d,%d)", sc.shot,
          NAME[picked] or "?", tostring(picked), n, x, y))
        stage(sc)
        local mid = math.floor(n / 2)
        local _, _, shot = play(sc, mid)
        local f = shot and io.open(shot, "rb")
        if f then f:close() end
        result(f ~= nil, string.format("%s: shot at main+%d of %d", sc.shot, mid, n))
      end
    end
  end

  love.event.quit(fails == 0 and 0 or 1)
end
