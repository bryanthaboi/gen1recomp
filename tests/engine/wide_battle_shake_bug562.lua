-- BATTLE LAYOUT = WIDE, screen shakes (#562).
--
-- A battle sets rWY to 0 (engine/battle/core.asm), so the window
-- PredefShakeScreenVertically / PredefShakeScreenHorizontally /
-- AnimationShakeScreenHorizontallySlow displace IS the whole screen: pics,
-- both HUDs and the message window move together, which is what
-- BattleState:drawClassic does by offsetting its whole BG canvas.  The wide
-- composition used to apply fx.shakeX/shakeY to the two pic regions only, so
-- an applying-attack shake slid the monsters across a nailed-down HUD and
-- text box -- TAIL WHIP's slow 3px creep (wAnimationType 6) being the case
-- the report named.
--
-- Headless: WideBattle.draw is played into a recording love.graphics and the
-- Font / HudTiles entry points, so what is asserted is where each piece of
-- the composition landed, not pixels.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local WideBattle = require("src.battle.WideBattle")
local Font = require("src.render.Font")
local HudTiles = require("src.render.HudTiles")

-- ---------------------------------------------------------------- recorder
-- The stub's push/pop keep no transform, so the translate stack is tracked
-- here: `tx, ty` is the offset in force when a draw call is issued.  Font and
-- HudTiles are patched in place (WideBattle captured these very tables at
-- require time, so swapping package.loaded would not reach it).
local g = love.graphics
local realPush, realPop = g.push, g.pop
local tx, ty, stack = 0, 0, {}
local scissors, marks

g.push = function(...) stack[#stack + 1] = { tx, ty }; realPush(...) end
g.pop = function()
  local s = table.remove(stack)
  if s then tx, ty = s[1], s[2] end
  realPop()
end
g.translate = function(dx, dy) tx, ty = tx + (dx or 0), ty + (dy or 0) end
-- restoreScissor calls setScissor() with no arguments to clear; only a real
-- rect is a region being opened
g.setScissor = function(x, y, w, h)
  if x then scissors[#scissors + 1] = { x = x, y = y, w = w, h = h } end
end

local function mark(name) marks[#marks + 1] = { name = name, tx = tx, ty = ty } end
Font.drawBox = function() mark("box") end
Font.draw = function() mark("text") end
Font.drawCode = function() mark("code") end
Font.split = function() return {} end
Font.spansFitting = function() return math.huge end
HudTiles.tile = function() mark("tile") end
HudTiles.drawHPBar = function() mark("hpbar") end

-- A battle stripped to what the composition reads.  drawPicsLayer and
-- drawAnimLayer only record the offset they were handed, which is the whole
-- question: are the two pic regions and everything else moving as one?
local function battleWith(fx, sprites)
  return {
    data = {},
    frame = 0,
    phase = "messages",
    current = {},
    shown = {},
    fx = fx,
    enemy = { name = "GENGAR", shownHP = 60,
              mon = { level = 25, stats = { hp = 60 } } },
    player = { name = "NIDORINO", shownHP = 55,
               mon = { level = 24, stats = { hp = 55 } } },
    animPlaying = sprites ~= nil,
    animPlayer = sprites and { stepIndex = 1, steps = { { sprites = sprites } } },
    drawPicsLayer = function() mark("pics") end,
    drawAnimLayer = function() mark("anim") end,
    growInScale = function() return nil end,
    drawBallRow = function() end,
    statusLabel = function() return "" end,
    statusHUDVisible = function() return true end,
    bottomUIVisible = function() return true end,
    caughtMarkerVisible = function() return false end,
  }
end

local function draw(fx, sprites)
  tx, ty, stack = 0, 0, {}
  scissors, marks = {}, {}
  WideBattle.draw(battleWith(fx, sprites))
  return scissors, marks
end

local function marksNamed(list, name)
  local out = {}
  for _, m in ipairs(list) do if m.name == name then out[#out + 1] = m end end
  return out
end

-- Every piece of the composition drawn in wide-surface coordinates sits at
-- (dx, dy).  The two pic passes and the anim layer carry their own anchor on
-- top of the shake and are checked against it by hand.
local SELF_ANCHORED = { pics = true, anim = true }
local function everythingAt(list, dx, dy, label)
  local seen = 0
  for _, m in ipairs(list) do
    if not SELF_ANCHORED[m.name] then
      seen = seen + 1
      if m.tx ~= dx or m.ty ~= dy then
        T.check(false, ("%s: %s drew at (%d, %d), wanted (%d, %d)")
                         :format(label, m.name, m.tx, m.ty, dx, dy))
        return
      end
    end
  end
  T.check(seen >= 6,
    label .. ": the HUDs, the status bars and the message box all drew")
  T.check(true, ("%s: all %d pieces moved to (%d, %d) together")
                  :format(label, seen, dx, dy))
end

-- ------------------------------------------------------------ still screen
-- The baseline the shaken frames are measured against: the player's 160x144
-- region is inset 32px from the top of the wider field, the enemy's starts at
-- x=160, and both draw their classic-space pics at the wide anchors.
local s, m = draw(nil)
T.eq(s[1].x, 0, "unshaken, the player region clips from the left edge")
T.eq(s[1].y, 32, "unshaken, the player region starts below the foe's HUD")
T.eq(s[2].x, 160, "unshaken, the enemy region clips from the halfway mark")
T.eq(s[2].y, 0, "unshaken, the enemy region starts at the top")
local pics = marksNamed(m, "pics")
T.eq(#pics, 2, "one pics pass per side")
T.eq(pics[1].tx, 20, "unshaken, the player pic sits on the player anchor")
T.eq(pics[1].ty, 8, "unshaken, the player pic sits on the player baseline")
T.eq(pics[2].tx, 136, "unshaken, the enemy pic sits on the enemy anchor")
everythingAt(m, 0, 0, "no shake")

-- -------------------------------------------------- horizontal shake (#562)
-- TAIL WHIP is wAnimationType 6, AnimationShakeScreenHorizontallySlow b=3:
-- the screen creeps out to 3px and back, twice, in silence.  Before the fix
-- the two pic regions took the 3px and drawHUDs / drawTextArea did not, so
-- the foe glided sideways over a stationary HUD and message box.
s, m = draw({ shakeX = 3, shakeY = 0 })
T.eq(s[1].x, 3, "a horizontal shake carries the player region's clip with it")
T.eq(s[2].x, 163, "...and the enemy region's")
pics = marksNamed(m, "pics")
T.eq(pics[1].tx, 23, "the player pic rides the shake")
T.eq(pics[2].tx, 139, "the enemy pic rides the shake")
everythingAt(m, 3, 0, "3px horizontal shake")

-- ---------------------------------------------------- vertical shake (#562)
-- wAnimationType 1 (PredefShakeScreenVertically b=8) drops the whole window.
-- The region rects move with their contents, so a pic pushed toward
-- FIELD_BOTTOM is not sheared off its own window edge on the way down.
s, m = draw({ shakeX = 0, shakeY = 8 })
T.eq(s[1].y, 40, "a vertical shake carries the player region's clip down")
T.eq(s[1].h, WideBattle.FIELD_BOTTOM - 32,
  "the player region keeps its height, so the pic is not cropped short")
T.eq(s[2].y, 8, "the enemy region's clip drops the same 8px")
pics = marksNamed(m, "pics")
T.eq(pics[1].ty, 16, "the player pic drops with it")
everythingAt(m, 0, 8, "8px vertical shake")

-- --------------------------------------------------- the animations-off path
-- With ANIMATION = OFF an extracted anim that carries a shake flag falls back
-- to fx.shake, a +-2 alternation read off battle.frame; it moves the screen
-- through the same path.
s, m = draw({ shake = 24 })
T.eq(s[1].x, 2, "the animations-off fallback shakes the regions too")
everythingAt(m, 2, 0, "animations-off fallback")

-- ------------------------------------------------------- the OAM anim layer
-- Battle animation sprites are OAM, not BG, so the window shake never moves
-- them -- drawClassic draws its anim layer outside the offset for the same
-- reason.  Their own offset is WideBattle.animationOffset, and that stays put
-- while the screen under them shakes.
local sprites = { { x = 104 }, { x = 144 } }
local ax, ay = WideBattle.animationOffset(sprites)
s, m = draw({ shakeX = 3, shakeY = 0 }, sprites)
local anim = marksNamed(m, "anim")
T.eq(#anim, 1, "the anim layer drew")
T.eq(anim[1].tx, ax, "the anim layer keeps its own anchor, not the shake")
T.eq(anim[1].ty, ay, "...on both axes")
T.eq(s[#s].x, 0, "the anim region spans the field from the left edge")
T.eq(s[#s].w, WideBattle.WIDTH, "...the full wide surface")

T.finish("wide battle shake")
