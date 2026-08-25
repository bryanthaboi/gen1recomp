-- Central session lifecycle orchestrator.  Subsystems register teardown hooks
-- at module load (Assets release/invalidate bus, process shutdown below); the
-- host only calls phase entry points.
--
-- Three tiers:
--   mount  endMountedSession   — GPU release + CacheFs/Data/Runtime/Assets
--   game   endGameSession      — audio + game:reset; workers stay alive
--   process endProcess          — worker shutdown on real app exit (love.quit)
--
-- Hot reload (Assets.flush / installLoader) stays invalidate-only forever.

local SessionLifecycle = {}

local processShutdowns = {}

function SessionLifecycle.registerProcessShutdown(fn)
  processShutdowns[#processShutdowns + 1] = fn
end

-- Drop CacheFs / Data / mod Runtime / Assets / LegacyCompat for one mounted
-- version session (save editor or game).  GPU release runs before soft
-- invalidate via installLoader(nil).
function SessionLifecycle.endMountedSession(version)
  local Assets = require("src.render.Assets")
  if Assets.releaseSession then Assets.releaseSession() end
  if version then
    require("src.import.CacheFs").unmountVersion(version)
  end
  require("src.core.Data"):unloadGenerated()
  local Runtime = require("src.mods.Runtime")
  if Runtime.reset then Runtime.reset() end
  if Assets.installLoader then Assets.installLoader(nil) end
  local okCompat, LegacyCompat = pcall(require, "src.mods.LegacyCompat")
  if okCompat and LegacyCompat.reset then LegacyCompat.reset() end
end

-- Evict every save-editor module from package.loaded without a hardcoded
-- panel whitelist.  Flat require names (App, Party, …) resolve under
-- tools/save-editor/; path-style keys may also appear.
local function flushEditorPackageLoaded()
  local fs = love and love.filesystem
  local function isEditorFlat(name)
    if not (fs and fs.getInfo) then return false end
    if name:find("[./]") then return false end
    return fs.getInfo("tools/save-editor/" .. name .. ".lua") ~= nil
      or fs.getInfo("tools/save-editor/panels/" .. name .. ".lua") ~= nil
  end
  for k in pairs(package.loaded) do
    if type(k) == "string"
        and (k:find("save%-editor", 1, false) or isEditorFlat(k)) then
      package.loaded[k] = nil
    end
  end
end

function SessionLifecycle.endEditorSession(opts)
  opts = opts or {}
  if opts.app and opts.app.unload then pcall(opts.app.unload) end
  flushEditorPackageLoaded()
  if opts.version then
    SessionLifecycle.endMountedSession(opts.version)
  end
end

-- EXIT GAME / intent_game before dropping Game.  Stops audio and resets the
-- live game instance so map/GPU holders are gone before endMountedSession.
function SessionLifecycle.endGameSession(game)
  pcall(function() require("src.core.Music").stop() end)
  pcall(function() require("src.core.Sound").stop() end)
  if package.loaded["src.core.ChipAudio"] then
    pcall(package.loaded["src.core.ChipAudio"].shutdown)
  end
  if package.loaded["src.core.DiscordPresence"] then
    pcall(package.loaded["src.core.DiscordPresence"].shutdown)
  end
  if package.loaded["src.core.gen2.Clock"] then
    pcall(package.loaded["src.core.gen2.Clock"].shutdown)
  end
  if package.loaded["src.net.Gen1Tls"] then
    pcall(package.loaded["src.net.Gen1Tls"].shutdown)
  end
  if love.audio and love.audio.stop then
    pcall(love.audio.stop)
  end
  pcall(function() require("src.render.SecondScreen").setEnabled(false) end)

  if game and game.reset then
    pcall(function() game:reset() end)
  end
  -- Gen1 Game is the module singleton.  If teardown left it without load,
  -- drop the cached module so the next require rebuilds a clean table
  -- (bootGame also guards this; doing it here keeps Play-again reliable).
  if game and type(game.load) ~= "function"
      and package.loaded["src.core.Game"] == game then
    package.loaded["src.core.Game"] = nil
  end

  local Input = require("src.core.Input")
  local TouchControls = require("src.core.TouchControls")
  Input:reset()
  TouchControls:reset()
end

function SessionLifecycle.endProcess()
  for _, fn in ipairs(processShutdowns) do pcall(fn) end
end

return SessionLifecycle
