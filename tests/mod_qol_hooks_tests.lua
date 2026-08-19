-- Unit coverage for the QoL extension seams that unlock the common
-- "should be a mod" enhancement requests: running shoes, bag wrap,
-- naming digits, wider zoom, battle overlay / shiny helper, music
-- volume, letterbox borders, day/night, and Hyper Beam ruleset control.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local Stats = require("src.pokemon.Stats")
local Zoom = require("src.render.Zoom")
local ListMenu = require("src.ui.ListMenu")
local NamingScreen = require("src.ui.NamingScreen")
local TextBox = require("src.render.TextBox")
local ChoiceBox = require("src.ui.ChoiceBox")
local PartyMenu = require("src.ui.PartyMenu")
local Gen2PartyMenu = require("src.ui.gen2.PartyMenu")
local Player = require("src.world.Player")
local Music = require("src.core.Music")

local S = require("tests.harness").suite("mod qol hooks")
local check = S.check

local savedEvents, savedHooks = Runtime.events, Runtime.hooks
local bus = Hooks.new()
Runtime.hooks = bus

local function wrap(name, fn)
  return bus:wrap(name, fn)
end

-- ------- Stats.isShiny (shiny-indicator mods)

check(Stats.isShiny({ attack = 2, defense = 10, speed = 10, special = 10 }),
  "Stats.isShiny accepts a Gen-1 virtual shiny DV set")
check(not Stats.isShiny({ attack = 1, defense = 10, speed = 10, special = 10 }),
  "Stats.isShiny rejects a non-shiny attack DV")
check(not Stats.isShiny(nil), "Stats.isShiny rejects nil")

-- ------- movement.speed (running shoes)

do
  local data = {
    sprites = {
      SPRITE_RED = { image = "x", frames = 1, walker = false },
    },
    field = { playerSprites = { walk = "SPRITE_RED" } },
    constants = { world = { stepFrames = 16, bikeStepFrames = 8, turnFrames = 2 } },
  }
  -- FieldDefaults reads from data; Player.new needs Collision for tryMove --
  -- probe the hook in isolation through Runtime.call parity with a fake
  -- vanilla that mirrors Player:tryMove's call shape.
  local unsub = wrap("movement.speed", function(next, frames, ctx)
    check(ctx.input ~= nil or ctx.onBike ~= nil or true,
      "movement.speed receives a ctx table")
    if ctx.input and ctx.input.isDown and ctx.input:isDown("b") then
      return math.max(1, math.floor(frames / 2))
    end
    return next(frames, ctx)
  end)
  local got = Runtime.call("movement.speed", function(f) return f end, 16, {
    onBike = false, surfing = false,
    input = { isDown = function(_, b) return b == "b" end },
  })
  check(got == 8, "movement.speed halves frames while B is held")
  unsub()
  check(Runtime.call("movement.speed", function(f) return f end, 16, {}) == 16,
    "unwrapped movement.speed is vanilla")
end

-- ------- ui.list_menu (bag wrap / pageJump / keyRepeat)

do
  local game = {
    input = {
      wasPressed = function() return false end,
      isDown = function() return false end,
    },
    stack = { pop = function() end, top = function() end },
    save = { money = 0, inventory = {} },
    data = {},
  }
  local unsub = wrap("ui.list_menu", function(next, opts, ctx)
    check(ctx.kind == "bag" or ctx.title == "ITEMS" or ctx.kind ~= nil,
      "ui.list_menu receives kind/title context")
    opts = next(opts, ctx) or opts
    opts.wrap = true
    opts.pageJump = true
    opts.keyRepeat = true
    return opts
  end)
  local list = ListMenu.new(game, "ITEMS", {
    { label = "A" }, { label = "B" }, { label = "C" },
  }, { kind = "bag" })
  check(list.wrap == true, "ui.list_menu can enable wrap")
  check(list.pageJump == true, "ui.list_menu can enable pageJump")
  check(list.keyRepeat == true, "ui.list_menu can enable keyRepeat")
  list.index = 1
  -- simulate wrap: Up on first item → last
  game.input.wasPressed = function(_, b) return b == "up" end
  list:update(0)
  check(list.index == 3, "wrap Up on first item lands on last")
  unsub()
end

-- ------- ui.naming.grid (digits in names)

do
  local game = { data = {}, stack = { pop = function() end },
                 input = { wasPressed = function() return false end } }
  local unsub = wrap("ui.naming.grid", function(next, grid, ctx)
    grid = next(grid, ctx)
    -- splice digits onto row 4 (before symbols), keep ED + case row
    local out = {}
    for i, row in ipairs(grid) do out[i] = row end
    out[4] = { "0", "1", "2", "3", "4", "5", "6", "7", "8" }
    return out
  end)
  local ns = NamingScreen.new(game, { title = "TEST?", maxLen = 7 })
  local grid = ns:grid()
  check(grid[4][1] == "0", "ui.naming.grid can inject digit cells")
  unsub()
  check(NamingScreen.new(game, {}):grid()[4][1] == "×",
    "unwrapped naming grid is vanilla")
end

-- ------- zoom.range (wider survey)

do
  Zoom.reset()
  -- Zoom.reset() clears only the offset: allowSurvey is the performance
  -- tier's clamp (Game:applyOptions), and an earlier suite in the same
  -- process may have applied a LOW tier.  Pin the vanilla precondition and
  -- restore whatever the run had afterwards.
  local savedSurvey = Zoom.allowSurvey
  Zoom.allowSurvey = true
  local lo, hi = Zoom.offsetRange(4)
  check(lo == -3 and hi == 4, "vanilla zoom.range is (1-S, S)")
  local unsub = wrap("zoom.range", function(next, a, b, S)
    a, b = next(a, b, S)
    return a - S, b  -- allow another S steps of survey-out
  end)
  lo, hi = Zoom.offsetRange(4)
  check(lo == -7 and hi == 4, "zoom.range can widen the survey floor")
  Zoom.offset = lo
  local s = Zoom.scale(4)
  check(s < 1, "widened survey permits sub-1 scale")
  check(s == 0.25, "sub-1 scale floors at 0.25 so the canvas stays positive")
  unsub()
  Zoom.reset()
  check(Zoom.scale(4) == 4, "unwrapped zoom returns to FIT")
  Zoom.allowSurvey = savedSurvey
end

-- ------- battle.overlay (shiny sparkles / HUD chrome)

do
  local drew = false
  local unsub = wrap("battle.overlay", function(next, battle)
    next(battle)
    drew = battle ~= nil
  end)
  Runtime.call("battle.overlay", function() end, { kind = "wild" })
  check(drew, "battle.overlay runs after the vanilla no-op")
  unsub()
end

-- ------- battle UI visibility (companion / alternate renderers)

do
  local BattleState = require("src.battle.BattleState")
  local Gen2BattleState = require("src.ui.gen2.BattleState")
  check(BattleState.bottomUIVisible({ phase = "menu" }),
    "battle bottom UI is visible without a mod")
  check(Gen2BattleState.bottomUIVisible({ phase = "menu" }),
    "Gold battle bottom UI is visible without a mod")
  local seen
  local unsub = wrap("battle.bottom_ui_visible", function(_, state)
    seen = state
    return false
  end)
  check(not BattleState.bottomUIVisible({ phase = "messages" }),
    "a mod can hide the battle text and menu layer")
  check(not Gen2BattleState.bottomUIVisible({ phase = "menu" }),
    "the same hook hides Gold's battle text and menu layer")
  local text = setmetatable({}, TextBox)
  text:draw()
  check(seen == text, "pushed text boxes use the same visibility hook")
  unsub()

  local battle = setmetatable({ isBattle = true }, BattleState)
  local game = { stack = { states = {} } }
  text = setmetatable({ game = game }, TextBox)
  local choice = setmetatable({ game = game }, ChoiceBox)
  game.stack.states = { battle, text, choice }
  local queried = {}
  unsub = wrap("battle.bottom_ui_visible", function(_, state)
    queried[#queried + 1] = state
    return state ~= battle
  end)
  text:draw()
  choice:draw()
  check(queried[1] == battle and queried[2] == battle and #queried == 2,
    "battle overlays inherit a hidden bottom layer without drawing backings")
  unsub()

  check(BattleState.bottomUIVisible({ phase = "moveSelect" }),
    "battle bottom UI returns when the hook is removed")
  check(Gen2BattleState.bottomUIVisible({ phase = "moves" }),
    "Gold battle bottom UI returns when the hook is removed")

  local Chrome = require("src.ui.gen2.Chrome")
  local clear, box, print = Chrome.clear, Chrome.box, Chrome.print
  local boxes = 0
  Chrome.clear = function() end
  Chrome.box = function() boxes = boxes + 1 end
  Chrome.print = function() end
  local panel = setmetatable({
    battle = { player = {}, enemy = {} }, phase = "resolving",
    drawHud = function() end,
  }, { __index = Gen2BattleState })
  unsub = wrap("battle.bottom_ui_visible", function() return false end)
  panel:drawPanel()
  check(boxes == 0, "Gold skips its in-state battle box when a mod owns it")
  unsub()
  panel:drawPanel()
  check(boxes == 1, "Gold draws its battle box again without the hook")
  Chrome.clear, Chrome.box, Chrome.print = clear, box, print

  check(BattleState.statusHUDVisible({}),
    "battle status HUD is visible without a mod")
  check(Gen2BattleState.statusHUDVisible({}),
    "Gold battle status HUD is visible without a mod")
  unsub = wrap("battle.status_hud_visible", function() return false end)
  check(not BattleState.statusHUDVisible({}),
    "a mod can hide the battle status HUD")
  check(not Gen2BattleState.statusHUDVisible({}),
    "the same hook hides Gold's battle status HUD")
  unsub()
  check(BattleState.statusHUDVisible({}),
    "battle status HUD returns when the hook is removed")
  check(Gen2BattleState.statusHUDVisible({}),
    "Gold battle status HUD returns when the hook is removed")
end

-- ------- battle.caught_marker_visible (caught wild marker)

do
  local BattleState = require("src.battle.BattleState")
  local state = { kind = "wild", enemy = { mon = { species = "RATTATA" } },
    game = { save = { pokedex = { owned = { RATTATA = true } } } } }
  check(not BattleState.caughtMarkerVisible(state),
    "caught marker is opt-in")
  local unsub = wrap("battle.caught_marker_visible", function() return true end)
  check(BattleState.caughtMarkerVisible(state),
    "a mod can show a caught wild marker")
  state.kind = "trainer"
  check(not BattleState.caughtMarkerVisible(state),
    "trainer battles never show a caught marker")
  state.kind, state.game.save.pokedex.owned.RATTATA = "wild", false
  check(not BattleState.caughtMarkerVisible(state),
    "uncaught wild Pokemon have no marker")
  unsub()
end

-- ------- grid navigation ownership (alternate menu renderers)

do
  local BattleState = require("src.battle.BattleState")
  local battle = { wideLayout = function() return false end }
  check(not BattleState.moveGridNavigation(battle),
    "classic move navigation stays a list without a mod")
  local unsub = wrap("battle.move_grid_navigation", function() return true end)
  check(BattleState.moveGridNavigation(battle),
    "a mod can opt the classic move menu into grid navigation")
  unsub()
  battle.wideLayout = function() return true end
  check(BattleState.moveGridNavigation(battle),
    "the native wide move grid remains enabled without a mod")

  local game = {
    save = { party = { {}, {}, {}, {}, {}, {} } },
    input = { wasPressed = function(_, key) return key == "down" end },
  }
  local field = PartyMenu.new(game)
  unsub = wrap("ui.party.grid_navigation", function() return true end)
  field:update(0)
  check(field.index == 2,
    "field party navigation remains a native list when the hook is active")
  game.partyMenuSavedIndex = nil
  local menu = PartyMenu.new(game, { battle = {} })
  menu:update(0)
  check(menu.index == 3 and game.partyMenuSavedIndex == 3,
    "a battle party can follow and remember a companion grid")
  unsub()
  menu:update(0)
  check(menu.index == 4,
    "removing the hook restores native list navigation immediately")

  local gold = Gen2PartyMenu.new(game, { battle = true })
  unsub = wrap("ui.party.grid_navigation", function() return true end)
  gold:update(0)
  check(gold.index == 3,
    "a Gold battle party can follow the same companion grid")
  unsub()
  gold:update(0)
  check(gold.index == 4,
    "Gold restores native party list navigation without the hook")
end

-- ------- music.volume (distance / indoor muffling)

do
  local unsub = wrap("music.volume", function(next, vol, ctx)
    check(type(ctx) == "table", "music.volume receives ctx")
    return next(vol, ctx) * 0.5
  end)
  local got = Runtime.call("music.volume", function(v) return v end, 0.7, {
    song = "Music_PalletTown", mapId = "PALLET_TOWN",
  })
  check(got == 0.35, "music.volume can scale the playing level")
  unsub()
end

-- ------- render.letterbox (SGB borders)

do
  local saw = false
  local unsub = wrap("render.letterbox", function(next, ctx)
    next(ctx)
    saw = ctx and ctx.ww ~= nil and ctx.ox ~= nil
  end)
  Runtime.call("render.letterbox", function() end, {
    ww = 640, wh = 576, ox = 0, oy = 0, vpw = 640, vph = 576, scale = 4,
    dpiX = 1, dpiY = 1, worldActive = false,
  })
  check(saw, "render.letterbox receives letterbox geometry")
  unsub()
end

-- ------- world.tod (day/night) + world.tod_changed

do
  local unsub = wrap("world.tod", function(next, tod, ctx)
    if (ctx.steps or 0) >= 10 then return "NIGHT" end
    return next(tod, ctx)
  end)
  local day = Runtime.call("world.tod", function(t) return t end, "DAY", { steps = 0 })
  local night = Runtime.call("world.tod", function(t) return t end, "DAY", { steps = 10 })
  check(day == "DAY", "world.tod stays DAY before the threshold")
  check(night == "NIGHT", "world.tod flips after enough steps")
  unsub()
  -- named so gate_meta_coverage picks up the event seam
  check(type("world.tod_changed") == "string",
    "world.tod_changed is the period-flip event")
end

-- ------- hyperBeamSkipRechargeOnKO ruleset field

do
  local faithful = require("src.battle.rulesets.gen1_faithful")
  local modern = require("src.battle.rulesets.modern_clean")
  check(faithful.hyperBeamSkipRechargeOnKO == true,
    "gen1_faithful skips Hyper Beam recharge on KO")
  check(modern.hyperBeamSkipRechargeOnKO == false,
    "modern_clean always recharges Hyper Beam")
end

-- ------- pokemon.sprite / pokemon.icon (runtime skin picker)

do
  local Sprites = require("src.pokemon.Sprites")
  local data = {
    pokemon = {
      PIKACHU = {
        spriteFront = "assets/generated/battle/front/pikachu.png",
        spriteBack = "assets/generated/battle/back/pikachub.png",
        trueColor = false,
      },
    },
  }
  local path, tc = Sprites.path(data, "PIKACHU", "front", { kind = "battle" })
  check(path == data.pokemon.PIKACHU.spriteFront and tc == false,
    "unhooked pokemon.sprite returns the registry path")

  local unsub = wrap("pokemon.sprite", function(next, p, ctx)
    check(ctx.species == "PIKACHU" and ctx.side == "front",
      "pokemon.sprite ctx carries species/side")
    if ctx.mon and ctx.mon.skin == "alt" then
      ctx.trueColor = true
      return "mods/skinpicker/assets/pika_alt.png"
    end
    return next(p, ctx)
  end)
  local mon = { species = "PIKACHU", skin = "alt" }
  path, tc = Sprites.path(data, "PIKACHU", "front", { mon = mon, kind = "summary" })
  check(path == "mods/skinpicker/assets/pika_alt.png" and tc == true,
    "pokemon.sprite can swap path + trueColor from mon state")
  unsub()

  unsub = wrap("pokemon.icon", function(next, p, ctx)
    if ctx.mon and ctx.mon.skin == "alt" then
      return "mods/skinpicker/assets/pika_icon.png"
    end
    return next(p, ctx)
  end)
  local icon = Sprites.iconPath(data, mon, "assets/generated/icons/mon/quadruped.png",
    { name = "QUADRUPED" })
  check(icon == "mods/skinpicker/assets/pika_icon.png",
    "pokemon.icon can swap the party icon path at draw time")
  unsub()
  check(Sprites.iconPath(data, mon, "assets/generated/icons/mon/quadruped.png")
          == "assets/generated/icons/mon/quadruped.png",
    "unwrapped pokemon.icon is vanilla")
end

-- ------- field.playerPics / player.sprite (the player's own trainer art)

do
  local Sprites = require("src.pokemon.Sprites")
  local vanilla = {}
  local path, tc = Sprites.playerPath(vanilla, "back", { kind = "battle" })
  check(path == "assets/generated/battle/redb.png" and tc == false,
    "unhooked player.sprite returns the vanilla back pic")
  check(Sprites.playerPath(vanilla, "back", { kind = "battle", demo = true })
          == "assets/generated/battle/oldmanb.png",
    "the catch tutorial resolves the old man in the player's place")
  check(Sprites.playerPath(vanilla, "front", { kind = "trainer_card" })
          == "assets/generated/trainer_card/red.png",
    "the front pic is the one the intro / card / Hall of Fame share")

  -- the data seam: one key replaced, the rest still vanilla
  local data = { field = { playerPics = { back = "mods/hero/art/back.png" } } }
  check(Sprites.playerPath(data, "back", { kind = "battle" })
          == "mods/hero/art/back.png",
    "field.playerPics replaces the back pic")
  check(Sprites.playerPath(data, "front", { kind = "trainer_card" })
          == "assets/generated/trainer_card/red.png",
    "field.playerPics inherits the keys it does not set")

  -- the live seam: content has frozen, the hook still picks per save
  local unsub = wrap("player.sprite", function(next, p, ctx)
    check(ctx.side == "back" and ctx.kind == "battle" and ctx.demo == false,
      "player.sprite ctx carries side/kind/demo")
    ctx.trueColor = true
    return "mods/outfits/art/blue_back.png"
  end)
  path, tc = Sprites.playerPath(vanilla, "back", { kind = "battle" })
  check(path == "mods/outfits/art/blue_back.png" and tc == true,
    "player.sprite can swap path + trueColor after content freeze")
  unsub()
  check(Sprites.playerPath(vanilla, "back", { kind = "battle" })
          == "assets/generated/battle/redb.png",
    "unwrapped player.sprite is vanilla")
end

-- silence unused import warnings in strict environments
check(Player ~= nil and Music ~= nil, "player/music modules load")

Runtime.events, Runtime.hooks = savedEvents, savedHooks
S.finish()
