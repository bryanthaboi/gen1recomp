-- Parity: Route 22 + Cerulean rival post-battle exits (#154 / #168).
--
-- pokered Route22Rival{1,2}ExitMovementData* and CeruleanCityMovement3/4
-- plus CeruleanCityRivalText's Bill line after EVENT_BEAT_CERULEAN_RIVAL.
--
--   luajit tests/parity_rival_walkoff.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity rival walkoff")
local check, eq = S.check, S.eq

-- restored at the bottom for the suites run after this file
local realMusic = package.loaded["src.core.Music"]
local realCommands = package.loaded["src.script.Commands"]
local realPicBox = package.loaded["src.ui.PicBox"]
package.loaded["src.core.Music"] = {
  play = function() end, playOnce = function() return true end, stop = function() end,
}
package.loaded["src.script.Commands"] = {
  hide_object = function() end,
}
package.loaded["src.ui.PicBox"] = { new = function() return {} end }

local story5 = dofile("data/scripts/story5.lua")
local story = dofile("data/scripts/story.lua")

local function dirsEqual(a, b)
  if type(a) ~= "table" or #a ~= #b then return false end
  for i = 1, #b do if a[i] ~= b[i] then return false end end
  return true
end

local function findWalk(rows)
  for _, r in ipairs(rows) do
    if r[1] == "walk_npc" then return r end
  end
end

local function lastWalk(rows)
  local found
  for _, r in ipairs(rows) do
    if r[1] == "walk_npc" then found = r end
  end
  return found
end

local function findRow(rows, name)
  for i, r in ipairs(rows) do
    if r[1] == name then return r, i end
  end
end

local function texts(rows)
  local out = {}
  for _, r in ipairs(rows) do
    if r[1] == "show_text" then out[#out + 1] = r[2] end
  end
  return out
end

local function capture(mapMod, game, x, y)
  local rows
  local ow = {
    runner = {
      isRunning = function() return false end,
      run = function(_, r) rows = r end,
    },
    player = { facing = "down" },
    npcByIndex = function() return { def = { name = "X" } } end,
  }
  check(mapMod.onStep(game, ow, x, y),
        ("onStep fires at (%d,%d)"):format(x, y))
  check(rows ~= nil, "onStep queued rows")
  return rows
end

-- Route22Rival1ExitMovementData1 / Data2, keyed on wSavedCoordIndex (which
-- Route22RivalBattleCoords entry matched, counted from 1) and NOT on the
-- rival's own row: index 1 is the (29,4) tile, where he stops BELOW the
-- player on (29,5) and leaves east; index 2 is the (29,5) tile, where he
-- stops LEFT of him on (28,5) and must step UP to row 4 to get around him.
-- This mapping was backwards until #236 (the y=4 walk began UP into the
-- cliff cell (28,3)), so these constants flipped with the fix.
local R1_Y4 = { "right", "right", "down", "down", "down", "down", "down" }
local R1_Y5 = { "up", "right", "right", "right",
                "down", "down", "down", "down", "down", "down" }
-- Route22Rival2ExitMovementData1 falls through Data2, so index 1 (y=4) is
-- LEFT x4 from (29,5) and index 2 (y=5) LEFT x3 from (28,5)
local R2_Y4 = { "left", "left", "left", "left" }
local R2_Y5 = { "left", "left", "left" }
local CER_X20 = { "right", "down", "down", "down", "down", "down", "down" }
local CER_X21 = { "left", "down", "down", "down", "down", "down", "down" }

do
  local game = { save = { flags = { EVENT_GOT_POKEDEX = true } }, data = {} }
  local w5 = findWalk(capture(story5.ROUTE_22, game, 29, 5))
  local w4 = findWalk(capture(story5.ROUTE_22, game, 29, 4))
  check(dirsEqual(w5[3], R1_Y5), "Rival1 y=5 goes U,R×3,D×6 around the player")
  check(dirsEqual(w4[3], R1_Y4), "Rival1 y=4 exits toward Viridian (R,R,D×5)")
  local rows = capture(story5.ROUTE_22,
    { save = { flags = { EVENT_GOT_POKEDEX = true } }, data = {} }, 29, 5)
  for _, r in ipairs(rows) do
    check(not (r[1] == "move_npc_to" and r[3] == 25 and r[4] == 5),
          "Rival1 must not retreat to spawn (25,5)")
  end
end

do
  local flags = {
    EVENT_BEAT_BROCK = true,
    EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE = true,
    EVENT_BEAT_GIOVANNI = true,
  }
  local w5 = findWalk(capture(story5.ROUTE_22, { save = { flags = flags }, data = {} }, 29, 5))
  local w4 = findWalk(capture(story5.ROUTE_22, { save = { flags = flags }, data = {} }, 29, 4))
  check(dirsEqual(w5[3], R2_Y5), "Rival2 y=5 exits left×3 toward League")
  check(dirsEqual(w4[3], R2_Y4), "Rival2 y=4 exits left×4 toward League")
end

do
  local rows = capture(story5.CERULEAN_CITY, { save = { flags = {} }, data = {} }, 20, 6)
  local t = texts(rows)
  local hasBill = false
  for _, id in ipairs(t) do
    if id == "_CeruleanCityRivalIWentToBillsText" then hasBill = true end
  end
  check(hasBill, "Cerulean post-battle includes Bill dialogue")
  local order = {
    "_CeruleanCityRivalPreBattleText",
    "_CeruleanCityRivalIWentToBillsText",
  }
  local pi = 1
  for _, id in ipairs(t) do
    if pi <= #order and id == order[pi] then pi = pi + 1 end
  end
  eq(pi, #order + 1, "Cerulean text order: pre, Bill")
  check(dirsEqual(lastWalk(rows)[3], CER_X20),
        "Cerulean x=20 exit: right then into town")
  for _, r in ipairs(rows) do
    check(not (r[1] == "move_npc_to" and r[4] == 2),
          "Cerulean must not walk back north to (20,2)")
  end
end

do
  local rows = capture(story5.CERULEAN_CITY, { save = { flags = {} }, data = {} }, 21, 6)
  check(dirsEqual(lastWalk(rows)[3], CER_X21),
        "Cerulean x=21 exit: left then into town")
end

-- #2149 scripts/CeruleanCity.asm:84-99
for _, px in ipairs({ 20, 21 }) do
  local rows = capture(story5.CERULEAN_CITY, { save = { flags = {} }, data = {} }, px, 6)
  local place = findRow(rows, "place_npc")
  check(place ~= nil, ("Cerulean x=%d places the rival before he walks"):format(px))
  eq(place[2], 1, "place_npc addresses CERULEANCITY_RIVAL (object 1)")
  eq(place[3], px, ("the rival spawns in the player's column (x=%d)"):format(px))
  eq(place[4], 2, "the rival spawns on the object_event home row 2")
  check(dirsEqual(findWalk(rows)[3], { "down", "down", "down" }),
        ("Cerulean x=%d approach is CeruleanCityMovement1"):format(px))
  check(findRow(rows, "move_npc_to") == nil,
        "the BFS walk is gone, so no fourth sideways step")
end

-- #2151 scripts/CeruleanCity.asm:141
local function assertEndBattleText(rows, what)
  local save, si = findRow(rows, "save_end_battle_text")
  check(save ~= nil, what .. " arms save_end_battle_text")
  eq(save[2], "_CeruleanCityRivalDefeatedText", what .. " arms the loss line")
  local _, bi = findRow(rows, "rival_battle")
  eq(si, bi - 1, what .. " arms it on the row before rival_battle")
  for _, r in ipairs(rows) do
    check(not (r[1] == "show_text" and r[2] == "_CeruleanCityRivalDefeatedText"),
          what .. " no longer prints the loss line from the script queue")
  end
end

do
  local rows = capture(story5.CERULEAN_CITY, { save = { flags = {} }, data = {} }, 21, 6)
  assertEndBattleText(rows, "the Cerulean ambush")
  assertEndBattleText(story.CERULEAN_CITY.talk.TEXT_CERULEANCITY_RIVAL,
                      "the Cerulean talk path")
end

do
  local ScriptRunner = require("src.script.ScriptRunner")
  local anyVerb = function() return true end
  local scenes = {
    ["Cerulean ambush x=20"] =
      capture(story5.CERULEAN_CITY, { save = { flags = {} }, data = {} }, 20, 6),
    ["Cerulean ambush x=21"] =
      capture(story5.CERULEAN_CITY, { save = { flags = {} }, data = {} }, 21, 6),
    ["Cerulean talk"] = story.CERULEAN_CITY.talk.TEXT_CERULEANCITY_RIVAL,
    ["S.S. Anne 2F x=36"] =
      capture(story5.SS_ANNE_2F, { save = { flags = {} }, data = {} }, 36, 8),
    ["S.S. Anne 2F x=37"] =
      capture(story5.SS_ANNE_2F, { save = { flags = {} }, data = {} }, 37, 8),
  }
  for name, rows in pairs(scenes) do
    local problems = ScriptRunner.validate(rows, anyVerb)
    eq(#problems, 0, name .. " jump targets resolve: "
       .. table.concat(problems, "; "))
  end
end

-- #2164 scripts/SSAnne2F.asm:73
do
  local game = { save = { flags = {} }, data = {} }
  local kept
  local function captureFacing(x)
    local rows
    local ow = {
      runner = {
        isRunning = function() return false end,
        run = function(_, r) rows = r end,
      },
      player = { facing = "right" },
      npcByIndex = function() return { def = { name = "X" } } end,
    }
    check(story5.SS_ANNE_2F.onStep(game, ow, x, 8),
          ("SS Anne onStep fires at (%d,8)"):format(x))
    kept = ow.player.facing
    return rows
  end

  local right = captureFacing(37)
  eq(kept, "right", "the player keeps his walking facing while the rival comes down")
  local turn, ti = findRow(right, "face_player_dir")
  check(turn ~= nil, "x=37 turns the player as a scripted row")
  eq(turn[2], "left", "x=37 turns the player left")
  local _, mi = findRow(right, "move_npc_to")
  local _, xi = findRow(right, "show_text")
  check(ti > mi, "the turn happens after the rival's walk")
  check(ti < xi, "the turn happens before the dialogue box")

  local left = captureFacing(36)
  eq(kept, "right", "x=36 leaves the player's facing alone")
  check(findRow(left, "face_player_dir") == nil,
        "x=36 never writes wPlayerMovingDirection")
end

do
  local talk = story.CERULEAN_CITY.talk.TEXT_CERULEANCITY_RIVAL
  check(talk ~= nil, "talk script for CERULEANCITY_RIVAL exists")
  local hasBill = false
  for _, r in ipairs(talk) do
    if r[1] == "show_text" and r[2] == "_CeruleanCityRivalIWentToBillsText" then
      hasBill = true
    end
  end
  check(hasBill, "talk path also exposes Bill dialogue")
end

package.loaded["src.core.Music"] = realMusic
package.loaded["src.script.Commands"] = realCommands
package.loaded["src.ui.PicBox"] = realPicBox

S.finish()
