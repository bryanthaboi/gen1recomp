---@class UTF8
---Compatibility layer for UTF-8 support across Lua versions
---Handles utf8 (Lua 5.3+), lua-utf8 (LuaRocks), and basic fallbacks

local UTF8 = {}

-- Try to load UTF-8 library in order of preference:
-- 1. Built-in utf8 (Lua 5.3+, LÖVE2D)
-- 2. lua-utf8 from LuaRocks (Lua 5.1, 5.2)
-- 3. Error if neither available
local function loadUTF8()
  -- Try built-in utf8 first (Lua 5.3+ and LÖVE2D)
  if utf8 and type(utf8) == "table" and utf8.len then
    return utf8
  end

  -- Try lua-utf8 from LuaRocks
  local ok, luautf8 = pcall(require, "lua-utf8")
  if ok then
    return luautf8
  end

  -- Try standard utf8 module name as fallback
  ok, luautf8 = pcall(require, "utf8")
  if ok then
    return luautf8
  end

  -- No UTF-8 library available
  error("No UTF-8 library available. Please install 'luautf8' via LuaRocks: luarocks install luautf8")
end

-- Load the UTF-8 implementation
local utf8lib = loadUTF8()

-- Export all utf8 functions
UTF8.char = utf8lib.char
UTF8.charpattern = utf8lib.charpattern
UTF8.codes = utf8lib.codes
UTF8.codepoint = utf8lib.codepoint
UTF8.len = utf8lib.len
UTF8.offset = utf8lib.offset

return UTF8
