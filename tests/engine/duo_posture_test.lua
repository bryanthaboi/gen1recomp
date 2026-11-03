-- iPhone Duo posture layouts (src/core/DuoPosture.lua).  Geometry measured on
-- the device: cover display 466x678 pt with an 84 pt camera/status column
-- (trailing in portrait) and a 34 pt home-indicator inset; inner display
-- ~626x890 pt flat and ~669x951 pt half open.  Port-only affordance, no
-- pokered cite.
--   luajit tests/engine/duo_posture_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Duo = require("src.core.DuoPosture")

local function safe(x, y, w, h) return { x = x, y = y, w = w, h = h } end

-- the windows a Duo actually reports, with their safe rects
local CASES = {
  { name = "cover portrait", ww = 466, wh = 678, safe = safe(0, 0, 382, 644),
    status = "closed", id = "duo_cover_portrait" },
  { name = "cover landscape", ww = 678, wh = 466, safe = safe(84, 0, 594, 432),
    status = "closed", id = "duo_cover_landscape" },
  { name = "clamshell", ww = 669, wh = 951, safe = safe(0, 0, 669, 917),
    status = "partial", id = "duo_clamshell" },
  { name = "book", ww = 951, wh = 669, safe = safe(0, 0, 951, 635),
    status = "partial", id = "duo_book" },
  { name = "flat portrait", ww = 626, wh = 890, safe = safe(0, 0, 626, 856),
    status = "open", id = "duo_flat_portrait" },
  { name = "flat landscape", ww = 890, wh = 626, safe = safe(0, 0, 890, 592),
    status = "open", id = "duo_flat_landscape" },
}

local function inside(inner, outer, slop)
  slop = slop or 0.5
  return inner.x >= outer.x - slop and inner.y >= outer.y - slop
     and inner.x + inner.w <= outer.x + outer.w + slop
     and inner.y + inner.h <= outer.y + outer.h + slop
end

local function overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w
     and a.y < b.y + b.h and b.y < a.y + a.h
end

-- a control's touch footprint; START/SELECT carry their label underneath
local function box(name, z)
  -- round controls draw a backing disc of radius 0.58w (drawIcon)
  local w = z.h and z.w * 1.08 or z.w * 1.16
  local h = z.h and z.h * 1.08 or w
  local bottom = h / 2
  if name == "start" or name == "select" then bottom = math.max(bottom, z.w * 0.66 + 12) end
  return { x = z.cx - w / 2, y = z.cy - h / 2, w = w, h = h / 2 + bottom }
end

local NAMES_GB = { "dpad", "a", "b", "start", "select", "hotbar" }
local NAMES_GBA = { "dpad", "a", "b", "start", "select", "hotbar", "l", "r" }

for _, c in ipairs(CASES) do
  for _, gen in ipairs({ 1, 3 }) do
    local p = Duo.resolve(c.ww, c.wh, c.safe, c.status, 100, { generation = gen })
    local tag = c.name .. " gen" .. gen
    -- the cover display hands back its camera column in portrait
    local usable = c.safe
    if c.id ~= "duo_cover_landscape" then usable = safe(0, 0, c.ww, c.wh) end
    check(p ~= nil, tag .. ": resolves")
    eq(p.id, c.id, tag .. ": posture id")
    if p.game then
      check(inside(p.game, usable), tag .. ": game inside the safe area")
      if p.fold and (c.status == "partial") then
        check(not overlap(p.game, p.fold), tag .. ": game clear of the fold")
      end
    end
    for _, area in ipairs(p.controls or {}) do
      check(inside(area, usable), tag .. ": control area inside the safe area")
      if p.game then check(not overlap(area, p.game), tag .. ": controls clear of the game") end
      if p.fold and c.status == "partial" then
        check(not overlap(area, p.fold), tag .. ": controls clear of the fold")
      end
    end
    if p.controls then
      for _, scale in ipairs({ 0.6, 1, 1.6 }) do
        local L = Duo.controlLayout(p, scale, gen == 3)
        local names = gen == 3 and NAMES_GBA or NAMES_GB
        local boxes = {}
        for _, n in ipairs(names) do
          local z = L[n]
          check(z ~= nil, tag .. ": has " .. n)
          local b = box(n, z)
          boxes[n] = b
          local within = false
          for _, area in ipairs(p.controls) do
            if inside(b, area, 1) then within = true end
          end
          check(within, string.format("%s x%.1f: %s inside a control area", tag, scale, n))
        end
        for i = 1, #names do
          for j = i + 1, #names do
            local a, b = names[i], names[j]
            check(not overlap(boxes[a], boxes[b]),
              string.format("%s x%.1f: %s and %s don't overlap", tag, scale, a, b))
          end
        end
        -- thumb-sized: the d-pad is at least ~2 cm on a 460 ppi panel
        check(L.dpad.w >= 110 * math.min(scale, 1),
          string.format("%s x%.1f: d-pad big enough (%.0f)", tag, scale, L.dpad.w))
      end
    end
  end
end

-- the game screen fills its half: Game Boy at >= 3x on the inner display
do
  local p = Duo.resolve(669, 951, safe(0, 0, 669, 917), "partial", 100, { generation = 1 })
  check(p.game.w >= 480 and p.game.h >= 432, "clamshell fits Game Boy at 3x")
  local f = Duo.resolve(890, 626, safe(0, 0, 890, 592), "open", 180, { generation = 1 })
  check(f.game.h >= 528 * (592 / 626) - 1, "flat landscape keeps the full height")
end

-- cover portrait runs edge to edge; cover landscape keeps its hidden inset
do
  local p = Duo.resolve(466, 678, safe(0, 0, 382, 644), "closed", 0, { generation = 1 })
  eq(p.game.w, 466, "cover portrait game spans the camera column")
  eq(p.controls[1].w, 466, "cover portrait controls span the camera column")
  local x, y, w, h = Duo.widenCover(678, 466, 84, 0, 594, 432)
  check(x == 84 and w == 594, "cover landscape keeps the leading inset")
  local _, _, w2 = Duo.widenCover(402, 874, 0, 59, 402, 781)
  eq(w2, 402, "an ordinary phone is untouched")
  local _, _, w3, h3 = Duo.widenCover(669, 951, 0, 0, 600, 917)
  check(w3 == 669 and h3 == 951, "the inner display uses the whole panel")
  local _, _, _, h4 = Duo.widenCover(466, 678, 0, 0, 382, 644)
  eq(h4, 678, "the cover display uses the home-indicator band")
end

-- book mode swaps sides for left-handed play
do
  local p = Duo.resolve(951, 669, safe(0, 0, 951, 635), "partial", 100, { swap = true })
  check(p.game.x > p.controls[1].x, "swap puts the game on the right page")
end

-- not a Duo: no hinge, or an ordinary phone's 19.5:9 window
check(Duo.resolve(466, 678, nil, nil) == nil, "no hinge keeps the stock layout")
check(Duo.resolve(402, 874, nil, "open", 180) == nil, "a normal iPhone keeps the stock layout")
check(Duo.resolve(1024, 1366, nil, "open", 180) ~= nil, "a big near-square window is still handled")

-- env override parsing and the off switch
do
  local oldGetenv = os.getenv
  os.getenv = function(k)
    if k == "POKEPORT_DUO_HINGE" then return "partial:95" end
    return oldGetenv(k)
  end
  local s, a = Duo.hinge()
  eq(s, "partial", "env forces the hinge status")
  eq(a, 95, "env forces the angle")
  os.getenv = function(k)
    if k == "POKEPORT_DUO_HINGE" then return "off" end
    return oldGetenv(k)
  end
  check(Duo.hinge() == nil, "env off disables Duo layouts")
  os.getenv = oldGetenv
end

-- the bridge is read through love.system.getHinge
do
  love.system = love.system or {}
  local old = love.system.getHinge
  love.system.getHinge = function() return "closed", 0 end
  local s = Duo.hinge()
  eq(s, "closed", "reads love.system.getHinge")
  love.system.getHinge = function() error("boom") end
  check(Duo.hinge() == nil, "a failing bridge is treated as no hinge")
  love.system.getHinge = old
end

T.finish("duo_posture")
