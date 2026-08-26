-- Async release-check and payload-download for the self-update flow.
--
-- The heavy lifting (curl calls, sha256 verification, the Boot gate) happens
-- on a background love.thread worker (src/update/check_worker.lua); this module
-- is only the thin main-thread state machine the UI polls.  Two channels carry
-- the conversation:
--   "update_check_cmd"   main -> worker: { cmd = "check" | "download" |
--                                           "download_full" | "quit" }
--   "update_check_state" worker -> main: { status, latest, progress, error }
--
-- Nothing here ever blocks or throws into the game loop: when love.thread is
-- absent (the headless test stub) or the worker cannot run, state() reports
-- "error" (or the worker reports "needs_full" when there is no transport).
-- See the shared contract in the task brief for the status vocabulary.
--
-- The release-JSON extraction and the sums parsing are exported as pure
-- functions (no love.* calls) so plain-Lua tests can cover them, and so the
-- worker can reuse the exact same code path via love.filesystem.load.

local Check = {}
local Platform = require("src.core.Platform")

Check.REPO = "bryanthaboi/gen1recomp"

-- Full native packages are deliberately named by release target, not by the
-- generic .love payload.  Keeping the mapping here makes the release parser,
-- worker and launcher agree on exactly which asset a platform may offer.
-- Switch owns its native OTA launcher and therefore never reaches this code.
local function fullAssetName(version, osName, arch, port)
  if port == "rg34xxsp" then
    return "gen1recomp-" .. version .. "-rg34xxsp-stockos64-mod.zip"
  elseif port == "portmaster" then
    return "gen1recomp-" .. version .. "-sbc-portmaster.zip"
  elseif osName == "Android" then
    return "gen1recomp-" .. version .. "-android.apk"
  elseif osName == "iOS" then
    return "gen1recomp++-" .. version .. "-ios.ipa"
  elseif osName == "OS X" or osName == "macOS" then
    return "gen1recomp-" .. version .. "-macos.zip"
  elseif osName == "Windows" then
    return "gen1recomp-" .. version .. "-windows.zip"
  elseif osName == "UWP" then
    return "gen1recomp-" .. version .. "-xbox-uwp.zip"
  elseif osName == "NX" then
    return "gen1recomp-" .. version .. "-switch.zip"
  elseif osName == "Linux" and (arch == "arm64" or arch == "aarch64") then
    return "gen1recomp-" .. version .. "-linux-arm64.AppImage"
  elseif osName == "Linux" then
    return "gen1recomp-" .. version .. "-linux.zip"
  end
  return nil
end

function Check.fullAssetName(version, osName, arch, port)
  if type(version) ~= "string" or not version:match("^%d+%.%d+%.%d+$") then
    return nil
  end
  return fullAssetName(version, osName, arch, port)
end

-- A legacy Android APK can run a newer downloaded payload while still lacking
-- the native bridge that installs future APK updates. It needs one manual
-- package update even when that payload already reports the latest engine.
function Check.androidNeedsInstallerBootstrap(osName, hasInstaller)
  return osName == "Android" and not hasInstaller
end

local CMD = "update_check_cmd"
local STATE = "update_check_state"

-- ---------------------------------------------------------------------------
-- pure helpers (no love.*) -- also used inside the worker
-- ---------------------------------------------------------------------------

-- Find the release asset named exactly `name`, returning its download URL and
-- byte size (or nil when the release has no such asset).
function Check.pickAsset(assets, name)
  if type(assets) ~= "table" then return nil end
  for _, a in ipairs(assets) do
    if type(a) == "table" and a.name == name then
      return { url = a.browser_download_url, size = tonumber(a.size) }
    end
  end
  return nil
end

local function stripV(tag)
  return (tostring(tag):gsub("^[vV]", ""))
end

-- Decode a GitHub "releases/latest" response into just the fields the updater
-- needs.  Returns { version, payloadName, payload, sums } where payload/sums are
-- { url, size } tables (or nil when that asset is missing), or nil, err when the
-- document is not a release with a strict X.Y.Z tag.  Json is injected so the
-- worker can pass a filesystem-loaded codec; on the main thread / in tests it
-- falls back to require.
function Check.parseRelease(jsonText, Json, target)
  Json = Json or require("src.link.Json")
  local notJson = Json.describeUnexpected(jsonText)
  if notJson then return nil, notJson end
  local doc, decodeErr = Json.decode(jsonText)
  if type(doc) ~= "table" then
    return nil, decodeErr or "no tag_name in release json"
  end
  if not doc.tag_name then
    return nil, "no tag_name in release json"
  end
  local version = stripV(doc.tag_name)
  if not version:match("^%d+%.%d+%.%d+$") then
    return nil, "release tag is not X.Y.Z: " .. tostring(doc.tag_name)
  end
  local payloadName = "gen1recomp-" .. version .. ".love"
  target = type(target) == "table" and target or {}
  local fullName = fullAssetName(version, target.os, target.arch, target.port)
  return {
    version = version,
    payloadName = payloadName,
    payload = Check.pickAsset(doc.assets, payloadName),
    sums = Check.pickAsset(doc.assets, "sha256sums.txt"),
    fullName = fullName,
    full = fullName and Check.pickAsset(doc.assets, fullName) or nil,
    -- GitHub release body: already fetched with the update check, shown by
    -- the launcher's Patch notes footer button.
    notes = type(doc.body) == "string" and doc.body or "",
  }
end

-- Parse a shasum -a 256 file ("<hex>  <filename>", bare filenames).  With a
-- `target` argument returns just that file's hash (or nil); otherwise returns
-- the whole name -> hash map.  Tolerates the "*" binary marker and "./" prefix.
function Check.parseSums(text, target)
  local map = {}
  for line in tostring(text):gmatch("[^\r\n]+") do
    local hash, file = line:match("^(%x+)%s+%*?(%S+)")
    if hash and file then
      map[(file:gsub("^%./", ""))] = hash:lower()
    end
  end
  if target ~= nil then return map[target] end
  return map
end

-- ---------------------------------------------------------------------------
-- main-thread state machine
-- ---------------------------------------------------------------------------

function Check.releaseUrl()
  return "https://github.com/" .. Check.REPO .. "/releases/latest"
end

local worker           -- the love.thread, once started
local cmdCh, stateCh   -- the two channels
local workerReady      -- nil = untried, true = running, false = unavailable
local requested        -- a check has been asked for this session
local cache = { status = "idle" } -- newest snapshot from the worker

local function target()
  local osName = love and love.system and love.system.getOS and love.system.getOS() or nil
  local arch = jit and jit.arch or nil
  local port = os.getenv("POKEPORT_PORTMASTER")
  return { os = osName, arch = arch, port = port }
end

local function readPersistedFullRequirement()
  if not (love and love.filesystem and love.filesystem.getInfo) then return nil end
  local path = "updates/full-update.json"
  if not love.filesystem.getInfo(path) then return nil end
  local text = love.filesystem.read(path)
  if type(text) ~= "string" then return nil end
  local ok, Json = pcall(require, "src.link.Json")
  if not ok or not Json then return nil end
  local decodedOk, requirement = pcall(Json.decode, text)
  if not decodedOk or type(requirement) ~= "table" then return nil end
  if type(requirement.version) ~= "string" then return nil end
  return requirement
end

local persistedRequirement = readPersistedFullRequirement()
if persistedRequirement then
  cache = {
    status = "needs_full",
    latest = persistedRequirement.version,
    reason = persistedRequirement.reason,
    full = persistedRequirement.full,
  }
end

local function ensureWorker()
  if workerReady ~= nil then return workerReady end
  if not Platform.networkValidated() then
    workerReady = false
    return false
  end
  if not (love and love.thread and love.thread.newThread) then
    workerReady = false
    return false
  end
  local ok, th = pcall(love.thread.newThread, "src/update/check_worker.lua")
  if not ok or not th then
    workerReady = false
    return false
  end
  cmdCh = love.thread.getChannel(CMD)
  stateCh = love.thread.getChannel(STATE)
  if not pcall(function() th:start() end) then
    workerReady = false
    return false
  end
  worker = th
  workerReady = true
  return true
end

-- Pull every pending snapshot off the state channel (keeping the newest) and
-- surface a worker crash as a soft error the UI can hide on.
local function drain()
  if stateCh then
    local msg = stateCh:pop()
    while msg do
      if type(msg) == "table" and type(msg.notes) ~= "string"
          and type(cache.notes) == "string" then
        msg.notes = cache.notes
      end
      cache = msg
      msg = stateCh:pop()
    end
  end
  if worker then
    local err = worker:getError()
    if err then
      cache = { status = "error", error = tostring(err) }
    end
  end
end

-- Begin (or, on a prior error, retry) an async check.  Safe to call every frame:
-- once a check is in flight or has reached a terminal state it is a no-op unless
-- force=true is passed (e.g. from an explicit button press).
function Check.start(force)
  drain()
  if cache.status == "checking" or cache.status == "downloading" then return end
  if not force and requested and cache.status ~= "error" and cache.status ~= "idle" then return end
  if not ensureWorker() then
    cache = { status = "error", error = "background threads unavailable" }
    return
  end
  requested = true
  cache = { status = "checking", notes = cache.notes, latest = cache.latest }
  cmdCh:push({ cmd = "check", target = target() })
end

-- Current snapshot: { status, latest, progress, error, notes, reason, full }.
-- status is one of
-- idle | checking | uptodate | available | downloading | ready | needs_full |
-- full_downloading | full_ready | error.
function Check.state()
  drain()
  return {
    status = cache.status or "idle",
    latest = cache.latest,
    progress = cache.progress,
    error = cache.error,
    notes = cache.notes,
    reason = cache.reason,
    full = cache.full,
  }
end

-- The full-update record is intentionally persistent. An offline launch still
-- tells the player why this native shell cannot run the downloaded release.
function Check.fullUpdateAction()
  drain()
  local st = Check.state()
  if st.status ~= "needs_full" and st.status ~= "full_ready" then return nil end
  local osName = love and love.system and love.system.getOS and love.system.getOS() or ""
  if osName == "Android" and type(st.full) == "table"
      and type(st.full.url) == "string" then
    if type(love.system.installApk) == "function" then
      if st.status == "full_ready" and type(st.full.path) == "string" then
        return { label = "Install Android update", kind = "install" }
      end
      return { label = "Download Android update", kind = "download" }
    end
    return { label = "Update app manually", url = st.full.url }
  end
  if osName == "iOS" then
    return { label = "Re-sideload app", url =
      "https://github.com/bryanthaboi/gen1recomp/raw/refs/heads/main/mobile/ios/app-repo.json" }
  elseif osName == "UWP" then
    return { label = "Open Xbox install guide", url = Check.releaseUrl() }
  elseif type(st.full) == "table" and type(st.full.url) == "string" then
    return { label = "Download full update", url = st.full.url }
  end
  return { label = "Open releases", url = Check.releaseUrl() }
end

function Check.downloadFull()
  drain()
  if not cmdCh or cache.status ~= "needs_full" then return false end
  if not (cache.full and cache.full.url) then return false end
  cache = { status = "full_downloading", latest = cache.latest, progress = 0,
    reason = cache.reason, full = cache.full, notes = cache.notes }
  cmdCh:push({ cmd = "download_full" })
  return true
end

function Check.installFull()
  drain()
  if cache.status ~= "full_ready" then return false end
  local path = cache.full and cache.full.path
  if type(path) ~= "string" or path == "" then return false end
  if not (love and love.system and type(love.system.installApk) == "function") then return false end
  local ok, started = pcall(love.system.installApk, path)
  return ok and started == true
end

function Check.performFullUpdate()
  local action = Check.fullUpdateAction()
  if not action then return false end
  if action.kind == "download" then return Check.downloadFull() end
  if action.kind == "install" then return Check.installFull() end
  if action.url and love and love.system and love.system.openURL then
    return pcall(love.system.openURL, action.url)
  end
  return false
end

-- Start downloading the payload announced by an "available" check.  A no-op in
-- any other state (the worker still holds the release info from the check).
function Check.download()
  drain()
  if not cmdCh then return end
  if cache.status ~= "available" then return end
  cache = { status = "downloading", latest = cache.latest, progress = 0,
    notes = cache.notes }
  cmdCh:push({ cmd = "download" })
end

-- End the worker thread.  Its command loop sits in Channel:demand(), which
-- never returns on its own, and LOVE waits for every live love.thread before
-- the process exits (#339).
function Check.shutdown()
  if cmdCh then cmdCh:push({ cmd = "quit" }) end
  if worker then pcall(function() worker:wait() end) end
  worker, cmdCh, stateCh = nil, nil, nil
  workerReady = nil
end

require("src.core.SessionLifecycle").registerProcessShutdown(Check.shutdown)

return Check
