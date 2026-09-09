-- #2166: the mouse wheel zoomed Gen 2's world through World:zoomStep without
-- writing the new offset into options.zoom, so the next Game2:applyOptions
-- (leaving OPTIONS, CONTINUE) snapped the camera back to the stored level.
--   luajit tests/engine/gen2_wheel_zoom_persists_bug2166.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Zoom = require("src.render.Zoom")
local Game2 = require("src.core.Game2")

local function fakeGame()
  local persisted = 0
  local world = { map = {}, fitScale = function() return 4 end }
  function world:zoomStep(delta) Zoom.step(delta, self:fitScale()) end
  function world:zoomCycle() Zoom.cycle(self:fitScale()) end
  local game = {
    world = world,
    stack = { top = function() return nil end },
    options = { zoom = 0 },
    save = { options = nil },
    persistOptions = function() persisted = persisted + 1 end,
  }
  setmetatable(game, { __index = Game2 })
  return game, function() return persisted end
end

do
  Zoom.reset()
  local game, persisted = fakeGame()
  Game2.wheelmoved(game, 0, -1)
  eq(Zoom.offset, -1, "wheel down zooms the live world one step out")
  eq(game.options.zoom, -1, "BUG FIX: wheel zoom is written into options.zoom")
  eq(game.save.options, game.options, "the save's options table follows")
  eq(persisted(), 1, "and persisted once")

  Game2.applyOptions(game)
  eq(Zoom.offset, -1, "BUG FIX: re-applying options keeps the wheel zoom")

  Game2.wheelmoved(game, 0, 1)
  Game2.wheelmoved(game, 0, 1)
  eq(game.options.zoom, 1, "wheel up steps back in and is stored each time")
  eq(persisted(), 3, "one persist per wheel step")
end

do
  Zoom.reset()
  local game, persisted = fakeGame()
  Game2.hotkey(game, "-")
  eq(game.options.zoom, -1, "the - hotkey still stores the offset")
  Game2.hotkey(game, "4")
  eq(game.options.zoom, Zoom.offset, "the 4 hotkey still stores the offset")
  eq(persisted(), 2, "hotkeys persist once each")
end

do
  Zoom.reset()
  local game = fakeGame()
  game.world = nil
  Game2.wheelmoved(game, 0, 1)
  eq(game.options.zoom, 0, "no world: the wheel is ignored")
  game = fakeGame()
  game.stack.top = function() return {} end
  Game2.wheelmoved(game, 0, 1)
  eq(game.options.zoom, 0, "a menu on the stack: the wheel is ignored")
  check(Zoom.offset == 0, "and the live offset is untouched")
end

Zoom.reset()
T.finish("gen2 wheel zoom persists (#2166)")
