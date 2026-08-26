-- The Safari Zone game entrance (scripts/SafariZoneGate.asm).
--
-- Stepping on (3,2)/(4,2) next to the worker fires the join prompt
-- (.PlayerNextToSafariZoneWorker1CoordsArray).  Paying ¥500 hands over
-- 30 SAFARI BALLs and starts the 502-step game
-- (SafariZoneGateWouldYouLikeToJoinScript: wSafariSteps = 502,
-- wNumSafariBalls = SAFARI_BALLS_RECEIVED), then auto-walks the player
-- up through the north warp into the zone.  Declining walks you back
-- so you can't slip past.  Returning to the gate ends the game, the
-- worker takes the leftover balls back and the auto-walk drops you 3
-- cells below the warp you came in by (#540).
--
-- Step/ball bookkeeping lives in src/world/OverworldController.lua
-- (safariStep/safariGameOver, from
-- engine/events/hidden_events/safari_game.asm); the in-battle
-- BALL/BAIT/ROCK/RUN game is src/battle/BattleState.lua makeSafari.

local M = {}

local FEE = 500
local BALLS = 30
local STEPS = 502

-- SafariZoneGateSafariZoneWorker1WouldYouLikeToJoinText .success closes with
-- `ld a, PAD_UP / ld c, 3 / SafariZoneEntranceAutoWalk`: paying walks the
-- player up out of the gate and through the north warp, it is never left to
-- the player.  EVENT_IN_SAFARI_ZONE is already set when that walk runs, so
-- the two gate steps taken before the warp fires are charged against
-- wSafariSteps (home/overworld.asm:307-310) -- which is why the counter
-- reads 500/500 on arrival even though the script wrote 502 (#540).  The
-- port's counter only runs on the nine interior maps (FieldDefaults
-- safari.stepMaps, OverworldState:inSafariStepZone), so charge those two
-- steps here instead.
local function walkIntoZone(game, ow)
  local p = ow.player
  -- only from the two trigger cells in front of the worker, which are the
  -- columns the north warps sit on; a player who paid after TALKING to him
  -- from somewhere else walks in on their own, as they do today
  local w = p.cellY == 2 and ow.map:warpAtCell(p.cellX, 0) or nil
  if not w then return end
  ow:scriptMove(p, "up", 2, function()
    local st = game.save.safari
    if st then st.steps = st.steps - 2 end
    -- scripted steps skip onStepComplete (and with it CheckWarpsNoCollision),
    -- so take that warp explicitly once the walk lands on it
    ow:takeWarp(w.def)
  end)
end

local function startGame(game, ow, t, done, balls, introText)
  game.save.safari = { balls = balls or BALLS, steps = STEPS }
  game.save.safariNags = nil
  local TextBox = require("src.render.TextBox")
  local paid = introText
    or (t._SafariZoneGateSafariZoneWorker1ThatllBe500PleaseText
        or "That'll be ¥500\nplease!\f{PLAYER} received\n30 SAFARI BALLs!")
       :gsub("{NUM:[^}]*}", "500")
  paid = paid:gsub("{PLAYER}", game.save.player.name)
  local pa = t._SafariZoneGateSafariZoneWorker1CallYouOnThePAText
             or "\fWe'll call you on\nthe PA when you\nrun out of time\nor SAFARI BALLs!"
  local luck = t._SafariZoneGateSafariZoneWorker1GoodLuckText or "Good Luck!"
  game.stack:push(TextBox.new(game, paid .. pa .. "\f" .. luck, function()
    if done then done() end
    walkIntoZone(game, ow)
  end))
end

-- Yellow's soft-lock fix (scripts/SafariZoneGate_2.asm): a player short of
-- the full fee still gets in.
--   0 < money < 500: SafariZoneEntranceCalculateLowCostAdmission takes
--   everything and hands over min(money/23 + 1, 29) balls.
--   money == 0: SafariZoneEntranceGetLowCostAdmissionText nags four times
--   (LowCostText5/6/7/8), then relents -- free entry, one ball.
local function yellowLowCost(game, ow, t, done, back)
  local TextBox = require("src.render.TextBox")
  if game.save.money > 0 then
    local balls = math.min(math.floor(game.save.money / 23) + 1, 29)
    game.save.money = 0
    local intro =
      (t._SafariZoneGateSafariZoneWorker1NotEnoughMoneyText
       or "Oops! Not enough\nmoney!")
      .. (t._SafariZoneLowCostText1
          or "\fOh, all right, pay\nme what you have.")
      .. "\f" .. (t._SafariZoneLowCostText2
                  or "But, I can't give\nyou all 30 BALLs.")
    startGame(game, ow, t, done, balls, intro)
    return
  end
  local nag = game.save.safariNags or 0
  game.save.safariNags = nag + 1
  if nag >= 3 then
    local intro =
      (t._SafariZoneLowCostText8 or "Read my lips, NO!\nGet it?")
      .. (t._SafariZoneLowCostText3
          or "\fYou're persistent,\naren't you?\fOK, you can go in\nfor free, but\njust this once!")
    startGame(game, ow, t, done, 1, intro)
    return
  end
  local nags = {
    t._SafariZoneLowCostText5 or "I'm sorry, but you\nhave to pay to\nenter.",
    t._SafariZoneLowCostText6 or "You can't enter\nwithout paying!",
    t._SafariZoneLowCostText7 or "I said, no money,\nno entry!",
  }
  back(nags[nag + 1])
end

local function joinPrompt(game, ow, done)
  done = done or function() end
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local t = game.data.text
  local back = function(text)
    game.stack:push(TextBox.new(game, text, function()
      ow:scriptMove(ow.player, "down", 1, done, { collide = true })
    end))
  end
  game.stack:push(TextBox.new(game,
    t._SafariZoneGateSafariZoneWorker1WouldYouLikeToJoinText
    or "For just ¥500 you\ncan join the hunt!\fWould you like to\njoin the hunt?",
    function()
      game.stack:push(ChoiceBox.new(game, function(yes)
        if not yes then
          back(t._SafariZoneGateSafariZoneWorker1PleaseComeAgainText
               or "OK! Please come\nagain!")
        elseif game.save.money < FEE then
          if require("src.core.GameVersion").isYellow() then
            yellowLowCost(game, ow, t, done, back)
          else
            back(t._SafariZoneGateSafariZoneWorker1NotEnoughMoneyText
                 or "Oops! Not enough\nmoney!")
          end
        else
          game.save.money = game.save.money - FEE
          startGame(game, ow, t, done)
        end
      end))
    end))
end

M.SAFARI_ZONE_GATE = {
  talk = {
    TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1 = function(game, ow, npc, done)
      local TextBox = require("src.render.TextBox")
      local t = game.data.text
      if game.save.safari then
        game.stack:push(TextBox.new(game,
          t._SafariZoneGateSafariZoneWorker1GoodLuckText or "Good Luck!", done))
        return
      end
      game.stack:push(TextBox.new(game,
        t._SafariZoneGateSafariZoneWorker1Text or "Welcome to the\nSAFARI ZONE!",
        function() joinPrompt(game, ow, done) end))
    end,
  },

  -- the join trigger cells in front of the worker
  onStep = function(game, ow, x, y)
    if y ~= 2 or (x ~= 3 and x ~= 4) then return false end
    if game.save.safari then return false end -- paid, walking in
    joinPrompt(game, ow, nil)
    return true
  end,

  -- arriving back from the zone (the north warps): the worker asks
  -- "Leaving early?" -- yes ends the game and takes the leftover balls,
  -- no walks you back into the zone
  onEnter = function(game, ow)
    if not game.save.safari or ow.player.cellY > 1 then return end
    -- QUEUED, never pushed: onEnter runs inside the arriving warp's
    -- Transition midpoint, and Transition:finish pops whatever is on top
    -- the same frame (Timing.WARP_FADE_IN is 0) -- so a box pushed here is
    -- swallowed, and on a build where it survived it drew over a screen
    -- still faded to black (#540).  Same contract as M.HALL_OF_FAME in
    -- data/scripts/story.lua.
    --
    -- SafariZoneGateLeavingSafariScript .leaving_early: YES prints the
    -- return-balls text, faces the player down and runs
    -- SafariZoneEntranceAutoWalk with `PAD_DOWN, c = 3`, landing on the
    -- counter row 3 cells below the warp you came in by; NO prints
    -- "Good Luck!" and walks one step back up through that same warp.
    local rightSide = ow.player.cellX ~= 3
    local dest = game.data.maps.SAFARI_ZONE_CENTER.warps[rightSide and 2 or 1]
    ow:queueScript({
      { "ask", "_SafariZoneGateSafariZoneWorker1LeavingEarlyText" },
      { "jump_if_false", "stay" },
      -- the port never reaches SafariZoneGateLeavingSafariScript's own
      -- GOOD_HAUL_COME_AGAIN branch (safariGameOver warps straight to the
      -- counter), so the sign-off rides on this path
      { "show_text", "_SafariZoneGateSafariZoneWorker1ReturnSafariBallsText" },
      { "show_text", "_SafariZoneGateSafariZoneWorker1GoodHaulComeAgainText" },
      -- no value: set_field assigns nil, which is how save.safari is cleared
      { "set_field", "safari" },
      -- move_player runs through scriptMove, which skips onStepComplete, so
      -- walking back down past (x,2) cannot re-fire the join trigger
      { "move_player", "down", 3 },
      { "jump", "end" },
      { "label", "stay" },
      { "show_text", "_SafariZoneGateSafariZoneWorker1GoodLuckText" },
      { "warp", "SAFARI_ZONE_CENTER", dest.x, dest.y, "up" },
    })
  end,
}

return M
