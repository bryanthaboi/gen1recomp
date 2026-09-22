-- A map loaded without a def must release the previous map's collision grid.
--
-- Regression: Map.load bound collision only when a def existed
-- (`if def then Collision.bindMap(...) end`), so loading a known-but-def-less id
-- kept the PREVIOUS map's grid live while Map.current, the session and the
-- player all moved on.  Movement was then validated against the map we left.
-- Collision.canEnter only falls back to the host map when no grid is bound
-- (collision.lua "Prefer owned grid; fall back to host map if unbound"), so the
-- def-less case must clear the binding.
--
-- Map.load's unrelated boundaries are stubbed; the collision binding is real.
--   luajit tests/engine/game3_map_def_less_bind_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.preload["src.core.game3.ghosts"] = function()
  return { capture = function() end, adopt = function() end }
end
package.preload["src.core.game3.scripting.space"] = function()
  return {
    bundle = {}, ensureBundle = function() end, attachEventsToMaps = function() end,
    activate = function() end, runEnterScripts = function() end,
  }
end
package.preload["src.core.game3.field"] = function()
  return { lock = function() end, unlock = function() end,
           clearMetatiles = function() end, metatileOverrides = {} }
end
package.preload["src.core.game3.runtime"] = function()
  return { isActive = function() return false end,
           getSession = function() return nil end, _mod = {} }
end
package.preload["src.core.game3.player"] = function()
  return { cellX = 0, cellY = 0, px = 0, py = 0, facing = "down", biking = false,
           reset = function() end, syncSavePosition = function() end }
end
package.preload["src.core.game3.objects"] = function() return { loadMap = function() end } end
package.preload["src.core.game3.audio"] = function()
  return { setSavedSong = function() end, playMapSong = function() end }
end
package.preload["src.core.game3.encounters"] = function()
  return { resetRateModifiers = function() end }
end
package.preload["src.core.game3.field_effects"] = function() return {} end
package.preload["src.core.game3.vs_seeker"] = function() return { mapReset = function() end } end
package.preload["src.core.game3.field_view"] = function()
  return { setDefaultFlashLevel = function() end }
end

local Map = require("src.core.game3.map")
local Collision = require("src.core.game3.collision")

local game = { data = { maps = {} }, save = {} }

-- Stage a binding as it would be after loading any real map.
Collision._grid = { 0, 0, 0, 0 }
Collision._mapId = "FR_PREV"
Collision._mapDef = { id = "FR_PREV" }
Collision._warps = {}
Collision._widthCells = 2
Collision._heightCells = 2
check(Collision._grid ~= nil, "a previous map's collision grid is bound")

-- game.data.maps has no entry for FR_MISSING, so Map.load resolves no def.
Map.load({}, game, "FR_MISSING", { seamless = true })

eq(Collision._grid, nil, "a def-less map load releases the previous collision grid")
eq(Collision._mapId, nil, "and forgets which map was bound")
eq(Collision._mapDef, nil, "and drops the previous map def")

T.finish("game3_map_def_less_bind_test")
