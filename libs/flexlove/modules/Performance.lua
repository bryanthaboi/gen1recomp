---@class Performance
---@field enabled boolean
---@field hudEnabled boolean
---@field hudToggleKey string
---@field hudPosition {x: number, y: number}
---@field warningThresholdMs number
---@field criticalThresholdMs number
---@field logToConsole boolean
---@field logWarnings boolean
---@field warningsEnabled boolean
---@field _ErrorHandler table?
---@field _timers table
---@field _metrics table
---@field _lastMetricsCleanup number
---@field _frameMetrics table
---@field _memoryMetrics table
---@field _warnings table
---@field _lastFrameStart number?
---@field _shownWarnings table
---@field _memoryProfiler table
local Performance = {}
Performance.__index = Performance

---@type Performance|nil
local instance = nil

local METRICS_CLEANUP_INTERVAL = 30
local METRICS_RETENTION_TIME = 10
local MAX_METRICS_COUNT = 500
local CORE_METRICS = { frame = true, layout = true, render = true }

---@param config {enabled?: boolean, hudEnabled?: boolean, hudToggleKey?: string, hudPosition?: {x: number, y: number}, warningThresholdMs?: number, criticalThresholdMs?: number, logToConsole?: boolean, logWarnings?: boolean, warningsEnabled?: boolean, memoryProfiling?: boolean}?
---@param deps {ErrorHandler: ErrorHandler}
---@return Performance
function Performance.init(config, deps)
  if instance == nil then
    local self = setmetatable({}, Performance)

    -- Configuration
    self.enabled = config and config.enabled or false
    self.hudEnabled = config and config.hudEnabled or false
    self.hudToggleKey = config and config.hudToggleKey or "f3"
    self.hudPosition = config and config.hudPosition or { x = 10, y = 10 }
    self.warningThresholdMs = config and config.warningThresholdMs or 13.0
    self.criticalThresholdMs = config and config.criticalThresholdMs or 16.67
    self.logToConsole = config and config.logToConsole or false
    self.logWarnings = config and config.logWarnings or true
    self.warningsEnabled = config and config.warningsEnabled or true

    self._timers = {}
    self._metrics = {}
    self._lastMetricsCleanup = 0
    self._frameMetrics = {
      frameCount = 0,
      totalTime = 0,
      lastFrameTime = 0,
      minFrameTime = math.huge,
      maxFrameTime = 0,
      fps = 0,
      lastFpsUpdate = 0,
      fpsUpdateInterval = 0.5,
    }
    self._memoryMetrics = {
      current = 0,
      peak = 0,
      gcCount = 0,
      lastGcCheck = 0,
    }
    self._warnings = {}
    self._lastFrameStart = nil
    self._shownWarnings = {}
    self._memoryProfiler = {
      enabled = config and config.memoryProfiling or false,
      sampleInterval = 60,
      framesSinceLastSample = 0,
      samples = {},
      maxSamples = 20,
      monitoredTables = {},
    }
    self._ErrorHandler = deps and deps.ErrorHandler
    instance = self
  end
  return instance
end

--- Toggle HUD visibility
function Performance:toggleHUD()
  self.hudEnabled = not self.hudEnabled
end

function Performance:startTimer(name)
  if not self.enabled then
    return
  end
  self._timers[name] = love.timer.getTime()
end

function Performance:stopTimer(name)
  if not self.enabled then
    return nil
  end

  local startTime = self._timers[name]
  if not startTime then
    -- Silently return nil if timer wasn't started
    -- This can happen legitimately when Performance is toggled mid-frame
    -- or when layout functions have early returns
    return nil
  end

  local elapsed = (love.timer.getTime() - startTime) * 1000
  self._timers[name] = nil

  -- Update metrics
  if not self._metrics[name] then
    self._metrics[name] = {
      total = 0,
      count = 0,
      min = math.huge,
      max = 0,
      average = 0,
      lastUsed = love.timer.getTime(),
    }
  end

  local m = self._metrics[name]
  m.total = m.total + elapsed
  m.count = m.count + 1
  m.min = math.min(m.min, elapsed)
  m.max = math.max(m.max, elapsed)
  m.average = m.total / m.count
  m.lastUsed = love.timer.getTime()

  -- Check for warnings
  if elapsed > self.criticalThresholdMs then
    self:_addWarning(name, elapsed, "critical")
  elseif elapsed > self.warningThresholdMs then
    self:_addWarning(name, elapsed, "warning")
  end

  if self.logToConsole then
    -- Use ErrorHandler if available, otherwise fall back to print
    if self._ErrorHandler and self._ErrorHandler.warn then
      self._ErrorHandler:warn("Performance", "PERF_001", {
        metric = name,
        elapsed = string.format("%.3fms", elapsed),
      })
    else
      print(string.format("[Performance] %s: %.3fms", name, elapsed))
    end
  end

  return elapsed
end

--- Update with actual delta time from LÖVE (call from love.update)
---@param dt number Delta time in seconds
function Performance:updateDeltaTime(dt)
  if not self.enabled then
    return
  end
  local now = love.timer.getTime()
  if now - self._frameMetrics.lastFpsUpdate >= self._frameMetrics.fpsUpdateInterval then
    if dt > 0 then
      self._frameMetrics.fps = math.floor(1 / dt + 0.5)
    end
    self._frameMetrics.lastFpsUpdate = now
  end
end

--- Start frame timing (call at beginning of frame)
function Performance:startFrame()
  if not self.enabled then
    return
  end
  self._lastFrameStart = love.timer.getTime()
  self:_updateMemory()
end

function Performance:endFrame()
  if not self.enabled or not self._lastFrameStart then
    return
  end

  local now = love.timer.getTime()
  local frameTime = (now - self._lastFrameStart) * 1000

  self._frameMetrics.lastFrameTime = frameTime
  self._frameMetrics.totalTime = self._frameMetrics.totalTime + frameTime
  self._frameMetrics.frameCount = self._frameMetrics.frameCount + 1
  self._frameMetrics.minFrameTime = math.min(self._frameMetrics.minFrameTime, frameTime)
  self._frameMetrics.maxFrameTime = math.max(self._frameMetrics.maxFrameTime, frameTime)

  if frameTime > self.criticalThresholdMs then
    self:_addWarning("frame", frameTime, "critical")
  end

  self:updateMemoryProfiling()

  -- Periodic metrics cleanup
  if now - self._lastMetricsCleanup >= METRICS_CLEANUP_INTERVAL then
    local cleanupTime = now - METRICS_RETENTION_TIME
    for name, data in pairs(self._metrics) do
      if not CORE_METRICS[name] and data.lastUsed and data.lastUsed < cleanupTime then
        self._metrics[name] = nil
      end
    end
    self._lastMetricsCleanup = now
  end

  -- Enforce max metrics limit
  local metricsCount = 0
  for _ in pairs(self._metrics) do
    metricsCount = metricsCount + 1
  end

  if metricsCount > MAX_METRICS_COUNT then
    local sortedMetrics = {}
    for name, data in pairs(self._metrics) do
      if not CORE_METRICS[name] then
        table.insert(sortedMetrics, { name = name, lastUsed = data.lastUsed or 0 })
      end
    end

    table.sort(sortedMetrics, function(a, b)
      return a.lastUsed < b.lastUsed
    end)

    local toRemove = metricsCount - MAX_METRICS_COUNT
    for i = 1, math.min(toRemove, #sortedMetrics) do
      self._metrics[sortedMetrics[i].name] = nil
    end
  end
end

--- Update memory metrics
function Performance:_updateMemory()
  if not self.enabled then
    return
  end

  local memKb = collectgarbage("count")
  self._memoryMetrics.current = memKb
  self._memoryMetrics.peak = math.max(self._memoryMetrics.peak, memKb)

  local now = love.timer.getTime()
  if now - self._memoryMetrics.lastGcCheck >= 1.0 then
    self._memoryMetrics.gcCount = self._memoryMetrics.gcCount + 1
    self._memoryMetrics.lastGcCheck = now
  end
end

--- Add a performance warning (private)
--- @param name string Metric name
--- @param value number Metric value
--- @param level "warning"|"critical" Warning level
function Performance:_addWarning(name, value, level)
  if not self.logWarnings then
    return
  end

  local warning = {
    name = name,
    value = value,
    level = level,
    time = love.timer.getTime(),
  }

  table.insert(self._warnings, warning)

  if #self._warnings > 100 then
    table.remove(self._warnings, 1)
  end

  if self.logToConsole or self.warningsEnabled then
    local warningKey = name .. "_" .. level
    local lastWarningTime = self._shownWarnings[warningKey] or 0
    local now = love.timer.getTime()

    if now - lastWarningTime >= 60 then
      if self._ErrorHandler and self._ErrorHandler.warn then
        local code = level == "critical" and "PERF_002" or "PERF_001"

        self._ErrorHandler:warn("Performance", code, {
          metric = name,
          value = string.format("%.2fms", value),
          threshold = level == "critical" and self.criticalThresholdMs or self.warningThresholdMs,
        })
      end

      self._shownWarnings[warningKey] = now
    end
  end
end

--- Render performance HUD
--- @param x number? X position (default: 10)
--- @param y number? Y position (default: 10)
function Performance:renderHUD(x, y)
  if not self.hudEnabled then
    return
  end

  x = x or self.hudPosition.x
  y = y or self.hudPosition.y

  self:_updateMemory()

  local fm = self._frameMetrics
  local mm = self._memoryMetrics

  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.rectangle("fill", x, y, 300, 220)

  love.graphics.setColor(1, 1, 1, 1)
  local lineHeight = 18
  local currentY = y + 10

  -- FPS
  local fpsColor = { 1, 1, 1 }
  if fm.lastFrameTime > self.criticalThresholdMs then
    fpsColor = { 1, 0, 0 }
  elseif fm.lastFrameTime > self.warningThresholdMs then
    fpsColor = { 1, 1, 0 }
  end
  love.graphics.setColor(fpsColor)
  love.graphics.print(string.format("FPS: %d (%.2fms)", fm.fps, fm.lastFrameTime), x + 10, currentY)
  currentY = currentY + lineHeight

  love.graphics.setColor(1, 1, 1, 1)
  local avgFrame = fm.frameCount > 0 and fm.totalTime / fm.frameCount or 0
  love.graphics.print(string.format("Avg Frame: %.2fms", avgFrame), x + 10, currentY)
  currentY = currentY + lineHeight
  love.graphics.print(string.format("Min/Max: %.2f/%.2fms", fm.minFrameTime, fm.maxFrameTime), x + 10, currentY)
  currentY = currentY + lineHeight

  local currentMb = mm.current / 1024
  local peakMb = mm.peak / 1024
  love.graphics.print(string.format("Memory: %.2f MB (peak: %.2f MB)", currentMb, peakMb), x + 10, currentY)
  currentY = currentY + lineHeight

  local metricsCount = 0
  for _ in pairs(self._metrics) do
    metricsCount = metricsCount + 1
  end
  local metricsColor = metricsCount > MAX_METRICS_COUNT * 0.8 and { 1, 0.5, 0 } or { 1, 1, 1 }
  love.graphics.setColor(metricsColor)
  love.graphics.print(string.format("Metrics: %d/%d", metricsCount, MAX_METRICS_COUNT), x + 10, currentY)
  currentY = currentY + lineHeight + 5

  -- Top timings
  love.graphics.setColor(1, 1, 1, 1)
  local sortedMetrics = {}
  for name, data in pairs(self._metrics) do
    table.insert(sortedMetrics, { name = name, average = data.average })
  end
  table.sort(sortedMetrics, function(a, b)
    return a.average > b.average
  end)

  love.graphics.print("Top Timings:", x + 10, currentY)
  currentY = currentY + lineHeight

  for i = 1, math.min(5, #sortedMetrics) do
    local m = sortedMetrics[i]
    love.graphics.print(string.format("  %s: %.3fms", m.name, m.average), x + 10, currentY)
    currentY = currentY + lineHeight
  end

  if #self._warnings > 0 then
    love.graphics.setColor(1, 0.5, 0, 1)
    love.graphics.print(string.format("Warnings: %d", #self._warnings), x + 10, currentY)
  end
end

--- Handle keyboard input for HUD toggle
--- @param key string Key pressed
function Performance:keypressed(key)
  if key == self.hudToggleKey then
    self:toggleHUD()
  end
end

--- Log a performance warning (only once per warning key)
--- @param warningKey string Unique key for this warning type
--- @param module string Module name (e.g., "LayoutEngine", "Element")
--- @param message string Warning message
--- @param details table? Additional details
--- @param suggestion string? Optimization suggestion
function Performance:logWarning(warningKey, module, message, details, suggestion)
  if not self.warningsEnabled then
    return
  end

  if self._shownWarnings[warningKey] then
    return
  end

  self._shownWarnings[warningKey] = true

  local count = 0
  for _ in pairs(self._shownWarnings) do
    count = count + 1
  end
  if count > 1000 then
    self._shownWarnings = { [warningKey] = true }
  end

  if self._ErrorHandler and self._ErrorHandler.warn then
    self._ErrorHandler:warn(module, "PERF_001", details or {})
  end
end

--- Track a counter metric (increments per frame)
--- @param name string Counter name
--- @param value number? Value to add (default: 1)
function Performance:incrementCounter(name, value)
  if not self.enabled then
    return
  end

  value = value or 1

  if not self._metrics[name] then
    self._metrics[name] = {
      total = 0,
      count = 0,
      min = math.huge,
      max = 0,
      average = 0,
      frameValue = 0,
      lastUsed = love.timer.getTime(),
    }
  end

  local m = self._metrics[name]
  m.frameValue = (m.frameValue or 0) + value
  m.lastUsed = love.timer.getTime()
end

--- Reset frame counters (call at end of frame)
function Performance:resetFrameCounters()
  if not self.enabled then
    return
  end

  local now = love.timer.getTime()
  local toRemove = {}

  for name, data in pairs(self._metrics) do
    if data.frameValue then
      if data.frameValue > 0 then
        data.total = data.total + data.frameValue
        data.count = data.count + 1
        data.min = math.min(data.min, data.frameValue)
        data.max = math.max(data.max, data.frameValue)
        data.average = data.total / data.count
        data.lastUsed = now
      end

      data.frameValue = 0

      if data.count == 0 and not CORE_METRICS[name] then
        table.insert(toRemove, name)
      end
    end
  end

  for _, name in ipairs(toRemove) do
    self._metrics[name] = nil
  end
end

--- Register a table for memory leak monitoring
--- @param name string Friendly name for the table
--- @param tableRef table Reference to the table to monitor
function Performance:registerTableForMonitoring(name, tableRef)
  self._memoryProfiler.monitoredTables[name] = tableRef
end

function Performance:_sampleMemory()
  local sample = {
    time = love.timer.getTime(),
    memory = collectgarbage("count") / 1024, -- MB
    tableSizes = {},
  }
  local function getTableSize(tbl)
    local count = 0
    for _ in pairs(tbl) do
      count = count + 1
    end
    return count
  end

  for name, tableRef in pairs(self._memoryProfiler.monitoredTables) do
    sample.tableSizes[name] = getTableSize(tableRef)
  end

  table.insert(self._memoryProfiler.samples, sample)

  -- Keep only maxSamples
  if #self._memoryProfiler.samples > self._memoryProfiler.maxSamples then
    table.remove(self._memoryProfiler.samples, 1)
  end

  -- Check for memory leaks (consistent growth)
  if #self._memoryProfiler.samples >= 5 then
    for name, _ in pairs(self._memoryProfiler.monitoredTables) do
      local sizes = {}
      for i = math.max(1, #self._memoryProfiler.samples - 4), #self._memoryProfiler.samples do
        table.insert(sizes, self._memoryProfiler.samples[i].tableSizes[name])
      end

      -- Check if table is consistently growing
      local growing = true
      for i = 2, #sizes do
        if sizes[i] <= sizes[i - 1] then
          growing = false
          break
        end
      end

      if growing and sizes[#sizes] > sizes[1] * 1.5 then
        self:_addWarning("memory_leak", sizes[#sizes], "warning")

        if not self._shownWarnings[name] then
          local message = string.format("Table '%s' growing consistently", name)
          if self._ErrorHandler and self._ErrorHandler.warn then
            self._ErrorHandler:warn("Performance", "MEM_001", {
              table = name,
              initialSize = sizes[1],
              currentSize = sizes[#sizes],
              growthPercent = math.floor(((sizes[#sizes] / sizes[1]) - 1) * 100),
            })
          end

          self._shownWarnings[name] = true
        end
      elseif not growing then
        self._shownWarnings[name] = nil
      end
    end
  end
end

--- Update memory profiling (call from endFrame)
function Performance:updateMemoryProfiling()
  if not self._memoryProfiler.enabled then
    return
  end

  self._memoryProfiler.framesSinceLastSample = self._memoryProfiler.framesSinceLastSample + 1

  if self._memoryProfiler.framesSinceLastSample >= self._memoryProfiler.sampleInterval then
    self:_sampleMemory()
    self._memoryProfiler.framesSinceLastSample = 0
  end
end

return Performance
