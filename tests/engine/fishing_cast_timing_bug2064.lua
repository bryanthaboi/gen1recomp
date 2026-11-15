-- engine/items/item_effects.asm:1893
-- engine/overworld/player_animations.asm:378, :453
--   luajit tests/engine/fishing_cast_timing_bug2064.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local ItemEffects = require("src.inventory.ItemEffects")
local OverworldState = require("src.world.OverworldController")

check(type(ItemEffects.itemUseLine) == "function",
      "ItemEffects exports the used-line helper")
local USE_TEXT = { _ItemUseText001 = "{PLAYER} used{DONE}",
                   _ItemUseText002 = "{RAM:wStringBuffer}!{DONE}",
                   _NoNibbleText = "Not even a nibble!",
                   _NothingHereText = "Looks like there's\nnothing here.",
                   _ItsABiteText = "Oh!\nIt's a bite!" }
eq(ItemEffects.itemUseLine({ text = USE_TEXT }, { player = { name = "RED" } }, "OLD ROD"),
   "RED used\nOLD ROD!", "it is the _ItemUseText001 line")

local function setUpvalue(fn, name, value)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then
      debug.setupvalue(fn, i, value)
      return true
    end
    i = i + 1
  end
end


eq(OverworldState.fishAnimFrames(false), 190, "no bite: 80 + 10 + 100 frames")
eq(OverworldState.fishAnimFrames(true), 280, "a bite adds 30 shake + 60 bubble")

local function runSteps(bite)
  local fa, evs = { frames = 0, bite = bite }, {}
  for i = 1, OverworldState.fishAnimFrames(bite) do
    local ev = OverworldState.stepFishAnim(fa)
    if ev then evs[#evs + 1] = { ev, i } end
  end
  return evs
end

local dry = runSteps(false)
eq(#dry, 2, "a dry cast is exactly two events")
eq(dry[1][1] .. "@" .. dry[1][2], "cast@90", "the pose goes up on frame 90")
eq(dry[2][1] .. "@" .. dry[2][2], "verdict@190", "the verdict lands on frame 190")

local wet = runSteps(true)
eq(wet[1][1] .. "@" .. wet[1][2], "cast@90", "a bite casts on the same frame")
local shakes, bubbleAt, verdictAt = 0, nil, nil
for _, e in ipairs(wet) do
  if e[1] == "shake" then shakes = shakes + 1 end
  if e[1] == "bubble" then bubbleAt = e[2] end
  if e[1] == "verdict" then verdictAt = e[2] end
end
eq(shakes, 10, ".ShakePlayerSprite toggles ten times (b = 10, Delay3)")
eq(bubbleAt, 221, "the bubble opens right after the 30 shake frames")
eq(verdictAt, 280, "and the text waits out the 60-frame bubble")


local function fakeOw(facing)
  return setmetatable({ player = { facing = facing or "right", px = 0, py = 0 },
                        map = { id = "VIRIDIAN_CITY" } },
                      { __index = OverworldState })
end

local ow = fakeOw("right")
local fa = { frames = 0, bite = true }
for i = 1, 89 do
  OverworldState.tickFishAnim(ow, fa)
  if i == 89 then
    check(ow.fishing == nil and ow.player.fishing == nil,
          "the rod and pose stay down for the whole used-line hold")
  end
end
OverworldState.tickFishAnim(ow, fa)
check(ow.fishing ~= nil and ow.fishing.facing == "right",
      "the cast raises the rod OAM for the faced direction")
eq(ow.player.fishing, true, "and the fishing pose with it")

local shakeSeen = {}
for _ = 91, 220 do
  OverworldState.tickFishAnim(ow, fa)
  if ow.player.fishShakeDy then shakeSeen[ow.player.fishShakeDy] = true end
end
check(shakeSeen[1], "the sprite offsets 1px during the shake")
eq(ow.player.fishShakeDy, 0, "an even toggle count leaves it level again")

OverworldState.tickFishAnim(ow, fa)
check(ow.emote ~= nil and ow.emote.npc == ow.player,
      "the bubble hold is an emote over the player")
eq(ow.emote and ow.emote.frames, 60, "EmotionBubble's 60-frame DelayFrames")
eq(ow.emote and ow.emote.bubble, 1, "EXCLAMATION_BUBBLE")
eq(ow.player.fishShakeDy, nil, "the shake offset is cleared for it")
for _ = 222, 280 do OverworldState.tickFishAnim(ow, fa) end
eq(ow.emote, nil, "the bubble is gone when the verdict prints")
check(ow.fishing ~= nil, "the rod is still up for the verdict box (#321)")

local up = fakeOw("up")
local upFa = { frames = 0, bite = true }
for _ = 1, 221 do OverworldState.tickFishAnim(up, upFa) end
eq(up.fishing.hideRod, true, "facing up parks the rod OAM off the bubble")
for _ = 222, 280 do OverworldState.tickFishAnim(up, upFa) end
eq(up.fishing.hideRod, nil, "and gives it back for the verdict")


local pushed = {}
local FakeBox = { new = function(_, text, onDone, opts)
  local box = { text = text, onDone = onDone, opts = opts }
  return box
end }
local fakeGame = {
  data = { text = USE_TEXT, items = { OLD_ROD = { name = "OLD ROD" },
                     SUPER_ROD = { name = "SUPER ROD" } } },
  save = { player = { name = "RED" } },
  stack = { push = function(_, box) pushed[#pushed + 1] = box end },
}
local pool, encStub
check(setUpvalue(OverworldState.goFishing, "Game", fakeGame), "Game is swappable")
check(setUpvalue(OverworldState.goFishing, "TextBox", FakeBox), "TextBox is swappable")
check(setUpvalue(OverworldState.goFishing, "fishingPool",
                 function() return pool end), "fishingPool is swappable")
check(setUpvalue(OverworldState.goFishing, "catchFrom",
                 function() return encStub end), "catchFrom is swappable")

local function cast(rod, ow2)
  pushed = {}
  OverworldState.goFishing(ow2, rod)
  return pushed[1]
end

encStub = { species = "MAGIKARP", level = 5 }
local bite = cast("OLD_ROD", fakeOw("down"))
eq(bite.text, "RED used\nOLD ROD!", "the box prints the used line, not dots")
check(bite.opts and bite.opts.auto, "it is an auto box (no A press to skip)")
eq(bite.opts.auto.wait, false, "text_end: no trailing button wait")
eq(bite.opts.auto.delay, 280, "a bite holds the box for the whole animation")
check(type(bite.opts.auto.sound) == "function", "SFX_HEAL_AILMENT rides the box")
check(type(bite.opts.auto.tick) == "function", "the cast is driven per frame")

encStub = nil
pool = nil
local dryBox = cast("OLD_ROD", fakeOw("down"))
eq(dryBox.opts.auto.delay, 190, "a dry cast holds 190 frames")


local vow = fakeOw("down")
pushed = {}
OverworldState.fishVerdict(vow, nil, false)
eq(pushed[1].text, "Not even a nibble!", "no bite on a map with a group")
pushed[1].onDone()
eq(vow.fishing, nil, "the rod OAM goes out with the box")
eq(vow.fishPose, 10, "the pose holds the #384 tail")

pushed = {}
OverworldState.fishVerdict(vow, nil, true)
eq(pushed[1].text, "Looks like there's\nnothing here.",
   "wRodResponse = 2 prints _NothingHereText (item_effects.asm:2855)")

pushed = {}
OverworldState.fishVerdict(vow, { species = "MAGIKARP", level = 5 }, false)
eq(pushed[1].text, "Oh!\nIt's a bite!", "a hooked fish announces itself")

pool = nil
local nothing = cast("SUPER_ROD", fakeOw("down"))
pushed = {}
nothing.onDone()
eq(pushed[1].text, "Looks like there's\nnothing here.",
   "a SUPER ROD on a group-less map says nothing here")
pool = { { species = "TENTACOOL", level = 15 } }
local nibble = cast("SUPER_ROD", fakeOw("down"))
pushed = {}
nibble.onDone()
eq(pushed[1].text, "Not even a nibble!",
   "a SUPER ROD on a real group that rolled nothing says not even a nibble")

T.finish("fishing_cast_timing_bug2064")
