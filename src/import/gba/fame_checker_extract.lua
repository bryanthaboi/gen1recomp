-- src/fame_checker.c:119, src/graphics.c:1230

local Versions = require("src.import.gba.versions")
local BgBake = require("src.import.gba.bg_bake")
local TextIR = require("src.core.game3.scripting.text_ir")

local FameCheckerExtract = {}

FameCheckerExtract.CACHE_SUB = "fame_checker"
FameCheckerExtract.MANIFEST_VERSION = 1

local PORTRAIT = 64
local BG_W, BG_H = 240, 160

-- src/fame_checker.c:1342 CreatePersonPicSprite
local OWN_ART = {
  { person = 0, gfx = "FAME_OAK_GFX", pal = "FAME_OAK_PAL" },
  { person = 1, gfx = "FAME_DAISY_GFX", pal = "FAME_DAISY_PAL" },
  { person = 13, gfx = "FAME_BILL_GFX", pal = "FAME_BILL_PAL" },
  { person = 14, gfx = "FAME_FUJI_GFX", pal = "FAME_FUJI_PAL" },
}

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function rom_bytes(rom, off, len)
  local out = {}
  for i = 1, len do out[i] = rom:get(off + i - 1) end
  out._len = len
  return out
end

-- src/fame_checker.c:209
local function decode_text(rom, off)
  local bytes = {}
  for i = 0, 1023 do
    local b = rom:get(off + i)
    bytes[#bytes + 1] = b
    if b == 0xFF then break end
  end
  local out = {}
  for _, seg in ipairs(TextIR.decode(bytes)) do
    if seg.t == "nl" then
      out[#out + 1] = "\n"
    elseif seg.t == "para" then
      out[#out + 1] = "\\p"
    elseif seg.t == "scroll" then
      out[#out + 1] = "\\l"
    elseif seg.t == "player" then
      out[#out + 1] = "{PLAYER}"
    elseif seg.t == "rival" then
      out[#out + 1] = "{RIVAL}"
    elseif seg.t == "strvar" then
      out[#out + 1] = "{STR_VAR_" .. tostring(seg.n) .. "}"
    elseif seg.t == "text" then
      out[#out + 1] = seg.s
    end
  end
  return table.concat(out)
end

local function pointer(rom, off)
  local p = rom:ptrOffset(rom:u32(off))
  if not p or p >= rom.size then
    error(string.format("fame_checker: bad pointer at 0x%X", off))
  end
  return p
end

local function quote(s)
  local lit = string.format("%q", s)
  return (lit:gsub("\\\n", "\\n"))
end

-- src/fame_checker.c:664
local function bake_page(rom)
  local gfx = rom_bytes(rom, Versions.FAME_BG_GFX,
    Versions.FAME_BG3_TILEMAP - Versions.FAME_BG_GFX)
  local banks = BgBake.loadPalBanks(rom_bytes(rom, Versions.FAME_BG_PAL, 64), 2)
  local bg3 = rom_bytes(rom, Versions.FAME_BG3_TILEMAP, 2048)
  local bg2 = rom_bytes(rom, Versions.FAME_BG2_TILEMAP, 2048)
  local base = BgBake.bakeBgRgba(gfx, banks, bg3, BG_W, BG_H)
  local over = BgBake.bakeRegionRgba(gfx, banks, bg2, BG_W, BG_H, { alpha0 = true })
  local chunks = {}
  for i = 1, BG_W * BG_H do
    local o = (i - 1) * 4
    if over:byte(o + 4) > 0 then
      chunks[i] = over:sub(o + 1, o + 4)
    else
      chunks[i] = base:sub(o + 1, o + 4)
    end
  end
  return table.concat(chunks)
end

local function bake_sprite(rom, gfxOff, palOff, w, h)
  local tiles = (w / 8) * (h / 8)
  local gfx = rom_bytes(rom, gfxOff, tiles * 32)
  local bank = BgBake.loadPalBanks(rom_bytes(rom, palOff, 32), 1)[0]
  return BgBake.bakeSpriteRgba(gfx, bank, 0, w, h, false, false)
end

local function write_pack(rom)
  local persons = Versions.FAME_PERSON_COUNT
  local slots = Versions.FAME_FLAVOR_TEXT_COUNT
  local lines = { "return {", "  version = 1," }

  lines[#lines + 1] = "  listNames = {"
  for i, off in ipairs(Versions.FAME_NONTRAINER_NAME_PTRS) do
    local person = ({ 0, 1, 13, 14 })[i]
    lines[#lines + 1] = string.format("    [%d] = %s,", person, quote(decode_text(rom, off)))
  end
  lines[#lines + 1] = "  },"

  lines[#lines + 1] = "  names = {"
  for p = 0, persons - 1 do
    local text = decode_text(rom, pointer(rom, Versions.FAME_NAME_QUOTE_PTRS + p * 4))
    lines[#lines + 1] = string.format("    [%d] = %s,", p, quote(text))
  end
  lines[#lines + 1] = "  },"

  lines[#lines + 1] = "  quotes = {"
  for p = 0, persons - 1 do
    local off = Versions.FAME_NAME_QUOTE_PTRS + (persons + p) * 4
    lines[#lines + 1] = string.format("    [%d] = %s,", p, quote(decode_text(rom, pointer(rom, off))))
  end
  lines[#lines + 1] = "  },"

  local tables = {
    { "flavorText", Versions.FAME_FLAVOR_TEXT_PTRS },
    { "originLocation", Versions.FAME_ORIGIN_LOCATION_PTRS },
    { "originObject", Versions.FAME_ORIGIN_OBJECT_PTRS },
  }
  for _, row in ipairs(tables) do
    lines[#lines + 1] = "  " .. row[1] .. " = {"
    for p = 0, persons - 1 do
      local cells = {}
      for s = 0, slots - 1 do
        local off = row[2] + (p * slots + s) * 4
        cells[#cells + 1] = string.format("[%d] = %s", s, quote(decode_text(rom, pointer(rom, off))))
      end
      lines[#lines + 1] = string.format("    [%d] = { %s },", p, table.concat(cells, ", "))
    end
    lines[#lines + 1] = "  },"
  end

  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function FameCheckerExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. FameCheckerExtract.CACHE_SUB

  cache:write(root .. "/bg.rgba", bake_page(rom))

  for _, row in ipairs(OWN_ART) do
    local rgba = bake_sprite(rom, Versions[row.gfx], Versions[row.pal], PORTRAIT, PORTRAIT)
    cache:write(string.format("%s/%d.rgba", root, row.person), rgba)
  end

  -- src/fame_checker.c:429
  cache:write(root .. "/cursor.rgba",
    bake_sprite(rom, Versions.FAME_CURSOR_GFX, Versions.FAME_CURSOR_PAL, 32, 32))
  cache:write(root .. "/question_mark.rgba",
    bake_sprite(rom, Versions.FAME_QUESTION_GFX, Versions.FAME_CURSOR_PAL, 16, 32))

  cache:write(root .. "/pack.lua", write_pack(rom))

  -- src/fame_checker.c:1375 LoadPalette(sSilhouettePalette, OBJ_PLTT_ID(PERSON_PAL_NUM))
  local silhouette = BgBake.loadPalBanks(rom_bytes(rom, Versions.FAME_SILHOUETTE_PAL, 32), 1)[0]
  local pal = {}
  for i = 0, 15 do
    pal[#pal + 1] = string.char(BgBake.bgr555ToRgb8(silhouette[i] or 0))
  end
  cache:write(root .. "/silhouette.pal", table.concat(pal))

  local picIdxs = {}
  for i = 0, Versions.FAME_PERSON_COUNT - 1 do
    picIdxs[#picIdxs + 1] = tostring(rom:get(Versions.FAME_TRAINER_PIC_IDXS + i))
  end
  cache:write(root .. "/manifest.lua", string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  portrait = %d,
  persons = %d,
  flavorTexts = %d,
  trainerPic = { %s },
}
]], FameCheckerExtract.MANIFEST_VERSION, BG_W, BG_H, PORTRAIT,
    Versions.FAME_PERSON_COUNT, Versions.FAME_FLAVOR_TEXT_COUNT,
    table.concat(picIdxs, ", ")))

  print(string.format("[fame_checker_extract] page %dx%d, %d portraits, %d persons -> %s",
    BG_W, BG_H, #OWN_ART, Versions.FAME_PERSON_COUNT, root))
  return { root = root, portraits = #OWN_ART }
end

function FameCheckerExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. FameCheckerExtract.CACHE_SUB
  if not (cache and cache.exists) then return false end
  for _, rel in ipairs({ "bg.rgba", "0.rgba", "1.rgba", "13.rgba", "14.rgba",
    "cursor.rgba", "question_mark.rgba", "silhouette.pal", "pack.lua", "manifest.lua" }) do
    if not cache:exists(root .. "/" .. rel) then return false end
  end
  return true
end

return FameCheckerExtract
