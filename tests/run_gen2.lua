-- T2 Gen 2 tier: tests/gen2_*.lua, tests/crystal_*.lua and the LZ3 decoder, one
-- process per suite.  ROM-free, so it runs with no data/generated/ and no cache.
--   luajit tests/run_gen2.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local FsIo = require("tests.fs_io")

local PREFIXES = { "gen2_", "crystal_" }
local EXTRA = { "tests/rom_lz3_test.lua" }

local function suites()
  local files = {}
  for _, name in ipairs(FsIo.listDir("tests")) do
    if name:match("%.lua$") then
      for _, prefix in ipairs(PREFIXES) do
        if name:sub(1, #prefix) == prefix then
          files[#files + 1] = "tests/" .. name
          break
        end
      end
    end
  end
  for _, path in ipairs(EXTRA) do
    local handle = io.open(path, "r")
    if handle then
      handle:close()
      files[#files + 1] = path
    end
  end
  table.sort(files)
  return files
end

local lua = (arg and arg[-1]) or "luajit"
local failed, total = 0, 0
for _, path in ipairs(suites()) do
  total = total + 1
  local status = os.execute(("%s %s"):format(lua, path))
  if status == 0 or status == true then
    print("ok   " .. path)
  else
    failed = failed + 1
    print("FAIL " .. path)
  end
end

print(("\ngen2: %d/%d suites passed"):format(total - failed, total))
print(("%s"):format(failed == 0 and "ALL TESTS PASSED" or failed .. " FAILURES"))
os.exit(failed == 0 and 0 or 1)
