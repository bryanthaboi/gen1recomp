-- T4: FireRed mod API parity, read from src/mods/Gen3Compat.lua and the
-- per-generation mod.world / mod.battle modules at run time.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local Gen2Compat = require("src.mods.Gen2Compat")
local Gen3Compat = require("src.mods.Gen3Compat")

for _, fn in ipairs({ "serves", "resolve", "bind", "coverage", "modules",
                      "memberStatus", "applyMerged", "scriptCtx" }) do
  T.eq(type(Gen3Compat[fn]), "function", "Gen3Compat." .. fn .. " exists")
end
T.eq(type(Gen3Compat.ADAPTERS), "table", "Gen3Compat.ADAPTERS is published")
T.eq(Gen3Compat.COVERAGE_VERSION, Gen2Compat.COVERAGE_VERSION,
  "both compat layers speak one coverage contract version")

for name in pairs(Gen2Compat.ADAPTERS) do
  T.check(Gen3Compat.serves(name),
    "a module Gold adapts is adapted on FireRed too: " .. name)
end
for name in pairs(Gen3Compat.ADAPTERS) do
  T.check(Gen2Compat.serves(name),
    "FireRed adapts nothing Gold does not: " .. name)
  local row = Gen3Compat.coverage(name)
  T.check(row ~= nil, "coverage row for " .. name)
  if row then
    T.check(row.kind == "facade" or row.kind == "alias",
      "coverage kind is facade or alias: " .. name)
    for member, status in pairs(row.members) do
      T.check(status == "backed" or status == "warned" or status == "absent",
        ("%s.%s carries one of the three statuses"):format(name, member))
    end
  end
end

local function publicMethods(module)
  local out = {}
  for key, value in pairs(module) do
    if type(value) == "function" and not key:find("^_") then out[#out + 1] = key end
  end
  table.sort(out)
  return out
end

local function surface(label, gen3Name, others)
  local ok3, gen3 = pcall(require, gen3Name)
  T.check(ok3, label .. ": " .. gen3Name .. " loads headless")
  if not ok3 then return end
  for _, otherName in ipairs(others) do
    local ok, other = pcall(require, otherName)
    if ok and type(other) == "table" then
      for _, key in ipairs(publicMethods(other)) do
        T.eq(type(gen3[key]), "function",
          ("%s: %s.%s has a FireRed arm"):format(label, otherName, key))
      end
    else
      T.check(true, label .. ": " .. otherName .. " not loadable headless, skipped")
    end
  end
end

surface("mod.world", "src.world.game3.WorldAPI",
  { "src.world.WorldAPI", "src.world.gen2.WorldAPI" })
surface("mod.battle", "src.battle.game3.BattleAPI",
  { "src.battle.BattleAPI", "src.battle.gen2.BattleAPI" })

local worldRow = Gen3Compat.coverage("src.world.WorldAPI")
T.eq(worldRow and worldRow.target, "src.world.game3.WorldAPI",
  "the WorldAPI coverage row names the FireRed module")

T.finish("gen3check")
