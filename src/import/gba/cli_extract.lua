#!/usr/bin/env luajit
-- Offline FRLG extract → CacheFS (Love firered save dir), never mod-tree.
-- Usage (from repo root):
--   luajit src/import/gba/cli_extract.lua [path/to/firered.gba]
--   luajit src/import/gba/cli_extract.lua --native-only [rom]
-- Override output with GBA_CACHE_ROOT=/path/to/firered (contains data/generated/gba).

package.path = package.path
  .. ";./?.lua;./?/init.lua"
  .. ";mods/Kanto-Reforged/?.lua;mods/Kanto-Reforged/?/init.lua"

-- Allow running from inside the mod directory.
local function add_path(p)
  package.path = p .. "/?.lua;" .. p .. "/?/init.lua;" .. package.path
end
add_path(".")
add_path("..")
add_path("../..")
add_path("../../..")

-- Map mods.Kanto-Reforged.* → local sevii when running inside mod tree.
local real_require = require
table.insert(package.searchers or package.loaders, 1, function(name)
  local prefix = "mods.Kanto-Reforged."
  if name:sub(1, #prefix) == prefix then
    local rel = name:sub(#prefix + 1):gsub("%.", "/")
    local candidates = {
      rel .. ".lua",
      "./" .. rel .. ".lua",
    }
    for _, c in ipairs(candidates) do
      local f = io.open(c, "r")
      if f then
        f:close()
        return assert(loadfile(c))
      end
    end
  end
end)

local FileIO = require("src.import.gba.file_io")
local Extract = require("src.import.gba.extract_island1")

local nativeOnly = false
local pokemonOnly = false
local battleMovesOnly = false
local encountersOnly = false
local namingOnly = false
local introOnly = false
local battleAnimsOnly = false
local battleAiOnly = false
local battleTransitionsOnly = false
local trainersOnly = false
local itemsOnly = false
local pokedexOnly = false
local mapTreeOnly = false
local martsOnly = false
local scriptsOnly = false
local bagChromeOnly = false
local dumpMid = nil -- { pair, mid, outPath }
local romPath = nil
local ai = 1
while ai <= #arg do
  if arg[ai] == "--native-only" then
    nativeOnly = true
    ai = ai + 1
  elseif arg[ai] == "--pokemon" then
    pokemonOnly = true
    ai = ai + 1
  elseif arg[ai] == "--items" then
    itemsOnly = true
    ai = ai + 1
  elseif arg[ai] == "--pokedex" then
    pokedexOnly = true
    ai = ai + 1
  elseif arg[ai] == "--marts" then
    martsOnly = true
    ai = ai + 1
  elseif arg[ai] == "--scripts" then
    scriptsOnly = true
    ai = ai + 1
  elseif arg[ai] == "--bag-chrome" then
    bagChromeOnly = true
    ai = ai + 1
  elseif arg[ai] == "--map-tree" then
    mapTreeOnly = true
    ai = ai + 1
  elseif arg[ai] == "--battle-moves" then
    battleMovesOnly = true
    ai = ai + 1
  elseif arg[ai] == "--battle-anims" then
    battleAnimsOnly = true
    ai = ai + 1
  elseif arg[ai] == "--battle-ai" then
    battleAiOnly = true
    ai = ai + 1
  elseif arg[ai] == "--battle-transitions" then
    battleTransitionsOnly = true
    ai = ai + 1
  elseif arg[ai] == "--trainers" then
    trainersOnly = true
    ai = ai + 1
  elseif arg[ai] == "--encounters" then
    encountersOnly = true
    ai = ai + 1
  elseif arg[ai] == "--naming" then
    namingOnly = true
    ai = ai + 1
  elseif arg[ai] == "--intro" then
    introOnly = true
    ai = ai + 1
  elseif arg[ai] == "--dump-mid" and arg[ai + 3] then
    dumpMid = { pair = arg[ai + 1], mid = tonumber(arg[ai + 2]), out = arg[ai + 3] }
    ai = ai + 4
  elseif not romPath and arg[ai]:sub(1, 1) ~= "-" then
    romPath = arg[ai]
    ai = ai + 1
  else
    ai = ai + 1
  end
end

if not romPath then
  -- Default: FireRed dump in mod root (gitignored).
  local here = debug.getinfo(1, "S").source:match("@(.*)/") or "."
  romPath = here .. "/../../1636 - Pokemon Fire Red (U)(Squirrels).gba"
  if not io.open(romPath, "rb") then
    romPath = "1636 - Pokemon Fire Red (U)(Squirrels).gba"
  end
end

local md5
do
  -- Engine identity is SHA-1; fall back to md5sum (Versions.BY_MD5 aliases).
  local q = "'" .. romPath:gsub("'", "'\\''") .. "'"
  local p = io.popen("sha1sum " .. q .. " 2>/dev/null || shasum -a 1 " .. q)
  local line = p and p:read("*l")
  if p then p:close() end
  md5 = line and line:match("^(%x+)")
  if not md5 then
    p = io.popen("md5sum " .. q)
    line = p and p:read("*l")
    if p then p:close() end
    md5 = line and line:match("^(%x+)")
  end
  md5 = md5 or "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"
end

print("ROM:", romPath)
print("SHA1:", md5)

local imports = FileIO.makeImports(romPath, md5, "firered")
-- CacheFS root: Love firered save dir (data/generated/gba lives underneath).
local outDir = os.getenv("GBA_CACHE_ROOT")
  or ((os.getenv("HOME") or ".") .. "/.local/share/love/pokemon-love2d/firered")
Extract.CACHE_ROOT = "data/generated/gba"
Extract.NATIVE_ROOT = "data/generated/gba/native"
local cache = FileIO.makeCache(outDir)
print("CacheFS:", outDir .. "/" .. Extract.CACHE_ROOT)

if dumpMid then
  local Rom = require("src.import.gba.rom")
  local Versions = require("src.import.gba.versions")
  local Tileset = require("src.import.gba.tileset")
  local Metatile = require("src.import.gba.metatile")
  local NativePack = require("src.import.gba.native_pack")
  local version = assert(Versions.lookup(md5))
  local rom = assert(Rom.open(imports, "firered"))
  local bundle = assert(Tileset.loadPair(rom, version, dumpMid.pair))
  local idx = Metatile.compositeIndexed(bundle, dumpMid.mid)
  local rgb = NativePack.palsToRgb8(bundle.mapPals)
  local fake = {
    midCount = 1, atlasCols = 1, atlasRows = 1, midIds = { dumpMid.mid }, pixels = idx,
  }
  local rgba = NativePack.bakeRgba(fake, rgb)
  local f = assert(io.open(dumpMid.out, "wb"))
  f:write("P6\n16 16\n255\n")
  for i = 1, 16 * 16 do
    local o = (i - 1) * 4 + 1
    f:write(string.char(rgba:byte(o), rgba:byte(o + 1), rgba:byte(o + 2)))
  end
  f:close()
  print("Wrote", dumpMid.out)
  imports:_close()
  os.exit(0)
end

if namingOnly or introOnly then
  print("NOTE: --naming/--intro require Love2D image encoders; use RomExtractorGen3 or love runner.")
  print("Offsets live in Versions.NAMING / Versions.INTRO.")
  os.exit(0)
end

if battleMovesOnly then
  local Rom = require("src.import.gba.rom")
  local BattleMovesExtract = require("src.import.gba.battle_moves_extract")
  local outRoot = os.getenv("HOME")
    and (os.getenv("HOME") .. "/.local/share/love/pokemon-love2d/firered")
    or "."
  local packCache = FileIO.makeCache(outRoot)
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting gBattleMoves →", outRoot .. "/data/generated/gba/pokemon")
  local detail = BattleMovesExtract.run(rom, packCache, { cacheRoot = "data/generated/gba" })
  rom:clearCache()
  imports:_close()
  print("OK battle moves", detail.pack.count, "→", detail.path)
  os.exit(0)
end

if encountersOnly then
  local Rom = require("src.import.gba.rom")
  local Versions = require("src.import.gba.versions")
  local EncExtract = require("src.import.gba.encounters_extract")
  local outRoot = os.getenv("HOME")
    and (os.getenv("HOME") .. "/.local/share/love/pokemon-love2d/firered")
    or "."
  local packCache = FileIO.makeCache(outRoot)
  local version = assert(Versions.lookup(md5))
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting gWildMonHeaders →", outRoot .. "/data/generated/gba/encounters.lua")
  local detail = assert(EncExtract.writeExtract(rom, packCache, "data/generated/gba", version))
  rom:clearCache()
  imports:_close()
  print("OK encounters", detail.headers, "headers,", detail.aliases, "aliases")
  os.exit(0)
end

if battleAnimsOnly then
  local Rom = require("src.import.gba.rom")
  local AnimExtract = require("src.import.gba.battle_anim_extract")
  local outRoot = outDir
  local packCache = cache
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting battle anim IR →", outRoot .. "/data/generated/gba/pokemon/battle_anims")
  local animCache = {
    write = function(_, rel, bytes)
      local path = rel
      if not path:match("^data/") then
        path = "data/generated/gba/" .. path
      end
      return packCache:write(path, bytes)
    end,
    exists = function(_, rel) return packCache.exists and packCache:exists(rel) end,
    read   = function(_, rel) return packCache.read and packCache:read(rel) end,
  }
  local detail = assert(AnimExtract.run(rom, animCache, { cacheRoot = "data/generated/gba", force = true }))
  rom:clearCache()
  imports:_close()
  print("OK battle anims", detail.moveCount, "→", detail.path)
  os.exit(0)
end

if battleAiOnly then
  local AiExtract = require("src.import.gba.battle_ai_extract")
  local outRoot = os.getenv("HOME")
    and (os.getenv("HOME") .. "/.local/share/love/pokemon-love2d/firered")
    or "."
  local packCache = FileIO.makeCache(outRoot)
  print("Extracting battle AI scripts →", outRoot .. "/data/generated/gba/battle_ai")
  local detail = assert(AiExtract.run({
    cache = packCache,
    cacheRoot = "data/generated/gba",
    pretRoot = os.getenv("POKEFIRERED"),
  }))
  imports:_close()
  print("OK battle AI", detail.scriptCount or "?", "scripts →", detail.path or detail.root)
  os.exit(0)
end

if battleTransitionsOnly then
  local Rom = require("src.import.gba.rom")
  local BattleTransitionExtract = require("src.import.gba.battle_transition_extract")
  local outRoot = os.getenv("HOME")
    and (os.getenv("HOME") .. "/.local/share/love/pokemon-love2d/firered")
    or "."
  local packCache = FileIO.makeCache(outRoot)
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting battle transitions →", outRoot .. "/data/generated/gba/pokemon/battle_transition")
  local detail = assert(BattleTransitionExtract.run(rom, packCache, {
    cacheRoot = "data/generated/gba",
  }))
  rom:clearCache()
  imports:_close()
  print("OK battle transition →", detail.root,
    detail.bigW .. "x" .. detail.bigH, "big_pokeball")
  os.exit(0)
end

if trainersOnly then
  local Rom = require("src.import.gba.rom")
  local TrainerExtract = require("src.import.gba.trainer_extract")
  local outRoot = os.getenv("HOME")
    and (os.getenv("HOME") .. "/.local/share/love/pokemon-love2d/firered")
    or "."
  local packCache = FileIO.makeCache(outRoot)
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting trainers →", outRoot .. "/data/generated/gba/trainers.lua")
  local detail = TrainerExtract.run(rom, packCache, { cacheRoot = "data/generated/gba" })
  rom:clearCache()
  imports:_close()
  print("OK trainers", detail.pack.trainerCount, "→", detail.root)
  os.exit(0)
end

if pokemonOnly then
  local Rom = require("src.import.gba.rom")
  local PokemonExtract = require("src.import.gba.pokemon_extract")
  -- Standalone FireRed cache (never sevii). Prefer LOVE save dir when present.
  local outRoot = os.getenv("HOME")
    and (os.getenv("HOME") .. "/.local/share/love/pokemon-love2d/firered")
    or "."
  local packCache = FileIO.makeCache(outRoot)
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting Pokémon pack →", outRoot .. "/data/generated/gba/pokemon")
  local detail = PokemonExtract.run(rom, packCache, {
    cacheRoot = "data/generated/gba",
    progress = function(stage, cur, total)
      if cur % 50 == 0 or cur + 1 >= total then
        print(string.format("  [%s] %d/%d", stage, cur, total))
      end
    end,
  })
  rom:clearCache()
  imports:_close()
  print("OK pokemon", detail.numSpecies, "species →", detail.root)
  if detail.partyChrome then
    print("OK party chrome →", detail.partyChrome.root)
  end
  if detail.battleChrome then
    print("OK battle chrome →", detail.battleChrome.root,
      detail.battleChrome.textboxW, "x", detail.battleChrome.textboxH)
  end
  if detail.stats and detail.stats[1] then
    local s = detail.stats[1]
    print(string.format("  Bulbasaur stats hp=%d atk=%d def=%d spe=%d spa=%d spd=%d",
      s.hp, s.atk, s.def, s.spe, s.spa, s.spd))
  end
  if detail.abilityNames and detail.abilityNames[1] then
    print("  ability 1 =", detail.abilityNames[1])
  end
  if detail.learnsets and detail.learnsets[1] then
    local parts = {}
    for _, e in ipairs(detail.learnsets[1]) do
      local name = detail.moveNames and detail.moveNames[e.move] or tostring(e.move)
      parts[#parts + 1] = string.format("Lv%d %s", e.level, name)
    end
    print("  Bulbasaur learnset:", table.concat(parts, ", "))
  end
  if detail.battleMoves and detail.battleMoves.moves and detail.battleMoves.moves[33] then
    local t = detail.battleMoves.moves[33]
    print(string.format("  TACKLE pp=%d power=%d", t.pp, t.power))
  end
  os.exit(0)
end

if itemsOnly then
  local Rom = require("src.import.gba.rom")
  local ItemsExtract = require("src.import.gba.items_extract")
  local outRoot = os.getenv("HOME")
    and (os.getenv("HOME") .. "/.local/share/love/pokemon-love2d/firered")
    or "."
  local packCache = FileIO.makeCache(outRoot)
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting items pack →", outRoot .. "/data/generated/gba/items")
  local detail = ItemsExtract.run(rom, packCache, { cacheRoot = "data/generated/gba" })
  rom:clearCache()
  imports:_close()
  print("OK items", detail and detail.count or "?", "→", detail and detail.path or outRoot)
  os.exit(0)
end

if pokedexOnly then
  local Rom = require("src.import.gba.rom")
  local PokedexExtract = require("src.import.gba.pokedex_chrome_extract")
  local outRoot = os.getenv("HOME")
    and (os.getenv("HOME") .. "/.local/share/love/pokemon-love2d/firered")
    or "."
  local packCache = FileIO.makeCache(outRoot)
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting Pokédex data from ROM →", outRoot .. "/data/generated/gba/pokemon/pokedex")
  local ok = PokedexExtract.run(rom, packCache, {
    cacheRoot = "data/generated/gba",
    force = true,
    progress = function(stage, cur, total)
      print(string.format("  [%s] %d/%d", stage, cur, total))
    end,
  })
  rom:clearCache()
  imports:_close()
  print("OK pokedex entries, categories, and orders extracted from ROM")
  os.exit(0)
end

if martsOnly then
  local Rom = require("src.import.gba.rom")
  local MartsExtract = require("src.import.gba.marts_extract")
  local outRoot = outDir
  local packCache = cache
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting pokemart lists →", outRoot .. "/data/generated/gba/scripts/marts.lua")
  local detail, err = MartsExtract.run(rom, packCache, { cacheRoot = Extract.CACHE_ROOT })
  rom:clearCache()
  imports:_close()
  if not detail then
    io.stderr:write("FAIL marts: " .. tostring(err) .. "\n")
    os.exit(1)
  end
  print("OK marts", detail.listCount, "lists from", detail.ptrCount, "ptrs →", detail.path)
  os.exit(0)
end

if scriptsOnly then
  local Rom = require("src.import.gba.rom")
  local ExtractScripts = require("src.import.gba.extract_scripts")
  local Versions = require("src.import.gba.versions")
  local outRoot = outDir
  local packCache = cache
  local rom = assert(Rom.open(imports, "firered"))
  local version = Versions.lookup(rom.md5)
  print("Extracting scripts bundle →", outRoot .. "/data/generated/gba/scripts")
  local bundle = ExtractScripts.writeBundleFromRom(rom, packCache, Extract.CACHE_ROOT, version)
  rom:clearCache()
  imports:_close()
  print("OK scripts", bundle.scriptCount, "scripts →", Extract.CACHE_ROOT .. "/scripts")
  os.exit(0)
end

if bagChromeOnly then
  local Rom = require("src.import.gba.rom")
  local BagChromeExtract = require("src.import.gba.bag_chrome_extract")
  local rom = assert(Rom.open(imports, "firered"))
  print("Extracting bag chrome + icons →", outDir .. "/data/generated/gba/items/bag")
  local detail = BagChromeExtract.run(rom, cache, {
    cacheRoot = Extract.CACHE_ROOT,
    progress = function(stage, cur, total)
      if cur % 50 == 0 or cur + 1 >= total then
        print(string.format("  [%s] %d/%d", stage, cur, total))
      end
    end,
  })
  rom:clearCache()
  imports:_close()
  print("OK bag-chrome icons=", detail.iconsBaked, "→", detail.root)
  os.exit(0)
end

if mapTreeOnly then
  local Rom = require("src.import.gba.rom")
  local Versions = require("src.import.gba.versions")
  local MapTreeExtract = require("src.import.gba.map_tree_extract")
  local outRoot = os.getenv("HOME")
    and (os.getenv("HOME") .. "/.local/share/love/pokemon-love2d/firered")
    or "."
  local packCache = FileIO.makeCache(outRoot)
  local version = assert(Versions.lookup(md5))
  local rom = assert(Rom.open(imports, "firered"))
  print("Walking gMapGroups →", outRoot .. "/data/generated/gba/map_tree")
  local ok, detail = MapTreeExtract.run(rom, packCache, {
    version = version,
    progress = function(name, cur, total)
      if cur % 50 == 0 or cur + 1 >= total then
        print(string.format("  %s %d/%d", name, cur, total))
      end
    end,
  })
  rom:clearCache()
  imports:_close()
  if not ok then
    io.stderr:write("FAIL map-tree: " .. tostring(detail) .. "\n")
    os.exit(1)
  end
  print("OK map-tree", detail.map_count, "maps", detail.tileset_count, "tilesets")
  print("  →", outRoot .. "/" .. detail.root)
  os.exit(0)
end

local runner = nativeOnly and Extract.runNativeOnly or Extract.run
local ok, detail = runner(imports, cache, function(stage, n, name, cur, total)
  print(string.format("  [%d/%d] %s %s/%s", stage, n, name, tostring(cur), tostring(total)))
end)
imports:_close()

if not ok then
  io.stderr:write("FAIL: " .. tostring(detail) .. "\n")
  os.exit(1)
end
if detail.native_only then
  print("OK native-only", detail.md5,
    "pairs=" .. tostring(detail.pairs), "maps=" .. tostring(detail.maps))
else
  print("OK", detail.tile_count, "tiles", detail.block_count, "blocks", detail.mid_count, "mids")
end
print("Wrote CacheFS", outDir .. "/" .. Extract.CACHE_ROOT)
