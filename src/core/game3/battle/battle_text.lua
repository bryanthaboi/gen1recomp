-- src/battle_message.c:1523 BufferStringBattle, :1829 BattleStringExpandPlaceholders

local TextIR = require("src.core.game3.scripting.text_ir")
local RomText = require("src.core.game3.rom_text")

local BattleText = {}

-- include/constants/battle_string_ids.h:4-9
BattleText.INTROMSG = 0
BattleText.INTROSENDOUT = 1
BattleText.RETURNMON = 2
BattleText.SWITCHINMON = 3
BattleText.USEDMOVE = 4
BattleText.BATTLEEND = 5
-- include/constants/moves.h:360
BattleText.MOVES_COUNT = 355

local SPECIAL = {
  STRINGID_INTROMSG = 0, STRINGID_INTROSENDOUT = 1, STRINGID_RETURNMON = 2,
  STRINGID_SWITCHINMON = 3, STRINGID_USEDMOVE = 4, STRINGID_BATTLEEND = 5,
}

local function need(fill, field, code)
  local v = fill[field]
  if v == nil then
    error(string.format("battle text {%s} needs fill.%s", TextIR.B_TXT[code] or tostring(code), field), 0)
  end
  return v
end

local function isPlayer(ref)
  local side = type(ref) == "table" and ref.side or ref
  return side == "player" or side == 0
end

local function monName(ref)
  if type(ref) == "string" then return ref end
  if ref.name then return ref.name end
  return require("src.core.game3.battle.state").displayName(ref)
end

-- src/battle_message.c:1807 HANDLE_NICKNAME_STRING_CASE
local function withPrefix(fill, ref)
  if isPlayer(ref) then return monName(ref) end
  local prefix = fill.trainer and "sText_FoePkmnPrefix" or "sText_WildPkmnPrefix"
  return RomText.plain(prefix) .. monName(ref)
end

local function moveName(fill, move)
  if type(move) == "string" then return move end
  if move >= BattleText.MOVES_COUNT then
    return RomText.plain(RomText.key("sATypeMove_Table", need(fill, "moveType", 0x14)))
  end
  return require("src.core.game3.pokemon").moveName(move)
end

local function abilityName(ability)
  if type(ability) == "string" then return ability end
  return require("src.core.game3.pokemon").abilityName(ability)
end

local function itemName(item)
  if type(item) == "string" then return item end
  return require("src.core.game3.items_data").displayName(item)
end

local function prefix(fill, field, code, ally, foe)
  return RomText.plain(isPlayer(need(fill, field, code)) and ally or foe)
end

local RESOLVE = {
  [0x00] = function(f) return need(f, "buff1", 0x00) end,
  [0x01] = function(f) return need(f, "buff2", 0x01) end,
  [0x30] = function(f) return need(f, "buff3", 0x30) end,
  [0x02] = function(f) return need(f, "stringVars", 0x02)[1] end,
  [0x03] = function(f) return need(f, "stringVars", 0x03)[2] end,
  [0x04] = function(f) return need(f, "stringVars", 0x04)[3] end,
  [0x05] = function(f) return monName(need(f, "playerMon1", 0x05)) end,
  [0x06] = function(f) return monName(need(f, "opponentMon1", 0x06)) end,
  [0x07] = function(f) return monName(need(f, "playerMon2", 0x07)) end,
  [0x08] = function(f) return monName(need(f, "opponentMon2", 0x08)) end,
  [0x09] = function(f) return monName(need(f, "linkPlayerMon1", 0x09)) end,
  [0x0A] = function(f) return monName(need(f, "linkOpponentMon1", 0x0A)) end,
  [0x0B] = function(f) return monName(need(f, "linkPlayerMon2", 0x0B)) end,
  [0x0C] = function(f) return monName(need(f, "linkOpponentMon2", 0x0C)) end,
  [0x0D] = function(f) return withPrefix(f, need(f, "atkMon1", 0x0D)) end,
  [0x0E] = function(f) return monName(need(f, "atkPartner", 0x0E)) end,
  [0x0F] = function(f) return withPrefix(f, need(f, "atk", 0x0F)) end,
  [0x10] = function(f) return withPrefix(f, need(f, "def", 0x10)) end,
  [0x11] = function(f) return withPrefix(f, need(f, "eff", 0x11)) end,
  [0x12] = function(f) return withPrefix(f, need(f, "active", 0x12)) end,
  [0x13] = function(f) return withPrefix(f, need(f, "scrActive", 0x13)) end,
  [0x14] = function(f) return moveName(f, need(f, "currentMove", 0x14)) end,
  [0x15] = function(f) return moveName(f, need(f, "lastMove", 0x15)) end,
  [0x16] = function(f) return itemName(need(f, "lastItem", 0x16)) end,
  [0x17] = function(f) return abilityName(need(f, "lastAbility", 0x17)) end,
  [0x18] = function(f) return abilityName(need(f, "atkAbility", 0x18)) end,
  [0x19] = function(f) return abilityName(need(f, "defAbility", 0x19)) end,
  [0x1A] = function(f) return abilityName(need(f, "scrActiveAbility", 0x1A)) end,
  [0x1B] = function(f) return abilityName(need(f, "effAbility", 0x1B)) end,
  [0x1C] = function(f)
    local class = need(f, "trainer1Class", 0x1C)
    if type(class) == "string" then return class end
    return RomText.plain(RomText.key("gTrainerClassNames", class))
  end,
  [0x1D] = function(f) return need(f, "trainer1Name", 0x1D) end,
  [0x1E] = function(f) return need(f, "linkPlayerName", 0x1E) end,
  [0x1F] = function(f) return need(f, "linkPartnerName", 0x1F) end,
  [0x20] = function(f) return need(f, "linkOpponent1Name", 0x20) end,
  [0x21] = function(f) return need(f, "linkOpponent2Name", 0x21) end,
  [0x22] = function(f) return need(f, "linkScrTrainerName", 0x22) end,
  [0x23] = function(f) return need(f, "playerName", 0x23) end,
  [0x24] = function(f) return need(f, "trainer1LoseText", 0x24) end,
  [0x25] = function(f) return need(f, "trainer1WinText", 0x25) end,
  [0x26] = function(f) return withPrefix(f, need(f, "scrActivePartyMon", 0x26)) end,
  [0x27] = function(f)
    return RomText.plain(need(f, "billsPc", 0x27) and "sText_Bills" or "sText_Someones")
  end,
  [0x28] = function(f) return prefix(f, "atk", 0x28, "sText_AllyPkmnPrefix", "sText_FoePkmnPrefix2") end,
  [0x29] = function(f) return prefix(f, "def", 0x29, "sText_AllyPkmnPrefix", "sText_FoePkmnPrefix2") end,
  [0x2A] = function(f) return prefix(f, "atk", 0x2A, "sText_AllyPkmnPrefix2", "sText_FoePkmnPrefix3") end,
  [0x2B] = function(f) return prefix(f, "def", 0x2B, "sText_AllyPkmnPrefix2", "sText_FoePkmnPrefix3") end,
  [0x2C] = function(f) return prefix(f, "atk", 0x2C, "sText_AllyPkmnPrefix3", "sText_FoePkmnPrefix4") end,
  [0x2D] = function(f) return prefix(f, "def", 0x2D, "sText_AllyPkmnPrefix3", "sText_FoePkmnPrefix4") end,
  [0x2E] = function(f) return need(f, "trainer2LoseText", 0x2E) end,
  [0x2F] = function(f) return need(f, "trainer2WinText", 0x2F) end,
}

function BattleText.context(fill)
  fill = fill or {}
  local values = setmetatable({}, {
    __index = function(t, code)
      local resolve = RESOLVE[code]
      if not resolve then
        error("battle text placeholder code " .. tostring(code) .. " is not a B_TXT id", 0)
      end
      local v = resolve(fill)
      rawset(t, code, v)
      return v
    end,
  })
  return { battle = values, stringVars = fill.stringVars, playerName = fill.playerName,
    rivalName = fill.rivalName, maxWidth = fill.maxWidth }
end

-- src/battle_message.c:1551-1766
local function special(id, fill)
  if id == 0 then
    if fill.trainer then
      if fill.link then
        if fill.multi then return "sText_TwoLinkTrainersWantToBattle" end
        return fill.unionRoom and "sText_Trainer1WantsToBattle" or "sText_LinkTrainerWantsToBattle"
      end
      return "sText_Trainer1WantsToBattle"
    end
    if fill.ghost then
      return fill.ghostUnveiled and "sText_TheGhostAppeared" or "sText_GhostAppearedCantId"
    elseif fill.legendary then
      return "sText_WildPkmnAppeared2"
    elseif fill.double then
      return "sText_TwoWildPkmnAppeared"
    elseif fill.oldMan then
      return "sText_WildPkmnAppearedPause"
    end
    return "sText_WildPkmnAppeared"
  elseif id == 1 then
    if isPlayer(need(fill, "side", 0)) then
      if fill.double then
        return fill.multi and "sText_LinkPartnerSentOutPkmnGoPkmn" or "sText_GoTwoPkmn"
      end
      return "sText_GoPkmn"
    end
    if fill.double then
      if fill.multi then return "sText_TwoLinkTrainersSentOutPkmn" end
      return fill.link and "sText_LinkTrainerSentOutTwoPkmn" or "sText_Trainer1SentOutTwoPkmn"
    end
    if not fill.link or fill.unionRoom then return "sText_Trainer1SentOutPkmn" end
    return "sText_LinkTrainerSentOutPkmn"
  elseif id == 2 then
    if isPlayer(need(fill, "side", 0)) then
      local scale = need(fill, "hpScale", 0)
      if scale == 0 then return "sText_PkmnThatsEnough" end
      if scale == 1 or fill.double then return "sText_PkmnComeBack" end
      if scale == 2 then return "sText_PkmnOkComeBack" end
      return "sText_PkmnGoodComeBack"
    end
    if fill.linkOpponent then
      return fill.multi and "sText_LinkTrainer2WithdrewPkmn" or "sText_LinkTrainer1WithdrewPkmn"
    end
    return "sText_Trainer1WithdrewPkmn"
  elseif id == 3 then
    if isPlayer(need(fill, "side", 0)) then
      local scale = need(fill, "hpScale", 0)
      if scale == 0 or fill.double then return "sText_GoPkmn2" end
      if scale == 1 then return "sText_DoItPkmn" end
      if scale == 2 then return "sText_GoForItPkmn" end
      return "sText_YourFoesWeakGetEmPkmn"
    end
    if fill.link then
      if fill.multi then return "sText_LinkTrainerMultiSentOutPkmn" end
      return fill.unionRoom and "sText_Trainer1SentOutPkmn2" or "sText_LinkTrainerSentOutPkmn2"
    end
    return "sText_Trainer1SentOutPkmn2"
  elseif id == 4 then
    local copy = {}
    for k, v in pairs(fill) do copy[k] = v end
    copy.buff2 = moveName(fill, need(fill, "currentMove", 0x14)) .. RomText.plain("sText_ExclamationMark")
    return "sText_AttackerUsedX", copy
  elseif id == 5 then
    local outcome = need(fill, "outcome", 0)
    if fill.linkRan then
      if outcome == "lost" or outcome == "drew" then return "sText_GotAwaySafely" end
      if fill.multi then return "sText_TwoWildFled" end
      return fill.unionRoom and "sText_Trainer1Fled" or "sText_WildFled"
    end
    if fill.multi then
      return ({ won = "sText_TwoLinkTrainersDefeated", lost = "sText_PlayerLostToTwo",
        drew = "sText_PlayerBattledToDrawVsTwo" })[outcome]
    elseif fill.unionRoom then
      return ({ won = "sText_PlayerDefeatedLinkTrainerTrainer1", lost = "sText_PlayerLostAgainstTrainer1",
        drew = "sText_PlayerBattledToDrawTrainer1" })[outcome]
    end
    return ({ won = "sText_PlayerDefeatedLinkTrainer", lost = "sText_PlayerLostAgainstLinkTrainer",
      drew = "sText_PlayerBattledToDrawLinkTrainer" })[outcome]
  end
end

function BattleText.key(id, fill)
  fill = fill or {}
  if type(id) == "string" and SPECIAL[id] then id = SPECIAL[id] end
  if type(id) == "number" then
    if id < 12 then
      local key, over = special(id, fill)
      return assert(key, "battle string id " .. id .. " has no text for this battle"), over or fill
    end
    local Versions = require("src.import.gba.versions")
    return assert(Versions.BATTLE_STRING_IDS[id], "no battle string id " .. id), fill
  end
  return id, fill
end

function BattleText.ir(id, fill)
  local key = BattleText.key(id, fill)
  return RomText.ir(key)
end

function BattleText.get(id, fill)
  local key, f = BattleText.key(id, fill)
  local ctx = BattleText.context(f)
  return TextIR.toAscii(RomText.translate(RomText.ir(key), ctx, key), ctx)
end

BattleText.expand = BattleText.get

return BattleText
