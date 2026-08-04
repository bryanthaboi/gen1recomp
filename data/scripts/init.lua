-- Registry of hand-ported map scripts.  Map-specific behavior lives HERE,
-- never in engine classes (Critical Engineering Rule #9).
--
-- Each module returns { talk = { [TEXT_CONST] = script }, onEnter = fn,
-- onBoulderMoved = fn } where a script is a list of { "command", args... }
-- rows executed by src/script/ScriptRunner.lua.  Every hand-ported script
-- cites the pokered source it was ported from.
--
-- The modules land in src/script/MapScripts.lua as the engine's base
-- contribution: attachBase keeps the historical merge (talk tables merge
-- per TEXT constant, other hooks are replaced by later files, so
-- different files can each add NPCs to the same map), and mod
-- contributions from the map_scripts registry compose on top of it.

local GameVersion = require("src.core.GameVersion")
local MapScripts = require("src.script.MapScripts")

-- OaksLab is a full Yellow rewrite (one Eevee ball + forced Pikachu);
-- Red/Blue keep the three-starter choose flow.
local oaksLab = GameVersion.isYellow()
  and "data.scripts.oaks_lab_yellow"
  or "data.scripts.oaks_lab"

for _, mapEntry in ipairs({
  { "PALLET_TOWN", "data.scripts.pallet_town" },
  { "OAKS_LAB", oaksLab },
  { "REDS_HOUSE_1F", "data.scripts.reds_house" },
  { "CELADON_MANSION_ROOF_HOUSE", "data.scripts.celadon_eevee" },
}) do
  MapScripts.attachBase(mapEntry[1], require(mapEntry[2]))
end

-- story-critical scripts, one table per map, in the order the old merge
-- loop required them
for _, file in ipairs({ "data.scripts.story", "data.scripts.story2",
                        "data.scripts.story3", "data.scripts.story4",
                        "data.scripts.story5", "data.scripts.story6",
                        "data.scripts.story7", "data.scripts.flavor_all",
                        "data.scripts.safari", "data.scripts.seafoam",
                        "data.scripts.gyms" }) do
  for mapId, mod in pairs(require(file)) do
    MapScripts.attachBase(mapId, mod)
  end
end

-- Yellow-only content on top of the shared tables (talk keys merge per
-- TEXT constant): the Kanto-starter gift quests and Jessie & James.
if GameVersion.isYellow() then
  for _, file in ipairs({ "data.scripts.yellow_gifts",
                          "data.scripts.yellow_jessie_james",
                          "data.scripts.yellow_beach_house",
                          "data.scripts.yellow_viridian_old_man" }) do
    for mapId, mod in pairs(require(file)) do
      MapScripts.attachBase(mapId, mod)
    end
  end
end

local M = {}

function M.get(mapId)
  return MapScripts.get(mapId)
end

-- script to run when the player talks to an object with this TEXT_ constant
function M.talkScript(mapId, textConst)
  return MapScripts.talkScript(mapId, textConst)
end

-- attribution for that script's run: the owning mod's source, nil for base
function M.talkSource(mapId, textConst)
  return MapScripts.talkSource(mapId, textConst)
end

return M
