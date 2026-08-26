-- A generated chunk that would loop if executed must be rejected as syntax.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = require("tests.modkit.dataset_view_fixture")

local files = {}
Fixture.cache(files, "red", {
  pokemon = "while true do end; return {}",
})
local modPath = Fixture.addMod(files, "nontermination_probe", [[
local mod = ...
local view, reason = mod.datasets:open("red")
local value = view and view.content.pokemon:get("FIXMON")
local reopened, reopenedReason = mod.datasets:open("red")
mod.exports.result = {
  first = view ~= nil, firstReason = reason, value = value,
  reopened = reopened ~= nil, reason = reopenedReason,
}
]])
local run = T.sdk.loadMods({ modPath }, {
  fs = T.sdk.memfs(files), data = { pokemon = {} }, generation = 1,
})
T.same(run.loader.exports.nontermination_probe.result,
  { first = true, reopened = false, reason = "invalid_cache" },
  "generated code is never executed and invalidates on first root access")
run.release()
T.finish("dataset_views_nontermination")
