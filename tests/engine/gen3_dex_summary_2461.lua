package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local Boot = require("src.ui.game3.boot")
local Dex = require("src.core.game3.dex")
local F = require("tests.fixture_data.gen3_saves")

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then
      out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else
      out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
    end
  end
  return table.concat(out)
end

local function launcherCount(save)
  local _, meta = SaveData.slotSummary(save)
  return meta and meta.dexCount
end

for _, name in ipairs({ "fr_rich_game", "lg_rich_game" }) do
  local ver = name:sub(1, 2) == "fr" and "firered" or "leafgreen"
  local save = assert(SaveConvert.importSav(unrle(F.images[name]), ver, ver))
  eq(#save.modData.cartImport.dexOwned, 8, name .. " cart owns 8 species")
  eq(Dex.nationalEnabled(save), false, name .. " national dex off")
  eq(launcherCount(save), 5, name .. " launcher counts the imported Kanto dex")
  eq(Boot.continueInfoFromSave(save).dexCount, 5, name .. " CONTINUE counts the imported Kanto dex")
  save.dex.national = true
  eq(launcherCount(save), 8, name .. " launcher counts the imported national dex")
  eq(Boot.continueInfoFromSave(save).dexCount, 8, name .. " CONTINUE counts the imported national dex")
end

do
  local save = {
    engine = "game3", version = "firered", name = "RED",
    dex = { seen = {}, owned = { [1] = true, [4] = true, [277] = true }, caught = { [1] = true, [4] = true, [277] = true }, national = false },
    flags = {}, vars = {},
  }
  eq(launcherCount(save), 2, "native save before national dex counts Kanto only")
  eq(Boot.continueInfoFromSave(save).dexCount, 2, "CONTINUE native save counts Kanto only")
  save.flags[0x840] = true
  save.vars[0x404E] = 0x6258
  eq(launcherCount(save), 3, "native save with FLAG_SYS_NATIONAL_DEX counts national")
  eq(Boot.continueInfoFromSave(save).dexCount, 3, "CONTINUE native save with national flag counts national")
  save.flags, save.vars = {}, {}
  save.dex.nationalUnlocked = true
  eq(launcherCount(save), 3, "dex.nationalUnlocked counts national")
  save.dex.nationalUnlocked = nil
  save.flags = { ["2112"] = true }
  eq(Dex.nationalEnabled(save), true, "string-keyed national flag")
  save.flags = {}
  save.dex.owned, save.dex.caught = { ["1"] = true, ["150"] = true }, {}
  eq(launcherCount(save), 2, "string-keyed dex entries count")
end

do
  local save = {
    engine = "game3", version = "firered",
    dex = { seen = {}, owned = { [25] = true }, caught = { [25] = true } },
    modData = { cartImport = { dexOwned = { 25, 26 } } },
  }
  eq(Dex.summaryCount(save), 2, "cart list and merged dex do not double count")
end

T.finish("gen3_dex_summary_2461")
