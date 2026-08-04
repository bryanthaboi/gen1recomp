local modulePath = (...):match("(.-)[^%.]+$")
local function req(name)
  return require(modulePath .. name)
end

-- Text sanitization, escaping, and input validation utilities.

-- ErrorHandler is injected via init() for truncation warnings.
local ErrorHandler = nil

--- Initialize dependencies
---@param deps table Dependencies: { ErrorHandler = ErrorHandler }
local function init(deps)
  if type(deps) == "table" then
    ErrorHandler = deps.ErrorHandler
  end
end

--- Sanitize text to prevent security vulnerabilities
--- @param text string? Text to sanitize
--- @param options table? Sanitization options
--- @return string Sanitized text
local function sanitizeText(text, options)
  local utf8 = require("utf8")
  -- Handle nil or non-string inputs
  if text == nil then
    return ""
  end
  if type(text) ~= "string" then
    text = tostring(text)
  end

  -- Default options
  options = options or {}
  local maxLength = options.maxLength or 10000
  local allowNewlines = options.allowNewlines ~= false -- default true
  local allowTabs = options.allowTabs ~= false -- default true
  local stripControls = options.stripControls ~= false -- default true
  local trimWhitespace = options.trimWhitespace ~= false -- default true

  -- Remove null bytes (critical security risk)
  text = text:gsub("%z", "")

  -- Strip control characters except allowed ones
  if stripControls then
    local pattern = "[\1-\31\127]" -- All control characters
    if allowNewlines and allowTabs then
      pattern = "[\1-\8\11\12\14-\31\127]" -- Exclude \t (9), \n (10), \r (13)
    elseif allowNewlines then
      pattern = "[\1-\9\11\12\14-\31\127]" -- Exclude \n (10), \r (13)
    elseif allowTabs then
      pattern = "[\1-\8\10\12-\31\127]" -- Exclude \t (9)
    end
    text = text:gsub(pattern, "")
  end

  -- Trim leading/trailing whitespace
  if trimWhitespace then
    text = text:match("^%s*(.-)%s*$") or ""
  end

  -- Limit string length (use UTF-8 character count, not byte count)
  local charCount = utf8.len(text)
  if charCount and charCount > maxLength then
    if ErrorHandler then
      ErrorHandler:warn("utils", "UTIL_001", {
        original = charCount,
        truncated = maxLength,
      })
    end
    -- Truncate to maxLength UTF-8 characters
    local bytePos = utf8.offset(text, maxLength + 1)
    if bytePos then
      text = text:sub(1, bytePos - 1)
    end
    if ErrorHandler then
      ErrorHandler:warn("utils", string.format("Text truncated from %d to %d characters", charCount, maxLength))
    end
  end

  return text
end

--- Validate text input against rules
--- @param text string Text to validate
--- @param rules table Validation rules
--- @return boolean, string? Returns true if valid, or false with error message
local function validateTextInput(text, rules)
  rules = rules or {}

  -- Check minimum length
  if rules.minLength and #text < rules.minLength then
    return false, string.format("Text must be at least %d characters", rules.minLength)
  end

  -- Check maximum length
  if rules.maxLength and #text > rules.maxLength then
    return false, string.format("Text must be at most %d characters", rules.maxLength)
  end

  -- Check pattern match
  if rules.pattern and not text:match(rules.pattern) then
    return false, rules.patternError or "Text does not match required pattern"
  end

  -- Check character whitelist
  if rules.allowedChars then
    local pattern = "[^" .. rules.allowedChars .. "]"
    if text:match(pattern) then
      return false, "Text contains invalid characters"
    end
  end

  -- Check character blacklist
  if rules.forbiddenChars then
    local pattern = "[" .. rules.forbiddenChars .. "]"
    if text:match(pattern) then
      return false, "Text contains forbidden characters"
    end
  end

  return true, nil
end

--- Validate text against range/length rules (alias of validateTextInput)
--- @param text string Text to validate
--- @param rules table Validation rules (minLength, maxLength, pattern, etc.)
--- @return boolean, string? Returns true if valid, or false with error message
local function validateTextRange(text, rules)
  return validateTextInput(text, rules)
end

--- Escape HTML special characters
--- @param text string Text to escape
--- @return string Escaped text
local function escapeHtml(text)
  if text == nil then
    return ""
  end
  text = tostring(text)
  text = text:gsub("&", "&amp;")
  text = text:gsub("<", "&lt;")
  text = text:gsub(">", "&gt;")
  text = text:gsub('"', "&quot;")
  text = text:gsub("'", "&#39;")
  return text
end

--- Escape Lua pattern special characters
--- @param text string Text to escape
--- @return string Escaped text
local function escapeLuaPattern(text)
  if text == nil then
    return ""
  end
  text = tostring(text)
  -- Escape all Lua pattern special characters
  text = text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return text
end

--- Strip all non-printable characters from text
--- @param text string Text to clean
--- @return string Cleaned text
local function stripNonPrintable(text)
  if text == nil then
    return ""
  end
  text = tostring(text)
  -- Keep printable ASCII (32-126), newline (10), tab (9), and carriage return (13)
  text = text:gsub("[^\9\10\13\32-\126]", "")
  return text
end

return {
  init = init,
  sanitizeText = sanitizeText,
  validateTextInput = validateTextInput,
  validateTextRange = validateTextRange,
  escapeHtml = escapeHtml,
  escapeLuaPattern = escapeLuaPattern,
  stripNonPrintable = stripNonPrintable,
}
