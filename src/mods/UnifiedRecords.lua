
local Ids = require("src.mods.UnifiedIds")
local Stats = require("src.pokemon.Stats")
local Records = {}

local STAT_KEYS = { "hp", "attack", "defense", "speed", "special", "specialAttack", "specialDefense" }
local STAT_ALIASES = {
  hp = { "hp", "maxHp", "maxhp" }, attack = { "attack", "atk" },
  defense = { "defense", "def" }, speed = { "speed", "spe" },
  special = { "special" },
  specialAttack = { "specialAttack", "spAtk", "spa" },
  specialDefense = { "specialDefense", "spDef", "spd" },
}
local STATUS = {
  SLP = "sleep", SLEEP = "sleep", PSN = "poison", POISON = "poison",
  BRN = "burn", BURN = "burn", FRZ = "freeze", FREEZE = "freeze",
  PAR = "paralyze", PARALYZE = "paralyze", PARALYSIS = "paralyze",
  TOX = "toxic", TOXIC = "toxic",
}
local SHORT_STATUS = { sleep = "SLP", poison = "PSN", burn = "BRN",
  freeze = "FRZ", paralyze = "PAR", toxic = "TOX" }
local STATUS_BITS = { sleep = 1, poison = 8, burn = 16, freeze = 32,
  paralyze = 64, toxic = 128 }
local FIELDS = { species = true, item = true, name = true, nickname = true, level = true,
  hp = true, maxHp = true, status = true, isEgg = true, stats = true,
  moves = true, native = true, dvs = true, shiny = true }

local function shinyOf(native, generation)
  if native.shiny ~= nil then return native.shiny == true end
  if generation == 3 then
    if native.isShiny ~= nil then return native.isShiny == true end
    local p = (tonumber(native.personality) or 0) % 4294967296
    local full = (tonumber(native.otId or native.trainerId) or 0) % 4294967296
    local tid = full % 65536
    local sid = (tonumber(native.otSecretId) or math.floor(full / 65536)) % 65536
    local value = bit.bxor(bit.bxor(tid, sid), bit.bxor(math.floor(p / 65536), p % 65536))
    return value < 8
  end
  return Stats.isShiny(native.dvs)
end

local function copy(value, seen)
  if type(value) ~= "table" then
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    return nil
  end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do
    if type(k) == "string" or type(k) == "number" then out[k] = copy(v, seen) end
  end
  return out
end

local function shallow(value)
  local out = {}
  for k, v in pairs(value or {}) do out[k] = v end
  return out
end

local function equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function integer(value, low, high)
  return type(value) == "number" and value == value and value % 1 == 0
    and value >= low and value <= high
end

local function idOf(name)
  if type(name) ~= "string" then return nil end
  local s = name:gsub("é", "E"):gsub("É", "E")
    :gsub("♀", "_F"):gsub("♂", "_M"):gsub("'", "")
  s = s:upper():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if s ~= "" then return s end
end

local function tables(kind, generation, data)
  data = data or {}
  local key = kind == "species" and "pokemon" or kind == "move" and "moves" or "items"
  local base = generation == 3 and data["gen3" .. key:sub(1, 1):upper() .. key:sub(2)]
    or data[key]
  base = type(base) == "table" and base or {}
  local pokemon = (generation == 3 and data.gen3Pokemon) or data.pokemon or {}
  if kind == "species" then return base._names or base.names or base, base end
  if kind == "move" then
    return base._moveNames or base.moveNames or base.names
      or pokemon._moveNames or pokemon.moveNames or base._rom or base.moves
      or (base.rom and (base.rom.moves or base.rom)) or base, base
  end
  return base._byId or base.items or base, base
end

local function rowId(key, row)
  if type(key) == "string" and type(row) == "table" then return key end
  if type(row) == "string" then return idOf(row) end
  if type(row) == "table" then
    return type(row.id) == "string" and row.id or idOf(row.name)
  end
end

local function speciesNumber(value, native, base, toNative)
  if native.speciesNumbering ~= "national" then return value end
  local national = base._national or base.national or {}
  local map = toNative and national.toNational or national.toSpecies
  if type(map) == "table" and map[value] then return map[value] end
  if value <= 251 then return value end
  return nil
end

local function registeredId(base, num)
  for id, record in pairs(base.modRecords or {}) do
    if type(id) == "string" and type(record) == "table" and record.index == num then
      return id
    end
  end
end

local function readId(value, kind, generation, data, native)
  if value == nil or value == false or value == 0 or value == "" then return nil end
  if type(value) == "string" and not tonumber(value) then return Ids.canonical(value, kind, generation) end
  local rows, base = tables(kind, generation, data)
  local num = tonumber(value)
  if kind == "species" and generation == 3 and num then
    num = speciesNumber(num, native or {}, base, false)
  end
  local id = (generation == 3 and registeredId(base, num)) or rowId(num, rows[num]) or tostring(value)
  return Ids.canonical(id, kind, generation)
end

local function writeId(id, kind, generation, data, original, native)
  if type(id) ~= "string" or id == "" then error(kind .. " must be a string ID", 0) end
  local reserved = generation == 2 and ({
    species = { growthRates = true, tmhmMoves = true, tutorMoves = true },
    move = { generation = true, source = true },
    item = { generation = true, source = true, pockets = true },
  })[kind]
  if reserved and reserved[id] then error("reserved engine metadata is not a " .. kind .. " ID", 0) end
  local rows, base = tables(kind, generation, data)
  id = Ids.native(id, kind, generation, function(key) return rows[key] ~= nil end)
  local registered = generation == 3 and base.modRecords and base.modRecords[id]
  local found = type(registered) == "table" and registered.index or nil
  if found and rows[found] == nil then found = nil end
  if found == nil then
    if rows[id] ~= nil and type(rows[id]) ~= "function" then found = id end
    for key, row in pairs(rows) do
      if rowId(key, row) == id and (found == nil or type(key) == "number") then
        if found ~= nil and found ~= key and type(found) == "number" then
          error("ambiguous " .. kind .. " ID " .. id, 0)
        end
        found = key
      end
    end
  end
  if found == nil and tonumber(id) and rows[tonumber(id)] ~= nil then found = tonumber(id) end
  if found == nil then error("unknown " .. kind .. " ID " .. id, 0) end
  if generation == 3 and (type(original) ~= "string" or tonumber(original)) then
    if not integer(found, 1, 65535) then error("no numeric " .. kind .. " ID for " .. id, 0) end
    if kind == "species" then
      found = speciesNumber(found, native, base, true)
      if not found then error("species has no native national ID", 0) end
    end
    return type(original) == "string" and tostring(found) or found
  end
  return type(found) == "string" and found or id
end

local function statusOf(value)
  if value == nil or value == false or value == 0 or value == "" then return nil end
  if type(value) == "number" then
    if value % 8 ~= 0 then return "sleep" end
    for _, name in ipairs({ "toxic", "poison", "burn", "freeze", "paralyze" }) do
      if math.floor(value / STATUS_BITS[name]) % 2 == 1 then return name end
    end
    return nil
  end
  return STATUS[tostring(value):upper()] or tostring(value)
end

local function statOf(native, key, generation)
  local stats = type(native.stats) == "table" and native.stats or {}
  if key == "special" and generation ~= 1 then key = "specialAttack" end
  if generation == 1 and (key == "specialAttack" or key == "specialDefense") then
    return stats.special or native.special
  end
  if key == "hp" then return native.maxHp or native.maxhp or stats.hp end
  for _, alias in ipairs(STAT_ALIASES[key]) do
    if stats[alias] ~= nil then return stats[alias] end
    if native[alias] ~= nil then return native[alias] end
  end
end

local function moveDef(id, rawId, generation, data)
  local rows, base = tables("move", generation, data)
  local defs = base._rom or base.moves or (base.rom and (base.rom.moves or base.rom)) or base
  local pokemon = data and ((generation == 3 and data.gen3Pokemon) or data.pokemon) or {}
  local battle = pokemon._battleMoves or pokemon.battleMoves or {}
  local row = defs[rawId] or defs[id] or battle[rawId] or rows[rawId] or rows[id]
  return type(row) == "table" and row or {}
end

local function moveId(move)
  if type(move) ~= "table" then return move end
  return move.id or move.move or move.num or move.moveId or move.name or move[1]
end

local function ppBonus(base, generation)
  local bonus = math.floor(base / 5)
  return generation == 2 and math.min(bonus, 7) or bonus
end

function Records.mon(native, generation, data, version)
  if type(native) ~= "table" then return nil end
  local species = readId(native.species or native.speciesId, "species", generation, data, native)
  local stats, moves = {}, {}
  for _, key in ipairs(STAT_KEYS) do stats[key] = statOf(native, key, generation) end
  for slot = 1, 4 do
    local raw = native.moves and native.moves[slot]
    local rawId = moveId(raw)
    local id = readId(rawId, "move", generation, data)
    if id then
      local row = type(raw) == "table" and raw or {}
      local def = moveDef(id, rawId, generation, data)
      local ups = row.ppUps
      if ups == nil and native.ppBonusesPacked then
        ups = math.floor(native.ppBonusesPacked / 4 ^ (slot - 1)) % 4
      end
      local max = row.maxPp or (native.maxPp and native.maxPp[slot])
      if generation == 2 and def.pp then
        local bonus = ppBonus(def.pp, generation)
        if ups == nil and max and max > def.pp and bonus > 0 and (max - def.pp) % bonus == 0 then
          ups = (max - def.pp) / bonus
        end
        max = def.pp + math.max(0, math.min(3, math.floor(ups or 0))) * bonus
      elseif generation == 1 or max == nil then
        max = def.pp and (def.pp + (ups or 0) * ppBonus(def.pp, generation)) or max
      end
      local pp = row.pp or (native.pp and native.pp[slot]) or max or 0
      moves[slot] = { id = id, pp = pp, maxPp = max or pp, ppUps = ups }
    end
  end
  local rows = tables("species", generation, data)
  local def = rows[species] or rows[native.species or native.speciesId]
  local name = native.nickname
  if not name or name == "" then
    name = native.name or (type(def) == "table" and def.name) or (type(def) == "string" and def) or species
  end
  return { species = species, item = readId(native.item or native.heldItem, "item", generation, data),
    name = name, nickname = native.nickname, level = native.level, hp = native.hp,
    maxHp = stats.hp or native.hp, status = SHORT_STATUS[statusOf(native.status)] or statusOf(native.status),
    isEgg = native.isEgg == true or native.egg == true or (generation == 3 and native.species == 412),
    stats = stats, moves = moves, native = copy(native),
    dvs = generation ~= 3 and type(native.dvs) == "table" and copy(native.dvs) or nil,
    shiny = shinyOf(native, generation) }
end

local function prepare(native, canonical, generation, data, version)
  if type(native) ~= "table" or type(canonical) ~= "table" then error("Pokemon must be tables", 0) end
  if generation ~= 1 and generation ~= 2 and generation ~= 3 then error("unsupported generation", 0) end
  for key in pairs(canonical) do if not FIELDS[key] then error("unknown Pokemon field " .. tostring(key), 0) end end
  local before = Records.mon(native, generation, data, version)
  local pending, touched = {}, {}
  local function put(key, value) pending[key], touched[key] = value, true end
  local function changed(key)
    return canonical[key] ~= nil and not equal(canonical[key], before[key])
  end
  if changed("species") then
    local value = writeId(canonical.species, "species", generation, data,
      native.species or native.speciesId, native)
    put(native.species ~= nil and "species" or "speciesId", value)
    if native.species ~= nil and native.speciesId ~= nil then
      put("speciesId", writeId(canonical.species, "species", generation, data, native.speciesId, native))
    end
  end
  if changed("dvs") or changed("shiny") then error("dvs and shiny are read only", 0) end
  local complete = type(canonical.native) == "table"
  if changed("item") or (complete and canonical.item == nil and before.item ~= nil) then
    local id = canonical.item
    if generation == 1 and id ~= nil and id ~= false then error("held items are unsupported in Gen 1", 0) end
    local key = native.item ~= nil and "item" or native.heldItem ~= nil and "heldItem" or "item"
    local value
    if id ~= nil and id ~= false then value = writeId(id, "item", generation, data, native[key], native)
    elseif type(native[key]) == "number" then value = 0 end
    put(key, value)
    if native.item ~= nil and native.heldItem ~= nil then
      local other = key == "item" and "heldItem" or "item"
      put(other, id and writeId(id, "item", generation, data, native[other], native)
        or (type(native[other]) == "number" and 0 or nil))
    end
  end
  if changed("nickname") or changed("name") then
    if canonical.nickname ~= nil and type(canonical.nickname) ~= "string" then error("nickname must be a string", 0) end
    if canonical.name ~= nil and type(canonical.name) ~= "string" then error("name must be a string", 0) end
    if changed("nickname") and changed("name") and canonical.nickname ~= canonical.name then
      error("nickname and name disagree", 0)
    end
    put("nickname", changed("nickname") and canonical.nickname or canonical.name)
  end
  for _, key in ipairs({ "level", "hp", "maxHp" }) do
    if changed(key) then
      if not integer(canonical[key], key == "hp" and 0 or 1, key == "level" and 100 or 65535) then
        error("invalid " .. key, 0)
      end
      if key ~= "maxHp" then put(key, canonical[key]) end
    end
  end
  local stats = shallow(native.stats)
  local statsChanged = false
  local function putStat(key, value)
    if not integer(value, key == "hp" and 1 or 0, 65535) then error("invalid stat " .. key, 0) end
    local aliases = STAT_ALIASES[key]
    if generation == 1 and (key == "specialAttack" or key == "specialDefense") then aliases = { "special" } end
    local found = false
    for _, alias in ipairs(aliases) do
      if stats[alias] ~= nil then stats[alias], statsChanged, found = value, true, true end
      if alias ~= "hp" and native[alias] ~= nil then put(alias, value) found = true end
    end
    if not found then
      if generation == 3 and native.stats == nil then
        put(key == "hp" and "maxHp" or key == "specialAttack" and "spAtk"
          or key == "specialDefense" and "spDef" or key, value)
      else stats[aliases[1]], statsChanged = value, true end
    end
  end
  if canonical.stats ~= nil then
    if type(canonical.stats) ~= "table" then error("stats must be a table", 0) end
    for key, value in pairs(canonical.stats) do
      if not STAT_ALIASES[key] then error("unknown stat " .. tostring(key), 0) end
      if key ~= "special" and value ~= before.stats[key] then putStat(key, value) end
    end
    local special = canonical.stats.special
    local specialChanged = special ~= nil and special ~= before.stats.special
    if specialChanged then
      for _, key in ipairs({ "specialAttack", "specialDefense" }) do
        local value = canonical.stats[key]
        if value ~= nil and value ~= before.stats[key] and value ~= special then
          error("special and " .. key .. " disagree", 0)
        end
        putStat(key, special)
      end
    end
    if generation == 1 then
      local a = specialChanged and special or canonical.stats.specialAttack or before.stats.specialAttack
      local b = specialChanged and special or canonical.stats.specialDefense or before.stats.specialDefense
      if a ~= b then error("Gen 1 cannot split Special", 0) end
    end
  end
  if changed("maxHp") then
    if canonical.stats and canonical.stats.hp ~= nil and canonical.stats.hp ~= before.stats.hp
      and canonical.stats.hp ~= canonical.maxHp then error("maxHp and stats.hp disagree", 0) end
    putStat("hp", canonical.maxHp)
  end
  if statsChanged then put("stats", stats) end
  local maxHp = pending.maxHp or pending.maxhp or (pending.stats and pending.stats.hp) or before.maxHp
  if (touched.hp or changed("maxHp") or (pending.stats and pending.stats.hp ~= before.stats.hp))
    and (pending.hp or native.hp or 0) > (maxHp or 65535) then error("hp exceeds maxHp", 0) end
  local status = canonical.status
  if type(status) == "string" then status = statusOf(status) end
  if status == false then status = nil end
  local previousStatus = statusOf(before.status)
  if (canonical.status ~= nil and status ~= previousStatus)
    or (complete and canonical.status == nil and previousStatus ~= nil) then
    local value = status
    if value ~= nil and not SHORT_STATUS[value] then
      local statuses = data and (generation == 2 and data.gen2Statuses or data.statuses) or {}
      if type(value) ~= "string" or not statuses[value] or generation == 3 then error("unknown status", 0) end
    end
    if generation == 1 and value == "toxic" then error("Gen 1 Toxic is a battler condition, not a Pokemon status", 0) end
    if (generation == 3 or type(native.status) == "number") and value and not STATUS_BITS[value] then
      error("status has no native bit value", 0)
    end
    if generation == 3 or type(native.status) == "number" then put("status", value and STATUS_BITS[value] or 0)
    else put("status", value and (generation == 2 and value or SHORT_STATUS[value] or value) or nil) end
    if previousStatus == "sleep" and value ~= "sleep" then
      if native.sleepTurns ~= nil then put("sleepTurns", nil) end
      if native.sleep ~= nil then put("sleep", nil) end
    end
    if previousStatus == "toxic" and value ~= "toxic" and native.toxicCounter ~= nil then put("toxicCounter", nil) end
  end
  if changed("isEgg") then
    if type(canonical.isEgg) ~= "boolean" then error("isEgg must be boolean", 0) end
    if generation == 1 then error("eggs are unsupported in Gen 1", 0) end
    if native.species == 412 and not canonical.isEgg then error("egg needs a real species before hatching", 0) end
    put(native.egg ~= nil and "egg" or "isEgg", canonical.isEgg)
    if native.egg ~= nil and native.isEgg ~= nil then put("isEgg", canonical.isEgg) end
  end
  if changed("moves") then
    if type(canonical.moves) ~= "table" then error("moves must be a list", 0) end
    local count = 0
    for key in pairs(canonical.moves) do
      if not integer(key, 1, 4) then error("invalid move slot", 0) end
      count = count + 1
    end
    local moves, pp, maxPp = {}, shallow(native.pp), shallow(native.maxPp)
    local packed = native.ppBonusesPacked
    for slot = 1, count do
      local row, old = canonical.moves[slot], native.moves and native.moves[slot]
      if type(row) ~= "table" then error("moves must be a contiguous list", 0) end
      for key in pairs(row) do
        if key ~= "id" and key ~= "pp" and key ~= "maxPp" and key ~= "ppUps" then error("unknown move field", 0) end
      end
      local oldId = moveId(old)
      local id = before.moves[slot] and row.id == before.moves[slot].id and oldId
        or writeId(row.id, "move", generation, data, oldId, native)
      local def = moveDef(row.id, id, generation, data)
      local prior = before.moves[slot]
      local max = row.maxPp or (prior and prior.maxPp) or def.pp
      if row.ppUps ~= nil and not integer(row.ppUps, 0, 3) then error("invalid PP Ups", 0) end
      local upsChanged = row.ppUps ~= nil and (not prior or row.ppUps ~= prior.ppUps)
      if upsChanged then
        if not def.pp then error("move data is required to change PP Ups", 0) end
        local adjusted = def.pp + row.ppUps * ppBonus(def.pp, generation)
        if row.maxPp ~= nil and (not prior or row.maxPp ~= prior.maxPp) and row.maxPp ~= adjusted then
          error("maxPp and ppUps disagree", 0)
        end
        max = adjusted
      end
      if not integer(max, 0, 255) or not integer(row.pp, 0, max) then error("invalid move PP", 0) end
      if type(old) == "table" or (old == nil and generation ~= 3) then
        local converted = shallow(type(old) == "table" and old or nil)
        local key = converted.id ~= nil and "id" or converted.move ~= nil and "move"
          or converted.num ~= nil and "num" or converted.moveId ~= nil and "moveId"
          or converted.name ~= nil and "name" or converted[1] ~= nil and 1 or "id"
        converted[key], converted.pp = id, row.pp
        if not prior or row.id ~= prior.id or max ~= prior.maxPp or upsChanged then
          local bonus = def.pp and ppBonus(def.pp, generation) or 0
          if def.pp then
            local ups = upsChanged and row.ppUps or max == def.pp and 0 or bonus > 0 and (max - def.pp) / bonus or -1
            if not integer(ups, 0, 3) then error("maxPp cannot be represented by PP Ups", 0) end
            converted.ppUps = ups
            if generation == 3 and packed ~= nil then
              local shift = 4 ^ (slot - 1)
              local oldUps = math.floor(packed / shift) % 4
              packed = packed + (ups - oldUps) * shift
            end
          elseif not prior or max ~= prior.maxPp then
            error("move data is required to change maxPp", 0)
          end
        end
        if generation ~= 1 or converted.maxPp ~= nil then converted.maxPp = max end
        moves[slot] = converted
        if native.pp ~= nil then pp[slot] = row.pp end
        if native.maxPp ~= nil then maxPp[slot] = max end
      else
        moves[slot], pp[slot], maxPp[slot] = id, row.pp, max
        if generation == 3 and (not prior or row.id ~= prior.id or max ~= prior.maxPp or upsChanged) then
          if def.pp then
            local bonus = ppBonus(def.pp, generation)
            local ups = upsChanged and row.ppUps or bonus > 0 and (max - def.pp) / bonus or -1
            if max == def.pp and not upsChanged then ups = 0 end
            if not integer(ups, 0, 3) then error("maxPp cannot be represented by PP Ups", 0) end
            local shift = 4 ^ (slot - 1)
            local oldUps = math.floor((packed or 0) / shift) % 4
            packed = (packed or 0) + (ups - oldUps) * shift
          elseif not prior or max ~= prior.maxPp then error("move data is required to change maxPp", 0)
          end
        end
      end
    end
    for slot = count + 1, 4 do pp[slot], maxPp[slot] = nil, nil end
    put("moves", moves)
    if native.pp ~= nil or generation == 3 then put("pp", pp) end
    if native.maxPp ~= nil or generation == 3 then put("maxPp", maxPp) end
    if packed ~= native.ppBonusesPacked then put("ppBonusesPacked", packed) end
  end
  return pending, touched
end

function Records.applyMon(native, canonical, generation, data, version)
  local ok, pending, touched = pcall(prepare, native, canonical, generation, data, version)
  if not ok then return nil, tostring(pending) end
  for key in pairs(touched) do native[key] = pending[key] end
  return true
end

function Records.id(value, kind, generation, data, native)
  return readId(value, kind, generation, data, native)
end

function Records.nativeId(value, kind, generation, data, original, native)
  local ok, result = pcall(writeId, value, kind, generation, data, original, native or {})
  if not ok then return nil, tostring(result) end
  return result
end

return Records
