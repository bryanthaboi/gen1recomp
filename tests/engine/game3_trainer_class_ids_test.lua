#!/usr/bin/env luajit
-- The rival and the champion take the player's chosen rival name by class id,
-- as pret's B_TXT_TRAINER1_NAME does (pokefirered/src/battle_message.c:2078),
-- so a mod that translates the class ("RIVALE", "MAÎTRE") keeps the name.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

local Trainers = require("src.core.game3.scripting.trainers")
local rows = {
  [326] = { id = 326, class = 81, className = "RIVALE", name = "TERRY", party = {} },
  [438] = { id = 438, class = 90, className = "MAÎTRE", name = "TERRY", party = {} },
  [500] = { id = 500, class = 89, className = "RIVAL", name = "TERRY", party = {} },
  [347] = { id = 347, class = 82, className = "RIVAL", name = "IVAN", party = {} },
}
Trainers.get = function(id) return rows[tonumber(id)] end

local function nameOf(id) return Trainers.info(id, { rivalName = "GARY" }).name end
check(nameOf(326) == "GARY", "the early rival takes the rival name, whatever its class is called")
check(nameOf(500) == "GARY", "so does the late rival")
check(nameOf(438) == "GARY", "and the champion, as on the cart")
check(nameOf(347) == "IVAN", "another class keeps its own trainer's name, even one called RIVAL")
check(Trainers.info(326, {}).name == "TERRY", "with no rival name, the ROM's placeholder stays")

T.finish("game3_trainer_class_ids_test")
