-- Fixed-pool battle anim particles (pret OAM sprite slots analogue).
-- No per-frame table.insert/nil churn — acquire overwrites, release clears active.

local AnimSprites = {}

AnimSprites.MAX = 128
AnimSprites.Z = {
  GLOBAL_BEHIND = 10,
  ENEMY_BEHIND  = 90,
  ENEMY_MON     = 100,
  ENEMY_FRONT   = 110,
  MID_FIELD     = 150,
  PLAYER_BEHIND = 190,
  PLAYER_MON    = 200,
  PLAYER_FRONT  = 210,
  GLOBAL_FRONT  = 900,
}

AnimSprites.RESET_KEYS = {
  customDraw = true, invisible = true, objBlend = true, palBlend = true,
  affineMode = true, aff = true, animNum = true, animCmdIndex = true,
  animDelayCounter = true, animLoopCounter = true, animEnded = true,
  animPaused = true, animBeginning = true, affineAnimPaused = true,
  affineAnimEnded = true, affineAnimBeginning = true, pretHFlip = true,
  pretVFlip = true, oamPriority = true, cb = true,
}

--- Slot-based dynamic Z calculation (supports 1v1 and 2v2 double battles).
function AnimSprites.slotZ(slot, layer)
  local slotId = 1
  if type(slot) == "number" then
    slotId = slot
  elseif slot == "player" or slot == "player_left" then
    slotId = 2
  elseif slot == "player_right" then
    slotId = 4
  elseif slot == "enemy_right" then
    slotId = 3
  else -- "enemy" or "enemy_left"
    slotId = 1
  end

  if layer == "behind" then
    return (slotId * 100) - 10
  elseif layer == "mon" then
    return (slotId * 100)
  elseif layer == "front" then
    return (slotId * 100) + 10
  elseif layer == "global_behind" then
    return 10
  elseif layer == "global_front" then
    return 900
  end
  return (slotId * 100) + 10
end

local function clear_slot(s)
  for k in pairs(s) do
    if k ~= "data" then s[k] = nil end
  end
  s.active = false
  s.x = 0
  s.y = 0
  s.ox = 0
  s.oy = 0
  s.z = AnimSprites.Z.MID_FIELD
  s.priority = 2
  s.subpriority = 0
  s.hostId = nil
  s.alpha = 1
  s.hFlip = false
  s.vFlip = false
  s.rotation = 0
  s.scaleX = 1
  s.scaleY = 1
  s.originX = nil
  s.originY = nil
  s.blendMode = "alpha" -- "alpha" | "add"
  s.visible = true
  s.tag = nil
  s.template = nil
  s.image = nil
  s.quad = nil
  s.w = 16
  s.h = 16
  s.callback = nil
  s.palSlot = 0 -- index into VM pal buffers
  s.monoTint = nil -- {r,g,b} fast path
  s.quadX = nil
  s.quadY = nil
  s._quadX = nil
  s._quadY = nil
  s._quadW = nil
  s._quadH = nil
  s._baseW = nil
  s._baseH = nil
  s._reversed = nil
  s._inited = nil
  for k in pairs(s) do
    if k ~= "data" and type(k) == "string" and (k:sub(1, 1) == "_" or AnimSprites.RESET_KEYS[k]) then
      s[k] = nil
    end
  end
  s.visible = true
  s.alpha = 1
  for i = 0, 7 do
    s.data[i] = 0
  end
end

local function new_slot()
  local s = { data = {} }
  for i = 0, 7 do s.data[i] = 0 end
  clear_slot(s)
  return s
end

function AnimSprites.init()
  if AnimSprites._pool then return end
  AnimSprites._pool = {}
  for i = 1, AnimSprites.MAX do
    AnimSprites._pool[i] = new_slot()
  end
  AnimSprites._overflowLogged = false
end

function AnimSprites.reset()
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    clear_slot(AnimSprites._pool[i])
  end
  AnimSprites._overflowLogged = false
end

--- Sweep and destroy any active particles bound to a fainted/switched host battler.
function AnimSprites.clearHost(hostId)
  if not hostId then return end
  AnimSprites.init()
  local AnimCoords = require("src.core.game3.battle.anim_coords")
  local want = AnimCoords.idOf(hostId)
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active and s.hostId ~= nil and (s.hostId == hostId or (want ~= nil and AnimCoords.idOf(s.hostId) == want)) then
      clear_slot(s)
    end
  end
end

--- Acquire a free slot. Returns sprite or nil if pool exhausted.
function AnimSprites.acquire(opts)
  AnimSprites.init()
  opts = opts or {}
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if not s.active then
      clear_slot(s)
      s.active = true
      s.x = opts.x or 0
      s.y = opts.y or 0
      s.z = opts.z or AnimSprites.Z.MID_FIELD
      s.priority = opts.priority or 2
      s.subpriority = opts.subpriority or 0
      s.hostId = opts.hostId
      s.tag = opts.tag
      s.template = opts.template
      s.image = opts.image
      s.quad = opts.quad
      s.w = opts.w or 16
      s.h = opts.h or 16
      s.hFlip = opts.hFlip and true or false
      s.vFlip = opts.vFlip and true or false
      s.rotation = opts.rotation or 0
      s.scaleX = opts.scaleX or 1
      s.scaleY = opts.scaleY or 1
      s.originX = opts.originX
      s.originY = opts.originY
      s.blendMode = opts.blendMode or "alpha"
      s.callback = opts.callback
      s.palSlot = opts.palSlot or 0
      s.monoTint = opts.monoTint
      if opts.data then
        for k, v in pairs(opts.data) do
          s.data[k] = v
        end
      end
      return s
    end
  end
  if not AnimSprites._overflowLogged then
    print("[battle.anim] sprite pool exhausted (" .. AnimSprites.MAX .. ")")
    AnimSprites._overflowLogged = true
  end
  return nil
end

function AnimSprites.release(sprite)
  if not sprite then return end
  clear_slot(sprite)
end

function AnimSprites.activeCount()
  AnimSprites.init()
  local n = 0
  for i = 1, AnimSprites.MAX do
    if AnimSprites._pool[i].active then n = n + 1 end
  end
  return n
end

function AnimSprites.forEachActive(fn)
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active then fn(s, i) end
  end
end

function AnimSprites.update()
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active and s.callback then
      local ok, err = pcall(s.callback, s)
      if not ok then
        print("[battle.anim] sprite cb: " .. tostring(err))
        AnimSprites.release(s)
      end
    end
    if s.active and s._g4anim and AnimSprites.animate then
      local ok, err = pcall(AnimSprites.animate, s)
      if not ok then print("[battle.anim] sprite anim: " .. tostring(err)) end
    end
  end
end

--- Collect active sprites sorted by z and subpriority, filtered by optional [minZ, maxZ] range.
function AnimSprites.sortedDrawList(out, minZ, maxZ)
  out = out or {}
  for i = #out, 1, -1 do out[i] = nil end
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active and s.visible then
      local z = s.z or AnimSprites.Z.MID_FIELD
      if (not minZ or z >= minZ) and (not maxZ or z <= maxZ) then
        out[#out + 1] = s
      end
    end
  end
  table.sort(out, function(a, b)
    local za = a.z or AnimSprites.Z.MID_FIELD
    local zb = b.z or AnimSprites.Z.MID_FIELD
    if za ~= zb then return za < zb end
    local sa = a.subpriority or 0
    local sb = b.subpriority or 0
    if sa ~= sb then return sa < sb end
    return false
  end)
  return out
end

return AnimSprites
