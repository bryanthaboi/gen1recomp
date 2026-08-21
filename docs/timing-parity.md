# Timing parity with the Game Boy

The port's clock is faithful: `src/core/FixedStep.lua` advances game logic in
whole 1/60 s steps off wall-clock `dt`, the default speed multiplier is 1x
(`src/core/GameSpeed.lua:22`), and audio runs on its own real-time accumulator
so fast-forward cannot pitch it. Almost nothing in `src/` is seconds-based.

What diverges is the **frame budget of composed sequences**. The original
spends a large fraction of its running time inside `DelayFrames` calls that
produce no visible change - the pause after a page break, the beat before a
status move resolves, the drain of an HP bar one point at a time. Those are
invisible in a screenshot and easy to drop when porting behavior rather than
timing. Dropping them is why the port reads as faster and snappier than
hardware even though every individual animation is correct.

This document is the specification: what each sequence costs on hardware, and
where that number comes from.

## Method

`tools/scan_pokered_delays.ps1` walks the disassembly and reports every
frame-consuming wait with its enclosing routine label:

| Kind | Meaning | Frames |
| --- | --- | --- |
| `DelayFrames` | `ld c, N` + `call DelayFrames` (`home/delay.asm:1`) | N |
| `DelayFrame` | one vblank wait (`home/vblank.asm:92`) | 1 |
| `Delay3` | `home/palettes.asm:14`, three frames for a full bg-map update | 3 |
| `Fade` | the `GBFade*` helpers, expanded to their totals below | 24 or 32 |

Current inventory against `pokered-master`: **450 sites** - 181 `DelayFrames`,
164 `Delay3`, 65 `DelayFrame`, 31 `GBFade*`, and 9 `DelayFrames` calls whose
count is computed at runtime.

The four fades all live in `home/fade.asm` and are loops of
`ld c, 8 / call DelayFrames`:

| Routine | Iterations | Frames | Source |
| --- | --- | --- | --- |
| `GBFadeInFromBlack` | 4 | **32** | `home/fade.asm:21` |
| `GBFadeOutToBlack` | 4 | **32** | `home/fade.asm:43` |
| `GBFadeOutToWhite` | 3 | **24** | `home/fade.asm:26` |
| `GBFadeInFromWhite` | 3 | **24** | `home/fade.asm:48` |

## The metric

For each catalog entry, `delta = |port - truth| / truth`; the entry passes at
`delta <= 0.05`. The headline number is the **exposure-weighted** pass rate,
weighting each sequence by how often it occurs in ordinary play - a 30-frame
error on every page of dialogue matters more than a 30-frame error in the Hall
of Fame. Weights are in the tier column: T1 sequences recur constantly, T2 are
frequent, T3 are set pieces seen once or twice per playthrough.

## Tier 1 - constant exposure

These recur every few seconds of play and dominate perceived pacing. Both
sides are verified.

### Overworld and transitions

| Sequence | Hardware | Source | Port | Port source | Delta |
| --- | --- | --- | --- | --- | --- |
| Overworld loop iteration | 2 frames (two `DelayFrame`) | `home/overworld.asm:41-44` | 1 step | `src/core/Game.lua:174` | see note |
| Warp / door: fade out | **32** | `home/overworld.asm:703` -> `GBFadeOutToBlack` | 32 | `src/render/Transition.lua` | **fixed** |
| Warp / door: fade in | **0** (map is drawn under blacked palettes, no fade) | `home/overworld.asm:690-703` | 0 | `src/render/Transition.lua` | **fixed** |
| Return to overworld after a battle | **10** hold, then `GBFadeInFromWhite` **24** | `home/overworld.asm:351-352`, `:22`, `:749-753` | 10 + 24 | `Transition.battleReturn` | **fixed** |
| Special warp entry (fly / teleport / dungeon) | `Delay3` + `GBFadeInFromWhite` = **27** | `engine/overworld/player_animations.asm:5-7` | - | - | unmeasured |
| Dungeon-warp arrival hold | **50** | `engine/overworld/player_animations.asm:43` | - | - | unmeasured |
| Player step (walk) | 16 | 8 loop iterations x 2 frames | 16 | `src/world/Player.lua:14` | **ok** |
| Turn in place | 2 | one extra loop pass | 2 | `src/world/Player.lua:18` | **ok** |

Note on the overworld loop: `OverworldLoop` calls `DelayFrame` and then falls
through to `OverworldLoopLessDelay`, which calls it again - so a full pass
costs 2 frames, and input is sampled every other frame. The port steps logic
and samples input every frame. This does not change walking speed (the 2-frame
loop moves 2 px, giving the same 16 frames per tile) but it does halve input
latency versus hardware. Flagged rather than "wrong": matching it exactly would
make the port feel less responsive than the original does on a modern display,
and it is the one place where a deliberate divergence is defensible.

### Text

The typewriter cadence itself is already correct - 1/3/5 frames per character
from `TextSpeedOptionData`, implemented at `src/render/TextBox.lua:267`. The
gaps around it are missing.

| Sequence | Hardware | Source | Port | Port source | Delta |
| --- | --- | --- | --- | --- | --- |
| `<CONT>` line scroll (after the A press) | `ProtectedDelay3` 3 + 2x `ScrollTextUpOneLine` 5 = **13** | `home/text.asm:262-277`, `:283-307` | 13 | `src/render/TextBox.lua` | **fixed** |
| `<PARA>` paragraph break | `ProtectedDelay3` 3 + clear + **20** = **23** | `home/text.asm:230-243` | 23 | `src/render/TextBox.lua` | **fixed** |
| Page break (`PageChar`) | 3 + **20** = **23** | `home/text.asm:245-260` | 23 | `src/render/TextBox.lua` | **fixed** |
| `TextCommand_PAUSE` | **30** | `home/text.asm:500` | 30, skipped while A/B is held | both ROM extractors + text renderers | **fixed** |
| `TextCommand_DOTS` | **10** per dot | `home/text.asm:576` | 10 per ellipsis, skipped while A/B is held | both ROM extractors + text renderers | **fixed** |

The three ProtectedDelay3 frames are a *pre*-input hold: the arrow is already
up and the button is ignored, because `ManualTextScroll` only starts watching
the joypad after the delay returns. Mashing A through a long conversation
therefore cannot go faster than 3 frames per line on hardware, and now cannot
here either. `PromptText` (`home/text.asm:209-217`) has the same shape, so a
finished page holds three frames before it can be dismissed too.

**Battle text is a second, separate engine.** `BattleState` types its own
messages rather than going through `src/render/TextBox.lua`, so none of the
fixes above reached it and it had drifted further than the overworld box:

| Sequence | Hardware | Source | Was | Now |
| --- | --- | --- | --- | --- |
| Per character | 1 glyph per `wOptions & $f` frames (1/3/5, default **3**) | `home/print_text.asm:4-45` | 2 glyphs **per frame**, option ignored | 3 |
| Per character, A or B held | **1** frame | `print_text.asm:27-36` | 2 glyphs per frame | 1 |
| `<CONT>` pre-input hold | **3** | `home/text.asm:263-267` | 0 | 3 |
| `<CONT>` scroll after the press | **10** | `home/text.asm:280-305` | 0 | 10 |
| Finished page, pre-input hold | **3** | `home/text.asm:213-217` | 0 | 3 |

At the default text speed the battle typewriter was running **six times**
hardware speed, which is most of why battle text read as a blur, and it
ignored the OPTION text-speed setting entirely.

`ScrollTextUpOneLine` is `ld b, 5` of `DelayFrame` (`home/text.asm:301-305`)
and its own comment notes it is "always called twice in a row", so a CONT
scroll blocks for 10 frames. The port's `scrollPx` slide at
`src/render/TextBox.lua:305-307` is a cosmetic 8 px at 2 px/frame running in
`draw()`, not on the logic step, and it does not gate the typewriter.

### Menus

| Sequence | Hardware | Source | Port | Port source | Delta |
| --- | --- | --- | --- | --- | --- |
| Yes/no answer (either option) | **15** | `engine/menus/text_box.asm:322-323`, `:333-334` | 15 | `src/ui/ChoiceBox.lua` | **fixed** |
| List menu open (bag, PC, party-as-list) | **10**, then the loop's initial **3** | `home/list_menu.asm:55-64` | 10 + 3 before first input | `src/ui/ListMenu.lua` | **fixed** |
| List menu redraw per navigation | `Delay3` = **3** | `home/list_menu.asm:64` | 3 | `src/ui/ListMenu.lua` | **fixed** |
| Field move from the party menu | `Delay3` = **3** | `engine/menus/start_sub_menus.asm:4,27,175-203` | 7 (white flash) | `src/render/Transition.lua:8` | see note |
| Teleport from the party menu | **60** + `Delay3` | `engine/menus/start_sub_menus.asm:224-225` | - | - | unmeasured |

The port's 7-frame `white_flash` models `GBPalWhiteOutWithDelay3` plus the
screen-tile restore, which is a defensible reading of the same sequence; it is
listed here to be reconciled against the exact path rather than treated as a
bug.

### Battle entry

The wipe into a battle and the silhouette slide behind it. Numbers here come
from **pokered-c** (`C:\Users\Anthony\pokered`), whose `battle_transition.c`
derives each wipe from `battle_transitions.asm` and then corrects it against a
live side-by-side with the ROM. Where that project's measured value and a
naive reading of the asm disagree, the measured value wins - see the inward
spiral below.

| Sequence | Hardware | Was | Now |
| --- | --- | --- | --- |
| DoubleCircle wipe (wild, weak) | 10 x 3 = **30** | 40 | 30 |
| Circle wipe (wild, strong) | 20 x 3 = **60** | 40 | 60 |
| Spiral outward (trainer, strong) | 360 fills / 3 per frame = **120** | 40 | 120 |
| Spiral inward (trainer, weak) | 7 tiles per `Delay3` = **~150** | 40 | 156 |
| HStripes (dungeon wild, weak) | 20 x 3 = **60** | 24 | 60 |
| VStripes (dungeon wild, strong) | 18 x 3 = **54** | 24 | 54 |
| Shrink (dungeon trainer, weak) | 9 x 6 = **54** | 24 | 54 |
| Split (dungeon trainer, strong) | 9 x 6 = **54** | 24 | 54 |
| Flash before the circle wipes | 12 x 2 x 3 = **72** | 72 | 72 |
| Black hold before the battle draws | not stated by pokered; ~30 floor, calibrated **60** | 30 | 60 |
| Silhouette slide in | 144 px at 2 px/frame = **72** | 40 (160 px at 4 px/frame) | 72 |
| Trainer intro, before balls + text | `WaitForSoundToFinish` + `DelayFrames 20` | 0 | sfx wait + 20 |

The trainer intro's sound is `SFX_Silph_Scope`, extracted here as
`Trainer_Appeared` (`tools/rom_manifest.json` `audio.sfxHeaders`, bank 8 /
`$42bb`). It was being extracted and never played by anything. It now plays
into a clear window: `PrintBeginningBattleText .trainerBattle` does
`PlaySound` then `WaitForSoundToFinish`, which **blocks**, and only then
`DelayFrames 20` before `DrawAllPokeballs` and the text. `BattleState`'s
message queue grew a `waitSound` row for that, since `WaitForSoundToFinish`
waits on the sound actually stopping rather than on a fixed frame count.

**Scripted battles were skipping the transition entirely.** `BattleTransition`
runs from `DoBattleTransitionAndInitBattleVariables`, which both
`InitBattleCommon` (`core.asm:6680`, trainers) and `InitWildBattle` (`:6699`)
call unconditionally - every battle on hardware enters through a wipe. In the
port only `OverworldState:pushBattle` built one, and `Commands.start_battle`
pushed the `BattleState` straight onto the stack. The trainer-*sight* path
went through `pushBattle`, but every **script-driven** battle did not: gym
leaders, the rival, Giovanni, and every scripted wild encounter cut straight
to the battle screen with no transition at all. The catch tutorial
(`old_man_demo`) had the same gap; `InitWildBattle` has no
`BATTLE_TYPE_OLD_MAN` special case, so it gets a wipe too.

**Beyond 160x144.** Both halves of the transition used to stop at the classic
letterbox. The flash filled the 160x144 UI canvas, and the wipe handed the
surrounding window a generic centre-out square cascade
(`Renderer:drawBattleCascade`) regardless of which of the eight styles was
running - so at any zoom a spiral read as "a spiral in a box, with something
else happening around it".

- The flash is a palette write (`rBGP`), and a palette register tints every
  pixel the LCD shows; there is no "outside the screen" for it to miss. It is
  now published to the renderer as a screen-space veil and painted over the
  finished composite, so it covers the whole surface at any zoom.
- The spiral and circle walks are now generated for whatever grid the window
  works out to (`BattleTransition.gridOrder`), and the area outside the
  letterbox is filled in that order instead of the square cascade. The
  authentic 20x18 builders still own the letterbox itself, overrun and all,
  so nothing changes at 1x. The generic builders are deliberately *not* the
  ROM's walk - out there the hardware has no behaviour to be faithful to,
  only a shape to continue.
- `shrink`, `split` and the two stripe styles are plain geometry rather than
  a tile order, so they keep the cascade for now. Extending them is
  rectangles, not a walk, and has not been done.

Note that the **flash is wild-only**: `BattleTransition_FlashScreen` is called
from `BattleTransition_Circle` (`:585`) and `BattleTransition_DoubleCircle`
(`:628`) and nowhere else. A trainer battle's transition is the spiral -
inward against a weaker foe, outward against a stronger one
(`wBattleTransitionSpiralDirection`, `:119-126`) - with no flash in front of
it. The port's `flash` mapping was already correct; the transition simply
never ran for those battles.

Two of these deserve their reasoning recorded:

**The inward spiral** writes one tile per iteration and calls
`BattleTransition_TransferDelay3` every seventh tile. That helper is not a
one-frame transfer - it is `ld a,1 / ldh [hAutoBGTransferEnabled] / call
Delay3 / xor a / ldh [...]` (`battle_transitions.asm:619`), so the cadence is
7 tiles per **three** frames. Reading it as one frame runs the whole wipe 3x
too fast, ~46 frames against the ROM's ~150. pokered-c hit that exact bug and
caught it on a live comparison.

**The black hold** is not a number pokered states anywhere; it is incidental
load cost that a modern port does not pay. The derivable floor is ~13 frames
(`LoadHpBarAndStatusTilePatterns` 4, `LoadHudTilePatterns` 2, `ClearScreen`'s
`Delay3` 3, the `DisableLCD` LY wait 1, `Delay3` after `EnableLCD` 3), but the
two sprite decompressors (`UncompressSpriteFromDE` for the 7x7 front pic and
`LoadPlayerBackPic`'s uncompress + `ScaleSpriteByTwo`) are bit-level RLE/delta
decoders that cannot be cycle-counted from the asm at all. So the derivation
bottoms out around 25-30 with an unbounded remainder. pokered-c set 60 by ear
against the real ROM and marked it ~95% right rather than frame-matched. The
credible range is 30-60; it should not be "corrected" down toward the floor on
the strength of the derivation, because the omitted decompressors are exactly
the unbounded part. Pinning it exactly wants a frame-by-frame capture.

### Battle turns

| Sequence | Hardware | Source | Port | Port source | Delta |
| --- | --- | --- | --- | --- | --- |
| Player HP bar drain of D HP over P pixels | **D + 2P + 6** | `engine/gfx/hp_bar.asm:81-135`, `:140-159`, `:234` | D + 2P + 6 | `src/battle/BattleState.lua` `stepHPDrain` | **fixed** |
| Enemy HP bar drain over P pixels | **2P + 5** (no per-HP frame) | same, gated at `:207-209` | 2P + 5 | same | **fixed** |
| Status move / missed move beat | **30** | `engine/battle/core.asm:3145,3158,3185-3186`; enemy `:5588` | 30 | `EffectRegistry` `missBeat`, `BattleState:performMove` | **fixed** |
| Applying anim type 1, vertical shake b=8 | **48** | `animations.asm:500-503` | 48 | `BattleState:applyHitFx` | ok |
| Applying anim type 2, fast horizontal b=8 | **72** | `animations.asm:505-508` | 72 | same | ok |
| Applying anim type 3, slow horizontal 6,2 | **48** | `animations.asm:510-512,526-549` | 48 | same | ok |
| Applying anim type 4, `AnimationBlinkMon` | **60** | `animations.asm:514-516`, `:1360-1376` | 60 | same | **fixed** |
| Applying anim type 5, fast horizontal b=2 | **18** | `animations.asm:518-521` | 18 | same | ok |
| Applying anim type 6, slow horizontal 3,2 | **24** | `animations.asm:523-525` | 24 | same | ok |
| Faint slide-down | **14** (`PIC_HEIGHT` x `DelayFrames 2`) | `engine/battle/core.asm:1186-1222` | 14 | `BattleState:onFaint` | **fixed** |
| Before every move animation | `Delay3` = **3** | `engine/battle/core.asm:6635-6640` | 3 | `BattleState:updateQueue` | **fixed** |
| Battle start, after enemy send-out | **40** | `engine/battle/core.asm:152-156` | 40 | `BattleState:enter` | **fixed** |
| Poison / burn / leech-seed tick | **20** | `engine/battle/core.asm:529-530` | 20 | `src/battle/BattleState.lua:1817` | **ok** |
| Switch player mon | **50** | `engine/battle/core.asm:2421-2422` | 50 | `src/battle/BattleState.lua:1666-1668` | **ok** |
| Post-hit hold (crit text or not) | **20** | `engine/battle/core.asm:3798-3814` | 20 | `EffectRegistry.runDamaging` | **fixed** |
| Fainted mon slide-down | **2** per row | `engine/battle/core.asm:1216-1217` | - | - | unmeasured |
| Trainer pic slide off | **2** per column | `engine/battle/core.asm:1267-1268` | - | - | unmeasured |
| Trainer battle victory | **40** | `engine/battle/core.asm:940-941` | - | - | unmeasured |
| Player blackout | **40** | `engine/battle/core.asm:1143-1144` | - | - | unmeasured |
| No moves left (Struggle) | **60** | `engine/battle/core.asm:2753-2754` | - | - | unmeasured |
| Send-out animation | `Delay3` + **4** + **5** | `engine/battle/core.asm:6814-6830` | - | - | unmeasured |

The HP bar was the single largest battle divergence. `UpdateHPBar` steps **one
HP point per loop iteration**; each iteration pays 1 frame in
`UpdateHPBar_PrintHPNumber` whenever `wHPBarType != 0` - the player's own HUD
and the party menu, but not the enemy HUD - plus 2 frames for each pixel the
bar actually moves. The tail (`.animateHPBarDone`, `:132-135`) prints the
number once more, animates one last pixel and falls into `Delay3`, so it costs
6 frames player-side and 5 enemy-side.

A 150 HP mon losing everything therefore costs 150 + 96 + 6 = **252 frames
(4.2 s)** on the player's HUD, against 96 + 5 = 101 on the enemy's. The port
used a flat `maxHP/96` - the enemy-side rate applied to both sides - and ran
that same drain in 96 frames (1.6 s).

## Tier 2 - frequent

Status-effect failures (`engine/battle/effects.asm:161,1162,1205`) hold **50**
frames each. `SwitchAndTeleportEffect` uses 50 and 20
(`:834-901`). Evolution holds **50** then **40**
(`engine/pokemon/evos_moves.asm:123,155`). The healing machine
(`engine/overworld/healing_machine.asm`), item effects
(`engine/items/item_effects.asm`, 259 frames across 8 sites), and the fishing
animation (**10** then **100**, `engine/overworld/player_animations.asm:380,399`)
are all in this tier.

## Tier 3 - set pieces

Highest total budgets in the scan, all seen rarely:
`engine/movie/hall_of_fame.asm` (529 frames / 7 sites),
`engine/link/cable_club.asm` (507 / 12), `engine/movie/credits.asm` (502 / 7),
`engine/movie/trade.asm` (494 / 19), `engine/movie/intro.asm` (317 / 7),
`engine/menus/main_menu.asm` (271 / 15), `engine/menus/save.asm` (250 / 3),
`engine/battle/end_of_battle.asm` (200 / 1, the link-battle win/lose string).
Several of these already have faithful implementations - see
`src/ui/IntroMovie.lua`, `src/ui/Credits.lua`, `src/ui/HallOfFame.lua`, whose
constants cite their asm sources directly.

## Status

Closed, and locked by `tests/engine/timing_parity.lua`:

1. **Text page and CONT breaks** - were 0 frames where hardware spends 13-23,
   on every page of every dialogue in the game. Now exact, including the
   three-frame pre-input hold that swallows a mashed A.
2. **Player HP bar drain** - was ~2.5x too fast on a typical mon. Now steps
   one HP point at a time at the hardware rate, with the enemy HUD correctly
   cheaper than the player's.
3. **Warp fade** - was a symmetric 12/12; now 32 out and no fade in, which is
   both the right duration and the right shape.
4. **Yes/no answer** - was 0 frames where hardware spends 15, with the cursor
   snapping to NO on B for the duration as `.choseSecondMenuItem` does.

5. **Battle entry** - every wipe ran at a flat 40/24 against budgets of 30-156,
   the silhouette slide was 40 frames against 72, the black hold was half
   what pokered-c calibrated, and the trainer intro's 20-frame gap before the
   balls and text was missing entirely. This was the single most compressed
   stretch in the game.

6. **Battle turns** - the type-4 blink ran at 20 frames against 60. That is
   the applying animation for every plain damaging move the player uses, so
   it was the single most-repeated timing error in the game. The 30-frame
   beat that hardware spends on every status move and every miss was missing
   entirely. The faint slide, unusually, ran *slower* than hardware (30
   against 14).

Two things worth recording about that last batch, because both contradict a
plausible reading:

- **`PrintCriticalOHKOText`'s 20-frame hold is not conditional.** The
  "no critical hit" early-out at `core.asm:3799` jumps to `.done`, and
  `.done` *is* the `ld c, 20 / jp DelayFrames`. Every landed hit pays it,
  which is where the beat before "It's super effective!" comes from.
- **`StartBattle`'s 40-frame hold is not conditional either.** The `call nz`
  at `core.asm:154` gates only `EnemySendOutFirstMon`; the `DelayFrames 40`
  under it runs for wild battles too, and it lands *between* the enemy's
  send-out and `.playerSendOutFirstMon` (`:166`) rather than at the end of
  the intro.

Trainer victory (24-frame scroll-in + 40-frame hold) and the ball shake
(`SFX_TINK` + `DelayFrames 40` per rock) were already correct -
`BattleState.lua`'s `wait = 64` and `AnimPlayer.lua`'s `emit(40)`. Note that
pokered-c's `BUI_TRAINER_VICTORY_SLIDE` comment calls the scroll-in 14
frames; `_ScrollTrainerPicAfterBattle` is 6 loop passes of `DelayFrames 4`,
so 24 is right and this port already had it.

**Leaving a battle was a cut, not a fade.** `EnterMap` checks
`BIT_BATTLE_OVER_OR_BLACKOUT` and calls `MapEntryAfterBattle`
(`home/overworld.asm:22`), which is `GBFadeInFromWhite` - so the map fades up
from white over 24 frames, behind the 10-frame hold at `:351-352`. The port
popped the battle and the overworld was simply there. `Transition.battleReturn`
supplies both halves, and steps the veil in three palette stages of 8 frames
rather than tweening it, because `GBFadeIncCommon` writes a palette and holds
it with `ld c, 8 / call DelayFrames` (`home/fade.asm:30-41`) three times over.

It is wrapped around `battle.onFinish` in `OverworldState:pushBattle` - the
one funnel every battle goes through - rather than living in `afterBattle`.
That placement matters: a script-driven **win** defers `afterBattle` into
`ctx.afterScript` so an evolution screen cannot be buried under the trainer's
follow-up text (`Commands.start_battle`), and a fade inside `afterBattle`
inherited that deferral. On a rival battle it fired after the post-battle
dialogue *and* the rival's walk-off, rather than when the battle ended.

The rest of `onFinish` runs as the fade's `onDone`, which is also the hardware
order: `MapEntryAfterBattle` fades the map back in and only then does the map
script run. The overworld is frozen meanwhile - `StateStack` updates the top
state only - so nothing moves under the white.

Hardware skips the fade on a dark map (`wMapPalOffset` nonzero takes the
`LoadGBPal` branch at `:754`). This port has no `wMapPalOffset` equivalent -
no map needs FLASH to be lit - so that branch is unreachable here;
`battleReturn` accepts `opts.instant` for it if that ever changes.

Still open: every table row explicitly marked "unmeasured" above has a
confirmed hardware number but has not yet had its complete port path traced.

Entries marked "unmeasured" have confirmed hardware numbers but the port side
has not been traced; they are remaining work, not known-good.
