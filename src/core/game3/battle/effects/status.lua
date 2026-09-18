
local H = require("src.core.game3.battle.effects._helpers")
local Secondary = require("src.core.game3.battle.effects.secondary")
local Types = require("src.core.game3.battle.types")

local Status = {}

local function name(ctx, b) return ctx.adapter:displayName(b) end

local function sub(ctx) return (ctx.target.substituteHP or 0) > 0 end

local function safeguarded(ctx)
  local side = ctx.adapter:ownSide(ctx.target)
  if side and (side.expSafeguardTurns or 0) > 0 then
    ctx.adapter:say(name(ctx, ctx.target) .. "'s party is protected\nby SAFEGUARD!")
    return true
  end
  return false
end
Status.safeguarded = safeguarded

local function not_affected(ctx)
  local M = H.move(ctx)
  if M then M.noEffect = true end
  ctx.adapter:say("It doesn't affect\n" .. name(ctx, ctx.target) .. "…")
end

local function primary(ctx, eff)
  local M = H.move(ctx)
  if M then return Secondary.set(M, eff, true, false, false) end
  local fake = { adapter = ctx.adapter, user = ctx.user, target = ctx.target, st = ctx.adapter._st }
  return Secondary.set(fake, eff, true, false, false)
end

-- pokefirered/src/battle_script_commands.c:6546
function Status.cantMakeAsleep(ctx, target)
  local ad = ctx.adapter
  local ab = ad:abilityOf(target)
  local up = ad:uproarActive()
  if up and ab ~= "SOUNDPROOF" then
    ad:say("But " .. name(ctx, target) .. " can't\nsleep in an UPROAR!")
    return true
  end
  if ab == "INSOMNIA" or ab == "VITAL_SPIRIT" then
    ad:say(name(ctx, target) .. " stayed awake\nusing its " .. ab:gsub("_", " ") .. "!")
    return true
  end
  return false
end

-- pokefirered/data/battle_scripts_1.s:2170
function Status.burn(ctx)
  local ad, t = ctx.adapter, ctx.target
  if sub(ctx) then return H.sayFail(ctx) end
  if ad:status(t) == "BRN" then
    return ad:say(name(ctx, t) .. " already\nhas a burn.")
  end
  if H.hasType(ctx, t, Types.ID.FIRE) then return not_affected(ctx) end
  if ad:abilityOf(t) == "WATER_VEIL" then
    return ad:say(name(ctx, t) .. "'s WATER VEIL\nprevents burns!")
  end
  if ad:status(t) then return H.sayFail(ctx) end
  if not H.accuracy(ctx, "normal") then return end
  if safeguarded(ctx) then return end
  H.attackAnim(ctx)
  primary(ctx, "BURN")
end

-- pokefirered/data/battle_scripts_1.s:984
function Status.poison(ctx)
  local ad, t = ctx.adapter, ctx.target
  if ad:abilityOf(t) == "IMMUNITY" then
    return ad:say(name(ctx, t) .. "'s IMMUNITY\nprevents poisoning!")
  end
  if sub(ctx) then return H.sayFail(ctx) end
  if ad:status(t) == "PSN" or ad:status(t) == "TOX" then
    return ad:say(name(ctx, t) .. " is already\npoisoned.")
  end
  if H.hasType(ctx, t, Types.ID.POISON) or H.hasType(ctx, t, Types.ID.STEEL) then
    return not_affected(ctx)
  end
  if ad:status(t) then return H.sayFail(ctx) end
  if not H.accuracy(ctx, "normal") then return end
  if safeguarded(ctx) then return end
  H.attackAnim(ctx)
  primary(ctx, "POISON")
end

-- pokefirered/data/battle_scripts_1.s:687
function Status.toxic(ctx)
  local ad, t = ctx.adapter, ctx.target
  if ad:abilityOf(t) == "IMMUNITY" then
    return ad:say(name(ctx, t) .. "'s IMMUNITY\nprevents poisoning!")
  end
  if sub(ctx) then return H.sayFail(ctx) end
  if ad:status(t) == "PSN" or ad:status(t) == "TOX" then
    return ad:say(name(ctx, t) .. " is already\npoisoned.")
  end
  if ad:status(t) then return H.sayFail(ctx) end
  if H.hasType(ctx, t, Types.ID.POISON) or H.hasType(ctx, t, Types.ID.STEEL) then
    return not_affected(ctx)
  end
  if not H.accuracy(ctx, "normal") then return end
  if safeguarded(ctx) then return end
  H.attackAnim(ctx)
  primary(ctx, "TOXIC")
end

-- pokefirered/data/battle_scripts_1.s:287
function Status.sleep(ctx)
  local ad, t = ctx.adapter, ctx.target
  if sub(ctx) then return H.sayFail(ctx) end
  if ad:status(t) == "SLP" then
    return ad:say(name(ctx, t) .. " is\nalready asleep!")
  end
  if Status.cantMakeAsleep(ctx, t) then return end
  if ad:status(t) then return H.sayFail(ctx) end
  if not H.accuracy(ctx, "normal") then return end
  if safeguarded(ctx) then return end
  H.attackAnim(ctx)
  primary(ctx, "SLEEP")
end

-- pokefirered/data/battle_scripts_1.s:1005
function Status.paralyze(ctx)
  local ad, t = ctx.adapter, ctx.target
  if ad:abilityOf(t) == "LIMBER" then
    return ad:say(name(ctx, t) .. "'s LIMBER\nprevents paralysis!")
  end
  if sub(ctx) then return H.sayFail(ctx) end
  local mt = ctx.move and ctx.move.type or 0
  local _, flags = Types.typeCalc(mt, t.type1, t.type2, nil, t.expIdentified)
  if flags.immune or (ad:abilityOf(t) == "LEVITATE" and tonumber(mt) == Types.ID.GROUND) then
    return not_affected(ctx)
  end
  if ad:status(t) == "PAR" then
    return ad:say(name(ctx, t) .. " is\nalready paralyzed!")
  end
  if ad:status(t) then return H.sayFail(ctx) end
  if not H.accuracy(ctx, "normal") then return end
  if safeguarded(ctx) then return end
  H.attackAnim(ctx)
  primary(ctx, "PARALYSIS")
end

-- pokefirered/data/battle_scripts_1.s:2303
function Status.taunt(ctx)
  if not H.accuracy(ctx, "normal") then return end
  if (ctx.target.expTauntedTurns or 0) > 0 then return H.sayFail(ctx) end
  -- pokefirered/src/battle_script_commands.c:8765
  ctx.target.expTauntedTurns = 2
  H.attackAnim(ctx)
  ctx.adapter:say(name(ctx, ctx.target) .. " fell for\nthe TAUNT!")
end

-- pokefirered/data/battle_scripts_1.s:2446
function Status.yawn(ctx)
  local ad, t = ctx.adapter, ctx.target
  local ab = ad:abilityOf(t)
  if ab == "VITAL_SPIRIT" or ab == "INSOMNIA" then
    return ad:say(name(ctx, t) .. "'s " .. ab:gsub("_", " ") .. "\nmade it ineffective!")
  end
  if sub(ctx) then return H.sayFail(ctx) end
  if safeguarded(ctx) then return end
  if not H.accuracy(ctx, "lockon") then return end
  if ad:uproarActive() and ab ~= "SOUNDPROOF" then return H.sayFail(ctx) end
  if (t.expYawnTurns or 0) > 0 or ad:status(t) then return H.sayFail(ctx) end
  t.expYawnTurns = 2
  t.yawnTurns = 2
  H.attackAnim(ctx)
  ad:say(name(ctx, ctx.user) .. " made\n" .. name(ctx, t) .. " drowsy!")
end

return Status
