-- constants/engine_flags.asm:2

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local version = os.getenv("POKEPORT_VERSION") or "crystal"
require("src.core.GameVersion").set(version)

local root = require("tests.cache_gen2_constants").root(version)
if not root then
  print("[skip] gen2 boot binds engine flags: no " .. version .. " cache")
  os.exit(0)
end

local function slurp(rel)
  local f = io.open(root .. "/" .. rel, "rb")
  if not f then return nil end
  local bytes = f:read("*a")
  f:close()
  return bytes
end

local CacheFs = require("src.import.CacheFs")
CacheFs.readActive = slurp
CacheFs.loadActive = function(rel)
  local bytes = slurp(rel)
  if not bytes then return nil, "missing " .. rel end
  return assert(loadstring(bytes, "@" .. rel))()
end
package.loaded["src.core.DiscordPresence"] = { init = function() end }

local Runtime = require("src.mods.Runtime")
local Game2 = require("src.core.Game2")
local Pokegear = require("src.ui.gen2.Pokegear")

local Clock = require("src.core.gen2.Clock")

local ready, worldAtReady, ok, cards, dayOk, day
local emit = Runtime.emit
Runtime.emit = function(name, payload)
  if name == "game.ready" then
    ready = true
    worldAtReady = payload.game.world
    local reader = setmetatable({ save = payload.game.save }, Pokegear)
    ok, cards = pcall(reader.visibleCards, reader)
    dayOk, day = pcall(Clock.weekdayName, 1)
  end
  return emit(name, payload)
end

local game = Game2.new()
local loaded, err = pcall(game.load, game, {})
Runtime.emit = emit

T.check(loaded, "Game2:load boots headless: " .. tostring(err))
T.check(ready, "game.ready is emitted")
T.eq(worldAtReady, nil, "with no World built yet")
T.check(ok, "a bare { save } Pokegear reader lists its cards at game.ready: "
  .. tostring(cards))
T.check(type(cards) == "table" and #cards >= 1, "and the clock card is among them")

T.check(dayOk and type(day) == "string" and day ~= "",
  "Clock.weekdayName reads the boot dataset when handed none: " .. tostring(day))

T.finish("gen2 boot binds engine flags 3147")
