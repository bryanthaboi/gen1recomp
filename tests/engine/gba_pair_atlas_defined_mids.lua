package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local GameVersion = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local NativePack = require("src.import.gba.native_pack")

for _, case in ipairs({ { "firered", 640 }, { "emerald", 512 } }) do
  local version, primary = case[1], case[2]
  GameVersion.set(version)
  Versions.select(version)
  local bundle = { primaryMt = { count = 7 }, secondaryMt = { count = 5 } }
  local grids = { X = { pair = "p", cells = { { mid = 3 } } } }
  local list = NativePack.collectMidsForPair(grids, {}, "p", nil, bundle)
  local set = {}
  for _, mid in ipairs(list) do set[mid] = true end
  for mid = 0, 6 do T.check(set[mid], version .. " packs primary metatile " .. mid) end
  for i = 0, 4 do T.check(set[primary + i], version .. " packs secondary metatile " .. (primary + i)) end
  T.check(not set[7] and not set[primary + 5], version .. " packs nothing past the defined counts")
  for i = 2, #list do T.check(list[i - 1] < list[i], version .. " the mid list stays sorted") end
end

T.finish("gba pair atlas packs every defined metatile")
