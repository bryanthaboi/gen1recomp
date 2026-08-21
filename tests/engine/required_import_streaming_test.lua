-- Regression for large raw required imports: direct source -> engine-owned
-- baseroms destination, incremental MD5, no whole-file staging requirement.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local RomImporter = require("src.import.RomImporter")
local RequiredImports = require("src.mods.RequiredImports")

-- The stock headless filesystem intentionally omits love.filesystem.newFile.
-- Add the smallest streaming-file facade this transport path needs so the
-- regression drives the same seek/read/write API production LÖVE provides.
local oldNewFile = love.filesystem.newFile
local oldGetInfo = love.filesystem.getInfo
love.filesystem.newFile = function(path)
  local body, pos, mode = love.filesystem.read(path) or "", 1, nil
  local file = {}
  function file:open(m)
    mode = m
    if m == "w" then body, pos = "", 1 else pos = 1 end
    return true
  end
  function file:read(n)
    local out = body:sub(pos, pos + n - 1)
    pos = pos + #out
    if out == "" then return nil end
    return out
  end
  function file:write(bytes)
    if mode ~= "w" then return nil, "not open for write" end
    body = body:sub(1, pos - 1) .. bytes .. body:sub(pos + #bytes)
    pos = pos + #bytes
    love.filesystem.write(path, body)
    return true
  end
  function file:seek(offset) pos = offset + 1 return offset end
  function file:getSize() return #body end
  function file:close()
    if mode == "w" then love.filesystem.write(path, body) end
    mode = nil
    return true
  end
  return file
end
love.filesystem.getInfo = function(path, filter)
  local info = oldGetInfo(path, filter)
  if info and info.type == "file" then
    local bytes = love.filesystem.read(path) or ""
    return { type = "file", size = #bytes, modtime = 1 }
  end
  return info
end

local source = "required_import_streaming_source.tmp"
local f = assert(io.open(source, "wb"))
f:write("abc")
f:close()

local manifest = {
  id = "stream_probe",
  name = "Stream Probe",
  path = "mods/stream_probe",
  required_imports = {
    { id = "source", name = "Source", file = "source.bin", format = "raw",
      size = 3, md5 = { "900150983cd24fb0d6963f7d28e17f72" } },
  },
  optional_imports = {},
}

local importer = setmetatable({
  mods = { { id = "stream_probe", manifest = manifest } },
  requiredImportNotice = nil,
  modNotice = nil,
  _refreshMods = function(self) self._refreshed = true end,
}, RomImporter)

-- Reproduce the Windows failure seen with a 1.46 GiB optical-disc image:
-- after the user accepts the "Large import" confirmation, the old path calls
-- love.filesystem.read(source) and attempts to materialize the entire source as
-- one Lua string. A large raw source must go straight to the streaming branch.
local ordinaryLoveRead = love.filesystem.read
local forbiddenWholeSourceReads = 0
love.filesystem.read = function(path, ...)
  if path == source then
    forbiddenWholeSourceReads = forbiddenWholeSourceReads + 1
    error("large external required import used whole-file love.filesystem.read")
  end
  return ordinaryLoveRead(path, ...)
end

-- Exercise the exact large-file branch with tiny fixture bytes by lowering the
-- threshold for this test. Production keeps the 128 MiB confirmation/streaming
-- threshold; the copy/hash algorithm is identical.
local oldWarn = RequiredImports.LARGE_WARN_BYTES
RequiredImports.LARGE_WARN_BYTES = 2
local ok = importer:_importRequiredSource("stream_probe", "source", source, true)
RequiredImports.LARGE_WARN_BYTES = oldWarn
love.filesystem.read = ordinaryLoveRead

T.eq(ok, true, "large raw required import streams successfully")
T.eq(forbiddenWholeSourceReads, 0,
  "post-confirm large import never materializes the external source as one Lua string")
T.eq(love.filesystem.read("mods/stream_probe/baseroms/source.bin"), "abc",
  "streamed destination preserves exact source bytes")
T.eq(importer.requiredImportNotice, nil, "successful stream leaves no import error")
T.eq(importer._refreshed, true, "successful stream refreshes the mod list")

local CacheFs = require("src.import.CacheFs")

-- A thrown writer error must not leak the temporary empty CacheFs prefix.
local workingNewFile = love.filesystem.newFile
local workingPrefix = CacheFs.prefix
CacheFs.prefix = "sentinel/"
love.filesystem.newFile = function(path)
  local file = workingNewFile(path)
  if path == "mods/stream_probe/baseroms/source.bin" then
    function file:write()
      error("forced writer failure")
    end
  end
  return file
end
importer.requiredImportNotice = nil
RequiredImports.LARGE_WARN_BYTES = 2
local failedWrite = importer:_importRequiredSource(
  "stream_probe", "source", source, true)
RequiredImports.LARGE_WARN_BYTES = oldWarn
T.eq(failedWrite, nil, "thrown streaming writer error is contained")
T.eq(CacheFs.prefix, "sentinel/",
  "streaming writer error restores CacheFs.prefix")
love.filesystem.newFile = workingNewFile
CacheFs.prefix = workingPrefix

-- acceptStoredDigest has its own prefix switch for marker/receipt I/O.
-- Even an unexpected CacheFs failure must restore the caller's prefix.
love.filesystem.write("mods/stream_probe/baseroms/source.bin", "abc")
local workingRemove = CacheFs.remove
CacheFs.prefix = "sentinel/"
CacheFs.remove = function()
  error("forced marker removal failure")
end
local accepted = RequiredImports.acceptStoredDigest(
  manifest, "source", "900150983cd24fb0d6963f7d28e17f72", love.filesystem)
T.eq(accepted, nil, "acceptStoredDigest contains CacheFs failure")
T.eq(CacheFs.prefix, "sentinel/",
  "acceptStoredDigest failure restores CacheFs.prefix")
CacheFs.remove = workingRemove
CacheFs.prefix = workingPrefix

-- Native sources are rejected cleanly if seek-to-start fails after the
-- size probe; never return a handle left sitting at EOF.
local realIoOpen = io.open
local fakeCloses = 0
io.open = function(path, mode)
  if path ~= source then return realIoOpen(path, mode) end
  local calls = 0
  return {
    seek = function(_, whence)
      calls = calls + 1
      if whence == "end" then return 3 end
      if whence == "set" then return nil, "forced rewind failure" end
      return nil, "unexpected seek"
    end,
    close = function() fakeCloses = fakeCloses + 1 end,
  }
end
importer.requiredImportNotice = nil
RequiredImports.LARGE_WARN_BYTES = 2
local failedSeek = importer:_importRequiredSource(
  "stream_probe", "source", source, true)
RequiredImports.LARGE_WARN_BYTES = oldWarn
io.open = realIoOpen
T.eq(failedSeek, nil, "failed native rewind rejects import source")
T.eq(fakeCloses >= 2, true,
  "failed native rewind closes probed source handles")

love.filesystem.remove("mods/stream_probe/baseroms/source.bin")
love.filesystem.remove("mods/stream_probe/baseroms/source.iso")
os.remove(source)
love.filesystem.newFile = oldNewFile
love.filesystem.getInfo = oldGetInfo

T.finish("required_import_streaming")
