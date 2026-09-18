-- Gate for the Gen 1 module facades a FireRed mod's require resolves to
-- (src/mods/Gen3Compat.lua), plus mod.world / mod.battle for Gen 3.

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen3 mod facade")
local check, eq = S.check, S.eq

local session = {
  map = "FR_OAKS_LAB", x = 6, y = 5, facing = "up",
  party = {}, money = 3000, name = "RED", rivalName = "BLUE",
  bag = { pockets = {} }, dex = { seen = {}, owned = { [4] = true } },
  flags = {}, vars = {},
  healMap = "FR_PLAYERS_HOUSE_1F", healX = 8, healY = 5,
}
local sessionLive = false

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return sessionLive and session or nil end,
}

local Player = { cellX = 6, cellY = 5, facing = "up", moving = false }
package.loaded["src.core.game3.player"] = Player

local maps = {
  FR_OAKS_LAB = { id = "FR_OAKS_LAB", width = 13, height = 13, warps = {} },
  FR_PALLET_TOWN = { id = "FR_PALLET_TOWN", width = 24, height = 20, warps = {} },
}

local mapLoads = {}
local MapStub = { current = "FR_OAKS_LAB" }
function MapStub.currentDef() return maps[MapStub.current] end
function MapStub.load(_mod, _game, mapId, opts)
  mapLoads[#mapLoads + 1] = { mapId = mapId, opts = opts }
  MapStub.current = mapId
  return true
end
package.loaded["src.core.game3.map"] = MapStub

local metatiles = {}
package.loaded["src.core.game3.field"] = {
  running = true, locked = false,
  setMetatile = function(x, y, m) metatiles[#metatiles + 1] = { x, y, m } end,
  respawnAtHeal = function() end,
}

local warps = {}
package.loaded["src.core.game3.warp"] = {
  isBusy = function() return false end,
  request = function(_mod, _game, mapId, x, y, facing, opts)
    warps[#warps + 1] = { mapId = mapId, x = x, y = y, facing = facing, opts = opts }
    return true
  end,
}

local store = { flags = {}, vars = {} }
local FLAG_IDS = { FLAG_SYS_POKEMON_GET = 0x828, SYS_POKEMON_GET = 0x828 }
package.loaded["src.core.game3.scripting.flags"] = {
  IDS = FLAG_IDS,
  VAR_IDS = { VAR_STARTER_MON = 0x4031 },
  getFlag = function(st, _, id) return st.flags[id] == true end,
  setFlag = function(st, _, id, on) st.flags[id] = on and true or nil end,
  getVar = function(st, _, id) return st.vars[id] or 0 end,
  setVar = function(st, _, id, v) st.vars[id] = v end,
}

local started = {}
local vm = { ctx = {}, isRunning = function() return false end }
package.loaded["src.core.game3.scripting.space"] = {
  store = store, vm = vm,
  bundle = { text = { ["g3:hello"] = "HELLO" } },
  startScript = function(key) started[#started + 1] = key return true end,
}

local tracks = {}
local npc = { localId = 1, cellX = 3, cellY = 4, facing = "down",
              visible = true, hidden = false, def = { localId = 1 } }
package.loaded["src.core.game3.objects"] = {
  PLAYER_LOCAL_ID = 0xFF,
  _order = { 1 }, _byId = { [1] = npc }, _defs = { { localId = 1 } },
  at = function(x, y) if x == 3 and y == 4 then return npc end end,
  startTrack = function(lid, actions, onDone)
    tracks[#tracks + 1] = { lid = lid, actions = actions }
    if onDone then onDone() end
  end,
  addObject = function() return true end,
  removeObject = function() return true end,
  facePlayer = function() end,
  scriptFace = function(eo, dir) eo.facing = dir end,
}

package.loaded["src.core.game3.collision"] = {
  inBounds = function(x, y) return x >= 0 and y >= 0 and x < 13 and y < 13 end,
  isWalkable = function() return true end,
  isWater = function() return false end,
  isGrass = function() return false end,
  warpAt = function() return nil end,
  behavior = function() return 0 end,
  canEnter = function(_g, x, y)
    if x < 0 or y < 0 or x >= 13 or y >= 13 then return false, "bounds" end
    if x == 7 and y == 5 then return false, "water" end
    return true
  end,
}

local reloadFns = {}
local vanillaFront = { image = "vanilla-front", w = 64, h = 64 }
local Pokemon = {
  _names = { [4] = "CHARMANDER", [29] = "NIDORAN♀", [122] = "MR. MIME",
             [151] = "MEW" },
  _front = {}, _back = {},
  _stats = { [151] = { hp = 100, atk = 100, def = 100, spe = 100, spa = 100,
                       spd = 100 } },
}
function Pokemon.name(sp) return Pokemon._names[sp] or "?????" end
function Pokemon.speciesFromName(name)
  local key = tostring(name):upper():gsub("[^%w]", "")
  for id, n in pairs(Pokemon._names) do
    if n:upper():gsub("[^%w]", "") == key then return id end
  end
  return nil
end
function Pokemon.stats(sp) return Pokemon._stats[sp] end
function Pokemon.speciesMeta() return { catchRate = 45 } end
function Pokemon.types() return { 14, 14 } end
function Pokemon.frontPic(sp) return Pokemon._front[sp] or vanillaFront end
function Pokemon.backPic(sp) return Pokemon._back[sp] or vanillaFront end
function Pokemon.knowsMove() return false end
function Pokemon.onReload(fn) reloadFns[#reloadFns + 1] = fn end
package.loaded["src.core.game3.pokemon"] = Pokemon

local Gen3Compat = require("src.mods.Gen3Compat")
local Gen2Compat = require("src.mods.Gen2Compat")

-- ------- 1. every served name resolves, once, to a table

local SERVED = Gen2Compat.modules()
for _, name in ipairs(SERVED) do
  check(Gen3Compat.serves(name), "served on Gen 3 as on Gen 2: " .. name)
  local a = Gen3Compat.resolve(name, "fixture")
  eq(type(a), "table", "resolves to a table: " .. name)
  check(a == Gen3Compat.resolve(name, "fixture"),
    "one stable table for the run: " .. name)
end
eq(#Gen3Compat.modules(), #SERVED, "Gen 3 serves exactly the Gen 2 names")
eq(Gen3Compat.resolve("src.world.WorldAPI"), require("src.world.game3.WorldAPI"),
  "WorldAPI is the game3 WorldAPI itself, so a patch lands on every mod.world")
check(not Gen3Compat.serves("src.script.Commands"),
  "src.script.Commands stays unserved, as on Gold")
check(Gen3Compat.resolve("src.battle.BattleState").newWild == nil,
  "no invented newWild on FireRed")

-- ------- 2. coverage

eq(Gen3Compat.COVERAGE_VERSION, 1, "the coverage contract is versioned")
for _, name in ipairs(Gen3Compat.modules()) do
  local row = Gen3Compat.coverage(name)
  check(row ~= nil, "coverage for " .. name)
  eq(row.module, name, "coverage names itself: " .. name)
  check(row.kind == "facade" or row.kind == "alias",
    "coverage kind is facade or alias: " .. name)
  for member, status in pairs(row.members) do
    check(status == "backed" or status == "warned" or status == "absent",
      ("%s.%s carries one of the three statuses"):format(name, member))
  end
end
eq(Gen3Compat.memberStatus("src.world.Collision", "load"), "warned",
  "Collision.load is present, answers nil and says so")
eq(Gen3Compat.memberStatus("src.battle.BattleState", "makeSafari"), "absent",
  "makeSafari is published absent")
eq(Gen3Compat.coverage("nope.nope"), nil, "an unserved name has no coverage")
local first = Gen3Compat.coverage("src.world.Collision")
first.members.canMove = "absent"
eq(Gen3Compat.memberStatus("src.world.Collision", "canMove"), "backed",
  "coverage hands back a fresh table each call")

local worldApiRow = Gen3Compat.coverage("src.world.WorldAPI")
local WorldAPI = require("src.world.game3.WorldAPI")
for member, status in pairs(worldApiRow.members) do
  if status ~= "absent" and member ~= "__index" then
    eq(type(WorldAPI[member]), "function",
      "published WorldAPI member exists: " .. member)
  end
end

-- ------- 3. the Game facade proxies a LIVE game

local writes = 0
local current = nil
local liveGame = {
  phase = "field", options = { textSpeed = 1 },
  data = { maps = maps, gen3Trainers = { tag = "trainers" } },
  writeOptions = function() writes = writes + 1 end,
}
Gen3Compat.bind(function() return current end)

local Game = Gen3Compat.resolve("src.core.Game", "fixture")
eq(Game.save, nil, "captured before a game exists, the facade reads nil")
current = liveGame
sessionLive = true
eq(Game.generation, 3, "the facade reports its generation")
check(Game.save ~= nil, "save fills in the moment a session is live")
eq(Game.save.party, session.party, "save.party IS the session party")
eq(Game.save.money, 3000, "save.money reads the session")
Game.save.money = 1234
eq(session.money, 1234, "a write through save lands on the session")
eq(Game.save.player.map, "OAKS_LAB", "save.player.map is the Gen 1 spelling")
eq(Game.save.player.gen3Map, "FR_OAKS_LAB", "and gen3Map is the raw id")
eq(Game.save.player.x, 6, "player x reads the live avatar")
eq(Game.save.flags.FLAG_SYS_POKEMON_GET, nil, "an unset flag reads nil")
Game.save.flags.SYS_POKEMON_GET = true
eq(store.flags[0x828], true, "a flag write by name lands in the live store")
eq(Game.save.flags.FLAG_SYS_POKEMON_GET, true, "and reads back under either name")
eq(Game.save.flags.EVENT_GOT_STARTER, nil,
  "a Gen 1 flag name FireRed lacks reads nil")
eq(Game.save.pokedex.caught.CHARMANDER, true, "pokedex.caught by species name")
eq(Game.data.trainers, liveGame.data.gen3Trainers, "data.trainers is gen3Trainers")
eq(Game.data.maps.PALLET_TOWN, maps.FR_PALLET_TOWN,
  "data.maps resolves a Gen 1 spelling to the FR_ id")
eq(Game.data.maps.FR_OAKS_LAB, maps.FR_OAKS_LAB, "and the raw id")
eq(Game.data.pokemon.MEW.index, 151, "data.pokemon is name keyed")
eq(Game.data.pokemon.MEW.baseStats.hp, 100, "with Gen 1 baseStats field names")
eq(Game.data.pokemon.MEW.spriteFront,
  "data/generated/gba/pokemon/front/151.rgba", "and the cache sprite path")
eq(Game.data.sprites, nil, "data.sprites has no Gen 3 backing and says so")
Game.writeOptions(Game)
eq(writes, 1, "writeOptions reaches Game3:writeOptions")
eq(Game.renderer, nil, "renderer is named unbacked, not the Gen 1 singleton")

eq(Gen3Compat.speciesName(122), "MR_MIME", "display names canonicalise")
eq(Gen3Compat.speciesName(29), "NIDORAN_F", "gender glyphs become _F / _M")
eq(Gen3Compat.gen3MapId("OAKS_LAB"), "FR_OAKS_LAB", "Gen 1 id to FR_ id")
eq(Gen3Compat.gen1MapId("FR_OAKS_LAB"), "OAKS_LAB", "FR_ id to Gen 1 id")

-- ------- 4. OverworldController

local OW = Gen3Compat.resolve("src.world.OverworldController")
eq(Game.overworld, OW, "Game.overworld is the facade while in the field")
eq(OW.map.id, "OAKS_LAB", "ow.map.id is the Gen 1 spelling")
eq(OW.map.gen3Id, "FR_OAKS_LAB", "ow.map.gen3Id is the raw id")
eq(OW.map.widthCells, 13, "ow.map answers the live def")
eq(OW.player, Player, "ow.player IS the game3 avatar")
eq(#OW.npcs, 1, "ow.npcs lists the visible event objects")
eq(OW.npcAtCell(3, 4), npc, "npcAtCell finds the object")
eq(OW:npcAtCell(3, 4), npc, "and answers a colon call the same")
check(OW.isOverworld, "isOverworld answers true")
eq(OW.healPoint().map, "PLAYERS_HOUSE_1F", "healPoint in the Gen 1 spelling")
OW.startWarpTo("PALLET_TOWN", 5, 6, "down")
eq(warps[#warps].mapId, "FR_PALLET_TOWN", "startWarpTo maps the id")
check(OW.scriptMove(Player, "left", 2), "scriptMove moves the player")
eq(tracks[#tracks].lid, 0xFF, "the player is localId 0xFF")
eq(#tracks[#tracks].actions, 2, "two step actions")
local refused = OW.scriptMove({}, "left", 1)
eq(refused, nil, "an entity with no localId is refused, not guessed")
liveGame.phase = "boot"
eq(Game.overworld, nil, "no overworld outside the field")
liveGame.phase = "field"

local Collision = Gen3Compat.resolve("src.world.Collision")
local mover = { cellX = 6, cellY = 5 }
check(Collision.canMove(nil, {}, mover, "up"), "an open cell is enterable")
local ok, why = Collision.canMove(nil, {}, mover, "right")
check(not ok and why == "tile", "water folds to reason 'tile'")
local ok2, why2 = Collision.canMove(nil, { { cellX = 6, cellY = 4 } }, mover, "up")
check(not ok2 and why2 == "entity", "an occupied cell is refused as 'entity'")

-- ------- 5. script ctx

local ctx = Gen3Compat.scriptCtx(vm)
eq(ctx.overworld.map.id, "OAKS_LAB", "ctx.overworld.map.id is the Gen 1 id")
eq(ctx.overworld.map.gen3Id, "FR_OAKS_LAB", "ctx.overworld.map.gen3Id is raw")
eq(ctx.save.party, session.party, "ctx.save.party is the live party")
eq(ctx.save.flags.FLAG_SYS_POKEMON_GET, true, "ctx.save.flags by name")
eq(ctx.runner, vm, "ctx.runner is the VM that raised it")
eq(ctx.game, liveGame, "ctx.game is the live Game3")
MapStub.current = "FR_PALLET_TOWN"
eq(ctx.overworld.map.id, "PALLET_TOWN", "answered at read time, not built")
MapStub.current = "FR_OAKS_LAB"

-- ------- 6. sprite overrides

local merged = { MEW = { spriteFront = "mods/x/assets/mew_front.png",
                         spriteBack = "mods/x/assets/mew_back.png" },
                 CHARMANDER = { spriteFront = "data/generated/gba/pokemon/front/4.rgba" } }
liveGame.mods = { content = { pokemon = {
  ops = { MEW = {}, CHARMANDER = {} },
  get = function(_, id) return merged[id] end,
} } }
Gen3Compat.applyMerged(liveGame)
local front = Pokemon.frontPic(151)
check(front ~= vanillaFront and front.w == 64 and front.h == 64,
  "Mew's front pic is the mod image on a 64x64 entry")
eq(front.path, "mods/x/assets/mew_front.png", "and it is the mod's path")
eq(Pokemon._front[151], front, "the cache entry is seeded")
eq(Pokemon.backPic(151).path, "mods/x/assets/mew_back.png", "back pic too")
eq(Pokemon.frontPic(4), vanillaFront, "a vanilla .rgba path leaves the pic alone")
eq(#reloadFns, 1, "Gen3Compat registered with Pokemon.onReload once")
Pokemon._front = {}
Pokemon._back = nil
reloadFns[1]()
eq(Pokemon._front[151] and Pokemon._front[151].path,
  "mods/x/assets/mew_front.png", "a reload re-seeds the cache")
Gen3Compat.applyMerged(liveGame)
eq(#reloadFns, 1, "a second applyMerged does not register twice")
local wrapped = Pokemon.frontPic
Gen3Compat.applyMerged(liveGame)
eq(Pokemon.frontPic, wrapped, "and does not wrap twice")
eq(Game.data.pokemon.MEW, merged.MEW, "a registry override wins in data.pokemon")

-- ------- 7. mod.world

local api = WorldAPI.new(liveGame, "fixture")
local here = api:current()
eq(here.mapId, "FR_OAKS_LAB", "current().mapId is the raw id")
eq(here.gen1MapId, "OAKS_LAB", "with the Gen 1 spelling alongside")
eq(here.x, 6, "current().x is the live avatar")
check(api:warpTo("PALLET_TOWN", 1, 2), "warpTo takes a Gen 1 spelling")
eq(warps[#warps].mapId, "FR_PALLET_TOWN", "and warps to the FR_ map")
local nope, reason = api:warpTo("NOWHERE", 1, 2)
check(nope == nil and reason:find("unknown map"), "an unknown map is refused")
check(api:setFlag("FLAG_SYS_POKEMON_GET", false), "setFlag by name")
eq(api:getFlag("SYS_POKEMON_GET"), nil, "getFlag reads it back cleared")
local bad, err = api:setFlag("EVENT_GOT_STARTER", true)
check(bad == nil and err:find("unknown FireRed flag"),
  "a Gen 1 flag name is refused by name")
local q, qerr = api:queueScript({ { "text", "hi" }, { "give_item", "POTION" } })
check(q == nil and qerr:find("give_item"), "queueScript refuses an unknown verb up front")
local handle = api:npc("OAKS_LAB", 1)
check(handle ~= nil, "npc resolves by localId on the active map")
check(handle:scriptMove("up", 1), "a handle walks its object")
eq(tracks[#tracks].lid, 1, "through Objects.startTrack with its localId")
eq(select(1, handle:position()), 3, "position reads the live object")
local wild, werr = api:startWildBattle("MISSINGNO", 5)
check(wild == nil and werr:find("unknown species"), "an unknown species is refused")
check(api:replaceBlock(2, 3, 0x2A), "replaceBlock sets a metatile")
eq(metatiles[#metatiles][3], 0x2A, "through Field.setMetatile")

-- ------- 8. mod.battle

local BattleAPI = require("src.battle.game3.BattleAPI")
local battle = BattleAPI.new(liveGame)
eq(battle:snapshot(), nil, "no snapshot without a battle")
local handled = {}
local Ui = { _mode = "menu", _menuIndex = 1 }
function Ui.handleInput(input)
  handled[#handled + 1] = input:wasPressed("a") and "a"
    or input:wasPressed("b") and "b" or "?"
end
package.loaded["src.core.game3.battle.ui"] = Ui
local mon = { species = 151, level = 20, hp = 50, maxHp = 60, moves = { 1 }, pp = { 35 } }
local foe = { species = 4, level = 5, hp = 19, maxHp = 19, moves = {} }
local battleState = { kind = "wild", wild = true, turn = 2,
  playerParty = { mon }, player = { mon = mon }, enemy = { mon = foe } }
package.loaded["src.core.game3.battle.init"] = {
  _phase = "command",
  isActive = function() return true end,
  getState = function() return battleState end,
}
local snap = battle:snapshot()
check(snap ~= nil, "a snapshot while a battle runs")
eq(snap.kind, "wild", "kind")
eq(snap.prompt, "menu", "prompt reads the FireRed command menu")
eq(snap.player.species, "MEW", "species is the Gen 1-style name")
eq(snap.player.gen3Species, 151, "with the FireRed number alongside")
eq(snap.enemy.hp, 19, "enemy hp")
check(battle:submit({ id = 1, revision = snap.revision, kind = "menu",
  choice = "fight" }), "a menu intent submits")
eq(Ui._menuIndex, 1, "FIGHT is menu index 1")
eq(handled[#handled], "a", "and is confirmed with A")
local stale = battle:submit({ id = 2, revision = -1, kind = "menu", choice = "run" })
eq(stale, nil, "a stale revision is refused")
local replay = battle:submit({ id = 1, revision = snap.revision, kind = "menu",
  choice = "run" })
eq(replay, nil, "a replayed id is refused")

S.finish()
