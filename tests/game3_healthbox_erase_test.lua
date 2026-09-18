#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function find_upvalue(fn, name, seen)
  seen = seen or {}
  if type(fn) ~= "function" or seen[fn] then return nil end
  seen[fn] = true
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then break end
    if n == name and type(v) == "function" then return v end
    if type(v) == "function" then
      local r = find_upvalue(v, name, seen)
      if r then return r end
    end
    i = i + 1
  end
  return nil
end

local bake_rgb
do
  local ok, Extract = pcall(require, "src.import.gba.battle_chrome_extract")
  if ok and type(Extract) == "table" then
    for _, v in pairs(Extract) do
      bake_rgb = find_upvalue(v, "bgr555_to_rgb8")
      if bake_rgb then break end
    end
  end
end
if not bake_rgb then
  bake_rgb = function(c)
    local r5, g5, b5 = c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
    return math.floor(r5 * 255 / 31 + 0.5), math.floor(g5 * 255 / 31 + 0.5), math.floor(b5 * 255 / 31 + 0.5)
  end
end
check(bake_rgb ~= nil, "bake conversion available")

local function bgr(r, g, b) return r + g * 32 + b * 1024 end
local function rgb8(r5, g5, b5)
  local r, g, b = bake_rgb(bgr(r5, g5, b5))
  return { r, g, b }
end

local PAL2 = rgb8(31, 31, 27)
local PAL1 = rgb8(8, 8, 8)
local PAL3 = rgb8(27, 26, 22)
check(PAL2[1] == 255 and PAL2[2] == 255 and PAL2[3] == 222, "bake cream is 255,255,222")
check(PAL3[1] == 222 and PAL3[2] == 214 and PAL3[3] == 181, "bake shadow is 222,214,181")

local function to8(c)
  return { math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5) }
end
local function same(a, b)
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
local function fmt(c) return string.format("%d,%d,%d", c[1], c[2], c[3]) end

local log = {}
local phase = "pre"
local current = { 1, 1, 1, 1 }
_G.love = {
  graphics = {
    setColor = function(r, g, b, a)
      if type(r) == "table" then current = { r[1], r[2], r[3], r[4] or 1 }
      else current = { r, g, b, a or 1 } end
    end,
    rectangle = function(mode, x, y, w, h)
      log[#log + 1] = { phase = phase, color = current, x = x, y = y, w = w, h = h }
    end,
    draw = function() end,
  },
}

local textColors = {}
package.loaded["src.ui.game3.battle_chrome"] = {
  drawPlayerBox = function() phase = "erase" end,
  drawEnemyBox = function() phase = "erase" end,
  drawHpBar = function() phase = "post" end,
  drawExpBar = function() end,
}
package.loaded["src.ui.game3.frlg_font"] = {
  CHAR_LV_2 = 1, CHAR_MALE = 2, CHAR_FEMALE = 3,
  draw = function(_, _, _, opts) textColors[#textColors + 1] = opts and opts.colors end,
  drawGlyph = function(_, _, _, opts) textColors[#textColors + 1] = opts and opts.colors end,
  measure = function(s) return #tostring(s) * 5 end,
  advance = function() return 6 end,
}
package.loaded["src.core.game3.battle.state"] = {
  displayName = function(b) return b.name end,
}
package.loaded["src.core.game3.battle.anim"] = {
  stage = function() return { healthbox = { player = { visible = true, ox = 0 }, enemy = { visible = true, ox = 0 } } } end,
  displayHpRatio = function(_, b) return b.mon.hp / b.mon.maxHp, b.mon.hp, b.mon.maxHp end,
  displayExpRatio = function() return 0 end,
  present = function() return {} end,
}
package.loaded["src.ui.game3.summary_chrome"] = { drawStatusIcon = function() end }
package.loaded["src.core.game3.summary_data"] = { statusAilment = function() return 0 end }
package.loaded["src.core.game3.pokemon"] = { gender = function() return nil end }

local Healthbox = require("src.core.game3.battle.healthbox")

local function run(side, name)
  log, textColors, phase = {}, {}, "pre"
  Healthbox.draw(side, {
    name = name,
    mon = { species = 4, level = 5, hp = 7, maxHp = 19, gender = "X" },
  })
  local erased = {}
  for _, e in ipairs(log) do
    if e.phase == "erase" then erased[#erased + 1] = e end
  end
  return erased
end

for _, side in ipairs({ "player", "enemy" }) do
  print("[test] " .. side .. " placeholder erase uses bake cream")
  local erased = run(side, side == "player" and "ABC" or "PIDGEY")
  check(#erased > 0, side .. " erase painted pixels (" .. #erased .. ")")
  local bad
  for _, e in ipairs(erased) do
    if not same(to8(e.color), PAL2) then bad = e break end
  end
  check(bad == nil, side .. " erase color == " .. fmt(PAL2) .. (bad and (" got " .. fmt(to8(bad.color))) or ""))

  print("[test] " .. side .. " text colors use bake ink/shadow")
  local c = textColors[1]
  check(c and same(to8(c.fg), PAL1), side .. " text fg == " .. fmt(PAL1) .. (c and (" got " .. fmt(to8(c.fg))) or ""))
  check(c and same(to8(c.shadow), PAL3), side .. " text shadow == " .. fmt(PAL3) .. (c and (" got " .. fmt(to8(c.shadow))) or ""))
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
