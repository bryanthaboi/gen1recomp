local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local FameChecker = {}

-- pokefirered/include/constants/fame_checker.h:4
FameChecker.PERSON = {
  OAK = 0,
  DAISY = 1,
  BROCK = 2,
  MISTY = 3,
  LTSURGE = 4,
  ERIKA = 5,
  KOGA = 6,
  SABRINA = 7,
  BLAINE = 8,
  LORELEI = 9,
  BRUNO = 10,
  AGATHA = 11,
  LANCE = 12,
  BILL = 13,
  MRFUJI = 14,
  GIOVANNI = 15,
}

-- pokefirered/include/constants/fame_checker.h:20
FameChecker.NUM_PERSONS = 16
-- pokefirered/src/fame_checker.c:1158
FameChecker.NUM_FLAVOR_TEXTS = 6

-- pokefirered/include/constants/fame_checker.h:22
FameChecker.PICKSTATE = {
  NO_DRAW = 0,
  SILHOUETTE = 1,
  COLORED = 2,
}

-- pokefirered/src/fame_checker.c:32
FameChecker.NON_TRAINER_START = 0xFE00

-- pokefirered/src/fame_checker.c:145 sTrainerIdxs
FameChecker.TRAINER_IDS = {
  [0] = 0xFE00,
  0xFE01,
  414,
  415,
  416,
  417,
  418,
  420,
  419,
  410,
  411,
  412,
  413,
  0xFE02,
  0xFE03,
  348,
}

-- pokefirered/src/fame_checker.c:1064
local TRAINER_LEADER_GIOVANNI = 350

local PICK = FameChecker.PICKSTATE

local function sessionOf(session)
  if type(session) == "table" then return session end
  local rt = package.loaded["src.core.game3.runtime"]
  local got = rt and rt.getSession and rt.getSession()
  if type(got) == "table" then return got end
  return nil
end

-- pokefirered/src/fame_checker.c:1140 ResetFameChecker
local function blankRecords()
  local recs = {}
  for i = 1, FameChecker.NUM_PERSONS do
    recs[i] = { pickState = PICK.NO_DRAW, flavorTextFlags = 0 }
  end
  recs[FameChecker.PERSON.OAK + 1].pickState = PICK.COLORED
  return recs
end

function FameChecker.records(session)
  session = sessionOf(session)
  if type(session) ~= "table" then return nil end
  local md = session.modData
  if type(md) ~= "table" then
    md = {}
    session.modData = md
  end
  local recs = session.fameChecker
  if type(recs) ~= "table" then recs = md.fameChecker end
  if type(recs) ~= "table" then recs = blankRecords() end
  for i = 1, FameChecker.NUM_PERSONS do
    local rec = recs[i]
    if type(rec) ~= "table" then
      rec = { pickState = PICK.NO_DRAW, flavorTextFlags = 0 }
      recs[i] = rec
    end
    rec.pickState = tonumber(rec.pickState) or PICK.NO_DRAW
    rec.flavorTextFlags = tonumber(rec.flavorTextFlags) or 0
  end
  session.fameChecker = recs
  md.fameChecker = recs
  return recs
end

function FameChecker.record(session, person)
  local p = tonumber(person)
  if not p or p < 0 or p >= FameChecker.NUM_PERSONS then return nil end
  local recs = FameChecker.records(session)
  if not recs then return nil end
  return recs[p + 1]
end

-- pokefirered/src/fame_checker.c:1140
function FameChecker.reset(session)
  session = sessionOf(session)
  if type(session) ~= "table" then return false end
  session.fameChecker = nil
  if type(session.modData) == "table" then session.modData.fameChecker = nil end
  return FameChecker.records(session) ~= nil
end

-- pokefirered/src/fame_checker.c:1152 FullyUnlockFameChecker
function FameChecker.fullyUnlock(session)
  local recs = FameChecker.records(session)
  if not recs then return false end
  local all = 0
  for j = 0, FameChecker.NUM_FLAVOR_TEXTS - 1 do
    all = bor(all, lshift(1, j))
  end
  for i = 1, FameChecker.NUM_PERSONS do
    recs[i].pickState = PICK.COLORED
    recs[i].flavorTextFlags = all
  end
  return true
end

-- pokefirered/src/fame_checker.c:1232 UpdatePickStateFromSpecialVar8005
function FameChecker.updatePickState(person, state, session)
  local p, st = tonumber(person), tonumber(state)
  if not p or not st then return false end
  if p < 0 or p >= FameChecker.NUM_PERSONS then return false end
  if st < 0 or st >= 3 then return false end
  if st == PICK.NO_DRAW then return false end
  local rec = FameChecker.record(session, p)
  if not rec then return false end
  if st == PICK.SILHOUETTE and rec.pickState == PICK.COLORED then return false end
  rec.pickState = st
  return true
end

-- pokefirered/src/fame_checker.c:1222 SetFlavorTextFlagFromSpecialVars
function FameChecker.setFlavorText(person, slot, session)
  local p, s = tonumber(person), tonumber(slot)
  if not p or not s then return false end
  if p < 0 or p >= FameChecker.NUM_PERSONS then return false end
  if s < 0 or s >= FameChecker.NUM_FLAVOR_TEXTS then return false end
  local rec = FameChecker.record(session, p)
  if not rec then return false end
  rec.flavorTextFlags = bor(rec.flavorTextFlags, lshift(1, s))
  FameChecker.updatePickState(p, PICK.SILHOUETTE, session)
  return true
end

function FameChecker.pickState(session, person)
  local rec = FameChecker.record(session, person)
  if not rec then return PICK.NO_DRAW end
  return rec.pickState
end

function FameChecker.flavorTextFlags(session, person)
  local rec = FameChecker.record(session, person)
  if not rec then return 0 end
  return rec.flavorTextFlags
end

function FameChecker.hasFlavorText(session, person, slot)
  local s = tonumber(slot)
  if not s or s < 0 or s >= FameChecker.NUM_FLAVOR_TEXTS then return false end
  local rec = FameChecker.record(session, person)
  if not rec then return false end
  return band(rshift(rec.flavorTextFlags, s), 1) == 1
end

-- pokefirered/src/fame_checker.c:1246 HasUnlockedAllFlavorTextsForCurrentPerson
function FameChecker.hasUnlockedAllFlavorTexts(session, person)
  local rec = FameChecker.record(session, person)
  if not rec then return false end
  for i = 0, FameChecker.NUM_FLAVOR_TEXTS - 1 do
    if band(rshift(rec.flavorTextFlags, i), 1) ~= 1 then return false end
  end
  return true
end

local function giovanniBeatenInGym(session)
  local Flags = require("src.core.game3.scripting.flags")
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = (Space and Space.store) or (type(session) == "table" and session.store) or nil
  if not store then return false end
  return Flags.isTrainerDefeated(store, nil, TRAINER_LEADER_GIOVANNI) and true or false
end

-- pokefirered/src/fame_checker.c:1062 AdjustGiovanniIndexIfBeatenInGym
function FameChecker.adjustGiovanniIndex(index, beaten)
  local i = tonumber(index) or 0
  if not beaten then return i end
  if i == 9 then return FameChecker.PERSON.GIOVANNI end
  if i > 9 then return i - 1 end
  return i
end

-- pokefirered/src/fame_checker.c:1546 FC_PopulateListMenu
function FameChecker.unlockedPersons(session)
  session = sessionOf(session)
  local recs = FameChecker.records(session)
  if not recs then return {} end
  local beaten = giovanniBeatenInGym(session)
  local list = {}
  for i = 0, FameChecker.NUM_PERSONS - 1 do
    local idx = FameChecker.adjustGiovanniIndex(i, beaten)
    if recs[idx + 1].pickState ~= PICK.NO_DRAW then
      list[#list + 1] = idx
    end
  end
  return list
end

return FameChecker
