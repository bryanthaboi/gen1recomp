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

local phase = "pre"
local rects, texts = {}, {}
_G.love = {
  graphics = {
    setColor = function() end,
    rectangle = function(mode, x, y, w, h)
      rects[#rects + 1] = { phase = phase, x = x, y = y, w = w, h = h }
    end,
    draw = function() end,
  },
}

package.loaded["src.ui.game3.battle_chrome"] = {
  drawPlayerBox = function() phase = "box" end,
  drawEnemyBox = function() phase = "box" end,
  drawHpBar = function() phase = "bar" end,
  drawExpBar = function() end,
}
package.loaded["src.ui.game3.frlg_font"] = {
  CHAR_LV_2 = 1, CHAR_MALE = 2, CHAR_FEMALE = 3,
  draw = function(s, x, y) texts[#texts + 1] = { s = s, x = x, y = y, phase = phase } end,
  drawGlyph = function() end,
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
local TLX = Healthbox.PLAYER_CENTER.x - 32
local TLY = Healthbox.PLAYER_CENTER.y - 16

local function run(hp, maxHp)
  rects, texts, phase = {}, {}, "pre"
  Healthbox.draw("player", { name = "MEOWTH", mon = { species = 52, level = 50, hp = hp, maxHp = maxHp, gender = "X" } })
end

local function text(s)
  for _, t in ipairs(texts) do
    if t.s == s then return t end
  end
  return nil
end

local function covers(x, y, w, h)
  for _, r in ipairs(rects) do
    if r.phase == "box" and r.x <= x and r.y <= y and r.x + r.w >= x + w and r.y + r.h >= y + h then
      return true
    end
  end
  return false
end

print("[test] 105/105 prints like UpdateHpTextInHealthbox")
run(105, 105)
local cur, max = text("105/"), text("105")
check(cur ~= nil, "current HP string is \"105/\"")
check(max ~= nil, "max HP string is \"105\"")
check(cur and cur.x == TLX + 60 and cur.y == TLY + 21, "current HP at box+(60,21)" .. (cur and string.format(" got (%d,%d)", cur.x - TLX, cur.y - TLY) or ""))
check(max and max.x == TLX + 80 and max.y == TLY + 21, "max HP at box+(80,21)" .. (max and string.format(" got (%d,%d)", max.x - TLX, max.y - TLY) or ""))
check(text("105/ 105") == nil, "no combined right-aligned HP string")
check(covers(TLX + 56, TLY + 21, 40, 11), "HP window x56-95 y21-31 cream-filled before the HP bar")

print("[test] 2-digit and 1-digit values pad with spaces")
run(7, 19)
cur, max = text("  7/"), text(" 19")
check(cur and cur.x == TLX + 60 and cur.y == TLY + 21, "current \"  7/\" at box+(60,21)")
check(max and max.x == TLX + 80 and max.y == TLY + 21, "max \" 19\" at box+(80,21)")

run(45, 105)
cur = text(" 45/")
check(cur and cur.x == TLX + 60, "current \" 45/\" keeps the slash cell at box+75")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[PASS] game3 u12 healthbox hp text")
