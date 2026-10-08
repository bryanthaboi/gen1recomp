package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local function read(path)
  local file = assert(io.open(path, "rb"))
  local body = file:read("*a")
  file:close()
  return body
end

local main = read("main.lua")
local hostSource = read("src/core/HostShell.lua")
local quitSource = assert(main:match("\nfunction love%.quit%(%).-\nend\n"))
local returnSource = assert(main:match("local function returnToLauncher%([^)]*%).-\nend\n"))
local endSource = assert(main:match("local function endProcessOnce%(%).-\nend\n"))
local dispatchSource = assert(main:match('(        if name == "quit" then.-)\n        if WAKE'))

local function scenario(osName, state, options)
  options = options or {}
  local stats = { events = {}, joins = 0, presence = 0, markers = 0,
    sessions = 0, editor = 0, platform = 0, splash = 0, theme = 0,
    observe = 0, flush = 0 }
  local env = setmetatable({ processEnded = false, quitToLauncher = false,
    launchedIntoGame = options.shortcut or false, editorMode = state == "editor",
    RELAUNCH_MARKER = "marker" }, { __index = _G })
  env.os = setmetatable({ getenv = function() return nil end }, { __index = os })
  env.Game = state == "game" and {} or nil
  env.Importer = state ~= "game" and { _themeVideo = {
    release = function() stats.theme = stats.theme + 1 end } } or nil
  env.launcherSplash = { release = function() stats.splash = stats.splash + 1 end }
  env.EditorApp = { quit = function() stats.editor = stats.editor + 1 return true end }
  env.PlatformHooks = { quitToLauncher = function(fn)
    stats.platform = stats.platform + 1
    if options.platformVeto then return true end
    return fn()
  end }
  env.love = {
    system = { getOS = function() return osName end },
    event = { quit = function(value) stats.events[#stats.events + 1] = value or 0 end },
    filesystem = { write = function() stats.markers = stats.markers + 1 end },
  }
  env.SessionLifecycle = {
    endProcess = function() stats.joins = stats.joins + 1 end,
    endGameSession = function() stats.sessions = stats.sessions + 1 end,
  }
  local hostChunk = assert(loadstring(hostSource, "@src/core/HostShell.lua"))
  setfenv(hostChunk, env)
  local host = hostChunk()
  env.require = function(name)
    if name == "src.core.HostShell" then return host end
    if name == "src.core.SessionLifecycle" then return env.SessionLifecycle end
    if name == "src.core.DiscordPresence" then
      return { shutdown = function() stats.presence = stats.presence + 1 end }
    end
    if name == "src.core.SaveSerializer" then return { encode = function() return "{}" end } end
    if name == "src.import.LauncherWindow" then
      return { observe = function() stats.observe = stats.observe + 1 end,
        flush = function() stats.flush = stats.flush + 1 end }
    end
    error("unexpected module " .. name)
  end
  local chunk = assert(loadstring(endSource .. "\n" .. returnSource .. "\n"
    .. quitSource .. '\nreturn { quit = love.quit, explicitReturn = returnToLauncher, dispatch = function(a)\n'
    .. 'local name = "quit"\n' .. dispatchSource .. '\nreturn "veto"\nend }', "@main.lua:quit-policy"))
  setfenv(chunk, env)
  return chunk(), stats, env
end

for _, state in ipairs({ "game", "launcher", "editor" }) do
  local callbacks, stats, env = scenario("NX", state, { platformVeto = true })
  eq(callbacks.dispatch(), 0, "NX " .. state .. " accepts system quit")
  eq(stats.joins, 1, "NX " .. state .. " tears down workers once")
  eq(stats.presence, 1, "NX " .. state .. " tears down presence once")
  eq(#stats.events, 0, "NX " .. state .. " queues no restart")
  eq(stats.markers, 0, "NX " .. state .. " writes no launcher handoff")
  eq(stats.platform, 0, "NX " .. state .. " bypasses platform veto")
  eq(stats.editor, 0, "NX " .. state .. " bypasses editor veto")
  eq(stats.splash, 1, "NX " .. state .. " releases splash")
  if state ~= "game" then
    eq(stats.theme, 1, "NX " .. state .. " releases launcher theme")
    eq(stats.observe, 1, "NX " .. state .. " observes launcher window")
    eq(stats.flush, 1, "NX " .. state .. " flushes launcher window")
    eq(env.Importer._themeVideo, nil, "NX " .. state .. " drops theme reference")
  end
  eq(callbacks.dispatch(), 0, "NX " .. state .. " accepts repeated quit")
  eq(stats.joins, 1, "NX " .. state .. " repeated quit keeps teardown idempotent")
end

local desktop, desktopStats = scenario("OS X", "game")
eq(desktop.dispatch(), "veto", "desktop game close returns to launcher")
eq(desktopStats.events[1], "restart", "desktop game close requests restart")
eq(desktopStats.markers, 1, "desktop game close writes launcher handoff")
eq(desktopStats.joins, 1, "desktop game close joins before restart")
eq(desktop.dispatch("restart"), "restart", "desktop queued restart is accepted")
eq(desktopStats.joins, 1, "desktop queued restart avoids duplicate joins")

local editor, editorStats = scenario("OS X", "editor")
eq(editor.dispatch(), "veto", "desktop editor preserves unsaved-change veto")
eq(editorStats.joins, 0, "desktop editor veto leaves workers running")

local shortcut, shortcutStats = scenario("OS X", "game", { shortcut = true })
eq(shortcut.dispatch(), 0, "desktop shortcut exits without returning to launcher")
eq(#shortcutStats.events, 0, "desktop shortcut queues no restart")

local restart, restartStats = scenario("NX", "game")
eq(restart.dispatch("restart"), "restart", "NX explicit restart keeps requested native action")
eq(restartStats.joins, 1, "NX explicit restart joins workers once")
eq(#restartStats.events, 0, "NX explicit restart adds no event")
eq(restartStats.markers, 0, "NX explicit restart adds no launcher handoff")

local inGame, inGameStats = scenario("NX", "game")
inGame.explicitReturn()
eq(inGameStats.events[1], "restart", "NX in-game EXIT GAME retains explicit restart")
eq(inGameStats.markers, 1, "NX in-game EXIT GAME retains launcher handoff")
eq(inGameStats.sessions, 1, "NX in-game EXIT GAME ends game session")
eq(inGameStats.joins, 1, "NX in-game EXIT GAME joins workers once")
eq(inGame.dispatch("restart"), "restart", "NX in-game queued restart retains action")
eq(inGameStats.joins, 1, "NX in-game queued restart avoids duplicate joins")
check(inGameStats.events[2] == nil, "NX in-game queued restart adds no event")

T.finish("nx_quit_policy_2720")
