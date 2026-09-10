-- engine/events/give_pokemon.asm:45-46, engine/pokemon/add_mon.asm:52
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local scripts = dofile("data/scripts/story4.lua")

local function assertGift(rows, species, level, where)
  local give, gots = nil, 0
  for _, row in ipairs(rows) do
    if row[1] == "give_pokemon" then give = row end
    if row[1] == "show_text" and row[2] == "_GotMonText" then gots = gots + 1 end
  end
  T.check(give ~= nil, where .. ": give_pokemon row present")
  T.eq(give and give[2], species, where .. ": the gift is " .. species)
  T.eq(give and give[3], level, where .. ": level " .. level)
  T.check(give and give[4] ~= true,
    where .. ": still asks for a nickname (add_mon.asm:52)")
  T.eq(give and give[5], true,
    where .. ": GotMonText + jingle come from GivePokemon (give_pokemon.asm:45-46)")
  T.eq(gots, 0, where .. ": no hand-rolled _GotMonText row after the give")
end

assertGift(scripts.SILPH_CO_7F.talk.TEXT_SILPHCO7F_SILPH_WORKER_M1,
  "LAPRAS", 15, "SilphCo7F.asm:311")
assertGift(scripts.MT_MOON_POKECENTER.talk.TEXT_MTMOONPOKECENTER_MAGIKARP_SALESMAN,
  "MAGIKARP", 5, "MtMoonPokecenter.asm:47")

T.finish("LAPRAS / MAGIKARP gifts print GotMonText before AskName (#2243)")
