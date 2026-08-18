-- Guard: core code must not call love loaders directly on literal
-- assets/generated paths.  Centralized loading (Assets / the NX overlay)
-- is what keeps mod overrides and the Blue/Yellow NX fallback working; a
-- raw literal load silently bypasses both.  This scans every src/*.lua and
-- fails on new violations so the class of bug cannot regress by accident.
-- Self-contained: luajit tests/engine/nx_generated_guard_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local FORBIDDEN = {
  'love%.graphics%.newImage%(%s*"assets/generated',
  'love%.image%.newImageData%(%s*"assets/generated',
  'love%.audio%.newSource%(%s*"assets/generated',
  'love%.sound%.newSoundData%(%s*"assets/generated',
  'love%.graphics%.newFont%(%s*"assets/generated',
  'love%.font%.newFontData%(%s*"assets/generated',
  'love%.filesystem%.read%(%s*"assets/generated',
  'love%.filesystem%.load%(%s*"assets/generated',
  'love%.filesystem%.lines%(%s*"assets/generated',
  'love%.filesystem%.newFileData%(%s*"assets/generated',
  'love%.filesystem%.getInfo%(%s*"assets/generated',
}

-- Files that legitimately reference generated literals but never load them
-- directly (writers, mount setup, the NX probe, mod source roots) are not
-- matched by the patterns above, so no allowlist is needed.

local function listLuaFiles(dir, out)
  out = out or {}
  local p = io.popen('find "' .. dir .. '" -name "*.lua" -type f')
  if not p then return out end
  for line in p:lines() do
    out[#out + 1] = line
  end
  p:close()
  return out
end

local violations = {}
for _, file in ipairs(listLuaFiles("src")) do
  local f = io.open(file, "r")
  if f then
    local body = f:read("*a")
    f:close()
    for _, pat in ipairs(FORBIDDEN) do
      if body:find(pat) then
        violations[#violations + 1] = file .. " matches " .. pat
      end
    end
  end
end

check(#violations == 0,
  "no direct love loader call on literal assets/generated paths"
    .. (#violations > 0 and (":\n  " .. table.concat(violations, "\n  ")) or ""))

-- The NX overlay module itself must exist and stay NX-gated at install time.
local f = io.open("main.lua", "r")
local mainSrc = f and f:read("*a") or ""
if f then f:close() end
check(mainSrc:find("NxAssetOverlay", 1, true) ~= nil,
  "main.lua installs NxAssetOverlay")
check(mainSrc:find("isNX", 1, true) ~= nil
    and mainSrc:find('require("src.core.NxAssetOverlay").install()', 1, true) ~= nil,
  "the overlay install stays gated on Platform.isNX()")

-- Gold Game2 / World must compile data/generated via CacheFs.loadActive so
-- a fused NX boot does not depend on mounting gold/ onto data/generated.
local function readSrc(path)
  local fh = io.open(path, "r")
  local body = fh and fh:read("*a") or ""
  if fh then fh:close() end
  return body
end
local game2Src = readSrc("src/core/Game2.lua")
check(game2Src:find("loadActive", 1, true) ~= nil,
  "Game2 compiles generated modules through CacheFs.loadActive")
check(game2Src:find("loadActive(path)", 1, true) ~= nil,
  "Game2.loadGenerated calls loadActive before love.filesystem.load")
local worldSrc = readSrc("src/world/gen2/World.lua")
check(worldSrc:find("loadActive", 1, true) ~= nil,
  "World's on-disk fallback also uses CacheFs.loadActive")

T.finish()
