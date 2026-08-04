---@class MemoryScanner
---@field _StateManager table
---@field _Context table
---@field _ImageCache table
---@field _ErrorHandler table
local MemoryScanner = {}

---Initialize MemoryScanner with dependencies
---@param deps {StateManager: table, Context: table, ImageCache: table, ErrorHandler: table}
function MemoryScanner.init(deps)
  MemoryScanner._StateManager = deps.StateManager
  MemoryScanner._Context = deps.Context
  MemoryScanner._ImageCache = deps.ImageCache
  MemoryScanner._ErrorHandler = deps.ErrorHandler
end

---Count items in a table
---@param tbl table
---@return number
local function countTable(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end

---Calculate memory size estimate for a table (recursive)
---@param tbl table
---@param visited table? Tracking table to prevent circular references
---@param depth number? Current recursion depth
---@return number bytes Estimated memory usage in bytes
local function estimateTableSize(tbl, visited, depth)
  if type(tbl) ~= "table" then
    return 0
  end

  visited = visited or {}
  depth = depth or 0

  -- Limit recursion depth to prevent stack overflow
  if depth > 10 then
    return 0
  end

  -- Check for circular references
  if visited[tbl] then
    return 0
  end
  visited[tbl] = true

  local size = 40 -- Base table overhead (approximate)

  for k, v in pairs(tbl) do
    -- Key size
    if type(k) == "string" then
      size = size + #k + 24 -- String overhead
    elseif type(k) == "number" then
      size = size + 8
    else
      size = size + 8 -- Reference
    end

    -- Value size
    if type(v) == "string" then
      size = size + #v + 24
    elseif type(v) == "number" then
      size = size + 8
    elseif type(v) == "boolean" then
      size = size + 4
    elseif type(v) == "table" then
      size = size + estimateTableSize(v, visited, depth + 1)
    elseif type(v) == "function" then
      size = size + 16 -- Function reference
    else
      size = size + 8 -- Other references
    end
  end

  return size
end

---Scan StateManager for memory issues
---@return table report Detailed report of StateManager memory usage
function MemoryScanner.scanStateManager()
  local report = {
    stateCount = 0,
    stateStoreSize = 0,
    metadataSize = 0,
    callSiteCounterSize = 0,
    orphanedStates = {},
    staleStates = {},
    largeStates = {},
    issues = {},
  }

  if not MemoryScanner._StateManager then
    table.insert(report.issues, {
      severity = "error",
      message = "StateManager not initialized",
    })
    return report
  end

  local internal = MemoryScanner._StateManager._getInternalState()
  local stateStore = internal.stateStore
  local stateMetadata = internal.stateMetadata
  local callSiteCounters = internal.callSiteCounters
  local currentFrame = MemoryScanner._StateManager.getFrameNumber()

  -- Count states
  report.stateCount = countTable(stateStore)

  -- Estimate sizes
  report.stateStoreSize = estimateTableSize(stateStore)
  report.metadataSize = estimateTableSize(stateMetadata)
  report.callSiteCounterSize = estimateTableSize(callSiteCounters)

  -- Check for orphaned states (metadata without state)
  for id, _ in pairs(stateMetadata) do
    if not stateStore[id] then
      table.insert(report.orphanedStates, id)
    end
  end

  -- Check for stale states (not accessed in many frames)
  local staleThreshold = 120 -- 2 seconds at 60fps
  for id, meta in pairs(stateMetadata) do
    local framesSinceAccess = currentFrame - meta.lastFrame
    if framesSinceAccess > staleThreshold then
      table.insert(report.staleStates, {
        id = id,
        framesSinceAccess = framesSinceAccess,
        createdFrame = meta.createdFrame,
        accessCount = meta.accessCount,
      })
    end
  end

  -- Check for large states (may indicate memory bloat)
  for id, state in pairs(stateStore) do
    local stateSize = estimateTableSize(state)
    if stateSize > 1024 then -- More than 1KB
      table.insert(report.largeStates, {
        id = id,
        size = stateSize,
        keyCount = countTable(state),
      })
    end
  end

  -- Check callSiteCounters (should be near 0 after frame cleanup)
  local callSiteCount = countTable(callSiteCounters)
  if callSiteCount > 100 then
    table.insert(report.issues, {
      severity = "warning",
      message = string.format("callSiteCounters has %d entries (expected near 0)", callSiteCount),
      suggestion = "incrementFrame() may not be called properly, or counters aren't being reset",
    })
  end

  -- Check for excessive state count
  if report.stateCount > 500 then
    table.insert(report.issues, {
      severity = "warning",
      message = string.format("High state count: %d states", report.stateCount),
      suggestion = "Consider reducing element count or implementing more aggressive cleanup",
    })
  end

  -- Check for orphaned states
  if #report.orphanedStates > 0 then
    table.insert(report.issues, {
      severity = "error",
      message = string.format("Found %d orphaned states (metadata without state)", #report.orphanedStates),
      suggestion = "This indicates a bug in state management - metadata should be cleaned up with state",
    })
  end

  -- Check for stale states
  if #report.staleStates > 10 then
    table.insert(report.issues, {
      severity = "warning",
      message = string.format("Found %d stale states (not accessed in 2+ seconds)", #report.staleStates),
      suggestion = "Cleanup may not be aggressive enough - consider reducing stateRetentionFrames",
    })
  end

  return report
end

---Scan Context for memory issues
---@return table report Detailed report of Context memory usage
function MemoryScanner.scanContext()
  local report = {
    topElementCount = 0,
    zIndexElementCount = 0,
    frameElementCount = 0,
    issues = {},
  }

  if not MemoryScanner._Context then
    table.insert(report.issues, {
      severity = "error",
      message = "Context not initialized",
    })
    return report
  end

  -- Count elements
  report.topElementCount = #MemoryScanner._Context.topElements
  report.zIndexElementCount = #MemoryScanner._Context._zIndexOrderedElements
  report.frameElementCount = #MemoryScanner._Context._currentFrameElements

  -- Check for stale z-index elements (should be cleared each frame)
  if MemoryScanner._Context.isImmediateMode() then
    -- In immediate mode, _zIndexOrderedElements should be cleared at frame start
    -- If it has elements outside of frame rendering, that's a leak
    if not MemoryScanner._Context._frameStarted and report.zIndexElementCount > 0 then
      table.insert(report.issues, {
        severity = "warning",
        message = string.format("Z-index array has %d elements outside of frame", report.zIndexElementCount),
        suggestion = "clearFrameElements() may not be called properly in beginFrame()",
      })
    end
  end

  -- Check for excessive element count
  if report.topElementCount > 100 then
    table.insert(report.issues, {
      severity = "info",
      message = string.format("High top-level element count: %d", report.topElementCount),
      suggestion = "Consider consolidating elements or using fewer top-level containers",
    })
  end

  return report
end

---Scan ImageCache for memory issues
---@return table report Detailed report of ImageCache memory usage
function MemoryScanner.scanImageCache()
  local report = {
    imageCount = 0,
    estimatedMemory = 0,
    issues = {},
  }

  if not MemoryScanner._ImageCache then
    table.insert(report.issues, {
      severity = "error",
      message = "ImageCache not initialized",
    })
    return report
  end

  local stats = MemoryScanner._ImageCache.getStats()
  report.imageCount = stats.count
  report.estimatedMemory = stats.memoryEstimate

  -- Check for excessive memory usage (>100MB)
  if report.estimatedMemory > 100 * 1024 * 1024 then
    table.insert(report.issues, {
      severity = "warning",
      message = string.format("ImageCache using ~%.2f MB", report.estimatedMemory / 1024 / 1024),
      suggestion = "Consider implementing cache eviction or clearing unused images",
    })
  end

  -- Check for excessive image count
  if report.imageCount > 50 then
    table.insert(report.issues, {
      severity = "info",
      message = string.format("ImageCache has %d images", report.imageCount),
      suggestion = "Review if all cached images are necessary",
    })
  end

  return report
end

---Check if a circular reference is intentional (parent-child, module, or metatable)
---@param path string The current path where circular ref was detected
---@param originalPath string The original path where the table was first seen
---@return boolean True if this is an intentional circular reference
local function isIntentionalCircularReference(path, originalPath)
  -- Pattern 1: child.parent points back to parent
  -- Example: "topElements.1.children.1.parent" -> "topElements.1"
  if path:match("%.parent$") then
    local parentPath = path:match("^(.+)%.children%.[^.]+%.parent$")
    if parentPath == originalPath then
      return true
    end
  end

  -- Pattern 2: parent.children[n] points to child, child points back somewhere in parent tree
  -- Example: "topElements.1" -> "topElements.1.children.1.parent"
  if originalPath:match("%.parent$") then
    local childParentPath = originalPath:match("^(.+)%.children%.[^.]+%.parent$")
    if childParentPath == path then
      return true
    end
  end

  -- Pattern 3: Check for nested parent-child cycles
  -- child.children[n].parent -> child
  local segments = {}
  for segment in path:gmatch("[^.]+") do
    table.insert(segments, segment)
  end

  -- Look for .children.N.parent pattern
  for i = 1, #segments - 2 do
    if segments[i] == "children" and segments[i + 2] == "parent" then
      -- Reconstruct path without the .children.N.parent suffix
      local reconstructedPath = table.concat(segments, ".", 1, i - 1)
      if reconstructedPath == originalPath then
        return true
      end
    end
  end

  -- Pattern 4: Metatable __index self-references (modules)
  -- Example: "element._renderer._Theme.__index" -> "element._renderer._Theme"
  if path:match("%.__index$") then
    local basePath = path:match("^(.+)%.__index$")
    if basePath == originalPath then
      return true
    end
  end

  -- Pattern 5: Shared module references (elements sharing same module instances)
  -- Example: Multiple elements referencing _utils, _Theme, _Blur, etc.
  -- These start with _ and are typically modules
  local pathModuleName = path:match("%.(_[%w]+)%.")
  local originalModuleName = originalPath:match("%.(_[%w]+)%.")

  if pathModuleName and originalModuleName then
    -- If both paths reference the same internal module (starting with _), it's intentional
    if pathModuleName == originalModuleName then
      return true
    end
  end

  -- Pattern 6: Shared Color/Transform objects between elements
  -- These are value objects that can be safely shared
  if path:match("Color") and originalPath:match("Color") then
    return true
  end
  if path:match("Transform") and originalPath:match("Transform") then
    return true
  end

  -- Pattern 7: LayoutEngine holding reference to its element
  -- Example: "element._layoutEngine.element" -> "element"
  if path:match("%._layoutEngine%.element$") then
    local elementPath = path:match("^(.+)%._layoutEngine%.element$")
    if elementPath == originalPath then
      return true
    end
  end

  -- Pattern 8: Renderer holding references to element properties
  -- Example: "element._renderer.cornerRadius" -> "element.cornerRadius"
  if path:match("%._renderer%.") then
    local rendererBasePath = path:match("^(.+)%._renderer%.")
    local originalBasePath = originalPath:match("^(.+)%.")
    if rendererBasePath == originalBasePath then
      return true
    end
  end

  -- Pattern 9: Context reference from layout engine (shared singleton)
  -- Example: "element._layoutEngine._Context.topElements" -> "topElements"
  if path:match("%._layoutEngine%._Context%.") and originalPath == "topElements" then
    return true
  end

  return false
end

---Detect circular references in a table
---@param tbl table Table to check
---@param path string? Current path (for reporting)
---@param visited table? Tracking table
---@return table[] circularRefs Array of circular reference paths
---@return table[] intentionalRefs Array of intentional parent-child refs
local function detectCircularReferences(tbl, path, visited)
  if type(tbl) ~= "table" then
    return {}, {}
  end

  path = path or "root"
  visited = visited or {}
  local circularRefs = {}
  local intentionalRefs = {}

  -- Check if we've seen this table before
  if visited[tbl] then
    local ref = {
      path = path,
      originalPath = visited[tbl],
    }

    -- Determine if this is an intentional circular reference
    if isIntentionalCircularReference(path, visited[tbl]) then
      table.insert(intentionalRefs, ref)
    else
      table.insert(circularRefs, ref)
    end

    return circularRefs, intentionalRefs
  end

  -- Mark as visited
  visited[tbl] = path

  -- Recursively check children
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      local childPath = path .. "." .. tostring(k)
      local childRefs, childIntentionalRefs = detectCircularReferences(v, childPath, visited)
      for _, ref in ipairs(childRefs) do
        table.insert(circularRefs, ref)
      end
      for _, ref in ipairs(childIntentionalRefs) do
        table.insert(intentionalRefs, ref)
      end
    end
  end

  return circularRefs, intentionalRefs
end

---Scan for circular references in immediate mode
---@return table report Detailed report of circular references
function MemoryScanner.scanCircularReferences()
  local report = {
    stateStoreCircularRefs = {},
    stateStoreIntentionalRefs = {},
    contextCircularRefs = {},
    contextIntentionalRefs = {},
    issues = {},
  }

  if MemoryScanner._StateManager then
    local internal = MemoryScanner._StateManager._getInternalState()
    report.stateStoreCircularRefs, report.stateStoreIntentionalRefs =
      detectCircularReferences(internal.stateStore, "stateStore")
  end

  if MemoryScanner._Context then
    report.contextCircularRefs, report.contextIntentionalRefs =
      detectCircularReferences(MemoryScanner._Context.topElements, "topElements")
  end

  -- Report issues only for cross-module circular references
  if #report.stateStoreCircularRefs > 0 then
    table.insert(report.issues, {
      severity = "info",
      message = string.format(
        "Found %d cross-module circular references in StateManager",
        #report.stateStoreCircularRefs
      ),
      suggestion = "These are typically architectural dependencies between modules, not memory leaks",
    })
  end

  if #report.contextCircularRefs > 0 then
    table.insert(report.issues, {
      severity = "info",
      message = string.format("Found %d cross-module circular references in Context", #report.contextCircularRefs),
      suggestion = "These are typically architectural dependencies (e.g., layout engine ↔ renderer), not memory leaks",
    })
  end

  return report
end

---Run comprehensive memory scan
---@return table report Complete memory analysis report
function MemoryScanner.scan()
  local startMemory = collectgarbage("count")

  local report = {
    timestamp = os.time(),
    startMemory = startMemory / 1024, -- MB
    stateManager = MemoryScanner.scanStateManager(),
    context = MemoryScanner.scanContext(),
    imageCache = MemoryScanner.scanImageCache(),
    circularRefs = MemoryScanner.scanCircularReferences(),
    summary = {
      totalIssues = 0,
      criticalIssues = 0,
      warnings = 0,
      info = 0,
    },
  }

  -- Count issues by severity
  local function countIssues(subReport)
    for _, issue in ipairs(subReport.issues or {}) do
      report.summary.totalIssues = report.summary.totalIssues + 1
      if issue.severity == "error" then
        report.summary.criticalIssues = report.summary.criticalIssues + 1
      elseif issue.severity == "warning" then
        report.summary.warnings = report.summary.warnings + 1
      elseif issue.severity == "info" then
        report.summary.info = report.summary.info + 1
      end
    end
  end

  countIssues(report.stateManager)
  countIssues(report.context)
  countIssues(report.imageCache)
  countIssues(report.circularRefs)

  -- Force GC and measure freed memory
  local beforeGC = collectgarbage("count")
  collectgarbage("collect")
  collectgarbage("collect")
  local afterGC = collectgarbage("count")

  report.gcAnalysis = {
    beforeGC = beforeGC / 1024, -- MB
    afterGC = afterGC / 1024, -- MB
    freed = (beforeGC - afterGC) / 1024, -- MB
    freedPercent = ((beforeGC - afterGC) / beforeGC) * 100,
  }

  -- Analyze GC effectiveness
  if report.gcAnalysis.freedPercent < 5 then
    table.insert(report.stateManager.issues, {
      severity = "info",
      message = string.format("GC freed only %.1f%% of memory", report.gcAnalysis.freedPercent),
      suggestion = "Most memory is still referenced - this is normal if UI is active",
    })
  elseif report.gcAnalysis.freedPercent > 30 then
    table.insert(report.stateManager.issues, {
      severity = "warning",
      message = string.format("GC freed %.1f%% of memory", report.gcAnalysis.freedPercent),
      suggestion = "Significant memory was unreferenced - may indicate cleanup issues",
    })
  end

  return report
end

---Format report as human-readable string
---@param report table Memory scan report
---@return string formatted Formatted report
function MemoryScanner.formatReport(report)
  local lines = {}

  table.insert(lines, "=== FlexLöve Memory Scanner Report ===")
  table.insert(lines, string.format("Timestamp: %s", os.date("%Y-%m-%d %H:%M:%S", report.timestamp)))
  table.insert(lines, string.format("Memory: %.2f MB", report.startMemory))
  table.insert(lines, "")

  -- Summary
  table.insert(lines, "--- Summary ---")
  table.insert(lines, string.format("Total Issues: %d", report.summary.totalIssues))
  table.insert(lines, string.format("  Critical: %d", report.summary.criticalIssues))
  table.insert(lines, string.format("  Warnings: %d", report.summary.warnings))
  table.insert(lines, string.format("  Info: %d", report.summary.info))
  table.insert(lines, "")

  -- StateManager
  table.insert(lines, "--- StateManager ---")
  table.insert(lines, string.format("State Count: %d", report.stateManager.stateCount))
  table.insert(lines, string.format("State Store Size: %.2f KB", report.stateManager.stateStoreSize / 1024))
  table.insert(lines, string.format("Metadata Size: %.2f KB", report.stateManager.metadataSize / 1024))
  table.insert(lines, string.format("CallSite Counters: %.2f KB", report.stateManager.callSiteCounterSize / 1024))
  table.insert(lines, string.format("Orphaned States: %d", #report.stateManager.orphanedStates))
  table.insert(lines, string.format("Stale States: %d", #report.stateManager.staleStates))
  table.insert(lines, string.format("Large States: %d", #report.stateManager.largeStates))

  if #report.stateManager.issues > 0 then
    table.insert(lines, "Issues:")
    for _, issue in ipairs(report.stateManager.issues) do
      table.insert(lines, string.format("  [%s] %s", string.upper(issue.severity), issue.message))
      if issue.suggestion then
        table.insert(lines, string.format("    → %s", issue.suggestion))
      end
    end
  end
  table.insert(lines, "")

  -- Context
  table.insert(lines, "--- Context ---")
  table.insert(lines, string.format("Top Elements: %d", report.context.topElementCount))
  table.insert(lines, string.format("Z-Index Elements: %d", report.context.zIndexElementCount))
  table.insert(lines, string.format("Frame Elements: %d", report.context.frameElementCount))

  if #report.context.issues > 0 then
    table.insert(lines, "Issues:")
    for _, issue in ipairs(report.context.issues) do
      table.insert(lines, string.format("  [%s] %s", string.upper(issue.severity), issue.message))
      if issue.suggestion then
        table.insert(lines, string.format("    → %s", issue.suggestion))
      end
    end
  end
  table.insert(lines, "")

  -- ImageCache
  table.insert(lines, "--- ImageCache ---")
  table.insert(lines, string.format("Image Count: %d", report.imageCache.imageCount))
  table.insert(lines, string.format("Estimated Memory: %.2f MB", report.imageCache.estimatedMemory / 1024 / 1024))

  if #report.imageCache.issues > 0 then
    table.insert(lines, "Issues:")
    for _, issue in ipairs(report.imageCache.issues) do
      table.insert(lines, string.format("  [%s] %s", string.upper(issue.severity), issue.message))
      if issue.suggestion then
        table.insert(lines, string.format("    → %s", issue.suggestion))
      end
    end
  end
  table.insert(lines, "")

  -- Circular References
  table.insert(lines, "--- Circular References ---")
  table.insert(lines, string.format("StateStore (Cross-module refs): %d", #report.circularRefs.stateStoreCircularRefs))
  table.insert(
    lines,
    string.format(
      "StateStore (Intentional - parent-child, modules, metatables): %d",
      #report.circularRefs.stateStoreIntentionalRefs
    )
  )
  table.insert(lines, string.format("Context (Cross-module refs): %d", #report.circularRefs.contextCircularRefs))
  table.insert(
    lines,
    string.format(
      "Context (Intentional - parent-child, modules, metatables): %d",
      #report.circularRefs.contextIntentionalRefs
    )
  )

  if #report.circularRefs.issues > 0 then
    table.insert(lines, "Issues:")
    for _, issue in ipairs(report.circularRefs.issues) do
      table.insert(lines, string.format("  [%s] %s", string.upper(issue.severity), issue.message))
      if issue.suggestion then
        table.insert(lines, string.format("    → %s", issue.suggestion))
      end
    end
  else
    table.insert(lines, "  ✓ No unexpected circular references detected")
  end
  table.insert(lines, "  Note: Cross-module refs are typically architectural dependencies, not memory leaks")
  table.insert(lines, "")

  -- GC Analysis
  table.insert(lines, "--- Garbage Collection Analysis ---")
  table.insert(lines, string.format("Before GC: %.2f MB", report.gcAnalysis.beforeGC))
  table.insert(lines, string.format("After GC: %.2f MB", report.gcAnalysis.afterGC))
  table.insert(lines, string.format("Freed: %.2f MB (%.1f%%)", report.gcAnalysis.freed, report.gcAnalysis.freedPercent))
  table.insert(lines, "")

  table.insert(lines, "=== End Report ===")

  return table.concat(lines, "\n")
end

---Save report to file
---@param report table Memory scan report
---@param filename string? Output filename (default: memory_report.txt)
function MemoryScanner.saveReport(report, filename)
  filename = filename or "memory_report.txt"
  local formatted = MemoryScanner.formatReport(report)

  local file = io.open(filename, "w")
  if file then
    file:write(formatted)
    file:close()
    if MemoryScanner._ErrorHandler then
      MemoryScanner._ErrorHandler:warn("MemoryScanner", "RES_004", {
        resourceType = "report",
        path = filename,
        status = "saved",
      })
    end
  else
    if MemoryScanner._ErrorHandler then
      MemoryScanner._ErrorHandler:warn("MemoryScanner", "RES_004", {
        resourceType = "report",
        path = filename,
        status = "failed to save",
      })
    end
  end
end

return MemoryScanner
