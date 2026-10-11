#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
_G.love = { graphics = gfx }

package.loaded["src.core.game3.audio"] = {
  install = function() return true end,
  playSe = function() end,
  playSong = function() end,
  playFanfare = function() end,
  stopAll = function() end,
  stopSurfMusic = function() end,
  waitSe = function(_, cb) if cb then cb() end end,
}

local Versions = require("src.import.gba.versions")
local GameVersion = require("src.core.GameVersion")

local function emeraldRoot()
  local home, identity = os.getenv("HOME"), os.getenv("POKEPORT_IDENTITY")
  if not (home and identity and identity ~= "") then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    local root = base .. "/" .. identity .. "/emerald/data/generated/gba"
    local f = io.open(root .. "/meta.json", "rb")
    if f then
      local src = f:read("*a") or ""
      f:close()
      local want = Versions.select("emerald") and Versions.CACHE_VERSION
      Versions.select("firered")
      if tonumber(src:match('"cache_version"%s*:%s*(%d+)')) == want then return root end
    end
  end
  return nil
end

GameVersion.set("firered")
local Cache = require("tests.game3_cache")
local version, mapId
if Cache.root("scripts/events.lua", { native = true }) then
  Cache.mount("scripts/events.lua", { native = true })
  version, mapId = "firered", "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
else
  local root = emeraldRoot()
  if not root then
    print("[skip] game3_escalator_elevation_test: " .. tostring(Cache.reason or "no imported FireRed or Emerald cache"))
    finish()
  end
  GameVersion.set("emerald")
  Versions.select("emerald")
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = root
  Dataset.mountExtractRoots()
  version, mapId = "emerald", "EM_OLDALE_TOWN_POKEMON_CENTER_2F"
end
print("[info] " .. version .. " " .. mapId)

local Dataset = require("src.core.game3.dataset")
local game = { data = {} }
Dataset.hydrate(game)

local Map = require("src.core.game3.map")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local Warp = require("src.core.game3.warp")

local def = game.data.maps[mapId]
check(def ~= nil, mapId .. " exists")
if not def then finish() end
pcall(Map.ensureMidLayout, game, mapId, def)
Collision.bindMap(game, mapId, def)
game.currentMap = mapId

check(Collision.isEscalator(Collision.behavior(1, 6)), "(1,6) is an escalator")
check(Collision.elevationAt(1, 6) == 4, "(1,6) escalator sits at elevation 4")
check(Collision.elevationAt(1, 5) == 3, "(1,5) above the escalator is elevation 3")
check(Collision.elevationAt(1, 7) == 3, "(1,7) below the escalator is elevation 3")

local started
local realStart = Warp.startEscalator
Warp.startEscalator = function(...) started = { ... } end

local function attempt(x, y, elevation, dir)
  started = nil
  Player.cellX, Player.cellY = x, y
  Player.facing = dir
  Player.moving = false
  Player.turnTimer = 0
  Player.turnArmed = false
  Player.currentElevation = elevation
  return Player.tryMove(dir, game, false)
end

local r = attempt(1, 5, 3, "down")
check(r ~= "escalator" and started == nil,
  "walking DOWN from (1,5) at elevation 3 does not ride the escalator (got " .. tostring(r) .. ")")

r = attempt(1, 7, 3, "up")
check(r ~= "escalator" and started == nil,
  "walking UP from (1,7) at elevation 3 does not ride the escalator (got " .. tostring(r) .. ")")

local sideElev = Collision.elevationAt(2, 6)
r = attempt(2, 6, sideElev, "left")
check(r == "escalator" and started ~= nil,
  "walking LEFT from (2,6) at elevation " .. tostring(sideElev) .. " rides the escalator (got " .. tostring(r) .. ")")

Warp.startEscalator = realStart
finish()
