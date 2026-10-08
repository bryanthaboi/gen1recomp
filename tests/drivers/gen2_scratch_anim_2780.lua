-- ../pokecrystal/data/moves/animations.asm:1509
-- ../pokecrystal/engine/battle_anims/anim_commands.asm:51-90
local U = require("tests.drivers.util")
local Sound = require("src.core.Sound")
local Mon = require("src.battle.gen2.Mon")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-scratch-anim-2780"
local SCENE_OFF = os.getenv("SCENE_ON") == nil

return function(game)
  os.execute('mkdir -p "' .. SHOT_DIR .. '" 2>/dev/null')
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[2780] " .. (cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    print("[2780] " .. (fails == 0 and "all claims passed" or (fails .. " claims failed")))
    love.event.quit(fails == 0 and 0 or 1)
    while true do U.wait(60) end
  end

  local tick = 0
  local timeline = {}
  local function note(kind, name, extra)
    timeline[#timeline + 1] = { t = tick, kind = kind, name = name, extra = extra }
  end
  for _, fnName in ipairs({ "play", "playStereo" }) do
    local real = Sound[fnName]
    Sound[fnName] = function(data, name, ...)
      local src = real(data, name, ...)
      local okp, playing = pcall(function() return src and src:isPlaying() end)
      note(fnName, name, (okp and playing) and "heard" or "dropped")
      return src
    end
  end

  U.wait(45)
  local world = game.world
  if not ok(world and world.map, "the world booted") then finish() end
  world:warpToMapId("ROUTE_29", 48, 3, "up")
  U.wait(30)

  game.options.battleScene = not SCENE_OFF
  local lead = Mon.new(game.data, "TOTODILE", 5)
  game.save.party = { lead }
  local wild = Mon.new(game.data, "SENTRET", 3)
  wild.moves = { { id = "TACKLE", pp = 40, maxPp = 40 } }
  ok(world:startBattle({ wild = wild }), "a wild battle started")
  local screen
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  if not ok(screen ~= nil, "the battle screen came up") then finish() end
  for _ = 1, 600 do
    if screen.phase == "menu" then break end
    if screen.anim == nil then U.tap(game, "a") end
    U.wait(2)
  end
  if not ok(screen.phase == "menu", "the battle menu came up") then finish() end
  ok((lead.moves[1] and lead.moves[1].id) == "SCRATCH", "Totodile's first move is SCRATCH")
  U.tap(game, "a")
  U.wait(10)
  timeline = {}
  U.tap(game, "a")
  local lastAnim, shots = nil, 0
  for _ = 1, 900 do
    tick = tick + 1
    local anim = screen.anim
    if anim ~= lastAnim then
      if anim then
        note("anim", anim.animId, (screen.typer and "typing" or "idle"))
      end
      lastAnim = anim
    end
    if anim and anim.animId == "SCRATCH" and anim.frames == 12 and shots == 0 then
      U.still(game, SHOT_DIR .. "/2780_01_scratch_claws.png")
      shots = 1
    end
    if anim and anim.animId == "ANIM_ENEMY_DAMAGE" and anim.frames == 6 and shots < 2 then
      U.still(game, SHOT_DIR .. "/2780_02_enemy_damage.png")
      shots = 2
    end
    if tick > 30 and screen.phase == "menu" then break end
    U.wait(1)
  end
  local trail = {}
  for _, e in ipairs(timeline) do
    trail[#trail + 1] = ("%d:%s:%s:%s"):format(e.t, e.kind, tostring(e.name), tostring(e.extra))
  end
  print("[2780] timeline " .. table.concat(trail, " "))

  local function first(kind, name)
    for _, e in ipairs(timeline) do
      if e.kind == kind and e.name == name then return e end
    end
  end
  if SCENE_OFF then
    ok(first("anim", "SCRATCH") == nil, "BATTLE SCENE OFF skips the SCRATCH script")
    ok(first("anim", "ANIM_ENEMY_DAMAGE") ~= nil, "the player's hit still runs ANIM_ENEMY_DAMAGE")
    local hits = {}
    for _, e in ipairs(timeline) do
      if e.kind == "play" and e.name == "Sfx_Damage" then hits[#hits + 1] = e end
    end
    ok(hits[1] and hits[1].extra == "heard", "the player's hit sound is heard")
    ok(hits[2] and hits[2].extra == "heard", "the enemy's hit sound is heard")
  else
    ok(first("anim", "SCRATCH") ~= nil, "the player's SCRATCH animation ran")
    local s = first("playStereo", "Sfx_Scratch")
    ok(s and s.extra == "heard", "Sfx_Scratch is heard")
    ok(first("anim", "TACKLE") ~= nil, "the enemy's TACKLE animation ran")
  end
  finish()
end
