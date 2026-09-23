-- Game3 script VM (FRLG dialect).

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Ops = require("src.core.game3.scripting.ops_a")
local Adapters = require("src.core.game3.scripting.adapters")
local ModRuntime = require("src.mods.Runtime")

local Vm = {}
Vm.__index = Vm

function Vm.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Vm)
  self.ctx = Ctx.new(opts)
  self.store = opts.store or Flags.newStore()
  self.scripts = opts.scripts or {}
  self.text = opts.text or {}
  self.movements = opts.movements or {}
  self.adapters = opts.adapters or Adapters.stub(opts)
  for k, rows in pairs(opts.stdscripts or {}) do
    if not self.scripts[k] then
      self.scripts[k] = rows
    end
  end
  return self
end

function Vm:getText(key)
  local t = self.text[key]
  if not t and self.adapters.lookupText then
    t = self.adapters.lookupText(key)
  end
  return t
end

function Vm:setPc(listKey, index)
  self.ctx.pc = { listKey = listKey, index = index or 1 }
end

function Vm:_scriptEnded(completed)
  if not self._scriptKey then return end
  local key = self._scriptKey
  self._scriptKey = nil
  if ModRuntime.wants("script.ended") then
    ModRuntime.emit("script.ended", { ctx = Ctx.modCtx(self), completed = completed and true or false, key = key })
  end
end

function Vm:halt(aborted)
  local a = self.adapters
  local ctx = self.ctx
  if a and a.unfreezeLocal then
    for lid, snap in pairs(ctx.lockSnapshots or {}) do
      a.unfreezeLocal(lid, snap)
    end
  end
  Ctx.haltCleanup(self.ctx)
  self:_scriptEnded(not aborted)
end

function Vm:isRunning()
  return self.ctx.status == "running" or self.ctx.status == "waiting"
end

--- Stamp LAST_TALKED and VAR_FACING then start script.
function Vm:startTalk(scriptKey, localId, facing)
  Flags.setVar(self.store, self.ctx, Ctx.VAR_LAST_TALKED, localId or 0)
  Ctx.selectObject(self.ctx, localId) -- src/field_control_avatar.c:426
  if facing then
    Flags.setVar(self.store, self.ctx, Ctx.VAR_FACING, facing)
  end
  return self:start(scriptKey, facing)
end

function Vm:start(scriptKey, facing)
  if not self.scripts[scriptKey] then
    if self.adapters.log then
      self.adapters.log("[game3] missing script " .. tostring(scriptKey))
    end
    return false
  end
  if self._scriptKey then self:_scriptEnded(false) end
  self.ctx.mode = "bytecode"
  self.ctx.status = "running"
  self.ctx.stack = {}
  self.ctx.stringVars = { [1] = "", [2] = "", [3] = "" }
  -- specialVars wiped at halt; fresh talk starts clean for RESULT etc. but
  -- LAST_TALKED already stamped by startTalk, and VAR_FACING passed or read from adapters.
  local keptLast = self.ctx.specialVars[Ctx.VAR_LAST_TALKED]
  local keptFacing = facing or self.ctx.specialVars[Ctx.VAR_FACING]
  if not keptFacing and self.adapters and self.adapters.getPlayerFacing then
    local f = self.adapters.getPlayerFacing()
    if f then
      local dirs = { down = 1, up = 2, left = 3, right = 4 }
      keptFacing = dirs[f] or tonumber(f)
    end
  end
  Ctx.wipeSpecial(self.ctx)
  if keptLast then
    self.ctx.specialVars[Ctx.VAR_LAST_TALKED] = keptLast
  end
  if keptFacing then
    self.ctx.specialVars[Ctx.VAR_FACING] = keptFacing
  end
  self:setPc(scriptKey, 1)
  self._scriptKey = scriptKey
  if ModRuntime.wants("script.started") then
    ModRuntime.emit("script.started", { ctx = Ctx.modCtx(self), key = scriptKey })
  end
  self:resume()
  return true
end

function Vm:resume()
  local ctx = self.ctx
  local guard = 0
  while ctx.status == "running" or ctx.status == "waiting" do
    guard = guard + 1
    if guard > 10000 then
      self.adapters.log("[game3] runaway script")
      self:halt(true)
      return
    end
    if ctx.mode == "native" then
      if ctx.nativePoll and ctx.nativePoll() then
        ctx.mode = "bytecode"
        ctx.status = "running"
        ctx.nativePoll = nil
      else
        return -- yield frame
      end
    end
    local pc = ctx.pc
    if not pc then
      self:halt()
      return
    end
    local list = self.scripts[pc.listKey]
    if not list then
      self.adapters.log("[game3] bad list " .. tostring(pc.listKey))
      self:halt(true)
      return
    end
    local row = list[pc.index]
    if not row then
      self:halt()
      return
    end
    -- Advance PC before op (unless op jumps).
    pc.index = pc.index + 1
    local yield = Ops.dispatch(self, row)
    if yield then
      if ctx.status == "shutdown" then return end
      if ctx.mode == "native" then return end
      -- end/halt already cleaned
      if not self:isRunning() then return end
    end
  end
end

function Vm:tick()
  if self.ctx.status == "waiting" or self.ctx.status == "running" then
    self:resume()
  end
end

return Vm
