-- Parity gate for the Gen 1 / Gen 2 mod API boundary.
--
-- The rule this file exists to hold: hook names, event names and registry
-- names are SHARED across generations, and the only things that differ are
-- where a registry's content lands and whether the mod runs at all.  A mod
-- opts into Gen 2 with `gen2compat` in its manifest and is left out of a Gold
-- boot entirely without it, because a mod that half-applies reads as broken.
--
-- Runs ROM-free: the generation is injected through the loader rather than by
-- booting Gold (T.sdk.loadMods opts.generation).

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
local Manifest = require("src.mods.Manifest")
local Schemas = require("src.mods.Schemas")
local StateStack = require("src.core.StateStack")

-- ------- 1. the version table knows its generation

T.eq(GameVersion.generation("red"), 1, "Red is Gen 1")
T.eq(GameVersion.generation("blue"), 1, "Blue is Gen 1")
T.eq(GameVersion.generation("yellow"), 1, "Yellow is Gen 1")
T.eq(GameVersion.generation("gold"), 2, "Gold is Gen 2")
T.eq(GameVersion.generation("silver"), 2, "Silver is Gen 2")
T.eq(GameVersion.generation("crystal"), 2, "Crystal is Gen 2")

-- ------- 2. manifest: gen2compat is opt-in and defaults off

local function manifest(extra)
  local raw = { id = "fix", name = "Fixture", version = "1.0.0",
                entry = "main.lua", api = 2 }
  for key, value in pairs(extra or {}) do raw[key] = value end
  return Manifest.validate(raw, "mods/fix")
end

T.eq(manifest().gen2compat, false,
  "a manifest that says nothing is Gen 1 only")
T.eq(manifest({ gen2compat = true }).gen2compat, true,
  "gen2compat = true is carried through")
T.eq(manifest({ gen2compat = false }).gen2compat, false,
  "gen2compat = false is carried through")
T.check(not pcall(manifest, { gen2compat = "yes" }),
  "a non-boolean gen2compat is rejected")

-- ------- 3. registry target routing
--
-- One routing table per generation (Schemas.routing): Gen 2 keeps the shared
-- target for everything it can serve and reports the rest instead of merging
-- into a table nothing reads, and Gen 1 does the same for the registries that
-- only exist because Gold does.  Gen 1 used to consult nothing at all; the
-- catalog now holds content BOTH ways round, so the claim is the symmetrical
-- one -- a registry is gated in a generation exactly when it has no home
-- there, whichever generation that is.

for name, spec in pairs(Schemas.REGISTRIES) do
  T.eq(Schemas.targetFor(name, spec, 1), spec.target,
    "Gen 1 keeps the catalog target: " .. name)
  if Schemas.GEN1[name] == nil then
    T.eq(Schemas.gatedFor(name, 1), false,
      "a registry Gen 1 routing says nothing about is not gated there: " .. name)
  else
    -- the mirror of the gated rows below: a Gen 2-only system, so there is no
    -- Gen 1 target to keep and a Red mod's write is dropped and reported
    -- rather than merged into a namespace no Gen 1 boot reads.  The per-
    -- registry cases are in tests/engine/gen2_content_registries.lua.
    T.eq(Schemas.gatedFor(name, 1), true, "gated under Gen 1: " .. name)
    T.eq(spec.target, nil,
      "a Gen 1-gated registry carries no Gen 1 target: " .. name)
    T.check(Schemas.targetFor(name, spec, 2) ~= nil,
      "and has a Gen 2 home, or the name is dead in both: " .. name)
  end
end

-- the registries Gold genuinely reads off game.data keep their name AND their
-- path, which is what lets one mod source target both generations.
-- `commands` is here rather than in the routed set below because the Gen 2 VM
-- resolves a mod verb out of the SAME merged data.commands table Gen 1's
-- runner does (src/script/gen2/Vm.lua:runModCommand, reached from the
-- Opcodes.MOD_COMMAND row a cart can never write).
for _, name in ipairs({ "pokemon", "moves", "items", "type_chart", "screens",
                        "strings", "font", "audio", "music", "sfx", "cries",
                        "map_songs", "commands",
                        -- `tokens` because TextBox.substitute reads
                        -- game.data.tokens on every box in both games, and
                        -- `growth_rates` because src/mods/Builtins.lua's Gen 2
                        -- registrant seeds Gold's curves as the same
                        -- { expForLevel } record Gen 1 uses, so one mod record
                        -- serves both (src/battle/gen2/Mon.lua:growthFor is the
                        -- single accessor all six Gen 2 readers go through)
                        "tokens", "growth_rates",
                        -- `battle_sprite_scales` because
                        -- src/ui/gen2/BattleState.lua:imageScale walks
                        -- data.battle_sprite_scales for a record whose .path
                        -- matches the pic being drawn, skipping `_owners`,
                        -- exactly as Gen 1's BattleState.imageBattleScale
                        -- does, and picScale falls through to the species'
                        -- battleScaleFront / battleScaleBack after it.  Only
                        -- the default differs (Red draws 32x32 back pics at
                        -- 2x, Gold's 48x48 ones fill their box at 1x) and the
                        -- default is not a registry record either side.
                        --
                        -- `render_pipelines` because src/core/Game2.lua:load
                        -- calls Pipelines.install(self.data) AFTER mods:load,
                        -- so src/render/Pipelines.lua walks the MERGED table,
                        -- and Game2:draw composites the whole-frame half
                        -- through Pipelines.wantsPresent / Pipelines.present.
                        -- Gold does not composite `drawWorld` yet -- its
                        -- overworld draws straight to the window -- and
                        -- Game2:load retires a restored drawWorld-only level
                        -- rather than leaving it on and drawing nothing, so
                        -- that half is inert rather than broken.  Routing it
                        -- is still right: the registry has a live reader, and
                        -- a gated registry would drop the `present` half too.
                        "battle_sprite_scales", "render_pipelines" }) do
  local spec = Schemas.REGISTRIES[name]
  T.check(spec ~= nil, "catalog still has registry: " .. name)
  T.eq(Schemas.targetFor(name, spec, 2), spec.target,
    "available under Gen 2 at its Gen 1 path: " .. name)
  T.eq(Schemas.gatedFor(name, 2), false, "not gated under Gen 2: " .. name)
end

-- The tables Gold namespaces: same registry NAME, a Gen 2 Data path
-- underneath it.  src/core/Game2.lua:load reads each of these into game.data
-- before mods:load runs, and the consumer holds it by reference --
-- src/world/gen2/World.lua:dataTable for the overworld four, the menus for
-- palettes/icons/battle_anims/constants -- so the merge lands in the table the
-- game walks.  The battle-rule six have no table on disk at all: they come
-- into existence AS the merge (src/mods/Builtins.lua seeds Gold's own records
-- there), and each consumer reads them through a per-id lookup that falls back
-- to the module's records, so a mod-free boot behaves identically.
-- The pairing is asserted both ways round: routed is NOT the Gen 1 target
-- (that would mean merging into a table no Gold boot reads) and NOT nil (that
-- would mean the write is being dropped).
for name, path in pairs({ maps = "gen2Maps", tilesets = "gen2Tilesets",
                          sprites = "gen2Sprites", text = "gen2Text",
                          encounters = "gen2Encounters",
                          trainers = "gen2Trainers",
                          palettes = "gen2Palettes", icons = "gen2Icons",
                          battle_anims = "gen2BattleAnims",
                          constants = "gen2Constants",
                          statuses = "gen2Statuses",
                          move_effects = "gen2MoveEffects",
                          item_effects = "gen2ItemEffects",
                          balls = "gen2Balls",
                          ai_classes = "gen2AiClasses",
                          evolution_methods = "gen2EvolutionMethods" }) do
  local spec = Schemas.REGISTRIES[name]
  T.check(spec ~= nil, "catalog still has registry: " .. name)
  T.eq(Schemas.targetFor(name, spec, 2), path,
    "available under Gen 2 at its Gen 2 path: " .. name)
  T.check(Schemas.targetFor(name, spec, 2) ~= spec.target,
    "a routed registry does not keep the Gen 1 path: " .. name)
  T.eq(Schemas.gatedFor(name, 2), false, "not gated under Gen 2: " .. name)
  T.eq(Schemas.targetFor(name, spec, 1), spec.target,
    "and Gen 1 is untouched by the routing: " .. name)
end

-- The mirror set: six registries that exist because GOLD does.  They carry no
-- Gen 1 target at all, so the routed path is the only path they ever have, and
-- Schemas.GEN1 gates them on Red the way Schemas.GEN2 gates `map_scripts` on Gold.
-- Each is held to a live consumer, which is the claim that matters: a routed
-- registry nothing reads is the silent no-op the whole routing table exists to
-- prevent.  The per-consumer cases are in
-- tests/engine/gen2_content_registries.lua; here the pairing itself is pinned.
--   held_items      src/core/gen2/ItemEffects.lua:heldItemFor / applyHeldItems,
--                   written back onto data.items for Battle:itemDef
--   phone_contacts  src/core/gen2/Phone.lua:useRegistry
--   decorations     src/core/gen2/Decorations.lua:attributes
--   apricorns       src/core/gen2/Apricorns.lua:useRegistry
--   landmarks       src/core/gen2/Nests.lua:landmarkId / landmark
--   radio_channels  src/ui/gen2/MapRadio.lua:channelRecord
for name, path in pairs({ held_items = "gen2HeldItems",
                          phone_contacts = "gen2PhoneContacts",
                          decorations = "gen2Decorations",
                          apricorns = "gen2Apricorns",
                          landmarks = "gen2Landmarks.landmarks",
                          radio_channels = "gen2RadioChannels" }) do
  local spec = Schemas.REGISTRIES[name]
  T.check(spec ~= nil, "catalog still has registry: " .. name)
  T.eq(Schemas.targetFor(name, spec, 2), path,
    "a Gen 2-only registry is available under Gen 2: " .. name)
  T.eq(Schemas.gatedFor(name, 2), false, "not gated under Gen 2: " .. name)
  T.eq(spec.target, nil,
    "and carries no Gen 1 target to fall back on: " .. name)
  T.eq(Schemas.gatedFor(name, 1), true,
    "so a Red boot reports the write rather than merging it: " .. name)
  T.eq(Schemas.targetFor(name, spec, 1), nil,
    "and has no Gen 1 path at all: " .. name)
end

-- and the ones Gold has no home for are gated, not silently retargeted.
-- One cause is left behind these: Gold reimplements the system WITHOUT
-- reading a registry, so there is no table a merge could land in that anything
-- would read.  Closing one is a consumer change in the Gen 2 module first and
-- a routing row second, which is exactly how growth_rates closed --
-- src/battle/gen2/Mon.lua grew growthFor / registerInto and takes an
-- expForLevel record ahead of the coefficient row, so the registry now routes
-- to the SHARED Gen 1 path and one mod record serves both games.
--
-- `tokens` was on this list by mistake rather than by cause: TextBox.new runs
-- TextBox.substitute on every box in both generations and substitute reads
-- game.data.tokens, so the shared target was live on Gold the whole time.
-- `battle_sprite_scales` and `render_pipelines` came off it the way
-- growth_rates did, consumer first: src/ui/gen2/BattleState.lua:imageScale now
-- reads data.battle_sprite_scales, and src/core/Game2.lua:load installs
-- src/render/Pipelines.lua on Gold's merged dataset after mods:load so
-- Game2:draw composites a `present` pipeline.  Both are asserted in the shared
-- set above.
--
-- `transitions` stays because Gold's own intro
-- (src/ui/gen2/BattleTransition.lua) keys STYLES as a boolean SET of the four
-- cart wipes rather than the { frames, draw, sound, flash } record this
-- registry carries, and has no styleDef lookup a mod id could reach.
--
-- map_scripts is the one genuine script-side gap left: src/script/gen2/Vm.lua
-- runs the cart's bytecode out of data.gen2Scripts keyed by ROM pointer, and a
-- Lua row list merged into that pool is not something the VM can run.
for _, name in ipairs({ "map_scripts", "rulesets", "transitions",
                        "field", "text_pointers", "link_fields" }) do
  local spec = Schemas.REGISTRIES[name]
  T.check(spec ~= nil, "catalog still has registry: " .. name)
  T.eq(Schemas.targetFor(name, spec, 2), nil,
    "gated registry has no Gen 2 target: " .. name)
  T.eq(Schemas.gatedFor(name, 2), true, "gated under Gen 2: " .. name)
end

-- A routed registry is only routed if the records already sitting at that
-- path pass the shared schema, so this pins the two optional warp fields Gen 2
-- carries (the ROM map-group pair) that a strict record would otherwise
-- reject on every one of Gold's 368 maps.
do
  local spec = Schemas.REGISTRIES.maps
  local gen2Map = {
    id = "MOD_TOWN", tileset = "TILESET_JOHTO", width = 2, height = 2,
    blocks = { 1, 2, 3, 4 },
    warps = { { x = 6, y = 3, destMap = "ELMS_LAB", destWarp = 1,
                destGroup = 24, destMapNum = 5 } },
  }
  T.check(Schemas.check(spec, "maps", "MOD_TOWN", gen2Map, "register"),
    "a Gen 2 warp row validates against the shared maps schema")
  local gen1Map = {
    id = "MOD_TOWN", tileset = "OVERWORLD", width = 2, height = 2,
    blocks = { 1, 2, 3, 4 },
    warps = { { x = 1, y = 1, destMap = "PALLET_TOWN", destWarp = 1 } },
  }
  T.check(Schemas.check(spec, "maps", "MOD_TOWN", gen1Map, "register"),
    "and the Gen 1 warp row still does, the added fields being optional")
end

-- ------- 3b. the per-generation RECORD shape
--
-- Routing says where a registration lands; this says what a record there looks
-- like.  A registry whose Gen 2 records differ carries gen2Fields / gen2Keys /
-- gen2Write beside the Gen 1 slots and Schemas.shapeFor folds them onto the
-- canonical names, which is what let the six shaped registries above be routed
-- at all: without it a Gold species would be judged against Red's `special`.

do
  local spec = Schemas.REGISTRIES.pokemon
  T.eq(Schemas.shapeFor("pokemon", spec, 1), spec,
    "Gen 1 gets the catalog spec itself, not a copy")
  local gen2 = Schemas.shapeFor("pokemon", spec, 2)
  T.check(gen2 ~= spec, "Gen 2 gets a derived spec")
  T.eq(Schemas.shapeFor("pokemon", gen2, 2), gen2,
    "resolving a derived spec again is a no-op")
  T.check(gen2.fields.levelMoves ~= nil and gen2.fields.level1Moves == nil,
    "the Gen 2 species shape is folded onto `fields`")
  T.eq(gen2.gen2Fields, nil, "and the gen2* keys are gone from the derived spec")
  T.eq(gen2.target, "pokemon",
    "a reshaped registry that is not rerouted keeps its path")

  -- the split special stats, which is the difference that makes register
  -- usable on Gold at all
  local gold = {
    id = "MODMON", name = "MODMON", dex = 252,
    types = { "GRASS" },
    baseStats = { hp = 45, attack = 49, defense = 49, speed = 45,
                  specialAttack = 65, specialDefense = 65 },
    catchRate = 45, baseExp = 64, growthRate = "MEDIUM_SLOW",
    levelMoves = { { level = 1, move = "FIX_TACKLE" } },
    evolutions = {},
    spriteFront = "a.png", spriteBack = "b.png", picSize = 5,
  }
  T.check(Schemas.check(spec, "pokemon", "MODMON", gold, "register", 2),
    "a Gen 2 species record registers under Gen 2")
  T.check(not Schemas.check(spec, "pokemon", "MODMON", gold, "register", 1),
    "and the same record is not a Gen 1 species")
  local _, err = Schemas.check(spec, "pokemon", "FIXMON_A",
    { baseStats = { special = 80 } }, "patch", 2)
  T.check(err ~= nil and err:match("special"),
    "a Gen 1 baseStats.special is rejected under Gen 2: " .. tostring(err))
end

do
  -- trainers routes one level further in, into .classes, and battle_anims
  -- CLEARS the Gen 1 write (there the ids are the subtables the Gen 1 write
  -- would have routed into)
  local trainers = Schemas.shapeFor("trainers", Schemas.REGISTRIES.trainers, 2)
  T.eq(trainers.target, "gen2Trainers", "the derived spec carries the routed path")
  T.check(trainers.write ~= nil and trainers.baseAt ~= nil
    and trainers.baseIds ~= nil,
    "trainers reaches into .classes through write/baseAt/baseIds")
  local anims = Schemas.shapeFor("battle_anims", Schemas.REGISTRIES.battle_anims, 2)
  T.eq(anims.write, nil, "gen2Write = false clears the Gen 1 write")
  T.eq(anims.baseAt, nil, "and the Gen 1 baseAt with it")
  T.check(anims.keys ~= nil and anims.value == nil,
    "a Gen 2 shape described by keys clears the Gen 1 value slot")
end

-- a Gen 2 shape on a registry with no Gen 2 home would be dead code: nothing
-- ever validates against it, because the write is dropped before it is checked
for name, spec in pairs(Schemas.REGISTRIES) do
  if Schemas.hasGen2Shape(spec) then
    T.eq(Schemas.gatedFor(name, 2), false,
      "a registry with a Gen 2 shape is not gated: " .. name)
  end
end

-- every routing entry names a real registry, so a rename cannot leave a
-- stale row behind that silently stops gating anything
for name in pairs(Schemas.GEN2) do
  T.check(Schemas.REGISTRIES[name] ~= nil,
    "Schemas.GEN2 names a real registry: " .. name)
end

-- a routed path must not be some other registry's path: two registries
-- folding into one table would let the second one's ids overwrite the first's
do
  local claimed = {}
  for name, spec in pairs(Schemas.REGISTRIES) do
    local path = Schemas.targetFor(name, spec, 2)
    if path then
      T.check(claimed[path] == nil or claimed[path] == name,
        ("two registries share one Gen 2 path (%s): %s and %s")
          :format(path, tostring(claimed[path]), name))
      claimed[path] = name
    end
  end
end

-- ------- 4. the shared names, raised from Gold's own call sites
--
-- The rule: when a Gen 2 call site lands for something Gen 1 already names,
-- it reuses the EXACT name, so one mod's subscription serves both games.  The
-- catalog reads the names back out of the source (tests/modkit/catalog.lua
-- scans for Runtime.emit / Runtime.call), so each name below is held to
-- having BOTH a site inside a Gen 2 module and a site outside one.  A
-- "gen2.world.stepped" would satisfy the first half and fail the second,
-- which is exactly the drift this gate exists to catch; so would quietly
-- deleting Gold's site while docs/mod-api-gen2-compat.md still promises it.
--
-- Payload parity cannot be checked here (the shapes come from a live Gold
-- boot, and this file is ROM-free); tests/engine/gate_hooks.lua and
-- gate_events.lua carry the per-payload cases, and the Gen 2 sites were
-- proved against the gold_* drivers.

local Catalog = T.catalog

-- Gold's modules live under a gen2/ directory, except the two that own the
-- boot and the extractor and carry the generation in their name
local function isGen2Site(path)
  return path:match("gen2") ~= nil or path:match("Gen2") ~= nil
    or path:match("Game2") ~= nil
end

local GEN2_EVENTS = {
  -- overworld
  "map.entered", "map.exited", "map.reloaded", "player.warped",
  "world.stepped", "world.interacted", "world.npc_spawned",
  "world.trainer_engaged", "world.blacked_out", "world.block_replaced",
  "world.boulder_moved", "world.tod_changed", "world.object_toggled",
  "flag.changed",
  -- battle
  "battle.started", "battle.ended", "battle.turn_started", "battle.turn_ended",
  "battle.move_used", "battle.damage_dealt", "battle.fainted",
  "battle.status_inflicted", "battle.battler_switched", "battle.ball_thrown",
  "battle.exp_gained", "pokemon.level_up", "pokemon.move_learned",
  -- the catch and the evolution themselves: pushCaught emits after the mon is
  -- in the party or the box, Evolution.apply after the species swap, both
  -- matching the Gen 1 payload keys
  "pokemon.caught", "pokemon.evolved",
  -- boot, save and the script VM
  "game.ready", "save.created", "save.loaded", "save.loading", "save.writing",
  "script.started", "script.ended",
  -- The new-game speech.  Gold's is a different scene (Elm, not Oak, and its
  -- own src/ui/gen2/OakSpeech.lua), but it is the SAME moment -- the intro
  -- asking the player for the answers a save is built from -- so it keeps Gen
  -- 1's four names and payload keys rather than inventing "intro.elm_speech".
  "intro.oak_speech.started", "intro.oak_speech.step",
  "intro.oak_speech.answered", "intro.oak_speech.finished",
}

local GEN2_HOOKS = {
  -- overworld
  "warp.destination", "movement.collision", "movement.speed",
  "encounter.roll", "encounter.species", "encounter.fishing",
  "world.tod", "map.palette", "fieldmove.eligibility",
  -- menus and the battle intro
  "ui.start_menu.items", "ui.title_menu.items", "ui.options.rows",
  "ui.party.submenu", "ui.party.grid_navigation", "ui.naming.grid",
  "ui.pc.items", "ui.list_menu",
  "transition.style",
  -- battle
  "battle.damage", "battle.crit", "battle.accuracy",
  "battle.charge_required", "battle.turn_order",
  "battle.enemy_action", "battle.run", "battle.exp_award", "exp.gain",
  "catch.rate", "trainer.party",
  -- one wrap cancels or forces an evolution in either game: Gold passes `data`
  -- where Gen 1 passes `game`, and positions 2-4 (mon, row, trigger) match
  "evolution.check",
  -- save and the script VM
  "save.write", "save.new_game", "script.command",
  -- the intro's step list, wrapped before the first card draws.  Same hook,
  -- same (steps, speech) arguments and same "return the list" contract as
  -- src/ui/OakSpeech.lua's, so one wrapper reorders either game's speech.
  "intro.oak_speech.build",
  -- Battle seams Gold raises from src/battle/gen2/Battle.lua and
  -- src/ui/gen2/BattleState.lua.  battle.low_health_alarm carries `data` on
  -- Gold where Gen 1's vanilla link reads ctx.battle.data: Gold's battle
  -- screen has no .data field, so the key is ADDED beside the Gen 1 ones
  -- rather than the payload being reshaped (docs/mod-api-gen2-compat.md warns
  -- that a Gen 1 mod reaching through ctx.battle.data instead of calling
  -- nextFn gets nil there).
  "battle.catch_exp", "battle.low_health_alarm", "battle.overlay",
  "battle.bottom_ui_visible", "battle.status_hud_visible",
  "battle.move_grid_navigation",
  -- One pic path resolver for both games: the Gen 1 site is the SHARED
  -- src/pokemon/Sprites.lua and Gold's own battle screen calls the same hook
  -- with the Gen 1 ctx keys plus `letter` and `shiny`, which Red has no
  -- concept of.
  "pokemon.sprite",
  -- The player's own trainer pic, same story: the Runtime.call is the shared
  -- src/pokemon/Sprites.lua and Gold's battle back pic, Hall of Fame and intro
  -- resolve their own path into Sprites.playerPic with the Gen 1 ctx keys.
  "player.sprite",
  -- The frame itself, from src/core/Game2.lua, in the same places
  -- src/core/Game.lua raises them: the logic tick before the pad is read, a
  -- pointer with the touch overlay given first refusal, the palette zone list
  -- handed to the present pass, the letterbox and the HUD rect.
  "input.step", "input.pointer",
  "render.zones", "render.compose", "render.output_enabled", "render.output",
  "render.letterbox", "render.hud",
}

local function assertShared(name, sites, kind)
  local gen2, gen1 = 0, 0
  for _, path in ipairs(sites) do
    if isGen2Site(path) then gen2 = gen2 + 1 else gen1 = gen1 + 1 end
  end
  T.check(gen2 > 0, ("Gold raises the %s: %s"):format(kind, name))
  T.check(gen1 > 0,
    ("the %s %s is shared, not a Gen 2 invention (no Gen 1 site)")
      :format(kind, name))
end

for _, name in ipairs(GEN2_EVENTS) do
  assertShared(name, Catalog.eventSites(name), "event")
end
for _, name in ipairs(GEN2_HOOKS) do
  assertShared(name, Catalog.hookSites(name), "hook")
end

-- and the lists are COMPLETE, not a sample.  Without this half the gate only
-- catches a seam being taken away; a Gen 2 site landing for a Gen 1 name and
-- never reaching docs/mod-api-gen2-compat.md is the other drift, and it is the
-- more likely one -- the doc is where an author looks to decide whether a
-- subscription serves both games, so an unlisted shared seam reads as absent.
local function assertListed(names, catalogNames, sites, kind)
  local listed = {}
  for _, name in ipairs(names) do listed[name] = true end
  for _, name in ipairs(catalogNames) do
    if not Catalog.isModEvent(name) then
      local gen2, gen1 = false, false
      for _, path in ipairs(sites(name)) do
        if isGen2Site(path) then gen2 = true else gen1 = true end
      end
      if gen2 and gen1 then
        T.check(listed[name],
          ("%s %s has a site in both generations but is not in this gate's "
            .. "list; add it here and to docs/mod-api-gen2-compat.md")
            :format(kind, name))
      end
    end
  end
end

assertListed(GEN2_EVENTS, Catalog.events(), Catalog.eventSites, "event")
assertListed(GEN2_HOOKS, Catalog.hooks(), Catalog.hookSites, "hook")

-- and nothing anywhere invents a generation-prefixed name.  New-in-Gen-2
-- systems (held_item.trigger, egg.hatched) get plain names of their own;
-- "gen2." would be a namespace no Gen 1 mod could ever match.
for _, name in ipairs(Catalog.events()) do
  T.check(name:sub(1, 5) ~= "gen2.", "no generation-prefixed event: " .. name)
end
for _, name in ipairs(Catalog.hooks()) do
  T.check(name:sub(1, 5) ~= "gen2.", "no generation-prefixed hook: " .. name)
end

-- ------- 4b. the seams Gen 2 invents
--
-- The other half of the shared-name rule.  Section 4 holds a name Gen 1
-- already has to keeping it; these are the systems Red does not have at all
-- (friendship, breeding, the Pokegear, the radio, Pokerus, the roamers, Kurt,
-- the Bug Contest, the Unown puzzle, mail, held items, shininess and gender),
-- so a NEW name is justified -- and the discipline is the same one from the
-- other side: a plain name, never a "gen2." namespace no Gen 1 mod could
-- match, so that when Red ever grows the system the name is already right.
--
-- Three things are asserted per seam, and each one has failed at some point in
-- a review of this programme:
--
--   1. the site exists at all.  docs/mod-api-gen2-compat.md promises these by
--      name, so a deleted emit is doc drift the moment it happens.
--   2. every site is inside a Gen 2 module.  If a Gen 1 site ever appears the
--      seam is no longer Gen 2-only and belongs in the shared lists above,
--      where BOTH halves are checked -- this is the tripwire for that move.
--   3. the site is guarded by Runtime.wants / wantsHook for its own name, so a
--      mod-free boot allocates no payload table.  Several of these sit in the
--      step loop (happiness.changed, roamer.moved) or in the damage path
--      (held_item.trigger, eight triggers a turn), where an unguarded emit is
--      a per-frame cost every player pays for a feature nobody enabled.
--
-- Payload keys are not checkable here (this file is ROM-free);
-- tests/engine/gen2_new_seams.lua drives each one through a live bus and
-- asserts the payload the call site documents.

local GEN2_ONLY_EVENTS = {
  "happiness.changed", "breeding.egg_created", "egg.hatched",
  "phone.call_received", "clock.day_changed", "pokerus.infected",
  "roamer.moved", "roamer.encountered", "apricorn.converted",
  "bug_contest.scored", "unown.unlocked", "radio.channel",
  "mail.written", "mail.read",
  -- The GS boot cinema, card by card.  Red boots straight into its title
  -- screen, so there is no Gen 1 moment for these to share a name with; they
  -- are plain names rather than "gen2." ones so that the day Red grows a
  -- cinema the name is already right.  Each fires as its card comes UP, with
  -- movie_ended the one card END worth a name of its own (it is where the
  -- attract loop restarts).
  "intro.boot.copyright", "intro.boot.gamefreak", "intro.boot.movie",
  "intro.boot.movie_ended", "intro.boot.title",
}

local GEN2_ONLY_HOOKS = {
  "held_item.trigger", "breeding.compatibility", "phone.contact_list",
  "shiny.roll", "gender.roll",
}

local sourceCache = {}
local function sourceOf(path)
  if sourceCache[path] == nil then
    local handle = io.open(path, "r")
    sourceCache[path] = handle and handle:read("*a") or false
    if handle then handle:close() end
  end
  return sourceCache[path] or nil
end

local function assertGen2Only(name, sites, kind, guard)
  T.check(#sites > 0, ("Gold raises the Gen 2-only %s: %s"):format(kind, name))
  local guarded = false
  for _, path in ipairs(sites) do
    T.check(isGen2Site(path),
      ("a Gen 2-only %s is raised from a Gen 2 module (%s is not one): %s")
        :format(kind, path, name))
    local body = sourceOf(path)
    if body and body:find(('%s("%s")'):format(guard, name), 1, true) then
      guarded = true
    end
  end
  T.check(guarded,
    ("the %s %s is guarded by %s, so a mod-free boot pays nothing")
      :format(kind, name, guard))
end

for _, name in ipairs(GEN2_ONLY_EVENTS) do
  assertGen2Only(name, Catalog.eventSites(name), "event", "Runtime.wants")
end
for _, name in ipairs(GEN2_ONLY_HOOKS) do
  assertGen2Only(name, Catalog.hookSites(name), "hook", "Runtime.wantsHook")
end

-- complete both ways, like the shared lists: a seam raised ONLY from Gen 2
-- modules is by definition a Gen 2-only one, so if it is not listed above it
-- has skipped the guard check, the doc's payload table and gen2_new_seams.lua
-- all at once.
local function assertGen2OnlyListed(names, catalogNames, sites, kind)
  local listed = {}
  for _, name in ipairs(names) do listed[name] = true end
  for _, name in ipairs(catalogNames) do
    if not Catalog.isModEvent(name) then
      local anyGen1 = false
      for _, path in ipairs(sites(name)) do
        if not isGen2Site(path) then anyGen1 = true end
      end
      if not anyGen1 then
        T.check(listed[name],
          ("%s %s is raised from Gen 2 modules alone but is not listed as a "
            .. "Gen 2-only seam; add it here and to "
            .. "docs/mod-api-gen2-compat.md"):format(kind, name))
      end
    end
  end
end

assertGen2OnlyListed(GEN2_ONLY_EVENTS, Catalog.events(), Catalog.eventSites,
  "event")
assertGen2OnlyListed(GEN2_ONLY_HOOKS, Catalog.hooks(), Catalog.hookSites,
  "hook")

-- ------- 5. the gate, through a real load

local GEN1_ONLY = {
  ["mods/fix_gen1_only/manifest.json"] = [[{
    "id": "fix_gen1_only",
    "name": "Fixture Gen 1 Only",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/fix_gen1_only/main.lua"] = [[
    local mod = ...
    mod.content.pokemon:patch("FIXMON_A", { catchRate = 111 })
  ]],
}

local GEN2_READY = {
  ["mods/fix_gen2_ready/manifest.json"] = [[{
    "id": "fix_gen2_ready",
    "name": "Fixture Gen 2 Ready",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "gen2compat": true
  }]],
  ["mods/fix_gen2_ready/main.lua"] = [[
    local mod = ...
    -- one registry with a Gen 2 home, one without: the first applies in both
    -- generations, the second applies in Gen 1 and reports in Gen 2.
    -- `transitions` is the gated one because Gold draws its own battle intro
    -- (src/ui/gen2/BattleTransition.lua) and never composes through the Gen 1
    -- Renderer, so nothing on a Gold boot would ever read the merged record.
    mod.content.pokemon:patch("FIXMON_A", { catchRate = 123 })
    mod.content.transitions:register("FIXTURE_WIPE", { frames = 30 })
  ]],
}

local function files(...)
  local out = {}
  for _, set in ipairs({ ... }) do
    for path, body in pairs(set) do out[path] = body end
  end
  return out
end

local function statusOf(run, id)
  for _, entry in ipairs(run.loader:status().available) do
    if entry.id == id then return entry end
  end
  return nil
end

-- Gen 1: both mods run, both patches land
do
  local run = T.sdk.loadMods({ "mods/fix_gen1_only", "mods/fix_gen2_ready" }, {
    fs = T.sdk.memfs(files(GEN1_ONLY, GEN2_READY)),
    generation = 1,
  })
  T.eq(statusOf(run, "fix_gen1_only").state, "loaded",
    "Gen 1: a mod with no gen2compat loads")
  T.eq(statusOf(run, "fix_gen2_ready").state, "loaded",
    "Gen 1: a gen2compat mod loads too")
  T.eq(run.data.pokemon.FIXMON_A.catchRate, 123,
    "Gen 1: the later mod's patch merged")
  T.check(run.data.transitions ~= nil
    and run.data.transitions.FIXTURE_WIPE ~= nil,
    "Gen 1: transitions merged")
  run.release()
end

-- Gen 2: the undeclared mod is skipped whole, the declared one runs
do
  local run = T.sdk.loadMods({ "mods/fix_gen1_only", "mods/fix_gen2_ready" }, {
    fs = T.sdk.memfs(files(GEN1_ONLY, GEN2_READY)),
    generation = 2,
  })

  local skipped = statusOf(run, "fix_gen1_only")
  T.eq(skipped.state, "wrong_generation",
    "Gen 2: a mod with no gen2compat is not loaded")
  T.check(skipped.note ~= nil and skipped.note:match("gen2compat"),
    "Gen 2: the skip says why")
  T.eq(skipped.error, nil,
    "Gen 2: a skip is not reported as a failure")
  T.eq(skipped.enabled, true,
    "Gen 2: the player's enable flag is untouched by the skip")

  T.eq(statusOf(run, "fix_gen2_ready").state, "loaded",
    "Gen 2: the declared mod loads")

  -- the skipped mod's registration must leave no trace: 111 would mean it ran
  T.eq(run.data.pokemon.FIXMON_A.catchRate, 123,
    "Gen 2: only the declared mod's patch merged")

  -- a gated registry takes the write, drops it, and says so
  T.check(run.data.transitions == nil
    or run.data.transitions.FIXTURE_WIPE == nil,
    "Gen 2: a gated registry merges nothing")
  local told = false
  for _, message in ipairs(run.errors) do
    if message:match("transitions") and message:match("Gen 2") then told = true end
  end
  T.check(told, "Gen 2: the dropped registration is reported, not silent")
  run.release()
end

-- The drop is worded from the loader's own generation, because the gating runs
-- both ways: a Red boot rejecting a write to a Gen 2-only registry must not
-- claim the registry has "no Gen 2 target".  The registry name and the drop
-- were always right; the sentence was one-directional.
do
  local MIRROR = {
    ["mods/fix_gen1_drop/manifest.json"] = [[{
      "id": "fix_gen1_drop",
      "name": "Fixture Gen 1 Drop",
      "version": "1.0.0",
      "entry": "main.lua",
      "api": 2
    }]],
    ["mods/fix_gen1_drop/main.lua"] = [[
      local mod = ...
      mod.content.decorations:patch("deco:2", { name = "COZY" })
    ]],
  }
  local run = T.sdk.loadMods({ "mods/fix_gen1_drop" },
    { fs = T.sdk.memfs(MIRROR), generation = 1 })
  local told
  for _, message in ipairs(run.errors) do
    if message:match("decorations") then told = message end
  end
  T.check(told ~= nil,
    "Gen 1: a write to a Gen 2-only registry is reported")
  T.check(told and told:match("Gen 1"),
    "Gen 1: and the report names Gen 1, not Gen 2: " .. tostring(told))
  T.eq(run.data.gen2Decorations, nil, "Gen 1: and nothing merged")
  run.release()
end

-- ------- 5b. the vanilla records at a routed path are GOLD's
--
-- Six of the routed registries are the battle rules, and there the registry is
-- not just a merge target: src/battle/gen2/Catching.lua:recordFor,
-- Battle.statusRecordFor / moveEffectRecordFor, Ai.layersFor,
-- Evolution.methodFor and src/core/gen2/ItemEffects.lua:recordFor all read the
-- merged table.  So WHICH module seeds it is load bearing, and it is not the
-- one that seeds Red: the ids collide.  src/mods/Builtins.lua swaps the
-- registrant per generation and this holds it to that -- seeding Red's
-- GREAT_BALL would leave Gold's x1.5 multiplier nil, which reads as a ball
-- that quietly stopped working.
do
  local gen1 = T.sdk.loadNone({ generation = 1 })
  local gen2 = T.sdk.loadNone({ generation = 2 })

  local ball1 = gen1.loader.content.balls:get("GREAT_BALL")
  local ball2 = gen2.loader.content.balls:get("GREAT_BALL")
  T.check(ball1 ~= nil and ball1.hpFactor ~= nil and ball1.multiplier == nil,
    "Gen 1 seeds Red's GREAT_BALL (an HP factor, no multiplier)")
  T.check(ball2 ~= nil and ball2.multiplier == 1.5,
    "Gen 2 seeds Gold's GREAT_BALL (the x1.5 the cart multiplies by)")

  -- statuses are the clearest case of the shared NAME over different ids:
  -- Red writes BRN into mon.status where Gold writes "burn"
  T.check(gen1.loader.content.statuses:get("BRN") ~= nil,
    "Gen 1 seeds Red's status ids")
  T.check(gen2.loader.content.statuses:get("burn") ~= nil
    and gen2.loader.content.statuses:get("BRN") == nil,
    "Gen 2 seeds Gold's status ids and none of Red's")

  -- Ai.layersFor walks the merged table for mod-registered scoring passes, so
  -- Red's LAYER_1..LAYER_3 landing there would join Gold's ten
  T.check(gen1.loader.content.ai_classes:get("LAYER_1") ~= nil,
    "Gen 1 seeds Red's move-scoring layers")
  T.check(gen2.loader.content.ai_classes:get("LAYER_1") == nil
    and gen2.loader.content.ai_classes:get("SMART") ~= nil,
    "Gen 2 seeds Gold's scoring passes instead")

  -- and the Gen 2 VM's verb table is the mod verbs alone: a Gen 1 row-list
  -- verb handed Gold's ctx would find no runner on it
  T.check(gen1.loader.content.commands:get("show_text") ~= nil,
    "Gen 1 seeds the row-list verbs")
  T.eq(gen2.loader.content.commands:get("show_text"), nil,
    "Gen 2 seeds none of them")
  T.eq(gen2.data.commands, nil,
    "and a mod-free Gold boot leaves data.commands absent entirely")

  -- the seeded records land at the routed path, not the Gen 1 one
  T.check(gen2.data.gen2Statuses ~= nil and gen2.data.gen2Statuses.burn ~= nil,
    "the Gen 2 records merge into their Gen 2 path")
  T.eq(gen2.data.statuses, nil,
    "and nothing is written to the Gen 1 path a Gold boot never reads")
  T.check(gen1.data.statuses ~= nil and gen1.data.statuses.BRN ~= nil,
    "while Gen 1 is untouched by any of it")

  gen1.release()
  gen2.release()
end

-- A gated registry is an absent id space, not an empty one.  Gold's species
-- carry a growthRate exactly as Red's do, so a patch that keeps one must not
-- be reported as referencing something that does not exist just because the
-- Gen 1 `growth_rates` namespace has no Gen 2 home.  A ROUTED registry is the
-- opposite: `evolution_methods` has real ids on Gold now, so the same pass
-- resolves an evolution's method against them and a typo is caught.
local function refsFixture(body)
  return {
    ["mods/fix_refs/manifest.json"] = [[{
      "id": "fix_refs",
      "name": "Fixture Refs",
      "version": "1.0.0",
      "entry": "main.lua",
      "api": 2,
      "gen2compat": true
    }]],
    ["mods/fix_refs/main.lua"] = body,
  }
end

-- The ROM-free fixture dataset is Gen 1 shaped, and Gold hangs its experience
-- curves off data.pokemon.growthRates (which src/mods/Builtins.lua's Gen 2
-- registrant seeds the growth_rates registry from).  A generation-2 run over
-- unmodified fixtures therefore seeds no curves, and every fixture species'
-- growthRate reads as a dangling reference -- an artifact of the dataset, not
-- of the engine: on a real Gold boot the ids line up exactly (both sides say
-- GROWTH_MEDIUM_SLOW).  Added per-run rather than to tests/fixture_data, whose
-- shape is Gen 1's and whose fingerprint is a committed golden.
local function gen2Fixtures()
  local data = T.fixtures.fresh()
  -- pokegold data/growth_rates.asm's MEDIUM_SLOW row, under the id the fixture
  -- species reference
  data.pokemon.growthRates = {
    MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
                    linear = 100, constant = 140 },
  }
  return data
end

local function danglingRefs(run)
  local dangling = {}
  for _, message in ipairs(run.errors) do
    if message:match("unresolved reference") then
      dangling[#dangling + 1] = message
    end
  end
  return dangling
end

do
  -- the Gen 2 evolution row shape: `into` rather than `species`, and Gold's
  -- own EVOLVE_* method ids, which src/core/gen2/Evolution.lua seeds
  local run = T.sdk.loadMods({ "mods/fix_refs" }, {
    fs = T.sdk.memfs(refsFixture([[
      local mod = ...
      local base = mod.content.pokemon:get("FIXMON_A")
      mod.content.pokemon:patch("FIXMON_A", {
        catchRate = 90,
        growthRate = base.growthRate,
        evolutions = { { method = "EVOLVE_LEVEL", level = 16,
                         into = "FIXMON_B" } },
      })
    ]])),
    data = gen2Fixtures(),
    generation = 2,
  })
  local dangling = danglingRefs(run)
  T.eq(#dangling, 0,
    "Gen 2: a record whose refs all resolve reports nothing ("
      .. table.concat(dangling, "; ") .. ")")
  T.eq(run.data.pokemon.FIXMON_A.catchRate, 90, "Gen 2: the patch still landed")
  run.release()
end

do
  local run = T.sdk.loadMods({ "mods/fix_refs" }, {
    fs = T.sdk.memfs(refsFixture([[
      local mod = ...
      mod.content.pokemon:patch("FIXMON_A", {
        evolutions = { { method = "EVOLVE_BY_VIBES", level = 16,
                         into = "FIXMON_B" } },
      })
    ]])),
    data = gen2Fixtures(),
    generation = 2,
  })
  local dangling = danglingRefs(run)
  T.eq(#dangling, 1,
    "Gen 2: a routed registry HAS an id space, so a bad method is caught")
  T.check(dangling[1] and dangling[1]:match("evolution_methods"),
    "Gen 2: and the report names the registry it could not resolve against")
  run.release()
end

-- the skip is contagious as a SKIP.  A mod that DID claim gen2compat but sits
-- on one that did not is left out with the dependency's own wording, not
-- failed with "dependency X failed to load": neither mod has a bug and neither
-- belongs on the boot error list the player is shown.
do
  local DEPENDENT = {
    ["mods/fix_gen2_dependent/manifest.json"] = [[{
      "id": "fix_gen2_dependent",
      "name": "Fixture Gen 2 Dependent",
      "version": "1.0.0",
      "entry": "main.lua",
      "api": 2,
      "gen2compat": true,
      "dependencies": ["fix_gen1_only"]
    }]],
    ["mods/fix_gen2_dependent/main.lua"] = [[
      local mod = ...
      mod.content.pokemon:patch("FIXMON_A", { catchRate = 222 })
    ]],
  }
  local run = T.sdk.loadMods({ "mods/fix_gen1_only", "mods/fix_gen2_dependent" }, {
    fs = T.sdk.memfs(files(GEN1_ONLY, DEPENDENT)),
    generation = 2,
  })
  local dependent = statusOf(run, "fix_gen2_dependent")
  T.eq(dependent.state, "wrong_generation",
    "Gen 2: a dependent of a gate-skipped mod is skipped, not failed")
  T.eq(dependent.error, nil,
    "Gen 2: the dependent's skip is not reported as a failure")
  T.check(dependent.note ~= nil and dependent.note:match("gen2compat"),
    "Gen 2: the dependent's skip names the dependency's reason")
  T.eq(#run.errors, 0, "Gen 2: neither mod contributes a boot error")
  run.release()
end

-- the player's override: options.modsGen2 forces a mod past the gate, because
-- the manifest flag is the AUTHOR's claim and a mod written before the field
-- existed can never carry one
do
  local fs = T.sdk.memfs(files(GEN1_ONLY))
  fs.write("options.lua", require("src.core.SaveSerializer").encode({
    mods = {}, modsGen2 = { fix_gen1_only = true },
  }))
  local run = T.sdk.loadMods({ "mods/fix_gen1_only" },
    { fs = fs, generation = 2 })
  local forced = statusOf(run, "fix_gen1_only")
  T.eq(forced.state, "loaded", "Gen 2: the override loads an unclaimed mod")
  T.eq(forced.gen2Forced, true, "Gen 2: the manager sees the override")
  T.check(forced.note ~= nil and forced.note:match("not verified"),
    "Gen 2: a forced mod still says its author never claimed this game")
  T.eq(run.data.pokemon.FIXMON_A.catchRate, 111,
    "Gen 2: the forced mod's patch merged")
  run.release()
end

-- a skipped mod is skipped before validation, so a Gen 1 mod with a broken
-- manifest does not ALSO shout about its entry file on a Gold boot
do
  local BROKEN = {
    ["mods/fix_broken/manifest.json"] = [[{
      "id": "fix_broken",
      "name": "Fixture Broken",
      "version": "1.0.0",
      "entry": "missing.lua",
      "api": 2
    }]],
  }
  local run = T.sdk.loadMods({ "mods/fix_broken" },
    { fs = T.sdk.memfs(BROKEN), generation = 2 })
  T.eq(statusOf(run, "fix_broken").state, "wrong_generation",
    "Gen 2: the generation gate runs before entry-file validation")
  T.eq(#run.errors, 0, "Gen 2: a skipped mod contributes no boot errors")
  run.release()
end

-- ------- 6. StateStack:clear, which is what Gold's boot cinema hands off
-- through now that it runs the engine stack

do
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local order = {}
  local function state(name)
    return { isOpaque = true, exit = function() order[#order + 1] = name end }
  end
  stack:push(state("a"))
  stack:push(state("b"))
  stack:push(state("c"))
  stack:clear()
  T.eq(stack:top(), nil, "clear empties the stack")
  T.eq(table.concat(order, ","), "c,b,a", "clear unwinds top-first")
end

-- Without this the file printed its FAILs and exited 0, so the runner marked
-- the gate "ok" while it was red -- a gate that cannot fail is not a gate.
T.finish("gate_gen2_mod_api")
