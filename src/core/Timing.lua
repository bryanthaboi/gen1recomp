-- Hardware frame budgets, in fixed 60Hz logic steps.
--
-- The original spends a large share of its running time inside DelayFrames
-- calls that produce no visible change -- the pause after a page break, the
-- beat before a status move resolves, the one-HP-at-a-time drain of an HP
-- bar.  Porting the visible half of a sequence and dropping the wait is what
-- makes a port read as snappier than hardware, so every one of those waits
-- lives here with its asm citation instead of as a file-local constant.
--
-- See docs/timing-parity.md for the full catalog and the measurement method;
-- tools/scan_pokered_delays.ps1 regenerates the hardware side from a
-- disassembly checkout.

local Timing = {}

-- home/palettes.asm:14 -- three frames to let the bg map fully update
Timing.DELAY3 = 3

-- home/fade.asm: each fade is a loop of `ld c, 8 / call DelayFrames`
Timing.FADE_IN_FROM_BLACK  = 32 -- fade.asm:21, b = 4
Timing.FADE_OUT_TO_BLACK   = 32 -- fade.asm:43, b = 4
Timing.FADE_OUT_TO_WHITE   = 24 -- fade.asm:26, b = 3
Timing.FADE_IN_FROM_WHITE  = 24 -- fade.asm:48, b = 3

-- Overworld -----------------------------------------------------------------

-- home/overworld.asm:703 PlayMapChangeSound tail-calls GBFadeOutToBlack on
-- every map change.  There is no matching fade in: the new map is drawn while
-- the palettes are still blacked out and LoadGBPal restores them in one write,
-- so the map appears instantly.
Timing.WARP_FADE_OUT = Timing.FADE_OUT_TO_BLACK
Timing.WARP_FADE_IN  = 0

-- home/overworld.asm:351-352 -- after a battle, before EnterMap
Timing.POST_BATTLE_RETURN = 10

-- engine/overworld/player_animations.asm:5-7 -- EnterMapAnim, the fly /
-- teleport / dungeon-warp arrival: Delay3 then GBFadeInFromWhite
Timing.SPECIAL_WARP_ENTRY = Timing.DELAY3 + Timing.FADE_IN_FROM_WHITE
-- player_animations.asm:43 -- dungeon warp holds before handing back control
Timing.DUNGEON_WARP_ARRIVAL = 50

-- Text ----------------------------------------------------------------------

-- home/text.asm:283-307 ScrollTextUpOneLine is `ld b, 5` of DelayFrame, and
-- its own comment notes it is "always called twice in a row"
Timing.TEXT_SCROLL_LINE = 5
Timing.TEXT_SCROLL_PAIR = Timing.TEXT_SCROLL_LINE * 2

-- Both _ContText (home/text.asm:262-277) and Paragraph (:230-243) print the
-- â–¼ and call ProtectedDelay3 *before* ManualTextScroll starts watching the
-- joypad, so three frames pass with the arrow up and the button ignored.
Timing.TEXT_PRE_ADVANCE = Timing.DELAY3

-- Paragraph / PageChar clear the box and then hold (home/text.asm:239-240,
-- :254-255) before the next page starts typing.
Timing.TEXT_PAGE_CLEAR = 20

-- Totals, for the catalog and the parity tests.
Timing.TEXT_CONT      = Timing.TEXT_PRE_ADVANCE + Timing.TEXT_SCROLL_PAIR
Timing.TEXT_PARAGRAPH = Timing.TEXT_PRE_ADVANCE + Timing.TEXT_PAGE_CLEAR
Timing.TEXT_PAGE      = Timing.TEXT_PARAGRAPH

Timing.TEXT_PAUSE = 30 -- home/text.asm:500 TextCommand_PAUSE
Timing.TEXT_DOT   = 10 -- home/text.asm:576 TextCommand_DOTS, per dot

-- Menus ---------------------------------------------------------------------

-- engine/menus/text_box.asm:322-323 / :333-334 -- both branches of a
-- two-option (yes/no) menu hold before restoring the screen tiles
Timing.YES_NO_ANSWER = 15

Timing.LIST_MENU_OPEN   = 10             -- home/list_menu.asm:55-56
Timing.LIST_MENU_REDRAW = Timing.DELAY3  -- home/list_menu.asm:64

-- engine/menus/start_sub_menus.asm:224-225
Timing.FIELD_TELEPORT = 60 + Timing.DELAY3

-- Battle --------------------------------------------------------------------

-- SlidePlayerAndEnemySilhouettesOnScreen (engine/battle/core.asm:9-49):
-- the enemy comes in on BG SCX $90 -> $00 and the player's back pic on
-- decrementing OAM x, both 2 px per frame -- so 144 px over 72 frames.  The
-- port ran 160 px at 4 px/frame (40 frames), a little under twice too fast.
Timing.BATTLE_SLIDE_IN_FRAMES = 72
Timing.BATTLE_SLIDE_PX_PER_FRAME = 2

-- PrintBeginningBattleText .trainerBattle (engine/battle/common_text.asm):
-- SFX_SILPH_SCOPE plays into a clear window (PlaySound then
-- WaitForSoundToFinish, which blocks), and only after `ld c, 20 /
-- DelayFrames` do DrawAllPokeballs and the "wants to fight!" text run.
Timing.TRAINER_INTRO_SFX_GAP = 20

Timing.BATTLE_START_SENDOUT = 40 -- engine/battle/core.asm:155-156
Timing.MOVE_ANIM_PRE        = Timing.DELAY3 -- core.asm:6638 PlayMoveAnimation

-- core.asm:3185-3186 (player) / :5587-5588 (enemy).  Reached when the move
-- has 0 BP (core.asm:3145 -- every status move) or missed (:3158), so this
-- beat is paid on a large fraction of all turns.
Timing.MOVE_STATUS_OR_MISS = 30

-- PlayApplyingAttackAnimation's six types (AnimationTypePointerTable,
-- engine/battle/animations.asm:490-524).  The two shake families are
-- `AnimationShakeScreenHorizontallySlow`, whose double push/pop makes each
-- outer pass cost 4b frames and run c times -- so c * 4b.
Timing.SHAKE_VERTICAL     = 48 -- type 1, b=8: 8 x 6
Timing.SHAKE_HORIZ_HEAVY  = 72 -- type 2, b=8: 8 x 9
Timing.SHAKE_HORIZ_SLOW   = 48 -- type 3, lb bc, 6, 2: 2 x 4x6
Timing.SHAKE_HORIZ_LIGHT  = 18 -- type 5, b=2: 2 x 9
Timing.SHAKE_HORIZ_SLOW2  = 24 -- type 6, lb bc, 3, 2: 2 x 4x3

-- Type 4 -- the player's damaging move with no added effect, and so the
-- single most common animation in the game -- is AnimationBlinkMon
-- (animations.asm:1360-1376): `ld c, 6` iterations of hide + DelayFrames 5
-- + show + DelayFrames 5.  The asm's own comment calls it "a second or
-- two"; the port ran it in 20 frames, three times too fast, which is a
-- large part of why trading blows felt hurried.
Timing.BLINK_MON = 60

-- SlideDownFaintedMonPic (engine/battle/core.asm:1181-1222): b = PIC_HEIGHT
-- (7) outer iterations, each closing with `ld c, 2 / call DelayFrames`.
-- This one the port ran SLOWER than hardware, at 30.
Timing.FAINT_SLIDE = 14

Timing.RESIDUAL_TICK      = 20 -- core.asm:529-530 poison/burn/leech seed
Timing.CRIT_OHKO_TEXT     = 20 -- core.asm:3813-3814
Timing.SWITCH_PLAYER_MON  = 50 -- core.asm:2421-2422
Timing.NO_MOVES_LEFT      = 60 -- core.asm:2753-2754
Timing.TRAINER_VICTORY    = 40 -- core.asm:940-941
Timing.PLAYER_BLACKOUT    = 40 -- core.asm:1143-1144
Timing.FAINT_SLIDE_ROW    = 2  -- core.asm:1216-1217, per row
Timing.TRAINER_SLIDE_COL  = 2  -- core.asm:1267-1268, per column

-- HP bar (engine/gfx/hp_bar.asm) ---------------------------------------------
--
-- UpdateHPBar steps ONE HP point per loop iteration (:81-120).  Each
-- iteration pays:
--   * 1 frame in UpdateHPBar_PrintHPNumber's DelayFrame (:234) -- but only
--     when wHPBarType is nonzero (:207-209), i.e. the player's own HUD and
--     the party menu, never the enemy HUD; and
--   * 2 frames per pixel the bar actually moved, from
--     UpdateHPBar_AnimateHPBar's `ld c, 2 / call DelayFrames` (:147-148).
-- The drain closes with one more pixel step and a Delay3 (:133-135).
--
-- So a player-side drain of D HP across P pixels costs D + 2P + 6 frames,
-- while the same drain on the enemy HUD costs only 2P + 5.  A 150 HP mon
-- losing everything takes 150 + 96 + 6 = 252 frames on hardware.

Timing.HP_BAR_PIXELS      = 48 -- the bar is 48 px wide (GetHPBarLength)
Timing.HP_BAR_PIXEL_STEP  = 2  -- frames per pixel of bar movement
Timing.HP_BAR_HP_STEP     = 1  -- frames per HP point, player-side HUD only

-- Pixels the bar shows for `hp` out of `maxHP`.  GetHPBarLength floors the
-- 48ths and clamps the result to at least 1 for any nonzero HP
-- (engine/gfx/hp_bar.asm:42-45); an empty bar is 0.
function Timing.hpBarPixels(hp, maxHP)
  if not maxHP or maxHP <= 0 then return 0 end
  if hp <= 0 then return 0 end
  local px = math.floor(hp * Timing.HP_BAR_PIXELS / maxHP)
  if px < 1 then px = 1 end
  return px
end

-- Frames one single-HP step of the drain costs: the per-HP number print
-- (player side only) plus two frames for every pixel that step moved.
function Timing.hpDrainStepFrames(fromHP, toHP, maxHP, playerSide)
  local pixels = math.abs(Timing.hpBarPixels(toHP, maxHP)
                          - Timing.hpBarPixels(fromHP, maxHP))
  local frames = pixels * Timing.HP_BAR_PIXEL_STEP
  if playerSide then frames = frames + Timing.HP_BAR_HP_STEP end
  return frames
end

-- After the loop, .animateHPBarDone prints the number one last time, runs
-- AnimateHPBar for a single pixel and falls into Delay3 (hp_bar.asm:132-135)
-- -- so the tail costs 6 frames on the player's HUD and 5 on the enemy's.
function Timing.hpDrainClosingFrames(playerSide)
  local frames = Timing.HP_BAR_PIXEL_STEP + Timing.DELAY3
  if playerSide then frames = frames + Timing.HP_BAR_HP_STEP end
  return frames
end

-- Total cost of draining `fromHP` to `toHP`, for tests and for anything that
-- needs to budget the whole animation up front.
function Timing.hpDrainFrames(fromHP, toHP, maxHP, playerSide)
  local total = 0
  local hp = fromHP
  local dir = (toHP < fromHP) and -1 or 1
  while hp ~= toHP do
    local nextHP = hp + dir
    total = total + Timing.hpDrainStepFrames(hp, nextHP, maxHP, playerSide)
    hp = nextHP
  end
  return total + Timing.hpDrainClosingFrames(playerSide)
end

return Timing
