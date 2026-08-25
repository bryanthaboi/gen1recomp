-- Dedicated Route B no-mod parity: the additive facade remains cold.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local reads = 0
local fs = T.sdk.memfs({})
local read = fs.read
fs.read = function(path)
  if path:match("^[a-z]+/data/generated/")
      or path:match("^[a-z]+/rom%-cache%.complete$") then
    reads = reads + 1
  end
  return read(path)
end
local data = { pokemon = { ACTIVE = { id = "ACTIVE", nested = { n = 1 } } } }
local run = T.sdk.loadNone({ fs = fs, data = data, generation = 1 })
T.eq(#run.errors, 0, "no-mod load remains clean")
T.eq(run.loader.datasetViews, nil, "no-mod load does not allocate dataset service")
T.eq(reads, 0, "no-mod load performs no imported dataset reads")
T.eq(data.pokemon.ACTIVE.nested.n, 1, "no-mod data remains unchanged")
run.release()
T.finish("dataset_views_no_mod_parity")
