-- The battle-animation tables, read out of a Gold cache and checked against
-- the decomp they came from.
--
-- Every expectation below is a literal from pokegold, so a failure names the
-- file it disagrees with rather than "a number changed":
--   data/moves/animations.asm   BattleAnim_Tackle
--   data/battle_anims/objects.asm   battleanimobj rows
--   data/battle_anims/framesets.asm oamframe lists
--   data/battle_anims/oam.asm       battleanimoam + dbsprite rows
--   data/battle_anims/object_gfx.asm anim_obj_gfx counts
--
--   luajit tests/gen2_battle_anims_test.lua
-- Also dofile'd by tests/run_tests.lua.  Skips when there is no Gold cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle anims")
local check, eq = S.check, S.eq

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  local bases = { home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }
  local ids = { os.getenv("POKEPORT_IDENTITY") or "", "g1r-gold", "pokeport-test-caches" }
  for _, base in ipairs(bases) do
    for _, id in ipairs(ids) do
      local root = base .. "/" .. id .. "/gold"
      local f = id ~= "" and io.open(root .. "/data/generated/battle_anims.lua", "r")
      if f then
        f:close()
        cache = cache or root
      end
    end
  end
  cache = cache or (bases[1] .. "/g1r-gold/gold")
end

local path = cache .. "/data/generated/battle_anims.lua"
local file = io.open(path, "r")
if not file then
  print("[skip] no Gold cache at " .. path)
  check(true, "no Gold cache at " .. path .. " (SKIP)")
  S.finish()
  return
end
file:close()

local data = assert(loadfile(path))()

-- A cache from before the anims were extracted still has the Phase 2 stub.
if not data.scripts then
  check(true, "battle_anims.lua is still the stub -- re-import Gold (SKIP)")
  S.finish()
  return
end

-- ---- the per-move scripts -------------------------------------------------

check(type(data.moves) == "table", "a move -> script map")
eq(data.bank, 50, "the animations live in bank $32")

local function countKeys(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

eq(countKeys(data.moves), 251, "one animation per move (NUM_MOVES)")
check(countKeys(data.scripts) > 300,
  ("%d scripts in the pool, including the ones only anim_call reaches")
    :format(countKeys(data.scripts)))
eq(countKeys(data.scripts), #data.scriptOrder,
  "scriptOrder lists every script exactly once")

-- BattleAnim_Tackle, row for row.  This one is worth pinning: it uses a gfx
-- load, a call, a BG effect, a wait, a sound, an object and a return, which is
-- most of the command set a move animation actually reaches for.
local tackle = data.scripts[data.moves.TACKLE]
check(tackle ~= nil, "TACKLE has a script")
if tackle then
  eq(tackle[1][1], "1gfx", "anim_1gfx first")
  eq(tackle[1][2], 1, "...loading BATTLE_ANIM_GFX_HIT")
  eq(tackle[2][1], "call", "then anim_call BattleAnim_TargetObj_1Row")
  check(type(tackle[2][2]) == "string",
    "and a branch target is an address key, not two loose bytes")
  check(data.scripts[tackle[2][2]] ~= nil,
    "which resolves to a script in the pool")
  eq(tackle[3][1], "bgeffect", "then anim_bgeffect")
  eq(tackle[3][2], 36, "...BATTLE_BG_EFFECT_TACKLE")
  eq(tackle[3][4], 1, "...on BG_EFFECT_USER")
  eq(tackle[4][1], "wait", "then anim_wait 4")
  eq(tackle[4][2], 4, "...four frames")
  eq(tackle[5][1], "sound", "then anim_sound")
  eq(tackle[6][1], "obj", "then anim_obj")
  eq(tackle[6][2], 0, "...BATTLE_ANIM_OBJ_HIT_BIG_YFIX")
  eq(tackle[6][3], 136, "...at x 136")
  eq(tackle[6][4], 48, "...and y 48")
  eq(tackle[7][1], "wait", "then anim_wait 8")
  eq(tackle[7][2], 8, "...eight frames")
  eq(tackle[8][1], "call", "then anim_call BattleAnim_ShowMon_0")
  eq(tackle[9][1], "ret", "then anim_ret")
  eq(#tackle, 9, "and nothing after it")
end

-- ---- BattleAnimObjects ----------------------------------------------------
--
-- A row is SIX bytes: BATTLEANIMOBJ_LENGTH is `_RS - 1`, discounting the
-- struct's runtime INDEX byte.  Reading seven walks every row off the end.

eq(countKeys(data.objects), 188, "188 animation objects")
local ember = data.objects.BATTLE_ANIM_OBJ_EMBER
check(ember ~= nil, "EMBER is one of them")
if ember then
  eq(ember.fixY, 0xaa, "EMBER's enemy y-fix is $aa")
  eq(ember.frameset, "BATTLE_ANIM_FRAMESET_EMBER", "its own frameset")
  eq(ember.func, "BATTLE_ANIM_FUNC_EMBER", "its own per-frame function")
  eq(ember.palette, "PAL_BATTLE_OB_RED",
    "an OBJ palette, not the BG palette of the same number")
  eq(ember.gfx, "BATTLE_ANIM_GFX_FIRE", "off the fire sheet")
end
local hit = data.objects.BATTLE_ANIM_OBJ_HIT_BIG_YFIX
if hit then
  eq(hit.fixY, 0xff, "HIT_BIG_YFIX is the $ff y-fix variant")
  eq(hit.func, "BATTLE_ANIM_FUNC_NULL", "and does not move itself")
  eq(hit.palette, "PAL_BATTLE_OB_GRAY", "grey")
end

-- ---- framesets ------------------------------------------------------------
--
-- oam_anims.asm counts DOWN from $ff: oamend $ff, oamrestart $fe, oamwait
-- $fd, oamdelete $fc.  Getting that order wrong runs one frameset into the
-- next and every list comes out dozens of frames long.

eq(countKeys(data.framesets), 185, "185 framesets")
local hitBig = data.framesets.BATTLE_ANIM_FRAMESET_HIT_BIG
check(hitBig ~= nil, "HIT_BIG is one")
if hitBig then
  eq(#hitBig, 2, "Frameset_HitBig is one frame and a delete")
  eq(hitBig[1][1], "frame", "the frame")
  eq(hitBig[1][2], "BATTLE_ANIM_OAMSET_00", "...is OAM set 00")
  eq(hitBig[1][3], 6, "...held six frames")
  eq(hitBig[2][1], "delete", "then oamdelete")
end
local ember2 = data.framesets.BATTLE_ANIM_FRAMESET_EMBER
if ember2 then
  eq(#ember2, 3, "Frameset_Ember is two frames and a restart")
  eq(ember2[3][1], "restart", "oamrestart, not oamend")
end
local shake = data.framesets.BATTLE_ANIM_FRAMESET_PUNCH_SHAKE
if shake then
  eq(#shake, 9, "Frameset_PunchShake alternates four times, then deletes")
  eq(shake[9][1], "delete", "ending on oamdelete")
end

-- ---- OAM sets -------------------------------------------------------------
--
-- dbsprite emits y FIRST even though the macro reads x first, and a negative
-- tile column wraps: `dbsprite -2, -2, 0, 0, $00, $0` is y $f0, x $f0.

eq(countKeys(data.oamsets), 216, "216 OAM sets")
local set00 = data.oamsets.BATTLE_ANIM_OAMSET_00
check(set00 ~= nil, "OAM set 00 is one")
if set00 then
  eq(set00.vtile, 0, "at vtile offset 0")
  eq(#set00.sprites, 16, "with 16 sprites")
  eq(set00.sprites[1].y, 0xf0, "the first one's y wraps to $f0")
  eq(set00.sprites[1].x, 0xf0, "and its x to $f0")
  eq(set00.sprites[1].tile, 0, "tile $00")
  eq(set00.sprites[2].tile, 1, "then tile $01")
end

-- ---- object graphics ------------------------------------------------------
--
-- BATTLE_ANIM_GFX_* starts at 1, because AnimObjGFX row 0 is the empty
-- AnimObj00GFX -- so the name list carries a placeholder and every id indexes
-- it the same way.

check(countKeys(data.gfx) >= 39, "the object sheets extracted")
local hitGfx = data.gfx.BATTLE_ANIM_GFX_HIT
check(hitGfx ~= nil, "the hit sheet is one")
if hitGfx then
  eq(hitGfx.tiles, 21, "AnimObjHitGFX is 21 tiles")
  check(hitGfx.image:match("battle_anims/"), "written under battle_anims/")
end
local cutGfx = data.gfx.BATTLE_ANIM_GFX_CUT
if cutGfx then eq(cutGfx.tiles, 6, "AnimObjCutGFX is 6 tiles") end
check(data.gfx.BATTLE_ANIM_GFX_NONE == nil,
  "and the empty row 0 is not written as a sheet")

-- ---- the runtime -----------------------------------------------------------
--
-- src/battle/gen2/AnimRunner.lua + AnimObjects.lua + BgEffects.lua: the
-- command interpreter, the ten object structs and the five BG-effect structs,
-- stepped one 60 Hz frame at a time with no window.  The expectations below
-- come from engine/battle_anims/{anim_commands,core,functions,bg_effects}.asm
-- rather than from a recorded run, so a failure names the routine it
-- disagrees with.

local consts
do
  local file = io.open(cache .. "/data/generated/constants.lua", "r")
  if file then
    file:close()
    consts = assert(loadfile(cache .. "/data/generated/constants.lua"))()
  end
end

if not (consts and consts.battleAnimObjectOrder) then
  check(true, "no constants.lua in the cache -- skipping the runtime (SKIP)")
  S.finish()
  return
end

local AnimObjects = require("src.battle.gen2.AnimObjects")
local AnimRunner = require("src.battle.gen2.AnimRunner")

-- The sine BattleAnim_Sine computes is the same quarter wave the sprite anims
-- use, and entry 16 is exactly $100 -- so sin(pi/2) * d is d itself.
eq(AnimObjects.sine(16, 0x40), 0x40, "sine at a quarter turn is the amplitude")
eq(AnimObjects.sine(0, 0x40), 0, "and zero at zero")
eq(AnimObjects.sine(48, 0x40), 0xc0, "the lower half comes back negative")
eq(AnimObjects.cosine(0, 0x40), 0x40, "cosine leads it by eight steps")

-- `sra` keeps the sign, which is what every "an eighth of the width" does.
eq(AnimObjects.sra(0xff), 0xff, "sra of -1 is -1")
eq(AnimObjects.sra(0xfd), 0xfe, "sra of -3 is -2")
eq(AnimObjects.sra(0x08), 0x04, "and of 8 is 4")

local function runner(key, opts)
  opts = opts or {}
  local r = AnimRunner.new({
    data = data, constants = consts,
    battleTurn = opts.turn or 0, animId = opts.animId,
    param = opts.param or 0, sfxOrder = consts.sfxOrder,
    hooks = opts.hooks,
  })
  r:start(key)
  return r
end

-- BattleAnim_Tackle: anim_1gfx HIT, anim_call, anim_bgeffect TACKLE,
-- anim_wait 4, anim_sound, anim_obj HIT_BIG_YFIX, anim_wait 8, anim_call,
-- anim_ret.  One step runs commands up to the first wait.
local sounds = {}
local tackle = runner(data.moves.TACKLE, {
  animId = "TACKLE",
  hooks = { sound = function(name) sounds[#sounds + 1] = name end },
})
check(tackle ~= nil, "a runner for Tackle")
tackle:step()
eq(tackle:tileOffsetFor("BATTLE_ANIM_GFX_HIT"), 0,
  "anim_1gfx puts the hit sheet at the base tile")
check(tackle.bg:activeCount() >= 1, "and queued a BG effect before waiting")
local steps = 0
while tackle:step() and steps < 600 do steps = steps + 1 end
check(steps > 0 and steps < 600, "Tackle runs to its anim_ret in " .. steps .. " frames")
check(#sounds >= 1, "and played at least one SFX (" .. tostring(sounds[1]) .. ")")

-- The pic-swap commands all branch on hBattleTurn with the same `and a / jr z,
-- .player`, and every .player arm writes vTiles2 tile $31, the 6x6 backpic:
-- turn 0 repaints the PLAYER, the fall-through (tile $00, a 7x7 frontpic) the
-- enemy.  engine/battle_anims/anim_commands.asm BattleAnimCmd_Transform,
-- _RaiseSub, _DropSub, _MinimizeOpp, _BeatUp.
local CMD = AnimRunner.COMMANDS
local function overrideSide(name, turn)
  local r = runner(nil, { turn = turn })
  CMD[name](r)
  if r.picOverride.player ~= nil then return "player" end
  if r.picOverride.enemy ~= nil then return "enemy" end
  return nil
end
for _, name in ipairs({ "transform", "raisesub", "minimizeopp", "beatup" }) do
  eq(overrideSide(name, 0), "player", "anim_" .. name .. " on turn 0 is the player's own pic")
  eq(overrideSide(name, 1), "enemy", "anim_" .. name .. " on turn 1 is the enemy's")
end
-- $e9 is one of the six labels stacked on BattleAnimCmd_E8's single `ret`, so
-- the opcode named `minimize` draws nothing; $e2 minimizeopp is the real one.
eq(overrideSide("minimize", 0), nil, "anim_minimize ($e9) is a cart dummy")

-- Every one of the 251 move animations has to terminate, from both sides.
-- A script that never reaches an anim_ret outside a subroutine would hang the
-- battle screen, and the branch-heavy ones (Metronome, Bide, the multi-hit
-- loops) are exactly where that would happen.
local longest, longestName, stuck = 0, nil, 0
local DroppedBg = require("src.battle.gen2.BgEffects").DROPPED
eq(#DroppedBg, 0, "no BG effect id was dropped before the sweep")
for move, key in pairs(data.moves) do
  for _, turn in ipairs({ 0, 1 }) do
    for _, param in ipairs({ 0, 1, 2, 3 }) do
      local r = runner(key, { animId = move, turn = turn, param = param })
      local frames = 0
      local ok = pcall(function()
        while r:step() and frames < 1500 do frames = frames + 1 end
      end)
      if not ok or frames >= 1500 then stuck = stuck + 1 end
      if frames > longest then longest, longestName = frames, move end
    end
  end
end
eq(stuck, 0, "all 251 move animations terminate on both turns at params 0-3")
check(longest > 0 and longest < 1500,
  ("the longest is %s at %d frames"):format(tostring(longestName), longest))
eq(#DroppedBg, 0, "no BG effect id was dropped for want of an E entry ("
  .. table.concat(DroppedBg, ", ") .. ")")

-- BattleAnimObjects rows are six bytes and the struct's TILEID comes from the
-- tile dict, not the row -- so an object queued before its sheet is loaded
-- draws at offset 0 rather than reading a seventh byte that is not there.
local objects = AnimObjects.new(data, consts, { battleTurn = 0 })
local st = objects:queue("BATTLE_ANIM_OBJ_HIT_BIG_YFIX", 0x88, 0x30, 0)
check(st ~= nil, "an object queues into the first free struct")
if st then
  eq(st.index, 1, "and takes wLastAnimObjectIndex 1")
  eq(st.x, 0x88, "at the x it was given")
  eq(st.frame, 0xff, "with FRAME initialised to -1, not 0")
  eq(st.tileId, 0, "and no tile offset without a dict entry")
end

-- BattleAnimCmd_ClearObjs only reaches six and two thirds structs, so 8, 9
-- and 10 survive it (docs/bugs_and_glitches.md).
local pool = AnimObjects.new(data, consts, { battleTurn = 0 })
for _ = 1, 10 do pool:queue("BATTLE_ANIM_OBJ_HIT", 0x40, 0x40, 0) end
eq(pool:activeCount(), 10, "ten structs is the whole pool")
pool:clearObjs()
eq(pool:activeCount(), 3, "anim_clearobjs leaves the last three running")

-- BATTLE_ANIM_FUNC_NULL only deletes once anim_incobj has walked it past
-- .zero; before that it does nothing at all.
local nullObj = AnimObjects.new(data, consts, { battleTurn = 0 })
local nst = nullObj:queue("BATTLE_ANIM_OBJ_ABSORB_CENTER", 0x40, 0x40, 0)
AnimObjects.FUNCTIONS.BATTLE_ANIM_FUNC_NULL(nullObj, nst)
eq(nst.index, 1, "FUNC_NULL at jumptable 0 is a no-op")
nst.jt = 1
AnimObjects.FUNCTIONS.BATTLE_ANIM_FUNC_NULL(nullObj, nst)
eq(nst.index, 0, "and deletes the object at 1")

-- BattleAnim_StepToTarget: the lower nybble is the x step and half of it the
-- y step, and a y step of 0 walks the coordinate 256 times -- back to where it
-- started, not once.
local step = AnimObjects.new(data, consts, { battleTurn = 0 })
local sst = step:queue("BATTLE_ANIM_OBJ_HIT", 0x40, 0x40, 4)
sst.jt = 0
AnimObjects.FUNCTIONS.BATTLE_ANIM_FUNC_USER_TO_TARGET(step, sst)
eq(sst.x, 0x44, "a param of 4 moves four right")
eq(sst.y, 0x3e, "and two up")

-- BgEffects: the shake's amplitude is the struct's BATTLE_TURN field, which
-- flips sign every time the PARAM countdown reloads.
local BgEffects = require("src.battle.gen2.BgEffects")
local bg = BgEffects.new(consts, { battleTurn = 0 })
bg:queue("BATTLE_BG_EFFECT_SHAKE_SCREEN_X", 0x10, 2, 0x22)
bg:playFrame()
eq(bg.scx, 2, "the first frame shakes by the amplitude it was given")
for _ = 1, 2 do bg:playFrame() end
eq(bg.scx, 0xfe, "and flips to -2 once the period runs out")
for _ = 1, 40 do bg:playFrame() end
eq(bg.scx, 0, "the shake ends flat")
eq(bg:activeCount(), 0, "and frees its struct")

-- Tackle's BG effect writes the attacker's own scanlines: on the player's
-- turn that is $2f-$5e, and SCX goes NEGATIVE because the player's mon steps
-- to the right.
local tack = BgEffects.new(consts, { battleTurn = 0 })
tack:queue("BATTLE_BG_EFFECT_TACKLE", 0, 1, 0)
tack:playFrame()
eq(tack.lyStart, 0x2f, "the player's window starts at scanline $2f")
eq(tack.lyEnd, 0x5f, "and ends one past $5e")
eq(tack.lcdc, "SCX", "through rSCX")
tack:playFrame()
eq(tack.lyBackup[0x30], 0,
  "Tackle_MoveForward writes the distance so far BEFORE stepping it")
tack:playFrame()
eq(tack.lyBackup[0x30], 0xfe,
  "so the step only shows on the frame after: two pixels right")

-- The intro slide is 72 frames from $90 and $70 to nothing at all.
local BattleAnimView = require("src.ui.gen2.BattleAnimView")
eq(BattleAnimView.SLIDE_FRAMES, 72, "BattleIntroSlidingPics runs 72 frames")
local top, middle = BattleAnimView.slideOffsets(0)
eq(top, 0x90, "the enemy's half starts a screen and a half to the right")
eq(middle, 0x70, "and the player's to the left")
top, middle = BattleAnimView.slideOffsets(72)
eq(top, 0, "both land on zero")
eq(middle, 0, "at the same frame")


-- ------------------------------------------------ the screen deformations
--
-- The thirteen effects that used to be BgEffects.UNMODELLED.  Each one is a
-- DeformScreen / DeformWater / surf-ring shape, so the assertions here are
-- about the ARRAY the effect writes rather than what it looks like.

check(#BgEffects.UNMODELLED == 0,
  "every BG effect is modelled (" .. #BgEffects.UNMODELLED .. " left)")

-- DeformScreen writes only lyStart < row <= lyEnd, but advances its phase on
-- every one of its $80 iterations -- so WHERE the window sits changes which
-- part of the wave lands on it.
local deform = BgEffects.new(consts, { battleTurn = 0 })
deform.lyStart, deform.lyEnd = 0x10, 0x20
deform:deformScreen(2, 2)
eq(deform.lyBackup[0x10], 0, "DeformScreen leaves the row AT lyStart alone")
eq(deform.lyBackup[0x21], 0, "and the row past lyEnd")
-- Row n takes sine(2n) at amplitude 2, which is the phase after n iterations.
local SpriteAnims = require("src.ui.gen2.SpriteAnims")
eq(deform.lyBackup[0x18], SpriteAnims.sine(0x18 * 2, 2),
  "and the value on a row is the phase that iteration had reached")

-- WavyScreenFX rotates the window up one, the top row wrapping to the bottom.
local wavy = BgEffects.new(consts, { battleTurn = 0 })
wavy.lyStart, wavy.lyEnd = 4, 8
for row = 4, 8 do wavy.lyBackup[row] = row end
wavy:wavyScreenFX()
eq(wavy.lyBackup[4], 5, "the wave travels up a scanline a frame")
eq(wavy.lyBackup[7], 8, "...all the way to the end of the window")
eq(wavy.lyBackup[8], 4, "...and the top row wraps around to the bottom")

-- Teleport: one DeformScreen, then a rotation a frame, then the registers go
-- back.  The player's window is $2f-$5e.
local tele = BgEffects.new(consts, { battleTurn = 0 })
tele:queue("BATTLE_BG_EFFECT_TELEPORT", 0, 1, 0)
tele:playFrame()
eq(tele.lcdc, "SCX", "Teleport warps horizontally")
eq(tele.lyStart, 0x2f, "over the user's own rows")
local before = tele.lyBackup[0x40]
tele:playFrame()
eq(tele.lyBackup[0x3f], before, "and the wave moves up one row a frame")
tele:incEffect("BATTLE_BG_EFFECT_TELEPORT")
tele:playFrame()
eq(tele.lcdc, nil, "the third state puts the registers back")
eq(tele:activeCount(), 0, "and frees the struct")

-- Psychic covers the whole screen whichever side used it, and only travels
-- every fourth frame.
local psy = BgEffects.new(consts, { battleTurn = 0 })
psy:queue("BATTLE_BG_EFFECT_PSYCHIC", 0, 1, 0)
psy:playFrame()
eq(psy.lyStart, 0, "Psychic is hardcoded to the whole screen")
eq(psy.lyEnd, 0x5f, "...all $5f scanlines of it")
-- `ld a, [hl] / inc [hl] / and $3 / ret nz`: the PRE-increment counter, so the
-- first frame in state 1 does travel and the next three do not.  Compare the
-- whole window rather than one row: at amplitude 6 plenty of neighbouring
-- rows happen to hold the same byte.
local function snapshot(pool)
  local out = {}
  for row = pool.lyStart, pool.lyEnd - 1 do out[row] = pool.lyBackup[row] end
  return out
end
local function rotatedBy(before, pool, steps)
  for row = pool.lyStart, pool.lyEnd - 1 - steps do
    if pool.lyBackup[row] ~= before[row + steps] then return false end
  end
  return true
end
local laid = snapshot(psy)
psy:playFrame()
check(rotatedBy(laid, psy, 1), "the first frame of state 1 travels one row")
local held = snapshot(psy)
for _ = 1, 3 do psy:playFrame() end
check(rotatedBy(held, psy, 0), "then three frames pass with it standing still")
psy:playFrame()
check(rotatedBy(held, psy, 1), "and it moves again on the fourth")

-- Whirlpool rolls VERTICALLY, over both battlers at once.
local whirl = BgEffects.new(consts, { battleTurn = 0 })
whirl:queue("BATTLE_BG_EFFECT_WHIRLPOOL", 0, 0, 0)
whirl:playFrame()
eq(whirl.lcdc, "SCY", "Whirlpool scrolls vertically")
eq(whirl.lyEnd, 0x5e, "over the whole screen, not one pic box")

-- Surf: the ring is laid down on the first frame, and `.one` refuses to paint
-- engine/battle_anims/functions.asm:1148, the SURF OBJECT, is what does.
local surf = BgEffects.new(consts, { battleTurn = 0 })
surf:queue("BATTLE_BG_EFFECT_SURF", 0, 0, 0)
surf:playFrame()
check(surf.surfWave ~= nil, "Surf builds its $40-byte wave ring")
eq(surf.lyBackup[0x20], 0, "but paints nothing without an LCDC pointer")

-- data/moves/animations.asm:1126 BattleAnim_Surf, driven whole.
local surfRun = runner(data.moves.SURF, { animId = "SURF" })
local surfOpened, surfPainted = false, false
for _ = 1, 120 do
  if not surfRun:step() then break end
  if surfRun.bg.lcdc == "SCY" and surfRun.bg.lyEnd == 0x5e then
    surfOpened = true
  end
  if surfOpened then
    for row = 1, 0x5e do
      if (surfRun.bg.lyBackup[row] or 0) ~= 0 then surfPainted = true end
    end
  end
end
check(surfOpened, "the Surf object opens the window the BG effect waits on")
check(surfPainted, "so the water rolls across the scanlines")

-- The three water effects as a set: START opens the window and ends itself,
-- WATER grows two scanlines a frame until its counter passes $20, END resets.
local water = BgEffects.new(consts, { battleTurn = 0 })
water:queue("BATTLE_BG_EFFECT_START_WATER", 0, 0, 0)
water:playFrame()
eq(water.lcdc, "SCY", "START_WATER opens a vertical window")
eq(water:activeCount(), 0, "and frees its struct on the same frame")
water:queue("BATTLE_BG_EFFECT_WATER", 0x18, 0, 0)
water:playFrame()
eq(water.effects[1].turn, 2, "WATER's counter climbs two a frame")
for _ = 1, 20 do water:playFrame() end
eq(water:activeCount(), 0, "and it ends once the counter passes $20")

-- Double Team's afterimage: alternate rows +n and -n.
local dt = BgEffects.new(consts, { battleTurn = 0 })
dt:queue("BATTLE_BG_EFFECT_DOUBLE_TEAM", 0, 1, 0)
dt:playFrame() -- state 0: open the window
dt:playFrame() -- state 1: first split, at 0
dt:playFrame() -- ...and again, at 1
eq(dt.lyBackup[0x2f], 1, "one copy of the pic goes right")
eq(dt.lyBackup[0x30], 0xff, "and the row under it goes left by the same")
for _ = 1, 20 do dt:playFrame() end
eq(dt.effects[1].jt, 2, "the split stops at $10 and waits for the script")

-- Acid Armor scrolls the window down a row a frame with a blank fed in on top.
local acid = BgEffects.new(consts, { battleTurn = 0 })
acid:queue("BATTLE_BG_EFFECT_ACID_ARMOR", 0, 1, 4)
acid:playFrame()
local sank = acid.lyBackup[0x40]
acid:playFrame()
eq(acid.lyBackup[0x41], sank, "the wave sinks a scanline a frame")
eq(acid.lyBackup[0x2f], 0x90, "with a blank row fed in at the top")

-- Wave Deform ramps its amplitude up to $20 and, in state 2, back to nothing.
local wd = BgEffects.new(consts, { battleTurn = 0 })
wd:queue("BATTLE_BG_EFFECT_WAVE_DEFORM_MON", 0, 1, 0)
wd:playFrame()
for _ = 1, 40 do wd:playFrame() end
eq(wd.effects[1].param, 0x20, "the ramp stops at $20 rather than wrapping")
wd:incEffect("BATTLE_BG_EFFECT_WAVE_DEFORM_MON")
for _ = 1, 0x21 do wd:playFrame() end
eq(wd:activeCount(), 0, "and the way back down ends the effect")

-- The two unused beta send-outs still run to completion rather than sitting
-- in the pool forever.
local beta1 = BgEffects.new(consts, { battleTurn = 0 })
beta1:queue("BATTLE_BG_EFFECT_BETA_SEND_OUT_MON1", 0, 1, 0)
beta1:playFrame()
eq(beta1.lcdc, "BGP", "the beta send-out writes a PALETTE per scanline")
beta1:incEffect("BATTLE_BG_EFFECT_BETA_SEND_OUT_MON1")
for _ = 1, 40 do beta1:playFrame() end
eq(beta1.effects[1].jt, 3, "the first blind pass hands on to the second")
for _ = 1, 40 do beta1:playFrame() end
eq(beta1.effects[1].jt, 4, "and that one ends on the script's own state")
beta1:incEffect("BATTLE_BG_EFFECT_BETA_SEND_OUT_MON1")
beta1:playFrame()
eq(beta1:activeCount(), 0, "state five frees the struct")

local beta2 = BgEffects.new(consts, { battleTurn = 0 })
beta2:queue("BATTLE_BG_EFFECT_BETA_SEND_OUT_MON2", 0, 1, 0)
beta2:playFrame()
eq(beta2.effects[1].turn, 0x40, "MON2 counts down from $40")
for _ = 1, 0x42 do beta2:playFrame() end
eq(beta2:activeCount(), 0, "and unwinds to nothing on its own")

-- A per-scanline BGP entry reads as a brightness: $00 is white, $ff black,
-- $e4 the identity.
local AnimView = require("src.ui.gen2.BattleAnimView")
eq(AnimView.palVeil(0xe4), 0, "$e4 is no veil at all")
eq(AnimView.palVeil(0xff), 1, "$ff is solid black")
eq(AnimView.palVeil(0x00), -1, "$00 is solid white")

S.finish()
