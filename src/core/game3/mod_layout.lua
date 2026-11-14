local NativePack = require("src.import.gba.native_pack")
local ScriptColl = require("src.core.game3.scripting.collision")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local Profile = require("src.core.game3.profile")
local Merge = require("src.mods.Merge")
local Versions = require("src.import.gba.versions")

local ModLayout = {}

local LAYOUT_KEYS = { blocks = true, cells = true, border = true,
  borderWidth = true, borderHeight = true }
ModLayout.LAYOUT_KEYS = LAYOUT_KEYS

-- pokefirered/include/global.fieldmap.h:7
function ModLayout.word(entry)
  if type(entry) == "number" then
    return entry % 1024, math.floor(entry / 1024) % 4, math.floor(entry / 4096) % 16
  end
  return entry.metatile, entry.collision or 0, entry.elevation
end

local function rse()
  return Profile.active().family == "rse"
end

-- pokeemerald/src/fieldmap.c:51
local function defaultBorder()
  if rse() then return 2, 2, { 0, 0, 0, 0 } end
  return 1, 1, { 0 }
end

local function warpSet(def)
  local set = {}
  for _, w in ipairs(def.warps or {}) do
    local x, y = tonumber(w.x), tonumber(w.y)
    if x and y then set[NativePack.warpKey(x, y)] = true end
  end
  return set
end

function ModLayout.behaviors(pair)
  return pair and Interaction.behaviors and Interaction.behaviors[pair] or nil
end

function ModLayout.checkMetatile(pair, mid)
  local behaviors = ModLayout.behaviors(pair)
  if not behaviors then return nil, ('unknown tileset pair "%s"'):format(tostring(pair)) end
  if type(mid) ~= "number" or behaviors[mid] == nil then
    return nil, ("unknown block id: metatile %s is not defined by tileset pair %s")
      :format(tostring(mid), tostring(pair))
  end
  return true
end

-- pokefirered/src/scrcmd.c:2103
function ModLayout.cellColl(def, pair, mid, collision, warps, x, y)
  local behaviors = ModLayout.behaviors(pair)
  local coll = (ScriptColl.fromCell(mid, collision, behaviors and behaviors[mid], def.kind))
  return NativePack.resolveLayoutColl(coll, collision, warps[NativePack.warpKey(x, y)])
end

-- pokefirered/src/fieldmap.c:401
local function writeCells(decoded, def, spec, warps)
  local cells = decoded.cells
  for _, c in ipairs(spec.cells or {}) do
    local i = c.y * decoded.width + c.x + 1
    local cur = cells[i]
    local collision = c.collision or 0
    cells[i] = {
      mid = c.metatile,
      coll = ModLayout.cellColl(def, spec.pair or def.pair, c.metatile, collision, warps, c.x, c.y),
      elev = c.elevation or (cur and cur.elev) or 0,
    }
  end
end

local function writeBorder(decoded, spec)
  if not spec.border then return end
  decoded.borderWidth = spec.borderWidth or decoded.borderWidth
  decoded.borderHeight = spec.borderHeight or decoded.borderHeight
  local mids = {}
  for i, mid in ipairs(spec.border) do mids[i] = mid end
  decoded.borderMids = mids
end

function ModLayout.build(def)
  local spec = rawget(def, "modLayout")
  local w, h = spec.width, spec.height
  local warps = warpSet(def)
  local cells = {}
  for i = 1, w * h do
    local mid, collision, elev = ModLayout.word(spec.blocks[i])
    local x, y = (i - 1) % w, math.floor((i - 1) / w)
    cells[i] = { mid = mid, coll = ModLayout.cellColl(def, spec.pair, mid, collision, warps, x, y),
      elev = elev or 0 }
  end
  local bw, bh, mids = defaultBorder()
  local base = spec.baseBorder
  if base then
    bw, bh, mids = base.width, base.height, {}
    for i, mid in ipairs(base.mids) do mids[i] = mid end
  end
  local decoded = { width = w, height = h, trueWidth = w, trueHeight = h, cells = cells,
    borderWidth = bw, borderHeight = bh, borderMids = mids }
  writeBorder(decoded, spec)
  writeCells(decoded, def, spec, warps)
  return decoded
end

function ModLayout.apply(decoded, def)
  local spec = rawget(def, "modLayout")
  if not spec then return decoded end
  if spec.blocks then return ModLayout.build(def) end
  local out = {}
  for k, v in pairs(decoded) do out[k] = v end
  local cells = {}
  for i = 1, (decoded.width or 0) * (decoded.height or 0) do cells[i] = decoded.cells[i] end
  out.cells = cells
  writeBorder(out, spec)
  writeCells(out, def, spec, warpSet(def))
  return out
end

function ModLayout.decodedOf(layout)
  return { width = layout.width, height = layout.height,
    trueWidth = layout.trueWidth, trueHeight = layout.trueHeight,
    borderWidth = layout.borderWidth, borderHeight = layout.borderHeight,
    borderMids = layout.borderMids, cells = layout.cells }
end

function ModLayout.refresh(def, mapId)
  local LayoutNative = require("src.core.game3.layout_native")
  local spec = rawget(def, "modLayout")
  if spec.blocks then
    rawset(def, "midLayout", LayoutNative.fromDecoded(ModLayout.build(def), mapId, def.pair))
    return
  end
  local current = rawget(def, "midLayout")
  if current and current.cells then
    rawset(def, "midLayout", LayoutNative.fromDecoded(
      ModLayout.apply(ModLayout.decodedOf(current), def), mapId, current.pair or def.pair))
  end
end

local function copy(v)
  if type(v) ~= "table" then return v end
  return Merge.deepCopy(v)
end

local function addCells(spec, list, owner)
  if list == Merge.DELETE then spec.cells = {}; return end
  for n, c in ipairs(list or {}) do
    spec.cells[#spec.cells + 1] = { x = c.x, y = c.y, metatile = c.metatile,
      collision = c.collision, elevation = c.elevation, owner = owner, index = n }
  end
end

local function reset(value, owner)
  return { blocks = copy(value.blocks), width = value.width, height = value.height,
    pair = value.pair, border = copy(value.border), borderWidth = value.borderWidth,
    borderHeight = value.borderHeight, cells = {}, owner = owner,
    borderOwner = value.border ~= nil and owner or nil }
end

function ModLayout.fold(ops, old)
  local spec
  for _, entry in ipairs(ops or {}) do
    local value, owner = entry.value, entry.owner
    if entry.op == "remove" or value == Merge.DELETE then
      spec = nil
    elseif entry.op == "register" or entry.op == "override" then
      spec = nil
      if value.blocks ~= nil or value.cells ~= nil or value.border ~= nil then
        spec = reset(value, owner)
        addCells(spec, value.cells, owner)
      end
    elseif entry.op == "patch" and type(value) == "table" then
      local base = old or {}
      if value.blocks == Merge.DELETE then
        spec = nil
      elseif value.blocks ~= nil then
        local keep = spec
        spec = reset(value, owner)
        spec.width = value.width or (keep and keep.width) or base.width
        spec.height = value.height or (keep and keep.height) or base.height
        spec.pair = value.pair or (keep and keep.pair) or base.pair
        if keep and value.border == nil then
          spec.border, spec.borderWidth, spec.borderHeight = keep.border, keep.borderWidth, keep.borderHeight
          spec.borderOwner = keep.borderOwner
        end
      end
      if value.border ~= nil or value.borderWidth ~= nil or value.borderHeight ~= nil then
        spec = spec or { cells = {}, owner = owner }
        spec.borderOwner = owner
        if value.border ~= nil then spec.border = copy(value.border) end
        spec.borderWidth = value.borderWidth or spec.borderWidth
        spec.borderHeight = value.borderHeight or spec.borderHeight
      end
      if value.cells ~= nil then
        spec = spec or { cells = {}, owner = owner }
        addCells(spec, value.cells, owner)
      end
    end
  end
  return spec
end

function ModLayout.validate(id, spec, value, old, problems)
  local owner = spec.owner
  local function fail(who, fmt, ...)
    who = who or owner
    problems[#problems + 1] = { owner = who,
      text = ("%s: maps.%s%s"):format(tostring(who), id, fmt:format(...)) }
  end
  local before = #problems
  local base = old or value
  local pair = spec.pair or base.pair
  local behaviors = ModLayout.behaviors(pair)
  if not behaviors then
    fail(owner, ': unknown tileset pair "%s"', tostring(pair))
    return false
  end
  local w, h
  if spec.blocks then
    w, h = spec.width, spec.height
    if type(w) ~= "number" or type(h) ~= "number" or #spec.blocks ~= w * h then
      fail(owner, ": blocks has %d entries, expected width*height = %s", #spec.blocks,
        tostring((tonumber(w) or 0) * (tonumber(h) or 0)))
      return false
    end
    for n, entry in ipairs(spec.blocks) do
      local mid = ModLayout.word(entry)
      if behaviors[mid] == nil then
        fail(owner, ".blocks[%d]: metatile %d is not defined by tileset pair %s", n, mid, pair)
      end
    end
  else
    w, h = base.width, base.height
  end
  for _, c in ipairs(spec.cells) do
    if c.x >= (w or 0) or c.y >= (h or 0) then
      fail(c.owner, ".cells[%d]: (%d,%d) is outside the %sx%s grid", c.index, c.x, c.y, tostring(w), tostring(h))
    elseif behaviors[c.metatile] == nil then
      fail(c.owner, ".cells[%d]: metatile %d is not defined by tileset pair %s", c.index, c.metatile, pair)
    end
  end
  local borderOwner = spec.borderOwner or owner
  if spec.border then
    local prior = spec.baseBorder
    local bw = spec.borderWidth or (prior and prior.width) or (not spec.blocks and base.borderWidth)
      or (rse() and 2 or 1)
    local bh = spec.borderHeight or (prior and prior.height) or (not spec.blocks and base.borderHeight)
      or (rse() and 2 or 1)
    if rse() and (bw ~= 2 or bh ~= 2) then
      fail(borderOwner, ".border: border is 2x2 on %s", Profile.active().label or Profile.active().id)
    elseif #spec.border ~= bw * bh then
      fail(borderOwner, ".border: %d entries, expected borderWidth*borderHeight = %d", #spec.border, bw * bh)
    end
    for n, mid in ipairs(spec.border) do
      if behaviors[mid] == nil then
        fail(borderOwner, ".border[%d]: metatile %d is not defined by tileset pair %s", n, mid, pair)
      end
    end
  elseif spec.borderWidth or spec.borderHeight then
    fail(borderOwner, ".border: borderWidth and borderHeight need a border list")
  end
  if spec.blocks then
    for n, warp in ipairs(value.warps or {}) do
      local x, y = tonumber(warp.x), tonumber(warp.y)
      if not (x and y) or x < 0 or y < 0 or x >= w or y >= h then
        fail(owner, ".warps[%d]: (%s,%s) is outside the %dx%d grid", n, tostring(warp.x), tostring(warp.y), w, h)
      end
    end
  end
  return #problems == before
end

local function replaces(ops)
  for _, entry in ipairs(ops or {}) do
    if entry.op == "register" or entry.op == "override" then return true end
  end
  return false
end

local function touched(ops)
  local keys = {}
  for _, entry in ipairs(ops or {}) do
    if entry.op == "patch" and type(entry.value) == "table" then
      for key in pairs(entry.value) do
        if not LAYOUT_KEYS[key] then keys[key] = true end
      end
    end
  end
  return keys
end

local CARRIED = { "bgEvents", "coordEvents", "mapScripts", "music" }

local function carriesLayout(value)
  if type(value) ~= "table" or value == Merge.DELETE then return false end
  for key in pairs(LAYOUT_KEYS) do
    if value[key] ~= nil then return true end
  end
  return false
end

local function without(ops, dropped)
  if next(dropped) == nil then return ops end
  local out = {}
  for _, entry in ipairs(ops) do
    if not (dropped[entry.owner] and carriesLayout(entry.value)) then out[#out + 1] = entry end
  end
  return out
end

local function valueOf(registry, id, ops)
  if ops == registry.ops[id] then return registry:get(id) end
  local savedOps, savedCache = registry.ops[id], registry.cache[id]
  registry.ops[id], registry.cache[id] = ops, nil
  local ok, value = pcall(registry.get, registry, id)
  registry.ops[id], registry.cache[id] = savedOps, savedCache
  if not ok then error(value, 0) end
  return value
end

local function baseBorder(old)
  local prior = rawget(old, "modLayout")
  if prior and prior.baseBorder then return prior.baseBorder end
  local layout = old.midLayout
  if not (layout and layout.borderMids and layout.borderWidth and layout.borderHeight) then return nil end
  local mids = {}
  for i, mid in ipairs(layout.borderMids) do mids[i] = mid end
  return { width = layout.borderWidth, height = layout.borderHeight, mids = mids }
end

local function prefixProblem(id, spec, found)
  local prefixes = Profile.active().map.prefixes
  for _, prefix in ipairs(prefixes) do
    if id:sub(1, #prefix) == prefix then return end
  end
  found[#found + 1] = { owner = spec.owner,
    text = ("%s: maps.%s: new map ids on %s start with %s"):format(tostring(spec.owner), id,
      Profile.active().label or Profile.active().id, table.concat(prefixes, " or ")) }
end

local function unknownMap(id, ops, problems)
  local named = {}
  for _, entry in ipairs(ops) do
    if not named[entry.owner] then
      named[entry.owner] = true
      problems[#problems + 1] = ("%s: maps.%s: no map %s to patch (register it first)")
        :format(tostring(entry.owner), id, id)
    end
  end
end

local function place(target, id, ops, value, old, spec)
  local Dataset = require("src.core.game3.dataset")
  local def
  if old == nil or replaces(ops) then
    def = Dataset.newMapDef(id, value)
    def.objects = copy(value.objects)
    for key, field in pairs(value) do
      if rawget(def, key) == nil and not LAYOUT_KEYS[key] then def[key] = field end
    end
    if old then
      for _, key in ipairs(CARRIED) do
        if rawget(old, key) ~= nil and value[key] == nil then def[key] = rawget(old, key) end
      end
      if value.objects == nil then def.objects = rawget(old, "objects") end
    end
    target[id] = def
  else
    def = old
    for key in pairs(touched(ops)) do def[key] = copy(value[key]) end
    Dataset.bindUnderwater(def)
  end
  if spec then
    if spec.blocks then
      def.width, def.height, def.pair = spec.width, spec.height, spec.pair
      def.tileset = Versions.PAIR_TILESET and Versions.PAIR_TILESET[spec.pair] or def.tileset
    end
    def.modLayout = spec
    ModLayout.refresh(def, id)
  end
end

function ModLayout.write(target, registry)
  local problems = {}
  local ids = {}
  for id in pairs(registry.ops) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local all = registry.ops[id]
    local old = rawget(target, id)
    if old == nil and not replaces(all) and registry:get(id) ~= nil then
      unknownMap(id, all, problems)
    else
      local dropped = {}
      while true do
        local ops = without(all, dropped)
        local value = valueOf(registry, id, ops)
        if value == nil then
          target[id] = nil
          break
        end
        local spec = ModLayout.fold(ops, old)
        if spec and spec.blocks and old and not replaces(ops) then spec.baseBorder = baseBorder(old) end
        local found = {}
        if old == nil and spec and spec.blocks then prefixProblem(id, spec, found) end
        if spec and #found == 0 then ModLayout.validate(id, spec, value, old, found) end
        if #found == 0 then
          place(target, id, ops, value, old, spec)
          break
        end
        local grew = false
        for _, p in ipairs(found) do
          problems[#problems + 1] = p.text
          if p.owner ~= nil and not dropped[p.owner] then
            dropped[p.owner] = true
            grew = true
          end
        end
        if not grew then break end
      end
    end
  end
  if #problems > 0 then error(table.concat(problems, "; "), 0) end
end

return ModLayout
