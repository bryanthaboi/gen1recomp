-- The SHADER FX preset picker: OFF, every .slangp ShaderFX.list() finds, then a
-- permanent DOWNLOAD SHADERS action row. `slot` picks which of ShaderFX.SLOTS
-- A activates and which save.options key persists it. See docs/shaderfx.md.

local ListMenu = require("src.ui.ListMenu")
local ShaderFX = require("src.render.ShaderFX")
local Strings = require("src.core.Strings")
local Screens = require("src.ui.Screens")

local ShaderFXScreen = setmetatable({}, { __index = ListMenu })
ShaderFXScreen.__index = ShaderFXScreen

-- OFF plus the preset's display name with its extension stripped.
local function label(entry)
  if not entry then return Strings("OFF") end
  return Strings((entry.name:gsub("%.slangp$", "")))
end

-- One row's display state from its entry.converted, shared by new() and
-- onChoose() so a successful convert updates a row exactly as building it did.
local function applyRowState(item)
  if not item.entry then return end
  -- NOT `cond and a or b`: that idiom breaks when `a` is itself nil/false.
  if item.entry.converted then
    item.muted = false
    item.right = nil
  else
    item.muted = true
    item.right = Strings("CONVERT")
  end
end

-- OFF, every real preset, then the permanent DOWNLOAD SHADERS action row.
local function buildItems(active)
  local items = { { label = label(nil), entry = nil } }
  local selected = 1
  for _, entry in ipairs(ShaderFX.list()) do
    local item = { label = label(entry), entry = entry }
    applyRowState(item)
    items[#items + 1] = item
    if active and active.name == entry.name then selected = #items end
  end
  items[#items + 1] = { label = Strings("DOWNLOAD SHADERS"), download = true }
  return items, selected
end

-- `slot` defaults to "main" so a caller that still pushes this screen with no
-- argument keeps today's behavior rather than erroring on a nil slot key.
function ShaderFXScreen.new(game, slot)
  slot = slot or "main"
  local optKey = ShaderFX.OPTION_KEY[slot]
  local title = (slot == "secondary") and "SHADER FX 2" or "SHADER FX"
  local items, selected = buildItems(ShaderFX.activeEntry(slot))

  local self = setmetatable(ListMenu.new(game, title, items, {
    -- 7 rows leaves the title line and the one-line footer hint free.
    rows = 7,
    footer = Strings("SELECT:EDIT PARAMS"),
  }), ShaderFXScreen)
  -- Opens on the active preset (or OFF).
  self.index = selected
  self.downloadJob = nil

  -- Rebuilds from ShaderFX.list() (e.g. after an install adds presets), keeping
  -- the cursor on the same row index (clamped) rather than resetting to OFF.
  local function refresh()
    local newItems = buildItems(ShaderFX.activeEntry(slot))
    self.items = newItems
    self.index = math.max(1, math.min(self.index, #newItems))
  end

  -- Polls the in-flight buildbot download alongside ListMenu's own input
  -- handling. installDownloaded() itself is synchronous, a sub-second job.
  local baseUpdate = ListMenu.update
  self.update = function(self_, dt)
    if self_.downloadJob then
      local st = ShaderFX.downloadStatus(self_.downloadJob)
      local row = self_.items[#self_.items]
      if st.status == "pending" then
        local pct = st.progress and (" %d%%"):format(st.progress * 100) or ""
        row.right = Strings("...") .. pct
      elseif st.status == "ok" then
        local copied, err, unchanged = ShaderFX.installDownloaded(st.notModified)
        self_.downloadJob = nil
        if unchanged then
          require("src.core.Logger").info("ShaderFXScreen: buildbot presets already up to date")
          row.right = Strings("UP TO DATE")
        elseif copied then
          require("src.core.Logger").info("ShaderFXScreen: buildbot install copied %d files", copied)
          refresh()
        else
          require("src.core.Logger").error("ShaderFXScreen: buildbot install failed: %s", tostring(err))
          self_.items[#self_.items].right = Strings("FAILED")
        end
      else -- "error" or "cancelled"
        self_.downloadJob = nil
        require("src.core.Logger").error("ShaderFXScreen: buildbot download failed: %s", tostring(st.err))
        row.right = Strings("FAILED")
      end
    end
    baseUpdate(self_, dt)
  end

  self.onChoose = function(item)
    if item.download then
      -- Ignore a repeat press while one is already in flight.
      if self.downloadJob then return end
      self.downloadJob = ShaderFX.downloadPresets()
      item.right = Strings("...")
      return
    end

    -- A on an unconverted preset converts it in place instead of activating;
    -- the screen stays open either way, since a convert is not a selection.
    if item.entry and not item.entry.converted then
      local ok, err = ShaderFX.convert(item.entry)
      if not ok then
        require("src.core.Logger").error("ShaderFXScreen: convert failed for %s: %s",
          item.entry.name, tostring(err))
      end
      applyRowState(item)
      if not ok then item.right = Strings("FAILED") end
      return
    end

    local opts = game.save and game.save.options
    if not item.entry then
      ShaderFX.deactivate(slot)
      if opts then opts[optKey] = nil end
    else
      -- isConverted() is existence-only with no staleness check, so an explicit
      -- selection always reconverts. Human-paced, CPU-only, never per frame.
      local convOk, convErr = ShaderFX.convert(item.entry)
      if not convOk then
        require("src.core.Logger").error("ShaderFXScreen: reconvert failed for %s: %s",
          item.entry.name, tostring(convErr))
      end
      local overrides = opts and opts.shaderfxParams and opts.shaderfxParams[item.entry.name]
      local ok = ShaderFX.activate(slot, item.entry, overrides)
      if opts then opts[optKey] = ok and item.entry.name or nil end
    end
    if game.writeOptions then
      game:writeOptions()
    elseif game.persistOptions then
      game:persistOptions()
    end
    self:close()
  end

  -- SELECT on a real, converted row opens its pragma-parameter editor; OFF, the
  -- action row and an unconverted preset have nothing to read metadata from.
  self.onSelectKey = function(item)
    if not item.entry or item.download or not item.entry.converted then return end
    Screens.push(game, "ShaderFXParamsScreen", item.entry)
  end

  return self
end

return ShaderFXScreen
