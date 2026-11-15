package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local ids = T.fixtures.ids
require("src.render.Font").load(Data)

local Pokemon = require("src.pokemon.Pokemon")
local Boxes = require("src.pokemon.Boxes")
local TextBox = require("src.render.TextBox")
local BoxMenu = require("src.ui.BoxMenu")
local ListMenu = require("src.ui.ListMenu")
local ChoiceBox = require("src.ui.ChoiceBox")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")

local realCry, realPlay = Sound.playCry, Sound.play
Sound.playCry = function() end
Sound.play = function() end

-- spy: records every raw text TextBox.new receives, without disturbing
-- pagination/choice re-push, so the interactive flow behaves exactly like
-- pc_release.lua's
local captured
local realNew = TextBox.new
TextBox.new = function(game, text, onDone, opts)
  captured[#captured + 1] = text
  return realNew(game, text, onDone, opts)
end

local stack = { states = {} }
function stack:push(s) self.states[#self.states + 1] = s end
function stack:pop()
  local t = self.states[#self.states]
  self.states[#self.states] = nil
  return t
end
function stack:top() return self.states[#self.states] end
function stack:update(dt)
  local t = self:top()
  if t and t.update then t:update(dt) end
end

local pressed = {}
local function press(btn)
  pressed = { [btn] = true }
  stack:update(1 / 60)
  pressed = {}
end

local function topMt() return getmetatable(stack:top()) end
local function mash(btn, cond, n)
  for _ = 1, (n or 400) do
    if cond() then return true end
    press(btn)
  end
  return false
end

local function mkGame()
  stack.states = {}
  captured = {}
  local game = {
    data = Data,
    save = SaveData.newGame(),
    stack = stack,
    input = {
      wasPressed = function(_, key) return pressed[key] or false end,
      isDown = function() return false end,
    },
  }
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  local box = Boxes.active(game.save)
  box[1] = Pokemon.new(Data, ids.species[1], 5)
  return game, box
end

local function releaseFirstMon(game)
  stack:push(BoxMenu.new(game))
  press("down"); press("down"); press("a") -- open RELEASE list
  T.check(topMt() == ListMenu, "RELEASE opens the box list")
  press("a") -- choose the first (only) mon
  T.check(mash("a", function() return topMt() == ChoiceBox end),
    "confirm choice opens")
  -- the confirmation TextBox is captured[1] the moment it was pushed,
  -- before this mash even ran
  return captured[1]
end

-- monName (BoxMenu.lua): mon.nickname or def.name
local function monName(box)
  local mon = box[1]
  local def = Data.pokemon[mon.species]
  return mon.nickname or def.name
end

-- translated: the fake value must reach the pushed TextBox
do
  local game, box = mkGame()
  local name = monName(box)
  Data.text._OnceReleasedText = "FAKE {RAM:wStringBuffer} released!"
  local text = releaseFirstMon(game)
  T.eq(text, "FAKE " .. name .. " released!",
    "a translated _OnceReleasedText reaches the release confirmation")
end

do
  local game, box = mkGame()
  local name = monName(box)
  Data.text._OnceReleasedText = "Once released,\n{RAM:wStringBuffer} is\vgone forever. OK?{DONE}"
  local text = releaseFirstMon(game)
  T.eq(text, "Once released,\n" .. name .. " is\vgone forever. OK?{DONE}",
    "the cached label prints with the cart's line breaks")
end

do
  local game = mkGame()
  Data.text._OnceReleasedText = nil
  stack:push(BoxMenu.new(game))
  press("down"); press("down"); press("a")
  local ok, err = pcall(press, "a")
  T.check(not ok and tostring(err):find("_OnceReleasedText", 1, true) ~= nil,
    "a cache without _OnceReleasedText is an error, not an English literal")
end

TextBox.new = realNew
Sound.playCry, Sound.play = realCry, realPlay
T.finish("box_release_confirmation_romtext")
