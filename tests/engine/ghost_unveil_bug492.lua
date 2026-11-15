-- The Silph Scope unveil in the POKEMON_TOWER_6F battle (#492).
--
-- PrintBeginningBattleText .isMarowak (engine/battle/common_text.asm:49-60):
-- with the scope in the bag the battle still ENTERS disguised -- InitWildBattle
-- takes its .isGhost branch on wCurOpponent == RESTLESS_SOUL either way -- and
-- the scope only buys the unveil that is played over the disguise:
-- EnemyAppearedText, UnveiledGhostText, LoadEnemyMonData, MarowakAnim, then
-- WildMonAppearedText.  The port used to hand the scope-carrying player a
-- battle that opened with MAROWAK already on screen and no unveil at all.
--
-- The story3 dispatch half (which branch the trigger picks, and that the ball
-- dodge survives the unveil) is tests/parity_marowak.lua and
-- tests/parity_marowak_ball.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local BattleState = require("src.battle.BattleState")

T.check(type(BattleState.makeUnveiledGhost) == "function",
  "BattleState:makeUnveiledGhost exists")
T.check(BattleState.makeUnveiledGhost ~= BattleState.makeGhost,
  "the unveiled battle is not just the scope-less ghost battle")

local REAL_SPRITE = { marker = "the MAROWAK front pic" }

local function newBattle()
  return setmetatable({
    kind = "wild",
    queue = {},
    frame = 0,
    data = { text = T.fixtures.load().text, pokemon = {} },
    enemy = { name = "MAROWAK", sprite = REAL_SPRITE,
              mon = { species = "MAROWAK", level = 30 } },
  }, BattleState)
end

-- ------------------------------------------------------- entering disguised
local b = newBattle()
b:makeUnveiledGhost()
T.eq(b.enemy.name, "GHOST",
  "with the scope the battle still OPENS as the GHOST (#492)")
T.check(b.enemy.sprite ~= REAL_SPRITE,
  "and wears the ghost pic, not the MAROWAK one")
T.check(b.scopeReveal == true, "the unveil is armed")
T.check(not b.ghost,
  "but IsGhostBattle stays false: the mon can be attacked and flees normally")
T.eq(b.ghostReal.name, "MAROWAK", "the real nick is kept for LoadEnemyMonData")
T.eq(b.ghostReal.sprite, REAL_SPRITE, "...and the real pic with it")

local ghostSprite = b.enemy.sprite

-- ------------------------------------------------------------- the row order
-- .isMarowak prints over the "GHOST appeared!" box enter() already queued: the
-- unveil line, MarowakAnim (a wait row parked over the fx state machine), then
-- "Wild MAROWAK appeared!" under the restored name.
b:queueScopeReveal()
T.eq(#b.queue, 4, "the unveil is four queue rows")
T.check(type(b.queue[1].text) == "string"
        and b.queue[1].text:find("SILPH SCOPE", 1, true) ~= nil,
  "row 1 is UnveiledGhostText")
T.check(type(b.queue[2].fn) == "function", "row 2 starts MarowakAnim")
T.eq(b.queue[3].wait, BattleState.GHOST_REVEAL_FRAMES,
  "row 3 holds the queue for the length of the animation")
T.check(type(b.queue[4].text) == "string"
        and b.queue[4].text:find("MAROWAK", 1, true) ~= nil,
  "row 4 is WildMonAppearedText under the real name")
T.check(b.queue[4].text:find("GHOST", 1, true) == nil,
  "...and not under the disguise")

-- ------------------------------------------------------------ the animation
-- MarowakAnim (engine/battle/ghost_marowak_anim.asm): FlashSprite8Times, the
-- rOBP1 fade-out, the pic swap, the fade-in.  The whole point of #492 is that
-- the swap comes AFTER the ghost has faded off the paper, so every frame up to
-- there still shows the GHOST.
b.queue[2].fn()
T.check(b.ghostReveal ~= nil, "the fn arms the reveal state")

local FLASH = BattleState.GHOST_FLASH_FRAMES
local FADE_OUT = BattleState.GHOST_FADE_OUT_FRAMES
local swapFrame, fades, stillGhost = nil, {}, true
for frame = 1, BattleState.GHOST_REVEAL_FRAMES do
  b:updateFx()
  local pf = b.picFx and b.picFx[b.enemy]
  fades[frame] = pf and pf.fade
  if not swapFrame and b.enemy.name ~= "GHOST" then swapFrame = frame end
  if frame <= FLASH + FADE_OUT and b.enemy.name ~= "GHOST" then
    stillGhost = false
  end
end

T.check(stillGhost,
  "the GHOST is on screen for the whole flash and fade-out (#492)")
T.eq(swapFrame, FLASH + FADE_OUT + 1,
  "the pic and nick swap the frame after the ghost has faded out")
T.eq(b.enemy.name, "MAROWAK", "the real nick is back by the end")
T.eq(b.enemy.sprite, REAL_SPRITE, "and the real pic with it")
T.check(b.enemy.sprite ~= ghostSprite, "the ghost pic is gone")

-- FlashSprite8Times xors rOBP1 with $80 every 10 frames, so the body alternates
-- between two shades rather than sitting opaque
T.eq(fades[5], 1, "the flash opens on the ghost at full strength")
T.eq(fades[15], 0.5, "...drops a shade 10 frames in")
T.eq(fades[25], 1, "...and comes back")
T.check(fades[FLASH + FADE_OUT] == 0,
  "the ghost is fully faded out when the swap lands")
T.check(fades[FLASH + FADE_OUT + 1] > 0
        and fades[FLASH + FADE_OUT + 1] < 1,
  "the MAROWAK fades IN rather than popping on")
T.eq(fades[BattleState.GHOST_REVEAL_FRAMES - 1], 1,
  "and reaches full strength before the box turns")

T.check(b.ghostReveal == nil, "the reveal state clears itself")
T.check(b.scopeReveal == nil, "so does the flag that gated the intro cry")
local pf = b.picFx and b.picFx[b.enemy]
T.check(pf == nil or pf.fade == nil,
  "no leftover alpha on the pic for the rest of the battle")

-- ------------------------------------------------ the scope-less ghost still
-- Nothing above may change the battle you get WITHOUT the scope: still a real
-- ghost battle, still no unveil queued.
local noScope = newBattle()
noScope:makeGhost()
T.check(noScope.ghost == true, "without the scope IsGhostBattle is true")
T.eq(noScope.enemy.name, "GHOST", "and the disguise is the same one")
T.check(noScope.scopeReveal == nil, "with no unveil armed")
T.eq(#noScope.queue, 0, "and no unveil rows queued")

T.finish("ghost unveil")
