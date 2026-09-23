local H = require("src.core.game3.battle.effects._helpers")
local Types = require("src.core.game3.battle.types")
local Secondary = require("src.core.game3.battle.effects.secondary")
local Strings = require("src.core.Strings")

local Special = {}

local function name(ctx, b) return ctx.adapter:displayName(b) end

local function engine() return require("src.core.game3.battle.engine") end
local function state() return require("src.core.game3.battle.state") end
local function moves() return require("src.core.game3.battle.moves") end

local function end_battle(ctx, reason)
  local st = ctx.adapter._st
  st.over = true
  st.result = "run"
  st.endReason = reason
  ctx.adapter:pushEvent({ kind = "end", result = "run", reason = reason })
end

local function sent_out_text(ctx, battler)
  local st = ctx.adapter._st
  if battler.side == "player" then
    return Strings("Go! %s!", name(ctx, battler))
  end
  local trainer = tostring(st.trainerName or "TRAINER")
  if st.trainerClassName and st.trainerClassName ~= "" then
    return Strings("%s %s sent\nout %s!", st.trainerClassName, trainer, name(ctx, battler))
  end
  return Strings("%s sent\nout %s!", trainer, name(ctx, battler))
end

-- pokefirered/src/battle_script_commands.c:6905
function Special.roar(ctx)
  local ad, user, target = ctx.adapter, ctx.user, ctx.target
  local st = ad._st
  if ad:abilityOf(target) == "SUCTION_CUPS" then
    return ad:say(Strings("%s anchors\nitself with SUCTION CUPS!", name(ctx, target)))
  end
  if target.expIngrain then
    return ad:say(Strings("%s anchored\nitself with its roots!", name(ctx, target)))
  end
  if not H.accuracy(ctx, "lockon") then return end
  if not H.accuracy(ctx, "normal") then return end
  local candidates = engine().switchCandidates(st, st.double and target.id or target.side)
  if not st.wild and #candidates < 1 then return H.sayFail(ctx) end
  local uLvl = tonumber(user.mon and user.mon.level) or 1
  local tLvl = tonumber(target.mon and target.mon.level) or 1
  if uLvl < tLvl then
    local r = ad:roll(0, 255)
    if math.floor(r * (uLvl + tLvl) / 256) + 1 <= math.floor(tLvl / 4) then
      return H.sayFail(ctx)
    end
  end
  H.attackAnim(ctx)
  if st.wild then
    -- pokefirered/data/battle_scripts_1.s:3283
    ad:pushEvent({ kind = "switch_out", side = target.side, reason = "roar" })
    end_battle(ctx, "roar")
    return
  end
  local slot = candidates[ad:roll(1, #candidates)]
  local nb = engine().performSwitch(st, ad, st.double and target.id or target.side, slot, { reason = "roar" })
  if nb then
    local M = H.move(ctx)
    if M then M.target = nb end
    ad:say(Strings("%s was\ndragged out!", name(ctx, nb)))
    engine().switchInEffects(st, ad, nb, { spikes = true, deferIntimidate = true })
  end
end

-- pokefirered/src/battle_script_commands.c:7003
function Special.conversion(ctx)
  local ad, user = ctx.adapter, ctx.user
  local mon = user.mon or {}
  local list = {}
  for i = 1, 4 do
    local mv = H.moveNum(mon.moves and mon.moves[i])
    if not mv or mv == 0 then break end
    local t = tonumber(moves().get(mv).type) or 0
    if t == Types.ID.MYSTERY then
      t = H.hasType(ctx, user, Types.ID.GHOST) and Types.ID.GHOST or Types.ID.NORMAL
    end
    if not H.hasType(ctx, user, t) then list[#list + 1] = t end
  end
  if #list == 0 then return H.sayFail(ctx) end
  local t = list[ad:roll(1, #list)]
  user.type1, user.type2 = t, t
  H.attackAnim(ctx)
  ad:say(Strings("%s transformed\ninto the %s type!", name(ctx, user), Types.name(t)))
end

-- pokefirered/src/battle_script_commands.c:7699
function Special.conversion2(ctx)
  local ad, user = ctx.adapter, ctx.user
  local last = user.expLastLandedMove
  local lastType = user.expLastHitByType
  if not last or last == 0 or lastType == nil then return H.sayFail(ctx) end
  local foe = ad:foeOf(user)
  if ad._st.double and user.expLastHitById ~= nil then
    foe = require("src.core.game3.battle.state").battler(ad._st, user.expLastHitById) or foe
  end
  if engine().isTwoTurnMove(last) and foe and foe.twoTurnMove then return H.sayFail(ctx) end
  local valid = {}
  local t = Types.TABLE
  local i = 1
  while i <= #t do
    local a, d, m = t[i], t[i + 1], t[i + 2]
    if a == -1 then break end
    if a == lastType and m <= 5 and not H.hasType(ctx, user, d) then valid[#valid + 1] = d end
    i = i + 3
  end
  if #valid == 0 then return H.sayFail(ctx) end
  local pick = valid[ad:roll(1, #valid)]
  user.type1, user.type2 = pick, pick
  H.attackAnim(ctx)
  ad:say(Strings("%s transformed\ninto the %s type!", name(ctx, user), Types.name(pick)))
end

-- pokefirered/src/battle_script_commands.c:7398
function Special.transform(ctx)
  local ad, user, target = ctx.adapter, ctx.user, ctx.target
  if target.transformed or target.semiInvulnerable then return H.sayFail(ctx) end
  local proxy = state().ensureBattleMoves(user)
  local tm = target.mon or {}
  local Damage = require("src.core.game3.battle.damage")
  rawset(proxy, "attack", Damage.monStat(tm, "attack", 50))
  rawset(proxy, "defense", Damage.monStat(tm, "defense", 50))
  rawset(proxy, "speed", Damage.monStat(tm, "speed", 50))
  rawset(proxy, "spAtk", Damage.monStat(tm, "spAtk", 50))
  rawset(proxy, "spDef", Damage.monStat(tm, "spDef", 50))
  rawset(proxy, "atk", proxy.attack)
  rawset(proxy, "def", proxy.defense)
  rawset(proxy, "spe", proxy.speed)
  rawset(proxy, "spa", proxy.spAtk)
  rawset(proxy, "spd", proxy.spDef)
  rawset(proxy, "ivs", tm.ivs)
  rawset(proxy, "species", tm.species)
  for i = 1, 4 do
    local mv = tm.moves and tm.moves[i]
    proxy.moves[i] = mv
    if mv and mv ~= 0 then
      local pp = tonumber(moves().get(mv).pp) or 5
      proxy.pp[i] = math.min(5, pp)
    else
      proxy.pp[i] = nil
    end
  end
  for k, v in pairs(target.stages or {}) do user.stages[k] = v end
  user.type1, user.type2 = target.type1, target.type2
  user.ability = target.ability
  user.expTracedAbility = target.expTracedAbility
  user.transformed = true
  user.expTransform = { species = target.species, type1 = target.type1, type2 = target.type2,
    -- pokefirered/src/battle_script_commands.c:7416
    personality = target.mon and target.mon.personality }
  user.expDisabledMove = nil
  user.expDisableTurns = nil
  user.permanentSlots = { false, false, false, false }
  H.attackAnim(ctx)
  local Pokemon = require("src.core.game3.pokemon")
  ad:say(Strings("%s transformed\ninto %s!", name(ctx, user), tostring(Pokemon.name(target.species))))
end

-- pokefirered/src/battle_script_commands.c:7478
function Special.mimic(ctx)
  local ad, user, target = ctx.adapter, ctx.user, ctx.target
  if (target.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  if not H.accuracy(ctx, "lockon") then return end
  local last = H.moveNum(H.lastMove(ctx, target))
  if not last or last == 0 or user.transformed or engine().isForbiddenToCopy(last, true) then
    return H.sayFail(ctx)
  end
  if H.slotOf(user, last) then return H.sayFail(ctx) end
  local M = H.move(ctx)
  local slot = M and M.slot
  if not slot then return H.sayFail(ctx) end
  local proxy = state().ensureBattleMoves(user)
  proxy.moves[slot] = last
  proxy.pp[slot] = math.min(5, tonumber(moves().get(last).pp) or 5)
  user.permanentSlots[slot] = false
  H.attackAnim(ctx)
  ad:say(Strings("%s learned\n%s!", name(ctx, user), moves().displayName(last)))
end

-- pokefirered/src/battle_script_commands.c:7617
function Special.disable(ctx)
  local ad, target = ctx.adapter, ctx.target
  if not H.accuracy(ctx, "normal") then return end
  local last = H.lastMove(ctx, target)
  local slot = last and H.slotOf(target, last)
  local mon = target.mon
  if target.expDisabledMove or not slot or not mon or not mon.pp or (tonumber(mon.pp[slot]) or 0) <= 0 then
    return H.sayFail(ctx)
  end
  target.expDisabledMove = H.moveNum(mon.moves[slot])
  target.expDisableTurns = ad:roll(0, 3) % 4 + 2
  target.disabled = true
  H.attackAnim(ctx)
  ad:say(Strings("%s's %s\nwas disabled!", name(ctx, target), moves().displayName(mon.moves[slot])))
end

-- pokefirered/src/battle_script_commands.c:7768
function Special.sketch(ctx)
  local ad, user, target = ctx.adapter, ctx.user, ctx.target
  if (target.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  local last = H.moveNum(target.expLastPrinted)
  if user.transformed or not last or last == 0 or last == 165 or last == 166 then return H.sayFail(ctx) end
  local mon = user.mon or {}
  for i = 1, 4 do
    local mv = H.moveNum(mon.moves and mon.moves[i])
    if mv ~= 166 and mv == last then return H.sayFail(ctx) end
  end
  local M = H.move(ctx)
  local slot = M and M.slot
  if not slot then return H.sayFail(ctx) end
  local fullPp = tonumber(moves().get(last).pp) or 5
  local party = state().partyMon(user)
  if party then
    party.moves = party.moves or {}
    party.pp = party.pp or {}
    party.moves[slot] = last
    party.pp[slot] = fullPp
  end
  if user._partyMon then
    user.mon.moves[slot] = last
    user.mon.pp[slot] = fullPp
    user.sketched = user.sketched or {}
    user.sketched[slot] = true
  end
  H.attackAnim(ctx)
  ad:say(Strings("%s SKETCHED\n%s!", name(ctx, user), moves().displayName(last)))
end

-- pokefirered/data/battle_scripts_1.s:1690
function Special.batonPass(ctx)
  local ad, user = ctx.adapter, ctx.user
  local st = ad._st
  local candidates = engine().switchCandidates(st, st.double and user.id or user.side)
  if #candidates == 0 then return H.sayFail(ctx) end
  H.attackAnim(ctx)
  local pick
  if type(st.batonPassChooser) == "function" then
    local ok, v = pcall(st.batonPassChooser, user.side, candidates)
    if ok then pick = tonumber(v) end
  elseif user.side == "player" and st.interactiveChoices and coroutine.running() then
    -- pokefirered/src/battle_script_commands.c:4626
    pick = tonumber(coroutine.yield({ kind = "baton_pass", side = user.side, battler = user.id, candidates = candidates }))
  elseif user.side == "enemy" then
    -- pokefirered/src/battle_controller_opponent.c:1410
    pick = engine().mostSuitableMon(st, ad, st.double and user.id or "enemy")
  end
  local slot = candidates[1]
  for _, c in ipairs(candidates) do
    if c == pick then slot = pick end
  end
  local nb = engine().performSwitch(st, ad, st.double and user.id or user.side, slot, { batonPass = true, reason = "baton_pass" })
  if nb then
    local M = H.move(ctx)
    if M then M.user = nb end
    local text = sent_out_text(ctx, nb)
    -- pokefirered/data/battle_scripts_1.s:1705
    ad:pushEvent({ kind = "msg", text = text, wait = 0 })
    ad._say(text)
    engine().switchInEffects(st, ad, nb, { spikes = true, deferIntimidate = true })
  end
end

-- pokefirered/data/battle_scripts_1.s:1921
function Special.teleport(ctx)
  local ad, user = ctx.adapter, ctx.user
  local st = ad._st
  if not st.wild then return H.sayFail(ctx) end
  local item = tonumber(user.item) or 0
  local ab = ad:abilityOf(user)
  local foe = ad:foeOf(user)
  local fab = foe and ad:abilityOf(foe)
  if ad._st.double then
    local Abilities = require("src.core.game3.battle.abilities")
    foe, fab = Abilities.escapeBlocker(ad, user)
  end
  if not (ab == "RUN_AWAY" or item == 194) then
    if fab == "SHADOW_TAG" or (fab == "ARENA_TRAP" and not H.hasType(ctx, user, Types.ID.FLYING) and ab ~= "LEVITATE")
        or (fab == "MAGNET_PULL" and H.hasType(ctx, user, Types.ID.STEEL)) then
      return ad:say(Strings("%s's %s\nmade it ineffective!", name(ctx, foe), require("src.core.game3.battle.abilities").name(fab)))
    end
    if user.expTrapped or user.escapePrevention or (user.expTrapTurns or 0) > 0 or user.expIngrain then
      return H.sayFail(ctx)
    end
  end
  H.attackAnim(ctx)
  ad:say(Strings("%s fled from\nbattle!", name(ctx, user)))
  end_battle(ctx, "teleport")
end

-- pokefirered/src/battle_script_commands.c:8702
function Special.followMe(ctx)
  local side = ctx.adapter:ownSide(ctx.user)
  if side then
    side.expFollowMe = ctx.user
    side.expFollowMeId = ctx.user.id
  end
  H.attackAnim(ctx)
  ctx.adapter:say(Strings("%s became the\ncenter of attention!", name(ctx, ctx.user)))
end

-- pokefirered/src/battle_script_commands.c:8798
function Special.trick(ctx)
  local ad, user, target = ctx.adapter, ctx.user, ctx.target
  if (target.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  if not H.accuracy(ctx, "normal") then return end
  -- src/battle_script_commands.c:8799-8810
  local StType = ad._st
  if StType and StType.trainerTower then return H.sayFail(ctx) end
  if user.side ~= "player" and not (StType and (StType.link or StType.battleTower
      or StType.eReader or StType.secretBase)) then
    return H.sayFail(ctx)
  end
  local St = state()
  if user.expKnockedOff or target.expKnockedOff
      or (St and (St.isKnockedOff(ad._st, user) or St.isKnockedOff(ad._st, target))) then
    return H.sayFail(ctx)
  end
  local ui, ti = tonumber(user.item) or 0, tonumber(target.item) or 0
  if (ui == 0 and ti == 0) or ui == 175 or ti == 175 or Secondary.isMail(ui) or Secondary.isMail(ti) then
    return H.sayFail(ctx)
  end
  if ad:abilityOf(target) == "STICKY_HOLD" then
    return ad:say(Strings("%s's STICKY HOLD\nmade TRICK ineffective!", name(ctx, target)))
  end
  user.item, target.item = ti, ui
  Secondary.persistItem(user, ti)
  -- Both sides: the target's party mon must take the item its battler now
  -- holds, or it keeps the old one and duplicates it on switch-out.
  Secondary.persistItem(target, ui)
  H.attackAnim(ctx)
  ad:say(Strings("%s switched\nitems with its opponent!", name(ctx, user)))
  if ui ~= 0 and ti ~= 0 then
    ad:say(Strings("%s obtained\n%s.", name(ctx, user), Secondary.itemName(ti)))
    ad:say(Strings("%s obtained\n%s.", name(ctx, target), Secondary.itemName(ui)))
  elseif ti ~= 0 then
    ad:say(Strings("%s obtained\n%s.", name(ctx, user), Secondary.itemName(ti)))
  else
    ad:say(Strings("%s obtained\n%s.", name(ctx, target), Secondary.itemName(ui)))
  end
end

-- pokefirered/src/battle_script_commands.c:9366
function Special.recycle(ctx)
  local ad, user = ctx.adapter, ctx.user
  local side = ad:ownSide(user)
  local used = tonumber(side and side.expUsedHeldItem) or tonumber(user.expUsedHeldItem) or 0
  if used == 0 or (tonumber(user.item) or 0) ~= 0 then return H.sayFail(ctx) end
  user.expUsedHeldItem = nil
  if side then side.expUsedHeldItem = nil end
  user.item = used
  Secondary.persistItem(user, used)
  H.attackAnim(ctx)
  ad:say(Strings("%s found\none %s!", name(ctx, user), Secondary.itemName(used)))
end

return Special
