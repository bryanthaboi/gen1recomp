-- In-battle / post-battle learn-move flow (pret handlelearnnewmove).
-- Driven by ROM learnsets via Pokemon.movesLearnedAt.
-- Choices open only after the message queue is idle (see LearnMove.pump).

local Pokemon = require("src.core.game3.pokemon")
local Strings = require("src.core.Strings")

local LearnMove = {}

LearnMove._active = false
LearnMove._mon = nil
LearnMove._moveId = nil
LearnMove._name = nil
LearnMove._moveName = nil
LearnMove._pushMsg = nil
LearnMove._askYesNo = nil
LearnMove._askForget = nil
LearnMove._onDone = nil
LearnMove._headless = false
LearnMove._waitingChoice = false
LearnMove._forgetSlots = nil

function LearnMove.reset()
  LearnMove._active = false
  LearnMove._mon = nil
  LearnMove._moveId = nil
  LearnMove._name = nil
  LearnMove._moveName = nil
  LearnMove._pushMsg = nil
  LearnMove._askYesNo = nil
  LearnMove._askForget = nil
  LearnMove._onDone = nil
  LearnMove._waitingChoice = false
  LearnMove._forgetSlots = nil
  LearnMove._battleText = false
  LearnMove._relearner = false
  LearnMove._queue = nil
  LearnMove._queueIdx = 0
  LearnMove._queueOpts = nil
end

function LearnMove.busy()
  return LearnMove._active == true
end

function LearnMove.waitingChoice()
  return LearnMove._waitingChoice == true
end

local function finish(learned)
  local cb = LearnMove._onDone
  LearnMove._active = false
  LearnMove._mon = nil
  LearnMove._moveId = nil
  LearnMove._waitingChoice = false
  LearnMove._onDone = nil
  -- Leave _queue / _queueOpts for beginQueue's onDone → queue_next
  if cb then cb(learned == true) end
end

local function say(text, cb)
  if LearnMove._pushMsg and text then
    LearnMove._pushMsg(text, cb)
  elseif cb then
    cb()
  end
end

local function move_name(moveId)
  return Pokemon.moveName(moveId) or ("MOVE " .. tostring(moveId))
end

local open_delete_prompt
local open_stop_prompt
local open_forget_list
local ask_to_learn

local function T(battle, field, relearner)
  if LearnMove._relearner then return relearner or field end
  if LearnMove._battleText then return battle end
  return field
end

local function did_not_learn_text()
  -- pokefirered/src/battle_message.c:63
  return T(Strings("%s did not learn\n%s.", LearnMove._name, LearnMove._moveName),
    Strings("%s did not learn the\nmove %s.", LearnMove._name, LearnMove._moveName))
end

function ask_to_learn()
  if LearnMove._relearner then
    -- pokefirered/src/strings.c:1259
    say(Strings("%s is trying to learn\n%s.", LearnMove._name, LearnMove._moveName), function()
      say(Strings("But %s can't learn more\nthan four moves.", LearnMove._name), function()
        open_delete_prompt()
      end)
    end)
    return
  end
  if LearnMove._battleText then
    -- pokefirered/data/battle_scripts_1.s:3124
    say(Strings("%s is trying to\nlearn %s.", LearnMove._name, LearnMove._moveName), function()
      say(Strings("But, %s can't learn\nmore than four moves.", LearnMove._name), function()
        open_delete_prompt()
      end)
    end)
    return
  end
  say(Strings("%s wants to learn the\nmove %s.", LearnMove._name, LearnMove._moveName), function()
    say(Strings("However, %s already\nknows four moves.", LearnMove._name), function()
      open_delete_prompt()
    end)
  end)
end

function open_delete_prompt()
  if LearnMove._headless or not LearnMove._askYesNo then
    say(Strings("%s did not learn\n%s.", LearnMove._name, LearnMove._moveName), function()
      finish(false)
    end)
    return
  end
  LearnMove._waitingChoice = true
  -- pokefirered/src/battle_message.c:60
  LearnMove._askYesNo(T(Strings("Delete a move to make\nroom for %s?", LearnMove._moveName),
    Strings("Should a move be deleted and\nreplaced with %s?", LearnMove._moveName),
    Strings("Delete an older move to make\nroom for %s?", LearnMove._moveName)), function(yes)
    LearnMove._waitingChoice = false
    if not yes then
      open_stop_prompt()
      return
    end
    if LearnMove._relearner then
      -- pokefirered/src/learn_move.c:562
      say(Strings("Which move should be forgotten?"), function()
        open_forget_list()
      end)
      return
    end
    open_forget_list()
  end)
end

function open_stop_prompt()
  if LearnMove._headless or not LearnMove._askYesNo then
    say(did_not_learn_text(), function()
      finish(false)
    end)
    return
  end
  LearnMove._waitingChoice = true
  -- pokefirered/src/battle_message.c:62
  LearnMove._askYesNo(T(Strings("Stop learning\n%s?", LearnMove._moveName),
    Strings("Stop trying to teach\n%s?", LearnMove._moveName),
    Strings("Stop learning %s?", LearnMove._moveName)), function(stop)
    LearnMove._waitingChoice = false
    if stop then
      if LearnMove._relearner then
        -- pokefirered/src/learn_move.c:583
        finish(false)
        return
      end
      say(did_not_learn_text(), function()
        finish(false)
      end)
    elseif LearnMove._battleText or LearnMove._relearner then
      -- pokefirered/data/battle_scripts_1.s:3133
      ask_to_learn()
    else
      open_delete_prompt()
    end
  end)
end

function open_forget_list()
  if LearnMove._headless or not LearnMove._askForget then
    say(did_not_learn_text(), function()
      finish(false)
    end)
    return
  end
  local opts, slots = {}, {}
  for i = 1, 4 do
    local id = Pokemon.moveIdAt(LearnMove._mon, i)
    if id and id > 0 then
      local label = move_name(id)
      if Pokemon.isHmMove(id) then label = Strings("%s (HM)", label) end
      opts[#opts + 1] = label
      slots[#slots + 1] = i
    end
  end
  LearnMove._forgetSlots = slots
  LearnMove._waitingChoice = true
  LearnMove._askForget(opts, function(idx)
    LearnMove._waitingChoice = false
    if idx == nil or idx < 0 or idx >= #slots then
      open_stop_prompt()
      return
    end
    local slot = slots[idx + 1]
    local oldId = Pokemon.moveIdAt(LearnMove._mon, slot)
    if Pokemon.isHmMove(oldId) then
      say(Strings("HM moves can't be\nforgotten now."), function()
        if LearnMove._battleText or LearnMove._relearner then
          -- pokefirered/src/battle_script_commands.c:5246
          -- pokefirered/src/pokemon_summary_screen.c:3899
          open_forget_list()
        else
          open_delete_prompt()
        end
      end)
      return
    end
    local forgotten = Pokemon.replaceMove(LearnMove._mon, slot, LearnMove._moveId)
    if forgotten then
      local battle = LearnMove._battleText
      local function fanfare()
        pcall(function() require("src.core.game3.audio").playFanfare(257) end)
      end
      if not battle then fanfare() end
      -- pokefirered/src/battle_message.c:315
      -- pokefirered/src/strings.c:1261
      local poof = T(Strings("1, 2, and… … … Poof!"), Strings("1, 2, and… Poof!"),
        Strings("1, 2, and… … … Poof!"))
      -- pokefirered/src/battle_message.c:61
      -- pokefirered/src/strings.c:1262
      local forgot = T(Strings("%s forgot\n%s.", LearnMove._name, move_name(forgotten)),
        Strings("%s forgot how to\nuse %s.", LearnMove._name, move_name(forgotten)),
        Strings("%s forgot %s.", LearnMove._name, move_name(forgotten)))
      local andText = T(Strings("And…"), Strings("And..."), Strings("And…"))
      local learned = T(Strings("%s learned\n%s!", LearnMove._name, LearnMove._moveName),
        Strings("%s learned\n%s!", LearnMove._name, LearnMove._moveName),
        Strings("%s\nlearned %s.", LearnMove._name, LearnMove._moveName))
      if LearnMove._headless then
        say(poof)
        say(forgot)
        say(andText)
        if battle then fanfare() end
        say(learned)
        finish(true)
      else
        say(poof, function()
          say(forgot, function()
            say(andText, function()
              -- pokefirered/data/battle_scripts_1.s:3142
              if battle then fanfare() end
              say(learned, function()
                finish(true)
              end)
            end)
          end)
        end)
      end
    else
      open_delete_prompt()
    end
  end, { mon = LearnMove._mon, moveId = LearnMove._moveId })
end

--- Call when message queue is idle. Opens deferred Choice prompts.
-- Returns false while still busy.
function LearnMove.pump()
  return not LearnMove._active
end

function LearnMove.begin(opts)
  opts = opts or {}
  local mon = opts.mon
  local moveId = tonumber(opts.moveId)
  if not mon or not moveId then
    if opts.onDone then opts.onDone(false) end
    return
  end
  if Pokemon.knowsMove(mon, moveId) then
    if opts.onDone then opts.onDone(false) end
    return
  end

  LearnMove._active = true
  LearnMove._mon = mon
  LearnMove._moveId = moveId
  LearnMove._name = opts.displayName or Pokemon.displayMonName(mon)
  LearnMove._moveName = move_name(moveId)
  LearnMove._pushMsg = opts.pushMsg
  LearnMove._askYesNo = opts.askYesNo
  LearnMove._askForget = opts.askForget
  LearnMove._onDone = opts.onDone
  LearnMove._headless = opts.headless and true or false
  LearnMove._battleText = opts.battleText and true or false
  LearnMove._relearner = opts.relearner and true or false
  LearnMove._waitingChoice = false

  if Pokemon.moveSlotCount(mon) < 4 then
    local ok = Pokemon.teachMove(mon, moveId)
    if ok then
      pcall(function() require("src.core.game3.audio").playFanfare(257) end)
      -- pokefirered/src/strings.c:1258
      local learned = T(Strings("%s learned\n%s!", LearnMove._name, LearnMove._moveName),
        Strings("%s learned\n%s!", LearnMove._name, LearnMove._moveName),
        Strings("%s learned\n%s.", LearnMove._name, LearnMove._moveName))
      if LearnMove._headless then
        say(learned)
        finish(ok)
      else
        say(learned, function()
          finish(ok)
        end)
      end
    else
      finish(false)
    end
    return
  end

  if LearnMove._headless then
    say(Strings("%s did not learn\n%s.", LearnMove._name, LearnMove._moveName))
    finish(false)
    return
  end

  ask_to_learn()
end

function LearnMove.movesForLevels(mon, levels)
  local species = Pokemon.speciesOf(mon) or tonumber(mon and (mon.species or mon.speciesId))
  local out = {}
  if not species then return out end
  local seen = {}
  for _, lv in ipairs(levels or {}) do
    for _, mv in ipairs(Pokemon.movesLearnedAt(species, lv)) do
      if not seen[mv] and not Pokemon.knowsMove(mon, mv) then
        seen[mv] = true
        out[#out + 1] = { level = lv, moveId = mv }
      end
    end
  end
  return out
end

local function queue_next()
  local opts = LearnMove._queueOpts
  local mon = opts and opts.mon
  LearnMove._queueIdx = (LearnMove._queueIdx or 0) + 1
  local item = LearnMove._queue and LearnMove._queue[LearnMove._queueIdx]
  if not item or not mon then
    local cb = opts and opts.onDone
    LearnMove._queue = nil
    LearnMove._queueOpts = nil
    if cb then cb() end
    return
  end
  LearnMove.begin({
    mon = mon,
    moveId = item.moveId,
    displayName = opts.displayName,
    pushMsg = opts.pushMsg,
    askYesNo = opts.askYesNo,
    askForget = opts.askForget,
    headless = opts.headless,
    battleText = opts.battleText,
    onDone = function()
      queue_next()
    end,
  })
end

function LearnMove.beginQueue(mon, levels, opts)
  opts = opts or {}
  opts.mon = mon
  local q = LearnMove.movesForLevels(mon, levels)
  if #q == 0 then
    if opts.onDone then opts.onDone() end
    return false
  end
  LearnMove._queue = q
  LearnMove._queueIdx = 0
  LearnMove._queueOpts = opts
  queue_next()
  return true
end

return LearnMove
