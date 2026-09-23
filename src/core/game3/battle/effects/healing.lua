-- Healing / recover / wish / stockpile swallow (FRLG; KR-sourced; no KR require).

local H = require("src.core.game3.battle.effects._helpers")
local Rules = require("src.core.game3.battle.rules")

local Healing = {}

local function hp_full(ctx, b)
  ctx.adapter:sayText("STRINGID_PKMNHPFULL", { def = b })
end

-- pokefirered/data/battle_scripts_1.s:2515
function Healing.refresh(ctx)
  local st = ctx.adapter:status(ctx.user)
  local ok = st == "BRN" or st == "PSN" or st == "PAR" or st == "TOX"
  if not ok then return H.sayFail(ctx) end
  ctx.adapter:clearStatus(ctx.user)
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNSTATUSNORMAL", { atk = ctx.user })
end

-- pokefirered/data/battle_scripts_1.s:2372
function Healing.ingrain(ctx)
  if ctx.user.expIngrain then return H.sayFail(ctx) end
  ctx.user.expIngrain = true
  ctx.user.rooted = true
  ctx.user.expTrapped = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNPLANTEDROOTS", { atk = ctx.user })
end

-- pokefirered/src/battle_script_commands.c:6332
function Healing.recover(ctx)
  local maxHp = ctx.adapter:maxHp(ctx.user)
  local hp = ctx.adapter:hp(ctx.user)
  if hp >= maxHp then return hp_full(ctx, ctx.user) end
  local heal = math.floor(maxHp / 2)
  if heal == 0 then heal = 1 end
  H.attackAnim(ctx)
  ctx.adapter:heal(ctx.user, heal)
  ctx.adapter:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = ctx.user })
end

function Healing.softboiled(ctx)
  return Healing.recover(ctx)
end

-- pokefirered/src/battle_script_commands.c:8478
function Healing.morningSun(ctx)
  local ad, user = ctx.adapter, ctx.user
  local maxHp = ad:maxHp(user)
  if ad:hp(user) >= maxHp then return hp_full(ctx, user) end
  local weather = Rules.weather.effective(ad._st, ad)
  local heal
  if not weather then
    heal = math.floor(maxHp / 2)
  elseif weather == "SUN" then
    heal = math.floor(20 * maxHp / 30)
  else
    heal = math.floor(maxHp / 4)
  end
  if heal == 0 then heal = 1 end
  H.attackAnim(ctx)
  ad:heal(user, heal)
  ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = user })
end

-- pokefirered/data/battle_scripts_1.s:735
function Healing.rest(ctx)
  local ad, user = ctx.adapter, ctx.user
  if ad:status(user) == "SLP" then
    return ad:sayText("STRINGID_PKMNALREADYASLEEP2", { atk = user })
  end
  local Status = require("src.core.game3.battle.effects.status")
  if Status.cantMakeAsleep(ctx, user) then return end
  local maxHp = ad:maxHp(user)
  local hp = ad:hp(user)
  if hp >= maxHp then return hp_full(ctx, user) end
  local hadStatus = ad:status(user) ~= nil
  ad:clearStatus(user)
  user.status = "SLP"
  if user.mon then user.mon.status = "SLP" end
  -- pokefirered/src/battle_script_commands.c:6480
  user.sleepTurns = 3
  if hadStatus then
    ad:sayText("STRINGID_PKMNSLEPTHEALTHY", { atk = user })
  else
    ad:sayText("STRINGID_PKMNWENTTOSLEEP", { atk = user })
  end
  H.attackAnim(ctx)
  ad:heal(user, maxHp - hp)
  ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = user })
end

-- pokefirered/src/battle_script_commands.c:8399
function Healing.bellyDrum(ctx)
  local ad, user = ctx.adapter, ctx.user
  local maxHp = ad:maxHp(user)
  local half = math.floor(maxHp / 2)
  if half == 0 then half = 1 end
  local stages = ad:stages(user)
  if not stages or (stages.attack or 0) >= 6 or ad:hp(user) <= half then return H.sayFail(ctx) end
  stages.attack = 6
  H.attackAnim(ctx)
  ad:applyHpLoss(user, half)
  ad:sayText("STRINGID_PKMNCUTHPMAXEDATTACK", { atk = user })
end

-- pokefirered/src/battle_script_commands.c:8899
function Healing.wish(ctx)
  local side = ctx.adapter:ownSide(ctx.user)
  if not side then return H.sayFail(ctx) end
  side.tokens = side.tokens or {}
  local double = ctx.adapter._st and ctx.adapter._st.double
  for _, tok in ipairs(side.tokens) do
    if tok.id == "EXP_WISH" and (not double or tok.battlerId == ctx.user.id) then return H.sayFail(ctx) end
  end
  side.tokens[#side.tokens + 1] = {
    id = "EXP_WISH",
    turns = 2,
    wisher = ctx.adapter:displayName(ctx.user),
    battlerId = ctx.user.id,
  }
  H.attackAnim(ctx)
end

-- pokefirered/src/battle_script_commands.c:7995
function Healing.healBell(ctx)
  local ad, user = ctx.adapter, ctx.user
  local move = ctx.move or {}
  local isBell = tonumber(move.numId) == 215 or move.id == "HEAL_BELL"
  local State = require("src.core.game3.battle.state")
  local active = State.partyMon(user)
  local blocked = isBell and ad:abilityOf(user) == "SOUNDPROOF"
  -- battle_script_commands.c:8015-8016
  if not blocked then
    ad:clearStatus(user)
    user.expNightmare = nil
  end
  local partner = ad._st and ad._st.double and ad:partnerOf(user) or nil
  local partnerBlocked = partner and isBell and ad:abilityOf(partner) == "SOUNDPROOF"
  -- pokefirered/src/battle_script_commands.c:8023
  if partner and not partnerBlocked then
    ad:clearStatus(partner)
    partner.expNightmare = nil
  end
  local partnerMon = partner and State.partyMon(partner)
  for _, mon in ipairs(ad:partyMons(user)) do
    if mon and mon ~= active and mon ~= partnerMon and mon.status then
      mon.status = nil
      mon.sleep = nil
      -- battle_script_commands.c:8015
      mon.expNightmare = nil
    end
  end
  H.attackAnim(ctx)
  if isBell then
    ad:sayText("STRINGID_BELLCHIMED")
    local soundproof = H.abilityId("SOUNDPROOF")
    -- data/battle_scripts_1.s:1368
    if blocked then
      ad:sayText("STRINGID_PKMNSXBLOCKSY", { def = user, defAbility = soundproof, currentMove = 215 })
    end
    if partnerBlocked then
      ad:sayText("STRINGID_PKMNSXBLOCKSY2", { scrActive = partner, scrActiveAbility = soundproof, currentMove = 215 })
    end
  else
    ad:sayText("STRINGID_SOOTHINGAROMA")
  end
end

-- pokefirered/src/battle_script_commands.c:7674
function Healing.painSplit(ctx)
  local ad = ctx.adapter
  if not H.accuracy(ctx, "lockon") then return end
  if (ctx.target.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  local uHp = ad:hp(ctx.user)
  local tHp = ad:hp(ctx.target)
  local avg = math.floor((uHp + tHp) / 2)
  H.attackAnim(ctx)
  ad:setHp(ctx.user, math.min(ad:maxHp(ctx.user), avg))
  ad:setHp(ctx.target, math.min(ad:maxHp(ctx.target), avg))
  ad:sayText("STRINGID_SHAREDPAIN")
end

-- pokefirered/src/battle_script_commands.c:6612
function Healing.swallow(ctx)
  local ad, user = ctx.adapter, ctx.user
  local n = user.expStockpile or 0
  if n <= 0 then
    return ad:sayText("STRINGID_FAILEDTOSWALLOW")
  end
  local maxHp = ad:maxHp(user)
  user.expStockpile = 0
  user.stockpile = 0
  if ad:hp(user) >= maxHp then return hp_full(ctx, user) end
  local heal = math.floor(maxHp / (2 ^ (3 - n)))
  if heal == 0 then heal = 1 end
  H.attackAnim(ctx)
  ad:heal(user, heal)
  ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = user })
end

return Healing
