-- Sharp-bilinear UV mapping: Themaister / rsn8887, public domain.
local M = {}
local shaders = setmetatable({}, { __mode = "k" })
local source = [[
  extern vec2 sourceSize;
  extern vec2 prescale;
  vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
    vec2 texel = uv * sourceSize;
    vec2 center = fract(texel) - 0.5;
    vec2 region = 0.5 - 0.5 / prescale;
    vec2 f = (center - clamp(center, -region, region)) * prescale + 0.5;
    return Texel(image, (floor(texel) + f) / sourceSize) * color;
  }
]]

function M.resolve(choice, sx, sy)
  if choice == "nearest" or choice == "bilinear" or choice == "sharp" then return choice end
  if sx < 1 or sy < 1 then return "bilinear" end
  if math.abs(sx - math.floor(sx + 0.5)) < 1e-6
      and math.abs(sy - math.floor(sy + 0.5)) < 1e-6 then return "nearest" end
  return "sharp"
end

function M.draw(G, image, x, y, sx, sy, choice, physicalX, physicalY)
  physicalX, physicalY = physicalX or sx, physicalY or sy
  local mode = M.resolve(choice, physicalX, physicalY)
  local oldShader = G.getShader and G.getShader()
  local min, mag = "nearest", "nearest"
  if image.getFilter then min, mag = image:getFilter() end
  image:setFilter(mode == "nearest" and "nearest" or "linear",
    mode == "nearest" and "nearest" or "linear")
  if mode == "sharp" then
    local state = shaders[G]
    if not state then state = { shader = G.newShader(source), size = {}, scale = {} }; shaders[G] = state end
    state.size[1], state.size[2] = image:getWidth(), image:getHeight()
    state.scale[1], state.scale[2] = math.max(1, math.floor(physicalX + 1e-7)),
      math.max(1, math.floor(physicalY + 1e-7))
    state.shader:send("sourceSize", state.size)
    state.shader:send("prescale", state.scale)
    G.setShader(state.shader)
  else G.setShader() end
  G.draw(image, x, y, 0, sx, sy)
  G.setShader(oldShader)
  image:setFilter(min, mag)
  return mode
end

return M
