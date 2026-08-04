-- NX must not invoke HostShell / desktop file pickers (SWNX-04).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
love.system = love.system or {}
love.filesystem = love.filesystem or {}

local S = require("tests.harness").suite("platform NX shell gate")
local check = S.check
local eq = S.eq

local popenCalls = 0
local realHostShell = package.loaded["src.core.HostShell"]
package.loaded["src.core.HostShell"] = {
  envPrefix = function() return "" end,
  popen = function()
    popenCalls = popenCalls + 1
    return nil
  end,
  restart = function() end,
}

love.system.getOS = function() return "NX" end
love.filesystem.getSaveDirectory = function() return "/save/pokemon-love2d" end

package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil
local RomImporter = require("src.import.RomImporter")

local ri = RomImporter.new(function() end, { launcher = true })
ri.ready = { red = false, blue = false, yellow = false }

popenCalls = 0
ri:choose("red")
eq(popenCalls, 0, "choose on NX does not call HostShell.popen")
check(ri.notice ~= nil, "NX choose sets a save-directory notice")
check(ri.notice.detail:find("imports", 1, true) ~= nil,
  "notice mentions imports inbox path")

-- Desktop path still reaches the shell when a picker exists.
love.system.getOS = function() return "Linux" end
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil
RomImporter = require("src.import.RomImporter")
ri = RomImporter.new(function() end, { launcher = true })
ri.ready = { red = false, blue = false, yellow = false }
popenCalls = 0
ri:choose("red")
check(popenCalls >= 1 or ri.notice ~= nil,
  "Linux choose still attempts shell picker or falls back with notice")

package.loaded["src.core.HostShell"] = realHostShell
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
