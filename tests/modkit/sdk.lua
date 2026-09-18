-- Headless mod load/merge for the SDK harness (21-testing-and-ci "modkit
-- test harness").  A mod author with a checkout of the engine and no ROM
-- can load their mod, merge it into the fixture dataset, and assert on the
-- result -- the seam that makes `modkit test` possible.
--
-- Loader:_discover hard-codes the root "mods", so loading exactly one mod
-- (or a mod that lives outside mods/) goes through an aliasing filesystem:
-- "mods/<name>" is rewritten to the real directory and the listing of
-- "mods" is narrowed to the selected set.  Everything else is the
-- production path -- same Loader, same validate, same topo-sort, same
-- merge -- so a green SDK test means the mod really loads in the game.

local FsIo = require("tests.fs_io")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")

local Sdk = {}

local function basename(path)
  return (tostring(path):gsub("/+$", ""):match("[^/]+$"))
end

-- rewrite "mods/<alias>" and anything under it to the mod's real location,
-- and answer getDirectoryItems("mods") with just the selected aliases
local function aliasFs(inner, alias)
  local fs = { root = inner.root }

  local function map(path)
    if path == nil then return path end
    for name, real in pairs(alias) do
      local prefix = "mods/" .. name
      if path == prefix then return real end
      if path:sub(1, #prefix + 1) == prefix .. "/" then
        return real .. path:sub(#prefix + 1)
      end
    end
    return path
  end

  function fs.read(path) return inner.read(map(path)) end
  function fs.write(path, body) return inner.write(map(path), body) end
  function fs.load(path) return inner.load(map(path)) end

  function fs.getInfo(path)
    if path == "mods" then return { type = "directory" } end
    return inner.getInfo(map(path))
  end

  function fs.getDirectoryItems(path)
    if path == "mods" then
      local names = {}
      for name in pairs(alias) do names[#names + 1] = name end
      table.sort(names)
      return names
    end
    return inner.getDirectoryItems(map(path))
  end

  return fs
end

-- flat path -> content filesystem, for cases that synthesize a mod rather
-- than committing one to disk
function Sdk.memfs(files)
  local loadstr = loadstring or load
  return {
    read = function(path) return files[path] end,
    write = function(path, body) files[path] = body return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return loadstr(files[path], path)
    end,
    getDirectoryItems = function(path)
      local seen, items = {}, {}
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
      table.sort(items)
      return items
    end,
  }
end

-- Runtime is process-wide and Loader:load installs into it; a case that
-- forgets to put it back would leak its buses into the next suite
local saved

function Sdk.captureRuntime()
  saved = { events = Runtime.events, hooks = Runtime.hooks, errors = Runtime.errors }
end

function Sdk.restoreRuntime()
  if not saved then return end
  Runtime.events, Runtime.hooks, Runtime.errors = saved.events, saved.hooks, saved.errors
  Runtime.currentMod = nil
  saved = nil
end

-- opts.data        the merge target (defaults to a fresh fixture dataset)
-- opts.fs          override the filesystem entirely (e.g. Sdk.memfs)
-- opts.root        repo root the real paths are relative to
-- opts.dev         force the dev tripwire on
-- opts.generation  1 (default), 2 or 3; loads as if Gold or FireRed were the
--                  running game, which is the seam the generation gate and the
--                  registry target routing are tested through without a boot;
--                  a Gen 3 run wants opts.data = Sdk.gen3Data()
function Sdk.loadMods(paths, opts)
  opts = opts or {}
  local data = opts.data or require("tests.modkit.fixtures").fresh()

  local fs = opts.fs
  if not fs then
    local alias = {}
    for _, path in ipairs(paths) do alias[basename(path)] = path end
    fs = aliasFs(FsIo.new(opts.root or "."), alias)
  end

  Sdk.captureRuntime()
  local loader = Loader.new({ fs = fs, dev = opts.dev,
                              generation = opts.generation })
  local ok, err = pcall(loader.load, loader, data)
  if not ok then
    Sdk.restoreRuntime()
    error(err, 0)
  end

  local mods = {}
  for _, path in ipairs(paths) do
    for id, mod in pairs(loader.mods) do
      if mod.path == path or basename(mod.path) == basename(path) then mods[id] = mod end
    end
  end

  return {
    loader = loader,
    data = data,
    mods = mods,
    errors = loader.errors,
    -- release the buses; a case that wants them live calls keep()
    release = function() Sdk.restoreRuntime() end,
  }
end

local function mon(hp, atk, def, spe, spa, spd)
  return { hp = hp, atk = atk, def = def, spe = spe, spa = spa, spd = spd }
end

local function meta(catchRate, expYield, growthRate)
  return { catchRate = catchRate, expYield = expYield, genderRatio = 31,
           eggCycles = 20, friendship = 70, growthRate = growthRate,
           eggGroup1 = 1, eggGroup2 = 1, itemCommon = 0, itemRare = 0 }
end

local function move(power, typeId, accuracy, pp)
  return { effect = 0, power = power, type = typeId, accuracy = accuracy,
           pp = pp, secondaryChance = 0, target = 0, priority = 0, flags = 0 }
end

function Sdk.gen3Data()
  return {
    maps = {
      FR_OAKS_LAB = { id = "FR_OAKS_LAB", name = "OAKS LAB",
                      width = 13, height = 12 },
    },
    tilesets = {},
    gen3Pokemon = {
      _names = { [4] = "CHARMANDER", [5] = "CHARMELEON", [16] = "PIDGEY",
                 [29] = "NIDORAN\226\153\128", [151] = "MEW",
                 [252] = "?" },
      _types = { [4] = { 10, 10 }, [5] = { 10, 10 }, [16] = { 0, 2 },
                 [29] = { 3, 3 }, [151] = { 14, 14 } },
      _stats = { [4] = mon(39, 52, 43, 65, 60, 50),
                 [5] = mon(58, 64, 58, 80, 80, 65),
                 [16] = mon(40, 45, 40, 56, 35, 35),
                 [29] = mon(55, 47, 52, 41, 40, 40),
                 [151] = mon(100, 100, 100, 100, 100, 100) },
      _speciesMeta = { [4] = meta(45, 65, 3), [5] = meta(45, 142, 3),
                       [16] = meta(255, 55, 3), [29] = meta(235, 59, 3),
                       [151] = meta(45, 64, 3) },
      _abilities = { [4] = { 66, 0 }, [5] = { 66, 0 }, [16] = { 51, 0 },
                     [29] = { 38, 0 }, [151] = { 28, 0 } },
      _abilityNames = { [28] = "SYNCHRONIZE", [38] = "POISON POINT",
                        [51] = "KEEN EYE", [66] = "BLAZE" },
      _learnsets = { [4] = { { 1, 10 }, { 7, 52 } }, [5] = { { 1, 10 } },
                     [16] = { { 1, 33 } }, [29] = { { 1, 33 } },
                     [151] = { { 1, 1 } } },
      _evolutions = { [4] = { { method = 4, param = 16, target = 5 } } },
      _dex = { [4] = { category = "LIZARD", height = 6, weight = 85 },
               [151] = { category = "NEW SPECIES", height = 4, weight = 40 } },
      _moveNames = { [0] = "-", [1] = "POUND", [10] = "SCRATCH",
                     [33] = "TACKLE", [52] = "EMBER", [57] = "SURF" },
    },
    gen3Moves = {
      _rom = { [1] = move(40, 0, 100, 35), [10] = move(40, 0, 100, 35),
               [33] = move(35, 0, 95, 35), [52] = move(40, 10, 100, 25),
               [57] = move(95, 11, 100, 15) },
    },
    gen3Items = {
      _byId = {
        [0] = { name = "????????", pocket = "ITEMS", price = 0 },
        [4] = { name = "POK\195\169 BALL", pocket = "POKE_BALLS", price = 200 },
        [13] = { name = "POTION", pocket = "ITEMS", price = 300 },
        [96] = { name = "THUNDERSTONE", pocket = "ITEMS", price = 2100 },
      },
    },
    gen3Encounters = {
      FR_ROUTE_1 = { mapGroup = 3, mapNum = 19, land = { rate = 21, slots = {
        { species = 16, minLevel = 2, maxLevel = 3 },
        { species = 29, minLevel = 2, maxLevel = 4 } } } },
      ["3:19"] = { mapGroup = 3, mapNum = 19, land = { rate = 21, slots = {
        { species = 16, minLevel = 2, maxLevel = 3 },
        { species = 29, minLevel = 2, maxLevel = 4 } } } },
    },
    gen3Trainers = {
      classNames = { [81] = "RIVAL" },
      trainers = {
        [326] = { class = 81, className = "RIVAL", name = "TERRY",
                  partySize = 1, party = { { species = 4, level = 5 } },
                  dialogs = {} },
      },
    },
    gen3Text = {
      Text_BootedUpPC = { { t = "player" }, { t = "text", s = " booted up the PC." },
                          { t = "eos" } },
    },
    gen3Scripts = {
      EventScript_Fixture = { { op = "msgbox", text = "Text_BootedUpPC" },
                              { op = "end" } },
    },
  }
end

function Sdk.loadMod(path, opts)
  local result = Sdk.loadMods({ path }, opts)
  result.mod = select(2, next(result.mods))
  return result
end

-- load nothing: the no-mod baseline every parity gate compares against
function Sdk.loadNone(opts)
  return Sdk.loadMods({}, opts)
end

return Sdk
