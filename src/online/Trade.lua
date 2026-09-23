local GameVersion = require("src.core.GameVersion")
local Protocol = require("src.link.Protocol")
local SaveData = require("src.core.SaveData")
local TeamPick = require("src.online.TeamPick")

local Trade = {}

Trade.GEN3_LOCAL_ONLY =
  "FireRed and LeafGreen can only trade on this device for now."

local function disk()
  return SaveData.persistenceFs()
end

local function scopeKey(version, cartId)
  if cartId then return "cart_" .. cartId end
  return version
end

function Trade.slotPath(version, slotId, cartId)
  return "saves/" .. scopeKey(version, cartId) .. "/" .. slotId .. ".lua"
end

Trade.mountDepth = 0

function Trade.mounted()
  return (Trade.mountDepth or 0) > 0
end

Trade.hostIsLive = nil

function Trade.gameIsLive()
  if type(Trade.hostIsLive) == "function" then
    return Trade.hostIsLive() == true
  end
  if Trade.mounted() then return false end
  local Data = package.loaded["src.core.Data"]
  return Data ~= nil and Data._pristineKeys ~= nil
end

local function deepCopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do out[deepCopy(k, seen)] = deepCopy(v, seen) end
  return out
end

-- ------- dataset mounting (no Game)

local function gen2Dataset()
  local CacheFs = require("src.import.CacheFs")
  local data = {}
  local function load(name)
    return CacheFs.loadActive("data/generated/" .. name .. ".lua")
  end
  data.pokemon = load("pokemon") or {}
  data.items = load("items") or {}
  data.moves = load("moves") or {}
  data.type_chart = load("type_chart") or {}
  data.gen2Constants = load("constants")
  local ItemEffects = require("src.core.gen2.ItemEffects")
  data.gen2HeldItems = ItemEffects.heldItemsFrom(data.items)
  return data
end

local function gen3Dataset(version)
  local Pokemon = require("src.core.game3.pokemon")
  local ItemsData = require("src.core.game3.items_data")
  Pokemon.install(nil)
  if not Pokemon._names then
    error(("%s is not imported"):format(tostring(version)), 0)
  end
  ItemsData.install(nil)
  return { generation = 3, version = version, Pokemon = Pokemon,
           ItemsData = ItemsData }
end

local function gen3Snapshot()
  local ItemsData = require("src.core.game3.items_data")
  local was = { pack = ItemsData._pack, byId = ItemsData._byId,
                byName = ItemsData._byName }
  return function()
    require("src.core.game3.pokemon").invalidate()
    ItemsData._pack, ItemsData._byId, ItemsData._byName =
      was.pack, was.byId, was.byName
  end
end

local function mountDataset(version)
  local CacheFs = require("src.import.CacheFs")
  local generation = GameVersion.generation(version)
  local prevVersion, prevPrefix = GameVersion.get(), CacheFs.prefix
  local released = false
  local restore3 = generation == 3 and gen3Snapshot() or nil
  Trade.mountDepth = (Trade.mountDepth or 0) + 1
  local function release()
    if released then return end
    released = true
    Trade.mountDepth = math.max(0, (Trade.mountDepth or 1) - 1)
    if restore3 then
      pcall(restore3)
    elseif generation ~= 2 then
      pcall(function() require("src.core.Data"):unloadGenerated() end)
    end
    pcall(CacheFs.unmountVersion, version)
    GameVersion.set(prevVersion)
    CacheFs.prefix = prevPrefix
  end
  local ok, data = pcall(function()
    GameVersion.set(version)
    CacheFs.prefix = GameVersion.cachePrefix(version)
    CacheFs.mountVersion(version)
    local probe = generation == 3 and "data/generated/gba/pokemon/names.lua"
      or "data/generated/pokemon.lua"
    if not CacheFs.readActive(probe) then
      error(("%s is not imported"):format(tostring(version)), 0)
    end
    if generation == 3 then return gen3Dataset(version) end
    if generation == 2 then return gen2Dataset() end
    local Data = require("src.core.Data")
    Data:load()
    return Data
  end)
  if not ok then
    release()
    return nil, tostring(data)
  end
  return data, release
end

function Trade.withDataset(version, fn)
  local data, release = mountDataset(version)
  if not data then return nil, release end
  local ok, result = pcall(fn, data)
  release()
  if not ok then return nil, tostring(result) end
  return result
end

function Trade.withMountedData(data, fn)
  Trade.mountDepth = (Trade.mountDepth or 0) + 1
  local ok, result = pcall(fn, data)
  Trade.mountDepth = math.max(0, (Trade.mountDepth or 1) - 1)
  if not ok then return nil, tostring(result) end
  return result
end

local function withData(handle, fn)
  if handle.data then
    local ok, result = pcall(fn, handle.data)
    if not ok then return nil, tostring(result) end
    return result
  end
  if Trade.gameIsLive() then return nil, "close the game first" end
  return Trade.withDataset(handle.version, fn)
end

-- ------- handles

function Trade.openSlot(version, slotId, cartId, opts)
  opts = type(opts) == "table" and opts or {}
  if Trade.gameIsLive() then return nil, "close the game first" end
  local slot, reason = TeamPick.readSlot(version, slotId, cartId)
  if not slot then return nil, reason end
  local save = slot.save
  return {
    version = version,
    generation = slot.generation,
    slotId = slotId,
    cartId = cartId,
    save = save,
    path = Trade.slotPath(version, slotId, cartId),
    party = slot.party,
    boxes = type(save.boxes) == "table" and save.boxes or nil,
    trainerName = slot.trainerName,
    data = opts.data,
  }
end

local function refOf(index)
  local where, box, at = "party", nil, index
  if type(index) == "table" then
    at = index.index
    if index.where == "box" then
      where = "box"
      box = tonumber(index.box)
      if not box or box < 1 or box ~= math.floor(box) then return nil end
    end
  end
  at = tonumber(at)
  if not at or at < 1 or at ~= math.floor(at) then return nil end
  return { where = where, box = box, index = at }
end

Trade.refOf = refOf

-- engine/link/link.asm:810
function Trade.holdsMail(handle, index)
  if type(handle) ~= "table" or handle.generation ~= 2 then return false end
  local ref = refOf(index)
  if not ref or ref.where == "box" then return false end
  local mon = (handle.party or {})[ref.index]
  local Mail = require("src.core.gen2.Mail")
  if Mail.monHoldsMail(mon) then return true end
  local state = type(handle.save) == "table" and handle.save.mail or nil
  local party = type(state) == "table" and state.party or nil
  return type(party) == "table" and party[ref.index] ~= nil
end

local function pickable(handle, index)
  if type(handle) ~= "table" or type(handle.party) ~= "table" then
    return nil, "that save can't be read"
  end
  local ref = refOf(index)
  if not ref then
    return nil, (type(index) == "table" and index.where == "box")
      and "that's not in the PC" or "that's not in the party"
  end
  -- pokefirered/src/trade.c:945
  if handle.generation == 3 and ref.where == "box" then
    return nil, "that's not in the party"
  end
  local mon = TeamPick.monAt(handle, ref)
  if type(mon) ~= "table" then
    return nil, (ref.where == "box") and "that's not in the PC"
      or "that's not in the party"
  end
  if mon.isEgg and handle.generation ~= 3 then
    return nil, "an EGG can't be traded"
  end
  if Trade.holdsMail(handle, ref) then return nil, "take the MAIL first" end
  return mon, nil, ref
end

-- ------- rebuild, evolve, dex

local function packFor(generation, mon)
  if generation == 2 then return Protocol.packMon2(mon) end
  return Protocol.packMon(mon)
end

local function packPartyFor(generation, party, indices)
  if generation ~= 2 then return Protocol.packParty(party, indices) end
  if Protocol.packParty2 then return Protocol.packParty2(party, indices) end
  local mons = {}
  if indices then
    for _, i in ipairs(indices) do
      mons[#mons + 1] = Protocol.packMon2(party[i])
    end
    return mons
  end
  for _, mon in ipairs(party) do mons[#mons + 1] = Protocol.packMon2(mon) end
  return mons
end

-- engine/pokemon/evos_moves.asm
local function evolveGen1(data, record)
  local def = data.pokemon and data.pokemon[record.species]
  local into
  for _, evo in ipairs((def and def.evolutions) or {}) do
    if evo.method == "TRADE" then
      into = evo.species
      break
    end
  end
  local newDef = into and data.pokemon and data.pokemon[into]
  if not newDef then return nil end
  local Stats = require("src.pokemon.Stats")
  local evolved = deepCopy(record)
  local previousMax = (record.stats and record.stats.hp) or record.hp or 0
  local lost = previousMax - (record.hp or previousMax)
  evolved.species = into
  evolved.stats = Stats.calc(newDef, evolved.level, evolved.dvs, evolved.statExp)
  evolved.hp = math.max(1, evolved.stats.hp - lost)
  if evolved.nickname and evolved.nickname == (def.name or record.species) then
    evolved.nickname = nil
  end
  return into, evolved, false
end

-- engine/pokemon/evolve.asm
local function evolveGen2(data, record)
  local Evolution = require("src.core.gen2.Evolution")
  local entry, consumes = Evolution.checkMon(data, record, { link = true })
  if not entry then return nil end
  local evolved = Evolution.apply(data, record, entry)
  if not evolved then return nil end
  return entry.into, evolved, consumes == true
end

local function markDex(save, generation, species)
  local dex = save.pokedex
  if type(dex) ~= "table" then
    dex = {}
    save.pokedex = dex
  end
  local ownedKey = generation == 2 and "caught" or "owned"
  if type(dex.seen) ~= "table" then dex.seen = {} end
  if type(dex[ownedKey]) ~= "table" then dex[ownedKey] = {} end
  for _, id in ipairs(species) do
    dex.seen[id] = true
    dex[ownedKey][id] = true
  end
end

local function sideFor(handle, ref, packed, record, warnings)
  return withData(handle, function(data)
    local built, why = record, nil
    if not built then
      local unpacker = handle.generation == 2
        and Protocol.unpackMon2 or Protocol.unpackMon
      built, why = unpacker(data, packed, { strict = true })
      if not built then return { error = why or "unknown POKéMON" } end
    end
    -- engine/battle/experience.asm:69
    built.traded = true
    local into, evolved, consumed
    if handle.generation == 2 then
      into, evolved, consumed = evolveGen2(data, built)
    else
      into, evolved, consumed = evolveGen1(data, built)
    end
    local species = { built.species }
    if into then species[#species + 1] = into end
    if into then
      warnings[#warnings + 1] =
        { code = "evolve", slot = handle.slotId, species = into }
    end
    if consumed then
      warnings[#warnings + 1] =
        { code = "item_used", slot = handle.slotId, item = built.item }
    end
    return {
      handle = handle,
      ref = ref,
      index = ref.index,
      received = built,
      record = evolved or built,
      evolveTo = into,
      dex = species,
      sent = TeamPick.monAt(handle, ref),
    }
  end)
end

-- pokefirered/include/constants/global.h:11
local VERSION_FIRE_RED, VERSION_LEAF_GREEN = 4, 5

local ONLY_MON3 = "that's your only POKéMON for battle"

-- pokefirered/src/trade.c:546
local function refusalText3(NTrade, code)
  if code == NTrade.CANT_TRADE_LAST_MON then return ONLY_MON3 end
  if code == NTrade.CANT_TRADE_EGG_YET
      or code == NTrade.CANT_TRADE_PARTNER_EGG_YET then
    return "an EGG can't be traded now"
  end
  return "that POKéMON can't be traded now"
end

local function nationalProxy(save)
  return {
    dex = save.dex,
    national_dex_unlocked = save.national_dex_unlocked,
    store = { flags = type(save.flags) == "table" and save.flags or {},
              vars = type(save.vars) == "table" and save.vars or {} },
  }
end

local function national3(save)
  local PokedexData = require("src.core.game3.pokedex_data")
  local proxy = nationalProxy(save)
  return PokedexData.isNationalUnlocked(proxy, proxy.dex) == true
end

local function isEgg3(mon)
  return require("src.core.game3.pokemon").isEgg(mon) == true
end

-- pokefirered/src/trade.c:2745
local function refusal3(handle, ref, partner)
  local NTrade = require("src.core.game3.scripting.natives_trade")
  local party = handle.party or {}
  local code = NTrade.canTradeSelectedMon(party, ref.index - 1, {
    partyCount = #party,
    nationalDex = national3(handle.save),
    partner = {
      version = partner.version == "leafgreen" and VERSION_LEAF_GREEN
        or VERSION_FIRE_RED,
      progressFlags = national3(partner.save) and 1 or 0,
    },
  })
  if code ~= NTrade.CAN_TRADE_MON then return refusalText3(NTrade, code) end
  -- pokefirered/src/trade.c:1951
  for i, mon in ipairs(party) do
    if i ~= ref.index and not isEgg3(mon) and (tonumber(mon.hp) or 0) > 0 then
      return nil
    end
  end
  return ONLY_MON3
end

local function mailOf3(save, mon)
  local Mail = require("src.core.game3.mail")
  local id = tonumber(mon and mon.mail)
  if not id or id == Mail.MAIL_NONE then return nil end
  local record = Mail.get({ mail = deepCopy(save.mail) }, id)
  return record and Mail.copy(record) or nil
end

local function itemName3(item)
  local ok, info = pcall(require("src.core.game3.items_data").info, item)
  return ok and type(info) == "table" and info.name or tostring(item)
end

local function questLogEvent3(save, key, args)
  local Q = require("src.core.game3.quest_log")
  save.questLog = Q.restore(save.questLog)
  local final = save.questLog.final
  local frame = type(final) == "table" and type(final.frames) == "table" and final.frames[1]
    or { x = (tonumber(save.x) or 0) * 16, y = (tonumber(save.y) or 0) * 16, actors = {} }
  save._questNewScene = true
  Q.record(save, key, args, frame)
  save._questNewScene = nil
  if type(final) == "table" and final.map == save.map then Q.addTiles(save, final.tiles) end
end

-- pokefirered/src/trade_scene.c:1054
local function sideFor3(handle, ref, incoming, partnerMail, warnings, partnerName)
  return withData(handle, function(data)
    local NTrade = require("src.core.game3.scripting.natives_trade")
    local Evolution = require("src.core.game3.evolution")
    local Pokemon = data.Pokemon or require("src.core.game3.pokemon")
    local save = deepCopy(handle.save)
    save.party = type(save.party) == "table" and save.party or {}
    local sent = TeamPick.monAt(handle, ref)
    local received = deepCopy(incoming)
    NTrade.clearPartnerMail()
    if partnerMail then
      local Mail = require("src.core.game3.mail")
      local id = tonumber(received.mail)
      if not id or id == Mail.MAIL_NONE then id = 0 end
      received.mail = id
      NTrade.setPartnerMail(id, partnerMail)
    else
      received.mail = nil
    end
    local dexBefore = deepCopy(save.dex)
    local swapped = NTrade.tradeMons(save, ref.index - 1, received)
    NTrade.clearPartnerMail()
    if not swapped then return { error = "that's not in the party" } end
    -- pokefirered/src/trade_scene.c:2599
    local qlKey, qlArgs = NTrade.noteLinkTrade(save, sent, incoming, partnerName, false)
    if qlKey then questLogEvent3(save, qlKey, qlArgs) end
    local egg = isEgg3(received)
    -- pokefirered/src/trade_scene.c:1036
    if egg then save.dex = dexBefore end
    local shown = deepCopy(received)
    local record = save.party[ref.index]
    local species = { tonumber(record.species) }
    local into, consumed = nil, nil
    if not egg then
      -- pokefirered/src/trade_scene.c:2311
      local held = tonumber(record.item or record.heldItem) or 0
      into = Evolution.tradeTarget(record, nationalProxy(save))
      if into then
        consumed = held ~= 0 and (tonumber(record.item) or 0) == 0 and held or nil
        Evolution.apply(record, into, save, save.bag, "trade")
        species[#species + 1] = into
        warnings[#warnings + 1] = { code = "evolve", slot = handle.slotId,
          species = into, name = Pokemon.name(into) }
      end
      if consumed then
        warnings[#warnings + 1] = { code = "item_used", slot = handle.slotId,
          item = consumed, itemName = itemName3(consumed) }
      end
    end
    return {
      handle = handle,
      ref = ref,
      index = ref.index,
      received = shown,
      record = record,
      evolveTo = into,
      fromName = Pokemon.name(tonumber(shown.species)),
      evolveName = into and Pokemon.name(into) or nil,
      dex = species,
      sent = sent,
      save3 = save,
    }
  end)
end

local function plan3(from, to, refA, refB, monA, monB)
  local why = refusal3(from, refA, to) or refusal3(to, refB, from)
  if why then return nil, why end
  local mailA, mailB = mailOf3(from.save, monA), mailOf3(to.save, monB)
  local warnings = {}
  local sideB, whyB = sideFor3(to, refB, monA, mailA, warnings, from.save and from.save.name)
  if not sideB then return nil, tostring(whyB) end
  if sideB.error then return nil, sideB.error end
  local sideA, whyA = sideFor3(from, refA, monB, mailB, warnings, to.save and to.save.name)
  if not sideA then return nil, tostring(whyA) end
  if sideA.error then return nil, sideA.error end
  sideA.role, sideB.role = "a", "b"
  return { sides = { sideA, sideB }, warnings = warnings,
           get = sideA.record, give = sideB.record,
           evolveA = sideA.evolveTo, evolveB = sideB.evolveTo }
end

-- ------- plan

local function planFrom(sides, warnings)
  local plan = { sides = sides, warnings = warnings }
  for _, side in ipairs(sides) do
    if side.role == "a" then
      plan.get = side.record
      plan.evolveA = side.evolveTo
      plan.give = plan.give or side.sent
    elseif side.role == "b" then
      plan.give = side.record
      plan.evolveB = side.evolveTo
    end
  end
  return plan
end

function Trade.plan(req)
  req = type(req) == "table" and req or {}
  local from, to = req.from, req.to
  if type(from) ~= "table" or type(to) ~= "table" then
    return nil, "two saves are needed"
  end
  if from.path == to.path then return nil, "that's the same save" end
  local monA, reasonA, refA = pickable(from, req.fromIndex)
  if not monA then return nil, reasonA end
  local monB, reasonB, refB = pickable(to, req.toIndex)
  if not monB then return nil, reasonB end
  if from.generation == 3 or to.generation == 3 then
    if from.generation ~= to.generation then
      return nil, "Those two games can't trade."
    end
    return plan3(from, to, refA, refB, monA, monB)
  end

  local packA = packFor(from.generation, monA)
  local packB = packFor(to.generation, monB)
  if from.generation ~= to.generation then
    if type(req.convert) ~= "function" then return nil, "needs_conversion" end
    local intoB, whyB = req.convert(packA, from.generation, to.generation)
    if not intoB then return nil, tostring(whyB or "needs_conversion") end
    local intoA, whyA = req.convert(packB, to.generation, from.generation)
    if not intoA then return nil, tostring(whyA or "needs_conversion") end
    packA, packB = intoB, intoA
  end

  local warnings = {}
  local sideB, whyB = sideFor(to, refB, packA, nil, warnings)
  if not sideB then return nil, tostring(whyB) end
  if sideB.error then return nil, sideB.error end
  local sideA, whyA = sideFor(from, refA, packB, nil, warnings)
  if not sideA then return nil, tostring(whyA) end
  if sideA.error then return nil, sideA.error end
  sideA.role, sideB.role = "a", "b"
  return planFrom({ sideA, sideB }, warnings)
end

function Trade.planIncoming(req)
  req = type(req) == "table" and req or {}
  local to = req.to
  if type(to) ~= "table" then return nil, "no save" end
  if to.generation == 3 then return nil, Trade.GEN3_LOCAL_ONLY end
  local mon, reason, ref = pickable(to, req.toIndex)
  if not mon then return nil, reason end
  local warnings = {}
  local side, why = sideFor(to, ref, req.mon, req.record, warnings)
  if not side then return nil, tostring(why) end
  if side.error then return nil, side.error end
  side.role = "a"
  return planFrom({ side }, warnings)
end

-- ------- commit

local function validateSave(save, generation, data)
  if generation == 3 then
    local Schema = require("src.core.game3.save_schema_firered")
    local ok = pcall(Schema.fromSaveTable, deepCopy(save))
    if not ok then return false, "that save didn't validate" end
    return true
  end
  if generation == 2 then
    local Save2 = require("src.core.gen2.Save")
    local report = Save2.validate(save)
    if not Save2.emptyReport(report) then return false, "that save didn't validate" end
    return true
  end
  local report = SaveData.validate(save, data)
  if not SaveData.emptyReport(report) then return false, "that save didn't validate" end
  return true
end

local function buildSave(side)
  local handle = side.handle
  if handle.generation == 3 then return deepCopy(side.save3) end
  local save = deepCopy(handle.save)
  local ref = side.ref or { where = "party", index = side.index }
  if ref.where == "box" then
    if type(save.boxes) ~= "table" then save.boxes = {} end
    if type(save.boxes[ref.box]) ~= "table" then save.boxes[ref.box] = {} end
    save.boxes[ref.box][ref.index] = side.record
  else
    if type(save.party) ~= "table" then save.party = {} end
    save.party[ref.index] = side.record
  end
  markDex(save, handle.generation, side.dex)
  if handle.generation == 2 then
    local state = ref.where ~= "box" and type(save.mail) == "table"
      and save.mail or nil
    if state and type(state.party) == "table" then
      state.party[ref.index] = nil
    end
  elseif handle.version == "yellow" and side.sent then
    -- engine/link/cable_club.asm:801
    local previous = GameVersion.get()
    GameVersion.set("yellow")
    pcall(function()
      require("src.world.PikachuFollower")
        .modifyHappiness(save, "TRADE", side.sent)
    end)
    GameVersion.set(previous)
  end
  return save
end

function Trade.commit(plan)
  if type(plan) ~= "table" or type(plan.sides) ~= "table"
      or #plan.sides == 0 then
    return false, "no trade to make"
  end
  if Trade.gameIsLive() then return false, "close the game first" end

  local jobs = {}
  for _, side in ipairs(plan.sides) do
    local built, why = withData(side.handle, function(data)
      local save = buildSave(side)
      local encoded = SaveData.encode(save)
      local decoded = SaveData.decode(encoded)
      if type(decoded) ~= "table" then
        return { error = "that save didn't encode" }
      end
      local ok, reason = validateSave(decoded, side.handle.generation, data)
      if not ok then return { error = reason } end
      return { save = save, encoded = encoded }
    end)
    if not built then return false, tostring(why) end
    if built.error then return false, built.error end
    jobs[#jobs + 1] = { side = side, path = side.handle.path,
                        save = built.save, encoded = built.encoded }
  end

  local fs = disk()
  if not fs then return false, "no filesystem" end
  local stamp = tostring(os.time())
  local backups = {}
  for _, job in ipairs(jobs) do
    job.prevMain = fs.getInfo(job.path) and fs.read(job.path) or nil
    job.prevBak = fs.getInfo(job.path .. ".bak") and fs.read(job.path .. ".bak")
      or nil
    job.backup = job.path .. ".trade-bak-" .. stamp
    if job.prevMain then
      local ok = fs.write(job.backup, job.prevMain)
      if not ok then return false, "couldn't back that save up" end
      backups[#backups + 1] = job.backup
    end
  end

  local function restore()
    for _, job in ipairs(jobs) do
      if job.prevMain then
        fs.write(job.path, job.prevMain)
      elseif fs.remove then
        fs.remove(job.path)
      end
      if job.prevBak then
        fs.write(job.path .. ".bak", job.prevBak)
      elseif fs.remove then
        fs.remove(job.path .. ".bak")
      end
      if fs.remove then fs.remove(job.path .. ".tmp") end
    end
  end

  for _, job in ipairs(jobs) do
    local dir = job.path:match("^(.*)/[^/]+$")
    if dir and fs.createDirectory then fs.createDirectory(dir) end
    local ok, err = fs.write(job.path .. ".tmp", job.encoded)
    if not ok then
      restore()
      return false, tostring(err or "couldn't write that save")
    end
    local body = fs.read(job.path .. ".tmp")
    if body ~= job.encoded or type(SaveData.decode(body or "")) ~= "table" then
      restore()
      return false, "that save didn't write"
    end
  end

  for _, job in ipairs(jobs) do
    if job.prevMain then fs.write(job.path .. ".bak", job.prevMain) end
    if fs.remove then fs.remove(job.path) end
    local ok, err = fs.write(job.path, job.encoded)
    if not ok then
      restore()
      return false, tostring(err or "couldn't write that save")
    end
  end

  local handles = {}
  for i, job in ipairs(jobs) do
    if fs.remove then fs.remove(job.path .. ".tmp") end
    local handle = job.side.handle
    handle.save = job.save
    handle.party = job.save.party
    handle.boxes = type(job.save.boxes) == "table" and job.save.boxes or nil
    handles[i] = handle
  end
  return true, handles, backups
end

function Trade.pruneBackups(path, keep)
  keep = math.max(0, tonumber(keep) or 3)
  if type(path) ~= "string" or path == "" then return 0 end
  local fs = disk()
  if not fs or type(fs.getDirectoryItems) ~= "function"
      or type(fs.remove) ~= "function" then
    return 0
  end
  local dir, base = path:match("^(.*)/([^/]+)$")
  if not dir then dir, base = "", path end
  local ok, items = pcall(fs.getDirectoryItems, dir)
  if not ok or type(items) ~= "table" then return 0 end
  local prefix = base .. ".trade-bak-"
  local found = {}
  for _, name in ipairs(items) do
    if type(name) == "string" and name:sub(1, #prefix) == prefix then
      local stamp = tonumber(name:sub(#prefix + 1))
      if stamp then found[#found + 1] = { name = name, stamp = stamp } end
    end
  end
  table.sort(found, function(a, b)
    if a.stamp ~= b.stamp then return a.stamp > b.stamp end
    return a.name > b.name
  end)
  local removed = 0
  for i = keep + 1, #found do
    local full = (dir == "") and found[i].name or (dir .. "/" .. found[i].name)
    if fs.remove(full) then removed = removed + 1 end
  end
  return removed
end

-- ------- remote

local Remote = {}
Remote.__index = Remote

function Trade.remote(handle, link, opts)
  if type(handle) ~= "table" then return nil, "no save" end
  if handle.generation == 3 then return nil, Trade.GEN3_LOCAL_ONLY end
  if type(link) ~= "table" or type(link.send) ~= "function" then
    return nil, "no room"
  end
  opts = type(opts) == "table" and opts or {}
  local data, release = handle.data, nil
  if not data then
    if Trade.gameIsLive() then return nil, "close the game first" end
    local mounted, freeOrReason = mountDataset(handle.version)
    if not mounted then return nil, tostring(freeOrReason) end
    data, release = mounted, freeOrReason
  end
  local session = Protocol.TradeSession.new(data, handle.party, {
    subset = opts.subset, strict = opts.strict, peerName = opts.peerName,
  })
  return setmetatable({
    handle = handle,
    link = link,
    data = data,
    session = session,
    release = release,
    game = { data = data, save = handle.save },
  }, Remote)
end

function Remote:_send(msg)
  if type(msg) ~= "table" then return end
  if msg.type == "party" and self.handle.generation == 2 then
    msg = { type = "party",
            mons = packPartyFor(2, self.session.party,
                                self.session.sendIndices) }
  end
  self.link:send(msg)
end

function Remote:start()
  self:_send(self.session:opening())
end

function Remote:_theirParty(msg)
  local session = self.session
  session.theirParty = {}
  for _, packed in ipairs(msg.mons or {}) do
    local mon, why = Protocol.unpackMon2(self.data, packed,
                                         { strict = session.strict })
    if mon then
      session.theirParty[#session.theirParty + 1] = mon
    elseif session.strict then
      session.stage = "cancelled"
      session.error = why or "the other game sent an unknown POKéMON"
      return
    end
  end
  if session.stage == "waitParty" then session.stage = "picking" end
end

function Remote:update()
  if self.link.update then self.link:update() end
  local session = self.session
  if (self.link.closed or self.link.paired == false)
      and session.stage ~= "done" and session.stage ~= "cancelled" then
    session.stage = "cancelled"
    session.error = "the other trainer left"
    return session.stage
  end
  local messages = self.link:poll() or {}
  for _, msg in ipairs(messages) do
    if type(msg) == "table" and type(msg.type) == "string" then
      if msg.type == "party" and self.handle.generation == 2 then
        self:_theirParty(msg)
      else
        local reply = self.session:handle(msg)
        if reply then self:_send(reply) end
      end
    end
  end
  return self.session.stage
end

function Remote:stage()
  return self.session.stage
end

function Remote:canPick(index)
  return self.session:canPick(index)
end

function Remote:pick(index)
  local mon, reason = pickable(self.handle, index)
  if not mon then return false, reason end
  self:_send(self.session:pick(index))
  return true
end

function Remote:confirm(ok)
  self:_send(self.session:confirm(ok and true or false))
  return true
end

function Remote:plan()
  local session = self.session
  if session.stage ~= "done" then return nil, "the trade isn't finished" end
  local record = session.theirParty[session.theirPick]
  if type(record) ~= "table" then return nil, "the other game sent nothing" end
  local handle = self.handle
  local injected = handle.data
  handle.data = self.data
  local plan, reason = Trade.planIncoming({
    to = handle, toIndex = session.myPick, record = record,
  })
  handle.data = injected
  return plan, reason
end

function Remote:commit()
  local plan, reason = self:plan()
  if not plan then return false, reason end
  local handle = self.handle
  local injected = handle.data
  handle.data = self.data
  local ok, result, backups = Trade.commit(plan)
  handle.data = injected
  return ok, result, backups
end

function Remote:close()
  if self.release then
    self.release()
    self.release = nil
  end
  if self.link.close then pcall(function() self.link:close() end) end
end

return Trade
