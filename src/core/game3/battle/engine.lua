-- Owned turn resolver: moves, effects, residuals, commands.

local Damage = require("src.core.game3.battle.damage")
local Moves = require("src.core.game3.battle.moves")
local State = require("src.core.game3.battle.state")
local Effects = require("src.core.game3.battle.effects")
local EffectIds = require("src.core.game3.battle.effect_ids")
local Residuals = require("src.core.game3.battle.residuals")
local rollWarned = false
local badgeWarned = false
local ResidualHandlers = require("src.core.game3.battle.residual_handlers")
local Commands = require("src.core.game3.battle.commands")
local Types = require("src.core.game3.battle.types")
local Rules = require("src.core.game3.battle.rules")
local Secondary = require("src.core.game3.battle.effects.secondary")
local HeldItems = require("src.core.game3.battle.held_items")
local Abilities = require("src.core.game3.battle.abilities")
local Oak = require("src.core.game3.battle.oak_advice")
local ModRuntime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")

local Engine = {}

ResidualHandlers.registerAll()

local E = EffectIds

-- pokefirered/include/constants/pokemon.h:238
local FLAG_PROTECT_AFFECTED = 2
local FLAG_MAGIC_COAT_AFFECTED = 4
local FLAG_SNATCH_AFFECTED = 8
local FLAG_MIRROR_MOVE_AFFECTED = 16

local MOVE_TARGET_SELECTED = 0
local MOVE_TARGET_DEPENDS = 1
local MOVE_TARGET_USER_OR_SELECTED = 2
local MOVE_TARGET_RANDOM = 4
local MOVE_TARGET_BOTH = 8
local MOVE_TARGET_USER = 16
local MOVE_TARGET_FOES_AND_ALLY = 32
local MOVE_TARGET_OPPONENTS_FIELD = 64
Engine.MOVE_TARGET = {
  SELECTED = MOVE_TARGET_SELECTED, DEPENDS = MOVE_TARGET_DEPENDS,
  USER_OR_SELECTED = MOVE_TARGET_USER_OR_SELECTED, RANDOM = MOVE_TARGET_RANDOM,
  BOTH = MOVE_TARGET_BOTH, USER = MOVE_TARGET_USER, FOES_AND_ALLY = MOVE_TARGET_FOES_AND_ALLY,
  OPPONENTS_FIELD = MOVE_TARGET_OPPONENTS_FIELD,
}

local MOVE_SNORE, MOVE_SLEEP_TALK, MOVE_STRUGGLE, MOVE_CURSE = 173, 214, 165, 174
local MOVE_SKY_ATTACK, MOVE_BOUNCE, MOVE_FLY, MOVE_DIG, MOVE_DIVE = 143, 340, 19, 91, 291

-- pokefirered/src/battle_script_commands.c:707
local FORBIDDEN_TO_COPY = {
  118, 165, 166, 102, -1, 68, 243, 182, 197, 203, 194, 214, 168, 266, 289, 270, 343, 271, 264,
}

local function forbidden(move, list_end_at_mimic)
  for _, m in ipairs(FORBIDDEN_TO_COPY) do
    if m == -1 then
      if list_end_at_mimic then return false end
    elseif m == move then
      return true
    end
  end
  return false
end
Engine.isForbiddenToCopy = forbidden

-- pokefirered/src/battle_script_commands.c:741
Engine.NATURE_POWER_MOVES = {
  [0] = 78, [1] = 75, [2] = 89, [3] = 56, [4] = 57, [5] = 61, [6] = 157, [7] = 247, [8] = 129, [9] = 129,
}

local function move_num(moveId, move)
  local n = tonumber(move and move.numId) or tonumber(moveId)
  if n then return n end
  if type(moveId) == "string" then return Moves.numForName(Moves.normalizeId(moveId)) end
  return nil
end
Engine.moveNum = move_num

local function has_flag(move, flag)
  local f = move and move.flags
  if f == nil or (move.numId == nil and (tonumber(f) or 0) == 0) then
    if flag == FLAG_PROTECT_AFFECTED then
      return (tonumber(move and move.target) or 0) ~= MOVE_TARGET_USER
    end
    return false
  end
  f = tonumber(f) or 0
  return math.floor(f / flag) % 2 == 1
end
Engine.hasFlag = has_flag

local function roll(adapter, lo, hi)
  if adapter and adapter.rng then
    local ok, v = pcall(adapter:rng(), lo, hi)
    if ok and type(v) == "number" then return v end
    if not rollWarned then
      rollWarned = true
      print("[game3/engine] adapter rng failed: " .. tostring(v))
    end
  end
  local okR, Rng = pcall(require, "src.core.game3.rng")
  if okR and Rng and Rng.compat then
    return Rng.compat(lo, hi)
  end
  return math.random(lo, hi)
end
Engine.roll = roll

local function terrain_of(st)
  if st and st.terrain ~= nil then return tonumber(st.terrain) or 8 end
  local Bg = package.loaded["src.core.game3.battle.bg"]
  if Bg and Bg.terrainId then return tonumber(Bg.terrainId()) or 8 end
  return 8
end
Engine.terrainOf = terrain_of

-- pokefirered/src/battle_util.c:203
function Engine.cancelMultiTurnMoves(b)
  if not b then return end
  b.expLockedMove = nil
  b.expLockedSlot = nil
  b.expRampageTurns = nil
  b.expUproarTurns = nil
  b.uproar = nil
  b.bideTurns = nil
  b.twoTurnMove = nil
  b.twoTurnTarget = nil
  b.semiInvulnerable = nil
  b.onAir, b.underground, b.underwater = nil, nil, nil
  b.expRolloutTimer = nil
  b.expFuryCutter = nil
end

-- pokefirered/src/battle_main.c:2373
function Engine.refreshLinks(st)
  if not st then return end
  local onField = {}
  for id = 0, 3 do
    local b = State.battler(st, id)
    if b then onField[b] = true end
  end
  for id = 0, 3 do
    local b = State.battler(st, id)
    if b then
      local foe = (not st.double) and State.battler(st, State.OPPOSITE(id)) or nil
      local function gone(src)
        if st.double then return not onField[src] end
        return src ~= foe
      end
      if b.expInfatuatedWith and gone(b.expInfatuatedWith) then
        b.expInfatuated, b.expInfatuatedWith = nil, nil
      end
      if b.expTrapSource and gone(b.expTrapSource) then
        b.expTrapTurns, b.expTrapSource, b.expTrapMove, b.wrapped = nil, nil, nil, nil
      end
      if b.expTrappedBy and gone(b.expTrappedBy) then
        b.expTrapped, b.expTrappedBy, b.escapePrevention = nil, nil, nil
      end
    end
  end
end

-- pokefirered/src/pokemon.c:2381
function Engine.hasBadge(st, n)
  if not st or st.link then return false end
  local b = st.badges
  if type(b) == "table" then return b[n] == true end
  if type(b) == "number" then return math.floor(b / 2 ^ (n - 1)) % 2 == 1 end
  local Space = package.loaded["src.core.game3.scripting.space"]
  local Flags = package.loaded["src.core.game3.scripting.flags"]
  if Space and Space.store and Flags and Flags.hasBadge then
    local ok, v = pcall(Flags.hasBadge, Space.store, n)
    if not ok then
      if not badgeWarned then
        badgeWarned = true
        print("[game3/battle] hasBadge failed: " .. tostring(v))
      end
      return false
    end
    return v == true
  end
  return false
end

-- pokefirered/src/battle_controllers.c:163 InitLinkBtlControllers
local function link_seat_swap(st)
  if not (st and st.link) then return false end
  return st.linkMaster == false
end

Engine.linkSeatSwap = link_seat_swap

-- pokefirered/src/battle_main.c:3399
local function speed_of(battler, st, adapter)
  local mon = battler and battler.mon
  local spe = tonumber(mon and (mon.speed or mon.spe)) or 50
  if battler and battler.expTransform and battler.expTransform.speed then
    spe = battler.expTransform.speed
  end
  local weather = adapter and Rules.weather.effective(st, adapter) or Rules.weather.kind(st and st.weather)
  local ab = adapter and adapter:abilityOf(battler)
  local mul = 1
  if (ab == "SWIFT_SWIM" and weather == "RAIN") or (ab == "CHLOROPHYLL" and weather == "SUN") then
    mul = 2
  end
  local stage = battler and battler.stages and battler.stages.speed or 0
  spe = Damage.applyStage(spe * mul, stage)
  if battler and battler.side == "player" and Engine.hasBadge(st, 3) then
    spe = math.floor(spe * 110 / 100)
  end
  local he, param = HeldItems.of(battler)
  if he == HeldItems.HOLD.MACHO_BRACE then spe = math.floor(spe / 2) end
  local st1 = battler and (battler.status or (battler.mon and battler.mon.status))
  if st1 == "PAR" then spe = math.floor(spe / 4) end
  if he == HeldItems.HOLD.QUICK_CLAW and st and (tonumber(st.randomTurnNumber) or 0xFFFF)
      < math.floor(0xFFFF * param / 100) then
    spe = 0xFFFFFFFF
  end
  return spe
end
Engine.speedOf = speed_of

local function clear_turn_flags(battler)
  if not battler then return end
  -- pokefirered/src/battle_main.c:3623
  battler.expProtected = nil
  battler.expEnduring = nil
  battler.expMagicCoat = nil
  battler.expSnatch = nil
  battler.expHelpingHand = nil
  battler.flinched = nil
  battler.damageTakenThisTurn = 0
  battler.lastPhysicalDamageTaken = nil
  battler.lastSpecialDamageTaken = nil
  battler.expHurtBy = nil
  battler.expHurtById = nil
  battler.lastPhysicalById = nil
  battler.lastSpecialById = nil
  battler.expLightningRodRedirected = nil
  battler.expMovedThisTurn = nil
  battler.expTurnOrder = nil
  battler.expUnableToMove = nil
  battler._statLoweredMsg = nil
  if (battler.isFirstTurn or 0) > 0 then battler.isFirstTurn = battler.isFirstTurn - 1 end
  if battler.expRechargeTurns then
    battler.expRechargeTurns = battler.expRechargeTurns - 1
    if battler.expRechargeTurns <= 0 then
      battler.expRechargeTurns = nil
      battler.expMustRecharge = nil
      battler.recharge = nil
    end
  end
end
Engine.clearTurnFlags = clear_turn_flags

local function effectiveness_line(flags, eff)
  if flags then
    if flags.super then return Strings("It's super effective!") end
    if flags.notVery then return Strings("It's not very effective…") end
    return nil
  end
  if eff >= 2 then return Strings("It's super effective!") end
  if eff > 0 and eff < 1 then return Strings("It's not very effective…") end
  return nil
end
Engine.effectivenessLine = effectiveness_line

local Ctx = {}
Ctx.__index = Ctx

function Ctx:say(text) self.adapter:say(text) end

-- pokefirered/src/battle_script_commands.c:1108
function Ctx:attackString()
  if self.printedUsed then return end
  self.printedUsed = true
  self:say(Strings("%s used\n%s!", self.uname, self.moveName))
  if ModRuntime.wants("battle.move_used") then
    local G3 = require("src.mods.Gen3Compat")
    local view = G3.moveView(self.move)
    ModRuntime.emit("battle.move_used", {
      battle = self.st, user = self.user, target = self.target, move = view,
      isCalled = self.opts.called and true or false,
      moveId = view and view.id, moveNum = self.mnum, side = self.user and self.user.side,
      userId = self.user and State.idOf(self.user),
      targetId = self.target and State.idOf(self.target),
    })
  end
end

-- pokefirered/src/battle_script_commands.c:1122
function Ctx:ppReduce()
  if self.ppDone then return end
  self.ppDone = true
  if self.noPP or not self.slot then return end
  local mon = self.user.mon
  if not mon then return end
  mon.pp = mon.pp or {}
  local pp = tonumber(mon.pp[self.slot])
  if not pp then return end
  local cost = 1
  local target = self.target
  local ttype = tonumber(self.move.target) or 0
  if self.st and self.st.double and (ttype == MOVE_TARGET_FOES_AND_ALLY or ttype == MOVE_TARGET_BOTH
      or ttype == MOVE_TARGET_OPPONENTS_FIELD) then
    for _, b in ipairs(State.present(self.st)) do
      if b ~= self.user and self.adapter:abilityOf(b) == "PRESSURE"
          and (ttype == MOVE_TARGET_FOES_AND_ALLY or b.side ~= self.user.side) then
        cost = cost + 1
      end
    end
  elseif target and target ~= self.user and ttype ~= MOVE_TARGET_USER
      and self.adapter:abilityOf(target) == "PRESSURE" then
    cost = 2
  end
  if pp > cost then mon.pp[self.slot] = pp - cost else mon.pp[self.slot] = 0 end
end

-- pokefirered/src/battle_controller_player.c:2330
function Ctx:attackAnimation(turn, multihitLeft)
  local ad, user = self.adapter, self.user
  if self.st and self.st.double and (self.animTargetsHit or 0) > 0 then
    local ttype = tonumber(self.move.target) or 0
    -- pokefirered/src/battle_script_commands.c:1677
    if ttype == MOVE_TARGET_BOTH or ttype == MOVE_TARGET_FOES_AND_ALLY or ttype == MOVE_TARGET_DEPENDS then
      return nil
    end
  end
  local behindSub = user and (user.substituteHP or 0) > 0
  if behindSub and not self._subLowered then
    self._subLowered = true
    ad:playAnim("special", "SUBSTITUTE_TO_MON", user, user)
  end
  local ev = ad:pushEvent({
    kind = "move",
    moveId = self.moveId,
    attacker = user and user.side,
    target = self.target and self.target.side,
    attackerId = user and State.idOf(user),
    targetId = self.target and State.idOf(self.target),
    turn = turn or self.animTurn or 0,
    damage = self._animDmg,
    power = self._animPower,
  })
  self.animTurn = (self.animTurn or 0) + 1
  self.animTargetsHit = (self.animTargetsHit or 0) + 1
  if behindSub and (multihitLeft or 0) < 2 then
    self._subLowered = false
    ad:playAnim("special", "MON_TO_SUBSTITUTE", user, user)
  end
  return ev
end

function Ctx:isProtected()
  local t = self.target
  if not t or t == self.user or not t.expProtected then return false end
  if not has_flag(self.move, FLAG_PROTECT_AFFECTED) then return false end
  if self.mnum == MOVE_CURSE and not (self.adapter:hasType(self.user, Types.ID.GHOST)) then return false end
  return true
end

function Ctx:lockOnActive()
  local t = self.target
  if not (t and (t.expLockedOn or 0) ~= 0 and t.expLockedOn ~= false) then return false end
  if self.st and self.st.double and t.expLockedOnById ~= nil then
    return t.expLockedOnById == State.idOf(self.user)
  end
  return t.expLockedOnBy == nil or t.expLockedOnBy == self.user.side
end

-- pokefirered/src/battle_script_commands.c:1003
function Ctx:accuracyCheck(mode, printFail)
  local ad, user, target = self.adapter, self.user, self.target
  local failMsg = function(reason)
    self.missReason = reason
    if not printFail then return end
    if reason == "protected" then
      self:say(Strings("%s\nprotected itself!", ad:displayName(target)))
    elseif reason == "fail" then
      self.failed = true
      ad:sayFail()
    else
      self:say(Strings("%s's\nattack missed!", ad:displayName(user)))
    end
  end
  if mode == "noacc" or mode == "lockon" then
    if mode == "lockon" and self:lockOnActive() then return true end
    if target and target.semiInvulnerable and target ~= user then
      failMsg("fail")
      return false
    end
    if self:isProtected() then
      failMsg("protected")
      return false
    end
    return true
  end
  -- pokefirered/src/battle_script_commands.c:896
  if self:isProtected() then
    failMsg("protected")
    return false
  end
  -- pokefirered/src/battle_script_commands.c:1007
  if Oak.active(self.st) and user and user.side == "player" then
    local power = tonumber(self.move and self.move.power) or 0
    local mask = (power > 0) and Oak.FLAG_INFLICT_DMG or Oak.FLAG_STAT_CHG
    if not Oak.testFlag(self.st, mask) then return not self:absorbed() end
  end
  if self:lockOnActive() then return not self:absorbed() end
  local semi = target and target ~= user and target.semiInvulnerable
  if semi == "ON_AIR" and not self.ignoreOnAir then failMsg("miss"); return false end
  if semi == "UNDERGROUND" and not self.ignoreUnderground then failMsg("miss"); return false end
  if semi == "UNDERWATER" and not self.ignoreUnderwater then failMsg("miss"); return false end
  local weather = Rules.weather.effective(self.st, ad)
  local eff = self.effect
  if (weather == "RAIN" and eff == E.THUNDER) or eff == E.ALWAYS_HIT or eff == E.VITAL_THROW then
    return not self:absorbed()
  end
  local accStage = user.stages and user.stages.accuracy or 0
  local evaStage = target and target.stages and target.stages.evasion or 0
  local buff
  if target and target.expIdentified then
    buff = accStage
  else
    buff = accStage - evaStage
  end
  if buff < -6 then buff = -6 elseif buff > 6 then buff = 6 end
  local moveAcc = tonumber(self.accOverride or self.move.accuracy) or 100
  if weather == "SUN" and eff == E.THUNDER then moveAcc = 50 end
  local ratio = Rules.ACCURACY_STAGE[buff]
  local calc = math.floor(ratio[1] * moveAcc / ratio[2])
  if ad:abilityOf(user) == "COMPOUND_EYES" then calc = math.floor(calc * 130 / 100) end
  if weather == "SAND" and ad:abilityOf(target) == "SAND_VEIL" then calc = math.floor(calc * 80 / 100) end
  if ad:abilityOf(user) == "HUSTLE" and Types.isPhysical(self.moveType or self.move.type) then
    calc = math.floor(calc * 80 / 100)
  end
  local tHe, tParam = HeldItems.of(target)
  if tHe == HeldItems.HOLD.EVASION_UP then calc = math.floor(calc * (100 - tParam) / 100) end
  local hit
  if ModRuntime.wantsHook("battle.accuracy") then
    local G3 = require("src.mods.Gen3Compat")
    local view = G3.moveView(self.move)
    hit = ModRuntime.call("battle.accuracy", function(c)
      return roll(ad, 1, 100) <= c.accuracy
    end, { battle = self.st, move = view, moveId = view and view.id, moveNum = self.mnum,
           user = user, target = target, accuracy = calc, rng = ad:rng() })
  else
    hit = roll(ad, 1, 100) <= calc
  end
  if not hit then
    failMsg("miss")
    return false
  end
  return not self:absorbed()
end

-- pokefirered/src/battle_script_commands.c:912
function Ctx:absorbed()
  if Abilities.absorb(self) then
    self.missReason = "absorbed"
    return true
  end
  return false
end

function Ctx:faintMessage(battler)
  local ad = self.adapter
  if not battler or battler._faintAnnounced then return false end
  if not ad:isFainted(battler) then return false end
  battler._faintAnnounced = true
  ad:pushEvent({ kind = "faint", side = battler.side, battler = State.idOf(battler) })
  self:say(Strings("%s fainted!", ad:displayName(battler)))
  self.anim.fainted = true
  self.anim.faints[#self.anim.faints + 1] = { side = battler.side or "enemy", battler = State.idOf(battler) }
  ad:emitFaint(battler)
  return true
end

-- pokefirered/src/battle_script_commands.c:2831
function Ctx:tryFaintTarget()
  local ad, user, target = self.adapter, self.user, self.target
  if not target or target == user then return end
  if not ad:isFainted(target) or target._faintAnnounced then return end
  self:faintMessage(target)
  if target.expDestinyBond and user.side ~= target.side and not ad:isFainted(user) then
    self:say(Strings("%s took\n%s with it!", ad:displayName(target), ad:displayName(user)))
    ad:applyHpLoss(user, ad:hp(user))
    self:faintMessage(user)
  end
  if target.expGrudge and self.slot and user.mon and user.mon.pp and not ad:isFainted(user) then
    user.mon.pp[self.slot] = 0
    self:say(Strings("%s's %s lost\nall its PP due to the GRUDGE!", ad:displayName(user), self.moveName))
  end
end

function Ctx:tryFaintUser()
  if self.adapter:isFainted(self.user) then self:faintMessage(self.user) end
end

local function new_ctx(user, target, moveId, slot, adapter, st, out, anim, opts)
  local move = Moves.get(moveId)
  local M = setmetatable({
    isMoveContext = true,
    adapter = adapter,
    st = st,
    user = user,
    target = target,
    moveId = moveId,
    move = move,
    mnum = move_num(moveId, move),
    effect = tonumber(move.effect) or 0,
    slot = slot,
    out = out,
    anim = anim,
    opts = opts or {},
    moveName = Moves.displayName(moveId),
    uname = adapter:displayName(user),
    tname = adapter:displayName(target),
    animTurn = 0,
  }, Ctx)
  return M
end
Engine.newContext = new_ctx

-- pokefirered/data/battle_scripts_1.s:3741
function Engine.selfHit(M, dmg)
  local ad, user = M.adapter, M.user
  local r = roll(ad, 85, 100)
  dmg = math.floor(dmg * r / 100)
  if dmg == 0 then dmg = 1 end
  local banded = HeldItems.rollFocusBand(ad, user)
  local hung = nil
  if (user.substituteHP or 0) <= 0 and (user.expEnduring or banded) and dmg >= ad:hp(user) then
    dmg = ad:hp(user) - 1
    hung = user.expEnduring and "endured" or "band"
  end
  user.expFocusBanded = nil
  M:say(Strings("It hurt itself in its\nconfusion!"))
  ad:applyHpLoss(user, dmg)
  if hung == "endured" then
    M:say(Strings("%s ENDURED\nthe hit!", M.uname))
  elseif hung == "band" then
    HeldItems.focusBandMessage(ad, user)
  end
  M:tryFaintUser()
end

-- pokefirered/src/battle_util.c:1253
local function canceller(M)
  local ad, user = M.adapter, M.user
  local uname = M.uname
  user.expDestinyBond = nil
  user.destinyBond = nil
  user.expGrudge = nil

  local st = ad:status(user)
  if st == "SLP" then
    local up = ad:uproarActive()
    if up and ad:abilityOf(user) ~= "SOUNDPROOF" then
      ad:clearStatus(user)
      user.expNightmare = nil
      M:say(Strings("%s woke up\nin the UPROAR!", uname))
    else
      local toSub = (ad:abilityOf(user) == "EARLY_BIRD") and 2 or 1
      local turns = tonumber(user.sleepTurns) or tonumber(user.mon and (user.mon.sleepTurns or user.mon.sleep))
      if not turns or turns <= 0 then turns = ad:rollSleepTurns() end
      if turns < toSub then turns = 0 else turns = turns - toSub end
      user.sleepTurns = turns
      if turns > 0 then
        if M.mnum ~= MOVE_SNORE and M.mnum ~= MOVE_SLEEP_TALK then
          M:say(Strings("%s is fast\nasleep.", uname))
          ad:statusAnim(user, "SLP")
          return false
        end
      else
        ad:clearStatus(user)
        user.expNightmare = nil
        M:say(Strings("%s woke up!", uname))
      end
    end
  end

  if ad:status(user) == "FRZ" then
    if roll(ad, 0, 4) ~= 0 then
      if M.effect ~= E.THAW_HIT then
        M:say(Strings("%s is\nfrozen solid!", uname))
        ad:statusAnim(user, "FRZ")
        return false
      end
    else
      ad:clearStatus(user)
      M:say(Strings("%s was\ndefrosted!", uname))
    end
  end

  if Abilities.truantLoafs(ad, user) then
    -- pokefirered/src/battle_util.c:1337
    Engine.cancelMultiTurnMoves(user)
    M:say(Strings("%s is\nloafing around!", uname))
    user.expUnableToMove = true
    return false
  end

  if user.expMustRecharge then
    user.expMustRecharge = nil
    user.expRechargeTurns = nil
    user.recharge = nil
    Engine.cancelMultiTurnMoves(user)
    M:say(Strings("%s must\nrecharge!", uname))
    return false
  end

  if user.flinched then
    user.flinched = nil
    Engine.cancelMultiTurnMoves(user)
    M:say(Strings("%s flinched!", uname))
    user.expUnableToMove = true
    return false
  end

  if user.expDisabledMove and M.mnum == user.expDisabledMove then
    Engine.cancelMultiTurnMoves(user)
    M:say(Strings("%s's %s\nis disabled!", uname, M.moveName))
    user.expUnableToMove = true
    return false
  end

  if (user.expTauntedTurns or 0) > 0 and (tonumber(M.move.power) or 0) == 0 then
    Engine.cancelMultiTurnMoves(user)
    M:say(Strings("%s can't use\n%s after the TAUNT!", uname, M.moveName))
    user.expUnableToMove = true
    return false
  end

  if M.mnum and Engine.isImprisoned(ad, user, M.mnum) then
    Engine.cancelMultiTurnMoves(user)
    M:say(Strings("%s can't use the\nsealed %s!", uname, M.moveName))
    user.expUnableToMove = true
    return false
  end

  if (user.confusionTurns or 0) > 0 then
    user.confusionTurns = user.confusionTurns - 1
    if user.confusionTurns > 0 then
      M:say(Strings("%s is\nconfused!", uname))
      ad:playAnim("status", "CONFUSION", user, user)
      if roll(ad, 0, 1) == 0 then
        Engine.cancelMultiTurnMoves(user)
        -- pokefirered/src/battle_util.c:1424
        local dmg = Damage.base(user, user, { power = 40, type = 0, effect = 0 }, {
          power = 40, moveType = 0, adapter = ad,
        })
        Engine.selfHit(M, dmg)
        user.expUnableToMove = true
        return false
      end
    else
      user.confusionTurns = nil
      M:say(Strings("%s snapped\nout of confusion!", uname))
    end
  end

  if ad:status(user) == "PAR" and roll(ad, 0, 3) == 0 then
    M:say(Strings("%s is paralyzed!\nIt can't move!", uname))
    ad:statusAnim(user, "PAR")
    user.expUnableToMove = true
    return false
  end

  -- pokefirered/src/battle_util.c:1451
  if M.st and M.st.ghostBattle and not M.st.ghostUnveiled then
    if user.side == "player" then
      -- pokefirered/data/battle_scripts_1.s:3809
      M:say(Strings("%s is too scared to move!", uname))
      ad:playAnim("general", "MON_SCARED", user, ad:foeOf(user))
    else
      -- pokefirered/data/battle_scripts_1.s:3815
      ad:pushEvent({ kind = "msg", text = Strings("GHOST: Get out…… Get out……"), wait = 0 })
      ad._say(Strings("GHOST: Get out…… Get out……"))
      ad:playAnim("general", "GHOST_GET_OUT", user, ad:foeOf(user))
    end
    return "ghost"
  end

  if user.expInfatuated then
    local lover = (M.st and M.st.double and user.expInfatuatedWith) or ad:foeOf(user)
    M:say(Strings("%s is in love\nwith %s!", uname, ad:displayName(lover)))
    ad:playAnim("status", "INFATUATION", user, user)
    if roll(ad, 0, 1) == 0 then
      Engine.cancelMultiTurnMoves(user)
      M:say(Strings("%s is\nimmobilized by love!", uname))
      user.expUnableToMove = true
      return false
    end
  end

  if (user.bideTurns or 0) > 0 then
    user.bideTurns = user.bideTurns - 1
    if user.bideTurns > 0 then
      M:say(Strings("%s is storing\nenergy!", uname))
      return false
    end
    return "bide"
  end

  if ad:status(user) == "FRZ" and M.effect == E.THAW_HIT then
    ad:clearStatus(user)
    M:say(Strings("%s was\ndefrosted by %s!", uname, M.moveName))
  end
  return true
end
Engine.canceller = canceller

-- pokefirered/data/battle_scripts_1.s:3251
local function bide_attack(M)
  local ad, user = M.adapter, M.user
  local dmgStored = user.expBideDamage or 0
  local src = user.expBideTarget
  user.expBideDamage = nil
  user.expBideTarget = nil
  user.bideTurns = nil
  user.expLockedMove = nil
  user.expLockedSlot = nil
  M:say(Strings("%s unleashed\nenergy!", M.uname))
  if dmgStored <= 0 then
    M.failed = true
    ad:sayFail()
    return
  end
  if src and src.side and M.st and not M.st.double and M.st[src.side] then M.target = M.st[src.side] end
  if src and M.st and M.st.double then
    local sid = State.idOf(src)
    -- pokefirered/src/battle_util.c:1500
    if State.isPresent(M.st, sid) then
      M.target = State.battler(M.st, sid)
    else
      M.target = State.battler(M.st, Engine.getMoveTarget(M.st, ad, user, M.moveId, MOVE_TARGET_SELECTED + 1))
    end
    M.tname = ad:displayName(M.target)
  end
  local target = M.target
  if not M:accuracyCheck("normal", true) then return end
  local _, flags = Types.typeCalc(M.move.type, target.type1, target.type2, nil, target.expIdentified)
  if flags.immune then
    M:say(Strings("It doesn't affect\n%s…", ad:displayName(target)))
    return
  end
  local Hit = require("src.core.game3.battle.effects.hit")
  Hit.applySetDamage(M, dmgStored * 2)
  M:tryFaintTarget()
end

local function run_called(M, calledId, opts)
  opts = opts or {}
  local sub = {}
  for k, v in pairs(M.opts or {}) do sub[k] = v end
  sub.called = true
  sub.anim = M.anim
  sub.noAttackString = nil
  sub.calledBy = M.moveId
  M.anim.calledBy = M.anim.calledBy or M.moveId
  local target = M.target
  local cmove = Moves.get(calledId)
  if M.st and M.st.double then
    target = State.battler(M.st, Engine.getMoveTarget(M.st, M.adapter, M.user, calledId))
  elseif tonumber(cmove.target) == MOVE_TARGET_USER then target = M.user else target = M.adapter:foeOf(M.user) end
  return Engine.resolveMove(M.user, target, calledId, opts.slot, M.adapter, M.st, M.out, sub)
end

-- pokefirered/src/battle_script_commands.c:7519
local function pick_metronome(M)
  for _ = 1, 64 do
    local m = roll(M.adapter, 1, 511)
    if m < 355 and not forbidden(m, false) then return m end
  end
  local list = {}
  for m = 1, 354 do if not forbidden(m, false) then list[#list + 1] = m end end
  return list[roll(M.adapter, 1, #list)]
end

local function invalid_sleep_talk(move)
  -- pokefirered/src/battle_script_commands.c:7834
  return move == nil or move == 0 or move == MOVE_SLEEP_TALK or move == 274 or move == 119 or move == 118
end

local function is_two_turn(move)
  local m = Moves.get(move)
  local e = tonumber(m and m.effect)
  return e == E.SKULL_BASH or e == E.RAZOR_WIND or e == E.SKY_ATTACK or e == E.SOLAR_BEAM
    or e == E.SEMI_INVULNERABLE or e == E.BIDE
end
Engine.isTwoTurnMove = is_two_turn

local function call_moves(M)
  local ad, user, eff = M.adapter, M.user, M.effect
  if eff == E.METRONOME then
    M:attackString()
    M:ppReduce()
    M:attackAnimation()
    return run_called(M, pick_metronome(M))
  elseif eff == E.SLEEP_TALK then
    -- pokefirered/data/battle_scripts_1.s:1307
    if ad:status(user) ~= "SLP" then
      M:attackString()
      M:ppReduce()
      M.failed = true
      ad:sayFail()
      return
    end
    M:say(Strings("%s is fast\nasleep.", M.uname))
    ad:statusAnim(user, "SLP")
    M:attackString()
    M:ppReduce()
    local mon = user.mon or {}
    local valid = {}
    for i = 1, 4 do
      local mv = move_num(mon.moves and mon.moves[i])
      local pp = mon.pp and mon.pp[i]
      if mv and not invalid_sleep_talk(mv) and mv ~= 264 and mv ~= 253 and not is_two_turn(mv)
          and not (user.expDisabledMove and mv == user.expDisabledMove)
          and not (user.expEncoreMove and move_num(user.expEncoreMove) ~= mv and (user.expEncoreTurns or 0) > 0) then
        valid[#valid + 1] = { move = mv, slot = i, pp = pp }
      end
    end
    if #valid == 0 then
      M.failed = true
      ad:sayFail()
      return
    end
    local pick = valid[roll(ad, 1, #valid)]
    M:attackAnimation()
    return run_called(M, pick.move)
  elseif eff == E.MIRROR_MOVE then
    -- pokefirered/src/battle_script_commands.c:6350
    M:attackString()
    local mv = user.expLastTakenMove
    if mv and mv ~= 0 then
      M:ppReduce()
      return run_called(M, mv)
    end
    M:ppReduce()
    M.failed = true
    M:say(Strings("The MIRROR MOVE failed!"))
    return
  elseif eff == E.ASSIST then
    -- pokefirered/src/battle_script_commands.c:9091
    M:attackString()
    local list = {}
    for i, mon in ipairs(ad:partyMons(user)) do
      if i ~= user.partyIndex and mon and (mon.species or 0) ~= 0 and not mon.isEgg then
        for j = 1, 4 do
          local mv = move_num(mon.moves and mon.moves[j])
          if mv and mv ~= 0 and not invalid_sleep_talk(mv) and not forbidden(mv, false) then
            list[#list + 1] = mv
          end
        end
      end
    end
    M:ppReduce()
    if #list == 0 then
      M.failed = true
      ad:sayFail()
      return
    end
    M:attackAnimation()
    return run_called(M, list[roll(ad, 1, #list)])
  elseif eff == E.NATURE_POWER then
    -- pokefirered/src/battle_script_commands.c:8718
    M:attackString()
    local called = Engine.NATURE_POWER_MOVES[terrain_of(M.st)] or 129
    M:say(Strings("NATURE POWER turned into\n%s!", Moves.displayName(called)))
    return run_called(M, called, { slot = M.slot })
  end
end

-- Templates, translated at the time they are said (Strings.source only marks
-- the key: this table is built before a translation catalog exists).
local CHARGE_TEXT = {
  [E.RAZOR_WIND] = Strings.source("%s whipped\nup a whirlwind!"),
  [E.SOLAR_BEAM] = Strings.source("%s took\nin sunlight!"),
  [E.SKULL_BASH] = Strings.source("%s lowered\nits head!"),
  [E.SKY_ATTACK] = Strings.source("%s is glowing!"),
}

local SEMI_TEXT = {
  [MOVE_FLY] = { Strings.source("%s flew\nup high!"), "ON_AIR" },
  [MOVE_BOUNCE] = { Strings.source("%s sprang up!"), "ON_AIR" },
  [MOVE_DIG] = { Strings.source("%s dug a hole!"), "UNDERGROUND" },
  [MOVE_DIVE] = { Strings.source("%s hid\nunderwater!"), "UNDERWATER" },
}

local function set_semi(b, kind)
  b.semiInvulnerable = kind
  b.onAir = kind == "ON_AIR" or nil
  b.underground = kind == "UNDERGROUND" or nil
  b.underwater = kind == "UNDERWATER" or nil
end
Engine.setSemiInvulnerable = set_semi

-- pokefirered/data/battle_scripts_1.s:794
local function charge_turn(M)
  local ad, user, eff = M.adapter, M.user, M.effect
  local isCharge = CHARGE_TEXT[eff] or eff == E.SEMI_INVULNERABLE
  if not isCharge then return false end
  if user.twoTurnMove ~= nil and move_num(user.twoTurnMove) == M.mnum then
    user.twoTurnMove = nil
    user.twoTurnTarget = nil
    user.expLockedMove = nil
    user.expLockedSlot = nil
    M.noPP = true
    M.secondTurn = true
    M.animTurn = 1
    if M.mnum == MOVE_SKY_ATTACK then M.extraEffect = { eff = "FLINCH" } end
    if M.mnum == MOVE_BOUNCE then M.extraEffect = { eff = "PARALYSIS" } end
    return false
  end
  if eff == E.SOLAR_BEAM and Rules.weather.effective(M.st, ad) == "SUN" then
    M:ppReduce()
    M.noPP = true
    return false
  end
  if ModRuntime.wantsHook("battle.charge_required") then
    local required = ModRuntime.call("battle.charge_required", function(c)
      return c.charge
    end, { battle = M.st, user = user, target = M.target,
           move = require("src.mods.Gen3Compat").moveView(M.move),
           charge = true, isCalled = M.opts.called and true or false })
    if required == false then
      M:ppReduce()
      M.noPP = true
      return false
    end
  end
  M:ppReduce()
  M:attackAnimation(0)
  user.twoTurnMove = M.moveId
  user.twoTurnTarget = M.target
  user.expLockedMove = M.moveId
  user.expLockedSlot = M.slot
  if eff == E.SEMI_INVULNERABLE then
    local row = SEMI_TEXT[M.mnum]
    if not row then
      local n = tostring(M.moveName):upper()
      if n:find("FLY") then row = SEMI_TEXT[MOVE_FLY]
      elseif n:find("DIVE") then row = SEMI_TEXT[MOVE_DIVE]
      elseif n:find("BOUNCE") then row = SEMI_TEXT[MOVE_BOUNCE]
      else row = SEMI_TEXT[MOVE_DIG] end
    end
    M:say(Strings(row[1], M.uname))
    set_semi(user, row[2])
  else
    M:say(Strings(CHARGE_TEXT[eff], M.uname))
    if eff == E.SKULL_BASH then
      Secondary.changeStat(ad, user, "defense", 1, { user = true, allowPtr = true, noMsg = (user.stages.defense or 0) >= 6 })
    end
  end
  M.anim.statusOnly = true
  M.anim.charging = true
  return true
end

-- pokefirered/data/battle_scripts_1.s:761
local function ohko(M)
  local ad, user, target = M.adapter, M.user, M.target
  M:attackString()
  M:ppReduce()
  if not M:accuracyCheck("lockon", true) then
    M.anim.missed = true
    return
  end
  local _, flags = Types.typeCalc(M.move.type, target.type1, target.type2, nil, target.expIdentified)
  if flags.immune or (ad:abilityOf(target) == "LEVITATE" and tonumber(M.move.type) == Types.ID.GROUND) then
    M.anim.missed = true
    M:say(Strings("It doesn't affect\n%s…", M.tname))
    return
  end
  local banded = HeldItems.rollFocusBand(ad, target)
  target.expFocusBanded = nil
  if ad:abilityOf(target) == "STURDY" then
    M.anim.missed = true
    M:say(Strings("%s was protected\nby STURDY!", M.tname))
    return
  end
  local uLvl = tonumber(user.mon and user.mon.level) or 1
  local tLvl = tonumber(target.mon and target.mon.level) or 1
  local hit
  -- pokefirered/src/battle_script_commands.c:7104
  if M:lockOnActive() and uLvl >= tLvl then
    hit = true
  else
    local chance = (tonumber(M.move.accuracy) or 30) + (uLvl - tLvl)
    hit = roll(ad, 1, 100) < chance and uLvl >= tLvl
  end
  if not hit then
    M.anim.missed = true
    if uLvl >= tLvl then
      M:say(Strings("%s's\nattack missed!", M.uname))
    else
      M:say(Strings("%s is\nunaffected!", M.tname))
    end
    return
  end
  local Hit = require("src.core.game3.battle.effects.hit")
  local hpBefore = ad:hp(target)
  local dmg = hpBefore
  local endured = target.expEnduring and true or false
  local hung = not endured and banded
  if endured or hung then dmg = math.max(0, hpBefore - 1) end
  Hit.dealDamage(M, dmg, { physical = Types.isPhysical(M.move.type) })
  if endured then
    M:say(Strings("%s ENDURED\nthe hit!", M.tname))
  elseif hung then
    HeldItems.focusBandMessage(ad, target)
  else
    M:say(Strings("It's a one-hit KO!"))
  end
  M:tryFaintTarget()
end

-- pokefirered/src/battle_script_commands.c:866
local function try_bounce(M)
  local ad, user, target = M.adapter, M.user, M.target
  if M.opts.bounced then return false end
  if target and target ~= user and target.expMagicCoat and has_flag(M.move, FLAG_MAGIC_COAT_AFFECTED) then
    target.expMagicCoat = nil
    M:attackString()
    M:ppReduce()
    M:say(Strings("%s's %s\nwas bounced back by MAGIC COAT!", M.uname, M.moveName))
    M.user, M.target = target, user
    M.uname, M.tname = M.tname, M.uname
    M.slot = nil
    M.noPP = true
    M.opts.bounced = true
    return true
  end
  local foe = ad:foeOf(user)
  if M.st and M.st.double then
    foe = nil
    for _, id in ipairs(Engine.turnOrderIds(M.st)) do
      local b = State.battler(M.st, id)
      if b and b ~= user and b.expSnatch and State.isPresent(M.st, id) then foe = b break end
    end
  end
  if foe and foe ~= user and foe.expSnatch and has_flag(M.move, FLAG_SNATCH_AFFECTED) then
    foe.expSnatch = nil
    M:attackString()
    M:ppReduce()
    ad:playAnim("general", "SNATCH_MOVE", user, foe)
    M:say(Strings("%s SNATCHED\n%s's move!", ad:displayName(foe), M.uname))
    M.user, M.target = foe, user
    M.uname, M.tname = ad:displayName(foe), M.uname
    M.slot = nil
    M.noPP = true
    M.opts.bounced = true
    return true
  end
  return false
end

-- pokefirered/src/battle_util.c:427
function Engine.isImprisoned(ad, b, num)
  if not (ad and b and num) then return false end
  local st = ad._st
  local foes = (st and st.double) and State.foes(st, b) or { ad:foeOf(b) }
  for _, foe in ipairs(foes) do
    if foe and foe.expImprison then
      local fm = foe.mon and foe.mon.moves or {}
      for j = 1, 4 do
        if fm[j] and move_num(fm[j]) == num then return true end
      end
    end
  end
  return false
end

function Engine.turnOrderIds(st)
  if st and st.turnOrder and #st.turnOrder > 0 then return st.turnOrder end
  return State.presentIds(st)
end

-- pokefirered/src/battle_script_commands.c:2092
function Engine.turnOrderNum(st, id)
  local order = Engine.turnOrderIds(st)
  for i, v in ipairs(order) do
    if v == id then return i - 1 end
  end
  return 4
end

local function has_bit(v, b) return math.floor((tonumber(v) or 0) / b) % 2 == 1 end

local function follow_me_id(st, ad, attacker)
  local side = ad:foeSide(attacker)
  if not side then return nil end
  if side.expFollowMeId ~= nil then return side.expFollowMeId end
  if side.expFollowMe then return State.idOf(side.expFollowMe) end
  return nil
end
Engine.followMeId = follow_me_id

local function foe_left(aid) return (aid % 2 == 0) and 1 or 0 end

local function random_foe_flank(st, ad, aid)
  if roll(ad, 0, 1) == 1 then return foe_left(aid) end
  return foe_left(aid) + 2
end

-- pokefirered/src/battle_util.c:3054
function Engine.getMoveTarget(st, ad, attacker, moveId, setTarget)
  local aid = State.idOf(attacker)
  local mv = Moves.get(moveId)
  local ttype = setTarget and (setTarget - 1) or (tonumber(mv and mv.target) or 0)
  local count = (st and st.double) and 4 or 2
  local target
  if ttype == MOVE_TARGET_SELECTED then
    local fm = follow_me_id(st, ad, attacker)
    if fm ~= nil and ad:hp(State.battler(st, fm)) > 0 then
      target = fm
    else
      for _ = 1, 256 do
        target = roll(ad, 0, count - 1) % count
        if target ~= aid and target % 2 ~= aid % 2 and State.isPresent(st, target) then break end
        target = nil
      end
      target = target or foe_left(aid)
      local lr = 0
      for id = 0, count - 1 do
        local b = State.battler(st, id)
        if b and id % 2 ~= aid % 2 and ad:abilityOf(b) == "LIGHTNING_ROD" then lr = lr + 1 end
      end
      if tonumber(mv and mv.type) == Types.ID.ELECTRIC and lr > 0
          and ad:abilityOf(State.battler(st, target)) ~= "LIGHTNING_ROD" then
        target = State.PARTNER(target)
        local rb = State.battler(st, target)
        if rb then rb.expLightningRodRedirected = true end
      end
    end
  elseif ttype == MOVE_TARGET_DEPENDS or ttype == MOVE_TARGET_BOTH or ttype == MOVE_TARGET_FOES_AND_ALLY
      or ttype == MOVE_TARGET_OPPONENTS_FIELD then
    target = foe_left(aid)
    if not State.isPresent(st, target) and count == 4 then target = State.PARTNER(target) end
  elseif ttype == MOVE_TARGET_RANDOM then
    local fm = follow_me_id(st, ad, attacker)
    if fm ~= nil and ad:hp(State.battler(st, fm)) > 0 then
      target = fm
    elseif st and st.double then
      target = random_foe_flank(st, ad, aid)
      if not State.isPresent(st, target) then target = State.PARTNER(target) end
    else
      target = foe_left(aid)
    end
  else
    target = aid
  end
  if st then
    st.moveTarget = st.moveTarget or {}
    st.moveTarget[aid] = target
  end
  return target
end

-- pokefirered/src/battle_main.c:4024
function Engine.resolveTarget(st, ad, attacker, moveId, chosenId, info)
  info = info or {}
  local aid = State.idOf(attacker)
  local mv = Moves.get(moveId)
  local ttype = tonumber(mv and mv.target) or 0
  local chosenMv = info.chosenMove and Moves.get(info.chosenMove) or mv
  local chosenRandom = has_bit(chosenMv and chosenMv.target, MOVE_TARGET_RANDOM)
  local mt = chosenId
  if mt == nil or info.recompute then mt = Engine.getMoveTarget(st, ad, attacker, moveId) end
  st.moveTarget = st.moveTarget or {}
  st.moveTarget[aid] = mt
  local function absent_fix(t)
    if not State.isPresent(st, t) then
      if t % 2 ~= aid % 2 then
        t = State.PARTNER(t)
      else
        t = foe_left(aid)
        if not State.isPresent(st, t) then t = State.PARTNER(t) end
      end
    end
    return t
  end
  local fm = follow_me_id(st, ad, attacker)
  if fm ~= nil and ttype == MOVE_TARGET_SELECTED and fm % 2 ~= aid % 2
      and ad:hp(State.battler(st, fm)) > 0 then
    return fm
  end
  if st.double and fm == nil and ((tonumber(mv and mv.power) or 0) ~= 0 or ttype ~= MOVE_TARGET_USER)
      and ad:abilityOf(State.battler(st, mt)) ~= "LIGHTNING_ROD"
      and tonumber(mv and mv.type) == Types.ID.ELECTRIC then
    local best, bestNum = nil, 4
    for id = 0, 3 do
      local b = State.battler(st, id)
      if b and id % 2 ~= aid % 2 and id ~= mt and ad:abilityOf(b) == "LIGHTNING_ROD" then
        local n = Engine.turnOrderNum(st, id)
        if n < bestNum then best, bestNum = id, n end
      end
    end
    if best == nil then
      local t = mt
      if chosenRandom then t = random_foe_flank(st, ad, aid) end
      return absent_fix(t)
    end
    State.battler(st, best).expLightningRodRedirected = true
    return best
  end
  if st.double and chosenRandom then
    local t = random_foe_flank(st, ad, aid)
    if not State.isPresent(st, t) then t = State.PARTNER(t) end
    return t
  end
  return absent_fix(mt)
end

-- pokefirered/src/battle_util.c:361
function Engine.moveLimitations(b, ad)
  local bad = {}
  local mon = b and b.mon or {}
  local he = HeldItems.of(b)
  local foe = ad and ad:foeOf(b)
  for i = 1, 4 do
    local mv = mon.moves and mon.moves[i]
    local n = (mv ~= nil and mv ~= "" and mv ~= 0) and move_num(mv) or nil
    if not n or n == 0 then
      bad[i] = true
    else
      if tonumber(mon.pp and mon.pp[i]) == 0 then bad[i] = true end
      if b.expDisabledMove and n == b.expDisabledMove then bad[i] = true end
      if b.expTormented and n == move_num(b.lastMoveId) then bad[i] = true end
      if (b.expTauntedTurns or 0) > 0 and (tonumber(Moves.get(mv).power) or 0) == 0 then bad[i] = true end
      if ad and ad._st and ad._st.double then
        if Engine.isImprisoned(ad, b, n) then bad[i] = true end
      elseif foe and foe.expImprison then
        local fm = foe.mon and foe.mon.moves or {}
        for j = 1, 4 do
          if fm[j] and move_num(fm[j]) == n then bad[i] = true end
        end
      end
      if (b.expEncoreTurns or 0) > 0 and b.expEncoreMove and move_num(b.expEncoreMove) ~= n then bad[i] = true end
      if he == HeldItems.HOLD.CHOICE_BAND and b.choicedMove and b.choicedMove ~= n then bad[i] = true end
    end
  end
  return bad
end

local function player_identity(st)
  local id, nm = st.playerTrainerId, st.playerOtName or st.playerName
  if id == nil then
    local Runtime = package.loaded["src.core.game3.runtime"]
    local ok, sess = pcall(function() return Runtime and Runtime.getSession and Runtime.getSession() end)
    if ok and sess then
      id = sess.trainerId or sess.id or sess.playerId or 12345
      nm = sess.name or sess.playerName or nm or "RED"
    end
  end
  return id, nm
end

-- pokefirered/src/pokemon.c:5965
function Engine.isTradedMon(st, mon)
  if not mon or mon.otId == nil then return false end
  local pid, pname = player_identity(st or {})
  if pid == nil then return false end
  return tonumber(mon.otId) ~= tonumber(pid)
    or (mon.otName ~= nil and pname ~= nil and tostring(mon.otName) ~= tostring(pname))
end

local LOAF_TEXT = {
  Strings.source("%s is\nloafing around!"), Strings.source("%s won't\nobey!"),
  Strings.source("%s turned away!"), Strings.source("%s pretended\nnot to notice!"),
}

-- pokefirered/src/battle_util.c:3143
local function disobedient(M)
  local ad, user, st = M.adapter, M.user, M.st
  if not st or st.link or st.pokedude or not user or user.side ~= "player" then return nil end
  local mon = State.partyMon(user) or user.mon or {}
  local species = tonumber(user.species)
  local ob = 0
  if not ((species == 151 or species == 410) and mon.fatefulEncounter == false) then
    if not Engine.isTradedMon(st, mon) or Engine.hasBadge(st, 8) then return nil end
    ob = 10
    if Engine.hasBadge(st, 2) then ob = 30 end
    if Engine.hasBadge(st, 4) then ob = 50 end
    if Engine.hasBadge(st, 6) then ob = 70 end
  end
  local lvl = tonumber(user.mon and user.mon.level) or tonumber(mon.level) or 1
  if lvl <= ob then return nil end
  if math.floor((lvl + ob) * roll(ad, 0, 255) / 256) < ob then return nil end
  if M.mnum == 99 then user.rage = nil end
  if ad:status(user) == "SLP" and (M.mnum == MOVE_SNORE or M.mnum == MOVE_SLEEP_TALK) then
    M:say(Strings("%s ignored\norders while asleep!", M.uname))
    return "stop"
  end
  if math.floor((lvl + ob) * roll(ad, 0, 255) / 256) < ob and M.mnum ~= 264 then
    local bad = Engine.moveLimitations(user, ad)
    if M.slot then bad[M.slot] = true end
    if bad[1] and bad[2] and bad[3] and bad[4] then
      M:say(Strings(LOAF_TEXT[roll(ad, 0, 3) % 4 + 1], M.uname))
      return "stop"
    end
    local slot
    repeat slot = roll(ad, 0, 3) % 4 + 1 until not bad[slot]
    M:say(Strings("%s ignored\norders!", M.uname))
    return "called", slot
  end
  local diff = lvl - ob
  local r = roll(ad, 0, 255)
  local ab = ad:abilityOf(user)
  if r < diff and not ad:status(user) and ab ~= "VITAL_SPIRIT" and ab ~= "INSOMNIA" and not ad:uproarActive() then
    M:say(Strings("%s began to nap!", M.uname))
    ad:applyStatus(user, "SLP", user, { force = true, ignoreSafeguard = true })
    ad:statusAnim(user, "SLP")
    M:say(Strings("%s\nfell asleep!", M.uname))
    return "stop"
  end
  r = r - diff
  if r < diff then
    M:say(Strings("%s won't\nobey!", M.uname))
    Engine.cancelMultiTurnMoves(user)
    local dmg = Damage.base(user, user, { power = 40, type = 0, effect = 0 }, {
      power = 40, moveType = 0, adapter = ad,
    })
    Engine.selfHit(M, dmg)
    return "stop"
  end
  M:say(Strings(LOAF_TEXT[roll(ad, 0, 3) % 4 + 1], M.uname))
  return "stop"
end
Engine.disobedient = disobedient

-- pokefirered/src/battle_script_commands.c:4121
function Engine.moveEndEffects(M)
  local ad, user, target = M.adapter, M.user, M.target
  if target and target ~= user then Abilities.synchronize(M, target, user) end
  Abilities.onDamage(M)
  Abilities.immunityCure(ad)
  if target and target ~= user then Abilities.synchronize(M, user, target) end
  local chosenNum = move_num(M.opts.calledBy or M.moveId)
  if not M.notObeyed and HeldItems.has(user, HeldItems.HOLD.CHOICE_BAND) and chosenNum ~= MOVE_STRUGGLE
      and not user.choicedMove then
    local cm = Moves.get(M.opts.calledBy or M.moveId)
    if not (tonumber(cm and cm.effect) == E.BATON_PASS and not M.failed) then
      user.choicedMove = chosenNum
    end
  end
  if user.choicedMove then
    local H = require("src.core.game3.battle.effects._helpers")
    if not H.slotOf(user, user.choicedMove) then user.choicedMove = nil end
  end
  HeldItems.moveEnd(ad)
  HeldItems.kingsRockShellBell(M)
end

function Engine.moveEndLite(M)
  Abilities.immunityCure(M.adapter)
  HeldItems.moveEnd(M.adapter)
end

-- pokefirered/src/battle_util.c:1208
function Engine.afterAction(st, ad)
  if not st or st.over then return end
  for _ = 1, 4 do
    local did = Abilities.runIntimidate(ad) or Abilities.runTrace(ad)
      or HeldItems.normal(ad, st.player, true) or Abilities.forecast(ad)
    if not did then break end
  end
end

-- pokefirered/src/battle_script_commands.c:4056
local function move_end(M)
  local ad, user, target = M.adapter, M.user, M.target
  if target and target ~= user and target.rage and not ad:isFainted(target)
      and user.side ~= target.side and not M.noEffect and (M.hitsLanded or 0) > 0
      and (tonumber(M.move.power) or 0) > 0 and (target.stages.attack or 0) < 6 then
    target.stages.attack = target.stages.attack + 1
    M:say(Strings("%s's RAGE\nis building!", ad:displayName(target)))
  end
  if target and target ~= user and ad:status(target) == "FRZ" and not ad:isFainted(target)
      and (M.specialHit or false) and not M.noEffect and tonumber(M.moveType or M.move.type) == Types.ID.FIRE then
    ad:clearStatus(target)
    M:say(Strings("%s was\ndefrosted!", ad:displayName(target)))
  end
  Engine.moveEndEffects(M)
  local chosen = M.opts.calledBy or M.moveId
  local chosenMove = M.opts.calledBy and Moves.get(M.opts.calledBy) or M.move
  if tonumber(chosenMove.effect) ~= E.BATON_PASS then
    user.lastMoveId = chosen
    user.lastMove = chosen
    user.expLastResulting = M.moveId
  end
  if M.printedUsed then user.expLastPrinted = chosen end
  if M.notObeyed then
    user.lastMoveId = nil
    user.lastMove = nil
  end
  if target and target ~= user and not M.noEffect and not M.anim.missed
      and has_flag(chosenMove, FLAG_MIRROR_MOVE_AFFECTED) and not ad:isFainted(target) then
    target.expLastTakenMove = chosen
  end
  if target and target ~= user and not M.noEffect and not M.anim.missed and (M.hitsLanded or 0) > 0 then
    target.expLastLandedMove = M.mnum
    target.expLastHitByType = tonumber(M.moveType or M.move.type)
  end
end

local function run(M)
  local ad, user = M.adapter, M.user
  local eff = M.effect

  if not M.opts.called then
    user.expMovedThisTurn = true
    local c = canceller(M)
    if c == false then
      M.anim.statusOnly = true
      M.anim.cancelled = true
      user.lastMoveId = nil
      user.lastMove = nil
      Engine.moveEndLite(M)
      return
    end
    if c == "bide" then
      M.anim.statusOnly = false
      bide_attack(M)
      move_end(M)
      return
    end
    if c == "ghost" then
      M.anim.statusOnly = true
      move_end(M)
      return
    end
    if Abilities.soundproofBlocks(M) then
      M.notObeyed = true
      move_end(M)
      return
    end
    if M.slot and user.mon and user.mon.pp and tonumber(user.mon.pp[M.slot]) == 0
        and not user.expLockedMove and M.mnum ~= MOVE_STRUGGLE then
      M:attackString()
      M:say(Strings("But there was no PP left\nfor the move!"))
      M.anim.statusOnly = true
      return
    end
    if not user.expLockedMove then
      local d, slot = disobedient(M)
      if d == "stop" then
        M.anim.statusOnly = true
        M.anim.cancelled = true
        user.lastMoveId = nil
        user.lastMove = nil
        Engine.moveEndLite(M)
        return
      elseif d == "called" then
        M.anim.statusOnly = true
        return run_called(M, user.mon.moves[slot], { slot = slot })
      end
    end
  end

  if eff ~= E.PROTECT and eff ~= E.ENDURE then
    user.expProtectStreak = 0
  end

  if charge_turn(M) then
    move_end(M)
    return
  end

  if eff == E.METRONOME or eff == E.SLEEP_TALK or eff == E.MIRROR_MOVE or eff == E.ASSIST
      or eff == E.NATURE_POWER then
    M.anim.statusOnly = true
    return call_moves(M)
  end

  if eff == E.FOCUS_PUNCH and ((user.lastPhysicalDamageTaken or 0) > 0 or (user.lastSpecialDamageTaken or 0) > 0) then
    -- pokefirered/data/battle_scripts_1.s:2255
    M:ppReduce()
    M:say(Strings("%s lost its\nfocus and couldn't move!", M.uname))
    M.anim.statusOnly = true
    return
  end

  local function body()
    try_bounce(M)
    Engine.lightningRodTook(M)

    if eff == E.OHKO then
      ohko(M)
      move_end(M)
      return
    end

    if eff == E.BIDE then
      -- pokefirered/data/battle_scripts_1.s:575
      M:attackString()
      M:ppReduce()
      M:attackAnimation()
      user.bideTurns = 2
      user.expBideDamage = 0
      user.expBideTarget = nil
      user.expLockedMove = M.moveId
      user.expLockedSlot = M.slot
      M.anim.statusOnly = true
      move_end(M)
      return
    end

    local power = tonumber(M.move.power) or 0
    if power > 0 then
      local Hit = require("src.core.game3.battle.effects.hit")
      Hit.run(M)
      move_end(M)
      return
    end

    M.anim.statusOnly = true
    M:attackString()
    M:ppReduce()
    local handled = Effects.runForMove(ad, M.user, M.target, M.moveId, M)
    if not handled then
      M:attackAnimation()
      M:say(Strings("But nothing happened!"))
    end
    M:tryFaintTarget()
    M:tryFaintUser()
    move_end(M)
  end

  Engine.forEachTarget(M, body)
end

-- pokefirered/src/battle_script_commands.c:888
function Engine.lightningRodTook(M)
  local t = M.target
  if not (t and t.expLightningRodRedirected) then return false end
  t.expLightningRodRedirected = nil
  M:attackString()
  M:say(Strings("%s's %s\ntook the attack!", M.adapter:displayName(t), Abilities.name("LIGHTNING_ROD")))
  return true
end

-- pokefirered/src/battle_script_commands.c:3469
function Engine.resetTargetValues(M)
  M.noEffect, M.missReason, M.failed, M.hitSubstitute = nil, nil, nil, nil
  M.hpDealt, M.firstDmg, M.hitsLanded, M.targetDamaged, M.specialHit = nil, nil, nil, nil, nil
  M.dmgMultiplier = 1
  M.ignoreOnAir, M.ignoreUnderground, M.ignoreUnderwater = nil, nil, nil
  M.brokeWall, M._animDmg, M._animPower = nil, nil, nil
  if M.anim then M.anim.missed = false end
end

local function set_target(M, b)
  M.target = b
  M.tname = M.adapter:displayName(b)
  if b then b._statLoweredMsg = nil end
end

-- pokefirered/src/battle_script_commands.c:4308
function Engine.forEachTarget(M, body)
  local st, ad = M.st, M.adapter
  local ttype = tonumber(M.move and M.move.target) or 0
  M.targets = { M.target and State.idOf(M.target) or nil }
  M.targetIndex = 1
  if not (st and st.double) or M.noSpread then return body(M) end
  if ttype == MOVE_TARGET_FOES_AND_ALLY then
    -- pokefirered/src/battle_script_commands.c:8532
    local uid = State.idOf(M.user)
    local ids = {}
    for id = 0, 3 do
      if id ~= uid and State.isPresent(st, id) then ids[#ids + 1] = id end
    end
    if #ids == 0 then return body(M) end
    M.targets = ids
    M.deferUserFaint = (M.effect == E.EXPLOSION)
    local anyLanded = false
    for i, id in ipairs(ids) do
      if i > 1 then Engine.resetTargetValues(M) end
      M.targetIndex = i
      set_target(M, State.battler(st, id))
      body(M)
      if not M.anim.missed then anyLanded = true end
      if M.stopTargets then break end
    end
    M.anim.missed = not anyLanded
    if M.deferUserFaint then
      M.deferUserFaint = nil
      M:tryFaintUser()
    end
    return
  end
  if ttype == MOVE_TARGET_BOTH then
    body(M)
    local firstMissed = M.anim.missed
    if M.stopTargets or not M.target then return end
    local pid = State.PARTNER(State.idOf(M.target))
    local nb = State.battler(st, pid)
    if nb and State.isPresent(st, pid) and ad:hp(nb) > 0 then
      Engine.resetTargetValues(M)
      M.targets[2] = pid
      M.targetIndex = 2
      set_target(M, nb)
      body(M)
      M.anim.missed = firstMissed and M.anim.missed
    end
    return
  end
  return body(M)
end

--- Resolve a move. Returns message list.
-- Also fills out._anim (presentation meta for AnimSeq): moveId, user, target,
function Engine.resolveMove(user, target, moveId, slot, adapter, st, out, opts)
  out = out or {}
  opts = opts or {}
  local chosenTargetId = (target ~= nil and type(target) ~= "string") and State.idOf(target) or nil
  if st then
    user = State.occupant(st, user)
    target = State.occupant(st, target)
  end

  local nested = opts.called and opts.anim ~= nil
  local prevSay = adapter._say
  local mark = adapter:eventMark()
  if not nested then
    adapter._say = function(text) out[#out + 1] = text end
  end

  local absentUser = st and st.double and user and State.isAbsent(st, State.idOf(user))
  if not opts.called and st and (st.over or absentUser) then
    local anim = { moveId = moveId, user = user, target = target, hits = {}, heals = {}, faints = {},
      missed = false, statusOnly = true, msgs = {}, events = {} }
    out._anim = anim
    adapter._say = prevSay
    return out
  end

  local chosenMoveId = moveId
  local retarget = false
  local locked = false
  if not opts.called and user then
    if user.expLockedMove and not opts.pursuitSwitch then
      moveId = user.expLockedMove
      slot = user.expLockedSlot
      locked = true
      if user.twoTurnTarget and st and State.occupant(st, user.twoTurnTarget) then
        target = State.occupant(st, user.twoTurnTarget)
      end
    elseif user.expEncoreMove and (user.expEncoreTurns or 0) > 0 then
      local H = require("src.core.game3.battle.effects._helpers")
      local es = H.slotOf(user, user.expEncoreMove)
      if es then
        if move_num(user.mon.moves[es]) ~= move_num(moveId) then retarget = true end
        moveId = user.mon.moves[es]
        slot = es
      end
    end
  end
  -- pokefirered/src/battle_main.c:3963
  if st and st.double and user and not opts.called and not opts.pursuitSwitch and not opts.noRetarget
      and not absentUser then
    for id = 0, 3 do
      local b = State.battler(st, id)
      if b then b.expLightningRodRedirected = nil end
    end
    local uid = State.idOf(user)
    local tid = chosenTargetId
    if locked then
      tid = (st.moveTarget and st.moveTarget[uid]) or (user.twoTurnTarget and State.idOf(user.twoTurnTarget)) or tid
    end
    local rid = Engine.resolveTarget(st, adapter, user, moveId, tid, {
      recompute = retarget or tid == nil, chosenMove = locked and moveId or chosenMoveId,
    })
    target = State.battler(st, rid) or target
  end

  local anim = opts.anim or {
    moveId = moveId,
    user = user,
    target = target,
    hits = {},
    heals = {},
    faints = {},
    missed = false,
    statusOnly = false,
  }
  if nested then
    anim.moveId = moveId
    anim.target = target
  end

  if not opts.called then Engine.refreshLinks(st) end
  if not opts.called and st and st._focusPunchSetup then
    local list = st._focusPunchSetup
    st._focusPunchSetup = nil
    for _, b in ipairs(list) do
      if not adapter:isFainted(b) then
        adapter:playAnim("general", "FOCUS_PUNCH_SETUP", b, b)
        adapter:say(Strings("%s is tightening\nits focus!", adapter:displayName(b)))
      end
    end
  end

  local M = new_ctx(user, target, moveId, slot, adapter, st, out, anim, opts)
  if opts.called then M.printedUsed = false end
  if user then user._statLoweredMsg = nil end
  if target then target._statLoweredMsg = nil end
  if not opts.called then adapter._syncEffect = nil end
  if nested or not (st and st.interactiveChoices) then
    run(M)
  else
    local co = coroutine.create(run)
    local ok, req = coroutine.resume(co, M)
    if not ok then error(debug.traceback(co, req), 0) end
    if coroutine.status(co) == "suspended" then
      st.pendingChoice = { co = co, req = req, M = M }
      return Engine.finishResolve(adapter, st, out, anim, mark, prevSay, true)
    end
  end

  if nested then return out end
  return Engine.finishResolve(adapter, st, out, anim, mark, prevSay, opts.called)
end

function Engine.finishResolve(adapter, st, out, anim, mark, prevSay, skipAfter)
  if not skipAfter then Engine.afterAction(st, adapter) end

  anim.events = adapter:eventsSince(mark)
  anim.heals = {}
  for _, ev in ipairs(anim.events) do
    if ev.kind == "hp" then
      anim.heals[#anim.heals + 1] = { side = ev.side, from = ev.from, to = ev.to, maxHp = ev.maxHp }
    end
  end
  anim.msgs = {}
  for i = 1, #out do anim.msgs[i] = out[i] end
  out.events = anim.events
  out._anim = anim
  out.pendingChoice = st and st.pendingChoice and st.pendingChoice.req or nil
  adapter._say = prevSay
  return out
end

-- pokefirered/src/battle_script_commands.c:4626
function Engine.resumeChoice(st, adapter, value)
  local pend = st and st.pendingChoice
  if not pend then return nil end
  st.pendingChoice = nil
  local M = pend.M
  local out = {}
  local anim = {
    moveId = M.moveId, user = M.user, target = M.target, hits = {}, heals = {}, faints = {},
    missed = false, statusOnly = true,
  }
  M.out = out
  local prevSay = adapter._say
  local mark = adapter:eventMark()
  adapter._say = function(text) out[#out + 1] = text end
  local ok, req = coroutine.resume(pend.co, value)
  if not ok then
    adapter._say = prevSay
    error(debug.traceback(pend.co, req), 0)
  end
  if coroutine.status(pend.co) == "suspended" then
    st.pendingChoice = { co = pend.co, req = req, M = M }
    return Engine.finishResolve(adapter, st, out, anim, mark, prevSay, true)
  end
  return Engine.finishResolve(adapter, st, out, anim, mark, prevSay, false)
end

-- pokefirered/src/battle_ai_switch_items.c:428
function Engine.mostSuitableMon(st, adapter, side)
  local id = (type(side) == "number") and side or State.idOf(side)
  if type(side) == "table" then side = side.side end
  if type(side) ~= "string" then side = State.sideOf(id) end
  local party = (side == "player") and st.playerParty or st.foeParty
  local active = State.battler(st, id)
  local opp = State.battler(st, State.OPPOSITE(id))
  local pending = st.monToSwitchInto or {}
  if pending[id] then return pending[id] end
  local in2 = id
  if st.double then
    if State.isPresent(st, State.PARTNER(id)) then in2 = State.PARTNER(id) end
    -- pokefirered/src/battle_ai_switch_items.c:448
    local oid = (math.floor(roll(adapter, 0, 65535) / 2) % 2) * 2 + (1 - id % 2)
    if not State.isPresent(st, oid) then oid = State.PARTNER(oid) end
    opp = State.battler(st, oid)
  end
  if not party or not opp then return nil end
  local activeIdx = active and active.partyIndex
  local partner = State.battler(st, in2)
  local in2Idx = partner and partner.partyIndex
  local function valid(i, mon)
    return mon and not mon.isEgg and (tonumber(mon.hp) or 0) > 0 and i ~= activeIdx and i ~= in2Idx
      and i ~= pending[id] and i ~= pending[in2]
      and (tonumber(mon.species or mon.speciesId) or 0) ~= 0
  end
  -- pokefirered/src/battle_ai_switch_items.c:404
  local function modulate(atk, d1, d2, v)
    local t = Types.TABLE
    for i = 1, #t, 3 do
      if t[i] ~= -1 and t[i] == atk then
        if t[i + 1] == d1 then v = math.floor(v * t[i + 2] / 10) end
        if t[i + 1] == d2 and d1 ~= d2 then v = math.floor(v * t[i + 2] / 10) end
      end
    end
    return v
  end
  local function types_of(mon)
    local b = State.makeBattler(mon, side, {})
    return b.type1, b.type2 or b.type1
  end
  local oT1, oT2 = opp.type1, opp.type2 or opp.type1
  local invalid = {}
  while true do
    local bestDmg, bestId = 0, nil
    for i = 1, 6 do
      local mon = party[i]
      if valid(i, mon) and not invalid[i] then
        local t1, t2 = types_of(mon)
        local v = modulate(oT1, t1, t2, 10)
        v = modulate(oT2, t1, t2, v)
        if bestDmg < v then bestDmg, bestId = v, i end
      else
        invalid[i] = true
      end
    end
    if not bestId then break end
    local mon = party[bestId]
    for j = 1, 4 do
      local mv = mon.moves and mon.moves[j]
      local n = move_num(mv)
      if n and n ~= 0 then
        local _, flags = Types.typeCalc(Moves.get(mv).type, opp.type1, opp.type2)
        if flags.super then return bestId end
      end
    end
    invalid[bestId] = true
  end
  -- pokefirered/src/battle_ai_switch_items.c:510
  local bestDmg, bestId = 0, nil
  for i = 1, 6 do
    local mon = party[i]
    if valid(i, mon) then
      for j = 1, 4 do
        local mv = mon.moves and mon.moves[j]
        local n = move_num(mv)
        local dmg = 0
        if n and n ~= 0 then
          local m = Moves.get(mv)
          if (tonumber(m.power) or 0) ~= 1 then
            local mt = tonumber(m.type) or 0
            dmg = 2
            if active and (active.type1 == mt or active.type2 == mt) then dmg = math.floor(dmg * 15 / 10) end
            dmg = Types.typeCalc(mt, opp.type1, opp.type2, dmg) or 0
          end
        end
        if bestDmg < dmg then bestDmg, bestId = dmg, i end
      end
    end
  end
  return bestId
end

-- pokefirered/src/battle_main.c:4150
function Engine.performEnemyItem(st, adapter, act)
  local BattleItems = require("src.core.game3.battle.items")
  return BattleItems.enemyUse(st, adapter, act)
end

-- pokefirered/src/battle_script_commands.c:4467
local function switched_event(st, adapter, id, nb, old, opts)
  if not ModRuntime.wants("battle.battler_switched") then return end
  local mon = nb and nb.mon
  local sp = mon and tonumber(mon.species or mon.speciesId)
  ModRuntime.emit("battle.battler_switched", {
    battle = st, side = adapter.ownSide and adapter:ownSide(nb), sideName = nb and nb.side, battler = nb,
    previous = old, battlerId = id, reason = opts and opts.reason,
    species = require("src.mods.Gen3Compat").speciesName(sp), speciesId = sp,
    partyIndex = nb and nb.partyIndex,
  })
end

function Engine.performSwitch(st, adapter, side, slot, opts)
  opts = opts or {}
  local id = (type(side) == "number") and side or State.idOf(side)
  side = State.sideOf(id)
  local old = State.battler(st, id)
  local party = (side == "player") and st.playerParty or st.foeParty
  if not old or not party or not party[slot] then return nil end
  local oldSlot = old.partyIndex
  if side == "player" and not st.double then
    State.trackParticipant(st, st.enemy, oldSlot or 1)
  end
  Engine.switchOutEffects(st, adapter, old)
  State.syncBattlerToParty(old, party)
  local nb = State.makeBattler(party[slot], side, { partyIndex = slot, id = id, st = st })
  if opts.batonPass then
    -- pokefirered/src/battle_main.c:2350
    for k, v in pairs(old.stages or {}) do nb.stages[k] = v end
    nb.confusionTurns = old.confusionTurns
    nb.expFocusEnergy = old.expFocusEnergy
    nb.focusEnergy = old.focusEnergy
    nb.substituteHP = old.substituteHP
    nb.expSeeded = old.expSeeded
    nb.expSeedSource = old.expSeedSource
    nb.expIngrain = old.expIngrain
    nb.expPerishTurns = old.expPerishTurns
    nb.expCursed = old.expCursed
    nb.expTrapped = old.expTrapped
    nb.escapePrevention = old.escapePrevention
    nb.expLockedOn = old.expLockedOn
    nb.expLockedOnBy = old.expLockedOnBy
  end
  if st.battlers then st.battlers[id] = nb else st[side] = nb end
  if st.absent then st.absent[id] = nil end
  if st.monToSwitchInto then st.monToSwitchInto[id] = nil end
  Engine.cancelPendingAction(st, id)
  if st.double then
    -- pokefirered/src/battle_script_commands.c:4966
    State.updateSentPokes(st, nb)
    for oid = 0, 3 do
      local b = State.battler(st, oid)
      if b and oid ~= id then
        if b.expSeedSource == old then b.expSeedSource = nb end
        if b.expTrapSource == old then
          b.expTrapTurns, b.expTrapSource, b.wrapped = nil, nil, nil
        end
        if b.expTrappedBy == old then
          b.expTrapped, b.expTrappedBy, b.escapePrevention = nil, nil, nil
        end
        if b.expInfatuatedWith == old then
          b.expInfatuated, b.expInfatuatedWith, b.expInfatuatedBy = nil, nil, nil
        end
        if b.expLockedOnById == id then b.expLockedOn, b.expLockedOnById, b.expLockedOnBy = nil, nil, nil end
      end
    end
    adapter:pushEvent({ kind = "switch", side = side, battler = id, from = oldSlot, to = slot, reason = opts.reason })
    switched_event(st, adapter, id, nb, old, opts)
    return nb
  end
  local foe = (side == "player") and st.enemy or st.player
  if side == "player" then
    State.trackParticipant(st, st.enemy, slot)
  elseif st.player then
    -- pokefirered/src/battle_util.c:254
    State.trackParticipant(st, nb, st.player.partyIndex)
  end
  if foe then
    if foe.expSeedSource == old then foe.expSeedSource = nb end
    if foe.expTrapSource == old then
      foe.expTrapTurns = nil
      foe.expTrapSource = nil
      foe.wrapped = nil
    end
    if foe.expTrappedBy == old then
      foe.expTrapped = nil
      foe.escapePrevention = nil
    end
    foe.expInfatuated = nil
    if foe.expLockedOnBy == side then foe.expLockedOn = nil end
  end
  adapter:pushEvent({ kind = "switch", side = side, battler = id, from = oldSlot, to = slot, reason = opts.reason })
  switched_event(st, adapter, id, nb, old, opts)
  return nb
end

-- pokefirered/src/battle_script_commands.c:5013
function Engine.cancelPendingAction(st, id)
  for _, act in ipairs(st and st.turnActions or {}) do
    if act.battler == id and not act.done then act.finished = true end
  end
end

function Engine.actionRunnable(st, act)
  if not act or act.finished or act.done then return false end
  if act.battler ~= nil and State.isAbsent(st, act.battler) then return false end
  return true
end

-- pokefirered/src/battle_script_commands.c:9197
function Engine.switchOutEffects(st, adapter, battler)
  if not battler or not adapter then return false end
  return Abilities.switchOut(adapter, battler)
end

-- pokefirered/src/battle_script_commands.c:4960
function Engine.switchInEffects(st, adapter, battler, opts)
  opts = opts or {}
  if not battler or not adapter or (st and st.over) then return false end
  if opts.spikes then
    local Hazards = require("src.core.game3.battle.effects.hazards")
    local layers = Hazards.layers(adapter:ownSide(battler))
    if layers > 0 and not adapter:hasType(battler, Types.ID.FLYING) and adapter:abilityOf(battler) ~= "LEVITATE" then
      local denom = ({ 8, 6, 4 })[math.min(layers, 3)]
      local dmg = math.max(1, math.floor(adapter:maxHp(battler) / denom))
      adapter:applyHpLoss(battler, dmg)
      adapter:say(Strings("%s is hurt\nby SPIKES!", adapter:displayName(battler)))
      if adapter:isFainted(battler) then return true end
    end
  end
  if adapter:isFainted(battler) then return false end
  if adapter:abilityOf(battler) == "TRUANT" then battler.expTruantCounter = 1 end
  local did = Abilities.switchIn(adapter, battler)
  if not did then did = HeldItems.onSwitchIn(adapter, battler) end
  if not opts.deferIntimidate then
    for _ = 1, 4 do
      if not (Abilities.runIntimidate(adapter) or Abilities.runTrace(adapter)) then break end
      did = true
    end
  end
  return did
end

-- pokefirered/src/battle_main.c:2856
function Engine.battleStartEffects(st, adapter)
  if not st or not adapter then return false end
  local did = false
  local w = Rules.weather.kind(st.overworldWeather)
  if w and not st._overworldWeatherDone then
    st._overworldWeatherDone = true
    if Rules.weather.kind(st.weather) ~= w then
      st.weather, st.weatherTurns = w, 0
      local line = (w == "SAND" and Strings("A sandstorm is raging."))
        or (w == "SUN" and Strings("The sunlight is strong.")) or Strings("It is raining.")
      adapter:say(line)
      adapter:playAnim("general", w == "SAND" and "SANDSTORM_CONTINUES" or (w == "SUN" and "SUN_CONTINUES")
        or "RAIN_CONTINUES", st.player, st.player)
      did = true
    end
  end
  local order = Residuals.sortedBattlers(adapter)
  -- pokefirered/src/battle_util.c:1678
  if not st.safari then
    for _, b in ipairs(order) do
      if Abilities.switchIn(adapter, b) then did = true end
    end
    for _ = 1, 4 do
      if not (Abilities.runIntimidate(adapter) or Abilities.runTrace(adapter)) then break end
      did = true
    end
  end
  for _, b in ipairs(order) do
    if HeldItems.onSwitchIn(adapter, b) then did = true end
  end
  return did
end

-- pokefirered/src/battle_main.c:3002
function Engine.canRun(st, adapter, battler)
  battler = battler or (st and st.player)
  if not st or not battler then return false, nil end
  -- pokefirered/src/battle_main.c:3240
  if st.link then return true end
  if not st.wild then return false, Strings("No! There's no running\nfrom a TRAINER battle!") end
  if HeldItems.has(battler, HeldItems.HOLD.CAN_ALWAYS_RUN) or adapter:abilityOf(battler) == "RUN_AWAY" then
    return true
  end
  local holder, ab = Abilities.escapeBlocker(adapter, battler)
  if holder then
    return false, Strings("%s prevents\nescape with %s!", adapter:displayName(holder), Abilities.name(ab))
  end
  if battler.expTrapped or battler.escapePrevention or (battler.expTrapTurns or 0) > 0 or battler.expIngrain then
    return false, Strings("Can't escape!")
  end
  return true
end

-- pokefirered/src/battle_main.c:3196
function Engine.canSwitch(st, adapter, battler)
  battler = battler or (st and st.player)
  if not battler then return true end
  if battler.expTrapped or battler.escapePrevention or (battler.expTrapTurns or 0) > 0 or battler.expIngrain then
    return false, Strings("%s can't be switched\nout!", adapter:displayName(battler))
  end
  local holder, ab = Abilities.escapeBlocker(adapter, battler)
  if holder then
    return false, Strings("%s's %s\nprevents switching!", adapter:displayName(holder), Abilities.name(ab))
  end
  return true
end

-- pokefirered/src/battle_main.c:4229
function Engine.tryFlee(st, adapter, battler)
  battler = battler or (st and st.player)
  if not st.wild then
    adapter:say(Strings("No! There's no running\nfrom a TRAINER battle!"))
    return false
  end
  local foe = adapter:foeOf(battler)
  if HeldItems.has(battler, HeldItems.HOLD.CAN_ALWAYS_RUN) then
    adapter:playAnim("general", "SMOKEBALL_ESCAPE", battler, battler)
    adapter:say(Strings("%s fled\nusing its %s!", adapter:displayName(battler), HeldItems.name(HeldItems.itemOf(battler))))
    return true, "item"
  end
  if adapter:abilityOf(battler) == "RUN_AWAY" then
    adapter:say(Strings("%s fled\nusing %s!", adapter:displayName(battler), Abilities.name("RUN_AWAY")))
    return true, "ability"
  end
  if st.ghostBattle and battler.side == "player" then
    adapter:say(Strings("Got away safely!"))
    return true
  end
  local ok = false
  local mySpe = tonumber(battler.mon and battler.mon.speed) or 0
  local foeSpe = tonumber(foe and foe.mon and foe.mon.speed) or 0
  local function vanilla_run(pSpd, eSpd)
    if st.double then
      -- pokefirered/src/battle_main.c:4259
      return false
    elseif pSpd < eSpd then
      local speedVar = (math.floor(pSpd * 128 / math.max(1, eSpd)) + (st.fleeAttempts or 0) * 30) % 256
      return speedVar > roll(adapter, 0, 255)
    end
    return true
  end
  if ModRuntime.wantsHook("battle.run") then
    ok = ModRuntime.call("battle.run", function(c)
      return vanilla_run(c.pSpd, c.eSpd)
    end, { battle = st, pSpd = mySpe, eSpd = foeSpe, attempts = st.fleeAttempts or 0,
           rng = adapter:rng(), battler = battler }) and true or false
  else
    ok = vanilla_run(mySpe, foeSpe)
  end
  st.fleeAttempts = (st.fleeAttempts or 0) + 1
  if ok then
    adapter:say(Strings("Got away safely!"))
    return true
  end
  battler.expDestinyBond, battler.destinyBond, battler.expGrudge, battler.expFuryCutter = nil, nil, nil, 0
  adapter:say(Strings("Can't escape!"))
  return false
end

-- pokefirered/src/battle_script_commands.c:4536
function Engine.switchCandidates(st, side)
  local id = (type(side) == "number") and side or State.idOf(side)
  if type(side) ~= "string" then side = State.sideOf(id) end
  local party = (side == "player") and st.playerParty or st.foeParty
  local excl = {}
  local ids = st.double and State.positionsOnSide(side) or { id }
  for _, bid in ipairs(ids) do
    local b = State.battler(st, bid)
    if b and b.partyIndex then excl[b.partyIndex] = true end
    local pend = st.monToSwitchInto and st.monToSwitchInto[bid]
    if pend and bid ~= id then excl[pend] = true end
  end
  local out = {}
  for i, mon in ipairs(party or {}) do
    if not excl[i] and mon and (tonumber(mon.hp) or 0) > 0 and not mon.isEgg then out[#out + 1] = i end
  end
  return out
end

-- pokefirered/src/party_menu.c:5916
function Engine.replacementCandidates(st, id)
  local side = State.sideOf(id)
  local party = (side == "player") and st.playerParty or st.foeParty
  local excl = {}
  for _, bid in ipairs(st.double and State.positionsOnSide(side) or { id }) do
    local b = State.battler(st, bid)
    if b and b.partyIndex then excl[b.partyIndex] = true end
    local pend = st.monToSwitchInto and st.monToSwitchInto[bid]
    if pend then excl[pend] = true end
  end
  local out = {}
  for i, mon in ipairs(party or {}) do
    if not excl[i] and mon and not mon.isEgg and (tonumber(mon.hp) or 0) > 0
        and (tonumber(mon.species or mon.speciesId) or 0) ~= 0 then
      out[#out + 1] = i
    end
  end
  return out
end

function Engine.faintedBattlers(st)
  local out = {}
  for id = 0, 3 do
    local b = State.battler(st, id)
    if b and not State.isAbsent(st, id) and State.isFainted(b) then out[#out + 1] = id end
  end
  return out
end

-- pokefirered/src/battle_script_commands.c:4870
function Engine.markAbsent(st, id)
  st.absent = st.absent or {}
  st.absent[id] = true
  Engine.cancelPendingAction(st, id)
end

-- pokefirered/src/battle_util.c:1156
function Engine.refreshAbsent(st)
  local back = {}
  if not (st and st.double and st.absent) then return back end
  for id = 0, 3 do
    if st.absent[id] and State.battler(st, id) and #Engine.replacementCandidates(st, id) > 0 then
      st.absent[id] = nil
      back[#back + 1] = id
    end
  end
  return back
end

-- pokefirered/src/battle_util.c:1144
function Engine.pendingReplacements(st)
  local out = {}
  for _, id in ipairs(Engine.faintedBattlers(st)) do
    local cands = Engine.replacementCandidates(st, id)
    out[#out + 1] = { battler = id, side = State.sideOf(id), candidates = cands, noMons = #cands == 0 }
  end
  return out
end

-- pokefirered/src/battle_script_commands.c:3113
function Engine.expAwardOrder(st)
  local out = {}
  for _, id in ipairs(Engine.faintedBattlers(st)) do
    if State.sideOf(id) == "enemy" then out[#out + 1] = id end
  end
  return out
end

local function is_chosen_map(t)
  if type(t) ~= "table" or t.kind ~= nil then return false end
  for id = 0, 3 do
    if t[id] ~= nil then return true end
  end
  return next(t) == nil
end

local function forced_move(b, mv, slot)
  if not b then return mv, slot end
  if b.expLockedMove then return b.expLockedMove, slot end
  if b.expEncoreMove and (b.expEncoreTurns or 0) > 0 then return b.expEncoreMove, slot end
  if b.choicedMove and HeldItems.has(b, HeldItems.HOLD.CHOICE_BAND) and move_num(mv) ~= b.choicedMove
      and move_num(mv) ~= MOVE_STRUGGLE then
    local H = require("src.core.game3.battle.effects._helpers")
    local cs = H.slotOf(b, b.choicedMove)
    if cs and (tonumber(b.mon.pp and b.mon.pp[cs]) or 1) > 0 then return b.mon.moves[cs], cs end
  end
  return mv, slot
end

local function is_meta_first(kind) return kind == "bag" or kind == "switch" or kind == "item" end

local function order_hook(st, adapter, a, aMove, b, bMove, vanilla)
  local G3 = require("src.mods.Gen3Compat")
  return ModRuntime.call("battle.turn_order", function()
    return vanilla()
  end, a, aMove and G3.moveView(aMove) or nil, b, bMove and G3.moveView(bMove) or nil,
  { battle = st, rng = adapter:rng(), playerMove = aMove and G3.moveName(move_num(aMove)),
    enemyMove = bMove and G3.moveName(move_num(bMove)),
    firstId = State.idOf(a), secondId = State.idOf(b) }) and true or false
end

-- pokefirered/src/battle_main.c:3532
function Engine.planTurnActions(st, adapter, chosen)
  chosen = chosen or {}
  st.chosen = chosen
  st.monToSwitchInto = st.monToSwitchInto or {}
  for id = 0, 3 do clear_turn_flags(State.battler(st, id)) end
  Engine.refreshLinks(st)
  if st.playerSide then st.playerSide.expFollowMe, st.playerSide.expFollowMeId = nil, nil end
  if st.enemySide then st.enemySide.expFollowMe, st.enemySide.expFollowMeId = nil, nil end
  local rows = {}
  for id = 0, 3 do
    local act = chosen[id]
    local b = State.battler(st, id)
    if b and State.isAbsent(st, id) then
      -- pokefirered/src/battle_main.c:3115
      rows[id] = { battler = id, user = b, kind = "nothing", finished = true }
    elseif act and b then
      local row = {}
      for k, v in pairs(act) do row[k] = v end
      row.battler = id
      row.user = b
      row.kind = act.kind or "move"
      if row.kind == "move" then
        row.move, row.slot = forced_move(b, act.move, act.slot)
        local mv = Moves.get(row.move)
        row.targetType = tonumber(mv and mv.target) or 0
      end
      rows[id] = row
    end
  end
  -- pokefirered/src/battle_util.c:1223
  for id, row in pairs(rows) do
    local b = row.user
    local mv = b.expLockedMove or (row.kind == "move" and row.move) or nil
    if b.rage and move_num(mv) ~= 99 then b.rage = nil end
  end
  local order = {}
  local sortable = 0
  -- pokefirered/src/battle_controllers.c:163 the non-master owns the odd battler ids
  local ids = link_seat_swap(st) and { 1, 0, 3, 2 } or { 0, 1, 2, 3 }
  if rows[0] and rows[0].kind == "run" then
    order[1] = 0
    for id = 1, 3 do if rows[id] then order[#order + 1] = id end end
  else
    for _, id in ipairs(ids) do
      if rows[id] and is_meta_first(rows[id].kind) then order[#order + 1] = id end
    end
    for _, id in ipairs(ids) do
      if rows[id] and not is_meta_first(rows[id].kind) then
        order[#order + 1] = id
        sortable = sortable + 1
      end
    end
  end
  if sortable >= 2 then
    -- pokefirered/src/battle_main.c:2926
    st.randomTurnNumber = roll(adapter, 0, 0xFFFF)
    for i = 1, #order - 1 do
      for j = i + 1, #order do
        local r1, r2 = rows[order[i]], rows[order[j]]
        if not is_meta_first(r1.kind) and not is_meta_first(r2.kind) then
          local p1 = r1.kind == "move" and Moves.priority(r1.move) or 0
          local p2 = r2.kind == "move" and Moves.priority(r2.move) or 0
          local s1 = speed_of(r1.user, st, adapter)
          local s2 = speed_of(r2.user, st, adapter)
          local function vanilla_swap()
            -- pokefirered/src/battle_main.c:3505
            if p1 ~= p2 then
              return p1 < p2
            elseif s1 == s2 then
              return roll(adapter, 0, 1) == 1
            end
            return s1 < s2
          end
          local swap
          if ModRuntime.wantsHook("battle.turn_order") then
            swap = not order_hook(st, adapter, r1.user, r1.kind == "move" and r1.move or nil,
              r2.user, r2.kind == "move" and r2.move or nil,
              function() return not vanilla_swap() end)
          else
            swap = vanilla_swap()
          end
          if swap then order[i], order[j] = order[j], order[i] end
        end
      end
    end
  end
  -- pokefirered/src/battle_main.c:3669
  local focus = {}
  for id = 0, 3 do
    local row = rows[id]
    if row and row.kind == "move" then
      local mv = Moves.get(row.move)
      if tonumber(mv and mv.effect) == E.FOCUS_PUNCH and not row.user.expLockedMove
          and not adapter:hasStatus(row.user, "SLP") then
        focus[#focus + 1] = row.user
      end
    end
  end
  st._focusPunchSetup = (#focus > 0) and focus or nil
  local actions = {}
  for i, id in ipairs(order) do
    rows[id].user.expTurnOrder = i
    actions[i] = rows[id]
  end
  st.turnOrder = order
  st.turnActions = actions
  return actions, nil
end

function Engine.planTurnFromActions(st, adapter, playerAct, enemyAct)
  if is_chosen_map(playerAct) and enemyAct == nil then
    return Engine.planTurnActions(st, adapter, playerAct)
  end
  if st and st.double then
    return Engine.planTurnActions(st, adapter, {
      [0] = playerAct or Commands.playerAction(st, 1, 1),
      [1] = enemyAct or Commands.enemyAction(st, 1),
    })
  end
  playerAct = playerAct or Commands.playerAction(st, 1, 1)
  enemyAct = enemyAct or Commands.enemyAction(st)

  clear_turn_flags(st.player)
  clear_turn_flags(st.enemy)
  Engine.refreshLinks(st)
  if st.playerSide then st.playerSide.expFollowMe = nil end
  if st.enemySide then st.enemySide.expFollowMe = nil end

  -- pokefirered/src/battle_util.c:1223
  local function chosen(b, act)
    if not b then return nil end
    if b.expLockedMove then return b.expLockedMove end
    return act and act.kind == "move" and act.move or nil
  end
  local pChosen = chosen(st.player, playerAct)
  local eChosen = chosen(st.enemy, enemyAct)
  if st.player and st.player.rage and move_num(pChosen) ~= 99 then st.player.rage = nil end
  if st.enemy and st.enemy.rage and move_num(eChosen) ~= 99 then st.enemy.rage = nil end

  local actions = {}
  local enemyMeta = enemyAct.kind == "switch" or enemyAct.kind == "item"
  local function enemy_meta_row()
    local row = {}
    for k, v in pairs(enemyAct) do row[k] = v end
    row.user, row.battler = st.enemy, 1
    return row
  end
  -- pokefirered/src/battle_main.c:3537
  if st.safari then
    if st.player then st.player.expTurnOrder = 1 end
    if st.enemy then st.enemy.expTurnOrder = 2 end
    -- pokefirered/src/battle_controller_opponent.c:1364
    actions[#actions + 1] = {
      user = st.enemy, battler = 1,
      kind = (enemyAct.kind == "run") and "run" or "watch",
    }
    st.turnOrder = { 0, 1 }
    st.turnActions = actions
    return actions, playerAct
  end
  if playerAct.kind == "run" or playerAct.kind == "bag" or playerAct.kind == "switch" then
    if st.player then st.player.expTurnOrder = 1 end
    if enemyMeta then
      -- pokefirered/src/battle_main.c:3586
      if st.enemy then st.enemy.expTurnOrder = 2 end
      actions[#actions + 1] = enemy_meta_row()
    elseif enemyAct.kind == "move" then
      if st.enemy then st.enemy.expTurnOrder = 2 end
      actions[#actions + 1] = {
        user = st.enemy, target = st.player,
        move = enemyAct.move, slot = enemyAct.slot,
        battler = 1, kind = "move",
      }
    end
    st.turnOrder = { 0, 1 }
    st.turnActions = actions
    return actions, playerAct
  end

  local pMove, pSlot = playerAct.move, playerAct.slot
  if enemyMeta then
    -- pokefirered/src/battle_main.c:3586
    pMove, pSlot = forced_move(st.player, pMove, pSlot)
    if st.enemy then st.enemy.expTurnOrder = 1 end
    if st.player then st.player.expTurnOrder = 2 end
    actions[1] = enemy_meta_row()
    actions[2] = { user = st.player, target = st.enemy, move = pMove, slot = pSlot, battler = 0, kind = "move" }
    local mv = Moves.get(pMove)
    st._focusPunchSetup = nil
    if tonumber(mv and mv.effect) == E.FOCUS_PUNCH and not st.player.expLockedMove
        and not adapter:hasStatus(st.player, "SLP") then
      st._focusPunchSetup = { st.player }
    end
    st.turnOrder = { 1, 0 }
    st.turnActions = actions
    return actions, nil
  end
  local eMove, eSlot = enemyAct.move, enemyAct.slot
  local function forced(b, mv, slot)
    if not b then return mv, slot end
    if b.expLockedMove then return b.expLockedMove, slot end
    if b.expEncoreMove and (b.expEncoreTurns or 0) > 0 then return b.expEncoreMove, slot end
    if b.choicedMove and HeldItems.has(b, HeldItems.HOLD.CHOICE_BAND) and move_num(mv) ~= b.choicedMove
        and move_num(mv) ~= MOVE_STRUGGLE then
      local H = require("src.core.game3.battle.effects._helpers")
      local cs = H.slotOf(b, b.choicedMove)
      if cs and (tonumber(b.mon.pp and b.mon.pp[cs]) or 1) > 0 then return b.mon.moves[cs], cs end
    end
    return mv, slot
  end
  pMove, pSlot = forced(st.player, pMove, pSlot)
  eMove, eSlot = forced(st.enemy, eMove, eSlot)
  -- pokefirered/src/battle_main.c:2926
  st.randomTurnNumber = roll(adapter, 0, 0xFFFF)
  local pPri = Moves.priority(pMove)
  local ePri = Moves.priority(eMove)
  local pSpe = speed_of(st.player, st, adapter)
  local eSpe = speed_of(st.enemy, st, adapter)
  -- pokefirered/src/battle_main.c:3400
  local function vanilla_first()
    if pPri ~= ePri then
      return pPri > ePri
    elseif pSpe ~= eSpe then
      return pSpe > eSpe
    end
    -- pokefirered/src/battle_controllers.c:163 the non-master reads battler1/battler2 swapped
    return (roll(adapter, 0, 1) == 1) == link_seat_swap(st)
  end
  local playerFirst
  if ModRuntime.wantsHook("battle.turn_order") then
    playerFirst = order_hook(st, adapter, st.player, pMove, st.enemy, eMove, vanilla_first)
  else
    playerFirst = vanilla_first()
  end
  -- pokefirered/src/battle_main.c:3682
  local focus = {}
  for _, row in ipairs({ { st.player, pMove }, { st.enemy, eMove } }) do
    local mv = Moves.get(row[2])
    if tonumber(mv and mv.effect) == E.FOCUS_PUNCH and not row[1].expLockedMove
        and not adapter:hasStatus(row[1], "SLP") then
      focus[#focus + 1] = row[1]
    end
  end
  st._focusPunchSetup = (#focus > 0) and focus or nil
  if playerFirst then
    st.player.expTurnOrder, st.enemy.expTurnOrder = 1, 2
    actions[#actions + 1] = { user = st.player, target = st.enemy, move = pMove, slot = pSlot, battler = 0, kind = "move" }
    actions[#actions + 1] = { user = st.enemy, target = st.player, move = eMove, slot = eSlot, battler = 1, kind = "move" }
    st.turnOrder = { 0, 1 }
  else
    st.player.expTurnOrder, st.enemy.expTurnOrder = 2, 1
    actions[#actions + 1] = { user = st.enemy, target = st.player, move = eMove, slot = eSlot, battler = 1, kind = "move" }
    actions[#actions + 1] = { user = st.player, target = st.enemy, move = pMove, slot = pSlot, battler = 0, kind = "move" }
    st.turnOrder = { 1, 0 }
  end
  st.turnActions = actions
  return actions, nil
end

function Engine.planTurn(st, adapter)
  return Engine.planTurnFromActions(st, adapter, nil, nil)
end

function Engine.collectResidualEvents(_st, adapter)
  return Residuals.collectEvents(adapter)
end

function Engine.hasLivingMons(party)
  if not party then return false end
  for _, mon in ipairs(party) do
    if mon and (tonumber(mon.hp) or 0) > 0 then
      return true
    end
  end
  return false
end

function Engine.nextLivingMonIndex(party, currentIdx)
  if not party then return nil end
  for i, mon in ipairs(party) do
    if i ~= currentIdx and mon and (tonumber(mon.hp) or 0) > 0 then
      return i
    end
  end
  return nil
end

function Engine.isPursuit(move)
  if not move then return false end
  if type(move) == "string" and move:upper() == "PURSUIT" then return true end
  if type(move) == "number" and move == 228 then return true end
  if type(move) == "table" and (move.id == 228 or move.effect == 128 or (move.name and move.name:upper() == "PURSUIT")) then
    return true
  end
  return false
end

function Engine.checkEnd(st, adapter)
  if not st then return nil end
  if st.over then return st.result end

  if st.player and st.playerParty then
    State.syncBattlerToParty(st.player, st.playerParty)
  end
  if st.enemy and st.foeParty then
    State.syncBattlerToParty(st.enemy, st.foeParty)
  end
  if st.double then
    local b2, b3 = State.battler(st, 2), State.battler(st, 3)
    if b2 and st.playerParty then State.syncBattlerToParty(b2, st.playerParty) end
    if b3 and st.foeParty then State.syncBattlerToParty(b3, st.foeParty) end
  end

  local playerAlive = Engine.hasLivingMons(st.playerParty)
  if not playerAlive then
    st.over = true
    st.result = "lose"
    return "lose"
  end

  local foeAlive = Engine.hasLivingMons(st.foeParty)
  if not foeAlive then
    st.over = true
    st.result = "win"
    return "win"
  end

  return nil
end

return Engine
