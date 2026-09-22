-- Generated cache modules must load without access to the process API.
--
-- L1 regression: Data's cache loader used
--   loadstring(bytes, "@" .. prefix .. path)
-- with no environment, so any file at <save dir>/data/generated/<name>.lua ran
-- at boot with the real `os`, `io` and `loadfile` in scope -- local code
-- execution from a directory the game treats as data.  Every other generated
-- loader in the engine sandboxes (dataset.lua, doors.lua, field.lua, ... all use
-- load(src, name, "t", {})), and LuaWriter only ever emits literals, so the
-- module format has no need for globals.
--   luajit tests/engine/game3_cache_module_sandbox_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- A generated module that reports whether the process API is reachable.
local HOSTILE = [[
if os ~= nil or io ~= nil or require ~= nil or loadfile ~= nil or loadstring ~= nil then
  return "ESCAPED"
end
return "sandboxed"
]]

package.preload["src.import.CacheFs"] = function()
  return { readActive = function() return HOSTILE end }
end
package.preload["src.core.GameVersion"] = function()
  return { cachePrefix = function() return "red/" end }
end

local Data = require("src.core.Data")

check(type(Data._loadModule) == "function", "Data exposes its cache loader as a seam")
if type(Data._loadModule) == "function" then
  local called, ok, res = pcall(Data._loadModule, nil, "pokemon")
  check(called and ok, "the cache module loads through the sandbox")
  eq(res, "sandboxed", "a generated module cannot reach os/io/require/loadfile")
end

-- Real generated data must survive the sandbox: fixture modules are written in
-- the same literal-only format LuaWriter emits, so one must compile and evaluate
-- to its table under the sandbox expression the loader now uses.
do
  local f = io.open("tests/fixture_data/pokemon.lua", "r")
  check(f ~= nil, "a fixture generated module is readable")
  if f then
    local src = f:read("*a")
    f:close()
    local chunk = load(src, "@tests/fixture_data/pokemon.lua", "t", {})
    check(chunk ~= nil, "a real generated module compiles under the sandbox")
    if chunk then
      local okEval, mod = pcall(chunk)
      check(okEval and type(mod) == "table", "...and evaluates to its table")
    end
  end
end

T.finish("game3_cache_module_sandbox_test")