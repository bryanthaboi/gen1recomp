local modulePath = (...):match("(.-)[^%.]+$")
local function req(name)
  return require(modulePath .. name)
end

-- Font cache with LRU eviction, font resolution, and cache management.
-- `ErrorHandler` and `resolveImagePath` are injected via init() to avoid
-- a cross-import into utils (utils re-exports the cache via aliases).

-- Font cache with LRU eviction
local FONT_CACHE = {}
local FONT_CACHE_MAX_SIZE = 50
local FONT_CACHE_STATS = {
  hits = 0,
  misses = 0,
  evictions = 0,
  size = 0,
}

local ErrorHandler = nil
local resolveImagePath = nil

--- Initialize dependencies
---@param deps table Dependencies: { ErrorHandler = ErrorHandler, resolveImagePath = function }
local function init(deps)
  if type(deps) == "table" then
    ErrorHandler = deps.ErrorHandler
    resolveImagePath = deps.resolveImagePath
  end
end

-- LRU tracking: each entry has {font, lastUsed, accessCount}
local function updateCacheAccess(cacheKey)
  local entry = FONT_CACHE[cacheKey]
  if entry then
    entry.lastUsed = love.timer.getTime()
    entry.accessCount = entry.accessCount + 1
  end
end

local function evictLRU()
  local oldestKey = nil
  local oldestTime = math.huge

  for key, entry in pairs(FONT_CACHE) do
    -- Skip methods (get, getFont) - only evict cache entries (tables with lastUsed)
    if type(entry) == "table" and entry.lastUsed then
      if entry.lastUsed < oldestTime then
        oldestTime = entry.lastUsed
        oldestKey = key
      end
    end
  end

  if oldestKey then
    FONT_CACHE[oldestKey] = nil
    FONT_CACHE_STATS.evictions = FONT_CACHE_STATS.evictions + 1
    FONT_CACHE_STATS.size = FONT_CACHE_STATS.size - 1
  end
end

--- Create or get a font from cache
---@param size number
---@param fontPath string?
---@return love.Font
function FONT_CACHE.get(size, fontPath)
  -- Bucket font sizes for better cache reuse (reduces unique cache entries)
  -- Small sizes (< 20): round to nearest 2
  -- Medium sizes (20-40): round to nearest 4
  -- Large sizes (> 40): round to nearest 8
  if size < 20 then
    size = math.floor((size + 1) / 2) * 2
  elseif size < 40 then
    size = math.floor((size + 2) / 4) * 4
  else
    size = math.floor((size + 4) / 8) * 8
  end

  local cacheKey = fontPath and (fontPath .. ":" .. tostring(size)) or ("default:" .. tostring(size))

  if FONT_CACHE[cacheKey] then
    -- Cache hit
    FONT_CACHE_STATS.hits = FONT_CACHE_STATS.hits + 1
    updateCacheAccess(cacheKey)
    return FONT_CACHE[cacheKey].font
  end

  -- Cache miss
  FONT_CACHE_STATS.misses = FONT_CACHE_STATS.misses + 1

  local font
  if fontPath then
    local resolvedPath = resolveImagePath(fontPath)
    local success, result = pcall(love.graphics.newFont, resolvedPath, size)
    if success then
      font = result
    else
      if ErrorHandler then
        ErrorHandler:warn("utils", "RES_004", {
          resourceType = "font",
          path = fontPath,
        })
      end
      font = love.graphics.newFont(size)
    end
  else
    font = love.graphics.newFont(size)
  end

  -- Add to cache with LRU metadata
  FONT_CACHE[cacheKey] = {
    font = font,
    lastUsed = love.timer.getTime(),
    accessCount = 1,
  }
  FONT_CACHE_STATS.size = FONT_CACHE_STATS.size + 1

  -- Evict if cache is full
  if FONT_CACHE_STATS.size > FONT_CACHE_MAX_SIZE then
    evictLRU()
  end

  return font
end

--- Get font for text size (cached)
---@param textSize number?
---@param fontPath string?
---@return love.Font
function FONT_CACHE.getFont(textSize, fontPath)
  if textSize then
    return FONT_CACHE.get(textSize, fontPath)
  else
    return love.graphics.getFont()
  end
end

-- Font resolution utilities

--- Resolve font path from fontFamily and theme
---@param fontFamily string? Font family name or direct path
---@param themeComponent string? Theme component name
---@param themeManager table? ThemeManager instance
---@return string? Resolved font path or nil
local function resolveFontPath(fontFamily, themeComponent, themeManager)
  if fontFamily then
    -- Check if fontFamily is a theme font name
    local themeToUse = themeManager and themeManager:getTheme()
    if themeToUse and themeToUse.fonts and themeToUse.fonts[fontFamily] then
      return themeToUse.fonts[fontFamily]
    else
      -- Treat as direct path to font file
      return fontFamily
    end
  elseif themeComponent and themeManager then
    -- If using themeComponent but no fontFamily specified, check for default font in theme
    return themeManager:getDefaultFontFamily()
  end
  return nil
end

--- Get font for element (resolves from theme or fontFamily)
---@param textSize number? Text size in pixels
---@param fontFamily string? Font family name or direct path
---@param themeComponent string? Theme component name
---@param themeManager table? ThemeManager instance
---@return love.Font
local function getFont(textSize, fontFamily, themeComponent, themeManager)
  local fontPath = resolveFontPath(fontFamily, themeComponent, themeManager)
  return FONT_CACHE.getFont(textSize, fontPath)
end

-- Font cache management

--- Get font cache statistics
---@return table stats {hits, misses, evictions, size, hitRate}
local function getFontCacheStats()
  local total = FONT_CACHE_STATS.hits + FONT_CACHE_STATS.misses
  local hitRate = total > 0 and (FONT_CACHE_STATS.hits / total) or 0
  return {
    hits = FONT_CACHE_STATS.hits,
    misses = FONT_CACHE_STATS.misses,
    evictions = FONT_CACHE_STATS.evictions,
    size = FONT_CACHE_STATS.size,
    hitRate = hitRate,
  }
end

--- Set maximum font cache size
---@param maxSize number Maximum number of fonts to cache
local function setFontCacheSize(maxSize)
  FONT_CACHE_MAX_SIZE = math.max(1, maxSize)

  -- Evict entries if cache is now over limit
  while FONT_CACHE_STATS.size > FONT_CACHE_MAX_SIZE do
    evictLRU()
  end
end

--- Clear font cache
local function clearFontCache()
  -- Clear cache entries but preserve methods (get, getFont)
  for key, entry in pairs(FONT_CACHE) do
    if type(entry) == "table" and entry.lastUsed then
      FONT_CACHE[key] = nil
    end
  end
  FONT_CACHE_STATS.size = 0
  FONT_CACHE_STATS.evictions = 0
end

--- Preload font at multiple sizes
---@param fontPath string? Path to font file (nil for default font)
---@param sizes table Array of font sizes to preload
local function preloadFont(fontPath, sizes)
  for _, size in ipairs(sizes) do
    -- Round size to reduce cache entries
    size = math.floor(size + 0.5)

    local cacheKey = fontPath and (fontPath .. ":" .. tostring(size)) or ("default:" .. tostring(size))

    if not FONT_CACHE[cacheKey] then
      local font
      if fontPath then
        local resolvedPath = resolveImagePath(fontPath)
        local success, result = pcall(love.graphics.newFont, resolvedPath, size)
        if success then
          font = result
        else
          font = love.graphics.newFont(size)
        end
      else
        font = love.graphics.newFont(size)
      end

      FONT_CACHE[cacheKey] = {
        font = font,
        lastUsed = love.timer.getTime(),
        accessCount = 1,
      }
      FONT_CACHE_STATS.size = FONT_CACHE_STATS.size + 1
      FONT_CACHE_STATS.misses = FONT_CACHE_STATS.misses + 1

      -- Evict if cache is full
      if FONT_CACHE_STATS.size > FONT_CACHE_MAX_SIZE then
        evictLRU()
      end
    end
  end
end

--- Reset font cache statistics
local function resetFontCacheStats()
  FONT_CACHE_STATS.hits = 0
  FONT_CACHE_STATS.misses = 0
  FONT_CACHE_STATS.evictions = 0
end

return {
  FONT_CACHE = FONT_CACHE,
  init = init,
  resolveFontPath = resolveFontPath,
  getFont = getFont,
  getFontCacheStats = getFontCacheStats,
  setFontCacheSize = setFontCacheSize,
  clearFontCache = clearFontCache,
  preloadFont = preloadFont,
  resetFontCacheStats = resetFontCacheStats,
}
