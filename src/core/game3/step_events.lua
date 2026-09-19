-- Game3 Overworld Step Events Engine (pret field_control_avatar.c / wild_encounter.c).
-- Features:
-- 1. Lockstep Event Queue: Prevents simultaneous tick collisions; flushes on party white-out.
-- 2. Happiness Step Counter (128 steps): +1 friendship to all party Pokémon.
-- 3. VS Seeker Battery (100 steps): Increments while the VS SEEKER is in the bag.
-- 4. Overworld Poison (4 steps): 4-frame reddish screen flash, SE_FIELD_POISON, lethal faint at 0 HP.
-- 5. Egg Cycles & Daycare (256 steps): Decrements egg cycles -> EggHatchScene; +1 EXP per step in Daycare.
-- 6. Repel Counter: Decrements steps -> "Repel's effect wore off..." on expiration.

local Pokemon = require("src.core.game3.pokemon")
local ModRuntime = require("src.mods.Runtime")

local StepEvents = {}

StepEvents._queue = {}
StepEvents._activeEvent = nil
StepEvents._poisonFlashTimer = 0
StepEvents._totalSteps = 0

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

function StepEvents.busy()
  return StepEvents._activeEvent ~= nil or #StepEvents._queue > 0 or StepEvents._poisonFlashTimer > 0
end

function StepEvents.flush()
  StepEvents._queue = {}
  StepEvents._activeEvent = nil
  StepEvents._poisonFlashTimer = 0
end

function StepEvents.queueEvent(event)
  if type(event) == "function" then
    local fn = event
    event = { run = function(onDone) fn() if onDone then onDone() end end }
  end
  StepEvents._queue[#StepEvents._queue + 1] = event
end

local push_event = StepEvents.queueEvent

-- pokefirered/src/metatile_behavior.c:266
local function forced_step()
  local Player = package.loaded["src.core.game3.player"]
  local Collision = package.loaded["src.core.game3.collision"]
  if not (Player and Collision and Collision.behavior) then return false end
  local ok, mb = pcall(Collision.behavior, Player.cellX, Player.cellY)
  mb = ok and tonumber(mb) or nil
  if not mb then return false end
  return (mb >= 0x40 and mb <= 0x48) or (mb >= 0x50 and mb <= 0x53)
    or mb == 0x13 or mb == 0x23 or (mb >= 0x54 and mb <= 0x57)
end

local function party_is_wiped(party)
  if not party or #party == 0 then return false end
  local hasAlive = false
  for _, mon in ipairs(party) do
    local isEgg = mon.isEgg or (type(mon.egg) == "boolean" and mon.egg)
    local hp = tonumber(mon.hp) or 0
    if not isEgg and hp > 0 then
      hasAlive = true
      break
    end
  end
  return not hasAlive
end

local function trigger_white_out(session, game)
  StepEvents.flush()
  if session and session.onWhiteout then
    session.onWhiteout()
    return
  end
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Fade = require("src.ui.game3.fade")

  -- 1. Faint message
  local Hud = require("src.ui.game3.hud")
  local playerName = (session and (session.name or session.playerName)) or "PLAYER"
  local msg = playerName .. " is out of usable\nPOKéMON!\n\n" .. playerName .. " whited out!"

  Hud.openMessage(game, msg, {
    done = function()
      -- 2. Fade to black and warp to last heal location (or Pallet Town player house)
      Fade.begin(Fade.MODE.TO_BLACK, 0.5, function()
        local healMap = (session and session.healMap) or "FR_PALLET_TOWN_PLAYERS_HOUSE_2F"
        local healX = (session and session.healX) or 6
        local healY = (session and session.healY) or 6
        local healFacing = (session and session.healFacing) or "down"
        if ModRuntime.wants("world.blacked_out") then
          ModRuntime.emit("world.blacked_out", {
            save = session,
            healTarget = { map = healMap, x = healX, y = healY },
          })
        end

        -- Heal all party Pokémon
        if session and session.party then
          for _, mon in ipairs(session.party) do
            local maxHp = tonumber(mon.maxHp or mon.maxhp) or 1
            mon.hp = maxHp
            mon.status = nil
            mon.statusNum = 0
          end
        end

        Map.load(Runtime._mod, game, healMap, {
          x = healX,
          y = healY,
          facing = healFacing,
        })
        Fade.begin(Fade.MODE.FROM_BLACK, 0.5)
      end)
    end
  })
end

--- Evaluate step counters upon completing a grid step (Walk, Run, Bike, Surf).
function StepEvents.onStepTaken(session, game)
  if not session then return end
  session.vars = session.vars or {}
  local party = session.party or {}
  StepEvents._totalSteps = StepEvents._totalSteps + 1

  -- 1. Happiness Counter (VAR_HAPPINESS_STEP_COUNTER % 128)
  local hapSteps = (tonumber(session.vars[0x403F] or session.happinessSteps) or 0) + 1
  if hapSteps >= 128 then
    hapSteps = 0
    for _, mon in ipairs(party) do
      if not (mon.isEgg or (type(mon.egg) == "boolean" and mon.egg)) then
        local curHap = tonumber(mon.friendship or mon.happiness) or 70
        if curHap < 255 then
          mon.friendship = math.min(255, curHap + 1)
          mon.happiness = mon.friendship
        end
      end
    end
  end
  session.vars[0x403F] = hapSteps
  session.happinessSteps = hapSteps

  -- pokefirered/src/field_control_avatar.c:658
  local vsChargeDone = false
  if not forced_step() then
    local VsSeeker = require("src.core.game3.vs_seeker")
    if VsSeeker.onStep(session) then
      vsChargeDone = true
      push_event(VsSeeker.chargingDoneEvent())
    end
  end
  if vsChargeDone then
    StepEvents.onRepelStep(session, game)
    return
  end

  -- 3. Overworld Poison Counter (every 4 steps, pret field_poison.c)
  local psnSteps = (tonumber(session.vars[0x4040] or session.poisonSteps) or 0) + 1
  if psnSteps >= 4 then
    psnSteps = 0
    local anyPoisonDamage = false
    local faintedMons = {}

    for slotIdx, mon in ipairs(party) do
      local isEgg = mon.isEgg or (type(mon.egg) == "boolean" and mon.egg)
      local st = tostring(mon.status or ""):upper()
      local isPsn = (st == "PSN" or st == "POISON" or st == "TOXIC" or (tonumber(mon.statusNum) or 0) == 8)
      local hp = tonumber(mon.hp) or 0

      if not isEgg and isPsn and hp > 0 then
        anyPoisonDamage = true
        mon.hp = math.max(0, hp - 1)
        if mon.hp == 0 then
          mon.status = nil
          mon.statusNum = 0
          faintedMons[#faintedMons + 1] = {
            slot = slotIdx,
            mon = mon,
            name = Pokemon.displayMonName(mon),
          }
        end
      end
    end

    if anyPoisonDamage then
      -- Trigger 4-frame reddish screen flash and poison SE
      StepEvents._poisonFlashTimer = 4 / 60
      se(35) -- SE_FIELD_POISON

      for _, fainted in ipairs(faintedMons) do
        push_event({
          type = "poison_faint",
          name = fainted.name,
          mon = fainted.mon,
          run = function(onDone)
            -- Play mon cry
            pcall(function()
              local Audio = require("src.core.game3.audio")
              local sp = Pokemon.speciesOf(fainted.mon)
              if Audio and Audio.playCry and sp then Audio.playCry(sp) end
            end)

            local Hud = require("src.ui.game3.hud")
            Hud.openMessage(game, fainted.name .. " fainted...", {
              done = function()
                if party_is_wiped(party) then
                  trigger_white_out(session, game)
                else
                  onDone()
                end
              end
            })
          end,
        })
      end
    end
  end
  session.vars[0x4040] = psnSteps
  session.poisonSteps = psnSteps

  -- 4. Daycare EXP & Egg Hatching Cycles (every 256 steps)
  local eggSteps = (tonumber(session.eggSteps) or 0) + 1
  if eggSteps >= 256 then
    eggSteps = 0
    for slotIdx, mon in ipairs(party) do
      local isEgg = mon.isEgg or (type(mon.egg) == "boolean" and mon.egg)
      if isEgg then
        local cycles = tonumber(mon.friendship or mon.eggCycles or mon.cycles) or 20
        cycles = math.max(0, cycles - 1)
        mon.friendship = cycles
        mon.eggCycles = cycles
        if cycles == 0 then
          push_event({
            type = "egg_hatch",
            mon = mon,
            slot = slotIdx,
            run = function(onDone)
              local EvolutionScene = require("src.ui.game3.evolution_scene")
              local Audio = require("src.core.game3.audio")
              mon.isEgg = false
              mon.egg = false
              mon.level = 5
              Pokemon.applyStats(mon)
              EvolutionScene.start(mon, mon.species or mon.speciesId, {
                session = session,
                isEggHatch = true,
                savedSong = Audio._mapSong,
                onDone = onDone,
              })
            end,
          })
        end
      end
    end
  end
  session.eggSteps = eggSteps

  StepEvents.onRepelStep(session, game)
end

function StepEvents.onRepelStep(session, game)
  -- 5. Repel Step Counter (VAR_REPEL_STEP_COUNT)
  local repelSteps = tonumber(session.repelSteps or session.vars[0x4021]) or 0
  if repelSteps > 0 then
    repelSteps = repelSteps - 1
    session.repelSteps = repelSteps
    session.vars[0x4021] = repelSteps

    if repelSteps == 0 then
      push_event({
        type = "repel_wore_off",
        run = function(onDone)
          se(67) -- SE_REPEL
          local Hud = require("src.ui.game3.hud")
          Hud.openMessage(game, "Repel's effect wore off...", {
            done = onDone,
          })
        end,
      })
    end
  end
end

--- Pump the sequential lockstep queue.
function StepEvents.update(dt, game)
  if StepEvents._poisonFlashTimer > 0 then
    StepEvents._poisonFlashTimer = math.max(0, StepEvents._poisonFlashTimer - (dt or 1 / 60))
  end

  if StepEvents._activeEvent then
    local active = StepEvents._activeEvent
    if active.tick then active.tick(dt, game) end
    return
  end
  if #StepEvents._queue == 0 then return end

  local ev = table.remove(StepEvents._queue, 1)
  StepEvents._activeEvent = ev
  ev.run(function()
    StepEvents._activeEvent = nil
  end)
end

--- Render screen flash if poison triggered.
function StepEvents.draw()
  if StepEvents._poisonFlashTimer > 0 then
    local okR, Renderer = pcall(require, "src.render.Renderer")
    if okR and Renderer and Renderer.canvas then
      Renderer.screenVeil = { 0.85, 0.15, 0.15, 0.45 }
      return
    end
    love.graphics.setColor(0.85, 0.15, 0.15, 0.45)
    local w, h = 240, 160
    local curCanvas = love.graphics.getCanvas()
    if curCanvas then
      local okW, cw, ch = pcall(function() return curCanvas:getWidth(), curCanvas:getHeight() end)
      if okW and cw and ch then w, h = cw, ch end
    elseif love and love.graphics and love.graphics.getDimensions then
      local gw, gh = love.graphics.getDimensions()
      if gw and gh and gw > 0 and gh > 0 then w, h = gw, gh end
    end
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

StepEvents.onStep = StepEvents.onStepTaken

return StepEvents
