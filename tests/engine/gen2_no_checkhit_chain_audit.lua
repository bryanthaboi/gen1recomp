-- data/moves/effects.asm (tools/audit_effect_chains.py)
-- engine/battle/effect_commands.asm:1713 (CheckHit .FlyDigMoves)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Effects = require("src.battle.gen2.Effects")

local CART = {
  EFFECT_MIRROR_MOVE = true, -- data/moves/effects.asm:180
  EFFECT_ATTACK_UP = true, -- data/moves/effects.asm:187
  EFFECT_DEFENSE_UP = true, -- data/moves/effects.asm:199
  EFFECT_SPEED_UP = true, -- data/moves/effects.asm:211
  EFFECT_SP_ATK_UP = true, -- data/moves/effects.asm:223
  EFFECT_SP_DEF_UP = true, -- data/moves/effects.asm:235
  EFFECT_ACCURACY_UP = true, -- data/moves/effects.asm:247
  EFFECT_EVASION_UP = true, -- data/moves/effects.asm:259
  EFFECT_RESET_STATS = true, -- data/moves/effects.asm:788
  EFFECT_CONVERSION = true, -- data/moves/effects.asm:781
  EFFECT_HEAL = true, -- data/moves/effects.asm:997
  EFFECT_LIGHT_SCREEN = true, -- data/moves/effects.asm:1011
  EFFECT_OHKO = true, -- data/moves/effects.asm:917
  EFFECT_MIST = true, -- data/moves/effects.asm:953
  EFFECT_FOCUS_ENERGY = true, -- data/moves/effects.asm:960
  EFFECT_ATTACK_UP_2 = true, -- data/moves/effects.asm:272
  EFFECT_DEFENSE_UP_2 = true, -- data/moves/effects.asm:284
  EFFECT_SPEED_UP_2 = true, -- data/moves/effects.asm:296
  EFFECT_SP_ATK_UP_2 = true, -- data/moves/effects.asm:308
  EFFECT_SP_DEF_UP_2 = true, -- data/moves/effects.asm:320
  EFFECT_ACCURACY_UP_2 = true, -- data/moves/effects.asm:332
  EFFECT_EVASION_UP_2 = true, -- data/moves/effects.asm:344
  EFFECT_TRANSFORM = true, -- data/moves/effects.asm:1004
  EFFECT_REFLECT = true, -- data/moves/effects.asm:1012
  EFFECT_SUBSTITUTE = true, -- data/moves/effects.asm:1084
  EFFECT_METRONOME = true, -- data/moves/effects.asm:1141
  EFFECT_SPLASH = true, -- data/moves/effects.asm:1156
  EFFECT_COUNTER = true, -- data/moves/effects.asm:1270
  EFFECT_SKETCH = true, -- data/moves/effects.asm:1338
  EFFECT_DEFROST_OPPONENT = true, -- data/moves/effects.asm:1345
  EFFECT_SLEEP_TALK = true, -- data/moves/effects.asm:1352
  EFFECT_DESTINY_BOND = true, -- data/moves/effects.asm:1359
  EFFECT_HEAL_BELL = true, -- data/moves/effects.asm:1395
  EFFECT_MEAN_LOOK = true, -- data/moves/effects.asm:1452
  EFFECT_NIGHTMARE = true, -- data/moves/effects.asm:1459
  EFFECT_CURSE = true, -- data/moves/effects.asm:1488
  EFFECT_PROTECT = true, -- data/moves/effects.asm:1495
  EFFECT_SPIKES = true, -- data/moves/effects.asm:1502
  EFFECT_PERISH_SONG = true, -- data/moves/effects.asm:1517
  EFFECT_SANDSTORM = true, -- data/moves/effects.asm:1524
  EFFECT_ENDURE = true, -- data/moves/effects.asm:1531
  EFFECT_SAFEGUARD = true, -- data/moves/effects.asm:1670
  EFFECT_BATON_PASS = true, -- data/moves/effects.asm:1721
  EFFECT_MORNING_SUN = true, -- data/moves/effects.asm:1770
  EFFECT_SYNTHESIS = true, -- data/moves/effects.asm:1777
  EFFECT_MOONLIGHT = true, -- data/moves/effects.asm:1784
  EFFECT_RAIN_DANCE = true, -- data/moves/effects.asm:1811
  EFFECT_SUNNY_DAY = true, -- data/moves/effects.asm:1818
  EFFECT_BELLY_DRUM = true, -- data/moves/effects.asm:1835
  EFFECT_PSYCH_UP = true, -- data/moves/effects.asm:1842
  EFFECT_MIRROR_COAT = true, -- data/moves/effects.asm:1849
  EFFECT_TELEPORT = true, -- data/moves/effects.asm:2034
  EFFECT_DEFENSE_CURL = true, -- data/moves/effects.asm:2068
}

-- engine/battle/effect_commands.asm:5448
local DEFERRED = {
  EFFECT_OHKO = true,
}

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

eq(count(CART), 53, "the cart has 53 effect chains with no checkhit")

for effect in pairs(Effects.NO_CHECKHIT) do
  check(CART[effect], effect .. ": NO_CHECKHIT names a chain the cart runs without checkhit")
  check(not DEFERRED[effect], effect .. ": enforced and deferred are disjoint")
end

for effect in pairs(CART) do
  check((Effects.NO_CHECKHIT[effect] and true or false) ~= (DEFERRED[effect] and true or false),
    effect .. ": every cart no-checkhit chain is either enforced or deferred")
end

for effect in pairs(DEFERRED) do
  check(CART[effect], effect .. ": DEFERRED only names cart chains")
end

for _, effect in ipairs({ "EFFECT_NORMAL_HIT", "EFFECT_SLEEP", "EFFECT_ATTACK_DOWN",
    "EFFECT_FORCE_SWITCH", "EFFECT_FLY", "EFFECT_LEECH_SEED", "EFFECT_ENCORE" }) do
  check(not Effects.NO_CHECKHIT[effect] and not CART[effect],
    effect .. ": a chain with checkhit is never exempted")
end

local function chainsWithoutCheckhit(pret)
  local f = io.open(pret .. "/data/moves/effects.asm", "r")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  local consts = {}
  local cf = io.open(pret .. "/constants/move_effect_constants.asm", "r")
  if not cf then return nil end
  for line in cf:lines() do
    local name = line:match("^%s*const%s+(EFFECT_[A-Z0-9_]+)")
    if name then consts[#consts + 1] = name end
  end
  cf:close()
  local labels = {}
  local pf = io.open(pret .. "/data/moves/effects_pointers.asm", "r")
  if not pf then return nil end
  for line in pf:lines() do
    local label = line:match("^%s*dw%s+([%a_][%w_]*)")
    if label then labels[#labels + 1] = label end
  end
  pf:close()
  if #consts ~= #labels then return nil end
  local chains, current = {}, {}
  for raw in (src .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw:gsub(";.*$", "")
    local label = line:match("^([%a_][%w_]*):")
    if label then
      local last = current[#current]
      if last and next(chains[last]) ~= nil then current = {} end
      current[#current + 1] = label
      chains[label] = chains[label] or {}
    else
      local cmd = line:match("^%s+([a-z][%w_]*)")
      if cmd then
        for _, name in ipairs(current) do chains[name][cmd] = true end
      end
    end
  end
  local out = {}
  for i, effect in ipairs(consts) do
    local chain = chains[labels[i]]
    if chain and not chain.checkhit then out[effect] = true end
  end
  return out
end

for _, pret in ipairs({ "../pokecrystal", "../pokegold" }) do
  local derived = chainsWithoutCheckhit(pret)
  if derived then
    for effect in pairs(derived) do
      check(CART[effect], ("%s: %s is in the pinned cart list"):format(pret, effect))
    end
    for effect in pairs(CART) do
      check(derived[effect], ("%s: %s still has no checkhit"):format(pret, effect))
    end
  else
    check(true, "no pret checkout at " .. pret .. " (re-derivation SKIP)")
  end
end

T.finish("gen2 no-checkhit chain audit")
