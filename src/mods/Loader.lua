local Json = require("src.link.Json")
local Logger = require("src.core.Logger")
local SaveData = require("src.core.SaveData")
local Data = require("src.core.Data")
local GameVersion = require("src.core.GameVersion")
local Version = require("src.core.Version")
local RequiredImports = require("src.mods.RequiredImports")
local Assets = require("src.render.Assets")
local ModUI = require("src.ui.ModUI")
local DateTime = require("src.core.DateTime")
local AssetTransform = require("src.mods.AssetTransform")
local Manifest = require("src.mods.Manifest")
local Merge = require("src.mods.Merge")
local ModTargets = require("src.mods.ModTargets")
local Registry = require("src.mods.Registry")
local SafePath = require("src.mods.SafePath")
local Sandbox = require("src.mods.Sandbox")
local Schemas = require("src.mods.Schemas")
local Semver = require("src.mods.Semver")
local Events = require("src.mods.Events")
local Gen2Compat = require("src.mods.Gen2Compat")
local Hooks = require("src.mods.Hooks")
local LegacyCompat = require("src.mods.LegacyCompat")
local Runtime = require("src.mods.Runtime")
local Steps = require("src.mods.Steps")
local Net = require("src.mods.Net")
local Job = require("src.mods.Job")

local Loader = {}
Loader.__index = Loader

local MOD_STATE_FILE = "mod_state.lua" -- legacy migration only
local OPTION_SCHEMAS_FILENAME = "mod_option_schemas.json"
local OPTION_SCHEMAS_VERSION = 1

-- The working tree's engine version is the "0.0.0-dev" placeholder that CI
-- restamps into the packed game.love (src/core/Version.lua:7), and it sorts
-- BELOW every release, so a checkout would fail every mod that names a
-- floor.  A placeholder is not a compatibility statement: skip the range
-- check rather than answer it wrong.  A stamped build checks as it always did.
-- Read at call time, not captured: a build stamps Version before this loads
-- and a test stamps it after.
local function devEngine()
  return Version.engine:match("^0%.0%.0%-") ~= nil
end

-- walk a dotted target path without creating anything; the base view a
-- registry folds against must never perturb Data on a mod-free boot
local function resolvePath(root, path)
  local node = root
  for key in path:gmatch("[^%.]+") do
    if type(node) ~= "table" then return nil end
    node = node[key]
  end
  return node
end

local function readManifest(fs, root)
  local raw, err = fs.read(root .. "/manifest.json")
  if not raw then return nil, err end
  local data, decodeErr = Json.decode(raw)
  if not data then return nil, decodeErr end
  local ok, manifest = pcall(Manifest.validate, data, root)
  if not ok then return nil, manifest end
  return manifest
end

-- the ordering contract every phase walks in: priority ascending, ties by id
local function orderedIds(mods, filter)
  local ids = {}
  for id, mod in pairs(mods) do
    if not filter or filter(mod) then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b)
    local pa, pb = mods[a].manifest.priority, mods[b].manifest.priority
    if pa == pb then return a < b end
    return pa < pb
  end)
  return ids
end

-- ------- the require gate
-- Two jobs in one interposition.  The engine_internals/network scan is
-- attribution only and stays dev-mode: it warns and delegates.  The
-- Sandbox.moduleDenial check is not -- require("io") would hand back
-- package.loaded.io and undo the whole mod environment -- so it is installed
-- in player builds too, for any boot that has mods on it.

local devShim = { installed = false, permissions = {}, warned = {}, depth = 0 }

-- The Gen 1 engine modules a Gold boot never instantiates.  Each one still
-- LOADS under Gen 2 -- require finds the file and hands back a module table --
-- so a mod that captures src.core.Game and reads Game.overworld gets nil for
-- the life of the process and its patches land on code nothing runs.  That is
-- the failure the generation gate exists to prevent, and it is worth naming
-- when a forced or gen2compat mod reaches for one anyway.  Gold's own
-- counterparts are src/core/Game2.lua and the src/*/gen2/ trees; the live
-- owner is in the game.ready payload and mod.world resolves per generation.
local GEN1_ONLY_MODULES = {
  ["src.core.Game"] = true,
  ["src.world.OverworldController"] = true,
  ["src.world.PikachuFollower"] = true,
  ["src.world.NPC"] = true,
  ["src.world.Collision"] = true,
  ["src.world.WorldAPI"] = true,
  ["src.world.Map"] = true,
  ["src.battle.BattleState"] = true,
  ["src.script.ScriptRunner"] = true,
  -- Not a dead patch but a dead SCRIPT: Gold's registry carries mod verbs
  -- only (src/mods/Builtins.lua:100), so every Gen 1 built-in in this table
  -- resolves here and then runs as nothing.
  ["src.script.Commands"] = true,
  -- Loads fine under Gold and paints Red's chrome over Gold's options screen,
  -- whose layout is one 18x16 box rather than four 20x4 ones.
  ["src.ui.OptionRows"] = true,
  ["src.ui.PartyMenu"] = true,
  ["src.ui.BoxMenu"] = true,
  ["src.ui.StartMenu"] = true,
  ["src.ui.OptionsMenu"] = true,
}

-- the src.* modules the mod surface points authors at: another mod's
-- exports carry a version string that wants range-checking before use, and
-- ChipAsm is the authoring path for chip music and sfx
local SUPPORTED_REQUIRES = {
  ["src.mods.Semver"] = true,
  ["src.audio.ChipAsm"] = true,
  ["src.pokemon.Stats"] = true, -- Stats.isShiny / calc for indicator mods
}

-- Where this file lives, so the shim can tell an engine require from a mod's:
-- a mod chunk is named after its own directory, and this is the only test that
-- survives a lazy require made long after Runtime.currentMod went back to nil.
local ENGINE_PREFIX = (debug.getinfo(1, "S").source or "")
  :gsub("^@", ""):gsub("mods[/\\]Loader%.lua$", "")

local function callerIsMod(level)
  if ENGINE_PREFIX == "" then return false end
  local info = debug.getinfo(level, "S")
  local source = info and info.source
  if not source or source:sub(1, 1) ~= "@" then return false end
  return source:sub(2, 1 + #ENGINE_PREFIX) ~= ENGINE_PREFIX
end

local function scanRequire(name)
  local modId = Runtime.currentMod
  if type(modId) ~= "string" then modId = Runtime.modRequire end
  if type(modId) ~= "string" or type(name) ~= "string" then return end
  local granted = devShim.permissions[modId] or {}
  local function warnOnce(permission)
    local key = modId .. "|" .. permission .. "|" .. name
    if devShim.warned[key] then return end
    devShim.warned[key] = true
    Logger.warn("[%s] undeclared %s require: %s", modId, permission, name)
  end
  -- A Gen 1-only module on a Gold boot is not a permissions question, it is a
  -- dead patch: reported once, attributed, and onto the boot error feed the
  -- manager shows the player rather than a dev-only log line.
  if devShim.generation ~= 1 and GEN1_ONLY_MODULES[name]
      and not Gen2Compat.serves(name) then
    local key = modId .. "|gen2|" .. name
    if not devShim.warned[key] then
      devShim.warned[key] = true
      local message = ("%s: requires %s, which a Gen 2 game never runs and "
        .. "src/mods/Gen2Compat.lua has no adapter for; take the game from "
        .. "the game.ready payload and mod.world")
        :format(modId, name)
      local errors = devShim.errors
      if errors then errors[#errors + 1] = message end
      Logger.error("%s", message)
    end
  end
  -- link modules are the one place a mod can reach the wire, so network is
  -- the permission that governs them
  if name:match("^src%.link%.") then
    if not granted.network then warnOnce("network") end
  elseif name:match("^src%.") and not SUPPORTED_REQUIRES[name]
      and not granted.engine_internals then
    warnOnce("engine_internals")
  end
end

-- the genuine require, captured before the shim can replace it
local rawRequire = require

-- a module the loader pulls in late on the mod's behalf.  The mod asked for
-- a facade, not for this module nor for whatever it drags in, so the whole
-- load runs at shim depth and neither level is attributed to the mod.
local function engineRequire(name)
  devShim.depth = devShim.depth + 1
  local ok, module = pcall(rawRequire, name)
  devShim.depth = devShim.depth - 1
  if not ok then return nil end
  return module
end

function Loader:_installDevShim()
  for id, mod in pairs(self.mods) do
    devShim.permissions[id] = mod.manifest.permissionSet
  end
  devShim.dev = self.dev
  if devShim.installed then return end
  devShim.installed = true
  local delegate = require
  _G.require = function(name, ...)
    -- only the mod's own call is the mod's doing; whatever that module
    -- requires in turn is the engine wiring itself up
    if devShim.depth == 0 then
      -- Backstop for the deny list Sandbox.envFor's require already applies:
      -- an engine module requiring io is the engine wiring itself up, a mod
      -- doing it is the hole this closes, and any future path that runs mod
      -- code without a sandbox env still lands here.
      local owner = Runtime.currentMod or Runtime.modRequire
      if owner or callerIsMod(3) then
        local id = type(owner) == "string" and owner or nil
        local denial = Sandbox.moduleDenial(name, devShim.permissions[id])
        if denial then error(("[%s] %s"):format(id or "mod", denial), 0) end
      end
      if devShim.dev or devShim.generation ~= 1 then scanRequire(name) end
      -- The Gen 1 name a mod asked for, answered by the Gen 2 arm behind it.
      -- Engine code keeps the real module: src/render/PaletteFX.lua:776
      -- requires src.core.Game on both generations and means it.
      if devShim.generation ~= 1 and Gen2Compat.serves(name)
          and (owner or callerIsMod(3)) then
        local adapter = Gen2Compat.resolve(name, Runtime.currentMod)
        if adapter then
          local key = "adapter|" .. name
          if not devShim.warned[key] then
            devShim.warned[key] = true
            Logger.info("gen2 facade: %s -> %s", name,
              tostring(Gen2Compat.ADAPTERS[name]))
          end
          return adapter
        end
      end
    end
    devShim.depth = devShim.depth + 1
    local ok, result = pcall(delegate, name, ...)
    devShim.depth = devShim.depth - 1
    if not ok then error(result, 0) end
    return result
  end
end

-- opts.fs injects a filesystem (read/getInfo/load/getDirectoryItems, plus
-- write where enable-state should persist) so the loader runs headless under
-- plain Lua; the default is love.filesystem.  opts.dev forces the dev-mode
-- tripwire on for tests that cannot set the environment.
function Loader.new(opts)
  local dev = opts and opts.dev
  if dev == nil then
    dev = os.getenv("POKEPORT_DEV") == "1" or _G.POKEPORT_DEV_MODE == true
  end
  local self = setmetatable({
    mods = {}, loaded = {}, errors = {}, initialized = false,
    events = Events.new(), hooks = Hooks.new(), content = {}, assets = {},
    exports = {}, migrations = {}, order = {},
    modSave = {}, modOptions = {}, optionSchemas = {}, imageCache = {},
    modInput = {}, modEnv = {}, stepsQueues = {},
    fs = (opts and opts.fs) or (love and love.filesystem),
    dev = dev,
    safeMode = false,
    -- Which generation this boot is (1 or 2).  Fixed at construction: the
    -- active version is set once in main.lua's bootGame before anything
    -- builds a loader, and a run never changes generation underneath one.
    -- opts.generation is the test seam.
    generation = (opts and opts.generation) or GameVersion.generation(),
  }, Loader)
  assert(self.fs, "Loader.new requires opts.fs when love is unavailable")
  -- Schemas.shapeFor, not the catalog spec: a registry whose Gen 2 records are
  -- shaped differently (a species' specialAttack/specialDefense, an encounter
  -- table keyed by kind, a trainer CLASS hanging off .classes) carries its Gen
  -- 2 shape beside the Gen 1 one, and resolving it once here is what makes
  -- every reader downstream generation-blind: Schemas.check off registry.spec,
  -- Registry's fold/baseAt/baseIds, _mergeOrder's depth and _merge's
  -- spec.write / spec.semantics all read this one spec and never ask again.
  -- Gen 1 and any registry with no Gen 2 shape get the catalog table itself.
  for name, spec in pairs(Schemas.REGISTRIES) do
    self.content[name] = Registry.new(name, Schemas.shapeFor(name, spec, self.generation))
  end
  self.disabled = {}
  self.gen2Forced = {}
  return self
end

-- The game this boot is, or nil when a harness injected a generation the
-- running version disagrees with (only the generation can be trusted then).
function Loader:_targetVersion()
  local version = GameVersion.get and GameVersion.get()
  if not (version and GameVersion.VERSIONS[version]) then return nil end
  if GameVersion.generation(version) ~= self.generation then return nil end
  return version
end

-- The version an enable flag is read and written under: this running game.
-- Reads and writes go through the same answer so the two can never drift.
function Loader:_enableScope()
  return SaveData.modScope(self:_targetVersion())
end

function Loader:_loadState()
  self.disabled = {}
  local options = SaveData.loadOptions(self.fs)
  -- The environment override is primarily for deterministic diagnostics and
  -- ROM-free integration boots: they must be able to start the vanilla
  -- engine even when the checkout/save directory contains enabled mods whose
  -- content targets a real ROM dataset.  It never persists or changes the
  -- player's saved safe-mode choice.
  self.safeMode = SaveData.isSafeMode(options)
    or os.getenv("POKEPORT_SAFE_MODE") == "1"
  Runtime.safeMode = self.safeMode
  local scope = self:_enableScope()
  local ids = {}
  for id in pairs(options.mods or {}) do ids[id] = true end
  local bucket = scope and (options.modsByVersion or {})[scope]
  if type(bucket) == "table" then
    for id in pairs(bucket) do ids[id] = true end
  end
  for id in pairs(ids) do
    if SaveData.modEnabled(options, id, scope) == false then
      self.disabled[id] = true
    end
  end
  -- the player's target override, resolved for THIS game: forcing a mod onto
  -- Gold never changes whether it runs on Red (SaveData.modForced)
  self.gen2Forced = {}
  for id in pairs(options.modsGen2 or {}) do
    if SaveData.modForced(options, id, self:_targetVersion(), self.generation) then
      self.gen2Forced[id] = true
    end
  end
  -- mod.options reads through this; M11 owns writing it back
  self.modOptions = options.modOptions or {}
  -- Migrate the original prototype manager's separate state file into the
  -- normal persistent options file once.  New Game never resets options.
  if next(options.mods or {}) == nil and self.fs.getInfo
      and self.fs.getInfo(MOD_STATE_FILE) then
    local chunk = self.fs.load(MOD_STATE_FILE)
    -- `chunk and pcall(chunk)` truncates to one value, so state came back nil
    -- however well the chunk ran and the migration below never fired once:
    -- the guard has to be a statement for pcall's second return to survive.
    local ok, state = false, nil
    if chunk then ok, state = pcall(chunk) end
    if ok and type(state) == "table" then
      for id, disabled in pairs(state) do
        if disabled then
          options.mods[id] = false
          self.disabled[id] = true
        end
      end
      if self.fs.write then SaveData.saveOptions(options, self.fs) end
    end
  end
end

function Loader:_saveState()
  -- a read-only injected fs keeps enable toggles in-memory only
  if not self.fs.write then return end
  local options = SaveData.loadOptions(self.fs)
  options.mods = options.mods or {}
  local scope = self:_enableScope()
  local version = self:_targetVersion()
  for id in pairs(self.mods) do
    SaveData.setModEnabled(options, id, not self.disabled[id], scope)
    -- only the games this boot can answer for: another version's overrides
    -- are not this run's to rewrite.  With no version (an injected-generation
    -- harness) the override stays in memory for this boot only.
    SaveData.setModForced(options, id, self.gen2Forced[id] == true, version)
  end
  SaveData.saveOptions(options, self.fs)
end

-- Export the runtime option schemas after mod entry chunks have run.  This
-- is an optional, data-only handoff for native launchers: they must not run
-- arbitrary mod code before boot just to discover settings.  The snapshot is
-- deliberately written beside options.lua so every platform's native shell
-- can use the same filesystem contract.
function Loader:_writeOptionSchemas()
  if not self.fs.write then return end

  local mods = {}
  for id, mod in pairs(self.mods) do
    if mod.enabled and not mod.failed then
      local schema = self.optionSchemas[id]
      -- Keep the legacy manifest options_schema path visible to native
      -- consumers too. ManagerState loads this same data-only chunk on
      -- demand; using it here means older mods do not need to migrate to
      -- mod.options:define just to appear in a launcher settings screen.
      if schema == nil and mod.manifest.options_schema and self.fs.load then
        local ok, rows = pcall(function()
          local path = SafePath.join(mod.path, mod.manifest.options_schema,
            "options_schema")
          local chunk = Sandbox.loadFile(self.fs, path, self:_modEnv(mod))
          return chunk and chunk()
        end)
        if ok and type(rows) == "table" then schema = rows end
      end
      if schema ~= nil then
        mods[id] = schema
      end
    end
  end

  -- Do not create storage on a fresh mod-free boot, but do overwrite an old
  -- snapshot when the current boot has no schemas so disabled/failed mods do
  -- not leave stale native settings rows behind.
  if next(mods) == nil
      and not (self.fs.getInfo and self.fs.getInfo(OPTION_SCHEMAS_FILENAME)) then
    return
  end

  local ok, encoded = pcall(Json.encode, {
    schema_version = OPTION_SCHEMAS_VERSION,
    mods = mods,
  })
  if not ok then
    Logger.warn("mod option schema export: failed to encode: %s", tostring(encoded))
    return
  end
  local written, err = self.fs.write(OPTION_SCHEMAS_FILENAME, encoded)
  if not written then
    Logger.warn("mod option schema export: failed to write: %s", tostring(err))
  end
end

function Loader:setEnabled(id, enabled)
  if self.safeMode then return false end
  if not self.mods[id] then return false end
  self.disabled[id] = not enabled
  self.mods[id].enabled = enabled
  self:_saveState()
  return true
end

-- Takes effect on the next boot, like every other load-time decision: the
-- gate runs once, before any entry chunk.  Second return is false when the
-- choice could not be persisted for a game, so the caller does not promise a
-- restart will honour it.
function Loader:setGen2Forced(id, forced)
  if self.safeMode then return false, false end
  if not self.mods[id] then return false, false end
  self.gen2Forced[id] = forced or nil
  self:_saveState()
  local persisted = self:_targetVersion() ~= nil and self.fs.write ~= nil
  if not persisted then
    Logger.warn("mod %s: target override kept for this boot only", id)
  end
  return true, persisted
end

function Loader:isGen2Forced(id)
  return self.gen2Forced[id] == true
end

function Loader:_discover()
  if not self.fs.getDirectoryItems then return end
  local roots = { "mods" }
  for _, root in ipairs(roots) do
    if self.fs.getInfo(root) then
      for _, name in ipairs(self.fs.getDirectoryItems(root)) do
        local path = root .. "/" .. name
        local info = self.fs.getInfo(path)
        -- a dev-linked mod dir (ln -s) reports type "symlink" even with
        -- setSymlinksEnabled(true) -- PhysFS never resolves the symlink's
        -- own getInfo, only traversal into it. readManifest below still
        -- correctly no-ops on a symlink that isn't a directory.
        if info and (info.type == "directory" or info.type == "symlink") then
          local manifest, err = readManifest(self.fs, path)
          if manifest then
            if self.mods[manifest.id] then
              self.errors[#self.errors + 1] =
                ("%s: duplicate mod id (ignored %s)"):format(manifest.id, path)
            else
              self.mods[manifest.id] = { manifest = manifest, path = path }
            end
          else
            Logger.warn("mod %s ignored: %s", path, tostring(err))
          end
        end
      end
    end
  end
end

-- ------- validate and resolve

-- a failed mod keeps the user's enable flag (the manager still shows it as
-- enabled-but-broken) and is treated as absent by every later phase
function Loader:_fail(mod, state, reason)
  if mod.failed then return end
  mod.failed, mod.state, mod.failure = true, state, reason
  self.errors[#self.errors + 1] = mod.manifest.id .. ": " .. reason
  Logger.error("mod %s failed: %s", mod.manifest.id, reason)
end

-- left out rather than broken: inactive like a failure, but off the boot
-- error list and rendered with its own manager row state (ManagerState:264)
function Loader:_skip(mod, state, reason)
  if mod.failed then return end
  mod.failed, mod.state, mod.skipReason = true, state, reason
  Logger.info("mod %s skipped: %s", mod.manifest.id, reason)
end

local function isActive(mod)
  return mod.enabled and not mod.failed
end

-- the Data path a registry merges into for THIS boot's generation, or nil
-- when it has no home here (Schemas.GEN2)
function Loader:_target(name, spec)
  return Schemas.targetFor(name, spec, self.generation)
end

-- Which games a mod runs on is opt-in per manifest (`games`, and the legacy
-- gen2compat it subsumes).  A mod that did not claim THIS game is left out of
-- the boot whole: not loaded, no registrations, no subscriptions.  The
-- alternative is what this replaces -- the mod loads, the manager shows it
-- enabled, and roughly four of its hooks out of a hundred actually fire --
-- which reads as a broken mod rather than an absent one.  This is a skip and
-- not a failure: it is not the mod's bug, so it stays off the boot error list
-- and out of the log's error stream, and the manager gives it its own row
-- state.
--
-- The gate is per VERSION, not only per generation: `games: ["blue"]` is a
-- claim about Blue, and the two mod UIs already say "For Blue, not Red" off
-- the same ModTargets answer, so enforcing it here is what makes that line a
-- verdict instead of a decoration.
--
-- The player owns the override.  The manifest is the AUTHOR's claim, and a mod
-- written before the field existed can never carry it, so `options.modsGen2`
-- (the manager's TRY HERE ANYWAY toggle, scoped to one game) forces one on for
-- this boot; a forced mod loads normally and keeps a note saying it was never
-- verified here.
function Loader:_gateGeneration()
  local version = self:_targetVersion()
  for _, id in ipairs(orderedIds(self.mods, isActive)) do
    local mod = self.mods[id]
    if ModTargets.supports(mod.manifest, version, self.generation) then
      -- nothing to say: the author claimed this game
    elseif self.gen2Forced[id] then
      mod.forcedGen2 = true
      mod.skipReason = ("forced onto this Gen %d game; not verified by its author")
        :format(self.generation)
      Logger.warn("mod %s: %s", id, mod.skipReason)
    elseif self.generation == 2 and not mod.manifest.gen2compat then
      -- the whole-generation miss keeps its own wording: gen2compat is the
      -- field the author has to add, so the skip line names it
      self:_skip(mod, "wrong_generation",
        ("not marked gen2compat; this is a Gen %d game"):format(self.generation))
    elseif version then
      -- claimed some game, just not this one (ModTargets.detail)
      self:_skip(mod, "wrong_generation", ModTargets.detail(mod.manifest, version))
    else
      -- worded from the loader's own generation, not from GameVersion's
      -- current id: the two agree in a real boot, and a harness that injects
      -- a generation should not produce a sentence naming the wrong game
      self:_skip(mod, "wrong_generation",
        ("not made for a Gen %d game"):format(self.generation))
    end
  end
end

function Loader:_exists(path)
  if not self.fs.getInfo then return true end
  return self.fs.getInfo(path) ~= nil
end

-- static per-manifest checks that need the filesystem or the engine version.
-- Enabled mods only: a mod the user switched off is not a boot problem
function Loader:_validate()
  for _, id in ipairs(orderedIds(self.mods, isActive)) do
    local mod = self.mods[id]
    local manifest = mod.manifest
    local reason
    if not self:_exists(mod.path .. "/" .. manifest.entry) then
      reason = "entry file missing: " .. manifest.entry
    elseif manifest.options_schema
        and not self:_exists(mod.path .. "/" .. manifest.options_schema) then
      reason = "options_schema file missing: " .. manifest.options_schema
    elseif manifest.assets_transforms
        and not self:_exists(mod.path .. "/" .. manifest.assets_transforms) then
      reason = "assets_transforms file missing: " .. manifest.assets_transforms
    end
    if not reason and #(manifest.required_imports or {}) > 0 then
      for _, import in ipairs(manifest.required_imports) do
        local path = mod.path .. "/baseroms/" .. import.file
        if not self:_exists(path) then
          reason = "required import missing: " .. import.name
          break
        end
        local valid, importErr = RequiredImports.validateStored(
          manifest, import, self.fs)
        if not valid then
          reason = "required import invalid: " .. import.name
            .. " (" .. tostring(importErr) .. ")"
          break
        end
      end
    end
    if not reason and manifest.game_version and not devEngine() then
      local ok, err = Semver.satisfies(Version.engine, manifest.game_version)
      if not ok then
        reason = ("needs game version %s, engine is %s")
          :format(manifest.game_version, Version.engine)
        if err then reason = reason .. " (" .. err .. ")" end
      end
    end
    if reason then self:_fail(mod, "invalid", reason) end
  end
end

-- hard dependencies must exist, be enabled, have survived, and satisfy their
-- range; run to a fixpoint so failures propagate to dependents transitively
function Loader:_enforceDependencies()
  local targetVersion = self:_targetVersion()
  local generation = self.generation
  local changed = true
  while changed do
    changed = false
    for _, id in ipairs(orderedIds(self.mods, isActive)) do
      local mod = self.mods[id]
      for _, spec in ipairs(mod.manifest.dependencySpecs) do
        if ModTargets.specApplies(spec, targetVersion, generation) then
          local dep = self.mods[spec.id]
          local reason, skip
          if not dep then
            reason = "missing dependency: " .. spec.id
          elseif not dep.enabled then
            reason = ("dependency %s is disabled"):format(spec.id)
          elseif dep.state == "wrong_generation" then
            -- the gate's skip is contagious as a SKIP, not as a failure: the
            -- dependency has no bug to report and neither does this mod, so
            -- nothing here lands on the boot error list
            skip = true
            -- carry the dependency's own reason: it names the game or the
            -- missing gen2compat, and a guess here would name the wrong one
            reason = ("depends on %s, which does not run here (%s)")
              :format(spec.id, dep.skipReason or "not made for this game")
          elseif dep.failed then
            reason = ("dependency %s failed to load"):format(spec.id)
          elseif spec.range
              and not Semver.satisfies(dep.manifest.version, spec.range) then
            reason = ("needs %s@%s, found %s")
              :format(spec.id, spec.range, dep.manifest.version)
          end
          if reason then
            if skip then
              self:_skip(mod, "wrong_generation", reason)
            else
              self:_fail(mod, "blocked_dependency", reason)
            end
            changed = true
            break
          end
        end
      end
    end
  end
end

-- Tarjan SCC over the hard-dependency graph: only a cycle's own members
-- fail, so an unrelated mod beside a cycle still loads
function Loader:_failCycles()
  local targetVersion = self:_targetVersion()
  local generation = self.generation
  local mods = self.mods
  local counter, stack, onStack, index, low = 0, {}, {}, {}, {}
  local cycles = {}
  local function connect(id)
    counter = counter + 1
    index[id], low[id] = counter, counter
    stack[#stack + 1] = id
    onStack[id] = true
    local selfEdge = false
    for _, spec in ipairs(mods[id].manifest.dependencySpecs) do
      if ModTargets.specApplies(spec, targetVersion, generation) then
        local dep = mods[spec.id]
        if spec.id == id then selfEdge = true end
        if dep and isActive(dep) and spec.id ~= id then
          if not index[spec.id] then
            connect(spec.id)
            if low[spec.id] < low[id] then low[id] = low[spec.id] end
          elseif onStack[spec.id] and index[spec.id] < low[id] then
            low[id] = index[spec.id]
          end
        end
      end
    end
    if low[id] == index[id] then
      local component = {}
      repeat
        local top = table.remove(stack)
        onStack[top] = false
        component[#component + 1] = top
      until top == id
      if #component > 1 or selfEdge then cycles[#cycles + 1] = component end
    end
  end
  for _, id in ipairs(orderedIds(mods, isActive)) do
    if not index[id] then connect(id) end
  end
  for _, component in ipairs(cycles) do
    table.sort(component)
    local trace = table.concat(component, " -> ") .. " -> " .. component[1]
    for _, id in ipairs(component) do
      self:_fail(mods[id], "blocked_dependency", "circular dependency: " .. trace)
    end
  end
end

-- the declaring mod loses: it asserted the incompatibility, and judging every
-- claim against one snapshot makes a mutual pair fail together
function Loader:_enforceConflicts()
  local doomed = {}
  for _, id in ipairs(orderedIds(self.mods, isActive)) do
    local mod = self.mods[id]
    for _, spec in ipairs(mod.manifest.conflictSpecs) do
      local other = self.mods[spec.id]
      if other and isActive(other)
          and (not spec.range
            or Semver.satisfies(other.manifest.version, spec.range)) then
        doomed[#doomed + 1] = { mod = mod,
          reason = ("conflicts with %s %s"):format(spec.id, other.manifest.version) }
        break
      end
    end
  end
  for _, entry in ipairs(doomed) do
    self:_fail(entry.mod, "conflict", entry.reason)
  end
end

-- Kahn over the surviving graph with the ready set kept in (priority, id)
-- order, so dependencies come first and the rest matches the v1 contract
function Loader:_order()
  local targetVersion = self:_targetVersion()
  local generation = self.generation
  local pending, indegree, dependents = {}, {}, {}
  for _, id in ipairs(orderedIds(self.mods, isActive)) do
    pending[id], indegree[id] = true, 0
  end
  for id in pairs(pending) do
    local manifest = self.mods[id].manifest
    local function edge(depId)
      if not pending[depId] or depId == id then return end
      dependents[depId] = dependents[depId] or {}
      dependents[depId][#dependents[depId] + 1] = id
      indegree[id] = indegree[id] + 1
    end
    for _, spec in ipairs(manifest.dependencySpecs) do
      if ModTargets.specApplies(spec, targetVersion, generation) then
        edge(spec.id)
      end
    end
    -- optional dependencies order without requiring anything
    for _, spec in ipairs(manifest.optionalSpecs) do
      if ModTargets.specApplies(spec, targetVersion, generation) then
        edge(spec.id)
      end
    end
  end
  local ordered = {}
  local function nextId()
    local best
    for id in pairs(pending) do
      if indegree[id] == 0 then
        if not best then
          best = id
        else
          local pa, pb = self.mods[id].manifest.priority,
            self.mods[best].manifest.priority
          if pa < pb or (pa == pb and id < best) then best = id end
        end
      end
    end
    if best then return best end
    -- optional dependencies can close a loop the hard-dependency cycle check
    -- deliberately ignores; break it at the lowest-ordered id rather than
    -- silently dropping the mods
    local leftovers = {}
    for id in pairs(pending) do leftovers[#leftovers + 1] = id end
    if #leftovers == 0 then return nil end
    table.sort(leftovers)
    Logger.warn("optional dependency loop broken at %s", leftovers[1])
    return leftovers[1]
  end
  while true do
    local id = nextId()
    if not id then break end
    pending[id], indegree[id] = nil, nil
    ordered[#ordered + 1] = self.mods[id]
    for _, dependent in ipairs(dependents[id] or {}) do
      if indegree[dependent] then indegree[dependent] = indegree[dependent] - 1 end
    end
  end
  return ordered
end

-- merge order is a property of the target paths, never of pairs(): a
-- whole-table registry ("audio") has to land before the granular ones nested
-- under it ("audio.sfx"), or its subtable swap discards every id they already
-- wrote into the object it replaces.  A strict prefix always has fewer
-- segments, so shallowest-first buys that; the name breaks ties so the same
-- content always merges the same way.
function Loader:_mergeOrder()
  local names, depth = {}, {}
  for name, registry in pairs(self.content) do
    names[#names + 1] = name
    local segments = 0
    -- the routed path, not spec.target: nesting is a property of where the
    -- content actually lands, and that is per generation (Schemas.GEN2)
    for _ in (self:_target(name, registry.spec) or ""):gmatch("[^%.]+") do
      segments = segments + 1
    end
    depth[name] = segments
  end
  table.sort(names, function(a, b)
    if depth[a] ~= depth[b] then return depth[a] < depth[b] end
    return a < b
  end)
  return names
end

function Loader:_resolve()
  self:_enforceDependencies()
  self:_failCycles()
  self:_enforceDependencies()
  self:_enforceConflicts()
  self:_enforceDependencies()
  return self:_order()
end

-- per-registry accessor bound to one mod: schema violations are load
-- errors for api 2 mods and attributed warnings for api 1 (compat), and a
-- deprecated name warns once per mod on first use
function Loader:_contentApi(mod, registry, deprecation)
  local loader = self
  local modId = mod.manifest.id
  local apiLevel = mod.manifest.api or 1
  local warned = false
  local function note()
    if deprecation and not warned then
      warned = true
      Logger.warn("[%s] %s", modId, deprecation)
    end
  end
  local function validate(mode, id, value)
    local ok, err = Schemas.check(registry.spec, registry.name, id, value, mode)
    if ok then return end
    if apiLevel >= 2 then error(err, 0) end
    Logger.warn("[%s] %s", modId, err)
  end
  -- A registry with no home in this generation (Schemas.routing) takes the
  -- write and drops it.  Reported once per mod per registry, into the same feed
  -- the manager shows, because a mod that declared gen2compat and then wrote
  -- here is owed the reason -- but NOT fatal: a mod that supports both
  -- generations registers its content unconditionally and should still load
  -- the half that does apply.
  --
  -- Worded from loader.generation, the way _gateGeneration's skipReason is,
  -- because the gating runs BOTH ways now: Schemas.GEN1 gates the six Gen
  -- 2-only registries (held_items, phone_contacts, decorations, apricorns,
  -- landmarks, radio_channels), so a Red boot rejecting a write to
  -- `decorations` must not claim it has "no Gen 2 target".
  local gated = Schemas.gatedFor(registry.name, loader.generation)
  local toldGated = false
  local function dropped()
    if not gated then return false end
    if not toldGated then
      toldGated = true
      local message = ("%s: the %s registry has no Gen %d target; those "
        .. "registrations do not apply here")
        :format(modId, registry.name, loader.generation)
      loader.errors[#loader.errors + 1] = message
      Logger.warn("%s", message)
    end
    return true
  end
  return {
    register = function(_, id, value)
      note()
      if dropped() then return nil end
      validate("register", id, value)
      loader:_journal(registry.name)
      return registry:register(id, value, modId)
    end,
    override = function(_, id, value)
      note()
      if dropped() then return nil end
      validate("override", id, value)
      loader:_journal(registry.name)
      return registry:override(id, value, modId)
    end,
    patch = function(_, id, partial)
      note()
      if dropped() then return nil end
      validate("patch", id, partial)
      loader:_journal(registry.name)
      return registry:patch(id, partial, modId)
    end,
    remove = function(_, id)
      note()
      if dropped() then return nil end
      loader:_journal(registry.name)
      return registry:remove(id, modId)
    end,
    get = function(_, id)
      note()
      return registry:get(id)
    end,
    each = function()
      note()
      return registry:each()
    end,
  }
end

-- mod.commands is sugar over the commands registry; the engine's own verbs
-- are registered there too, so replacing one has to say override
function Loader:_registerCommand(modId, verb, fn)
  assert(type(verb) == "string" and verb ~= "", "command verb is required")
  assert(type(fn) == "function", "command handler must be a function")
  self:_journal("commands")
  return self.content.commands:register(verb, fn, modId)
end

-- the GB buttons mod.input may drive (#807)
local GB_BUTTONS = {
  up = true, down = true, left = true, right = true,
  a = true, b = true, start = true, select = true,
}

-- per-mod mod.input ledger (#807): seq numbers this mod's Input sources,
-- tokens maps each opaque press token to what release must undo.  Living
-- on the loader (not the api closure) is what lets rollback, hot reload
-- and input recovery retire a mod's holds from outside the mod's own code.
function Loader:_modInput(modId)
  local bucket = self.modInput[modId]
  if not bucket then
    bucket = { seq = 0, tokens = {} }
    self.modInput[modId] = bucket
  end
  return bucket
end

-- Release every outstanding mod.input hold: one mod's on entry-chunk
-- rollback, everyone's (no argument) on hot reload and input recovery
-- (#807).  When Input:reset already dropped the sources these releases
-- are no-ops; the point is the stale tokens die with the code that took
-- them, so a later mod.input:release on one is refused instead of
-- touching a button someone else now holds.
function Loader:releaseModInput(modId)
  if modId == nil then
    for id in pairs(self.modInput) do self:releaseModInput(id) end
    return
  end
  local bucket = self.modInput[modId]
  if not bucket then return end
  self.modInput[modId] = nil
  for _, rec in pairs(bucket.tokens) do
    rec.input:sourceRelease(rec.btn, rec.source)
  end
end

function Loader:_api(mod)
  local loader = self
  local modId = mod.manifest.id
  local Storage = engineRequire("src.mods.Storage")
  local storage = Storage and Storage.new(modId, loader.fs)
  local Checkpoint = engineRequire("src.core.Checkpoint")
  local ImportAccess = engineRequire("src.mods.ImportAccess")
  local importApi, installCache = ImportAccess.new(mod.manifest, loader.fs)
  local api = {
    id = modId,
    version = mod.manifest.version,
    path = mod.path,
    -- a deep copy: what a mod does to its own view never reaches the loader
    manifest = Merge.deepCopy(mod.manifest),
    content = {},
    exports = {},
    DELETE = Registry.DELETE,
    events = {
      on = function(_, name, callback, priority)
        return loader.events:on(name, callback, priority, modId)
      end,
      once = function(_, name, callback, priority)
        return loader.events:once(name, callback, priority, modId)
      end,
      -- mods broadcast under their own prefix only, so no mod can forge an
      -- engine event; exports stay the call-style channel
      emit = function(_, name, payload)
        local prefix = "mod." .. modId .. "."
        if type(name) ~= "string" or name:sub(1, #prefix) ~= prefix then
          error(("[%s] mods may only emit %s* events"):format(modId, prefix), 0)
        end
        return loader.events:emit(name, payload)
      end,
    },
    hooks = { wrap = function(_, name, callback, priority)
      return loader.hooks:wrap(name, callback, priority, modId)
    end },
    -- source-safe scripted GB input (#807): tap queues exactly one
    -- wasPressed edge for the next fixed step with no held state; press
    -- holds until release.  Every call is its own "mod:<id>:<n>" source in
    -- game.input, so releasing a token can never drop a button the
    -- keyboard, a pad, the touch overlay, or another mod still holds.
    input = {
      tap = function(_, game, btn)
        local input = game and game.input
        assert(input, "mod.input needs the live game (see game.ready)")
        assert(GB_BUTTONS[btn], "unknown GB button: " .. tostring(btn))
        local bucket = loader:_modInput(modId)
        bucket.seq = bucket.seq + 1
        local source = "mod:" .. modId .. ":" .. bucket.seq
        input:sourcePress(btn, source)
        input:sourceRelease(btn, source)
      end,
      press = function(_, game, btn)
        local input = game and game.input
        assert(input, "mod.input needs the live game (see game.ready)")
        assert(GB_BUTTONS[btn], "unknown GB button: " .. tostring(btn))
        local bucket = loader:_modInput(modId)
        bucket.seq = bucket.seq + 1
        local source = "mod:" .. modId .. ":" .. bucket.seq
        input:sourcePress(btn, source)
        local token = {}
        bucket.tokens[token] = { input = input, btn = btn, source = source }
        return token
      end,
      -- idempotent, and a token another mod took is simply not in this
      -- ledger, so cross-mod release is refused by construction
      release = function(_, token)
        local bucket = loader.modInput[modId]
        local rec = bucket and bucket.tokens[token]
        if not rec then return false end
        bucket.tokens[token] = nil
        rec.input:sourceRelease(rec.btn, rec.source)
        return true
      end,
    },
    -- the widget toolkit facade (12 4.5) is one shared surface, not
    -- per-mod state; each widget inside it loads on first touch
    ui = ModUI,
    -- Read-only shared timestamp presentation using current options.lua
    -- preferences. The live game supplies only the current option context;
    -- checkpoint/save data never changes as a side effect.
    datetime = {
      date = function(_, game, timestamp) return DateTime.date(game, timestamp) end,
      time = function(_, game, timestamp) return DateTime.time(game, timestamp) end,
      dateTime = function(_, game, timestamp)
        return DateTime.dateTime(game, timestamp)
      end,
    },
    -- The read-only part of love.system that device UIs legitimately need.
    -- Do not expose the module: openURL and clipboard access stay sandboxed.
    device = {
      powerInfo = function()
        local getPowerInfo = love and love.system and love.system.getPowerInfo
        if not getPowerInfo then return "unknown", nil end
        local state, percent = getPowerInfo()
        return state, percent
      end,
    },
    -- The native step bridge (#1186), behind the "steps" permission the
    -- player sees in the mod manager: sync asks the platform to refresh
    -- its count, poll hands this mod its copy of what the bridge
    -- delivered.  The engine owns the pending file -- a mod never names a
    -- path, it only receives { steps, from, to }.  available() answers
    -- false without the permission (a probe stays quiet); the calls that
    -- would do something name the missing permission instead, the way the
    -- network gate does.
    steps = (function()
      if mod.manifest.permissionSet.steps then
        loader.stepsQueues[modId] = loader.stepsQueues[modId] or {}
        return {
          available = function() return Steps.available() end,
          sync = function() return Steps.sync() end,
          poll = function() return Steps.poll(loader, modId) end,
        }
      end
      local function refuse()
        error(('[%s] mod.steps needs the "steps" permission in '
          .. "manifest.json"):format(modId), 2)
      end
      return { available = function() return false end,
               sync = refuse, poll = refuse }
    end)(),
    -- Background HTTP, behind the "network" permission the player already
    -- sees.  This is what love.thread is NOT: the worker runs engine code in
    -- an engine-owned pool, so a mod gets asynchrony without getting a Lua
    -- state the sandbox cannot reach.  get() hands back an opaque handle;
    -- poll() is non-blocking, so nothing here can hang a frame.
    fetch = (function()
      if mod.manifest.permissionSet.network then
        return {
          available = function() return Net.available() end,
          get = function(_, url, opts) return Net.get(loader, modId, url, opts) end,
          poll = function(_, handle) return Net.poll(loader, modId, handle) end,
          release = function(_, handle) return Net.release(loader, modId, handle) end,
          cancel = function(_, handle) return Net.cancel(loader, modId, handle) end,
        }
      end
      local function refuse()
        error(('[%s] mod.fetch needs the "network" permission in '
          .. "manifest.json"):format(modId), 2)
      end
      return { available = function() return false end,
               get = refuse, poll = refuse, release = refuse, cancel = refuse }
    end)(),
    -- One-way crash-log reporting to the https URL the manifest declares in
    -- log_url.  The destination is reviewed at load, not chosen per call, so
    -- a mod cannot aim this at arbitrary hosts; the response body is never
    -- returned, and the worker pool bounds the transfer.  Same handle/poll/
    -- release shape as mod.fetch, so mod.job's sibling patterns carry over.
    postLog = (function()
      if mod.manifest.permissionSet.network and mod.manifest.log_url then
        return function(_, body, opts)
          return Net.postLog(loader, modId, mod.manifest.log_url, body, opts)
        end
      end
      local function refuse()
        error(('[%s] mod.postLog needs the "network" permission and a '
          .. "log_url in manifest.json"):format(modId), 2)
      end
      return refuse
    end)(),
    -- Background compute, behind the "background" permission.  The worker
    -- rebuilds this mod's sandbox before loading the script, so a job is the
    -- one thing love.thread is not: off the main thread without a Lua state
    -- that escapes the sandbox.  Plain data in, plain data out.
    job = (function()
      if mod.manifest.permissionSet.background then
        return {
          available = function() return Job.available() end,
          run = function(_, script, arg, opts)
            return Job.run(loader, modId, mod.path, script, arg, opts)
          end,
          poll = function(_, handle) return Job.poll(loader, modId, handle) end,
          release = function(_, handle) return Job.release(loader, modId, handle) end,
          cancel = function(_, handle) return Job.cancel(loader, modId, handle) end,
        }
      end
      local function refuse()
        error(('[%s] mod.job needs the "background" permission in '
          .. "manifest.json"):format(modId), 2)
      end
      return { available = function() return false end,
               run = refuse, poll = refuse, release = refuse, cancel = refuse }
    end)(),
    -- namespaced per mod; M11 backs these with save.modData /
    -- options.modOptions, the shape mods compile against is already final
    save = {
      get = function(_, key, default)
        local bucket = loader.modSave[modId]
        local value = bucket and bucket[key]
        if value == nil then return default end
        return value
      end,
      set = function(_, key, value)
        local bucket = loader.modSave[modId]
        if not bucket then
          bucket = {}
          loader.modSave[modId] = bucket
        end
        bucket[key] = value
      end,
    },
    -- Data-only and opaque-byte state independent of the vanilla progress
    -- checkpoint. The
    -- engine binds version/playthrough/mod scope and portable persistence;
    -- callers never receive paths or a raw filesystem handle.
    -- Read-only bounded access to this mod's manifest-declared, launcher-validated
    -- imports. No host path is exposed; large sources are read in bounded ranges.
    imports = importApi,
    -- Installation-scoped generated data, independent from Pokémon save slots.
    -- This is where ROM-derived caches belong; mod.storage remains playthrough-scoped.
    cache = installCache,
    storage = {
      context = function(_, game) return storage:context(game) end,
      selected = function(_, game) return storage:selected(game) end,
      write = function(_, game, key, value) return storage:write(game, key, value) end,
      read = function(_, game, key) return storage:read(game, key) end,
      writeBytes = function(_, game, key, bytes)
        return storage:writeBytes(game, key, bytes)
      end,
      readBytes = function(_, game, key) return storage:readBytes(game, key) end,
      list = function(_, game, prefix) return storage:list(game, prefix) end,
      delete = function(_, game, key) return storage:delete(game, key) end,
    },
    -- Runtime safety and reconstruction stay engine-owned. Checkpoints contain
    -- data only; no controller, stack, coroutine or renderer object crosses out.
    checkpoints = {
      inspect = function(_, game) return Checkpoint.inspect(game) end,
      capture = function(_, game) return Checkpoint.capture(game) end,
      restore = function(_, game, checkpoint)
        return Checkpoint.restore(game, checkpoint)
      end,
      resume = function(_, game, checkpoint)
        return Checkpoint.resume(game, checkpoint)
      end,
      ensureNormalSave = function(_, game, checkpoint)
        return Checkpoint.ensureNormalSave(game, checkpoint, loader.fs)
      end,
    },
    options = {
      define = function(_, schema)
        assert(type(schema) == "table", "options schema must be a table of rows")
        for _, row in ipairs(schema) do
          assert(type(row) == "table" and type(row.key) == "string" and row.key ~= "",
            "each options row needs a string key")
        end
        loader.optionSchemas[modId] = schema
        return schema
      end,
      get = function(_, key)
        local stored = loader.modOptions[modId]
        if stored ~= nil and stored[key] ~= nil then return stored[key] end
        for _, row in ipairs(loader.optionSchemas[modId] or {}) do
          if row.key == key then return row.default end
        end
        return nil
      end,
    },
    commands = { register = function(_, verb, fn)
      return loader:_registerCommand(modId, verb, fn)
    end },
    -- M11 runs these against save.meta; recording them is what M2 owes
    migrations = { add = function(_, since, fn)
      assert(type(since) == "string" and since ~= "",
        "migrations need the version they upgrade from")
      assert(type(fn) == "function", "migration must be a function")
      local list = loader.migrations[modId]
      if not list then
        list = {}
        loader.migrations[modId] = list
      end
      list[#list + 1] = { since = since, apply = fn }
      return fn
    end },
    log = {
      info = function(_, fmt, ...) Logger.info("[%s] " .. fmt, modId, ...) end,
      warn = function(_, fmt, ...) Logger.warn("[%s] " .. fmt, modId, ...) end,
      error = function(_, fmt, ...) Logger.error("[%s] " .. fmt, modId, ...) end,
    },
  }
  self.exports[modId] = api.exports
  -- a handle, not the mod object: {id, version, exports} or nil when the
  -- other mod is absent, disabled, failed, or has not run yet.  Tolerates
  -- mod:find(id) as well as the documented mod.find(id).
  api.find = function(first, second)
    local otherId = second == nil and first or second
    local other = loader.mods[otherId]
    if not other or not isActive(other) then return nil end
    local exports = loader.exports[otherId]
    if exports == nil then return nil end
    return { id = otherId, version = other.manifest.version, exports = exports }
  end
  for name, registry in pairs(self.content) do
    local deprecation = registry.spec.deprecated
      and ("the %s registry is deprecated; use %s")
        :format(name, registry.spec.deprecated.useInstead)
    api.content[name] = self:_contentApi(mod, registry, deprecation)
  end
  for alias, canonical in pairs(Schemas.ALIASES) do
    api.content[alias] = self:_contentApi(mod, self.content[canonical],
      ("the %s registry is deprecated; use %s"):format(alias, canonical))
  end
  -- A relative path inside this mod, or the mod root when relative is
  -- omitted.  Empty is the one listing case SafePath.safe rejects on
  -- purpose (it is not a file), so it is special-cased here.
  local function ownPath(relative, what)
    if relative == nil or relative == "" then return mod.path end
    return SafePath.join(mod.path, relative, what)
  end

  -- Shallow directory listing, the sandboxed stand-in for
  -- love.filesystem.getDirectoryItems.  Names only, sorted, never a host
  -- path.  A missing directory is an empty list, not an error.
  local function listOwn(_, relative)
    local dir = ownPath(relative, "mod:list")
    local fs = loader.fs
    if not (fs and fs.getDirectoryItems) then return {} end
    local items = fs.getDirectoryItems(dir) or {}
    local out = {}
    for i = 1, #items do out[i] = items[i] end
    table.sort(out)
    return out
  end

  -- love.filesystem.getInfo for a path inside this mod.  type is "file" or
  -- "directory"; size is set for files.  nil when the path does not exist.
  local function infoOwn(_, relative)
    local path = ownPath(relative, "mod:info")
    local fs = loader.fs
    if not (fs and fs.getInfo) then return nil end
    local info = fs.getInfo(path)
    if not info then return nil end
    return { type = info.type, size = info.size }
  end

  -- assets keeps the v1 alias to the content accessors and adds the file
  -- helpers on top, so mod.assets.pokemon and mod.assets:image both resolve
  api.assets = setmetatable({
    path = function(_, relative)
      return SafePath.join(mod.path, relative, "mod.assets:path")
    end,
    image = function(_, relative)
      local full = SafePath.join(mod.path, relative, "mod.assets:image")
      local cached = loader.imageCache[full]
      if cached then return cached end
      assert(love and love.graphics,
        ("[%s] mod.assets:image needs a graphics context"):format(modId))
      local image = love.graphics.newImage(full)
      loader.imageCache[full] = image
      return image
    end,
    list = listOwn,
    info = infoOwn,
  }, { __index = api.content })
  -- the mod's own directory and nothing above it: PhysFS already refuses a
  -- climb, but loader.fs is injectable and has no such floor
  function api:read(relative)
    return loader.fs.read(SafePath.join(self.path, relative, "mod:read"))
  end
  api.list = listOwn
  api.info = infoOwn
  -- mod.world materializes on first touch, like the image helper above: a
  -- headless load must not drag the world stack in, and the Game the facade
  -- acts on is still being wired when the entry chunk runs
  local world, battle
  setmetatable(api, { __index = function(_, key)
    -- mod.game is the live service owner, resolved per generation the way
    -- mod.world is: src/core/Game.lua's singleton under Gen 1, the Game2
    -- INSTANCE Gold injected under Gen 2.  Read on every touch rather than
    -- cached, because the Gen 1 singleton's stack and save fill in after the
    -- entry chunk runs.  This is what a mod should hold instead of requiring
    -- src.core.Game, which under Gold hands back a table nothing instantiated.
    if key == "game" then return loader:_game() end
    local game = loader:_game()
    if key == "battle" then
      if battle then return battle end
      local module = game and engineRequire(loader.generation == 2
        and "src.battle.gen2.BattleAPI" or "src.battle.BattleAPI")
      if not module then return nil end
      battle = module.new(game)
      return battle
    end
    if key ~= "world" then return nil end
    if world then return world end
    -- one facade name, one arm per generation: Gold's world is not a stack
    -- state and its flags are a bitfield, so the resolution differs even
    -- where the method set does not (src/world/gen2/WorldAPI.lua)
    local module = game and engineRequire(loader.generation == 2
      and "src.world.gen2.WorldAPI" or "src.world.WorldAPI")
    if not module then return nil end
    world = module.new(game, modId)
    return world
  end })
  return api
end

-- the live Game.  An injected reference wins so a headless caller can hand
-- over a stub; otherwise the boot singleton, whose stack and overworld fill
-- in after this loader returns -- holding the table keeps the facade live.
--
-- Gen 2 has no fallback to reach for: src/core/Game.lua is the Gen 1 service
-- owner and a Gold boot never loads it, so returning it would hand mod.world a
-- live-looking object with no stack, no save and no overworld.  Gold injects
-- itself (src/core/Game2.lua), and nil here is the honest answer if it
-- somehow did not.
function Loader:_game()
  if self.game then return self.game end
  if self.generation ~= 1 then return nil end
  return engineRequire("src.core.Game")
end

-- The environment every chunk this mod authors runs in, built once per mod so
-- its entry file and its options_schema share one globals table.
function Loader:_modEnv(mod)
  local id = mod.manifest.id
  local env = self.modEnv[id]
  if not env then
    local loader = self
    local compat = LegacyCompat.new({
      modId = id, modPath = mod.path, fs = self.fs,
      game = function() return loader:_game() end,
    })
    env = Sandbox.envFor({ modId = id, permissions = mod.manifest.permissionSet,
      compat = compat })
    self.modEnv[id] = env
  end
  return env
end

-- Which pre-sandbox calls each loaded mod actually took, for the manager's
-- "needs updating" badge; nil id answers for every mod.
function Loader:legacyReport(modId)
  return LegacyCompat.report(modId)
end

function Loader:_loadMod(mod)
  local path = SafePath.join(mod.path, mod.manifest.entry, "manifest entry")
  local chunk, err = Sandbox.loadFile(self.fs, path, self:_modEnv(mod))
  if not chunk then error(err or ("unable to load " .. path)) end
  local api = self:_api(mod)
  local result = chunk(api)
  if type(result) == "function" then result(api) end
  -- a mod that replaced the table wholesale (mod.exports = {...}) still
  -- publishes what its dependents will see
  self.exports[mod.manifest.id] = api.exports
end

-- remember which registries a mod touched so a failing entry chunk can be
-- undone with one owner-wide op purge per registry
function Loader:_journal(name)
  local journal = self.journal
  if journal then journal[name] = true end
end

-- a failing mod leaves zero residue: its ops are dropped before the merge
-- loop ever runs, and every subscription, export, command, option schema and
-- migration it took goes with them.  The journal only exists around an
-- entry chunk; a later failure (script validation) purges every registry.
function Loader:_rollback(modId)
  for name in pairs(self.journal or self.content) do
    self.content[name]:rollback(modId)
  end
  self.events:removeOwner(modId)
  self.hooks:removeOwner(modId)
  self:releaseModInput(modId)
  self.exports[modId] = nil
  self.optionSchemas[modId] = nil
  self.migrations[modId] = nil
  self.modSave[modId] = nil
  self.stepsQueues[modId] = nil
  Net.releaseAll(self, modId)
  Job.releaseAll(self, modId)
end

-- a mod that explicitly swears it stays link-compatible while writing into a
-- link-relevant registry gets one attributed warning; the default for a
-- content profile is not a claim, so only a written affects_link is judged.
-- The fingerprint itself is derived from merged data either way (M12)
function Loader:_checkLinkClaims(mod)
  if mod.manifest.raw.affects_link ~= false then return end
  for name, registry in pairs(self.content) do
    if Manifest.LINK_REGISTRIES[name] then
      for _, list in pairs(registry.ops) do
        for _, entry in ipairs(list) do
          if entry.owner == mod.manifest.id then
            Logger.warn("[%s] declares affects_link = false but writes to %s",
              mod.manifest.id, name)
            return
          end
        end
      end
    end
  end
end

-- ------- script validation (09 §4.9)

-- Every row list reachable from a map_scripts contribution is checked
-- against the merged command set once all entry chunks have run, before the
-- merge writes the chains home.  Findings fail an api 2 owner outright --
-- the mod is purged like an entry-chunk error -- while api 1 and engine
-- owners keep the v1 runtime skip and get attributed warnings.
function Loader:_validateScripts()
  local registry = self.content.map_scripts
  if not registry or next(registry.ops) == nil then return end
  local MapScripts = engineRequire("src.script.MapScripts")
  if not MapScripts then return end
  local commands = self.content.commands
  local function lookup(verb) return commands:get(verb) ~= nil end
  local failed = false
  for mapId in pairs(registry.ops) do
    local chain = registry:chain(mapId)
    local owners = registry:chainOwners(mapId)
    for i = 1, #chain do
      local findings = MapScripts.validateContribution(chain[i], lookup)
      if #findings > 0 then
        local owner = owners[i]
        local mod = owner and self.mods[owner]
        local reason = ("map_scripts %s: %s"):format(mapId,
          table.concat(findings, "; "))
        if mod and (mod.manifest.api or 1) >= 2 then
          self:_fail(mod, "failed", reason)
          failed = true
        else
          Logger.warn("[%s] %s", tostring(owner or Schemas.ENGINE), reason)
        end
      end
    end
  end
  if not failed then return end
  -- purge the failed mods and whatever dependency enforcement takes with
  -- them, exactly as an entry-chunk failure would have
  self:_enforceDependencies()
  for i = #self.loaded, 1, -1 do
    local mod = self.loaded[i]
    if mod.failed then
      self:_rollback(mod.manifest.id)
      table.remove(self.loaded, i)
    end
  end
  for i = #self.order, 1, -1 do
    local mod = self.mods[self.order[i]]
    if mod and mod.failed then table.remove(self.order, i) end
  end
end

-- ------- audio provenance
-- An audio def only fails when its cue fires, long after the load phase has
-- handed its report to the manager, so the merge leaves behind who wrote
-- each def for Music/Sound to name in the failure (13.3).  Engine records
-- stay unstamped on purpose: they resolve to "base", which Runtime.reportError
-- keeps out of the manager's error feed because no mod can be blamed for them.

local AUDIO_OWNERS = {
  music = "songs", sfx = "sfx", cries = "cries", map_songs = "mapSongs",
}

local function stampAudioOwners(data, name, registry)
  local key = AUDIO_OWNERS[name]
  if not key then return end
  local owners = Data.ensure(data, "audio._owners")
  local map = owners[key] or {}
  for id in pairs(registry.ops) do
    local owner = registry.owners[id]
    -- a tombstoned id has no def left to attribute, and a resurrected one
    -- belongs to whoever wrote it last
    if owner == nil or owner == Schemas.ENGINE or registry:get(id) == nil then
      map[id] = nil
    else
      map[id] = owner
    end
  end
  owners[key] = map
end

function Loader:load(data)
  self.baseData = data
  -- every registry folds against the pristine view of its Data target;
  -- resolution is lazy so optional namespaces may appear later
  for name, registry in pairs(self.content) do
    local target = self:_target(name, registry.spec)
    if target then
      registry.base = function()
        return data and resolvePath(data, target)
      end
    end
  end
  -- vanilla content is registrations too, and they land before discovery so
  -- a mod's register collides with the engine's and has to say override
  -- the generation decides WHICH module owns a registry's vanilla records:
  -- Gold reimplements the battle rules, so its own statuses/balls/AI records
  -- go in instead of Red's, not beside them (src/mods/Builtins.lua)
  require("src.mods.Builtins").install(self.content, data, self.generation)
  self:_loadState()
  self:_discover()
  if self.safeMode then
    for id in pairs(self.mods) do self.disabled[id] = true end
  end
  -- Existing installs stored one shared answer.  Once their manifests are
  -- known, split that answer across every game before the next launcher/game
  -- toggle can change one independently.  _loadState already used the same
  -- fallback, so this write cannot change the current boot's result.
  do
    local options = SaveData.loadOptions(self.fs)
    local installed = {}
    for id, mod in pairs(self.mods) do
      installed[#installed + 1] = {
        id = id,
        experimental = mod.manifest and mod.manifest.experimental == true,
      }
    end
    if SaveData.migrateModEnablement(options, installed) and self.fs.write then
      SaveData.saveOptions(options, self.fs)
    end
  end
  -- Experimental mods stay off until the player opts in: a missing
  -- options.mods entry normally means enabled, but experimental flips that.
  do
    local options = SaveData.loadOptions(self.fs)
    local scope = self:_enableScope()
    for id, mod in pairs(self.mods) do
      if not self.disabled[id] and SaveData.modEnabled(options, id, scope) == nil
          and mod.manifest.experimental then
        self.disabled[id] = true
      end
    end
  end
  -- A manifest may name an env var that force-enables it regardless of a
  -- saved disable in options.mods -- generic, not tied to any mod id, for
  -- a mod (e.g. a native-launcher bridge) that cannot function disabled on
  -- the one build where its env var is set.
  for id, mod in pairs(self.mods) do
    local envName = mod.manifest.force_enable_env
    if not self.safeMode and envName and os.getenv(envName) == "1" then
      self.disabled[id] = nil
    end
  end
  for id, mod in pairs(self.mods) do
    mod.enabled = not self.disabled[id]
    mod.state = mod.enabled and "pending" or "disabled"
  end
  -- engine call sites reach these buses -- and this error feed, for failures
  -- that only surface at play time -- through Runtime from here on
  Runtime.install(self.events, self.hooks, self.errors)
  -- before _validate: a mod that is not running on this generation should not
  -- also be reported for a missing entry file it will never be asked for
  self:_gateGeneration()
  self:_validate()
  local ordered = self:_resolve()
  -- The shim is a process singleton, so whichever loader is running owns these
  -- two: a harness that builds a Gen 1 loader after a Gen 2 one must not keep
  -- reporting against the old generation or the old error feed.
  devShim.generation = self.generation
  devShim.errors = self.errors
  -- The Gen 1 Game facade proxies THIS loader's live game, and reads it on
  -- every touch: a mod captures the facade at file scope, before Game2 has a
  -- save or a world (src/mods/Gen2Compat.lua).
  Gen2Compat.bind(function() return self:_game() end)
  -- Any boot with mods on it needs the gate, because require("io") is how a
  -- mod would walk out of Sandbox.envFor.  Dev mode adds the permissions
  -- tripwire on top, and a Gold boot the Gen 1-only require report -- the
  -- difference between "the mod does nothing" and knowing why.  A boot with no
  -- mods pays nothing.
  if self.dev or next(self.mods) ~= nil then
    self:_installDevShim()
  end
  for _, mod in ipairs(ordered) do
    -- a mod ahead of this one may have failed and taken its dependents with
    -- it, so the order list is filtered as it is walked
    if isActive(mod) then
      local modId = mod.manifest.id
      self.journal = {}
      -- the dev tripwire attributes requires to whoever is running
      Runtime.currentMod = modId
      local success, err = pcall(self._loadMod, self, mod)
      Runtime.currentMod = nil
      if not success then self:_rollback(modId) end
      self.journal = nil
      if success then
        mod.state = "loaded"
        self.loaded[#self.loaded + 1] = mod
        self.order[#self.order + 1] = modId
        self:_checkLinkClaims(mod)
        Logger.info("loaded mod %s %s", modId, mod.manifest.version)
      else
        self:_fail(mod, "failed", tostring(err))
        self:_enforceDependencies()
      end
    end
  end
  -- the commands registry is final once every entry chunk has run, so
  -- each map_scripts contribution's rows can be judged before they merge
  self:_validateScripts()
  -- merge: fold every touched id from its pristine base value and write it
  -- home, creating the Data namespace when the base modules never shipped
  -- one.  A registry nobody wrote to -- engine included -- is skipped, so
  -- the namespaces that appear are exactly the ones with content behind them.
  for _, name in ipairs(self:_mergeOrder()) do
    local registry = self.content[name]
    local spec = registry.spec
    local path = self:_target(name, spec)
    if data and path and next(registry.ops) ~= nil then
      local target = Data.ensure(data, path)
      if spec.write then
        -- ids that do not map one-to-one onto target keys (type_chart's
        -- ordered rows, battle_anims' per-kind subtables) place themselves
        spec.write(target, registry)
      elseif spec.semantics == "compose" then
        for id in pairs(registry.ops) do
          local chain = registry:chain(id)
          if #chain == 0 then
            -- an emptied chain still has to say which kind of empty it is:
            -- a tombstone keeps the (empty) chain so the consumer drops its
            -- own base contribution too, while a chain nobody wrote to
            -- leaves the id untouched and base dispatches as it always did
            if registry:chainReplacesBase(id) then
              target[id] = { replacesBase = true }
            else
              target[id] = nil
            end
          else
            -- owner records ride the chain under a named key ipairs
            -- skips, so the consumer can attribute each contribution
            -- (map_scripts builds runner sources from these)
            local owners = registry:chainOwners(id)
            for i = 1, #chain do
              local owner = owners[i]
              local mod = owner and self.mods[owner]
              owners[i] = { modId = mod and owner or nil,
                            strict = mod and (mod.manifest.api or 1) >= 2 or nil }
            end
            chain.owners = owners
            -- an override chain is a total conversion: the consumer must
            -- leave its own base contribution out (09 4.4)
            chain.replacesBase = registry:chainReplacesBase(id) or nil
            target[id] = chain
          end
        end
      else
        local tombstones = {}
        for id in pairs(registry.ops) do
          local value = registry:get(id)
          if value == nil then
            tombstones[#tombstones + 1] = id
          else
            target[id] = value
          end
        end
        -- tombstones survive the fold as an explicit delete pass so
        -- consumers see the id as absent, not as a stale record
        for _, id in ipairs(tombstones) do target[id] = nil end
      end
      stampAudioOwners(data, name, registry)
    end
  end
  -- dangling f.id references are attributed to the id's last writer;
  -- api 1 mods keep the warning-only compat path
  if data then
    for _, problem in ipairs(Schemas.crossValidate(self, data)) do
      local ownerMod = problem.owner and self.mods[problem.owner]
      local apiLevel = ownerMod and (ownerMod.manifest.api or 1) or 1
      local message = tostring(problem.owner or "?") .. ": " .. problem.message
      if apiLevel >= 2 then
        self.errors[#self.errors + 1] = message
        Logger.error("%s", message)
      else
        Logger.warn("%s", message)
      end
    end
  end
  -- content freezes at the merge boundary; the event/hook buses stay open
  -- so mods may subscribe at any point for the life of the process
  for _, registry in pairs(self.content) do
    registry:freeze()
  end
  -- the load set is final here, so every surviving mod's recipe builds its
  -- derived art before the resolver is first asked to serve it; stamped, so
  -- a boot that changed nothing pays only the stat
  AssetTransform.run(self)
  -- and the same final load set becomes the asset search path, so an
  -- overrides/ file or a transform's output shadows the generated cache
  -- from the next image load on.  No mods means an empty search path,
  -- which resolves every path to itself (14 §asset resolution).
  Assets.installLoader(self)
  self.events:emit("mods.loaded", { loader = self, data = data })
  self:_writeOptionSchemas()
  self.initialized = true
  return #self.errors == 0
end

-- the manager reads api, profile, permissions, per-mod state and the load
-- order from here; enabled stays the user's flag so a failed mod still
-- renders as enabled-but-broken instead of silently switching itself off
function Loader:status()
  local available, loaded = {}, {}
  for _, mod in pairs(self.mods) do
    local manifest = {}
    for key, value in pairs(mod.manifest) do manifest[key] = value end
    manifest.enabled = mod.enabled ~= false
    manifest.safeMode = self.safeMode == true
    manifest.state = mod.state or (manifest.enabled and "loaded" or "disabled")
    manifest.error = mod.failure
    -- set instead of `error` when the mod was left out for a reason that is
    -- not a fault of the mod (today: the gen2compat gate)
    manifest.note = mod.skipReason
    -- the player's override, which the manager offers on a Gen 2 boot for a
    -- mod whose author never claimed one
    manifest.gen2Forced = self.gen2Forced[mod.manifest.id] == true
    available[#available + 1] = manifest
    if manifest.state == "loaded" then loaded[#loaded + 1] = manifest end
  end
  table.sort(available, function(a, b) return a.id < b.id end)
  table.sort(loaded, function(a, b) return a.id < b.id end)
  return { available = available, loaded = loaded, errors = self.errors,
    order = self.order }
end

return Loader
