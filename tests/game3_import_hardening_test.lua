#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function contains(haystack, needle, msg)
  check(type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil,
    msg .. " (" .. tostring(haystack) .. ")")
end

print("[test] 1. refused sprite write stops PokemonExtract.run")
local PokemonExtract = require("src.import.gba.pokemon_extract")

local zeroRom = {}
function zeroRom:get() return 0 end
function zeroRom:u16() return 0 end
function zeroRom:u32() return 0 end
function zeroRom:readBytes(_, len)
  local t = {}
  for i = 1, (len or 0) do t[i] = 0 end
  return t
end
function zeroRom:clearCache() end

local refused = {}
local refusingCache = {
  write = function(_, rel)
    if rel:find("/icons/", 1, true) then
      refused[#refused + 1] = rel
      return false, "disk full"
    end
    return true
  end,
  read = function() return nil end,
  exists = function() return false end,
}

local ok, err = pcall(PokemonExtract.run, zeroRom, refusingCache, {
  cacheRoot = "data/generated/gba",
  numSpecies = 1,
})
check(ok == false, "PokemonExtract.run raises instead of returning")
contains(tostring(err), "could not write", "the error names the refused write")
contains(tostring(err), "icons/0.rgba", "the error names the file")
check(#refused == 1, "the refusal happened on the first species (" .. #refused .. ")")

local pointerRom = {}
function pointerRom:get() return 0 end
function pointerRom:u16() return 0 end
function pointerRom:u32() return 0x08000100 end
function pointerRom:ptrOffset(p) return p - 0x08000000 end
function pointerRom:readBytes(_, len)
  local t = {}
  for i = 1, (len or 0) do t[i] = 0 end
  return t
end
function pointerRom:clearCache() end

local written = 0
local acceptingCache = {
  write = function() written = written + 1; return true end,
  read = function() return nil end,
  exists = function() return false end,
}
local picsOk, picsErr = pcall(PokemonExtract.run, pointerRom, acceptingCache, {
  cacheRoot = "data/generated/gba",
  numSpecies = 1,
})
check(picsOk == false, "a species whose pic never decodes stops PokemonExtract.run")
contains(tostring(picsErr), "produced no file",
  "the error names the species with a valid pointer and no sprite")
contains(tostring(picsErr), "front/0", "the error lists the missing front sprite")

print("[test] 2. RomExtractorGen3 stage gating")
local Json = require("src.link.Json")
local SHA1 = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"

local function loadExtractorWithStubs(pokeRun, sectionsRun)
  for name in pairs(package.loaded) do
    if name:find("src.import.RomExtractorGen3", 1, true) then
      package.loaded[name] = nil
    end
  end
  local files = {}
  local seenImports = {}
  package.loaded["src.import.CacheFs"] = {
    prefix = "",
    write = function(rel, data) files[rel] = data; return true end,
    read = function(rel) return files[rel] end,
    exists = function(rel) return files[rel] ~= nil end,
    remove = function(rel) files[rel] = nil; return true end,
  }
  package.loaded["src.import.LuaWriter"] = {
    write = function(rel) files[rel] = "return {}"; return true end,
  }
  package.loaded["src.import.gba.extract_island1"] = {
    CACHE_ROOT = "data/generated/gba",
    NATIVE_ROOT = "data/generated/gba/native",
    STAGE_COUNT = 7,
    run = function() return true, { stub = true } end,
  }
  package.loaded["src.import.gba.rom"] = {
    open = function(imports)
      seenImports[#seenImports + 1] = imports
      return { clearCache = function() end }
    end,
  }
  package.loaded["src.import.gba.pokemon_extract"] = {
    ready = function() return false end,
    run = pokeRun,
  }
  for _, sibling in ipairs({
    "items_extract", "pokedex_chrome_extract", "storage_chrome_extract",
    "text_chrome_extract", "trainer_card_extract", "seagallop_extract",
    "cave_transition_extract", "ingame_trades_extract", "union_room_classes_extract",
    "map_preview_extract",
  }) do
    package.loaded["src.import.gba." .. sibling] = { run = function() return true end }
  end
  package.loaded["src.import.gba.region_map_extract"] = {
    ready = function() return true end,
    run = function() return {} end,
  }
  package.loaded["src.import.gba.multichoice_extract"] = {
    ready = function() return true end,
    run = function() return {} end,
  }
  for _, sibling in ipairs({ "credits_extract", "league_extract", "battle_ai_extract" }) do
    package.loaded["src.import.gba." .. sibling] = {
      ready = function() return true end,
      run = function() return {} end,
    }
  end
  package.loaded["src.import.gba.map_sections_extract"] = {
    run = sectionsRun or function(_, cache, opts)
      cache:write((opts and opts.cacheRoot or "data/generated/gba")
        .. "/region_map/map_sections.lua", string.rep("-", 2048))
      return true
    end,
  }
  package.loaded["src.import.gba.revision_view"] = {
    forImports = function(imports)
      seenImports[#seenImports + 1] = imports
      return nil
    end,
    apply = function(data) return data end,
  }
  package.loaded["src.import.gba.extract_intro"] = { run = function() return true, {} end }
  package.loaded["src.import.gba.extract_naming"] = { run = function() return true end }
  package.loaded["src.import.gba.extract_audio"] = { run = function() return true, {} end }
  local Extractor = require("src.import.RomExtractorGen3")
  return Extractor.new("ROM", {}, nil, SHA1), files, seenImports
end

local STATUS = "data/generated/gba/pokemon/extract_status.json"

local throwing, throwFiles = loadExtractorWithStubs(function()
  error("species sprite pass refused a write")
end)
local runOk, runErr = pcall(throwing.run, throwing)
check(runOk == false, "a throwing PokemonExtract fails the import")
contains(tostring(runErr), "Pokemon extract failed", "the import error names the stage")
local throwStatus = throwFiles[STATUS] and Json.decode(throwFiles[STATUS])
check(throwStatus ~= nil, "pokemon/extract_status.json was written")
check(throwStatus and throwStatus.ok == false, "the failed status says ok = false")
contains(throwStatus and tostring(throwStatus.error), "refused a write",
  "the failed status carries the real error")

local passing, passFiles, passImports = loadExtractorWithStubs(function()
  return { root = "data/generated/gba/pokemon", picsWritten = { icons = 412 } }
end)
local passOk, passErr = pcall(passing.run, passing)
check(passOk == true, "a successful PokemonExtract completes the import (" .. tostring(passErr) .. ")")
local passStatus = passFiles[STATUS] and Json.decode(passFiles[STATUS])
check(passStatus ~= nil, "pokemon/extract_status.json was written on success")
check(passStatus and passStatus.ok == true, "the successful status says ok = true")
check(passStatus and passStatus.error == nil,
  "a successful stage records no error (" .. tostring(passStatus and passStatus.error) .. ")")

local AUX_STATUS = "data/generated/gba/region_map/extract_status.json"
local silent, silentFiles = loadExtractorWithStubs(function()
  return { root = "data/generated/gba/pokemon", picsWritten = { icons = 412 } }
end, function() return true end)
local silentOk, silentErr = pcall(silent.run, silent)
check(silentOk == false, "a map_sections pass that writes nothing fails the import")
contains(tostring(silentErr), "map_sections extract wrote 0 bytes",
  "the import error names the empty mapsec write")
local auxStatus = silentFiles[AUX_STATUS] and Json.decode(silentFiles[AUX_STATUS])
check(auxStatus and auxStatus.ok == false, "region_map/extract_status.json says ok = false")

print("[test] 3. shared imports object")
check(#passImports >= 3, "the run opened the ROM for at least 3 stages (" .. #passImports .. ")")
local sameTable = true
for i = 2, #passImports do
  if passImports[i] ~= passImports[1] then sameTable = false end
end
check(sameTable, "every stage got the same imports table, so one revision view is built")

local shared = loadExtractorWithStubs(function() return {} end)
local a = shared:sharedImports(SHA1)
local b = shared:sharedImports(SHA1)
check(a == b, "sharedImports returns the same table on every stage")

package.loaded["src.import.CacheFs"] = nil
package.loaded["src.import.LuaWriter"] = nil
package.loaded["src.import.gba.extract_island1"] = nil
package.loaded["src.import.gba.rom"] = nil
package.loaded["src.import.gba.pokemon_extract"] = nil
package.loaded["src.import.gba.region_map_extract"] = nil
package.loaded["src.import.gba.multichoice_extract"] = nil
package.loaded["src.import.gba.credits_extract"] = nil
package.loaded["src.import.gba.league_extract"] = nil
package.loaded["src.import.gba.battle_ai_extract"] = nil
package.loaded["src.import.gba.map_sections_extract"] = nil
package.loaded["src.import.gba.revision_view"] = nil
package.loaded["src.import.gba.extract_intro"] = nil
package.loaded["src.import.gba.extract_naming"] = nil
package.loaded["src.import.gba.extract_audio"] = nil
package.loaded["src.import.RomExtractorGen3"] = nil
for _, sibling in ipairs({
  "items_extract", "pokedex_chrome_extract", "storage_chrome_extract",
  "text_chrome_extract", "trainer_card_extract", "seagallop_extract",
  "cave_transition_extract", "ingame_trades_extract", "union_room_classes_extract",
  "map_preview_extract",
}) do
  package.loaded["src.import.gba." .. sibling] = nil
end

print("[test] 4. firered required files")
local CacheContract = require("src.import.CacheContract")
local required = {}
for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.firered) do
  required[path] = true
end
for _, path in ipairs({
  "data/generated/gba/pokemon/front/1.rgba",
  "data/generated/gba/pokemon/front/200.rgba",
  "data/generated/gba/pokemon/front/411.rgba",
  "data/generated/gba/pokemon/back/1.rgba",
  "data/generated/gba/pokemon/back/200.rgba",
  "data/generated/gba/pokemon/back/411.rgba",
  "data/generated/gba/pokemon/icons/1.rgba",
  "data/generated/gba/pokemon/icons/200.rgba",
  "data/generated/gba/pokemon/icons/411.rgba",
  "data/generated/gba/region_map/kanto_map.png",
  "data/generated/gba/region_map/cursor.png",
  "data/generated/gba/region_map/player_red.png",
  "data/generated/gba/region_map/map_sections.lua",
  "data/generated/gba/scripts/multichoice.lua",
}) do
  check(required[path] == true, "required: " .. path)
end

local fakeFs = { prefix = "" }
local present = {}
for path in pairs(required) do present[path] = true end
function fakeFs.exists(rel) return present[rel] == true end
local complete = CacheContract.allRequiredFilesExist("firered", fakeFs)
check(complete == true, "a cache holding every required file is complete")
present["data/generated/gba/pokemon/front/411.rgba"] = nil
local incomplete, missing = CacheContract.allRequiredFilesExist("firered", fakeFs)
check(incomplete == false, "a cache without the last species front sprite is incomplete")
check(missing == "data/generated/gba/pokemon/front/411.rgba",
  "the contract names the missing sprite (" .. tostring(missing) .. ")")

local GbaVersions = require("src.import.gba.versions")
local META = "data/generated/gba/meta.json"
present["data/generated/gba/pokemon/front/411.rgba"] = true
local stamp = tostring(GbaVersions.CACHE_VERSION)
local stampFs = { prefix = "" }
function stampFs.exists(rel) return present[rel] == true end
function stampFs.read(rel)
  if rel == CacheContract.MARKER_PATH then return CacheContract.markerFor("firered") end
  if rel == META then
    return '{"md5":"x","cache_version":' .. stamp .. ',"native_version":6}'
  end
  return nil
end
check(CacheContract.isReady("firered", stampFs) == true,
  "a complete cache stamped at the current CACHE_VERSION is ready")
stamp = tostring(GbaVersions.CACHE_VERSION - 1)
check(CacheContract.isReady("firered", stampFs) == false,
  "a complete cache stamped at an older CACHE_VERSION is not ready, so it re-imports")
stamp = tostring(GbaVersions.CACHE_VERSION)

print("[test] 5. PokemonExtract.ready")
local Versions = require("src.import.gba.versions")
local last = (Versions.NUM_SPECIES or 412) - 1
local iconBytes = (Versions.MON_ICON_W or 32) * (Versions.MON_ICON_H or 32) * 2 * 4
local ROOT = "data/generated/gba"
local function readyCacheWith(skip, format, numSpecies)
  local manifest = string.format(
    "return { magic = \"SVPK\", format = %d, numSpecies = %d }%s\n",
    format or PokemonExtract.FORMAT_VERSION,
    numSpecies or Versions.NUM_SPECIES or 412,
    string.rep(" ", 40))
  local sizes = {
    [ROOT .. "/pokemon/manifest.lua"] = 64,
    [ROOT .. "/pokemon/names.lua"] = 64,
    [ROOT .. "/pokemon/stats.lua"] = 64,
    [ROOT .. "/pokemon/learnsets.lua"] = 64,
    [ROOT .. "/pokemon/egg_moves.lua"] = 64,
    [ROOT .. "/pokemon/move_names.lua"] = 64,
    [ROOT .. "/pokemon/party/slot_main.rgba"] = 80 * 56 * 4,
    [ROOT .. "/pokemon/summary/page_info.rgba"] = 240 * 160 * 4,
    [ROOT .. "/pokemon/storage/manifest.lua"] = 64,
    [ROOT .. "/chrome/menu_message_rgba.rgba"] = 64,
    [ROOT .. "/trainer_card/bg.rgba"] = 240 * 160 * 4,
    [ROOT .. "/items/pack.lua"] = 64,
    [ROOT .. "/pokemon/front/1.rgba"] = 64 * 64 * 4,
    [ROOT .. "/pokemon/back/1.rgba"] = 64 * 64 * 4,
    [ROOT .. "/pokemon/icons/1.rgba"] = iconBytes,
    [ROOT .. "/pokemon/front/" .. last .. ".rgba"] = 64 * 64 * 4,
    [ROOT .. "/pokemon/back/" .. last .. ".rgba"] = 64 * 64 * 4,
    [ROOT .. "/pokemon/icons/" .. last .. ".rgba"] = iconBytes,
    [ROOT .. "/chrome/fonts/braille.lua"] = 64,
    [ROOT .. "/seagallop/manifest.lua"] = 64,
    [ROOT .. "/seagallop/wb.rgba"] = 32 * 8 * 32 * 8 * 4,
    [ROOT .. "/pokemon/pokedex/paper_bg.rgba"] = 240 * 160 * 4,
    [ROOT .. "/pokemon/pokedex/footprints/1.rgba"] = 16 * 16 * 4,
    [ROOT .. "/pokemon/pokedex/footprints/question_mark.rgba"] = 16 * 16 * 4,
    [ROOT .. "/pokemon/battle/terrain_cave.rgba"] = 256 * 256 * 4,
    [ROOT .. "/pokemon/battle/terrain_water.rgba"] = 256 * 256 * 4,
    [ROOT .. "/pokemon/battle/terrain_champion.rgba"] = 256 * 256 * 4,
  }
  if skip then sizes[skip] = nil end
  return {
    read = function(_, rel)
      local n = sizes[rel]
      if not n then return nil end
      if rel == ROOT .. "/pokemon/manifest.lua" then return manifest end
      return string.rep("x", n)
    end,
  }
end
check(PokemonExtract.ready(readyCacheWith(nil), ROOT) == true,
  "a complete species cache is ready")
check(PokemonExtract.ready(readyCacheWith(ROOT .. "/pokemon/icons/1.rgba"), ROOT) == false,
  "a cache with no first-species icon is not ready")
check(PokemonExtract.ready(readyCacheWith(ROOT .. "/pokemon/front/" .. last .. ".rgba"), ROOT) == false,
  "a cache with no last-species front sprite is not ready")
check(PokemonExtract.ready(readyCacheWith(ROOT .. "/pokemon/icons/" .. last .. ".rgba"), ROOT) == false,
  "a cache with no last-species icon is not ready")
check(PokemonExtract.ready(readyCacheWith(nil, PokemonExtract.FORMAT_VERSION - 1), ROOT) == false,
  "a cache written by an older species format is not ready")
check(PokemonExtract.ready(readyCacheWith(nil, nil, 1), ROOT) == false,
  "a cache whose manifest counts fewer species than the ROM is not ready")

local siblings = {
  ROOT .. "/chrome/fonts/braille.lua",
  ROOT .. "/seagallop/manifest.lua",
  ROOT .. "/seagallop/wb.rgba",
  ROOT .. "/pokemon/pokedex/paper_bg.rgba",
  ROOT .. "/pokemon/pokedex/footprints/1.rgba",
  ROOT .. "/pokemon/pokedex/footprints/question_mark.rgba",
  ROOT .. "/pokemon/battle/terrain_cave.rgba",
  ROOT .. "/pokemon/battle/terrain_water.rgba",
  ROOT .. "/pokemon/battle/terrain_champion.rgba",
}
for _, rel in ipairs(siblings) do
  check(PokemonExtract.ready(readyCacheWith(rel), ROOT) == false,
    "an import interrupted before " .. rel .. " re-runs the pokemon block")
end
local requiredSet = {}
for _, key in ipairs(CacheContract.requiredFiles("firered")) do requiredSet[key] = true end
for _, rel in ipairs(siblings) do
  check(requiredSet[rel] == true,
    rel .. " is both a ready() sentinel and a contract-required key")
end

print("[test] 4. the parallel success path writes the stage markers")
local par, parFiles = loadExtractorWithStubs(function()
  return { root = "data/generated/gba/pokemon", picsWritten = { icons = 412 } }
end)
par.runParallel = function() return true end
local parOk, parErr = pcall(par.run, par)
check(parOk == true, "the parallel path completes the import (" .. tostring(parErr) .. ")")
local parPoke = parFiles[STATUS] and Json.decode(parFiles[STATUS])
check(parPoke ~= nil and parPoke.ok == true,
  "the parallel path writes pokemon/extract_status.json with ok = true")
local parAux = parFiles[AUX_STATUS] and Json.decode(parFiles[AUX_STATUS])
check(parAux ~= nil and parAux.ok == true,
  "the parallel path writes region_map/extract_status.json with ok = true")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
