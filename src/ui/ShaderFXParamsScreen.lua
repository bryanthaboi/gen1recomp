-- Per-preset #pragma parameter editor, reached via SELECT on a converted row in
-- ShaderFXScreen. A steps and wraps, Left/Right step and clamp, SELECT resets
-- one row, START resets all. Edits are keyed by preset name, not by slot.
-- See docs/shaderfx.md.

local ListMenu = require("src.ui.ListMenu")
local ChoiceBox = require("src.ui.ChoiceBox")
local ShaderFX = require("src.render.ShaderFX")
local Strings = require("src.core.Strings")
local Logger = require("src.core.Logger")

local ShaderFXParamsScreen = setmetatable({}, { __index = ListMenu })
ShaderFXParamsScreen.__index = ShaderFXParamsScreen

local function overridesFor(game, entry)
  local opts = game.save and game.save.options
  local all = opts and opts.shaderfxParams
  return all and all[entry.name]
end

local function currentValue(p, overrides)
  local v = overrides and overrides[p.id]
  if v == nil then v = p.initial end
  return v
end

-- Trims trailing zeros but always keeps one decimal place: many real pragma
-- steps are 0.01-0.05, which a fixed-width format would hide.
local function fmt(v)
  local s = ("%.3f"):format(v)
  s = s:gsub("(%..-)0+$", "%1"):gsub("%.$", ".0")
  return s
end

local function buildItems(game, entry, params)
  local overrides = overridesFor(game, entry)
  local items = {}
  for _, p in ipairs(params) do
    items[#items + 1] = {
      label = Strings(p.description), param = p,
      right = fmt(currentValue(p, overrides)),
    }
  end
  return items
end

function ShaderFXParamsScreen.new(game, entry)
  local params, err = ShaderFX.listParams(entry)
  if not params then
    Logger.error("ShaderFXParamsScreen: %s: %s", entry.name, tostring(err))
    params = {}
  end
  local items = buildItems(game, entry, params)
  local title = Strings((entry.name:gsub("%.slangp$", "")))

  local self = setmetatable(ListMenu.new(game, title, items, {
    rows = 6,
    footer = Strings("A/L/R:STEP\nSELECT:RESET  START:ALL"),
  }), ShaderFXParamsScreen)

  -- Re-activates whichever slot(s) currently show this preset, so an edit
  -- reaches the running chain by the next frame. Cheap enough to call on every
  -- step: activate() re-reads the cached artifact, it never calls the bridge.
  local function applyLive(overrides)
    for _, slot in ipairs(ShaderFX.SLOTS) do
      local active = ShaderFX.activeEntry(slot)
      if active and active.name == entry.name then
        ShaderFX.activate(slot, active, overrides)
      end
    end
  end

  local function setParam(item, value)
    local p = item.param
    value = math.max(p.minimum, math.min(p.maximum, value))
    local opts = game.save and game.save.options
    if not opts then return end
    opts.shaderfxParams = opts.shaderfxParams or {}
    opts.shaderfxParams[entry.name] = opts.shaderfxParams[entry.name] or {}
    opts.shaderfxParams[entry.name][p.id] = value
    item.right = fmt(value)
    applyLive(opts.shaderfxParams[entry.name])
    if game.writeOptions then
      game:writeOptions()
    elseif game.persistOptions then
      game:persistOptions()
    end
  end

  self.onChoose = function(item)
    local overrides = overridesFor(game, entry)
    local cur = currentValue(item.param, overrides)
    local nextVal = cur + item.param.step
    if nextVal > item.param.maximum + 1e-6 then nextVal = item.param.minimum end
    setParam(item, nextVal)
  end
  self.onSelectKey = function(item)
    setParam(item, item.param.initial)
  end

  -- dir=-1/+1; clamps at the ends instead of onChoose's wrap.
  local function stepCurrent(dir)
    local item = self.items[self.index]
    if not item then return end
    local overrides = overridesFor(game, entry)
    local cur = currentValue(item.param, overrides)
    setParam(item, cur + dir * item.param.step)
  end

  -- One write + one applyLive for the whole preset, not one per row.
  local function resetAll()
    local opts = game.save and game.save.options
    if not opts then return end
    opts.shaderfxParams = opts.shaderfxParams or {}
    local ov = {}
    opts.shaderfxParams[entry.name] = ov
    for _, item in ipairs(items) do
      local v = item.param.initial
      ov[item.param.id] = v
      item.right = fmt(v)
    end
    applyLive(ov)
    if game.writeOptions then
      game:writeOptions()
    elseif game.persistOptions then
      game:persistOptions()
    end
  end

  -- START: confirm, then reset every row.
  local function confirmResetAll()
    local hint = self.footer
    self.footer = Strings("RESET ALL PARAMS?")
    game.stack:push(ChoiceBox.new(game, function(yes)
      self.footer = hint
      if yes then resetAll() end
    end, { defaultNo = true }))
  end

  local baseUpdate = ListMenu.update
  self.update = function(self_, dt)
    local input = self_.game.input
    if #self_.items > 0 then
      if input:wasPressed("left") then
        stepCurrent(-1)
        return
      elseif input:wasPressed("right") then
        stepCurrent(1)
        return
      elseif input:wasPressed("start") then
        confirmResetAll()
        return
      end
    end
    baseUpdate(self_, dt)
  end

  return self
end

return ShaderFXParamsScreen
