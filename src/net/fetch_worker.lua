-- Worker thread behind src/net/Fetch.lua.  Several of these run as a pool.
--
-- Pulls jobs off the shared "fetch_cmd" channel and pushes results onto
-- "fetch_result".  Every job is wrapped in pcall: a worker that dies takes
-- its in-flight job with it, and Fetch surfaces that as an error rather than
-- leaving a loader overlay spinning forever.
--
-- Transport is HostShell, so this inherits the platform matrix that already
-- exists (curl on desktop, the JNI bridge on Android).  Fresh love threads do
-- not carry the "src.*" package searcher, so HostShell is pulled in with
-- love.filesystem.load exactly like src/update/check_worker.lua does.

require("love.thread")
require("love.filesystem")
require("love.timer")
require("love.system")

local function loadModule(path)
  local ok, chunk = pcall(love.filesystem.load, path)
  if not ok or type(chunk) ~= "function" then return nil end
  local ok2, mod = pcall(chunk)
  if not ok2 then return nil end
  return mod
end

local HostShell = loadModule("src/core/HostShell.lua")

local cmdCh = love.thread.getChannel("fetch_cmd")
local resCh = love.thread.getChannel("fetch_result")
-- Raised by Fetch.shutdown BEFORE the wake sentinels go out.  A worker checks
-- it after every demand() and drops whatever it just pulled, so a quit does
-- not have to wait its turn behind a queue of jobs nobody will ever read the
-- results of.
local quitCh = love.thread.getChannel("fetch_quit")

local saveDir = love.filesystem.getSaveDirectory()

-- See the note in doGet: these bound how long a quit can block.  A mod index
-- or a release list is a small JSON document, and a mod zip is a few MB; the
-- old 300s download ceiling was sized for the self-updater's whole payload,
-- which does not come through this pool.  Callers may pass a shorter one
-- (job.maxSeconds) -- a thumbnail has no business holding the process open
-- for as long as a mod install does.
local GET_MAX_SECONDS = 20
local DOWNLOAD_MAX_SECONDS = 90

local function quitting()
  return quitCh:peek() ~= nil
end

local function post(t) resCh:push(t) end

local function doGet(job)
  if not HostShell then
    post({ id = job.id, ok = false, err = "no transport" })
    return
  end
  -- Bounded transfer time: a worker inside a blocking curl cannot see a quit
  -- command, and LOVE waits for live threads before exiting (#339), so this
  -- ceiling is also the worst case for how long closing the window can take.
  local body, err = HostShell.httpGet(job.url, job.userAgent, job.accept,
    tonumber(job.maxSeconds) or GET_MAX_SECONDS)
  if not body then
    post({ id = job.id, ok = false, err = err or "fetch failed" })
    return
  end
  post({ id = job.id, ok = true, body = body })
end

-- Downloads go straight to the save directory.  HostShell.httpDownload
-- blocks until curl exits, which is fine here -- this is the whole reason
-- the work is on a worker -- but it means progress cannot be sampled from
-- inside the call.  Where the caller knows the expected size we poll the
-- growing file from a second pass instead; where it does not, the job simply
-- reports indeterminate progress and the UI shows a spinner.
--
-- job.etagRel (optional, relative to saveDir like job.dest) turns this into
-- a conditional GET -- see HostShell.httpDownload's own comment for the
-- 304/notModified contract. A notModified result never writes `rel` at all
-- (confirmed empirically, not assumed -- see TrueFX/etag-cache-repro/), so
-- the usual "did a file actually land" check below is skipped for it.
local function doDownload(job)
  if not HostShell then
    post({ id = job.id, ok = false, err = "no transport" })
    return
  end
  local rel = job.dest
  local abs = saveDir .. "/" .. rel
  local dir = rel:match("^(.*)/[^/]*$")
  if dir then love.filesystem.createDirectory(dir) end
  love.filesystem.remove(rel)

  local etagAbs = job.etagRel and (saveDir .. "/" .. job.etagRel) or nil
  local ok, err, notModified = HostShell.httpDownload(job.url, abs, job.userAgent,
    job.accept, tonumber(job.maxSeconds) or DOWNLOAD_MAX_SECONDS, etagAbs)
  if not ok then
    post({ id = job.id, ok = false, err = err or "download failed" })
    return
  end
  if notModified then
    post({ id = job.id, ok = true, path = rel, done = true, notModified = true })
    return
  end
  local info = love.filesystem.getInfo(rel)
  if not info or (info.size or 0) == 0 then
    love.filesystem.remove(rel)
    post({ id = job.id, ok = false, err = "empty download" })
    return
  end
  post({ id = job.id, ok = true, path = rel, done = true })
end

local function doPost(job)
  if not HostShell then
    post({ id = job.id, ok = false, err = "no transport" })
    return
  end
  local ok, err = HostShell.httpPost(job.url, job.body, job.contentType,
    job.userAgent, tonumber(job.maxSeconds) or GET_MAX_SECONDS)
  if not ok then
    post({ id = job.id, ok = false, err = err or "post failed" })
    return
  end
  post({ id = job.id, ok = true, done = true })
end

local function doRequest(job)
  if not HostShell then
    post({ id = job.id, ok = false, err = "no transport" })
    return
  end
  local body, err, code = HostShell.httpRequest(job.url, {
    method = job.method, body = job.body, headers = job.headers,
    userAgent = job.userAgent,
    maxTime = tonumber(job.maxSeconds) or GET_MAX_SECONDS })
  if not code then
    post({ id = job.id, ok = false, err = err or "request failed" })
    return
  end
  post({ id = job.id, ok = true, body = body or "", code = code, done = true })
end

while true do
  local job = cmdCh:demand()
  -- The flag is checked before the job's KIND, so a worker woken by a
  -- sentinel abandons whatever real job it happened to pull instead of
  -- running it.  Without this the quit commands queued behind a page of
  -- thumbnail downloads and closing the window blocked for as long as those
  -- transfers took -- the launcher froze on close after a visit to the mods
  -- tabs, which is exactly what LOVE waiting on live threads looks like.
  if quitting() then break end
  if type(job) == "table" then
    if job.kind == "quit" then
      break
    elseif job.kind == "get" then
      local ok, err = pcall(doGet, job)
      if not ok then post({ id = job.id, ok = false, err = tostring(err) }) end
    elseif job.kind == "post" then
      local ok, err = pcall(doPost, job)
      if not ok then post({ id = job.id, ok = false, err = tostring(err) }) end
    elseif job.kind == "request" then
      local ok, err = pcall(doRequest, job)
      if not ok then post({ id = job.id, ok = false, err = tostring(err) }) end
    elseif job.kind == "download" then
      local ok, err = pcall(doDownload, job)
      if not ok then post({ id = job.id, ok = false, err = tostring(err) }) end
    end
  end
end
