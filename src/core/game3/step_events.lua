-- Game3 Overworld Step Events Engine (pret field_control_avatar.c / wild_encounter.c).
-- Features:
-- 1. Lockstep Event Queue: Prevents simultaneous tick collisions; flushes on party white-out.
-- 2. Happiness Step Counter (128 steps): +1 friendship to all party Pokémon.
-- 3. VS Seeker Battery (100 steps): Increments while the VS SEEKER is in the bag.
-- 4. Overworld Poison (4 steps RSE, 5 FRLG): 4-frame reddish screen flash, SE_FIELD_POISON, lethal faint at 0 HP.
-- 5. Egg Cycles & Daycare (daycare stepCounter == 255): Decrements egg cycles -> EggHatch; +1 EXP per step in Daycare.
-- 6. Repel Counter: Decrements steps -> Text_RepelWoreOff on expiration.

local Pokemon = require("src.core.game3.pokemon")
local RomText = require("src.core.game3.rom_text")
local Sem = require("src.core.game3.field_semantics")
local FieldModules = require("src.core.game3.field_modules")

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

local function field_poison_script_event(scriptName)
  local ev = { type = "field_poison_script", script = scriptName }
  ev.run = function(onDone)
    local Space = package.loaded["src.core.game3.scripting.space"]
      or require("src.core.game3.scripting.space")
    local key = Space.scriptKey(scriptName)
    if not (key and Space.startScript(key)) then
      error("field poison script did not start: " .. tostring(scriptName))
    end
    ev.tick = function()
      local vm = Space.vm
      if not vm or not vm.active then onDone() end
    end
  end
  return ev
end

--- Evaluate step counters upon completing a grid step (Walk, Run, Bike, Surf).
function StepEvents.onStepTaken(session, game)
  if not session then return false end
  session.vars = session.vars or {}
  local party = session.party or {}
  StepEvents._totalSteps = StepEvents._totalSteps + 1

  -- 1. Happiness Counter (VAR_HAPPINESS_STEP_COUNTER % 128)
  -- pokefirered/src/field_control_avatar.c:687 UpdateHappinessStepCounter
  local hapVar = Sem.var(session, "happinessSteps")
  local hapSteps = (tonumber(session.vars[hapVar] or session.happinessSteps) or 0) + 1
  if hapSteps >= 128 then
    hapSteps = 0
    -- pokefirered/src/field_control_avatar.c:699
    local ctx = { mapSec = Pokemon.currentMapSec(session) }
    for _, mon in ipairs(party) do
      Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_WALKING, ctx)
    end
  end
  session.vars[hapVar] = hapSteps
  session.happinessSteps = hapSteps

  local isRse = require("src.core.game3.profile").family(session) == "rse"
  local mcOn = isRse and require("src.core.game3.capabilities").gate(session, "match_call")
  local RsRematch = isRse and require("src.core.game3.rs.rematch")
  if RsRematch and RsRematch.enabled(session) then
    -- pokeruby/src/field_control_avatar.c:576
    RsRematch.incrementStepCounter(session)
  elseif mcOn then
    -- pokeemerald/src/field_control_avatar.c:543
    require("src.core.game3.rse.match_call").incrementRematchStepCounter(session)
  end
  if isRse then
    -- pokeemerald/src/field_control_avatar.c:545
    require("src.core.game3.faraway_island").updateStepCounter()
  end

  -- pokefirered/src/field_control_avatar.c:217
  local MysteryGift = require("src.core.game3.mystery_gift")
  MysteryGift.incrementNewsStepCounter(session)

  -- pokefirered/src/field_specials.c:2068
  local massageVar = Sem.var(session, "massageSteps")
  if massageVar then
    local massage = tonumber(session.vars[massageVar]) or 0
    if massage < 500 then session.vars[massageVar] = massage + 1 end
  end

  -- pokefirered/src/field_specials.c:2433 IncrementBirthIslandRockStepCount
  if FieldModules.enabled("deoxys", session) then
    require("src.core.game3.deoxys").incrementStepCount(session)
  end

  if isRse then
    local R = require("src.core.game3.rse.init")
    -- pokeemerald/src/field_control_avatar.c:158
    R.call("eventIslands", "incrementStepCount", nil, nil, session)
    -- pokeemerald/src/field_control_avatar.c:517
    local P = require("src.core.game3.player")
    R.call("pyramid", "onStep", nil, nil, session, P.cellX, P.cellY)
  end

  -- pokefirered/src/field_control_avatar.c:219 IncrementRenewableHiddenItemStepCounter
  local okRen, Renewable = false, nil
  if FieldModules.enabled("renewableHiddenItems", session) then
    okRen, Renewable = pcall(require, "src.core.game3.renewable_hidden_items")
  end
  if okRen and Renewable and Renewable.onStep then
    Renewable.onStep(session, session.mapGroup, session.mapNum, session.map)
  end

  -- pokefirered/src/field_control_avatar.c:658
  local forced = forced_step()
  local poisonFainted = false
  local vsChargeDone = false
  if not forced and FieldModules.enabled("vsSeeker", session) then
    local VsSeeker = require("src.core.game3.vs_seeker")
    if VsSeeker.onStep(session) then
      vsChargeDone = true
      push_event(VsSeeker.chargingDoneEvent())
    end
  end
  if vsChargeDone then
    -- pokefirered/src/field_control_avatar.c:663
    return true
  end

  -- pokeemerald/src/field_control_avatar.c:641
  local Map = package.loaded["src.core.game3.map"]
  local curDef = Map and Map.currentDef and Map.currentDef()
  -- pokeemerald/include/constants/map_types.h:13
  local psnGate = not forced and not (curDef and tonumber(curDef.mapType) == 9)
  local psnVar = Sem.var(session, "poisonSteps")
  local psnSteps = tonumber(session.vars[psnVar] or session.poisonSteps) or 0
  -- pokeemerald/src/field_control_avatar.c:645
  -- pokefirered/src/field_control_avatar.c:718
  local psnPeriod = isRse and 4 or 5
  if psnGate then psnSteps = (psnSteps + 1) % psnPeriod end
  if psnGate and psnSteps == 0 then
    local anyPoisonDamage = false
    local faintedMons = {}
    local profileField = require("src.core.game3.profile").forSession(session).field
    local poisonScript = profileField and profileField.fieldPoisonScript

    for slotIdx, mon in ipairs(party) do
      local isEgg = mon.isEgg or (type(mon.egg) == "boolean" and mon.egg)
      local st = tostring(mon.status or ""):upper()
      local isPsn = (st == "PSN" or st == "POISON" or st == "TOXIC" or (tonumber(mon.statusNum) or 0) == 8)
      local hp = tonumber(mon.hp) or 0

      if not isEgg and isPsn and hp > 0 then
        anyPoisonDamage = true
        mon.hp = math.max(0, hp - 1)
        if mon.hp == 0 and poisonScript then
          faintedMons[#faintedMons + 1] = { slot = slotIdx, mon = mon }
        elseif mon.hp == 0 then
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
      se(require("src.core.game3.se_ids").SE_FIELD_POISON)

      -- pokefirered/src/field_control_avatar.c:727 FLDPSN_FNT
      poisonFainted = #faintedMons > 0
      if poisonFainted and poisonScript then
        -- pokeemerald/src/field_control_avatar.c:551
        push_event(field_poison_script_event(poisonScript))
        faintedMons = {}
      end
      for _, fainted in ipairs(faintedMons) do
        push_event({
          type = "poison_faint",
          name = fainted.name,
          mon = fainted.mon,
          run = function(onDone)
            local Hud = require("src.ui.game3.hud")
            -- pokefirered/src/field_poison.c:64
            local P = require("src.core.game3.profile").forSession(session)
            Hud.openMessage(game, RomText.box((P.field and P.field.poisonFaintText) or "gText_PkmnFainted3",
              { stringVars = { fainted.name } }),
              { done = onDone })
          end,
        })
      end
      -- pokefirered/src/field_poison.c:76
      if poisonFainted and not poisonScript then push_event(field_white_out_event(session, game)) end
    end
  end
  session.vars[psnVar] = psnSteps
  session.poisonSteps = psnSteps
  -- pokeemerald/src/field_control_avatar.c:552
  if poisonFainted then return true end

  -- pokefirered/src/field_control_avatar.c:670 ShouldEggHatch
  if not forced then
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
          local P = require("src.core.game3.profile").forSession(session)
          -- pokefirered/data/scripts/day_care.inc:112 DayCare_Text_Huh
          Hud.openMessage(game, RomText.box((P.field and P.field.eggHatchText) or "DayCare_Text_Huh"), {
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
      return true
    end
    if isRse and require("src.core.game3.braille_field").shouldDoRegicePuzzle(session) then
      -- pokeemerald/src/field_control_avatar.c:570
      local Space = require("src.core.game3.scripting.space")
      local key = Space.scriptKey("IslandCave_EventScript_OpenRegiEntrance")
      if key and Space.startScript(key) then
        return true
      end
    end
    if mcOn and require("src.core.game3.rse.match_call").tryStepCountScripts(session, game) then
      -- pokeemerald/src/field_control_avatar.c:575
      return true
    end
  end

  -- pokefirered/src/safari_zone.c:60 CB2_EndSafariBattle
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.pollSafariBalls and Field.pollSafariBalls(game) then
    return true
  end

  -- pokefirered/src/field_control_avatar.c:677
  local okSafari, Safari = pcall(require, "src.core.game3.safari")
  if okSafari and Safari and Safari.takeStep and Safari.takeStep(session, game) then
    return true
  end

  if isRse and require("src.core.game3.special_scene_rse").countSSTidalStep(1) then
    -- pokeruby/src/field_control_avatar.c:593
    local Space = require("src.core.game3.scripting.space")
    local id = require("src.core.game3.profile").forSession(session).id
    local name = (id == "ruby" or id == "sapphire") and "gUnknown_0815FD0D"
      or "SSTidalCorridor_EventScript_ReachedStepCount"
    local key = Space.scriptKey(name)
    if key and Space.startScript(key) then
      return true
    end
  end

  if mcOn and require("src.core.game3.rse.match_call").tryStartMatchCall(session, game) then
    -- pokeemerald/src/field_control_avatar.c:605
    return true
  end

  -- pokeemerald/src/field_control_avatar.c:494
  return StepEvents.onRepelStep(session, game)
end

function StepEvents.onRepelStep(session, game)
  -- 5. Repel Step Counter (VAR_REPEL_STEP_COUNT)
  local Pike = package.loaded["src.core.game3.rse.frontier.pike"]
  local Py = package.loaded["src.core.game3.rse.frontier.pyramid"]
  -- pokeemerald/src/wild_encounter.c:854
  if (Pike and Pike.inBattlePike(session)) or (Py and Py.inPyramid(session)) then return false end
  local repelSteps = tonumber(Sem.getVar(session, "repelSteps")) or 0
  if repelSteps > 0 then
    repelSteps = repelSteps - 1
    session.repelSteps = repelSteps
    Sem.setVar(session, "repelSteps", repelSteps)

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
      return true
    end
  end
  return false
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
