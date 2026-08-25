-- The BICYCLE is used straight off the item list, with no USE/TOSS box
-- (#1705).
--
-- StartMenu_Item's .choseItem reads wCurItem and, before it ever loads
-- USE_TOSS_MENU_TEMPLATE into wTextBoxID, does `cp BICYCLE / jp z,
-- .useOrTossItem` (engine/menus/start_sub_menus.asm:340-342).  So the bike
-- mounts, dismounts or refuses on one A press, and -- having no TOSS row to
-- reach -- can never be thrown away from the bag at all.  Every other item,
-- key items included, still gets the option box.
--
-- The port pushed the USE/TOSS Menu for every field item, so the bike took
-- two presses and offered a TOSS the cart does not.
--   luajit tests/engine/bag_bicycle_no_options_bug1705.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Sound"] = { play = function() end, playCry = function() end }
local music = {}
package.loaded["src.core.Music"] = {
  playMap = function(_, mapId, biking) music[#music + 1] = { mapId, biking } end,
}
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { textBox = true, text = text, done = done } end,
  soundOpts = function() return nil end,
}
package.loaded["src.ui.BagMenu"] = nil
local BagMenu = require("src.ui.BagMenu")
local Menu = require("src.ui.Menu")
require("src.ui.Screens").invalidate()

local Fixtures = require("tests.modkit.fixtures")
local Bag = require("src.inventory.Bag")

local Data = Fixtures.fresh()
-- the fixture item table carries neither, and BagMenu reads only
-- name/keyItem/machine off a def; the branches under test key on the id
Data.items.BICYCLE = { id = "BICYCLE", index = 6, name = "BICYCLE", price = 0,
                       keyItem = true }
Data.items.TOWN_MAP = { id = "TOWN_MAP", index = 5, name = "TOWN MAP",
                        price = 0, keyItem = true }
Data.items.FIX_POTION = Data.items.FIX_POTION
  or { id = "FIX_POTION", index = 20, name = "FIX POTION", price = 300 }

local BIKE_MAP = { id = "FIX_TOWN", def = { tileset = "OVERWORLD" } }

local function freshGame(extras)
  local game = {
    data = Data,
    save = {
      party = {},
      player = { name = "RED", id = 1 },
      inventory = {},
      options = {},
      flags = {},
      money = 0,
    },
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = { pressed = nil }
  function game.input:wasPressed(b) return self.pressed == b end
  function game.input:isDown() return false end
  -- IsBikeRidingAllowed reads the tileset off the loaded map, and the
  -- mount/dismount lines read the player's name off the save
  game.overworld = { map = BIKE_MAP, player = { surfing = false } }
  Bag.add(game.save, "FIX_POTION", 3)
  Bag.add(game.save, "BICYCLE", 1)
  Bag.add(game.save, "TOWN_MAP", 1)
  for k, v in pairs(extras or {}) do game.save[k] = v end
  return game
end

local function rowFor(list, id)
  for i, r in ipairs(list.items) do
    if r.value == id then return i end
  end
  return nil
end

local function isMenu(s) return getmetatable(s) == Menu end
local function isBox(s) return type(s) == "table" and s.textBox == true end

local function inStack(game, pred)
  for _, s in ipairs(game.stack.states) do
    if pred(s) then return true end
  end
  return false
end

-- Open the bag, put the cursor on `id` and press A once.  Returns the list
-- and every state the press left on the stack above it, so a USE/TOSS box
-- that appears and is then replaced is still caught.
local function chooseOnce(game, id)
  local list = BagMenu.new(game, {})
  game.stack:push(list)
  local row = rowFor(list, id)
  if not row then return nil, nil, "no " .. id .. " row in the bag" end
  list.index = row
  local seen = {}
  local realPush = game.stack.push
  game.stack.push = function(self, s)
    seen[#seen + 1] = s
    return realPush(self, s)
  end
  game.input.pressed = "a"
  list:update(1 / 60)
  game.input.pressed = nil
  game.stack.push = realPush
  return list, seen
end

local function sawMenu(seen)
  for _, s in ipairs(seen or {}) do
    if isMenu(s) then return true end
  end
  return false
end

local function boxText(game)
  local top = game.stack:top()
  return isBox(top) and top.text or nil
end

-- on foot, somewhere cycling is allowed: one A press mounts
do
  music = {}
  local game = freshGame()
  local list, seen, why = chooseOnce(game, "BICYCLE")
  if check(list ~= nil, "the bag opened on the BICYCLE row: " .. tostring(why)) then
    check(not sawMenu(seen),
          "no USE/TOSS Menu was pushed, not even for a frame (:340-342)")
    eq(game.save.onBike, true, "the single press mounted the bike")
    local said = boxText(game)
    if check(said ~= nil, "and printed a line") then
      check(said:find("got on", 1, true) ~= nil,
            "which is the mount text: " .. tostring(said))
    end
    eq(game.save.inventory.BICYCLE, 1, "the bike is still in the bag")
    eq(#music, 1, "the bike theme was cued once")
    check(music[1] and music[1][2] == true, "as the riding track")
  end
end

-- already riding: the same single press dismounts
do
  music = {}
  local game = freshGame({ onBike = true })
  local list, seen = chooseOnce(game, "BICYCLE")
  if check(list ~= nil, "the bag opened while riding") then
    check(not sawMenu(seen), "still no option box on the way off the bike")
    eq(game.save.onBike, false, "one press dismounted")
    local said = boxText(game)
    if check(said ~= nil, "and printed a line") then
      check(said:find("got off", 1, true) ~= nil,
            "which is the dismount text: " .. tostring(said))
    end
    check(music[1] and music[1][2] == false, "and the map theme came back")
  end
end

-- Cycling Road: the refusal is reached on the same single press, and the
-- item list stays open behind it (`jp ItemMenuLoop`, #513)
do
  local game = freshGame({ onBike = true, forcedBike = true })
  local list, seen = chooseOnce(game, "BICYCLE")
  if check(list ~= nil, "the bag opened on the Cycling Road") then
    check(not sawMenu(seen), "the refusal is not behind an option box either")
    eq(game.save.onBike, true, "and the player is still riding")
    local said = boxText(game)
    if check(said ~= nil, "the refusal printed") then
      check(said:find("get off", 1, true) ~= nil,
            "with _CannotGetOffHereText: " .. tostring(said))
    end
    check(inStack(game, function(s) return s == list end),
          "the bag list is still on the stack under it (#513)")
  end
end

-- somewhere cycling is not allowed: still one press, still no box
do
  local game = freshGame()
  game.overworld.map = { id = "FIX_INDOORS", def = { tileset = "FIX_HOUSE" } }
  local list, seen = chooseOnce(game, "BICYCLE")
  if check(list ~= nil, "the bag opened indoors") then
    check(not sawMenu(seen), "the no-cycling refusal skips the box too")
    eq(game.save.onBike, nil, "and nothing was mounted")
    local said = boxText(game)
    check(said ~= nil and said:find("cycling", 1, true) ~= nil,
          "NoCyclingAllowedHere printed: " .. tostring(said))
  end
end

-- the control cases: everything else still gets USE/TOSS, key items included
do
  local game = freshGame()
  local list, seen = chooseOnce(game, "FIX_POTION")
  if check(list ~= nil, "the bag opened on a plain item") then
    check(sawMenu(seen), "an ordinary item still opens the option box")
    check(isMenu(game.stack:top()), "and it is what the A press left on top")
  end
end

do
  local game = freshGame()
  local list, seen = chooseOnce(game, "TOWN_MAP")
  if check(list ~= nil, "the bag opened on the TOWN MAP") then
    check(sawMenu(seen),
          "another key item still gets the box: pokered special-cases the "
          .. "BICYCLE by id, not key items as a class")
  end
end

-- the box the bike no longer opens is the only route to TOSS, so the bike
-- cannot be thrown away from the bag at all
do
  local game = freshGame()
  local list, seen = chooseOnce(game, "BICYCLE")
  if check(list ~= nil, "the bag opened on the BICYCLE row") then
    local rows = {}
    for _, s in ipairs(seen or {}) do
      for _, it in ipairs((isMenu(s) and s.items) or {}) do
        rows[#rows + 1] = tostring(it.label)
      end
    end
    eq(#rows, 0, "the press offered no menu rows at all, TOSS included")
    eq(game.save.inventory.BICYCLE, 1, "and the bike survives the press")
  end
end

package.loaded["src.core.Sound"] = nil
package.loaded["src.core.Music"] = nil
package.loaded["src.render.TextBox"] = nil
package.loaded["src.ui.BagMenu"] = nil
require("src.ui.Screens").invalidate()

T.finish()
