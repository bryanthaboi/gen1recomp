package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local GameVersion = require("src.core.GameVersion")
local Movement = require("src.core.game3.scripting.movement")
local Player = require("src.core.game3.player")
local Objects = require("src.core.game3.objects")
local Collision = require("src.core.game3.collision")
local Runtime = require("src.core.game3.runtime")
local Field = require("src.core.game3.field")
local game = { data = {}, session = { version = "emerald", flags = {}, vars = {}, party = {} } }
Runtime.session = game.session
Field.locked = true
local dirs = { "down", "up", "left", "right" }
local delta = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local function tick()
  Player.tick(game)
  Objects.update(game)
end
local function fixture()
  Player.reset(5, 5, "down")
  local eo = { localId = 1, cellX = 5, cellY = 5, px = 80, py = 80,
    facing = "down", animClock = 0, progress = 0, frozen = true, scriptBusy = true }
  Objects._byId, Objects._order, Objects._tracks = { [1] = eo }, { 1 }, {}
  return eo
end
for _, version in ipairs({ "emerald", "ruby", "sapphire" }) do
  GameVersion.set(version)
  game.session.version = version
  for i = 0, 4 do
    local frames = 2 ^ i
    fixture()
    Objects.applyMovement(255, { 0x18 + i, 0xFE })
    for n = 1, frames - 1 do
      tick()
      T.check(not Objects.pollMovement(255), version .. " delay remains active " .. n)
    end
    tick()
    T.check(Objects.pollMovement(255), version .. " delay ends at " .. frames)
  end
  for i, dir in ipairs(dirs) do
    for _, spec in ipairs({ { 0x31, 6 }, { 0x39, 2 } }) do
      for _, lid in ipairs({ 1, 255 }) do
        local eo = fixture()
        local actor = lid == 255 and Player or eo
        Objects.applyMovement(lid, { spec[1] + i - 1, 0xFE })
        T.eq(actor.stepFrames, spec[2], version .. " " .. dir .. " selected duration")
        for n = 1, spec[2] do
          tick()
          T.eq(actor.moving, n < spec[2], version .. " " .. dir .. " moving tick " .. n)
        end
        T.eq(actor.cellX, 5 + delta[dir][1], version .. " " .. dir .. " landing x")
        T.eq(actor.cellY, 5 + delta[dir][2], version .. " " .. dir .. " landing y")
      end
    end
  end
end
for _, version in ipairs({ "firered", "leafgreen" }) do
  GameVersion.set(version)
  game.session.version = version
  T.eq(Movement.decodeAction(0x1C).frames, 32, version .. " delay behavior retained")
  T.eq(Movement.decodeAction(0x32).kind, "nop", version .. " current behavior retained")
  T.eq(Movement.decodeAction(0x39).frames, nil, version .. " slide behavior retained")
end
GameVersion.set("emerald")
game.session.version = "emerald"
require("src.import.gba.versions").select("emerald")
local Cache = require("tests.game3_cache")
local root = Cache.mount("scripts/movements.lua", { native = true })
if not root then
  print("[skip] 2764 extracted Emerald scenes: " .. tostring(Cache.reason))
  T.finish("game3_cutscene_push_2764")
end
local Dataset = require("src.core.game3.dataset")
Dataset.hydrate(game)
local bundle = require("src.import.gba.extract_scripts").loadBundle(Cache.cache(), root, { allowIncomplete = true })
local moves = bundle.movements
local function enter(id)
  game.session.map = id
  local def = assert(game.data.maps[id])
  Collision.bindMap(game, id, def)
  Objects.loadMap(game, id, def)
end
local function stepFor(n)
  for _ = 1, n do tick() end
end
enter("EM_ROUTE119_WEATHER_INSTITUTE_2F")
Player.reset(5, 6, "left")
local grunt = assert(Objects.find(7))
grunt.hidden = false
Objects.applyMovement(7, assert(moves["g3:08270170"]))
Objects.applyMovement(255, assert(moves["g3:0827017c"]))
stepFor(80)
T.eq(Player.py, 96, "Weather player stays until shove")
stepFor(6)
T.eq(Player.cellY, 5, "Weather six-frame north shove complete")
T.check(grunt.moving, "Weather shove precedes grunt completion")
stepFor(2)
T.eq(grunt.cellX, 5, "Weather grunt reaches destination")
T.eq(Player.cellY, 5, "Weather player vacated grunt destination")
stepFor(4)
Objects.applyMovement(255, assert(moves["g3:08270184"]))
local scientist = assert(Objects.find(5))
scientist.cellX, scientist.cellY, scientist.px, scientist.py = 1, 6, 16, 96
scientist.hidden = false
Objects.applyMovement(5, assert(moves["g3:08270187"]))
stepFor(2)
T.eq(Player.cellY, 6, "Weather return slide lasts two frames")
stepFor(48)
T.eq(Player.cellX, 5, "Weather dialogue player x")
T.eq(Player.cellY, 6, "Weather dialogue player y")
T.eq(scientist.cellX, 4, "Weather dialogue scientist x")
T.eq(scientist.cellY, 6, "Weather dialogue scientist y")
enter("EM_SLATEPORT_CITY_OCEANIC_MUSEUM_2F")
Player.reset(12, 6, "left")
local archie, other = assert(Objects.find(2)), assert(Objects.find(4))
other.cellX, other.cellY, other.px, other.py = 10, 6, 160, 96
archie.hidden, other.hidden = false, false
Objects.applyMovement(2, assert(moves["g3:0820bcd8"]))
Objects.applyMovement(4, assert(moves["g3:0820bcfe"]))
stepFor(140)
T.check(archie.moving and other.moving and other.py > 96, "Museum grunt vacates during Archie approach")
stepFor(4)
T.eq(archie.cellX, 10, "Museum Archie destination x")
T.eq(archie.cellY, 6, "Museum Archie destination y")
T.eq(other.cellY, 7, "Museum grunt vacates destination on time")
T.eq(Player.cellY, 6, "Museum player was not shoved")
T.finish("game3_cutscene_push_2764")
