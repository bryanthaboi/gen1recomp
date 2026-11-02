-- engine/battle_anims/anim_commands.asm:100-139
-- engine/items/item_effects.asm:394-406

local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_ball_throw_no_skip_bug3094"
  local failures = 0
  local function ok(label, c, d)
    if c then print("[3094] PASS " .. label) else
      failures = failures + 1 print("[3094] FAIL " .. label .. " " .. tostring(d)) end
  end
  local function finish()
    print(failures == 0 and "[3094] PASS done" or "[3094] FAIL done")
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end
  local function waitFor(p, n)
    for _ = 1, n or 600 do if p() then return true end U.wait(1) end
    return p() and true or false
  end
  U.wait(45)
  local world = game.world
  local save = game.save
  save.party = { Mon.new(game.data, "CYNDAQUIL", 12) }
  save.inventory = { POTION = 2, POKE_BALL = 10 }
  local wild = Mon.new(game.data, "WOOPER", 5)
  ok("wild battle started", world:startBattle({ wild = wild }))
  local screen
  ok("battle screen up", waitFor(function()
    local t = game.stack:top()
    screen = t and t.battle and t or nil
    return screen ~= nil
  end, 900))
  if not screen then finish() end
  for _ = 1, 400 do if screen.phase == "menu" then break end U.tap(game, "a") U.wait(2) end
  ok("menu", screen.phase == "menu", screen.phase)
  if screen.phase ~= "menu" then finish() end
  screen.battle.random = function() return 0 end
  if screen.menuIndex % 2 == 0 then U.tap(game, "left") U.wait(3) end
  if screen.menuIndex <= 2 then U.tap(game, "down") U.wait(3) end
  U.tap(game, "a") U.wait(6)
  local pack = game.stack:top()
  for _ = 1, 4 do if pack.pocket and pack:pocket().id == "BALL" then break end U.tap(game, "right") U.wait(4) end
  local ballRow
  for i, row in ipairs(pack.rows or {}) do if row.id == "POKE_BALL" then ballRow = i end end
  ok("ball row", ballRow ~= nil, pack.rows and #pack.rows)
  if not ballRow then finish() end
  for _ = 1, 20 do if pack.index == ballRow then break end U.tap(game, pack.index < ballRow and "down" or "up") U.wait(3) end
  U.tap(game, "a") U.wait(4)
  U.tap(game, "a") U.wait(1)
  ok("ANIM_THROW_POKE_BALL started", screen.anim ~= nil and screen.anim.animId == "ANIM_THROW_POKE_BALL",
    screen.anim and screen.anim.animId)
  if not screen.anim then finish() end
  local frames = 0
  local marks = { [26] = "01_ball_thrown_after_b", [200] = "02_ball_wobble" }
  while screen.anim and not (screen.anim:done() and screen.anim.keepSprites) and frames < 2000 do
    frames = frames + 1
    if marks[frames] then
      U.still(game, ("%s/3094_%s.png"):format(out, marks[frames]))
    end
    if frames == 20 then U.tap(game, "b") else U.wait(1) end
  end
  print("[3094] anim frames", frames, "wobble", screen.ballThrow and screen.ballThrow.wobble)
  ok("B at frame 20 does not cut the throw short (>400 frames)", frames > 400, frames)
  ok("wobble loop reached its fourth GetPokeBallWobble call",
    screen.ballThrow and screen.ballThrow.wobble == 4, screen.ballThrow and screen.ballThrow.wobble)
  finish()
end
