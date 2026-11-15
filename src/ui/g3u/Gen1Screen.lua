local RomText = require("src.core.RomText")
local Strings = require("src.core.Strings")
local Events = require("src.battle.g3u.Events")

local Gen1Screen = {}

local MAPS = setmetatable({}, { __mode = "k" })

function Gen1Screen.maps(data)
  local m = MAPS[data]
  if m then return m end
  m = { species = {}, moves = {} }
  for key, def in pairs(data and data.pokemon or {}) do
    local n = type(def) == "table" and tonumber(def.dex) or nil
    if n and n >= 1 and (m.species[n] == nil or tostring(key) < tostring(m.species[n])) then
      m.species[n] = key
    end
  end
  for key, def in pairs(data and data.moves or {}) do
    local n = type(def) == "table" and tonumber(def.index) or nil
    if n and n >= 1 then m.moves[n] = key end
  end
  MAPS[data] = m
  return m
end

function Gen1Screen.speciesKey(data, national)
  return Gen1Screen.maps(data).species[tonumber(national) or -1]
end

function Gen1Screen.moveKey(data, id)
  return Gen1Screen.maps(data).moves[tonumber(id) or -1]
end

local function speciesName(data, key)
  local def = key and data.pokemon and data.pokemon[key]
  return def and def.name or nil
end

local function moveName(data, key)
  local def = key and data.moves and data.moves[key]
  return def and def.name or (key and tostring(key)) or nil
end

local function plain(s)
  return (tostring(s or ""):upper():gsub("[^%w]", ""))
end

function Gen1Screen.monFromRecord(rec, data)
  if type(rec) ~= "table" then return nil, "record" end
  local key = Gen1Screen.speciesKey(data, rec.species)
  if not key then return nil, "species" end
  local moves = {}
  for i, mv in ipairs(rec.moves or {}) do
    moves[i] = { id = Gen1Screen.moveKey(data, mv.id) or tostring(mv.id), pp = tonumber(mv.pp) or 0,
      ppUps = tonumber(mv.ppUps) or 0 }
  end
  local nick = rec.nickname
  if type(nick) ~= "string" or nick == "" or plain(nick) == plain(speciesName(data, key)) then nick = nil end
  return {
    species = key, national = rec.species, level = rec.level, hp = rec.hp,
    stats = { hp = rec.maxHp, attack = rec.atk, defense = rec.def, speed = rec.speed, special = rec.spAtk },
    moves = moves, nickname = nick, status = nil,
    dvs = { attack = 0, defense = 0, speed = 0, special = 0, hp = 0 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    exp = 0,
  }
end

function Gen1Screen.monName(data, mon)
  if not mon then return "?" end
  return mon.nickname or speciesName(data, mon.species) or tostring(mon.species)
end

function Gen1Screen.newCtx(data, seat, parties, names)
  local ctx = { data = data, seat = seat, peer = 1 - seat, mons = { [0] = {}, [1] = {} },
    active = { [0] = 1, [1] = 1 }, fainted = { [0] = {}, [1] = {} },
    names = { me = names and names.me or "?", foe = names and names.foe or "?" } }
  for s = 0, 1 do
    for i, rec in ipairs(parties and parties[s] or {}) do
      local mon, why = Gen1Screen.monFromRecord(rec, data)
      if not mon then return nil, why end
      ctx.mons[s][i] = mon
    end
  end
  return ctx
end

local function refSeat(ref)
  if type(ref) == "table" then return tonumber(ref.side) end
  if type(ref) == "string" then return Events.seatOf(ref) end
  return nil
end

local function refMon(ctx, ref)
  local seat = refSeat(ref)
  if seat == nil or not ctx.mons[seat] then return nil end
  local idx = type(ref) == "table" and tonumber(ref.index) or nil
  return ctx.mons[seat][idx or ctx.active[seat]], seat
end

function Gen1Screen.who(ctx, ref)
  local mon, seat = refMon(ctx, ref)
  if not mon then return nil end
  local name = Gen1Screen.monName(ctx.data, mon)
  -- home/text.asm:185
  if seat ~= ctx.seat then return RomText(ctx.data, "EnemyText", nil) .. name end
  return name
end

local function rawName(ctx, ref)
  local mon = refMon(ctx, ref)
  return mon and Gen1Screen.monName(ctx.data, mon) or nil
end

local function moveOf(ctx, v)
  local id = type(v) == "table" and tonumber(v.move) or tonumber(v)
  if not id then return nil end
  return moveName(ctx.data, Gen1Screen.moveKey(ctx.data, id))
end

local function speciesOf(ctx, v)
  local n = type(v) == "table" and tonumber(v.species) or tonumber(v)
  return speciesName(ctx.data, Gen1Screen.speciesKey(ctx.data, n))
end

-- data/battle/stat_mod_names.asm:4-10
local STAT_LABEL = {
  attack = 1, atk = 1, defense = 2, def = 2, speed = 3, spe = 3,
  spAtk = 4, spDef = 4, spatk = 4, spdef = 4, spa = 4, spd = 4,
  special = 4, accuracy = 5, acc = 5, evasion = 6, eva = 6,
}

-- engine/battle/effects.asm:1032-1054
local CHARGE = {
  STRINGID_PKMNFLEWHIGH = "_FlewUpHighText",
  STRINGID_PKMNDUGHOLE = "_DugAHoleText",
  STRINGID_PKMNWHIPPEDWHIRLWIND = "_MadeWhirlwindText",
  STRINGID_PKMNTOOKSUNLIGHT = "_TookInSunlightText",
  STRINGID_PKMNLOWEREDHEAD = "_LoweredItsHeadText",
  STRINGID_PKMNISGLOWING = "_SkyAttackGlowingText",
}

local function rom(ctx, label, ...)
  for i = 1, select("#", ...) do
    if select(i, ...) == nil then return nil end
  end
  return RomText(ctx.data, label, nil, ...)
end

local function joined(...)
  local parts = { ... }
  for i = 1, #parts do parts[i] = parts[i]:gsub("{DONE}$", ""):gsub("{SCROLL}", "\n") end
  return table.concat(parts)
end

local function first(f, ...)
  for _, k in ipairs({ ... }) do
    if f[k] ~= nil then return f[k] end
  end
  return nil
end

local function statText(ctx, ref, f)
  local name = Gen1Screen.who(ctx, ref)
  local index = STAT_LABEL[f.stat or ""] or STAT_LABEL[tostring(f.stat or ""):lower()]
  local delta = tonumber(f.delta)
  if not name or not index or not delta or delta == 0 then return nil end
  local label = RomText(ctx.data, "StatModTextStrings." .. index, nil)
  -- engine/battle/effects.asm:516-538, :718-742
  if delta > 0 then
    return joined(rom(ctx, "_MonsStatsRoseText", name, label),
      delta >= 2 and rom(ctx, "_GreatlyRoseText") or "", rom(ctx, "_RoseText"))
  end
  return joined(rom(ctx, "_MonsStatsFellText", name, label),
    delta <= -2 and rom(ctx, "_GreatlyFellText") or "", rom(ctx, "_FellText"))
end

local function failed(ctx) return rom(ctx, "_ButItFailedText") end
local function nothing(ctx) return rom(ctx, "_NothingHappenedText") end
local function didntAffect(ctx, f) return rom(ctx, "_DidntAffectText", Gen1Screen.who(ctx, f.def)) end

local function faintedText(ctx, ref)
  local _, seat = refMon(ctx, ref)
  local name = rawName(ctx, ref)
  if not name then return nil end
  if seat == ctx.seat then return rom(ctx, "_PlayerMonFaintedText", name) end
  return rom(ctx, "_EnemyMonFaintedText", name)
end

local TEXT = {
  STRINGID_CRITICALHIT = function(c) return rom(c, "_CriticalHitText") end,
  STRINGID_ONEHITKO = function(c) return rom(c, "_OHKOText") end,
  STRINGID_SUPEREFFECTIVE = function(c) return rom(c, "_SuperEffectiveText") end,
  STRINGID_NOTVERYEFFECTIVE = function(c) return rom(c, "_NotVeryEffectiveText") end,
  STRINGID_ITDOESNTAFFECT = function(c, f)
    return rom(c, "_DoesntAffectMonText", Gen1Screen.who(c, f.def))
  end,
  STRINGID_ATTACKMISSED = function(c, f)
    return rom(c, "_AttackMissedText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNPROTECTEDBYMIST = function(c, f)
    local user = f.atk or (c.lastUser ~= nil and { side = c.lastUser }) or nil
    return rom(c, "_AttackMissedText", Gen1Screen.who(c, user))
  end,
  STRINGID_PKMNAVOIDEDATTACK = function(c, f)
    return rom(c, "_EvadedAttackText", Gen1Screen.who(c, f.def))
  end,
  STRINGID_BUTITFAILED = failed,
  STRINGID_MIRRORMOVEFAILED = failed,
  STRINGID_PKMNHPFULL = failed,
  STRINGID_PKMNALREADYCONFUSED = failed,
  STRINGID_BUTNOEFFECT = nothing,
  STRINGID_BUTNOTHINGHAPPENED = nothing,
  STRINGID_STATSWONTINCREASE = nothing,
  STRINGID_STATSWONTINCREASE2 = nothing,
  STRINGID_STATSWONTDECREASE = nothing,
  STRINGID_STATSWONTDECREASE2 = nothing,
  STRINGID_PKMNWASNTAFFECTED = didntAffect,
  STRINGID_PKMNALREADYPOISONED = didntAffect,
  STRINGID_PKMNISALREADYPARALYZED = didntAffect,
  STRINGID_PKMNUNAFFECTED = function(c, f)
    return rom(c, "_UnaffectedText", Gen1Screen.who(c, f.def))
  end,
  STRINGID_HITXTIMES = function(c, f)
    local n = tonumber(f.buff1)
    if not n then return nil end
    if c.lastUser == c.seat then return rom(c, "_MultiHitText", n) end
    return rom(c, "_HitXTimesText", n)
  end,
  STRINGID_TARGETFAINTED = function(c, f) return faintedText(c, f.def) end,
  STRINGID_ATTACKERFAINTED = function(c, f) return faintedText(c, f.atk) end,
  STRINGID_PKMNHURTBYPOISON = function(c, f)
    return rom(c, "_HurtByPoisonText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNHURTBYBURN = function(c, f)
    return rom(c, "_HurtByBurnText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNSAPPEDBYLEECHSEED = function(c, f)
    return rom(c, "_HurtByLeechSeedText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNWOKEUP = function(c, f) return rom(c, "_WokeUpText", Gen1Screen.who(c, f.atk)) end,
  STRINGID_PKMNISFROZEN = function(c, f)
    return rom(c, "_IsFrozenText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNISPARALYZED = function(c, f)
    return rom(c, "_FullyParalyzedText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNHEALEDCONFUSION = function(c, f)
    return rom(c, "_ConfusedNoMoreText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_ITHURTCONFUSION = function(c) return rom(c, "_HurtItselfText") end,
  STRINGID_PKMNFLINCHED = function(c, f) return rom(c, "_FlinchedText", Gen1Screen.who(c, f.atk)) end,
  STRINGID_PKMNMUSTRECHARGE = function(c, f)
    return rom(c, "_MustRechargeText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNFATIGUECONFUSION = function(c, f)
    return rom(c, "_BecameConfusedText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNUNLEASHEDENERGY = function(c, f)
    return rom(c, "_UnleashedEnergyText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNSTORINGENERGY = function(c, f)
    local name = Gen1Screen.who(c, f.atk)
    return name and Strings("%s\nis storing energy!", name) or nil
  end,
  STRINGID_PKMNRAGEBUILDING = function(c, f)
    return rom(c, "_BuildingRageText", Gen1Screen.who(c, first(f, "def", "atk")))
  end,
  STRINGID_PKMNHITWITHRECOIL = function(c, f)
    return rom(c, "_HitWithRecoilText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNCRASHED = function(c, f)
    return rom(c, "_KeptGoingAndCrashedText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNENERGYDRAINED = function(c, f)
    return rom(c, "_SuckedHealthText", Gen1Screen.who(c, f.def))
  end,
  STRINGID_PKMNDREAMEATEN = function(c, f)
    return rom(c, "_DreamWasEatenText", Gen1Screen.who(c, f.def))
  end,
  STRINGID_PKMNREGAINEDHEALTH = function(c, f)
    return rom(c, "_RegainedHealthText", Gen1Screen.who(c, first(f, "def", "atk")))
  end,
  STRINGID_PKMNWENTTOSLEEP = function(c, f)
    return rom(c, "_StartedSleepingEffect", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNSLEPTHEALTHY = function(c, f)
    return rom(c, "_FellAsleepBecameHealthyText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNFELLASLEEP = function(c, f)
    return rom(c, "_FellAsleepText", Gen1Screen.who(c, first(f, "eff", "def")))
  end,
  STRINGID_PKMNALREADYASLEEP = function(c, f)
    return rom(c, "_AlreadyAsleepText", Gen1Screen.who(c, f.def))
  end,
  STRINGID_PKMNWASPOISONED = function(c, f)
    return rom(c, "_PoisonedText", Gen1Screen.who(c, first(f, "eff", "def")))
  end,
  STRINGID_PKMNBADLYPOISONED = function(c, f)
    return rom(c, "_BadlyPoisonedText", Gen1Screen.who(c, first(f, "eff", "def")))
  end,
  STRINGID_PKMNWASBURNED = function(c, f)
    return rom(c, "_BurnedText", Gen1Screen.who(c, first(f, "eff", "def")))
  end,
  STRINGID_PKMNWASFROZEN = function(c, f)
    return rom(c, "_FrozenText", Gen1Screen.who(c, first(f, "eff", "def")))
  end,
  STRINGID_PKMNWASPARALYZED = function(c, f)
    return rom(c, "_ParalyzedMayNotAttackText",
      Gen1Screen.who(c, first(f, "eff", "def")))
  end,
  STRINGID_PKMNWASCONFUSED = function(c, f)
    return rom(c, "_BecameConfusedText", Gen1Screen.who(c, first(f, "eff", "def")))
  end,
  STRINGID_PKMNWASDEFROSTED = function(c, f)
    return rom(c, "_FireDefrostedText", Gen1Screen.who(c, first(f, "def", "atk", "eff")))
  end,
  STRINGID_ATTACKERSSTATROSE = function(c, f) return statText(c, f.atk, f) end,
  STRINGID_ATTACKERSSTATFELL = function(c, f) return statText(c, f.atk, f) end,
  STRINGID_DEFENDERSSTATROSE = function(c, f) return statText(c, f.def, f) end,
  STRINGID_DEFENDERSSTATFELL = function(c, f) return statText(c, f.def, f) end,
  STRINGID_STATCHANGESGONE = function(c)
    return rom(c, "_StatusChangesEliminatedText")
  end,
  STRINGID_PKMNSHROUDEDINMIST = function(c, f)
    return rom(c, "_ShroudedInMistText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNGETTINGPUMPED = function(c, f)
    return rom(c, "_GettingPumpedText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNMADESUBSTITUTE = function(c) return rom(c, "_SubstituteText") end,
  STRINGID_PKMNHASSUBSTITUTE = function(c, f)
    return rom(c, "_HasSubstituteText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_TOOWEAKFORSUBSTITUTE = function(c)
    return rom(c, "_TooWeakSubstituteText")
  end,
  STRINGID_SUBSTITUTEDAMAGED = function(c, f)
    return rom(c, "_SubstituteTookDamageText", Gen1Screen.who(c, f.def))
  end,
  STRINGID_PKMNSUBSTITUTEFADED = function(c, f)
    return rom(c, "_SubstituteBrokeText", Gen1Screen.who(c, f.def))
  end,
  STRINGID_PKMNTRANSFORMEDINTO = function(c, f)
    return rom(c, "_TransformedText", Gen1Screen.who(c, f.atk), speciesOf(c, f.buff1))
  end,
  STRINGID_PKMNMOVEWASDISABLED = function(c, f)
    return rom(c, "_MoveWasDisabledText", Gen1Screen.who(c, f.def), moveOf(c, f.buff1))
  end,
  STRINGID_PKMNMOVEDISABLEDNOMORE = function(c, f)
    return rom(c, "_DisabledNoMoreText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNMOVEISDISABLED = function(c, f)
    return rom(c, "_MoveIsDisabledText", Gen1Screen.who(c, f.atk),
      moveOf(c, first(f, "currentMove", "buff1")))
  end,
  STRINGID_PKMNSEEDED = function(c, f)
    return rom(c, "_WasSeededText", Gen1Screen.who(c, f.def))
  end,
  STRINGID_COINSSCATTERED = function(c) return rom(c, "_CoinsScatteredText") end,
  STRINGID_PKMNRAISEDDEF = function(c, f)
    return rom(c, "_ReflectGainedArmorText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNRAISEDSPDEF = function(c, f)
    return rom(c, "_LightScreenProtectedText", Gen1Screen.who(c, f.atk))
  end,
  STRINGID_PKMNLEARNEDMOVE2 = function(c, f)
    return rom(c, "_MimicLearnedMoveText", Gen1Screen.who(c, f.atk), moveOf(c, f.buff1))
  end,
  STRINGID_PKMNHASNOMOVESLEFT = function(c, f)
    return rom(c, "_NoMovesLeftText", rawName(c, f.atk))
  end,
  STRINGID_NOPPLEFT = function(c) return rom(c, "_MoveNoPPText") end,
  STRINGID_BUTNOPPLEFT = function(c) return rom(c, "_MoveNoPPText") end,
  STRINGID_PKMNCHANGEDTYPE = function(c, f)
    local name = Gen1Screen.who(c, f.atk)
    local t = type(f.buff1) == "table" and tonumber(f.buff1.type) or nil
    local Identity = require("src.online.xgen.Identity")
    local typeName = t and Identity.GEN3_TYPES[t]
    if not name or not typeName then return nil end
    return Strings("%s's type\nbecame %s!", name, Strings(typeName))
  end,
  STRINGID_PKMNWASDRAGGEDOUT = function(c, f)
    local name = Gen1Screen.who(c, f.def)
    return name and Strings("%s was\ndragged out!", name) or nil
  end,
  STRINGID_PKMNHURTBY = function(c, f)
    local name, mv = Gen1Screen.who(c, f.atk), moveOf(c, f.buff1)
    return (name and mv) and Strings("%s's\nhurt by %s!", name, mv) or nil
  end,
}
TEXT.STRINGID_PKMNEVADEDATTACK = TEXT.STRINGID_PKMNAVOIDEDATTACK
TEXT.STRINGID_PKMNWASDEFROSTED2 = TEXT.STRINGID_PKMNWASDEFROSTED
TEXT.STRINGID_PKMNWASDEFROSTEDBY = TEXT.STRINGID_PKMNWASDEFROSTED
TEXT.STRINGID_STATROSE = function(c, f) return statText(c, first(f, "atk", "def"), f) end
TEXT.STRINGID_STATFELL = function(c, f) return statText(c, first(f, "def", "atk"), f) end

Gen1Screen.TEXT = TEXT

local function sleepAnim(ctx, ref, kind)
  local _, seat = refMon(ctx, ref)
  if seat == nil then return nil end
  local mine = seat == ctx.seat
  if kind == "sleep" then return { op = "anim", seat = seat, name = mine and "SLP_PLAYER_ANIM" or "SLP_ANIM" } end
  return { op = "anim", seat = seat, name = mine and "CONF_PLAYER_ANIM" or "CONF_ANIM" }
end

function Gen1Screen.textFor(id, fill, ctx)
  if id == "STRINGID_USEDMOVE" then
    local name = Gen1Screen.who(ctx, fill.atk)
    local mv = moveOf(ctx, fill.currentMove)
    if not name or not mv then return nil end
    -- engine/battle/used_move_text.asm:5-6
    return joined(rom(ctx, "_ActorNameText", name), rom(ctx, "_UsedMove1Text"),
      rom(ctx, "_MoveNameText", mv)), true
  end
  local charge = CHARGE[id]
  if charge then
    local name = Gen1Screen.who(ctx, fill.atk)
    if not name then return nil end
    return joined(rom(ctx, "_ChargeMoveEffectText", name), rom(ctx, charge))
  end
  local fn = TEXT[id]
  if not fn then return nil end
  local ok, text = pcall(fn, ctx, fill or {})
  if not ok then return nil end
  return text
end

local function effectiveness(rest, from)
  for i = from or 1, #(rest or {}) do
    local e = rest[i]
    if e.kind == "move" or (e.kind == "msg" and e.id == "STRINGID_USEDMOVE") then break end
    if e.kind == "msg" and e.id == "STRINGID_SUPEREFFECTIVE" then return { sound = "Super_Effective", pitch = 0xe0 } end
    if e.kind == "msg" and e.id == "STRINGID_NOTVERYEFFECTIVE" then
      return { sound = "Not_Very_Effective", pitch = 0x50 }
    end
  end
  -- engine/battle/animations.asm:2639
  return { sound = "Damage", pitch = 0x20 }
end

local STATUS = { SLP = "SLP", PSN = "PSN", TOX = "PSN", BRN = "BRN", PAR = "PAR", FRZ = "FRZ" }

local function baseRowsFor(ev, ctx, rest, restAt)
  local rows = {}
  if type(ev) ~= "table" then return rows end
  local k = ev.kind
  if k == "msg" then
    local fill = type(ev.fill) == "table" and ev.fill or {}
    local text, auto = Gen1Screen.textFor(ev.id, fill, ctx)
    if not text then return rows end
    rows[#rows + 1] = { op = "say", text = text, auto = auto or nil }
    if ev.id == "STRINGID_PKMNISCONFUSED" then
      rows[#rows + 1] = sleepAnim(ctx, fill.atk, "confusion")
    elseif ev.id == "STRINGID_PKMNTRANSFORMEDINTO" then
      local _, seat = refMon(ctx, fill.atk)
      local key = Gen1Screen.speciesKey(ctx.data, type(fill.buff1) == "table" and fill.buff1.species or nil)
      if seat ~= nil and key then table.insert(rows, 1, { op = "transform", seat = seat, species = key }) end
    end
    return rows
  elseif k == "move" then
    local key = Gen1Screen.moveKey(ctx.data, ev.moveId)
    if ev.user == nil or not key then return rows end
    ctx.lastUser = ev.user
    local row = { op = "move", seat = ev.user, target = ev.target, move = key }
    ctx.lastMoveRow = row
    rows[1] = row
    return rows
  elseif k == "hp" then
    local seat = tonumber(ev.side)
    if seat == nil then return rows end
    local idx = ctx.active[seat]
    local row = { op = "hp", seat = seat, index = idx, from = ev.from, to = tonumber(ev.to) or 0, max = ev.max }
    local mv = ctx.lastMoveRow
    if ev.hit and mv and not mv.hit and mv.target == seat and (tonumber(ev.to) or 0) < (tonumber(ev.from) or 0) then
      local def = ctx.data.moves and ctx.data.moves[mv.move]
      local added = def and def.effect ~= nil and def.effect ~= "NO_ADDITIONAL_EFFECT"
      local mine = mv.seat == ctx.seat
      -- engine/battle/core.asm:3159
      mv.hit = { animType = mine and (added and 5 or 4) or (added and 2 or 1), sfx = effectiveness(rest, restAt) }
    end
    rows[1] = row
    return rows
  elseif k == "faint" then
    local seat = tonumber(ev.side)
    if seat == nil then return rows end
    ctx.fainted[seat][ctx.active[seat]] = true
    ctx.lastMoveRow = nil
    rows[1] = { op = "faint", seat = seat, index = ctx.active[seat] }
    return rows
  elseif k == "status" then
    local seat = tonumber(ev.side)
    if seat == nil then return rows end
    rows[1] = { op = "status", seat = seat, index = ctx.active[seat], status = STATUS[ev.status] }
    return rows
  elseif k == "stage" then
    local seat = tonumber(ev.side)
    if seat == nil then return rows end
    rows[1] = { op = "stage", seat = seat, stat = ev.stat, delta = ev.delta, sync = ev.sync }
    return rows
  elseif k == "withdraw" then
    local seat, idx = tonumber(ev.side), tonumber(ev.index)
    if seat == nil or not idx then return rows end
    if ev.reason == "start" or ctx.fainted[seat][idx] then return rows end
    rows[1] = { op = "withdraw", seat = seat, index = idx, reason = ev.reason }
    return rows
  elseif k == "sendout" then
    local seat, idx = tonumber(ev.side), tonumber(ev.index)
    if seat == nil or not idx or not ctx.mons[seat][idx] then return rows end
    ctx.active[seat] = idx
    ctx.lastMoveRow = nil
    if ev.reason == "start" then return rows end
    rows[1] = { op = "sendout", seat = seat, index = idx, reason = ev.reason }
    return rows
  end
  return rows
end

TEXT.STRINGID_PKMNFASTASLEEP = function(c, f)
  return rom(c, "_FastAsleepText", Gen1Screen.who(c, f.atk))
end
TEXT.STRINGID_PKMNISCONFUSED = function(c, f)
  return rom(c, "_IsConfusedText", Gen1Screen.who(c, f.atk))
end

function Gen1Screen.rowsFor(ev, ctx, rest, restAt)
  if type(ev) == "table" and ev.kind == "msg" and ev.id == "STRINGID_PKMNFASTASLEEP" then
    local fill = type(ev.fill) == "table" and ev.fill or {}
    local text = Gen1Screen.textFor(ev.id, fill, ctx)
    if not text then return {} end
    local anim = sleepAnim(ctx, fill.atk, "sleep")
    -- engine/battle/core.asm:3341
    if anim and anim.seat == ctx.seat then return { anim, { op = "say", text = text } } end
    return { { op = "say", text = text }, anim }
  end
  return baseRowsFor(ev, ctx, rest, restAt)
end

function Gen1Screen.endRows(result, ctx)
  local rows = {}
  local function say(t) if t then rows[#rows + 1] = { op = "say", text = t } end end
  result = result or {}
  local me, foe = ctx.names.me, ctx.names.foe
  local why, outcome = result.why, result.outcome
  if why == "forfeit" then
    say(Strings("%s forfeited\nthe match!", outcome == "win" and foe or me))
  elseif why == "desync" or why == "disconnect" then
    say(Strings("The link was\nlost."))
    return rows
  elseif why ~= "faint" then
    say(Strings("The battle can't\ncontinue."))
    return rows
  end
  if outcome == "win" then
    -- engine/battle/core.asm:956
    say(RomText(ctx.data, "_TrainerDefeatedText", nil, me, foe))
  elseif outcome == "lose" then
    -- engine/battle/core.asm:1157
    say(RomText(ctx.data, "_LinkBattleLostText", nil, me, foe))
  else
    say(Strings("The match ended\nin a draw!"))
  end
  return rows
end

function Gen1Screen.menuFor(legal)
  local out = { slots = {}, switches = {}, struggle = false, locked = nil, forfeit = false, any = false }
  for _, a in ipairs(legal or {}) do
    if a.kind == "move" then
      if a.locked then
        out.locked = { kind = "move", slot = a.slot, locked = true }
      elseif (tonumber(a.slot) or 0) >= 1 then
        out.slots[a.slot] = true
        out.any = true
      else
        out.struggle = true
      end
    elseif a.kind == "switch" then
      out.switches[a.index] = true
    elseif a.kind == "forfeit" then
      out.forfeit = true
    end
  end
  return out
end

function Gen1Screen.liveMoves(bs, seat, data)
  local m = bs and bs.match
  local mon, b
  if bs and type(bs.activeMon) == "function" then mon, b = bs:activeMon(seat) end
  if not mon then
    local party = m and m:party(seat)
    local i = m and m:active(seat)
    mon = party and i and party[i]
  end
  if not mon then return nil end
  local out, disabled = {}, nil
  for i = 1, 4 do
    local id = mon.moves and tonumber(mon.moves[i])
    if id and id > 0 then
      out[#out + 1] = { id = Gen1Screen.moveKey(data, id) or tostring(id), pp = tonumber(mon.pp and mon.pp[i]) or 0,
        ppUps = tonumber(mon.ppUps and mon.ppUps[i]) or 0 }
      if b and b.expDisabledMove and tonumber(b.expDisabledMove) == id then disabled = #out end
    end
  end
  return out, disabled
end

local OWN_AFTER = { g3u = true, g3uMenu = true, g3uReplace = true, g3uEnd = true }
local STOP = { prompt = true, waiting = true, over = true }

local Host = {}
Host.__index = Host
Host.isOpaque = false

function Host:pump()
  local bs = self.bs
  local ok, err = pcall(bs.update, bs)
  if not ok then
    require("src.core.Logger").warn("g3u gen1: session update failed: %s", tostring(err))
    if not bs.result then pcall(bs.quit, bs) end
  end
  for _, ev in ipairs(bs:events()) do self.pending[#self.pending + 1] = ev end
end

function Host:close()
  if self.closed then return end
  self.closed = true
  local game = self.game
  for i = #game.stack.states, 1, -1 do
    if game.stack.states[i] == self then
      while game.stack:top() ~= self do game.stack:pop() end
      game.stack:pop()
      break
    end
  end
  if self.onDone then
    local cb = self.onDone
    self.onDone = nil
    cb(self.bs.result)
  end
end

function Host:update()
  if self.closed then return end
  if self.battle then
    self:close()
    return
  end
  self:pump()
  for i, ev in ipairs(self.pending) do
    if ev.kind == "ready" then
      table.remove(self.pending, i)
      local ok, err = pcall(self.startBattle, self, ev)
      if not ok then
        require("src.core.Logger").warn("g3u gen1: battle failed to start: %s", tostring(err))
        pcall(self.bs.quit, self.bs)
        self:closeWithText(Strings("The battle can't\ncontinue."))
      end
      return
    end
  end
  if self.bs.result then
    local ctx = { data = self.game.data, names = self.names }
    local rows = Gen1Screen.endRows(self.bs.result, ctx)
    self:closeWithText(rows[1] and rows[1].text or Strings("The link was\nlost."))
  end
end

function Host:closeWithText(text)
  if self.texting then return end
  self.texting = true
  local TextBox = require("src.render.TextBox")
  self.game.stack:push(TextBox.new(self.game, text, function() self:close() end))
end

function Host:draw()
  if self.battle or self.texting then return end
  local Font = require("src.render.Font")
  Font.drawBox(3, 10, 13, 3)
  love.graphics.setColor(0, 0, 0, 1)
  -- engine/link/print_waiting_text.asm:21
  Font.draw(RomText(self.game.data, "WaitingText", nil), 32, 88)
  love.graphics.setColor(1, 1, 1, 1)
end

local function wrapUi(s, inst)
  local base = inst.update
  inst.update = function(self, dt)
    s.g3uHost:pump()
    if s.g3uBs.result and not s.g3uEnding then
      local stack = s.game.stack
      if stack:top() == self then stack:pop() end
      return
    end
    return base(self, dt)
  end
  return inst
end

local function battlerFor(s, seat)
  return seat == s.g3uSeat and s.player or s.enemy
end

local function applyRows(s, rows)
  local data = s.data
  local game = s.game
  local BattleState = require("src.battle.BattleState")
  local Timing = require("src.core.Timing")
  local Sound = require("src.core.Sound")
  local mons = s.g3uCtx.mons
  for _, r in ipairs(rows) do
    if r.op == "say" then
      if r.auto then s:sayAuto(r.text) else s:say(r.text) end
    elseif r.op == "move" then
      local row = { anim = r.move, attackerIsPlayer = r.seat == s.g3uSeat }
      s:act(function()
        row.hit = r.hit
        if row.hit and (row.hit.animType == 4 or row.hit.animType == 5) then
          row.hit.blink = battlerFor(s, r.target)
        end
      end)
      table.insert(s.queue, row)
    elseif r.op == "anim" then
      table.insert(s.queue, { anim = r.name, attackerIsPlayer = r.seat == s.g3uSeat })
    elseif r.op == "hp" then
      s:act(function()
        local mon = mons[r.seat][r.index]
        if not mon then return end
        mon.hp = math.max(0, math.min(r.to, mon.stats.hp))
        local b = battlerFor(s, r.seat)
        if b and b.mon == mon then s:drainNext(b, mon.hp) end
      end)
    elseif r.op == "status" then
      s:act(function()
        local mon = mons[r.seat][r.index]
        if not mon then return end
        mon.status = r.status
        if mon.status ~= "SLP" then mon.sleepTurns = nil end
        local b = battlerFor(s, r.seat)
        if b and b.mon == mon then b.shownStatus = mon.status end
      end)
    elseif r.op == "stage" then
      s:act(function()
        local b = battlerFor(s, r.seat)
        if not b then return end
        b.stages = b.stages or {}
        b.stages[r.stat] = (b.stages[r.stat] or 0) + (tonumber(r.delta) or 0)
      end)
    elseif r.op == "transform" then
      s:act(function()
        local b = battlerFor(s, r.seat)
        if b then b.sprite = s:speciesSprite(r.species, b.isPlayer) or b.sprite end
      end)
    elseif r.op == "faint" then
      s:act(function()
        local b = battlerFor(s, r.seat)
        if not b then return end
        b.fainted = true
        -- engine/battle/core.asm:1042
        if b.isPlayer then
          s.faintCry = Sound.playCry(data, b.mon.species, 4)
        else
          Sound.play(data, "Faint_Fall")
        end
        s.fx = s.fx or {}
        s.fx.faint = { battler = b, frames = Timing.FAINT_SLIDE }
        s:waitNext(Timing.FAINT_SLIDE)
        if b.isPlayer then
          s:waitSfxNext(function() return s.faintCry end)
        else
          s:actNext(function() Sound.play(data, "Faint_Thud") end)
        end
      end)
    elseif r.op == "withdraw" then
      if r.seat == s.g3uSeat then
        s:act(function()
          if not s.player or s.player.fainted then return end
          -- engine/battle/core.asm:2419
          s:sayNextAuto(s:withdrawText(s.player.name), Timing.SWITCH_PLAYER_MON)
          s:queueRetreatAnim()
          s:actNext(function() s.sendingOut = true end)
        end)
      else
        s:act(function()
          if not s.enemy or s.enemy.fainted then return end
          -- engine/battle/trainer_ai.asm:598
          s:sayNext(s:romLine("_AIBattleWithdrawText", s.opponentName, s.enemy.name))
          s:actNext(function() s.enemySendingOut = true end)
        end)
      end
    elseif r.op == "sendout" then
      local quiet = r.reason == "roar"
      if r.seat == s.g3uSeat then
        s:act(function()
          local mon = mons[r.seat][r.index]
          s.player = BattleState.makeBattler(data, mon, true, nil)
          s.g3uShown[r.seat] = r.index
          s:syncSides()
          s.menuIndex, s.moveIndex, s.playerMoveListIndex = 1, 1, 1
          s.sendingOut = true
          if not quiet then s:sayNextAuto(s:sendOutText(s.player.name)) end
          s:animNext("POOF_ANIM", false)
          s:actNext(function()
            s.sendingOut = false
            s:startGrowIn(s.player)
            s:waitSfxNext(s:playEntranceCry(s.player))
          end)
        end)
      else
        s:act(function()
          local mon = mons[r.seat][r.index]
          s.enemy = BattleState.makeBattler(data, mon, false, nil)
          s.g3uShown[r.seat] = r.index
          s:syncSides()
          s.enemySendingOut = true
          if not quiet then
            -- engine/battle/core.asm:1421
            s:sayNextAuto(s:romLine("_TrainerSentOutText", s.opponentName, s.enemy.name))
          end
          s:actNext(function()
            s.enemySendingOut = false
            s:startGrowIn(s.enemy)
            s:queueEnemySendOutCry(false)
          end)
        end)
      end
    end
  end
  return game
end

local function submit(s, act)
  local bs = s.g3uBs
  s.g3uWaiting = true
  s.phase = "g3u"
  s.msgHold, s.shown = nil, nil
  if not bs.result then bs:choose(act) end
end

local function openReplacement(s)
  s.g3uPick = nil
  s.phase = "messages"
  s.afterQueue = "g3uReplace"
  local legal = Gen1Screen.menuFor(s.g3uBs:legal())
  s:ui(function()
    return wrapUi(s, s:buildScreen("PartyMenu", {
      battle = s,
      party = s.playerParty,
      forceSwitch = true,
      keepOpen = true,
      onSwitch = function(mon, menu)
        local idx
        for i, m in ipairs(s.playerParty) do if m == mon then idx = i end end
        if not idx or not legal.switches[idx] then
          -- engine/battle/core.asm:1484
          if menu then menu:refuse(s:romLine("_NoWillText")) end
          return
        end
        s.g3uPick = { kind = "switch", index = idx }
        if menu then menu:close() end
      end,
    }))
  end)
end

local function syncMenu(s)
  local bs = s.g3uBs
  local moves, disabled = Gen1Screen.liveMoves(bs, s.g3uSeat, s.data)
  if moves and #moves > 0 and s.player then
    s.player.curMoves = moves
    s.player.disabledSlot = disabled
  end
  s.g3uLegal = Gen1Screen.menuFor(bs:legal())
end

local function handleStop(s, ev)
  local bs = s.g3uBs
  if ev.kind == "waiting" then
    s.g3uWaiting = true
    return
  end
  if ev.kind == "over" then
    s.g3uEnding = true
    s.g3uWaiting = false
    local result = { outcome = ev.outcome, why = ev.why, detail = ev.detail }
    if result.outcome == "win" and result.why == "faint" then s:playVictoryMusic() end
    applyRows(s, Gen1Screen.endRows(result, s.g3uCtx))
    s.phase = "messages"
    s.afterQueue = "g3uEnd"
    return
  end
  if ev.what == "move" then
    if bs.phase ~= "choose" then return end
    syncMenu(s)
    s.g3uWaiting = false
    if s.g3uLegal.locked then return submit(s, s.g3uLegal.locked) end
    s.phase = "menu"
  elseif ev.what == "replace" then
    if bs.phase ~= "replace" then return end
    s.g3uWaiting = false
    openReplacement(s)
  end
end

local function advance(s)
  local pending = s.g3uHost.pending
  while pending[1] do
    local ev = pending[1]
    if STOP[ev.kind] then
      table.remove(pending, 1)
      handleStop(s, ev)
      if s.phase ~= "g3u" then return end
    else
      while pending[1] and not STOP[pending[1].kind] do
        local e = table.remove(pending, 1)
        local ok, rows = pcall(Gen1Screen.rowsFor, e, s.g3uCtx, pending, 1)
        if ok then applyRows(s, rows) end
      end
      if #s.queue > 0 then
        s.g3uWaiting = false
        s.phase = "messages"
        s.afterQueue = "g3u"
        return
      end
    end
  end
end

local function afterOwn(s, dest)
  if dest == "g3uEnd" then
    s:finish()
    return
  end
  s.msgHold, s.shown = nil, nil
  if dest == "g3uMenu" then
    local pick = s.g3uPick
    s.g3uPick = nil
    if pick then return submit(s, pick) end
    s.phase = "menu"
  elseif dest == "g3uReplace" then
    local pick = s.g3uPick
    s.g3uPick = nil
    if pick then
      s.g3uWaiting = true
      s.phase = "g3u"
      if not s.g3uBs.result then s.g3uBs:pickReplacement(pick.index) end
    else
      openReplacement(s)
    end
  else
    s.phase = "g3u"
  end
end

local function install(s, host)
  local BattleState = require("src.battle.BattleState")
  local game = host.game
  local bs = host.bs
  local baseUpdate = BattleState.update

  s.enterCommandMenu = function(self) self.phase = "g3u" end
  s.swapMoves = function() end

  s.enter = function(self, ...)
    BattleState.enter(self, ...)
    for i, item in ipairs(self.queue) do
      if item.text == self.introText then
        table.insert(self.queue, i + 1, { text = Strings("UNION RULES: GEN 3\nbattle mechanics.") })
        table.insert(self.queue, i + 2, { text = Strings("No abilities or\nheld items.") })
        break
      end
    end
  end

  s.chooseMenu = function(self, choice)
    if self.phase ~= "menu" then return nil, "battle menu is not active" end
    if choice == "fight" then
      local legal = self.g3uLegal or Gen1Screen.menuFor(bs:legal())
      if not legal.any and legal.struggle then
        self:say(self:romLine("_NoMovesLeftText", self.player.name))
        self.g3uPick = { kind = "move", slot = 0 }
        self.phase = "messages"
        self.afterQueue = "g3uMenu"
        return true
      end
      self.phase = "moveSelect"
      self.moveIndex = math.max(1, math.min(self.moveIndex, #self.player.curMoves))
      self.moveSwapIndex = nil
      return true
    end
    return BattleState.chooseMenu(self, choice)
  end

  s.chooseMove = function(self, index)
    if self.phase ~= "moveSelect" then return nil, "move menu is not active" end
    local move = self.player.curMoves[index]
    if not move then return nil, "invalid move slot" end
    self.moveIndex = index
    local legal = self.g3uLegal or Gen1Screen.menuFor(bs:legal())
    if not legal.slots[index] then
      if self.player.disabledSlot == index or (move.pp or 0) > 0 then
        self:say(self:romLine("_MoveDisabledText"))
      else
        self:say(self:romLine("_MoveNoPPText"))
      end
      self.phase = "messages"
      self.afterQueue = "g3uMenu"
      return true
    end
    self.playerMoveListIndex = index
    submit(self, { kind = "move", slot = index })
    return true
  end

  s.resolveTurn = function() end
  s.resolveSwitch = function() end

  s.tryRun = function(self)
    self.g3uPick = nil
    self.phase = "messages"
    self.afterQueue = "g3uMenu"
    self:sayAuto(Strings("Forfeit the\nmatch?"))
    self:ui(function()
      local ChoiceBox = require("src.ui.ChoiceBox")
      return wrapUi(self, ChoiceBox.new(game, function(yes)
        if yes then self.g3uPick = { kind = "forfeit" } end
      end, { defaultNo = true }))
    end)
  end

  s.openItems = function(self)
    self:say(Strings("Items can't be\nused in a link\nbattle!"))
    self.phase = "messages"
    self.afterQueue = "g3uMenu"
  end

  s.openParty = function(self)
    self.g3uPick = nil
    self.phase = "messages"
    self.afterQueue = "g3uMenu"
    local legal = self.g3uLegal or Gen1Screen.menuFor(bs:legal())
    self:ui(function()
      return wrapUi(self, self:buildScreen("PartyMenu", {
        battle = self,
        party = self.playerParty,
        keepOpen = true,
        onSwitch = function(mon, menu)
          local idx
          for i, m in ipairs(self.playerParty) do if m == mon then idx = i end end
          local refusal
          -- engine/battle/core.asm:2403
          if mon == self.player.mon then
            refusal = self:romLine("_AlreadyOutText", self.player.name)
          elseif mon.hp <= 0 then
            refusal = self:romLine("_NoWillText")
          elseif not idx or not legal.switches[idx] then
            refusal = self:romLine("_CantEscapeText")
          end
          if refusal then
            if menu then menu:refuse(refusal) end
            return
          end
          self.g3uPick = { kind = "switch", index = idx }
          if menu then menu:close() end
        end,
      }))
    end)
  end

  s.update = function(self, dt)
    if self.g3uFinished then return end
    host:pump()
    if bs.result and not self.g3uEnding and (self.phase == "menu" or self.phase == "moveSelect") then
      self.phase = "g3u"
    end
    if self.phase == "moveSelect" then self.moveSwapIndex = nil end
    if self.phase == "messages" and OWN_AFTER[self.afterQueue] then
      self:tickFx()
      if not self:updateQueue() then
        local dest = self.afterQueue
        self.afterQueue, self.nextInsert, self.waitFrames = nil, nil, nil
        afterOwn(self, dest)
      end
      self:tickTextScroll()
      return
    end
    if self.phase == "g3u" then
      self:tickFx()
      advance(self)
      return
    end
    return baseUpdate(self, dt)
  end

  s.draw = function(self, ...)
    BattleState.draw(self, ...)
    if self.phase == "g3u" and self.g3uWaiting and not self.g3uEnding then
      local Font = require("src.render.Font")
      Font.drawBox(3, 10, 13, 3)
      love.graphics.setColor(0, 0, 0, 1)
      -- engine/link/print_waiting_text.asm:21
      Font.draw(RomText(self.data, "WaitingText", nil), 32, 88)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  s.finish = function(self)
    if self.g3uFinished then return end
    self.g3uFinished = true
    require("src.core.Sound").stopLoop("Low_Health_Alarm")
    require("src.core.Music").restoreMap(self.data)
    if game.stack:top() == self then game.stack:pop() end
    local Transition = require("src.render.Transition")
    game.stack:push(Transition.battleReturn(game, function() host:close() end))
  end
end

function Host:startBattle(ready)
  local game, bs = self.game, self.bs
  local BattleState = require("src.battle.BattleState")
  local data = game.data
  local seat = bs.seat
  local peer = 1 - seat
  local ctx, why = Gen1Screen.newCtx(data, seat, ready.parties, self.names)
  if not ctx then error("g3u gen1: " .. tostring(why)) end
  for _, e in ipairs(self.pending) do
    if e.kind == "sendout" and e.reason == "start" and ctx.mons[e.side] and ctx.mons[e.side][e.index] then
      ctx.active[e.side] = e.index
    end
  end
  local myMon = ctx.mons[seat][ctx.active[seat]]
  local foeMon = ctx.mons[peer][ctx.active[peer]]
  if not myMon or not foeMon then error("g3u gen1: empty party") end
  local dex = game.save and game.save.pokedex
  local seen = dex and dex.seen and dex.seen[foeMon.species]
  local s = BattleState.newWild(game, foeMon.species, foeMon.level)
  if dex and dex.seen then dex.seen[foeMon.species] = seen end
  s.dead = nil
  s.kind = "link"
  s.g3u = true
  s.g3uHost, s.g3uBs, s.g3uCtx, s.g3uSeat = self, bs, ctx, seat
  s.g3uShown = { [seat] = ctx.active[seat], [peer] = ctx.active[peer] }
  s.player = BattleState.makeBattler(data, myMon, true, nil)
  s.enemy = BattleState.makeBattler(data, foeMon, false, nil)
  s.playerParty = ctx.mons[seat]
  s.enemyParty = ctx.mons[peer]
  s.opponentName = ctx.names.foe
  -- data/text/text_2.asm:1257
  s.introText = s:romLine("_TrainerWantsToFightText", ctx.names.foe)
  install(s, self)
  self.battle = s
  game.stack:push(s)
end

function Gen1Screen.start(game, bs, opts)
  if type(game) ~= "table" or type(bs) ~= "table" then return nil, "bad_args" end
  opts = opts or {}
  local names = opts.names or {}
  local seat = bs.seat or 0
  local me = names.me or (bs.names and bs.names[seat]) or (game.save and game.save.player and game.save.player.name)
  local foe = names.foe or (bs.names and bs.names[1 - seat]) or Strings("FOE")
  local host = setmetatable({
    game = game, bs = bs, onDone = opts.onDone, pending = {},
    names = { me = me or "?", foe = foe },
  }, Host)
  game.stack:push(host)
  return { host = host, bs = bs, battle = function() return host.battle end }
end

Gen1Screen.Host = Host

return Gen1Screen
