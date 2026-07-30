-- Parity: Team Rocket leaves Silph Co, and the president keeps talking (#392).
--
-- Oracle: scripts/SilphCo11F.asm SilphCo11FTeamRocketLeavesScript walks
-- .HideToggleableObjectIDs (TOGGLE_SILPH_CO_2F_2..11F_3 plus the Saffron
-- street set, which M.SAFFRON_CITY handles) through predef HideObject just
-- before SetEvent EVENT_BEAT_SILPH_CO_GIOVANNI.  The ordinals come from
-- constants/toggle_constants.asm and name the objects listed per floor in
-- data/maps/toggleable_objects.asm, so the item balls, the rescued 2F/10F
-- workers and the 7F rival keep their sprites.  HideObject writes
-- wMissableObjectFlags, which the port keeps in save.objectToggles.
--
-- Oracle: scripts/SilphCo11F.asm SilphCo11FSilphPresidentText branches on
-- EVENT_GOT_MASTER_BALL alone -- nz jumps to .got_item, which prints
-- _SilphCo11FSilphPresidentMasterBallDescriptionText -- so every later talk
-- prints something.
--
-- Self-contained: `luajit tests/parity_silph_rockets.lua`; also globbed by
-- tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity silph rockets")
local check, eq = S.check, S.eq

local MapScripts = require("src.script.MapScripts")
require("data.scripts.init")
local Commands = require("src.script.Commands")
local ScriptRunner = require("src.script.ScriptRunner")
local OverworldState = require("src.world.OverworldController")

-- .HideToggleableObjectIDs, floor by floor, in the order the asm lists them
local HIDDEN = {
  { "SILPH_CO_2F", { "SILPHCO2F_SCIENTIST1", "SILPHCO2F_SCIENTIST2",
                     "SILPHCO2F_ROCKET1", "SILPHCO2F_ROCKET2" } },
  { "SILPH_CO_3F", { "SILPHCO3F_ROCKET", "SILPHCO3F_SCIENTIST" } },
  { "SILPH_CO_4F", { "SILPHCO4F_ROCKET1", "SILPHCO4F_SCIENTIST",
                     "SILPHCO4F_ROCKET2" } },
  { "SILPH_CO_5F", { "SILPHCO5F_ROCKET1", "SILPHCO5F_SCIENTIST",
                     "SILPHCO5F_ROCKER", "SILPHCO5F_ROCKET2" } },
  { "SILPH_CO_6F", { "SILPHCO6F_ROCKET1", "SILPHCO6F_SCIENTIST",
                     "SILPHCO6F_ROCKET2" } },
  { "SILPH_CO_7F", { "SILPHCO7F_ROCKET1", "SILPHCO7F_SCIENTIST",
                     "SILPHCO7F_ROCKET2", "SILPHCO7F_ROCKET3" } },
  { "SILPH_CO_8F", { "SILPHCO8F_ROCKET1", "SILPHCO8F_SCIENTIST",
                     "SILPHCO8F_ROCKET2" } },
  { "SILPH_CO_9F", { "SILPHCO9F_ROCKET1", "SILPHCO9F_SCIENTIST",
                     "SILPHCO9F_ROCKET2" } },
  { "SILPH_CO_10F", { "SILPHCO10F_ROCKET", "SILPHCO10F_SCIENTIST" } },
  { "SILPH_CO_11F", { "SILPHCO11F_GIOVANNI", "SILPHCO11F_ROCKET1",
                      "SILPHCO11F_ROCKET2" } },
}

-- toggleable objects the hide list deliberately skips
local KEPT = {
  { "SILPH_CO_2F", "SILPHCO2F_SILPH_WORKER_F" },
  { "SILPH_CO_3F", "SILPHCO3F_HYPER_POTION" },
  { "SILPH_CO_5F", "SILPHCO5F_CARD_KEY" },
  { "SILPH_CO_7F", "SILPHCO7F_RIVAL" },
  { "SILPH_CO_7F", "SILPHCO7F_TM_SWORDS_DANCE" },
  { "SILPH_CO_10F", "SILPHCO10F_SILPH_WORKER_F" },
  { "SILPH_CO_11F", "SILPHCO11F_BEAUTY" },
}

local function objOf(mapId, name)
  for _, o in ipairs(Data.maps[mapId].objects) do
    if o.name == name then return o end
  end
end

local function newSave(beat)
  return {
    flags = beat and { EVENT_BEAT_SILPH_CO_GIOVANNI = true } or {},
    inventory = {}, objectToggles = {}, itemsTaken = {},
    defeatedTrainers = {},
  }
end

-- every name in both lists has to be a real object_event, or the toggle
-- write lands on a key nothing reads
for _, floor in ipairs(HIDDEN) do
  for _, name in ipairs(floor[2]) do
    check(objOf(floor[1], name) ~= nil,
          name .. " is an object_event on " .. floor[1])
  end
end
for _, kept in ipairs(KEPT) do
  check(objOf(kept[1], kept[2]) ~= nil,
        kept[2] .. " is an object_event on " .. kept[1])
end

-- ---------------------------------------------------------------- hide pass
-- 11F's onEnter is the whole pass: it runs on the post-battle callback's
-- floor and repairs saves that beat Giovanni before the list existed
local function enter(mapId, save)
  local view = MapScripts.get(mapId)
  check(view and type(view.onEnter) == "function",
        mapId .. " has an onEnter hook")
  if view and view.onEnter then view.onEnter({ save = save }, nil) end
end

do
  local save = newSave(true)
  enter("SILPH_CO_11F", save)
  local hidden = 0
  for _, floor in ipairs(HIDDEN) do
    for _, name in ipairs(floor[2]) do
      eq(save.objectToggles[floor[1]] and save.objectToggles[floor[1]][name],
         false, name .. " hidden by the 11F pass")
      check(not OverworldState.objectVisible(save, floor[1],
                                            objOf(floor[1], name)),
            name .. " no longer spawns")
      hidden = hidden + 1
    end
  end
  eq(hidden, 31, "the asm hides 31 Silph objects on 2F-11F")

  for _, kept in ipairs(KEPT) do
    eq(save.objectToggles[kept[1]] and save.objectToggles[kept[1]][kept[2]],
       nil, kept[2] .. " is not in .HideToggleableObjectIDs")
    check(OverworldState.objectVisible(save, kept[1], objOf(kept[1], kept[2])),
          kept[2] .. " still spawns")
  end
end

-- each floor repairs itself on entry and touches no other floor, so a save
-- that walks back in one elevator ride at a time still clears
for _, floor in ipairs(HIDDEN) do
  local save = newSave(true)
  enter(floor[1], save)
  for _, name in ipairs(floor[2]) do
    eq(save.objectToggles[floor[1]][name], false,
       name .. " hidden on entering " .. floor[1])
  end
  if floor[1] ~= "SILPH_CO_11F" then
    local others = 0
    for mapId in pairs(save.objectToggles) do
      if mapId ~= floor[1] then others = others + 1 end
    end
    eq(others, 0, floor[1] .. " onEnter writes only its own floor")
  end
end

-- before the win nothing is hidden: the grunts are still battleable
for _, floor in ipairs(HIDDEN) do
  local save = newSave(false)
  enter(floor[1], save)
  eq(next(save.objectToggles), nil,
     floor[1] .. " hides nothing while the event is unset")
  for _, name in ipairs(floor[2]) do
    check(OverworldState.objectVisible(save, floor[1], objOf(floor[1], name)),
          name .. " still spawns before Giovanni falls")
  end
end

-- ---------------------------------------------------------------- president
local rows = MapScripts.get("SILPH_CO_11F").talk.TEXT_SILPHCO11F_SILPH_PRESIDENT
check(type(rows) == "table", "the president has a hand-ported talk script")

-- the shipped bug: the last row jumped past the end of the script, which
-- validate reports and every branch walked into
local problems = ScriptRunner.validate(rows)
eq(#problems, 0, "president script validates: " .. table.concat(problems, "; "))

for _, row in ipairs(rows) do
  check(row[2] ~= "EVENT_BEAT_SILPH_CO_GIOVANNI",
        "no Giovanni gate: the teleport pads reach him without the trigger")
end

for _, key in ipairs({ "_SilphCo11FSilphPresidentText",
                       "_SilphCo11FSilphPresidentReceivedMasterBallText",
                       "_SilphCo11FSilphPresidentMasterBallDescriptionText" }) do
  local body = Data.text[key]
  check(type(body) == "string" and body ~= "", key .. " is extracted")
end

-- run the rows through the real interpreter with only the leaf commands
-- stubbed, so the branch arithmetic is what is under test
local shown, given
Commands.face_player = function() end
Commands.show_text = function(_, key) shown[#shown + 1] = key end
Commands.give_item = function(_, item, count) given = { item, count } end

local function talk(save)
  shown, given = {}, nil
  local runner = ScriptRunner.new({ data = Data, save = save }, nil)
  runner:exec(rows, runner:makeContext({}))
  return shown, given
end

do
  local save = newSave(true)
  local first = talk(save)
  eq(first[1], "_SilphCo11FSilphPresidentText", "first talk thanks the player")
  eq(given and given[1], "MASTER_BALL", "first talk hands over a MASTER BALL")
  eq(given and given[2], 1, "one ball, as in lb bc, MASTER_BALL, 1")
  eq(first[2], "_SilphCo11FSilphPresidentReceivedMasterBallText",
     "the got-item line prints after the give (sound_get_key_item rides it)")
  eq(#first, 2, "the description is not printed on the same talk")
  eq(save.flags.EVENT_GOT_MASTER_BALL, true, "SetEvent EVENT_GOT_MASTER_BALL")

  local second, secondGive = talk(save)
  eq(second[1], "_SilphCo11FSilphPresidentMasterBallDescriptionText",
     "second talk describes the ball instead of going silent")
  eq(#second, 1, "and prints nothing else")
  eq(secondGive, nil, "a second ball is not handed out")
end

-- the ball does not depend on Giovanni's coordinate trigger having fired
do
  local fresh = talk(newSave(false))
  eq(fresh[1], "_SilphCo11FSilphPresidentText",
     "an unbeaten-Giovanni save still gets the thank-you and the ball")
end

S.finish()
