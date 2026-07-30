-- Third batch of hand-ported events: fishing rod givers, the Marowak
-- ghost, elevators, the Game Corner coins/prizes, the SS Anne departure
-- and the Hall of Fame record.  Each cites its pokered source.

local M = {}

-- -------------------------------------------------------------------
-- Fishing rod givers (scripts/VermilionOldRodHouse.asm,
-- FuchsiaGoodRodHouse.asm, Route12SuperRodHouse.asm)
-- -------------------------------------------------------------------

local function rodGiver(askText, receivedText, afterText, rodItem, flag)
  return {
    { "face_player" },                -- 1
    { "check_flag", flag },           -- 2
    { "jump_if_true", 9 },            -- 3
    { "ask", askText },               -- 4
    { "jump_if_false", 10 },          -- 5
    -- give-then-print like the three rod-house scripts (GiveItem fills
    -- wStringBuffer; the received texts read OLD/GOOD/SUPER ROD from it)
    { "give_item", rodItem, 1, false },  -- 6
    { "show_text", receivedText },       -- 7
    { "set_flag", flag },             -- 8
    { "jump", 10 },                   -- 9 is below
  }
end

M.VERMILION_OLD_ROD_HOUSE = {
  talk = {
    TEXT_VERMILIONOLDRODHOUSE_FISHING_GURU = rodGiver(
      "_VermilionOldRodHouseFishingGuruDoYouLikeToFishText",
      "_VermilionOldRodHouseFishingGuruTakeThisText",
      "_VermilionOldRodHouseFishingGuruHowAreTheFishBitingText",
      "OLD_ROD", "EVENT_GOT_OLD_ROD"),
  },
}
M.VERMILION_OLD_ROD_HOUSE.talk.TEXT_VERMILIONOLDRODHOUSE_FISHING_GURU[9] =
  { "show_text", "_VermilionOldRodHouseFishingGuruHowAreTheFishBitingText" }

M.FUCHSIA_GOOD_ROD_HOUSE = {
  talk = {
    TEXT_FUCHSIAGOODRODHOUSE_FISHING_GURU = rodGiver(
      "_FuchsiaGoodRodHouseFishingGuruText",
      "_FuchsiaGoodRodHouseFishingGuruReceivedGoodRodText",
      "_FuchsiaGoodRodHouseFishingGuruHowAreTheFishText",
      "GOOD_ROD", "EVENT_GOT_GOOD_ROD"),
  },
}
M.FUCHSIA_GOOD_ROD_HOUSE.talk.TEXT_FUCHSIAGOODRODHOUSE_FISHING_GURU[9] =
  { "show_text", "_FuchsiaGoodRodHouseFishingGuruHowAreTheFishText" }

M.ROUTE_12_SUPER_ROD_HOUSE = {
  talk = {
    TEXT_ROUTE12SUPERRODHOUSE_FISHING_GURU = rodGiver(
      "_Route12SuperRodHouseFishingGuruDoYouLikeToFishText",
      "_Route12SuperRodHouseFishingGuruReceivedSuperRodText",
      "_Route12SuperRodHouseFishingGuruTryFishingText",
      "SUPER_ROD", "EVENT_GOT_SUPER_ROD"),
  },
}
M.ROUTE_12_SUPER_ROD_HOUSE.talk.TEXT_ROUTE12SUPERRODHOUSE_FISHING_GURU[9] =
  { "show_text", "_Route12SuperRodHouseFishingGuruTryFishingText" }

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
-- battle is disguised (IsGhostBattle -> makeGhost: "too scared to move",
-- balls dodged). An earlier version of this port turned the player back
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
      if not game.save.inventory.SILPH_SCOPE then
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
          game.stack:push(TextBox.new(game,
            t._PokemonTower6FSoulWasCalmedText
            or "The mother's soul\nwas calmed.\012It departed to\nthe afterlife!"))
        elseif result ~= "lose" then
          -- .did_not_defeat: one simulated step right, off the trigger,
          -- so fleeing does not leave you standing on a cell that
          -- immediately re-fires.
          ow:scriptMove(ow.player, "right", 1)
        end
        ow:afterBattle(result, battle)
      end
      game.stack:push(battle)
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
    local ListMenu = require("src.ui.ListMenu")
    game.stack:push(ListMenu.new(game, "WHICH FLOOR?", items, {
      onChoose = function(item, list)
        list:close()
        -- the whole ShakeElevator ride runs in place -- music stop, 100
        -- collision-thud scroll bounces, the PA chime -- and only then
        -- does .UpdateWarp's rewrite land, with the player still stood
        -- at the panel: they walk out to the car door themselves
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
        -- DisplayElevatorFloorMenu: `ret c` on B -- no warp, nothing
        -- happens, the player just stays in the car (exit warps were
        -- already seeded on entry)
        done()
      end,
    }))
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
        battle.onFinish = function(result)
          if result ~= "win" then
            ow:afterBattle(result, battle)
            done()
            return
          end
          game.save.defeatedTrainers[npc.id] = true
          game.save.flags.EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI = true
          -- End-battle "WHAT!" then BeatGiovanniScript's hope text,
          -- fade, HideObject Giovanni, ShowObject Silph Scope.
          game.stack:push(TextBox.new(game, cannotBe, function()
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
            -- #198: GameCornerRocketExitScript (scripts/GameCorner.asm)
            -- ApplyMovementData walks the grunt one tile UP into the poster
            -- (the hideout's secret entrance at 9,4) before HideObject, so
            -- he leaves the floor rather than popping out of existence on
            -- (9,5).  scriptMove locks player input (#scriptMoves>0) and
            -- ignores collision, so we despawn + unfreeze (done) only once
            -- the step lands.
            ow:scriptMove(npc, "up", 1, function()
              hideRocket()
              done()
            end)
          end))
      end)
    end,
    TEXT_GAMECORNER_CLERK1 = function(game, ow, npc, done)
      local TextBox = require("src.render.TextBox")
      local ChoiceBox = require("src.ui.ChoiceBox")
      local t = game.data.text
      game.stack:push(TextBox.new(game,
        (t._GameCornerClerk1DoYouNeedSomeGameCoinsText
         or "Do you need some\ngame coins?\f¥1000 for 50."), function()
        game.stack:push(ChoiceBox.new(game, function(yes)
          if not yes then
            game.stack:push(TextBox.new(game,
              t._GameCornerClerk1PleaseComePlaySometimeText
              or "No? Please come\nplay sometime!", done))
            return
          end
          -- scripts/GameCorner.asm GameCornerClerk1Text: coins need
          -- the COIN CASE and room for at least 9 coins (Has9990Coins)
          if not game.save.inventory.COIN_CASE then
            game.stack:push(TextBox.new(game,
              t._GameCornerClerk1DontHaveCoinCaseText
              or "You don't have a\nCOIN CASE!", done))
            return
          end
          if (game.save.coins or 0) >= 9990 then
            game.stack:push(TextBox.new(game,
              t._GameCornerClerk1CoinCaseIsFullText
              or "Oops! Your COIN\nCASE is full.", done))
            return
          end
          if game.save.money < 1000 then
            game.stack:push(TextBox.new(game,
              t._GameCornerClerk1CantAffordTheCoinsText
              or "You can't afford\nthe coins!", done))
            return
          end
          game.save.money = game.save.money - 1000
          game.save.coins = math.min(9999, (game.save.coins or 0) + 50)
          game.stack:push(TextBox.new(game,
            (t._GameCornerClerk1ThanksHereAre50CoinsText
             or "Thanks! Here are\nyour 50 coins!")
            .. ("\fCOINS: %d"):format(game.save.coins), done))
        end))
      end))
    end,
  },
}

-- Game Corner prize lists (data/events/prizes.asm, prize_mon_levels.asm).
-- The six mon prizes differ between Red and Blue; the three TM prizes are
-- identical, so they are shared and appended to each version's mon list.
local PRIZE_TMS = {
  { kind = "item", item = "TM_DRAGON_RAGE", cost = 3300 },
  { kind = "item", item = "TM_HYPER_BEAM", cost = 5500 },
  { kind = "item", item = "TM_SUBSTITUTE", cost = 7700 },
}
local RED_PRIZES = {
  { kind = "mon", species = "ABRA", level = 9, cost = 180 },
  { kind = "mon", species = "CLEFAIRY", level = 8, cost = 500 },
  { kind = "mon", species = "NIDORINA", level = 17, cost = 1200 },
  { kind = "mon", species = "DRATINI", level = 18, cost = 2800 },
  { kind = "mon", species = "SCYTHER", level = 25, cost = 5500 },
  { kind = "mon", species = "PORYGON", level = 26, cost = 9999 },
  PRIZE_TMS[1], PRIZE_TMS[2], PRIZE_TMS[3],
}
local BLUE_PRIZES = {
  { kind = "mon", species = "ABRA", level = 6, cost = 120 },
  { kind = "mon", species = "CLEFAIRY", level = 12, cost = 750 },
  { kind = "mon", species = "NIDORINO", level = 17, cost = 1200 },
  { kind = "mon", species = "PINSIR", level = 20, cost = 2500 },
  { kind = "mon", species = "DRATINI", level = 24, cost = 4600 },
  { kind = "mon", species = "PORYGON", level = 18, cost = 6500 },
  PRIZE_TMS[1], PRIZE_TMS[2], PRIZE_TMS[3],
}

local function activePrizes()
  return require("src.core.GameVersion").isBlue() and BLUE_PRIZES or RED_PRIZES
end

-- Prize counters (engine/menus/prize_menu.asm CeladonPrizeMenu; the prize
-- list itself is data/events/prizes.asm, prize_mon_levels.asm).  Gen1 gates
-- the prize window on the COIN CASE: it does IsItemInBag COIN_CASE first, and
-- with no case prints RequireCoinCaseText and returns without ever opening a
-- window; only with the case does it print ExchangeCoinsForPrizesText and then
-- show the prizes.  #194: the port used to open the window unconditionally and
-- skip both text boxes.
local function prizeCounter(game, ow, npc, done)
  local ListMenu = require("src.ui.ListMenu")
  local Commands = require("src.script.Commands")
  local TextBox = require("src.render.TextBox")
  local t = game.data.text
  -- IsItemInBag COIN_CASE: without the case, deny and open no window
  -- (COIN_CASE is a numeric count in save.inventory, nil when absent).
  if not game.save.inventory.COIN_CASE then
    game.stack:push(TextBox.new(game,
      t._RequireCoinCaseText or "A COIN CASE is\nrequired!", done))
    return
  end
  -- ExchangeCoinsForPrizesText plays before the prize window opens.
  game.stack:push(TextBox.new(game,
    t._ExchangeCoinsForPrizesText or "We exchange your\ncoins for prizes.",
    function()
      local items = {}
      for _, p in ipairs(activePrizes()) do
        local label
        if p.kind == "mon" then
          label = ("%s L%d"):format(game.data.pokemon[p.species].name, p.level)
        else
          label = game.data.items[p.item].name
        end
        table.insert(items,
          { label = label, right = tostring(p.cost), value = p })
      end
      local list
      list = ListMenu.new(game, "PRIZES (COINS)", items, {
        footer = ("COINS %d"):format(game.save.coins or 0),
        onChoose = function(item)
          local p = item.value
          if (game.save.coins or 0) < p.cost then
            list.footer = "Not enough coins!"
            return
          end
          game.save.coins = game.save.coins - p.cost
          if p.kind == "mon" then
            Commands.give_pokemon({ save = game.save, game = game },
                                  p.species, p.level)
          else
            game.save.inventory[p.item] = (game.save.inventory[p.item] or 0) + 1
          end
          list.footer = ("Got it! COINS %d"):format(game.save.coins)
        end,
        onCancel = done,
      })
      game.stack:push(list)
    end))
end

M.GAME_CORNER_PRIZE_ROOM = {
  talk = { -- the three prize counters are bg events
    TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_1 = prizeCounter,
    TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_2 = prizeCounter,
    TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_3 = prizeCounter,
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

-- her four hull columns bow-to-stern (upper-half / lower-half block ids)
-- and the open-water ids of the rows she sits in
local DOCK_SHIP_COLUMNS = {
  { bx = 5, top = 4, bottom = 8 },
  { bx = 6, top = 5, bottom = 9 },
  { bx = 7, top = 6, bottom = 10 },
  { bx = 8, top = 7, bottom = 11 },
}
local DOCK_WATER_TOP, DOCK_WATER_BOTTOM = 1, 13

M.VERMILION_DOCK = {
  onEnter = function(game, ow)
    local Flags = require("src.script.Flags")
    local f = game.save.flags
    if Flags.get(game.save, "EVENT_SS_ANNE_LEFT") then
      -- the ship is long gone: erase her right away, and anyone who
      -- still lands here is sent back out past the guard
      for _, b in ipairs(DOCK_SHIP_BLOCKS) do
        ow.map:setBlock(b.bx, b.by, b.water)
      end
      ow.map.renderer:rebuild()
      local TextBox = require("src.render.TextBox")
      game.stack:push(TextBox.new(game,
        game.data.text._VermilionCitySailor1ShipSetSailText
        or "The ship set sail.", function()
        ow:startWarpTo("VERMILION_CITY", 18, 29, "up")
      end))
    elseif f.EVENT_GOT_HM01 and ow.player.cellY == 2 then
      -- VermilionDockSSAnneLeavesScript: only stepping OFF the ship
      -- triggers the departure (wDestinationWarpID == 1 in pokered) --
      -- Music_Surfing plays for the sail-away cutscene, smoke puffs
      -- drift off the funnel, the horn blows, the ship is erased to
      -- open water, and the player is walked off the dock into the
      -- city past the guard (VermilionCity's
      -- SCRIPT_VERMILIONCITY_PLAYER_EXIT_SHIP walk)
      Flags.set(game.save, "EVENT_SS_ANNE_LEFT")
      local Music = require("src.core.Music")
      Music.stop()
      Music.play(game.data, "Music_Surfing")
      local function puff(n, cx)
        if n <= 0 then return end
        ow:startDustAnim(cx, 1, function() puff(n - 1, cx + 2) end)
      end
      puff(3, 15)
      -- VermilionDock_EraseSSAnne deliberately leaves the blocks under the
      -- player alone ("south of the player and won't be redrawn"), so skip
      -- his own block: he must not spend the walk-out standing on water
      local pbx = math.floor(ow.player.cellX / 2)
      local pby = math.floor(ow.player.cellY / 2)
      local rows = {}
      local function setBlock(bx, by, block)
        if bx < 1 or bx > 8 then return end
        if bx == pbx and by == pby then return end
        rows[#rows + 1] = { "replace_block", bx, by, block }
      end
      rows[#rows + 1] = { "wait", 120 }
      rows[#rows + 1] = { "play_sound", "SS_Anne_Horn" }
      -- .shift_columns_up slides her tile columns west behind a mid-frame
      -- rSCX split; with no split scroll here she sails one block per beat
      -- and the water closes in astern (#360)
      for step = 1, 8 do
        for _, col in ipairs(DOCK_SHIP_COLUMNS) do
          setBlock(col.bx - step, 1, col.top)
          setBlock(col.bx - step, 2, col.bottom)
        end
        setBlock(9 - step, 1, DOCK_WATER_TOP)
        setBlock(9 - step, 2, DOCK_WATER_BOTTOM)
        rows[#rows + 1] = { "wait", 20 }
      end
      -- the second horn as she clears the dock, then EraseSSAnne's 120
      -- frames before the walk out
      rows[#rows + 1] = { "play_sound", "SS_Anne_Horn" }
      rows[#rows + 1] = { "wait", 120 }
      rows[#rows + 1] = { "move_player", "up", 2 }
      -- no keepMusic on this warp: Music_Surfing belongs to the dock's
      -- cutscene, and VERMILION_CITY's own theme has to take over as the
      -- player crosses in (EnterMap's PlayDefaultMusic)
      rows[#rows + 1] = { "warp", "VERMILION_CITY", 18, 31, "up" }
      rows[#rows + 1] = { "move_player", "up", 2 }
      ow:queueScript(rows)
    end
  end,
}

return M
