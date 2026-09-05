-- pokered engine/overworld/movement.asm:406-414
-- scripts/SSAnneCaptainsRoom.asm:5-10,45-68

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local OW = require("src.world.OverworldController")
local Commands = require("src.script.Commands")
local GameVersion = require("src.core.GameVersion")
local story = require("data.scripts.story")

local player = { cellX = 3, cellY = 5 }
local function newNpc()
  return { facing = "up",
           facePlayer = function(self) self.facing = "down" end }
end

local ow = setmetatable({ player = player }, { __index = OW })
local npc = newNpc()
ow.noNpcFacePlayer = true
ow:makeNpcFacePlayer(npc)
eq(npc.facing, "up", "the no-face flag leaves the NPC's facing alone")

ow.noNpcFacePlayer = nil
ow:makeNpcFacePlayer(npc)
eq(npc.facing, "down", "with the flag clear the NPC turns to the player")

ow.noNpcFacePlayer = true
ow:makeNpcFacePlayer(nil)

local ctx = { overworld = ow }
Commands.no_npc_face_player(ctx, true)
eq(ow.noNpcFacePlayer, true, "no_npc_face_player true sets the flag")
Commands.no_npc_face_player(ctx, false)
eq(ow.noNpcFacePlayer, nil, "no_npc_face_player false clears the flag")
Commands.no_npc_face_player({}, true)

local room = story.SS_ANNE_CAPTAINS_ROOM
check(type(room.onEnter) == "function", "SS_ANNE_CAPTAINS_ROOM has a map script")

local saved = GameVersion.get()
local function entered(version, flags)
  GameVersion.set(version)
  local state = {}
  room.onEnter({ save = { flags = flags } }, state)
  return state.noNpcFacePlayer
end

eq(entered("yellow", {}), true, "yellow sets the bit before HM01")
eq(entered("yellow", { EVENT_RUBBED_CAPTAINS_BACK = true }), true,
   "yellow gates on EVENT_GOT_HM01, not the rub")
eq(entered("yellow", { EVENT_GOT_HM01 = true }), nil, "yellow clears it after HM01")
eq(entered("red", {}), true, "red sets the bit before the rub")
eq(entered("red", { EVENT_RUBBED_CAPTAINS_BACK = true }), nil,
   "red gates on EVENT_RUBBED_CAPTAINS_BACK")
GameVersion.set(saved)

local rows = room.talk.TEXT_SSANNECAPTAINSROOM_CAPTAIN
local rubAt, optsAt, clearAt, rubbedAt, giveAt, rearmAt, gotAt, finalClearAt
for i, row in ipairs(rows) do
  check(row[1] ~= "play_once",
        "no bare play_once row survives -- the jingle rides the box")
  if row[1] == "show_text"
     and row[2] == "_SSAnneCaptainsRoomRubCaptainsBackText" then rubAt = i end
  if row[1] == "text_opts" then optsAt = i end
  if row[1] == "no_npc_face_player" then
    if row[2] == true then rearmAt = i
    elseif clearAt then finalClearAt = i
    else clearAt = i end
  end
  if row[1] == "set_flag" and row[2] == "EVENT_RUBBED_CAPTAINS_BACK" then
    rubbedAt = i
  end
  if row[1] == "set_flag" and row[2] == "EVENT_GOT_HM01" then gotAt = i end
  if row[1] == "give_item" then giveAt = i end
end
check(rubAt, "the rub text is still shown")
eq(optsAt, rubAt - 1, "a text_opts row arms the rub box")
check(rubbedAt and rubbedAt > rubAt, "EVENT_RUBBED_CAPTAINS_BACK is set after the rub")
check(clearAt, "a no_npc_face_player row clears the bit")
eq(rows[clearAt][2], false, "that row clears rather than sets")
eq(clearAt, rubbedAt + 1, "the rub tail clears the bit before the gift (SSAnneCaptainsRoom.asm:64-66)")
check(finalClearAt and gotAt and finalClearAt == gotAt + 1,
      "the success path clears it again after EVENT_GOT_HM01 (:31-33)")
if require("src.core.GameVersion").isYellow() then
  eq(rearmAt, nil, "Yellow never re-arms the bit: a full bag still turns the captain")
else
  eq(rearmAt, giveAt - 1, "Red re-arms the bit right before GiveItem so a full bag halts with him back-turned (pokered :34-37)")
end

local auto = rows[optsAt][2].auto
eq(auto.wait, false, "the rub box never waits for A (bare text terminator)")
eq(auto.delay, 0, "WaitForSoundToFinish has no trailing Delay3")
check(type(auto.sound) == "function", "the rub box starts the jingle itself")

local Music = require("src.core.Music")
local playedSong
local realPlayOnce, realOnePlaying = Music.playOnce, Music.oneShotPlaying
local playing = true
Music.playOnce = function(_, song) playedSong = song; return true end
Music.oneShotPlaying = function() return playing end
local src = auto.sound()
eq(playedSong, "Music_PkmnHealed", "the rub box plays MUSIC_PKMN_HEALED")
check(src and src.isPlaying(src), "the box holds while the jingle plays")
eq(src.getDuration(src), 10, "the source reports a duration past the 180-frame ceiling")
playing = false
eq(src.isPlaying(src), false, "and lets go once the jingle ends")
Music.playOnce = function() return false end
eq(auto.sound(), nil, "a jingle that never started drops the hold")
Music.playOnce, Music.oneShotPlaying = realPlayOnce, realOnePlaying

for i, row in ipairs(rows) do
  if row[1] == "jump" or row[1]:sub(1, 8) == "jump_if_" then
    local target = row[#row]
    check(target == "end" or (type(target) == "number" and target >= 1 and target <= #rows),
          string.format("row %d jumps to a real row (%s)", i, tostring(target)))
  end
end
eq(rows[2][2], #rows, "the already-healed branch jumps to the last row")
eq(rows[#rows - 1][2], "end", "the healed path halts with the reserved end target")
eq(#require("src.script.ScriptRunner").validate(rows), 0, "the captain rows pass validate")

local function setUpvalue(fn, name, value)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then
      debug.setupvalue(fn, i, value)
      return true
    end
    i = i + 1
  end
end

local talkDone
local function talkTo(state, who)
  talkDone = nil
  state:showMapText("TEXT_X", who, function() end)
  return talkDone
end
check(setUpvalue(OW.showMapText, "mapScripts", {
  talkScript = function() return function(_, _, _, onDone) talkDone = onDone end end,
  talkSource = function() end,
}), "showMapText reads the script registry through an upvalue")
local room2 = setmetatable({ player = player, map = { id = 1, def = { label = "X" } } },
                           { __index = OW })

room2.noNpcFacePlayer = true
local captain = newNpc()
local done = talkTo(room2, captain)
eq(captain.facing, "up", "the captain keeps his back turned at talk time")
room2.noNpcFacePlayer = nil
done()
eq(captain.facing, "down", "and turns once the conversation ends with the bit cleared")

room2.noNpcFacePlayer = nil
local other = newNpc()
done = talkTo(room2, other)
eq(other.facing, "down", "an ordinary NPC faces the player at talk time")
other.facing = "left"
done()
eq(other.facing, "left", "and is not re-faced when the conversation ends")

room2.noNpcFacePlayer = true
done = talkTo(room2, nil)
done()

T.finish("ss_anne_captain_face_bug2189")
