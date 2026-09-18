-- Pure ROM extractor for GBA FireRed font glyphs, widths, and text window chrome.
-- Extracts:
--   1) latin_normal font (512 glyphs @ 0x1FF300, widths @ 0x207300) -> 256x512 FG/Shadow
--   2) latin_small font (288 glyphs @ 0x1EAF00, widths @ 0x1EEF00) -> 256x288 FG/Shadow
--   3) down_arrows prompt icon (8 frames 16x16 @ 0x1EA14C) -> 128x16 FG
--   4) menu_message dialogue frame (18 4bpp tiles @ 0x41F1C8, stdpal_0 @ 0x471DEC) -> 48x24 RGBA
--   5) std menu frame (9 4bpp tiles @ 0x471A4C, stdpal_3 @ 0x471E4C) -> 24x24 RGBA
--   6) signpost frame (19 4bpp tiles @ 0x470B0C, stdpal_1 @ 0x471E0C) -> 40x32 RGBA
-- 100% self-contained: zero external files or assets required.

local Versions = require("src.import.gba.versions")

local TextChromeExtract = {}

TextChromeExtract.CACHE_SUB = "chrome"
TextChromeExtract.FORMAT_VERSION = 1

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

local function read_pal(rom, offset)
  local pal = {}
  for i = 0, 15 do
    local b0 = rom:get(offset + i * 2) or 0
    local b1 = rom:get(offset + i * 2 + 1) or 0
    local c = b0 + b1 * 256
    local r, g, b = bgr555_to_rgb8(c)
    pal[i] = { r, g, b }
  end
  return pal
end

local function unpack_tile16(rom, offset)
  local pix = {}
  for y = 0, 7 do
    pix[y] = {}
    for x = 0, 7 do
      local byte_i = y * 2 + (1 - math.floor(x / 4))
      local shift = (3 - (x % 4)) * 2
      local byte = rom:get(offset + byte_i) or 0
      local val = math.floor(byte / (2 ^ shift)) % 4
      pix[y][x] = val
    end
  end
  return pix
end

--- Decode latin_normal font: 512 glyphs (each is four 8x8 2bpp tiles in 16x16 layout)
function TextChromeExtract.extractLatinNormal(rom)
  local baseGfx = 0x1FF300
  local baseWidths = 0x207300
  local glyphCount = 512
  local cols = 16
  local rows = math.floor((glyphCount + cols - 1) / cols)
  local sheetW, sheetH = cols * 16, rows * 16

  local fgPixels = {}
  local shPixels = {}
  for i = 1, sheetW * sheetH * 4 do
    fgPixels[i] = 0
    shPixels[i] = 0
  end

  local widths = {}
  for gid = 0, glyphCount - 1 do
    local gOff = baseGfx + gid * 64
    local t0 = unpack_tile16(rom, gOff)
    local t1 = unpack_tile16(rom, gOff + 16)
    local t2 = unpack_tile16(rom, gOff + 32)
    local t3 = unpack_tile16(rom, gOff + 48)

    local ox = (gid % cols) * 16
    local oy = math.floor(gid / cols) * 16

    local subTiles = {
      { tx = 0, ty = 0, t = t0 },
      { tx = 8, ty = 0, t = t1 },
      { tx = 0, ty = 8, t = t2 },
      { tx = 8, ty = 8, t = t3 },
    }
    for _, sub in ipairs(subTiles) do
      for y = 0, 7 do
        for x = 0, 7 do
          local v = sub.t[y][x]
          local px = ox + sub.tx + x
          local py = oy + sub.ty + y
          local pi = (py * sheetW + px) * 4 + 1
          if v == 1 then
            fgPixels[pi] = 255
            fgPixels[pi + 1] = 255
            fgPixels[pi + 2] = 255
            fgPixels[pi + 3] = 255
          elseif v == 2 then
            shPixels[pi] = 255
            shPixels[pi + 1] = 255
            shPixels[pi + 2] = 255
            shPixels[pi + 3] = 255
          end
        end
      end
    end
    widths[gid] = rom:get(baseWidths + gid) or 6
  end

  local fgChars, shChars = {}, {}
  for i = 1, sheetW * sheetH * 4 do
    fgChars[i] = string.char(fgPixels[i] or 0)
    shChars[i] = string.char(shPixels[i] or 0)
  end

  return {
    fgRgba = table.concat(fgChars),
    shRgba = table.concat(shChars),
    width = sheetW,
    height = sheetH,
    widths = widths,
  }
end

--- Decode latin_small font: 288 glyphs (each is two 8x8 2bpp tiles in 8x16 layout)
function TextChromeExtract.extractLatinSmall(rom)
  local baseGfx = 0x1EAF00
  local baseWidths = 0x1EEF00
  local glyphCount = 288 -- 0x120
  local cols = 16
  local rows = math.floor((glyphCount + cols - 1) / cols) -- 18
  local sheetW, sheetH = cols * 16, rows * 16 -- 256x288

  local fgPixels = {}
  local shPixels = {}
  for i = 1, sheetW * sheetH * 4 do
    fgPixels[i] = 0
    shPixels[i] = 0
  end

  local widths = {}
  for gid = 0, glyphCount - 1 do
    local gOff = baseGfx + gid * 32
    local t0 = unpack_tile16(rom, gOff)
    local t1 = unpack_tile16(rom, gOff + 16)

    local ox = (gid % cols) * 16
    local oy = math.floor(gid / cols) * 16

    local subTiles = {
      { tx = 0, ty = 0, t = t0 },
      { tx = 0, ty = 8, t = t1 },
    }
    for _, sub in ipairs(subTiles) do
      for y = 0, 7 do
        for x = 0, 7 do
          local v = sub.t[y][x]
          local px = ox + sub.tx + x
          local py = oy + sub.ty + y
          local pi = (py * sheetW + px) * 4 + 1
          if v == 1 then
            fgPixels[pi] = 255
            fgPixels[pi + 1] = 255
            fgPixels[pi + 2] = 255
            fgPixels[pi + 3] = 255
          elseif v == 2 then
            shPixels[pi] = 255
            shPixels[pi + 1] = 255
            shPixels[pi + 2] = 255
            shPixels[pi + 3] = 255
          end
        end
      end
    end
    widths[gid] = rom:get(baseWidths + gid) or 4
  end

  local fgChars, shChars = {}, {}
  for i = 1, sheetW * sheetH * 4 do
    fgChars[i] = string.char(fgPixels[i] or 0)
    shChars[i] = string.char(shPixels[i] or 0)
  end

  return {
    fgRgba = table.concat(fgChars),
    shRgba = table.concat(shChars),
    width = sheetW,
    height = sheetH,
    widths = widths,
  }
end

--- Decode down_arrows: 8 frames of 16x16 (sDownArrowTiles @ 0x1EA14C in FireRed)
function TextChromeExtract.extractDownArrows(rom)
  local baseGfx = 0x1EA14C
  local sheetW, sheetH = 128, 16
  local pal = {
    [0] = { 0, 0, 0, 0 },
    [1] = { 0, 0, 0, 0 },
    [2] = { 48, 48, 48, 255 },    -- dark shadow
    [3] = { 213, 213, 205, 255 }, -- highlight
    [4] = { 230, 8, 8, 255 },      -- red arrow
    [5] = { 255, 189, 115, 255 },
    [6] = { 32, 156, 8, 255 },
    [7] = { 148, 246, 148, 255 },
    [8] = { 49, 82, 205, 255 },
    [9] = { 164, 197, 246, 255 },  -- light blue shadow (for dark arrow)
  }

  local pixels = {}
  for i = 1, sheetW * sheetH * 4 do pixels[i] = 0 end

  for ty = 0, 1 do
    for tx = 0, 15 do
      local tileIdx = ty * 16 + tx
      local tileOff = baseGfx + tileIdx * 32
      for row = 0, 7 do
        for col = 0, 7, 2 do
          local byte = (rom and rom:get(tileOff + row * 4 + math.floor(col / 2))) or 0
          local p0 = byte % 16
          local p1 = math.floor(byte / 16) % 16

          local px0 = tx * 8 + col
          local py0 = ty * 8 + row
          local pi0 = (py0 * sheetW + px0) * 4 + 1
          local c0 = pal[p0] or pal[0]
          pixels[pi0] = c0[1]
          pixels[pi0 + 1] = c0[2]
          pixels[pi0 + 2] = c0[3]
          pixels[pi0 + 3] = c0[4]

          local px1 = tx * 8 + col + 1
          local pi1 = (py0 * sheetW + px1) * 4 + 1
          local c1 = pal[p1] or pal[0]
          pixels[pi1] = c1[1]
          pixels[pi1 + 1] = c1[2]
          pixels[pi1 + 2] = c1[3]
          pixels[pi1 + 3] = c1[4]
        end
      end
    end
  end

  local chunks = {}
  for i = 1, sheetW * sheetH * 4 do
    chunks[i] = string.char(pixels[i] or 0)
  end
  return {
    rgba = table.concat(chunks),
    width = sheetW,
    height = sheetH,
  }
end

-- pokefirered/src/text.c:32
function TextChromeExtract.extractTextCursor(rom)
  local baseGfx, basePal = 0x1EA54C, 0x3CC2E4
  local pal = { [0] = { 0, 0, 0, 0 } }
  for i = 1, 15 do
    local lo = (rom and rom:get(basePal + i * 2)) or 0
    local hi = (rom and rom:get(basePal + i * 2 + 1)) or 0
    local v = lo + hi * 256
    local function c5(n) return math.floor((n % 32) * 255 / 31 + 0.5) end
    pal[i] = { c5(v), c5(math.floor(v / 32)), c5(math.floor(v / 1024)), 255 }
  end
  local pixels = {}
  for t = 0, 3 do
    local ox, oy = (t % 2) * 8, math.floor(t / 2) * 8
    for row = 0, 7 do
      for col = 0, 7 do
        local byte = (rom and rom:get(baseGfx + t * 32 + row * 4 + math.floor(col / 2))) or 0
        local idx = (col % 2 == 0) and (byte % 16) or math.floor(byte / 16)
        local c = pal[idx]
        local pi = ((oy + row) * 16 + ox + col) * 4
        pixels[pi + 1], pixels[pi + 2], pixels[pi + 3], pixels[pi + 4] = c[1], c[2], c[3], c[4]
      end
    end
  end
  local chunks = {}
  for i = 1, 16 * 16 * 4 do chunks[i] = string.char(pixels[i] or 0) end
  return { rgba = table.concat(chunks), width = 16, height = 16 }
end

--- Decode 4bpp tile frame with given palette
local function decode_4bpp_frame(rom, offset, tilesW, tilesH, pal, maxTiles)
  local w = tilesW * 8
  local h = tilesH * 8
  maxTiles = maxTiles or (tilesW * tilesH)
  local chunks = {}
  local totalPixels = w * h
  for i = 1, totalPixels do
    chunks[i] = string.char(0, 0, 0, 0)
  end

  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local tileIndex = ty * tilesW + tx
      if tileIndex < maxTiles then
        local tileOff = offset + tileIndex * 32
        for y = 0, 7 do
          for bx = 0, 3 do
            local byte = rom:get(tileOff + y * 4 + bx) or 0
            local p0 = byte % 16
            local p1 = math.floor(byte / 16) % 16
            local px0 = tx * 8 + bx * 2
            local px1 = px0 + 1
            local py = ty * 8 + y

            local pi0 = py * w + px0 + 1
            if p0 > 0 and pal[p0] then
              local c = pal[p0]
              chunks[pi0] = string.char(c[1], c[2], c[3], 255)
            else
              chunks[pi0] = string.char(0, 0, 0, 0)
            end

            local pi1 = py * w + px1 + 1
            if p1 > 0 and pal[p1] then
              local c = pal[p1]
              chunks[pi1] = string.char(c[1], c[2], c[3], 255)
            else
              chunks[pi1] = string.char(0, 0, 0, 0)
            end
          end
        end
      end
    end
  end

  return {
    rgba = table.concat(chunks),
    width = w,
    height = h,
  }
end

function TextChromeExtract.extractMenuMessage(rom)
  local pal0 = read_pal(rom, 0x471DEC)
  return decode_4bpp_frame(rom, 0x41F1C8, 6, 3, pal0, 18)
end

function TextChromeExtract.extractStdFrame(rom)
  local pal3 = read_pal(rom, 0x471E4C)
  return decode_4bpp_frame(rom, 0x471A4C, 3, 3, pal3, 9)
end

local KEYPAD_PALETTE = {
  { 255, 255, 255 }, -- 0: transparent (alpha = 0)
  { 255, 255, 255 }, -- 1: white
  { 98, 98, 98 },    -- 2: dark grey (outline/shadow)
  { 213, 213, 205 }, -- 3: light grey
  { 230, 8, 8 },     -- 4: red (A button)
  { 255, 189, 115 }, -- 5: light orange
  { 32, 156, 8 },    -- 6: green (B button)
  { 148, 246, 148 }, -- 7: light green
  { 49, 82, 205 },   -- 8: blue (DPAD arrows)
  { 164, 197, 246 }, -- 9: light blue
  { 0, 0, 0 },       -- 10
  { 0, 0, 0 },       -- 11
  { 0, 0, 0 },       -- 12
  { 0, 0, 0 },       -- 13
  { 0, 0, 0 },       -- 14
  { 0, 0, 0 },       -- 15
}

function TextChromeExtract.extractKeypadIcons(rom)
  local off = Versions.KEYPAD_ICONS_GFX or 0x1EA700
  local w, h = 128, 32
  local tilesX, tilesY = 16, 4
  local chunks = {}
  local get = function(i) return rom and rom.get and rom:get(i) or 0 end

  local pixels = {}
  for i = 1, w * h do pixels[i] = 0 end

  local tileIdx = 0
  for ty = 0, tilesY - 1 do
    for tx = 0, tilesX - 1 do
      local tileOff = off + tileIdx * 32
      tileIdx = tileIdx + 1
      for y = 0, 7 do
        for bx = 0, 3 do
          local byte = get(tileOff + y * 4 + bx)
          local p0 = byte % 16
          local p1 = math.floor(byte / 16) % 16
          local px0 = tx * 8 + bx * 2
          local px1 = px0 + 1
          local py = ty * 8 + y
          pixels[py * w + px0 + 1] = p0
          pixels[py * w + px1 + 1] = p1
        end
      end
    end
  end

  for i = 1, w * h do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local c = KEYPAD_PALETTE[idx + 1] or { 255, 255, 255 }
      chunks[i] = string.char(c[1], c[2], c[3], 255)
    end
  end

  return {
    rgba = table.concat(chunks),
    width = w,
    height = h,
  }
end

function TextChromeExtract.extractSignpostFrame(rom)
  local pal1 = read_pal(rom, 0x471E0C)
  return decode_4bpp_frame(rom, 0x470B0C, 5, 4, pal1, 19)
end

local function format_widths_lua(widths, comment)
  local lines = {
    "-- " .. tostring(comment),
    "-- Extracted directly from ROM — do not hand-edit.",
    "return {",
  }
  local maxKey = 0
  for k in pairs(widths) do if k > maxKey then maxKey = k end end
  for i = 0, maxKey do
    local comma = (i < maxKey) and "," or ""
    lines[#lines + 1] = string.format("  [%d] = %d%s", i, widths[i] or 0, comma)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

TextChromeExtract.USER_FRAMES_TABLE = 0x471E8C -- pokefirered/src/text_window_graphics.c:42
TextChromeExtract.USER_FRAME_COUNT = 10

local function read_ptr(rom, offset)
  local v = 0
  for i = 3, 0, -1 do
    v = v * 256 + (rom:get(offset + i) or 0)
  end
  return v - 0x08000000
end

function TextChromeExtract.extractUserFrame(rom, frameType)
  local entry = TextChromeExtract.USER_FRAMES_TABLE + frameType * 8
  local tiles = read_ptr(rom, entry)
  local pal = read_pal(rom, read_ptr(rom, entry + 4))
  return decode_4bpp_frame(rom, tiles, 3, 3, pal, 9)
end

local function write_cache(cache, rel, data)
  if type(cache) == "table" and type(cache.write) == "function" then
    local ok, res = pcall(function() return cache:write(rel, data) end)
    if ok and res ~= nil then return res end
    return cache.write(rel, data)
  end
end

function TextChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = opts.cacheRoot or "data/generated/gba"
  local cDir = root .. "/" .. TextChromeExtract.CACHE_SUB
  local fDir = cDir .. "/fonts"

  -- 1) Fonts
  local norm = TextChromeExtract.extractLatinNormal(rom)
  write_cache(cache, fDir .. "/latin_normal_fg.rgba", norm.fgRgba)
  write_cache(cache, fDir .. "/latin_normal_shadow.rgba", norm.shRgba)
  write_cache(cache, fDir .. "/latin_widths.lua", format_widths_lua(norm.widths, "sFontNormalLatinGlyphWidths (FireRed @ 0x207300)"))

  local small = TextChromeExtract.extractLatinSmall(rom)
  write_cache(cache, fDir .. "/latin_small_fg.rgba", small.fgRgba)
  write_cache(cache, fDir .. "/latin_small_shadow.rgba", small.shRgba)
  write_cache(cache, fDir .. "/latin_small_widths.lua", format_widths_lua(small.widths, "sFontSmallLatinGlyphWidths (FireRed @ 0x1EEF00)"))

  local arrows = TextChromeExtract.extractDownArrows(rom)
  write_cache(cache, fDir .. "/down_arrows_fg.rgba", arrows.rgba)
  write_cache(cache, fDir .. "/text_cursor.rgba", TextChromeExtract.extractTextCursor(rom).rgba)

  local kp = TextChromeExtract.extractKeypadIcons(rom)
  write_cache(cache, root .. "/keypad_icons.rgba", kp.rgba)
  write_cache(cache, cDir .. "/keypad_icons.rgba", kp.rgba)
  write_cache(cache, fDir .. "/keypad_icons.rgba", kp.rgba)

  -- 2) Window Chrome
  local dlg = TextChromeExtract.extractMenuMessage(rom)
  write_cache(cache, cDir .. "/menu_message_rgba.rgba", dlg.rgba)

  local std = TextChromeExtract.extractStdFrame(rom)
  write_cache(cache, cDir .. "/std_rgba.rgba", std.rgba)

  local sign = TextChromeExtract.extractSignpostFrame(rom)
  write_cache(cache, cDir .. "/signpost_rgba.rgba", sign.rgba)

  for i = 0, TextChromeExtract.USER_FRAME_COUNT - 1 do
    local user = TextChromeExtract.extractUserFrame(rom, i)
    write_cache(cache, cDir .. "/user_frame_" .. i .. ".rgba", user.rgba)
  end

  -- 3) Manifest
  local manifestContent = table.concat({
    "return {",
    "  formatVersion = 1,",
    "  fonts = {",
    "    latin_normal = { width = 256, height = 512, glyphs = 512 },",
    "    latin_small = { width = 256, height = 288, glyphs = 288 },",
    "    down_arrows = { width = 128, height = 16, frames = 8 },",
    "  },",
    "  frames = {",
    "    menu_message = { width = 48, height = 24, tilesW = 6, tilesH = 3 },",
    "    std = { width = 24, height = 24, tilesW = 3, tilesH = 3 },",
    "    signpost = { width = 40, height = 32, tilesW = 5, tilesH = 4 },",
    "  },",
    "}",
    "",
  }, "\n")
  write_cache(cache, cDir .. "/manifest.lua", manifestContent)

  return true
end

return TextChromeExtract
