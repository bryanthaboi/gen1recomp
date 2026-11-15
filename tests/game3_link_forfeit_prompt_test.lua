package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if cond then print("[ok] " .. msg) else failed = failed + 1; print("[FAIL] " .. msg) end
end

require("src.core.game3.profile").reset()
require("src.core.GameVersion").set("firered")

local BattleText = require("src.core.game3.battle.battle_text")
local realGet = BattleText.get
BattleText.get = function(key, ...)
  if key == "STRINGID_QUESTIONFORFEITMATCH" then return "<ROM QUESTIONFORFEITMATCH>" end
  return realGet(key, ...)
end

local Ui = require("src.core.game3.battle.ui")
local Commands = require("src.core.game3.battle.commands")

local function runIndex()
  for i, k in ipairs(Commands.MENU) do if k == "RUN" then return i end end
end

local function press(key)
  return { wasPressed = function(_, k) return k == key end, isDown = function() return false end }
end

local function run(st)
  local asked
  local realAsk = Ui.askYesNo
  Ui.askYesNo = function(prompt) asked = prompt end
  Ui._headless = false
  Ui._st = st
  Ui._mode = "menu"
  Ui._menuIndex = runIndex()
  Ui._active = 0
  Ui._actionCursor = Ui._actionCursor or {}
  Ui._pendingCommand = nil
  local ok, err = pcall(Ui.handleInput, press("a"))
  Ui.askYesNo = realAsk
  if not ok then print("[info] " .. tostring(err)) end
  return asked
end

local frontier = run({ link = false, wild = false, kinds = { frontier = true }, player = { mon = {} } })
check(frontier == "<ROM QUESTIONFORFEITMATCH>", "frontier RUN asks STRINGID_QUESTIONFORFEITMATCH from ROM")

local hill = run({ link = false, wild = false, kinds = { trainerHill = true }, player = { mon = {} } })
check(hill == "<ROM QUESTIONFORFEITMATCH>", "trainer hill RUN asks STRINGID_QUESTIONFORFEITMATCH from ROM")

local plain = run({ link = true, wild = false, player = { mon = {} } })
check(type(plain) == "string" and plain ~= "<ROM QUESTIONFORFEITMATCH>",
  "frlg plain link RUN keeps the port forfeit prompt")

local wild = run({ link = false, wild = true, player = { mon = {} } })
check(wild == nil, "wild RUN asks nothing")

if failed > 0 then print(failed .. " failure(s)") os.exit(1) end
print("all passed")
