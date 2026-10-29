package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = love or require("tests.love_stub")

package.loaded["src.core.Logger"] = {
  info = function() end, warn = function() end, error = function() end,
}

local g = love.graphics
love.filesystem.write = function() return true end
g.getRendererInfo = function() return "OpenGL", "4.1 stub", "stub", "stub" end
g.getSupported = function() return { glsl3 = true } end
g.flushBatch = function() end
g.validateShader = function() return true end
g.newShader = function(frag, vert)
  return { frag = frag, vert = vert, send = function() end }
end
love.timer = love.timer or {}
love.timer.getDelta = love.timer.getDelta or function() return 1 / 60 end

local ShaderFX = require("src.render.ShaderFX")
local Renderer = require("src.render.Renderer")
local Zoom = require("src.render.Zoom")

local okFx = ShaderFX.activate("main", {
  name = "lcd3x.slangp", fullPath = "tests/data/shaderfx/gl/lcd3x.slangp", converted = true,
})
eq(okFx, true, "the in-repo lcd3x grid preset activates under the stub")

local fxCalls
ShaderFX.render = function(canvas, rect, source, dpiX, dpiY, opts)
  fxCalls[#fxCalls + 1] = { rect = rect, opts = opts or {} }
end

local draws, scissor
local realDraw, realScissor = g.draw, g.setScissor
g.draw = function(img, x, y, r, sx, sy)
  draws[#draws + 1] = { img = img, x = x, y = y, sx = sx, sy = sy, clip = scissor }
end
g.setScissor = function(x, y, w, h)
  scissor = x and { x, y, w, h } or nil
end

Renderer:init()
Zoom.offset = 0

local START = { 80, 0, 80, 88, "topright" }
local TEXT = { 0, 96, 160, 48, "bottom" }

local function frame(W, H, opts)
  g.getDimensions = function() return W, H end
  g.getPixelDimensions = function() return W, H end
  Renderer:beginFrame(true)
  Renderer.uiCentered, Renderer.uiAnchorHold = false, false
  Renderer.uiShiftRight = opts.shift or false
  local vw, vh = Renderer:worldViewSize()
  if not Renderer.worldCanvas or Renderer.worldCanvas:getWidth() ~= vw
     or Renderer.worldCanvas:getHeight() ~= vh then
    Renderer.worldCanvas = g.newCanvas(vw, vh)
  end
  Renderer.worldActive = true
  for _, a in ipairs(opts.anchors or {}) do
    Renderer:setUIAnchor(a[1], a[2], a[3], a[4], a[5])
  end
  draws, scissor, fxCalls = {}, nil, {}
  local R = Renderer:frameRects()
  Renderer:endFrame(nil)
  local world, ui = nil, {}
  for _, d in ipairs(draws) do
    if d.img == Renderer.worldCanvas and not world then world = d end
    if d.img == Renderer.canvas and d.clip and d.clip[3] > 0 and d.clip[4] > 0 then
      ui[#ui + 1] = d
    end
  end
  return R, world, ui, fxCalls[1]
end

local function uiPieces(ui, R)
  local out = {}
  for _, d in ipairs(ui) do
    local key = ("%g,%g,%s"):format(d.x, d.y, table.concat(d.clip, ","))
    if not out[key] then
      out[key] = { x = d.x, y = d.y, clip = d.clip }
      out[#out + 1] = out[key]
    end
  end
  table.sort(out, function(a, b) return a.clip[2] < b.clip[2] end)
  return out
end

local function phaseChecks(tag, W, H, opts)
  local R, world, ui, fx = frame(W, H, opts)
  local U = R.Up
  check(world ~= nil, tag .. ": the world was blitted")
  check(fx ~= nil, tag .. ": the frame went through ShaderFX")
  if not (world and fx) then return end
  local px, py = world.x % U, world.y % U
  eq(fx.opts.originX % U, px, tag .. ": the grid origin shares the world's column phase")
  eq(fx.opts.originY % U, py, tag .. ": the grid origin shares the world's row phase")
  local pieces = uiPieces(ui, R)
  check(#pieces > 0, tag .. ": the UI was blitted")
  for i, p in ipairs(pieces) do
    local name = tag .. ": UI piece " .. i .. " at " .. p.clip[1] .. "," .. p.clip[2]
    eq(p.x % U, px, name .. " sits on the world's column phase")
    eq(p.y % U, py, name .. " sits on the world's row phase")
    check(p.clip[1] >= 0 and p.clip[2] >= 0
      and p.clip[1] + p.clip[3] <= W and p.clip[2] + p.clip[4] <= H,
      name .. " stays inside the window")
  end
  return R, pieces
end

local function edgeChecks(tag, W, H, R, pieces)
  local U = R.Up
  local top, bot = pieces[1], pieces[1]
  for _, p in ipairs(pieces) do
    if p.clip[2] < top.clip[2] or (p.clip[2] == top.clip[2]
       and p.clip[1] + p.clip[3] > top.clip[1] + top.clip[3]) then
      top = p
    end
    if p.clip[2] + p.clip[4] > bot.clip[2] + bot.clip[4] then bot = p end
  end
  local right = top.clip[1] + top.clip[3]
  check(right <= W and right > W - U and top.clip[2] < U,
    tag .. ": the START box stays within one GB pixel of the top right corner")
  local bottom = bot.clip[2] + bot.clip[4]
  check(bottom <= H and bottom > H - U,
    tag .. ": the text box stays within one GB pixel of the bottom edge")
end

for _, win in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 1000, 700 }, { 1001, 700 } }) do
  local W, H = win[1], win[2]
  local tag = ("%dx%d docked"):format(W, H)
  local R, pieces = phaseChecks(tag, W, H, { anchors = { START, TEXT } })
  if R and pieces[1] then edgeChecks(tag, W, H, R, pieces) end
  tag = ("%dx%d save shift"):format(W, H)
  R, pieces = phaseChecks(tag, W, H, { shift = true })
  if R and pieces[1] then
    local right = pieces[1].x + 160 * R.Ux
    check(right <= W and right > W - R.Up,
      tag .. ": the shifted canvas ends within one GB pixel of the window edge")
  end
end

local function placements(W, H, opts)
  local _, _, ui = frame(W, H, opts)
  local out = {}
  for _, p in ipairs(uiPieces(ui)) do
    out[#out + 1] = table.concat(p.clip, ",") .. "@" .. p.x .. "," .. p.y
  end
  table.sort(out)
  return table.concat(out, " ")
end

for _, win in ipairs({ { 1280, 720 }, { 960, 864 }, { 640, 576 }, { 1000, 700 }, { 1920, 1080 } }) do
  local W, H = win[1], win[2]
  for _, opts in ipairs({ { anchors = { START, TEXT } }, { shift = true } }) do
    local on = placements(W, H, opts)
    ShaderFX.deactivate("main")
    local off = placements(W, H, opts)
    local tag = ("%dx%d %s"):format(W, H, opts.shift and "save shift" or "docked")
    if (W % 160 == 0 and H % 144 == 0 and W / 160 == H / 144) or (W == 1280 and H == 720) then
      eq(on, off, tag .. ": where every phase already agrees the grid moves nothing")
    end
    check(off ~= "", tag .. ": the shader-off frame still blits the UI")
    ShaderFX.activate("main", {
      name = "lcd3x.slangp", fullPath = "tests/data/shaderfx/gl/lcd3x.slangp", converted = true,
    })
  end
end

do
  ShaderFX.deactivate("main")
  g.getDimensions = function() return 1920, 1080 end
  g.getPixelDimensions = function() return 1920, 1080 end
  Renderer.uiCentered, Renderer.uiShiftRight = false, true
  eq(Renderer:frameRects().uox, 800, "1920x1080 with no shader: the save shift stays flush at 800")
  Renderer.uiShiftRight = false
  local _, _, ui = frame(1920, 1080, { anchors = { START, TEXT } })
  local startRight
  for _, p in ipairs(uiPieces(ui)) do
    if p.clip[2] == 0 then startRight = p.clip[1] + p.clip[3] end
  end
  eq(startRight, 1920, "1920x1080 with no shader: the START box still ends at the window edge")
end

local YESNO = { 112, 56, 48, 40, "bottom" }

local function find(pieces, w, h)
  for _, p in ipairs(pieces) do
    if p.clip[3] == w and p.clip[4] == h then return p end
  end
end

for _, win in ipairs({ { 1366, 768 }, { 2048, 1536 }, { 1920, 1080 } }) do
  local W, H = win[1], win[2]
  ShaderFX.activate("main", {
    name = "lcd3x.slangp", fullPath = "tests/data/shaderfx/gl/lcd3x.slangp", converted = true,
  })
  local tag = ("%dx%d YES/NO over the dialogue box"):format(W, H)
  local R, pieces = phaseChecks(tag, W, H, { anchors = { TEXT, YESNO } })
  if R then
    local U = R.Up
    local text = find(pieces, 160 * U, 48 * U)
    local yes = find(pieces, 48 * U, 40 * U)
    check(text ~= nil and yes ~= nil, tag .. ": both boxes were blitted")
    if text and yes then
      eq(yes.clip[2] + yes.clip[4], text.clip[2], tag .. ": the YES/NO box ends exactly where the dialogue box starts")
      eq(yes.clip[1] + yes.clip[3], text.clip[1] + text.clip[3], tag .. ": and shares its right edge")
      check(text.clip[2] + text.clip[4] > H - U, tag .. ": the dialogue box stays within one GB pixel of the bottom")
    end
  end
end

local function anchor(t, clamped)
  return { x = t[1], y = t[2], w = t[3], h = t[4], anchor = t[5], windowClamped = clamped }
end

do
  ShaderFX.activate("main", {
    name = "lcd3x.slangp", fullPath = "tests/data/shaderfx/gl/lcd3x.slangp", converted = true,
  })
  local place = Renderer.placeUIAnchor
  check(place ~= nil, "anchor placement is readable")
  local text, yes, start = anchor(TEXT), anchor(YESNO), anchor(START)
  local status = anchor({ 160, 64, 120, 40, "bottom" }, true)
  local cmd = anchor({ 0, 104, 304, 40, "bottom" }, true)
  local enemy = anchor({ 8, 0, 128, 32, "top" }, true)
  local bad = { split = 0, phase = 0, corner = 0, hud = 0 }
  local first = {}
  local function miss(kind, msg)
    bad[kind] = bad[kind] + 1
    first[kind] = first[kind] or msg
  end
  local sizes = 0
  for W = 640, 2600, 41 do
    for H = 480, 1600, 23 do
      g.getDimensions = function() return W, H end
      g.getPixelDimensions = function() return W, H end
      Renderer.uiCentered, Renderer.uiAnchorHold, Renderer.uiShiftRight = false, false, false
      Renderer:setUISize(160, 144)
      local R = Renderer:frameRects()
      if place and R.gridUp then
        sizes = sizes + 1
        local U = R.Up
        local tag = ("%dx%d"):format(W, H)
        local tx, ty = place(R, text)
        local yx, yy, yw, yh = place(R, yes)
        local sx, sy, sw = place(R, start)
        if yy + yh ~= ty then miss("split", tag .. " gap " .. (ty - yy - yh)) end
        for _, v in ipairs({ { tx, R.gridX }, { yx, R.gridX }, { sx, R.gridX },
                             { ty, R.gridY }, { yy, R.gridY }, { sy, R.gridY } }) do
          if (v[1] - v[2]) % U ~= 0 then miss("phase", tag) end
        end
        if not (sx + sw <= W and sx + sw > W - U and sy >= 0 and sy < U and yx + yw <= W) then
          miss("corner", tag)
        end
        Renderer.uiAnchorHold = true
        Renderer:setUISize(304, 144)
        R = Renderer:frameRects()
        if R.gridUp then
          local _, cy = place(R, cmd)
          local _, hy, _, hh = place(R, status)
          local ex, ey = place(R, enemy)
          if hy + hh ~= cy or (ey - R.gridY) % R.Up ~= 0 or (ex - R.gridX) % R.Up ~= 0 then
            miss("hud", tag .. " gap " .. (cy - hy - hh))
          end
        end
      end
    end
  end
  Renderer:setUISize(160, 144)
  Renderer.uiAnchorHold = false
  check(sizes > 1000, "the sweep covers " .. sizes .. " shaded window sizes")
  eq(bad.split, 0, "sweep: the YES/NO box never comes off the dialogue box (" .. tostring(first.split) .. ")")
  eq(bad.phase, 0, "sweep: every docked box sits on the grid (" .. tostring(first.phase) .. ")")
  eq(bad.corner, 0, "sweep: the START box stays within one GB pixel of the corner (" .. tostring(first.corner) .. ")")
  eq(bad.hud, 0, "sweep: the wide battle status box stays on the command box (" .. tostring(first.hud) .. ")")
end

g.draw, g.setScissor = realDraw, realScissor
Renderer.uiAnchors, Renderer.uiShiftRight, Renderer.worldActive = nil, false, false

T.finish("shaderfx_docked_ui_grid_phase")
