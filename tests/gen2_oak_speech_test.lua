-- Gen 2 Oak speech extract + stub UI smoke against a Gold cache.
--   luajit tests/gen2_oak_speech_test.lua
-- Also dofile'd by tests/run_tests.lua.  Skips when no gold cache / oak_speech.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 oak speech")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

do
  local OakSpeech = require("src.ui.gen2.OakSpeech")
  local stub = {
    save = { player = { name = "GOLD", rival = "???" } },
    data = { tokens = require("src.render.TextBox").TOKENS, audio = {} },
    stack = { push = function() end, pop = function() end, top = function() end },
    input = { wasPressed = function() return false end },
  }
  local speech = OakSpeech.new(stub, { data = { text = {
    _OakText7 = "{PLAYER}, are you\nready?\fI'll be seeing you\nlater!{DONE}",
  } } })
  local lines = speech:lastPageLines("_OakText7")
  eq(#lines, 2, "the shrink page keeps its two rows")
  eq(lines[1], "I'll be seeing you", "row one of the shrink page")
  eq(lines[2], "later!", "DoneText leaves no glyph on row two")
  check(not table.concat(lines, "|"):find("DONE", 1, true),
    "the {DONE} terminator never reaches Font.draw")
  local prompt = OakSpeech.new(stub, { data = { text = {
    _OakText7 = "See you!{PROMPT}",
  } } })
  eq(prompt:lastPageLines("_OakText7")[1], "See you!",
    "nor does {PROMPT}")
end

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end

local path = cache .. "/data/generated/oak_speech.lua"
local file = io.open(path, "r")
if not file then
  check(true, "gold oak_speech.lua absent : re-import Gold (SKIP)")
  S.finish()
  return
end
file:close()

local data = assert(loadfile(path))()
check(data.generation == 2, "oak_speech.generation is 2")
eq(data.music, "Music_Route30", "speech music is Music_Route30")
eq(data.demoSpecies, "MARILL", "demo mon is MARILL")
check(type(data.oakPic) == "string", "oakPic path present")
check(type(data.playerPic) == "string", "playerPic (Cal) path present")
check(type(data.marillPic) == "string", "marillPic path present")

local texts = data.text or {}
for i = 1, 7 do
  local key = ("_OakText%d"):format(i)
  check(type(texts[key]) == "string", key .. " extracted")
end
check(texts._OakText1:find("OAK", 1, true), "_OakText1 mentions OAK")
check(texts._OakText2:find("POKé", 1, true) or texts._OakText2:find("MON", 1, true),
  "_OakText2 mentions POKéMON")
check(texts._OakText6:find("name", 1, true), "_OakText6 asks for name")
check(texts._OakText7:find("{PLAYER}", 1, true)
  or texts._OakText7:find("PLAYER", 1, true),
  "_OakText7 addresses player")

local function assetExists(rel)
  local f = io.open(cache .. "/" .. rel, "rb")
  if f then f:close() return true end
  return false
end
check(assetExists("assets/generated/intro/oak.png"), "intro/oak.png on disk")
check(assetExists("assets/generated/intro/cal.png"), "intro/cal.png on disk")
check(assetExists("assets/generated/battle/front/marill.png"),
  "battle/front/marill.png on disk")

-- Stub UI constructs without LOVE graphics errors under the stub.
local OakSpeech = require("src.ui.gen2.OakSpeech")
local speech = OakSpeech.new({
  save = { player = { name = "GOLD", rival = "???" } },
  data = { tokens = require("src.render.TextBox").TOKENS, audio = {} },
  stack = { push = function() end, pop = function() end, top = function() end },
  input = { wasPressed = function() return false end },
  fontData = nil,
}, { data = data })
eq(speech.music, "Music_Route30", "UI reads speech music")
check(speech:text("_OakText1"):find("OAK", 1, true), "UI text() serves _OakText1")
check(type(speech:text("_OakText3")) == "string", "_OakText3 is a string (may be empty)")

S.finish()
