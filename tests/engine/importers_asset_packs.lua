package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Importers = require("src.import.Importers")
local Manifest = require("src.mods.Manifest")
local LuaWriter = require("src.import.LuaWriter")

for _, desc in ipairs(Importers.all()) do
  local ok, err = Importers.validateDescriptor(desc)
  T.check(ok, "shipped importer " .. tostring(desc.id) .. " validates: "
    .. tostring(err))
end

local lttp = Importers.get("lttp")
T.check(lttp ~= nil, "A Link to the Past is registered")
T.eq(lttp.status, "beta", "and its graphics side is runnable")
T.check(Importers.pack("lttp", "sprites") ~= nil, "it exports a sprite pack")
T.check(Importers.pack("lttp", "sfx").planned,
  "its audio packs are still declared but not produced")
T.check(not Importers.pack("lttp", "palettes").planned,
  "while the palette pack is real")

T.eq(Importers.packRoot("lttp", "sprites"), "asset_packs/lttp/sprites",
  "packs live under their own root, clear of the NX imports/ inbox")

local function packManifest(overrides)
  local out = {
    format = Importers.PACK_FORMAT,
    importer = "lttp",
    pack = "sprites",
    kind = "sprite",
    version = "1.2.0",
    source = { name = "A Link to the Past (USA)",
      md5 = "777aac2f7b26c0b0d67d2b1bf5d4ecb0", size = 1048576 },
    entries = {
      ["link/walk_down"] = { file = "link/walk_down.png", size = 4,
        width = 16, height = 24, frames = 4 },
    },
  }
  for key, value in pairs(overrides or {}) do out[key] = value end
  return out
end

do
  local ok = Importers.validatePack(packManifest(), "lttp", "sprites")
  T.check(ok, "a well-formed pack manifest validates")

  local badKind = packManifest({ kind = "voxels" })
  T.check(not Importers.validatePack(badKind), "an unknown asset kind is refused")

  local badExt = packManifest({ entries = {
    ["link/walk_down"] = { file = "link/walk_down.exe", size = 4 } } })
  T.check(not Importers.validatePack(badExt),
    "a sprite pack refuses a file that is not an image")

  local badVersion = packManifest({ version = "one" })
  T.check(not Importers.validatePack(badVersion), "pack versions must be semver")

  local escape = packManifest({ entries = {
    ["link/walk_down"] = { file = "../../escape.png", size = 4 } } })
  T.check(not Importers.validatePack(escape), "a pack entry cannot climb out")

  local wrongPack = Importers.validatePack(packManifest(), "lttp", "tiles")
  T.check(not wrongPack, "a manifest cannot claim a pack it was not written for")
end

local files = {
  ["mods/pack_probe/manifest.json"] = [[{
    "id": "pack_probe",
    "name": "Pack Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "required_assets": [{ "importer": "lttp", "pack": "sprites",
      "version": ">=1.0.0" }],
    "optional_assets": [{ "importer": "lttp", "pack": "music" }]
  }]],
  ["mods/pack_probe/main.lua"] = [[
    local mod = ...
    local info, infoErr = mod.packs:info("lttp", "sprites")
    local entries = mod.packs:entries("lttp", "sprites")
    local bytes, bytesErr = mod.packs:read("lttp", "sprites", "link/walk_down")
    local missing, missingErr = mod.packs:info("lttp", "music")
    local undeclared, undeclaredErr = mod.packs:read("lttp", "tiles", "x")
    mod.exports.result = {
      info = info, infoErr = infoErr,
      entries = entries,
      bytes = bytes, bytesErr = bytesErr,
      missing = missing, missingErr = missingErr,
      undeclared = undeclared, undeclaredErr = undeclaredErr,
      list = mod.packs:list(),
    }
  ]],
  ["asset_packs/lttp/sprites/pack.lua"] = LuaWriter.encode(packManifest()),
  ["asset_packs/lttp/sprites/link/walk_down.png"] = "PNG!",
}

do
  local base = { id = "pack_probe", name = "Pack Probe", version = "1.0.0",
    entry = "main.lua", api = 2 }
  local function withAssets(required, optional)
    local raw = {}
    for k, v in pairs(base) do raw[k] = v end
    raw.required_assets, raw.optional_assets = required, optional
    return raw
  end

  local parsed = Manifest.validate(withAssets(
    { { importer = "lttp", pack = "sprites", version = ">=1.0.0" } },
    { { importer = "lttp", pack = "music" } }), "mods/pack_probe")
  T.eq(#parsed.required_assets, 1, "the manifest declares one required pack")
  T.eq(parsed.required_assets[1].version, ">=1.0.0", "with its semver range")
  T.eq(parsed.optional_assets[1].required, false, "and one optional pack")

  T.check(not pcall(Manifest.validate, withAssets(
    { { importer = "lttp", pack = "sprites" } },
    { { importer = "lttp", pack = "sprites" } }), "mods/d"),
    "the same pack cannot be both required and optional")

  T.check(not pcall(Manifest.validate, withAssets(
    { { importer = "lttp", pack = "sprites", version = "wat" } }), "mods/b"),
    "a malformed version range is refused at parse time")

  T.check(not pcall(Manifest.validate, withAssets(
    { { importer = "LTTP", pack = "sprites" } }), "mods/c"),
    "importer ids stay lowercase")
end

local fs = T.sdk.memfs(files)

do
  local roundtrip = Importers.readPack("lttp", "sprites", fs)
  T.check(roundtrip ~= nil, "an installed pack reads back")
  T.eq(roundtrip and roundtrip.version, "1.2.0", "with its export version")
  T.eq(Importers.installed("lttp", fs).sprites.entries, 1,
    "and is reported as installed with its entry count")
  T.eq(Importers.state("lttp", fs), "partial",
    "one installed pack of three reads as partial")

  local resolved, err = Importers.resolve(
    { importer = "lttp", pack = "sprites", version = ">=2.0.0" }, fs)
  T.eq(resolved, nil, "a range the installed pack misses does not resolve")
  T.check(type(err) == "string" and err:find("1.2.0", 1, true),
    "and the refusal names the version that is installed")
end

do
  local run = T.sdk.loadMods({ "mods/pack_probe" }, { fs = fs })
  T.eq(#run.errors, 0, "a mod whose required pack is installed loads")
  local out = run.loader.exports.pack_probe.result
  T.eq(out.info and out.info.kind, "sprite", "mod.packs:info reports the kind")
  T.eq(out.info and out.info.entries, 1, "and the entry count")
  T.eq(#out.entries, 1, "mod.packs:entries lists the pack")
  T.eq(out.entries[1].width, 16, "with the metadata the importer recorded")
  T.eq(out.bytes, "PNG!", "mod.packs:read returns the exported bytes")
  T.eq(out.missing, nil, "an optional pack that is not installed is not exposed")
  T.check(type(out.missingErr) == "string", "and says so")
  T.eq(out.undeclared, nil, "an undeclared pack is refused")
  T.check(type(out.undeclaredErr) == "string"
      and out.undeclaredErr:find("undeclared", 1, true),
    "with an explicit refusal")
  T.eq(#out.list, 2, "mod.packs:list answers for every declared pack")
  run.release()
end

do
  local gated = {}
  for key, value in pairs(files) do gated[key] = value end
  gated["asset_packs/lttp/sprites/pack.lua"] = nil
  local run = T.sdk.loadMods({ "mods/pack_probe" },
    { fs = T.sdk.memfs(gated) })
  local mod = run.loader.mods.pack_probe
  T.eq(mod and mod.state, "invalid",
    "a mod whose required pack is missing is gated, not half-loaded")
  T.check(mod and type(mod.failure) == "string"
      and mod.failure:find("IMPORTERS", 1, true),
    "and the reason points at the tab that would fix it")
  T.eq(run.loader.exports.pack_probe, nil, "its entry chunk never ran")
  run.release()
end

do
  local out = {}
  local memfs = T.sdk.memfs(out)
  local ok = Importers.writePack("lttp", "sprites", packManifest(), memfs)
  T.check(ok, "an importer can write a pack manifest through the contract")
  T.check(out["asset_packs/lttp/sprites/pack.lua"] ~= nil,
    "at the path the readers look in")
  local bad, reason = Importers.writePack("lttp", "sprites",
    packManifest({ kind = "voxels" }), memfs)
  T.eq(bad, nil, "an invalid manifest is never written")
  T.check(type(reason) == "string", "and the writer says why")
end

T.finish("importers_asset_packs")
