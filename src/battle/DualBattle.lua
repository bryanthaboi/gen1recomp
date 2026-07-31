-- Dual-screen battle layout (DUAL SCREEN on).
--
-- The battle simulation, animations, HUDs, pics and menus stay BattleState's:
-- this module only re-composes them onto a 160x288 surface -- two stacked
-- Game Boy screens. The field (both mons + both HUDs) is spread across the
-- TOP screen with the enemy high and the player at the foot; the message /
-- command / move window owns the BOTTOM screen. Each element is drawn once,
-- per side, at its own DS anchor (never sliced out of a composite), so a
-- send-out or attack animation that crosses the field is not torn in two.
-- Renderer splits the 288 surface at its midpoint (144) so each half fills an
-- equal screen.

local PaletteFX = require("src.render.PaletteFX")

local DualBattle = {
  WIDTH = 160,
  HEIGHT = 288,
  SCREEN = 144,        -- one Game Boy screen; the split midpoint
}

-- how far each side's classic 160x144 coordinates shift on the top screen:
-- the enemy sits near the top, the player is pushed to the foot so the pair
-- fills the screen rather than huddling in the middle
local ENEMY_DY = 4
local PLAYER_DY = 48
-- the message/menu block (classic rows 96-144) dropped onto the bottom screen
local MENU_DY = DualBattle.SCREEN

-- Draw `fn`'s classic-coordinate content translated by (0, dy) and clipped to
-- surface rows [y, y+h). The scissor bounds the band; the translate slides the
-- classic 160x144 coordinates into it.
local function inRegion(y, h, dy, fn)
  local g = love.graphics
  local x0, y0, w0, h0
  if g.getScissor then x0, y0, w0, h0 = g.getScissor() end
  g.setScissor(0, y, DualBattle.WIDTH, h)
  g.push()
  g.translate(0, dy)
  fn()
  g.pop()
  if x0 then g.setScissor(x0, y0, w0, h0) else g.setScissor() end
end

-- The animation layer is authored in the classic 160x144 field; shift it to
-- the anchor of the side it plays on -- enemy effects stay high, player
-- effects drop to the foot with the player pic -- so a hit flash, status
-- animation or send-out lands on its mon instead of the classic position
-- (mirrors WideBattle.animationOffset, vertical instead of horizontal).
local function animOffsetY(battle)
  local sprites
  if battle.animPlaying and battle.animPlayer then
    local step = battle.animPlayer.steps[battle.animPlayer.stepIndex]
    sprites = step and step.sprites
  elseif battle.lockedBall then
    sprites = battle.lockedBall
  end
  if not sprites or #sprites == 0 then return 0 end
  local minX, maxX = math.huge, -math.huge
  for _, s in ipairs(sprites) do
    minX = math.min(minX, s.x - 8)
    maxX = math.max(maxX, s.x)
  end
  -- snap to the nearer side rather than blend: a cross-field dash would
  -- otherwise drift vertically as its sprites' center crosses the field
  local t = (maxX + minX) / 2
  return (t < 80) and PLAYER_DY or ENEMY_DY
end

function DualBattle.draw(battle)
  local g = love.graphics

  -- both screens are the field's paper, so the space the mons stand in and
  -- the room around the menu read as one battlefield, not black bars
  local m = PaletteFX.mode
  if m == "og" or m == "og_inv" or m == "classic" then
    g.setColor(1, 1, 1, 1)
  else
    g.setColor(PaletteFX.paperShade(battle.data))
  end
  g.rectangle("fill", 0, 0, DualBattle.WIDTH, DualBattle.HEIGHT)
  g.setColor(1, 1, 1, 1)

  if battle.blankForAskName then
    return
  end

  local slide = (battle.introSlide or 0) * 4

  -- side windows are their own clip, like the wide layout, so a pic is not
  -- trimmed to the classic move-menu rows
  battle.wideRegion = true
  -- TOP SCREEN: enemy high, player at the foot -- each pic drawn once
  battle:drawPicsLayer(slide, 0, ENEMY_DY, "enemy", true)
  battle:drawPicsLayer(slide, 0, PLAYER_DY, "player", true)
  battle.wideRegion = nil

  -- The two HUDs ride with their sides: the enemy's classic block (rows 0-48)
  -- stays up top, the player's (rows 56-96) drops to the foot with its pic.
  -- Shadow colorMode off for the draw so drawHPBar tints its own green/red
  -- fill: the classic path leaves it gray for the zone pass (#229), but this
  -- surface opts out of that pass, so nothing would recolor it.
  local realColorMode = battle.colorMode
  battle.colorMode = function() return false end
  inRegion(ENEMY_DY, 56, ENEMY_DY, function() battle:drawHUDs(slide) end)
  inRegion(56 + PLAYER_DY, DualBattle.SCREEN - (56 + PLAYER_DY), PLAYER_DY,
           function() battle:drawHUDs(slide) end)
  battle.colorMode = realColorMode

  -- the field FX / send-out / attack animation, shifted to the side it plays
  -- on; false so it tints its own colors (the surface opts out of the zone pass)
  local ady = animOffsetY(battle)
  inRegion(0, DualBattle.SCREEN, ady, function() battle:drawAnimLayer(false) end)

  -- BOTTOM SCREEN: the message / command / move window (classic rows 96-144)
  inRegion(MENU_DY, DualBattle.SCREEN, MENU_DY, function() battle:drawTextArea() end)
end

-- The pics and HUDs resolve their own species / paper / HP-bar colors, so the
-- colorized modes take the trueColor opt-out over the whole surface; the
-- forced-mono modes remap the finished frame and want a whole-surface gray
-- zone (like WideBattle.zones).
function DualBattle.zones()
  local w, h = DualBattle.WIDTH, DualBattle.HEIGHT
  local m = PaletteFX.mode
  if m == "og" or m == "og_inv" or m == "classic" then
    return { PaletteFX.zone(PaletteFX.GRAYS, 0, 0, w / 8 - 1, h / 8 - 1) }
  end
  return { { colors = false, x = 0, y = 0, w = w, h = h } }
end

return DualBattle
