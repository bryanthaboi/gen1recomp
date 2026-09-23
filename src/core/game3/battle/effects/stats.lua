-- Stat stage effects. ROM effect byte → STAT_CHANGES drives generic path.

local H = require("src.core.game3.battle.effects._helpers")
local EffectIds = require("src.core.game3.battle.effect_ids")
local Secondary = require("src.core.game3.battle.effects.secondary")

local Stats = {}

local ORDER = { "attack", "defense", "speed", "spAtk", "spDef", "accuracy", "evasion" }

function Stats.change(ctx, target, changes, isFoe)
  if isFoe and (target.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  for _, k in ipairs(ORDER) do
    local d = changes[k]
    if d and d ~= 0 then
      Secondary.changeStat(ctx.adapter, target, k, d, { allowPtr = true, user = not isFoe })
    end
  end
end

-- pokefirered/data/battle_scripts_1.s:491
local function stat_up(ctx, stat, delta)
  local ad, user = ctx.adapter, ctx.user
  if (user.stages[stat] or 0) >= 6 then
    ad:sayText("STRINGID_STATSWONTINCREASE", { atk = user, buff1 = Secondary.statName(stat) })
    local M = H.move(ctx)
    if M then M.failed = true end
    return
  end
  H.attackAnim(ctx)
  Secondary.changeStat(ad, user, stat, delta, { user = true, allowPtr = true })
end
Stats.statUp = stat_up

-- pokefirered/data/battle_scripts_1.s:536
local function stat_down(ctx, stat, delta)
  local ad, t = ctx.adapter, ctx.target
  if (t.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  if not H.accuracy(ctx, "normal") then return end
  local cur = t.stages[stat] or 0
  local side = ad:ownSide(t)
  local ab = ad:abilityOf(t)
  local blocked = (side and (side.expMistTurns or 0) > 0)
    or ab == "CLEAR_BODY" or ab == "WHITE_SMOKE"
    or (ab == "KEEN_EYE" and stat == "accuracy")
    or (ab == "HYPER_CUTTER" and stat == "attack")
  if not blocked and cur > -6 then H.attackAnim(ctx) end
  Secondary.changeStat(ad, t, stat, delta, { allowPtr = true })
end
Stats.statDown = stat_down

function Stats.fromRomEffect(ctx)
  local effect = tonumber(ctx.move and ctx.move.effect)
  local spec = effect and EffectIds.STAT_CHANGES[effect]
  if not spec then return H.sayFail(ctx) end
  for stat, d in pairs(spec.stages) do
    if spec.self then stat_up(ctx, stat, d) else stat_down(ctx, stat, d) end
  end
end

-- pokefirered/data/battle_scripts_1.s:1472
function Stats.minimize(ctx)
  ctx.user.minimized = true
  stat_up(ctx, "evasion", 1)
end

-- pokefirered/data/battle_scripts_1.s:2010
function Stats.defenseCurl(ctx)
  ctx.user.defenseCurl = true
  stat_up(ctx, "defense", 1)
end

local function multi_up(ctx, stats)
  local ad, user = ctx.adapter, ctx.user
  local any = false
  for _, s in ipairs(stats) do
    if (user.stages[s] or 0) < 6 then any = true end
  end
  if not any then
    local M = H.move(ctx)
    if M then M.failed = true end
    return ad:sayText("STRINGID_STATSWONTINCREASE2", { atk = user })
  end
  H.attackAnim(ctx)
  Secondary.multiStatAnim(ad, user, stats, 1)
  for _, s in ipairs(stats) do
    if (user.stages[s] or 0) < 6 then
      Secondary.changeStat(ad, user, s, 1, { user = true, allowPtr = true, noAnim = true })
    end
  end
end
Stats.multiUp = multi_up

-- pokefirered/data/battle_scripts_1.s:2733
function Stats.calmMind(ctx) multi_up(ctx, { "spAtk", "spDef" }) end
-- pokefirered/data/battle_scripts_1.s:2708
function Stats.bulkUp(ctx) multi_up(ctx, { "attack", "defense" }) end
-- pokefirered/data/battle_scripts_1.s:2765
function Stats.dragonDance(ctx) multi_up(ctx, { "attack", "speed" }) end
-- pokefirered/data/battle_scripts_1.s:2679
function Stats.cosmicPower(ctx) multi_up(ctx, { "defense", "spDef" }) end

function Stats.growl(ctx) stat_down(ctx, "attack", -1) end
function Stats.tailWhip(ctx) stat_down(ctx, "defense", -1) end
function Stats.leer(ctx) stat_down(ctx, "defense", -1) end
function Stats.harden(ctx) stat_up(ctx, "defense", 1) end
function Stats.swordsDance(ctx) stat_up(ctx, "attack", 2) end
function Stats.agility(ctx) stat_up(ctx, "speed", 2) end
function Stats.amnesia(ctx) stat_up(ctx, "spDef", 2) end

-- pokefirered/data/battle_scripts_1.s:2644
function Stats.tickle(ctx)
  local ad, t = ctx.adapter, ctx.target
  if (t.stages.attack or 0) <= -6 and (t.stages.defense or 0) <= -6 then
    local M = H.move(ctx)
    if M then M.failed = true end
    return ad:sayText("STRINGID_STATSWONTDECREASE2", { def = t })
  end
  if not H.accuracy(ctx, "normal") then return end
  H.attackAnim(ctx)
  Secondary.multiStatAnim(ad, t, { "attack", "defense" }, -1)
  Secondary.changeStat(ad, t, "attack", -1, { allowPtr = true, noAnim = true, noMsg = (t.stages.attack or 0) <= -6 })
  Secondary.changeStat(ad, t, "defense", -1, { allowPtr = true, noAnim = true, noMsg = (t.stages.defense or 0) <= -6 })
end

local function swagger_like(ctx, stat, delta)
  local ad, t = ctx.adapter, ctx.target
  local M = H.move(ctx)
  if (t.substituteHP or 0) > 0 then
    if M then M.anim.missed = true end
    return ad:sayText("STRINGID_ATTACKMISSED", { atk = ctx.user })
  end
  if not H.accuracy(ctx, "normal") then return end
  if (t.confusionTurns or 0) > 0 and (t.stages[stat] or 0) >= 6 then return H.sayFail(ctx) end
  H.attackAnim(ctx)
  if (t.stages[stat] or 0) < 6 then
    Secondary.changeStat(ad, t, stat, delta, { allowPtr = true })
  end
  if ad:abilityOf(t) == "OWN_TEMPO" then
    return ad:sayText("STRINGID_PKMNPREVENTSCONFUSIONWITH", { def = t, defAbility = H.abilityId("OWN_TEMPO") })
  end
  local side = ad:ownSide(t)
  if side and (side.expSafeguardTurns or 0) > 0 then
    return ad:sayText("STRINGID_PKMNUSEDSAFEGUARD", { def = t })
  end
  local ctxM = M or { adapter = ad, user = ctx.user, target = t, st = ad._st }
  Secondary.set(ctxM, "CONFUSION", true, false, false)
end

-- pokefirered/data/battle_scripts_1.s:1604
function Stats.swagger(ctx) swagger_like(ctx, "attack", 2) end
-- pokefirered/data/battle_scripts_1.s:2147
function Stats.flatter(ctx) swagger_like(ctx, "spAtk", 1) end

-- pokefirered/src/battle_script_commands.c:8423
function Stats.psychUp(ctx)
  local target = ctx.target
  if not target or not target.stages then return H.sayFail(ctx) end
  for _, s in ipairs(ORDER) do
    ctx.user.stages[s] = target.stages[s] or 0
  end
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNCOPIEDSTATCHANGES", { atk = ctx.user, def = target })
end

-- pokefirered/src/battle_script_commands.c:6568
function Stats.stockpile(ctx)
  local n = ctx.user.expStockpile or 0
  if n >= 3 then
    local M = H.move(ctx)
    if M then M.failed = true end
    return ctx.adapter:sayText("STRINGID_PKMNCANTSTOCKPILE", { atk = ctx.user })
  end
  ctx.user.expStockpile = n + 1
  ctx.user.stockpile = n + 1
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNSTOCKPILED", { atk = ctx.user, buff1 = tostring(n + 1) })
end

function Stats.clearStockpileBoost(user)
  if user then user.stockpile = 0 end
end

-- pokefirered/src/battle_script_commands.c:8709
function Stats.charge(ctx)
  ctx.user.expCharged = 2
  ctx.user.chargedUp = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNCHARGINGPOWER", { atk = ctx.user })
end

-- pokefirered/data/battle_scripts_1.s:2199
function Stats.memento(ctx)
  local ad, user, t = ctx.adapter, ctx.user, ctx.target
  local M = H.move(ctx)
  local protected = M and M:isProtected()
  if not protected and (t.stages.attack or 0) <= -6 and (t.stages.spAtk or 0) <= -6 then
    return H.sayFail(ctx)
  end
  ad:setHp(user, 0)
  if protected then
    ad:sayText("STRINGID_PKMNPROTECTEDITSELF", { def = t })
  else
    H.attackAnim(ctx)
    if (t.substituteHP or 0) > 0 then
      ad:sayText("STRINGID_BUTNOEFFECT")
    else
      Secondary.multiStatAnim(ad, t, { "attack", "spAtk" }, -2)
      Secondary.changeStat(ad, t, "attack", -2, { allowPtr = true, noAnim = true, noMsg = (t.stages.attack or 0) <= -6 })
      Secondary.changeStat(ad, t, "spAtk", -2, { allowPtr = true, noAnim = true, noMsg = (t.stages.spAtk or 0) <= -6 })
    end
  end
  if M then M.checkUserFaint = true; M:tryFaintUser() end
end

return Stats
