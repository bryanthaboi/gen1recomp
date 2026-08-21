-- BoxMenu's RELEASE confirmation ("Once released,\n%s is\ngone forever.
-- OK?") used to be a bare Lua literal. tests/engine/pc_release.lua only
-- ever runs with an empty Data.text, so it can't tell a properly-wired
-- t._OnceReleasedText or "..." fallback apart from a literal that never
-- looked at t at all -- every assertion there passes either way. This
-- test drives the same interactive release flow with a faked
-- Data.text._OnceReleasedText and checks the pushed TextBox's raw text
-- (captured via a TextBox.new spy, so real pagination/choice behavior is
-- untouched) uses the translated value, not the English literal.
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
  Data.text._OnceReleasedText = nil
end

-- vanilla: with no catalog entry, the English literal still substitutes
do
  local game, box = mkGame()
  local name = monName(box)
  local text = releaseFirstMon(game)
  T.eq(text, "Once released,\n" .. name .. " is\ngone forever. OK?",
    "no catalog entry still falls back to the English literal")
end

TextBox.new = realNew
Sound.playCry, Sound.play = realCry, realPlay
T.finish("box_release_confirmation_romtext")
