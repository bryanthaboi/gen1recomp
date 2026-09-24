local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")

local PAL = Theme.PAL

local InvitePicker = {}

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end

function InvitePicker.draw(imp, m)
  local OnlinePanel = OP()
  local pick = type(imp) == "table" and imp._invitePicker or nil
  if not pick then return false end
  local player = pick.player or {}
  local list = pick.activities or {}
  local pad = math.floor(18 * m.s)
  local gap = math.floor(8 * m.s)
  local w = math.floor(360 * m.s)
  local btnH = math.max(m.btnH, Kit.tapMin())
  local sub = player.game or ""
  if player.where and player.where ~= "" then
    sub = sub .. "  " .. player.where
  end
  local n = math.max(1, #list)
  local h = pad + Kit.textHeight("button") + gap + Kit.textHeight("small") + gap
    + n * (btnH + gap) + btnH + pad
  local px, py, pw = LV().modalPanel(m, w, h)
  local x = px + pad
  local innerW = pw - 2 * pad
  local cy = py + pad
  Kit.textBold("button", Kit.ellipsize("button",
    Strings("Invite %s", tostring(player.name or "?")), innerW), x, cy,
    PAL.heading)
  cy = cy + Kit.textHeight("button") + gap
  Kit.text("small", Kit.ellipsize("small", sub, innerW), x, cy, PAL.muted)
  cy = cy + Kit.textHeight("small") + gap
  if #list == 0 then
    Kit.emptyBox(x, cy, innerW, btnH,
      Strings("Nothing you can invite them to yet."))
    cy = cy + btnH + gap
  end
  for i, activity in ipairs(list) do
    local label = OnlinePanel.ACTIVITY_LABEL[activity] or activity
    local key = "online-invite-pick-" .. activity
    LV().btn(imp, x, cy, innerW, btnH, key, Strings(label),
      { kind = i == 1 and "primary" or "ghost", font = "small",
        action = function() OnlinePanel.startInvite(imp, player, activity) end })
    cy = cy + btnH + gap
  end
  LV().btn(imp, x, cy, innerW, btnH, "online-invite-cancel", Strings("Cancel"),
    { kind = "ghost", font = "small",
      action = function() OnlinePanel.invitePickerClose(imp) end })
  return true
end

return InvitePicker
