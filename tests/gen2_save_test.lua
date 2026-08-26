-- Gen 2 save file (src/core/gen2/Save.lua): naming, normalization, migration,
-- the CONTINUE summary, play-clock ticking, and the write/read round trip.
--
-- The filesystem is an in-memory stub, so this never touches a real save.

package.path = "./?.lua;" .. package.path

-- A memory filesystem standing in for love.filesystem.  Save.lua only uses
-- getInfo / read / write / remove, which is the whole contract this needs.
local files = {}
love = love or {}
love.filesystem = {
  getInfo = function(path)
    if files[path] then return { type = "file", size = #files[path] } end
    return nil
  end,
  read = function(path) return files[path] end,
  write = function(path, data)
    files[path] = data
    return true
  end,
  remove = function(path)
    files[path] = nil
    return true
  end,
}

local GameVersion = require("src.core.GameVersion")
local Save = require("src.core.gen2.Save")

local priorVersion = GameVersion.get()
GameVersion.set("gold")

local failures, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

-- ---------------------------------------------------------------- filenames

-- Gold's save sits beside Red/Blue/Yellow rather than sharing a file: its
-- suffix comes from GameVersion, which is what keeps a Gold playthrough from
-- overwriting a Red one.
local main, backup, tmp = Save.filenames("gold")
check("main file", main, "save_gold.lua")
check("backup file", backup, "save_gold.lua.bak")
check("staged file", tmp, "save_gold.lua.tmp")
check("gold suffix", GameVersion.saveSuffix("gold"), "_gold")
local sMain, sBackup, sTmp = Save.filenames("silver")
check("silver main file", sMain, "save_silver.lua")
check("silver backup file", sBackup, "save_silver.lua.bak")
check("silver staged file", sTmp, "save_silver.lua.tmp")
check("silver suffix", GameVersion.saveSuffix("silver"), "_silver")
-- Red keeps its historical un-suffixed name, so the two can never collide.
check("red is unsuffixed", GameVersion.saveSuffix("red"), "")

-- ----------------------------------------------------------------- new game

local fresh = Save.newGame({ playerName = "GOLD", rivalName = "SILVER" })
check("version", fresh.version, "gold")
check("generation", fresh.generation, 2)
check("format", fresh.format, Save.FORMAT)
check("player name", fresh.player.name, "GOLD")
check("rival name", fresh.rival.name, "SILVER")
-- With nothing passed, NewGame's own seed stands, and that seed is "???":
-- _ResetWRAM calls InitializeNPCNames, whose .Rival row is `db "???@"`
-- (engine/menus/intro_menu.asm:131, :193-214).  SILVER is NameRival's InitName
-- fallback (engine/events/specials.asm:80-91), which the officer scene applies
-- only after the keyboard closes, so every {RIVAL} line and every RIVAL1 battle
-- before that -- Cherrygrove included -- reads "???".
check("an unnamed rival is ???", Save.newGame().rival.name, "???")
local unnamed = Save.normalize({ player = {} })
check("and so is one on a save with no rival field", unnamed.rival.name, "???")
-- A new game starts with 3000 and an empty party at SPAWN_HOME.
check("starting money", fresh.player.money, 3000)
check("empty party", #fresh.party, 0)
check("spawn", fresh.spawn, "SPAWN_HOME")
check("no position yet", fresh.position, nil)
check("and starts on foot", fresh.playerState, Save.PLAYER_NORMAL)
check("clock at zero", fresh.playTime.hours, 0)
check("dex empty", next(fresh.pokedex.caught), nil)
-- A trainer ID is rolled so two saves are distinguishable.
check("trainer id in range",
  fresh.player.id >= 0 and fresh.player.id <= 65535, true)
-- _ResetWRAM rolls it out of hRandomSub/hRandomAdd (intro_menu.asm:41-49).
local rolled = Save.newGame({}).player.id
check("the trainer ID is a whole number", math.floor(rolled), rolled)
check("in wPlayerID's range", rolled >= 0 and rolled <= 65535, true)
check("and an explicit id wins", Save.newGame({ trainerId = 7 }).player.id, 7)

-- Options are Gold's own set, stored by name so a reordered enum cannot
-- silently repoint one.
local options = Save.defaultOptions()
check("default text speed", options.textSpeed, "MID")
check("default battle style", options.battleStyle, "SHIFT")
check("default sound", options.sound, "MONO")
check("battle scene on", options.battleScene, true)
check("menu account on", options.menuAccount, true)
check("frame 1", options.frame, 1)
-- defaultOptions hands out a copy: editing one save's options must not change
-- the next new game's.
options.textSpeed = "FAST"
check("defaults are copied", Save.defaultOptions().textSpeed, "MID")

-- -------------------------------------------------------------- normalize

-- A sparse or hand-edited save must come back indexable rather than crashing
-- the first screen that reads it.
local sparse = Save.normalize({ player = {} })
check("normalized version", sparse.version, GameVersion.get())
check("a Gen 2 version already on the table is kept",
  Save.normalize({ version = "silver", player = {} }).version, "silver")
check("and a Gen 1 one is replaced by the running edition",
  Save.normalize({ version = "red", player = {} }).version, "gold")
check("and Crystal is a Gen 2 version, so it keeps its own",
  Save.normalize({ version = "crystal", player = {} }).version, "crystal")
-- "nonesuch" is the deliberate never-a-game token: "gold" stood here until
-- Gold shipped, "crystal" until Crystal did.  This one never becomes a game.
check("as is a version this engine does not have",
  Save.normalize({ version = "nonesuch", player = {} }).version, "gold")
check("party exists", type(sparse.party), "table")
check("inventory exists", type(sparse.inventory), "table")
check("pokedex seen exists", type(sparse.pokedex.seen), "table")
check("phone book exists", type(sparse.phoneContacts), "table")
check("play time exists", type(sparse.playTime), "table")
check("name defaulted", sparse.player.name, "GOLD")
-- wPlayerGender is zeroed by _ResetWRAM and Gold never writes it, so a
-- normalized save has to come back with the field present rather than nil.
check("gender defaulted", sparse.player.gender, "male")
check("and a recorded gender is kept",
  Save.normalize({ player = { gender = "female" } }).player.gender, "female")
check("normalize rejects a non-table", Save.normalize("nope"), nil)

-- The blank-name fallback is table driven so Crystal can be a row rather than
-- a third arm of a two-way test (data/player_names.asm).
check("Gold's PlayerNameArray row", Save.defaultPlayerName("gold"), "GOLD")
check("Silver's", Save.defaultPlayerName("silver"), "SILVER")
check("Crystal's MalePlayerNameArray row",
  Save.defaultPlayerName("crystal"), "CHRIS")
check("and an unknown edition falls back to Gold's",
  Save.defaultPlayerName("nonesuch"), "GOLD")

-- Money and coins are clamped to their caps, and a negative is floored at 0.
local rich = Save.normalize({ player = { money = 9999999, coins = 99999 } })
check("money capped", rich.player.money, Save.MAX_MONEY)
check("coins capped", rich.player.coins, Save.MAX_COINS)
local broke = Save.normalize({ player = { money = -100 } })
check("money floored", broke.player.money, 0)

-- An over-long party is trimmed: a corrupt file must not feed a seventh mon
-- into battle.
local overfull = Save.normalize({ party = {
  {}, {}, {}, {}, {}, {}, {}, {},
} })
check("party trimmed to six", #overfull.party, Save.PARTY_SIZE)

-- move_mon.asm:143-149: a mon the player owns carries wPlayerID, so a save
-- written before the stamp existed is backfilled on load.
local legacy = Save.normalize({ player = { name = "GOLD", id = 4242 },
  party = { { species = "CYNDAQUIL", level = 5 } } })
check("an id-less save gets one", type(legacy.player.id), "number")
check("and an unstamped mon takes the player's ID", legacy.party[1].otId, 4242)
check("and the player's name", legacy.party[1].ot, "GOLD")

-- --------------------------------------------------------------- migration

-- Save.FORMAT must never move without a step to carry old files across, so
-- every format below the current one has an entry and the current one has
-- none.  Format 2 is the Hall of Fame roster, format 3 the script VM's WRAM
-- store, format 4 the MAIL structs (sPartyMail + sMailboxes), format 5 the
-- world state (wEventFlags and the w<Map>SceneID block) becoming load bearing,
-- format 6 wPlayerState, format 7 Mom's shopping pair (wWhichMomItem and
-- wMomItemTriggerBalance).
check("format is 7", Save.FORMAT, 7)
for from = 1, Save.FORMAT - 1 do
  check("a migration exists for format " .. from,
    type(Save.MIGRATIONS[from]), "function")
end
check("and none for the current format", Save.MIGRATIONS[Save.FORMAT], nil)
local old = Save.migrate({ format = 1 })
check("migrate lifts a format-1 save to the current one", old.format,
  Save.FORMAT)
check("and gives it an empty Hall of Fame", old.hallOfFame.count, 0)
check("with no roster", #old.hallOfFame.teams, 0)
check("and no pending post-game spawn", old.spawnAfterChampion, nil)
check("and an empty script memory store", next(old.scriptMem), nil)
local current = Save.migrate({ format = Save.FORMAT, hallOfFame = { count = 4 } })
check("migrate is a no-op at the current format", current.hallOfFame.count, 4)

-- A format-2 save (the Hall of Fame landed, scriptMem had not) loads clean:
-- the store arrives empty rather than nil, so the first readmem sees a 0 the
-- same way the cart's zero-filled WRAM would.
local preMem = Save.normalize(Save.migrate({ format = 2, party = {} }))
check("an old save gains the store", type(preMem.scriptMem), "table")
check("with nothing in it", next(preMem.scriptMem), nil)
check("and is at the current format", preMem.format, Save.FORMAT)

-- A format-4 save with no world state at all -- the shape a file written
-- before the snapshot reached the world has -- comes across clean rather than
-- nil-indexing World:loadPlayerData, and its empty bitfield is what makes that
-- routine fall back to InitializeEventsScript's seed.
local preWorld = Save.normalize(Save.migrate({ format = 4, party = {} }))
check("an old save gains the event bitfield", type(preWorld.events), "table")
check("with no flags set", next(preWorld.events), nil)
check("and the scene table", type(preWorld.mapScenes), "table")
check("with no map advanced", next(preWorld.mapScenes), nil)
check("and is at the current format", preWorld.format, Save.FORMAT)
check("and it loads without a quarantine",
  Save.emptyReport(Save.validate(preWorld)), true)
-- A format-4 file that DID record world state keeps it: the fields were always
-- written, format 5 is only where they started being read back.
local keptWorld = Save.normalize(Save.migrate({
  format = 4, party = {}, events = { [6] = 0x40 },
  mapScenes = { PLAYERS_HOUSE_1F = 1 },
}))
check("an old save keeps the flags it recorded", keptWorld.events[6], 0x40)
check("and the scenes", keptWorld.mapScenes.PLAYERS_HOUSE_1F, 1)

-- A format-5 save never wrote wPlayerState at all, so it comes across as
-- PLAYER_NORMAL -- which is what it has been loading as anyway, since a world
-- that read no state started the player on foot.
local preState = Save.normalize(Save.migrate({ format = 5, party = {} }))
check("an old save gains the player state", preState.playerState,
  Save.PLAYER_NORMAL)
check("and is at the current format", preState.format, Save.FORMAT)
check("and it loads without a quarantine",
  Save.emptyReport(Save.validate(preState)), true)

-- A format-6 save predates MomTriesToBuySomething, so neither of Mom's two
-- shopping bytes can have been written: both come across as NewGame's seed,
-- the ladder on its first rung and the threshold at MOM_MONEY.  A file that
-- had already banked money therefore starts buying from the bottom of the
-- list, which is what a cartridge with the same savings would do.
local MomShopping = require("src.core.gen2.MomShopping")
local preMom = Save.normalize(Save.migrate({
  format = 6, party = {}, mom = { savedMoney = 12345 },
}))
check("an old save gains the ladder index", preMom.mom.whichItem, 0)
check("and the consolation threshold", preMom.mom.triggerBalance,
  MomShopping.MOM_MONEY)
check("keeping the savings it had", preMom.mom.savedMoney, 12345)
check("and is at the current format", preMom.format, Save.FORMAT)
check("and it loads without a quarantine",
  Save.emptyReport(Save.validate(preMom)), true)
local newMom = Save.newGame({})
check("a new game seeds the same pair", newMom.mom.whichItem, 0)
check("with the threshold at MOM_MONEY", newMom.mom.triggerBalance,
  MomShopping.MOM_MONEY)

-- --------------------------------------------------- script memory validate

-- Script_readmem addresses are 16-bit and Script_writemem moves one byte, so
-- an entry outside those ranges cannot have come from a script and is
-- quarantined instead of being handed to the VM.
local dirty = Save.normalize({ scriptMem = {
  [0xd6a8] = 3,          -- wUndergroundSwitchPositions, plausible
  [0x1d6a8] = 1,         -- past $ffff
  [0xd7f1] = 300,        -- not a byte
  [0xd7f2] = "switch",   -- not a number at all
} })
local report = Save.validate(dirty)
check("the plausible byte survives", dirty.scriptMem[0xd6a8], 3)
check("the out-of-range address is gone", dirty.scriptMem[0x1d6a8], nil)
check("the over-large value is gone", dirty.scriptMem[0xd7f1], nil)
check("the non-numeric value is gone", dirty.scriptMem[0xd7f2], nil)
check("three entries quarantined", #report.lostScriptMem, 3)
check("and the report is not empty", Save.emptyReport(report), false)
-- A store that is not even a table is replaced wholesale rather than left to
-- nil-index the VM later.
local wrecked = Save.validate(Save.normalize({ scriptMem = 7 }))
check("a non-table store is quarantined", #wrecked.lostScriptMem, 1)
-- A save this port wrote passes through without a word.
check("a clean save reports nothing",
  Save.emptyReport(Save.validate(Save.newGame({}))), true)

-- ---------------------------------------------------- world state validate

-- wEventFlags is 256 bytes of bitfield, so a byte index past the last one or a
-- value that is not a byte could not have come from the cart's array, and
-- neither may reach Events:restore.  The scene ids get the same treatment: one
-- byte per map, keyed by the map id World:mapSceneOf looks up.
local dirtyWorld = Save.normalize({
  events = {
    [6] = 0x40,          -- EVENT_INITIALIZED_EVENTS, byte 6 bit 6
    [255] = 1,           -- the last byte of the array, still legal
    [256] = 1,           -- one past it
    [-1] = 1,            -- and before the start
    [10] = 300,          -- not a byte
    [11] = "set",        -- not a number at all
  },
  mapScenes = {
    PLAYERS_HOUSE_1F = 1,
    ELMS_LAB = 2.5,      -- a scene id is a whole byte
    [7] = 1,             -- not a map id
    ROUTE_29 = "two",    -- not a number
  },
})
local worldReport = Save.validate(dirtyWorld)
check("the seed byte survives", dirtyWorld.events[6], 0x40)
check("and so does the last byte of the array", dirtyWorld.events[255], 1)
check("a byte past the array is gone", dirtyWorld.events[256], nil)
check("a negative index is gone", dirtyWorld.events[-1], nil)
check("an over-large value is gone", dirtyWorld.events[10], nil)
check("a non-numeric value is gone", dirtyWorld.events[11], nil)
check("four event bytes quarantined", #worldReport.lostEvents, 4)
check("the plausible scene survives", dirtyWorld.mapScenes.PLAYERS_HOUSE_1F, 1)
check("a fractional scene is gone", dirtyWorld.mapScenes.ELMS_LAB, nil)
check("a non-string map key is gone", dirtyWorld.mapScenes[7], nil)
check("a non-numeric scene is gone", dirtyWorld.mapScenes.ROUTE_29, nil)
check("three scenes quarantined", #worldReport.lostMapScenes, 3)
check("and the report is not empty", Save.emptyReport(worldReport), false)
-- Keys survive the serializer as strings in some files; the bitfield is keyed
-- by NUMBER, so they come back as numbers here rather than sitting beside the
-- numeric ones where Events:restore would have to guess.
local stringKeyed = Save.normalize({ events = { ["6"] = 0x40 } })
Save.validate(stringKeyed)
check("a string byte index is folded back to a number",
  stringKeyed.events[6], 0x40)
check("and nothing is left under the string", stringKeyed.events["6"], nil)
-- Neither field being a table at all is replaced wholesale, the same as the
-- script store above.
local wreckedWorld = Save.validate(Save.normalize({ events = 9,
  mapScenes = "gone" }))
check("a non-table bitfield is quarantined", #wreckedWorld.lostEvents, 1)
check("a non-table scene list too", #wreckedWorld.lostMapScenes, 1)

-- wPlayerState is one of four names, and the round trip only works because
-- both ends agree on them: Save.PLAYER_STATES is the set World:loadPlayerData
-- tests a restored value against too.
check("PLAYER_NORMAL is a state", Save.PLAYER_STATES[Save.PLAYER_NORMAL], true)
check("so is the bike", Save.PLAYER_STATES.bike, true)
check("and both surf states", Save.PLAYER_STATES.surf
  and Save.PLAYER_STATES.surf_pika, true)
check("PLAYER_SKATE is not one", Save.PLAYER_STATES.skate, nil)
-- A save made on the bike keeps it; a state no cartridge could have written is
-- dropped to PLAYER_NORMAL rather than handed to a sprite lookup with no row.
local riding = Save.normalize({ playerState = "bike" })
check("a bike save keeps its state",
  Save.emptyReport(Save.validate(riding)) and riding.playerState, "bike")
local afloat = Save.normalize({ playerState = "surf_pika" })
Save.validate(afloat)
check("and a surfing one keeps its own sprite", afloat.playerState,
  "surf_pika")
local bogus = Save.normalize({ playerState = "skateboard" })
local stateReport = Save.validate(bogus)
check("an impossible state is dropped", bogus.playerState, Save.PLAYER_NORMAL)
check("and quarantined", #stateReport.lostPlayerState, 1)
check("so the report is not empty", Save.emptyReport(stateReport), false)
-- A raw byte -- what a hand-edited file or another tool might leave -- is not
-- a name either, and 1 would otherwise silently mean nothing at all.
local rawByte = Save.validate(Save.normalize({ playerState = 1 }))
check("a raw wPlayerState byte is quarantined too",
  #rawByte.lostPlayerState, 1)

-- --------------------------------------------------------------- summary

local summary = Save.summary(fresh)
check("summary name", summary.name, "GOLD")
check("summary badges", summary.badges, 0)
check("summary caught", summary.caught, 0)
check("summary hours", summary.hours, 0)

fresh.player.badges = { true, true, false }
fresh.pokedex.caught = { CYNDAQUIL = true, PIDGEY = true, RATTATA = false }
fresh.playTime = { hours = 12, minutes = 34, seconds = 0, frames = 0 }
summary = Save.summary(fresh)
check("counts only earned badges", summary.badges, 2)
check("counts only caught mons", summary.caught, 2)
check("summary time", ("%d:%02d"):format(summary.hours, summary.minutes),
  "12:34")
check("summary of nothing", Save.summary(nil), nil)

-- ------------------------------------------------------------- play clock

-- The clock ticks once per logic step, so 60 calls is one second.
local timed = Save.newGame()
for _ = 1, 60 do Save.tickPlayTime(timed) end
check("one second", timed.playTime.seconds, 1)
check("frames rolled over", timed.playTime.frames, 0)
for _ = 1, 60 * 59 do Save.tickPlayTime(timed) end
check("one minute", timed.playTime.minutes, 1)
check("seconds reset", timed.playTime.seconds, 0)
-- The cart caps at 999 hours rather than overflowing the trainer card's field.
timed.playTime = { hours = 999, minutes = 59, seconds = 59, frames = 59 }
Save.tickPlayTime(timed)
check("hours capped", timed.playTime.hours, 999)

-- -------------------------------------------------------- write and read

files = {}
check("no save yet", Save.exists("gold"), false)

local written = Save.newGame({ playerName = "ETHAN" })
written.player.money = 4321
written.party = { { species = "CYNDAQUIL", level = 7, hp = 20, maxHp = 22 } }
written.position = { map = "ROUTE_29", x = 5, y = 9, facing = "left" }
written.pokedex.caught.CYNDAQUIL = true
-- wUndergroundSwitchPositions after the Goldenrod switch room has been
-- worked: the VM's readmem / addval / writemem triple lands here, and this is
-- the field that used to evaporate on reload.
written.scriptMem[0xd6a8] = 2
-- The world state a reload has to come back with: wEventFlags as the byte ->
-- value bitfield Events:serialize writes (byte 6 bit 6 is
-- EVENT_INITIALIZED_EVENTS 54, byte 216 bit 7 is EVENT_PLAYERS_HOUSE_MOM_1
-- 1735) and the scene MeetMomScript leaves PLAYERS_HOUSE_1F on.  Both used to
-- evaporate on reload, which is what had MOM play her first-time scene again.
written.events[6] = 0x40
written.events[216] = 0x80
written.mapScenes.PLAYERS_HOUSE_1F = 1
-- And the third member of that block: this save was made on the BICYCLE, on
-- the route the position above puts it on.
written.playerState = "bike"
check("save wrote", Save.save(written), true)
check("save exists now", Save.exists("gold"), true)
check("no stray staged file", files["save_gold.lua.tmp"], nil)
check("stamped savedAt", type(written.savedAt), "number")

local loaded, recovered, err = Save.load("gold")
check("load succeeded", loaded ~= nil, true)
check("no recovery needed", recovered, nil)
check("no error", err, nil)
check("round-tripped name", loaded.player.name, "ETHAN")
check("round-tripped money", loaded.player.money, 4321)
check("round-tripped party", loaded.party[1].species, "CYNDAQUIL")
check("round-tripped position", loaded.position.map, "ROUTE_29")
check("round-tripped facing", loaded.position.facing, "left")
check("round-tripped dex", loaded.pokedex.caught.CYNDAQUIL, true)
check("round-tripped script memory", loaded.scriptMem[0xd6a8], 2)
-- The two halves of LoadPlayerData, through a real encode/decode: the flag
-- byte comes back keyed by NUMBER (a byte index that decoded as the string "6"
-- would read as an unset flag), and the map is still on the scene it was
-- advanced to.
check("round-tripped seed flag", loaded.events[6], 0x40)
check("round-tripped event byte", loaded.events[216], 0x80)
check("no flag byte under a string key", loaded.events["216"], nil)
check("round-tripped map scene", loaded.mapScenes.PLAYERS_HOUSE_1F, 1)
-- The third: a save made on the bike loads on the bike.
check("round-tripped player state", loaded.playerState, "bike")
-- Sparse, not a WRAM image: only the byte a script actually wrote is in the
-- file, and the load report is empty for a save this port wrote itself.
local memCount = 0
for _ in pairs(loaded.scriptMem) do memCount = memCount + 1 end
check("only the written byte is stored", memCount, 1)
local _, _, _, loadReport = Save.load("gold")
check("load reports a clean save", Save.emptyReport(loadReport), true)

-- A second write backs the first up, so the previous file is always
-- recoverable.  The file lives at saves/<version>/<slot>.lua since Gold grew
-- launcher slots (#1107); the flat save_gold.lua is only the migration source.
local SLOT = "saves/gold/slot1.lua"
written.player.money = 5555
Save.save(written)
check("backup written", files[SLOT .. ".bak"] ~= nil, true)
check("new value loads", Save.load("gold").player.money, 5555)

-- A corrupt main file falls back to the backup rather than losing the game.
files[SLOT] = "this is not a lua table"
local recoveredSave, how = Save.load("gold")
check("recovered from the backup", recoveredSave ~= nil, true)
check("recovery reported", how, "bak")
check("backup held the previous money", recoveredSave.player.money, 4321)

-- A staged .tmp is preferred over the backup: it is the newer of the two.
files[SLOT] = nil
files[SLOT .. ".tmp"] = files[SLOT .. ".bak"]
local staged, stagedHow = Save.load("gold")
check("recovered from the staged copy", staged ~= nil, true)
check("staged recovery reported", stagedHow, "tmp")

-- Nothing on disk at all is a clean miss, not an error.
files = {}
local missing, _, missingErr = Save.load("gold")
check("missing save", missing, nil)
check("missing reports why", missingErr, "missing")
check("exists is false again", Save.exists("gold"), false)

-- ------- per-mod save state rides the slot
--
-- Game2:adoptSave points the loader's mod.save backing at save.modData, the
-- way Gen 1 does (src/core/Game.lua:990).  Without it every mod.save:set
-- survives only until the process exits, which is invisible until a player
-- notices their settings reset every session.
do
  local Game2 = require("src.core.Game2")
  local loader = { modSave = { early = { seeded = true } } }
  local host = setmetatable({ mods = loader }, { __index = Game2 })

  local boot = Save.newGame({ playerName = "GOLD" })
  host:adoptSave(boot, true)
  check("boot seeds what entry chunks wrote", boot.modData.early.seeded, true)
  check("the backing is the save's own table", loader.modSave, boot.modData)

  loader.modSave.tester = { followers = 3 }
  Save.save(boot)
  local reloaded = Save.load("gold")
  check("modData round-trips through the Gold save",
    reloaded.modData and reloaded.modData.tester
      and reloaded.modData.tester.followers, 3)

  -- NEW GAME takes no carry-over: state from an abandoned session must not
  -- leak into a fresh slot
  local fresh = Save.newGame({ playerName = "GOLD" })
  host:adoptSave(fresh)
  check("a fresh slot starts empty", next(fresh.modData), nil)
  files = {}
end

-- ------- the same save, run as Silver
--
-- The blank name is the edition's own first PlayerNameArray row
-- (data/player_names.asm:12-23).
do
  GameVersion.set("silver")
  files = {}

  local born = Save.newGame({})
  check("a silver boot stamps silver", born.version, "silver")
  check("still generation 2", born.generation, 2)
  check("with the edition's own preset name", born.player.name, "SILVER")
  check("gold's preset is unchanged", Save.defaultPlayerName("gold"), "GOLD")
  check("and silver's is its own", Save.defaultPlayerName("silver"), "SILVER")
  check("the running edition answers with no argument",
    Save.defaultPlayerName(), "SILVER")

  check("a version-less save takes the running edition",
    Save.normalize({ player = {} }).version, "silver")
  check("and a gold save keeps gold on a silver boot",
    Save.normalize({ version = "gold", player = {} }).version, "gold")

  check("no silver save yet", Save.exists("silver"), false)
  check("silver save wrote", Save.save(born), true)
  check("silver save exists now", Save.exists("silver"), true)
  check("gold is untouched by it", Save.exists("gold"), false)

  local main = Save.filenames("silver")
  check("the silver file is silver's own", main, "saves/silver/slot1.lua")
  check("and it is the file on disk", files[main] ~= nil, true)
  local back = Save.load("silver")
  check("silver round-trips", back and back.player.name, "SILVER")
  check("keeping its stamp", back.version, "silver")

  files = {}
  GameVersion.set("gold")
end

GameVersion.set(priorVersion)

print(("gen2 save: %d checks, %d failures"):format(checks, failures))
-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an
-- exit here takes the whole tier down with it and silently skips every
-- suite listed after this one (see tests/harness.lua's T.suite note).
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
