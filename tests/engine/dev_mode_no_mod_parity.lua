-- Developer-mode reflection is allocated only with a mod API object; toggling
-- the engine tripwire with no mods leaves the fixture dataset unchanged.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Fingerprint = require("src.link.Fingerprint")

for _, enabled in ipairs({ false, true }) do
  local data = T.fixtures.fresh()
  local expected = Fingerprint.compute(data, {})
  local run = T.sdk.loadNone({ data = data, dev = enabled })
  T.eq(#run.errors, 0, "no-mod boot remains clean")
  T.eq(next(run.loader.mods), nil, "no mod API object is allocated")
  T.eq(next(run.loader.exports), nil, "no mod export table is allocated")
  T.check(run.data == data,
    "no-mod boot preserves the active dataset object")
  T.eq(Fingerprint.compute(run.data, {}), expected,
    "developer-mode state leaves the no-mod link surface byte-equivalent")
  run.release()
end

T.finish("developer-mode no-mod parity")
