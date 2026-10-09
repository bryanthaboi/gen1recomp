-- scripts/OaksLab.asm:448-472/488-508, engine/overworld/pathfinding.asm:36-70;
-- pokeyellow scripts/OaksLab.asm:411-436/452-469 (one extra down step).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local function fakeOw(rival)
  return {
    npcByIndex = function(_, i) return i == 1 and rival or nil end,
    map = {
      inBounds = function() return true end,
      isWalkableCell = function() return true end,
    },
    runner = { run = function() return true end },
  }
end

local function captureRun(ow)
  local captured
  ow.runner.run = function(_, rows) captured = rows return true end
  return function() return captured end
end

local function baseGame()
  return {
    save = {
      flags = {
        EVENT_GOT_STARTER = true,
        EVENT_BATTLED_RIVAL_IN_OAKS_LAB = false,
        EVENT_CHOSE_BULBASAUR = true,
      },
    },
  }
end

local function runOnStep(path, rival, x, y)
  local M = assert(loadfile(path))()
  local ow = fakeOw(rival)
  local getRows = captureRun(ow)
  local ok = M.onStep(baseGame(), ow, x, y)
  T.check(ok == true, path .. ": onStep claims the rival-challenge step")
  local rows = getRows()
  T.check(rows ~= nil, path .. ": the challenge rows reached the runner")
  return rows or {}
end

local function indexOf(rows, pred, from)
  for i = from or 1, #rows do
    if pred(rows[i]) then return i end
  end
  return nil
end

local function isMove(row, dir)
  return row[1] == "move_npc" and row[3] == dir
end

local function checkApproach(rows, expectX, expectXCount)
  T.check(indexOf(rows, function(r) return r[1] == "move_npc_to" end) == nil,
    "no move_npc_to row survives on the approach (#1989)")
  local i = indexOf(rows, function(r) return r[1] == "move_npc" end)
  T.check(i ~= nil, "the rival walks the approach with move_npc rows")
  if not i then return #rows + 1 end
  T.same(rows[i], { "move_npc", 1, expectX, expectXCount },
    "the rival closes the X distance first (FindPathToPlayer ties to X)")
  T.same(rows[i + 1], { "move_npc", 1, "down", 1 },
    "then the single Y step down to the tile above the player")
  return i + 2
end

local function checkExit(rows, from, side, totalDowns, turnAfterDowns)
  local i = indexOf(rows, function(r) return isMove(r, side) end, from)
  T.check(i ~= nil, "the rival sidesteps " .. side .. " out of the column")
  if not i then return end
  T.same(rows[i], { "move_npc", 1, side, 1 }, "the sidestep is a single tile")
  local downs, sideTurnAt, downTurnAt = 0, nil, nil
  local j = i + 1
  while rows[j] and rows[j][1] ~= "hide_object" do
    local r = rows[j]
    if isMove(r, "down") then downs = downs + r[4] end
    if r[1] == "walk_npc" and r[2] == 1 then
      for _, d in ipairs(r[3]) do
        if d == "down" then downs = downs + 1 end
      end
    end
    if r[1] == "face_player_dir" and r[2] == side then sideTurnAt = downs end
    if r[1] == "face_player_dir" and r[2] == "down" then downTurnAt = downs end
    j = j + 1
  end
  T.eq(downs, totalDowns, "the rival walks straight down to his hide cell")
  T.eq(sideTurnAt, turnAfterDowns,
    "the player turns " .. side .. " to watch him go (#1987)")
  T.eq(downTurnAt, turnAfterDowns + 1,
    "and turns down one step later, as the counter branch does")
  T.same(rows[j], { "hide_object", "OAKS_LAB", "OAKSLAB_RIVAL" },
    "the rival is hidden where the movement list runs out")
end

local RED = "data/scripts/oaks_lab.lua"
local YELLOW = "data/scripts/oaks_lab_yellow.lua"

do
  local rows = runOnStep(RED, { cellX = 7, cellY = 4 }, 4, 6)
  local after = checkApproach(rows, "left", 3)
  checkExit(rows, after, "right", 5, 0)
end

do
  local rows = runOnStep(RED, { cellX = 7, cellY = 4 }, 5, 6)
  local after = checkApproach(rows, "left", 2)
  checkExit(rows, after, "left", 5, 0)
end

do
  local rows = runOnStep(RED, { id = "rival" }, 4, 6)
  T.check(indexOf(rows, function(r)
    return r[1] == "move_npc_to" and r[3] == 4 and r[4] == 5
  end) ~= nil, "a coordinate-less rival falls back to move_npc_to")
end

do
  local rows = runOnStep(YELLOW, { cellX = 7, cellY = 4 }, 4, 6)
  local after = checkApproach(rows, "left", 3)
  checkExit(rows, after, "right", 6, 1)
end

do
  local rows = runOnStep(YELLOW, { cellX = 7, cellY = 4 }, 5, 6)
  local after = checkApproach(rows, "left", 2)
  checkExit(rows, after, "left", 6, 1)
end

T.finish("oaks_lab_rival_paths_bug1989_bug1987")
