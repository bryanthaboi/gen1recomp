-- The engine's own content, registered into the catalog under owner
-- "engine" before any mod runs.  Overriding a vanilla record and overriding
-- a mod's record are then the same verb, each() always yields the whole
-- world, and a mod's cross-references resolve against real ids.
-- Every registrant hands over the table its module already reads, and
-- install deep-copies it on the way in: two loads must not share record
-- tables, or an edit through one dataset (hot reload, a test loading
-- twice) reaches the other and the module's own statics.  Functions ride
-- the copy by reference, so handlers keep their identity and the merged
-- value stays equal to the vanilla one -- the mod-free merge is a no-op.
-- Modules are required lazily -- the loader must not drag the battle and
-- script stacks in with it at require time.
local Logger = require("src.core.Logger")
local Merge = require("src.mods.Merge")
local Schemas = require("src.mods.Schemas")

local Builtins = {}

Builtins.OWNER = Schemas.ENGINE

-- registry name -> the module that owns its vanilla records.  Each exposes
-- registerInto(registry, data, owner).
local REGISTRANTS = {
  -- The one registrant that owns its whole target: R.type_chart rebuilds
  -- Data.type_chart.matchups AND .types from the op log, so whatever is not
  -- registered here is not in the merged chart.  TypeChart.registerInto
  -- already reads the matchup rows out of the dataset, but its TYPE records
  -- are the module's Gen 1 literals -- and on a Gold boot those replaced
  -- Gold's own 19 type records with Red's 15, dropping DARK, STEEL, BIRD and
  -- CURSE_TYPE outright and reverting every category to the Gen 1 split
  -- (src/battle/gen2/Damage.lua:isPhysical reads exactly this table).  A
  -- dataset that ships its own type records is authoritative over the
  -- module's fallback; Gen 1's extractor writes no `types`, so there the
  -- override loop finds nothing and behavior is unchanged.
  { name = "type_chart", modules = { "src.battle.TypeChart" },
    install = function(registry, modules, owner, data)
      modules[1].registerInto(registry, data, owner)
      local chart = data and data.type_chart
      for id, record in pairs(chart and chart.types or {}) do
        registry:override(id, record, owner)
      end
    end },
  { name = "statuses", from = "src.battle.Status" },
  { name = "move_effects", from = "src.battle.MoveEffects" },
  { name = "balls", from = "src.battle.Catching" },
  { name = "transitions", from = "src.render.BattleTransition" },
  { name = "growth_rates", from = "src.pokemon.Growth" },
  { name = "evolution_methods", from = "src.pokemon.Evolution" },
  { name = "commands", from = "src.script.Commands" },
  { name = "tokens", from = "src.render.TextBox" },
  -- plain data files with no owning module: registered from here
  { name = "rulesets", modules = { "src.battle.rulesets.gen1_faithful",
                                   "src.battle.rulesets.modern_clean" },
    install = function(registry, modules, owner)
      for _, ruleset in ipairs(modules) do
        registry:register(ruleset.name, ruleset, owner)
      end
    end },
  -- the per-trainer class records plus the three vanilla move-scoring
  -- layers, which share the registry under LAYER_1..LAYER_3
  { name = "ai_classes", modules = { "data.scripts.ai_classes",
                                     "src.battle.TrainerAI" },
    install = function(registry, modules, owner)
      for id, record in pairs(modules[1]) do
        registry:register(id, record, owner)
      end
      modules[2].registerInto(registry, nil, owner)
    end },
}

-- Gen 2 (Gold) reimplements the systems behind these registries, and since
-- Schemas.GEN2 routes them to their own Data paths the vanilla records that
-- land there have to be GOLD's, not Red's.  Seeding Red's would be worse than
-- seeding nothing: the ids collide (both games call it GREAT_BALL, and Red's
-- record carries no `multiplier`, so src/battle/gen2/Catching.lua would read
-- nil and quietly drop the x1.5), and Ai.layersFor walks the merged table for
-- mod-registered layers, so Red's LAYER_1..LAYER_3 would join Gold's scoring
-- passes.  A name mapped to `false` is seeded by nothing on Gold, which is the
-- right answer for `commands`: the Gen 2 VM's verb table is the mod verbs
-- alone (src/script/gen2/Vm.lua:runModCommand), and a Gen 1 row-list verb
-- handed Gold's ctx would find no runner on it.
--
-- Same registry NAMES throughout -- only the records differ, exactly as only
-- the target path differs in Schemas.GEN2.
local GEN2_REGISTRANTS = {
  -- src/battle/gen2/Battle.lua owns two registries, so it names its entry
  -- points rather than exposing one registerInto
  statuses = { from = "src.battle.gen2.Battle", fn = "registerStatusesInto" },
  move_effects = { from = "src.battle.gen2.Battle",
                   fn = "registerMoveEffectsInto" },
  item_effects = { from = "src.core.gen2.ItemEffects" },
  balls = { from = "src.battle.gen2.Catching" },
  ai_classes = { from = "src.battle.gen2.Ai" },
  evolution_methods = { from = "src.core.gen2.Evolution" },
  -- Gold's curves are coefficient rows in the extracted pokemon.lua, not
  -- records; the Gen 2 registrant wraps each one as the { expForLevel } record
  -- Gen 1's registry uses, so the registry keeps ONE record shape across both
  -- games and a mod writes a custom curve once.
  growth_rates = { from = "src.battle.gen2.Mon" },
  commands = false,
  -- The Gen 2-only content registries (Schemas.GEN1 gates every one of these
  -- under Gen 1, which is the mirror of the `false` rows in Schemas.GEN2).
  -- Four of the six are seeded here, from the module that holds the cart's own
  -- table; the other two merge onto a table that already exists when
  -- mods:load runs and so have no registrant, exactly as `maps` has none --
  -- `landmarks` onto the cache's gen2Landmarks.landmarks, and `held_items`
  -- onto the view src/core/Game2.lua builds from data.items.
  phone_contacts = { from = "src.core.gen2.Phone" },
  decorations = { from = "src.core.gen2.Decorations" },
  apricorns = { from = "src.core.gen2.Apricorns" },
  radio_channels = { from = "src.ui.gen2.MapRadio" },
}

-- the registrant list for one generation, in registration order: the Gen 1
-- entries with the reimplemented ones swapped out, then the Gen 2-only ones
-- (item_effects and the content five have no Gen 1 registrant to swap) in a
-- fixed order so two boots seed the same registries the same way
local GEN2_ONLY_ORDER = { "item_effects", "phone_contacts", "decorations",
                          "apricorns", "radio_channels" }

local function registrantsFor(generation)
  if generation ~= 2 then return REGISTRANTS end
  local out, taken = {}, {}
  for _, entry in ipairs(REGISTRANTS) do
    local swap = GEN2_REGISTRANTS[entry.name]
    if swap == nil then
      out[#out + 1] = entry
    elseif swap then
      taken[entry.name] = true
      out[#out + 1] = { name = entry.name, from = swap.from, fn = swap.fn }
    end
  end
  for _, name in ipairs(GEN2_ONLY_ORDER) do
    local swap = GEN2_REGISTRANTS[name]
    if swap and not taken[name] then
      out[#out + 1] = { name = name, from = swap.from, fn = swap.fn }
    end
  end
  return out
end

-- the registries the engine seeds, in registration order; the parity tests
-- read this to tell an engine-owned namespace from a stray one
function Builtins.registries(generation)
  local names = {}
  for i, entry in ipairs(registrantsFor(generation)) do names[i] = entry.name end
  return names
end

-- the top-level Data keys those registrations bring into existence: the
-- only namespaces a mod-free boot is allowed to add.  Routed per generation
-- for the same reason the merge is (Schemas.GEN2): on Gold the engine's own
-- statuses land in data.gen2Statuses, so gen2Statuses is the root that appears.
function Builtins.namespaceRoots(generation)
  local roots = {}
  for _, name in ipairs(Builtins.registries(generation)) do
    local spec = Schemas.REGISTRIES[name]
    local target = spec and Schemas.targetFor(name, spec, generation)
    if target then roots[target:match("^[^%.]+")] = true end
  end
  return roots
end

-- a module the build dropped disables its registry rather than the game:
-- the consumer still reads its own table, so vanilla keeps working
local function load(path, moduleLoader)
  local ok, module = pcall(moduleLoader or require, path)
  if ok then return module end
  Logger.warn("builtin registrations skipped for %s (%s)", path, tostring(module))
  return nil
end

-- the write verbs copy their payload before it lands; centralized here so
-- the isolation holds for every registrant instead of leaning on each
-- module to hand over fresh tables
local function isolate(registry)
  return setmetatable({
    register = function(_, id, value, owner)
      return registry:register(id, Merge.deepCopy(value), owner)
    end,
    override = function(_, id, value, owner)
      return registry:override(id, Merge.deepCopy(value), owner)
    end,
    patch = function(_, id, partial, owner)
      return registry:patch(id, Merge.deepCopy(partial), owner)
    end,
  }, { __index = registry })
end

function Builtins.install(content, data, generation, moduleLoader)
  for _, entry in ipairs(registrantsFor(generation)) do
    local registry = content[entry.name] and isolate(content[entry.name])
    if registry then
      if entry.install then
        local modules, complete = {}, true
        for i, path in ipairs(entry.modules) do
          modules[i] = load(path, moduleLoader)
          if modules[i] == nil then complete = false end
        end
        -- data is the fourth argument, not the second, so the existing
        -- installers keep their signature; only a registrant that seeds from
        -- the loaded dataset (type_chart) reaches for it
        if complete then
          entry.install(registry, modules, Builtins.OWNER, data)
        end
      else
        local module = load(entry.from, moduleLoader)
        -- entry.fn names the entry point for a module that owns more than one
        -- registry (Gold's Battle owns statuses and move_effects); the default
        -- is the registerInto every single-registry module exposes
        local into = module and module[entry.fn or "registerInto"]
        if into then into(registry, data, Builtins.OWNER) end
      end
    end
  end
end

return Builtins
