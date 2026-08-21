-- OverworldState:tryHiddenObject()'s "%s found\n%s!" message used to
-- substitute both the player name and the item name into one bare Lua
-- literal. The real _FoundHiddenItemText label leads with a {PLAYER}
-- named token, which romText auto-fills from a 2-arg call in the same
-- order the literal already used -- this test checks both slots land
-- correctly (an accidental argument swap is the easy mistake this shape
-- invites).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

local SaveData = require("src.core.SaveData")
local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed = {}
local textBoxStub = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
  soundOpts = function() return {} end,
}

local MAP_ID = "FIX_TOWN"
Data.field.hiddenItems[MAP_ID] = { { x = 3, y = 3, item = "FIX_BALL" } }

local function mkGame()
  local save = SaveData.newGame()
  save.player.name = "FAKEPLAYER"
  pushed = {}
  return {
    data = Data, save = save,
    stack = { push = function(_, item) pushed[#pushed + 1] = item end },
  }
end

T.check(setUpvalue(OW.tryHiddenObject, "Game", mkGame()), "Game upvalue on tryHiddenObject")
T.check(setUpvalue(OW.tryHiddenObject, "TextBox", textBoxStub), "TextBox upvalue on tryHiddenObject")

local fakeSelf = setmetatable({ map = { id = MAP_ID } }, { __index = OW })

-- translated: player name and item name both land in the right slots
do
  local game = mkGame()
  setUpvalue(OW.tryHiddenObject, "Game", game)
  Data.text._FoundHiddenItemText = "FAKE {PLAYER} found FAKE {RAM:wNameBuffer} FAKE!"
  local found = fakeSelf:tryHiddenObject(3, 3)
  T.check(found == true, "the hidden item at (3,3) is found")
  T.eq(pushed[1] and pushed[1].text,
    "FAKE FAKEPLAYER found FAKE FIX BALL FAKE!",
    "a translated _FoundHiddenItemText fills both {PLAYER} and the item name")
  Data.text._FoundHiddenItemText = nil
end

-- vanilla: no catalog entry, so romText falls back to plain
-- Strings(fallback, ...) -- the fallback literal is "%s found\n%s!" (both
-- slots plain %s, matching the pre-fix literal's own shape), not the
-- {PLAYER} token the real label uses, since Strings() never does
-- {TOKEN} substitution on its own. (A {PLAYER}-token fallback would
-- still render correctly too, since the real TextBox.new always runs
-- TextBox.substitute over whatever text it's given -- but this test
-- stubs TextBox without that call, and the fallback shouldn't lean on a
-- substitution pass happening downstream regardless.)
do
  local game = mkGame()
  setUpvalue(OW.tryHiddenObject, "Game", game)
  game.save.hiddenTaken = {} -- fresh spot
  local found = fakeSelf:tryHiddenObject(3, 3)
  T.check(found == true, "the hidden item is found again in a fresh game")
  T.eq(pushed[1] and pushed[1].text, "FAKEPLAYER found\nFIX BALL!",
    "with no catalog entry, the fallback still fills both the player "
    .. "and item name via plain %s substitution")
end

T.finish("overworld_hidden_item_romtext")
