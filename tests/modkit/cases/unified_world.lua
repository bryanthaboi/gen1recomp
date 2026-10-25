package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified world")
local UnifiedWorld = require("src.mods.UnifiedWorld")
local Records = require("src.mods.UnifiedRecords")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local Events = require("src.mods.Events")
local ScriptRunner = require("src.script.ScriptRunner")
local TextBox = require("src.render.TextBox")
local Gen3Compat = require("src.mods.Gen3Compat")
local Sdk = require("tests.modkit.sdk")

local methods = {
  "overworld", "current", "activeBlockAt", "party", "canReorderParty",
  "reorderParty", "availableFieldActions", "useFieldAction", "canFly",
  "flyTo", "mapOverview", "warpTo", "toggleObject", "setFlag", "getFlag",
  "effectiveEncounters", "replaceBlock", "spawnNpc", "liveMaps", "removeNpc",
  "npc", "queueScript", "startWildBattle", "invalidateMap",
}
T.same(UnifiedWorld.METHODS, methods, "all generations share the 24 world calls")

local savedRuntime = { Runtime.events, Runtime.hooks, Runtime.errors }
local oldTextBoxNew = TextBox.new
local savedModules = {}
local function install(name, module)
  if not savedModules[name] then savedModules[name] = { package.loaded[name] } end
  package.loaded[name] = module
end

local function rejected(value, reason, expected, label)
  T.eq(value, nil, label .. " returns nil")
  if expected then T.eq(reason, expected, label .. " explains refusal")
  else T.check(type(reason) == "string" and #reason > 0, label .. " explains refusal") end
end

local function fixture(generation)
  local f = { generation = generation, texts = {}, flies = {}, errors = {}, busy = false }
  local version = ({ "red", "gold", "firered" })[generation]
  local hooks, events = Hooks.new(), Events.new()
  Runtime.install(events, hooks, f.errors)
  f.hooks = hooks
  local data = generation == 3 and Sdk.gen3Data() or {
    pokemon = { MEW = { name = "MEW" }, PIDGEY = { name = "PIDGEY" } },
    moves = { POUND = { pp = 35 }, FLY = { pp = 15 } },
    items = {}, text = { FIRST = "First row", SECOND = "Second row" },
    audio = { sfx = {} },
    field = { outsideTilesets = { "OVERWORLD" }, flyOrder = { "HOME", "DEST" },
      flyWarps = { HOME = true, DEST = true } },
  }
  local home, dest = "HOME", "DEST"
  if generation == 3 then home, dest = "FR_HOME", "FR_DEST" end
  f.home, f.dest = home, dest
  local maps = {}
  for i, id in ipairs({ home, dest }) do
    maps[id] = { id = id, index = i - 1, label = id, width = 2, height = 2,
      tileset = "OVERWORLD", environment = "TOWN", type = 1,
      blocks = { 7, 8, 8, 7 }, midLayout = { width = 2, height = 2,
        midAt = function(_, x, y) return x == y and 7 or 8 end } }
  end
  data.text_pointers = data.text_pointers or {}
  if generation == 3 then
    data.gen3Text = data.gen3Text or {}
    data.gen3Text.FIRST, data.gen3Text.SECOND = "First row", "Second row"
  end
  setmetatable(data, { __index = require("src.core.Data") })
  data.maps = maps
  data.sprites = {
    SPRITE_WORLD_PROBE = { image = "fixture_npc.png", frames = 6, walker = true },
    SPRITE_WORLD_ALT = { image = "fixture_npc_alt.png", frames = 6, walker = true },
  }
  local save = { version = version, flags = {}, inventory = { THUNDERBADGE = 1 },
    visited = { HOME = true, DEST = true }, player = { badges = { STORM = true } },
    party = { { species = "MEW", nickname = "Scout", level = 20, hp = 30,
      stats = { hp = 40, attack = 21, defense = 22, speed = 23,
        special = generation == 1 and 24 or nil,
        specialAttack = generation ~= 1 and 24 or nil,
        specialDefense = generation ~= 1 and 25 or nil },
      moves = { { id = "POUND", pp = 30 }, { id = "FLY", pp = 15 } } },
      { species = "PIDGEY", level = 10, hp = 15, stats = { hp = 20 }, moves = {} } } }
  local game = { data = data, save = save, phase = "field" }
  f.game, f.save = game, save
  local player = { cellX = 0, cellY = 0, facing = "down", moving = false }
  local ow = { isOverworld = true, player = player, scriptMoves = {}, maps = maps }
  f.ow, f.player = ow, player
  local stack = { states = generation == 1 and { ow } or {} }
  function stack:top() return self.states[#self.states] end
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  game.stack = stack
  if generation == 1 then
    local Map = require("src.world.Map")
    ow.map = Map.new(maps[home], { walkable = {}, blocks = {} })
    game.overworld = ow
    ow.runner = ScriptRunner.new(game, ow)
    TextBox.new = function(_, text, onDone)
      local box = { text = text, onDone = onDone }
      f.texts[#f.texts + 1] = box
      return box
    end
    function ow:partyKnows(move)
      for _, mon in ipairs(game.save.party) do
        for _, row in ipairs(mon.moves) do if row.id == move then return mon end end
      end
    end
    function ow:flyTo(id) f.flies[#f.flies + 1] = id end
    function ow:startWarpTo(id, x, y, facing)
      f.warp = { map = id, x = x, y = y, facing = facing }
      self.transitioning = true
    end
    function ow:pushBattle(battle) f.battle = battle; stack:push(battle) end
    function ow:afterBattle(result, battle)
      f.afterBattle = { result = result, battle = battle }
    end
  elseif generation == 2 then
    ow.map = require("src.world.gen2.Map").new(maps[home], {
      collision = { [8] = { 0x29, 0x29, 0x29, 0x29 } }, blocks = {} })
    game.world = ow
    function ow:acceptsMenuInput() return not f.busy end
    function ow:fieldContext()
      return { save = game.save, party = game.save.party, environment = "TOWN" }
    end
    function ow:flyPoints() return { { spawn = "HOME_SPAWN" } } end
    ow.landmarks = { spawns = { HOME_SPAWN = { map = home } } }
    function ow:flyTo(spawn, mon)
      f.flies[#f.flies + 1] = { spawn = spawn, mon = mon }
      return true
    end
    function ow:warpToMapId(id, x, y, facing)
      f.warp = { map = id, x = x, y = y, facing = facing }
      f.busy = true
      return true
    end
    function ow:showText(text, onDone)
      f.texts[#f.texts + 1] = { text = text, onDone = onDone }
      f.busy = true
    end
    function ow:startBattle(args, onDone)
      f.battle = { args = args, onDone = onDone }
      f.busy = true
      return true
    end
  else
    save.party[1].species, save.party[2].species = 151, 16
    save.party[1].moves, save.party[1].pp = { 1, 19 }, { 30, 15 }
    save.party[1].item = 13
    save.badges = { FLY = true }
    data.gen3Pokemon._moveNames[19] = "FLY"
    data.gen3Moves._rom[19] = { pp = 15 }
    game.session = save
    local field = require("src.core.game3.field")
    local savedField = {}
    for _, key in ipairs({ "running", "_locks", "_game", "_session", "_modScriptLock",
        "metatileOverrideAt", "setMetatile", "flyDestination", "flyTo" }) do
      savedField[key] = { field[key] }
    end
    function f:restoreField()
      for key, saved in pairs(savedField) do field[key] = saved[1] end
    end
    field.running, field._locks, field._game, field._session = true, {}, game, save
    field._modScriptLock = nil
    f.field = field
    local map = { current = home, currentDef = function() return maps[f.map.current] end }
    f.map = map
    install("src.core.game3.runtime", { getSession = function() return game.session end,
      uiBusy = function() return f.busy end })
    install("src.core.game3.map", map)
    install("src.core.game3.player", player)
    install("src.core.game3.pokemon", data.gen3Pokemon)
    install("src.core.game3.scripting.space", {})
    install("src.core.game3.collision", { behavior = function() return 0x29 end })
    install("src.core.game3.warp", {
      isBusy = function() return f.busy end,
      request = function(_, owner, id, x, y, facing)
        T.eq(owner, game, "Gen 3 warp dispatch retains the live game")
        f.warp = { map = id, x = x, y = y, facing = facing }
        f.busy = true
        return true
      end,
    })
    install("src.core.game3.battle.init", { isActive = function() return f.battleActive end })
    data.gen3Pokemon.speciesFromName = function(id)
      return require("src.mods.Schemas").gen3View.speciesNum(data.gen3Pokemon, id)
    end
    data.gen3Pokemon.name = function(id) return data.gen3Pokemon._names[id] end
    install("src.core.game3.battle_bridge", {
      startWild = function(_, owner, args, opts)
        T.eq(owner, game, "Gen 3 battle dispatch retains the live game")
        f.battle = { args = args, onDone = opts.done }
        f.battleActive = true
        return true
      end,
    })
    local message = { open = false }
    function message.isOpen() return message.open end
    function message.show(text, onDone)
      message.open, message._done = true, onDone
      f.texts[#f.texts + 1] = { text = text, onDone = onDone }
      f.busy = true
    end
    function message.close()
      local done = message._done
      message.open, message._done, f.busy = false, nil, false
      if done then done() end
    end
    f.message = message
    install("src.ui.game3.message", message)
    function field.metatileOverrideAt() return f.override end
    function field.setMetatile(x, y, id) f.override = { metatile = id } end
    function field.flyDestination() return { map = home, x = 0, y = 0 } end
    function field.flyTo(section, mon, opts)
      f.flies[#f.flies + 1] = { section = section, mon = mon, opts = opts }
      return true
    end
    f.constants = { of = function()
      return { region_map_sections = { byName = { MAPSEC_HOME = 1 } } }
    end }
    f.regionMap = { MAPSECTYPE = { VISITED = 1 }, mapsecType = function() return 1 end }
    Gen3Compat.bind(function() return game end)
  end

  local objDef = { index = 1, localId = 1, name = "world_probe",
    sprite = "SPRITE_WORLD_PROBE", x = 1, y = 1,
    movement = generation == 2 and 1 or "STAY", range = "DOWN" }
  if generation == 3 then
    data.gen2Sprites = data.sprites
    f.npc = require("src.core.game3.object_prepare").instance(objDef, { mapId = home })
    install("src.core.game3.objects", { _byId = { [1] = f.npc }, _order = { 1 } })
  elseif generation == 2 then
    f.npc = require("src.world.gen2.Npc").new(home, objDef, data.sprites[objDef.sprite])
    ow.game = game
    function ow:applySpritePalette(npc) f.paletteNpc = npc end
    ow.npcs = { f.npc }
  else
    f.npc = require("src.world.NPC").new(data, home, objDef)
    ow.npcs = { f.npc }
  end

  local function engineRequire(name)
    if name == "src.core.game3.constants" then return f.constants
    elseif name == "src.ui.game3.region_map" then return f.regionMap
    elseif name == "src.battle.BattleState" then
      return { newWild = function(owner, species, level)
        T.eq(owner, game, "Gen 1 battle constructor receives the live game")
        return { species = species, level = level }
      end }
    elseif name == "src.battle.gen2.Mon" then
      return { new = function(_, species, level) return { species = species, level = level } end }
    end
    return require(name)
  end
  function f:world(owner)
    return UnifiedWorld.new(function() return self.live end, generation, version,
      owner or "world_probe", engineRequire)
  end
  f.api = f:world()
  function f:update(action)
    local a, b, c = hooks:call("core.update", function(owner, dt)
      T.eq(owner, self.game, "core.update receives the live game")
      if action then action() end
      return "updated", nil, dt
    end, self.game, 0.25)
    T.eq(a, "updated", "continuation preserves update's first return")
    T.eq(b, nil, "continuation preserves nil return holes")
    T.eq(c, 0.25, "continuation preserves trailing returns")
  end
  function f:completeText()
    local box = self.texts[#self.texts]
    if generation == 3 then self.message.close()
    else
      if generation == 1 and stack:top() == box then stack:pop() end
      self.busy = false
      box.onDone()
    end
    return box.onDone
  end
  function f:clearCancelledText(box)
    if generation == 1 then
      T.check(stack:top() ~= box, "cancellation removes its owned text box")
      if stack:top() == box then stack:pop() end
      T.eq(stack:top(), ow, "cancellation preserves the overworld stack state")
    elseif generation == 3 then
      T.eq(self.message.isOpen(), false, "cancellation closes its owned message")
      T.eq(self.message._done, nil, "cancellation retires its owned message callback")
    else self.busy = false end
  end
  function f:completeBattle(result, ...)
    local callback
    if generation == 1 then
      stack:pop()
      callback = self.battle.onFinish
    else
      self.busy, self.battleActive = false, false
      callback = self.battle.onDone
    end
    callback(result or "won", ...)
    return callback
  end
  function f:arrive(id, x, y)
    if generation == 3 then self.map.current = id
    else self.ow.map.id, self.ow.map.def = id, maps[id] end
    player.cellX, player.cellY, player.facing = x, y, "up"
    self.busy, self.ow.transitioning = false, false
  end
  return f
end

for generation = 1, 3 do
  local f = fixture(generation)
  local api = f.api
  local expectedErrors = 0
  for _, name in ipairs(methods) do
    local value, reason = api[name](api)
    rejected(value, reason, "no game", name .. " before provider is ready")
  end
  f.live = f.game
  local current = api:current()
  T.eq(current.mapId, f.home, "pre-ready handle resolves the native map")
  T.eq(current.block.tileSize, generation == 3 and 16 or 32, "native tile scale is explicit")
  T.eq(current.block.coordinateBase, 0, "world coordinates are zero based")
  current.x, current.block.tileSize = 99, 99
  T.eq(api:current().x, 0, "current returns a detached view")
  local id, meta = api:activeBlockAt(f.home, 0, 0)
  T.eq(id, 7, "activeBlockAt returns the native block ID rather than behavior 0x29")
  T.eq(meta.kind, generation == 3 and "metatile" or "block", "block kind matches the native grid")
  local value, reason = api:activeBlockAt(f.home, 2, 0)
  rejected(value, reason, "block coordinates out of bounds", "block bounds")
  value, reason = api:activeBlockAt(f.dest, 0, 0)
  rejected(value, reason, "map is not active", "stale map read")

  local npc = api:npc(f.home, "world_probe")
  T.check(type(npc) == "table", "native NPC lookup returns a handle")
  T.eq(npc.id, f.home .. "_obj_1", "NPC handles retain Gen 1 public identity")
  T.eq(api:npc(f.home, npc.id).id, npc.id, "public identity resolves the native handle")
  T.eq(type(npc.setAppearance), "function", "native NPC handles inherit setAppearance")
  local x, y = npc:position()
  T.eq(x, 1, "NPC handle reads the native actor's x coordinate")
  T.eq(y, 1, "NPC handle reads the native actor's y coordinate")
  value, reason = npc:setAppearance("SPRITE_WORLD_MISSING")
  rejected(value, reason, "unknown sprite: SPRITE_WORLD_MISSING", "unknown NPC appearance")
  T.eq(npc:setAppearance("SPRITE_WORLD_ALT"), true, "appearance reaches the native handle")
  if generation == 3 then
    T.eq(f.npc.sprite, "SPRITE_WORLD_ALT", "Gen 3 appearance updates the native sprite")
    T.eq(f.npc.def.sprite, "SPRITE_WORLD_ALT", "Gen 3 appearance updates the object definition")
  else
    T.eq(f.npc.appearance, "SPRITE_WORLD_ALT", "appearance updates the native NPC")
    T.eq(f.npc.sprite.def, f.game.data.sprites.SPRITE_WORLD_ALT,
      "appearance updates the native sprite renderer")
    if generation == 2 then
      T.eq(f.paletteNpc, f.npc, "Gen 2 appearance reapplies the native actor's palette")
    end
  end
  T.eq(npc.id, f.home .. "_obj_1", "appearance preserves public identity")

  local party = api:party()
  T.eq(party[1].species, "MEW", "party species is canonical")
  T.eq(party[1].nickname, "Scout", "party exposes the raw nickname")
  T.eq(party[1].moves[1].id, "POUND", "party moves are canonical")
  T.eq(party[1].moves[1].pp, 30, "party retains current PP")
  T.eq(party[1].stats.special, 24, "party exposes common Special")
  T.eq(party[1].stats.specialAttack, 24, "party exposes canonical Special Attack")
  T.eq(party[1].stats.specialDefense, generation == 1 and 24 or 25,
    "party exposes shared or split Special as native")
  party[1].hp, party[1].moves[1].pp, party[1].native.hp = 1, 1, 1
  party[1].nickname, party[1].stats.special = "Detached", 1
  T.eq(f.save.party[1].hp, 30, "party HP and native extension are detached")
  T.eq(api:party()[1].moves[1].pp, 30, "party move rows are detached")
  T.eq(api:party()[1].nickname, "Scout", "party nicknames are detached")
  T.eq(api:party()[1].stats.special, 24, "party stats are detached")
  T.eq(Records.applyMon(f.save.party[1], { nickname = "Guide", stats = { special = 31 } },
    generation, f.game.data, f.save.version), true, "Gen 1-shaped nickname and Special writes succeed")
  T.eq(f.save.party[1].nickname, "Guide", "nickname writes reach the native record")
  T.eq(api:party()[1].nickname, "Guide", "party rereads the written nickname")
  T.eq(api:party()[1].stats.special, 31, "party rereads the written common Special")
  if generation == 1 then
    T.eq(f.save.party[1].stats.special, 31, "Gen 1 writes native Special")
    T.eq(f.save.party[1].stats.specialAttack, nil, "Gen 1 writes do not add Special Attack")
    T.eq(f.save.party[1].stats.specialDefense, nil, "Gen 1 writes do not add Special Defense")
  else
    T.eq(f.save.party[1].stats.specialAttack, 31, "common Special writes native Special Attack")
    T.eq(f.save.party[1].stats.specialDefense, 31, "common Special writes native Special Defense")
  end
  T.eq(api:canReorderParty(), true, "idle native party can be reordered")
  T.eq(api:reorderParty(1, 1), true, "same-slot reorder reaches the native adapter")
  value, reason = api:reorderParty(1.5, 2)
  rejected(value, reason, "invalid party slot", "fractional party slot")

  local other = f:world("other_probe")
  local changes = 0
  local stop = Runtime.events:on("flag.changed", function() changes = changes + 1 end)
  T.eq(api:getFlag("mod:visited"), false, "new portable flags are false")
  T.eq(api:setFlag("mod:visited", true), true, "portable flag writes succeed")
  T.eq(api:setFlag("mod:visited", true), true, "repeated writes succeed")
  T.eq(changes, 1, "unchanged flags do not emit another change")
  T.eq(f:world():getFlag("mod:visited"), true, "a fresh facade sees persisted flags")
  T.eq(f.save.modData.world_probe.worldFlags.visited, true, "flags live in the mod save bucket")
  T.eq(other:getFlag("mod:visited"), false, "mod flags are isolated")
  value, reason = other:getFlag("mod.world_probe.visited")
  rejected(value, reason, "foreign mod flag", "foreign explicit flag")
  T.eq(next(f.save.flags), nil, "portable flags do not enter native flag storage")
  value, reason = api:setFlag("mod:visited", 1)
  rejected(value, reason, "flag value must be boolean", "nonboolean flag")
  value, reason = api:setFlag(-1, true)
  rejected(value, reason, "invalid or unknown flag", "invalid native flag")
  T.eq(api:setFlag("mod:visited", false), true, "portable flags can be cleared")
  T.eq(changes, 2, "clearing emits exactly one change")
  stop()

  T.eq(api:canFly(), true, "native pure validator accepts outdoor FLY")
  T.eq(api:canFly(), true, "querying FLY repeatedly remains available")
  T.eq(#f.flies, 0, "FLY availability does not dispatch a destination")
  T.eq(#f.texts, 0, "FLY availability does not open dialogue")
  T.eq(api:flyTo(f.home), true, "validated destination dispatch succeeds")
  T.eq(#f.flies, 1, "one request dispatches one native flight")
  if generation == 1 then T.eq(f.flies[1], f.home, "Gen 1 receives the validated map")
  elseif generation == 2 then
    T.eq(f.flies[1].spawn, "HOME_SPAWN", "Gen 2 dispatches the actual spawn ID")
    T.eq(f.flies[1].mon, f.save.party[1], "Gen 2 dispatches the actual move user")
  else
    T.eq(f.flies[1].section, 1, "Gen 3 dispatches the validated region section")
    T.eq(f.flies[1].opts.dest.map, f.home, "Gen 3 passes the validated warp destination")
  end
  value, reason = api:flyTo("UNKNOWN")
  rejected(value, reason, nil, "unknown FLY destination")
  T.eq(#f.flies, 1, "rejected FLY never dispatches")
  if generation == 1 then f.ow.player.moving = true
  elseif generation == 2 then f.busy = true
  else f.field.locked = true end
  T.eq(api:canFly(), false, "busy world refuses FLY availability")
  value, reason = api:flyTo(f.home)
  rejected(value, reason, "world is busy", "busy FLY dispatch")
  T.eq(#f.flies, 1, "busy FLY never reaches native execution")
  value, reason = api:queueScript({})
  rejected(value, reason, "world is busy", "busy script")
  f.ow.player.moving, f.busy = false, false
  if f.field then f.field.locked = false end

  for _, args in ipairs({ { f.dest, -1, 0 }, { f.dest, 0 / 0, 0 },
      { f.dest, math.huge, 0 }, { f.dest, 99, 0 }, { f.dest, 0, 0, "north" } }) do
    value, reason = api:warpTo((table.unpack or unpack)(args))
    rejected(value, reason, nil, "invalid warp")
  end
  T.eq(f.warp, nil, "invalid warp input never reaches native dispatch")
  value, reason = api:startWildBattle("MEW", 1.5)
  rejected(value, reason, "level must be a whole number 1..100", "fractional battle level")
  value, reason = api:queueScript({ { "set_flag", "mod:partial" }, { "unsupported" } })
  rejected(value, reason, "unsupported script command: unsupported", "script preflight")
  T.eq(api:getFlag("mod:partial"), false, "preflight failure does not run earlier rows")
  value, reason = api:queueScript({ { "show_text", "hello" } }, { onDone = true })
  rejected(value, reason, "invalid script option", "invalid script callback")
  local tooMany = {}
  for i = 1, 1025 do tooMany[i] = { "show_text", "hello" } end
  value, reason = api:queueScript(tooMany)
  rejected(value, reason, "too many script rows", "bounded script")
  value, reason = api:queueScript({ { "show_text", "hello", "extra" } })
  rejected(value, reason, "invalid text substitutions", "invalid text substitutions")
  value, reason = api:queueScript({ { "show_text", string.rep("x", 65537) } })
  rejected(value, reason, "invalid script text", "bounded script text")

  local calls, succeeded, failure = 0
  local function done(ok, err) calls, succeeded, failure = calls + 1, ok, err end
  local started, ended, scriptCtx = 0, 0
  local stopStarted = Runtime.events:on("script.started", function(payload)
    started, scriptCtx = started + 1, payload.ctx
    T.eq(payload.ctx.runner:isRunning(), true, "whole-script runner is live at script.started")
  end)
  local stopEnded = Runtime.events:on("script.ended", function(payload)
    ended = ended + 1
    T.eq(payload.ctx, scriptCtx, "whole-script completion retains its starting context")
    T.eq(payload.ctx.runner:isRunning(), false, "whole-script runner is retired at script.ended")
    T.eq(payload.completed, true, "whole-script lifecycle reports successful completion")
  end)
  T.eq(api:setFlag("mod:text_pending", true), true, "text sequence starts with a pending flag")
  T.eq(api:queueScript({ { "show_text", "FIRST" }, { "show_text", "SECOND" },
    { "set_flag", "mod:text_done" }, { "clear_flag", "mod:text_pending" } },
    { onDone = done }), true, "two text rows start")
  T.eq(#f.texts, 1, "only the first text starts immediately")
  T.eq(started, 1, "text queue emits one script.started event")
  f:update(function()
    f:completeText()
    T.eq(#f.texts, 1, "native completion does not reenter the text runner")
    T.eq(calls, 0, "native text completion does not finish the whole script")
    T.eq(ended, 0, "native text completion does not end the whole script")
  end)
  T.eq(#f.texts, 2, "second text starts after native update returns")
  T.eq(ended, 0, "the second text remains inside the same script lifecycle")
  T.eq(f.texts[1].text, "First row", "first row uses native text resolution")
  T.eq(f.texts[2].text, "Second row", "second row uses native text resolution")
  f:update(function() f:completeText() end)
  T.eq(api:getFlag("mod:text_done"), true, "following row runs after second text completes")
  T.eq(api:getFlag("mod:text_pending"), true, "clear_flag waits for its own script step")
  f:update()
  f:update()
  T.eq(api:getFlag("mod:text_pending"), false, "clear_flag clears the portable flag")
  T.eq(calls, 1, "text script finishes exactly once")
  T.eq(started, 1, "text rows share one script.started event")
  T.eq(ended, 1, "text queue emits one script.ended event")
  T.eq(succeeded, true, "text script reports success")
  T.eq(failure, nil, "text script has no hidden runner failure")
  T.eq(f.hooks.chains["core.update"], nil, "completed script retires its update subscription")
  stopStarted()
  stopEnded()

  calls = 0
  T.eq(api:queueScript({ { "warp", f.dest, 1, 1, "up" },
    { "set_flag", "mod:arrived" } }, { onDone = done }), true, "async warp starts")
  T.eq(f.warp.map, f.dest, "warp reaches the real native adapter seam")
  f:update()
  T.eq(api:getFlag("mod:arrived"), false, "warp does not advance while native world is busy")
  f.busy, f.ow.transitioning = false, false
  f:update()
  T.eq(api:getFlag("mod:arrived"), false, "idle old map is not warp arrival")
  f:arrive(f.dest, 0, 0)
  f:update()
  T.eq(api:getFlag("mod:arrived"), false, "destination map with wrong coordinates still waits")
  f:arrive(f.dest, 1, 1)
  f.player.facing = "down"
  f:update()
  T.eq(api:getFlag("mod:arrived"), false, "warp waits for the requested facing too")
  f.player.facing = "up"
  f:update()
  T.eq(api:getFlag("mod:arrived"), true, "warp advances only at the requested destination")
  f:update()
  T.eq(calls, 1, "warp script finishes once")

  calls = 0
  T.eq(api:queueScript({ { "start_battle", "wild", "MEW", 5 },
    { "set_flag", "mod:battle_done" } }, { onDone = done }), true, "async wild battle starts")
  if generation == 1 then T.eq(f.battle.species, "MEW", "Gen 1 battle uses native species")
  elseif generation == 2 then T.eq(f.battle.args.wild.species, "MEW", "Gen 2 battle builds a native mon")
  else T.eq(f.battle.args.species, 151, "Gen 3 battle receives the numeric native species") end
  f:update()
  T.eq(api:getFlag("mod:battle_done"), false, "battle row waits for native completion")
  f:update(function()
    f:completeBattle()
    T.eq(api:getFlag("mod:battle_done"), false, "battle completion does not reenter the script")
  end)
  T.eq(api:getFlag("mod:battle_done"), true, "battle continuation runs after native update")
  f:update()
  if generation ~= 1 then f.battle.onDone("won") end
  f:update()
  T.eq(calls, 1, "duplicate or late battle completion cannot finish twice")
  if generation == 1 then T.eq(f.afterBattle.result, "won", "native Gen 1 afterBattle is preserved") end

  for _, outcome in ipairs({ "win", "lose", { caught = true } }) do
    local outcomes, detail = 0, {}
    T.eq(api:startWildBattle("MEW", 5, function(...)
      outcomes = outcomes + 1
      local result, nativeDetail, hole, tail = ...
      T.eq(select("#", ...), 4, "direct wild callback preserves native argument count")
      T.eq(result, outcome, "direct wild callback preserves the native outcome")
      T.eq(nativeDetail, detail, "direct wild callback preserves opaque native arguments")
      T.eq(hole, nil, "direct wild callback preserves nil argument holes")
      T.eq(tail, "tail", "direct wild callback preserves trailing native arguments")
    end), true, "direct API3 wild battle starts")
    local mapId = api:current().mapId
    f:arrive(mapId == f.home and f.dest or f.home, 0, 0)
    local complete = f:completeBattle(outcome, detail, nil, "tail")
    T.eq(outcomes, 1, "native map changes preserve the direct wild callback")
    complete(outcome, detail, nil, "tail")
    T.eq(outcomes, 1, "duplicate direct wild completion is delivered once")
    if generation == 1 then
      T.eq(f.afterBattle.result, outcome, "direct wild completion preserves native afterBattle")
    end
  end

  for _, change in ipairs({ "provider", "save" }) do
    local outcomes, live = 0, f.live
    local saveKey = generation == 3 and "session" or "save"
    local previousSave = f.game[saveKey]
    T.eq(api:startWildBattle("MEW", 5, function() outcomes = outcomes + 1 end),
      true, "direct wild battle starts before " .. change .. " replacement")
    if change == "provider" then f.live = {}
    else f.game[saveKey] = {} end
    local complete = f:completeBattle("win")
    T.eq(outcomes, 0, change .. " replacement blocks the stale direct wild callback")
    f.live, f.game[saveKey] = live, previousSave
    complete("win")
    T.eq(outcomes, 0, "restoring the " .. change .. " cannot revive a stale wild callback")
  end

  T.eq(#f.errors, 0, "native continuations complete without swallowed runtime errors")
  local callbackApi = f:world("wild_callback_probe")
  T.eq(callbackApi:startWildBattle("MEW", 5, function() error("wild callback probe") end),
    true, "direct wild battle accepts a mod callback")
  local completed, callback = pcall(function() return f:completeBattle("win") end)
  T.eq(completed, true, "mod callback errors do not escape native battle completion")
  expectedErrors = expectedErrors + 1
  T.eq(#f.errors, expectedErrors, "mod callback failure is reported once")
  T.check(type(f.errors[1]) == "string" and f.errors[1]:match("^wild_callback_probe: ")
    and f.errors[1]:find("wild callback probe", 1, true), "wild callback error identifies its mod owner")
  if completed then callback("win") end
  T.eq(#f.errors, expectedErrors, "duplicate completion does not report the mod error twice")

  calls = 0
  T.eq(api:queueScript({ { "show_text", "cancel me" }, { "set_flag", "mod:stale" } },
    { onDone = done }), true, "session-owned script starts")
  T.eq(f.texts[#f.texts].text, "cancel me", "show_text accepts literal text")
  local cancelledText = f.texts[#f.texts]
  local late = cancelledText.onDone
  local replacement = { party = f.save.party, flags = {}, version = f.save.version }
  if generation == 3 then f.game.session = replacement else f.game.save = replacement end
  if f.field then f.field._session = replacement end
  f:update()
  T.eq(calls, 1, "session replacement cancels once")
  T.eq(succeeded, false, "session replacement reports cancellation")
  T.eq(failure, "world changed", "session cancellation has a stable reason")
  f:clearCancelledText(cancelledText)
  late()
  late()
  f:update()
  T.eq(calls, 1, "late native completions cannot repeat cancellation")
  T.eq(api:getFlag("mod:stale"), false, "stale queued rows never enter the replacement save")
  T.eq(f.hooks.chains["core.update"], nil, "cancellation retires the owned update subscription")

  calls = 0
  T.eq(api:queueScript({ { "show_text", "provider change" }, { "set_flag", "mod:old_provider" } },
    { onDone = done }), true, "provider-owned script starts")
  cancelledText = f.texts[#f.texts]
  late = cancelledText.onDone
  local providerSave = { party = { { species = generation == 3 and 16 or "PIDGEY",
    hp = 10, level = 5, moves = {} } }, flags = {} }
  local replacementGame = { data = f.game.data, save = providerSave, session = providerSave,
    stack = f.game.stack, world = f.game.world, overworld = f.game.overworld, phase = "title" }
  f.live = replacementGame
  f:update()
  T.eq(calls, 1, "provider replacement cancels queued work once")
  T.eq(succeeded, false, "provider replacement reports cancellation")
  T.eq(failure, "world changed", "provider cancellation explains the stale world")
  f:clearCancelledText(cancelledText)
  late()
  f:update()
  T.eq(calls, 1, "late completion cannot revive an old provider's script")
  T.eq(api:getFlag("mod:old_provider"), false, "provider replacement blocks stale flag writes")
  T.eq(f.hooks.chains["core.update"], nil, "provider cancellation cleans up its subscription")
  T.eq(api:party()[1].species, "PIDGEY", "held facade rereads a replaced game provider")
  if generation == 3 then
    value, reason = api:current()
    rejected(value, reason, "no overworld", "replaced provider phase")
  else
    local previous = f.ow.player.cellX
    f.ow.player.cellX = 2
    T.eq(api:current().x, 2, "held facade resolves live replacement world state")
    f.ow.player.cellX = previous
  end
  T.eq(#f.errors, expectedErrors, "native continuations add no unexpected runtime errors")
  if f.restoreField then f:restoreField() end
end

local native = { species = "MEW", hp = 20, level = 5, stats = { hp = 30 }, moves = {} }
for _, id in ipairs({ "growthRates", "tmhmMoves", "tutorMoves" }) do
  local ok, err = Records.applyMon(native, { species = id, hp = 1 }, 2,
    { pokemon = { MEW = {}, growthRates = {}, tmhmMoves = {}, tutorMoves = {} } }, "gold")
  rejected(ok, err, nil, "reserved Pokemon metadata " .. id)
  T.eq(native.species, "MEW", "reserved species rejection preserves the native ID")
  T.eq(native.hp, 20, "reserved species rejection is atomic")
end

local data = Sdk.gen3Data()
native = { species = 151, item = 13, hp = 20, level = 5, maxHp = 30,
  moves = { 1 }, pp = { 30 } }
local view = Records.mon(native, 3, data, "firered")
T.eq(view.species, "MEW", "numeric Gen 3 species reads canonically")
T.eq(view.item, "POTION", "numeric Gen 3 item reads canonically")
T.eq(view.moves[1].id, "POUND", "numeric Gen 3 move reads canonically")
T.eq(Records.applyMon(native, view, 3, data, "firered"), true, "unchanged canonical record round trips")
T.eq(native.species, 151, "round trip preserves numeric species representation")
T.eq(native.item, 13, "round trip preserves numeric item representation")
T.eq(native.moves[1], 1, "round trip preserves numeric move representation")
T.eq(Records.applyMon(native, { species = "PIDGEY", item = "POKE_BALL",
  moves = { { id = "SURF", pp = 15, maxPp = 15 } } }, 3, data, "firered"), true,
  "canonical writes convert all three Gen 3 ID kinds")
T.eq(native.species, 16, "species write resolves to numeric native ID")
T.eq(native.item, 4, "item write resolves to numeric native ID")
T.eq(native.moves[1], 57, "move write resolves to numeric native ID")
view = Records.mon(native, 3, data, "firered")
T.eq(view.species, "PIDGEY", "changed species reads back canonically")
T.eq(view.item, "POKE_BALL", "changed item reads back canonically")
T.eq(view.moves[1].id, "SURF", "changed move reads back canonically")

TextBox.new = oldTextBoxNew
Gen3Compat.endSession()
for name, saved in pairs(savedModules) do package.loaded[name] = saved[1] end
Runtime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish()
