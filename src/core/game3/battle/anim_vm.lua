-- Pret-shaped battle anim script VM over portable IR (not live ROM pointers).
-- Opcodes mirror battle_anim_script.inc; createsprite/createvisualtask use named IDs.

local bit = require("bit")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimPal = require("src.core.game3.battle.anim_pal")
local AnimCoords = require("src.core.game3.battle.anim_coords")

local band, rshift = bit.band, bit.rshift

local AnimVm = {}

AnimVm.Z = {
  BG = 0,
  BEHIND = 10,
  ENEMY = 20,
  MID = 30,
  PLAYER = 40,
  FRONT = 50,
  HEALTHBOX = 60,
  UI = 70,
}

local ARG_COUNT = 8
local WAIT_CAP = 900

local SOUND_PAN_ATTACKER = -64
local SOUND_PAN_TARGET = 63

local function s16(v)
  v = band(math.floor(tonumber(v) or 0), 0xFFFF)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

local function resolve_pan_token(pan)
  if pan == nil then return 0 end
  if type(pan) == "number" then return pan end
  local s = tostring(pan)
  if s == "SOUND_PAN_TARGET" or s == "TARGET" then return SOUND_PAN_TARGET end
  if s == "SOUND_PAN_ATTACKER" or s == "ATTACKER" then return SOUND_PAN_ATTACKER end
  return tonumber(s) or 0
end

-- pokefirered/src/battle_anim.c:1160
local function adjust_panning(vm, pan)
  pan = resolve_pan_token(pan)
  local atk = vm and vm:attackerSide() or "player"
  local tgt = vm and vm:targetSide() or "enemy"
  if vm and vm.statusAnimActive then
    if atk ~= "player" then pan = SOUND_PAN_TARGET else pan = SOUND_PAN_ATTACKER end
  elseif atk == "player" then
    if tgt == "player" then
      if pan == SOUND_PAN_TARGET then
        pan = SOUND_PAN_ATTACKER
      elseif pan ~= SOUND_PAN_ATTACKER then
        pan = -pan
      end
    end
  elseif tgt == "enemy" then
    if pan == SOUND_PAN_ATTACKER then
      pan = SOUND_PAN_TARGET
    end
  else
    pan = -pan
  end
  if pan > SOUND_PAN_TARGET then pan = SOUND_PAN_TARGET end
  if pan < SOUND_PAN_ATTACKER then pan = SOUND_PAN_ATTACKER end
  return pan
end

-- pokefirered/src/battle_anim.c:1197
local function adjust_panning2(vm, pan)
  pan = resolve_pan_token(pan)
  local atk = vm and vm:attackerSide() or "player"
  if vm and vm.statusAnimActive then
    if atk ~= "player" then pan = SOUND_PAN_TARGET else pan = SOUND_PAN_ATTACKER end
  elseif atk ~= "player" then
    pan = -pan
  end
  return pan
end

-- pokefirered/src/battle_anim.c:1214
local function keep_pan_in_range(pan)
  if pan > SOUND_PAN_TARGET then return SOUND_PAN_TARGET end
  if pan < SOUND_PAN_ATTACKER then return SOUND_PAN_ATTACKER end
  return pan
end

-- pokefirered/src/battle_anim.c:1226
local function calc_pan_increment(src, tgt, inc)
  inc = math.abs(inc)
  if src < tgt then return inc end
  if src > tgt then return -inc end
  return 0
end

AnimVm.keepPanInRange = keep_pan_in_range
AnimVm.calcPanIncrement = calc_pan_increment

local function play_se12(se, pan)
  if se == nil then return end
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and Audio and Audio.playSe then pcall(Audio.playSe, se, { pan = pan }) end
end

-- pokefirered/src/sound.c:606
local function se12_panpot(pan)
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and Audio and Audio.setSePan then pcall(Audio.setSePan, pan) end
end
AnimVm.se12PanpotControl = se12_panpot

local function se_playing()
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and Audio and Audio.isSePlaying then
    local ok2, v = pcall(Audio.isSePlaying)
    return ok2 and v or false
  end
  return false
end

local function default_pal()
  local p = {}
  p[0] = { 0, 0, 0, 0 }
  for i = 1, 15 do
    local g = i / 15
    p[i] = { g, g, g, 1 }
  end
  p[1] = { 1, 1, 1, 1 }
  p[2] = { 1, 0.9, 0.2, 1 }
  p[3] = { 1, 0.4, 0.1, 1 }
  return p
end

function AnimVm.new()
  local vm = {
    active = false,
    isReversed = false,
    _attackerSide = "player",
    _targetSide = "enemy",
    _atkId = 0,
    _tgtId = 1,
    pc = 1,
    script = nil,
    callStack = {},
    args = {},
    framesToWait = 0,
    waitingVisual = false,
    headless = false,
    pals = { [0] = default_pal() },
    loadedTags = {},
    visualTaskCount = 0,
    ctx = {},
    bg3 = { x = 0, y = 0 },
    _drawList = {},
    _onEnd = nil,
    _pack = nil,
    _shader = nil,
    _cbMode = "run",
    _phase = "cb1",
    _monbg = AnimCoords.idTable(),
    _bgPrio = { [1] = 2, [2] = 2 },
    _tagBlend = {},
  }
  for i = 0, ARG_COUNT - 1 do vm.args[i] = 0 end
  return setmetatable(vm, { __index = AnimVm })
end

function AnimVm:attackerSide()
  return self._attackerSide or "player"
end

function AnimVm:targetSide()
  return self._targetSide or (self._attackerSide == "player" and "enemy" or "player")
end

function AnimVm:attackerId()
  local id = self._atkId
  if id ~= nil and AnimCoords.sideOf(id) == self:attackerSide() then return id end
  return AnimCoords.fixedId(self:attackerSide()) or 0
end

function AnimVm:targetId()
  local id = self._tgtId
  if id ~= nil and AnimCoords.sideOf(id) == self:targetSide() then return id end
  return AnimCoords.fixedId(self:targetSide()) or 1
end

function AnimVm:allyPair()
  local a, t = self:attackerId(), self:targetId()
  return a ~= t and AnimCoords.sideOf(a) == AnimCoords.sideOf(t)
end

-- pokefirered/src/battle_anim_mons.c:860
function AnimVm:isDouble()
  return AnimCoords.isDouble()
end

-- pokefirered/src/battle_anim_mons.c:831
function AnimVm:battlerAtPosition(position)
  local id = tonumber(position)
  if id == nil or id < 0 or id > 3 then return nil end
  if id >= 2 and not AnimCoords.isDouble() then return nil end
  return id
end

local function key_to_id(key, cur)
  if type(key) == "number" then return AnimCoords.idOf(key) end
  if key == "player" or key == "enemy" then
    if cur ~= nil and AnimCoords.sideOf(cur) == key then return cur end
    return AnimCoords.idOf(key)
  end
  return nil
end

function AnimVm:applyBind()
  if self.active then AnimCoords.bind(self:attackerId(), self:targetId()) end
end

function AnimVm:setBattlers(atk, tgt)
  local a = key_to_id(atk, self._atkId)
  local t = key_to_id(tgt, self._tgtId)
  if a ~= nil then
    self._atkId = a
    self._attackerSide = AnimCoords.sideOf(a)
  elseif atk then
    self._attackerSide = atk
  end
  if t ~= nil then
    self._tgtId = t
    self._targetSide = AnimCoords.sideOf(t)
  elseif tgt then
    self._targetSide = tgt
  end
  self.isReversed = (self._attackerSide == "enemy")
  self:applyBind()
end

-- pokefirered/src/battle_anim_mons.c:333
function AnimVm:battlerId(token)
  if token == nil then return self:targetId() end
  local n = tonumber(token)
  local s = type(token) == "string" and token:lower() or nil
  if n == 0 or s == "attacker" or s == "anim_attacker" then return self:attackerId() end
  if n == 1 or s == "target" or s == "anim_target" then return self:targetId() end
  local id
  if n == 2 or s == "atk_partner" or s == "anim_atk_partner" then
    id = AnimCoords.partner(self:attackerId())
  elseif n == 3 or s == "def_partner" or s == "anim_def_partner" then
    id = AnimCoords.partner(self:targetId())
  elseif s == "player" or s == "enemy" then
    return AnimCoords.idOf(s)
  else
    return self:targetId()
  end
  if AnimCoords.spritePresent(nil, id) then return id end
  return nil
end

function AnimVm:resolveBattlerSide(token)
  if token == nil then return self:targetSide() end
  if type(token) == "number" then
    if token == 0 then return self:attackerSide()
    elseif token == 1 then return self:targetSide()
    elseif token == 2 or token == 3 then return self:battlerId(token)
    else return nil end
  end
  local s = tostring(token):lower()
  if s == "attacker" or s == "anim_attacker" or s == "0" then
    return self:attackerSide()
  end
  if s == "target" or s == "anim_target" or s == "1" then
    return self:targetSide()
  end
  if s == "player" or s == "enemy" then return s end
  if s == "atk_partner" or s == "anim_atk_partner" or s == "def_partner" or s == "anim_def_partner" then
    return self:battlerId(s)
  end
  return self:targetSide()
end

function AnimVm:x(v)
  v = tonumber(v) or 0
  if self.isReversed then return -v end
  return v
end

local function live_species(id)
  local b = AnimCoords.battler(nil, id)
  if type(b) ~= "table" then return nil end
  if b.expTransform and b.expTransform.species then return b.expTransform.species end
  return b.species or (b.mon and (b.mon.species or b.mon.speciesId))
end

function AnimVm:speciesForSide(side)
  if side == nil then return nil end
  local id = AnimCoords.idOf(side)
  if self._speciesBySide and self._speciesBySide[side] ~= nil then return self._speciesBySide[side] end
  if id ~= nil and id == self:attackerId() and self._attackerSpecies ~= nil then return self._attackerSpecies end
  if id ~= nil and id == self:targetId() and self._targetSpecies ~= nil then return self._targetSpecies end
  if id == nil then
    if side == self:attackerSide() then return self._attackerSpecies end
    if side == self:targetSide() then return self._targetSpecies end
    return nil
  end
  if id >= 2 then return live_species(id) end
  return nil
end

-- pokefirered/src/battle_anim.c:1160
function AnimVm:adjustPanning(pan)
  return adjust_panning(self, pan)
end

-- pokefirered/src/battle_anim.c:1197
function AnimVm:adjustPanning2(pan)
  return adjust_panning2(self, pan)
end

function AnimVm:playSe12(se, pan)
  play_se12(se, pan)
end

function AnimVm:battlerCenter(side)
  local Anim = require("src.core.game3.battle.anim")
  if side == "attacker" then side = self:attackerId()
  elseif side == "target" then side = self:targetId() end
  return Anim.battlerCenter(side)
end

function AnimVm:setPack(pack)
  self._pack = pack
  AnimPal.setPack(pack)
end

function AnimVm:idle()
  return not self.active
end

function AnimVm:busy()
  return self.active == true
end

function AnimVm:visualCount()
  local n = 0
  AnimTasks.init()
  for i = 1, AnimTasks.MAX do
    local t = AnimTasks._pool[i]
    if t.active and t._g4kind ~= "sound" and t._g4kind ~= "aux" and not t._uncounted then n = n + 1 end
  end
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active and s._g4counted then n = n + 1 end
  end
  return n
end

function AnimVm:soundCount()
  local n = 0
  AnimTasks.init()
  for i = 1, AnimTasks.MAX do
    local t = AnimTasks._pool[i]
    if t.active and t._g4kind == "sound" then n = n + 1 end
  end
  return n
end

function AnimVm:reset()
  self.active = false
  self.pc = 1
  self.script = nil
  self.callStack = {}
  self._retScript, self._retPc = nil, nil
  self.framesToWait = 0
  self._cbMode = "run"
  self.waitingVisual = false
  self.waitingSprites = false
  self._waitFrames = 0
  self._endWait = 0
  self._soundWait = 0
  self.loadedTags = {}
  AnimPal.reset()
  self._onEnd = nil
  self._attackerSpecies = nil
  self._targetSpecies = nil
  self._speciesBySide = nil
  self._monbg = AnimCoords.idTable()
  self._bgPrio = { [1] = 2, [2] = 2 }
  AnimCoords.bind(nil)
  self._tagBlend = {}
  self.bldAlpha = nil
  self.statusAnimActive = false
  self.ctx = {}
  self.animArg = 0
  self.bg3 = { x = 0, y = 0 }
  self._bgFade = nil
  self._bgFadeState = 0
  self._animBgId = nil
  self._animBgBlend = nil
  self.animCustomPanning = 0
  self._spriteHooks = nil
  for i = 0, 15 do self.args[i] = 0 end
  AnimSprites.reset()
  AnimTasks.reset()
end

local function finish(self)
  self.active = false
  self.waitingVisual = false
  self.waitingSprites = false
  self.framesToWait = 0
  self._cbMode = "run"
  local cb = self._onEnd
  self._onEnd = nil
  AnimSprites.reset()
  AnimTasks.reset()
  self._monbg = AnimCoords.idTable()
  AnimCoords.bind(nil)
  if cb then pcall(cb) end
end

local function normalize_args(src)
  local out = {}
  for i = 0, ARG_COUNT - 1 do out[i] = 0 end
  if type(src) ~= "table" then return out end
  if src[0] ~= nil then
    for i = 0, ARG_COUNT - 1 do out[i] = s16(src[i] or 0) end
  else
    for i = 1, ARG_COUNT do out[i - 1] = s16(src[i] or 0) end
  end
  return out
end

local function begin(self, script, opts)
  self:reset()
  self.active = true
  self.script = script
  self.pc = 1
  self.isReversed = opts.isReversed and true or false
  local atk, tgt = opts.attackerSide, opts.targetSide
  local atkId = tonumber(opts.attackerId) or AnimCoords.fixedId(atk)
  local tgtId = tonumber(opts.targetId) or AnimCoords.fixedId(tgt)
  if type(atk) ~= "string" then atk = atkId and AnimCoords.sideOf(atkId) or nil end
  if type(tgt) ~= "string" then tgt = tgtId and AnimCoords.sideOf(tgtId) or nil end
  self._attackerSide = atk or (self.isReversed and "enemy" or "player")
  self._targetSide = tgt or (self.isReversed and "player" or "enemy")
  if atk and opts.isReversed == nil then
    self.isReversed = (self._attackerSide == "enemy")
  end
  self._atkId = atkId or AnimCoords.fixedId(self._attackerSide)
  self._tgtId = tgtId or AnimCoords.fixedId(self._targetSide)
  AnimCoords.bind(self._atkId, self._tgtId)
  self._attackerSpecies = opts.attackerSpecies
  self._targetSpecies = opts.targetSpecies
  self._speciesBySide = AnimCoords.idTable()
  if opts.speciesById then
    for k, v in pairs(opts.speciesById) do self._speciesBySide[k] = v end
  end
  if opts.speciesBySide then
    for k, v in pairs(opts.speciesBySide) do self._speciesBySide[k] = v end
  end
  if opts.attackerSpecies ~= nil and rawget(self._speciesBySide, self._atkId) == nil then
    rawset(self._speciesBySide, self._atkId, opts.attackerSpecies)
  end
  if opts.targetSpecies ~= nil and rawget(self._speciesBySide, self._tgtId) == nil then
    rawset(self._speciesBySide, self._tgtId, opts.targetSpecies)
  end
  self._onEnd = opts.onEnd
  self._turn = tonumber(opts.moveTurn or opts.turn) or 0
  self.statusAnimActive = opts.statusAnim and true or false
  self._phase = opts.phase or "cb1"
  local a = normalize_args(opts.args)
  for i = 0, ARG_COUNT - 1 do self.args[i] = a[i] end
  self.ctx = opts.ctx or {}
  self.animArg = tonumber(opts.animArg or self.ctx.animArg) or 0
  if self.ctx.animArg == nil then self.ctx.animArg = self.animArg end
  return true
end

function AnimVm:launch(script, opts)
  opts = opts or {}
  if self.headless or opts.headless then
    if opts.onEnd then pcall(opts.onEnd) end
    return true
  end
  if type(script) ~= "table" or #script == 0 then
    if opts.onEnd then pcall(opts.onEnd) end
    return false
  end
  return begin(self, script, opts)
end

function AnimVm:launchScript(ops, opts)
  opts = opts or {}
  if opts.phase == nil then
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.phase = "task"
    opts = o
  end
  return self:launch(ops, opts)
end

function AnimVm:launchTable(kind, index, opts)
  local pack = self._pack
  local tbl = pack and pack[kind]
  local ops = tbl and tbl[index]
  opts = opts or {}
  if kind == "moves" and opts.phase == nil then
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.phase = "cb1"
    opts = o
  end
  if kind == "status" and opts.statusAnim == nil then
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.statusAnim = true
    opts = o
  end
  return self:launchScript(ops, opts)
end

function AnimVm:ensureShader()
  return nil
end

function AnimVm:uploadPal(_slot)
  return false
end

local function sprite_source_quad(s, bw, bh)
  local qx = s.quadX or 0
  local qy = s.quadY or 0
  if s.quad and s._quadX == qx and s._quadY == qy and s._quadW == bw and s._quadH == bh then
    return s.quad
  end
  if not (s.image and s.image.getDimensions) then return nil end
  local iw, ih = s.image:getDimensions()
  if iw == bw and ih == bh and qx == 0 and qy == 0 then
    s.quad = nil
    return nil
  end
  local ok, q = pcall(love.graphics.newQuad, qx, qy, bw, bh, iw, ih)
  if not ok or not q then return nil end
  s.quad = q
  s._quadX, s._quadY, s._quadW, s._quadH = qx, qy, bw, bh
  return q
end

local BLEND_SHADER_SRC = [[
extern float coeff;
extern vec3 target;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  vec3 c5 = floor(c.rgb * 31.0 + 0.5);
  vec3 o = c5 + floor((target - c5) * coeff / 16.0);
  return vec4(o / 31.0, c.a) * color;
}
]]

local function blend_shader()
  if AnimVm._blendShader == nil then
    local ok, sh = pcall(love.graphics.newShader, BLEND_SHADER_SRC)
    AnimVm._blendShader = ok and sh or false
  end
  return AnimVm._blendShader or nil
end

function AnimVm:setTagBlend(tag, coeff, color)
  tag = tostring(tag or ""):upper():gsub("^ANIM_TAG_", "")
  if not coeff or coeff <= 0 then
    self._tagBlend[tag] = nil
  else
    self._tagBlend[tag] = { coeff = coeff, color = color or 0 }
  end
end

local function sprite_blend(vm, s)
  local b = s.palBlend
  if b and (b.coeff or 0) > 0 then return b end
  if s.tag and vm._tagBlend then
    local tb = vm._tagBlend[s.tag]
    if tb then return tb end
  end
  return nil
end

-- pokefirered/src/battle_anim.c:630
local function effective_z(vm, s)
  if not s._pz then return s.z or AnimSprites.Z.MID_FIELD end
  local pri = s.oamPriority or 2
  local sub = tonumber(s.subpriority) or 0
  if pri <= 1 then return 900 + (255 - sub) % 99 end
  if pri >= 3 then return math.max(1, math.min(98, 98 - sub)) end
  return AnimCoords.layerZ(sub, vm._monbg, vm._bgPrio)
end

local function draw_anim_bg(vm)
  local id = vm._animBgId
  local tintBg = vm._animBgBlend
  if id ~= nil and id >= 0 and AnimPal.bgColors("bg") and AnimPal.drawBg(id, "bg",
      band(math.floor(vm.bg3.x or 0), 0x1FF), band(math.floor(vm.bg3.y or 0), 0xFF),
      tintBg and { coeff = tintBg.coeff, color = tintBg.color } or nil) then
    id = nil
  end
  if id ~= nil and id >= 0 then
    local img = AnimVm.animBgImage(vm, id)
    if img then
      local iw, ih = img:getDimensions()
      if not vm._bgQuad or vm._bgQuadImg ~= img then
        pcall(function() img:setWrap("repeat", "repeat") end)
        vm._bgQuad = love.graphics.newQuad(0, 0, 240, 160, iw, ih)
        vm._bgQuadImg = img
      end
      local x = band(math.floor(vm.bg3.x or 0), 0x1FF) % iw
      local y = band(math.floor(vm.bg3.y or 0), 0xFF) % ih
      vm._bgQuad:setViewport(x, y, 240, 160, iw, ih)
      love.graphics.setColor(1, 1, 1, 1)
      local tint = vm._animBgBlend
      local sh = tint and (tint.coeff or 0) > 0 and blend_shader()
      if sh then
        local c = tonumber(tint.color) or 0
        pcall(function()
          sh:send("coeff", tint.coeff)
          sh:send("target", { band(c, 31), band(rshift(c, 5), 31), band(rshift(c, 10), 31) })
        end)
        love.graphics.setShader(sh)
      end
      love.graphics.draw(img, vm._bgQuad, 0, 0)
      if sh then love.graphics.setShader() end
    end
  end
  local f = vm._bgFade
  local y = f and f.y or 0
  if y > 0 then
    love.graphics.setColor(0, 0, 0, math.min(16, y) / 16)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function draw_sprite(self, s, a)
  if s.customDraw then
    s:customDraw(self)
  elseif s.image and a > 0 then
    local drawX = math.floor(s.x + (s.ox or 0) + 0.5)
    local drawY = math.floor(s.y + (s.oy or 0) + 0.5)
    love.graphics.setColor(1, 1, 1, a)
    local flipX = s.hFlip and -1 or 1
    local flipY = s.vFlip and -1 or 1
    local bw = s._baseW or s.w or 32
    local bh = s._baseH or s.h or 32
    local scaleX = (s.scaleX or 1) * flipX
    local scaleY = (s.scaleY or 1) * flipY
    local rot = s.rotation or 0
    local pivX = s.originX or (bw / 2)
    local pivY = s.originY or (bh / 2)
    local tint = sprite_blend(self, s)
    local pimg = AnimPal.begin(s, s.image, tint and { coeff = tint.coeff, color = tint.color } or nil)
    local sh = (not pimg) and tint and blend_shader()
    if sh then
      local r, g, b = band(tint.color, 31), band(rshift(tint.color, 5), 31), band(rshift(tint.color, 10), 31)
      pcall(function()
        sh:send("coeff", tint.coeff)
        sh:send("target", { r, g, b })
      end)
      love.graphics.setShader(sh)
    end
    local q = sprite_source_quad(s, bw, bh)
    if q then
      love.graphics.draw(pimg or s.image, q, drawX, drawY, rot, scaleX, scaleY, pivX, pivY)
    else
      love.graphics.draw(pimg or s.image, drawX, drawY, rot, scaleX, scaleY, pivX, pivY)
    end
    if sh or pimg then love.graphics.setShader() end
  end
end

function AnimVm:draw(minZ, maxZ)
  if not (love and love.graphics) then return end

  if (minZ or 0) <= 0 then draw_anim_bg(self) end

  if AnimTasks and AnimTasks.draw then
    AnimTasks.draw(minZ, maxZ, self)
  end

  local list = self._drawList
  for i = #list, 1, -1 do list[i] = nil end
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    s._poolIndex = i
    if s.active and s.visible ~= false then
      local z = effective_z(self, s)
      if (not minZ or z >= minZ) and (not maxZ or z <= maxZ) then
        s._drawZ = z
        list[#list + 1] = s
      end
    end
  end
  table.sort(list, function(a, b)
    if a._drawZ ~= b._drawZ then return a._drawZ < b._drawZ end
    return (a._poolIndex or 0) > (b._poolIndex or 0)
  end)

  local activeBlend = "alpha"
  local bld = self.bldAlpha
  local function setMode(mode)
    if mode ~= activeBlend then
      if mode == "add" then
        love.graphics.setBlendMode("add", "alphamultiply")
      else
        love.graphics.setBlendMode("alpha", "alphamultiply")
      end
      activeBlend = mode
    end
  end
  for _, s in ipairs(list) do
    local a = s.alpha or 1
    local eva, evb = nil, nil
    if s.objBlend and bld then
      eva = math.max(0, math.min(16, tonumber(bld.eva or bld[1]) or 16))
      evb = math.max(0, math.min(16, tonumber(bld.evb or bld[2]) or 0))
    end
    if eva and eva + evb ~= 16 and s.image and AnimPal.indexImage(s.image) then
      -- pokefirered/src/battle_anim.c:630
      setMode("alpha")
      AnimPal.blackPass = true
      s._drawAlpha = a * (1 - evb / 16)
      draw_sprite(self, s, s._drawAlpha)
      AnimPal.blackPass = nil
      setMode("add")
      s._drawAlpha = a * eva / 16
      draw_sprite(self, s, s._drawAlpha)
    else
      local desiredBlend = s.blendMode or "alpha"
      if eva then
        if evb >= 16 and eva < 16 then desiredBlend = "add" end
        a = a * eva / 16
      end
      setMode(desiredBlend)
      s._drawAlpha = a
      draw_sprite(self, s, a)
    end
  end

  if activeBlend ~= "alpha" then
    love.graphics.setBlendMode("alpha", "alphamultiply")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function tag_image(vm, tag)
  tag = tostring(tag or ""):upper():gsub("^ANIM_TAG_", "")
  local pack = vm._pack
  if pack and pack.tags and pack.tags[tag] and pack.tags[tag].image then
    return pack.tags[tag].image, pack.tags[tag]
  end
  return nil, pack and pack.tags and pack.tags[tag]
end

local function read_pack_bytes(file)
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = ok and Dataset.cache and Dataset.cache() or nil
  local rel = "data/generated/gba/pokemon/battle_anims/" .. file
  return cache and cache.read and (cache:read(rel) or cache:read("firered/" .. rel))
end

function AnimVm.sheetImage(vm, tag, w)
  tag = tostring(tag or ""):upper():gsub("^ANIM_TAG_", "")
  local img, info = tag_image(vm, tag)
  if not img or not info then return img, info and info.w end
  local iw = img:getWidth()
  w = tonumber(w)
  if not w or w <= 0 or w == iw or not (love and love.image) then return img, iw end
  info._relaid = info._relaid or {}
  local cached = info._relaid[w]
  if cached ~= nil then
    if cached then return cached, w end
    return img, iw
  end
  info._relaid[w] = false
  local bytes = info.file and read_pack_bytes(info.file)
  if type(bytes) ~= "string" then return img, iw end
  local okFd, fd = pcall(love.filesystem.newFileData, bytes, info.file)
  if not okFd then return img, iw end
  local okId, src = pcall(love.image.newImageData, fd)
  if not okId or not src then return img, iw end
  local sw, sh = src:getDimensions()
  local srcTilesWide = math.floor(sw / 8)
  local tiles = srcTilesWide * math.floor(sh / 8)
  local dstTilesWide = math.max(1, math.floor(w / 8))
  local dh = math.max(8, math.ceil(tiles / dstTilesWide) * 8)
  local dst = love.image.newImageData(dstTilesWide * 8, dh)
  for t = 0, tiles - 1 do
    local sx, sy = (t % srcTilesWide) * 8, math.floor(t / srcTilesWide) * 8
    local dx, dy = (t % dstTilesWide) * 8, math.floor(t / dstTilesWide) * 8
    dst:paste(src, dx, dy, sx, sy, 8, 8)
  end
  local okImg, out = pcall(love.graphics.newImage, dst)
  if not okImg or not out then return img, iw end
  out:setFilter("nearest", "nearest")
  info._relaid[w] = out
  AnimPal.relayIndex(info, tag, out, w)
  return out, dstTilesWide * 8
end

function AnimVm.animBgImage(vm, id)
  local pack = vm._pack
  local bgs = pack and pack.animBgs
  local info = bgs and bgs[id]
  if not info then return nil end
  if info.image ~= nil then return info.image or nil end
  info.image = false
  if not (love and love.image and love.graphics and info.file) then return nil end
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = ok and Dataset.cache and Dataset.cache() or nil
  local rel = "data/generated/gba/pokemon/battle_anims/" .. info.file
  local bytes = cache and cache.read and (cache:read(rel) or cache:read("firered/" .. rel))
  if type(bytes) ~= "string" or #bytes == 0 then return nil end
  local okFd, fd = pcall(love.filesystem.newFileData, bytes, info.file)
  if not okFd then return nil end
  local okImg, img = pcall(love.graphics.newImage, fd)
  if not okImg or not img then return nil end
  img:setFilter("nearest", "nearest")
  info.image = img
  return img
end

local LEGACY_TASK_CB = {
  HorizontalLunge = "HorizontalLunge", DoHorizontalLunge = "HorizontalLunge",
  ReverseHorizontalLungeDirection = "HorizontalLunge",
  VerticalDip = "VerticalDip", DoVerticalDip = "VerticalDip", ReverseVerticalDipDirection = "VerticalDip",
  SlideMonToOffset = "SlideMonToOffset", SlideMonToOriginalPos = "SlideMonToOriginalPos",
  SlideMonToOffsetAndBack = "SlideMonToOffsetAndBack",
  BowMon = "BowMon", AnimBowMon = "BowMon",
  ShakeMonOrBattleTerrain = "ShakeMonOrBattleTerrain", AnimShakeMonOrBattleTerrain = "ShakeMonOrBattleTerrain",
  SimplePaletteBlend = "BlendBattleAnimPal", AnimSimplePaletteBlend = "BlendBattleAnimPal",
  ComplexPaletteBlend = "ComplexPaletteBlend", AnimComplexPaletteBlend = "ComplexPaletteBlend",
}

local function set_args(vm, args)
  if type(args) ~= "table" then return end
  for i, v in ipairs(args) do
    if i > ARG_COUNT then break end
    if type(v) == "number" then vm.args[i - 1] = s16(v) end
  end
end

local function spawn_task(vm, name, priority, args, kind)
  local t = AnimTasks.spawn(name, priority, args or {}, vm)
  if not t then return nil end
  t._g4kind = kind
  local fn = t.func
  if fn then
    local ok, err = pcall(fn, t, vm)
    if not ok then
      print("[battle.anim] task " .. tostring(name) .. ": " .. tostring(err))
      AnimTasks.destroy(t)
    end
  end
  return t
end
AnimVm.spawnTask = spawn_task

-- pokefirered/src/battle_anim.c:349
local function pret_subpriority(vm, op)
  local raw = tonumber(op.subpriority) or 0
  local argVar = band(raw, 0x7F)
  if argVar >= 64 then argVar = argVar - 64 else argVar = -argVar end
  local id = (op.animBattler == "target") and vm:targetId() or vm:attackerId()
  local sub = AnimCoords.SUBPRIORITY[id] + argVar
  if sub < 3 then sub = 3 end
  return sub
end

local function animate_sprite(s)
  if s.active and s._g4anim then
    local ok, P = pcall(require, "src.core.game3.battle.anim_port.g4_pret")
    if ok and P then P.animate(s) end
  end
end
AnimVm.animateSprite = animate_sprite

local function run_createsprite(vm, op)
  local AnimTemplates = require("src.core.game3.battle.anim_templates")
  local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")

  local template = tostring(op.template or "")
  local info = AnimTemplates.get(template)
  local args = op.args or {}
  set_args(vm, args)
  local cbName = op.callback or (info and info.callback)
  local noGfx = op.noGfx or (info and info.noGfx)

  if noGfx and cbName and cbName ~= "" and AnimTasks.REGISTRY["_noGfx_" .. cbName] then
    spawn_task(vm, "_noGfx_" .. cbName, 2, args, "visual")
    return
  end
  local legacyTask = cbName and LEGACY_TASK_CB[cbName]
  if template == "gSimplePaletteBlendSpriteTemplate" then legacyTask = "BlendBattleAnimPal" end
  if template == "gComplexPaletteBlendSpriteTemplate" then legacyTask = "ComplexPaletteBlend" end
  if noGfx and not legacyTask and cbName and cbName ~= "" then
    local cb = AnimCallbacks[cbName]
    if not cb then legacyTask = cbName end
  end
  if legacyTask and not (AnimCallbacks._pretNoGfx and AnimCallbacks._pretNoGfx[cbName]) then
    if legacyTask == "HorizontalLunge" then
      spawn_task(vm, "HorizontalLunge", 2, { args[1] or 4, args[2] or 4 }, "visual")
    elseif legacyTask == "VerticalDip" then
      spawn_task(vm, "VerticalDip", 2, { args[1] or 4, args[2] or 4, args[3] or 0 }, "visual")
    else
      spawn_task(vm, legacyTask, 2, args, "visual")
    end
    return
  end

  local tag = op.tag or (info and info.tag) or "IMPACT"
  local img, tagInfo = tag_image(vm, tag)
  if not img and vm.getImpactFallback and not noGfx then
    img = vm:getImpactFallback()
  end

  local isCutting = (cbName == "CuttingSlice" or cbName == "AirCutterSlice")
  local isSlash = (cbName == "SlashSlice" or cbName == "FalseSwipeSlice" or cbName == "ClawSlash" or cbName == "FurySwipes")
  local isBite = (cbName == "Bite" or cbName == "Fang" or cbName == "SuperFang")
  local isProjectile = (
    cbName == "ThrowProjectile" or cbName == "BulletSeed"
    or cbName == "WaterBubbleProjectile" or cbName == "SludgeProjectile"
    or cbName == "BoneHitProjectile" or cbName == "TranslateAnimSpriteToTargetMonLocation"
    or cbName == "TranslateLinearSingleSineWave" or cbName == "PainSplitProjectile"
    or cbName == "RedHeartProjectile" or cbName == "ThrowMistBall"
  )
  local isTravelDiagonally = (
    cbName == "AnimTravelDiagonally" or cbName == "TravelDiagonally"
    or cbName == "AnimEmberFlare" or cbName == "EmberFlare"
    or cbName == "AnimBurnFlame" or cbName == "BurnFlame"
  )
  local isAttackerAlways = (
    isProjectile or cbName == "RoarNoiseLine" or cbName == "AnimFireRing"
    or cbName == "FireRing" or cbName == "AnimFireSpiralOutward"
    or cbName == "FireSpiralOutward" or cbName == "AnimFirePlume"
    or cbName == "FirePlume" or cbName == "AnimLargeFlame" or cbName == "LargeFlame"
    or cbName == "AnimEruptionLaunchRock" or cbName == "EruptionLaunchRock"
    or cbName == "AnimWillOWispOrb" or cbName == "WillOWispOrb"
  )
  local isTargetAlways = (
    isCutting or isBite or cbName == "AbsorptionOrb" or cbName == "BubbleEffect"
    or cbName == "ConfuseRayBallSpiral" or cbName == "ConstrictBinding"
    or cbName == "CrossChopHand" or cbName == "DizzyPunchDuck"
    or cbName == "Electricity" or cbName == "EllipticalGust"
    or cbName == "FlatterSpotlight" or cbName == "IceEffectParticle"
    or cbName == "InitIceBallParticle" or cbName == "ItemSteal"
    or cbName == "Lick" or cbName == "PresentHealParticle"
    or cbName == "SlidingKick" or cbName == "SmallDriftingBubbles"
    or cbName == "SpinningKickOrPunch" or cbName == "SporeParticle"
    or cbName == "Spotlight" or cbName == "StompFoot"
    or cbName == "TealAlert" or cbName == "WaterGunDroplet"
    or cbName == "WaveFromCenterOfTarget"
    or cbName == "AnimFireCross" or cbName == "FireCross"
    or cbName == "AnimFireSpread" or cbName == "FireSpread"
    or cbName == "AnimFireSpiralInward" or cbName == "FireSpiralInward"
    or cbName == "AnimSunlight" or cbName == "Sunlight"
    or cbName == "AnimWeatherBallDown" or cbName == "WeatherBallDown"
    or cbName == "AnimEruptionFallingRock" or cbName == "EruptionFallingRock"
    or cbName == "AnimWillOWispFire" or cbName == "WillOWispFire"
  )
  local isDynamicArg3 = (
    cbName == "SpriteOnMonPos" or cbName == "SpinningSparkle"
    or cbName == "HitSplatBasic" or cbName == "HitSplatPersistent"
    or cbName == "HitSplatRandom" or cbName == "CrossImpact"
    or cbName == "FlashingHitSplat" or cbName == "BasicFistOrFoot"
    or cbName == "RevengeScratch" or cbName == "ParticleInVortex"
    or cbName == "SmallBubblePair" or cbName == "WhirlwindLine"
  )
  local isDynamicArg1 = (isSlash or cbName == "EndureEnergy")

  local role = (op.animBattler == "target") and "target" or "attacker"
  local hFlip = false
  if isAttackerAlways then
    role = "attacker"
  elseif isTravelDiagonally then
    local battlerArg = args[6]
    if battlerArg == 1 or battlerArg == "target" then
      role = "target"
    else
      role = "attacker"
    end
  elseif isTargetAlways then
    role = "target"
  elseif isDynamicArg3 then
    local which = args[3]
    if which == 0 or which == "attacker" then
      role = "attacker"
    elseif which == 1 or which == 2 or which == "target" or (which and which ~= 0) then
      role = "target"
    end
  elseif isDynamicArg1 then
    if args[1] == 0 or args[1] == "attacker" then
      role = "attacker"
    else
      role = "target"
    end
  end
  local anchorId = (role == "attacker") and vm:attackerId() or vm:targetId()
  local anchorSide = (role == "attacker") and vm:attackerSide() or vm:targetSide()

  local cx, cy = vm:battlerCenter(anchorId)
  if isCutting and anchorSide == "player" then cy = cy + 8 end

  local ox, oy, dir = 0, 0, 0
  if isCutting then
    dir = tonumber(args[3]) or 0
    ox = (dir == 0 and 40 or -40)
    oy = tonumber(args[2]) or -32
    hFlip = (dir == 1)
  elseif isSlash then
    ox = vm:x(tonumber(args[2]) or 0)
    oy = tonumber(args[3]) or 0
  elseif cbName == "RoarNoiseLine" then
    local argX = tonumber(args[1]) or 24
    if vm.isReversed then argX = -argX end
    ox = argX
    oy = tonumber(args[2]) or 0
    dir = tonumber(args[3]) or 0
  else
    ox = vm:x(tonumber(args[1]) or 0)
    oy = tonumber(args[2]) or 0
  end

  local bw = op.w or (info and info.w) or 32
  local bh = op.h or (info and info.h) or 32
  if tag == "NOISE_LINE" or isCutting or isSlash or isBite then
    bw, bh = 32, 32
  end

  local subpri = pret_subpriority(vm, op)
  local sheetW = tagInfo and tagInfo.w
  if img and tagInfo and tagInfo.image == img then
    img, sheetW = AnimVm.sheetImage(vm, tag, bw)
  end

  local spr = AnimSprites.acquire({
    x = cx + ox,
    y = cy + oy,
    z = AnimSprites.Z.MID_FIELD,
    priority = 2,
    subpriority = subpri,
    hostId = anchorId,
    blendMode = "alpha",
    image = (not noGfx) and img or nil,
    w = bw,
    h = bh,
    hFlip = hFlip,
    template = template,
    tag = tag,
    callback = AnimCallbacks.get(cbName),
    palSlot = 0,
  })
  if not spr then return end
  spr._op = op
  spr._vm = vm
  spr._g4counted = true
  spr._pz = true
  spr.oamPriority = 2
  spr.subpriority = subpri
  spr._baseW = bw
  spr._baseH = bh
  spr._sheetW = sheetW
  spr._reversed = vm.isReversed
  spr._args = args
  spr._anchorSide = anchorSide
  spr._anchorId = anchorId
  spr._cbName = cbName
  if op.z or op.depth then
    spr._pz = nil
    spr.z = tonumber(op.z or op.depth)
  end
  for k, v in ipairs(args) do
    if k <= 8 then spr.data[k - 1] = v end
  end
  spr.data[0] = 0
  spr.data[1] = 0
  spr.data[2] = isCutting and dir or (cbName == "RoarNoiseLine" and dir or (tonumber(args[3]) or 0))
  local tx, ty = vm:battlerCenter(vm:targetId())
  local ax, ay = vm:battlerCenter(vm:attackerId())
  spr._attackerX, spr._attackerY = ax, ay
  if isProjectile then
    spr._targetX = tx + vm:x(tonumber(args[3]) or 0)
    spr._targetY = ty + (tonumber(args[4]) or 0)
  elseif isTravelDiagonally then
    spr._targetX = cx + vm:x(tonumber(args[3]) or 0)
    spr._targetY = cy + (tonumber(args[4]) or 0)
  else
    spr._targetX = tx
    spr._targetY = ty
  end
  spr._dx = spr._targetX - spr.x
  spr._dy = spr._targetY - spr.y

  spr.palTag = op.palTag
  if spr.callback then
    local ok, err = pcall(spr.callback, spr)
    if not ok then
      print("[battle.anim] sprite cb: " .. tostring(err))
      AnimSprites.release(spr)
      return
    end
  end
  animate_sprite(spr)
end

local function jump_label(vm, label)
  local sub = vm._pack and vm._pack.labels and vm._pack.labels[label]
  if sub then
    vm.script = sub
    vm.pc = 1
    return true
  end
  return false
end

-- pokefirered/src/battle_anim.c:1438
local function task_loop_and_play_se(t, vm)
  local cnt = t._counter
  t._counter = cnt + 1
  if cnt >= t._wait then
    t._counter = 0
    t._plays = band(t._plays - 1, 0xFF)
    play_se12(t._se, t._pan)
    if t._plays == 0 then AnimTasks.destroy(t) end
  end
end

-- pokefirered/src/battle_anim.c:1491
local function task_wait_and_play_se(t, vm)
  local w = t._wait
  t._wait = w - 1
  if w <= 0 then
    play_se12(t._se, t._pan)
    AnimTasks.destroy(t)
  end
end

-- pokefirered/src/battle_anim.c:1299
local function task_pan_to_target(t, vm)
  local cnt = t._counter
  t._counter = cnt + 1
  if cnt >= t._wait then
    t._counter = 0
    local pan = t._cur + t._inc
    t._cur = pan
    local done = false
    if t._inc == 0 then
      done = true
    elseif t._init < t._target then
      done = pan >= t._target
    else
      done = pan <= t._target
    end
    if done then
      pan = t._target
      AnimTasks.destroy(t)
    end
    se12_panpot(pan)
  end
end

AnimTasks.REGISTRY._G4LoopAndPlaySE = task_loop_and_play_se
AnimTasks.REGISTRY._G4WaitAndPlaySE = task_wait_and_play_se
AnimTasks.REGISTRY._G4PanFromInitialToTarget = task_pan_to_target

local function sound_task(vm, fnName, fields, callNow)
  local t = AnimTasks.spawn(fnName, 1, {}, vm)
  if not t then return nil end
  t._g4kind = "sound"
  for k, v in pairs(fields) do t[k] = v end
  if callNow then pcall(t.func, t, vm) end
  return t
end

-- pokefirered/src/battle_anim.c:1065
local function task_fade_to_bg(t, vm)
  local f = vm._bgFade
  if not f or f.task ~= t then
    AnimTasks.destroy(t)
    return
  end
  if f.state == 0 then
    f.from, f.to, f.y = 0, 16, 0
    f.fading = true
    f.state = 1
    return
  end
  if f.fading then return end
  if f.state == 1 then
    f.state = 2
    vm._bgFadeState = 2
  elseif f.state == 2 then
    if f.bgId == -1 then
      vm._animBgId = nil
      vm.bg3.x, vm.bg3.y = 0, 0
    else
      vm._animBgId = f.bgId
      AnimPal.bgLoad("bg", f.bgId)
    end
    f.from, f.to, f.y = 16, 0, 16
    f.fading = true
    f.state = 3
    return
  end
  if f.fading then return end
  if f.state == 3 then
    AnimTasks.destroy(t)
    vm._bgFade = nil
    vm._bgFadeState = 0
  end
end
AnimTasks.REGISTRY._G4FadeToBg = task_fade_to_bg

local function tick_bg_fade(vm)
  local f = vm._bgFade
  if not (f and f.fading) then return end
  if f.to > f.from then
    if f.y >= f.to then f.fading = false else f.y = f.y + 1 end
  else
    if f.y <= f.to then f.fading = false else f.y = f.y - 1 end
  end
end

local function start_bg_fade(vm, bgId)
  local t = AnimTasks.spawn("_G4FadeToBg", 5, {}, vm)
  if not t then return end
  t._g4kind = "aux"
  vm._bgFade = { task = t, state = 0, bgId = bgId, y = (vm._bgFade and vm._bgFade.y) or 0 }
  vm._bgFadeState = 1
end

-- pokefirered/src/battle_anim.c:786
local function task_clear_monbg(t, vm)
  t._n = (t._n or 0) + 1
  if t._n ~= 1 then
    local Anim = require("src.core.game3.battle.anim")
    for _, e in ipairs(t._ids or {}) do
      rawset(vm._monbg, e.id, nil)
      local p = Anim.present(e.id)
      if p and e.origZ then p.z = e.origZ end
      if p then p.monbg = false end
    end
    AnimTasks.destroy(t)
  end
end
AnimTasks.REGISTRY._G4ClearMonBg = task_clear_monbg

local function battler_from_monbg_token(vm, token)
  local s = tostring(token or "target")
  if s == "attacker" or s == "atk_partner" then return vm:attackerId() end
  return vm:targetId()
end

local function monbg_ids(vm, token)
  local id = battler_from_monbg_token(vm, token)
  local out = { id }
  local partner = AnimCoords.partner(id)
  if AnimCoords.spritePresent(nil, partner) then out[2] = partner end
  return out
end

local OPS = {}

OPS.loadspritegfx = function(vm, op)
  if not vm.loadedTags[tostring(op.tag or "")] then
    AnimPal.markLoaded(op.tag, false)
    AnimPal.markLoaded(op.tag, true)
  end
  vm.loadedTags[tostring(op.tag or "")] = true
  vm.framesToWait = 1
  vm._cbMode = "wait"
  return true
end

OPS.unloadspritegfx = function(vm, op)
  vm.loadedTags[tostring(op.tag or "")] = nil
  AnimPal.free(op.tag)
  return true
end

OPS.createsprite = function(vm, op)
  run_createsprite(vm, op)
  return true
end

OPS.createvisualtask = function(vm, op)
  set_args(vm, op.args)
  spawn_task(vm, op.task or op.name or "stub", op.priority or 2, op.args or {}, "visual")
  return true
end

OPS.createsoundtask = function(vm, op)
  set_args(vm, op.args)
  spawn_task(vm, op.task or op.name or "stub", 1, op.args or {}, "sound")
  return true
end

-- pokefirered/src/battle_anim.c:433
OPS.delay = function(vm, op)
  local n = tonumber(op.frames) or 0
  if n == 0 then n = -1 end
  vm.framesToWait = n
  vm._cbMode = "wait"
  return true
end

-- pokefirered/src/battle_anim.c:443
OPS.waitforvisualfinish = function(vm)
  vm._waitFrames = (vm._waitFrames or 0) + 1
  if vm:visualCount() == 0 or vm._waitFrames > WAIT_CAP then
    if vm._waitFrames > WAIT_CAP then print("[battle.anim] waitforvisualfinish cap") end
    vm._waitFrames = 0
    vm.framesToWait = 0
    return true
  end
  vm.framesToWait = 1
  return false
end

-- pokefirered/src/battle_anim.c:1526
OPS.waitsound = function(vm)
  if vm:soundCount() ~= 0 then
    vm._soundWait = 0
    vm.framesToWait = 1
    return false
  elseif se_playing() then
    vm._soundWait = (vm._soundWait or 0) + 1
    if vm._soundWait > 90 then
      vm._soundWait = 0
    else
      vm.framesToWait = 1
      return false
    end
  end
  vm._soundWait = 0
  vm.framesToWait = 0
  return true
end

OPS.waitanimation = function(vm)
  vm._waitFrames = (vm._waitFrames or 0) + 1
  if AnimSprites.activeCount() == 0 or vm._waitFrames > WAIT_CAP then
    vm._waitFrames = 0
    return true
  end
  vm.framesToWait = 1
  return false
end
OPS.waitsprites = OPS.waitanimation
OPS.waitforsprites = OPS.waitanimation

OPS.nop = function() return true end
OPS.nop2 = OPS.nop
OPS.jumpifcontest = OPS.nop
OPS.stopsound = function()
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and Audio and Audio.stopSe then pcall(Audio.stopSe) end
  return true
end
OPS.teamattack_moveback = OPS.nop
OPS.teamattack_movefwd = OPS.nop

-- pokefirered/src/battle_anim.c:464
OPS["end"] = function(vm)
  vm._endWait = (vm._endWait or 0) + 1
  local capped = vm._endWait > WAIT_CAP
  if not capped and (vm:visualCount() ~= 0 or vm:soundCount() ~= 0 or next(vm._monbg) ~= nil) then
    vm._soundWait = 0
    vm.framesToWait = 1
    return false
  end
  if not capped and se_playing() then
    vm._soundWait = (vm._soundWait or 0) + 1
    if vm._soundWait <= 90 then
      vm.framesToWait = 1
      return false
    end
  end
  if capped then print("[battle.anim] end wait cap") end
  vm._soundWait = 0
  vm._endWait = 0
  finish(vm)
  return "end"
end

OPS.playse = function(vm, op)
  play_se12(op.song or op.se or op.id or op[1], nil)
  return true
end

-- pokefirered/src/battle_anim.c:1240
OPS.playsewithpan = function(vm, op)
  play_se12(op.song or op.se or op.id or op[1], adjust_panning(vm, op.pan))
  return true
end

-- pokefirered/src/battle_anim.c:1252
OPS.setpan = function(vm, op)
  se12_panpot(adjust_panning(vm, op.pan))
  return true
end

-- pokefirered/src/battle_anim.c:1412
OPS.loopsewithpan = function(vm, op)
  local wait = band(tonumber(op.wait or op.frames) or 0, 0xFF)
  sound_task(vm, "_G4LoopAndPlaySE", {
    _se = op.song or op.se or op.id or op[1],
    _pan = adjust_panning(vm, op.pan),
    _wait = wait,
    _plays = band(tonumber(op.times or op.plays or op.count) or 1, 0xFF),
    _counter = wait,
  }, true)
  return true
end

-- pokefirered/src/battle_anim.c:1469
OPS.waitplaysewithpan = function(vm, op)
  sound_task(vm, "_G4WaitAndPlaySE", {
    _se = op.song or op.se or op.id or op[1],
    _pan = adjust_panning(vm, op.pan),
    _wait = band(tonumber(op.wait or op.frames) or 0, 0xFF),
  }, false)
  return true
end

-- pokefirered/src/battle_anim.c:1269
local function panse(vm, op, mode)
  local cur, target, inc
  local curArg = tonumber(op.pan) or 0
  local targetArg = tonumber(op.targetPan) or 0
  local incArg = tonumber(op.step) or 0
  if mode == "adjustnone" then
    cur, target, inc = curArg, targetArg, incArg
  elseif mode == "adjustall" then
    cur, target, inc = adjust_panning2(vm, curArg), adjust_panning2(vm, targetArg), adjust_panning2(vm, incArg)
  else
    cur = adjust_panning(vm, curArg)
    target = adjust_panning(vm, targetArg)
    inc = calc_pan_increment(cur, target, incArg)
  end
  sound_task(vm, "_G4PanFromInitialToTarget", {
    _init = cur, _target = target, _inc = inc,
    _wait = band(tonumber(op.wait) or 0, 0xFF), _cur = cur, _counter = 0,
  }, false)
  play_se12(op.song or op.se or op.id or op[1], cur)
  return true
end

OPS.panse = function(vm, op) return panse(vm, op, op.mode) end
OPS.panse_adjustnone = function(vm, op) return panse(vm, op, "adjustnone") end
OPS.panse_adjustall = function(vm, op) return panse(vm, op, "adjustall") end

-- pokefirered/src/battle_anim.c:531
OPS.monbg = function(vm, op)
  local Anim = require("src.core.game3.battle.anim")
  for _, id in ipairs(monbg_ids(vm, op.battler)) do
    local p = Anim.present(id)
    if p and p.visible ~= false then
      rawset(vm._monbg, id, true)
      vm._bgPrio[AnimCoords.BG_PRIORITY_RANK[id]] = 2
      if p._g4OrigZ == nil then p._g4OrigZ = p.z end
      p.z = AnimVm.Z.BEHIND
      p.monbg = true
    end
  end
  return true
end
OPS.monbg_static = function(vm, op)
  local id = battler_from_monbg_token(vm, op.battler)
  vm._bgPrio[AnimCoords.BG_PRIORITY_RANK[id]] = 2
  return true
end

-- pokefirered/src/battle_anim.c:754
OPS.clearmonbg = function(vm, op)
  local Anim = require("src.core.game3.battle.anim")
  local ids = {}
  for _, id in ipairs(monbg_ids(vm, op.battler)) do
    local p = Anim.present(id)
    local e = { id = id }
    e.origZ = p and p._g4OrigZ or ((AnimCoords.sideOf(id) == "player") and AnimVm.Z.PLAYER or AnimVm.Z.ENEMY)
    if rawget(vm._monbg, id) then ids[#ids + 1] = e end
    if p then p._g4OrigZ = nil end
  end
  local t = AnimTasks.spawn("_G4ClearMonBg", 5, {}, vm)
  if t then
    t._g4kind = "aux"
    t._ids = ids
  else
    for _, e in ipairs(ids) do rawset(vm._monbg, e.id, nil) end
  end
  return true
end
OPS.clearmonbg_static = OPS.nop

-- pokefirered/src/battle_anim.c:933
OPS.setalpha = function(vm, op)
  vm.bldAlpha = { eva = tonumber(op.eva) or 16, evb = tonumber(op.evb) or 0 }
  return true
end

OPS.setbldcnt = OPS.nop

OPS.blendoff = function(vm)
  vm.bldAlpha = nil
  return true
end

-- pokefirered/src/battle_anim.c:961
OPS.call = function(vm, op)
  local label = op.label or op.target
  local sub = vm._pack and vm._pack.labels and vm._pack.labels[label]
  if sub then
    vm._retScript, vm._retPc = vm.script, vm.pc + 1
    vm.script = sub
    vm.pc = 1
    return "jump"
  end
  return true
end

OPS["return"] = function(vm)
  if vm._retScript then
    vm.script = vm._retScript
    vm.pc = vm._retPc
    return "jump"
  end
  return true
end

OPS["goto"] = function(vm, op)
  if jump_label(vm, op.label or op.target) then return "jump" end
  return true
end

-- pokefirered/src/battle_anim.c:973
OPS.setarg = function(vm, op)
  local id = tonumber(op.argId) or 0
  if id >= 0 and id < ARG_COUNT then vm.args[id] = s16(tonumber(op.value) or 0) end
  return true
end

-- pokefirered/src/battle_anim.c:987
OPS.choosetwoturnanim = function(vm, op)
  local label = (band(vm._turn or 0, 1) == 1) and op.label2 or op.label1
  if jump_label(vm, label) then return "jump" end
  return true
end

-- pokefirered/src/battle_anim.c:995
OPS.jumpifmoveturn = function(vm, op)
  if (tonumber(op.turn) or 0) == (vm._turn or 0) then
    if jump_label(vm, op.label) then return "jump" end
  end
  return true
end

-- pokefirered/src/battle_anim.c:1554
OPS.jumpargeq = function(vm, op)
  local id = tonumber(op.argId) or 0
  if s16(tonumber(op.value) or 0) == (vm.args[id] or 0) then
    if jump_label(vm, op.label) then return "jump" end
  end
  return true
end

-- pokefirered/src/battle_anim.c:1032
OPS.fadetobg = function(vm, op)
  start_bg_fade(vm, tonumber(op.bg or op.bg1) or 0)
  return true
end

-- pokefirered/src/battle_anim.c:1045
OPS.fadetobgfromset = function(vm, op)
  local id = (vm:targetSide() == "player") and op.bg2 or op.bg1
  start_bg_fade(vm, tonumber(id) or 0)
  return true
end

-- pokefirered/src/battle_anim.c:1114
OPS.restorebg = function(vm)
  start_bg_fade(vm, -1)
  return true
end

-- pokefirered/src/battle_anim.c:1127
OPS.waitbgfadeout = function(vm)
  if vm._bgFadeState == 2 then
    vm.framesToWait = 0
    return true
  end
  vm.framesToWait = 1
  return false
end

OPS.waitbgfadein = function(vm)
  if (vm._bgFadeState or 0) == 0 then
    vm.framesToWait = 0
    return true
  end
  vm.framesToWait = 1
  return false
end

-- pokefirered/src/battle_anim.c:1153
OPS.changebg = function(vm, op)
  vm._animBgId = tonumber(op.bg) or 0
  AnimPal.bgLoad("bg", vm._animBgId)
  return true
end

-- pokefirered/src/battle_anim.c:1574
OPS.splitbgprio = function(vm, op)
  local id = (op.battler == "attacker") and vm:attackerId() or vm:targetId()
  if op.mode == "foes" and vm:attackerSide() == vm:targetSide() then return true end
  if op.mode == "all" or AnimCoords.BG_PRIORITY_RANK[id] == 2 then
    vm._bgPrio[1] = 1
    vm._bgPrio[2] = 2
  end
  return true
end
OPS.splitbgprio_all = function(vm)
  vm._bgPrio[1] = 1
  vm._bgPrio[2] = 2
  return true
end
OPS.splitbgprio_foes = function(vm, op)
  if vm:attackerSide() ~= vm:targetSide() then
    return OPS.splitbgprio(vm, { battler = op.battler })
  end
  return true
end

-- pokefirered/src/battle_anim.c:1631
local function set_visible(vm, op, visible)
  local Anim = require("src.core.game3.battle.anim")
  local id = vm:battlerId(op.battler or "attacker")
  local p = id and Anim.present(id)
  if p then p.visible = visible end
  return true
end
OPS.invisible = function(vm, op) return set_visible(vm, op, false) end
OPS.visible = function(vm, op) return set_visible(vm, op, true) end

local function run_op(vm, op)
  if type(op) ~= "table" then return true end
  local code = op.op or op[1]
  local fn = OPS[code]
  if not fn then return true end
  return fn(vm, op)
end

-- pokefirered/src/battle_anim.c:310
local function script_step(self)
  if not self.active then return end
  if self._cbMode == "wait" then
    -- pokefirered/src/battle_anim.c:297
    if self.framesToWait <= 0 then
      self._cbMode = "run"
      self.framesToWait = 0
    else
      self.framesToWait = self.framesToWait - 1
    end
    return
  end
  local guard = 0
  repeat
    guard = guard + 1
    local op = self.script and self.script[self.pc]
    if not op then
      finish(self)
      return
    end
    self.framesToWait = 0
    local r = run_op(self, op)
    if r == "end" then return end
    if r == true then
      self.pc = self.pc + 1
    elseif r == false then
      return
    end
  until self.framesToWait ~= 0 or not self.active or guard >= 2048
end

local function run_sprites(self)
  AnimSprites.init()
  local hooks = self._spriteHooks
  if hooks then
    for i = #hooks, 1, -1 do
      local ok, keep = pcall(hooks[i], self)
      if not ok or keep == false then table.remove(hooks, i) end
    end
  end
  AnimSprites.update()
end

function AnimVm:update(_dt)
  if not self.active then return end
  if self.headless then
    finish(self)
    return
  end
  if self._phase ~= "task" then script_step(self) end
  if not self.active then return end
  run_sprites(self)
  tick_bg_fade(self)
  AnimTasks.update(self)
  if self._phase == "task" then script_step(self) end
end

function AnimVm:addSpriteHook(fn)
  self._spriteHooks = self._spriteHooks or {}
  self._spriteHooks[#self._spriteHooks + 1] = fn
end

function AnimVm:tickFrames(n)
  for _ = 1, n or 1 do
    if not self.active then return end
    self:update(1 / 60)
  end
end

return AnimVm
