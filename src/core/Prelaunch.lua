local Prelaunch = {}
Prelaunch.__index = Prelaunch

Prelaunch.UPDATE_BUDGET = 25
Prelaunch.SYNC_BUDGET = 30
Prelaunch.MARKER = "launch_update.txt"

local function loveFs()
  local l = rawget(_G, "love")
  return l and l.filesystem or nil
end

local function consumeMarker(fs)
  if not (fs and fs.getInfo) then return false end
  local ok, info = pcall(fs.getInfo, Prelaunch.MARKER)
  if not ok or not info then return false end
  pcall(fs.remove, Prelaunch.MARKER)
  return true
end

local function updateAllowed(opts, fs)
  if opts.allowUpdate ~= nil then return opts.allowUpdate and true or false end
  local ok, Version = pcall(require, "src.core.Version")
  if ok and type(Version) == "table" and Version.isDev and Version.isDev() then
    return false
  end
  local okp, Platform = pcall(require, "src.core.Platform")
  if okp and type(Platform) == "table" and Platform.networkValidated
      and not Platform.networkValidated() then
    return false
  end
  -- Fused and unpacked packaged builds both update; a dev checkout does not.
  -- Boot owns the second half of that decision (the isDev check above is the
  -- first) so the boot gate and this one cannot disagree.
  if fs and fs.isFused and fs.isFused() then return true end
  local okb, Boot = pcall(require, "src.update.Boot")
  if okb and type(Boot) == "table"
      and type(Boot.canUpdateInPlace) == "function" then
    return Boot.canUpdateInPlace() and true or false
  end
  return false
end

local function syncSupported()
  local ok, HostShell = pcall(require, "src.core.HostShell")
  if not ok or type(HostShell) ~= "table"
      or type(HostShell.canHttpRequest) ~= "function" then
    return true
  end
  local asked, can = pcall(HostShell.canHttpRequest)
  return (not asked) or (can and true or false)
end

local function sharedEngine(opts)
  if opts.engine ~= nil then return opts.engine or nil end
  if not syncSupported() then return nil end
  local ok, SyncEngine = pcall(require, "src.sync.SyncEngine")
  if not ok or type(SyncEngine) ~= "table" then return nil end
  local got, eng = pcall(SyncEngine.shared)
  return (got and type(eng) == "table") and eng or nil
end

local function engineWanted(eng)
  if type(eng) ~= "table" then return false end
  if not (eng.state and eng.state.enabled) then return false end
  local ok, linked = pcall(eng.linked, eng)
  return (ok and linked) and true or false
end

function Prelaunch.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Prelaunch)
  self.version = opts.version
  self.done = opts.done
  self.fs = opts.fs
  if self.fs == nil then self.fs = loveFs() end
  if self.fs == false then self.fs = nil end
  self.restart = opts.restart or function()
    require("src.core.HostShell").restart()
  end

  local tasks = opts.tasks or {}
  local stages = {}
  local resumed = consumeMarker(self.fs)
  if tasks.update and not resumed and updateAllowed(opts, self.fs) then
    local ok, check = pcall(function()
      return opts.check or require("src.update.Check")
    end)
    if ok and type(check) == "table" then
      self.check = check
      stages[#stages + 1] = "update"
    end
  end
  if tasks.sync ~= false then
    local eng = sharedEngine(opts)
    if engineWanted(eng) then
      self.engine = eng
      stages[#stages + 1] = "sync"
    end
  end
  if #stages == 0 then return nil end

  self.stages = stages
  self.index = 0
  self.elapsed = 0
  self.status = ""
  self:_advance()
  return self
end

function Prelaunch:_finish(outcome)
  if self.finished then return end
  self.finished = true
  self.outcome = outcome
  if self.done then self.done(outcome) end
end

function Prelaunch:_advance()
  self.index = (self.index or 0) + 1
  self.elapsed = 0
  self.stage = self.stages[self.index]
  if self.stage == nil then return self:_finish("boot") end
  if self.stage == "update" then
    self.status = "Checking for updates..."
    pcall(self.check.start, true)
  elseif self.stage == "sync" then
    self.status = "Syncing saves..."
    pcall(self.engine.syncNow, self.engine)
  end
end

function Prelaunch:_updateStage()
  local ok, st = pcall(self.check.state)
  st = (ok and type(st) == "table") and st or nil
  local status = st and st.status or "error"
  if status == "available" then
    self.status = "Downloading update..."
    pcall(self.check.download)
  elseif status == "downloading" then
    self.status = string.format("Updating %d%%",
      math.floor((tonumber(st.progress) or 0) * 100))
  elseif status == "ready" then
    if self.fs and self.fs.write then
      pcall(self.fs.write, Prelaunch.MARKER, "1")
    end
    self.status = "Restarting..."
    pcall(self.restart)
    return self:_finish("restart")
  elseif status ~= "checking" then
    return self:_advance()
  end
  if self.elapsed >= Prelaunch.UPDATE_BUDGET then return self:_advance() end
end

function Prelaunch:_syncStage(dt)
  local eng = self.engine
  pcall(eng.update, eng, dt)
  if type(eng.status) == "string" and eng.status ~= "" then
    self.status = eng.status
  end
  if eng.phase == "conflict" then return self:_finish("launcher") end
  if eng.phase == "idle" or eng.phase == "error" then
    return self:_advance()
  end
  if self.elapsed >= Prelaunch.SYNC_BUDGET then return self:_advance() end
end

function Prelaunch:update(dt)
  if self.finished then return end
  dt = tonumber(dt) or 0
  self.elapsed = (self.elapsed or 0) + dt
  if self.stage == "update" then
    self:_updateStage()
  elseif self.stage == "sync" then
    self:_syncStage(dt)
  end
end

function Prelaunch:cancel()
  self:_finish("boot")
end

function Prelaunch:keypressed()
  self:cancel()
end

function Prelaunch:draw()
  local l = rawget(_G, "love")
  local g = l and l.graphics
  if not (g and g.printf) then return end
  g.clear(0, 0, 0, 1)
  g.setColor(1, 1, 1, 1)
  local w = g.getWidth and g.getWidth() or 0
  local h = g.getHeight and g.getHeight() or 0
  g.printf(tostring(self.status or ""), 0, math.floor(h / 2) - 12, w, "center")
  g.setColor(1, 1, 1, 0.55)
  g.printf("Press any button to skip", 0, math.floor(h / 2) + 8, w, "center")
  g.setColor(1, 1, 1, 1)
end

return Prelaunch
