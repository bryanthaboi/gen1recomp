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
  for _, name in ipairs({ "battle.style", "catch.nickname", "catch.party_full" }) do
    T.eq(UnifiedCallbacks.supports("hooks", name, generation, version), true,
      version .. " " .. name .. " has a call site")
  end
  T.eq(UnifiedCallbacks.supports("events", "pokemon.before_give", generation, version), true,
    version .. " pokemon.before_give has a call site")
end
for gen = 1, 3 do
  for _, name in ipairs({ "battle.style", "catch.nickname", "catch.party_full" }) do
    T.eq(found.hooks[name] and found.hooks[name][gen], true, name .. " is called in Gen " .. gen)
  end
  T.eq(found.events["pokemon.before_give"] and found.events["pokemon.before_give"][gen], true,
    "pokemon.before_give is emitted in Gen " .. gen)
end
for _, name in ipairs({ "link.connected", "link.ended", "trade.completed" }) do
  for _, version in ipairs(GameVersion.ORDER) do
    local generation = GameVersion.generation(version)
    T.eq(UnifiedCallbacks.supports("events", name, generation, version) == true, generation ~= 2,
      version .. " " .. name .. " support follows its Gen 1 and Gen 3 sites")
  end
  T.eq(found.events[name] and found.events[name][2], nil, name .. " has no Gen 2 call site")
end
T.finish("callback catalog sites")
