package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")
love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local Loader = require("src.mods.Loader")
local CartManifest = require("src.carts.CartManifest")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local Manifest = require("src.mods.Manifest")
local ModProfile = require("src.mods.ModProfile")
local LauncherMods = require("src.mods.LauncherMods")
local LoadOrder = require("src.mods.LoadOrder")
local Logger = require("src.core.Logger")
Logger.warn = function() end
Logger.info = function() end

local function names(list) return table.concat(list or {}, ",") end

local function memfs(files)
  return {
    files = files,
    read = function(path) return files[path] end,
    write = function(path, content) files[path] = content return true end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return load(files[path], path)
    end,
    createDirectory = function() return true end,
    getDirectoryItems = function(path)
      local seen, items = {}, {}
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
      table.sort(items)
      return items
    end,
  }
end

local function manifestJson(id, extra)
  return ([[{"id":"%s","name":"%s","version":"1.0.0","entry":"main.lua"%s}]])
    :format(id, id, extra or "")
end

local function entry(label)
  return ([[
return function(mod)
  mod.content.pokemon:override("PIKACHU", { name = "%s" })
end
]]):format(label)
end

local function install(opts, extras)
  extras = extras or {}
  local files = { ["options.lua"] = SaveSerializer.encode(opts or {}) }
  for _, id in ipairs({ "alpha", "beta", "gamma" }) do
    files["mods/" .. id .. "/manifest.json"] = manifestJson(id, extras[id])
    files["mods/" .. id .. "/main.lua"] = entry(id:upper())
  end
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

local function boot(files, mode)
  local data = { pokemon = { PIKACHU = { name = "PIKACHU" } } }
  local loader = Loader.new({ fs = memfs(files) })
  local ok = loader:load(data, mode and { mode = mode } or nil)
  return loader, data, ok
end


do
  T.check(type(SaveData.defaultOptions().modOrder) == "table",
    "defaultOptions carries a modOrder list")
  T.eq(names(SaveData.modOrder({ modOrder = { "b", 3, "a", "b", "", "c" } })),
    "b,a,c", "modOrder keeps strings once, in order")
  T.eq(#SaveData.modOrder({}), 0, "no modOrder reads as empty")
  local o = SaveData.setModOrder({}, { "x", "x", "y" })
  T.eq(names(o.modOrder), "x,y", "setModOrder stores the sanitized list")
end


do
  local entries = {
    { id = "gamma", priority = 0 }, { id = "alpha", priority = 5 },
    { id = "beta", priority = 0 },
  }
  T.eq(names(LoadOrder.materialize({}, entries)), "beta,gamma,alpha",
    "an empty saved order materializes to (priority, id)")
  T.eq(names(LoadOrder.materialize({ "alpha", "gone" }, entries)),
    "beta,gamma,alpha,gone",
    "unlisted ids merge in by priority, uninstalled saved ids keep their slot")
  T.eq(names(LoadOrder.materialize({ "gamma" }, entries)), "gamma,beta,alpha",
    "an unlisted id tied on priority follows the saved one")
  local grown = {
    { id = "a", priority = 0 }, { id = "b", priority = 0 }, { id = "c", priority = 0 },
    { id = "fw", priority = -1000 }, { id = "late", priority = 50 },
  }
  T.eq(names(LoadOrder.materialize({ "b", "a", "c" }, grown)), "fw,b,a,c,late",
    "a mod installed after a reorder still lands by its manifest priority")
  local l = { "a", "b", "c", "d" }
  T.eq(names(LoadOrder.move(l, "b", -1)), "b,a,c,d", "move up one")
  T.eq(names(LoadOrder.move(l, "a", -1)), "a,b,c,d", "move up clamps at the top")
  T.eq(names(LoadOrder.move(l, "d", 1)), "a,b,c,d", "move down clamps at the bottom")
  T.eq(names(LoadOrder.move(l, "c", -math.huge)), "c,a,b,d", "move to top")
  T.eq(names(LoadOrder.move(l, "a", math.huge)), "b,c,d,a", "move to bottom")
  T.eq(names(l), "a,b,c,d", "move never edits its input")
  local full, changed = LoadOrder.moveWithin({ "a", "x", "b", "c" },
    { "a", "b", "c" }, "b", -1)
  T.check(changed, "moveWithin reports a change")
  T.eq(names(full), "b,x,a,c",
    "moveWithin swaps visible neighbours and keeps hidden ids in their slots")
end


do
  local files = install()
  local loader, data = boot(files)
  T.eq(names(loader.order), "alpha,beta,gamma",
    "no modOrder keeps the (priority, id) order")
  T.eq(data.pokemon.PIKACHU.name, "GAMMA", "and the last id wins")
end

do
  local files = install({ modOrder = { "gamma", "alpha", "beta" } })
  local loader, data = boot(files)
  T.eq(names(loader.order), "gamma,alpha,beta", "modOrder decides the load order")
  T.eq(data.pokemon.PIKACHU.name, "BETA", "the last mod in the player's order wins")
end

do
  local files = install({ modOrder = { "beta" } })
  local loader = boot(files)
  T.eq(names(loader.order), "beta,alpha,gamma",
    "a partial list leads, the rest follow by priority and id")
end

do
  local files = install({ modOrder = { "nope", "gamma" } })
  local loader, _, ok = boot(files)
  T.check(ok ~= false, "an unknown id in modOrder is not an error")
  T.eq(names(loader.order), "gamma,alpha,beta", "unknown ids are skipped")
end

do
  local files = install({ modOrder = { "alpha", "beta", "gamma" } },
    { alpha = [[,"priority":9]], gamma = [[,"priority":-4]] })
  local loader = boot(files)
  T.eq(names(loader.order), "alpha,beta,gamma",
    "the player's order outranks manifest priority")
end

do
  local files = install({ modOrder = { "beta", "alpha" } },
    { gamma = [[,"priority":-1000]] })
  local loader = boot(files)
  T.eq(names(loader.order), "gamma,beta,alpha",
    "a low-priority mod missing from the saved order still loads first")
end

do
  local files = install({ modOrder = { "alpha", "beta", "gamma" } },
    { alpha = [[,"dependencies":["gamma"] ]] })
  local loader = boot(files)
  T.eq(names(loader.order), "beta,gamma,alpha",
    "a dependency still loads before the mod that needs it")
end

do
  local files = install({ modOrder = { "alpha", "beta", "gamma" } })
  local cart = assert(CartManifest.parse({ id = "cartx", title = "cartx",
    version = "1.0.0", author = "t", shell = "#102030", base = "red",
    seal = "sealed",
    mods = { { id = "alpha", source = "local", version = "1.0.0" },
             { id = "gamma", source = "local", version = "1.0.0" } },
    load_order = { "gamma", "alpha" } }))
  files["carts/cartx" .. CartManifest.EXT] = CartManifest.encode(cart)
  SaveData.setCart("cartx", "hashx")
  local loader = boot(files)
  T.eq(names(loader.order), "gamma,alpha", "a cart's load_order beats modOrder")
  SaveData.setCart(nil)
end

do
  local files = install({ modOrder = { "gamma", "alpha", "beta" } })
  local loader = boot(files, "disableAll")
  T.eq(loader.playerRank and next(loader.playerRank), nil,
    "arena modes ignore the player's order")
end


do
  local p = ModProfile.capture({ { id = "a", enabled = true } }, {}, {},
    { "b", "a", "b" })
  T.eq(names(p.order), "b,a", "capture copies the sanitized order")
  local back = ModProfile.decode(ModProfile.encode({ name = "P", enabled = {},
    options = {}, slots = {}, enabledByVersion = {}, order = { "b", "a" } }))
  T.eq(names(back and back.order), "b,a", "encode/decode round-trips order")
  local bad = SaveSerializer.encode({ format = ModProfile.FORMAT,
    formatVersion = 1, profile = { name = "Q", order = { "x", 4, "x", "y" } } })
  T.eq(names(ModProfile.decode(bad).order), "x,y",
    "decode drops non-strings and duplicates")
  local live = { modOrder = { "z" } }
  T.check(not ModProfile.matchesOrder({ name = "old" }, live),
    "a profile without an order does not match a custom order")
  ModProfile.restoreOrder({ name = "old" }, live)
  T.eq(names(live.modOrder), "", "a profile without an order resets to the default order")
  T.check(ModProfile.matchesOrder({ name = "old" }, live),
    "and matches once the order is back to default")
  ModProfile.restoreOrder(back, live)
  T.eq(names(live.modOrder), "b,a", "restoreOrder writes the profile's order")
  T.check(ModProfile.matchesOrder(back, live), "matchesOrder agrees after restore")
  T.check(not ModProfile.matchesOrder(back, { modOrder = { "a", "b" } }),
    "matchesOrder notices a moved mod")
end


local function mf(raw) return Manifest.validate(raw) end

do
  local manifests = {
    mf({ id = "aaa", name = "A", version = "1.0.0", entry = "m.lua" }),
    mf({ id = "bbb", name = "B", version = "1.0.0", entry = "m.lua",
         dependencies = { "ccc" } }),
    mf({ id = "ccc", name = "C", version = "1.0.0", entry = "m.lua" }),
  }
  local rows = LauncherMods.deriveList(manifests,
    { mods = {}, modOrder = { "bbb", "ccc", "aaa" } }, "red")
  local by = {}
  for _, r in ipairs(rows) do by[r.id] = r end
  T.eq(by.bbb.loadRank, 1, "deriveList stamps the saved position")
  T.eq(by.aaa.loadRank, 3, "for every row")
  T.eq(by.bbb.orderAfter, "ccc", "a dependency placed later is flagged")
  T.check(type(by.bbb.orderNote) == "string" and by.bbb.orderNote:find("C", 1, true),
    "with a note naming it")
  T.eq(by.ccc.orderNote, nil, "no note when nothing forces a move")
  T.eq(names(LauncherMods.orderedIds(rows, { modOrder = { "ccc" } })),
    "ccc,aaa,bbb", "orderedIds materializes over rows")
  T.eq(names(LauncherMods.moveInOrder({ "a", "b" }, "b", -1)), "b,a",
    "moveInOrder swaps")
end

do
  local fs = love.filesystem
  for _, id in ipairs({ "lo_one", "lo_two", "lo_three" }) do
    fs.write("mods/" .. id .. "/manifest.json", manifestJson(id))
    fs.write("mods/" .. id .. "/main.lua", "return function() end")
  end
  SaveData.saveOptions(SaveData.defaultOptions())
  local ok, at = LauncherMods.moveMod("lo_one", 1)
  T.check(ok, "moveMod moves a mod down")
  T.eq(at, 2, "and reports its new position")
  T.eq(names(SaveData.loadOptions().modOrder), "lo_three,lo_one,lo_two",
    "moveMod persists the whole materialized list")
  T.check(not LauncherMods.moveMod("lo_two", 1), "the last mod cannot move down")
  T.check(not LauncherMods.moveMod("missing_mod", -1), "an unknown id is refused")
  local opts = SaveData.loadOptions()
  opts.safeMode = true
  SaveData.saveOptions(opts)
  T.check(not LauncherMods.moveMod("lo_one", -1), "safe mode refuses a move")
  opts = SaveData.loadOptions()
  opts.safeMode = false
  SaveData.saveOptions(opts)
  fs.write("mods/lo_zero/manifest.json", manifestJson("lo_zero", [[,"priority":-1000]]))
  fs.write("mods/lo_zero/main.lua", "return function() end")
  T.check(LauncherMods.moveMod("lo_two", -1), "a move after a new install")
  T.eq(names(SaveData.loadOptions().modOrder), "lo_zero,lo_three,lo_two,lo_one",
    "the new low-priority mod was placed by priority, not forced last")
  opts = SaveData.loadOptions()
  opts.modProfiles = { { name = "PLAIN", enabled = {}, options = {}, slots = {},
    enabledByVersion = {} } }
  SaveData.saveOptions(opts)
  T.check(LauncherMods.applyProfile("PLAIN"), "applyProfile takes a profile with no order")
  T.eq(#SaveData.loadOptions().modOrder, 0, "and resets the load order to default")
  LauncherMods.moveMod("lo_one", 1)
  T.check(LauncherMods.resetOrder(), "resetOrder clears a saved order")
  T.eq(#SaveData.loadOptions().modOrder, 0, "back to author priority")
  opts = SaveData.loadOptions()
  opts.modProfiles, opts.activeProfile = nil, nil
  SaveData.saveOptions(opts)
  for _, id in ipairs({ "lo_one", "lo_two", "lo_three", "lo_zero" }) do
    fs.remove("mods/" .. id .. "/manifest.json")
    fs.remove("mods/" .. id .. "/main.lua")
  end
end


do
  local ManagerState = require("src.mods.ManagerState")
  local writes = 0
  local game = {
    save = { options = { mods = {}, modOrder = {} } },
    modStatus = { errors = {}, available = {
      { id = "ma", name = "MA", enabled = true, state = "loaded", priority = 0 },
      { id = "mb", name = "MB", enabled = true, state = "loaded", priority = 0 },
      { id = "mc", name = "MC", enabled = true, state = "loaded", priority = 0 },
    } },
    writeOptions = function() writes = writes + 1 end,
    stack = { pop = function() end, push = function() end },
  }
  local ms = ManagerState.new(game)
  ms:refresh()
  local function labels(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.label end
    return table.concat(out, "|")
  end
  local function rowNamed(rows, label)
    for _, r in ipairs(rows) do if r.label == label then return r end end
  end
  local rows = ms:detailRows(ms.byId.ma)
  local orderRow = rowNamed(rows, "< LOAD #1/3 >")
  T.check(orderRow and orderRow.adjust, "the detail screen has one load position row")
  T.eq(labels(rows):find("LOAD EARLIER", 1, true), nil, "no separate earlier/later rows")
  ms.currentMod, ms.screen, ms.scroll = ms.byId.ma, "detail", 1
  for i, r in ipairs(rows) do if r == orderRow then ms.cursor = i end end
  ms:adjustOrTab(1)
  T.eq(names(game.save.options.modOrder), "mb,ma,mc", "RIGHT on the row loads it later")
  T.check(writes > 0, "and persists the options")
  T.check(ms.restartPending, "a moved mod stages a restart")
  rows = ms:detailRows(ms.byId.ma)
  T.check(rowNamed(rows, "< LOAD #2/3 >") ~= nil, "the row follows the move")
  ms:adjustOrTab(-1)
  T.check(not ms.restartPending, "moving back to where it booted clears the restart")
  T.eq(ms.descScroll, 1, "left/right on the row does not scroll the description")
  rowNamed(ms:detailRows(ms.byId.mc), "< LOAD #3/3 >").adjust(-1)
  ms:discardChanges()
  T.eq(names(game.save.options.modOrder), "", "discard restores the boot order")
  T.check(not ms.restartPending, "and clears the pending restart")

  local Font = require("src.render.Font")
  local busy = { id = "md", name = "MD", enabled = true, state = "loaded", priority = 0,
    github = "someone/md", experimental = true, error = "boom", permissions = { "net" } }
  game.modStatus.available[#game.modStatus.available + 1] = busy
  ms:refresh()
  ms.currentMod, ms.screen, ms.cursor, ms.scroll = ms.byId.md, "detail", 1, 1
  local all = ms:rowsForScreen()
  T.check(#all > 4, "a busy mod has more detail rows than fit above the footer")
  local function drawAll()
    local drawn = {}
    local realDraw, realCode = Font.draw, Font.drawCode
    Font.draw = function(text, x, y) drawn[#drawn + 1] = { text = tostring(text), x = x, y = y } end
    Font.drawCode = function() end
    ms:drawDetail()
    Font.draw, Font.drawCode = realDraw, realCode
    local low, seen = true, {}
    for _, d in ipairs(drawn) do
      if d.x == 32 then
        if d.y >= 15 * 8 then low = false end
        seen[d.text] = true
      end
    end
    return low, seen
  end
  local clear, seen = drawAll()
  T.check(clear, "no detail row draws on the footer")
  T.check(seen["FOR " .. require("src.mods.ModTargets").chip(busy)] == nil,
    "FOR is a header line, not a row")
  T.check(not seen["BACK"], "BACK starts below the scroll window")
  for _ = 1, #all - 1 do ms:moveCursor(1) end
  T.eq(all[ms.cursor].label, "BACK", "the cursor reaches BACK")
  clear, seen = drawAll()
  T.check(clear and seen["BACK"], "and BACK scrolls into view above the footer")
end


do
  local Kit = require("src.ui.kit.Kit")
  local RomImporter = require("src.import.RomImporter")
  local LauncherView = require("src.import.LauncherView")
  local function window(w, h)
    love.graphics.getDimensions = function() return w, h end
    love.graphics.getPixelDimensions = function() return w, h end
  end
  local manifests = {
    mf({ id = "va", name = "Alpha", version = "1.0.0", entry = "m.lua" }),
    mf({ id = "vb", name = "Beta", version = "1.0.0", entry = "m.lua" }),
    mf({ id = "vc", name = "Gamma", version = "1.0.0", entry = "m.lua" }),
  }
  local rows = LauncherMods.deriveList(manifests,
    { mods = {}, modOrder = { "vc", "va", "vb" } })
  local seen, labels = {}, {}
  local realButton = Kit.button
  Kit.button = function(x, y, w, h, label, opts)
    if opts and opts.id then
      seen[opts.id] = { x = x, y = y, w = w, h = h, opts = opts }
      labels[opts.id] = label
    end
    return realButton(x, y, w, h, label, opts)
  end
  local texts = {}
  local realText = Kit.text
  Kit.text = function(font, s, ...)
    texts[#texts + 1] = s
    return realText(font, s, ...)
  end
  for _, size in ipairs({ { 1280, 2400 }, { 360, 3200 } }) do
    window(size[1], size[2])
    seen, labels, texts = {}, {}, {}
    local imp = RomImporter.new(function() end, { launcher = true })
    imp.tab = "mods"
    imp.ready = { red = true }
    imp.mods = rows
    imp.modSort = "order"
    local moved
    imp._moveMod = function(_, id, delta) moved = { id, delta } end
    local ok, err = pcall(LauncherView.draw, imp)
    T.check(ok, ("%dx%d draws: %s"):format(size[1], size[2], tostring(err)))
    local tag = size[1] .. "x" .. size[2]
    T.check(seen["mod-up-va"] ~= nil and seen["mod-down-va"] ~= nil,
      tag .. ": up/down buttons are drawn for a visible row")
    T.check(seen["mod-up-vc"] and seen["mod-up-vc"].opts.enabled == false,
      tag .. ": the first mod cannot move up")
    T.check(seen["mod-down-vb"] and seen["mod-down-vb"].opts.enabled == false,
      tag .. ": the last mod cannot move down")
    local found = false
    for _, s in ipairs(texts) do
      if type(s) == "string" and s:find("^#1  Gamma") then found = true end
    end
    T.check(found, tag .. ": the list is sorted by load order with #n badges")
    local det, up = seen["mod-row-va"], seen["mod-up-va"]
    if det and up then
      T.check(det.y == up.y and det.x + det.w <= up.x,
        tag .. ": the move buttons share the Details line, row height unchanged")
    end
    seen["mod-down-va"].opts.action()
    T.eq(moved and moved[1], "va", tag .. ": Down moves that mod")
    T.eq(moved and moved[2], 1, tag .. ": by one slot")
    imp._modActions = "va"
    seen, texts = {}, {}
    imp._uiActions = {}
    ok, err = pcall(LauncherView.draw, imp)
    T.check(ok, tag .. " details modal draws: " .. tostring(err))
    T.check(seen["modact-up"] and seen["modact-down"] and seen["modact-top"]
      and seen["modact-bottom"], tag .. ": Details offers the four Move buttons")
    T.check(seen["modact-top"] and seen["modact-top"].opts.enabled == true,
      tag .. ": the middle mod can move to the top")
    seen["modact-bottom"].opts.action()
    T.eq(moved and moved[2], math.huge, tag .. ": Move to bottom")
    imp._modActions = nil
    imp._sortPopup = "mods"
    seen = {}
    pcall(LauncherView.draw, imp)
    T.check(seen["sortpop-order"] ~= nil, tag .. ": Load order is a MODS sort")
    T.check(seen["sortpop-reset-order"] ~= nil, tag .. ": with a reset button")
    imp._sortPopup = "find"
    seen = {}
    pcall(LauncherView.draw, imp)
    T.check(seen["sortpop-order"] == nil, tag .. ": but not a FIND sort")
  end
  Kit.button, Kit.text = realButton, realText
end

T.finish("mod load order (#2177)")
