-- pokefirered/src/slot_machine.c:863

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")
local Model = require("src.core.game3.slot_machine")

local SlotMachineUi = {}

SlotMachineUi.open = false
SlotMachineUi.state = nil
SlotMachineUi.task = "bet"

-- pokefirered/src/slot_machine.c:1826
SlotMachineUi.REEL_X = { [0] = 80, [1] = 120, [2] = 160 }
SlotMachineUi.REEL_TOP_Y = 44
SlotMachineUi.ICON_SPACING = 24
SlotMachineUi.ICON_SIZE = 32

-- pokefirered/src/slot_machine.c:1894
SlotMachineUi.CREDIT_X = 85
SlotMachineUi.PAYOUT_X = 133
SlotMachineUi.DIGIT_Y = 30

-- pokefirered/src/slot_machine.c:796
SlotMachineUi.MSG_LEFT = 5
SlotMachineUi.MSG_TOP = 15
SlotMachineUi.MSG_WIDTH = 20
SlotMachineUi.MSG_HEIGHT = 4

-- pokefirered/src/slot_machine.c:847
SlotMachineUi.YESNO_LEFT = 19
SlotMachineUi.YESNO_TOP = 9

-- pokefirered/src/slot_machine.c:1923
SlotMachineUi.CLEFAIRY_SIZE = 32
SlotMachineUi.CLEFAIRY_X = { 16, 224 }
SlotMachineUi.CLEFAIRY_Y = 136

-- pokefirered/src/slot_machine.c:679
SlotMachineUi.CLEFAIRY_ANIM = {
  [0] = { { frame = 0, duration = 4 } },
  [1] = { { frame = 0, duration = 24 }, { frame = 1, duration = 24 } },
  [2] = { { frame = 2, duration = 28 }, { frame = 3, duration = 28 } },
  [3] = { { frame = 4, duration = 12 }, { frame = 5, duration = 12 } },
}

SlotMachineUi.ANIM_NEUTRAL = 0
SlotMachineUi.ANIM_SPINNING = 1
SlotMachineUi.ANIM_PAYOUT = 2
SlotMachineUi.ANIM_LOSE = 3

-- pokefirered/src/slot_machine.c:857
SlotMachineUi.BUTTON_X = { [0] = 72, [1] = 112, [2] = 152 }
SlotMachineUi.BUTTON_Y = 136
SlotMachineUi.BUTTON_SIZE = 16

-- pokefirered/src/slot_machine.c:2399
SlotMachineUi.LINE_FLASH_PERIOD = 8

-- pokefirered/src/slot_machine.c:2385
SlotMachineUi.ROW_Y = { [0] = 68, [1] = 92, [2] = 116 }

-- pokefirered/include/constants/songs.h:275
SlotMachineUi.MUS_SLOTS_JACKPOT = 268
-- pokefirered/include/constants/songs.h:276
SlotMachineUi.MUS_SLOTS_WIN = 269

-- pokefirered/src/slot_machine.c:2287
SlotMachineUi.HELP_SLIDE_STEP = 16
SlotMachineUi.HELP_WIDTH = 256

-- pokefirered/src/palette.c:162
SlotMachineUi.FADE_STEP = 3
SlotMachineUi.FADE_MAX = 16

local ICON = Model.ICON

local PLACEHOLDER = {
  [ICON.SEVEN] = { { 0.90, 0.16, 0.16 }, Strings("7") },
  [ICON.ROCKET] = { { 0.12, 0.12, 0.16 }, Strings("R") },
  [ICON.PIKACHU] = { { 0.98, 0.84, 0.16 }, Strings("PI") },
  [ICON.PSYDUCK] = { { 0.98, 0.63, 0.20 }, Strings("PS") },
  [ICON.CHERRIES] = { { 0.85, 0.20, 0.42 }, Strings("CH") },
  [ICON.MAGNEMITE] = { { 0.64, 0.70, 0.78 }, Strings("MA") },
  [ICON.SHELLDER] = { { 0.55, 0.72, 0.95 }, Strings("SH") },
}

-- pokefirered/src/slot_machine.c:1638
local function help_icons(rank)
  local out = {}
  for icon = 0, 6 do
    if Model.testIconAttribute(rank, icon) then out[#out + 1] = icon end
  end
  return out
end

-- pokefirered/src/slot_machine.c:388
local HELP_ROWS = {}
for rank = Model.NUM_PAYOUT_TYPES - 1, Model.PAYOUT.CHERRIES2, -1 do
  HELP_ROWS[#HELP_ROWS + 1] = { icons = help_icons(rank), payout = Model.payoutFor(rank) }
end

local function cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then return Extract.CACHE_ROOT end
  return "data/generated/gba"
end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local okR, d = pcall(function() return Dataset.cache():read(rel) end)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  local okF, CacheFs = pcall(require, "src.import.CacheFs")
  if okF and CacheFs and CacheFs.readActive then
    local okR, d = pcall(CacheFs.readActive, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local okR, d = pcall(love.filesystem.read, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  local f = io.open(rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 0 then return d end
  end
  return nil
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  local okD, data = pcall(love.image.newImageData, w, h)
  if not okD or not data then return nil end
  local okFfi, ffi = pcall(require, "ffi")
  if okFfi and ffi and data.getFFIPointer then
    ffi.copy(data:getFFIPointer(), rgba, w * h * 4)
  else
    local p = 1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        data:setPixel(x, y, rgba:byte(p) / 255, rgba:byte(p + 1) / 255,
          rgba:byte(p + 2) / 255, rgba:byte(p + 3) / 255)
        p = p + 4
      end
    end
  end
  local img = love.graphics.newImage(data)
  if img and img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

function SlotMachineUi.iconSheet()
  if SlotMachineUi._iconsTried then return SlotMachineUi._icons, SlotMachineUi._iconQuads end
  SlotMachineUi._iconsTried = true
  local size = SlotMachineUi.ICON_SIZE
  local raw = read_bytes(cache_root() .. "/slot_machine/reel_icons.rgba")
  if not raw then return nil end
  local frames = math.floor(#raw / (size * size * 4))
  if frames < 7 then return nil end
  local img = rgba_to_image(raw, size, size * frames)
  if not img then return nil end
  local quads = {}
  for i = 0, frames - 1 do
    quads[i] = love.graphics.newQuad(0, i * size, size, size, size, size * frames)
  end
  SlotMachineUi._icons = img
  SlotMachineUi._iconQuads = quads
  return img, quads
end

function SlotMachineUi.background()
  if SlotMachineUi._bgTried then return SlotMachineUi._bg end
  SlotMachineUi._bgTried = true
  local raw = read_bytes(cache_root() .. "/slot_machine/bg.rgba")
  if raw and #raw >= 240 * 160 * 4 then
    SlotMachineUi._bg = rgba_to_image(raw, 240, 160)
  end
  return SlotMachineUi._bg
end

function SlotMachineUi.clefairySheet()
  if SlotMachineUi._clefTried then return SlotMachineUi._clef, SlotMachineUi._clefQuads end
  SlotMachineUi._clefTried = true
  local size = SlotMachineUi.CLEFAIRY_SIZE
  local raw = read_bytes(cache_root() .. "/slot_machine/clefairy.rgba")
  if not raw then return nil end
  local frames = math.floor(#raw / (size * size * 4))
  if frames < 6 then return nil end
  local img = rgba_to_image(raw, size, size * frames)
  if not img then return nil end
  local quads = {}
  for i = 0, frames - 1 do
    quads[i] = love.graphics.newQuad(0, i * size, size, size, size, size * frames)
  end
  SlotMachineUi._clef = img
  SlotMachineUi._clefQuads = quads
  return img, quads
end

-- pokefirered/src/slot_machine.c:27
SlotMachineUi.NUM_DIGIT_SPRITES = 4
SlotMachineUi.DIGIT_W = 8
SlotMachineUi.DIGIT_H = 16

-- pokefirered/src/slot_machine.c:1889
function SlotMachineUi.digitSheet()
  if SlotMachineUi._digitsTried then return SlotMachineUi._digits, SlotMachineUi._digitQuads end
  SlotMachineUi._digitsTried = true
  local w, h = SlotMachineUi.DIGIT_W, SlotMachineUi.DIGIT_H
  local raw = read_bytes(cache_root() .. "/slot_machine/digits.rgba")
  if not raw then return nil end
  local frames = math.floor(#raw / (w * h * 4))
  if frames < 10 then return nil end
  local img = rgba_to_image(raw, w, h * frames)
  if not img then return nil end
  local quads = {}
  for i = 0, frames - 1 do
    quads[i] = love.graphics.newQuad(0, i * h, w, h, w, h * frames)
  end
  SlotMachineUi._digits = img
  SlotMachineUi._digitQuads = quads
  return img, quads
end

-- pokefirered/src/slot_machine.c:2523
function SlotMachineUi.buttonSheet()
  if SlotMachineUi._buttonTried then return SlotMachineUi._button end
  SlotMachineUi._buttonTried = true
  local size = SlotMachineUi.BUTTON_SIZE
  local raw = read_bytes(cache_root() .. "/slot_machine/button_pressed.rgba")
  if raw and #raw >= size * size * 4 then
    SlotMachineUi._button = rgba_to_image(raw, size, size)
  end
  return SlotMachineUi._button
end

-- pokefirered/src/slot_machine.c:747
function SlotMachineUi.combosWindow()
  if SlotMachineUi._combosTried then return SlotMachineUi._combos end
  SlotMachineUi._combosTried = true
  local raw = read_bytes(cache_root() .. "/slot_machine/combos_window.rgba")
  if raw and #raw >= 240 * 160 * 4 then
    SlotMachineUi._combos = rgba_to_image(raw, 240, 160)
  end
  return SlotMachineUi._combos
end

local SE = require("src.core.game3.se_ids")

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

-- pokefirered/src/sound.c:220
local function fanfare(id)
  pcall(function() require("src.core.game3.audio").playFanfare(id) end)
end

-- pokefirered/src/sound.c:249
local function fanfareInactive()
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if not (ok and type(Audio) == "table") then return true end
  if type(Audio.isFanfareFinished) ~= "function" then return true end
  local okF, done = pcall(Audio.isFanfareFinished)
  if not okF then return true end
  return done and true or false
end

function SlotMachineUi.show(opts)
  opts = opts or {}
  SlotMachineUi.open = true
  SlotMachineUi._session = opts.session
  SlotMachineUi._onClose = opts.onClose
  SlotMachineUi.state = Model.newState(opts.machineIdx)
  SlotMachineUi.task = "bet"
  SlotMachineUi._timer = 0
  SlotMachineUi._frame = 0
  SlotMachineUi._message = nil
  SlotMachineUi._yesNo = nil
  SlotMachineUi._payDelay = 0
  SlotMachineUi._winPhase = 0
  SlotMachineUi._payAll = false
  SlotMachineUi.setClefairyAnim(SlotMachineUi.ANIM_NEUTRAL)
  SlotMachineUi.releaseReelButtons()
  SlotMachineUi._lineFlash = 0
  SlotMachineUi.helpPhase = nil
  SlotMachineUi.helpX = 0
  -- pokefirered/src/slot_machine.c:2087
  SlotMachineUi._fadeY = SlotMachineUi.FADE_MAX
  SlotMachineUi._fadeDir = -1
  SlotMachineUi.updateLineLights(SlotMachineUi.state.bet)
  SlotMachineUi._msgTpl = Window.template(SlotMachineUi.MSG_LEFT, SlotMachineUi.MSG_TOP,
    SlotMachineUi.MSG_WIDTH, SlotMachineUi.MSG_HEIGHT)
  SlotMachineUi._yesNoTpl = Window.template(SlotMachineUi.YESNO_LEFT, SlotMachineUi.YESNO_TOP, 6, 4)
  SlotMachineUi._amounts = { credit = -1, payout = -1, bet = -1 }
  Stack.push("slot_machine", SlotMachineUi, { hideBelow = true })
  return SlotMachineUi.state
end

-- pokefirered/src/slot_machine.c:2344
function SlotMachineUi.updateLineLights(bet)
  local lit = SlotMachineUi._lit or {}
  for i = 0, Model.NUM_MATCH_LINES - 1 do lit[i] = false end
  for _, id in ipairs(Model.linesForBet(bet or 0)) do lit[id] = true end
  SlotMachineUi._lit = lit
  return lit
end

-- pokefirered/src/slot_machine.c:1932
function SlotMachineUi.setClefairyAnim(animId)
  animId = tonumber(animId) or 0
  if not SlotMachineUi.CLEFAIRY_ANIM[animId] then animId = 0 end
  SlotMachineUi.clefairyAnim = animId
  SlotMachineUi.clefairyStep = 1
  SlotMachineUi.clefairyTimer = 0
end

-- pokefirered/src/sprite.c:905
function SlotMachineUi.stepClefairy()
  local anim = SlotMachineUi.CLEFAIRY_ANIM[SlotMachineUi.clefairyAnim or 0]
  if not anim then return end
  SlotMachineUi.clefairyTimer = (SlotMachineUi.clefairyTimer or 0) + 1
  local cmd = anim[SlotMachineUi.clefairyStep or 1]
  if not cmd then return end
  if SlotMachineUi.clefairyTimer > cmd.duration and #anim > 1 then
    SlotMachineUi.clefairyTimer = 0
    SlotMachineUi.clefairyStep = (SlotMachineUi.clefairyStep % #anim) + 1
  end
end

function SlotMachineUi.clefairyFrame()
  local anim = SlotMachineUi.CLEFAIRY_ANIM[SlotMachineUi.clefairyAnim or 0]
  local cmd = anim and anim[SlotMachineUi.clefairyStep or 1]
  return cmd and cmd.frame or 0
end

-- pokefirered/src/slot_machine.c:2492
function SlotMachineUi.pressReelButton(reel)
  SlotMachineUi.buttonPressed = SlotMachineUi.buttonPressed or {}
  SlotMachineUi.buttonPressed[tonumber(reel) or 0] = true
end

-- pokefirered/src/slot_machine.c:2507
function SlotMachineUi.releaseReelButtons()
  SlotMachineUi.buttonPressed = {}
end

function SlotMachineUi.isOpen()
  return SlotMachineUi.open
end

function SlotMachineUi.close()
  SlotMachineUi.open = false
  Stack.pop("slot_machine")
  local cb = SlotMachineUi._onClose
  SlotMachineUi._onClose = nil
  SlotMachineUi.state = nil
  if cb then cb() end
end

local function coins()
  return Model.coins(SlotMachineUi._session)
end

-- pokefirered/src/slot_machine.c:946
local function update_bet(st, input)
  if coins() == 0 then
    SlotMachineUi.task = "nocoins"
    SlotMachineUi._message = RomText.plain("gString_OutOfCoins")
    return
  end
  if input:wasPressed("down") then
    if Model.betOne(st, SlotMachineUi._session) then
      se(SE.SE_RS_SHOP)
      SlotMachineUi.updateLineLights(st.bet)
      if st.bet >= Model.MAX_BET or coins() == 0 then
        SlotMachineUi.task = "spin"
      end
    end
  elseif input:wasPressed("r") then
    if Model.betMax(st, SlotMachineUi._session) then
      se(SE.SE_RS_SHOP)
      SlotMachineUi.updateLineLights(st.bet)
      SlotMachineUi.task = "spin"
    end
  elseif input:wasPressed("a") and st.bet ~= 0 then
    SlotMachineUi.task = "spin"
  elseif input:wasPressed("b") then
    SlotMachineUi.task = "quit"
    SlotMachineUi._message = RomText.plain("gString_QuitPlaying")
    SlotMachineUi._yesNo = 1
  elseif input:wasPressed("right") then
    -- pokefirered/src/slot_machine.c:993
    SlotMachineUi.showHelp()
  end
end

-- pokefirered/src/slot_machine.c:2271
function SlotMachineUi.showHelp()
  SlotMachineUi.task = "help"
  SlotMachineUi.helpPhase = "in"
  SlotMachineUi.helpX = 0
  se(SE.SE_WIN_OPEN)
end

-- pokefirered/src/slot_machine.c:1074
local function update_help(_st, input)
  if SlotMachineUi.helpPhase == "shown" and input:wasPressed("left") then
    -- pokefirered/src/slot_machine.c:2302
    se(SE.SE_WIN_OPEN)
    SlotMachineUi.helpPhase = "out"
  end
end

-- pokefirered/src/slot_machine.c:2287
function SlotMachineUi.stepHelp()
  local phase = SlotMachineUi.helpPhase
  if phase == "in" then
    SlotMachineUi.helpX = (SlotMachineUi.helpX or 0) + SlotMachineUi.HELP_SLIDE_STEP
    if SlotMachineUi.helpX >= SlotMachineUi.HELP_WIDTH then
      SlotMachineUi.helpX = SlotMachineUi.HELP_WIDTH
      SlotMachineUi.helpPhase = "shown"
    end
  elseif phase == "out" then
    -- pokefirered/src/slot_machine.c:2311
    SlotMachineUi.helpX = (SlotMachineUi.helpX or 0) - SlotMachineUi.HELP_SLIDE_STEP
    if SlotMachineUi.helpX <= 0 then
      SlotMachineUi.helpX = 0
      SlotMachineUi.helpPhase = nil
      SlotMachineUi.task = "bet"
    end
  end
end

-- pokefirered/src/slot_machine.c:1000
local function begin_spin(st)
  Model.calcBias(st)
  Model.startReels(st)
  st.currentReel = 0
  SlotMachineUi.task = "stopping"
  -- pokefirered/src/slot_machine.c:1012
  SlotMachineUi.setClefairyAnim(SlotMachineUi.ANIM_SPINNING)
end

-- pokefirered/src/slot_machine.c:1016
local function press_stop(st)
  if Model.isReelSpinning(st, st.currentReel) then
    se(SE.SE_CONTEST_PLACE)
    Model.stopCurrentReel(st, st.currentReel, st.currentReel)
    SlotMachineUi.pressReelButton(st.currentReel)
  end
end

-- pokefirered/src/slot_machine.c:1027
local function advance_stopped_reel(st)
  if not Model.isReelSpinning(st, st.currentReel) then
    st.currentReel = st.currentReel + 1
    if st.currentReel >= Model.NUM_REELS then
      Model.calcPayout(st)
      st.bet = 0
      st.currentReel = 0
      if st.slotRewardClass == Model.PAYOUT.NONE then
        SlotMachineUi.task = "lose"
        SlotMachineUi._timer = 0
        -- pokefirered/src/slot_machine.c:2166
        SlotMachineUi.setClefairyAnim(SlotMachineUi.ANIM_LOSE)
      else
        if st.slotRewardClass == Model.PAYOUT.SEVEN then
          -- pokefirered/src/slot_machine.c:1041
          Model.incrementGameStat(SlotMachineUi._session, Model.GAME_STAT_SLOT_JACKPOTS)
        end
        Model.resetBias(st)
        SlotMachineUi.task = "win"
        SlotMachineUi._timer = 0
        SlotMachineUi._winPhase = 0
        SlotMachineUi._payAll = false
        -- pokefirered/src/slot_machine.c:2140
        SlotMachineUi.setClefairyAnim(SlotMachineUi.ANIM_PAYOUT)
        SlotMachineUi._lineFlash = 0
      end
    end
  end
end

-- pokefirered/src/slot_machine.c:1142
local function update_lose(st)
  SlotMachineUi._timer = SlotMachineUi._timer + 1
  if SlotMachineUi._timer > 60 then
    SlotMachineUi.task = "bet"
    -- pokefirered/src/slot_machine.c:1157
    SlotMachineUi.setClefairyAnim(SlotMachineUi.ANIM_NEUTRAL)
    SlotMachineUi.releaseReelButtons()
    SlotMachineUi.updateLineLights(st.bet)
  end
end

-- pokefirered/src/slot_machine.c:1170
local function update_win(st)
  local input = SlotMachineUi._lastInput
  local aHeld = (input and input.isDown and input:isDown("a")) and true or false
  local phase = SlotMachineUi._winPhase or 0
  if phase == 0 then
    -- pokefirered/src/slot_machine.c:1177
    if st.slotRewardClass == Model.PAYOUT.ROCKET or st.slotRewardClass == Model.PAYOUT.SEVEN then
      fanfare(SlotMachineUi.MUS_SLOTS_JACKPOT)
    else
      fanfare(SlotMachineUi.MUS_SLOTS_WIN)
    end
    SlotMachineUi._payDelay = 8
    SlotMachineUi._winPhase = 1
    return
  end
  if phase == 1 then
    -- pokefirered/src/slot_machine.c:1186
    SlotMachineUi._payDelay = SlotMachineUi._payDelay + 1
    if SlotMachineUi._payDelay > 120 then
      SlotMachineUi._payDelay = aHeld and 2 or 8
      SlotMachineUi._winPhase = 2
    end
    return
  end
  if phase == 2 then
    local payAll = SlotMachineUi._payAll
    SlotMachineUi._payAll = false
    -- pokefirered/src/slot_machine.c:1199
    if fanfareInactive() and payAll then
      Model.payAll(st, SlotMachineUi._session)
    else
      SlotMachineUi._payDelay = SlotMachineUi._payDelay - 1
      if SlotMachineUi._payDelay == 0 then
        -- pokefirered/src/slot_machine.c:1209
        if fanfareInactive() then se(SE.SE_PIN) end
        Model.payCoin(st, SlotMachineUi._session)
        SlotMachineUi._payDelay = aHeld and 2 or 8
      end
    end
    if st.payout == 0 then SlotMachineUi._winPhase = 3 end
    return
  end
  -- pokefirered/src/slot_machine.c:1227
  if fanfareInactive() then
    SlotMachineUi.task = "bet"
    -- pokefirered/src/slot_machine.c:2158
    SlotMachineUi.setClefairyAnim(SlotMachineUi.ANIM_NEUTRAL)
    SlotMachineUi.releaseReelButtons()
    SlotMachineUi.updateLineLights(st.bet)
  end
end

-- pokefirered/src/slot_machine.c:1102
local function update_quit(st, input)
  if input:wasPressed("up") or input:wasPressed("down") then
    SlotMachineUi._yesNo = (SlotMachineUi._yesNo == 1) and 2 or 1
  elseif input:wasPressed("a") then
    if SlotMachineUi._yesNo == 1 then
      Model.refundBet(st, SlotMachineUi._session)
      SlotMachineUi._message = nil
      SlotMachineUi.task = "exit"
    else
      SlotMachineUi._message = nil
      SlotMachineUi._yesNo = nil
      SlotMachineUi.task = "bet"
    end
  elseif input:wasPressed("b") then
    SlotMachineUi._message = nil
    SlotMachineUi._yesNo = nil
    SlotMachineUi.task = "bet"
  end
end

function SlotMachineUi.handleInput(input)
  local st = SlotMachineUi.state
  if not (SlotMachineUi.open and st and input) then return end
  SlotMachineUi._lastInput = input
  local task = SlotMachineUi.task
  if task == "bet" then
    update_bet(st, input)
  elseif task == "stopping" then
    if input:wasPressed("a") then press_stop(st) end
  elseif task == "win" then
    -- pokefirered/src/slot_machine.c:1199
    if input:wasPressed("start") and SlotMachineUi._winPhase == 2 and fanfareInactive() then
      SlotMachineUi._payAll = true
    end
  elseif task == "help" then
    update_help(st, input)
  elseif task == "quit" then
    update_quit(st, input)
  elseif task == "nocoins" then
    -- pokefirered/src/slot_machine.c:1068
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("up")
        or input:wasPressed("down") or input:wasPressed("left") or input:wasPressed("right") then
      SlotMachineUi._message = nil
      SlotMachineUi.task = "exit"
    end
  end
end

-- pokefirered/src/palette.c:393
function SlotMachineUi.stepFade()
  local dir = SlotMachineUi._fadeDir or 0
  if dir == 0 then return end
  local y = (SlotMachineUi._fadeY or 0) + dir * SlotMachineUi.FADE_STEP
  if dir < 0 and y <= 0 then y, dir = 0, 0 end
  if dir > 0 and y >= SlotMachineUi.FADE_MAX then y, dir = SlotMachineUi.FADE_MAX, 0 end
  SlotMachineUi._fadeY, SlotMachineUi._fadeDir = y, dir
end

function SlotMachineUi.fadeActive()
  return (SlotMachineUi._fadeDir or 0) ~= 0
end

function SlotMachineUi.update(_dt)
  local st = SlotMachineUi.state
  if not (SlotMachineUi.open and st) then return end
  SlotMachineUi._frame = SlotMachineUi._frame + 1
  SlotMachineUi.stepFade()
  if SlotMachineUi.task == "spin" then
    begin_spin(st)
  elseif SlotMachineUi.task == "lose" then
    update_lose(st)
  elseif SlotMachineUi.task == "win" then
    update_win(st)
  elseif SlotMachineUi.task == "help" then
    SlotMachineUi.stepHelp()
  elseif SlotMachineUi.task == "exit" then
    -- pokefirered/src/slot_machine.c:2106
    SlotMachineUi._fadeDir = 1
    SlotMachineUi.task = "fadeout"
  elseif SlotMachineUi.task == "fadeout" then
    if not SlotMachineUi.fadeActive() then
      SlotMachineUi.close()
      return
    end
  end
  -- pokefirered/src/slot_machine.c:1274
  Model.spinStep(st)
  if SlotMachineUi.task == "stopping" then
    advance_stopped_reel(st)
  end
  SlotMachineUi.stepClefairy()
  SlotMachineUi._lineFlash = ((SlotMachineUi._lineFlash or 0) + 1) % (SlotMachineUi.LINE_FLASH_PERIOD * 2)
end

-- pokefirered/src/slot_machine.c:2398
function SlotMachineUi.lineFlashOn()
  return (SlotMachineUi._lineFlash or 0) < SlotMachineUi.LINE_FLASH_PERIOD
end

local function draw_icon(icon, cx, cy)
  local img, quads = SlotMachineUi.iconSheet()
  local size = SlotMachineUi.ICON_SIZE
  if img and quads and quads[icon] then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, quads[icon], cx - size / 2, cy - size / 2)
    return
  end
  local p = PLACEHOLDER[icon]
  if not p then return end
  local w = 22
  love.graphics.setColor(p[1][1], p[1][2], p[1][3], 1)
  love.graphics.rectangle("fill", cx - w / 2, cy - w / 2, w, w)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", cx - w / 2 + 0.5, cy - w / 2 + 0.5, w - 1, w - 1)
  love.graphics.setColor(1, 1, 1, 1)
  FrlgFont.draw(p[2], cx - 7, cy - 6, { small = true, colors = FrlgFont.COLOR.NORMAL })
end

-- pokefirered/src/slot_machine.c:1842
local function draw_reel(st, reel)
  local cx = SlotMachineUi.REEL_X[reel]
  local pos = st.reelPositions[reel]
  local yoff = st.reelSubpixel[reel] * 8
  for j = 0, Model.REEL_LOAD_LENGTH - 1 do
    local icon = Model.iconAt(reel, (pos + j) % Model.REEL_LENGTH)
    draw_icon(icon, cx, SlotMachineUi.REEL_TOP_Y + SlotMachineUi.ICON_SPACING * j + yoff)
  end
end

-- pokefirered/src/slot_machine.c:2381
local function draw_line_seg(x1, y1, x2, y2, on, win, flash, skipUnlit)
  if skipUnlit and not (on or win) then return end
  if win then
    if flash then
      love.graphics.setColor(1, 0.9, 0.2, 1)
    else
      love.graphics.setColor(1, 0.55, 0.12, 1)
    end
  elseif on then
    love.graphics.setColor(1, 0.35, 0.35, 1)
  else
    love.graphics.setColor(0.35, 0.35, 0.4, 1)
  end
  love.graphics.line(x1, y1, x2, y2)
end

local function draw_lines(st)
  local lit = SlotMachineUi._lit or SlotMachineUi.updateLineLights(st.bet)
  local left, right = SlotMachineUi.REEL_X[0] - 24, SlotMachineUi.REEL_X[2] + 24
  local rowY = SlotMachineUi.ROW_Y
  local flash = SlotMachineUi.lineFlashOn()
  -- pokefirered/src/slot_machine.c:2367
  local baked = SlotMachineUi.background() ~= nil
  draw_line_seg(left, rowY[0], right, rowY[0], lit[1], st.winFlags[1], flash, baked)
  draw_line_seg(left, rowY[1], right, rowY[1], lit[2], st.winFlags[2], flash, baked)
  draw_line_seg(left, rowY[2], right, rowY[2], lit[3], st.winFlags[3], flash, baked)
  draw_line_seg(left, rowY[0], right, rowY[2], lit[0], st.winFlags[0], flash, baked)
  draw_line_seg(left, rowY[2], right, rowY[0], lit[4], st.winFlags[4], flash, baked)
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/slot_machine.c:2492
local function draw_reel_buttons()
  local pressed = SlotMachineUi.buttonPressed or {}
  local size = SlotMachineUi.BUTTON_SIZE
  local sheet = SlotMachineUi.buttonSheet()
  if sheet then
    love.graphics.setColor(1, 1, 1, 1)
    for reel = 0, Model.NUM_REELS - 1 do
      if pressed[reel] then
        love.graphics.draw(sheet, SlotMachineUi.BUTTON_X[reel], SlotMachineUi.BUTTON_Y)
      end
    end
    return
  end
  for reel = 0, Model.NUM_REELS - 1 do
    local x = SlotMachineUi.BUTTON_X[reel]
    local y = SlotMachineUi.BUTTON_Y + (pressed[reel] and 2 or 0)
    if pressed[reel] then
      love.graphics.setColor(0.40, 0.12, 0.14, 1)
    else
      love.graphics.setColor(0.86, 0.22, 0.25, 1)
    end
    love.graphics.rectangle("fill", x, y, size, size - (pressed[reel] and 2 or 0))
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, size - 1, size - 1 - (pressed[reel] and 2 or 0))
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/slot_machine.c:1923
local function draw_clefairy()
  local size = SlotMachineUi.CLEFAIRY_SIZE
  local frame = SlotMachineUi.clefairyFrame()
  local img, quads = SlotMachineUi.clefairySheet()
  for i, cx in ipairs(SlotMachineUi.CLEFAIRY_X) do
    local x = cx - size / 2
    local y = SlotMachineUi.CLEFAIRY_Y - size / 2
    if img and quads and quads[frame] then
      love.graphics.setColor(1, 1, 1, 1)
      if i == 2 then
        love.graphics.draw(img, quads[frame], x + size, y, 0, -1, 1)
      else
        love.graphics.draw(img, quads[frame], x, y)
      end
    else
      local shade = 0.75 + 0.08 * (frame % 2)
      love.graphics.setColor(0.98 * shade, 0.72 * shade, 0.78 * shade, 1)
      love.graphics.rectangle("fill", x + 6, y + 6, size - 12, size - 12)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("line", x + 6.5, y + 6.5, size - 13, size - 13)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/slot_machine.c:2052
local function draw_help()
  local w = SlotMachineUi.helpX or 0
  if w <= 0 then return end
  if w > 240 then w = 240 end
  local sx, sy, sw, sh = love.graphics.getScissor()
  love.graphics.setScissor(0, 0, w, 160)
  local img = SlotMachineUi.combosWindow()
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, 0, 0)
  else
    love.graphics.setColor(0.06, 0.06, 0.12, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    for i, row in ipairs(HELP_ROWS) do
      local y = 16 + (i - 1) * 22
      for k, icon in ipairs(row.icons) do
        local p = PLACEHOLDER[icon]
        if p then
          love.graphics.setColor(p[1][1], p[1][2], p[1][3], 1)
          love.graphics.rectangle("fill", 24 + (k - 1) * 22, y, 18, 18)
          love.graphics.setColor(1, 1, 1, 1)
          FrlgFont.draw(p[2], 27 + (k - 1) * 22, y + 4,
            { small = true, colors = FrlgFont.COLOR.NORMAL })
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
      FrlgFont.draw(string.format("%4d", row.payout), 150, y + 4,
        { small = true, colors = FrlgFont.COLOR.NORMAL })
    end
  end
  if sw then
    love.graphics.setScissor(sx, sy, sw, sh)
  else
    love.graphics.setScissor()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/slot_machine.c:1903
local function amount_text(key, value, fmt)
  local cache = SlotMachineUi._amounts
  if not cache then
    cache = { credit = -1, payout = -1, bet = -1 }
    SlotMachineUi._amounts = cache
  end
  if cache[key] ~= value then
    cache[key] = value
    cache[key .. "Text"] = fmt(value)
  end
  return cache[key .. "Text"]
end

local function digits(n)
  return string.format("%4d", n)
end

local function bet_text(n)
  return Strings("BET %d", n)
end

-- pokefirered/src/slot_machine.c:1903
local function draw_digits(value, baseX)
  local sheet, quads = SlotMachineUi.digitSheet()
  if not (sheet and quads) then return false end
  value = math.max(0, math.floor(tonumber(value) or 0))
  local divisor = 1000
  love.graphics.setColor(1, 1, 1, 1)
  for i = 0, SlotMachineUi.NUM_DIGIT_SPRITES - 1 do
    local quotient = math.floor(value / divisor)
    value = value - quotient * divisor
    if quads[quotient] then
      love.graphics.draw(sheet, quads[quotient],
        baseX + 7 * i - SlotMachineUi.DIGIT_W / 2, SlotMachineUi.DIGIT_Y - SlotMachineUi.DIGIT_H / 2)
    end
    divisor = divisor / 10
  end
  return true
end

function SlotMachineUi.draw()
  local st = SlotMachineUi.state
  if not (SlotMachineUi.open and st) then return end
  if not (love and love.graphics) then return end

  local bg = SlotMachineUi.background()
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, 0, 0)
  else
    love.graphics.setColor(0.12, 0.10, 0.22, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(0.24, 0.20, 0.38, 1)
    love.graphics.rectangle("fill", 56, 40, 128, 96)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 60, 50, 120, 76)
  end
  love.graphics.setColor(1, 1, 1, 1)

  local sx, sy, sw, sh = love.graphics.getScissor()
  love.graphics.setScissor(60, 50, 120, 76)
  for reel = 0, Model.NUM_REELS - 1 do
    draw_reel(st, reel)
  end
  if sw then
    love.graphics.setScissor(sx, sy, sw, sh)
  else
    love.graphics.setScissor()
  end

  draw_lines(st)
  draw_reel_buttons()
  draw_clefairy()

  -- pokefirered/src/slot_machine.c:2037
  if not bg then
    FrlgFont.draw(Strings("CREDIT"), SlotMachineUi.CREDIT_X - 30, SlotMachineUi.DIGIT_Y - 14,
      { small = true, colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(amount_text("bet", st.bet, bet_text), 8, SlotMachineUi.DIGIT_Y - 4,
      { small = true, colors = FrlgFont.COLOR.NORMAL })
  end
  -- pokefirered/src/slot_machine.c:1903
  if not draw_digits(coins(), SlotMachineUi.CREDIT_X) then
    FrlgFont.draw(amount_text("credit", coins(), digits),
      SlotMachineUi.CREDIT_X - 4, SlotMachineUi.DIGIT_Y - 4,
      { small = true, colors = FrlgFont.COLOR.NORMAL })
  end
  if not draw_digits(st.payout, SlotMachineUi.PAYOUT_X) then
    FrlgFont.draw(amount_text("payout", st.payout, digits),
      SlotMachineUi.PAYOUT_X - 4, SlotMachineUi.DIGIT_Y - 4,
      { small = true, colors = FrlgFont.COLOR.NORMAL })
  end

  draw_help()

  if SlotMachineUi._message then
    local tpl = SlotMachineUi._msgTpl
    Window.stdFrame(tpl)
    Window.printPx(SlotMachineUi._message, SlotMachineUi.MSG_LEFT * 8, SlotMachineUi.MSG_TOP * 8 + 2)
  end

  if SlotMachineUi._yesNo then
    local tpl = SlotMachineUi._yesNoTpl
    Window.stdFrame(tpl)
    Window.printPx(Strings("YES"), (SlotMachineUi.YESNO_LEFT + 1) * 8, SlotMachineUi.YESNO_TOP * 8 + 2)
    Window.printPx(Strings("NO"), (SlotMachineUi.YESNO_LEFT + 1) * 8, SlotMachineUi.YESNO_TOP * 8 + 16)
    Window.cursorPx(SlotMachineUi.YESNO_LEFT * 8 + 2,
      SlotMachineUi.YESNO_TOP * 8 + 2 + (SlotMachineUi._yesNo - 1) * 14)
  end

  -- pokefirered/src/slot_machine.c:2087
  local fadeY = SlotMachineUi._fadeY or 0
  if fadeY > 0 then
    love.graphics.setColor(0, 0, 0, fadeY / SlotMachineUi.FADE_MAX)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return SlotMachineUi
