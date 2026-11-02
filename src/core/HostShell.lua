-- Helpers for calling host tools (curl, zenity/kdialog, ...).

local HostShell = {}

-- Our AppRun exports LD_LIBRARY_PATH="$APPDIR/lib:..." so every subprocess we
-- spawn tries to link against the libraries we're shipping instead of the
-- system ones. Host tools (curl, zenity) need that unset. A *bundled* AppDir
-- curl must keep APPDIR on LD_LIBRARY_PATH so it resolves the bundled
-- libssl/libcrypto -- scrubbing it forces host OpenSSL and segfaults across
-- distros. LD_PRELOAD is always scrubbed: Steam's overlay (#1470) cannot load
-- into a 64-bit child.
function HostShell.envPrefix()
  return HostShell.curlEnvPrefix("host")
end

-- kind "bundled" = AppDir / Flatpak curl (keep LD_LIBRARY_PATH, scrub preload).
-- kind "host"    = system curl (scrub both).
function HostShell.curlEnvPrefix(kind)
  local unset = ""
  if kind ~= "bundled" and os.getenv("APPIMAGE") then
    unset = unset .. "-u LD_LIBRARY_PATH "
  end
  if os.getenv("LD_PRELOAD") then unset = unset .. "-u LD_PRELOAD " end
  if unset == "" then return "" end
  return "env " .. unset
end

local curlResolved = nil -- { path=, kind= } once per Lua state

local function pathIsExecutable(path)
  if type(path) ~= "string" or path == "" then return false end
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  -- Best-effort: existence is enough; exec bit is checked by the spawn.
  return true
end

-- Prefer Flatpak /app/bin/curl, then $APPDIR/{usr/,}bin/curl, else host "curl".
function HostShell.resolveCurl()
  if curlResolved ~= nil then return curlResolved.path, curlResolved.kind end
  local candidates = {}
  if os.getenv("FLATPAK_ID") then
    candidates[#candidates + 1] = { "/app/bin/curl", "bundled" }
  end
  local appdir = os.getenv("APPDIR")
  if type(appdir) == "string" and appdir ~= "" then
    candidates[#candidates + 1] = { appdir .. "/usr/bin/curl", "bundled" }
    candidates[#candidates + 1] = { appdir .. "/bin/curl", "bundled" }
  end
  for _, c in ipairs(candidates) do
    if pathIsExecutable(c[1]) then
      curlResolved = { path = c[1], kind = c[2] }
      return curlResolved.path, curlResolved.kind
    end
  end
  curlResolved = { path = "curl", kind = "host" }
  return curlResolved.path, curlResolved.kind
end

-- Quoted curl argv0 for a shell command, plus the matching env prefix.
function HostShell.curlInvocation()
  local path, kind = HostShell.resolveCurl()
  return HostShell.curlEnvPrefix(kind) .. HostShell.quote(path), kind
end

-- Diagnostics for support / About screens.
function HostShell.curlDiagnostics()
  local path, kind = HostShell.resolveCurl()
  return {
    path = path,
    kind = kind,
    appimage = os.getenv("APPIMAGE") ~= nil,
    appdir = os.getenv("APPDIR"),
    flatpakId = os.getenv("FLATPAK_ID"),
    haveCurl = HostShell.haveCurl(),
  }
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

-- Wraps io.popen with the AppImage env fix applied and lua errors swallowed.
-- opts.envPrefix overrides the default HostShell.envPrefix() (pass "" to skip,
-- or curlEnvPrefix(kind) when spawning a resolved curl binary).
function HostShell.popen(command, mode, opts)
  HostShell.releasePointerGrab()
  local prefix = HostShell.envPrefix()
  if type(opts) == "table" and opts.envPrefix ~= nil then
    prefix = opts.envPrefix
  end
  local pipe
  local line = HostShell.shellCommand(prefix .. command)
  withPopenLock(function()
    local ok, p = pcall(io.popen, line, mode or "r")
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

function HostShell.pumpHostEvents()
  if not (love and love.event and love.event.pump) then return end
  pcall(love.event.pump)
end

local function winApi()
  local ok, mod = pcall(require, "src.core.WinApi")
  if ok and type(mod) == "table" then return mod end
  local fs = love and love.filesystem
  if not (fs and fs.load) then return nil end
  local okLoad, chunk = pcall(fs.load, "src/core/WinApi.lua")
  if not okLoad or type(chunk) ~= "function" then return nil end
  local okRun, loaded = pcall(chunk)
  if not okRun or type(loaded) ~= "table" then return nil end
  package.loaded["src.core.WinApi"] = loaded
  return loaded
end

local function windowsModulePath()
  local api = winApi()
  return api and api.modulePath() or nil
end

-- quit("restart") re-inits physfs, which an AppImage refuses ("already initialized"), so Linux execs the binary.
function HostShell.loopRestarts()
  return rawget(_G, "POKEPORT_LOOP_RESTART") == true
end

function HostShell.canRestart()
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  return osName ~= "Android" or HostShell.loopRestarts()
end

HostShell.restarting = false

function HostShell.restart()
  if not (love and love.event and love.event.quit) then return end
  HostShell.restarting = true

  local osName = love.system and love.system.getOS and love.system.getOS()
  if osName == "Android" then
    if HostShell.loopRestarts() then
      love.event.quit("restart")
      return
    end
    if love.system.restartApp and love.system.restartApp() then return end
    love.event.quit()
    return
  end
  if osName == "iOS" then
    love.event.quit()
    return
  end
  if osName == "Linux" then
    local appimage = os.getenv("APPIMAGE")
    local exe = appimage or "/proc/self/exe"
    local f = io.open("/proc/self/cmdline", "rb")
    if f then
      local raw = f:read("*a")
      f:close()
      local parts = {}
      for p in raw:gmatch("[^%z]+") do
        parts[#parts + 1] = p
      end
      if #parts > 0 then
        local ffi = require("ffi")
        pcall(ffi.cdef, [[
          int execv(const char *path, char *const argv[]);
          int unsetenv(const char *name);
        ]])
        if appimage then
          ffi.C.unsetenv("LD_LIBRARY_PATH")
        end
        local argv = ffi.new("const char *[" .. (#parts + 1) .. "]")
        for i, p in ipairs(parts) do
          argv[i - 1] = p
        end
        argv[#parts] = nil
        ffi.C.execv(exe, ffi.cast("char *const *", argv))
      end
    end
    love.event.quit("restart")
    return
  end

  if osName == "Windows" and love.filesystem.isFused and love.filesystem.isFused() then
    local exe = love.filesystem.getSource()
    if type(exe) ~= "string" or exe == "" then
      exe = windowsModulePath()
    end
    local api = winApi()
    if api and exe and exe ~= "" then
      exe = exe:gsub("/", "\\")
      if api.spawn(exe, {}, { cwd = api.dirOf(exe) }) then
        love.event.quit()
        return
      end
    end
  end

  love.event.quit("restart")
end

-- ------- HTTP transport ----------------------------------------------------
--
-- Every remote fetch (mod index, mod releases, thumbnails) used to shell out
-- to curl, which desktop OSes ship and mobile / console ports may not. Android
-- goes through the GameActivity.httpDownload JNI bridge instead
-- (HttpsURLConnection, using the INTERNET permission link play already needs),
-- surfaced by our vendored liblove as love.system.httpDownload(url, absPath,
-- userAgent, accept). love-nx can expose the same download bridge on Switch.
-- Both transports block the calling thread and deal in whole files, so callers
-- keep exactly the contract they had with curl.

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

function HostShell.isWindows()
  return (love and love.system and love.system.getOS
    and love.system.getOS() == "Windows") or false
end

function HostShell.shellCommand(command)
  command = tostring(command)
  if not HostShell.isWindows() then return command end
  if command:sub(1, 1) ~= '"' then return command end
  return '"' .. command .. '"'
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

  local osName = love.system and love.system.getOS and love.system.getOS()
  if osName == "Windows" then
    local api = winApi()
    if not api then return false end
    executable = executable:gsub("/", "\\")
    return api.spawn(executable, argv, { cwd = api.dirOf(executable) })
  end

  local command = HostShell.quote(executable)
  for _, value in ipairs(argv) do
    command = command .. " " .. HostShell.quote(value)
  end
  command = HostShell.envPrefix() .. command .. " >/dev/null 2>&1 &"
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
  local path, kind = HostShell.resolveCurl()
  local pipe = HostShell.popen(
    HostShell.quote(path) .. " --version", "r",
    { envPrefix = HostShell.curlEnvPrefix(kind) })
  if not pipe then curlAvailable = false return false end
  local readOk, out = pcall(function() return pipe:read("*a") end)
  HostShell.pclose(pipe)
  curlAvailable = readOk and out ~= nil and out:find("curl", 1, true) ~= nil
  return curlAvailable
end

function HostShell.winRelative(paths)
  local split = {}
  for i, p in ipairs(paths) do
    local parts = {}
    for c in tostring(p):gmatch("[^/\\]+") do parts[#parts + 1] = c end
    split[i] = parts
  end
  if #split == 0 then return nil end
  local limit = math.huge
  for _, parts in ipairs(split) do limit = math.min(limit, #parts - 1) end
  local common = 0
  while common < limit do
    local c = split[1][common + 1]
    local same = true
    for i = 2, #split do
      if split[i][common + 1] ~= c then same = false break end
    end
    if not same then break end
    common = common + 1
  end
  if common == 0 then return nil end
  local cwd = table.concat(split[1], "\\", 1, common)
  if tostring(paths[1]):match("^[/\\][/\\]") then cwd = "\\\\" .. cwd end
  if cwd:match("^%a:$") then cwd = cwd .. "\\" end
  local rels = {}
  for i, parts in ipairs(split) do
    local rel = table.concat(parts, "\\", common + 1)
    if not rel:find("[\128-\255]") then rels[i] = rel end
  end
  return cwd, rels
end

local function shellArgs(argv)
  local parts = {}
  for i, a in ipairs(argv) do
    parts[i] = a:match("^[%w%-=,%.]+$") and a or HostShell.quote(a)
  end
  return table.concat(parts, " ")
end

local function resolveArgs(argv, relative)
  local out = {}
  for i, a in ipairs(argv) do
    if type(a) == "table" then
      out[i] = (a.prefix or "") .. ((relative and a.rel) or a.abs)
    else
      out[i] = a
    end
  end
  return out
end

local function pathArgs(argv)
  local list = {}
  for _, a in ipairs(argv) do
    if type(a) == "table" then list[#list + 1] = a end
  end
  return list
end

local function runCurlWindows(argv)
  local api = winApi()
  if not (api and api.run) then return nil end
  local specs = pathArgs(argv)
  local cwd = nil
  if #specs > 0 then
    local abs = {}
    for i, s in ipairs(specs) do abs[i] = s.abs end
    local rels
    cwd, rels = HostShell.winRelative(abs)
    for i, s in ipairs(specs) do s.rel = cwd and rels[i] or nil end
  end
  HostShell.releasePointerGrab()
  local path = HostShell.resolveCurl()
  return api.run(path, resolveArgs(argv, cwd ~= nil), {
    cwd = cwd, useApplicationName = false, flags = api.CREATE_NO_WINDOW,
    lock = withPopenLock,
  })
end

local function runCurl(argv)
  if HostShell.isWindows() then
    local out = runCurlWindows(argv)
    if out ~= nil then return true, true, out end
  end
  local path, kind = HostShell.resolveCurl()
  local cmd = HostShell.quote(path) .. " " .. shellArgs(resolveArgs(argv, false)) .. " 2>&1"
  local pipe = HostShell.popen(cmd, "r", { envPrefix = HostShell.curlEnvPrefix(kind) })
  if not pipe then return false end
  local readOk, out = pcall(function() return pipe:read("*a") end)
  HostShell.pclose(pipe)
  return true, readOk, out
end

local function curlBase(fail, connectTimeout, maxTime)
  return { fail and "-fsSL" or "-sSL", "--proto", "=http,https",
    "--proto-redir", "=http,https", "--connect-timeout", tostring(connectTimeout),
    "--max-time", tostring(maxTime) }
end

local function push(list, ...)
  for i = 1, select("#", ...) do list[#list + 1] = select(i, ...) end
end

local function winStage(kind, text)
  local fs = love and love.filesystem
  if not (HostShell.isWindows() and fs and fs.write and fs.getSaveDirectory) then
    return nil
  end
  local okDir, saveDir = pcall(fs.getSaveDirectory)
  if not okDir or type(saveDir) ~= "string" or saveDir == "" then return nil end
  local name = ("gen1recomp-%s-%d-%d.tmp"):format(kind, os.time() % 1000000,
    math.random(0, 999999))
  local okWrite, wrote = pcall(fs.write, name, text)
  if not okWrite or not wrote then return nil end
  return saveDir .. "/" .. name, function() pcall(fs.remove, name) end
end

-- An older mobile build reports nil here and falls back to the "no transport"
-- error the callers already show.
local function haveBridge()
  if not (love and love.system and type(love.system.httpDownload) == "function") then
    return false
  end
  -- The OS allowlist is deliberate: the bridge is a per-port native addition,
  -- not part of LOVE, so a build that exports the name on a platform we never
  -- wired one for is a name collision, not a transport. NX is listed for
  -- love-nx builds that expose the native download bridge. UWP is listed
  -- because Xbox has no curl and no way to spawn one (Platform.canSpawnProcess
  -- is false there), so the bridge is its only possible transport (#876). Its
  -- LOVE backend does not export it today and this still returns false, but
  -- the gate is no longer the thing in the way.
  local osName = love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS" or osName == "NX"
    or osName == "UWP"
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
    local argv = curlBase(true, 15, tonumber(maxTime) or 300)
    push(argv, "-H", "User-Agent: " .. userAgent)
    if accept then
      push(argv, "-H", "Accept: " .. accept)
    end
    if type(etagPath) == "string" and etagPath ~= "" then
      local etag = { abs = etagPath }
      push(argv, "--etag-compare", etag, "--etag-save", etag)
    end
    push(argv, "-o", { abs = absPath }, "-w", HTTP_MARK_FMT, url)
    local started, readOk, out = runCurl(argv)
    if not started then return nil, "could not start download" end
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
  -- The native bridge has no conditional-GET support -- etagPath is
  -- silently ignored here, so a downloaded preset re-fetches in full every
  -- time on bridge-only platforms. No transport-level ETag/If-None-Match hook
  -- exists on the bridge to hang one off, and it's low-priority for now.
  local ok, done = pcall(love.system.httpDownload, url, absPath, userAgent, accept)
  if ok and done then return true end
  return nil, "download failed for " .. url
end

-- GET returning the body. curl streams it through a pipe; the native bridge
-- can only write a file, so there we fetch into the save directory and read
-- it back.
function HostShell.httpGet(url, userAgent, accept, maxTime)
  if type(url) ~= "string" or url == "" then return nil, "missing url" end
  userAgent = userAgent or "gen1recomp"
  if HostShell.haveCurl() then
    -- No -f here (the download branch keeps it).  -f suppresses the error
    -- BODY, and on the two services this talks to that body is the whole
    -- diagnosis: GitHub's 403 says "API rate limit exceeded for <ip>", which
    -- tells a user to wait rather than to go hunting for a broken index.
    local argv = curlBase(false, 10, tonumber(maxTime) or 40)
    push(argv, "-H", "User-Agent: " .. userAgent)
    if accept then
      push(argv, "-H", "Accept: " .. accept)
    end
    push(argv, "-w", HTTP_MARK_FMT, url)
    local started, readOk, out = runCurl(argv)
    if not started then return nil, "could not run curl" end
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
    -- Windows; TMPDIR (with /tmp fallback) covers POSIX.
    local function stagingPath()
      local dir = os.getenv("TEMP") or os.getenv("TMP")
      if not dir or dir == "" then dir = os.getenv("TMPDIR") or "/tmp" end
      local sep = dir:find("\\") and "\\" or "/"
      return dir .. sep .. ("gen1recomp-post-%d.tmp"):format(
        (os.time() % 1000000) * 100 + math.random(0, 99))
    end
    local bodyPath, removeBody = winStage("post", body)
    if not bodyPath then
      bodyPath = stagingPath()
      removeBody = function() pcall(os.remove, bodyPath) end
      local bodyFile, bodyOpenErr = io.open(bodyPath, "wb")
      if not bodyFile then
        removeBody()
        return nil, "could not create request body: " .. tostring(bodyOpenErr)
      end
      local bodyOk, bodyErr = pcall(function()
        assert(bodyFile:write(body))
        assert(bodyFile:close())
      end)
      if not bodyOk then
        pcall(function() bodyFile:close() end)
        removeBody()
        return nil, "could not write body: " .. tostring(bodyErr)
      end
    end

    -- --data-binary @<file> keeps the payload out of argv (command-line length
    -- limits on Windows) and preserves every byte including trailing
    -- newlines.  The body is staged above because io.popen cannot be opened
    -- for both writing and reading.  No -f, matching httpGet: the response
    -- body is discarded anyway, and curl's stderr carries the diagnosis.
    local argv = curlBase(false, 10, tonumber(maxTime) or 40)
    push(argv, "-X", "POST", "-H", "User-Agent: " .. userAgent)
    if contentType then
      push(argv, "-H", "Content-Type: " .. contentType)
    end
    push(argv, "-H", "Content-Length: " .. tostring(#body),
      "--data-binary", { abs = bodyPath, prefix = "@" },
      "-w", HTTP_MARK_FMT, url)
    local started, readOk, out = runCurl(argv)
    removeBody()
    if not started then
      return nil, "could not run curl"
    end
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
  local staged, removeStaged = winStage("req-" .. kind, text)
  if staged then return staged, removeStaged end
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
  return path, function() pcall(os.remove, path) end
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

  local bodyPath, removeBody, stageErr
  if body then
    bodyPath, removeBody = writeStagingFile("body", body)
    if not bodyPath then return nil, removeBody end
  end

  local lines = { "User-Agent: " .. userAgent }
  for _, line in ipairs(headers) do lines[#lines + 1] = line end
  if body then
    lines[#lines + 1] = "Content-Length: " .. tostring(#body)
  end
  local headerPath, removeHeader = writeStagingFile("head",
    table.concat(lines, "\n") .. "\n")
  if not headerPath then
    stageErr = removeHeader
    if removeBody then removeBody() end
    return nil, stageErr
  end

  local function cleanup()
    if removeBody then removeBody() end
    removeHeader()
  end

  local argv = curlBase(false, 10, maxTime)
  push(argv, "-X", method, "-H", { abs = headerPath, prefix = "@" })
  if body then
    push(argv, "--data-binary", { abs = bodyPath, prefix = "@" })
  end
  push(argv, "-w", HTTP_MARK_FMT, url)

  local started, readOk, out = runCurl(argv)
  cleanup()
  if not started then
    return nil, "could not run curl"
  end
  if not readOk then
    return nil, fetchError(url, nil, tostring(out))
  end
  local respBody, status, noise = splitCurlOutput(out)
  if not status then return nil, fetchError(url, nil, noise) end
  return respBody or "", nil, status
end

return HostShell
