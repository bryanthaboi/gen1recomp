local modulePath = (...):match("(.-)[^%.]+$")
local function req(name)
  return require(modulePath .. name)
end

-- Path sanitization, validation, and file-extension helpers.
-- Uses love.filesystem when available (optional) for existence checks.

--- Normalize a file path for consistent cache keys
---@param path string File path to normalize
---@return string Normalized path
local function normalizePath(path)
  path = path:match("^%s*(.-)%s*$")
  path = path:gsub("\\", "/")
  path = path:gsub("/+", "/")
  return path
end

--- Sanitize a file path
--- @param path string Path to sanitize
--- @return string Sanitized path
local function sanitizePath(path)
  if path == nil then
    return ""
  end
  path = tostring(path)

  -- Trim whitespace
  path = path:match("^%s*(.-)%s*$") or ""

  -- Normalize separators to forward slash
  path = path:gsub("\\", "/")

  -- Remove duplicate slashes
  path = path:gsub("/+", "/")

  -- Remove trailing slash (except for root)
  if #path > 1 and path:sub(-1) == "/" then
    path = path:sub(1, -2)
  end

  return path
end

--- Check if a path is safe (no traversal attacks)
--- @param path string Path to check
--- @param baseDir string? Base directory to check against (optional)
--- @return boolean, string? Returns true if safe, or false with reason
local function isPathSafe(path, baseDir)
  if path == nil or path == "" then
    return false, "Path is empty"
  end

  -- Sanitize the path
  path = sanitizePath(path)

  -- Check for suspicious patterns
  if path:match("%.%.") then
    return false, "Path contains '..' (parent directory reference)"
  end

  -- Check for null bytes
  if path:match("%z") then
    return false, "Path contains null bytes"
  end

  -- Check for encoded traversal attempts (including double-encoding)
  local lowerPath = path:lower()
  if
    lowerPath:match("%%2e")
    or lowerPath:match("%%2f")
    or lowerPath:match("%%5c")
    or lowerPath:match("%%252e")
    or lowerPath:match("%%252f")
    or lowerPath:match("%%255c")
  then
    return false, "Path contains URL-encoded directory separators"
  end

  -- If baseDir is provided, ensure path is within it
  if baseDir then
    baseDir = sanitizePath(baseDir)

    -- For relative paths, prepend baseDir
    local fullPath = path
    if not path:match("^/") and not path:match("^%a:") then
      fullPath = baseDir .. "/" .. path
    end
    fullPath = sanitizePath(fullPath)

    -- Check if fullPath starts with baseDir
    if not fullPath:match("^" .. baseDir:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")) then
      return false, "Path is outside allowed directory"
    end
  end

  return true, nil
end

--- Validate a file path with comprehensive checks
--- @param path string Path to validate
--- @param options table? Validation options
--- @return boolean, string? Returns true if valid, or false with error message
local function validatePath(path, options)
  options = options or {}

  -- Check path is not nil/empty
  if path == nil or path == "" then
    return false, "Path is empty"
  end

  path = tostring(path)

  -- Check maximum length
  local maxLength = options.maxLength or 4096
  if #path > maxLength then
    return false, string.format("Path exceeds maximum length of %d characters", maxLength)
  end

  -- Sanitize path
  path = sanitizePath(path)

  -- Check for safety (traversal attacks)
  local safe, reason = isPathSafe(path, options.baseDir)
  if not safe then
    return false, reason
  end

  -- Check allowed extensions
  if options.allowedExtensions then
    local ext = path:match("%.([^%.]+)$")
    if not ext then
      return false, "Path has no file extension"
    end

    ext = ext:lower()
    local allowed = false
    for _, allowedExt in ipairs(options.allowedExtensions) do
      if ext == allowedExt:lower() then
        allowed = true
        break
      end
    end

    if not allowed then
      return false, string.format("File extension '%s' is not allowed", ext)
    end
  end

  -- Check if file must exist
  if options.mustExist and love and love.filesystem then
    local info = love.filesystem.getInfo(path)
    if not info then
      return false, "File does not exist"
    end
  end

  return true, nil
end

--- Get file extension from path
--- @param path string File path
--- @return string? extension File extension (lowercase) or nil
local function getFileExtension(path)
  if not path then
    return nil
  end
  local ext = path:match("%.([^%.]+)$")
  return ext and ext:lower() or nil
end

--- Check if path has allowed extension
--- @param path string File path
--- @param allowedExtensions table Array of allowed extensions
--- @return boolean
local function hasAllowedExtension(path, allowedExtensions)
  local ext = getFileExtension(path)
  if not ext then
    return false
  end

  for _, allowedExt in ipairs(allowedExtensions) do
    if ext == allowedExt:lower() then
      return true
    end
  end

  return false
end

return {
  normalizePath = normalizePath,
  sanitizePath = sanitizePath,
  isPathSafe = isPathSafe,
  validatePath = validatePath,
  getFileExtension = getFileExtension,
  hasAllowedExtension = hasAllowedExtension,
}
