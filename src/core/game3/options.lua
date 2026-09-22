-- FRLG options mirrored into game3 session (option_menu.c fields used on field).

local Options = {}

local Profile = require("src.core.game3.profile")

Options.BLOCK = Profile.FALLBACK_ID

-- pret: textSpeed 0=SLOW 1=MID 2=FAST
Options.DEFAULTS = {
  textSpeed = 1,
  battleScene = 0,   -- 0=ON 1=OFF
  battleStyle = 0,   -- 0=SHIFT 1=SET
  sound = 0,         -- 0=MONO 1=STEREO
  buttonMode = 0,    -- 0=HELP 1=LR 2=L=A
  frameType = 0,
  voidFill = "map",
}

local function fill_defaults(o)
  for k, v in pairs(Options.DEFAULTS) do
    if o[k] == nil then o[k] = v end
  end
  return o
end

local CART_KEYS = {
  "textSpeed", "battleScene", "battleStyle", "sound", "buttonMode", "frameType",
}

local function migrate_root(engine, o)
  if type(engine.battleStyle) ~= "number" then return end
  for _, k in ipairs(CART_KEYS) do
    if type(engine[k]) == type(Options.DEFAULTS[k]) and o[k] == nil then
      o[k] = engine[k]
    end
    engine[k] = nil
  end
  engine.text_speed = nil
  engine.l_equals_a = nil
end

function Options.block(engine, blockId)
  if type(engine) ~= "table" then return fill_defaults({}) end
  blockId = blockId or Profile.active().optionsBlock
  local o = engine[blockId]
  if type(o) ~= "table" then
    o = {}
    engine[blockId] = o
    migrate_root(engine, o)
  end
  return fill_defaults(o)
end

function Options.blockId(session)
  if type(session) == "table" and type(session.version) == "string" then
    return Profile.of(session.version).optionsBlock
  end
  return Profile.active().optionsBlock
end

function Options.bind(session, engine)
  if type(session) ~= "table" then return nil end
  if type(engine) ~= "table" then return Options.ensure(session) end
  local o = Options.block(engine, Options.blockId(session))
  session.options = o
  session.engineOptions = engine
  o.text_speed = o.textSpeed
  o.l_equals_a = (tonumber(o.buttonMode) == 2)
  return o
end

function Options.engine(session)
  local e = type(session) == "table" and session.engineOptions
  if type(e) == "table" then return e end
  return nil
end

function Options.ensure(session)
  session = session or {}
  local o = session.options
  if type(o) ~= "table" then
    o = {}
    session.options = o
  end
  local blockId = Options.blockId(session)
  if type(o[blockId]) == "table" then
    session.engineOptions = o
    o = Options.block(o, blockId)
    session.options = o
  end
  return fill_defaults(o)
end

function Options.textSpeed(session)
  local o = Options.ensure(session)
  -- Canonical field is textSpeed; text_speed is a schema alias.
  local n = tonumber(o.textSpeed)
  if n == nil then n = tonumber(o.text_speed) end
  n = n or 1
  if n < 0 then n = 0 end
  if n > 2 then n = 2 end
  return n
end

function Options.lEqualsA(session)
  local o = Options.ensure(session)
  if o.l_equals_a ~= nil then return o.l_equals_a and true or false end
  return tonumber(o.buttonMode) == 2
end

-- src/menu_helpers.c:72
function Options.lrMode(session)
  local o = Options.ensure(session)
  return tonumber(o.buttonMode) == 1
end

-- pokefirered/src/battle_main.c
function Options.battleStyle(session)
  local o = Options.ensure(session)
  return tonumber(o.battleStyle) == 1 and "set" or "shift"
end

-- pokefirered/src/option_menu.c
function Options.battleScene(session)
  local o = Options.ensure(session)
  return tonumber(o.battleScene) ~= 1
end

function Options.frameType(session)
  local o = Options.ensure(session)
  return tonumber(o.frameType) or 0
end

function Options.mono(session)
  local o = Options.ensure(session)
  return tonumber(o.sound) == 0
end

function Options.voidFill(session)
  local o = Options.ensure(session)
  local v = o.voidFill
  if v == "trees" or v == "water" or v == "black" then return v end
  return "map"
end

function Options.set(session, key, value)
  local o = Options.ensure(session)
  o[key] = value
  if key == "textSpeed" or key == "text_speed" then
    o.textSpeed = value
    o.text_speed = value
  end
  if key == "buttonMode" then
    o.l_equals_a = (tonumber(value) == 2)
  end
  if key == "l_equals_a" then
    o.buttonMode = value and 2 or 0
  end
  return o
end

return Options
