package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq

local function configure(osName, major)
  love = {
    _os = osName,
    getVersion = function() return major, 0, 0 end,
    filesystem = { setSymlinksEnabled = function() end },
  }
  dofile("conf.lua")
  local config = { window = {}, modules = {}, graphics = {} }
  love.conf(config)
  return config
end

local mac11 = configure("OS X", 11)
eq(mac11.version, "11.5", "LÖVE 11 macOS builds keep their version")
eq(mac11.graphics.renderers, nil, "LÖVE 11 does not receive a Metal option")

local mac12 = configure("OS X", 12)
eq(mac12.version, "12.0", "LÖVE 12 macOS builds declare version 12")
eq(mac12.graphics.renderers[1], "metal", "LÖVE 12 macOS uses Metal")
eq(#mac12.graphics.renderers, 1, "macOS excludes the broken OpenGL fallback")

local linux12 = configure("Linux", 12)
eq(linux12.version, "11.5", "other desktop builds keep their version")
eq(linux12.graphics.renderers, nil, "other desktops keep default renderers")

local ios12 = configure("iOS", 12)
eq(ios12.version, "12.0", "iOS keeps its existing version")
eq(ios12.graphics.renderers, nil, "iOS keeps its existing renderer selection")

print("macOS Metal configuration: PASS")
