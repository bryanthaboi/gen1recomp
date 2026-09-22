#!/usr/bin/env luajit
-- An egg's menu icon is SPECIES_EGG's, as pret draws it from
-- GetMonData(MON_DATA_SPECIES_OR_EGG) (pokefirered/src/pokemon.c:3245,
-- party_menu.c:2655), not the icon of the species it will hatch into.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

local Pokemon = require("src.core.game3.pokemon")
Pokemon._names = { [25] = "PIKACHU", [172] = "PICHU" } -- a minimal pack, so no ROM is needed

check(Pokemon.speciesOrEgg({ species = 172, isEgg = true }) == 412, "a Pichu egg's icon is the EGG's")
check(Pokemon.speciesOrEgg({ species = 172, egg = true }) == 412, "whichever egg flag it carries")
check(Pokemon.speciesOrEgg({ species = 412 }) == 412, "an egg known only by the egg species stays one")
check(Pokemon.speciesOrEgg({ species = 172, isEgg = false }) == 172, "a hatched mon keeps its species")
check(Pokemon.speciesOrEgg({ species = 25 }) == 25, "and so does any other mon")
check(Pokemon.speciesOrEgg(nil) == nil, "no mon, no species")

-- Every screen that draws a party or box mon's icon goes through it (the PC
-- chrome's third call is its hovered-mon front pic).
local SITES = {
  { "src/ui/game3/party_menu.lua", 1 },
  { "src/ui/game3/box_storage_ui.lua", 2 },
  { "src/ui/game3/pc_chrome.lua", 3 },
  { "src/ui/game3/release_seq.lua", 1 },
}
for _, site in ipairs(SITES) do
  local f = assert(io.open(site[1], "rb"))
  local src = f:read("*a")
  f:close()
  local n = select(2, src:gsub("Pokemon%.speciesOrEgg%(", ""))
  check(n == site[2], ("%s draws %d mon(s) by speciesOrEgg (found %d)"):format(site[1], site[2], n))
end

T.finish("game3_egg_icon_species_test")
