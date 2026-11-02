local Battle = require("src.battle.gen2.Battle")
local Effects = require("src.battle.gen2.Effects")
local Identity = require("src.online.xgen.Identity")
local Strings = require("src.core.Strings")

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
  noItems = S("Items can't be used in a link battle!"),
  runAgain = S("Choose RUN again\nto forfeit."),
  cantNow = S("That can't be\nchosen now."),
  defeated = S("%s was defeated!"),
  noMore = S("You have no more POKéMON!"),
  draw = S("The battle ended\nin a draw!"),
  foeForfeit = S("%s forfeited\nthe match!"),
  meForfeit = S("You forfeited\nthe match."),
  desync = S("The link fell out\nof sync. It's a draw."),
  left = S("%s left the battle."),
  illegal = S("The other game sent\na bad move. Draw."),
  broken = S("The battle could\nnot continue."),
  fainted = S("%s fainted!"),
  enemyFainted = S("Enemy %s fainted!"),
  withdrew = S("%s withdrew %s!"),
  go = S("Go! %s!"),
  usedMove = S("%s\nused %s!"),
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

-- home/text.asm:330-345
function Facade:N(r)
  local v = self:ref(r)
  if not v then return "?" end
  local foe = (type(r) == "table") and (r.side ~= self.seat) or (r == "enemy")
  if foe then return Strings("Enemy %s", self:nameOf(v)) end
  return self:nameOf(v)
end

local function moveOf(v)
  if type(v) == "table" then return v.move end
  return tonumber(v)
end

local function stageText(self, ref, stat, delta)
  return Effects.stageMessage(self:N(ref), Gen2Facade.STATS[stat] or stat, tonumber(delta) or 0)
end

local function wontText(self, ref, stat, up)
  local label = Strings(Effects.STAT_NAMES[Gen2Facade.STATS[stat] or stat] or tostring(stat))
  if up then return Strings("%s's %s won't rise anymore!", self:N(ref), label) end
  return Strings("%s's %s won't drop anymore!", self:N(ref), label)
end

local function role(src, key)
  return function(self, f) return Strings(src, self:N(f[key])) end
end

local function plain(src)
  return function() return Strings(src) end
end

local function inflict(status, key)
  return function(self, f) return Strings(Battle.STATUS_INFLICT_TEMPLATES[status], self:N(f[key])) end
end

local function weatherText(tbl, kind)
  return function() return Strings(tbl[kind]) end
end

local MSG = {
  STRINGID_ATTACKERSSTATROSE = function(self, f) return stageText(self, f.atk, f.stat, f.delta) end,
  STRINGID_ATTACKERSSTATFELL = function(self, f) return stageText(self, f.atk, f.stat, f.delta) end,
  STRINGID_DEFENDERSSTATROSE = function(self, f) return stageText(self, f.def, f.stat, f.delta) end,
  STRINGID_DEFENDERSSTATFELL = function(self, f) return stageText(self, f.def, f.stat, f.delta) end,
  STRINGID_STATSWONTINCREASE = function(self, f) return wontText(self, f.atk or f.def, f.buff1, true) end,
  STRINGID_STATSWONTDECREASE = function(self, f) return wontText(self, f.def or f.atk, f.buff1, false) end,
  STRINGID_ATTACKMISSED = role("%s's attack missed!", "atk"),
  STRINGID_BELLCHIMED = plain("A bell chimed!"),
  STRINGID_BUTITFAILED = plain("But it failed!"),
  STRINGID_MIRRORMOVEFAILED = plain("But it failed!"),
  STRINGID_BUTNOTHINGHAPPENED = plain("But nothing\nhappened."),
  STRINGID_BUTNOEFFECT = plain("But nothing\nhappened."),
  STRINGID_COINSSCATTERED = plain("Coins scattered\neverywhere!"),
  STRINGID_CRITICALHIT = plain("A critical hit!"),
  STRINGID_FAINTINTHREE = plain("Both POKéMON will\nfaint in 3 turns!"),
  STRINGID_HITXTIMES = function(_, f) return Strings("Hit %d times!", tonumber(f.buff1) or 0) end,
  STRINGID_ITDOESNTAFFECT = role("It didn't affect\n%s!", "def"),
  STRINGID_PKMNUNAFFECTED = role("It didn't affect\n%s!", "def"),
  STRINGID_PKMNWASNTAFFECTED = role("It didn't affect\n%s!", "def"),
  STRINGID_ITHURTCONFUSION = plain("It hurt itself in its confusion!"),
  STRINGID_MAGNITUDESTRENGTH = function(_, f) return Strings("Magnitude %d!", tonumber(f.buff1) or 0) end,
  STRINGID_NOTVERYEFFECTIVE = plain("It's not very\neffective…"),
  STRINGID_SUPEREFFECTIVE = plain("It's super-\neffective!"),
  STRINGID_ONEHITKO = plain("It's a one-hit KO!"),
  STRINGID_PKMNALREADYASLEEP = role("%s's already asleep!", "def"),
  STRINGID_PKMNALREADYASLEEP2 = role("%s's already asleep!", "atk"),
  STRINGID_PKMNALREADYCONFUSED = role("%s's already confused!", "def"),
  STRINGID_PKMNALREADYPOISONED = role("%s's already poisoned!", "def"),
  STRINGID_PKMNISALREADYPARALYZED = role("%s's already paralyzed!", "def"),
  STRINGID_PKMNALREADYHASBURN = role("%s's already burned!", "def"),
  STRINGID_PKMNATTACK = function(self, f)
    local sp = type(f.buff1) == "table" and f.buff1.species
    return Strings("%s's attack!", sp and self:speciesName(sp) or "?")
  end,
  STRINGID_PKMNBADLYPOISONED = inflict("toxic", "eff"),
  STRINGID_PKMNWASPOISONED = inflict("poison", "eff"),
  STRINGID_PKMNWASBURNED = inflict("burn", "eff"),
  STRINGID_PKMNWASFROZEN = inflict("freeze", "eff"),
  STRINGID_PKMNWASPARALYZED = inflict("paralyze", "eff"),
  STRINGID_PKMNFELLASLEEP = inflict("sleep", "eff"),
  STRINGID_PKMNWASCONFUSED = inflict("confuse", "eff"),
  STRINGID_PKMNBRACEDITSELF = role("%s braced itself!", "atk"),
  STRINGID_PKMNBUFFETEDBYSANDSTORM = role("%s is buffeted by the sandstorm!", "atk"),
  STRINGID_PKMNCHANGEDTYPE = function(self, f)
    local t = type(f.buff1) == "table" and f.buff1.type
    return Strings("%s transformed into the %s type!", self:N(f.atk),
      t and (Identity.GEN3_TYPES[t] == "MYSTERY" and "???" or Identity.GEN3_TYPES[t]) or "?")
  end,
  STRINGID_PKMNCOPIEDSTATCHANGES = function(self, f)
    return Strings("%s\ncopied the stat\fchanges of\n%s!", self:N(f.atk), self:N(f.def))
  end,
  STRINGID_PKMNCOVEREDBYVEIL = role("%s's covered by a veil!", "atk"),
  STRINGID_PKMNUSEDSAFEGUARD = role("%s's covered by a veil!", "atk"),
  STRINGID_PKMNCRASHED = role("%s kept going and crashed!", "atk"),
  STRINGID_PKMNCUTHPMAXEDATTACK = role("%s\ncut its HP and\nmaximized ATTACK!", "atk"),
  STRINGID_PKMNDREAMEATEN = role("%s's dream was eaten!", "def"),
  STRINGID_PKMNDUGHOLE = role("%s dug a hole!", "atk"),
  STRINGID_PKMNENDUREDHIT = role("%s endured the hit!", "def"),
  STRINGID_PKMNENERGYDRAINED = role("%s's energy was drained!", "def"),
  STRINGID_PKMNEVADEDATTACK = role("%s evaded the attack!", "def"),
  STRINGID_PKMNAVOIDEDATTACK = role("%s evaded the attack!", "def"),
  STRINGID_PKMNFASTASLEEP = role("%s is fast asleep!", "atk"),
  STRINGID_PKMNFATIGUECONFUSION = role("%s became confused due to fatigue!", "atk"),
  STRINGID_PKMNFELLINLOVE = role("%s\nfell in love!", "def"),
  STRINGID_PKMNFLEWHIGH = role("%s flew up high!", "atk"),
  STRINGID_PKMNFLINCHED = role("%s flinched!", "atk"),
  STRINGID_PKMNFORESAWATTACK = role("%s foresaw an attack!", "atk"),
  STRINGID_PKMNFREEDFROM = function(self, f)
    return Strings("%s was released from %s!", self:N(f.atk), self:moveName(moveOf(f.buff1)))
  end,
  STRINGID_PKMNGETTINGPUMPED = role("%s's\ngetting pumped!", "atk"),
  STRINGID_PKMNGOTENCORE = role("%s got an ENCORE!", "def"),
  STRINGID_PKMNENCOREENDED = role("%s's ENCORE ended!", "atk"),
  STRINGID_PKMNHASSUBSTITUTE = role("%s has a SUBSTITUTE!", "atk"),
  STRINGID_PKMNHEALEDCONFUSION = role("%s's confused no more!", "atk"),
  STRINGID_PKMNHITWITHRECOIL = role("%s is hit with recoil!", "atk"),
  STRINGID_PKMNHPFULL = role("%s's HP is full!", "def"),
  STRINGID_PKMNHURTBY = function(self, f)
    return Strings("%s's hurt by %s!", self:N(f.atk), self:moveName(moveOf(f.buff1)))
  end,
  STRINGID_PKMNHURTBYBURN = role("%s is hurt by its burn!", "atk"),
  STRINGID_PKMNHURTBYPOISON = role("%s is hurt by poison!", "atk"),
  STRINGID_PKMNHURTBYSPIKES = role("%s is hurt by SPIKES!", "scrActive"),
  STRINGID_PKMNIDENTIFIED = function(self, f) return Strings("%s identified %s!", self:N(f.atk), self:N(f.def)) end,
  STRINGID_PKMNIMMOBILIZEDBYLOVE = role("%s's infatuation kept\nit from attacking!", "atk"),
  STRINGID_PKMNINLOVE = function(self, f)
    return Strings("%s\nis in love with\n%s!", self:N(f.atk), self:N(f.scrActive or f.def))
  end,
  STRINGID_PKMNISCONFUSED = role("%s is confused!", "atk"),
  STRINGID_PKMNISFROZEN = role("%s is frozen solid!", "atk"),
  STRINGID_PKMNISGLOWING = role("%s is glowing!", "atk"),
  STRINGID_PKMNISPARALYZED = role("%s's fully paralyzed!", "atk"),
  STRINGID_PKMNLEARNEDMOVE2 = function(self, f)
    return Strings("%s learned %s!", self:N(f.atk), self:moveName(moveOf(f.buff1)))
  end,
  STRINGID_PKMNLOWEREDHEAD = role("%s lowered its head!", "atk"),
  STRINGID_PKMNMADESUBSTITUTE = role("%s made a SUBSTITUTE!", "atk"),
  STRINGID_TOOWEAKFORSUBSTITUTE = plain("Too weak to make\na SUBSTITUTE!"),
  STRINGID_PKMNMOVEDISABLEDNOMORE = role("%s's move is no longer disabled!", "atk"),
  STRINGID_PKMNMOVEISDISABLED = function(self, f)
    return Strings("%s's %s is DISABLED!", self:N(f.active or f.atk), self:moveName(moveOf(f.currentMove)))
  end,
  STRINGID_PKMNMOVEWASDISABLED = function(self, f)
    return Strings("%s's %s was disabled!", self:N(f.def), self:moveName(moveOf(f.buff1)))
  end,
  STRINGID_PKMNMUSTRECHARGE = role("%s must recharge!", "atk"),
  STRINGID_PKMNPERISHCOUNTFELL = function(self, f)
    return Strings("%s's PERISH count is %d!", self:N(f.atk), tonumber(f.buff1) or 0)
  end,
  STRINGID_PKMNPROTECTEDBYMIST = role("%s's protected by MIST.", "scrActive"),
  STRINGID_PKMNPROTECTEDITSELF = role("%s protected itself!", "def"),
  STRINGID_PKMNPROTECTEDITSELF2 = role("%s protected itself!", "atk"),
  STRINGID_PKMNRAGEBUILDING = role("%s's RAGE is building!", "def"),
  STRINGID_PKMNRAISEDDEF = role("%s's DEFENSE rose!", "atk"),
  STRINGID_PKMNRAISEDSPDEF = role("%s's SPCL.DEF rose!", "atk"),
  STRINGID_PKMNREDUCEDPP = function(self, f)
    return Strings("%s's %s was reduced by %d!", self:N(f.def), self:moveName(moveOf(f.buff1)),
      tonumber(f.buff2) or 0)
  end,
  STRINGID_PKMNREGAINEDHEALTH = role("%s regained health!", "def"),
  STRINGID_PKMNSAFEGUARDEXPIRED = role("%s's SAFEGUARD faded!", "atk"),
  STRINGID_PKMNSAPPEDBYLEECHSEED = role("LEECH SEED saps %s!", "atk"),
  STRINGID_PKMNSEEDED = role("%s was seeded!", "def"),
  STRINGID_PKMNSHROUDEDINMIST = role("%s's\nshrouded in MIST!", "atk"),
  STRINGID_PKMNSKETCHEDMOVE = function(self, f)
    return Strings("%s\nSKETCHED\v%s!", self:N(f.atk), self:moveName(moveOf(f.buff1)))
  end,
  STRINGID_PKMNSLEPTHEALTHY = role("%s fell asleep and became healthy!", "atk"),
  STRINGID_PKMNWENTTOSLEEP = role("%s went to sleep!", "atk"),
  STRINGID_PKMNSQUEEZEDBYBIND = function(self, f)
    return Strings("%s used BIND on %s!", self:N(f.atk), self:N(f.def))
  end,
  STRINGID_PKMNWRAPPEDBY = function(self, f)
    return Strings("%s was WRAPPED by %s!", self:N(f.def), self:N(f.atk))
  end,
  STRINGID_PKMNCLAMPED = function(self, f)
    return Strings("%s was CLAMPED by %s!", self:N(f.def), self:N(f.atk))
  end,
  STRINGID_PKMNTRAPPEDINVORTEX = role("%s was trapped!", "def"),
  STRINGID_PKMNSTORINGENERGY = role("%s is storing energy!", "atk"),
  STRINGID_PKMNSUBSTITUTEFADED = role("%s's SUBSTITUTE broke!", "def"),
  STRINGID_SUBSTITUTEDAMAGED = role("The SUBSTITUTE took damage for %s!", "def"),
  STRINGID_PKMNSXWOREOFF = function(self, f)
    local mv = moveOf(f.buff1)
    local seat = f.atk == "enemy" and 1 or 0
    local label = Strings(Battle.SCREEN_SIDE_LABEL[self:sideName(seat)])
    if mv == 113 then return Strings(Battle.SCREEN_FALL_TEXT.lightScreen, label) end
    if mv == 115 then return Strings(Battle.SCREEN_FALL_TEXT.reflect, label) end
    return Strings(T.woreOff, label, self:moveName(mv))
  end,
  STRINGID_PKMNTOOKAIM = role("%s took aim!", "atk"),
  STRINGID_PKMNTOOKATTACK = function(self, f)
    return Strings("%s took the %s attack!", self:N(f.def), self:moveName(moveOf(f.buff1)))
  end,
  STRINGID_PKMNTOOKFOE = role("%s took its foe down with it!", "atk"),
  STRINGID_PKMNTRYINGTOTAKEFOE = role("%s is trying to take its foe with it!", "atk"),
  STRINGID_PKMNTOOKSUNLIGHT = role("%s took in sunlight!", "atk"),
  STRINGID_PKMNUNLEASHEDENERGY = role("%s unleashed energy!", "atk"),
  STRINGID_PKMNWASDEFROSTED = role("%s thawed out!", "def"),
  STRINGID_PKMNWASDEFROSTED2 = role("%s thawed out!", "atk"),
  STRINGID_PKMNWASDRAGGEDOUT = role("%s was dragged out!", "def"),
  STRINGID_PKMNWHIPPEDWHIRLWIND = role("%s made a whirlwind!", "atk"),
  STRINGID_PKMNWOKEUP = role("%s woke up!", "atk"),
  STRINGID_PKMNBEGANTONAP = role("%s began to nap!", "atk"),
  STRINGID_PKMNHASNOMOVESLEFT = role("%s has no moves left!", "atk"),
  STRINGID_PKMNAFFLICTEDBYCURSE = role("%s's hurt by the CURSE!", "atk"),
  STRINGID_PKMNLAIDCURSE = function(self, f)
    return Strings("%s cut its own HP and put a CURSE on %s!", self:N(f.atk), self:N(f.def))
  end,
  STRINGID_PKMNFELLINTONIGHTMARE = role("%s\nstarted to have a\vNIGHTMARE!", "def"),
  STRINGID_PKMNLOCKEDINNIGHTMARE = role("%s\nhas a NIGHTMARE!", "atk"),
  STRINGID_PKMNBLEWAWAYSPIKES = role("%s blew away SPIKES!", "atk"),
  STRINGID_PKMNSHEDLEECHSEED = role("%s was freed from LEECH SEED!", "atk"),
  STRINGID_TARGETCANTESCAPENOW = role("%s can't escape now!", "def"),
  STRINGID_SHAREDPAIN = plain("The battlers shared\ntheir pain!"),
  STRINGID_SPIKESSCATTERED = plain("Spikes were scattered all around!"),
  STRINGID_STATCHANGESGONE = plain("All stat changes\nwere eliminated!"),
  STRINGID_NOPPLEFT = plain("There's no PP left\nfor this move!"),
  STRINGID_BUTNOPPLEFT = plain("But there was no\nPP left!"),
  STRINGID_STARTEDTORAIN = weatherText(Effects.WEATHER_START_TEXT, "rain"),
  STRINGID_SUNLIGHTGOTBRIGHT = weatherText(Effects.WEATHER_START_TEXT, "sun"),
  STRINGID_SANDSTORMBREWED = weatherText(Effects.WEATHER_START_TEXT, "sandstorm"),
  STRINGID_RAINCONTINUES = weatherText(Effects.WEATHER_TURN_TEXT, "rain"),
  STRINGID_SUNLIGHTSTRONG = weatherText(Effects.WEATHER_TURN_TEXT, "sun"),
  STRINGID_SANDSTORMRAGES = weatherText(Effects.WEATHER_TURN_TEXT, "sandstorm"),
  STRINGID_SANDSTORMISRAGING = weatherText(Effects.WEATHER_TURN_TEXT, "sandstorm"),
  STRINGID_ITISRAINING = weatherText(Effects.WEATHER_TURN_TEXT, "rain"),
  STRINGID_RAINSTOPPED = weatherText(Effects.WEATHER_END_TEXT, "rain"),
  STRINGID_SUNLIGHTFADED = weatherText(Effects.WEATHER_END_TEXT, "sun"),
  STRINGID_SANDSTORMSUBSIDED = weatherText(Effects.WEATHER_END_TEXT, "sandstorm"),
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
      out[#out + 1] = { kind = "message", text = Strings(T.defeated, foe) }
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
            text = Strings(T.go, self:nameOf(v))
          else
            text = Battle.sentOutText(self.foeName, self:nameOf(v))
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
          out[#out + 1] = { kind = "message", text = Strings(T.withdrew, self.foeName, self:nameOf(v)) }
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
      local side = self:sideName(ev.side)
      out[#out + 1] = { kind = "faint", side = side,
        text = Strings(side == "enemy" and T.enemyFainted or T.fainted, self:nameOf(v)) }
    elseif k == "weather" then
      self.weather = Gen2Facade.WEATHER[tostring(ev.weather or ""):upper()]
    elseif k == "msg" then
      local f = ev.fill or {}
      if ev.id == "STRINGID_USEDMOVE" then
        local atk = type(f.atk) == "table" and f.atk or {}
        local mv = moveOf(f.currentMove)
        local nxt = evs[i + 1]
        local e = { kind = "move", side = self:sideName(atk.side), move = self:moveKey(mv) or mv,
          text = Strings(T.usedMove, self:N(f.atk), self:moveName(mv)) }
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
          out[#out + 1] = { kind = "message", text = Strings(T.fainted, self:N(r)) }
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
          text = Strings("%s TRANSFORMED into %s!", self:N(f.atk), sp and self:speciesName(sp) or "?") }
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
    if action.kind == "item" then return s:refuseMenu(T.noItems) end
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
      s:refuseMenu(T.noItems)
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
