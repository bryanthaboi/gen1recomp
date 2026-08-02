-- Regression coverage for #600 "Wrong Prof. Oak dialogue" (T2, ROM-free).
--
-- pret/pokered scripts/OaksLab.asm OaksLabOak1Text opens with the dex
-- rating branch: EVENT_PALLET_AFTER_GETTING_POKEBALLS, or 2+ owned species
-- (CountSetBits over wPokedexOwned) once EVENT_GOT_POKEDEX is set, sends
-- Oak to .HowIsYourPokedexComingText + predef DisplayDexRating.  The port
-- skipped that branch entirely, so a player with the Pokedex kept getting
-- .PokemonAroundTheWorldText, the line Oak reads right after handing it
-- over.  Yellow already had the branch (data/scripts/oaks_lab_yellow.lua);
-- Red additionally gates it on GOT_POKEDEX, which Yellow's copy drops.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local MapScripts = require("src.script.MapScripts")

local contribution = dofile("data/scripts/oaks_lab.lua")
T.eq(#MapScripts.validateContribution(contribution), 0,
  "oaks_lab contribution validates cleanly")

local script = contribution.talk.TEXT_OAKSLAB_OAK1
local labels = {}
for i, row in ipairs(script) do
  if row[1] == "label" then labels[row[2]] = i end
end

-- mini executor with ScriptRunner semantics: label/number/"end" jumps,
-- the three checks this branch needs, and text/dex_rating recorded
local function run(flags, owned, bag)
  local pc, out, last, guard = 1, {}, nil, 0
  while pc <= #script and guard < 400 do
    guard = guard + 1
    local row = script[pc]
    local verb, jump = row[1], nil
    if verb == "check_flag" then last = flags[row[2]] == true
    elseif verb == "check_dex_owned" then last = owned >= row[2]
    elseif verb == "check_item" then last = (bag[row[2]] or 0) > 0
    elseif verb == "jump" then jump = row[2]
    elseif verb == "jump_if_true" then if last then jump = row[2] end
    elseif verb == "jump_if_false" then if not last then jump = row[2] end
    elseif verb == "show_text" then out[#out + 1] = row[2]
    elseif verb == "dex_rating" then out[#out + 1] = "<dex_rating>"
    end
    if jump == "end" then break
    elseif type(jump) == "string" then pc = labels[jump]
    elseif type(jump) == "number" then pc = jump
    else pc = pc + 1 end
  end
  return table.concat(out, "|")
end

local dex = "_OaksLabOak1HowIsYourPokedexComingText|<dex_rating>"

T.eq(run({ EVENT_GOT_POKEDEX = true }, 2, {}), dex,
  "Pokédex + 2 owned rates the dex")
T.eq(run({ EVENT_GOT_POKEDEX = true }, 6, { POKE_BALL = 5 }), dex,
  "the rating branch wins over the come-see-me line")
T.eq(run({ EVENT_PALLET_AFTER_GETTING_POKEBALLS = true }, 0, {}), dex,
  "converted saves rate off EVENT_PALLET_AFTER_GETTING_POKEBALLS")
T.eq(run({ EVENT_GOT_POKEDEX = true, EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE = true },
  5, {}), dex, "the rating branch wins over the poke ball gift")

T.eq(run({ EVENT_GOT_POKEDEX = true }, 1, {}),
  "_OaksLabOak1PokemonAroundTheWorldText",
  "one owned species is still the around-the-world line")
T.eq(run({}, 3, {}), "_OaksLabOak1WhichPokemonDoYouWantText",
  "no Pokédex yet: never rate, whatever the owned count (Red-only gate)")

T.finish("oaks_lab_dex_rating_bug600")
