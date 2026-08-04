-- Blue/Yellow mountVersion must overlay save-dir caches without FFI (NX).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")

love.filesystem._mounts = {}
-- Imply blue/data/generated and blue/assets/generated directories via file keys.
love.filesystem.write("blue/data/generated/maps.lua", "return {}")
love.filesystem.write("blue/data/generated/constants.lua", "return {}")
love.filesystem.write("blue/assets/generated/fonts/font.png", "font-bytes")

check(CacheFs.mountVersion("blue") == true, "mountVersion(blue) returns true")

local sawBlueRoot, sawDataGen, sawAssetsGen = false, false, false
for _, m in ipairs(love.filesystem._mounts) do
  if m.archive == "blue" and m.mountpoint == "" and m.append == false then
    sawBlueRoot = true
  end
  if m.archive == "blue/data/generated" and m.mountpoint == "data/generated"
      and m.append == false then
    sawDataGen = true
  end
  if m.archive == "blue/assets/generated" and m.mountpoint == "assets/generated"
      and m.append == false then
    sawAssetsGen = true
  end
end
check(sawBlueRoot, "prepend-mounts save-dir relative blue/")
check(sawDataGen, "prepend-mounts blue/data/generated -> data/generated")
check(sawAssetsGen, "prepend-mounts blue/assets/generated -> assets/generated")

eq(love.filesystem.read("assets/generated/fonts/font.png"), "font-bytes",
  "post-mount probe can read unprefixed assets/generated canary")
eq(love.filesystem.read("data/generated/constants.lua"), "return {}",
  "post-mount probe can read unprefixed data/generated canary")

-- Yellow-only: same overlay contract
love.filesystem._mounts = {}
GameVersion.set("yellow")
love.filesystem.write("yellow/data/generated/constants.lua", "return {y=1}")
love.filesystem.write("yellow/assets/generated/fonts/font.png", "yellow-font")
check(CacheFs.mountVersion("yellow") == true, "mountVersion(yellow) returns true")
eq(love.filesystem.read("assets/generated/fonts/font.png"), "yellow-font",
  "Yellow mount exposes fonts/font.png at the unprefixed path")

GameVersion.set("red")
T.finish()
