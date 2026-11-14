package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("unified gen2 hooks")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local Events = require("src.mods.Events")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")
local BattleState = require("src.ui.gen2.BattleState")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")
local World = require("src.world.gen2.World")
local Vm = require("src.script.gen2.Vm")
local StateStack = require("src.core.StateStack")
local Input = require("src.core.Input")
local Font = require("src.render.Font")
local Assets = require("src.render.Assets")

local savedRuntime = { Runtime.events, Runtime.hooks, Runtime.errors }
local savedDraw, savedImage = Font.draw, Assets.image
local printed, images = {}, {}

Assets.image = function(path)
  if not images[path] then
    images[path] = love.graphics.newImage(path)
  end
  return images[path]
end
Font.draw = function(text, x, y)
  printed[#printed + 1] = { text = tostring(text or ""), x = x, y = y }
  return Font.width(text or "")
end
local charmap = { { seq = "<LV>", code = 0x6e } }
for code = 32, 126 do
  charmap[#charmap + 1] = { seq = string.char(code), code = code + 128 }
end
Font.load({ font = { charmap = charmap } })

local function buses()
  Runtime.install(Events.new(), Hooks.new(), {})
end

local function dataFor(version)
  return {
    version = version,
    gen2Palettes = { battleText = {
      { 255, 255, 255 }, { 140, 156, 255 }, { 115, 132, 255 }, { 0, 0, 0 },
    } },
    pokemon = {
      growthRates = { GROWTH_MEDIUM_FAST = {
        numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0,
      } },
      MAGIKARP = {
        id = "MAGIKARP", name = "MAGIKARP", index = 129, dex = 129,
        types = { "WATER", "WATER" }, genderRatio = 127,
        catchRate = 255, baseExp = 20, growthRate = "GROWTH_MEDIUM_FAST",
        baseStats = { hp = 80, attack = 10, defense = 55, speed = 80,
          specialAttack = 15, specialDefense = 20 },
        levelMoves = { { level = 1, move = "SPLASH" } }, evolutions = {},
      },
    },
    moves = { SPLASH = { id = "SPLASH", name = "SPLASH", type = "NORMAL",
      power = 0, accuracy = 100, pp = 40, effect = "EFFECT_SPLASH" } },
    type_chart = { types = {
      NORMAL = { id = "NORMAL", index = 0, category = "physical" },
      WATER = { id = "WATER", index = 21, category = "special" },
    }, matchups = {} },
    items = {},
  }
end

local function newGame(version)
  local data = dataFor(version)
  local player = Mon.new(data, "MAGIKARP", 42, {
    dvs = { attack = 8, defense = 8, speed = 8, special = 8 },
  })
  player.nickname = "SCOUT"
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local input = setmetatable({}, { __index = Input })
  input:init()
  return { data = data, stack = stack, input = input, sessionStartedAt = 1,
    save = { version = version, party = { player }, player = { name = "GOLD" },
      options = {}, pokedex = { seen = {}, caught = {} }, engineFlags = {},
      inventory = {}, money = 1000 } }
end

local function newBattle(version)
  local game = newGame(version)
  local enemy = Mon.new(game.data, "MAGIKARP", 42, {
    dvs = { attack = 8, defense = 8, speed = 8, special = 8 },
  })
  enemy.nickname = "FOE"
  local battle = Battle.new({ data = game.data, save = game.save,
    party = game.save.party, wild = enemy,
    random = function(n) return n > 1 and 1 or 0 end })
  return game, battle
end

local function newScreen(version)
  local game, battle = newBattle(version)
  local screen = BattleState.new(game, { battle = battle })
  screen.phase, screen.slideFrame = "menu", 1000
  screen.queue = {}
  screen.showPlayerHud, screen.showEnemyHud = true, true
  screen.ballRows = { player = false, enemy = false }
  screen.shownMon = { player = battle.player, enemy = battle.enemy }
  screen.shownHp = { player = battle.player.hp, enemy = battle.enemy.hp }
  screen.shownStatus = { player = false, enemy = false }
  screen.shownExp = 0
  game.stack.states = { screen }
  return game, battle, screen
end

local function capture(draw)
  printed = {}
  draw()
  local out = printed
  printed = {}
  return out
end

local function contains(rows, fragment)
  for _, row in ipairs(rows) do
    if row.text:find(fragment, 1, true) then return true end
  end
  return false
end

local function at(rows, x, y)
  local out = {}
  for _, row in ipairs(rows) do
    if row.x == x * 8 and row.y == y * 8 then out[#out + 1] = row.text end
  end
  return table.concat(out)
end

local function exercise(version, name, fn)
  buses()
  local ok, err = pcall(fn)
  T.check(ok, version .. " " .. name .. " completes: " .. tostring(err))
end

local function trainerWorld(version)
  local game = newGame(version)
  local world = World.new(game)
  game.world = world
  world.map = { id = "FIX_ROUTE", def = {} }
  local record = { class = 1, member = 1, event = 700,
    name = "JOEY", className = "YOUNGSTER",
    roster = { { species = "MAGIKARP", level = 5 } } }
  local npc = { id = "TRAINER_1", def = { trainer = record } }
  world.npcs = { npc }
  world.vm = Vm.new({}, {}, world.events)
  return game, world, npc, record
end

local SCRIPT = { { op = "pause", frames = 10 }, { op = "end" } }

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  exercise(version, "trainer defer, resume and unsubscribe", function()
    for _, sight in ipairs({ false, { distance = 1, dir = "down" } }) do
      local game, world, npc = trainerWorld(version)
      local calls, engaged, continuation, context = 0, 0
      Runtime.events:on("world.trainer_engaged", function()
        engaged = engaged + 1
      end, 0, "trainer-events")
      local unsubscribe = Runtime.hooks:wrap("trainer.before_battle",
        function(_, hookGame, ctx, continueBattle)
          calls, continuation, context = calls + 1, continueBattle, ctx
          T.eq(hookGame, game, version .. " trainer receives the live game")
          return true
        end)
      world:startTrainerScript(npc, SCRIPT, sight or nil)
      T.eq(calls, 1, version .. " trainer hook runs once")
      T.eq(engaged, 0, version .. " deferred trainer has no engagement event")
      T.eq(npc.frozen, nil, version .. " deferred trainer is not frozen early")
      T.eq(world.vm:running(), false, version .. " deferred trainer VM is idle")
      T.same(context, { trainerClass = 1, partyIndex = 1,
        mapId = "FIX_ROUTE", npcId = "TRAINER_1" },
        version .. " trainer context keeps Gen1 identity keys")
      T.eq(continuation(), true, version .. " continuation starts the native VM")
      T.eq(world.vm:running(), true, version .. " resumed trainer VM is running")
      T.eq(world.vm.pending.kind, "wait", version .. " native pause owns the VM")
      T.eq(npc.frozen, true, version .. " resumed trainer freezes once")
      T.eq(engaged, 1, version .. " resumed trainer emits engagement once")
      T.eq(continuation(), false, version .. " duplicate continuation is refused")
      T.eq(engaged, 1, version .. " duplicate continuation emits no engagement")
      unsubscribe()
      Runtime.events:removeOwner("trainer-events")
      local _, plain, plainNpc = trainerWorld(version)
      T.eq(plain:startTrainerScript(plainNpc, SCRIPT), true,
        version .. " unsubscribe restores immediate trainer entry")
      T.eq(plain.vm:running(), true, version .. " native no-hook VM starts")
    end
  end)

  exercise(version, "stale trainer continuations", function()
    local changes = {
      session = function(game) game.sessionStartedAt = 2 end,
      world = function(game) game.world = {} end,
      save = function(game) game.save = {} end,
      map = function(_, world) world.map = { id = "OTHER_ROUTE" } end,
      npc = function(_, world) world.npcs = {} end,
      trainer = function(_, _, npc) npc.def.trainer = {} end,
      provider = function() Runtime.hooks = Hooks.new() end,
    }
    for name, change in pairs(changes) do
      buses()
      local game, world, npc = trainerWorld(version)
      local continuation
      Runtime.hooks:wrap("trainer.before_battle", function(_, _, _, continueBattle)
        continuation = continueBattle
        return true
      end)
      world:startTrainerScript(npc, SCRIPT)
      change(game, world, npc)
      T.eq(continuation(), false, version .. " stale " .. name .. " is refused")
      T.eq(world.vm:running(), false, version .. " stale " .. name .. " cannot start VM")
      T.eq(npc.frozen, nil, version .. " stale " .. name .. " cannot freeze NPC")
    end
  end)

  exercise(version, "trainer callback errors fall through", function()
    local _, world, npc = trainerWorld(version)
    local engaged = 0
    Runtime.events:on("world.trainer_engaged", function() engaged = engaged + 1 end)
    Runtime.hooks:wrap("trainer.before_battle", function() error("trainer probe") end)
    world:startTrainerScript(npc, SCRIPT)
    T.eq(world.vm:running(), true, version .. " throwing wrapper starts native VM")
    T.eq(engaged, 1, version .. " throwing wrapper engages exactly once")
  end)

  exercise(version, "scripted trainer constructs one real battle", function()
    local game, world, _, record = trainerWorld(version)
    world.map = nil
    local starts, calls, continuation = 0, 0
    local seenBattles = {}
    Runtime.events:on("battle.started", function(payload)
      local native = payload.battle.battle or payload.battle
      if not seenBattles[native] then
        seenBattles[native], starts = true, starts + 1
      end
    end)
    local unsubscribe = Runtime.hooks:wrap("trainer.before_battle",
      function(_, _, _, continueBattle)
        calls, continuation = calls + 1, continueBattle
        return true
      end)
    world:startScriptedBattle(record)
    T.eq(starts, 0, version .. " scripted trainer defers battle construction")
    T.eq(#game.stack.states, 0, version .. " deferred battle pushes no screen")
    T.eq(continuation(), true, version .. " scripted continuation is accepted")
    T.eq(starts, 1, version .. " scripted continuation constructs native battle")
    T.eq(game.stack:top().battle.wild, false, version .. " native trainer battle opens")
    T.eq(continuation(), false, version .. " scripted continuation is one-shot")
    T.eq(starts, 1, version .. " duplicate cannot construct a second battle")
    T.eq(calls, 1, version .. " scripted continuation does not reintercept itself")
    unsubscribe()
  end)

  exercise(version, "residual HP, detachment and native event order", function()
    local game, battle = newBattle(version)
    battle.player.status = "poison"
    local hp, enemyHp = battle.player.hp, battle.enemy.hp
    local poison = math.max(1, math.floor(battle.player.maxHp / 8))
    battle.field = { tokens = { { id = "wind", state = { strength = 2 },
      onExpire = function() error("live callback leaked") end } } }
    local calls, order, view = 0, {}, nil
    Runtime.events:on("battle.turn_started", function() order[#order + 1] = "start" end)
    Runtime.events:on("battle.turn_ended", function()
      order[#order + 1] = "end"
      T.eq(battle.player.hp, hp - poison - 7,
        version .. " turn_ended observes native poison then custom residual HP")
    end)
    local unsubscribe = Runtime.hooks:wrap("battle.field_residual", function(_, context)
      calls, view = calls + 1, context
      order[#order + 1] = "residual"
      T.eq(context.battlers.player.hp, hp - poison,
        version .. " hook runs after ordinary poison")
      T.eq(context.battle, nil, version .. " residual view exposes no raw battle")
      T.eq(context.field.tokens[1].onExpire, nil, version .. " view strips callbacks")
      T.check(context.field ~= battle.field and context.battlers.player ~= battle.player,
        version .. " public snapshots are detached")
      context.field.tokens[1].state.strength = 99
      context.battlers.player.hp = 1
      context.battlers.enemy.types[1] = "FIRE"
      return { { side = "player", amount = 7, message = "FIELD CHIP" },
        { side = "enemy", amount = 3 } }
    end)
    local rows = battle:takeTurn({ kind = "move", move = "SPLASH" })
    T.eq(calls, 1, version .. " hook runs once for a real round")
    T.same(order, { "start", "residual", "end" }, version .. " lifecycle ordering")
    T.eq(view.turn, battle.turn, version .. " residual context identifies round")
    T.eq(battle.player.hp, hp - poison - 7, version .. " native HP includes custom chip")
    T.eq(battle.enemy.hp, enemyHp - 3, version .. " enemy HP uses validated amount")
    T.eq(battle.field.tokens[1].state.strength, 2, version .. " token mutation is detached")
    T.eq(game.data.pokemon.MAGIKARP.types[1], "WATER", version .. " type mutation is detached")
    local messageIndex, damageIndex
    for i, row in ipairs(rows) do
      if row.text == "FIELD CHIP" then messageIndex = i end
      if row.kind == "damage" and row.side == "player" and row.amount == 7 then
        damageIndex = i
        T.eq(row.hp, battle.player.hp, version .. " native drain event carries final HP")
      end
    end
    T.check(messageIndex and damageIndex and messageIndex < damageIndex,
      version .. " custom message precedes native damage event")
    unsubscribe()
    Runtime.events = Events.new()
    local before = battle.player.hp
    battle:takeTurn({ kind = "move", move = "SPLASH" })
    T.eq(calls, 1, version .. " unsubscribe stops residual calls")
    T.eq(battle.player.hp, before - poison, version .. " unsubscribe keeps native poison")
  end)

  exercise(version, "invalid residual descriptors preserve HP", function()
    local _, battle = newBattle(version)
    local hp, enemyHp = battle.player.hp, battle.enemy.hp
    Runtime.hooks:wrap("battle.field_residual", function()
      return { false, "bad", {}, { side = "other", amount = 4 },
        { side = "player", amount = -1 }, { side = "player", amount = 0 },
        { side = "player", amount = 1.5 }, { side = "player", amount = "7" },
        { side = "player", amount = math.huge }, { side = "player", amount = 0 / 0 },
        { side = "enemy", amount = 5, message = {} } }
    end)
    battle:takeTurn({ kind = "move", move = "SPLASH" })
    T.eq(battle.player.hp, hp, version .. " invalid rows cannot damage player")
    T.eq(battle.enemy.hp, enemyHp, version .. " invalid rows cannot damage enemy")
  end)

  exercise(version, "residual faint batch and settled exits", function()
    local _, battle = newBattle(version)
    local hp, enemyHp = battle.player.hp, battle.enemy.hp
    local calls, ended = 0, {}
    Runtime.events:on("battle.ended", function(event) ended[#ended + 1] = event.result end)
    local unsubscribe = Runtime.hooks:wrap("battle.field_residual", function()
      calls = calls + 1
      return { { side = "enemy", amount = 999999 },
        { side = "player", amount = 999999 } }
    end)
    local rows = battle:takeTurn({ kind = "move", move = "SPLASH" })
    T.eq(battle.player.hp, 0, version .. " player residual clamps at zero")
    T.eq(battle.enemy.hp, 0, version .. " enemy residual clamps at zero")
    T.eq(battle.outcome, "lose", version .. " terminal player faint wins the batch")
    T.same(ended, { "lose" }, version .. " native battle ends exactly once")
    local fainted, drained = {}, {}
    for _, row in ipairs(rows) do
      if row.kind == "faint" then fainted[row.side] = true end
      if row.kind == "damage" then drained[row.side] = row.amount end
      T.check(row.kind ~= "exp", version .. " terminal batch awards no experience")
    end
    T.check(fainted.player and fainted.enemy, version .. " native faint events cover both sides")
    T.eq(drained.player, hp, version .. " player drain clamps to remaining HP")
    T.eq(drained.enemy, enemyHp, version .. " enemy drain clamps to remaining HP")
    battle:takeTurn({ kind = "move", move = "SPLASH" })
    T.eq(calls, 1, version .. " already settled battle gets no extra residual")
    unsubscribe()

    local _, escaped = newBattle(version)
    local escapeCalls = 0
    Runtime.hooks:wrap("battle.field_residual", function()
      escapeCalls = escapeCalls + 1
      return { { side = "player", amount = 1 } }
    end)
    escaped.player.stats.speed = 999
    escaped:takeTurn({ kind = "run" })
    T.eq(escaped.outcome, "run", version .. " native escape settles the round")
    T.eq(escapeCalls, 0, version .. " successful escape has no custom residual")
  end)

  exercise(version, "caught eligibility and dynamic visibility", function()
    local game, battle, screen = newScreen(version)
    screen.caughtMark = true
    T.eq(screen:caughtMarkerVisible(), false, version .. " uncaught species has no marker")
    game.save.pokedex.caught.MAGIKARP = true
    T.eq(screen:caughtMarkerVisible(), true, version .. " native caught species is eligible")
    local answer, calls = false, 0
    local unsubscribe = Runtime.hooks:wrap("battle.caught_marker_visible", function(_, owner)
      T.eq(owner, screen, version .. " caught wrapper receives native screen")
      calls = calls + 1
      return answer
    end)
    capture(function() screen:drawEnemyHud() end)
    T.eq(calls, 1, version .. " actual HUD draw evaluates caught visibility")
    T.eq(screen:caughtMarkerVisible(), false, version .. " false hides eligible marker")
    answer = true
    T.eq(screen:caughtMarkerVisible(), true, version .. " live answer changes without new battle")
    local before = calls
    capture(function() screen:drawEnemyHud() end)
    T.eq(calls, before + 1, version .. " next HUD draw reevaluates visibility")
    game.save.pokedex.caught.MAGIKARP = nil
    T.eq(screen:caughtMarkerVisible(), false, version .. " true cannot invent caught ownership")
    game.save.pokedex.caught.MAGIKARP = true
    battle.wild = false
    T.eq(screen:caughtMarkerVisible(), false, version .. " trainer battle stays ineligible")
    battle.wild = true
    unsubscribe()
    T.eq(screen:caughtMarkerVisible(), true, version .. " unsubscribe restores stock marker")
  end)

  exercise(version, "START claim and native fallback", function()
    local game, _, screen = newScreen(version)
    game.input.pressed = { start = true, right = true }
    screen:update(0)
    T.eq(screen.menuIndex, 2, version .. " no-hook START preserves native menu input")
    local calls, answer = 0, true
    local unsubscribe = Runtime.hooks:wrap("battle.menu_auxiliary", function(_, hookGame, ctx)
      calls = calls + 1
      T.eq(hookGame, game, version .. " START wrapper receives game")
      T.same(ctx, { kind = "wild" }, version .. " START wrapper receives Gen1 context")
      return answer
    end)
    screen.menuIndex = 1
    screen:update(0)
    T.eq(calls, 1, version .. " safe START invokes wrapper once")
    T.eq(screen.menuIndex, 1, version .. " true consumes native menu input")
    answer = false
    screen:update(0)
    T.eq(calls, 2, version .. " false still invokes wrapper once")
    T.eq(screen.menuIndex, 2, version .. " false falls through to native navigation")
    unsubscribe()
    screen.menuIndex = 1
    screen:update(0)
    T.eq(calls, 2, version .. " unsubscribe removes START callback")
    T.eq(screen.menuIndex, 2, version .. " unsubscribe restores native navigation")
  end)

  exercise(version, "unsafe START boundaries", function()
    local unsafe = {
      covered = function(game) game.stack.states[#game.stack.states + 1] = {} end,
      link = function(_, battle) battle.linkBattle = true end,
      tutorial = function(_, _, screen) screen.tutorial = true end,
      forcedSwitch = function(_, battle) battle.forcedSwitch = true end,
      pendingSwitch = function(_, battle) battle.pendingSwitch = true end,
      queue = function(_, _, screen) screen.queue = { { kind = "message" } } end,
      changing = function(_, battle) battle.events = { { kind = "damage" } } end,
      fainted = function(_, battle) battle.player.hp = 0 end,
      unsettled = function(_, _, screen) screen.shownHp.player = screen.shownHp.player - 1 end,
      animating = function(_, _, screen) screen.trainerSlide = 1 end,
      moves = function(_, _, screen) screen.phase = "moves" end,
    }
    for name, change in pairs(unsafe) do
      local game, battle, screen = newScreen(version)
      local calls = 0
      local unsubscribe = Runtime.hooks:wrap("battle.menu_auxiliary", function()
        calls = calls + 1
        return true
      end)
      change(game, battle, screen)
      game.input.pressed = { start = true }
      screen:update(0)
      T.eq(calls, 0, version .. " unsafe " .. name .. " cannot claim START")
      unsubscribe()
    end
  end)

  exercise(version, "whole level omission and restoration on real screens", function()
    local game, battle, screen = newScreen(version)
    local party = PartyMenu.new(game)
    local summary = SummaryMenu.new(game)
    local surfaces = {
      { name = "party", draw = function() party:draw() end, count = 1 },
      { name = "party", draw = function() party:drawWidescreen(960, 576) end, count = 1 },
      { name = "summary", draw = function() summary:draw() end, count = 2 },
      { name = "summary", draw = function() summary:drawWidescreen(960, 576) end, count = 2 },
      { name = "battle", draw = function() screen:draw() end, count = 2 },
      { name = "battle", draw = function() screen:drawWidescreen(960, 576) end, count = 2 },
    }
    for index, surface in ipairs(surfaces) do
      local label = version .. " " .. surface.name .. " layout " .. index
      local baseline = capture(surface.draw)
      local levels = 0
      for _, row in ipairs(baseline) do
        if row.text:find("<LV>", 1, true) then levels = levels + 1 end
      end
      T.eq(levels, surface.count, label .. " native whole level count")
      local seen = {}
      local unsubscribe = Runtime.hooks:wrap("pokemon.level_visible", function(_, mon, ctx)
        seen[ctx.where] = true
        T.eq(ctx.game, game, label .. " level context carries live game")
        T.check(mon == battle.player or mon == battle.enemy, label .. " level context carries mon")
        return false
      end)
      local hidden = capture(surface.draw)
      T.eq(contains(hidden, "<LV>"), false, label .. " no orphan level glyph")
      for _, row in ipairs(baseline) do
        if row.text:find("<LV>", 1, true) then
          T.eq(at(hidden, row.x / 8, row.y / 8), "", label .. " level digits also omitted")
        end
      end
      T.check(seen[surface.name] or (seen["battle.player"] and seen["battle.enemy"]),
        label .. " actual draws identify their surfaces")
      T.check(contains(hidden, "SCOUT"), label .. " nickname remains")
      if surface.name == "party" or surface.name == "battle" then
        T.check(contains(hidden, "/"), label .. " native HP digits remain")
      end
      unsubscribe()
      T.same(capture(surface.draw), baseline, label .. " unsubscribe restores exact printed rows")
    end

    summary.moveDetail = true
    local baseline = capture(function() summary:draw() end)
    T.check(contains(baseline, "<LV>42"), version .. " move-detail baseline includes level")
    local unsubscribe = Runtime.hooks:wrap("pokemon.level_visible", function() return false end)
    T.eq(contains(capture(function() summary:draw() end), "<LV>"), false,
      version .. " move-detail omits whole level")
    battle.player.status, battle.enemy.status = "poison", "poison"
    screen.shownStatus = { player = "poison", enemy = "poison" }
    T.check(contains(capture(function() screen:drawPlayerHud() end), "PSN"),
      version .. " level suppression preserves player status label")
    T.check(contains(capture(function() screen:drawEnemyHud() end), "PSN"),
      version .. " level suppression preserves enemy status label")
    T.check(contains(capture(function() party:draw() end), "PSN"),
      version .. " level suppression preserves party status label")
    battle.player.hp = 0
    T.check(contains(capture(function() party:draw() end), "FNT"),
      version .. " level suppression preserves party faint label")
    unsubscribe()
    T.same(capture(function() summary:draw() end), baseline,
      version .. " move-detail unsubscribe restores printed level")
  end)
end

Font.draw, Assets.image = savedDraw, savedImage
Runtime.install(savedRuntime[1], savedRuntime[2], savedRuntime[3])
T.finish()
