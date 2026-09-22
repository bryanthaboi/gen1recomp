-- The Mt Moon B2F Jessie & James ambush closes in, and vanishes behind a
-- fade (#423).  pokeyellow MtMoonB2FScript_49e15 (scripts/MtMoonB2F.asm:225)
-- shows both objects, prints TEXT_MTMOONB2F_TEXT12, then simulates PAD_UP for
-- one player step; Script6/Script9 MoveSprite Jessie with MovementData_f9e65
-- (six $06) and James with f9e66 (its last five), and both objects carry
-- movement byte 2 = LEFT (data/maps/objects/MtMoonB2F.asm), which
-- .determineDirection (engine/overworld/movement.asm) turns into LEFT steps.
-- Script8/Script11 then face Jessie DOWN and James LEFT, and Script14 wraps
-- the two HideObjects in GBFadeOutToBlack / GBFadeInFromBlack.  The port used
-- to jump from the motto straight to the challenge with the duo still parked
-- at (9,3)/(9,4), and popped them out with no fade.
-- ROM-free: reads data/scripts/ only.
--   luajit tests/engine/jessie_james_mtmoon_walk.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local sites = require("data.scripts.yellow_jessie_james")

-- pokeyellow data/maps/objects/MtMoonB2F.asm: object 2 is JESSIE at (9,3),
-- object 6 is JAMES at (9,4), both STAY LEFT.  The trigger tile is (3,5).
local JESSIE, JAMES = 2, 6
local JESSIE_START = { x = 9, y = 3 }
local JAMES_START = { x = 9, y = 4 }
local TRIGGER = { x = 3, y = 5 }

-- captures the row list a site's onStep hands to the runner
local function rowsFor(site, x, y, flags)
  local captured = nil
  local ow = { runner = { run = function(_, rows) captured = rows end } }
  local game = { save = { flags = flags or {} } }
  local fired = sites[site].onStep(game, ow, x, y)
  return captured, fired
end

local function indexOf(rows, pred, from)
  for i = (from or 1), #rows do
    if pred(rows[i]) then return i end
  end
  return nil
end

local function isRow(name, arg2)
  return function(r)
    return r[1] == name and (arg2 == nil or r[2] == arg2)
  end
end

local function dirsMatch(dirs, count, want)
  if type(dirs) ~= "table" or #dirs ~= count then return false end
  for i = 1, count do
    if dirs[i] ~= want then return false end
  end
  return true
end

-- ---- the ambush arms on the pokeyellow conditions ------------------------

check(type(sites.MT_MOON_B2F.onStep) == "function", "MT_MOON_B2F has an onStep")

local armed = { EVENT_GOT_HELIX_FOSSIL = true }
local rows, fired = rowsFor("MT_MOON_B2F", TRIGGER.x, TRIGGER.y, armed)
check(fired == true, "stepping on (3,5) with a fossil fires the ambush")
check(rows ~= nil, "the ambush handed a script to the runner")
rows = rows or {}

check(select(2, rowsFor("MT_MOON_B2F", TRIGGER.x, TRIGGER.y, {})) == false,
      "no fossil in the bag, no ambush")
check(select(2, rowsFor("MT_MOON_B2F", TRIGGER.x, TRIGGER.y,
        { EVENT_GOT_HELIX_FOSSIL = true,
          EVENT_BEAT_MT_MOON_3_JESSIE_JAMES = true })) == false,
      "a beaten duo does not re-engage")

-- ---- the duo closes in ---------------------------------------------------

local motto = indexOf(rows, isRow("show_text", "_MtMoonJessieJamesText1"))
local challenge = indexOf(rows, isRow("show_text", "_MtMoonJessieJamesText2"))
local battle = indexOf(rows, isRow("start_battle"))
check(motto ~= nil, "the motto plays")
check(challenge ~= nil, "the challenge line plays")
check(battle ~= nil, "the fight starts")

local playerStep = indexOf(rows, function(r)
  return r[1] == "walk_npc" and r[2] == "player"
end)
check(playerStep ~= nil, "the simulated PAD_UP step is walked")
if playerStep then
  check(dirsMatch(rows[playerStep][3], 1, "up"),
        "one step, since wSimulatedJoypadStatesIndex is 1")
  check(motto and playerStep > motto,
        "the step comes after TEXT12, as StartSimulatingJoypadStates does")
end

local jessieWalk = indexOf(rows, isRow("walk_npc", JESSIE))
local jamesWalk = indexOf(rows, isRow("walk_npc", JAMES))
check(jessieWalk ~= nil, "Jessie walks")
check(jamesWalk ~= nil, "James walks")
check(jessieWalk and jamesWalk and jessieWalk < jamesWalk,
      "Script6 moves Jessie before Script9 moves James")

if jessieWalk then
  check(dirsMatch(rows[jessieWalk][3], 6, "left"),
        "Jessie walks the six $06 of MovementData_f9e65, resolved LEFT")
end
if jamesWalk then
  check(dirsMatch(rows[jamesWalk][3], 5, "left"),
        "James walks the five $06 of MovementData_f9e66, resolved LEFT")
end

-- where those step counts land them, against the object coordinates
if jessieWalk and jamesWalk and playerStep then
  local playerX, playerY = TRIGGER.x, TRIGGER.y - 1
  local jx = JESSIE_START.x - #rows[jessieWalk][3]
  local jmx = JAMES_START.x - #rows[jamesWalk][3]
  eq(jx, playerX, "Jessie ends in the player's column")
  eq(JESSIE_START.y, playerY - 1, "Jessie ends one cell above the player")
  eq(jmx, playerX + 1, "James ends one cell east of the player")
  eq(JAMES_START.y, playerY, "James ends level with the player")
end

local faceJessie = indexOf(rows, isRow("face_object", JESSIE), jessieWalk)
local faceJames = indexOf(rows, isRow("face_object", JAMES), jamesWalk)
check(faceJessie ~= nil and rows[faceJessie][3] == "down",
      "Script8 leaves Jessie facing DOWN at the player")
check(faceJames ~= nil and rows[faceJames][3] == "left",
      "Script11 leaves James facing LEFT at the player")

-- scripts/MtMoonB2F.asm:446
local function rowsWithPlayer(site, x, y, flags, player)
  local captured = nil
  local ow = { player = player,
               runner = { run = function(_, r) captured = r end } }
  sites[site].onStep({ save = { flags = flags or {} } }, ow, x, y)
  return captured, ow
end

local SITES = {
  { site = "MT_MOON_B2F", x = 3, y = 5, flags = armed,
    motto = "_MtMoonJessieJamesText1", parting = "_MtMoonJessieJamesText4",
    challenge = "_MtMoonJessieJamesText2", face = "up", duo = { 2, 6 } },
  { site = "ROCKET_HIDEOUT_B4F", x = 24, y = 14, flags = {},
    motto = "_RocketHideoutJessieJamesText1",
    parting = "_RocketHideoutJessieJamesText4",
    challenge = "_RocketHideoutJessieJamesText2", face = "up", duo = { 2, 3 } },
  { site = "POKEMON_TOWER_7F", x = 10, y = 12, flags = {},
    motto = "_PokemonTowerJessieJamesText1",
    parting = "_PokemonTowerJessieJamesText4",
    challenge = "_PokemonTowerJessieJamesText2", face = "up", duo = { 1, 2 } },
  { site = "SILPH_CO_11F", x = 3, y = 3,
    flags = { EVENT_BEAT_SILPH_CO_GIOVANNI = true },
    motto = "_SilphCoJessieJamesText1", parting = "_SilphCoJessieJamesText4",
    challenge = "_SilphCoJessieJamesText2", face = "down", duo = { 4, 6 } },
}

for _, s in ipairs(SITES) do
  local player = { facing = "right" }
  local sr, sow = rowsWithPlayer(s.site, s.x, s.y, s.flags, player)
  sr = sr or {}
  local m = indexOf(sr, isRow("show_text", s.motto))
  check(m ~= nil, s.site .. " plays the motto")
  m = m or 1
  local armedRow = sr[m - 1]
  local auto = armedRow and armedRow[1] == "text_opts"
               and type(armedRow[2]) == "table" and armedRow[2].auto
  check(type(auto) == "table", s.site .. " motto box is armed no-wait")
  auto = type(auto) == "table" and auto or {}
  eq(auto.delay, 91, s.site .. " motto box closes 10+60+1+20 frames after typing")
  check(not auto.wait, s.site .. " motto box never waits for A/B")
  check(type(auto.tick) == "function", s.site .. " motto box drives the bubble")

  local firstWalk = indexOf(sr, isRow("walk_npc")) or #sr
  check(indexOf(sr, isRow("face_player_dir")) == nil
        or indexOf(sr, isRow("face_player_dir")) > firstWalk,
        s.site .. " has no separate turn row after the box closes")
  check(indexOf(sr, isRow("emote")) == nil,
        s.site .. " has no separate bubble row after the box closes")

  if type(auto.tick) == "function" then
    local early, during, late = true, true, true
    for t = 1, 91 do
      auto.tick()
      if t <= 10 and sow.emote ~= nil then early = false end
      if t >= 11 and t <= 70 then
        if not (sow.emote and sow.emote.npc == player)
           or player.facing ~= "right" then during = false end
      end
      if t >= 71 and (sow.emote ~= nil or player.facing ~= s.face) then
        late = false
      end
    end
    check(early, s.site .. " DelayFrames 10 before the bubble")
    check(during, s.site .. " bubble over the player for 60 frames, old facing kept")
    check(late, s.site .. " bubble gone, player turned " .. s.face .. " with the box still up")
  end

  local ch = indexOf(sr, isRow("show_text", s.challenge)) or #sr
  local fastOk, faceOk, walks, faces = true, true, 0, 0
  for i = 1, ch do
    local r = sr[i]
    if r[1] == "walk_npc" and r[2] ~= "player" then
      walks = walks + 1
      if not (type(r[4]) == "table" and r[4].stepFrames == 16) then
        fastOk = false
      end
    elseif r[1] == "walk_npc" and r[2] == "player" then
      if type(r[4]) == "table" and r[4].stepFrames then fastOk = false end
    elseif r[1] == "face_object" and i > firstWalk then
      faces = faces + 1
      if not (type(r[4]) == "table" and (r[4].hold or 0) >= 256) then
        faceOk = false
      end
    end
  end
  eq(walks, 2, s.site .. " walks both of the duo")
  check(fastOk, s.site .. " duo walks at the player's 16-frame step")
  eq(faces, 2, s.site .. " faces both of the duo after their walks")
  check(faceOk, s.site .. " post-walk facings hold past the STAY turn timer")

  local p = indexOf(sr, isRow("show_text", s.parting))
  check(p ~= nil, s.site .. " plays the parting line")
  p = p or 1
  local pArm = sr[p - 1]
  local pAuto = pArm and pArm[1] == "text_opts" and type(pArm[2]) == "table"
                and pArm[2].auto
  check(type(pAuto) == "table" and pAuto.delay == 64 and not pAuto.wait,
        s.site .. " parting box closes itself after DelayFrames 64")
  local downs = 0
  for i = math.max(1, p - 4), p - 1 do
    local r = sr[i]
    if r and r[1] == "face_object" and r[3] == "down"
       and (r[2] == s.duo[1] or r[2] == s.duo[2]) then
      downs = downs + 1
    end
  end
  eq(downs, 2, s.site .. " both of the duo face down before the parting line")
end

do
  local Commands = require("src.script.Commands")
  local NPC = require("src.world.NPC")
  local npc = setmetatable({ facing = "left", pinnedFacing = "left",
                             wanders = true, timer = 5, moving = false,
                             cellX = 9, cellY = 3, px = 144, py = 48 }, NPC)
  local player = { stepFrames = 16, cellX = 3, cellY = 5 }
  local frames, stepDuring, playerDuring = 0, {}, {}
  local ow = { player = player }
  function ow.npcByIndex(_, i) if i == 2 then return npc end end
  function ow.scriptMove(_, e, dir, _, onDone)
    if e == player then
      playerDuring[#playerDuring + 1] = e.stepFrames
      onDone()
      return
    end
    stepDuring[#stepDuring + 1] = e.stepFrames
    e.facing = dir
    e.targetX, e.targetY = e.cellX - 1, e.cellY
    e.moving, e.progress = true, 0
    while e.moving do
      e:update(nil, {})
      frames = frames + 1
    end
    onDone()
  end
  local ctx = { overworld = ow, runner = {} }
  Commands.walk_npc(ctx, 2, { "left", "left", "left", "left", "left", "left" },
                    { stepFrames = 16 })
  eq(frames, 96, "six fast steps take 96 frames, not 192")
  eq(stepDuring[1], 16, "walk_npc stepFrames applies during the walk")
  eq(npc.stepFrames, nil, "walk_npc restores the NPC step length after")
  Commands.walk_npc(ctx, "player", { "up" }, { stepFrames = 8 })
  eq(playerDuring[1], 16, "walk_npc stepFrames never touches the player")

  frames = 0
  Commands.walk_npc(ctx, 2, { "left" })
  eq(frames, 32, "walk_npc with no opts keeps the 32-frame NPC step")

  npc.timer = 5
  Commands.face_object(ctx, 2, "down", { hold = 510 })
  eq(npc.timer, 510, "face_object hold arms the turn timer")
  local held = true
  for _ = 1, 200 do
    npc:update(nil, {})
    if npc.facing ~= "down" then held = false end
  end
  check(held, "a held facing survives 200 frames of the STAY pinned-facing timer")

  npc.timer = 5
  Commands.face_object(ctx, 2, "down")
  eq(npc.timer, 5, "face_object without hold leaves the timer alone")
end

if challenge and jamesWalk and faceJames then
  check(faceJames < challenge and challenge < (battle or math.huge),
        "both walks finish before TEXT13, which precedes the fight")
end

-- ---- and leaves behind a fade -------------------------------------------

-- Script14: GBFadeOutToBlack, HideObject JESSIE, HideObject JAMES,
-- UpdateSprites, Delay3, GBFadeInFromBlack.  Checked at all four sites: the
-- other three already faded, so they are the regression half.
local function checkFadedExit(site, label, x, y, flags)
  local siteRows = rowsFor(site, x, y, flags)
  check(siteRows ~= nil, label .. " handed a script to the runner")
  if not siteRows then return end
  local fadeOut = indexOf(siteRows, function(r)
    return r[1] == "fade" and r[2] == "out"
  end)
  check(fadeOut ~= nil, label .. " fades out before the duo vanishes")
  if not fadeOut then return end
  local firstHide = indexOf(siteRows, isRow("hide_object"))
  check(firstHide ~= nil and firstHide > fadeOut,
        label .. " hides nobody while the screen is still lit")
  local secondHide = indexOf(siteRows, isRow("hide_object"), (firstHide or 0) + 1)
  check(secondHide ~= nil and secondHide == (firstHide or 0) + 1,
        label .. " hides both of them inside the same fade")
  local fadeIn = indexOf(siteRows, function(r)
    return r[1] == "fade" and r[2] == "in"
  end, (secondHide or 0) + 1)
  check(fadeIn ~= nil, label .. " fades back in with the duo gone")
  local music = indexOf(siteRows, isRow("play_default_music"))
  check(music ~= nil and fadeIn and music > fadeIn,
        label .. " resumes the map theme after the fade, as PlayDefaultMusic does")
end

checkFadedExit("MT_MOON_B2F", "Mt Moon B2F", TRIGGER.x, TRIGGER.y, armed)
checkFadedExit("ROCKET_HIDEOUT_B4F", "Rocket Hideout B4F", 24, 14, {})
checkFadedExit("POKEMON_TOWER_7F", "Pokemon Tower 7F", 10, 12, {})
checkFadedExit("SILPH_CO_11F", "Silph Co 11F", 3, 3,
  { EVENT_BEAT_SILPH_CO_GIOVANNI = true })

-- every site walks the duo in rather than fighting them from across the room
for _, site in ipairs({ "MT_MOON_B2F", "ROCKET_HIDEOUT_B4F",
                        "POKEMON_TOWER_7F", "SILPH_CO_11F" }) do
  local siteRows = ({
    MT_MOON_B2F = function() return rowsFor(site, TRIGGER.x, TRIGGER.y, armed) end,
    ROCKET_HIDEOUT_B4F = function() return rowsFor(site, 25, 14, {}) end,
    POKEMON_TOWER_7F = function() return rowsFor(site, 11, 12, {}) end,
    SILPH_CO_11F = function()
      return rowsFor(site, 2, 3, { EVENT_BEAT_SILPH_CO_GIOVANNI = true })
    end,
  })[site]()
  local walk = siteRows and indexOf(siteRows, isRow("walk_npc"))
  local start = siteRows and indexOf(siteRows, isRow("start_battle"))
  check(walk ~= nil and start ~= nil and walk < start,
        site .. " walks somebody before the battle begins")
end

T.finish("jessie james mt moon walk")
