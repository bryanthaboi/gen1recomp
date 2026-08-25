local CartManifest = require("src.carts.CartManifest")
local SaveData = require("src.core.SaveData")
local Semver = require("src.mods.Semver")

local CartStore = {}

CartStore.DIR = CartManifest.DIR
CartStore.EXT = CartManifest.EXT
CartStore.OPTIONS_KEY = "carts"
CartStore.UNPINNED_VERSION = "0.0.0"

local RECORD_FIELDS = { "id", "title", "version", "author", "base", "seal",
                        "shell", "finish", "speeds", "summary", "hash", "file" }

local function fsOr(fs)
  return fs or (love and love.filesystem) or nil
end

local function safeId(id)
  return type(id) == "string" and id ~= "" and #id <= CartManifest.MAX_ID
    and id:match("^[%w_%-]+$") ~= nil
end

local function fileFor(id)
  return CartStore.DIR .. "/" .. id .. CartStore.EXT
end
CartStore.fileFor = fileFor

local function readOptions(fs)
  local ok, opts = pcall(SaveData.loadOptions, fs)
  if not ok or type(opts) ~= "table" then return {} end
  return opts
end

local function writeOptions(opts, fs)
  local ok = pcall(SaveData.saveOptions, opts, fs)
  return ok and true or false
end

local function registry(opts)
  local reg = opts[CartStore.OPTIONS_KEY]
  return type(reg) == "table" and reg or nil
end

local function ensureRegistry(opts)
  if type(opts[CartStore.OPTIONS_KEY]) ~= "table" then
    opts[CartStore.OPTIONS_KEY] = {}
  end
  return opts[CartStore.OPTIONS_KEY]
end

local function recordFor(cart, hash)
  return { id = cart.id, title = cart.title, version = cart.version,
           author = cart.author, base = cart.base, seal = cart.seal,
           shell = cart.shell, finish = cart.finish, speeds = cart.speeds,
           summary = cart.summary,
           hash = hash, file = fileFor(cart.id) }
end

local function sameValue(a, b)
  if type(a) == "table" and type(b) == "table" then
    if #a ~= #b then return false end
    for i = 1, #a do
      if a[i] ~= b[i] then return false end
    end
    return true
  end
  return a == b
end

local function sameRecord(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for _, field in ipairs(RECORD_FIELDS) do
    if not sameValue(a[field], b[field]) then return false end
  end
  return true
end

local function entryFor(cart, hash)
  return { id = cart.id, title = cart.title, version = cart.version,
           author = cart.author, base = cart.base, seal = cart.seal,
           shell = cart.shell, finish = cart.finish, speeds = cart.speeds,
           summary = cart.summary, label = cart.label,
           cart = cart, cartHash = hash, file = fileFor(cart.id) }
end

local function readCart(fs, id)
  if not safeId(id) then return nil, "unknown cart id" end
  if not (fs and fs.read) then return nil, "NO FILESYSTEM" end
  local path = fileFor(id)
  if fs.getInfo and not fs.getInfo(path) then
    return nil, ("cart %q is not installed"):format(id)
  end
  local body = fs.read(path)
  if type(body) ~= "string" or body == "" then
    return nil, ("cart %q is not installed"):format(id)
  end
  local ok, cart, err = pcall(CartManifest.decode, body)
  if not ok then return nil, "BAD CART" end
  if not cart then return nil, err or "BAD CART" end
  if cart.id ~= id then
    return nil, ("cart file %s names %q"):format(path, tostring(cart.id))
  end
  local hashed, hash = pcall(CartManifest.hash, cart)
  if not hashed then return nil, "BAD CART" end
  return cart, hash
end

local function strayIds(fs, seen)
  local out = {}
  if not (fs and fs.getDirectoryItems) then return out end
  if fs.getInfo and not fs.getInfo(CartStore.DIR) then return out end
  local ok, items = pcall(fs.getDirectoryItems, CartStore.DIR)
  if not ok then return out end
  for _, name in ipairs(items or {}) do
    if type(name) == "string" and name:sub(-#CartStore.EXT) == CartStore.EXT then
      local id = name:sub(1, #name - #CartStore.EXT)
      if safeId(id) and not seen[id] then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  end
  table.sort(out)
  return out
end

function CartStore.index(fs)
  local opts = readOptions(fsOr(fs))
  local reg = registry(opts) or {}
  local out = {}
  for id, record in pairs(reg) do
    if safeId(id) and type(record) == "table" then
      local row = { id = id, file = fileFor(id) }
      for _, field in ipairs(RECORD_FIELDS) do
        if record[field] ~= nil then row[field] = record[field] end
      end
      row.id, row.title = id, record.title or id
      out[#out + 1] = row
    end
  end
  table.sort(out, function(a, b)
    local at, bt = tostring(a.title):lower(), tostring(b.title):lower()
    if at ~= bt then return at < bt end
    return a.id < b.id
  end)
  return out
end

function CartStore.list(fs)
  fs = fsOr(fs)
  local rows = {}
  if not fs then return rows end
  local opts = readOptions(fs)
  local reg = registry(opts) or {}
  local ids, seen = {}, {}
  for id in pairs(reg) do
    if safeId(id) and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  for _, id in ipairs(strayIds(fs, seen)) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    local cart, hash = readCart(fs, id)
    if cart then rows[#rows + 1] = entryFor(cart, hash) end
  end
  table.sort(rows, function(a, b)
    local at, bt = tostring(a.title):lower(), tostring(b.title):lower()
    if at ~= bt then return at < bt end
    return a.id < b.id
  end)
  local healed, changed = {}, false
  for _, row in ipairs(rows) do
    healed[row.id] = recordFor(row.cart, row.cartHash)
    if not sameRecord(reg[row.id], healed[row.id]) then changed = true end
  end
  for id in pairs(reg) do
    if healed[id] == nil then changed = true end
  end
  if changed then
    opts[CartStore.OPTIONS_KEY] = healed
    writeOptions(opts, fs)
  end
  return rows
end

function CartStore.listFor(version, fs)
  local out = {}
  for _, row in ipairs(CartStore.list(fs)) do
    if row.base == version then out[#out + 1] = row end
  end
  return out
end

function CartStore.get(id, fs)
  return readCart(fsOr(fs), id)
end

function CartStore.labelArt(id, fs)
  local cart, err = readCart(fsOr(fs), id)
  if not cart then return nil, err end
  return CartManifest.labelArtBytes(cart)
end

function CartStore.export(id, fs)
  local cart, err = readCart(fsOr(fs), id)
  if not cart then return nil, err end
  return CartManifest.encode(cart), CartManifest.hash(cart)
end

function CartStore.install(bytes, fs)
  fs = fsOr(fs)
  if not (fs and fs.write) then return nil, "NO FILESYSTEM" end
  local ok, cart, err = pcall(CartManifest.decode, bytes)
  if not ok then return nil, "BAD CART" end
  if not cart then return nil, err or "BAD CART" end
  local existing = readCart(fs, cart.id)
  if existing then
    local order = Semver.compare(cart.version, existing.version)
    if order and order < 0 then
      return nil, ("%s %s is older than the installed %s")
        :format(cart.title, cart.version, existing.version)
    end
  end
  if fs.createDirectory then fs.createDirectory(CartStore.DIR) end
  local wrote, writeErr = fs.write(fileFor(cart.id), CartManifest.encode(cart))
  if not wrote then return nil, tostring(writeErr) end
  local hash = CartManifest.hash(cart)
  local opts = readOptions(fs)
  ensureRegistry(opts)[cart.id] = recordFor(cart, hash)
  writeOptions(opts, fs)
  return cart, hash
end

function CartStore.uninstall(id, fs)
  fs = fsOr(fs)
  if not safeId(id) then return nil, "unknown cart id" end
  if not fs then return nil, "NO FILESYSTEM" end
  local path = fileFor(id)
  local present = not fs.getInfo or fs.getInfo(path) ~= nil
  if present and fs.read and fs.read(path) == nil then present = false end
  local opts = readOptions(fs)
  local reg = registry(opts)
  local known = reg ~= nil and reg[id] ~= nil
  if not present and not known then
    return nil, ("cart %q is not installed"):format(id)
  end
  if present and fs.remove then fs.remove(path) end
  if known then
    reg[id] = nil
    writeOptions(opts, fs)
  end
  return true
end

local function manifestOf(row)
  return type(row.manifest) == "table" and row.manifest or nil
end

local function textOf(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if type(value) == "string" and value ~= "" then return value end
  end
  return nil
end

local function pinRepo(row)
  local m = manifestOf(row)
  return textOf(row.github, m and m.github)
end

local function pinHash(row)
  local m = manifestOf(row)
  local hash = textOf(row.sha256, row.archiveSha256,
    m and m.sha256, m and m.archiveSha256)
  if hash and #hash == 64 and hash:match("^[0-9a-f]+$") then return hash end
  return nil
end

local function frozenOptions(bucket)
  if type(bucket) ~= "table" then return nil end
  local out, any = {}, false
  for key, value in pairs(bucket) do
    local kind = type(value)
    if type(key) == "string" and key ~= ""
        and (kind == "string" or kind == "number" or kind == "boolean") then
      out[key] = value
      any = true
    end
  end
  return any and out or nil
end

local function pinReason(repo, version, semver, hash)
  local why = {}
  if not repo then why[#why + 1] = "no GitHub repo is recorded" end
  if not semver then
    why[#why + 1] = ("version %s is not a semantic version, so it pins as %s")
      :format(version and ("%q"):format(version) or "is missing",
        CartStore.UNPINNED_VERSION)
  end
  if repo and semver and not hash then
    why[#why + 1] = "no archive hash is known yet"
  end
  return table.concat(why, " and ")
end

function CartStore.capture(identity, available, modOptions)
  if type(identity) ~= "table" then return nil, "cart identity is required" end
  local mods, order, unresolved = {}, {}, {}
  for _, row in ipairs(available or {}) do
    if type(row) == "table" and safeId(row.id) then
      local m = manifestOf(row)
      local version = textOf(row.version, m and m.version)
      local semver = version and Semver.parse(version) and version or nil
      local repo = pinRepo(row)
      local hash = pinHash(row)
      local entry
      if repo and semver and hash then
        entry = { id = row.id, source = "github", repo = repo,
                  version = semver, sha256 = hash }
      else
        entry = { id = row.id, source = "local",
                  version = semver or CartStore.UNPINNED_VERSION }
        unresolved[#unresolved + 1] = {
          id = row.id,
          name = textOf(row.name, m and m.name) or row.id,
          version = version,
          reason = pinReason(repo, version, semver, hash),
        }
      end
      -- A switched-off mod is pinned OFF rather than dropped, so the cart
      -- still ships it with the author's settings.
      if not row.enabled then entry.enabled = false end
      entry.options = frozenOptions(modOptions and modOptions[row.id])
      mods[#mods + 1] = entry
      order[#order + 1] = row.id
    end
  end
  local cart, err = CartManifest.parse({
    id = identity.id, title = identity.title, version = identity.version,
    author = identity.author, repo = identity.repo, summary = identity.summary,
    shell = identity.shell, finish = identity.finish, speeds = identity.speeds,
    label = identity.label, base = identity.base,
    engine = identity.engine, seal = identity.seal, options = identity.options,
    mods = mods, load_order = order,
  })
  if not cart then return nil, err end
  return cart, unresolved
end

return CartStore
