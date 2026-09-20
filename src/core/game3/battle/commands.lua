-- Battle commands: FIGHT / BAG / POKéMON / RUN (+ move slots).

local ModRuntime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")

local Commands = {}

Commands.MENU = { "FIGHT", "BAG", "POKEMON", "RUN" }

function Commands.defaultMenuIndex()
  return 1 -- FIGHT
end

local function battler_of(st, id)
  if id == nil or id == 0 then return st and st.player end
  if id == 1 then return st and st.enemy end
  return st and st.battlers and st.battlers[id]
end
Commands.battlerOf = battler_of

local function move_target_type(mv)
  local ok, Moves = pcall(require, "src.core.game3.battle.moves")
  if not ok or mv == nil then return nil end
  local m = Moves.get(mv)
  return tonumber(m and m.target) or 0
end

local function tag(act, id, targetId)
  if not act then return act end
  act.battler = id or 0
  if targetId ~= nil then act.target = targetId end
  if act.kind == "move" then act.targetType = move_target_type(act.move) end
  return act
end

--- Build a player action from menu selection.
-- menuIndex 1..4; moveSlot 1..4 when FIGHT.
function Commands.playerAction(st, menuIndex, moveSlot, battlerId, targetId)
  if battlerId ~= nil or targetId ~= nil then
    local b = battler_of(st, battlerId)
    local act = Commands.playerAction({ player = b }, menuIndex, moveSlot, nil, nil)
    return tag(act, battlerId or 0, targetId)
  end
  menuIndex = menuIndex or 1
  local kind = Commands.MENU[menuIndex] or "FIGHT"
  if kind == "FIGHT" then
    local mon = st.player and st.player.mon
    local slot = moveSlot or 1
    local move = mon and mon.moves and mon.moves[slot]
    local pp = mon and mon.pp and mon.pp[slot]
    if not move or move == 0 or move == "" or (pp ~= nil and tonumber(pp) <= 0) then
      -- Fall back to first usable
      for i = 1, 4 do
        local mv = mon and mon.moves and mon.moves[i]
        local p = mon and mon.pp and mon.pp[i]
        if mv and mv ~= 0 and mv ~= "" and (p == nil or tonumber(p) > 0) then
          return { kind = "move", move = mv, slot = i, user = "player" }
        end
      end
      return { kind = "move", move = "STRUGGLE", slot = nil, user = "player" }
    end
    return { kind = "move", move = move, slot = slot, user = "player" }
  elseif kind == "RUN" then
    return { kind = "run", user = "player" }
  elseif kind == "BAG" then
    return { kind = "bag", user = "player" }
  elseif kind == "POKEMON" then
    return { kind = "switch", user = "player" }
  end
  return { kind = "move", move = "TACKLE", slot = 1, user = "player" }
end

local MOVE_STRUGGLE = 165
local ITEM_CHOICE_BAND = 186

local function move_num(mv)
  local n = tonumber(mv)
  if n then return n end
  if mv == nil or mv == "" then return 0 end
  local ok, Moves = pcall(require, "src.core.game3.battle.moves")
  if ok and Moves.numForName then return Moves.numForName(mv) or 0 end
  return 0
end

local function battler_name(b)
  local State = require("src.core.game3.battle.state")
  return State.displayName(b)
end

local function move_name(mv)
  local Moves = require("src.core.game3.battle.moves")
  return Moves.displayName(mv)
end

local function foe_of(st, b)
  if not st or not b then return nil end
  return (b.side == "enemy") and st.player or st.enemy
end

local function foes_of(st, b)
  if st and st.double then
    local State = require("src.core.game3.battle.state")
    return State.foes(st, b)
  end
  return { foe_of(st, b) }
end

local function imprisoned(st, b, num)
  for _, foe in ipairs(foes_of(st, b)) do
    if foe and foe.expImprison and foe.mon and foe.mon.moves then
      for i = 1, 4 do
        if move_num(foe.mon.moves[i]) == num and num ~= 0 then return true end
      end
    end
  end
  return false
end

local function choiced(b)
  local cm = b and move_num(b.choicedMove) or 0
  if (tonumber(b and b.item) or 0) ~= ITEM_CHOICE_BAND then return nil end
  if cm == 0 or cm == 0xFFFF then return nil end
  return cm
end

-- pokefirered/src/battle_util.c:302
function Commands.selectionError(st, slot, battlerId)
  local b = battler_of(st, battlerId)
  local mon = b and b.mon
  if not mon or not slot then return nil end
  local mv = mon.moves and mon.moves[slot]
  local num = move_num(mv)
  local name = battler_name(b)
  local err
  if b.expDisabledMove and move_num(b.expDisabledMove) == num and num ~= 0 then
    err = Strings("%s's %s\nis disabled!", name, move_name(mv))
  end
  if (b.expTormented or b.torment) and num ~= MOVE_STRUGGLE and num ~= 0
      and move_num(b.lastMoveId or b.lastMove) == num then
    err = Strings("%s can't use the same\nmove in a row due to the TORMENT!", name)
  end
  if (tonumber(b.expTauntedTurns) or 0) > 0 then
    local Moves = require("src.core.game3.battle.moves")
    local def = Moves.get(mv)
    if def and (tonumber(def.power) or 0) == 0 then
      err = Strings("%s can't use\n%s after the TAUNT!", name, move_name(mv))
    end
  end
  if imprisoned(st, b, num) then
    err = Strings("%s can't use the\nsealed %s!", name, move_name(mv))
  end
  local cm = choiced(b)
  if cm and cm ~= num then
    local okI, Items = pcall(require, "src.core.game3.items")
    local iname = okI and Items.displayName and Items.displayName(b.item) or "CHOICE BAND"
    err = Strings("%s's effect allows only\n%s to be used!", iname, move_name(cm))
  end
  local pp = mon.pp and tonumber(mon.pp[slot])
  if pp ~= nil and pp <= 0 then
    err = Strings("There's no PP left for\nthis move!")
  end
  return err
end

-- pokefirered/src/battle_util.c:361
function Commands.moveUsable(st, slot, battlerId)
  local b = battler_of(st, battlerId)
  local mon = b and b.mon
  local mv = mon and mon.moves and mon.moves[slot]
  if move_num(mv) == 0 then return false end
  return Commands.selectionError(st, slot, battlerId) == nil
end

-- pokefirered/src/battle_main.c:3146
function Commands.fightShortcut(st, battlerId)
  local b = battler_of(st, battlerId)
  if not b or not b.mon then return nil end
  local any = false
  for i = 1, 4 do
    if Commands.moveUsable(st, i, battlerId) then any = true break end
  end
  if not any then
    local act = { kind = "move", move = "STRUGGLE", slot = nil, user = "player" }
    if battlerId ~= nil then tag(act, battlerId) end
    return act, Strings("%s has no\nmoves left!", battler_name(b))
  end
  if b.expEncoreMove and (tonumber(b.expEncoreTurns) or 0) > 0 then
    local slot = b.expEncoreSlot
    if not slot then
      for i = 1, 4 do
        if move_num(b.mon.moves[i]) == move_num(b.expEncoreMove) then slot = i break end
      end
    end
    if slot then
      local act = { kind = "move", move = b.mon.moves[slot], slot = slot, user = "player" }
      if battlerId ~= nil then tag(act, battlerId) end
      return act
    end
  end
  return nil
end

-- pokefirered/src/party_menu.c:5916
function Commands.switchError(st, slot, forced, battlerId)
  local party = st and st.playerParty
  local mon = party and party[slot]
  if not mon then return nil end
  local Pokemon = require("src.core.game3.pokemon")
  local name = Pokemon.displayMonName and Pokemon.displayMonName(mon) or "POKéMON"
  if (tonumber(mon.hp) or 0) <= 0 then return Strings("%s has no energy\nleft to battle!", name) end
  if st.player and st.player.partyIndex == slot then return Strings("%s is already\nin battle!", name) end
  if st.double then
    -- pokefirered/src/party_menu.c:5934
    local b2 = battler_of(st, 2)
    if b2 and b2.partyIndex == slot and not (st.absent and st.absent[2]) then
      return Strings("%s is already\nin battle!", name)
    end
    local pend = st.monToSwitchInto or {}
    local partner = (battlerId == 2) and 0 or 2
    if battlerId ~= nil and pend[partner] == slot then
      return Strings("%s has already been\nselected.", name)
    end
  end
  if mon.isEgg then return Strings("An EGG can't battle!") end
  if forced then return nil end
  local Engine = package.loaded["src.core.game3.battle.engine"]
  local Battle = package.loaded["src.core.game3.battle"]
  local ad = Battle and Battle._adapter
  if Engine and Engine.canSwitch and ad then
    local ok, why = Engine.canSwitch(st, ad, battler_of(st, battlerId))
    if not ok then return why end
  end
  return nil
end

Commands.aiHook = nil

function Commands.setAiHook(fn) Commands.aiHook = fn end

local function first_usable_action(b, id)
  local mon = b and b.mon
  for i = 1, 4 do
    local mv = mon and mon.moves and mon.moves[i]
    local p = mon and mon.pp and mon.pp[i]
    if mv and mv ~= 0 and mv ~= "" and (p == nil or tonumber(p) > 0) then
      return { kind = "move", move = mv, slot = i, user = "enemy", battler = id }
    end
  end
  return { kind = "move", move = "STRUGGLE", slot = nil, user = "enemy", battler = id }
end

local function vanilla_enemy_action(st, battlerId)
  local id = battlerId or 1
  if st and st.double then
    local b = battler_of(st, id)
    local act
    local hook = Commands.aiHook
    local ok, res = pcall(function()
      if hook then return hook(st, id) end
      local Ai = require("src.core.game3.battle.ai")
      if Ai.chooseAction then return Ai.chooseAction(st, id) end
      return Ai.chooseMove(st, { battler = id })
    end)
    if ok and res and res.kind and (res.battler == id or (res.battler == nil and id == 1)) then act = res end
    act = act or first_usable_action(b, id)
    return tag(act, id, act.target)
  end
  local ok, act = pcall(function()
    local Ai = require("src.core.game3.battle.ai")
    if Ai.chooseAction then return Ai.chooseAction(st, 1) end
    return Ai.chooseMove(st)
  end)
  if ok and act and act.kind == "move" then
    act.battler = (battlerId ~= nil) and 1 or nil
    return act
  end
  if ok and act and (act.kind == "switch" or act.kind == "item" or act.kind == "run" or act.kind == "watch") then
    act.battler = 1
    return act
  end
  local fb = first_usable_action(st.enemy, nil)
  fb.battler = nil
  if battlerId ~= nil then fb.battler = 1 end
  return fb
end

local function normalize_enemy_action(st, res, battlerId)
  local id = battlerId or 1
  if type(res) == "string" or type(res) == "number" then res = { kind = "move", move = res } end
  if type(res) ~= "table" then return nil end
  local act = {}
  for k, v in pairs(res) do act[k] = v end
  act.kind = act.kind or "move"
  if act.kind == "move" then
    local ref = act.move or act.id
    local num = ref ~= nil and require("src.mods.Gen3Compat").moveId(ref) or nil
    if not num then return nil end
    local b = battler_of(st, id)
    local moves = b and b.mon and b.mon.moves or {}
    act.move, act.id = num, nil
    if not act.slot or tonumber(moves[act.slot]) ~= num then
      act.slot = nil
      for i = 1, 4 do
        if tonumber(moves[i]) == num then act.slot = i break end
      end
    end
  end
  act.user = act.user or "enemy"
  if st and st.double then return tag(act, id, act.target) end
  act.battler = (battlerId ~= nil) and 1 or nil
  return act
end

-- pokefirered/src/battle_controller_opponent.c:1350
function Commands.enemyAction(st, battlerId)
  if not ModRuntime.wantsHook("battle.enemy_action") then
    return vanilla_enemy_action(st, battlerId)
  end
  local vanilla
  local res = ModRuntime.call("battle.enemy_action", function(battle, bid)
    vanilla = vanilla_enemy_action(battle, bid)
    return vanilla
  end, st, battlerId)
  if res ~= nil and res == vanilla then return vanilla end
  return normalize_enemy_action(st, res, battlerId) or vanilla or vanilla_enemy_action(st, battlerId)
end

function Commands.enemyActions(st)
  local out = {}
  for _, id in ipairs({ 1, 3 }) do
    local b = battler_of(st, id)
    if b and not (st.absent and st.absent[id]) and (id == 1 or st.double) then
      out[id] = Commands.enemyAction(st, id)
    end
  end
  return out
end

--- Wild flee: pret-ish odds from speed (simplified).
function Commands.tryFlee(st, adapter)
  local Engine = package.loaded["src.core.game3.battle.engine"]
  if Engine and Engine.tryFlee then
    local ok = Engine.tryFlee(st, adapter, st.player)
    return ok and true or false
  end
  if not st.wild then
    adapter:say(Strings("No! There's no\nrunning from a\nTRAINER battle!"))
    return false
  end
  local pSpe = tonumber(st.player.mon.speed or st.player.mon.spe) or 50
  local eSpe = tonumber(st.enemy.mon.speed or st.enemy.mon.spe) or 50
  local odds = math.floor((pSpe * 128) / math.max(1, eSpe)) + 30 * (st.fleeAttempts or 0)
  st.fleeAttempts = (st.fleeAttempts or 0) + 1
  local roll = adapter:rng()
  local r
  local ok, v = pcall(roll, 0, 255)
  if ok and type(v) == "number" then
    r = v
  else
    local okR, Rng = pcall(require, "src.core.game3.rng")
    if okR and Rng and Rng.compat then
      r = Rng.compat(0, 255)
    else
      r = math.random(0, 255)
    end
  end
  if r < odds then
    adapter:say(Strings("Got away safely!"))
    return true
  end
  adapter:say(Strings("Can't escape!"))
  return false
end

return Commands
