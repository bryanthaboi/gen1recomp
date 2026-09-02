-- pret data/sprites/facings.asm: per-facing OAM tables for standard 16x16 walkers.
-- RELATIVE_ATTRIBUTES (bit 3) on an entry means InitSprite ORs hCurSpriteOAMFlags
-- into that tile's attribute byte — IN_GRASS sets OAM_PRIO there, so only those
-- rows sit behind BG palette shades 1-3.

local OAM_XFLIP = 0x20
local RELATIVE_ATTRIBUTES = 0x08 -- RELATIVE_ATTRIBUTES_F in map_object_constants.asm

local OamFacings = {}

OamFacings.OAM_XFLIP = OAM_XFLIP
OamFacings.RELATIVE_ATTRIBUTES = RELATIVE_ATTRIBUTES

-- Each entry: { y, x, attr, tileIndex } relative to InitSprite anchor.
local function row(y, x, attr, tile)
  return { y = y, x = x, attr = attr, tile = tile }
end

local function facing(rows)
  return rows
end

-- FacingStepDown0 / FacingStepDown2 (standing down)
OamFacings.standingDown = facing({
  row(0, 0, 0, 0x00),
  row(0, 8, 0, 0x01),
  row(8, 0, RELATIVE_ATTRIBUTES, 0x02),
  row(8, 8, RELATIVE_ATTRIBUTES, 0x03),
})

OamFacings.walkDown1 = facing({
  row(0, 0, 0, 0x80),
  row(0, 8, 0, 0x81),
  row(8, 0, RELATIVE_ATTRIBUTES, 0x82),
  row(8, 8, RELATIVE_ATTRIBUTES, 0x83),
})

OamFacings.walkDown2 = facing({
  row(0, 8, OAM_XFLIP, 0x80),
  row(0, 0, OAM_XFLIP, 0x81),
  row(8, 8, RELATIVE_ATTRIBUTES + OAM_XFLIP, 0x82),
  row(8, 0, RELATIVE_ATTRIBUTES + OAM_XFLIP, 0x83),
})

OamFacings.standingUp = facing({
  row(0, 0, 0, 0x04),
  row(0, 8, 0, 0x05),
  row(8, 0, RELATIVE_ATTRIBUTES, 0x06),
  row(8, 8, RELATIVE_ATTRIBUTES, 0x07),
})

OamFacings.standingLeft = facing({
  row(0, 0, 0, 0x08),
  row(0, 8, 0, 0x09),
  row(8, 0, RELATIVE_ATTRIBUTES, 0x0a),
  row(8, 8, RELATIVE_ATTRIBUTES, 0x0b),
})

OamFacings.standingRight = facing({
  row(0, 8, OAM_XFLIP, 0x08),
  row(0, 0, OAM_XFLIP, 0x09),
  row(8, 8, RELATIVE_ATTRIBUTES + OAM_XFLIP, 0x0a),
  row(8, 0, RELATIVE_ATTRIBUTES + OAM_XFLIP, 0x0b),
})

function OamFacings.relativeAttrRows(facingTable)
  local out = {}
  for _, entry in ipairs(facingTable or {}) do
    if bit.band(entry.attr, RELATIVE_ATTRIBUTES) ~= 0 then
      out[#out + 1] = entry
    end
  end
  return out
end

function OamFacings.bottomRowY()
  return 8
end

return OamFacings
