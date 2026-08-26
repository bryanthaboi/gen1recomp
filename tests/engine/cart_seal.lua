package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local Loader = require("src.mods.Loader")
local CartManifest = require("src.carts.CartManifest")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")

local realFS = love.filesystem

local function memfs(files)
  local fs
  fs = {
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
  return fs
end

local function manifestJson(id)
  return ([[{"id":"%s","name":"%s","version":"1.0.0","entry":"main.lua"}]])
    :format(id, id)
end

local function entry(record)
  return ([[
return function(mod)
  mod.options:define({ { key = "tint", default = "base" } })
  mod.content.pokemon:register("%s", { name = tostring(mod.options:get("tint")) })
end
]]):format(record)
end

local function install()
  local files = {
    ["options.lua"] = SaveSerializer.encode({
      mods = { beta = false },
      modOptions = { alpha = { tint = "player" }, beta = { tint = "player" } },
    }),
  }
  for _, id in ipairs({ "alpha", "beta", "gamma" }) do
    files["mods/" .. id .. "/manifest.json"] = manifestJson(id)
    files["mods/" .. id .. "/main.lua"] = entry(id:upper())
  end
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

local function writeCart(files, tbl)
  local cart, err = CartManifest.parse(tbl)
  assert(cart, err)
  files["carts/" .. tbl.id .. CartManifest.EXT] = CartManifest.encode(cart)
  return cart
end

local function cartTable(id, seal, mods, order)
  return { id = id, title = id, version = "1.0.0", author = "tester",
           shell = "#102030", base = "red", seal = seal,
           mods = mods, load_order = order }
end

local function pin(id, version, options)
  return { id = id, source = "local", version = version or "1.0.0",
           options = options }
end

local function offPin(id, version, options)
  local p = pin(id, version, options)
  p.enabled = false
  return p
end

local function boot(files)
  local data = { pokemon = {} }
  local loader = Loader.new({ fs = memfs(files) })
  local ok = loader:load(data)
  return loader, data, ok
end

local function options(files)
  return SaveSerializer.decode(files["options.lua"] or "") or {}
end

local function names(list)
  return table.concat(list, ",")
end

-- ------- a sealed cart loads its pins, in its order, with its options

do
  local files = install()
  writeCart(files, cartTable("sealed", "sealed",
    { pin("alpha", "1.0.0", { tint = "cart" }), pin("beta") },
    { "beta", "alpha" }))
  SaveData.setCart("sealed", "hash1")

  local loader, data, ok = boot(files)
  T.check(ok, "a sealed cart whose pins are all installed loads cleanly")
  T.eq(names(loader.order), "beta,alpha",
    "the cart's load_order beats priority and the id tie-break")
  T.eq(data.pokemon.ALPHA.name, "cart",
    "a frozen option overrides the player's saved value")
  T.eq(data.pokemon.BETA.name, "base",
    "a pin that froze no options falls to the schema default, not the player's")
  T.eq(data.pokemon.GAMMA, nil, "an enabled mod the cart does not pin never runs")
  T.eq(loader.mods.gamma.enabled, false, "and is reported as inactive")
  T.eq(loader.mods.gamma.state, "disabled", "with the disabled row state")
  T.eq(loader.mods.beta.enabled, true, "a pin the player switched off still loads")

  local report = loader:cartStatus()
  T.eq(report.id, "sealed", "the report names the cart")
  T.eq(report.seal, "sealed", "and its seal")
  T.eq(report.enforced, true, "which is enforced")
  T.eq(report.refused, false, "and not refused")
  T.eq(#report.missing, 0, "with no missing pins")
  T.eq(#report.mismatched, 0, "and no version mismatches")
  T.eq(loader:status().cart, report, "status() carries the same report")

  local opts = options(files)
  T.eq(SaveData.modEnabled(opts, "beta", "red"), false,
    "the player's disable flag is untouched on disk")
  T.eq(SaveData.modEnabled(opts, "gamma", "red") == false, false,
    "and so is the enable flag of the mod the seal left out")
  T.eq(opts.modOptions.alpha.tint, "player",
    "the frozen option never overwrote the player's saved value")
  T.eq(opts.modOptions.beta.tint, "player", "for any pinned mod")
end

-- ------- an open cart layers the player's mods on top

do
  local files = install()
  writeCart(files, cartTable("open", "open",
    { pin("beta", "1.0.0", { tint = "cart" }), pin("gamma", "1.0.0", { tint = "cart" }) },
    { "beta", "gamma" }))
  SaveData.setCart("open", "hash2")

  local loader, data, ok = boot(files)
  T.check(ok, "an open cart loads")
  T.eq(names(loader.order), "beta,gamma,alpha",
    "the cart's mods come first in its order, then the player's own")
  T.eq(data.pokemon.BETA.name, "player",
    "an open cart's option is a starting value the player's own setting beats")
  T.eq(data.pokemon.GAMMA.name, "cart",
    "and it stands where the player set nothing")
  T.eq(data.pokemon.ALPHA.name, "player", "the player's extra mod loads normally")
  T.eq(loader:cartStatus().enforced, false, "an open cart enforces nothing")
end

-- ------- a pin the cart ships switched off

local function withFlags(files, flags)
  local opts = SaveSerializer.decode(files["options.lua"]) or {}
  opts.mods = opts.mods or {}
  for id, on in pairs(flags) do opts.mods[id] = on end
  files["options.lua"] = SaveSerializer.encode(opts)
  return files
end

local function withCartFlags(files, cartId, flags)
  local opts = SaveSerializer.decode(files["options.lua"]) or {}
  opts.cartMods = opts.cartMods or {}
  opts.cartMods[cartId] = opts.cartMods[cartId] or {}
  for id, on in pairs(flags) do opts.cartMods[cartId][id] = on end
  files["options.lua"] = SaveSerializer.encode(opts)
  return files
end

do
  local files = install()
  writeCart(files, cartTable("shipped_off", "sealed",
    { pin("alpha"), offPin("gamma", "1.0.0", { tint = "cart" }) },
    { "alpha", "gamma" }))
  SaveData.setCart("shipped_off", "hashA")

  local loader, data, ok = boot(files)
  T.check(ok, "a sealed cart that ships a mod switched off loads")
  T.eq(names(loader.order), "alpha", "and runs only the pins it ships switched on")
  T.eq(data.pokemon.GAMMA, nil, "the switched-off pin does not run")
  T.eq(loader.mods.gamma.enabled, false, "and is reported as inactive")
  T.eq(loader.mods.gamma.state, "disabled", "with the disabled row state")
  T.check(loader.mods.gamma ~= nil, "while still being installed")
  T.eq(loader:cartStatus().pins.gamma.options.tint, "cart",
    "carrying the settings the cart shipped it with")
end

do
  local files = withCartFlags(install(), "welded", { gamma = true })
  writeCart(files, cartTable("welded", "sealed",
    { pin("alpha"), offPin("gamma") }, { "alpha", "gamma" }))
  SaveData.setCart("welded", "hashB")

  local loader, data, ok = boot(files)
  T.check(ok, "a sealed cart loads with the player asking for the off pin")
  T.eq(data.pokemon.GAMMA, nil, "but sealed refuses the toggle")
  T.eq(loader.mods.gamma.enabled, false, "the pin stays exactly as the cart shipped it")
end

-- ------- sealed+ : the same fixed set, switchable

do
  local files = withCartFlags(install(), "plus", { gamma = true })
  writeCart(files, cartTable("plus", "sealed+",
    { pin("alpha"), offPin("gamma", "1.0.0", { tint = "cart" }) },
    { "alpha", "gamma" }))
  SaveData.setCart("plus", "hashC")

  local loader, data, ok = boot(files)
  T.check(ok, "a sealed+ cart loads")
  local report = loader:cartStatus()
  T.eq(report.seal, "sealed+", "the report carries the new seal")
  T.eq(report.sealed, true, "which is a sealed cart")
  T.eq(report.enforced, true, "and is enforced like one")
  T.eq(names(loader.order), "alpha,gamma",
    "the player switched the cart's off pin on and it runs")
  T.eq(data.pokemon.GAMMA.name, "cart",
    "still with the cart's frozen option value, not the player's")
  T.eq(data.pokemon.BETA, nil, "a mod the cart does not pin cannot be added")
  T.eq(loader.mods.beta.enabled, false, "and stays switched off")
end

do
  local files = withCartFlags(install(), "plus_off", { alpha = false })
  writeCart(files, cartTable("plus_off", "sealed+",
    { pin("alpha"), pin("gamma") }, { "alpha", "gamma" }))
  SaveData.setCart("plus_off", "hashD")

  local loader, data, ok = boot(files)
  T.check(ok, "a sealed+ cart loads with a pin the player switched off")
  T.eq(names(loader.order), "gamma", "which does not run")
  T.eq(data.pokemon.ALPHA, nil, "so its content is absent")
  T.eq(loader.mods.alpha.enabled, false, "and the row reads as off")
end

do
  local files = install()
  writeCart(files, cartTable("plus_gap", "sealed+",
    { pin("alpha"), pin("delta", "2.0.0") }, { "alpha", "delta" }))
  SaveData.setCart("plus_gap", "hashE")

  local loader, _, ok = boot(files)
  T.check(not ok, "sealed+ still refuses a pin that is not installed")
  T.eq(#loader.order, 0, "and plays no subset of itself")
  T.eq(loader:cartStatus().refused, true, "the report refuses it")
end

do
  local files = install()
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  writeCart(files, cartTable("plus_seal", "sealed+",
    { pin("alpha"), offPin("gamma") }, { "alpha", "gamma" }))
  SaveData.setCart("plus_seal", "hashF")
  local slot = SaveData.createCartSlot("plus_seal")
  SaveData.setActiveCartSlot("plus_seal", slot)

  local loader = boot(files)
  T.check(loader:setEnabled("gamma", true), "switch a sealed+ pin on")
  T.eq(SaveData.isSealBroken(), false, "which does not break the session seal")
  T.eq(SaveData.slotSealBroken("plus_seal", slot), false,
    "nor mark the save slot modified")
  T.eq(SaveData.adoptCartSeal("plus_seal"), false,
    "so the next boot still adopts an intact seal")

  local again, data, ok = boot(files)
  T.check(ok, "and the cart loads again")
  T.eq(names(again.order), "alpha,gamma", "with the mod the player switched on")
  T.eq(data.pokemon.BETA, nil, "and still nothing the cart does not pin")
end

do
  local files = withFlags(install(), { gamma = false })
  writeCart(files, cartTable("plus_split", "sealed+",
    { pin("alpha"), offPin("gamma") }, { "alpha", "gamma" }))
  SaveData.setCart("plus_split", "hashI")

  local loader = boot(files)
  T.eq(loader.mods.gamma.enabled, false, "a cart's off pin starts off")
  T.check(loader:setEnabled("gamma", true), "and the player switches it on")
  local opts = options(files)
  T.eq(opts.cartMods.plus_split.gamma, true,
    "the answer is stored under the cart that asked for it")
  T.eq(SaveData.modEnabled(opts, "gamma", "red"), false,
    "and the base game's own flag for that mod is untouched")
end

-- ------- an open cart hands back only the pins it ships switched off

do
  local files = withCartFlags(install(), "open_off", { gamma = true })
  writeCart(files, cartTable("open_off", "open",
    { pin("beta"), offPin("gamma") }, { "beta", "gamma" }))
  SaveData.setCart("open_off", "hashG")

  local loader, data, ok = boot(files)
  T.check(ok, "an open cart with a switched-off pin loads")
  T.check(data.pokemon.GAMMA ~= nil, "the player switched it on, so it runs")
  T.eq(loader.mods.beta.enabled, true,
    "while a pin the cart says nothing about is still forced on")
end

do
  local files = install()
  writeCart(files, cartTable("open_quiet", "open",
    { pin("beta"), offPin("gamma") }, { "beta", "gamma" }))
  SaveData.setCart("open_quiet", "hashH")

  local loader, data, ok = boot(files)
  T.check(ok, "an open cart whose off pin the player never touched loads")
  T.eq(data.pokemon.GAMMA, nil, "with that pin off by default")
  T.eq(loader.mods.gamma.enabled, false, "and reported off")
end

-- ------- a missing pin: refusal when sealed, warning when open

do
  local files = install()
  writeCart(files, cartTable("gap", "sealed",
    { pin("alpha"), pin("delta", "2.0.0") }, { "alpha", "delta" }))
  SaveData.setCart("gap", "hash3")

  local loader, data, ok = boot(files)
  T.check(not ok, "a sealed cart with an uninstalled pin fails the load")
  T.eq(#loader.order, 0, "and plays no subset of itself")
  T.eq(data.pokemon.ALPHA, nil, "not even the pin that is installed")
  T.eq(data.pokemon.GAMMA, nil, "and certainly not the player's own mods")

  local report = loader:cartStatus()
  T.eq(report.refused, true, "the report refuses the cart")
  T.eq(#report.missing, 1, "naming one missing pin")
  T.eq(report.missing[1].id, "delta", "by id")
  T.eq(report.missing[1].version, "2.0.0", "and by the version it pins")
  T.eq(report.missing[1].source, "local", "with the source it would come from")
  T.check(report.message:find("delta 2.0.0 is not installed", 1, true) ~= nil,
    "and a message the launcher can show")
  T.eq(loader.errors[1], report.message, "the refusal is on the boot error list")

  local opts = options(files)
  T.eq(SaveData.modEnabled(opts, "beta", "red"), false,
    "a refusal still leaves the player's flags alone")
end

do
  local files = install()
  writeCart(files, cartTable("gap", "open",
    { pin("alpha"), pin("delta", "2.0.0") }, { "alpha", "delta" }))
  SaveData.setCart("gap", "hash4")

  local loader, data, ok = boot(files)
  T.check(ok, "an open cart with an uninstalled pin still loads")
  T.eq(names(loader.order), "alpha,gamma", "with the pins it does have, then the rest")
  T.eq(data.pokemon.ALPHA.name, "player", "the surviving pin runs")
  local report = loader:cartStatus()
  T.eq(report.refused, false, "the missing pin is a warning, not a refusal")
  T.eq(report.missing[1].id, "delta", "and is still reported by id")
end

-- ------- a pin installed at another version

do
  local files = install()
  writeCart(files, cartTable("skew", "sealed",
    { pin("alpha", "2.0.0") }, { "alpha" }))
  SaveData.setCart("skew", "hash5")

  local loader, _, ok = boot(files)
  T.check(not ok, "a sealed cart refuses a pin installed at another version")
  T.eq(#loader.order, 0, "and loads nothing")
  local report = loader:cartStatus()
  T.eq(report.mismatched[1].id, "alpha", "the mismatch names the mod")
  T.eq(report.mismatched[1].version, "2.0.0", "the version the cart pins")
  T.eq(report.mismatched[1].installed, "1.0.0", "and the version installed")
  T.check(report.message:find("alpha is pinned at 2.0.0 but 1.0.0 is installed",
    1, true) ~= nil, "with a message the launcher can show")
end

do
  local files = install()
  writeCart(files, cartTable("skew", "open",
    { pin("alpha", "2.0.0") }, { "alpha" }))
  SaveData.setCart("skew", "hash6")

  local loader, data, ok = boot(files)
  T.check(ok, "an open cart warns about a version skew instead of refusing")
  T.eq(data.pokemon.ALPHA.name, "player", "and loads the version that is there")
  T.eq(loader:cartStatus().mismatched[1].installed, "1.0.0", "while reporting it")
end

-- ------- an unreadable cart

do
  local files = install()
  SaveData.setCart("ghost", "hash7")
  local loader, data, ok = boot(files)
  T.check(not ok, "a cart that is not installed cannot be played as that cart")
  T.eq(data.pokemon.GAMMA, nil, "so nothing loads under its name")
  T.check(loader:cartStatus().message:find("ghost", 1, true) ~= nil,
    "and the report names the cart that went missing")
end

-- ------- breaking the seal downgrades a sealed cart to the open answer

do
  local files = install()
  writeCart(files, cartTable("sealed", "sealed",
    { pin("beta", "1.0.0", { tint = "cart" }), pin("delta", "2.0.0") },
    { "beta", "delta" }))
  SaveData.setCart("sealed", "hash8")
  SaveData.breakSeal()

  local loader, data, ok = boot(files)
  T.check(ok, "a broken seal no longer refuses over a missing pin")
  T.eq(names(loader.order), "beta,alpha,gamma",
    "the player's own mods load alongside the cart's")
  T.eq(data.pokemon.BETA.name, "player",
    "and the player's option values come back with them")
  local report = loader:cartStatus()
  T.eq(report.broken, true, "the report says the seal is broken")
  T.eq(report.enforced, false, "so the seal enforces nothing")
end

-- ------- vanilla is untouched when no cart is active

do
  local files = install()
  SaveData.resetSlotState()
  local loader, data, ok = boot(files)
  T.check(ok, "a vanilla boot with no cart loads")
  T.eq(loader:cartStatus(), nil, "and reports no cart at all")
  T.eq(names(loader.order), "alpha,gamma", "with the player's enabled set, in id order")
  T.eq(data.pokemon.ALPHA.name, "player", "and the player's option values")
  T.eq(data.pokemon.BETA, nil, "the mod the player switched off stays off")
end

-- ------- planCart on its own

do
  local report = Loader.planCart(nil, {})
  T.eq(report.refused, true, "planCart refuses a cart it was handed nothing for")
  T.check(report.message:find("not installed", 1, true) ~= nil,
    "with a presentable reason")

  local unpinned = Loader.planCart(
    cartTable("c", "sealed", { pin("gamma", "0.0.0") }, { "gamma" }),
    { { id = "gamma", version = "whatever" } })
  T.eq(#unpinned.mismatched, 0,
    "a local pin captured with no semantic version makes no version claim")
  T.eq(unpinned.refused, false, "so it cannot refuse over one")

  local skew = Loader.planCart(
    cartTable("c", "sealed", { pin("gamma", "1.0.0") }, { "gamma" }),
    { gamma = { manifest = { id = "gamma", version = "1.0.0-beta" } } })
  T.eq(skew.mismatched[1].installed, "1.0.0-beta",
    "a prerelease is a different version to a sealed cart")

  local broken = Loader.planCart(
    cartTable("c", "sealed", { pin("gamma", "1.0.0") }, { "gamma" }), {}, true)
  T.eq(broken.refused, false, "a broken seal downgrades the refusal to a warning")
  T.eq(broken.missing[1].id, "gamma", "while still reporting the missing pin")
end

-- ------- the broken-seal stamp

local function plainSave(name)
  return {
    version = "red",
    player = { name = name, map = "PALLET_TOWN", x = 1, y = 1 },
    pokedex = { seen = {}, owned = {} },
    inventory = {},
    playTime = 0,
  }
end

do
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")

  T.eq(SaveData.isSealBroken(), false, "a fresh session has no broken seal")
  local save = plainSave("INTACT")
  T.eq(SaveData.isSealBroken(save), false, "and neither does a fresh save")
  T.check(SaveData.save(save, {}), "write a save under an intact seal")
  T.eq(SaveData.load("red").meta.sealBroken, nil, "which carries no stamp")

  local loaded = SaveData.load("red")
  T.check(SaveData.breakSeal(loaded), "breaking the seal stamps the save")
  T.eq(SaveData.isSealBroken(loaded), true, "the save reads back as modified")
  T.eq(SaveData.isSealBroken(), true, "and the session is armed")
  T.check(SaveData.save(loaded, {}), "save the stamped file")
  T.eq(SaveData.load("red").meta.sealBroken, true,
    "the stamp survives a save/load round trip")

  local again = SaveData.load("red")
  T.check(SaveData.save(again, {}), "re-save with a rebuilt meta stamp")
  T.eq(SaveData.load("red").meta.sealBroken, true, "buildMeta carries the stamp")

  T.eq(SaveData.unbreakSeal, nil, "there is no public unset")
  T.eq(SaveData.clearSeal, nil, "under any spelling")
  T.eq(SaveData.setSealBroken, nil, "and no setter that takes a value")
  T.check(SaveData.breakSeal(again, false), "the setter takes no argument that clears")
  T.eq(SaveData.isSealBroken(again), true, "so the stamp is still there")

  SaveData.resetSlotState()
  T.eq(SaveData.isSealBroken(), false, "a new session starts unarmed")
  local reread = SaveData.load("red")
  T.eq(reread.meta.sealBroken, true, "but the file it stamped is modified for good")
  T.check(SaveData.save(reread, {}), "and re-saving it under a fresh session")
  T.eq(SaveData.load("red").meta.sealBroken, true, "does not un-modify it")

  local fresh = plainSave("FRESH")
  T.check(SaveData.save(fresh, {}), "a save written while the session is unarmed")
  T.eq(SaveData.load("red").meta.sealBroken, nil, "carries no stamp of its own")
end

-- ------- the durable per-slot broken mark

do
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")

  local first = SaveData.createCartSlot("kanto")
  T.eq(first, "slot1", "a cart's first save slot")
  T.eq(SaveData.slotSealBroken("kanto", first), false, "starts sealed")
  T.eq(SaveData.listCartSlots("kanto")[1].sealBroken, false,
    "which its launcher row reports without loading a save")

  T.check(SaveData.markSlotSealBroken("kanto", first), "break that slot's seal")
  T.eq(SaveData.slotSealBroken("kanto", first), true, "the slot reads as broken")
  T.eq(SaveData.listCartSlots("kanto")[1].sealBroken, true,
    "and the launcher row carries it")

  SaveData.resetSlotState()
  T.eq(SaveData.slotSealBroken("kanto", first), true,
    "the mark survives a restart")

  local second = SaveData.createCartSlot("kanto")
  T.eq(SaveData.slotSealBroken("kanto", second), false,
    "a new slot under the same cart starts sealed again")

  T.eq(SaveData.clearSlotSealBroken, nil, "there is no public unset")
  T.eq(SaveData.unmarkSlotSealBroken, nil, "under any spelling")
  T.eq(SaveData.setSlotSealBroken, nil, "and no setter that takes a value")
  T.check(SaveData.markSlotSealBroken("kanto", first, false),
    "the setter takes no argument that clears")
  T.eq(SaveData.slotSealBroken("kanto", first), true, "so the mark stands")
  T.eq(SaveData.markSlotSealBroken("kanto", "slot9"), false,
    "a slot that is not registered cannot be marked")

  SaveData.setCart("kanto", "hash9")
  SaveData.setActiveCartSlot("kanto", second)
  T.eq(SaveData.adoptCartSeal("kanto"), false,
    "booting an unmarked slot leaves the session sealed")
  T.eq(SaveData.isSealBroken(), false, "so the loader still enforces the cart")
  SaveData.setActiveCartSlot("kanto", first)
  T.eq(SaveData.adoptCartSeal("kanto"), true,
    "booting the marked slot breaks the seal for the session")
  T.eq(SaveData.isSealBroken(), true, "which is what the loader reads")

  SaveData.deleteCartSlot("kanto", first)
  T.eq(SaveData.slotSealBroken("kanto", first), false,
    "deleting the playthrough takes its mark with it")
end

-- ------- a marked slot loads the cart's pins first, then the player's mods

do
  local files = install()
  writeCart(files, cartTable("marked", "sealed",
    { pin("beta", "1.0.0", { tint = "cart" }), pin("delta", "2.0.0") },
    { "beta", "delta" }))
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  SaveData.setCart("marked", "hash10")
  local slot = SaveData.createCartSlot("marked")
  SaveData.setActiveCartSlot("marked", slot)

  local intact, _, intactOk = boot(files)
  T.check(not intactOk, "an unmarked slot still refuses the missing pin")
  T.eq(intact:cartStatus().refused, true, "with the refusal on its report")

  SaveData.resetSlotState()
  SaveData.setCart("marked", "hash10")
  T.check(SaveData.markSlotSealBroken("marked", slot), "mark that slot broken")
  T.check(SaveData.adoptCartSeal("marked"), "boot adopts the mark")

  local loader, data, ok = boot(files)
  T.check(ok, "and the cart loads")
  T.eq(names(loader.order), "beta,alpha,gamma",
    "the cart's pins load first, then the player's own enabled mods")
  T.eq(data.pokemon.BETA.name, "player",
    "with the player's own option values back")
  T.eq(loader:cartStatus().broken, true, "the report says the seal is broken")

  local stamped = plainSave("BROKEN")
  T.check(SaveData.save(stamped, {}), "a save written under the adopted mark")
  T.eq(SaveData.load("red").meta.sealBroken, true,
    "carries the save's own permanent stamp")
end

love.filesystem = realFS

T.finish("cart_seal")
