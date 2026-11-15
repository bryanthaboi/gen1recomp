-- pokefirered/src/mail.c:141

local Versions = require("src.import.gba.versions")
local BgBake = require("src.import.gba.bg_bake")
local Lz77 = require("src.import.gba.lz77")

local M = {}

M.SUB = "mail"
M.FORMAT_VERSION = 1
M.DESIGN_COUNT = 12
M.REQUIRED = { "mail/manifest.lua" }
for d = 0, M.DESIGN_COUNT - 1 do
  for g = 0, 1 do
    M.REQUIRED[#M.REQUIRED + 1] = string.format("mail/design_%02d_%d.rgba", d, g)
  end
end

local W, H = 240, 160
-- pokefirered/src/mail.c:46 struct MailGfxData
local GFX_STRIDE = 20
-- pokefirered/src/mail.c:36 struct MailAttrStruct
local LAYOUT_STRIDE = 12

local function lz(rom, off)
  local out = Lz77.decompress(function(i) return rom:get(i) end, off)
  out._len = Lz77.len(out)
  return out
end

local function ptr(rom, off)
  return assert(rom:ptrOffset(rom:u32(off)), string.format("mail_extract: bad pointer at 0x%X", off))
end

local function palette(rom, off)
  local p = {}
  for i = 0, 15 do p[i] = rom:u16(off + i * 2) end
  return p
end

local function fill_map(tile)
  local map = {}
  for i = 0, 32 * 32 - 1 do
    map[i * 2 + 1] = tile % 256
    map[i * 2 + 2] = math.floor(tile / 256)
  end
  map._len = 32 * 32 * 2
  return map
end

-- pokefirered/src/mail.c:546
local function bake(gfx, pal, map, genderPal)
  local bank = {}
  for i = 0, 15 do bank[i] = pal[i] end
  -- pokefirered/src/mail.c:570
  bank[10], bank[11] = genderPal[1], genderPal[2]
  local i1, p1 = BgBake.regionIndices(gfx, map, W, H, {})
  -- pokefirered/src/mail.c:554
  local i2, p2 = BgBake.regionIndices(gfx, fill_map(1), W, H, {})
  local chunks = {}
  for i = 1, W * H do
    local c
    if p1[i] >= 0 and i1[i] ~= 0 then
      c = bank[i1[i]]
    elseif p2[i] >= 0 and i2[i] ~= 0 then
      c = bank[i2[i]]
    else
      c = bank[0]
    end
    local r, g, b = BgBake.bgr555ToRgb8(c or 0)
    chunks[i] = string.char(r, g, b, 255)
  end
  return table.concat(chunks)
end

function M.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or "data/generated/gba") .. "/" .. M.SUB
  local C = require("src.core.game3.constants").of(require("src.core.GameVersion").get())
  local gOff = assert(Versions.MAIL_GENDER_PALS, "mail_extract: no MAIL_GENDER_PALS for this game")
  local genders = {
    { rom:u16(gOff), rom:u16(gOff + 2) },
    { rom:u16(gOff + 4), rom:u16(gOff + 6) },
  }
  local lines = { "return {", string.format("  format_version = %d,", M.FORMAT_VERSION),
    string.format("  width = %d,", W), string.format("  height = %d,", H),
    string.format("  firstMailItem = %d,", C:require("items", "ITEM_ORANGE_MAIL")), "  designs = {" }
  for d = 0, M.DESIGN_COUNT - 1 do
    local e = Versions.MAIL_GFX_HEADERS + d * GFX_STRIDE
    local pal = palette(rom, ptr(rom, e))
    local gfx = lz(rom, ptr(rom, e + 4))
    local map = lz(rom, ptr(rom, e + 8))
    local files = {}
    for g = 1, 2 do
      local file = string.format("design_%02d_%d.rgba", d, g - 1)
      assert(cache:write(root .. "/" .. file, bake(gfx, pal, map, genders[g])))
      files[g] = string.format("%q", file)
    end
    lines[#lines + 1] = string.format("    [%d] = { files = { %s }, textColor = 0x%04X, textShadow = 0x%04X },",
      d, table.concat(files, ", "), rom:u16(e + 16), rom:u16(e + 18))
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  layouts = {"
  for d = 0, M.DESIGN_COUNT - 1 do
    local e = Versions.MAIL_LAYOUTS_5X2 + d * LAYOUT_STRIDE
    local n = rom:get(e)
    local lp = ptr(rom, e + 8)
    local rows = {}
    for i = 0, n - 1 do
      local b = rom:get(lp + i * 4)
      rows[#rows + 1] = string.format("{ words = %d, xOffset = %d, height = %d }",
        b % 4, math.floor(b / 4), rom:get(lp + i * 4 + 1))
    end
    lines[#lines + 1] = string.format(
      "    [%d] = { nameY = %d, nameX = %d, messageTop = %d, messageLeft = %d, lines = { %s } },",
      d, rom:get(e + 1), rom:get(e + 2), rom:get(e + 3), rom:get(e + 4), table.concat(rows, ", "))
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  assert(cache:write(root .. "/manifest.lua", table.concat(lines, "\n")))
  return { root = root, designs = M.DESIGN_COUNT }
end

function M.ready(cache, cacheRoot)
  if not (cache and cache.exists) then return false end
  for _, rel in ipairs(M.REQUIRED) do
    if not cache:exists((cacheRoot or "data/generated/gba") .. "/" .. rel) then return false end
  end
  return true
end

return M
