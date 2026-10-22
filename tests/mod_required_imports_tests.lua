package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Manifest = require("src.mods.Manifest")
local RequiredImports = require("src.mods.RequiredImports")
local Loader = require("src.mods.Loader")
local S = require("tests.harness").suite("required mod imports")
local check, eq = S.check, S.eq

local DIGEST = "0123456789abcdef0123456789abcdef"
local function fakeHash(data)
  return data:sub(1, 4) == "\128\55\18\64" and DIGEST
    or "ffffffffffffffffffffffffffffffff"
end

local manifest = Manifest.validate({
  id = "stadium_fx", name = "Stadium FX", version = "1.0.0", entry = "main.lua",
  required_imports = {
    { id = "stadium2", name = "Stadium 2", file = "stadium2.z64",
      description = "USA dump", format = "n64", size = 8,
      md5 = { DIGEST, DIGEST:upper() } },
  },
}, "mods/stadium_fx")

eq(#manifest.required_imports, 1, "required import parses")
eq(#manifest.required_imports[1].md5, 1, "accepted MD5 values normalize and dedupe")
eq(manifest.required_imports[1].md5[1], DIGEST, "MD5 is lowercase")
eq(manifest.required_imports[1].description, "USA dump",
  "import description is preserved for the picker UI")
eq(manifest.required_imports[1].size, 8, "exact import size parses")

local optionalManifest = Manifest.validate({
  id = "optional_fx", name = "Optional FX", version = "1.0.0", entry = "main.lua",
  optional_imports = {
    { id = "bonus", name = "Bonus ROM", file = "bonus.z64",
      format = "n64", md5 = DIGEST },
  },
}, "mods/optional_fx")
eq(#optionalManifest.optional_imports, 1, "optional import parses")
eq(optionalManifest.optional_imports[1].required, false,
  "optional import is marked non-blocking")
local optionalRows, optionalMissing, missingOptional =
  RequiredImports.inspect(optionalManifest, love.filesystem, fakeHash)
eq(optionalMissing, 0, "missing optional import is not required")
eq(missingOptional, 1, "missing optional import is reported separately")
check(not optionalRows[1].required, "optional row is labeled optional")

check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  required_imports = { { id = "rom", file = "../outside.z64", md5 = DIGEST } },
}), "required import cannot escape baseroms")
check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  required_imports = { { id = "rom", file = "rom.z64", md5 = "short" } },
}), "malformed MD5 is refused")
check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  required_imports = { { id = "rom", file = ".rom.removed", md5 = DIGEST } },
}), "hidden import filenames cannot collide with engine metadata")
check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  required_imports = { { id = "rom", file = "rom.bin", md5 = DIGEST,
    max_size = RequiredImports.MAX_BYTES + 1 } },
}), "manifest import sizes cannot exceed the hard limit")

local canonical = "\128\55\18\64ABCD"
local v64 = "\55\128\64\18BADC"
local n64 = "\64\18\55\128DCBA"
check(RequiredImports.importData(optionalManifest, "bonus", canonical,
  { hash = fakeHash }), "optional import uses the normal validation path")
eq(RequiredImports.normalizeN64(canonical), canonical, "z64 stays canonical")
eq(RequiredImports.normalizeN64(v64), canonical, "v64 pair swap canonicalizes")
eq(RequiredImports.normalizeN64(n64), canonical, "n64 word swap canonicalizes")
eq(RequiredImports.normalizeN64(string.rep("H", 512) .. v64), canonical,
  "recognized 512-byte copier header is stripped")
check(RequiredImports.normalizeN64(string.rep("H", 520)) == nil,
  "an arbitrary 512-byte prefix is not treated as a copier header")

local ok, digest = RequiredImports.importData(manifest, "stadium2", v64,
  { hash = fakeHash })
check(ok, "validated bytes import")
eq(digest, DIGEST, "import reports canonical digest")
eq(love.filesystem.read("mods/stadium_fx/baseroms/stadium2.z64"), canonical,
  "import writes canonical bytes inside the mod")
local rows, missing = RequiredImports.inspect(manifest, love.filesystem, fakeHash)
eq(missing, 0, "written import satisfies its declaration")
check(rows[1].present, "inspection reports ready")

local target = Manifest.validate({
  id = "other_fx", name = "Other FX", version = "1.0.0", entry = "main.lua",
  required_imports = {
    { id = "same_rom", file = "source.z64", format = "n64", md5 = DIGEST },
  },
}, "mods/other_fx")
local targetRows, targetMissing = RequiredImports.inspect(target,
  love.filesystem, fakeHash)
eq(targetMissing, 1, "matching hashes do not silently share another mod's import")
check(not targetRows[1].present,
  "a mod needs its own explicit player-selected file")
check(RequiredImports.remove(target, "same_rom"), "a required import can be removed")
eq(love.filesystem.read("mods/other_fx/baseroms/source.z64"), nil,
  "remove deletes this mod's private copy")
check(RequiredImports.importData(target, "same_rom", canonical, { hash = fakeHash }),
  "choosing the file again clears the removal decision")

local legacy = Manifest.validate({
  id = "legacy", name = "Legacy", version = "1.0.0", entry = "main.lua",
}, "mods/legacy")
local legacyTarget = Manifest.validate({
  id = "legacy_user", name = "Legacy User", version = "1.0.0", entry = "main.lua",
  required_imports = {
    { id = "rom", file = "legacy-source.z64", format = "n64", md5 = DIGEST },
  },
}, "mods/legacy_user")
love.filesystem.write("mods/legacy/baseroms/manually-imported.v64", v64)
local legacyRows, legacyMissing = RequiredImports.inspect(legacyTarget,
  love.filesystem, fakeHash)
eq(legacyMissing, 1, "undeclared files in another mod are never indexed")
check(not legacyRows[1].present, "legacy baseroms remain private to their mod")

local capped = Manifest.validate({
  id = "capped", name = "Capped", version = "1.0.0", entry = "main.lua",
  required_imports = {
    { id = "small", file = "small.bin", md5 = DIGEST, max_size = 4 },
  },
}, "mods/capped")
local tooLarge, sizeWhy = RequiredImports.validateData(
  capped.required_imports[1], "12345", fakeHash)
eq(tooLarge, nil, "per-import size cap rejects before hashing")
check(tostring(sizeWhy):find("too large", 1, true) ~= nil,
  "size rejection explains the limit")

-- A successful validation writes an engine receipt. Matching size + modtime
-- lets later launcher refreshes avoid reading and hashing the ROM again.
local cacheFiles = {
  ["mods/cache/baseroms/source.z64"] = canonical,
}
local dataReads = 0
local cacheModtime = 123
local cacheFs = {
  getInfo = function(path, kind)
    local data = cacheFiles[path]
    if data then return { type = "file", size = #data, modtime = cacheModtime } end
    return nil
  end,
  read = function(path)
    if path == "mods/cache/baseroms/source.z64" then dataReads = dataReads + 1 end
    return cacheFiles[path]
  end,
  write = function(path, data) cacheFiles[path] = data return true end,
  remove = function(path) cacheFiles[path] = nil return true end,
}
local cacheManifest = Manifest.validate({
  id = "cache", name = "Cache", version = "1.0.0", entry = "main.lua",
  required_imports = {
    { id = "source", file = "source.z64", format = "n64", size = 8,
      md5 = DIGEST },
  },
}, "mods/cache")
local cacheRows = RequiredImports.inspect(cacheManifest, cacheFs, fakeHash)
check(cacheRows[1].present, "initial cached import validation succeeds")
cacheRows = RequiredImports.inspect(cacheManifest, cacheFs, function()
  error("unchanged cached import should not be hashed again")
end)
check(cacheRows[1].present, "validation receipt satisfies the next refresh")
eq(dataReads, 1, "unchanged imported ROM is read only once")
cacheFiles["mods/cache/baseroms/source.z64"] = "BADBYTES"
cacheModtime = 124
cacheRows = RequiredImports.inspect(cacheManifest, cacheFs, fakeHash)
check(not cacheRows[1].present, "changed imported ROM bypasses a stale receipt")
eq(dataReads, 2, "changed imported ROM is read again")
eq(cacheFiles[RequiredImports.receiptPath(cacheManifest, cacheManifest.required_imports[1])],
  nil, "stale validation receipt is removed")

local rejected, why = RequiredImports.importData(target, "same_rom", "wrong",
  { hash = fakeHash })
eq(rejected, nil, "mismatched selection is rejected")
check(tostring(why):find("N64 ROM (.z64/.v64/.n64)", 1, true) ~= nil,
  "normalization failure explains the selected format")

love.filesystem.write("mods/launcher_needs/manifest.json", ([[{
  "id":"launcher_needs","name":"Launcher Needs","version":"1.0.0",
  "entry":"main.lua","required_imports":[{"id":"source","name":"Source ROM",
  "file":"source.bin","md5":"%s"}]
}]]):format(DIGEST))
love.filesystem.write("mods/launcher_needs/main.lua", "return function(mod) end")
local launcherRows = require("src.mods.LauncherMods").list()
eq(#launcherRows, 1, "launcher keeps a mod with a missing required import visible")
eq(launcherRows[1].missingRequiredImports, 1,
  "launcher row carries the missing import count")
eq(launcherRows[1].status, "needs_import",
  "missing import changes Ready to Import required")
check(launcherRows[1].statusDetail:find("Source ROM", 1, true) ~= nil,
  "launcher warning names the missing file")

local function memfs(files)
  return {
    read = function(path) return files[path] end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
    end,
    getDirectoryItems = function(path)
      if path == "mods" then
        local out, seen = {}, {}
        for key in pairs(files) do
          local id = key:match("^mods/([^/]+)/manifest%.json$")
          if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
        table.sort(out)
        return out
      end
      return {}
    end,
    load = function(path)
      local source = files[path]
      if not source then return nil, "missing" end
      return load(source, path)
    end,
  }
end

local manifestJson = ([[{
  "id":"needs_rom","name":"Needs ROM","version":"1.0.0","entry":"main.lua",
  "required_imports":[{"id":"rom","name":"Source ROM","file":"source.bin",
  "md5":"%s"}]
}]]):format(DIGEST)
local loader = Loader.new({ fs = memfs({
  ["mods/needs_rom/manifest.json"] = manifestJson,
  ["mods/needs_rom/main.lua"] = "return function(mod) mod.exports.ran = true end",
}) })
check(loader:load({}) == false, "missing required import blocks the enabled mod")
local status = loader:status().available[1]
eq(status.state, "invalid", "blocked mod reports invalid")
check(status.error:find("Source ROM", 1, true) ~= nil,
  "loader failure names the required import")
check(not (loader.exports.needs_rom and loader.exports.needs_rom.ran),
  "blocked mod entry never executes")

local optionalJson = ([[{
  "id":"optional_rom","name":"Optional ROM","version":"1.0.0","entry":"main.lua",
  "optional_imports":[{"id":"rom","name":"Bonus ROM","file":"bonus.bin",
  "md5":"%s"}]
}]]):format(DIGEST)
local optionalLoader = Loader.new({ fs = memfs({
  ["mods/optional_rom/manifest.json"] = optionalJson,
  ["mods/optional_rom/main.lua"] = "return function(mod) mod.exports.ran = true end",
}) })
check(optionalLoader:load({}), "missing optional import does not block the mod")
check(optionalLoader.exports.optional_rom.ran,
  "mod entry executes without its optional import")

-- verify = "mod": the mod checks the content, so md5 is optional and any
-- digest is accepted; the engine never hashes the stored file.
local modVerified = Manifest.validate({
  id = "any_dump", name = "Any Dump", version = "1.0.0", entry = "main.lua",
  optional_imports = {
    { id = "image", name = "Card image", file = "image.cci", verify = "mod",
      extensions = { ".CCI", ".3ds" }, max_size = 64 },
  },
}, "mods/any_dump")
local mvSpec = modVerified.optional_imports[1]
eq(mvSpec.verify, "mod", "verify = mod parses")
eq(#mvSpec.md5, 0, "a mod-verified import needs no md5")
eq(mvSpec.extensions[1], ".cci", "extensions are lowercased")
check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  optional_imports = { { id = "rom", file = "rom.bin" } },
}), "md5 is still required without verify = mod")
check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  optional_imports = { { id = "rom", file = "rom.bin", verify = "engine" } },
}), "an unknown verify value is refused")
check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  optional_imports = { { id = "rom", file = "rom.bin", md5 = DIGEST,
    extensions = { "cci" } } },
}), "an extension without its dot is refused")
check(not pcall(Manifest.validate, {
  id = "bad", name = "Bad", version = "1", entry = "main.lua",
  optional_imports = { { id = "rom", file = "rom.bin", md5 = DIGEST,
    extensions = { ".c'i" } } },
}), "an extension with punctuation is refused")

eq(RequiredImports.extensionError(mvSpec, "C:/dumps/Alpha Sapphire.CCI"), nil,
  "a declared extension is accepted, case-insensitively")
eq(RequiredImports.extensionError(mvSpec, "/home/p/as.3ds"), nil,
  "every declared extension is accepted")
check(RequiredImports.extensionError(mvSpec, "as.zip"):find(".zip", 1, true) ~= nil,
  "another extension is refused and named")
check(RequiredImports.extensionError(mvSpec, "noext") ~= nil,
  "a name without an extension is refused")
eq(RequiredImports.extensionError(manifest.required_imports[1], "x.zip"), nil,
  "an import without extensions takes any name")

local mvFiles = { ["mods/any_dump/baseroms/image.cci"] = "ANYBYTES" }
local mvFs = {
  getInfo = function(path)
    local data = mvFiles[path]
    if data then return { type = "file", size = #data, modtime = 1 } end
  end,
  read = function(path) return mvFiles[path] end,
  write = function(path, data) mvFiles[path] = data return true end,
  remove = function(path) mvFiles[path] = nil return true end,
}
local mvRows = RequiredImports.inspect(modVerified, mvFs, function()
  error("a mod-verified import is never hashed")
end)
check(mvRows[1].present, "a mod-verified import is present without a digest")
local accepted = RequiredImports.acceptStoredDigest(modVerified, "image", nil, mvFs)
check(accepted, "a streamed mod-verified copy is accepted without a digest")
eq(mvFiles[RequiredImports.receiptPath(modVerified, mvSpec)], nil,
  "no md5 receipt is written for a mod-verified import")
mvFiles["mods/any_dump/baseroms/image.cci"] = string.rep("x", 65)
mvRows = RequiredImports.inspect(modVerified, mvFs)
check(not mvRows[1].present, "max_size still applies to a mod-verified import")

local listed = Manifest.validate({
  id = "listed", name = "Listed", version = "1.0.0", entry = "main.lua",
  optional_imports = {
    { id = "image", file = "image.cci", verify = "mod", md5 = DIGEST },
  },
}, "mods/listed")
check(RequiredImports.importData(listed, "image", "OTHERBYTES",
  { hash = fakeHash }), "a listed md5 does not narrow a mod-verified import")

S.finish()
