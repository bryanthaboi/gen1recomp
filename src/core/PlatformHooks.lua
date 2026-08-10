-- Generic process-lifecycle mod hooks so a platform-specific launcher
-- integration (a native shell embedding this engine, e.g. wrapping the
-- window in a platform UI) can live entirely in a mod instead of
-- hand-patching main.lua, which every other engine change also touches.
-- See docs/modding.md's "Process-lifecycle hooks" section.
local ModRuntime = require("src.mods.Runtime")

local PlatformHooks = {}

function PlatformHooks.update(game, dt)
  return ModRuntime.call("core.update", function(g, d) g:update(d) end, game, dt)
end

function PlatformHooks.quitToLauncher(vanilla)
  return ModRuntime.call("core.quit_to_launcher", vanilla)
end

return PlatformHooks
