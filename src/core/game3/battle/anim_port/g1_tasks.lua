local bit = require("bit")
local P = require("src.core.game3.battle.anim_port.g1_pret")
local S = require("src.core.game3.battle.anim_port.g1_sprite")
local K = require("src.core.game3.battle.anim_port.g1_task_base")

local band, bor, bxor, rshift, arshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.arshift, bit.lshift
local s16, u16 = P.s16, P.u16
local Sin, Cos = P.Sin, P.Cos
local cdiv = P.cdiv
local Pal = P.Pal

local T = {}
local F = {}

local function tag_key(vm, tagId)
  local name = P.tagIdToName(vm, tagId)
  return name and ("tag:" .. name) or nil, name
end

-- pokefirered/src/battle_anim_normal.c:437
local function blend_cycle(t, keys, start, target)
  P.beginNormalPaletteFade(keys, t.data[1], start, target, u16(t.data[5]))
  t.data[2] = t.data[2] - 1
  t.data[8] = bxor(t.data[8], 1)
end

-- pokefirered/src/battle_anim_normal.c:451
local function blend_cycle_loop(t)
  if not P.fadeActive() then
    local d = t.data
    if d[2] > 0 then
      local start, target
      if d[8] == 0 then
        start, target = d[3], d[4]
      else
        start, target = d[4], d[3]
      end
      if d[2] == 1 then target = 0 end
      blend_cycle(t, t._keys, start, target)
    else
      K.destroy(t)
    end
  end
end

local function blend_cycle_init(t, keys)
  local A, d = t._A, t.data
  d[0] = A[0]
  d[1] = A[1]
  d[2] = A[2]
  d[3] = A[3]
  d[4] = A[4]
  d[5] = A[5]
  d[8] = 0
  t._keys = keys
  blend_cycle(t, keys, 0, d[4])
  t._fn = blend_cycle_loop
end

-- pokefirered/src/battle_anim_normal.c:424
T.BlendColorCycle = K.wrap(function(t, vm)
  blend_cycle_init(t, P.unpackSelected(vm, t._A[0]))
end)

-- pokefirered/src/battle_anim_normal.c:484
T.BlendColorCycleExclude = K.wrap(function(t, vm)
  local keys = {}
  if t._A[0] == 1 then keys[#keys + 1] = "bg" end
  blend_cycle_init(t, keys)
end)

-- pokefirered/src/battle_anim_normal.c:559
T.BlendColorCycleByTag = K.wrap(function(t, vm)
  local key = tag_key(vm, t._A[0])
  blend_cycle_init(t, key and { key } or {})
end)

-- pokefirered/src/battle_anim_normal.c:686
local function flash_tag_step2(t)
  if not P.fadeActive() then
    P.beginNormalPaletteFade(t._keys, 0, 0, 0, 0)
    K.destroy(t)
  end
end

-- pokefirered/src/battle_anim_normal.c:652
local function flash_tag_step1(t)
  local d = t.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    return
  end
  if P.fadeActive() then return end
  if d[2] == 0 then
    t._fn = flash_tag_step2
    return
  end
  if band(d[1], 0x100) ~= 0 then
    P.beginNormalPaletteFade(t._keys, 0, d[4], d[4], u16(d[3]))
  else
    P.beginNormalPaletteFade(t._keys, 0, d[6], d[6], u16(d[5]))
  end
  d[1] = bxor(d[1], 0x100)
  d[0] = band(d[1], 0xFF)
  d[2] = d[2] - 1
end

-- pokefirered/src/battle_anim_normal.c:631
T.FlashAnimTagWithColor = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  for i = 1, 6 do d[i] = A[i] end
  d[0] = A[1]
  d[7] = A[0]
  local key = tag_key(vm, A[0])
  t._keys = key and { key } or {}
  P.beginNormalPaletteFade(t._keys, 0, A[4], A[4], u16(A[3]))
  t._fn = flash_tag_step1
end)

-- pokefirered/src/battle_anim_normal.c:698
T.InvertScreenColor = K.wrap(function(t, vm)
  local A = t._A
  if band(A[0], 0x100) ~= 0 then Pal.invert("bg") end
  if band(A[1], 0x100) ~= 0 then Pal.invert(P.atk(vm)) end
  if band(A[2], 0x100) ~= 0 then Pal.invert(P.tgt(vm)) end
  Pal.flush()
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_normal.c:864
local function shake_terrain_set(vm, x, y)
  local Anim = P.anim()
  if vm then
    vm.bg3 = vm.bg3 or { x = 0, y = 0 }
    vm.bg3.x = x
    vm.bg3.y = y
  end
  Anim._bg3Scroll = Anim._bg3Scroll or { x = 0, y = 0 }
  Anim._bg3Scroll.x = x
  Anim._bg3Scroll.y = y
end

local function shake_terrain_get(vm)
  local b = vm and vm.bg3
  if b then return b.x or 0, b.y or 0 end
  local s = P.anim()._bg3Scroll
  return s and s.x or 0, s and s.y or 0
end
F.bg3Set, F.bg3Get = shake_terrain_set, shake_terrain_get

-- pokefirered/src/battle_anim_normal.c:877
local function shake_terrain_step(t, vm)
  local d = t.data
  if d[3] == 0 then
    local x, y = shake_terrain_get(vm)
    if x == d[0] then x = -d[0] else x = d[0] end
    if y == -d[1] then y = 0 else y = -d[1] end
    d[3] = d[8]
    d[2] = d[2] - 1
    if d[2] <= 0 then
      shake_terrain_set(vm, 0, 0)
      K.destroy(t)
      return
    end
    shake_terrain_set(vm, x, y)
  else
    d[3] = d[3] - 1
  end
end

-- pokefirered/src/battle_anim_normal.c:864
T.ShakeBattleTerrain = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  d[0] = A[0]
  d[1] = A[1]
  d[2] = A[2]
  d[3] = A[3]
  d[8] = A[3]
  shake_terrain_set(vm, A[0], A[1])
  t._fn = shake_terrain_step
  t._fn(t, vm)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:184
local function blend_sprite_color_step2(t)
  local d = t.data
  if d[9] == d[2] then
    d[9] = 0
    for _, key in ipairs(t._keys) do Pal.blend(key, d[10], u16(d[5])) end
    Pal.flush()
    if d[10] < d[4] then
      d[10] = d[10] + 1
    elseif d[10] > d[4] then
      d[10] = d[10] - 1
    else
      K.destroy(t)
    end
  else
    d[9] = d[9] + 1
  end
end

-- pokefirered/src/battle_anim_utility_funcs.c:171
local function start_blend_anim_sprite_color(t, keys)
  local A, d = t._A, t.data
  t._keys = keys
  d[2] = A[1]
  if (A[2] or 0) > 16 then
    d[3] = 0
    d[4] = 16
    d[5] = A[2]
    d[10] = 0
  else
    d[3] = A[2]
    d[4] = A[3]
    d[5] = A[4]
    d[10] = A[2]
  end
  t._fn = blend_sprite_color_step2
  t._fn(t)
end

-- pokefirered/src/battle_anim_utility_funcs.c:53
T.BlendBattleAnimPal = K.wrap(function(t, vm)
  local sel = t._A[0]
  local keys = P.unpackSelected(vm, sel)
  if band(sel, 0x80) ~= 0 then keys[#keys + 1] = 0 end
  if band(sel, 0x100) ~= 0 and P.spriteVisible(2) then keys[#keys + 1] = 2 end
  if band(sel, 0x200) ~= 0 then keys[#keys + 1] = 1 end
  if band(sel, 0x400) ~= 0 and P.spriteVisible(3) then keys[#keys + 1] = 3 end
  start_blend_anim_sprite_color(t, keys)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:75
T.BlendBattleAnimPalExclude = K.wrap(function(t, vm)
  local cmd = t._A[0]
  local keys = { "bg" }
  local ex1, ex2
  if cmd == 2 or cmd == 0 then
    if cmd == 2 then keys = {} end
    ex1 = P.atkId(vm)
  elseif cmd == 3 or cmd == 1 then
    if cmd == 3 then keys = {} end
    ex1 = P.tgtId(vm)
  elseif cmd == 4 then
    ex1, ex2 = P.atkId(vm), P.tgtId(vm)
  elseif cmd == 6 then
    keys = {}
    ex1 = bxor(P.atkId(vm), 2)
  elseif cmd == 7 then
    keys = {}
    ex1 = bxor(P.tgtId(vm), 2)
  end
  for _, id in ipairs(P.visibleIds(ex1, ex2)) do keys[#keys + 1] = id end
  start_blend_anim_sprite_color(t, keys)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:123
local CAMOUFLAGE = {
  [0] = P.RGB(12, 24, 2), [1] = P.RGB(0, 15, 2), [2] = P.RGB(30, 24, 11), [3] = P.RGB(0, 0, 18),
  [4] = P.RGB(11, 22, 31), [5] = P.RGB(11, 22, 31), [6] = P.RGB(22, 16, 10), [7] = P.RGB(14, 9, 3),
  [8] = P.RGB(31, 31, 31), [9] = P.RGB(31, 31, 31),
}

function F.battleTerrain(vm)
  local v = K.ctx(vm, "battleTerrain", nil)
  if v == nil then
    local ok, BattleBg = pcall(require, "src.core.game3.battle.bg")
    v = ok and BattleBg.terrainId and BattleBg.terrainId() or 8
  end
  return tonumber(v) or 8
end

T.SetCamouflageBlend = K.wrap(function(t, vm)
  local keys = P.unpackSelected(vm, t._A[0])
  local c = CAMOUFLAGE[F.battleTerrain(vm)]
  if c then t._A[4] = c end
  start_blend_anim_sprite_color(t, keys)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:163
T.BlendParticle = K.wrap(function(t, vm)
  local key = tag_key(vm, t._A[0])
  start_blend_anim_sprite_color(t, key and { key } or {})
end)

-- pokefirered/src/battle_anim_mons.c:1628
local function blend_in_out_step(t)
  local d = t.data
  d[4] = d[4] + 1
  if d[4] >= d[5] then
    d[4] = 0
    if d[6] == 0 then
      d[2] = d[2] + 1
      Pal.blend(t._key, d[2], u16(d[1]))
      if d[2] == d[3] then d[6] = 1 end
    else
      d[2] = d[2] - 1
      Pal.blend(t._key, d[2], u16(d[1]))
      if d[2] == 0 then
        d[7] = d[7] - 1
        if d[7] ~= 0 then
          d[4] = 0
          d[6] = 0
        else
          Pal.flush()
          K.destroy(t)
          return
        end
      end
    end
    Pal.flush()
  end
end

-- pokefirered/src/battle_anim_mons.c:1616
local function blend_in_out_setup(t, key)
  local A, d = t._A, t.data
  t._key = key
  d[1] = A[1]
  d[2] = 0
  d[3] = A[2]
  d[4] = 0
  d[5] = A[3]
  d[6] = 0
  d[7] = A[4]
  t._fn = blend_in_out_step
end

-- pokefirered/src/battle_anim_mons.c:1603
T.BlendMonInAndOut = K.wrap(function(t, vm)
  local side = K.battlerSide(vm, t._A[0])
  if not side then return K.destroy(t) end
  blend_in_out_setup(t, side)
end)

-- pokefirered/src/battle_anim_mons.c:1664
T.BlendPalInAndOutByTag = K.wrap(function(t, vm)
  local key = tag_key(vm, t._A[0])
  if not key then return K.destroy(t) end
  blend_in_out_setup(t, key)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:213
T.HardwarePaletteFade = K.wrap(function(t, vm)
  local A = t._A
  P.beginHardwarePaletteFade(A[0], A[1], A[2], A[3], A[4])
  local okG3, G3 = pcall(require, "src.core.game3.battle.anim_port.g3_pret")
  if okG3 and type(G3) == "table" and G3.ensureColorOverlay then pcall(G3.ensureColorOverlay, vm) end
  t._fn = function(tt)
    if not P.fadeActive() then K.destroy(tt) end
  end
end)

-- pokefirered/src/battle_anim_effects_1.c:4896
T.ConversionAlphaBlend = K.wrap(function(t, vm)
  t._fn = function(tt, v)
    local d = tt.data
    if d[2] == 1 then
      if v and v.args then v.args[7] = -1 end
      d[2] = d[2] + 1
    elseif d[2] == 2 then
      K.destroy(tt)
    else
      d[0] = d[0] + 1
      if d[0] == 4 then
        d[0] = 0
        d[1] = d[1] + 1
        P.setBldAlpha(v, 16 - d[1], d[1])
        if d[1] == 16 then d[2] = d[2] + 1 end
      end
    end
  end
  t._fn(t, vm)
end)

-- pokefirered/src/battle_anim_effects_1.c:4945
T.Conversion2AlphaBlend = K.wrap(function(t, vm)
  t._fn = function(tt, v)
    local d = tt.data
    d[0] = d[0] + 1
    if d[0] == 4 then
      d[0] = 0
      d[1] = d[1] + 1
      P.setBldAlpha(v, d[1], 16 - d[1])
      if d[1] == 16 then K.destroy(tt) end
    end
  end
  t._fn(t, vm)
end)

-- pokefirered/src/battle_anim_effects_1.c:1064
local MAGICAL_LEAF_COLORS = {
  [0] = P.RGB(31, 0, 0), P.RGB(31, 19, 0), P.RGB(31, 31, 0), P.RGB(0, 31, 0),
  P.RGB(5, 14, 31), P.RGB(22, 10, 31), P.RGB(22, 21, 31),
}

-- pokefirered/src/battle_anim_effects_1.c:3668
T.CycleMagicalLeafPal = K.wrap(function(t, vm)
  t._fn = function(tt, v)
    local d = tt.data
    if d[0] == 0 then
      d[0] = d[0] + 1
    elseif d[0] == 1 then
      d[9] = d[9] + 1
      if d[9] >= 0 then
        d[9] = 0
        Pal.blend("tag:LEAF", d[10], MAGICAL_LEAF_COLORS[d[11]])
        Pal.blend("tag:RAZOR_LEAF", d[10], MAGICAL_LEAF_COLORS[d[11]])
        Pal.flush()
        d[10] = d[10] + 1
        if d[10] == 17 then
          d[10] = 0
          d[11] = d[11] + 1
          if d[11] == 7 then d[11] = 0 end
        end
      end
    end
    if v and v.args and s16(v.args[7] or 0) == -1 then K.destroy(tt) end
  end
  t._fn(t, vm)
end)

-- pokefirered/src/battle_anim_effects_1.c:5289
T.MusicNotesRainbowBlend = K.wrap(function(t, vm)
  local AnimPal = require("src.core.game3.battle.anim_pal")
  require("src.core.game3.battle.anim_port.g1_callbacks_b")
  for j = 0, 3 do
    local row = P.PARTICLES_COLOR_BLEND[j]
    local f = nil
    if j == 0 then
      if AnimPal.isLoaded(row[1]) then f = AnimPal.writeFaded(row[1]) end
    else
      AnimPal.alloc(row[1])
      f = AnimPal.writeFaded(row[1])
    end
    if f then
      for i = 1, 5 do f[i] = row[i + 1] end
    end
  end
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_effects_1.c:5317
T.MusicNotesClearRainbowBlend = K.wrap(function(t, vm)
  local AnimPal = require("src.core.game3.battle.anim_pal")
  require("src.core.game3.battle.anim_port.g1_callbacks_b")
  for j = 1, 3 do
    AnimPal.free(P.PARTICLES_COLOR_BLEND[j][1])
  end
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_effects_1.c:5067
local function moonlight_end_fade_step(t, vm)
  local d = t.data
  if d[0] == 0 then
    d[1] = d[1] + 1
    if d[1] > 0 then
      d[1] = 0
      local color
      d[2] = d[2] + 1
      if d[2] <= 15 then
        d[4] = d[4] + d[7]
        d[5] = d[5] + d[8]
        d[6] = d[6] + d[9]
        color = P.RGB(rshift(d[4], 3), rshift(d[5], 3), rshift(d[6], 3))
      else
        color = P.RGB(27, 29, 31)
        d[0] = d[0] + 1
      end
      local r, g, b = P.rgb555(color)
      Pal.setFaded("bg", { m = 0, r = r, g = g, b = b })
      Pal.flush()
    end
  elseif d[0] == 1 then
    if not P.fadeActive() then
      local AnimSprites = require("src.core.game3.battle.anim_sprites")
      AnimSprites.forEachActive(function(s)
        if s.template == "gMoonSpriteTemplate" or s.template == "gMoonlightSparkleSpriteTemplate" then
          s.data[0] = 1
        end
      end)
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 2 then
    d[1] = d[1] + 1
    if d[1] > 30 then
      P.beginNormalPaletteFade({ "bg", "player", "enemy" }, 0, 16, 0, P.RGB(27, 29, 31))
      d[0] = d[0] + 1
    end
  elseif d[0] == 3 then
    if not P.fadeActive() then K.destroy(t) end
  end
end

-- pokefirered/src/battle_anim_effects_1.c:5040
T.MoonlightEndFade = K.wrap(function(t, vm)
  local d = t.data
  for i = 0, 6 do d[i] = 0 end
  d[7] = 13
  d[8] = 14
  d[9] = 15
  P.beginNormalPaletteFade({ "player", "enemy", "tag:MOON", "tag:GREEN_SPARKLE" }, 0, 0, 16, P.RGB(27, 29, 31))
  t._fn = moonlight_end_fade_step
  t._fn(t, vm)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:838
T.GetBattleTerrain = K.wrap(function(t, vm)
  if vm and vm.args then vm.args[0] = F.battleTerrain(vm) end
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:844
T.AllocBackupPalBuffer = K.wrap(function(t, vm)
  Pal.backup = {}
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:850
T.FreeBackupPalBuffer = K.wrap(function(t, vm)
  Pal.backup = {}
  K.destroy(t)
end)

local function pal_sel_key(vm, sel)
  if sel == 0 then return "bg" end
  if sel == 1 then return P.atk(vm) end
  if sel == 2 then return P.tgt(vm) end
  return nil
end

-- pokefirered/src/battle_anim_utility_funcs.c:856
T.CopyPalUnfadedToBackup = K.wrap(function(t, vm)
  local key = pal_sel_key(vm, t._A[0])
  if key then Pal.toBackup(t._A[1], key) end
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:874
T.CopyPalUnfadedFromBackup = K.wrap(function(t, vm)
  local key = pal_sel_key(vm, t._A[0])
  if key then Pal.fromBackup(t._A[1], key) end
  Pal.flush()
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:892
T.CopyPalFadedToUnfaded = K.wrap(function(t, vm)
  local key = pal_sel_key(vm, t._A[0])
  if key then Pal.copyFadedToUnfaded(key) end
  Pal.flush()
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:910
T.IsContest = K.wrap(function(t, vm)
  if vm and vm.args then vm.args[7] = 0 end
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:926
T.IsTargetSameSide = K.wrap(function(t, vm)
  if vm and vm.args then
    vm.args[7] = (P.isOpponent(P.atk(vm)) == P.isOpponent(P.tgt(vm))) and 1 or 0
  end
  K.destroy(t)
end)

local function set_battlers(vm, atk, tgt)
  if not vm then return end
  if vm.setBattlers then
    vm:setBattlers(atk, tgt)
  else
    if atk then vm._attackerSide = atk end
    if tgt then vm._targetSide = tgt end
    vm.isReversed = (vm._attackerSide == "enemy")
  end
end

-- pokefirered/src/battle_anim_utility_funcs.c:919
T.SetAnimAttackerAndTargetForEffectTgt = K.wrap(function(t, vm)
  local atk = K.sideFromCtx(K.ctx(vm, "battlerTarget", nil))
  local tgt = K.sideFromCtx(K.ctx(vm, "effectBattler", nil))
  set_battlers(vm, atk, tgt)
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:935
T.SetAnimTargetToBattlerTarget = K.wrap(function(t, vm)
  local tgt = K.sideFromCtx(K.ctx(vm, "battlerTarget", nil))
  set_battlers(vm, nil, tgt)
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:941
T.SetAnimAttackerAndTargetForEffectAtk = K.wrap(function(t, vm)
  local atk = K.sideFromCtx(K.ctx(vm, "battlerAttacker", nil))
  local tgt = K.sideFromCtx(K.ctx(vm, "effectBattler", nil))
  set_battlers(vm, atk, tgt)
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:963
local function wait_restore_visibility(t, vm)
  if vm and vm.args and (tonumber(vm.args[7]) or 0) == 0x1000 then
    local p = P.present(t._side)
    if p then p.battlerInvisible = t._prevInvisible end
    K.destroy(t)
  end
end

-- pokefirered/src/battle_anim_utility_funcs.c:948
T.SetAttackerInvisibleWaitForSignal = K.wrap(function(t, vm)
  local side = P.atk(vm)
  local p = P.present(side)
  t._side = side
  t._prevInvisible = p and p.battlerInvisible or false
  if p then p.battlerInvisible = true end
  t._uncounted = true
  t._fn = wait_restore_visibility
end)

-- pokefirered/src/battle_anim_mons.c:1865
T.GetFrustrationPowerLevel = K.wrap(function(t, vm)
  local f = tonumber(K.ctx(vm, "friendship", nil))
  if f == nil then
    local st = K.battleState()
    local b = st and st[P.atk(vm)]
    f = b and b.mon and tonumber(b.mon.friendship) or 0
  end
  local lvl
  if f <= 30 then lvl = 0 elseif f <= 100 then lvl = 1 elseif f <= 200 then lvl = 2 else lvl = 3 end
  if vm and vm.args then vm.args[7] = lvl end
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_effects_1.c:2510
T.SporeDoubleBattle = K.wrap(function(t, vm)
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_effects_1.c:3545
local function leaf_blade_pos_factor(s)
  if s.data[4] < s.y then return -8 end
  return 8
end

-- pokefirered/src/battle_anim_effects_1.c:3581
local function leaf_blade_trail_cb(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] > 1 then
    d[0] = 0
    s.visible = not s.visible
    d[1] = d[1] + 1
    if d[1] > 8 then
      local owner = s._owner
      if owner and owner.active and owner._g1LeafBlade == s._ownerToken then
        owner.data[12] = owner.data[12] - 1
      end
      S.destroy(s)
    end
  end
end

-- pokefirered/src/battle_anim_effects_1.c:3555
local function leaf_blade_trail(t)
  local d = t.data
  d[14] = d[14] + 1
  if d[14] > 0 then
    d[14] = 0
    local main = t._spr
    local x = main.x + main.ox
    local y = main.y + main.oy
    local sp = S.create(t._vm, "gLeafBladeSpriteTemplate", x, y, d[4], leaf_blade_trail_cb)
    if sp then
      sp._owner = t
      sp._ownerToken = t._g1LeafBlade
      d[12] = d[12] + 1
      sp.data[0] = band(d[13], 1)
      d[13] = d[13] + 1
      S.startAnim(sp, d[3])
      sp.subpriority = d[4]
      P.updateZ(sp)
    end
  end
end

local function leaf_blade_restart(t, sprite, dx, dy, subDelta, animNum)
  local d = t.data
  sprite.x = sprite.x + sprite.ox
  sprite.y = sprite.y + sprite.oy
  sprite.ox = 0
  sprite.oy = 0
  sprite.data[0] = 10
  sprite.data[1] = sprite.x
  sprite.data[2] = dx
  sprite.data[3] = sprite.y
  sprite.data[4] = dy
  sprite.data[5] = leaf_blade_pos_factor(sprite)
  d[4] = d[4] + subDelta
  d[3] = animNum
  sprite.subpriority = d[4]
  S.startAnim(sprite, d[3])
  S.initArc(sprite)
  d[0] = d[0] + 1
end

local ARC_NEXT = { [0] = 1, [2] = 3, [4] = 5, [6] = 7, [8] = 9, [10] = 11 }

-- pokefirered/src/battle_anim_effects_1.c:3359
local function leaf_blade_step(t)
  local d = t.data
  local sprite = t._spr
  if not sprite or not sprite.active or sprite._owner ~= t or sprite._ownerToken ~= t._g1LeafBlade then
    K.destroy(t)
    return
  end
  local a = d[0]
  local w2 = cdiv(d[10], 2) + 10
  local h2 = cdiv(d[11], 2) + 10
  if ARC_NEXT[a] then
    leaf_blade_trail(t)
    if S.translateHArc(sprite) then
      d[15] = ARC_NEXT[a]
      d[0] = 0xFF
    end
  elseif a == 1 then
    leaf_blade_restart(t, sprite, d[6], d[7], 2, 1)
  elseif a == 3 then
    leaf_blade_restart(t, sprite, d[6] - w2 * d[5], d[7] - h2 * d[5], 0, 2)
  elseif a == 5 then
    leaf_blade_restart(t, sprite, d[6] + w2 * d[5], d[7] + h2 * d[5], -2, 3)
  elseif a == 7 then
    leaf_blade_restart(t, sprite, d[6], d[7], 2, 4)
  elseif a == 9 then
    leaf_blade_restart(t, sprite, d[6] - w2 * d[5], d[7] + h2 * d[5], 0, 5)
  elseif a == 11 then
    leaf_blade_restart(t, sprite, d[8], d[9], -2, 6)
  elseif a == 12 then
    leaf_blade_trail(t)
    if S.translateHArc(sprite) then
      S.destroy(sprite)
      d[0] = d[0] + 1
    end
  elseif a == 13 then
    if d[12] == 0 then K.destroy(t) end
  elseif a == 0xFF then
    d[1] = d[1] + 1
    if d[1] > 5 then
      d[1] = 0
      d[0] = d[15]
    end
  end
end

local leafBladeSerial = 0

-- pokefirered/src/battle_anim_effects_1.c:3333
T.LeafBlade = K.wrap(function(t, vm)
  local d = t.data
  local tgt = P.tgt(vm)
  d[4] = P.subpriorityOf(tgt) - 1
  d[6] = P.coord(vm, tgt, P.X_2)
  d[7] = P.coord(vm, tgt, P.Y_PIC_OFFSET)
  d[10] = P.attr(vm, tgt, P.ATTR_WIDTH)
  d[11] = P.attr(vm, tgt, P.ATTR_HEIGHT)
  d[5] = P.isOpponent(tgt) and 1 or -1
  d[9] = 56 - d[5] * 64
  d[8] = d[7] - d[9] + d[6]
  local sprite = S.create(vm, "gLeafBladeSpriteTemplate", d[8], d[9], d[4], nil)
  if not sprite then return K.destroy(t) end
  leafBladeSerial = leafBladeSerial + 1
  t._g1LeafBlade = leafBladeSerial
  sprite._owner = t
  sprite._ownerToken = leafBladeSerial
  t._spr = sprite
  sprite.data[0] = 10
  sprite.data[1] = d[8]
  sprite.data[2] = d[6] - cdiv(d[10], 2) * d[5] - 10 * d[5]
  sprite.data[3] = d[9]
  sprite.data[4] = d[7] + (cdiv(d[11], 2) + 10) * d[5]
  sprite.data[5] = leaf_blade_pos_factor(sprite)
  S.initArc(sprite)
  t._fn = leaf_blade_step
end)

-- pokefirered/src/battle_anim_effects_1.c:2335
T.CreateSmallSolarBeamOrbs = K.wrap(function(t, vm)
  t._fn = function(tt, v)
    local d = tt.data
    d[0] = d[0] - 1
    if d[0] == -1 then
      d[1] = d[1] + 1
      d[0] = 6
      local args = { [0] = 15, [1] = 0, [2] = 80, [3] = 0 }
      if v and v.args then
        v.args[0], v.args[1], v.args[2], v.args[3] = 15, 0, 80, 0
      end
      local C = require("src.core.game3.battle.anim_port.g1_callbacks")
      S.createAndAnimate(v, "gSolarBeamSmallOrbSpriteTemplate", 0, 0, P.subpriorityOf(P.tgt(v)) + 1, S.inits[C.SolarBeamSmallOrb], args)
    end
    if d[1] == 15 then K.destroy(tt) end
  end
  t._fn(t, vm)
end)

T._F = F
local B0 = require("src.core.game3.battle.anim_port.g1_tasks_b")
B0(T, F)
for _, n in ipairs({ "SimplePaletteBlend", "ComplexPaletteBlend", "BowMon", "ShakeMonOrBattleTerrain",
  "SlideMonToOffset", "SlideMonToOriginalPos", "SlideMonToOffsetAndBack" }) do
  T["_noGfx_" .. n] = T[n]
end
T._noGfx_DoHorizontalLunge = T.HorizontalLunge
T._noGfx_DoVerticalDip = T.VerticalDip
return T
