-- pokeyellow scripts/OaksLab.asm:211-216, engine/overworld/movement.asm:871
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()
local SaveData = require("src.core.SaveData")

local lab = dofile("data/scripts/oaks_lab_yellow.lua")
local ball = lab.talk.TEXT_OAKSLAB_EEVEE_POKE_BALL

local function buildScene(cellX, cellY)
  local captured
  local game = { data = Data, save = SaveData.newGame() }
  game.save.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON = true
  local ow = {
    player = { cellX = cellX, cellY = cellY },
    runner = { run = function(_, rows) captured = rows end },
  }
  ball(game, ow, { def = {} }, function() end)
  return captured or {}
end

local function rivalSteps(rows)
  local steps = {}
  for _, row in ipairs(rows) do
    if row[1] == "move_npc_to" and row[2] == 1 then
      steps[#steps + 1] = "move_npc_to"
    elseif (row[1] == "walk_npc" or row[1] == "move_npc") and row[2] == 1 then
      local dirs = type(row[3]) == "table" and row[3] or {}
      if row[1] == "move_npc" then
        dirs = {}
        for i = 1, row[4] or 1 do dirs[i] = row[3] end
      end
      local opts = row[1] == "walk_npc" and row[4] or nil
      local frames = type(opts) == "table" and opts.stepFrames or 32
      for _, d in ipairs(dirs) do steps[#steps + 1] = d .. ":" .. frames end
    end
  end
  return table.concat(steps, " ")
end

for _, spot in ipairs({ { 7, 4 }, { 8, 3 } }) do
  local where = ("from (%d,%d)"):format(spot[1], spot[2])
  T.eq(rivalSteps(buildScene(spot[1], spot[2])),
       "down:32 right:16 right:16 right:16",
       "$00 is a normal down step and each $07 a double-speed right " .. where)
end

local rows = buildScene(7, 4)
local lastRight, shove
for i, row in ipairs(rows) do
  if row[1] == "walk_npc" and row[2] == 1 then lastRight = i end
  if row[1] == "move_player" and not shove then shove = i end
end
local last = rows[lastRight]
T.check(last and last[4] and last[4].wait == false and last[4].stepFrames == 16,
        "the last $07 runs fast without blocking the shove")
T.check(shove and lastRight and shove > lastRight,
        "the PAD_RIGHT x2 shove is queued once the last $07 has begun")
T.eq(rows[shove] and rows[shove][2], "right", "the shove pushes right")
T.eq(rows[shove] and rows[shove][3], 2, "the shove is two tiles")

T.finish("oaks_lab_yellow_eevee_push_fast_2821")
