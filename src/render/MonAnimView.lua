-- ../pokecrystal/engine/gfx/pic_animation.asm:79-89 AnimateFrontpic

local Assets = require("src.render.Assets")
local MonAnim = require("src.render.MonAnim")
local Unown = require("src.core.gen2.Unown")

local MonAnimView = {}
MonAnimView.__index = MonAnimView

-- ../pokecrystal/engine/gfx/load_pics.asm:105-131
function MonAnimView.replaced(vanilla, resolved)
  if type(vanilla) ~= "string" then return false end
  if type(resolved) == "string" and resolved ~= vanilla then return true end
  return Assets.resolve(vanilla) ~= vanilla
end

-- ../pokecrystal/engine/events/halloffame.asm:225-238
function MonAnimView.animData(def, mon)
  if not def then return nil end
  local data = def.anim
  if mon and mon.species == Unown.SPECIES and def.letters then
    local entry = def.letters[Unown.name(Unown.monLetter(mon))]
    if entry and entry.anim then data = entry.anim end
  end
  return data
end

-- ../pokecrystal/engine/gfx/load_pics.asm:132-158
function MonAnimView.start(def, mon, scene, imageFn, onCry, opts)
  local data = MonAnimView.animData(def, mon)
  if not (data and data.tiles and imageFn) then return nil end
  local path, trueColor = data.sheet, false
  if opts and opts.resolve and type(path) == "string" then
    path, trueColor = opts.resolve(path)
    if type(path) ~= "string" or path == "" then path = data.sheet end
  end
  if opts and opts.staticReplaced
     and not MonAnimView.replaced(data.sheet, path) then
    return nil
  end
  local sheet = imageFn(path)
  if not sheet then return nil end
  local runner = MonAnim.new(data, scene, onCry)
  if not runner then return nil end
  return setmetatable({
    runner = runner,
    sheet = sheet,
    size = data.tiles * 8,
    quads = {},
    trueColor = trueColor and true or false,
  }, MonAnimView)
end

function MonAnimView:step()
  self.runner:update()
  return self.runner:finished()
end

function MonAnimView:finished() return self.runner:finished() end

function MonAnimView:currentFrame() return self.runner:currentFrame() end

-- ../pokecrystal/engine/gfx/pic_animation.asm:431-435
function MonAnimView:frame()
  local frame = self.runner:currentFrame()
  if frame <= 0 then return nil end
  local quad = self.quads[frame]
  if not quad then
    local w, h = self.sheet:getDimensions()
    if (frame + 1) * self.size > h then return nil end
    quad = love.graphics.newQuad(0, frame * self.size, self.size, self.size,
      w, h)
    self.quads[frame] = quad
  end
  return self.sheet, quad, self.size
end

return MonAnimView
