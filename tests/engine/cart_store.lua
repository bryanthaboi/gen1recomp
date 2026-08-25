package.path = "./?.lua;./?/init.lua;" .. package.path

if not rawget(_G, "bit") and not rawget(_G, "bit32") then
  local ok, bit32 = pcall(require, "bit32")
  if ok then _G.bit32 = bit32 end
end

local T = require("tests.harness")
love = love or require("tests.love_stub")

local Base64 = require("src.core.Base64")
local SaveData = require("src.core.SaveData")
local CartManifest = require("src.carts.CartManifest")
local CartStore = require("src.carts.CartStore")

local SHA = ("a1b2c3d4"):rep(8)
local SHA2 = ("beefcafe"):rep(8)
local MD5 = ("0123456789abcdef"):rep(2)

local function memfs()
  local files, dirs = {}, {}
  local fs
  fs = {
    files = files,
    write = function(path, body) files[path] = body return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    createDirectory = function(path) dirs[path] = true return true end,
    getInfo = function(path)
      if files[path] ~= nil then return { type = "file" } end
      if dirs[path] then return { type = "directory" } end
      for name in pairs(files) do
        if name:sub(1, #path + 1) == path .. "/" then return { type = "directory" } end
      end
      return nil
    end,
    getDirectoryItems = function(path)
      local prefix = (path == "" or path == nil) and "" or (path .. "/")
      local out, seen = {}, {}
      for name in pairs(files) do
        if name:sub(1, #prefix) == prefix then
          local child = name:sub(#prefix + 1):match("^([^/]+)")
          if child and not seen[child] then
            seen[child] = true
            out[#out + 1] = child
          end
        end
      end
      table.sort(out)
      return out
    end,
  }
  return fs
end

local function cartTable(over)
  local tbl = {
    id = "kanto_plus",
    title = "Kanto Plus",
    version = "1.2.0",
    author = "Ren",
    shell = "#3fa9f5",
    base = "red",
    seal = "sealed",
    mods = {
      { id = "rare_soda", source = "github", repo = "ren/rare-soda",
        version = "0.4.1", sha256 = SHA,
        options = { flavour = "grape", sweetness = 3 } },
      { id = "hard_mode", source = "gamebanana", mod = 4821, file = 99123,
        md5 = MD5 },
    },
  }
  for key, value in pairs(over or {}) do tbl[key] = value end
  return tbl
end

local function bytesOf(over)
  local cart, err = CartManifest.parse(cartTable(over))
  if not cart then error("fixture does not parse: " .. tostring(err)) end
  return CartManifest.encode(cart), cart
end

local fs = memfs()
local bytes, fixture = bytesOf()
local installed, hash = CartStore.install(bytes, fs)
T.check(installed ~= nil, "a good cart installs: " .. tostring(hash))
T.eq(installed.id, "kanto_plus", "install returns the parsed cart")
T.eq(hash, CartManifest.hash(fixture), "install returns the cart hash")
T.check(fs.files["carts/kanto_plus.g1rcart"] ~= nil,
  "install writes carts/<id>.g1rcart")

local reg = SaveData.loadOptions(fs).carts
T.check(type(reg) == "table" and type(reg.kanto_plus) == "table",
  "install registers the cart in options.carts")
T.eq(reg.kanto_plus.title, "Kanto Plus", "the registry carries the title")
T.eq(reg.kanto_plus.base, "red", "the registry carries the base game")
T.eq(reg.kanto_plus.version, "1.2.0", "the registry carries the cart version")
T.eq(reg.kanto_plus.hash, hash, "the registry carries the cart hash")
T.eq(reg.kanto_plus.file, "carts/kanto_plus.g1rcart",
  "the registry names the cart file")

local index = CartStore.index(fs)
T.eq(#index, 1, "index lists the registry without reading the files")
T.eq(index[1].base, "red", "an index row carries the base game")

local rows = CartStore.list(fs)
T.eq(#rows, 1, "list returns the installed cart")
T.eq(rows[1].id, "kanto_plus", "the row names the cart")
T.eq(rows[1].base, "red", "the row carries the base")
T.eq(rows[1].cartHash, hash, "the row carries the cart hash")
T.check(type(rows[1].cart) == "table" and rows[1].cart.mods ~= nil,
  "the row carries the parsed cart")
T.eq(rows[1].cart.mods[1].sha256, SHA, "the parsed cart keeps its pins")

local got, gotHash = CartStore.get("kanto_plus", fs)
T.check(got ~= nil, "get returns the cart")
T.eq(gotHash, hash, "get returns the cart hash")
T.same(got, fixture, "get returns exactly what was installed")
T.eq(CartStore.get("nothing_here", fs), nil, "get refuses an unknown id")
T.eq(CartStore.get("../etc/passwd", fs), nil, "get refuses a climbing id")

local exported, exportHash = CartStore.export("kanto_plus", fs)
T.check(type(exported) == "string", "export hands back bytes")
T.eq(exportHash, hash, "export reports the cart hash")
T.same(CartManifest.decode(exported), fixture, "the exported bytes decode back")
T.eq(CartStore.export("nothing_here", fs), nil, "export refuses an unknown id")

local blueBytes = bytesOf({ id = "johto_lite", title = "Aaa Johto Lite",
                            base = "blue" })
T.check(CartStore.install(blueBytes, fs) ~= nil, "a blue cart installs")
T.eq(#CartStore.list(fs), 2, "list returns both carts")
T.eq(CartStore.list(fs)[1].id, "johto_lite", "list sorts by title")
T.eq(#CartStore.listFor("red", fs), 1, "listFor red returns one cart")
T.eq(CartStore.listFor("red", fs)[1].id, "kanto_plus", "listFor red picks the red cart")
T.eq(#CartStore.listFor("blue", fs), 1, "listFor blue returns one cart")
T.eq(#CartStore.listFor("yellow", fs), 0, "listFor yellow returns nothing")

local newer, newerErr = CartStore.install(
  bytesOf({ version = "1.3.0", title = "Kanto Plus" }), fs)
T.check(newer ~= nil, "a newer cart replaces the installed one: " .. tostring(newerErr))
T.eq(CartStore.get("kanto_plus", fs).version, "1.3.0",
  "the newer version is what is installed")
T.eq(#CartStore.list(fs), 2, "replacing does not add a second row")
T.eq(SaveData.loadOptions(fs).carts.kanto_plus.version, "1.3.0",
  "the registry follows the replacement")

local same, sameErr = CartStore.install(bytesOf({ version = "1.3.0" }), fs)
T.check(same ~= nil, "the same version reinstalls: " .. tostring(sameErr))

local older, olderErr = CartStore.install(bytesOf({ version = "1.1.0" }), fs)
T.eq(older, nil, "an older cart is refused")
T.check(type(olderErr) == "string" and olderErr:find("older", 1, true) ~= nil,
  "the refusal says why (got " .. tostring(olderErr) .. ")")
T.eq(CartStore.get("kanto_plus", fs).version, "1.3.0",
  "the refused install leaves the newer cart in place")

T.eq(CartStore.install("return { }", fs), nil, "install refuses an untagged file")
T.eq(CartStore.install(nil, fs), nil, "install refuses a non-string")
T.eq(CartStore.install("\1\2\3 not lua", fs), nil, "install refuses noise")

fs.files["saves/cart_kanto_plus/slot1.lua"] = "return { player = { name = \"RED\" } }"
local opts = SaveData.loadOptions(fs)
opts.cartSlots = { kanto_plus = { list = { "slot1" }, active = "slot1" } }
SaveData.saveOptions(opts, fs)

T.check(CartStore.uninstall("kanto_plus", fs), "uninstall reports success")
T.eq(fs.files["carts/kanto_plus.g1rcart"], nil, "uninstall removes the cart file")
T.eq(SaveData.loadOptions(fs).carts.kanto_plus, nil,
  "uninstall clears the registry entry")
T.eq(#CartStore.list(fs), 1, "the uninstalled cart is gone from the list")
T.check(fs.files["saves/cart_kanto_plus/slot1.lua"] ~= nil,
  "uninstall leaves the cart's save file alone")
local slots = SaveData.loadOptions(fs).cartSlots
T.check(type(slots) == "table" and type(slots.kanto_plus) == "table",
  "uninstall leaves the cart's slot registry alone")
T.eq(slots.kanto_plus.active, "slot1", "the active slot survives an uninstall")

local gone, goneErr = CartStore.uninstall("kanto_plus", fs)
T.eq(gone, nil, "uninstalling twice is refused")
T.check(type(goneErr) == "string" and goneErr:find("not installed", 1, true) ~= nil,
  "the second uninstall says why (got " .. tostring(goneErr) .. ")")
T.eq(CartStore.uninstall("../etc/passwd", fs), nil, "uninstall refuses a climbing id")

T.check(CartStore.install(bytes, fs) ~= nil, "the cart reinstalls after removal")
T.same(CartStore.get("kanto_plus", fs), fixture, "reinstalling restores the cart")
T.check(fs.files["saves/cart_kanto_plus/slot1.lua"] ~= nil,
  "the old playthrough is still there for the reinstalled cart")

fs.files["carts/kanto_plus.g1rcart"] = "return { format = \"nonsense\" }"
local damaged = CartStore.list(fs)
T.eq(#damaged, 1, "a corrupt cart file is skipped and the rest still list")
T.eq(damaged[1].id, "johto_lite", "the healthy cart survives a corrupt sibling")
T.check(fs.files["carts/kanto_plus.g1rcart"] ~= nil,
  "listing never deletes the file it could not read")
T.eq(CartStore.get("kanto_plus", fs), nil, "get reports the corrupt cart as unreadable")
fs.files["carts/kanto_plus.g1rcart"] = nil

opts = SaveData.loadOptions(fs)
opts.carts = opts.carts or {}
opts.carts.ghost = { id = "ghost", title = "Ghost", base = "red",
                     version = "1.0.0", file = "carts/ghost.g1rcart" }
SaveData.saveOptions(opts, fs)
local haunted = CartStore.list(fs)
T.eq(#haunted, 1, "a registry entry with no file is skipped")
T.eq(haunted[1].id, "johto_lite", "the rest of the list still comes back")
T.eq(SaveData.loadOptions(fs).carts.ghost, nil,
  "listing prunes the registry entry whose file is gone")

local strayCart = select(2, bytesOf({ id = "wanderer", title = "Zzz Wanderer" }))
fs.files["carts/wanderer.g1rcart"] = CartManifest.encode(strayCart)
local adopted = CartStore.list(fs)
T.eq(#adopted, 2, "a cart file with no registry entry is still listed")
T.eq(adopted[2].id, "wanderer", "the stray cart sorts in by title")
T.eq(adopted[2].cartHash, CartManifest.hash(strayCart),
  "the stray cart is hashed from its own file")
T.check(SaveData.loadOptions(fs).carts.wanderer ~= nil,
  "listing registers the stray cart it adopted")

fs.files["carts/readme.txt"] = "hello"
fs.files["carts/half written.g1rcart"] = "return { }"
T.eq(#CartStore.list(fs), 2, "junk in carts/ is ignored")

local empty = memfs()
T.eq(#CartStore.list(empty), 0, "a fresh install lists no carts")
T.eq(#CartStore.listFor("red", empty), 0, "listFor is empty on a fresh install")

-- ------- the fields the registry rows have to carry through the store

local dressedFs = memfs()
local dressed = select(2, bytesOf({ id = "dressed", title = "Dressed",
  finish = "holo", speeds = { 1, 2 }, seal = "sealed+",
  options = { textSpeed = 1 } }))
local dressedCart, dressedHash = CartStore.install(CartManifest.encode(dressed),
  dressedFs)
T.check(dressedCart ~= nil, "a cart with a finish, speeds and settings installs")
T.eq(dressedHash, CartManifest.hash(dressed), "hashing the same as it was written")
T.same(CartStore.get("dressed", dressedFs), dressed,
  "and coming back off disk unchanged")

local dressedReg = SaveData.loadOptions(dressedFs).carts.dressed
T.eq(dressedReg.finish, "holo", "the registry row carries the finish")
T.same(dressedReg.speeds, { 1, 2 }, "and the speed ladder")
T.eq(dressedReg.seal, "sealed+", "and the seal, spelled in full")

local dressedRow = CartStore.list(dressedFs)[1]
T.eq(dressedRow.finish, "holo", "the list row carries the finish")
T.same(dressedRow.speeds, { 1, 2 }, "and the speed ladder")
T.eq(dressedRow.seal, "sealed+", "and the seal")
T.eq(dressedRow.cart.options.textSpeed, 1,
  "and the settings the cart ships, on the parsed cart")
T.eq(SaveData.loadOptions(dressedFs).carts.dressed.hash, dressedHash,
  "listing does not rewrite the registry it already agrees with")

local function rowSet()
  return {
    { id = "hard_mode", name = "Hard Mode", version = "2.0.0", enabled = true,
      github = "ren/hard-mode",
      manifest = { id = "hard_mode", version = "2.0.0",
                   github = "ren/hard-mode", sha256 = SHA } },
    { id = "off_mode", name = "Off Mode", version = "1.0.0", enabled = false,
      github = "ren/off-mode",
      manifest = { id = "off_mode", version = "1.0.0",
                   github = "ren/off-mode", sha256 = SHA2 } },
    { id = "rare_soda", name = "Rare Soda", version = "0.4.1", enabled = true,
      github = "ren/rare-soda",
      manifest = { id = "rare_soda", version = "0.4.1",
                   github = "ren/rare-soda" } },
    { id = "sprite_pack", name = "Sprite Pack", version = "beta", enabled = true,
      manifest = { id = "sprite_pack", version = "beta" } },
  }
end

local identity = { id = "my_cart", title = "My Cart", version = "0.1.0",
                   author = "Ren", base = "red", shell = "#FF8800",
                   seal = "open", summary = "Built in the launcher" }
local modOptions = {
  rare_soda = { flavour = "grape", sweetness = 3, nested = { 1, 2 } },
  off_mode = { unused = true },
}

local captured, unresolved = CartStore.capture(identity, rowSet(), modOptions)
T.check(captured ~= nil, "capture builds a cart: " .. tostring(unresolved))
T.eq(captured.id, "my_cart", "the captured cart keeps the identity id")
T.eq(captured.title, "My Cart", "the captured cart keeps the title")
T.eq(captured.shell, "#ff8800", "the captured shell normalises")
T.eq(captured.seal, "open", "the captured seal is the author's choice")
T.eq(captured.base, "red", "the captured base is the identity's")
T.eq(#captured.mods, 4, "every installed mod is pinned, switched on or off")
T.eq(captured.load_order[1], "hard_mode", "load order follows the row order")
T.eq(captured.load_order[2], "off_mode", "including the row that is switched off")
T.eq(captured.load_order[3], "rare_soda", "load order follows the row order")
T.eq(captured.load_order[4], "sprite_pack", "load order follows the row order")

T.eq(captured.mods[1].source, "github", "a mod with repo, version and hash pins to github")
T.eq(captured.mods[1].repo, "ren/hard-mode", "the github pin keeps the repo")
T.eq(captured.mods[1].sha256, SHA, "the github pin keeps the recorded hash")
T.eq(captured.mods[1].enabled, nil, "an enabled mod pins with no enabled field")
T.eq(CartManifest.modEnabled(captured.mods[1]), true, "and reads back as enabled")
T.eq(captured.mods[2].id, "off_mode", "the switched-off mod is pinned in place")
T.eq(captured.mods[2].enabled, false, "and is pinned switched off")
T.eq(CartManifest.modEnabled(captured.mods[2]), false, "which reads back as off")
T.eq(captured.mods[2].source, "github", "a disabled pin still resolves its source")
T.eq(captured.mods[2].sha256, SHA2, "and still carries its archive hash")
T.eq(captured.mods[2].options.unused, true,
  "a disabled mod's options are captured like any other")
T.eq(captured.mods[3].source, "local", "a mod with no archive hash pins locally")
T.eq(captured.mods[3].version, "0.4.1", "the local pin keeps the installed version")
T.eq(captured.mods[3].repo, nil, "a local pin carries no repo")
T.eq(captured.mods[3].sha256, nil, "a local pin carries no hash")
T.eq(captured.mods[3].options.flavour, "grape", "the author's option values are frozen in")
T.eq(captured.mods[3].options.sweetness, 3, "every scalar option is frozen in")
T.eq(captured.mods[3].options.nested, nil, "a table option value is dropped")
T.eq(captured.mods[4].source, "local", "a mod with no repo pins locally")
T.eq(captured.mods[4].version, "0.0.0", "an unparsable version pins as 0.0.0")
T.eq(captured.mods[1].options, nil, "a mod with no options freezes none")

T.eq(#unresolved, 2, "capture reports every locally pinned mod")
T.eq(unresolved[1].id, "rare_soda", "the first unresolved mod is named")
T.eq(unresolved[1].name, "Rare Soda", "the unresolved row carries the mod name")
T.check(unresolved[1].reason:find("archive hash", 1, true) ~= nil,
  "a missing hash is the reason (got " .. tostring(unresolved[1].reason) .. ")")
T.eq(unresolved[2].id, "sprite_pack", "the second unresolved mod is named")
T.check(unresolved[2].reason:find("GitHub repo", 1, true) ~= nil,
  "a missing repo is a reason (got " .. tostring(unresolved[2].reason) .. ")")
T.check(unresolved[2].reason:find("semantic version", 1, true) ~= nil,
  "an unpinnable version is a reason (got " .. tostring(unresolved[2].reason) .. ")")

local publishable, why = CartManifest.publishable(captured)
T.eq(publishable, false, "a captured cart with local pins cannot be published")
T.check(why:find("rare_soda", 1, true) ~= nil, "the reason names rare_soda")
T.check(why:find("sprite_pack", 1, true) ~= nil, "the reason names sprite_pack")
T.check(why:find("hard_mode", 1, true) == nil, "the reason leaves the pinned mod out")

local storeFs = memfs()
local roundTrip, roundHash = CartStore.install(CartManifest.encode(captured), storeFs)
T.check(roundTrip ~= nil, "a captured cart installs: " .. tostring(roundHash))
T.same(roundTrip, captured, "a captured cart survives the file round trip")
T.eq(roundHash, CartManifest.hash(captured), "a captured cart hashes the same on disk")

local pinned = rowSet()
pinned[3].manifest.sha256 = SHA2
pinned[4] = nil
local full, fullUnresolved = CartStore.capture(identity, pinned, modOptions)
T.check(full ~= nil, "a fully pinned capture builds a cart")
T.eq(#fullUnresolved, 0, "a fully pinned capture reports nothing unresolved")
T.eq(full.mods[3].source, "github", "a recorded hash promotes the pin to github")
T.eq(full.mods[3].sha256, SHA2, "the promoted pin uses the recorded hash")
T.eq(CartManifest.publishable(full), true, "a fully pinned cart is publishable")

local offOnly = CartStore.capture(identity, { rowSet()[2] }, modOptions)
T.check(offOnly ~= nil, "a capture of nothing but switched-off mods still builds")
T.eq(#offOnly.mods, 1, "pinning the one mod it was given")
T.eq(offOnly.mods[1].enabled, false, "switched off")
T.eq(offOnly.mods[1].options.unused, true, "with its settings kept")

local noMods, noModsErr = CartStore.capture(identity, {}, modOptions)
T.eq(noMods, nil, "a capture with no mods at all is refused")
T.check(type(noModsErr) == "string" and noModsErr:find("cart must pin", 1, true) ~= nil,
  "the empty capture says why (got " .. tostring(noModsErr) .. ")")
T.eq(CartStore.capture({ id = "bad id" }, rowSet(), modOptions), nil,
  "a capture with a bad identity is refused")
T.eq(CartStore.capture(nil, rowSet(), modOptions), nil,
  "a capture with no identity is refused")

local PNG = CartManifest.PNG_SIGNATURE .. "\0\0\0\13IHDRa cart label"
local ART_DATA = Base64.encode(PNG)

local function artedCart()
  local plain = select(2, bytesOf({ id = "art_cart", title = "Art Cart",
                                    label = "label.png" }))
  plain.labelArt = { name = "label.png", encoding = "base64", bytes = #PNG,
                     data = ART_DATA }
  return plain
end

local artFs = memfs()
local artFixture = artedCart()
local packed = CartManifest.encode(artFixture)
local artInstalled, artHash = CartStore.install(packed, artFs)
T.check(artInstalled ~= nil, "a cart with label art installs: " .. tostring(artHash))
T.eq(artInstalled.labelArt.data, ART_DATA, "install returns the cart with its art")
T.check(artFs.files["carts/art_cart.g1rcart"]:find(ART_DATA, 1, true) ~= nil,
  "install writes the art payload to the cart file")
T.same(CartStore.get("art_cart", artFs), artFixture,
  "the installed cart reads back with its art")

local artless = select(2, bytesOf({ id = "art_cart", title = "Art Cart",
                                    label = "label.png" }))
T.eq(artHash, CartManifest.hash(artless),
  "the art is not part of the hash a save pins itself to")

local artExported, artExportHash = CartStore.export("art_cart", artFs)
T.eq(artExportHash, artHash, "export reports the same hash for an arted cart")
T.eq(artExported, packed, "export hands back the bytes that were packed")
local reread = CartManifest.decode(artExported)
T.same(reread, artFixture, "the exported bytes decode to the same cart and art")
T.eq(reread.labelArt.data, ART_DATA, "the exported payload is byte identical")

local sharedFs = memfs()
T.check(CartStore.install(artExported, sharedFs) ~= nil,
  "an exported cart installs somewhere else")
T.same(CartStore.get("art_cart", sharedFs), artFixture,
  "pack, install, export and install again leaves the cart unchanged")

local shownBytes, shownName = CartStore.labelArt("art_cart", sharedFs)
T.eq(shownBytes, PNG, "labelArt hands back the decoded PNG")
T.eq(shownName, "label.png", "labelArt hands back the art name")
T.eq(CartStore.labelArt("nothing_here", sharedFs), nil,
  "labelArt refuses an unknown id")
T.eq(CartStore.labelArt("../etc/passwd", sharedFs), nil,
  "labelArt refuses a climbing id")

local plainFs = memfs()
T.check(CartStore.install(CartManifest.encode(artless), plainFs) ~= nil,
  "a cart with no art still installs")
T.eq(CartStore.labelArt("art_cart", plainFs), nil,
  "a cart with no art has no label art")
T.same(CartStore.get("art_cart", plainFs), artless,
  "a cart with no art round trips exactly as before")

local tamperedBytes = (packed:gsub("bytes = " .. #PNG, "bytes = " .. (#PNG + 1), 1))
T.neq(tamperedBytes, packed, "the tampered bundle really changed")
local tamperedFs = memfs()
local tampered, tamperedErr = CartStore.install(tamperedBytes, tamperedFs)
T.check(tampered ~= nil, "bad art never fails the install: " .. tostring(tamperedErr))
T.eq(tampered.labelArt, nil, "the bad art is dropped")
T.eq(CartStore.labelArt("art_cart", tamperedFs), nil,
  "the installed cart shows no art")
T.eq(tamperedFs.files["carts/art_cart.g1rcart"], CartManifest.encode(artless),
  "the bad art is not written back to disk")
T.eq(#CartStore.list(tamperedFs), 1, "the cart still lists without its art")

T.finish("cart_store")
