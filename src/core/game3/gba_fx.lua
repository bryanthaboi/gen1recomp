local Fx = {}

local SRC = [[
extern float fadeY;
extern vec3 fadeColor;
extern float gray;
extern float bldy;
extern float mode;
extern float k;
extern float winOn;
extern Image winTex;
extern vec4 winRect;
extern float winBldy;
extern float bandOn;
extern float bandY;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 p = Texel(tex, tc);
  if (p.a < 0.5) discard;
  vec3 c = floor(p.rgb * 31.0 + 0.5);
  if (gray > 0.5) {
    float g = min(floor((c.r * 76.0 + c.g * 151.0 + c.b * 29.0) / 256.0), 31.0);
    if (g >= 30.0) g = 31.0;
    else if (g >= 25.0) g = 27.0;
    else if (g >= 20.0) g = 21.0;
    else if (g >= 15.0) g = 16.0;
    else if (g >= 10.0) g = 11.0;
    else if (g >= 5.0) g = 5.0;
    else g = 0.0;
    c = vec3(g);
  }
  c = c + floor((fadeColor - c) * fadeY / 16.0);
  float b = bldy;
  if (bandOn > 0.5) {
    float d = abs(floor(sc.y) - bandY);
    b = d <= 15.0 ? 15.0 - d : 0.0;
  }
  if (winOn > 0.5) {
    vec2 w = (sc - winRect.xy) / winRect.zw;
    if (w.x >= 0.0 && w.y >= 0.0 && w.x < 1.0 && w.y < 1.0 && Texel(winTex, w).a > 0.5) b = winBldy;
  }
  c = c + floor((31.0 - c) * b / 16.0);
  if (mode > 1.5) return vec4(c / 31.0 * k, 1.0);
  if (mode > 0.5) return vec4(k, k, k, 1.0);
  return vec4(c / 31.0, color.a);
}
]]

Fx.WHITE = { 31, 31, 31 }
Fx.BLACK = { 0, 0, 0 }

local shader

local function getShader()
  if shader == nil then
    if not (love and love.graphics and love.graphics.newShader) then
      shader = false
    else
      local ok, sh = pcall(love.graphics.newShader, SRC)
      shader = ok and sh or false
    end
  end
  return shader or nil
end

local function send(sh, fx, mode, k)
  local col = fx and fx.color or Fx.BLACK
  sh:send("fadeY", fx and fx.y or 0)
  sh:send("fadeColor", { col[1], col[2], col[3] })
  sh:send("gray", (fx and fx.gray) and 1 or 0)
  sh:send("bldy", fx and fx.bldy or 0)
  sh:send("mode", mode)
  sh:send("k", k or 1)
  sh:send("bandOn", (fx and fx.band) and 1 or 0)
  sh:send("bandY", (fx and fx.band) or 0)
  local win = fx and fx.objWin
  if win and win.image then
    sh:send("winOn", 1)
    sh:send("winTex", win.image)
    sh:send("winRect", { win.x, win.y, win.w, win.h })
    sh:send("winBldy", win.bldy or 0)
  else
    sh:send("winOn", 0)
  end
end

function Fx.active(fx, blend)
  if blend then return true end
  if not fx then return false end
  return (fx.y or 0) > 0 or fx.gray or (fx.bldy or 0) > 0 or fx.objWin ~= nil or fx.band ~= nil
end

function Fx.draw(drawFn, fx, blend)
  if not Fx.active(fx, blend) then
    drawFn()
    return
  end
  local sh = getShader()
  if not sh then
    drawFn()
    return
  end
  local prevShader = love.graphics.getShader()
  if blend then
    local mode, alphaMode = love.graphics.getBlendMode()
    send(sh, fx, 1, math.min(16, blend.evb or 0) / 16)
    love.graphics.setShader(sh)
    love.graphics.setBlendMode("multiply", "premultiplied")
    drawFn()
    send(sh, fx, 2, math.min(16, blend.eva or 0) / 16)
    love.graphics.setBlendMode("add", "alphamultiply")
    drawFn()
    love.graphics.setBlendMode(mode, alphaMode)
  else
    send(sh, fx, 0, 1)
    love.graphics.setShader(sh)
    drawFn()
  end
  love.graphics.setShader(prevShader)
end

function Fx.withClip(clip, fn)
  if not clip then
    fn()
    return
  end
  local sx, sy, sw, sh = love.graphics.getScissor()
  love.graphics.intersectScissor(clip.x, clip.y, math.max(0, clip.w), math.max(0, clip.h))
  fn()
  if sx then
    love.graphics.setScissor(sx, sy, sw, sh)
  else
    love.graphics.setScissor()
  end
end

return Fx
