-- scripts/SilphCo7F.asm:184-186
-- Self-contained; run via `luajit tests/parity_silph_rival_bug2241.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity silph co 7f rival")
local check, eq = S.check, S.eq

local realMusic = package.loaded["src.core.Music"]
package.loaded["src.core.Music"] = { play = function() end }

local story5 = dofile("data/scripts/story5.lua")
local silph = story5.SILPH_CO_7F
check(silph ~= nil and silph.onStep ~= nil, "SILPH_CO_7F onStep exists")

local function capture(y)
  local rows
  local probe = {
    runner = { isRunning = function() return false end,
               run = function(_, r) rows = r end },
    player = { facing = "up" },
  }
  local game = { data = {}, save = { flags = {} } }
  local fired = silph.onStep(game, probe, 3, y)
  return rows, fired, probe.player.facing
end

local function find(rows, verb, arg)
  for i, row in ipairs(rows) do
    if row[1] == verb and (arg == nil or row[2] == arg) then return i, row end
  end
end

local ScriptRunner = require("src.script.ScriptRunner")

for _, y in ipairs({ 2, 3 }) do
  local rows, fired, facing = capture(y)
  check(fired == true and type(rows) == "table",
        ("onStep fires on (3,%d)"):format(y))
  eq(facing, "down", ("the player is turned down on (3,%d)"):format(y))

  local iBattle = find(rows, "rival_battle", "OPP_RIVAL2")
  local iArm = find(rows, "save_end_battle_text", "_SilphCo7FRivalDefeatedText")
  check(iArm ~= nil,
        ("(3,%d): _SilphCo7FRivalDefeatedText is armed for the battle"):format(y))
  check(iBattle and iArm == iBattle - 1,
        ("(3,%d): SaveEndBattleTextPointers runs just before the battle"):format(y))
  check(find(rows, "show_text", "_SilphCo7FRivalDefeatedText") == nil,
        ("(3,%d): the loss line is not also printed on the map"):format(y))

  local iSet = find(rows, "set_flag", "EVENT_BEAT_SILPH_CO_RIVAL")
  local iLuck = find(rows, "show_text", "_SilphCo7FRivalGoodLuckToYouText")
  check(iSet and iLuck and iLuck > iSet and iSet > (iBattle or 0),
        ("(3,%d): the win sets the event then prints GoodLuckToYou"):format(y))

  local problems = ScriptRunner.validate(rows)
  eq(#problems, 0, ("(3,%d): scene validates: %s"):format(y, table.concat(problems, "; ")))

  local iJump, jumpRow = find(rows, "jump_if_false")
  check(iJump ~= nil and type(jumpRow[2]) == "string",
        ("(3,%d): the loss branch jumps to a label, not a row number"):format(y))
  local iLabel = find(rows, "label", jumpRow and jumpRow[2])
  local iHide = find(rows, "hide_object")
  check(iLabel and iHide and iHide == iLabel + 1,
        ("(3,%d): the loss label sits right before hide_object"):format(y))

  local iWalk, walkRow = find(rows, "walk_npc")
  check(iWalk ~= nil and find(rows, "move_npc_to", 9) ~= nil,
        ("(3,%d): the exit is an explicit walk_npc"):format(y))
  check(iWalk and iHide and iWalk > iLuck and iHide > iWalk,
        ("(3,%d): the walk-out runs after GoodLuckToYou and before the hide"):format(y))
  local iDefault = find(rows, "play_default_music")
  check(iDefault and iWalk and iDefault > iWalk,
        ("(3,%d): PlayDefaultMusic follows the walk"):format(y))

  local iMove, moveRow = find(rows, "move_npc_to", 9)
  check(iMove and moveRow[3] == 3 and moveRow[4] == y + 1 and iMove < iBattle,
        ("(3,%d): the rival parks on (3,%d) before the fight"):format(y, y + 1))

  local want = (y == 2) and { "right", "right" }
    or { "left", "up", "up", "right", "right", "right", "down" }
  local dirs = walkRow and walkRow[3] or {}
  eq(table.concat(dirs, ","), table.concat(want, ","),
     ("(3,%d): exit list is %s"):format(y, table.concat(want, ",")))

  local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local rx, ry, prevX, prevY = 3, y + 1, nil, nil
  local throughPlayer = false
  for _, d in ipairs(dirs) do
    prevX, prevY = rx, ry
    rx, ry = rx + D[d][1], ry + D[d][2]
    if rx == 3 and ry == y then throughPlayer = true end
  end
  check(not throughPlayer, ("(3,%d): the exit never crosses the player's cell"):format(y))
  check(rx == 5 and ry == 3, ("(3,%d): the exit ends on the (5,3) teleporter"):format(y))
  if y == 3 then
    check(prevX == 5 and prevY == 2, "(3,3): the last step comes down from (5,2)")
  end
end

package.loaded["src.core.Music"] = realMusic
S.finish()
