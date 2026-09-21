local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_special_legendary"

local NAVEL_ROCK_BASE = "FR_NAVEL_ROCK_BASE"
local LUGIA_XY = { 10, 15 }
local SPECIES_LUGIA = 249 -- pokefirered/include/constants/species.h:256

-- pokefirered/include/constants/flags.h:171
local FLAG_HIDE_LUGIA = 0x09B
-- pokefirered/include/constants/flags.h:781
local FLAG_FOUGHT_LUGIA = 0x2F2
-- pokefirered/include/constants/flags.h:784
local FLAG_LUGIA_FLEW_AWAY = 0x2F5
-- pokefirered/include/constants/flags.h:1334
local FLAG_SYS_SPECIAL_WILD_BATTLE = 0x807

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS special_legendary")
    love.event.quit(0)
  else
    print("FAIL special_legendary failures=" .. failures)
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
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Encounters = require("src.core.game3.encounters")

  local Natives = require("src.core.game3.scripting.natives")
  U.log("natives modules: " .. table.concat(Natives.MODULE_NAMES, ","))
  result(Natives.ALLOW["special:" .. 0x1BB] ~= nil,
    "auto-discovery bound CreateEnemyEventMon under love.filesystem")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 150, 100)

  local function ctx() return Space.vm and Space.vm.ctx end
  local function flag(id) return Flags.getFlag(Space.store, ctx(), id) and true or false end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  local function objectAt(x, y)
    for _, lid in ipairs(Objects._order or {}) do
      local eo = Objects._byId and Objects._byId[lid]
      local ex = eo and (eo.cellX or eo.x)
      local ey = eo and (eo.cellY or eo.y)
      if eo and eo.visible ~= false and ex == x and ey == y then return eo, lid end
    end
    return nil
  end

  local function fieldBusy()
    local Message = package.loaded["src.ui.game3.message"]
    return (Message and Message.isOpen and Message.isOpen()) and true or false
  end

  local function atCommand()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local function mash(frames, stop)
    for i = 1, (frames or 2500) do
      if stop() then return true end
      if i % 300 == 0 then
        U.log("mash", i, "battle=" .. tostring(Battle.isActive()),
          "phase=" .. tostring(Battle._phase),
          "vm=" .. tostring(Space.vm and Space.vm:isRunning()))
      end
      if Ui.dialogPending and Ui.dialogPending() then
        U.tap(game, "a")
        U.wait(8)
      elseif i % 16 == 0 then
        U.tap(game, "a")
        U.wait(4)
      else
        U.wait(1)
      end
    end
    return stop()
  end

  goTo(NAVEL_ROCK_BASE, LUGIA_XY[1], LUGIA_XY[2] + 1, "up")

  -- pokefirered/data/maps/NavelRock_Base/scripts.inc:15 NavelRock_Base_EventScript_TryShowLugia
  result(flag(FLAG_FOUGHT_LUGIA) == false, "FLAG_FOUGHT_LUGIA starts clear")
  result(flag(FLAG_LUGIA_FLEW_AWAY) == false, "FLAG_LUGIA_FLEW_AWAY starts clear")
  result(flag(FLAG_HIDE_LUGIA) == false,
    "the map's own ON_TRANSITION TryShowLugia cleared FLAG_HIDE_LUGIA")
  local lugiaObj = objectAt(LUGIA_XY[1], LUGIA_XY[2])
  result(lugiaObj ~= nil, "Lugia stands on Navel Rock Base at (10,15)")
  U.shot(game, DIR .. "/special_legendary_01_lugia_on_map.png")

  Encounters.takePendingWild()
  U.tap(game, "a")
  U.wait(30)
  for _ = 1, 600 do
    if Battle.isActive() then break end
    if fieldBusy() then U.tap(game, "a") end
    U.wait(6)
  end

  if not result(Battle.isActive(),
    "seteventmon + StartLegendaryBattle started the Lugia battle") then
    U.log("vm running=" .. tostring(Space.vm and Space.vm:isRunning()) ..
      " special wild flag=" .. tostring(flag(FLAG_SYS_SPECIAL_WILD_BATTLE)))
    U.shot(game, DIR .. "/special_legendary_02_no_battle.png")
    return finish()
  end

  result(mash(2500, atCommand), "the Lugia battle reached the command menu")
  local st = Battle.getState()
  local foe = st and st.enemy and st.enemy.mon
  result(foe ~= nil and tonumber(foe.species or foe.speciesId) == SPECIES_LUGIA,
    "the event mon is SPECIES_LUGIA, got " ..
    tostring(foe and (foe.species or foe.speciesId)))
  result(foe ~= nil and tonumber(foe.level) == 70,
    "the event mon is level 70, got " .. tostring(foe and foe.level))
  U.shot(game, DIR .. "/special_legendary_02_lugia_battle.png")

  finish()
end
