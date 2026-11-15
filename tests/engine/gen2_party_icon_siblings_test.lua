package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

package.loaded["src.render.Assets"] = {
  register = function() end,
  image = function(path)
    return {
      path = path,
      getDimensions = function() return 16, 32 end,
      getWidth = function() return 16 end,
      getHeight = function() return 32 end,
    }
  end,
}

love.graphics.newQuad = function(x, y, w, h)
  local q = { x = x, y = y, w = w, h = h }
  function q:setViewport(nx, ny, nw, nh)
    self.x, self.y, self.w, self.h = nx, ny, nw, nh
  end
  return q
end

local GbcPalette = require("src.render.GbcPalette")
local Runtime = require("src.mods.Runtime")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local NamingScreen = require("src.ui.gen2.NamingScreen")

local RED = { { 1, 2, 3 }, { 4, 5, 6 } }

local function newGame(trueColorIcon)
  local game = {
    data = {
      gen2Icons = {
        species = { CHIKORITA = "ICON_ODDISH", MAGNEMITE = "ICON_VOLTORB" },
        icons = {
          ICON_ODDISH = { image = "icons/oddish.png" },
          ICON_VOLTORB = { image = "icons/voltorb.png",
            trueColor = trueColorIcon or nil },
          ICON_EGG = { image = "icons/egg.png" },
        },
      },
      gen2Palettes = { partyMenu = { RED } },
      text = require("tests.fixture_data.gen2_rom_text_s7_c").text(),
    },
  }
  require("tests.fixtures.gen2_naming").fill(game.data)
  return game
end

local function mon(hp, maxHp, species)
  return { species = species or "CHIKORITA", name = "CHIKORITA",
    hp = hp, maxHp = maxHp, gender = "male" }
end

local function frameAt(menu, m, clock)
  menu.clock = clock
  return menu:iconFrame(m)
end

do
  local menu = PartyMenu.new(newGame(), { party = {} })
  local green = mon(48, 48)
  local yellow = mon(15, 48)
  local red = mon(4, 48)
  local fainted = mon(0, 48)

  T.eq(PartyMenu.iconHpBand(green), "green", "full HP is HP_GREEN")
  T.eq(PartyMenu.iconHpBand(yellow), "yellow", "15/48 is HP_YELLOW")
  T.eq(PartyMenu.iconHpBand(red), "red", "4/48 is HP_RED")
  T.eq(PartyMenu.iconHpBand(fainted), "red", "a fainted mon is HP_RED")

  T.eq(PartyMenu.iconFrameSteps(green), 9, "green pose holds duration 8 + 1")
  T.eq(PartyMenu.iconFrameSteps(yellow), 73, "yellow adds $40")
  T.eq(PartyMenu.iconFrameSteps(red), 137, "red adds $80")
  T.eq(PartyMenu.iconFrameSteps(fainted), 137, "fainted runs at the red rate")

  T.eq(frameAt(menu, green, 8), 0, "green still frame 0 at tick 8")
  T.eq(frameAt(menu, green, 9), 1, "green frame 1 at tick 9")
  T.eq(frameAt(menu, green, 18), 0, "green back to frame 0 at tick 18")
  T.eq(frameAt(menu, yellow, 72), 0, "yellow still frame 0 at tick 72")
  T.eq(frameAt(menu, yellow, 73), 1, "yellow frame 1 at tick 73")
  T.eq(frameAt(menu, red, 136), 0, "red still frame 0 at tick 136")
  T.eq(frameAt(menu, red, 137), 1, "red frame 1 at tick 137")
  T.eq(frameAt(menu, fainted, 137), 1, "a fainted icon still animates")

  menu.index = 1
  menu.clock = 16
  T.eq(menu:iconBob(1, green), -2, "selected green icon bobs 2px")
  T.eq(menu:iconBob(1, yellow), -1, "selected yellow icon bobs 1px")
  T.eq(menu:iconBob(1, red), 0, "selected red icon does not bob")
  T.eq(menu:iconBob(2, green), 0, "unselected icon does not bob")
  menu.clock = 15
  T.eq(menu:iconBob(1, green), 0, "no bob in the first 16 ticks")
end

local used
local realAvailable, realUse, realMode =
  GbcPalette.available, GbcPalette.use, GbcPalette.mode
GbcPalette.available = function() return true end
GbcPalette.use = function(colors) used[#used + 1] = colors end
GbcPalette.mode = "gbc"

do
  local menu = PartyMenu.new(newGame(true), { party = {} })
  used = {}
  menu:drawIcon(mon(48, 48), 0, 0)
  T.eq(#used, 1, "a ROM icon in the party list wears PAL_OW_RED")
  used = {}
  menu:drawIcon(mon(48, 48, "MAGNEMITE"), 0, 0)
  T.eq(#used, 0, "a trueColor icon record skips the party palette")
end

do
  used = {}
  local screen = NamingScreen.new(newGame(true),
    { type = "nickname", mon = mon(48, 48, "MAGNEMITE") })
  screen:drawPanel()
  local hitRed = false
  for _, c in ipairs(used) do if c == RED then hitRed = true end end
  T.eq(hitRed, false, "a trueColor icon skips the naming screen palette")

  used = {}
  screen = NamingScreen.new(newGame(true), { type = "nickname", mon = mon(48, 48) })
  screen:drawPanel()
  hitRed = false
  for _, c in ipairs(used) do if c == RED then hitRed = true end end
  T.eq(hitRed, true, "a ROM icon on the naming screen wears PAL_OW_RED")
end

do
  local realWants, realCall = Runtime.wantsHook, Runtime.call
  Runtime.wantsHook = function(name) return name == "pokemon.icon" end
  Runtime.call = function(_, _, _, ctx)
    ctx.trueColor = true
    return "mods/skin/icon.png"
  end
  local menu = PartyMenu.new(newGame(), { party = {} })
  used = {}
  menu:drawIcon(mon(48, 48), 0, 0)
  T.eq(#used, 0, "a pokemon.icon hook's trueColor skips the party palette")

  used = {}
  local screen = NamingScreen.new(newGame(), { type = "nickname", mon = mon(48, 48) })
  screen:drawPanel()
  local hitRed = false
  for _, c in ipairs(used) do if c == RED then hitRed = true end end
  T.eq(hitRed, false, "and the naming screen palette")
  Runtime.wantsHook, Runtime.call = realWants, realCall
end

GbcPalette.available, GbcPalette.use, GbcPalette.mode =
  realAvailable, realUse, realMode

T.finish("gen2_party_icon_siblings_test")
