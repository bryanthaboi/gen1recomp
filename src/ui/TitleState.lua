-- Spanish Red/Blue title-screen wrapper.
-- Keep the upstream title implementation intact and only change how the
-- localized Version_GFX ribbon is treated. The importer extracts the ribbon
-- from the active Spanish ROM into its own version cache.
local Original = require("src.ui.TitleStateOriginal")
local GameVersion = require("src.core.GameVersion")

local TitleState = {}
for key, value in pairs(Original) do
  TitleState[key] = value
end

function TitleState.new(game, opts)
  local self = Original.new(game, opts)
  if GameVersion.isSpanish() then
    -- The Spanish ROM's Version_GFX is a complete 80x8 ribbon, so draw it as
    -- one continuous image instead of slicing it into the English layout.
    self.versionFull = true
  end
  return self
end

return TitleState
