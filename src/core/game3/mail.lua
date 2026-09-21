local Mail = {}

-- pokefirered/include/constants/global.h:43
local MAIL_COUNT = 16
-- pokefirered/include/constants/global.h:65
local MAIL_WORDS_COUNT = 9
-- pokefirered/include/constants/global.h:78
local PARTY_SIZE = 6
-- pokefirered/include/constants/items.h:451
local MAIL_NONE = 0xFF
-- pokefirered/include/constants/items.h:4
local ITEM_NONE = 0
-- pokefirered/include/mail.h:21 FIRST_MAIL_IDX
local ITEM_ORANGE_MAIL = 121
-- pokefirered/include/constants/easy_chat.h:1091
local EC_WORD_UNDEFINED = 0xFFFF
-- pokefirered/include/constants/species.h:5
local SPECIES_BULBASAUR = 1
-- pokefirered/include/constants/species.h:208
local SPECIES_UNOWN = 201
-- pokefirered/src/mail_data.c:8
local UNOWN_OFFSET = 30000
-- pokefirered/include/pokemon.h:273
local NUM_UNOWN_FORMS = 28

Mail.MAIL_COUNT = MAIL_COUNT
Mail.MAIL_WORDS_COUNT = MAIL_WORDS_COUNT
Mail.MAIL_NONE = MAIL_NONE
Mail.PARTY_SIZE = PARTY_SIZE
Mail.ITEM_NONE = ITEM_NONE
Mail.EC_WORD_UNDEFINED = EC_WORD_UNDEFINED

-- pokefirered/src/mail_data.c:167 ItemIsMail
local MAIL_ITEMS = {
  [121] = true, [122] = true, [123] = true, [124] = true,
  [125] = true, [126] = true, [127] = true, [128] = true,
  [129] = true, [130] = true, [131] = true, [132] = true,
}

function Mail.isMailItem(itemId)
  return MAIL_ITEMS[tonumber(itemId) or -1] == true
end

-- pokefirered/include/mail.h:23 ITEM_TO_MAIL
function Mail.designOf(itemId)
  if not Mail.isMailItem(itemId) then return nil end
  return (tonumber(itemId) or 0) - ITEM_ORANGE_MAIL
end

-- pokefirered/src/pokemon_icon.c:1080 GetUnownLetterByPersonality
local function unown_letter(personality)
  local p = tonumber(personality) or 0
  if p == 0 then return 0 end
  p = p % 0x100000000
  local b3 = math.floor(p / 0x1000000) % 4
  local b2 = math.floor(p / 0x10000) % 4
  local b1 = math.floor(p / 0x100) % 4
  return (b3 * 64 + b2 * 16 + b1 * 4 + (p % 4)) % NUM_UNOWN_FORMS
end

-- pokefirered/src/mail_data.c:75 SpeciesToMailSpecies
function Mail.speciesToMailSpecies(species, personality)
  species = tonumber(species) or 0
  if species == SPECIES_UNOWN then
    return unown_letter(personality) + UNOWN_OFFSET
  end
  return species
end

-- pokefirered/src/mail_data.c:84 MailSpeciesToSpecies
function Mail.mailSpeciesToSpecies(mailSpecies)
  mailSpecies = tonumber(mailSpecies) or 0
  if mailSpecies >= UNOWN_OFFSET and mailSpecies < UNOWN_OFFSET + NUM_UNOWN_FORMS then
    return SPECIES_UNOWN, mailSpecies - UNOWN_OFFSET
  end
  return mailSpecies, 0
end

-- pokefirered/src/mail_data.c:18 ClearMailStruct
function Mail.clear(record)
  record = type(record) == "table" and record or {}
  local words = type(record.words) == "table" and record.words or {}
  for i = 1, MAIL_WORDS_COUNT do words[i] = EC_WORD_UNDEFINED end
  record.words = words
  record.playerName = ""
  record.trainerId = 0
  record.species = SPECIES_BULBASAUR
  record.itemId = ITEM_NONE
  record.design = nil
  return record
end

function Mail.copy(record)
  if type(record) ~= "table" then return nil end
  local words = {}
  for i = 1, MAIL_WORDS_COUNT do
    words[i] = tonumber(record.words and record.words[i]) or EC_WORD_UNDEFINED
  end
  return {
    words = words,
    playerName = tostring(record.playerName or ""),
    trainerId = tonumber(record.trainerId) or 0,
    species = tonumber(record.species) or SPECIES_BULBASAUR,
    itemId = tonumber(record.itemId) or ITEM_NONE,
    design = tonumber(record.design),
  }
end

function Mail.isEmpty(record)
  return type(record) ~= "table" or (tonumber(record.itemId) or ITEM_NONE) == ITEM_NONE
end

-- pokefirered/include/global.h:798 gSaveBlock1Ptr->mail
function Mail.pool(session)
  if type(session) ~= "table" then return nil end
  local pool = session.mail
  if type(pool) ~= "table" then
    pool = {}
    session.mail = pool
  end
  for i = 1, MAIL_COUNT do
    if type(pool[i]) ~= "table" then pool[i] = Mail.clear(nil) end
  end
  return pool
end

function Mail.slot(session, mailId)
  local id = tonumber(mailId)
  if not id or id == MAIL_NONE or id < 0 or id >= MAIL_COUNT then return nil end
  local pool = Mail.pool(session)
  return pool and pool[id + 1] or nil
end

function Mail.get(session, mailId)
  local record = Mail.slot(session, mailId)
  if Mail.isEmpty(record) then return nil end
  return record
end

-- pokefirered/src/mail_data.c:32 MonHasMail
function Mail.monHasMail(mon)
  if type(mon) ~= "table" then return false end
  local mailId = tonumber(mon.mail)
  if not mailId or mailId == MAIL_NONE then return false end
  return Mail.isMailItem(mon.item or mon.heldItem)
end

local function set_held_item(mon, itemId)
  mon.item = itemId
  mon.heldItem = itemId
end

-- pokefirered/src/mail_data.c:41 GiveMailToMon
function Mail.giveMailToMon(session, mon, itemId)
  itemId = tonumber(itemId) or ITEM_NONE
  local pool = Mail.pool(session)
  if not (pool and type(mon) == "table") then return MAIL_NONE end
  for id = 0, PARTY_SIZE - 1 do
    local record = pool[id + 1]
    if (tonumber(record.itemId) or ITEM_NONE) == ITEM_NONE then
      Mail.clear(record)
      record.playerName = tostring(session.name or session.playerName or "")
      record.trainerId = tonumber(session.trainerId or session.id or session.playerId) or 0
      record.species = Mail.speciesToMailSpecies(mon.species or mon.speciesId, mon.personality)
      record.itemId = itemId
      record.design = Mail.designOf(itemId)
      mon.mail = id
      set_held_item(mon, itemId)
      return id
    end
  end
  return MAIL_NONE
end

-- pokefirered/src/mail_data.c:100 GiveMailToMon2
function Mail.giveMailToMon2(session, mon, record)
  if type(record) ~= "table" then return MAIL_NONE end
  local itemId = tonumber(record.itemId) or ITEM_NONE
  local mailId = Mail.giveMailToMon(session, mon, itemId)
  if mailId == MAIL_NONE then return MAIL_NONE end
  local pool = Mail.pool(session)
  pool[mailId + 1] = Mail.copy(record)
  mon.mail = mailId
  set_held_item(mon, itemId)
  return mailId
end

-- pokefirered/src/mail_data.c:123 TakeMailFromMon
function Mail.takeMailFromMon(session, mon)
  if not Mail.monHasMail(mon) then return nil end
  local record = Mail.slot(session, mon.mail)
  if record then record.itemId = ITEM_NONE end
  mon.mail = nil
  set_held_item(mon, ITEM_NONE)
  return record
end

-- pokefirered/src/daycare.c:427 StorePokemonInDaycare
function Mail.takeMonMailForDaycare(session, mon, otName, monName)
  if not Mail.monHasMail(mon) then return nil end
  local message = Mail.copy(Mail.slot(session, mon.mail))
  Mail.takeMailFromMon(session, mon)
  if not message then return nil end
  -- pokefirered/include/global.h:533 struct DayCareMail
  return { message = message, otName = tostring(otName or ""), monName = tostring(monName or "") }
end

-- pokefirered/src/daycare.c:526 TakeSelectedPokemonFromDaycare
function Mail.giveDaycareMailToMon(session, mon, daycareMail)
  if type(daycareMail) ~= "table" then return false end
  local message = daycareMail.message
  if Mail.isEmpty(message) then return false end
  if Mail.giveMailToMon2(session, mon, message) == MAIL_NONE then return false end
  -- pokefirered/src/daycare.c:614 ClearDaycareMonMail
  daycareMail.otName = ""
  daycareMail.monName = ""
  Mail.clear(message)
  return true
end

function Mail.export(session)
  if type(session) ~= "table" or type(session.mail) ~= "table" then return nil end
  local pool = Mail.pool(session)
  if not pool then return nil end
  local out, used = {}, false
  for i = 1, MAIL_COUNT do
    out[i] = Mail.copy(pool[i])
    if not Mail.isEmpty(out[i]) then used = true end
  end
  if not used then return nil end
  return out
end

function Mail.restore(saved)
  if type(saved) ~= "table" then return nil end
  local pool = {}
  for i = 1, MAIL_COUNT do
    local record = saved[i]
    pool[i] = (type(record) == "table" and Mail.copy(record)) or Mail.clear(nil)
  end
  return pool
end

return Mail
