-- Custom carts in the launcher.
--   luajit tests/engine/cart_launcher.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end
love.graphics.polygon = love.graphics.polygon or function() end

local Kit = require("src.ui.kit.Kit")
local SaveData = require("src.core.SaveData")
local CartManifest = require("src.carts.CartManifest")
local CartStore = require("src.carts.CartStore")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

local SHA = ("a1b2c3d4"):rep(8)

local function window(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

local function freshLauncher(onComplete)
  return RomImporter.new(onComplete or function() end, { launcher = true })
end

local realPrint = love.graphics.print
local function drawAndCapture(imp)
  local seen = {}
  love.graphics.print = function(str, ...)
    seen[#seen + 1] = tostring(str)
    return realPrint(str, ...)
  end
  local ok, err = pcall(LauncherView.draw, imp)
  love.graphics.print = realPrint
  check(ok, "the frame draws: " .. tostring(err))
  return table.concat(seen, "\n")
end

local realSetColor = love.graphics.setColor
local function drawColors(imp)
  local seen = {}
  love.graphics.setColor = function(r, g, b, a)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      seen[("%d,%d,%d"):format(math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))] = true
    end
    return realSetColor(r, g, b, a)
  end
  local ok, err = pcall(LauncherView.draw, imp)
  love.graphics.setColor = realSetColor
  check(ok, "the frame draws: " .. tostring(err))
  return seen
end

local function cartTable(over)
  local tbl = {
    id = "kanto_plus", title = "Kanto Plus", version = "1.2.0",
    author = "Ren", shell = "#3fa9f5", base = "red", seal = "sealed",
    mods = { { id = "rare_soda", source = "github", repo = "ren/rare-soda",
               version = "0.4.1", sha256 = SHA } },
  }
  for key, value in pairs(over or {}) do tbl[key] = value end
  return tbl
end

local function install(over)
  over = over or {}
  local cart, parseErr = CartManifest.parse(cartTable(over))
  check(cart ~= nil, "fixture parses: " .. tostring(parseErr))
  cart.labelArt = over.labelArt
  local ok, err = CartStore.install(CartManifest.encode(cart))
  check(ok ~= nil, "fixture installs: " .. tostring(err))
  return cart
end

install()
install({ id = "zeta_open", title = "Zeta Open", version = "0.9.0",
          seal = "open", shell = "#112233" })
install({ id = "johto_lite", title = "Johto Lite", base = "blue",
          shell = "#7a5c2e" })

window(1280, 720)

local imp = freshLauncher()
local red = imp:_ensureCarts("red")
eq(#red, 2, "red lists exactly the carts based on red")
eq(red[1].id, "kanto_plus", "the list is sorted by title")
eq(red[2].id, "zeta_open", "the list is sorted by title")
eq(#imp:_ensureCarts("blue"), 1, "blue lists only its own cart")
eq(imp:_ensureCarts("blue")[1].id, "johto_lite", "and that one is Johto Lite")
eq(#imp:_ensureCarts("yellow"), 0, "a game with no carts lists none")

-- A .g1rcart dropped into the carts folder by hand, with no registry entry:
-- the launcher must adopt it, not read past it.  _refreshCarts used to call
-- CartStore.index (registry only) and never saw one.
do
  local stray = CartManifest.parse(cartTable({
    id = "dropped_in", title = "Dropped In", version = "2.0.0" }))
  check(stray ~= nil, "the stray fixture parses")
  local opts = SaveData.loadOptions()
  opts[CartStore.OPTIONS_KEY] = nil
  SaveData.saveOptions(opts)
  love.filesystem.createDirectory(CartStore.DIR)
  love.filesystem.write(CartStore.fileFor("dropped_in"),
    CartManifest.encode(stray))

  local fresh = freshLauncher()
  local found
  for _, row in ipairs(fresh:_ensureCarts("red")) do
    if row.id == "dropped_in" then found = row end
  end
  check(found ~= nil, "the launcher lists a cart dropped into the folder")
  if found then
    eq(found.title, "Dropped In", "and reads its title from the file")
    eq(found.base, "red", "and its base game")
  end
  eq(CartStore.index()[1] ~= nil, true,
    "listing healed the registry so the cheap index sees it too")

  -- Put the fixture set back: later blocks assert on the picker's own layout,
  -- and a third red cart changes its height.
  CartStore.uninstall("dropped_in")
end

imp.tab = "red"
imp.ready.red = true
imp._cartPopup = "red"
local picker = drawAndCapture(imp)
check(picker:find("Pokemon Red", 1, true) ~= nil,
  "the picker offers the base game as the first row")
check(picker:find("Kanto Plus", 1, true) ~= nil, "the picker lists Kanto Plus")
check(picker:find("Zeta Open", 1, true) ~= nil, "the picker lists Zeta Open")
check(picker:find("Johto Lite", 1, true) == nil,
  "the picker does NOT list a cart based on another game")
check(picker:find("v1.2.0", 1, true) ~= nil, "a cart row carries its version")
check(picker:find("sealed", 1, true) ~= nil, "a cart row carries its seal state")
check(picker:find("open", 1, true) ~= nil, "including an open one")
check(picker:find("Import a cart", 1, true) ~= nil
    or picker:find("Get more carts", 1, true) ~= nil,
  "the last row imports a cart, by picker or by folder")

imp._cartPopup = nil
local vanillaColors = drawColors(imp)
check(vanillaColors["63,169,245"] == nil,
  "a vanilla page never paints the cart's shell colour")

imp:_selectCart("red", "kanto_plus")
eq(imp.activeCart.red, "kanto_plus", "the pick lands on activeCart")
eq(imp._cartPopup, nil, "picking closes the picker")

local titled = drawAndCapture(imp)
check(titled:find("Kanto Plus", 1, true) ~= nil,
  "the panel title becomes the cart's title")

local cartColors = drawColors(imp)
eq(cartColors["63,169,245"], true,
  "the cartridge takes the cart's shell colour")

eq(imp.tab, "red", "a cart id never reaches imp.tab")
eq(imp.panelVersion, "red", "a cart id never reaches imp.panelVersion")

check(imp._cartridge["cart:kanto_plus"] ~= nil,
  "the cart spins on its own cartridge state")
check(imp._cartridge["cart:kanto_plus"] ~= imp._cartridge.red,
  "which is not the base game's")
eq(imp._cartridgeLabels["cart:kanto_plus"], false,
  "a cart carrying no label art falls through to bare plastic")

local scope = imp:slotScope("red")
eq(scope, "cart_kanto_plus", "an active cart scopes the panel's save slots")
imp:_newSlot(scope)
imp:_newSlot(scope)
eq(#SaveData.listCartSlots("kanto_plus"), 2, "both slots land in the cart")
eq(#SaveData.listSlots("red"), 0, "and none of them in the base game")
imp:_ensureSlots(scope)
eq(#imp.slots[scope], 2, "the panel reads the cart's slots back")

imp:_beginRename(scope, "slot1")
imp._rename.text = "Nuzlocke"
imp:_commitRename()
eq(SaveData.listCartSlots("kanto_plus")[1].label, "Nuzlocke",
  "a rename writes into the cart's registry")

imp:_selectSlot(scope, "slot2")
eq(SaveData.activeCartSlot("kanto_plus"), "slot2",
  "selecting a row moves the cart's active slot")
imp:_deleteSlot(scope, "slot2")
eq(#SaveData.listCartSlots("kanto_plus"), 1, "a delete removes the cart's slot")

local withCart = drawAndCapture(imp)
check(withCart:find("Nuzlocke", 1, true) ~= nil,
  "the slot card shows the cart's slots while the cart is active")

imp:_selectCart("red", nil)
eq(imp.activeCart.red, nil, "choosing the base game clears the active cart")
eq(imp:slotScope("red"), "red", "and the slots go back to the version's own")
imp:_newSlot("red")
eq(#SaveData.listSlots("red"), 1, "a vanilla slot lands in the version")
eq(#SaveData.listCartSlots("kanto_plus"), 1, "and not in the cart")

local backHome = drawAndCapture(imp)
check(backHome:find("Nuzlocke", 1, true) == nil,
  "the slot card no longer shows the cart's slots")
check(backHome:find("Kanto Plus", 1, true) == nil,
  "and the panel title is the base game's again")
local homeColors = drawColors(imp)
check(homeColors["63,169,245"] == nil,
  "the cartridge is back to the base game's shell")

local handed = {}
local player = freshLauncher(function(version, cartId)
  handed.version, handed.cart = version, cartId
end)
player.ready.red = true
player:_selectCart("red", "kanto_plus")
player:play("red")
eq(handed.version, "red", "Play still boots the base game")
eq(handed.cart, "kanto_plus", "and names the cart it is running")

local opts = SaveData.loadOptions()
eq(opts.lastVersion, "red", "play still remembers the version")
eq(type(opts.activeCart) == "table" and opts.activeCart.red or nil, "kanto_plus",
  "play persists the active cart beside it")

local restored = freshLauncher()
eq(restored.activeCart.red, "kanto_plus",
  "a fresh launcher restores the cart its page was on")
eq(restored.tab, "red", "and a cart id still never reaches the tab")

local uninstalled = freshLauncher()
uninstalled.activeCart.red = nil
uninstalled:_restoreActiveCarts({ activeCart = { red = "gone_forever" } })
eq(uninstalled.activeCart.red, nil,
  "a remembered cart that is no longer installed is dropped")

local Base64 = require("src.core.Base64")
local PNG = CartManifest.PNG_SIGNATURE .. ("labelart"):rep(4)
local function artOf()
  return { encoding = "base64", bytes = #PNG, data = Base64.encode(PNG) }
end

install({ id = "art_cart", title = "Art Cart", base = "yellow",
          shell = "#204060", labelArt = artOf() })
install({ id = "bare_cart", title = "Bare Cart", base = "yellow",
          shell = "#405060" })
install({ id = "bad_cart", title = "Bad Cart", base = "yellow",
          shell = "#605040", labelArt = artOf() })

check(CartStore.labelArt("art_cart") == PNG,
  "the store hands back the cart's own PNG bytes")
check(CartStore.labelArt("bare_cart") == nil,
  "and nothing for a cart that carries none")

window(1280, 720)
local realNewImage = love.graphics.newImage
local madeImages = 0
love.graphics.newImage = function(...)
  madeImages = madeImages + 1
  return realNewImage(...)
end

local art = freshLauncher()
art.tab = "yellow"
art.ready.yellow = true
art:_selectCart("yellow", "art_cart")
drawAndCapture(art)
local artLabel = art._cartridgeLabels["cart:art_cart"]
check(type(artLabel) == "table" and artLabel.image ~= nil,
  "a cart's own label art becomes a cached cartridge image")
local afterFirst = madeImages
drawAndCapture(art)
eq(madeImages, afterFirst, "the decode happens once, not every frame")

art:_selectCart("yellow", "bare_cart")
drawAndCapture(art)
eq(art._cartridgeLabels["cart:bare_cart"], false,
  "a cart with no art renders as bare plastic")
check(art._cartridgeLabels["cart:art_cart"] ~= art._cartridgeLabels["cart:bare_cart"],
  "and the two carts never share one label cache entry")

love.graphics.newImage = function(a, ...)
  if type(a) == "table" and a._fileData then error("not a PNG this engine reads") end
  return realNewImage(a, ...)
end
local bad = freshLauncher()
bad.tab = "yellow"
bad.ready.yellow = true
bad:_selectCart("yellow", "bad_cart")
drawAndCapture(bad)
love.graphics.newImage = realNewImage
eq(bad._cartridgeLabels["cart:bad_cart"], false,
  "art that will not decode leaves the cart bare instead of throwing")
drawAndCapture(bad)
eq(bad._cartridgeLabels["cart:bad_cart"], false,
  "and it is not retried on the next frame")

local LauncherMods = require("src.mods.LauncherMods")
local realModList = LauncherMods.list

local function fakeRow(over)
  local row = { id = "x", name = "X", version = "1.0.0", badge = "MOD",
                description = "", enabled = true, status = "ok",
                statusDetail = "", experimental = false, targetsHere = true,
                targets = nil, safeMode = false, requiredImports = {},
                imports = {}, missingRequiredImports = 0,
                missingOptionalImports = 0,
                enabledByVersion = { red = true, blue = true, yellow = true,
                                     gold = true, silver = true } }
  for key, value in pairs(over) do row[key] = value end
  row.manifest = row.manifest or { id = row.id, name = row.name,
                                   version = row.version }
  return row
end

local FAKE_MODS = {
  fakeRow({ id = "rare_soda", name = "Rare Soda", version = "0.4.1",
            github = "ren/rare-soda", sha256 = SHA }),
  fakeRow({ id = "wide_gym", name = "Wide Gym", version = "dev" }),
  fakeRow({ id = "off_mod", name = "Off Mod", enabled = false,
            enabledByVersion = { red = false } }),
}

local modsView = freshLauncher()
modsView.tab = "mods"
local modsText = drawAndCapture(modsView)
check(modsText:find("Save as cart", 1, true) ~= nil,
  "the mods tab carries the Save as cart control")

LauncherMods.list = function() return FAKE_MODS end

local maker = freshLauncher()
maker.tab = "red"
maker.ready.red = true
maker:_setModScope("red")
eq(maker:_cartCaptureCount("red"), 3,
  "the control counts every mod the capture would pin, on or off")

maker:_beginCartSave("red")
check(maker._cartSave ~= nil, "Save as cart opens a form")
eq(maker._cartSave.count, 3, "the form reports the captured mod count")
eq(maker._cartSave.version, "red", "scoped to the game the panel is showing")
eq(#maker._cartSave.unresolved, 2, "capture reports the pins it could not resolve")
eq(maker._cartSave.unresolved[1].id, "wide_gym", "naming the mod it belongs to")
check(tostring(maker._cartSave.unresolved[1].reason):find("semantic", 1, true) ~= nil,
  "and why it could only be pinned locally")
eq(maker._cartSave.publishable, false, "a local pin makes the cart unpublishable")

local form = drawAndCapture(maker)
check(form:find("Save as cart", 1, true) ~= nil, "the form is titled")
check(form:find("Wide Gym", 1, true) ~= nil,
  "the unresolved pin is named BEFORE the player confirms")
check(form:find("could only be pinned to this install", 1, true) ~= nil,
  "under a heading that says what a local pin means")
check(form:find("cannot be shared", 1, true) ~= nil,
  "and the form says plainly that the result cannot be shared")

maker._cartSave.text = "Kanto Plus"
maker:_commitCartSave()
check(maker._cartSave ~= nil, "a title that collides with an installed cart refuses")
check(tostring(maker._cartSave.error):find("kanto_plus", 1, true) ~= nil,
  "and names the id that is already taken")
eq(CartStore.get("kanto_plus").title, "Kanto Plus",
  "the installed cart is untouched")

maker._cartSave.text = "Soda Run"
maker:_commitCartSave()
eq(maker._cartSave, nil, "a free title saves the cart and closes the form")
eq(maker._cartPopup, "red", "and drops the player straight into the picker")
local made = CartStore.get("soda_run")
check(made ~= nil, "the cart is installed under the id derived from the title")
eq(made.base, "red", "based on the game the panel was showing")
eq(made.version, "1.0.0", "at the default cart version")
eq(made.seal, "sealed", "sealed by default")
eq(made.shell, "#ff3c48", "wearing the base game's rail colour")
eq(#made.mods, 3, "pinning every installed mod, on or off")
local madeOff
for _, entry in ipairs(made.mods) do
  if entry.id == "off_mod" then madeOff = entry end
end
check(madeOff ~= nil, "including the one the player has switched off")
eq(madeOff.enabled, false, "which is pinned switched off rather than dropped")

local listedNow = false
for _, row in ipairs(maker:_ensureCarts("red")) do
  if row.id == "soda_run" then listedNow = true end
end
check(listedNow, "and the picker lists it immediately")
local picked = drawAndCapture(maker)
check(picked:find("Soda Run", 1, true) ~= nil, "including on screen")

LauncherMods.list = function() return { FAKE_MODS[1] } end
local pure = freshLauncher()
pure.tab = "red"
pure.ready.red = true
pure:_beginCartSave("red")
eq(#pure._cartSave.unresolved, 0, "a fully pinned capture has no local pins")
eq(pure._cartSave.publishable, true, "and it is publishable")
local pureForm = drawAndCapture(pure)
check(pureForm:find("can be shared", 1, true) ~= nil,
  "which the form says before the player confirms")
check(pureForm:find("cannot be shared", 1, true) == nil,
  "instead of the local-pin warning")
pure._cartSave.text = "Pure Soda"
pure:_commitCartSave()
eq(pure._cartSave, nil, "a fully pinned capture saves too")
local pureOk, pureWhy = CartManifest.publishable(CartStore.get("pure_soda"))
eq(pureOk, true, "and the saved cart really is publishable")
eq(pureWhy, nil, "with nothing holding it back")
LauncherMods.list = function() return FAKE_MODS end

local blank = freshLauncher()
blank:_beginCartSave("red")
blank:_commitCartSave()
check(blank._cartSave ~= nil, "an empty title does not save")
check(tostring(blank._cartSave.error):find("title", 1, true) ~= nil,
  "and asks for one")
blank:_cancelCartSave()
eq(blank._cartSave, nil, "Cancel closes the form")

LauncherMods.list = realModList

local exporter = freshLauncher()
exporter:exportCart("kanto_plus")
check(tostring(exporter._cartNotice):find("Exported", 1, true) ~= nil,
  "Export reports where the cart file went: " .. tostring(exporter._cartNotice))
local wroteBytes = love.filesystem.read("exports/carts/kanto_plus" .. CartStore.EXT)
check(type(wroteBytes) == "string" and wroteBytes ~= "",
  "and the bytes land in the same exports tree a save export uses")
eq(wroteBytes, (CartStore.export("kanto_plus")),
  "byte for byte what CartStore.export returned")
local roundTrip = CartManifest.decode(wroteBytes)
check(roundTrip ~= nil and roundTrip.id == "kanto_plus",
  "and the file decodes back into the cart")

exporter:exportCart("no_such_cart")
check(tostring(exporter._cartNotice):find("not installed", 1, true) ~= nil,
  "exporting a cart that is not installed says so")

window(1920, 1080)

local FULL_MODS = { fakeRow({ id = "rare_soda", name = "Rare Soda",
                              version = "0.4.1", github = "ren/rare-soda",
                              sha256 = SHA }) }

LauncherMods.list = function() return FULL_MODS end
local okCart = freshLauncher()
okCart.tab = "red"
okCart.ready.red = true
okCart:_selectCart("red", "kanto_plus")
local okPlan = okCart:cartPlan("red")
eq(okPlan.refused, false, "a cart whose pin is installed is playable")
eq(okPlan.sealed, true, "and is still sealed")
local okText = drawAndCapture(okCart)
check(okText:find("Sealed", 1, true) ~= nil,
  "the verdict is on the page before the player commits")
check(okText:find("Break the seal", 1, true) ~= nil,
  "and a sealed cart's page offers the escape hatch")

LauncherMods.list = function() return {} end
local gapCart = freshLauncher()
gapCart.tab = "red"
gapCart.ready.red = true
gapCart:_selectCart("red", "kanto_plus")
local gapPlan = gapCart:cartPlan("red")
eq(gapPlan.refused, true, "a cart with an uninstalled pin refuses")
eq(gapPlan.missing[1].id, "rare_soda", "naming the pin it cannot find")
local gapText = drawAndCapture(gapCart)
check(gapText:find("will not start", 1, true) ~= nil,
  "which the page says without the player booting into an error")
check(gapText:find("rare_soda", 1, true) ~= nil, "and names the pin")
check(gapText:find("Break the seal", 1, true) ~= nil,
  "with the escape hatch beside the refusal")

local sealScope = gapCart:slotScope("red")
gapCart:_ensureSlots(sealScope)
local sealSlot = gapCart.activeSlot[sealScope]
check(type(sealSlot) == "string", "the cart page has a loaded save slot")
eq(gapCart:pressBreakSeal("red"), false, "the first press only arms the confirm")
eq(SaveData.slotSealBroken("kanto_plus", sealSlot), false,
  "so one press breaks nothing")
local armedText = drawAndCapture(gapCart)
check(armedText:find("Kanto Plus", 1, true) ~= nil,
  "the armed confirm names the cart")
check(armedText:find("save slot", 1, true) ~= nil, "and the save slot")
check(armedText:find("cannot be undone", 1, true) ~= nil,
  "says it is permanent")
check(armedText:find("marked modified", 1, true) ~= nil,
  "says the file is marked modified from then on")
check(armedText:find("pinned mods first", 1, true) ~= nil,
  "and that the cart's own list still loads first")
eq(gapCart:pressBreakSeal("red"), true, "a second press breaks the seal")
eq(SaveData.slotSealBroken("kanto_plus", sealSlot), true,
  "which lands on that slot, durably")
eq(gapCart:cartPlan("red").refused, false, "and the cart is no longer refused")
local brokenText = drawAndCapture(gapCart)
check(brokenText:find("Seal broken", 1, true) ~= nil,
  "the cart page shows the broken state afterwards")
check(brokenText:find("seal broken", 1, true) ~= nil,
  "and so does the cart's slot row")

gapCart:_newSlot(sealScope)
local freshSlot = gapCart.activeSlot[sealScope]
check(freshSlot ~= sealSlot, "a new save slot under the same cart")
eq(SaveData.slotSealBroken("kanto_plus", freshSlot), false,
  "starts sealed again")
eq(gapCart:cartPlan("red").refused, true, "so the cart refuses that one")

install({ id = "plus_cart", title = "Plus Cart", seal = "sealed+",
          shell = "#445566" })
LauncherMods.list = function() return FULL_MODS end
local plusCart = freshLauncher()
plusCart.tab = "red"
plusCart.ready.red = true
plusCart._cartPopup = "red"
local plusPicker = drawAndCapture(plusCart)
check(plusPicker:find("sealed+", 1, true) ~= nil,
  "the picker spells a sealed+ cart's seal out")
plusCart._cartPopup = nil
plusCart:_selectCart("red", "plus_cart")
local plusPlan = plusCart:cartPlan("red")
eq(plusPlan.seal, "sealed+", "the plan carries the sealed+ seal")
eq(plusPlan.sealed, true, "sealed+ is a sealed cart")
eq(plusPlan.enforced, true, "and enforces its mod set")
local plusText = drawAndCapture(plusCart)
check(plusText:find("Sealed", 1, true) ~= nil, "the page says it is sealed")
check(plusText:find("switch any of them on or off", 1, true) ~= nil,
  "and that the player may switch the mods it pins")
check(plusText:find("Break the seal", 1, true) ~= nil,
  "while still offering the escape hatch")
eq(SaveData.slotSealBroken("plus_cart",
  plusCart.activeSlot[plusCart:slotScope("red")] or "slot1"), false,
  "and reading the page breaks nothing")

-- ------- installing the mods a cart pins, instead of defeating its seal

local ModUpdate = require("src.mods.ModUpdate")
local realFetchBegin, realFetchPump =
  ModUpdate.beginFetchReleases, ModUpdate.pumpFetchReleases
local realDlBegin, realDlPump =
  ModUpdate.beginDownloadZip, ModUpdate.pumpDownloadZip
local realInstallDownloaded = LauncherMods.installDownloadedZip

love.data = love.data or {}
local savedData = { hash = love.data.hash, encode = love.data.encode }
-- The archive's digest IS its bytes here, so a fixture writes the hash it
-- wants the downloaded zip to have.
love.data.hash = function(_, data) return tostring(data) end
love.data.encode = function(_, _, digest) return tostring(digest) end

local SHA_ONE = ("0123abcd"):rep(8)
local SHA_TWO = ("dead9876"):rep(8)

local net = { versions = {}, bytes = {}, err = nil, repos = {} }
ModUpdate.beginFetchReleases = function(repo, modId)
  net.repos[modId] = repo
  return { modId = modId, repo = repo }
end
ModUpdate.pumpFetchReleases = function(h)
  if net.err then return true, nil, net.err end
  local out = {}
  for _, v in ipairs(net.versions[h.modId] or {}) do
    out[#out + 1] = { version = v, tag = "v" .. v,
      zip = { url = h.modId .. "@" .. v, name = h.modId .. ".zip" } }
  end
  return true, out
end
ModUpdate.beginDownloadZip = function(url, destName)
  love.filesystem.write(destName, net.bytes[url] or "not-the-pinned-archive")
  return { path = destName }
end
ModUpdate.pumpDownloadZip = function(h) return true, h.path end

local haveMods = {}
LauncherMods.installDownloadedZip = function(modId, localPath, version)
  haveMods[modId] = version or "?"
  pcall(love.filesystem.remove, localPath)
  return true, haveMods[modId]
end
LauncherMods.list = function()
  local rows = {}
  for id, v in pairs(haveMods) do
    rows[#rows + 1] = fakeRow({ id = id, name = id, version = v })
  end
  return rows
end

install({ id = "fill_cart", title = "Fill Cart", shell = "#227744",
  mods = {
    { id = "fill_one", source = "github", repo = "ren/fill-one",
      version = "1.0.0", sha256 = SHA_ONE },
    { id = "fill_two", source = "github", repo = "ren/fill-two",
      version = "2.1.0", sha256 = SHA_TWO },
  },
  load_order = { "fill_one", "fill_two" } })
install({ id = "odd_cart", title = "Odd Cart", shell = "#772244",
  mods = {
    { id = "banana_mod", source = "gamebanana", mod = 4821, file = 99123,
      md5 = ("ab"):rep(16) },
    { id = "here_mod", source = "local", version = "0.0.0" },
  },
  load_order = { "banana_mod", "here_mod" } })

local function fillPage(cartId)
  local page = freshLauncher()
  page.tab = "red"
  page.ready.red = true
  page:_selectCart("red", cartId)
  return page
end

local function runFill(page)
  page:pressInstallCartMods("red")
  local guard = 0
  while page._cartFill and guard < 500 do
    page:_pumpModInstall()
    page:_pumpCartFill()
    guard = guard + 1
  end
  check(page._cartFill == nil, "the install run finishes")
  return page.cartFillNotice or {}
end

local function failureText(notice)
  return table.concat(notice.failures or {}, " | ")
end

net.versions.fill_one = { "1.0.0", "0.9.0" }
net.versions.fill_two = { "2.1.0" }
net.bytes["fill_one@1.0.0"] = SHA_ONE
net.bytes["fill_two@2.1.0"] = SHA_TWO

-- A cart whose pins are all installed offers nothing to install.
haveMods = { fill_one = "1.0.0", fill_two = "2.1.0" }
local readyFill = fillPage("fill_cart")
eq(readyFill:cartPlan("red").refused, false, "every pin installed, so it plays")
eq(#readyFill:cartFillRows("red"), 0, "with nothing left to install")
local readyText = drawAndCapture(readyFill)
check(readyText:find("Install required mods", 1, true) == nil
    and readyText:find("required mods", 1, true) == nil,
  "so a ready cart never offers the install button")
check(readyText:find("Break the seal", 1, true) ~= nil,
  "while the seal control is where it always was")

-- Nothing installed: the button appears, named for the count, beside the seal.
haveMods = {}
local gapFill = fillPage("fill_cart")
eq(#gapFill:cartFillRows("red"), 2, "both uninstalled pins queue up")
local gapFillText = drawAndCapture(gapFill)
check(gapFillText:find("Install 2 required mods", 1, true) ~= nil,
  "a refused cart offers to install what it pins, counted")
check(gapFillText:find("the way its author built it", 1, true) ~= nil,
  "saying plainly that this is the way to play it as built")
check(gapFillText:find("Break the seal", 1, true) ~= nil,
  "with breaking the seal still there as the fallback")

-- A pin installed at the WRONG version is a gap too: the cart wants its own.
haveMods = { fill_one = "0.9.0", fill_two = "2.1.0" }
local skewFill = fillPage("fill_cart")
eq(skewFill:cartPlan("red").mismatched[1].id, "fill_one",
  "a pin at another version is a mismatch")
eq(#skewFill:cartFillRows("red"), 1, "which queues for install like a gap")
eq(skewFill:cartFillRows("red")[1].version, "1.0.0",
  "at the version the cart pins, not the one on disk")
local skewText = drawAndCapture(skewFill)
check(skewText:find("Install required mods", 1, true) ~= nil,
  "a single gap drops the count from the label")

-- THE HASH GATE.  An archive that is not the one the cart recorded installs
-- nothing, however well the id and version line up.
haveMods = {}
net.bytes["fill_one@1.0.0"] = "some other build entirely"
local badHash = fillPage("fill_cart")
local badNotice = runFill(badHash)
eq(haveMods.fill_one, nil, "a hash mismatch installs nothing at all")
eq(badNotice.ok, false, "and the run reports as failed")
check(failureText(badNotice):find("fill_one", 1, true) ~= nil,
  "naming the mod whose archive did not match")
check(failureText(badNotice):find("sha256", 1, true) ~= nil,
  "and saying it was the hash: " .. failureText(badNotice))
eq(badHash:cartPlan("red").refused, true, "so the cart still refuses")
net.bytes["fill_one@1.0.0"] = SHA_ONE

-- Partial: one archive verifies, the other does not.
haveMods = {}
net.bytes["fill_two@2.1.0"] = "wrong bytes for the second mod"
local partial = fillPage("fill_cart")
local partialNotice = runFill(partial)
eq(haveMods.fill_one, "1.0.0", "the pin that verified is installed")
eq(haveMods.fill_two, nil, "the pin that did not is not")
eq(partialNotice.ok, false, "a partial run reads as a failure")
check(tostring(partialNotice.text):find("1 of 2", 1, true) ~= nil,
  "counting what landed: " .. tostring(partialNotice.text))
check(failureText(partialNotice):find("fill_two", 1, true) ~= nil,
  "and naming only the mod that failed")
check(failureText(partialNotice):find("fill_one", 1, true) == nil,
  "not the one that worked")
local partialText = drawAndCapture(partial)
check(partialText:find("fill_two", 1, true) ~= nil,
  "the card reports the failure where the player pressed the button")
net.bytes["fill_two@2.1.0"] = SHA_TWO

-- The whole run, verified, with the seal untouched at the end of it.
haveMods = {}
local good = fillPage("fill_cart")
local goodScope = good:slotScope("red")
good:_ensureSlots(goodScope)
local goodSlot = good.activeSlot[goodScope]
eq(good:cartPlan("red").refused, true, "the cart refuses before the run")
local goodNotice = runFill(good)
eq(goodNotice.ok, true, "the run reports success: " .. tostring(goodNotice.text))
eq(haveMods.fill_one, "1.0.0", "the first pin lands at its pinned version")
eq(haveMods.fill_two, "2.1.0", "and the second at its own")
eq(net.repos.fill_one, "ren/fill-one", "each pin was looked up in its own repo")
eq(net.repos.fill_two, "ren/fill-two", "including the second")
eq(good:cartPlan("red").refused, false,
  "and the cart is ready to play with no further presses")
eq(SaveData.slotSealBroken("fill_cart", goodSlot or "slot1"), false,
  "installing never breaks the cart's seal")
eq(SaveData.isSealBroken(), false, "nor the session's")
local goodText = drawAndCapture(good)
check(goodText:find("Sealed", 1, true) ~= nil,
  "the card flips to ready without another click")
check(goodText:find("required mods", 1, true) == nil,
  "and stops offering the install button")

-- No release carrying that version.
haveMods = {}
net.versions.fill_one = { "0.9.0" }
local noRel = fillPage("fill_cart")
local noRelNotice = runFill(noRel)
eq(haveMods.fill_one, nil, "a version the repo does not publish installs nothing")
check(failureText(noRelNotice):find("v1.0.0", 1, true) ~= nil,
  "and the failure names the version it wanted: " .. failureText(noRelNotice))
net.versions.fill_one = { "1.0.0", "0.9.0" }

-- No .zip on the matching release.
haveMods = {}
local savedPump = ModUpdate.pumpFetchReleases
ModUpdate.pumpFetchReleases = function(h)
  return true, { { version = "1.0.0", tag = "v1.0.0" },
                 { version = "2.1.0", tag = "v2.1.0" } }
end
local noZip = fillPage("fill_cart")
local noZipNotice = runFill(noZip)
eq(haveMods.fill_one, nil, "a release with no archive installs nothing")
check(failureText(noZipNotice):find(".zip", 1, true) ~= nil,
  "and says so: " .. failureText(noZipNotice))
ModUpdate.pumpFetchReleases = savedPump

-- Network down.
haveMods = {}
net.err = "no network transport on this platform"
local offline = fillPage("fill_cart")
local offlineNotice = runFill(offline)
eq(haveMods.fill_one, nil, "an offline run installs nothing")
eq(offlineNotice.ok, false, "and reports as failed")
check(failureText(offlineNotice):find("no network transport", 1, true) ~= nil,
  "carrying the transport's own words: " .. failureText(offlineNotice))
net.err = nil

-- Sources the launcher cannot fetch are refused per mod, not as one silence.
haveMods = {}
local odd = fillPage("odd_cart")
eq(#odd:cartFillRows("red"), 2, "both odd pins are gaps")
local oddText = drawAndCapture(odd)
check(oddText:find("Install 2 required mods", 1, true) ~= nil,
  "the button is offered even when a pin may not be fetchable")
local oddNotice = runFill(odd)
eq(oddNotice.ok, false, "neither can be installed")
eq(#(oddNotice.failures or {}), 2, "and each is reported on its own line")
check(failureText(oddNotice):find("banana_mod", 1, true) ~= nil
    and failureText(oddNotice):find("GameBanana", 1, true) ~= nil,
  "the gamebanana pin says what it is pinned to: " .. failureText(oddNotice))
check(failureText(oddNotice):find("here_mod", 1, true) ~= nil
    and failureText(oddNotice):find("nothing to download", 1, true) ~= nil,
  "and the local pin says there is nothing to fetch")
eq(next(haveMods), nil, "with nothing installed either way")
local oddAfter = drawAndCapture(odd)
check(oddAfter:find("Break the seal", 1, true) ~= nil,
  "and the seal is still the fallback it was")

-- Breaking the seal still works exactly as it did, install button or not.
local sealStill = fillPage("odd_cart")
local oddScope = sealStill:slotScope("red")
sealStill:_newSlot(oddScope)
local oddSlot = sealStill.activeSlot[oddScope]
check(type(oddSlot) == "string", "the cart page has a loaded save slot")
eq(sealStill:pressBreakSeal("red"), false, "the first press still only arms")
eq(SaveData.slotSealBroken("odd_cart", oddSlot), false, "breaking nothing")
eq(sealStill:pressBreakSeal("red"), true, "and the second still breaks it")
eq(SaveData.slotSealBroken("odd_cart", oddSlot), true, "on that slot")
eq(sealStill:cartPlan("red").refused, false, "so the cart plays")

love.data.hash, love.data.encode = savedData.hash, savedData.encode
ModUpdate.beginFetchReleases, ModUpdate.pumpFetchReleases =
  realFetchBegin, realFetchPump
ModUpdate.beginDownloadZip, ModUpdate.pumpDownloadZip =
  realDlBegin, realDlPump
LauncherMods.installDownloadedZip = realInstallDownloaded
-- Later blocks audit the picker's layout, which counts the carts on red.
CartStore.uninstall("fill_cart")
CartStore.uninstall("odd_cart")

LauncherMods.list = realModList
window(1280, 720)

-- ------- the MODS tab under an active cart

-- the rows the base game's own list would hand back, so the panel with no
-- cart active has something real to disagree with the carts about
local PIN_MODS = {
  fakeRow({ id = "pin_on", name = "Pin On", version = "1.0.0" }),
  fakeRow({ id = "pin_off", name = "Pin Off", version = "1.0.0",
            enabled = false,
            enabledByVersion = { red = false, blue = false, yellow = false,
                                 gold = false, silver = false } }),
}

local function localPin(id, off)
  local entry = { id = id, source = "local", version = "1.0.0" }
  if off then entry.enabled = false end
  return entry
end

local PIN_SET = { localPin("pin_on"), localPin("pin_off", true) }
local PIN_ORDER = { "pin_on", "pin_off" }

install({ id = "plus_mods", title = "Plus Mods", seal = "sealed+",
          shell = "#2b8a3e", mods = PIN_SET, load_order = PIN_ORDER })
install({ id = "hard_mods", title = "Hard Mods", seal = "sealed",
          shell = "#8a2b3e", mods = PIN_SET, load_order = PIN_ORDER })
install({ id = "gap_mods", title = "Gap Mods", seal = "sealed+",
          shell = "#3e2b8a",
          mods = { localPin("pin_on"), localPin("ghost_mod") },
          load_order = { "pin_on", "ghost_mod" } })

local realSetEnabled, realSetAllEnabled = LauncherMods.setEnabled, LauncherMods.setAllEnabled
local perGameWrites = 0
LauncherMods.setEnabled = function(...)
  perGameWrites = perGameWrites + 1
  return realSetEnabled(...)
end
LauncherMods.setAllEnabled = function(...)
  perGameWrites = perGameWrites + 1
  return realSetAllEnabled(...)
end
LauncherMods.list = function() return PIN_MODS end

-- the base game's own answer for the same mod, which nothing below may move
local seeded = SaveData.loadOptions()
SaveData.setModEnabled(seeded, "pin_off", false, "red")
SaveData.setModEnabled(seeded, "pin_on", true, "red")
SaveData.saveOptions(seeded)

local function rowsById(imp)
  local byId = {}
  for _, row in ipairs(imp.mods or {}) do byId[row.id] = row end
  return byId
end

local plain = freshLauncher()
plain.tab = "mods"
plain.ready.red = true
plain:_selectCart("red", nil)
plain:_setModScope("red")
eq(#plain.mods, 2, "with no cart the panel lists the installed mods")
eq(plain.mods[1].cartPin, nil, "which are not marked as any cart's")
check(type(plain.mods[1].enabledByVersion) == "table",
  "and still carry their per-game answers")
perGameWrites = 0
plain:_toggleMod("pin_on", nil, "red")
eq(perGameWrites, 1, "a toggle with no cart still writes the per-game flag")
eq(SaveData.modEnabled(SaveData.loadOptions(), "pin_on", "red"), false,
  "which is what changed")
eq(SaveData.cartModEnabled(SaveData.loadOptions(), "plus_mods", "pin_on"), nil,
  "and no cart scope was touched")
SaveData.setModEnabled(seeded, "pin_on", true, "red")
SaveData.saveOptions(seeded)

local pins = freshLauncher()
pins.tab = "mods"
pins.ready.red = true
pins:_selectCart("red", "plus_mods")
pins:_setModScope("red")
eq(#pins.mods, 2, "an active cart makes the panel list its pins")
local pinRows = rowsById(pins)
eq(pinRows.pin_on.cartPin, true, "each row is marked as the cart's")
eq(pinRows.pin_on.cartId, "plus_mods", "naming the cart it came from")
eq(pinRows.pin_on.enabled, true, "a pin shipped switched on shows on")
eq(pinRows.pin_off.enabled, false, "a pin shipped switched off shows off")
eq(pinRows.pin_off.cartTogglable, true, "sealed+ hands every pin's switch over")
eq(pinRows.pin_on.enabledByVersion, nil,
  "and a cart row carries no per-game answer, because a cart is one game")

local pinText = drawAndCapture(pins)
check(pinText:find("PINNED", 1, true) ~= nil,
  "the list says on every row that these are the cart's mods")
check(pinText:find("Plus Mods", 1, true) ~= nil, "and names the cart above them")
check(pinText:find("In this cart:", 1, true) ~= nil,
  "with a switch that answers the cart, not the game")

perGameWrites = 0
pins:_toggleMod("pin_off", nil, "red")
local afterOn = SaveData.loadOptions()
eq(SaveData.cartModEnabled(afterOn, "plus_mods", "pin_off"), true,
  "a sealed+ toggle writes the player's answer into the cart's scope")
eq(perGameWrites, 0, "and never through the per-game path")
eq(SaveData.modEnabled(afterOn, "pin_off", "red"), false,
  "so the base game's flag for that mod is untouched")
eq(SaveData.modEnabled(afterOn, "pin_on", "red"), true, "as is every other")
eq(rowsById(pins).pin_off.enabled, true, "the row follows the new answer")

local pinScope = pins:slotScope("red")
pins:_ensureSlots(pinScope)
local pinSlot = pins.activeSlot[pinScope]
eq(SaveData.slotSealBroken("plus_mods", pinSlot or "slot1"), false,
  "switching a sealed+ pin does not break the cart's seal")
eq(SaveData.isSealBroken(), false, "nor the session's")
eq(pins:cartPlan("red").broken, false, "and the plan still reads it as intact")

pins:_toggleMod("pin_off", nil, "red")
eq(SaveData.cartModEnabled(SaveData.loadOptions(), "plus_mods", "pin_off"), false,
  "pressing again switches it back off, still in the cart's scope")

perGameWrites = 0
pins:_setAllMods(true)
eq(perGameWrites, 0, "Enable all cannot reach a cart's mod set")
eq(SaveData.cartModEnabled(SaveData.loadOptions(), "plus_mods", "pin_off"), false,
  "so no pin moved")
check(tostring(pins.modNotice.text):find("Plus Mods", 1, true) ~= nil,
  "and the panel says which cart is deciding")
eq(pins.modNotice.ok, false, "as a refusal")
pins:_setAllMods(false)
eq(perGameWrites, 0, "Disable all cannot either")
eq(SaveData.modEnabled(SaveData.loadOptions(), "pin_on", "red"), true,
  "and the base game's list is where it was")

pins:_toggleMod("wide_gym", nil, "red")
check(tostring(pins.modNotice.text):find("cannot be added to", 1, true) ~= nil,
  "a mod the cart does not pin cannot be switched on from here")
eq(SaveData.cartModEnabled(SaveData.loadOptions(), "plus_mods", "wide_gym"), nil,
  "and nothing is written for it")

pins.safeMode = true
pins:_toggleMod("pin_off", nil, "red")
check(tostring(pins.modNotice.text):find("Safe mode", 1, true) ~= nil,
  "safe mode still refuses a cart toggle first")
eq(SaveData.cartModEnabled(SaveData.loadOptions(), "plus_mods", "pin_off"), false,
  "and writes nothing")
pins.safeMode = false

local sealedPins = freshLauncher()
sealedPins.tab = "mods"
sealedPins.ready.red = true
sealedPins:_selectCart("red", "hard_mods")
sealedPins:_setModScope("red")
local hardRows = rowsById(sealedPins)
eq(hardRows.pin_off.enabled, false, "a sealed cart's off pin shows off")
eq(hardRows.pin_off.cartTogglable, false, "and hands no switch over")
eq(hardRows.pin_on.cartTogglable, false, "nor does the pin it ships on")
perGameWrites = 0
sealedPins:_toggleMod("pin_off", nil, "red")
eq(perGameWrites, 0, "a sealed pin never reaches the per-game path either")
eq(SaveData.cartModEnabled(SaveData.loadOptions(), "hard_mods", "pin_off"), nil,
  "and a press under a sealed cart writes nothing")
eq(sealedPins.modNotice.ok, false, "the press is refused")
check(tostring(sealedPins.modNotice.text):find("sealed", 1, true) ~= nil,
  "with the panel saying why rather than doing nothing")
check(tostring(sealedPins.modNotice.text):find("Break the seal", 1, true) ~= nil,
  "and pointing at the one way to change it")
local hardScope = sealedPins:slotScope("red")
sealedPins:_ensureSlots(hardScope)
eq(SaveData.slotSealBroken("hard_mods",
  sealedPins.activeSlot[hardScope] or "slot1"), false,
  "a refused press breaks no seal of its own")
local hardText = drawAndCapture(sealedPins)
check(hardText:find("Pinned, sealed:", 1, true) ~= nil,
  "and the row itself reads as locked")

local gapPins = freshLauncher()
gapPins.tab = "mods"
gapPins.ready.red = true
gapPins:_selectCart("red", "gap_mods")
gapPins:_setModScope("red")
local gapRows = rowsById(gapPins)
eq(#gapPins.mods, 2, "a pin that is not installed is still listed")
eq(gapRows.ghost_mod.status, "missing", "as missing")
eq(gapRows.ghost_mod.enabled, false, "and switched off")
gapPins:_toggleMod("ghost_mod", nil, "red")
check(tostring(gapPins.modNotice.text):find("not installed", 1, true) ~= nil,
  "switching it says so instead of writing an answer for a mod that is absent")
eq(SaveData.cartModEnabled(SaveData.loadOptions(), "gap_mods", "ghost_mod"), nil,
  "and writes nothing")

pins:_selectCart("red", nil)
pins:_setModScope("red")
local backRows = rowsById(pins)
eq(#pins.mods, 2, "choosing the base game lists the player's own mods again")
eq(backRows.pin_on.cartPin, nil, "with no cart marks left on them")
check(type(backRows.pin_on.enabledByVersion) == "table",
  "and their per-game answers back")
eq(backRows.pin_off.enabled, false,
  "reading exactly what the base game's flags say")
perGameWrites = 0
pins:_toggleMod("pin_off", nil, "red")
eq(perGameWrites, 1, "and a toggle is a per-game write once more")
eq(SaveData.modEnabled(SaveData.loadOptions(), "pin_off", "red"), true,
  "which lands in the game's own flags")
eq(SaveData.cartModEnabled(SaveData.loadOptions(), "plus_mods", "pin_off"), false,
  "leaving the cart's answer where the player left it")

LauncherMods.setEnabled, LauncherMods.setAllEnabled = realSetEnabled, realSetAllEnabled
LauncherMods.list = realModList

local function clipped(r)
  local x1, y1, x2, y2 = r.x, r.y, r.x + r.w, r.y + r.h
  if r.clip then
    x1 = math.max(x1, r.clip.x); y1 = math.max(y1, r.clip.y)
    x2 = math.min(x2, r.clip.x + r.clip.w); y2 = math.min(y2, r.clip.y + r.clip.h)
  end
  if x2 - x1 <= 1 or y2 - y1 <= 1 then return nil end
  return x1, y1, x2, y2
end

local function overlap(a, b)
  local ax1, ay1, ax2, ay2 = clipped(a)
  if not ax1 then return false end
  local bx1, by1, bx2, by2 = clipped(b)
  if not bx1 then return false end
  return math.min(ax2, bx2) - math.max(ax1, bx1) > 1
     and math.min(ay2, by2) - math.max(ay1, by1) > 1
end

local function auditFrame(label, want)
  local controls, found = {}, false
  for _, r in ipairs(Kit.audit or {}) do
    if r.class == "control" then
      controls[#controls + 1] = r
      if want and tostring(r.label):find(want, 1, true) then found = true end
    end
  end
  check(#controls > 0, label .. ": the frame dispatched controls at all")
  local collisions = 0
  for i = 1, #controls do
    for j = i + 1, #controls do
      if overlap(controls[i], controls[j]) then
        collisions = collisions + 1
        print(("  overlap: '%s' vs '%s' at (%.0f,%.0f) / (%.0f,%.0f)")
          :format(tostring(controls[i].label), tostring(controls[j].label),
            controls[i].x, controls[i].y, controls[j].x, controls[j].y))
      end
    end
  end
  check(collisions == 0, label .. ": no two controls overlap")
  if want then check(found, label .. ": drew " .. want) end
end

local SIZES = {
  { 360, 780 }, { 412, 915 }, { 480, 900 }, { 720, 1280 },
  { 1280, 720 }, { 1024, 768 }, { 900, 700 }, { 1920, 1080 },
}

for _, size in ipairs(SIZES) do
  local W, H = size[1], size[2]
  window(W, H)
  for _, cart in ipairs({ false, true }) do
    local page = freshLauncher()
    page.tab = "red"
    page.ready.red = true
    page:_selectCart("red", cart and "kanto_plus" or nil)
    LauncherView.draw(page)
    Kit.audit = {}
    local ok, err = pcall(LauncherView.draw, page)
    Kit.audit = ok and Kit.audit or nil
    check(ok, ("%dx%d %s draws: %s")
      :format(W, H, cart and "cart" or "vanilla", tostring(err)))
    if ok then
      auditFrame(("%dx%d %s"):format(W, H, cart and "cart" or "vanilla"),
        "Custom Carts")
      -- The refused card carries two chips now, so both have to stay on it.
      if cart then
        local sawFill = false
        for _, r in ipairs(Kit.audit or {}) do
          local label = tostring(r.label)
          if label == "Install required mods" or label == "Break the seal" then
            sawFill = sawFill or label == "Install required mods"
            check(r.x >= -0.5 and r.x + r.w <= W + 0.5
              and r.y >= -0.5 and r.y + r.h <= H + 0.5,
              ("%dx%d cart card: %q stays inside the window")
                :format(W, H, label))
          end
        end
        check(sawFill,
          ("%dx%d cart card: drew Install required mods"):format(W, H))
      end
    end
    Kit.audit = nil

    page._cartPopup = "red"
    if cart then
      page._cartNotice = "Browsing for carts arrives in a later update."
    end
    LauncherView.draw(page)
    Kit.audit = {}
    ok, err = pcall(LauncherView.draw, page)
    Kit.audit = ok and Kit.audit or nil
    check(ok, ("%dx%d picker draws: %s"):format(W, H, tostring(err)))
    if ok then
      auditFrame(("%dx%d picker"):format(W, H), "Kanto Plus")
      for _, r in ipairs(Kit.audit or {}) do
        local label = tostring(r.label)
        if label == "Get more carts" or label == "Close" then
          check(r.y >= -0.5 and r.y + r.h <= H + 0.5,
            ("%dx%d picker: %q stays inside the window"):format(W, H, label))
        end
      end
    end
    Kit.audit = nil
  end
end

LauncherMods.list = function() return FAKE_MODS end
for _, size in ipairs(SIZES) do
  local W, H = size[1], size[2]
  window(W, H)
  local form = freshLauncher()
  form.tab = "mods"
  form.ready.red = true
  form:_setModScope("red")
  form:_beginCartSave("red")
  form._cartSave.text = "Soda Run"
  form:_commitCartSave()
  check(form._cartSave ~= nil,
    ("%dx%d save form stays open on a colliding title"):format(W, H))
  LauncherView.draw(form)
  Kit.audit = {}
  local ok, err = pcall(LauncherView.draw, form)
  Kit.audit = ok and Kit.audit or nil
  check(ok, ("%dx%d save form draws: %s"):format(W, H, tostring(err)))
  if ok then
    auditFrame(("%dx%d save form"):format(W, H), "Save as cart")
    for _, r in ipairs(Kit.audit or {}) do
      if tostring(r.label) == "Cancel" then
        check(r.y >= -0.5 and r.y + r.h <= H + 0.5,
          ("%dx%d save form: Cancel stays inside the window"):format(W, H))
      end
    end
  end
  Kit.audit = nil
end
LauncherMods.list = function() return PIN_MODS end
for _, size in ipairs(SIZES) do
  local W, H = size[1], size[2]
  window(W, H)
  for _, cart in ipairs({ "plus_mods", "hard_mods" }) do
    local panel = freshLauncher()
    panel.tab = "mods"
    panel.ready.red = true
    panel:_selectCart("red", cart)
    panel:_setModScope("red")
    LauncherView.draw(panel)
    Kit.audit = {}
    local ok, err = pcall(LauncherView.draw, panel)
    Kit.audit = ok and Kit.audit or nil
    check(ok, ("%dx%d %s mods draws: %s"):format(W, H, cart, tostring(err)))
    if ok then auditFrame(("%dx%d %s mods"):format(W, H, cart)) end
    Kit.audit = nil
  end
end
LauncherMods.list = realModList

-- ------- FIND tab: browsing the index's carts instead of its mods
--
-- The feed carries carts beside mods at the same schema_version, so the panel
-- has a Mods / Carts switch.  Installing a cart from a listing goes through
-- CartStore.install with the downloaded bytes, never the mod installer.

local ModIndex = require("src.mods.ModIndex")
local ModUpdate = require("src.mods.ModUpdate")
local Json = require("src.link.Json")

local INDEX_CART = {
  id = "indexed_cart", title = "Indexed Cart", author = "Ren",
  version = "1.4.0", base = "silver", seal = "sealed",
  repo = "https://github.com/ren/indexed-cart",
  github = "ren/indexed-cart",
  mods = { { id = "rare_soda", source = "github", repo = "ren/rare-soda",
             version = "0.4.1", sha256 = SHA } },
  update_check = "ok",
  latest = { version = "1.4.0", tag = "v1.4.0",
             zip = { name = "indexed_cart-1.4.0.zip",
                     url = "https://example.test/indexed_cart-1.4.0.zip" } },
}

local INDEX_FEED = ModIndex.parse(Json.encode({
  schema_version = 1,
  categories = { "GAMEPLAY" },
  base_games = { "red", "blue", "yellow", "gold", "silver" },
  mods = {
    { id = "rare_soda", title = "Rare Soda", author = "Ren", version = "0.4.1",
      categories = { "GAMEPLAY" }, update_check = "off" },
    { id = "true_colour", title = "True Colour", author = "Sam",
      version = "1.0.0", categories = { "ART" }, update_check = "off" },
  },
  carts = {
    INDEX_CART,
    { id = "gold_rush", title = "Gold Rush", author = "Sam", version = "3.0.0",
      base = "gold", seal = "open", repo = "https://github.com/sam/gold-rush",
      mods = { { id = "steps", source = "github", repo = "sam/steps",
                 version = "1.0.0", sha256 = SHA } },
      update_check = "off" },
  },
}))
check(INDEX_FEED ~= nil, "the find-tab fixture feed parses")

window(1280, 720)

local find = freshLauncher()
eq(find.findKind, "mods", "the Find tab browses mods by default")
check(find.findBase == nil, "with no base-game filter armed")
find.tab = "find"
find.modScope = nil
find.findLoaded = true
find.findSources = { { feed = "https://example.test/data/index.json",
                       base = "https://example.test/",
                       label = "example/index" } }
find.findIndex = { mods = INDEX_FEED.mods, carts = INDEX_FEED.carts,
                   categories = { "GAMEPLAY", "ART" },
                   baseGames = ModIndex.baseGamesIn(INDEX_FEED) }

eq(#find:_findRows(), 2, "the default rows are the feed's mods")
eq(find:_findRows()[1].id, "rare_soda", "and they are the mod entries")

local modsFind = drawAndCapture(find)
check(modsFind:find("Mods (2)", 1, true) ~= nil,
  "the switch says how many mods the feed lists")
check(modsFind:find("Carts (2)", 1, true) ~= nil, "and how many carts")
check(modsFind:find("Rare Soda", 1, true) ~= nil, "mods are what is listed")

find:_setFindKind("carts")
eq(find.findKind, "carts", "the switch flips to carts")
eq(#find:_findRows(), 2, "and the rows become the feed's carts")
check(ModIndex.isCart(find:_findRows()[1]), "which are cart entries")

local cartsFind = drawAndCapture(find)
check(cartsFind:find("Indexed Cart", 1, true) ~= nil,
  "a cart listing is drawn on the Carts half")
check(cartsFind:find("Rare Soda", 1, true) == nil,
  "and the mod listings are gone")
check(cartsFind:find("Search carts", 1, true) ~= nil,
  "the search field asks for carts")

-- search spans the same fields it does for a mod
find.findQuery = "gold"
eq(#find:_findRows(), 1, "searching a cart title narrows the list")
eq(find:_findRows()[1].id, "gold_rush", "to that cart")
find.findQuery = "Ren"
eq(find:_findRows()[1].id, "indexed_cart", "searching by author works too")
find.findQuery = ""

-- the cart-side filter is by base game, and the popup offers only the base
-- games the feed's carts actually play as
find.findBase = "gold"
eq(#find:_findRows(), 1, "filtering by base game keeps that game's carts")
eq(find:_findRows()[1].id, "gold_rush", "and only those")
local filterText
do
  find._filterPopup = true
  filterText = drawAndCapture(find)
  find._filterPopup = nil
end
check(filterText:find("Filter by base game", 1, true) ~= nil,
  "the filter popup filters carts by base game")
check(filterText:find("Filter by category", 1, true) == nil,
  "not by a category no cart has")
find.findBase = nil

-- MODS-tab scope still applies: a cart plays as exactly one game
find.modScope = "silver"
eq(#find:_findRows(), 1, "a scoped launcher lists only that game's carts")
eq(find:_findRows()[1].id, "indexed_cart", "the one based on silver")
find.modScope = nil

find:_setFindKind("mods")
eq(#find:_findRows(), 2, "switching back restores the mod rows")
find:_setFindKind("carts")

-- ------- installing a cart from a listing

local INDEX_CART_BYTES = CartManifest.encode(CartManifest.parse(cartTable({
  id = "indexed_cart", title = "Indexed Cart", version = "1.4.0",
  base = "silver", shell = "#d8c24a" })))

eq(#find:_ensureCarts("silver"), 0, "silver has no carts before the install")

local entry
for _, row in ipairs(find:_findRows()) do
  if row.id == "indexed_cart" then entry = row end
end
check(entry ~= nil, "the cart listing is on screen to install")

local realBegin, realPump = ModUpdate.beginDownloadZip, ModUpdate.pumpDownloadZip
local asked = {}
ModUpdate.beginDownloadZip = function(url, name)
  asked[#asked + 1] = { url = url, name = name }
  return { name = name }
end
ModUpdate.pumpDownloadZip = function(h)
  love.filesystem.write(h.name, INDEX_CART_BYTES)
  return true, h.name
end

find:_findConfirmInstall(entry)
check(find._modConfirm ~= nil, "installing a cart arms a confirm first")
eq(find._modConfirm.title, "Install cart", "and it says it is a cart")
eq(find._modConfirm.indexEntry, entry, "carrying the listing it will install")
do
  local lines = table.concat(find._modConfirm.lines or {}, "\n")
  check(lines:find("Pins 1 mod", 1, true) ~= nil,
    "the confirm says how many mods the cart pins")
  check(lines:find("installed separately", 1, true) ~= nil,
    "and that installing the cart does not install them")
end
find._modConfirm = nil

find:_findInstall(entry)
check(find._cartInstall ~= nil, "the cart download is in flight")
check(find._modInstall == nil, "and it is not a mod install")
eq(asked[1].url, "https://example.test/indexed_cart-1.4.0.zip",
  "the release the listing resolves is what gets downloaded")
check(asked[1].name:find(".g1rcart", 1, true) ~= nil,
  "into a cart file, not a mod zip")

-- single in flight: a mod install cannot start on top of a cart download
find:_beginModInstall({ modId = "rare_soda", name = "Rare Soda", notice = "find",
  release = { version = "0.4.1",
              zip = { url = "https://example.test/rare_soda.zip" } } })
check(find._modInstall == nil, "a mod install cannot race a cart install")
eq(#asked, 1, "and nothing else was downloaded")

find:_pumpCartInstall()
check(find._cartInstall == nil, "the cart install completes")
check(find.findNotice ~= nil and find.findNotice.ok,
  "and reports success on the Find tab")

local installedCart = CartStore.get("indexed_cart")
check(installedCart ~= nil, "the cart is installed through CartStore")
if installedCart then
  eq(installedCart.title, "Indexed Cart", "with its own title")
  eq(installedCart.base, "silver", "and the game it plays as")
end

-- the per-version cache is the whole point: without invalidating it the new
-- cart would not show in Custom Carts until a relaunch
eq(#find.carts["silver"], 1,
  "the cached cart list for that game is refreshed in place")
eq(find.carts["silver"][1].id, "indexed_cart", "with the new cart in it")
eq(find:_findInstalledCarts()["indexed_cart"], "1.4.0",
  "and the Find rows now read it as installed")

-- the Custom Carts picker draws the new cart in the same session, with no
-- refresh call from here and no relaunch
do
  local picker = freshLauncher()
  picker.tab = "silver"
  picker.ready.silver = true
  picker._cartPopup = "silver"
  local pickerText = drawAndCapture(picker)
  check(pickerText:find("Indexed Cart", 1, true) ~= nil,
    "the Custom Carts picker lists the freshly installed cart")
end
do
  local same = drawAndCapture(find)
  check(same ~= nil, "the Find tab still draws after an install")
end

-- ------- the pins prompt
--
-- Installing a cart never installs its mods behind the player's back, but a
-- cart whose pins are missing will not start, so it asks once and routes a
-- yes at the existing hash-verified fill queue.

check(find._modConfirm ~= nil, "a cart with missing pins prompts after install")
eq(find._modConfirm.kind, "cartPins", "through the launcher's confirm modal")
eq(find._modConfirm.version, "silver", "for the game the cart plays as")
eq(find._modConfirm.id, "indexed_cart", "naming the cart just installed")
do
  local lines = table.concat(find._modConfirm.lines or {}, "\n")
  check(lines:find("Indexed Cart pins 1 mod", 1, true) ~= nil,
    "the prompt names the cart and how many pins are missing")
end
check(find.activeCart["silver"] == nil,
  "and asking does not select the cart on its own")

-- yes routes at pressInstallCartMods, which owns the hash check
do
  local realFetchRel = ModUpdate.beginFetchReleases
  local realPumpRel = ModUpdate.pumpFetchReleases
  local asked_repos = {}
  ModUpdate.beginFetchReleases = function(repo)
    asked_repos[#asked_repos + 1] = repo
    return { repo = repo }
  end
  ModUpdate.pumpFetchReleases = function() return true, nil, "no releases" end
  find._modConfirm = nil
  find:_installCartPins("silver", "indexed_cart")
  eq(find.activeCart["silver"], "indexed_cart",
    "saying yes selects the cart the pins belong to")
  for _ = 1, 8 do find:_pumpCartFill() end
  eq(asked_repos[1], "ren/rare-soda",
    "and the fill queue resolves the cart's own pin")
  check(find.cartFillNotice ~= nil and not find.cartFillNotice.ok,
    "reporting per-mod failures through the existing notice")
  find:_selectCart("silver", nil)
  find.cartFillNotice = nil
  ModUpdate.beginFetchReleases = realFetchRel
  ModUpdate.pumpFetchReleases = realPumpRel
end

-- a cart whose pins are all installed must not prompt at all
do
  local realList = LauncherMods.list
  LauncherMods.list = function()
    return { { id = "rare_soda", version = "0.4.1",
               manifest = { id = "rare_soda", version = "0.4.1" } } }
  end
  local satisfied = freshLauncher()
  eq(#satisfied:_cartPinsMissing("silver", "indexed_cart"), 0,
    "a cart with every pin installed is missing none")
  satisfied:_offerCartPins({ id = "indexed_cart", title = "Indexed Cart",
                             base = "silver" })
  check(satisfied._modConfirm == nil, "so it does not prompt")
  LauncherMods.list = realList
end

-- a download that is not a cart at all fails loudly instead of installing
ModUpdate.pumpDownloadZip = function(h)
  love.filesystem.write(h.name, "not a cart at all")
  return true, h.name
end
find.findNotice = nil
find:_findInstall(entry)
find:_pumpCartInstall()
check(find._cartInstall == nil, "a junk download ends the job")
check(find.findNotice ~= nil and not find.findNotice.ok,
  "and says so rather than installing anything")

ModUpdate.beginDownloadZip, ModUpdate.pumpDownloadZip = realBegin, realPump

T.finish("cart launcher")
