local T = require("tests.harness")

local cutoff = os.time({ year = 2026, month = 11, day = 1, hour = 0, min = 0, sec = 0 })
local file = assert(io.open("src/import/LauncherView.lua", "rb"))
local source = file:read("*a")
file:close()
local updateSource = assert(source:match(
  "function LauncherView%.update%(imp, dt%).-if imp%._launchFade then return end"))

local function scenario(now, expectedPath, expectedDuration, background)
  local options, loadedPath, clockReads = {}, nil, 0
  local elapsed = 0
  local resource = { setFilter = function() end, release = function() end }
  local video = {
    setFilter = function() end, getDimensions = function() return 1280, 720 end,
    getSource = function() end, play = function() end,
    tell = function() return elapsed end, isPlaying = function() return true end,
  }
  local env = setmetatable({
    os = { time = function(date)
      clockReads = clockReads + 1
      return date and os.time(date) or now
    end },
    love = { graphics = {
      newVideo = function(path) loadedPath = path return video end,
      newCanvas = function() return resource end,
      newShader = function() return resource end,
    } },
    require = function(name)
      assert(name == "src.core.SaveData")
      return { loadOptions = function() return options end }
    end,
  }, { __index = _G })
  local chunk = assert(loadfile("src/import/LauncherSplash.lua"))
  setfenv(chunk, env)
  local splash = chunk()
  local player = assert(splash.new())
  T.eq(loadedPath, expectedPath, "launch selects intro at " .. now)
  elapsed = expectedDuration - 0.04
  T.eq(player:update(0), false, "intro remains active before its end")
  elapsed = expectedDuration
  T.eq(player:update(0), true, "intro uses the selected video's duration")

  local created, updated, released = 0, 0, 0
  local viewEnv = setmetatable({ LauncherView = {}, require = function(name)
    if name == "src.import.LauncherSplash" then return splash end
    assert(name == "src.import.LauncherThemeVideo")
    return { new = function()
      created = created + 1
      return { update = function() updated = updated + 1 end,
        release = function() released = released + 1 end }
    end }
  end }, { __index = _G })
  local viewChunk = assert(loadstring(updateSource .. "\nend\nreturn LauncherView.update"))
  setfenv(viewChunk, viewEnv)
  local update = viewChunk()
  local imp = { _flex = {}, _settings = { opts = options }, _launchFade = true }
  update(imp, 0)
  T.eq(created, background and 1 or 0, "launch gates the background")
  local launchReads = clockReads
  now = cutoff + 86400
  update(imp, 0)
  splash.new()
  T.eq(loadedPath, expectedPath, "intro selection stays fixed for the process")
  T.eq(updated, background and 2 or 0, "open launcher keeps its launch selection")
  T.eq(clockReads, launchReads, "updates and subsequent intros do not read the clock")
  options.themeVideoBg = false
  update(imp, 0)
  T.eq(released, background and 1 or 0, "manual background toggle still works")
  options.splashVideo = false
  T.eq(splash.new(), nil, "manual intro toggle still works")
end

scenario(cutoff - 1, "assets/launcher/spooky.ogv", 381 / 30, true)
scenario(cutoff, "assets/launcher/splash.ogv", 127 / 30, false)
scenario(cutoff + 365 * 86400, "assets/launcher/splash.ogv", 127 / 30, false)
T.finish("launcher_season_cutoff")
