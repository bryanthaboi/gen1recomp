-- Sandboxed background asset-I/O: declared imports + owning private cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Job = require("src.mods.Job")
local JobAssetIO = require("src.mods.JobAssetIO")
local Json = require("src.link.Json")

local digest = "00000000000000000000000000000000"
local files = {
  ["mods/asset_probe/baseroms/source.iso"] = "0123456789abcdef",
  ["mods/asset_probe/baseroms/.required-import-disc.validated"] =
    "v1\n" .. digest .. "\n16\n1\n",
}

local fs = {
  read = function(path) return files[path] end,
  write = function(path, body) files[path] = body return true end,
  getInfo = function(path)
    local body = files[path]
    if body ~= nil then return { type = "file", size = #body, modtime = 1 } end
    local prefix = path .. "/"
    for key in pairs(files) do
      if key:sub(1, #prefix) == prefix then return { type = "directory" } end
    end
    return nil
  end,
  readRange = function(path, offset, length)
    local body = files[path]
    if not body then return nil end
    return body:sub(offset + 1, offset + length)
  end,
  createDirectory = function() return true end,
  remove = function(path) files[path] = nil return true end,
}

local manifest = {
  id = "asset_probe",
  path = "mods/asset_probe",
  permissionSet = { background = true },
  required_imports = {{
    id = "disc", name = "Disc", file = "source.iso", md5 = { digest }, size = 16,
  }},
  optional_imports = {},
}

-- The descriptor carries declarations, not host paths or a filesystem handle.
local descriptor, descriptorErr = JobAssetIO.descriptor(manifest, manifest.path)
T.check(descriptor ~= nil, "asset descriptor builds (" .. tostring(descriptorErr) .. ")")
T.eq(descriptor.id, "asset_probe", "descriptor binds the owning mod id")
T.eq(descriptor.path, "mods/asset_probe", "descriptor keeps the engine-owned mod root")
T.eq(descriptor.fs, nil, "descriptor does not carry a filesystem handle")
T.eq(descriptor.cache, nil, "descriptor does not carry a cache path/handle")

-- Reconstructed worker facade is exactly the import/cache subset.
local asset, openErr = JobAssetIO.open(descriptor, fs, "asset_probe")
T.check(asset ~= nil, "worker asset facade opens (" .. tostring(openErr) .. ")")
T.eq(type(asset.imports), "table", "worker gets imports capability")
T.eq(type(asset.cache), "table", "worker gets cache capability")
T.eq(asset.cache.delete, nil, "worker cache deliberately has no destructive delete")
T.eq(asset.filesystem, nil, "worker facade exposes no raw filesystem")

local info, infoErr = asset.imports:info("disc")
T.check(type(info) == "table", "declared validated import has info (" .. tostring(infoErr) .. ")")
T.eq(info.size, 16, "worker import info reports stored size")
local slice, sliceErr = asset.imports:read("disc", 4, 6)
T.eq(slice, "456789", "worker bounded import read seeks exact bytes")
T.eq(sliceErr, nil, "worker bounded import read has no error")
local oob, oobErr = asset.imports:read("disc", 15, 2)
T.eq(oob, nil, "worker out-of-bounds import read is refused")
T.check(oobErr and oobErr:find("out of bounds", 1, true),
  "worker out-of-bounds refusal is explicit")
local undeclared, undeclaredErr = asset.imports:read("other", 0, 1)
T.eq(undeclared, nil, "worker cannot read an undeclared import")
T.check(undeclaredErr and undeclaredErr:find("undeclared", 1, true),
  "undeclared worker import refusal is explicit")

local wrote, writeErr = asset.cache:write("models/059/model.bin", "runtime-bytes")
T.check(wrote == true, "worker private-cache write succeeds (" .. tostring(writeErr) .. ")")
T.eq(asset.cache:read("models/059/model.bin"), "runtime-bytes",
  "worker private-cache read returns exact bytes")
T.eq(asset.cache:exists("models/059/model.bin"), true,
  "worker private-cache exists sees completed file")
T.eq(asset.cache:info("models/059/model.bin").size, 13,
  "worker private-cache info stays scoped")
T.eq(files["mod_cache/asset_probe/models/059/model.bin"], "runtime-bytes",
  "worker output is rooted under the owning mod id")
local escaped = pcall(function() asset.cache:write("../escape.bin", "x") end)
T.eq(escaped, false, "worker cache traversal is rejected")
T.eq(files["escape.bin"], nil, "worker traversal creates nothing outside cache root")

local wrong, wrongErr = JobAssetIO.open(descriptor, fs, "different_mod")
T.eq(wrong, nil, "descriptor cannot be rebound to another mod")
T.check(wrongErr and wrongErr:find("owner mismatch", 1, true),
  "cross-mod descriptor refusal names ownership")
local badPath = {
  id = "asset_probe", path = "../other_mod",
  required_imports = manifest.required_imports, optional_imports = {},
}
local climbed, climbedErr = JobAssetIO.open(badPath, fs, "asset_probe")
T.eq(climbed, nil, "worker descriptor cannot climb to another root")
T.check(climbedErr and climbedErr:find("inside its root", 1, true),
  "worker descriptor path refusal uses the safe-path rule")

-- Parent-side transport: assetIO gets a longer bounded foreground budget and
-- the worker receives only JSON descriptor metadata. Pure compute remains 30s.
local previousLove = rawget(_G, "love")
local startedArgs
local channels = {}
local function channel(name)
  local ch = channels[name]
  if ch then return ch end
  ch = { values = {} }
  function ch:clear() self.values = {} end
  function ch:push(v) self.values[#self.values + 1] = v return true end
  function ch:pop()
    if #self.values == 0 then return nil end
    return table.remove(self.values, 1)
  end
  channels[name] = ch
  return ch
end
_G.love = {
  thread = {
    getChannel = channel,
    newThread = function(path)
      T.eq(path, "src/mods/job_worker.lua", "Job.run uses the engine worker")
      return {
        start = function(_, ...)
          startedArgs = { ... }
          return true
        end,
        getError = function() return nil end,
      }
    end,
  },
  timer = { getTime = function() return 100 end },
}

local loader = { mods = { asset_probe = { manifest = manifest } }, jobs = {} }
local handle, runErr = Job.run(loader, "asset_probe", "mods/asset_probe",
  "jobs/build.lua", { asset = 59 }, { assetIO = true, maxSeconds = 999 })
T.check(handle ~= nil, "asset-I/O Job.run starts (" .. tostring(runErr) .. ")")
local state = handle and loader.jobs.asset_probe[handle]
T.eq(state and state.seconds, 300, "asset-I/O jobs have a hard 300-second poll budget")
T.eq(startedArgs and startedArgs[1], "asset_probe", "worker transport binds owner id")
local transported = startedArgs and Json.decode(startedArgs[6] or "")
T.eq(transported and transported.id, "asset_probe", "worker transport includes owner descriptor")
T.eq(transported and transported.path, "mods/asset_probe", "worker transport includes only safe mod root")
T.eq(transported and transported.required_imports[1].id, "disc",
  "worker transport includes declared import metadata")
T.eq(transported and transported.permissionSet, nil,
  "asset descriptor does not duplicate unrelated manifest state")
if handle then Job.release(loader, "asset_probe", handle) end

startedArgs = nil
local pureHandle, pureErr = Job.run(loader, "asset_probe", "mods/asset_probe",
  "jobs/crunch.lua", { n = 4 }, { maxSeconds = 999 })
T.check(pureHandle ~= nil, "pure Job.run still starts (" .. tostring(pureErr) .. ")")
local pureState = pureHandle and loader.jobs.asset_probe[pureHandle]
T.eq(pureState and pureState.seconds, 30, "pure-compute job timeout remains capped at 30 seconds")
T.eq(startedArgs and startedArgs[6], "", "pure-compute worker receives no asset-I/O descriptor")
if pureHandle then Job.release(loader, "asset_probe", pureHandle) end
_G.love = previousLove

T.finish("mod_job_asset_io")
