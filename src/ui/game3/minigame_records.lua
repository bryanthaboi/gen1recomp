-- pokefirered/src/berry_crush.c:3095, src/pokemon_jump.c:4509, src/dodrio_berry_picking.c:2956

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")

local Records = {}

Records.ID = "minigame_records"

Records.KIND = {
  BERRY_CRUSH = "berry_crush",
  POKEMON_JUMP = "pokemon_jump",
  DODRIO = "dodrio",
}

-- pokefirered/src/berry_crush.c:545
-- pokefirered/src/pokemon_jump.c:4493
-- pokefirered/src/dodrio_berry_picking.c:2935
local TEMPLATES = {
  berry_crush = Window.template(3, 4, 24, 13),
  pokemon_jump = Window.template(1, 1, 28, 9),
  dodrio = Window.template(1, 1, 28, 11),
}

-- pokefirered/src/berry_crush.c:635
Records.PRESSING_SPEED_CONVERSION = {
  50000000, 25000000, 12500000, 6250000, 3125000, 1562500, 781250, 390625,
}

-- pokefirered/src/berry_crush.c:540
local COLOR_BLUE = {
  fg = FrlgFont.STDPAL[8], shadow = FrlgFont.STDPAL[9], bg = FrlgFont.STDPAL[0],
}
-- pokefirered/src/berry_crush.c:537
local COLOR_GRAY = FrlgFont.COLOR.NORMAL

Records.open = false
Records._kind = nil
Records._lines = {}
Records._onDone = nil
Records._frames = 0

local function num(v, digits)
  v = math.floor(tonumber(v) or 0)
  if v < 0 then v = 0 end
  if digits then v = v % (10 ^ digits) end
  return v
end

-- pokefirered/src/berry_crush.c:3146
function Records.pressingSpeedText(speed)
  speed = num(speed) % 0x10000
  local hi = math.floor(speed / 256)
  local lo = speed % 256
  local score = 0
  for j = 0, 7 do
    if math.floor(lo / 2 ^ (7 - j)) % 2 == 1 then
      score = score + Records.PRESSING_SPEED_CONVERSION[j + 1]
    end
  end
  local frac = math.floor(score / 1000000) % 100
  -- pokefirered/src/strings.c:1048
  return string.format("%3d.%02d ", hi, frac) .. Strings("Times/sec.")
end

-- pokefirered/src/berry_crush.c:3189
local function crushSpeeds(session)
  local stored = type(session) == "table" and session.berryCrushPressingSpeeds or nil
  local out = {}
  for i = 1, 4 do
    out[i] = num(type(stored) == "table" and stored[i] or 0) % 0x10000
  end
  return out
end

local function jumpRecords(session)
  local r = type(session) == "table" and type(session.pokemonJumpRecords) == "table"
    and session.pokemonJumpRecords or {}
  -- pokefirered/src/pokemon_jump.c:4550
  return {
    num(r.jumpsInRow, 5),
    num(r.bestJumpScore, 5),
    num(r.excellentsInRow, 5),
  }
end

-- pokefirered/src/dodrio_berry_picking.c:3001
local function dodrioRecords(session)
  local r = type(session) == "table" and type(session.dodrioBerryPickingRecords) == "table"
    and session.dodrioBerryPickingRecords or {}
  -- pokefirered/src/dodrio_berry_picking.c:2947
  return {
    num(r.berriesPicked, 4),
    num(r.bestScore, 7),
    num(r.berriesPickedInRow, 4),
  }
end

local function line(text, x, y, colors, spacing)
  return { text = text, x = x, y = y, colors = colors or COLOR_GRAY, spacing = spacing or 0 }
end

local function buildBerryCrush(session)
  local lines = {}
  -- pokefirered/src/berry_crush.c:3112
  local title = Strings("BERRY CRUSH")
  lines[#lines + 1] = line(title, 96 - math.floor(FrlgFont.measure(title) / 2), 2, COLOR_BLUE)
  -- pokefirered/src/berry_crush.c:3122
  local sub = Strings("Pressing-Speed Rankings")
  lines[#lines + 1] = line(sub, 96 - math.floor(FrlgFont.measure(sub) / 2), 18, COLOR_BLUE)
  local speeds = crushSpeeds(session)
  local y = 42
  for i = 1, 4 do
    -- pokefirered/src/berry_crush.c:3135
    lines[#lines + 1] = line(Strings("%d PLAYERS", i + 1), 4, y)
    -- pokefirered/src/berry_crush.c:3156
    local s = Records.pressingSpeedText(speeds[i])
    lines[#lines + 1] = line(s, 192 - FrlgFont.measure(s), y)
    y = y + 14
  end
  return lines
end

local function buildPokemonJump(session)
  local lines = {}
  -- pokefirered/src/pokemon_jump.c:4560
  lines[#lines + 1] = line(Strings("POKéMON JUMP RECORDS"), 0, 0, nil, 1)
  -- pokefirered/src/pokemon_jump.c:4504
  local labels = { Strings("Jumps in a row:"), Strings("Best score:"), Strings("EXCELLENTS in a row:") }
  local values = jumpRecords(session)
  for i = 1, 3 do
    local y = 20 + (i - 1) * 14
    lines[#lines + 1] = line(labels[i], 0, y, nil, 1)
    -- pokefirered/src/pokemon_jump.c:4566
    local s = tostring(values[i])
    lines[#lines + 1] = line(s, 0xDE - FrlgFont.measure(s), y)
  end
  return lines
end

local function buildDodrio(session)
  local lines = {}
  -- pokefirered/src/dodrio_berry_picking.c:3008
  lines[#lines + 1] = line(Strings("DODRIO BERRY-PICKING RECORDS"), 1, 1)
  -- pokefirered/src/dodrio_berry_picking.c:2946
  local labels = {
    Strings("BERRIES picked:"),
    Strings("Best score:"),
    Strings("BERRIES picked in a row with\nfive players:"),
  }
  -- pokefirered/src/dodrio_berry_picking.c:2950
  local textY, numY = { 24, 40, 56 }, { 24, 40, 70 }
  local values = dodrioRecords(session)
  for i = 1, 3 do
    local s = tostring(values[i])
    lines[#lines + 1] = line(labels[i], 1, textY[i])
    -- pokefirered/src/dodrio_berry_picking.c:3014
    lines[#lines + 1] = line(s, 240 - 16 - FrlgFont.measure(s), numY[i])
  end
  return lines
end

local BUILDERS = {
  berry_crush = buildBerryCrush,
  pokemon_jump = buildPokemonJump,
  dodrio = buildDodrio,
}

function Records.lines()
  return Records._lines
end

function Records.kind()
  return Records._kind
end

function Records.isOpen()
  return Records.open
end

function Records.show(kind, session, onDone)
  local build = BUILDERS[kind]
  if not build then error("unknown minigame records kind: " .. tostring(kind)) end
  Records._kind = kind
  Records._lines = build(session)
  Records._onDone = onDone
  Records._frames = 0
  Records.open = true
  Stack.push(Records.ID, Records, { hideBelow = false, drawUnder = true })
  return Records
end

function Records.close()
  if not Records.open then return false end
  Records.open = false
  Records._kind = nil
  Stack.pop(Records.ID)
  local cb = Records._onDone
  Records._onDone = nil
  if cb then cb() end
  return true
end

function Records.reset()
  Records.open = false
  Records._kind = nil
  Records._lines = {}
  Records._onDone = nil
  Stack.pop(Records.ID)
end

function Records.update(_dt)
  if Records.open then Records._frames = Records._frames + 1 end
end

function Records.handleInput(input)
  if not Records.open or not input then return end
  if Records._frames < 2 then return end
  if input:wasPressed("a") or input:wasPressed("b") then
    Records.close()
  end
end

local function drawSpaced(text, x, y, colors, spacing)
  for ttype, val in FrlgFont.scanTokens(text) do
    if ttype == "char" then
      x = x + FrlgFont.drawGlyph(FrlgFont.glyphId(val), x, y, { colors = colors }) + spacing
    end
  end
end

function Records.draw()
  if not Records.open then return end
  local tpl = TEMPLATES[Records._kind]
  if not tpl then return end
  Window.stdFrame(tpl)
  local ox, oy = tpl.tilemapLeft * 8, tpl.tilemapTop * 8
  for _, l in ipairs(Records._lines) do
    if l.spacing > 0 then
      drawSpaced(l.text, ox + l.x, oy + l.y, l.colors, l.spacing)
    else
      FrlgFont.draw(l.text, ox + l.x, oy + l.y, { colors = l.colors })
    end
  end
end

return Records
