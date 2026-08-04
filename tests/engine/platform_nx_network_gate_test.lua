-- Self-updater and remote mod download must stay off on NX until validated.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
love.system = love.system or {}
love.filesystem = love.filesystem or {}

local S = require("tests.harness").suite("platform NX network gate")
local check = S.check
local eq = S.eq

local checkStarted = false
package.loaded["src.update.Check"] = {
  start = function() checkStarted = true end,
  state = function() return { status = "idle" } end,
}

love.system.getOS = function() return "NX" end
love.filesystem.isFused = function() return true end
love.filesystem.getSaveDirectory = function() return "/save/pokemon-love2d" end

package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil
local RomImporter = require("src.import.RomImporter")

local ri = RomImporter.new(function() end, { launcher = true })
ri.ready = { red = false, blue = false, yellow = false }
eq(checkStarted, false, "self-updater does not start on NX fused launcher")
check(ri.Check == nil, "launcher has no Check module on NX")

eq(require("src.core.Platform").networkValidated(), false,
  "NX reports networkValidated false")

ri.mods = { { id = "demo", name = "Demo", github = "owner/repo", version = "1.0.0" } }
ri:_modGithubAction("demo", "update")
check(ri.modNotice and not ri.modNotice.ok,
  "remote mod github action is blocked on NX")

ri.tab = "find"
ri:_refreshFind(true)
eq(#((ri.findIndex and ri.findIndex.mods) or {}), 0,
  "find mods refresh stays empty on NX")

package.loaded["src.update.Check"] = nil
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
