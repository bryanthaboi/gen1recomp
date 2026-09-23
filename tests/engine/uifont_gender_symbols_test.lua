package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, label)
  if cond then
    print("ok   " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label)
  end
end

local created = {}
love = {
  filesystem = {
    newFileData = function(contents, name)
      return { contents = contents, name = name }
    end,
  },
  graphics = {
    newFont = function(src, size)
      local f = { src = src, size = size }
      function f:setFilter() end
      function f:setFallbacks(...) self.fallbacks = { ... } end
      created[#created + 1] = f
      return f
    end,
  },
}

local UiFont = require("src.render.UiFont")

local function u16(s, i) local a, b = s:byte(i, i + 1) return a * 256 + b end
local function u32(s, i) return u16(s, i) * 65536 + u16(s, i + 2) end
local function s16(s, i) local v = u16(s, i) return v >= 32768 and v - 65536 or v end

local function tableOf(ttf, tag)
  for i = 0, u16(ttf, 5) - 1 do
    local rec = 13 + i * 16
    if ttf:sub(rec, rec + 3) == tag then
      return ttf:sub(u32(ttf, rec + 8) + 1, u32(ttf, rec + 8) + u32(ttf, rec + 12))
    end
  end
end

local function glyphIndex(cmap, cp)
  local sub = u32(cmap, 9) + 1
  local segX2 = u16(cmap, sub + 6)
  local ends = sub + 14
  local starts = ends + segX2 + 2
  local deltas = starts + segX2
  for k = 0, segX2 / 2 - 1 do
    local e, st = u16(cmap, ends + 2 * k), u16(cmap, starts + 2 * k)
    if st <= cp and cp <= e then
      return (cp + s16(cmap, deltas + 2 * k)) % 65536
    end
  end
  return 0
end

check(type(UiFont.symbolFontData) == "function", "UiFont builds a symbol face")
local ttf = type(UiFont.symbolFontData) == "function" and UiFont.symbolFontData() or ""
local cmap, loca, glyf = tableOf(ttf, "cmap"), tableOf(ttf, "loca"), tableOf(ttf, "glyf")
check(cmap and loca and glyf, "symbol face has cmap/loca/glyf")

if cmap and loca and glyf then
  for _, cp in ipairs({ 0x2642, 0x2640 }) do
    local gid = glyphIndex(cmap, cp)
    check(gid > 0, ("U+%04X maps to a glyph"):format(cp))
    local off, nextOff = u32(loca, gid * 4 + 1), u32(loca, gid * 4 + 5)
    check(nextOff > off and s16(glyf, off + 1) >= 3,
      ("U+%04X has an outline"):format(cp))
  end
  check(glyphIndex(cmap, 0x41) == 0, "Latin stays on the primary face")
end

local primary = love.graphics.newFont(13)
UiFont.attach(primary, 13)
local chain = primary.fallbacks or {}
local symbols
for _, f in ipairs(chain) do
  if type(f.src) == "table" and f.src.name == "UiSymbols.ttf" then symbols = f end
end
check(symbols ~= nil, "attach chains the symbol face onto launcher fonts")
check(symbols and symbols.size == 13, "symbol face matches the primary em size")
check(chain[1] and chain[1].src == "assets/fonts/plainpixel/PlainPixel-Regular.ttf",
  "Plain Pixel stays first in the chain")

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("uifont gender symbols: all passed")
