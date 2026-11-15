package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local function loadRel(rel)
  local src = cache and cache.read and cache:read(rel)
  if type(src) ~= "string" then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  return chunk and chunk() or nil
end
local manifest = loadRel("data/generated/gba/pokemon/battle/manifest.lua")
if not (manifest and manifest.layout == "rse") then
  print("emerald_story_battles_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end

require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local BattleProfile = require("src.core.game3.battle.profile")
BattleProfile.reset()
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Kinds = require("src.core.game3.battle.kinds")
local BattleText = require("src.core.game3.battle.battle_text")
local Adapter = require("src.core.game3.battle.adapter")
local Commands = require("src.core.game3.battle.commands")
local Trainers = require("src.core.game3.scripting.trainers")
local Story = require("src.core.game3.scripting.natives_frontier_story")
local Roamer = require("src.core.game3.roamer")
local Rng = require("src.core.game3.rng")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local Runtime = require("src.core.game3.runtime")

local sess = { version = "emerald", name = "BRENDAN", trainerId = 12345, money = 1000, party = {}, gender = 0 }
local prevGet = Runtime.getSession
Runtime.getSession = function() return sess end

local function mon(name, level, moves)
  local m = { species = C.species.byName[name], level = level, moves = {}, pp = {} }
  for i, mv in ipairs(moves) do
    m.moves[i] = C.moves.byName[mv]
    m.pp[i] = 30
  end
  m.ivs = { hp = 10, atk = 10, def = 10, spa = 10, spd = 10, spe = 10 }
  m.evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  m = require("src.core.game3.battle.damage").ensureStats(m, level)
  m.hp = m.hp or m.maxHp
  return m
end

local seed = 0x2468
local function lcg(lo, hi)
  seed = (seed * 1103515245 + 24691) % 2147483648
  local v = math.floor(seed / 65536)
  if lo == nil then return v / 32768 end
  if hi == nil then return 1 + v % lo end
  return lo + v % (hi - lo + 1)
end

local function logIdx(needle, from)
  for i, t in ipairs(Ui.log and Ui.log() or {}) do
    if i >= (from or 1) and type(t) == "string" and t:gsub("[\n\r]", " "):find(needle, 1, true) then return i end
  end
  return nil
end

local bp = BattleProfile.get(sess)
eq(bp.backPics.wally, 6, "Wally back pic index (trainers.h:120)")
eq(bp.backPics.steven, 7, "Steven back pic index (trainers.h:121)")
eq(BattleProfile.get({ version = "firered" }).legendary, nil, "FireRed profile has no Emerald legendary rows")

-- pokeemerald/src/battle_controller_wally.c:188
local zig = Story.wallyZigzagoon(sess)
eq(zig.level, 7, "LoadWallyZigzagoon makes a level 7 Zigzagoon")
eq(#zig.moves, 1, "Wally's Zigzagoon knows only one move")
eq(zig.moves[1], C.moves.byName.MOVE_TACKLE, "and it is Tackle")
eq(zig.abilityNum, 1, "ability num forced to 1 (field_specials.c:1428)")
local partyBefore = #sess.party
Ui.reset({ headless = true })
local ok, err = Battle.start({
  headless = true, autoFight = true, session = sess, rng = lcg, wild = true,
  playerParty = { zig }, foe = { species = C.species.byName.SPECIES_RALTS, level = 5, gender = "M" },
  tutorialKind = "wally", onDone = function() end,
})
check(ok, "headless Wally tutorial starts " .. tostring(err or ""))
local stW = Battle.getState()
eq(stW and stW.result, "catch", "Wally catches Ralts")
eq(stW and stW.wallyState, 4, "Wally ran FIGHT, FIGHT, throw, BAG (battle_controller_wally.c:185)")
eq(Kinds.controllerOf(stW, 0), "tutorial", "player slot runs the Wally controller")
local iPause = logIdx("Wild RALTS appeared!")
local iBack = logIdx("come back") or logIdx("that's enough") or logIdx("Come back")
local iNow = logIdx(BattleText.get("STRINGID_YOUTHROWABALLNOWRIGHT", Adapter.fill(stW)):gsub("[\n\r]", " "):sub(1, 12))
local iUsed = logIdx("WALLY used")
local iGot = logIdx("RALTS was caught")
print(string.format("[info] wally log appeared=%s return=%s now=%s used=%s gotcha=%s", tostring(iPause),
  tostring(iBack), tostring(iNow), tostring(iUsed), tostring(iGot)))
check(iPause ~= nil, "intro says a wild Ralts appeared")
check(iBack and iNow and iUsed and iGot and iBack < iNow and iNow < iUsed and iUsed < iGot,
  "return mon, 'you throw a ball now', WALLY used, Gotcha (battle_scripts_2.s:193)")
eq(#sess.party, partyBefore, "the caught Ralts does not join the player's party")

-- pokeemerald/src/battle_setup.c:513
local g = Story.legendaryOpts(sess, C.species.byName.SPECIES_GROUDON)
eq(g.groudon, true, "Groudon battle sets the groudon scene kind")
eq(g.transitionId, C.battle.byName.B_TRANSITION_GROUDON, "Groudon transition")
eq(g.song, C.songs.byName.MUS_VS_KYOGRE_GROUDON, "Groudon music")
local k = Story.legendaryOpts(sess, C.species.byName.SPECIES_KYOGRE)
check(k.kyogre and k.transitionId == C.battle.byName.B_TRANSITION_KYOGRE, "Kyogre scene + transition")
local r = Story.legendaryOpts(sess, C.species.byName.SPECIES_RAYQUAZA)
check(r.rayquaza and r.song == C.songs.byName.MUS_VS_RAYQUAZA, "Rayquaza scene + MUS_VS_RAYQUAZA")
local d = Story.legendaryOpts(sess, C.species.byName.SPECIES_DEOXYS)
check(d.song == C.songs.byName.MUS_RG_VS_DEOXYS and d.transitionId == C.battle.byName.B_TRANSITION_BLUR,
  "Deoxys BLUR + MUS_RG_VS_DEOXYS")
local m = Story.legendaryOpts(sess, C.species.byName.SPECIES_MEW)
eq(m.transitionId, C.battle.byName.B_TRANSITION_GRID_SQUARES, "Mew GRID_SQUARES")
local fallback = Story.legendaryOpts(sess, C.species.byName.SPECIES_ZIGZAGOON)
check(fallback.groudon == true, "default case falls into Groudon (battle_setup.c:521)")
local rr = Story.regiOpts(sess, C.species.byName.SPECIES_REGICE)
check(rr.regi and rr.transitionId == C.battle.byName.B_TRANSITION_REGICE and rr.song == C.songs.byName.MUS_VS_REGI,
  "Regice transition + MUS_VS_REGI")
eq(BattleProfile.battleSong(bp, { wild = true, kind = "regi" }), C.songs.byName.MUS_VS_REGI, "regi kind music")
eq(BattleProfile.battleSong(bp, { wild = true }), C.songs.byName.MUS_VS_WILD, "Lati battle keeps MUS_VS_WILD")

Ui.reset({ headless = true })
ok, err = Battle.start({
  headless = true, autoFight = true, session = sess, rng = lcg, wild = true, legendary = true, groudon = true,
  playerParty = { mon("SPECIES_SWAMPERT", 80, { "MOVE_SURF" }) },
  foe = { species = C.species.byName.SPECIES_GROUDON, level = 70 }, onDone = function() end,
})
check(ok, "headless Groudon battle starts " .. tostring(err or ""))
local stG = Battle.getState()
eq(stG and stG.aiFlags, 0, "Emerald wild legendaries have no AI script (battle_ai_script_commands.c:361)")
check(stG and stG.kinds.groudon and stG.kinds.legendary, "Groudon kinds recorded")
local BattleBg = require("src.core.game3.battle.bg")
eq(BattleBg.env().SCENE_SHEET[BattleBg.terrainId()], "groudon", "battle scene is the Groudon cave scene (battle_bg.c:760)")
check(logIdx("GROUDON") ~= nil, "legendary intro names Groudon")

-- pokeemerald/src/battle_tower.c:2122
local steven = Story.stevenParty(sess)
eq(#steven, 3, "Steven brings three mons")
eq(steven[1].species, C.species.byName.SPECIES_METANG, "Metang")
eq(steven[2].species, C.species.byName.SPECIES_SKARMORY, "Skarmory")
eq(steven[3].species, C.species.byName.SPECIES_AGGRON, "Aggron")
eq(steven[1].level, 42, "Metang lv42")
eq(steven[3].ivs.spe, 31, "fixed IV 31")
eq(steven[1].evs.atk, 252, "Metang attack EVs")
eq(steven[2].personality, 1, "non-BUGFIX personality is the slot index (battle_tower.c:2984)")
eq(steven[1].moves[4], C.moves.byName.MOVE_METAL_CLAW, "Metang knows Metal Claw")
eq(steven[1].otId, 61226, "STEVEN_OTID")

local pl = { mon("SPECIES_SWAMPERT", 45, { "MOVE_SURF" }), mon("SPECIES_BLAZIKEN", 45, { "MOVE_FLAMETHROWER" }) }
local party = { pl[1], pl[2], steven[1], steven[2], steven[3] }
local st = State.new({ double = true, playerParty = party, foeParty = { mon("SPECIES_CAMERUPT", 40, { "MOVE_EMBER" }),
  mon("SPECIES_MIGHTYENA", 40, { "MOVE_BITE" }) }, foeHalf = 1, playerHalf = 2 })
st.session = sess
st.kinds = { partner = true, twoOpponents = true }
eq(st.player.partyIndex, 1, "player leads with the first chosen mon")
eq(st.battlers[2].partyIndex, 3, "Steven leads with Metang (battle_controllers.c:688)")
check(State.ownsSlot(st, 0, 2) and not State.ownsSlot(st, 0, 3), "player owns only the chosen half")
check(State.ownsSlot(st, 2, 5) and not State.ownsSlot(st, 2, 1), "Steven owns only his half")
eq(Kinds.controllerOf(st, 2), "aiPartner", "battler 2 is the in-game partner controller")
check(Commands.switchError(st, 4, true, 0) ~= nil, "player cannot switch to Steven's mons (party_menu.c:5807)")
eq(Engine.disobedient({ st = st, user = st.battlers[2] }), nil, "Steven's mons always obey (battle_util.c:3922)")
local Experience = require("src.core.game3.battle.experience")
eq(Experience.recipientOpts(st, steven[1]).traded, false, "no traded exp boost for Steven's mons (battle_script_commands.c:3384)")
pl[1].hp, pl[2].hp = 0, 0
st.player.mon.hp = 0
eq(Engine.checkEnd(st), "lose", "losing both chosen mons loses even with Steven standing (battle_script_commands.c:3543)")

sess.party = { mon("SPECIES_SWAMPERT", 45, { "MOVE_SURF", "MOVE_EARTHQUAKE" }),
  mon("SPECIES_BLAZIKEN", 45, { "MOVE_FLAMETHROWER" }), mon("SPECIES_SCEPTILE", 45, { "MOVE_LEAF_BLADE" }),
  mon("SPECIES_ZIGZAGOON", 5, { "MOVE_TACKLE" }) }
local original = {}
for i, p in ipairs(sess.party) do original[i] = p.species end
Story.savePlayerParty(sess)
Story.setSelectedOrder(sess, { 3, 1 })
Story.reducePartyToSelected(sess)
eq(#sess.party, 2, "ReducePlayerPartyToSelectedMons keeps the chosen mons")
eq(sess.party[1].species, original[3], "in the chosen order")
sess.party[1].level = 46
sess.frontier = nil
local fs = Story.BY_NAME
local ctx = { specialVars = {} }
local Rse = require("src.core.game3.rse.init")
local prevSV = Rse.specialVar
Rse.specialVar = function(_, id) return ctx.specialVars[id] or 0 end
ctx.specialVars[0x8004], ctx.specialVars[0x8005] = 2, 4
fs.CallFrontierUtilFunc(ctx)
ctx.specialVars[0x8004] = 6
fs.CallFrontierUtilFunc(ctx)
Rse.specialVar = prevSV
Story.loadPlayerParty(sess)
eq(#sess.party, 4, "LoadPlayerParty restores the full party")
eq(sess.party[3].level, 46, "frontier_saveparty wrote the battle mon back to its slot (frontier_util.c:907)")
eq(sess.party[4].species, original[4], "unchosen mons are untouched")

local haveB2 = loadRel("data/generated/gba/roamer/locations.lua") ~= nil
  and loadRel("data/generated/gba/safari/rse_tables.lua") ~= nil
if not haveB2 then
  print("[info] cache predates roamer_extract / safari_rse_extract: roamer and safari sections skipped (reimport)")
  Runtime.getSession = prevGet
  T.finish("emerald_story_battles_test")
  return
end

-- pokeemerald/src/roamer.c:35
check(Roamer.config(sess) ~= nil, "Emerald has a roamer profile row")
check(Roamer.config(sess) ~= Roamer.config({ version = "firered" }), "FireRed has its own roamer row")
local sets = Roamer.locationSets(Roamer.config(sess))
eq(#sets, 20, "20 roamer location sets extracted (roamer.c:35)")
eq(sets[1][1], "EM_ROUTE110", "first set starts on Route 110")
eq(sets[20][3], "EM_ROUTE110", "Route 134 links back to Route 110")
Rng.SeedRng(7)
Roamer.initRse(sess, false)
eq(sess.roamer.species, C.species.byName.SPECIES_LATIAS, "VAR_0x8004 = 0 -> Latias")
eq(sess.roamer.level, 40, "roamer level 40")
local heads = {}
for _, s in ipairs(sets) do heads[s[1]] = s end
check(heads[sess.roamer.map] ~= nil, "initial map is a location-set head")
Roamer.initRse(sess, true)
eq(sess.roamer.species, C.species.byName.SPECIES_LATIOS, "VAR_0x8004 = 1 -> Latios")
local legal = true
for _ = 1, 200 do
  local before = sess.roamer.map
  Roamer.move(sess, "map_transition", "EM_ROUTE101")
  local set = heads[before]
  local found = sess.roamer.map == before
  for _, s in ipairs(sets) do if s[1] == sess.roamer.map then found = found or true end end
  if set then for j = 2, 6 do if set[j] == sess.roamer.map then found = true end end end
  if not found then legal = false end
end
check(legal, "RoamerMove stays inside the location table")
local hits, tries = 0, 400
sess.roamer.map = "EM_ROUTE110"
for _ = 1, tries do
  local enc = Roamer.tryEncounter(sess, "EM_ROUTE110", "land")
  if enc then hits = hits + 1 end
end
check(hits > tries / 8 and hits < tries / 2, "roamer encounter rolls Random() % 4 (" .. hits .. "/" .. tries .. ")")
eq(Roamer.tryEncounter(sess, "EM_ROUTE101", "land"), nil, "no roamer off its map")
Roamer.onBattleEnd(sess, { hp = 12, status = 0 }, "run")
check(sess.roamer.active and sess.roamer.hp == 12, "running keeps the roamer active and saves its HP")
Roamer.onBattleEnd(sess, { hp = 12, status = 0 }, "teleport_player")
check(not sess.roamer.active, "non-BUGFIX: PLAYER_TELEPORTED (Roar) deactivates the roamer (battle_main.c:5240)")

-- pokeemerald/src/battle_util.c:559
local Rules = require("src.core.game3.battle.rules")
local Commands2 = require("src.core.game3.battle.commands")
local sfCfg = bp.safari
eq(sfCfg.steps, 500, "Emerald safari has 500 steps (safari_zone.c:61)")
local tables = Rules.safari.rseTables(sfCfg)
eq(tables.pkblToEscapeFactor[1][2], 5, "sPkblToEscapeFactor[1][ENTHRALLED] = 5")
eq(table.concat(tables.goNearCounterToCatchFactor, ","), "4,3,2,1", "sGoNearCounterToCatchFactor")
local sf = Rules.safari.newStateRse(190, sfCfg)
eq(sf.escapeFactor, 3, "escape factor starts at 3")
eq(sf.catchFactor, math.floor(190 * 100 / 1275), "catch factor = catchRate * 100 / 1275")
eq(Rules.safari.fleeRate(sf), 15, "flee rate = escapeFactor * 5 (battle_ai_script_commands.c:2031)")
eq(Rules.safari.goNear(sf, tables), "STRINGID_CREPTCLOSER", "first go near creeps closer")
eq(sf.catchFactor, math.floor(190 * 100 / 1275) + 4, "go near adds 4 to the catch factor")
eq(sf.escapeFactor, 7, "go near adds 4 to the escape factor")
Rules.safari.goNear(sf, tables); Rules.safari.goNear(sf, tables)
eq(Rules.safari.goNear(sf, tables), "STRINGID_CANTGETCLOSER", "fourth go near cannot get closer")
eq(sf.escapeFactor, 19, "escape factor keeps growing to the cap")
eq(Rules.safari.goNear(sf, tables), "STRINGID_CANTGETCLOSER", "still no closer")
eq(sf.escapeFactor, 20, "escape factor capped at 20")
local r = Rules.safari.throwPokeblock(sf, tables, 30)
eq(r, 1, "positive gain enthralls")
eq(sf.escapeFactor, 15, "first enthralling block lowers escape by 5")
eq(Rules.safari.throwPokeblock(sf, tables, 0), 0, "zero gain makes it curious")
eq(sf.escapeFactor, 13, "second curious block lowers escape by 2")
sf.escapeFactor = 2
Rules.safari.throwPokeblock(sf, tables, 5)
eq(sf.escapeFactor, 0, "non-BUGFIX: a factor equal to the step drops to 0 (battle_util.c:571 pokeblock throw glitch)")
sf.escapeFactor = 1
Rules.safari.throwPokeblock(sf, tables, 5)
eq(sf.escapeFactor, 1, "factor 1 is left alone")
local nat = 3
local gain = Rules.safari.pokeblockGain(tables, nat, { 10, 0, 0, 0, 0 })
eq(gain, 10 * tables.flavorCompatibility[nat * 5], "PokeblockGetGain uses gPokeblockFlavorCompatibilityTable")
local stS = { safari = true, session = sess }
eq(Commands2.playerAction(stS, 2).action, "pokeblock", "menu slot 2 is POKeBLOCK on Emerald")
eq(Commands2.playerAction(stS, 3).action, "go_near", "menu slot 3 is GO NEAR on Emerald")
eq(Commands2.playerAction({ safari = true, session = { version = "firered" } }, 2).action, "bait",
  "FireRed keeps BAIT (D8)")

Runtime.getSession = prevGet
T.finish("emerald_story_battles_test")
