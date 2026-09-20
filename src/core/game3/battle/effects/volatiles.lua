-- FRLG volatiles (ported from KR battle/core/effects/volatiles.lua; no KR require).

local H = require("src.core.game3.battle.effects._helpers")
local Strings = require("src.core.Strings")

local Volatiles = {}

local function name(ctx, b) return ctx.adapter:displayName(b) end

-- pokefirered/src/battle_script_commands.c:6220
local function protect_like(ctx, onSuccess)
  local user = ctx.user
  local last = user.expLastResulting and H.moveNum(user.expLastResulting)
  if last ~= 182 and last ~= 197 and last ~= 203 then user.expProtectStreak = 0 end
  local streak = user.expProtectStreak or 0
  local st = ctx.adapter._st
  local ok = user.expTurnOrder ~= ((st and st.double) and 4 or 2)
  if ok and streak > 0 then
    local denom = 2 ^ math.min(streak, 3)
    ok = ctx.adapter:roll(0, denom - 1) == 0
  end
  if not ok then
    user.expProtectStreak = 0
    return H.sayFail(ctx)
  end
  user.expProtectStreak = streak + 1
  H.attackAnim(ctx)
  onSuccess(user)
end

function Volatiles.protect(ctx)
  protect_like(ctx, function(user)
    user.expProtected = true
    ctx.adapter:say(Strings("%s protected\nitself!", name(ctx, user)))
  end)
end

function Volatiles.endure(ctx)
  protect_like(ctx, function(user)
    user.expEnduring = true
    ctx.adapter:say(Strings("%s braced\nitself!", name(ctx, user)))
  end)
end

-- pokefirered/src/battle_script_commands.c:7642
function Volatiles.encore(ctx)
  local target = ctx.target
  if not H.accuracy(ctx, "normal") then return end
  local last = H.moveNum(H.lastMove(ctx, target))
  if not last or last == 0 or last == 165 or last == 227 or last == 119 then return H.sayFail(ctx) end
  if (target.expEncoreTurns or 0) > 0 then return H.sayFail(ctx) end
  local slot = H.slotOf(target, last)
  local mon = target.mon
  if not slot or not mon or not mon.pp or (tonumber(mon.pp[slot]) or 0) <= 0 then return H.sayFail(ctx) end
  target.expEncoreMove = mon.moves[slot]
  target.expEncoreSlot = slot
  target.expEncoreTurns = ctx.adapter:roll(0, 3) % 4 + 3
  H.attackAnim(ctx)
  ctx.adapter:say(Strings("%s got\nan ENCORE!", name(ctx, target)))
end

-- pokefirered/src/battle_script_commands.c:8133
function Volatiles.perishSong(ctx)
  local ad = ctx.adapter
  local affected = 0
  local blocked = {}
  for _, b in ipairs(ad:activeBattlers()) do
    if b.expPerishTurns or ad:abilityOf(b) == "SOUNDPROOF" then
      if ad:abilityOf(b) == "SOUNDPROOF" then blocked[#blocked + 1] = b end
    else
      b.expPerishTurns = 3
      b.perishSong = true
      affected = affected + 1
    end
  end
  if affected == 0 then return H.sayFail(ctx) end
  H.attackAnim(ctx)
  ad:say(Strings("All affected POKéMON will\nfaint in three turns!"))
  for _, b in ipairs(blocked) do
    ad:say(Strings("%s's SOUNDPROOF\nblocks PERISH SONG!", name(ctx, b)))
  end
end

-- pokefirered/src/battle_script_commands.c:7275
function Volatiles.attract(ctx)
  local ad, target = ctx.adapter, ctx.target
  if not H.accuracy(ctx, "normal") then return end
  if ad:abilityOf(target) == "OBLIVIOUS" then
    return ad:say(Strings("%s's OBLIVIOUS\nprevents romance!", name(ctx, target)))
  end
  local userMon = ad:mon(ctx.user)
  local targetMon = ad:mon(target)
  local ug = userMon and userMon.gender
  local tg = targetMon and targetMon.gender
  if target.expInfatuated or not ug or not tg or ug == "U" or tg == "U" or ug == tg then
    return H.sayFail(ctx)
  end
  target.expInfatuated = true
  target.expInfatuatedBy = ctx.user.side
  target.expInfatuatedWith = ctx.user
  H.attackAnim(ctx)
  ad:say(Strings("%s\nfell in love!", name(ctx, target)))
end

-- pokefirered/src/battle_script_commands.c:7943
function Volatiles.spite(ctx)
  local ad, target = ctx.adapter, ctx.target
  if not H.accuracy(ctx, "normal") then return end
  local last = H.lastMove(ctx, target)
  local slot = last and H.slotOf(target, last)
  local mon = target.mon
  if not slot or not mon or not mon.pp or (tonumber(mon.pp[slot]) or 0) <= 1 then return H.sayFail(ctx) end
  local cut = ad:roll(0, 3) % 4 + 2
  if mon.pp[slot] < cut then cut = mon.pp[slot] end
  mon.pp[slot] = mon.pp[slot] - cut
  if mon.pp[slot] == 0 then
    local Engine = require("src.core.game3.battle.engine")
    Engine.cancelMultiTurnMoves(target)
  end
  H.attackAnim(ctx)
  local Moves = require("src.core.game3.battle.moves")
  ad:say(Strings("Reduced %s's\n%s by %d!", name(ctx, target), Moves.displayName(last), cut))
end

-- pokefirered/src/battle_script_commands.c:8744
function Volatiles.torment(ctx)
  if not H.accuracy(ctx, "normal") then return end
  if ctx.target.expTormented then return H.sayFail(ctx) end
  ctx.target.expTormented = true
  ctx.target.torment = true
  H.attackAnim(ctx)
  ctx.adapter:say(Strings("%s was subjected\nto TORMENT!", name(ctx, ctx.target)))
end

return Volatiles
