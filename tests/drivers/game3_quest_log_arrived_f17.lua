local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_quest_log_arrived_f17"
local ITEM_ESCAPE_ROPE = 85

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "f17 quest log arrived failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "f17 boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not check(session ~= nil, "f17 field reached") then return finish() end
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Fade = require("src.ui.game3.fade")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local FE = require("src.core.game3.field_effects")
  local Warp = require("src.core.game3.warp")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local ItemUse = require("src.core.game3.item_use")
  local Message = require("src.ui.game3.message")
  local Q = require("src.core.game3.quest_log")
  local QuestLog = require("src.ui.game3.quest_log")
  local QuestRecorder = require("src.core.game3.quest_log_recorder")
  local T = require("src.core.game3.tileset_native")
  local C = require("src.core.game3.constants").of(session.version)
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end

  local function waitFor(pred, limit)
    for _ = 1, limit do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local function holdUntil(dir, pred, limit)
    local reached = false
    for _ = 1, limit do
      if pred() then reached = true break end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      U.wait(1)
    end
    game.input.state[dir] = false
    return reached or pred()
  end
  local function settle()
    return waitFor(function()
      return not Fade.active and not Warp._busy and not Field.locked and not Player.moving
        and #(FE._anims or {}) == 0
    end, 900)
  end

  local label = "newgame"
  local arrivals = {}
  local realEvent = QuestRecorder.event
  QuestRecorder.event = function(s, key, args, ...)
    if key == "ArrivedInLocation" then
      local row = {
        label = label, map = s and s.map, loc = args and args[1],
        visible = Player.isVisible() and true or false, busy = Warp._busy and true or false,
      }
      arrivals[#arrivals + 1] = row
      print(string.format("[f17] Arrived #%d label=%s map=%s loc=%s visible=%s warpBusy=%s",
        #arrivals, row.label, tostring(row.map), tostring(row.loc), tostring(row.visible), tostring(row.busy)))
    end
    return realEvent(s, key, args, ...)
  end
  local function arrivalsFor(l)
    local n = 0
    for _, r in ipairs(arrivals) do if r.label == l then n = n + 1 end end
    return n
  end
  local function sceneOn(map)
    for _, s in ipairs(session.questLog and session.questLog.scenes or {}) do
      if s.map == map then return s end
    end
  end

  session.party = {}
  Party.giveMon(session, C:require("species", "SPECIES_ABRA"), 30)
  local mon = session.party[1]
  mon.moves = { "TELEPORT", "DIG", "FLY", "SURF" }
  mon.pp = { 20, 10, 15, 15 }
  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_ESCAPE_ROPE, 1)
  settle()
  U.wait(30)
  check(arrivalsFor("newgame") == 0, "f17 no Arrived in the new game bedroom")
  session.questLog = nil

  local function flag(name)
    return Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, Flags.IDS[name]) and true or false
  end

  label = "load_viridian_first_visit"
  local viridianBefore = flag("FLAG_WORLD_MAP_VIRIDIAN_CITY")
  Map.load(nil, game, "FR_VIRIDIAN_CITY", { x = 20, y = 20, facing = "down" })
  U.wait(60)
  settle()
  local viridianAfter = flag("FLAG_WORLD_MAP_VIRIDIAN_CITY")
  check(viridianBefore == false and viridianAfter == true, "f17 first Viridian entry sets the world map flag")
  check(arrivalsFor(label) == 1, "f17 first Viridian entry records one Arrived")
  local first = arrivals[1]
  check(first ~= nil and first.visible and not first.busy and first.loc == "VIRIDIAN CITY",
    "f17 Arrived captured with the player visible and no warp running")
  local viridianScene = sceneOn("FR_VIRIDIAN_CITY")
  local p0
  for _, a in ipairs(viridianScene and viridianScene.frames[1].actors or {}) do if a.id == 255 then p0 = a end end
  check(viridianScene ~= nil and viridianScene.events[1].key == "ArrivedInLocation" and p0 ~= nil,
    "f17 Viridian Arrived scene first frame has the player")

  local def = game.data.maps["FR_VIRIDIAN_CITY"]
  local door
  for _, w in ipairs(def.warps or {}) do
    for _, v in pairs(w) do
      if type(v) == "string" and v:find("POKEMON_CENTER_1F", 1, true) then door = w end
    end
  end
  if not check(door ~= nil, "f17 Viridian Pokemon Center door found") then return finish() end
  local dx, dy = tonumber(door.x), tonumber(door.y)
  Player.reset(dx, dy + 1, "up")
  U.wait(20)

  label = "door_into_pokemon_center"
  check(holdUntil("up", function() return session.map ~= "FR_VIRIDIAN_CITY" end, 300), "f17 walked through the PC door")
  settle()
  U.wait(30)
  check(arrivalsFor(label) == 0, "f17 no Arrived on entering an indoor map")

  label = "door_out_revisit_viridian"
  check(holdUntil("down", function() return session.map == "FR_VIRIDIAN_CITY" end, 400), "f17 walked out of the PC")
  settle()
  U.wait(30)
  check(arrivalsFor(label) == 0, "f17 no Arrived on a Viridian revisit")

  label = "whiteout"
  session.healMap, session.healX, session.healY = "FR_PALLET_TOWN", 10, 6
  Field.respawnAtHeal()
  waitFor(function() return session.map == "FR_PALLET_TOWN" end, 900)
  U.clearWhiteoutRush(game)
  settle()
  U.wait(30)
  check(arrivalsFor(label) == 0, "f17 no Arrived after a whiteout to Pallet")

  label = "load_mt_moon"
  Map.load(nil, game, "FR_MT_MOON_1F", { x = 5, y = 5, facing = "down" })
  Player.reset(5, 5, "down")
  U.wait(60)
  settle()
  session.healMap, session.healX, session.healY = "FR_PLAYERS_HOUSE_1F", 8, 5
  session.escapeWarp = nil

  label = "escape_rope"
  check(ItemUse.useEscapeRope(session, session.bag, ITEM_ESCAPE_ROPE) == true, "f17 Escape Rope accepted in Mt Moon")
  for _ = 1, 900 do
    if session.map ~= "FR_MT_MOON_1F" then break end
    if Message.isOpen() and not Message.isTyping() then U.tap(game, "a") end
    U.wait(2)
  end
  settle()
  U.wait(30)
  check(session.map == "FR_PLAYERS_HOUSE_1F", "f17 Escape Rope landed in " .. tostring(session.map))
  check(arrivalsFor(label) == 0, "f17 no Arrived after Escape Rope")

  label = "load_mt_moon_dig"
  Map.load(nil, game, "FR_MT_MOON_1F", { x = 5, y = 5, facing = "down" })
  Player.reset(5, 5, "down")
  U.wait(60)
  settle()
  label = "dig"
  Field.executeFieldMove({ action = "dig", mon = mon })
  waitFor(function() return session.map ~= "FR_MT_MOON_1F" end, 1500)
  settle()
  U.wait(30)
  check(arrivalsFor(label) == 0, "f17 no Arrived after Dig to " .. tostring(session.map))
  check(sceneOn("FR_MT_MOON_1F") == nil, "f17 Dig does not start its own scene")

  label = "load_pallet"
  Map.load(nil, game, "FR_PALLET_TOWN", { x = 10, y = 6, facing = "down" })
  Player.reset(10, 6, "down")
  U.wait(60)
  settle()
  session.healMap, session.healX, session.healY = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", 7, 4
  label = "teleport"
  Field.executeFieldMove({ action = "teleport", mon = mon, se = nil })
  waitFor(function() return session.map ~= "FR_PALLET_TOWN" end, 1500)
  settle()
  U.wait(30)
  check(arrivalsFor(label) == 0, "f17 no Arrived after Teleport to " .. tostring(session.map))
  check(sceneOn("FR_PALLET_TOWN") == nil, "f17 Teleport does not start its own scene")

  label = "load_route1"
  Map.load(nil, game, "FR_ROUTE_1", { x = 10, y = 10, facing = "down" })
  Player.reset(10, 10, "down")
  U.wait(60)
  settle()
  label = "fly"
  local dest = Field.flyDestination("MAPSEC_VIRIDIAN_CITY")
  check(dest ~= nil and Field.flyTo("MAPSEC_VIRIDIAN_CITY", mon), "f17 Fly to Viridian starts")
  waitFor(function()
    return dest and session.map == dest.map and not Field._flyLanding and not Field.locked and not Fade.active
  end, 3000)
  settle()
  U.wait(30)
  check(arrivalsFor(label) == 0, "f17 no Arrived after Fly to " .. tostring(session.map))
  check(sceneOn("FR_ROUTE_1") == nil, "f17 Fly does not start its own scene")

  print("[f17] arrivals total=" .. #arrivals)
  check(#arrivals == 1, "f17 exactly one Arrived over the whole sequence")

  QuestRecorder.save(game)
  local log = Q.export(session)
  for i, s in ipairs(log.scenes) do
    local keys = {}
    for _, e in ipairs(s.events) do keys[#keys + 1] = e.key end
    print(string.format("[f17] recap scene %d map=%s frames=%d events=%s", i, s.map, #s.frames, table.concat(keys, ",")))
  end

  local function undrawn(scene, frame)
    local cx = math.floor(frame.x + 8 - 120); local cy = math.floor(frame.y + 8 - 80)
    local missing = 0
    for y = math.floor(cy / 16), math.floor((cy + 159) / 16) do
      for x = math.floor(cx / 16), math.floor((cx + 239) / 16) do
        local t = scene.tiles and scene.tiles[x .. "," .. y]
        local ts = t and T.get(t[2])
        if not (ts and T.slotFor(ts, t[1])) then missing = missing + 1 end
      end
    end
    return missing
  end

  local phase = game.phase
  local playback = QuestLog.begin(session)
  if not check(playback ~= nil, "f17 recap playback begins") then return finish() end
  game.questPlayback = playback
  game.phase = "quest_log"
  local viridianIndex
  for i, s in ipairs(playback.scenes) do
    if s.map == "FR_VIRIDIAN_CITY" and s.events[1].key == "ArrivedInLocation" then viridianIndex = i end
    local worst = 0
    for t = 0, #s.frames * 6 - 1 do
      playback.index, playback.ticks = i, t
      local m = undrawn(s, playback:frame())
      if m > worst then worst = m end
    end
    check(worst == 0, "f17 recap scene " .. i .. " has no undrawn cell in any frame")
  end
  if check(viridianIndex ~= nil, "f17 recap has the Viridian Arrived scene") then
    playback.index, playback.ticks = viridianIndex, 0
    check(U.still(game, DIR .. "/f17_01_recap_arrived_viridian_player_present.png"), "f17 recap Arrived shot")
  end
  game.questPlayback = nil
  game.phase = phase
  finish()
end
