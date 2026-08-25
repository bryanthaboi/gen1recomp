
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SaveSerializer = require("src.core.SaveSerializer")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")

local realFS = love.filesystem

local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      return nil
    end,
  }
end

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

local function options(files)
  return SaveSerializer.decode(files["options.lua"] or "") or {}
end

local function plainSave(name, hash)
  return {
    version = "red",
    meta = hash and { cartHash = hash } or nil,
    player = { name = name, map = "PALLET_TOWN", x = 1, y = 1 },
    pokedex = { seen = {}, owned = {} },
    inventory = {},
    playTime = 0,
  }
end

do
  fresh()
  T.eq(SaveData.getCart(), nil, "no cart is active by default")
  T.eq(SaveData.setCart("nuzlocke", "abc123"), "nuzlocke", "setCart returns the id")
  T.eq(SaveData.getCart(), "nuzlocke", "getCart reads the active cart back")
  T.eq(SaveData.getCartHash(), "abc123", "the build hash rides along")
  T.eq(SaveData.setCart(nil), nil, "setCart(nil) returns to vanilla play")
  T.eq(SaveData.getCart(), nil, "and getCart says so")
  T.eq(SaveData.getCartHash(), nil, "clearing the cart clears its build hash")

  T.eq(SaveData.setCart("../evil"), nil, "a path-climbing cart id is refused")
  T.eq(SaveData.setCart(".."), nil, "so is a bare parent reference")
  T.eq(SaveData.setCart("has spaces"), nil, "so is a non-word id")
  T.eq(SaveData.setCart(42), nil, "so is a non-string id")
  T.eq(SaveData.getCart(), nil, "none of them become the active cart")
end

do
  local files = fresh()
  T.eq(#SaveData.listCartSlots("nuzlocke"), 0, "a cart starts with no slots")
  T.eq(SaveData.activeCartSlot("nuzlocke"), nil, "and no active slot")
  T.eq(SaveData.slotCartHash("nuzlocke", "slot1"), nil, "and no stamped hash")
  T.eq(files["options.lua"], nil, "listing an empty cart writes no options file")

  T.eq(#SaveData.listCartSlots("../evil"), 0, "an unusable cart id lists nothing")
  T.eq(SaveData.createCartSlot("../evil"), nil, "and can allocate no slot")
  local ok, err = SaveData.deleteCartSlot("../evil", "slot1")
  T.check(not ok, "and deleting from it fails")
  T.check(tostring(err):find("unknown cart", 1, true) ~= nil,
    "with a user-presentable reason")
end

do
  local files = fresh()
  T.eq(SaveData.createCartSlot("nuzlocke"), "slot1", "first cart slot is slot1")
  T.eq(SaveData.createCartSlot("nuzlocke"), "slot2", "ids increment as they do per version")
  T.eq(SaveData.setActiveCartSlot("nuzlocke", "slot2"), "slot2",
    "setActiveCartSlot returns the chosen id")
  T.eq(SaveData.activeCartSlot("nuzlocke"), "slot2", "and the choice is live")

  local opts = options(files)
  T.eq(opts.cartSlots.nuzlocke.active, "slot2", "the active id persists in options.lua")
  T.eq(opts.cartSlots.nuzlocke.list[1], "slot1", "the slot list persists with it")
  T.eq(opts.cartSlots.nuzlocke.list[2], "slot2", "in allocation order")
  T.eq(opts.saveSlots, nil, "no per-version registry is created by cart work")

  T.check(SaveData.renameCartSlot("nuzlocke", "slot1", "  Hardcore  "),
    "renameCartSlot labels a registered slot")
  T.eq(options(files).cartSlots.nuzlocke.names.slot1, "Hardcore",
    "the label is trimmed and persisted")
  T.eq(SaveData.listCartSlots("nuzlocke")[1].label, "Hardcore",
    "listCartSlots carries the label")
  T.check(SaveData.renameCartSlot("nuzlocke", "slot1", ""), "an empty name clears it")
  T.eq(options(files).cartSlots.nuzlocke.names, nil,
    "the names table leaves the registry once empty")

  local bad, badErr = SaveData.renameCartSlot("nuzlocke", "slot99", "x")
  T.check(not bad, "renaming an unregistered cart slot fails")
  T.check(tostring(badErr):find("not registered", 1, true) ~= nil,
    "unknown-slot rename error is user-presentable")

  T.check(SaveData.writeCartSlot("nuzlocke", "slot2", plainSave("NUZ")),
    "seed the active cart slot")
  T.check(files["saves/cart_nuzlocke/slot2.lua"] ~= nil,
    "the bytes land in the cart's own directory")

  T.check(SaveData.deleteCartSlot("nuzlocke", "slot2"), "deleteCartSlot removes it")
  T.eq(files["saves/cart_nuzlocke/slot2.lua"], nil, "the slot file is gone")
  opts = options(files)
  T.eq(#opts.cartSlots.nuzlocke.list, 1, "the id is dropped from the registry")
  T.eq(opts.cartSlots.nuzlocke.active, "slot1",
    "active falls back to the remaining slot")
  T.eq(SaveData.activeCartSlot("nuzlocke"), "slot1", "and the live cache follows")

  T.check(SaveData.deleteCartSlot("nuzlocke", "slot1"), "deleting the last slot works")
  T.eq(#SaveData.listCartSlots("nuzlocke"), 0, "the cart is empty again")
  T.eq(options(files).cartSlots.nuzlocke.active, nil, "active clears with the list")
end

do
  local files = fresh()
  T.eq(SaveData.createCartSlot("alpha"), "slot1", "alpha allocates its own slot1")
  T.eq(SaveData.createCartSlot("beta"), "slot1", "beta allocates its own slot1")
  T.check(SaveData.writeCartSlot("alpha", "slot1", plainSave("AAA", "aaa111")),
    "seed alpha's slot")
  T.check(SaveData.writeCartSlot("beta", "slot1", plainSave("BBB", "bbb222")),
    "seed beta's slot")

  T.eq(#SaveData.listCartSlots("alpha"), 1, "alpha lists only its own slot")
  T.eq(#SaveData.listCartSlots("beta"), 1, "beta lists only its own slot")
  T.eq(SaveData.listCartSlots("alpha")[1].name, "AAA", "alpha reads its own save")
  T.eq(SaveData.listCartSlots("beta")[1].name, "BBB", "beta reads its own save")
  T.check(files["saves/cart_alpha/slot1.lua"] ~= files["saves/cart_beta/slot1.lua"],
    "two carts with the same slot id write different files")
  T.eq(SaveData.slotCartHash("alpha", "slot1"), "aaa111", "alpha's build stamp")
  T.eq(SaveData.slotCartHash("beta", "slot1"), "bbb222", "beta's build stamp")

  T.check(SaveData.deleteCartSlot("alpha", "slot1"), "delete alpha's only slot")
  T.eq(#SaveData.listCartSlots("alpha"), 0, "alpha is empty")
  T.eq(#SaveData.listCartSlots("beta"), 1, "beta is untouched")
  T.check(files["saves/cart_beta/slot1.lua"] ~= nil, "beta's file survives")
  T.eq(SaveData.slotCartHash("beta", "slot1"), "bbb222", "as does its stamp")
end

do
  local files = fresh()
  T.eq(SaveData.createSlot("red"), "slot1", "red allocates a version slot")
  T.eq(SaveData.createCartSlot("red"), "slot1",
    "a cart may even be named after a version")
  T.check(SaveData.writeSlot("red", "slot1", plainSave("VANILLA")),
    "seed the version slot")
  T.check(SaveData.writeCartSlot("red", "slot1", plainSave("CARTRED")),
    "seed the cart slot")

  T.eq(#SaveData.listSlots("red"), 1, "the version lists only its own slot")
  T.eq(SaveData.listSlots("red")[1].name, "VANILLA", "with the vanilla save in it")
  T.eq(#SaveData.listCartSlots("red"), 1, "the cart lists only its own slot")
  T.eq(SaveData.listCartSlots("red")[1].name, "CARTRED", "with the cart save in it")
  T.check(files["saves/red/slot1.lua"] ~= nil, "the version path is saves/red/")
  T.check(files["saves/cart_red/slot1.lua"] ~= nil, "the cart path is saves/cart_red/")
  T.eq(SaveData.listSlots("red")[1].cartHash, nil,
    "a version slot carries no cart hash")

  T.check(SaveData.deleteCartSlot("red", "slot1"), "uninstall-style cart slot delete")
  T.eq(#SaveData.listSlots("red"), 1, "the vanilla slot is still registered")
  T.check(files["saves/red/slot1.lua"] ~= nil, "and its file is not orphaned")
  T.eq(options(files).saveSlots.red.list[1], "slot1",
    "the version registry is independent of the cart one")
end

do
  local files = fresh()
  SaveData.setCart("nuzlocke", "abc123")
  T.eq(SaveData.saveFilename("red"), "save_cart_nuzlocke.lua",
    "with no cart slot yet, the flat path follows the version suffix scheme")

  SaveData.createCartSlot("nuzlocke")
  SaveData.setActiveCartSlot("nuzlocke", "slot1")
  T.eq(SaveData.saveFilename("red"), "saves/cart_nuzlocke/slot1.lua",
    "the active cart slot owns the save path")

  local save = SaveData.newGame()
  save.player.name = "NUZ"
  T.check(SaveData.save(save, {}), "an in-game save under a cart writes")
  T.check(files["saves/cart_nuzlocke/slot1.lua"] ~= nil, "into the cart's slot")
  T.eq(files["save.lua"], nil, "never into the base game's flat file")
  T.eq(files["saves/red/slot1.lua"], nil, "never into the base game's slot")
  T.eq(#SaveData.listSlots("red"), 0, "and the base game still has no slots")

  local loaded = SaveData.load("red")
  T.check(loaded and loaded.player.name == "NUZ", "load reads the cart's slot back")
  T.eq(loaded.meta.cartHash, "abc123", "the save records the build it was made under")
  T.eq(SaveData.slotCartHash("nuzlocke", "slot1"), "abc123",
    "and the registry mirrors it for a listing with no save decode")
  T.eq(SaveData.listCartSlots("nuzlocke")[1].cartHash, "abc123",
    "listCartSlots surfaces the stamp")
end

do
  fresh()
  SaveData.setCart("nuzlocke", "abc123")
  SaveData.createCartSlot("nuzlocke")
  SaveData.setActiveCartSlot("nuzlocke", "slot1")
  T.check(SaveData.save(SaveData.newGame(), {}), "first save under build abc123")

  local loaded = SaveData.load("red")
  T.check(SaveData.save(loaded, {}), "a re-save rebuilds meta")
  T.eq(SaveData.load("red").meta.cartHash, "abc123",
    "buildMeta carries the stamp instead of dropping it")

  SaveData.setCartHash("def456")
  T.eq(SaveData.slotCartHash("nuzlocke", "slot1"), "abc123",
    "installing an update does not restamp the slot")
  loaded = SaveData.load("red")
  T.eq(loaded.meta.cartHash, "abc123", "nor the in-progress save")
  T.check(SaveData.save(loaded, {}), "save under the new build")
  T.eq(SaveData.load("red").meta.cartHash, "def456", "now the save carries it")
  T.eq(SaveData.slotCartHash("nuzlocke", "slot1"), "def456", "and so does the registry")

  local ok, err = SaveData.setSlotCartHash("nuzlocke", "slot9", "zzz")
  T.check(not ok, "an unregistered slot cannot be stamped")
  T.check(tostring(err):find("not registered", 1, true) ~= nil,
    "with a user-presentable reason")
end

do
  local files = fresh()
  SaveData.createSlot("red")
  SaveData.setActiveSlot("red", "slot1")
  local save = SaveData.newGame()
  save.player.name = "VANILLA"
  T.check(SaveData.save(save, {}), "a vanilla save with no cart set")

  local bytes = files["saves/red/slot1.lua"]
  T.check(bytes:find("cartHash", 1, true) == nil, "records no cartHash")
  T.check(files["options.lua"]:find("cartSlots", 1, true) == nil,
    "and options.lua grows no cart registry")
  T.eq(options(files).cartSlots, nil, "which decodes as absent, not empty")

  local loaded = SaveData.load("red")
  T.check(SaveData.save(loaded), "re-save the migrated shape once")
  local before = files["saves/red/slot1.lua"]
  SaveData.setCart("nuzlocke", "abc123")
  T.eq(SaveData.saveFilename("red"), "save_cart_nuzlocke.lua",
    "the cart takes over the path while it is active")
  SaveData.setCart(nil)
  T.eq(SaveData.saveFilename("red"), "saves/red/slot1.lua",
    "and hands it straight back")
  T.check(SaveData.save(loaded), "re-save after the cart round trip")
  T.eq(files["saves/red/slot1.lua"], before, "the vanilla bytes are identical")
  T.check(files["options.lua"]:find("cartSlots", 1, true) == nil,
    "and options.lua still carries no cart registry")

  local again = SaveData.load("red")
  T.check(again and again.player.name == "VANILLA", "the vanilla save still loads")
  T.eq(again.meta.cartHash, nil, "with no cart stamp on it")
end

-- ------- cart-scoped settings

do
  local files = fresh()
  local base = SaveData.loadOptions()
  base.textSpeed = 5
  base.musicVol = 2
  base.speedBattle = 1
  T.check(SaveData.saveOptions(base), "the base game writes its own settings")
  local plain = files["options.lua"]

  SaveData.setCart("nuzlocke", "hash1")
  local inCart = SaveData.loadOptions()
  T.eq(inCart.textSpeed, 5, "a cart starts from the global value")
  T.eq(inCart.musicVol, 2, "for every key, scoped or not")
  inCart.textSpeed = 1
  inCart.musicVol = 7
  inCart.speedBattle = 4
  T.check(SaveData.saveOptions(inCart), "change some settings inside the cart")

  local stored = options(files)
  T.eq(stored.textSpeed, 5, "the global text speed is untouched")
  T.eq(stored.cartOptions.nuzlocke.textSpeed, 1, "the cart keeps its own")
  T.eq(stored.cartOptions.nuzlocke.speedBattle, 4, "and its own battle speed")
  T.eq(stored.musicVol, 7, "an unscoped setting is written globally")
  T.eq(stored.cartOptions.nuzlocke.musicVol, nil, "and never lands in the cart")

  T.eq(SaveData.loadOptions().textSpeed, 1, "the cart reads its value back")
  T.eq(SaveData.loadOptions().musicVol, 7, "and the machine's shared volume")

  SaveData.setCart("marathon", "hash2")
  T.eq(SaveData.loadOptions().textSpeed, 5,
    "another cart does not see the first cart's setting")
  local other = SaveData.loadOptions()
  other.textSpeed = 3
  T.check(SaveData.saveOptions(other), "the second cart sets its own")
  T.eq(options(files).cartOptions.nuzlocke.textSpeed, 1,
    "which leaves the first cart's alone")

  SaveData.setCart(nil)
  T.eq(SaveData.loadOptions().textSpeed, 5, "and the base game keeps the global")
  T.eq(SaveData.loadOptions().speedBattle, 1, "for every scoped key")

  T.check(plain:find("cartOptions", 1, true) ~= nil,
    "the options file declares the overlay")
  T.check(plain:find("nuzlocke", 1, true) == nil,
    "but an install that never ran a cart names no cart in it")
  SaveData.setCart(nil)
  local vanilla = SaveData.loadOptions()
  vanilla.textSpeed = 4
  T.check(SaveData.saveOptions(vanilla), "a base-game write after playing carts")
  T.eq(options(files).cartOptions.nuzlocke.textSpeed, 1,
    "leaves every cart's overlay intact")
  T.eq(options(files).cartOptions.marathon.textSpeed, 3, "for every cart")
end

do
  local files = fresh()
  SaveData.setCart("author_cart", "hash3")
  T.eq(SaveData.seedCartOptions({ textSpeed = 1, animations = false,
    musicVol = 0, nonesuch = 3 }), true, "a cart seeds its shipped settings")
  local seeded = SaveData.loadOptions()
  T.eq(seeded.textSpeed, 1, "the author's text speed applies")
  T.eq(seeded.animations, false, "and the author's battle animation choice")
  T.eq(seeded.musicVol, 7, "a machine setting is never seeded")
  T.eq(options(files).cartOptions.author_cart.musicVol, nil, "not even into the cart")
  T.eq(options(files).cartOptions.author_cart.nonesuch, nil,
    "and a key outside the cart-scoped set is ignored")
  T.eq(options(files).cartOptionsSeeded.author_cart, true, "the seed is recorded")

  local player = SaveData.loadOptions()
  player.textSpeed = 5
  T.check(SaveData.saveOptions(player), "the player then picks their own speed")
  T.eq(SaveData.seedCartOptions({ textSpeed = 1, animations = false }), false,
    "a second boot re-seeds nothing")
  T.eq(SaveData.loadOptions().textSpeed, 5, "so the player's change survives")

  SaveData.setCart(nil)
  T.eq(SaveData.loadOptions().textSpeed, 3,
    "and the base game still has the shipped default of its own")
  T.eq(SaveData.seedCartOptions({ textSpeed = 1 }), false,
    "seeding with no cart active does nothing")
end

love.filesystem = realFS

T.finish("cart_saves")
