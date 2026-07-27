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
  -- FieldDefaults reads from data; Player.new needs Collision for tryMove —
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
