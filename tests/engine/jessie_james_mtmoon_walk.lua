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

local facePlayer = indexOf(rows, isRow("face_player_dir"))
check(facePlayer ~= nil and rows[facePlayer][2] == "up",
      "the player turns up to the duo, not right")
local emote = indexOf(rows, isRow("emote", "player"))
check(emote ~= nil, "the player gets the exclamation bubble TEXT12 shows")

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
