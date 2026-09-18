-- Pret-faithful FRLG map palette system (13 BG slots × 16 BGR555).

local Tileset = require("src.import.gba.tileset")
local NativePack = require("src.import.gba.native_pack")

local Palette = {}

Palette.NUM_PALS_IN_PRIMARY = Tileset.NUM_PALS_IN_PRIMARY -- 7
Palette.NUM_PALS_TOTAL = Tileset.NUM_PALS_TOTAL           -- 13

--- Load palettes.bin → BGR555 map (0..15).
function Palette.loadBgr555(blob)
  return NativePack.decodePalettes(blob)
end

--- Load → RGB8 tables { [slot] = { [c] = {r,g,b} } }.
function Palette.load(blob)
  local bgr, err = Palette.loadBgr555(blob)
  if not bgr then return nil, err end
  assert((bgr[0] and bgr[0][0] or -1) == 0, "pret: mapPals[0][0] must be black")
  return NativePack.palsToRgb8(bgr), bgr
end

--- Stable hash of BGR555 pals (+ optional extraBlob) for RGBA disk cache keys.
function Palette.hash(bgrPals, extraBlob)
  local parts = {}
  for p = 0, Palette.NUM_PALS_TOTAL - 1 do
    local colors = bgrPals[p] or bgrPals[0] or {}
    for c = 0, 15 do
      parts[#parts + 1] = string.format("%04x", (colors[c] or 0) % 65536)
    end
  end
  if extraBlob and type(extraBlob) == "string" then
    parts[#parts + 1] = extraBlob
  end
  -- FNV-1a 32-bit over hex stream (stable, no bit lib).
  local h = 2166136261
  local s = table.concat(parts)
  for i = 1, #s do
    h = (h * 16777619 + s:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

--- Identity tint hook (weather / time later).
function Palette.tint(rgbPals, _kind)
  return rgbPals
end

return Palette
