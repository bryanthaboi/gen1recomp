-- Diploma screen rendering and dismiss tests (engine/events/diploma.asm).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

local S = require("tests.harness").suite("diploma")
local check, eq = S.check, S.eq

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local SaveData = require("src.core.SaveData")
local Diploma = require("src.ui.Diploma")

Game.data = Data
Data.palettes = {
  palettes = {
    MEWMON = { {255,255,255}, {180,180,180}, {90,90,90}, {0,0,0} }
  }
}
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
Game.save.player.name = "ASH"
require("src.render.Font").load(Data)

local done = false
local diploma = Diploma.new(Game, function() done = true end)
Game.stack:push(diploma)

check(diploma.isOpaque, "Diploma is opaque screen")
local pals = diploma:sgbPalettes(Game)
check(pals ~= nil, "Diploma resolves sgbPalettes")

-- Confirm rendering does not crash
local ok, err = pcall(function()
  diploma:draw()
end)
check(ok, "Diploma:draw() runs without error: " .. tostring(err))

-- Confirm dismissal on A or B press
Input.pressed = { a = true }
diploma:update()
check(done, "Diploma calls onDone on A press")
eq(Game.stack:top(), nil, "Diploma pops from stack")

S.finish()
