-- The Gen 2 battle-animation command interpreter.
--
-- pokegold engine/battle_anims/anim_commands.asm: RunBattleAnimScript's frame
-- loop and the 48-entry BattleAnimCommands jumptable it dispatches through.
-- The scripts themselves are already disassembled into the cache by
-- RomExtractorGen2 (`data/generated/battle_anims.lua`), keyed by their ROM
-- address because that is what a branch names.
--
-- One frame of an animation is exactly three things, in this order:
--
--   RunBattleAnimCommand   run script bytes until one asks to wait
--   ExecuteBGEffects       one pass over the five BG-effect structs
--   BattleAnim_UpdateOAM_All   one pass over the ten object structs
--
-- so `step()` here is one 60 Hz frame and nothing else needs a clock.  The
-- animation is over when a `ret` runs outside a subroutine, which is what
-- BATTLEANIM_STOP_F means.
--
-- Two things about the script format that are easy to get wrong and are
-- already handled by the extractor, repeated here because this is where they
-- bite: anything under $d0 is `anim_wait <n>` and carries no arguments, and a
-- branch's target is the LAST two bytes of the command, which the extractor
-- has already rewritten into a pool key.
--
-- Love-free: sound and cries go out through the `hooks` table the battle
-- screen supplies, so a test can step a whole animation and assert what it
-- asked to play.

local bit = require("bit")
local AnimObjects = require("src.battle.gen2.AnimObjects")
local BgEffects = require("src.battle.gen2.BgEffects")

local AnimRunner = {}
local Runner = {}
Runner.__index = Runner

-- wBattleAnimTileDict is five {gfx id, tile id} pairs.
local NUM_TILEDICT_ENTRIES = 5
-- BATTLEANIM_BASE_TILE is 7*7; the sheets share the tiles above it up to
-- vTiles1, so the running allocator stops at 128 - 49.
local MAX_ANIM_TILES = 128 - 49

-- BattleAnimCmd_BattlerGFX_*: the battlers' own pic tiles are registered in
-- the dict at fixed ids rather than loaded from AnimObjGFX.  These are the
-- ASM's `($80 - 6 - 7) - BATTLEANIM_BASE_TILE` and friends.
local BATTLER_TILES = {
  oneRow = { player = (0x80 - 6 - 7) - 49, enemy = (0x80 - 6) - 49 },
  twoRow = { player = (0x80 - 6 * 2 - 7 * 2) - 49, enemy = (0x80 - 6 * 2) - 49 },
}

-- BattleAnimCmd_Cry's .CryData: a pitch and a length added to the mon's own
-- cry, indexed by the command's argument masked to NUM_NOISE_CHANS.
local CRY_DATA = {
  [0] = { pitch = 0x0000, length = 0x00c0 },
  [1] = { pitch = 0x0000, length = 0x0040 },
  [2] = { pitch = 0x0000, length = 0x0000 },
  [3] = { pitch = 0x0000, length = 0x0000 },
}

-- BattleAnimCmd_Sound's .GetPanning, indexed by the cry-track pair.
local PANNING = { [0] = 0xf0, [1] = 0x0f, [2] = 0xf0, [3] = 0x0f }

--------------------------------------------------------------------------

-- opts:
--   data        the cache's battle_anims.lua
--   constants   the cache's constants.lua
--   battleTurn  hBattleTurn -- 0 while the player is attacking
--   param       wBattleAnimParam, which the effect layer sets (hit count,
--               stat direction, the Beat Up party slot...)
--   animId      the move (or ANIM_* id) whose script this is
--   hooks       { sound(name, panning, duration), cry(side, pitch, length) }
--   ballPalette the PAL_BATTLE_OB_* name for the ball being thrown
function AnimRunner.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Runner)
  self.data = opts.data or {}
  self.constants = opts.constants or {}
  self.hooks = opts.hooks or {}
  -- Shared by both pools; the object functions and the BG effects read the
  -- same hBattleTurn.
  self.env = {
    battleTurn = opts.battleTurn or 0,
    animId = opts.animId,
    ballPalette = opts.ballPalette,
    sgb = opts.sgb,
    flying = opts.flying or {},
  }
  self.objects = AnimObjects.new(self.data, self.constants, self.env)
  self.bg = BgEffects.new(self.constants, self.env)
  self.gfxOrder = self.constants.battleAnimGfxOrder or {}
  self.sfxOrder = opts.sfxOrder or {}

  self.param = opts.param or 0 -- wBattleAnimParam
  self.var = 0                 -- wBattleAnimVar
  self.delay = 0               -- wBattleAnimDelay
  self.loops = 0               -- wBattleAnimLoops
  self.inSubroutine = false
  self.inLoop = false
  self.stopped = false
  self.keepSprites = false
  self.frames = 0
  -- wBattleAnimTileDict, and the sheets it points at.
  self.tileDict = {}
  self.loaded = {}
  -- Set by the substitute / minimize / transform commands, for the view.
  self.picOverride = { player = nil, enemy = nil }
  self.address = nil
  self.parent = nil
  return self
end

-- ClearBattleAnims: the whole animation block, then the entry point.
function Runner:start(scriptKey)
  self.objects:clear()
  self.bg:reset()
  self.var, self.delay, self.loops = 0, 0, 0
  self.inSubroutine, self.inLoop, self.stopped = false, false, false
  self.keepSprites = false
  self.frames = 0
  self.tileDict = {}
  self.loaded = {}
  self.picOverride = { player = nil, enemy = nil }
  self.address = scriptKey and { key = scriptKey, index = 1 } or nil
  self.parent = nil
  return self
end

-- The script for a move, or nil when the cache has none (which is what an
-- unextracted or modded move looks like).
function AnimRunner.scriptForMove(data, moveId)
  local moves = (data or {}).moves or {}
  return moves[moveId]
end

function Runner:scriptRows(key)
  return (self.data.scripts or {})[key]
end

-- GetBattleAnimByte, one decoded row at a time.
function Runner:fetch()
  local at = self.address
  if not at then return nil end
  local rows = self:scriptRows(at.key)
  if not rows then return nil end
  local row = rows[at.index]
  if not row then return nil end
  at.index = at.index + 1
  return row
end

-- The three "skip the branch target" tails: a conditional that does not take
-- its branch steps the address past the two address bytes, which in a decoded
-- row list is simply "carry on".
function Runner:jumpTo(key)
  self.address = { key = key, index = 1 }
end

--------------------------------------------------------------------------
-- The tile dict
--------------------------------------------------------------------------

-- GetBattleAnimTileOffset: the dict is scanned for the gfx id and its tile
-- returned; a miss is 0, which is why an object whose sheet the script never
-- loaded draws whatever happens to sit at the base tile.
function Runner:tileOffsetFor(gfxId)
  for i = 1, NUM_TILEDICT_ENTRIES do
    local entry = self.tileDict[i]
    if entry and entry.gfx == gfxId then return entry.tile end
  end
  return 0
end

-- BattleAnimCmd_1GFX..5GFX.  The running tile id restarts at 0 for every
-- command and each sheet is laid down after the last, so two animations that
-- load different sheet counts do not agree about where anything is -- which
-- is exactly why the dict exists.  Entries past the count are NOT cleared.
function Runner:loadGfx(names)
  local tile = 0
  for slot, gfxId in ipairs(names) do
    if tile >= MAX_ANIM_TILES then break end
    local name = gfxId
    if type(gfxId) == "number" then
      name = self.gfxOrder[gfxId + 1] or gfxId
    end
    self.tileDict[slot] = { gfx = name, tile = tile }
    local sheet = (self.data.gfx or {})[name]
    self.loaded[#self.loaded + 1] = {
      gfx = name, tile = tile, tiles = (sheet and sheet.tiles) or 0,
    }
    tile = tile + ((sheet and sheet.tiles) or 0)
  end
end

-- engine/battle_anims/anim_commands.asm:755.  The jumptable crosses the macro
-- names: $d9 (anim_battlergfx_2row) dispatches to _1Row (#1401)
function Runner:loadBattlerGfx(rows)
  local tiles = rows == 2 and BATTLER_TILES.twoRow or BATTLER_TILES.oneRow
  local slot = 1
  while slot <= NUM_TILEDICT_ENTRIES and self.tileDict[slot] do
    slot = slot + 1
  end
  if slot + 1 > NUM_TILEDICT_ENTRIES then return end
  self.tileDict[slot] = { gfx = "BATTLE_ANIM_GFX_PLAYERHEAD", tile = tiles.player }
  self.tileDict[slot + 1] = { gfx = "BATTLE_ANIM_GFX_ENEMYFEET", tile = tiles.enemy }
  self.loaded[#self.loaded + 1] =
    { gfx = "BATTLE_ANIM_GFX_PLAYERHEAD", tile = tiles.player, tiles = rows * 7,
      battler = "enemy", rows = rows }
  self.loaded[#self.loaded + 1] =
    { gfx = "BATTLE_ANIM_GFX_ENEMYFEET", tile = tiles.enemy, tiles = rows * 6,
      battler = "player", rows = rows }
end

--------------------------------------------------------------------------
-- BattleAnimCommands
--------------------------------------------------------------------------

local C = {}

C.obj = function(self, row)
  self.objects:queue(row[2], row[3], row[4], row[5], function(gfx)
    return self:tileOffsetFor(gfx)
  end)
end

for count = 1, 5 do
  C[count .. "gfx"] = function(self, row)
    local names = {}
    for i = 1, count do names[i] = row[i + 1] end
    self:loadGfx(names)
  end
end

C.incobj = function(self, row)
  local st = self.objects:findByIndex(row[2])
  if st then st.jt = AnimObjects.u8(st.jt + 1) end
end

C.setobj = function(self, row)
  local st = self.objects:findByIndex(row[2])
  if st then st.jt = AnimObjects.u8(row[3]) end
end

C.incbgeffect = function(self, row) self.bg:incEffect(row[2]) end

-- anim_commands.asm:317: $d9 (anim_battlergfx_2row) dispatches to _1Row
C.battlergfx_1row = function(self) self:loadBattlerGfx(2) end
C.battlergfx_2row = function(self) self:loadBattlerGfx(1) end

-- GetPokeBallWobble's answer, which the ball's own script then branches on.
C.checkpokeball = function(self)
  self.var = self.hooks.pokeballWobble and self.hooks.pokeballWobble() or 0
end

-- The commands that swap a battler's pic out for something else.  The port
-- records which, and the view draws it.
--
-- Every one of them branches on hBattleTurn the same way
-- (engine/battle_anims/anim_commands.asm): `and a / jr z, .player`, and the
-- .player arm is the one that writes vTiles2 tile $31, the 6x6 BACKPIC slot.
-- So turn 0, the player attacking, always repaints the PLAYER's own pic, and
-- the fall-through arm (tile $00, the 7x7 frontpic) repaints the enemy's.
C.transform = function(self)
  -- BattleAnimCmd_Transform: .player loads wTempEnemyMonSpecies into the
  -- backpic slot, i.e. the player's sprite becomes what it transformed into.
  local side = self.env.battleTurn == 0 and "player" or "enemy"
  self.picOverride[side] = "transform"
end

C.raisesub = function(self)
  local side = self.env.battleTurn == 0 and "player" or "enemy"
  self.picOverride[side] = "substitute"
end

C.dropsub = function(self)
  local side = self.env.battleTurn == 0 and "player" or "enemy"
  self.picOverride[side] = false
end

-- BattleAnimCmd_MinimizeOpp / GetMinimizePic: despite the name it shrinks the
-- ATTACKER, because .player (turn 0) requests the 6x6 block at tile $31.  The
-- other minimize opcode, $e9, is one of the dummies below.
C.minimizeopp = function(self)
  local side = self.env.battleTurn == 0 and "player" or "enemy"
  self.picOverride[side] = "minimize"
end

C.beatup = function(self)
  -- wBattleAnimParam is the party slot whose pic to show.
  local side = self.env.battleTurn == 0 and "player" or "enemy"
  self.picOverride[side] = { kind = "beatup", slot = self.param }
end

C.resetobp0 = function(self)
  self.bg.obp0 = self.env.sgb and 0xf0 or 0xe0
end

C.sound = function(self, row)
  local packed = row[2] or 0
  -- The first byte is BOTH the duration (its top six bits) and the cry-track
  -- pair (its bottom two), which is why the same value reads twice here.
  local duration = bit.rshift(packed, 2)
  local tracks = bit.band(packed, 3)
  if self.env.battleTurn ~= 0 then tracks = bit.bxor(tracks, 1) end
  local id = row[3] or 0
  local name = self.sfxOrder[id + 1]
  if self.hooks.sound then
    self.hooks.sound(name, PANNING[tracks] or 0xff, duration, id)
  end
end

C.cry = function(self, row)
  local slot = bit.band(row[2] or 0, 3)
  local entry = CRY_DATA[slot] or CRY_DATA[0]
  local side = self.env.battleTurn == 0 and "player" or "enemy"
  if self.hooks.cry then self.hooks.cry(side, entry.pitch, entry.length) end
end

C.clearobjs = function(self) self.objects:clearObjs() end

C.oamon = function() end
C.oamoff = function() end
C.updateactorpic = function() end
-- $e7 and $e8-$ed are `ret` on the cart; $f5-$f7 too.  $e9 is `minimize`, and
-- it really is one of them: BattleAnimCmd_E8 through BattleAnimCmd_ED are six
-- labels stacked on a single `ret` (engine/battle_anims/anim_commands.asm).
-- The minimize animation that is actually drawn is $e2, minimizeopp above.
C.minimize = function() end
C.unknown_e7 = function() end
C.unknown_ea = function() end
C.unknown_eb = function() end
C.unknown_ec = function() end
C.unknown_ed = function() end
C.unknown_f5 = function() end
C.unknown_f6 = function() end
C.unknown_f7 = function() end

C.keepsprites = function(self) self.keepSprites = true end

C.bgp = function(self, row) self.bg.bgp = row[2] end
C.obp0 = function(self, row) self.bg.obp0 = row[2] end
C.obp1 = function(self, row) self.bg.obp1 = row[2] end

C.bgeffect = function(self, row)
  self.bg:queue(row[2], row[3], row[4], row[5])
end

C.setvar = function(self, row) self.var = AnimObjects.u8(row[2]) end
C.incvar = function(self) self.var = AnimObjects.u8(self.var + 1) end

C.if_var_equal = function(self, row)
  if row[2] == self.var then self:jumpTo(row[3]) end
end

C.if_param_equal = function(self, row)
  if row[2] == self.param then self:jumpTo(row[3]) end
end

C.if_param_and = function(self, row)
  if bit.band(self.param, row[2] or 0) ~= 0 then self:jumpTo(row[3]) end
end

-- The one conditional that CONSUMES what it tests: each pass decrements
-- wBattleAnimParam, so `anim_jumpuntil` runs its block param times.
C.jumpuntil = function(self, row)
  if self.param == 0 then return end
  self.param = AnimObjects.u8(self.param - 1)
  self:jumpTo(row[2])
end

C.jump = function(self, row) self:jumpTo(row[2]) end

C.loop = function(self, row)
  local count = row[2] or 0
  if not self.inLoop then
    -- A count of 0 loops forever and never claims the loop flag.
    if count ~= 0 then
      self.inLoop = true
      self.loops = AnimObjects.u8(count - 1)
    end
    self:jumpTo(row[3])
    return
  end
  if self.loops == 0 then
    self.inLoop = false
    return -- falls through past the target
  end
  self.loops = self.loops - 1
  self:jumpTo(row[3])
end

C.call = function(self, row)
  self.parent = { key = self.address.key, index = self.address.index }
  self.inSubroutine = true
  self:jumpTo(row[2])
end

C.ret = function(self)
  self.inSubroutine = false
  self.address = self.parent
    and { key = self.parent.key, index = self.parent.index } or nil
end

--------------------------------------------------------------------------

-- RunBattleAnimCommand: burn the delay, otherwise run script rows until one
-- of them asks to wait or the animation ends.
function Runner:runCommands()
  if self.delay ~= 0 then
    self.delay = self.delay - 1
    return
  end
  for _ = 1, 512 do
    local row = self:fetch()
    if not row then
      self.stopped = true
      return
    end
    local cmd = row[1]
    if cmd == "ret" then
      -- A `ret` outside a subroutine is what ends the whole animation.
      if not self.inSubroutine then
        self.stopped = true
        return
      end
      C.ret(self, row)
    elseif cmd == "wait" then
      self.delay = row[2] or 0
      return
    else
      local fn = C[cmd]
      if fn then fn(self, row) end
    end
  end
  -- A script that never waits would hang the battle; stopping is the only
  -- honest thing to do with one.
  self.stopped = true
end

-- One frame.  Returns false once the animation is over.
function Runner:step()
  if self.stopped then return false end
  self.frames = self.frames + 1
  self:runCommands()
  self.bg:playFrame()
  -- A BG effect can ask for an object (the battler-pic ones do), and it has
  -- to land before the object pass or it would be a frame late.
  for _, spawn in ipairs(self.bg:takeSpawns()) do
    self.objects:queue(spawn.object, spawn.x, spawn.y, spawn.param,
      function(gfx) return self:tileOffsetFor(gfx) end)
  end
  self.objects:playFrame()
  -- Rollout hands the shake to the first object's Y offset.
  if self.bg.rolloutYOffset then
    local first = self.objects.structs[1]
    if first and first.index ~= 0 then first.yOffset = self.bg.rolloutYOffset end
  end
  if self.stopped then
    -- BattleAnim_ClearOAM: unless the script asked to keep them, every object
    -- goes at the end.
    if not self.keepSprites then self.objects.oam = {} end
    return false
  end
  return true
end

function Runner:oam() return self.objects.oam end
function Runner:done() return self.stopped end

AnimRunner.COMMANDS = C
AnimRunner.NUM_TILEDICT_ENTRIES = NUM_TILEDICT_ENTRIES
AnimRunner.MAX_ANIM_TILES = MAX_ANIM_TILES
AnimRunner.BATTLER_TILES = BATTLER_TILES

return AnimRunner
