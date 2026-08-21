-- UiFont is deliberately fail-safe because trimmed platform builds may omit
-- its fallback face. Pin its size selection, cache, and negative paths.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness").suite("ui font")

local created, filters = {}, {}
love = { graphics = {} }
love.graphics.newFont = function(path, size)
  local fallback = {
    path = path,
    size = size,
    setFilter = function(_, min, mag)
      filters[#filters + 1] = { min, mag }
    end,
  }
  created[#created + 1] = fallback
  return fallback
end

package.loaded["src.render.UiFont"] = nil
local UiFont = require("src.render.UiFont")

local attached = {}
local primary = {
  getHeight = function() return 22 end,
  setFallbacks = function(_, fallback) attached[#attached + 1] = fallback end,
}
T.eq(UiFont.attach(primary), primary, "attach returns the primary font")
T.eq(created[1].size, 15, "22px primary snaps to the nearest 15px design size")
T.eq(created[1].path, "assets/fonts/plainpixel/PlainPixel-Regular.ttf",
  "the bundled fallback face is selected")
T.eq(filters[1][1], "nearest", "fallback uses nearest minification")
T.eq(filters[1][2], "nearest", "fallback uses nearest magnification")
T.eq(attached[1], created[1], "fallback is attached to the primary face")

UiFont.attach(primary, 20)
T.eq(#created, 1, "sizes in the same snapped bucket reuse the fallback")
T.eq(attached[2], created[1], "cached fallback remains attachable")

UiFont.attach(primary, 23)
T.eq(created[2].size, 30, "size above the midpoint snaps to the next design size")

local withoutApi = {}
T.eq(UiFont.attach(withoutApi, 30), withoutApi,
  "font without setFallbacks is returned unchanged")
T.eq(#created, 2, "unsupported primary font does not allocate a fallback")

UiFont.clear()
local attempts = 0
love.graphics.newFont = function()
  attempts = attempts + 1
  error("font missing")
end
T.eq(UiFont.attach(primary, 15), primary, "missing fallback fails open")
T.eq(UiFont.attach(primary, 30), primary, "known missing fallback keeps failing open")
T.eq(attempts, 1, "missing fallback is not retried every draw")

UiFont.clear()
love.graphics.newFont = function()
  attempts = attempts + 1
  return { setFilter = function() error("filter unsupported") end }
end
local rejectingPrimary = { setFallbacks = function() error("fallback unsupported") end }
local okAttach, returned = pcall(UiFont.attach, rejectingPrimary, 15)
T.check(okAttach and returned == rejectingPrimary,
  "font filter and attachment errors are swallowed")
T.eq(attempts, 2, "clear permits one new fallback load attempt")

package.loaded["src.render.UiFont"] = nil
T.finish()
