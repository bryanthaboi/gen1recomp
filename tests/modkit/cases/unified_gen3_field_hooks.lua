package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local ModRuntime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")
local Runtime = require("src.core.game3.runtime")
local Pokemon = require("src.core.game3.pokemon")
local Player = require("src.core.game3.player")
local Collision = require("src.core.game3.collision")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local Space = require("src.core.game3.scripting.space")
local FieldMoves = require("src.core.game3.field_moves")
local Encounters = require("src.core.game3.encounters")
local Rng = require("src.core.game3.rng")
local Display = require("src.core.game3.display")
local Renderer = require("src.render.Renderer")
local Game3Link = require("src.link.Game3Link")
local Net = require("src.link.Net")

local originalVersion, originalNativeVersion = Version.get(), Versions.active()
local originalRng = Rng.getState()
local savedRuntime = { ModRuntime.events, ModRuntime.hooks, ModRuntime.errors }
local restore, links = {}, {}
local function fixture(owner, key, value)
  local old = owner[key]
  restore[#restore + 1] = function() owner[key] = old end
  owner[key] = value
end

local BODY = [[
local mod = ...
local out = mod.exports
out.mode, out.calls, out.trace = "pass", {}, {}
out.connected, out.ended = {}, {}
out.install = function(kind)
  local removers = {}
  local function wrap(name, fn)
    removers[#removers + 1] = mod.hooks:wrap(name, function(next, ...)
      out.calls[name] = (out.calls[name] or 0) + 1
      return fn(next, ...)
    end)
  end
  if kind == "movement" then
    wrap("movement.speed", function(next, frames, ctx)
      out.frames, out.movement = frames, ctx
      if out.mode == "change" then return 3.9 end
      if out.mode == "zero" then return 0 end
      if out.mode == "nan" then return 0 / 0 end
      if out.mode == "infinity" then return math.huge end
      if out.mode == "invalid" then return {} end
      return next(frames, ctx)
    end)
  elseif kind == "eligibility" then
    wrap("fieldmove.eligibility", function(next, moveId, ctx)
      out.moveId, out.eligibility = moveId, ctx
      local mon = next(moveId, ctx)
      out.nativeMon = mon
      if out.mode == "change" then return ctx.party[2] end
      if out.mode == "suppress" then return nil end
      if out.mode == "invalid" then return { species = "PIDGEY", moves = { { id = "SURF", pp = 10, maxPp = 15 } }, level = 5, hp = 10 } end
      if out.mode == "malformed" then return { species = "PIDGEY", moves = { "SURF" } } end
      return mon
    end)
  elseif kind == "fishing" then
    wrap("encounter.fishing", function(next, rodId, mapId, pool)
      out.rodId, out.mapId, out.pool = rodId, mapId, pool
      if out.mode == "suppress" then return nil end
      if out.mode == "change" then
        for _, entry in ipairs(pool) do
          entry.species, entry.level = "CHARMANDER", 17
          entry.minLevel, entry.maxLevel = 17, 17
        end
      end
      local result = next(rodId, mapId, pool)
      out.fish = result
      if out.mode == "invalid" then return false end
      return result
    end)
  elseif kind == "render" then
    wrap("render.zones", function(next, game, zones)
      out.trace[#out.trace + 1] = "zones"
      out.renderGame = game
      zones = next(game, zones)
      if out.mode == "change" then return out.zones end
      return zones
    end)
    wrap("render.compose", function(next, renderer, ctx)
      out.trace[#out.trace + 1] = "compose"
      out.composite, out.renderer = ctx, renderer
      out.shaderAtCompose = love.graphics.getShader()
      if out.onRender then out.onRender("compose") end
      if out.mode == "claim" then return true end
      return next(renderer, ctx)
    end)
    wrap("render.output_enabled", function(next)
      out.trace[#out.trace + 1] = "enabled"
      if out.onRender then out.onRender("enabled") end
      return out.mode ~= "disabled"
    end)
    wrap("render.letterbox", function(next, ctx)
      out.trace[#out.trace + 1] = "letterbox"
      out.letterbox = ctx
      if out.onRender then out.onRender("letterbox") end
      return next(ctx)
    end)
    wrap("render.output", function(next, ctx)
      out.trace[#out.trace + 1] = "output"
      out.output = ctx
      if out.onRender then out.onRender("output") end
      if out.mode == "output_claim" then return true end
      return next(ctx)
    end)
  elseif kind == "link" then
    removers[#removers + 1] = mod.events:on("link.connected", function(ev)
      out.connected[#out.connected + 1] = ev
      if out.onConnected then out.onConnected(ev) end
    end)
    removers[#removers + 1] = mod.events:on("link.ended", function(ev)
      out.ended[#out.ended + 1] = ev
      if out.onEnded then out.onEnded(ev) end
    end)
  end
  return function() for _, remove in ipairs(removers) do remove() end end
end
]]

local function setup(version)
  Version.set(version)
  Versions.select(version)
  Profile.reset()
  local data = T.sdk.gen3Data()
  data.gen3Inputs = { stats = data.gen3Pokemon._stats, types = data.gen3Pokemon._types,
    abilities = data.gen3Pokemon._abilities, meta = data.gen3Pokemon._speciesMeta,
    moves = data.gen3Moves._rom, items = data.gen3Items._byId,
    typeChart = require("src.core.game3.battle.types").TABLE, natures = {}, constants = {} }
  for key, value in pairs(data.gen3Pokemon) do fixture(Pokemon, key, value) end
  fixture(Pokemon, "_byName", { CHARMANDER = 4, PIDGEY = 16, MEW = 151 })
  fixture(Pokemon, "_national", { toNational = { [4] = 4, [16] = 16 } })
  local party = {
    { species = 16, nickname = "FIRST", moves = { 57 }, hp = 0, maxHp = 20,
      level = 5, personality = 0, ability = 0 },
    { species = 4, nickname = "SECOND", moves = { 57 }, hp = 20, maxHp = 20,
      level = 5, personality = 1, ability = 0 },
  }
  local session = { version = version, name = "RED", trainerId = 42, secretId = 0,
    party = party, map = "FR_OAKS_LAB", flags = {}, vars = {}, options = {} }
  local game = { data = data, session = session, save = { position = {} },
    options = session.options, phase = "field", input = {} }
  session.game = game
  fixture(Runtime, "active", true)
  fixture(Runtime, "session", session)
  fixture(Runtime, "_game", game)
  fixture(Runtime, "_mod", nil)
  fixture(Space, "store", session)
  local files = {
    ["mods/field_hooks/manifest.json"] = '{"id":"field_hooks","name":"Field hooks",'
      .. '"version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/field_hooks/main.lua"] = BODY,
  }
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3,
    version = version, dev = true })
  loader.game = game
  T.eq(loader:load(data), true, version .. " API 3 loader succeeds")
  T.eq(#loader.errors, 0, version .. " mod loads without errors")
  return loader.exports.field_hooks, game, loader
end

local function exercise(version, label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  T.check(ok, version .. " " .. label .. ": " .. tostring(err))
  for _, link in ipairs(links) do link:close("fixture_cleanup") end
  links = {}
  for i = #restore, 1, -1 do restore[i]() end
  restore = {}
  love.graphics.setCanvas()
  love.graphics.setShader()
end

local function bindFloor(game)
  local layout = { width = 4, height = 1, pair = "unified_field_hooks" }
  function layout:collAt() return 0 end
  function layout:elevAt() return 3 end
  function layout:midAt() return 0 end
  function layout:collArray() return { 0, 0, 0, 0 } end
  fixture(Interaction.behaviors, layout.pair, { [0] = 0 })
  fixture(Collision, "_mapDef", Collision._mapDef)
  Collision.bindMap(game, game.session.map, { midLayout = layout, pair = layout.pair, warps = {} })
  Player.reset(0, 0, "right")
  Player.elevation, Player.currentElevation = 3, 3
end

local function step(game, expected)
  Player.reset(0, 0, "right")
  T.eq(Player.tryMove("right", game, false), "step", "native movement starts")
  T.eq(Player.stepFrames, expected, "committed duration uses hook result")
  local pixels = {}
  for frame = 1, expected do
    Player.tick(game)
    pixels[frame] = Player.px
    T.eq(Player.px, math.floor(frame * 16 / expected), "native pixel interpolation")
    T.eq(Player.moving, frame < expected, "native completion frame")
  end
  T.eq(Player.cellX, 1, "native step reaches destination")
  return pixels
end

local seed = { value = 123456, value2 = 98765, wild = 4321 }
local function fish(rod, direct, opts)
  Rng.setState(seed)
  Encounters._encounterRateBuff, Encounters._stepsSinceLastEncounter = 0, 0
  local enc
  if direct then enc = Encounters.rules().rollFishing("FR_OAKS_LAB", rod, opts)
  else enc = Encounters.rollFishing("FR_OAKS_LAB", rod, opts) end
  return { encounter = enc, rng = Rng.getState(), buff = Encounters._encounterRateBuff,
    steps = Encounters._stepsSinceLastEncounter }
end

for _, version in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  exercise(version, "committed movement", function()
    local out, game, loader = setup(version)
    bindFloor(game)
    local rng = Rng.getState()
    local stock = step(game, 16)
    local remove = out.install("movement")
    T.same(step(game, 16), stock, version .. " observer preserves native movement")
    T.eq(out.calls["movement.speed"], 1, version .. " committed step wraps exactly once")
    T.eq(out.frames, 16, version .. " duration is in 60 Hz ticks")
    T.eq(out.movement.dir, "right", version .. " actual facing reaches callback")
    T.eq(out.movement.onBike, false, version .. " foot context")
    T.eq(out.movement.surfing, false, version .. " land context")
    out.mode = "change"
    step(game, 3)
    out.mode = "zero"
    step(game, 1)
    for _, mode in ipairs({ "nan", "infinity", "invalid" }) do
      out.mode = mode
      step(game, 16)
    end
    out.mode = "change"
    Player.reset(0, 0, "right")
    local calls = out.calls["movement.speed"]
    T.eq(Player.forcedStep("right", 4), true, version .. " forced movement starts")
    T.eq(Player.stepFrames, 4, version .. " forced exact timing survives hook")
    T.eq(out.calls["movement.speed"], calls, version .. " forced step bypasses ordinary hook")
    remove()
    T.same(step(game, 16), stock, version .. " unsubscribe restores movement")
    T.same(Rng.getState(), rng, version .. " movement hooks consume no RNG")
    T.eq(#loader.errors, 0, version .. " movement callbacks are valid")
  end)

  exercise(version, "selected party reference", function()
    local out, game, loader = setup(version)
    local party, rng = game.session.party, Rng.getState()
    local mon, slot = FieldMoves.partyMoveUser(party, 57)
    T.eq(mon, party[1], version .. " native fainted move user remains eligible")
    T.eq(slot, 0, version .. " native slot remains zero based")
    local remove = out.install("eligibility")
    mon, slot = FieldMoves.partyMoveUser(party, 57)
    T.eq(mon, party[1], version .. " observer returns actual native reference")
    T.eq(slot, 0, version .. " observer keeps native slot")
    T.eq(out.moveId, "SURF", version .. " public move identifier")
    T.eq(out.eligibility.moveId, "SURF", version .. " context move identifier")
    T.eq(out.eligibility.party[1].species, "PIDGEY", version .. " public party species")
    T.eq(out.nativeMon.species, "PIDGEY", version .. " next returns public mon")
    out.mode = "change"
    mon, slot = FieldMoves.partyMoveUser(party, 57)
    T.eq(mon, party[2], version .. " selected public mon restores native identity")
    T.eq(slot, 1, version .. " selected mon drives native slot")
    out.mode = "suppress"
    mon, slot = FieldMoves.partyMoveUser(party, 57)
    T.eq(mon, nil, version .. " rejected eligibility returns no mon")
    T.eq(slot, 6, version .. " rejected eligibility uses native sentinel")
    for _, mode in ipairs({ "invalid", "malformed" }) do
      out.mode = mode
      mon, slot = FieldMoves.partyMoveUser(party, 57)
      T.eq(mon, party[1], version .. " " .. mode .. " record keeps native eligibility fallback")
      T.eq(slot, 0, version .. " " .. mode .. " record keeps native fallback slot")
    end
    remove()
    party[1].isEgg = true
    mon, slot = FieldMoves.partyMoveUser(party, 57)
    T.eq(mon, party[2], version .. " native egg exclusion survives unsubscribe")
    T.eq(slot, 1, version .. " native egg exclusion selects next slot")
    T.same(Rng.getState(), rng, version .. " eligibility consumes no RNG")
    T.eq(#loader.errors, 0, version .. " eligibility callbacks are valid")
  end)

  exercise(version, "fishing pool and native RNG", function()
    local out, _, loader = setup(version)
    local slots = {}
    for i = 1, 10 do slots[i] = { species = 16, minLevel = 5, maxLevel = 9 } end
    fixture(Encounters, "_tables", { FR_OAKS_LAB = { fishing = { rate = 100, slots = slots } } })
    fixture(Encounters, "_loaded", true)
    local rods = { [0] = "OLD_ROD", [1] = "GOOD_ROD", [2] = "SUPER_ROD" }
    for rod = 0, 2 do
      local native, stock = fish(rod, true), fish(rod)
      T.same(stock, native, version .. " facade matches selected native family")
      T.eq(stock.encounter.species, 16, version .. " native pool is consumed")
      local remove = out.install("fishing")
      out.mode = "pass"
      T.same(fish(rod), stock, version .. " observer preserves full RNG and result")
      T.eq(out.rodId, rods[rod], version .. " public rod identifier")
      T.eq(out.pool[1].species, "PIDGEY", version .. " public candidate species")
      T.eq(#out.pool, rod == 0 and 2 or rod == 1 and 3 or 5, version .. " selected rod pool")
      T.eq(out.fish.species, "PIDGEY", version .. " public downstream encounter")
      out.mode = "change"
      local changed = fish(rod)
      T.eq(changed.encounter.species, 4, version .. " changed pool controls native selection")
      T.eq(changed.encounter.level, 17, version .. " changed pool controls native level")
      T.eq(slots[1].species, 16, version .. " shared native table is unchanged")
      T.eq(slots[1].minLevel, 5, version .. " shared native level is unchanged")
      out.mode = "invalid"
      T.same(fish(rod), stock, version .. " invalid return never rolls twice")
      out.mode = "suppress"
      local suppressed = fish(rod)
      T.eq(suppressed.encounter, nil, version .. " nil suppresses actual fishing")
      T.same(suppressed.rng, seed, version .. " suppression consumes no RNG")
      remove()
      T.same(fish(rod), stock, version .. " unsubscribe restores native fishing")
    end
    local malformed = fish(0, true, { modFishingPool = { { species = 4, minLevel = 0 } } })
    T.eq(malformed.encounter, nil, version .. " backend rejects malformed optional pool")
    T.same(malformed.rng, seed, version .. " malformed pool rejected before RNG")
    local custom = fish(2, true, { modFishingPool = {
      { species = 4, minLevel = 17, maxLevel = 17 },
    } })
    T.eq(custom.encounter.species, 4, version .. " backend consumes optional selected rod pool")
    T.eq(custom.encounter.level, 17, version .. " backend consumes optional level range")
    T.eq(#loader.errors, 0, version .. " fishing callbacks are valid")
  end)

  exercise(version, "native display and shared compositor", function()
    local out, game, loader = setup(version)
    fixture(Display, "planesBroken", false)
    local draws, scissors = {}, {}
    local draw = love.graphics.draw
    fixture(love.graphics, "draw", function(canvas, ...)
      draws[#draws + 1] = { canvas = canvas, target = love.graphics.getCanvas() }
      return draw(canvas, ...)
    end)
    fixture(love.graphics, "setScissor", function(x, y, w, h)
      if x then scissors[#scissors + 1] = { x, y, w, h } end
    end)
    fixture(love.graphics, "newShader", function()
      return { send = function() end, hasUniform = function() return true end }
    end)
    local dirty = love.graphics.newShader("")
    local function present()
      out.trace, draws, scissors = {}, {}, {}
      love.graphics.setShader()
      local ok = Display.presentUi(game, 640, 576, "field", function()
        love.graphics.setShader(dirty)
        love.graphics.setColor(0.2, 0.3, 0.4, 1)
      end)
      T.eq(ok, true, version .. " native display presents without fallback")
      T.eq(Display.planesBroken, false, version .. " shared renderer remains active")
      return #scissors
    end
    present()
    local remove = out.install("render")
    out.mode = "pass"
    local baselineScissors = present()
    T.same(out.trace, { "zones", "compose", "enabled", "letterbox", "output" },
      version .. " actual composite hook order")
    T.eq(out.renderGame, game, version .. " zones receive actual game")
    T.eq(out.renderer, Renderer, version .. " native shared renderer owns composition")
    T.eq(out.composite.uiCanvas, Renderer.canvas, version .. " compose receives actual UI canvas")
    T.eq(out.composite.uiw, 240, version .. " compose uses native width")
    T.eq(out.composite.uih, 160, version .. " compose uses native height")
    T.eq(out.shaderAtCompose, nil, version .. " UI graphics state restored before composition")
    T.eq(out.output.canvas, Renderer.presentCanvas, version .. " actual composite reaches output")
    T.eq(out.output.generation, 3, version .. " actual native compositor identifies generation")
    T.check(#draws > 0, version .. " renderer performs actual blits")
    out.zones = { { x = 8, y = 16, w = 24, h = 32,
      colors = { { 255, 0, 0 }, { 170, 0, 0 }, { 85, 0, 0 }, { 0, 0, 0 } } } }
    out.mode = "change"
    local zoneScissors = present()
    T.eq(out.composite.zones[1].x, 8, version .. " zones reach actual compositor")
    T.check(zoneScissors > baselineScissors, version .. " changed zones affect native blit clipping")
    out.mode = "claim"
    present()
    T.same(out.trace, { "zones", "compose" }, version .. " claimed composition skips default output")
    out.mode = "disabled"
    present()
    T.same(out.trace, { "zones", "compose", "enabled", "letterbox" },
      version .. " disabled output retains native letterbox and blit")
    remove()
    present()
    T.same(out.trace, {}, version .. " unsubscribe silences render callbacks")
    T.eq(#loader.errors, 0, version .. " render callbacks are valid")
  end)

  exercise(version, "finished canvas presentation", function()
    local out, game, loader = setup(version)
    local G = love.graphics
    local canvas = G.newCanvas(240, 160)
    local target, stray = G.newCanvas(640, 576), G.newCanvas(8, 8)
    fixture(Display, "_presentCanvas", nil)
    fixture(G, "newShader", function()
      return { send = function() end, hasUniform = function() return true end }
    end)
    local dirty = G.newShader("")
    local draws, draw = {}, G.draw
    fixture(G, "draw", function(source, ...)
      draws[#draws + 1] = { canvas = source, target = G.getCanvas(), args = { ... },
        shader = G.getShader(), color = { G.getColor() }, blend = G.getBlendMode() }
      return draw(source, ...)
    end)
    out.onRender = function(name)
      T.eq(G.getShader(), nil, version .. " " .. name .. " receives clean shader state")
      T.same({ G.getColor() }, { 1, 1, 1, 1 }, version .. " " .. name .. " receives clean color")
      T.eq(G.getBlendMode(), "alpha", version .. " " .. name .. " receives restored blend")
      local expected = name == "letterbox" and out.mode ~= "disabled"
        and Display._presentCanvas or target
      T.eq(G.getCanvas(), expected, version .. " " .. name .. " receives actual render target")
      G.setCanvas(stray)
      G.setShader(dirty)
      G.setColor(0.7, 0.6, 0.5, 0.4)
      G.setBlendMode("add")
    end
    local function present(mode, worldActive, hooked)
      out.mode, out.trace, draws = mode, {}, {}
      G.setCanvas(target)
      G.setShader(hooked and dirty or nil)
      G.setColor(0.2, 0.3, 0.4, 1)
      G.setBlendMode("alpha")
      T.eq(Display.presentCanvas(game, canvas, 640, 576, worldActive), true,
        version .. " finished native canvas presents")
      T.eq(G.getCanvas(), target, version .. " finished presentation preserves caller target")
      if hooked then
        T.eq(G.getShader(), dirty, version .. " finished presentation restores caller shader")
        T.same({ G.getColor() }, { 0.2, 0.3, 0.4, 1 },
          version .. " finished presentation restores caller color")
        T.eq(G.getBlendMode(), "alpha", version .. " finished presentation restores caller blend")
        for _, blit in ipairs(draws) do
          T.eq(blit.shader, nil, version .. " callback shader does not leak into native blit")
          T.same(blit.color, { 1, 1, 1, 1 }, version .. " callback color does not tint native blit")
          T.eq(blit.blend, "alpha", version .. " callback blend does not leak into native blit")
        end
      end
      return draws
    end
    for _, worldActive in ipairs({ false, true }) do
      local stock = present("pass", worldActive, false)
      local scale, ox, oy, vpw, vph, scaleY = Display.fit(640, 576)
      T.eq(#stock, 1, version .. " native finished canvas blits once")
      T.eq(stock[1].canvas, canvas, version .. " native path uses supplied finished canvas")
      T.eq(stock[1].target, target, version .. " native path draws to caller target")
      T.same(stock[1].args, { ox, oy, 0, scale, scaleY }, version .. " native letterbox geometry")
      local remove = out.install("render")
      present("pass", worldActive, true)
      T.same(out.trace, { "zones", "compose", "enabled", "letterbox", "output" },
        version .. " finished canvas dispatches each hook once in order")
      T.eq(out.renderGame, game, version .. " finished canvas zones receive actual game")
      T.eq(out.composite.zones, nil, version .. " native RGB canvas needs no palette zones")
      T.eq(out.composite.uiCanvas, canvas, version .. " compose receives supplied finished canvas")
      T.eq(out.composite.worldCanvas, canvas, version .. " flat world uses supplied finished canvas")
      T.eq(out.composite.worldActive, worldActive, version .. " native world activity reaches compose")
      T.eq(out.composite.generation, 3, version .. " finished compose identifies generation")
      T.eq(out.output.generation, 3, version .. " finished output identifies generation")
      T.eq(out.output.canvas, Display._presentCanvas, version .. " finished composite reaches output")
      T.same({ out.output.width, out.output.height, out.output.gameX, out.output.gameY,
        out.output.gameWidth, out.output.gameHeight }, { 640, 576, ox, oy, vpw, vph },
        version .. " finished output carries actual window and native viewport")
      T.eq(#draws, 2, version .. " observer composites and presents once")
      T.eq(draws[1].canvas, canvas, version .. " supplied canvas feeds finished composite")
      T.eq(draws[1].target, Display._presentCanvas, version .. " native frame reaches output canvas")
      T.eq(draws[2].canvas, out.output.canvas, version .. " unclaimed output is presented")
      T.eq(draws[2].target, target, version .. " unclaimed output reaches caller target")
      present("claim", worldActive, true)
      T.same(out.trace, { "zones", "compose" }, version .. " finished compose claim takes precedence")
      T.eq(#draws, 0, version .. " claimed finished composition skips native blits")
      present("output_claim", worldActive, true)
      T.same(out.trace, { "zones", "compose", "enabled", "letterbox", "output" },
        version .. " output claim follows finished composition")
      T.eq(#draws, 1, version .. " output claim skips final native presentation")
      T.eq(draws[1].target, Display._presentCanvas, version .. " claimed output still builds composite")
      present("disabled", worldActive, true)
      T.same(out.trace, { "zones", "compose", "enabled", "letterbox" },
        version .. " disabled finished output keeps native letterbox")
      T.eq(#draws, 1, version .. " disabled output blits native canvas once")
      T.eq(draws[1].canvas, canvas, version .. " disabled output retains supplied canvas")
      T.eq(draws[1].target, target, version .. " disabled output draws directly to caller target")
      remove()
      T.same(present("pass", worldActive, false), stock,
        version .. " unsubscribe restores native finished-canvas blit and state")
      T.same(out.trace, {}, version .. " unsubscribe silences finished-canvas callbacks")
    end
    T.eq(#loader.errors, 0, version .. " finished-canvas callbacks are valid")
  end)

  exercise(version, "link handshake and once lifecycle", function()
    local out, game, loader = setup(version)
    local remove = out.install("link")
    local host, guest = Game3Link.loopback({ game = game, linkType = Game3Link.LINKTYPE.TRADE })
    links = { host, guest }
    host:update(0); guest:update(0); host:update(0); guest:update(0)
    T.eq(host:isReady(), true, version .. " actual host handshake succeeds")
    T.eq(guest:isReady(), true, version .. " actual guest handshake succeeds")
    T.eq(#out.connected, 2, version .. " each native session connects once")
    local roles = {}
    for _, ev in ipairs(out.connected) do
      roles[ev.role] = true
      T.eq(ev.remote.name, "RED", version .. " connected remote name")
      T.check(type(ev.remote.mods) == "table", version .. " connected remote mod list")
      T.check(ev.remote.fingerprint ~= nil, version .. " connected remote fingerprint")
    end
    T.check(roles.host and roles.guest, version .. " inherited host and guest roles")
    out.onEnded = function() host:close("reentrant"); guest:close("reentrant") end
    host:close("fixture_close")
    guest:update(0)
    host:close("duplicate"); guest:close("duplicate")
    T.eq(#out.ended, 2, version .. " reentrant and repeated close notify once per session")
    T.eq(out.ended[1].reason, "fixture_close", version .. " ended preserves original reason")
    remove()
    local count = #out.ended
    local a = Net.loopbackPair()
    local quiet = Game3Link.attach(a, { game = game, timeout = 1 })
    links[#links + 1] = quiet
    quiet:update(2)
    T.eq(quiet:getStatus(), "failed", version .. " native handshake timeout")
    T.eq(#out.ended, count, version .. " unsubscribe silences link lifecycle")
    T.eq(#loader.errors, 0, version .. " link callbacks are valid")
  end)

  exercise(version, "link error transitions", function()
    local out, game = setup(version)
    out.install("link")
    local a, b = Net.loopbackPair()
    local timeout = Game3Link.attach(a, { game = game, timeout = 1 })
    links[#links + 1] = timeout
    timeout:update(2); timeout:update(2); timeout:close("duplicate")
    T.eq(#out.connected, 0, version .. " timeout cannot report connected")
    T.eq(#out.ended, 1, version .. " timeout ends once")
    T.eq(out.ended[1].reason, "handshake_timeout", version .. " timeout reason")
    a, b = Net.loopbackPair()
    local failed = Game3Link.attach(a, { game = game })
    links[#links + 1] = failed
    b:close()
    failed:update(0); failed:update(0)
    T.eq(#out.ended, 2, version .. " lost transport ends once")
    T.eq(out.ended[2].reason, "no_peer", version .. " lost transport reason")
    a, b = Net.loopbackPair()
    local mine, peer = Game3Link.hello(game, Game3Link.LINKTYPE.TRADE),
      Game3Link.hello(game, Game3Link.LINKTYPE.TRADE)
    peer.game3.cacheVersion = -1
    local refused = Game3Link.attach(a, { game = game, hello = mine })
    local other = Game3Link.attach(b, { game = game, hello = peer })
    links[#links + 1], links[#links + 2] = refused, other
    refused:update(0); refused:update(0); refused:close("duplicate")
    T.eq(#out.connected, 1, version .. " incompatible peer is identified once before native refusal")
    T.eq(#out.ended, 3, version .. " refusal ends once")
    T.eq(out.ended[3].reason, "cache_version_mismatch", version .. " native refusal reason")
  end)
end

ModRuntime.events, ModRuntime.hooks, ModRuntime.errors = savedRuntime[1], savedRuntime[2], savedRuntime[3]
Version.set(originalVersion)
Versions.select(originalNativeVersion)
Profile.reset()
Rng.setState(originalRng)
T.finish("unified_gen3_field_hooks")
