-- T4 mod-SDK tier: the public mod API exercised headlessly against the
-- fixture dataset, plus any tests a shipped mod carries in its own
-- tests/ directory.  No ROM, no display.
--   luajit tests/run_modkit.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local Runner = require("tests.tier_runner")

local dirs = { "tests/modkit/cases" }

-- mods ship their own tests (21-testing-and-ci "how mods ship their own
-- tests"); pick up every mods/<id>/tests directory that exists.
-- Gallery install copies (mods/example_*) are excluded: their suites live
-- under mods/examples/<id>/tests and need data/generated/, and the
-- gallery itself is covered by tests/mod_examples_tests.lua.  Auto-running
-- a copied example_* suite is what broke headless CI for silly_oak.
local pipe = io.popen("ls -d mods/*/tests 2>/dev/null")
if pipe then
  for line in pipe:lines() do
    if line ~= "" and not line:match("^mods/example_") then
      dirs[#dirs + 1] = line
    end
  end
  pipe:close()
end

Runner.main(dirs, "modkit")
