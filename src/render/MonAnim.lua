-- ../pokecrystal/engine/gfx/pic_animation.asm:544 ConvertAndApplyBitmask
-- ../pokecrystal/engine/gfx/pic_animation.asm:356 PokeAnim_DoAnimScript

local MonAnim = {}
MonAnim.__index = MonAnim

-- .Sizes db 4, 5, 7: bitmask bytes for a 5x5, 6x6 and 7x7 pic.
-- ../pokecrystal/engine/gfx/pic_animation.asm:534
MonAnim.BITMASK_BYTES = { [5] = 4, [6] = 5, [7] = 7 }

-- ../pokecrystal/macros/scripts/pic_anims.asm:13-27
MonAnim.END = 0xff
MonAnim.SETREPEAT = 0xfe
MonAnim.DOREPEAT = 0xfd

-- .NextBit walks the row first, so bit i is row i % height, column i / height.
-- ../pokecrystal/engine/gfx/pic_animation.asm:746
function MonAnim.tileMap(data, frame)
  local tiles = data and data.tiles
  if not tiles then return nil end
  local count = tiles * tiles
  local out = {}
  for i = 1, count do out[i] = i - 1 end
  if not frame or frame <= 0 then return out end
  local row = data.frames and data.frames[frame]
  local mask = row and data.bitmasks and data.bitmasks[row.bitmask]
  if not (row and mask) then return nil end
  local cursor = 1
  for i = 0, count - 1 do
    local byte = mask[math.floor(i / 8) + 1] or 0
    if math.floor(byte / 2 ^ (i % 8)) % 2 == 1 then
      local id = row.tiles[cursor]
      if id == nil then return nil end
      out[i + 1] = id
      cursor = cursor + 1
    end
  end
  return out
end

-- PokeAnim_GetDuration: a * (1 + [wPokeAnimSpeed] / 16), truncated to 8 bits.
-- ../pokecrystal/engine/gfx/pic_animation.asm:413
function MonAnim.duration(param, speed)
  param = param % 256
  local scaled = math.floor(param * (speed or 0) / 16) % 256
  return (scaled + param) % 256
end

-- The PokeAnims programs less their cry commands; "wait" is SetWait's 18.
-- ../pokecrystal/engine/gfx/pic_animation.asm:69-77, :150-164
local SCENES = {
  battle = { "setup", "play" },
  battleSlow = { "setup2", "play" },
  menu = { "setup", "play", "wait", "idle", "play" },
}

MonAnim.SCENE_WAIT = 18

function MonAnim.scenes() return SCENES end

function MonAnim.new(data, scene)
  local steps = SCENES[scene or "battle"]
  if not (data and steps and data.play and #data.play > 0) then return nil end
  return setmetatable({
    data = data,
    steps = steps,
    step = 1,
    frame = 0,
    speed = 0,
    script = nil,
    pc = 1,
    repeatTimer = 0,
    waiting = false,
    waitCounter = 0,
    sceneWait = nil,
    done = false,
  }, MonAnim)
end

function MonAnim:finished() return self.done end

-- PokeAnim_GetFrame's `and a / ret z`: command 0 is the base picture.
-- ../pokecrystal/engine/gfx/pic_animation.asm:431-435
function MonAnim:currentFrame() return self.frame end

function MonAnim:beginScript(rows, speed)
  self.script = rows or {}
  self.speed = speed
  self.pc = 1
  self.repeatTimer = 0
  self.waiting = false
  self.waitCounter = 0
end

-- One tick of PokeAnim_DoAnimScript; true once the script has hit endanim.
-- ../pokecrystal/engine/gfx/pic_animation.asm:370-411
function MonAnim:runScript()
  if self.waiting then
    self.waitCounter = (self.waitCounter - 1) % 256
    if self.waitCounter == 0 then self.waiting = false end
    return false
  end
  for _ = 1, 256 do
    local row = self.script[self.pc]
    self.pc = self.pc + 1
    if row == nil then return true end
    local command = row[1]
    if command == MonAnim.END then
      return true
    elseif command == MonAnim.SETREPEAT then
      self.repeatTimer = row[2]
    elseif command == MonAnim.DOREPEAT then
      -- .DoRepeat returns on both `ret z` (:397-406).
      if self.repeatTimer == 0 then return false end
      self.repeatTimer = self.repeatTimer - 1
      if self.repeatTimer == 0 then return false end
      self.pc = row[2] + 1
    else
      self.frame = command
      self.waiting = true
      self.waitCounter = MonAnim.duration(row[2], self.speed)
      -- StartWaitAnim falls through into .WaitAnim (:383-388), so the frame
      -- it places is the frame the counter first ticks on.
      self.waitCounter = (self.waitCounter - 1) % 256
      if self.waitCounter == 0 then self.waiting = false end
      return false
    end
  end
  return true
end

-- One iteration of AnimateFrontpic's .loop: one scene command per frame.
-- ../pokecrystal/engine/gfx/pic_animation.asm:79-89
function MonAnim:update()
  if self.done then return end
  local step = self.steps[self.step]
  if step == nil then
    -- PokeAnim_Finish's DeinitFrames puts the base picture back (:224-228).
    self.frame = 0
    self.done = true
    return
  end
  if step == "setup" or step == "setup2" or step == "idle" then
    local rows = (step == "idle") and self.data.idle or self.data.play
    self:beginScript(rows, step == "setup2" and 4 or 0)
    self.step = self.step + 1
    return
  end
  if step == "wait" then
    self.sceneWait = (self.sceneWait or MonAnim.SCENE_WAIT) - 1
    if self.sceneWait <= 0 then
      self.sceneWait = nil
      self.step = self.step + 1
    end
    return
  end
  if self:runScript() then
    -- PokeAnim_Play redraws the base picture as the script ends (:196-205).
    self.frame = 0
    self.step = self.step + 1
  end
end

return MonAnim
