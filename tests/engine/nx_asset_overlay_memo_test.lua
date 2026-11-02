package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Assets = require("src.render.Assets")
local Overlay = require("src.core.NxAssetOverlay")

local PNG = "assets/generated/sprites/oak.png"
local OTHER = "assets/generated/sprites/rival.png"
local MISSING = "assets/generated/sprites/no_such_sheet.png"
local savedVersion = GameVersion.get()

GameVersion.set("yellow")
love.filesystem.write("yellow/" .. PNG, "png")
love.filesystem.write("yellow/" .. OTHER, "png")

local stockGetInfo = love.filesystem.getInfo
local probes = {}
love.filesystem.getInfo = function(path, ...)
  probes[path] = (probes[path] or 0) + 1
  return stockGetInfo(path, ...)
end
local function probed(path) return probes["yellow/" .. path] or 0 end

Overlay.install()

local first = love.graphics.newImage(PNG)
eq(first.path, "yellow/" .. PNG, "the first load opens the versioned copy")
eq(probed(PNG), 1, "and probes the versioned tree once")
local second = love.graphics.newImage(PNG)
eq(second.path, "yellow/" .. PNG, "a repeat load opens the versioned copy")
eq(probed(PNG), 1, "without probing the versioned tree again")

love.image.newImageData(PNG)
love.filesystem.read(PNG)
eq(probed(PNG), 1, "other loaders share the same answer")

check(love.filesystem.getInfo(PNG) ~= nil,
  "getInfo still reports the versioned file")
eq(probed(PNG), 2, "with one real stat for the caller and no extra probe")

love.graphics.newImage(OTHER)
love.graphics.newImage(OTHER)
eq(probed(OTHER), 1, "each path is probed once")

love.graphics.newImage(MISSING)
love.graphics.newImage(MISSING)
eq(probed(MISSING), 2, "a miss is not remembered, so a later import is seen")
love.filesystem.write("yellow/" .. MISSING, "png")
eq(love.graphics.newImage(MISSING).path, "yellow/" .. MISSING,
  "a versioned file written mid-session is picked up")

GameVersion.set("blue")
love.filesystem.write("blue/" .. PNG, "png")
eq(love.graphics.newImage(PNG).path, "blue/" .. PNG,
  "a version switch probes its own tree")
GameVersion.set("yellow")

Assets.invalidate()
love.graphics.newImage(PNG)
eq(probed(PNG), 3, "an asset flush drops the memo")

Overlay.uninstall()
Overlay.install()
love.graphics.newImage(PNG)
eq(probed(PNG), 4, "a reinstall starts from an empty memo")

Overlay.uninstall()
love.filesystem.getInfo = stockGetInfo
GameVersion.set(savedVersion)
T.finish("nx asset overlay memo")
