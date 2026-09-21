-- Write game3 script/event cache blobs from ROM MapEvents + BFS (primary),
-- or curated island1_content (dev/CI fallback when no ROM extract).

local Content = require("src.import.gba.island1_content")
local Disasm = require("src.core.game3.scripting.disasm")
local TextIR = require("src.core.game3.scripting.text_ir")
local Movement = require("src.core.game3.scripting.movement")
local Versions = require("src.import.gba.versions")
local Opcodes = require("src.core.game3.scripting.opcodes")
local ExtractMapEvents = require("src.import.gba.extract_map_events")

local ExtractScripts = {}

ExtractScripts.CACHE_SUB = "scripts"

local SCRIPT_CHUNK = 8192
local TEXT_MAX = 1024
local MOVE_MAX = 256
local BFS_MAX = 4000

local function json_escape(s)
  return (tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"))
end

local function serialize_lua(val, indent)
  indent = indent or 0
  local sp = string.rep("  ", indent)
  local sp1 = string.rep("  ", indent + 1)
  local t = type(val)
  if t == "nil" then return "nil" end
  if t == "boolean" then return val and "true" or "false" end
  if t == "number" then return tostring(val) end
  if t == "string" then
    return string.format("%q", val)
  end
  if t ~= "table" then return "nil" end
  local n = #val
  local isArr = n > 0
  if isArr then
    for k in pairs(val) do
      if type(k) ~= "number" then isArr = false; break end
    end
  end
  local parts = { "{\n" }
  if isArr then
    for i = 1, n do
      parts[#parts + 1] = sp1 .. serialize_lua(val[i], indent + 1) .. ",\n"
    end
  else
    local keys = {}
    for k in pairs(val) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. serialize_lua(k) .. "]"
      end
      parts[#parts + 1] = sp1 .. key .. " = " .. serialize_lua(val[k], indent + 1) .. ",\n"
    end
  end
  parts[#parts + 1] = sp .. "}"
  return table.concat(parts)
end

local function merge_std_scripts()
  local scripts = {}
  for k, v in pairs(Content.STDSCRIPTS) do scripts[k] = v end
  return scripts
end

local function merge_std_text()
  local text = {}
  for k, v in pairs(Content.TEXT) do
    -- Prefer extracted text; curated TEXT is only used for std nurse/PC labels
    -- that are not in ROM BFS (EventScript_PC host path).
    if type(k) == "string" and (k:find("^Text_", 1, true) or k:find("^EventScript", 1, true)) then
      text[k] = v
    end
  end
  -- Always include Std nurse/PC text keys.
  local Std = require("src.core.game3.scripting.stdscripts")
  for k, v in pairs(Std.TEXT) do text[k] = v end
  return text
end

local function is_rom_ptr(ptr)
  ptr = tonumber(ptr) or 0
  return ptr >= 0x08000000 and ptr < 0x0A000000
end

local function read_text_ir(rom, gbaPtr)
  local off = rom:ptrOffset(gbaPtr)
  if not off then return nil end
  local bytes = {}
  for i = 0, TEXT_MAX - 1 do
    local b = rom:get(off + i)
    bytes[#bytes + 1] = b
    if b == 0xFF then break end
  end
  return TextIR.decode(bytes)
end

-- pokefirered/include/characters.h:285
local BRAILLE_CHARMAP = {
  [0x00] = " ",
  [0x01] = "A", [0x03] = "C", [0x04] = ",", [0x05] = "B", [0x06] = "I",
  [0x07] = "F", [0x09] = "E", [0x0B] = "D", [0x0C] = ":", [0x0D] = "H",
  [0x0E] = "J", [0x0F] = "G", [0x10] = "'", [0x11] = "K", [0x12] = "/",
  [0x13] = "M", [0x14] = ";", [0x15] = "L", [0x16] = "S", [0x17] = "P",
  [0x19] = "O", [0x1B] = "N", [0x1C] = "!", [0x1D] = "R", [0x1E] = "T",
  [0x1F] = "Q", [0x2C] = ".", [0x2E] = "W", [0x30] = "-", [0x31] = "U",
  [0x33] = "X", [0x34] = "?", [0x35] = "V", [0x38] = '"', [0x39] = "Z",
  [0x3A] = "#", [0x3B] = "Y", [0x3C] = "(",
}

local function decode_braille(bytes)
  local out, buf = {}, {}
  local function flush()
    if #buf > 0 then
      out[#out + 1] = { t = "text", s = table.concat(buf) }
      buf = {}
    end
  end
  local n = #bytes
  for i = 1, n do
    local c = bytes[i]
    if c == 0xFF then
      flush()
      out[#out + 1] = { t = "eos" }
      break
    elseif c == 0xFE then
      flush()
      out[#out + 1] = { t = "nl" }
    else
      buf[#buf + 1] = BRAILLE_CHARMAP[c] or "?"
    end
  end
  flush()
  return out
end

local function read_braille_ir(rom, gbaPtr)
  local off = rom:ptrOffset(gbaPtr)
  if not off then return nil end
  local bytes = {}
  for i = 0, TEXT_MAX - 1 do
    local b = rom:get(off + i)
    if not b then break end
    bytes[#bytes + 1] = b
    if b == 0xFF then break end
  end
  return decode_braille(bytes)
end

ExtractScripts.BRAILLE_CHARMAP = BRAILLE_CHARMAP
ExtractScripts.decodeBraille = decode_braille

local function read_movement(rom, gbaPtr)
  local off = rom:ptrOffset(gbaPtr)
  if not off then return nil end
  local bytes = rom:readBytes(off, MOVE_MAX)
  return Disasm.decodeMovement(bytes, 1)
end

--- BFS disasm from seed GBA pointers → scripts / text / movements tables.
-- Annotates IR so goto/call/message/applymovement use stable keys.
function ExtractScripts.bfsFromSeeds(rom, seedPtrs)
  local scripts, text, movements, marts = {}, {}, {}, {}
  local opInventory, specialInventory = {}, {}
  local queue = {}
  local queued = {}
  local function enqueue(ptr)
    ptr = tonumber(ptr) or 0
    if not is_rom_ptr(ptr) then return end
    if queued[ptr] then return end
    queued[ptr] = true
    queue[#queue + 1] = ptr
  end
  for _, p in ipairs(seedPtrs or {}) do enqueue(p) end

  local processed = 0
  while #queue > 0 and processed < BFS_MAX do
    local ptr = table.remove(queue, 1)
    processed = processed + 1
    local key = Opcodes.key(ptr)
    if scripts[key] then goto continue end
    local off = rom:ptrOffset(ptr)
    if not off then goto continue end
    local bytes = rom:readBytes(off, SCRIPT_CHUNK)
    local rows = {}
    local i = 1
    local guard = 0
    while i <= #bytes and guard < 4096 do
      guard = guard + 1
      local row
      row, i = Disasm.decodeOne(bytes, i)
      opInventory[row.op] = (opInventory[row.op] or 0) + 1
      if row.op == "special" or row.op == "specialvar" then
        local id = row.id or row[1]
        if id then specialInventory[id] = (specialInventory[id] or 0) + 1 end
      end
      if row.op == "unknown" or (row.op == "trainerbattle" and row.opaque) then
        rows[#rows + 1] = row
        break
      end
      -- Remap pointer operands to keys + enqueue.
      if row.target and is_rom_ptr(row.target) then
        enqueue(row.target)
        row.target = Opcodes.key(row.target)
      end
      if row.op == "trainerbattle" then
        -- Remap embedded text / continue-script pointers; keep scanning so
        -- the post-battle ret addr (e.g. goto EndRivalBattle) is enqueued.
        for _, field in ipairs({ "introText", "defeatText", "victoryText",
            "notEnoughText", "eventScript" }) do
          local tp = row[field]
          if is_rom_ptr(tp) then
            local tk = Opcodes.key(tp)
            if field == "eventScript" then
              enqueue(tp)
            elseif not text[tk] then
              text[tk] = read_text_ir(rom, tp)
            end
            row[field] = tk
          end
        end
      elseif row.op == "goto" or row.op == "call" or row.op == "goto_if"
          or row.op == "call_if" or row.op == "vgoto" or row.op == "vcall"
          or row.op == "vgoto_if" or row.op == "vcall_if" then
        -- target already remapped
      elseif row.op == "braillemessage" or row.op == "getbraillestringwidth" then
        -- pokefirered/asm/macros/event.inc:1845
        local tp = row.ptr or row[1]
        if is_rom_ptr(tp) then
          local tk = Opcodes.key(tp)
          local ir = read_braille_ir(rom, tp)
          if ir then text[tk] = ir end
          row.ptr = tk
          row[1] = tk
        end
      elseif row.op == "message" or row.op == "vmessage"
          or row.op == "messageautoscroll" then
        local tp = row.ptr or row[1]
        if is_rom_ptr(tp) then
          local tk = Opcodes.key(tp)
          if not text[tk] then text[tk] = read_text_ir(rom, tp) end
          row.ptr = tk
          row[1] = tk
        end
      elseif row.op == "loadword" then
        local val = row.value or row[2]
        if is_rom_ptr(val) then
          local tk = Opcodes.key(val)
          if not text[tk] then text[tk] = read_text_ir(rom, val) end
          row.value = tk
          row[2] = tk
        end
      elseif row.op == "bufferstring" then
        local sp = row.src or row[2]
        if is_rom_ptr(sp) then
          local tk = Opcodes.key(sp)
          if not text[tk] then text[tk] = read_text_ir(rom, sp) end
          row.src = tk
          row[2] = tk
        end
      elseif row.op == "applymovement" or row.op == "applymovementat" then
        local mp = row.movement or row[2]
        if is_rom_ptr(mp) then
          local mk = Opcodes.key(mp)
          if not movements[mk] then movements[mk] = read_movement(rom, mp) end
          row.movement = mk
          row[2] = mk
        end
      elseif row.op == "pokemart" or row.op == "pokemartdecoration"
          or row.op == "pokemartdecoration2" then
        local MartsExtract = require("src.import.gba.marts_extract")
        MartsExtract.remapRow(rom, row, marts)
      end
      rows[#rows + 1] = row
      if row.op == "end" or row.op == "return" then
        break
      end
      -- gotostd / callstd — std overlay covers runtime; no ROM enqueue
    end
    scripts[key] = rows
    ::continue::
  end

  return {
    scripts = scripts,
    text = text,
    movements = movements,
    marts = marts,
    opInventory = opInventory,
    specialInventory = specialInventory,
    scriptCount = processed,
  }
end

--- Full Island 1 extract: MapEvents + BFS + stdscripts overlay.
function ExtractScripts.extractFromRom(rom, version)
  local events, seeds = ExtractMapEvents.extractIsland1(rom, version)
  local bfs = ExtractScripts.bfsFromSeeds(rom, seeds)
  local scripts = merge_std_scripts()
  for k, v in pairs(bfs.scripts) do scripts[k] = v end
  local text = merge_std_text()
  for k, v in pairs(bfs.text) do text[k] = v end
  local movements = {}
  for k, v in pairs(bfs.movements) do movements[k] = v end
  return {
    events = events,
    scripts = scripts,
    text = text,
    movements = movements,
    marts = bfs.marts or {},
    opInventory = bfs.opInventory,
    specialInventory = bfs.specialInventory,
    seedCount = #seeds,
    scriptCount = bfs.scriptCount,
    fromRom = true,
  }
end

local function write_tables(cache, root, scripts, text, movements, events, metaExtra)
  root = root or "data/generated/gba"
  local base = root .. "/" .. ExtractScripts.CACHE_SUB
  cache:write(base .. "/scripts.lua", "return " .. serialize_lua(scripts) .. "\n")
  cache:write(base .. "/text.lua", "return " .. serialize_lua(text) .. "\n")
  cache:write(base .. "/movements.lua", "return " .. serialize_lua(movements) .. "\n")
  cache:write(base .. "/stdscripts.lua", "return " .. serialize_lua(merge_std_scripts()) .. "\n")
  cache:write(base .. "/events.lua", "return " .. serialize_lua(events) .. "\n")
  local meta = {
    cache_version = Versions.CACHE_VERSION,
    kind = "game3",
    source = metaExtra and metaExtra.source or "rom",
    maps = {},
  }
  for mapId in pairs(events or {}) do
    meta.maps[#meta.maps + 1] = mapId
  end
  table.sort(meta.maps)
  if metaExtra and metaExtra.opInventory then
    -- Compact inventory for smoke / ISA growth tracking.
    local inv = {}
    for op, n in pairs(metaExtra.opInventory) do
      inv[#inv + 1] = string.format("%s:%d", op, n)
    end
    table.sort(inv)
    meta.ops = inv
  end
  local parts = { "{" }
  parts[#parts + 1] = string.format('"cache_version":%d', meta.cache_version)
  parts[#parts + 1] = string.format(',"kind":%q', meta.kind)
  parts[#parts + 1] = string.format(',"source":%q', meta.source)
  parts[#parts + 1] = ',"maps":['
  for i, m in ipairs(meta.maps) do
    if i > 1 then parts[#parts + 1] = "," end
    parts[#parts + 1] = string.format("%q", m)
  end
  parts[#parts + 1] = "]"
  if meta.ops then
    parts[#parts + 1] = ',"ops":['
    for i, o in ipairs(meta.ops) do
      if i > 1 then parts[#parts + 1] = "," end
      parts[#parts + 1] = string.format("%q", o)
    end
    parts[#parts + 1] = "]"
  end
  parts[#parts + 1] = "}\n"
  cache:write(base .. "/meta.json", table.concat(parts))
  return true
end

--- Primary write path: ROM MapEvents + BFS.
function ExtractScripts.writeBundleFromRom(rom, cache, root, version, extracted)
  local bundle = extracted or ExtractScripts.extractFromRom(rom, version)
  write_tables(cache, root, bundle.scripts, bundle.text, bundle.movements, bundle.events, {
    source = "rom",
    opInventory = bundle.opInventory,
  })
  do
    local MartsExtract = require("src.import.gba.marts_extract")
    local marts = bundle.marts
    if not marts or not next(marts) then
      marts = select(1, MartsExtract.build(rom, bundle.scripts))
    end
    local n = 0
    local seen = {}
    for k, e in pairs(marts or {}) do
      if type(k) == "number" and e and not seen[e.ptr] then
        seen[e.ptr] = true
        n = n + 1
      end
    end
    MartsExtract.write(cache, root, marts, { count = n })
    bundle.martListCount = n
  end
  do
    local FlagsExtract = require("src.import.gba.flags_extract")
    FlagsExtract.write(cache, root)
  end
  return bundle
end

--- Dev/CI fallback: curated island1_content (no ROM).
function ExtractScripts.writeBundle(cache, root)
  local scripts = merge_std_scripts()
  for k, v in pairs(Content.SCRIPTS) do scripts[k] = v end
  write_tables(cache, root, scripts, Content.TEXT, Content.MOVEMENTS or {}, Content.EVENTS, {
    source = "curated",
  })
  do
    local FlagsExtract = require("src.import.gba.flags_extract")
    FlagsExtract.write(cache, root)
  end
  return true
end

--- Cache contract: ready extract has events+scripts+text.
function ExtractScripts.bundleReady(bundle)
  if not bundle then return false, "nil bundle" end
  if not bundle.scripts or not next(bundle.scripts) then
    return false, "missing scripts"
  end
  if not bundle.events or not next(bundle.events) then
    return false, "missing events"
  end
  if not bundle.text then
    return false, "missing text"
  end
  return true
end

function ExtractScripts.loadBundle(cache, root, opts)
  opts = opts or {}
  root = root or "data/generated/gba"
  local base = root .. "/" .. ExtractScripts.CACHE_SUB
  local function load_lua(rel)
    local src = cache:read(rel)
    if not src then return nil end
    local chunk, err = load(src, "@" .. rel, "t", {})
    if not chunk then return nil, err end
    return chunk()
  end
  local scripts = load_lua(base .. "/scripts.lua")
  local text = load_lua(base .. "/text.lua")
  local movements = load_lua(base .. "/movements.lua")
  local events = load_lua(base .. "/events.lua")
  if scripts and events then
    local objects=load_lua(root .. "/objects/pack.lua")
    require("src.core.game3.scripting.interaction_scripts").install(objects)
    require("src.core.game3.encounters").installEncounterTypes(objects and objects.encounterTypes)
    if objects then
      text=text or {};movements=movements or {}
      for k,v in pairs(objects.scripts or {}) do scripts[k]=v end
      for k,v in pairs(objects.text or {}) do text[k]=v end
      for k,v in pairs(objects.movements or {}) do movements[k]=v end
    end
    -- Overlay stdscripts always (nurse/PC host arms).
    for k, v in pairs(merge_std_scripts()) do
      scripts[k] = v
    end
    local stdText = merge_std_text()
    text = text or {}
    for k, v in pairs(stdText) do
      if text[k] == nil then text[k] = v end
    end
    local bundle = {
      scripts = scripts,
      text = text,
      movements = movements or {},
      events = events,
      fromCache = true,
      fromCurated = false,
    }
    do
      local Marts = require("src.core.game3.marts")
      local n = Marts.load(cache, root)
      bundle.martListCount = n
    end
    local ok, why = ExtractScripts.bundleReady(bundle)
    if not ok and not opts.allowIncomplete then
      -- Incomplete cache: refuse silent curated substitution for "normal" boots.
      if opts.strict then
        return nil, why
      end
    end
    return bundle
  end
  -- No cache: curated fallback (CI / no ROM).
  if opts.forbidCurated then
    return nil, "extract cache missing"
  end
  return {
    scripts = (function()
      local s = merge_std_scripts()
      for k, v in pairs(Content.SCRIPTS) do s[k] = v end
      return s
    end)(),
    text = Content.TEXT,
    movements = Content.MOVEMENTS or {},
    events = Content.EVENTS,
    fromCache = false,
    fromCurated = true,
  }
end

ExtractScripts.Disasm = Disasm
ExtractScripts.TextIR = TextIR
ExtractScripts.Movement = Movement
ExtractScripts.Content = Content
ExtractScripts.serialize_lua = serialize_lua

return ExtractScripts
