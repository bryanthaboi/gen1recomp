-- FireRed 1:1 battle AI — BattleAI_ChooseMoveOrAction scoring loop.

local AiVm = require("src.core.game3.battle.ai_vm")

local choose_move_core

local Ai = {}

Ai._pack = nil
Ai._packTried = false

local function pack_paths()
  local rel = "data/generated/gba/battle_ai/pack.lua"
  local paths = {}
  local home = os.getenv("HOME")
  if home then
    paths[#paths + 1] = home .. "/.local/share/love/pokemon-love2d/firered/" .. rel
  end
  paths[#paths + 1] = rel
  paths[#paths + 1] = "firered/" .. rel
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local sd = love.filesystem.getSaveDirectory()
    if type(sd) == "string" and sd ~= "" then
      paths[#paths + 1] = sd .. "/" .. rel
      local parent = sd:match("^(.*)/[^/]+$")
      if parent then
        paths[#paths + 1] = parent .. "/pokemon-love2d/firered/" .. rel
      end
    end
  end
  return paths, rel
end

local function load_lua_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  if not src then return nil end
  local chunk, err = load(src, "@" .. path, "t", {})
  if not chunk then return nil, err end
  local ok, t = pcall(chunk)
  if ok then return t end
  return nil, t
end

function Ai.loadPack(opts)
  opts = opts or {}
  if Ai._pack and not opts.force then return Ai._pack end
  Ai._packTried = true

  local paths, rel = pack_paths()

  -- love filesystem
  if love and love.filesystem and love.filesystem.read then
    local src = love.filesystem.read(rel)
    if src then
      local chunk = load(src, "@" .. rel, "t", {})
      if chunk then
        local ok, t = pcall(chunk)
        if ok and t then
          Ai._pack = t
          return t
        end
      end
    end
  end

  -- Dataset cache
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local cache = Dataset.cache()
    if cache and cache.read then
      local src = cache:read(rel)
      if src then
        local chunk = load(src, "@" .. rel, "t", {})
        if chunk then
          local ok, t = pcall(chunk)
          if ok and t then
            Ai._pack = t
            return t
          end
        end
      end
    end
  end

  for _, p in ipairs(paths) do
    local t = load_lua_file(p)
    if t then
      Ai._pack = t
      return t
    end
  end

  -- Try extract on demand
  if opts.extract ~= false then
    local okE, Extract = pcall(require, "src.import.gba.battle_ai_extract")
    if okE and Extract and Extract.run then
      local FileIO = require("src.import.gba.file_io")
      local home = os.getenv("HOME")
      local outRoot = home and (home .. "/.local/share/love/pokemon-love2d/firered") or "."
      local cache = FileIO.makeCache(outRoot)
      local detail = Extract.run({
        cache = cache,
        cacheRoot = "data/generated/gba",
        pretRoot = os.getenv("POKEFIRERED"),
      })
      if detail then
        local t = load_lua_file(outRoot .. "/" .. (detail.path or rel))
        if not t and detail.path then t = load_lua_file(detail.path) end
        if t then
          Ai._pack = t
          return t
        end
        -- re-read via cache
        local src = cache:read(rel)
        if src then
          local chunk = load(src, "@" .. rel, "t", {})
          if chunk then
            local ok, pack = pcall(chunk)
            if ok and pack then
              Ai._pack = pack
              return pack
            end
          end
        end
      end
    end
  end

  return nil
end

local function rng_fn(st, opts)
  if opts and opts.rng then return opts.rng end
  if st and type(st.rng) == "function" then return st.rng end
  local okR, Rng = pcall(require, "src.core.game3.rng")
  if okR and Rng and Rng.compat then return Rng.compat end
  return math.random
end

local function roll(rng, lo, hi)
  local ok, v = pcall(rng, lo, hi)
  if ok and type(v) == "number" then return v end
  ok, v = pcall(rng)
  if ok and type(v) == "number" then
    return lo + (math.floor(v) % (hi - lo + 1))
  end
  local okR, Rng = pcall(require, "src.core.game3.rng")
  if okR and Rng and Rng.compat then
    return Rng.compat(lo, hi)
  end
  return math.random(lo, hi)
end

local function bit_and_flags(a, b)
  a = math.floor(a or 0)
  b = math.floor(b or 0)
  local r, bitv = 0, 1
  for _ = 1, 32 do
    if (a % 2) > 0 and (b % 2) > 0 then r = r + bitv end
    a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
  end
  return r
end

local function bit_or_flags(a, b)
  return a + b - bit_and_flags(a, b)
end

local function run_scripts(pack, aiFlags, st, user, target, userSide, targetSide, scores, simulatedRNG, rng)
  local aiAction = 0
  local logicId = 0
  local flags = aiFlags
  while flags ~= 0 do
    if bit_and_flags(flags, 1) ~= 0 then
      local scriptName = pack.table[logicId + 1] -- Lua 1-based; pret index 0
      if scriptName and pack.scripts[scriptName] then
        for movesetIndex = 1, 4 do
          local vm = AiVm.new({
            pack = pack,
            st = st,
            user = user,
            target = target,
            userSide = userSide,
            targetSide = targetSide,
            scores = scores,
            simulatedRNG = simulatedRNG,
            movesetIndex = movesetIndex,
            rng = rng,
          })
          AiVm.run(vm, scriptName)
          aiAction = bit_or_flags(aiAction, vm.aiAction or 0)
          if bit_and_flags(aiAction, 0x8) ~= 0 then break end
        end
      end
    end
    flags = math.floor(flags / 2)
    logicId = logicId + 1
    if logicId > 31 then break end
  end
  return aiAction
end

local MOVE_TARGET_BOTH = 0x08
local MOVE_TARGET_SELF = 0x12

local function move_num(mv)
  local n = tonumber(mv)
  if n then return n end
  if mv == nil or mv == "" then return 0 end
  local Moves = require("src.core.game3.battle.moves")
  return Moves.numForName and Moves.numForName(mv) or 0
end

local function move_target_byte(mv)
  if move_num(mv) == 0 then return 0 end
  local Moves = require("src.core.game3.battle.moves")
  local m = Moves.get(mv)
  return tonumber(m and m.target) or 0
end

local function random_u16(rng)
  return roll(rng, 0, 65535)
end

local ad_cache = setmetatable({}, { __mode = "k" })
local function adapter_for(st, opts)
  if opts and opts.adapter then return opts.adapter end
  local Battle = package.loaded["src.core.game3.battle"]
  local ad = Battle and Battle._adapter
  if ad and ad._st == st then return ad end
  ad = ad_cache[st]
  if not ad then
    ad = require("src.core.game3.battle.adapter").new(st, function() end)
    ad_cache[st] = ad
  end
  return ad
end

-- src/battle_ai_script_commands.c:370
local function pret_pick(scores, rng)
  local best = scores[1] or 0
  local considered = { 1 }
  for i = 2, 4 do
    local s = scores[i] or 0
    if best < s then
      best = s
      considered = { i }
    end
    if best == s then considered[#considered + 1] = i end
  end
  return considered[roll(rng, 1, #considered)], best
end

local function double_first_usable(mon, id, bad)
  for i = 1, 4 do
    local mv = mon and mon.moves and mon.moves[i]
    if move_num(mv) ~= 0 and not (bad and bad[i]) then
      return { kind = "move", move = mv, slot = i, user = "enemy", battler = id }
    end
  end
  return { kind = "move", move = "STRUGGLE", slot = nil, user = "enemy", battler = id }
end

local AI_SCRIPT_ROAMING = 0x20000000
local AI_SCRIPT_SAFARI = 0x40000000

local function uses_ai(st)
  return not st.wild or st.roamer or st.safari or st.firstBattle
end

-- src/battle_controller_opponent.c:1350
function choose_move_core(st, id, opts)
  local State = require("src.core.game3.battle.state")
  local Engine = require("src.core.game3.battle.engine")
  local b = State.battler(st, id)
  local mon = b and b.mon
  if not mon then return nil end
  local rng = rng_fn(st, opts)
  local ad = adapter_for(st, opts)
  local double = st.double and true or false
  local function shape(act)
    if not double then
      act.target = nil
      if opts.battler == nil then act.battler = nil end
    end
    return act
  end

  local bad = {}
  local okL, lim = pcall(Engine.moveLimitations, b, ad)
  if okL and type(lim) == "table" then bad = lim end
  -- src/battle_main.c:3147
  if bad[1] and bad[2] and bad[3] and bad[4] then
    return shape({ kind = "move", move = "STRUGGLE", slot = nil, user = "enemy", battler = id })
  end

  if not uses_ai(st) then
    -- src/battle_controller_opponent.c:1389
    local slot, mv
    for _ = 1, 1000 do
      slot = roll(rng, 0, 3) + 1
      mv = mon.moves and mon.moves[slot]
      if move_num(mv) ~= 0 then break end
    end
    if move_num(mv) == 0 then return shape(double_first_usable(mon, id, bad)) end
    local tid
    if bit_and_flags(move_target_byte(mv), MOVE_TARGET_SELF) ~= 0 then
      tid = id
    elseif double then
      tid = bit_and_flags(random_u16(rng), 2)
    else
      tid = State.OPPOSITE(id)
    end
    return shape({ kind = "move", move = mv, slot = slot, user = "enemy", battler = id, target = tid,
      scores = { 0, 0, 0, 0 } })
  end

  -- src/battle_ai_script_commands.c:331
  local aiFlags
  if st.safari then
    aiFlags = AI_SCRIPT_SAFARI
  elseif st.roamer then
    aiFlags = AI_SCRIPT_ROAMING
  else
    aiFlags = tonumber(opts.aiFlags or st.aiFlags) or 0
  end
  local pack = opts.pack
  if aiFlags ~= 0 and not pack then pack = Ai.loadPack() end

  -- src/battle_ai_script_commands.c:301
  local scores = { 100, 100, 100, 100 }
  local simulatedRNG = {}
  for i = 1, 4 do
    if bad[i] then scores[i] = 0 end
    simulatedRNG[i] = 100 - roll(rng, 0, 15)
  end
  -- src/battle_ai_script_commands.c:317
  local tid
  if double then
    tid = bit_and_flags(random_u16(rng), 2)
    if State.isAbsent(st, tid) then tid = 2 - tid end
  else
    tid = State.OPPOSITE(id)
  end
  local target = State.battler(st, tid)
  local userSide = (b.side == "player") and st.playerSide or st.enemySide
  local targetSide = (b.side == "player") and st.enemySide or st.playerSide

  local aiAction = 0
  if aiFlags ~= 0 and pack and pack.table and pack.scripts and target then
    aiAction = run_scripts(pack, aiFlags, st, b, target, userSide, targetSide, scores, simulatedRNG, rng)
  end
  -- src/battle_ai_script_commands.c:383
  if bit_and_flags(aiAction, 0x2) ~= 0 then
    return shape({ kind = "run", user = "enemy", battler = id, scores = scores })
  end
  if bit_and_flags(aiAction, 0x4) ~= 0 then
    return shape({ kind = "watch", user = "enemy", battler = id, scores = scores })
  end

  local slot = pret_pick(scores, rng)
  local mv = mon.moves and mon.moves[slot]
  if move_num(mv) == 0 then
    local fb = double_first_usable(mon, id, bad)
    fb.scores = scores
    return shape(fb)
  end
  -- src/battle_controller_opponent.c:1370
  local tt = move_target_byte(mv)
  if bit_and_flags(tt, MOVE_TARGET_SELF) ~= 0 then tid = id end
  if bit_and_flags(tt, MOVE_TARGET_BOTH) ~= 0 then
    tid = double and 0 or State.OPPOSITE(id)
    if double and State.isAbsent(st, tid) then tid = 2 end
  end
  return shape({
    kind = "move",
    move = mv,
    slot = slot,
    user = "enemy",
    battler = id,
    target = tid,
    scores = scores,
  })
end

--- Choose enemy move via pret AI scripts.
-- @return { kind="move", move=..., slot=i, user="enemy", scores=... }
function Ai.chooseMove(st, opts)
  opts = opts or {}
  if not st then return nil end
  local id = opts.battler or 1
  return choose_move_core(st, id, opts)
end

-- src/battle_main.c:3125
function Ai.chooseAction(st, id, opts)
  opts = opts or {}
  id = id or 1
  if not st then return nil end
  local State = require("src.core.game3.battle.state")
  local b = State.battler(st, id)
  if not b or not b.mon then return nil end
  if b.expLockedMove or b.expMustRecharge then
    local act = { kind = "move", move = b.expLockedMove, slot = b.expLockedSlot, user = "enemy", battler = id }
    if not act.move then act = double_first_usable(b.mon, id) end
    return act
  end
  local rng = rng_fn(st, opts)
  local ad = adapter_for(st, opts)
  -- src/battle_ai_switch_items.c:358
  if not st.wild and not st.pokedude then
    local AiSwitch = require("src.core.game3.battle.ai_switch")
    local pick = AiSwitch.trySwitch(st, ad, id, rng)
    if pick then
      st.monToSwitchInto = st.monToSwitchInto or {}
      st.monToSwitchInto[id] = pick
      return { kind = "switch", slot = pick, user = "enemy", battler = id }
    end
    local AiItems = require("src.core.game3.battle.ai_items")
    local use = AiItems.shouldUseItem(st, id)
    if use then
      return {
        kind = "item",
        item = use.item,
        aiItemType = use.aiItemType,
        aiItemFlags = use.aiItemFlags,
        user = "enemy",
        battler = id,
        target = id,
      }
    end
  end
  return choose_move_core(st, id, {
    battler = id,
    rng = rng,
    adapter = ad,
    pack = opts.pack,
    aiFlags = opts.aiFlags,
  })
end

-- src/battle_controllers.c:59
function Ai.battleStart(st, opts)
  opts = opts or {}
  if not st then return end
  st._aiHistory = nil
  require("src.core.game3.battle.ai_items").history(st)
  local rng = rng_fn(st, opts)
  for _ = 1, 4 do roll(rng, 0, 15) end
  if st.double then random_u16(rng) end
end

return Ai
