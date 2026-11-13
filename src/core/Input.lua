-- Input abstraction: maps keyboard to Game Boy buttons.
-- `down` = held this frame; `pressed` = edge, consumed per fixed step.

local GamepadMap = require("src.core.GamepadMap")
local PadHints = require("src.core.PadHints")

local Input = {}
local press, release

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
  -- FRLG shoulders: bag paging + L=A alias.
  q = "l",
  e = "r",
  lctrl = "l",
  rctrl = "r",
}

-- keys that map to "start" but also to "a" would conflict; keep Enter = a,
-- Escape = start for desktop friendliness.

-- left-stick deadzones: press past STICK_ON, release once back under
-- STICK_OFF. The gap (hysteresis) stops the direction from flickering
-- while the stick sits near the threshold.
local STICK_ON = 0.5
local STICK_OFF = 0.3

-- Raw joystick defaults + NX overrides live in src/core/GamepadMap.lua
-- (see RAW_BUTTON_BINDINGS / NX_RAW_BUTTON_BINDINGS and #620 / #632).
--
-- SELECT ON A PLAYSTATION PAD, checked rather than assumed.  There is no
-- button called "select" in SDL's game-controller vocabulary: the small
-- left-hand menu button is `back` on every family, and GamepadMap's
-- DEFAULT_GAMEPAD_BINDINGS maps it to GB SELECT.  The DualSense's CREATE
-- button (and the DualShock 4's SHARE) is that button -- the controller
-- database LOVE 11.5 ships spells the DualSense row
-- "PS5 Controller,a:b1,b:b2,back:b8,...,misc1:b13,start:b9" -- so a
-- recognized pad delivers it here as gamepadpressed(_, "back") and needs no
-- entry of its own.  What it also has, and what LOVE 11.x has no name for at
-- all, is the TOUCHPAD click (SDL_CONTROLLER_BUTTON_TOUCHPAD) and the mute
-- key (`misc1`): neither reaches love.gamepadpressed, so neither can be bound,
-- and a player reaching for the touchpad expecting SELECT will find nothing.
-- Not a mapping this file can add -- the event never arrives.
--
-- An unrecognized PlayStation pad falls to the raw path instead, where SHARE /
-- CREATE is generic-HID button 9 and RAW_BUTTON_BINDINGS[9] is already
-- "select".  Both roads reach SELECT; the one road that did not was Gold's,
-- where src/core/Game2.lua used to answer `back` with love.event.quit().

Input.PAD_ACTIONS = { speedUp = true, speedDown = true }

local STICK_DEFAULT_BINDINGS = {
  leftstick_up = "up", leftstick_down = "down",
  leftstick_left = "left", leftstick_right = "right",
  lsup = "up", lsdown = "down", lsleft = "left", lsright = "right",
}

local POLLABLE_PAD_BUTTONS = {
  a = true, b = true, x = true, y = true, back = true, guide = true, start = true,
  leftstick = true, rightstick = true, leftshoulder = true, rightshoulder = true,
  dpup = true, dpdown = true, dpleft = true, dpright = true,
  triggerleft = true, triggerright = true,
  leftstick_up = true, leftstick_down = true, leftstick_left = true, leftstick_right = true,
  rightstick_up = true, rightstick_down = true, rightstick_left = true, rightstick_right = true,
  misc1 = true, paddle1 = true, paddle2 = true, paddle3 = true, paddle4 = true,
  touchpad = true,
}

local HAT_DIRECTIONS = {
  u = { "up" }, d = { "down" }, l = { "left" }, r = { "right" },
  lu = { "left", "up" }, ru = { "right", "up" },
  ld = { "left", "down" }, rd = { "right", "down" },
}

function Input:init(shoulderGameplay)
  self.shoulderGameplay = shoulderGameplay ~= false
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
  local keys, pads, joys, acts, explicit = {}, {}, {}, {}, {}
  for key, action in pairs(DEFAULT_BINDINGS) do keys[key] = action end
  for button, action in pairs(GamepadMap.gamepadBindings()) do pads[button] = action end
  pads.leftshoulder, pads.rightshoulder = "l", "r"
  for index, action in pairs(GamepadMap.rawBindings()) do joys[index] = action end
  for button, action in pairs(GamepadMap.DEFAULT_PAD_ACTIONS) do acts[button] = action end
  local ids = {}
  for id in pairs(overlay or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local binding = overlay[id]
    if not Input.PAD_ACTIONS[id] then
      if type(binding) == "table" then
        if binding.key then keys[binding.key] = id end
        if binding.pad then
          local button = GamepadMap.normalizePad and GamepadMap.normalizePad(binding.pad) or GamepadMap.TRIGGER_AXES[binding.pad] or binding.pad
          pads[button], acts[button] = id, nil
        end
      elseif type(binding) == "string" then keys[binding] = id end
    end
  end
  for _, id in ipairs(ids) do
    if Input.PAD_ACTIONS[id] then
      for button, action in pairs(acts) do
        if action == id then acts[button] = nil end
      end
    end
  end
  for _, id in ipairs(ids) do
    local binding = overlay[id]
    if Input.PAD_ACTIONS[id] and type(binding) == "table" and binding.pad then
      local button = GamepadMap.normalizePad and GamepadMap.normalizePad(binding.pad) or GamepadMap.TRIGGER_AXES[binding.pad] or binding.pad
      acts[button], explicit[button], pads[button] = id, true, nil
    end
  end
  for button, action in pairs(pads) do
    local n = tonumber(button:match("^joy(%d+)$"))
    if n then joys[n] = action end
  end
  local joyActs = {}
  for button, action in pairs(acts) do
    local n = tonumber(button:match("^joy(%d+)$"))
    if n then joyActs[n], joys[n] = action, nil end
  end
  local poll = {}
  local canPoll = GamepadMap.gamepadBindings() ~= GamepadMap.NX_GAMEPAD_BINDINGS
  for button, action in pairs(pads) do
    if canPoll and POLLABLE_PAD_BUTTONS[button] then
      poll[#poll + 1] = { button = button, btn = action, source = "pad:" .. button,
        chord = GamepadMap.displayChordDigit(button) ~= nil }
    end
  end
  self.keyBindings, self.padBindings, self.joyBindings = keys, pads, joys
  self.padActions, self.explicitPadActions, self.joyActions = acts, explicit, joyActs
  self.padPoll = poll
  local pollSet = {}
  for i = 1, #poll do pollSet[poll[i].button] = true end
  self.padPollSet = pollSet

  local effectiveSticks = {}
  for k, v in pairs(STICK_DEFAULT_BINDINGS) do effectiveSticks[k] = v end

  for button, action in pairs(pads) do
    -- Rule A: Competing stick bound to directional action
    local isRightStick = button:sub(1, 10) == "rightstick" or button:sub(1, 2) == "rs"
    if isRightStick and (action == "up" or action == "down" or action == "left" or action == "right") then
      effectiveSticks["leftstick_" .. action] = nil
      effectiveSticks["ls" .. action] = nil
    end
    -- Rule B: Left stick bound to an arbitrary action (normalize long/short aliases)
    local lsDir = button:match("^leftstick_(%a+)$") or button:match("^ls(%a+)$")
    if lsDir then
      effectiveSticks["leftstick_" .. lsDir] = nil
      effectiveSticks["ls" .. lsDir] = nil
    end
  end
  self.effectiveStickBindings = effectiveSticks

  if release and self.sources then
    local stickDirs = { "up", "down", "left", "right" }
    for _, dir in ipairs(stickDirs) do
      local sourcesToClear = {
        "pad:leftstick_" .. dir,
        "pad:rightstick_" .. dir,
        "pad:ls" .. dir,
        "pad:rs" .. dir,
      }
      for _, src in ipairs(sourcesToClear) do
        for btn, sources in pairs(self.sources) do
          if sources[src] then release(self, btn, src) end
        end
      end
    end
  end
  self.stickDir = nil
  self.rightStickDir = nil
  self.stickOwner = nil
  self.rightStickOwner = nil
end

function Input.hotkeyKey(key)
  if type(key) ~= "string" then return key end
  if key:match("^%d$") then return key end
  local bound = Input.keyBindings
  if bound and bound[key] then return key end
  local digit = key:match("^kp(%d)$")
  if digit then return digit end
  local kb = love and love.keyboard
  if kb and kb.getScancodeFromKey then
    local ok, scancode = pcall(kb.getScancodeFromKey, key)
    if ok and type(scancode) == "string" and scancode:match("^%d$") then
      return scancode
    end
  end
  return key
end

function Input:padAction(button, shoulderGameplay)
  button = GamepadMap.normalizePad and GamepadMap.normalizePad(button) or GamepadMap.TRIGGER_AXES[button] or button
  if shoulderGameplay and (button == "leftshoulder" or button == "rightshoulder")
      and not (self.explicitPadActions and self.explicitPadActions[button]) then return nil end
  return self.padActions and self.padActions[button] or nil
end

function Input:joyAction(index)
  return self.joyActions and self.joyActions[index] or nil
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
  self.rightStickAxis = { x = 0, y = 0 }
  self.rightStickDir = nil
  self.stickOwner = nil
  self.rightStickOwner = nil
  self.hatDirs = {}
  self.triggerHeld = {}
  self.captureArmed = false
  self.captureEvents = nil
  self.aliases = nil
  self.aliasHeld = nil
  self._pollPads = nil
  self._pollPadCount = nil
  local suppress = {}
  local poll = self.padPoll
  if poll then
    for i = 1, #poll do suppress[poll[i].button] = true end
  end
  self.padSuppress = suppress
end

function Input:padEventSeen(button)
  if type(button) ~= "string" then return end
  local suppress = self.padSuppress
  if not suppress then
    suppress = {}
    self.padSuppress = suppress
  end
  suppress[button] = true
end

-- pokefirered/src/main.c:325
function Input:setButtonAlias(src, dst)
  local aliases = self.aliases
  if dst == nil then
    if aliases then
      aliases[src] = nil
      if next(aliases) == nil then self.aliases = nil end
    end
    return
  end
  if not aliases then
    aliases = {}
    self.aliases = aliases
  end
  aliases[src] = dst
end

function Input:armCapture()
  self.captureArmed = true
  self.captureEvents = {}
end

function Input:disarmCapture()
  self.captureArmed = false
  self.captureEvents = nil
end

function Input:takeCaptureEvents()
  local ev = self.captureEvents
  self.captureEvents = self.captureArmed and {} or nil
  return ev
end

local function noteCapture(self, kind, phase, value)
  if not self.captureArmed then return end
  local ev = self.captureEvents
  if not ev then
    ev = {}
    self.captureEvents = ev
  end
  ev[#ev + 1] = { kind = kind, phase = phase, value = value }
end

-- Multiple physical sources (W + Up, d-pad + stick, etc.) can claim the
-- same GB button. Track them individually so releasing one doesn't clear
-- a hold another source still owns, and so a press+release that both land
-- before the next FixedStep can't be revived when step() drains the queue.
press = function(self, btn, source)
  local sources = self.sources[btn]
  if not sources then
    sources = {}
    self.sources[btn] = sources
  end
  if not sources[source] then
    local held = next(sources) ~= nil
    sources[source] = true
    if not held then table.insert(self.pressQueue, btn) end
  end
  self.state[btn] = true
end

release = function(self, btn, source)
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
  noteCapture(self, "key", "pressed", key)
  local btn = self.keyBindings[key]
  if btn then
    press(self, btn, "key:" .. key)
  end
end

function Input:keyreleased(key)
  noteCapture(self, "key", "released", key)
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
local function modOwnsPad()
  local Runtime = package.loaded["src.mods.Runtime"]
  return type(Runtime) == "table" and Runtime.wantsHook ~= nil
    and Runtime.wantsHook("input.gamepad") == true
end

local function notePadRepair(fix, button)
  local Diag = package.loaded["src.debug.SwitchDiagnostics"]
  if type(Diag) == "table" and Diag.onEvent then
    Diag.onEvent("padwatch", { fix = fix, button = button })
  end
end

local function anyPadDown(pads, button)
  for k = 1, #pads do
    local j = pads[k]
    if button == "triggerleft" or button == "triggerright" then
      if j.getGamepadAxis then
        local ok, v = pcall(j.getGamepadAxis, j, button)
        if ok and type(v) == "number" and v >= GamepadMap.TRIGGER_ON then return true end
      end
    elseif button == "leftstick_up" or button == "leftstick_down"
        or button == "leftstick_left" or button == "leftstick_right"
        or button == "rightstick_up" or button == "rightstick_down"
        or button == "rightstick_left" or button == "rightstick_right" then
      if j.getGamepadAxis then
        local axisPrefix = button:sub(1, 9) == "leftstick" and "left" or "right"
        local isY = (button:sub(-2) == "up" or button:sub(-4) == "down")
        local axis = axisPrefix .. (isY and "y" or "x")
        local ok, v = pcall(j.getGamepadAxis, j, axis)
        if ok and type(v) == "number" then
          if button:sub(-2) == "up" and v <= -STICK_ON then return true
          elseif button:sub(-4) == "down" and v >= STICK_ON then return true
          elseif button:sub(-4) == "left" and v <= -STICK_ON then return true
          elseif button:sub(-5) == "right" and v >= STICK_ON then return true
          end
        end
      end
    else
      local ok, down = pcall(j.isGamepadDown, j, button)
      if ok and down then return true end
    end
  end
  return false
end

-- a joystick was added or removed: rebuild pollPads' list on the next poll
function Input:joysticksChanged()
  self._pollPads = nil
end

-- pokefirered/src/main.c:296
function Input:pollPads()
  local js = love and love.joystick
  if not (js and js.getJoystickCount and js.getJoysticks) then return end
  local okC, count = pcall(js.getJoystickCount)
  if not okC or type(count) ~= "number" or count == 0 then
    self._pollPadCount = 0
    return
  end
  local pads = self._pollPads
  -- The count alone cannot see one controller swapped for another between
  -- two polls; a cached pad that has gone away forces the rebuild too (and
  -- main.lua's joystickadded/removed drop the cache via
  -- Input:joysticksChanged).
  local stale = not pads or self._pollPadCount ~= count
  if not stale then
    for k = 1, #pads do
      local j = pads[k]
      if j.isConnected then
        local okConn, connected = pcall(j.isConnected, j)
        if okConn and not connected then
          stale = true
          break
        end
      end
    end
  end
  if stale then
    pads = {}
    local ok, list = pcall(js.getJoysticks)
    if ok and type(list) == "table" then
      for _, j in ipairs(list) do
        if j.isGamepadDown and GamepadMap.ignoreRawForJoystick(j)
            and not GamepadMap.isAccelerometer(j) then
          pads[#pads + 1] = j
        end
      end
    end
    self._pollPads = pads
    self._pollPadCount = count
  end
  local list = self.padPoll
  if #pads == 0 or not list then return end
  local mute = self.captureArmed or modOwnsPad()
  local suppress = self.padSuppress
  if not suppress then
    suppress = {}
    self.padSuppress = suppress
  end
  local backDown = nil
  local minimized = nil
  for i = 1, #list do
    local e = list[i]
    local down = anyPadDown(pads, e.button)
    local sources = self.sources[e.btn]
    local held = sources ~= nil and sources[e.source] == true
    if not down then suppress[e.button] = nil end
    if down and not held and minimized == nil then
      minimized = PadHints.windowMinimized()
    end
    if held and not down then
      release(self, e.btn, e.source)
      notePadRepair("release", e.button)
    elseif down and not held and not mute and not minimized and not suppress[e.button]
        and not self:padAction(e.button, self.shoulderGameplay) then
      if e.chord and backDown == nil then
        backDown = self.state.select == true or anyPadDown(pads, "back")
      end
      if not (e.chord and backDown) then
        press(self, e.btn, e.source)
        notePadRepair("press", e.button)
      end
    end
  end
end

-- step's two per-step tables are recycled rather than reallocated, but only
-- while they are still the ones step itself installed: a test or driver that
-- assigns its own `pressed` / `pressQueue` gets a fresh table afterwards,
-- exactly as before, and never sees its own table emptied.
local function ownedCleared(self, field, ownKey)
  local own = self[ownKey]
  if own ~= nil and self[field] == own then
    for k in pairs(own) do own[k] = nil end
  else
    own = {}
    self[ownKey] = own
  end
  self[field] = own
end

function Input:step()
  self:pollPads()
  ownedCleared(self, "pressed", "_ownPressed")
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
  ownedCleared(self, "pressQueue", "_ownPressQueue")
  -- pokefirered/src/main.c:325
  local aliases = self.aliases
  local held = nil
  if aliases then
    for src, dst in pairs(aliases) do
      if self.pressed[src] then self.pressed[dst] = true end
      if self.state[src] then
        held = held or {}
        held[dst] = true
      end
    end
  end
  self.aliasHeld = held
end

-- The on-screen touch overlay (src/core/TouchControls.lua) presses GB
-- buttons directly by name -- not through a keyboard alias -- so a player
-- rebind can never detach or shadow the overlay.
function Input:overlayPressed(btn)
  noteCapture(self, "touch", "pressed", btn)
  press(self, btn, "touch:" .. btn)
end

function Input:overlayReleased(btn)
  noteCapture(self, "touch", "released", btn)
  release(self, btn, "touch:" .. btn)
end

-- Programmatic mod input (#807).  mod.input taps and holds land here under
-- loader-issued "mod:<id>:<n>" source names, riding the same per-source
-- bookkeeping as every physical path above, so releasing one can never
-- clear a hold a key, stick, hat, the overlay, or another mod still owns.
-- A tap is a sourcePress immediately followed by its sourceRelease: the
-- queued edge survives into the next step, and the emptied source map
-- keeps the hold from being revived (see Input:step's sources == {} rule).
function Input:sourcePress(btn, source)
  press(self, btn, source)
end

function Input:sourceRelease(btn, source)
  release(self, btn, source)
end

function Input:gamepadpressed(joystick, button)
  button = GamepadMap.normalizePad and GamepadMap.normalizePad(button) or GamepadMap.TRIGGER_AXES[button] or button
  if self.padSuppress then self.padSuppress[button] = nil end
  noteCapture(self, "pad", "pressed", button)
  local btn = self.padBindings[button] or (self.effectiveStickBindings and self.effectiveStickBindings[button])
  if btn and not self:padAction(button, self.shoulderGameplay) then
    press(self, btn, "pad:" .. button)
  end
end

function Input:gamepadreleased(joystick, button)
  button = GamepadMap.normalizePad and GamepadMap.normalizePad(button) or GamepadMap.TRIGGER_AXES[button] or button
  noteCapture(self, "pad", "released", button)
  local pads = self._pollPads
  if joystick and pads and #pads > 1 and self.padPollSet and self.padPollSet[button]
      and anyPadDown(pads, button) then
    return
  end
  local source = "pad:" .. button
  for btn, sources in pairs(self.sources) do
    if sources[source] then release(self, btn, source) end
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
-- Gate: GamepadMap.ignoreRawForJoystick (pcall-safe isGamepad check).

function Input:joystickpressed(joystick, button)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
  noteCapture(self, "joy", "pressed", button)
  local btn = self.joyBindings[button]
  if btn then press(self, btn, "joy:" .. button) end
end

function Input:joystickreleased(joystick, button)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
  noteCapture(self, "joy", "released", button)
  local btn = self.joyBindings[button]
  if btn then release(self, btn, "joy:" .. button) end
end

function Input:triggerAxis(axis, value)
  local name = GamepadMap.TRIGGER_AXES[axis]
  if not name then return nil end
  self.triggerHeld = self.triggerHeld or {}
  local was = self.triggerHeld[name]
  if not was and value >= GamepadMap.TRIGGER_ON then
    self.triggerHeld[name] = true
    return name, "pressed"
  elseif was and value <= GamepadMap.TRIGGER_OFF then
    self.triggerHeld[name] = nil
    return name, "released"
  end
  return name
end

function Input:stickAxisEvents(axis, value, joystick)
  local isLeft = (axis == "leftx" or axis == "lefty")
  local isRight = (axis == "rightx" or axis == "righty")
  if not isLeft and not isRight then return nil end

  local prefix = isLeft and "leftstick" or "rightstick"
  local stateKey = isLeft and "stickAxis" or "rightStickAxis"
  local dirKey = isLeft and "stickDir" or "rightStickDir"
  local ownerKey = isLeft and "stickOwner" or "rightStickOwner"
  local owner = self[ownerKey]
  if self[dirKey] and owner ~= nil and joystick ~= nil and owner ~= joystick then return nil end

  self[stateKey] = self[stateKey] or { x = 0, y = 0 }
  if axis:sub(-1) == "x" then
    self[stateKey].x = value
  else
    self[stateKey].y = value
  end

  local x, y = self[stateKey].x, self[stateKey].y
  local ax, ay = math.abs(x), math.abs(y)
  local currentDir = self[dirKey]
  local newDir = currentDir

  if ax > STICK_ON or ay > STICK_ON then
    if ax >= ay then
      newDir = x > 0 and "right" or "left"
    else
      newDir = y > 0 and "down" or "up"
    end
  elseif ax < STICK_OFF and ay < STICK_OFF then
    newDir = nil
  end

  if newDir == currentDir then return nil end

  self[dirKey] = newDir
  self[ownerKey] = newDir and joystick or nil
  local events = {}
  if currentDir then
    events[#events + 1] = { phase = "released", button = prefix .. "_" .. currentDir }
  end
  if newDir then
    events[#events + 1] = { phase = "pressed", button = prefix .. "_" .. newDir }
  end
  return events
end

function Input:gamepadaxis(joystick, axis, value)
  local trigger, phase = self:triggerAxis(axis, value)
  if trigger then
    if phase == "pressed" then
      self:gamepadpressed(joystick, trigger)
    elseif phase == "released" then
      self:gamepadreleased(joystick, trigger)
    end
    return
  end
  local events = self:stickAxisEvents(axis, value, joystick)
  if events then
    for i = 1, #events do
      local ev = events[i]
      if ev.phase == "pressed" then
        self:gamepadpressed(joystick, ev.button)
      elseif ev.phase == "released" then
        self:gamepadreleased(joystick, ev.button)
      end
    end
    return
  end
end

function Input:joystickaxis(joystick, axis, value)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
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
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
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

-- Lifecycle resets (focus/visibility flips, joystick add/remove, resume)
-- wipe held state because a release can be swallowed while the OS owns the
-- event stream.  A direction the player is STILL holding never re-fires
-- keypressed/gamepadpressed after the wipe either, so a spurious reset --
-- macOS re-enumerating a Bluetooth pad fires joystickadded with no hotplug,
-- and the blanket reset took unrelated keyboard holds down with it --
-- parked the player in place until every direction was released and
-- pressed again (#799).  Rebuild holds from the devices' ground truth
-- instead: only what is physically down right now comes back, so the
-- swallowed-release hazards the resets guard against stay cleared.
-- Deliberately separate from reset(): the soft-reset chord path in
-- Game:step needs the clean slate (re-arming A there would read it as a
-- title-menu choice).
function Input:reconcile()
  local okD, Diag = pcall(require, "src.debug.SwitchDiagnostics")
  if okD and Diag.onPadReconcile then pcall(Diag.onPadReconcile) end
  local kb = love and love.keyboard
  if kb and kb.isDown then
    for key, btn in pairs(self.keyBindings) do
      local ok, down = pcall(kb.isDown, key)
      if ok and down then press(self, btn, "key:" .. key) end
    end
  end
  local js = love and love.joystick
  if not (js and js.getJoysticks) then return end
  local ok, joysticks = pcall(js.getJoysticks)
  if not ok or type(joysticks) ~= "table" then return end
  for _, j in ipairs(joysticks) do
    if GamepadMap.isAccelerometer(j) then
    elseif GamepadMap.ignoreRawForJoystick(j) then
      -- SDL-recognized pad: buttons + left stick, the gamepad surfaces
      if j.isGamepadDown then
        for button, btn in pairs(self.padBindings) do
          local ok2, down = pcall(j.isGamepadDown, j, button)
          if ok2 and down and not self:padAction(button, self.shoulderGameplay) then
            press(self, btn, "pad:" .. button)
          end
        end
      end
      if j.getGamepadAxis then
        local axes = { "leftx", "lefty", "rightx", "righty", "triggerleft", "triggerright" }
        for _, axis in ipairs(axes) do
          local ok2, v = pcall(j.getGamepadAxis, j, axis)
          if ok2 and type(v) == "number" then self:gamepadaxis(j, axis, v) end
        end
      end
    else
      -- raw stick (#620/#632): the surfaces the joystick* events feed
      if j.isDown then
        for index, btn in pairs(self.joyBindings) do
          local ok2, down = pcall(j.isDown, j, index)
          if ok2 and down then press(self, btn, "joy:" .. index) end
        end
      end
      if j.getAxis then
        for _, axis in ipairs({ 1, 2 }) do
          local ok2, v = pcall(j.getAxis, j, axis)
          if ok2 and type(v) == "number" then self:joystickaxis(j, axis, v) end
        end
      end
      if j.getHatCount and j.getHat then
        local ok2, count = pcall(j.getHatCount, j)
        for hat = 1, (ok2 and count) or 0 do
          local ok3, dir = pcall(j.getHat, j, hat)
          if ok3 and dir then self:joystickhat(j, hat, dir) end
        end
      end
    end
  end
end

-- pokefirered/src/main.c:325
function Input:isDown(btn)
  if self.state[btn] then return true end
  local held = self.aliasHeld
  return (held and held[btn]) or false
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
