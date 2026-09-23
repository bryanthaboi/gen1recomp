package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
love.graphics.setLineJoin = function() end
love.graphics.newShader = function() return {} end
local T = require("tests.harness")
local Kit = require("src.ui.kit.Kit")
local View = require("src.import.LauncherView")
local Transition = require("src.ui.kit.Transition")
local Importer = require("src.import.RomImporter")
local GameVersion = require("src.core.GameVersion")

local width, height = 853, 480
love.graphics.getDimensions = function() return width, height end
love.graphics.getPixelDimensions = love.graphics.getDimensions
local mouseX, mouseY = -100, -100
love.mouse.getPosition = function() return mouseX, mouseY end
local now = 100
love.timer.getTime = function() return now end

local CATEGORIES = { "graphics", "gameplay", "audio", "qol", "translation", "challenge", "ui" }

local function fixture(tab)
  local imp = Importer.new(function() end, { launcher = true, onEditSave = function() end })
  for _, v in ipairs(GameVersion.ORDER) do imp.ready[v] = true end
  imp._ensureSlots, imp._ensureMods = function() end, function() end
  imp._refreshMods = function() end
  imp._resetModOrder = function(self) self.didReset = true end
  imp.mods = {}
  imp.tab = tab
  return imp
end

local MODALS = {
  { key = "_modScopePopup", tab = "mods", close = "Close",
    open = function(imp) imp._modScopePopup = true end },
  { key = "_filterPopup", tab = "find", close = "Close",
    open = function(imp)
      imp.findIndex = { categories = CATEGORIES, baseGames = {} }
      imp._filterPopup = true
    end },
  { key = "_sortPopup", tab = "mods", close = "Close",
    open = function(imp) imp._sortPopup = "mods" end },
  { key = "_indexManage", tab = "find", close = "Close",
    open = function(imp)
      imp.findSources = {}
      for i = 1, 6 do imp.findSources[i] = { feed = "https://x/" .. i, label = "Index " .. i } end
      imp._indexManage = true
    end },
}

local function draw(imp)
  Kit.audit = {}
  View.draw(imp)
  Transition.reset()
  Kit.audit = {}
  View.draw(imp)
  local rects = Kit.audit
  Kit.audit = nil
  return rects
end

local function opened(spec)
  local imp = fixture(spec.tab)
  View.draw(imp)
  spec.open(imp)
  return imp, draw(imp)
end

local function inside(r, W, H)
  return r.x >= 0 and r.y >= 0 and r.x + r.w <= W + 0.5 and r.y + r.h <= H + 0.5
end

local function within(inner, outer)
  return inner.x >= outer.x - 0.5 and inner.y >= outer.y - 0.5
    and inner.x + inner.w <= outer.x + outer.w + 0.5
    and inner.y + inner.h <= outer.y + outer.h + 0.5
end

for _, size in ipairs({ { 853, 480 }, { 780, 360 }, { 1280, 720 } }) do
  width, height = size[1], size[2]
  for _, spec in ipairs(MODALS) do
    local imp, rects = opened(spec)
    local tag = ("%s at %dx%d"):format(spec.key, width, height)
    T.eq(View.modalKey(imp), spec.key, tag .. " is the open modal")
    local state = imp._modalScroll and imp._modalScroll[spec.key]
    T.check(state ~= nil and state.rect ~= nil, tag .. " records a scroll rect")
    local closeSeen, escaped = false, {}
    for _, r in ipairs(rects) do
      if r.clip then
        if not inside(r.clip, width, height) then escaped[#escaped + 1] = r.label .. " clip" end
        if state and not within(r.clip, state.rect) then escaped[#escaped + 1] = r.label .. " clip outside body" end
      elseif not inside(r, width, height) then
        escaped[#escaped + 1] = r.label
      end
      if r.label == spec.close and not r.clip then
        closeSeen = true
        T.check(inside(r, width, height), tag .. " Close is on screen")
      end
    end
    T.check(closeSeen, tag .. " draws a pinned Close")
    T.check(#escaped == 0, tag .. " keeps every control on screen or in the scroll clip: "
      .. table.concat(escaped, ", "))
    if state and state.rect then
      T.check(inside(state.rect, width, height), tag .. " scroll body is on screen")
    end
  end
end

width, height = 1280, 720
do
  local imp = opened(MODALS[1])
  T.eq(imp._modalScroll._modScopePopup.maxScroll, 0, "Show-for fits without scrolling at 1280x720")
end

for _, size in ipairs({ { 853, 480 }, { 780, 360 } }) do
  width, height = size[1], size[2]
  local imp = opened(MODALS[1])
  local state = imp._modalScroll._modScopePopup
  T.check(state.maxScroll > 0, ("Show-for list overflows at %dx%d"):format(width, height))
  local r = state.rect
  local scopeBefore = imp.modScope
  now = now + 1
  View.touchpressed(imp, 7, r.x + 20, r.y + r.h - 5)
  View.touchmoved(imp, 7, r.x + 20, r.y + 5)
  draw(imp)
  now = now + 1
  View.touchreleased(imp, 7, r.x + 20, r.y + 5)
  draw(imp)
  View.update(imp, 1 / 60)
  T.check(state.scroll > 0, ("touch drag scrolls Show-for at %dx%d"):format(width, height))
  T.check(imp._modScopePopup ~= nil, "drag leaves Show-for open")
  T.eq(imp.modScope, scopeBefore, "drag does not pick a scope")

  state.scroll = 0
  mouseX, mouseY = r.x + 20, r.y + 10
  imp._wheelY = -1
  draw(imp)
  mouseX, mouseY = -100, -100
  T.check(state.scroll > 0, ("mouse wheel scrolls Show-for at %dx%d"):format(width, height))

  state.scroll = 0
  now = now + 1
  Kit.setFocus("scopepop-leafgreen")
  local rects = draw(imp)
  local shown = false
  for _, a in ipairs(rects) do
    if a.label == GameVersion.info("leafgreen").label and a.clip
        and a.y >= a.clip.y - 0.5 and a.y + a.h <= a.clip.y + a.clip.h + 0.5 then
      shown = true
    end
  end
  T.check(shown, ("focusing LeafGreen scrolls it into view at %dx%d"):format(width, height))
  Kit.activateFocused()
  View.draw(imp)
  View.update(imp, 1 / 60)
  T.eq(imp.modScope, "leafgreen", "LeafGreen is selectable from the Show-for list")
  T.eq(imp._modScopePopup, nil, "choosing a scope closes Show-for")
  draw(imp)
  T.eq(imp._modalScroll and imp._modalScroll._modScopePopup, nil, "closing drops the scroll state")
  Kit.setFocus(nil)
end

width, height = 780, 360
do
  local imp = opened(MODALS[2])
  local state = imp._modalScroll._filterPopup
  T.check(state.maxScroll > 0, "FIND filter overflows at 780x360")
  local r = state.rect
  now = now + 1
  View.touchpressed(imp, 9, r.x + 20, r.y + r.h - 5)
  View.touchmoved(imp, 9, r.x + 20, r.y + 5)
  draw(imp)
  now = now + 1
  View.touchreleased(imp, 9, r.x + 20, r.y + 5)
  draw(imp)
  View.update(imp, 1 / 60)
  T.check(state.scroll > 0, "touch drag scrolls the FIND filter")
  T.check(imp._filterPopup ~= nil, "drag leaves the FIND filter open")
  now = now + 1
  Kit.setFocus("filterpop-ui")
  draw(imp)
  Kit.activateFocused()
  View.draw(imp)
  View.update(imp, 1 / 60)
  T.eq(imp.findCategory, "ui", "last FIND category is selectable")
  Kit.setFocus(nil)
end

do
  local imp = opened(MODALS[3])
  local state = imp._modalScroll._sortPopup
  T.check(state.maxScroll > 0, "sort list overflows at 780x360")
  now = now + 1
  Kit.setFocus("sortpop-reset-order")
  draw(imp)
  Kit.activateFocused()
  View.draw(imp)
  View.update(imp, 1 / 60)
  T.check(imp.didReset == true, "Reset load order is reachable at 780x360")
  Kit.setFocus(nil)
end

local LONG = "This paragraph is long on purpose so it wraps across several lines of the"
  .. " modal body at phone widths and pushes the controls below it off a short window."

local function richMods(imp)
  local imports = {}
  for i = 1, 6 do
    imports[i] = { id = "f" .. i, name = "File " .. i, file = "file" .. i .. ".bin",
      required = i % 2 == 1, description = "Needed piece " .. i, present = i == 2 }
  end
  imp.mods = {
    { id = "alpha", name = "Alpha", version = "1.0.0", status = "enabled", github = "o/alpha",
      dependencySpecs = { { id = "beta" } }, imports = imports, loadRank = 1,
      missingRequiredImports = 3 },
    { id = "beta", name = "Beta", version = "1.0.0", status = "enabled", loadRank = 2 },
    { id = "gamma", name = "Gamma", version = "1.0.0", status = "enabled", loadRank = 3 },
  }
  imp.requiredImportNotice = { modId = "alpha", importId = "f1", text = LONG }
end

local function profiles(imp, n)
  local list = {}
  for i = 1, n do list[i] = { name = "Profile " .. i } end
  imp._profileCache = { options = {}, list = list, active = "Profile 1" }
end

local function syncEngine(linked)
  local devices = {}
  for i = 1, 4 do devices[i] = { id = "d" .. i, label = "Device " .. i, current = i == 1 } end
  return {
    phase = "idle", status = "Last sync a minute ago", devices = devices,
    codes = linked and { code1 = "ABCD-EFGH", code2 = "IJKL-MNOP" } or nil,
    shareCode = "QRSTUV", conflicts = {},
    busy = function() return false end,
    linked = function() return linked end,
  }
end

local SWEEP = {
  { key = "_saveExport", tab = "red", open = function(imp)
      imp._saveExport = { scope = "red", version = "red", label = LONG, slotId = "a" }
    end },
  { key = "_rename", tab = "red", foot = "Cancel", open = function(imp)
      imp._rename = { text = "slot" }
    end },
  { key = "_indexPrompt", tab = "find", foot = "Cancel", open = function(imp)
      imp._indexPrompt = { text = "" }
    end },
  { key = "_profileSavePrompt", tab = "mods", foot = "Cancel", open = function(imp)
      imp._profileSavePrompt = { text = "P" }
    end },
  { key = "_modConfirm", tab = "mods", foot = "Cancel", scrolls = true, open = function(imp)
      imp._modConfirm = { title = "Enable this mod for every game in the list below",
        lines = { LONG, LONG, LONG, LONG, LONG, LONG, LONG, LONG }, toggle = { label = "Remember this", on = false } }
    end },
  { key = "_singleProfileActions", tab = "mods", foot = "Close", open = function(imp)
      profiles(imp, 3)
      imp._singleProfileActions = { name = "Profile 2" }
    end },
  { key = "_profilesPopup", tab = "mods", foot = "Close", scrolls = true, open = function(imp)
      profiles(imp, 8)
      imp._profilesPopup = true
    end },
  { key = "_modHeaderActionsPopup", tab = "mods", foot = "Close", scrolls = true, open = function(imp)
      imp._modHeaderActionsPopup = true
    end },
  { key = "_gamePopup", tab = "red", foot = "Close", open = function(imp)
      imp._gamePopup = true
    end },
  { key = "_cartSave", tab = "mods", foot = "Cancel", scrolls = true, open = function(imp)
      local pins = {}
      for i = 1, 6 do pins[i] = { id = "m" .. i, name = "Mod " .. i, reason = LONG } end
      imp._cartSave = { version = "red", count = 6, text = "My cart", cartVersion = "1.0.0",
        author = "me", unresolved = pins, publishable = false, error = LONG }
    end },
  { key = "_skinActions", tab = "skins", foot = "Close", scrolls = true, open = function(imp)
      imp._skins = { { id = "pad", format = "native", pages = 1, controls = 8 } }
      imp._ensureSkins = function(self) return self._skins end
      imp.onOpenSkinStudio = function() end
      imp._skinExport = { dir = "/tmp" }
      imp._skinActions = { id = "pad" }
    end },
  { key = "_modActions", tab = "mods", foot = "Close", scrolls = true, open = function(imp)
      richMods(imp)
      imp._modActions = "alpha"
    end },
  { key = "_modImports", tab = "mods", foot = "Close", scrolls = true, open = function(imp)
      richMods(imp)
      imp._modImports = "alpha"
    end },
  { key = "_findEntry", tab = "find", foot = "Close", open = function(imp)
      imp._findEntry = { id = "alpha", title = "Alpha", version = "1.0.0", author = "someone",
        categories = { "qol" }, repo = "https://example.invalid/alpha" }
    end },
  { key = "_gameManage", tab = "red", foot = "Close", open = function(imp)
      imp._webClipNotice = { key = "red:", ok = false, text = LONG }
      imp._gameManage = "red"
    end },
  { key = "_syncModal", tab = "red", foot = "Close", label = "sync home", scrolls = true,
    open = function(imp)
      imp._syncTransportOk = true
      imp._sync = syncEngine(true)
      imp._syncModal = { view = "home" }
    end },
  { key = "_syncModal", tab = "red", foot = "Back", label = "sync mods", open = function(imp)
      imp._syncTransportOk = true
      imp._sync = syncEngine(true)
      imp._sync.modPlan = { toInstall = { 1, 2 }, indexes = { 1 } }
      imp._syncModal = { view = "mods" }
    end },
  { key = "_syncModal", tab = "red", foot = "Back", label = "sync link", open = function(imp)
      imp._syncTransportOk = true
      imp._sync = syncEngine(false)
      imp._syncModal = { view = "link" }
    end },
}

local function sweepTag(spec)
  return ("%s at %dx%d"):format(spec.label or spec.key, width, height)
end

local sawScroll = {}
for _, size in ipairs({ { 853, 480 }, { 780, 360 }, { 1280, 720 } }) do
  width, height = size[1], size[2]
  for _, spec in ipairs(SWEEP) do
    local imp, rects = opened(spec)
    local tag = sweepTag(spec)
    T.eq(View.modalKey(imp), spec.key, tag .. " is the open modal")
    local state = imp._modalScroll and imp._modalScroll[spec.key]
    T.check(state ~= nil and state.rect ~= nil, tag .. " lays out through a scroll body")
    local escaped, footSeen = {}, not spec.foot
    for _, r in ipairs(rects) do
      if r.clip then
        if not inside(r.clip, width, height) then escaped[#escaped + 1] = r.label .. " clip" end
        if state and not within(r.clip, state.rect) then
          escaped[#escaped + 1] = r.label .. " clip outside body"
        end
      elseif not inside(r, width, height) then
        escaped[#escaped + 1] = r.label
      end
      if spec.foot and r.label == spec.foot and not r.clip and inside(r, width, height) then
        footSeen = true
      end
    end
    T.check(footSeen, tag .. " pins " .. tostring(spec.foot) .. " on screen")
    T.check(#escaped == 0, tag .. " keeps every control on screen or in the scroll clip: "
      .. table.concat(escaped, ", "))
    if state and state.rect then
      T.check(inside(state.rect, width, height), tag .. " scroll body is on screen")
      if width == 1280 and not spec.scrolls then
        T.eq(state.maxScroll, 0, tag .. " fits without scrolling")
      end
      if state.maxScroll > 0 then sawScroll[spec.label or spec.key] = true end
    end
  end
end

local PAGED = {
  { key = "_modVersions", tab = "mods", open = function(imp)
      local rel = {}
      for i = 1, 8 do rel[i] = { version = "1." .. i, body = LONG } end
      imp._modVersions = { id = "alpha", name = "Alpha", current = "1.1", releases = rel }
    end },
  { key = "_modDepResolver", tab = "mods", open = function(imp)
      local deps = {}
      for i = 1, 6 do deps[i] = { id = "d" .. i, name = "Dep " .. i, status = "missing", github = "o/d" } end
      imp._modDepResolver = { targetMod = { id = "alpha", name = "Alpha" }, deps = deps }
    end },
  { key = "_modReleaseNotes", tab = "mods", open = function(imp)
      imp._modReleaseNotes = { version = "1.0", body = LONG .. LONG .. LONG }
    end },
  { key = "_cartPopup", tab = "red", open = function(imp) imp._cartPopup = "red" end },
}

for _, size in ipairs({ { 853, 480 }, { 780, 360 } }) do
  width, height = size[1], size[2]
  for _, spec in ipairs(PAGED) do
    local imp, rects = opened(spec)
    local tag = sweepTag(spec)
    T.eq(View.modalKey(imp), spec.key, tag .. " is the open modal")
    local escaped = {}
    for _, r in ipairs(rects) do
      if not inside(r.clip or r, width, height) then escaped[#escaped + 1] = r.label end
    end
    T.check(#escaped == 0, tag .. " keeps every control on screen: " .. table.concat(escaped, ", "))
  end
end

for _, spec in ipairs(SWEEP) do
  if spec.scrolls then
    T.check(sawScroll[spec.label or spec.key] == true,
      (spec.label or spec.key) .. " overflows somewhere in the sweep")
  end
end

width, height = 780, 360
do
  local imp = opened(SWEEP[8])
  local state = imp._modalScroll._modHeaderActionsPopup
  T.check(state.maxScroll > 0, "More Mod Actions overflows at 780x360")
  local r = state.rect
  now = now + 1
  View.touchpressed(imp, 11, r.x + 20, r.y + r.h - 5)
  View.touchmoved(imp, 11, r.x + 20, r.y + 5)
  draw(imp)
  now = now + 1
  View.touchreleased(imp, 11, r.x + 20, r.y + 5)
  draw(imp)
  View.update(imp, 1 / 60)
  T.check(state.scroll > 0, "touch drag scrolls More Mod Actions")
  T.check(imp._modHeaderActionsPopup ~= nil, "drag leaves More Mod Actions open")
  state.scroll = 0
  now = now + 1
  Kit.setFocus("modheadact-6")
  local rects = draw(imp)
  local shown = false
  for _, a in ipairs(rects) do
    if a.label == "Sort mods..." and a.clip
        and a.y >= a.clip.y - 0.5 and a.y + a.h <= a.clip.y + a.clip.h + 0.5 then
      shown = true
    end
  end
  T.check(shown, "focusing Sort mods scrolls it into view")
  Kit.activateFocused()
  View.draw(imp)
  View.update(imp, 1 / 60)
  T.eq(imp._sortPopup, "mods", "Sort mods is reachable from More Mod Actions at 780x360")
  Kit.setFocus(nil)
end

do
  local imp = opened(SWEEP[7])
  local state = imp._modalScroll._profilesPopup
  T.check(state.maxScroll > 0, "profile list scrolls at 780x360")
  now = now + 1
  Kit.setFocus("prof-sw-8")
  draw(imp)
  Kit.activateFocused()
  View.draw(imp)
  View.update(imp, 1 / 60)
  T.check(state.scroll > 0, "focusing the last profile scrolls the list")
  Kit.setFocus(nil)
end

do
  local imp = opened(SWEEP[5])
  local state = imp._modalScroll._modConfirm
  T.check(state.maxScroll > 0, "long confirm scrolls at 780x360")
  local yes
  for _, r in ipairs(draw(imp)) do
    if r.label == "OK" and not r.clip then yes = r end
  end
  T.check(yes ~= nil and inside(yes, width, height), "confirm OK stays pinned on screen")
end

do
  local imp = fixture("red")
  View.draw(imp)
  local rows = {}
  for i = 1, 40 do
    rows[i] = { label = "OPTION " .. i, value = function() return "ON" end,
      step = function() return true end }
  end
  imp._settings = { opts = {}, sections = { { title = "Options", rows = rows } },
    save = function() end }
  draw(imp)
  local model = imp._settings
  T.check(model.maxScroll > 0, "settings list overflows at 780x360")
  local lines = {}
  for i = 1, 10 do lines[i] = LONG end
  model.confirm = { title = "Reset everything?", lines = lines,
    yesLabel = "Yes", noLabel = "No", close = function() model.confirm = nil end }
  draw(imp)
  local all = imp._modalScroll or {}
  local cs = all._settingsConfirm or all._settings
  T.check(all._settingsConfirm ~= nil, "settings confirm keeps its own scroll state")
  T.check(cs ~= nil and cs.maxScroll > 0, "long settings confirm scrolls at 780x360")
  if cs and cs.rect then
    local r, before = cs.rect, model.scroll or 0
    now = now + 1
    View.touchpressed(imp, 21, r.x + 20, r.y + r.h - 5)
    View.touchmoved(imp, 21, r.x + 20, r.y + 5)
    draw(imp)
    now = now + 1
    View.touchreleased(imp, 21, r.x + 20, r.y + 5)
    draw(imp)
    T.check(cs.scroll > 0, "touch drag scrolls the settings confirm body")
    T.eq(model.scroll or 0, before, "confirm drag leaves the settings list alone")
    T.check(model.confirm ~= nil, "drag leaves the settings confirm open")
    T.check(imp._modalScroll._settingsConfirm == cs, "confirm scroll survives redraw")
  end
  model.confirm = nil
  draw(imp)
  T.eq(imp._modalScroll._settingsConfirm, nil, "closing the confirm drops its scroll state")
end

width, height = 1280, 720
do
  local spec
  for _, s in ipairs(SWEEP) do if s.key == "_modActions" then spec = s end end
  local imp = opened(spec)
  local state = imp._modalScroll._modActions
  local del = state.rows["modact-del"]
  T.check(state.rows["modact-top"] ~= nil, "mod actions shows the reorder rows")
  T.eq(state.maxScroll, 0, "mod actions fits at 1280x720")
  T.eq(del[1] + del[2], state.rect.h, "mod actions body ends at Delete with no blank row")
end

T.finish("launcher modal scroll")
