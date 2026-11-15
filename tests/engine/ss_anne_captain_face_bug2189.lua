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
eq(rearmAt, nil, "no row re-arms the bit ahead of GiveItem on the success path")
eq(rows[giveAt][5], "_SSAnneCaptainsRoomCaptainHM01NoRoomText",
   "a full bag prints the captain's own no-room text")
if require("src.core.GameVersion").isYellow() then
  eq(rows[giveAt][7], nil, "Yellow never re-arms the bit on a full bag")
else
  eq(rows[giveAt][7], true, "Red re-arms the bit only once GiveItem refuses (pokered :34-37)")
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

local boxes = {}
check(setUpvalue(Commands.show_text, "TextBox", {
  new = function(_, text) return { text = text } end,
}), "show_text builds its box through an upvalue")
local function textCtx(state)
  return {
    overworld = state,
    game = { data = { text = { rub = "rub", better = "better", received = "received",
                               noroom = "noroom" },
                      resolveText = function() return nil end },
             stack = { push = function(_, b) table.insert(boxes, b) end } },
    runner = { yield = function() end, resume = function() end },
  }
end

room2.noNpcFacePlayer = true
local captain = newNpc()
local done = talkTo(room2, captain)
eq(captain.facing, "up", "the captain keeps his back turned at talk time")
local tctx = textCtx(room2)
Commands.show_text(tctx, "rub")
eq(captain.facing, "up", "the rub box opens with the bit still set: back stays turned")
Commands.no_npc_face_player(tctx, false)
eq(captain.facing, "up", "clearing the bit alone does not turn him")
Commands.show_text(tctx, "better")
eq(captain.facing, "down", "the next text box turns him (PrintText -> UpdateSprites)")
captain.facing = "up"
Commands.show_text(tctx, "received")
eq(captain.facing, "up", "the latched turn fires once, not on every later box")
done()
eq(captain.facing, "up", "and the end of the talk does not turn him again")

room2.noNpcFacePlayer = true
captain = newNpc()
done = talkTo(room2, captain)
Commands.show_text(textCtx(room2), "rub")
done()
eq(captain.facing, "up", "a talk that ends with the bit still set never turns him")

room2.noNpcFacePlayer = true
captain = newNpc()
done = talkTo(room2, captain)
room2.noNpcFacePlayer = nil
done()
eq(captain.facing, "down", "a function script that clears the bit still turns him at the end")

local realBag = package.loaded["src.inventory.Bag"]
package.loaded["src.inventory.Bag"] = { add = function() return false end }
room2.noNpcFacePlayer = nil
local fctx = textCtx(room2)
fctx.save = {}
eq(Commands.give_item(fctx, "HM_CUT", 1, false, "noroom", "Get_Key_Item", true),
   math.huge, "a refused gift halts the script")
eq(room2.noNpcFacePlayer, true, "and fullNoFace re-arms the bit after the no-room text")
room2.noNpcFacePlayer = nil
Commands.give_item(fctx, "HM_CUT", 1, false, "noroom", "Get_Key_Item")
eq(room2.noNpcFacePlayer, nil, "without fullNoFace a full bag leaves the bit clear")
package.loaded["src.inventory.Bag"] = realBag

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
