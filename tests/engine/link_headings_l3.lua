-- engine/events/hidden_events/school_blackboard.asm:9-74
--   luajit tests/engine/link_headings_l3.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local savedMenu = package.loaded["src.ui.Menu"]
local savedBox = package.loaded["src.render.TextBox"]
local savedScript = package.loaded["data.scripts.celadon_eevee"]
local Menu = { new = function(_, items, opts)
  return { isMenu = true, items = items, opts = opts }
end }
local TextBox = { new = function(_, text, onDone, opts)
  return { text = text, onDone = onDone, opts = opts }
end }
package.loaded["src.ui.Menu"] = Menu
package.loaded["src.render.TextBox"] = TextBox
package.loaded["data.scripts.celadon_eevee"] = nil
local script = require("data.scripts.celadon_eevee")
package.loaded["src.ui.Menu"] = savedMenu
package.loaded["src.render.TextBox"] = savedBox
package.loaded["data.scripts.celadon_eevee"] = savedScript

local function run(text)
  local stack = {}
  local game = {
    data = { text = text },
    stack = {
      push = function(_, s) stack[#stack + 1] = s end,
      pop = function() return table.remove(stack) end,
      top = function() return stack[#stack] end,
    },
  }
  local handled = script.onInteract(game, {}, 3, 0)
  local intro = stack[1]
  if intro and intro.onDone then intro.onDone() end
  local prompt = stack[#stack]
  if prompt and prompt.opts and prompt.opts.stay then prompt.opts.stay.onShown() end
  return handled, stack
end

local text = {
  _LinkCableHelpText1 = "INTRO", _LinkCableHelpText2 = "PROMPT",
  _LinkCableInfoText1 = "ONE", _LinkCableInfoText2 = "TWO",
  _LinkCableInfoText3 = "THREE",
  HowToLinkText = "ROW A\nROW B\nROW C\nROW D",
}
local handled, stack = run(text)
check(handled == true, "the blackboard tile is handled")
local menu = stack[#stack]
check(menu and menu.isMenu, "the heading menu is pushed after the prompt")
local labels = {}
for i, item in ipairs(menu and menu.items or {}) do labels[i] = item.label end
eq(table.concat(labels, "/"), "ROW A/ROW B/ROW C/ROW D",
   "menu rows are the lines of HowToLinkText")
eq(menu.items[1].keepOpen, true, "a heading keeps the menu open")
eq(menu.items[4].keepOpen, nil, "the fourth row closes the menu")
menu.items[2].onSelect()
eq(stack[#stack].text, "TWO", "the second heading prints _LinkCableInfoText2")

text.HowToLinkText = nil
local ok, err = pcall(run, text)
check(not ok and tostring(err):find("HowToLinkText", 1, true) ~= nil,
      "a cache without HowToLinkText is an error, not built-in headings")

T.finish()
