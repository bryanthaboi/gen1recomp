package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ModUpdate = require("src.mods.ModUpdate")
local LauncherMods = require("src.mods.LauncherMods")
local Platform = require("src.core.Platform")
local CartStore = require("src.carts.CartStore")
local RomImporter = require("src.import.RomImporter")

local RELEASES = {
  { version = "2.0.0", zip = { url = "https://example.invalid/a.zip" } },
  { version = "1.0.0", zip = { url = "https://example.invalid/b.zip" } },
}

local FEED_CART = {
  kind = "cart", id = "wild_green", title = "Wild Green", author = "Ren",
  version = "0.29.1", base = "red", seal = "sealed",
  repo = "https://github.com/ren/wild-green", github = "ren/wild-green",
  update_check = "ok",
  latest = { version = "0.29.1", tag = "v0.29.1",
             zip = { name = "wild_green-0.29.1.g1rcart",
                     url = "https://example.invalid/wild_green.g1rcart" } },
}

local function feedAt(version)
  local entry = {}
  for k, v in pairs(FEED_CART) do entry[k] = v end
  entry.version = version
  entry.latest = { version = version, tag = "v" .. version,
                   zip = { name = "wild_green-" .. version .. ".g1rcart",
                           url = "https://example.invalid/wild_green.g1rcart" } }
  return entry
end

local oldBeginFetch = ModUpdate.beginFetchReleases
local oldBeginZip = ModUpdate.beginDownloadZip
local oldPumpZip = ModUpdate.pumpDownloadZip
local oldInstall = LauncherMods.installDownloadedZip
local oldDeps = LauncherMods.checkDependencies
local oldRemote = Platform.canFetchRemote
local oldCartList = CartStore.list
local oldCartIndex = CartStore.index
local oldCartListFor = CartStore.listFor
local oldCartInstall = CartStore.install

local failId = nil
local installs = {}
local cartRows = {}
local cartInstalls = {}
local cartInstallErr = nil

ModUpdate.beginFetchReleases = function() return {} end
ModUpdate.beginDownloadZip = function() return {} end
ModUpdate.pumpDownloadZip = function()
  love.filesystem.write("install.zip", "CART BYTES")
  return true, "install.zip"
end
LauncherMods.installDownloadedZip = function(id, _, version)
  installs[#installs + 1] = id
  if id == failId then return nil, "the archive had no manifest" end
  return true, version
end
LauncherMods.checkDependencies = function() return { hasIssues = false } end
Platform.canFetchRemote = function() return true end
CartStore.list = function() return cartRows end
CartStore.listFor = function() return {} end
CartStore.index = function()
  local out = {}
  for _, row in ipairs(cartRows) do
    out[#out + 1] = { id = row.id, title = row.title, version = row.version }
  end
  return out
end
CartStore.install = function(bytes)
  cartInstalls[#cartInstalls + 1] = tostring(bytes)
  if cartInstallErr then return nil, cartInstallErr end
  return { id = "wild_green", title = "Wild Green", version = "0.29.1",
           base = "red" }
end
local function installedCart(version, repo)
  return { { id = "wild_green", title = "Wild Green", version = version,
             cart = { id = "wild_green", version = version, repo = repo } } }
end

local function info(status, best)
  return { status = status, latest = best and best.version or nil,
           best = best, releases = RELEASES }
end

local function launcher(secondStatus, feedCarts)
  local ri = setmetatable({
    mods = {
      { id = "one", name = "One", version = "1.0.0", github = "a/one" },
      { id = "two", name = "Two", version = "1.0.0", github = "a/two" },
      { id = "three", name = "Three", version = "1.0.0" },
    },
    modUpdateInfo = {
      one = info("available", RELEASES[1]),
      two = info(secondStatus or "current",
        secondStatus == "available" and RELEASES[1] or nil),
    },
    activeCart = {},
    carts = {},
    findLoaded = true,
    findIndex = { mods = {}, carts = feedCarts or {} },
  }, RomImporter)
  ri._refreshMods = function() end
  return ri
end

local function run(ri, frames)
  for _ = 1, frames or 40 do
    if not ri._updateAll then break end
    ri:_pumpUpdateAll()
    if ri._updateAll and ri._updateAll.stage == "confirm" then
      ri:_confirmUpdateAll()
    end
    ri:_pumpModInstall()
    ri:_pumpCartInstall()
  end
end


do
  local ri = launcher()
  local rows = ri:_updateAllRows()
  eq(#rows, 1, "only a mod whose badge says a release is available is queued")
  eq(rows[1].id, "one", "the current mod and the one with no github stay out")

  ri.modCartPlan = function() return "cart1", { pins = {} }, "gold" end
  eq(#ri:_updateAllRows(), 0, "a cart owns its mod set, so it offers no rows")
end


do
  cartRows = installedCart("0.2.0", "ren/wild-green")
  local ri = launcher(nil, { FEED_CART })
  local rows = ri:_updateAllRows()
  eq(#rows, 2, "an installed cart the index lists ahead of it is swept too")
  eq(rows[1].kind, "mod", "mods keep their place at the front of the queue")
  eq(rows[2].kind, "cart", "and the cart rows follow")
  eq(rows[2].id, "wild_green", "named by the installed cart")
  eq(rows[2].from, "0.2.0", "from what is on disk")
  eq(rows[2].to, "0.29.1", "to what the feed lists")

  cartRows = installedCart("0.2.0", "someoneelse/wild-green")
  eq(#launcher(nil, { FEED_CART }):_updateAllCartRows(), 0,
    "a cart of the same id from another repo is never overwritten")

  cartRows = { { id = "wild_green", title = "Wild Green", version = "0.2.0" } }
  local noRepo = launcher(nil, { FEED_CART }):_updateAllCartRows()
  eq(#noRepo, 1,
    "a manifest that names no repo matches by id, as the Find tab does")
  eq((noRepo[1] or {}).to, "0.29.1", "and is offered the listed version")

  cartRows = installedCart("0.29.1", "ren/wild-green")
  eq(#launcher(nil, { FEED_CART }):_updateAllCartRows(), 0,
    "a cart already at the listed version is not queued")

  cartRows = installedCart("1.0.0", "ren/wild-green")
  eq(#launcher(nil, { FEED_CART }):_updateAllCartRows(), 0,
    "and one ahead of it is never downgraded")
  cartRows = {}
end


do
  installs, cartInstalls = {}, {}
  cartRows = installedCart("0.2.0", "someoneelse/wild-green")
  local ri = launcher(nil, { FEED_CART })
  ri.modUpdateInfo = {}
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  run(ri)
  eq(#cartInstalls, 0, "a cart from another repo is still never overwritten")
  check(ri.modNotice.text ~= "Everything is up to date.",
    "but the sweep no longer reports the skip as up to date")
  eq(#(ri.modNotice.failures or {}), 1, "it names the cart it passed over")
  check(tostring((ri.modNotice.failures or {})[1]):find(
    "ren/wild-green", 1, true) ~= nil, "with the repo the feed lists it under")
  cartRows = {}
end


do
  installs, cartInstalls = {}, {}
  cartRows = installedCart("0.29.1", "ren/wild-green")
  local ri = launcher(nil, { FEED_CART })
  ri.modUpdateInfo = {}
  local refreshes = {}
  ri._refreshFindSources = function(self)
    self.findSources = { { feed = "https://example.invalid/index.json" } }
  end
  ri._refreshFind = function(self, force, opts)
    refreshes[#refreshes + 1] = { force = force, quiet = opts and opts.quiet }
    self._findFetch = {}
  end
  check(ri:pressUpdateAllMods(), "the press starts the queue")
  ri._modInfoFetch = nil
  ri:_pumpUpdateAll()
  eq(#refreshes, 1, "the sweep fetches the cart feed itself")
  eq((refreshes[1] or {}).force, true,
    "forced, not served from the day-old cache")
  eq((refreshes[1] or {}).quiet, true,
    "and quiet, since the sweep owns the overlay")
  eq((ri._updateAll or {}).stage, "check", "the queue waits for that fetch")
  eq(#cartInstalls, 0, "installing nothing against the cached listing")

  ri._findFetch = nil
  ri.findIndex = { mods = {}, carts = { feedAt("0.30.0") } }
  run(ri)
  eq(#refreshes, 1, "one forced fetch per sweep, never one per row")
  eq(#cartInstalls, 1, "the release the fresh feed lists is installed")
  eq(ri.findNotice, nil, "with no FIND notice left behind")
  eq(ri.modNotice.text, "Updated 1 items.", "and the run is reported")
  cartRows = {}
end


do
  cartInstalls = {}
  cartRows = { { id = "wild_green", title = "Wild Green", version = "0.2.0",
                 cart = { id = "wild_green", version = "0.2.0" } } }
  local function sweep()
    local ri = launcher(nil, { feedAt("0.2.0") })
    ri.modUpdateInfo = {}
    ri._refreshFindSources = function(self)
      self.findSources = { { feed = "https://example.invalid/index.json" } }
    end
    ri._refreshFind = function(self) self._findFetch = {} end
    ri:pressUpdateAllMods()
    ri._modInfoFetch = nil
    ri:_pumpUpdateAll()
    ri._findFetch = nil
    ri.findIndex = { mods = {}, carts = { feedAt("0.29.1") } }
    for _ = 1, 40 do
      if not ri._updateAll or ri._updateAll.stage == "confirm" then break end
      ri:_pumpUpdateAll(); ri:_pumpModInstall(); ri:_pumpCartInstall()
    end
    return ri
  end

  local ri = sweep()
  eq((ri._updateAll or {}).stage, "confirm",
    "a launcher-authored cart the fresh feed lists ahead is asked about first")
  eq(#cartInstalls, 0, "and nothing is installed before the answer")
  eq((ri._modConfirm or {}).kind, "updateAllRun", "the dialog is on screen")
  eq(((ri._modConfirm or {}).lines or {})[1], "Update 1 items?",
    "built from the fresh feed, not the cached one")
  eq(((ri._modConfirm or {}).lines or {})[2], "Wild Green",
    "naming the cart that would be replaced")
  eq(ri._busy, nil, "with the overlay down")
  ri._modConfirm = nil
  run(ri)
  eq(ri._updateAll, nil, "declining ends the sweep")
  eq(#cartInstalls, 0, "with the cart left alone")
  eq(ri.modNotice, nil, "and no notice for a run that never started")

  ri = sweep()
  check(ri:_confirmUpdateAll(), "accepting the dialog")
  run(ri)
  eq(#cartInstalls, 1, "installs the listed release")
  eq(ri.modNotice.text, "Updated 1 items.", "and reports it")
  cartRows = {}
end


do
  cartInstalls = {}
  cartRows = installedCart("0.2.0", "ren/wild-green")
  local ri = launcher(nil, { FEED_CART })
  ri.modUpdateInfo = {}
  ri._refreshFindSources = function(self)
    self.findSources = { { feed = "https://example.invalid/index.json" } }
  end
  ri._refreshFind = function(self) self._findFetch = {} end
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  ri:_pumpUpdateAll()
  check(ri._findFetch ~= nil, "the feed fetch is in flight")
  check(type(ri._busy.cancel) == "function", "behind a cancellable overlay")
  ri:_cancelUpdateAll()
  eq(ri._updateAll, nil, "cancelling there ends the sweep on the spot")
  eq(#cartInstalls, 0, "with nothing installed")
  check(ri._findFetch ~= nil, "and the fetch left to finish on its own")
  check(ri.modNotice.text:find("Stopped after updating", 1, true) ~= nil,
    "and says how far it got")
  cartRows = {}
end


do
  installs, cartInstalls = {}, {}
  cartRows = installedCart("0.2.0", "ren/wild-green")
  local ri = launcher(nil, { FEED_CART })
  check(ri:pressUpdateAllMods(), "the press starts the queue")

  ri._modInfoFetch = nil
  ri._findFetch = {}
  ri:_pumpUpdateAll()
  eq(ri._updateAll.stage, "check", "the queue waits for the index feed too")
  eq(#cartInstalls, 0, "and installs nothing meanwhile")

  ri._findFetch = nil
  run(ri)
  eq(ri._updateAll, nil, "the queue finishes")
  eq(#installs, 1, "the mod went through the mod installer")
  eq(installs[1], "one", "by id")
  eq(#cartInstalls, 1, "and the cart through CartStore.install, not that one")
  eq(ri.findNotice, nil, "with no FIND notice raised mid-sweep")
  eq(ri._modConfirm, nil, "and no pin modal to click through")
  check(ri.modNotice and ri.modNotice.ok, "the run is reported")
  eq(ri.modNotice.text, "Updated 2 items.", "counting both kinds")
end


do
  installs, cartInstalls = {}, {}
  cartInstallErr = "the cart file was truncated"
  cartRows = installedCart("0.2.0", "ren/wild-green")
  local ri = launcher(nil, { FEED_CART })
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  run(ri)
  cartInstallErr = nil
  eq(#installs, 1, "a failed cart does not stop the mod half")
  eq(ri.modNotice.text, "Updated 1 of 2. 1 failed:", "and is counted")
  eq(#ri.modNotice.failures, 1, "with one line")
  check(ri.modNotice.failures[1]:find("Wild Green", 1, true) ~= nil,
    "naming the cart")
  cartRows = {}
end


do
  cartInstalls = {}
  cartRows = installedCart("0.2.0", "ren/wild-green")
  local ri = launcher(nil, { FEED_CART })
  local seen = {}
  ri._updateAll = { stage = "installing" }
  ri:_beginCartInstall(FEED_CART, { quiet = true, fromUpdateAll = true,
    done = function(ok) seen[#seen + 1] = ok end })
  check(ri._cartInstall ~= nil, "the queue's own cart install is let through")
  ri:_pumpCartInstall()
  eq(#cartInstalls, 1, "the bytes reach CartStore.install")
  eq(ri.findNotice, nil, "a quiet cart install writes no FIND notice")
  eq(ri._modConfirm, nil, "and raises no pin modal mid-queue")
  eq(#seen, 1, "the queue is told the row is done")
  eq(seen[1], true, "and that it worked")
  cartRows = {}
end


do
  installs = {}
  local ri = launcher("available")
  check(ri:pressUpdateAllMods(), "the press starts the queue")
  check(ri._busy ~= nil, "behind the blocking overlay")
  check(type(ri._busy.cancel) == "function", "which can be cancelled")
  check(ri._modInfoFetch ~= nil, "the release checks are refreshed first")

  ri:_pumpUpdateAll()
  eq(ri._updateAll.stage, "check", "the queue waits for them to drain")
  eq(#installs, 0, "and installs nothing meanwhile")

  ri._modInfoFetch = nil
  ri:_pumpUpdateAll()
  eq(ri._updateAll.total, 2, "then queues every outdated mod")
  eq(ri._updateAll.stage, "confirm", "and stops to ask before installing")
  eq(ri._busy, nil, "with the overlay down so the dialog can be answered")
  eq((ri._modConfirm or {}).kind, "updateAllRun", "the dialog is up")
  eq(((ri._modConfirm or {}).lines or {})[1], "Update 2 items?",
    "counting the rows built after the release checks")
  eq(((ri._modConfirm or {}).lines or {})[2], "One", "and naming them")
  ri:_pumpUpdateAll()
  eq(ri._updateAll.index, 0, "no row starts while the dialog waits")

  check(ri:_confirmUpdateAll(), "accepting the dialog")
  eq(ri._modConfirm, nil, "takes it down")
  check(ri._busy ~= nil, "and puts the overlay back")
  eq(ri._updateAll.index, 1, "one row is started")
  ri:_pumpUpdateAll()
  eq(ri._updateAll.index, 1, "and the next waits for it, not for the frame")
  eq(#installs, 0, "nothing has unzipped yet")

  run(ri)
  eq(ri._updateAll, nil, "the queue finishes")
  eq(#installs, 2, "having installed both rows")
  eq(installs[1], "one", "in feed order")
  eq(installs[2], "two", "one after the other")
  check(ri.modNotice and ri.modNotice.ok, "and reports the run")
  eq(ri.modNotice.text, "Updated 2 items.", "as one summary")
  eq(ri._busy, nil, "with the overlay down")
end


do
  installs = {}
  failId = "two"
  local ri = launcher("available")
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  run(ri)
  failId = nil
  eq(#installs, 2, "the queue carries on past a failure")
  check(ri.modNotice and not ri.modNotice.ok, "and says the run was partial")
  eq(ri.modNotice.text, "Updated 1 of 2. 1 failed:", "with the counts")
  eq(#ri.modNotice.failures, 1, "naming what failed")
  check(ri.modNotice.failures[1]:find("Two", 1, true) ~= nil,
    "by the mod's own name")
end


do
  local ri = launcher()
  ri.modUpdateInfo = {}
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  run(ri)
  eq(ri.modNotice.text, "Everything is up to date.",
    "a run with no outdated mod or cart says so rather than going quiet")
end

do
  Platform.canFetchRemote = function() return false end
  local ri = launcher("available")
  local refreshed = false
  ri._refreshFind = function() refreshed = true end
  check(ri:pressUpdateAllMods() == false, "no remote fetch, no queue")
  eq(ri._updateAll, nil, "nothing is started")
  eq(refreshed, false, "and the cart feed is not fetched either")
  check(ri.modNotice and not ri.modNotice.ok, "and the refusal is on screen")
  Platform.canFetchRemote = function() return true end
end


do
  installs = {}
  local ri = launcher("available")
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  ri:_pumpUpdateAll()
  ri:_confirmUpdateAll()
  ri:_pumpModInstall()
  eq(#installs, 1, "one row is through")
  ri:_cancelUpdateAll()
  check(ri._updateAll == nil or ri._updateAll.cancelled,
    "the cancel is taken")
  run(ri)
  eq(ri._updateAll, nil, "the queue stops")
  eq(#installs, 1, "without starting the rest")
  check(ri.modNotice.text:find("Stopped after updating", 1, true) ~= nil,
    "and says how far it got")
end

do
  local ri = launcher("available")
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  ri:_pumpUpdateAll()
  ri:_confirmUpdateAll()
  check(ri._modInstall ~= nil, "a row is downloading")
  ri:_cancelUpdateAll()
  check(ri._busy ~= nil,
    "cancelling mid-download keeps the overlay: the download has no abort")
  run(ri)
  eq(ri._busy, nil, "and it comes down once that row is done")
end


do
  installs = {}
  local ri = launcher()
  ri:_beginModInstall({ modId = "one", name = "One", release = RELEASES[1],
                        verb = "Updated", notice = "mod", quiet = true })
  ri:_pumpModInstall()
  eq(ri.modNotice, nil, "a quiet install writes no per-mod notice")
  eq(ri._modDepResolver, nil, "and raises no dependency modal mid-queue")
end

do
  local ri = launcher("available")
  ri.cartFillRows = function()
    return { { id = "one", name = "One", release = RELEASES[1] } }
  end
  eq(ri:pressInstallCartMods("red"), true,
    "a cart fill starts when nothing else is running")
  ri._cartFill = nil

  ri:pressUpdateAllMods()
  check(ri._updateAll ~= nil, "the update-all queue is live")
  eq(ri:pressInstallCartMods("red"), false,
    "a cart fill refuses in the frame the queue is between rows")
  eq(ri._cartFill, nil, "and starts nothing")

  ri:_beginCartInstall({ id = "cart", title = "Cart",
    releases = { { version = "1.0.0", zip = { url = "https://x.invalid/c.zip" } } } })
  eq(ri._cartInstall, nil, "a cart install refuses there too")
  eq(ri.findNotice, nil, "silently, since the overlay owns the screen")
end


do
  love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
  love.graphics.newShader = love.graphics.newShader or function() return {} end
  love.graphics.polygon = love.graphics.polygon or function() end
  local LauncherView = require("src.import.LauncherView")
  local Kit = require("src.ui.kit.Kit")

  local realPrint = love.graphics.print
  local realButton = Kit.button
  local buttons, kinds = {}, {}
  local function draw(imp)
    local seen = {}
    buttons, kinds = {}, {}
    love.graphics.print = function(str, ...)
      seen[#seen + 1] = tostring(str)
      return realPrint(str, ...)
    end
    Kit.button = function(x, y, w, h, label, opts)
      buttons[tostring(label)] = not (opts and opts.enabled == false)
      kinds[tostring(label)] = opts and opts.kind or nil
      return realButton(x, y, w, h, label, opts)
    end
    local ok, err = pcall(LauncherView.draw, imp)
    love.graphics.print = realPrint
    Kit.button = realButton
    check(ok, "the frame draws: " .. tostring(err))
    return table.concat(seen, "\n")
  end
  local function window(w, h)
    love.graphics.getDimensions = function() return w, h end
    love.graphics.getPixelDimensions = function() return w, h end
  end

  local imp = RomImporter.new(function() end, { launcher = true })
  imp._ensureMods = function() end
  imp._refreshMods = function() end
  imp.findLoaded, imp._findFetch = true, nil
  imp.mods = launcher("available").mods
  imp.modUpdateInfo = { one = info("available", RELEASES[1]) }
  imp.tab = "mods"

  window(1400, 900)
  local wide = draw(imp)
  check(wide:find("Update all", 1, true) ~= nil,
    "a wide header carries Update all beside Check for updates")

  local cache = imp._modUpdateCountCache
  eq(cache and cache.count, 1, "the header counts the one outdated mod")
  draw(imp)
  check(rawequal(imp._modUpdateCountCache, cache),
    "and a second frame reuses that count instead of rebuilding a list")
  imp.modUpdateInfo.two = info("available", RELEASES[1])
  imp._modUpdateRev = (imp._modUpdateRev or 0) + 1
  draw(imp)
  eq(imp._modUpdateCountCache.count, 2,
    "a bumped update revision rebuilds it")

  window(430, 860)
  local narrow = draw(imp)
  check(narrow:find("More...", 1, true) ~= nil,
    "a phone-width header collapses to More...")
  imp._modHeaderActionsPopup = true
  local popup = draw(imp)
  imp._modHeaderActionsPopup = nil
  check(popup:find("Update all", 1, true) ~= nil,
    "and More... is where a phone reaches Update all")

  window(1400, 900)
  cartRows = installedCart("0.2.0", "ren/wild-green")
  imp.mods = {}
  imp._modUpdateCountCache = nil
  imp._cartUpdateCache = nil
  imp._findCartMap = nil
  imp.findIndex = { mods = {}, carts = { FEED_CART } }
  local cartsOnly = draw(imp)
  check(cartsOnly:find("Update all", 1, true) ~= nil,
    "a launcher with carts but no mods still reaches the sweep")

  imp.mods = launcher("available").mods
  imp.modUpdateInfo = { one = info("available", RELEASES[1]) }
  imp._modUpdateCountCache = nil
  imp.modScope = "red"
  imp.activeCart = { red = "wild_green" }
  imp.modCartPlan = function()
    return "wild_green", { pins = {}, order = {}, seal = "sealed",
                           title = "Wild Green" }, "red"
  end
  local underCart = draw(imp)
  check(underCart:find("Update all", 1, true) ~= nil,
    "a selected cart still shows the sweep in the header")
  eq(buttons["Update all"], true,
    "and it is live there: replacing a cart with a newer release is legal")
  eq(buttons["Enable all"], false,
    "while the bulk pair stays refused, since the cart owns its pins")
  eq(buttons["Disable all"], false, "on both halves of that pair")
  local underRows = imp:_updateAllRows()
  eq(#underRows, 1, "the sweep queues the cart alone")
  eq(underRows[1].kind, "cart", "and never a pinned mod")
  eq(imp._modUpdateCountCache.count, 1,
    "the header count is the sweep's own rows, not the pinned mods' badges")
  eq(kinds["Update all"], "warn", "and the cart behind tints the button")

  cartRows = installedCart("0.29.1", "ren/wild-green")
  imp._modUpdateCountCache = nil
  imp._cartUpdateCache = nil
  imp._findCartMap = nil
  draw(imp)
  eq(buttons["Update all"], true,
    "with nothing behind it the button stays live and says so when pressed")
  eq(kinds["Update all"], "ghost",
    "untinted: a pinned mod's own badge is not the sweep's business")
  eq(#imp:_updateAllRows(), 0, "and the sweep has nothing to run")
  cartRows = installedCart("0.2.0", "ren/wild-green")
  imp._modUpdateCountCache = nil
  imp._cartUpdateCache = nil
  imp._findCartMap = nil

  window(430, 860)
  imp._modHeaderActionsPopup = true
  local cartPopup = draw(imp)
  imp._modHeaderActionsPopup = nil
  eq(buttons["Update all"], true, "More... reaches the same live button")
  eq(buttons["Enable all mods"], false, "with the bulk pair still refused")
  eq(buttons["Disable all mods"], false, "on both rows")
  check(cartPopup:find("decides which mods run", 1, true) ~= nil,
    "and the modal says why those two are grey")

  window(1400, 900)
  imp._updateAll = { stage = "check" }
  draw(imp)
  eq(buttons["Update all"], false, "a sweep already in flight disables it")
  imp._updateAll = nil
  imp.safeMode = true
  draw(imp)
  eq(buttons["Update all"], false, "and safe mode disables it too")
  imp.safeMode = false
  imp.modCartPlan = nil
  cartRows = {}
end

ModUpdate.beginFetchReleases = oldBeginFetch
ModUpdate.beginDownloadZip = oldBeginZip
ModUpdate.pumpDownloadZip = oldPumpZip
LauncherMods.installDownloadedZip = oldInstall
LauncherMods.checkDependencies = oldDeps
Platform.canFetchRemote = oldRemote
CartStore.list = oldCartList
CartStore.index = oldCartIndex
CartStore.listFor = oldCartListFor
CartStore.install = oldCartInstall

T.finish("launcher update all")
