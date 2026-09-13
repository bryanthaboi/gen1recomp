-- screen.render_visible through the public mod API: a mirrored native screen
-- may leave the main render without leaving the active state stack.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")
local Runtime = require("src.mods.Runtime")
local StateStack = require("src.core.StateStack")
local Renderer = require("src.render.Renderer")
local TouchControls = require("src.core.TouchControls")

local FIXTURE = {
  ["mods/fix_screen_mirror/manifest.json"] = [[{
    "id": "fix_screen_mirror",
    "name": "Fixture Screen Mirror",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/fix_screen_mirror/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("screen.render_visible", function(nextFn, state)
      if state.screenId == "BagMenu" then return false end
      return nextFn(state)
    end)
  ]],
}

local savedSetUISize, savedBegin, savedEnd, savedTouch =
  Renderer.setUISize, Renderer.beginFrame, Renderer.endFrame,
  TouchControls.draw
local presentedZones
Renderer.setUISize = function() end
Renderer.beginFrame = function() end
Renderer.endFrame = function(_, zones)
  presentedZones = zones
  return {}
end
TouchControls.draw = function() end

local function scene()
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local base = {
    isOpaque = true,
    draws = 0,
    draw = function(self) self.draws = self.draws + 1 end,
    sgbPalettes = function() return "base zones" end,
  }
  local menu = {
    screenId = "BagMenu",
    isOpaque = true,
    draws = 0,
    updates = 0,
    draw = function(self) self.draws = self.draws + 1 end,
    update = function(self) self.updates = self.updates + 1 end,
    sgbPalettes = function() return "menu zones" end,
  }
  stack:push(base)
  stack:push(menu)
  return { stack = stack, overworld = base, save = { options = {} } },
    base, menu
end

-- no-mod parity
do
  local run = T.sdk.loadNone({})
  local game, base, menu = scene()
  T.eq(Runtime.wantsHook("screen.render_visible"), false,
    "no subscriber leaves the render hook cold")
  Game.draw(game)
  T.eq(base.draws, 0, "the opaque menu still covers the state beneath")
  T.eq(menu.draws, 1, "the opaque menu still draws")
  T.eq(presentedZones, "menu zones", "the visible menu still owns palettes")
  run.release()
end

-- subscribed path, registered by a real fixture mod
do
  local run = T.sdk.loadMods({ "mods/fix_screen_mirror" },
    { fs = T.sdk.memfs(FIXTURE) })
  T.eq(#run.errors, 0,
    "the fixture mod loads clean (" .. tostring(run.errors[1]) .. ")")
  local game, base, menu = scene()
  Game.draw(game)
  T.eq(base.draws, 1, "the state beneath the hidden menu draws")
  T.eq(menu.draws, 0, "the mirrored menu is omitted from the main draw")
  T.eq(presentedZones, "base zones",
    "a hidden state cannot own the main-screen palette")
  T.check(game.stack:top() == menu,
    "the hidden menu remains the active top state")
  game.stack:update(1 / 60)
  T.eq(menu.updates, 1, "the hidden menu keeps its update ownership")

  -- Gold keeps the overworld outside its state stack. A companion-opened
  -- screen can therefore be the stack's only state; visibleBase() still
  -- returns index 1, but that hidden state must not become the direct base.
  for _, boot in ipairs({ false, true }) do
    local stack = setmetatable({}, { __index = StateStack })
    stack:init()
    local hidden = {
      screenId = "BagMenu",
      isOpaque = true,
      draws = 0,
      wideDraws = 0,
      draw = function(self) self.draws = self.draws + 1 end,
      drawsWidescreen = function() return true end,
      drawWidescreen = function(self)
        self.wideDraws = self.wideDraws + 1
      end,
    }
    stack:push(hidden)
    local world = {
      map = {}, draws = 0,
      draw = function(self) self.draws = self.draws + 1 end,
      fitScale = function() return 1 end,
    }
    game = { stack = stack, world = world }
    game.inFillBoot = function() return boot end
    game.letterbox = function() end
    setmetatable(game, { __index = Game2 })

    game:drawScene(1280, 720)
    T.eq(hidden.wideDraws, 0,
      "Gold omits a hidden widescreen top (boot=" .. tostring(boot) .. ")")
    T.eq(hidden.draws, 0,
      "Gold omits its hidden GB canvas (boot=" .. tostring(boot) .. ")")
    T.eq(world.draws, boot and 0 or 1,
      "Gold reveals its external world (boot=" .. tostring(boot) .. ")")
  end
  -- A mirrored menu leaves the complete widescreen battle visible. Drawing
  -- its ordinary panel again can cover a mod-provided scene with opaque paper.
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local wide = {
    isOpaque = true, draws = 0, wideDraws = 0,
    drawsWidescreen = function() return true end,
    drawWidescreen = function(self) self.wideDraws = self.wideDraws + 1 end,
    draw = function(self) self.draws = self.draws + 1 end,
  }
  local hidden = {
    screenId = "BagMenu", isOpaque = true, updates = 0,
    update = function(self) self.updates = self.updates + 1 end,
    draw = function() error("hidden menu drawn") end,
  }
  local overlay = { draws = 0,
    draw = function(self) self.draws = self.draws + 1 end }
  game = setmetatable({
    stack = stack, world = { map = {} }, save = { options = {} },
    inFillBoot = function() return false end,
    letterbox = function() end, paintBattleSurround = function() end,
  }, { __index = Game2 })
  local function draw(states)
    stack.states = states
    wide.draws, wide.wideDraws, overlay.draws = 0, 0, 0
    game:drawScene(1280, 720)
    T.eq(wide.wideDraws, 1, "the widescreen base is composed once")
  end
  draw({ wide })
  T.eq(wide.draws, 0, "an unobscured widescreen scene needs no panel pass")
  draw({ wide, hidden })
  T.eq(wide.draws, 0, "a hidden menu must not repaint the widescreen base")
  T.eq(stack:top(), hidden, "rendering does not change native menu ownership")
  stack:update(1 / 60)
  T.eq(hidden.updates, 1, "the hidden menu still receives input updates")
  local hiddenChild = { screenId = "BagMenu", isOpaque = true,
    draw = function() error("hidden child drawn") end }
  draw({ wide, hidden, hiddenChild })
  T.eq(wide.draws, 0, "multiple hidden menus must not trigger a panel pass")
  draw({ wide, overlay })
  T.eq(wide.draws, 1, "a visible overlay retains the existing panel pass")
  T.eq(overlay.draws, 1, "visible text is still drawn above the base")
  draw({ wide, hidden, overlay })
  T.eq(overlay.draws, 1, "visible text above a mirrored menu remains visible")
  draw({ wide, overlay, hidden })
  T.eq(overlay.draws, 1, "a hidden top must not suppress a visible lower overlay")
  overlay.isOpaque = true
  stack.states = { wide, overlay }
  wide.draws, wide.wideDraws, overlay.draws = 0, 0, 0
  game:drawScene(1280, 720)
  T.eq(wide.wideDraws, 0, "an opaque visible menu still replaces the battle")
  T.eq(overlay.draws, 1, "the opaque visible menu is drawn")
  run.release()
end

Renderer.setUISize, Renderer.beginFrame, Renderer.endFrame,
  TouchControls.draw = savedSetUISize, savedBegin, savedEnd, savedTouch

T.finish("screen_render_visible")
