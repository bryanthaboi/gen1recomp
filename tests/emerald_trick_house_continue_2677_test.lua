package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Trick House end room survives Continue #2677")
local root = os.getenv("POKEPORT_EMERALD_CACHE")
if not root then
  local home, id = os.getenv("HOME"), os.getenv("POKEPORT_EMERALD_IDENTITY")
  local candidate = home and id and (home .. "/Library/Application Support/LOVE/" .. id .. "/emerald/data/generated/gba")
  local f = candidate and io.open(candidate .. "/meta.json", "rb")
  if f then f:close() root = candidate end
end
root = root or require("tests.game3_cache").root("emerald")
if not root then print("SKIP #2677 Trick House continue requires an Emerald cache"); T.finish(); return end
require("src.core.GameVersion").set("emerald")
require("src.import.gba.versions").select("emerald")
local Dataset = require("src.core.game3.dataset"); Dataset.cacheRootOverride = root
require("src.core.game3.profile").reset()
local Schema = require("src.core.game3.save_schema_firered")
local SaveData = require("src.core.SaveData")
local Runtime = require("src.core.game3.runtime")
local session = Schema.newGame({ version = "emerald", name = "BRENDAN" })
local game = { session = session, save = Schema.toSaveTable(session) }
Dataset.hydrate(game)
Runtime.start(nil, game, session, { alreadyOnMap = true })
local Map = require("src.core.game3.map")
local Space = require("src.core.game3.scripting.space")
local Objects = require("src.core.game3.objects")
local Rse = require("src.core.game3.rse.init")

local END = "EM_ROUTE110_TRICK_HOUSE_END"
local CORRIDOR = "EM_ROUTE110_TRICK_HOUSE_CORRIDOR"
T.check(game.data.maps[END] ~= nil and Space.ensureBundle(nil).events[END] ~= nil, "the end room is in the cache")

local function settle()
  for _ = 1, 256 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    Space.vm:tick()
  end
end
local function load(mapId, x, y, via)
  Map.load(nil, game, mapId, { x = x, y = y, facing = "up", enterVia = via })
  settle()
end
local function master()
  local eo = Objects.find(1)
  return eo and eo.visible == true and eo.hidden ~= true and eo or nil, eo
end
local function checkMaster(label)
  local eo, raw = master()
  T.check(eo ~= nil, label .. ": the Trick Master is visible")
  T.eq(raw and raw.cellX, 4, label .. ": at x 4")
  T.eq(raw and raw.cellY, 5, label .. ": at y 5")
  T.eq(raw and raw.facing, "right", label .. ": facing east")
end

load(CORRIDOR, 5, 5)
Rse.setVar("VAR_TRICK_HOUSE_LEVEL", 4, session)
Rse.setFlag("FLAG_HIDE_TRICK_HOUSE_END_MAN", true, session)
load(END, 10, 2)
T.eq(Map.current, END, "warped into the end room")
T.check(Rse.flag("FLAG_HIDE_TRICK_HOUSE_END_MAN", session), "his hide flag is still set after a later puzzle")
checkMaster("warp in")
T.eq(Rse.var("VAR_TEMP_2", session), 0, "the exit trigger is armed until he is talked to")

local disk = SaveData.decode(SaveData.encode(Schema.toSaveTable(session)))
T.check(type(disk) == "table" and type(disk.objectEvents) == "table" and disk.objectEvents.mapId == END,
  "the save carries the end room's object events")

load(CORRIDOR, 5, 5)
session.objectEvents = Schema.fromSaveTable(disk).objectEvents
load(END, 10, 2, "continue")
checkMaster("continue")
T.eq(session.objectEvents, nil, "the snapshot is consumed by the Continue")

load(CORRIDOR, 5, 5)
session.objectEvents = nil
load(END, 10, 2, "continue")
checkMaster("legacy continue")

T.finish()
