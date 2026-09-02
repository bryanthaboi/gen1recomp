-- Map-pixel coverage for standard 16x16 overworld walkers, derived from pret
-- pokecrystal data/sprites/facings.asm and map_objects.asm InitSprite.
--
-- FacingStep* tables place RELATIVE_ATTRIBUTES on the bottom OAM row (y = 8).
-- InitSprite writes each OBJ at object Y + OAM_Y_OFS - 4, so that row covers
-- map pixels py+4 .. py+12.  OBJECT_SPRITE_Y_OFFSET moves the whole sprite
-- without moving the object off its tile.

local OamFootprint = {}

function OamFootprint.spriteYOffset(entity)
  return entity and (entity.spriteYOffset or 0) or 0
end

-- Bottom OAM row when IN_GRASS sets OAM_PRIO (facings.asm RELATIVE_ATTRIBUTES).
function OamFootprint.feetStrip(entity)
  local px = entity.px or 0
  local py = (entity.py or 0) + OamFootprint.spriteYOffset(entity)
  return px, py + 4, px + 16, py + 12
end

-- Full OBJ footprint for wAttrmap B_BG_PRIO (bit 7) overdraw.
function OamFootprint.spriteBBox(entity)
  local px = entity.px or 0
  local py = (entity.py or 0) + OamFootprint.spriteYOffset(entity)
  return px, py, px + 16, py + 24
end

return OamFootprint
