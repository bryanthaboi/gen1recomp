#!/usr/bin/env luajit
-- pokefirered/src/safari_zone.c:26 EnterSafariMode
-- pokefirered/src/safari_zone.c:41 SafariZoneTakeStep
-- pokefirered/data/scripts/safari_zone.inc:7 SafariZone_EventScript_Exit
-- pokefirered/src/field_control_avatar.c:677 TryStartStepCountScript

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Safari = require("src.core.game3.safari")
local Rules = require("src.core.game3.battle.rules")

print("[test] 1. the constants are pret's")
check(Safari.BALLS == 30, "30 SAFARI BALLS")
check(Safari.STEPS == 600, "600 steps")
check(Safari.BALLS == Rules.safari.BALLS and Safari.STEPS == Rules.safari.STEPS,
  "the overworld and the battle side agree")
check(Safari.FLAG_SYS_SAFARI_MODE == 0x800, "FLAG_SYS_SAFARI_MODE is 0x800")
check(Safari.VAR_ENTRANCE_SCENE == 0x406E,
  "VAR_MAP_SCENE_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE is 0x406E")
check(Safari.EXIT_MAP == "FR_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE"
  and Safari.EXIT_X == 4 and Safari.EXIT_Y == 1,
  "the exit warp is the Fuchsia entrance at (4,1)")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_field_safari_test (cache-backed sections): " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local StepEvents = require("src.core.game3.step_events")
local Warp = require("src.core.game3.warp")
local Runtime = require("src.core.game3.runtime")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = nil, flags = {}, vars = {}, party = {}, name = "RED" }
game.session = session
Runtime.session = session

local function enterMap(mapId)
  local def = game.data.maps[mapId]
  if not def then return nil end
  Field._game = game
  Field._session = session
  session.map = mapId
  Field.running = true
  Field.locked = false
  Space.activate(nil, mapId, game, nil)
  Collision.bindMap(game, mapId, def)
  Objects.loadMap(game, mapId, def)
  return def
end

print("[test] 2. the Safari Zone maps and the entrance warp exist")
local center = enterMap("FR_SAFARI_ZONE_CENTER")
check(center ~= nil, "FR_SAFARI_ZONE_CENTER is in the cache")
local entrance = game.data.maps[Safari.EXIT_MAP]
check(entrance ~= nil, Safari.EXIT_MAP .. " is in the cache")
if not (center and entrance) then finish() end

print("[test] 3. EnterSafariMode arms the session")
check(Safari.isActive(session) == false, "safari mode starts off")
check(Safari.enter(session) == true, "EnterSafariMode")
check(Safari.isActive(session) == true, "FLAG_SYS_SAFARI_MODE is set")
check(Flags.getFlag(Space.store, nil, Safari.FLAG_SYS_SAFARI_MODE) == true,
  "and the script store sees it")
check(Safari.balls(session) == 30, "30 balls on the session")
check(Safari.steps(session) == 600, "600 steps on the session")
check(session.safari.balls == 30, "the battle side reads session.safari.balls")

print("[test] 4. every step burns one of the 600")
session.party = { { species = 1, level = 10, hp = 20, maxHp = 20 } }
for _ = 1, 10 do StepEvents.onStepTaken(session, game) end
check(Safari.steps(session) == 590, "10 steps left 590 (" .. Safari.steps(session) .. ")")

print("[test] 5. a step outside safari mode burns nothing")
Safari.exit(session)
check(Safari.isActive(session) == false, "ExitSafariMode cleared the flag")
check(Safari.balls(session) == 0, "and zeroed the balls")
local before = Safari.steps(session)
StepEvents.onStepTaken(session, game)
check(Safari.steps(session) == before, "SafariZoneTakeStep is a no-op when off")

print("[test] 6. the last step ends the game and ejects to the entrance")
Safari.enter(session)
session.safari.steps = 2
Warp.clear()
StepEvents.onStepTaken(session, game)
check(Safari.steps(session) == 1, "599 of 600 gone, one step left")
check(Safari.isActive(session) == true, "still in the Safari Zone")
StepEvents.onStepTaken(session, game)
check(Safari.steps(session) == 0, "the counter hits zero")
check(Safari.isActive(session) == false, "the PA announcement ran ExitSafariMode")
check(session.vars[Safari.VAR_ENTRANCE_SCENE] == 1,
  "VAR_MAP_SCENE_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE is 1 for the exit cutscene")
check(Flags.getVar(Space.store, nil, Safari.VAR_ENTRANCE_SCENE) == 1,
  "the script store sees the same var")
local pending = Warp._pending
check((pending ~= nil and pending.mapId == Safari.EXIT_MAP and pending.x == 4 and pending.y == 1)
  or session.map == Safari.EXIT_MAP,
  "the player is on the way to the Fuchsia entrance at (4,1)")
Warp.clear()

print("[test] 7. retiring early ejects the same way")
enterMap("FR_SAFARI_ZONE_CENTER")
Safari.enter(session)
check(Safari.retirePrompt(session, game) == true, "the retire prompt ran")
check(Safari.isActive(session) == false, "retiring left safari mode")
check(session.vars[Safari.VAR_ENTRANCE_SCENE] == 1, "and set the entrance scene var")
Warp.clear()

print("[test] 8. out of balls ends it too")
enterMap("FR_SAFARI_ZONE_CENTER")
Safari.enter(session)
session.safari.balls = 0
check(Safari.outOfBalls(session, game) == true, "the out-of-balls announcement ran")
check(Safari.isActive(session) == false, "out of balls leaves safari mode")
Warp.clear()

print("[test] 9. Continue inside the zone does not eject on the first step")
local Schema = require("src.core.game3.save_schema_firered")
enterMap("FR_SAFARI_ZONE_CENTER")
Safari.enter(session)
session.safari.steps = 500
Space.persistSession(nil, game)
local save = Schema.toSaveTable(session)
check(save.safari == nil,
  "gNumSafariBalls / gSafariZoneStepCounter are EWRAM, so no save block carries them")
check(save.flags[tostring(Safari.FLAG_SYS_SAFARI_MODE)] == true,
  "but FLAG_SYS_SAFARI_MODE rides the saved flag store")
local loaded = Schema.fromSaveTable(save)
check(loaded.safari == nil, "the loaded session has no counters")
game.session = loaded
Runtime.session = loaded
Field._session = loaded
Space.deactivate(nil)
Space.activate(nil, "FR_SAFARI_ZONE_CENTER", game, nil)
-- pokefirered/src/overworld.c:1695 CB2_ContinueSavedGame
check(Safari.isActive(loaded) == false, "ResetSafariZoneFlag_ clears the flag on Continue")
check(Flags.getFlag(Space.store, nil, Safari.FLAG_SYS_SAFARI_MODE) == false,
  "and the script store agrees")
loaded.party = { { species = 1, level = 10, hp = 20, maxHp = 20 } }
Warp.clear()
StepEvents.onStepTaken(loaded, game)
check(Warp._pending == nil, "the first step after Continue does not eject the player")
check((loaded.vars[Safari.VAR_ENTRANCE_SCENE] or 0) ~= 1, "and does not run the exit script")
game.session = session
Runtime.session = session
Field._session = session
session.flags[Safari.FLAG_SYS_SAFARI_MODE] = nil
session.safari = nil
Space.deactivate(nil)
Space.activate(nil, "FR_SAFARI_ZONE_CENTER", game, nil)

print("[test] 10. zero balls ejects on return to the field, with no step needed")
enterMap("FR_SAFARI_ZONE_CENTER")
Safari.enter(session)
check(Field.pollSafariBalls(game) == false, "with balls left the field poll does nothing")
session.safari.balls = 0
Warp.clear()
-- pokefirered/src/safari_zone.c:60 CB2_EndSafariBattle
check(Field.pollSafariBalls(game) == true, "at zero balls the poll runs the PA announcement")
check(Safari.isActive(session) == false, "which leaves safari mode")
check(session.vars[Safari.VAR_ENTRANCE_SCENE] == 1, "and sets the entrance scene var")
check(Warp._pending ~= nil and Warp._pending.mapId == Safari.EXIT_MAP,
  "with a warp to the Fuchsia entrance")
Warp.clear()

print("[test] 11. a step at zero balls ejects too, before the step counter")
enterMap("FR_SAFARI_ZONE_CENTER")
Safari.enter(session)
session.safari.balls = 0
Warp.clear()
StepEvents.onStepTaken(session, game)
check(Safari.isActive(session) == false, "walking with an empty bag of balls ends the game")
check(Warp._pending ~= nil and Warp._pending.mapId == Safari.EXIT_MAP, "same eject")
Warp.clear()

print("[test] 12. RETIRE asks before it ejects")
enterMap("FR_SAFARI_ZONE_CENTER")
Safari.enter(session)
Warp.clear()
local asked, answer, closed = nil, false, false
Safari.presenter = {
  message = function(text, onDone) asked = text; onDone() end,
  yesNo = function(onPick) onPick(answer) end,
  close = function() closed = true end,
}
check(Safari.retirePrompt(session, game) == true, "the retire prompt ran")
check(type(asked) == "string" and asked:find("exit the SAFARI", 1, true) ~= nil,
  "it asks SafariZone_Text_WouldYouLikeToExit")
check(Safari.isActive(session) == true, "NO keeps the SAFARI GAME going")
check(closed == true, "and closes the box")
check(Warp._pending == nil, "warping nowhere")
answer = true
check(Safari.retirePrompt(session, game) == true, "asked again")
check(Safari.isActive(session) == false, "YES ends the SAFARI GAME")
check(Warp._pending ~= nil and Warp._pending.mapId == Safari.EXIT_MAP,
  "and warps to the Fuchsia entrance")
Safari.presenter = nil
Warp.clear()

finish()
