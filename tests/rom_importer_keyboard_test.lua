-- Mobile soft keyboard: LOVE only delivers love.textinput while
-- setTextInput(true) is active, and that call is what raises the Android/iOS
-- keyboard.  The launcher's text fields -- the add-mod-index prompt (#578),
-- the mod search field and the save-slot rename modal (#205) -- must raise it
-- while the field is up and lower it when it closes; desktop has text input on
-- by default and must be left alone (mirrors tools/save-editor/Kit.lua).
-- Self-contained: `luajit tests/rom_importer_keyboard_test.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer soft keyboard")
local eq = S.eq
local check = S.check

local RomImporter = require("src.import.RomImporter")

local saved = love.keyboard.setTextInput

local calls = {}
love.keyboard.setTextInput = function(enabled, x, y, w, h)
  calls[#calls + 1] = { enabled = enabled, x = x, y = y, w = w, h = h }
end

local function freshImporter(android)
  return setmetatable({
    android = android == nil and true or android,
    tab = "find",
    slots = {},
    pulse = 0,
    _padAxis = {},
    _padDir = {},
    _findSearchFocus = false,
  }, RomImporter)
end

-- No field up: the keyboard stays down.
calls = {}
local ri = freshImporter()
ri:update(0.016)
eq(#calls, 0, "no field means no keyboard")

-- Opening the add-an-index prompt raises the keyboard over the field (#578).
calls = {}
ri = freshImporter()
ri:_promptAddIndex()
ri:update(0.016)
eq(#calls, 1, "prompt raises the keyboard")
eq(calls[1].enabled, true, "prompt enables text input")
check(calls[1].x == math.floor(calls[1].x)
  and calls[1].y == math.floor(calls[1].y),
  "prompt passes an integer field rect")

-- Closing the prompt lowers it again.
ri._indexPrompt = nil
ri:update(0.016)
eq(#calls, 2, "closing the prompt lowers the keyboard")
eq(calls[2].enabled, false, "prompt close disables text input")

-- The search field raises and lowers the same way, over its own rect.
calls = {}
ri = freshImporter()
ri.findSearchRect = { x = 40, y = 80, width = 300, height = 30 }
ri._findSearchFocus = true
ri:update(0.016)
eq(#calls, 1, "search focus raises the keyboard")
eq(calls[1].enabled, true, "search focus enables text input")
eq(calls[1].x, 40, "search raises over the field rect")
eq(calls[1].y, 80, "search raises over the field rect")
ri._findSearchFocus = false
ri:update(0.016)
eq(#calls, 2, "search blur lowers the keyboard")
eq(calls[2].enabled, false, "search blur disables text input")

-- The save-slot rename modal raises over its own rect (#205).
calls = {}
ri = freshImporter()
ri:_beginRename("red", "missing")
ri:update(0.016)
eq(#calls, 1, "rename modal raises the keyboard")
eq(calls[1].enabled, true, "rename enables text input")
ri._rename = nil
ri:update(0.016)
eq(#calls, 2, "closing the rename modal lowers the keyboard")
eq(calls[2].enabled, false, "rename close disables text input")

-- Desktop is untouched: no field needs a raise, and a modal must not lower
-- anything either (setTextInput is global SDL state).
calls = {}
ri = freshImporter(false)
ri:_promptAddIndex()
ri:update(0.016)
eq(#calls, 0, "desktop never touches the soft keyboard")

love.keyboard.setTextInput = saved
S.finish()
