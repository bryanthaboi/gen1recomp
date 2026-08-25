local Base64 = require("src.core.Base64")
local GameVersion = require("src.core.GameVersion")
local SafePath = require("src.mods.SafePath")
local SaveSerializer = require("src.core.SaveSerializer")
local Semver = require("src.mods.Semver")
local StreamMD5 = require("src.mods.StreamMD5")

local CartManifest = {}

CartManifest.SCHEMA = 1
CartManifest.EXT = ".g1rcart"
CartManifest.FORMAT = "g1rcart"
CartManifest.DIR = "carts"
-- sealed: the pinned set runs exactly as pinned.  sealed+: the same fixed set,
-- but the player may switch any pinned mod on or off.  open: additive.
CartManifest.SEALS = { sealed = true, ["sealed+"] = true, open = true }
-- Shell and label finishes the launcher cartridge can render.
CartManifest.FINISHES = {
  sparkle = true, holo = true, ["sparkle+holo"] = true,
}
CartManifest.SOURCES = { github = true, gamebanana = true, ["local"] = true }
CartManifest.ART_ENCODINGS = { base64 = true }
CartManifest.PNG_SIGNATURE = "\137PNG\r\n\26\10"

CartManifest.MAX_ID = 64
CartManifest.MAX_TITLE = 48
CartManifest.MAX_AUTHOR = 64
CartManifest.MAX_SUMMARY = 120
CartManifest.MAX_LABEL = 128
CartManifest.MAX_LABEL_ART = 1024 * 1024
CartManifest.MAX_MODS = 64
CartManifest.MAX_OPTIONS = 64
CartManifest.MAX_OPTION_KEY = 64
CartManifest.MAX_OPTION_TEXT = 256

local function trim(text)
  return text:match("^%s*(.-)%s*$")
end

local function isId(value)
  return type(value) == "string" and value ~= "" and #value <= CartManifest.MAX_ID
    and value:match("^[%w_%-]+$") ~= nil
end

local function isRepo(value)
  if type(value) ~= "string" then return false end
  local owner, name = value:match("^([%w%._%-]+)/([%w%._%-]+)$")
  return owner ~= nil and name ~= nil
end

local function isHex(value, width)
  return type(value) == "string" and #value == width
    and value:match("^[0-9a-f]+$") ~= nil
end

local function isCount(value)
  return type(value) == "number" and value > 0 and value % 1 == 0
end

local function isSemver(value)
  return type(value) == "string" and Semver.parse(value) ~= nil
end

local function parseOptions(raw, label)
  if raw == nil then return nil end
  if type(raw) ~= "table" then
    return nil, label .. " options must be a table"
  end
  local keys = {}
  for key in pairs(raw) do
    if type(key) ~= "string" then
      return nil, label .. " option keys must be strings"
    end
    if key == "" or #key > CartManifest.MAX_OPTION_KEY then
      return nil, ("%s option keys must be 1 to %d characters")
        :format(label, CartManifest.MAX_OPTION_KEY)
    end
    keys[#keys + 1] = key
  end
  if #keys > CartManifest.MAX_OPTIONS then
    return nil, ("%s carries more than %d options")
      :format(label, CartManifest.MAX_OPTIONS)
  end
  local out = {}
  for _, key in ipairs(keys) do
    local value = raw[key]
    local kind = type(value)
    if kind == "string" then
      if #value > CartManifest.MAX_OPTION_TEXT then
        return nil, ("%s option %q must be %d characters or fewer")
          :format(label, key, CartManifest.MAX_OPTION_TEXT)
      end
    elseif kind ~= "number" and kind ~= "boolean" then
      return nil, ("%s option %q must be a string, number or boolean")
        :format(label, key)
    end
    out[key] = value
  end
  return out
end

local function parseMod(raw, index, seen)
  local label = ("cart mod #%d"):format(index)
  if type(raw) ~= "table" then return nil, label .. " must be a table" end
  if not isId(raw.id) then
    return nil, ("%s id must be 1 to %d characters of letters, numbers, _ or -")
      :format(label, CartManifest.MAX_ID)
  end
  label = ("cart mod %q"):format(raw.id)
  if seen[raw.id] then return nil, label .. " is pinned twice" end
  seen[raw.id] = true

  local source = raw.source
  if type(source) ~= "string" or not CartManifest.SOURCES[source] then
    return nil, label .. " source must be github, gamebanana or local"
  end

  local entry = { id = raw.id, source = source }
  if source == "github" then
    if not isRepo(raw.repo) then
      return nil, label .. " repo must be owner/name"
    end
    if not isSemver(raw.version) then
      return nil, label .. " version must be a semantic version"
    end
    if not isHex(raw.sha256, 64) then
      return nil, label .. " sha256 must be 64 lowercase hex characters"
    end
    entry.repo = raw.repo
    entry.version = trim(raw.version)
    entry.sha256 = raw.sha256
  elseif source == "local" then
    if not isSemver(raw.version) then
      return nil, label .. " version must be a semantic version"
    end
    entry.version = trim(raw.version)
  else
    if not isCount(raw.mod) then
      return nil, label .. " mod must be a positive integer"
    end
    if not isCount(raw.file) then
      return nil, label .. " file must be a positive integer"
    end
    if not isHex(raw.md5, 32) then
      return nil, label .. " md5 must be 32 lowercase hex characters"
    end
    entry.mod = raw.mod
    entry.file = raw.file
    entry.md5 = raw.md5
  end

  if raw.enabled ~= nil and type(raw.enabled) ~= "boolean" then
    return nil, label .. " enabled must be true or false"
  end
  -- Only a declared OFF is carried: an absent or explicit true is the default,
  -- so a cart that says nothing serializes exactly as it did before this field.
  if raw.enabled == false then entry.enabled = false end

  local options, err = parseOptions(raw.options, label)
  if err then return nil, err end
  entry.options = options
  return entry
end

-- A pin the cart ships switched off is installed and configured but not run.
function CartManifest.modEnabled(entry)
  return type(entry) == "table" and entry.enabled ~= false
end

local function parseOrder(raw, mods)
  local out = {}
  if raw == nil then
    for i, entry in ipairs(mods) do out[i] = entry.id end
    return out
  end
  if type(raw) ~= "table" then return nil, "cart load_order must be an array" end
  if #raw ~= #mods then
    return nil, "cart load_order must list every pinned mod exactly once"
  end
  local pinned, seen = {}, {}
  for _, entry in ipairs(mods) do pinned[entry.id] = true end
  for i = 1, #raw do
    local id = raw[i]
    if type(id) ~= "string" or not pinned[id] then
      return nil, ("cart load_order names %s, which the cart does not pin")
        :format(tostring(id))
    end
    if seen[id] then
      return nil, ("cart load_order names %s twice"):format(id)
    end
    seen[id] = true
    out[i] = id
  end
  return out
end

function CartManifest.parse(tbl)
  if type(tbl) ~= "table" then return nil, "cart must be a table" end

  if not isId(tbl.id) then
    return nil, ("cart id must be 1 to %d characters of letters, numbers, _ or -")
      :format(CartManifest.MAX_ID)
  end

  if type(tbl.title) ~= "string" then return nil, "cart title is required" end
  local title = trim(tbl.title)
  if title == "" or #title > CartManifest.MAX_TITLE then
    return nil, ("cart title must be 1 to %d characters"):format(CartManifest.MAX_TITLE)
  end

  if not isSemver(tbl.version) then
    return nil, "cart version must be a semantic version"
  end

  if type(tbl.author) ~= "string" then return nil, "cart author is required" end
  local author = trim(tbl.author)
  if author == "" or #author > CartManifest.MAX_AUTHOR then
    return nil, ("cart author must be 1 to %d characters"):format(CartManifest.MAX_AUTHOR)
  end

  local repo = nil
  if tbl.repo ~= nil then
    if not isRepo(tbl.repo) then return nil, "cart repo must be owner/name" end
    repo = tbl.repo
  end

  local summary = nil
  if tbl.summary ~= nil then
    if type(tbl.summary) ~= "string" then
      return nil, "cart summary must be a string"
    end
    summary = trim(tbl.summary)
    if #summary > CartManifest.MAX_SUMMARY then
      return nil, ("cart summary must be %d characters or fewer")
        :format(CartManifest.MAX_SUMMARY)
    end
  end

  local shell = type(tbl.shell) == "string" and tbl.shell:match("^#(%x%x%x%x%x%x)$")
  if not shell then return nil, "cart shell must be a #RRGGBB colour" end
  shell = "#" .. shell:lower()

  local label = nil
  if tbl.label ~= nil then
    if type(tbl.label) ~= "string" or #tbl.label > CartManifest.MAX_LABEL then
      return nil, ("cart label must be a path of %d characters or fewer")
        :format(CartManifest.MAX_LABEL)
    end
    label = SafePath.safe(tbl.label)
    if not label then return nil, "cart label must stay inside the cart" end
  end

  if type(tbl.base) ~= "string" or not GameVersion.VERSIONS[tbl.base] then
    return nil, "cart base must name a game this engine knows"
  end

  local engine = nil
  if tbl.engine ~= nil then
    if type(tbl.engine) ~= "string" or trim(tbl.engine) == "" then
      return nil, "cart engine must be a non-empty version range"
    end
    engine = trim(tbl.engine)
  end

  local speeds
  if tbl.speeds ~= nil then
    if type(tbl.speeds) ~= "table" or #tbl.speeds == 0 then
      return nil, "cart speeds must be a non-empty array of multipliers"
    end
    local GameSpeed = require("src.core.GameSpeed")
    local valid, seen = {}, {}
    for _, want in ipairs(GameSpeed.LEVELS) do
      for _, have in ipairs(tbl.speeds) do
        if have == want and not seen[want] then
          seen[want] = true
          valid[#valid + 1] = want
        end
      end
    end
    if #valid ~= #tbl.speeds then
      return nil, "cart speeds must all be GameSpeed levels"
    end
    speeds = valid
  end

  local finish = tbl.finish
  if finish ~= nil then
    if type(finish) ~= "string" or not CartManifest.FINISHES[finish] then
      return nil, "cart finish must be sparkle, holo or sparkle+holo"
    end
  end

  local seal = tbl.seal
  if seal == nil then seal = "sealed" end
  if type(seal) ~= "string" or not CartManifest.SEALS[seal] then
    return nil, "cart seal must be sealed, sealed+ or open"
  end

  -- The author's preferred game settings, seeded once per cart
  -- (SaveData.CART_OPTION_KEYS); unknown keys are kept but ignored.
  local cartOptions, cartOptErr = parseOptions(tbl.options, "cart")
  if cartOptErr then return nil, cartOptErr end

  if type(tbl.mods) ~= "table" then return nil, "cart mods must be an array" end
  local count = #tbl.mods
  if count < 1 or count > CartManifest.MAX_MODS then
    return nil, ("cart must pin 1 to %d mods"):format(CartManifest.MAX_MODS)
  end
  local mods, seen = {}, {}
  for i = 1, count do
    local entry, err = parseMod(tbl.mods[i], i, seen)
    if not entry then return nil, err end
    mods[i] = entry
  end

  local order, orderErr = parseOrder(tbl.load_order, mods)
  if not order then return nil, orderErr end

  return {
    id = tbl.id,
    title = title,
    version = trim(tbl.version),
    author = author,
    repo = repo,
    summary = summary,
    shell = shell,
    finish = finish,
    speeds = speeds,
    label = label,
    base = tbl.base,
    engine = engine,
    seal = seal,
    options = cartOptions,
    mods = mods,
    load_order = order,
  }
end

function CartManifest.parseLabelArt(raw)
  if raw == nil then return nil, "cart carries no label art" end
  if type(raw) ~= "table" then return nil, "cart label art must be a table" end

  if type(raw.encoding) ~= "string" or not CartManifest.ART_ENCODINGS[raw.encoding] then
    return nil, "cart label art encoding must be base64"
  end
  if type(raw.data) ~= "string" or raw.data == "" then
    return nil, "cart label art data must be a base64 string"
  end

  local tooBig = ("cart label art must be %d bytes or fewer")
    :format(CartManifest.MAX_LABEL_ART)
  if #raw.data > math.ceil(CartManifest.MAX_LABEL_ART / 3) * 4 then
    return nil, tooBig
  end

  local bytes, err = Base64.decode(raw.data)
  if not bytes then return nil, "cart label art " .. err end
  if #bytes > CartManifest.MAX_LABEL_ART then return nil, tooBig end
  if not isCount(raw.bytes) or raw.bytes ~= #bytes then
    return nil, ("cart label art declares %s bytes but decodes to %d")
      :format(tostring(raw.bytes), #bytes)
  end
  if bytes:sub(1, #CartManifest.PNG_SIGNATURE) ~= CartManifest.PNG_SIGNATURE then
    return nil, "cart label art must be a PNG"
  end

  local name = nil
  if raw.name ~= nil then
    if type(raw.name) ~= "string" or #raw.name > CartManifest.MAX_LABEL then
      return nil, ("cart label art name must be a path of %d characters or fewer")
        :format(CartManifest.MAX_LABEL)
    end
    name = SafePath.safe(raw.name)
    if not name then return nil, "cart label art name must stay inside the cart" end
  end

  return { name = name, encoding = raw.encoding, bytes = raw.bytes, data = raw.data },
    nil, bytes
end

function CartManifest.labelArtBytes(cart)
  if type(cart) ~= "table" then return nil, "cart must be a table" end
  local art, err, bytes = CartManifest.parseLabelArt(cart.labelArt)
  if not art then return nil, err end
  return bytes, art.name
end

function CartManifest.publishable(cart)
  if type(cart) ~= "table" or type(cart.mods) ~= "table" then
    return false, "a cart must be parsed before it can be published"
  end
  local unpinned = {}
  for _, entry in ipairs(cart.mods) do
    if type(entry) == "table" and entry.source == "local" then
      unpinned[#unpinned + 1] = tostring(entry.id)
    end
  end
  if #unpinned == 0 then return true end
  table.sort(unpinned)
  return false, ("%s %s pinned to this install only, so nobody else can fetch %s: publish needs a repo and an archive hash for %s")
    :format(table.concat(unpinned, ", "),
      #unpinned == 1 and "is" or "are",
      #unpinned == 1 and "it" or "them",
      #unpinned == 1 and "it" or "each")
end

local function number(value)
  return ("%.17g"):format(value)
end

local function writeText(out, prefix, text)
  out[#out + 1] = ("%s%d:%s"):format(prefix, #text, text)
end

local function writeValue(out, value)
  local kind = type(value)
  if kind == "number" then
    out[#out + 1] = "#" .. number(value)
  elseif kind == "boolean" then
    out[#out + 1] = value and "T" or "F"
  elseif kind == "table" then
    -- Length-prefixed so a list can never collide with another field's text.
    out[#out + 1] = "*" .. tostring(#value)
    for _, item in ipairs(value) do writeValue(out, item) end
  else
    writeText(out, "$", tostring(value))
  end
end

local function writeField(out, name, value)
  if value == nil then return end
  writeText(out, ".", name)
  writeValue(out, value)
end

local CART_FIELDS = { "author", "base", "engine", "finish", "id", "label",
                      "repo", "seal", "shell", "speeds", "summary", "title",
                      "version" }
local MOD_FIELDS = { "enabled", "file", "id", "md5", "mod", "repo", "sha256",
                     "source", "version" }

local function writeOptions(out, marker, options)
  out[#out + 1] = marker
  local keys = {}
  for key in pairs(options or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do writeField(out, key, options[key]) end
end

function CartManifest.canonical(cart)
  local out = { "[cart]" }
  for _, field in ipairs(CART_FIELDS) do writeField(out, field, cart[field]) end
  -- Absent when the cart ships no settings, so a cart written before this
  -- field hashes byte for byte as it did.
  if cart.options ~= nil then writeOptions(out, "[cart_options]", cart.options) end
  out[#out + 1] = "[mods]"
  for _, entry in ipairs(cart.mods or {}) do
    writeText(out, "@", tostring(entry.id))
    for _, field in ipairs(MOD_FIELDS) do writeField(out, field, entry[field]) end
    writeOptions(out, "[options]", entry.options)
  end
  out[#out + 1] = "[order]"
  for _, id in ipairs(cart.load_order or {}) do writeText(out, "@", tostring(id)) end
  return table.concat(out)
end

function CartManifest.hash(cart)
  return StreamMD5.new():update(CartManifest.canonical(cart)):final()
end

function CartManifest.encode(cart)
  return SaveSerializer.encode({
    format = CartManifest.FORMAT,
    formatVersion = CartManifest.SCHEMA,
    labelArt = CartManifest.parseLabelArt(cart.labelArt),
    -- Every field parse() keeps: a name missing here is a field the file
    -- round trip silently drops, as finish and speeds were.
    cart = { id = cart.id, title = cart.title, version = cart.version,
             author = cart.author, repo = cart.repo, summary = cart.summary,
             shell = cart.shell, finish = cart.finish, speeds = cart.speeds,
             label = cart.label, base = cart.base,
             engine = cart.engine, seal = cart.seal, options = cart.options,
             mods = cart.mods, load_order = cart.load_order },
  })
end

function CartManifest.decode(str)
  if type(str) ~= "string" or str == "" then return nil, "EMPTY FILE" end
  local data = SaveSerializer.decode(str)
  if type(data) ~= "table" then return nil, "BAD FILE" end
  if data.format ~= CartManifest.FORMAT then return nil, "NOT A CART" end
  if data.formatVersion ~= CartManifest.SCHEMA then
    return nil, ("unknown cart schema %s"):format(tostring(data.formatVersion))
  end
  local cart, err = CartManifest.parse(data.cart)
  if not cart then return nil, err end
  cart.labelArt = CartManifest.parseLabelArt(data.labelArt)
  return cart
end

return CartManifest
