-- BoxMenu's Yellow-only "Pikachu looks unhappy" release path
-- (release()'s isYellow()/species=="PIKACHU"/otId/ot branch) pushes its
-- TextBox with `TextBox.new(game, (...):gsub(...))` -- the gsub call is
-- the last argument, unparenthesized, so Lua expands its second return
-- value (the substitution count) into TextBox.new's third parameter,
-- onDone.  TextBox.lua later calls onDone() unconditionally once the box
-- is dismissed, and a number is not callable: every release of your own
-- caught Pikachu in Yellow crashed, regardless of its nickname (unlike
-- the separate %-escape gsub bug, this needs no special save content --
-- ordinary play reaches it every time).  ROM-free: registers a fake
-- Data.pokemon.PIKACHU cloned from the fixture species so the species ==
-- "PIKACHU" check can be exercised without a real ROM import.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local ids = T.fixtures.ids
require("src.render.Font").load(Data)

-- clone a real fixture species under the literal id release() checks for
Data.pokemon.PIKACHU = Data.pokemon[ids.species[1]]

local Pokemon = require("src.pokemon.Pokemon")
local Boxes = require("src.pokemon.Boxes")
local TextBox = require("src.render.TextBox")
local BoxMenu = require("src.ui.BoxMenu")
local ListMenu = require("src.ui.ListMenu")
local ChoiceBox = require("src.ui.ChoiceBox")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local Sound = require("src.core.Sound")

local realCry, realPlay = Sound.playCry, Sound.play
Sound.playCry = function() end
Sound.play = function() end

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

GameVersion.set("yellow")

local save = SaveData.newGame()
local game = {
  data = Data,
  save = save,
  stack = stack,
  input = {
    wasPressed = function(_, key) return pressed[key] or false end,
    isDown = function() return false end,
  },
}
game.save.options = game.save.options or {}
game.save.options.textSpeed = 1

local box = Boxes.active(save)
local mon = Pokemon.new(Data, "PIKACHU", 5)
mon.otId = save.player.id
mon.ot = save.player.name
box[1] = mon

stack:push(BoxMenu.new(game))
press("down"); press("down"); press("a") -- open RELEASE list
T.check(topMt() == ListMenu, "RELEASE opens the box list")

-- release() calls Sound.playCry (stubbed) then pushes the "unhappy"
-- TextBox before any confirmation prompt -- pre-fix this line itself
-- raises "attempt to call field 'onDone' (a number value)" the moment
-- TextBox.new stores the leaked count and something dismisses the box.
local ok, err = pcall(function()
  press("a") -- choose the Pikachu; release() runs synchronously here
  T.check(topMt() == TextBox, "the unhappy-Pikachu TextBox opens directly, no confirm prompt")
  -- dismiss it: this is what calls onDone, which is where the pre-fix
  -- leaked count used to crash
  mash("a", function() return topMt() ~= TextBox end)
end)
T.check(ok, "releasing your own caught Pikachu in Yellow does not crash: " .. tostring(err))

GameVersion.set("red")
Sound.playCry, Sound.play = realCry, realPlay
T.finish("pikachu_unhappy_release_crash")
