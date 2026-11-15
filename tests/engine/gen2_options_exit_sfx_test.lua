-- ../pokecrystal/engine/menus/options_menu.asm:69
--   luajit tests/engine/gen2_options_exit_sfx_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local eq = T.eq

local GameVersion = require("src.core.GameVersion")
local Sound = require("src.core.Sound")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")

local played = {}
local realPlay = Sound.play
Sound.play = function(_, name) played[#played + 1] = name end

local function fakeGame(pressed)
  local game = { data = { audio = { sfx = {} }, text = require("tests.fixture_data.gen2_rom_text_s7_c").text() } }
  game.input = { wasPressed = function(_, key) return key == pressed end }
  game.stack = { items = {} }
  function game.stack:push(s) self.items[#self.items + 1] = s end
  function game.stack:pop() self.items[#self.items] = nil end
  function game.stack:top() return self.items[#self.items] end
  return game
end

local function exitVia(version, key, viaCancelRow)
  GameVersion.set(version)
  played = {}
  local game = fakeGame(key)
  local done = false
  local menu = OptionsMenu.new(game, { onDone = function() done = true end })
  game.stack:push(menu)
  if viaCancelRow then
    menu.index = #menu:visible()
    eq(menu:row().cancel, true, version .. ": last root row is the cancel row")
  end
  menu:update(0)
  eq(done, true, version .. " " .. key .. ": menu closed")
  return played
end

for _, key in ipairs({ "b", "start" }) do
  local p = exitVia("crystal", key)
  eq(#p, 1, "crystal " .. key .. ": one sfx on exit")
  eq(p[1], "Sfx_Transaction", "crystal " .. key .. ": SFX_TRANSACTION on exit")
  eq(#exitVia("gold", key), 0, "gold " .. key .. ": silent exit")
  eq(#exitVia("silver", key), 0, "silver " .. key .. ": silent exit")
end

local p = exitVia("crystal", "a", true)
eq(p[1], "Sfx_Transaction", "crystal CANCEL+A: SFX_TRANSACTION on exit")
eq(#exitVia("gold", "a", true), 0, "gold CANCEL+A: silent exit")

do
  GameVersion.set("crystal")
  played = {}
  local game = fakeGame("b")
  local menu = OptionsMenu.new(game, {})
  game.stack:push(menu)
  menu:focusRow("sfxVol")
  local page = game.stack:top()
  eq(page.sub, true, "sfxVol lives on a group page")
  page:update(0)
  eq(#played, 0, "crystal: backing out of a group page is silent")
  eq(game.stack:top(), menu, "group page popped back to the root")
end

Sound.play = realPlay
GameVersion.set("red")
T.finish()
