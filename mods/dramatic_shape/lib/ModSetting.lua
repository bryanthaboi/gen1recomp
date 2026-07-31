-- One of this mod's own settings: a ladder of values, where it persists,
-- and the row the player cycles it on.
--
-- The engine gives a render pipeline all of this for free -- ladder,
-- options row, hotkey, persistence -- but only to something that OWNS a
-- pass of the frame. The voxel wireframe and the world curve do not: they
-- parameterise the voxel pass, so they have nothing to put in drawWorld or
-- present and the registry rightly rejects them. What is left is a plain
-- mod setting, and this is the boilerplate two of them would otherwise
-- each carry a copy of:
--
--   options:define   a home in options.modOptions.DRAMATIC_SHAPE, plus a row
--                    on this mod's page in the mod manager.
--   ui.options.rows  the same setting on the OPTIONS menu, where the
--                    player already goes for VOXEL and T-SHIFT.
--
-- Both rows read and write the one stored value, so they cannot disagree.
-- Writing mirrors what the manager's own page does (ManagerState:setOption):
-- the live save's options table, the loader's copy that mod.options:get
-- reads, and then the file.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = {}
ModSetting.__index = ModSetting

local function modId()
  local mod = V.mod
  return (mod and mod.id) or "DRAMATIC_SHAPE"
end

-- `values` are the stored values in ladder order and `labels` what the row
-- shows for each; values[1] is the default, and the one an unreadable or
-- unrecognised stored value falls back to.
function ModSetting.new(key, label, values, labels)
  return setmetatable({
    key = key, label = label, values = values, labels = labels,
    index = nil,          -- nil = not yet read back from the persisted options
  }, ModSetting)
end

local function indexOf(self, value)
  for i, v in ipairs(self.values) do
    if v == value then return i end
  end
  return 1
end

-- What the player left it at last session. Read lazily rather than at load
-- time: the loader fills modOptions before a mod runs, but reading through
-- the API keeps this honest about where the value lives.
function ModSetting:read()
  if self.index then return self.index end
  local mod = V.mod
  local value
  if mod and mod.options then
    local ok, got = pcall(mod.options.get, mod.options, self.key)
    if ok then value = got end
  end
  self.index = indexOf(self, value)
  return self.index
end

function ModSetting:get()
  return self.values[self:read()]
end

function ModSetting:level()
  return self:read() - 1
end

function ModSetting:setIndex(i, game)
  local n = #self.values
  i = ((i - 1) % n + n) % n + 1
  self.index = i
  local value, id = self.values[i], modId()
  local opts = game and game.save and game.save.options
  if opts then
    opts.modOptions = opts.modOptions or {}
    opts.modOptions[id] = opts.modOptions[id] or {}
    opts.modOptions[id][self.key] = value
  end
  local loader = game and game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[id] = loader.modOptions[id] or {}
    loader.modOptions[id][self.key] = value
  end
  if game and game.writeOptions then pcall(game.writeOptions, game) end
  return value
end

function ModSetting:cycle(game, dir)
  return self:setIndex(self:read() + (dir or 1), game)
end

-- Adopt a value set from somewhere else (the mod manager's settings page,
-- which writes and persists on its own). Nothing to store: just move the
-- cached index so the next read agrees with it.
function ModSetting:sync(value)
  self.index = indexOf(self, value)
end

-- The descriptor src/ui/OptionRows.lua renders, in the shape the
-- ui.options.rows hook appends.
function ModSetting:row()
  local self_ = self
  return {
    id = "DRAMATIC_SHAPE:" .. self.key,
    label = self.label,
    value = function() return self_.labels[self_:read()] end,
    step = function(game, dir)
      self_:cycle(game, dir)
      return true
    end,
  }
end

-- The row the mod manager's own settings page builds for this mod.
function ModSetting:schema(help)
  local choices = {}
  for i, v in ipairs(self.values) do choices[i] = { self.labels[i], v } end
  if #self.values == 2 and self.values[1] == false then
    return { key = self.key, type = "toggle", label = self.label,
             default = self.values[1], help = help }
  end
  return { key = self.key, type = "choice", label = self.label,
           choices = choices, default = self.values[1], help = help }
end

return ModSetting
