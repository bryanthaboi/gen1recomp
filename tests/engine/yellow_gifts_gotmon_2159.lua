-- AskName: engine/events/give_pokemon.asm:45-46
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local scripts = dofile("data/scripts/yellow_gifts.lua")

local function giveRow(rows)
  for _, row in ipairs(rows) do
    if row[1] == "give_pokemon" then return row end
  end
end

local function drive(handler, save)
  local captured
  local ow = { runner = { run = function(_, rows) captured = rows end } }
  handler({ save = save }, ow, { id = "npc" }, function() end)
  T.check(captured ~= nil, "the handler builds a row list")
  return captured
end

local function assertGift(row, species)
  T.check(row ~= nil, species .. " is still given")
  T.eq(row[2], species, "the gift is " .. species)
  T.check(row[4] ~= true,
    species .. " still asks for a nickname (add_mon.asm:52)")
  T.eq(row[5], true,
    species .. " prints GotMonText + the jingle (give_pokemon.asm:45-46)")
end

assertGift(giveRow(scripts.ROUTE_24.talk.TEXT_ROUTE24_COOLTRAINER_M4),
  "CHARMANDER")

local melanie = drive(
  scripts.CERULEAN_MELANIES_HOUSE.talk.TEXT_CERULEANMELANIESHOUSE_MELANIE,
  { flags = {}, pikachuHappiness = 147 })
assertGift(giveRow(melanie), "BULBASAUR")

local jenny = drive(
  scripts.VERMILION_CITY.talk.TEXT_VERMILIONCITY_OFFICER_JENNY,
  { flags = {}, inventory = { THUNDERBADGE = 1 } })
assertGift(giveRow(jenny), "SQUIRTLE")

T.finish("Yellow starter gifts print GotMonText (#2159)")
