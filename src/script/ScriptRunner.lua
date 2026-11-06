-- Executes map scripts: lists of { "command", args... } rows (see
-- src/script/Commands.lua and data/scripts/).  Runs as a coroutine so
-- commands like show_text and wait can block on UI.
--
-- Map-specific behavior lives in data/scripts/<map>.lua modules, never in
-- engine code.  Each hand-ported script references its asm source.
--
-- Script v2: { "label", "name" } rows are jump targets; jump/jump_if_*
-- may return a label name and exec resolves it through a pre-scanned
-- label map.  "end" is reserved shorthand for halt.  Numeric targets are
-- untouched, so hand-numbered vanilla ports keep working row for row.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local SaveSerializer = require("src.core.SaveSerializer")
local Strings = require("src.core.Strings")

local unpack = table.unpack or unpack -- LuaJIT (LÖVE) compatibility

local ScriptRunner = {}
ScriptRunner.__index = ScriptRunner

-- weak-keyed so a hot-reloaded script table drops its stale scan
local labelCache = setmetatable({}, { __mode = "k" })

function ScriptRunner.scanLabels(script)
  local hit = labelCache[script]
  if hit then return hit end
  local labels = {}
  for index, row in ipairs(script) do
    if type(row) == "table" and row[1] == "label" and type(row[2]) == "string"
        and labels[row[2]] == nil then
      labels[row[2]] = index
    end
  end
  labelCache[script] = labels
  return labels
end

-- Load-time validation (09 §4.9): every finding names its row.  lookup
-- is fn(verb) -> true when the verb resolves; nil uses the built-in set,
-- so the offline validator and the loader share this code path.
function ScriptRunner.validate(script, lookup)
  local problems = {}
  local function bad(fmt, ...)
    problems[#problems + 1] = fmt:format(...)
  end
  if type(script) ~= "table" then
    bad("script is not a row list")
    return problems
  end
  lookup = lookup or function(verb) return Commands[verb] ~= nil end
  local labels = {}
  for index, row in ipairs(script) do
    if type(row) ~= "table" or type(row[1]) ~= "string" then
      bad("row %d is not a { \"command\", ... } row", index)
    elseif row[1] == "label" then
      local name = row[2]
      if type(name) ~= "string" then
        bad("row %d: label needs a string name", index)
      elseif labels[name] then
        bad("row %d: duplicate label '%s' (first at row %d)",
          index, name, labels[name])
      else
        labels[name] = index
      end
    elseif not lookup(row[1]) then
      bad("row %d: unknown command '%s'", index, row[1])
    end
  end
  for index, row in ipairs(script) do
    if type(row) == "table" and (row[1] == "jump" or row[1] == "jump_if_true"
        or row[1] == "jump_if_false") then
      local target = row[2]
      if type(target) == "string" then
        if target ~= "end" and not labels[target] then
          bad("row %d: jump to missing label '%s'", index, target)
        end
      elseif type(target) == "number" then
        if target ~= math.huge and (target < 1 or target > #script
            or target % 1 ~= 0) then
          bad("row %d: jump target %s out of range 1..%d",
            index, tostring(target), #script)
        end
      else
        bad("row %d: jump needs a label or row number", index)
      end
    end
  end
  return problems
end

function ScriptRunner.new(game, overworld)
  local self = setmetatable({}, ScriptRunner)
  self.game = game
  self.overworld = overworld
  self.co = nil
  return self
end

function ScriptRunner:isRunning()
  return self.co ~= nil and coroutine.status(self.co) ~= "dead"
end

-- ctx passed to commands: engine services plus per-run info (npc, map).
-- extra.source = { modId, mapId, hook } attributes errors and the mod:
-- field route to the contribution's owner.
function ScriptRunner:makeContext(extra)
  local ctx = {
    game = self.game,
    overworld = self.overworld,
    save = self.game.save,
    runner = self,
  }
  for k, v in pairs(extra or {}) do ctx[k] = v end
  return ctx
end

local function trainerAhead(rows, from, depth)
  for k = from, math.min(#rows, from + 23) do
    local row = rows[k]
    if type(row) == "table" then
      local name = row[1]
      if name == "rival_battle" and type(row[2]) == "string" then
        return row[2], row[3]
      end
      if name == "start_battle" and row[2] == "trainer" and type(row[3]) == "string" then
        return row[3], row[4]
      end
      if depth < 3 then
        for j = 2, #row do
          local v = row[j]
          if type(v) == "table" and type(v[1]) == "table" then
            local cls, party = trainerAhead(v, 1, depth + 1)
            if cls then return cls, party end
          end
        end
      end
    end
  end
end

function ScriptRunner:hintTrainerBattle(script, ctx, startPc)
  if ctx.trainerHinted or self.parallel or ctx.resumeBattle then return end
  local data = self.game and self.game.data
  if not (data and data.trainers and type(script) == "table") then return end
  local cls, party = trainerAhead(script, startPc or 1, 0)
  if not (cls and data.trainers[cls]) then return end
  ctx.trainerHinted = true
  local ok, err = pcall(require("src.world.OverworldController").prepareTrainerBattleMusic,
    data, cls, type(party) == "number" and party or nil)
  if not ok then Logger.warn("trainer battle music hint failed: %s", tostring(err)) end
end

function ScriptRunner:run(script, extra, startPc)
  assert(not self:isRunning(), "script already running")
  local ctx = self:makeContext(extra)
  self.ctx = ctx
  if Runtime.wants("script.started") then
    Runtime.emit("script.started", { ctx = ctx })
  end
  self.co = coroutine.create(function()
    self:exec(script, ctx, startPc)
    if ctx.trainerHinted and ctx.lastBattleResult == nil then
      local ok, err = pcall(require("src.core.Music").prepareBattle, self.game.data, "wild")
      if not ok then Logger.warn("wild battle music re-park failed: %s", tostring(err)) end
    end
    -- Commands can defer a game action until the script's own dialogue is
    -- done. start_battle uses this for win-path evolutions, which must not
    -- be covered by post-battle trainer text.
    for _, callback in ipairs(ctx.afterScript or {}) do callback() end
    if ctx.onDone then ctx.onDone() end
    if Runtime.wants("script.ended") then
      Runtime.emit("script.ended", { ctx = ctx, completed = true })
    end
  end)
  self:resume()
end

-- Execute a command list.  Supports labels via jump commands: a script is
-- an array of rows; control commands return a new program counter, as a
-- row number or a label name.
function ScriptRunner:exec(script, ctx, startPc)
  local labels = ScriptRunner.scanLabels(script)
  local data = self.game and self.game.data
  local pc = startPc or 1
  self:hintTrainerBattle(script, ctx, startPc)
  self.script = script
  while pc <= #script do
    self.pc = pc
    local row = script[pc]
    local name = row[1]
    local fn, meta = Commands.resolve(data, name)
    if not fn then
      -- api 2 owned scripts fail loudly; everything else keeps the v1
      -- skip so old content degrades instead of dying
      if ctx.source and ctx.source.strict then
        error(("unknown command '%s' at row %d"):format(tostring(name), pc), 0)
      end
      Logger.warn("script: unknown command '%s' (skipped)", tostring(name))
      pc = pc + 1
    else
      if self.parallel and meta and meta.foreground then
        error(("'%s' is a foreground command; illegal in a parallel script")
          :format(name), 0)
      end
      local jump
      if Runtime.wantsHook("script.command") then
        local args = { select(2, unpack(row)) }
        jump = Runtime.call("script.command", function(hctx, _, hargs)
          return fn(hctx, unpack(hargs))
        end, ctx, name, args)
      else
        jump = fn(ctx, select(2, unpack(row)))
      end
      if type(jump) == "string" then
        if jump == "end" then
          pc = math.huge
        else
          local target = labels[jump]
          if not target then
            error(("jump to missing label '%s' at row %d"):format(jump, pc), 0)
          end
          pc = target
        end
      elseif type(jump) == "number" then
        pc = jump
      else
        pc = pc + 1
      end
    end
  end
end

local CHECKPOINT_BATTLE_COMMANDS = {
  start_battle = true,
  static_battle = true,
  rival_battle = true,
}

local function dataCopy(value)
  local ok, encoded = pcall(SaveSerializer.encode, value)
  if not ok then return nil end
  return SaveSerializer.decode(encoded)
end

-- Return a detached semantic continuation only for built-in battle commands
-- whose post-yield behavior can be replayed from the current row. The live
-- coroutine and arbitrary completion callbacks never cross this boundary.
function ScriptRunner:battleCheckpointOrigin(battle)
  local row = self.script and self.script[self.pc]
  if not self:isRunning() or type(row) ~= "table"
      or not CHECKPOINT_BATTLE_COMMANDS[row[1]] then
    return nil
  end
  local ctx = self.ctx or {}
  if ctx.onDone ~= nil and ctx.checkpointOnDone ~= "release_npc" then
    return nil
  end
  local npcId = ctx.npc and ctx.npc.id or nil
  if ctx.checkpointOnDone == "release_npc" and type(npcId) ~= "string" then
    return nil
  end
  local map = self.overworld and self.overworld.map and self.overworld.map.id
  if type(map) ~= "string" then return nil end
  local origin = {
    kind = "script_battle",
    map = map,
    script = self.script,
    pc = self.pc,
    command = row[1],
    npcId = npcId,
    source = ctx.source,
    battleKind = battle and battle.kind,
    trainerClass = battle and battle.oppClass or nil,
    partyIndex = battle and battle.partyIndex or nil,
    wildSpecies = battle and battle.enemy and battle.enemy.mon
      and battle.enemy.mon.species or nil,
    wildLevel = battle and battle.enemy and battle.enemy.mon
      and battle.enemy.mon.level or nil,
  }
  return dataCopy(origin)
end

function ScriptRunner:isCheckpointBattle(battle)
  return self.checkpointBattle == battle and self:isRunning()
end

-- Called by blocking commands from inside the coroutine.
function ScriptRunner:yield()
  return coroutine.yield()
end

function ScriptRunner:resume(...)
  local co = self.co
  if not co then return end
  -- A completion callback can fire synchronously from inside the running
  -- coroutine (e.g. a battle that finishes during its own stack push when
  -- the party is already fainted).  Resuming a running coroutine is an
  -- error that would kill the whole script, so land the pending yield
  -- first and continue on the next update tick instead.
  if coroutine.status(co) == "running" then
    self.waitingFrames = 1
    return
  end
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    local source = self.ctx and self.ctx.source
    local where = source
      and Strings(" [%s %s.%s]", tostring(source.modId or "engine"),
        tostring(source.mapId or "?"), tostring(source.hook or "?"))
      or ""
    Logger.error("script error%s: %s", where, tostring(err))
    if source and source.modId then
      Runtime.reportError(source.modId, tostring(err))
    end
    if Runtime.wants("script.ended") then
      Runtime.emit("script.ended", { ctx = self.ctx, completed = false })
    end
    self.co = nil
    self.waitingFrames = nil
    self.waitingCheck = nil
  -- status via the captured co: a nested resume during the call above may
  -- already have torn self.co down, and status(nil) would throw
  elseif coroutine.status(co) == "dead" then
    if self.co == co then self.co = nil end
  end
end

function ScriptRunner:update()
  -- commands that wait on frames re-resume every step while running
  if self:isRunning() and self.waitingFrames then
    self.waitingFrames = self.waitingFrames - 1
    if self.waitingFrames <= 0 then
      self.waitingFrames = nil
      self:resume()
    end
  end
  -- per-frame condition polls (wait_flag, push_screen): the check returns
  -- done plus the value the yield should hand back
  if self:isRunning() and self.waitingCheck then
    local done, result = self.waitingCheck()
    if done then
      self.waitingCheck = nil
      self:resume(result)
    end
  end
end

return ScriptRunner
