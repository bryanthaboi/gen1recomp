-- ROM-free Gen 2 tier. Unlike the historical list inside run_tests.lua this
-- discovers every gen2_*_test.lua and gold_*_test.lua automatically and runs
-- each in a fresh process. Cache-backed assertions may skip without a private
-- ROM cache, but their fixture-backed behavior always runs in CI.

package.path = "./?.lua;./?/init.lua;" .. package.path

local FsIo = require("tests.fs_io")
local files = { "tests/rom_lz3_test.lua" }

for _, name in ipairs(FsIo.listDir("tests")) do
  if name:match("^gen2_.*_test%.lua$") or name:match("^gold_.*_test%.lua$") then
    files[#files + 1] = "tests/" .. name
  end
end
table.sort(files)

require("tests.tier_runner").mainFiles(files, "gen2 fixture")
