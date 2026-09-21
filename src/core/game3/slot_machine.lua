-- pokefirered/src/slot_machine.c:1

local SlotMachine = {}

SlotMachine.NUM_REELS = 3
SlotMachine.REEL_LENGTH = 21
SlotMachine.REEL_LOAD_LENGTH = 5
SlotMachine.NUM_MATCH_LINES = 5
SlotMachine.MAX_BET = 3

-- pokefirered/src/slot_machine.c:51
SlotMachine.ICON = {
  SEVEN = 0,
  ROCKET = 1,
  PIKACHU = 2,
  PSYDUCK = 3,
  CHERRIES = 4,
  MAGNEMITE = 5,
  SHELLDER = 6,
}

-- pokefirered/src/slot_machine.c:61
SlotMachine.PAYOUT = {
  NONE = 0,
  CHERRIES2 = 1,
  CHERRIES3 = 2,
  MAGSHELL = 3,
  PIKAPSY = 4,
  ROCKET = 5,
  SEVEN = 6,
}
SlotMachine.NUM_PAYOUT_TYPES = 7

local ICON = SlotMachine.ICON
local PAYOUT = SlotMachine.PAYOUT
local REEL_LENGTH = SlotMachine.REEL_LENGTH
local NUM_REELS = SlotMachine.NUM_REELS
local NUM_MATCH_LINES = SlotMachine.NUM_MATCH_LINES

local function zeroBased(list)
  local t = {}
  for i = 1, #list do t[i - 1] = list[i] end
  return t
end

local function rows(list)
  local t = {}
  for i = 1, #list do t[i - 1] = zeroBased(list[i]) end
  return t
end

-- pokefirered/src/slot_machine.c:223
SlotMachine.SECOND_REEL_BIAS_CHECK = rows({
  { 0x00, 0x03 }, { 0x00, 0x06 }, { 0x03, 0x06 },
  { 0x01, 0x04 }, { 0x01, 0x07 }, { 0x04, 0x07 },
  { 0x02, 0x05 }, { 0x02, 0x08 }, { 0x05, 0x08 },
  { 0x00, 0x04 }, { 0x00, 0x08 }, { 0x04, 0x08 },
  { 0x02, 0x04 }, { 0x02, 0x06 }, { 0x04, 0x06 },
})
SlotMachine.NUM_SECOND_REEL_BIAS_CHECK = 15

-- pokefirered/src/slot_machine.c:245
SlotMachine.THIRD_REEL_BIAS_CHECK = rows({
  { 0x00, 0x03, 0x06 },
  { 0x01, 0x04, 0x07 },
  { 0x02, 0x05, 0x08 },
  { 0x00, 0x04, 0x08 },
  { 0x02, 0x04, 0x06 },
})

-- pokefirered/src/slot_machine.c:72
SlotMachine.ROWATTR = { COL1POS = 0, COL2POS = 1, COL3POS = 2, MINBET = 3 }

-- pokefirered/src/slot_machine.c:253
SlotMachine.ROW_ATTRIBUTES = rows({
  { 0x00, 0x04, 0x08, 0x03 },
  { 0x00, 0x03, 0x06, 0x02 },
  { 0x01, 0x04, 0x07, 0x01 },
  { 0x02, 0x05, 0x08, 0x02 },
  { 0x02, 0x04, 0x06, 0x03 },
})

-- pokefirered/src/slot_machine.c:261
SlotMachine.BIAS_CHANCES = rows({
  { 0x1fa1, 0x2eab, 0x3630, 0x39f3, 0x3bd4, 0x3bfc, 0x0049 },
  { 0x1f97, 0x2ea2, 0x3627, 0x39e9, 0x3bca, 0x3bf8, 0x0049 },
  { 0x1f91, 0x2e9b, 0x3620, 0x39e3, 0x3bc4, 0x3bf4, 0x0049 },
  { 0x1f87, 0x2e92, 0x3617, 0x39d9, 0x3bba, 0x3bef, 0x0050 },
  { 0x1f7f, 0x2e89, 0x360e, 0x39d1, 0x3bb2, 0x3bea, 0x0050 },
  { 0x1fc9, 0x2efc, 0x3696, 0x3a63, 0x3c49, 0x3c8b, 0x0073 },
})
SlotMachine.NUM_MACHINE_CLASSES = 6

-- pokefirered/src/slot_machine.c:318
SlotMachine.REELS = rows({
  {
    ICON.SEVEN, ICON.PSYDUCK, ICON.CHERRIES, ICON.ROCKET, ICON.PIKACHU,
    ICON.SHELLDER, ICON.PIKACHU, ICON.MAGNEMITE, ICON.SEVEN, ICON.SHELLDER,
    ICON.PSYDUCK, ICON.ROCKET, ICON.CHERRIES, ICON.PIKACHU, ICON.SHELLDER,
    ICON.SEVEN, ICON.MAGNEMITE, ICON.PIKACHU, ICON.ROCKET, ICON.SHELLDER,
    ICON.PIKACHU,
  },
  {
    ICON.SEVEN, ICON.MAGNEMITE, ICON.CHERRIES, ICON.PSYDUCK, ICON.ROCKET,
    ICON.MAGNEMITE, ICON.CHERRIES, ICON.PSYDUCK, ICON.PIKACHU, ICON.MAGNEMITE,
    ICON.CHERRIES, ICON.PSYDUCK, ICON.SEVEN, ICON.MAGNEMITE, ICON.CHERRIES,
    ICON.ROCKET, ICON.PSYDUCK, ICON.SHELLDER, ICON.MAGNEMITE, ICON.PSYDUCK,
    ICON.CHERRIES,
  },
  {
    ICON.SEVEN, ICON.PSYDUCK, ICON.SHELLDER, ICON.MAGNEMITE, ICON.PIKACHU,
    ICON.PSYDUCK, ICON.SHELLDER, ICON.MAGNEMITE, ICON.PIKACHU, ICON.PSYDUCK,
    ICON.MAGNEMITE, ICON.SHELLDER, ICON.PIKACHU, ICON.PSYDUCK, ICON.MAGNEMITE,
    ICON.SHELLDER, ICON.PIKACHU, ICON.PSYDUCK, ICON.MAGNEMITE, ICON.SHELLDER,
    ICON.ROCKET,
  },
})

-- pokefirered/src/slot_machine.c:388
SlotMachine.PAYOUT_TABLE = zeroBased({ 0, 2, 6, 8, 15, 100, 300 })

-- pokefirered/src/field_specials.c:362
SlotMachine.MACHINE_CLASS_BY_ID = zeroBased({
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 5,
})
SlotMachine.NUM_MACHINE_IDS = 22

-- pokefirered/include/constants/game_stat.h:32
SlotMachine.GAME_STAT_SLOT_JACKPOTS = 28

-- pokefirered/src/slot_machine.c:1361
local PRE_STRIP = {}
do
  -- pokefirered/src/slot_machine.c:261
  local tail = SlotMachine.BIAS_CHANCES[SlotMachine.NUM_MACHINE_CLASSES - 1]
  local at = 1
  for i = SlotMachine.NUM_PAYOUT_TYPES - 1, SlotMachine.NUM_PAYOUT_TYPES - 2, -1 do
    PRE_STRIP[at] = math.floor(tail[i] / 256)
    PRE_STRIP[at + 1] = tail[i] % 256
    at = at + 2
  end
end

local REELS = SlotMachine.REELS
local ROW_ATTRIBUTES = SlotMachine.ROW_ATTRIBUTES
local SECOND_REEL_BIAS_CHECK = SlotMachine.SECOND_REEL_BIAS_CHECK
local THIRD_REEL_BIAS_CHECK = SlotMachine.THIRD_REEL_BIAS_CHECK
local BIAS_CHANCES = SlotMachine.BIAS_CHANCES
local PAYOUT_TABLE = SlotMachine.PAYOUT_TABLE

local NO_ICON = 7

-- pokefirered/src/slot_machine.c:318
function SlotMachine.iconAt(reel, pos)
  local flat = reel * REEL_LENGTH + pos
  if flat < 0 then
    return PRE_STRIP[-flat] or NO_ICON
  end
  local strip = REELS[math.floor(flat / REEL_LENGTH)]
  if not strip then return NO_ICON end
  return strip[flat % REEL_LENGTH]
end

-- pokefirered/src/slot_machine.c:1638
function SlotMachine.testIconAttribute(attr, icon)
  if attr == PAYOUT.NONE then
    return icon ~= ICON.CHERRIES
  elseif attr == PAYOUT.CHERRIES2 or attr == PAYOUT.CHERRIES3 then
    return icon == ICON.CHERRIES
  elseif attr == PAYOUT.MAGSHELL then
    return icon == ICON.MAGNEMITE or icon == ICON.SHELLDER
  elseif attr == PAYOUT.PIKAPSY then
    return icon == ICON.PIKACHU or icon == ICON.PSYDUCK
  elseif attr == PAYOUT.ROCKET then
    return icon == ICON.ROCKET
  elseif attr == PAYOUT.SEVEN then
    return icon == ICON.SEVEN
  end
  return false
end

-- pokefirered/src/slot_machine.c:1660
function SlotMachine.iconToPayoutRank(icon)
  if icon == ICON.MAGNEMITE or icon == ICON.SHELLDER then return PAYOUT.MAGSHELL end
  if icon == ICON.PIKACHU or icon == ICON.PSYDUCK then return PAYOUT.PIKAPSY end
  if icon == ICON.ROCKET then return PAYOUT.ROCKET end
  if icon == ICON.SEVEN then return PAYOUT.SEVEN end
  return PAYOUT.CHERRIES2
end

-- pokefirered/src/slot_machine.c:253
function SlotMachine.linesForBet(bet)
  bet = math.floor(tonumber(bet) or 0)
  local out = {}
  for line = 0, NUM_MATCH_LINES - 1 do
    if bet >= ROW_ATTRIBUTES[line][SlotMachine.ROWATTR.MINBET] then
      out[#out + 1] = line
    end
  end
  return out
end

function SlotMachine.payoutFor(rank)
  return PAYOUT_TABLE[rank] or 0
end

local function rng()
  return require("src.core.game3.rng")
end

-- pokefirered/src/slot_machine.c:880
function SlotMachine.newState(machineIdx)
  machineIdx = math.floor(tonumber(machineIdx) or 0)
  -- pokefirered/src/slot_machine.c:871
  if machineIdx < 0 or machineIdx >= SlotMachine.NUM_MACHINE_CLASSES then machineIdx = 0 end
  local st = {
    machineIdx = machineIdx,
    currentReel = 0,
    bet = 0,
    payout = 0,
    machineBias = 0,
    slotRewardClass = 0,
    biasCooldown = 0,
    reel2BiasInPlay = 0,
    reelIsSpinning = {},
    reelPositions = {},
    reelSubpixel = {},
    destReelPos = {},
    reelStopOrder = {},
    winFlags = {},
  }
  for i = 0, NUM_REELS - 1 do
    st.reelIsSpinning[i] = false
    st.reelPositions[i] = 0
    st.reelSubpixel[i] = 0
    st.destReelPos[i] = REEL_LENGTH
    st.reelStopOrder[i] = 0
  end
  for i = 0, NUM_MATCH_LINES - 1 do
    st.winFlags[i] = false
  end
  return st
end

-- pokefirered/src/slot_machine.c:1304
function SlotMachine.startReels(st)
  for i = 0, NUM_REELS - 1 do
    st.reelIsSpinning[i] = true
  end
end

-- pokefirered/src/slot_machine.c:1328
function SlotMachine.isReelSpinning(st, reel)
  return st.reelIsSpinning[reel] and true or false
end

-- pokefirered/src/slot_machine.c:1274
function SlotMachine.spinStep(st)
  for i = 0, NUM_REELS - 1 do
    if st.reelIsSpinning[i] or st.reelSubpixel[i] ~= 0 then
      local settled = true
      if st.reelSubpixel[i] ~= 0 or st.reelPositions[i] ~= st.destReelPos[i] then
        st.reelSubpixel[i] = st.reelSubpixel[i] + 1
        if st.reelSubpixel[i] > 2 then
          st.reelSubpixel[i] = 0
          st.reelPositions[i] = st.reelPositions[i] - 1
          if st.reelPositions[i] < 0 then
            st.reelPositions[i] = REEL_LENGTH - 1
          end
        end
        if st.reelPositions[i] ~= st.destReelPos[i] then
          settled = false
        end
      end
      if settled then
        st.destReelPos[i] = REEL_LENGTH
        st.reelIsSpinning[i] = false
      end
    end
  end
end

-- pokefirered/src/slot_machine.c:1333
local function nextReelPosition(st, reel)
  local pos = st.reelPositions[reel]
  if st.reelSubpixel[reel] ~= 0 then
    pos = pos - 1
    if pos < 0 then pos = REEL_LENGTH - 1 end
  end
  return pos
end
SlotMachine.nextReelPosition = nextReelPosition

-- pokefirered/src/slot_machine.c:1495
local function twoReelBiasCheck(reel0id, reel0pos, reel1id, reel1pos, icon)
  local icons = {}
  for i = 0, 8 do icons[i] = NO_ICON end
  for i = 0, 2 do
    icons[3 * reel0id + i] = SlotMachine.iconAt(reel0id, reel0pos)
    icons[3 * reel1id + i] = SlotMachine.iconAt(reel1id, reel1pos)
    reel0pos = reel0pos + 1
    if reel0pos >= REEL_LENGTH then reel0pos = 0 end
    reel1pos = reel1pos + 1
    if reel1pos >= REEL_LENGTH then reel1pos = 0 end
  end
  if icon == 0 then
    for i = 0, 2 do
      if SlotMachine.testIconAttribute(1, icons[i]) then return false end
    end
    for i = 0, 14 do
      if icons[SECOND_REEL_BIAS_CHECK[i][0]] == icons[SECOND_REEL_BIAS_CHECK[i][1]] then
        return true
      end
    end
    return false
  elseif icon == 1 then
    if reel0id == 0 or reel1id == 0 then
      if reel0id == 1 or reel1id == 1 then
        for i = 0, 14, 3 do
          if icons[SECOND_REEL_BIAS_CHECK[i][0]] == icons[SECOND_REEL_BIAS_CHECK[i][1]] then
            return false
          end
        end
      end
      for i = 0, 2 do
        if SlotMachine.testIconAttribute(icon, icons[i]) then return true end
      end
      return false
    end
    return true
  elseif icon == 2 then
    if reel0id == 2 or reel1id == 2 then
      for i = 0, 8 do
        if SlotMachine.testIconAttribute(icon, icons[i]) then return true end
      end
      return false
    end
  end
  for i = 0, 14 do
    if icons[SECOND_REEL_BIAS_CHECK[i][0]] == icons[SECOND_REEL_BIAS_CHECK[i][1]]
        and SlotMachine.testIconAttribute(icon, icons[SECOND_REEL_BIAS_CHECK[i][0]]) then
      return true
    end
  end
  return false
end
SlotMachine.twoReelBiasCheck = twoReelBiasCheck

-- pokefirered/src/slot_machine.c:1568
local function oneReelBiasCheck(st, reelId, reelPos, biasIcon)
  local icons = {}
  local firstId = st.reelStopOrder[0]
  local secondId = st.reelStopOrder[1]
  local firstPos = st.reelPositions[firstId] + 1
  local secondPos = st.reelPositions[secondId] + 1
  reelPos = reelPos + 1
  if firstPos >= REEL_LENGTH then firstPos = 0 end
  if secondPos >= REEL_LENGTH then secondPos = 0 end
  if reelPos >= REEL_LENGTH then reelPos = 0 end
  for i = 0, 2 do
    icons[firstId * 3 + i] = SlotMachine.iconAt(firstId, firstPos)
    icons[secondId * 3 + i] = SlotMachine.iconAt(secondId, secondPos)
    icons[reelId * 3 + i] = SlotMachine.iconAt(reelId, reelPos)
    firstPos = firstPos + 1
    if firstPos >= REEL_LENGTH then firstPos = 0 end
    secondPos = secondPos + 1
    if secondPos >= REEL_LENGTH then secondPos = 0 end
    reelPos = reelPos + 1
    if reelPos >= REEL_LENGTH then reelPos = 0 end
  end
  if biasIcon == PAYOUT.NONE then
    for i = 0, 2 do
      if SlotMachine.testIconAttribute(1, icons[i]) then return false end
    end
    for i = 0, NUM_MATCH_LINES - 1 do
      local l = THIRD_REEL_BIAS_CHECK[i]
      if icons[l[0]] == icons[l[1]] and icons[l[0]] == icons[l[2]] then return false end
    end
    return true
  elseif biasIcon == PAYOUT.CHERRIES2 then
    for i = 0, NUM_MATCH_LINES - 1 do
      local l = THIRD_REEL_BIAS_CHECK[i]
      if icons[l[0]] == icons[l[1]] and SlotMachine.testIconAttribute(biasIcon, icons[l[0]]) then
        return false
      end
    end
    for i = 0, 2 do
      if SlotMachine.testIconAttribute(biasIcon, icons[i]) then return true end
    end
    return false
  elseif biasIcon == PAYOUT.CHERRIES3 then
    for i = 0, NUM_MATCH_LINES - 1 do
      local l = THIRD_REEL_BIAS_CHECK[i]
      if icons[l[0]] == icons[l[1]] and SlotMachine.testIconAttribute(biasIcon, icons[l[0]]) then
        return true
      end
    end
    return false
  end
  for i = 0, NUM_MATCH_LINES - 1 do
    local l = THIRD_REEL_BIAS_CHECK[i]
    if icons[l[0]] == icons[l[1]] and icons[l[0]] == icons[l[2]]
        and SlotMachine.testIconAttribute(biasIcon, icons[l[0]]) then
      return true
    end
  end
  return false
end
SlotMachine.oneReelBiasCheck = oneReelBiasCheck

-- pokefirered/src/slot_machine.c:1345
function SlotMachine.stopReel1(st, whichReel)
  local nextPos = nextReelPosition(st, whichReel)
  local posToSample = {}
  local numPosToSample = 0
  local destPos
  if st.machineBias == 0 and whichReel == 0 then
    for i = 0, 4 do
      local j = 0
      destPos = nextPos - i + 1
      while j < 3 do
        if destPos >= REEL_LENGTH then destPos = 0 end
        if SlotMachine.testIconAttribute(1, SlotMachine.iconAt(whichReel, destPos)) then break end
        j = j + 1
        destPos = destPos + 1
      end
      if j == 3 then
        posToSample[numPosToSample] = i
        numPosToSample = numPosToSample + 1
      end
    end
  elseif st.machineBias ~= 1 or whichReel == 0 then
    destPos = nextPos + 1
    for _ = 0, 2 do
      if destPos >= REEL_LENGTH then destPos = 0 end
      if SlotMachine.testIconAttribute(st.machineBias, SlotMachine.iconAt(whichReel, destPos)) then
        posToSample[0] = 0
        numPosToSample = 1
        break
      end
      destPos = destPos + 1
    end
    destPos = nextPos
    for i = 0, 3 do
      if destPos < 0 then destPos = REEL_LENGTH - 1 end
      if SlotMachine.testIconAttribute(st.machineBias, SlotMachine.iconAt(whichReel, destPos)) then
        posToSample[numPosToSample] = i + 1
        numPosToSample = numPosToSample + 1
      end
      destPos = destPos - 1
    end
  end
  if numPosToSample == 0 then
    destPos = rng().Random() % 5
  else
    destPos = posToSample[rng().Random() % numPosToSample]
  end
  destPos = nextPos - destPos
  if destPos < 0 then destPos = destPos + REEL_LENGTH end
  st.reelStopOrder[0] = whichReel
  st.destReelPos[whichReel] = destPos
end

-- pokefirered/src/slot_machine.c:1410
function SlotMachine.stopReel2(st, whichReel)
  local firstId = st.reelStopOrder[0]
  local firstPos = st.reelPositions[firstId] + 1
  if firstPos >= REEL_LENGTH then firstPos = 0 end
  local nextPos = nextReelPosition(st, whichReel)
  local pos = nextPos + 1
  if pos >= REEL_LENGTH then pos = 0 end
  local possible = {}
  local num = 0
  for i = 0, 4 do
    if twoReelBiasCheck(firstId, firstPos, whichReel, pos, st.machineBias) then
      possible[num] = i
      num = num + 1
    end
    pos = pos - 1
    if pos < 0 then pos = REEL_LENGTH - 1 end
  end
  if num == 0 then
    st.reel2BiasInPlay = 0
    if st.machineBias == PAYOUT.ROCKET or st.machineBias == PAYOUT.SEVEN then
      pos = 4
    else
      pos = 0
    end
  else
    st.reel2BiasInPlay = 1
    pos = possible[0]
  end
  pos = nextPos - pos
  if pos < 0 then pos = pos + REEL_LENGTH end
  st.reelStopOrder[1] = whichReel
  st.destReelPos[whichReel] = pos
end

-- pokefirered/src/slot_machine.c:1457
function SlotMachine.stopReel3(st, whichReel)
  local nextPos = nextReelPosition(st, whichReel)
  local testPos = nextPos
  local possible = {}
  local num = 0
  for i = 0, 4 do
    if oneReelBiasCheck(st, whichReel, testPos, st.machineBias) then
      possible[num] = i
      num = num + 1
    end
    testPos = testPos - 1
    if testPos < 0 then testPos = 20 end
  end
  local pos
  if num == 0 then
    if st.machineBias == PAYOUT.ROCKET or st.machineBias == PAYOUT.SEVEN then
      pos = 4
    else
      pos = 0
    end
  else
    pos = possible[0]
  end
  pos = nextPos - pos
  if pos < 0 then pos = pos + REEL_LENGTH end
  st.destReelPos[whichReel] = pos
end

-- pokefirered/src/slot_machine.c:1312
function SlotMachine.stopCurrentReel(st, whichReel, whichReel2)
  if whichReel2 == 0 then
    SlotMachine.stopReel1(st, whichReel)
  elseif whichReel2 == 1 then
    SlotMachine.stopReel2(st, whichReel)
  elseif whichReel2 == 2 then
    SlotMachine.stopReel3(st, whichReel)
  end
end

-- pokefirered/src/slot_machine.c:1680
function SlotMachine.calcBias(st)
  local R = rng()
  local rval = math.floor(R.Random() / 4)
  local chances = BIAS_CHANCES[st.machineIdx] or BIAS_CHANCES[0]
  local i = 0
  while i < SlotMachine.NUM_PAYOUT_TYPES - 1 do
    if rval < chances[i] then break end
    i = i + 1
  end
  if st.machineBias < PAYOUT.ROCKET then
    if st.biasCooldown == 0 then
      if (R.Random() % 0x4000) < chances[PAYOUT.SEVEN] then
        st.biasCooldown = ((R.Random() % 2) == 1) and 5 or 60
      end
    end
    if st.biasCooldown ~= 0 then
      if i == 0 and (R.Random() % 0x4000) < math.floor(0.7 * 0x3FFF) then
        st.biasCooldown = ((R.Random() % 2) == 1) and 5 or 60
      end
      st.biasCooldown = st.biasCooldown - 1
    end
    st.machineBias = i
  end
  return st.machineBias
end

-- pokefirered/src/slot_machine.c:1707
function SlotMachine.resetBias(st)
  st.machineBias = 0
end

-- pokefirered/src/slot_machine.c:1712
function SlotMachine.visibleIcons(st)
  local icons = {}
  local pos = { [0] = st.reelPositions[0], [1] = st.reelPositions[1], [2] = st.reelPositions[2] }
  for i = 0, 2 do
    for reel = 0, NUM_REELS - 1 do
      pos[reel] = pos[reel] + 1
      if pos[reel] >= REEL_LENGTH then pos[reel] = 0 end
      icons[reel * 3 + i] = SlotMachine.iconAt(reel, pos[reel])
    end
  end
  return icons
end

-- pokefirered/src/slot_machine.c:1712
function SlotMachine.calcPayout(st)
  for i = 0, NUM_MATCH_LINES - 1 do
    st.winFlags[i] = false
  end
  local icons = SlotMachine.visibleIcons(st)
  local bestMatch = 0
  st.payout = 0
  for i = 0, NUM_MATCH_LINES - 1 do
    local attr = ROW_ATTRIBUTES[i]
    if st.bet >= attr[SlotMachine.ROWATTR.MINBET] then
      local c1 = icons[attr[SlotMachine.ROWATTR.COL1POS]]
      local c2 = icons[attr[SlotMachine.ROWATTR.COL2POS]]
      local c3 = icons[attr[SlotMachine.ROWATTR.COL3POS]]
      local curMatch
      if SlotMachine.testIconAttribute(1, c1) then
        curMatch = SlotMachine.testIconAttribute(2, c2) and 2 or 1
      elseif c1 == c2 and c1 == c3 then
        curMatch = SlotMachine.iconToPayoutRank(c1)
      else
        curMatch = 0
      end
      if curMatch ~= 0 then
        st.winFlags[i] = true
        st.payout = st.payout + (PAYOUT_TABLE[curMatch] or 0)
      end
      if curMatch > bestMatch then bestMatch = curMatch end
    end
  end
  st.slotRewardClass = bestMatch
  return bestMatch
end

-- pokefirered/src/overworld.c:379
function SlotMachine.gameStat(session, statId)
  statId = tonumber(statId)
  if type(session) ~= "table" or not statId then return 0 end
  local stats = session.gameStats
  if type(stats) ~= "table" then return 0 end
  return math.floor(tonumber(stats[statId]) or 0)
end

-- pokefirered/src/overworld.c:366
function SlotMachine.incrementGameStat(session, statId)
  statId = tonumber(statId)
  if type(session) ~= "table" or not statId then return 0 end
  if type(session.gameStats) ~= "table" then session.gameStats = {} end
  local value = SlotMachine.gameStat(session, statId)
  if value < 0xFFFFFF then value = value + 1 else value = 0xFFFFFF end
  session.gameStats[statId] = value
  return value
end

local function coinsApi()
  local ok, Bag = pcall(require, "src.core.game3.bag")
  local api = (ok and type(Bag) == "table") and Bag.Coins or nil
  if type(api) ~= "table" then return nil end
  return api
end

function SlotMachine.coins(session)
  local api = coinsApi()
  if api and api.get then
    local ok, n = pcall(api.get, session)
    if ok and tonumber(n) then return tonumber(n) end
  end
  local raw = math.floor(tonumber(session and session.coins) or 0)
  return raw < 0 and 0 or raw
end

-- pokefirered/src/slot_machine.c:960
function SlotMachine.betOne(st, session)
  if SlotMachine.coins(session) == 0 then return false end
  local api = coinsApi()
  st.bet = st.bet + 1
  if api and api.remove then pcall(api.remove, session, 1) end
  return true
end

-- pokefirered/src/slot_machine.c:969
function SlotMachine.betMax(st, session)
  local api = coinsApi()
  local coins = SlotMachine.coins(session)
  if coins == 0 then return false end
  local toAdd = SlotMachine.MAX_BET - st.bet
  if coins >= toAdd then
    st.bet = SlotMachine.MAX_BET
    if api and api.remove then pcall(api.remove, session, toAdd) end
  else
    st.bet = st.bet + coins
    if api and api.set then pcall(api.set, session, 0) end
  end
  return true
end

-- pokefirered/src/slot_machine.c:1120
function SlotMachine.refundBet(st, session)
  local api = coinsApi()
  if st.bet > 0 and api and api.add then
    pcall(api.add, session, st.bet)
  end
  st.bet = 0
end

-- pokefirered/src/slot_machine.c:1213
function SlotMachine.payCoin(st, session)
  if st.payout <= 0 then return false end
  local api = coinsApi()
  if api and api.add then pcall(api.add, session, 1) end
  st.payout = st.payout - 1
  return true
end

-- pokefirered/src/slot_machine.c:1201
function SlotMachine.payAll(st, session)
  if st.payout <= 0 then return false end
  local api = coinsApi()
  if api and api.add then pcall(api.add, session, st.payout) end
  st.payout = 0
  return true
end

return SlotMachine
