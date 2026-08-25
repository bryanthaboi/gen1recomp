-- Static privacy gate for the narrow Mew dock engine branch.  It checks the
-- Git publication set, not ignored local imports: user ROMs and progress
-- saves may exist on a developer machine but must never become tracked files.

package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")

local pipe = io.popen("git ls-files 2>" .. (package.config:sub(1, 1) == "\\" and "nul" or "/dev/null"))
local paths = {}
if pipe then
  for path in pipe:lines() do paths[#paths + 1] = path:gsub("\\", "/") end
  pipe:close()
end

T.check(#paths > 100,
  "privacy gate inspects a real Git publication set instead of passing vacuously")

local forbiddenExtensions = {
  gb = true, gbc = true, gba = true, sav = true, srm = true,
  rom = true, z64 = true, v64 = true, n64 = true, nds = true,
  sfc = true, smc = true,
}
local forbiddenRuntimeRoots = {
  ["save.lua"] = true,
  ["save_blue.lua"] = true,
  ["save_yellow.lua"] = true,
  ["save_gold.lua"] = true,
  ["options.lua"] = true,
}

local binaryLeaks, runtimeLeaks = {}, {}
for _, path in ipairs(paths) do
  local lower = path:lower()
  local ext = lower:match("%.([^./\\]+)$")
  if forbiddenExtensions[ext] then binaryLeaks[#binaryLeaks + 1] = path end
  if forbiddenRuntimeRoots[lower]
      or lower:match("^saves/")
      or lower:match("^imports/")
      or lower:match("^mods%-data/") then
    runtimeLeaks[#runtimeLeaks + 1] = path
  end
end

T.eq(#binaryLeaks, 0,
  "tracked publication contains no ROM/save binaries: " .. table.concat(binaryLeaks, ", "))
T.eq(#runtimeLeaks, 0,
  "tracked publication contains no runtime save/import data: " .. table.concat(runtimeLeaks, ", "))

T.finish("mew dock private artifact gate")
