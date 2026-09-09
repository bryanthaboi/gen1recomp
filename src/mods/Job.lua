-- Background compute for sandboxed mods, behind the "background" permission.
--
-- mod.fetch covers work that is waiting on a server.  This covers work that is
-- waiting on the CPU: a mod hands over a script from its own folder plus a
-- table of plain data, and gets the return value back through the same
-- handle/poll/release shape mod.fetch uses.
--
-- The worker (src/mods/job_worker.lua) builds the SAME Sandbox.envFor
-- environment the main thread does before it loads the mod's chunk, so this
-- is not the love.thread hole reopened: the mod's code still cannot see
-- io, os, debug, ffi, package or love.filesystem, and require is refused
-- outright inside a job.
--
-- One thread per job rather than a pool.  A pooled state would carry one
-- mod's globals into the next mod's job, and resetting it properly is the
-- same work as making a new one.

local SafePath = require("src.mods.SafePath")
local JobAssetIO = require("src.mods.JobAssetIO")

local Job = {}

Job.MAX_INFLIGHT = 2       -- per mod
Job.MAX_GLOBAL = 4         -- across all mods, so jobs cannot eat every core
Job.DEFAULT_SECONDS = 5
Job.MAX_SECONDS = 30
Job.MAX_ASSET_SECONDS = 300 -- explicit source/cache preprocessing jobs
-- Depth cap on the data crossing the channel.  A cycle is caught by the seen
-- set; this catches the merely absurd.
Job.MAX_DEPTH = 16

local nextId = 0
local liveGlobal = 0

-- Only plain data crosses a thread boundary: a function or userdata cannot be
-- serialised, and letting one through would fail deep inside LÖVE instead of
-- at the call the mod made.
local function plain(value, depth, seen)
  local t = type(value)
  if t == "nil" or t == "boolean" or t == "number" or t == "string" then
    return value
  end
  if t ~= "table" then
    return nil, ("a job cannot carry a %s, only plain data"):format(t)
  end
  depth = (depth or 0) + 1
  if depth > Job.MAX_DEPTH then
    return nil, "a job's data is nested too deeply"
  end
  seen = seen or {}
  if seen[value] then return nil, "a job cannot carry a cycle" end
  seen[value] = true
  local out = {}
  for k, v in pairs(value) do
    local kt = type(k)
    if kt ~= "string" and kt ~= "number" then
      return nil, ("a job cannot carry a %s key"):format(kt)
    end
    local copied, err = plain(v, depth, seen)
    if err then return nil, err end
    out[k] = copied
  end
  seen[value] = nil
  return out
end
Job.plain = plain

function Job.available()
  return (love and love.thread and love.thread.newThread) ~= nil
end

local function bucket(loader, modId)
  loader.jobs = loader.jobs or {}
  local b = loader.jobs[modId]
  if not b then b = {}; loader.jobs[modId] = b end
  return b
end

local function inflight(b)
  local n = 0
  for _, job in pairs(b) do
    if job.status == "pending" then n = n + 1 end
  end
  return n
end

-- `script` is relative to the mod's own folder, and goes through the same
-- SafePath rules mod:read does -- a job is not a way to name a path.
-- Argument checks come BEFORE the host check: a bad path or an unserialisable
-- argument is the mod author's bug and should read the same on every machine,
-- not be masked into "unavailable" on a build without threads.
function Job.run(loader, modId, modPath, script, arg, opts)
  if type(script) ~= "string" or script == "" then
    return nil, "a job needs a script path inside your mod"
  end
  -- SafePath.require raises rather than returning, so the mod's bad path
  -- comes back as a value here instead of unwinding its caller.
  local okPath, safe = pcall(SafePath.join, modPath, script, "a job script")
  if not okPath then return nil, tostring(safe) end
  local payload, dataErr = plain(arg)
  if dataErr then return nil, dataErr end
  if not Job.available() then return nil, "background jobs are unavailable" end

  local b = bucket(loader, modId)
  if inflight(b) >= Job.MAX_INFLIGHT then
    return nil, ("too many jobs in flight (limit %d); poll and release the "
      .. "ones you have"):format(Job.MAX_INFLIGHT)
  end
  if liveGlobal >= Job.MAX_GLOBAL then
    return nil, "the machine is already running as many jobs as it will"
  end

  opts = type(opts) == "table" and opts or {}
  local assetIO = opts.assetIO == true
  local seconds = tonumber(opts.maxSeconds) or Job.DEFAULT_SECONDS
  local maxSeconds = assetIO and Job.MAX_ASSET_SECONDS or Job.MAX_SECONDS
  if seconds > maxSeconds then seconds = maxSeconds end
  if seconds < 1 then seconds = 1 end

  -- Asset-I/O is opt-in per job. Only a data-only copy of this mod's own
  -- import declarations and root crosses the thread boundary; the worker
  -- reconstructs the actual capability with engine-owned validation.
  local assetDescriptor = nil
  if assetIO then
    local mod = loader.mods and loader.mods[modId]
    local descriptor, descriptorErr = JobAssetIO.descriptor(
      mod and mod.manifest, modPath)
    if not descriptor then return nil, descriptorErr end
    assetDescriptor, dataErr = plain(descriptor)
    if dataErr then return nil, dataErr end
  end

  nextId = nextId + 1
  local argName = "modjob_arg_" .. nextId
  local resultName = "modjob_result_" .. nextId
  local argCh = love.thread.getChannel(argName)
  local resCh = love.thread.getChannel(resultName)
  argCh:clear()
  resCh:clear()
  argCh:push(payload == nil and false or payload)

  local okNew, thread = pcall(love.thread.newThread, "src/mods/job_worker.lua")
  if not okNew or not thread then return nil, "could not start a job thread" end
  local Json = require("src.link.Json")
  local permissions = select(2, pcall(Json.encode,
    loader.mods and loader.mods[modId]
      and loader.mods[modId].manifest.permissionSet or {})) or "{}"
  local assetJson = ""
  if assetDescriptor then
    local okAsset, encoded = pcall(Json.encode, assetDescriptor)
    if not okAsset then return nil, "could not encode asset-I/O descriptor" end
    assetJson = encoded
  end
  local started = pcall(thread.start, thread, modId, safe, argName, resultName,
    permissions, assetJson)
  if not started then return nil, "could not start a job thread" end

  liveGlobal = liveGlobal + 1
  local handle = {}
  b[handle] = { thread = thread, resultCh = resCh, status = "pending",
                deadline = love.timer.getTime() + seconds, seconds = seconds }
  return handle
end

local function settle(job, status, value, err)
  if job.status == "pending" then liveGlobal = math.max(0, liveGlobal - 1) end
  job.status, job.value, job.err = status, value, err
end

function Job.poll(loader, modId, handle)
  local job = bucket(loader, modId)[handle]
  if not job then return { status = "error", err = "unknown job" } end
  if job.status == "pending" then
    local msg = job.resultCh:pop()
    if msg then
      if msg.ok then settle(job, "ok", msg.result)
      else settle(job, "error", nil, msg.err) end
    else
      -- A worker that died before pushing anything (an error outside its own
      -- pcall) would otherwise leave the mod polling forever.
      local threadErr = job.thread.getError and job.thread:getError()
      if threadErr then
        settle(job, "error", nil, tostring(threadErr))
      elseif love.timer.getTime() > job.deadline then
        -- The budget bounds how long the MOD waits, not how long the work
        -- runs: there is no way to stop a LÖVE thread, and every in-worker
        -- attempt made things worse (see job_worker.lua).  A job that
        -- overruns is reported here and its result dropped if it ever lands.
        settle(job, "error", nil, ("job exceeded its %gs budget")
          :format(job.seconds))
      end
    end
  end
  if job.status == "ok" then
    -- A copy, so a mod cannot edit what a later poll returns.
    return { status = "ok", result = (plain(job.value)) }
  end
  return { status = job.status, err = job.err }
end

function Job.release(loader, modId, handle)
  local b = bucket(loader, modId)
  local job = b[handle]
  if not job then return false end
  if job.status == "pending" then liveGlobal = math.max(0, liveGlobal - 1) end
  b[handle] = nil
  return true
end

-- There is no way to kill a LÖVE thread, so cancelling drops the result
-- rather than stopping the work; the worker's own time budget is what bounds
-- how long an abandoned job can run.
function Job.cancel(loader, modId, handle)
  local job = bucket(loader, modId)[handle]
  if not job then return false end
  if job.status == "pending" then
    settle(job, "cancelled")
  end
  return true
end

function Job.releaseAll(loader, modId)
  local b = loader.jobs and loader.jobs[modId]
  if not b then return end
  for handle, job in pairs(b) do
    if job.status == "pending" then liveGlobal = math.max(0, liveGlobal - 1) end
    b[handle] = nil
  end
  loader.jobs[modId] = nil
end

return Job
