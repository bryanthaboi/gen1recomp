package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local src = cache and cache:read("data/generated/gba/pokemon/battle_anims/pack.lua")
local manifest = cache and cache:read("data/generated/gba/pokemon/battle/manifest.lua")
if type(src) ~= "string" or type(manifest) ~= "string" or not manifest:find('layout = "rse"', 1, true) then
  print("emerald_battle_anims_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end
local pack = assert(load(src, "@pack.lua", "t", {}))()

local Anim = require("src.core.game3.battle.anim")
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
AnimTasks.init()

do
  local coords = Anim.Coords
  local vm = AnimVm.new()
  local contestLabel = { { op = "delay", frames = 2 }, { op = "end" } }
  vm:setPack({ labels = { CONTEST_ANIM = contestLabel } })
  local positions = { [2] = { 112, 80, x = 112, y = 80 }, [3] = { 48, 40, x = 48, y = 40 } }
  vm:launch({ { op = "jumpifcontest", label = "CONTEST_ANIM" }, { op = "end" } }, {
    ctx = { isContest = true }, coordinateOverrides = positions, attackerId = 2, targetId = 3,
  })
  vm:update(1 / 60)
  eq(vm.script[1].op, "delay", "jumpifcontest selects the contest animation body")
  eq(coords.coords(nil, 2).x .. "/" .. coords.coords(nil, 3).x, "112/48", "contest coordinates are active during playback")
  vm:tickFrames(5)
  eq(vm.active, false, "contest animation VM finishes")
  check(coords.coords(nil, 2) ~= positions[2], "animation end restores shared battler coordinates")
end

local moves = 0
for _ in pairs(pack.moves) do moves = moves + 1 end
eq(moves, 355, "Emerald gBattleAnims_Moves rows")
eq(pack.generalNames[4], "POKEBLOCK_THROW", "general anim 4")
eq(#pack.generalNames, 22, "23 general anims")
check(pack.tags.POKEBLOCK ~= nil and pack.tags.SAFARI_BAIT == nil, "tag 269 is POKEBLOCK on Emerald")

local function taskOk(name)
  local key = tostring(name):gsub("^g", "")
  return AnimTasks.REGISTRY[name] or AnimTasks.REGISTRY[key] or AnimTasks.REGISTRY["AnimTask_" .. key]
end
local function cbOk(name)
  local clean = tostring(name):gsub("^Anim", "")
  return AnimCallbacks[name] or AnimCallbacks[clean] or AnimCallbacks["Anim" .. clean]
end
local missing = {}
local function scan(script, where)
  for _, op in ipairs(script or {}) do
    if op.op == "createvisualtask" or op.op == "createsoundtask" then
      if not taskOk(op.task) then missing[#missing + 1] = "task " .. tostring(op.task) .. " @" .. where end
    elseif op.op == "createsprite" then
      if op.callback and op.callback ~= "" and not cbOk(op.callback)
          and not AnimTasks.REGISTRY["_noGfx_" .. op.callback] and not (op.noGfx and taskOk(op.callback)) then
        missing[#missing + 1] = "callback " .. op.callback .. " @" .. where
      end
      if op.tag and not pack.tags[op.tag] then missing[#missing + 1] = "tag " .. op.tag .. " @" .. where end
    elseif op.op == "loadspritegfx" and op.tag and not pack.tags[op.tag] then
      missing[#missing + 1] = "tag " .. op.tag .. " @" .. where
    end
  end
end
for id, s in pairs(pack.moves) do scan(s, "move " .. id) end
for _, kind in ipairs({ "general", "special", "status" }) do
  for i, s in pairs(pack[kind]) do scan(s, kind .. " " .. tostring(pack[kind .. "Names"][i])) end
end
for l, s in pairs(pack.labels) do scan(s, "label " .. l) end
for _, m in ipairs(missing) do print("  unresolved " .. m) end
eq(#missing, 0, "every task/callback/tag in the Emerald pack resolves")
check(taskOk("ThrowBall_StandingTrainer") ~= nil, "AnimTask_ThrowBall_StandingTrainer registered")
check(taskOk("IsBallBlockedByTrainer") ~= nil, "AnimTask_IsBallBlockedByTrainer registered")

local PicSizes = require("src.core.game3.battle.anim_port.g1_pic_sizes")
local pc = assert(load(cache:read("data/generated/gba/pokemon/pic_coords.lua"), "@pic_coords", "t", {}))()
eq(PicSizes.front[1], pc.front[1].width * 256 + pc.front[1].height, "Emerald front pic size from the pic_coords pack")
eq(PicSizes.back[25], pc.back[25].width * 256 + pc.back[25].height, "Emerald back pic size from the pic_coords pack")
check(PicSizes.front ~= PicSizes.FRLG.front, "Emerald does not read the FRLG pic size table")
eq(require("src.core.game3.battle.anim_port.g2_mon_sizes").front[1],
  (pc.front[1].width / 8) * 16 + pc.front[1].height / 8, "g2 mon size shape from the pack")

local rp = print
local logs = {}
local errors, timeouts, ran = 0, 0, 0
local function run(label, script, side)
  AnimTasks.reset()
  AnimSprites.reset()
  Anim.reset({ headless = true })
  Anim.loadPack(pack)
  local vm = AnimVm.new()
  vm:setPack(pack)
  print = function(...) logs[#logs + 1] = label .. ": " .. table.concat({ ... }, " ") end
  local ok, err = pcall(function()
    vm:launch(script, {
      attackerSide = side, targetSide = side == "player" and "enemy" or "player", isReversed = side == "enemy",
      attackerSpecies = 280, targetSpecies = 288,
    })
    local n = 0
    while vm:busy() and n < 1500 do
      n = n + 1
      vm:update(1 / 60)
      Anim.update(1 / 60)
    end
  end)
  print = rp
  ran = ran + 1
  if not ok then
    errors = errors + 1
    rp("  " .. label .. ": " .. tostring(err))
  elseif vm:busy() then
    timeouts = timeouts + 1
    rp("  " .. label .. ": timeout")
  end
end
for id = 1, 354 do
  run("move " .. id .. "/player", pack.moves[id], "player")
  run("move " .. id .. "/enemy", pack.moves[id], "enemy")
end
for i = 0, #pack.generalNames do run("general " .. pack.generalNames[i], pack.general[i], "player") end
for i = 0, #pack.statusNames do run("status " .. pack.statusNames[i], pack.status[i], "enemy") end
local taskErrors = 0
for _, l in ipairs(logs) do
  if l:find("[battle.anim]", 1, true) and not l:find("cap", 1, true) then
    taskErrors = taskErrors + 1
    rp("  " .. l)
  end
end
eq(errors, 0, "no Lua error across " .. ran .. " Emerald anims")
eq(timeouts, 0, "every Emerald move/general/status anim ends")
eq(taskErrors, 0, "no task/sprite callback error logged")

T.finish()
