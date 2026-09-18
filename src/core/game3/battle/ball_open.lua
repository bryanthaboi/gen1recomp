local AnimCoords = require("src.core.game3.battle.anim_coords")

local BallOpen = {}

BallOpen.CACHE_SUB = "pokemon/battle/ball_open"

-- pokefirered/src/battle_anim_special.c:702
local ITEM_TO_BALL = {
  [1] = 4, [2] = 3, [3] = 1, [4] = 0, [5] = 2, [6] = 5,
  [7] = 6, [8] = 7, [9] = 8, [10] = 9, [11] = 10, [12] = 11,
}

-- pokefirered/src/battle_anim_special.c:149
local ANIMS = {
  [0] = { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 0, 1, true }, { 2, 1 }, { 1, 1 }, jump = 1 },
  [1] = { { 3, 1 } },
  [2] = { { 4, 1 } },
  [3] = { { 5, 1 } },
  [4] = { { 6, 4 }, { 7, 4 }, jump = 1 },
  [5] = { { 7, 4 } },
}

-- pokefirered/src/battle_anim_special.c:201
local ANIM_NUMS = { [0] = 0, 0, 0, 5, 1, 2, 2, 3, 5, 5, 4, 4 }

BallOpen._data = nil
BallOpen._image = nil
BallOpen._quads = {}
BallOpen._shader = nil

local function new_fade()
  return { active = false, y = 0, target = 0, yDec = false, toggle = 0,
    finishing = false, counter = 0, selected = false, bgY = 0,
    objSel = nil, color = nil, delay = 0, delayCounter = 0 }
end

function BallOpen.reset()
  BallOpen._sprites = {}
  BallOpen._particles = {}
  BallOpen._tasks = {}
  BallOpen._mon = AnimCoords.idTable()
  BallOpen._fade = new_fade()
end

BallOpen.reset()

function BallOpen.ballIdForItem(item)
  return ITEM_TO_BALL[tonumber(item) or 0] or 0
end

local function read_cache(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local c = Dataset.cache()
    local d = c and c.read and c:read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  return nil
end

local function cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  return (ok and Extract and Extract.CACHE_ROOT or "data/generated/gba") .. "/" .. BallOpen.CACHE_SUB
end

function BallOpen.setData(data, image)
  BallOpen._data = data
  BallOpen._image = image
  BallOpen._quads = {}
end

function BallOpen.data()
  if BallOpen._data == nil then
    BallOpen._data = false
    local src = read_cache(cache_root() .. "/manifest.lua")
    local chunk = src and load(src, "=ball_open", "t", {})
    local ok, t = false, nil
    if chunk then ok, t = pcall(chunk) end
    if ok and type(t) == "table" then BallOpen._data = t end
  end
  return BallOpen._data or nil
end

local function image()
  if BallOpen._image == nil then
    BallOpen._image = false
    local d = BallOpen.data()
    if d and love and love.image and love.graphics then
      local rgba = read_cache(cache_root() .. "/" .. (d.sheet or "particles.rgba"))
      local w, h = d.sheetW or 64, d.sheetH or 8
      if rgba and #rgba >= w * h * 4 then
        local ok, id = pcall(love.image.newImageData, w, h, "rgba8", rgba)
        if ok and id then
          local okI, img = pcall(love.graphics.newImage, id)
          if okI and img then
            img:setFilter("nearest", "nearest")
            BallOpen._image = img
          end
        end
      end
    end
  end
  return BallOpen._image or nil
end

-- pokefirered/src/trig.c:514
local function sin(index, amp)
  local d = BallOpen.data()
  local v = d and d.sine and d.sine[index + 1] or 0
  return math.floor(amp * v / 256)
end

-- pokefirered/src/trig.c:520
local function cos(index, amp)
  return sin(index + 64, amp)
end

BallOpen.sin = sin
BallOpen.cos = cos

-- pokefirered/src/blend_palette.c:16
function BallOpen.blend5(c, target, coeff)
  return c + math.floor((target - c) * coeff / 16)
end

-- pokefirered/src/palette.c:393
local function update_fade()
  local f = BallOpen._fade
  if not f.active then return end
  if f.finishing then
    if f.counter == 4 then
      f.active = false
      f.finishing = false
      f.counter = 0
    else
      f.counter = f.counter + 1
    end
    return
  end
  if f.toggle == 0 then
    if f.delayCounter < f.delay then
      f.delayCounter = f.delayCounter + 1
      return
    end
    f.delayCounter = 0
    if f.selected then f.bgY = f.y end
  elseif f.objSel then
    f.objSel.coeff = f.y
    f.objSel.r, f.objSel.g, f.objSel.b = f.color[1], f.color[2], f.color[3]
  end
  f.toggle = 1 - f.toggle
  if f.toggle == 0 then
    if f.y == f.target then
      f.selected = false
      f.objSel = nil
      f.finishing = true
    elseif not f.yDec then
      f.y = math.min(f.target, f.y + 2)
    else
      f.y = math.max(f.target, f.y - 2)
    end
  end
end

-- pokefirered/src/palette.c:151
local function begin_fade(startY, targetY, opts)
  local f = BallOpen._fade
  if f.active then return false end
  opts = opts or {}
  f.y = startY
  f.target = targetY
  f.active = true
  f.selected = opts.obj == nil
  f.objSel = opts.obj
  f.color = opts.color or { 31, 31, 31 }
  f.delay = opts.delay or 0
  f.delayCounter = f.delay
  f.yDec = not (startY < targetY)
  update_fade()
  return true
end

BallOpen.beginFade = begin_fade

-- pokefirered/src/sprite.c:905
local function animate(p)
  local cmds = (p.anims or ANIMS)[p.animNum] or ANIMS[0]
  local c
  if p.animBeginning then
    p.animBeginning = false
    p.animEnded = false
    p.cmd = 1
    c = cmds[1]
  elseif p.delay > 0 then
    if not p.animPaused then p.delay = p.delay - 1 end
    return
  elseif p.animPaused then
    return
  else
    local nextI = p.cmd + 1
    if cmds[nextI] then
      p.cmd = nextI
    elseif cmds.jump then
      p.cmd = cmds.jump
    else
      p.animEnded = true
      return
    end
    c = cmds[p.cmd]
  end
  p.frame = c[1]
  p.hFlip = c[3] == true
  p.delay = math.max(0, c[2] - 1)
end

BallOpen.animate = animate

local function spawn(task, cb, d, animNum)
  local p = {
    x = task.x, y = task.y, x2 = 0, y2 = 0,
    animNum = animNum or ANIM_NUMS[task.ballId] or 0, animBeginning = true,
    frame = 0, hFlip = false, delay = 0, cmd = 1,
    cb = cb, data = { [0] = 0, 0, 0, 0, 0, 0, 0, 0 },
  }
  for k, v in pairs(d or {}) do p.data[k] = v end
  local list = BallOpen._particles
  list[#list + 1] = p
  return p
end

local CB = {}

-- pokefirered/src/battle_anim_special.c:1492
function CB.poke1(p)
  if p.data[1] == 0 then
    p.cb = CB.poke2
  else
    p.data[1] = p.data[1] - 1
  end
end

-- pokefirered/src/battle_anim_special.c:1500
function CB.poke2(p)
  local d = p.data
  p.x2 = sin(d[0], d[1])
  p.y2 = cos(d[0], d[1])
  d[1] = d[1] + 2
  if d[1] == 50 then p.dead = true end
end

-- pokefirered/src/battle_anim_special.c:1693
function CB.fan(p)
  local d = p.data
  p.x2 = sin(d[0], d[1])
  p.y2 = cos(d[0], d[2])
  d[0] = (d[0] + d[4]) % 256
  d[1] = d[1] + d[5]
  d[2] = d[2] + d[6]
  d[3] = d[3] + 1
  if d[3] == 51 then p.dead = true end
end

-- pokefirered/src/battle_anim_special.c:1735
function CB.repeat_(p)
  local d = p.data
  p.x2 = sin(d[0], d[1])
  p.y2 = cos(d[0], sin(d[0], d[2]))
  d[0] = (d[0] + 6) % 256
  d[1] = d[1] + 1
  d[2] = d[2] + 1
  d[3] = d[3] + 1
  if d[3] == 51 then p.dead = true end
end

-- pokefirered/src/battle_anim_special.c:1823
function CB.premier(p)
  local d = p.data
  p.x2 = sin(d[0], d[1])
  p.y2 = cos(d[0], sin(d[0] % 64, d[2]))
  d[0] = (d[0] + 10) % 256
  d[1] = d[1] + 1
  d[2] = d[2] + 1
  d[3] = d[3] + 1
  if d[3] == 51 then p.dead = true end
end

local function fan_burst(task, count, step, d4, d5, d6)
  for i = 0, count - 1 do
    spawn(task, CB.fan, { [0] = i * step, [4] = d4, [5] = d5, [6] = d6 })
  end
end

local SPAWN = {}

-- pokefirered/src/battle_anim_special.c:1448
function SPAWN.poke(task)
  if task.data0 < 16 then
    local var0 = task.data0
    if var0 >= 8 then var0 = var0 - 8 end
    spawn(task, CB.poke1, { [0] = var0 * 32 })
    if task.data0 == 15 then return true end
  end
  task.data0 = task.data0 + 1
  return false
end

-- pokefirered/src/battle_anim_special.c:1648
function SPAWN.great(task)
  if task.data7 ~= 0 then
    task.data7 = task.data7 - 1
    return false
  end
  fan_burst(task, 8, 32, 8, 2, 2)
  task.data7 = 8
  task.data0 = task.data0 + 1
  return task.data0 == 2
end

-- pokefirered/src/battle_anim_special.c:1578
function SPAWN.safari(task)
  fan_burst(task, 8, 32, 4, 1, 1)
  return true
end

-- pokefirered/src/battle_anim_special.c:1613
function SPAWN.ultra(task)
  fan_burst(task, 10, 25, 5, 1, 1)
  return true
end

-- pokefirered/src/battle_anim_special.c:1746
function SPAWN.master(task)
  fan_burst(task, 8, 32, 8, 2, 1)
  fan_burst(task, 8, 32, 8, 1, 2)
  return true
end

-- pokefirered/src/battle_anim_special.c:1543
function SPAWN.dive(task)
  fan_burst(task, 8, 32, 10, 1, 2)
  return true
end

-- pokefirered/src/battle_anim_special.c:1704
function SPAWN.repeat_(task)
  for i = 0, 11 do
    spawn(task, CB.repeat_, { [0] = i * 21 })
  end
  return true
end

-- pokefirered/src/battle_anim_special.c:1509
function SPAWN.timer(task)
  fan_burst(task, 8, 32, 10, 2, 1)
  return true
end

-- pokefirered/src/battle_anim_special.c:1792
function SPAWN.premier(task)
  for i = 0, 7 do
    spawn(task, CB.premier, { [0] = i * 32 })
  end
  return true
end

-- pokefirered/src/battle_anim_special.c:217
local SPAWNERS = {
  [0] = SPAWN.poke, SPAWN.great, SPAWN.safari, SPAWN.ultra, SPAWN.master, SPAWN.safari,
  SPAWN.dive, SPAWN.ultra, SPAWN.repeat_, SPAWN.timer, SPAWN.great, SPAWN.premier,
}

-- pokefirered/src/battle_anim_special.c:1910
local function run_mon_fade(m)
  if m.state == "wait" then
    if not BallOpen._fade.active then
      begin_fade(16, 0)
      m.state = "step"
    end
    return false
  end
  if m.d2 <= 16 then
    m.coeff = m.d0
    m.d0 = m.d0 + m.d1
    m.d2 = m.d2 + 1
    return false
  end
  if m.state == "to" then
    -- pokefirered/src/battle_anim_special.c:1902
    if BallOpen._fade.active then return false end
    begin_fade(16, 0)
    m.hold = true
  end
  return true
end

-- pokefirered/src/pokeball.c:763
function BallOpen.start(side, x, y, ballItem, unfadeLater)
  side = AnimCoords.fixedId(side) or side
  local ballId = BallOpen.ballIdForItem(ballItem)
  -- pokefirered/src/battle_anim_special.c:1427
  local tasks = BallOpen._tasks
  tasks[#tasks + 1] = {
    kind = "particles", ballId = ballId,
    x = math.floor(tonumber(x) or 0) % 256,
    y = (math.floor(tonumber(y) or 0) - 5) % 256,
    data0 = 0, data7 = 0,
  }
  -- pokefirered/src/battle_anim_special.c:1865
  local m
  if unfadeLater == false then
    m = { kind = "mon", side = side, ballId = ballId, coeff = 0, d0 = 0, d1 = 1, d2 = 0, state = "to" }
  else
    m = { kind = "mon", side = side, ballId = ballId, coeff = 16, d0 = 16, d1 = -1, d2 = 0, state = "wait" }
  end
  BallOpen._mon[side] = m
  tasks[#tasks + 1] = m
  begin_fade(0, 16)
  return ballId
end

-- pokefirered/src/pokeball.c:1006
function BallOpen.startParticles(x, y, ballItem)
  local tasks = BallOpen._tasks
  tasks[#tasks + 1] = {
    kind = "particles", ballId = BallOpen.ballIdForItem(ballItem),
    x = math.floor(tonumber(x) or 0) % 256,
    y = (math.floor(tonumber(y) or 0) - 5) % 256,
    data0 = 0, data7 = 0,
  }
end

function BallOpen.addSprite(s)
  local list = BallOpen._sprites
  list[#list + 1] = s
  return s
end

function BallOpen.spawnSprite(x, y, animNum, cb)
  return spawn({ x = x, y = y, ballId = 0 }, cb, nil, animNum)
end

-- pokefirered/src/battle_main.c:1447
function BallOpen.tick()
  local sprites = BallOpen._sprites
  if #sprites > 0 then
    local keepS = {}
    for _, s in ipairs(sprites) do
      s.update(s)
      if not s.dead then keepS[#keepS + 1] = s end
    end
    BallOpen._sprites = keepS
  end
  local list = BallOpen._particles
  if #list > 0 then
    local keep = {}
    for _, p in ipairs(list) do
      p.cb(p)
      if not p.dead then
        animate(p)
        keep[#keep + 1] = p
      end
    end
    BallOpen._particles = keep
  end
  update_fade()
  local tasks = BallOpen._tasks
  if #tasks > 0 then
    local keep = {}
    for _, t in ipairs(tasks) do
      local done
      if t.kind == "particles" then
        done = SPAWNERS[t.ballId](t)
      else
        done = run_mon_fade(t)
        if done and not t.hold and BallOpen._mon[t.side] == t then BallOpen._mon[t.side] = nil end
      end
      if not done then keep[#keep + 1] = t end
    end
    local added = BallOpen._tasks
    for i = #tasks + 1, #added do keep[#keep + 1] = added[i] end
    BallOpen._tasks = keep
  end
end

function BallOpen.active()
  return #BallOpen._sprites > 0 or #BallOpen._particles > 0 or #BallOpen._tasks > 0 or BallOpen._fade.active
end

function BallOpen.particleCount()
  return #BallOpen._particles
end

function BallOpen.particles()
  return BallOpen._particles
end

function BallOpen.bgCoeff()
  return BallOpen._fade.bgY or 0
end

function BallOpen.fadeActive()
  return BallOpen._fade.active
end

function BallOpen.monBlend(side)
  local m = BallOpen._mon[AnimCoords.fixedId(side) or side]
  if not m or m.coeff <= 0 then return 0 end
  local d = BallOpen.data()
  local c = d and d.fadeColors and d.fadeColors[m.ballId + 1]
  if not c then return 0 end
  return m.coeff, c[1], c[2], c[3]
end

local SHADER_SRC = [[
extern float coeff;
extern vec3 target;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc) * color;
  vec3 c5 = floor(c.rgb * 31.0 + 0.5);
  vec3 o = c5 + floor((target - c5) * coeff / 16.0);
  return vec4(o / 31.0, c.a);
}
]]

function BallOpen.setBlendShader(coeff, r, g, b)
  if not (coeff and coeff > 0 and love and love.graphics and love.graphics.newShader) then
    return false
  end
  if BallOpen._shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER_SRC)
    BallOpen._shader = ok and sh or false
  end
  local sh = BallOpen._shader
  if not sh then return false end
  sh:send("coeff", coeff)
  sh:send("target", { r, g, b })
  love.graphics.setShader(sh)
  return true
end

function BallOpen.draw()
  local list = BallOpen._particles
  if #list == 0 or not (love and love.graphics) then return end
  local img = image()
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  for i = #list, 1, -1 do
    local p = list[i]
    if not p.animBeginning and not p.invisible then
      local q = BallOpen._quads[p.frame]
      if not q then
        local iw, ih = img:getDimensions()
        q = love.graphics.newQuad(p.frame * 8, 0, 8, 8, iw, ih)
        BallOpen._quads[p.frame] = q
      end
      local px, py = p.x + p.x2 - 4, p.y + p.y2 - 4
      if p.hFlip then
        love.graphics.draw(img, q, px + 8, py, 0, -1, 1)
      else
        love.graphics.draw(img, q, px, py)
      end
    end
  end
end

return BallOpen
