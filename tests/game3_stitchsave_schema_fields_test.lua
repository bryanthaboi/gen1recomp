#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").stubSpeciesNames()

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local Schema = require("src.core.game3.save_schema_firered")
local Rng = require("src.core.game3.rng")
local Flags = require("src.core.game3.scripting.flags")

local FLAG_SYS_SAFARI_MODE = 0x800
local VAR_SAFARI_ENTRANCE = 0x406E

print("[test] 1. New Game rolls a secret id in pret's order")
do
  -- pokefirered/src/new_game.c:103 SeedWildEncounterRng, then :123 InitPlayerTrainerId
  Rng.SeedRng(0x2468)
  Rng.Random()
  local expected = Rng.Random()

  local session = Schema.newGame({ rngSeed = 0x2468 })
  eq(session.trainerId, 0x2468, "trainerId is the timer seed")
  check(type(session.secretId) == "number", "newGame stamps a numeric secretId")
  check(type(session.secretId) == "number"
    and session.secretId >= 0 and session.secretId < 0x10000, "secretId is 16 bit")
  eq(session.secretId, expected, "secretId is the Random() after the wild seed")

  local other = Schema.newGame({ rngSeed = 0x1357 })
  check(other.secretId ~= session.secretId, "a different seed rolls a different secret id")
end

print("[test] 2. secretId survives save and load")
do
  local session = Schema.newGame({ rngSeed = 0x4242 })
  local secret = session.secretId
  local save = Schema.toSaveTable(session)
  eq(save.secretId, secret, "toSaveTable writes secretId")
  local loaded = Schema.fromSaveTable(save)
  eq(loaded.secretId, secret, "fromSaveTable restores secretId")
  eq(loaded.trainerId, session.trainerId, "and trainerId beside it")

  local Catching = require("src.core.game3.battle.catching")
  loaded.party = {}
  loaded.storage = nil
  eq(Catching.playerSecretId(loaded), secret,
    "an empty party still reports the saved secret id")
end

print("[test] 3. An old save with none of the three fields loads clean")
do
  local old = {
    schemaVersion = 1, engine = "game3", version = "firered",
    name = "RED", rivalName = "BLUE", gender = 0, money = 3000, coins = 0,
    trainerId = 31337,
    party = { { species = 1, speciesId = 1, level = 7, hp = 22, maxHp = 22,
                otId = 31337, otSecretId = 4242 } },
    dex = { seen = {}, owned = {} },
    map = "FR_PALLET_TOWN", x = 5, y = 6, facing = "down",
    flags = {}, vars = {},
  }
  local loaded = Schema.fromSaveTable(old)
  eq(loaded.secretId, nil, "no secretId in, no secretId out")
  eq(loaded.safari, nil, "no safari block")
  eq(loaded.mail, nil, "no mail pool")
  eq(#loaded.party, 1, "the party is not quarantined")
  eq(loaded.party[1].otSecretId, 4242, "the mon keeps its own secret id")
  eq(loaded.orphaned, nil, "nothing was orphaned")

  local Catching = require("src.core.game3.battle.catching")
  eq(Catching.playerSecretId(loaded), 4242,
    "the old-save recovery path still reads it off an owned mon")

  local again = Schema.fromSaveTable(Schema.toSaveTable(loaded))
  eq(again.secretId, 4242, "and the next save persists what was recovered")
end

print("[test] 4. Continue clears safari mode, whatever spelling the save used")
do
  local save = {
    schemaVersion = 1, engine = "game3", version = "firered",
    party = {}, dex = { seen = {}, owned = {} },
    map = "FR_FUCHSIA_CITY", x = 4, y = 4,
    flags = {
      [FLAG_SYS_SAFARI_MODE] = true,
      [tostring(FLAG_SYS_SAFARI_MODE)] = true,
      ["FLAG_SYS_SAFARI_MODE"] = true,
      [tostring(0x828)] = true,
    },
    vars = {
      [tostring(VAR_SAFARI_ENTRANCE)] = 1,
      ["VAR_MAP_SCENE_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE"] = 1,
      [tostring(0x4001)] = 3,
    },
    safari = { balls = 17, steps = 412 },
  }
  local loaded = Schema.fromSaveTable(save)
  -- pokefirered/src/overworld.c:1695 CB2_ContinueSavedGame
  check(Flags.getFlag(loaded, nil, FLAG_SYS_SAFARI_MODE) == false,
    "ResetSafariZoneFlag_ clears FLAG_SYS_SAFARI_MODE on Continue")
  eq(loaded.flags[FLAG_SYS_SAFARI_MODE], nil, "the numeric key is gone")
  eq(loaded.flags[tostring(FLAG_SYS_SAFARI_MODE)], nil, "the decimal key is gone")
  eq(loaded.flags["FLAG_SYS_SAFARI_MODE"], nil, "the name key is gone")
  eq(loaded.flags[tostring(0x828)], true, "an unrelated flag is untouched")

  eq(Flags.getVar(loaded, nil, VAR_SAFARI_ENTRANCE), 0,
    "Overworld_ResetStateOnContinue zeroes the entrance scene var")
  eq(loaded.vars[tostring(VAR_SAFARI_ENTRANCE)], nil, "no stale decimal var key")
  eq(loaded.vars["VAR_MAP_SCENE_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE"], nil,
    "no stale named var key")
  eq(loaded.vars[tostring(0x4001)], 3, "an unrelated var is untouched")

  eq(loaded.safari, nil, "gNumSafariBalls and the step counter do not come back")

  local session = Schema.newGame({ rngSeed = 7 })
  session.safari = { balls = 30, steps = 600 }
  eq(Schema.toSaveTable(session).safari, nil,
    "and they are EWRAM, so no save block ever carries them")

  local stranded = Schema.fromSaveTable({
    schemaVersion = 1, engine = "game3", version = "firered",
    party = {}, dex = { seen = {}, owned = {} },
    map = "FR_SAFARI_ZONE_CENTER", x = 26, y = 30, facing = "up",
    flags = {}, vars = {},
  })
  -- pokefirered/data/scripts/safari_zone.inc:7 SafariZone_EventScript_Exit
  eq(stranded.map, "FR_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE", "a save left in the zone resumes at the gate")
  eq(stranded.x, 4, "gate x")
  eq(stranded.y, 1, "gate y")
  eq(Flags.getVar(stranded, nil, VAR_SAFARI_ENTRANCE), 1, "entrance ExitWarpIn scene queued")
  local again = Schema.fromSaveTable(Schema.toSaveTable(stranded))
  eq(again.map, "FR_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE", "second Continue stays at the gate")
end

print("[test] 5. The mail pool rides the save through mail.lua")
do
  local KEY = "src.core.game3.mail"
  local prev = package.loaded[KEY]

  local exported, restored = nil, nil
  package.loaded[KEY] = {
    export = function(session)
      exported = session
      return { pool = { [1] = { item = 121, words = { 1, 2, 3 } } } }
    end,
    restore = function(saved)
      restored = saved
      return saved and { pool = saved.pool, live = true } or nil
    end,
  }

  local session = Schema.newGame({ rngSeed = 9 })
  local save = Schema.toSaveTable(session)
  check(exported == session, "toSaveTable hands the session to Mail.export")
  check(type(save.mail) == "table" and save.mail.pool[1].item == 121,
    "the exported pool lands in the save table")

  local loaded = Schema.fromSaveTable(save)
  check(restored == save.mail, "fromSaveTable hands the saved pool to Mail.restore")
  check(type(loaded.mail) == "table" and loaded.mail.live == true,
    "and the restored pool lands on the session")

  package.loaded[KEY] = { GIVE_MAIL = 1 }
  local bare = Schema.newGame({ rngSeed = 11 })
  bare.mail = { pool = {} }
  local bareSave = Schema.toSaveTable(bare)
  check(bareSave.mail == bare.mail,
    "a mail module without export is a no-op, the raw field passes through")
  eq(Schema.fromSaveTable(bareSave).mail, bare.mail,
    "and so is one without restore")

  package.loaded[KEY] = prev
end

print("[test] 6. A script gift mon carries the player's secret id")
do
  local Pokemon = require("src.core.game3.pokemon")
  Pokemon.install(nil)
  local Party = require("src.core.game3.party")
  local session = Schema.newGame({ rngSeed = 0x0F0F })
  -- pokefirered/src/script_pokemon_util.c:48 ScriptGiveMon
  local code, mon = Party.giveMonToPlayer(session, 1, 5, "BULBASAUR")
  eq(code, Party.MON_GIVEN_TO_PARTY, "the gift went to the party")
  eq(mon.otId, session.trainerId, "stamped with the visible trainer id")
  check(type(mon.otSecretId) == "number", "and with a numeric secret half")
  eq(mon.otSecretId, session.secretId, "which is the player's own")
end

print("[test] 7. the SaveBlock1 warp slots ride the save")
do
  -- pokefirered/include/global.h:764
  local session = Schema.newGame({ rngSeed = 0x77 })
  eq(session.dynamicWarp, nil, "a New Game has no dynamic warp")
  eq(session.escapeWarp, nil, "and no escape warp")

  session.map = "FR_SILPH_CO_ELEVATOR"
  -- pokefirered/src/overworld.c:600 SetDynamicWarp
  session.dynamicWarp = { map = "FR_SILPH_CO_5F", warpId = 255, x = 22, y = 3 }
  -- pokefirered/src/overworld.c:651 SetEscapeWarp
  session.escapeWarp = { map = "FR_PEWTER_CITY", warpId = 255, x = 14, y = 8 }

  local save = Schema.toSaveTable(session)
  eq((save.dynamicWarp or {}).map, "FR_SILPH_CO_5F", "toSaveTable writes the dynamic warp")
  eq((save.escapeWarp or {}).map, "FR_PEWTER_CITY", "and the escape warp")

  local loaded = Schema.fromSaveTable(save)
  eq((loaded.dynamicWarp or {}).map, "FR_SILPH_CO_5F", "the lift exit survives the reload")
  eq((loaded.dynamicWarp or {}).x, 22, "with its recorded x")
  eq((loaded.dynamicWarp or {}).y, 3, "and its y")
  eq((loaded.escapeWarp or {}).map, "FR_PEWTER_CITY", "so does the escape warp")
  eq((loaded.escapeWarp or {}).y, 8, "with its doorstep y")

  local old = Schema.fromSaveTable({
    schemaVersion = 1, engine = "game3", version = "firered",
    party = {}, dex = { seen = {}, owned = {} },
    map = "FR_PALLET_TOWN", x = 5, y = 6, facing = "down", flags = {}, vars = {},
  })
  eq(old.dynamicWarp, nil, "an old save without the slots loads with none")
  eq(old.escapeWarp, nil, "neither half is invented")

  local junk = Schema.fromSaveTable({
    schemaVersion = 1, engine = "game3", version = "firered",
    party = {}, dex = { seen = {}, owned = {} },
    map = "FR_PALLET_TOWN", x = 5, y = 6, facing = "down", flags = {}, vars = {},
    dynamicWarp = "FR_SILPH_CO_5F", escapeWarp = 7,
  })
  eq(junk.dynamicWarp, nil, "a non-table dynamic warp is dropped")
  eq(junk.escapeWarp, nil, "and so is a non-table escape warp")
end

print("[test] 8. the flash level is saved with the block it lives in")
do
  -- pokefirered/include/global.h:770
  local Runtime = require("src.core.game3.runtime")
  local FieldView = require("src.core.game3.field_view")
  local prev = Runtime.session

  local session = Schema.newGame({ rngSeed = 0x78 })
  eq(session.flashLevel, 0, "a New Game starts with no flash level")

  Runtime.session = session
  -- pokefirered/src/overworld.c:966 SetFlashLevel
  FieldView.setFlashLevel(FieldView.MAX_FLASH_LEVEL)
  eq(session.flashLevel, FieldView.MAX_FLASH_LEVEL,
    "SetFlashLevel writes the level into the save block")

  local loaded = Schema.fromSaveTable(Schema.toSaveTable(session))
  eq(loaded.flashLevel, FieldView.MAX_FLASH_LEVEL,
    "saving in a dark cave and reloading keeps the level")

  local old = Schema.fromSaveTable({
    schemaVersion = 1, engine = "game3", version = "firered",
    party = {}, dex = { seen = {}, owned = {} },
    map = "FR_PALLET_TOWN", x = 5, y = 6, facing = "down", flags = {}, vars = {},
  })
  eq(old.flashLevel, nil, "a save with no flashLevel key loads without one")
  -- pokefirered/src/overworld.c:956 SetDefaultFlashLevel
  Runtime.session = old
  eq(FieldView.setDefaultFlashLevel(nil, "FR_PALLET_TOWN"), 0,
    "so the map load falls back to the default for the map")
  eq(old.flashLevel, 0, "and that default is what the next save carries")

  Runtime.session = prev
end

print("[test] berryPowder round-trips through the schema")
do
  -- include/global.h:354, src/berry_powder.c:50
  local session = Schema.newGame({ rngSeed = 0x99 })
  eq(session.berryPowder, 0, "a New Game starts with 0 berry powder")

  session.berryPowder = 40
  local save = Schema.toSaveTable(session)
  eq(save.berryPowder, 40, "toSaveTable writes berryPowder")
  local loaded = Schema.fromSaveTable(save)
  eq(loaded.berryPowder, 40, "fromSaveTable restores berryPowder")

  local old = Schema.fromSaveTable({
    schemaVersion = 1, engine = "game3", version = "firered",
    party = {}, dex = { seen = {}, owned = {} },
    map = "FR_PALLET_TOWN", x = 5, y = 6, facing = "down", flags = {}, vars = {},
  })
  eq(old.berryPowder, 0, "a save with no berryPowder key loads 0")
end

print(string.format("[test] %d passed, %d failed", passed, failed))
if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
