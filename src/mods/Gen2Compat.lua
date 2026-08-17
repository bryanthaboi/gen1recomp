-- Gen 1 module facades for a Gen 2 boot: the Gen 1 API, backed by Gen 2
-- internals, handed to a mod's own require by src/mods/Loader.lua's shim.
-- Contract and the full table: docs/mod-api-gen2-compat.md.
--
-- Three rules, because a plausible wrong answer is worse than a missing
-- module: answered at CALL time (never a snapshot), absent or warned once when
-- Gold cannot back it, and one stable writable table for the whole run.
--
-- A fourth that decides facade-versus-alias: a name a mod MONKEY-PATCHES has
-- to resolve to the very table Gold runs, or the patch lands on a copy and
-- silently never fires.  Everything else is a translating facade, because an
-- alias to a Gen 2 module with a different argument list is the plausible
-- wrong answer in its purest form.
--
-- Gen2Compat.coverage() publishes which is which, per member, so the modkit
-- checker cannot drift from what is actually built here.

local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")

local Gen2Compat = {}

-- the genuine require: the Loader replaces _G.require while mods load
local rawRequire = require

-- injected by src/mods/Loader.lua: the live Game2, or nil before one exists
local resolveGame = nil

-- built adapters, one per name for the life of the process
local built = {}
-- mod ids that took each facade, for attribution in the warnings below
local claimants = {}
local warned = {}

local function warnOnce(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  Logger.warn(fmt, ...)
end

local function who(name)
  local ids = claimants[name]
  if not ids or #ids == 0 then return "a gen2compat mod" end
  return table.concat(ids, ", ")
end

local function live()
  return resolveGame and resolveGame() or nil
end

-- the live World, or nil plus one warning naming the member that wanted it
local function liveWorld(module, member)
  local g = live()
  local world = g and g.world
  if world then return world end
  warnOnce(module .. "." .. member .. ".noworld",
    "[%s] %s.%s: no world is up yet; the honest replacement is the "
    .. "game.ready / map.entered event", who(module), module, member)
  return nil
end

-- A member Gold cannot back: the call is answered with nil and named once,
-- with the mod that took the facade attributed.  Never a default.
local function unbacked(module, member, why)
  return function()
    warnOnce(module .. "." .. member,
      "[%s] %s.%s has no Gen 2 backing: %s",
      who(module), module, member, why)
    return nil
  end
end

-- ------- coverage
--
-- One machine-readable answer to "is this module served, and what happened to
-- each member".  Statuses are exactly three and the vocabulary is frozen:
--   backed  the member is present and does the Gen 1 job on Gold
--   warned  the member is present, answers nil (or degrades) and says so once
--   absent  the member is deliberately not on the table; a nil call is the
--           honest failure and calling it is a mod bug, not an adapter gap
-- `notes` carries the one-line reason a checker or a doc wants to quote.

local COVERAGE = {}

Gen2Compat.COVERAGE_VERSION = 1
Gen2Compat.STATUS = { BACKED = "backed", WARNED = "warned", ABSENT = "absent" }

local function words(s)
  local out = {}
  for w in tostring(s or ""):gmatch("%S+") do out[#out + 1] = w end
  return out
end

-- ------- src.core.Game
--
-- Gen 1's `Game` IS the running game (src/core/Game.lua:17); Game2 is a class
-- whose instance is minted per boot, so there is no table to alias.  The
-- proxy resolves every key against the live instance at read time.
--
-- Deliberately NOT a blanket forward: a dozen Gen 1 members Game2 simply
-- lacks would read nil with no word, and two (applyOptions, load) forward to a
-- Game2 method of the same name with a different contract.

-- data.sprites is a rename (gen2Sprites, src/mods/Schemas.lua:475); the rest
-- of the renames sit beside it.  data.constants is the one that must NOT be
-- routed: Gold's gen2Constants is the cart's ordered name lists, not Gen 1's
-- rule table, so the same word names a different thing.
local DATA_RENAMES = {
  sprites = "gen2Sprites", maps = "gen2Maps", tilesets = "gen2Tilesets",
  text = "gen2Text", encounters = "gen2Encounters", palettes = "gen2Palettes",
  icons = "gen2Icons", battle_anims = "gen2BattleAnims",
}

local DATA_UNBACKED = {
  field = "Gold's ledges are src/world/gen2/Permissions.lua and its tile "
    .. "pairs do not exist",
  constants = "data.gen2Constants is the cart's ordered NAME LISTS, not Gen "
    .. "1's rule table; partyMax / boxCount / badges have no Gold equivalent",
  text_pointers = "the extractor's Gen 1 pointer table has no Gold counterpart",
  trainer_headers = "the extractor's Gen 1 header table has no Gold counterpart",
}

local dataProxies = setmetatable({}, { __mode = "kv" })

local function dataProxy(data)
  if not data then return nil end
  local hit = dataProxies[data]
  if hit then return hit end
  hit = setmetatable({}, {
    __index = function(_, key)
      local renamed = DATA_RENAMES[key]
      if renamed then return data[renamed] end
      local why = DATA_UNBACKED[key]
      if why then
        warnOnce("data." .. key, "[%s] game.data.%s is Gen 1 only: %s",
          who("src.core.Game"), key, why)
        return nil
      end
      return data[key]
    end,
    __newindex = function(_, key, value) data[DATA_RENAMES[key] or key] = value end,
  })
  dataProxies[data] = hit
  return hit
end

-- Members Gen 1 answers and Gold does NOT, where a nil read would otherwise
-- pass for "the game says no" instead of "this API is not here".  Everything
-- Game2 genuinely carries forwards; everything else reads nil AND says so.
local GAME_UNBACKED = {
  renderer = "Gold composites in Game2:draw and never inits the Renderer "
    .. "singleton; Game2:pixelScale / :frameFit / :viewport are the honest "
    .. "replacements, and a Renderer alias would answer fitScale correctly "
    .. "while every state write silently no-opped",
  load = "calling it would re-run Gold's whole boot on top of a running game",
  bootConfig = "Gold's new-game inputs are Save.newGame's opts, not a "
    .. "data.field slice",
  makeTitleState = "Gen 2 pushes the title itself (Game2:showTitle); nothing "
    .. "returns a state to push",
  step = "Gold's logic tick is the FixedStep callback in Game2:load; the "
    .. "input.step hook fires at the identical moment",
}

-- Pure whole-stack walks that are not generation-bound at all; pulled off the
-- real Gen 1 module rather than copied, so they cannot drift.
local GAME_STACK_STATICS = {
  "worldBgBattleDim", "worldBgBattleInStack", "fillScaleInStack",
  "wideBattleInStack", "uiAnchorsHeldInStack", "drawBaseInStack", "dynamicUI",
}

local function buildGame()
  local proxy = {}
  local statics = nil

  local function gen1Static(key)
    if statics == nil then
      local ok, module = pcall(rawRequire, "src.core.Game")
      statics = ok and module or false
    end
    return statics and statics[key] or nil
  end

  local translate = {}

  -- `.overworld` is the Gen 1 spelling of Game2.world (src/core/Game2.lua:213)
  function translate.overworld(g) return g.world end
  function translate.data(g) return dataProxy(g.data) end
  function translate.fixedStep() return rawRequire("src.core.FixedStep") end

  function translate.writeOptions()
    return function()
      local g = live()
      if g and g.persistOptions then return g:persistOptions() end
    end
  end

  function translate.logicSpeed()
    return function()
      local g = live()
      if not g then return 1 end
      return math.max(1, tonumber(g.speedOverride)
        or tonumber(g.options and g.options.speed) or 1)
    end
  end

  -- Game2:applyOptions takes NO argument and applies self.options, so a
  -- blanket forward of Game:applyOptions(myTable) succeeds and applies the
  -- wrong table.  Adopt the argument first, exactly as Gen 1 does.
  function translate.applyOptions()
    return function(opts)
      local g = live()
      if not g then return end
      if opts and opts ~= proxy and opts ~= g.options then
        g.options = opts
        if g.save then g.save.options = opts end
      end
      return g:applyOptions()
    end
  end

  function translate.restoreSave()
    return function(loaded, recovered)
      local g = live()
      if not g then return end
      if recovered ~= nil then
        warnOnce("game.restoreSave.recovered",
          "[%s] Game:restoreSave's `recovered` and the quarantine report are "
          .. "unserved: Gold has no SaveData.validate pass",
          who("src.core.Game"))
      end
      return g:continueGame(loaded)
    end
  end

  function translate.restartWithMods()
    return function() return rawRequire("src.core.HostShell").restart() end
  end

  function translate.recoverInput()
    return function()
      local g = live()
      if not g then return end
      local Input = rawRequire("src.core.Input")
      local Touch = rawRequire("src.core.TouchControls")
      Input:reset()
      if Input.reconcile then Input:reconcile() end
      Touch:reset()
      if g.mods and g.mods.releaseModInput then g.mods:releaseModInput() end
      if g.cancelPointers then g:cancelPointers() end
    end
  end

  -- Gen 1's joystickadded runs the whole input recovery; Gold's is a noop, so
  -- a mod relying on hotplug recovery would get none and no signal.
  function translate.joystickadded()
    local recover = translate.recoverInput()
    return function(joystick)
      recover()
      local g = live()
      if g and g.joystickadded then g:joystickadded(joystick) end
    end
  end

  function translate.zoomStep()
    return function(delta)
      local g = live()
      if not (g and g.world and g.world.map) then return end
      g.world:zoomStep(delta)
      g.options = g.options or {}
      g.options.zoom = rawRequire("src.render.Zoom").offset
      if g.persistOptions then g:persistOptions() end
    end
  end

  setmetatable(proxy, {
    __index = function(_, key)
      local why = GAME_UNBACKED[key]
      if why then
        warnOnce("game." .. key, "[%s] Game.%s has no Gen 2 backing: %s",
          who("src.core.Game"), key, why)
        return nil
      end
      local made = translate[key]
      if made then
        local g = live()
        if not g and key ~= "writeOptions" and key ~= "logicSpeed"
            and key ~= "fixedStep" and key ~= "restartWithMods" then
          return nil
        end
        return made(g)
      end
      for _, name in ipairs(GAME_STACK_STATICS) do
        if name == key then return gen1Static(key) end
      end
      local g = live()
      if not g then return nil end
      local value = g[key]
      -- Gen 1 has it, Gold does not, and nothing above claimed it: nil is the
      -- answer either way, but a mod deserves to hear which nil this is.
      if value == nil then
        warnOnce("game.unknown." .. tostring(key),
          "[%s] Game.%s is not on the Gen 2 service owner; it reads nil "
          .. "because Game2 has no member of that name",
          who("src.core.Game"), tostring(key))
        return nil
      end
      -- a method reached through the facade gets the live game as self
      if type(value) == "function" then
        return function(first, ...)
          if first == proxy then return value(g, ...) end
          return value(first, ...)
        end
      end
      return value
    end,
    __newindex = function(_, key, value)
      local g = live()
      if not g then return end
      if key == "overworld" then g.world = value return end
      g[key] = value
    end,
  })
  return proxy
end

COVERAGE["src.core.Game"] = {
  kind = "facade",
  backed = "overworld data data.sprites data.maps data.tilesets data.text "
    .. "data.encounters data.trainers data.palettes data.icons "
    .. "data.battle_anims data.pokemon data.moves data.items data.type_chart "
    .. "data.font data.audio save mods modStatus input touchControls stack "
    .. "fixedStep speedOverride modPointers capturePath audioAccum "
    .. "writeOptions logicSpeed applyOptions restoreSave restartWithMods "
    .. "recoverInput zoomStep joystickadded returnToTitle update draw "
    .. "wheelmoved keypressed keyreleased gamepadpressed gamepadreleased "
    .. "gamepadaxis joystickpressed joystickreleased joystickaxis "
    .. "joystickhat joystickremoved focus visible onResume pointerEvent "
    .. "touchpressed touchmoved touchreleased mousepressed mousemoved "
    .. "mousereleased cancelPointers adoptSave writeSave worldBgBattleDim "
    .. "worldBgBattleInStack fillScaleInStack wideBattleInStack "
    .. "uiAnchorsHeldInStack drawBaseInStack dynamicUI",
  warned = "renderer load bootConfig makeTitleState step data.field "
    .. "data.constants data.text_pointers data.trainer_headers",
  absent = "linkNet linkSession saveReport save.money save.player.map "
    .. "save.player.x save.player.y save.player.facing save.player.rival "
    .. "save.defeatedTrainers save.meta save.box",
  notes = {
    identity = "the proxy can never compare equal to the Game2 instance the "
      .. "game.ready payload carries (5.1 fires __eq only when both operands "
      .. "share it)",
    iteration = "pairs/next/rawget see an EMPTY table; enumerate the "
      .. "game.ready payload instead",
    rawset = "rawset lands on the proxy, invisible to the engine, and reads "
      .. "back correctly through the same facade -- which is what hides it",
    ["save.money"] = "save.player.money on Gold",
    ["save.player.map"] = "save.position.map/x/y/facing on Gold",
    ["save.player.rival"] = "save.rival.name on Gold",
    keypressed = "F10, F5, backtick and `4` outside the world are silent "
      .. "no-ops on Gold; `2` cycles GbcPalette, not PaletteFX",
    keyreleased = "a Gold screen never sees onKeyReleased (#589)",
  },
}

-- ------- src.world.NPC
--
-- ALIAS, and it has to be: a mod tests getmetatable(npc) == the module it
-- required, or setmetatable(its own trailer, NPC).  A facade table cannot be
-- the metatable of an object built by src/world/gen2/Npc.lua, so the Gen 1
-- CONSTRUCTOR arity was added there instead (NPC.new sniffs a table first
-- argument) and the Gen 1 instance surface (pose, a camera-arity draw,
-- `marching`) with it.

local function buildNpc()
  local Npc2 = rawRequire("src.world.gen2.Npc")
  -- the sheet a Gen 1 objDef naming a Kanto SPRITE_* falls back to
  Npc2.fallbackSpriteDef = function()
    local g = live()
    return g and g.world and g.world.player and g.world.player.spriteDef
  end
  return Npc2
end

COVERAGE["src.world.NPC"] = {
  kind = "alias", target = "src.world.gen2.Npc",
  backed = "new __index facePlayer update walkPhase pose draw def id cellX "
    .. "cellY px py facing moving progress stepFlip frozen timer targetX "
    .. "targetY sprite spriteId passable stepFrames marching MOVE",
  warned = "",
  absent = "hopStep",
  notes = {
    new = "movement translated: WALK+UP_DOWN/LEFT_RIGHT to WALK_*, else "
      .. "WANDER with a {x=3,y=3} radius default (radius 0 freezes the "
      .. "object); STAY to STANDING_*, never STILL, which carries FIXED_FACING",
    facePlayer = "Gen 2 returns early for a fixed-facing object or a sheet "
      .. "with one frame, so a raw MOVE.STILL byte still no-ops",
    draw = "two arguments is read as a Gen 1 camera; three is Gold's "
      .. "(ox, oy, scale)",
    hopStep = "Gen 2 interpolates cell to target, so a two-cell hop is "
      .. "expressed by setting the target two cells out",
    update = "wanders / roamDirs are not read; Gold branches on npc.kind, and "
      .. "for kind == 'turn' roamDirs is a facing->facing MAP, not an array",
  },
}

-- ------- src.world.Map
--
-- ALIAS, for the same reason: a mod never builds a Map, it gets world.map, so
-- anything a facade added would be invisible.  The Gen 1 module-level statics
-- and the missing instance methods went into src/world/gen2/Map.lua.

COVERAGE["src.world.Map"] = {
  kind = "alias", target = "src.world.gen2.Map",
  backed = "new inBounds cellTile isWalkableCell isWaterCell isGrassCell "
    .. "isCounterCell warpAtCell blockAt setBlock tileAt isDoorTileCell "
    .. "isWarpTileCell signAtCell connection isOutdoor isOutside inRegion "
    .. "isPushable defCellTile defIsWalkableCell defIsWaterCell defPassable "
    .. "def tileset id widthCells heightCells DELTA warps",
  warned = "cellTile defCellTile",
  absent = "isFlyTown ghostBattles warpPadOrHoleAt walkable doorTiles "
    .. "warpTiles waterTiles renderer signAt",
  notes = {
    warpAt = "NAME COLLISION: Gen 1's map.warpAt is a TABLE keyed by cell, "
      .. "Gold's Map:warpAt is a METHOD of the same name.  map.warpAt[k] "
      .. "errors and pairs(map.warpAt) errors -- loud, but pointing at the "
      .. "mod.  Enumerate map.warps instead, which Gold carries as an "
      .. "ordered array",
    cellTile = "returns a COLL_* byte, not a Gen 1 tile id; unrelated number "
      .. "spaces, warned once on first call",
    isDoorTileCell = "the narrow arm (Permissions.isImmediateWarp): a door "
      .. "walked INTO, not a mat stood on",
    signAtCell = "coordinate-only, so it reports bg events World:bgEventAt "
      .. "would filter out by facing; the record is a bgEvent, not a sign, "
      .. "so sign.text is nil",
    isOutdoor = "Gold decides both isOutdoor and isOutside from the header's "
      .. "environment byte, so they collapse to one answer",
    isFlyTown = "Gold's fly destinations are landmark SPAWN POINTS, not a "
      .. "property of a def; ask world.landmarks.spawns",
    walkable = "Gold has no per-map tile set to extend; widen movement "
      .. "through the movement.collision hook, which Gold honours for the "
      .. "player and for NPC wandering",
    renderer = "Gold bakes whole-map images on the World; the equivalent "
      .. "operation is mod.world:replaceBlock",
  },
}

-- ------- src.world.Collision

local function buildCollision()
  local Map2 = rawRequire("src.world.gen2.Map")
  local Permissions = rawRequire("src.world.gen2.Permissions")
  local Collision = { DELTA = Map2.DELTA }

  function Collision.target(cx, cy, dir)
    local d = Map2.DELTA[dir]
    -- Gen 1 errors here (it indexes a nil DELTA row); softened deliberately,
    -- so a loop on a bad dir spins rather than crashing.
    if not d then return cx, cy end
    return cx + d[1], cy + d[2]
  end

  -- src/world/Collision.lua:20's contract, `passable` included
  function Collision.occupied(entities, cx, cy, ignore)
    for _, e in ipairs(entities or {}) do
      if e ~= ignore and not e.passable then
        if (e.cellX == cx and e.cellY == cy)
            or (e.targetX == cx and e.targetY == cy) then
          return e
        end
      end
    end
    return nil
  end

  -- Gold has no tile-pair table and no data.field to read one out of; the
  -- capability's Gen 2 home is Permissions, which is not data-driven.  A
  -- silent accept would leave the mod's intent unhappened with no trace.
  function Collision.load(_data)
    warnOnce("collision.load",
      "[%s] Collision.load: Gold has no data.field.tilePairs; ledges and side "
      .. "walls come from src/world/gen2/Permissions.lua, which is not "
      .. "data-driven", who("src.world.Collision"))
    return nil
  end

  local function passthrough(allowed) return allowed end

  -- The verdict Gold's own player gets one line later, not a walkable test:
  -- the surf exception and GetMovementPermissions' side-wall rule are both
  -- invisible to map:isWalkableCell, and without them the facade says yes
  -- where Gold bumps and no on every water cell a surfer is riding.
  local function verdict(map, entities, mover, dir, tx, ty)
    if not map:inBounds(tx, ty) then return false, "bounds" end
    if not map:isWalkableCell(tx, ty) then
      local surfable = mover.surfing
        and Permissions.surfable(map:cellCollision(tx, ty)) ~= nil
      if not surfable then return false, "tile" end
    end
    -- src/world/gen2/Map.lua:128, the refusal World:movePlayer applies BEFORE
    -- tryMove.  Reported as "tile", which is how it arrives at Gold's own
    -- verdict; Gen 1 has no name for it.
    if map.stepPermitted and not map:stepPermitted(mover.cellX, mover.cellY, dir)
    then
      return false, "tile"
    end
    if Collision.occupied(entities, tx, ty, mover) then return false, "entity" end
    return true
  end

  function Collision.canMove(map, entities, mover, dir)
    local tx, ty = Collision.target(mover.cellX, mover.cellY, dir)
    local allowed, why = verdict(map, entities, mover, dir, tx, ty)
    -- the mod's OWN movement.collision hook has to see its own canMove call,
    -- with the ctx keys both generations already use
    if Runtime.wantsHook("movement.collision") then
      local ctx = { map = map, mover = mover, dir = dir,
                    fromX = mover.cellX, fromY = mover.cellY,
                    toX = tx, toY = ty, reason = why }
      allowed = Runtime.call("movement.collision", passthrough, allowed, ctx)
      why = ctx.reason
    end
    if allowed then return true end
    return false, why
  end

  return Collision
end

COVERAGE["src.world.Collision"] = {
  kind = "facade",
  backed = "DELTA target occupied canMove",
  warned = "load",
  absent = "",
  notes = {
    DELTA = "the LIVE table, as under Gen 1: a mod that adds a key mutates "
      .. "Gold's own movement table",
    target = "returns (cx, cy) unchanged for an unknown dir where Gen 1 errors",
    canMove = "adds Gold's side-wall refusal (Map:stepPermitted) as reason "
      .. "'tile'; Gen 1's tile-pair check has no Gen 2 counterpart and drops",
    occupied = "tests targetX/Y unconditionally, as Gen 1 does; Gold's own "
      .. "loops test them only while moving",
  },
}

-- ------- src.world.FieldDefaults
--
-- Pure Lua with no love.* and no world.  Three members hold values that are
-- TRUE on Gold and are answered; the FIELD half is Kanto content and stays
-- refused, because a table with one real key and twelve Kanto keys is worse
-- than no table.

-- Every one of these is the same number on both generations, verified against
-- the Gen 2 file named beside it.  The four Gen 1 world constants NOT here
-- (poisonStepInterval, poisonDamage, blackoutMoneyDivisor, daycareExpPerStep)
-- are absent on purpose: Gold's step events do not read a shared constant
-- table and the Gen 1 numbers would be a guess.
local WORLD_CONSTANTS = {
  stepFrames = 16,   -- src/world/gen2/Npc.lua's STEP_FRAMES
  turnFrames = 4,    -- src/world/gen2/Player.lua's TURN_FRAMES
  neighborHops = 2,  -- the hop count World.computeNeighbors is called with
}

local function buildFieldDefaults()
  local FieldDefaults = {}

  local constants = { world = WORLD_CONSTANTS }
  -- bikeStepFrames is derived, not copied: Gold's bike length comes out of
  -- src/world/gen2/Bike.lua rather than a table.
  local okBike, Bike = pcall(rawRequire, "src.world.gen2.Bike")
  if okBike and Bike and Bike.stepFramesFor then
    WORLD_CONSTANTS.bikeStepFrames = Bike.stepFramesFor(WORLD_CONSTANTS.stepFrames)
  end
  -- encounterBuckets and hmBadges are Kanto: absent, so a mod's
  -- `for _, b in ipairs(CONSTANTS.encounterBuckets)` errors instead of
  -- rolling Kanto odds on Gold.
  FieldDefaults.CONSTANTS = constants

  function FieldDefaults.field(_data, key)
    warnOnce("fieldDefaults.field." .. tostring(key),
      "[%s] src.world.FieldDefaults.field(%s): Gold has no data.field",
      who("src.world.FieldDefaults"), tostring(key))
    return nil
  end

  -- Gen 1's is VARIADIC (src/world/FieldDefaults.lua:240); a fixed arity drops
  -- every deeper path.  Exactly one path resolves on Gold.
  function FieldDefaults.fieldValue(_data, key, ...)
    local first = ...
    if key == "playerSprites" then
      if first == "walk" then
        return rawRequire("src.world.gen2.World").PLAYER_SPRITE
      end
      -- Gen 1 returns the whole TABLE here (walk/surf/bike/fly), so answering
      -- the walk string would make a mod's `.surf` a string-index error.
      if first == nil then
        warnOnce("fieldDefaults.fieldValue.playerSprites",
          "[%s] FieldDefaults.fieldValue(data, 'playerSprites') returns the "
          .. "whole Gen 1 table; Gold can answer only the 'walk' leaf",
          who("src.world.FieldDefaults"))
        return nil
      end
    end
    local path = tostring(key)
    for i = 1, select("#", ...) do path = path .. "." .. tostring((select(i, ...))) end
    warnOnce("fieldDefaults.fieldValue." .. path,
      "[%s] src.world.FieldDefaults: Gold has no data.field %s",
      who("src.world.FieldDefaults"), path)
    return nil
  end

  -- data.constants is the cache's own; the three Gen 1 default tables are
  -- Kanto (encounterBuckets is the Gen 1 wild-slot spread, hmBadges names
  -- Kanto badges) and must never be the fallback.
  function FieldDefaults.constant(data, key)
    local value = data and data.constants and data.constants[key]
    if value ~= nil then return value end
    if key == "world" then return constants.world end
    warnOnce("fieldDefaults.constant." .. tostring(key),
      "[%s] FieldDefaults.constant(%s): Gold's cache does not carry it and "
      .. "the Gen 1 default is Kanto", who("src.world.FieldDefaults"),
      tostring(key))
    return nil
  end

  function FieldDefaults.world(data, key)
    local scoped = data and data.constants and data.constants.world
    local value = scoped and scoped[key]
    if value ~= nil then return value end
    value = WORLD_CONSTANTS[key]
    if value ~= nil then return value end
    warnOnce("fieldDefaults.world." .. tostring(key),
      "[%s] FieldDefaults.world(%s): Gold's step events do not read a shared "
      .. "constant table, so the Gen 1 number would be a guess",
      who("src.world.FieldDefaults"), tostring(key))
    return nil
  end

  -- Never let it write: seeding Kanto's field record into a Gold dataset
  -- would put PALLET_TOWN palettes and SILPH_SCOPE rules where mod patches
  -- and engine reads would find them.
  FieldDefaults.seed = unbacked("src.world.FieldDefaults", "seed",
    "seeding Kanto's FIELD into a Gold dataset would put PALLET_TOWN "
    .. "palettes and SILPH_SCOPE rules into data.field")

  return FieldDefaults
end

COVERAGE["src.world.FieldDefaults"] = {
  kind = "facade",
  backed = "CONSTANTS CONSTANTS.world constant world fieldValue",
  warned = "field seed",
  absent = "FIELD CONSTANTS.encounterBuckets CONSTANTS.hmBadges",
  notes = {
    ["CONSTANTS.world"] = "stepFrames, turnFrames, neighborHops and a derived "
      .. "bikeStepFrames only; the four poison / blackout / daycare keys are "
      .. "warned because Gold's StepEvents do not read a shared table",
    fieldValue = "serves data.field playerSprites.walk and nothing else",
    FIELD = "every leaf is Kanto (map ids, tileset names, SGB palettes); a "
      .. "nil-index error is the honest outcome",
  },
}

-- ------- src.pokemon.Boxes

local function buildBoxes()
  local Boxes2 = rawRequire("src.core.gen2.Boxes")
  -- the pass-through is purely additive (name/rename/withdraw/release/move/
  -- canUsePc...); only `deposit` collides, and the override below takes it back
  local adapter = setmetatable({}, { __index = Boxes2 })

  adapter.COUNT = Boxes2.NUM_BOXES
  adapter.CAPACITY = Boxes2.MONS_PER_BOX

  -- Gen 1's ensure MATERIALISES save.boxes because its callers then index it;
  -- src/core/gen2/Boxes.lua:48 creates one box on demand instead.  The clamp
  -- is src/pokemon/Boxes.lua:22 verbatim and is load bearing: Boxes2.box
  -- hands back a fresh DETACHED table for an index outside 1..NUM_BOXES, so
  -- an unclamped currentBox loses whatever is deposited into it.
  function adapter.ensure(save)
    if not save then return {} end
    save.boxes = save.boxes or {}
    for i = 1, Boxes2.NUM_BOXES do
      save.boxes[i] = save.boxes[i] or {}
    end
    save.currentBox =
      math.max(1, math.min(Boxes2.NUM_BOXES, save.currentBox or 1))
    return save.boxes
  end

  function adapter.active(save)
    local boxes = adapter.ensure(save)
    return boxes[save and save.currentBox or 1]
  end

  -- src/pokemon/Boxes.lua:33-43 with COUNT/CAPACITY swapped for Gold's.
  -- NOT the inherited Gen 2 deposit(save, partyIndex, boxIndex): a Gen 1 call
  -- would index save.party with a MON TABLE, get nil, and return false plus
  -- "There is no POKeMON there." -- which reads to the caller exactly like
  -- "every box is full" while the mon is silently dropped.
  function adapter.deposit(save, mon)
    local boxes = adapter.ensure(save)
    for off = 0, Boxes2.NUM_BOXES - 1 do
      local i = ((save.currentBox - 1 + off) % Boxes2.NUM_BOXES) + 1
      if #boxes[i] < Boxes2.MONS_PER_BOX then
        table.insert(boxes[i], mon)
        return i
      end
    end
    return nil
  end

  return adapter
end

COVERAGE["src.pokemon.Boxes"] = {
  kind = "facade", target = "src.core.gen2.Boxes",
  backed = "COUNT CAPACITY ensure active deposit defaultName name rename box "
    .. "count isFull setCurrent healthyCount canDeposit canWithdraw withdraw "
    .. "release move canUsePc NUM_BOXES MONS_PER_BOX PARTY_SIZE",
  warned = "",
  absent = "",
  notes = {
    COUNT = "14 on Gold, not 12; data.constants.boxCount reads nil, so a UI "
      .. "mod sizing a grid off constants and one sizing it off COUNT "
      .. "disagree",
    ensure = "the save.box migration arm is dropped; a Gold save is born with "
      .. "boxes and never had one",
  },
}

-- ------- src.world.WorldAPI
--
-- ALIAS, and it must stay one: src/mods/Loader.lua:977 builds every mod's
-- mod.world from src.world.gen2.WorldAPI, so a patch applied to the aliased
-- table is a patch applied to every live mod.world.  A facade copy would
-- produce two WorldAPIs: one the mod patches, one the engine handed it.

COVERAGE["src.world.WorldAPI"] = {
  kind = "alias", target = "src.world.gen2.WorldAPI",
  backed = "new __index overworld current mapOverview warpTo toggleObject replaceBlock "
    .. "spawnNpc removeNpc npc queueScript invalidateMap "
    .. "availableFieldActions useFieldAction",
  warned = "setFlag getFlag",
  absent = "",
  notes = {
    overworld = "Gold's World is not a stack state, so nothing can hide it; "
      .. "the returned object is a World, not an OverworldState",
    warpTo = "opts is accepted for parity and nothing in it is read: no "
      .. "arrive FX, no onDone, no keepMusic -- a mod chaining off onDone "
      .. "stops with no error",
    toggleObject = "visibility IS the MAPOBJECT_EVENT_FLAG, so an off-map "
      .. "toggle is refused where Gen 1 accepts it",
    setFlag = "Gen 2 event flags are NUMERIC indices into wEventFlags; a "
      .. "string is refused by name rather than written where nothing reads it",
    npc = "looks up def.index or def.name only, NOT npc.id; the handle's "
      .. "marchInPlace is refused outright and scriptMove refuses a second "
      .. "concurrent movement (World.moveState is one slot)",
    queueScript = "validates the WHOLE row list against a five-verb allow "
      .. "list and refuses by name before the first row runs",
  },
}

-- ------- src.world.OverworldController
--
-- FACADE (dispatch table), never an alias.  Gen 1's module IS the live state
-- singleton, so patching a method and calling one are the same table; Gold's
-- overworld is a World INSTANCE with a separate class table.  So this is a
-- table Gold DISPATCHES THROUGH at named seams (World:step calls worldTick,
-- World:interact asks interactWrapper, World:interactBody asks talkToWrapper)
-- plus, where a member is a plain query, a function that resolves the live
-- world and forwards.

local overworld

local function defaultUpdate() end

local function defaultInteract(world)
  return world:interactBody()
end

local function defaultTalkTo()
  return false
end

local OW = "src.world.OverworldController"

-- the compass keys Map:connection is indexed by, from the up/down/left/right
-- vocabulary everything else uses.  Getting this wrong lands the player on
-- the wrong edge with no error.
local COMPASS = { up = "north", down = "south", left = "west", right = "east" }

-- The one place a Gen 1 ENTITY becomes a Gen 2 objectId: 0 is the player, 1 is
-- wLastTalked and an extracted object is its index + 1
-- (src/world/gen2/World.lua:3559).  The player has no .def, so the old
-- `(def.index or 0) + 1` walked the last-talked NPC instead; nil means "not
-- addressable", never a fallback.
local function objectIdOf(world, entity)
  if entity == nil then return nil end
  if world and entity == world.player then return 0 end
  local index = entity.def and entity.def.index
  if type(index) == "number" then return index + 1 end
  return nil
end

local function buildOverworld()
  local Map2 = rawRequire("src.world.gen2.Map")
  local Permissions = rawRequire("src.world.gen2.Permissions")
  local World2 = rawRequire("src.world.gen2.World")
  local Movement = rawRequire("src.script.gen2.Movement")
  local HiddenItems = rawRequire("src.world.gen2.HiddenItems")
  local Bike = rawRequire("src.world.gen2.Bike")

  local api = nil
  -- one WorldAPI instance, so queueScript reuses the five-verb allow list
  -- rather than growing a second one here
  local function worldApi()
    if api then return api end
    local g = live()
    if not g then return nil end
    api = rawRequire("src.world.gen2.WorldAPI").new(g, OW)
    return api
  end

  local function w(member) return liveWorld(OW, member) end

  local ow = {
    update = defaultUpdate,
    interact = defaultInteract,
    talkTo = defaultTalkTo,
  }

  -- ---- entity lookups

  function ow.npcAtCell(cx, cy)
    local world = w("npcAtCell")
    return world and world:npcAt(cx, cy) or nil
  end

  function ow.pushableAtCell(cx, cy)
    local world = w("pushableAtCell")
    if not world then return nil end
    for _, npc in ipairs(world.npcs or {}) do
      if World2.isStrengthBoulder(npc) and npc:covers(cx, cy) then return npc end
    end
    return nil
  end

  -- Gen 2 objectIds are the extracted index PLUS ONE (0 is the player, 1 is
  -- wLastTalked), so passing the Gen 1 index straight through returns the
  -- object before the one asked for and nothing errors.  Extracted indices are
  -- 1-based on BOTH generations (src/world/gen2/World.lua:6924), so anything
  -- below 1 names no object at all: World:objectEntity would answer talkNpc.
  function ow.npcByIndex(index)
    local world = w("npcByIndex")
    if not world then return nil end
    if type(index) ~= "number" or index < 1 then
      warnOnce("ow.npcByIndex.range",
        "[%s] OverworldState.npcByIndex(%s): object indices start at 1 on "
        .. "both generations; the player is objectId 0 on Gold and is "
        .. "world.player, not an entry in this list", who(OW), tostring(index))
      return nil
    end
    return world:objectEntity(index + 1)
  end

  -- pool and data are the World's own; a mod keeping a private pool gets
  -- Gold's objects instead, which is worth one line.
  function ow.pooledNPC(pool, _data, mapId, obj)
    local world = w("pooledNPC")
    if not world then return nil end
    if pool ~= nil and pool ~= world.npcPool then
      warnOnce("ow.pooledNPC.pool",
        "[%s] OverworldState.pooledNPC ignores the pool argument: Gold pools "
        .. "on the World (World:pooledNpc)", who(OW))
    end
    return world:pooledNpc(mapId, obj)
  end

  ow.computeNeighbors = World2.computeNeighbors

  -- ---- map lifecycle

  function ow.setMap(mapId, x, y, facing, opts)
    local world = w("setMap")
    if not world then return nil end
    if opts and opts.keepPikachu ~= nil and opts.keepFollower == nil then
      opts = { via = opts.via, seamless = opts.seamless,
               keepMusic = opts.keepMusic, keepFollower = opts.keepPikachu }
    end
    return world:setMap(mapId, x, y, facing, opts)
  end

  function ow.rebuildNeighbors()
    local world = w("rebuildNeighbors")
    return world and world:rebuildNeighbors() or nil
  end

  function ow.reloadMap(mapId, reason)
    local world = w("reloadMap")
    if not world then return nil end
    if mapId ~= nil and world.map and world.map.id ~= mapId then return true end
    return world:reloadMapBadWarp(reason)
  end

  function ow.takeWarp(warpDef)
    local world = w("takeWarp")
    return world and world:takeWarp(warpDef) or nil
  end

  function ow.startWarpTo(mapId, x, y, facing, onDone, _opts)
    local world = w("startWarpTo")
    if not world then return nil end
    if onDone then
      warnOnce("ow.startWarpTo.onDone",
        "[%s] OverworldState.startWarpTo drops onDone on Gold "
        .. "(World:warpToMapId has no completion callback); a mod chaining "
        .. "off it stalls", who(OW))
    end
    return world:warpToMapId(mapId, x, y,
      facing or (world.player and world.player.facing))
  end

  function ow.canCollisionWarp()
    local world = w("canCollisionWarp")
    return world and not world:warpsSuppressed() or false
  end

  function ow.refreshStandingOnWarp()
    local world = w("refreshStandingOnWarp")
    return world and world:armWarpCheck() or nil
  end

  function ow.healPoint()
    local world = w("healPoint")
    return world and world:healPoint() or nil
  end

  function ow.warpToHealPoint(onDone)
    local world = w("warpToHealPoint")
    if not world then return nil end
    if onDone then
      warnOnce("ow.warpToHealPoint.onDone",
        "[%s] OverworldState.warpToHealPoint drops onDone and opts.arrive on "
        .. "Gold (World:warpToSpawn takes neither)", who(OW))
    end
    return world:warpToSpawn()
  end

  -- ---- movement

  function ow.dirHeld()
    local world = w("dirHeld")
    return world and world.heldDir or nil
  end

  function ow.handleInput()
    local world = w("handleInput")
    local g = live()
    return world and world:pollInput(g and g.input) or nil
  end

  function ow.stepForwardOrCrossEdge(dir)
    local world = w("stepForwardOrCrossEdge")
    return world and world:movePlayer(dir) or nil
  end

  function ow.checkLedgeHop(dir)
    local world = w("checkLedgeHop")
    return world and world:tryLedgeJump(dir) or false
  end

  function ow.checkEdgeExit(dir)
    local world = w("checkEdgeExit")
    return world and world:tryConnection(dir) or false
  end

  -- Gold has no crossConnection/checkEdgeExit split: tryConnection does both.
  ow.crossConnection = function(dir) return ow.checkEdgeExit(dir) end

  -- Gen 1's five-value shape, in order: the destination map DEF, its tileset
  -- def, x, y, conn (src/world/OverworldController.lua:1404).  Returning the
  -- map ID first put a STRING where callers index .width, and dropped the
  -- tileset the very next Map.defPassable call needs.
  function ow.connectionLanding(dir)
    local world = w("connectionLanding")
    if not (world and world.map and world.player) then return nil end
    local side = world.map:connection(COMPASS[dir] or dir)
    if not side then return nil end
    -- A side may hold several connections (editor-only extras); pick the one
    -- whose seam sits under the player's position along the edge.
    local conn = side
    if type(side) == "table" and not (side.map or side.mapId) then
      local isH = (dir == "north" or dir == "south")
      local cell = isH and world.player.cellX or world.player.cellY
      conn = nil
      for _, c in ipairs(side) do
        if c and (c.map or c.mapId) then
          local destDef = world.maps[c.map or c.mapId]
          local along = cell - (c.offset or 0) * 2
          local dim = destDef
            and (((isH and destDef.width) or destDef.height) * 2) or math.huge
          if along >= 0 and along < dim then conn = c; break end
        end
      end
      conn = conn or side[1]
    end
    if not conn then return nil end
    local destId = conn.map or conn.mapId
    local destDef = destId and world.maps and world.maps[destId]
    if not destDef then return nil end
    local tileset = world.tilesets and world.tilesets[destDef.tileset]
    if not tileset then return nil end
    local x, y = Map2.connectionLanding(destDef, conn, dir,
      world.player.cellX, world.player.cellY)
    return destDef, tileset, x, y, conn
  end

  function ow.checkBoulderPush(dir)
    local world = w("checkBoulderPush")
    if not (world and world.player) then return false end
    local d = Map2.DELTA[dir]
    if not d then return false end
    local p = world.player
    return world:tryPushBoulder(dir, p.cellX + d[1], p.cellY + d[2])
  end

  function ow.checkForcedMovement()
    local world = w("checkForcedMovement")
    return world and world:checkCarpetWhileStanding() or nil
  end

  -- Gold has ONE movement slot; a second concurrent call is refused with a
  -- reason rather than dropped (src/world/gen2/WorldAPI.lua:171's recipe).
  function ow.scriptMove(entity, dir, tiles, onDone)
    local world = w("scriptMove")
    if not world then return nil, "no overworld" end
    if world.moveState then return nil, "a movement is already running" end
    local step = Movement.stepByte(dir)
    if not step then return nil, "unknown direction: " .. tostring(dir) end
    local bytes = {}
    for _ = 1, math.max(0, tiles or 1) do bytes[#bytes + 1] = step end
    bytes[#bytes + 1] = Movement.STEP_END
    local objectId = objectIdOf(world, entity)
    if not objectId then
      return nil, "no Gen 2 objectId for that entity: only the player and a "
        .. "mapped object (def.index) can be moved"
    end
    world:beginMovement(objectId, bytes, onDone)
    return true
  end

  function ow.updateScriptMoves()
    local world = w("updateScriptMoves")
    return world and world:updateMovement() or nil
  end

  -- ---- world state

  function ow.timeOfDay()
    local world = w("timeOfDay")
    if not world then return nil end
    -- Gen 1 returns the CACHED tod, Gold recomputes from the clock every
    -- call: a mod that set a custom tod reads the clock's answer back unless
    -- its world.tod hook is still installed.
    return world:timeOfDay(world:hour())
  end

  -- Gold's darkness is a map PROPERTY the palette set reads; the only thing a
  -- mod can move is flashUsed, and only on a DARKNESS palset map.
  function ow.setDark(on)
    local world = w("setDark")
    if not world then return nil end
    warnOnce("ow.setDark",
      "[%s] OverworldState.setDark only has an effect on maps whose palset is "
      .. "DARKNESS; elsewhere it is a no-op (Gold's dimming is a palette set, "
      .. "not a state boolean)", who(OW))
    world.flashUsed = not on
    return world:applyPalettes()
  end

  function ow.bikeAllowed(mapId)
    local world = w("bikeAllowed")
    if not world then return false end
    local def = world.maps and world.maps[mapId]
    if not def then return false end
    return Bike.environmentAllows(def.environment)
  end

  function ow.replaceBlock(bx, by, block)
    local world = w("replaceBlock")
    if not world then return nil end
    -- NEVER World:replaceBlock, which exists on Gold under the same name and
    -- takes a FLAT INDEX plus a block id: forwarding there edits an unrelated
    -- block and drops the third argument, without erroring.
    local ok = world:changeBlock(bx, by, block)
    Runtime.emit("world.block_replaced",
      { mapId = world.map and world.map.id, bx = bx, by = by, block = block })
    return ok
  end

  ow.addRuntimeObject = function(mapId, objDef, owner)
    local world = w("addRuntimeObject")
    return world and world:addRuntimeObject(mapId, objDef, owner) or nil
  end

  ow.removeRuntimeObject = function(npcId, owner)
    local world = w("removeRuntimeObject")
    return world and world:removeRuntimeObject(npcId, owner) or nil
  end

  -- ---- interaction and field moves

  function ow.tryHiddenObject(fx, fy)
    local world = w("tryHiddenObject")
    if not (world and world.map) then return nil end
    return HiddenItems.at(world.map.def, fx, fy, world.events)
  end

  function ow.hasHiddenItemLeft()
    local world = w("hasHiddenItemLeft")
    if not (world and world.map) then return false end
    return #HiddenItems.unfound(world.map.def, world.events) > 0
  end

  function ow.facingIsShoreOrWater()
    local world = w("facingIsShoreOrWater")
    if not (world and world.map and world.player) then return false end
    local p = world.player
    local d = Map2.DELTA[p.facing]
    if not d then return false end
    return Permissions.surfable(
      world.map:cellCollision(p.cellX + d[1], p.cellY + d[2])) ~= nil
  end

  function ow.facingIsLandDismount()
    local world = w("facingIsLandDismount")
    if not (world and world.map and world.player) then return false end
    local p = world.player
    if not p.surfing then return false end
    local d = Map2.DELTA[p.facing]
    if not d then return false end
    return Permissions.isLand(
      world.map:cellCollision(p.cellX + d[1], p.cellY + d[2]))
  end

  function ow.trySurf(_fx, _fy, onClose)
    local world = w("trySurf")
    if not world then return nil end
    if onClose then
      warnOnce("ow.trySurf.onClose",
        "[%s] OverworldState.trySurf drops onClose on Gold: World:trySurfOW "
        .. "takes the faced cell from the player and has no callback",
        who(OW))
    end
    return world:trySurfOW()
  end

  function ow.tryCut()
    local world = w("tryCut")
    return world and world:tryCutOW() or nil
  end

  function ow.partyKnows(moveId)
    local world = w("partyKnows")
    -- Gold returns the MON; forwarding it raw hands back a table where the mod
    -- expects true/false, which works in a conditional and breaks on `== true`
    return world ~= nil and world:partyMoveUser(moveId) ~= nil
  end

  function ow.goFishing(rod)
    local world = w("goFishing")
    if not world then return nil end
    if type(rod) == "string" then
      warnOnce("ow.goFishing.rod",
        "[%s] OverworldState.goFishing takes a Gen 2 ITEM ID on Gold, not a "
        .. "Gen 1 rod name like %s", who(OW), rod)
      return nil
    end
    return world:useRod(rod)
  end

  -- Gen 1 takes a MAP ID, Gold takes a SPAWN ID out of landmarks.spawns.
  -- Forwarding the map id returns false and the player simply does not fly.
  function ow.flyTo(mapId)
    local world = w("flyTo")
    if not world then return nil end
    for key, spawn in pairs(world.landmarks and world.landmarks.spawns or {}) do
      if spawn.map == mapId then return world:flyTo(key) end
    end
    warnOnce("ow.flyTo." .. tostring(mapId),
      "[%s] OverworldState.flyTo(%s): no landmark spawn lands on that map, so "
      .. "Gold has no fly destination for it", who(OW), tostring(mapId))
    return nil
  end

  function ow.openPC(onDone)
    local world = w("openPC")
    return world and world:openPc({ onDone = onDone }) or nil
  end

  function ow.nurseHeal(onDone)
    local world = w("nurseHeal")
    if not world then return nil end
    return world:startHealMachineAnim(nil, function()
      world:healParty()
      if onDone then onDone() end
    end)
  end

  function ow.trainerDefeated(npc)
    local world = w("trainerDefeated")
    if not world then return false end
    local def = npc and npc.def
    return world:trainerBeaten(def and def.trainer or def) and true or false
  end

  function ow.engageTrainer(npc, onDone, endBattleText, skipBattleText)
    local world = w("engageTrainer")
    if not world then return nil end
    if endBattleText ~= nil or skipBattleText ~= nil then
      warnOnce("ow.engageTrainer.text",
        "[%s] OverworldState.engageTrainer drops endBattleText / "
        .. "skipBattleText on Gold: the trainer flow is an extracted SCRIPT "
        .. "and there is nowhere to put them", who(OW))
    end
    local script = npc and npc.def and npc.def.scriptKey
    local ok = world:startTrainerScript(npc, script, false)
    if onDone then onDone(ok) end
    return ok
  end

  function ow.checkTrainerSight()
    local world = w("checkTrainerSight")
    return world and world:checkTrainerBattle() or false
  end

  function ow.startTrainerApproach(npc, _dist)
    local world = w("startTrainerApproach")
    if not world then return nil end
    if npc then
      warnOnce("ow.startTrainerApproach.npc",
        "[%s] OverworldState.startTrainerApproach drops its npc and distance "
        .. "on Gold: World:trainerApproach takes them from the World's own "
        .. "sight scan, so a specific object cannot be approached", who(OW))
    end
    return world:trainerApproach()
  end

  -- Forwarding a TEXT_* constant to World:showText prints the constant NAME
  -- on screen, which looks like a mod bug forever.
  function ow.showMapText(key, _npc, onDone)
    local world = w("showMapText")
    if not world then return nil end
    local body = world.text and world.text[key]
    if body == nil then
      warnOnce("ow.showMapText." .. tostring(key),
        "[%s] OverworldState.showMapText(%s): Gold's text ids are ROM pointer "
        .. "strings, so a TEXT_* constant resolves to nothing; printing "
        .. "nothing rather than the key", who(OW), tostring(key))
      return nil
    end
    return world:showText(body, onDone)
  end

  function ow.applyFieldPoison()
    local world = w("applyFieldPoison")
    if not world then return nil end
    local StepEvents = rawRequire("src.world.gen2.StepEvents")
    local g = live()
    return StepEvents.poisonStep(g and g.save and g.save.party)
  end

  function ow.queueScript(rows, extra)
    local a = worldApi()
    if not a then return nil, "no overworld" end
    return a:queueScript(rows, extra)
  end

  -- Gen 1's module IS the state, so a mod calls these with a COLON and the
  -- module arrives as self.  Strip that leading argument -- and a World, which
  -- is what a mod holding game.overworld would pass -- so one source calls
  -- either way.  The three seams below are called BY Gold with the world as
  -- their first argument and must keep it.
  local SEAMS = { update = true, interact = true, talkTo = true,
                  computeNeighbors = true }
  for key, fn in pairs(ow) do
    if type(fn) == "function" and not SEAMS[key] then
      ow[key] = function(first, ...)
        if first == overworld
            or (type(first) == "table" and first.stepBody ~= nil) then
          return fn(...)
        end
        return fn(first, ...)
      end
    end
  end

  -- Gen 1's module IS the live state (src/core/Game.lua:87 assigns the module
  -- itself), so `OverworldController.player` off the required module is the
  -- ordinary idiom.  These seven names are the World's own fields under the
  -- same spelling and shape, and they read AND write through to it.
  local LIVE_FIELD = { map = true, player = true, npcs = true, entities = true,
                       ghosts = true, npcPool = true, camera = true }

  setmetatable(ow, {
    __index = function(_, key)
      if LIVE_FIELD[key] then
        local world = w(key)
        return world and world[key] or nil
      end
      -- Gen 1's entries are { map = mapDef, ox, oy } and Gold's are
      -- { id, ox, oy, image }: nb.map is nil there, so a scan silently matches
      -- nothing (src/world/OverworldController.lua:529 vs World.lua:8275).
      if key == "neighbors" then
        warnOnce("ow.neighbors",
          "[%s] OverworldState.neighbors has no Gen 2 backing with the Gen 1 "
          .. "shape: Gold's entries carry `id`, not `map`.  world.neighbors "
          .. "plus world.maps[nb.id] is the honest route", who(OW))
        return nil
      end
      if key == "isOverworld" then
        warnOnce("ow.isOverworld",
          "[%s] OverworldController.isOverworld exists on this facade so a "
          .. "module compare works, but Gold's world is NOT on the state "
          .. "stack: a scan of game.stack.states finds nothing.  Use "
          .. "mod.world:overworld()", who(OW))
        return true
      end
      return nil
    end,
    -- a write to one of the live names has to move the world, the way a write
    -- to the Gen 1 module did; everything else is a seam the mod installs
    __newindex = function(t, key, value)
      if LIVE_FIELD[key] then
        -- never rawset one of these: the key would shadow the world for the
        -- rest of the run and every later read would answer the stale value
        local world = w(key)
        if world then world[key] = value end
        return
      end
      rawset(t, key, value)
    end,
  })

  overworld = ow
  return ow
end

-- called once per logic frame from World:step's tail
function Gen2Compat.worldTick(world, dt)
  if not overworld then return end
  if overworld.update == defaultUpdate then return end
  overworld.update(world, dt)
end

-- nil while nothing replaced `interact`: one comparison on a mod-free press
function Gen2Compat.interactWrapper()
  if not overworld or overworld.interact == defaultInteract then return nil end
  return overworld.interact
end

-- the same shape for the talk dispatch World:interactBody seams in
function Gen2Compat.talkToWrapper()
  if not overworld or overworld.talkTo == defaultTalkTo then return nil end
  return overworld.talkTo
end

COVERAGE[OW] = {
  kind = "facade", target = "src.world.gen2.World",
  backed = "update interact talkTo npcAtCell pushableAtCell npcByIndex "
    .. "pooledNPC computeNeighbors setMap rebuildNeighbors reloadMap takeWarp "
    .. "startWarpTo canCollisionWarp refreshStandingOnWarp healPoint "
    .. "warpToHealPoint dirHeld handleInput stepForwardOrCrossEdge "
    .. "checkLedgeHop checkEdgeExit crossConnection connectionLanding "
    .. "checkBoulderPush checkForcedMovement scriptMove updateScriptMoves "
    .. "timeOfDay bikeAllowed replaceBlock addRuntimeObject "
    .. "removeRuntimeObject tryHiddenObject hasHiddenItemLeft "
    .. "facingIsShoreOrWater facingIsLandDismount tryCut partyKnows "
    .. "goFishing flyTo openPC nurseHeal trainerDefeated engageTrainer "
    .. "checkTrainerSight startTrainerApproach showMapText applyFieldPoison "
    .. "queueScript map player npcs entities ghosts npcPool camera",
  warned = "isOverworld setDark trySurf neighbors npcByIndex",
  absent = "isOpaque objectVisible enter paletteNameFor sgbPalettes "
    .. "sgbWorldZones isDungeonTransitionMap pushBattle drainPendingScripts "
    .. "startParallel killParallel updateParallel startDustAnim "
    .. "startCutTreeAnim useSurfFieldMove useCutFieldMove beginTeleportOut "
    .. "syncSurfingPikachu tryBookshelf benchGuyText tryCardKeyDoor "
    .. "trashCanSwitch stampClosedDoors billsHousePC billsHousePokemonList "
    .. "billsHouseBillExits tilesetHasWater surfBlockedHere "
    .. "checkSeafoamCurrent seafoamHolesFor boulderIntoHole openOaksPC "
    .. "dexRating cableClubReceptionist finishNurseHeal stepHealAnim "
    .. "checkVictoryRewards offerGymTm runVictoryHook onStepComplete "
    .. "rollEncounter checkSpinner runSpinnerMoves rewrittenLastMap "
    .. "syncLastMapRewrite rememberOutdoor checkBadgeGate inSafariStepZone "
    .. "safariStep safariGameOver afterBattle draw drawWorld drawUI billboard "
    .. "captureSave marchInPlace runner scriptMoves marchers parallelRunners "
    .. "parallelQueue pendingScripts npcMoveLocks engaging lastOutdoor dark "
    .. "tod",
  notes = {
    update = "called as update(world, dt) with dt fixed at 1/60, AFTER "
      .. "World:stepBody -- a Gen 1 wrapper that expects to pre-empt the body "
      .. "is too late; `self` is a World, not an OverworldState",
    interact = "the default is world:interactBody(), so a wrapper receives "
      .. "the World as self and can call through",
    talkTo = "seamed into World:interactBody once the object is resolved; a "
      .. "true return suppresses the built-in path",
    npcAtCell = "Gold does NOT match targetX/targetY, so an NPC walking INTO "
      .. "the cell is missed; it DOES match all four cells of a BIG_OBJECT",
    player = "the LIVE World's field, read and written through: it is a "
      .. "src/world/gen2/Player.lua, so cellX / cellY / facing / surfing "
      .. "carry and the Gen 1 Player's own methods do not",
    map = "the live World's map, a src/world/gen2/Map.lua instance -- which "
      .. "IS what require('src.world.Map') hands the mod back here",
    npcs = "the live lists; a ghost NPC on a neighbouring map is in `ghosts`, "
      .. "not here, on both generations",
    neighbors = "WARNED: Gold's entries are { id, ox, oy, image } where Gen "
      .. "1's are { map = mapDef, ox, oy }, so the field answers nil rather "
      .. "than a list whose nb.map is nil on every row",
    npcByIndex = "1-based extracted indices only; 0 and below answer nil and "
      .. "warn, because Gold's objectId 0 is the PLAYER (world.player) and "
      .. "objectId 1 is wLastTalked, not object zero",
    scriptMove = "the player maps to objectId 0 and a mapped object to "
      .. "def.index + 1; an entity with neither (a mod's own guest) is "
      .. "REFUSED with a reason rather than moving the last-talked NPC",
    connectionLanding = "Gen 1's five values (destDef, tilesetDef, x, y, "
      .. "conn); `conn` is Gold's connection record, keyed map/mapId + offset",
    timeOfDay = "recomputed from the clock every call and never cached, so a "
      .. "custom tod does not read back; world.daytime is the field",
    setDark = "only a DARKNESS palset map is affected",
    rollEncounter = "absent: Gold's takes (kind, terrain, tables, vanilla) "
      .. "and the Gen 1 kind vocabulary cannot be derived from an encDef",
    runner = "absent from the facade; world.runner is the shim on the World "
      .. "itself and answers isRunning()",
    tod = "world.daytime is the Gen 2 spelling",
    onStepComplete = "no seam; the world.stepped event is the supported route",
    afterBattle = "no seam; the battle.ended event is the supported route",
    draw = "no seam; the render_pipelines registry is the supported route on "
      .. "both generations",
  },
}

-- ------- src.world.PikachuFollower
--
-- ALIAS, required: followers-ex reaches the module's file-local shouldSpawn
-- UPVALUE with debug.setupvalue and monkey-patches update / onMapEntered /
-- starterInParty on the module table.  A facade copy would have different
-- upvalues and the patched function would be one nothing calls.

COVERAGE["src.world.PikachuFollower"] = {
  kind = "alias", target = "src.world.gen2.Follower",
  backed = "setShouldSpawn current onMapEntered update rebase "
    .. "talk starterInParty setVisible at SPRITE",
  warned = "",
  absent = "shouldSpawn onStep bumpHappiness modifyHappiness picLift hopToCounter "
    .. "updateHop onBillsHouseEnter onBillWalksAroundPlayer "
    .. "onBillEnteredMachine onBillExitedMachine",
  notes = {
    shouldSpawn = "ABSENT as a MODULE member on both generations: it is a "
      .. "file-local, reachable through setShouldSpawn or the upvalue of that "
      .. "name.  The callback is passed (game, world) where Gen 1 passes "
      .. "(game, ow); a predicate reading ow.player / ow.map is unchanged",
    onMapEntered = "accepts opts.keepPikachu as well as opts.keepFollower",
    talk = "the stub returns false and does NOT call done(); a mod that calls "
      .. "it and waits for the callback hangs -- check the return",
    ["ow.pikachuTrail"] = "aliased by reference to world.followerTrail, so a "
      .. "reset through either name moves the live trail",
    bumpHappiness = "Gold has per-mon friendship, not one companion byte; "
      .. "mapping it would silently move a real game stat",
  },
}

-- ------- src.ui.PartyMenu
--
-- FACADE over the aliased Gen 2 class: __index falls through so a wrap of
-- .update / .draw resolves, __newindex writes THROUGH so that wrap lands on
-- Gold's live class, and only the four members whose contract differs are
-- overridden here.  The icon statics and sgbPalettes must stay ABSENT.

local UI_ABSENT_ICON = "Gold has per-species two-frame icon sheets, not Gen "
  .. "1's nine shared icon classes, so there is no class name to key on"

-- A mod's write WINS on read (rawequal(read, patch) holds, so the patch is
-- visible) and is written THROUGH so Gold's own class runs it too.  The
-- overrides below must therefore call the member they CAPTURED at build time,
-- never target[key], or a wrapper that chains to the override re-enters it.
local PATCHED_NIL = {}

local function passThroughProxy(target, overrides, absent, moduleName)
  local patched = {}
  return setmetatable({}, {
    __index = function(_, key)
      local mine = patched[key]
      if mine == PATCHED_NIL then return nil end
      if mine ~= nil then return mine end
      local made = overrides[key]
      if made ~= nil then return made end
      local why = absent[key]
      if why then
        warnOnce(moduleName .. "." .. key,
          "[%s] %s.%s has no Gen 2 backing: %s",
          who(moduleName), moduleName, key, why)
        return nil
      end
      return target[key]
    end,
    -- a monkey-patch has to land on the class Gold actually pushes
    __newindex = function(_, key, value)
      patched[key] = (value == nil) and PATCHED_NIL or value
      target[key] = value
    end,
  })
end

local function buildPartyMenu()
  local Party2 = rawRequire("src.ui.gen2.PartyMenu")
  local overrides, absent = {}, {}
  -- built first so .new can stamp whatever the MOD last wrote to these names
  local proxy = passThroughProxy(Party2, overrides, absent, "src.ui.PartyMenu")
  -- captured before any mod write: a wrapper chaining to overrides.new must
  -- reach Gold's constructor, not itself
  local newOrig = Party2.new

  absent.drawIcon = "PartyMenu.drawIcon is a STATIC under Gen 1 and a METHOD "
    .. "on Gold, so the same call would bind self = game and die inside "
    .. "iconFor; " .. UI_ABSENT_ICON
  absent.frameFor = UI_ABSENT_ICON
  absent.mirrorsIcon = UI_ABSENT_ICON .. " and Gold draws the whole 16x16 quad"
  absent.iconFrames = UI_ABSENT_ICON .. "; an empty table would accept the "
    .. "mod's writes and never draw from them"
  absent.sgbPalettes = "Gold is a GBC title: colour is GbcPalette plus the "
    .. "map palsets, and there are no SGB zone packets under src/ui/gen2/"
  absent.animateTo = "Gold's party screen has no HP-fill animation; a stub "
    .. "calling onDone immediately would print the mod's message with no fill "
    .. "and leave A live over a menu the caller thinks is busy"

  -- Gen 1 pops ITSELF on B (src/ui/PartyMenu.lua:540) and Gold never pops.
  function overrides.new(game, opts)
    opts = opts or {}
    -- the LIVE Game2, not the src.core.Game proxy the mod is holding: the Gen
    -- 2 screen reads game.partyMenuCursor, game.data and game.stack off it
    local g = live() or game
    local inst
    local function popSelf()
      if g and g.stack and g.stack:top() == inst then g.stack:pop() end
    end
    if opts.keepOpen then
      warnOnce("party.keepOpen",
        "[%s] PartyMenu opts.keepOpen has no Gen 2 backing and is treated as "
        .. "false: Gold's party list has no stay-open contract",
        who("src.ui.PartyMenu"))
    end
    if opts.tmhm then
      warnOnce("party.tmhm",
        "[%s] PartyMenu opts.tmhm has no Gen 2 backing: Gold has no per-row "
        .. "ABLE / NOT ABLE column, so prompt = 'teach' alone would make the "
        .. "mod read every mon as ineligible", who("src.ui.PartyMenu"))
    end
    local prompt, submenu, battleSubmenu
    if opts.forceSwitch then
      prompt = "which"
    elseif opts.battle and opts.onSwitch then
      prompt, battleSubmenu = "choose", true
    elseif opts.pickOnly then
      prompt = "useItem"
    elseif opts.onSwitch then
      -- src/ui/PartyMenu.lua:569: onSwitch OUTSIDE battle fires on A itself,
      -- so the field submenu must not swallow the press
      prompt = "choose"
    else
      prompt, submenu = "choose", true
    end
    -- Gen 1's saved cursor lives under a different name; copy it over or the
    -- mod's stored slot is ignored.
    if g and g.partyMenuSavedIndex and not g.partyMenuCursor then
      g.partyMenuCursor = g.partyMenuSavedIndex
    end
    inst = newOrig(g, {
      party = opts.party,
      prompt = prompt, submenu = submenu, battleSubmenu = battleSubmenu,
      -- (mon, menu) versus (index, mon): both the order and the arity differ
      onChoose = function(_i, mon)
        popSelf()
        if opts.onSwitch then opts.onSwitch(mon, inst) end
      end,
      onCancel = function()
        popSelf()
        if opts.onCancel then opts.onCancel() end
      end,
    })
    -- Stamped per INSTANCE, never onto the Gen 2 class: the object's
    -- metatable is Gold's PartyMenu, so a facade-only member would be
    -- unreachable as inst:close(), and writing it onto the class would change
    -- what Gold's own screen answers.
    inst.close = proxy.close
    inst.bottomMessage = proxy.bottomMessage
    return inst
  end

  -- src/ui/PartyMenu.lua:306, which Gold has no counterpart for and needs
  -- nothing from Gen 2 to write.
  function overrides.close(self)
    if self.game and self.game.stack and self.game.stack:top() == self then
      self.game.stack:pop()
    end
  end

  -- src/ui/gen2/PartyMenu.lua:734 verbatim
  function overrides.bottomMessage(self)
    if self.switchFrom then return Party2.PROMPTS.moveTo end
    return self.prompt
  end

  -- Gold's list starts at tile row 1, so Gen 1's (i-1)*16 sits 8px high on
  -- every row.
  function overrides.entryY(i)
    return 8 + (i - 1) * 16
  end

  return proxy
end

COVERAGE["src.ui.PartyMenu"] = {
  kind = "facade", target = "src.ui.gen2.PartyMenu",
  backed = "new close bottomMessage entryY update draw isOpaque __index "
    .. "PROMPTS index party submenu switchFrom clock onCancel",
  warned = "keepOpen tmhm",
  absent = "drawIcon frameFor mirrorsIcon iconFrames sgbPalettes animateTo "
    .. "heal softboiledFrom battle subItems subIndex swapFrom blink onSwitch "
    .. "pickOnly forceSwitch",
  notes = {
    new = "onSwitch(mon, menu) is wrapped onto onChoose(index, mon); opts."
      .. "battle carries only its BOOLEAN sense and self.battle is left nil "
      .. "so a `menu.battle:say(...)` fails loudly",
    index = "1..#party+1 on Gold because CANCEL is one past the last mon; "
      .. "party[self.index] is nil there",
    party = "always materialised, so `if not menu.party then` takes the wrong "
      .. "branch",
    swapFrom = "renamed switchFrom; a WRITE of menu.swapFrom is inert",
    subItems = "self.submenu is a TABLE on Gold: subItems is submenu.items "
      .. "and subIndex is submenu.index",
    blink = "renamed clock, and Gold never wraps it (Gen 1 wraps at 320)",
    onSwitch = "replacing menu.onSwitch on a LIVE instance writes a field "
      .. "Gen 2 never reads; pass it to .new instead",
    bottomMessage = "returns Gold's strings with <PK>/<MN> charmap glyphs, so "
      .. "a compare against \"Use on which one?\" will not match",
    ["hook ui.party.submenu"] = "same name and arity; rows carry `id` on Gold "
      .. "where Gen 1 carries `action`, and ctx.battle is a BOOLEAN, not a "
      .. "BattleState",
  },
}

-- ------- src.ui.BoxMenu
--
-- ALIAS, but to src.ui.gen2.PcMenu, not src.ui.gen2.BoxMenu.  Gen 1's
-- src.ui.BoxMenu is Bill's PC TOP MENU; Gold's BoxMenu is the withdraw /
-- deposit LIST that Gen 1 builds inline with ListMenu.  The alias has to be
-- bare, because PcMenu is the table src/ui/Screens.lua caches for
-- "Gen2PcMenu" and a monkey-patch of .new must land there.

COVERAGE["src.ui.BoxMenu"] = {
  kind = "alias", target = "src.ui.gen2.PcMenu",
  backed = "new",
  warned = "",
  absent = "",
  notes = {
    new = "PcMenu.new(game) with opts omitted yields the five-row folded PC; "
      .. "the RETURNED object is a PcMenu, not a src.ui.Menu",
    items = "renamed .entries; rows are { id, label } dispatched by id, and a "
      .. "row carrying label + onSelect is now answered by PcMenu:choose's "
      .. "onSelect arm so an injected row does something",
    th = "PcMenu owns the whole screen (0,0,19,17); .th / .tx / .tw / "
      .. ".scroll / :clampScroll do not exist and a write to them is inert",
    ["hook ui.pc.items"] = "same NAME, DIFFERENT MENU: Gen 1 raises it over "
      .. "the WHICH-PC list, Gold over Bill's PC's own rows",
  },
}

-- ------- src.ui.StartMenu

local function buildStartMenu()
  local Start2 = rawRequire("src.ui.gen2.StartMenu")
  local overrides, absent = {}, {}
  -- captured before any mod write, so a wrapper of .new cannot re-enter here
  local newOrig = Start2.new

  -- Both callbacks MUST be synthesised: Gen 2's :close() only calls
  -- self.onClose and :choose() only calls self.onChoose, so without them B
  -- does nothing and A on POKeMON does nothing -- a menu that opens and
  -- cannot be exited.  The wiring is src/core/Game2.lua:390-396.
  function overrides.new(game)
    local g = live() or game
    local save = g and g.save
    if save and save.startMenuIndex then
      Start2.lastIndex = save.startMenuIndex
    end
    return newOrig(g, {
      save = save,
      onClose = function()
        local owner = live()
        if owner and owner.stack then owner.stack:pop() end
      end,
      onChoose = function(id)
        local owner = live()
        if owner and owner.openStartMenuItem then
          owner:openStartMenuItem(id)
        end
      end,
    })
  end

  return passThroughProxy(Start2, overrides, absent, "src.ui.StartMenu")
end

COVERAGE["src.ui.StartMenu"] = {
  kind = "facade", target = "src.ui.gen2.StartMenu",
  backed = "new items ITEMS lastIndex",
  warned = "",
  absent = "",
  notes = {
    new = "synthesises onClose (stack:pop) and onChoose "
      .. "(Game2:openStartMenuItem); without them the menu cannot be left",
    index = "the cursor is menu.list.index on Gold (a Chrome.List)",
    ["save.startMenuIndex"] = "copied INTO StartMenu.lastIndex on construct "
      .. "and never copied back: Gold's cursor is a class field, not save data",
    tx = "the box is fixed at Chrome.box(10, 0, 10, h); tx/ty/tw/th/anchor/"
      .. "maxVisible/startCloses/noSound do not exist and writes are inert",
    ["hook ui.start_menu.items"] = "full parity; a row carrying { label, "
      .. "onSelect } and no value is answered on both generations",
  },
}

-- ------- src.ui.OptionsMenu

local function buildOptionsMenu()
  local Options2 = rawRequire("src.ui.gen2.OptionsMenu")
  local overrides, absent = {}, {}
  -- captured before any mod write, so a wrapper of .new cannot re-enter here
  local newOrig = Options2.new

  absent.sgbPalettes = "Gold is a GBC title; a mod wrapping this to append a "
    .. "zone would get nil from the original and register a zone nothing reads"

  -- Gen 2's :leave_ is the only exit and it calls self.onDone or nothing, so
  -- without a synthesised one the screen cannot be left.  Body is
  -- src/core/Game2.lua:330-341 plus the pop Gen 1 does for itself.
  function overrides.new(game, opts)
    opts = opts or {}
    local g = live() or game
    local inst
    inst = newOrig(g, {
      options = g and g.options,
      onDone = function(options)
        local owner = live()
        if owner then
          owner.options = options
          if owner.save then owner.save.options = options end
          if owner.applyOptions then owner:applyOptions() end
          if owner.persistOptions then owner:persistOptions() end
          if owner.stack and owner.stack:top() == inst then owner.stack:pop() end
        end
        if opts.onCancel then opts.onCancel() end
      end,
    })
    return inst
  end

  return passThroughProxy(Options2, overrides, absent, "src.ui.OptionsMenu")
end

COVERAGE["src.ui.OptionsMenu"] = {
  kind = "facade", target = "src.ui.gen2.OptionsMenu",
  backed = "new update draw isOpaque rows index scroll options",
  warned = "",
  absent = "sgbPalettes",
  notes = {
    new = "synthesises onDone out of opts.onCancel plus the pop Gen 1 does "
      .. "for itself",
    index = "1..#rows on Gold: there is no CANCEL row, so `index == #rows+1` "
      .. "never fires.  A row carrying cancel = true is the Gen 2 equivalent",
    rows = "row.step's RETURN VALUE is ignored on Gold; the write happens "
      .. "once, on close, through onDone",
    options = "Game2 sets save.options = self.options, so a Gen 1 row's "
      .. "g.save.options write edits the same table the screen edits",
    ["hook ui.options.rows"] = "full parity: Gen 2 answers row.step, "
      .. "row.activate and row.value first",
    ["src.ui.OptionRows"] = "NOT gated by the shim and loads fine under Gold, "
      .. "so a mod calling OptionRows.draw paints Red's chrome over Gold's",
  },
}

-- ------- src.battle.BattleState
--
-- FACADE, and mostly an absent one.  Gen 1's BattleState is engine and screen
-- on one table; Gold splits them (src/battle/gen2/Battle.lua is the model,
-- src/ui/gen2/BattleState.lua the screen).  Nine of ~163 members share a name
-- and two of those differ in signature.  Everything else is named once,
-- grouped, and left absent rather than answered with a near miss.

local function buildBattleState()
  local Battle2 = rawRequire("src.ui.gen2.BattleState")
  local overrides, absent = {}, {}

  local MOVED = "turn resolution, damage, catching and the AI live on "
    .. "src/battle/gen2/Battle.lua, over a mon rather than a Gen 1 battler "
    .. "wrapper, so no argument shape survives"

  for _, name in ipairs({
    "makeSafari", "makeGhost", "makeUnveiledGhost", "queueScopeReveal",
    "sayChoice", "act", "ui", "animNext", "actNext", "sayNext", "sayNextAuto",
    "uiNext", "drainNext", "waitNext", "buildScreen", "makeBattler",
    "resolveTurn", "executeAction", "performMove", "enemyAction",
    "vanillaEnemyAction", "resolveSwitch", "endOfTurn", "residualFor",
    "queueResidual", "tickTokens", "applyDamage", "onFaint", "awardExp",
    "learnMove", "clearVolatiles", "computeDamage", "accuracyRoll",
    "catchAttempt", "runRoll", "runRollVanilla", "moveDef", "effectRecord",
    "ballDef", "statusLabel", "aiUsesFor", "battleKind", "sideOf",
    "syncSides", "playerHasPP", "lockedAction", "computeMusicKind",
    "throwBall", "ballChain", "tossAnimFor", "ballFlicker", "ballMissMessage",
    "storeCaughtMon", "safariAction", "safariEnemyTurn", "drawBallRow",
    "drawClassic", "isWideBattleLayout", "wideLayout", "bgMode", "uiSize",
    "sgbPalettes", "trainerPalette", "trainerPicPath", "trainerTrueColor",
    "trainerSprite", "invalidate",
    "imageBattleScale", "resolveBattleScale", "backPlacement",
    "frontPlacement", "StatBox", "enter", "exit",
  }) do
    absent[name] = MOVED
  end
  absent.newWild = "Gold has no factory that returns an UNPUSHED battle: "
    .. "World:startBattle constructs a src/battle/gen2/Battle.lua and pushes "
    .. "the screen in one call.  A mod rewriting the species belongs on the "
    .. "encounter.species hook, which Gold raises with the same name and shape"
  absent.newTrainer = absent.newWild
  absent.makeSafari = "Gold has no Safari Zone; the Bug-Catching Contest is a "
    .. "different rule set (PARK BALL, a held-mon rule, no BAIT or ROCK), and "
    .. "answering this would make a mod take its native safari path"
  absent.enter = "Gold's battle sets up in .new and tears down in "
    .. "finishBattle; StateStack calls enter/exit when callable, so INSTALLING "
    .. "one where Gold has none makes the original a nil call"
  absent.exit = absent.enter
  absent.sgbPalettes = "Gold is a GBC title; there are no SGB zone packets"

  -- say/sayAuto: exact, because the generic text arm honours event.text on
  -- any event.  Gold's messages always auto-advance, so sayAuto's delay is
  -- meaningless there rather than wrong.
  function overrides.say(self, text)
    return self:push({ kind = "message", text = text })
  end

  function overrides.sayAuto(self, text)
    return self:push({ kind = "message", text = text })
  end

  function overrides.openItems(self) return self:openPack() end
  function overrides.openReplacementMenu(self) return self:openParty(true) end
  function overrides.finish(self) return self:finishBattle() end

  function overrides.askNicknameUI(self, mon, displayName)
    if displayName then
      warnOnce("battle.askNicknameUI",
        "[%s] BattleState:askNicknameUI drops displayName on Gold: the "
        .. "nickname prompt names the species itself",
        who("src.battle.BattleState"))
    end
    return self:askNickname(mon)
  end

  function overrides.playEntranceCry(self, battler)
    return self:playCry(battler and battler.mon or battler)
  end

  function overrides.stampOT(save, mon)
    return rawRequire("src.battle.gen2.Mon").stampOT(save, mon)
  end

  -- Gen 1's tryRun PREDICTS; Gold's model method RESOLVES the escape, which
  -- is the difference between asking and doing.
  function overrides.tryRun(self)
    warnOnce("battle.tryRun",
      "[%s] BattleState:tryRun RESOLVES the escape on Gold "
      .. "(src/battle/gen2/Battle.lua:3618); Gen 1's queued a message and "
      .. "returned a roll", who("src.battle.BattleState"))
    return self.battle and self.battle:tryRun() or nil
  end

  -- These seven are INSTANCE methods a mod calls as battle:say(...), and the
  -- instance's metatable is Gold's own class -- a facade-only member would be
  -- unreachable from it.  Every one is a name Gold does not use, so the write
  -- is purely additive and changes nothing Gold's screen does; a name the
  -- class already answers is left exactly as it is.
  for _, name in ipairs({ "say", "sayAuto", "openItems", "openReplacementMenu",
                          "finish", "askNicknameUI", "playEntranceCry",
                          "tryRun" }) do
    if Battle2[name] == nil then Battle2[name] = overrides[name] end
  end

  return passThroughProxy(Battle2, overrides, absent, "src.battle.BattleState")
end

COVERAGE["src.battle.BattleState"] = {
  kind = "facade", target = "src.ui.gen2.BattleState",
  backed = "update draw __index isOpaque openParty swapMoves "
    .. "lowHealthAlarmActive playVictoryMusic say sayAuto openItems "
    .. "openReplacementMenu finish askNicknameUI playEntranceCry stampOT "
    .. "tryRun wantsFillScale",
  warned = "tryRun askNicknameUI",
  absent = "newWild newTrainer makeSafari makeGhost makeBattler resolveTurn "
    .. "computeDamage catchAttempt runRoll enter exit sgbPalettes "
    .. "isWideBattleLayout wideLayout bgMode uiSize letterboxWhite "
    .. "holdsUIAnchors BG_WORLD_DIM trainerPalette trainerPicPath "
    .. "trainerTrueColor trainerSprite invalidate "
    .. "backPlacement frontPlacement StatBox drawClassic drawBallRow "
    .. "safariAction safariEnemyTurn throwBall storeCaughtMon field ruleset "
    .. "rng oppClass partyIndex aiUses introText dead",
  notes = {
    newWild = "ABSENT: Gold has no factory that returns an unpushed battle, "
      .. "and World:startBattle constructs and pushes in one call.  A mod "
      .. "that wraps newWild to rewrite the species must be pointed at the "
      .. "encounter.species hook, which Gold raises with the same name and "
      .. "shape (World:rollEncounter)",
    makeSafari = "must stay absent: the wilds mod probes for it by name and "
      .. "takes its native safari path when it finds one",
    openParty = "Gold's takes a `forced` argument Gen 1's does not; a wrap "
      .. "must forward ... faithfully rather than normalising it away",
    wantsFillScale = "returns TRUE unconditionally on Gold, which reads as "
      .. "\"the player chose FILL\" and is not a choice at all",
    swapMoves = "no disabled-slot migration and no sfx on Gold",
    sides = "self.battle.sides is the same { index, battlers, screens, "
      .. "hazards, tokens } shape, with the same index-1-is-player rule",
    say = "Gold's messages always auto-advance, so sayAuto's delay is ignored",
  },
}

-- ------- src.script.ScriptRunner
--
-- NARROW FACADE, never an alias: ScriptRunner.new(game, overworld) landing on
-- Vm.new(scripts, text, events, hooks) would build a Vm whose `scripts` is
-- the Game and whose `text` is the World, and every later call would fail
-- deep inside the VM naming neither the mod nor the mismatch.
--
-- Two halves.  scanLabels and validate are PURE over the mod's own row list
-- and forward verbatim; the lifecycle half has a different execution model
-- and is a thin handle onto the one world.vm, with the two double-drive
-- members refused.

local SR = "src.script.ScriptRunner"

local function buildScriptRunner()
  local Gen1 = rawRequire("src.script.ScriptRunner")
  local adapter = {}

  -- pure over the caller's table; Gold's VM has no label concept, so a
  -- scanned label is meaningful only to the mod's own tooling
  adapter.scanLabels = Gen1.scanLabels

  -- The default lookup MUST be replaced: with lookup nil, Gen 1's validate
  -- resolves against src/script/Commands.lua, so a script of show_text / wait
  -- / warp validates CLEAN on Gold and then every row is skipped at run time.
  -- A validator that passes a script the game cannot run is worse than none.
  function adapter.validate(script, lookup)
    return Gen1.validate(script, lookup or function(verb)
      local g = live()
      local commands = g and g.data and g.data.commands
      return commands ~= nil and commands[verb] ~= nil
    end)
  end

  local Handle = {}
  Handle.__index = function(self, key)
    if key == "game" then return live() end
    if key == "overworld" then return rawget(self, "world") end
    local vm = rawget(self, "vm")
    if key == "co" then return vm and vm.co end
    if key == "ctx" then return vm and vm.ctx end
    if key == "waitingFrames" then return vm and vm.waitLeft end
    if key == "parallel" then
      warnOnce("runner.parallel",
        "[%s] runner.parallel has no Gen 2 backing: Gold has one script "
        .. "frame, and src/script/gen2/Vm.lua unpacks the `foreground` and "
        .. "`blocking` flags and ignores them", who(SR))
      return nil
    end
    if key == "waitingCheck" then
      warnOnce("runner.waitingCheck",
        "[%s] runner.waitingCheck has no Gen 2 backing: the Gen 2 VM parks on "
        .. "a TYPED REQUEST the World resumes, with no polling model", who(SR))
      return nil
    end
    return rawget(Handle, key)
  end

  function Handle:isRunning()
    return self.vm ~= nil and self.vm:running() or false
  end

  function Handle:run(script, extra)
    if extra ~= nil then
      warnOnce("runner.run.extra",
        "[%s] runner:run's `extra` is unserved on Gold: the VM builds its own "
        .. "ctx and there is no afterScript / onDone drain", who(SR))
    end
    if not self.vm then return false end
    return self.vm:start(script)
  end

  -- Same name and calling convention as Gen 1's fire-and-forget resume, and
  -- Gold's re-raises AND double-drives a VM the World is already driving, so
  -- a pending request is dispatched twice.  Refused rather than forwarded.
  Handle.resume = unbacked(SR, "runner:resume",
    "Gold's Vm:resume re-raises and dispatches the pending request, and the "
    .. "World already drives it; a second call double-drives the VM")

  Handle.update = unbacked(SR, "runner:update",
    "World already calls Vm:update every frame; a second call "
    .. "double-decrements waitLeft, so every `pause` in a running script "
    .. "finishes early")

  Handle.exec = unbacked(SR, "runner:exec",
    "the patch point a mod wants is the script.command hook, which both "
    .. "generations raise around the one-row dispatch with (ctx, name, args)")

  Handle.yield = unbacked(SR, "runner:yield",
    "a mod verb blocks with ctx.vm:waitFrames(n) or ctx.vm:showText(key)")

  Handle.makeContext = unbacked(SR, "runner:makeContext",
    "Vm:scriptCtx builds its own ctx and deliberately carries no game / save "
    .. "/ overworld / runner")

  function adapter.new(game, overworldArg)
    local world = overworldArg
    if type(world) ~= "table" or world.vm == nil then
      local g = live() or game
      world = g and g.world
    end
    if not world or not world.vm then
      error("src.script.ScriptRunner: Gold has one script frame and it does "
        .. "not exist yet; take it after the game.ready event", 0)
    end
    return setmetatable({ vm = world.vm, world = world }, Handle)
  end

  return adapter
end

COVERAGE[SR] = {
  kind = "facade", target = "src.script.gen2.Vm",
  backed = "scanLabels validate new isRunning run game overworld co ctx "
    .. "waitingFrames",
  warned = "resume update exec yield makeContext parallel waitingCheck",
  absent = "__index",
  notes = {
    validate = "the default verb lookup is game.data.commands (MOD verbs "
      .. "only on Gold), not src/script/Commands.lua, or a script of Gen 1 "
      .. "built-ins would validate clean and then run as nothing",
    new = "a thin handle onto the ONE world.vm, never a second runner: a "
      .. "mod-built Vm would carry none of World's ~70 hooks, so every "
      .. "blocking opcode falls through",
    run = "Vm:start returns FALSE when busy where Gen 1 asserts; only rows "
      .. "whose verb is a REGISTERED mod command run, and a verb that raises "
      .. "is pcall'd and skipped",
    scanLabels = "Gold's VM has no label concept at all",
    ["src.script.Commands"] = "NOT gated by the shim: a mod requiring it on "
      .. "Gold gets the real Gen 1 table of ~100 verbs, none of which Gold "
      .. "can run",
    events = "script.started / script.ended / script.command already work on "
      .. "Gold with the same payload and are the supported route",
  },
}

-- ------- the table

-- name -> how to build it.  A string means the Gen 2 arm IS the adapter, so a
-- mod's patch lands on the table Gold runs rather than on a copy.
local ADAPTERS = {
  ["src.core.Game"] = buildGame,
  ["src.world.NPC"] = buildNpc,
  ["src.world.Collision"] = buildCollision,
  ["src.world.FieldDefaults"] = buildFieldDefaults,
  ["src.pokemon.Boxes"] = buildBoxes,
  ["src.world.OverworldController"] = buildOverworld,
  ["src.ui.PartyMenu"] = buildPartyMenu,
  ["src.ui.StartMenu"] = buildStartMenu,
  ["src.ui.OptionsMenu"] = buildOptionsMenu,
  ["src.battle.BattleState"] = buildBattleState,
  ["src.script.ScriptRunner"] = buildScriptRunner,
  ["src.world.PikachuFollower"] = "src.world.gen2.Follower",
  ["src.world.Map"] = "src.world.gen2.Map",
  ["src.world.WorldAPI"] = "src.world.gen2.WorldAPI",
  -- Gen 1's BoxMenu is Bill's PC TOP MENU, which is PcMenu on Gold;
  -- src/ui/gen2/BoxMenu.lua is the withdraw/deposit LIST Gen 1 builds inline.
  ["src.ui.BoxMenu"] = "src.ui.gen2.PcMenu",
}

Gen2Compat.ADAPTERS = ADAPTERS

function Gen2Compat.bind(fn)
  resolveGame = fn
end

function Gen2Compat.serves(name)
  return ADAPTERS[name] ~= nil
end

-- ------- the coverage API
--
-- Stable contract, versioned by Gen2Compat.COVERAGE_VERSION:
--   Gen2Compat.modules()             -> sorted array of served module names
--   Gen2Compat.coverage(name)        -> { module, kind, target, members, notes }
--                                       members[member] = "backed"|"warned"|
--                                       "absent"; a fresh table per call
--   Gen2Compat.memberStatus(n, m)    -> that status string, or nil when the
--                                       module is unserved or the member is
--                                       not recorded

function Gen2Compat.modules()
  local out = {}
  for name in pairs(ADAPTERS) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function Gen2Compat.coverage(name)
  local row = COVERAGE[name]
  if not row then return nil end
  local members = {}
  -- warned last on purpose: a name listed as backed AND warned is present and
  -- degraded, and the weaker claim is the safe one to publish
  for _, status in ipairs({ "backed", "absent", "warned" }) do
    for _, member in ipairs(words(row[status])) do
      members[member] = status
    end
  end
  local notes = {}
  for key, value in pairs(row.notes or {}) do notes[key] = value end
  return { module = name, kind = row.kind, target = row.target,
           members = members, notes = notes }
end

function Gen2Compat.memberStatus(name, member)
  local row = Gen2Compat.coverage(name)
  return row and row.members[member] or nil
end

-- The one entry point the Loader calls.  `modId` is attribution only: no
-- adapter branches on it.
function Gen2Compat.resolve(name, modId)
  local spec = ADAPTERS[name]
  if not spec then return nil end
  local module = built[name]
  if not module then
    module = type(spec) == "string" and rawRequire(spec) or spec()
    built[name] = module
  end
  if modId then
    local ids = claimants[name]
    if not ids then ids = {} claimants[name] = ids end
    local seen = false
    for _, id in ipairs(ids) do if id == modId then seen = true break end end
    if not seen then ids[#ids + 1] = modId end
  end
  return module
end

return Gen2Compat
