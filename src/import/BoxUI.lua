local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Transition = require("src.ui.kit.Transition")
local Strings = require("src.core.Strings")
local Icons = require("src.ui.kit.Icons")
local Toast = require("src.ui.kit.Toast")
local UI = {}
local PAL = Theme.PAL
UI.ICONS = { List = "book-open", Filters = "list-filter", Arrange = "arrow-left-right",
  Themes = "paintbrush", Dashboard = "chart-no-axes-column", Teams = "users", Gifts = "package",
  Showcase = "grid-2x2", Files = "folder", Events = "mail", Migration = "arrow-left-right", Items = "backpack" }
UI.HELP = {
  Box = "these pokémon stay here until you send them to a game. Box saves separately, and sync keeps both sides of a move together.",
  List = "all your stored pokémon in one list. select up to six to compare them.",
  Arrange = "sort and Auto Box work on Box storage or the linked game's PC. top rule wins. preview where they'll go, then apply to save.",
  Themes = "just the look of this box. use a saved Showcase stage if you want your own wallpaper.",
  Dashboard = "what’s in Box right now. caught is from the linked game’s pokédex, so the numbers can be different.",
  Teams = "save a group of up to six. send team moves them into the linked game’s party, so leave enough room.",
  Gifts = "this trainer unlocks eggs by storing more pokémon. claim one here, then send it to a game to hatch it.",
  Showcase = "make a little scene with your pokémon. edits are a draft until you save. saved stages can become wallpapers.",
  Files = "bring in a GameCube Box save or export one back out. exports need its original template and Gen 3 pokémon.",
  Backup = "restores Box and its linked saves together. your current collection gets backed up first. older incomplete backups won’t restore.",
  Events = "tickets for event trips in the linked game. collect the ticket, then use the normal ship route. story requirements still apply.",
  Migration = "same pokémon, new generation. check the changes first. the original stays archived so you can switch back.",
  MigrationPolicy = "Gen 2 and Gen 3 never had an official transfer route. G1R converts what fits and blocks what doesn’t. Gen 1 and 2 to Gen 3 follows Pokémon Bank: nature from EXP, IVs from DVs, EVs reset, Poké Ball.",
  Items = "store bag items here, then send them to another game's bag. gen 1 and 2 share a stash. changing a ball uses one up.",
}
local HELP_TITLES = { Box = "Box storage",
  Backup = "Restore backup", MigrationPolicy = "Conversion rules" }
local function view() return require("src.import.LauncherView") end
function UI.button(imp, x, y, w, h, id, label, action, opts)
  opts = opts or {}; opts.action, opts.font = action, opts.font or "small"
  view().btn(imp, x, y, w, h, "box-" .. id, Strings(label), opts)
end
local function toastStore(imp, key)
  imp._toasts = imp._toasts or {}
  imp._toasts[key] = imp._toasts[key] or {}
  return imp._toasts[key]
end
function UI.toast(imp, text, kind, sticky, key)
  local store = toastStore(imp, key or "box")
  if text == nil or text == "" then return Toast.clear(store) end
  Toast.show(store, Strings(tostring(text)), kind, { sticky = sticky })
end
function UI.currentToast(imp)
  local store = imp._toasts and imp.tab and imp._toasts[imp.tab]
  return store and Toast.current(store) and store or nil
end
function UI.occludeToast(imp)
  local store = UI.currentToast(imp)
  local r = store and store.toast.rect
  if r then Kit.occlude(r[1], r[2], r[3], r[4]) end
end
local function wrapHeight(text, w, maxLines) return Kit.wrapHeight("small", text, w, maxLines) end
local function drawText(text, x, y, w, c, maxLines) Kit.textWrapped("small", text, x, y, w, c, maxLines) end
function UI.drawToast(imp, m, bottom)
  local store = UI.currentToast(imp)
  if not store then return end
  local rect = Toast.draw(store, { x = 0, w = m.W, bottom = bottom, s = m.s,
    wrapHeight = wrapHeight, drawText = drawText })
  if not rect then return end
  local overlay = Kit._overlay
  Kit._overlay = true
  view().btn(imp, rect[1], rect[2], rect[3], rect[4], "box-toast", "", { face = "bare", ring = false,
    action = function() Toast.clear(store) end })
  Kit._overlay = overlay
end
function UI.close(imp)
  imp._boxPopup = nil; Kit.blur(); Kit._drag = nil
  Kit.mouseClicked, Kit.wheelY = false, 0
end
function UI.open(imp, title, options, current, apply)
  Kit.blur(); Kit._drag = nil
  imp._boxPopup = { title = title, options = options, current = current, apply = apply,
    scroll = 0, index = 1, query = "", reveal = true }
  if #options == 0 then imp._boxPopup.message = title == "Choose a game"
    and "save a game first. your party and PC boxes will show up here." or "nothing here yet." end
  if current ~= nil then
    for i, option in ipairs(options) do if option.id == current then imp._boxPopup.index = i end end
  end
  if options[imp._boxPopup.index] and options[imp._boxPopup.index].disabled then
    for i, option in ipairs(options) do
      if not option.disabled then imp._boxPopup.index = i; break end
    end
  end
end
function UI.confirm(imp, title, message, label, action)
  UI.open(imp, title, {}, nil)
  imp._boxPopup.message, imp._boxPopup.confirm = message, { label = label, action = action }
end
function UI.help(imp, key, x, y, size, message)
  UI.button(imp, x, y, size, size, "help-" .. key, "", function()
    UI.open(imp, HELP_TITLES[key] or key, {}, nil)
    imp._boxPopup.message = message or UI.HELP[key]
  end, { face = "bare", icon = "circle-help" })
end
function UI.dropdown(imp, x, y, w, h, id, label, options, current, apply, icon)
  UI.button(imp, x, y, w, h, id, label, function()
    UI.open(imp, label, type(options) == "function" and options() or options, current, apply)
  end,
    { face = "invert", align = "left", icon = icon or "sliders-horizontal", trailingIcon = "chevron-down" })
end
function UI.values(values, labels, icon)
  local options = {}
  for i, value in ipairs(values) do options[i] = { id = value, label = labels and labels[value] or tostring(value), icon = icon } end
  return options
end
function UI.change(imp, s, key, value, direction)
  if s[key] == value then return false end
  local old = {}; for k, v in pairs(s) do if k ~= "motionFrom" then old[k] = v end end
  s[key] = value; s.motionFrom = old; Kit.blur()
  Transition.start("box", "tab", { dir = direction or 1 })
  imp._tabScroll = imp._tabScroll or {}; imp._tabScroll.box = 0
  return true
end
function UI.pages(imp, s, x, y, w, h, m, draw)
  local tr = Transition.get("box")
  if not tr or not s.motionFrom then s.motionFrom = nil; return draw(imp, s, x, y, w, h, m) end
  local blocked = Kit.blockClicks; Kit.blockClicks = true
  Kit.pushClip(x, y, w, math.max(h, 1))
  local dir = tr.dir >= 0 and 1 or -1
  local oldH, newH
  local ok, err = xpcall(function()
    oldH = draw(imp, s.motionFrom, x - dir * tr.p * w, y, w, h, m)
    newH = draw(imp, s, x + dir * (1 - tr.p) * w, y, w, h, m)
  end, debug.traceback)
  Kit.popClip(); Kit.blockClicks = blocked
  if not ok then error(err, 0) end
  return math.max(oldH or 0, newH or 0)
end
local function filtered(p)
  if p.filteredQuery ~= p.query then
    p.rows = {}
    for _, option in ipairs(p.options) do
      local fold=require("src.box.Search").normalize
      if p.query == "" or fold(option.label):find(fold(p.query), 1, true) then p.rows[#p.rows + 1] = option end
    end
    p.filteredQuery = p.query
  end
  return p.rows
end
local function choose(imp, p, option)
  if imp._boxPopup ~= p or not option or option.disabled then return false end
  UI.close(imp)
  if option.action then option.action() elseif p.apply then p.apply(option.id) end
  return true
end
function UI.keypressed(imp, key)
  local p = imp._boxPopup
  if not p then return false end
  if key == "escape" then UI.close(imp)
  elseif key == "return" or key == "kpenter" then
    if p.confirm then UI.close(imp); p.confirm.action()
    elseif p.message then UI.close(imp) else choose(imp, p, filtered(p)[p.index]) end
  elseif not p.message and (key == "up" or key == "down" or key == "home" or key == "end") then
    local rows = filtered(p)
    if key == "home" then p.index = 1 elseif key == "end" then p.index = #rows
    else
      local step = key == "up" and -1 or 1
      for _ = 1, math.max(1, #rows) do
        p.index = (p.index - 1 + step) % math.max(1, #rows) + 1
        if not (rows[p.index] and rows[p.index].disabled) then break end
      end
    end
    p.reveal = true
  elseif Kit.focus == "box-chooser-filter" then Kit.keypressed(key) end
  return true
end
function UI.drawPopup(imp, m)
  local p = imp._boxPopup
  local pad, gap = 16 * m.s, 8 * m.s
  local row = math.max(Kit.tapMin(), m.btnH)
  local width = math.min((p.message and 390 or 460) * m.s, m.W - 2 * m.pad)
  local searchable = not p.message and #p.options > 8
  local inner = width - 2 * pad
  local content = p.message and Kit.wrapHeight("small", Strings(p.message), inner, 6) + (p.confirm and gap + row or 0)
    or math.max(row, math.min(7, #p.options) * (row + gap) - gap)
  local x, y, w, h = view().modalPanel(m, width, 2 * pad + row + gap + content + (searchable and row + gap or 0), { scrim = .76, slide = true })
  if Kit.press(0, 0, m.W, m.H) and not Kit.hit(x, y, w, h) then UI.close(imp); return end
  UI.button(imp, x + w - pad - row, y + pad, row, row, "popup-close", "", function() UI.close(imp) end,
    { face = "bare", icon = "x" })
  Kit.textBold("button", Strings(Kit.ellipsize("button", p.title, w - 2 * pad - row - gap)), x + pad,
    y + pad + (row - Kit.textHeight("button")) / 2, PAL.heading)
  local bx, by, bw = x + pad, y + pad + row + gap, w - 2 * pad
  if p.message then
    Kit.textWrapped("small", Strings(p.message), bx, by, bw, PAL.text, 6)
    if p.confirm then
      local cw, cy = (bw - gap) / 2, y + h - pad - row
      UI.button(imp, bx, cy, cw, row, "popup-cancel", "Cancel", function() UI.close(imp) end, { icon = "x" })
      UI.button(imp, bx + cw + gap, cy, cw, row, "popup-confirm", p.confirm.label, function()
        if imp._boxPopup ~= p then return end
        UI.close(imp); p.confirm.action()
      end, { face = "invert", icon = "check", ring = true })
    end
    return
  end
  if searchable then
    local query = Kit.textfield("box-chooser-filter", bx, by, bw, row, p.query, Strings("Find an option"))
    if query ~= p.query then p.query, p.index, p.scroll, p.reveal = query, 1, 0, true end
    by = by + row + gap
  end
  local rows = filtered(p)
  local bh = math.max(1, y + h - pad - by)
  local total = math.max(row, #rows * (row + gap) - gap)
  local extent = Kit.scrollExtent(total, bh)
  if p.reveal then
    local at = (p.index - 1) * (row + gap)
    p.scroll = Kit.scrollClamp(math.max(at + row - bh, math.min(p.scroll, at)), extent); p.reveal = nil
  end
  p.scroll = Kit.scrollInput(p.scroll, extent, bx, by, bw, bh)
  local cy = Kit.scrollBegin(bx, by, bw, bh, p.scroll, extent)
  local first = math.max(1, math.floor(p.scroll / (row + gap)) + 1)
  local last = math.min(#rows, math.ceil((p.scroll + bh) / (row + gap)))
  for i = first, last do
    local option = rows[i]
    local active = p.current ~= nil and option.id == p.current or option.active
    UI.button(imp, bx, cy + (i - 1) * (row + gap), bw - Kit.scrollGutter(), row,
      "popup-option-" .. i, (option.entry or option.prop) and ("       " .. option.label) or option.label, function() choose(imp, p, option) end,
      { face = "selection", align = "left", active = active,
        enabled = not option.disabled, icon = not (option.entry or option.prop) and (option.icon or "check") or nil,
        trailingIcon = active and "check" or nil, ring = p.index == i })
    local iy=cy+(i-1)*(row+gap)
    if option.entry then
      local art=require("src.box.Catalog").art(option.entry)
      if art then require("src.online.OnlineSprites").drawIcon(art,bx+8*m.s,iy+4*m.s,row-8*m.s,0) end
    elseif option.prop then require("src.box.Showcase").drawProp(option.prop,bx+8*m.s,iy+4*m.s,row-8*m.s) end
  end
  if #rows == 0 then Kit.text("small", Strings("Nothing matches."), bx, by, PAL.muted) end
  Kit.scrollEnd(bx, by, bw, bh, p.scroll, extent)
end
return UI
