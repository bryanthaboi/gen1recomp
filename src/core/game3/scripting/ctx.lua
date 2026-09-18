-- Game3 ScriptContext mirror.

local Ctx = {}

Ctx.SPECIAL_LO = 0x8000
Ctx.SPECIAL_HI = 0x8014
Ctx.TEMP_LO = 0x4000
Ctx.TEMP_HI = 0x400F
Ctx.GFX_VAR_LO = 0x4010
Ctx.GFX_VAR_HI = 0x401F

Ctx.VAR_FACING = 0x800C
Ctx.VAR_RESULT = 0x800D
Ctx.VAR_ITEM_ID = 0x800E
Ctx.VAR_LAST_TALKED = 0x800F
Ctx.VAR_TEXT_COLOR = 0x8012
Ctx.VAR_PREV_TEXT_COLOR = 0x8013
Ctx.TEXT_COLOR_DEFAULT = 255

function Ctx.isSpecial(id)
  id = tonumber(id) or 0
  return id >= Ctx.SPECIAL_LO and id <= Ctx.SPECIAL_HI
end

function Ctx.isTemp(id)
  id = tonumber(id) or 0
  return id >= Ctx.TEMP_LO and id <= Ctx.TEMP_HI
end

function Ctx.isGfxVar(id)
  id = tonumber(id) or 0
  return id >= Ctx.GFX_VAR_LO and id <= Ctx.GFX_VAR_HI
end

function Ctx.new(opts)
  opts = opts or {}
  return {
    mode = "stopped",       -- stopped | bytecode | native
    status = "shutdown",    -- shutdown | running | waiting
    stack = {},
    comparisonResult = 0,
    data = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 },
    stringVars = { [1] = "", [2] = "", [3] = "" },
    specialVars = { [Ctx.VAR_TEXT_COLOR] = Ctx.TEXT_COLOR_DEFAULT },
    lockSnapshots = {},
    lockKind = nil,         -- "single" | "all" | nil
    activeMoves = {},
    nativePoll = nil,
    pc = nil,               -- { listKey, index }
    messageOpen = false,
    frozen = false,
    playerName = opts.playerName or "PLAYER",
    rivalName = opts.rivalName or "RIVAL",
    warnings = {},
  }
end

function Ctx.wipeSpecial(ctx)
  ctx.specialVars = { [Ctx.VAR_TEXT_COLOR] = Ctx.TEXT_COLOR_DEFAULT } -- src/field_specials.c:1542
end

function Ctx.selectObject(ctx, localId)
  localId = tonumber(localId) or 0
  ctx.selectedLocalId = localId ~= 0 and localId or nil
  ctx.selectedGfx = nil
  if ctx.selectedLocalId then
    local Objects = package.loaded["src.core.game3.objects"]
    local obj = Objects and Objects.find and Objects.find(localId)
    ctx.selectedGfx = obj and (obj.graphicsId or (obj.def and (obj.def.graphicsId or obj.def.graphics))) or nil
  end
end

function Ctx.clearLocks(ctx)
  ctx.lockSnapshots = {}
  ctx.lockKind = nil
end

function Ctx.clearMoves(ctx)
  ctx.activeMoves = {}
  ctx.nativePoll = nil
end

function Ctx.haltCleanup(ctx)
  Ctx.wipeSpecial(ctx)
  Ctx.selectObject(ctx, 0)
  Ctx.clearLocks(ctx)
  Ctx.clearMoves(ctx)
  ctx.messageOpen = false
  ctx.frozen = false
  ctx.mode = "stopped"
  ctx.status = "shutdown"
  ctx.pc = nil
  ctx.stack = {}
  ctx.nativePoll = nil
end

function Ctx.clearTemps(store)
  if not store then return end
  for id = Ctx.TEMP_LO, Ctx.TEMP_HI do
    store[id] = nil
  end
end

function Ctx.modCtx(vm)
  local ok, Gen3Compat = pcall(require, "src.mods.Gen3Compat")
  if ok and type(Gen3Compat) == "table" and type(Gen3Compat.scriptCtx) == "function" then
    local okC, c = pcall(Gen3Compat.scriptCtx, vm)
    if okC and type(c) == "table" then return c end
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local Map = package.loaded["src.core.game3.map"]
  return {
    game = Runtime and Runtime._game,
    save = session,
    session = session,
    overworld = { map = { id = Map and Map.current } },
    runner = vm,
  }
end

return Ctx
