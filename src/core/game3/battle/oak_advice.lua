-- pokefirered/src/battle_controller_oak_old_man.c:626

local RomText = require("src.core.game3.rom_text")
local BattleText = require("src.core.game3.battle.battle_text")

local Oak = {}

-- pokefirered/include/battle_controllers.h:287
Oak.FLAG_INFLICT_DMG = 1
Oak.FLAG_STAT_CHG = 2
Oak.FLAG_HP_RESTORE = 4
Oak.FLAG_PARTY_MENU = 8

-- pokefirered/src/battle_message.c:507
Oak.TEXT = {
  forPetesSake = { "gText_ForPetesSake", "gText_TheTrainerThat", "gText_TryBattling" },
  inflictingDamage = { "gText_InflictingDamageIsKey" },
  loweringStats = { "gText_LoweringStats" },
  keepAnEyeOnHp = { "gText_KeepAnEyeOnHP" },
  noRunning = { "gText_OakNoRunningFromATrainer" },
  winEarnsPrize = { "gText_WinEarnsPrizeMoney" },
  howDisappointing = { "gText_HowDissapointing" },
  -- pokefirered/src/strings.c:345
  partyMenu = { "gText_OakImportantToGetToKnowPokemonThroughly", "gText_OakThisIsListOfPokemon", field = true },
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

function Oak.pages(st, key)
  local keys = Oak.TEXT[key]
  if keys == nil then return nil end
  local name = st.playerName
  local out = {}
  for i = 1, #keys do
    if keys.field then
      out[i] = RomText.ascii(keys[i], { playerName = name })
    else
      out[i] = BattleText.get(keys[i], { playerName = name })
    end
  end
  return out
end

function Oak.screens(pages)
  local out = {}
  for _, page in ipairs(pages or {}) do
    for part in (tostring(page) .. "\\p"):gmatch("(.-)\\p") do
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
  local keys = Oak.TEXT[key]
  for i, p in ipairs(pages) do
    -- pokefirered/src/battle_bg.c:359
    if Ui.markVoiceover then Ui.markVoiceover(p) end
    sayFn(p, keys[i])
  end
  return true
end

function Oak.sayOnce(st, mask, key, sayFn)
  if not Oak.pending(st, mask) then return false end
  Oak.setFlag(st, mask)
  return Oak.say(st, key, sayFn)
end

return Oak
