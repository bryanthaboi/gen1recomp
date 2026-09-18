-- Lightweight timed task chain for game3 (pret Task_* analogue).
-- Used by Oak intro beats (pokéball, shrink) and reusable from adapters.

local Task = {}

Task._list = {}
Task._nextId = 1

--- Spawn a task. fn(task, dt) → true when finished.
-- opts: { frames = N } auto-finishes after N frames if fn returns nil.
function Task.spawn(fn, opts)
  opts = opts or {}
  local id = Task._nextId
  Task._nextId = id + 1
  local t = {
    id = id,
    fn = fn,
    frames = 0,
    maxFrames = tonumber(opts.frames),
    data = opts.data or {},
    done = false,
    onDone = opts.onDone,
  }
  Task._list[#Task._list + 1] = t
  return t
end

function Task.cancel(id)
  for i = #Task._list, 1, -1 do
    if Task._list[i].id == id then
      table.remove(Task._list, i)
      return true
    end
  end
  return false
end

function Task.clear()
  Task._list = {}
end

function Task.busy()
  return #Task._list > 0
end

function Task.count()
  return #Task._list
end

function Task.update(dt)
  local i = 1
  while i <= #Task._list do
    local t = Task._list[i]
    t.frames = t.frames + 1
    local finished = false
    if t.fn then
      local ok, res = pcall(t.fn, t, dt)
      if ok and res == true then finished = true end
      if not ok then
        print("[game3.task] error: " .. tostring(res))
        finished = true
      end
    end
    if t.maxFrames and t.frames >= t.maxFrames then
      finished = true
    end
    if finished then
      t.done = true
      local cb = t.onDone
      table.remove(Task._list, i)
      if cb then pcall(cb, t) end
    else
      i = i + 1
    end
  end
end

--- Wait N frames then call done.
function Task.waitFrames(n, done)
  return Task.spawn(function(t)
    return t.frames >= (n or 1)
  end, { onDone = function() if done then done() end end })
end

--- Linear tween helper: writes t.data.u in 0..1 over frames.
function Task.tween(frames, onStep, done)
  frames = math.max(1, tonumber(frames) or 1)
  return Task.spawn(function(t)
    local u = math.min(1, t.frames / frames)
    if onStep then onStep(u, t) end
    return u >= 1
  end, { onDone = function() if done then done() end end })
end

return Task
