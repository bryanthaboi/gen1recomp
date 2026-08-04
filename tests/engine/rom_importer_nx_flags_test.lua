-- NX RomImporter must not inherit Android mobile-file-bridge semantics (SWNX-03).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer NX flags")
local eq = S.eq
local check = S.check

love.system = love.system or {}
love.filesystem = love.filesystem or {}
local saved = {
  getOS = love.system.getOS,
  getSaveDirectory = love.filesystem.getSaveDirectory,
  createDirectory = love.filesystem.createDirectory,
}

love.system.getOS = function() return "NX" end
love.filesystem.getSaveDirectory = function() return "sdmc:/switch/gen1recomp/pokemon-love2d" end
love.filesystem.createDirectory = function() return true end

package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil
local RomImporter = require("src.import.RomImporter")

local ri = RomImporter.new(function() end, { launcher = true })
eq(ri.isNX, true, "NX importer sets isNX")
eq(ri.android, false, "NX importer does not set android")
eq(ri.mobileFileBridge, false, "NX importer does not set mobileFileBridge")
eq(ri.romImportMode, "save-directory", "NX importer exposes save-directory mode")
check(ri.pickPending == nil, "NX importer does not arm mobile pick polling")

love.system.getOS = function() return "Android" end
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil
RomImporter = require("src.import.RomImporter")
ri = RomImporter.new(function() end, { launcher = true })
eq(ri.isNX, false, "Android importer is not NX")
eq(ri.android, true, "Android importer keeps android mobile path")
eq(ri.mobileFileBridge, true, "Android importer sets mobileFileBridge")

love.system.getOS = saved.getOS
love.filesystem.getSaveDirectory = saved.getSaveDirectory
love.filesystem.createDirectory = saved.createDirectory
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
