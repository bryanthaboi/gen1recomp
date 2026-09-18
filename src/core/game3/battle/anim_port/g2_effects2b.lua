local P = require("src.core.game3.battle.anim_port.g2_pret")

local CB = {}
local TASKS = {}

local band = bit.band

local function sketch_step(t)
  local d = t.data
  if d[4] == 0 then
    d[5] = d[5] + 1
    if d[5] > 20 then d[4] = d[4] + 1 end
  elseif d[4] == 1 then
    d[1] = d[1] + 1
    if d[1] > 3 then
      d[1] = 0
      d[2] = band(d[3], 3)
      d[5] = d[0] - d[3]
      if d[2] == 1 then
        d[5] = d[5] - 2
      elseif d[2] == 2 or d[2] == 3 then
        d[5] = d[5] + 1
      end
      if d[5] >= 0 then t.g2.shift[d[5]] = 0 end
      d[3] = d[3] + 1
      if d[3] >= d[15] then
        local p = t.g2.p
        if p and p.hShift == t.g2.shift then p.hShift = nil end
        P.destroyTask(t)
      end
    end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2399
TASKS.SketchDrawMon = P.task(function(t)
  local tg = P.tgt()
  local d = t.data
  d[0] = P.yWithElevation(tg) + 32
  d[1] = 4
  d[2] = 0
  d[3] = 0
  d[4] = 0
  d[5] = 0
  d[15] = P.coordAttr(tg, P.ATTR_HEIGHT)
  d[6] = 0
  local shift = {}
  for i = d[0] - 0x40, d[0] do
    if i >= 0 then shift[i] = -0xF0 end
  end
  t.g2.shift = shift
  local p = P.present(tg)
  t.g2.p = p
  if p then p.hShift = shift end
  t.func = sketch_step
end)

local function pencil_step(s)
  local d = s.data
  if d[0] == 0 then
    d[2] = d[2] + 1
    if d[2] > 1 then
      d[2] = 0
      s.invisible = not s.invisible
    end
    d[1] = d[1] + 1
    if d[1] > 16 then
      s.invisible = false
      d[0] = d[0] + 1
    end
  elseif d[0] == 1 then
    d[1] = d[1] + 1
    if d[1] > 3 and d[2] < d[5] then
      d[1] = 0
      s.y = s.y - 1
      d[2] = d[2] + 1
      if d[2] % 10 == 0 then P.playSE("SE_M_SKETCH", d[6]) end
    end
    d[4] = d[4] + d[3]
    if d[4] > 31 then
      d[4] = 0x40 - d[4]
      d[3] = -d[3]
    elseif d[4] <= -32 then
      d[4] = -0x40 - d[4]
      d[3] = -d[3]
    end
    s.x2 = d[4]
    if d[5] == d[2] then
      d[1] = 0
      d[2] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 2 then
    d[2] = d[2] + 1
    if d[2] > 1 then
      d[2] = 0
      s.invisible = not s.invisible
    end
    d[1] = d[1] + 1
    if d[1] > 16 then
      s.invisible = false
      P.destroy(s)
    end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2487
function CB.Pencil(s)
  local tg = P.tgt()
  s.x = P.coord(tg, 0) - 16
  s.y = P.yWithElevation(tg) + 16
  s.data[0] = 0
  s.data[1] = 0
  s.data[2] = 0
  s.data[3] = 16
  s.data[4] = 0
  s.data[5] = P.coordAttr(tg, P.ATTR_HEIGHT) + 2
  local vm = P.vm
  s.data[6] = vm and vm.adjustPanning and vm:adjustPanning(63) or 63
  s.pcb = pencil_step
end

-- pokefirered/src/battle_anim_effects_2.c:2560
function CB.BlendThinRing(s)
  s.pcb = P.AnimSpriteOnMonPos
  s.pcb(s)
end

local function hyper_voice_wait_end(s)
  if P.AnimTranslateLinear(s) then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:2600
function CB.HyperVoiceRing(s)
  local b1, b2
  if P.arg(5) == 0 then
    b1, b2 = P.atk(), P.tgt()
  else
    b1, b2 = P.tgt(), P.atk()
  end
  local xt, yt = 0, 1
  if P.arg(6) ~= 0 then xt, yt = 2, 3 end
  local startX
  if b1 ~= "player" then
    startX = P.u16(P.coord(b1, xt) + P.arg(0))
    s.subpriority = P.subpriorityOf(b2) - 1
  else
    startX = P.u16(P.coord(b1, xt) - P.arg(0))
    s.subpriority = P.subpriorityOf(b1) - 1
  end
  local startY = P.u16(P.coord(b1, yt) + P.arg(1))
  local x = P.coord(b2, xt)
  local y = P.coord(b2, yt)
  if b2 ~= "player" then x = x + P.arg(3) else x = x - P.arg(3) end
  y = y + P.arg(4)
  s.x = P.s16(startX)
  s.data[1] = P.s16(startX)
  s.y = P.s16(startY)
  s.data[3] = P.s16(startY)
  s.data[2] = P.s16(x)
  s.data[4] = P.s16(y)
  s.data[0] = P.arg(0)
  P.InitAnimLinearTranslation(s)
  s.pcb = hyper_voice_wait_end
  s.pcb(s)
end

-- pokefirered/src/battle_anim_effects_2.c:2685
function CB.UproarRing(s)
  P.palBlend("tag:THIN_RING", P.arg(5), P.u16(P.arg(4)))
  P.startAffineAnim(s, 1)
  s.pcb = P.AnimSpriteOnMonPos
  s.pcb(s)
end

local function set_bld_alpha(eva, evb)
  local vm = P.vm
  if vm then vm.bldAlpha = { eva = eva, evb = evb } end
end

local function egg_step4_cb(s)
  local vm = P.vm
  if vm then vm.bldAlpha = nil end
  P.destroy(s)
end

local function egg_step4(s)
  if P.u16(P.arg(7)) == 0xFFFF then
    s.invisible = true
    if s.data[7] == 0 then
      s.pcb = egg_step4_cb
    else
      s.pcb = P.DestroyAnimSprite
    end
  end
end

local function egg_step3_cb2(s)
  local v = s.data[1]
  s.data[1] = v + 1
  if v % 3 == 0 then
    s.data[0] = s.data[0] - 1
    set_bld_alpha(s.data[0], 16 - s.data[0])
    if s.data[0] == 0 then s.pcb = egg_step4 end
  end
end

local function egg_step3_cb1(s)
  s.y2 = s.y2 - 2
  s.data[0] = s.data[0] + 1
  if s.data[0] == 9 then
    s.data[0] = 16
    s.data[1] = 0
    set_bld_alpha(s.data[0], 0)
    s.pcb = egg_step3_cb2
  end
end

local function egg_step3(s)
  if s.affineAnimEnded then
    P.startAffineAnim(s, 1)
    s.data[0] = 0
    if s.data[7] == 0 then
      s.tileBase = s.tileBase + 16
      s.pcb = egg_step3_cb1
    else
      s.tileBase = s.tileBase + 32
      s.pcb = egg_step4
    end
  end
end

local function egg_step2(s)
  local v = s.data[0]
  s.data[0] = v + 1
  if v > 19 then
    P.startAffineAnim(s, 2)
    s.pcb = egg_step3
  end
end

local function egg_step1(s)
  s.y2 = s.y2 - P.asr(s.data[0], 8)
  s.x2 = P.asr(s.data[1], 8)
  s.data[0] = s.data[0] - 32
  local add = (P.atk() ~= "player") and -160 or 160
  s.data[1] = P.s16(s.data[1] + add)
  if s.y2 > 0 then
    s.y = s.y + s.y2
    s.x = s.x + s.x2
    s.y2 = 0
    s.x2 = 0
    s.data[0] = 0
    P.startAffineAnim(s, 1)
    s.pcb = egg_step2
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2697
function CB.SoftBoiledEgg(s)
  P.InitSpritePosToAnimAttacker(s, false)
  local r1 = (P.atk() ~= "player") and -160 or 160
  s.data[0] = 0x380
  s.data[1] = r1
  s.data[7] = P.arg(2)
  s.pcb = egg_step1
end

local function stretch_disappear_step(t)
  if not P.RunAffineAnimFromTaskData(t) then
    local m = t.g2.affMon
    m.y2 = 0
    m.invisible = true
    P.destroyTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2802
TASKS.AttackerStretchAndDisappear = P.task(function(t)
  local m = P.mon(P.atk())
  if not m then return P.destroyTask(t) end
  P.PrepareAffineAnimInTaskData(t, m, P.affineCmds("sStretchAttackerAffineAnimCmds"))
  t.func = stretch_disappear_step
end)

local function es_impact_step(t)
  local d = t.data
  local m = t.g2.mon
  if d[0] == 0 then
    m.x2 = m.x2 + d[14]
    d[1] = 0
    d[2] = 0
    d[3] = 0
    d[0] = d[0] + 1
  elseif d[0] == 1 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] + 1
      if band(d[2], 1) ~= 0 then m.x2 = m.x2 + 6 else m.x2 = m.x2 - 6 end
      d[3] = d[3] + 1
      if d[3] > 4 then
        if band(d[2], 1) ~= 0 then m.x2 = m.x2 - 6 end
        d[0] = d[0] + 1
      end
    end
  elseif d[0] == 2 then
    d[12] = d[12] - 1
    if d[12] ~= 0 then d[0] = 0 else d[0] = d[0] + 1 end
  elseif d[0] == 3 then
    m.x2 = m.x2 + d[13]
    if m.x2 == 0 then P.destroyTask(t) end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2824
TASKS.ExtremeSpeedImpact = P.task(function(t)
  local d = t.data
  d[12] = 3
  if P.tgt() == "player" then
    d[13] = -1
    d[14] = 8
  else
    d[13] = 1
    d[14] = -8
  end
  local m = P.mon(P.tgt())
  if not m then return P.destroyTask(t) end
  t.g2.mon = m
  t.func = es_impact_step
end)

local function es_reappear_step(t)
  local d = t.data
  local m = t.g2.mon
  if d[0] == 0 then
    d[1] = d[1] + 1
    if d[1] > d[4] then
      d[1] = 0
      d[2] = d[2] + 1
      m.invisible = band(d[2], 1) == 0
      d[3] = d[3] + 1
      if d[3] >= d[13] then
        d[4] = d[4] + 1
        if d[4] < d[14] then
          d[1] = 0
          d[2] = 0
          d[3] = 0
        else
          m.invisible = false
          P.destroyTask(t)
        end
      end
    end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2894
TASKS.ExtremeSpeedMonReappear = P.task(function(t)
  local m = P.mon(P.atk())
  if not m then return P.destroyTask(t) end
  t.g2.mon = m
  t.data[4] = 1
  t.data[13] = 14
  t.data[14] = 2
  t.func = es_reappear_step
end)

local SPEED_DUST_POS = { [0] = { 30, 28 }, { -20, 24 }, { 16, 26 }, { -10, 28 } }

local function speed_dust_step(t)
  local d = t.data
  if d[8] == 0 then
    d[4] = d[4] + 1
    if d[4] > 1 then
      d[4] = 0
      d[5] = band(d[5] + 1, 1)
      d[6] = d[6] + 1
      if d[6] > 20 then
        if d[7] == 0 then
          d[6] = 0
          d[8] = 1
        else
          d[8] = 2
        end
      end
    end
  elseif d[8] == 1 then
    d[5] = 0
    d[4] = d[4] + 1
    if d[4] > 20 then
      d[7] = 1
      d[8] = 0
    end
  elseif d[8] == 2 then
    d[5] = 1
  end
  if d[0] == 0 then
    d[1] = d[1] + 1
    if d[1] > 4 then
      d[1] = 0
      local s = P.createSprite("gSpeedDustSpriteTemplate", d[14], d[15], 0)
      if s then
        s.g2.task = t
        s.data[1] = 13
        s.x2 = SPEED_DUST_POS[d[2]][1]
        s.y2 = SPEED_DUST_POS[d[2]][2]
        d[13] = d[13] + 1
        d[2] = d[2] + 1
        if d[2] > 3 then
          d[2] = 0
          d[3] = d[3] + 1
          if d[3] > 5 then d[0] = d[0] + 1 end
        end
      end
    end
  elseif d[0] == 1 then
    if d[13] == 0 then P.destroyTask(t) end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3024
function CB.SpeedDust(s)
  local t = s.g2.task
  s.invisible = (t and t.data and t.data[5] ~= 0) and true or false
  if s.animEnded then
    if t and t.data then t.data[s.data[1]] = t.data[s.data[1]] - 1 end
    P.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2938
TASKS.SpeedDust = P.task(function(t)
  local d = t.data
  d[1] = 4
  d[14] = P.coord(P.atk(), 0)
  d[15] = P.coord(P.atk(), 1)
  t.func = speed_dust_step
end)

-- pokefirered/src/battle_anim_effects_2.c:3034
local MUSIC_NOTE_PAL_TAGS = { [0] = "MUSIC_NOTES_2", "MUSIC_NOTES_2_PAL1", "MUSIC_NOTES_2_PAL2" }

TASKS.LoadMusicNotesPals = P.task(function(t)
  local AnimPal = require("src.core.game3.battle.anim_pal")
  local pack = AnimPal._pack
  local full = pack and pack.tagPals and pack.tagPals.MUSIC_NOTES_2
  for i = 0, 2 do
    local tag = MUSIC_NOTE_PAL_TAGS[i]
    if i > 0 then AnimPal.alloc(tag) end
    if full then
      local row = {}
      for c = 0, 15 do row[c] = full[i * 16 + c + 1] or 0 end
      AnimPal.load(tag, row, 0, 16)
    end
  end
  P.destroyTask(t)
end)

-- pokefirered/src/battle_anim_effects_2.c:3052
TASKS.FreeMusicNotesPals = P.task(function(t)
  local AnimPal = require("src.core.game3.battle.anim_pal")
  for i = 0, 2 do AnimPal.free(MUSIC_NOTE_PAL_TAGS[i]) end
  P.destroyTask(t)
end)

-- pokefirered/src/battle_anim_effects_2.c:3062
local function set_music_note_palette(s, a, b)
  local tile = (band(b, 1) ~= 0) and 32 or 0
  s.tileBase = s.tileBase + tile + a * 4
  s._palTag = MUSIC_NOTE_PAL_TAGS[math.floor(b / 2)]
end

-- pokefirered/src/battle_anim_effects_2.c:3069
function CB.HealBellMusicNote(s)
  P.InitSpritePosToAnimAttacker(s, false)
  if P.atk() ~= "player" then P.setArg(2, -P.arg(2)) end
  s.data[0] = P.arg(4)
  s.data[2] = P.coord(P.atk(), 0) + P.arg(2)
  s.data[4] = P.coord(P.atk(), 1) + P.arg(3)
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, P.DestroyAnimSprite)
  set_music_note_palette(s, P.arg(5), P.arg(6))
end

local function magenta_heart(s)
  s.data[0] = s.data[0] + 1
  if s.data[0] == 1 then P.InitSpritePosToAnimAttacker(s, false) end
  s.x2 = P.Sin(s.data[1], 8)
  s.y2 = P.asr(s.data[2], 8)
  s.data[1] = (s.data[1] + 7) % 256
  s.data[2] = P.s16(s.data[2] - 0x80)
  if s.data[0] == 60 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:3083
function CB.MagentaHeart(s)
  magenta_heart(s)
  s.pcb = magenta_heart
end

local function fake_out_draw(t)
  local g2 = t.g2
  if not g2 or not (love and love.graphics) then return end
  local l, r = g2.winL or 0, g2.winR or 240
  love.graphics.setColor(0, 0, 0, 1)
  if g2.full then
    love.graphics.rectangle("fill", 0, 0, 240, 160)
  else
    if l > 0 then love.graphics.rectangle("fill", 0, 0, l, 160) end
    if r < 240 then love.graphics.rectangle("fill", r, 0, 240 - r, 160) end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function fake_out_step2(t)
  t.data[10] = t.data[10] + 1
  if t.data[10] == 5 then
    t.data[11] = 0x88
    t.draw = nil
    P.palBlend("bg", 16, 0x7FFF)
  elseif t.data[10] > 4 then
    t.draw = nil
    P.destroyTask(t)
  end
end

local function fake_out_step1(t)
  t.data[0] = t.data[0] + 13
  t.data[1] = t.data[1] - 13
  if t.data[0] >= t.data[1] then
    t.g2.full = true
    t.func = fake_out_step2
  else
    t.g2.winL = t.data[0]
    t.g2.winR = t.data[1]
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3096
TASKS.FakeOut = P.task(function(t)
  t.data[0] = 0
  t.data[1] = P.DISPLAY_WIDTH
  t.g2.winL = 0
  t.g2.winR = P.DISPLAY_WIDTH
  t.z = 1
  t.draw = fake_out_draw
  t.func = fake_out_step1
end)

local function stretch_up(t, which)
  local m = t.g2.mon or P.monById(which)
  t.g2.mon = m
  if not m then return P.destroyTask(t) end
  t.data[0] = t.data[0] + 1
  if t.data[0] == 1 then
    P.PrepareAffineAnimInTaskData(t, m, P.affineCmds("sAffineAnims_StretchBattlerUp"))
    m.x2 = 4
  else
    m.x2 = -m.x2
    if not P.RunAffineAnimFromTaskData(t) then
      m.x2 = 0
      m.y2 = 0
      P.destroyTask(t)
    end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3149
TASKS.StretchTargetUp = P.task(function(t)
  t.func = function(tt) stretch_up(tt, P.ANIM_TARGET) end
  stretch_up(t, P.ANIM_TARGET)
end)

-- pokefirered/src/battle_anim_effects_2.c:3170
TASKS.StretchAttackerUp = P.task(function(t)
  t.func = function(tt) stretch_up(tt, P.ANIM_ATTACKER) end
  stretch_up(t, P.ANIM_ATTACKER)
end)

return { cb = CB, tasks = TASKS }
