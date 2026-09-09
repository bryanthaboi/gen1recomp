-- Worker state behind src/mods/Job.lua.  One per job, not a pool: a reused
-- state would carry one mod's globals into another mod's job.
--
-- This is the file that makes running mod Lua off the main thread safe.  The
-- mod's chunk is loaded into the SAME sandbox environment the main thread
-- builds (Sandbox.envFor), so love.filesystem, io, os, debug, ffi and package
-- are as absent here as they are there -- even though this state required
-- love.filesystem to bootstrap itself.
--
-- A normal job is pure compute: plain data in, plain data out, no engine API
-- or game state. An explicit asset-I/O job additionally receives only the
-- owning mod's declared-import/private-cache facade; raw filesystem access
-- remains hidden. require is refused outright rather than reaching src.*.

require("love.thread")
require("love.filesystem")
require("love.timer")

local modId, scriptPath, argChannel, resultChannel, permissionsJson, assetJson = ...

-- Fresh love threads have no "src.*" searcher (see src/net/fetch_worker.lua),
-- so install one before Sandbox's own requires run.
table.insert(package.loaders or package.searchers, function(name)
  local path = name:gsub("%.", "/") .. ".lua"
  if not love.filesystem.getInfo(path) then return nil end
  return love.filesystem.load(path)
end)

local resCh = love.thread.getChannel(resultChannel)

local function fail(err)
  resCh:push({ ok = false, err = tostring(err) })
end

local ok, err = pcall(function()
  local Sandbox = require("src.mods.Sandbox")
  local Json = require("src.link.Json")

  local permissions = {}
  if type(permissionsJson) == "string" and permissionsJson ~= "" then
    local decoded = select(2, pcall(Json.decode, permissionsJson))
    if type(decoded) == "table" then permissions = decoded end
  end

  local env = Sandbox.envFor({ modId = modId, permissions = permissions })

  -- Asset preprocessors get a capability object, never love.filesystem. The
  -- descriptor was assembled by Job.run from this mod's validated manifest;
  -- JobAssetIO re-checks ownership and routes every operation through the same
  -- ImportAccess bounds/safe paths as mod.imports and mod.cache.
  if type(assetJson) == "string" and assetJson ~= "" then
    local descriptor = select(2, pcall(Json.decode, assetJson))
    if type(descriptor) ~= "table" then
      error("invalid asset-I/O descriptor", 0)
    end
    local JobAssetIO = require("src.mods.JobAssetIO")
    local assetApi, assetErr = JobAssetIO.open(descriptor, love.filesystem, modId)
    if not assetApi then error(assetErr or "asset-I/O unavailable", 0) end
    env.job = assetApi
  end

  -- A job cannot reach the engine. Anything else it needs comes in through
  -- its argument and goes back through its return value.
  env.require = function(name)
    error(("[%s] require(%q) is not available inside a background job; a job "
      .. "takes plain data and returns plain data"):format(modId,
      tostring(name)), 2)
  end

  local chunk, loadErr = Sandbox.loadFile(love.filesystem, scriptPath, env)
  if not chunk then error(loadErr or ("could not load " .. scriptPath), 0) end

  local arg = love.thread.getChannel(argChannel):pop()

  -- NO in-worker time budget, deliberately.  A debug count hook was the
  -- obvious way to stop a runaway, and it does not work: LuaJIT swallows an
  -- error raised from a hook (measured: ~5000 raises a second, the loop
  -- running straight through them), and the raising itself wedged the whole
  -- process -- the main thread stopped being scheduled at all.  Without the
  -- hook a runaway job simply spins on its own core, the game stays
  -- responsive, and it quits normally.  Job.poll enforces maxSeconds on the
  -- main thread so the MOD is never left waiting; the work itself runs to its
  -- own end.
  local ranOk, result = pcall(chunk, arg)
  if not ranOk then error(result, 0) end
  resCh:push({ ok = true, result = result })
end)

if not ok then fail(err) end
