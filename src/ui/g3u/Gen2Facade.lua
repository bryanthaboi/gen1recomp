local Battle = require("src.battle.gen2.Battle")
local Effects = require("src.battle.gen2.Effects")
local Identity = require("src.online.xgen.Identity")
local RomText = require("src.core.RomText")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local Gen2Facade = {}

-- engine/link/link.asm:443
Gen2Facade.LINK_CLASS = "CAL"

Gen2Facade.FAIL_HOLD_FRAMES = 240

Gen2Facade.STATUS = {
  SLP = "sleep", PSN = "poison", TOX = "toxic", BRN = "burn", PAR = "paralyze", FRZ = "freeze",
}

Gen2Facade.STATS = {
  attack = "attack", defense = "defense", speed = "speed", spAtk = "specialAttack",
  spDef = "specialDefense", accuracy = "accuracy", evasion = "evasion",
  atk = "attack", def = "defense", spe = "speed", spa = "specialAttack", spd = "specialDefense",
}

Gen2Facade.WEATHER = {
  SUN = "sun", SUNNY = "sun", HARSH_SUN = "sun", RAIN = "rain", RAINY = "rain", DOWNPOUR = "rain",
  SAND = "sandstorm", SANDSTORM = "sandstorm",
}

Gen2Facade.ANIMS = {
  status = {
    SLEEP = "ANIM_SLP", POISON = "ANIM_PSN", BURN = "ANIM_BRN", PARALYSIS = "ANIM_PAR",
    FREEZE = "ANIM_FRZ", CONFUSION = "ANIM_CONFUSED", INFATUATION = "ANIM_IN_LOVE",
    NIGHTMARE = "ANIM_IN_NIGHTMARE",
  },
  general = {
    LEECH_SEED_DRAIN = "ANIM_SAP", SANDSTORM_CONTINUES = "ANIM_IN_SANDSTORM",
  },
}

Gen2Facade.MOVE_ANIMS = { TURN_TRAP = "arg", FUTURE_SIGHT_HIT = 248 }

Gen2Facade.FIELDS = {
  "player", "enemy", "party", "enemyParty", "trainer", "wild", "over", "outcome", "battleType",
  "random", "participants", "payDay", "amuletCoin", "timeOfDay", "boxFilled", "data",
  "inBattleTowerBattle", "linkBattle", "events", "turnOpen", "pendingSwitch", "pendingEnemySwitch",
  "forcedSwitch", "mirrored",
}

Gen2Facade.NILABLE = {
  battleType = true, payDay = true, amuletCoin = true, timeOfDay = true, boxFilled = true,
  outcome = true, inBattleTowerBattle = true, turnOpen = true, pendingSwitch = true,
  pendingEnemySwitch = true, forcedSwitch = true, mirrored = true,
}

Gen2Facade.METHODS = {
  "takeTurn", "takeEvents", "volatile", "lockedInMove", "moveDisabled", "hasUsableMoves",
  "switchLocked", "switch", "shiftSwitch", "resolveForget", "declineForget", "partyMoves",
  "clearAllVolatiles", "useBattleItem", "tryRun", "endBattle", "forcedReplacement",
}

local S = Strings.source
local T = {
  rules1 = S("UNION RULES!"),
  rules2 = S("GEN 3 battle rules.\nNo abilities or\nheld items."),
  waiting = S("Waiting..."),
  waitingFor = S("Waiting for\n%s..."),
  runAgain = S("Choose RUN again\nto forfeit."),
  cantNow = S("That can't be\nchosen now."),
  noMore = S("You have no more POKéMON!"),
  draw = S("The battle ended\nin a draw!"),
  foeForfeit = S("%s forfeited\nthe match!"),
  meForfeit = S("You forfeited\nthe match."),
  desync = S("The link fell out\nof sync. It's a draw."),
  left = S("%s left the battle."),
  illegal = S("The other game sent\na bad move. Draw."),
  broken = S("The battle could\nnot continue."),
  woreOff = S("%s's %s wore off!"),
}
Gen2Facade.TEXT = T

local GENDER = { [0] = "male", [1] = "female" }

local IDLE = {
  menu = true, moves = true, ["locked-in"] = true, ["link-wait"] = true, ["link-hold"] = true,
  ["refuse-menu"] = true, ["refuse-move"] = true, ["refuse-switch"] = true,
}
Gen2Facade.IDLE = IDLE

local Facade = {}
Facade.__index = Facade
Gen2Facade.Facade = Facade

local function lcg(seed)
  local s = (tonumber(seed) or 1) % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(n)
    s = (s * 16807) % 2147483647
    n = math.max(1, math.floor(tonumber(n) or 1))
    return s % n
  end
end

function Gen2Facade.new(game, bs, opts)
  opts = opts or {}
  local names = opts.names or {}
  local seat = bs.seat
  local self = setmetatable({
    game = game, bs = bs, seat = seat, peer = 1 - seat,
    data = (game and game.data) or {},
    myName = names.me or (bs.names and bs.names[seat]) or "PLAYER",
    foeName = names.foe or (bs.names and bs.names[1 - seat]) or "FOE",
    views = { [0] = {}, [1] = {} }, activeIndex = {},
    party = {}, enemyParty = {}, player = nil, enemy = nil,
    wild = false, over = false, outcome = nil, linkBattle = true,
    participants = {}, events = {}, vol = setmetatable({}, { __mode = "k" }),
    awaiting = nil, ready = false, ended = false, weather = nil,
    random = lcg(bs.seed),
  }, Facade)
  self.trainer = { name = self.foeName, classId = opts.foeClass or Gen2Facade.LINK_CLASS }
  return self
end

function Facade:sideName(seat)
  if seat == nil then return nil end
  return seat == self.seat and "player" or "enemy"
end

function Facade:speciesKey(n)
  if not self._dex then
    self._dex = {}
    for key, def in pairs(self.data.pokemon or {}) do
      if type(def) == "table" then
        local dex = tonumber(def.dex) or tonumber(def.index)
        if dex and self._dex[dex] == nil then self._dex[dex] = key end
      end
    end
  end
  return self._dex[tonumber(n) or -1]
end

function Facade:moveKey(id)
  if not self._moves then
    self._moves = {}
    for key, def in pairs(self.data.moves or {}) do
      if type(def) == "table" and tonumber(def.index) then self._moves[def.index] = key end
    end
  end
  return self._moves[tonumber(id) or -1]
end

function Facade:moveName(id)
  local key = self:moveKey(id)
  local def = key and self.data.moves[key]
  return (def and def.name) or tostring(key or id or "?")
end

function Facade:speciesName(n)
  local key = self:speciesKey(n)
  local def = key and self.data.pokemon[key]
  return (def and def.name) or tostring(key or n or "?")
end

function Facade:viewOf(rec)
  local key = self:speciesKey(rec.species)
  local def = key and self.data.pokemon[key] or nil
  local moves, slots = {}, {}
  for i, mv in ipairs(rec.moves or {}) do
    moves[i] = { id = self:moveKey(mv.id) or mv.id, national = mv.id, pp = mv.pp, maxPp = mv.pp,
      ppUps = mv.ppUps or 0 }
    slots[mv.id] = i
  end
  local nick = rec.nickname
  if type(nick) ~= "string" or nick == "" then nick = def and def.name or nil end
  return {
    species = key or rec.species, national = rec.species, nickname = nick,
    name = def and def.name or nil, level = rec.level, hp = rec.hp, maxHp = rec.maxHp,
    status = nil, gender = GENDER[rec.gender], moves = moves, engineSlots = slots,
    types = def and def.types or nil, friendship = rec.friendship,
    stats = { hp = rec.maxHp, attack = rec.atk, defense = rec.def, speed = rec.speed,
      specialAttack = rec.spAtk, specialDefense = rec.spDef },
  }
end

function Facade:onReady(ev)
  for seat = 0, 1 do
    local list = {}
    for i, rec in ipairs((ev.parties and ev.parties[seat]) or {}) do list[i] = self:viewOf(rec) end
    self.views[seat] = list
  end
  self.party = self.views[self.seat]
  self.enemyParty = self.views[self.peer]
  self:setActive(self.seat, 1)
  self:setActive(self.peer, 1)
  self.ready = true
end

function Facade:setActive(seat, index)
  self.activeIndex[seat] = index
  local v = self.views[seat][index]
  if seat == self.seat then
    self.player = v
    self.participants[index] = true
  else
    self.enemy = v
  end
  return v
end

function Facade:active(seat)
  return self.views[seat] and self.views[seat][self.activeIndex[seat] or 1] or nil
end

function Facade:ref(r)
  if type(r) == "string" then
    if r == "player" then return self:active(0) end
    if r == "enemy" then return self:active(1) end
    return nil
  end
  if type(r) ~= "table" or r.side == nil then return nil end
  local list = self.views[r.side]
  return list and (list[r.index] or self:active(r.side)) or nil
end

function Facade:nameOf(v)
  if not v then return "?" end
  return v.nickname or v.name or tostring(v.species or "?")
end

local function romLine(self, label, ...)
  return TextBox.strip(RomText(self.data, label, nil, ...))
end

function Facade:isFoe(r)
  return (type(r) == "table") and (r.side ~= self.seat) or (r == "enemy")
end

-- engine/battle/used_move_text.asm:1
function Facade:usedMoveText(ref, mv)
  return romLine(self, "_ActorNameText", { USER = self:N(ref) }) .. romLine(self, "_UsedMove1Text")
    .. romLine(self, "_MoveNameText", { STRBUF = self:moveName(mv) }) .. romLine(self, "_EndUsedMove1Text")
end

-- ../pokecrystal/engine/battle/core.asm:7685, :7707
function Facade:goMonText(v)
  local name = self:nameOf(v)
  if self.data.text and self.data.text.BattleMonNicknameText then
    return romLine(self, "GoMonText") .. romLine(self, "BattleMonNicknameText", name)
  end
  return romLine(self, "GoMonText", name)
end

function Facade:faintText(seat, v)
  v = v or self:active(seat)
  local label = self:sideName(seat) == "enemy" and "BattleText_EnemyMonFainted" or "BattleText_MonFainted"
  return romLine(self, label, { STRBUF = self:nameOf(v) })
end

-- home/text.asm:330-345
function Facade:N(r)
  local v = self:ref(r)
  if not v then return "?" end
  if self:isFoe(r) then return romLine(self, "EnemyText") .. self:nameOf(v) end
  return self:nameOf(v)
end

local function moveOf(v)
  if type(v) == "table" then return v.move end
  return tonumber(v)
end

local function stageText(self, ref, stat, delta)
  return Effects.stageMessage(self.data, self:N(ref), Gen2Facade.STATS[stat] or stat, tonumber(delta) or 0)
end

local function wontText(self, ref, stat, up)
  local label = Effects.statName(self.data, Gen2Facade.STATS[stat] or stat)
  if up then return romLine(self, "WontRiseAnymoreText", { USER = self:N(ref), STRBUF = label }) end
  return romLine(self, "WontDropAnymoreText", { TARGET = self:N(ref), STRBUF = label })
end

local function pick(f, key)
  if type(key) ~= "table" then return f[key] end
  for _, k in ipairs(key) do
    if f[k] ~= nil then return f[k] end
  end
  return nil
end

local function say(label, slots)
  return function(self, f)
    if not slots then return romLine(self, label) end
    local fill = {}
    for slot, key in pairs(slots) do
      if type(key) == "function" then
        fill[slot] = key(self, f)
      else
        fill[slot] = self:N(pick(f, key))
      end
    end
    return romLine(self, label, fill)
  end
end

local function role(src, key)
  return function(self, f) return Strings(src, self:N(f[key])) end
end

local function inflict(status, key)
  return function(self, f)
    return romLine(self, Battle.STATUSES[status].inflictLabel, { TARGET = self:N(f[key]) })
  end
end

local function weatherText(phase, kind)
  return function(self) return Effects.weatherText(self.data, phase, kind) end
end

local function charge(effect, moveId)
  return function(self, f) return Effects.chargeText(self.data, effect, moveId, self:N(f.atk)) end
end

local function buffMove(self, f) return self:moveName(moveOf(f.buff1)) end
local function buffNum(_, f) return tonumber(f.buff1) or 0 end

local function opponent(self, f)
  if f.def ~= nil then return self:N(f.def) end
  local atk = f.atk
  if type(atk) == "table" and atk.side ~= nil then return self:N({ side = 1 - atk.side }) end
  return self:N(nil)
end

local MSG = {
  STRINGID_ATTACKERSSTATROSE = function(self, f) return stageText(self, f.atk, f.stat, f.delta) end,
  STRINGID_ATTACKERSSTATFELL = function(self, f) return stageText(self, f.atk, f.stat, f.delta) end,
  STRINGID_DEFENDERSSTATROSE = function(self, f) return stageText(self, f.def, f.stat, f.delta) end,
  STRINGID_DEFENDERSSTATFELL = function(self, f) return stageText(self, f.def, f.stat, f.delta) end,
  STRINGID_STATSWONTINCREASE = function(self, f) return wontText(self, f.atk or f.def, f.buff1, true) end,
  STRINGID_STATSWONTDECREASE = function(self, f) return wontText(self, f.def or f.atk, f.buff1, false) end,
  STRINGID_ATTACKMISSED = say("AttackMissedText", { USER = "atk" }),
  STRINGID_BELLCHIMED = say("BellChimedText"),
  STRINGID_BUTITFAILED = say("ButItFailedText"),
  STRINGID_MIRRORMOVEFAILED = say("MirrorMoveFailedText"),
  STRINGID_BUTNOTHINGHAPPENED = say("NothingHappenedText"),
  STRINGID_BUTNOEFFECT = say("NothingHappenedText"),
  STRINGID_COINSSCATTERED = say("CoinsScatteredText"),
  STRINGID_CRITICALHIT = say("CriticalHitText"),
  STRINGID_FAINTINTHREE = say("StartPerishText"),
  STRINGID_HITXTIMES = function(self, f)
    local label = self:isFoe(f.atk) and "EnemyHitTimesText" or "PlayerHitTimesText"
    return romLine(self, label, { NUM = buffNum(self, f) })
  end,
  STRINGID_ITDOESNTAFFECT = say("DidntAffect1Text", { TARGET = "def" }),
  STRINGID_PKMNUNAFFECTED = say("DidntAffect1Text", { TARGET = "def" }),
  STRINGID_PKMNWASNTAFFECTED = say("DidntAffect1Text", { TARGET = "def" }),
  STRINGID_ITHURTCONFUSION = say("HurtItselfText"),
  STRINGID_MAGNITUDESTRENGTH = say("MagnitudeText", { NUM = buffNum }),
  STRINGID_NOTVERYEFFECTIVE = say("NotVeryEffectiveText"),
  STRINGID_SUPEREFFECTIVE = say("SuperEffectiveText"),
  STRINGID_ONEHITKO = say("OneHitKOText"),
  STRINGID_PKMNALREADYASLEEP = say("AlreadyAsleepText", { TARGET = "def" }),
  STRINGID_PKMNALREADYASLEEP2 = say("AlreadyAsleepText", { TARGET = "atk" }),
  STRINGID_PKMNALREADYCONFUSED = say("AlreadyConfusedText", { TARGET = "def" }),
  STRINGID_PKMNALREADYPOISONED = say("AlreadyPoisonedText", { TARGET = "def" }),
  STRINGID_PKMNISALREADYPARALYZED = say("AlreadyParalyzedText", { TARGET = "def" }),
  STRINGID_PKMNALREADYHASBURN = role("%s's already burned!", "def"),
  STRINGID_PKMNATTACK = say("BeatUpAttackText", { STRBUF = function(self, f)
    local sp = type(f.buff1) == "table" and f.buff1.species
    return sp and self:speciesName(sp) or "?"
  end }),
  STRINGID_PKMNBADLYPOISONED = inflict("toxic", "eff"),
  STRINGID_PKMNWASPOISONED = inflict("poison", "eff"),
  STRINGID_PKMNWASBURNED = inflict("burn", "eff"),
  STRINGID_PKMNWASFROZEN = inflict("freeze", "eff"),
  STRINGID_PKMNWASPARALYZED = inflict("paralyze", "eff"),
  STRINGID_PKMNFELLASLEEP = inflict("sleep", "eff"),
  STRINGID_PKMNWASCONFUSED = inflict("confuse", "eff"),
  STRINGID_PKMNBRACEDITSELF = say("BracedItselfText", { USER = "atk" }),
  STRINGID_PKMNBUFFETEDBYSANDSTORM = say("SandstormHitsText", { USER = "atk" }),
  STRINGID_PKMNCHANGEDTYPE = say("TransformedTypeText", { USER = "atk", STRBUF = function(_, f)
    local t = type(f.buff1) == "table" and f.buff1.type
    return t and (Identity.GEN3_TYPES[t] == "MYSTERY" and "???" or Identity.GEN3_TYPES[t]) or "?"
  end }),
  STRINGID_PKMNCOPIEDSTATCHANGES = say("CopiedStatsText", { USER = "atk", TARGET = "def" }),
  STRINGID_PKMNCOVEREDBYVEIL = say("CoveredByVeilText", { USER = "atk" }),
  STRINGID_PKMNUSEDSAFEGUARD = say("CoveredByVeilText", { USER = "atk" }),
  STRINGID_PKMNCRASHED = say("CrashedText", { USER = "atk" }),
  STRINGID_PKMNCUTHPMAXEDATTACK = say("BellyDrumText", { USER = "atk" }),
  STRINGID_PKMNDREAMEATEN = say("DreamEatenText", { TARGET = "def" }),
  STRINGID_PKMNDUGHOLE = charge("EFFECT_FLY", "DIG"),
  STRINGID_PKMNENDUREDHIT = say("EnduredText", { TARGET = "def" }),
  STRINGID_PKMNENERGYDRAINED = say("SuckedHealthText", { TARGET = "def" }),
  STRINGID_PKMNEVADEDATTACK = say("EvadedText", { TARGET = "def" }),
  STRINGID_PKMNAVOIDEDATTACK = say("EvadedText", { TARGET = "def" }),
  STRINGID_PKMNFASTASLEEP = say("FastAsleepText", { USER = "atk" }),
  STRINGID_PKMNFATIGUECONFUSION = role("%s became confused due to fatigue!", "atk"),
  STRINGID_PKMNFELLINLOVE = say("FellInLoveText", { TARGET = "def" }),
  STRINGID_PKMNFLEWHIGH = charge("EFFECT_FLY"),
  STRINGID_PKMNFLINCHED = say("FlinchedText", { USER = "atk" }),
  STRINGID_PKMNFORESAWATTACK = say("ForesawAttackText", { USER = "atk" }),
  STRINGID_PKMNFREEDFROM = say("BattleText_UserWasReleasedFromStringBuffer1",
    { USER = "atk", STRBUF = buffMove }),
  STRINGID_PKMNGETTINGPUMPED = say("GettingPumpedText", { USER = "atk" }),
  STRINGID_PKMNGOTENCORE = say("GotAnEncoreText", { TARGET = "def" }),
  STRINGID_PKMNENCOREENDED = say("BattleText_TargetsEncoreEnded", { TARGET = "atk" }),
  STRINGID_PKMNHASSUBSTITUTE = say("HasSubstituteText", { USER = "atk" }),
  STRINGID_PKMNHEALEDCONFUSION = say("ConfusedNoMoreText", { USER = "atk" }),
  STRINGID_PKMNHITWITHRECOIL = say("RecoilText", { USER = "atk" }),
  STRINGID_PKMNHPFULL = say("HPIsFullText", { USER = "def" }),
  STRINGID_PKMNHURTBY = say("BattleText_UsersHurtByStringBuffer1", { USER = "atk", STRBUF = buffMove }),
  STRINGID_PKMNHURTBYBURN = say("HurtByBurnText", { USER = "atk" }),
  STRINGID_PKMNHURTBYPOISON = say("HurtByPoisonText", { USER = "atk" }),
  STRINGID_PKMNHURTBYSPIKES = say("BattleText_UserHurtBySpikes", { USER = "scrActive" }),
  STRINGID_PKMNIDENTIFIED = say("IdentifiedText", { USER = "atk", TARGET = "def" }),
  STRINGID_PKMNIMMOBILIZEDBYLOVE = say("InfatuationText", { USER = "atk" }),
  STRINGID_PKMNINLOVE = say("InLoveWithText", { USER = "atk", TARGET = { "scrActive", "def" } }),
  STRINGID_PKMNISCONFUSED = say("IsConfusedText", { USER = "atk" }),
  STRINGID_PKMNISFROZEN = say("FrozenSolidText", { USER = "atk" }),
  STRINGID_PKMNISGLOWING = charge("EFFECT_SKY_ATTACK"),
  STRINGID_PKMNISPARALYZED = say("FullyParalyzedText", { USER = "atk" }),
  STRINGID_PKMNLEARNEDMOVE2 = say("MimicLearnedMoveText", { USER = "atk", STRBUF = buffMove }),
  STRINGID_PKMNLOWEREDHEAD = charge("EFFECT_SKULL_BASH"),
  STRINGID_PKMNMADESUBSTITUTE = say("MadeSubstituteText", { USER = "atk" }),
  STRINGID_TOOWEAKFORSUBSTITUTE = say("TooWeakSubText"),
  STRINGID_PKMNMOVEDISABLEDNOMORE = say("DisabledNoMoreText", { USER = "atk" }),
  STRINGID_PKMNMOVEISDISABLED = say("DisabledMoveText", { USER = { "active", "atk" }, STRBUF = function(self, f)
    return self:moveName(moveOf(f.currentMove))
  end }),
  STRINGID_PKMNMOVEWASDISABLED = say("WasDisabledText", { TARGET = "def", STRBUF = buffMove }),
  STRINGID_PKMNMUSTRECHARGE = say("MustRechargeText", { USER = "atk" }),
  STRINGID_PKMNPERISHCOUNTFELL = say("PerishCountText", { USER = "atk", NUM = buffNum }),
  STRINGID_PKMNPROTECTEDBYMIST = say("ProtectedByMistText", { TARGET = "scrActive" }),
  STRINGID_PKMNPROTECTEDITSELF = say("ProtectingItselfText", { TARGET = "def" }),
  STRINGID_PKMNPROTECTEDITSELF2 = say("ProtectedItselfText", { USER = "atk" }),
  STRINGID_PKMNRAGEBUILDING = say("RageBuildingText", { USER = "def" }),
  STRINGID_PKMNRAISEDDEF = say("ReflectEffectText", { USER = "atk" }),
  STRINGID_PKMNRAISEDSPDEF = say("LightScreenEffectText", { USER = "atk" }),
  STRINGID_PKMNREDUCEDPP = say("SpiteEffectText", { TARGET = "def", STRBUF = buffMove,
    NUM = function(_, f) return tonumber(f.buff2) or 0 end }),
  STRINGID_PKMNREGAINEDHEALTH = say("RegainedHealthText", { USER = "def" }),
  STRINGID_PKMNSAFEGUARDEXPIRED = say("BattleText_SafeguardFaded", { USER = "atk" }),
  STRINGID_PKMNSAPPEDBYLEECHSEED = say("LeechSeedSapsText", { USER = "atk" }),
  STRINGID_PKMNSEEDED = say("WasSeededText", { TARGET = "def" }),
  STRINGID_PKMNSHROUDEDINMIST = say("MistText", { USER = "atk" }),
  STRINGID_PKMNSKETCHEDMOVE = say("SketchedText", { USER = "atk", STRBUF = buffMove }),
  STRINGID_PKMNSLEPTHEALTHY = say("RestedText", { USER = "atk" }),
  STRINGID_PKMNWENTTOSLEEP = say("WentToSleepText", { USER = "atk" }),
  STRINGID_PKMNSQUEEZEDBYBIND = say("UsedBindText", { USER = "atk", TARGET = "def" }),
  STRINGID_PKMNWRAPPEDBY = say("WrappedByText", { USER = "atk", TARGET = "def" }),
  STRINGID_PKMNCLAMPED = say("ClampedByText", { USER = "atk", TARGET = "def" }),
  STRINGID_PKMNTRAPPEDINVORTEX = function(self, f)
    return romLine(self, Battle.trapTextLabel(self, "WHIRLPOOL"), { TARGET = self:N(f.def) })
  end,
  STRINGID_PKMNSTORINGENERGY = say("StoringEnergyText", { USER = "atk" }),
  STRINGID_PKMNSUBSTITUTEFADED = say("SubFadedText", { TARGET = "def" }),
  STRINGID_SUBSTITUTEDAMAGED = say("SubTookDamageText", { TARGET = "def" }),
  STRINGID_PKMNSXWOREOFF = function(self, f)
    local mv = moveOf(f.buff1)
    local seat = f.atk == "enemy" and 1 or 0
    local label = romLine(self, self:sideName(seat) == "player" and "HandleScreens.Your" or "HandleScreens.Enemy")
    if mv == 113 then return romLine(self, "BattleText_MonsLightScreenFell", { STRBUF = label }) end
    if mv == 115 then return romLine(self, "BattleText_MonsReflectFaded", { STRBUF = label }) end
    return Strings(T.woreOff, label, self:moveName(mv))
  end,
  STRINGID_PKMNTOOKAIM = say("TookAimText", { USER = "atk" }),
  STRINGID_PKMNTOOKATTACK = say("BattleText_TargetWasHitByFutureSight", { TARGET = "def" }),
  STRINGID_PKMNTOOKFOE = say("TookDownWithItText", { USER = "atk", TARGET = "def" }),
  STRINGID_PKMNTRYINGTOTAKEFOE = say("DestinyBondEffectText", { USER = "atk" }),
  STRINGID_PKMNTOOKSUNLIGHT = charge("EFFECT_SOLARBEAM"),
  STRINGID_PKMNUNLEASHEDENERGY = say("UnleashedEnergyText", { USER = "atk" }),
  STRINGID_PKMNWASDEFROSTED = say("DefrostedOpponentText", { TARGET = "def" }),
  STRINGID_PKMNWASDEFROSTED2 = say("WasDefrostedText", { USER = "atk" }),
  STRINGID_PKMNWASDRAGGEDOUT = say("DraggedOutText", { USER = "def" }),
  STRINGID_PKMNWHIPPEDWHIRLWIND = charge("EFFECT_RAZOR_WIND"),
  STRINGID_PKMNWOKEUP = say("WokeUpText", { USER = "atk" }),
  STRINGID_PKMNBEGANTONAP = say("BeganToNapText", { STRBUF = "atk" }),
  STRINGID_PKMNHASNOMOVESLEFT = say("BattleText_MonHasNoMovesLeft", { STRBUF = "atk" }),
  STRINGID_PKMNAFFLICTEDBYCURSE = say("HurtByCurseText", { USER = "atk" }),
  STRINGID_PKMNLAIDCURSE = say("PutACurseText", { USER = "atk", TARGET = "def" }),
  STRINGID_PKMNFELLINTONIGHTMARE = say("StartedNightmareText", { TARGET = "def" }),
  STRINGID_PKMNLOCKEDINNIGHTMARE = say("HasANightmareText", { USER = "atk" }),
  STRINGID_PKMNBLEWAWAYSPIKES = say("BlewSpikesText", { USER = "atk" }),
  STRINGID_PKMNSHEDLEECHSEED = say("ShedLeechSeedText", { USER = "atk" }),
  STRINGID_TARGETCANTESCAPENOW = say("CantEscapeNowText", { TARGET = "def" }),
  STRINGID_SHAREDPAIN = say("SharedPainText"),
  STRINGID_SPIKESSCATTERED = say("SpikesText", { TARGET = opponent }),
  STRINGID_STATCHANGESGONE = say("EliminatedStatsText"),
  STRINGID_NOPPLEFT = say("BattleText_TheresNoPPLeftForThisMove"),
  STRINGID_BUTNOPPLEFT = say("NoPPLeftText"),
  STRINGID_STARTEDTORAIN = weatherText("start", "rain"),
  STRINGID_SUNLIGHTGOTBRIGHT = weatherText("start", "sun"),
  STRINGID_SANDSTORMBREWED = weatherText("start", "sandstorm"),
  STRINGID_RAINCONTINUES = weatherText("turn", "rain"),
  STRINGID_SUNLIGHTSTRONG = weatherText("turn", "sun"),
  STRINGID_SANDSTORMRAGES = weatherText("turn", "sandstorm"),
  STRINGID_SANDSTORMISRAGING = weatherText("turn", "sandstorm"),
  STRINGID_ITISRAINING = weatherText("turn", "rain"),
  STRINGID_RAINSTOPPED = weatherText("end", "rain"),
  STRINGID_SUNLIGHTFADED = weatherText("end", "sun"),
  STRINGID_SANDSTORMSUBSIDED = weatherText("end", "sandstorm"),
}

Gen2Facade.MSG = MSG

local SILENT = { STRINGID_SWITCHINMON = true, STRINGID_USEDMOVE = true, STRINGID_INTROMSG = true,
  STRINGID_INTROSENDOUT = true, STRINGID_RETURNMON = true, STRINGID_BATTLEEND = true,
  STRINGID_EMPTYSTRING4 = true }
Gen2Facade.SILENT = SILENT

function Facade:msgText(id, fill)
  local fn = MSG[id]
  if not fn then return nil end
  local ok, text = pcall(fn, self, fill or {})
  if ok then return text end
  return nil
end

function Facade:effectivenessAfter(evs, i)
  for j = i + 1, #evs do
    local e = evs[j]
    if e.kind == "hp" or e.kind == "move" or e.kind == "faint" then return 10 end
    if e.kind == "msg" then
      if e.id == "STRINGID_SUPEREFFECTIVE" then return 20 end
      if e.id == "STRINGID_NOTVERYEFFECTIVE" then return 5 end
      if e.id == "STRINGID_USEDMOVE" then return 10 end
    end
  end
  return 10
end

function Facade:animEvent(seat, out, fields)
  local side = self:sideName(seat)
  local v = self:active(seat)
  local ev = { kind = "damage", side = side, amount = 0, hp = v and v.hp or 0, anim = false }
  for k, x in pairs(fields) do ev[k] = x end
  out[#out + 1] = ev
end

function Facade:revert(v)
  if v and v.transformedFrom then
    v.species = v.transformedFrom
    v.transformedFrom = nil
  end
  if v then self.vol[v] = nil end
end

function Facade:endText(why, outcome, out)
  local foe = self.foeName
  if why == "faint" then
    if outcome == "win" then
      out[#out + 1] = { kind = "message", text = romLine(self, "BattleText_EnemyWasDefeated", { ENEMY = foe }) }
      out[#out + 1] = { kind = "trainer-return" }
    elseif outcome == "lose" then
      out[#out + 1] = { kind = "message", text = Strings(T.noMore) }
    else
      out[#out + 1] = { kind = "message", text = Strings(T.draw) }
    end
  elseif why == "forfeit" then
    if outcome == "win" then
      out[#out + 1] = { kind = "message", text = Strings(T.foeForfeit, foe) }
    elseif outcome == "lose" then
      out[#out + 1] = { kind = "message", text = Strings(T.meForfeit) }
    else
      out[#out + 1] = { kind = "message", text = Strings(T.draw) }
    end
  elseif why == "desync" then
    out[#out + 1] = { kind = "message", text = Strings(T.desync) }
  elseif why == "disconnect" then
    out[#out + 1] = { kind = "message", text = Strings(T.left, foe) }
  elseif why == "illegal" then
    out[#out + 1] = { kind = "message", text = Strings(T.illegal) }
  else
    out[#out + 1] = { kind = "message", text = Strings(T.broken) }
  end
end

function Facade:finishWith(outcome)
  self.over = true
  self.outcome = outcome
  self.awaiting = nil
end

function Facade:reconcile()
  local v = self.player
  if not v then return end
  local live = self:liveMon(self.seat)
  if not (live and type(live.moves) == "table") then return end
  local same = true
  local count = 0
  for i = 1, 4 do
    local id = tonumber(live.moves[i])
    if id and id ~= 0 then
      count = count + 1
      if not v.engineSlots[id] then same = false end
    end
  end
  if count ~= #v.moves then same = false end
  if not same then
    local old = {}
    for _, mv in ipairs(v.moves) do old[mv.national] = mv end
    local moves, slots = {}, {}
    for i = 1, 4 do
      local id = tonumber(live.moves[i])
      if id and id ~= 0 then
        local prev = old[id]
        moves[#moves + 1] = { id = self:moveKey(id) or id, national = id,
          pp = tonumber(live.pp and live.pp[i]) or 0,
          maxPp = prev and prev.maxPp or tonumber(live.pp and live.pp[i]) or 0, ppUps = prev and prev.ppUps or 0 }
        slots[id] = i
      end
    end
    v.moves, v.engineSlots = moves, slots
    return
  end
  for i = 1, 4 do
    local id = tonumber(live.moves[i])
    if id and id ~= 0 then
      v.engineSlots[id] = i
      for _, mv in ipairs(v.moves) do
        if mv.national == id then mv.pp = tonumber(live.pp and live.pp[i]) or mv.pp end
      end
    end
  end
end

function Facade:liveMon(seat)
  local m = self.bs and self.bs.match
  local st = m and m.st
  if type(st) ~= "table" then return nil end
  local b = st.battlers and st.battlers[seat] or (seat == 0 and st.player or st.enemy)
  return type(b) == "table" and b.mon or nil
end

function Facade:translate(evs)
  local out = {}
  local fainted = {}
  local lastUser, hitSince = nil, false
  local i = 1
  while i <= #evs do
    local ev = evs[i]
    local k = ev.kind
    if k == "ready" then
      self:onReady(ev)
    elseif k == "sendout" then
      local v = self:setActive(ev.side, ev.index)
      if ev.reason ~= "start" and v then
        local side = self:sideName(ev.side)
        local text
        if ev.reason ~= "roar" then
          if side == "player" then
            text = self:goMonText(v)
          else
            text = romLine(self, "BattleText_EnemySentOut", self.foeName, self:nameOf(v))
          end
        end
        out[#out + 1] = { kind = "send", side = side, mon = v, hp = v.hp or 0, status = v.status or false,
          level = v.level, text = text }
      end
    elseif k == "withdraw" then
      local v = self.views[ev.side] and self.views[ev.side][ev.index]
      if ev.reason ~= "start" and v then
        self:revert(v)
        if self:sideName(ev.side) == "enemy" and ev.reason == "switch" and (v.hp or 0) > 0 then
          out[#out + 1] = { kind = "message", text = romLine(self, "EnemyWithdrewText",
            { ENEMY = self.foeName, STRBUF = self:nameOf(v) }) }
        end
      end
    elseif k == "move" then
      lastUser, hitSince = ev.user, false
      out[#out + 1] = { kind = "move", side = self:sideName(ev.user), move = self:moveKey(ev.moveId) or ev.moveId }
    elseif k == "hp" then
      local v = self:active(ev.side)
      local to = tonumber(ev.to) or 0
      local from = tonumber(ev.from) or (v and v.hp) or to
      if v then v.hp = to end
      local side = self:sideName(ev.side)
      if to < from then
        local e = { kind = "damage", side = side, amount = from - to, hp = to }
        if ev.hit then
          hitSince = true
          e.effectiveness = self:effectivenessAfter(evs, i)
        else
          e.anim = false
        end
        out[#out + 1] = e
      elseif to > from then
        out[#out + 1] = { kind = "heal", side = side, amount = to - from, hp = to }
      end
    elseif k == "status" then
      local v = self:active(ev.side)
      local s = Gen2Facade.STATUS[ev.status]
      if v then v.status = s end
      out[#out + 1] = { kind = "status", side = self:sideName(ev.side), status = s or false }
    elseif k == "stage" then
      local delta = tonumber(ev.delta) or 0
      if delta < 0 and not ev.sync and lastUser ~= nil and lastUser ~= ev.side and not hitSince then
        if self:sideName(ev.side) == "enemy" then
          self:animEvent(ev.side, out, { anim = "ANIM_ENEMY_STAT_DOWN", animSide = "player" })
        else
          self:animEvent(ev.side, out, { anim = "ANIM_WOBBLE", animSide = "enemy" })
        end
      end
    elseif k == "anim" then
      local seat = ev.user ~= nil and ev.user or ev.target
      local group = Gen2Facade.ANIMS[ev.anim]
      local id = group and group[ev.name]
      local moveAnim = Gen2Facade.MOVE_ANIMS[ev.name]
      if seat ~= nil and id then
        if id == "ANIM_SAP" then
          self:animEvent(seat, out, { anim = id })
        else
          self:animEvent(seat, out, { anim = id, animSide = self:sideName(seat) })
        end
      elseif seat ~= nil and moveAnim then
        local mv = moveAnim == "arg" and tonumber(ev.arg) or moveAnim
        local key = mv and self:moveKey(mv)
        if key then
          local target = ev.name == "FUTURE_SIGHT_HIT" and (ev.target or seat) or seat
          self:animEvent(target, out, { animMove = key })
        end
      end
    elseif k == "faint" then
      local v = self:active(ev.side)
      if v then v.hp = 0 end
      fainted[ev.side] = true
      out[#out + 1] = { kind = "faint", side = self:sideName(ev.side),
        text = self:faintText(ev.side, v) }
    elseif k == "weather" then
      self.weather = Gen2Facade.WEATHER[tostring(ev.weather or ""):upper()]
    elseif k == "msg" then
      local f = ev.fill or {}
      if ev.id == "STRINGID_USEDMOVE" then
        local atk = type(f.atk) == "table" and f.atk or {}
        local mv = moveOf(f.currentMove)
        local nxt = evs[i + 1]
        local e = { kind = "move", side = self:sideName(atk.side), move = self:moveKey(mv) or mv,
          text = self:usedMoveText(f.atk, mv) }
        lastUser, hitSince = atk.side, false
        if nxt and nxt.kind == "move" and nxt.user == atk.side then
          e.move = self:moveKey(nxt.moveId) or nxt.moveId
          i = i + 1
        else
          e.missed = true
        end
        out[#out + 1] = e
      elseif ev.id == "STRINGID_TARGETFAINTED" or ev.id == "STRINGID_ATTACKERFAINTED" then
        local r = ev.id == "STRINGID_TARGETFAINTED" and f.def or f.atk
        if not (type(r) == "table" and fainted[r.side]) then
          out[#out + 1] = { kind = "message", text = self:faintText(r.side, self:ref(r)) }
        end
      elseif ev.id == "STRINGID_PKMNTRANSFORMEDINTO" then
        local v = self:ref(f.atk)
        local sp = type(f.buff1) == "table" and f.buff1.species
        local key = sp and self:speciesKey(sp)
        if v and key then
          local from = v.transformedFrom or v.species
          v.transformedFrom = from
          v.species = key
          self:volatile(v).transformed = true
          out[#out + 1] = { kind = "transform", side = self:sideName(f.atk.side), mon = v, from = from }
        end
        out[#out + 1] = { kind = "message",
          text = romLine(self, "TransformedText",
            { USER = self:N(f.atk), STRBUF = sp and self:speciesName(sp) or "?" }) }
      elseif not SILENT[ev.id] then
        local text = self:msgText(ev.id, f)
        if text then out[#out + 1] = { kind = "message", text = text } end
      end
    elseif k == "end" then
      local r = ev.result or {}
      local outcome = r.draw and "draw" or (r.winner == self.seat and "win" or "lose")
      self.ended = true
      self:finishWith(outcome)
      self:endText(r.why, outcome, out)
    elseif k == "over" then
      self.result = { outcome = ev.outcome, why = ev.why, detail = ev.detail }
      if not self.ended then
        self.ended = true
        self:finishWith(ev.outcome)
        self:endText(ev.why, ev.outcome, out)
      end
    elseif k == "prompt" then
      if ev.what == "move" then
        self.awaiting = "move"
        self:reconcile()
      elseif ev.what == "replace" then
        self.awaiting = "replace"
        out[#out + 1] = { kind = "choose-switch" }
      end
    end
    i = i + 1
  end
  for _, e in ipairs(out) do self.events[#self.events + 1] = e end
  return out
end

function Facade:takeEvents()
  local out = self.events
  self.events = {}
  return out
end

function Facade:takeTurn()
  return {}
end

function Facade:volatile(mon)
  if mon == nil then return {} end
  local v = self.vol[mon]
  if not v then
    v = {}
    self.vol[mon] = v
  end
  return v
end

function Facade:clearAllVolatiles()
  for seat = 0, 1 do
    for _, v in ipairs(self.views[seat] or {}) do self:revert(v) end
  end
end

function Facade:legal()
  if not self.bs then return {} end
  return self.bs:legal()
end

function Facade:slotOf(moveKey)
  local v = self.player
  if not v then return nil end
  if moveKey == Battle.STRUGGLE then return 0 end
  for _, mv in ipairs(v.moves) do
    if mv.id == moveKey then return v.engineSlots[mv.national] end
  end
  return nil
end

function Facade:slotMove(slot)
  if not slot or slot == 0 then return Battle.STRUGGLE end
  local v = self.player
  for id, s in pairs(v and v.engineSlots or {}) do
    if s == slot then return self:moveKey(id) or id end
  end
  return Battle.STRUGGLE
end

function Facade:lockedAction()
  if self.awaiting ~= "move" then return nil end
  for _, a in ipairs(self:legal()) do
    if a.kind == "move" and a.locked then return a end
  end
  return nil
end

function Facade:lockedInMove(mon)
  if mon ~= self.player then return nil end
  local a = self:lockedAction()
  return a and self:slotMove(a.slot) or nil
end

function Facade:hasUsableMoves(mon)
  if mon ~= self.player then return true end
  for _, a in ipairs(self:legal()) do
    if a.kind == "move" and (a.locked or (a.slot or 0) >= 1) then return true end
  end
  return false
end

function Facade:moveDisabled(mon, moveKey)
  if mon ~= self.player then return false end
  local slot = self:slotOf(moveKey)
  if not slot then return true end
  for _, a in ipairs(self:legal()) do
    if a.kind == "move" and a.slot == slot and not a.locked then return false end
  end
  return true
end

function Facade:switchLocked()
  local bench = false
  for i, v in ipairs(self.party) do
    if i ~= self.activeIndex[self.seat] and (v.hp or 0) > 0 then bench = true end
  end
  if not bench then return false end
  for _, a in ipairs(self:legal()) do
    if a.kind == "switch" then return false end
  end
  return true
end

function Facade:switch() return false end
function Facade:shiftSwitch() return false end
function Facade:forcedReplacement() return false end
function Facade:tryRun() return false end
function Facade:useBattleItem() return false end
function Facade:resolveForget() end
function Facade:declineForget() end

function Facade:partyMoves(mon)
  return (mon and mon.moves) or {}
end

function Facade:endBattle(outcome)
  self:finishWith(outcome)
end

function Facade:actionFor(action)
  local legal = self:legal()
  local function find(pred)
    for _, a in ipairs(legal) do
      if pred(a) then return { kind = a.kind, slot = a.slot, index = a.index } end
    end
    return nil
  end
  if action.kind == "switch" then
    return find(function(a) return a.kind == "switch" and a.index == action.index end)
  end
  if action.kind ~= "move" then return nil end
  local locked = find(function(a) return a.kind == "move" and a.locked end)
  if locked then return locked end
  local slot = self:slotOf(action.move)
  if slot == nil then return nil end
  return find(function(a) return a.kind == "move" and a.slot == slot end)
end

function Facade:wait(s)
  s.phase = "link-wait"
  s.message = Strings(T.waiting)
  s.typedText = nil
  s.messageTimer = 0
end

function Facade:hooks()
  local facade = self
  local hooks = {}
  hooks.submit = function(s, action)
    if facade.over then return end
    if action.kind == "item" then return s:refuseMenu(romLine(facade, "BattleText_ItemsCantBeUsedHere")) end
    if action.kind == "run" then return hooks.menuChoice(s, "run") end
    local act = facade.awaiting == "move" and facade:actionFor(action) or nil
    if not act or not facade.bs:choose(act) then return s:refuseMenu(T.cantNow) end
    facade.awaiting = nil
    facade.runArmed = nil
    facade:wait(s)
  end
  hooks.menuChoice = function(s, choice)
    if choice == "item" then
      facade.runArmed = nil
      s:refuseMenu(romLine(facade, "BattleText_ItemsCantBeUsedHere"))
      return true
    end
    if choice == "run" then
      if facade.runArmed and facade.awaiting == "move" then
        facade.runArmed = nil
        if facade.bs:choose({ kind = "forfeit" }) then
          facade.awaiting = nil
          facade:wait(s)
        end
        return true
      end
      facade.runArmed = true
      s:refuseMenu(T.runAgain)
      return true
    end
    facade.runArmed = nil
    return false
  end
  hooks.forcedSwitch = function(s, index)
    if facade.awaiting ~= "replace" or not facade.bs:pickReplacement(index) then
      return s:refuseSwitch(true)
    end
    facade.awaiting = nil
    facade:wait(s)
    return true
  end
  return hooks
end

function Facade:fakeSave()
  local save = self.game and self.game.save
  local player = (save and save.player) or {}
  return {
    party = self.party,
    player = { name = player.name or self.myName, gender = player.gender },
    inventory = {}, pokedex = { seen = {}, caught = {} }, options = {}, modData = {},
  }
end

local Host = {}
Host.__index = Host
Gen2Facade.Host = Host

function Gen2Facade.banner()
  return {
    { kind = "message", text = Strings(T.rules1) },
    { kind = "message", text = Strings(T.rules2) },
  }
end

function Host:wrap(state)
  if state == nil or state == self or self.wrapped[state] or type(state.update) ~= "function" then return end
  local host = self
  local prev = rawget(state, "update")
  local base = state.update
  self.wrapped[state] = { prev = prev }
  state.update = function(st, dt)
    if not host.finished then host:pump() end
    local r = base(st, dt)
    if not host.finished then host:wrapTop() end
    return r
  end
end

function Host:wrapTop()
  local stack = self.game and self.game.stack
  if stack then self:wrap(stack:top()) end
end

function Host:unwrap()
  for state, w in pairs(self.wrapped) do rawset(state, "update", w.prev) end
  self.wrapped = {}
end

function Host:kick()
  local s = self.screen
  if not s or self.screenDone then return end
  local stack = self.game.stack
  local facade = self.facade
  if facade.over and stack:top() ~= s then
    local seen = false
    for _, st in ipairs(stack.states or {}) do
      if st == s then seen = true end
    end
    if seen then
      while stack:top() ~= s do stack:pop() end
    end
  end
  if stack:top() ~= s then return end
  if IDLE[s.phase] and #s.queue > 0 then
    s.phase = "resolving"
    s.message = nil
    s.messageTimer = 0
    s:advanceQueue()
  end
end

function Host:pump()
  local bs, facade = self.bs, self.facade
  if not bs.result then bs:update() end
  local evs = bs:events()
  if #evs > 0 then facade:translate(evs) end
  if bs.result and not facade.result then facade.result = bs.result end
  if self.screen then
    local pending = facade:takeEvents()
    if #pending > 0 then self.screen:pushAll(pending) end
    self:kick()
  end
end

function Host:world()
  return self.game and self.game.world
end

function Host:buildScreen()
  local BattleState = require("src.ui.gen2.BattleState")
  local game, facade = self.game, self.facade
  local host = self
  local screen
  screen = BattleState.new(game, {
    battle = facade,
    save = facade:fakeSave(),
    link = facade:hooks(),
    music = { class = facade.trainer.classId },
    onDone = function()
      host.screenDone = true
      if game.stack:top() == screen then game.stack:pop() end
      local world = host:world()
      if world then
        world.battleActive = nil
        if type(world.battleReturnFade) == "function" then world:battleReturnFade() end
        if type(world.restoreMapMusic) == "function" then world:restoreMapMusic() end
      end
      host.stage = "closing"
    end,
  })
  screen.kind = "link"
  screen.g3u = true
  local banner = Gen2Facade.banner()
  for j = #banner, 1, -1 do table.insert(screen.queue, 1, banner[j]) end
  local baseAdvance = screen.advanceQueue
  screen.advanceQueue = function(s)
    local r = baseAdvance(s)
    if (s.phase == "menu" or s.phase == "locked-in") and facade.awaiting ~= "move" and not facade.over then
      facade:wait(s)
    end
    return r
  end
  local pending = facade:takeEvents()
  if #pending > 0 then screen:pushAll(pending) end
  self.screen = screen
  return screen
end

function Host:openBattle()
  local game = self.game
  local world = self:world()
  local screen = self:buildScreen()
  self.stage = "battle"
  if world and type(world.playBattleMusic) == "function" then
    world:playBattleMusic({ trainer = { classId = self.facade.trainer.classId } })
  end
  local function push()
    if world then world.battleActive = true end
    game.stack:push(screen)
  end
  local pushed = false
  if world and type(world.pushBattleTransition) == "function" then
    pushed = world:pushBattleTransition(self.facade, { trainer = true }, push)
  end
  if not pushed then push() end
end

function Host:finish()
  if self.finished then return end
  self.finished = true
  self:unwrap()
  local stack = self.game.stack
  if stack:top() == self then stack:pop() end
  local result = self.bs.result
  local onDone = self.onDone
  self.onDone = nil
  if onDone then onDone(result) end
end

function Host:update()
  if self.finished then return end
  self:pump()
  self:step()
  if not self.finished then self:wrapTop() end
end

function Host:step()
  local facade, bs = self.facade, self.bs
  if self.stage == "setup" then
    if facade.ready and (facade.awaiting or facade.over) then return self:openBattle() end
    if bs.result then
      self.stage = "failed"
      self.frames = 0
      local out = {}
      facade:endText(bs.result.why, bs.result.outcome, out)
      self.failText = out[1] and out[1].text or Strings(T.broken)
    end
    return
  end
  if self.stage == "failed" then
    self.frames = self.frames + 1
    local input = self.game.input
    local pressed = input and input.wasPressed and (input:wasPressed("a") or input:wasPressed("b"))
    if pressed or self.frames >= Gen2Facade.FAIL_HOLD_FRAMES then self:finish() end
    return
  end
  if self.stage == "closing" and bs.result then self:finish() end
end

function Host:text()
  if self.stage == "failed" then return self.failText end
  if self.stage == "setup" then return Strings(T.waitingFor, self.facade.foeName) end
  return nil
end

function Host:draw()
  local text = self:text()
  if not text then return end
  local Chrome = require("src.ui.gen2.Chrome")
  Chrome.textbox(0, 12, 18, 4)
  Chrome.printWrapped(text, 1, 13, 18, 4)
end

function Gen2Facade.start(game, bs, opts)
  opts = opts or {}
  if type(game) ~= "table" or type(game.stack) ~= "table" then return nil, "no_stack" end
  if type(bs) ~= "table" then return nil, "no_session" end
  local facade = Gen2Facade.new(game, bs, opts)
  local host = setmetatable({
    game = game, bs = bs, facade = facade, stage = "setup", frames = 0, onDone = opts.onDone, wrapped = {},
  }, Host)
  game.stack:push(host)
  return host
end

return Gen2Facade
