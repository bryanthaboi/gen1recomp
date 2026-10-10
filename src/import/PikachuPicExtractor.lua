local ImageWriter = require("src.import.ImageWriter")
local Rom = require("src.import.Rom")

local PikachuPicExtractor = {}

local DIR = "assets/generated/pikachu/"

-- constants/script_constants.asm:3
local BUBBLES = {
  [0] = "EXCLAMATION_BUBBLE", "QUESTION_BUBBLE", "SMILE_BUBBLE",
  "SKULL_BUBBLE", "HEART_BUBBLE", "BOLT_BUBBLE", "ZZZ_BUBBLE", "FISH_BUBBLE",
}

-- engine/pikachu/pikachu_emotions.asm:229
local EMOTION_COUNT = 33
-- engine/pikachu/pikachu_pic_animation.asm:151
local PIC_COUNT = 0x1d
-- engine/pikachu/pikachu_pic_animation.asm:362
local FRAMESET_COUNT = 0x23
-- engine/pikachu/pikachu_movement.asm:1048
local SINE_COUNT = 32
-- engine/pikachu/pikachu_pic_animation.asm:738
local PIC_VTILE_BASE = 0x80
local PIC_SIZE = 5

function PikachuPicExtractor.symbolNames()
  return {
    "PikachuEmotionTable", "PikachuMovementDatabase", "SineWave_3f",
    "PikaPicAnimPointers", "PikaPicAnimBGFramesPointers",
    "PikaPicTilemapPointers", "PikaPicAnimGFXHeaders",
    "PikachuMoodLookupTable", "PikaPicAnimationScriptPointerLookupTable",
    "MapSpecificPikachuExpression.Emotions", "IsPlayerPikachuAsleepInParty",
    "PikaPicAnimThunderboltPals",
  }
end

-- engine/pikachu/pikachu_movement.asm:57
local function decodeMovement(rom, bank, address, database)
  local out = {}
  for _ = 1, 64 do
    local cmd = rom:byte(bank, address)
    address = address + 1
    if cmd == 0x3f then return out end
    local row = database.address + cmd * 4
    local f1 = rom:byte(database.bank, row)
    local p1 = rom:byte(database.bank, row + 1)
    if p1 == 0x80 then
      p1 = rom:byte(bank, address)
      address = address + 1
    end
    local f2 = rom:byte(database.bank, row + 2)
    local p2 = rom:byte(database.bank, row + 3)
    if p2 == 0x80 then
      p2 = rom:byte(bank, address)
      address = address + 1
    end
    out[#out + 1] = { cmd = cmd, func1 = f1, param1 = p1, func2 = f2, param2 = p2 }
  end
  error(("unterminated pikachu movement at %02X:%04X"):format(bank, address))
end

-- engine/pikachu/pikachu_emotions.asm:26
local function decodeEmotion(rom, bank, address, database)
  local out = {}
  for _ = 1, 64 do
    local op = rom:byte(bank, address)
    address = address + 1
    if op == 0xff then return out end
    local arg = rom:byte(bank, address)
    if op == 1 then
      out[#out + 1] = { op = "text", pointer = rom:word(bank, address) }
      address = address + 2
    elseif op == 2 then
      address = address + 1
      -- macros/pikachu.asm:172
      out[#out + 1] = { op = "pcm", cry = arg ~= 0xff and arg + 1 or nil }
    elseif op == 3 then
      address = address + 1
      out[#out + 1] = { op = "bubble", bubble = assert(BUBBLES[arg], "bubble " .. arg) }
    elseif op == 4 then
      out[#out + 1] = { op = "move",
        movement = decodeMovement(rom, bank, rom:word(bank, address), database) }
      address = address + 2
    elseif op == 5 then
      address = address + 1
      out[#out + 1] = { op = "pikapic", script = arg }
    elseif op == 6 then
      address = address + 1
      out[#out + 1] = { op = "subcmd", sub = arg }
    elseif op == 7 then
      address = address + 1
      out[#out + 1] = { op = "delay", frames = arg }
    elseif op == 9 then
      out[#out + 1] = { op = "turnaway" }
    else
      assert(op == 0 or op == 8 or op == 10, ("emotion command %02X"):format(op))
    end
  end
  error(("unterminated pikachu emotion at %02X:%04X"):format(bank, address))
end

-- engine/pikachu/pikachu_pic_animation.asm:499
local function decodeScript(rom, bank, address)
  local script = { gfx = {}, objects = {}, passes = 0 }
  for _ = 1, 64 do
    local op = rom:byte(bank, address)
    address = address + 1
    local function arg()
      local v = rom:byte(bank, address)
      address = address + 1
      return v
    end
    if op == 0x01 then
      script.delay = arg()
    elseif op == 0x02 then
      script.gfx[#script.gfx + 1] = arg()
    elseif op == 0x03 then
      local frameset = arg()
      arg()
      local vtile, x, y = arg(), arg(), arg()
      script.objects[#script.objects + 1] = {
        frameset = frameset, vtile = vtile, y = y, x = x,
      }
    elseif op == 0x06 then
      arg()
    elseif op == 0x09 then
      return script
    elseif op == 0x0a then
      script.dur = rom:word(bank, address)
      address = address + 2
    elseif op == 0x0b then
      local cry = arg()
      if cry ~= 0xff and not script.cry then script.cry = cry + 1 end
    elseif op == 0x0c then
      script.thunderbolt = true
    elseif op == 0x0d then
      script.passes = script.passes + 1
    elseif op == 0x0e then
      return script
    end
  end
  error(("unterminated pikapic script at %02X:%04X"):format(bank, address))
end

-- data/pikachu/pikachu_pic_objects.asm:44
local function decodeFrameset(rom, base, index)
  local pointer = rom:word(base.bank, base.address + index * 2)
  local frames = {}
  for i = 0, 63 do
    local tilemap = rom:byte(base.bank, pointer + i * 2)
    if tilemap == 0xe0 then return frames end
    frames[#frames + 1] = {
      tilemap = tilemap, dur = rom:byte(base.bank, pointer + i * 2 + 1),
    }
  end
  error(("unterminated pikapic frameset %d"):format(index))
end

-- engine/pikachu/pikachu_pic_animation.asm:412
local function decodeTilemap(rom, base, index)
  local pointer = rom:word(base.bank, base.address + index * 2)
  local rows = rom:byte(base.bank, pointer)
  local cols = rom:byte(base.bank, pointer + 1)
  local cells = rom:bytes(base.bank, pointer + 2, rows * cols)
  return { rows = rows, cols = cols, cells = cells }
end

-- engine/pikachu/pikachu_pic_animation.asm:610
local function loadGfx(ex, headers, id)
  local row = headers.address + id * 4
  local size = ex.rom:byte(headers.bank, row)
  local bank = ex.rom:byte(headers.bank, row + 1)
  local address = ex.rom:word(headers.bank, row + 2)
  if size == 0xff then
    -- engine/pikachu/pikachu_pic_animation.asm:658
    local raw, width = Rom.decompressPic(
      ex.rom:bytes(bank, address, 0x8000 - address))
    assert(width == PIC_SIZE, "pikapic is not 5x5")
    local image = ImageWriter.decode2bpp(raw, width * 8, width * 8)
    return width * width, function(k)
      return image, math.floor(k / width) * 8, k % width * 8
    end
  end
  local image = ImageWriter.decode2bpp(
    ex.rom:bytes(bank, address, size * 16), size * 8, 8)
  return size, function(k) return image, k * 8, 0 end
end

local function paint(canvas, vram, object, tilemap)
  for r = 0, tilemap.rows - 1 do
    for c = 0, tilemap.cols - 1 do
      local cell = tilemap.cells[r * tilemap.cols + c + 1]
      local y, x = object.y + r, object.x + c
      if cell ~= 0xff and y < PIC_SIZE and x < PIC_SIZE then
        local tile = vram[(cell + object.vtile) % 0x100]
        assert(tile, ("pikapic tile $%02X is not loaded"):format(cell + object.vtile))
        ImageWriter.blit(canvas, tile[1], x * 8, y * 8, tile[2], tile[3], 8, 8)
      end
    end
  end
end

function PikachuPicExtractor.extract(ex)
  local rom = ex.rom
  local emotionTable = ex:symbol("PikachuEmotionTable")
  local database = ex:symbol("PikachuMovementDatabase")
  local picPointers = ex:symbol("PikaPicAnimPointers")
  local framesets = ex:symbol("PikaPicAnimBGFramesPointers")
  local tilemaps = ex:symbol("PikaPicTilemapPointers")
  local headers = ex:symbol("PikaPicAnimGFXHeaders")

  local data = { emotions = {}, pics = {} }
  for i = 0, EMOTION_COUNT - 1 do
    data.emotions[i] = decodeEmotion(rom, emotionTable.bank,
      rom:word(emotionTable.bank, emotionTable.address + i * 2), database)
  end

  local sine = ex:symbol("SineWave_3f")
  data.sine = {}
  for i = 0, SINE_COUNT - 1 do
    data.sine[i + 1] = rom:word(sine.bank, sine.address + i * 2)
  end

  local mood = ex:symbol("PikachuMoodLookupTable")
  data.moodColumns = {}
  for i = 0, 15 do
    local limit = rom:byte(mood.bank, mood.address + i * 2)
    data.moodColumns[i + 1] = {
      limit = limit, column = rom:byte(mood.bank, mood.address + i * 2 + 1),
    }
    if limit == 0xff then break end
  end
  local columns = 0
  for _, m in ipairs(data.moodColumns) do columns = math.max(columns, m.column) end
  local matrix = ex:symbol("PikaPicAnimationScriptPointerLookupTable")
  data.moodRows = {}
  for i = 0, 15 do
    local row = matrix.address + i * (columns + 1)
    local entry = { limit = rom:byte(matrix.bank, row) }
    for c = 1, columns do entry[c] = rom:byte(matrix.bank, row + c) end
    data.moodRows[i + 1] = entry
    if entry.limit == 0xff then break end
  end

  local modifiers = ex:symbol("MapSpecificPikachuExpression.Emotions")
  local modifiersEnd = ex:symbol("IsPlayerPikachuAsleepInParty")
  data.modifierEmotions = rom:bytes(modifiers.bank, modifiers.address,
    modifiersEnd.address - modifiers.address)

  local pals = ex:symbol("PikaPicAnimThunderboltPals")
  data.thunderboltPals = {}
  for i = 0, 63 do
    local frames = rom:byte(pals.bank, pals.address + i * 2)
    if frames == 0xff then break end
    data.thunderboltPals[i + 1] = {
      frames = frames, bgp = rom:byte(pals.bank, pals.address + i * 2 + 1),
    }
  end

  for id = 1, PIC_COUNT - 1 do
    local script = decodeScript(rom, picPointers.bank,
      rom:word(picPointers.bank, picPointers.address + id * 2))
    local vram, nextTile = {}, PIC_VTILE_BASE
    for _, gfx in ipairs(script.gfx) do
      local size, tileAt = loadGfx(ex, headers, gfx)
      for k = 0, size - 1 do
        local image, sx, sy = tileAt(k)
        vram[nextTile + k] = { image, sx, sy }
      end
      nextTile = nextTile + size
    end
    assert(#script.objects == 2, "pikapic script " .. id .. " object count")
    local baseObject, overlay = script.objects[1], script.objects[2]
    local baseFrames = decodeFrameset(rom, framesets, baseObject.frameset)
    assert(#baseFrames == 1 and baseFrames[1].dur == 0,
      "pikapic script " .. id .. " base frameset is not static")
    local baseMap = decodeTilemap(rom, tilemaps, baseFrames[1].tilemap)

    local function compose(overlayMap)
      local canvas = ImageWriter.blank(PIC_SIZE * 8, PIC_SIZE * 8, 1, 1, 1, 1)
      paint(canvas, vram, baseObject, baseMap)
      if overlayMap then paint(canvas, vram, overlay, overlayMap) end
      return ImageWriter.matteColor0(canvas)
    end

    local name = "pikapic_" .. id
    ex:save(compose(nil), "pikachu/" .. name .. ".png")
    local pic = {
      dur = script.dur, cry = script.cry, passes = script.passes,
      image = DIR .. name .. ".png", frames = {},
    }
    if script.thunderbolt then pic.boltDelay = script.delay or 0 end
    local written = {}
    assert(overlay.frameset < FRAMESET_COUNT, "pikapic frameset out of range")
    for i, f in ipairs(decodeFrameset(rom, framesets, overlay.frameset)) do
      local frame = { tilemap = f.tilemap, dur = f.dur }
      if f.tilemap ~= 0 then
        local path = name .. "_" .. f.tilemap .. ".png"
        if not written[path] then
          ex:save(compose(decodeTilemap(rom, tilemaps, f.tilemap)), "pikachu/" .. path)
          written[path] = true
        end
        frame.image = DIR .. path
      end
      pic.frames[i] = frame
    end
    data.pics[id] = pic
  end
  data.pics[0] = data.pics[1]
  return data
end

return PikachuPicExtractor
