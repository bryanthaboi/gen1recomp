package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Sites = require("tests.modkit.callback_sites")
local UnifiedCallbacks = require("src.mods.UnifiedCallbacks")
local GameVersion = require("src.core.GameVersion")

local catalog = UnifiedCallbacks.catalog()
local found = Sites.scan("src")

for _, surface in ipairs({ "events", "hooks" }) do
  local other = surface == "events" and "hooks" or "events"
  for name, gens in pairs(found[surface]) do
    T.check(catalog[surface][name] ~= nil, surface .. " site " .. name .. " is in the catalog")
    T.check(found[other][name] == nil, name .. " is raised on one surface only")
    for gen = 1, 3 do
      local ok = UnifiedCallbacks.supports(surface, name, gen)
      T.eq(ok, gens[gen] == true, surface .. " " .. name .. " Gen " .. gen .. " support matches its call sites")
    end
  end
  for name in pairs(catalog[surface]) do
    T.check(found[surface][name] ~= nil, surface .. " catalog name " .. name .. " has a call site")
  end
end

for _, name in ipairs({ "battle.style", "catch.nickname", "catch.party_full", "transition.style" }) do
  T.check(catalog.hooks[name] ~= nil, name .. " is registrable")
end
T.check(catalog.events["mod.options_changed"] ~= nil, "mod.options_changed is registrable")

for _, version in ipairs(GameVersion.ORDER) do
  local generation = GameVersion.generation(version)
  for _, name in ipairs(UnifiedCallbacks.nativeVersions("hooks", "render.letterbox") or {}) do
    T.eq(GameVersion.generation(name) >= 1, true, "nativeVersions lists real versions")
  end
  local ok = UnifiedCallbacks.supports("hooks", "battle.style", generation, version)
  T.eq(ok, generation == 1, version .. " battle.style support follows its Gen 1 only site")
  T.eq(UnifiedCallbacks.supports("hooks", "catch.nickname", generation, version), true,
    version .. " catch.nickname has a call site")
end
for gen = 1, 3 do
  T.eq(found.hooks["catch.nickname"] and found.hooks["catch.nickname"][gen], true,
    "catch.nickname is called in Gen " .. gen)
end
T.finish("callback catalog sites")
