-- pokefirered/src/field_screen_effect.c:387 Task_RushInjuredPokemonToCenter

local Stack = require("src.ui.game3.stack")
local Font = require("src.ui.game3.frlg_font")
local Display = require("src.core.game3.display")
local RomText = require("src.core.game3.rom_text")

local Rush = {}

Rush.ID = "whiteout_rush"
-- pokefirered/src/overworld.c:1549
Rush.HOLD_FRAMES = 120
Rush._state = nil

local function stopMusic()
  local Audio = require("src.core.game3.audio")
  if Audio.currentSong and Audio.currentSong() then Audio.playSong(0) end
end

function Rush.start(game, session, opts)
  opts = opts or {}
  local name = (session and (session.name or session.playerName)) or ""
  -- pokefirered/src/field_screen_effect.c:414, :421
  local key = opts.home and "gText_PlayerScurriedBackHome" or "gText_PlayerScurriedToCenter"
  local text = RomText.plain(key, { playerName = name })
  Rush._state = {
    phase = "hold",
    frames = 0,
    text = text,
    total = Font.countChars(text),
    shown = 0,
    home = opts.home and true or false,
    healerLocalId = opts.healerLocalId,
    game = game,
  }
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.lock then Field.lock() end
  -- pokefirered/src/overworld.c:1552
  stopMusic()
  Stack.push(Rush.ID, Rush, { hideBelow = true, fullscreen = true })
end

function Rush.isActive()
  return Rush._state ~= nil
end

function Rush.phase()
  return Rush._state and Rush._state.phase
end

function Rush.text()
  return Rush._state and Rush._state.text
end

local function finish()
  local st = Rush._state
  Rush._state = nil
  Stack.pop(Rush.ID)
  local Fade = require("src.ui.game3.fade")
  -- pokefirered/src/field_screen_effect.c:434
  Fade.begin(Fade.MODE.FROM_BLACK, 1, function()
    local Space = package.loaded["src.core.game3.scripting.space"]
    if not (Space and Space.startScript) then return end
    -- pokefirered/src/field_screen_effect.c:441
    local key = st.home and "EventScript_AfterWhiteOutMomHeal" or "EventScript_AfterWhiteOutHeal"
    Space.startScript(key, st.healerLocalId)
  end)
end

function Rush.update(_dt)
  local st = Rush._state
  if not st then return end
  stopMusic()
  if st.phase == "hold" then
    st.frames = st.frames + 1
    if st.frames >= Rush.HOLD_FRAMES then st.phase = "print" end
  elseif st.phase == "print" then
    st.shown = st.shown + 1
    if st.shown >= st.total then st.phase = "wait" end
  end
end

function Rush.handleInput(input)
  local st = Rush._state
  if not (st and st.phase == "wait" and input and input.wasPressed) then return end
  if input:wasPressed("a") or input:wasPressed("b") then finish() end
end

function Rush.draw()
  local st = Rush._state
  local Renderer = package.loaded["src.render.Renderer"]
  if Renderer then
    Renderer.worldFadeAlpha = 1
    Renderer.worldFadeColor = { 0, 0, 0 }
  end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  love.graphics.setColor(1, 1, 1, 1)
  if not st or st.phase == "hold" then return end
  -- pokefirered/src/field_screen_effect.c:21 sWindowTemplate_WhiteoutText
  Font.draw(st.text, 2, 5 * 8 + 8, { colors = Font.COLOR.WHITE, limitChars = st.shown })
end

return Rush
