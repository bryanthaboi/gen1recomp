package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local realRead = love.filesystem.read
love.filesystem.read = function(path, ...)
  if path == "build-info.json" then return nil end
  return realRead(path, ...)
end

local realTime, now = os.time, 1790855999
os.time = function(t)
  if t then return realTime(t) end
  return now
end

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end
love.graphics.polygon = love.graphics.polygon or function() end
love.graphics.getDimensions = function() return 1280, 720 end
love.graphics.getPixelDimensions = function() return 1280, 720 end
love.mouse.getPosition = function() return -100, -100 end
love.mouse.isDown = function() return false end

local SaveData = require("src.core.SaveData")
local options = {}
SaveData.loadOptions = function() return options end
SaveData.saveOptions = function(patch)
  for k, v in pairs(patch) do options[k] = v end
  return options
end

local Kit = require("src.ui.kit.Kit")
local Transition = require("src.ui.kit.Transition")
local GameVersion = require("src.core.GameVersion")
local SecretGames = require("src.import.SecretGames")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

SecretGames.reload()
check(not SecretGames.visible("emerald"), "emerald starts locked")

local function newLauncher(tab)
  local imp = RomImporter.new(function() end, { launcher = true })
  for _, v in ipairs(GameVersion.ORDER) do imp.ready[v] = true end
  imp._flex = true
  imp.tab = tab
  return imp
end

local function press(imp, key)
  Transition.reset()
  Kit.focus = nil
  imp:keypressed(key)
  Transition.reset()
  return imp.tab
end

local imp = newLauncher("red")
eq(press(imp, "e"), "blue", "E steps from Red to the next game")
eq(press(imp, "e"), "yellow", "E again steps to Yellow")
eq(press(imp, "q"), "blue", "Q steps back to the previous game")
eq(press(imp, "q"), "red", "Q again is back on Red")
eq(press(imp, "q"), "sapphire", "Q from the first game wraps to the last visible game (Emerald locked)")
eq(press(imp, "e"), "red", "E from Sapphire wraps to Red, skipping locked Emerald")

local games = LauncherView.gameTabs(imp)
local walked, seen = {}, {}
imp.tab = games[1].id
for _ = 1, #games do
  local t = press(imp, "e")
  walked[#walked + 1] = t
  seen[t] = true
end
eq(walked[#walked], games[1].id, "E walks every dropdown game once and wraps")
for _, g in ipairs(games) do
  check(seen[g.id], "the cycle visits " .. g.id)
end
for _, tab in ipairs(LauncherView.HEADER_TABS) do
  check(not seen[tab.id], "the cycle never lands on the " .. tab.id .. " tab")
end

local mods = newLauncher("mods")
mods.modScope = "gold"
eq(press(mods, "e"), "silver", "from MODS scoped to Gold, E opens Silver")
local box = newLauncher("box")
box.modScope = "gold"
eq(press(box, "q"), "yellow", "from BOX scoped to Gold, Q opens Yellow")

local popup = newLauncher("red")
popup._gamePopup = true
eq(press(popup, "e"), "blue", "E works while the Choose game popup is open")
eq(popup._gamePopup, nil, "and closes the popup")

local guards = {
  { "the FIND search field", "find", function(i) i._findSearchFocus = true end },
  { "the ID sync code field", "red", function(i) i._syncModal = { step = "enter" }; i._syncFocus = "code1" end },
  { "a rename prompt", "red", function(i) i._rename = { version = "red", slot = "1", text = "" } end },
  { "an online text field", "online", function(i) i._onlineFocus = "name" end },
  { "the sort popup", "mods", function(i) i._sortPopup = "mods" end },
  { "the skin URL field", "skins", function(i) i._skinUrlFocus = true end },
}
for _, g in ipairs(guards) do
  for _, key in ipairs({ "q", "e" }) do
    local i = newLauncher(g[2])
    g[3](i)
    Transition.reset()
    i:keypressed(key)
    eq(i.tab, g[2], key:upper() .. " does nothing while " .. g[1] .. " is up")
  end
end

local search = newLauncher("box")
Transition.reset()
Kit.focus = "box-search"
search:keypressed("e")
eq(search.tab, "box", "E does nothing while the BOX search field has focus")
Kit.focus = nil

local busy = newLauncher("red")
busy.workState = "working"
Transition.reset()
busy:keypressed("e")
eq(busy.tab, "red", "E does nothing while an import is working")

now = SecretGames.EMERALD_RELEASE_AT
SecretGames.reload()
check(SecretGames.visible("emerald"), "emerald unlocks at release")
local open = newLauncher("sapphire")
eq(press(open, "e"), "emerald", "unlocked: E from Sapphire opens Emerald")
eq(press(open, "e"), "red", "and E from Emerald wraps to Red")
eq(press(open, "q"), "emerald", "Q from Red wraps to Emerald")

os.time = realTime
T.finish("launcher game hotkeys")
