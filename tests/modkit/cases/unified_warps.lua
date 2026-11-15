package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified warps")
local Sdk = require("tests.modkit.sdk")
local Fixtures = require("tests.modkit.fixtures")
local Merge = require("src.mods.Merge")
local Version = require("src.core.GameVersion")
local ModRuntime = require("src.mods.Runtime")
local Compat = require("src.mods.Gen3Compat")
local OW = require("src.world.OverworldController")
local World2 = require("src.world.gen2.World")
local MapLoader = require("src.world.MapLoader")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Warp = require("src.core.game3.warp")
local Effects = require("src.core.game3.field_effects")
local Task = require("src.core.game3.task")
local Fade = require("src.ui.game3.fade")
local Space = require("src.core.game3.scripting.space")
local Music = require("src.core.Music")
local Audio = require("src.core.game3.audio")
local NativeVersions = require("src.import.gba.versions")
local NativeAssets = require("tests.fixture_data.game3_native_menus")
local savedVersion, savedNativeVersion = Version.get(), NativeVersions.active()
local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }

local files = {
  ["mods/warp_probe/manifest.json"] = [[{"id":"warp_probe","name":"Warp probe","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}]],
  ["mods/warp_probe/main.lua"] = [[
    local mod = ...
    mod.exports.calls = 0
    local function completed()
      mod.exports.calls = mod.exports.calls + 1
      mod.exports.arrival = mod.world:current()
      mod.exports.observeDone()
    end
    mod.exports.warp = function(mapId, arrive, keepMusic)
      return mod.world:warpTo(mapId, 2, 3, "up", {
        arrive = arrive, keepMusic = keepMusic,
        onDone = completed,
      })
    end
    mod.exports.legacy = function(mapId, arrive, keepMusic)
      local ow = require("src.world.OverworldController")
      return ow.startWarpTo(mapId, 2, 3, "up", completed,
        { arrive = arrive, keepMusic = keepMusic })
    end
    mod.exports.plain = function(mapId)
      return mod.world:warpTo(mapId, 2, 3, "up")
    end
  ]],
}

local function mapDef(id, generation, music)
  local def = Merge.deepCopy(Fixtures.load().maps.FIX_TOWN)
  def.id, def.label, def.index = id, id, music
  def.objects, def.warps, def.connections, def.signs = {}, {}, {}, {}
  def.environment, def.type, def.mapType, def.music = "TOWN", 1, 1, music
  def.showMapName, def.regionMapSectionId = 0, 0
  if generation == 3 then
    def.midLayout = { width = 10, height = 9, pair = "warp_probe" }
    function def.midLayout:midAt() return 0 end
    function def.midLayout:collAt() return 0 end
    function def.midLayout:elevAt() return 3 end
    function def.midLayout:collArray()
      local cells = {}
      for i = 1, 90 do cells[i] = 0 end
      return cells
    end
  end
  return def
end

local function fixture(version, f)
  Version.set(version)
  if Version.generation() == 2 then require("tests.fixture_data.gen2_engine_flags").bind(version) end
  local generation = Version.generation()
  f.generation, f.version = generation, version
  f.restore, f.music, f.offsets = {}, {}, {}
  f.sawFade, f.animationFrames = false, 0
  local function replace(owner, key, value)
    local old = owner[key]
    f.restore[#f.restore + 1] = function() owner[key] = old end
    owner[key] = value
  end
  f.replace = replace
  local function observe(owner, key)
    local native = owner[key]
    if type(native) ~= "function" then return end
    replace(owner, key, function(...)
      f.music[#f.music + 1] = key
      return native(...)
    end)
  end
  function f:finish()
    if generation == 3 then
      Warp.clear()
      Task.clear()
      Fade.clear()
      Effects._anims = {}
      Space.deactivate(nil)
      Compat.endSession()
    end
    if self.run then self.run.release() end
    for i = #self.restore, 1, -1 do self.restore[i]() end
    OW._setGameForTest(require("src.core.Game"))
  end
  local newCanvas = love.graphics.newCanvas
  replace(love.graphics, "newCanvas", function(...)
    local canvas = newCanvas(...)
    function canvas:renderTo(fn)
      love.graphics.push("all")
      love.graphics.setCanvas(self)
      local ok, why = pcall(fn)
      love.graphics.pop()
      if not ok then error(why, 0) end
    end
    return canvas
  end)
  local prefix = generation == 3 and require("src.core.game3.profile").active().map.enginePrefix or ""
  f.home, f.away = prefix .. "WARP_HOME", prefix .. "WARP_AWAY"
  local data = generation == 3 and Sdk.gen3Data() or Fixtures.fresh()
  setmetatable(data, { __index = require("src.core.Data") })
  data.maps = { [f.home] = mapDef(f.home, generation, 101),
    [f.away] = mapDef(f.away, generation, 102) }
  data.audio = { runtime = {}, sfx = {}, songs = {},
    mapSongs = { [f.home] = "WARP_HOME", [f.away] = "WARP_AWAY" } }
  data.field = data.field or {}
  data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER" }
  data.field.flyWarps = {}
  data.field.forcedMovement = { tiles = {} }
  data.sprites = Merge.deepCopy(Fixtures.load().sprites)
  data.gen2Icons = { species = { MEW = "ICON_WARP" },
    icons = { ICON_WARP = { image = "tests/fixture_data/assets/fix_sprite.png" } } }
  local save = { version = version, map = f.home, x = 1, y = 1, facing = "down",
    player = { name = "RED" }, flags = {}, vars = {}, engineFlags = {},
    inventory = {}, options = {}, modData = {}, visited = {},
    party = { { species = generation == 3 and 151 or "MEW", hp = 30,
      level = 10, moves = {} } } }
  local game = { data = data, save = save, phase = "field" }
  game.input = { wasPressed = function() return false end,
    isDown = function() return false end, direction = function() return nil end }
  game.renderer = { worldViewSize = function() return 160, 144 end }
  local stack = { states = {} }
  function stack:top() return self.states[#self.states] end
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  game.stack = stack
  f.game, f.save, f.live, f.stack = game, save, game, stack

  if generation == 1 then
    local world = setmetatable({ isOverworld = true, npcs = {}, ghosts = {},
      entities = {}, scriptMoves = {}, npcPool = {}, pendingScripts = {},
      parallelRunners = {}, parallelQueue = {}, npcMoveLocks = {}, marchers = {},
      wildEncounterGraceSteps = 0 }, { __index = OW })
    world.camera = require("src.render.Camera").new()
    world.runner = require("src.script.ScriptRunner").new(game, world)
    game.overworld, stack.states[1] = world, world
    replace(package.loaded, "src.core.Game", game)
    OW._setGameForTest(game)
    MapLoader.invalidate(f.home)
    MapLoader.invalidate(f.away)
    world:enter(f.home, 1, 1, "down", { keepMusic = true })
    f.world, f.player = world, world.player
  elseif generation == 2 then
    local world = World2.new(game)
    world.maps, world.tilesets = data.maps, Merge.deepCopy(Fixtures.load().tilesets)
    world.tilesets.FIX_OUT.collision = { [1] = { 0, 0, 0, 0 } }
    world.sprites, world.scripts, world.constants, world.text = data.sprites, {}, {}, {}
    game.world = world
    T.eq(world:setMap(f.home, 1, 1, "down", { keepMusic = true }), true,
      version .. " native fixture map loads")
    f.world, f.player = world, world.player
  else
    NativeVersions.select(version)
    local cache = require("src.core.game3.dataset").cache()
    local read = cache.read
    replace(cache, "read", function(self, path, ...)
      return NativeAssets.bytes(version, path) or read(self, path, ...)
    end)
    replace(Space, "bundle", { scripts = {}, text = {}, movements = {}, events = {} })
    replace(Space, "vm", nil)
    replace(Space, "active", false)
    replace(Space, "_pendingOnFrame", nil)
    replace(Runtime, "active", true)
    replace(Runtime, "session", save)
    replace(Runtime, "_game", game)
    replace(Field, "running", true)
    replace(Field, "_game", game)
    replace(Field, "_session", save)
    replace(Field, "_locks", {})
    replace(Field, "_fieldCallback", nil)
    replace(Field, "_modScriptLock", nil)
    game.session = save
    Task.clear()
    Fade.clear()
    Warp.clear()
    Effects._anims = {}
    replace(Player, "spriteXOffset", 0)
    replace(Player, "spriteYOffset", 0)
    replace(Player, "flyRide", false)
    replace(Player, "fieldMoveAnim", 0)
    replace(Player, "oamPriority", nil)
    replace(Player, "fixedPriority", nil)
    replace(Player, "subpriority", nil)
    replace(Player, "visible", true)
    replace(Player, "animDisabled", false)
    replace(Player, "spinning", false)
    replace(Player, "walkInPlace", false)
    replace(Player, "walkInPlaceFast", false)
    Map.current, Map._announced = nil, nil
    T.check(Map.load(nil, game, f.home, { x = 1, y = 1, facing = "down",
      keepMusic = true }) ~= nil, version .. " native fixture map loads")
    Field.unlock()
    f.player = Player
  end

  local run = Sdk.loadMods({ "mods/warp_probe" },
    { generation = generation, data = data, fs = Sdk.memfs(files) })
  run.loader.game = game
  f.run, f.exports = run, run.loader.exports.warp_probe
  T.eq(#run.errors, 0, version .. " real Loader accepts the same mod")
  Compat.bind(function() return f.live end)
  observe(Music, "playMap")
  observe(Music, "fadeOut")
  observe(Audio, "playMapSong")
  observe(Audio, "mapLoadMusic")
  observe(Audio, "fadeOutBgm")

  function f:busy()
    if generation == 3 then return Warp.isBusy() or Fade.isActive() or #Effects._anims > 0 end
    local world = self.world
    return world.transitioning or world.mapSetup or world.flyAnim or world.flyArrive
      or world.spinArrive or world.moveState or self.player.inputLocked
  end
  function f:animation()
    if generation == 3 then return Effects._anims[1] end
    return self.world.flyAnim or self.world.flyArrive or self.world.moveState
      or (self.player.spinFrames and self.player)
  end
  f.exports.observeDone = function()
    f.callbackMusicCount = #f.music
    f.callbackHadAnimation = f:animation() ~= nil
    f.callbackBusy = f:busy()
    f.callbackPosition = { f.player.cellX, f.player.cellY, f.player.facing }
    if generation == 3 then
      f.callbackTransitioning = Fade.isActive()
      f.callbackFieldLocked = Field.isLocked()
    else
      f.callbackTransitioning = f.world.transitioning or f.world.mapSetup
    end
    T.check(not f.callbackTransitioning, version .. " callback follows native transition completion")
    T.check(f.exports.arrival and f.exports.arrival.mapId == f.away,
      version .. " callback observes the destination map")
    T.same(f.callbackPosition, { 2, 3, "up" }, version .. " callback observes destination position")
  end
  function f:tick()
    self.run.loader.hooks:call("core.update", function()
      if generation == 1 then
        local top = stack:top()
        if top and top ~= self.world then
          self.sawFade = true
          top:update(1 / 60)
        else self.world:update(1 / 60) end
      elseif generation == 2 then
        if self.world.mapSetup then
          self.sawFade = true
          self.world:updateMapSetup()
        end
        self.world:stepFlyAnim()
        self.world:updateMovement()
        self.player:update()
      else
        if Fade.isActive() then self.sawFade = true end
        Task.update(1 / 60)
        Fade.tick(1 / 60)
        require("src.core.game3.doors").update(1 / 60)
        Effects.step()
      end
    end, game, 1 / 60)
    local anim = self:animation()
    if anim then
      self.animationFrames = self.animationFrames + 1
      local fields = {}
      for _, object in ipairs({ anim, self.player }) do
        for key, value in pairs(object) do
          if type(value) == "number" then fields[#fields + 1] = tostring(key) .. "=" .. tostring(value) end
        end
      end
      table.sort(fields)
      self.offsets[table.concat(fields, ":")] = true
    end
  end
  function f:drain()
    for _ = 1, 1200 do
      if not self:busy() then break end
      self:tick()
    end
    T.check(not self:busy(), version .. " native arrival finishes within bounded frames")
  end
  return f
end

local versions = { "red", "blue", "yellow", "gold", "silver", "crystal",
  "firered", "leafgreen", "ruby", "sapphire", "emerald" }

local function exercise(version, label, body)
  local f = {}
  local ok, err = xpcall(function()
    fixture(version, f)
    body(f)
  end, debug.traceback)
  T.check(ok, version .. " " .. label .. ": " .. tostring(err))
  if f.finish then f:finish() end
end

for _, version in ipairs(versions) do
  for _, arrive in ipairs({ "plain", "teleport", "fly" }) do
    exercise(version, arrive .. " arrival", function(f)
      local arrival = arrive ~= "plain" and arrive or nil
      T.eq(f.exports.warp(f.away, arrival, true), true, version .. " inherited options accepted")
      T.eq(f.exports.calls, 0, version .. " callback is asynchronous")
      f:drain()
      T.eq(f.exports.calls, 1, version .. " successful arrival calls back once")
      T.same({ f.player.cellX, f.player.cellY, f.player.facing }, { 2, 3, "up" },
        version .. " native arrival position and facing")
      T.check(f.exports.arrival and f.exports.arrival.mapId == f.away,
        version .. " callback observes the destination map")
      T.eq(f.callbackMusicCount, 0, version .. " keepMusic preserves BGM through transition completion")
      T.eq(f.sawFade, true, version .. " native default fade advances")
      if arrival then
        T.eq(f.callbackHadAnimation, true, version .. " Gen1 callback phase precedes landing completion")
        T.check(f.animationFrames > 1, version .. " real arrival animation advances")
        local n = 0
        for _ in pairs(f.offsets) do n = n + 1 end
        T.check(n > 1, version .. " native arrival changes animation state")
      else
        T.check(not f.callbackBusy, version .. " plain callback follows native cleanup")
        T.check(not f.callbackFieldLocked, version .. " plain callback releases owned field lock")
      end
      for _ = 1, 8 do f:tick() end
      T.eq(f.exports.calls, 1, version .. " later native frames cannot repeat callback")
      T.eq(#f.run.errors, 0, version .. " callback succeeds without swallowed errors")
    end)
  end

  if Version.generation(version) > 1 then
    for _, arrive in ipairs({ "plain", "teleport", "fly" }) do
      exercise(version, arrive .. " legacy startWarpTo completion", function(f)
        local arrival = arrive ~= "plain" and arrive or nil
        T.eq(f.exports.legacy(f.away, arrival, true), true, version .. " legacy warp accepted")
        T.eq(f.exports.calls, 0, version .. " legacy callback is asynchronous")
        f:drain()
        T.eq(f.exports.calls, 1, version .. " legacy warp completes once")
        T.eq(f.callbackMusicCount, 0, version .. " legacy keepMusic survives through callback")
        T.eq(f.sawFade, true, version .. " legacy warp retains native fade")
        T.same({ f.player.cellX, f.player.cellY, f.player.facing }, { 2, 3, "up" },
          version .. " legacy arrival retains destination position and facing")
        if arrival then
          T.eq(f.callbackHadAnimation, true, version .. " legacy callback precedes native landing")
          T.check(f.animationFrames > 1, version .. " legacy arrival advances native animation")
        else
          T.check(not f.callbackBusy, version .. " legacy plain callback follows cleanup")
          T.check(not f.callbackFieldLocked, version .. " legacy plain callback releases owned lock")
        end
        for _ = 1, 8 do f:tick() end
        T.eq(f.exports.calls, 1, version .. " legacy native completion cannot repeat callback")
        T.eq(#f.run.errors, 0, version .. " legacy callback has no swallowed errors")
      end)
    end
  end

  exercise(version, "native defaults", function(f)
    T.eq(f.exports.plain(f.away), true, version .. " no-options warp accepted")
    f:drain()
    T.eq(f.exports.calls, 0, version .. " no-options path installs no callback")
    T.check(#f.music > 0, version .. " no-options path retains native map music selection")
    T.eq(f.animationFrames, 0, version .. " no-options path adds no special arrival")
  end)

  for _, reason in ipairs({ "provider", "save", "rollback", "bus", "cancel", "map" }) do
    exercise(version, reason .. " suppresses callback", function(f)
      T.eq(f.exports.warp(f.away, "teleport", true), true, version .. " pending warp starts")
      if reason == "provider" then
        f.live, f.run.loader.game = {}, {}
      elseif reason == "save" then
        local replacement = Merge.deepCopy(f.save)
        if f.generation == 3 then f.game.session = replacement else f.game.save = replacement end
      elseif reason == "rollback" then
        f.run.loader:_rollback("warp_probe")
      elseif reason == "bus" then
        ModRuntime.install(require("src.mods.Events").new(), require("src.mods.Hooks").new(), {})
      elseif reason == "cancel" then
        if f.generation == 3 then Warp.clear()
        elseif f.generation == 2 then
          f.world:setMap(f.home, 1, 1, "down", { keepMusic = true })
        else
          f.stack:pop()
          f.world.transitioning = false
        end
      elseif f.generation == 3 then
        Map.load(nil, f.game, f.home, { x = 1, y = 1, keepMusic = true })
      elseif f.generation == 2 then
        f.world:setMap(f.home, 1, 1, "down", { keepMusic = true })
      else
        f.world:setMap(f.home, 1, 1, "down", { keepMusic = true })
      end
      for _ = 1, 600 do f:tick() end
      T.eq(f.exports.calls, 0, version .. " " .. reason .. " suppresses stale success")
    end)
  end

  exercise(version, "refused native load", function(f)
    local calls = f.exports.calls
    if f.generation == 2 then
      f.world.tilesets.FIX_OUT = nil
      T.check(f.exports.warp(f.away, "teleport", true) ~= true,
        version .. " missing native tileset refuses warp")
    else
      f.game.data.maps[f.away] = nil
      T.check(f.exports.warp(f.away, "teleport", true) ~= true,
        version .. " unknown destination refuses warp")
    end
    for _ = 1, 8 do f:tick() end
    T.eq(f.exports.calls, calls, version .. " refusal never reports success")
    T.check(not f:busy(), version .. " refused warp leaves no transition busy")
    if f.generation == 3 then
      local nativeCalls = 0
      local result = Warp.request(nil, f.game, "NOT_GAME3_MAP", 2, 3, "up", {
        fade = false, keepMusic = true, onDone = function() nativeCalls = nativeCalls + 1 end,
      })
      T.eq(result, nil, version .. " native Map.load refusal propagates")
      for _ = 1, 8 do f:tick() end
      T.eq(nativeCalls, 0, version .. " native load refusal suppresses completion")
      T.eq(Warp.isBusy(), false, version .. " native load refusal releases owned transition")
      T.eq(Field.isLocked(), false, version .. " native load refusal releases owned field lock")
    end
  end)

  if Version.generation(version) == 3 then
    for _, kind in ipairs({ "teleport", "fly" }) do
      for _, reason in ipairs({ "bus", "provider", "locks", "session" }) do
        exercise(version, kind .. " mid-arrival " .. reason .. " retirement", function(f)
          T.eq(f.exports.warp(f.away, kind, true), true, version .. " starts owned arrival")
          for _ = 1, 600 do
            if f.exports.calls > 0 then break end
            f:tick()
          end
          T.eq(f.exports.calls, 1, version .. " transition notifies before cancellation")
          T.eq(f.callbackHadAnimation, true, version .. " callback arms a real native arrival")
          local owned = Effects._anims[1]
          T.check(owned ~= nil, version .. " real native arrival remains in flight")
          local foreign, locks = {}, Field._locks
          local token = Warp._portable
          T.check(token ~= nil and locks[token] == true, version .. " arrival owns a captured lock token")
          Field.lock(foreign)
          Field.lock()
          local unrelated = { kind = "warp_probe_foreign", timer = 0 }
          Effects._anims[#Effects._anims + 1] = unrelated
          local replacement, session, player, effects, pose
          if reason == "bus" then
            ModRuntime.install(require("src.mods.Events").new(), require("src.mods.Hooks").new(), {})
          elseif reason == "locks" then
            f.replace(Field, "_locks", { [foreign] = true, default = true })
          elseif reason == "session" then
            session = Merge.deepCopy(f.save)
            session.map, session.x, session.y = f.away, 4, 5
            f.replace(f.game, "session", session)
            f.replace(f.game, "save", session)
            f.replace(Runtime, "session", session)
            f.replace(Field, "_session", session)
            pose = { cellX = 4, cellY = 5, facing = "left", visible = false,
              spriteXOffset = 7, spriteYOffset = -23, flyRide = true,
              fieldMoveAnim = 9, oamPriority = 2, fixedPriority = true, subpriority = 5 }
            for key, value in pairs(pose) do f.replace(Player, key, value) end
          else
            session = Merge.deepCopy(f.save)
            session.map, session.x, session.y = f.home, 4, 5
            replacement = { session = session, save = session, data = f.game.data }
            player = { cellX = 4, cellY = 5, facing = "left", visible = false,
              spriteXOffset = 7, spriteYOffset = -23, flyRide = true,
              fieldMoveAnim = 9, oamPriority = 2, fixedPriority = true, subpriority = 5 }
            effects = { _anims = { { kind = "warp_probe_new", timer = 0 } } }
            f.live, f.run.loader.game = replacement, replacement
            f.replace(Runtime, "session", session)
            f.replace(Runtime, "_game", replacement)
            f.replace(Field, "_game", replacement)
            f.replace(Field, "_session", session)
            f.replace(Field, "_locks", { [foreign] = true, default = true })
            f.replace(package.loaded, "src.core.game3.player", player)
            f.replace(package.loaded, "src.core.game3.field_effects", effects)
          end
          local currentLocks = Field._locks
          f:tick()
          T.same(Effects._anims, { unrelated }, version .. " retires only the stale owned effect")
          T.check(not owned or owned.onDone == nil, version .. " retires the stale native completion")
          T.eq(Warp.isBusy(), false, version .. " cancellation retires owned warp")
          T.eq(locks[token], nil, version .. " cancellation removes its token from captured locks")
          T.eq(locks[foreign], true, version .. " cancellation preserves captured foreign lock")
          T.eq(locks.default, true, version .. " cancellation preserves captured default lock")
          T.eq(Field._locks, currentLocks, version .. " cancellation preserves current lock table ownership")
          T.eq(currentLocks[foreign], true, version .. " cancellation preserves current foreign lock")
          T.eq(currentLocks.default, true, version .. " cancellation preserves current default lock")
          if reason == "bus" or reason == "locks" then
            T.eq(Player.spriteXOffset, 0, version .. " cancelled arrival restores horizontal offset")
            T.eq(Player.spriteYOffset, 0, version .. " cancelled arrival restores grounded player offset")
            T.check(not Player.flyRide, version .. " cancelled arrival clears owned flying pose")
            T.eq(Player.fieldMoveAnim, 0, version .. " cancelled arrival clears owned field move pose")
            T.eq(Player.oamPriority, nil, version .. " cancelled arrival clears owned teleport priority")
            T.eq(Player.visible, true, version .. " cancelled arrival leaves player visible")
            T.eq(Runtime.getSession(), f.save, version .. " cancellation retains the current session")
            T.eq(package.loaded["src.core.game3.player"], Player, version .. " cancellation retains the current Player")
            T.eq(package.loaded["src.core.game3.field_effects"], Effects,
              version .. " cancellation retains the current effects provider")
          end
          for _ = 1, 8 do f:tick() end
          T.eq(f.exports.calls, 1, version .. " cancellation and later frames cannot repeat callback")
          if reason == "session" then
            T.eq(Runtime.getSession(), session, version .. " cancellation preserves replacement session")
            T.eq(Field._game, f.game, version .. " session replacement retains the field provider")
            T.eq(Field._session, session, version .. " cancellation preserves replacement field session")
            T.eq(package.loaded["src.core.game3.player"], Player, version .. " session replacement retains the same Player")
            T.eq(package.loaded["src.core.game3.field_effects"], Effects,
              version .. " session replacement retains the same effects provider")
            T.same({ session.map, session.x, session.y }, { f.away, 4, 5 },
              version .. " cancellation preserves replacement session position")
            for key, value in pairs(pose) do
              T.eq(Player[key], value, version .. " cancellation preserves replacement session Player " .. key)
            end
          end
          if replacement then
            T.eq(Runtime.getSession(), session, version .. " cancellation preserves new session ownership")
            T.eq(Field._game, replacement, version .. " cancellation preserves new field provider")
            T.eq(Field._session, session, version .. " cancellation preserves new field session")
            T.eq(Field._locks[foreign], true, version .. " cancellation preserves new foreign lock")
            T.eq(Field._locks.default, true, version .. " cancellation preserves new default lock")
            T.same({ session.map, session.x, session.y }, { f.home, 4, 5 },
              version .. " cancellation preserves new session position")
            T.eq(package.loaded["src.core.game3.player"], player, version .. " preserves replacement Player")
            T.same(player, { cellX = 4, cellY = 5, facing = "left", visible = false,
              spriteXOffset = 7, spriteYOffset = -23, flyRide = true,
              fieldMoveAnim = 9, oamPriority = 2, fixedPriority = true, subpriority = 5 },
              version .. " cancellation preserves new Player state")
            T.eq(package.loaded["src.core.game3.field_effects"], effects,
              version .. " cancellation preserves replacement effects provider")
            T.same(effects._anims, { { kind = "warp_probe_new", timer = 0 } },
              version .. " cancellation preserves new provider animation")
          end
        end)
      end
    end
    exercise(version, "foreign lock ownership", function(f)
      T.eq(f.exports.warp(f.away, "fly", true), true, version .. " warp starts before foreign lock")
      local foreign = {}
      Field.lock(foreign)
      Field.lock()
      f:drain()
      T.eq(Field._locks[foreign], true, version .. " arrival preserves another owner's lock")
      T.eq(Field._locks.default, true, version .. " arrival preserves an existing default lock")
      T.eq(f.exports.calls, 1, version .. " own transition completes with foreign lock intact")
    end)
    for _, kind in ipairs({ "transition", "on-frame" }) do
      exercise(version, kind .. " native script lock ownership", function(f)
        Space.bundle.scripts.warp_probe_lock = {
          { op = "delay", frames = 10000 }, { op = "end" },
        }
        Space.bundle.events[f.away] = { mapScripts = kind == "transition"
          and { onTransition = "warp_probe_lock" }
          or { onFrame = { { var = 0, value = 0, script = "warp_probe_lock" } } } }
        T.eq(Field._locks.default, nil, version .. " native script starts without a default lock")
        T.eq(f.exports.warp(f.away, nil, true), true, version .. " plain warp enters native script map")
        f:drain()
        T.eq(f.exports.calls, 1, version .. " native script map reports arrival once")
        T.eq(f.callbackFieldLocked, true, version .. " callback preserves native script lock")
        T.eq(Field._locks.default, true, version .. " arrival preserves map-load script lock")
        if kind == "transition" then
          T.eq(Space.vm:isRunning(), true, version .. " native transition VM remains running")
        else
          T.eq(Space._pendingOnFrame, true, version .. " native on-frame script remains pending")
          T.eq(Space.vm:isRunning(), false, version .. " pending on-frame lock precedes VM execution")
        end
        for _ = 1, 8 do f:tick() end
        T.eq(f.exports.calls, 1, version .. " native script lock cannot repeat arrival callback")
        T.eq(Field._locks.default, true, version .. " later warp frames preserve native script lock")
      end)
    end
  elseif Version.generation(version) == 2 then
    exercise(version, "remembered outdoor escape consumer", function(f)
      local world = f.world
      local nativeWarp = { x = 4, y = 5 }
      world.maps[f.home].warps[1] = nativeWarp
      world.backupWarp = { map = f.home, warp = 1 }
      local backup = world.backupWarp
      world.map.def.environment = "CAVE"
      world:rememberOutdoor(f.home, 2, 3)
      T.same(world.lastOutdoor, { id = f.home, x = 2, y = 3 }, version .. " remembers Gen 1 coordinates")
      T.same(f.save.lastOutdoor, world.lastOutdoor, version .. " remembered record persists")
      local id, target = world:escapeRopeTarget()
      T.eq(id, f.home, version .. " escape consumes remembered map")
      T.same(target, { x = 2, y = 3 }, version .. " escape consumes remembered cells")
      T.eq(world.backupWarp, backup, version .. " coordinate memory preserves backup warp ownership")
      T.same(backup, { map = f.home, warp = 1 }, version .. " native -1 warp retains its index")
      world.lastOutdoor = nil
      id, target = world:escapeRopeTarget()
      T.same(target, { x = 2, y = 3 }, version .. " escape also consumes persisted record")
      for _, bad in ipairs({ -1, 0 / 0, math.huge, 0.5, 999 }) do
        f.save.lastOutdoor = { id = f.home, x = bad, y = 3 }
        id, target = world:escapeRopeTarget()
        T.eq(id, f.home, version .. " invalid memory retains native fallback map")
        T.eq(target, nativeWarp, version .. " invalid memory retains native warp record")
      end
      f.save.lastOutdoor = nil
      id, target = world:escapeRopeTarget()
      T.eq(target, nativeWarp, version .. " no remembered record retains native fallback")
      world.map.def.environment = "TOWN"
      T.eq(world:escapeRopeTarget(), nil, version .. " outdoor map still refuses escape")
    end)
  end
end

NativeVersions.select(savedNativeVersion)
Version.set(savedVersion)
ModRuntime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish()
