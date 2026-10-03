-- ROM-free Gen 5 importer and example-provider suites, each in its own process.
package.path = "./?.lua;./?/init.lua;" .. package.path
local Runner = require("tests.tier_runner")
local dirs = { "tests/gen5", "mods/examples/gen5_battle_sprites/tests" }
-- A missing directory must not turn this required CI tier into a vacuous pass.
for _, dir in ipairs(dirs) do
  assert(#Runner.suites(dir) > 0, "no Gen 5 suites found in " .. dir)
end
Runner.main(dirs, "gen5")
