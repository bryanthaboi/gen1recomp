-- Public load-time developer-mode signal for sandboxed mods.
--
-- The production break this catches is a loader that computes dev mode but
-- does not expose the same fixed answer to the public mod object before the
-- entry chunk runs.  It also protects the data-only contract: the public
-- value is a boolean snapshot, not a live loader or environment handle.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local FILES = {
  ["mods/dev_probe/manifest.json"] = [[{
    "id": "dev_probe",
    "name": "Developer Mode Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "games": ["all"]
  }]],
  ["mods/dev_probe/main.lua"] = [[
    local mod = ...
    mod.exports.seenAtLoad = mod.developer
    mod.exports.kind = type(mod.developer)
    if mod.developer then
      mod.commands:register("dev_probe:diagnostics", function() return true end)
    end
  ]],
}

local function load(dev, generation)
  return T.sdk.loadMods({ "mods/dev_probe" }, {
    fs = T.sdk.memfs(FILES),
    dev = dev,
    generation = generation,
  })
end

do
  local run = load(true)
  T.eq(#run.errors, 0, "developer-mode public probe loads clean")
  local out = run.loader.exports.dev_probe
  T.eq(out.seenAtLoad, true,
    "sandboxed entry code sees developer mode at load time")
  T.eq(out.kind, "boolean", "developer mode is exposed as plain data")
  T.check(run.loader.content.commands:get("dev_probe:diagnostics") ~= nil,
    "entry code can register diagnostics only in developer mode")
  run.release()
end

do
  local run = load(false)
  T.eq(#run.errors, 0, "production-mode public probe loads clean")
  local out = run.loader.exports.dev_probe
  T.eq(out.seenAtLoad, false,
    "sandboxed entry code sees production mode at load time")
  T.eq(out.kind, "boolean", "production mode is exposed as plain data")
  T.eq(run.loader.content.commands:get("dev_probe:diagnostics"), nil,
    "production load does not register developer diagnostics")
  run.release()
end

for _, provided in ipairs({ "yes", 1 }) do
  local run = load(provided)
  T.eq(#run.errors, 0,
    "non-boolean developer-mode probe loads clean: " .. tostring(provided))
  local out = run.loader.exports.dev_probe
  T.eq(out.seenAtLoad, false,
    "non-boolean opts.dev is false in mod.developer: " .. tostring(provided))
  T.eq(out.kind, "boolean",
    "non-boolean opts.dev stays a strict public boolean: " .. tostring(provided))
  T.eq(run.loader.dev, false,
    "non-boolean opts.dev is false in loader.dev: " .. tostring(provided))
  T.eq(run.loader.content.commands:get("dev_probe:diagnostics"), nil,
    "non-boolean opts.dev cannot register developer diagnostics: " .. tostring(provided))
  run.release()
end

do
  local run = load(true, 2)
  T.eq(#run.errors, 0, "Gen 2 developer-mode public probe loads clean")
  local out = run.loader.exports.dev_probe
  T.eq(out.seenAtLoad, true,
    "Gen 2 entry code sees the same developer-mode answer")
  T.check(run.loader.content.commands:get("dev_probe:diagnostics") ~= nil,
    "Gen 2 entry code can gate diagnostics on the same signal")
  run.release()
end

do
  local saved = _G.POKEPORT_DEV_MODE
  _G.POKEPORT_DEV_MODE = true
  local ok, run = pcall(load, nil)
  _G.POKEPORT_DEV_MODE = saved
  if not ok then error(run, 0) end
  T.eq(#run.errors, 0, "command-line developer-mode probe loads clean")
  T.eq(run.loader.exports.dev_probe.seenAtLoad, true,
    "the --developer boot decision reaches the public signal")
  run.release()
end

T.finish("mod developer mode public API")
