#!/usr/bin/env luajit
-- Pokemon Center heal: pret screen OAM + centerToCorner parity.

package.path = "./?.lua;./?/init.lua;" .. package.path

local Heal = require("src.core.game3.pokecenter_heal")

package.loaded["src.core.game3.runtime"] = {
  getSession = function()
    return { party = { {}, {} } }
  end,
}
package.loaded["src.core.game3.party"] = { size = function(p) return #p end }
package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playFanfare = function() end,
  isFanfareFinished = function() return true end,
  role = function() return 256 end,
}
package.loaded["src.core.game3.se_ids"] = { SE_BALL = 23 }

local function check(name, cond)
  if not cond then
    io.stderr:write("FAIL " .. name .. "\n")
    os.exit(1)
  end
  print("ok  " .. name)
end

-- pret: CreateSprite(93,36) 8x8 → OAM TL (89,32); slot1 + (6,0) → (95,32)
local x0, y0 = Heal._ballScreenTl(0)
local x1, y1 = Heal._ballScreenTl(1)
local x2, y2 = Heal._ballScreenTl(2)
check("ball0 OAM TL", x0 == 89 and y0 == 32)
check("ball1 +6x L→R", x1 == 95 and y1 == 32)
check("ball2 next row", x2 == 89 and y2 == 36)

-- pret: CreateSprite(128,24) 32x16 → OAM TL (112,16)
local mx, my = Heal._monitorScreenTl()
check("monitor OAM TL", mx == 112 and my == 16)

check("start", Heal.start() == true)
Heal.step()
local fx = Heal._fx
check("placed ball0 at OAM TL", fx.balls[1].x == 89 and fx.balls[1].y == 32)

local done = false
Heal.wait(function() done = true end)
local frames, maxBalls = 0, 0
for i = 1, 800 do
  Heal.step()
  frames = i
  fx = Heal._fx
  if fx then maxBalls = math.max(maxBalls, #fx.balls) end
  if done then break end
end
check("two balls", maxBalls == 2)
check("done", done)
print("pokecenter heal OAM parity ok (" .. frames .. " frames)")

-- Test FieldEffects routing
local FieldEffects = require("src.core.game3.field_effects")
check("FieldEffects.doFieldEffect starts heal", FieldEffects.doFieldEffect(25) == true)
check("FieldEffects.isFieldEffectActive is true", FieldEffects.isFieldEffectActive(25) == true)
local fldDone = false
FieldEffects.waitFieldEffect(25, function() fldDone = true end)
for i = 1, 800 do
  FieldEffects.step()
  if fldDone then break end
end
check("FieldEffects.waitFieldEffect completed", fldDone == true)
check("FieldEffects.isFieldEffectActive is false after done", FieldEffects.isFieldEffectActive(25) == false)
print("FieldEffects integration ok")
