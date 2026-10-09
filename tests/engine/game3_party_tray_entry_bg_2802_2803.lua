-- pokeemerald/src/battle_interface.c:1450
-- pokeemerald/src/battle_intro.c:86
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local IntroSeq = require("src.core.game3.battle.intro_seq")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")

T.check(type(IntroSeq.entryFrame) == "function", "intro exposes the BG1 entry timeline")
T.check(type(IntroSeq.trayEnterTick) == "function", "intro exposes the party tray sprite callbacks")
if not (IntroSeq.entryFrame and IntroSeq.trayEnterTick) then return T.finish("game3_party_tray_entry_bg_2802_2803") end

local x, y, a = IntroSeq.entryFrame(1, 0, 10)
T.same({ x, y, a }, { 60, 0, 1 }, "grass entry scrolls BG1 6px a frame before the window opens")
x, y = IntroSeq.entryFrame(1, 0, 67)
T.same({ x, y }, { 402, -1 }, "grass entry starts sinking 32 frames after the window band")
x, y = IntroSeq.entryFrame(1, 0, 150)
T.eq(y, -56, "grass entry stops at BG1_Y -56")
x, y = IntroSeq.entryFrame(1, 1, 150)
T.eq(y, -80, "long grass sinks 2px a frame to -80")
T.eq(IntroSeq.entryFrame(1, 0, 154), nil, "entry tilemap cleared when the scanline slide finishes")
x, y, a = IntroSeq.entryFrame(2, 4, 1)
T.same({ x, y, a }, { 8, 0, 1 }, "water entry scrolls 8px with Cos2 bob starting at 0")
x, y = IntroSeq.entryFrame(2, 4, 46)
T.eq(y, -16, "water bob bottoms out at Cos2(180)/512 - 8")
local _, _, a2 = IntroSeq.entryFrame(2, 2, 71)
T.eq(a2, 14 / 16, "sand entry alpha drops one step every 4 frames after the delay")
local _, _, a3 = IntroSeq.entryFrame(3, 8, 10)
T.eq(a3, 8 / 16, "building entry blends at 8/8 from the start")
local _, _, a4 = IntroSeq.entryFrame(3, 8, 73)
T.eq(a4, 6 / 16, "building entry fades one step every 6 frames")

T.same({ IntroSeq.entrySlide({ terrain = 0 }, "grass") }, { 1, 0 }, "grass uses BattleIntroSlide1")
T.same({ IntroSeq.entrySlide({ terrain = 8 }, "frontier") }, { 3, 8 }, "frontier uses BattleIntroSlide3")
T.eq(IntroSeq.entrySlide({ terrain = 0, link = true }, "grass"), nil, "link battles keep the VS frame, not an entry tilemap")

local played = {}
local playSe = Audio.playSe
Audio.playSe = function(id, opts) played[#played + 1] = { id = id, pan = opts and opts.pan } return true end
local bar = IntroSeq.trayEnterState({}, { "ok", "faint", "ok", "empty", "empty", "empty" }, false)
local landed, barHome = {}, nil
for f = 1, 80 do
  local before = #played
  IntroSeq.trayEnterTick(bar, false)
  if bar.ox == 0 and not barHome then barHome = f end
  if #played > before then landed[#landed + 1] = f end
end
T.eq(barHome, 20, "summary bar slides in at 5px per frame")
T.same(landed, { 19, 26, 33, 40, 47, 54 }, "balls land one at a time, 7 frames apart")
T.eq(played[1] and played[1].id, SE.SE_BALL_TRAY_BALL, "filled slot ticks SE_BALL_TRAY_BALL")
T.eq(played[4] and played[4].id, SE.SE_BALL_TRAY_EXIT, "empty slot ticks SE_BALL_TRAY_EXIT")
T.eq(played[1] and played[1].pan, 63, "player tray pans SOUND_PAN_TARGET")
local foe = IntroSeq.trayEnterState({}, { "empty", "empty", "empty", "empty", "empty", "ok" }, true)
played = {}
local first
for f = 1, 80 do
  IntroSeq.trayEnterTick(foe, true)
  if not first and foe.ballState[6].done then first = f end
end
T.eq(first, 26, "opponent rightmost ball goes first after 17 frames")
T.eq(foe.ballState[1].done and #played, 6, "opponent tray ticks once per ball")
Audio.playSe = playSe

local stub = { manifest = function() return { partyBarPlayer = { x = 136 }, partyBarOpponent = { x = 104 } } end }
package.loaded["src.ui.game3.battle_chrome"] = stub
IntroSeq.trayExitState(bar, false)
local alphas, hiddenAt = {}, nil
for f = 1, 40 do
  local done = IntroSeq.trayExitTick(bar, false)
  alphas[f] = bar.alpha
  if not bar.visible and not hiddenAt then hiddenAt = f end
  if done then break end
end
T.eq(alphas[1], 15 / 16, "fade starts at BLDALPHA 15/16")
T.eq(alphas[2], 15 / 16, "blend steps every other frame")
T.eq(alphas[31], 0, "blend reaches 0 after 31 frames")
T.eq(hiddenAt, 32, "tray sprites destroyed the frame after the blend ends")
T.eq(bar.ox, -2 * 34, "player bar slides left 2px per frame on exit")
T.check(bar.extended, "exit uses the stretched subsprite table")
T.check(bar.ballHidden[1] and not bar.ballHidden[6], "leftmost ball leaves first")

T.finish("game3_party_tray_entry_bg_2802_2803")
