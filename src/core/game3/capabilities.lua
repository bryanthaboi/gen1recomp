local Profile = require("src.core.game3.profile")

local Capabilities = {}

Capabilities.NAMES = {
  easyChat = true,
  braille = true,
  mysteryGift = true,
  unionRoom = true,
  daycare = true,
  pokecenter = true,
  marts = true,
  moveRelearner = true,
  eggs = true,
  berries = true,
  sizeRecord = true, -- pokeemerald/src/pokemon_size_record.c
  helpSystem = true, -- pokefirered/src/help_system.c
  tmCase = true, -- pokefirered/src/tm_case.c
  fameChecker = true, -- pokefirered/src/fame_checker.c
  teachyTV = true, -- pokefirered/src/teachy_tv.c
  vsSeeker = true, -- pokefirered/src/vs_seeker.c
  trainerTower = true, -- pokefirered/src/trainer_tower.c
  seagallop = true, -- pokefirered/src/seagallop.c
  trainerFanClub = true, -- pokefirered/src/trainer_fan_club.c
  sevii = true,
  contests = true,
  secretBase = true,
  battleTower = true,
  berryPouch = true,
  matchCall = true,
  pokeNav = true,
}

Capabilities.CORE = {
  easyChat = true, braille = true, mysteryGift = true, unionRoom = true,
  daycare = true, pokecenter = true, marts = true, moveRelearner = true,
  eggs = true, berries = true, sizeRecord = true,
}

Capabilities.FRLG = {
  easyChat = true, braille = true, mysteryGift = true, unionRoom = true,
  daycare = true, pokecenter = true, marts = true, moveRelearner = true,
  eggs = true, berries = true, sizeRecord = true,
  helpSystem = true, tmCase = true, fameChecker = true, teachyTV = true,
  vsSeeker = true, trainerTower = true, seagallop = true,
  trainerFanClub = true, berryPouch = true, sevii = true,
}

Capabilities.RSE = {
  easyChat = true, braille = true, mysteryGift = true, unionRoom = true,
  daycare = true, pokecenter = true, marts = true, moveRelearner = true,
  eggs = true, berries = true, sizeRecord = true,
  battleTower = true, -- pokeemerald/src/battle_tower.c
  contests = true, secretBase = true, matchCall = true, pokeNav = true,
}

-- pokefirered/src/fame_checker.c
Capabilities.FEATURES = {
  fame_checker = {
    cap = "fameChecker",
    label = "Fame Checker",
    source = "pokefirered/src/fame_checker.c",
    counterpart = "absent from pokeemerald/pokeruby (ITEM_FAME_CHECKER is a leftover constant)",
    core = "src.core.game3.fame_checker",
    ui = "src.ui.game3.fame_checker",
    extractor = "fame_checker_extract",
    natives = "natives_fame",
  },
  teachy_tv = {
    cap = "teachyTV",
    label = "Teachy TV",
    source = "pokefirered/src/teachy_tv.c",
    counterpart = "absent from pokeemerald/pokeruby (ITEM_TEACHY_TV is a leftover constant)",
    core = "src.core.game3.teachy_tv",
    ui = "src.ui.game3.teachy_tv",
    extractor = "teachy_tv_extract",
  },
  vs_seeker = {
    cap = "vsSeeker",
    label = "VS Seeker",
    source = "pokefirered/src/vs_seeker.c",
    counterpart = "absent from pokeemerald/pokeruby (ITEM_VS_SEEKER is a leftover constant)",
    core = "src.core.game3.vs_seeker",
    data = "src.core.game3.vs_seeker_data",
  },
  trainer_tower = {
    cap = "trainerTower",
    label = "Trainer Tower",
    source = "pokefirered/src/trainer_tower.c",
    counterpart = "absent from pokeemerald/pokeruby (Emerald's src/battle_tower.c is a different mode)",
    core = "src.core.game3.trainer_tower",
    ui = "src.ui.game3.trainer_tower_records",
    extractor = "trainer_tower_extract",
    natives = "natives_tower",
  },
  seagallop = {
    cap = "seagallop",
    label = "Seagallop ferry",
    source = "pokefirered/src/seagallop.c",
    counterpart = "absent from pokeemerald/pokeruby",
    natives = "natives_seagallop",
    extractor = "seagallop_extract",
  },
  help_system = {
    cap = "helpSystem",
    label = "Help System",
    source = "pokefirered/src/help_system.c",
    counterpart = "absent from pokeemerald/pokeruby",
    ui = "src.ui.game3.help_system",
    extractor = "help_extract",
  },
  tm_case = {
    cap = "tmCase",
    label = "TM Case",
    source = "pokefirered/src/tm_case.c",
    counterpart = "absent from pokeemerald/pokeruby",
    ui = "src.ui.game3.tm_case",
    extractor = "tm_case_extract",
  },
  trainer_fan_club = {
    cap = "trainerFanClub",
    label = "Trainer Fan Club",
    source = "pokefirered/src/trainer_fan_club.c",
    counterpart = "absent from pokeemerald/pokeruby",
    core = "src.core.game3.trainer_fan_club",
    natives = "natives_fan_club",
  },
  berry_pouch = {
    cap = "berryPouch",
    label = "Berry Pouch",
    source = "pokefirered/src/berry_pouch.c",
    counterpart = "absent from pokeemerald/pokeruby (RSE keeps berries in the bag)",
    ui = "src.ui.game3.berry_pouch",
    extractor = "berry_pouch_extract",
  },
  contests = {
    cap = "contests",
    label = "Pokemon Contests",
    source = "pokeemerald/src/contest.c",
    counterpart = "absent from pokefirered",
  },
  secret_base = {
    cap = "secretBase",
    label = "Secret Bases",
    source = "pokeemerald/src/secret_base.c",
    counterpart = "absent from pokefirered",
  },
  match_call = {
    cap = "matchCall",
    label = "Match Call (Emerald)",
    source = "pokeemerald/src/match_call.c",
    counterpart = "absent from pokefirered and pokeruby (RS use the PokeNav)",
  },
  poke_nav = {
    cap = "pokeNav",
    label = "PokeNav",
    source = "pokeemerald/src/pokenav.c",
    counterpart = "absent from pokefirered",
  },
}

local warned = {}

local function log(msg)
  print("[game3/capabilities] " .. tostring(msg))
end

local function warnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  log(msg)
end

function Capabilities.of(session)
  return Profile.capabilitiesFor(session)
end

function Capabilities.has(session, cap)
  if not Capabilities.NAMES[cap] then
    warnOnce("cap:" .. tostring(cap), "unknown capability '" .. tostring(cap) .. "'")
    return false
  end
  return Capabilities.of(session)[cap] == true
end

function Capabilities.enabled(caps, featureId)
  local feature = Capabilities.FEATURES[featureId]
  if not feature or type(caps) ~= "table" then return false end
  return caps[feature.cap] == true
end

function Capabilities.gate(session, featureId)
  if not Capabilities.FEATURES[featureId] then
    warnOnce("feat:" .. tostring(featureId),
      "unknown feature '" .. tostring(featureId) .. "'")
    return false
  end
  return Capabilities.enabled(Capabilities.of(session), featureId)
end

local nativesIndex

function Capabilities.nativeFeature(moduleName)
  nativesIndex = nativesIndex or (function()
    local index = {}
    for id, feature in pairs(Capabilities.FEATURES) do
      if feature.natives then index[feature.natives] = id end
    end
    return index
  end)()
  if type(moduleName) ~= "string" then return nil end
  return nativesIndex[moduleName]
end

function Capabilities.nativeAllowed(session, moduleName)
  local featureId = Capabilities.nativeFeature(moduleName)
  if not featureId then return true end
  return Capabilities.gate(session, featureId)
end

function Capabilities.audit(caps)
  local problems = {}
  if type(caps) ~= "table" then
    problems[1] = "capabilities table is missing"
    return false, problems
  end
  for name, value in pairs(caps) do
    if not Capabilities.NAMES[name] then
      problems[#problems + 1] = "unknown capability '" .. tostring(name) .. "'"
    elseif type(value) ~= "boolean" then
      problems[#problems + 1] =
        "capability '" .. name .. "' is " .. type(value) .. ", not boolean"
    end
  end
  table.sort(problems)
  return #problems == 0, problems
end

function Capabilities.reset()
  warned = {}
end

return Capabilities
