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
local FsIo = require("tests.fs_io")
for _, name in ipairs(FsIo.listDir("mods")) do
  if not name:find(".", 1, true) and not name:match("^example_") then
    local dir = "mods/" .. name .. "/tests"
    if FsIo.isDir(dir) then dirs[#dirs + 1] = dir end
  end
end

Runner.main(dirs, "modkit")
