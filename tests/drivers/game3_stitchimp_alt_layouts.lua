local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchimp_alt_layouts"

-- pokefirered/include/constants/flags.h:86,87
local FLAG_HIDE_SEAFOAM_B3F_BOULDER_1 = 0x046
local FLAG_HIDE_SEAFOAM_B3F_BOULDER_2 = 0x047
-- pokefirered/include/constants/flags.h:92,93
local FLAG_HIDE_SEAFOAM_B4F_BOULDER_1 = 0x04C
local FLAG_HIDE_SEAFOAM_B4F_BOULDER_2 = 0x04D
-- pokefirered/include/constants/flags.h:749,750
local FLAG_STOPPED_SEAFOAM_B3F_CURRENT = 0x2D2
local FLAG_STOPPED_SEAFOAM_B4F_CURRENT = 0x2D3
-- pokefirered/include/constants/flags.h:1398
local FLAG_SYS_NATIONAL_DEX = 0x840

local B3F = "FR_SEAFOAM_ISLANDS_B3F"
local B4F = "FR_SEAFOAM_ISLANDS_B4F"
local TUNNEL = "FR_THREE_ISLAND_DUNSPARCE_TUNNEL"
local ROOM1 = "FR_SEVEN_ISLAND_HOUSE_ROOM1"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchimp_alt_layouts")
    love.event.quit(0)
  else
    print("FAIL stitchimp_alt_layouts failures=" .. failures)
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
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setFlag(id, on) Flags.setFlag(Space.store, ctx(), id, on) end

  local function look(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    U.wait(30)
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    look(x, y, facing)
    U.wait(90)
  end

  local function mapDef()
    return game.data and game.data.maps and game.data.maps[Space.mapId]
  end

  local function trueSize()
    local L = mapDef() and mapDef().midLayout
    if not L then return 0, 0 end
    return L.trueWidth or L.width, L.trueHeight or L.height
  end

  -- pokefirered/include/constants/metatile_behaviors.h:62-65
  local function countCurrents()
    local w, h = trueSize()
    local n = 0
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local b = Collision.behavior(x, y)
        if b and b >= 0x50 and b <= 0x53 then n = n + 1 end
      end
    end
    return n
  end

  -- pokefirered/include/constants/metatile_behaviors.h:8
  local function countBehavior(want)
    local w, h = trueSize()
    local n = 0
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        if Collision.behavior(x, y) == want then n = n + 1 end
      end
    end
    return n
  end

  -- pokefirered/data/maps/Route20/scripts.inc:10-19
  setFlag(FLAG_STOPPED_SEAFOAM_B3F_CURRENT, false)
  setFlag(FLAG_HIDE_SEAFOAM_B3F_BOULDER_1, true)
  setFlag(FLAG_HIDE_SEAFOAM_B3F_BOULDER_2, true)
  goTo(B3F, 8, 14, "down")
  result(Space.mapId == B3F, "stood on Seafoam Islands B3F, map=" .. tostring(Space.mapId))
  local b3Flowing = countCurrents()
  result(b3Flowing == 56, "B3F current still flowing, " .. b3Flowing .. " current cells")
  result(Flags.getFlag(Space.store, ctx(), FLAG_STOPPED_SEAFOAM_B3F_CURRENT) ~= true,
    "B3F stopped-current flag is still clear with both boulders up top")
  look(19, 4, "down")
  U.shot(game, DIR .. "/stitchimp_alt_layouts_01_b3f_current_flowing.png")

  -- pokefirered/data/maps/SeafoamIslands_B2F/map.json:27,41
  setFlag(FLAG_HIDE_SEAFOAM_B3F_BOULDER_1, false)
  setFlag(FLAG_HIDE_SEAFOAM_B3F_BOULDER_2, false)
  goTo(B3F, 8, 14, "down")
  result(Flags.getFlag(Space.store, ctx(), FLAG_STOPPED_SEAFOAM_B3F_CURRENT) == true,
    "the real ON_TRANSITION set FLAG_STOPPED_SEAFOAM_B3F_CURRENT")
  local b3Stopped = countCurrents()
  result(b3Stopped == 22, "B3F current stopped, " .. b3Stopped .. " current cells left")
  look(19, 4, "down")
  U.shot(game, DIR .. "/stitchimp_alt_layouts_02_b3f_current_stopped.png")

  setFlag(FLAG_STOPPED_SEAFOAM_B4F_CURRENT, false)
  setFlag(FLAG_HIDE_SEAFOAM_B4F_BOULDER_1, true)
  setFlag(FLAG_HIDE_SEAFOAM_B4F_BOULDER_2, true)
  goTo(B4F, 15, 9, "down")
  result(Space.mapId == B4F, "stood on Seafoam Islands B4F, map=" .. tostring(Space.mapId))
  local b4Flowing = countCurrents()
  result(b4Flowing == 173, "B4F current still flowing, " .. b4Flowing .. " current cells")
  look(8, 18, "up")
  U.shot(game, DIR .. "/stitchimp_alt_layouts_03_b4f_current_flowing.png")

  setFlag(FLAG_HIDE_SEAFOAM_B4F_BOULDER_1, false)
  setFlag(FLAG_HIDE_SEAFOAM_B4F_BOULDER_2, false)
  goTo(B4F, 15, 9, "down")
  result(Flags.getFlag(Space.store, ctx(), FLAG_STOPPED_SEAFOAM_B4F_CURRENT) == true,
    "the real ON_TRANSITION set FLAG_STOPPED_SEAFOAM_B4F_CURRENT")
  local b4Stopped = countCurrents()
  result(b4Stopped == 15, "B4F current stopped, " .. b4Stopped .. " current cells left")
  look(8, 18, "up")
  U.shot(game, DIR .. "/stitchimp_alt_layouts_04_b4f_current_stopped.png")

  -- pokefirered/data/maps/ThreeIsland_DunsparceTunnel/scripts.inc:5-13
  setFlag(FLAG_SYS_NATIONAL_DEX, false)
  goTo(TUNNEL, 3, 4, "down")
  result(Space.mapId == TUNNEL, "stood in the Dunsparce Tunnel, map=" .. tostring(Space.mapId))
  local tunnelWalled = countBehavior(0x08)
  result(tunnelWalled == 164, "the tunnel is still walled, " .. tunnelWalled .. " MB_CAVE cells")
  look(3, 3, "right")
  U.shot(game, DIR .. "/stitchimp_alt_layouts_05_tunnel_walled.png")

  setFlag(FLAG_SYS_NATIONAL_DEX, true)
  goTo(TUNNEL, 3, 4, "down")
  local PokedexData = require("src.core.game3.pokedex_data")
  local natDex = PokedexData.isNationalUnlocked(Runtime.getSession(), nil)
  local varResult = Flags.getVar(Space.store, ctx(), 0x800D)
  result(natDex == true, "the session reads the national dex as unlocked")
  -- pokefirered/data/maps/ThreeIsland_DunsparceTunnel/scripts.inc:7
  local tunnelOnTransition = countBehavior(0x08)
  result(tunnelOnTransition == 86,
    "the real ON_TRANSITION dug the tunnel out, " .. tunnelOnTransition ..
    " MB_CAVE cells, VAR_RESULT now reads " .. tostring(varResult))
  local Ops = require("src.core.game3.scripting.ops_a")
  -- pokefirered/include/constants/layouts.h:308
  local swapped = select(2, Ops.setMapLayout(319))
  local tunnelDug = countBehavior(0x08)
  result(tunnelDug == 86,
    "setmaplayoutindex 319 dug the tunnel out, " .. tunnelDug .. " MB_CAVE cells after " ..
    tostring(swapped) .. " swapped cells")
  look(3, 3, "right")
  U.shot(game, DIR .. "/stitchimp_alt_layouts_06_tunnel_dug_out.png")

  -- pokefirered/data/maps/SevenIsland_House_Room1/scripts.inc:8-19
  goTo(ROOM1, 4, 7, "up")
  print("[driver] HANDOFF special 0xF6 ValidateEReaderTrainer is unbound, so " ..
    "SevenIsland_House_Room1_OnTransition takes the VAR_RESULT == 0 arm and the room " ..
    "loads with " .. countBehavior(0x60) .. " MB_CAVE_DOOR cell(s) on a clean save; pret " ..
    "writes VAR_RESULT = 1 for an empty e-Reader slot (src/battle_tower.c:1360-1371) and " ..
    "keeps the door shut, and the port cannot be driven to that arm from here because " ..
    "vm.lua:100-116 wipes specialVars at every script start")

  local Dataset = require("src.core.game3.dataset")
  local NativePack = require("src.import.gba.native_pack")
  local Island1 = require("src.import.gba.extract_island1")
  local nativeRoot = Island1.NATIVE_ROOT
    or ((Island1.CACHE_ROOT or "data/generated/gba") .. "/native")
  local function bakedLayout(name)
    local blob = Dataset.cache():read(nativeRoot .. "/layouts/" .. name .. ".mid")
    return blob and NativePack.decodeMidLayout(blob)
  end
  -- pokefirered/include/constants/layouts.h:253
  local baseGrid, altGrid = bakedLayout(ROOM1), bakedLayout("alt_264")
  if not result(baseGrid ~= nil and altGrid ~= nil,
    "the shut-door layout and alt_264 are both baked") then return finish() end
  result(altGrid.width == baseGrid.width and altGrid.height == baseGrid.height,
    "alt_264 is the room's own size, " .. altGrid.width .. "x" .. altGrid.height)
  local diff = 0
  for i = 1, baseGrid.width * baseGrid.height do
    local a, b = baseGrid.cells[i], altGrid.cells[i]
    if a and b and (a.mid ~= b.mid or a.coll ~= b.coll) then diff = diff + 1 end
  end
  result(diff > 0, "alt_264 differs from the shut-door layout in " .. diff .. " cells")

  local function countBehaviorIn(grid, want)
    local def = mapDef()
    local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
    local behaviors = require("src.core.game3.scripting.interaction_scripts").behaviors[pair]
    local n = 0
    for i = 1, grid.width * grid.height do
      local cell = grid.cells[i]
      if cell and behaviors and behaviors[cell.mid] == want then n = n + 1 end
    end
    return n
  end

  -- pokefirered/src/battle_tower.c:1354 ValidateEReaderTrainer
  result(countBehaviorIn(baseGrid, 0x60) == 0,
    "the layout a clean save keeps has no MB_CAVE_DOOR cell, the door is shut")
  -- pokefirered/include/constants/layouts.h:253
  result(countBehaviorIn(altGrid, 0x60) == 1,
    "alt_264 is the one that opens it, " .. countBehaviorIn(altGrid, 0x60) ..
    " MB_CAVE_DOOR cell")

  local applied, doorSwapped = Ops.setMapLayout(264)
  result(applied == true, "setmaplayoutindex 264 applied the baked layout")
  local doorCells = countBehavior(0x60)
  result(doorCells == 1,
    "driving 264 leaves the live room with " .. doorCells .. " MB_CAVE_DOOR cell, " ..
    tostring(doorSwapped) .. " cells swapped live")
  look(4, 4, "up")
  U.shot(game, DIR .. "/stitchimp_alt_layouts_07_seven_island_door_open.png")

  finish()
end
