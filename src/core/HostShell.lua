-- Helpers for calling host tools (curl, zenity/kdialog, ...).

local HostShell = {}

-- Our AppRun exports LD_LIBRARY_PATH="$APPDIR/lib:..." so every subprocess we
-- spawn tries to link against the libraries we're shipping instead of the
-- system ones. We want to unset the var so that any system tools can find
-- their proper libraries. Only needed when running in an AppImage.
function HostShell.envPrefix()
  if os.getenv("APPIMAGE") then
    return "env -u LD_LIBRARY_PATH "
  end
  return ""
end

-- Windows: every host tool we shell out to (curl for the update and mod-index
-- fetches, the PowerShell ROM picker, the update downloader's `start /b`) is
-- spawned through io.popen / os.execute, which run it under cmd.exe.  A
-- GUI-subsystem process owns no console, so each of those children allocates
-- its own -- one console window flashing per call, several stacking up during
-- a mod install or an update (#606).  #74 fixed the same storm for the
-- per-file cache mkdir by dropping the shell entirely (src/import/CacheFs.lua);
-- the callers above genuinely need one, so we do the other half: allocate a
-- single console for ourselves, once, and hide it.  A child inherits the
-- parent's console when the parent has one, so every later spawn attaches to
-- that invisible console and pops up nothing.  GUI dialogs the children raise
-- (the PowerShell OpenFileDialog) are desktop windows and still appear.
--
-- Skipped when a console already exists, which is the developer case
-- (lovec.exe, what scripts/run.ps1 prefers, or t.console), so printed output
-- keeps landing in the terminal the game was launched from.  POKEPORT_CONSOLE=1
-- opts out entirely and restores the old behaviour.  Memoized; non-Windows and
-- FFI-less builds no-op.  Called once from love.load before anything shells
-- out (main.lua).
local consoleHidden = nil

function HostShell.hideHostConsole()
  if consoleHidden ~= nil then return consoleHidden end
  consoleHidden = false
  if os.getenv("POKEPORT_CONSOLE") == "1" then return consoleHidden end

  local okFfi, ffi = pcall(require, "ffi")
  if not okFfi or ffi.os ~= "Windows" then return consoleHidden end

  -- kernel32 (AllocConsole/GetConsoleWindow) and user32 (ShowWindow) are
  -- already loaded in any LOVE process, so ffi.C resolves both -- the same
  -- assumption CacheFs makes for CreateDirectoryA.
  pcall(ffi.cdef, [[
    void *GetConsoleWindow(void);
    int AllocConsole(void);
    int ShowWindow(void *hWnd, int nCmdShow);
  ]])
  local ok, hidden = pcall(function()
    if ffi.C.GetConsoleWindow() ~= nil then return false end
    if ffi.C.AllocConsole() == 0 then return false end
    local hwnd = ffi.C.GetConsoleWindow()
    if hwnd == nil then return false end
    ffi.C.ShowWindow(hwnd, 0) -- SW_HIDE
    return true
  end)
  consoleHidden = (ok and hidden) or false
  return consoleHidden
end

-- Wraps io.popen with the AppImage env fix applied and lua errors swallowed
function HostShell.popen(command, mode)
  local ok, pipe = pcall(io.popen, HostShell.envPrefix() .. command, mode or "r")
  if not ok or not pipe then return nil end
  return pipe
end

-- Restart the whole app. The obvious love.event.quit("restart") re-runs LÖVE's
-- boot in-process, which calls love.filesystem.init a second time -- and inside
-- an AppImage physfs is already initialized, so that second init throws
-- ("Failed to initialize filesystem: already initialized") and the relaunch
-- crashes. So on an AppImage we relaunch the executable; the fresh process's
-- Boot step mounts any downloaded update exactly as a manual relaunch would.
-- Android hits the same wall (#575): the vendored love.cpp loops runlove()
-- in-process on "restart", and PHYSFS_deinit in the old Filesystem module's
-- destructor fails ("files still open") whenever any physfs handle survives
-- lua_close, so the second PHYSFS_init throws the same "already initialized"
-- and the app dies. There we relaunch through the GameActivity.restartApp
-- JNI bridge (love.system.restartApp), which schedules our launch intent
-- and kills the process so no native state can leak into the fresh run.
-- On every other platform the in-process restart works, so keep it.
function HostShell.restart()
  if not (love and love.event and love.event.quit) then return end

  local osName = love.system and love.system.getOS and love.system.getOS()
  if osName == "Android" then
    -- restartApp kills the process on success, so a true return is never
    -- observed; false means the bridge could not schedule the relaunch.
    -- An older APK whose liblove predates the bridge (love.system.restartApp
    -- is nil) has no crash-free in-process restart, so quit to the OS
    -- cleanly and let the player relaunch by hand -- worse than restarting,
    -- but better than the guaranteed crash of quit("restart") (#575).
    if love.system.restartApp and love.system.restartApp() then return end
    love.event.quit()
    return
  end

  local appimage = os.getenv("APPIMAGE")
  if not appimage then
    love.event.quit("restart")
    return
  end

  -- We have to restart the process with this cursed execv call to prevent the
  -- PID from changing, which might cause SteamOS and other Linux launchers to
  -- think the app has crashed.
  local ffi = require("ffi")
  pcall(ffi.cdef, [[
    int execv(const char *path, char *const argv[]);
    int unsetenv(const char *name);
  ]])
  ffi.C.unsetenv("LD_LIBRARY_PATH")
  local argv = ffi.new("const char *[2]", appimage, nil)
  ffi.C.execv(appimage, ffi.cast("char *const *", argv))
end

-- ------- HTTP transport ----------------------------------------------------
--
-- Every remote fetch (mod index, mod releases, thumbnails) used to shell out
-- to curl, which macOS / Windows 10+ / desktop Linux all ship and Android does
-- not: adding a mod index on Android died with "curl is not available on this
-- platform" (#597).  Android goes through the GameActivity.httpDownload JNI
-- bridge instead (HttpsURLConnection, using the INTERNET permission link play
-- already needs), surfaced by our vendored liblove as
-- love.system.httpDownload(url, absPath, userAgent, accept).  Both transports
-- block the calling thread and deal in whole files, so callers keep exactly
-- the contract they had with curl.

-- Shell quoting for one curl argument; cmd.exe has no single-quote form.
function HostShell.quote(s)
  s = tostring(s)
  if love and love.system and love.system.getOS
      and love.system.getOS() == "Windows" then
    return '"' .. s:gsub('"', '') .. '"'
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function HostShell.haveCurl()
  local pipe = HostShell.popen("curl --version")
  if not pipe then return false end
  local readOk, out = pcall(function() return pipe:read("*a") end)
  pcall(function() pipe:close() end)
  return readOk and out ~= nil and out:find("curl", 1, true) ~= nil
end

-- An older mobile build reports nil here and falls back to the "no transport"
-- error the callers already show.
local function haveBridge()
  if not (love and love.system and type(love.system.httpDownload) == "function") then
    return false
  end
  local osName = love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

-- Is any transport available at all?  Callers gate on this, never on curl.
function HostShell.canFetch()
  return HostShell.haveCurl() or haveBridge()
end

-- Download url to an absolute host path.  Returns true, or nil plus an error.
-- The curl branch deliberately ignores curl's exit code, as the download paths
-- always did: callers judge the result by the file they got.
function HostShell.httpDownload(url, absPath, userAgent, accept)
  if type(url) ~= "string" or url == "" then return nil, "missing url" end
  if type(absPath) ~= "string" or absPath == "" then return nil, "missing path" end
  userAgent = userAgent or "gen1recomp"
  if HostShell.haveCurl() then
    local cmd = "curl -fsSL --connect-timeout 15 --max-time 300 "
      .. "-H " .. HostShell.quote("User-Agent: " .. userAgent) .. " "
    if accept then
      cmd = cmd .. "-H " .. HostShell.quote("Accept: " .. accept) .. " "
    end
    cmd = cmd .. "-o " .. HostShell.quote(absPath) .. " " .. HostShell.quote(url)
    local pipe = HostShell.popen(cmd)
    if not pipe then return nil, "could not start download" end
    pcall(function() pipe:read("*a") end)
    pcall(function() pipe:close() end)
    return true
  end
  if not haveBridge() then
    return nil, "no network transport on this platform"
  end
  local ok, done = pcall(love.system.httpDownload, url, absPath, userAgent, accept)
  if ok and done then return true end
  return nil, "download failed"
end

-- GET returning the body.  curl streams it through a pipe; the Android bridge
-- can only write a file, so there we fetch into the save directory (the only
-- writable root on Android) and read it back.
function HostShell.httpGet(url, userAgent, accept)
  if type(url) ~= "string" or url == "" then return nil, "missing url" end
  userAgent = userAgent or "gen1recomp"
  if HostShell.haveCurl() then
    local cmd = "curl -fsSL --connect-timeout 10 --max-time 40 "
      .. "-H " .. HostShell.quote("User-Agent: " .. userAgent) .. " "
    if accept then
      cmd = cmd .. "-H " .. HostShell.quote("Accept: " .. accept) .. " "
    end
    cmd = cmd .. HostShell.quote(url)
    local pipe = HostShell.popen(cmd)
    if not pipe then return nil, "could not run curl" end
    local readOk, out = pcall(function() return pipe:read("*a") end)
    pcall(function() pipe:close() end)
    if not readOk then return nil, "fetch failed: " .. tostring(out) end
    if not out or out == "" then return nil, "empty response from " .. url end
    return out
  end
  if not haveBridge() then
    return nil, "no network transport on this platform"
  end
  if not (love.filesystem and love.filesystem.getSaveDirectory) then
    return nil, "fetch needs LOVE"
  end
  local dirOk, saveDir = pcall(love.filesystem.getSaveDirectory)
  if not dirOk or not saveDir or saveDir == "" then
    return nil, "no save directory"
  end
  local name = "http_fetch.tmp"
  pcall(love.filesystem.remove, name)
  local ok, err = HostShell.httpDownload(url, saveDir .. "/" .. name, userAgent, accept)
  if not ok then return nil, err end
  local readOk, body = pcall(love.filesystem.read, name)
  pcall(love.filesystem.remove, name)
  if not readOk or type(body) ~= "string" or body == "" then
    return nil, "empty response from " .. url
  end
  return body
end

return HostShell
