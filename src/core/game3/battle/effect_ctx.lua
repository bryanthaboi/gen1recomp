-- Pre-allocated effect context stack (owned game3 copy).

local EffectCtx = {}

local MAX_DEPTH = 8
local pool = {}
for i = 1, MAX_DEPTH do pool[i] = {} end
local depth = 0

function EffectCtx.push(adapter, user, target, move, moveId, rng, opts)
  depth = depth + 1
  assert(depth <= MAX_DEPTH, "effect context stack overflow")
  local ctx = pool[depth]
  ctx.adapter = adapter
  ctx.user = user
  ctx.target = target
  ctx.move = move
  ctx.moveId = moveId
  ctx.rng = rng
  ctx.opts = opts
  return ctx
end

function EffectCtx.pop()
  assert(depth > 0, "effect context stack underflow")
  local ctx = pool[depth]
  ctx.adapter = nil
  ctx.user = nil
  ctx.target = nil
  ctx.move = nil
  ctx.moveId = nil
  ctx.rng = nil
  ctx.opts = nil
  depth = depth - 1
end

function EffectCtx.current()
  return depth > 0 and pool[depth] or nil
end

function EffectCtx.depth()
  return depth
end

function EffectCtx.reset()
  while depth > 0 do EffectCtx.pop() end
end

local OPTS_POOL_SIZE = 16
local optsPool = {}
for i = 1, OPTS_POOL_SIZE do optsPool[i] = {} end
local optsIndex = 0

function EffectCtx.borrowOpts(phase)
  optsIndex = optsIndex + 1
  if optsIndex > OPTS_POOL_SIZE then optsIndex = 1 end
  local o = optsPool[optsIndex]
  o.phase = phase
  return o
end

return EffectCtx
