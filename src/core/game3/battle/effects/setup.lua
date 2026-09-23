-- FRLG setup effects (KR-sourced bodies; adapter-only; no KR require).

local H = require("src.core.game3.battle.effects._helpers")
local Types = require("src.core.game3.battle.types")
local Secondary = require("src.core.game3.battle.effects.secondary")

local Setup = {}

local function moved_last(ctx)
  local st = ctx.adapter and ctx.adapter._st
  -- pokefirered/src/battle_script_commands.c:9148
  if st and st.double then return ctx.user and ctx.user.expTurnOrder == 4 end
  return ctx.user and ctx.user.expTurnOrder == 2
end

-- pokefirered/data/battle_scripts_1.s:1440
function Setup.meanLook(ctx)
  local t = ctx.target
  if not t then return H.sayFail(ctx) end
  if not H.accuracy(ctx, "noacc") then return end
  if t.expTrapped or t.escapePrevention then return H.sayFail(ctx) end
  if (t.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  H.attackAnim(ctx)
  t.expTrapped = true
  t.escapePrevention = true
  t.expTrappedBy = ctx.user
  ctx.adapter:sayText("STRINGID_TARGETCANTESCAPENOW", { def = t })
end

-- pokefirered/src/battle_script_commands.c:6436
function Setup.leechSeed(ctx)
  local ad, t = ctx.adapter, ctx.target
  if (t.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  local M = H.move(ctx)
  local hit = true
  if M then hit = M:accuracyCheck("normal", false) end
  H.attackAnim(ctx)
  if not hit or t.expSeeded then
    ad:sayText("STRINGID_PKMNEVADEDATTACK", { def = t })
    return
  end
  if H.hasType(ctx, t, Types.ID.GRASS) then
    ad:sayText("STRINGID_ITDOESNTAFFECT", { def = t })
    return
  end
  t.expSeeded = true
  t.leechSeed = true
  t.expSeedSource = ctx.user
  ad:sayText("STRINGID_PKMNSEEDED", { def = t })
end

-- pokefirered/data/battle_scripts_1.s:1330
function Setup.destinyBond(ctx)
  ctx.user.expDestinyBond = true
  ctx.user.destinyBond = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNTRYINGTOTAKEFOE", { atk = ctx.user })
end

-- pokefirered/data/battle_scripts_1.s:1455
function Setup.nightmare(ctx)
  local t = ctx.target
  if (t.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  if t.expNightmare then return H.sayFail(ctx) end
  if not ctx.adapter:hasStatus(t, "SLP") then return H.sayFail(ctx) end
  H.attackAnim(ctx)
  t.expNightmare = true
  ctx.adapter:sayText("STRINGID_PKMNFELLINTONIGHTMARE", { def = t })
end

-- pokefirered/data/battle_scripts_1.s:884
function Setup.focusEnergy(ctx)
  if ctx.user.expFocusEnergy then return H.sayFail(ctx) end
  ctx.user.expFocusEnergy = true
  ctx.user.focusEnergy = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNGETTINGPUMPED", { atk = ctx.user })
end

-- pokefirered/data/battle_scripts_1.s:1551
function Setup.foresight(ctx)
  if not H.accuracy(ctx, "normal") then return end
  ctx.target.expIdentified = true
  ctx.target.foresight = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNIDENTIFIED", { atk = ctx.user, def = ctx.target })
end

-- pokefirered/src/battle_script_commands.c:7759
function Setup.lockOn(ctx)
  if (ctx.target.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  if not H.accuracy(ctx, "normal") then return end
  ctx.target.expLockedOn = 2
  ctx.target.expLockedOnBy = ctx.user.side
  ctx.target.expLockedOnById = ctx.user.id
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNTOOKAIM", { atk = ctx.user, def = ctx.target })
end

-- pokefirered/src/battle_script_commands.c:9144
function Setup.magicCoat(ctx)
  if moved_last(ctx) then return H.sayFail(ctx) end
  ctx.user.expMagicCoat = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNSHROUDEDITSELF", { atk = ctx.user, currentMove = H.moveNum(ctx.move or ctx.moveId) })
end

-- pokefirered/data/battle_scripts_1.s:2527
function Setup.grudge(ctx)
  if ctx.user.expGrudge then return H.sayFail(ctx) end
  ctx.user.expGrudge = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNWANTSGRUDGE", { atk = ctx.user })
end

-- pokefirered/src/battle_script_commands.c:9019
function Setup.imprison(ctx)
  local user = ctx.user
  if user.expImprison then return H.sayFail(ctx) end
  local st = ctx.adapter._st
  local foes = (st and st.double) and ctx.adapter:foesOf(user) or { ctx.adapter:foeOf(user) }
  local shared = false
  local um = user.mon and user.mon.moves or {}
  for _, foe in ipairs(foes) do
    local fm = foe and foe.mon and foe.mon.moves or {}
    for i = 1, 4 do
      local a = H.moveNum(um[i])
      if a and a ~= 0 then
        for j = 1, 4 do
          if H.moveNum(fm[j]) == a then shared = true end
        end
      end
    end
  end
  if not shared then return H.sayFail(ctx) end
  user.expImprison = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNSEALEDOPPONENTMOVE", { atk = user })
end

-- pokefirered/src/battle_script_commands.c:9160
function Setup.snatch(ctx)
  if moved_last(ctx) then return H.sayFail(ctx) end
  ctx.user.expSnatch = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNWAITSFORTARGET", { atk = ctx.user })
end

-- pokefirered/src/battle_script_commands.c:9316
function Setup.mudSport(ctx)
  if ctx.user.mudSport then return H.sayFail(ctx) end
  ctx.user.mudSport = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_ELECTRICITYWEAKENED")
end

function Setup.waterSport(ctx)
  if ctx.user.waterSport then return H.sayFail(ctx) end
  ctx.user.waterSport = true
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_FIREWEAKENED")
end

-- pokefirered/src/battle_script_commands.c:793
Setup.TERRAIN_TYPE = {
  [0] = Types.ID.GRASS, [1] = Types.ID.GRASS, [2] = Types.ID.GROUND, [3] = Types.ID.WATER,
  [4] = Types.ID.WATER, [5] = Types.ID.WATER, [6] = Types.ID.ROCK, [7] = Types.ID.ROCK,
  [8] = Types.ID.NORMAL, [9] = Types.ID.NORMAL,
}

-- pokefirered/src/battle_script_commands.c:9389
function Setup.camouflage(ctx)
  local Engine = require("src.core.game3.battle.engine")
  local t = Setup.TERRAIN_TYPE[Engine.terrainOf(ctx.adapter._st)] or Types.ID.NORMAL
  if H.hasType(ctx, ctx.user, t) then return H.sayFail(ctx) end
  ctx.user.type1 = t
  ctx.user.type2 = t
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNCHANGEDTYPE", { atk = ctx.user, buff1 = Types.name(t) })
end

-- pokefirered/src/battle_script_commands.c:8884
function Setup.rolePlay(ctx)
  if not H.accuracy(ctx, "lockon") then return end
  local foeAb = ctx.adapter:abilityOf(ctx.target)
  if not foeAb or foeAb == "WONDER_GUARD" then return H.sayFail(ctx) end
  ctx.user.expTracedAbility = foeAb
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNCOPIEDFOE", { atk = ctx.user, def = ctx.target, defAbility = H.abilityId(foeAb) })
end

-- pokefirered/src/battle_script_commands.c:8999
function Setup.skillSwap(ctx)
  if not H.accuracy(ctx, "lockon") then return end
  local a = ctx.adapter:abilityOf(ctx.user)
  local b = ctx.adapter:abilityOf(ctx.target)
  if (not a and not b) or a == "WONDER_GUARD" or b == "WONDER_GUARD" then return H.sayFail(ctx) end
  ctx.user.expTracedAbility = b
  ctx.target.expTracedAbility = a
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNSWAPPEDABILITIES", { atk = ctx.user })
end

-- pokefirered/src/battle_script_commands.c:8544
function Setup.futureSight(ctx)
  local ad = ctx.adapter
  local side = ad:foeSide(ctx.user)
  if not side then return H.sayFail(ctx) end
  side.tokens = side.tokens or {}
  local double = ad._st and ad._st.double
  for _, tok in ipairs(side.tokens) do
    if tok.id == "EXP_FUTURE_SIGHT" and (not double or tok.targetId == ctx.target.id) then
      return H.sayFail(ctx)
    end
  end
  local Damage = require("src.core.game3.battle.damage")
  local Rules = require("src.core.game3.battle.rules")
  local defSide = ad:ownSide(ctx.target)
  local dmg = Damage.base(ctx.user, ctx.target, ctx.move or { power = 80, type = 14 }, {
    adapter = ad,
    weatherKind = Rules.weather.effective(ad._st, ad),
    reflect = defSide and (defSide.expReflectTurns or 0) > 0,
    lightScreen = defSide and (defSide.expLightScreenTurns or 0) > 0,
    doubleScreens = double and ad._st and require("src.core.game3.battle.state").countPresentOnSide(ad._st, ctx.target.side) == 2,
  })
  -- pokefirered/src/battle_script_commands.c:8558
  if ctx.user.expHelpingHand then dmg = math.floor(dmg * 15 / 10) end
  side.tokens[#side.tokens + 1] = {
    id = "EXP_FUTURE_SIGHT",
    turns = 3,
    damage = dmg,
    moveId = ctx.moveId,
    attackerSide = ctx.user.side,
    attackerId = ctx.user.id,
    targetId = ctx.target.id,
  }
  H.attackAnim(ctx)
  local tok = side.tokens[#side.tokens]
  if H.moveNum(ctx.move or ctx.moveId) == 353 then
    tok.doomDesire = true
    ad:sayText("STRINGID_PKMNCHOSEXASDESTINY", { atk = ctx.user, currentMove = 353 })
  else
    ad:sayText("STRINGID_PKMNFORESAWATTACK", { atk = ctx.user })
  end
end

-- pokefirered/data/battle_scripts_1.s:1478
function Setup.curse(ctx)
  local ad, user = ctx.adapter, ctx.user
  if H.hasType(ctx, user, Types.ID.GHOST) then
    local t = ctx.target
    if t == user then t = ad:foeOf(user); ctx.target = t end
    if (t.substituteHP or 0) > 0 then return H.sayFail(ctx) end
    if not H.accuracy(ctx, "lockon") then return end
    if t.expCursed then return H.sayFail(ctx) end
    t.expCursed = true
    t.cursed = true
    local cost = math.floor(ad:maxHp(user) / 2)
    if cost == 0 then cost = 1 end
    H.attackAnim(ctx)
    ad:applyHpLoss(user, cost)
    ad:sayText("STRINGID_PKMNLAIDCURSE", { atk = user, def = t })
    local M = H.move(ctx)
    if M then M.checkUserFaint = true end
    return
  end
  local s = user.stages
  if (s.speed or 0) <= -6 and (s.attack or 0) >= 6 and (s.defense or 0) >= 6 then
    return H.sayFail(ctx)
  end
  H.attackAnim(ctx)
  Secondary.changeStat(ad, user, "speed", -1, { user = true, allowPtr = true, curse = true, noAnim = true, noMsg = (s.speed or 0) <= -6 })
  Secondary.changeStat(ad, user, "attack", 1, { user = true, allowPtr = true, noAnim = true, noMsg = (s.attack or 0) >= 6 })
  Secondary.changeStat(ad, user, "defense", 1, { user = true, allowPtr = true, noAnim = true, noMsg = (s.defense or 0) >= 6 })
end

-- pokefirered/data/battle_scripts_1.s:1690
function Setup.batonPass(ctx)
  local Special = require("src.core.game3.battle.effects.special")
  return Special.batonPass(ctx)
end

-- pokefirered/src/battle_script_commands.c:8779
function Setup.helpingHand(ctx)
  local ad, user = ctx.adapter, ctx.user
  local st = ad._st
  local State = require("src.core.game3.battle.state")
  local pid = State.PARTNER(State.idOf(user))
  local partner = State.battler(st, pid)
  if not (st and st.double) or not State.isPresent(st, pid) or not partner
      or user.expHelpingHand or partner.expHelpingHand then
    return H.sayFail(ctx)
  end
  partner.expHelpingHand = true
  ctx.target = partner
  local M = H.move(ctx)
  if M then
    M.target = partner
    M.tname = ad:displayName(partner)
  end
  H.attackAnim(ctx)
  ad:sayText("STRINGID_PKMNREADYTOHELP", { atk = user, def = partner })
end

function Setup.splash(ctx)
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_BUTNOTHINGHAPPENED")
end

-- pokefirered/data/battle_scripts_1.s:902
function Setup.confuse(ctx)
  local ad, t = ctx.adapter, ctx.target
  if ad:abilityOf(t) == "OWN_TEMPO" then
    return ad:sayText("STRINGID_PKMNPREVENTSCONFUSIONWITH", { def = t, defAbility = H.abilityId("OWN_TEMPO") })
  end
  if (t.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  if (t.confusionTurns or 0) > 0 then
    return ad:sayText("STRINGID_PKMNALREADYCONFUSED", { def = t })
  end
  if not H.accuracy(ctx, "normal") then return end
  local Status = require("src.core.game3.battle.effects.status")
  if Status.safeguarded(ctx) then return end
  H.attackAnim(ctx)
  local M = H.move(ctx) or { adapter = ad, user = ctx.user, target = t, st = ad._st }
  Secondary.set(M, "CONFUSION", true, false, false)
end

-- pokefirered/src/battle_script_commands.c:6826
function Setup.haze(ctx)
  H.attackAnim(ctx)
  for _, b in ipairs(ctx.adapter:activeBattlers()) do
    if b and b.stages then
      for k in pairs(b.stages) do b.stages[k] = 0 end
    end
  end
  ctx.adapter:sayText("STRINGID_STATCHANGESGONE")
end

-- pokefirered/src/battle_script_commands.c:7442
function Setup.substitute(ctx)
  local ad, user = ctx.adapter, ctx.user
  if (user.substituteHP or 0) > 0 then
    return ad:sayText("STRINGID_PKMNHASSUBSTITUTE", { atk = user })
  end
  local maxHp = ad:maxHp(user)
  local cost = math.floor(maxHp / 4)
  if cost == 0 then cost = 1 end
  if ad:hp(user) <= cost then
    local M = H.move(ctx)
    if M then M.failed = true end
    return ad:sayText("STRINGID_TOOWEAKFORSUBSTITUTE")
  end
  user.substituteHP = cost
  user.expTrapTurns = nil
  user.wrapped = nil
  H.attackAnim(ctx)
  ad:applyHpLoss(user, cost)
  ad:sayText("STRINGID_PKMNMADESUBSTITUTE", { atk = user })
end

-- pokefirered/data/battle_scripts_1.s:2566
function Setup.teeterDance(ctx)
  local ad, t = ctx.adapter, ctx.target
  if ad:abilityOf(t) == "OWN_TEMPO" then
    return ad:sayText("STRINGID_PKMNPREVENTSCONFUSIONWITH", { def = t, defAbility = H.abilityId("OWN_TEMPO") })
  end
  if (t.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  if (t.confusionTurns or 0) > 0 then
    return ad:sayText("STRINGID_PKMNALREADYCONFUSED", { def = t })
  end
  if not H.accuracy(ctx, "normal") then return end
  local side = ad:ownSide(t)
  if side and (side.expSafeguardTurns or 0) > 0 then
    return ad:sayText("STRINGID_PKMNUSEDSAFEGUARD", { def = t })
  end
  H.attackAnim(ctx)
  local M = H.move(ctx) or { adapter = ad, user = ctx.user, target = t, st = ad._st }
  Secondary.set(M, "CONFUSION", true, false, false)
end

return Setup
