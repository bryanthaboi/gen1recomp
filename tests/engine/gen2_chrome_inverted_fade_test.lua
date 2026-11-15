package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Font = require("src.render.Font")

local WHITE, ORANGE, RED, BLACK =
  { 255, 255, 255 }, { 255, 160, 0 }, { 160, 32, 0 }, { 0, 0, 0 }
local DEX = { WHITE, ORANGE, RED, BLACK }

local function same(a, b)
  return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function name(c)
  if same(c, WHITE) then return "white" end
  if same(c, ORANGE) then return "orange" end
  if same(c, RED) then return "red" end
  if same(c, BLACK) then return "black" end
  return "?"
end

GbcPalette.setMode("gbc")

-- ../pokecrystal/engine/pokedex/pokedex.asm:2452-2461, home/fade.asm:50-51
local function cart(palette, byte, s)
  local shades = GbcPalette.bgpShades(byte)
  return palette[shades[3 - s + 1] + 1]
end

do
  local bad
  for byte = 0, 255 do
    GbcPalette.setBgp(byte)
    local pal = Chrome.throughPalette(DEX, true)
    for s = 0, 3 do
      if not same(pal[s + 1], cart(DEX, byte, s)) then
        bad = bad or ("$%02x shade %d is %s, cart %s"):format(byte, s,
          name(pal[s + 1]), name(cart(DEX, byte, s)))
      end
    end
  end
  GbcPalette.setBgp(nil)
  T.check(bad == nil, "every rBGP byte maps the inverted font like the cart"
    .. (bad and (": " .. bad) or ""))
end

-- ../pokecrystal/home/fade.asm:112-115
local FADE = {
  { 0x90, RED, WHITE },
  { 0x40, ORANGE, WHITE },
  { 0x00, WHITE, WHITE },
}

for _, row in ipairs(FADE) do
  GbcPalette.setBgp(row[1])
  local pal = Chrome.throughPalette(DEX, true)
  T.eq(name(pal[1]), name(row[2]),
    ("$%02x: the inverted paper fades, not black"):format(row[1]))
  T.eq(name(pal[4]), name(row[3]),
    ("$%02x: the inverted ink fades"):format(row[1]))
end
GbcPalette.setBgp(nil)

do
  local pal = Chrome.throughPalette(DEX, true)
  T.eq(name(pal[1]), "black", "no byte: the dex paper is black")
  T.eq(name(pal[4]), "white", "no byte: the dex ink is white")
  local plain = Chrome.throughPalette(DEX, false)
  T.eq(name(plain[1]), "white", "no byte, uninverted: paper is colour 0")
end

do
  GbcPalette.available = function() return true end
  Font.encode = function(codes) return codes end
  Font.advanceOf = function() return 8 end
  Font.drawCode = function() end
  GbcPalette.useRaw = function() end
  local paper
  local G = love.graphics
  local realRect = G.rectangle
  G.rectangle = function(...)
    if not paper then
      local r, g, b = G.getColor()
      paper = { math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5) }
    end
    return realRect(...)
  end
  GbcPalette.setBgp(0x90)
  Chrome.printInverted({ 0x80 }, 0, 0, DEX)
  GbcPalette.setBgp(nil)
  G.rectangle = realRect
  T.eq(name(paper), "red", "printInverted under $90 lays dark red paper, not black")
end

T.finish("gen2_chrome_inverted_fade_test")
