local Itemfinder = {}

local SE_ITEMFINDER = 65
local CENTER_X, CENTER_Y = 120, 76
local STAR_ANIM = 4

Itemfinder._task = nil
Itemfinder._sprites = {}

local function is_hidden(ev)
  return ev.type == "hidden_item" or ev.kind == 7
end

-- pokefirered/src/itemfinder.c:383
local function register_if_closer(t, dx, dy)
  if not t.found then
    t.itemX, t.itemY, t.found = dx, dy, true
    return
  end
  local dx2, dy2 = math.abs(t.itemX), math.abs(t.itemY)
  local dx3, dy3 = math.abs(dx), math.abs(dy)
  if dx2 + dy2 > dx3 + dy3 then
    t.itemX, t.itemY = dx, dy
  elseif dx2 + dy2 == dx3 + dy3 and (dy2 > dy3 or (dy2 == dy3 and t.itemY < dy)) then
    t.itemX, t.itemY = dx, dy
  end
end

-- pokefirered/src/itemfinder.c:287
local function hidden_item_at_pos(events, x, y, flagSet)
  for _, ev in ipairs(events or {}) do
    if is_hidden(ev) and ev.x == x and ev.y == y then
      return not ev.underfoot and not flagSet(ev)
    end
  end
  return false
end

local function neighbor(neighbors, a, b)
  return neighbors and (neighbors[a] or neighbors[b])
end

local function layout_size(def)
  local L = def and def.midLayout
  if L then return L.width or 0, L.height or 0 end
  return (tonumber(def and def.width) or 0) * 2, (tonumber(def and def.height) or 0) * 2
end

-- pokefirered/src/fieldmap.c:761, src/itemfinder.c:312
local function connected_hidden_item(opts, lx, ly)
  local curW, curH = opts.width, opts.height
  local n = opts.neighbors
  local conn, cx, cy
  if ly < 0 then
    conn = neighbor(n, "north", "up")
    if conn then
      local w, h = layout_size(conn.def)
      local off = tonumber(conn.offset) or 0
      if lx - off >= 0 and lx - off < w then cx, cy = lx - off, h + ly end
    end
  end
  if not cx and ly >= curH then
    conn = neighbor(n, "south", "down")
    if conn then
      local w = layout_size(conn.def)
      local off = tonumber(conn.offset) or 0
      if lx - off >= 0 and lx - off < w then cx, cy = lx - off, ly - curH end
    end
  end
  if not cx and lx < 0 then
    conn = neighbor(n, "west", "left")
    if conn then
      local w, h = layout_size(conn.def)
      local off = tonumber(conn.offset) or 0
      if ly - off >= 0 and ly - off < h then cx, cy = w + lx, ly - off end
    end
  end
  if not cx and lx >= curW then
    conn = neighbor(n, "east", "right")
    if conn then
      local _, h = layout_size(conn.def)
      local off = tonumber(conn.offset) or 0
      if ly - off >= 0 and ly - off < h then cx, cy = lx - curW, ly - off end
    end
  end
  if not cx then return false end
  return hidden_item_at_pos(opts.eventsFor(conn.map or conn.mapId), cx, cy, opts.flagSet)
end

-- pokefirered/src/itemfinder.c:202
function Itemfinder.scan(opts)
  local t = { found = false, itemX = 0, itemY = 0 }
  for _, ev in ipairs(opts.events or {}) do
    if is_hidden(ev) and not opts.flagSet(ev) then
      local dx, dy = ev.x - opts.px, ev.y - opts.py
      if ev.underfoot then
        if dx == 0 and dy == 0 then
          -- pokefirered/src/itemfinder.c:241
          return { underfoot = true, item = ev, itemX = 0, itemY = 0, dings = 3 }
        end
      elseif dx >= -7 and dx <= 7 and dy >= -5 and dy <= 5 then
        register_if_closer(t, dx, dy)
      end
    end
  end
  -- pokefirered/src/itemfinder.c:354
  if opts.width and opts.height and opts.eventsFor then
    for x = opts.px - 7, opts.px + 7 do
      for y = opts.py - 5, opts.py + 5 do
        if x < 0 or x >= opts.width or y < 0 or y >= opts.height then
          if connected_hidden_item(opts, x, y) then
            register_if_closer(t, x - opts.px, y - opts.py)
          end
        end
      end
    end
  end
  if not t.found then return nil end
  -- pokefirered/src/itemfinder.c:255
  local ax, ay = math.abs(t.itemX), math.abs(t.itemY)
  local dings = 4
  if not (t.itemX == 0 and t.itemY == 0) then
    if ax > ay then
      if ax > 3 then dings = 2 end
    elseif ay > 3 then
      dings = 2
    end
  end
  return { underfoot = false, itemX = t.itemX, itemY = t.itemY, dings = dings }
end

-- pokefirered/src/itemfinder.c:434, :535
local AFFINE_TURN = { left = 0, down = 0x40, right = 0x80, up = 0xC0 }
local function arrow_motion(itemX, itemY, facing)
  if itemX == 0 and itemY == 0 then
    if facing == "left" then return -100, 0, AFFINE_TURN.left end
    if facing == "up" then return 0, -100, AFFINE_TURN.up end
    if facing == "right" then return 100, 0, AFFINE_TURN.right end
    return 0, 100, AFFINE_TURN.down
  end
  local ax, ay = math.abs(itemX), math.abs(itemY)
  if ax > ay then
    if itemX < 0 then return -100, 0, AFFINE_TURN.left end
    return 100, 0, AFFINE_TURN.right
  end
  if itemY < 0 then return 0, -100, AFFINE_TURN.up end
  return 0, 100, AFFINE_TURN.down
end

local function spawn(anim, dx, dy, turn)
  local s = { anim = anim, dx = dx, dy = dy, curX = 0, curY = 0, x = CENTER_X, y = CENTER_Y, turn = turn or 0 }
  Itemfinder._sprites[#Itemfinder._sprites + 1] = s
  return s
end

-- pokefirered/src/itemfinder.c:595, :632
local function step_sprites()
  local keep = {}
  for _, s in ipairs(Itemfinder._sprites) do
    s.curX = s.curX + s.dx
    s.curY = s.curY + s.dy
    s.x = CENTER_X + math.floor(s.curX / 256)
    s.y = CENTER_Y + math.floor(s.curY / 256)
    if not (s.x <= 104 or s.x > 132 or s.y <= 60 or s.y > 88) then
      keep[#keep + 1] = s
    end
  end
  Itemfinder._sprites = keep
end

-- pokefirered/src/itemfinder.c:131
function Itemfinder.start(task)
  Itemfinder._sprites = {}
  task.timer = 0
  task.dingNum = 0
  task.remaining = task.result.dings
  task.phase = "dings"
  Itemfinder._task = task
end

function Itemfinder.isActive()
  return Itemfinder._task ~= nil
end

function Itemfinder.sprites()
  return Itemfinder._sprites
end

-- pokefirered/src/itemfinder.c:158, :181
function Itemfinder.update()
  Itemfinder.runTask()
  step_sprites()
end

function Itemfinder.runTask()
  local t = Itemfinder._task
  if not (t and t.phase == "dings") then return end
  if t.timer % 25 == 0 then
    if t.remaining == 0 then
      t.phase = "message"
      local key = t.result.underfoot and "gText_ItemfinderShakingWildly" or "gText_ItemfinderResponding"
      t.onMessage(key, function()
        Itemfinder._task = nil
        Itemfinder._sprites = {}
        t.onDone()
      end)
      return
    end
    local Audio = require("src.core.game3.audio")
    Audio.playSe(SE_ITEMFINDER)
    if t.result.underfoot then
      spawn(STAR_ANIM, 0, -100, 0)
    else
      local dx, dy, turn = arrow_motion(t.result.itemX, t.result.itemY, t.facing)
      spawn(t.dingNum, dx, dy, turn)
    end
    t.dingNum = t.dingNum + 1
    t.remaining = t.remaining - 1
  end
  t.timer = t.timer + 1
end

function Itemfinder.draw()
  if #Itemfinder._sprites == 0 then return end
  local FieldEffects = require("src.core.game3.field_effects")
  local sheet = FieldEffects.loadSheet("itemfinder_arrow_star", 16, 16, 5)
  if not sheet then return end
  love.graphics.setColor(1, 1, 1, 1)
  for _, s in ipairs(Itemfinder._sprites) do
    local q = sheet.quads[s.anim]
    if q then
      love.graphics.draw(sheet.image, q, s.x, s.y, -s.turn * math.pi / 128, 1, 1, 8, 8)
    end
  end
end

function Itemfinder.reset()
  Itemfinder._task = nil
  Itemfinder._sprites = {}
end

return Itemfinder
