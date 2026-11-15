-- engine/pokegear/pokegear.asm:2285 (#1267)
--   luajit tests/engine/gen2_pokedex_area_landmark_bug1267.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Chrome = require("src.ui.gen2.Chrome")
local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local Nests = require("src.core.gen2.Nests")

-- one Johto landmark (index 5), one species that nests there
local data = {
  text = require("tests.fixture_data.gen2_rom_text_s7_e"),
  gen2Encounters = {
    grass = {
      ROUTE_30 = { slots = { day = { { species = "RATTATA" } } } },
    },
  },
  gen2Maps = {
    ROUTE_30 = { landmark = 5 },
  },
  gen2Landmarks = {
    landmarks = {
      LANDMARK_ROUTE_30 = { index = 5, x = 40, y = 60, name = "ROUTE 30" },
    },
  },
}

-- sanity: Nests.landmark itself resolves the index (never broken, per the
-- verifier) so a failure below is isolated to drawArea's own lookup
eq(Nests.landmark(data, 5) and Nests.landmark(data, 5).name, "ROUTE 30",
  "Nests.landmark resolves index 5 to the ROUTE 30 record")

local function newSelf(species, region)
  local seen = { texts = {}, inverted = {}, header = {}, icons = {} }
  local self = setmetatable({
    game = { save = { position = { map = "ROUTE_30" } } },
    data = data,
    mapGfx = { maps = { johto = { 1 }, kanto = { 1 } } },
    areaRegion = region,
    areaBlink = 0,
    current = function() return { species = species or "RATTATA" } end,
    monName = function() return species or "RATTATA" end,
    fill = function() end,
    blank = function() end,
    drawTilemap = function() end,
    text = function(_, str, tx, ty)
      seen.texts[#seen.texts + 1] = { str = str, tx = tx, ty = ty }
    end,
    drawAreaHeader = function(_, title)
      seen.header[#seen.header + 1] = title
    end,
    drawNestIcon = function(_, x, y)
      seen.icons[#seen.icons + 1] = { x = x, y = y }
    end,
  }, { __index = PokedexMenu })
  return self, seen
end

local function drawText(seen)
  local out = {}
  for _, t in ipairs(seen.texts) do out[#out + 1] = t.str end
  return table.concat(out, "|")
end

do
  local self, seen = newSelf("RATTATA", "johto")
  self:drawArea()
  eq(#seen.icons, 1, "the one Johto nest gets one marker")
  local icon = seen.icons[1]
  eq(icon and icon.x, 40 - 4, "the marker sits four pixels left of the landmark")
  eq(icon and icon.y, 60 - 4, "and four pixels above it")
  eq(seen.header[1], "RATTATA'S NEST", "the only string is the nest caption")
  eq(drawText(seen), "", "nothing is printed in the dex's inverted font")

  local blinkOff = 0
  for frame = 0, 31 do
    local one, s2 = newSelf("RATTATA", "johto")
    one.areaBlink = frame
    one:drawArea()
    if #s2.icons == 0 then blinkOff = blinkOff + 1 end
  end
  eq(blinkOff, 16, "the marker is hidden for sixteen of every thirty-two frames")
end

do
  local self, seen = newSelf("RATTATA", "kanto")
  self:drawArea()
  eq(#seen.icons, 0, "no Kanto nest, so nothing blinks")
  eq(drawText(seen), "", "and no AREA UNKNOWN over the Kanto map")
  eq(seen.header[1], "RATTATA'S NEST", "the caption stays either way")
end

do
  local writes = {}
  local realThrough = Chrome.printThrough
  Chrome.printThrough = function(str, tx, ty)
    writes[#writes + 1] = { str = str, tx = tx, ty = ty }
  end
  local self = newSelf("RATTATA", "johto")
  self.drawAreaHeader = nil
  self:drawAreaHeader("RATTATA'S NEST")
  Chrome.printThrough = realThrough
  eq(#writes, 1, "the caption is placed once")
  eq(writes[1] and writes[1].tx, 2, "at hlcoord 2")
  eq(writes[1] and writes[1].ty, 0, "on row 0")
end

local function newInput()
  local input = { pressed = {} }
  function input:press(button) self.pressed[button] = true end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  return input
end

do
  local self = newSelf("RATTATA", nil)
  self.game.save.position.map = "ROUTE_30"
  eq(self:areaRegionName(), "johto",
    "the page opens on Johto whatever the player is standing in")

  local input = newInput()
  input:press("right")
  self:updateArea(input)
  eq(self:areaRegionName(), "johto",
    "right does nothing before the Hall of Fame")

  self.game.save.hallOfFame = { count = 1 }
  input:press("right")
  self:updateArea(input)
  eq(self:areaRegionName(), "kanto", "and swaps to Kanto once it has been rung")

  input:press("left")
  self:updateArea(input)
  eq(self:areaRegionName(), "johto", "left always comes back")

  input:press("b")
  self:updateArea(input)
  eq(self.view, "entry", "B returns to the entry")
end

T.finish("gen2 pokedex area landmark bug 1267")
