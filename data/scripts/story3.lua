-- Third batch of hand-ported events: fishing rod givers, the Marowak
-- ghost, elevators, the Game Corner coins/prizes, the SS Anne departure
-- and the Hall of Fame record.  Each cites its pokered source.

local Runtime = require("src.mods.Runtime")

local M = {}

-- -------------------------------------------------------------------
-- Fishing rod givers (scripts/VermilionOldRodHouse.asm,
-- FuchsiaGoodRodHouse.asm, Route12SuperRodHouse.asm)
-- -------------------------------------------------------------------

-- refusedText is the .ThatsSoDisappointingText tail on NO; followText is
-- the second half of the received chain (scripts/VermilionOldRodHouse.asm:45)
local function rodGiver(askText, receivedText, afterText, rodItem, flag,
                        refusedText, followText)
  local rows = {
    { "face_player" },
    { "check_flag", flag },
    { "jump_if_true", "already_got" },
    { "ask", askText },
    { "jump_if_false", "refused" },
    -- give-then-print like the three rod-house scripts (GiveItem fills
    -- wStringBuffer; the received texts read OLD/GOOD/SUPER ROD from it)
    { "give_item", rodItem, 1, false },
    { "set_flag", flag },
    { "show_text", receivedText },
  }
  if followText then rows[#rows + 1] = { "show_text", followText } end
  rows[#rows + 1] = { "jump", "end" }
  rows[#rows + 1] = { "label", "refused" }
  rows[#rows + 1] = { "show_text", refusedText }
  rows[#rows + 1] = { "jump", "end" }
  rows[#rows + 1] = { "label", "already_got" }
  rows[#rows + 1] = { "show_text", afterText }
  return rows
end

M.VERMILION_OLD_ROD_HOUSE = {
  talk = {
    TEXT_VERMILIONOLDRODHOUSE_FISHING_GURU = rodGiver(
      "_VermilionOldRodHouseFishingGuruDoYouLikeToFishText",
      "_VermilionOldRodHouseFishingGuruTakeThisText",
      "_VermilionOldRodHouseFishingGuruHowAreTheFishBitingText",
      "OLD_ROD", "EVENT_GOT_OLD_ROD",
      "_VermilionOldRodHouseFishingGuruThatsSoDisappointingText",
      "_VermilionOldRodHouseFishingGuruFishingIsAWayOfLifeText"),
  },
}

M.FUCHSIA_GOOD_ROD_HOUSE = {
  talk = {
    TEXT_FUCHSIAGOODRODHOUSE_FISHING_GURU = rodGiver(
      "_FuchsiaGoodRodHouseFishingGuruText",
      "_FuchsiaGoodRodHouseFishingGuruReceivedGoodRodText",
      "_FuchsiaGoodRodHouseFishingGuruHowAreTheFishText",
      "GOOD_ROD", "EVENT_GOT_GOOD_ROD",
      "_FuchsiaGoodRodHouseFishingGuruThatsSoDisappointingText"),
  },
}

M.ROUTE_12_SUPER_ROD_HOUSE = {
  talk = {
    TEXT_ROUTE12SUPERRODHOUSE_FISHING_GURU = rodGiver(
      "_Route12SuperRodHouseFishingGuruDoYouLikeToFishText",
      "_Route12SuperRodHouseFishingGuruReceivedSuperRodText",
      "_Route12SuperRodHouseFishingGuruTryFishingText",
      "SUPER_ROD", "EVENT_GOT_SUPER_ROD",
      "_Route12SuperRodHouseFishingGuruThatsDisappointingText",
      "_Route12SuperRodHouseFishingGuruFishingWayOfLifeText"),
  },
}

-- -------------------------------------------------------------------
-- Pokemon Tower 5F purified zone (scripts/PokemonTower5F.asm
-- PokemonTower5FDefaultScript): the 2x2 center pad heals the party once
-- per visit.  EVENT_IN_PURIFIED_ZONE latches until the player steps off;
-- while on the pad the map script also sets BIT_NO_BATTLES (we return
-- true from onStep so wild encounters are skipped the same way).
-- -------------------------------------------------------------------

local TOWER_5F_PURIFIED = {
  [10 * 256 + 8] = true, [11 * 256 + 8] = true,
  [10 * 256 + 9] = true, [11 * 256 + 9] = true,
}

-- HealParty -> GBFadeOutToWhite -> Delay3 -> Delay3 -> GBFadeInFromWhite
-- -> TEXT_POKEMONTOWER5F_PURIFIEDZONE (no Music_PkmnHealed).
local TOWER_5F_HEAL = {
  { "heal_party" },
  { "fade", "out", "white" },
  { "wait", 3 },
  { "wait", 3 },
  { "fade", "in", "white" },
  { "show_text", "_PokemonTower5FPurifiedZoneText" },
}

M.POKEMON_TOWER_5F = {
  onStep = function(game, ow, x, y)
    if not TOWER_5F_PURIFIED[x * 256 + y] then
      game.save.flags.EVENT_IN_PURIFIED_ZONE = nil
      return false
    end
    if game.save.flags.EVENT_IN_PURIFIED_ZONE then
      return true
    end
    if ow.runner and ow.runner:isRunning() then return false end
    game.save.flags.EVENT_IN_PURIFIED_ZONE = true
    if ow.runner then
      ow.runner:run(TOWER_5F_HEAL)
    elseif ow.queueScript then
      ow:queueScript(TOWER_5F_HEAL)
    end
    return true
  end,
}

-- -------------------------------------------------------------------
-- The ghost Marowak (scripts/PokemonTower6F.asm): blocks the stairs at
-- (10,16) until defeated.
--
-- PokemonTower6FDefaultScript starts the RESTLESS SOUL battle with NO
-- Silph Scope check at the trigger -- the scope only decides whether the
-- disguise sticks (IsGhostBattle -> makeGhost: "too scared to move", balls
-- dodged) or comes off in the unveil (makeUnveiledGhost, #492). An earlier
-- version of this port turned the player back
-- without the scope and never opened the battle, which made 6F
-- impassable on any route that skips Rocket Hideout; vanilla lets the
-- battle open and a POKE_DOLL end it (see wBattleResult below).
-- -------------------------------------------------------------------

M.POKEMON_TOWER_6F = {
  onStep = function(game, ow, x, y)
    if game.save.flags.EVENT_BEAT_GHOST_MAROWAK then return false end
    if x ~= 10 or y ~= 16 then return false end
    local TextBox = require("src.render.TextBox")
    local t = game.data.text
    game.stack:push(TextBox.new(game,
      t._PokemonTower6FBeGoneText or "Be gone...\nIntruders...", function()
      local BattleState = require("src.battle.BattleState")
      local battle = BattleState.newWild(game, "MAROWAK", 30)
      -- ItemUseBall .notOldManBattle (item_effects.asm:166-175): a ball
      -- thrown on POKEMON_TOWER_6F at the RESTLESS SOUL is dodged whether
      -- or not the scope revealed it, so the "can't be caught" state rides
      -- the battle instead of IsGhostBattle alone (#444)
      battle.noCatch = true
      -- InitWildBattle enters disguised for the RESTLESS SOUL either way
      -- (core.asm:6698-6700).  The scope does not skip the disguise, it
      -- buys the unveil PrintBeginningBattleText .isMarowak plays over it
      -- before the battle proceeds as an ordinary wild one (#492).
      if game.save.inventory.SILPH_SCOPE then
        battle:makeUnveiledGhost()
      else
        battle:makeGhost()
      end
      battle.onFinish = function(result)
        -- wBattleResult parity (PokemonTower6FMarowakBattleScript's
        -- "and a / jr nz"): losing writes $1 and running writes $2, but
        -- ItemUsePokeDoll ends the battle WITHOUT touching it, so the
        -- script reads 0 -- defeated. That is the famous Poke Doll
        -- trick, and the speedrun route this bot follows depends on it.
        if result == "win" or battle.pokeDollEscape then
          game.save.flags.EVENT_BEAT_GHOST_MAROWAK = true
          -- PokemonTower6FMarowakDepartedText (scripts/PokemonTower6F.asm)
          -- is two texts, not one: the CUBONE's-mother line first, then
          -- PlayCry RESTLESS_SOUL (EQU MAROWAK, constants/pokemon_constants
          -- .asm:209) + WaitForSoundToFinish + DelayFrames 30 before the
          -- calmed line; the port dropped the first text and the cry
          -- (#867).  text/PokemonTower6F.asm:1-5 (#1849)
          local rows = {
            { "play_cry", "MAROWAK" },
            { "show_text", t._PokemonTower6FGhostWasCubonesMotherText
              or "The GHOST was the\nrestless soul of\vCUBONE's mother!" },
            { "wait", 30 },
            { "show_text", t._PokemonTower6FSoulWasCalmedText
              or "The mother's soul\nwas calmed.\012It departed to\nthe afterlife!" },
          }
          if ow.runner then
            ow.runner:run(rows)
          elseif ow.queueScript then
            ow:queueScript(rows)
          end
        elseif result ~= "lose" then
          -- .did_not_defeat: one simulated step right, off the trigger,
          -- so fleeing does not leave you standing on a cell that
          -- immediately re-fires.
          ow:scriptMove(ow.player, "right", 1, nil, { collide = true })
        end
        ow:afterBattle(result, battle)
      end
      -- InitWildBattle runs the wipe before the disguise (core.asm:6695-6702)
      ow:pushBattle(battle)
    end))
    return true
  end,
}

-- -------------------------------------------------------------------
-- Elevators (scripts/SilphCoElevator.asm etc.): a floor menu built from
-- the maps whose warps lead to the elevator (fully data-driven).
--
-- engine/events/elevator.asm DisplayElevatorFloorMenu: prints the floor
-- list (SPECIALLISTMENU -- a plain text list, constants/list_constants
-- .asm:7, not a graphical panel) built from each elevator's fixed
-- FLOOR_* table (e.g. scripts/SilphCoElevator.asm SilphCoElevatorFloors,
-- ascending FLOOR_1F..FLOOR_11F); wCurrentMenuItem is explicitly zeroed
-- so the cursor always rests on the topmost floor -- there is no
-- current-floor marker/wWhichFloor symbol anywhere in Gen1.  Floor
-- labels are the short FLOOR_* item-name strings (data/items/names.asm:
-- 87-100 -- '1F'..'11F', 'B1F', 'B2F', 'B4F'), never the room/map name.
-- On B (`ret c`) nothing happens -- no warp, the player just stays put.
-- On A, the map script sees BIT_CUR_MAP_USED_ELEVATOR and runs
-- engine/overworld/elevator.asm ShakeElevator (src/world/ElevatorShake
-- .lua): the music stops, the BG scroll bounces -1/+1px for 100
-- two-frame cycles with SFX_COLLISION each cycle, then
-- SFX_SAFARI_ZONE_PA plays out and the map theme returns, before the
-- player is delivered to the chosen floor.
-- keyGate: the Rocket Hideout panel refuses without the LIFT KEY
-- (scripts/RocketHideoutElevator.asm RocketHideoutElevatorText:
-- "It appears to need a key." and no floor menu)
-- preFrames: the shake's lead-in delays -- ShakeElevator's own Delay3s
-- come to 9 frames; Silph/Rocket's ...ShakeScript prefixes another
-- Delay3 (12) while CeladonMartElevatorShakeScript farjps straight in
-- The panel is a bg_event, not a map-entry script: data/maps/objects/
-- CeladonMartElevator.asm has `bg_event 3, 0, TEXT_CELADONMARTELEVATOR`
-- and CeladonMartElevatorText is what runs DisplayElevatorFloorMenu, so
-- the menu waits for the player to face the panel and press A (#395).
-- Map entry only stores the car's exit warps (CeladonMartElevator
-- StoreWarpEntriesScript), which is elevatorSeedExit below.
-- After the ride the original does NOT jump-cut to the floor: choosing a
-- floor rewrites the elevator car's own warp entries (wWarpEntries, via
-- .UpdateWarp) to the chosen floor's exit warp and returns control, and
-- the player walks out of the car onto that warp themselves.

-- .UpdateWarp: point EVERY car exit warp at the same floor's elevator
-- door (warp id, map id).  Shared generated map data, but the car's
-- warps are only read from inside the car; rides rewrite them again.
local function elevatorSetExit(ow, floor)
  if not floor then return end
  for _, w in ipairs(ow.map.def.warps) do
    w.destMap = floor.map
    w.destWarp = floor.warpIdx
  end
end

local function elevatorFloors(elevatorMapId, game)
  local floors = {}
  for mapId, def in pairs(game.data.maps) do
    for i, w in ipairs(def.warps) do
      if w.destMap == elevatorMapId then
        -- short floor token pokered actually prints, e.g.
        -- SILPH_CO_10F -> "10F", ROCKET_HIDEOUT_B2F -> "B2F"
        local token = mapId:match("_([^_]+)$") or mapId
        -- warpIdx: this floor's warp back into the elevator IS the
        -- warp the car's rewritten exit lands on (the reciprocal
        -- pair), matching wElevatorWarpMaps' (warp id, map id)
        table.insert(floors,
          { map = mapId, x = w.x, y = w.y, token = token, warpIdx = i })
        break
      end
    end
  end
  -- numeric floor order (SilphCoElevatorFloors' FLOOR_1F..FLOOR_11F),
  -- not lexicographic -- otherwise 10F/11F sort before 2F..9F
  table.sort(floors, function(a, b)
    return (tonumber(a.token:match("%d+")) or 0) <
           (tonumber(b.token:match("%d+")) or 0)
  end)
  return floors
end

local function elevatorSeedExit(ow, floors, fromMapId)
  -- Seed a walk-out destination on entry (before the panel is ever
  -- read): entry floor when known, else the first listed floor (1F).
  -- Choosing a floor rewrites it again; B-cancel / no-key leave
  -- keeps this seed so walking out of the car cannot hit a missing ROM
  -- placeholder (#123) or the car's static default floor (#90: Rocket
  -- Hideout defaults to B1F even when entered from B2F/B4F).
  local exitFloor = floors[1]
  if fromMapId then
    for _, f in ipairs(floors) do
      if f.map == fromMapId then exitFloor = f break end
    end
  end
  elevatorSetExit(ow, exitFloor)
  return exitFloor
end

local function elevator(elevatorMapId, panelText, keyGate, preFrames)
  -- the panel bg_event: DisplayElevatorFloorMenu runs from this text
  -- script, never from map entry (#395)
  local function panel(game, ow, npc, done)
    done = done or function() end
    local floors = elevatorFloors(elevatorMapId, game)
    -- Rocket Hideout: without LIFT_KEY the panel only prints the need-
    -- a-key line and shows no floor menu
    -- (scripts/RocketHideoutElevator.asm).
    if keyGate and not game.save.inventory[keyGate.item] then
      local TextBox = require("src.render.TextBox")
      game.stack:push(TextBox.new(game,
        game.data.text[keyGate.text] or "It appears to\nneed a key.", done))
      return
    end
    local items = {}
    for _, f in ipairs(floors) do
      table.insert(items, { label = f.token, value = f })
    end
    -- (home/list_menu.asm:105-110, 371-372, 524-525)
    local Strings = require("src.core.Strings")
    items[#items + 1] = { cancel = true, label = Strings("CANCEL") }
    -- (engine/events/elevator.asm:2-3, data/text_boxes.asm:13)
    local prompt
    local function closePrompt()
      if prompt and game.stack:top() == prompt then game.stack:pop() end
      prompt = nil
    end
    local function openList()
      local ListMenu = require("src.ui.ListMenu")
      game.stack:push(ListMenu.new(game, nil, items, {
        kind = "elevator_floors",
        itemBox = true,
        onChoose = function(item, list)
          list:close()
          closePrompt()
          if item.cancel then
            done()
            return
          end
          local ElevatorShake = require("src.world.ElevatorShake")
          game.stack:push(ElevatorShake.new(game, ow, {
            preFrames = preFrames,
            onDone = function()
              elevatorSetExit(ow, item.value)
              done()
            end,
          }))
        end,
        onCancel = function()
          closePrompt()
          done()
        end,
      }))
    end
    local TextBox = require("src.render.TextBox")
    prompt = TextBox.new(game,
      game.data.text._WhichFloorText or "Which floor do\nyou want? ", nil, {
        -- pokeyellow/engine/events/elevator.asm:1-8 sets BIT_NO_TEXT_DELAY
        instant = require("src.core.GameVersion").isYellow(),
        stay = { onShown = openList },
      })
    game.stack:push(prompt)
  end
  return {
    -- fromMapId: the floor the player just left (setMap passes it), so a
    -- B-cancel can still walk out onto a real map.  Silph's ROM car warps
    -- default to UNUSED_MAP_ED, which is not in Data.maps -- Warp.resolve
    -- asserted and hard-crashed (#123).
    onEnter = function(game, ow, fromMapId)
      elevatorSeedExit(ow, elevatorFloors(elevatorMapId, game), fromMapId)
    end,
    talk = { [panelText] = panel },
  }
end

M.SILPH_CO_ELEVATOR = elevator("SILPH_CO_ELEVATOR",
  "TEXT_SILPHCOELEVATOR_ELEVATOR")
M.CELADON_MART_ELEVATOR = elevator("CELADON_MART_ELEVATOR",
  "TEXT_CELADONMARTELEVATOR", nil, 9)
M.ROCKET_HIDEOUT_ELEVATOR = elevator("ROCKET_HIDEOUT_ELEVATOR",
  "TEXT_ROCKETHIDEOUTELEVATOR",
  { item = "LIFT_KEY", text = "_RocketHideoutElevatorAppearsToNeedKeyText" })

-- -------------------------------------------------------------------
-- Rocket Hideout B4F (scripts/RocketHideoutB4F.asm):
--   Rocket3's after-battle text_asm drops the LIFT KEY item ball
--   (CheckAndSetEvent EVENT_ROCKET_DROPPED_LIFT_KEY / ShowObject
--   TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_5).  Both start hidden in the map
--   objects; without this talk side-effect the key never appears (#90,
--   #105).
--   Giovanni's post-battle script likewise ShowObject's the Silph Scope
--   after the hope-we-meet-again line (TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_4).
-- -------------------------------------------------------------------

M.ROCKET_HIDEOUT_B4F = {
  talk = {
    TEXT_ROCKETHIDEOUTB4F_ROCKET3 = function(game, ow, npc, done)
      if not ow:trainerDefeated(npc) then
        ow:engageTrainer(npc, done)
        return
      end
      local TextBox = require("src.render.TextBox")
      local t = game.data.text
      game.stack:push(TextBox.new(game,
        t._RocketHideoutB4FRocket3AfterBattleText
        or "Oh no! I dropped\nthe LIFT KEY!",
        function()
          -- CheckAndSetEvent EVENT_ROCKET_DROPPED_LIFT_KEY: first talk
          -- after the win reveals the ball; later talks only reprint.
          if not game.save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY then
            game.save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY = true
            local Commands = require("src.script.Commands")
            Commands.show_object(
              { game = game, save = game.save, overworld = ow },
              "ROCKET_HIDEOUT_B4F", "ROCKETHIDEOUTB4F_LIFT_KEY")
          end
          done()
        end))
    end,

    -- Yellow swaps Rocket1/Rocket2 for Jessie & James and keeps a single
    -- grunt, spelled ROCKETHIDEOUTB4F_ROCKET / TEXT_ROCKETHIDEOUTB4F_ROCKET
    -- (pokeyellow/scripts/RocketHideoutB4F.asm), so the Red/Blue key above
    -- never matched there and the LIFT KEY never dropped (#552, a
    -- regression of #105).  Yellow also moves the drop off the second
    -- talk: RocketHideoutB4FRocketEndBattleText is text_promptbutton +
    -- text_asm, so its SetEvent EVENT_ROCKET_DROPPED_LIFT_KEY / ShowObject
    -- TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_5 run the instant the battle ends.
    TEXT_ROCKETHIDEOUTB4F_ROCKET = function(game, ow, npc, done)
      if not ow:trainerDefeated(npc) then
        ow:engageTrainer(npc, function()
          -- engageTrainer records the win before it calls back, so this
          -- is the end-battle text's SetEvent + ShowObject
          if ow:trainerDefeated(npc)
             and not game.save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY then
            game.save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY = true
            local Commands = require("src.script.Commands")
            Commands.show_object(
              { game = game, save = game.save, overworld = ow },
              "ROCKET_HIDEOUT_B4F", "ROCKETHIDEOUTB4F_LIFT_KEY")
          end
          done()
        end)
        return
      end
      -- RocketHideoutB4FRocketAfterBattleText: later talks only reprint
      local TextBox = require("src.render.TextBox")
      game.stack:push(TextBox.new(game,
        game.data.text._RocketHideoutB4FRocketAfterBattleText
        or "Oh no! I dropped\nthe LIFT KEY!", done))
    end,

    TEXT_ROCKETHIDEOUTB4F_GIOVANNI = function(game, ow, npc, done)
      -- Giovanni has no trainer-header row (def_trainers 2); his text_asm
      -- owns both the engage and the BeatGiovanniScript aftermath.
      if ow:trainerDefeated(npc)
         or game.save.flags.EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI then
        local TextBox = require("src.render.TextBox")
        game.stack:push(TextBox.new(game,
          game.data.text._RocketHideoutB4FGiovanniHopeWeMeetAgainText
          or "I hope we meet\nagain...", done))
        return
      end
      local TextBox = require("src.render.TextBox")
      local BattleState = require("src.battle.BattleState")
      local t = game.data.text
      local impressed = t._RocketHideoutB4FGiovanniImpressedYouGotHereText
                        or "So! I must say, I\nam impressed you\ngot here!"
      local cannotBe = t._RocketHideoutB4FGiovanniWhatCannotBeText
                       or "WHAT!\nThis cannot be!"
      local hope = t._RocketHideoutB4FGiovanniHopeWeMeetAgainText
                   or "I hope we meet\nagain..."
      game.stack:push(TextBox.new(game, impressed, function()
        local battle = BattleState.newTrainer(game, "OPP_GIOVANNI", 1)
        -- SaveEndBattleTextPointers (scripts/RocketHideoutB4F.asm:99-120):
        -- PrintEndBattleText prints it on the battle screen (#1817)
        battle.endBattleText = TextBox.substitute(game, cannotBe)
        battle.onFinish = function(result)
          if result ~= "win" then
            ow:afterBattle(result, battle)
            done()
            return
          end
          game.save.defeatedTrainers[npc.id] = true
          game.save.flags.EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI = true
          -- BeatGiovanniScript (scripts/RocketHideoutB4F.asm)
          game.stack:push(TextBox.new(game, hope, function()
            local Transition = require("src.render.Transition")
            game.stack:push(Transition.new(game, function()
              local Commands = require("src.script.Commands")
              local ctx = { game = game, save = game.save, overworld = ow }
              Commands.hide_object(ctx, "ROCKET_HIDEOUT_B4F",
                "ROCKETHIDEOUTB4F_GIOVANNI")
              Commands.show_object(ctx, "ROCKET_HIDEOUT_B4F",
                "ROCKETHIDEOUTB4F_SILPH_SCOPE")
            end, function()
              ow:afterBattle(result, battle)
              done()
            end))
          end))
        end
        ow:pushBattle(battle)
      end))
    end,
  },
}

-- -------------------------------------------------------------------
-- Game Corner coins, prizes, and the rocket-poster switch that reveals
-- the hideout stairs (scripts/GameCorner.asm, data/events/prizes.asm +
-- prize_mon_levels.asm)
-- -------------------------------------------------------------------

M.GAME_CORNER = {
  -- the hideout stairs hide behind a wall block until the poster
  -- switch is found (the block at (8,2) is $2a while
  -- EVENT_FOUND_ROCKET_HIDEOUT is unset, $43 after)
  onEnter = function(game, ow)
    local poster = game.data.field.gameCornerPoster
    if poster then
      local block = game.save.flags[poster.event] and poster.openBlock
                    or poster.closedBlock
      ow:replaceBlock(poster.x, poster.y, block)
    end
    -- pick this visit's lucky slot machine
    -- (wLuckySlotHiddenEventIndex, engine/slots/game_corner_slots2.asm)
    local seats = game.data.field.slotMachines.GAME_CORNER
    ow.luckySlot = love.math.random(1, #seats)
    -- #131: pre-#50 saves beat the poster grunt (defeatedTrainers) but
    -- never hid him; clear the tile if he is already marked defeated
    local rocketId = "GAME_CORNER_obj_11"
    if game.save.defeatedTrainers and game.save.defeatedTrainers[rocketId] then
      local Commands = require("src.script.Commands")
      Commands.hide_object({ game = game, save = game.save, overworld = ow },
                           "GAME_CORNER", "GAMECORNER_ROCKET")
    end
  end,
  talk = {
    -- the poster bg event: pressing A reveals the hidden switch
    TEXT_GAMECORNER_POSTER = function(game, ow, npc, done)
      local TextBox = require("src.render.TextBox")
      local poster = game.data.field.gameCornerPoster
      local t = game.data.text
      local text = t._GameCornerPosterSwitchBehindPosterText
                   or "Hey!\fA switch behind\nthe poster!?\nLet's push it!"
      if game.save.flags[poster.event] then
        game.stack:push(TextBox.new(game, text, done))
        return
      end
      -- GameCornerPosterText: the SwitchBehindPosterText plays
      -- SFX_SWITCH as it shows, then SFX_GO_INSIDE opens the stairs
      require("src.core.Sound").play(game.data, "Switch")
      game.stack:push(TextBox.new(game, text, function()
        game.save.flags[poster.event] = true
        require("src.core.Sound").play(game.data, "Go_Inside")
        ow:replaceBlock(poster.x, poster.y, poster.openBlock)
        done()
      end))
    end,
    -- the grunt guarding the poster (GameCornerRocketText /
    -- GameCornerRocketBattleScript / GameCornerRocketExitScript): after
    -- losing he warns the BOSS and leaves the floor for good, freeing
    -- the tile in front of the hideout switch
    TEXT_GAMECORNER_ROCKET = function(game, ow, npc, done)
      local Commands = require("src.script.Commands")
      local function hideRocket()
        Commands.hide_object({ game = game, save = game.save,
                               overworld = ow },
                             "GAME_CORNER", "GAMECORNER_ROCKET")
      end
      -- already beaten: hide anyway so pre-#50 saves that only have
      -- defeatedTrainers (no objectToggles hide) clear the poster tile
      if ow:trainerDefeated(npc) then
        hideRocket()
        done()
        return
      end
      -- GameCornerRocketText hands the battle its own loss line through
      -- SaveEndBattleTextPointers (.BattleEndText ->
      -- _GameCornerRocketBattleEndText, "Dang!"), and PrintEndBattleText
      -- prints it ON the battle screen between TrainerDefeatedText and
      -- MoneyForWinningText (engine/battle/core.asm TrainerBattleVictory).
      -- He is a text_asm trainer with no def_trainers header, so there is no
      -- header.won for engageTrainer to find and the line has to be handed
      -- over here or it never shows at all (#862).
      ow:engageTrainer(npc, function()
        if not ow:trainerDefeated(npc) then
          done()
          return
        end
        local TextBox = require("src.render.TextBox")
        game.stack:push(TextBox.new(game,
          game.data.text._GameCornerRocketAfterBattleText
          or "Our hideout might\nbe discovered! I\nbetter tell BOSS!",
          function()
            -- #198/#862: GameCornerRocketBattleScript (scripts/GameCorner.asm)
            -- picks the exit walk from where the player is standing, because
            -- the grunt on (9,5) has to get past him: wYCoord == 6 (talked to
            -- from the south) or wXCoord == 8 (from the west) leaves the row
            -- clear and takes GameCornerMovement_Rocket_WalkDirect, five steps
            -- RIGHT; otherwise the player is east of him on (10,5) and
            -- GameCornerMovement_Rocket_WalkAroundPlayer steps DOWN, right, UP
            -- and right again to go AROUND him.  pokeyellow's copy of the
            -- around-path takes one extra RIGHT on the lower row before coming
            -- back up (it also has to clear Pikachu); both versions end on
            -- (15,5).  He never steps UP: (9,4) is the poster wall, which is
            -- where the old single UP step sent him.
            local px = ow.player and ow.player.cellX
            local py = ow.player and ow.player.cellY
            local path
            if py == 6 or px == 8 then
              path = { { "right", 5 } }
            elseif require("src.core.GameVersion").isYellow() then
              path = { { "down", 1 }, { "right", 3 }, { "up", 1 }, { "right", 3 } }
            else
              path = { { "down", 1 }, { "right", 2 }, { "up", 1 }, { "right", 4 } }
            end
            -- GameCornerRocketExitScript only HideObjects him once
            -- BIT_SCRIPTED_NPC_MOVEMENT clears, i.e. after the last step.
            -- scriptMove locks player input (#scriptMoves>0) and ignores
            -- collision, so the despawn + unfreeze (done) ride the final step.
            local function step(i)
              if i > #path then
                hideRocket()
                done()
                return
              end
              ow:scriptMove(npc, path[i][1], path[i][2],
                            function() step(i + 1) end)
            end
            step(1)
          end))
      end, game.data.text._GameCornerRocketBattleEndText or "Dang!")
    end,
    -- GameCornerClerk1Text (scripts/GameCorner.asm): the offer, a
    -- YesNoChoice, then ¥1000 for 50 coins.  Yellow drops the "1" from the
    -- object const and from every one of his text labels
    -- (GameCornerClerkText, pokeyellow/scripts/GameCorner.asm) with an
    -- identical body, so each line resolves under both spellings and the
    -- handler is bound to both text ids just below (#552).
    TEXT_GAMECORNER_CLERK1 = function(game, ow, npc, done)
      local TextBox = require("src.render.TextBox")
      local Font = require("src.render.Font")
      local Strings = require("src.core.Strings")
      local t = game.data.text
      local function line(suffix, fallback)
        return t["_GameCornerClerk1" .. suffix]
               or t["_GameCornerClerk" .. suffix]
               or fallback
      end
      -- GameCornerDrawCoinBox (scripts/GameCorner.asm; pokeyellow's copy is
      -- identical): TextBoxBorder at hlcoord 11,0 with b=5 c=7, a 9x7-tile
      -- window in the top right holding MONEY at (12,2) over the amount on
      -- row 3 and COIN at (12,4) over the count on row 5.  Both
      -- PrintBCDNumber calls pass LEADING_ZEROES, whose bit 7 SUPPRESSES
      -- leading zeroes (home/print_bcd.asm), and neither passes LEFT_ALIGN,
      -- so both numbers read plain and right-aligned against the inner edge
      -- at column 18.  The asm draws the box before the offer and redraws it
      -- after the purchase, so it stands for the whole exchange: a draw-only
      -- state under the dialogue gets that lifetime, since StateStack draws
      -- every state above the last opaque one and updates only the top
      -- (src/core/StateStack.lua), and reading save each frame is the
      -- redraw (#624).
      local coinBox = { draw = function()
        Font.drawBox(11, 0, 9, 7)
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw(Strings("MONEY"), 96, 16)
        local money = ("¥%d"):format(game.save.money or 0)
        Font.draw(money, 152 - Font.width(money), 24)
        Font.draw(Strings("COIN"), 96, 32)
        local coins = ("%d"):format(game.save.coins or 0)
        Font.draw(coins, 152 - Font.width(coins), 40)
        love.graphics.setColor(1, 1, 1, 1)
      end }
      game.stack:push(coinBox)
      -- Every branch below finishes here.  A TextBox pops itself before its
      -- onDone runs, so the coin box is top of the stack again by then and
      -- this pop takes it down, never someone else's state.
      local function finish()
        game.stack:pop()
        done()
      end
      -- YesNoChoice is called with the offer still printed, so the prompt
      -- has to ride the open text box (opts.choice) instead of being pushed
      -- after it closes, which is what made the question vanish (#624).
      game.stack:push(TextBox.new(game,
        line("DoYouNeedSomeGameCoinsText",
             "Do you need some\ngame coins?\f¥1000 for 50."),
        nil, { choice = function(yes)
          if not yes then
            game.stack:push(TextBox.new(game,
              line("PleaseComePlaySometimeText",
                   "No? Please come\nplay sometime!"), finish))
            return
          end
          -- scripts/GameCorner.asm GameCornerClerk1Text: coins need
          -- the COIN CASE and room for at least 9 coins (Has9990Coins)
          if not game.save.inventory.COIN_CASE then
            game.stack:push(TextBox.new(game,
              line("DontHaveCoinCaseText",
                   "You don't have a\nCOIN CASE!"), finish))
            return
          end
          if (game.save.coins or 0) >= 9990 then
            game.stack:push(TextBox.new(game,
              line("CoinCaseIsFullText",
                   "Oops! Your COIN\nCASE is full."), finish))
            return
          end
          if game.save.money < 1000 then
            game.stack:push(TextBox.new(game,
              line("CantAffordTheCoinsText",
                   "You can't afford\nthe coins!"), finish))
            return
          end
          game.save.money = game.save.money - 1000
          game.save.coins = math.min(9999, (game.save.coins or 0) + 50)
          -- the thanks text is the plain _GameCornerClerk1ThanksHereAre50-
          -- CoinsText; the new count belongs in the coin box the asm
          -- redraws here, not appended to the line (#624)
          game.stack:push(TextBox.new(game,
            line("ThanksHereAre50CoinsText",
                 "Thanks! Here are\nyour 50 coins!"), finish))
        end }))
    end,
  },
}

-- Yellow's coin clerk is GAMECORNER_CLERK / TEXT_GAMECORNER_CLERK where Red
-- and Blue spell him CLERK1, and the two text_asm bodies are identical, so
-- one handler answers both ids.  Without the alias the Yellow clerk fell
-- through to his extracted offer line with no yes/no box behind it (#552).
M.GAME_CORNER.talk.TEXT_GAMECORNER_CLERK =
  M.GAME_CORNER.talk.TEXT_GAMECORNER_CLERK1

-- Game Corner prize lists (data/events/prizes.asm, prize_mon_levels.asm).
-- Each counter owns ONE window of three prizes, not the whole catalogue:
-- GetPrizeMenuId (engine/events/prize_menu.asm) subtracts
-- TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_1 from hTextID and indexes
-- PrizeDifferentMenuPtrs with the result, so vendor 1 sells
-- PrizeMenuMon1Entries, vendor 2 PrizeMenuMon2Entries and vendor 3
-- PrizeMenuTMsEntries (#623).  The mon windows and their levels differ per
-- version; the TM window is identical in all three, so it is shared.
local PRIZE_TMS = {
  { kind = "item", item = "TM_DRAGON_RAGE", cost = 3300 },
  { kind = "item", item = "TM_HYPER_BEAM", cost = 5500 },
  { kind = "item", item = "TM_SUBSTITUTE", cost = 7700 },
}
local RED_PRIZE_WINDOWS = {
  {
    { kind = "mon", species = "ABRA", level = 9, cost = 180 },
    { kind = "mon", species = "CLEFAIRY", level = 8, cost = 500 },
    { kind = "mon", species = "NIDORINA", level = 17, cost = 1200 },
  },
  {
    { kind = "mon", species = "DRATINI", level = 18, cost = 2800 },
    { kind = "mon", species = "SCYTHER", level = 25, cost = 5500 },
    { kind = "mon", species = "PORYGON", level = 26, cost = 9999 },
  },
  PRIZE_TMS,
}
local BLUE_PRIZE_WINDOWS = {
  {
    { kind = "mon", species = "ABRA", level = 6, cost = 120 },
    { kind = "mon", species = "CLEFAIRY", level = 12, cost = 750 },
    { kind = "mon", species = "NIDORINO", level = 17, cost = 1200 },
  },
  {
    { kind = "mon", species = "PINSIR", level = 20, cost = 2500 },
    { kind = "mon", species = "DRATINI", level = 24, cost = 4600 },
    { kind = "mon", species = "PORYGON", level = 18, cost = 6500 },
  },
  PRIZE_TMS,
}
-- Yellow keeps the three windows but restocks both mon counters
-- (pokeyellow/data/events/prizes.asm, prize_mon_levels.asm)
local YELLOW_PRIZE_WINDOWS = {
  {
    { kind = "mon", species = "ABRA", level = 15, cost = 230 },
    { kind = "mon", species = "VULPIX", level = 18, cost = 1000 },
    { kind = "mon", species = "WIGGLYTUFF", level = 22, cost = 2680 },
  },
  {
    { kind = "mon", species = "SCYTHER", level = 30, cost = 6500 },
    { kind = "mon", species = "PINSIR", level = 30, cost = 6500 },
    { kind = "mon", species = "PORYGON", level = 26, cost = 9999 },
  },
  PRIZE_TMS,
}

local function prizeWindow(n)
  local GameVersion = require("src.core.GameVersion")
  local windows = RED_PRIZE_WINDOWS
  if GameVersion.isBlue() then
    windows = BLUE_PRIZE_WINDOWS
  elseif GameVersion.isYellow() then
    windows = YELLOW_PRIZE_WINDOWS
  end
  return windows[n]
end

-- Prize counters (engine/events/prize_menu.asm CeladonPrizeMenu; the prize
-- list itself is data/events/prizes.asm, prize_mon_levels.asm).  Gen1 gates
-- the prize window on the COIN CASE: it does IsItemInBag COIN_CASE first, and
-- with no case prints RequireCoinCaseText and returns without ever opening a
-- window; only with the case does it print ExchangeCoinsForPrizesText and then
-- show the prizes.  #194: the port used to open the window unconditionally and
-- skip both text boxes.  wMaxMenuItem is 3, i.e. this window's three prizes
-- plus the NO THANKS row, and HandlePrizeChoice confirms the pick with
-- SoYouWantPrizeText + YesNoChoice before any coins move; every branch then
-- rets out of CeladonPrizeMenu, so one transaction ends the conversation and
-- buying again means talking to the counter again (#623).
local function prizeCounter(window)
  return function(game, ow, npc, done)
    local PrizeCounter = require("src.ui.PrizeCounter")
    local TextBox = require("src.render.TextBox")
    local t = game.data.text
    -- IsItemInBag COIN_CASE: without the case, deny and open no window
    -- (COIN_CASE is a numeric count in save.inventory, nil when absent).
    if not game.save.inventory.COIN_CASE then
      game.stack:push(TextBox.new(game,
        t._RequireCoinCaseText or "A COIN CASE is\nrequired!", done))
      return
    end
    game.stack:push(TextBox.new(game,
      t._ExchangeCoinsForPrizesText or "We exchange your\ncoins for prizes.",
      function()
        local rows = {}
        for _, p in ipairs(prizeWindow(window)) do
          rows[#rows + 1] = {
            name = (p.kind == "mon")
                   and game.data.pokemon[p.species].name
                   or game.data.items[p.item].name,
            cost = p.cost,
            prize = p,
          }
        end
        local whichBox, menu
        local function close()
          local st = game.stack
          while st:top() == menu or st:top() == whichBox do st:pop() end
        end
        -- engine/events/prize_menu.asm:42
        local function endTalk()
          if ow then ow.prizeWindow = nil end
          done()
        end
        local function finish(msg)
          game.stack:push(TextBox.new(game, msg, endTalk))
        end
        local function buy(p)
          if (game.save.coins or 0) < p.cost then
            finish(t._SorryNeedMoreCoinsText or "Sorry, you need\nmore coins.")
            return
          end
          -- HasEnoughCoins passed, so hand the prize over first and only
          -- subtract once it landed: the asm rets before .subtractCoins when
          -- the bag is full, or when both the party and every box are full
          if p.kind == "mon" then
            -- engine/events/prize_menu.asm:217-243
            ow.runner:run({
              { "give_pokemon", p.species, p.level, false, true },
              { "jump_if_false", "boxfull" },
              { "take_coins", p.cost },
              { "jump", "out" },
              { "label", "boxfull" },
              -- engine/events/give_pokemon.asm:40-42
              { "show_text", "_BoxIsFullText" },
              { "label", "out" },
            }, { onDone = endTalk })
            return
          end
          if not require("src.inventory.Bag").add(
              game.save, p.item, 1, game.data) then
            -- engine/events/prize_menu.asm:245-246
            finish(t._OopsYouDontHaveEnoughRoomText
                   or "Oops! You don't\nhave enough room.")
            return
          end
          game.save.coins = game.save.coins - p.cost
          -- no thank-you line: HereYouGoText is unreferenced in the asm,
          -- which just redraws the coin box (PrintPrizePrice) and returns
          endTalk()
        end
        whichBox = TextBox.new(game,
          t._WhichPrizeText or "Which prize do\nyou want?", nil, {
            instant = true,
            stay = { onShown = function()
              menu = PrizeCounter.new(game, rows, {
                onCancel = function()
                  close()
                  done()
                end,
                onPick = function(row, idx)
                  local p = row.prize
                  if ow then
                    ow.prizeWindow = { prizes = rows, index = idx }
                  end
                  close()
                  local ask = (t._SoYouWantPrizeText
                               or "So, you want\n{RAM:wNameBuffer}?")
                              :gsub("{RAM:wNameBuffer}", row.name)
                  game.stack:push(TextBox.new(game, ask, nil, {
                    instant = true,
                    choice = function(yes)
                      if not yes then
                        finish(t._OhFineThenText or "Oh, fine then.")
                        return
                      end
                      buy(p)
                    end,
                  }))
                end,
              })
              game.stack:push(menu)
            end },
          })
        game.stack:push(whichBox)
      end, { instant = true }))
  end
end

M.GAME_CORNER_PRIZE_ROOM = {
  talk = { -- the three prize counters are bg events, one window each
    TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_1 = prizeCounter(1),
    TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_2 = prizeCounter(2),
    TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_3 = prizeCounter(3),
  },
}

-- -------------------------------------------------------------------
-- SS Anne departure (scripts/VermilionDock.asm): once HM01 is in hand
-- and the player steps off the dock, the ship sets sail.
-- -------------------------------------------------------------------

-- the ship's hull/deck blocks (block cols 5-8, rows 1-2) and the water
-- that replaces them once she sails (the surrounding blocks of each row)
local DOCK_SHIP_BLOCKS = {
  { bx = 5, by = 1, water = 1 }, { bx = 6, by = 1, water = 1 },
  { bx = 7, by = 1, water = 1 }, { bx = 8, by = 1, water = 1 },
  { bx = 5, by = 2, water = 13 }, { bx = 6, by = 2, water = 13 },
  { bx = 7, by = 2, water = 13 }, { bx = 8, by = 2, water = 13 },
}

M.VERMILION_DOCK = {
  onEnter = function(game, ow)
    local Flags = require("src.script.Flags")
    local f = game.save.flags
    if Flags.get(game.save, "EVENT_SS_ANNE_LEFT") then
      -- the ship is long gone: erase her right away, and anyone who
      -- still lands here is sent back out past the guard unless a mod
      -- explicitly permits this occupied map state.  This hook surrounds
      -- only the ejection decision; map-script registration and dispatch
      -- stay unchanged, and the departed ship remains erased.
      for _, b in ipairs(DOCK_SHIP_BLOCKS) do
        ow.map:setBlock(b.bx, b.by, b.water)
      end
      ow.map.renderer:rebuild()
      local occupancyAllowed = false
      if Runtime.wantsHook("map.occupancy_allowed") then
        local player = ow.player or {}
        occupancyAllowed = Runtime.call("map.occupancy_allowed",
          function() return false end, game, {
            mapId = "VERMILION_DOCK",
            reason = "ss_anne_departed",
            gameVersion = game.save and game.save.version,
            x = player.cellX,
            y = player.cellY,
          }) == true
      end
      if not occupancyAllowed then
        local TextBox = require("src.render.TextBox")
        game.stack:push(TextBox.new(game,
          game.data.text._VermilionCitySailor1ShipSetSailText
          or "The ship set sail.", function()
          ow:startWarpTo("VERMILION_CITY", 18, 29, "up")
        end))
      end
    elseif f.EVENT_GOT_HM01 and ow.player.cellY == 2 then
      -- VermilionDockSSAnneLeavesScript: only stepping OFF the ship
      -- triggers the departure (wDestinationWarpID == 1 in pokered)
      Flags.set(game.save, "EVENT_SS_ANNE_LEFT")
      local Music = require("src.core.Music")
      Music.stop()
      Music.play(game.data, "Music_Surfing")
      ow:queueScript({
        -- scripts/VermilionDock.asm:50 zeroes the player image index and
        -- :77 freezes sprite updates, so he faces DOWN throughout (#1689)
        { "face_player_dir", "down" },
        { "wait", 120 },
        { "play_sound", "SS_Anne_Horn" },
        -- scripts/VermilionDock.asm:80 .shift_columns_up
        { "ss_anne_departs" },
        -- scripts/VermilionDock.asm:205 VermilionDock_EraseSSAnne
        { "play_sound", "SS_Anne_Horn" },
        { "wait", 120 },
        { "move_player", "up", 2 },
        -- no keepMusic on this warp: Music_Surfing belongs to the dock's
        -- cutscene, and VERMILION_CITY's own theme has to take over as the
        -- player crosses in (EnterMap's PlayDefaultMusic)
        { "warp", "VERMILION_CITY", 18, 31, "up" },
        { "move_player", "up", 2 },
      })
    end
  end,
}

return M
