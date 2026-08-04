-- Rebinding over the logical Game Boy buttons (gap C2's file-12 half,
-- 12-ui-extensibility 4.4): one row per button, A arms a "PRESS A BUTTON"
-- capture and the captured key or pad button lands in
-- save.options.bindings, which Input:applyBindings layers over its fixed
-- default map (see src/core/Input.lua and Game:applyOptions).

local Font = require("src.render.Font")
local ListMenu = require("src.ui.ListMenu")
local ChoiceBox = require("src.ui.ChoiceBox")
local Input = require("src.core.Input")
local Strings = require("src.core.Strings")

local BindingsMenu = setmetatable({}, { __index = ListMenu })
BindingsMenu.__index = BindingsMenu

-- Input.lua's map, primary key first where several keys share a button.
-- `pad` mirrors DEFAULT_GAMEPAD_BINDINGS in src/core/Input.lua row for
-- row; keep the two in sync.  Every row shows its key and pad so the
-- controller side is discoverable (#73, #589), and the swap in
-- storeBinding leans on each row holding a value in both slots.
local BUTTONS = {
  { id = "up", label = "UP", key = "up", pad = "dpup" },
  { id = "down", label = "DOWN", key = "down", pad = "dpdown" },
  { id = "left", label = "LEFT", key = "left", pad = "dpleft" },
  { id = "right", label = "RIGHT", key = "right", pad = "dpright" },
  { id = "a", label = "A", key = "z", pad = "a" },
  { id = "b", label = "B", key = "x", pad = "b" },
  { id = "start", label = "START", key = "escape", pad = "start" },
  { id = "select", label = "SELECT", key = "tab", pad = "back" },
}

-- a binding is a plain key string or { key, pad }; absent = the fixed
-- map, so a vanilla save renders today's keys byte-identically
local function boundKey(overlay, def)
  local b = overlay and overlay[def.id]
  if type(b) == "table" then return b.key or def.key end
  if type(b) == "string" then return b end
  return def.key
end

local function boundPad(overlay, def)
  local b = overlay and overlay[def.id]
  if type(b) == "table" and b.pad then return b.pad end
  return def.pad
end

-- The right column is KEY/PAD (e.g. "Z/A").  The row is 20 tiles and the
-- widest label ("SELECT") ends at x=64, so each half is clamped to 5
-- glyphs: 5+1+5 right-aligned at x=152 starts no further left than x=64.
-- SDL names longer than 5 get a fixed short form before the clamp.
local KEY_SHORT = {
  escape = "ESC", backspace = "BKSP", ["return"] = "ENTER",
  kpenter = "ENTER", space = "SPACE",
}
local PAD_SHORT = {
  dpup = "D-UP", dpdown = "D-DN", dpleft = "D-LT", dpright = "D-RT",
  leftshoulder = "LB", rightshoulder = "RB",
  leftstick = "LS", rightstick = "RS", guide = "GUIDE",
}
local function shortName(name, shorts)
  local s = shorts[name]
  if s then return s end
  s = name:upper()
  return #s > 5 and s:sub(1, 5) or s
end

-- Right column for every row: effective key and pad together, so a
-- controller player can read the whole map without a second legend (#589).
local function boundRight(overlay, def)
  local key = shortName(boundKey(overlay, def), KEY_SHORT)
  local pad = boundPad(overlay, def)
  if pad then return key .. "/" .. shortName(pad, PAD_SHORT) end
  return key
end

function BindingsMenu.new(game)
  local overlay = game.save and game.save.options
                  and game.save.options.bindings
  local items = {}
  for i, def in ipairs(BUTTONS) do
    -- translated here, not in ROWS: that table is built at require
    -- time, before Strings.load has a catalog to look in
    items[i] = { label = Strings(def.label),
                 right = boundRight(overlay, def), button = def }
  end
  local self = setmetatable(ListMenu.new(game, "CONTROLS", items, {
    -- 6 rows leaves the bottom two lines free for the hint; a clear or
    -- reset nobody can see on screen may as well not exist (#589)
    rows = 6,
    footer = Strings("SELECT:CLEAR ROW\nSTART:RESET ALL"),
  }), BindingsMenu)
  self.onChoose = function(item) self:beginCapture(item) end
  -- SELECT deletes one row's rebind: dropping the overlay entry is enough
  -- because Input:applyBindings rebuilds the whole map from the defaults
  -- on every call (#589)
  self.onSelectKey = function(item) self:clearBinding(item) end
  -- A rebind reaches Input only when this screen closes (#510).  The menu
  -- steers by the live map, so applying "B = Z" the instant it was captured
  -- turned the player's next confirm press into a cancel and shut the
  -- screen mid-swap.  options.bindings is still written immediately, and
  -- Game:applyOptions re-applies it on load, so a close that skips this
  -- hook still ends up with the saved map.
  self.onCancel = function() self:commitBindings() end
  return self
end

-- Cross-file contract with src/core/Input.lua: the saved overlay reaches
-- the live map here, on close, and nowhere else in this screen.
function BindingsMenu:commitBindings()
  local game = self.game
  local opts = game and game.save and game.save.options
  if opts then Input:applyBindings(opts.bindings) end
end

-- The capture handlers are per-instance slots, so Game's raw-input
-- routing only ever sees this screen while a capture is armed.  A capture
-- no longer commits on the press: it commits when that press is RELEASED,
-- and a second key or pad button going down while the first is still held
-- cancels instead.  That gives a bare controller a way to back out of an
-- armed row, where Escape cannot help (#589).
function BindingsMenu:beginCapture(item)
  self.capture = item
  self.pending = nil
  self.onKeyPressed = BindingsMenu.captureKey
  self.onGamepadPressed = BindingsMenu.capturePad
  self.onJoystickPressed = BindingsMenu.captureJoy
  self.onKeyReleased = BindingsMenu.captureKeyRelease
  self.onGamepadReleased = BindingsMenu.capturePadRelease
  self.onJoystickReleased = BindingsMenu.captureJoyRelease
end

function BindingsMenu:endCapture()
  self.capture = nil
  self.pending = nil
  self.onKeyPressed = nil
  self.onGamepadPressed = nil
  self.onJoystickPressed = nil
  self.onKeyReleased = nil
  self.onGamepadReleased = nil
  self.onJoystickReleased = nil
end

-- Escape is the capture's way out, so it is never captured: every other
-- key is bindable, which otherwise leaves an armed row with no exit but
-- to bind something (#510).  Escape stays START in Input's default map,
-- which no rebind removes, so reserving it costs the player nothing.
function BindingsMenu:captureKey(key)
  if key == "escape" or self.pending then return self:endCapture() end
  self.pending = { slot = "key", value = key }
end

function BindingsMenu:capturePad(button)
  if self.pending then return self:endCapture() end
  self.pending = { slot = "pad", value = button }
end

-- Game forwards every release to Input BEFORE these hooks (see
-- Game:keyreleased): the capture observes releases, it never owns them,
-- so Input's held-state stays honest for keys it saw go down before the
-- capture armed.  A release that does not match the pending input (the
-- press that armed the row, a cancelled capture's stragglers) is noise.
function BindingsMenu:captureKeyRelease(key)
  local p = self.pending
  if p and p.slot == "key" and p.value == key then
    self:storeBinding("key", key)
  end
end

function BindingsMenu:capturePadRelease(button)
  local p = self.pending
  if p and p.slot == "pad" and p.value == button then
    self:storeBinding("pad", button)
  end
end

-- A stick SDL has no game-controller-database entry for reports plain
-- button numbers instead of names, so its capture stores "joyN" in the
-- SAME pad slot every other controller uses (#632).  The row's right
-- column, storeBinding's swap and START's reset-all then need no special
-- case, and src/core/Input.lua's applyBindings is the only place that has
-- to decode the name.  `raw` keeps the two release hooks apart: p.value is
-- "joy3" here and an SDL button name there, so neither can claim the
-- other's release.  Game only routes a raw stick to these hooks, so a
-- recognized pad still records its readable SDL name.
function BindingsMenu:captureJoy(button)
  if self.pending then return self:endCapture() end
  self.pending = { slot = "pad", value = "joy" .. button, raw = true }
end

function BindingsMenu:captureJoyRelease(button)
  local p = self.pending
  if p and p.raw and p.value == "joy" .. button then
    self:storeBinding("pad", p.value)
  end
end

function BindingsMenu:storeBinding(slot, value)
  local item = self.capture
  self:endCapture()
  local game = self.game
  if not (item and value and game.save and game.save.options) then return end
  local opts = game.save.options
  opts.bindings = opts.bindings or {}
  -- Swap, never steal (#589): when the captured input is another row's
  -- effective binding in this slot, that row inherits this row's previous
  -- binding.  Every BUTTONS row has a default in both slots, so `prev`
  -- always exists: no row goes empty and no input serves two rows.
  -- Default key ALIASES (W beside Up, Space beside Z; DEFAULT_BINDINGS in
  -- Input.lua) are not effective bindings, so capturing one costs the
  -- other row a spare alias, never its shown key.
  local effective = (slot == "key") and boundKey or boundPad
  local prev = effective(opts.bindings, item.button)
  if value ~= prev then
    for _, other in ipairs(self.items) do
      if other ~= item and effective(opts.bindings, other.button) == value then
        local ob = opts.bindings[other.button.id]
        if type(ob) ~= "table" then
          ob = { key = type(ob) == "string" and ob or nil }
        end
        ob[slot] = prev
        opts.bindings[other.button.id] = ob
        other.right = boundRight(opts.bindings, other.button)
        break
      end
    end
  end
  local b = opts.bindings[item.button.id]
  if type(b) ~= "table" then
    -- keep a direct-edited plain key string when only the pad changes
    b = { key = type(b) == "string" and b or nil }
  end
  b[slot] = value
  opts.bindings[item.button.id] = b
  item.right = boundRight(opts.bindings, item.button)
  if game.writeOptions then game:writeOptions() end
end

-- SELECT: forget one row's rebind and fall back to the defaults.  #510's
-- deferral still holds: only options change here, the live map catches up
-- in commitBindings on close.
function BindingsMenu:clearBinding(item)
  local game = self.game
  local opts = game and game.save and game.save.options
  if not (opts and opts.bindings and opts.bindings[item.button.id]) then
    return
  end
  opts.bindings[item.button.id] = nil
  item.right = boundRight(opts.bindings, item.button)
  if game.writeOptions then game:writeOptions() end
end

-- START: confirm, then drop the whole overlay (#589).  The footer doubles
-- as the prompt while the YES/NO box is up, the same bottom-line pattern
-- the mart and PC screens use.
function BindingsMenu:confirmReset()
  local game = self.game
  local hint = self.footer
  self.footer = Strings("RESET ALL BINDINGS?")
  game.stack:push(ChoiceBox.new(game, function(yes)
    self.footer = hint
    if not yes then return end
    local opts = game.save and game.save.options
    if opts then opts.bindings = nil end
    for _, it in ipairs(self.items) do
      it.right = boundRight(nil, it.button)
    end
    if game.writeOptions then game:writeOptions() end
  end, { defaultNo = true }))
end

function BindingsMenu:update(dt)
  if self.capture then return end -- the raw capture owns the input
  if self.game.input:wasPressed("start") then
    return self:confirmReset()
  end
  ListMenu.update(self, dt)
end

function BindingsMenu:draw()
  ListMenu.draw(self)
  if self.capture then
    Font.drawBox(1, 6, 18, 6)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("PRESS A BUTTON"), 24, 60)
    Font.draw(Strings("RELEASE TO SET"), 24, 72)
    Font.draw(Strings("ESC/2ND CANCELS"), 24, 84)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return BindingsMenu
