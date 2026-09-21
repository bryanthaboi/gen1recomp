local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_encounters_rocksmash"

local MT_EMBER = "FR_MT_EMBER_EXTERIOR"
local FOUR_ISLAND = "FR_FOUR_ISLAND"
-- pokefirered/include/constants/flags.h:1369
local FLAG_BADGE06_GET = 0x825
-- pokefirered/include/constants/event_objects.h:102
local GFX_ROCK_SMASH_ROCK = 96
-- pokefirered/include/constants/moves.h:253
local MOVE_ROCK_SMASH = 249
-- pokefirered/include/constants/vars.h:186
local VAR_MAP_SCENE_FOUR_ISLAND = 0x4086
-- pokefirered/src/wild_encounter.c:303
local WILD_SEED = 8

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    if fails == 0 then
      print("PASS encounters_rocksmash")
      love.event.quit(0)
    else
      print("FAIL encounters_rocksmash failures=" .. fails)
      love.event.quit(1)
    end
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local Encounters = require("src.core.game3.encounters")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Rng = require("src.core.game3.rng")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end

  session.party = {}
  Party.giveMon(session, 95, 40)
  local lead = session.party[1]
  lead.moves = { MOVE_ROCK_SMASH }
  lead.pp = { 15 }
  lead.maxPp = { 15 }
  Flags.setFlag(Space.store, ctx(), FLAG_BADGE06_GET, true)

  local function placeAt(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(60)
  end

  local function findRock()
    for _, lid in ipairs(Objects.listActive()) do
      local eo = Objects.find(lid)
      local gfx = eo and (eo.gfx or eo.graphicsId)
      if gfx == GFX_ROCK_SMASH_ROCK then return lid, eo end
    end
    return nil
  end

  local NEIGHBOURS = {
    { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
  }

  local FACE_DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

  local function facedObject()
    local d = FACE_DELTA[Player.facing] or { 0, 1 }
    return Objects.at(Player.cellX + d[1], Player.cellY + d[2])
  end

  local function standNextTo(mapId, eo)
    for _, n in ipairs(NEIGHBOURS) do
      local sx, sy = eo.cellX + n[1], eo.cellY + n[2]
      if Collision.isWalkable(sx, sy) and not Objects.blocks(sx, sy) then
        placeAt(mapId, sx, sy, n[3])
        local front = facedObject()
        U.log(string.format("at (%d,%d) facing %s, front object gfx=%s script=%s",
          sx, sy, n[3], tostring(front and (front.gfx or front.graphicsId)),
          tostring(front and (front.script or (front.def and front.def.script)))))
        return sx, sy, n[3]
      end
    end
    return nil
  end

  local function busy()
    return (Space.vm and Space.vm:isRunning())
      or (Message.isOpen and Message.isOpen())
      or Choice.active
      or require("src.core.game3.field").locked
  end

  local function smash(limit)
    local ticks, seen = 0, {}
    while ticks < (limit or 900) do
      if Battle.isActive and Battle.isActive() then return true end
      local txt = Message.currentPage and Message.currentPage()
      if type(txt) == "string" and txt ~= "" and not seen[txt] then
        seen[txt] = true
        U.log("dialog: " .. txt:gsub("\n", " / "))
      end
      U.tap(game, "a")
      U.wait(14)
      ticks = ticks + 14
      if not busy() and ticks > 120 then break end
    end
    return (Battle.isActive and Battle.isActive()) == true
  end

  local function enemySpecies()
    local st = Battle.getState and Battle.getState()
    local mon = st and st.enemy and st.enemy.mon
    return mon and (tonumber(mon.species) or mon.species), mon and mon.level
  end

  local function flee()
    for _ = 1, 400 do
      if not (Battle.isActive and Battle.isActive()) then return true end
      if Battle._phase == "command" and Ui._mode == "menu" then
        U.tap(game, "down")
        U.wait(6)
        U.tap(game, "right")
        U.wait(6)
        U.tap(game, "a")
        U.wait(20)
      else
        U.tap(game, "a")
        U.wait(8)
      end
    end
    return not (Battle.isActive and Battle.isActive())
  end

  -- pokefirered/src/wild_encounter.c:446
  placeAt(MT_EMBER, 29, 42, "up")
  local emberTable = Encounters.tableFor(MT_EMBER)
  result(type(emberTable) == "table" and type(emberTable.rocks) == "table",
    MT_EMBER .. " carries a rockSmashMonsInfo table")
  local rockIds, rockEo = findRock()
  result(rockIds ~= nil, "Mt Ember Exterior has a visible ROCK_SMASH_ROCK object")

  if rockIds and emberTable and emberTable.rocks then
    local sx, sy, facing = standNextTo(MT_EMBER, rockEo)
    result(sx ~= nil, string.format("stood next to the rock at (%d,%d)", rockEo.cellX, rockEo.cellY))
    U.log(string.format("player at (%s,%s) facing %s, rock at (%d,%d)",
      tostring(sx), tostring(sy), tostring(facing), rockEo.cellX, rockEo.cellY))

    Rng.SeedRng(0x1234)
    Rng.SeedWildEncounterRng(WILD_SEED)
    Encounters.resetRateModifiers()
    U.tap(game, "a")
    for _ = 1, 40 do
      if Message.isOpen and Message.isOpen() then break end
      U.wait(6)
    end
    U.wait(40)
    result(Message.isOpen and Message.isOpen(), "the rock prompt opened")
    U.shot(game, DIR .. "/rocksmash_01_prompt.png")
    local hit = smash(1200)
    result(hit, "smashing the Mt Ember rock started a wild battle")
    result(Objects.find(rockIds) == nil
      or not (Objects.find(rockIds).visible and not Objects.find(rockIds).hidden),
      "the smashed rock is gone from the map")
    if hit then
      U.wait(300)
      local sp, lv = enemySpecies()
      U.log(string.format("rock smash wild: species=%s level=%s", tostring(sp), tostring(lv)))
      local allowed, lo, hi = {}, 99, 0
      for _, slot in ipairs(emberTable.rocks.slots or {}) do
        allowed[slot.species] = true
        local a = tonumber(slot.minLevel) or 0
        local b = tonumber(slot.maxLevel) or a
        if a < lo then lo = a end
        if b > hi then hi = b end
      end
      result(allowed[sp] == true,
        "species " .. tostring(sp) .. " comes from the Mt Ember rocks table")
      result(lv ~= nil and lv >= lo and lv <= hi,
        string.format("level %s is inside the rocks table range %d-%d", tostring(lv), lo, hi))
      U.shot(game, DIR .. "/rocksmash_02_wild_battle.png")
      result(flee(), "left the rock smash battle")
      U.wait(90)
    end
  end

  -- pokefirered/src/wild_encounter.c:451
  -- pokefirered/data/maps/FourIsland/scripts.inc:48
  Flags.setVar(Space.store, ctx(), VAR_MAP_SCENE_FOUR_ISLAND, 1)
  placeAt(FOUR_ISLAND, 5, 12, "up")
  Flags.setVar(Space.store, ctx(), VAR_MAP_SCENE_FOUR_ISLAND, 1)
  local fourTable = Encounters.tableFor(FOUR_ISLAND)
  result(type(fourTable) == "table" and fourTable.rocks == nil,
    "Four Island has no rockSmashMonsInfo")
  local fourId, fourEo = findRock()
  result(fourId ~= nil, "Four Island has a visible ROCK_SMASH_ROCK object")
  if fourId and fourTable and fourTable.rocks == nil then
    local sx = standNextTo(FOUR_ISLAND, fourEo)
    result(sx ~= nil, string.format("stood next to the Four Island rock at (%d,%d)",
      fourEo.cellX, fourEo.cellY))
    Rng.SeedRng(0x1234)
    Rng.SeedWildEncounterRng(WILD_SEED)
    Encounters.resetRateModifiers()
    local hit2 = smash(900)
    result(not hit2, "a map with no rocks area starts no battle")
    result(Objects.find(fourId) == nil
      or not (Objects.find(fourId).visible and not Objects.find(fourId).hidden),
      "the Four Island rock still broke")
    U.wait(60)
    U.shot(game, DIR .. "/rocksmash_03_no_rocks_area.png")
  end

  finish()
end
