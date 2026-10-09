package.path = "./?.lua;./?/init.lua;" .. package.path

local passed, failed = 0, 0
local function check(cond, name)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("[FAIL] " .. tostring(name))
  end
end

local Cache = require("tests.game3_cache")
local root = Cache.root("pokemon/battle_anims/pack.lua")
local okPack, pack = false, nil
if root then okPack, pack = pcall(dofile, root .. "/pokemon/battle_anims/pack.lua") end
if not (okPack and type(pack) == "table" and pack.moves) then
  print("[skip] no battle anim pack in the cache")
  os.exit(0)
end
Cache.mount("pokemon/battle_anims/pack.lua")

local Anim = require("src.core.game3.battle.anim")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCoords = require("src.core.game3.battle.anim_coords")

-- pokefirered/include/constants/moves.h:251
local MOVE_SHADOW_BALL = 247

Anim.reset({ headless = false })
Anim.loadPack(pack)
Anim.present("player").visible = true
Anim.present("enemy").visible = true
local vm = Anim.vm()
vm:launchTable("moves", MOVE_SHADOW_BALL, { attackerSide = "player", targetSide = "enemy", attackerSpecies = 94, targetSpecies = 9 })

local ball
for _ = 1, 120 do
  Anim.update(1 / 60)
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active and s._op and s._op.callback == "ShadowBall" then ball = s end
  end
  if ball then break end
end

-- pokefirered/data/battle_anim_scripts.s:7481
check(ball ~= nil, "Shadow Ball creates its ShadowBall sprite")
if ball then
  Anim.update(1 / 60)
  check(ball.sub == AnimCoords.SUBPRIORITY[1] - 2, "ball subpriority is the target's minus 2 (" .. tostring(ball.sub) .. ")")
  local z = ball._pz and AnimCoords.layerZ(ball.subpriority) or ball.z
  check(z < AnimCoords.monBehindZ("player"), "ball draws under the player's back sprite (z=" .. tostring(z) .. ")")
  check(z > AnimCoords.monBehindZ("enemy"), "ball draws over the enemy front sprite (z=" .. tostring(z) .. ")")
end

print(string.format("game3_anim_subpriority_behind_attacker: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
