-- #578: the launcher's "Add an index" prompt (and the rename / find-search
-- fields) accepted no typing on Android, because nothing ever called
-- love.keyboard.setTextInput(true) -- mobile LOVE only delivers
-- love.textinput while it is armed.  Every site that opens a text field must
-- arm, every site that closes one must disarm, and disarm must be a no-op on
-- desktop where the hosted save editor depends on text input staying on
-- (tools/save-editor/Kit.lua, #529).  A touch screen also has no ctrl+V, so
-- the prompt grew a PASTE chip; both paste paths share _pasteIndexUrl and
-- both honor the whitespace strip and the MAX_INDEX_URL cap.
--   luajit tests/engine/launcher_text_input_bug578.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- record every setTextInput transition; the assertions read this log
local textInputLog = {}
love.keyboard.setTextInput = function(on)
  textInputLog[#textInputLog + 1] = on
end
local function lastArm() return textInputLog[#textInputLog] end

local clipboard = ""
love.system = love.system or {}
love.system.getClipboardText = function() return clipboard end

-- _commitAddIndex hands the typed URL to ModIndex.addSource; a canned
-- failure keeps the commit path off the network and out of options.lua
local addSourceUrl = nil
package.loaded["src.mods.ModIndex"] = {
  addSource = function(url) addSourceUrl = url return nil, "offline" end,
}
-- _commitRename goes through SaveData.renameSlot; record the call
local renamed = nil
package.loaded["src.core.SaveData"] = {
  renameSlot = function(version, id, text) renamed = { version, id, text } end,
}

local RomImporter = require("src.import.RomImporter")

local ri = setmetatable({
  android = true, workState = nil, tab = "find",
  ready = {}, slots = { red = { { id = "s1", label = "OLD" } } },
  slotScroll = {}, activeSlot = {},
}, RomImporter)
ri._refreshSlots = function() end -- rename commit relists; nothing to relist

-- ---- index prompt: arm on open, disarm on escape and on commit ------------

ri:_promptAddIndex()
check(ri._indexPrompt ~= nil, "the add-index prompt opens")
eq(lastArm(), true, "opening the prompt arms setTextInput (#578)")

-- typed input strips whitespace (URLs never contain a literal space)
ri:textinput("https://ex ample.com\n/idx")
eq(ri._indexPrompt.text, "https://example.com/idx",
   "typed input lands with whitespace stripped")

ri:keypressed("escape")
check(ri._indexPrompt == nil, "escape closes the prompt")
eq(lastArm(), false, "and disarms setTextInput")

ri:_promptAddIndex()
ri._indexPrompt.text = "https://example.com/index.json"
ri:keypressed("return")
check(ri._indexPrompt == nil, "enter commits and closes the prompt")
eq(lastArm(), false, "commit disarms setTextInput too")
eq(addSourceUrl, "https://example.com/index.json",
   "the committed text reaches ModIndex.addSource")
check(ri.findNotice and ri.findNotice.ok == false,
      "a rejected source surfaces as a notice, not a crash")

-- ---- PASTE chip: same entry point the touch screen uses -------------------

ri:_promptAddIndex()
-- the prompt's Paste button (LauncherView) queues _pasteIndexUrl, the same
-- funnel ctrl/cmd+V uses, so both paths share the strip and the cap
clipboard = "  https://example.com/mods/index.json\n"
ri:_pasteIndexUrl()
eq(ri._indexPrompt.text, "https://example.com/mods/index.json",
   "the PASTE chip lands the clipboard with whitespace stripped (#578)")

-- the cap holds through the button path: a 300-char clipboard cannot
-- overflow MAX_INDEX_URL (200)
ri._indexPrompt.text = ""
clipboard = string.rep("a", 300)
ri:_pasteIndexUrl()
eq(#ri._indexPrompt.text, 200, "the PASTE chip enforces MAX_INDEX_URL")

-- and through ctrl/cmd+V, which used to skip the cap entirely
ri._indexPrompt.text = ""
local savedIsDown = love.keyboard.isDown
love.keyboard.isDown = function() return true end
ri:keypressed("v")
love.keyboard.isDown = savedIsDown
eq(#ri._indexPrompt.text, 200, "ctrl+V routes through the same cap (#578)")
ri:keypressed("escape")

-- ---- rename field: arm on open, disarm on escape and on commit ------------

ri:_beginRename("red", "s1")
check(ri._rename ~= nil, "the rename modal opens")
eq(lastArm(), true, "opening the rename arms setTextInput")
ri:keypressed("escape")
check(ri._rename == nil, "escape closes the rename")
eq(lastArm(), false, "and disarms setTextInput")

ri:_beginRename("red", "s1")
ri:textinput("!")
ri:keypressed("return")
eq(lastArm(), false, "committing the rename disarms setTextInput")
eq(renamed and renamed[3], "OLD!", "the commit reaches SaveData.renameSlot")

-- ---- find-search field: arm on focus, disarm on escape / tab change -------

-- the search field's click handler (LauncherView) takes focus and arms;
-- drive the same pair the handler queues
ri._findSearchFocus = true
ri:_armTextInput()
eq(lastArm(), true, "focusing the search field arms setTextInput")
ri:keypressed("escape")
check(ri._findSearchFocus == false, "escape drops the search caret")
eq(lastArm(), false, "and disarms setTextInput")

-- switching tabs (chips, shoulder buttons) also drops the caret and disarms
ri._findSearchFocus = true
ri:_armTextInput()
eq(lastArm(), true, "refocus for the tab-change case")
ri:_switchTab("mods")
check(ri._findSearchFocus == false, "a tab change drops the caret")
eq(lastArm(), false, "and disarms setTextInput")
ri.tab = "find"

ri:_toggleFindSearchFocus()
check(ri._findSearchFocus == true, "tapping the search field focuses it")
eq(lastArm(), true, "refocusing the search field arms setTextInput")
ri:_toggleFindSearchFocus()
check(ri._findSearchFocus == false, "tapping the focused search field blurs it")
eq(lastArm(), false, "blurring the search field disarms setTextInput")

-- ---- desktop contract (#529): disarm never lowers off Android -------------

ri.android = false
ri:_promptAddIndex()
eq(lastArm(), true, "desktop still arms (harmless, already on)")
local before = #textInputLog
ri:keypressed("escape")
eq(#textInputLog, before,
   "desktop disarm is a no-op: the hosted save editor keeps text input on "
   .. "(#529)")

T.finish("launcher_text_input_bug578")
