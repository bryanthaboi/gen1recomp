local Ops = require("Ops")
local Gen = require("Gen")
local M = {}
local Touch = require("TouchEditor")
local Motion = require("Motion")
local Chooser = require("Chooser")
local function drawView(S, Kit, x, y, w, h)
  local s, pad, gap, row = Kit.scale, 12 * Kit.scale, 8 * Kit.scale, Kit.controlH()
  Kit.card(x, y, w, h)
  Ops.pcItems(S)
  local cx, cy, inner = x + pad, y + pad, w - 2 * pad
  S.itemView = S.itemView or "bag"
  local compact = Kit.desktop or h < 430 * s
  local views = { { "bag", "Bag" }, { "pc", "PC" }, { "wallet", "Wallet" }, { "badges", "Badges" } }
  if compact then
    local addW = Kit.desktop and Kit.buttonWidth("Add", { font = "small" }, row)
      or math.max(row, Kit.textWidth("small", "Add") + 20 * s)
    local toolsW = Kit.desktop and Kit.buttonWidth("Tools", { font = "small", trailingIcon = "chevron-down" }, row)
      or math.max(row, Kit.textWidth("small", "Tools") + 20 * s)
    local viewW = inner - addW - toolsW - 2 * gap
    if Kit.desktop then viewW = math.min(viewW, 240 * s) end
    local toolsX = Kit.desktop and cx + viewW + addW + 2 * gap or cx + inner - toolsW
    Chooser.navigation(S, Kit, "itemView", "Inventory view", views, cx, cy, viewW, row, function()
      S.itemMenu = nil
    end)
    local storage = S.itemView == "bag" or S.itemView == "pc"
    if
      Kit.button(cx + viewW + gap, cy, addW, row, "Add", { font = "small", enabled = storage })
    then
      Ops.openItemPicker(S, Kit, S.itemView)
    end
    if Kit.desktop and storage then
      local dest = S.itemView == "pc" and "pc" or "bag"
      Chooser.actions(S, Kit, "itemTools", "Tools", {
        { id = "max", label = "Max all stacks", icon = "chevrons-up", fn = function(state) Ops[dest .. "MaxAll"](state) end },
        { id = "name", label = "Sort by name", icon = "arrow-up-down", fn = function(state) Ops[dest .. "Sort"](state, "name") end },
        { id = "index", label = "Sort by item number", icon = "list-filter", fn = function(state) Ops[dest .. "Sort"](state, "index") end },
      }, toolsX, cy, toolsW, row)
    elseif
      Kit.button(
        toolsX,
        cy,
        toolsW,
        row,
        "Tools",
        { font = "small", enabled = storage }
      )
    then
      if S.itemMenu == "tools" then
        S.itemMenu = nil
      else
        S.itemMenu = "tools"
      end
      Kit.blur()
    end
    cy = cy + row + gap
  else
    Chooser.navigation(
      S,
      Kit,
      "itemView",
      "Inventory view",
      views,
      cx,
      cy,
      math.min(inner, 360 * s),
      row,
      function()
        S.itemMenu = nil
      end
    )
    cy = cy + row + gap
  end
  if S.itemView == "wallet" then
    local bodyH = math.max(0, y + h - pad - cy)
    S.walletScroll =
      Kit.scrollPixels(cx, cy, inner, bodyH, S.walletScroll or 0, S._walletHeight or 0)
    Kit.pushClip(cx, cy, inner, bodyH)
    local start = cy - S.walletScroll
    cy = start
    local fields = {
      { "money", "Money", Gen.money(S.save), 999999 },
      { "coins", "Coins", Gen.coins(S.save), 9999 },
    }
    if Gen.hasBuenaPoints(S.save, S.version) then
      fields[#fields + 1] = { "buenaPoints", "Buena points", Gen.buenaPoints(S.save, S.version), 30,
        "Blue Card points for Buena's prizes. Choose 0 to 30." }
    end
    if Gen.hasBerryPowder(S.save, S.version) then
      fields[#fields + 1] = { "berryPowder", "Berry Powder", Gen.berryPowder(S.save, S.version),
        Gen.BERRY_POWDER_MAX, "Powder from Berry Crush, spent at the Berry Powder shop. Choose 0 to 99999." }
    end
    if Gen.hasVolcanicAsh(S.save, S.version) then
      fields[#fields + 1] = { "volcanicAsh", "Volcanic Ash", Gen.volcanicAsh(S.save, S.version),
        Gen.VOLCANIC_ASH_MAX, "Ash collected in the Soot Sack, spent at the Glass Workshop. Choose 0 to 9999." }
    end
    if Gen.hasBattlePoints(S.save, S.version) then
      fields[#fields + 1] = { "battlePoints", "Battle Points", Gen.battlePoints(S.save, S.version),
        Gen.BATTLE_POINTS_MAX, "Battle Frontier points, spent at the Exchange Service Corner. Choose 0 to 9999." }
    end
    for _, f in ipairs(fields) do
      cy = cy
        + Touch.value(
          S,
          Kit,
          "wallet-" .. f[1],
          f[2],
          f[3],
          { lo = 0, hi = f[4], help = f[5] or "Max fills it. Type a value for an exact amount." },
          cx,
          cy,
          inner,
          function(v)
            return Ops.setTrainerProperty(S, f[1], v)
          end
        )
        + gap
    end
    S._walletHeight = cy - start
    Kit.popClip()
    return
  elseif S.itemView == "badges" then
    local ids = Ops.badgeIds(S)
    local bc = inner >= 480 * s and 4 or 2
    local bw = (inner - (bc - 1) * gap) / bc
    local bodyH = math.max(0, y + h - pad - cy)
    S.badgeScroll =
      Kit.scrollPixels(cx, cy, inner, bodyH, S.badgeScroll or 0, math.ceil(#ids / bc) * (row + gap))
    Kit.pushClip(cx, cy, inner, bodyH)
    for i, id in ipairs(ids) do
      if
        Kit.chip(
          cx + (i - 1) % bc * (bw + gap),
          cy + math.floor((i - 1) / bc) * (row + gap) - S.badgeScroll,
          bw,
          row,
          id:gsub("BADGE$", ""),
          Gen.hasBadge(S.save, id)
        )
      then
        Ops.toggleBadge(S, id)
      end
    end
    Kit.popClip()
    return
  end
  local pc = S.itemView == "pc"
  local prefix = pc and "pc" or "bag"
  local function call(verb, id, value, slot)
    return Ops[prefix .. verb](S, id, value, slot)
  end
  if not compact then
    local half = (inner - gap) / 2
    if Kit.button(cx, cy, half, row, "Add item", { kind = "good", font = "small" }) then
      Ops.openItemPicker(S, Kit, pc and "pc" or "bag")
    end
    if
      Kit.button(cx + half + gap, cy, half, row, "Max all", { kind = "accent", font = "small" })
    then
      call("MaxAll")
    end
    cy = cy + row + gap
    if Kit.button(cx, cy, half, row, "Sort A-Z", { font = "small" }) then
      call("Sort", "name")
    end
    if Kit.button(cx + half + gap, cy, half, row, "Sort #", { font = "small" }) then
      call("Sort", "index")
    end
    cy = cy + row + gap
  elseif S.itemMenu == "tools" and not Kit.desktop then
    local tools = {
      {
        "Max all",
        function()
          call("MaxAll")
        end,
      },
      {
        "Sort A-Z",
        function()
          call("Sort", "name")
        end,
      },
      {
        "Sort #",
        function()
          call("Sort", "index")
        end,
      },
    }
    local bw = (inner - 2 * gap) / 3
    for i, a in ipairs(tools) do
      if Kit.button(cx + (i - 1) * (bw + gap), cy, bw, row, a[1], { font = "small" }) then
        a[2]()
        S.itemMenu = nil
      end
    end
    return
  end
  local order = Ops.stackRows(S, pc)
  local pagerY = y + h - pad - row
  local bodyH = math.max(0, pagerY - gap - cy)
  -- Reserve the complete confirmation label before arming Drop, so its
  -- button never shrinks or changes the surrounding layout on a second tap.
  local actionMin = Kit.buttonWidth("Confirm?", { font = "small", iconStack = true }, row)
  local actionCols = inner >= 5 * actionMin + 4 * gap and 5 or 3
  local actionRows = math.ceil(5 / actionCols)
  local desktopWidths, desktopActionsW = {}, 4 * gap
  if Kit.desktop then
    for j, label in ipairs({ "Decrease", "Increase", "Max", pc and "Bag" or "PC", "Confirm?" }) do
      desktopWidths[j] = Kit.buttonWidth(label, {
        font = "small", iconOnly = j <= 2,
        icon = ({ "minus", "plus", "chevrons-up", pc and "backpack" or "package", "trash" })[j],
      }, row)
      desktopActionsW = desktopActionsW + desktopWidths[j]
    end
  end
  local itemH = Kit.desktop and row + gap or actionRows * row + (actionRows - 1) * gap + row + 3 * gap
  local visible = math.max(1, math.floor(bodyH / itemH))
  local offsetKey = prefix .. "Offset"
  local drawn, shift = Kit.list(S, offsetKey, cx, cy, inner, bodyH, #order, itemH)
  Kit.pushClip(cx, cy, inner, bodyH)
  for i = 1, drawn do
    local entry = order[S[offsetKey] + i]
    if entry == nil then
      break
    end
    local id, slot = entry.id, entry.slot
    local key = tostring(id) .. (slot > 1 and ("#" .. slot) or "")
    local by = cy + (i - 1) * itemH - shift
    local def = S.data.items[id]
    local count = entry.count or 0
    local max = Ops.itemMax(S, id, pc)
    local issue = not require("Legality").integer(count, 1, max)
      and ("Saved stack must be a whole number from 1 to " .. max) or nil
    local opts = { font = "small", align = "left", trailingIcon = "pencil", face = "invert", invalid = issue ~= nil }
    if
      Kit.button(
        cx,
        by,
        Kit.desktop and inner - desktopActionsW - gap or inner,
        row,
        tostring(def and def.name or id):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
          .. " ×"
          .. count,
        opts
      )
    then
      Touch.open(S, Kit, {
        mode = "number",
        id = "item-" .. key,
        title = def and def.name or tostring(id),
        value = count,
        savedValue = count,
        issue = issue,
        limits = {
          lo = 1,
          hi = max,
          help = "Set the stack size. Max fills it; Drop removes it.",
        },
        apply = function(v)
          return call("Adjust", id, v - count, slot)
        end,
      })
    end
    if not Kit.desktop then by = by + row + gap end
    local actionX = cx + inner - desktopActionsW
    local labels = {
      "Decrease",
      "Increase",
      "Max",
      pc and "Bag" or "PC",
      Ops.armLabel(S, prefix .. "-drop-" .. key, "Drop"),
    }
    for j, label in ipairs(labels) do
      local actionRow = math.floor((j - 1) / actionCols)
      local first = actionRow * actionCols + 1
      local cols = math.min(actionCols, #labels - first + 1)
      local bw = (inner - (cols - 1) * gap) / cols
      if Kit.desktop then bw = desktopWidths[j] end
      if
        Kit.button(Kit.desktop and actionX or cx + (j - first) * (bw + gap), by + (Kit.desktop and 0 or actionRow * (row + gap)), bw, row, label, {
          font = "small",
          icon = ({ "minus", "plus", "chevrons-up", pc and "backpack" or "package", "trash" })[j],
          iconOnly = j == 1 or j == 2,
          iconStack = not Kit.desktop and j >= 3,
          kind = j == 5 and "danger" or "ghost",
          enabled = j ~= 4 or Ops.moveCount(S, not pc, id) > 0,
        })
      then
        if j == 1 then
          call("Adjust", id, -1, slot)
        elseif j == 2 then
          call("Adjust", id, 1)
        elseif j == 3 then
          call("Max", id)
        elseif j == 4 then
          call(pc and "ToBag" or "ToPc", id)
        elseif
          Ops.arm(
            S,
            prefix .. "-drop-" .. key,
            "Drop this entire stack? Tap again to confirm"
          )
        then
          call("Drop", id, slot)
        end
      end
      actionX = actionX + bw + gap
    end
  end
  Kit.popClip()
  S[offsetKey] = Kit.pager(cx, pagerY, inner, S[offsetKey], #order, visible)
end
function M.draw(S, Kit, x, y, w, h)
  Motion.pages(S, Kit, "itemView", x, y, w, h, drawView)
end
return M
