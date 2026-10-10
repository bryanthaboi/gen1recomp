local CacheFs = require("src.import.CacheFs")
local LuaWriter = require("src.import.LuaWriter")
local GameVersion = require("src.core.GameVersion")
local CachePaths = require("src.core.game3.cache_paths")
local Plans = require("src.import.gba.plans.registry")

local RomExtractorGen3 = {}
RomExtractorGen3.__index = RomExtractorGen3

local STAGE_COUNT = 5
local GBA_ROOT = CachePaths.CACHE_ROOT

local function canonicalImportId(id)
  return id == "leafgreen" and "firered" or id
end

local function importVersion(sha1)
  local version = GameVersion.forSha1(sha1)
  if not version or GameVersion.generation(version) ~= 3 then
    error("unknown gen 3 ROM sha1 " .. tostring(sha1), 2)
  end
  return version
end

local function hexSha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

local function writeText(rel, body)
  local ok, err = CacheFs.write(rel, body)
  if not ok then
    error("could not write " .. rel .. ": " .. tostring(err))
  end
end

local function writeJson(rel, obj)
  local Canon = require("src.import.canonical_json")
  writeText(rel, Canon.encode(obj) .. "\n")
end

local function makeImports(romData, sha1, version)
  version = version or importVersion(sha1)
  return {
    info = function(_, id)
      if canonicalImportId(id) ~= canonicalImportId(version) then
        return nil, "undeclared"
      end
      return {
        id = canonicalImportId(version),
        size = #romData,
        -- versions.lua looks up by SHA-1 (legacy field name is md5).
        md5 = sha1,
        file = "memory",
      }
    end,
    read = function(_, id, offset, length)
      if canonicalImportId(id) ~= canonicalImportId(version) then
        return nil, "undeclared"
      end
      if offset < 0 or length < 0 or offset + length > #romData then
        return nil, "short read"
      end
      return romData:sub(offset + 1, offset + length)
    end,
  }
end

local function makeCache()
  return {
    write = function(_, rel, bytes)
      return CacheFs.write(rel, bytes)
    end,
    read = function(_, rel)
      return CacheFs.read(rel)
    end,
    exists = function(_, rel)
      return CacheFs.exists(rel)
    end,
    info = function(_, rel)
      if CacheFs.exists(rel) then return { type = "file" } end
      return nil
    end,
  }
end

local POKEMON_SUBTASKS = {
  ["pokemon"]           = { min = 0.00, max = 0.50, label = "Pokémon Species & Sprites" },
  ["learnsets"]         = { min = 0.50, max = 0.58, label = "Move Learnsets" },
  ["battle_moves"]      = { min = 0.58, max = 0.62, label = "Battle Moves Data" },
  ["party_chrome"]      = { min = 0.62, max = 0.68, label = "Party UI Graphics" },
  ["battle_chrome"]     = { min = 0.68, max = 0.74, label = "Battle UI Graphics" },
  ["pokedex_entries"]   = { min = 0.74, max = 0.78, label = "Pokédex Database" },
  ["pokedex_categories"]= { min = 0.78, max = 0.80, label = "Pokédex Categories" },
  ["pokedex_orders"]    = { min = 0.80, max = 0.82, label = "Pokédex Sorting" },
  ["pokedex_done"]      = { min = 0.82, max = 0.84, label = "Pokédex Complete" },
  ["storage_chrome"]    = { min = 0.84, max = 0.88, label = "PC Storage Chrome" },
  ["battle_transition"] = { min = 0.88, max = 0.92, label = "Battle Transitions" },
  ["summary_chrome"]    = { min = 0.92, max = 0.96, label = "Summary Screen Graphics" },
  ["bag_chrome"]        = { min = 0.96, max = 0.98, label = "Bag & Items Graphics" },
  ["shop_chrome"]       = { min = 0.98, max = 1.00, label = "Mart & Shop Graphics" },
}

function RomExtractorGen3.new(romData, manifest, progressCb, romSha1)
  local sha1 = romSha1 or (manifest and manifest.romSha1) or hexSha1(romData)
  local version = importVersion(sha1)
  require("src.import.gba.versions").select(sha1)
  return setmetatable({
    version = version,
    plan = Plans.of(version),
    romData = romData,
    manifest = manifest,
    progress = progressCb,
    romSha1 = romSha1,
    stage = 0,
    _lastPct = 0,
  }, RomExtractorGen3)
end

function RomExtractorGen3:sharedImports(sha1)
  if not self._imports then
    self._imports = makeImports(self.romData, sha1, importVersion(sha1))
  end
  return self._imports
end

function RomExtractorGen3:ensureSha1()
  if type(self.romSha1) == "string" and self.romSha1 ~= "" then
    return self.romSha1
  end
  self.romSha1 = hexSha1(self.romData)
  return self.romSha1
end

function RomExtractorGen3:report(pct, stageName, current, stageTotal)
  pct = math.max(self._lastPct or 0, math.min(1.0, pct or 0))
  self._lastPct = pct
  if self.progress then
    self.progress(math.floor(pct * 1000), 1000, stageName or "Extracting", current or 0, stageTotal or 1)
  end
end

function RomExtractorGen3:beginStage(name)
  self.stage = self.stage + 1
  self:report((self.stage - 1) / STAGE_COUNT, name, 0, 1)
end

function RomExtractorGen3:tickPokemon(name, current, total)
  local st = POKEMON_SUBTASKS[name]
  if st then
    local curFrac = (current or 0) / math.max(total or 1, 1)
    local frac = st.min + curFrac * (st.max - st.min)
    local label = st.label
    if total and total > 1 then
      label = label .. string.format(" (%d/%d)", current or 0, total)
    end
    self:report(frac, label, current, total)
  else
    local frac = (current or 0) / math.max(total or 1, 1)
    self:report(frac, name or "Pokémon Data", current, total)
  end
end

-- plus semantic module stubs for SEMANTIC_MODULES[3].
function RomExtractorGen3:writeRequiredMarkers(sha1)
  local Versions = require("src.import.gba.versions")
  local version = importVersion(sha1)
  local cache = makeCache()
  local metaRaw = cache:read(GBA_ROOT .. "/meta.json")
  if not metaRaw or not metaRaw:find('"md5"%s*:%s*"' .. sha1 .. '"') or not metaRaw:find('"cache_version"%s*:%s*' .. tostring(Versions.CACHE_VERSION)) then
    writeJson(GBA_ROOT .. "/meta.json", {
      romSha1 = sha1,
      md5 = sha1,
      version = version,
      cache_version = Versions.CACHE_VERSION,
      native_version = Versions.NATIVE_VERSION or 5,
      stub = false,
    })
  end
  if not CacheFs.exists(GBA_ROOT .. "/maps.json") then
    writeJson(GBA_ROOT .. "/maps.json", {
      maps = {},
      stub = true,
    })
  end
  if not CacheFs.exists(GBA_ROOT .. "/intro/meta.json") then
    writeJson(GBA_ROOT .. "/intro/meta.json", {
      stub = true,
    })
  end
  if not CacheFs.exists(GBA_ROOT .. "/audio/meta.json") then
    writeJson(GBA_ROOT .. "/audio/meta.json", {
      stub = true,
    })
  end
  if not CacheFs.exists("data/generated/maps.lua") then
    LuaWriter.write("data/generated/maps.lua", { stub = true, maps = {} })
  end
  if not CacheFs.exists("data/generated/intro.lua") then
    LuaWriter.write("data/generated/intro.lua", {
      stub = true,
      generation = 3,
      version = version,
    })
  end
  if not CacheFs.exists("data/generated/audio.lua") then
    LuaWriter.write("data/generated/audio.lua", { stub = true })
  end

  for _, d in ipairs(self.plan.dirs or {}) do
    if love and love.filesystem and love.filesystem.createDirectory then
      local p = (CacheFs.prefix or "") .. GBA_ROOT .. d
      pcall(love.filesystem.createDirectory, p)
    end
  end
end

function RomExtractorGen3:runGbaExtract(sha1, skipScriptsAndOw)
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot, prevNative = Extract.CACHE_ROOT, Extract.NATIVE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT
  Extract.NATIVE_ROOT = GBA_ROOT .. "/native"

  local imports = self:sharedImports(sha1)
  local cache = makeCache()
  local runOk, runDetail = false, "extract did not run"
  local callOk, err = pcall(function()
    runOk, runDetail = Extract.run(imports, cache, function(stage, n, name, cur, total)
      local curFrac = (cur or 0) / math.max(total or 1, 1)
      local frac = ((stage or 0) + curFrac) / math.max(n or Extract.STAGE_COUNT or 7, 1)
      local label = "World Maps: " .. tostring(name or "Processing")
      if total and total > 1 then
        label = label .. string.format(" (%d/%d)", cur or 0, total)
      end
      self:report(math.min(frac, 1.0), label, cur or 0, total or 1)
    end, { skipScriptsAndOw = skipScriptsAndOw == true })
  end)

  Extract.CACHE_ROOT = prevRoot
  Extract.NATIVE_ROOT = prevNative

  if not callOk then
    return false, err
  end
  return runOk, runDetail
end

function RomExtractorGen3:runScriptsAndOwExtract(sha1)
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot = Extract.CACHE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT

  local imports = self:sharedImports(sha1)
  local cache = makeCache()
  local runOk, runDetail = false, "scripts_ow did not run"
  local callOk, err = pcall(function()
    runOk = Extract.runScriptsAndOw(imports, cache, function(cur, total, stageName)
      local frac = (cur or 0) / math.max(total or 4, 1)
      self:report(frac, "Scripts & OW: " .. tostring(stageName or "Processing"), cur or 0, total or 4)
    end)
    return runOk
  end)

  Extract.CACHE_ROOT = prevRoot
  if not callOk then return false, err end
  return runOk, runDetail
end

--- Species pack + party chrome into data/generated/gba/pokemon/.
function RomExtractorGen3:runPokemonExtract(sha1, spMin, spMax)
  local Rom = require("src.import.gba.rom")
  local PokemonExtract = require("src.import.gba.pokemon_extract")
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot = Extract.CACHE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT

  local cache = makeCache()
  if not spMin and PokemonExtract.ready(cache, GBA_ROOT) then
    Extract.CACHE_ROOT = prevRoot
    return true, { skipped = true }
  end

  local imports = self:sharedImports(sha1)
  local version = importVersion(sha1)
  local rom, openErr = Rom.open(imports, version)
  if not rom then
    Extract.CACHE_ROOT = prevRoot
    return false, openErr or "rom open failed"
  end

  local ok, detail = pcall(function()
    local pRes = PokemonExtract.run(rom, cache, {
      cacheRoot = GBA_ROOT,
      spMin = spMin or 0,
      spMax = spMax,
      progress = function(name, cur, total)
        self:tickPokemon(name or "pokemon", cur or 0, total or 1)
      end,
    })
    for _, module in ipairs(self.plan.pokemonAfter or {}) do
      require(Plans.moduleFor(module)).run(rom, cache, { cacheRoot = GBA_ROOT })
    end
    return pRes
  end)

  Extract.CACHE_ROOT = prevRoot
  if not ok then
    return false, detail
  end
  return true, detail
end

function RomExtractorGen3:runPokemonGfxExtract(sha1, spMin, spMax)
  local Rom = require("src.import.gba.rom")
  local PokemonExtract = require("src.import.gba.pokemon_extract")
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot = Extract.CACHE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT

  local imports = self:sharedImports(sha1)
  local version = importVersion(sha1)
  local rom, openErr = Rom.open(imports, version)
  if not rom then
    Extract.CACHE_ROOT = prevRoot
    return false, openErr or "rom open failed"
  end

  local cache = makeCache()
  local ok, detail = pcall(function()
    return PokemonExtract.run(rom, cache, {
      cacheRoot = GBA_ROOT,
      spMin = spMin or 0,
      spMax = spMax or 200,
      onlySpeciesGfx = true,
      progress = function(name, cur, total)
        self:tickPokemon(name or "pokemon", cur or 0, total or 1)
      end,
    })
  end)

  Extract.CACHE_ROOT = prevRoot
  if not ok then
    return false, detail
  end
  return true, detail
end

function RomExtractorGen3:auxWanted()
  local Profile = require("src.core.game3.profile")
  local ok, row = pcall(Profile.of, self.version)
  if not ok or type(row) ~= "table" or row.id ~= self.version then return nil end
  local list = row.extractors
  if type(list) ~= "table" or #list == 0 then return nil end
  local wanted = {}
  for _, name in ipairs(list) do wanted[name] = true end
  return wanted
end

function RomExtractorGen3:runAuxExtracts(sha1)
  local wanted = self:auxWanted()
  local Rom = require("src.import.gba.rom")
  local entries = {}
  for _, entry in ipairs(self.plan.aux or {}) do
    entries[#entries + 1] = { entry = entry, mod = require(Plans.moduleFor(entry.name)) }
  end
  local Extract = require("src.import.gba.extract_island1")
  local prevRoot = Extract.CACHE_ROOT
  Extract.CACHE_ROOT = GBA_ROOT

  local cache = makeCache()
  local any = false
  for _, e in ipairs(entries) do
    local name, mod = e.entry.name, e.mod
    if wanted ~= nil and not wanted[name] then
      e.need = false
    elseif e.entry.mode == "sections" then
      e.need = not CacheFs.exists(GBA_ROOT .. "/region_map/map_sections.lua")
    else
      e.need = not (mod.ready and mod.ready(cache, GBA_ROOT))
    end
    any = any or e.need
  end

  if not any then
    Extract.CACHE_ROOT = prevRoot
    return true, { skipped = true }
  end

  local rom, openErr = Rom.open(self:sharedImports(sha1), importVersion(sha1))
  if not rom then
    Extract.CACHE_ROOT = prevRoot
    return false, openErr or "rom open failed"
  end

  local ok, detail = pcall(function()
    local out = {}
    local step = 0
    local totalSteps = self.plan.auxSteps or #entries
    local function auxTick(name)
      step = step + 1
      self:report(step / totalSteps, "Game Data: " .. name, step, totalSteps)
    end

    for _, e in ipairs(entries) do
      local entry, mod = e.entry, e.mod
      if e.need then
        local opts = { cacheRoot = GBA_ROOT }
        for k, v in pairs(entry.opts or {}) do opts[k] = v end
        local tag = entry.tag or entry.name
        if entry.mode == "sections" then
          mod.run(rom, cache, opts)
          local rel = GBA_ROOT .. "/region_map/map_sections.lua"
          local body = cache:read(rel)
          if type(body) ~= "string" or #body < 1024 then
            error("map_sections extract wrote " .. tostring(body and #body or 0)
              .. " bytes to " .. rel)
          end
          out[entry.key] = #body
        elseif entry.mode == "result" then
          local okR, detailR = mod.run(rom, cache, opts)
          if not okR then print("[" .. tag .. "] warn: " .. tostring(detailR)) end
          out[entry.key] = detailR
        elseif entry.mode == "warn" then
          local okW, detailW = pcall(mod.run, rom, cache, opts)
          if not okW then print("[" .. tag .. "] warn: " .. tostring(detailW)) end
          out[entry.key] = okW and detailW or false
        else
          out[entry.key] = mod.run(rom, cache, opts)
        end
      end
      auxTick(entry.label or entry.name)
    end

    return out
  end)

  rom:clearCache()
  Extract.CACHE_ROOT = prevRoot
  if not ok then return false, detail end
  return true, detail
end

function RomExtractorGen3:runStepsTask(sha1, task)
  local Rom = require("src.import.gba.rom")
  local cache = makeCache()
  local steps = task.steps or {}
  local rom, openErr
  local ok, detail = pcall(function()
    local out = {}
    for i, step in ipairs(steps) do
      local mod = require(Plans.moduleFor(step.name))
      if not (mod.ready and mod.ready(cache, GBA_ROOT)) then
        if not rom then
          rom, openErr = Rom.open(self:sharedImports(sha1), importVersion(sha1))
          if not rom then error(openErr or "rom open failed") end
        end
        local opts = { cacheRoot = GBA_ROOT }
        for k, v in pairs(step.opts or {}) do opts[k] = v end
        out[step.name] = mod.run(rom, cache, opts)
      end
      self:report(i / math.max(#steps, 1), task.id .. ": " .. (step.label or step.name), i, #steps)
    end
    return out
  end)
  if rom then rom:clearCache() end
  if not ok then return false, detail end
  return true, detail
end

function RomExtractorGen3:speciesRanges()
  local Versions = require("src.import.gba.versions")
  local last = (Versions.NUM_SPECIES or 412) - 1
  local split = self.plan.speciesSplit or math.floor(last / 2)
  return split, last
end

function RomExtractorGen3:runTask(task, sha1)
  local spec
  for _, t in ipairs(self.plan.tasks or {}) do
    if t.id == task then spec = t end
  end
  if not spec then error("unknown extract task: " .. tostring(task)) end
  local run = spec.run or "steps"
  if run == "gba" then
    return self:runGbaExtract(sha1, true)
  elseif run == "scripts_ow" then
    return self:runScriptsAndOwExtract(sha1)
  elseif run == "pokemon" then
    local split, last = self:speciesRanges()
    return self:runPokemonExtract(sha1, split + 1, last)
  elseif run == "pokemon_gfx" then
    local split = self:speciesRanges()
    return self:runPokemonGfxExtract(sha1, 0, split)
  elseif run == "aux" then
    return self:runAuxExtracts(sha1)
  elseif run == "intro_audio" then
    return self:runIntroAudio(sha1)
  elseif run == "steps" then
    return self:runStepsTask(sha1, spec)
  end
  error("unknown extract runner: " .. tostring(run))
end

function RomExtractorGen3:runIntroAudio(sha1)
  self:report(0.05, "Audio & Intro: Initializing", 0, 3)
  local cache = makeCache()
  if cache:exists(GBA_ROOT .. "/intro/meta.json") and cache:exists(GBA_ROOT .. "/audio/meta.json") then
    local im = cache:read(GBA_ROOT .. "/intro/meta.json")
    if im and not im:find('"stub"%s*:%s*true') then
      self:report(1.00, "Audio Streams Ready", 3, 3)
      return true, true
    end
  end

  local RevisionView = require("src.import.gba.revision_view")
  local imports = self:sharedImports(sha1)
  local version = importVersion(sha1)
  local info = imports:info(version)
  local romShim = { data = RevisionView.forImports(imports, version, info) or self.romData }
  local Intro = require("src.import.gba.extract_intro")
  local Naming = require("src.import.gba.extract_naming")
  local AudioExt = require("src.import.gba.extract_audio")

  self:report(0.20, "Intro: Cutscene Sequence", 1, 3)
  local okI, metaI = Intro.run(romShim, cache, { sha1 = sha1, root = GBA_ROOT .. "/intro" })

  self:report(0.50, "Intro: Naming Screen Graphics", 2, 3)
  local okN = Naming.run(romShim, cache, { sha1 = sha1, root = GBA_ROOT .. "/naming" })

  self:report(0.75, "Audio: Music & Sound Streams", 3, 3)
  local okA, metaA = AudioExt.run(romShim, cache, { sha1 = sha1, root = GBA_ROOT .. "/audio" })

  writeJson(GBA_ROOT .. "/intro/extract_status.json", { ok = okI == true })
  writeJson(GBA_ROOT .. "/naming/extract_status.json", { ok = okN == true })
  writeJson(GBA_ROOT .. "/audio/extract_status.json", { ok = okA == true })
  self:report(1.00, "Audio & Intro Ready", 3, 3)
  return okI, okA, metaI, metaA
end

local function maxWorkers(taskCount)
  local override = tonumber(os.getenv("POKEPORT_EXTRACT_WORKERS") or "")
  if override and override >= 1 then return math.min(taskCount, math.floor(override)) end
  if require("src.import.ImportGc").lowMemoryHost() then
    return math.min(taskCount, 1)
  end
  local osName = love.system and love.system.getOS and love.system.getOS() or ""
  if osName == "iOS" or osName == "Android" or osName == "NX" then
    return math.min(taskCount, 2)
  end
  local cores = love.system and love.system.getProcessorCount and love.system.getProcessorCount() or 4
  return math.max(1, math.min(taskCount, cores - 1, 6))
end

function RomExtractorGen3:runParallel(sha1)
  if os.getenv("POKEPORT_NO_THREAD") == "1" then
    return false, "POKEPORT_NO_THREAD set"
  end
  if not (love and love.thread and love.thread.newThread and love.timer) then
    return false, "love.thread unavailable"
  end

  local ch_name = "gba_extract_" .. tostring(love.timer.getTime()):gsub("%.", "") .. "_" .. tostring(math.random(10000, 99999))
  local ch = love.thread.getChannel(ch_name)

  local tasks, task_progress, weights = {}, {}, {}
  for _, t in ipairs(self.plan.tasks or {}) do
    tasks[#tasks + 1] = t.id
    task_progress[t.id] = 0
    weights[t.id] = t.weight or (1 / math.max(#self.plan.tasks, 1))
  end
  local prefix = CacheFs.prefix or ""

  local workerCode = nil
  if love and love.filesystem and love.filesystem.read then
    workerCode = love.filesystem.read("src/import/gba/extract_worker.lua")
  end

  local running, owned, nextTask = {}, {}, 1
  local cleanupErrors = {}
  local function joinWorker(worker)
    if worker.joinAttempted then return worker.joined end
    worker.joinAttempted = true
    local joined, joinError = pcall(worker.thread.wait, worker.thread)
    worker.joined = joined
    if not joined then
      cleanupErrors[#cleanupErrors + 1] = worker.task .. ": " .. tostring(joinError)
    end
    return joined
  end
  local function spawnUpTo(limit)
    while nextTask <= #tasks and #running < limit do
      local t = tasks[nextTask]
      local okTh, th = pcall(love.thread.newThread, workerCode or "src/import/gba/extract_worker.lua")
      if not okTh or not th then
        return false, "failed to spawn thread for " .. t .. ": " .. tostring(th)
      end
      local worker = { task = t, thread = th }
      owned[#owned + 1] = worker
      local okStart, startResult = pcall(th.start, th, t, prefix, self.romData, sha1, ch_name)
      if not okStart or startResult == false then
        return false, "failed to start thread for " .. t .. ": " .. tostring(startResult)
      end
      running[#running + 1] = worker
      nextTask = nextTask + 1
    end
    return true
  end
  local function retire(task)
    for i, r in ipairs(running) do
      if r.task == task then
        if not joinWorker(r) then error(cleanupErrors[#cleanupErrors]) end
        table.remove(running, i)
        for j, worker in ipairs(owned) do
          if worker == r then table.remove(owned, j) break end
        end
        return
      end
    end
  end

  local function runPool()
    local limit = maxWorkers(#tasks)
    local okSpawn, spawnErr = spawnUpTo(limit)
    if not okSpawn then return false, spawnErr end

    local done_count = 0
    local errors = {}

    while done_count < #tasks do
      local msg = ch:pop()
      if msg then
        if msg.type == "progress" then
          task_progress[msg.task] = math.max(task_progress[msg.task] or 0, math.min(1.0, msg.fraction or 0))
          local total_pct = 0.03
          for k, w in pairs(weights) do
            total_pct = total_pct + (task_progress[k] or 0) * w * 0.95
          end
          self:report(total_pct, msg.stage or "Extracting", msg.current or 0, msg.stageTotal or 1)
        elseif msg.type == "done" then
          done_count = done_count + 1
          task_progress[msg.task] = 1.0
          local total_pct = 0.03
          for k, w in pairs(weights) do
            total_pct = total_pct + (task_progress[k] or 0) * w * 0.95
          end
          self:report(total_pct, "Finalizing " .. tostring(msg.task), done_count, #tasks)
          if not msg.ok then
            errors[#errors + 1] = msg.task .. ": " .. tostring(msg.error)
          end
          retire(msg.task)
          okSpawn, spawnErr = spawnUpTo(limit)
          if not okSpawn then return false, spawnErr end
        end
      else
        for i = #running, 1, -1 do
          local err = running[i].thread:getError()
          if err then
            errors[#errors + 1] = running[i].task .. ": " .. tostring(err)
            retire(running[i].task)
            done_count = done_count + 1
          end
        end
        okSpawn, spawnErr = spawnUpTo(limit)
        if not okSpawn then return false, spawnErr end
        love.timer.sleep(0.005)
      end
    end

    if #errors > 0 then
      return false, "Parallel extraction error:\n" .. table.concat(errors, "\n")
    end
    return true
  end

  local callOk, poolOk, poolError = pcall(runPool)
  for _, worker in ipairs(owned) do
    joinWorker(worker)
  end
  if #cleanupErrors == 0 then
    local cleared, clearError = pcall(ch.clear, ch)
    if not cleared then cleanupErrors[#cleanupErrors + 1] = tostring(clearError) end
  end
  if #cleanupErrors > 0 then
    return false, "Parallel extraction cleanup failed:\n" .. table.concat(cleanupErrors, "\n"), true
  end
  if not callOk then return false, tostring(poolOk) end
  if not poolOk then return false, poolError end

  if not CacheFs.exists(GBA_ROOT .. "/maps.json") then
    writeJson(GBA_ROOT .. "/maps.json", { maps = {}, from_extract = true })
  end

  return true
end

function RomExtractorGen3:hasTask(id)
  for _, t in ipairs(self.plan.tasks or {}) do
    if t.id == id then return true end
  end
  return false
end

function RomExtractorGen3:run()
  local sha1 = self:ensureSha1()

  self:report(0.01, "Initializing Markers", 0, 1)
  self:writeRequiredMarkers(sha1)
  self:report(0.03, "Markers Ready", 1, 1)

  local okPar, parRes, parErr, cleanupFailed = pcall(function()
    return self:runParallel(sha1)
  end)
  if cleanupFailed then error(tostring(parErr)) end
  if okPar and parRes then
    if self:hasTask("pokemon") then
      writeJson(GBA_ROOT .. "/pokemon/extract_status.json", { ok = true, error = nil })
    end
    if self:hasTask("aux") then
      writeJson(GBA_ROOT .. "/region_map/extract_status.json", { ok = true, error = nil })
    end
    self:report(1.00, "Ready", 1, 1)
    collectgarbage("collect")
    return {
      romSha1 = sha1,
      extractOk = true,
      pokemonOk = true,
      auxOk = true,
    }
  end

  print("[RomExtractorGen3] Parallel extraction fell back to sequential: " .. tostring(parErr or parRes))

  local ok, detail, okPoke, okAux = true, nil, true, true
  for _, stage in ipairs(self.plan.sequential or {}) do
    if stage == "gba" then
      ok, detail = self:runGbaExtract(sha1)
      if ok then
        if not CacheFs.exists(GBA_ROOT .. "/maps.json") then
          writeJson(GBA_ROOT .. "/maps.json", { maps = {}, from_extract = true })
        end
      else
        writeJson(GBA_ROOT .. "/extract_status.json", {
          ok = false,
          error = tostring(detail),
          romSha1 = sha1,
        })
        error("GBA extract failed: " .. tostring(detail))
      end
      self:report(0.42, "World Maps Ready", 1, 1)
      collectgarbage("collect")
    elseif stage == "pokemon" then
      local pokeDetail
      okPoke, pokeDetail = self:runPokemonExtract(sha1)
      writeJson(GBA_ROOT .. "/pokemon/extract_status.json", {
        ok = okPoke == true,
        error = (not okPoke) and tostring(pokeDetail) or nil,
      })
      if not okPoke then
        error("Pokemon extract failed: " .. tostring(pokeDetail))
      end
      self:report(0.88, "Game Data & Chrome Ready", 1, 1)
      collectgarbage("collect")
    elseif stage == "aux" then
      local auxDetail
      okAux, auxDetail = self:runAuxExtracts(sha1)
      writeJson(GBA_ROOT .. "/region_map/extract_status.json", {
        ok = okAux == true,
        error = (not okAux) and tostring(auxDetail) or nil,
      })
      if not okAux then
        error("Region map / script table extract failed: " .. tostring(auxDetail))
      end
      collectgarbage("collect")
    elseif stage == "intro_audio" then
      self:runIntroAudio(sha1)
      self:report(0.98, "Finalizing Cache", 1, 1)
      collectgarbage("collect")
    else
      local okS, detailS = self:runTask(stage, sha1)
      if not okS then
        error(tostring(stage) .. " extract failed: " .. tostring(detailS))
      end
      collectgarbage("collect")
    end
  end

  if not CacheFs.exists(GBA_ROOT .. "/maps.json") then
    writeJson(GBA_ROOT .. "/maps.json", { maps = {}, from_extract = true })
  end
  self:report(1.00, "Ready", 1, 1)
  return {
    romSha1 = sha1,
    extractOk = ok == true,
    pokemonOk = okPoke == true,
    auxOk = okAux == true,
    detail = detail,
  }
end

return RomExtractorGen3
