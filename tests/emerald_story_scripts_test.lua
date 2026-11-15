package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local function cacheRoot()
  local explicit = os.getenv("POKEPORT_EMERALD_CACHE")
  if explicit and explicit ~= "" then return explicit end
  local identity = os.getenv("POKEPORT_IDENTITY")
  local home = os.getenv("HOME")
  if not (identity and identity ~= "" and home) then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE/", home .. "/.local/share/love/" }) do
    local root = base .. identity .. "/emerald"
    local f = io.open(root .. "/data/generated/gba/scripts/scripts.lua", "rb")
    if f then
      f:close()
      return root
    end
  end
  return nil
end

local ROOT = cacheRoot() or require("tests.game3_cache").gameDir("emerald", "scripts/scripts.lua")
if not ROOT then
  print("emerald_story_scripts_test: skipped (set POKEPORT_IDENTITY to an identity with an Emerald cache)")
  os.exit(0)
end

local function loadLua(rel)
  local f = io.open(ROOT .. "/" .. rel, "rb")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  local chunk = load(src, "@" .. rel, "t", {})
  return chunk and chunk() or nil
end

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("emerald")

local Opcodes = require("src.core.game3.scripting.opcodes")
local Natives = require("src.core.game3.scripting.natives")
local Movement = require("src.core.game3.scripting.movement")
local Constants = require("src.core.game3.constants")
local C = Constants.of("emerald")

local S = "data/generated/gba/scripts/"
local scripts = assert(loadLua(S .. "scripts.lua"), "scripts.lua")
local events = assert(loadLua(S .. "events.lua"), "events.lua")
local labels = assert(loadLua(S .. "labels.lua"), "labels.lua")
local movements = assert(loadLua(S .. "movements.lua"), "movements.lua")

local MAPS = {
  "EM_INSIDE_OF_TRUCK", "EM_LITTLEROOT_TOWN", "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F",
  "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", "EM_LITTLEROOT_TOWN_MAYS_HOUSE_1F", "EM_LITTLEROOT_TOWN_MAYS_HOUSE_2F",
  "EM_ROUTE101", "EM_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB",
}

local seeds, seen = {}, {}
local function add(k)
  if type(k) == "string" and not seen[k] then
    seen[k] = true
    seeds[#seeds + 1] = k
  end
end
for _, m in ipairs(MAPS) do
  local e = events[m]
  check(e ~= nil, m .. " has events")
  for _, o in ipairs(e and e.objects or {}) do add(o.scriptKey) end
  for _, o in ipairs(e and e.bgEvents or {}) do add(o.scriptKey) end
  for _, o in ipairs(e and e.coordEvents or {}) do add(o.scriptKey) end
  for _, v in pairs(e and e.mapScripts or {}) do
    if type(v) == "string" then add(v) else for _, r in ipairs(v) do add(r.script) end end
  end
end
add(labels.EventScript_TV)
add("EventScript_ResetAllMapFlags")

local opNames = {}
local set = Opcodes.forGame("emerald")
for byte = 0, set.MAX do
  local r = set:get(byte)
  if r then opNames[r.name] = true end
end
for _, alias in ipairs({ "goto_if", "call_if", "callstd_if", "gotostd_if", "vgoto_if", "vcall_if" }) do opNames[alias] = true end

local specials, unknownOps, moves = {}, {}, {}
local i = 1
while i <= #seeds do
  local key = seeds[i]
  i = i + 1
  for _, r in ipairs(scripts[key] or {}) do
    if not opNames[r.op] then unknownOps[r.op] = true end
    if r.op == "special" then specials[tonumber(r.id or r[1])] = true end
    if r.op == "specialvar" then specials[tonumber(r.id or r[2])] = true end
    if r.op == "callstd" or r.op == "gotostd" then add("std:" .. tostring(r.std or r[1])) end
    if r.op == "applymovement" then moves[#moves + 1] = r.movement or r[2] end
    for _, v in pairs(r) do
      if type(v) == "string" and v:match("^g3:") and scripts[v] then add(v) end
    end
  end
end
print(string.format("emerald_story_scripts_test: %d scripts reachable from the opening maps", #seeds))
check(#seeds > 300, "the opening maps reach more than 300 scripts")
local unk = {}
for k in pairs(unknownOps) do unk[#unk + 1] = k end
table.sort(unk)
eq(#unk, 0, "every op on the opening path is an Emerald opcode (" .. table.concat(unk, ",") .. ")")

Natives.bind("emerald")
local OPENING = {
  "ChooseStarter", "GetPlayerBigGuyGirlString", "GetRivalSonDaughterString", "ResetTVShowState",
  "CheckForPlayersHouseNews", "IsGabbyAndTyShowOnTheAir", "GetRandomActiveShowIdx", "GetNextActiveShowIfMassOutbreak",
  "GetSelectedTVShow", "GetMomOrDadStringForTVMessage", "TurnOffTVScreen", "TurnOnTVScreen", "DoTVShow", "DoPokeNews",
  "DoTVShowInSearchOfTrainers", "InitSecretBaseDecorationSprites", "StartWallClock", "Special_ViewWallClock",
  "HealPlayerParty", "ChangePokemonNickname", "ChangeBoxPokemonNickname", "EnableNationalPokedex",
}
local LATER = {
  BedroomPC = "W3 player PC",
  DoPCTurnOnEffect = "W3 PC metatile effect",
  GetPCBoxToSendMon = "W3 storage (party full path)",
  ShouldShowBoxWasFullMessage = "W3 storage (party full path)",
  HasAllHoennMons = "W3 dex (post-game lab)",
  ScriptGetPokedexInfo = "W3 dex rating",
  ShowPokedexRatingMessage = "W3 dex rating",
  SetUnlockedPokedexFlags = "W3 dex",
  InitRoamer = "E21 roamers (post-game)",
}
local opening = {}
for _, n in ipairs(OPENING) do opening[n] = true end
local unbound = {}
for id in pairs(specials) do
  local name = C.specials.byId[id]
  check(name ~= nil, string.format("special 0x%X has a pret name", id))
  local bound = Natives.ALLOW["special:" .. id] ~= nil
  if opening[name] then
    check(bound, "opening special " .. tostring(name) .. " is bound")
  elseif not bound then
    unbound[#unbound + 1] = name
    check(LATER[name] ~= nil, "unbound special " .. tostring(name) .. " is a documented later-wave item")
  end
end
table.sort(unbound)
for _, n in ipairs(unbound) do print("  later: " .. n .. " (" .. tostring(LATER[n]) .. ")") end

local nops = 0
for _, key in ipairs(moves) do
  local stream = movements[key]
  for _, b in ipairs(stream or {}) do
    if b >= 0x100 and Movement.decodeAction(b).kind == "nop" then nops = nops + 1 end
  end
end
eq(nops, 0, "no canonical RSE movement action on the opening path decodes to nop")

local man = loadLua("data/generated/gba/starter_choose/manifest.lua")
if check(man ~= nil, "starter_choose manifest in the cache") then
  -- pokeemerald/src/starter_choose.c:113
  eq(man.species[1], C.species.byName.SPECIES_TREECKO, "starter 0 is Treecko")
  eq(man.species[2], C.species.byName.SPECIES_TORCHIC, "starter 1 is Torchic")
  eq(man.species[3], C.species.byName.SPECIES_MUDKIP, "starter 2 is Mudkip")
  eq(man.pokeballCoords[2][1], 120, "middle ball x (starter_choose.c:99)")
  eq(man.pokeballCoords[2][2], 88, "middle ball y")
  eq(man.cursorCoords[3][1], 180, "right cursor x (starter_choose.c:204)")
  eq(man.windows.confirm.tilemapLeft, 24, "YES/NO window left (starter_choose.c:77)")
  eq(man.windows.message.width, 24, "message window width (starter_choose.c:63)")
  eq(man.affine.circle[1].xScale, 20, "circle affine starts at 20 (starter_choose.c:274)")
  eq(man.sprites.pokeball.frames, 3, "pokeball sheet has the still + two wobble frames")
end

Natives.bind("firered")
GameVersion.set(prevVersion)
T.finish()
