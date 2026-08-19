-- Async HTTP for the launcher: a small job queue over a pool of love.thread
-- workers.
--
-- WHY THIS EXISTS.  Every network call in the launcher used to run on the
-- render thread.  HostShell.httpGet shells out to curl through io.popen and
-- reads the pipe to EOF, so refreshing the mod index, checking one mod's
-- releases, or opening the Find Mods tab froze the window for as long as the
-- server took -- measured at over two minutes on a cold Find Mods open, with
-- no spinner, no progress and no way to cancel, because the frame that would
-- have drawn them never ran.  The self-updater already did this correctly on
-- a worker (src/update/check_worker.lua); this generalises that pattern so
-- everything else can follow it.
--
-- CONTRACT.  Callers get an opaque job id back immediately and poll it:
--     local job = Fetch.get(url)
--     ...
--     local st = Fetch.poll(job)     -- { status, body, err, progress }
--     if st.status == "ok" then ... end
-- status is: pending | ok | error | cancelled.  poll() never blocks and
-- never throws.  A job's result is retained until Fetch.release(job), so a
-- caller that polls once per frame cannot miss it.
--
-- DEGRADATION.  With no love.thread (the headless test stub), no curl and no
-- Android bridge, jobs complete immediately with status "error" and a reason.
-- The UI shows that as a failed fetch, which is the same path an offline
-- machine takes -- there is no code path where the launcher waits forever.

local Fetch = {}

local CMD    = "fetch_cmd"
local RESULT = "fetch_result"
local QUIT   = "fetch_quit"

-- Worker count.  Three is enough to overlap the common burst (a mod index
-- refresh plus a couple of per-mod release checks) without spawning a thread
-- per row on a 200-mod list; extra jobs queue on the channel.
local POOL = 3

local workers = {}
local cmdCh, resCh, quitCh
local ready          -- nil = untried, true = running, false = unavailable
local jobs = {}      -- id -> { status, body, err, progress, path }
local nextId = 0
local unavailableReason

local function ensureWorkers()
  if ready ~= nil then return ready end
  if not (love and love.thread and love.thread.newThread) then
    ready, unavailableReason = false, "background threads unavailable"
    return false
  end
  cmdCh = love.thread.getChannel(CMD)
  resCh = love.thread.getChannel(RESULT)
  quitCh = love.thread.getChannel(QUIT)
  -- Channels outlive a pool (they are global to the process, keyed by name),
  -- so a pool started after a shutdown -- the save editor opens from a live
  -- launcher and hands the screen back -- must clear the previous round's
  -- flag and leftovers or its workers quit on their first job.
  quitCh:clear()
  cmdCh:clear()
  for i = 1, POOL do
    local ok, th = pcall(love.thread.newThread, "src/net/fetch_worker.lua")
    if ok and th and pcall(function() th:start() end) then
      workers[#workers + 1] = th
    end
  end
  if #workers == 0 then
    ready, unavailableReason = false, "could not start fetch workers"
    return false
  end
  ready = true
  return true
end

-- Move every finished result off the channel into the job table.  Called by
-- poll() and pending(), so a caller that polls any job drains all of them.
local function drain()
  if not resCh then return end
  local msg = resCh:pop()
  while msg do
    if type(msg) == "table" and msg.id then
      local j = jobs[msg.id]
      if j and j.status == "pending" then
        if msg.progress and not msg.done then
          j.progress = msg.progress
        else
          j.status = msg.ok and "ok" or "error"
          j.body, j.err, j.path = msg.body, msg.err, msg.path
          j.code = msg.code
          j.progress = msg.ok and 1 or j.progress
        end
      end
    end
    msg = resCh:pop()
  end
  -- A worker that died takes its in-flight job with it; surface that rather
  -- than leaving the job pending forever (which would hang a loader overlay).
  for _, th in ipairs(workers) do
    local err = th:getError()
    if err then
      for _, j in pairs(jobs) do
        if j.status == "pending" then
          j.status, j.err = "error", tostring(err)
        end
      end
      break
    end
  end
end

local function submit(cmd)
  nextId = nextId + 1
  local id = nextId
  cmd.id = id
  jobs[id] = { status = "pending", progress = 0 }
  if not ensureWorkers() then
    jobs[id].status = "error"
    jobs[id].err = unavailableReason
    return id
  end
  cmdCh:push(cmd)
  return id
end

-- GET a URL, returning the body as a string.
-- opts: { userAgent, accept, maxSeconds }
-- maxSeconds is the transfer ceiling, and it is also this job's worst-case
-- contribution to how long closing the window takes (see Fetch.shutdown).
function Fetch.get(url, opts)
  opts = opts or {}
  return submit({ kind = "get", url = url,
    userAgent = opts.userAgent or "gen1recomp",
    accept = opts.accept, maxSeconds = opts.maxSeconds })
end

-- POST a body to a URL, one-way.  The result carries no body: postLog
-- reporting never trusts a server's reply, so the worker surfaces only
-- ok/error and the transport's complaint.
-- opts: { userAgent, contentType, maxSeconds }
function Fetch.post(url, body, opts)
  opts = opts or {}
  return submit({ kind = "post", url = url, body = body,
    userAgent = opts.userAgent or "gen1recomp",
    contentType = opts.contentType, maxSeconds = opts.maxSeconds })
end

function Fetch.request(url, opts)
  opts = opts or {}
  return submit({ kind = "request", url = url,
    method = opts.method, body = opts.body, headers = opts.headers,
    userAgent = opts.userAgent or "gen1recomp",
    maxSeconds = opts.maxSeconds })
end

-- Download a URL to `saveRel`, a path relative to the LOVE save directory.
-- Progress is reported as a 0..1 fraction when `size` is known.
function Fetch.download(url, saveRel, opts)
  opts = opts or {}
  return submit({ kind = "download", url = url, dest = saveRel,
    size = opts.size,
    userAgent = opts.userAgent or "gen1recomp",
    accept = opts.accept, maxSeconds = opts.maxSeconds })
end

-- Non-blocking status.  Returns a table; never nil, even for an unknown id
-- (an unknown id reads as an error, so a caller that dropped its handle
-- cannot deadlock a loader).
local MISSING = { status = "error", err = "unknown job" }
function Fetch.poll(id)
  drain()
  return jobs[id] or MISSING
end

function Fetch.isPending(id)
  return Fetch.poll(id).status == "pending"
end

-- Forget a finished job.  Callers should do this once they have consumed the
-- result, or the table grows for the life of the process.
function Fetch.release(id)
  jobs[id] = nil
end

-- Mark a job cancelled on the main thread.  The worker's curl is NOT killed
-- (there is no portable way to signal it), but the result is dropped when it
-- lands, so a cancelled download cannot resurrect a closed overlay.
function Fetch.cancel(id)
  local j = jobs[id]
  if j and j.status == "pending" then j.status = "cancelled" end
end

-- True while any job is still running -- drives the "working" indicator in
-- the launcher chrome.
function Fetch.busy()
  drain()
  for _, j in pairs(jobs) do
    if j.status == "pending" then return true end
  end
  return false
end

function Fetch.available()
  return ensureWorkers()
end

-- End every worker.  Their command loops sit in Channel:demand(), which never
-- returns on its own, and LOVE waits for every live love.thread before the
-- process exits (#339).
--
-- ORDER MATTERS, and getting it wrong is what froze the launcher on close
-- after a visit to the mod tabs.  A quit pushed as an ordinary command is
-- just another item in a FIFO the workers are already chewing through: a page
-- of thumbnail downloads sits in front of it, and th:wait() below blocks the
-- main thread until every one of them finishes.  So:
--   1. raise the quit FLAG, which workers check after every demand(),
--   2. CLEAR the queue -- nobody will read those results, and dropping them
--      is what turns "wait for the backlog" into "wait for what is in flight",
--   3. push one wake sentinel per worker, because a worker idling inside
--      demand() has nothing to check the flag on until something arrives.
-- What remains is at most one transfer per worker, bounded by the caller's
-- maxSeconds; there is no portable way to interrupt a running curl.
function Fetch.shutdown()
  if quitCh then quitCh:push(true) end
  if cmdCh then
    cmdCh:clear()
    for _ = 1, #workers do cmdCh:push({ kind = "quit" }) end
  end
  for _, th in ipairs(workers) do pcall(function() th:wait() end) end
  workers = {}
  cmdCh, resCh, quitCh, ready = nil, nil, nil, false
end

return Fetch
