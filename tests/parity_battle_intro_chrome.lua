-- Parity test: the battle intro's pokeball rows, HUD chrome and pic slides
-- (#317).  PrintBeginningBattleText calls DrawAllPokeballs right before
-- PrintText (engine/battle/common_text.asm:22-27), and a wild battle gets the
-- player's row only (engine/battle/draw_hud_pokeball_gfx.asm:1-7); the enemy
-- HUD comes up after, in _InitBattleCommon (engine/battle/core.asm:6755-6764).
-- Both pics slide off screen before their send-out text (core.asm:236-240, 1308-1310).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity battle intro chrome")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end
local Font = require("src.render.Font")
Font.load(Data)

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local Timing = require("src.core.Timing")

-- Silence audio: BattleState reaches both modules through require() at the
-- call site, so patching the fields here is what the battle ends up calling.
Sound.playCry = function() end
Sound.play = function() end
Sound.playMove = function() end
Sound.playMoveCry = function() end
Sound.stopLoop = function() end
Music.playBattle = function() end
Music.play = function() end

-- stub stack + input, like the other headless battle probes.  `press` is the
-- one-frame button state the battle reads through input:wasPressed.
local press = {}
local function makeGame(party)
  local save = SaveData.newGame()
  save.party = party
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  -- isDown as well as wasPressed: battle text collapses PrintLetterDelay
  -- while A or B is held, and the typing path reads it every frame
  return { data = Data, save = save, stack = stack,
           input = { wasPressed = function(_, b) return press[b] == true end,
                     isDown = function(_, b) return press[b] == true end } }
end

-- One fixed step with A held.  updateQueue only reads the button once a page
-- has typed out, so an early press is ignored and these ordering checks stay
-- independent of the prompt flag they also assert.
local function step(battle)
  press.a = true
  battle:update(1 / 60)
  press.a = false
end

-- the text of the message row currently on screen, or nil
local function currentText(battle)
  local cur = battle.current
  return cur and cur.text or nil
end

-- Record what drawHUDs actually puts on screen this frame.  drawBallRow is a
-- method, so an instance field shadows it; Font.draw is the module upvalue
-- BattleState draws HUD strings through.
local function snapshotHUD(battle)
  local rows, strings = {}, {}
  local realRow = battle.drawBallRow
  local realFont = Font.draw
  battle.drawBallRow = function(_, party, x, y, dx)
    rows[#rows + 1] = { count = #party, x = x, y = y, step = dx }
  end
  Font.draw = function(text, x, y) strings[#strings + 1] = tostring(text) end
  local ok, err = pcall(battle.drawHUDs, battle, 0)
  battle.drawBallRow = realRow
  Font.draw = realFont
  return ok, err, rows, strings
end

local function drewString(strings, want)
  for _, s in ipairs(strings) do
    if s:find(want, 1, true) then return true end
  end
  return false
end

-- ------------------------------------------------------------------ wild
local party = { Pokemon.new(Data, "BULBASAUR", 50), Pokemon.new(Data, "PIDGEY", 5) }
local game = makeGame(party)
local wild = BattleState.newWild(game, "RATTATA", 2)
wild.onFinish = function() end
wild:enter()

eq(wild.introBalls, true, "the wild intro opens the DrawAllPokeballs window")
-- introBalls is a plain field, not a queue row, so it cannot displace the
-- wild cry PrintBeginningBattleText plays before PrintText (#303)
check(wild.queue[1] and wild.queue[1].fn ~= nil,
      "the cry act is still the first queue row (#303)")
check(wild.queue[2] and wild.queue[2].text == wild.introText,
      "the intro text is still the second queue row")

-- let the silhouette slide land so the intro box is genuinely up (the slide
-- now runs 80 frames at 2px/frame, matching the original ~2px/frame)
for _ = 1, 85 do wild:update(1 / 60) end
eq(wild.introSlide or 0, 0, "the silhouette slide has landed")
eq(wild.introBalls, true, "the window is still open under the intro text")
eq(currentText(wild), wild.introText, "the intro box is the row on screen")

local ok, err, rows, strings = snapshotHUD(wild)
check(ok, "drawHUDs runs during the wild intro: " .. tostring(err))
eq(#rows, 1, "a WILD intro draws exactly one ball row (SetupOwnPartyPokeballs)")
if rows[1] then
  eq(rows[1].count, #party, "the row carries every party slot")
  eq(rows[1].x, 88, "player ball row x = 88 (wBaseCoordX $60)")
  eq(rows[1].y, 80, "player ball row y = 80 (wBaseCoordY $60)")
  eq(rows[1].step, 8, "player ball row steps +8 rightward")
end
check(not drewString(strings, wild.enemy.name),
      "the enemy HUD is NOT up during the intro box (DrawEnemyHUDAndHPBar "
      .. "runs after PrintBeginningBattleText returns)")

-- the page finishes typing and PromptText's blinking arrow takes over
local prompted = false
for _ = 1, 200 do
  if wild.msgPrompt then prompted = true break end
  press.a = false
  wild:update(1 / 60)
end
check(prompted, "a typed-out intro page raises the prompt flag (blinking arrow)")
eq(wild.introBalls, true, "the ball row is still up while the arrow blinks")

-- PromptText writes the arrow and then runs ProtectedDelay3 before
-- ManualTextScroll starts watching the joypad (home/text.asm:213-217), so the
-- page ignores the button for TEXT_PRE_ADVANCE frames.  The loop above breaks
-- on the frame the arrow goes up, which is inside that hold.
for _ = 1, Timing.TEXT_PRE_ADVANCE do press.a = false wild:update(1 / 60) end

-- press A: ClearSprites + both ClearScreenAreas, then the enemy HUD
step(wild)
eq(wild.msgPrompt, nil, "the prompt flag clears on the A press")
for _ = 1, 2 do press.a = false wild:update(1 / 60) end
eq(wild.introBalls, nil, "dismissing the intro box closes the window")
local ok2, err2, rows2, strings2 = snapshotHUD(wild)
check(ok2, "drawHUDs runs after the intro box: " .. tostring(err2))
eq(#rows2, 0, "no ball row survives the dismissal (ClearSprites)")
check(drewString(strings2, wild.enemy.name),
      "the enemy HUD appears once the intro box is gone")

-- the back pic walks off the LEFT edge before "Go! X!"
local slideLow, slideDone, goFrame, shownDuringSlide = 0, nil, nil, true
for f = 1, 240 do
  step(wild)
  local off = wild:picOffset("back")
  if off < slideLow then slideLow = off end
  if off < 0 and not wild.showPlayerBack then shownDuringSlide = false end
  if not slideDone and off <= -72 then slideDone = f end
  if not goFrame and currentText(wild) and currentText(wild):find("Go!", 1, true) then
    goFrame = f
  end
  if goFrame then break end
end
eq(slideLow, -72, "the back pic walks a full 9 tiles off the left edge")
check(shownDuringSlide, "the back pic stays drawn for the whole slide")
check(slideDone ~= nil and goFrame ~= nil and slideDone < goFrame,
      "the slide finishes BEFORE the send-out text (core.asm:236-240)")
eq(wild.showPlayerBack, false, "only then is the back pic taken down")
eq(wild:picOffset("back"), 0, "the slide program is cleared with the pic")

-- --------------------------------------------------------------- trainer
local game2 = makeGame({ Pokemon.new(Data, "BULBASAUR", 50) })
local tr = BattleState.newTrainer(game2, "OPP_YOUNGSTER", 1)
tr.onFinish = function() end
tr:enter()
eq(tr.introBalls, true, "the trainer intro opens the same window")
for _ = 1, 85 do tr:update(1 / 60) end

local ok3, err3, rows3 = snapshotHUD(tr)
check(ok3, "drawHUDs runs during the trainer intro: " .. tostring(err3))
eq(#rows3, 2, "a TRAINER intro draws both ball rows")
if rows3[1] and rows3[2] then
  eq(rows3[1].x, 64, "enemy ball row x = 64 (wBaseCoordX $48)")
  eq(rows3[1].y, 16, "enemy ball row y = 16 (wBaseCoordY $20)")
  eq(rows3[1].step, -8, "enemy ball row steps -8 leftward")
  eq(rows3[2].x, 88, "player ball row x = 88")
  eq(rows3[2].count, 1, "player row carries this save's one party slot")
end

-- the foe's pic walks off the RIGHT edge before "X sent out Y!"
local foeHigh, foeDone, sentFrame, foeShown = 0, nil, nil, true
for f = 1, 300 do
  step(tr)
  local off = tr:picOffset("foe")
  if off > foeHigh then foeHigh = off end
  if off > 0 and not tr.showEnemyTrainer then foeShown = false end
  if not foeDone and off >= 64 then foeDone = f end
  local t = currentText(tr)
  if not sentFrame and t and t:find("sent", 1, true) then sentFrame = f end
  if sentFrame then break end
end
eq(foeHigh, 64, "the foe's pic walks a full 8 tiles off the right edge")
check(foeShown, "the foe's pic stays drawn for the whole slide")
check(foeDone ~= nil and sentFrame ~= nil and foeDone < sentFrame,
      "the slide finishes BEFORE TrainerSentOutText (core.asm:1308-1310)")
eq(tr.showEnemyTrainer, false, "only then is the trainer pic taken down")

-- ...and the mon is not standing in that slot yet.  The pic walks off at
-- core.asm:1308-1310 but AnimateSendingOutMon does not run until :1421-1434,
-- so the slot is empty for the whole of TrainerSentOutText -- the mon is
-- still in its ball.  It used to pop in full-size the instant the trainer
-- left and sit there through the text, so the grow-in played over a mon that
-- had already arrived; the mid-battle replacement always held it back.
check(tr.enemySendingOut, "the foe's mon stays in its ball while announced")
eq(tr:growInScale(tr.enemy), nil, "and nothing is growing into the slot yet")

local firstGrowScale
for _ = 1, 400 do
  step(tr)
  if tr.growIn and tr.growIn.battler == tr.enemy then
    firstGrowScale = tr:growInScale(tr.enemy)
    break
  end
end
eq(firstGrowScale, 0, "the send-out opens on the ball beat, not a finished pic")
eq(tr.enemySendingOut, false, "which is when the slot is handed over")

-- and the window never reopens: drive the rest of the intro out
for _ = 1, 400 do
  step(tr)
  if tr.phase == "menu" then break end
end
eq(tr.phase, "menu", "the trainer intro reaches the battle menu")
eq(tr.introBalls, nil, "the DrawAllPokeballs window stays closed")
local ok4, err4, rows4 = snapshotHUD(tr)
check(ok4, "drawHUDs runs at the battle menu: " .. tostring(err4))
eq(#rows4, 0, "no ball row is drawn once the battle proper starts")

S.finish()
