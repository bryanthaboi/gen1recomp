local ScreenPosition = {}

ScreenPosition.MODES = { "center", "upper", "top" }
ScreenPosition.DEFAULT = "center"
ScreenPosition.mode = ScreenPosition.DEFAULT

local LABELS = { center = "CENTER", upper = "UPPER", top = "TOP" }

function ScreenPosition.normalize(v)
  if LABELS[v] then return v end
  return ScreenPosition.DEFAULT
end

function ScreenPosition.label(v)
  return LABELS[ScreenPosition.normalize(v)]
end

function ScreenPosition.cycle(v, dir)
  v = ScreenPosition.normalize(v)
  local modes = ScreenPosition.MODES
  local cur = 1
  for i, mode in ipairs(modes) do
    if mode == v then cur = i break end
  end
  return modes[(cur - 1 + (dir or 1)) % #modes + 1]
end

function ScreenPosition.setMode(v)
  ScreenPosition.mode = ScreenPosition.normalize(v)
end

function ScreenPosition.applyOptions(opts)
  ScreenPosition.setMode(opts and opts.screenPos)
end

function ScreenPosition.safeTop()
  local ok, SafeArea = pcall(require, "src.core.SafeArea")
  if not ok then return 0 end
  local okr, _, y = pcall(SafeArea.rect)
  if not okr then return 0 end
  return math.max(0, tonumber(y) or 0)
end

function ScreenPosition.skinActive(w, h)
  local ok, TouchSkin = pcall(require, "src.core.TouchSkin")
  if not ok or type(TouchSkin.viewport) ~= "function" then return false end
  local okv, x = pcall(TouchSkin.viewport, w, h)
  return okv and x ~= nil
end

function ScreenPosition.lift(viewH, contentH, safeTop)
  if ScreenPosition.mode == "center" then return 0 end
  viewH = tonumber(viewH) or 0
  contentH = tonumber(contentH) or 0
  local slack = viewH - contentH
  if slack <= 0 then return 0 end
  local centered = math.floor(slack / 2)
  local target = ScreenPosition.mode == "top" and 0 or math.floor(slack / 4)
  safeTop = math.floor(tonumber(safeTop) or 0)
  if safeTop > 0 and target < safeTop then
    target = math.min(safeTop, centered)
  end
  return centered - target
end

return ScreenPosition
