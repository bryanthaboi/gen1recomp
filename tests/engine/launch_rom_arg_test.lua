-- --rom=PATH: a launcher that holds the player's copy hands it over on the
-- command line.  Parsing only; main.lua decides whether to import it.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local LaunchOptions = require("src.core.LaunchOptions")

do
  local request = LaunchOptions.resolveRequest({ "--game=red" }, nil)
  eq(request.rom, nil, "without --rom there is no ROM to import")
  eq(request.game, "red", "and the game is read as before")
end

do
  local request = LaunchOptions.resolveRequest(
    { "--game=blue", "--rom=C:\\Roms\\Pokemon Blue.gb" }, nil)
  eq(request.rom, "C:\\Roms\\Pokemon Blue.gb", "--rom keeps a path with spaces")
  eq(request.game, "blue", "next to the game it belongs to")
end

do
  local request = LaunchOptions.resolveRequest({ "--rom=" }, nil)
  eq(request.rom, nil, "an empty --rom counts as none")
end

T.finish("launch --rom argument")
