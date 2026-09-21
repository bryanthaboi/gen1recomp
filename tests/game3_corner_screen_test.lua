#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Slots = require("src.core.game3.slot_machine")
local Ui = require("src.ui.game3.slot_machine")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local PRET = "../pokefirered/src/slot_machine.c"

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local src = slurp(PRET)

local Audio = require("src.core.game3.audio")

local function session(coins)
  return { coins = coins or 0 }
end

local function openMachine(coins, machineIdx)
  Ui.show({ machineIdx = machineIdx or 0, session = session(coins) })
  return Ui.state
end

local pressed = {}
local held = {}
local input = {
  wasPressed = function(_, key)
    local v = pressed[key]
    pressed[key] = nil
    return v and true or false
  end,
  isDown = function(_, key) return held[key] and true or false end,
}

local function tap(key)
  pressed[key] = true
  Ui.handleInput(input)
  pressed[key] = nil
end

local function frame()
  Ui.handleInput(input)
  Ui.update(1 / 60)
  Audio.update(1 / 60)
end

print("[test] 1. The Clefairy animation table matches pret frame for frame")
if not src then
  print("[skip] no pret checkout at " .. PRET)
else
  local names = { "Neutral", "Spinning", "Payout", "Lose" }
  for animId, name in ipairs(names) do
    local decl = "static const union AnimCmd sAnimCmd_Clefairy_" .. name .. "[] = {"
    local i = src:find(decl, 1, true)
    check(i ~= nil, "pret declares sAnimCmd_Clefairy_" .. name)
    if i then
      local body = src:sub(i + #decl, src:find("};", i, true))
      local frames = {}
      for tile, dur in body:gmatch("ANIMCMD_FRAME%(%s*(%d+)%s*,%s*(%d+)%s*%)") do
        frames[#frames + 1] = { frame = tonumber(tile) / 16, duration = tonumber(dur) }
      end
      local port = Ui.CLEFAIRY_ANIM[animId - 1]
      check(port ~= nil, "the port has anim " .. (animId - 1))
      if port then
        eq(#port, #frames, name .. " has pret's frame count")
        for k, f in ipairs(frames) do
          eq(port[k] and port[k].frame, f.frame, name .. " frame " .. k)
          eq(port[k] and port[k].duration, f.duration, name .. " duration " .. k)
        end
      end
    end
  end
end

print("[test] 2. Clefairy sprite geometry is pret's")
if not src then
  print("[skip] no pret checkout at " .. PRET)
else
  local body = src:match("static void CreateClefairySprites%(void%)%s*{(.-)\n}")
  check(body ~= nil, "pret declares CreateClefairySprites")
  if body then
    local x1, y1 = body:match("CreateSprite%(&sSpriteTemplate_Clefairy,%s*(%d+),%s*(%d+)")
    eq(Ui.CLEFAIRY_X[1], tonumber(x1), "the left Clefairy sits at pret's x")
    eq(Ui.CLEFAIRY_Y, tonumber(y1), "the Clefairy row is pret's y")
    local off, y2 = body:match("CreateSprite%(&sSpriteTemplate_Clefairy,%s*DISPLAY_WIDTH%s*%-%s*(%d+),%s*(%d+)")
    eq(Ui.CLEFAIRY_X[2], 240 - tonumber(off), "the right Clefairy sits at pret's mirrored x")
    eq(Ui.CLEFAIRY_Y, tonumber(y2), "both Clefairy sprites share a row")
  end
end

print("[test] 3. The reel buttons sit under pret's tilemap slots")
if not src then
  print("[skip] no pret checkout at " .. PRET)
else
  local body = src:match("sReelButtonMapTileIdxs%[NUM_REELS%]%[NUM_BUTTON_TILES%] = {(.-)};")
  check(body ~= nil, "pret declares sReelButtonMapTileIdxs")
  if body then
    local reel = 0
    for rowSrc in body:gmatch("{([^{}]+)}") do
      local idxs = {}
      for hex in rowSrc:gmatch("0x(%x+)") do idxs[#idxs + 1] = tonumber(hex, 16) end
      eq(#idxs, 4, "reel " .. reel .. " is a 2x2 button")
      local top = idxs[1]
      -- pokefirered/src/slot_machine.c:857
      local col = top % 32
      local rowTile = math.floor(top / 32)
      eq(Ui.BUTTON_X[reel], col * 8, "reel " .. reel .. " button x")
      eq(Ui.BUTTON_Y, rowTile * 8, "reel " .. reel .. " button y")
      eq(idxs[2], top + 1, "reel " .. reel .. " button is two tiles wide")
      eq(idxs[3], top + 32, "reel " .. reel .. " button is two tiles tall")
      reel = reel + 1
    end
    eq(reel, Slots.NUM_REELS, "every reel has a button")
    eq(Ui.BUTTON_SIZE, 16, "a 2x2 tile button is 16 px")
  end
end

print("[test] 4. The Clefairy animation follows the machine through a whole play")
do
  local st = openMachine(10, 0)
  eq(Ui.clefairyAnim, Ui.ANIM_NEUTRAL, "the machine opens on the neutral pose")
  -- pokefirered/src/slot_machine.c:958
  tap("down")
  eq(st.bet, 1, "DOWN bet one coin")
  -- pokefirered/src/slot_machine.c:984
  tap("a")
  eq(Ui.task, "spin", "A on a placed bet starts the spin")
  frame()
  eq(Ui.clefairyAnim, Ui.ANIM_SPINNING, "starting the reels switches to the spinning pose")

  local guard = 0
  while Ui.task == "stopping" and guard < 4000 do
    -- pokefirered/src/slot_machine.c:1016
    if Slots.isReelSpinning(st, st.currentReel) then pressed.a = true end
    frame()
    guard = guard + 1
  end
  check(guard < 4000, "the three reels resolved")
  check(Ui.task == "win" or Ui.task == "lose", "the spin scored")
  if Ui.task == "lose" then
    eq(Ui.clefairyAnim, Ui.ANIM_LOSE, "a losing spin faints the Clefairy")
  else
    eq(Ui.clefairyAnim, Ui.ANIM_PAYOUT, "a paying spin starts the Clefairy dance")
  end
  check(Ui.buttonPressed[0], "the A press put the first reel button down")

  guard = 0
  while Ui.task ~= "bet" and guard < 4000 do
    frame()
    guard = guard + 1
  end
  check(guard < 4000, "the machine returned to betting")
  eq(Ui.clefairyAnim, Ui.ANIM_NEUTRAL, "the Clefairy goes back to neutral")
  check(next(Ui.buttonPressed) == nil, "the reel buttons are released")
  Ui.close()
end

print("[test] 5. The Clefairy anim advances on pret's frame counts")
do
  openMachine(10, 0)
  Ui.setClefairyAnim(Ui.ANIM_LOSE)
  eq(Ui.clefairyFrame(), Ui.CLEFAIRY_ANIM[Ui.ANIM_LOSE][1].frame, "the lose anim starts on its first frame")
  local dur = Ui.CLEFAIRY_ANIM[Ui.ANIM_LOSE][1].duration
  for _ = 1, dur do Ui.stepClefairy() end
  eq(Ui.clefairyFrame(), Ui.CLEFAIRY_ANIM[Ui.ANIM_LOSE][1].frame,
    "the first frame is still up on its last tick")
  Ui.stepClefairy()
  eq(Ui.clefairyFrame(), Ui.CLEFAIRY_ANIM[Ui.ANIM_LOSE][2].frame, "the anim advanced")
  for _ = 1, Ui.CLEFAIRY_ANIM[Ui.ANIM_LOSE][2].duration + 1 do Ui.stepClefairy() end
  eq(Ui.clefairyFrame(), Ui.CLEFAIRY_ANIM[Ui.ANIM_LOSE][1].frame, "the anim jumped back to the start")

  Ui.setClefairyAnim(Ui.ANIM_NEUTRAL)
  for _ = 1, 200 do Ui.stepClefairy() end
  eq(Ui.clefairyFrame(), 0, "a one-frame anim never advances")
  Ui.close()
end

print("[test] 6. The winning line flashes on pret's cadence")
do
  openMachine(10, 0)
  Ui._lineFlash = 0
  local on, off = 0, 0
  for _ = 1, Ui.LINE_FLASH_PERIOD * 2 do
    if Ui.lineFlashOn() then on = on + 1 else off = off + 1 end
    Ui.update(1 / 60)
  end
  eq(on, Ui.LINE_FLASH_PERIOD, "the lit half is pret's eight frames")
  eq(off, Ui.LINE_FLASH_PERIOD, "the dark half is pret's eight frames")
  Ui.close()
end

print("[test] 7. The reel art and the Clefairy art degrade to placeholders")
do
  check(Ui.iconSheet() == nil or type(Ui.iconSheet()) == "userdata",
    "the reel sheet is absent or an image")
  check(Ui.clefairySheet() == nil or type(Ui.clefairySheet()) == "userdata",
    "the Clefairy sheet is absent or an image")
  check(Ui.combosWindow() == nil or type(Ui.combosWindow()) == "userdata",
    "the payout help sheet is absent or an image")
  openMachine(10, 0)
  local ok = pcall(Ui.draw)
  check(ok, "drawing without love and without art does not error")
  Ui.close()
end

print("[test] 8. DPAD_RIGHT slides the payout help panel in and DPAD_LEFT slides it out")
if not src then
  print("[skip] no pret checkout at " .. PRET)
else
  local loop = src:match("static void MainTask_SlotsGameLoop%(u8 taskId%)%s*{(.-)\nstatic ")
  check(loop ~= nil and loop:find("JOY_NEW(DPAD_RIGHT)", 1, true) ~= nil
    and loop:find("SetMainTask(MainTask_ShowHelp)", 1, true) ~= nil,
    "pret opens the help panel on DPAD_RIGHT from the betting phase")
  local help = src:match("static void MainTask_ShowHelp%(u8 taskId%)%s*{(.-)\nstatic ")
  check(help ~= nil and help:find("JOY_NEW(DPAD_LEFT)", 1, true) ~= nil,
    "pret closes it on DPAD_LEFT")
  local slide = src:match("static bool8 SlotsTask_ShowHelp%(u8 %* state.-\n}") or ""
  local step, width = slide:match("bg1X %+= (%d+).-bg1X >= (%d+)")
  eq(Ui.HELP_SLIDE_STEP, tonumber(step), "the panel slides at pret's pixels per frame")
  eq(Ui.HELP_WIDTH, tonumber(width), "the panel slides to pret's full width")

  openMachine(50, 0)
  eq(Ui.task, "bet", "the machine is on the betting phase")
  tap("right")
  eq(Ui.task, "help", "DPAD_RIGHT opened the payout help panel")
  local frames = 0
  while Ui.helpPhase == "in" and frames < 200 do
    frame()
    frames = frames + 1
  end
  eq(Ui.helpPhase, "shown", "the panel finished sliding in")
  eq(frames, Ui.HELP_WIDTH / Ui.HELP_SLIDE_STEP, "it took pret's sixteen frames")
  eq(Ui.helpX, Ui.HELP_WIDTH, "the panel covers the screen")
  for _ = 1, 120 do frame() end
  eq(Ui.task, "help", "the panel stays up until the player closes it")
  tap("left")
  frames = 0
  while Ui.task == "help" and frames < 200 do
    frame()
    frames = frames + 1
  end
  eq(Ui.task, "bet", "DPAD_LEFT put the machine back on the betting phase")
  eq(Ui.helpX, 0, "the panel slid back off screen")
  local ok = pcall(Ui.draw)
  check(ok, "drawing the help panel without art does not error")
  Ui.close()
end

print("[test] 9. A paying spin plays pret's fanfare on pret's frame counts")
do
  local played = {}
  local realFanfare = Audio.playFanfare
  Audio.playFanfare = function(id)
    played[#played + 1] = id
    return realFanfare(id)
  end

  local Rng = require("src.core.game3.rng")
  Rng.SeedRng(0x51075)
  local sess = { coins = 500 }
  Ui.show({ machineIdx = 5, session = sess })
  local st = Ui.state
  local coinFrame, winFrames, jackpots = nil, 0, 0
  for _ = 1, 80 do
    tap("r")
    frame()
    local guard = 0
    while Ui.task == "stopping" and guard < 2000 do
      if Slots.isReelSpinning(st, st.currentReel) then pressed.a = true end
      frame()
      guard = guard + 1
    end
    if Ui.task == "win" then
      winFrames = winFrames + 1
      if st.slotRewardClass == Slots.PAYOUT.SEVEN then jackpots = jackpots + 1 end
      local payoutAtWin = st.payout
      local n = 0
      while Ui.task == "win" and n < 5000 do
        frame()
        n = n + 1
        if not coinFrame and st.payout < payoutAtWin then coinFrame = n end
      end
      break
    end
    local n = 0
    while Ui.task ~= "bet" and n < 500 do frame(); n = n + 1 end
  end
  check(winFrames > 0, "a paying spin landed")
  eq(#played, 1, "the win started exactly one fanfare")
  -- pokefirered/src/slot_machine.c:1177
  local expect = (jackpots > 0) and Ui.MUS_SLOTS_JACKPOT or Ui.MUS_SLOTS_WIN
  eq(played[1], expect, "the fanfare is pret's song for that payout class")
  -- pokefirered/src/slot_machine.c:1182
  eq(coinFrame, 122, "the first coin drops 1 + 113 + 8 frames after the win")
  eq(Slots.gameStat(sess, Slots.GAME_STAT_SLOT_JACKPOTS), jackpots,
    "only a triple seven counts a jackpot")
  Ui.close()
  Audio.playFanfare = realFanfare
end

print("[test] 10. A triple seven counts the jackpot stat and plays the jackpot fanfare")
do
  local played = {}
  local realFanfare = Audio.playFanfare
  Audio.playFanfare = function(id)
    played[#played + 1] = id
    return realFanfare(id)
  end

  local Rng = require("src.core.game3.rng")
  Rng.SeedRng(0x7777)
  local sess = { coins = 9000 }
  Ui.show({ machineIdx = 5, session = sess })
  local st = Ui.state
  local hit = false
  for _ = 1, 4000 do
    tap("r")
    frame()
    -- pokefirered/src/slot_machine.c:1680
    st.machineBias = Slots.PAYOUT.SEVEN
    local guard = 0
    while Ui.task == "stopping" and guard < 2000 do
      if Slots.isReelSpinning(st, st.currentReel) then pressed.a = true end
      frame()
      guard = guard + 1
    end
    if st.slotRewardClass == Slots.PAYOUT.SEVEN then
      hit = true
      break
    end
    local n = 0
    while Ui.task ~= "bet" and n < 4000 do frame(); n = n + 1 end
  end
  check(hit, "a biased machine eventually lands the triple seven")
  if hit then
    -- pokefirered/src/slot_machine.c:1041
    eq(Slots.gameStat(sess, Slots.GAME_STAT_SLOT_JACKPOTS), 1, "the jackpot stat counted one")
    local n = 0
    while Ui.task == "win" and #played == 0 and n < 10 do frame(); n = n + 1 end
    eq(played[1], Ui.MUS_SLOTS_JACKPOT, "the jackpot plays MUS_SLOTS_JACKPOT")
  end
  Ui.close()
  Audio.playFanfare = realFanfare
end

print("[test] 11. The screen fades in on open and out on close")
do
  local sess = { coins = 0 }
  Ui.show({ machineIdx = 0, session = sess })
  -- pokefirered/src/slot_machine.c:2087
  eq(Ui._fadeY, Ui.FADE_MAX, "the machine opens black")
  check(Ui.fadeActive(), "the fade in is running")
  local frames = 0
  while Ui.fadeActive() and frames < 100 do
    frame()
    frames = frames + 1
  end
  eq(Ui._fadeY, 0, "the fade in finished")
  eq(frames, math.ceil(Ui.FADE_MAX / Ui.FADE_STEP), "pret's delta of three takes six frames")

  -- pokefirered/src/slot_machine.c:1068
  frame()
  eq(Ui.task, "nocoins", "an empty purse ends the game")
  tap("right")
  eq(Ui.task, "exit", "DPAD_ANY closes the game over message")
  frame()
  eq(Ui.task, "fadeout", "closing starts the fade out")
  frames = 0
  while Ui.isOpen() and frames < 100 do
    frame()
    frames = frames + 1
  end
  check(not Ui.isOpen(), "the machine closed after the fade out")
  eq(frames, math.ceil(Ui.FADE_MAX / Ui.FADE_STEP), "the fade out runs before the screen closes")
  eq(Ui._fadeY, Ui.FADE_MAX, "the screen is black when it hands control back")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
