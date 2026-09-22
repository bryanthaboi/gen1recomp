-- Tier A (+ movement) opcode handlers. Return true = yield (wait).

local Opcodes = require("src.core.game3.scripting.opcodes")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local TextIR = require("src.core.game3.scripting.text_ir")
local Natives = require("src.core.game3.scripting.natives")
local Movement = require("src.core.game3.scripting.movement")
local ModRuntime = require("src.mods.Runtime")

local Ops = {}

-- scrcmd.c
local PRET_NO_OPS = {
  initclock = true,           -- scrcmd.c:658-664
  dotimebasedevents = true,   -- scrcmd.c:667-671
  adddecoration = true,       -- scrcmd.c:526-532
  removedecoration = true,    -- scrcmd.c:534-540
  checkdecor = true,          -- scrcmd.c:550-556
  checkdecorspace = true,     -- scrcmd.c:542-548
  drawbox = true,             -- scrcmd.c:1464-1472
  drawboxtext = true,         -- scrcmd.c:1505-1516
  showcontestpainting = true, -- scrcmd.c:1543-1552
  setberrytree = true,        -- scrcmd.c:1989-1999
  startcontest = true,        -- scrcmd.c:2018-2024
  showcontestresults = true,  -- scrcmd.c:2026-2032
  contestlinktransfer = true, -- scrcmd.c:2034-2040
  getpokenewsactive = true,   -- scrcmd.c:2002-2008
  addelevmenuitem = true,     -- scrcmd.c:2178-2187
  showelevmenu = true,        -- scrcmd.c:2189-2194
}

local function cond_ok(ctx, cond)
  local r = ctx.comparisonResult or 0
  -- FRLG: 0=lt, 1=eq, 2=gt from compare; checkflag sets 1 if set else 0
  if cond == 0 then return r == 0 end      -- LT / FALSE-ish
  if cond == 1 then return r == 1 end      -- EQ / TRUE
  if cond == 2 then return r == 2 end      -- GT
  if cond == 3 then return r ~= 2 end      -- LE
  if cond == 4 then return r ~= 0 end      -- GE
  if cond == 5 then return r ~= 1 end      -- NE
  return false
end

local function jump(vm, target)
  if type(target) == "string" then
    vm:setPc(target, 1)
  elseif type(target) == "table" and target.listKey then
    vm:setPc(target.listKey, target.index or 1)
  else
    -- numeric ROM addr → key
    vm:setPc(Opcodes.key(target), 1)
  end
end

local function resolve_text(vm, ptr)
  if ptr == 0 or ptr == nil then
    ptr = vm.ctx.data[0]
  end
  if type(ptr) == "string" then
    return vm:getText(ptr)
  end
  local key = Opcodes.key(ptr)
  return vm:getText(key) or vm:getText(ptr)
end

local function var_get(store, ctx, id)
  id = tonumber(id) or 0
  -- FRLG VarGet: ids ≥ VARS_START (0x4000) are variables; else literal.
  -- pokefirered/include/constants/vars.h:310,313,337
  if (id >= 0x4000 and id <= 0x40FF) or (id >= 0x8000 and id <= 0x8014) then
    return Flags.getVar(store, ctx, id)
  end
  return id
end

-- Script local scratch space: pret's ScriptContext.data[4] (include/script.h:21).
local function local_get(ctx, i)
  return ctx.data[tonumber(i) or 0] or 0
end

local function local_set(ctx, i, v)
  ctx.data[tonumber(i) or 0] = v or 0
end

-- The port has no flat address space, so the *ptr family shares a synthetic
-- byte store keyed by the pointer value.  Pointers a script writes then reads
-- round-trip; pointers into engine structures read as 0 (they did before too).
local function mem_get(ctx, ptr)
  ctx.scriptMem = ctx.scriptMem or {}
  return tonumber(ctx.scriptMem[tonumber(ptr) or 0]) or 0
end

local function mem_set(ctx, ptr, v)
  ctx.scriptMem = ctx.scriptMem or {}
  ctx.scriptMem[tonumber(ptr) or 0] = (tonumber(v) or 0) % 256
end

-- pret src/scrcmd.c:358 Compare()
local function cmp(a, b)
  -- pokefirered/src/scrcmd.c:368: local comparisons read the low byte.
  a, b = (tonumber(a) or 0) % 256, (tonumber(b) or 0) % 256
  if a < b then return 0 end
  if a == b then return 1 end
  return 2
end

local function coins_api()
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local okBag, Bag = pcall(require, "src.core.game3.bag")
  local api = (okBag and type(Bag) == "table") and Bag.Coins or nil
  if type(api) ~= "table" then api = nil end
  return api, session
end

-- pokefirered/src/coins.c:11
local function coins_get()
  local api, session = coins_api()
  if api and type(api.get) == "function" then
    local ok, n = pcall(api.get, session)
    if ok and tonumber(n) then return tonumber(n) end
  end
  local raw = math.floor(tonumber(session and session.coins) or 0)
  return raw < 0 and 0 or raw
end

-- pokefirered/src/coins.c:21
local function coins_move(add, amount)
  amount = math.floor(tonumber(amount) or 0)
  if amount < 0 then amount = 0 end
  local api, session = coins_api()
  local fn = api and (add and api.add or api.remove)
  if type(fn) ~= "function" then return false end
  local ok, res = pcall(fn, session, amount)
  return (ok and res) and true or false
end

-- pokefirered/src/quest_log.c:860
local function ql_avoid_display()
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  return (game and game.phase == "quest_log") and true or false
end

-- pokefirered/src/coins.c:79
local function coins_box(fn, ...)
  local okReq, Box = pcall(require, "src.ui.game3.coins_box")
  if not (okReq and type(Box) == "table" and type(Box[fn]) == "function") then return false end
  return (pcall(Box[fn], ...))
end

local function message_print_done()
  local Message = package.loaded["src.ui.game3.message"]
  if not Message or not Message.isOpen or not Message.isOpen() then
    return true
  end
  if Message.isWaiting and not Message.isWaiting() then
    return false
  end
  local pages = Message._pages
  local page = Message._page or 1
  if type(pages) == "table" and page < #pages then
    return false
  end
  return true
end

local function show_message(vm, ptr, stay)
  local ir = resolve_text(vm, ptr)
  local a = vm.adapters
  local ctx = vm.ctx
  -- Pret ShowFieldMessage: open box + start printer; do not wait for dismiss.
  -- waitmessage waits for print-complete; waitbuttonpress / yesnobox follow.
  local body
  if not ir then
    body = "(missing text)"
  else
    local ctxView = {
      stringVars = ctx.stringVars,
      playerName = a.playerName
        and (type(a.playerName) == "function" and a.playerName() or a.playerName)
        or ctx.playerName,
      rivalName = a.rivalName
        and (type(a.rivalName) == "function" and a.rivalName() or a.rivalName)
        or ctx.rivalName,
    }
    body = TextIR.toTextBox(ir, ctxView)
  end
  ctx.messageOpen = true
  ctx.printerDone = false
  local openStay = a.openMessageStay or a.openMessageAsync
  if openStay then
    -- Always stay: box remains until closemessage / release (pret field box).
    openStay(body, nil)
  elseif a.openMessage then
    a.openMessage(body)
  end
  return false
end

local function text_ctx_view(vm)
  local ctx = vm.ctx
  local a = vm.adapters
  return {
    stringVars = ctx.stringVars,
    playerName = a.playerName
      and (type(a.playerName) == "function" and a.playerName() or a.playerName)
      or ctx.playerName,
    rivalName = a.rivalName
      and (type(a.rivalName) == "function" and a.rivalName() or a.rivalName)
      or ctx.rivalName,
  }
end

-- pokefirered/src/braille_text.c:209
local BRAILLE_GLYPH_WIDTH = 16

-- pokefirered/src/text.c:1020
local function braille_width(ir)
  if type(ir) ~= "table" then return 0 end
  local best, line = 0, 0
  for _, seg in ipairs(ir) do
    if seg.t == "text" then
      local glyphs = select(2, tostring(seg.s or ""):gsub("[^\128-\191]", ""))
      line = line + glyphs * BRAILLE_GLYPH_WIDTH
    elseif seg.t == "nl" then
      if line > best then best = line end
      line = 0
    end
  end
  if line > best then best = line end
  return best
end

-- pokefirered/src/overworld.c:978
local function set_map_layout(layoutId, log)
  layoutId = tonumber(layoutId)
  if not layoutId then return false end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local mapId = session and session.map
  local def = mapId and game and game.data and game.data.maps and game.data.maps[mapId]
  local layout = def and def.midLayout
  if not layout then return false end
  local Extract = require("src.import.gba.extract_island1")
  local Dataset = require("src.core.game3.dataset")
  local root = Extract.NATIVE_ROOT
    or ((Extract.CACHE_ROOT or "data/generated/gba") .. "/native")
  local blob = Dataset.cache():read(root .. "/layouts/alt_" .. layoutId .. ".mid")
  if not blob then
    if log then log("[game3] setmaplayoutindex " .. layoutId .. ": no baked layout") end
    return false
  end
  local NativePack = require("src.import.gba.native_pack")
  local decoded = NativePack.decodeMidLayout(blob)
  if not decoded or decoded.width ~= layout.width or decoded.height ~= layout.height then
    if log then log("[game3] setmaplayoutindex " .. layoutId .. ": size mismatch") end
    return false
  end
  local swapped = 0
  for i = 1, decoded.width * decoded.height do
    local cell = decoded.cells[i]
    if cell then
      local x = (i - 1) % decoded.width
      local y = math.floor((i - 1) / decoded.width)
      local cur = layout:cellAt(x, y)
      if cur.mid ~= cell.mid or cur.coll ~= cell.coll or cur.elev ~= cell.elev then
        layout:applyOverride(x, y, cell.mid, cell.coll, cell.elev)
        swapped = swapped + 1
      end
    end
  end
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field._overrideLayouts then Field._overrideLayouts[mapId] = layout end
  local Collision = package.loaded["src.core.game3.collision"]
  if Collision and Collision.bindMap then Collision.bindMap(game, mapId, def) end
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then FieldView._nativeDirty = true end
  return true, swapped
end

-- pokefirered/include/constants/maps.h:11
local function warp_hole_dest(group, num)
  group, num = tonumber(group) or 0, tonumber(num) or 0
  if group == 0xFF and num == 0xFF then return nil end
  local Versions = require("src.import.gba.versions")
  return (Versions.frMapFor and Versions.frMapFor(group, num))
    or (Versions.seviiMapFor and Versions.seviiMapFor(group, num))
end

-- pret's *at script commands carry an explicit (mapGroup, mapNum) so a script
-- can address another map's objects (asm/macros/event.inc:597-652).  The host
-- object/movement seams only address the current map, so resolve the target
-- map first and skip (with a note) when it is somewhere else.
local function objectat_same_map(store, ctx, row, groupIdx)
  local group = var_get(store, ctx, row[groupIdx])
  local num = tonumber(var_get(store, ctx, row[groupIdx + 1]))
  local Map = package.loaded["src.core.game3.map"]
  local current = Map and Map.current
  if group == nil or num == nil or not current then return true end
  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  local dest = okC and MapCatalog and MapCatalog.mapIdFor(group, num) or nil
  if type(dest) ~= "string" then
    local okV, Versions = pcall(require, "src.import.gba.versions")
    dest = okV and Versions and Versions.mapIdFor
      and Versions.mapIdFor(group, num) or nil
  end
  if type(dest) ~= "string" then return true end
  return dest == current
end

local function dispatch(vm, row)
  local op = row.op
  local ctx = vm.ctx
  local store = vm.store
  local a = vm.adapters

  if op == "nop" or op == "nop1" then
    return false
  elseif op == "end" then
    vm:halt()
    return true
  elseif op == "return" then
    local frame = table.remove(ctx.stack)
    if not frame then
      vm:halt()
      return true
    end
    vm:setPc(frame.listKey, frame.index)
    return false
  elseif op == "call" then
    if #ctx.stack >= 20 then
      a.log("[game3] call stack overflow")
      return false
    end
    -- VM advances PC before dispatch; cur.index is already the return site.
    local cur = ctx.pc
    ctx.stack[#ctx.stack + 1] = {
      listKey = cur.listKey,
      index = cur.index,
    }
    jump(vm, row.target or row[1])
    return false
  elseif op == "goto" then
    jump(vm, row.target or row[1])
    return false
  elseif op == "goto_if" then
    if cond_ok(ctx, row.cond or row[1]) then
      jump(vm, row.target or row[2])
    end
    return false
  elseif op == "call_if" then
    if cond_ok(ctx, row.cond or row[1]) then
      if #ctx.stack >= 20 then
        a.log("[game3] call stack overflow")
        return false
      end
      local cur = ctx.pc
      ctx.stack[#ctx.stack + 1] = {
        listKey = cur.listKey,
        index = cur.index,
      }
      jump(vm, row.target or row[2])
    end
    return false
  elseif op == "callstd" then
    local std = row.std or row[1]
    local key = "std:" .. tostring(std)
    if not vm.scripts[key] then
      a.log("[game3] missing " .. key .. " — skipping")
      return false
    end
    if #ctx.stack >= 20 then return false end
    local cur = ctx.pc
    ctx.stack[#ctx.stack + 1] = {
      listKey = cur.listKey,
      index = cur.index,
    }
    vm:setPc(key, 1)
    return false
  elseif op == "gotostd" then
    local key = "std:" .. tostring(row.std or row[1])
    if not vm.scripts[key] then
      a.log("[game3] missing " .. key .. " — skipping")
      return false
    end
    vm:setPc(key, 1)
    return false
  elseif op == "callstd_if" or op == "gotostd_if" then
    -- pret asm/macros/event.inc: .byte op / .byte condition / .byte std.
    -- callstd_if returns to the caller; gotostd_if does not.
    if not cond_ok(ctx, row.cond or row[1]) then return false end
    local key = "std:" .. tostring(row.std or row[2])
    if not vm.scripts[key] then
      a.log("[game3] missing " .. key .. " — skipping")
      return false
    end
    if op == "callstd_if" then
      if #ctx.stack >= 20 then return false end
      local cur = ctx.pc
      ctx.stack[#ctx.stack + 1] = {
        listKey = cur.listKey,
        index = cur.index,
      }
    end
    vm:setPc(key, 1)
    return false
  elseif op == "loadword" then
    local dest = row.dest or row[1] or 0
    local value = row.value or row[2]
    ctx.data[dest] = value
    return false
  elseif op == "loadbyte" then
    ctx.data[row[1] or 0] = row[2] or 0
    return false
  elseif op == "setvar" then
    Flags.setVar(store, ctx, row.var or row[1], row.value or row[2])
    return false
  elseif op == "addvar" then
    -- pokefirered/src/scrcmd.c:441
    local id = row.var or row[1]
    Flags.setVar(store, ctx, id, Flags.getVar(store, ctx, id) + (tonumber(row.value or row[2]) or 0))
    return false
  elseif op == "subvar" then
    -- pokefirered/src/scrcmd.c:448
    local id = row.var or row[1]
    Flags.setVar(store, ctx, id, Flags.getVar(store, ctx, id) - var_get(store, ctx, row.value or row[2]))
    return false
  elseif op == "copyvar" then
    local v = Flags.getVar(store, ctx, row[2])
    Flags.setVar(store, ctx, row[1], v)
    return false
  elseif op == "setorcopyvar" then
    -- if src is var id in special/normal range treat as copy; else set literal — cart uses bit.
    local src = row[2] or 0
    if src >= 0x4000 then
      Flags.setVar(store, ctx, row[1], Flags.getVar(store, ctx, src))
    else
      Flags.setVar(store, ctx, row[1], src)
    end
    return false
  elseif op == "compare_var_to_value" then
    local v = Flags.getVar(store, ctx, row.var or row[1])
    local n = row.value or row[2] or 0
    if v < n then ctx.comparisonResult = 0
    elseif v == n then ctx.comparisonResult = 1
    else ctx.comparisonResult = 2 end
    return false
  elseif op == "compare_var_to_var" then
    local a1 = Flags.getVar(store, ctx, row[1])
    local b1 = Flags.getVar(store, ctx, row[2])
    if a1 < b1 then ctx.comparisonResult = 0
    elseif a1 == b1 then ctx.comparisonResult = 1
    else ctx.comparisonResult = 2 end
    return false
  elseif op == "setflag" then
    local flag = row.flag or row[1]
    Flags.setFlag(store, ctx, flag, true)
    if a.onFlagChanged then a.onFlagChanged(flag, true) end
    return false
  elseif op == "clearflag" then
    local flag = row.flag or row[1]
    Flags.setFlag(store, ctx, flag, false)
    -- pret: clearing an object hide flag makes the template eligible; scripts
    -- often removeobject then clearflag without addobject (Oak lab intro).
    if a.onFlagChanged then a.onFlagChanged(flag, false) end
    return false
  elseif op == "checkflag" then
    ctx.comparisonResult = Flags.getFlag(store, ctx, row.flag or row[1]) and 1 or 0
    return false
  elseif op == "goto_if_set" then
    -- not a real op; handled via checkflag+goto_if in extract
    return false
  elseif op == "faceplayer" then
    local lid = Flags.getVar(store, ctx, Ctx.VAR_LAST_TALKED)
    if a.facePlayer then a.facePlayer(lid) end
    return false
  elseif op == "lock" then
    local lid = Flags.getVar(store, ctx, Ctx.VAR_LAST_TALKED)
    ctx.lockKind = "single"
    ctx.lockSnapshots = {}
    local snap = { facing = a.facing and a.facing[lid], movementType = "idle" }
    ctx.lockSnapshots[lid] = snap
    if a.freezeLocal then a.freezeLocal(lid, snap) end
    ctx.frozen = true
    local okF, Field = pcall(require, "src.core.game3.field")
    if okF and Field and Field.lock then Field.lock() end
    return false
  elseif op == "lockall" then
    ctx.lockKind = "all"
    ctx.lockSnapshots = {}
    local ids = (a.listActiveLocalIds and a.listActiveLocalIds()) or {}
    for _, lid in ipairs(ids) do
      local snap = { facing = a.facing and a.facing[lid], movementType = "idle" }
      ctx.lockSnapshots[lid] = snap
      if a.freezeLocal then a.freezeLocal(lid, snap) end
    end
    ctx.frozen = true
    local okF, Field = pcall(require, "src.core.game3.field")
    if okF and Field and Field.lock then Field.lock() end
    return false
  elseif op == "release" then
    if ctx.lockKind and ctx.lockKind ~= "single" then
      a.log("[game3] release after lockall — restoring lockSnapshots only")
    end
    for lid, snap in pairs(ctx.lockSnapshots) do
      if a.unfreezeLocal then a.unfreezeLocal(lid, snap) end
    end
    ctx.lockSnapshots = {}
    ctx.lockKind = nil
    if ctx.messageOpen then
      if a.closeMessage then a.closeMessage() end
      ctx.messageOpen = false
    end
    local okMB, MoneyBox = pcall(require, "src.ui.game3.money_box")
    if okMB and MoneyBox and MoneyBox.hide then MoneyBox.hide() end
    ctx.frozen = false
    local okF, Field = pcall(require, "src.core.game3.field")
    if okF and Field and Field.unlock then Field.unlock() end
    return false
  elseif op == "releaseall" then
    if ctx.lockKind and ctx.lockKind ~= "all" then
      a.log("[game3] releaseall after lock — clearing all snapshots")
    end
    for lid, snap in pairs(ctx.lockSnapshots) do
      if a.unfreezeLocal then a.unfreezeLocal(lid, snap) end
    end
    ctx.lockSnapshots = {}
    ctx.lockKind = nil
    if ctx.messageOpen then
      if a.closeMessage then a.closeMessage() end
      ctx.messageOpen = false
    end
    local okMB, MoneyBox = pcall(require, "src.ui.game3.money_box")
    if okMB and MoneyBox and MoneyBox.hide then MoneyBox.hide() end
    ctx.frozen = false
    local okF, Field = pcall(require, "src.core.game3.field")
    if okF and Field and Field.unlock then Field.unlock() end
    return false
  elseif op == "message" then
    return show_message(vm, row.ptr or row[1], row.stay)
  elseif op == "yesnobox" then
    -- Host YES/NO over stayed textbox; writes VAR_RESULT (1=yes, 0=no).
    local answered = false
    local left = tonumber(row[1] or row.x) or 20
    local top = tonumber(row[2] or row.y) or 8
    ctx.mode = "native"
    ctx.status = "waiting"
    ctx.nativePoll = function() return answered end
    local ask = a.askYesNo
    if ask then
      ask(function(yes)
        Flags.setVar(store, ctx, Ctx.VAR_RESULT, yes and 1 or 0)
        answered = true
      end, { left = left, top = top })
    else
      Flags.setVar(store, ctx, Ctx.VAR_RESULT, 1)
      answered = true
    end
    if answered then
      ctx.mode = "bytecode"
      ctx.status = "running"
      ctx.nativePoll = nil
      return false
    end
    return true
  elseif op == "waitmessage" then
    -- Pret: wait until text printer finished (box stays visible).
    if message_print_done() then
      ctx.printerDone = true
      return false
    end
    ctx.mode = "native"
    ctx.status = "waiting"
    ctx.nativePoll = function()
      if message_print_done() then
        ctx.printerDone = true
        return true
      end
      return false
    end
    return true
  elseif op == "waitbuttonpress" then
    -- Pret: A/B while message box still up (after waitmessage).
    local pressed = false
    ctx.mode = "native"
    ctx.status = "waiting"
    ctx.nativePoll = function() return pressed end
    if a.armWaitButton then
      -- pokefirered/src/scrcmd.c:1401, pokefirered/src/script.c:95
      local armed = false
      ctx.nativePoll = function()
        if not armed then
          armed = true
          a.armWaitButton(function()
            pressed = true
          end)
        end
        return pressed
      end
      return true
    elseif a.waitButton then
      a.waitButton(function()
        pressed = true
      end)
    else
      pressed = true
    end
    if pressed then
      ctx.mode = "bytecode"
      ctx.status = "running"
      ctx.nativePoll = nil
      return false
    end
    return true
  elseif op == "closemessage" then
    if a.closeMessage then a.closeMessage() end
    ctx.messageOpen = false
    return false
  elseif op == "showmonpic" then
    local species = var_get(store, ctx, row[1] or row.species)
    local x = tonumber(row[2] or row.x) or 10
    local y = tonumber(row[3] or row.y) or 3
    if a.showMonPic then
      a.showMonPic(species, x, y)
    else
      local MonPic = require("src.ui.game3.mon_pic")
      MonPic.show(species, x, y)
    end
    return false
  elseif op == "hidemonpic" then
    if a.hideMonPic then
      a.hideMonPic()
    else
      local MonPic = require("src.ui.game3.mon_pic")
      MonPic.hide()
    end
    return false
  elseif op == "givemon" then
    local species = var_get(store, ctx, row[1] or row.species)
    local level = var_get(store, ctx, row[2] or row.level)
    if level < 1 then level = 5 end
    local nickname
    if ModRuntime.wants("pokemon.before_give") then
      local Pokemon = require("src.core.game3.pokemon")
      local gift = {
        ctx = Ctx.modCtx(vm),
        species = Pokemon.keyName(species) or species,
        speciesId = species,
        level = level,
      }
      ModRuntime.emit("pokemon.before_give", gift)
      local id = type(gift.species) == "number" and gift.species
        or Pokemon.speciesFromName(gift.species)
      if tonumber(id) and tonumber(id) >= 1 and tonumber(id) ~= species then
        species = tonumber(id)
        local src = tonumber(row[1] or row.species) or 0
        if src >= 0x4000 then Flags.setVar(store, ctx, src, species) end
      end
      if tonumber(gift.level) then
        level = math.max(1, math.min(100, math.floor(tonumber(gift.level))))
      end
      if type(gift.nickname) == "string" and gift.nickname ~= "" then
        nickname = gift.nickname
      end
    end
    -- pokefirered/src/script_pokemon_util.c:48
    local code
    if a.giveMonToPlayer then
      code = tonumber((a.giveMonToPlayer(species, level, row[3], nickname)))
    elseif a.giveMon then
      local ok, c = a.giveMon(species, level, row[3], row[4], row[5], nickname)
      code = tonumber(c) or (ok and 0 or 2)
    else
      local Party = require("src.core.game3.party")
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      if session then
        code = tonumber((Party.giveMonToPlayer(session, species, level, nickname)))
      end
    end
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, code or 2)
    return false
  elseif op == "giveegg" then
    local species = var_get(store, ctx, row[1] or row.species)
    -- pokefirered/src/script_pokemon_util.c:75
    local code
    if a.giveEggToPlayer then
      code = tonumber((a.giveEggToPlayer(species)))
    elseif a.giveEgg then
      local ok, c = a.giveEgg(species)
      code = tonumber(c) or (ok and 0 or 2)
    else
      local Party = require("src.core.game3.party")
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      if session then
        code = tonumber((Party.giveEggToPlayer(session, species)))
      end
    end
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, code or 2)
    return false
  elseif op == "textcolor" then
    Flags.setVar(store, ctx, Ctx.VAR_PREV_TEXT_COLOR, Flags.getVar(store, ctx, Ctx.VAR_TEXT_COLOR)) -- src/scrcmd.c:1257
    Flags.setVar(store, ctx, Ctx.VAR_TEXT_COLOR, row.color or row[1] or 0)
    return false
  elseif op == "signmsg" or op == "normalmsg" then
    local Message = package.loaded["src.ui.game3.message"]
    if not Message then
      local ok, M = pcall(require, "src.ui.game3.message")
      if ok then Message = M end
    end
    if Message and Message.setFrame then
      Message.setFrame(op == "signmsg" and "sign" or "dialogue")
    end
    return false
  elseif op == "setworldmapflag" then
    local flag = row.flag or row[1]
    -- MapPreview_SetFlag: capture the pre-visit state for the forest preview
    -- duration, then set the flag (map_preview_screen.c:605).
    do
      local ok, MapPreviewScreen = pcall(require, "src.ui.game3.map_preview_screen")
      if ok and MapPreviewScreen and MapPreviewScreen.setVisitedFlag then
        MapPreviewScreen.setVisitedFlag(flag, Flags.getFlag(store, ctx, flag) == true)
      end
    end
    Flags.setFlag(store, ctx, flag, true)
    -- Host Sevii Town Map unlock (One Island region map page).
    if tonumber(flag) == Flags.IDS.WORLD_MAP_ONE_ISLAND
        or tonumber(flag) == Flags.IDS.SYS_SEVII_MAP_123 then
      local ok, TownMap = pcall(require, "src.core.game3.town_map_stub")
      if ok and TownMap.unlockSeviiMap then
        local Space = package.loaded["src.core.game3.scripting.space"]
        TownMap.unlockSeviiMap((vm and vm._mod) or (Space and Space._mod))
      end
    end
    return false
  elseif op == "callnative" then
    if Natives.callnative(ctx, row.fn or row[1], a) then
      return true
    end
    return false
  elseif op == "special" then
    if Natives.special(ctx, row.id or row[1], a) then
      return true
    end
    return false
  elseif op == "specialvar" then
    -- pokefirered/src/scrcmd.c:109
    local yield, value, known = Natives.special(ctx, row[2], a)
    if value == nil and not known then value = 0 end
    if value ~= nil then
      Flags.setVar(store, ctx, row[1], value)
    end
    if yield then
      return true
    end
    return false
  elseif op == "waitstate" then
    -- pokefirered/src/scrcmd.c:127
    local task = ctx.stateWait
    ctx.stateWait = nil
    local inner = (ctx.mode == "native") and ctx.nativePoll or nil
    if task or ctx.warpPending or inner then
      ctx.mode = "native"
      ctx.status = "waiting"
      ctx.nativePoll = function()
        if ctx.warpPending then
          if a.pollWarp then a.pollWarp() end
          if ctx.warpPending then return false end
        end
        if task and not task() then return false end
        if inner and not inner() then return false end
        return true
      end
      if ctx.nativePoll() then
        ctx.mode = "bytecode"
        ctx.status = "running"
        ctx.nativePoll = nil
        return false
      end
      return true
    end
    return false
  elseif op == "applymovement" then
    local lid = var_get(store, ctx, row.localId or row[1])
    local mv = row.movement or row[2]
    local bytes = mv
    if type(mv) == "string" or (type(mv) == "number" and a.lookupMovement) then
      bytes = a.lookupMovement and a.lookupMovement(mv) or mv
    end
    Movement.start(ctx, lid, bytes, a)
    return false -- async; do not wait
  elseif op == "waitmovement" then
    local lid = var_get(store, ctx, row.localId or row[1] or 0)
    ctx.mode = "native"
    ctx.status = "waiting"
    ctx.nativePoll = Movement.makePoll(ctx, lid, a)
    if ctx.nativePoll() then
      ctx.mode = "bytecode"
      ctx.status = "running"
      ctx.nativePoll = nil
      return false
    end
    return true
  elseif op == "removeobject" then
    local lid = var_get(store, ctx, row.localId or row[1])
    if a.removeObject then a.removeObject(lid) end
    return false
  elseif op == "comparestat" then
    -- pret ScrCmd_comparestat: .byte statIdx / .4byte value; sets
    -- ctx.comparisonResult to 0 (lt) / 1 (eq) / 2 (gt) from the game stat.
    local statIdx = tonumber(row[1]) or 0
    local value = tonumber(row[2]) or 0
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local stats = session and session.gameStats or {}
    local statValue = tonumber(stats[statIdx]) or 0
    ctx.comparisonResult = statValue < value and 0
      or (statValue == value and 1 or 2)
    return false
  elseif op == "bufferitemnameplural" then
    -- pret ScrCmd_bufferitemnameplural: the item's name pluralised the way the
    -- ROM does -- "S" for a Poké Ball stack, "IES" replacing the final letter
    -- for berries, and the plain name otherwise.
    local dest = (row.dest or row[1] or 0) + 1
    local item = var_get(store, ctx, row[2])
    local qty = tonumber(var_get(store, ctx, row[3])) or 1
    local ItemsData = require("src.core.game3.items_data")
    local name = (ItemsData.displayName and ItemsData.displayName(item))
      or tostring(item)
    if qty >= 2 then
      if tonumber(item) == 4 then -- ITEM_POKE_BALL (include/constants/items.h:8)
        name = name .. "S"
      elseif ItemsData.isBerry and ItemsData.isBerry(item) then
        name = name:sub(1, -2) .. "IES"
      end
    end
    ctx.stringVars[dest] = name
    return false
  elseif op == "setmonmove" or op == "setmonmetlocation"
      or op == "setmonmodernfatefulencounter"
      or op == "checkmonmodernfatefulencounter" then
    -- pret ScrCmd_* (src/scrcmd.c:1767, :2239, :2248, :2256).  Party indices,
    -- move slots and map-section ids are 0-based in the ROM.
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local idx = (tonumber(var_get(store, ctx, row[1])) or 0) + 1
    local mon = session and session.party and session.party[idx]
    if op == "setmonmove" then
      local slot = (tonumber(var_get(store, ctx, row[2])) or 0) + 1
      local move = tonumber(var_get(store, ctx, row[3])) or 0
      local Pokemon = require("src.core.game3.pokemon")
      if mon and Pokemon.replaceMove then Pokemon.replaceMove(mon, slot, move) end
    elseif op == "setmonmetlocation" then
      if mon then mon.metLocation = tonumber(row[2]) or 0 end
    elseif op == "setmonmodernfatefulencounter" then
      if mon then mon.modernFatefulEncounter = true end
    else
      Flags.setVar(store, ctx, Ctx.VAR_RESULT,
        (mon and mon.modernFatefulEncounter) and 1 or 0)
    end
    return false
  elseif op == "copylocal" then
    -- pret ScrCmd_copylocal (src/scrcmd.c:321)
    local_set(ctx, row[1], local_get(ctx, row[2]))
    return false
  elseif op == "setptr" then
    -- pret ScrCmd_setptr (src/scrcmd.c:300): value byte, then pointer word.
    mem_set(ctx, row[2], row[1])
    return false
  elseif op == "loadbytefromptr" then
    -- pret ScrCmd_loadbytefromptr (src/scrcmd.c:293)
    local_set(ctx, row[1], mem_get(ctx, row[2]))
    return false
  elseif op == "setptrbyte" then
    -- pret ScrCmd_setptrbyte (src/scrcmd.c:314)
    mem_set(ctx, row[2], local_get(ctx, row[1]))
    return false
  elseif op == "copybyte" then
    -- pret ScrCmd_copybyte (src/scrcmd.c:329)
    mem_set(ctx, row[1], mem_get(ctx, row[2]))
    return false
  elseif op == "compare_local_to_local" then
    -- pret ScrCmd_compare_local_to_local (src/scrcmd.c:368)
    ctx.comparisonResult = cmp(local_get(ctx, row[1]), local_get(ctx, row[2]))
    return false
  elseif op == "compare_local_to_value" then
    ctx.comparisonResult = cmp(local_get(ctx, row[1]), row[2])
    return false
  elseif op == "compare_local_to_ptr" then
    ctx.comparisonResult = cmp(local_get(ctx, row[1]), mem_get(ctx, row[2]))
    return false
  elseif op == "compare_ptr_to_local" then
    ctx.comparisonResult = cmp(mem_get(ctx, row[1]), local_get(ctx, row[2]))
    return false
  elseif op == "compare_ptr_to_value" then
    ctx.comparisonResult = cmp(mem_get(ctx, row[1]), row[2])
    return false
  elseif op == "compare_ptr_to_ptr" then
    ctx.comparisonResult = cmp(mem_get(ctx, row[1]), mem_get(ctx, row[2]))
    return false
  elseif op == "vgoto" or op == "vcall" or op == "vgoto_if" or op == "vcall_if" then
    -- pret ScrCmd_vgoto/vcall/vgoto_if/vcall_if (src/scrcmd.c:180-209).  The
    -- ROM's sAddressOffset relocation is unnecessary here: script pointers are
    -- engine keys, which Opcodes.key()/jump() already resolve.
    local cond = true
    local dest = row.target or row[1]
    if op == "vgoto_if" or op == "vcall_if" then
      cond = cond_ok(ctx, row.cond or row[1])
      dest = row.target or row[2]
    end
    if cond then
      if op == "vcall" or op == "vcall_if" then
        if #ctx.stack >= 20 then
          a.log("[game3] vcall stack overflow")
          return false
        end
        local cur = ctx.pc
        ctx.stack[#ctx.stack + 1] = { listKey = cur.listKey, index = cur.index }
      end
      jump(vm, dest)
    end
    return false
  elseif op == "setvaddress" then
    -- pret ScrCmd_setvaddress (src/scrcmd.c:171) records a ROM-address
    -- relocation for the v* family; the port resolves pointers by key, so
    -- there is nothing to relocate.  Kept for bookkeeping only.
    ctx.vaddress = row[1]
    return false
  elseif op == "vmessage" then
    -- pret ScrCmd_vmessage (src/scrcmd.c:1580) shows a field message.
    return show_message(vm, row[1], false)
  elseif op == "vbuffermessage" then
    -- pret ScrCmd_vbuffermessage (src/scrcmd.c:1706) expands placeholders into
    -- the field message buffer (gStringVar4 → ctx.stringVars[4]).
    local ir = resolve_text(vm, row[1])
    ctx.stringVars[4] = ir and TextIR.toPlain(ir, {
      stringVars = ctx.stringVars,
      playerName = a.playerName,
      rivalName = a.rivalName,
    }) or ""
    return false
  elseif op == "vbufferstring" then
    -- pret ScrCmd_vbufferstring (src/scrcmd.c:1714)
    local dest = (row.dest or row[1] or 0) + 1
    local ir = resolve_text(vm, row.ptr or row[2])
    ctx.stringVars[dest] = ir and TextIR.toPlain(ir, { stringVars = ctx.stringVars }) or ""
    return false
  elseif op == "endram" then
    -- pret ScrCmd_endram (src/scrcmd.c:262) clears the RAM script and stops.
    vm:halt()
    return true
  elseif op == "returnram" then
    -- pret ScrCmd_returnram (src/scrcmd.c:256) resumes the RAM script's caller.
    local frame = table.remove(ctx.stack)
    if not frame then
      vm:halt()
      return true
    end
    vm:setPc(frame.listKey, frame.index)
    return false
  elseif op == "checkpcitem" or op == "addpcitem" then
    -- pret ScrCmd_checkpcitem / ScrCmd_addpcitem: the Player PC item bag.
    -- VAR_RESULT is 1 for success (check: enough stored; add: stored), else 0.
    local item = tostring(var_get(store, ctx, row[1]))
    local qty = math.max(1, tonumber(var_get(store, ctx, row[2])) or 1)
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local Storage = require("src.core.game3.storage")
    local storage = session and Storage.ensure(session) or nil
    local ok = false
    if storage then
      storage.items = storage.items or {}
      local slot
      for _, entry in ipairs(storage.items) do
        if tostring(entry.id) == item then slot = entry break end
      end
      if op == "checkpcitem" then
        local have = slot and (tonumber(slot.qty) or 0) or 0
        ok = have >= qty
      elseif slot then
        local room = Storage.MAX_ITEM_QTY - (tonumber(slot.qty) or 0)
        if room >= qty then
          slot.qty = (tonumber(slot.qty) or 0) + qty
          ok = true
        end
      elseif #storage.items < Storage.PC_ITEMS_COUNT then
        storage.items[#storage.items + 1] = { id = item, qty = math.min(qty, Storage.MAX_ITEM_QTY) }
        ok = true
      end
    end
    if op == "addpcitem" and not ok then
      a.log("[game3] addpcitem had no PC room for " .. item)
    end
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, ok and 1 or 0)
    return false
  elseif op == "bufferspeciesname" or op == "bufferitemname"
      or op == "buffermovename" or op == "bufferdecorationname"
      or op == "bufferstdstring" or op == "bufferpartymonnick" then
    local dest = (row.dest or row[1] or 0) + 1 -- buffer index 0→STR_VAR_1
    local src = row.src or row[2] or 0
    if type(src) == "number" and src >= 0x4000 then
      src = Flags.getVar(store, ctx, src)
    end
    local name = tostring(src)
    if a.bufferName then name = a.bufferName(op, src) or name end
    if op == "buffermovename" and name == tostring(src) then
      -- pokefirered/src/scrcmd.c:1669
      local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
      if okP and Pokemon and Pokemon.moveName then
        local okN, moveName = pcall(Pokemon.moveName, tonumber(src) or src)
        if okN and type(moveName) == "string" and #moveName > 0 then name = moveName end
      end
    end
    ctx.stringVars[dest] = name
    return false
  elseif op == "bufferleadmonspeciesname" then
    local dest = (row.dest or row[1] or 0) + 1
    ctx.stringVars[dest] = (a.leadMonName and a.leadMonName()) or "POKéMON"
    return false
  elseif op == "buffernumberstring" then
    local dest = (row.dest or row[1] or 0) + 1
    local v = Flags.getVar(store, ctx, row.src or row[2])
    ctx.stringVars[dest] = tostring(v)
    return false
  elseif op == "bufferstring" then
    local dest = (row.dest or row[1] or 0) + 1
    local ir = resolve_text(vm, row.src or row[2])
    ctx.stringVars[dest] = ir and TextIR.toPlain(ir, {
      stringVars = ctx.stringVars,
      playerName = a.playerName
        and (type(a.playerName) == "function" and a.playerName() or a.playerName)
        or ctx.playerName,
      rivalName = a.rivalName
        and (type(a.rivalName) == "function" and a.rivalName() or a.rivalName)
        or ctx.rivalName,
    }) or ""
    return false
  elseif op == "delay" then
    local frames = tonumber(row[1] or row.frames) or 0
    if frames <= 0 then return false end
    -- Soft per-frame wait only. Never call a.delay that completes+tick_vm
    -- synchronously — that re-enters resume and clears waitmovement polls.
    ctx.delayLeft = frames
    ctx.mode = "native"
    ctx.status = "waiting"
    ctx.nativePoll = function()
      ctx.delayLeft = (ctx.delayLeft or 1) - 1
      if ctx.delayLeft <= 0 then
        ctx.delayLeft = nil
        return true
      end
      return false
    end
    return true
  elseif op == "turnobject" then
    local lid = var_get(store, ctx, row.localId or row[1])
    local dir = row[2] or row.direction or 0
    if a.turnObject then a.turnObject(lid, dir) end
    return false
  elseif op == "hideobjectat" or op == "showobjectat" then
    local lid = var_get(store, ctx, row.localId or row[1])
    if not objectat_same_map(store, ctx, row, 2) then
      if a.log then
        a.log("[game3] " .. op .. " targets another map — skipped")
      end
    elseif op == "hideobjectat" and a.hideObject then
      a.hideObject(lid)
    elseif op == "showobjectat" and a.showObject then
      a.showObject(lid)
    elseif op == "hideobjectat" and a.removeObject then
      a.removeObject(lid)
    end
    return false
  elseif op == "applymovementat" or op == "waitmovementat"
      or op == "removeobjectat" or op == "addobjectat" then
    -- pret ScrCmd_applymovementat / waitmovementat / removeobjectat /
    -- addobjectat (src/scrcmd.c:993, :1022, :1046, :1064).  On the current map
    -- they behave exactly like the plain command, so re-dispatch to it.
    local groupIdx = (op == "applymovementat") and 3 or 2
    if not objectat_same_map(store, ctx, row, groupIdx) then
      if a.log then
        a.log("[game3] " .. op .. " targets another map — skipped")
      end
      return false
    end
    local plain = ({
      applymovementat = "applymovement",
      waitmovementat = "waitmovement",
      removeobjectat = "removeobject",
      addobjectat = "addobject",
    })[op]
    return dispatch(vm, { op = plain, row[1], row[2] })
  elseif op == "addobject" then
    local lid = var_get(store, ctx, row.localId or row[1])
    if a.addObject then a.addObject(lid) end
    return false
  elseif op == "opendoor" or op == "closedoor" then
    -- Cosmetic on host; waitdooranim yields briefly.
    if a.doorAnim then a.doorAnim(op, row[1], row[2]) end
    return false
  elseif op == "setdooropen" or op == "setdoorclosed" then
    -- pret ScrCmd_setdooropen/setdoorclosed record a door's state (used to
    -- restore doors on re-entry).  The host exposes only the door animation
    -- seam, so map the stored state onto the matching action.
    if a.doorAnim then
      -- pret ScrCmd_setdooropen/setdoorclosed read their x/y through VarGet
      -- (src/scrcmd.c:2156).
      a.doorAnim(op == "setdooropen" and "opendoor" or "closedoor",
        var_get(store, ctx, row[1]), var_get(store, ctx, row[2]))
    end
    return false
  elseif op == "waitdooranim" then
    -- Short soft wait (no re-entrant tick_vm). Instant adapter done() was
    -- skipping applymovement that follows (lab door enter).
    local frames = 8
    ctx.delayLeft = frames
    ctx.mode = "native"
    ctx.status = "waiting"
    ctx.nativePoll = function()
      ctx.delayLeft = (ctx.delayLeft or 1) - 1
      if ctx.delayLeft <= 0 then
        ctx.delayLeft = nil
        return true
      end
      return false
    end
    return true
  elseif op == "fadescreen" or op == "fadescreenspeed" then
    local mode = row[1] or 0
    local speed = row[2]
    if a.fadeScreen then
      ctx.mode = "native"
      ctx.status = "waiting"
      local done = false
      ctx.nativePoll = function() return done end
      a.fadeScreen(mode, speed, function() done = true end)
      if done then
        ctx.mode = "bytecode"
        ctx.status = "running"
        ctx.nativePoll = nil
        return false
      end
      return true
    end
    return false
  elseif op == "setflashlevel" then
    -- pokefirered/src/scrcmd.c:612
    local okV, FieldView = pcall(require, "src.core.game3.field_view")
    if okV and type(FieldView) == "table" and type(FieldView.setFlashLevel) == "function" then
      pcall(FieldView.setFlashLevel, var_get(store, ctx, row[1]))
    end
    return false
  elseif op == "animateflash" then
    -- pokefirered/src/scrcmd.c:605
    local okV, FieldView = pcall(require, "src.core.game3.field_view")
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if not (okV and type(FieldView) == "table" and type(FieldView.getFlashLevel) == "function"
        and okFx and type(FieldEffects) == "table"
        and type(FieldEffects.animateFlashLevel) == "function") then
      return false
    end
    -- pokefirered/src/field_screen_effect.c:194
    local okAnim, anim = pcall(FieldEffects.animateFlashLevel,
      FieldView.getFlashLevel(), tonumber(row[1]) or 0)
    if not (okAnim and type(anim) == "table") then return false end
    local flashDone = false
    anim.onDone = function() flashDone = true end
    ctx.mode = "native"
    ctx.status = "waiting"
    ctx.nativePoll = function() return flashDone end
    return true
  elseif op == "warp" or op == "warpsilent" or op == "warpdoor"
      or op == "warpteleport" or op == "warpspinenter" then
    local group, num = row[1], row[2]
    local warpId = row[3]
    -- pokefirered/src/scrcmd.c:719-731
    local x = var_get(store, ctx, row[4])
    local y = var_get(store, ctx, row[5])
    if a.warp then
      -- waitstate typically follows; mark pending and let waitstate poll.
      ctx.warpPending = true
      a.warp(group, num, warpId, x, y, function()
        ctx.warpPending = false
      end)
    end
    return false
  elseif op == "warphole" then
    -- pokefirered/src/scrcmd.c:761
    local Player = package.loaded["src.core.game3.player"]
      or require("src.core.game3.player")
    local destX, destY = tonumber(Player.cellX) or 0, tonumber(Player.cellY) or 0
    local destMap = warp_hole_dest(row[1], row[2])
    if not destMap then
      a.log(string.format("[game3] warphole unknown FRLG map %s.%s",
        tostring(row[1]), tostring(row[2])))
      return false
    end
    local Warp = require("src.core.game3.warp")
    local Runtime = package.loaded["src.core.game3.runtime"]
    local started = Warp.startFall(Runtime and Runtime._mod, Runtime and Runtime._game,
      destMap, destX, destY)
    if not started then return false end
    ctx.warpPending = true
    local Task = require("src.core.game3.task")
    Task.spawn(function()
      if Warp.isBusy and Warp.isBusy() then return false end
      ctx.warpPending = false
      return true
    end)
    return false
  elseif op == "setwarp" or op == "setdynamicwarp" or op == "setescapewarp"
      or op == "setdivewarp" or op == "setholewarp" then
    -- pokefirered/src/scrcmd.c:819
    if a.setWarp then
      a.setWarp(op, row[1], row[2], row[3],
        var_get(store, ctx, row[4]), var_get(store, ctx, row[5]))
    end
    return false
  elseif op == "playse" or op == "playfanfare" or op == "waitfanfare" then
    local Audio = require("src.core.game3.audio")
    if op == "waitfanfare" then
      local isFinished = function()
        if a.isFanfareFinished then return a.isFanfareFinished() end
        if Audio.isFanfareFinished then return Audio.isFanfareFinished() end
        return true
      end
      if isFinished() then
        return false
      end
      ctx.mode = "native"
      ctx.status = "waiting"
      local done = false
      ctx.nativePoll = function() return done or isFinished() end
      local finish = function() done = true end
      if a.waitFanfare then
        a.waitFanfare(finish)
      else
        Audio.waitFanfare(finish)
      end
      return true
    else
      if op == "playfanfare" then
        local songId = row[1] or row.song or row.id or 0
        songId = var_get(store, ctx, songId)
        if a.playSe then a.playSe(songId, true) else Audio.playFanfare(songId) end
      else
        local seId = row[1] or row.id or 0
        seId = var_get(store, ctx, seId)
        if a.playSe then a.playSe(seId, false) else Audio.playSe(seId) end
      end
    end
    return false
  elseif op == "playbgm" or op == "playsong" or op == "fadenewbgm" then
    local Audio = require("src.core.game3.audio")
    -- pokefirered/src/scrcmd.c:927
    if op == "playbgm" and (row[2] == 1 or row[2] == true) then
      Audio.setSavedSong(row[1])
    end
    if a.playBgm then
      a.playBgm(row[1] or 0)
    else
      Audio.playSong(row[1] or 0)
    end
    return false
  elseif op == "fadedefaultbgm" or op == "fadeoutbgm" or op == "fadeinbgm" or op == "savebgm" then
    local Audio = require("src.core.game3.audio")
    if a.fadeBgm then
      a.fadeBgm(op, row[1], row[2])
    elseif op == "savebgm" then
      -- pokefirered/src/scrcmd.c:935
      Audio.setSavedSong(row[1])
    elseif op == "fadeoutbgm" then
      Audio.fadeOutBgm(row[1] or 4)
    elseif op == "fadeinbgm" then
      Audio.fadeInBgm(row[1] or Audio._mapSong, row[2] or 4)
    else
      Audio.fadeDefaultBgm(row[1] or 4)
    end
    return false
  elseif op == "waitse" then
    local Audio = require("src.core.game3.audio")
    ctx.mode = "native"
    ctx.status = "waiting"
    local done = false
    ctx.nativePoll = function() return done end
    Audio.waitSe(row[1], function() done = true end)
    if done or not Audio.isSePlaying(row[1]) then
      done = true
      ctx.mode = "bytecode"
      ctx.status = "running"
      ctx.nativePoll = nil
      return false
    end
    return true
  elseif op == "playmoncry" then
    -- pokefirered/src/scrcmd.c:2088
    local Audio = require("src.core.game3.audio")
    Audio.playCry(var_get(store, ctx, row[1]), var_get(store, ctx, row[2]))
    return false
  elseif op == "waitmoncry" then
    -- pokefirered/src/scrcmd.c:2097
    local Audio = require("src.core.game3.audio")
    local isFinished = function()
      if Audio.isCryFinished then return Audio.isCryFinished() == true end
      return true
    end
    if isFinished() then return false end
    ctx.mode = "native"
    ctx.status = "waiting"
    local lastClock = Audio._cryClock
    ctx.nativePoll = function()
      if isFinished() then return true end
      -- pokefirered/src/sound.c:502
      if Audio._cryClock == lastClock and Audio.tickCry then Audio.tickCry(1 / 60) end
      lastClock = Audio._cryClock
      return isFinished()
    end
    return true
  elseif op == "braillemessage" then
    -- pokefirered/src/scrcmd.c:1558
    local ptr = row.ptr or row[1]
    local ir = resolve_text(vm, ptr)
    if not ir then return show_message(vm, ptr, true) end
    local body = TextIR.toPlain(ir, text_ctx_view(vm)) or ""
    local okB, Braille = pcall(require, "src.ui.game3.braille")
    if okB and type(Braille) == "table" and type(Braille.show) == "function" then
      local okShow = pcall(Braille.show, body, { width = braille_width(ir) })
      if okShow then
        ctx.messageOpen = true
        return false
      end
    end
    return show_message(vm, ptr, true)
  elseif op == "getbraillestringwidth" then
    -- pokefirered/src/scrcmd.c:1570
    local ir = resolve_text(vm, row.ptr or row[1])
    local width
    local okB, Braille = pcall(require, "src.ui.game3.braille")
    if okB and type(Braille) == "table" and type(Braille.width) == "function" then
      local okW, v = pcall(Braille.width, TextIR.toPlain(ir or {}, text_ctx_view(vm)) or "")
      if okW then width = tonumber(v) end
    end
    Flags.setVar(store, ctx, 0x8004, width or braille_width(ir))
    return false
  elseif op == "messageautoscroll" then
    return show_message(vm, row.ptr or row[1], false)
  elseif op == "setmetatile" or op == "dofieldeffect" or op == "waitfieldeffect"
      or op == "setfieldeffectargument" then
    -- Field pack: no-op / instant unless host implements.
    if op == "waitfieldeffect" and a.waitFieldEffect then
      ctx.mode = "native"
      ctx.status = "waiting"
      local done = false
      ctx.nativePoll = function() return done end
      a.waitFieldEffect(row[1], function() done = true end)
      if done then
        ctx.mode = "bytecode"
        ctx.status = "running"
        ctx.nativePoll = nil
        return false
      end
      return true
    end
    if op == "setmetatile" and a.setMetatile then
      -- pokefirered/src/scrcmd.c:2103-2108
      a.setMetatile(var_get(store, ctx, row[1]), var_get(store, ctx, row[2]),
        var_get(store, ctx, row[3]), var_get(store, ctx, row[4]) ~= 0)
    elseif op == "dofieldeffect" and a.doFieldEffect then
      -- pokefirered/src/scrcmd.c:2042-2049
      a.doFieldEffect(var_get(store, ctx, row[1]))
    elseif op == "setfieldeffectargument" then
      -- pokefirered/src/scrcmd.c:2051 — the value operand is VarGet'd, which
      -- passes raw constants (< 0x4000) straight through.
      local argNum = tonumber(row[1]) or 0
      local value = var_get(store, ctx, row[2])
      if a.setFieldEffectArgument then
        a.setFieldEffectArgument(argNum, value)
      end
    end
    return false
  elseif op == "setstepcallback" then
    -- pokefirered/src/scrcmd.c:705
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    Ctx.setStepCallback(row[1] or 0, session and session.map)
    return false
  elseif op == "setmaplayoutindex" then
    -- pokefirered/src/scrcmd.c:711
    set_map_layout(var_get(store, ctx, row[1]), a.log)
    return false
  elseif op == "setweather" then
    -- pokefirered/src/scrcmd.c:685-691
    if a.setWeather then a.setWeather(var_get(store, ctx, row[1] or row.weather or 0)) end
    return false
  elseif op == "doweather" then
    if a.doWeather then a.doWeather() end
    return false
  elseif op == "resetweather" then
    if a.resetWeather then a.resetWeather() end
    return false
  elseif op == "setwildbattle" then
    local Enc = require("src.core.game3.encounters")
    Enc.setWildBattle(row[1] or row.species, row[2] or row.level, row[3] or row.item)
    return false
  elseif op == "dowildbattle" then
    local Enc = require("src.core.game3.encounters")
    local foe = Enc.takePendingWild()
    if a.startWildBattle and foe then
      foe.wildScripted = true
      ctx.mode = "native"
      ctx.status = "waiting"
      local done = false
      ctx.nativePoll = function() return done end
      a.startWildBattle(foe, function(result)
        local Natives = require("src.core.game3.scripting.natives")
        local code = Natives.outcome_to_code and Natives.outcome_to_code(result) or 1
        if ctx then ctx.lastBattleOutcome = code end
        Flags.setVar(store, ctx, 0x800D, code)
        done = true
      end, { wildScripted = true })
      if done then
        ctx.mode = "bytecode"
        ctx.status = "running"
        ctx.nativePoll = nil
        return false
      end
      return true
    end
    return false
  elseif op == "checktrainerflag" then
    local tid = var_get(store, ctx, row[1] or row.trainer)
    ctx.comparisonResult = Flags.getFlag(store, ctx, Flags.trainerFlagId(tid)) and 1 or 0
    return false
  elseif op == "settrainerflag" then
    local tid = var_get(store, ctx, row[1] or row.trainer)
    local fid = Flags.trainerFlagId(tid)
    Flags.setFlag(store, ctx, fid, true)
    if a.onFlagChanged then a.onFlagChanged(fid, true) end
    return false
  elseif op == "cleartrainerflag" then
    local tid = var_get(store, ctx, row[1] or row.trainer)
    local fid = Flags.trainerFlagId(tid)
    Flags.setFlag(store, ctx, fid, false)
    if a.onFlagChanged then a.onFlagChanged(fid, false) end
    return false
  elseif op == "gotopostbattlescript" then
    -- pret: resume after the trainerbattle that configured this fight.
    if ctx.trainerBattleEndScript then
      jump(vm, ctx.trainerBattleEndScript)
    end
    return false
  elseif op == "gotobeatenscript" then
    -- pret: CONTINUE_SCRIPT event pointer (e.g. DefeatedBrock → shoes aide).
    if ctx.trainerBattleBeatenScript then
      jump(vm, ctx.trainerBattleBeatenScript)
    end
    return false
  elseif op == "trainerbattle" or op == "dotrainerbattle" then
    -- pret ScrCmd_trainerbattle configures then jumps into trainer_battle.inc.
    -- We inline that: skip if already fought; else battle; on win set trainer
    -- flag and goto eventScript when present (CONTINUE_SCRIPT*).
    local Trainers = require("src.core.game3.scripting.trainers")
    local trainerId = tonumber(row.trainer or row[1]) or 0
    local battleType = tonumber(row.type) or 0
    local rivalFlags = tonumber(row.flags or row.localId) or 0
    local earlyRival = (battleType == 9) -- TRAINER_BATTLE_EARLY_RIVAL
    -- pokefirered/src/battle_setup.c:899
    local tutorialBattle = earlyRival and (rivalFlags % 4) ~= 0
    local eventScript = row.eventScript
    local trainerFlag = Flags.trainerFlagId(trainerId)
    local VsSeeker = require("src.core.game3.vs_seeker")
    local isRematch = op == "trainerbattle" and (battleType == 5 or battleType == 7)
    local trainerLocalId = tonumber(row.localId) or 0
    if op == "trainerbattle" and battleType ~= 3 and not earlyRival and trainerLocalId ~= 0 then
      -- src/battle_setup.c:778
      Flags.setVar(store, ctx, Ctx.VAR_LAST_TALKED, trainerLocalId)
      Ctx.selectObject(ctx, trainerLocalId)
    end
    local lastTalked = Flags.getVar(store, ctx, Ctx.VAR_LAST_TALKED)
    local opponentA = trainerId
    if op == "trainerbattle" then
      if isRematch then
        -- pokefirered/src/battle_setup.c:814
        opponentA = VsSeeker.rematchTrainerId(trainerId, store)
      end
      ctx.trainerBattleMode = battleType
      ctx.trainerBattleOpponentA = opponentA
    end

    -- Remember post-battle / beaten scripts for gotopost/gotobeaten.
    -- VM already advanced PC past this op → current PC is post-battle addr.
    ctx.trainerBattleEndScript = {
      listKey = ctx.pc.listKey,
      index = ctx.pc.index,
    }
    ctx.trainerBattleBeatenScript = eventScript

    if op == "trainerbattle" and not earlyRival and not isRematch and Flags.getFlag(store, ctx, trainerFlag) then
      -- Already defeated → fall through (gotopostbattlescript).
      return false
    end
    -- pokefirered/data/scripts/trainer_battle.inc:52
    if op == "trainerbattle" and isRematch and not VsSeeker.isTrainerReadyForRematch(opponentA, lastTalked) then
      return false
    end

    local isDouble = battleType == 4 or battleType == 6 or battleType == 7 or battleType == 8
    if op == "trainerbattle" and isDouble and a.startTrainerBattle then
      local Party = require("src.core.game3.party")
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      -- pokefirered/data/scripts/trainer_battle.inc:30
      if Party.monsStateToDoubles(session and session.party) ~= Party.PLAYER_HAS_TWO_USABLE_MONS then
        local dialogs = Trainers.dialogs(trainerId) or {}
        local cantText = (row.notEnoughText and resolve_text(vm, row.notEnoughText)) or dialogs.notEnough
        if cantText and cantText ~= "" and a.openMessageAsync then
          ctx.mode = "native"
          ctx.status = "waiting"
          local shown = false
          ctx.nativePoll = function()
            if not shown then return false end
            ctx.status = "halted"
            return false
          end
          a.openMessageAsync(cantText, function() shown = true end)
          if shown then
            ctx.mode = "bytecode"
            ctx.status = "halted"
            ctx.nativePoll = nil
          end
          return true
        end
        ctx.status = "halted"
        return true
      end
    end

    if a.startTrainerBattle then
      local foe = Trainers.foeFromId(opponentA)
      if not foe then
        local sp = tonumber(row.species)
        if not sp or sp < 1 then sp = nil end
        foe = {
          species = sp or 4,
          level = tonumber(row.level) or 5,
          trainerId = opponentA,
        }
      end
      foe.moves = foe.moves or row.moves

      local dialogs = Trainers.dialogs(opponentA) or Trainers.dialogs(trainerId) or {}
      local introText = nil
      if battleType ~= 3 and battleType ~= 9 then
        introText = (row.introText and resolve_text(vm, row.introText)) or dialogs.intro
      end
      local defeatText = (row.defeatText and resolve_text(vm, row.defeatText)) or dialogs.defeat
      local victoryText = (row.victoryText and resolve_text(vm, row.victoryText)) or dialogs.victory

      ctx.mode = "native"
      ctx.status = "waiting"
      local done = false
      local pendingGoto = nil
      local shouldHalt = false

      ctx.nativePoll = function()
        if not done then return false end
        if shouldHalt then
          ctx.status = "halted"
          return false
        end
        if pendingGoto then
          jump(vm, pendingGoto)
          pendingGoto = nil
        end
        return true
      end

      local function beginBattle()
        a.startTrainerBattle(foe, function(result)
          local lost = (result == "lose" or result == "whiteout" or result == "blackout")
          -- pret: gSpecialVar_Result = TRUE if player defeated (early rival).
          if earlyRival then
            Flags.setVar(store, ctx, Ctx.VAR_RESULT, lost and 1 or 0)
          end
          -- pokefirered/src/battle_main.c:3848
          VsSeeker.clearRematchStateByTrainerId(opponentA, lastTalked, store)
          if isRematch then
            if not lost then
              -- pokefirered/src/battle_setup.c:967
              local rematchFlag = Flags.trainerFlagId(opponentA)
              Flags.setFlag(store, ctx, rematchFlag, true)
              if a.onFlagChanged then a.onFlagChanged(rematchFlag, true) end
              VsSeeker.clearRematchStateOfLastTalked(lastTalked, opponentA, store)
            end
            shouldHalt = true
          elseif not lost then
            Flags.setFlag(store, ctx, trainerFlag, true)
            if a.onFlagChanged then a.onFlagChanged(trainerFlag, true) end
            -- CONTINUE_SCRIPT*: gotobeatenscript after battle.
            if eventScript and (battleType == 1 or battleType == 2
                or battleType == 6 or battleType == 8) then
              pendingGoto = eventScript
            elseif battleType == 0 or battleType == 4 then
              -- Single standard trainer: script ends after encounter
              shouldHalt = true
            end
          end
          done = true
        end, {
          trainerId = opponentA,
          earlyRival = earlyRival,
          rivalFlags = rivalFlags,
          firstBattle = tutorialBattle,
          noWhiteout = earlyRival and (rivalFlags % 2 == 1),
          defeatText = defeatText,
          victoryText = victoryText,
          double = (foe.doubleBattle == true) or nil,
        })
      end

      if isRematch then
        -- pokefirered/src/battle_setup.c:848
        local Objects = package.loaded["src.core.game3.objects"]
        local eo = Objects and Objects.find and Objects.find(lastTalked)
        if eo and Objects.setTrainerMovementType and not (Objects.isPlayer and Objects.isPlayer(lastTalked)) then
          Objects.setTrainerMovementType(eo, VsSeeker.faceTypeFor(eo.facing))
        end
      end

      if introText and introText ~= "" and a.openMessageAsync then
        -- Play trainer encounter music if not already playing (pret PlayTrainerEncounterMusic / EventScript_TryDoNormalTrainerBattle)
        local song = Trainers.getEncounterMusic and Trainers.getEncounterMusic(opponentA)
        local okA, Audio = pcall(require, "src.core.game3.audio")
        if okA and Audio and Audio.playSong and song then
          Audio.playSong(song)
        end
        a.openMessageAsync(introText, function()
          beginBattle()
        end)
      else
        beginBattle()
      end

      if done then
        ctx.mode = "bytecode"
        ctx.status = shouldHalt and "halted" or "running"
        ctx.nativePoll = nil
        if pendingGoto then
          jump(vm, pendingGoto)
        end
        return shouldHalt
      end
      return true
    end
    return false
  elseif op == "additem" or op == "removeitem" then
    local item = row[1] or row.item
    local qty = row[2] or row.quantity or 1
    item = tonumber(item) or item
    qty = tonumber(qty) or 1
    -- FRLG often passes VAR_0x8000 / VAR_0x8001 (setorcopyvar before callstd).
    if type(item) == "number" and item >= 0x4000 then
      item = Flags.getVar(store, ctx, item)
    end
    if type(qty) == "number" and qty >= 0x4000 then
      qty = Flags.getVar(store, ctx, qty)
    end
    local ok = true
    if a.modifyItem then
      ok = a.modifyItem(op, item, qty)
    end
    -- VAR_RESULT: 1 = success (bag accepted), 0 = full / failed.
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, ok and 1 or 0)
    return false
  elseif op == "checkitem" then
    -- pret ScrCmd_checkitem → CheckBagHasItem → VAR_RESULT
    local item = row[1] or row.item
    local qty = row[2] or row.quantity or 1
    item = tonumber(item) or item
    qty = tonumber(qty) or 1
    if type(item) == "number" and item >= 0x4000 then
      item = Flags.getVar(store, ctx, item)
    end
    if type(qty) == "number" and qty >= 0x4000 then
      qty = Flags.getVar(store, ctx, qty)
    end
    local ok = false
    if a.checkItem then
      ok = a.checkItem(item, qty) and true or false
    else
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      if session and session.bag then
        local Bag = require("src.core.game3.bag")
        ok = Bag.has(session.bag, item, qty)
      end
    end
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, ok and 1 or 0)
    return false
  elseif op == "checkitemtype" then
    -- pret ScrCmd_checkitemtype → GetPocketByItemId (1..5) → VAR_RESULT
    local item = row[1] or row.item
    item = tonumber(item) or item
    if type(item) == "number" and item >= 0x4000 then
      item = Flags.getVar(store, ctx, item)
    end
    local pocket = 0
    if a.checkItemType then
      pocket = tonumber(a.checkItemType(item)) or 0
    else
      local ItemsData = require("src.core.game3.items_data")
      pocket = ItemsData.pocketResult(item) or 0
    end
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, pocket)
    return false
  elseif op == "checkitemspace" then
    local item = row[1] or row.item
    local qty = row[2] or row.quantity or 1
    item = tonumber(item) or item
    qty = tonumber(qty) or 1
    if type(item) == "number" and item >= 0x4000 then
      item = Flags.getVar(store, ctx, item)
    end
    if type(qty) == "number" and qty >= 0x4000 then
      qty = Flags.getVar(store, ctx, qty)
    end
    local ok = true
    if a.checkItemSpace then
      ok = a.checkItemSpace(item, qty) and true or false
    else
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      if session and session.bag then
        local Bag = require("src.core.game3.bag")
        ok = Bag.canAdd(session.bag, item, qty) and true or false
      end
    end
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, ok and 1 or 0)
    return false
  elseif op == "addmoney" or op == "removemoney" or op == "checkmoney" then
    -- pokefirered/src/scrcmd.c:1798-1830, asm/macros/event.inc:1166-1186
    local amount = math.max(0, math.floor(tonumber(row[1] or row.amount) or 0))
    local disable = tonumber(row[2] or row.disable) or 0
    if disable == 0 then
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      local money = tonumber(session and session.money) or 0
      if op == "checkmoney" then
        Flags.setVar(store, ctx, Ctx.VAR_RESULT, money >= amount and 1 or 0)
      elseif session then
        local Prize = require("src.core.game3.battle.prize")
        if op == "addmoney" then
          Prize.apply(session, amount)
        else
          session.money = math.max(0, money - amount)
        end
      end
    end
    return false
  elseif op == "showmoneybox" then
    local x = tonumber(row[1] or row.x) or 19
    local y = tonumber(row[2] or row.y) or 1
    local ignore = tonumber(row[3] or row.ignore) or 0
    -- pokefirered/src/scrcmd.c:1834
    if ignore == 0 and not ql_avoid_display() then
      local MoneyBox = require("src.ui.game3.money_box")
      MoneyBox.show(x, y)
    end
    return false
  elseif op == "hidemoneybox" then
    local MoneyBox = require("src.ui.game3.money_box")
    MoneyBox.hide()
    return false
  elseif op == "updatemoneybox" then
    -- pokefirered/src/scrcmd.c:1848-1856, event.inc:1204-1211
    local disable = tonumber(row[3]) or 0
    if disable == 0 then
      local MoneyBox = require("src.ui.game3.money_box")
      MoneyBox.update()
    end
    return false
  elseif op == "checkcoins" then
    -- pokefirered/src/scrcmd.c:2197
    Flags.setVar(store, ctx, row[1] or row.dest, coins_get())
    return false
  elseif op == "addcoins" or op == "removecoins" then
    -- pokefirered/src/scrcmd.c:2204
    local amount = var_get(store, ctx, row[1] or row.amount)
    local moved = coins_move(op == "addcoins", amount)
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, moved and 0 or 1)
    return false
  elseif op == "showcoinsbox" then
    -- pokefirered/src/scrcmd.c:1864
    if not ql_avoid_display() then
      coins_box("show", tonumber(row[1] or row.x) or 0, tonumber(row[2] or row.y) or 0, coins_get())
    end
    return false
  elseif op == "hidecoinsbox" then
    -- pokefirered/src/scrcmd.c:1869
    coins_box("hide")
    return false
  elseif op == "updatecoinsbox" then
    -- pokefirered/src/scrcmd.c:1878
    coins_box("update", coins_get())
    return false
  elseif op == "pokemart" then
    local ptr = row[1] or row.ptr or row.items
    if a.openShop then
      ctx.mode = "native"
      ctx.status = "waiting"
      local done = false
      ctx.nativePoll = function() return done end
      a.openShop(ptr, function()
        done = true
      end)
      if done then
        ctx.mode = "bytecode"
        ctx.status = "running"
        ctx.nativePoll = nil
        return false
      end
      return true
    end
    if a.log then a.log("[game3] pokemart skipped (no openShop)") end
    return false
  elseif op == "pokemartdecoration" or op == "pokemartdecoration2" then
    -- Decor shops are a separate item namespace; skip until decor pack exists.
    if a.log then a.log("[game3] skip " .. tostring(op)) end
    return false
  elseif op == "playslotmachine" then
    -- pokefirered/src/scrcmd.c:1980
    local machineIdx = var_get(store, ctx, row[1] or row.id)
    local okUi, SlotUi = pcall(require, "src.ui.game3.slot_machine")
    if not (okUi and type(SlotUi) == "table" and type(SlotUi.show) == "function") then
      if a.log then a.log("[game3] playslotmachine skipped (no screen)") end
      return false
    end
    if a.closeMessage then a.closeMessage() end
    local okMsg, Message = pcall(require, "src.ui.game3.message")
    if okMsg and Message and Message.close then Message.close() end
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local done = false
    local function poll()
      if done and ctx.stateWait == poll then ctx.stateWait = nil end
      return done
    end
    ctx.mode = "native"
    ctx.status = "waiting"
    ctx.nativePoll = poll
    Natives.awaitState(ctx, poll)
    SlotUi.show({
      machineIdx = machineIdx,
      session = session,
      onClose = function() done = true end,
    })
    if done then
      ctx.mode = "bytecode"
      ctx.status = "running"
      ctx.nativePoll = nil
      ctx.stateWait = nil
      return false
    end
    return true
  elseif op == "setobjectxyperm" or op == "setobjectxy" or op == "setobjectmovementtype"
      or op == "copyobjectxytoperm" then
    if a.setObjectState then a.setObjectState(op, row) end
    return false
  elseif op == "multichoice" or op == "multichoicedefault" or op == "multichoicegrid" then
    -- Economy/UI pack: pick option 0 into VAR_RESULT unless host implements.
    Flags.setVar(store, ctx, 0x800D, 0)
    if op == "multichoice" then
      local listId = tonumber(row.listId or row[3]) or -1
      local okP, Prize = pcall(require, "src.ui.game3.prize_corner")
      if okP and type(Prize) == "table" and Prize.isPrizeList(listId) then
        local Multi = require("src.core.game3.scripting.multichoice")
        local labels = Multi.resolve(listId)
        local done = false
        local function poll()
          if done and ctx.stateWait == poll then ctx.stateWait = nil end
          return done
        end
        ctx.mode = "native"
        ctx.status = "waiting"
        ctx.nativePoll = poll
        Natives.awaitState(ctx, poll)
        -- pokefirered/src/script_menu.c:713
        local shown = Prize.show({
          listId = listId,
          labels = labels,
          left = tonumber(row.x or row.left or row[1]) or 0,
          top = tonumber(row.y or row.top or row[2]) or 0,
          ignoreBPress = (tonumber(row[4] or row.ignoreBPress) or 0) ~= 0,
          onChoose = function(sel)
            Flags.setVar(store, ctx, 0x800D, tonumber(sel) or 0)
            done = true
          end,
        })
        if not shown then
          done = true
        end
        if done then
          ctx.mode = "bytecode"
          ctx.status = "running"
          ctx.nativePoll = nil
          ctx.stateWait = nil
        else
          return true
        end
      end
    end
    if a.multichoice then
      ctx.mode = "native"
      ctx.status = "waiting"
      local done = false
      ctx.nativePoll = function() return done end
      a.multichoice(row, function(sel)
        Flags.setVar(store, ctx, 0x800D, tonumber(sel) or 0)
        done = true
      end)
      if done then
        ctx.mode = "bytecode"
        ctx.status = "running"
        ctx.nativePoll = nil
        return false
      end
      return true
    end
    return false
  elseif op == "random" then
    -- pokefirered/src/scrcmd.c:455-461
    local maxv = var_get(store, ctx, row[1])
    maxv = tonumber(maxv) or 1
    if maxv < 1 then maxv = 1 end
    Flags.setVar(store, ctx, 0x800D, math.random(0, maxv - 1))
    return false
  elseif op == "getplayerxy" then
    -- pokefirered/src/scrcmd.c:867
    local Player = package.loaded["src.core.game3.player"]
      or require("src.core.game3.player")
    Flags.setVar(store, ctx, row[1], tonumber(Player.cellX) or 0)
    Flags.setVar(store, ctx, row[2], tonumber(Player.cellY) or 0)
    return false
  elseif op == "getpartysize" then
    -- pokefirered/src/scrcmd.c:877
    local Party = require("src.core.game3.party")
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, Party.size(session and session.party))
    return false
  elseif op == "checkplayergender" then
    -- pokefirered/src/scrcmd.c:2082
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, tonumber(session and session.gender) or 0)
    return false
  elseif op == "bufferboxname" then
    -- pokefirered/src/pokemon_storage_system.c:118
    local dest = (tonumber(row.dest or row[1]) or 0) + 1
    local boxId = var_get(store, ctx, row.src or row[2])
    local Storage = require("src.core.game3.storage")
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local storage = session and Storage.ensure(session)
    local box = storage and Storage.getBox(storage, boxId + 1)
    ctx.stringVars[dest] = (box and box.name) or ""
    return false
  elseif op == "setrespawn" then
    -- pret ScrCmd_setrespawn → SetLastHealLocationWarp(healLocationId)
    local id = var_get(store, ctx, row[1])
    local Field = package.loaded["src.core.game3.field"]
      or require("src.core.game3.field")
    if Field.setRespawn then
      Field.setRespawn(id)
    end
    return false
  elseif op == "trywondercardscript" then
    -- pokefirered/src/scrcmd.c:275 ScrCmd_trywondercardscript
    local Gift = require("src.core.game3.scripting.natives_gift")
    local yield, jumped = Gift.runWonderCardScript(ctx, a)
    if jumped then ctx.pc = nil end
    return yield
  elseif op == "setobjectsubpriority" then
    -- src/scrcmd.c:1122-1130
    local objLid = var_get(store, ctx, row[1])
    local Objects = package.loaded["src.core.game3.objects"]
      or require("src.core.game3.objects")
    Objects.setSubpriority(objLid, row[2], row[3], (tonumber(row[4]) or 0) + 83)
    return false
  elseif op == "resetobjectsubpriority" then
    -- src/scrcmd.c:1133-1140
    local objLid = var_get(store, ctx, row[1])
    local Objects = package.loaded["src.core.game3.objects"]
      or require("src.core.game3.objects")
    Objects.resetSubpriority(objLid, row[2], row[3])
    return false
  elseif op == "gettime" then
    -- pokefirered/src/scrcmd.c:673-681
    Flags.setVar(store, ctx, 0x8000, 0)
    Flags.setVar(store, ctx, 0x8001, 0)
    Flags.setVar(store, ctx, 0x8002, 0)
    return false
  elseif op == "setmysteryeventstatus" then
    -- src/scrcmd.c:269-273, src/mystery_event_script.c:92-95
    ctx.mysteryEventStatus = row[1]
    local okMG, MysteryGift = pcall(require, "src.core.game3.mystery_gift")
    if okMG and MysteryGift and MysteryGift.setStatus then MysteryGift.setStatus(row[1]) end
    return false
  elseif op == "gotonative" then
    -- src/scrcmd.c:92-97
    local gaddr = tonumber(row[1]) or 0
    local gfn = Natives.resolveNative and Natives.resolveNative(gaddr)
    if type(gfn) == "function" then
      return (gfn(ctx, a)) and true or false
    end
    Natives.log_once("gotonative", gaddr, a and a.log)
    return false
  elseif op == "createvobject" then
    -- src/scrcmd.c:1171-1181
    local VO = package.loaded["src.core.game3.virtual_objects"]
      or require("src.core.game3.virtual_objects")
    VO.spawn(row[2], row[1], var_get(store, ctx, row[3]), var_get(store, ctx, row[4]),
      row[5], row[6])
    return false
  elseif op == "turnvobject" then
    -- src/scrcmd.c:1184-1190
    local VO = package.loaded["src.core.game3.virtual_objects"]
      or require("src.core.game3.virtual_objects")
    VO.turn(row[1], row[2])
    return false
  elseif op == "loadhelp" then
    -- src/scrcmd.c:1274-1280, src/new_menu_helpers.c:701-705
    local HelpWindow = require("src.ui.game3.help_window")
    local ir = resolve_text(vm, row[1])
    if HelpWindow.show then
      HelpWindow.show(ir and TextIR.toPlain(ir, text_ctx_view(vm)) or "")
    end
    return false
  elseif op == "unloadhelp" then
    -- src/new_menu_helpers.c:707-710
    local HelpWindow = require("src.ui.game3.help_window")
    if HelpWindow.close then HelpWindow.close() end
    return false
  elseif op == "choosecontestmon" then
    -- pokefirered/src/scrcmd.c:2010-2016
    ctx.mode = "native"
    ctx.status = "waiting"
    ctx.nativePoll = function() return false end
    return true
  elseif op == "incrementgamestat" then
    -- src/scrcmd.c:576-579, overworld.c:366-375, include/constants/game_stat.h:57
    local statId = tonumber(row[1]) or -1
    if statId >= 0 and statId < 52 then
      local Runtime = package.loaded["src.core.game3.runtime"]
      local session = Runtime and Runtime.getSession and Runtime.getSession()
      if session then
        session.gameStats = session.gameStats or {}
        local cur = tonumber(session.gameStats[statId]) or 0
        session.gameStats[statId] = math.min(0xFFFFFF, cur + 1)
      end
    end
    return false
  elseif op == "checkpartymove" then
    -- src/scrcmd.c:1777-1795
    local moveId = tonumber(row[1]) or 0
    local Runtime = package.loaded["src.core.game3.runtime"]
    local session = Runtime and Runtime.getSession and Runtime.getSession()
    local Pokemon = require("src.core.game3.pokemon")
    Flags.setVar(store, ctx, Ctx.VAR_RESULT, 6)
    local party = session and session.party or {}
    for i = 1, 6 do
      local mon = party[i]
      local sp = mon and (tonumber(mon.species) or 0) or 0
      if sp == 0 then break end
      if not mon.isEgg and not mon.egg and Pokemon.knowsMove(mon, moveId) then
        Flags.setVar(store, ctx, Ctx.VAR_RESULT, i - 1)
        Flags.setVar(store, ctx, 0x8004, sp)
        break
      end
    end
    return false
  elseif op == "erasebox" then
    return false
  else
    local Runtime = package.loaded["src.core.game3.runtime"]
    local game = Runtime and Runtime._game
    local commands = game and game.data and game.data.commands
    local record = type(commands) == "table" and commands[op]
    local fn = type(record) == "table" and record.fn or record
    if type(fn) == "function" then
      local okCall, res = pcall(fn, Ctx.modCtx(vm), unpack(row))
      if not okCall then
        if a.log then a.log("[game3] command " .. tostring(op) .. " failed: " .. tostring(res)) end
        return false
      end
      if type(res) == "string" and vm.scripts and vm.scripts[res] then
        jump(vm, res)
      elseif res == "end" then
        vm:halt()
        return true
      end
      return false
    end
    if PRET_NO_OPS[op] then return false end
    -- Unknown / Tier C: skip
    if a.log then a.log("[game3] skip op " .. tostring(op)) end
    return false
  end
end

local function commandVanilla(vm)
  return function(_, name, hrow)
    if type(hrow) ~= "table" then hrow = {} end
    if name ~= nil and name ~= hrow.op then
      local copy = {}
      for k, v in pairs(hrow) do copy[k] = v end
      copy.op = name
      hrow = copy
    end
    return dispatch(vm, hrow)
  end
end

function Ops.dispatch(vm, row)
  if not ModRuntime.wantsHook("script.command") then
    return dispatch(vm, row)
  end
  return ModRuntime.call("script.command", commandVanilla(vm), Ctx.modCtx(vm), row.op, row)
end

Ops.warpHoleDest = warp_hole_dest
Ops.setMapLayout = set_map_layout
Ops.brailleWidth = braille_width

return Ops
