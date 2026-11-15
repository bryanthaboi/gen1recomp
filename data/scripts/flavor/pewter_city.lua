-- Pewter City flavor dialogue (pokered/scripts/PewterCity.asm).
-- PewterCity_TextPointers text_asm bodies for the SUPER_NERD1 museum
-- guide and SUPER_NERD2 garden nerd.
--
-- The YOUNGSTER's gym escort (talk + east-exit onStep) lives in
-- story5.lua; SUPER_NERD1's museum escort (scripts/PewterCity.asm:47-113)
-- is below.

local M = {}

local function text(game) return game.data.text end

local function push(game, s, done)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, s, done))
end

-- PrintText on a text_end string returns with the box still drawn and
-- YesNoChoice then draws the menu above it (InitYesNoTextBoxParameters,
-- engine/menus/text_box.asm); no A press clears the question first.  Ride
-- TextBox's opts.choice, the same as Commands.ask (#854).
local function ask(game, s, cb)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, s, nil, { choice = cb }))
end

-- RLEList_PewterMuseumGuy (engine/overworld/auto_movement.asm:199-204)
local museumGuySteps = {
  "up", "up", "up", "up", "up", "up",
  "left", "left", "left", "left", "left", "left", "left", "left",
  "left", "left", "left", "left", "left",
  "up", "up", "up",
  "left",
}

-- RLEList_PewterMuseumPlayer (engine/overworld/auto_movement.asm:192-197)
local museumPlayerRle = {
  "NO",
  "up", "up", "up",
  "left", "left", "left", "left", "left", "left", "left", "left",
  "left", "left", "left", "left", "left",
  "up", "up", "up", "up", "up", "up",
}

-- PewterMuseumGuyCoords (engine/events/pewter_guys.asm:58-75)
local museumPreambles = {
  ["27,18"] = { "up", "up" },
  ["27,16"] = { "right", "left" },
  ["26,17"] = { "up", "right" },
  ["28,17"] = { "up", "left" },
}

-- PewterGuys (engine/events/pewter_guys.asm:1-49), same transform as
-- pewterEscort.playerPlan in story5.lua
local function museumPlan(x, y)
  local pre = museumPreambles[x .. "," .. y]
  if not pre then return nil end
  local buf = {}
  for i, d in ipairs(museumPlayerRle) do buf[i] = d end
  buf[#buf] = pre[1]
  for i = 2, #pre do buf[#buf + 1] = pre[i] end
  local path = {}
  for i = #buf, 1, -1 do path[#path + 1] = buf[i] end
  local head = 0
  while path[head + 1] == "NO" do head = head + 1 end
  local tail = #path
  while tail > head and path[tail] == "NO" do tail = tail - 1 end
  local steps = {}
  for i = head + 1, tail do steps[#steps + 1] = path[i] end
  return { steps = steps, guyHeadStart = math.floor(head / 8) }
end

-- PewterCitySuperNerd1ShowsPlayerMuseumScript (scripts/PewterCity.asm:47-113)
local function museumEscortWalk(game, ow)
  if ow.runner:isRunning() or #ow.scriptMoves > 0 then return false end
  local plan = museumPlan(ow.player.cellX, ow.player.cellY)
  if not plan then return false end
  local Music = require("src.core.Music")
  local t = text(game)
  local guy = ow:npcByIndex(3) -- PEWTERCITY_SUPER_NERD1
  local head = plan.guyHeadStart

  -- SetSpritePosition2 + ShowObject back on his spawn (27,17), the same
  -- snap walkHome does in story5.lua (scripts/PewterCity.asm:102-113)
  local function walkOut()
    if not guy then return end
    local i = 0
    local function tick()
      i = i + 1
      if i > 4 then
        guy.cellX, guy.cellY = 27, 17
        guy.px, guy.py = 27 * 16, 17 * 16
        guy.moving = false
        guy.targetX, guy.targetY = nil, nil
        guy.facing = "down"
        return
      end
      ow:scriptMove(guy, "down", 1, tick)
    end
    tick()
  end

  -- SetSpritePosition1 pins him beside the museum door (map (17,12) minus
  -- the +4 border offset = (13,8)), then MovementData_PewterMuseumGuyExit
  local function afterWalk()
    if guy then
      guy.stepFrames = nil
      guy.cellX, guy.cellY = 13, 8
      guy.px, guy.py = 13 * 16, 8 * 16
      guy.moving = false
      guy.targetX, guy.targetY = nil, nil
      guy.facing = "up"
    end
    Music.playMap(game.data, "PEWTER_CITY")
    push(game, t._PewterCitySuperNerd1ItsRightHereText, walkOut)
  end

  local function lockstep()
    local i = 0
    local function tick()
      i = i + 1
      local ps = plan.steps[i]
      if not ps then
        afterWalk()
        return
      end
      local gs = museumGuySteps[head + i]
      if guy and gs then ow:scriptMove(guy, gs, 1) end
      ow:scriptMove(ow.player, ps, 1, tick)
    end
    tick()
  end

  -- engine/overworld/movement.asm:737 (DoScriptedNPCMovement)
  if guy then
    guy.stepFrames = ow.player.stepFramesCur or ow.player.stepFrames
  end
  Music.play(game.data, "Music_MuseumGuy")
  if guy and head > 0 then
    local h = 0
    local function headTick()
      h = h + 1
      if h > head then lockstep(); return end
      ow:scriptMove(guy, museumGuySteps[h], 1, headTick)
    end
    headTick()
  else
    lockstep()
  end
  return true
end

M.PEWTER_CITY = {
  museumEscort = { plan = museumPlan, guySteps = museumGuySteps },
  talk = {
    -- PewterCitySuperNerd1Text (scripts/PewterCity.asm:209-237): YES ->
    -- fossils comment, NO -> "you have to go" and the museum escort
    TEXT_PEWTERCITY_SUPER_NERD1 = function(game, ow, npc, done)
      local t = text(game)
      ask(game, t._PewterCitySuperNerd1DidYouCheckOutMuseumText, function(yes)
        if yes then
          push(game, t._PewterCitySuperNerd1WerentThoseFossilsAmazingText, done)
        else
          push(game, t._PewterCitySuperNerd1YouHaveToGoText, function()
            museumEscortWalk(game, ow)
            if done then done() end
          end)
        end
      end)
    end,

    -- PewterCitySuperNerd2Text (scripts/PewterCity.asm): asks if you
    -- know what he's doing; YES -> "that's right", NO -> reveals he's
    -- spraying Repel to keep Pokemon out of his garden.
    TEXT_PEWTERCITY_SUPER_NERD2 = function(game, ow, npc, done)
      local t = text(game)
      ask(game, t._PewterCitySuperNerd2DoYouKnowWhatImDoingText, function(yes)
        if yes then
          push(game, t._PewterCitySuperNerd2ThatsRightText, done)
        else
          push(game, t._PewterCitySuperNerd2ImSprayingRepelText, done)
        end
      end)
    end,

  },
}

return M
