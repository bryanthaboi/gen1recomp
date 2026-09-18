-- Post-faint EXP presentation: gained → bar → level-up → learn moves (ROM learnset).

local Anim = require("src.core.game3.battle.anim")
local State = require("src.core.game3.battle.state")
local LearnMove = require("src.core.game3.battle.learn_move")
local Pokemon = require("src.core.game3.pokemon")

local ExpSeq = {}

ExpSeq._steps = nil
ExpSeq._i = 1
ExpSeq._waiting = false
ExpSeq._waitingMsg = false
ExpSeq._pushMsg = nil
ExpSeq._askYesNo = nil
ExpSeq._askForget = nil
ExpSeq._headless = false
ExpSeq._leveled = nil -- {[partyIndex]=true}
ExpSeq._pendingStatGrowth = nil

function ExpSeq.reset()
  ExpSeq._steps = nil
  ExpSeq._i = 1
  ExpSeq._waiting = false
  ExpSeq._waitingMsg = false
  ExpSeq._pushMsg = nil
  ExpSeq._askYesNo = nil
  ExpSeq._askForget = nil
  ExpSeq._leveled = nil
  ExpSeq._pendingStatGrowth = nil
  ExpSeq._lvlAnimWait = false
  local okA, Audio = pcall(require, "src.core.game3.audio")
  local okS, SE = pcall(require, "src.core.game3.se_ids")
  if okA and okS and Audio.stopSe and SE and SE.SE_EXP then
    Audio.stopSe(SE.SE_EXP)
  end
  local okSG, StatGrowth = pcall(require, "src.ui.game3.stat_growth")
  if okSG and StatGrowth and StatGrowth.close then
    StatGrowth.close()
  end
  LearnMove.reset()
end

function ExpSeq.busy()
  local okSG, StatGrowth = pcall(require, "src.ui.game3.stat_growth")
  if okSG and StatGrowth and StatGrowth.isOpen and StatGrowth.isOpen() then
    return true
  end
  return ExpSeq._steps ~= nil or LearnMove.busy()
end

function ExpSeq.leveledSet()
  return ExpSeq._leveled
end

local function finish()
  ExpSeq._steps = nil
  ExpSeq._i = 1
  ExpSeq._waiting = false
  ExpSeq._waitingMsg = false
  local okA, Audio = pcall(require, "src.core.game3.audio")
  local okS, SE = pcall(require, "src.core.game3.se_ids")
  if okA and okS and Audio.stopSe and SE and SE.SE_EXP then
    Audio.stopSe(SE.SE_EXP)
  end
end

local function advance()
  ExpSeq._waiting = false
  ExpSeq._waitingMsg = false
  ExpSeq._i = ExpSeq._i + 1
end

local function mon_name(entry)
  if entry.battler then return State.displayName(entry.battler) end
  return Pokemon.displayMonName(entry.mon)
end

--- awards: Experience.awardFoe results
--- opts: pushMsg, askYesNo, askForget, headless, thenMsgs
function ExpSeq.begin(awards, pushMsg, thenMsgs, opts)
  opts = opts or {}
  ExpSeq.reset()
  ExpSeq._pushMsg = pushMsg or opts.pushMsg
  ExpSeq._askYesNo = opts.askYesNo
  ExpSeq._askForget = opts.askForget
  ExpSeq._battleText = opts.battleText and true or false
  ExpSeq._headless = opts.headless and true or false
  ExpSeq._leveled = {}

  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data }
  end

  for _, entry in ipairs(awards or {}) do
    local mon = entry.mon
    local result = entry.result or {}
    local name = mon_name(entry)
    local gained = result.gained or entry.amount or 0
    local pi = entry.partyIndex or 1
    local isBench = (entry.battler == nil)
    local key = "player"
    if opts.double and entry.battler and entry.battler.id ~= nil then key = entry.battler.id end
    if gained > 0 then
      -- pokefirered/src/battle_message.c:53
      add("msg", { text = name .. " gained" .. (entry.boosted and " a boosted" or "") .. "\n" .. tostring(gained) .. " EXP. Points!" })
      for _, step in ipairs(result.steps or {}) do
        -- pokefirered/src/battle_controller_player.c:1034
        if not isBench and not opts.double then
          add("exp", {
            side = "player",
            level = step.level,
            fromRatio = step.fromRatio,
            toRatio = step.toRatio,
          })
        end
        if step.grewTo then
          ExpSeq._leveled[pi] = true
          add("level", {
            side = key,
            isBench = isBench,
            mon = mon,
            level = step.grewTo,
            hp = step.hp or (mon and tonumber(mon.hp)),
            maxHp = step.maxHp or (mon and tonumber(mon.maxHp)),
            oldStats = step.oldStats,
            newStats = step.newStats,
            text = name .. " grew to\nLV. " .. tostring(step.grewTo) .. "!",
          })
          -- ROM learnset moves at this exact level
          local moves = Pokemon.movesLearnedAt(
            tonumber(mon and (mon.species or mon.speciesId)),
            step.grewTo
          )
          for _, mv in ipairs(moves) do
            add("learn", {
              mon = mon,
              moveId = mv,
              displayName = name,
              partyIndex = pi,
            })
          end
        end
      end
    end
  end

  for _, t in ipairs(thenMsgs or opts.thenMsgs or {}) do
    add("msg", { text = t })
  end

  if #steps == 0 then
    finish()
    return false
  end
  ExpSeq._steps = steps
  ExpSeq._i = 1
  ExpSeq._waiting = false
  ExpSeq._waitingMsg = false
  return true
end

local function run_step(step)
  if not step then
    finish()
    return
  end
  local kind = step.kind
  local d = step.data or {}

  if kind == "msg" then
    if ExpSeq._pushMsg and d.text then
      ExpSeq._pushMsg(d.text)
    end
    if not ExpSeq._headless then
      ExpSeq._waiting = true
      ExpSeq._waitingMsg = true
      return
    end
    advance()
    return
  end

  if kind == "exp" then
    ExpSeq._waiting = true
    local p = Anim.present(d.side or "player")
    if p and d.level then p.displayLevel = d.level end
    do
      local Audio = require("src.core.game3.audio")
      local SE = require("src.core.game3.se_ids")
      Audio.playSe(SE.SE_EXP)
    end
    Anim.tweenExp(d.side or "player", d.fromRatio, d.toRatio, {
      level = d.level,
      onComplete = function()
        local okA, Audio = pcall(require, "src.core.game3.audio")
        local okS, SE = pcall(require, "src.core.game3.se_ids")
        if okA and okS and Audio.stopSe and SE and SE.SE_EXP then
          Audio.stopSe(SE.SE_EXP)
        end
        advance()
      end,
    })
    if not Anim.busy() and ExpSeq._waiting then
      local okA, Audio = pcall(require, "src.core.game3.audio")
      local okS, SE = pcall(require, "src.core.game3.se_ids")
      if okA and okS and Audio.stopSe and SE and SE.SE_EXP then
        Audio.stopSe(SE.SE_EXP)
      end
      advance()
    end
    return
  end

  if kind == "level" then
    if not d.isBench and not ExpSeq._headless and not d._lvlAnim then
      -- pokefirered/src/battle_controller_player.c:1143
      d._lvlAnim = true
      local side = d.side or "player"
      local bid = (type(side) == "number") and side or nil
      if bid then side = State.sideOf(bid) end
      ExpSeq._lvlAnimWait = true
      Anim.launchSpecial("LVL_UP", {
        attackerSide = side,
        targetSide = side,
        attackerId = bid,
        targetId = bid,
        onEnd = function() ExpSeq._lvlAnimWait = false end,
      })
      return
    end
    if not d.isBench then
      local p = Anim.present(d.side or "player")
      if p then
        p.displayLevel = d.level
        p.displayExp = 0
        if d.maxHp then
          p.displayMaxHp = d.maxHp
          p.displayHp = d.hp or d.maxHp
        end
      end
    end
    do
      local Audio = require("src.core.game3.audio")
      Audio.playFanfare(Audio.role("levelUp") or 257)
    end
    if ExpSeq._pushMsg and d.text then
      ExpSeq._pushMsg(d.text)
    end
    if not ExpSeq._headless then
      ExpSeq._waiting = true
      ExpSeq._waitingMsg = true
      ExpSeq._pendingStatGrowth = (d.oldStats and d.newStats) and {
        mon = d.mon,
        oldStats = d.oldStats,
        newStats = d.newStats,
      } or nil
      return
    end
    advance()
    return
  end

  if kind == "learn" then
    ExpSeq._waiting = true
    LearnMove.begin({
      mon = d.mon,
      moveId = d.moveId,
      displayName = d.displayName,
      pushMsg = ExpSeq._pushMsg,
      askYesNo = ExpSeq._askYesNo,
      askForget = ExpSeq._askForget,
      headless = ExpSeq._headless,
      battleText = ExpSeq._battleText,
      onDone = function()
        advance()
      end,
    })
    -- Free-slot teach may finish synchronously
    if not LearnMove.busy() and ExpSeq._waiting then
      if ExpSeq._waiting then advance() end
    end
    return
  end

  advance()
end

function ExpSeq.update()
  if LearnMove.busy() then
    LearnMove.pump()
    return false
  end
  if not ExpSeq._steps then return true end

  if ExpSeq._lvlAnimWait then
    if Anim.busy() then return false end
    ExpSeq._lvlAnimWait = false
  end

  if ExpSeq._waitingMsg then
    local Ui = package.loaded["src.core.game3.battle.ui"]
    local pending = false
    if Ui then
      if Ui.dialogPending then
        pending = Ui.dialogPending()
      elseif not Ui._headless then
        pending = (Ui._showing == true) or (Ui._queue and #Ui._queue > 0)
      end
    end
    if pending then
      return false
    end
    ExpSeq._waitingMsg = false
    if ExpSeq._pendingStatGrowth and not ExpSeq._headless then
      local sg = ExpSeq._pendingStatGrowth
      ExpSeq._pendingStatGrowth = nil
      local okSG, StatGrowth = pcall(require, "src.ui.game3.stat_growth")
      if okSG and StatGrowth and StatGrowth.open then
        ExpSeq._waiting = true
        StatGrowth.open(sg.mon, sg.oldStats, sg.newStats, function()
          ExpSeq._waiting = false
          advance()
        end)
        return false
      end
    end
    ExpSeq._waiting = false
    advance()
  end

  if ExpSeq._waiting then
    if LearnMove.busy() then
      return false
    end
    if not Anim.busy() then
      advance()
    else
      return false
    end
  end
  local step = ExpSeq._steps[ExpSeq._i]
  if not step then
    finish()
    return true
  end
  run_step(step)
  return false
end

return ExpSeq
