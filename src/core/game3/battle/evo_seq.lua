-- Post-win evolution presentation (pret TryEvolvePokemon).
-- Handles headless fast-path and visual EvolutionScene chaining.

local Evolution = require("src.core.game3.evolution")
local LearnMove = require("src.core.game3.battle.learn_move")
local Pokemon = require("src.core.game3.pokemon")

local EvoSeq = {}

EvoSeq._steps = nil
EvoSeq._i = 1
EvoSeq._waiting = false
EvoSeq._pushMsg = nil
EvoSeq._askYesNo = nil
EvoSeq._askForget = nil
EvoSeq._headless = false
EvoSeq._session = nil

function EvoSeq.reset()
  EvoSeq._steps = nil
  EvoSeq._i = 1
  EvoSeq._waiting = false
  EvoSeq._pushMsg = nil
  EvoSeq._session = nil
  LearnMove.reset()
end

function EvoSeq.busy()
  local okEv, EvolutionScene = pcall(require, "src.ui.game3.evolution_scene")
  if okEv and EvolutionScene and EvolutionScene.isOpen and EvolutionScene.isOpen() then
    return true
  end
  return EvoSeq._steps ~= nil or LearnMove.busy()
end

local function finish()
  local cb = EvoSeq._onDone
  EvoSeq._steps = nil
  EvoSeq._i = 1
  EvoSeq._waiting = false
  EvoSeq._onDone = nil
  if cb then cb() end
end

local function advance()
  EvoSeq._waiting = false
  EvoSeq._i = EvoSeq._i + 1
end

--- pending: Evolution.pending() results
function EvoSeq.begin(pending, opts)
  opts = opts or {}
  EvoSeq.reset()
  EvoSeq._pushMsg = opts.pushMsg
  EvoSeq._askYesNo = opts.askYesNo
  EvoSeq._askForget = opts.askForget
  EvoSeq._headless = opts.headless and true or false
  EvoSeq._session = opts.session
  EvoSeq._onDone = opts.onDone

  local steps = {}
  for _, entry in ipairs(pending or {}) do
    steps[#steps + 1] = entry
  end

  if #steps == 0 then
    finish()
    return false
  end
  EvoSeq._steps = steps
  EvoSeq._i = 1
  return true
end

local function run_step(entry)
  if not entry then
    finish()
    return
  end

  local mon = entry.mon
  local toSpecies = entry.toSpecies or entry.target
  local fromName = Pokemon.displayMonName(mon)
  local intoName = Pokemon.name(toSpecies) or "POKéMON"

  if EvoSeq._headless then
    if EvoSeq._pushMsg then
      EvoSeq._pushMsg("What?\n" .. fromName .. " is evolving!")
    end
    Evolution.apply(mon, toSpecies, EvoSeq._session)
    if EvoSeq._pushMsg then
      EvoSeq._pushMsg("Congratulations! Your " .. fromName .. "\nevolved into " .. intoName .. "!")
    end
    local lv = tonumber(mon and mon.level) or 1
    EvoSeq._waiting = true
    local started = LearnMove.beginQueue(mon, { lv }, {
      displayName = Pokemon.displayMonName(mon),
      pushMsg = EvoSeq._pushMsg,
      askYesNo = EvoSeq._askYesNo,
      askForget = EvoSeq._askForget,
      headless = true,
      onDone = function()
        advance()
      end,
    })
    if not started then
      advance()
    end
    return
  end

  -- Visual mode: launch dedicated EvolutionScene
  local okEv, EvolutionScene = pcall(require, "src.ui.game3.evolution_scene")
  if okEv and EvolutionScene and EvolutionScene.start then
    local Audio = require("src.core.game3.audio")
    local victorySong = (Audio._currentSong and Audio._currentSong.id) or Audio.role("victoryWild") or 311
    EvoSeq._waiting = true
    EvolutionScene.start(mon, toSpecies, {
      canStop = true,
      headless = EvoSeq._headless,
      session = EvoSeq._session,
      isBattle = true,
      savedSong = victorySong,
      onDone = function(result)
        advance()
      end,
    })
  else
    -- Fallback
    Evolution.apply(mon, toSpecies, EvoSeq._session)
    advance()
  end
end

function EvoSeq.update()
  local okEv, EvolutionScene = pcall(require, "src.ui.game3.evolution_scene")
  if okEv and EvolutionScene and EvolutionScene.isOpen and EvolutionScene.isOpen() then
    return false
  end

  if LearnMove.busy() then
    LearnMove.pump()
    return false
  end

  if not EvoSeq._steps then return true end

  if EvoSeq._waiting then
    return false
  end

  local entry = EvoSeq._steps[EvoSeq._i]
  if not entry then
    finish()
    return true
  end

  run_step(entry)
  return false
end

return EvoSeq
