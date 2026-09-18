-- Battle AI script VM: run one pret AI script for one considered move.

local AiCmds = require("src.core.game3.battle.ai_cmds")

local AiVm = {}

local function resolve_move_id(mv)
  if mv == nil or mv == 0 or mv == "" then return 0 end
  if type(mv) == "number" then return mv end
  local Moves = require("src.core.game3.battle.moves")
  -- name → numeric id
  if Moves.BY_NUM then
    for id, name in pairs(Moves.BY_NUM) do
      if name == mv then return id end
    end
  end
  return 0
end

function AiVm.new(opts)
  opts = opts or {}
  local vm = {
    pack = opts.pack,
    st = opts.st,
    user = opts.user,     -- enemy battler
    target = opts.target, -- player battler
    userSide = opts.userSide,
    targetSide = opts.targetSide,
    scores = opts.scores,
    simulatedRNG = opts.simulatedRNG,
    movesetIndex = opts.movesetIndex or 1,
    moveConsidered = opts.moveConsidered or 0,
    funcResult = 0,
    stack = {},
    scriptName = nil,
    ops = nil,
    ip = 1,
    done = false,
    aiAction = 0,
    rng = opts.rng or math.random,
  }

  function vm:jump(name, ip)
    local body = self.pack and self.pack.scripts and self.pack.scripts[name]
    if not body then
      self.done = true
      return
    end
    self.scriptName = name
    self.ops = body
    self.ip = ip or 1
  end

  return vm
end

--- Run script `scriptName` for movesetIndex; mutates vm.scores[movesetIndex].
function AiVm.run(vm, scriptName)
  if not vm or not scriptName then return end
  local mon = vm.user and vm.user.mon
  local slot = vm.movesetIndex
  local mv = mon and mon.moves and mon.moves[slot]
  local pp = mon and mon.pp and mon.pp[slot]
  if not mv or mv == 0 or mv == "" or (pp ~= nil and tonumber(pp) <= 0) then
    vm.scores[slot] = 0
    return
  end
  vm.moveConsidered = resolve_move_id(mv)
  if vm.moveConsidered == 0 and type(mv) == "string" then
    -- keep string moves usable via Moves.get by name; store 0 for if_move numeric compares
    vm.moveConsidered = mv
  end
  vm.done = false
  vm.stack = {}
  vm.funcResult = 0
  vm:jump(scriptName)
  local guard = 0
  while not vm.done and guard < 100000 do
    guard = guard + 1
    local op = vm.ops and vm.ops[vm.ip]
    if not op then
      vm.done = true
      break
    end
    AiCmds.dispatch(vm, op)
  end
end

AiVm.resolve_move_id = resolve_move_id

return AiVm
