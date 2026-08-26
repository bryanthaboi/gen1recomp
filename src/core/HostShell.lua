-- Helpers for calling host tools (curl, zenity/kdialog, ...).

local HostShell = {}

-- Our AppRun exports LD_LIBRARY_PATH="$APPDIR/lib:..." so every subprocess we
-- spawn tries to link against the libraries we're shipping instead of the
-- system ones. We want to unset the var so that any system tools can find
-- their proper libraries. Only needed when running in an AppImage.
-- LD_PRELOAD is Steam's overlay (#1470): its 32-bit half cannot load into a
-- 64-bit child, so ld.so prints an error into that child's output.
function HostShell.envPrefix()
  local unset = ""
  if os.getenv("APPIMAGE") then unset = unset .. "-u LD_LIBRARY_PATH " end
  if os.getenv("LD_PRELOAD") then unset = unset .. "-u LD_PRELOAD " end
  if unset == "" then return "" end
  return "env " .. unset
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

-- #254 was fixed inside the launcher and nowhere else: a native dialog opened
-- while a mouse button is still down blocks the whole loop in io.popen, so SDL
-- never processes the button-up and never drops the pointer capture it took
-- for the press (on X11 an XGrabPointer with owner_events).  The grab outlives
-- the click, every pointer event over the child dialog is still routed to our
-- window, and the dialog draws and keyboard-navigates but ignores the mouse.
-- src/import/RomImporter.lua owns the launcher's copy; hoisting it here means
-- every host spawn inherits it, including one a mod reaches through HostShell.
-- Pump until nothing is held so SDL sees the release first; bounded, so a
-- stuck button costs a moment and never the game.  pump() drains OS events
-- into LOVE's queue and dispatches nothing, so there is no reentry.  Worker
-- threads load neither love.mouse nor love.event, so the guard below makes
-- this a no-op off the main thread.
function HostShell.releasePointerGrab()
  if not (love and love.mouse and love.mouse.isDown and love.event
      and love.event.pump and love.timer) then
    return
  end
  local deadline = love.timer.getTime() + 1
  while love.mouse.isDown(1, 2, 3) do
    love.event.pump()
    if love.timer.getTime() > deadline then break end
    love.timer.sleep(0.005)
  end
end

-- POPEN IS NOT THREAD SAFE, and this app calls it from four threads (the main
-- one, the update checker, and a pool of three fetch workers).
--
-- On Darwin, popen() flushes every open stream first: _fwalk walks libc's
-- global FILE list and locks each entry as it goes.  pclose() frees a FILE and
-- takes it off that list.  Run the two concurrently and the walker can end up
-- waiting on the lock of a FILE another thread has already freed -- a wait
-- that nothing will ever satisfy.  That is the launcher freezing on close
-- after a visit to the mod tabs: sampling a hung process shows a fetch worker
-- parked in popen -> _fwalk -> flockfile with NO curl running anywhere on the
-- machine, and the main thread blocked in Thread:wait() for that worker, which
-- is why LOVE never reaches the process exit.
--
-- The fix is a process-wide mutex around the two list-mutating calls, and only
-- those: a LOVE Channel's performAtomic runs its callback holding the
-- channel's own mutex, which is the one lock primitive shared across love
-- threads.  Reading a pipe stays outside it, so the fetch pool still runs its
-- transfers in parallel -- a spawn is microseconds, a transfer is seconds.
local POPEN_LOCK = "hostshell_popen_lock"

local function popenLock()
  if not (love and love.thread and love.thread.getChannel) then return nil end
  local ok, ch = pcall(love.thread.getChannel, POPEN_LOCK)
  return ok and ch or nil
end

-- Run `fn` with the spawn lock held, or plain when there is no love.thread to
-- take one from (the headless test stub, a plain luajit run).
local function withPopenLock(fn)
  local ch = popenLock()
  if not ch then return fn() end
  local okAtomic = pcall(function() ch:performAtomic(fn) end)
  if not okAtomic then fn() end
end

-- Wraps io.popen with the AppImage env fix applied and lua errors swallowed
function HostShell.popen(command, mode)
  HostShell.releasePointerGrab()
  local pipe
  withPopenLock(function()
    local ok, p = pcall(io.popen, HostShell.envPrefix() .. command, mode or "r")
    pipe = (ok and p) or nil
  end)
  return pipe
end

-- Close a pipe HostShell.popen opened.  Callers MUST use this rather than
-- pipe:close(): pclose is the other half of the race above, and a close that
-- skips the lock can free a FILE out from under another thread's spawn.
function HostShell.pclose(pipe)
  if not pipe then return end
  withPopenLock(function() pcall(function() pipe:close() end) end)
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

-- DIAGNOSING A FAILED FETCH.  curl's own stderr ("curl: (56) The requested
-- URL returned error: 403") went straight to the terminal, naming neither the
-- URL nor which of the launcher's many fetches produced it, while the caller
-- got back a generic "empty response".  Both curl branches below now merge
-- stderr into the pipe and ask curl for the HTTP status with --write-out, so
-- the message that reaches the UI and the log says which URL failed and how.
--
-- The status rides a marker rather than a bare "%{http_code}": a GET streams
-- its body through the same pipe, so the code has to be findable at the end
-- of arbitrary text.  Matched from the END, and only the last occurrence is
-- cut, so a body that happens to contain the marker keeps its content.
-- Two spellings on purpose.  HTTP_MARK is what comes back down the pipe; the
-- FMT one is what goes to curl, where the newline MUST be the two characters
-- backslash-n (curl expands the escape itself).  A literal newline inside the
-- argument would be quoted fine by a POSIX shell and be a syntax error in
-- cmd.exe, which has no multi-line quoted string.
local HTTP_MARK = "\n__gen1recomp_http__"
local HTTP_MARK_FMT = "\\n__gen1recomp_http__%{http_code}"

local function stripLoaderNoise(out)
  while out:find("^ERROR: ld%.so:") do
    local nl = out:find("\n", 1, true)
    if not nl then return "" end
    out = out:sub(nl + 1)
  end
  return out
end

-- Split a curl pipe's output into (body, status, noise).  `status` is nil
-- when curl never got far enough to have one (DNS failure, no route, a
-- timeout), in which case `noise` carries curl's own complaint.
local function splitCurlOutput(out)
  out = stripLoaderNoise(tostring(out or ""))
  local at = nil
  local from = 1
  while true do
    local s = out:find(HTTP_MARK, from, true)
    if not s then break end
    at, from = s, s + 1
  end
  if not at then return out, nil, out end
  local body = out:sub(1, at - 1)
  local code = tonumber(out:sub(at + #HTTP_MARK):match("^(%d+)"))
  -- curl writes http_code 0 when it never got a response at all (DNS, no
  -- route, connect timeout).  That is not a status, and reporting it as
  -- "HTTP 0" buries the real reason, which is in curl's own message.
  if code == 0 then code = nil end
  return body, code, body
end

-- The error string a caller (and the launcher's notice line) sees.  It always
-- names the URL, because "403" on its own is unactionable when the launcher
-- has an index feed, a releases API and a page of thumbnails in flight.
local function fetchError(url, status, noise)
  if status then
    local extra = (noise or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #extra > 160 then extra = extra:sub(1, 157) .. "..." end
    if extra ~= "" then
      return ("HTTP %d from %s (%s)"):format(status, url, extra)
    end
    return ("HTTP %d from %s"):format(status, url)
  end
  local why = (noise or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if why == "" then why = "no response" end
  if #why > 160 then why = why:sub(1, 157) .. "..." end
  return ("fetch failed for %s: %s"):format(url, why)
end

-- Shell quoting for one curl argument; cmd.exe has no single-quote form.
function HostShell.quote(s)
  s = tostring(s)
  if love and love.system and love.system.getOS
      and love.system.getOS() == "Windows" then
    return '"' .. s:gsub('"', '') .. '"'
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Launch another instance of this packaged app without waiting for it.  The
-- same path works on all process-capable desktop hosts; only the shell's
-- background spelling differs.  Source checkouts include their game folder,
-- while fused releases and AppImages already carry it in the executable.
function HostShell.spawnSelfDetached(args)
  if not require("src.core.Platform").canSpawnProcess() then return false end
  local fs = love and love.filesystem
  if not (fs and fs.getExecutablePath) then return false end
  local executable = os.getenv("APPIMAGE") or fs.getExecutablePath()
  if type(executable) ~= "string" or executable == "" then return false end

  local argv = {}
  local fused = fs.isFused and fs.isFused()
  if not os.getenv("APPIMAGE") and not fused and fs.getSource then
    argv[#argv + 1] = fs.getSource()
  end
  for _, value in ipairs(args or {}) do argv[#argv + 1] = tostring(value) end

  local command = HostShell.quote(executable)
  for _, value in ipairs(argv) do
    command = command .. " " .. HostShell.quote(value)
  end
  local osName = love.system and love.system.getOS and love.system.getOS()
  if osName == "Windows" then
    command = 'start "" /b ' .. command .. " >NUL 2>&1"
  else
    command = HostShell.envPrefix() .. command .. " >/dev/null 2>&1 &"
  end
  local ok, _, code = os.execute(command)
  return ok == true or ok == 0 or code == 0
end

-- MEMOISED per Lua state (so once per thread).  This used to spawn a whole
-- `curl --version` process on every single fetch -- twice for a GET through
-- the Android-bridge fallback -- which doubled the number of spawns the lock
-- above has to serialise, for an answer that cannot change while the app is
-- running.
local curlAvailable = nil

function HostShell.haveCurl()
  if curlAvailable ~= nil then return curlAvailable end
  local pipe = HostShell.popen("curl --version")
  if not pipe then curlAvailable = false return false end
  local readOk, out = pcall(function() return pipe:read("*a") end)
  HostShell.pclose(pipe)
  curlAvailable = readOk and out ~= nil and out:find("curl", 1, true) ~= nil
  return curlAvailable
end

-- An older mobile build reports nil here and falls back to the "no transport"
-- error the callers already show.
local function haveBridge()
  if not (love and love.system and type(love.system.httpDownload) == "function") then
    return false
  end
  -- The OS allowlist is deliberate: the bridge is a per-port native addition,
  -- not part of LOVE, so a build that exports the name on a platform we never
  -- wired one for is a name collision, not a transport.  UWP is listed because
  -- Xbox has no curl and no way to spawn one (Platform.canSpawnProcess is
  -- false there), so the bridge is its only possible transport (#876).  Its
  -- LOVE backend does not export it today and this still returns false, but
  -- the gate is no longer the thing in the way.
  local osName = love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS" or osName == "UWP"
end

local function haveRequestBridge()
  if not (love and love.system and type(love.system.httpRequest) == "function") then
    return false
  end
  local osName = love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS" or osName == "UWP"
end

-- Is any transport available at all?  Callers gate on this, never on curl.
function HostShell.canFetch()
  return HostShell.haveCurl() or haveBridge()
end

function HostShell.canHttpRequest()
  return (HostShell.haveCurl() or haveRequestBridge()) and true or false
end

-- Download url to an absolute host path.  Returns true, or nil plus an error.
-- The curl branch deliberately ignores curl's exit code, as the download paths
-- always did: callers judge the result by the file they got.
-- `maxTime` bounds curl's total transfer seconds.  It matters at QUIT, not
-- during the transfer: LOVE waits for every live love.thread before the
-- process exits (#339), and a worker sitting inside a blocking curl cannot
-- notice a quit command until curl returns.  With the launcher's default 300s
-- ceiling, closing the window during a mod download hung the process for
-- minutes.  Callers on the interactive fetch pool pass something short.
--
-- `etagPath` (optional, absolute host path) turns this into a conditional
-- GET: curl sends `If-None-Match` from whatever ETag is already saved there
-- (`--etag-compare`) and overwrites it with the response's own ETag on
-- success (`--etag-save`), same file for both so a first call with no prior
-- ETag degrades to a plain unconditional download. A server that replies 304
-- Not Modified is reported as a third return value (`notModified`), and --
-- confirmed empirically against the real buildbot.libretro.com endpoint
-- (TrueFX/etag-cache-repro/) before this was wired in here -- curl does NOT
-- write `absPath` at all in that case (not even an empty file), matching
-- HTTP: a 304 carries no body. A caller must not treat a missing file as an
-- error when `notModified` comes back true.
function HostShell.httpDownload(url, absPath, userAgent, accept, maxTime, etagPath)
  if type(url) ~= "string" or url == "" then return nil, "missing url" end
  if type(absPath) ~= "string" or absPath == "" then return nil, "missing path" end
  userAgent = userAgent or "gen1recomp"
  if HostShell.haveCurl() then
    local cmd = ("curl -fsSL --proto =http,https --proto-redir =http,https "
      .. "--connect-timeout 15 --max-time %d ")
      :format(tonumber(maxTime) or 300)
      .. "-H " .. HostShell.quote("User-Agent: " .. userAgent) .. " "
    if accept then
      cmd = cmd .. "-H " .. HostShell.quote("Accept: " .. accept) .. " "
    end
    if type(etagPath) == "string" and etagPath ~= "" then
      cmd = cmd .. "--etag-compare " .. HostShell.quote(etagPath) .. " "
        .. "--etag-save " .. HostShell.quote(etagPath) .. " "
    end
    cmd = cmd .. "-o " .. HostShell.quote(absPath) .. " "
      .. "-w " .. HostShell.quote(HTTP_MARK_FMT) .. " "
      .. HostShell.quote(url) .. " 2>&1"
    local pipe = HostShell.popen(cmd)
    if not pipe then return nil, "could not start download" end
    local readOk, out = pcall(function() return pipe:read("*a") end)
    HostShell.pclose(pipe)
    -- The file is still what the caller judges success by (-f writes nothing
    -- on an HTTP error, and the callers all check the file anyway).  The
    -- status is here purely so the failure can NAME itself: "download failed"
    -- with no URL and no code is the report this whole change exists to fix.
    local body, status, noise = splitCurlOutput(readOk and out or "")
    if status == 304 then
      return true, nil, true
    end
    if status and (status < 200 or status >= 300) then
      return nil, fetchError(url, status, body)
    end
    if not status and (noise or ""):match("%S") then
      return nil, fetchError(url, nil, noise)
    end
    return true
  end
  if not haveBridge() then
    return nil, "no network transport on this platform"
  end
  -- The Android/iOS bridge has no conditional-GET support -- etagPath is
  -- silently ignored here, so a downloaded preset re-fetches in full every
  -- time on those platforms.  No transport-level ETag/If-None-Match hook
  -- exists on the bridge to hang one off, and it's low-priority for now.
  local ok, done = pcall(love.system.httpDownload, url, absPath, userAgent, accept)
  if ok and done then return true end
  return nil, "download failed for " .. url
end

-- GET returning the body.  curl streams it through a pipe; the Android bridge
-- can only write a file, so there we fetch into the save directory (the only
-- writable root on Android) and read it back.
function HostShell.httpGet(url, userAgent, accept, maxTime)
  if type(url) ~= "string" or url == "" then return nil, "missing url" end
  userAgent = userAgent or "gen1recomp"
  if HostShell.haveCurl() then
    -- No -f here (the download branch keeps it).  -f suppresses the error
    -- BODY, and on the two services this talks to that body is the whole
    -- diagnosis: GitHub's 403 says "API rate limit exceeded for <ip>", which
    -- tells a user to wait rather than to go hunting for a broken index.
    local cmd = ("curl -sSL --proto =http,https --proto-redir =http,https "
      .. "--connect-timeout 10 --max-time %d ")
      :format(tonumber(maxTime) or 40)
      .. "-H " .. HostShell.quote("User-Agent: " .. userAgent) .. " "
    if accept then
      cmd = cmd .. "-H " .. HostShell.quote("Accept: " .. accept) .. " "
    end
    cmd = cmd .. "-w " .. HostShell.quote(HTTP_MARK_FMT) .. " "
      .. HostShell.quote(url) .. " 2>&1"
    local pipe = HostShell.popen(cmd)
    if not pipe then return nil, "could not run curl" end
    local readOk, out = pcall(function() return pipe:read("*a") end)
    HostShell.pclose(pipe)
    if not readOk then
      return nil, fetchError(url, nil, tostring(out))
    end
    local body, status, noise = splitCurlOutput(out)
    if not status then return nil, fetchError(url, nil, noise) end
    if status < 200 or status >= 300 then
      return nil, fetchError(url, status, body)
    end
    if body == "" then return nil, "empty response from " .. url end
    return body
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

-- POST returning success/failure.  Strictly one-way: the response body is
-- discarded, only the HTTP status class is surfaced (postLog callers never
-- trust the reply).  curl --data-binary reads the payload from a pipe, so a
-- large body never lands in the command line; where curl is absent (Android
-- and the other bridge-only platforms) the POST rides the JNI bridge --
-- love.system.httpPost, the dedicated POST arm added beside httpDownload --
-- instead of half-working through httpDownload (a GET round-trip to a POST
-- endpoint would be a lie).
function HostShell.httpPost(url, body, contentType, userAgent, maxTime)
  if type(url) ~= "string" or url == "" then return nil, "missing url" end
  if type(body) ~= "string" then return nil, "missing body" end
  userAgent = userAgent or "gen1recomp"
  if HostShell.haveCurl() then
    -- io.popen is one-way on Lua/LuaJIT: its mode is "r" or "w", never
    -- "rw".  Stage the request body so the response can stay on a read
    -- pipe.  The staging directory comes from the OS temp contract, never
    -- tmpnam(): the CRT's tmpnam() can return a name relative to the process
    -- working directory, and a game installed under Program Files has no
    -- writable CWD -- io.open would fail before curl ever runs and postLog
    -- would silently drop the send.  TEMP/TMP are per-user writable on
    -- Windows; TMPDIR (with /tmp fallback) covers POSIX.  No love.filesystem:
    -- the sandbox-era transport stays on plain io/os.
    local function stagingPath()
      local dir = os.getenv("TEMP") or os.getenv("TMP")
      if not dir or dir == "" then dir = os.getenv("TMPDIR") or "/tmp" end
      local sep = dir:find("\\") and "\\" or "/"
      return dir .. sep .. ("gen1recomp-post-%d.tmp"):format(
        (os.time() % 1000000) * 100 + math.random(0, 99))
    end
    local bodyPath = stagingPath()
    local bodyFile, bodyOpenErr = io.open(bodyPath, "wb")
    if not bodyFile then
      pcall(os.remove, bodyPath)
      return nil, "could not create request body: " .. tostring(bodyOpenErr)
    end
    local bodyOk, bodyErr = pcall(function()
      assert(bodyFile:write(body))
      assert(bodyFile:close())
    end)
    if not bodyOk then
      pcall(function() bodyFile:close() end)
      pcall(os.remove, bodyPath)
      return nil, "could not write body: " .. tostring(bodyErr)
    end

    -- --data-binary @<file> keeps the payload out of argv (command-line length
    -- limits on Windows) and preserves every byte including trailing
    -- newlines.  The body is staged above because io.popen cannot be opened
    -- for both writing and reading.  No -f, matching httpGet: the response
    -- body is discarded anyway, and curl's stderr carries the diagnosis.
    local cmd = ("curl -sSL --proto =http,https --proto-redir =http,https "
      .. "--connect-timeout 10 --max-time %d ")
      :format(tonumber(maxTime) or 40)
      .. "-X POST "
      .. "-H " .. HostShell.quote("User-Agent: " .. userAgent) .. " "
    if contentType then
      cmd = cmd .. "-H " .. HostShell.quote("Content-Type: " .. contentType) .. " "
    end
    cmd = cmd .. "-H " .. HostShell.quote("Content-Length: " .. tostring(#body)) .. " "
      .. "--data-binary " .. HostShell.quote("@" .. bodyPath) .. " "
      .. "-w " .. HostShell.quote(HTTP_MARK_FMT) .. " "
      .. HostShell.quote(url) .. " 2>&1"
    local pipe = HostShell.popen(cmd)
    if not pipe then
      pcall(os.remove, bodyPath)
      return nil, "could not run curl"
    end
    local readOk, out = pcall(function() return pipe:read("*a") end)
    HostShell.pclose(pipe)
    pcall(os.remove, bodyPath)
    if not readOk then
      return nil, fetchError(url, nil, tostring(out))
    end
    local _, status, noise = splitCurlOutput(out)
    if not status then return nil, fetchError(url, nil, noise) end
    if status < 200 or status >= 300 then
      return nil, fetchError(url, status, "log post rejected")
    end
    return true
  end
  if not haveBridge() then
    return nil, "no network transport on this platform"
  end
  -- The GET bridge has no POST; the dedicated love.system.httpPost arm
  -- (GameActivity.httpPost) is the transport where curl is missing. A
  -- build without it reports the same "no POST transport" a missing curl
  -- would -- the old-APK skew path in the JNI bridge returns false.
  if love.system and type(love.system.httpPost) == "function" then
    local ok, sent = pcall(love.system.httpPost, url, body, contentType,
                           userAgent)
    if ok and sent then return true end
    return nil, "log post rejected"
  end
  return nil, "no POST transport on this platform"
end

local function requestHeaderList(headers)
  local out = {}
  if type(headers) == "table" then
    if #headers > 0 then
      for _, line in ipairs(headers) do
        if type(line) == "string" then out[#out + 1] = line end
      end
    else
      local names = {}
      for name in pairs(headers) do names[#names + 1] = tostring(name) end
      table.sort(names)
      for _, name in ipairs(names) do
        out[#out + 1] = name .. ": " .. tostring(headers[name])
      end
    end
  end
  for _, line in ipairs(out) do
    if line:find("[\r\n]") or not line:find(":", 1, true) then return nil end
  end
  return out
end

local BRIDGE_METHODS = { GET = true, POST = true, PUT = true, DELETE = true }

local function requestHeaderPairs(lines)
  local out = {}
  for _, line in ipairs(lines) do
    local name, value = line:match("^%s*([^:]-)%s*:%s*(.-)%s*$")
    if not name or name == "" then return nil end
    if name:find("[\r\n]") or value:find("[\r\n]") then return nil end
    out[#out + 1] = name
    out[#out + 1] = value
  end
  return out
end

local function bridgeRequest(url, method, headers, body, userAgent)
  if not BRIDGE_METHODS[method] then
    return nil, "no request transport for " .. method .. " on this platform"
  end
  local fields = requestHeaderPairs(headers)
  if not fields then return nil, "bad request header" end
  local ok, envelope = pcall(love.system.httpRequest, url, method, fields,
                             body, userAgent)
  if not ok or type(envelope) ~= "string" or envelope == "" then
    return nil, "this app build cannot make signed requests: update the app to use save sync"
  end
  local head, rest = envelope:match("^([^\n]*)\n(.*)$")
  if not head then
    return nil, fetchError(url, nil, "unreadable reply from the network bridge")
  end
  local status = tonumber(head:match("^STATUS (%d+)$"))
  if status then return rest or "", nil, status end
  return nil, fetchError(url, nil, head:match("^ERROR (.*)$") or head)
end

local requestSeq = 0

local function requestStagingPath(kind)
  local dir
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local ok, saveDir = pcall(love.filesystem.getSaveDirectory)
    if ok and type(saveDir) == "string" and saveDir ~= "" then dir = saveDir end
  end
  if not dir then
    dir = os.getenv("TEMP") or os.getenv("TMP")
    if not dir or dir == "" then dir = os.getenv("TMPDIR") or "/tmp" end
  end
  local sep = dir:find("\\") and "\\" or "/"
  requestSeq = requestSeq + 1
  return dir .. sep .. ("gen1recomp-req-%s-%d-%d-%d.tmp"):format(
    kind, os.time() % 1000000, requestSeq, math.random(0, 999999))
end

local function writeStagingFile(kind, text)
  local path = requestStagingPath(kind)
  local file, openErr = io.open(path, "wb")
  if not file then
    return nil, "could not create the request " .. kind .. ": " .. tostring(openErr)
  end
  local wrote, writeErr = pcall(function()
    assert(file:write(text))
    assert(file:close())
  end)
  if not wrote then
    pcall(function() file:close() end)
    pcall(os.remove, path)
    return nil, "could not write the request " .. kind .. ": " .. tostring(writeErr)
  end
  return path
end

function HostShell.httpRequest(url, opts)
  opts = type(opts) == "table" and opts or {}
  if type(url) ~= "string" or url == "" then return nil, "missing url" end
  local method = tostring(opts.method or "GET"):upper()
  if not method:match("^%u+$") then return nil, "bad request method" end
  local headers = requestHeaderList(opts.headers)
  if not headers then return nil, "bad request header" end
  local body = opts.body
  if body ~= nil and type(body) ~= "string" then return nil, "bad request body" end
  local userAgent = opts.userAgent or "gen1recomp"
  local maxTime = tonumber(opts.maxTime) or 30

  if not HostShell.haveCurl() then
    if haveRequestBridge() then
      return bridgeRequest(url, method, headers, body, userAgent)
    end
    if method == "GET" and #headers == 0 then
      local got, err = HostShell.httpGet(url, userAgent, opts.accept, maxTime)
      if not got then return nil, err end
      return got, nil, 200
    end
    if haveBridge() then
      return nil, "this app build cannot make signed requests: update the app to use save sync"
    end
    return nil, "no request transport on this platform"
  end

  local bodyPath, stageErr
  if body then
    bodyPath, stageErr = writeStagingFile("body", body)
    if not bodyPath then return nil, stageErr end
  end

  local lines = { "User-Agent: " .. userAgent }
  for _, line in ipairs(headers) do lines[#lines + 1] = line end
  if body then
    lines[#lines + 1] = "Content-Length: " .. tostring(#body)
  end
  local headerPath
  headerPath, stageErr = writeStagingFile("head",
    table.concat(lines, "\n") .. "\n")
  if not headerPath then
    if bodyPath then pcall(os.remove, bodyPath) end
    return nil, stageErr
  end

  local function cleanup()
    if bodyPath then pcall(os.remove, bodyPath) end
    pcall(os.remove, headerPath)
  end

  local cmd = ("curl -sSL --proto =http,https --proto-redir =http,https "
    .. "--connect-timeout 10 --max-time %d "):format(maxTime)
    .. "-X " .. HostShell.quote(method) .. " "
    .. "-H " .. HostShell.quote("@" .. headerPath) .. " "
  if body then
    cmd = cmd .. "--data-binary " .. HostShell.quote("@" .. bodyPath) .. " "
  end
  cmd = cmd .. "-w " .. HostShell.quote(HTTP_MARK_FMT) .. " "
    .. HostShell.quote(url) .. " 2>&1"

  local pipe = HostShell.popen(cmd)
  if not pipe then
    cleanup()
    return nil, "could not run curl"
  end
  local readOk, out = pcall(function() return pipe:read("*a") end)
  HostShell.pclose(pipe)
  cleanup()
  if not readOk then
    return nil, fetchError(url, nil, tostring(out))
  end
  local respBody, status, noise = splitCurlOutput(out)
  if not status then return nil, fetchError(url, nil, noise) end
  return respBody or "", nil, status
end

return HostShell
