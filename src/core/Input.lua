-- Input abstraction: maps keyboard to Game Boy buttons.
-- `down` = held this frame; `pressed` = edge, consumed per fixed step.

local Input = {}

local DEFAULT_BINDINGS = {
  up = "up", w = "up",
  down = "down", s = "down",
  left = "left", a = "left",
  right = "right", d = "right",
  z = "a", ["return"] = "a", space = "a",
  x = "b", backspace = "b",
  ["kpenter"] = "start", escape = "start",
  -- Select: fight-menu move reorder + bag item reorder. Tab is the
  -- discoverable default (shown in CONTROLS); both shifts stay as
  -- aliases so Right-Shift muscle memory from older builds still works.
  tab = "select",
  rshift = "select",
  lshift = "select",
}

-- keys that map to "start" but also to "a" would conflict; keep Enter = a,
-- Escape = start for desktop friendliness.

-- LÖVE's standard gamepad mapping (SDL game controller DB), consistent
-- across Xbox/PlayStation/generic controllers on desktop and mobile. Some
-- third-party pads report their own SDL mapping for a given physical
-- button (e.g. Select/Back/View on off-brand XInput pads), which is what
-- src/ui/BindingsMenu.lua's rebinding is for -- see applyBindings below.
local DEFAULT_GAMEPAD_BINDINGS = {
  dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
  a = "a", b = "b",
  start = "start", back = "select",
}

-- left-stick deadzones: press past STICK_ON, release once back under
-- STICK_OFF. The gap (hysteresis) stops the direction from flickering
-- while the stick sits near the threshold.
local STICK_ON = 0.5
local STICK_OFF = 0.3

-- Generic SDL joysticks expose the left stick as the first two numbered
-- axes and the D-pad as a hat.  This is common on Linux handhelds whose
-- controller has no game-controller database entry.  The indices below are
-- the desktop XInput order and are only meaningful for such pads: raw
-- numbering is per-driver, and SDL's iOS/MFi driver packs only the buttons
-- a pad actually reports, which slides the D-pad down onto 7..10 (#620).
-- These are the raw DEFAULTS only: applyBindings layers the player's
-- "joyN" pad bindings over them (#632), and only a stick SDL does NOT
-- recognize as a gamepad is ever served out of this table -- see
-- joystickpressed below.
local RAW_BUTTON_BINDINGS = {
  [1] = "a", [2] = "b",
  [7] = "select", [8] = "start", [9] = "select", [10] = "start",
}

local HAT_DIRECTIONS = {
  u = { "up" }, d = { "down" }, l = { "left" }, r = { "right" },
  lu = { "left", "up" }, ru = { "right", "up" },
  ld = { "left", "down" }, rd = { "right", "down" },
}

function Input:init()
  self:applyBindings(nil)
  self:reset()
end

-- Layers a player's rebind choices (save.options.bindings, written by
-- src/ui/BindingsMenu.lua) on top of the defaults above. A rebind adds an
-- extra way to trigger that action instead of replacing the default key,
-- so e.g. Z/Enter/Space all still press A even after binding a 4th key to
-- it. Call whenever options load or change (see Game:applyOptions and
-- BindingsMenu:storeBinding) -- without this the menu records a choice
-- that never actually reaches gameplay.
function Input:applyBindings(overlay)
  local keys, pads, joys = {}, {}, {}
  for key, action in pairs(DEFAULT_BINDINGS) do keys[key] = action end
  for button, action in pairs(DEFAULT_GAMEPAD_BINDINGS) do pads[button] = action end
  for index, action in pairs(RAW_BUTTON_BINDINGS) do joys[index] = action end
  for actionId, binding in pairs(overlay or {}) do
    if type(binding) == "table" then
      if binding.key then keys[binding.key] = actionId end
      if binding.pad then pads[binding.pad] = actionId end
    elseif type(binding) == "string" then
      keys[binding] = actionId
    end
  end
  -- A pad binding named "joyN" is the Nth button of a stick SDL has no
  -- game-controller-database entry for, captured on the joystick path by
  -- src/ui/BindingsMenu.lua (#632).  It deliberately rides the existing
  -- pad slot: the CONTROLS row, the swap in BindingsMenu:storeBinding and
  -- START's reset-all then all stay one code path, and this loop is the
  -- only place that has to know what the name means.  Laid over the raw
  -- defaults AFTER them, so a rebind wins the button it claims.
  for padName, action in pairs(pads) do
    local n = tonumber(padName:match("^joy(%d+)$"))
    if n then joys[n] = action end
  end
  self.keyBindings = keys
  self.padBindings = pads
  self.joyBindings = joys
end

-- Purely event-driven state (press sets true, release sets false) has no
-- fallback if a release event never arrives -- focus loss, a minimized
-- window, or a disconnected gamepad can all swallow the key-up/button-up
-- that would have cleared a held direction. Called from Game on those
-- transitions so a stuck flag can't outlive them.
function Input:reset()
  self.state = {}
  self.pressQueue = {}
  self.pressed = {}
  self.sources = {}
  self.stickAxis = { x = 0, y = 0 }
  self.stickDir = nil
  self.hatDirs = {}
end

-- Multiple physical sources (W + Up, d-pad + stick, etc.) can claim the
-- same GB button. Track them individually so releasing one doesn't clear
-- a hold another source still owns, and so a press+release that both land
-- before the next FixedStep can't be revived when step() drains the queue.
local function press(self, btn, source)
  local sources = self.sources[btn]
  if not sources then
    sources = {}
    self.sources[btn] = sources
  end
  if not sources[source] then
    sources[source] = true
    table.insert(self.pressQueue, btn)
  end
  self.state[btn] = true
end

local function release(self, btn, source)
  local sources = self.sources[btn]
  if sources then
    sources[source] = nil
    if next(sources) == nil then
      -- Leave an empty table (not nil) so step() can tell a real
      -- source was released before the queue drained, versus a
      -- synthetic pressQueue inject that never had sources at all.
      self.state[btn] = false
    end
  else
    self.state[btn] = false
  end
end

function Input:keypressed(key)
  local btn = self.keyBindings[key]
  if btn then
    press(self, btn, "key:" .. key)
  end
end

function Input:keyreleased(key)
  local btn = self.keyBindings[key]
  if btn then
    release(self, btn, "key:" .. key)
  end
end

-- Called once per fixed step: promote queued presses to this step's edges.
-- Hold state is owned by live sources (updated in press/release), not
-- re-asserted here -- otherwise a same-frame press→release leaves the
-- button stuck on after the queue drains.
-- Synthetic injects (tests/drivers writing pressQueue directly, with no
-- source entry) still set state so scripted holds keep working.
function Input:step()
  self.pressed = {}
  for _, btn in ipairs(self.pressQueue) do
    self.pressed[btn] = true
    local sources = self.sources[btn]
    if sources == nil then
      -- synthetic pressQueue inject (tests/drivers): no live source map
      self.state[btn] = true
    elseif next(sources) ~= nil then
      self.state[btn] = true
    end
    -- sources == {}: real press fully released before this step -- keep up
  end
  for btn, sources in pairs(self.sources) do
    if next(sources) == nil then
      self.sources[btn] = nil
    end
  end
  self.pressQueue = {}
end

-- The on-screen touch overlay (src/core/TouchControls.lua) presses GB
-- buttons directly by name -- not through a keyboard alias -- so a player
-- rebind can never detach or shadow the overlay.
function Input:overlayPressed(btn)
  press(self, btn, "touch:" .. btn)
end

function Input:overlayReleased(btn)
  release(self, btn, "touch:" .. btn)
end

function Input:gamepadpressed(joystick, button)
  local btn = self.padBindings[button]
  if btn then
    press(self, btn, "pad:" .. button)
  end
end

function Input:gamepadreleased(joystick, button)
  local btn = self.padBindings[button]
  if btn then
    release(self, btn, "pad:" .. button)
  end
end

-- LOVE raises love.joystickpressed for EVERY stick, including ones SDL
-- recognizes as gamepads, which raise love.gamepadpressed for the same
-- physical press as well.  Answering both meant the fixed raw table
-- re-asserted the factory A/B/START/SELECT map underneath the player's
-- rebinds, so swapping A and B in CONTROLS pressed both at once and any
-- controller rebind of those four looked ignored; on iOS the MFi driver's
-- packing put the D-pad on 7..10, so a D-pad press also fired SELECT or
-- START (#620, #632).  A recognized pad is served by the gamepad path
-- alone; the raw path exists for sticks with no game-controller-database
-- entry.  A nil joystick is a raw stick: that is how
-- tests/input_hold_test.lua and the drivers drive this path.
local function isRawStick(joystick)
  return not (joystick and joystick.isGamepad and joystick:isGamepad())
end

function Input:joystickpressed(joystick, button)
  if not isRawStick(joystick) then return end
  local btn = self.joyBindings[button]
  if btn then press(self, btn, "joy:" .. button) end
end

function Input:joystickreleased(joystick, button)
  if not isRawStick(joystick) then return end
  local btn = self.joyBindings[button]
  if btn then release(self, btn, "joy:" .. button) end
end

-- left stick treated as a continuous held direction, same 4-way rule as
-- the touch swipe d-pad: whichever axis has the larger magnitude wins.
function Input:gamepadaxis(joystick, axis, value)
  if axis == "leftx" then
    self.stickAxis.x = value
  elseif axis == "lefty" then
    self.stickAxis.y = value
  else
    return
  end

  local x, y = self.stickAxis.x, self.stickAxis.y
  local ax, ay = math.abs(x), math.abs(y)
  local newDir = self.stickDir
  if ax > STICK_ON or ay > STICK_ON then
    if ax >= ay then
      newDir = x > 0 and "right" or "left"
    else
      newDir = y > 0 and "down" or "up"
    end
  elseif ax < STICK_OFF and ay < STICK_OFF then
    newDir = nil
  end

  if newDir ~= self.stickDir then
    if self.stickDir then
      release(self, self.stickDir, "stick")
    end
    if newDir then
      press(self, newDir, "stick")
    end
    self.stickDir = newDir
  end
end

function Input:joystickaxis(joystick, axis, value)
  if not isRawStick(joystick) then return end
  if axis == 1 then
    self:gamepadaxis(joystick, "leftx", value)
  elseif axis == 2 then
    self:gamepadaxis(joystick, "lefty", value)
  end
end

-- Same duplicate-event rule as joystickpressed (#620, #632): a recognized
-- pad's D-pad already arrived as dpup/dpdown/dpleft/dpright through the
-- gamepad map, so letting the hat answer too would re-assert the factory
-- directions on top of a direction rebind.
function Input:joystickhat(joystick, hat, direction)
  if not isRawStick(joystick) then return end
  local source = "hat:" .. hat
  for _, btn in ipairs(self.hatDirs[hat] or {}) do
    release(self, btn, source)
  end
  local dirs = HAT_DIRECTIONS[direction] or {}
  for _, btn in ipairs(dirs) do
    press(self, btn, source)
  end
  self.hatDirs[hat] = dirs
end

function Input:isDown(btn)
  return self.state[btn] or false
end

-- True when the on-screen overlay is one of the live sources holding this
-- button (see overlayPressed above).  Player:turnWindow widens the
-- turn-in-place tap window on touch, where a press and release can never be
-- as short as a physical d-pad's (#415).
function Input:isTouchDown(btn)
  local sources = self.sources[btn]
  return (sources and sources["touch:" .. btn]) and true or false
end

function Input:wasPressed(btn)
  return self.pressed[btn] or false
end

-- Soft reset (#563).  _Joypad (engine/joypad.asm) tests the RAW joypad read
-- with `cp PAD_BUTTONS` -- an equality, not a mask -- so the combo counts
-- only while A, B, SELECT and START are the only buttons down; any d-pad
-- direction in the mix cancels it.  That test sits ahead of the wJoyIgnore
-- and BIT_DISABLE_JOYPAD masking below it, which is why the reset still
-- works mid-battle and mid-cutscene where ordinary input is thrown away.
-- TrySoftReset then burns one DelayFrame per pass and decrements hSoftReset,
-- seeded with 16 by Init (home/init.asm), so the combo has to survive 16
-- consecutive polls.  That hold is also what keeps the on-screen overlay
-- safe: it already takes four separate fingers on four separate controls,
-- and they all have to stay put for better than a quarter of a second.
local SOFT_RESET_FRAMES = 16

function Input:softResetHeld()
  if not (self.state.a and self.state.b
          and self.state.start and self.state.select) then
    return false
  end
  return not (self.state.up or self.state.down
              or self.state.left or self.state.right)
end

-- Ticked once per fixed step by Game:step; true on the step the countdown
-- runs out.  hSoftReset is never re-seeded on release in the original, so
-- its count leaks across a whole session; a port that copied that would
-- eventually reset on a stray four-button press, so the counter re-arms as
-- soon as the combo drops.
function Input:softResetStep()
  if not self:softResetHeld() then
    self.softResetFrames = nil
    return false
  end
  local left = (self.softResetFrames or SOFT_RESET_FRAMES) - 1
  self.softResetFrames = left
  if left > 0 then return false end
  self.softResetFrames = nil
  return true
end

return Input
