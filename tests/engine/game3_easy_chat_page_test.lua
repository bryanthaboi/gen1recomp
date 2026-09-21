-- The Easy Chat word picker pages eight words at a time, the way the cart
-- does (easy_chat_2.c scrolls selectWordRowsAbove by 4, two words per row),
-- and its own navigation moves through four rows.  The draw loop used to
-- render three, so the last two words of every page were selectable -- the
-- cursor could sit on them -- but never drawn, and a group's 7th and 8th
-- words could not be read at all.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

love = require("tests.love_stub")

-- Record what reaches the font instead of drawing it, the same technique
-- tests/engine/gen2_options_menu_translation_test.lua uses.
local drawn = {}
local realFont = require("src.ui.game3.frlg_font")
local stub = setmetatable({}, { __index = realFont })
stub.draw = function(text, x, y) drawn[#drawn + 1] = { text = text, x = x, y = y } end
package.loaded["src.ui.game3.frlg_font"] = stub

local EasyChat = require("src.ui.game3.easy_chat")
local EasyChatData = require("src.core.game3.easy_chat_data")

-- A group with more than eight words, so a full page is drawn.
local group
for _, candidate in pairs(EasyChatData.GROUPS) do
  if candidate.words and #candidate.words > 8 then group = candidate break end
end
check(group ~= nil, "the extracted data has a group with more than one page")

EasyChat.open({ type = 0, words = {} })
local st = EasyChat._state
check(st ~= nil, "the screen is open")
st.mode = "WORD"
st.groups = { group }
st.groupCursor = 1
st.wordPage = 0

drawn = {}
EasyChat.draw()

local shown = {}
for _, row in ipairs(drawn) do shown[row.text] = row.y end
local missing = {}
for index = 1, 8 do
  local word = group.words[index]
  if word and not shown[word.text] then missing[#missing + 1] = word.text end
end
check(#missing == 0, "every word of the page is drawn, got " .. #missing .. " missing")

-- The rows have to stay inside the 78 px frame the screen draws them in.
local frameTop, frameBottom = 76, 76 + 78
local lowest = 0
for index = 1, 8 do
  local word = group.words[index]
  local y = word and shown[word.text]
  if y then
    check(y >= frameTop, "row " .. index .. " starts below the frame top")
    if y > lowest then lowest = y end
  end
end
check(lowest + realFont.GLYPH_HEIGHT <= frameBottom,
  "the last row's glyphs stay inside the frame (" .. lowest + realFont.GLYPH_HEIGHT .. " <= " .. frameBottom .. ")")

EasyChat.close(false)
package.loaded["src.ui.game3.frlg_font"] = realFont

T.finish("game3_easy_chat_page_test")
