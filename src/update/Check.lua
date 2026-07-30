-- Async release-check and payload-download for the self-update flow.
--
-- The heavy lifting (curl calls, sha256 verification, the Boot gate) happens
-- on a background love.thread worker (src/update/check_worker.lua); this module
-- is only the thin main-thread state machine the UI polls.  Two channels carry
-- the conversation:
--   "update_check_cmd"   main -> worker: { cmd = "check" | "download" | "quit" }
--   "update_check_state" worker -> main: { status, latest, progress, error }
--
-- Nothing here ever blocks or throws into the game loop: when love.thread is
-- absent (the headless test stub) or the worker cannot run (no curl, Android),
-- state() simply reports "error" and the UI hides itself.  See the shared
-- contract in the task brief for the status vocabulary and the file layout.
--
-- The release-JSON extraction and the sums parsing are exported as pure
-- functions (no love.* calls) so plain-Lua tests can cover them, and so the
-- worker can reuse the exact same code path via love.filesystem.load.

local Check = {}

Check.REPO = "bryanthaboi/gen1recomp"

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
function Check.parseRelease(jsonText, Json)
  Json = Json or require("src.link.Json")
  local doc = Json.decode(jsonText)
  if type(doc) ~= "table" or not doc.tag_name then
    return nil, "no tag_name in release json"
  end
  local version = stripV(doc.tag_name)
  if not version:match("^%d+%.%d+%.%d+$") then
    return nil, "release tag is not X.Y.Z: " .. tostring(doc.tag_name)
  end
  local payloadName = "gen1recomp-" .. version .. ".love"
  return {
    version = version,
    payloadName = payloadName,
    payload = Check.pickAsset(doc.assets, payloadName),
    sums = Check.pickAsset(doc.assets, "sha256sums.txt"),
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

local function ensureWorker()
  if workerReady ~= nil then return workerReady end
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
-- once a check is in flight or has reached a terminal state it is a no-op.
function Check.start()
  drain()
  if cache.status == "checking" or cache.status == "downloading" then return end
  if requested and cache.status ~= "error" and cache.status ~= "idle" then return end
  if not ensureWorker() then
    cache = { status = "error", error = "background threads unavailable" }
    return
  end
  requested = true
  cache = { status = "checking" }
  cmdCh:push({ cmd = "check" })
end

-- Current snapshot: { status, latest, progress, error }.  status is one of
-- idle | checking | uptodate | available | downloading | ready | needs_full | error.
function Check.state()
  drain()
  return {
    status = cache.status or "idle",
    latest = cache.latest,
    progress = cache.progress,
    error = cache.error,
  }
end

-- Start downloading the payload announced by an "available" check.  A no-op in
-- any other state (the worker still holds the release info from the check).
function Check.download()
  drain()
  if not cmdCh then return end
  if cache.status ~= "available" then return end
  cache = { status = "downloading", latest = cache.latest, progress = 0 }
  cmdCh:push({ cmd = "download" })
end

-- Stop the worker thread (called from love.quit); same process-reuse rationale
-- as ChipAudio.shutdown.  An idle worker wakes from its demand() immediately;
-- one that is mid check/download only sees the command once the transfer
-- settles, so skip the join in those states: quit must not block behind curl.
function Check.shutdown()
  if not worker then return end
  drain()
  if cmdCh then cmdCh:push({ cmd = "quit" }) end
  if cache.status ~= "checking" and cache.status ~= "downloading" then
    pcall(function() worker:wait() end)
  end
  worker = nil
  workerReady = false
end

return Check
