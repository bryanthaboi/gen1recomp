-- More hand-ported events: the Pallet Town intro, the thirsty Saffron
-- gate guards, the Bike Voucher chain, fossils and the day-care.
-- Registered via data/scripts/init.lua; Red/Blue cite pokered, Yellow
-- cites pokeyellow (Pallet stop row, Oak spawn, walk RLE, and the
-- wild-Pikachu beat before the lab escort).

local GameVersion = require("src.core.GameVersion")

local M = {}

-- -------------------------------------------------------------------
-- Pallet Town intro (scripts/PalletTown.asm PalletTownOakHeyWaitScript):
-- stepping toward the grass without a starter makes Oak stop you and
-- take you to his lab (the walk cutscene is compressed into the warp).
-- -------------------------------------------------------------------

-- Pure escort data, exposed on the map entry as `escort` for
-- tests/parity_intro.lua.
local escort = {}

-- FindPathToPlayer (engine/overworld/pathfinding.asm): each step
-- reduces whichever axis has more distance left; ties step X first
-- (`ld a, e / cp d / jr c, .yDistanceGreater`, e = X left, d = Y left).
function escort.findPath(fromX, fromY, toX, toY)
  local xdist, ydist = math.abs(toX - fromX), math.abs(toY - fromY)
  local xdir = toX > fromX and "right" or "left"
  local ydir = toY > fromY and "down" or "up"
  local xprog, yprog = 0, 0
  local path = {}
  while xprog < xdist or yprog < ydist do
    if xdist - xprog >= ydist - yprog and xprog < xdist then
      xprog = xprog + 1
      path[#path + 1] = xdir
    else
      yprog = yprog + 1
      path[#path + 1] = ydir
    end
  end
  return path
end

-- Red: Oak object (8,5) -> one tile below the player at y=1.
-- Yellow: Oak object (10,4); stop fires at y=0 (pokeyellow PalletTown).
function escort.oakApproach(playerX)
  if GameVersion.isYellow() then
    return escort.findPath(10, 4, playerX, 1)
  end
  return escort.findPath(8, 5, playerX, 2)
end

-- RLEList_ProfOakWalkToLab (engine/overworld/auto_movement.asm).
-- Yellow differs: first DOWN is x6 (Oak starts one tile farther north).
local function buildOakSteps()
  if GameVersion.isYellow() then
    return {
      "down", "down", "down", "down", "down", "down",
      "left",
      "down", "down", "down", "down", "down",
      "right", "right", "right",
      "up",
    }
  end
  return {
    "down", "down", "down", "down", "down",
    "left",
    "down", "down", "down", "down", "down",
    "right", "right", "right",
    "up",
  }
end

escort.oakSteps = buildOakSteps()

-- Player stays one step behind Oak (simplified reverse-RLE port).
escort.playerSteps = { "down" }
for _, d in ipairs(escort.oakSteps) do
  escort.playerSteps[#escort.playerSteps + 1] = d
end

local function npcNamed(ow, name)
  for _, n in ipairs(ow.npcs or {}) do
    if n.def and n.def.name == name then return n end
  end
  return nil
end

M.PALLET_TOWN = {
  talk = require("data.scripts.pallet_town").talk,
  escort = escort,
  -- scripts/PalletTown.asm:133-144
  onEnter = function(game, ow)
    local f = game.save.flags
    if f.EVENT_GOT_TOWN_MAP and f.EVENT_ENTERED_BLUES_HOUSE
       and not f.EVENT_DAISY_WALKING then
      f.EVENT_DAISY_WALKING = true
      local Commands = require("src.script.Commands")
      local ctx = { save = game.save, game = game, overworld = ow }
      Commands.hide_object(ctx, "BLUES_HOUSE", "BLUESHOUSE_DAISY1")
      Commands.show_object(ctx, "BLUES_HOUSE", "BLUESHOUSE_DAISY2")
    end
  end,
  -- Red: stop at y==1 from (8,5).  Yellow: stop at y==0 from (10,4),
  -- then a wild Pikachu battle before the lab escort (pokeyellow
  -- PalletTownPikachuBattleScript).
  onStep = function(game, ow, x, y)
    local yellow = GameVersion.isYellow()
    local stopY = yellow and 0 or 1
    if y ~= stopY or game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB
       or game.save.flags.EVENT_GOT_STARTER then
      return false
    end
    local TextBox = require("src.render.TextBox")
    local Commands = require("src.script.Commands")
    local Music = require("src.core.Music")
    local BattleState = require("src.battle.BattleState")
    local t = game.data.text
    local ctx = { save = game.save, game = game, overworld = ow }

    -- Red turns the player down; Yellow faces up at the north exit.
    ow.player.facing = yellow and "up" or "down"
    Music.play(game.data, "Music_MeetProfOak")

    local function hold(frames, npc, cb)
      ow.emote = { frames = frames, npc = npc, onDone = cb }
    end

    local function walkList(entity, steps, done)
      local i = 0
      local function nextStep()
        i = i + 1
        if not entity or not steps[i] then
          if done then done() end
          return
        end
        ow:scriptMove(entity, steps[i], 1, nextStep)
      end
      nextStep()
    end

    -- OaksLabOakChooseMonSpeechScript.  Yellow's OakChooseMon text is
    -- the single-ball speech, not Red's "there are 3 POKéMON".
    local function chooseMonSpeech()
      local function say(key, fb, next)
        game.stack:push(TextBox.new(game, t[key] or fb, next))
      end
      say("_OaksLabRivalFedUpWithWaitingText",
          "{RIVAL}: Gramps!\nI'm fed up with\nwaiting!", function()
        hold(3, nil, function()
          say("_OaksLabOakChooseMonText",
              yellow
                and "OAK: Look, {PLAYER}! Do\nyou see that ball\non the table?"
                or "OAK: Here, {PLAYER}!\fThere are 3\nPOKéMON here!\fYou can have one!\nChoose!", function()
            hold(3, nil, function()
              say("_OaksLabRivalWhatAboutMeText",
                  "{RIVAL}: Hey!\nGramps! What\nabout me?", function()
                hold(3, nil, function()
                  say("_OaksLabOakBePatientText",
                      "OAK: Be patient!\n{RIVAL}, you can\nhave one too!", function()
                    game.save.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON = true
                  end)
                end)
              end)
            end)
          end)
        end)
      end)
    end

    -- Door Oak is OAKSLAB_OAK2: Red index 8, Yellow index 6 (one ball).
    local function labWalkIn()
      local oak2 = npcNamed(ow, "OAKSLAB_OAK2") or ow:npcByIndex(yellow and 6 or 8)
      local function swapOaks()
        Commands.hide_object(ctx, "OAKS_LAB", "OAKSLAB_OAK2")
        Commands.show_object(ctx, "OAKS_LAB", "OAKSLAB_OAK1")
        hold(3, nil, function()
          Commands.face_object(ctx, 1, "down")
          ow:scriptMove(ow.player, "up", 8, function()
            game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
            game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = true
            Commands.face_object(ctx, 1, "up")
            Music.playMap(game.data, "OAKS_LAB")
            chooseMonSpeech()
          end)
        end)
      end
      if oak2 then
        ow:scriptMove(oak2, "up", 3, swapOaks)
      else
        swapOaks()
      end
    end

    local function enterLab(oak)
      if oak then oak.stepFrames = nil end
      Commands.hide_object(ctx, "PALLET_TOWN", "PALLETTOWN_OAK")
      Commands.show_object(ctx, "OAKS_LAB", "OAKSLAB_OAK2")
      ow.doorWarp = true
      ow:startWarpTo("OAKS_LAB", 5, 11, "up", labWalkIn,
                     { keepMusic = true })
    end

    local function walkToLab(oak)
      -- lockstep half runs Oak on the player's own frames per cell
      -- engine/overworld/movement.asm:737 (DoScriptedNPCMovement)
      local i = 0
      if oak then
        oak.stepFrames = ow.player.stepFramesCur or ow.player.stepFrames
      end
      local function tick()
        i = i + 1
        local playerStep = escort.playerSteps[i]
        if not playerStep then
          enterLab(oak)
          return
        end
        if oak and escort.oakSteps[i] then
          ow:scriptMove(oak, escort.oakSteps[i], 1)
        elseif oak then
          ow:marchInPlace(oak)
        end
        ow:scriptMove(ow.player, playerStep, 1, tick)
      end
      tick()
    end

    local function escortToLab(oak)
      -- PalletMovementScript_OakMoveLeft
      -- (engine/overworld/auto_movement.asm) starts MUSIC_MUSEUM_GUY
      -- when the escort begins in Yellow. Until then, Pallet Town plays
      -- after the battle; Red/Blue leave MUSIC_MEET_PROF_OAK playing.
      if yellow then
        Music.play(game.data, "Music_MuseumGuy")
      end
      local numSteps = x - 10
      if oak and numSteps > 0 then
        ow:scriptMove(oak, "left", numSteps, function()
          ow:scriptMove(ow.player, "left", numSteps, function()
            walkToLab(oak)
          end)
        end)
      else
        walkToLab(oak)
      end
    end

    -- After Oak reaches the player: Red goes straight to "It's unsafe!".
    -- Yellow (PalletTownOakGreetsPlayerScript..AfterPikachuBattleScript):
    -- ThatWasClose -> Oak faces the grass patch -> BATTLE_TYPE_PIKACHU
    -- (the old-man-style simulated battle where PROF.OAK throws the ball
    -- and always catches the lv5 Pikachu) -> Whew -> ComeWithMe.
    local function afterOakArrives(oak)
      if not yellow then
        game.stack:push(TextBox.new(game,
          t._PalletTownOakItsUnsafeText
          or "OAK: It's unsafe!\nWild POKéMON\nlive in tall grass!",
          function() escortToLab(oak) end))
        return
      end
      local function comeWithMe()
        game.stack:push(TextBox.new(game,
          t._PalletTownOakComeWithMe
          or "OAK: Here, come with\nme!",
          function() escortToLab(oak) end))
      end
      local function afterPikaBattle()
        if oak then oak.facing = "up" end
        game.stack:push(TextBox.new(game,
          t._PalletTownOakWhewText or "OAK: Whew...",
          comeWithMe))
      end
      game.stack:push(TextBox.new(game,
        t._PalletTownOakThatWasCloseText
        or "OAK: That was\nclose!\fWild POKéMON live\nin tall grass!",
        function()
          -- Oak turns toward the horizontally adjacent grass (left exit
          -- looks right, right exit looks left -- the
          -- EVENT_PLAYER_AT_RIGHT_EXIT_TO_PALLET_TOWN branch).
          -- In pokeyellow, PalletTownOakGreetsPlayerScript turns Oak and
          -- PalletTownPikachuBattleScript arms the battle on the next
          -- overworld iteration. OverworldLoopLessDelay
          -- (home/overworld.asm) burns two DelayFrame calls at the top
          -- of each iteration and calls RunMapScript before checking
          -- wCurOpponent, so those two DelayFrame calls are what keep
          -- Oak's turn on screen before the battle check fires.
          if oak then oak.facing = x == 10 and "right" or "left" end
          hold(2, nil, function()
            local battle = BattleState.newWild(game, "PIKACHU", 5)
            battle:makeOldManDemo("PROF.OAK")
            battle.onFinish = function()
              afterPikaBattle()
            end
            -- Use the standard wild-battle entry transition.
            Commands.pushBattle(ctx, battle)
          end)
        end))
    end

    local function oakAppearsAndWalks()
      Commands.show_object(ctx, "PALLET_TOWN", "PALLETTOWN_OAK")
      local oak = npcNamed(ow, "PALLETTOWN_OAK") or ow:npcByIndex(1)
      if oak then oak.facing = "up" end
      hold(6, nil, function()
        walkList(oak, escort.oakApproach(x), function()
          afterOakArrives(oak)
        end)
      end)
    end

    game.stack:push(TextBox.new(game,
      t._PalletTownOakHeyWaitDontGoOutText or "OAK: Hey! Wait!\nDon't go out!",
      nil, { auto = { delay = 10, overlap = 10, onOverlap = function()
        -- .HeyWaitDontGoOutText turns the player to face down (toward
        -- the approaching Oak) before the exclamation bubble
        ow.player.facing = "down"
        ow.emote = { npc = ow.player, frames = 50, onDone = oakAppearsAndWalks }
      end } }))
    return true
  end,
}

-- -------------------------------------------------------------------
-- Saffron gate guards (scripts/Route5Gate.asm etc.): crossing the gate
-- without having given them a drink gets you turned back; a drink from
-- the bag (bought at Celadon's vending machines... or any mart that
-- stocks them) opens all four gates.
-- -------------------------------------------------------------------

local DRINKS = { "FRESH_WATER", "SODA_POP", "LEMONADE" }

-- Hand over the first drink in the bag, if any. Mirrors RemoveGuardDrink
-- (engine/items/inventory.asm), which walks the same three item ids and
-- removes ONE, and the caller's BIT_GAVE_SAFFRON_GUARDS_DRINK.
local function takeGuardDrink(game)
  for _, drink in ipairs(DRINKS) do
    if (game.save.inventory[drink] or 0) > 0 then
      game.save.inventory[drink] = game.save.inventory[drink] - 1
      if game.save.inventory[drink] == 0 then
        game.save.inventory[drink] = nil
      end
      game.save.flags.EVENT_GAVE_GUARDS_DRINK = true
      return true
    end
  end
  return false
end

local function saffronGate(guardText, triggers, horizontal)
  return {
    talk = {
      [guardText] = function(game, ow, npc, done)
        local TextBox = require("src.render.TextBox")
        local t = game.data.text
        if game.save.flags.EVENT_GAVE_GUARDS_DRINK then
          game.stack:push(TextBox.new(game,
            t._SaffronGateGuardThanksForTheDrinkText or "Gee, that was\ntasty!", done))
          return
        end
        if takeGuardDrink(game) then
          game.stack:push(TextBox.new(game,
            t._SaffronGateGuardImParchedText or "Whoa, boy!\nI'm parched!",
            function()
              game.stack:push(TextBox.new(game,
                (t._SaffronGateGuardYouCanGoOnThroughText or
                 "You can go on\nthrough!"), done))
            end))
          return
        end
        game.stack:push(TextBox.new(game,
          t._SaffronGateGuardGeeImThirstyText or "Gee, I'm thirsty\nthough!", done))
      end,
    },
    -- the gate's trigger cells (each gate's PlayerInCoordsArray):
    -- without the drink flag you get walked back the way you came
    onStep = function(game, ow, x, y)
      local hit = false
      for _, c in ipairs(triggers) do
        if x == c[1] and y == c[2] then hit = true break end
      end
      if not hit then return false end
      if game.save.flags.EVENT_GAVE_GUARDS_DRINK then return false end
      local TextBox = require("src.render.TextBox")
      local t = game.data.text
      -- Stepping on the trigger WITH a drink hands it over right here.
      --
      -- Route5GateDefaultScript (scripts/Route5Gate.asm) runs
      -- `farcall RemoveGuardDrink` before it decides anything: the coord
      -- trigger itself takes the drink and sets
      -- BIT_GAVE_SAFFRON_GUARDS_DRINK, and only a player carrying nothing
      -- gets the thirsty line and the walk-back. We had the removal on the
      -- guard's TALK handler only, so walking up with a FRESH_WATER in the
      -- bag was turned away and the four gates stayed shut unless you
      -- happened to talk to him -- which vanilla never requires.
      --
      -- Saffron is the middle of the map, so this sealed it: every route
      -- through the city (Celadon <-> Lavender, Vermilion <-> Cerulean the
      -- short way) was unreachable, and the bot could not get to Lavender
      -- for the POKE_FLUTE at all.
      if takeGuardDrink(game) then
        game.stack:push(TextBox.new(game,
          t._SaffronGateGuardImParchedText or "Whoa, boy!\nI'm parched!",
          function()
            game.stack:push(TextBox.new(game,
              (t._SaffronGateGuardYouCanGoOnThroughText or
               "You can go on\nthrough!")))
          end))
        return true
      end
      local back
      if horizontal then
        back = ow.player.facing == "left" and "right" or "left"
      else
        back = ow.player.facing == "up" and "down" or "up"
      end
      game.stack:push(TextBox.new(game,
        t._SaffronGateGuardGeeImThirstyText or "Gee, I'm thirsty\nthough!\nThe road's closed.",
        function()
          ow:scriptMove(ow.player, back, 1)
        end))
      return true
    end,
  }
end

M.ROUTE_5_GATE = saffronGate("TEXT_ROUTE5GATE_GUARD", { { 3, 3 }, { 4, 3 } })
M.ROUTE_6_GATE = saffronGate("TEXT_ROUTE6GATE_GUARD", { { 3, 2 }, { 4, 2 } })
M.ROUTE_7_GATE = saffronGate("TEXT_ROUTE7GATE_GUARD", { { 3, 3 }, { 3, 4 } }, true)
M.ROUTE_8_GATE = saffronGate("TEXT_ROUTE8GATE_GUARD", { { 2, 3 }, { 2, 4 } }, true)

-- -------------------------------------------------------------------
-- Bike Voucher chain (scripts/PokemonFanClub.asm, BikeShop.asm)
-- -------------------------------------------------------------------

M.POKEMON_FAN_CLUB = {
  onEnter = function(game, ow)
    require("src.world.PikachuFollower").onFanClubEntered(game, ow)
  end,
  talk = {
    TEXT_POKEMONFANCLUB_CHAIRMAN = {
      { "face_player" },                                          -- 1
      { "check_flag", "EVENT_RECEIVED_BIKE_VOUCHER" },            -- 2
      { "jump_if_true", "nothing_left" },                         -- 3
      -- YesNoChoice (scripts/PokemonFanClub.asm): NO forfeits the voucher (#1050)
      { "ask", "_PokemonFanClubChairmanIntroText" },              -- 4
      { "jump_if_false", "no_story" },                            -- 5
      { "show_text", "_PokemonFanClubChairmanStoryText" },        -- 6
      -- give-then-print like scripts/PokemonFanClub.asm (GiveItem
      -- fills wStringBuffer; the received text reads it)
      { "give_item", "BIKE_VOUCHER", 1, false },                  -- 7
      { "show_text", "_PokemonFanClubReceivedBikeVoucherText" },  -- 8
      { "set_flag", "EVENT_RECEIVED_BIKE_VOUCHER" },              -- 9
      { "show_text", "_PokemonFanClubExplainBikeVoucherText" },   -- 10
      { "jump", "end" },                                          -- 11
      { "label", "no_story" },                                    -- 12
      { "show_text", "_PokemonFanClubNoStoryText" },              -- 13
      { "jump", "end" },                                          -- 14
      -- .nothingleft: the gift is done, he only reminisces now
      { "label", "nothing_left" },                                -- 15
      { "show_text", "_PokemonFanClubChairFinalText" },           -- 16
    },
  },
}

-- BikeShopClerkText (scripts/BikeShop.asm) runs three ways: the BICYCLE is
-- already yours, you are carrying the BIKE VOUCHER, or you get the sales
-- pitch.  The pitch draws its own window (TextBoxBorder hlcoord 0,0, b=4
-- c=15) holding BikeShopMenuText and BikeShopMenuPrice, and leaves it up
-- while the clerk keeps talking in the bottom box: the original never
-- erases it before TextScriptEnd (#568).
local BikeShopWindow = {}
BikeShopWindow.__index = BikeShopWindow

function BikeShopWindow.new(game, footer, onChoose)
  local self = setmetatable({}, BikeShopWindow)
  self.game = game
  self.onChoose = onChoose
  self.index = 1
  self.active = true
  -- BikeShopClerkDoYouLikeItText stays on screen under the window for as
  -- long as the menu is up.  The text box pushed on top types it out and
  -- pops itself; this copy of its last page takes over from there, so the
  -- bottom box never blanks between the pitch and the answer.  Paginated
  -- with the themed column budget so the copy breaks where the box did.
  local TextBox = require("src.render.TextBox")
  local box = require("src.ui.Theme").textBox or {}
  local pages = TextBox.paginate(TextBox.substitute(game, footer), box.maxCols)
  self.footer = pages[#pages]
  return self
end

function BikeShopWindow:update()
  -- one answer only: the boxes pushed by onChoose sit on top of this
  -- state, but a second A on the same frame must not fire it twice
  if not self.active then return end
  local input = self.game.input
  -- HandleMenuInput with wMenuWrappingEnabled clear: the two rows clamp
  if input:wasPressed("up") then
    self.index = 1
  elseif input:wasPressed("down") then
    self.index = 2
  elseif input:wasPressed("a") or input:wasPressed("b") then
    local cancelled = input:wasPressed("b") -- bit B_PAD_B -> .cancel
    require("src.core.Sound").play(self.game.data, "Press_AB")
    self.active = false
    self.onChoose(not cancelled and self.index == 1)
  end
end

function BikeShopWindow:draw()
  local Font = require("src.render.Font")
  local Strings = require("src.core.Strings")
  local Theme = require("src.ui.Theme")
  Font.drawBox(0, 0, 17, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local bike = self.game.data.items.BICYCLE
  Font.draw(bike and bike.name or "BICYCLE", 16, 16)  -- hlcoord 2, 2
  Font.draw("¥1000000", 64, 24)                       -- hlcoord 8, 3
  Font.draw(Strings("CANCEL"), 16, 32)                -- `next` skips a row
  -- wTopMenuItemX 1, wTopMenuItemY 2, rows two apart
  Font.drawCode(Theme.cursor, 8, self.index == 1 and 16 or 32)
  if self.footer then
    -- same geometry TextBox resolves against, so a themed box matches
    local box = Theme.textBox or {}
    local tx, ty = box.tx or 0, box.ty or 12
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(tx, ty, box.tw or 20, box.th or 6)
    love.graphics.setColor(0, 0, 0, 1)
    for i, line in ipairs(self.footer) do
      Font.draw(line, (tx + 1) * 8, (ty + 2 * i) * 8)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

M.BIKE_SHOP = {
  talk = {
    TEXT_BIKESHOP_CLERK = function(game, ow, npc, done)
      local Bag = require("src.inventory.Bag")
      local Flags = require("src.script.Flags")
      local TextBox = require("src.render.TextBox")
      local t = game.data.text
      local function say(text, after, opts)
        game.stack:push(TextBox.new(game, text, after, opts))
      end

      -- CheckEvent EVENT_GOT_BICYCLE.  Saves made before the clerk started
      -- setting the event still have the bike in the bag, so either counts.
      if (game.save.inventory.BICYCLE or 0) > 0
          or Flags.get(game.save, "EVENT_GOT_BICYCLE") then
        say(t._BikeShopClerkHowDoYouLikeYourBicycleText, done)
        return
      end

      -- .dontHaveBike: IsItemInBag BIKE_VOUCHER
      if (game.save.inventory.BIKE_VOUCHER or 0) > 0 then
        say(t._BikeShopClerkOhThatsAVoucherText, function()
          -- GiveItem's `jr nc, .BagFull`: the voucher is only spent once
          -- the BICYCLE is actually in the bag
          if not Bag.add(game.save, "BICYCLE", 1) then
            say(t._BikeShopBagFullText, done)
            return
          end
          Bag.remove(game.save, "BIKE_VOUCHER", 1)
          Flags.set(game.save, "EVENT_GOT_BICYCLE")
          -- BikeShopExchangedVoucherText carries sound_get_key_item; the
          -- map runs EnableAutoTextBoxDrawing, so the box still waits for
          -- a button once the jingle has played (auto.wait, #247)
          say(t._BikeShopExchangedVoucherText, done, {
            auto = { wait = true, sound = function()
              return require("src.core.Sound").play(game.data, "Get_Key_Item")
            end },
          })
        end)
        return
      end

      -- .dontHaveVoucher: welcome, then the BICYCLE/CANCEL window
      say(t._BikeShopClerkWelcomeText, function()
        local pitch = t._BikeShopClerkDoYouLikeItText
        game.stack:push(BikeShopWindow.new(game, pitch, function(bought)
          local function comeAgain()
            say(t._BikeShopComeAgainText, function()
              game.stack:pop() -- the window, still up under the text
              done()
            end)
          end
          if bought then
            -- a million is out of anyone's reach: BikeShopCantAffordText
            say(t._BikeShopCantAffordText, comeAgain)
          else
            comeAgain()
          end
        end))
        -- PrintText BikeShopClerkDoYouLikeItText, then straight into
        -- HandleMenuInput: the box types out and hands over without
        -- waiting, leaving the window's copy of the line on screen
        say(pitch, nil, { auto = { delay = 0 } })
      end)
    end,
  },
}

-- -------------------------------------------------------------------
-- Fossils (scripts/MtMoonB2F.asm, Museum1F.asm,
-- CinnabarLabFossilRoom.asm): pick one Mt Moon fossil, revive them at
-- the Cinnabar lab (the wait is skipped).
-- -------------------------------------------------------------------

-- The Super Nerd (object index 1) claims both fossils and blocks the way
-- to them. In scripts/MtMoonB2F.asm he isn't a sight-line trainer: his
-- header carries no range, so MtMoonB2FDefaultScript force-triggers the
-- battle the instant the player steps onto (13,8) -- the chokepoint tile
-- to his right -- and reaching for a fossil intercepts you too.
local function superNerdBeaten(ow)
  local nerd = ow:npcByIndex(1)
  return not nerd or ow:trainerDefeated(nerd)
end

local function engageSuperNerd(game, ow, onDone)
  local nerd = ow:npcByIndex(1)
  if not nerd or ow:trainerDefeated(nerd) then
    if onDone then onDone() end
    return
  end
  nerd:facePlayer(ow.player)
  ow:engageTrainer(nerd, onDone)
end

-- MtMoonB2FMoveSuperNerdScript: player-near-dome coords walk RIGHT then
-- UP (MoveRight falls through into MoveUp); near-helix walks UP only.
local function mtMoonNerdWalk(px, py, itemId)
  if (px == 12 and py == 7) or (px == 11 and py == 6) or (px == 12 and py == 5) then
    return { "right", "up" }
  end
  if (px == 13 and py == 7) or (px == 14 and py == 6) or (px == 14 and py == 5) then
    return { "up" }
  end
  return (itemId == "DOME_FOSSIL") and { "right", "up" } or { "up" }
end

-- scripts/MtMoonB2F.asm Dome/Helix fossil text_asm + MoveSuperNerd +
-- SuperNerdTakesOtherFossil: pick one, hide it, walk the nerd to the
-- other, "All right. Then this is mine!", hide the other.
local function mtMoonFossil(itemId, otherName, gotFlag)
  return function(game, ow, npc, done)
    local TextBox = require("src.render.TextBox")
    local t = game.data.text
    local flags = game.save.flags
    if flags.EVENT_GOT_DOME_FOSSIL or flags.EVENT_GOT_HELIX_FOSSIL then
      done()
      return
    end
    if not superNerdBeaten(ow) then
      engageSuperNerd(game, ow, done)
      return
    end
    local want = (itemId == "DOME_FOSSIL")
      and (t._MtMoonB2FDomeFossilYouWantText or "You want the\nDOME FOSSIL?")
      or (t._MtMoonB2FHelixFossilYouWantText or "You want the\nHELIX FOSSIL?")
    game.stack:push(TextBox.new(game, want, nil, { choice = function(yes)
      if not yes then done() return end
      if not require("src.inventory.Bag").add(game.save, itemId, 1) then
        game.stack:push(TextBox.new(game,
          t._MtMoonB2FYouHaveNoRoomText or "Look, you've got\nno room for this.",
          done))
        return
      end
      local idef = game.data.items[itemId]
      game.stringBuffer = idef and idef.name or itemId
      local dirs = mtMoonNerdWalk(ow.player.cellX, ow.player.cellY, itemId)
      -- MtMoonB2FReceivedFossilText: text_far, sound_get_key_item,
      -- text_waitbutton -- the jingle plays after the box has typed and
      -- the button wait comes after it
      game.stack:push(TextBox.new(game,
        t._MtMoonB2FReceivedFossilText
          or ("{PLAYER} got the\n" .. game.stringBuffer .. "!"),
        function()
          local Commands = require("src.script.Commands")
          Commands.hide_object(
            { save = game.save, overworld = ow, game = game },
            "MT_MOON_B2F", npc.def.name)
          flags[gotFlag] = true
          ow.runner:run({
            { "walk_npc", 1, dirs },
            { "text_opts", { auto = true } },
            { "text_sound", "Get_Key_Item" },
            { "show_text", "_MtMoonB2FSuperNerdThenThisIsMineText" },
            { "hide_object", "MT_MOON_B2F", otherName },
          }, { onDone = done })
        end, TextBox.soundOpts(game, "Get_Key_Item")))
    end }))
  end
end

M.MT_MOON_B2F = {
  -- MtMoonB2FDefaultScript forces the Super Nerd battle when the player
  -- steps onto (13,8), the tile beside him guarding the fossils.
  onStep = function(game, ow, x, y)
    if x == 13 and y == 8 and not superNerdBeaten(ow) then
      engageSuperNerd(game, ow, nil)
      return true
    end
    return false
  end,
  talk = {
    -- MtMoonB2FSuperNerdText: once beaten his line turns on the fossils
    -- (scripts/MtMoonB2F.asm:187), which the header's flat `after` can't hold
    TEXT_MTMOONB2F_SUPER_NERD = function(game, ow, npc, done)
      if not superNerdBeaten(ow) then
        engageSuperNerd(game, ow, done)
        return
      end
      local TextBox = require("src.render.TextBox")
      local t = game.data.text
      local flags = game.save.flags
      local line = (flags.EVENT_GOT_DOME_FOSSIL or flags.EVENT_GOT_HELIX_FOSSIL)
        and (t._MtMoonB2FSuperNerdTheresAPokemonLabText
             or "Far away, on\nCINNABAR ISLAND,\nthere's a POKéMON\nLAB.")
        or (t._MtMoonB2fSuperNerdEachTakeOneText
            or "We'll each take\none!\nNo being greedy!")
      game.stack:push(TextBox.new(game, line, done))
    end,
    TEXT_MTMOONB2F_DOME_FOSSIL = mtMoonFossil(
      "DOME_FOSSIL", "MTMOONB2F_HELIX_FOSSIL", "EVENT_GOT_DOME_FOSSIL"),
    TEXT_MTMOONB2F_HELIX_FOSSIL = mtMoonFossil(
      "HELIX_FOSSIL", "MTMOONB2F_DOME_FOSSIL", "EVENT_GOT_HELIX_FOSSIL"),
  },
}

-- The ticket clerk (scripts/Museum1F.asm Museum1FScientist1Text): Y50, once.
-- Declining at the rope shoves the player one tile south (#151)
local function museumClerk(game, ow, done, onDecline)
  local TextBox = require("src.render.TextBox")
  local t = game.data.text or {}
  if game.save.flags.EVENT_BOUGHT_MUSEUM_TICKET then
    game.stack:push(TextBox.new(game,
      t._Museum1FScientist1TakePlentyOfTimeText
        or "Take your time,\nand enjoy it all!", done))
    return
  end
  -- scripts/Museum1F.asm:72
  local money = function() return game.save.money end
  game.stack:push(TextBox.new(game,
    t._Museum1FScientist1WouldYouLikeToComeInText
      or "It's ¥50 for a\nchild's ticket.\fWould you like to\ncome in?",
    nil, { money = money, choice = function(yes)
      if yes and game.save.money >= 50 then
        game.save.money = game.save.money - 50
        game.save.flags.EVENT_BOUGHT_MUSEUM_TICKET = true
        -- scripts/Museum1F.asm:106
        game.stack:push(TextBox.new(game,
          t._Museum1FScientist1ThankYouText or "Right, ¥50!\nThank you!", done,
          { money = money }))
      elseif yes then
        game.stack:push(TextBox.new(game,
          t._Museum1FScientist1DontHaveEnoughMoneyText
            or "You don't have\nenough money.", onDecline or done, { money = money }))
      else
        game.stack:push(TextBox.new(game,
          t._Museum1FScientist1ComeAgainText
            or "Come again!", onDecline or done, { money = money }))
      end
    end }))
end

M.MUSEUM_1F = {
  -- crossing the rope at (9,4)/(10,4) without a ticket calls the clerk
  -- over (Museum1FDefaultScript's coordinate check)
  onStep = function(game, ow, x, y)
    if y == 4 and (x == 9 or x == 10)
       and not game.save.flags.EVENT_BOUGHT_MUSEUM_TICKET then
      museumClerk(game, ow, nil, function()
        ow:scriptMove(ow.player, "down", 1)
      end)
      return true
    end
    return false
  end,
  talk = {
    TEXT_MUSEUM1F_SCIENTIST1 = function(game, ow, npc, done)
      museumClerk(game, ow, done)
    end,
    -- The OLD AMBER display object is plain flavor; the scientist
    -- (TEXT_MUSEUM1F_SCIENTIST2, data/scripts/flavor/museum_1f.lua) is who
    -- hands it over and hides this object, per scripts/Museum1F.asm.
    TEXT_MUSEUM1F_OLD_AMBER = function(game, ow, npc, done)
      local TextBox = require("src.render.TextBox")
      game.stack:push(TextBox.new(game,
        game.data.text._Museum1FOldAmberText or "The OLD AMBER.", done))
    end,
  },
}

local FOSSIL_MONS = {
  HELIX_FOSSIL = "OMANYTE", DOME_FOSSIL = "KABUTO", OLD_AMBER = "AERODACTYL",
}

-- Deterministic scan order mirrors FossilsList (scripts/
-- CinnabarLabFossilRoom.asm lines 43-47): DOME_FOSSIL, HELIX_FOSSIL,
-- OLD_AMBER (the old pairs()-order loop this replaced was undefined).
local FOSSIL_ORDER = { "DOME_FOSSIL", "HELIX_FOSSIL", "OLD_AMBER" }

-- fills the {PLAYER}/{RAM:...} placeholders in the extracted text
-- verbatim (text/CinnabarLabFossilRoom.asm); TextBox itself only knows
-- how to substitute {RAM:wStringBuffer}, so this has to happen first.
-- RAM placeholders resolve by buffer name from subs (SeesFossilText
-- reads both wNameBuffer and wStringBuffer), falling back to subs.ram.
local function fillFossilText(s, subs)
  s = s:gsub("{PLAYER}", subs.player or "")
  s = s:gsub("{RAM:([^}]*)}", function(name) return subs[name] or subs.ram or "" end)
  return s
end

M.CINNABAR_LAB_FOSSIL_ROOM = {
  talk = {
    -- Fossil revival quest (scripts/CinnabarLabFossilRoom.asm
    -- CinnabarLabFossilRoomScientist1Text lines 49-99, deposit flow in
    -- engine/events/cinnabar_lab.asm GiveFossilToCinnabarLab): deposit
    -- a fossil -> pending for the rest of this visit -> ready once the
    -- player leaves and re-enters the CINNABAR_ISLAND overworld map
    -- (M.CINNABAR_ISLAND.onEnter in data/scripts/story5.lua clears
    -- EVENT_LAB_STILL_REVIVING_FOSSIL there, mirroring CinnabarIsland.
    -- asm line 6) -> hand over the mon and reset the whole quest so a
    -- second fossil can be deposited later.
    --
    -- The deposit itself follows GiveFossilToCinnabarLab: a bordered
    -- top-left menu of every carried fossil (A/B watched; B backs out),
    -- then SeesFossilText with a Yes/No confirm; both cancel paths
    -- (B on the menu, NO on the confirm) share ComeAgainText.
    TEXT_CINNABARLABFOSSILROOM_SCIENTIST1 = function(game, ow, npc, done)
      local TextBox = require("src.render.TextBox")
      local t = game.data.text
      local f = game.save.flags
      local subs = { player = game.save.player.name }

      if f.EVENT_GAVE_FOSSIL_TO_LAB then
        if f.EVENT_LAB_STILL_REVIVING_FOSSIL then
          -- .check_done_reviving -> still pending this visit
          game.stack:push(TextBox.new(game,
            t._CinnabarLabFossilRoomScientist1GoForAWalkText or
            "I take a little\ntime!\fYou go for walk a\nlittle while!", done))
          return
        end
        -- STILL_REVIVING was cleared (CINNABAR_ISLAND was reloaded
        -- since the deposit): .done_reviving, lines 72-83
        local species = game.save.labFossilMon
        subs.ram = species and game.data.pokemon[species]
                   and game.data.pokemon[species].name or ""
        f.EVENT_LAB_HANDING_OVER_FOSSIL_MON = true
        game.stack:push(TextBox.new(game,
          fillFossilText(
            t._CinnabarLabFossilRoomScientist1FossilIsBackToLifeText or
            "Where were you?\fYour fossil is\nback to life!\fIt was {RAM:x}\nlike I think!",
            subs),
          function()
            if species then
              local Commands = require("src.script.Commands")
              local ctx = { save = game.save, game = game, overworld = ow }
              Commands.give_pokemon(ctx, species, 30)
              if not ctx.lastCheck then
                -- GivePokemon failed (party+box full): pokered's
                -- `jr nc, .done` leaves the quest pending so the
                -- scientist re-offers the mon next visit instead of
                -- destroying it.
                game.stack:push(TextBox.new(game,
                  t._BoxIsFullText or "Box is full!", done))
                return
              end
            end
            game.save.labFossilMon = nil
            f.EVENT_GAVE_FOSSIL_TO_LAB = nil
            f.EVENT_LAB_STILL_REVIVING_FOSSIL = nil
            f.EVENT_LAB_HANDING_OVER_FOSSIL_MON = nil
            done()
          end))
        return
      end

      -- No fossil deposited yet: the intro always plays first (.Text),
      -- then either the fossil-select menu (GiveFossilToCinnabarLab)
      -- or NoFossilsText.
      game.stack:push(TextBox.new(game,
        t._CinnabarLabFossilRoomScientist1Text or
        "Hiya!\fI am important\ndoctor!\fI study here rare\nPOKéMON fossils!\fYou! Have you a\nfossil for me?",
        function()
          -- Lab4Script_GetFossilsInBag: every carried fossil, in
          -- FossilsList order
          local carried = {}
          for _, fossil in ipairs(FOSSIL_ORDER) do
            if (game.save.inventory[fossil] or 0) > 0 then
              carried[#carried + 1] = fossil
            end
          end
          if #carried == 0 then
            game.stack:push(TextBox.new(game,
              t._CinnabarLabFossilRoomScientist1NoFossilsText or
              "No! Is too bad!", done))
            return
          end
          -- .cancelledGivingFossil: B on the menu and NO on the
          -- confirm both land here
          local function comeAgain()
            game.stack:push(TextBox.new(game,
              t._CinnabarLabFossilRoomScientist1ComeAgainText or
              "Aiyah! You come\nagain!", done))
          end
          local items = {}
          for _, fossil in ipairs(carried) do
            items[#items + 1] = {
              label = game.data.items[fossil].name,
              onSelect = function()
                -- LoadFossilItemAndMonName: wNameBuffer = item name,
                -- wStringBuffer = mon name; then .ScientistSeesFossilText
                -- with YesNoChoice (cursor starts on YES)
                local species = FOSSIL_MONS[fossil]
                local def = game.data.pokemon[species]
                subs.wNameBuffer = game.data.items[fossil].name
                subs.wStringBuffer = def and def.name or species
                game.stack:push(TextBox.new(game,
                  fillFossilText(
                    t._CinnabarLabFossilRoomScientist1SeesFossilText or
                    "Oh! That is\n{RAM:wNameBuffer}!\fIt is fossil of\n{RAM:wStringBuffer}, a\nPOKéMON that is\nalready extinct!\fMy Resurrection\nMachine will make\nthat POKéMON live\nagain!",
                    subs),
                  nil, { choice = function(yes)
                    if not yes then comeAgain() return end
                    -- YES: TakesFossilText, RemoveItemByID, GoForAWalk2,
                    -- SetEvents GAVE_FOSSIL_TO_LAB + STILL_REVIVING
                    require("src.inventory.Bag").remove(game.save, fossil, 1)
                    game.save.labFossilMon = species
                    f.EVENT_GAVE_FOSSIL_TO_LAB = true
                    f.EVENT_LAB_STILL_REVIVING_FOSSIL = true
                    game.stack:push(TextBox.new(game,
                      fillFossilText(
                        t._CinnabarLabFossilRoomScientist1TakesFossilText or
                        "So! You hurry and\ngive me that!\f{PLAYER} handed\nover {RAM:wNameBuffer}!",
                        subs),
                      function()
                        game.stack:push(TextBox.new(game,
                          t._CinnabarLabFossilRoomScientist1GoForAWalkText2 or
                          "I take a little\ntime!\fYou go for walk a\nlittle while!", done))
                      end))
                  end }))
              end,
            }
          end
          -- GiveFossilToCinnabarLab's menu: TextBoxBorder at 0,0
          -- (interior width $d, height 2 per fossil), A|B watched
          local Menu = require("src.ui.Menu")
          game.stack:push(Menu.new(game, items,
            { tx = 0, ty = 0, tw = 15, onCancel = comeAgain }))
        end))
    end,
    -- the other scientist trades SAILOR: Ponyta -> Seel
    -- (scripts/CinnabarLabFossilRoom.asm TRADE_FOR_SAILOR)
    TEXT_CINNABARLABFOSSILROOM_SCIENTIST2 = {
      { "face_player" },
      { "trade", 4, "EVENT_TRADED_PONYTA_FOR_SEEL" },
    },
  },
}

-- -------------------------------------------------------------------
-- Day-care (scripts/Daycare.asm): the boarded Pokémon earns 1 exp per
-- step; the fee is ¥100 plus ¥100 per level gained.
--
-- #118: do not raise mon.level until a paid retrieve (pokered reverts
-- wDayCareMonBoxLevel on .leaveMonInDayCare). Fold pending steps into
-- mon.exp once and clear them so a second talk cannot re-apply the same
-- walk. Fill {RAM:wNameBuffer}/{RAM:wDayCareMonName}/{NUM:...} here --
-- TextBox.TOKENS.RAM only knows wStringBuffer.
-- -------------------------------------------------------------------

local function fillDaycareText(s, subs)
  s = s:gsub("{PLAYER}", subs.player or "")
  s = s:gsub("{RAM:([^}]*)}", function(name) return subs[name] or "" end)
  -- extractor NUM spans may include flags after a comma; keep the name
  s = s:gsub("{NUM:([%w_]+)[^}]*}", function(name)
    return tostring(subs[name] or "0")
  end)
  return s
end

M.DAYCARE = {
  talk = {
    TEXT_DAYCARE_GENTLEMAN = function(game, ow, npc, done)
      local TextBox = require("src.render.TextBox")
      local t = game.data.text
      local dc = game.save.daycare
      local playerName = game.save.player and game.save.player.name or "RED"

      local function monName(mon)
        local def = game.data.pokemon[mon.species]
        return mon.nickname or (def and def.name) or mon.species
      end

      if dc and dc.mon then
        local Growth = require("src.pokemon.Growth")
        local Stats = require("src.pokemon.Stats")
        local Party = require("src.pokemon.Party")
        local mon = dc.mon
        local def = game.data.pokemon[mon.species]
        -- Apply deferred step-exp once (OverworldController only bumps
        -- daycare.steps). Clearing prevents double-count on re-talk.
        mon.exp = (mon.exp or 0) + (dc.steps or 0)
        dc.steps = 0
        -- depositLevel mirrors wDayCareMonBoxLevel: fee baseline that
        -- must survive a declined retrieve. Fall back to mon.level for
        -- older saves that predate the field.
        if dc.depositLevel == nil then dc.depositLevel = mon.level end
        local startLevel = dc.depositLevel
        local newLevel = Growth.levelForExp(def and def.growthRate, mon.exp)
        if newLevel >= 100 then
          newLevel = 100
          if def then
            mon.exp = Growth.expForLevel(def.growthRate, 100)
          end
        end
        local levelsGrown = math.max(0, newLevel - startLevel)
        local fee = 100 + levelsGrown * 100
        local name = monName(mon)
        local subs = {
          player = playerName,
          wNameBuffer = name,
          wDayCareMonName = name,
          wDayCareNumLevelsGrown = levelsGrown,
          wDayCareTotalCost = fee,
        }
        local statusText = levelsGrown > 0
          and (t._DaycareGentlemanMonHasGrownText
            or "Your {RAM:wNameBuffer}\nhas grown a lot!\fBy level, it's\ngrown by {NUM:wDayCareNumLevelsGrown, 1, 3}!\fAren't I great?")
          or (t._DaycareGentlemanMonNeedsMoreTimeText
            or "Back already?\nYour {RAM:wNameBuffer}\nneeds some more\ntime with me.")

        game.stack:push(TextBox.new(game, fillDaycareText(statusText, subs), function()
          if #game.save.party >= Party.MAX then
            game.stack:push(TextBox.new(game,
              t._DaycareGentlemanNoRoomForMonText
                or "You have no room\nfor this POKéMON!", done))
            return
          end
          game.stack:push(TextBox.new(game,
            fillDaycareText(
              t._DaycareGentlemanOweMoneyText
                or "You owe me ¥{NUM:wDayCareTotalCost, 2 | LEADING_ZEROES | LEFT_ALIGN}\nfor the return\nof this POKéMON.",
              subs),
            nil, { choice = function(yes)
              if not yes then
                -- .leaveMonInDayCare: revert any transient level bump
                mon.level = startLevel
                game.stack:push(TextBox.new(game,
                  (t._DaycareGentlemanAllRightThenText or "All right then,\n")
                    .. (t._DaycareGentlemanComeAgainText or "come again."),
                  done))
                return
              end
              if (game.save.money or 0) < fee then
                mon.level = startLevel
                game.stack:push(TextBox.new(game,
                  t._DaycareGentlemanNotEnoughMoneyText
                    or "Hey, you don't\nhave enough ¥!", done))
                return
              end
              game.save.money = game.save.money - fee
              mon.level = newLevel
              if def then
                mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
                mon.hp = mon.stats.hp
                -- Daycare.asm: WriteMonMoves with wLearningMovesFromDayCare
                local Pokemon = require("src.pokemon.Pokemon")
                Pokemon.learnMovesFromDayCare(
                  game.data, mon, def, startLevel, newLevel)
              end
              table.insert(game.save.party, mon)
              game.save.daycare = nil
              game.stack:push(TextBox.new(game,
                t._DaycareGentlemanHeresYourMonText
                  or "Thank you! Here's\nyour POKéMON!", function()
                game.stack:push(TextBox.new(game,
                  fillDaycareText(
                    t._DaycareGentlemanGotMonBackText
                      or "{PLAYER} got\n{RAM:wDayCareMonName} back!",
                    subs), done))
              end))
            end }))
        end))
        return
      end

      game.stack:push(TextBox.new(game,
        t._DaycareGentlemanIntroText
          or "I run a DAYCARE.\nWould you like me\nto raise one of\nyour POKéMON?",
        nil, { choice = function(yes)
          if not yes then
            game.stack:push(TextBox.new(game,
              t._DaycareGentlemanComeAgainText or "come again.", done))
            return
          end
          if #game.save.party < 2 then
            game.stack:push(TextBox.new(game,
              t._DaycareGentlemanOnlyHaveOneMonText
                or "You only have one\nPOKéMON with you.", done))
            return
          end
          game.stack:push(TextBox.new(game,
            t._DaycareGentlemanWhichMonText or "Which POKéMON\nshould I raise?",
            function()
              local PartyMenu = require("src.ui.PartyMenu")
              game.stack:push(PartyMenu.new(game, {
                pickOnly = true,
                onSwitch = function(mon)
                  for i, m in ipairs(game.save.party) do
                    if m == mon then table.remove(game.save.party, i) break end
                  end
                  local name = monName(mon)
                  -- depositLevel = wDayCareMonBoxLevel at deposit time
                  game.save.daycare = {
                    mon = mon, steps = 0, depositLevel = mon.level,
                  }
                  game.stack:push(TextBox.new(game,
                    fillDaycareText(
                      t._DaycareGentlemanWillLookAfterMonText
                        or "Fine, I'll look\nafter {RAM:wNameBuffer}\nfor a while.",
                      { player = playerName, wNameBuffer = name }),
                    function()
                      game.stack:push(TextBox.new(game,
                        t._DaycareGentlemanComeSeeMeInAWhileText
                          or "Come see me in\na while.", done))
                    end))
                end,
              }))
            end))
        end }))
    end,
  },
}

return M
