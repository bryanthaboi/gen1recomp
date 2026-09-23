-- Owned residual handlers (game3 owns status/weather/volatiles — not host).

local Residuals = require("src.core.game3.battle.residuals")
local Rules = require("src.core.game3.battle.rules")
local StatusChip = require("src.core.game3.battle.status")
local Moves = require("src.core.game3.battle.moves")

local Handlers = {}
Handlers._installed = false

local function side_battler(ad, sideKey)
  local st = ad._st
  return sideKey == "player" and st.player or st.enemy
end

local function slot_battler(ad, id)
  local State = require("src.core.game3.battle.state")
  if id == nil or not State.isPresent(ad._st, id) then return nil end
  return State.battler(ad._st, id)
end

local function token_battler(ad, key, tok, field)
  if ad._st.double and tok[field] ~= nil then return slot_battler(ad, tok[field]) end
  return side_battler(ad, key)
end

-- data/battle_scripts_1.s:3533
local function wish_heal(ad, tok, b)
  local State = require("src.core.game3.battle.state")
  -- src/battle_script_commands.c:8916
  ad:sayText("STRINGID_PKMNWISHCAMETRUE", { buff1 = State.prefixedName(ad._st, b, tok.wisher) })
  if ad:hp(b) >= ad:maxHp(b) then
    ad:sayText("STRINGID_PKMNHPFULL", { def = b })
  else
    local heal = math.floor(ad:maxHp(b) / 2)
    if heal == 0 then heal = 1 end
    ad:heal(b, heal)
    ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = b })
  end
end

-- pokefirered/src/battle_util.c:505
local function side_timer(field, move)
  return function(ctx)
    local ad = ctx.adapter
    for _, key in ipairs({ "player", "enemy" }) do
      local side = key == "player" and ad._st.playerSide or ad._st.enemySide
      if side and (side[field] or 0) > 0 then
        side[field] = side[field] - 1
        if side[field] <= 0 then
          side[field] = nil
          if field == "expSafeguardTurns" then
            ad:sayText("STRINGID_PKMNSAFEGUARDEXPIRED", { atk = key })
          else
            ad:sayText("STRINGID_PKMNSXWOREOFF", { atk = key, buff1 = Moves.displayName(move) })
          end
        end
      end
    end
  end
end

-- pokefirered/src/battle_util.c:624
function Handlers.tickWeather(ad)
  local st = ad._st
  local kind = Rules.weather.kind(st.weather)
  if not kind then return end
  local turns = tonumber(st.weatherTurns) or 0
  local ended = false
  if turns > 0 then
    st.weatherTurns = turns - 1
    ended = st.weatherTurns <= 0
  end
  if kind == "RAIN" then
    if ended then
      ad:sayText("STRINGID_RAINSTOPPED")
      st.weather = nil
    else
      ad:sayText("STRINGID_RAINCONTINUES")
      ad:playAnim("general", "RAIN_CONTINUES", nil, nil)
    end
    return
  end
  if kind == "SUN" then
    if ended then
      ad:sayText("STRINGID_SUNLIGHTFADED")
      st.weather = nil
    else
      ad:sayText("STRINGID_SUNLIGHTSTRONG")
      ad:playAnim("general", "SUN_CONTINUES", nil, nil)
    end
    return
  end
  if ended then
    ad:sayText(kind == "SAND" and "STRINGID_SANDSTORMSUBSIDED" or "STRINGID_HAILSTOPPED")
    st.weather = nil
    return
  end
  ad:sayText(kind == "SAND" and "STRINGID_SANDSTORMRAGES" or "STRINGID_HAILCONTINUES")
  ad:playAnim("general", kind == "SAND" and "SANDSTORM_CONTINUES" or "HAIL_CONTINUES", nil, nil)
  if not Rules.weather.effective(st, ad) then return end
  local order = Residuals.sortedBattlers(ad)
  for _, b in ipairs(order) do
    if not ad:isFainted(b) then
      local immune
      local semiHidden = b.semiInvulnerable == "UNDERGROUND" or b.semiInvulnerable == "UNDERWATER"
      if kind == "SAND" then
        immune = ad:hasType(b, 5) or ad:hasType(b, 8) or ad:hasType(b, 4)
          or ad:abilityOf(b) == "SAND_VEIL" or semiHidden
      else
        immune = ad:hasType(b, 15) or semiHidden
      end
      -- pokefirered/src/battle_script_commands.c:7218
      if st.ghostBattle and not st.ghostUnveiled and b.side == "enemy" then immune = true end
      if not immune then
        -- pokefirered/src/battle_script_commands.c:7216
        local dmg = Rules.weather.chipAmount(ad:maxHp(b))
        if kind == "SAND" then
          ad:sayText("STRINGID_PKMNBUFFETEDBYSANDSTORM", { atk = b })
        else
          ad:sayText("STRINGID_PKMNPELTEDBYHAIL", { atk = b })
        end
        ad:applyHpLoss(b, dmg)
        if ad:isFainted(b) then
          b._faintAnnounced = true
          ad:pushEvent({ kind = "faint", side = b.side, battler = b.id })
          ad:sayText("STRINGID_ATTACKERFAINTED", { atk = b })
          ad:emitFaint(b)
        end
      end
    end
  end
end

function Handlers.registerAll()
  if Handlers._installed then return end
  Handlers._installed = true

  -- src/battle_util.c:516
  Residuals.register("reflect", side_timer("expReflectTurns", 115))
  Residuals.register("light_screen", side_timer("expLightScreenTurns", 113))
  Residuals.register("mist", side_timer("expMistTurns", 54))
  Residuals.register("safeguard", side_timer("expSafeguardTurns", 219))

  -- pokefirered/src/battle_util.c:603
  Residuals.register("wish", function(ctx)
    local ad = ctx.adapter
    if ad._st.double then return Handlers.wishDoubles(ad) end
    for _, key in ipairs({ "player", "enemy" }) do
      local side = key == "player" and ad._st.playerSide or ad._st.enemySide
      if side and side.tokens then
        local keep = {}
        for _, tok in ipairs(side.tokens) do
          if tok.id == "EXP_WISH" then
            tok.turns = (tok.turns or 1) - 1
            local b = side_battler(ad, key)
            if tok.turns <= 0 then
              if b and ad:hp(b) > 0 then
                ad:playAnim("general", "WISH_HEAL", b, b)
                wish_heal(ad, tok, b)
              end
            else
              keep[#keep + 1] = tok
            end
          else
            keep[#keep + 1] = tok
          end
        end
        side.tokens = keep
      end
    end
  end)

  -- pokefirered/src/battle_util.c:603
  function Handlers.wishDoubles(ad)
    local st = ad._st
    for _, b0 in ipairs(Residuals.sortedBattlers(ad)) do
      local id = b0.id
      local side = (id % 2 == 0) and st.playerSide or st.enemySide
      if side and side.tokens then
        local keep = {}
        for _, tok in ipairs(side.tokens) do
          if tok.id == "EXP_WISH" and (tok.battlerId == nil or tok.battlerId == id) then
            tok.turns = (tok.turns or 1) - 1
            if tok.turns <= 0 then
              local b = slot_battler(ad, id)
              if b and ad:hp(b) > 0 then
                ad:playAnim("general", "WISH_HEAL", b, b)
                wish_heal(ad, tok, b)
              end
            else
              keep[#keep + 1] = tok
            end
          else
            keep[#keep + 1] = tok
          end
        end
        side.tokens = keep
      end
    end
  end

  Residuals.register("weather_continue", function(ctx)
    Handlers.tickWeather(ctx.adapter)
  end)

  -- pokefirered/src/battle_util.c:760
  Residuals.register("ingrain", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or not b.expIngrain then return end
    local maxHp, cur = ad:maxHp(b), ad:hp(b)
    if cur <= 0 or cur >= maxHp then return end
    local heal = math.floor(maxHp / 16)
    if heal == 0 then heal = 1 end
    ad:playAnim("general", "INGRAIN_HEAL", b, b)
    ad:sayText("STRINGID_PKMNABSORBEDNUTRIENTS", { atk = b })
    ad:heal(b, heal)
  end)

  -- pokefirered/src/battle_util.c:774
  Residuals.register("abilities_eot", function(ctx)
    local Abilities = require("src.core.game3.battle.abilities")
    Abilities.endTurn(ctx.adapter, ctx.target)
  end)

  -- pokefirered/src/battle_util.c:779
  Residuals.register("held_items", function(ctx)
    local HeldItems = require("src.core.game3.battle.held_items")
    HeldItems.normal(ctx.adapter, ctx.target, false)
    HeldItems.normal(ctx.adapter, ctx.target, true)
  end)

  -- pokefirered/src/battle_util.c:1208
  Residuals.register("fainted_actions", function(ctx)
    local Engine = require("src.core.game3.battle.engine")
    Engine.afterAction(ctx.adapter._st, ctx.adapter)
  end)

  -- pokefirered/src/battle_util.c:789
  Residuals.register("leech_seed", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or not b.expSeeded then return end
    local src = b.expSeedSource
    if src and ad._st.double then
      src = slot_battler(ad, src.id)
    elseif src and src.side then
      src = side_battler(ad, src.side)
    end
    if not src or ad:isFainted(src) or ad:isFainted(b) then return end
    local dmg = math.floor(ad:maxHp(b) / 8)
    if dmg == 0 then dmg = 1 end
    ad:playAnim("general", "LEECH_SEED_DRAIN", b, src)
    local dealt = ad:applyHpLoss(b, dmg)
    if ad:abilityOf(b) == "LIQUID_OOZE" then
      ad:applyHpLoss(src, dealt)
      ad:sayText("STRINGID_ITSUCKEDLIQUIDOOZE")
    else
      ad:heal(src, dealt)
      ad:sayText("STRINGID_PKMNSAPPEDBYLEECHSEED", { atk = b })
    end
  end)

  Residuals.register("status_chip", function(ctx)
    local b = ctx.target
    if not b then return end
    StatusChip.tickChip(b, ctx.adapter)
  end)

  -- pokefirered/src/battle_util.c:841
  Residuals.register("nightmare", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or not b.expNightmare or ad:hp(b) <= 0 then return end
    if not ad:hasStatus(b, "SLP") then
      b.expNightmare = nil
      return
    end
    local dmg = math.floor(ad:maxHp(b) / 4)
    if dmg == 0 then dmg = 1 end
    ad:sayText("STRINGID_PKMNLOCKEDINNIGHTMARE", { atk = b })
    ad:playAnim("status", "NIGHTMARE", b, b)
    ad:applyHpLoss(b, dmg)
  end)

  -- pokefirered/src/battle_util.c:861
  Residuals.register("curse", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or not b.expCursed or ad:hp(b) <= 0 then return end
    local dmg = math.floor(ad:maxHp(b) / 4)
    if dmg == 0 then dmg = 1 end
    ad:sayText("STRINGID_PKMNAFFLICTEDBYCURSE", { atk = b })
    ad:playAnim("status", "CURSED", b, b)
    ad:applyHpLoss(b, dmg)
  end)

  -- pokefirered/src/battle_util.c:872
  Residuals.register("partial_trap_chip", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or not b.expTrapTurns or ad:hp(b) <= 0 then return end
    local R = package.loaded["src.core.game3.battle.rules"] or Rules
    if R.partialTrap and R.partialTrap.active and not R.partialTrap.active() then return end
    b.expTrapTurns = b.expTrapTurns - 1
    -- src/battle_util.c:882
    local moveName = Moves.displayName(b.expTrapMove)
    if b.expTrapTurns > 0 then
      ad:playAnim("general", "TURN_TRAP", b, b, b.expTrapMove)
      ad:sayText("STRINGID_PKMNHURTBY", { atk = b, buff1 = moveName })
      local chip = (R.partialTrap and R.partialTrap.chipAmount and R.partialTrap.chipAmount(ad:maxHp(b))) or math.max(1, math.floor(ad:maxHp(b) / 16))
      ad:applyHpLoss(b, chip)
    else
      b.expTrapTurns = nil
      b.expTrapMove = nil
      b.expTrapSource = nil
      b.wrapped = nil
      ad:sayText("STRINGID_PKMNFREEDFROM", { atk = b, buff1 = moveName })
    end
  end)

  -- pokefirered/src/battle_util.c:904
  Residuals.register("uproar", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or (b.expUproarTurns or 0) <= 0 then return end
    local Engine = require("src.core.game3.battle.engine")
    for _, other in ipairs(ad:activeBattlers()) do
      if ad:hasStatus(other, "SLP") and ad:abilityOf(other) ~= "SOUNDPROOF" then
        ad:clearStatus(other)
        other.expNightmare = nil
        ad:sayText("STRINGID_PKMNWOKEUPINUPROAR", { atk = other })
      end
    end
    b.expUproarTurns = b.expUproarTurns - 1
    if b.expUnableToMove then
      Engine.cancelMultiTurnMoves(b)
      ad:sayText("STRINGID_PKMNCALMEDDOWN", { atk = b })
    elseif b.expUproarTurns > 0 then
      ad:sayText("STRINGID_PKMNMAKINGUPROAR", { atk = b })
    else
      Engine.cancelMultiTurnMoves(b)
      ad:sayText("STRINGID_PKMNCALMEDDOWN", { atk = b })
    end
  end)

  -- pokefirered/src/battle_util.c:953
  Residuals.register("thrash", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or (b.expRampageTurns or 0) <= 0 then return end
    local Engine = require("src.core.game3.battle.engine")
    b.expRampageTurns = b.expRampageTurns - 1
    if b.expUnableToMove then
      Engine.cancelMultiTurnMoves(b)
    elseif b.expRampageTurns <= 0 and b.expLockedMove then
      b.expLockedMove = nil
      b.expLockedSlot = nil
      b.expRampageTurns = nil
      if (b.confusionTurns or 0) <= 0 and ad:abilityOf(b) ~= "OWN_TEMPO" then
        b.confusionTurns = ad:roll(0, 3) % 4 + 2
        ad:playAnim("status", "CONFUSION", b, b)
        ad:sayText("STRINGID_PKMNFATIGUECONFUSION", { atk = b })
      end
    end
  end)

  -- pokefirered/src/battle_util.c:975
  Residuals.register("disable", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or not b.expDisabledMove then return end
    local known = false
    local mon = b.mon or {}
    local H = require("src.core.game3.battle.effects._helpers")
    for i = 1, 4 do
      if H.moveNum(mon.moves and mon.moves[i]) == b.expDisabledMove then known = true end
    end
    if not known then
      b.expDisabledMove, b.expDisableTurns, b.disabled = nil, nil, nil
      return
    end
    b.expDisableTurns = (b.expDisableTurns or 1) - 1
    if b.expDisableTurns <= 0 then
      b.expDisabledMove, b.expDisableTurns, b.disabled = nil, nil, nil
      ad:sayText("STRINGID_PKMNMOVEDISABLEDNOMORE", { atk = b })
    end
  end)

  -- pokefirered/src/battle_util.c:998
  Residuals.register("encore", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or (b.expEncoreTurns or 0) <= 0 then return end
    local H = require("src.core.game3.battle.effects._helpers")
    local mon = b.mon or {}
    local slot = b.expEncoreSlot or H.slotOf(b, b.expEncoreMove)
    if not slot or H.moveNum(mon.moves and mon.moves[slot]) ~= H.moveNum(b.expEncoreMove) then
      b.expEncoreMove, b.expEncoreTurns, b.expEncoreSlot = nil, nil, nil
      return
    end
    b.expEncoreTurns = b.expEncoreTurns - 1
    if b.expEncoreTurns <= 0 or (tonumber(mon.pp and mon.pp[slot]) or 0) <= 0 then
      b.expEncoreMove, b.expEncoreTurns, b.expEncoreSlot = nil, nil, nil
      ad:sayText("STRINGID_PKMNENCOREENDED", { atk = b })
    end
  end)

  Residuals.register("lock_on", function(ctx)
    local b = ctx.target
    if b and tonumber(b.expLockedOn) and b.expLockedOn > 0 then
      b.expLockedOn = b.expLockedOn - 1
      if b.expLockedOn <= 0 then b.expLockedOn = nil; b.expLockedOnBy = nil end
    elseif b and b.expLockedOn == true then
      b.expLockedOn = 1
    end
  end)

  Residuals.register("charge", function(ctx)
    local b = ctx.target
    if b and tonumber(b.expCharged) then
      b.expCharged = b.expCharged - 1
      if b.expCharged <= 0 then b.expCharged = nil; b.chargedUp = nil end
    end
  end)

  Residuals.register("taunt", function(ctx)
    local b = ctx.target
    if b and (b.expTauntedTurns or 0) > 0 then
      b.expTauntedTurns = b.expTauntedTurns - 1
      if b.expTauntedTurns <= 0 then b.expTauntedTurns = nil end
    end
  end)

  -- pokefirered/src/battle_util.c:1032
  Residuals.register("yawn", function(ctx)
    local ad, b = ctx.adapter, ctx.target
    if not b or (b.expYawnTurns or 0) <= 0 then return end
    b.expYawnTurns = b.expYawnTurns - 1
    b.yawnTurns = b.expYawnTurns > 0 and b.expYawnTurns or nil
    if b.expYawnTurns > 0 then return end
    b.expYawnTurns = nil
    local ab = ad:abilityOf(b)
    if ad:status(b) or ab == "VITAL_SPIRIT" or ab == "INSOMNIA" then return end
    if ad:uproarActive() and ab ~= "SOUNDPROOF" then return end
    local Engine = require("src.core.game3.battle.engine")
    Engine.cancelMultiTurnMoves(b)
    ad:applyStatus(b, "SLP", b, { force = true, ignoreSafeguard = true })
    ad:statusAnim(b, "SLP")
    ad:sayText("STRINGID_PKMNFELLASLEEP", { eff = b })
  end)

  Residuals.register("volatiles", function(ctx)
    local b = ctx.target
    if not b then return end
    b.expJustEntered = nil
    b.expUnableToMove = nil
  end)

  -- pokefirered/src/battle_util.c:1081
  Residuals.register("future_sight", function(ctx)
    local ad = ctx.adapter
    if ad._st.double then return Handlers.futureSightDoubles(ad) end
    for _, key in ipairs({ "player", "enemy" }) do
      local side = key == "player" and ad._st.playerSide or ad._st.enemySide
      if side and side.tokens then
        local keep = {}
        for _, tok in ipairs(side.tokens) do
          local target = token_battler(ad, key, tok, "targetId")
          if tok.id == "EXP_FUTURE_SIGHT" then
            tok.turns = (tok.turns or 1) - 1
            if tok.turns <= 0 then
              if target and ad:hp(target) > 0 then
                Handlers.futureSightHit(ad, tok, target)
              end
            else
              keep[#keep + 1] = tok
            end
          else
            keep[#keep + 1] = tok
          end
        end
        side.tokens = keep
      end
    end
  end)

  -- pokefirered/src/battle_util.c:1116
  Residuals.register("perish_song", function(ctx)
    local ad = ctx.adapter
    for _, b in ipairs(Residuals.sortedBattlers(ad)) do
      if b.expPerishTurns and ad:hp(b) > 0 then
        local n = b.expPerishTurns
        -- src/battle_util.c:1118
        ad:sayText("STRINGID_PKMNPERISHCOUNTFELL", { atk = b, buff1 = tostring(n) })
        if n <= 0 then
          b.expPerishTurns = nil
          b.perishSong = nil
          ad:applyHpLoss(b, ad:hp(b))
        else
          b.expPerishTurns = n - 1
        end
      end
    end
  end)
end

-- pokefirered/src/battle_util.c:1081
function Handlers.futureSightDoubles(ad)
  local st = ad._st
  for id = 0, 3 do
    local side = (id % 2 == 0) and st.playerSide or st.enemySide
    if side and side.tokens then
      local keep = {}
      for _, tok in ipairs(side.tokens) do
        local tid = tok.targetId or ((id % 2 == 0) and 0 or 1)
        if tok.id == "EXP_FUTURE_SIGHT" and tid == id then
          tok.turns = (tok.turns or 1) - 1
          if tok.turns <= 0 then
            local target = slot_battler(ad, id)
            if target and ad:hp(target) > 0 then Handlers.futureSightHit(ad, tok, target) end
          else
            keep[#keep + 1] = tok
          end
        else
          keep[#keep + 1] = tok
        end
      end
      side.tokens = keep
    end
  end
end

-- pokefirered/data/battle_scripts_1.s:3461
function Handlers.futureSightHit(ad, tok, target)
  local Engine = require("src.core.game3.battle.engine")
  local attacker = side_battler(ad, tok.attackerSide or (target.side == "player" and "enemy" or "player"))
  if ad._st.double and tok.attackerId ~= nil then
    local State = require("src.core.game3.battle.state")
    attacker = State.battler(ad._st, tok.attackerId) or attacker
  end
  ad:sayText("STRINGID_PKMNTOOKATTACK", { def = target, buff1 = Moves.displayName(tok.moveId or 248) })
  local anim = { moveId = tok.moveId, user = attacker, target = target, hits = {}, heals = {}, faints = {} }
  local M = Engine.newContext(attacker, target, tok.moveId or 248, nil, ad, ad._st, {}, anim, { futureSight = true })
  local Moves = require("src.core.game3.battle.moves")
  M.accOverride = tonumber(Moves.get(tok.moveId or 248).accuracy) or 90
  if not M:accuracyCheck("normal", false) then
    ad:sayFail()
    return
  end
  local dmg = tonumber(tok.damage) or 1
  local r = ad:roll(85, 100)
  dmg = math.floor(dmg * r / 100)
  if dmg == 0 then dmg = 1 end
  local Hit = require("src.core.game3.battle.effects.hit")
  local hung
  dmg, hung = Hit.adjustDamage(M, target, dmg)
  ad:playAnim("general", tok.doomDesire and "DOOM_DESIRE_HIT" or "FUTURE_SIGHT_HIT", attacker, target)
  Hit.dealDamage(M, dmg, { physical = false })
  if hung == "endured" then
    ad:sayText("STRINGID_PKMNENDUREDHIT", { def = target })
  elseif hung == "hung" then
    require("src.core.game3.battle.held_items").focusBandMessage(ad, target)
  end
end

return Handlers
