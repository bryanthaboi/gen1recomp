-- pokefirered/src/battle_controller_oak_old_man.c:626

local Strings = require("src.core.Strings")

local Oak = {}

-- pokefirered/include/battle_controllers.h:287
Oak.FLAG_INFLICT_DMG = 1
Oak.FLAG_STAT_CHG = 2
Oak.FLAG_HP_RESTORE = 4
Oak.FLAG_PARTY_MENU = 8

-- pokefirered/src/battle_message.c:507
Oak.TEXT = {
  forPetesSake = {
    Strings.source("OAK: Oh, for Pete's sake…\nSo pushy, as always.\f{PLAYER}.\fYou've never had a POKéMON battle\nbefore, have you?\fA POKéMON battle is when TRAINERS\npit their POKéMON against each\nother."),
    Strings.source("The TRAINER that makes the other\nTRAINER's POKéMON faint by lowering\ntheir HP to “0,” wins."),
    Strings.source("But rather than talking about it,\nyou'll learn more from experience.\fTry battling and see for yourself."),
  },
  inflictingDamage = Strings.source("OAK: Inflicting damage on the foe\nis the key to any battle."),
  loweringStats = Strings.source("OAK: Lowering the foe's stats\nwill put you at an advantage."),
  keepAnEyeOnHp = Strings.source("OAK: Keep your eyes on your\nPOKéMON's HP.\fIt will faint if the HP drops to\n“0.”"),
  noRunning = Strings.source("OAK: No! There's no running away\nfrom a TRAINER POKéMON battle!"),
  winEarnsPrize = Strings.source("OAK: Hm! Excellent!\fIf you win, you earn prize money,\nand your POKéMON will grow!\fBattle other TRAINERS and make\nyour POKéMON strong!"),
  howDisappointing = Strings.source("OAK: Hm…\nHow disappointing…\fIf you win, you earn prize money,\nand your POKéMON grow.\fBut if you lose, {PLAYER}, you end\nup paying prize money…\fHowever, since you had no warning\nthis time, I'll pay for you.\fBut things won't be this way once\nyou step outside these doors.\fThat's why you must strengthen your\nPOKéMON by battling wild POKéMON."),
  -- pokefirered/src/strings.c:345
  partyMenu = {
    Strings.source("OAK: It's important to get to know\nyour POKéMON thoroughly."),
    Strings.source("This is a list of your POKéMON,\n{PLAYER}.\fOpen this to check the skills\nand moves of your POKéMON.\fYou also choose POKéMON here if\nyou want to use an item on one."),
  },
}

-- pokefirered/src/battle_setup.c:899
function Oak.active(st)
  return (st and st.firstBattle) and true or false
end

-- pokefirered/src/battle_controller_oak_old_man.c:2228
function Oak.testFlag(st, mask)
  if not st or not mask or mask <= 0 then return false end
  return math.floor((tonumber(st.oakMsgFlags) or 0) / mask) % 2 == 1
end

function Oak.setFlag(st, mask)
  if not st or not mask or mask <= 0 then return end
  if Oak.testFlag(st, mask) then return end
  st.oakMsgFlags = (tonumber(st.oakMsgFlags) or 0) + mask
end

function Oak.pending(st, mask)
  return Oak.active(st) and not Oak.testFlag(st, mask)
end

function Oak.expand(st, s)
  local name = (st and st.playerName) or "PLAYER"
  s = Strings(tostring(s or "")):gsub("{B_PLAYER_NAME}", name)
  return (s:gsub("{PLAYER}", name))
end

function Oak.pages(st, key)
  local raw = Oak.TEXT[key]
  if raw == nil then return nil end
  if type(raw) == "string" then raw = { raw } end
  local out = {}
  for i = 1, #raw do out[i] = Oak.expand(st, raw[i]) end
  return out
end

function Oak.screens(pages)
  local out = {}
  for _, page in ipairs(pages or {}) do
    for part in (tostring(page) .. "\f"):gmatch("(.-)\f") do
      if part ~= "" then out[#out + 1] = part end
    end
  end
  return out
end

-- pokefirered/src/party_menu.c:5832
function Oak.take(st, mask, key)
  if not Oak.pending(st, mask) then return nil end
  Oak.setFlag(st, mask)
  local pages = Oak.pages(st, key)
  if not pages or #pages == 0 then return nil end
  return Oak.screens(pages)
end

function Oak.say(st, key, sayFn)
  if not Oak.active(st) then return false end
  local pages = Oak.pages(st, key)
  if not pages or #pages == 0 then return false end
  local Ui = require("src.core.game3.battle.ui")
  if not sayFn then sayFn = function(t) Ui.push(t) end end
  for _, p in ipairs(pages) do
    -- pokefirered/src/battle_bg.c:359
    if Ui.markVoiceover then Ui.markVoiceover(p) end
    sayFn(p)
  end
  return true
end

function Oak.sayOnce(st, mask, key, sayFn)
  if not Oak.pending(st, mask) then return false end
  Oak.setFlag(st, mask)
  return Oak.say(st, key, sayFn)
end

return Oak
