package.path = "./?.lua;./?/init.lua;" .. package.path

if not rawget(_G, "bit") and not rawget(_G, "bit32") then
  local ok, bit32 = pcall(require, "bit32")
  if ok then _G.bit32 = bit32 end
end

local T = require("tests.harness")
local Base64 = require("src.core.Base64")
local CartManifest = require("src.carts.CartManifest")
local SaveSerializer = require("src.core.SaveSerializer")

local SHA = ("a1b2c3d4"):rep(8)
local MD5 = ("0123456789abcdef"):rep(2)

local function baseCart()
  return {
    id = "kanto_plus",
    title = "  Kanto Plus  ",
    version = "1.2.0",
    author = "Ren",
    repo = "ren/kanto-plus",
    summary = "A sealed set of five",
    shell = "#3FA9F5",
    label = "./art/label.png",
    base = "red",
    engine = ">=1.4.0",
    mods = {
      { id = "rare_soda", source = "github", repo = "ren/rare-soda",
        version = "0.4.1", sha256 = SHA,
        options = { sweetness = 3, flavour = "grape", fizzy = true } },
      { id = "hard_mode", source = "gamebanana", mod = 4821, file = 99123,
        md5 = MD5 },
    },
  }
end

local function rejects(mutate, fragment, what)
  local tbl = baseCart()
  mutate(tbl)
  local cart, err = CartManifest.parse(tbl)
  T.eq(cart, nil, what .. " is rejected")
  T.check(type(err) == "string" and err:find(fragment, 1, true) ~= nil,
    ("%s says why (got %s)"):format(what, tostring(err)))
end

local raw = baseCart()
local cart, err = CartManifest.parse(raw)
T.check(cart ~= nil, "a good manifest parses: " .. tostring(err))
T.eq(cart.title, "Kanto Plus", "title is trimmed")
T.eq(cart.shell, "#3fa9f5", "shell normalises to lowercase")
T.eq(cart.label, "art/label.png", "label normalises through SafePath")
T.eq(cart.seal, "sealed", "seal defaults to sealed")
T.eq(cart.base, "red", "base survives")
T.eq(cart.engine, ">=1.4.0", "engine range is kept unevaluated")
T.eq(#cart.mods, 2, "both pins survive")
T.eq(cart.mods[1].sha256, SHA, "the github pin keeps its sha256")
T.eq(cart.mods[1].repo, "ren/rare-soda", "the github pin keeps its repo")
T.eq(cart.mods[1].version, "0.4.1", "the github pin keeps its version")
T.eq(cart.mods[1].options.flavour, "grape", "frozen option values survive")
T.eq(cart.mods[2].source, "gamebanana", "the gamebanana pin keeps its source")
T.eq(cart.mods[2].mod, 4821, "the gamebanana pin keeps its mod id")
T.eq(cart.mods[2].file, 99123, "the gamebanana pin keeps its file id")
T.eq(cart.mods[2].md5, MD5, "the gamebanana pin keeps its md5")
T.eq(cart.mods[2].sha256, nil, "a gamebanana pin carries no sha256")
T.eq(cart.load_order[1], "rare_soda", "load_order defaults to the mods order")
T.eq(cart.load_order[2], "hard_mode", "load_order defaults to the mods order")

T.eq(raw.title, "  Kanto Plus  ", "parse does not trim the input in place")
T.eq(raw.shell, "#3FA9F5", "parse does not recolour the input in place")
T.eq(raw.load_order, nil, "parse does not add load_order to the input")
T.neq(cart.mods, raw.mods, "the parsed mods array is a fresh table")
T.neq(cart.mods[1].options, raw.mods[1].options, "options are copied")

local again = CartManifest.parse(baseCart())
T.eq(CartManifest.canonical(again), CartManifest.canonical(cart),
  "two independent parses encode identically")
T.eq(CartManifest.hash(again), CartManifest.hash(cart),
  "two independent parses hash identically")
T.eq(#CartManifest.hash(cart), 32, "the cart hash is an MD5 hex digest")

local bumped = baseCart()
bumped.mods[1].version = "0.4.2"
T.neq(CartManifest.hash(CartManifest.parse(bumped)), CartManifest.hash(cart),
  "a bumped mod version moves the cart hash")

local retuned = baseCart()
retuned.mods[1].options.sweetness = 4
T.neq(CartManifest.hash(CartManifest.parse(retuned)), CartManifest.hash(cart),
  "a changed option value moves the cart hash")

local reordered = baseCart()
reordered.load_order = { "hard_mode", "rare_soda" }
local reorderedCart = CartManifest.parse(reordered)
T.eq(reorderedCart.load_order[1], "hard_mode", "an explicit load_order is kept")
T.neq(CartManifest.hash(reorderedCart), CartManifest.hash(cart),
  "a different load order moves the cart hash")

local encoded = CartManifest.encode(cart)
local decoded, decodeErr = CartManifest.decode(encoded)
T.check(decoded ~= nil, "an encoded cart decodes: " .. tostring(decodeErr))
T.same(decoded, cart, "the round trip is lossless")
T.eq(CartManifest.hash(decoded), CartManifest.hash(cart),
  "the round trip keeps the cart hash")

T.eq(CartManifest.decode(nil), nil, "decode refuses a non-string")
T.eq(CartManifest.decode(""), nil, "decode refuses an empty file")
T.eq(CartManifest.decode("return { }"), nil, "decode refuses an untagged file")
T.eq(CartManifest.decode('return { format = "g1rmodlist" }'), nil,
  "decode refuses another format's file")
T.eq(CartManifest.decode(
  ('return { format = "%s", formatVersion = 99, cart = {} }')
    :format(CartManifest.FORMAT)), nil, "decode refuses an unknown schema")
T.eq(CartManifest.decode('return os.exit(1)'), nil,
  "decode refuses a file that tries to call out")
T.eq(CartManifest.decode(
  ('return { format = "%s", formatVersion = 1, cart = { id = "x" } }')
    :format(CartManifest.FORMAT)), nil, "decode validates the cart it carries")

rejects(function(c) c.id = nil end, "cart id", "a missing id")
rejects(function(c) c.id = "kanto plus" end, "cart id", "an id with a space")
rejects(function(c) c.id = ("k"):rep(65) end, "cart id", "a 65 character id")
rejects(function(c) c.title = nil end, "cart title", "a missing title")
rejects(function(c) c.title = "   " end, "cart title", "a blank title")
rejects(function(c) c.title = ("T"):rep(49) end, "cart title", "a 49 character title")
rejects(function(c) c.version = nil end, "cart version", "a missing version")
rejects(function(c) c.version = "one" end, "cart version", "a non-semver version")
rejects(function(c) c.author = nil end, "cart author", "a missing author")
rejects(function(c) c.author = "" end, "cart author", "an empty author")
rejects(function(c) c.author = ("A"):rep(65) end, "cart author", "a 65 character author")
rejects(function(c) c.repo = "ren" end, "cart repo", "a repo with no owner")
rejects(function(c) c.repo = "ren/kanto/plus" end, "cart repo", "a three part repo")
rejects(function(c) c.summary = ("s"):rep(121) end, "cart summary", "a 121 character summary")
rejects(function(c) c.shell = nil end, "cart shell", "a missing shell colour")
rejects(function(c) c.shell = "3FA9F5" end, "cart shell", "a shell colour with no hash")
rejects(function(c) c.shell = "#3FA9F" end, "cart shell", "a five digit shell colour")
rejects(function(c) c.shell = "#gggggg" end, "cart shell", "a non-hex shell colour")
rejects(function(c) c.label = "../../etc/passwd" end, "cart label", "a climbing label path")
rejects(function(c) c.label = "/etc/passwd" end, "cart label", "an absolute label path")
rejects(function(c) c.label = ("a"):rep(129) end, "cart label", "a 129 character label path")
rejects(function(c) c.base = nil end, "cart base", "a missing base game")
rejects(function(c) c.base = "nonesuch" end, "cart base", "an unknown base game")
rejects(function(c) c.engine = "" end, "cart engine", "an empty engine range")
rejects(function(c) c.engine = 3 end, "cart engine", "a numeric engine range")
rejects(function(c) c.seal = "welded" end, "cart seal", "an unknown seal")
rejects(function(c) c.mods = nil end, "cart mods", "a cart with no mods array")
rejects(function(c) c.mods = {} end, "cart must pin", "a cart that pins nothing")
rejects(function(c)
  for i = 1, 65 do
    c.mods[i] = { id = "mod" .. i, source = "gamebanana", mod = i, file = i, md5 = MD5 }
  end
end, "cart must pin", "a cart that pins 65 mods")

rejects(function(c) c.mods[1] = "rare_soda" end, "must be a table", "a string mod entry")
rejects(function(c) c.mods[1].id = nil end, "id must be", "a pin with no id")
rejects(function(c) c.mods[1].id = "rare soda" end, "id must be", "a pin id with a space")
rejects(function(c) c.mods[2].id = "rare_soda" end, "pinned twice", "the same mod pinned twice")
rejects(function(c) c.mods[1].source = nil end, "source must be", "a pin with no source")
rejects(function(c) c.mods[1].source = "dropbox" end, "source must be", "a pin from an unknown source")
rejects(function(c) c.mods[1].repo = nil end, "repo must be", "a github pin with no repo")
rejects(function(c) c.mods[1].version = "latest" end, "version must be", "a github pin with no semver")
rejects(function(c) c.mods[1].sha256 = nil end, "sha256", "a github pin with no sha256")
rejects(function(c) c.mods[1].sha256 = SHA:upper() end, "sha256", "an uppercase sha256")
rejects(function(c) c.mods[1].sha256 = SHA:sub(1, 63) end, "sha256", "a short sha256")
rejects(function(c) c.mods[2].mod = nil end, "mod must be", "a gamebanana pin with no mod id")
rejects(function(c) c.mods[2].mod = 0 end, "mod must be", "a gamebanana mod id of zero")
rejects(function(c) c.mods[2].mod = 12.5 end, "mod must be", "a fractional gamebanana mod id")
rejects(function(c) c.mods[2].file = nil end, "file must be", "a gamebanana pin with no file id")
rejects(function(c) c.mods[2].file = -3 end, "file must be", "a negative gamebanana file id")
rejects(function(c) c.mods[2].md5 = nil end, "md5", "a gamebanana pin with no md5")
rejects(function(c) c.mods[2].md5 = MD5:upper() end, "md5", "an uppercase md5")
rejects(function(c) c.mods[2].md5 = MD5 .. "00" end, "md5", "an overlong md5")

rejects(function(c) c.mods[1].options = "grape" end, "options must be a table",
  "a non-table options block")
rejects(function(c) c.mods[1].options = { [("k"):rep(65)] = 1 } end,
  "option keys", "a 65 character option key")
rejects(function(c) c.mods[1].options = { [1] = "grape" } end,
  "option keys", "a numeric option key")
rejects(function(c) c.mods[1].options.nested = { 1, 2 } end,
  "must be a string, number or boolean", "a table option value")
rejects(function(c) c.mods[1].options.flavour = ("g"):rep(257) end,
  "characters or fewer", "a 257 character option value")
rejects(function(c)
  local options = {}
  for i = 1, 65 do options["opt" .. i] = i end
  c.mods[1].options = options
end, "more than 64 options", "a pin with 65 options")

rejects(function(c) c.load_order = "rare_soda" end, "load_order must be an array",
  "a string load_order")
rejects(function(c) c.load_order = { "rare_soda" } end, "exactly once",
  "a load_order that drops a mod")
rejects(function(c) c.load_order = { "rare_soda", "hard_mode", "hard_mode" } end,
  "exactly once", "a load_order longer than the mods array")
rejects(function(c) c.load_order = { "rare_soda", "rare_soda" } end, "twice",
  "a load_order that repeats a mod")
rejects(function(c) c.load_order = { "rare_soda", "master_ball" } end,
  "does not pin", "a load_order naming an unpinned mod")

rejects(function(c) c.mods[1].enabled = "no" end, "enabled must be",
  "a string enabled flag")
rejects(function(c) c.mods[1].enabled = 0 end, "enabled must be",
  "a numeric enabled flag")

rejects(function(c) c.options = "fast" end, "cart options must be a table",
  "a non-table cart options block")
rejects(function(c) c.options = { [2] = 1 } end, "cart option keys",
  "a numeric cart option key")
rejects(function(c) c.options = { textSpeed = { 1 } } end,
  "must be a string, number or boolean", "a table cart option value")

T.eq(CartManifest.parse(nil), nil, "parse refuses a non-table")

-- ------- a pin the cart ships switched off

T.eq(cart.mods[1].enabled, nil, "a pin that says nothing carries no enabled flag")
T.eq(CartManifest.modEnabled(cart.mods[1]), true, "and defaults to enabled")
T.eq(CartManifest.modEnabled(nil), false, "modEnabled refuses a non-entry")

local offRaw = baseCart()
offRaw.mods[1].enabled = false
local offCart = CartManifest.parse(offRaw)
T.check(offCart ~= nil, "a pin switched off parses")
T.eq(offCart.mods[1].enabled, false, "and keeps the flag")
T.eq(CartManifest.modEnabled(offCart.mods[1]), false, "which reads back as off")
T.eq(offCart.mods[1].sha256, SHA, "a switched-off pin is pinned like any other")
T.eq(offCart.mods[1].options.flavour, "grape", "with its options captured")
T.same(CartManifest.decode(CartManifest.encode(offCart)), offCart,
  "a switched-off pin survives the file round trip")
T.neq(CartManifest.hash(offCart), CartManifest.hash(cart),
  "and is part of the cart hash")

local onRaw = baseCart()
onRaw.mods[1].enabled = true
T.eq(CartManifest.canonical(CartManifest.parse(onRaw)),
  CartManifest.canonical(cart),
  "an explicit enabled = true is the same cart as saying nothing")

-- ------- settings the cart ships

local optRaw = baseCart()
optRaw.options = { textSpeed = 1, animations = false, ruleset = "gen1_faithful" }
local optCart, optErr = CartManifest.parse(optRaw)
T.check(optCart ~= nil, "a cart that ships settings parses: " .. tostring(optErr))
T.eq(optCart.options.textSpeed, 1, "the shipped number survives")
T.eq(optCart.options.animations, false, "the shipped boolean survives")
T.eq(optCart.options.ruleset, "gen1_faithful", "the shipped string survives")
T.eq(cart.options, nil, "a cart that ships none carries no options table")
T.same(CartManifest.decode(CartManifest.encode(optCart)), optCart,
  "shipped settings survive the file round trip")
T.neq(CartManifest.hash(optCart), CartManifest.hash(cart),
  "and are part of the cart hash")
T.neq(optCart.options, optCart.mods[1].options,
  "a cart's own settings are not a mod's")

-- ------- the sealed+ seal

local plusRaw = baseCart()
plusRaw.seal = "sealed+"
local plusCart, plusErr = CartManifest.parse(plusRaw)
T.check(plusCart ~= nil, "a sealed+ cart parses: " .. tostring(plusErr))
T.eq(plusCart.seal, "sealed+", "the seal survives")
T.same(CartManifest.decode(CartManifest.encode(plusCart)), plusCart,
  "a sealed+ cart round trips through a file")
T.neq(CartManifest.hash(plusCart), CartManifest.hash(cart),
  "and sealed+ is part of the cart hash")
T.eq(CartManifest.SEALS["sealed+"], true, "sealed+ is a known seal")

-- ------- the launcher fields the file round trip used to drop

local dressed = baseCart()
dressed.finish = "sparkle+holo"
dressed.speeds = { 1, 2 }
local dressedCart = CartManifest.parse(dressed)
local reread = CartManifest.decode(CartManifest.encode(dressedCart))
T.eq(reread.finish, "sparkle+holo", "a cart's finish survives the file round trip")
T.same(reread.speeds, { 1, 2 }, "and so does its speed ladder")
T.eq(CartManifest.hash(reread), CartManifest.hash(dressedCart),
  "so an installed copy hashes the same as the one that was written")

-- ------- a cart that uses none of the above serializes exactly as it always did

T.eq(CartManifest.canonical(cart),
  "[cart].6:author$3:Ren.4:base$3:red.6:engine$7:>=1.4.0.2:id$10:kanto_plus"
  .. ".5:label$13:art/label.png.4:repo$14:ren/kanto-plus.4:seal$6:sealed"
  .. ".5:shell$7:#3fa9f5.7:summary$20:A sealed set of five.5:title$10:Kanto Plus"
  .. ".7:version$5:1.2.0[mods]@9:rare_soda.2:id$9:rare_soda"
  .. ".4:repo$13:ren/rare-soda.6:sha256$64:" .. SHA
  .. ".6:source$6:github.7:version$5:0.4.1[options].5:fizzyT.7:flavour$5:grape"
  .. ".9:sweetness#3@9:hard_mode.4:file#99123.2:id$9:hard_mode.3:md5$32:" .. MD5
  .. ".3:mod#4821.6:source$10:gamebanana[options][order]@9:rare_soda@9:hard_mode",
  "the canonical string of a cart using no new field is byte for byte the old one")
T.eq(CartManifest.hash(cart), "2a8fbbacbd1df3f349b6a6ed387fa036",
  "so its hash, and every save stamped with it, is unchanged")

local open = baseCart()
open.seal = "open"
open.repo = nil
open.summary = nil
open.label = nil
open.engine = nil
local openCart = CartManifest.parse(open)
T.check(openCart ~= nil, "an open cart with no optional fields parses")
T.eq(openCart.seal, "open", "an open seal survives")
T.eq(openCart.label, nil, "an absent label stays absent")
T.same(CartManifest.decode(CartManifest.encode(openCart)), openCart,
  "an open cart round trips")
T.neq(CartManifest.hash(openCart), CartManifest.hash(cart),
  "the seal is part of the cart hash")

T.eq(CartManifest.publishable(cart), true,
  "a cart pinned entirely to github and gamebanana is publishable")
T.eq(CartManifest.publishable(nil), false, "publishable refuses a non-cart")
T.eq(CartManifest.publishable({}), false, "publishable refuses an unparsed cart")

local localised = baseCart()
localised.mods[1] = { id = "rare_soda", source = "local", version = "0.4.1",
                      repo = "ren/rare-soda", sha256 = SHA,
                      options = { flavour = "grape" } }
local localCart, localErr = CartManifest.parse(localised)
T.check(localCart ~= nil, "a local pin parses: " .. tostring(localErr))
T.eq(localCart.mods[1].source, "local", "the local pin keeps its source")
T.eq(localCart.mods[1].version, "0.4.1", "the local pin keeps its version")
T.eq(localCart.mods[1].repo, nil, "a local pin carries no repo")
T.eq(localCart.mods[1].sha256, nil, "a local pin carries no sha256")
T.eq(localCart.mods[1].md5, nil, "a local pin carries no md5")
T.eq(localCart.mods[1].options.flavour, "grape", "a local pin still freezes options")
T.eq(localCart.mods[2].source, "gamebanana", "the sibling pin is untouched")

T.eq(CartManifest.canonical(CartManifest.parse(localised)),
  CartManifest.canonical(localCart), "two parses of a local pin encode identically")
T.eq(CartManifest.hash(CartManifest.parse(localised)), CartManifest.hash(localCart),
  "two parses of a local pin hash identically")
T.neq(CartManifest.hash(localCart), CartManifest.hash(cart),
  "a local pin hashes differently from the github pin it replaced")

local localBump = baseCart()
localBump.mods[1] = { id = "rare_soda", source = "local", version = "0.4.2",
                      options = { flavour = "grape" } }
T.neq(CartManifest.hash(CartManifest.parse(localBump)), CartManifest.hash(localCart),
  "a bumped local pin version moves the cart hash")

T.same(CartManifest.decode(CartManifest.encode(localCart)), localCart,
  "a cart holding a local pin round trips")

local publishableLocal, localWhy = CartManifest.publishable(localCart)
T.eq(publishableLocal, false, "a cart holding a local pin is not publishable")
T.check(type(localWhy) == "string" and localWhy:find("rare_soda", 1, true) ~= nil,
  "the reason names the local pin (got " .. tostring(localWhy) .. ")")
T.check(localWhy:find("hard_mode", 1, true) == nil,
  "the reason leaves the publishable pins out")

local allLocal = baseCart()
allLocal.mods = {
  { id = "rare_soda", source = "local", version = "0.4.1" },
  { id = "hard_mode", source = "local", version = "2.0.0" },
}
local _, allWhy = CartManifest.publishable(CartManifest.parse(allLocal))
T.check(allWhy:find("hard_mode", 1, true) ~= nil and allWhy:find("rare_soda", 1, true) ~= nil,
  "the reason names every local pin (got " .. tostring(allWhy) .. ")")

rejects(function(c) c.mods[1] = { id = "rare_soda", source = "local" } end,
  "version must be", "a local pin with no version")
rejects(function(c)
  c.mods[1] = { id = "rare_soda", source = "local", version = "latest" }
end, "version must be", "a local pin with a non-semver version")
rejects(function(c) c.mods[1].source = "localhost" end, "source must be",
  "a source that merely starts like local")

local VECTORS = {
  { "", "" }, { "f", "Zg==" }, { "fo", "Zm8=" }, { "foo", "Zm9v" },
  { "foob", "Zm9vYg==" }, { "fooba", "Zm9vYmE=" }, { "foobar", "Zm9vYmFy" },
  { "\0\255\0", "AP8A" }, { "\255\255\255\255", "/////w==" },
}
for _, row in ipairs(VECTORS) do
  T.eq(Base64.encode(row[1]), row[2],
    ("base64 encodes %q as %s"):format(row[1], row[2]))
  T.eq(Base64.decode(row[2]), row[1],
    ("base64 decodes %s back"):format(row[2] == "" and "an empty string" or row[2]))
end

local seed = 7
local function nextByte()
  seed = (seed * 75 + 74) % 65537
  return seed % 256
end
for n = 0, 24 do
  local chunk = {}
  for i = 1, n do chunk[i] = string.char(nextByte()) end
  local raw = table.concat(chunk)
  local text = Base64.encode(raw)
  T.eq(#text % 4, 0, ("base64 pads %d bytes to a multiple of four"):format(n))
  T.eq(Base64.decode(text), raw, ("base64 round trips %d random bytes"):format(n))
end

T.eq(Base64.encode(nil), nil, "base64 encode refuses a non-string")
T.eq(Base64.decode(nil), nil, "base64 decode refuses a non-string")
T.eq(Base64.decode("TWF"), nil, "base64 refuses a length that is not a multiple of four")
T.eq(Base64.decode("TW*u"), nil, "base64 refuses a character outside the alphabet")
T.eq(Base64.decode("TWFu\n\n\n\n"), nil, "base64 refuses embedded whitespace")
T.eq(Base64.decode("TW=u"), nil, "base64 refuses padding inside a group")
T.eq(Base64.decode("=WFu"), nil, "base64 refuses a leading pad character")
T.eq(Base64.decode("TWFu===="), nil, "base64 refuses a group that is all padding")
T.eq(Base64.decode("TR=="), nil, "base64 refuses one-byte padding that carries data bits")
T.eq(Base64.decode("Zm9vYmF="), nil, "base64 refuses two-byte padding that carries data bits")
T.eq(Base64.decode("TWFu"), "Man", "base64 decodes a known vector")

local PNG = CartManifest.PNG_SIGNATURE .. "\0\0\0\13IHDRtiny label art"
local ART_DATA = Base64.encode(PNG)

local NONE = {}

local function artTable(over)
  local art = { name = "label.png", encoding = "base64", bytes = #PNG,
                data = ART_DATA }
  for key, value in pairs(over or {}) do
    if value == NONE then art[key] = nil else art[key] = value end
  end
  return art
end

local function bundle(body, art)
  return SaveSerializer.encode({ format = CartManifest.FORMAT,
    formatVersion = CartManifest.SCHEMA, cart = body, labelArt = art })
end

local arted = CartManifest.parse(baseCart())
arted.labelArt = artTable()

local artedBytes = CartManifest.encode(arted)
local artedRound, artedErr = CartManifest.decode(artedBytes)
T.check(artedRound ~= nil, "a cart with label art decodes: " .. tostring(artedErr))
T.same(artedRound, arted, "the label art survives the encode and decode round trip")
T.eq(artedRound.labelArt.data, ART_DATA, "the base64 payload is preserved verbatim")
T.eq(artedRound.labelArt.bytes, #PNG, "the declared byte count is preserved")
T.eq(artedRound.labelArt.name, "label.png", "the art name is preserved")
T.eq(CartManifest.encode(artedRound), artedBytes,
  "re-encoding a decoded cart writes the same bytes")

local artBytes, artName = CartManifest.labelArtBytes(artedRound)
T.eq(artBytes, PNG, "labelArtBytes hands back the PNG that was packed")
T.eq(artName, "label.png", "labelArtBytes hands back the art name")
T.eq(CartManifest.labelArtBytes(cart), nil, "a cart with no art has no art bytes")

T.eq(CartManifest.hash(arted), CartManifest.hash(cart),
  "label art is not part of the cart hash")
T.check(CartManifest.canonical(arted):find(ART_DATA, 1, true) == nil,
  "the canonical form leaves the art payload out")

local repainted = CartManifest.parse(baseCart())
local REPAINT = PNG .. "repainted"
repainted.labelArt = artTable({ data = Base64.encode(REPAINT), bytes = #REPAINT })
T.eq(CartManifest.hash(repainted), CartManifest.hash(arted),
  "changing only the art leaves the cart hash alone")
T.eq(CartManifest.labelArtBytes(CartManifest.decode(CartManifest.encode(repainted))),
  REPAINT, "the repainted art round trips")

local plain = CartManifest.decode(CartManifest.encode(cart))
T.eq(plain.labelArt, nil, "a cart with no art still decodes without art")
T.check(CartManifest.encode(cart):find("labelArt", 1, true) == nil,
  "a cart with no art writes no labelArt key")
T.same(plain, cart, "a cart with no art round trips exactly as before")

local OVERSIZE = PNG .. string.rep("\0", CartManifest.MAX_LABEL_ART)
local OVERSIZE_DATA = Base64.encode(OVERSIZE)

local function drops(art, what)
  local decodedArt, dropErr = CartManifest.decode(bundle(cart, art))
  T.check(decodedArt ~= nil, what .. " still loads the cart: " .. tostring(dropErr))
  T.eq(decodedArt.labelArt, nil, what .. " drops the art")
  T.same(decodedArt, cart, what .. " leaves the rest of the cart untouched")
end

drops("label.png", "art that is not a table")
drops(artTable({ encoding = "hex" }), "art in an encoding we do not support")
drops(artTable({ encoding = NONE }), "art with no encoding")
drops(artTable({ data = "not base64!!" }), "art whose payload is not base64")
drops(artTable({ data = NONE }), "art with no payload")
drops(artTable({ data = "" }), "art with an empty payload")
drops(artTable({ bytes = #PNG + 1 }), "art whose byte count is too high")
drops(artTable({ bytes = #PNG - 1 }), "art whose byte count is too low")
drops(artTable({ bytes = NONE }), "art with no byte count")
drops(artTable({ bytes = tostring(#PNG) }), "art whose byte count is a string")
drops(artTable({ data = Base64.encode("GIF89a not a png at all"),
                 bytes = #"GIF89a not a png at all" }), "art that is not a PNG")
drops(artTable({ data = OVERSIZE_DATA, bytes = #OVERSIZE }), "art past the size cap")
drops(artTable({ name = "../../etc/passwd" }), "art whose name climbs out")
drops(artTable({ name = ("a"):rep(129) }), "art with a 129 character name")
drops(artTable({ name = 7 }), "art with a numeric name")

local unnamed = CartManifest.decode(bundle(cart, artTable({ name = NONE })))
T.check(unnamed ~= nil and unnamed.labelArt ~= nil, "art with no name is still kept")
T.eq(unnamed.labelArt.name, nil, "the missing art name stays missing")
T.eq(CartManifest.labelArtBytes(unnamed), PNG, "unnamed art still decodes")

T.eq(CartManifest.parseLabelArt(nil), nil, "parseLabelArt refuses an absent payload")
local _, capErr = CartManifest.parseLabelArt(
  artTable({ data = OVERSIZE_DATA, bytes = #OVERSIZE }))
T.check(type(capErr) == "string" and capErr:find("bytes or fewer", 1, true) ~= nil,
  "the size cap says why (got " .. tostring(capErr) .. ")")
local _, pngErr = CartManifest.parseLabelArt(
  artTable({ data = Base64.encode("nope"), bytes = 4 }))
T.check(type(pngErr) == "string" and pngErr:find("PNG", 1, true) ~= nil,
  "a non-PNG payload says why (got " .. tostring(pngErr) .. ")")

T.finish("cart_manifest")
