package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified scripts")
local Sdk = require("tests.modkit.sdk")
local Fixtures = require("tests.modkit.fixtures")
local Merge = require("src.mods.Merge")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local Events = require("src.mods.Events")
local Version = require("src.core.GameVersion")
local UnifiedWorld = require("src.mods.UnifiedWorld")
local ScriptRunner = require("src.script.ScriptRunner")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")
local ChoiceBox = require("src.ui.ChoiceBox")
local Bag = require("src.inventory.Bag")
local Compat = require("src.mods.Gen3Compat")
local savedVersion = Version.get()
local savedRuntime = { Runtime.events, Runtime.hooks, Runtime.errors }
local savedModules = {}
local function install(name, value)
  if not savedModules[name] then savedModules[name] = { package.loaded[name] } end
  package.loaded[name] = value
end

local nativeMapCatalog = require("src.import.gba.map_catalog")
install("src.import.gba.map_catalog", setmetatable({ groupNumFor = function() return 1, 1 end }, { __index = nativeMapCatalog }))
install("src.ui.game3.rs.font_faces", { load = function(_, name, language, _, _, _, textMode)
  local widths, quads = {}, {}
  for glyph = 0, 511 do
    widths[glyph] = textMode == 1 and 8 or 6
    quads[glyph] = love.graphics.newQuad(glyph % 16 * 16,
      math.floor(glyph / 16) * 16, widths[glyph], 16, 256, 512)
  end
  return { name = name, language = language, nativeIndexed = true,
    fg = love.graphics.newCanvas(256, 512), sh = love.graphics.newCanvas(256, 512),
    widths = widths, quads = quads, boundaryQuads = {}, glyphs = 512,
    height = 16, pitch = 16, letterSpacing = 0 }
end })

local Field = require("src.core.game3.field")
local Player3 = require("src.core.game3.player")
local Objects = require("src.core.game3.objects")
local Collision3 = require("src.core.game3.collision")
local Message = require("src.ui.game3.message")
local Choice = require("src.ui.game3.choice")
local Bag3 = require("src.core.game3.bag")
local Items3 = require("src.core.game3.items_data")
local FrlgFont = require("src.ui.game3.frlg_font")
local Naming = require("src.ui.game3.naming")
local NativeStack = require("src.ui.game3.stack")
local NativeVersions = require("src.import.gba.versions")
local NativeMenus = require("tests.fixture_data.game3_native_menus")
local CacheBlob = require("src.import.CacheBlob")
local Pokemon3 = require("src.core.game3.pokemon")
local savedNativeVersion = NativeVersions.active()
local savedPokemon = {}
for key, value in pairs(Pokemon3) do
  if key:sub(1, 1) == "_" and type(Pokemon3[key]) ~= "function" and key ~= "_reloadHooks" then savedPokemon[key] = value end
end
local assetVersion
local nativeCache = require("src.core.game3.dataset").cache()
local originalCacheRead = nativeCache.read
nativeCache.read = function(self, path, ...)
  if path:match("/trainers/back_anims%.lua$") then return "return { [0] = { idle = { {0, 1} } }, [1] = { idle = { {0, 1} } } }" end
  if path:match("/pokemon/battle_moves%.lua$") then
    return "return { moves = { [1] = {effect=0,power=40,type=0,accuracy=100,pp=35}, [10] = {effect=0,power=40,type=0,accuracy=100,pp=35}, [33] = {effect=0,power=35,type=0,accuracy=95,pp=35}, [52] = {effect=0,power=40,type=10,accuracy=100,pp=25} } }"
  end
  return (assetVersion and NativeMenus.bytes(assetVersion, path)) or originalCacheRead(self, path, ...)
end
local savedRead, savedInfo, savedLoad = love.filesystem.read,
  love.filesystem.getInfo, love.filesystem.load
love.filesystem.read = function(path, ...)
  local bytes = assetVersion and NativeMenus.bytes(assetVersion, path)
  if bytes ~= nil then return CacheBlob.encode(path, bytes) end
  return savedRead(path, ...)
end
love.filesystem.getInfo = function(path, ...)
  local bytes = assetVersion and NativeMenus.bytes(assetVersion, path)
  if bytes ~= nil then return { type = "file", size = #bytes } end
  return savedInfo(path, ...)
end
love.filesystem.load = function(path, ...)
  local bytes = assetVersion and NativeMenus.bytes(assetVersion, path)
  if bytes ~= nil then return (loadstring or load)(bytes, "@" .. path) end
  return savedLoad(path, ...)
end

local files = {}
for _, owner in ipairs({ "script_probe", "other_probe" }) do
  files["mods/" .. owner .. "/manifest.json"] = ('{"id":"%s","name":"Script probe",'
    .. '"version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}'):format(owner)
  files["mods/" .. owner .. "/main.lua"] = [[
    local mod = ...
    mod.exports.world = mod.world
    mod.exports.queue = function(rows, opts) return mod.world:queueScript(rows, opts) end
    if mod.id == "script_probe" then
      assert(mod.content.text:register("_PortableScriptText", "Portable {PLAYER}!"))
      mod.commands:register("probe_context", function(ctx)
        local bucket = ctx.save.modData[mod.id]
        bucket.context = {
          owner = ctx.source.modId, map = ctx.mapId or ctx.source.mapId,
          sameSave = ctx.save == (mod.generation == 3 and ctx.game.session or ctx.game.save),
          sameWorld = ctx.overworld ~= nil, check = ctx.lastCheck,
          choice = ctx.lastChoice,
        }
        bucket.calls = (bucket.calls or 0) + 1
      end)
      mod.commands:register("probe_yield", function(ctx, frames)
        local bucket = ctx.save.modData[mod.id]
        bucket.beforeYield = (bucket.beforeYield or 0) + 1
        ctx.runner.waitingFrames = frames
        ctx.runner:yield()
        bucket.afterYield = (bucket.afterYield or 0) + 1
      end)
      mod.commands:register("probe_pending", function(ctx)
        local bucket = ctx.save.modData[mod.id]
        bucket.pending = { auto = ctx.pendingTextAuto, opts = ctx.textOpts }
      end)
      mod.commands:register("probe_loop", function(ctx)
        local bucket = ctx.save.modData[mod.id]
        bucket.loops = (bucket.loops or 0) + 1
        if bucket.loops == 3 then return "end" end
      end)
    end
  ]]
end

local function mapDef(id)
  local layout = { width = 8, height = 8, pair = "script_probe" }
  function layout:elevAt() return 3 end
  function layout:collAt() return 0 end
  function layout:midAt() return 0 end
  function layout:collArray()
    local cells = {}
    for i = 1, 64 do cells[i] = 0 end
    return cells
  end
  local blocks = {}
  for i = 1, 64 do blocks[i] = 0 end
  return { id = id, index = 0, label = id, width = 8, height = 8,
    tileset = "SCRIPT_OUT", environment = "TOWN", type = 1,
    blocks = blocks, midLayout = layout, pair = layout.pair,
    warps = {}, objects = {}, connections = {} }
end

local function fixture(version)
  Version.set(version)
  local generation = Version.generation()
  local f = { generation = generation, version = version, pressed = {}, pushes = 0 }
  local data = generation == 3 and Sdk.gen3Data() or Fixtures.fresh()
  setmetatable(data, { __index = require("src.core.Data") })
  data.maps = { SCRIPT_HOME = mapDef("SCRIPT_HOME"), SCRIPT_AWAY = mapDef("SCRIPT_AWAY") }
  data.text = generation == 1 and dofile("tests/fixture_data/text.lua") or {}
  data.text_pointers = {}
  data.items = data.items or {}
  f.potionId = generation == 2 and 18 or generation == 3 and 13 or 20
  data.items.POTION = { name = "POTION", index = f.potionId, price = 300,
    pocket = generation == 2 and "ITEM" or nil }
  data.items.ANTIDOTE = { name = "ANTIDOTE", index = 9, price = 100,
    pocket = generation == 2 and "ITEM" or nil }
  data.audio = { sfx = {}, songs = {} }
  data.constants = data.constants or {}
  local save = { version = version, map = "SCRIPT_HOME", money = 100, coins = 25,
    player = { name = "RED", money = 100, coins = 25 }, rival = { name = "BLUE" },
    party = {}, flags = {}, vars = {}, inventory = {}, options = {},
    pokedex = { seen = {}, owned = {} }, dex = { seen = {}, owned = {} }, modData = {} }
  local game = { data = data, save = save, phase = "field" }
  local stack = { states = {} }
  function stack:top() return self.states[#self.states] end
  function stack:push(state) self.states[#self.states + 1] = state; f.pushes = f.pushes + 1 end
  function stack:pop() return table.remove(self.states) end
  game.stack = stack
  game.input = { wasPressed = function(_, key) return f.pressed[key] == true end,
    isDown = function(_, key) return f.pressed[key] == true end }
  game.renderer = { worldViewSize = function() return 160, 144 end }
  f.game, f.save, f.live, f.stack = game, save, game, stack
  if generation < 3 then
    local world = { game = game, isOverworld = true, maps = data.maps,
      npcs = {}, ghosts = {}, entities = {}, scriptMoves = {}, npcPool = {}, tilesets = {} }
    if generation == 1 then
      setmetatable(world, { __index = require("src.world.OverworldController") })
      world.map = require("src.world.Map").new(data.maps.SCRIPT_HOME, { walkable = {}, blocks = {} })
      data.field = data.field or {}
      data.field.playerSprites = { walk = "SCRIPT_PLAYER" }
      data.sprites = data.sprites or {}
      data.sprites.SCRIPT_PLAYER = { image = "fixture_player.png", frames = 6, walker = true }
      world.player = require("src.world.Player").new(data, 2, 3, "right")
      world.runner = ScriptRunner.new(game, world)
      world.camera = require("src.render.Camera").new()
      game.overworld, stack.states[1] = world, world
      require("src.world.OverworldController")._setGameForTest(game)
    else
      setmetatable(world, require("src.world.gen2.World"))
      world.map = require("src.world.gen2.Map").new(data.maps.SCRIPT_HOME, { collision = {}, blocks = {} })
      world.player = require("src.world.gen2.Player").new(2, 3, "right")
      game.world = world
      save.money, save.coins = 777, 888
    end
    f.ow, f.player = world, world.player
  else
    NativeVersions.select(version)
    assetVersion = version
    for key in pairs(Pokemon3) do
      if key:sub(1, 1) == "_" and type(Pokemon3[key]) ~= "function" and key ~= "_reloadHooks" then Pokemon3[key] = nil end
    end
    for key, value in pairs(data.gen3Pokemon) do Pokemon3[key] = value end
    Pokemon3._national = { toNational = { [4] = 4, [5] = 5, [16] = 16, [151] = 151 },
      toSpecies = { [4] = 4, [5] = 5, [16] = 16, [151] = 151 } }
    Pokemon3._battleMoves, Pokemon3._tmhm = data.gen3Moves._rom, {}
    Pokemon3._icons, Pokemon3._front = {}, {}
    Pokemon3._byName = { CHARMANDER = 4, CHARMELEON = 5, PIDGEY = 16,
      MEW = 151 }
    Naming.dismiss()
    NativeStack.clear()
    require("src.ui.game3.naming_chrome").install()
    game.session = save
    game.save = { money = 777, inventory = {}, flags = {}, modData = {}, party = {} }
    f.hostSave = Merge.deepCopy(game.save)
    local map = { current = "SCRIPT_HOME", world = {} }
    function map.currentDef() return data.maps[map.current] end
    f.map = map
    local space = { active = true, mapId = map.current, store = { flags = {}, vars = {} },
      bundle = { events = { SCRIPT_HOME = { objects = {} }, SCRIPT_AWAY = { objects = {} } },
        text = { gText_Yes = { { t = "text", s = "YES" } },
          gText_No = { { t = "text", s = "NO" } } } },
      vm = { isRunning = function() return false end, tick = function() end },
      runOnFrame = function() end }
    function space.ensureBundle() return space.bundle end
    install("src.core.game3.scripting.space", space)
    install("src.core.game3.map", map)
    install("src.core.game3.runtime", { getSession = function() return f.live and f.live.session end,
      uiBusy = function() return Message.isOpen() or Choice.isOpen() or Naming.isOpen() end })
    f.space = space
    Field.running, Field._game, Field._session = true, game, save
    Field._locks, Field._modScriptLock = {}, nil
    Player3.cellX, Player3.cellY, Player3.facing = 2, 3, "right"
    Player3.targetX, Player3.targetY = 2, 3
    Player3.moving, Player3.surfing, Player3.boulderPush = false, false, nil
    f.player = Player3
    Objects.reset()
    Collision3.bindMap(game, map.current, data.maps[map.current])
    Objects.loadMap(game, map.current, data.maps[map.current])
    Items3.applyProfile(version)
    for id = 20, 90 do
      data.gen3Items._byId[id] = { name = "FIXTURE " .. id, pocket = "ITEMS", price = 1 }
    end
    Items3.installPack({ items = data.gen3Items._byId })
    save.bag = Bag3.new()
    FrlgFont.invalidate()
    Message.close()
    Choice.reset()
  end
  local run = Sdk.loadMods({ "mods/script_probe", "mods/other_probe" },
    { generation = generation, data = data, fs = Sdk.memfs(files) })
  run.loader.game = game
  f.run, f.hooks, f.events = run, run.loader.hooks, run.loader.events
  f.api = run.loader.exports.script_probe.world
  f.other = run.loader.exports.other_probe.world
  T.eq(#run.errors, 0, version .. " loads both real API 3 mods")
  Compat.bind(function() return f.live end)
  function f:provider(value) self.live, self.run.loader.game = value, value end
  function f:queue(rows, opts) return self.run.loader.exports.script_probe.queue(rows, opts) end
  function f:bucket() return self.save.modData.script_probe or {} end
  function f:money()
    return generation == 2 and self.ow:money() or self.save.money
  end
  function f:coins()
    return generation == 2 and self.ow:coins() or self.save.coins
  end
  function f:count()
    return generation == 3 and Bag3.get(self.save.bag, 13) or (self.save.inventory.POTION or 0)
  end
  function f:lock()
    if generation == 3 then return Field._modScriptLock end
    return self.ow._modScriptLock
  end
  function f:update(action)
    local n, a, b, c
    local function capture(...) n = select("#", ...); a, b, c = ... end
    capture(self.hooks:call("core.update", function(owner, dt)
      T.eq(owner, self.game, version .. " update retains the game")
      if action then action() end
      if generation == 1 then self.ow.runner:update() end
      return "updated", nil, dt
    end, self.game, 0.25))
    T.eq(n, 3, version .. " update preserves return arity")
    T.eq(a, "updated", version .. " update preserves first return")
    T.eq(b, nil, version .. " update preserves nil holes")
    T.eq(c, 0.25, version .. " update preserves trailing return")
  end
  function f:pump(n) for _ = 1, n or 8 do self:update() end end
  function f:drain()
    for _ = 1, 128 do
      if not self:lock() then break end
      self:update()
    end
    T.eq(self:lock(), nil, version .. " script completes within bounded updates")
  end
  function f:nativeUpdate()
    if generation == 1 then self.ow:update(1 / 60)
    elseif generation == 2 then self.ow:stepBody()
    else Field.update(1 / 60) end
  end
  function f:uiOpen()
    if generation == 3 then return Message.isOpen() or Choice.isOpen() end
    return self.stack:top() ~= (generation == 1 and self.ow or nil)
  end
  function f:text()
    if generation == 3 then return Message.currentPage() end
    local box = self.stack:top()
    local lines = {}
    for _, page in ipairs(box.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    return table.concat(lines, " ")
  end
  function f:revealChoice()
    if generation ~= 3 then return end
    for _ = 1, 600 do
      if Choice.isOpen() or not Message.isOpen() then break end
      Message.skipReveal()
      Message.tick()
      self:update()
      if not Choice.isOpen() and Message.isWaiting()
          and Message._pages and Message._page < #Message._pages then
        Message.advance()
      end
    end
    T.eq(Choice.isOpen(), true, version .. " revealed prompt opens native choice")
    T.eq(Choice.kind, "yesno", version .. " ask opens the native yes/no choice")
    T.eq(Message.isOpen(), true, version .. " prompt stays open until the choice is answered")
  end
  function f:completeUI(index)
    local late
    for tick = 1, 600 do
      if not self:uiOpen() then break end
      if generation == 3 then
        if Choice.isOpen() then
          local cb, value = Choice.done, Choice.kind == "yesno" and index == 1 or index - 1
          if Choice.kind == "yesno" then value = index == 1 end
          late = function() cb(value) end
          Choice.autoPick(value)
        else
          Message.skipReveal()
          local cb = Message._done
          if cb then late = cb end
          Message.advance()
          Message.tick()
        end
      else
        local top = self.stack:top()
        if getmetatable(top) == Menu then
          top.index = index
          local cb = top.items[index].onSelect
          late = cb
        elseif getmetatable(top) == ChoiceBox then
          top.index = index
          local cb = top.onChoose
          late = function() cb(index == 1) end
        elseif getmetatable(top) == TextBox and top.onDone then late = top.onDone end
        self.pressed = tick % 2 == 0 and { a = true } or {}
        top:update(1 / 60)
      end
    end
    self.pressed = {}
    T.eq(self:uiOpen(), false, version .. " native UI completes")
    return late
  end
  function f:finish()
    UnifiedWorld.cancel(self.api, "fixture finished")
    UnifiedWorld.cancel(self.other, "fixture finished")
    if generation == 3 then
      Naming.dismiss(); NativeStack.clear()
      require("src.core.game3.audio").stopCry()
      Message.close(); Choice.reset(); Objects.reset()
      Field.running, Field._game, Field._session = false, nil, nil
      Field._locks, Field._modScriptLock = {}, nil
      Compat.endSession()
    end
    self.run.release()
  end
  return f
end

local function scenario(f)
  local version = f.version
  local started, ended, dispatched = 0, 0, {}
  local stopStart = f.events:on("script.started", function(payload)
    if payload.ctx.source.modId == "script_probe" then started = started + 1 end
  end)
  local stopEnd = f.events:on("script.ended", function(payload)
    if payload.ctx.source.modId == "script_probe" then ended = ended + 1 end
  end)
  local stopCommand = f.hooks:wrap("script.command", function(nextFn, ctx, verb, args)
    T.eq(ctx.source.modId, "script_probe", version .. " command retains ownership")
    dispatched[verb] = (dispatched[verb] or 0) + 1
    return nextFn(ctx, verb, args)
  end, 0, "observer")

  local rows = {
    { "set_field", "mod:ready", true }, { "check_flag", "mod:ready" },
    { "jump_if_false", "bad" }, { "give_money", 40 }, { "take_money", 13 },
    { "take_coins", 7 }, { "check_money", 127 }, { "jump_if_true", "gift" },
    { "label", "bad" }, { "set_field", "mod:wrongBranch", true }, { "jump", "end" },
    { "label", "gift" }, { "give_item", "POTION", 3, false },
    { "take_item", "POTION", 1 }, { "check_item", "POTION" },
    { "jump_if_false", "bad" }, { "set_option", "textSpeed", "FAST" },
    { "set_flag", "mod:public" }, { "wait", 2 }, { "probe_context" },
    { "end" }, { "set_field", "mod:pastEnd", true },
  }
  local pristine = Merge.deepCopy(rows)
  local done = 0
  T.eq(f:queue(rows, { onDone = function() done = done + 1 end }), true,
    version .. " accepts the inherited row vocabulary")
  f:drain()
  T.eq(f:money(), 127, version .. " writes the authoritative native wallet")
  T.eq(f:coins(), 18, version .. " writes the authoritative native coin balance")
  T.eq(f:count(), 2, version .. " give and take change the native bag")
  T.eq(f:bucket().ready, true, version .. " set_field uses the owning mod bucket")
  T.eq(f:bucket().wrongBranch, nil, version .. " skipped branch has no effects")
  T.eq(f:bucket().pastEnd, nil, version .. " end halts execution")
  T.eq(f.save.options.textSpeed, "FAST", version .. " option reaches the native save")
  T.eq(f:bucket().worldFlags.public, true, version .. " public flags keep their world bucket")
  T.eq(f:bucket().worldFlags.ready, nil, version .. " private fields do not become world flags")
  T.same(f.save.flags, {}, version .. " mod fields never enter native flag storage")
  T.eq(f.other:getFlag("mod:public"), false, version .. " another owner cannot read the flag")
  T.same(f:bucket().context, { owner = "script_probe", map = "SCRIPT_HOME",
    sameSave = true, sameWorld = true, check = true }, version .. " custom command receives native context")
  T.eq(f:bucket().calls, 1, version .. " custom registry command runs once")
  T.eq(done, 1, version .. " native completion runs once")
  T.eq(started, 1, version .. " script started emits once")
  T.eq(ended, 1, version .. " script ended emits once")
  T.eq(dispatched.give_money, 1, version .. " command hook wraps actual dispatch once")
  T.same(rows, pristine, version .. " execution leaves submitted rows untouched")
  T.eq(f:lock(), nil, version .. " completion releases input ownership")
  if f.generation == 2 then
    T.eq(f.save.money, 777, version .. " never writes the Gen 1 wallet alias")
    T.eq(f.save.coins, 888, version .. " never writes the Gen 1 coin alias")
  elseif f.generation == 3 then
    T.same(f.game.save, f.hostSave, version .. " never writes the host save")
  end

  for _, tail in ipairs({ { { "unknown_script_probe" } },
      { { "jump", "missing" } },
      { { "label", "duplicate" }, { "label", "duplicate" } },
      { { "jump", 0 } }, { { "give_item", "NO_SUCH_ITEM", 1 } },
      { { "wait", -1 } } }) do
    local invalid = { { "give_money", 100 }, { "probe_context" },
      { "give_item", "POTION", 1 }, { "set_field", "mod:partial", true } }
    for _, row in ipairs(tail) do invalid[#invalid + 1] = row end
    local before, input = Merge.deepCopy(f.save), Merge.deepCopy(invalid)
    local beforeStart, beforeEnd, beforePush = started, ended, f.pushes
    local value, reason = f:queue(invalid)
    T.eq(value, nil, version .. " rejects invalid later rows")
    T.check(type(reason) == "string" and #reason > 0, version .. " preflight explains refusal")
    T.same(f.save, before, version .. " whole-list preflight is pure")
    T.same(invalid, input, version .. " preflight does not rewrite rows")
    T.eq(started, beforeStart, version .. " refused scripts never start")
    T.eq(ended, beforeEnd, version .. " refused scripts never end")
    T.eq(f.pushes, beforePush, version .. " preflight never opens UI")
    T.eq(f:lock(), nil, version .. " preflight never claims input")
  end

  T.eq(f:queue({ { "jump", 3 }, { "give_money", 1000 },
    { "label", "loop" }, { "probe_loop" }, { "jump", "loop" } }), true,
    version .. " accepts numeric and named control flow")
  f:drain()
  T.eq(f:bucket().loops, 3, version .. " custom return labels and bounded loops execute")
  T.eq(f:money(), 127, version .. " numeric jump skips wallet effects")
  T.eq(f:queue({ { "take_item", f.potionId, 1 } }), true,
    version .. " accepts native numeric item IDs")
  f:drain()
  T.eq(f:count(), 1, version .. " numeric removal reaches native inventory")

  T.eq(f:queue({ { "probe_yield", 3 }, { "set_field", "mod:afterWait", true } }), true,
    version .. " starts a yielding registry command")
  local token = f:lock()
  T.check(token ~= nil, version .. " custom yield owns native input")
  T.eq(f:bucket().afterYield, nil, version .. " custom yield suspends its coroutine")
  local otherValue = f.other:queueScript({ { "give_money", 1 } })
  T.eq(otherValue, nil, version .. " another owner cannot run over a suspended script")
  local mutation = f.api:replaceBlock(1, 0)
  T.eq(mutation, nil, version .. " ordinary world mutations respect the script lock")
  f.pressed = { start = true, right = true, a = true }
  if f.generation == 2 then
    T.eq(f.ow:acceptsMenuInput(), false, version .. " native menu gate blocks custom yield")
    T.eq(f.ow:scriptRunning(), true, version .. " native housekeeping sees the portable script")
  elseif f.generation == 3 then
    T.eq(Field.isLocked(), true, version .. " native field lock blocks custom yield")
  end
  local beforePush = f.pushes
  f:nativeUpdate()
  f.pressed = {}
  T.eq(f.player.cellX, 2, version .. " native update blocks held player movement")
  T.eq(f.pushes, beforePush, version .. " native update blocks held menu and interaction")
  f:pump(8)
  T.eq(f:bucket().beforeYield, 1, version .. " yielding custom handler enters once")
  T.eq(f:bucket().afterYield, 1, version .. " yielding custom handler resumes once")
  T.eq(f:bucket().afterWait, true, version .. " execution continues after custom yield")

  T.eq(f:queue({ { "wait_flag", "mod:signal", 2 }, { "jump_if_true", "end" },
    { "set_field", "mod:timedOut", true } }), true, version .. " starts a flag timeout")
  f:pump(6)
  T.eq(f:bucket().timedOut, true, version .. " timeout resumes with false")
  T.eq(f:queue({ { "wait_flag", "mod:signal", 8 }, { "jump_if_false", "end" },
    { "set_field", "mod:signalled", true } }), true, version .. " starts a flag wait")
  f:pump(2)
  T.eq(f:bucket().signalled, nil, version .. " unset private flag keeps waiting")
  f:bucket().signal = true
  f:pump(4)
  T.eq(f:bucket().signalled, true, version .. " native private flag releases the wait")

  T.eq(f:queue({ { "show_text", "_PortableScriptText", { PLAYER = "SCOUT" } },
    { "set_field", "mod:textDone", true } }), true, version .. " starts inherited show_text")
  f:pump(2)
  T.check(f:text():find("SCOUT", 1, true) ~= nil, version .. " show_text substitutes native text")
  T.eq(f:bucket().textDone, nil, version .. " text suspends its following rows")
  f:completeUI(1)
  f:pump(4)
  T.eq(f:bucket().textDone, true, version .. " closing native text releases its continuation")

  local choices = {
    { "ask", "Hello {RAM:wNameBuffer}!", { RAM = "SCOUT" } },
    { "jump_if_false", "end" }, { "set_field", "mod:answered", true },
    { "choice", { "FIRST", "SECOND" }, { default = 2, cancel = 2 } },
    { "probe_context" }, { "set_field", "mod:chosen", true },
  }
  T.eq(f:queue(choices), true, version .. " starts native asynchronous choices")
  f:pump(2)
  T.check(f:text():find("SCOUT", 1, true) ~= nil, version .. " native prompt substitutes text")
  T.eq(f:bucket().answered, nil, version .. " ask waits for native choice input")
  f:revealChoice()
  f:update(function()
    f:completeUI(1)
    T.eq(f:bucket().answered, nil, version .. " choice callback cannot advance inside native update")
  end)
  f:pump(2)
  T.eq(f:bucket().answered, true, version .. " yes takes the true branch")
  T.eq(f:bucket().chosen, nil, version .. " multi-choice remains asynchronous")
  local late = f:completeUI(2)
  f:pump(4)
  T.eq(f:bucket().chosen, true, version .. " native multi-choice resumes execution")
  T.same(f:bucket().context.choice, { index = 2, label = "SECOND" },
    version .. " choice preserves the Gen 1 context shape")
  T.eq(f:bucket().context.check, false, version .. " second choice stores false")
  if late then late() end
  f:pump(2)
  T.eq(dispatched.ask, 1, version .. " ask dispatches only once")
  T.eq(dispatched.choice, 1, version .. " stale completion cannot open another menu")
  T.eq(f:bucket().calls, 2, version .. " stale completion cannot repeat custom commands")

  if f.generation == 3 then
    Bag3.clear(f.save.bag)
    for id = 20, 19 + Items3.CAPACITY.ITEMS do
      T.eq(Bag3.add(f.save.bag, id, 1), true, version .. " fills a native item slot")
    end
  else
    f.game.data.constants.bagSize = 1
    f.save.inventory, f.save.bagOrder = {}, {}
    T.eq(Bag.add(f.save, "ANTIDOTE", 1, f.game.data), true, version .. " fills the native bag")
  end
  local gift = { { "give_item", "POTION", 1 }, { "set_field", "mod:giftTaken", true } }
  T.eq(f:queue(gift), true, version .. " attempts a gift with a full native bag")
  f:pump(2)
  f:completeUI(1)
  f:pump(4)
  T.eq(f:count(), 0, version .. " full bag never creates a sidecar item")
  T.eq(f:bucket().giftTaken, nil, version .. " failed gift never burns its later marker")
  if f.generation == 3 then Bag3.remove(f.save.bag, 20, 1)
  else Bag.remove(f.save, "ANTIDOTE", 1) end
  T.eq(f:queue(gift), true, version .. " retries the unconsumed gift")
  f:pump(2)
  f:completeUI(1)
  f:pump(4)
  T.eq(f:count(), 1, version .. " freed native slot receives the retry")
  T.eq(f:bucket().giftTaken, true, version .. " successful gift reaches its marker")

  local uiCancelled = 0
  T.eq(f:queue({ { "show_text", "Owned pending text." },
    { "set_field", "mod:uiCancelledTail", true } },
    { onDone = function() uiCancelled = uiCancelled + 1 end }), true,
    version .. " opens native UI before explicit cancellation")
  f:pump(2)
  local staleText = f.generation == 3 and Message._done or f.stack:top().onDone
  local unrelatedLock = {}
  if f.generation == 3 then Field.lock(unrelatedLock) end
  T.eq(UnifiedWorld.cancel(f.api, "pending text"), true, version .. " cancels pending native UI")
  T.eq(f:uiOpen(), false, version .. " cancellation closes its owned native UI")
  T.eq(uiCancelled, 1, version .. " UI cancellation completes once immediately")
  if f.generation == 3 then
    T.eq(Field.isLocked(), true, version .. " cancellation preserves an unrelated native lock")
    Field.unlock(unrelatedLock)
    Message.show("Unrelated native text.")
  else
    f.stack:push(TextBox.new(f.game, "Unrelated native text."))
  end
  local unrelatedText = f.generation == 3 and Message.currentPage() or f.stack:top()
  if staleText then staleText() end
  f:pump(2)
  T.eq(f.generation == 3 and Message.currentPage() or f.stack:top(), unrelatedText,
    version .. " stale completion preserves another native message")
  T.eq(f:bucket().uiCancelledTail, nil, version .. " stale UI completion cannot revive the script")
  T.eq(uiCancelled, 1, version .. " stale UI completion cannot complete twice")
  if f.generation == 3 then Message.close() else f.stack:pop() end

  for _, change in ipairs({ "explicit", "provider", "save", "map", "bus", "owner", "subscription" }) do
    local oldHooks, oldEvents = f.hooks, f.events
    local unrelatedCalls, cancelled = 0, 0
    local stopUnrelated = oldHooks:wrap("core.update", function(nextFn, ...)
      unrelatedCalls = unrelatedCalls + 1
      return nextFn(...)
    end, -100, "other_probe")
    T.eq(f:queue({ { "probe_yield", 100 }, { "set_field", "mod:cancelledTail", true } },
      { onDone = function() cancelled = cancelled + 1 end }), true,
      version .. " suspends before " .. change .. " cancellation")
    local captured = f:lock()
    local beforeAfter = f:bucket().afterYield
    if change == "explicit" then
      T.eq(UnifiedWorld.cancel(f.api, "explicit"), true, version .. " explicit cancel retires work immediately")
      T.eq(f:lock(), nil, version .. " explicit cancel releases native ownership immediately")
    elseif change == "provider" then
      f:provider({ data = f.game.data, save = f.save, session = f.save, phase = "field" })
    elseif change == "save" then
      if f.generation == 3 then f.game.session = Merge.deepCopy(f.save)
      else f.game.save = Merge.deepCopy(f.save) end
    elseif change == "map" then
      if f.generation == 3 then f.map.current = "SCRIPT_AWAY" else f.ow.map.id = "SCRIPT_AWAY" end
    elseif change == "bus" then Runtime.install(Events.new(), Hooks.new(), {})
    elseif change == "owner" then oldHooks:removeOwner("script_probe")
    else
      local chain = oldHooks.chains["core.update"]
      for i = #chain, 1, -1 do
        if chain[i].owner == "script_probe" then table.remove(chain, i) end
      end
    end
    if change ~= "explicit" then
      T.eq(captured:isRunning(), false, version .. " native token detects " .. change .. " invalidation")
    end
    T.eq(f:lock(), nil, version .. " cancellation releases only the captured world")
    f:provider(f.game)
    if f.generation == 3 then f.game.session = f.save; f.map.current = "SCRIPT_HOME"
    else f.game.save = f.save; f.ow.map.id = "SCRIPT_HOME" end
    Runtime.install(oldEvents, oldHooks, f.run.errors)
    f:pump(2)
    T.eq(captured:isRunning(), false, version .. " retired token cannot revive")
    T.eq(f:bucket().afterYield, beforeAfter, version .. " cancelled custom coroutine never resumes")
    T.eq(f:bucket().cancelledTail, nil, version .. " cancellation prevents later writes")
    T.eq(cancelled, 1, version .. " cancellation notifies completion once")
    T.eq(UnifiedWorld.cancel(f.api, "again"), false, version .. " repeated cancel has no effect")
    T.eq(unrelatedCalls, 2, version .. " another owner's update handler survives")
    stopUnrelated()
    T.eq(oldHooks.chains["core.update"], nil, version .. " no continuation leaks after cancellation")
  end

  T.eq(f:queue({ { "label", "forever" }, { "jump", "forever" } }), true,
    version .. " infinite control flow yields to the scheduler budget")
  f:update()
  T.eq(UnifiedWorld.cancel(f.api, "loop"), true, version .. " bounded loop remains cancellable")
  if f.generation == 1 then
    T.eq(f:queue({ { "set_field", "mod:nativeVerb", true }, { "no_npc_face_player", true } }), true,
      version .. " retains native Gen 1 vocabulary beyond the common rows")
    f:pump()
    T.eq(f.ow.noNpcFacePlayer, true, version .. " additional Gen 1 command reaches its native runner")
  end
  T.eq(#f.run.errors, 0, version .. " inherited script paths report no runtime errors")
  stopStart(); stopEnd(); stopCommand()
end

local function outdoorScenario(f)
  T.eq(f:queue({ { "remember_outdoor", "SCRIPT_AWAY", 1, 2 } }), true,
    f.version .. " accepts inherited outdoor return coordinates")
  f:drain()
  T.same(f.save.lastOutdoor, { id = "SCRIPT_AWAY", x = 1, y = 2 },
    f.version .. " keeps the Gen1 outdoor return record")
  if f.generation == 2 then
    local oldEnvironment = f.ow.map.def.environment
    f.ow.map.def.environment = "CAVE"
    local mapId, point = f.ow:escapeRopeTarget()
    T.eq(mapId, "SCRIPT_AWAY", f.version .. " actual native escape uses the remembered map")
    T.same(point and { x = point.x, y = point.y }, { x = 1, y = 2 },
      f.version .. " actual native escape uses the remembered coordinates")
    f.ow.map.def.environment = oldEnvironment
  end
end

local function martScenario(f)
  if f.generation ~= 1 then return end
  local version, data = f.version, f.game.data
  data.text_pointers.SCRIPT_HOME = { TEXT_SCRIPT_MART = { mart = { "POTION" } },
    TEXT_NOT_MART = { label = "ordinary dialogue" } }
  T.eq(data.marts, nil, version .. " first mart has no substitute mart registry")
  T.same(data:textEntry("SCRIPT_HOME", "TEXT_SCRIPT_MART").mart, { "POTION" },
    version .. " real textEntry resolves the first native mart")
  for _, id in ipairs({ "TEXT_MISSING_MART", "TEXT_NOT_MART" }) do
    local before, pushes = Merge.deepCopy(f.save), f.pushes
    local ok, reason = f:queue({ { "give_money", 99 }, { "open_mart", id } })
    T.eq(ok, nil, version .. " refuses unresolved native mart content")
    T.check(type(reason) == "string" and #reason > 0, version .. " missing mart explains refusal")
    T.same(f.save, before, version .. " invalid later mart has no earlier effects")
    T.eq(f.pushes, pushes, version .. " mart preflight opens no native UI")
    T.eq(f:lock(), nil, version .. " refused mart claims no input")
  end
  local done = 0
  T.eq(f:queue({ { "open_mart", "TEXT_SCRIPT_MART" },
    { "set_field", "mod:martDone", true } },
    { onDone = function() done = done + 1 end }), true,
    version .. " accepts a first textEntry-based native mart")
  f:pump(2)
  T.check(f:uiOpen(), version .. " opens the real ShopMenu")
  T.eq(f:bucket().martDone, nil, version .. " mart waits for native quit")
  local late = f:completeUI(3)
  f:drain()
  T.eq(f:bucket().martDone, true, version .. " native quit releases the mart continuation")
  if late then late() end
  f:pump(2)
  T.eq(done, 1, version .. " duplicate mart completion cannot finish twice")
  T.eq(f:uiOpen(), false, version .. " completed mart leaves no UI")
end

local function giftTextScenario(f)
  if f.generation == 1 then return end
  local version = f.version
  local data = f.game.data
  local shown
  if f.generation == 2 then
    data.pokemon = data.pokemon or {}
    data.pokemon.CHARMANDER = data.pokemon.CHARMANDER or { name = "CHARMANDER", dex = 4,
      baseStats = { hp = 39, attack = 52, defense = 43, speed = 65, specialAttack = 60, specialDefense = 50 },
      types = { "FIRE", "FIRE" }, growthRate = "GROWTH_MEDIUM_SLOW", levelMoves = {}, catchRate = 45,
      genderRatio = 31, baseExp = 65 }
    data.text = data.text or {}
    data.text.ReceivedItemText = "{PLAYER} received\n{STRBUF}.{DONE}"
    data.text._AskGiveNicknameText = "Give a nickname to\n{STRBUF}?{DONE}"
    data.text._BallSentToPCText = "{STRBUF} was\nsent to BILL's PC.{PROMPT}"
    f.save.party = {}
    local queued, why = f:queue({ { "give_pokemon", "CHARMANDER", 5, true, true } })
    T.eq(queued, true, version .. " accepts a native gift with received text: " .. tostring(why))
    f:pump(2)
    shown = f:text()
    T.check(shown:find("received", 1, true) and shown:find("CHARMANDER", 1, true),
      version .. " gift shows the native received line: " .. tostring(shown))
    f:completeUI(1)
    f:drain()
    return
  end
  local RomText = require("src.core.game3.rom_text")
  local rse = version == "ruby" or version == "sapphire" or version == "emerald"
  local label = rse and "LittlerootTown_ProfessorBirchsLab_Text_LikeYouToHavePokemon"
    or "Text_PlayerObtainedTheMon"
  local ir = rse and {
    { t = "text", s = "Oh, yes. As thanks for rescuing me," }, { t = "para" },
    { t = "player" }, { t = "text", s = " received the " }, { t = "strvar", n = 1 },
    { t = "text", s = "!" }, { t = "eos" } } or {
    { t = "player" }, { t = "text", s = " obtained\nthe " }, { t = "strvar", n = 1 },
    { t = "text", s = "!" }, { t = "eos" } }
  RomText.overrides[label] = ir
  local text = f.space.bundle.text
  local fallback = getmetatable(text)
  setmetatable(text, nil)
  rawset(text, "Text_PlayerObtainedTheMon", nil)
  f.save.party = {}
  local Audio = require("src.core.game3.audio")
  local playFanfare, fanfareDone = Audio.playFanfare, Audio.isFanfareFinished
  Audio.playFanfare = function() return true end
  Audio.isFanfareFinished = function() return true end
  local ok, err = pcall(function()
    T.eq(f:queue({ { "give_pokemon", "CHARMANDER", 5, true, true } }), true,
      version .. " accepts a native gift with received text")
    f:pump(2)
    shown = f:text()
    T.check(shown:find("CHARMANDER", 1, true) ~= nil,
      version .. " gift shows the native received line: " .. tostring(shown))
    T.check(not rse or shown:find("Oh, yes", 1, true) == nil,
      version .. " gift drops the unrelated lead-in paragraph")
  end)
  RomText.overrides[label] = nil
  Audio.playFanfare, Audio.isFanfareFinished = playFanfare, fanfareDone
  setmetatable(text, fallback)
  T.check(ok, version .. " gift text resolves natively" .. (ok and "" or ": " .. tostring(err)))
end

local function nicknameScenario(f)
  if f.generation ~= 3 then return end
  local version = f.version
  f.game.data.text._GotMonText = "{PLAYER} received {RAM:wNameBuffer}!"
  f.game.data.text._SentToBoxText = "{BOX_MON_NICK} was sent to BOX {RAM:wNameBuffer}!"
  local text = f.space.bundle.text
  setmetatable(text, { __index = function(rows, key)
    local ir = { { t = "text", s = tostring(key) }, { t = "eos" } }
    rawset(rows, key, ir)
    return ir
  end })
  local function press(key)
    f.pressed = { [key] = true }
    Naming.handleInput(f.game.input)
    f.pressed = {}
    for _ = 1, 20 do Naming.update(1 / 60) end
  end
  local function answer(yes)
    f:pump(2)
    f:revealChoice()
    local late = Choice.done
    Choice.autoPick(yes)
    T.eq(Naming.isOpen(), false, version .. " nickname choice cannot reenter the script")
    f:pump(2)
    return late
  end
  local function finishName()
    T.eq(Naming.isOpen(), true, version .. " yes opens the real native Naming modal")
    T.eq(NativeStack.has("naming"), true, version .. " native stack owns the naming modal")
    T.eq(Naming._state.maxLen, 10, version .. " gift names use the native ten-glyph limit")
    local late = Naming._state.onDone
    press("a")
    press("start")
    press("a")
    for _ = 1, 8 do
      if not Naming.isOpen() then break end
      press("a")
    end
    T.eq(Naming.isOpen(), false, version .. " native confirm closes naming and any PC pages")
    f:pump(2)
    if f:uiOpen() then f:completeUI(1) end
    f:drain()
    return late
  end
  for _, path in ipairs({ "no", "yes", "setnick", "boxed", "boxedNo" }) do
    f.save.party, f.save.storage = {}, nil
    if path == "boxed" or path == "boxedNo" then
      for _ = 1, 6 do
        T.eq(require("src.core.game3.party").giveMon(f.save, 4, 5), true,
          version .. " fills a party with real native gifts")
      end
    end
    local calls, giftCalls = 0, 0
    local stopGift = f.events:on("pokemon.before_give", function(gift)
      giftCalls = giftCalls + 1
      if path == "setnick" then
        gift.species, gift.level, gift.nickname = "MEW", 7, "SCOUT"
      end
    end)
    f:bucket().nicknameDone = nil
    T.eq(f:queue({ { "give_pokemon", "CHARMANDER", 5, false, false },
      { "probe_context" }, { "set_field", "mod:nicknameDone", true } },
      { onDone = function() calls = calls + 1 end }), true,
      version .. " accepts the native nickname " .. path .. " path")
    local staleChoice, staleName
    if path ~= "setnick" then
      staleChoice = answer(path ~= "no" and path ~= "boxedNo")
      if path == "yes" or path == "boxed" then staleName = finishName()
      else
        T.eq(Naming.isOpen(), false, version .. " no bypasses native naming")
        if f:uiOpen() then f:completeUI(1) end
        f:drain()
      end
    else f:drain() end
    local mon = (path == "boxed" or path == "boxedNo")
      and f.save.storage.boxes[1].mons[1] or f.save.party[1]
    T.check(mon ~= nil, version .. " gift remains in its native owning record")
    if mon then
      if path == "yes" or path == "boxed" then
        T.eq(mon.nickname, "A", version .. " native input writes back to the " .. path .. " record")
      elseif path == "setnick" then
        T.eq(mon.nickname, "SCOUT", version .. " gift nickname bypasses the prompt")
        T.eq(mon.species, 151, version .. " gift callback species mutation survives")
        T.eq(mon.level, 7, version .. " gift callback level mutation survives")
      else T.eq(mon.nickname, "", version .. " declining retains the default nickname") end
    end
    T.eq(f:bucket().context.check, true, version .. " gift success survives the nickname answer")
    T.eq(f:bucket().nicknameDone, true, version .. " nickname path reaches its tail")
    local before = Merge.deepCopy(f.save)
    if staleChoice then staleChoice(true) end
    if staleName then staleName("LATE") end
    f:pump(2)
    T.same(f.save, before, version .. " stale nickname callbacks cannot mutate or repeat the tail")
    T.eq(giftCalls, 1, version .. " gift callback runs once")
    T.eq(calls, 1, version .. " nickname completion runs once")
    T.eq(Field.isLocked(), false, version .. " nickname completion releases all owned Field locks")
    T.eq(NativeStack.has("naming"), false, version .. " nickname completion leaves no stale modal")
    stopGift()
  end

  for _, change in ipairs({ "owner", "provider", "map", "session" }) do
    f.save.party, f.save.storage = {}, nil
    local done = 0
    T.eq(f:queue({ { "give_pokemon", "CHARMANDER", 5, false, false },
      { "set_field", "mod:namingCancelledTail", true } },
      { onDone = function() done = done + 1 end }), true,
      version .. " starts naming before " .. change .. " replacement")
    answer(true)
    T.eq(Naming.isOpen(), true, version .. " cancellation begins with native naming open")
    local stale, token = Naming._state.onDone, f:lock()
    local before = Merge.deepCopy(f.save)
    local unrelated = {}
    Field.lock(unrelated)
    if change == "owner" then f.hooks:removeOwner("script_probe")
    elseif change == "provider" then f:provider({ data = f.game.data, session = f.save })
    elseif change == "map" then f.map.current = "SCRIPT_AWAY"
    else f.game.session = Merge.deepCopy(f.save) end
    T.eq(token:isRunning(), false, version .. " naming detects " .. change .. " invalidation")
    T.eq(Naming.isOpen(), false, version .. " invalidation dismisses native naming")
    T.eq(NativeStack.has("naming"), false, version .. " invalidation removes the stale naming stack entry")
    T.eq(f:lock(), nil, version .. " invalidation releases script ownership")
    T.eq(Field.isLocked(), true, version .. " naming cancellation preserves unrelated Field locks")
    Field.unlock(unrelated)
    f:provider(f.game)
    f.game.session, f.map.current = f.save, "SCRIPT_HOME"
    if stale then stale("LATE") end
    f:pump(2)
    T.same(f.save, before, version .. " stale naming cannot write into a retired gift")
    T.eq(f:bucket().namingCancelledTail, nil, version .. " cancelled naming never resumes its tail")
    T.eq(done, 1, version .. " naming cancellation completes only once")
    T.eq(Field.isLocked(), false, version .. " naming cancellation leaks no Field locks")
  end
end

local function encounterScenario(f)
  if f.generation ~= 3 then return end
  local version = f.version
  local Party = require("src.core.game3.party")
  local Bridge = require("src.core.game3.battle_bridge")
  local Transition = require("src.core.game3.battle_transition")
  for _, preparation in ipairs({ "heal_party", "give_pokemon" }) do
    f.save.party = {}
    if preparation == "heal_party" then
      T.eq(Party.giveMon(f.save, 4, 5), true, version .. " creates the initially fainted native party")
      f.save.party[1].hp = 0
    end
    local row = preparation == "heal_party" and { "heal_party" }
      or { "give_pokemon", "CHARMANDER", 5, true, false }
    local invalid = { row, { "start_battle", "wild", "PIDGEY", 3 }, { "wait", -1 } }
    local before = Merge.deepCopy(f.save)
    T.eq(f:queue(invalid), nil, version .. " refuses malformed rows after a party repair and battle")
    T.same(f.save, before, version .. " malformed battle list never heals or grants a gift")
    T.eq(Bridge._finish, nil, version .. " malformed battle list starts no native encounter")
    local done = 0
    f:bucket().battleReady = nil
    T.eq(f:queue({ row, { "start_battle", "wild", "PIDGEY", 3 },
      { "set_field", "mod:battleReady", true } },
      { onDone = function() done = done + 1 end }), true,
      version .. " accepts " .. preparation .. " before battle from an ineligible party")
    f:pump(4)
    T.check(f.save.party[1] and f.save.party[1].hp > 0,
      version .. " preceding native command makes the party usable")
    T.check(Bridge._battleParty and #Bridge._battleParty > 0,
      version .. " real native bridge accepts the repaired party")
    T.eq(f:bucket().battleReady, nil, version .. " encounter suspends its script tail")
    local stale = Bridge._finish
    T.check(type(stale) == "function", version .. " native encounter owns completion")
    Transition.finish()
    T.eq(Bridge._finish, stale, version .. " real native battle initialization accepts the transition")
    T.eq(require("src.core.game3.battle").isActive(), true, version .. " native battle becomes active")
    f:update(function()
      Bridge.finishPending("win")
      T.eq(f:bucket().battleReady, nil, version .. " battle completion is deferred beyond native update")
    end)
    for _ = 1, 40 do require("src.ui.game3.fade").tick(1 / 60) end
    f:drain()
    T.eq(f:bucket().battleReady, true, version .. " native encounter completion resumes the script")
    if stale then stale("win") end
    f:pump(2)
    T.eq(done, 1, version .. " repeated native battle completion cannot finish the script twice")
    T.eq(Field.isLocked(), false, version .. " encounter completion leaves no Field locks")
    Bridge.reset()
  end
  local Audio = require("src.core.game3.audio")
  local done = 0
  T.eq(f:queue({ { "play_cry", "CHARMANDER", true },
    { "show_text", "Cry fixture." }, { "set_field", "mod:cryDone", true } },
    { onDone = function() done = done + 1 end }), true,
    version .. " accepts a native cry with a button wait")
  f:pump(2)
  for _ = 1, 600 do Message.skipReveal(); Message.tick(); if Message.isWaiting() then break end end
  f:pump(2)
  T.eq(f:bucket().cryDone, nil, version .. " cry completion gates its script tail")
  Audio.tickCry(2)
  f:pump(2)
  T.eq(f:bucket().cryDone, nil, version .. " finished cry still requires native button input")
  f.pressed = { a = true }
  f:update(function() Message.advance() end)
  f.pressed = {}
  f:drain()
  T.eq(f:bucket().cryDone, true, version .. " native button releases the completed cry")
  f:pump(2)
  T.eq(done, 1, version .. " cry continuation completes only once")
  T.eq(Field.isLocked(), false, version .. " native cry wait releases Field locks")
end

local STORY_VERBS = { "old_man_demo", "ss_anne_departs", "pikachu_make_way",
  "spawn_pikachu_follower", "rival_battle", "load_player_starter_name", "dex_rating",
  "record_hall_of_fame", "save_end_battle_text" }
local NATIVE_ONLY_VERBS = { "no_npc_face_player", "set_catch_rate",
  "set_tile_anim", "run_parallel", "pushBattle" }
local GEN1_ROWS = {
  { "dex_rating" }, { "emote", "player", "shock", 1 }, { "fade", "out" },
  { "load_player_starter_name" }, { "march_in_place", 1, true }, { "no_npc_face_player", true },
  { "old_man_demo", "win" }, { "pan_camera", 1, 0, 10 }, { "pikachu_make_way" },
  { "pushBattle", {} }, { "push_screen", "PartyMenu" }, { "record_hall_of_fame" },
  { "rival_battle", "OPP_RIVAL1", {}, {} }, { "run_parallel", { { "wait", 1 } } },
  { "save_end_battle_text", "TEXT_NONE" }, { "set_catch_rate", 1, 10 },
  { "set_tile_anim", false }, { "spawn_pikachu_follower" }, { "ss_anne_departs" },
  { "text_opts", { auto = true } }, { "trade", 1 }, { "walk_npc", "player", { "right" } },
}

local function drivePush(f, ticks)
  for _ = 1, ticks or 120 do
    local top = f.stack:top()
    if top and top ~= f.ow and top.update then top:update(1 / 60) end
    f:update()
    if not f:lock() then break end
  end
end

local function verbScenario(f)
  local version, generation = f.version, f.generation
  if generation == 1 then
    f.game.data.field = f.game.data.field or {}
    f.game.data.field.trades = { [1] = { give = "PIDGEY", get = "CHARMANDER", dialogset = 1 } }
    for _, row in ipairs(GEN1_ROWS) do
      local value, reason = f:queue({ { "end" }, row })
      T.eq(value, true, version .. " keeps Gen 1 verb " .. row[1] .. (value and "" or ": " .. tostring(reason)))
      f:drain()
    end
    T.check(select(2, f:queue({ { "push_screen", "NoSuchScreen" } })) ~= nil,
      version .. " Gen 1 push_screen still rejects unknown screens")
    T.check(select(2, f:queue({ { "trade", 99 } })) ~= nil,
      version .. " Gen 1 trade still rejects unknown trades")
    T.eq(f:queue({ { "text_opts", { auto = true } }, { "probe_pending" } }), true,
      version .. " Gen 1 runs text_opts natively")
    f:drain()
    T.same(f:bucket().pending.opts, { auto = true }, version .. " Gen 1 text_opts arms the native box")
    f.save.party = { {} }
    T.eq(f:queue({ { "set_catch_rate", 1, 77 } }), true, version .. " Gen 1 runs set_catch_rate")
    f:drain()
    T.eq(f.save.party[1].catchRate, 77, version .. " Gen 1 set_catch_rate reaches the party")
    f.save.party = {}
    T.eq(f:queue({ { "fade", "out", "white" }, { "set_field", "mod:faded", true },
      { "fade", "in", "white" } }), true, version .. " Gen 1 starts fade")
    T.check(f.ow.fadeOverlay ~= nil, version .. " Gen 1 fade installs the native overlay")
    drivePush(f, 300)
    T.eq(f:lock(), nil, version .. " Gen 1 fade completes through the native overlay")
    T.eq(f:bucket().faded, true, version .. " Gen 1 fade out resumes the script")
    T.eq(f.ow.fadeOverlay, nil, version .. " Gen 1 fade in removes the overlay")
    T.eq(f:queue({ { "pan_camera", 2, 1, 4 } }), true, version .. " Gen 1 starts pan_camera")
    T.check(f.ow.cameraPan ~= nil and f.ow.cameraPan.toX == 32, version .. " Gen 1 pan_camera reaches the overworld")
    UnifiedWorld.cancel(f.api, "pan")
    T.eq(f:queue({ { "pan_camera", "reset" } }), true, version .. " Gen 1 resets the camera")
    f:drain()
    T.eq(f.ow.cameraPan, nil, version .. " Gen 1 pan_camera reset clears the pan")
    return
  end

  for _, verb in ipairs(STORY_VERBS) do
    local before = Merge.deepCopy(f.save)
    local value, reason = f:queue({ { "give_money", 5 }, { verb, "x" } })
    T.eq(value, nil, version .. " refuses Gen 1 story verb " .. verb)
    T.eq(reason, "native content adapter unavailable: " .. verb, version .. " story verb " .. verb .. " fails clearly")
    T.same(f.save, before, version .. " refused " .. verb .. " changes nothing")
  end
  for _, verb in ipairs(NATIVE_ONLY_VERBS) do
    local value, reason = f:queue({ { verb, 1, true } })
    T.eq(value, nil, version .. " refuses verb without a native equivalent " .. verb)
    T.eq(reason, "native content adapter unavailable: " .. verb, version .. " " .. verb .. " fails clearly")
  end
  if generation == 2 then
    for _, verb in ipairs({ "pan_camera", "march_in_place" }) do
      local value, reason = f:queue({ { verb, 1, true } })
      T.eq(value, nil, version .. " refuses " .. verb .. " without a native equivalent")
      T.eq(reason, "native content adapter unavailable: " .. verb, version .. " " .. verb .. " fails clearly")
    end
  end
  for _, bad in ipairs({
      { "emote", "player", "bogus" }, { "emote", "player", 1 }, { "emote", "player", "shock", 0 },
      { "fade", "sideways" }, { "fade", "out", 12 }, { "fade", "out", "white", "x" },
      { "walk_npc", "player", { "sideways" } }, { "walk_npc", "player", {}, { stepFrames = 2 } },
      { "text_opts", { auto = true, overlap = true } }, { "text_opts", { auto = false } },
      generation == 3 and { "pan_camera", 1, 0, 30 } or { "march_in_place", 1, true },
      generation == 3 and { "pan_camera", "reset", 1 } or { "walk_npc", "player", { "up" }, { wait = 1 } },
      { "trade", 1, "FLAG" }, { "push_screen", "NoSuchScreen" }, { "march_in_place", 999, true },
    }) do
    local before = Merge.deepCopy(f.save)
    local value, reason = f:queue({ { "give_money", 5 }, bad })
    T.eq(value, nil, version .. " refuses malformed " .. bad[1])
    T.check(type(reason) == "string" and #reason > 0, version .. " malformed " .. bad[1] .. " explains refusal")
    T.same(f.save, before, version .. " malformed " .. bad[1] .. " changes nothing")
  end

  T.eq(f:queue({ { "text_opts", { auto = true } }, { "probe_pending" } }), true, version .. " runs text_opts")
  f:drain()
  T.eq(f:bucket().pending.auto, true, version .. " text_opts arms the next native box")
  T.eq(f:queue({ { "text_opts", { auto = true } }, { "show_text", "_PortableScriptText", { PLAYER = "AUTO" } },
    { "probe_pending" } }), true, version .. " runs auto text")
  f:pump(2)
  if generation == 2 then
    local top = f.stack:top()
    T.check(top.auto ~= nil and top.auto.wait == false, version .. " auto text uses the native no-wait box")
  end
  for _ = 1, 600 do
    if generation == 3 then Message.skipReveal(); Message.tick() else
      local top = f.stack:top()
      if top and top ~= f.ow and top.update then top:update(1 / 60) end
    end
    f:update()
    if not f:lock() then break end
  end
  T.eq(f:lock(), nil, version .. " auto text closes without a button")
  T.eq(f:bucket().pending.auto, nil, version .. " auto text consumes the arming")

  if generation == 2 then
    f.ow.emoteOrder = { "shock", "question", "happy" }
    f.ow.emoteImages = { shock = {}, question = {}, happy = {} }
    T.eq(f:queue({ { "emote", "player", "question", 4 }, { "set_field", "mod:emoted", true } }), true,
      version .. " starts emote")
    T.check(f.ow.emote ~= nil and f.ow.emote.image == f.ow.emoteImages.question, version .. " emote selects the native bubble")
    T.eq(f.ow.emote.left, 4, version .. " emote holds the requested frames")
    f:pump(2)
    T.eq(f:bucket().emoted, nil, version .. " emote blocks while the bubble shows")
    f.ow.emote = nil
    f:pump(2)
    T.eq(f:bucket().emoted, true, version .. " emote resumes when the bubble clears")
    T.eq(f:queue({ { "fade", "out", "white" } }), true, version .. " starts fade out")
    f:drain()
    T.eq(f.ow.fade, "white", version .. " fade out uses the native white fade")
    T.eq(f:queue({ { "fade", "in" } }), true, version .. " starts fade in")
    f:drain()
    T.eq(f.ow.fade, nil, version .. " fade in clears the native fade")
    local opened
    f.ow.openNpcTrade = function(_, id, done) opened = { id = id, done = done }; return true end
    T.eq(f:queue({ { "trade", 3 }, { "set_field", "mod:traded", true } }), true, version .. " starts trade")
    T.eq(opened and opened.id, 3, version .. " trade reaches the native trade screen")
    f:pump(2)
    T.eq(f:bucket().traded, nil, version .. " trade blocks on the native screen")
    opened.done()
    f:pump(2)
    T.eq(f:bucket().traded, true, version .. " native trade completion resumes the script")
    local Screens = require("src.ui.Screens")
    f.game.data.screens = { probe_screen = { __modOwned = true, new = function()
      return { update = function() end, draw = function() end } end } }
    Screens.invalidate()
    T.eq(f:queue({ { "push_screen", "probe_screen" }, { "set_field", "mod:screened", true } }), true,
      version .. " starts push_screen")
    local pushed = f.stack:top()
    T.check(pushed ~= nil and pushed.screenId == "probe_screen", version .. " push_screen pushes the registered screen")
    f:pump(2)
    T.eq(f:bucket().screened, nil, version .. " push_screen blocks while the screen is up")
    f.stack:pop()
    f:pump(2)
    T.eq(f:bucket().screened, true, version .. " push_screen resumes after the screen pops")
    f.game.data.screens = nil
    Screens.invalidate()
  else
    local Fade = require("src.ui.game3.fade")
    T.eq(f:queue({ { "fade", "out", "white" }, { "set_field", "mod:faded", true } }), true, version .. " starts fade out")
    T.eq(Fade.active and Fade.mode, Fade.MODE.TO_WHITE, version .. " fade out starts the native white fade")
    f:pump(2)
    T.eq(f:bucket().faded, nil, version .. " fade blocks until the native fade ends")
    for _ = 1, 40 do Fade.tick(1 / 60) end
    f:drain()
    T.eq(f:bucket().faded, true, version .. " fade resumes when the native fade ends")
    T.eq(f:queue({ { "fade", "in", "white" } }), true, version .. " starts fade in")
    T.eq(Fade.active and Fade.mode, Fade.MODE.FROM_WHITE, version .. " fade in starts the native fade-from-white")
    for _ = 1, 40 do Fade.tick(1 / 60) end
    f:drain()
    Fade.clear()
    T.eq(f:queue({ { "emote", "player", "shock", 3 }, { "set_field", "mod:emoted", true } }), true,
      version .. " starts emote")
    f:pump(2)
    for _ = 1, 20 do Objects.update(1 / 60); f:update() end
    f:drain()
    T.eq(f:bucket().emoted, true, version .. " emote resumes after the native movement action")
    T.eq(f:queue({ { "pan_camera", 1, 0 }, { "set_field", "mod:panned", true } }), true, version .. " starts pan_camera")
    local Camera = require("src.core.game3.camera_object")
    T.eq(Camera.isActive(), true, version .. " pan_camera spawns the native camera object")
    for _ = 1, 60 do Objects.update(1 / 60); f:update() end
    f:drain()
    T.eq(f:bucket().panned, true, version .. " pan_camera resumes when the camera object arrives")
    T.check(select(1, Camera.offset()) ~= 0, version .. " pan_camera moved the camera")
    T.eq(f:queue({ { "pan_camera", "reset" } }), true, version .. " resets the camera")
    f:drain()
    T.eq(Camera.isActive(), false, version .. " pan_camera reset removes the camera object")
    Camera.reset()

    local Stack3 = require("src.ui.game3.stack")
    local plain = f.game.stack
    f.game.data.screens = { probe_screen = { new = function()
      return { update = function() end, draw = function() end } end } }
    T.eq(f:queue({ { "push_screen", "probe_screen" }, { "set_field", "mod:screened", true } }), true,
      version .. " starts push_screen")
    local screen = f.game.stack:top()
    T.check(screen ~= nil and Stack3.depth() == 1, version .. " push_screen pushes the registered mod screen")
    f:pump(2)
    T.eq(f:bucket().screened, nil, version .. " push_screen blocks while the screen is up")
    f.game.stack:pop()
    f:pump(2)
    f:drain()
    T.eq(f:bucket().screened, true, version .. " push_screen resumes after the screen pops")
    T.eq(f:queue({ { "push_screen", "probe_screen" } }), true, version .. " starts a cancellable push_screen")
    UnifiedWorld.cancel(f.api, "screen")
    T.eq(f.game.stack:top(), nil, version .. " cancellation pops the owned mod screen")
    Stack3.clear()
    f.game.data.screens, f.game.stack = nil, plain

    local TradeKey, PartyKey = "src.core.game3.scripting.natives_trade", "src.ui.game3.party_menu"
    local savedTrade, savedParty = package.loaded[TradeKey], package.loaded[PartyKey]
    local menuOpts, scenes = nil, 0
    package.loaded[TradeKey] = { entry = function(id)
        return id == 1 and { requestedSpecies = 16, species = 4, personality = 1, abilityNum = 0,
          otId = 1, heldItem = 0, nickname = "X", otName = "Y" } or nil
      end,
      levelOfSlot = function() return 5 end,
      createTradeMon = function() return { species = 4, level = 5 } end,
      sceneTask = function() scenes = scenes + 1
        local n = 0
        return function() n = n + 1; return n >= 3 end
      end }
    package.loaded[PartyKey] = { show = function(_, _, opts) menuOpts = opts end,
      isOpen = function() return menuOpts ~= nil end, close = function() menuOpts = nil end }
    local value, reason = f:queue({ { "trade", 9 } })
    T.eq(value, nil, version .. " refuses an unknown native trade")
    T.check(type(reason) == "string" and #reason > 0, version .. " unknown trade explains refusal")
    f.save.party = { { species = 4, level = 5 }, { species = 16, level = 5 } }
    T.eq(f:queue({ { "trade", 1 }, { "set_field", "mod:traded", true } }), true, version .. " starts trade")
    T.check(menuOpts ~= nil, version .. " trade opens the native party menu")
    menuOpts.onSelect(1); menuOpts.onClose()
    f:pump(4)
    T.eq(scenes, 0, version .. " a wrong species never starts the trade scene")
    f:drain()
    T.eq(f:bucket().traded, true, version .. " a refused trade still continues the script")
    menuOpts = nil
    T.eq(f:queue({ { "trade", 1 }, { "jump_if_false", "end" }, { "set_field", "mod:tradedOk", true } }), true,
      version .. " starts the accepted trade")
    menuOpts.onSelect(2); menuOpts.onClose()
    f:pump(2)
    T.eq(scenes, 1, version .. " the matching species runs the native trade scene")
    T.eq(f:bucket().tradedOk, nil, version .. " trade blocks while the scene runs")
    f:pump(6)
    f:drain()
    T.eq(f:bucket().tradedOk, true, version .. " a finished native trade sets the check")
    package.loaded[TradeKey], package.loaded[PartyKey] = savedTrade, savedParty
    f.save.party = {}

    local walk = Objects.walkInPlaceType("down") or Objects.walkInPlaceType("up")
    local pool = Objects.spawnFromDefs({ { localId = 5, x = 4, y = 4, graphicsId = 18, movementType = 8 } }, nil)
    local eo = pool and pool.byId and pool.byId[5]
    if eo then Objects._byId[5] = eo; Objects._order[#Objects._order + 1] = 5 end
    if walk and eo then
      eo.facing = "down"
      local before = eo.movementType
      T.eq(f:queue({ { "march_in_place", 5, true } }), true, version .. " accepts march_in_place")
      f:drain()
      T.eq(eo.movement, "IN_PLACE", version .. " march_in_place uses the native walk-in-place movement type")
      T.eq(f:queue({ { "march_in_place", 5, false } }), true, version .. " accepts march_in_place off")
      f:drain()
      T.eq(eo.movementType, before, version .. " march_in_place off restores the movement type")
    elseif eo then
      local refused, why = f:queue({ { "march_in_place", 5, true } })
      T.eq(refused, nil, version .. " refuses march_in_place without a native walk-in-place type")
      T.eq(why, "native walk-in-place unavailable", version .. " march_in_place explains the refusal")
    else
      T.check(false, version .. " fixture spawns a native object")
    end
    Objects.reset()
  end

  T.eq(f:queue({ { "walk_npc", "player", { "right", "right" }, { wait = false } },
    { "set_field", "mod:walkStarted", true } }), true, version .. " starts walk_npc")
  f:pump(2)
  for _ = 1, 240 do f:nativeUpdate(); f:update(); if not f:lock() then break end end
  f:drain()
  T.eq(f.player.cellX, 4, version .. " walk_npc moves the player through native movement")
  T.eq(f:bucket().walkStarted, true, version .. " walk_npc wait=false lets the script continue")
  f.player.cellX = 2
  T.eq(f:queue({ { "walk_npc", "player", { "down" } }, { "set_field", "mod:walked", true } }), true,
    version .. " starts blocking walk_npc")
  f:pump(2)
  T.eq(f:bucket().walked, nil, version .. " walk_npc blocks until the movement ends")
  for _ = 1, 120 do f:nativeUpdate(); f:update() end
  f:drain()
  T.eq(f:bucket().walked, true, version .. " walk_npc resumes after native movement")
  f.save.name, f.save.rivalName = "RED", "BLUE"
  f.save.rival = { name = "BLUE" }
  T.eq(f:queue({ { "show_text", "Hi {PLAYER}, {RIVAL} sent {STR_VAR_1}." } }), true, version .. " starts placeholder text")
  f:pump(2)
  if generation == 3 then
    for _ = 1, 400 do Message.skipReveal(); Message.tick() end
  end
  local shown = f:text()
  T.check(shown:find("BLUE", 1, true) ~= nil, version .. " portable text expands the rival name: " .. shown)
  T.check(shown:find("RED", 1, true) ~= nil, version .. " portable text expands the player name: " .. shown)
  f:completeUI(1)
  f:drain()
  T.eq(#f.run.errors, 0, version .. " adapted verbs report no runtime errors")
end

for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal",
    "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  local f
  local ok, err = pcall(function()
    f = fixture(version)
    scenario(f)
    outdoorScenario(f)
    martScenario(f)
    nicknameScenario(f)
    encounterScenario(f)
    verbScenario(f)
    giftTextScenario(f)
  end)
  T.check(ok, version .. " scenario completes" .. (ok and "" or ": " .. tostring(err)))
  if f then
    local cleaned, reason = pcall(function() f:finish() end)
    T.check(cleaned, version .. " fixture cleanup completes"
      .. (cleaned and "" or ": " .. tostring(reason)))
  end
end

FrlgFont.invalidate()
Naming.dismiss()
nativeCache.read = originalCacheRead
love.filesystem.read, love.filesystem.getInfo, love.filesystem.load = savedRead, savedInfo, savedLoad
for key in pairs(Pokemon3) do
  if key:sub(1, 1) == "_" and type(Pokemon3[key]) ~= "function" and key ~= "_reloadHooks" then Pokemon3[key] = nil end
end
for key, value in pairs(savedPokemon) do Pokemon3[key] = value end
NativeVersions.select(savedNativeVersion)
for name, saved in pairs(savedModules) do package.loaded[name] = saved[1] end
Version.set(savedVersion)
Runtime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish()
