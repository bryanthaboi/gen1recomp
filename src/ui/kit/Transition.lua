local Transition = {}

Transition.reduceMotion = false
Transition.armed = false

Transition.DURATIONS = {
  ["in"] = 0.12,
  out = 0.09,
  tab = 0.18,
  push = 0.16,
  pop = 0.16,
}

Transition.LAYERS = { "tabs", "online", "modal" }
Transition.PASSIVE = { "toast" }

local ALL = {}
for i = 1, #Transition.LAYERS do ALL[#ALL + 1] = Transition.LAYERS[i] end
for i = 1, #Transition.PASSIVE do ALL[#ALL + 1] = Transition.PASSIVE[i] end

local layers = {}
for i = 1, #ALL do
  layers[ALL[i]] = {
    active = false, kind = nil, dir = 1,
    t0 = 0, dur = 0, p = 1,
    from = nil, fromAt = nil, to = nil,
  }
end

local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return 0
end
Transition.now = now

local function ease(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local u = 1 - t
  return 1 - u * u * u
end
Transition.ease = ease

function Transition.update(t)
  t = t or now()
  for i = 1, #ALL do
    local L = layers[ALL[i]]
    if L.active then
      local raw = 1
      if L.dur > 0 then raw = (t - L.t0) / L.dur end
      if raw >= 1 then
        L.active, L.p = false, 1
      elseif raw <= 0 then
        L.p = 0
      else
        L.p = ease(raw)
      end
    end
  end
end

function Transition.start(layer, kind, opts)
  local L = layers[layer]
  if not L then return false end
  L.kind = kind
  L.dir = (opts and opts.dir) or 1
  L.from = opts and opts.from or nil
  L.fromAt = opts and opts.fromAt or nil
  L.to = opts and opts.to or nil
  local dur = (opts and opts.duration) or Transition.DURATIONS[kind] or 0.15
  if Transition.reduceMotion or not Transition.armed or dur <= 0 then
    L.active, L.p, L.dur, L.t0 = false, 1, 0, 0
    return false
  end
  L.active, L.p, L.dur, L.t0 = true, 0, dur, now()
  return true
end

function Transition.get(layer)
  local L = layers[layer]
  if L and L.active then return L end
  return nil
end

function Transition.progress(layer)
  local L = layers[layer]
  if not L or not L.active then return 1 end
  return L.p
end

function Transition.kind(layer)
  local L = layers[layer]
  if L and L.active then return L.kind end
  return nil
end

function Transition.dir(layer)
  local L = layers[layer]
  if L and L.active then return L.dir end
  return 0
end

function Transition.active(layer)
  if layer then
    local L = layers[layer]
    return (L and L.active) == true
  end
  for i = 1, #Transition.LAYERS do
    if layers[Transition.LAYERS[i]].active then return true end
  end
  return false
end

function Transition.clear(layer)
  local L = layers[layer]
  if not L then return false end
  L.active, L.p, L.dur, L.t0 = false, 1, 0, 0
  L.kind, L.from, L.fromAt, L.to = nil, nil, nil, nil
  return true
end

function Transition.reset()
  for i = 1, #ALL do
    Transition.clear(ALL[i])
  end
end

return Transition
