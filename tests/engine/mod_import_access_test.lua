-- Public mod-API coverage for bounded validated imports + installation cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local digest = "00000000000000000000000000000000"
local files = {
  ["mods/import_api_probe/manifest.json"] = [[{
    "id": "import_api_probe",
    "name": "Import API Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "required_imports": [{
      "id": "disc",
      "name": "Disc",
      "file": "source.iso",
      "md5": ["00000000000000000000000000000000"],
      "size": 16
    }],
    "optional_imports": [{
      "id": "optional",
      "name": "Optional",
      "file": "optional.bin",
      "md5": ["11111111111111111111111111111111"],
      "size": 4,
      "required": false
    }]
  }]],
  ["mods/import_api_probe/main.lua"] = [[
    local mod = ...
    local info, infoErr = mod.imports:info("disc")
    local slice, sliceErr = mod.imports:read("disc", 4, 6)
    local oob, oobErr = mod.imports:read("disc", 15, 2)
    local missing, missingErr = mod.imports:info("optional")
    local undeclared, undeclaredErr = mod.imports:read("not_declared", 0, 1)

    local wrote, writeErr = mod.cache:write("extract/v1/probe.bin", "abc")
    local cached, readErr = mod.cache:read("extract/v1/probe.bin")
    local cacheInfo = mod.cache:info("extract/v1/probe.bin")
    local escaped = pcall(function() mod.cache:write("../escape.bin", "x") end)

    mod.exports.result = {
      info = info, infoErr = infoErr,
      slice = slice, sliceErr = sliceErr,
      oob = oob, oobErr = oobErr,
      missing = missing, missingErr = missingErr,
      undeclared = undeclared, undeclaredErr = undeclaredErr,
      wrote = wrote, writeErr = writeErr,
      cached = cached, readErr = readErr,
      cacheInfo = cacheInfo,
      escaped = escaped,
    }
  ]],
  ["mods/import_api_probe/baseroms/source.iso"] = "0123456789abcdef",
  ["mods/import_api_probe/baseroms/.required-import-disc.validated"] =
    "v1\n" .. digest .. "\n16\n1\n",
}

local baseFs = T.sdk.memfs(files)
local oldInfo = baseFs.getInfo
function baseFs.getInfo(path)
  local info = oldInfo(path)
  if info and info.type == "file" then
    return { type = "file", size = #(files[path] or ""), modtime = 1 }
  end
  return info
end
function baseFs.readRange(path, offset, length)
  local body = files[path]
  if not body then return nil end
  return body:sub(offset + 1, offset + length)
end
function baseFs.createDirectory() return true end
function baseFs.remove(path) files[path] = nil return true end

local run = T.sdk.loadMods({ "mods/import_api_probe" }, { fs = baseFs })
T.eq(#run.errors, 0,
  "the import/cache probe loads through the production Loader")

local out = run.loader.exports.import_api_probe.result
T.check(type(out.info) == "table", "declared validated import has info")
T.eq(out.info.size, 16, "import info reports stored size")
T.eq(out.slice, "456789", "bounded read seeks into the validated import")
T.eq(out.sliceErr, nil, "bounded read has no error")
T.eq(out.oob, nil, "out-of-bounds read is refused")
T.check(type(out.oobErr) == "string" and out.oobErr:find("out of bounds", 1, true),
  "out-of-bounds read explains the refusal")
T.eq(out.missing, nil, "missing optional import is not exposed")
T.check(type(out.missingErr) == "string", "missing optional import returns an error")
T.eq(out.undeclared, nil, "undeclared import id is refused")
T.check(type(out.undeclaredErr) == "string"
    and out.undeclaredErr:find("undeclared", 1, true),
  "undeclared import refusal is explicit")

T.check(out.wrote == true, "installation cache write succeeds")
T.eq(out.cached, "abc", "installation cache read returns exact bytes")
T.eq(out.cacheInfo and out.cacheInfo.size, 3, "installation cache info is scoped")
T.eq(out.escaped, false, "cache traversal is rejected by the public facade")
T.eq(files["mod_cache/import_api_probe/extract/v1/probe.bin"], "abc",
  "cache bytes live under the calling mod id")
T.eq(files["escape.bin"], nil, "cache traversal created nothing outside its root")

run.release()
T.finish("mod_import_access")
