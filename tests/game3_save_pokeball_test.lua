package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
require("tests.game3_cache").stubSpeciesNames()

require("tests.love_stub")

local Schema = require("src.core.game3.save_schema_firered")
local SaveData = require("src.core.SaveData")
local BallOpen = require("src.core.game3.battle.ball_open")

local ok, fail = 0, 0
local function check(cond, msg)
  if cond then
    ok = ok + 1
  else
    fail = fail + 1
    print("FAIL: " .. msg)
  end
end

local old = {
  engine = "game3", version = "firered", map = "FR_PALLET_TOWN", x = 1, y = 1,
  party = {
    { species = 4, level = 5 },
    { species = 16, level = 3, pokeball = 2 },
  },
  storage = { currentBox = 1, items = {}, boxes = { [1] = { name = "BOX 1", wallpaper = 1, mons = { [3] = { species = 19, level = 2 } } } } },
}

local s = Schema.fromSaveTable(old)
check(s.party[1].pokeball == 4, "old save party mon without a ball loads as ITEM_POKE_BALL")
check(s.party[2].pokeball == 2, "stored ITEM_ULTRA_BALL kept on load")
local boxMon = s.storage and s.storage.boxes[1] and s.storage.boxes[1].mons[3]
check(boxMon and boxMon.pokeball == 4, "old save box mon without a ball loads as ITEM_POKE_BALL")

local legacy = Schema.fromSaveTable({ map = "FR_PALLET_TOWN", x = 1, y = 1 })
check(type(legacy.party) == "table" and #legacy.party == 0, "save with no party still loads")

local legacyPc = Schema.fromSaveTable({ map = "FR_PALLET_TOWN", x = 1, y = 1, pc = { items = {}, mons = { { species = 25, level = 9 } } } })
local pcMon = legacyPc.storage and legacyPc.storage.boxes[1].mons[1]
check(pcMon and pcMon.pokeball == 4, "legacy pc.mons mon defaults to ITEM_POKE_BALL")

s.party[1].pokeball = 1
local str = SaveData.encode(Schema.toSaveTable(s))
local back = Schema.fromSaveTable(SaveData.decode(str))
check(back.party[1].pokeball == 1, "ITEM_MASTER_BALL survives save round trip")
check(back.party[2].pokeball == 2, "ITEM_ULTRA_BALL survives save round trip")
check(back.storage.boxes[1].mons[3].pokeball == 4, "box mon ball survives save round trip")
check(BallOpen.ballIdForItem(back.party[2].pokeball) == 3, "loaded Ultra Ball mon resolves to BALL_ULTRA")
check(BallOpen.ballIdForItem(back.party[1].pokeball) == 4, "loaded Master Ball mon resolves to BALL_MASTER")

local okM, MonOps = pcall(require, "MonOps")
check(okM, "MonOps loads")
if okM then
  local okC, mon = pcall(MonOps.create, {}, 1, 5, 3)
  check(okC and type(mon) == "table" and mon.pokeball == 4, "save editor gen3 mon created with ITEM_POKE_BALL")
end

local Party = require("src.core.game3.party")
local sess = { party = {}, dex = { seen = {}, owned = {} } }
local okG = pcall(Party.giveMon, sess, 1, 5)
check(okG and sess.party[1] and sess.party[1].pokeball == 4, "givemon mon has ITEM_POKE_BALL")

print(("ok=%d fail=%d"):format(ok, fail))
os.exit(fail == 0 and 0 or 1)
