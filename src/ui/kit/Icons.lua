-- Lucide ISC/Feather MIT icons, rasterized offline into one shared texture.
local Icons = {}
local names = { "settings", "x", "arrow-left-right", "puzzle", "search",
  "globe", "paintbrush", "download", "pencil", "folder", "upload",
  "file-pen-line", "trash", "check", "chevron-right", "lock", "lock-open",
  "mail" }
local atlas, quads
Icons.NAMES = names

function Icons.draw(name, x, y, size, color, alpha)
  local g = love and love.graphics
  if not g or not g.newQuad or not g.newImage then return end
  if not atlas then
    atlas = g.newImage("assets/launcher/lucide/icons.png")
    if atlas.setFilter then atlas:setFilter("linear", "linear") end
    quads = {}
    for i, id in ipairs(names) do
      quads[id] = g.newQuad((i - 1) * 96, 0, 96, 96, #names * 96, 96)
    end
  end
  local quad = quads[name]
  if not quad then return end
  g.setColor(color[1] / 255, color[2] / 255, color[3] / 255, alpha or 1)
  g.draw(atlas, quad, x, y, 0, size / 96, size / 96)
end

return Icons
