-- Game3 Overworld Step Events Engine (pret field_control_avatar.c / wild_encounter.c).
-- Features:
-- 1. Lockstep Event Queue: Prevents simultaneous tick collisions; flushes on party white-out.
-- 2. Happiness Step Counter (128 steps): +1 friendship to all party Pokémon.
-- 3. VS Seeker Battery (100 steps): Increments while the VS SEEKER is in the bag.
-- 4. Overworld Poison (4 steps): 4-frame reddish screen flash, SE_FIELD_POISON, lethal faint at 0 HP.
-- 5. Egg Cycles & Daycare (daycare stepCounter == 255): Decrements egg cycles -> EggHatch; +1 EXP per step in Daycare.
-- 6. Repel Counter: Decrements steps -> Text_RepelWoreOff on expiration.

local Pokemon = require("src.core.game3.pokemon")
local RomText = require("src.core.game3.rom_text")

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

-- pokefirered/src/field_control_avatar.c:658
local function forced_step()
  local ForcedMovement = package.loaded["src.core.game3.forced_movement"]
    or require("src.core.game3.forced_movement")
  if ForcedMovement.isForced() then return true end
  local Player = package.loaded["src.core.game3.player"]
  local Collision = package.loaded["src.core.game3.collision"]
  if not (Player and Collision and Collision.behavior) then return false end
  local ok, mb = pcall(Collision.behavior, Player.cellX, Player.cellY)
  mb = ok and tonumber(mb) or nil
  if not mb then return false end
  return ForcedMovement.isForcedMovementTile(mb)
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

-- data/scripts/white_out.inc:43
local function field_white_out_event(session, game)
  local ev = { type = "poison_white_out" }
  ev.run = function(onDone)
    if not party_is_wiped(session.party) then
      onDone()
      return
    end
    local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
    Field.lock()
    local BattleBridge = require("src.core.game3.battle_bridge")
    local save = game and game.save
    local name = session.name or session.playerName or ""
    local money = tonumber(session.money) or 0
    local msg
    if money >= 1 then
      -- pokefirered/src/overworld.c:260
      local loss = math.min(BattleBridge.calcMoneyLossFrlg(session, save), money)
      -- data/scripts/white_out.inc:56
      msg = RomText.box("Text_WhitedOutLostMoney", { playerName = name, stringVars = { tostring(loss) } })
    else
      -- data/scripts/white_out.inc:50
      msg = RomText.box("Text_WhitedOut", { playerName = name })
    end
    ev.whiteOutText = msg
    local Hud = require("src.ui.game3.hud")
    Hud.openMessage(game, msg, {
      done = function()
        -- pokefirered/src/field_screen_effect.c:214
        require("src.core.game3.audio").fadeOutBgm(4)
        ev.phase = "music"
      end,
    })
  end
  ev.tick = function()
    if ev.phase ~= "music" then return end
    local Audio = require("src.core.game3.audio")
    if Audio._fadeOut then return end
    ev.phase = "fade"
    local Fade = require("src.ui.game3.fade")
    -- data/scripts/white_out.inc:63
    Fade.begin(Fade.MODE.TO_BLACK, 1, function()
      StepEvents.flush()
      local BattleBridge = require("src.core.game3.battle_bridge")
      -- pokefirered/src/overworld.c:253
      BattleBridge.applyFrlgMoneyLoss(session, game and game.save)
      local Field = package.loaded["src.core.game3.field"] or require("src.core.game3.field")
      Field.respawnAtHeal()
    end)
  end
  return ev
end

--- Evaluate step counters upon completing a grid step (Walk, Run, Bike, Surf).
function StepEvents.onStepTaken(session, game)
  if not session then return end
  session.vars = session.vars or {}
  local party = session.party or {}
  StepEvents._totalSteps = StepEvents._totalSteps + 1

  -- 1. Happiness Counter (VAR_HAPPINESS_STEP_COUNTER % 128)
  -- pokefirered/src/field_control_avatar.c:687 UpdateHappinessStepCounter
  local hapSteps = (tonumber(session.vars[0x4021] or session.happinessSteps) or 0) + 1
  if hapSteps >= 128 then
    hapSteps = 0
    -- pokefirered/src/field_control_avatar.c:699
    local ctx = { mapSec = Pokemon.currentMapSec(session) }
    for _, mon in ipairs(party) do
      Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_WALKING, ctx)
    end
  end
  session.vars[0x4021] = hapSteps
  session.happinessSteps = hapSteps

  -- pokefirered/src/field_control_avatar.c:217
  local MysteryGift = require("src.core.game3.mystery_gift")
  MysteryGift.incrementNewsStepCounter(session)

  -- pokefirered/src/field_specials.c:2068
  local massage = tonumber(session.vars[0x4025]) or 0
  if massage < 500 then session.vars[0x4025] = massage + 1 end

  -- pokefirered/src/field_specials.c:2433 IncrementBirthIslandRockStepCount
  require("src.core.game3.deoxys").incrementStepCount(session)

  -- pokefirered/src/field_control_avatar.c:219 IncrementRenewableHiddenItemStepCounter
  local okRen, Renewable = pcall(require, "src.core.game3.renewable_hidden_items")
  if okRen and Renewable and Renewable.onStep then
    Renewable.onStep(session, session.mapGroup, session.mapNum, session.map)
  end

  -- pokefirered/src/field_control_avatar.c:658
  local forced = forced_step()
  local poisonFainted = false
  local vsChargeDone = false
  if not forced then
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
          -- pokefirered/src/field_poison.c:36
          Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_FAINT_OUTSIDE_BATTLE,
            { mapSec = Pokemon.currentMapSec(session) })
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
      se(72) -- SE_FIELD_POISON (72)

      -- pokefirered/src/field_control_avatar.c:727 FLDPSN_FNT
      poisonFainted = #faintedMons > 0
      for _, fainted in ipairs(faintedMons) do
        push_event({
          type = "poison_faint",
          name = fainted.name,
          mon = fainted.mon,
          run = function(onDone)
            local Hud = require("src.ui.game3.hud")
            -- pokefirered/src/field_poison.c:64
            Hud.openMessage(game, RomText.box("gText_PkmnFainted3", { stringVars = { fainted.name } }),
              { done = onDone })
          end,
        })
      end
      -- pokefirered/src/field_poison.c:76
      if poisonFainted then push_event(field_white_out_event(session, game)) end
    end
  end
  session.vars[0x4040] = psnSteps
  session.poisonSteps = psnSteps

  -- pokefirered/src/field_control_avatar.c:670 ShouldEggHatch
  if not forced and not poisonFainted then
    local Daycare = package.loaded["src.core.game3.daycare"]
      or require("src.core.game3.daycare")
    local _, hatchSlot = Daycare.step(session)
    local hatching = hatchSlot and party[hatchSlot]
    if hatching then
      -- pokefirered/src/field_control_avatar.c:673 EventScript_EggHatch
      push_event({
        type = "egg_hatch",
        mon = hatching,
        slot = hatchSlot,
        run = function(onDone)
          local EggHatch = require("src.ui.game3.egg_hatch")
          local Audio = require("src.core.game3.audio")
          local Hud = require("src.ui.game3.hud")
          -- pokefirered/data/scripts/day_care.inc:112 DayCare_Text_Huh
          Hud.openMessage(game, RomText.box("DayCare_Text_Huh"), {
            done = function()
              -- pokefirered/data/scripts/day_care.inc:113 special EggHatch
              EggHatch.start(hatching, {
                session = session,
                slot = hatchSlot,
                savedSong = Audio._mapSong,
                onDone = onDone,
              })
            end,
          })
        end,
      })
      -- pokefirered/src/field_control_avatar.c:672 IncrementGameStat(GAME_STAT_HATCHED_EGGS)
      if type(session.gameStats) ~= "table" then session.gameStats = {} end
      -- pokefirered/include/constants/game_stat.h:17
      local hatched = math.floor(tonumber(session.gameStats[13]) or 0)
      session.gameStats[13] = math.min(0xFFFFFF, hatched + 1)
      -- pokefirered/src/field_control_avatar.c:674 return TRUE
      StepEvents.onRepelStep(session, game)
      return
    end
  end

  -- pokefirered/src/safari_zone.c:60 CB2_EndSafariBattle
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.pollSafariBalls and Field.pollSafariBalls(game) then
    return
  end

  -- pokefirered/src/field_control_avatar.c:677
  local okSafari, Safari = pcall(require, "src.core.game3.safari")
  if okSafari and Safari and Safari.takeStep and Safari.takeStep(session, game) then
    return
  end

  StepEvents.onRepelStep(session, game)
end

function StepEvents.onRepelStep(session, game)
  -- 5. Repel Step Counter (VAR_REPEL_STEP_COUNT)
  local repelSteps = tonumber(session.repelSteps or session.vars[0x4020]) or 0
  if repelSteps > 0 then
    repelSteps = repelSteps - 1
    session.repelSteps = repelSteps
    session.vars[0x4020] = repelSteps

    if repelSteps == 0 then
      push_event({
        type = "repel_wore_off",
        run = function(onDone)
          local Hud = require("src.ui.game3.hud")
          -- data/scripts/repel.inc:2
          Hud.openMessage(game, RomText.box("Text_RepelWoreOff"), {
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
