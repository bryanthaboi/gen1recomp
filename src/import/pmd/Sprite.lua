local Sprite = {}
local DIRECTIONS = { down = 1, right = 3, up = 5, left = 7 }

function Sprite.definition(entry)
  local meta = assert(entry.sprite, "entry has no PMD sprite metadata")
  local cells = {}
  for i = 1, entry.frames do cells[i] = { { tile = i - 1, dx = 0, dy = 0 } } end
  return {
    image = "asset_packs/pmd_red/sprites/" .. entry.file,
    frames = entry.frames, walker = true, trueColor = true,
    frameWidth = meta.frameWidth, frameHeight = meta.frameHeight,
    frameColumns = meta.frameColumns, anchorX = meta.anchorX, anchorY = meta.anchorY,
    cellWidth = meta.frameWidth, cellHeight = meta.frameHeight,
    cellColumns = meta.frameColumns, cells = cells,
  }
end

function Sprite.frame(meta, animation, direction, ticks)
  local group = meta.animations[(animation or 0) + 1] or meta.animations[1]
  local sequence = meta.sequences[group[DIRECTIONS[direction] or 1]]
  if #sequence == 0 then return { 1, 1, 0, 0, 0, 0, 0 } end
  local duration = 0
  for _, f in ipairs(sequence) do duration = duration + f[2] end
  local time = (ticks or 0) % duration
  for _, f in ipairs(sequence) do
    if time < f[2] then return f end
    time = time - f[2]
  end
  return sequence[1]
end

function Sprite.new(entry, metadata)
  metadata = metadata or entry.sprite
  local Renderer = require("src.render.SpriteRenderer")
  local renderer = Renderer.new(Sprite.definition(entry))
  renderer.pmdTicks = 0
  function renderer:step(moving)
    self.pmdTicks = moving and self.pmdTicks + 1 or 0
  end
  function renderer:draw(px, py, camX, camY, facing, phase, flip, top, forceFlip, override, row)
    local f = Sprite.frame(metadata, 0, facing, self.pmdTicks)
    return Renderer.draw(self, px + f[3], py + f[4], camX, camY,
      facing, phase, false, top, false, f[1] - 1, row)
  end
  function renderer:getPoseGeometry(facing)
    local f = Sprite.frame(metadata, 0, facing, self.pmdTicks)
    local geometry = Renderer.getFrameGeometry(self, f[1] - 1)
    geometry.x = (f[1] - 1) % entry.sprite.frameColumns * entry.sprite.frameWidth
    geometry.y = math.floor((f[1] - 1) / entry.sprite.frameColumns) * entry.sprite.frameHeight
    geometry.anchorX = geometry.anchorX - f[3]
    geometry.anchorY = geometry.anchorY - f[4]
    return geometry, false
  end
  return renderer
end

return Sprite
