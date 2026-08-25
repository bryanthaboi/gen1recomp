package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = love or require("tests.love_stub")

local NAME = "src.render.ShaderFX"

local function withFfi(fakeFfi, os, fn)
  local oldModule = package.loaded[NAME]
  local oldFfi = package.loaded.ffi
  local oldPreload = package.preload.ffi
  local oldGetOS = love.system.getOS
  if os then love.system.getOS = function() return os end end
  package.loaded[NAME] = nil
  package.loaded.ffi = nil
  package.preload.ffi = function() return fakeFfi end
  local ShaderFX = require(NAME)
  local can, err = ShaderFX.canConvert(), ShaderFX.bridgeError()
  if fn then fn(ShaderFX) end
  package.loaded[NAME] = oldModule
  package.loaded.ffi = oldFfi
  package.preload.ffi = oldPreload
  love.system.getOS = oldGetOS
  return can, err, ShaderFX
end

local function baseFfi()
  return {
    cdef = function() end,
    load = function() error("no such library") end,
    string = function(value) return value end,
  }
end

local staticFfi = baseFfi()
staticFfi.C = {
  librashader_translate_preset = function() return "{}" end,
  librashader_free_string = function() end,
}

local can, err = withFfi(staticFfi)
T.eq(can, true, "a statically linked bridge is found through ffi.C")
T.eq(err, nil, "the ffi.C fallback leaves no bridge error behind")

local emptyFfi = baseFfi()
emptyFfi.C = setmetatable({}, {
  __index = function() error("undefined symbol") end,
})

local missing, missingErr = withFfi(emptyFfi)
T.eq(missing, false, "no library and no ffi.C symbol means no conversion")
T.check(missingErr and missingErr:find("ffi.C has no librashader_translate_preset", 1, true) ~= nil,
  "libError says ffi.C was probed too (got " .. tostring(missingErr) .. ")")
T.check(missingErr and missingErr:find("looked in", 1, true) ~= nil,
  "libError still lists the paths that were tried")

local iosMissing, iosErr = withFfi(baseFfi(), "iOS")
T.eq(iosMissing, false, "iOS with no static symbol cannot convert")
T.check(iosErr and iosErr:find("ffi.C has no librashader_translate_preset", 1, true) ~= nil,
  "iOS libError names the ffi.C probe")
T.check(iosErr and iosErr:find("looked in", 1, true) == nil,
  "iOS lists no file candidates (got " .. tostring(iosErr) .. ")")

local iosCan = withFfi(staticFfi, "iOS")
T.eq(iosCan, true, "iOS resolves the bridge through ffi.C alone")

local freed = false
local translateFfi = baseFfi()
translateFfi.C = {
  librashader_translate_preset = function(path, es)
    return ('{"pass_count":1,"passes":[{"name":"%s","es":%d}]}'):format(path, es)
  end,
  librashader_free_string = function() freed = true end,
}
withFfi(translateFfi, "iOS", function(ShaderFX)
  local preset, terr = ShaderFX.translate("/presets/a.slangp", true)
  T.check(preset ~= nil, "translate works with lib == ffi.C (" .. tostring(terr) .. ")")
  T.eq(preset and preset.passes[1].name, "/presets/a.slangp",
    "the ffi.C symbol receives the preset path")
  T.eq(preset and preset.passes[1].es, 1, "the es flag reaches the ffi.C symbol")
  T.eq(freed, true, "the returned string is freed through ffi.C")
end)

T.finish("shaderfx ffi.C fallback")
