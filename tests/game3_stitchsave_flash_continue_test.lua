#!/usr/bin/env luajit
-- pokefirered/src/overworld.c:1691 CB2_ContinueSavedGame

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

require("src.core.GameVersion").set("firered")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchsave_flash_continue_test: " .. tostring(Cache.reason))
  done()
end

local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local FieldView = require("src.core.game3.field_view")
local Schema = require("src.core.game3.save_schema_firered")

local CAVE = "FR_ROCK_TUNNEL_1F"

local game = { data = {} }
Dataset.hydrate(game)
local def = game.data.maps[CAVE]
check(def ~= nil, CAVE .. " is in the cache")
if not def then done() end

local session = Schema.newGame({ rngSeed = 0x2121 })
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })

print("[test] 1. a dark cave loads at the map's own default")
Map.load(nil, game, CAVE, { x = 5, y = 5, facing = "down" })
eq(FieldView.getFlashLevel(), FieldView.MAX_FLASH_LEVEL,
  "walking into Rock Tunnel with no FLASH is gMaxFlashLevel")
eq(session.flashLevel, FieldView.MAX_FLASH_LEVEL, "and the save block carries it")

print("[test] 2. Continue keeps the level the save was made with")
-- pokefirered/src/overworld.c:966 SetFlashLevel
FieldView.setFlashLevel(1)
eq(session.flashLevel, 1, "a script-set level lands on the session")
local loaded = Schema.fromSaveTable(Schema.toSaveTable(session))
Runtime.session = loaded
game.session = loaded
Map.load(nil, game, CAVE, { x = 5, y = 5, facing = "down", enterVia = "continue" })
eq(FieldView.getFlashLevel(), 1,
  "CB2_ContinueSavedGame never calls SetDefaultFlashLevel, so the saved level stands")

print("[test] 3. an ordinary warp into the same cave still takes the default")
Map.load(nil, game, CAVE, { x = 5, y = 5, facing = "down" })
eq(FieldView.getFlashLevel(), FieldView.MAX_FLASH_LEVEL,
  "LoadMapFromWarp runs SetDefaultFlashLevel")

print("[test] 4. an old save with no level continues at the default")
local old = Schema.fromSaveTable({
  schemaVersion = 1, engine = "game3", version = "firered",
  party = {}, dex = { seen = {}, owned = {} },
  map = CAVE, x = 5, y = 5, facing = "down", flags = {}, vars = {},
})
eq(old.flashLevel, nil, "the old save has no level to restore")
Runtime.session = old
game.session = old
Map.load(nil, game, CAVE, { x = 5, y = 5, facing = "down", enterVia = "continue" })
eq(FieldView.getFlashLevel(), FieldView.MAX_FLASH_LEVEL,
  "so FieldView.defaultFlashLevel decides")

done()
