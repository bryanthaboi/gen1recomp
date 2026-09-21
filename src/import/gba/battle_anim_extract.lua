-- ROM-native GBA battle anim extraction.
-- Decodes bytecode scripts from gBattleAnims_Moves and subroutines.
-- createsprite: reads SpriteTemplate.tileTag from the embedded ROM pointer → true tag.
-- Sprite sheets: decompressed from gBattleAnimPicTable + gBattleAnimPaletteTable → PNG.
-- Writes: {cacheRoot}/pokemon/battle_anims/pack.lua  +  tags/*.png

local Versions  = require("src.import.gba.versions")
local Lz77      = require("src.import.gba.lz77")

local BattleAnimExtract = {}

BattleAnimExtract.FORMAT_VERSION = 5
BattleAnimExtract.CACHE_SUB      = "pokemon/battle_anims"

local V = Versions.BATTLE_ANIMS or {}

-- ── opcode sizes (total bytes incl. opcode byte) for fixed-width opcodes ──
-- Variable-width: 0x02 createsprite, 0x03 createvisualtask, 0x1F createsoundtask
local OP_FIXED = {
  [0x00]=3,[0x01]=3,                -- loadspritegfx / unloadspritegfx
  [0x04]=2,[0x05]=1,[0x06]=1,[0x07]=1,[0x08]=1, -- delay/waitforvisualfinish/nop/nop2/end
  [0x09]=3,                          -- playse
  [0x0A]=2,[0x0B]=2,                 -- monbg / clearmonbg
  [0x0C]=3,                          -- setalpha
  [0x0D]=1,                          -- blendoff
  [0x0E]=5,                          -- call
  [0x0F]=1,                          -- return
  [0x10]=4,                          -- setarg
  [0x11]=9,                          -- choosetwoturnanim
  [0x12]=6,                          -- jumpifmoveturn
  [0x13]=5,                          -- goto
  [0x14]=2,[0x15]=1,[0x16]=1,[0x17]=1,[0x18]=2, -- fadetobg/restorebg/waitbgfadeout/waitbgfadein/changebg
  [0x19]=4,                          -- playsewithpan
  [0x1A]=2,                          -- setpan
  [0x1B]=7,                          -- panse
  [0x1C]=6,                          -- loopsewithpan
  [0x1D]=5,                          -- waitplaysewithpan
  [0x1E]=3,                          -- setbldcnt
  [0x20]=1,                          -- waitsound
  [0x21]=8,                          -- jumpargeq
  [0x22]=2,[0x23]=2,                 -- monbg_static / clearmonbg_static
  [0x24]=5,                          -- jumpifcontest
  [0x25]=4,                          -- fadetobgfromset
  [0x26]=7,[0x27]=7,                 -- panse_adjustnone / panse_adjustall
  [0x28]=2,[0x29]=1,[0x2A]=2,        -- splitbgprio / splitbgprio_all / splitbgprio_foes
  [0x2B]=2,[0x2C]=2,                 -- invisible / visible
  [0x2D]=2,[0x2E]=2,[0x2F]=1,        -- teamattack_moveback / movefwd / stopsound
}

local SPRITES_START = V.sprites_start or 10000
local TAG_NAMES     = Versions.ANIM_TAG_NAMES or {}

local BATTLER_NAMES = { [0]="attacker", [1]="target", [2]="atk_partner", [3]="def_partner" }

-- Signed-extend 8-bit (for pan values stored as s8).
local function s8(v)
  if v >= 128 then return v - 256 end
  return v
end

-- Signed-extend 16-bit (for arg values stored as s16).
local function s16(v)
  if v >= 32768 then return v - 65536 end
  return v
end

--- Decode one battle anim bytecode script beginning at file offset `startOff`.
-- @param rom   Rom instance
-- @param startOff  0-based ROM file offset of first opcode byte
-- @param visited   table of offsets already decoded (avoid infinite loops across goto chains)
-- @param labels    table: ROM-offset-string → script IR list (filled in-place for call/goto targets)
-- @return list of IR op tables
local function decode_script(rom, startOff, visited, labels, tag_dims)
  if visited[startOff] then
    return labels[tostring(startOff)] or {}
  end
  visited[startOff] = true

  local ops = {}
  labels[tostring(startOff)] = ops

  local i = startOff
  local guard = 0
  while guard < 4096 do
    guard = guard + 1
    if i >= rom.size then break end

    local op = rom:get(i)

    if op == 0x08 then  -- end
      ops[#ops + 1] = { op = "end" }
      break

    elseif op == 0x00 then  -- loadspritegfx
      local tag_id  = rom:u16(i + 1)
      local tag_idx = tag_id - SPRITES_START
      local name    = TAG_NAMES[tag_idx] or ("TAG_" .. tag_idx)
      ops[#ops + 1] = { op = "loadspritegfx", tag = name, tag_idx = tag_idx }
      i = i + 3

    elseif op == 0x01 then  -- unloadspritegfx
      local tag_id  = rom:u16(i + 1)
      local tag_idx = tag_id - SPRITES_START
      local name    = TAG_NAMES[tag_idx] or ("TAG_" .. tag_idx)
      ops[#ops + 1] = { op = "unloadspritegfx", tag = name }
      i = i + 3

    elseif op == 0x02 then  -- createsprite
      local tmpl_gba = rom:u32(i + 1)
      local tmpl_off = rom:ptrOffset(tmpl_gba)
      -- SpriteTemplate layout: tileTag(u16)+paletteTag(u16)+oam*(u32)+anims*(u32)+images*(u32)+affineAnims*(u32)+callback*(u32) = 24 bytes
      local tile_id   = tmpl_off and rom:u16(tmpl_off)     or 0
      local tile_idx  = tile_id - SPRITES_START
      local tag_name  = (tile_id >= SPRITES_START) and (TAG_NAMES[tile_idx] or ("TAG_" .. tile_idx)) or nil
      local noGfx     = (tile_id < SPRITES_START)  -- tileTag = 0 means TAG_NONE → no gfx
      local pal_id    = tmpl_off and rom:u16(tmpl_off + 2) or 0
      local pal_name  = (pal_id >= SPRITES_START) and (TAG_NAMES[pal_id - SPRITES_START] or ("TAG_" .. (pal_id - SPRITES_START))) or nil

      -- OAM dimensions from SpriteTemplate.oam pointer
      local w, h = 32, 32
      if tmpl_off then
        local oam_gba = rom:u32(tmpl_off + 4)
        local oam_off = rom:ptrOffset(oam_gba)
        if oam_off then
          -- OAM struct: 4 bytes total. shape=bits[15:14] of u16[0], size=bits[15:14] of u16[1]
          local h0 = rom:u16(oam_off)
          local h1 = rom:u16(oam_off + 2)
          local shape = math.floor(h0 / 0x4000) % 4  -- bits [15:14]
          local size  = math.floor(h1 / 0x4000) % 4  -- bits [15:14]
          local DIMS = {  -- {w,h} indexed by [shape][size]
            [0]={{8,8},{16,16},{32,32},{64,64}},  -- square
            [1]={{16,8},{32,8},{32,16},{64,32}},  -- wide
            [2]={{8,16},{8,32},{16,32},{32,64}},  -- tall
          }
          local row = DIMS[shape]
          if row and row[size + 1] then
            w, h = row[size + 1][1], row[size + 1][2]
          end
        end
      end

      local cb_gba = tmpl_off and rom:u32(tmpl_off + 20) or 0
      local cb_name = Versions.ANIM_CALLBACK_NAMES and Versions.ANIM_CALLBACK_NAMES[cb_gba]
      local tmpl_name = Versions.ANIM_TEMPLATE_NAMES and Versions.ANIM_TEMPLATE_NAMES[tmpl_gba]

      if tag_name and tag_dims and not tag_dims[tag_name] then
        tag_dims[tag_name] = { w = w, h = h }
      end

      local battler_byte = rom:get(i + 5)
      local is_target    = (battler_byte >= 0x80)
      local subpri       = battler_byte % 0x80
      local argc         = rom:get(i + 6)
      local args = {}
      for ai = 0, argc - 1 do
        args[ai + 1] = s16(rom:u16(i + 7 + ai * 2))
      end

      local battler = is_target and "target" or "attacker"

      ops[#ops + 1] = {
        op           = "createsprite",
        template     = tmpl_name,
        tag          = tag_name,
        palTag       = (pal_name ~= tag_name) and pal_name or nil,
        callback     = cb_name,
        noGfx        = noGfx or nil,
        w            = w,
        h            = h,
        animBattler  = battler,
        subpriority  = subpri,
        args         = args,
      }
      i = i + 7 + argc * 2

    elseif op == 0x03 then  -- createvisualtask
      local fn_gba = rom:u32(i + 1)
      local pri    = rom:get(i + 5)
      local argc   = rom:get(i + 6)
      local args   = {}
      for ai = 0, argc - 1 do
        args[ai + 1] = s16(rom:u16(i + 7 + ai * 2))
      end
      local task_name = Versions.ANIM_TASK_NAMES and Versions.ANIM_TASK_NAMES[fn_gba]
      ops[#ops + 1] = {
        op       = "createvisualtask",
        task     = task_name or string.format("0x%08X", fn_gba),
        priority = pri,
        args     = args,
      }
      i = i + 7 + argc * 2

    elseif op == 0x04 then  -- delay
      ops[#ops + 1] = { op = "delay", frames = rom:get(i + 1) }
      i = i + 2

    elseif op == 0x05 then  -- waitforvisualfinish
      ops[#ops + 1] = { op = "waitforvisualfinish" }
      i = i + 1

    elseif op == 0x09 then  -- playse
      local se = rom:u16(i + 1)
      ops[#ops + 1] = { op = "playse", se = se }
      i = i + 3

    elseif op == 0x0A then  -- monbg
      local b = rom:get(i + 1)
      ops[#ops + 1] = { op = "monbg", battler = BATTLER_NAMES[b] or "target" }
      i = i + 2

    elseif op == 0x0B then  -- clearmonbg
      local b = rom:get(i + 1)
      ops[#ops + 1] = { op = "clearmonbg", battler = BATTLER_NAMES[b] or "target" }
      i = i + 2

    elseif op == 0x0C then  -- setalpha
      local v  = rom:u16(i + 1)
      local eva = v % 256
      local evb = math.floor(v / 256) % 256
      ops[#ops + 1] = { op = "setalpha", eva = eva, evb = evb }
      i = i + 3

    elseif op == 0x0D then  -- blendoff
      ops[#ops + 1] = { op = "blendoff" }
      i = i + 1

    elseif op == 0x0E then  -- call
      local target_gba = rom:u32(i + 1)
      local target_off = rom:ptrOffset(target_gba)
      ops[#ops + 1] = { op = "call", label = tostring(target_off) }
      i = i + 5
      -- Eagerly decode target if not yet visited
      if target_off and not visited[target_off] then
        decode_script(rom, target_off, visited, labels, tag_dims)
      end

    elseif op == 0x0F then  -- return
      ops[#ops + 1] = { op = "return" }
      break

    elseif op == 0x10 then  -- setarg
      local argId = rom:get(i + 1)
      local val   = s16(rom:u16(i + 2))
      ops[#ops + 1] = { op = "setarg", argId = argId, value = val }
      i = i + 4

    elseif op == 0x11 then  -- choosetwoturnanim
      local ptr1 = rom:u32(i + 1)
      local ptr2 = rom:u32(i + 5)
      local off1 = rom:ptrOffset(ptr1)
      local off2 = rom:ptrOffset(ptr2)
      ops[#ops + 1] = { op = "choosetwoturnanim", label1 = tostring(off1), label2 = tostring(off2) }
      i = i + 9
      if off1 and not visited[off1] then decode_script(rom, off1, visited, labels, tag_dims) end
      if off2 and not visited[off2] then decode_script(rom, off2, visited, labels, tag_dims) end

    elseif op == 0x12 then  -- jumpifmoveturn
      local toCheck = rom:get(i + 1)
      local ptr = rom:u32(i + 2)
      local off = rom:ptrOffset(ptr)
      ops[#ops + 1] = { op = "jumpifmoveturn", turn = toCheck, label = tostring(off) }
      i = i + 6
      if off and not visited[off] then decode_script(rom, off, visited, labels, tag_dims) end

    elseif op == 0x13 then  -- goto
      local target_gba = rom:u32(i + 1)
      local target_off = rom:ptrOffset(target_gba)
      ops[#ops + 1] = { op = "goto", label = tostring(target_off) }
      -- Decode target then stop (tail-jump)
      if target_off and not visited[target_off] then
        decode_script(rom, target_off, visited, labels, tag_dims)
      end
      break

    elseif op == 0x14 then  -- fadetobg
      local bgId = rom:get(i + 1)
      ops[#ops + 1] = { op = "fadetobg", bg = bgId }
      i = i + 2

    elseif op == 0x15 then  -- restorebg
      ops[#ops + 1] = { op = "restorebg" }
      i = i + 1

    elseif op == 0x18 then  -- changebg
      local bgId = rom:get(i + 1)
      ops[#ops + 1] = { op = "changebg", bg = bgId }
      i = i + 2

    elseif op == 0x19 then  -- playsewithpan
      local se  = rom:u16(i + 1)
      local pan = s8(rom:get(i + 3))
      ops[#ops + 1] = { op = "playsewithpan", se = se, pan = pan }
      i = i + 4

    elseif op == 0x1B then  -- panse
      local se   = rom:u16(i + 1)
      local pan1 = s8(rom:get(i + 3))
      local pan2 = s8(rom:get(i + 4))
      local step = s8(rom:get(i + 5))
      local wait = rom:get(i + 6)
      ops[#ops + 1] = { op = "panse", se = se, pan = pan1, targetPan = pan2, step = step, wait = wait }
      i = i + 7

    elseif op == 0x1C then  -- loopsewithpan
      local se    = rom:u16(i + 1)
      local pan   = s8(rom:get(i + 3))
      local wait  = rom:get(i + 4)
      local times = rom:get(i + 5)
      ops[#ops + 1] = { op = "loopsewithpan", se = se, pan = pan, wait = wait, times = times }
      i = i + 6

    elseif op == 0x1D then  -- waitplaysewithpan
      local se   = rom:u16(i + 1)
      local pan  = s8(rom:get(i + 3))
      local wait = rom:get(i + 4)
      ops[#ops + 1] = { op = "waitplaysewithpan", se = se, pan = pan, wait = wait }
      i = i + 5

    elseif op == 0x1F then  -- createsoundtask (variable, like createvisualtask)
      local fn_gba = rom:u32(i + 1)
      local argc   = rom:get(i + 5)
      local args   = {}
      for ai = 0, argc - 1 do
        args[ai + 1] = s16(rom:u16(i + 6 + ai * 2))
      end
      local snd_name = Versions.ANIM_TASK_NAMES and Versions.ANIM_TASK_NAMES[fn_gba]
      ops[#ops + 1] = {
        op   = "createsoundtask",
        task = snd_name or string.format("0x%08X", fn_gba),
        args = args,
      }
      i = i + 6 + argc * 2

    elseif op == 0x21 then  -- jumpargeq
      local argId = rom:get(i + 1)
      local val   = s16(rom:u16(i + 2))
      local ptr   = rom:u32(i + 4)
      local off   = rom:ptrOffset(ptr)
      ops[#ops + 1] = { op = "jumpargeq", argId = argId, value = val, label = tostring(off) }
      i = i + 8
      if off and not visited[off] then decode_script(rom, off, visited, labels, tag_dims) end

    elseif op == 0x25 then  -- fadetobgfromset
      ops[#ops + 1] = { op = "fadetobgfromset", bg1 = rom:get(i + 1), bg2 = rom:get(i + 2), bg3 = rom:get(i + 3) }
      i = i + 4

    elseif op == 0x26 or op == 0x27 then  -- panse_adjustnone / panse_adjustall
      local se   = rom:u16(i + 1)
      local pan1 = s8(rom:get(i + 3))
      local pan2 = s8(rom:get(i + 4))
      local step = s8(rom:get(i + 5))
      local wait = rom:get(i + 6)
      ops[#ops + 1] = { op = "panse", se = se, pan = pan1, targetPan = pan2, step = step, wait = wait,
        mode = (op == 0x26) and "adjustnone" or "adjustall" }
      i = i + 7

    elseif op == 0x28 or op == 0x29 or op == 0x2A then  -- splitbgprio / splitbgprio_all / splitbgprio_foes
      local b = (op == 0x28 or op == 0x2A) and rom:get(i + 1) or 1
      ops[#ops + 1] = { op = "splitbgprio", battler = BATTLER_NAMES[b] or "target",
        mode = (op == 0x29) and "all" or ((op == 0x2A) and "foes" or nil) }
      i = i + (op == 0x29 and 1 or 2)

    elseif op == 0x16 or op == 0x17 or op == 0x20 or op == 0x2F then
      local names = { [0x16] = "waitbgfadeout", [0x17] = "waitbgfadein", [0x20] = "waitsound", [0x2F] = "stopsound" }
      ops[#ops + 1] = { op = names[op] }
      i = i + 1

    elseif op == 0x1A then
      ops[#ops + 1] = { op = "setpan", pan = s8(rom:get(i + 1)) }
      i = i + 2

    elseif op == 0x1E then
      ops[#ops + 1] = { op = "setbldcnt", value = rom:u16(i + 1) }
      i = i + 3

    elseif op == 0x22 or op == 0x23 then
      local b = rom:get(i + 1)
      ops[#ops + 1] = { op = (op == 0x22) and "monbg_static" or "clearmonbg_static", battler = BATTLER_NAMES[b] or "target" }
      i = i + 2

    elseif op == 0x24 then
      ops[#ops + 1] = { op = "jumpifcontest" }
      i = i + 5

    elseif op == 0x2B then  -- invisible
      ops[#ops + 1] = { op = "invisible", battler = BATTLER_NAMES[rom:get(i+1)] or "attacker" }
      i = i + 2

    elseif op == 0x2C then  -- visible
      ops[#ops + 1] = { op = "visible", battler = BATTLER_NAMES[rom:get(i+1)] or "attacker" }
      i = i + 2

    else
      -- Fixed-size or unknown: step by known size, emit nop
      local sz = OP_FIXED[op] or 1
      if sz > 1 or (op >= 0x05 and op <= 0x2F) then
        ops[#ops + 1] = { op = "nop" }
      end
      i = i + sz
    end
  end

  -- Ensure scripts always terminate
  if #ops == 0 or (ops[#ops].op ~= "end" and ops[#ops].op ~= "return") then
    ops[#ops + 1] = { op = "end" }
  end
  return ops
end

-- ── Sprite sheet extraction ───────────────────────────────────────────────

--- Decode one GBA 4bpp tile (32 bytes) to 8×8 RGBA pixels into `out[1..64*4]`.
local function decode_4bpp_tile(rom_bytes, tile_off, pal, out, out_off)
  for byte_i = 0, 31 do
    local b    = rom_bytes[tile_off + byte_i + 1] or 0
    local lo   = b % 16
    local hi   = math.floor(b / 16) % 16
    local px   = out_off + byte_i * 8
    -- low nibble = left pixel (even x), high nibble = right pixel (odd x)
    local cl = pal[lo]
    local ch = pal[hi]
    out[px + 1] = cl[1]; out[px + 2] = cl[2]; out[px + 3] = cl[3]; out[px + 4] = cl[4]
    out[px + 5] = ch[1]; out[px + 6] = ch[2]; out[px + 7] = ch[3]; out[px + 8] = ch[4]
  end
end

--- Decode GBA RGB555 palette bytes (32 bytes = 16 colors) to RGBA table.
-- Color 0 is forced fully transparent (GBA OBJ convention).
local function decode_palette(pal_bytes)
  local pal = {}
  for ci = 0, 15 do
    local v = pal_bytes[ci * 2 + 1] + pal_bytes[ci * 2 + 2] * 256
    local r  = (v % 32) * 8
    local g  = math.floor(v / 32) % 32 * 8
    local b  = math.floor(v / 1024) % 32 * 8
    local a  = (ci == 0) and 0 or 255
    pal[ci]  = { r, g, b, a }
  end
  return pal
end

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local function pal_ints(pal_bytes, off)
  off = off or 0
  local out = {}
  for ci = 0, 15 do
    out[ci + 1] = band((pal_bytes[off + ci * 2 + 1] or 0) + (pal_bytes[off + ci * 2 + 2] or 0) * 256, 0x7FFF)
  end
  return out
end

-- CRC-32 table for PNG chunk checksums
local crc_table = {}
for n = 0, 255 do
  local c = n
  for _ = 0, 7 do
    if band(c, 1) ~= 0 then
      c = bxor(0xEDB88320, rshift(c, 1))
    else
      c = rshift(c, 1)
    end
  end
  crc_table[n] = c
end

local function crc32(str)
  local c = 0xFFFFFFFF
  for i = 1, #str do
    local b = str:byte(i)
    c = bxor(crc_table[band(bxor(c, b), 0xFF)], rshift(c, 8))
  end
  return bxor(c, 0xFFFFFFFF)
end

local function adler32(str)
  local s1 = 1
  local s2 = 0
  for i = 1, #str do
    s1 = (s1 + str:byte(i)) % 65521
    s2 = (s2 + s1) % 65521
  end
  return s2 * 65536 + s1
end

local function u32be(n)
  n = band(n, 0xFFFFFFFF)
  return string.char(
    band(rshift(n, 24), 0xFF),
    band(rshift(n, 16), 0xFF),
    band(rshift(n, 8), 0xFF),
    band(n, 0xFF)
  )
end

local function u16le(n)
  return string.char(band(n, 0xFF), band(rshift(n, 8), 0xFF))
end

local function make_chunk(type_str, data)
  local crc = crc32(type_str .. data)
  return u32be(#data) .. type_str .. data .. u32be(crc)
end

local ffi
do
  local ok, mod = pcall(require, "ffi")
  if ok and mod and mod.new and mod.string then
    ffi = mod
  end
end

local static_raw_buf = nil
local static_raw_cap = 0
local function get_raw_buffer(size)
  if not ffi then return nil end
  if static_raw_cap < size then
    static_raw_cap = math.max(size + 1024, 65536)
    static_raw_buf = ffi.new("uint8_t[?]", static_raw_cap)
  end
  return static_raw_buf
end

--- Encode RGBA pixel array/string to PNG bytes.
local function encode_png(pixels, w, h)
  local raw_size = h * (1 + w * 4)
  local buf = get_raw_buffer(raw_size)
  local is_str = type(pixels) == "string"
  local raw_data

  if buf then
    local dest = 0
    for y = 0, h - 1 do
      buf[dest] = 0 -- Filter: None
      dest = dest + 1
      local src_base = y * w * 4
      if is_str then
        for x = 0, w * 4 - 1 do
          buf[dest] = pixels:byte(src_base + x + 1) or 0
          dest = dest + 1
        end
      else
        for x = 0, w * 4 - 1 do
          buf[dest] = pixels[src_base + x + 1] or 0
          dest = dest + 1
        end
      end
    end
    raw_data = ffi.string(buf, raw_size)
  else
    local raw_lines = {}
    for y = 0, h - 1 do
      local row = { string.char(0) } -- Filter type 0: None
      local start_idx = y * w * 4 + 1
      for x = 0, w - 1 do
        local idx = start_idx + x * 4
        if is_str then
          row[#row + 1] = pixels:sub(idx, idx + 3)
        else
          row[#row + 1] = string.char(pixels[idx] or 0, pixels[idx+1] or 0, pixels[idx+2] or 0, pixels[idx+3] or 0)
        end
      end
      raw_lines[#raw_lines + 1] = table.concat(row)
    end
    raw_data = table.concat(raw_lines)
  end

  local idat_data
  if love and love.data and love.data.compress then
    local ok, comp = pcall(love.data.compress, "string", "zlib", raw_data)
    if ok and comp then
      idat_data = comp
    end
  end

  if not idat_data then
    -- Deflate uncompressed blocks (max 65535 per block)
    local zlib_blocks = { string.char(0x78, 0x01) } -- ZLIB header
    local pos = 1
    local total_len = #raw_data
    while pos <= total_len do
      local chunk_len = math.min(total_len - pos + 1, 65535)
      local is_final = (pos + chunk_len > total_len) and 1 or 0
      zlib_blocks[#zlib_blocks + 1] = string.char(is_final)
      zlib_blocks[#zlib_blocks + 1] = u16le(chunk_len)
      zlib_blocks[#zlib_blocks + 1] = u16le(bxor(chunk_len, 0xFFFF))
      zlib_blocks[#zlib_blocks + 1] = raw_data:sub(pos, pos + chunk_len - 1)
      pos = pos + chunk_len
    end
    zlib_blocks[#zlib_blocks + 1] = u32be(adler32(raw_data))
    idat_data = table.concat(zlib_blocks)
  end

  -- PNG Signature + IHDR + IDAT + IEND
  local sig = "\137PNG\r\n\026\n"
  local ihdr = u32be(w) .. u32be(h) .. string.char(8, 6, 0, 0, 0)
  return sig .. make_chunk("IHDR", ihdr) .. make_chunk("IDAT", idat_data) .. make_chunk("IEND", "")
end

BattleAnimExtract.encodePng = encode_png

--- Extract all sprite sheets referenced in `usedTags` from gBattleAnimPicTable.
-- @param rom        Rom instance
-- @param cache      cachefs with :write(rel, bytes)
-- @param root       cache root prefix (e.g. "data/generated/gba")
-- @param usedTags   table of tag_name → true (only extract what's actually used)
-- @param tag_dims   optional table of tag_name → { w=N, h=N } from SpriteTemplates
-- @return tags metadata table: { TAG_NAME = { file=..., w=N, h=N, frameW=..., frameH=... }, ... }
local function extract_tag_sheets(rom, cache, root, usedTags, tag_dims)
  local anim  = Versions.BATTLE_ANIMS
  local tags  = {}
  if not (anim and anim.pic_table) then return tags end

  local pic_base = anim.pic_table
  local pal_base = anim.pal_table

  for idx = 0, anim.tag_count - 1 do
    local name = TAG_NAMES[idx]
    if not name then goto continue_tag end

    -- Read pic pointer (8-byte stride: ptr at +0, size at +4)
    local pic_gba = rom:u32(pic_base + idx * 8)
    local pic_off = rom:ptrOffset(pic_gba)
    if not (pic_off and rom:get(pic_off) == 0x10) then goto continue_tag end

    -- Read pal pointer
    local pal_gba = rom:u32(pal_base + idx * 8)
    local pal_off = rom:ptrOffset(pal_gba)
    if not pal_off then goto continue_tag end

    -- Decompress tile data
    local ok_lz, tile_bytes, _ = pcall(Lz77.decompress, function(j) return rom:get(j) end, pic_off)
    if not ok_lz or not tile_bytes then goto continue_tag end

    -- Decode palette (32 bytes uncompressed, or LZ77 compressed)
    local pal_bytes
    if rom:get(pal_off) == 0x10 then
      local ok_p, pb = pcall(Lz77.decompress, function(j) return rom:get(j) end, pal_off)
      if ok_p and pb then pal_bytes = pb end
    else
      pal_bytes = {}
      for pi = 0, 31 do pal_bytes[pi + 1] = rom:get(pal_off + pi) end
    end
    if not pal_bytes then goto continue_tag end

    local pal = decode_palette(pal_bytes)
    local palInts = pal_ints(pal_bytes)

    -- tile_bytes: raw 4bpp tile data. Each tile = 32 bytes = 8×8 pixels.
    -- Tiles are arranged in columns determined by frame width.
    local total_bytes = #tile_bytes
    local tile_count  = math.floor(total_bytes / 32)
    if tile_count <= 0 then goto continue_tag end

    local frame_w = tag_dims and tag_dims[name] and tag_dims[name].w
    local frame_h = tag_dims and tag_dims[name] and tag_dims[name].h
    local best_w = frame_w and math.max(1, math.floor(frame_w / 8))
    if not best_w then
      local widths = {1, 2, 4, 8, 16}
      best_w = 4
      for _, w in ipairs(widths) do
        if w * w <= tile_count then best_w = w end
      end
    end

    local img_w = best_w * 8
    local img_h = math.ceil(tile_count / best_w) * 8
    if img_h == 0 then img_h = img_w end

    -- Decode all tiles to RGBA
    local pixels = {}
    for pi = 1, img_w * img_h * 4 do pixels[pi] = 0 end
    local ipx = {}
    for pi = 1, img_w * img_h * 4 do ipx[pi] = (pi % 4 == 0) and 255 or 0 end

    local tiles_wide = math.floor(img_w / 8)
    for ti = 0, tile_count - 1 do
      local tx = ti % tiles_wide
      local ty = math.floor(ti / tiles_wide)
      -- Each tile's 8 rows map to img_w-stride RGBA pixels
      for row = 0, 7 do
        local byte_base = ti * 32 + row * 4
        for col = 0, 3 do
          local b   = tile_bytes[byte_base + col + 1] or 0
          local lo  = b % 16
          local hi  = math.floor(b / 16) % 16
          local px  = ((ty * 8 + row) * img_w + tx * 8 + col * 2)
          local cl  = pal[lo]
          local ch  = pal[hi]
          local base = px * 4 + 1
          pixels[base]   = cl[1]; pixels[base+1] = cl[2]
          pixels[base+2] = cl[3]; pixels[base+3] = cl[4]
          ipx[base], ipx[base + 1], ipx[base + 2] = lo * 17, lo * 17, lo * 17
          base = base + 4
          pixels[base]   = ch[1]; pixels[base+1] = ch[2]
          pixels[base+2] = ch[3]; pixels[base+3] = ch[4]
          ipx[base], ipx[base + 1], ipx[base + 2] = hi * 17, hi * 17, hi * 17
        end
      end
    end

    local png = encode_png(pixels, img_w, img_h)
    if png and #png > 0 then
      local rel = root .. "/tags/" .. name .. ".png"
      if cache and cache.write then
        cache:write(rel, png)
      end
      local ipng = encode_png(ipx, img_w, img_h)
      local idxRel = nil
      if ipng and #ipng > 0 and cache and cache.write then
        idxRel = "tags/" .. name .. ".idx.png"
        cache:write(root .. "/" .. idxRel, ipng)
      end
      tags[name] = {
        file   = "tags/" .. name .. ".png",
        idxFile = idxRel,
        pal    = palInts,
        w      = img_w,
        h      = img_h,
        frameW = frame_w or (best_w * 8),
        frameH = frame_h or (best_w * 8),
      }
    end

    ::continue_tag::
  end
  return tags
end

local function lz_at(rom, ptr)
  local off = rom:ptrOffset(ptr)
  if not (off and rom:get(off) == 0x10) then return nil end
  local ok, bytes = pcall(Lz77.decompress, function(j) return rom:get(j) end, off)
  if ok and bytes then return bytes end
  return nil
end

local function raw_at(rom, off, n)
  local out = {}
  for i = 0, n - 1 do out[i + 1] = rom:get(off + i) end
  return out
end

local function pal_bytes_at(rom, ptr)
  local b = lz_at(rom, ptr)
  if b then return b end
  local po = rom:ptrOffset(ptr)
  if not po then return nil end
  return raw_at(rom, po, 32)
end

local function tag_pal_ints(rom, idx)
  local anim = Versions.BATTLE_ANIMS
  if not (anim and anim.pal_table) then return nil end
  local b = pal_bytes_at(rom, rom:u32(anim.pal_table + idx * 8))
  if not (b and #b >= 32) then return nil end
  local out = {}
  for k = 0, math.floor(#b / 32) - 1 do
    local row = pal_ints(b, k * 32)
    for i = 1, 16 do out[k * 16 + i] = row[i] end
  end
  return out
end

local function decode_bg(tiles, map, palInts, opaque0)
  local entries = math.floor(#map / 2)
  local mw = (entries >= 2048) and 64 or 32
  local mh = math.max(1, math.min(32, math.floor(entries / mw)))
  local w, h = mw * 8, mh * 8
  local rgba, idx = {}, {}
  for i = 1, w * h * 4 do
    rgba[i] = 0
    idx[i] = (i % 4 == 0) and 255 or 0
  end
  local cols = {}
  for ci = 0, 15 do
    local c = palInts[ci + 1] or 0
    cols[ci] = { band(c, 31) * 8, band(rshift(c, 5), 31) * 8, band(rshift(c, 10), 31) * 8 }
  end
  local ntiles = math.floor(#tiles / 32)
  for e = 0, mw * mh - 1 do
    local v = (map[e * 2 + 1] or 0) + (map[e * 2 + 2] or 0) * 256
    local tile = v % 1024
    local hf = math.floor(v / 1024) % 2 == 1
    local vf = math.floor(v / 2048) % 2 == 1
    local sbx = math.floor(e / 1024)
    local inb = e % 1024
    local tx = (inb % 32) + sbx * 32
    local ty = math.floor(inb / 32)
    if tile < ntiles then
      for row = 0, 7 do
        for col = 0, 7 do
          local b = tiles[tile * 32 + row * 4 + math.floor(col / 2) + 1] or 0
          local ci = (col % 2 == 0) and (b % 16) or math.floor(b / 16)
          local dx = hf and (7 - col) or col
          local dy = vf and (7 - row) or row
          local o = ((ty * 8 + dy) * w + tx * 8 + dx) * 4 + 1
          local c = cols[ci]
          rgba[o], rgba[o + 1], rgba[o + 2] = c[1], c[2], c[3]
          rgba[o + 3] = (ci == 0 and not opaque0) and 0 or 255
          idx[o], idx[o + 1], idx[o + 2] = ci * 17, ci * 17, ci * 17
        end
      end
    end
  end
  return rgba, idx, w, h
end

local function write_bg(cache, root, key, tiles, map, palInts, opaque0)
  local rgba, idx, w, h = decode_bg(tiles, map, palInts, opaque0)
  local rel = "animbg/" .. key .. ".png"
  local irel = "animbg/" .. key .. ".idx.png"
  local png = encode_png(rgba, w, h)
  local ipng = encode_png(idx, w, h)
  if not (png and ipng and cache and cache.write) then return nil end
  cache:write(root .. "/" .. rel, png)
  cache:write(root .. "/" .. irel, ipng)
  return { file = rel, idxFile = irel, pal = palInts, w = w, h = h, opaque0 = opaque0 or nil }
end

-- pokefirered/src/graphics.c:705
local function extract_named_bgs(rom, cache, root, out)
  local anim = Versions.BATTLE_ANIMS
  local named = anim and anim.named_bgs
  if not named then return out end
  for key, e in pairs(named) do
    local tiles
    if e.gfx_raw then
      tiles = raw_at(rom, e.gfx_raw, e.gfx_size or 0x800)
    else
      tiles = lz_at(rom, e.gfx + 0x08000000)
    end
    local map = lz_at(rom, e.map + 0x08000000)
    local palInts
    if e.pal_tag then
      for i = 0, (anim.tag_count or 289) - 1 do
        if TAG_NAMES[i] == e.pal_tag then palInts = tag_pal_ints(rom, i) end
      end
    elseif e.pal_raw then
      palInts = pal_ints(raw_at(rom, e.pal_raw, 32))
    elseif e.pal_white1 then
      palInts = {}
      for ci = 1, 16 do palInts[ci] = 0 end
      palInts[2] = 0x7FFF
    elseif e.pal then
      local pb = lz_at(rom, e.pal + 0x08000000)
      palInts = pb and pal_ints(pb)
    end
    if tiles and map and palInts then
      out[key] = write_bg(cache, root, key, tiles, map, palInts, false)
    end
  end
  return out
end

-- pokefirered/src/data/battle_anim.h:1596
local function extract_anim_bgs(rom, cache, root)
  local anim = Versions.BATTLE_ANIMS
  local base = anim and (anim.bg_table or (anim.pal_table and anim.tag_count and anim.pal_table + anim.tag_count * 8))
  local count = anim and anim.bg_count or 27
  local out = {}
  if not base then return out end
  local done = {}
  for id = 0, count - 1 do
    local imgPtr = rom:u32(base + id * 12)
    local palPtr = rom:u32(base + id * 12 + 4)
    local mapPtr = rom:u32(base + id * 12 + 8)
    local key = string.format("%08X_%08X_%08X", imgPtr, palPtr, mapPtr)
    if done[key] then
      out[id] = done[key]
    else
      local tiles = lz_at(rom, imgPtr)
      local map = lz_at(rom, mapPtr)
      local palBytes = lz_at(rom, palPtr)
      if not palBytes then
        local po = rom:ptrOffset(palPtr)
        if po then
          palBytes = {}
          for pi = 0, 31 do palBytes[pi + 1] = rom:get(po + pi) end
        end
      end
      if tiles and map and palBytes and #palBytes >= 32 then
        local e = write_bg(cache, root, tostring(id), tiles, map, pal_ints(palBytes), true)
        if e then
          out[id] = e
          done[key] = e
        end
      end
    end
  end
  return out
end

-- pokefirered/src/battle_anim_utility_funcs.c:459
local function extract_stat_mask(rom, cache, root)
  local anim = Versions.BATTLE_ANIMS
  if not (anim and anim.stat_mask_gfx) then return nil end
  local tiles = lz_at(rom, anim.stat_mask_gfx + 0x08000000)
  if not tiles then return nil end
  local out = { files = {}, pals = {} }
  for k = 1, 8 do
    local pb = lz_at(rom, anim.stat_mask_pal + (k - 1) * 0x20 + 0x08000000)
    if not pb then return nil end
    local pal = decode_palette(pb)
    local row = {}
    for ci = 0, 15 do row[ci + 1] = { pal[ci][1], pal[ci][2], pal[ci][3] } end
    out.pals[k] = row
  end
  local ntiles = math.floor(#tiles / 32)
  for mi, off in ipairs({ anim.stat_mask_tilemap1, anim.stat_mask_tilemap2 }) do
    local map = lz_at(rom, off + 0x08000000)
    if not map then return nil end
    local pixels = {}
    for i = 1, 256 * 256 * 4 do pixels[i] = 0 end
    for e = 0, 1023 do
      local v = map[e * 2 + 1] + map[e * 2 + 2] * 256
      local tile = v % 1024
      local hf = math.floor(v / 1024) % 2 == 1
      local vf = math.floor(v / 2048) % 2 == 1
      local tx, ty = e % 32, math.floor(e / 32)
      if tile < ntiles then
        for r = 0, 7 do
          for c = 0, 7 do
            local b = tiles[tile * 32 + r * 4 + math.floor(c / 2) + 1] or 0
            local ci = (c % 2 == 0) and (b % 16) or math.floor(b / 16)
            local dx = hf and (7 - c) or c
            local dy = vf and (7 - r) or r
            local i = ((ty * 8 + dy) * 256 + tx * 8 + dx) * 4 + 1
            pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3] = ci * 16, ci * 16, ci * 16, (ci == 0) and 0 or 255
          end
        end
      end
    end
    local png = encode_png(pixels, 256, 256)
    if not png then return nil end
    local rel = "statmask/" .. mi .. ".png"
    cache:write(root .. "/" .. rel, png)
    out.files[mi] = rel
  end
  return out
end

-- ── Lua serializer ────────────────────────────────────────────────────────

local function serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "nil"     then return "nil" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number"  then return tostring(v) end
  if t == "string"  then return string.format("%q", v) end
  if t == "table" then
    local n, isArr, count = #v, true, 0
    for k in pairs(v) do
      count = count + 1
      if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then isArr = false end
    end
    if isArr and n > 0 then
      local parts = {"{"}
      for i = 1, n do
        parts[#parts+1] = "\n"..indent.."  "..serialize(v[i], indent.."  ")..(i < n and "," or "")
      end
      parts[#parts+1] = "\n"..indent.."}"
      return table.concat(parts)
    end
    local keys, parts = {}, {"{"}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta == tb then
        if ta == "number" then return a < b end
        return tostring(a) < tostring(b)
      end
      return ta < tb
    end)
    for _, k in ipairs(keys) do
      local key = (type(k)=="string" and k:match("^[%a_][%w_]*$")) and k or ("["..serialize(k).."]")
      parts[#parts+1] = "\n"..indent.."  "..key.." = "..serialize(v[k], indent.."  ")..(k ~= keys[#keys] and "," or "")
    end
    parts[#parts+1] = "\n"..indent.."}"
    return table.concat(parts)
  end
  return "nil"
end

-- ── Generic fallback script (used when no pack is available) ──────────────

local GENERIC = {
  { op = "loadspritegfx", tag = "IMPACT", tag_idx = 135 },
  { op = "monbg", battler = "target" },
  { op = "createsprite", tag = "IMPACT", noGfx = nil, w = 32, h = 32,
    animBattler = "attacker", subpriority = 2,
    args = { 0, 0, -1, 2 } },  -- args[3]=-1 → from HorizontalLunge noGfx template
  { op = "createsprite", tag = "IMPACT", w = 32, h = 32,
    animBattler = "attacker", subpriority = 2, args = { 0, 0, 1, 2 } },
  { op = "createvisualtask", task = "AnimTask_ShakeMon", priority = 2,
    args = { 1, 3, 0, 6, 1 } },
  { op = "waitforvisualfinish" },
  { op = "clearmonbg", battler = "target" },
  { op = "blendoff" },
  { op = "end" },
}

-- ── Public API ────────────────────────────────────────────────────────────

function BattleAnimExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or "data/generated/gba") .. "/" .. BattleAnimExtract.CACHE_SUB
  local path = root .. "/pack.lua"
  if cache and cache.exists and cache:exists(path) then return true end
  if cache and cache.read  and cache:read(path)   then return true end
  return false
end

--- Main extraction entry point.
-- @param rom    Rom instance (required for ROM-native extraction)
-- @param cache  cache object with :write(rel, bytes) method
-- @param opts   { force=bool, cacheRoot=string, progressCb=function }
function BattleAnimExtract.run(rom, cache, opts)
  opts      = opts or {}
  local root = (opts.cacheRoot or "data/generated/gba") .. "/" .. BattleAnimExtract.CACHE_SUB

  -- Skip if already extracted and not forced
  if not opts.force and BattleAnimExtract.ready(cache, opts.cacheRoot or "data/generated/gba") then
    return {
      path        = root .. "/pack.lua",
      moveCount   = V.move_count or 355,
      tagCount    = 0,
      version     = BattleAnimExtract.FORMAT_VERSION,
      skipped     = true,
    }
  end

  local anim = Versions.BATTLE_ANIMS
  if not (rom and anim and anim.moves_table) then
    -- No ROM — write generic fallback
    local pack = {
      version  = BattleAnimExtract.FORMAT_VERSION,
      moves    = {},
      labels   = {},
      tags     = {},
    }
    for id = 0, (V.move_count or 355) - 1 do
      pack.moves[id] = GENERIC
    end
    local lua = "return " .. serialize(pack) .. "\n"
    if cache and cache.write then cache:write(root .. "/pack.lua", lua) end
    print("[battle_anim_extract] no ROM — wrote generic fallback")
    return { path = root .. "/pack.lua", moveCount = 0, tagCount = 0,
             version = BattleAnimExtract.FORMAT_VERSION }
  end

  -- ── Step 1: Decode all move scripts ──────────────────────────────────
  local visited  = {}
  local labels   = {}   -- offset-string → IR ops list
  local moves    = {}   -- [id] → IR ops list
  local usedTags = {}   -- tag_name → true
  local tagDims  = {}   -- tag_name → { w=N, h=N }

  local moves_table = anim.moves_table
  local move_count  = anim.move_count or 355

  print("[battle_anim_extract] decoding " .. move_count .. " move scripts from ROM...")
  for id = 0, move_count - 1 do
    local gba_ptr = rom:u32(moves_table + id * 4)
    local off     = rom:ptrOffset(gba_ptr)
    if off then
      local script = decode_script(rom, off, visited, labels, tagDims)
      moves[id] = script
      -- Collect used tags
      for _, op in ipairs(script) do
        if op.tag and op.tag ~= "" then
          usedTags[op.tag] = true
        end
      end
    else
      moves[id] = GENERIC
    end
  end

  local tag_count = 0
  local function decode_table(base, count, names)
    local out, outNames = {}, {}
    if not base then return out, outNames end
    for idx = 0, count - 1 do
      local off = rom:ptrOffset(rom:u32(base + idx * 4))
      if off then
        out[idx] = decode_script(rom, off, visited, labels, tagDims)
      else
        out[idx] = GENERIC
      end
      outNames[idx] = names and names[idx] or tostring(idx)
    end
    return out, outNames
  end

  local general, generalNames = decode_table(anim.general_table, anim.general_count or 28, Versions.BATTLE_ANIM_GENERAL_NAMES)
  local special, specialNames = decode_table(anim.special_table, anim.special_count or 7, Versions.BATTLE_ANIM_SPECIAL_NAMES)
  local status, statusNames   = decode_table(anim.status_table, anim.status_count or 9, Versions.BATTLE_ANIM_STATUS_NAMES)

  -- Collect tags from all label scripts too
  for _, script in pairs(labels) do
    for _, op in ipairs(script) do
      if op.tag and op.tag ~= "" then usedTags[op.tag] = true end
    end
  end

  for _ in pairs(usedTags) do tag_count = tag_count + 1 end
  print(string.format("[battle_anim_extract] %d moves decoded, %d unique tags", move_count, tag_count))

  -- ── Step 2: Extract sprite sheets ───────────────────────────────────
  local tagMeta = {}
  if cache then
    print("[battle_anim_extract] extracting " .. tag_count .. " sprite sheets...")
    tagMeta = extract_tag_sheets(rom, {
      write = function(_, rel, bytes) return cache:write(rel, bytes) end,
    }, root, usedTags, tagDims)
    local extracted = 0
    for _ in pairs(tagMeta) do extracted = extracted + 1 end
    print(string.format("[battle_anim_extract] wrote %d tag PNGs", extracted))
  end
  local animBgs = cache and extract_anim_bgs(rom, cache, root) or {}
  if cache then extract_named_bgs(rom, cache, root, animBgs) end
  local tagPals = {}
  for i = 0, (anim.tag_count or 289) - 1 do
    local nm = TAG_NAMES[i]
    if nm then tagPals[nm] = tag_pal_ints(rom, i) end
  end
  local bgPals = {}
  if anim.muddy_water_pal then
    local pb = lz_at(rom, anim.muddy_water_pal + 0x08000000)
    if pb then bgPals.MUDDY_WATER = pal_ints(pb) end
  end
  if cache and anim.smokescreen_gfx and anim.smokescreen_pal then
    local tb = lz_at(rom, anim.smokescreen_gfx + 0x08000000)
    local pb = lz_at(rom, anim.smokescreen_pal + 0x08000000)
    if tb and pb then
      local pal = decode_palette(pb)
      local palInts = pal_ints(pb)
      local ntiles = math.floor(#tb / 32)
      local w, h = 16, math.ceil(ntiles / 2) * 8
      local px, ipx = {}, {}
      for i = 1, w * h * 4 do
        px[i] = 0
        ipx[i] = (i % 4 == 0) and 255 or 0
      end
      for ti = 0, ntiles - 1 do
        local tx, ty = ti % 2, math.floor(ti / 2)
        for row = 0, 7 do
          for col = 0, 7 do
            local b = tb[ti * 32 + row * 4 + math.floor(col / 2) + 1] or 0
            local ci = (col % 2 == 0) and (b % 16) or math.floor(b / 16)
            local o = ((ty * 8 + row) * w + tx * 8 + col) * 4 + 1
            local c = pal[ci]
            px[o], px[o + 1], px[o + 2], px[o + 3] = c[1], c[2], c[3], c[4]
            ipx[o], ipx[o + 1], ipx[o + 2] = ci * 17, ci * 17, ci * 17
          end
        end
      end
      local png, ipng = encode_png(px, w, h), encode_png(ipx, w, h)
      if png and ipng then
        cache:write(root .. "/tags/TAG_SMOKESCREEN.png", png)
        cache:write(root .. "/tags/TAG_SMOKESCREEN.idx.png", ipng)
        tagMeta.TAG_SMOKESCREEN = { file = "tags/TAG_SMOKESCREEN.png", idxFile = "tags/TAG_SMOKESCREEN.idx.png",
          pal = palInts, w = w, h = h, frameW = 16, frameH = 16 }
        tagPals.TAG_SMOKESCREEN = palInts
      end
    end
  end
  if cache and anim.substitute_pal then
    local palBytes = lz_at(rom, anim.substitute_pal + 0x08000000)
    if palBytes then
      local pal = decode_palette(palBytes)
      for key, off in pairs({ SUBSTITUTE_DOLL_FRONT = anim.substitute_front, SUBSTITUTE_DOLL_BACK = anim.substitute_back }) do
        local tb = off and lz_at(rom, off + 0x08000000)
        if tb and #tb >= 2048 then
          local pixels = {}
          for i = 1, 64 * 64 * 4 do pixels[i] = 0 end
          for ti = 0, 63 do
            local tx, ty = ti % 8, math.floor(ti / 8)
            for row = 0, 7 do
              for col = 0, 3 do
                local b = tb[ti * 32 + row * 4 + col + 1] or 0
                local px = ((ty * 8 + row) * 64 + tx * 8 + col * 2) * 4 + 1
                local cl, ch = pal[b % 16], pal[math.floor(b / 16) % 16]
                pixels[px], pixels[px + 1], pixels[px + 2], pixels[px + 3] = cl[1], cl[2], cl[3], cl[4]
                pixels[px + 4], pixels[px + 5], pixels[px + 6], pixels[px + 7] = ch[1], ch[2], ch[3], ch[4]
              end
            end
          end
          local png = encode_png(pixels, 64, 64)
          if png and #png > 0 then
            cache:write(root .. "/tags/" .. key .. ".png", png)
            tagMeta[key] = { file = "tags/" .. key .. ".png", w = 64, h = 64, frameW = 64, frameH = 64 }
          end
        end
      end
    end
  end

  local statMask = cache and extract_stat_mask(rom, cache, root) or nil

  -- ── Step 3: Serialize pack ──────────────────────────────────────────
  local pack = {
    version = BattleAnimExtract.FORMAT_VERSION,
    moves   = moves,
    labels  = labels,
    tags    = tagMeta,
    general = general,
    special = special,
    status  = status,
    generalNames = generalNames,
    specialNames = specialNames,
    statusNames  = statusNames,
    animBgs      = animBgs,
    tagPals      = tagPals,
    bgPals       = bgPals,
    statMask     = statMask,
  }

  local lua = "return " .. serialize(pack) .. "\n"
  if cache and cache.write then
    cache:write(root .. "/pack.lua", lua)
  elseif opts.outPath then
    local f = assert(io.open(opts.outPath, "wb"))
    f:write(lua)
    f:close()
  end

  return {
    path      = root .. "/pack.lua",
    moveCount = move_count,
    tagCount  = tag_count,
    version   = BattleAnimExtract.FORMAT_VERSION,
  }
end

return BattleAnimExtract
