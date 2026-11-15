local U = require("tests.drivers.util")

local ROOT = "data/generated/gba/native"
local PAIR = "harbor"

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local CacheFs = require("src.import.CacheFs")
  local CacheBlob = require("src.import.CacheBlob")
  local GameVersion = require("src.core.GameVersion")
  local Dataset = require("src.core.game3.dataset")
  local Decode = require("src.core.game3.asset_decode")
  local Palette = require("src.core.game3.palette")
  local fs = love.filesystem
  local fails = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  local prefix = GameVersion.cachePrefix()
  local cache = Dataset.cache()
  local path = ROOT .. "/" .. PAIR
  local blob = cache:read(path .. "/mids.idx")
  local pals = cache:read(path .. "/palettes.bin")
  local over = cache:read(path .. "/mids_over.idx")
  check(blob ~= nil and pals ~= nil, "2705 harbor blobs readable under " .. prefix)
  if not (blob and pals) then love.event.quit(1) return end
  local _, bgr = Palette.load(pals)
  local rel = path .. "/atlas_" .. (over and "u" or "flat") .. "_" .. Palette.hash(bgr, blob) .. ".rgba"
  local raw = string.rep("\1\2\3\255", 256 * 64)

  fs.remove(prefix .. rel)
  fs.createDirectory(path)
  fs.write(rel, raw)
  local other = prefix == "leafgreen/" and "firered/" or "leafgreen/"
  fs.createDirectory(other .. path)
  fs.write(other .. rel, raw)
  CacheFs.mountVersion(other:gsub("/$", ""))

  local ok, err = pcall(Decode.pair, cache, ROOT, PAIR)
  check(ok and type(err) == "table", "2705 stale_unprefixed_atlas_not_read decode ok=" .. tostring(ok)
    .. (ok and "" or (" err=" .. tostring(err))))
  local written = fs.read(prefix .. rel)
  check(type(written) == "string" and written:byte(1) == 0x78,
    "2705 atlas_rebaked_deflated_under_" .. prefix:gsub("/$", ""))
  check(cache:read(rel) ~= nil and #cache:read(rel) == #CacheBlob.inflate(written),
    "2705 atlas_read_back_from_versioned_dir")
  CacheFs.unmountVersion(other:gsub("/$", ""))

  fs.write(prefix .. rel, raw)
  local okRaw, resRaw = pcall(Decode.pair, cache, ROOT, PAIR)
  check(okRaw and type(resRaw) == "table", "2705 raw_versioned_atlas_reads_as_miss")
  local healed = fs.read(prefix .. rel)
  check(type(healed) == "string" and healed:byte(1) == 0x78 and #healed ~= #raw,
    "2705 raw_versioned_atlas_rebaked_deflated")

  local idxRel = prefix .. path .. "/mids.idx"
  local savedIdx = fs.read(idxRel)
  fs.write(idxRel, string.rep("\0", 64))
  local okIdx, errIdx = pcall(Decode.pair, cache, ROOT, PAIR)
  fs.write(idxRel, savedIdx)
  check(not okIdx and tostring(errIdx):find(path .. "/mids.idx", 1, true) ~= nil
    and tostring(errIdx):find("is not deflated", 1, true) ~= nil,
    "2705 raw_versioned_mids_idx_fails_loudly")

  fs.remove(prefix .. rel)
  fs.remove(rel)
  fs.remove(other .. rel)
  local okClean = pcall(Decode.pair, cache, ROOT, PAIR)
  check(okClean, "2705 clean_rebake_after_cleanup")
  love.event.quit(fails == 0 and 0 or 1)
end
