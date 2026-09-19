
return function(K)
  local P, D, T = K.P, K.destroy, K.T
  local TK = {}

  local SE_M_THUNDERBOLT = 111
  local SE_M_HEADBUTT = 155
  local SE_M_DIG = 168

  local function play_se12(se, pan)
    local ok, Audio = pcall(require, "src.core.game3.audio")
    if ok and Audio and Audio.playSe then pcall(Audio.playSe, se, { pan = pan }) end
  end

  local function task_alive(s)
    local t = s._task
    return t and t.active and t._g4id == s._taskId
  end

  local function bind(s, t)
    s._task = t
    s._taskId = t._g4id
  end

  -- pokefirered/src/battle_anim_electric.c:736
  local function boltSegment(s)
    s.data[1] = s.data[1] + 1
    if s.data[1] == 15 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_electric.c:670
  local function electricBoltStep(t, vm)
    local d = t.data
    local r8, r2, r12
    local sp = P.u8(d[2])
    local x, y = d[0], d[1]
    if d[2] == 0 then
      r8, r2, r12 = 0, 1, 16
    else
      r12, r8, r2 = 16, 8, 4
    end
    local k = d[10]
    local create = false
    if k == 0 then
      create = true
    elseif k == 2 then
      r12 = r12 * 2
      r8 = r8 + r2
      create = true
    elseif k == 4 then
      r12 = r12 * 3
      r8 = r8 + r2 * 2
      create = true
    elseif k == 6 then
      r12 = r12 * 4
      r8 = r8 + r2 * 3
      create = true
    elseif k == 8 then
      r12 = r12 * 5
      create = true
    elseif k == 10 then
      D(t)
      return
    end
    if create then
      local w, h = 8, 16
      if sp ~= 0 then w, h = 16, 16 end
      local s = P.createSprite(vm, "SPARK", T.sElectricBoltSegmentSpriteTemplate, x, y + r12, 2, boltSegment, w, h)
      if s then
        P.addTile(s, r8)
        s.data[0] = sp
        s.callback(s)
      end
    end
    d[10] = d[10] + 1
  end

  -- pokefirered/src/battle_anim_electric.c:662
  TK.ElectricBolt = function(t, vm)
    t.data[0] = P.coord(vm, P.tgt(vm), P.X) + vm.args[0]
    t.data[1] = P.coord(vm, P.tgt(vm), P.Y) + vm.args[1]
    t.data[2] = vm.args[2]
    t.func = electricBoltStep
  end

  -- pokefirered/src/battle_anim_electric.c:239
  local CHARGE_OFFSETS = {
    [0] = { 58, -60 }, { -56, -36 }, { 8, -56 }, { -16, 56 }, { 58, -10 }, { -58, 10 }, { 48, -18 }, { -8, 56 },
    { 16, -56 }, { -58, -42 }, { 58, 30 }, { -48, 40 }, { 12, -48 }, { 48, -12 }, { -56, 18 }, { 48, 48 },
  }

  -- pokefirered/src/battle_anim_electric.c:849
  local function chargingParticleStep(s)
    if P.translateLinear(s) then
      if task_alive(s) then s._task.data[7] = s._task.data[7] - 1 end
      P.destroy(s)
    end
  end
  local function chargingParticle(s)
    P.startAnim(s, 1)
    s.callback = chargingParticleStep
  end

  -- pokefirered/src/battle_anim_electric.c:803
  local function chargingStep(t, vm)
    local d = t.data
    if d[6] ~= 0 then
      d[12] = d[12] + 1
      if d[12] > d[13] then
        d[12] = 0
        local s = P.createSprite(vm, "ELECTRIC_ORBS", T.gElectricChargingParticlesSpriteTemplate, d[14], d[15], 2, P.runStoredWhenAnimEnds, 8, 8)
        if s then
          local o = CHARGE_OFFSETS[d[9]]
          s.x = s.x + o[1]
          s.y = s.y + o[2]
          s.data[0] = 40 - d[8] * 5
          s.data[1] = s.x
          s.data[2] = d[14]
          s.data[3] = s.y
          s.data[4] = d[15]
          bind(s, t)
          P.initLinear(s)
          P.storeCb(s, chargingParticle)
          d[9] = d[9] + 1
          if d[9] > 15 then d[9] = 0 end
          d[10] = d[10] + 1
          if d[10] >= d[11] then
            d[10] = 0
            if d[8] <= 5 then d[8] = d[8] + 1 end
          end
          d[7] = d[7] + 1
          d[6] = d[6] - 1
        end
      end
    elseif d[7] == 0 then
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_electric.c:778
  TK.ElectricChargingParticles = function(t, vm)
    local a = vm.args
    local side = (a[0] == 0) and P.atk(vm) or P.tgt(vm)
    local d = t.data
    d[14] = P.coord(vm, side, P.X_2)
    d[15] = P.coord(vm, side, P.Y_PIC_OFFSET)
    d[6] = a[1]
    d[7], d[8], d[9], d[10] = 0, 0, 0, 0
    d[11] = a[3]
    d[12] = 0
    d[13] = a[2]
    t.func = chargingStep
  end

  -- pokefirered/src/battle_anim_electric.c:929
  TK.VoltTackleAttackerReappear = function(t, vm)
    local d = t.data
    local p = P.present(P.atk(vm))
    if not p then
      D(t)
      return
    end
    if d[0] == 0 then
      if P.atk(vm) == "player" then
        d[14] = -32
        d[13] = 2
      else
        d[14] = 32
        d[13] = -2
      end
      p.ox = d[14]
      d[0] = d[0] + 1
    elseif d[0] == 1 then
      d[1] = d[1] + 1
      if d[1] > 1 then
        d[1] = 0
        p.visible = not (p.visible ~= false)
        if d[14] ~= 0 then
          d[14] = d[14] + d[13]
          p.ox = d[14]
        else
          d[0] = d[0] + 1
        end
      end
    elseif d[0] == 2 then
      d[1] = d[1] + 1
      if d[1] > 1 then
        d[1] = 0
        p.visible = not (p.visible ~= false)
        d[2] = d[2] + 1
        if d[2] == 8 then d[0] = d[0] + 1 end
      end
    elseif d[0] == 3 then
      p.visible = true
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_electric.c:1080
  local function voltBoltSprite(s)
    s.data[0] = s.data[0] + 1
    if s.data[0] > 12 then
      if task_alive(s) then
        local k = s.data[7]
        s._task.data[k] = s._task.data[k] - 1
      end
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_electric.c:1057
  local function createVoltBolt(t, vm)
    local d = t.data
    local s = P.createSprite(vm, "SPARK", T.gVoltTackleBoltSpriteTemplate, d[3], d[5], 35, voltBoltSprite, 8, 16)
    if s then
      bind(s, t)
      s.data[6] = 0
      s.data[7] = 7
      d[7] = d[7] + 1
    end
    d[6] = d[6] + d[1]
    if d[6] < 0 then d[6] = 3 end
    if d[6] > 3 then d[6] = 0 end
    d[3] = d[3] + d[1] * 16
    return (d[1] == 1 and d[3] >= d[4]) or (d[1] == -1 and d[3] <= d[4])
  end

  -- pokefirered/src/battle_anim_electric.c:985
  TK.VoltTackleBolt = function(t, vm)
    local d = t.data
    if d[0] == 0 then
      d[1] = (P.atk(vm) == "player") and 1 or -1
      local a0 = vm.args[0]
      if a0 == 0 then
        d[3] = P.coord(vm, P.atk(vm), P.X_2)
        d[5] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
        d[4] = d[1] * 128 + 120
      elseif a0 == 4 then
        d[3] = 120 - d[1] * 128
        d[5] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
        d[4] = P.coord(vm, P.tgt(vm), P.X_2) - d[1] * 32
      else
        if P.band(a0, 1) ~= 0 then
          d[3], d[4] = 256, -16
        else
          d[3], d[4] = -16, 256
        end
        if d[1] == 1 then
          d[5] = 80 - a0 * 10
        else
          d[5] = a0 * 10 + 40
          d[3], d[4] = d[4], P.s16(P.u16(d[3]))
        end
      end
      if d[3] < d[4] then
        d[1] = 1
        d[6] = 0
      else
        d[1] = -1
        d[6] = 3
      end
      d[0] = d[0] + 1
    elseif d[0] == 1 then
      d[2] = d[2] + 1
      if d[2] > 0 then
        d[2] = 0
        if createVoltBolt(t, vm) or createVoltBolt(t, vm) then d[0] = d[0] + 1 end
      end
    elseif d[0] == 2 then
      if d[7] == 0 then D(t) end
    end
  end

  -- pokefirered/src/battle_anim_electric.c:1217
  local function progressingBoltSprite(s)
    s.data[0] = s.data[0] + 1
    if s.data[0] > 12 then
      if task_alive(s) then
        local k = s.data[7]
        s._task.data[k] = s._task.data[k] - 1
      end
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_electric.c:1182
  local function createShockWaveBolt(t, vm)
    local d = t.data
    local s = P.createSprite(vm, "SPARK", T.sShockWaveProgressingBoltSpriteTemplate, d[6], d[7], 35, progressingBoltSprite, 8, 8)
    if s then
      P.addTile(s, d[4])
      d[4] = d[4] + d[5]
      if d[4] < 0 then d[4] = 7 end
      if d[4] > 7 then d[4] = 0 end
      bind(s, t)
      s.data[7] = 3
      d[3] = d[3] + 1
    end
    if d[4] == 0 and d[5] > 0 then
      d[14] = d[14] + d[15]
      play_se12(SE_M_THUNDERBOLT, d[14])
    end
    if (d[5] < 0 and d[7] <= d[8]) or (d[5] > 0 and d[7] >= d[8]) then
      d[2] = d[2] + 1
      d[6] = d[6] + d[9]
      return true
    end
    d[7] = d[7] + d[5] * 8
    return false
  end

  -- pokefirered/src/battle_anim_electric.c:1107
  TK.ShockWaveProgressingBolt = function(t, vm)
    local d = t.data
    local st = d[0]
    if st == 0 then
      d[6] = P.coord(vm, P.atk(vm), P.X_2)
      d[7] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
      d[8] = 4
      d[10] = P.coord(vm, P.tgt(vm), P.X_2)
      d[9] = P.cdiv(d[10] - d[6], 5)
      d[4] = 7
      d[5] = -1
      d[11] = 12
      d[12] = vm:adjustPanning(P.SOUND_PAN_ATTACKER)
      d[13] = vm:adjustPanning(P.SOUND_PAN_TARGET)
      d[14] = d[12]
      d[15] = P.cdiv(d[13] - d[12], 3)
      d[0] = d[0] + 1
    elseif st == 1 then
      d[1] = d[1] + 1
      if d[1] > 0 then
        d[1] = 0
        if createShockWaveBolt(t, vm) then
          if d[2] == 5 then d[0] = 3 else d[0] = d[0] + 1 end
        end
      end
      if d[11] ~= 0 then d[11] = d[11] - 1 end
    elseif st == 2 then
      if d[11] ~= 0 then d[11] = d[11] - 1 end
      d[1] = d[1] + 1
      if d[1] > 4 then
        d[1] = 0
        if P.band(d[2], 1) ~= 0 then
          d[7], d[8], d[4], d[5] = 4, 68, 0, 1
        else
          d[7], d[8], d[4], d[5] = 68, 4, 7, -1
        end
        if d[11] ~= 0 then d[0] = 4 else d[0] = 1 end
      end
    elseif st == 3 then
      if d[3] == 0 then D(t) end
    elseif st == 4 then
      if d[11] ~= 0 then d[11] = d[11] - 1 else d[0] = 1 end
    end
  end

  -- pokefirered/src/battle_anim_electric.c:1273
  local function shockLightningSprite(s)
    if s.animEnded then
      if task_alive(s) then
        local k = s.data[7]
        s._task.data[k] = s._task.data[k] - 1
      end
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_electric.c:1226
  TK.ShockWaveLightning = function(t, vm)
    local d = t.data
    if d[0] == 0 then
      d[15] = P.coord(vm, P.tgt(vm), P.Y) + 32
      d[14] = d[15]
      while d[14] > 16 do d[14] = d[14] - 32 end
      d[13] = P.coord(vm, P.tgt(vm), P.X_2)
      d[12] = P.subpriorityOf(P.tgt(vm)) - 2
      d[0] = d[0] + 1
    elseif d[0] == 1 then
      d[1] = d[1] + 1
      if d[1] > 1 then
        d[1] = 0
        local s = P.createSprite(vm, "LIGHTNING", T.gLightningSpriteTemplate, d[13], d[14], d[12], shockLightningSprite, 32, 32)
        if s then
          bind(s, t)
          s.data[7] = 10
          d[10] = d[10] + 1
        end
        if d[14] >= d[15] then
          d[0] = d[0] + 1
        else
          d[14] = d[14] + 32
        end
      end
    elseif d[0] == 2 then
      if d[10] == 0 then D(t) end
    end
  end

  -- pokefirered/src/battle_anim_ground.c:599
  local function shakeTerrain(t, vm)
    local d = t.data
    if d[0] == 0 then
      d[1] = d[1] + 1
      if d[1] > 1 then
        d[1] = 0
        if P.band(d[2], 1) == 0 then vm.bg3.x = d[13] + d[15] else vm.bg3.x = d[13] - d[15] end
        d[2] = d[2] + 1
        if d[2] == d[3] then
          d[2] = 0
          d[14] = d[14] - 1
          d[0] = d[0] + 1
        end
      end
    elseif d[0] == 1 then
      d[1] = d[1] + 1
      if d[1] > 1 then
        d[1] = 0
        if P.band(d[2], 1) == 0 then vm.bg3.x = d[13] + d[14] else vm.bg3.x = d[13] - d[14] end
        d[2] = d[2] + 1
        if d[2] == 4 then
          d[2] = 0
          d[14] = d[14] - 1
          if d[14] == 0 then d[0] = d[0] + 1 end
        end
      end
    elseif d[0] == 2 then
      vm.bg3.x = d[13]
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_ground.c:688
  local function setShakeX(t)
    local d = t.data
    local x
    if P.band(d[2], 1) == 0 then
      x = P.cdiv(d[14], 2) + P.band(d[14], 1)
    else
      x = -P.cdiv(d[14], 2)
    end
    for _, p in ipairs(t._mons) do p.ox = x end
  end

  local function shakeBattlers(t, vm)
    local d = t.data
    if d[0] == 0 or d[0] == 1 then
      d[1] = d[1] + 1
      if d[1] > 1 then
        d[1] = 0
        setShakeX(t)
        d[2] = d[2] + 1
        if d[0] == 0 and d[2] == d[3] then
          d[2] = 0
          d[14] = d[14] - 1
          d[0] = d[0] + 1
        elseif d[0] == 1 and d[2] == 4 then
          d[2] = 0
          d[14] = d[14] - 1
          if d[14] == 0 then d[0] = d[0] + 1 end
        end
      end
    elseif d[0] == 2 then
      for _, p in ipairs(t._mons) do p.ox = 0 end
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_ground.c:555
  TK.HorizontalShake = function(t, vm)
    local a = vm.args
    local d = t.data
    if a[1] ~= 0 then
      d[14] = a[1] + 3
    else
      d[14] = P.cdiv(tonumber((vm.ctx or {}).movePower) or 0, 10) + 3
    end
    d[15] = d[14]
    d[3] = a[2]
    if a[0] == 5 then
      d[13] = vm.bg3.x
      t.func = shakeTerrain
    elseif a[0] == 4 then
      t._mons = {}
      local AnimCoords = require("src.core.game3.battle.anim_coords")
      for _, id in ipairs(AnimCoords.ids()) do
        local p = (id < 2 or AnimCoords.spritePresent(nil, id)) and P.present(id) or nil
        if p and p.visible ~= false then t._mons[#t._mons + 1] = p end
      end
      t.func = shakeBattlers
    else
      local side = P.battlerSide(vm, a[0])
      local p = side and P.present(side)
      if not p then
        D(t)
      else
        t._mons = { p }
        t.func = shakeBattlers
      end
    end
  end

  -- pokefirered/src/battle_anim_ground.c:713
  TK.IsPowerOver99 = function(t, vm)
    vm.args[15] = ((tonumber((vm.ctx or {}).movePower) or 0) > 99) and 1 or 0
    D(t)
  end

  -- pokefirered/src/battle_anim_ground.c:735
  local function waitFissure(t, vm)
    if vm.args[7] == t.data[3] then
      vm.bg3.x, vm.bg3.y = 0, 0
      D(t)
    else
      vm.bg3.x, vm.bg3.y = t.data[1], t.data[2]
    end
  end

  -- pokefirered/src/battle_anim_ground.c:719
  TK.PositionFissureBgOnBattler = function(t, vm)
    local a = vm.args
    local side = (P.band(a[0], 1) ~= 0) and P.tgt(vm) or P.atk(vm)
    local nt = K.spawnAux(vm, waitFissure, a[1])
    if nt then
      nt.data[1] = P.band(32 - P.coord(vm, side, P.X_2), 0x1FF)
      nt.data[2] = P.band(64 - P.coord(vm, side, P.Y_PIC_OFFSET), 0xFF)
      vm.bg3.x = nt.data[1]
      vm.bg3.y = nt.data[2]
      nt.data[3] = a[2]
    end
    D(t)
  end

  -- pokefirered/src/battle_anim_ice.c:1468
  TK.GetRolloutCounter = function(t, vm)
    local ctx = vm.ctx or {}
    local arg = P.u8(vm.args[0])
    vm.args[arg] = P.u8((ctx.rolloutTimerStartValue or 0) - (ctx.rolloutTimer or 0) - 1)
    D(t)
  end

  -- pokefirered/src/battle_anim_ice.c:334
  local HAZE_BLEND = { [0] = 0, 1, 2, 2, 2, 2, 3, 4, 4, 4, 5, 6, 6, 6, 6, 7, 8, 8, 8, 9 }
  local MIST_BLEND = { [0] = 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 5 }

  local function fog_end(t, vm)
    vm._fogBg = nil
    vm.bldAlpha = nil
    t.draw = nil
    D(t)
  end

  -- pokefirered/src/battle_anim_ice.c:947
  local function fog_begin(t, vm)
    local AnimPal = require("src.core.game3.battle.anim_pal")
    vm._fogBg = { x = 0, y = 0, eva = 0, evb = 16 }
    AnimPal.bgLoad("bg1", "FOG")
    t.z = 850
    t.draw = function(_, v)
      local f = (v or vm)._fogBg
      if f and (f.eva or 0) > 0 then
        AnimPal.drawBg("FOG", "bg1", f.x, f.y, { eva = f.eva, evb = f.evb })
      end
    end
  end

  -- pokefirered/src/battle_anim_ice.c:955
  local function hazeStep(t, vm)
    local d = t.data
    local f = vm._fogBg
    if f then f.x = f.x - 1 end
    if d[12] == 0 then
      d[10] = d[10] + 1
      if d[10] == 4 then
        d[10] = 0
        d[9] = d[9] + 1
        d[11] = HAZE_BLEND[d[9]] or 9
        if f then f.eva, f.evb = d[11], 16 - d[11] end
        if d[11] == 9 then
          d[12] = d[12] + 1
          d[11] = 0
        end
      end
    elseif d[12] == 1 then
      d[11] = d[11] + 1
      if d[11] == 0x51 then
        d[11] = 9
        d[12] = d[12] + 1
      end
    elseif d[12] == 2 then
      d[10] = d[10] + 1
      if d[10] == 4 then
        d[10] = 0
        d[11] = d[11] - 1
        if f then f.eva, f.evb = d[11], 16 - d[11] end
        if d[11] == 0 then
          d[12] = d[12] + 1
          d[11] = 0
        end
      end
    else
      fog_end(t, vm)
    end
  end

  -- pokefirered/src/battle_anim_ice.c:932
  TK.HazeScrollingFog = function(t, vm)
    fog_begin(t, vm)
    t.func = hazeStep
  end

  -- pokefirered/src/battle_anim_ice.c:1053
  local function mistBallStep(t, vm)
    local d = t.data
    local f = vm._fogBg
    if f then f.x = f.x + d[15] end
    if d[12] == 0 then
      d[9] = d[9] + 1
      d[11] = MIST_BLEND[d[9]] or 5
      if f then f.eva, f.evb = d[11], 17 - d[11] end
      if d[11] == 5 then
        d[12] = d[12] + 1
        d[11] = 0
      end
    elseif d[12] == 1 then
      d[11] = d[11] + 1
      if d[11] == 0x51 then
        d[11] = 5
        d[12] = d[12] + 1
      end
    elseif d[12] == 2 then
      d[10] = d[10] + 1
      if d[10] == 4 then
        d[10] = 0
        d[11] = d[11] - 1
        if f then f.eva, f.evb = d[11], 16 - d[11] end
        if d[11] == 0 then
          d[12] = d[12] + 1
          d[11] = 0
        end
      end
    else
      fog_end(t, vm)
    end
  end

  -- pokefirered/src/battle_anim_ice.c:1029
  TK.MistBallFog = function(t, vm)
    fog_begin(t, vm)
    t.data[15] = -1
    t.func = mistBallStep
  end

  -- pokefirered/src/battle_anim_ice.c:366
  local HAIL_COORDS = {
    [0] = { 100, 120, "player", 2 }, { 85, 120, "player", 0 }, { 242, 120, "enemy", 1 },
    { 66, 120, "player_right", 1 }, { 182, 120, "enemy_right", 0 }, { 60, 120, "player", 2 },
    { 214, 120, "enemy", 0 }, { 113, 120, "player", 1 }, { 210, 120, "enemy_right", 1 },
    { 38, 120, "player_right", 0 },
  }

  -- pokefirered/src/battle_anim_ice.c:1391
  local function hailContinue(s)
    s.data[0] = s.data[0] + 1
    if s.data[0] == 20 then
      if task_alive(s) then
        local k = s.data[7]
        s._task.data[k] = s._task.data[k] - 1
      end
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_ice.c:1362
  local function hailBegin(s)
    s.x = s.x + 4
    s.y = s.y + 8
    if s.x < s.data[3] and s.y < s.data[4] then return end
    if s.data[0] == 1 and s.data[5] == 0 then
      local vm = s._vm
      local h = P.createSprite(vm, "ICE_CRYSTALS", T.gIceCrystalHitLargeSpriteTemplate, s.data[3], s.data[4], s.subpriority, hailContinue, 8, 16)
      if h then
        h._task, h._taskId = s._task, s._taskId
        h.data[6] = s.data[6]
        h.data[7] = s.data[7]
      end
      P.destroy(s)
    else
      if task_alive(s) then
        local k = s.data[7]
        s._task.data[k] = s._task.data[k] - 1
      end
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_ice.c:1304
  local function generateHail(t, vm, id, affNum, c)
    local e = HAIL_COORDS[id]
    local bx, by = e[1], e[2]
    local possible = 0
    if e[4] ~= 2 and (e[3] == "player" or e[3] == "enemy") then
      local p = P.present(e[3])
      if p and p.visible ~= false then
        possible = 1
        bx = P.coord(vm, e[3], P.X_2)
        by = P.coord(vm, e[3], P.Y_PIC_OFFSET)
        local w, h = K.monSize(vm, e[3])
        if e[4] == 0 then
          bx = bx - P.cdiv(w, 6)
          by = by - P.cdiv(h, 6)
        elseif e[4] == 1 then
          bx = bx + P.cdiv(w, 6)
          by = by + P.cdiv(h, 6)
        end
      end
    end
    local sx = bx - P.cdiv(by + 8, 2)
    local s = P.createSprite(vm, "HAIL", T.sHailParticleSpriteTemplate, sx, -8, 18, hailBegin, 16, 16)
    if not s then return false end
    P.startAffineAnim(s, affNum)
    s.data[0] = possible
    s.data[3] = bx
    s.data[4] = by
    s.data[5] = affNum
    bind(s, t)
    s.data[7] = c
    return true
  end

  -- pokefirered/src/battle_anim_ice.c:1260
  local function hailStep(t, vm)
    local d = t.data
    if d[0] == 0 then
      d[4] = d[4] + 1
      if d[4] > 2 then
        d[4], d[5], d[2] = 0, 0, 0
        d[0] = d[0] + 1
      end
    elseif d[0] == 1 then
      if d[5] == 0 then
        if generateHail(t, vm, d[3], d[2], 1) then d[1] = d[1] + 1 end
        d[2] = d[2] + 1
        if d[2] == 3 then
          d[3] = d[3] + 1
          if d[3] == 10 then d[0] = d[0] + 1 else d[0] = d[0] - 1 end
        else
          d[5] = 1
        end
      else
        d[5] = d[5] - 1
      end
    elseif d[0] == 2 then
      if d[1] == 0 then D(t) end
    end
  end

  -- pokefirered/src/battle_anim_ice.c:1253
  TK.Hail = function(t, vm)
    t.func = hailStep
  end

  -- pokefirered/src/battle_anim_rock.c:705
  local function rollout_counter(vm)
    local ctx = vm.ctx or {}
    local ret = P.u8((ctx.rolloutTimerStartValue or 0) - (ctx.rolloutTimer or 0))
    if P.u8(ret - 1) > 4 then ret = 1 end
    return ret
  end

  -- pokefirered/src/battle_anim_rock.c:647
  local function createRolloutDirt(t, vm)
    local d = t.data
    local tpl, tag, w, h, tileOffset
    local c = d[1]
    if c == 1 then
      tpl, tag, w, h, tileOffset = T.gRolloutMudSpriteTemplate, "MUD_SAND", 8, 8, 0
    elseif c == 2 or c == 3 then
      tpl, tag, w, h, tileOffset = T.gRolloutRockSpriteTemplate, "ROCKS", 32, 32, 80
    elseif c == 4 then
      tpl, tag, w, h, tileOffset = T.gRolloutRockSpriteTemplate, "ROCKS", 32, 32, 64
    elseif c == 5 then
      tpl, tag, w, h, tileOffset = T.gRolloutRockSpriteTemplate, "ROCKS", 32, 32, 48
    else
      return
    end
    local x = P.u16(P.asr(d[2], 3))
    local y = P.u16(P.asr(d[3], 3))
    x = P.u16(x + d[12] * 4)
    local C = K.cb()
    local s = P.createSprite(vm, tag, tpl, x, y, 35, C and C.rolloutParticle or P.destroy, w, h)
    if s then
      s.data[0] = 18
      s.data[2] = d[12] * 20 + x + d[1] * 3
      s.data[4] = y
      s.data[5] = -16 - d[1] * 2
      P.addTile(s, tileOffset)
      P.initArc(s)
      bind(s, t)
      d[11] = d[11] + 1
    end
    d[12] = -d[12]
  end

  -- pokefirered/src/battle_anim_rock.c:587
  local function rolloutStep(t, vm)
    local d = t.data
    local p = t._mon
    local st = d[0]
    if st == 0 then
      d[6] = P.s16(d[6] - d[4])
      d[7] = P.s16(d[7] - d[5])
      if p then
        p.ox = P.asr(d[6], 3)
        p.oy = P.asr(d[7], 3)
      end
      d[9] = d[9] + 1
      if d[9] == 10 then
        d[11] = 20
        d[0] = d[0] + 1
      end
      play_se12(SE_M_HEADBUTT, d[13])
    elseif st == 1 then
      d[11] = d[11] - 1
      if d[11] == 0 then d[0] = d[0] + 1 end
    elseif st == 2 then
      d[9] = d[9] - 1
      if d[9] ~= 0 then
        d[6] = P.s16(d[6] + d[4])
        d[7] = P.s16(d[7] + d[5])
      else
        d[6], d[7] = 0, 0
        d[0] = d[0] + 1
      end
      if p then
        p.ox = P.asr(d[6], 3)
        p.oy = P.asr(d[7], 3)
      end
    elseif st == 3 then
      d[2] = P.s16(d[2] + d[4])
      d[3] = P.s16(d[3] + d[5])
      d[9] = d[9] + 1
      if d[9] >= d[10] then
        d[9] = 0
        createRolloutDirt(t, vm)
        d[13] = d[13] + d[14]
        play_se12(SE_M_DIG, d[13])
      end
      d[8] = d[8] - 1
      if d[8] == 0 then d[0] = d[0] + 1 end
    elseif st == 4 then
      if d[11] == 0 then D(t) end
    end
  end

  -- pokefirered/src/battle_anim_rock.c:544
  TK.Rollout = function(t, vm)
    local d = t.data
    t._g4rollout = true
    local v0 = P.coord(vm, P.atk(vm), P.X_2)
    local v1 = P.coord(vm, P.atk(vm), P.Y) + 24
    local v2 = P.coord(vm, P.tgt(vm), P.X_2)
    local v3 = P.coord(vm, P.tgt(vm), P.Y) + 24
    local rc = rollout_counter(vm)
    if rc == 1 then d[8] = 32 else d[8] = 48 - rc * 8 end
    d[0], d[11], d[9], d[12] = 0, 0, 0, 1
    local v5 = d[8]
    if v5 < 0 then v5 = v5 + 7 end
    d[10] = P.asr(v5, 3) - 1
    d[2] = v0 * 8
    d[3] = v1 * 8
    d[4] = P.cdiv((v2 - v0) * 8, d[8])
    d[5] = P.cdiv((v3 - v1) * 8, d[8])
    d[6], d[7] = 0, 0
    local pan1 = vm:adjustPanning(P.SOUND_PAN_ATTACKER)
    local pan2 = vm:adjustPanning(P.SOUND_PAN_TARGET)
    d[13] = pan1
    d[14] = P.cdiv(pan2 - pan1, d[8])
    d[1] = rc
    t._mon = P.present(P.atk(vm))
    t.func = rolloutStep
  end

  -- pokefirered/src/battle_anim_rock.c:777
  TK.GetSeismicTossDamageLevel = function(t, vm)
    local dmg = tonumber((vm.ctx or {}).moveDamage) or 0
    if dmg < 33 then vm.args[P.ARG_RET_ID] = 0 end
    if dmg >= 33 and dmg - 33 < 33 then vm.args[P.ARG_RET_ID] = 1 end
    if dmg > 65 then vm.args[P.ARG_RET_ID] = 2 end
    D(t)
  end

  -- pokefirered/src/battle_anim_rock.c:788
  TK.MoveSeismicTossBg = function(t, vm)
    local d = t.data
    if d[0] == 0 then d[1] = 200 end
    vm.bg3.y = P.s16(vm.bg3.y + P.cdiv(d[1], 10))
    d[1] = d[1] - 3
    if d[0] == 120 then
      D(t)
      return
    end
    d[0] = d[0] + 1
  end

  -- pokefirered/src/battle_anim_rock.c:805
  TK.SeismicTossBgAccelerateDownAtEnd = function(t, vm)
    local d = t.data
    if d[0] == 0 then
      d[0] = d[0] + 1
      d[2] = vm.bg3.y
    end
    d[1] = P.band(d[1] + 80, 0xFF)
    vm.bg3.y = d[2] + P.Cos(4, d[1])
    if vm.args[7] == 0xFFF then
      vm.bg3.y = 0
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_water.c:475
  TK.CreateRaindrops = function(t, vm)
    local d = t.data
    if d[0] == 0 then
      d[1] = vm.args[0]
      d[2] = vm.args[1]
      d[3] = vm.args[2]
    end
    d[0] = d[0] + 1
    if d[2] ~= 0 and d[0] % d[2] == 1 then
      local x = P.Random() % 240
      local y = P.Random() % 80
      local C = K.cb()
      P.createSprite(vm, "RAIN_DROPS", T.gRainDropSpriteTemplate, x, y, 4, C and C.rainDrop or P.destroy, 16, 32)
    end
    if d[0] == d[3] then D(t) end
  end

  -- pokefirered/src/battle_anim_water.c:626
  local function rotateAuroraStep(t, vm)
    local d = t.data
    d[10] = d[10] + 1
    if d[10] == 3 then
      d[10] = 0
      local f = require("src.core.game3.battle.anim_pal").writeFaded("RAINBOW_RINGS")
      if f then
        local saved = f[1]
        for i = 1, 7 do f[i] = f[i + 1] end
        f[8] = saved
      end
    end
    d[11] = d[11] + 1
    if d[11] == d[0] then D(t) end
  end

  -- pokefirered/src/battle_anim_water.c:620
  TK.RotateAuroraRingColors = function(t, vm)
    t.data[0] = vm.args[0]
    t.func = rotateAuroraStep
  end

  -- pokefirered/src/battle_anim_water.c:696
  local function runSinTimer(t, vm)
    vm.args[7] = P.band((vm.args[7] or 0) + 3, 0xFF)
    t.data[0] = (t.data[0] or 0) - 1
    if t.data[0] <= 0 then D(t) end
  end

  -- pokefirered/src/battle_anim_mons.c:1831
  local function setSquash(t, xs, ys, xe, ye, dur)
    local d = t.data
    d[8] = dur
    d[9], d[10] = xs, ys
    d[13], d[14] = xe, ye
    d[11] = P.cdiv(xe - xs, dur)
    d[12] = P.cdiv(ye - ys, dur)
  end

  -- pokefirered/src/battle_anim_mons.c:1843
  local function runSquash(t, vm)
    local d = t.data
    if d[8] == 0 then return 0 end
    d[8] = d[8] - 1
    if d[8] ~= 0 then
      d[9] = d[9] + d[11]
      d[10] = d[10] + d[12]
    else
      d[9], d[10] = d[13], d[14]
    end
    local p = t._mon
    P.setMonRotScale(p, d[9], d[10], 0)
    if d[8] ~= 0 then
      P.monYOffsetFromYScale(p, t._monSide, vm)
    elseif p then
      p.oy = 0
    end
    if p then p.oy = (p.oy or 0) + (p._g4y or 0) end
    return d[8]
  end

  -- pokefirered/src/battle_anim_water.c:1138
  local function waterSpoutPower(vm)
    local ctx = vm.ctx or {}
    local hp, maxhp = tonumber(ctx.attackerHp), tonumber(ctx.attackerMaxHp)
    if not hp or not maxhp then return 3 end
    maxhp = math.floor(maxhp / 4)
    for i = 0, 2 do
      if hp < maxhp * (i + 1) then return i end
    end
    return 3
  end

  -- pokefirered/src/battle_anim_water.c:1203
  local function smallWaterOrb(s)
    if s.data[0] == 0 then
      s.data[4] = s.data[4] + (s.data[1] % 6) * 3
      s.data[5] = s.data[5] + (s.data[1] % 3) * 3
      s.data[0] = s.data[0] + 1
    end
    s.data[2] = P.s16(s.data[2] + s.data[4])
    s.data[3] = P.s16(s.data[3] + s.data[5])
    s.x = P.asr(s.data[2], 4)
    s.y = P.asr(s.data[3], 4)
    if s.x < -8 or s.x > 248 or s.y < -8 or s.y > 120 then
      if task_alive(s) then
        local k = s.data[7]
        s._task.data[k] = s._task.data[k] - 1
      end
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_water.c:1170
  local function spoutLaunchDroplets(t, vm)
    local d = t.data
    local ax = P.coord(vm, P.atk(vm), P.X_2)
    local ay = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
    local trig = 172
    local sub = P.subpriorityOf(P.atk(vm)) - 1
    local inc = 4 - d[1]
    if inc <= 0 then inc = 1 end
    local i = 0
    while i < 20 do
      local s = P.createSprite(vm, "GLOWY_BLUE_ORB", T.gSmallWaterOrbSpriteTemplate, ax, ay, sub, smallWaterOrb, 8, 8)
      if s then
        s.data[1] = i
        s.data[2] = ax * 16
        s.data[3] = ay * 16
        s.data[4] = P.Cos(trig, 64)
        s.data[5] = P.Sin(trig, 64)
        bind(s, t)
        s.data[7] = 2
        if P.band(d[2], 1) ~= 0 then smallWaterOrb(s) end
        d[2] = d[2] + 1
      end
      trig = P.band(trig + inc * 2, 0xFF)
      i = i + inc
    end
  end

  -- pokefirered/src/battle_anim_water.c:1051
  local function spoutLaunchStep(t, vm)
    local d = t.data
    local p = t._mon
    local st = d[0]
    if st == 0 or st == 1 then
      if st == 0 then
        setSquash(t, 0x100, 0x100, 224, 0x200, 32)
        d[0] = d[0] + 1
      end
      d[3] = d[3] + 1
      if d[3] > 1 then
        d[3] = 0
        d[4] = d[4] + 1
        if P.band(d[4], 1) ~= 0 then
          if p then p.ox = 3; p._g4y = (p._g4y or 0) + 1 end
        elseif p then
          p.ox = -3
        end
      end
      if runSquash(t, vm) == 0 then
        P.monYOffsetFromYScale(p, t._monSide, vm)
        if p then
          p.oy = (p.oy or 0) + (p._g4y or 0)
          p.ox = 0
        end
        d[3], d[4] = 0, 0
        d[0] = d[0] + 1
      end
    elseif st == 2 then
      d[3] = d[3] + 1
      if d[3] > 4 then
        setSquash(t, 224, 0x200, 384, 224, 8)
        d[3] = 0
        d[0] = d[0] + 1
      end
    elseif st == 3 then
      if runSquash(t, vm) == 0 then
        d[3], d[4] = 0, 0
        d[0] = d[0] + 1
      end
    elseif st == 4 or st == 5 then
      if st == 4 then
        spoutLaunchDroplets(t, vm)
        d[0] = d[0] + 1
      end
      d[3] = d[3] + 1
      if d[3] > 1 then
        d[3] = 0
        d[4] = d[4] + 1
        if p then
          if P.band(d[4], 1) ~= 0 then p.oy = (p.oy or 0) + 2 else p.oy = (p.oy or 0) - 2 end
        end
        if d[4] == 10 then
          setSquash(t, 384, 224, 0x100, 0x100, 8)
          d[3], d[4] = 0, 0
          d[0] = d[0] + 1
        end
      end
    elseif st == 6 then
      if p then p._g4y = (p._g4y or 0) - 1 end
      if runSquash(t, vm) == 0 then
        P.resetMonRotScale(p)
        if p then
          p._g4y = nil
          p.oy = 0
        end
        d[4] = 0
        d[0] = d[0] + 1
      end
    elseif st == 7 then
      if d[2] == 0 then D(t) end
    end
  end

  -- pokefirered/src/battle_anim_water.c:1040
  TK.WaterSpoutLaunch = function(t, vm)
    t._monSide = P.atk(vm)
    t._mon = P.present(t._monSide)
    t.data[1] = waterSpoutPower(vm)
    if t._mon then t._mon.visible = true end
    t.func = spoutLaunchStep
  end

  -- pokefirered/src/battle_anim_water.c:1328
  local function spoutRainHit(s)
    s.data[1] = s.data[1] + 1
    if s.data[1] > 1 then
      s.data[1] = 0
      P.setInvisible(s, not P.isInvisible(s))
      s.data[2] = s.data[2] + 1
      if s.data[2] == 12 then
        if task_alive(s) then
          local k = s.data[7]
          s._task.data[k] = s._task.data[k] - 1
        end
        P.destroy(s)
      end
    end
  end

  -- pokefirered/src/battle_anim_water.c:1307
  local function spoutRain(s)
    if s.data[0] == 0 then
      s.y = s.y + 8
      if s.y >= s.data[5] then
        if task_alive(s) then s._task.data[10] = 1 end
        local h = P.createSprite(s._vm, "WATER_IMPACT", T.gWaterHitSplatSpriteTemplate, s.x, s.y, 1, spoutRainHit, 32, 32)
        if h then
          P.startAffineAnim(h, 3)
          h._task, h._taskId = s._task, s._taskId
          h.data[6] = s.data[6]
          h.data[7] = s.data[7]
        end
        P.destroy(s)
      end
    end
  end

  -- pokefirered/src/battle_anim_water.c:1289
  local function spoutRainDroplet(t, vm)
    local d = t.data
    local yPos = P.u16(P.asr(P.gSine(d[8]) + 3, 4) + d[6])
    local s = P.createSprite(vm, "GLOWY_BLUE_ORB", T.gSmallWaterOrbSpriteTemplate, d[7], 0, 0, spoutRain, 8, 8)
    if s then
      s.data[5] = yPos
      bind(s, t)
      s.data[7] = 9
      d[9] = d[9] + 1
    end
    d[11] = d[11] + 1
    d[8] = P.band(d[8] + 39, 0xFF)
    local r = P.u16(P.band(1103515245 * P.u16(d[7]) + 12345, 0xFFFFFFFF))
    if d[5] ~= 0 then d[7] = P.s16((r % d[5]) + d[4]) end
  end

  -- pokefirered/src/battle_anim_water.c:1246
  local function spoutRainStep(t, vm)
    local d = t.data
    if d[0] == 0 then
      d[2] = d[2] + 1
      if d[2] > 2 then
        d[2] = 0
        spoutRainDroplet(t, vm)
      end
      if d[10] ~= 0 and d[13] == 0 then
        for _, who in ipairs({ P.ANIM_TARGET, P.ANIM_DEF_PARTNER }) do
          vm.args[0], vm.args[1], vm.args[2] = who, 0, 12
          local nt = K.host.spawn("HorizontalShake", 80, {}, vm)
          if nt then
            nt._g4kind = "visual"
            nt.func(nt, vm)
          end
        end
        d[13] = 1
      end
      if d[11] >= d[12] then d[0] = d[0] + 1 end
    elseif d[0] == 1 then
      if d[9] == 0 then D(t) end
    end
  end

  -- pokefirered/src/battle_anim_water.c:1225
  TK.WaterSpoutRain = function(t, vm)
    local d = t.data
    d[1] = waterSpoutPower(vm)
    if P.atk(vm) == "player" then
      d[4], d[6] = 136, 40
    else
      d[4], d[6] = 16, 80
    end
    d[5] = 98
    d[7] = d[4] + 49
    d[12] = d[1] * 5 + 5
    t.func = spoutRainStep
  end

  -- pokefirered/src/battle_anim_water.c:1465
  local function waterSportDropletStep(s)
    if P.translateHArc(s) then
      if task_alive(s) then
        s._task.data[10] = 1
        s._task.data[8] = s._task.data[8] - 1
      end
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_water.c:1450
  local function waterSportDroplet(s)
    if P.translateHArc(s) then
      s.x = s.x + s.ox
      s.y = s.y + s.oy
      s.ox, s.oy = 0, 0
      s.data[0] = 6
      s.data[2] = P.band(P.Random(), 0x1F) - 16 + s.x
      s.data[4] = P.band(P.Random(), 0x1F) - 16 + s.y
      s.data[5] = P.s16(P.bxor(P.band(P.Random(), 7), 0xFFFF))
      P.initArc(s)
      s.callback = waterSportDropletStep
    end
  end

  -- pokefirered/src/battle_anim_water.c:1429
  local function waterSportCreate(t, vm)
    local d = t.data
    d[2] = d[2] + 1
    if d[2] > 1 then
      d[2] = 0
      local s = P.createSprite(vm, "GLOWY_BLUE_ORB", T.gSmallWaterOrbSpriteTemplate, d[3], d[4], 10, waterSportDroplet, 8, 8)
      if s then
        s.data[0] = 16
        s.data[2] = d[5]
        s.data[4] = d[6]
        s.data[5] = d[9]
        P.initArc(s)
        bind(s, t)
        d[8] = d[8] + 1
      end
    end
  end

  -- pokefirered/src/battle_anim_water.c:1360
  local function waterSportStep(t, vm)
    local d = t.data
    local st = d[0]
    if st == 0 then
      waterSportCreate(t, vm)
      if d[10] == 0 then d[0] = d[0] + 1 else d[0] = d[0] + 2 end
    elseif st == 1 then
      waterSportCreate(t, vm)
      d[1] = d[1] + 1
      if d[1] > 16 then
        d[1] = 0
        d[0] = d[0] + 1
      end
    elseif st == 2 then
      waterSportCreate(t, vm)
      d[5] = d[5] + d[7] * 6
      if not (d[5] >= -16 and d[5] <= 256) then
        d[12] = d[12] + 1
        if d[12] > 2 then
          d[13] = 1
          d[0] = 6
          d[1] = 0
        else
          d[1] = 0
          d[0] = d[0] + 1
        end
      end
    elseif st == 3 or st == 5 then
      waterSportCreate(t, vm)
      d[6] = d[6] - d[7] * 2
      d[1] = d[1] + 1
      if d[1] > 7 then
        if st == 3 then d[0] = d[0] + 1 else d[0] = 2 end
      end
    elseif st == 4 then
      waterSportCreate(t, vm)
      d[5] = d[5] - d[7] * 6
      if not (d[5] >= -16 and d[5] <= 256) then
        d[12] = d[12] + 1
        d[1] = 0
        d[0] = d[0] + 1
      end
    elseif st == 6 then
      d[1] = (d[1] or 0) + 1
      if d[8] <= 0 or d[1] > 60 then d[0] = d[0] + 1 end
    else
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_water.c:1343
  TK.WaterSport = function(t, vm)
    local d = t.data
    d[10] = vm.args[0] or 0
    d[3] = P.coord(vm, P.atk(vm), P.X_2)
    d[4] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
    d[7] = (P.atk(vm) == "player") and 1 or -1
    d[5] = d[3] + d[7] * 8
    d[6] = d[4] - d[7] * 8
    d[9] = -32
    d[1] = 0
    d[0] = 0
    t.func = waterSportStep
  end

  -- pokefirered/src/battle_anim_water.c:689
  TK.StartSinAnimTimer = function(t, vm)
    t.data[0] = vm.args[0]
    vm.args[7] = 0
    t.func = runSinTimer
  end

  return TK
end
