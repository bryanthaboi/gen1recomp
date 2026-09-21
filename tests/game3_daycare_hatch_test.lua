#!/usr/bin/env luajit
-- pokefirered/src/daycare.c:1749

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local songs, ses, fanfares, cries = {}, {}, {}, {}
package.loaded["src.core.game3.audio"] = setmetatable({
  _mapSong = 101,
  playSong = function(id) songs[#songs + 1] = id end,
  playSe = function(id) ses[#ses + 1] = id end,
  playFanfare = function(id) fanfares[#fanfares + 1] = id end,
  playCry = function(id) cries[#cries + 1] = id end,
  isCryFinished = function() return true end,
  isFanfareFinished = function() return true end,
}, { __index = function() return function() end end })

local hudMessages = {}
package.loaded["src.ui.game3.hud"] = {
  openMessage = function(_game, text, opts)
    hudMessages[#hudMessages + 1] = text
    if opts and opts.done then opts.done() end
  end,
}

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = "FR_FOUR_ISLAND_POKEMON_DAY_CARE", party = {},
  name = "RED", trainerId = 4242, vars = {}, flags = {},
  dex = { seen = {}, owned = {} },
}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Daycare = require("src.core.game3.daycare")
local StepEvents = require("src.core.game3.step_events")
local EggHatch = require("src.ui.game3.egg_hatch")
local Stack = require("src.ui.game3.stack")
local Message = require("src.ui.game3.message")
local Choice = require("src.ui.game3.choice")

print("[test] 1. the hatch scene is its own scene, not the evolution scene")
-- pokefirered/src/daycare.c:1749 EggHatch is a CB2 of its own
check(type(EggHatch.start) == "function", "src/ui/game3/egg_hatch.lua exposes start")
local stepSource = assert(io.open("src/core/game3/step_events.lua")):read("*a")
check(stepSource:find("src.ui.game3.egg_hatch", 1, true) ~= nil,
  "the hatch leg of step_events opens the egg-hatch scene")
check(stepSource:find("evolution_scene", 1, true) == nil,
  "and no longer routes a hatching EGG into the evolution scene")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("meta.json")
if not cacheRoot then
  print("[skip] game3_daycare_hatch_test needs species data: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Party = require("src.core.game3.party")
local Breeding = require("src.core.game3.breeding")

local MAGIKARP = 129

print("[test] 2. an egg in the party hatches out of the daycare step counter")
local scratch = { party = {}, name = "RED", trainerId = 4242, map = session.map }
local ok, _, egg = Party.giveMon(scratch, MAGIKARP, 5, "EGG")
check(ok, "built a MAGIKARP")
Breeding.applyEggData(egg, true)
egg.nickname = "EGG"
-- pokefirered/src/daycare.c:1106 METLOC_SPECIAL_EGG
eq(egg.metLocation, 253, "CreateEgg's hot springs met location")
local cycles = tonumber(Pokemon.speciesMeta(MAGIKARP).eggCycles)
eq(egg.friendship, cycles, "the hatch counter is the species' eggCycles")
session.party = { egg }
session.dex = { seen = {}, owned = {} }
StepEvents.flush()

local dc = Daycare.stateOf(session)
dc.stepCounter = 0
local steps, hatchEvent = 0, nil
while steps < 256 * (cycles + 3) and not hatchEvent do
  StepEvents.onStepTaken(session, nil)
  steps = steps + 1
  for _, event in ipairs(StepEvents._queue) do
    if event.type == "egg_hatch" then hatchEvent = event end
  end
end
check(hatchEvent ~= nil, "the egg queued its hatch event")
-- pokefirered/src/daycare.c:1157
eq(steps, 255 + cycles * 256, "on the cart's 255 + eggCycles * 256th step")
check(not session.dex.seen[MAGIKARP], "and the egg was still unknown to the POKeDEX")
-- pokefirered/src/field_control_avatar.c:672 GAME_STAT_HATCHED_EGGS
eq(session.gameStats and session.gameStats[13], 1, "the hatched-eggs game stat went up")

print("[test] 3. the scene shows Huh? then the hatch line, not an evolution")
local doneResult = nil
hatchEvent.run(function(result) doneResult = result end)
-- pokefirered/data/scripts/day_care.inc:112 DayCare_Text_Huh
eq(hudMessages[1], "Huh?", "the field script prints DayCare_Text_Huh first")
check(EggHatch.isOpen(), "the egg-hatch scene is on the stack")
check(Stack.has("egg_hatch"), "as its own stack layer")
check(not Stack.has("evolution_scene"), "and no evolution scene was pushed")
eq(egg.isEgg, false, "AddHatchedMonToParty ran at scene setup")
check(session.dex.seen[MAGIKARP], "which is where the POKeDEX flags are set")

local guard = 0
local framesSeen, maxShards = {}, 0
while EggHatch._state ~= "hatched_msg" and guard < 600 do
  EggHatch.update(1 / 60)
  local f = EggHatch._eggFrame or 0
  if framesSeen[#framesSeen] ~= f then framesSeen[#framesSeen + 1] = f end
  maxShards = math.max(maxShards, #(EggHatch._shards or {}))
  guard = guard + 1
end
eq(EggHatch._state, "hatched_msg", "the shake sequence reached the hatch message")
-- pokefirered/src/daycare.c:2009 StartSpriteAnim 1, then 2, then 2 again
eq(table.concat(framesSeen, ","), "0,1,2", "the egg walked sEggHatchTiles frames 0, 1, 2")
-- pokefirered/src/daycare.c:2128 CreateRandomEggShardSprite
check(maxShards >= 16, "the shards flew, most of them at the flash, got " .. tostring(maxShards))
-- pokefirered/src/daycare.c:2091 PlaySE(SE_EGG_HATCH)
check(ses[#ses] == 106, "SE_EGG_HATCH closed the crack sequence, got " .. tostring(ses[#ses]))
check(Message.isOpen(), "the message box is open")
local page = Message.currentPage() or ""
check(tostring(page):find("hatched from the EGG", 1, true) ~= nil,
  "gText_HatchedFromEgg is on screen, got " .. tostring(page))
-- pokefirered/src/daycare.c:1929 PlayFanfare(MUS_EVOLVED)
eq(fanfares[1], 259, "MUS_EVOLVED played")
eq(cries[1], MAGIKARP, "the hatchling cried")
-- pokefirered/src/daycare.c:2008 PlaySE(SE_BALL)
check(#ses >= 4, "the egg cracked on all four PlaySE(SE_BALL) beats, got " .. tostring(#ses))

print("[test] 4. the nickname prompt, and No returns to the field")
guard = 0
while EggHatch._state ~= "nickname_ask" and guard < 600 do
  EggHatch.update(1 / 60)
  guard = guard + 1
end
eq(EggHatch._state, "nickname_ask", "the scene asked about a nickname")
page = Message.currentPage() or ""
check(tostring(page):find("nickname the newly", 1, true) ~= nil,
  "gText_NickHatchPrompt is on screen, got " .. tostring(page))
check(Choice.active, "the yes/no menu is up")
eq(Choice.left, 21, "at sYesNoWinTemplate's tilemapLeft")
eq(Choice.top, 9, "and tilemapTop")
Choice.cancel()
guard = 0
while EggHatch.isOpen() and guard < 600 do
  EggHatch.update(1 / 60)
  guard = guard + 1
end
check(not EggHatch.isOpen(), "the scene closed")
-- pokefirered/src/daycare.c:2125 DestroySprite past y2 > 20
check(#(EggHatch._shards or {}) == 0, "every shard fell past its 20px floor")
check(not Stack.has("egg_hatch"), "and left the stack")
eq(doneResult, "hatched", "the step event was released")
eq(songs[#songs], 101, "the map song came back")
eq(egg.nickname, "", "declining the prompt leaves the species name")

finish()
