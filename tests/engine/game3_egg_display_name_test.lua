#!/usr/bin/env luajit
-- An egg is named by the language's own EGG, as pret's GetMonData(MON_DATA_NICKNAME)
-- does for any egg (pokefirered/src/pokemon.c:3020): the party and every screen
-- that names a mon through Pokemon.displayName / displayMonName show it, whatever
-- placeholder the egg's nickname stores.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

local Strings = require("src.core.Strings")
local Pokemon = require("src.core.game3.pokemon")

-- A minimal pack, so no ROM is needed.
Pokemon._names = { [25] = "PIKACHU", [172] = "PICHU" }

local egg = { species = 172, isEgg = true, nickname = "EGG", name = "EGG" }
local hatched = { species = 172, isEgg = false, nickname = "", name = "PICHU" }
local named = { species = 25, nickname = "SPARKY" }

Strings.load({})
check(Pokemon.displayName(egg) == "EGG", "an egg reads EGG with no catalog")
check(Pokemon.displayMonName(egg) == "EGG", "in both name helpers")

Strings.load({ strings = { EGG = "OEUF" } })
check(Pokemon.displayName(egg) == "OEUF", "an egg follows the catalog's EGG")
check(Pokemon.displayMonName(egg) == "OEUF", "in both name helpers")
check(egg.nickname == "EGG", "without its stored nickname being rewritten")

local bare = { species = 172, isEgg = true, nickname = "" }
check(Pokemon.displayName(bare) == "OEUF", "an egg with no nickname at all is still named EGG")
local species_only = { species = 412, nickname = "" }
check(Pokemon.displayName(species_only) == "OEUF", "and so is one known only by the egg species")

-- (looking up a species the pack lacks reloads it; put the minimal one back)
Pokemon._names = { [25] = "PIKACHU", [172] = "PICHU" }
check(Pokemon.displayName(hatched) == "PICHU", "a hatched egg goes back to its species name")
check(Pokemon.displayName(named) == "SPARKY", "and a nicknamed mon keeps its nickname")
check(Pokemon.displayMonName(named) == "SPARKY", "in both name helpers")

Strings.load({})
T.finish("game3_egg_display_name_test")
