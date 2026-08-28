-- Single source of truth for the registry catalog: per-registry merge
-- semantics (record | deep | compose), the Data target path each merge
-- writes, and the value schema every mod registration is checked against.
-- The loader builds its registries from this table and the reference docs
-- are generated from it, so neither can drift from the engine.
-- Pure Lua, no love.*, so the headless loader and doc generator run it.
local Merge = require("src.mods.Merge")

local Schemas = {}

-- ------- field-type combinators

local f = {}
Schemas.f = f

local function leaf(kind, desc, check)
  return { kind = kind, desc = desc, check = check }
end

f.str = leaf("str", "string", function(v) return type(v) == "string" end)
f.num = leaf("num", "number", function(v) return type(v) == "number" end)
f.bool = leaf("bool", "boolean", function(v) return type(v) == "boolean" end)
f.fn = leaf("fn", "function", function(v) return type(v) == "function" end)
f.any = leaf("any", "any value", function() return true end)
f.path = leaf("path", "file path", function(v)
  return type(v) == "string" and v ~= ""
end)
f.token = leaf("token", "text token name", function(v)
  return type(v) == "string" and v:match("^[%w_:%*]+$") ~= nil
end)

function f.int(min, max)
  local desc = "integer"
  if min and max then desc = ("integer %d..%d"):format(min, max)
  elseif min then desc = ("integer >= %d"):format(min) end
  return { kind = "int", min = min, max = max, desc = desc,
    check = function(v)
      return type(v) == "number" and v % 1 == 0
        and (min == nil or v >= min) and (max == nil or v <= max)
    end }
end

-- a bounded float; like f.int but keeps the fractional part (scales,
-- gains).  Rejects out-of-range with the "expected number a..b" message.
function f.numRange(min, max)
  local desc = "number"
  if min and max then desc = ("number %s..%s"):format(min, max)
  elseif min then desc = ("number >= %s"):format(min) end
  return { kind = "num", min = min, max = max, desc = desc,
    check = function(v)
      return type(v) == "number"
        and (min == nil or v >= min) and (max == nil or v <= max)
    end }
end

function f.enum(values)
  local set = {}
  for _, value in ipairs(values) do set[value] = true end
  local desc = 'one of "' .. table.concat(values, '" | "') .. '"'
  return { kind = "enum", set = set, values = values, desc = desc,
    check = function(v) return set[v] == true end }
end

function f.opt(inner)
  return { kind = "opt", inner = inner, desc = inner.desc }
end

function f.list(inner)
  return { kind = "list", inner = inner, desc = "list of " .. inner.desc }
end

function f.map(key, value)
  return { kind = "map", key = key, value = value,
    desc = ("map of %s -> %s"):format(key.desc, value.desc) }
end

-- opts.strict closes the record to unknown fields even at the extensible
-- top level.  A union alternative whose fields are ALL optional needs this:
-- with top-level leniency it matches every table, so the union stops
-- rejecting anything (the font "ttf" shape was the first such alternative).
function f.rec(fields, opts)
  local names = {}
  for name in pairs(fields) do names[#names + 1] = name end
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do
    local ft = fields[name]
    parts[#parts + 1] = name .. (ft.kind == "opt" and "?" or "")
  end
  return { kind = "rec", fields = fields, strict = opts and opts.strict or nil,
    desc = "{" .. table.concat(parts, ", ") .. "}" }
end

-- An open record: the listed fields are typed (including f.id
-- cross-references) and everything else on the value passes through
-- unexamined, unlike f.rec's nested shapes, which reject any key they do
-- not name.  Map objects are why this exists -- NPCs, signs, items, warps
-- and static encounters all share one array, and only a full union of
-- every kind's shape could describe it as f.rec; that is a lot of surface
-- to keep in sync with the loader for fields nothing here needs to check.
-- f.partial types just the field that actually names another registry and
-- leaves every kind-specific field around it alone.
function f.partial(fields)
  local names = {}
  for name in pairs(fields) do names[#names + 1] = name end
  table.sort(names)
  local parts = {}
  for _, name in ipairs(names) do
    local ft = fields[name]
    parts[#parts + 1] = name .. (ft.kind == "opt" and "?" or "")
  end
  return { kind = "partial", fields = fields,
    desc = "{" .. table.concat(parts, ", ") .. ", ...}" }
end

function f.union(alts)
  local parts = {}
  for _, alt in ipairs(alts) do parts[#parts + 1] = alt.desc end
  return { kind = "union", alts = alts, desc = table.concat(parts, " | ") }
end

-- cross-registry reference; the type check at register time is string-only,
-- resolution happens in the post-merge pass so forward references work
function f.id(registry)
  return { kind = "id", registry = registry, desc = registry .. " id",
    check = function(v) return type(v) == "string" and v ~= "" end }
end

-- ------- validation

-- snake_case/camelCase typos normalize to the same key, which is how the
-- classic base_stats-for-baseStats mistake gets a suggestion
local function normalizeName(name)
  return tostring(name):lower():gsub("_", "")
end

local function suggest(fields, unknown)
  local want = normalizeName(unknown)
  for known in pairs(fields) do
    if normalizeName(known) == want then return known end
  end
  return nil
end

local function got(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) == "table" then return "table" end
  return tostring(value)
end

local function fail(errors, path, expected, value)
  errors[#errors + 1] = ("%s: expected %s, got %s"):format(path, expected, got(value))
end

-- top marks the outermost value of a spec.value registry; opt and union
-- re-dispatch on the same value so they carry it, descending drops it
local checkValue
checkValue = function(t, value, path, patchMode, errors, top)
  if value == Merge.DELETE then
    if not patchMode then fail(errors, path, t.desc, value) end
    return
  end
  local kind = t.kind
  if kind == "any" then return end
  if kind == "opt" then return checkValue(t.inner, value, path, patchMode, errors, top) end
  if kind == "list" then
    if type(value) ~= "table" then return fail(errors, path, t.desc, value) end
    -- lists replace wholesale, so every row is a complete value even
    -- inside a patch; an extension wrapper carries the same rows and is
    -- typed the same way instead of slipping through unseen
    if Merge.isWrapper(value) then
      for _, key in ipairs({ "__prepend", "__append" }) do
        for i, element in ipairs(value[key] or {}) do
          checkValue(t.inner, element, ("%s.%s[%d]"):format(path, key, i),
            false, errors)
        end
      end
      return
    end
    for i, element in ipairs(value) do
      checkValue(t.inner, element, path .. "[" .. i .. "]", false, errors)
    end
    return
  end
  if kind == "map" then
    if type(value) ~= "table" then return fail(errors, path, t.desc, value) end
    for k, v in pairs(value) do
      if not t.key.check(k) then
        fail(errors, path .. "." .. tostring(k), "key " .. t.key.desc, k)
      end
      checkValue(t.value, v, path .. "." .. tostring(k), patchMode, errors)
    end
    return
  end
  if kind == "rec" then
    if type(value) ~= "table" then return fail(errors, path, t.desc, value) end
    for key, sub in pairs(value) do
      local ft = t.fields[key]
      if ft == nil then
        -- the top-level record stays extensible like the spec.fields path:
        -- unknown keys are preserved unless they read as a typo of a known
        -- field.  Nested recs stay strict, that is where typos hide.
        local hint = suggest(t.fields, key)
        if hint or not top or t.strict then
          errors[#errors + 1] = ("%s.%s: unknown field%s"):format(path, tostring(key),
            hint and (' (did you mean "' .. hint .. '"?)') or "")
        end
      else
        checkValue(ft, sub, path .. "." .. tostring(key), patchMode, errors)
      end
    end
    if not patchMode then
      for key, ft in pairs(t.fields) do
        if value[key] == nil and ft.kind ~= "opt" then
          errors[#errors + 1] = ("%s.%s: missing required field (%s)")
            :format(path, key, ft.desc)
        end
      end
    end
    return
  end
  if kind == "partial" then
    -- the open counterpart of "rec": listed fields are checked exactly
    -- like a rec's, and any key not listed is left alone rather than
    -- flagged, so a heterogeneous blob (map objects) can have one field
    -- typed without every other shape sharing the array being rejected
    if type(value) ~= "table" then return fail(errors, path, t.desc, value) end
    for key, ft in pairs(t.fields) do
      local sub = value[key]
      if sub ~= nil then
        checkValue(ft, sub, path .. "." .. tostring(key), patchMode, errors)
      elseif ft.kind ~= "opt" and not patchMode then
        errors[#errors + 1] = ("%s.%s: missing required field (%s)")
          :format(path, key, ft.desc)
      end
    end
    return
  end
  if kind == "union" then
    for _, alt in ipairs(t.alts) do
      local scratch = {}
      checkValue(alt, value, path, patchMode, scratch, top)
      if #scratch == 0 then return end
    end
    return fail(errors, path, t.desc, value)
  end
  if not t.check(value) then fail(errors, path, t.desc, value) end
end

-- mode is "register" | "override" (full record: required fields enforced),
-- "patch" (only provided leaves checked, DELETE legal) or "remove" (no
-- value).  Unknown top-level fields are allowed and preserved -- extensible
-- records are a feature -- but a patch key that is only a case/underscore
-- variant of a schema field is the classic typo and gets rejected with a
-- suggestion.
--
-- `generation` is optional and only ever narrows: passing it resolves the
-- per-generation shape first (Schemas.shapeFor), and omitting it validates
-- against the Gen 1 shape, which is what every Gen 1 call site wants and what
-- a caller already holding a derived spec has anyway.
function Schemas.check(spec, registryName, id, value, mode, generation)
  if generation ~= nil then
    spec = Schemas.shapeFor(registryName, spec, generation)
  end
  if mode == "remove" or spec == nil then return true end
  -- register and patch are synonyms on a deep registry, so a partial
  -- payload is the normal case there and only override is a full value
  local patchMode = mode == "patch"
    or (spec.semantics == "deep" and mode == "register")
  local errors = {}
  local path = registryName .. "." .. tostring(id)
  if spec.keys or spec.keyValue then
    -- deep registries are open namespaces: a key the catalog does not
    -- describe is a mod's own data, not a mistake.  keyValue types every
    -- key alike, for namespaces whose keys are content (one per map).
    local keyType = (spec.keys and spec.keys[id]) or spec.keyValue
    if keyType then checkValue(keyType, value, path, patchMode, errors, true) end
  elseif spec.value then
    checkValue(spec.value, value, path, patchMode, errors, true)
    if #errors == 0 and not patchMode and spec.extra then
      local problem = spec.extra(id, value)
      if problem then errors[#errors + 1] = ("%s: %s"):format(path, problem) end
    end
  elseif spec.fields then
    if type(value) ~= "table" then
      fail(errors, path, "record table", value)
    else
      for key, sub in pairs(value) do
        local ft = spec.fields[key]
        if ft ~= nil then
          checkValue(ft, sub, path .. "." .. tostring(key), patchMode, errors)
        elseif patchMode then
          local hint = suggest(spec.fields, key)
          if hint then
            errors[#errors + 1] = ('%s.%s: unknown field (did you mean "%s"?)')
              :format(path, tostring(key), hint)
          end
        end
      end
      if not patchMode then
        for key, ft in pairs(spec.fields) do
          if value[key] == nil and ft.kind ~= "opt" then
            errors[#errors + 1] = ("%s.%s: missing required field (%s)")
              :format(path, key, ft.desc)
          end
        end
      end
      if #errors == 0 and not patchMode and spec.extra then
        local problem = spec.extra(id, value)
        if problem then
          errors[#errors + 1] = ("%s: %s"):format(path, problem)
        end
      end
    end
  end
  if #errors == 0 then return true end
  return nil, table.concat(errors, "; ")
end

-- ------- cross-reference pass

local collectRefs
collectRefs = function(t, value, path, out)
  if value == nil or value == Merge.DELETE then return end
  local kind = t.kind
  if kind == "opt" then return collectRefs(t.inner, value, path, out) end
  if kind == "id" then
    if type(value) == "string" then
      out[#out + 1] = { registry = t.registry, ref = value, path = path }
    end
    return
  end
  if kind == "list" and type(value) == "table" then
    for i, element in ipairs(value) do
      collectRefs(t.inner, element, path .. "[" .. i .. "]", out)
    end
  elseif kind == "map" and type(value) == "table" then
    for k, v in pairs(value) do
      collectRefs(t.value, v, path .. "." .. tostring(k), out)
    end
  elseif (kind == "rec" or kind == "partial") and type(value) == "table" then
    for key, ft in pairs(t.fields) do
      collectRefs(ft, value[key], path .. "." .. tostring(key), out)
    end
  elseif kind == "union" then
    -- refs live in whichever alternative the value satisfies
    for _, alt in ipairs(t.alts) do
      local scratch = {}
      checkValue(alt, value, path, true, scratch)
      if #scratch == 0 then return collectRefs(alt, value, path, out) end
    end
  end
end

-- every f.id ref reachable from one record, tagged with its field path
local function refsFor(spec, name, id, value)
  local refs = {}
  if spec.keys or spec.keyValue then
    local keyType = (spec.keys and spec.keys[id]) or spec.keyValue
    if keyType then
      collectRefs(keyType, value, name .. "." .. tostring(id), refs)
    end
  elseif spec.fields and type(value) == "table" then
    for key, ft in pairs(spec.fields) do
      collectRefs(ft, value[key], name .. "." .. tostring(id) .. "." .. key, refs)
    end
  elseif spec.value then
    collectRefs(spec.value, value, name .. "." .. tostring(id), refs)
  end
  return refs
end

-- a structured target (battle_anims' per-kind subtables, Gold's trainer
-- classes) hides its ids one level down, so the pristine scan asks the spec
-- instead of the raw keys
local function baseEntries(spec, base)
  if not spec.baseIds then return pairs(base) end
  local ids = spec.baseIds(base)
  local i = 0
  return function()
    i = i + 1
    local id = ids[i]
    if id == nil then return nil end
    return id, spec.baseAt(base, id)
  end
end

-- runs once after the merge.  Records mods touched are scanned for dangling
-- refs (the op logs limit that, so a mod-free boot does zero work); if any
-- id folded to nil the scan widens to the untouched base records too, so a
-- remove that strands a vanilla reference is caught and attributed to the
-- removing mod instead of surfacing as an unowned crash later.  References
-- into registries the catalog does not declare yet are skipped, not guessed.
function Schemas.crossValidate(loader, data)
  local problems = {}
  local tombstoned, removed = {}, false
  for name, registry in pairs(loader.content) do
    for id in pairs(registry.ops) do
      if registry:get(id) == nil then
        tombstoned[name] = tombstoned[name] or {}
        tombstoned[name][id] = true
        removed = true
      end
    end
  end
  for name, registry in pairs(loader.content) do
    -- the shape this boot's generation validates by, so a Gen 2 record's
    -- refs are read out of the Gen 2 fields (a species' `into`, not
    -- `species`) instead of being missed entirely
    local spec = Schemas.shapeFor(name, registry.spec, loader.generation)
    for id in pairs(registry.ops) do
      local value = registry:get(id)
      if value ~= nil and registry.owners[id] ~= Schemas.ENGINE then
        for _, ref in ipairs(refsFor(spec, name, id, value)) do
          local refRegistry = Schemas.REGISTRIES[ref.registry]
            and loader.content[ref.registry]
          -- A registry with no home in this generation has no id space to
          -- check against: its base view resolves to nothing, so EVERY
          -- reference into it would read as dangling.  `transitions` is the
          -- standing example -- Gold draws its own battle intro and never
          -- reads the merged table, so a mod's transition id there is
          -- unconfirmable, not wrong.  `growth_rates` and `evolution_methods`
          -- used to sit in that category too, back when Gold had no id space
          -- for either.  Both are routed now: `growth_rates` keeps its Gen 1
          -- path and is seeded from data.pokemon.growthRates (the extractor's
          -- Gold curves, src/battle/gen2/Mon.lua), and `evolution_methods`
          -- routes to gen2EvolutionMethods (src/core/gen2/Evolution.lua's
          -- literal EVOLVE_* ids, present with or without a ROM import).  A
          -- Gold species' growthRate or evolution method is checked against
          -- real ids exactly like a Red one's, so a genuine typo is still
          -- caught here rather than waved through as "unknown, not wrong."
          if refRegistry and Schemas.gatedFor(ref.registry, loader.generation) then
            refRegistry = nil
          end
          if refRegistry and refRegistry:get(ref.ref) == nil then
            problems[#problems + 1] = {
              owner = registry.owners[id],
              message = ("%s: unresolved reference to %s %q")
                :format(ref.path, ref.registry, ref.ref),
            }
          end
        end
      end
    end
    if removed then
      local base = registry.base and registry.base()
      if base then
        for id, value in baseEntries(spec, base) do
          if registry.ops[id] == nil then
            for _, ref in ipairs(refsFor(spec, name, id, value)) do
              local set = tombstoned[ref.registry]
              if set and set[ref.ref] then
                problems[#problems + 1] = {
                  owner = loader.content[ref.registry].owners[ref.ref],
                  message = ("%s: unresolved reference to removed %s %q")
                    :format(ref.path, ref.registry, ref.ref),
                }
              end
            end
          end
        end
      end
    end
  end
  return problems
end

-- ------- the catalog

-- v1 registry names that live on as thin views of a renamed registry; both
-- names share one op log and diagnostics report the canonical name
Schemas.ALIASES = { scripts = "map_scripts", ui = "screens" }

-- owner of the engine's own registrations (src/mods/Builtins.lua); vanilla
-- content is internally consistent by construction, so the cross-reference
-- pass skips it and stays zero-work on a mod-free boot
Schemas.ENGINE = "engine"

-- ------- generation routing
--
-- Registry NAMES are shared across generations on purpose: a mod writes
-- mod.content.pokemon whichever game is running, and mod.content.encounters
-- means "wild encounters" in both.  What can differ is the Data path the
-- merge lands on, because Gold namespaces the tables whose Gen 1 counterpart
-- means something else (data.gen2Palettes beside data.palettes).
--
-- One routing table per generation, read through Schemas.routing, and both
-- are read the same way:
--
--   absent            -> keeps spec.target in that generation
--   mapped to a path  -> merges there instead
--   mapped to false   -> no home in that generation; the write is taken,
--                        dropped and reported
--
-- That last case is the whole point of the manifest's gen2compat opt-in: a
-- mod that claims Gen 2 gets told which registry has no home there instead of
-- merging into a table nothing reads and appearing to work.  It runs in both
-- directions, because the catalog now holds content BOTH ways round: Gold has
-- systems Red never had (the phone book, the decorations, the radio dial), and
-- those registries are the mirror image of the rows below -- declared once,
-- gated under GEN ONE, reported to a Red mod in the same sentence a Gold mod
-- gets about `tokens`.  Schemas.GEN1 below Schemas.GEN2 carries them.
--
-- The `false` rows used to have three causes and now have one.  The first is
-- gone: Gold's overworld tables no longer load off disk into World fields --
-- src/core/Game2.lua:load reads every one of them into game.data BEFORE it
-- calls mods:load(self.data), and src/world/gen2/World.lua:dataTable takes
-- them by reference and never copies, so a routed row merges into the very
-- table the world walks.  The second is gone too: a registry whose Gen 2
-- records are shaped differently now says so in its own spec (the gen2Fields /
-- gen2Keys layer below, resolved by Schemas.shapeFor), so routing it validates
-- a mod's record against the GEN 2 shape rather than against Red's.  What is
-- left is the systems Gold has not reimplemented through a registry at all.
Schemas.GEN2 = {
  -- Namespaced on Gold and merged there.  The registry NAME stays shared --
  -- mod.content.maps means "maps" in both games -- and only the Data path
  -- underneath it differs, which is the whole reason this table maps to paths
  -- rather than renaming anything.  Two id-space notes an author needs, and
  -- docs/mod-api-gen2-compat.md spells out: Gold's `text` ids are ROM pointer
  -- strings ("55:4067") rather than TEXT_* names, and a Gen 2 tileset carries
  -- its walkability as `collision` where Gen 1 says `walkable`.
  maps = "gen2Maps", tilesets = "gen2Tilesets", sprites = "gen2Sprites",
  text = "gen2Text",
  -- Namespaced AND differently shaped, and the shape is what these waited on.
  -- Each carries a Gen 2 record schema in its catalog entry now, so the id
  -- space is the one Gold actually keys by: the encounter KIND (.grass), the
  -- trainer CLASS (one level into .classes, through gen2Write), a species id
  -- or an ICON_ sheet name, and for palettes / battle_anims / constants the
  -- target's own subtable names.
  encounters = "gen2Encounters", trainers = "gen2Trainers",
  palettes = "gen2Palettes", icons = "gen2Icons",
  battle_anims = "gen2BattleAnims", constants = "gen2Constants",
  -- Gold reimplements the system, and reads its rules back through the same
  -- registry: src/battle/gen2/Battle.lua:statusRecordFor / moveEffectRecordFor,
  -- Catching.recordFor, Ai.layersFor, Evolution.methodFor and
  -- src/core/gen2/ItemEffects.lua:recordFor each read the merged table here
  -- and fall back to their own module records when no loader ran.  The vanilla
  -- records at these paths are GOLD's, not Red's -- src/mods/Builtins.lua
  -- swaps the registrant per generation, which it has to: both games call it
  -- GREAT_BALL.
  statuses = "gen2Statuses", move_effects = "gen2MoveEffects",
  item_effects = "gen2ItemEffects", balls = "gen2Balls",
  ai_classes = "gen2AiClasses", evolution_methods = "gen2EvolutionMethods",
  -- The Gen 2-only six.  They have no Gen 1 target to keep (their specs carry
  -- none), so the routed path IS the only path they ever have, and the
  -- Schemas.GEN1 rows below are what makes writing to one on Red a reported
  -- drop rather than a merge into a table Red has never heard of.  Two of them
  -- merge onto a table that already exists when mods:load runs -- landmarks
  -- onto the cache's own gen2Landmarks.landmarks, held_items onto the view
  -- src/core/Game2.lua builds from data.items -- and the other four come
  -- into existence AS the merge, seeded from their module's literals by
  -- src/mods/Builtins.lua the way the battle-rule six are.
  held_items = "gen2HeldItems", phone_contacts = "gen2PhoneContacts",
  decorations = "gen2Decorations", apricorns = "gen2Apricorns",
  landmarks = "gen2Landmarks.landmarks", radio_channels = "gen2RadioChannels",
  -- Still no Gen 2 home.  Every one of these is a system Gold reimplements
  -- WITHOUT reading a registry: the Gen 1 target is still built and merged
  -- into, but nothing in a Gold boot ever looks at it.  Closing one is a
  -- consumer change in the Gen 2 module first and a row here second, which is
  -- exactly how battle_sprite_scales and render_pipelines came off this list
  -- (see the note under it).
  --   rulesets        no Gen 2 ruleset dispatch exists
  --   transitions     Gold draws its own battle intro
  --                   (src/ui/gen2/BattleTransition.lua) and its STYLES table
  --                   is a boolean SET of the four cart wipes, not the
  --                   { frames, draw, sound, flash } record this registry
  --                   carries; there is no styleDef lookup for a mod id to
  --                   reach, so a registered style would fall back to vanilla
  --   field           the overworld grab bag; Gold's equivalents live in
  --                   gen2Maps and the VM's own tables
  --   text_pointers   Gen 1's TEXT_* indirection; Gold's text IS pointers
  --   link_fields     link play is Gen 1 only
  rulesets = false, transitions = false,
  field = false, text_pointers = false, link_fields = false,
  -- battle_sprite_scales and render_pipelines are ABSENT from this table on
  -- purpose: both keep the shared Gen 1 target because Gold reads the merged
  -- table at that exact path.
  --   battle_sprite_scales  src/ui/gen2/BattleState.lua:imageScale reads
  --                         data.battle_sprite_scales with the same
  --                         image-then-species-then-default order as Gen 1's
  --                         BattleState.imageBattleScale / resolveBattleScale,
  --                         skipping the `_owners` bookkeeping row the same
  --                         way.  Only the DEFAULT differs and neither side
  --                         reads it from here: Red's 32x32 back pics draw at
  --                         2x, Gold's 48x48 ones fill their 6x6 box at 1x.
  --   render_pipelines      src/core/Game2.lua:load calls Pipelines.install
  --                         AFTER the merge, so data.render_pipelines is the
  --                         merged table, and Game2:draw composites `present`
  --                         through Pipelines.wantsPresent / Pipelines.present.
  --                         The `drawWorld` half is not composited yet (Gold's
  --                         overworld draws straight to the window rather than
  --                         into a canvas), and Game2 RETIRES a restored
  --                         drawWorld-only level rather than leaving it
  --                         switched on and rendering nothing; a mod that
  --                         registers only drawWorld is therefore inert on
  --                         Gold, which docs/mod-api-gen2-compat.md says in
  --                         those words.  Gold also has no OPTION row for a
  --                         pipeline (Pipelines.rows is read only from
  --                         src/ui/OptionsMenu.lua), so a Gold player reaches
  --                         one by its hotkey.
  -- src/script/gen2/Vm.lua is a bytecode VM over the cart's own opcodes, not
  -- the Gen 1 row-list runner.  `commands` IS routed (it is absent from this
  -- table, so it keeps the shared data.commands target): the VM dispatches the
  -- Opcodes.MOD_COMMAND row -- an op name with no cart byte behind it --
  -- through that merged table, so mod.commands:register works on both games.
  -- data.gen2Scripts is that bytecode pool keyed by ROM pointer, so
  -- `map_scripts` has no home there: a Lua row list merged into it is not
  -- something the VM can run.  (`tokens` used to sit on this line and does
  -- not belong there -- TextBox.new runs TextBox.substitute on EVERY box in
  -- both generations and substitute reads game.data.tokens, so the shared
  -- target was already live on Gold.  It keeps that target, absent from this
  -- table, and src/core/Game2.lua seeds data.tokens with a copy of
  -- TextBox.TOKENS so the merge cannot mutate the module table.)
  map_scripts = false,
  -- Everything not listed keeps its Gen 1 target and works on Gold today:
  -- pokemon, moves, items, type_chart, audio + music/sfx/cries/map_songs,
  -- screens (the Gen2* ids in src/ui/Screens.lua), strings, font and commands.
}

-- The mirror of Schemas.GEN2: what a GEN 1 boot does with the registries that
-- only exist because Gold exists.  Same three readings as the table above, and
-- only the third is used today -- there is no Gen 2-only registry with a
-- useful Red target to reroute to, because the systems themselves are absent
-- from Red rather than spelled differently there.
--
--   held_items      Red's items carry no held attributes at all; the whole
--                   hold/trigger machinery is Gen 2 (src/battle/gen2/Battle.lua
--                   heldEffect)
--   phone_contacts  no Pokegear, no phone
--   decorations     no bedroom PC decoration menu
--   apricorns       no Kurt, no apricorn balls
--   landmarks       Red's town map is a Gen 1 town-map table, not the
--                   LANDMARK_* index space the Pokegear and the #DEX AREA
--                   page share
--   radio_channels  no radio
Schemas.GEN1 = {
  held_items = false, phone_contacts = false, decorations = false,
  apricorns = false, landmarks = false, radio_channels = false,
}

-- The routing table for a generation: which one is consulted is the only
-- difference between the two directions.  An unknown generation routes
-- nothing, so every registry keeps its catalog target.
local NO_ROUTING = {}

function Schemas.routing(generation)
  if generation == 2 then return Schemas.GEN2 end
  if generation == 1 then return Schemas.GEN1 end
  return NO_ROUTING
end

-- The Data path `name` merges into for a generation, or nil when the registry
-- has no home there.
function Schemas.targetFor(name, spec, generation)
  local routed = Schemas.routing(generation)[name]
  if routed == nil then return spec.target end
  return routed or nil
end

-- true when the registry exists but this generation has nowhere to put it,
-- which is a different diagnostic from a registry that has no target at all
function Schemas.gatedFor(name, generation)
  return Schemas.routing(generation)[name] == false
end

-- ------- per-generation record shapes
--
-- Routing says WHERE a registration lands; this says what a record at that
-- path LOOKS like.  The two are separate questions and only the second one is
-- gating the rest of the catalog: Gold's tables are the Gen 2 ROM's own
-- layout, so a species carries specialAttack/specialDefense where Red carries
-- one `special`, wild encounters key by encounter kind and time of day rather
-- than by map, and the palette table is GBC four-colour rows in a dozen named
-- subtables.  Validating any of those against the Gen 1 schema judges a mod's
-- record against the wrong shape, which is worse than refusing the write.
--
-- So beside `value` / `fields` / `keys` / `keyValue` a spec may carry
-- `gen2Value` / `gen2Fields` / `gen2Keys` / `gen2KeyValue`, and beside
-- `semantics` / `extra` / `write` / `baseAt` / `baseIds` / `reservedIds` /
-- `example` / `notes` the matching `gen2*`.  Absent means "the Gen 1 shape is
-- right here too", which is the common case and why most registries carry
-- none of this.
-- The registry NAME, the verbs and (wherever the id space allows it) the ids
-- stay shared, exactly as the routing table keeps them shared.
--
-- `gen2X = false` CLEARS the Gen 1 slot rather than setting it, the same
-- reading `false` has in the routing table above: battle_anims' Gen 1 `write`
-- routes ids into per-kind subtables by prefix, and under Gen 2 the ids ARE
-- the subtables, so the right Gen 2 write is the default one.  No slot here
-- ever carries a meaningful `false` (they are functions, strings and tables),
-- so the two readings cannot collide.
--
-- Schemas.shapeFor resolves it.  It hands back the spec unchanged for Gen 1
-- and for any registry with no Gen 2 shape; otherwise a derived spec with the
-- gen2* keys folded onto the canonical names, memoized per spec so the
-- resolve is one table lookup after the first call.  Everything downstream --
-- Schemas.check, Registry's fold and baseAt, the loader's merge and write --
-- then reads one spec and never learns about generations.
local GEN2_SHAPE = {
  gen2Value = "value", gen2Fields = "fields", gen2Keys = "keys",
  gen2KeyValue = "keyValue", gen2Extra = "extra",
  gen2Semantics = "semantics", gen2Write = "write",
  gen2BaseAt = "baseAt", gen2BaseIds = "baseIds",
  gen2ReservedIds = "reservedIds",
  gen2Example = "example", gen2Notes = "notes",
}

-- Schemas.check reads these four in a fixed order (keys/keyValue, then value,
-- then fields), so a Gen 2 shape that describes its records with `keys` must
-- clear the Gen 1 `value` rather than sit beside it: otherwise the first
-- branch that matches wins and the new schema is never consulted.
local VALUE_SLOTS = { value = true, fields = true, keys = true, keyValue = true }

-- Weak keys: a derived spec lives exactly as long as the catalog entry it
-- came from, which in a headless harness is per require rather than forever.
-- Keyed by spec alone, which is sound because the catalog gives every
-- registry its own table -- the two ALIASES resolve to the canonical name
-- before anything reaches here, and `target` is the only name-dependent
-- field a derived spec carries.
local derivedSpecs = setmetatable({}, { __mode = "k" })

-- does this registry describe its Gen 2 records differently at all?
function Schemas.hasGen2Shape(spec)
  if type(spec) ~= "table" then return false end
  for source in pairs(GEN2_SHAPE) do
    if spec[source] ~= nil then return true end
  end
  return false
end

-- The spec to validate and merge `name` with under `generation`.  Idempotent:
-- a derived spec carries no gen2* keys, so resolving one again returns it.
function Schemas.shapeFor(name, spec, generation)
  if generation ~= 2 or not Schemas.hasGen2Shape(spec) then return spec end
  local hit = derivedSpecs[spec]
  if hit then return hit end
  local out = {}
  for key, value in pairs(spec) do out[key] = value end
  local replacesValue = false
  for source, slot in pairs(GEN2_SHAPE) do
    if spec[source] ~= nil and VALUE_SLOTS[slot] then replacesValue = true end
  end
  if replacesValue then
    for slot in pairs(VALUE_SLOTS) do out[slot] = nil end
  end
  for source, slot in pairs(GEN2_SHAPE) do
    out[source] = nil
    -- `or nil` is the clear: gen2Write = false leaves the slot empty
    if spec[source] ~= nil then out[slot] = spec[source] or nil end
  end
  -- self-describing: a derived spec's `target` is the routed one, so a caller
  -- holding it alone never reads the Gen 1 path by accident.  targetFor stays
  -- authoritative and stays idempotent over the result.
  out.target = Schemas.targetFor(name, spec, generation)
  derivedSpecs[spec] = out
  return out
end

local R = {}
Schemas.REGISTRIES = R

-- Some generated Gen 2 modules keep extractor metadata beside their public
-- record maps. These callbacks are the registry normalization boundary: the
-- metadata remains available to engine consumers through Data, but is not an
-- id a mod can read or overwrite through the record registry.
local function recordMapExcept(...)
  local excluded = {}
  for index = 1, select("#", ...) do excluded[select(index, ...)] = true end
  return function(base, id)
    if excluded[id] then return nil end
    return base[id]
  end, function(base)
    local ids = {}
    for id in pairs(base) do
      if not excluded[id] then ids[#ids + 1] = id end
    end
    return ids
  end, excluded
end

local pokemonGen2BaseAt, pokemonGen2BaseIds, pokemonGen2ReservedIds =
  recordMapExcept("growthRates", "tmhmMoves")
local movesGen2BaseAt, movesGen2BaseIds, movesGen2ReservedIds =
  recordMapExcept("generation", "source")
local itemsGen2BaseAt, itemsGen2BaseIds, itemsGen2ReservedIds =
  recordMapExcept("generation", "source", "pockets")

-- ------- shared Gen 2 leaves
--
-- The ROM name spaces Gold's tables key by.  They are enums rather than
-- f.str so a typo ("MORNING") fails at register time instead of writing a
-- subtable nothing ever reads; the ordered lists themselves ship as
-- data.gen2Constants (eggGroupOrder, trainerTypeOrder, ...).

-- wild encounters, overworld palettes and the roof pair all bucket by time of
-- day; DARK is the fourth palette bucket and never an encounter one, so the
-- encounter maps take the three-value list (constants/time_of_day.asm)
local gen2Tod = f.enum{ "MORN", "DAY", "NITE" }
local gen2PaletteTod = f.enum{ "MORN", "DAY", "NITE", "DARK" }

-- one GBC colour as the extractor writes it: a positional {r,g,b} triple
-- already expanded from 5-bit BGR to 0..255 (src/render/GbcPalette.lua)
local gen2Color = f.list(f.int(0, 255))
-- a palette row.  The OBJ rows the sprite and mon pics use carry two colours
-- (the cart supplies white and black), the BG rows carry all four.
local gen2PaletteRow = f.list(gen2Color)

R.pokemon = {
  semantics = "record", target = "pokemon",
  gen2BaseAt = pokemonGen2BaseAt, gen2BaseIds = pokemonGen2BaseIds,
  gen2ReservedIds = pokemonGen2ReservedIds,
  fields = {
    id = f.str, name = f.str, dex = f.int(1),
    index = f.opt(f.int(0, 255)),
    types = f.list(f.id("type_chart")),
    baseStats = f.rec{ hp = f.int(1, 255), attack = f.int(1, 255),
                       defense = f.int(1, 255), speed = f.int(1, 255),
                       special = f.int(1, 255) },
    catchRate = f.int(0, 255), baseExp = f.int(0, 255),
    level1Moves = f.list(f.id("moves")),
    growthRate = f.id("growth_rates"),
    tmhm = f.opt(f.list(f.id("moves"))),
    learnset = f.list(f.rec{ level = f.int(1), move = f.id("moves") }),
    evolutions = f.list(f.rec{ method = f.id("evolution_methods"),
                               level = f.opt(f.int(1)),
                               item = f.opt(f.id("items")),
                               species = f.id("pokemon") }),
    spriteFront = f.path, spriteBack = f.path, frontSize = f.int(1, 7),
    -- text2 is the #DEX entry's second description page (Pokedex_asm's bare
    -- `page` macro, engine/pokedex/pokedex.asm): PokedexMenu:drawEntryBody
    -- shows `entry.text` on page 1 and `entry.text2` on page 2, so a
    -- translation needs both to cover the whole entry.
    dexEntry = f.opt(f.rec{ kind = f.str, heightFt = f.int(0),
                            heightIn = f.int(0, 11), weight = f.num,
                            heightM = f.opt(f.num), weightKg = f.opt(f.num),
                            text = f.str, text2 = f.opt(f.str) }),
    icon = f.opt(f.union{ f.str, f.rec{ image = f.path,
                                        frames = f.opt(f.int(1)) } }),
    cry = f.opt(f.id("cries")), palette = f.opt(f.id("palettes")),
    trueColor = f.opt(f.bool),
    -- battle-pic scale overrides for this species' own pics: front is the
    -- enemy pic (default 1x), back is the player pic (default 2x).  An
    -- image-level battle_sprite_scales entry for the same path beats these.
    -- The pic stays grounded (feet pinned) at any scale; see docs/modding.md.
    battleScaleFront = f.opt(f.numRange(0.25, 4.0)),
    battleScaleBack = f.opt(f.numRange(0.25, 4.0)),
  },
  -- Same registry, same target (data.pokemon), same species ids: only the
  -- record differs, and it differs in four places, every one of them a real
  -- Gen 2 change rather than an extractor spelling.  Gen 2 splits `special`
  -- into specialAttack/specialDefense (BaseData in pokegold's
  -- data/pokemon/base_stats/), names the level-up table `levelMoves` and the
  -- pic size `picSize`, has no separate level-1 move list (level 1 rows live
  -- in levelMoves), and points an evolution at `into` rather than `species`.
  -- Beside that it carries the breeding block Gen 1 has no analogue for
  -- (eggGroups/eggMoves/eggSteps, genderRatio) and a held-item pair.
  --
  -- Without this, mod.content.pokemon:register is unusable for a Gold
  -- species -- every record fails on the missing `special` -- while patch
  -- happens to work, which is the worst of both.
  gen2Fields = {
    id = f.str, name = f.str, dex = f.int(1),
    index = f.opt(f.int(0, 255)),
    types = f.list(f.id("type_chart")),
    baseStats = f.rec{ hp = f.int(1, 255), attack = f.int(1, 255),
                       defense = f.int(1, 255), speed = f.int(1, 255),
                       specialAttack = f.int(1, 255),
                       specialDefense = f.int(1, 255) },
    catchRate = f.int(0, 255), baseExp = f.int(0, 255),
    growthRate = f.id("growth_rates"), growthRateId = f.opt(f.int(0, 255)),
    levelMoves = f.list(f.rec{ level = f.int(1), move = f.id("moves") }),
    tmhm = f.opt(f.list(f.id("moves"))),
    -- the raw TM/HM bitfield bytes, kept beside the resolved list so a
    -- re-export round-trips; the engine reads `tmhm`
    tmhmRaw = f.opt(f.list(f.int(0, 255))),
    evolutions = f.list(f.rec{ method = f.id("evolution_methods"),
                               into = f.id("pokemon"),
                               level = f.opt(f.int(1)),
                               item = f.opt(f.id("items")),
                               -- EVOLVE_HAPPINESS' window and EVOLVE_STAT's
                               -- attack-vs-defence test
                               time = f.opt(f.enum{ "ANYTIME", "MORNDAY",
                                                    "NITE" }),
                               comparison = f.opt(f.enum{ "ATK_LT_DEF",
                                                          "ATK_GT_DEF",
                                                          "ATK_EQ_DEF" }) }),
    -- breeding: two egg groups (the raw byte packs both nibbles), the egg
    -- move list, and the cycle count src/core/gen2/Breeding.lua counts down
    eggGroups = f.opt(f.list(f.str)), eggGroupsRaw = f.opt(f.int(0, 255)),
    eggMoves = f.opt(f.list(f.id("moves"))), eggSteps = f.opt(f.int(0)),
    genderRatio = f.opt(f.int(0, 255)),
    -- the two wild held items, in the ROM's own order (rare then common)
    items = f.opt(f.list(f.id("items"))),
    spriteFront = f.path, spriteBack = f.path, picSize = f.int(1, 7),
    source = f.opt(f.str),
    cry = f.opt(f.id("cries")), trueColor = f.opt(f.bool),
    battleScaleFront = f.opt(f.numRange(0.25, 4.0)),
    battleScaleBack = f.opt(f.numRange(0.25, 4.0)),
  },
  example = 'mod.content.pokemon:patch("MEW", { baseStats = { attack = 120 } })',
  gen2Example = 'mod.content.pokemon:patch("TOTODILE", '
    .. '{ baseStats = { specialAttack = 80 } })',
}

R.moves = {
  semantics = "record", target = "moves",
  gen2BaseAt = movesGen2BaseAt, gen2BaseIds = movesGen2BaseIds,
  gen2ReservedIds = movesGen2ReservedIds,
  fields = {
    id = f.str, name = f.str,
    index = f.opt(f.int(0, 255)),
    type = f.id("type_chart"),
    power = f.int(0, 255),
    accuracy = f.int(0, 100),
    pp = f.int(0, 64),
    effect = f.id("move_effects"),
    anim = f.opt(f.any),
    category = f.opt(f.enum{ "physical", "special", "status" }),
    priority = f.opt(f.int(-7, 7)),
    highCrit = f.opt(f.bool),
    fixedDamage = f.opt(f.union{ f.int(1), f.fn }),
    chargeText = f.opt(f.str),
    semiInvulnerable = f.opt(f.bool),
    -- a fixed count or the distribution a uniform roll picks from
    multiHit = f.opt(f.union{ f.int(1), f.list(f.int(1)) }),
    counterable = f.opt(f.bool),
  },
  example = 'mod.content.moves:patch("BLIZZARD", { accuracy = 70 })',
}

R.items = {
  semantics = "record", target = "items",
  gen2BaseAt = itemsGen2BaseAt, gen2BaseIds = itemsGen2BaseIds,
  gen2ReservedIds = itemsGen2ReservedIds,
  fields = {
    id = f.str, name = f.str,
    index = f.opt(f.int(0, 255)),
    price = f.int(0),
    machine = f.opt(f.rec{ kind = f.str, move = f.id("moves"),
                           number = f.int(0) }),
    effect = f.opt(f.id("item_effects")),
    ball = f.opt(f.id("balls")),
    tossable = f.opt(f.bool),
    needsTarget = f.opt(f.bool),
  },
  example = 'mod.content.items:patch("POTION", { price = 100 })',
}

R.maps = {
  semantics = "record", target = "maps",
  fields = {
    -- the byte cap is a ROM table artifact; mod maps use ids at or above
    -- 1000, and the indoor/connection range compares read the number
    id = f.str, label = f.opt(f.str), index = f.opt(f.int(0)),
    tileset = f.id("tilesets"),
    width = f.int(1), height = f.int(1),
    blocks = f.list(f.int(0, 255)),
    borderBlock = f.opt(f.int(0, 255)),
    -- A named SGB palette, which wins over the field.palettes cascade
    -- (OverworldController.lua:506 reads map.def.palette first).  Deliberately
    -- a plain string rather than f.id("palettes"): the ROM-free fixture base
    -- carries no palettes at all, so an id reference would fail validation for
    -- a perfectly good mod wherever there is no imported dataset.
    palette = f.opt(f.str),
    -- destGroup / destMapNum are the ROM map-group pair Gen 2 carries beside
    -- the destination it actually warps through (World:resolveWarp reads
    -- destMap and destWarp, the same two keys Gen 1 does).  Optional and
    -- additive rather than a second warp shape: `maps` routes to
    -- data.gen2Maps under Gen 2, so the records a mod patches there are the
    -- extractor's own, and a strict rec would reject every one of them.
    warps = f.opt(f.list(f.rec{ x = f.int(0), y = f.int(0),
                                destMap = f.str, destWarp = f.int(0),
                                destGroup = f.opt(f.int(0)),
                                destMapNum = f.opt(f.int(0)) })),
    -- NPCs, signs, items, warps and static wild encounters all share this
    -- one array, with no field the loader could use to tell them apart
    -- ahead of time -- an f.rec strict enough to describe every kind would
    -- reject the others.  f.partial types only `pokemon` (the static
    -- encounter's species, OverworldController.lua's `d.pokemon` ->
    -- BattleState.newWild) so a bad id is a load-time error, the same as
    -- an encounter slot's species, instead of the crash newWild has no
    -- guard against.  Every other object field passes through untouched.
    objects = f.opt(f.list(f.partial{ pokemon = f.opt(f.id("pokemon")) })),
    signs = f.opt(f.list(f.any)),
    connections = f.opt(f.map(f.enum{ "north", "south", "east", "west" }, f.any)),
  },
  extra = function(_, value)
    if type(value.blocks) == "table" and type(value.width) == "number"
        and type(value.height) == "number"
        and #value.blocks ~= value.width * value.height then
      return ("blocks has %d entries, expected width*height = %d")
        :format(#value.blocks, value.width * value.height)
    end
  end,
  example = 'mod.content.maps:register("MY_CAVE", { tileset = "CAVERN", ... })',
}

R.tilesets = {
  semantics = "record", target = "tilesets",
  fields = {
    id = f.opt(f.str), image = f.path,
    imageWidth = f.opt(f.int(1)), imageHeight = f.opt(f.int(1)),
    tilesPerRow = f.opt(f.int(1)),
    blocks = f.list(f.any),
    walkable = f.opt(f.any), counterTiles = f.opt(f.any),
    doorTiles = f.opt(f.any), warpTiles = f.opt(f.any),
    animation = f.opt(f.str),
    trueColor = f.opt(f.bool),
  },
  extra = function(_, value)
    if type(value.blocks) == "table" then
      for i, row in ipairs(value.blocks) do
        if type(row) ~= "table" or #row ~= 16 then
          return ("blocks[%d] must be a row of 16 tile ids"):format(i)
        end
      end
    end
  end,
  example = 'mod.content.tilesets:register("MY_TILES", { image = "...", blocks = { ... } })',
}

-- ------- Gen 2 wild encounters
--
-- One wild slot.  A fishing slot's species may be the literal 0 the ROM uses
-- for "no fish here, roll the map's water table instead" (pokegold
-- data/wild/fish.asm), which is why species is a union rather than a bare id.
local gen2Slot = f.rec{ level = f.int(1), species = f.id("pokemon") }
-- the sentinel row carries level 0 as well as species 0, so both floors drop.
-- Time-dependent rows (TimeFishGroups) carry day/nite sub-slots.
local gen2FishSubSlot = f.rec{ level = f.int(0), species = f.union{ f.id("pokemon"), f.int(0, 0) } }
local gen2FishSlot = f.rec{ chance = f.int(0, 255), level = f.int(0),
                            species = f.union{ f.id("pokemon"), f.int(0, 0) },
                            timeGroup = f.opt(f.int(0, 255)),
                            day = f.opt(gen2FishSubSlot),
                            nite = f.opt(gen2FishSubSlot) }
-- Headbutt/Rock Smash slots.  species is optional and the level floor is 0
-- because TreeMonSet_Rock has no `rare` half in the ROM (pokegold
-- data/wild/treemons.asm ends the table after the common rows), so the four
-- Rock Smash maps that point at it carry a rare table read out of whatever
-- follows: levels past 100 and rows with no species at all.  Rejecting it
-- would mean the extractor's own table could never be re-registered.
local gen2TreeSlot = f.rec{ chance = f.int(0, 255), level = f.int(0),
                            species = f.opt(f.id("pokemon")) }

-- a grass row: one encounter rate and one seven-slot table PER time of day,
-- which is the whole reason this cannot share the Gen 1 shape
local gen2GrassRow = f.rec{
  map = f.opt(f.str),
  rates = f.map(gen2Tod, f.int(0, 255)),
  slots = f.map(gen2Tod, f.list(gen2Slot)),
}
-- water has no time-of-day split: one rate, one three-slot table
local gen2WaterRow = f.rec{
  map = f.opt(f.str), rate = f.int(0, 255), slots = f.list(gen2Slot),
}

R.encounters = {
  semantics = "record", target = "encounters",
  fields = {
    id = f.opt(f.str),
    grass = f.opt(f.rec{ rate = f.int(0, 255),
                         slots = f.list(f.rec{ level = f.int(1),
                                               species = f.id("pokemon") }) }),
    water = f.opt(f.rec{ rate = f.int(0, 255),
                         slots = f.list(f.rec{ level = f.int(1),
                                               species = f.id("pokemon") }) }),
  },
  -- Gold keys wild encounters by encounter KIND first and by map second
  -- (data.gen2Encounters.grass.ROUTE_29), because the cart ships one table
  -- per kind and a map appears in as many of them as it has water, swarms,
  -- fishing spots and headbuttable trees.  There is no per-map record to key
  -- the registry by, so the id is the kind and `patch` folds per map instead
  -- of replacing the kind's whole table.
  --
  -- Semantics stay "record" rather than becoming "deep" even though the id is
  -- a namespace: a slot table is an ORDERED list whose position is the
  -- encounter roll, and Merge.deepMerge appends lists under "deep" semantics,
  -- so a mod rewriting a seven-slot table would get a fourteen-slot one.
  gen2Keys = {
    grass = f.map(f.str, gen2GrassRow),
    -- the swarm variants shadow their base table while a swarm is running
    swarmGrass = f.map(f.str, gen2GrassRow),
    water = f.map(f.str, gen2WaterRow),
    swarmWater = f.map(f.str, gen2WaterRow),
    -- fishing: a map's rod points at a named group, and the group carries a
    -- chance-ordered table per rod
    fishGroups = f.map(f.str, f.rec{
      id = f.opt(f.str), index = f.opt(f.int(0, 255)),
      chance = f.int(0, 255),
      old = f.list(gen2FishSlot), good = f.list(gen2FishSlot),
      super = f.list(gen2FishSlot) }),
    timeFishGroups = f.opt(f.map(f.union{ f.str, f.int(0, 255) },
      f.rec{ day = gen2FishSubSlot, nite = gen2FishSubSlot })),
    -- headbutt: map -> tree set id, and the set's common/rare tables.  rocks
    -- is the same indirection for Rock Smash.
    trees = f.map(f.str, f.str),
    rocks = f.map(f.str, f.str),
    treeSets = f.map(f.str, f.rec{ common = f.list(gen2TreeSlot),
                                   rare = f.list(gen2TreeSlot) }),
    -- the Bug-Catching Contest pool (min/max level, not one level per slot)
    bugContest = f.list(f.rec{ species = f.id("pokemon"),
                               min = f.int(1), max = f.int(1),
                               chance = f.int(0, 255) }),
    -- where a roaming beast may walk next, keyed by the map it is on
    roamMaps = f.list(f.rec{ map = f.str, to = f.list(f.str) }),
    source = f.str, generation = f.int(1),
  },
  example = 'mod.content.encounters:patch("ROUTE_1", { grass = { rate = 30 } })',
  gen2Example = 'mod.content.encounters:patch("grass", '
    .. '{ ROUTE_29 = { rates = { NITE = 40 } } })',
}

R.trainers = {
  semantics = "record", target = "trainers",
  fields = {
    id = f.str, name = f.str,
    index = f.opt(f.int(0, 255)),
    -- unused vanilla classes ship without a pic, so it cannot be required
    pic = f.opt(f.path),
    -- Full-color portrait: skip the 4-shade SGB/GBC remap, same flag pokemon
    -- and sprites already carry.
    trueColor = f.opt(f.bool),
    -- Optional Advanced-mode OBJ palette source for a custom trainer portrait.
    -- It follows the same ROM crosswalk form as sprites.paletteSource.
    paletteSource = f.opt(f.str),
    -- Reuse a base trainer class's portrait without redistributing its asset.
    basePic = f.opt(f.id("trainers")),
    baseMoney = f.opt(f.int(0)),
    parties = f.list(f.list(f.rec{ level = f.int(1),
                                   species = f.id("pokemon") })),
    aiMods = f.opt(f.any),
    aiClass = f.opt(f.id("ai_classes")),
    brain = f.opt(f.fn),
    -- Per-trainer battle theme (an audio.songs id): overrides the
    -- kind-based default (wild/trainer/gym/final) for this trainer's
    -- battles.  The victory jingle stays kind-based.
    battleTheme = f.opt(f.id("music")),
  },
  -- Gold hangs its rosters off data.gen2Trainers.classes, one record per
  -- trainer CLASS carrying every named trainer of that class.  The id space
  -- is still the class id, so the registry keeps the Gen 1 call shape --
  -- mod.content.trainers:patch("BEAUTY", { baseMoney = 99 }) -- and only the
  -- one level of indirection to `.classes` is new.  That is the same trick
  -- battle_anims plays with its per-kind subtables, and it is why these three
  -- callbacks exist rather than a `classes` key nobody would guess.
  gen2BaseAt = function(base, id)
    return base.classes and base.classes[id] or nil
  end,
  gen2BaseIds = function(base)
    local ids = {}
    for id in pairs(base.classes or {}) do ids[#ids + 1] = id end
    return ids
  end,
  gen2Write = function(target, registry)
    local classes = target.classes
    if not classes then
      classes = {}
      target.classes = classes
    end
    local tombstones = {}
    for id in pairs(registry.ops) do
      local value = registry:get(id)
      if value == nil then
        tombstones[#tombstones + 1] = id
      else
        classes[id] = value
      end
    end
    for _, id in ipairs(tombstones) do classes[id] = nil end
  end,
  gen2Fields = {
    id = f.opt(f.str), name = f.str,
    index = f.opt(f.int(0, 255)),
    -- class frontpic; when set, this wins over menu_gfx.battleHud.trainerPics
    pic = f.opt(f.path),
    -- Full-color portrait: skip the GBC 4-shade remap, same flag Gen 1
    -- trainers and pokemon already carry.
    trueColor = f.opt(f.bool),
    baseMoney = f.opt(f.int(0)),
    -- the class's battle theme; Gen 1 spells the same idea `battleTheme`,
    -- but this is the extractor's own key and a strict rename would reject
    -- every one of Gold's 66 classes
    encounterMusic = f.opt(f.id("music")),
    -- the items the class's AI may use mid-battle, and the seven raw AI
    -- bytes behind them (pokegold data/trainers/attributes.asm)
    items = f.opt(f.list(f.id("items"))),
    attributes = f.opt(f.list(f.int(0, 255))),
    -- one entry per named trainer of the class.  trainerType decides which
    -- optional party fields the cart actually stores, so `moves` and `item`
    -- are optional here rather than four party shapes in a union.
    trainers = f.list(f.rec{
      id = f.opt(f.str), name = f.str, index = f.opt(f.int(0, 255)),
      trainerType = f.opt(f.enum{ "TRAINERTYPE_NORMAL", "TRAINERTYPE_MOVES",
                                  "TRAINERTYPE_ITEM",
                                  "TRAINERTYPE_ITEM_MOVES" }),
      party = f.list(f.rec{ level = f.int(1), species = f.id("pokemon"),
                            item = f.opt(f.id("items")),
                            moves = f.opt(f.list(f.id("moves"))) }) }),
  },
  example = 'mod.content.trainers:patch("OPP_BROCK", { baseMoney = 99 })',
  gen2Example = 'mod.content.trainers:patch("BEAUTY", { baseMoney = 99 })',
}

R.sprites = {
  semantics = "record", target = "sprites",
  fields = {
    id = f.opt(f.str),
    image = f.path,
    frames = f.int(1),
    walker = f.opt(f.bool),
    -- Optional sheet geometry for mod actors.  Defaults match the vanilla
    -- 16x16 grounded walker; anchors are measured from each frame's
    -- top-left in pixels (default: bottom-center).
    frameWidth = f.opt(f.int(1)),
    frameHeight = f.opt(f.int(1)),
    anchorX = f.opt(f.num),
    anchorY = f.opt(f.num),
    trueColor = f.opt(f.bool),
    -- Mod art can opt into an existing ROM sprite's Advanced-mode OBJ
    -- palette assignment without claiming that the image itself came from
    -- the ROM (which is what `source` documents on imported records).
    paletteSource = f.opt(f.str),
  },
  -- Same name, same ids, and (unlike the rest of this section) already
  -- routed: `sprites` merges into data.gen2Sprites and Gold walks that very
  -- table.  The Gen 1 schema accepts a Gen 2 record only because the extra
  -- keys fall through as unknown-but-preserved, which means none of them is
  -- checked -- a mod could write paletteId = "blue" and find out at draw
  -- time.  This types them.
  gen2Fields = {
    id = f.opt(f.str), image = f.path, frames = f.int(1),
    walker = f.opt(f.bool), trueColor = f.opt(f.bool),
    paletteSource = f.opt(f.str),
    -- the OBJ palette this sprite draws with, by name and by the slot index
    -- src/world/gen2/Palettes.lua indexes into (PAL_OW_RED is slot 0)
    palette = f.opt(f.str), paletteId = f.opt(f.int(0, 7)),
    -- how the overworld animates it: WALKING_SPRITE has the four facings and
    -- a step cycle, STANDING_SPRITE only the facings, STILL_SPRITE one frame,
    -- POKEMON_SPRITE the party-icon pair (pokegold constants/sprite_constants)
    spriteType = f.opt(f.enum{ "WALKING_SPRITE", "STANDING_SPRITE",
                               "STILL_SPRITE", "POKEMON_SPRITE" }),
    -- a POKEMON_SPRITE names the species it follows and the party icon it
    -- borrows its art from
    species = f.opt(f.id("pokemon")), icon = f.opt(f.str),
    source = f.opt(f.str),
  },
  example = 'mod.content.sprites:register("SPRITE_HERO", { image = "...", frames = 6 })',
  gen2Example = 'mod.content.sprites:patch("SPRITE_BEAUTY", '
    .. '{ palette = "PAL_OW_RED", paletteId = 0 })',
}

R.text = {
  semantics = "record", target = "text",
  value = f.str,
  example = 'mod.content.text:override("_PalletTownText1", "HELLO!")',
}

-- The engine's own authored text, the half of the game `text` does not
-- cover (src/core/Strings.lua).  The id is the English source string, so a
-- translation supplies one entry per literal the engine draws and anything
-- it has not reached yet keeps rendering in English.  Ids that collide in
-- English but not elsewhere carry a "context|source" prefix.
R.strings = {
  semantics = "record", target = "strings",
  value = f.str,
  example = 'mod.content.strings:override("But, it failed!", "Echec !")',
}

-- the self-contained bytecode blob ChipAsm.song/sfx emit (13.1 shape 2);
-- shared by every namespace that plays a chip program
local chipProgram = f.rec{
  blob = f.str, channels = f.any, waves = f.opt(f.any),
  drums = f.opt(f.any), engine = f.opt(f.num),
}

-- value union dispatched per def shape: rom chip ref, file-backed song, or
-- an authored chip program (ChipAsm)
R.music = {
  semantics = "record", target = "audio.songs",
  value = f.union{
    f.rec{ address = f.int(0), bank = f.int(0), engine = f.opt(f.num) },
    f.rec{ file = f.path, loopFile = f.opt(f.path), seconds = f.opt(f.num),
           loopSeconds = f.opt(f.num), intro = f.opt(f.any) },
    f.rec{ program = f.any, channels = f.any, waves = f.opt(f.any),
           drums = f.opt(f.any) },
    f.rec{ chip = chipProgram },
  },
  example = 'mod.content.music:register("MOD_SONG", { file = "song.ogg" })',
}

-- whole-key replacement of Data.audio, the v1 escape hatch.  Kept working
-- forever; the granular sfx / cries / map_songs registries supersede it and
-- whole-key swaps (programFile, bankOrder) remain its one honest use.
R.audio = {
  semantics = "record", target = "audio",
  value = f.any,
  deprecated = { useInstead = "sfx / cries / map_songs / music" },
  example = 'mod.content.audio:override("mapSongs", { ... })',
}

-- compose: registrations accumulate into per-map chains instead of
-- replacing each other.  Data.map_scripts is the interim home consumed by
-- data/scripts/init.lua until the M5 dispatcher reads chain() directly.
-- rows, a handler, or false: false is the explicit suppression that wins the
-- single-winner resolution and hides every lower-precedence entry (09 4.4)
local scriptEntry = f.union{
  f.list(f.any), f.fn,
  leaf("suppress", "false", function(v) return v == false end),
}

R.map_scripts = {
  semantics = "compose", target = "map_scripts",
  value = f.rec{
    talk = f.opt(f.map(f.str, scriptEntry)),
    scripts = f.opt(f.map(f.str, scriptEntry)),
    onEnter = f.opt(f.fn), onStep = f.opt(f.fn), onInteract = f.opt(f.fn),
    onVictory = f.opt(f.fn), onBoulderMoved = f.opt(f.fn),
    -- the flute wake sequence ItemEffects/BagMenu look up by map id; the
    -- other legacy ad-hoc keys stay unknown-but-preserved
    snorlaxWake = f.opt(f.rec{
      objName = f.opt(f.str), beatFlag = f.opt(f.str), script = f.list(f.any),
    }),
    priority = f.opt(f.num),
  },
  example = 'mod.content.map_scripts:register("PALLET_TOWN", { talk = { ... } })',
}

R.screens = {
  semantics = "record", target = "screens",
  value = f.union{ f.fn, f.rec{ new = f.fn } },
  example = 'mod.content.screens:register("QuestLog", { new = function(game) ... end })',
}

-- ------- battle

-- Two id forms share one registry: "ATTACKER>DEFENDER" matchup rows and
-- bare type ids.  Neither lives at a key of Data.type_chart (the rows are
-- an ordered array), so the registry owns the whole target: reads see only
-- registrations -- the engine makes them all -- and the merge rebuilds
-- matchups and types from the op order.
R.type_chart = {
  semantics = "record", target = "type_chart",
  value = f.union{
    f.rec{ multiplier = f.int(0) },
    f.rec{ name = f.opt(f.str), category = f.enum{ "physical", "special" },
           index = f.opt(f.int(0, 255)) },
  },
  baseAt = function() return nil end,
  baseIds = function() return {} end,
  write = function(target, registry)
    local matchups, types = {}, {}
    for _, id in ipairs(registry.order) do
      local value = registry:get(id)
      if value ~= nil then
        local attacker, defender = id:match("^([^>]+)>([^>]+)$")
        if attacker then
          local row = Merge.deepCopy(value)
          row.attacker, row.defender = attacker, defender
          matchups[#matchups + 1] = row
        else
          types[id] = value
        end
      end
    end
    target.matchups, target.types = matchups, types
  end,
  example = 'mod.content.type_chart:register("BUG>PSYCHIC_TYPE", { multiplier = 20 })',
}

R.statuses = {
  semantics = "record", target = "statuses",
  fields = {
    id = f.opt(f.str), label = f.str,
    hudLabel = f.opt(f.str),
    canInflict = f.opt(f.fn), onInflict = f.opt(f.fn),
    beforeMove = f.opt(f.fn), beforeMovePriority = f.opt(f.int(0)),
    residual = f.opt(f.fn),
    catchBonus = f.opt(f.int(0, 255)), shakeBonus = f.opt(f.int(0, 255)),
    statPenalty = f.opt(f.rec{ stat = f.str, div = f.int(1) }),
    cureOnSwitch = f.opt(f.bool),
  },
  example = 'mod.content.statuses:patch("BRN", { catchBonus = 12 })',
}

-- run is optional because the "full" effects are steered from inside the
-- damage pipeline and have no standalone handler to register yet; M7 gives
-- them the effect context that makes one possible
R.move_effects = {
  semantics = "record", target = "move_effects",
  fields = {
    kind = f.enum{ "primary", "secondary", "full" },
    accuracyChecked = f.opt(f.bool),
    run = f.opt(f.fn),
  },
  example = 'mod.content.move_effects:register("DRAIN_PP_EFFECT", { kind = "primary", run = fn })',
}

R.item_effects = {
  semantics = "record", target = "item_effects",
  fields = {
    use = f.fn,
    needsTarget = f.opt(f.bool), battle = f.opt(f.bool), field = f.opt(f.bool),
  },
  example = 'mod.content.item_effects:register("MOON_FLUTE", { use = fn, field = true })',
}

-- MASTER_BALL catches unconditionally and never rolls, so randMax 0 is a
-- legal record and hpFactor is only read on the wobble path
R.balls = {
  semantics = "record", target = "balls",
  fields = {
    randMax = f.int(0, 255),
    hpFactor = f.opt(f.int(1)), wobbleFactor = f.opt(f.int(1)),
    autoCatch = f.opt(f.bool), flicker = f.opt(f.bool),
    tossAnim = f.opt(f.str), attempt = f.opt(f.fn),
  },
  example = 'mod.content.balls:override("GREAT_BALL", { randMax = 180, hpFactor = 12 })',
}

R.rulesets = {
  semantics = "record", target = "rulesets",
  fields = { name = f.str },
  example = 'mod.content.rulesets:register("no_crits", { name = "no crits", critRate = 0 })',
}

-- three record kinds share the registry: "class" is the per-trainer
-- item/switch behavior, "layer" a move-scoring pass (the vanilla three are
-- LAYER_1..LAYER_3), "brain" a full action chooser
R.ai_classes = {
  semantics = "record", target = "ai_classes",
  fields = {
    kind = f.opt(f.enum{ "class", "layer", "brain" }),
    uses = f.opt(f.int(0)), chance = f.opt(f.int(0, 256)),
    item = f.opt(f.id("items")),
    switch = f.opt(f.bool), switchChance = f.opt(f.int(0, 256)),
    switchBelow = f.opt(f.int(1)), hpBelow = f.opt(f.int(1)),
    onStatus = f.opt(f.bool),
    score = f.opt(f.fn), choose = f.opt(f.fn), brain = f.opt(f.fn),
  },
  example = 'mod.content.ai_classes:patch("OPP_BROCK", { uses = 9 })',
}

-- ids route into the target's per-kind subtables: a bare move id is a move
-- animation, "subanim:<n>" and "tilesheet:<n>" address the shared pieces
local function animRoute(id)
  local kind, index = tostring(id):match("^(%a+):(%d+)$")
  if kind == "subanim" then return "subanims", tonumber(index) end
  if kind == "tilesheet" then return "tilesheets", tonumber(index) end
  return "moveAnims", id
end

R.battle_anims = {
  semantics = "record", target = "battle_anims",
  value = f.union{
    f.rec{ seq = f.list(f.any), source = f.opt(f.str) },
    f.rec{ blocks = f.list(f.any), type = f.opt(f.str) },
    f.rec{ path = f.path, width = f.int(1), height = f.int(1),
           tiles = f.int(1), source = f.opt(f.str) },
  },
  baseAt = function(base, id)
    local sub, key = animRoute(id)
    local table_ = base[sub]
    return table_ and table_[key] or nil
  end,
  baseIds = function(base)
    local ids = {}
    for id in pairs(base.moveAnims or {}) do ids[#ids + 1] = id end
    for index in pairs(base.subanims or {}) do ids[#ids + 1] = "subanim:" .. index end
    for index in pairs(base.tilesheets or {}) do ids[#ids + 1] = "tilesheet:" .. index end
    return ids
  end,
  write = function(target, registry)
    for _, id in ipairs(registry.order) do
      local sub, key = animRoute(id)
      local into = target[sub]
      if not into then
        into = {}
        target[sub] = into
      end
      into[key] = registry:get(id)
    end
  end,
  -- Gold's battle animations are the cart's own bytecode, not a Lua sequence:
  -- data.gen2BattleAnims is a script POOL keyed by ROM pointer plus the name
  -- tables that index into it (a move id or an ANIM_* id resolves to a
  -- pointer), and the object/frameset/OAM/graphics tables the scripts spawn
  -- from.  src/battle/gen2/AnimRunner.lua walks exactly those.  The id is the
  -- table, and `patch` adds one object without restating the pool.
  --
  -- The Gen 1 write/baseAt/baseIds trio is cleared rather than reused: it
  -- routes an id into a per-kind subtable by prefix, and here the ids ARE the
  -- subtables, so the plain record placement is the correct one.
  gen2Write = false, gen2BaseAt = false, gen2BaseIds = false,
  gen2Keys = {
    -- pointer -> the decoded command rows the runner steps; each row is a
    -- verb string followed by its operands
    scripts = f.map(f.str, f.list(f.list(f.any))),
    -- the pool in ROM order, which is what a re-export writes back
    scriptOrder = f.list(f.str),
    -- move id -> script pointer, and ANIM_* id -> script pointer
    moves = f.map(f.str, f.str),
    ids = f.map(f.str, f.str),
    -- an animation object: which graphics, palette, frameset and update
    -- function it spawns with
    objects = f.map(f.str, f.rec{ gfx = f.str, palette = f.str,
                                  frameset = f.str, func = f.str,
                                  fixY = f.opt(f.int(0, 255)),
                                  flags = f.opt(f.int(0, 255)) }),
    -- a frameset is its own little row list (frame / wait / delete)
    framesets = f.map(f.str, f.list(f.list(f.any))),
    -- OAM: the sprite rectangle an object draws, and the VRAM tile it starts
    -- at.  x/y are the cart's unsigned bytes, so 240 means -16.
    oamsets = f.map(f.str, f.rec{ vtile = f.int(0, 255),
                                  sprites = f.list(f.rec{
                                    x = f.int(0, 255), y = f.int(0, 255),
                                    tile = f.int(0, 255),
                                    attr = f.int(0, 255) }) }),
    gfx = f.map(f.str, f.rec{ image = f.path, tiles = f.int(1),
                              wide = f.int(1) }),
    bank = f.int(0), source = f.str, generation = f.int(1),
  },
  example = 'mod.content.battle_anims:register("SHADOW_BALL", { seq = { ... } })',
  gen2Example = 'mod.content.battle_anims:patch("moves", '
    .. '{ SHADOW_BALL = "5e86" })',
}

R.transitions = {
  semantics = "record", target = "transitions",
  fields = {
    frames = f.int(1), draw = f.opt(f.fn), sound = f.opt(f.str),
    flash = f.opt(f.bool),
  },
  example = 'mod.content.transitions:register("dissolve", { frames = 30, draw = fn })',
}

-- ------- rendering pipelines
--
-- A pipeline is a display mode that owns part of the frame: it may replace
-- the overworld's world pass with geometry of its own (drawWorld), add
-- upright objects to TILT (drawBillboards), and/or post-process the finished
-- composite (present).  Everything around that --
-- the OFF/1/2/3 ladder, its options row, its hotkey, persistence in
-- save.options.pipelines and the gating that keeps it out of battles and
-- menus -- is engine plumbing driven from this record, so a renderer mod
-- declares what it is and supplies only the stages it owns.
--
-- All callbacks are optional and independent: a present-only pipeline is a
-- post-process (bloom, tilt-shift, a CRT curve) that leaves whatever
-- rendered the frame alone, and a drawWorld-only pipeline is a world
-- renderer that composites straight.  See src/render/Pipelines.lua for the
-- ctx each receives and docs/modding.md for the worked example.
R.render_pipelines = {
  semantics = "record", target = "render_pipelines",
  fields = {
    -- shown in the options menu; the ladder labels default to OFF/ON
    label = f.str,
    levels = f.opt(f.list(f.str)),
    -- keyboard key that cycles the ladder, checked after the engine's own
    -- display hotkeys so a pipeline can never shadow one
    hotkey = f.opt(f.str),
    -- higher wins when two world pipelines are somehow active at once;
    -- also the options-row order, so a mode and its post-process sort
    -- together instead of by id
    priority = f.opt(f.num),
    -- hardware/driver gate, checked every frame: false keeps the vanilla
    -- 2D path, which is what a headless run and a driver with no depth
    -- canvas both get
    available = f.opt(f.fn),
    -- (top, overworld) -> boolean: whether the player may CHANGE the mode
    -- right now.  Defaults to the survey-zoom gate (free-roam overworld
    -- only), which keeps a hotkey press from switching modes mid-warp or
    -- mid-cutscene.  It has no say over whether an already-on mode draws:
    -- a mode that stopped rendering during a warp would flash the flat 2D
    -- world every time the player walked through a door.
    gate = f.opt(f.fn),
    -- (dt, level): presentational tweens, ticked on real frame time
    update = f.opt(f.fn),
    -- (ctx) -> canvas | nil: render the world.  nil falls back to the
    -- vanilla flat/tilt draw for this frame.
    drawWorld = f.opt(f.fn),
    -- (ctx) -> nil: add upright objects to the vanilla TILT pass. The
    -- callback queues through ctx.billboard and may remove source pixels
    -- from the active ground canvas through ctx.maskMapCutout.
    drawBillboards = f.opt(f.fn),
    -- (canvas, ctx) -> canvas: post-process the WORLD image, before the UI
    -- composites over it -- a depth-of-field or colour grade that must not
    -- touch the dialog boxes and menus sitting on top.  Only runs when some
    -- pipeline rendered the world, since the vanilla world pass has no
    -- single finished image to hand over.
    worldPresent = f.opt(f.fn),
    -- (canvas, ctx) -> canvas: post-process the whole finished composite,
    -- world and UI alike (a CRT curve, a full-screen grade).  Must return a
    -- canvas; the input unchanged is the correct answer when the effect is
    -- off.
    present = f.opt(f.fn),
    -- drop GPU objects (window resize, hot reload, mode switch)
    invalidate = f.opt(f.fn),
  },
  -- a pipeline that does neither half is dead weight and would silently
  -- occupy an options row and a hotkey
  extra = function(_, value)
    if value.drawWorld == nil and value.drawBillboards == nil
        and value.present == nil
        and value.worldPresent == nil then
      return "a render pipeline needs drawWorld, drawBillboards, "
        .. "worldPresent or present"
    end
  end,
  -- A pipeline callback fails at play time, long after the load phase has
  -- handed its report to the mod manager, so the merge leaves behind who
  -- wrote each record for Pipelines to name in the failure -- the same
  -- provenance trick the audio registries use (Loader.stampAudioOwners).
  -- Placement is otherwise the default record merge.
  write = function(target, registry)
    local owners, tombstones = {}, {}
    for id in pairs(registry.ops) do
      local value = registry:get(id)
      if value == nil then
        tombstones[#tombstones + 1] = id
      else
        target[id] = value
        local owner = registry.owners[id]
        if owner and owner ~= Schemas.ENGINE then owners[id] = owner end
      end
    end
    for _, id in ipairs(tombstones) do target[id] = nil end
    target._owners = owners
  end,
  example = 'mod.content.render_pipelines:register("voxel", ' ..
    '{ label = "VOXEL", levels = { "OFF", "15", "35", "50" }, drawWorld = fn })',
}

-- ------- battle sprite scales
--
-- Per-image battle-pic scale overrides, keyed by record id and consulted
-- by asset path at draw time.  Where a species' battleScaleFront /
-- battleScaleBack scales its own front/back pic, this scales ANY battle
-- pic by the path it is drawn from -- the only handle on the non-species
-- pics like the player's trainer back sprite.  Image-level beats
-- species-level; both compose with the send-out grow and keep the sprite
-- grounded (feet pinned) at whatever scale.  See docs/modding.md.
R.battle_sprite_scales = {
  semantics = "record", target = "battle_sprite_scales",
  fields = {
    -- the asset path exactly as data references it, e.g.
    -- "assets/generated/battle/back/abrab.png"
    path = f.path,
    -- 1 = native pixels; the drawn size relative to the pic's own pixels
    scale = f.numRange(0.25, 4.0),
  },
  example = [[
mod.content.battle_sprite_scales:register("abra_back", {
  path = "assets/generated/battle/back/abrab.png",
  scale = 1.5,
})]],
  notes = [[
Scales one battle pic by its asset path, overriding the species-level
`battleScaleFront`/`battleScaleBack` (see [pokemon](#pokemon)) for that
image. The only way to scale a pic that is not species-keyed, like the
player's trainer back sprite. Resolution order at draw time:
image-level, then species-level, then the defaults (1x front, 2x back).
The pic stays grounded at any scale: player feet stay flush on the
text-box top, the enemy pic stays bottom-pinned in its slot, and the
scale composes with the send-out grow animation.]],
}

-- ------- progression

R.evolution_methods = {
  semantics = "record", target = "evolution_methods",
  fields = { check = f.fn, describe = f.opt(f.fn) },
  example = 'mod.content.evolution_methods:register("FRIENDSHIP", { check = fn })',
}

R.growth_rates = {
  semantics = "record", target = "growth_rates",
  fields = { expForLevel = f.fn },
  -- a curve that does not grow makes levelForExp loop forever
  extra = function(_, value)
    if type(value.expForLevel) == "function" then
      local ok, low, high = pcall(function()
        return value.expForLevel(1), value.expForLevel(2)
      end)
      if ok and type(low) == "number" and type(high) == "number"
          and high <= low then
        return "expForLevel must increase with level"
      end
    end
  end,
  example = 'mod.content.growth_rates:register("ERRATIC", { expForLevel = fn })',
}

-- ------- audio (per-def shapes, dispatched by the consumer)

R.sfx = {
  semantics = "record", target = "audio.sfx",
  value = f.union{
    f.str,
    f.rec{ address = f.int(0), bank = f.int(0), engine = f.opt(f.num) },
    f.rec{ file = f.path },
    f.rec{ chip = chipProgram },
  },
  example = 'mod.content.sfx:register("SFX_MOD_CHIME", { file = "chime.ogg" })',
}

-- base names the species whose header a derived cry borrows, so it resolves
-- against this same registry (13.9)
R.cries = {
  semantics = "record", target = "audio.cries",
  value = f.union{
    f.rec{ header = f.any, pitch = f.int(0, 255), length = f.int(0, 255) },
    f.rec{ file = f.path },
    f.rec{ base = f.id("cries"), pitch = f.opt(f.int(0, 255)),
           length = f.opt(f.int(0, 255)) },
    f.rec{ chip = chipProgram, pitch = f.opt(f.int(0, 255)),
           length = f.opt(f.int(0, 255)) },
  },
  example = 'mod.content.cries:patch("PIKACHU", { pitch = 200 })',
}

R.map_songs = {
  semantics = "record", target = "audio.mapSongs",
  value = f.id("music"),
  example = 'mod.content.map_songs:override("PALLET_TOWN", "Music_Routes1")',
}

-- ------- presentation

-- vanilla palettes are four raw {r,g,b} triples; the named-record form is
-- the v2 shape a mod may register instead
R.palettes = {
  semantics = "record", target = "palettes.palettes",
  value = f.union{
    f.list(f.list(f.int(0, 255))),
    f.rec{ colors = f.list(f.rec{ r = f.int(0, 255), g = f.int(0, 255),
                                  b = f.int(0, 255) }) },
  },
  extra = function(_, value)
    local colors = value.colors or value
    if type(colors) == "table" and #colors ~= 4 then
      return ("needs exactly 4 colors, got %d"):format(#colors)
    end
  end,
  -- Gold's palette table is not a flat name -> four colours map: the GBC has
  -- eight BG and eight OBJ slots and the cart reloads them per context, so
  -- the extractor writes one subtable per context (mon pics with their shiny
  -- twin, trainer pics, the BG rows a map's environment indexes into, the
  -- overworld OBJ rows per time of day, the town roof pair, the HP and EXP
  -- bars).  The id is the context, so a mod that recolours one species
  -- patches `pokemon` and leaves the other 250 alone.  The Gen 1 four-colour
  -- `extra` is cleared: it reads the record as one palette, and here a record
  -- is a whole subtable of them.
  gen2Extra = false,
  gen2Keys = {
    -- every species has both a normal and a shiny row; the shiny one is what
    -- src/render/GbcPalette.lua swaps in on a shiny battler
    pokemon = f.map(f.str, f.rec{ normal = gen2PaletteRow,
                                  shiny = gen2PaletteRow }),
    trainers = f.map(f.str, gen2PaletteRow),
    -- the BG rows, indexed by number: `environments` names eight of them per
    -- environment per time of day, which is how a map gets its palette
    bg = f.list(gen2PaletteRow),
    environments = f.map(f.str, f.map(gen2PaletteTod, f.list(f.int(0)))),
    -- the eight overworld OBJ rows per time of day; a sprite's paletteId
    -- indexes this
    objects = f.map(gen2PaletteTod, f.list(gen2PaletteRow)),
    -- one pair per roof group (keyed by the group number, 0 included), and
    -- the BG slot the roof colours are written into
    roofs = f.map(f.int(0), f.rec{ mornDay = gen2PaletteRow,
                                   nite = gen2PaletteRow }),
    roofSlot = f.int(0, 7),
    hpBar = f.map(f.enum{ "green", "yellow", "red", "blue" }, gen2PaletteRow),
    expBar = gen2PaletteRow,
    partyMenu = f.list(gen2PaletteRow),
    battleObjects = f.map(f.str, gen2PaletteRow),
    -- the ordered name lists the numeric indices above resolve through
    daytimes = f.list(f.str), slotNames = f.list(f.str),
    source = f.str, generation = f.int(1),
  },
  example = 'mod.content.palettes:override("MEWMON", { {255,255,255}, ... })',
  gen2Example = 'mod.content.palettes:patch("pokemon", '
    .. '{ TOTODILE = { shiny = { {255,255,255}, {255,0,0} } } })',
}

-- keyed by species id, unlike the vanilla byDex array: a species past the
-- end of the dex gets an icon without punching a hole in the list. The party
-- menu (src/ui/PartyMenu.lua) reads this per-species entry before the vanilla
-- dex-indexed default. The value is a built-in icon NAME -- one of BALL, BIRD,
-- BUG, FAIRY, GRASS, HELIX, MON, QUADRUPED, SNAKE, WATER (uppercase) -- or a
-- { image = <bundled file path>, frames? } table of your own art.
-- Gold splits the same idea in two: data.gen2Icons.icons is the 39 icon
-- SHEETS (each its own two-frame image) and data.gen2Icons.species is the
-- species -> sheet name assignment.  Both halves keep the Gen 1 id space --
-- a species id names an assignment, a sheet id names a sheet -- so one
-- registry serves both, routed by the ICON_ prefix every sheet name carries.
-- Two id forms in one registry is the same shape font and battle_anims use.
local function gen2IconIsSheet(id)
  return tostring(id):match("^ICON_") ~= nil
end

R.icons = {
  semantics = "record", target = "icons.bySpecies",
  value = f.union{ f.str, f.rec{ image = f.path, frames = f.opt(f.int(1)) } },
  gen2Value = f.union{
    -- the assignment form: a species id mapped to a sheet name
    f.str,
    -- the sheet form: width/height are the sheet's pixel size, and every
    -- vanilla sheet is a 16x32 two-frame strip
    f.rec{ id = f.opt(f.str), index = f.opt(f.int(0, 255)), image = f.path,
           width = f.int(1), height = f.int(1), frames = f.int(1) },
  },
  gen2Extra = function(id, value)
    if gen2IconIsSheet(id) then
      if type(value) ~= "table" then
        return "an ICON_ id is a sheet and needs an image, width, height and frames"
      end
    elseif type(value) ~= "string" then
      return "a species id takes the NAME of an ICON_ sheet, not a sheet"
    end
  end,
  gen2BaseAt = function(base, id)
    if gen2IconIsSheet(id) then return base.icons and base.icons[id] or nil end
    return base.species and base.species[id] or nil
  end,
  gen2BaseIds = function(base)
    local ids = {}
    for id in pairs(base.icons or {}) do ids[#ids + 1] = id end
    for id in pairs(base.species or {}) do ids[#ids + 1] = id end
    return ids
  end,
  gen2Write = function(target, registry)
    local sheets, species = target.icons, target.species
    if not sheets then
      sheets = {}
      target.icons = sheets
    end
    if not species then
      species = {}
      target.species = species
    end
    for _, id in ipairs(registry.order) do
      local into = gen2IconIsSheet(id) and sheets or species
      into[id] = registry:get(id)
    end
  end,
  example = 'mod.content.icons:register("MODMON", "QUADRUPED")  -- a built-in name, or { image = mod.assets:path("icon.png"), frames = 2 }',
  gen2Example = 'mod.content.icons:override("TOTODILE", "ICON_MONSTER")',
}

-- glyph codes are not bytes: the vanilla pages sit at $60/$80 but a
-- registered page takes a range of its own above them (a kana block at
-- $100), so neither a base nor a charmap code is capped at one byte.
-- Two id forms share the registry (14 §registry schemas): a bare id is a
-- page, "charmap:<name>" is one sequence->code row.  A page carries its own
-- charmap only as a convenience -- replacing a sheet must not force an
-- author to restate the table.
local function fontIsCharmap(id)
  return tostring(id):match("^charmap:.+$") ~= nil
end

-- the third id form: "ttf" switches text rendering to a real TTF (the
-- bundled Plain Pixel when `file` is omitted -- src/render/Font.lua)
local function fontIsTtf(id)
  return tostring(id) == "ttf"
end

R.font = {
  semantics = "record", target = "font",
  value = f.union{
    f.rec{ image = f.path, base = f.int(0), glyphsPerRow = f.opt(f.int(1)),
           advance = f.opt(f.int(1)),
           charmap = f.opt(f.list(f.rec{ code = f.int(0), seq = f.str })) },
    f.rec{ seq = f.str, code = f.int(0) },
    -- strict: every field here is optional ({} is a legal "ttf" entry), so
    -- with the usual top-level leniency this alternative would match ANY
    -- table and let malformed pages through the union unchecked
    f.rec({ file = f.opt(f.path), size = f.opt(f.int(1)),
            spacing = f.opt(f.num), yOffset = f.opt(f.num),
            bold = f.opt(f.bool),
            -- characters that keep their ROM tile instead of coming from the
            -- TTF: a string of them, or a list when a multi-character charmap
            -- sequence is meant (src/render/Font.lua)
            tiles = f.opt(f.union{ f.str, f.list(f.str) }) },
          { strict = true }),
  },
  extra = function(id, value)
    if fontIsCharmap(id) then
      if type(value.seq) ~= "string" or value.seq == "" then
        return "a charmap: entry needs a non-empty seq"
      end
      if type(value.code) ~= "number" then
        return "a charmap: entry needs a code"
      end
    elseif fontIsTtf(id) then
      -- every field optional: {} is "the bundled font at its native size"
      if value.image ~= nil or value.base ~= nil then
        return 'the "ttf" entry takes file/size/spacing/yOffset/bold/tiles, not a page'
      end
    elseif value.image == nil or value.base == nil then
      return "a font page needs an image and a base"
    end
  end,
  baseAt = function(base, id)
    if fontIsCharmap(id) then return nil end
    if fontIsTtf(id) then return base.ttf end
    return base.pages and base.pages[id] or nil
  end,
  baseIds = function(base)
    local ids = {}
    for id in pairs(base.pages or {}) do ids[#ids + 1] = id end
    return ids
  end,
  write = function(target, registry)
    local pages = target.pages or {}
    target.pages = pages
    -- the extractor never emits a ttf entry, so like the charmap rows it is
    -- rebuilt from the registry each merge: disabling the mod disables it
    target.ttf = nil
    -- the extractor's rows have no id and stay put; the registry's own are
    -- rebuilt every merge so a re-merge replaces them instead of stacking
    local rows = {}
    for _, entry in ipairs(target.charmap or {}) do
      if type(entry) ~= "table" or entry.id == nil then rows[#rows + 1] = entry end
    end
    for _, id in ipairs(registry.order) do
      local value = registry:get(id)
      if fontIsCharmap(id) then
        if value ~= nil then
          rows[#rows + 1] = { id = id, seq = value.seq, code = value.code }
        end
      elseif fontIsTtf(id) then
        target.ttf = value
      else
        pages[id] = value
      end
    end
    target.charmap = rows
  end,
  example = 'mod.content.font:register("charmap:hiragana_a", { seq = "\227\129\130", code = 256 })',
}

-- ------- scripting and text plumbing

-- a record is the bare handler (the v1 shape every engine verb still uses)
-- or the flagged table Commands.resolve already unpacks (09 §4.2)
R.commands = {
  semantics = "record", target = "commands",
  value = f.union{ f.fn, f.rec{ fn = f.fn, foreground = f.opt(f.bool),
                                blocking = f.opt(f.bool) } },
  example = 'mod.content.commands:register("shake_screen", function(ctx, frames) ... end)',
}

R.tokens = {
  semantics = "record", target = "tokens",
  value = f.fn,
  example = 'mod.content.tokens:register("CLOCK", function(game) return "12" end)',
}

-- ------- deep registries: id is a top-level key of the target table

-- Gold's `constants` is not the Gen 1 rule block at all: it is the ROM's own
-- ordered name lists, one per enum the cart indexes by number.  A script
-- opcode that says "special 12" or an animation that says "object 41" is
-- resolved through these, so replacing an entry renames what that number
-- means.  Every one of them is a dense list of ids in ROM order, which is why
-- they can be built from a name list instead of restated one by one.
local GEN2_CONSTANT_ORDERS = {
  "battleAnimBgPaletteOrder", "battleAnimFramesetOrder", "battleAnimFuncOrder",
  "battleAnimGfxOrder", "battleAnimOamsetOrder", "battleAnimObPaletteOrder",
  "battleAnimObjectOrder", "battleBgEffectOrder", "cmdQueueOrder",
  "decoDescOrder", "eggGroupOrder", "environmentOrder", "evolveMethodOrder",
  "fishGroupOrder", "floorOrder", "growthRateOrder", "heldEffectOrder",
  "iconOrder", "itemMenuOrder", "itemOrder", "landmarkOrder",
  "mapCallbackOrder", "mapOrder", "moveEffectOrder", "moveOrder", "musicOrder",
  "paletteOrder", "phoneContactOrder", "pocketOrder", "sfxOrder", "spawnOrder",
  "specialCallOrder", "specialOrder", "speciesOrder", "spriteOrder",
  "stdScriptOrder", "tilesetOrder", "tradeDialogOrder", "tradeGenderOrder",
  "trainerClassOrder", "trainerTypeOrder", "treeMonSetOrder",
}

local gen2ConstantKeys = {
  -- the map table the group/number pair in a warp resolves through
  mapGroups = f.list(f.rec{ group = f.int(0), map = f.int(0), name = f.str,
                            width = f.int(1), height = f.int(1) }),
  -- class id -> its named trainers, in the order the class's table stores them
  trainerClassMembers = f.map(f.str, f.list(f.str)),
  -- type id -> its ROM byte; the only one of these that is a lookup rather
  -- than an ordered list, because the type numbers are not contiguous
  types = f.map(f.str, f.int(0)),
  -- counts the extractor stamps beside the lists
  itemNameCount = f.int(0), numOverworldSprites = f.int(0),
  spritePokemon = f.int(0),
  source = f.str, generation = f.int(1),
}
for _, name in ipairs(GEN2_CONSTANT_ORDERS) do
  gen2ConstantKeys[name] = f.list(f.str)
end

-- The rules the engine used to hard-code as Kanto/Red literals.  Keys the
-- importer does not stamp are seeded with their vanilla value at data load
-- (src/core/Data.lua) so a patch always has something to fold over.
R.constants = {
  semantics = "deep", target = "constants",
  keys = {
    bagSize = f.int(1), partyMax = f.int(1),
    boxCount = f.int(1), boxSize = f.int(1),
    moveMax = f.int(1),
    dexSize = f.int(1), dexDigits = f.int(1),
    levelCap = f.int(1), coinCap = f.int(0), moneyCap = f.int(0),
    -- ordered: list position is the badge number the trainer card draws
    badges = f.list(f.rec{ id = f.id("items"), name = f.opt(f.str),
                           icon = f.opt(f.path), item = f.opt(f.id("items")) }),
    hmMoves = f.list(f.id("moves")),
    encounterBuckets = f.list(f.int(1, 256)),
  },
  -- Gold's keys are ordered lists where position IS the id a script byte
  -- resolves through, so they must replace rather than append -- which is
  -- what "deep" semantics would do to them (Merge.deepMerge concatenates
  -- lists there, and Gen 1's `field` rows genuinely want that).  A key
  -- neither catalog names is still a mod's own data and merges as-is.
  gen2Semantics = "record",
  gen2Keys = gen2ConstantKeys,
  example = 'mod.content.constants:patch("levelCap", 80)',
  gen2Example = 'mod.content.constants:patch("speciesOrder", '
    .. '{ [252] = "MODMON" })',
}

-- The overworld's data grab bag.  Only the keys this milestone routes are
-- typed; the rest of the 37-subtable inventory stays open until its
-- consumers move off their literals.
R.field = {
  semantics = "deep", target = "field",
  keys = {
    ledges = f.list(f.rec{
      facing = f.enum{ "up", "down", "left", "right" },
      input = f.enum{ "up", "down", "left", "right" },
      standingTile = f.int(0), ledgeTile = f.int(0),
      tileset = f.opt(f.id("tilesets")) }),
    hiddenItems = f.map(f.str, f.list(f.rec{
      x = f.int(0), y = f.int(0), item = f.id("items") })),
    badgeGates = f.map(f.str, f.rec{
      badge = f.opt(f.id("items")), text = f.opt(f.str),
      passText = f.opt(f.str), failText = f.opt(f.str),
      -- omit it and the gate gets "PASSED_<mapId>"; Route 22 keeps its
      -- pre-v2 spelling only because saves already carry that flag
      passedFlag = f.opt(f.str),
      coords = f.opt(f.list(f.rec{ x = f.int(0), y = f.int(0) })),
      guards = f.opt(f.list(f.any)) }),
    townMap = f.rec{
      background = f.opt(f.any),
      gridPixelSize = f.opt(f.int(1)),
      cursorOrder = f.opt(f.list(f.str)),
      locations = f.opt(f.map(f.str, f.rec{ x = f.int(0), y = f.int(0),
                                            name = f.opt(f.str) })),
      nest = f.opt(f.any) },
    flyOrder = f.list(f.str),
    -- the player's own trainer art (FieldDefaults.PLAYER_PICS): the battle
    -- back pic, the catch tutorial's old man, Yellow's PROF.OAK variant of
    -- it (#557), and the front pic the intro, trainer card and Hall of Fame
    -- share.  Every key is optional so a conversion can replace one pic and
    -- inherit the rest.
    playerPics = f.rec{
      back = f.opt(f.str), demoBack = f.opt(f.str),
      oakBack = f.opt(f.str), front = f.opt(f.str) },
    -- the new-game and boot config a total conversion replaces
    boot = f.rec{
      startMap = f.opt(f.str), startX = f.opt(f.int(0)), startY = f.opt(f.int(0)),
      startFacing = f.opt(f.enum{ "up", "down", "left", "right" }),
      playerName = f.opt(f.str), rivalName = f.opt(f.str),
      startMoney = f.opt(f.int(0)),
      lastHeal = f.opt(f.rec{ map = f.str, x = f.int(0), y = f.int(0) }),
      namePresets = f.opt(f.rec{ player = f.opt(f.list(f.str)),
                                 rival = f.opt(f.list(f.str)) }),
      screens = f.opt(f.rec{ splash = f.opt(f.str), title = f.opt(f.str),
                             newGame = f.opt(f.str) }),
      starterScript = f.opt(f.str),
      title = f.opt(f.any) },
  },
  example = 'mod.content.field:patch("boot", { startMap = "SABLE_COVE" })',
}

-- Every key is a map label carrying the same per-TEXT-constant shape, so
-- one keyValue types them all: a mod adds a single sign binding without
-- restating the map.  label is the extractor's field, text the authored
-- one; Data:resolveText reads text and falls back to the hand-ported
-- script when only asm is set.
R.text_pointers = {
  semantics = "deep", target = "text_pointers",
  keyValue = f.map(f.str, f.rec{
    text = f.opt(f.str), label = f.opt(f.str), asm = f.opt(f.bool),
    mart = f.opt(f.list(f.id("items"))),
    nurse = f.opt(f.bool), pc = f.opt(f.bool), cableClub = f.opt(f.bool),
  }),
  example = 'mod.content.text_pointers:patch("PalletTown", { TEXT_PALLETTOWN_SIGN = { text = "_MySign" } })',
}

-- ------- Gen 2 only content
--
-- The mirror of the gated rows in Schemas.GEN2: six systems Gold has and Red
-- does not, so there is no Gen 1 table to share a target with and no Gen 1
-- consumer to read one.  Each spec therefore carries NO `target` at all -- the
-- routed Schemas.GEN2 path is its only home -- and a Schemas.GEN1 row of
-- `false`, which is what turns a Red mod's write into the same reported drop a
-- Gold mod gets for `tokens` instead of a silent merge into a namespace
-- nothing on Red would ever read.
--
-- Names stay plain for the same reason hook and event names do: `decorations`
-- is what the thing is called, and a "gen2Decorations" registry NAME would be
-- a namespace no mod could ever share if Gen 1 grew the system later.  Only
-- the Data path underneath carries the gen2 prefix.

-- data/items/attributes.asm's last two columns, split out of the item record
-- so a mod can give an item a held behaviour without owning the whole item.
-- src/core/Game2.lua seeds the merge target from data.items and writes the
-- merged rows back onto it, and src/battle/gen2/Battle.lua's heldEffect (the
-- one read all eight held-item sites go through, and the held_item.trigger
-- hook's own site) reads it from there.
R.held_items = {
  semantics = "record",
  fields = {
    -- the HELD_* name the battle compares against, out of
    -- data.gen2Constants.heldEffectOrder; a mod may invent its own and steer
    -- it from the held_item.trigger hook
    heldEffect = f.str,
    -- ItemAttributes' parameter byte: the boost percentage, the heal amount,
    -- the BrightPowder odds -- whatever the effect reads it as
    heldParameter = f.opt(f.int(0, 255)),
  },
  example = 'mod.content.held_items:override("LEFTOVERS", '
    .. '{ heldEffect = "HELD_LEFTOVERS", heldParameter = 0 })',
}

-- data/phone/phone_contacts.asm, one record per PHONE_* row.  The id space is
-- data.gen2Constants.phoneContactOrder, so PHONE_YOUNGSTER_JOEY names the row
-- the cart calls PHONE_YOUNGSTER_JOEY; `index` is that row's byte, which is
-- what the save's contact list holds and what src/core/gen2/Phone.lua keys
-- every one of its own lookups by.  The four PHONE_UNUSED const_skip holes are
-- not registered -- they are copies of the wrong-number filler row, and one id
-- cannot name four of them.
R.phone_contacts = {
  semantics = "record",
  fields = {
    index = f.int(0),
    -- non-trainer rows (MOM, BILL, ELM, the BIKE SHOP) carry a PHONECONTACT_*
    -- number instead of a trainer; trainer rows carry the class and the
    -- roster member, which is what the rematch machinery and the caller's
    -- name are looked up by
    number = f.opt(f.int(0, 255)),
    class = f.opt(f.str), member = f.opt(f.str),
    map = f.opt(f.id("maps")),
    -- the SCRIPT1 / SCRIPT2 time masks: MORN | DAY | NITE, 0 for "never"
    calleeTime = f.opt(f.int(0, 7)), callerTime = f.opt(f.int(0, 7)),
    -- the script LABEL (Phone.SCRIPT_KEYS resolves it) and, once the cache
    -- has been read, the "<bank>:<addr>" pointer it resolved to
    callee = f.opt(f.str), caller = f.opt(f.str),
    calleeKey = f.opt(f.str), callerKey = f.opt(f.str),
  },
  example = 'mod.content.phone_contacts:patch("PHONE_YOUNGSTER_JOEY", '
    .. '{ map = "ROUTE_31" })',
}

-- data/decorations/attributes.asm, one record per DECO_* row.  The cart's
-- decoration constants are a bare const_def block with no name table behind
-- them -- nothing in the ROM spells DECO_FEATHERY_BED -- so the id is the
-- attribute row's own index, written "deco:<n>" the way battle_anims writes
-- "subanim:<n>".  That index IS wMenuSelection, which is what every caller
-- passes src/core/gen2/Decorations.lua.
R.decorations = {
  semantics = "record",
  fields = {
    -- constants/deco_constants.asm decoration types: 1 PLANT, 2 BED,
    -- 3 CARPET, 4 POSTER, 5 DOLL, 6 BIGDOLL.  The type decides how GetDecoName
    -- spells the row and whether `sprite` is a block id or a sprite one.
    type = f.int(1, 6),
    name = f.str,
    -- DECOATTR_ACTION, as the Decorations.ACTIONS key rather than the
    -- jumptable index; nil on the CANCEL row alone
    action = f.opt(f.str),
    -- DECOATTR_EVENT_FLAG: the wEventFlags bit that says the player owns it
    flag = f.int(0),
    -- DECOATTR_SPRITE: a BLOCK id for the four kinds the map paints, a
    -- SPRITE_* byte for the four an object stands on
    sprite = f.int(0, 255),
  },
  example = 'mod.content.decorations:patch("deco:2", { name = "COZY" })',
}

-- data/items/apricorn_balls.asm.  Id = the apricorn item, because that is what
-- the player hands Kurt and what FindApricornsInBag walks the bag for;
-- `index` is the row's position in that table, which is load bearing twice
-- (Kurt's menu order and the checkevent chain in maps/KurtsHouse.asm).
R.apricorns = {
  semantics = "record",
  fields = {
    apricorn = f.id("items"), ball = f.id("items"),
    -- constants/event_flags.asm index of this apricorn's EVENT_GAVE_KURT_*
    event = f.int(0),
    index = f.int(1),
  },
  example = 'mod.content.apricorns:override("RED_APRICORN", '
    .. '{ apricorn = "RED_APRICORN", ball = "ULTRA_BALL", event = 600, index = 1 })',
}

-- data/maps/landmarks.asm.  The town-map places, which on Gold are one index
-- space shared by the Pokegear MAP card, the #DEX AREA page and every map
-- header's `landmark` byte.  The merge lands inside the cache's own landmark
-- table (gen2Landmarks.landmarks), so a registered record is one the map card
-- can already draw.
R.landmarks = {
  semantics = "record",
  fields = {
    id = f.opt(f.str),
    -- the two-line name the town map prints, "\n" and all
    name = f.str,
    -- the marker's tile position on the 20x18 town map
    x = f.int(0), y = f.int(0),
    -- LANDMARK_*: the byte a map header carries, and what
    -- src/core/gen2/Nests.lua's region split reads
    index = f.int(0),
  },
  example = 'mod.content.landmarks:patch("LANDMARK_ROUTE_29", { x = 12 })',
}

-- PlayRadioStationPointers (engine/pokegear/pokegear.asm).  Id = the station
-- the dial resolves to, which is the LoadStation_* id the show state machine
-- is keyed by; `channel` is its MAPRADIO_* dial position, the byte a wall
-- radio's `setval` passes to the MapRadio special.  Position 0 is not a
-- station: it resolves by region and time of day, so no record claims it.
R.radio_channels = {
  semantics = "record",
  fields = {
    channel = f.int(0, 255),
    -- the name quoted in the text box; without one the Pokegear's own
    -- STATION_NAMES row is used, which is where the vanilla eight get theirs
    name = f.opt(f.str),
  },
  example = 'mod.content.radio_channels:register("PIRATE_RADIO", '
    .. '{ channel = 9, name = "PIRATE RADIO" })',
}

-- ------- persistence

-- compose, keyed by the owning mod id: the runner walks each owner's chain
-- in semver order against the versions recorded in the save
R.migrations = {
  semantics = "compose",
  value = f.rec{ since = f.str, run = f.fn },
  example = 'mod.content.migrations:register("my_mod", { since = "1.0.0", run = fn })',
}

-- ------- link play

-- id = the extra-bag mon field a mod wants to force fingerprint agreement on.
-- Only rev reaches the digest: pack/unpack are Lua, and function bytes are not
-- portably hashable, so the author bumps rev when the codec's meaning changes
-- (the affects_link mod version is the backstop when they forget).  No engine
-- content, so the registry is empty on a mod-free boot and the fingerprint's
-- link_fields section is absent on both peers.
R.link_fields = {
  semantics = "record", target = "link_fields",
  fields = {
    rev = f.union{ f.int(0), f.str },
    pack = f.opt(f.fn), unpack = f.opt(f.fn),
  },
  example = 'mod.content.link_fields:register("held_item", { rev = 1, pack = fn, unpack = fn })',
}

return Schemas
