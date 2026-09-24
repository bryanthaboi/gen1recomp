local Fingerprint = require("src.link.Fingerprint")
local GameVersion = require("src.core.GameVersion")
local Protocol = require("src.link.Protocol")
local SaveData = require("src.core.SaveData")
local TeamPick = require("src.online.TeamPick")

local Trade = {}

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
           pokemon = Pokemon, ItemsData = ItemsData }
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
  local path = Trade.slotPath(version, slotId, cartId)
  return {
    version = version,
    generation = slot.generation,
    slotId = slotId,
    cartId = cartId,
    save = save,
    path = path,
    party = slot.party,
    boxes = type(save.boxes) == "table" and save.boxes or nil,
    trainerName = slot.trainerName,
    data = opts.data,
    pendingSent = Trade.pendingSentAt(path),
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

local PENDING_MON = "that POKéMON's last trade isn't settled yet"

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
  if Trade.pendingHolds(handle, mon) then return nil, PENDING_MON end
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

local function partnerInfo3(handle)
  return {
    version = handle.version == "leafgreen" and VERSION_LEAF_GREEN
      or VERSION_FIRE_RED,
    progressFlags = national3(handle.save) and 1 or 0,
  }
end

-- pokefirered/src/trade.c:2745
local function refusal3(handle, ref, partner)
  local NTrade = require("src.core.game3.scripting.natives_trade")
  local party = handle.party or {}
  partner = type(partner) == "table" and partner or {}
  local code = NTrade.canTradeSelectedMon(party, ref.index - 1, {
    partyCount = #party,
    nationalDex = national3(handle.save),
    partner = {
      version = tonumber(partner.version) or 0,
      progressFlags = tonumber(partner.progressFlags) or 0,
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
  local why = refusal3(from, refA, partnerInfo3(to))
    or refusal3(to, refB, partnerInfo3(from))
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
  local mon, reason, ref = pickable(to, req.toIndex)
  if not mon then return nil, reason end
  if to.generation == 3 then
    if type(req.record) ~= "table" then return nil, "the other game sent nothing" end
    local why = refusal3(to, ref, req.partner)
    if why then return nil, why end
    local warnings3 = {}
    local side3, why3 = sideFor3(to, ref, req.record, req.mail, warnings3,
      req.partnerName)
    if not side3 then return nil, tostring(why3) end
    if side3.error then return nil, side3.error end
    side3.role = "a"
    return planFrom({ side3 }, warnings3)
  end
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

local function buildJobs(plan)
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
    if not built then return nil, tostring(why) end
    if built.error then return nil, built.error end
    jobs[#jobs + 1] = { side = side, path = side.handle.path,
                        save = built.save, encoded = built.encoded }
  end
  return jobs
end

local function tradeable(plan)
  return type(plan) == "table" and type(plan.sides) == "table" and #plan.sides > 0
end

function Trade.prepare(plan)
  if not tradeable(plan) then return false, "no trade to make" end
  local jobs, why = buildJobs(plan)
  if not jobs then return false, why end
  plan.prepared = jobs
  return true
end

function Trade.commit(plan)
  if not tradeable(plan) then return false, "no trade to make" end
  if Trade.gameIsLive() then return false, "close the game first" end

  local jobs, why = plan.prepared, nil
  plan.prepared = nil
  if not jobs then
    jobs, why = buildJobs(plan)
    if not jobs then return false, why end
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

Trade.OUTCOME_RETRY_SECONDS = 5
Trade.JOURNAL_TTL = 24 * 60 * 60
Trade._applied = {}
Trade._journalPaths = {}
Trade._resolver = nil
Trade._scanned = false

function Trade.journalPath(savePath)
  if type(savePath) ~= "string" or savePath == "" then return nil end
  return (savePath:gsub("%.lua$", "")) .. "_trade.lua"
end

local function readJournal(file)
  local fs = disk()
  if not (fs and file and fs.getInfo(file)) then return {} end
  local ok, text = pcall(fs.read, file)
  if not ok or type(text) ~= "string" or text == "" then return {} end
  local okD, data = pcall(SaveData.decode, text)
  if not okD or type(data) ~= "table" or type(data.entries) ~= "table" then return {} end
  return data.entries
end

local function writeJournal(file, entries)
  local fs = disk()
  if not (fs and file) then return false end
  if #entries == 0 then
    if not fs.getInfo(file) then return true end
    local ok, removed = pcall(fs.remove, file)
    return ok and removed ~= false
  end
  local okE, text = pcall(SaveData.encode, { v = 1, entries = entries })
  if not okE then return false end
  local ok, wrote = pcall(fs.write, file, text)
  if not (ok and wrote) then return false end
  local okR, back = pcall(fs.read, file)
  return okR and back == text
end

local function journalAdd(file, entry)
  local kept = {}
  for _, e in ipairs(readJournal(file)) do
    if not (e.room == entry.room and e.digest == entry.digest) then kept[#kept + 1] = e end
  end
  kept[#kept + 1] = entry
  if not writeJournal(file, kept) then return false end
  Trade._journalPaths[file] = true
  return true
end

local function journalDrop(file, room, digest)
  local list, kept = readJournal(file), {}
  for _, e in ipairs(list) do
    if not (e.room == room and e.digest == digest) then kept[#kept + 1] = e end
  end
  if #kept == #list then return true end
  return writeJournal(file, kept)
end

local function journalFiles()
  local out, seen = {}, {}
  local function add(file, scope, slotId)
    if seen[file] or not (scope and slotId) then return end
    seen[file] = true
    out[#out + 1] = { file = file, scope = scope, slotId = slotId }
  end
  for file in pairs(Trade._journalPaths) do
    local scope, slotId = file:match("^saves/([^/]+)/(slot%d+)_trade%.lua$")
    add(file, scope, slotId)
  end
  local fs = disk()
  if fs and type(fs.getDirectoryItems) == "function" then
    local ok, dirs = pcall(fs.getDirectoryItems, "saves")
    for _, dir in ipairs(ok and type(dirs) == "table" and dirs or {}) do
      local okI, items = pcall(fs.getDirectoryItems, "saves/" .. tostring(dir))
      for _, name in ipairs(okI and type(items) == "table" and items or {}) do
        local slotId = type(name) == "string" and name:match("^(slot%d+)_trade%.lua$")
        if slotId then add("saves/" .. dir .. "/" .. name, dir, slotId) end
      end
    end
  end
  return out
end

function Trade.pendingTrades()
  local out = {}
  for _, f in ipairs(journalFiles()) do
    local cart = f.scope:match("^cart_(.+)$")
    for _, e in ipairs(readJournal(f.file)) do
      if type(e) == "table" then
        local version = type(e.version) == "string" and e.version
          or (not cart and f.scope) or nil
        if version and not GameVersion.info(version) then version = nil end
        out[#out + 1] = { file = f.file, entry = e, version = version,
                          slotId = e.slotId or f.slotId, cartId = e.cartId or cart }
      end
    end
  end
  return out
end

local function pendingKey(item)
  return tostring(item.file) .. ":" .. tostring(item.entry.room) .. ":"
    .. tostring(item.entry.digest)
end

local function sameMon3(mon, packed)
  return type(mon) == "table" and type(packed) == "table"
    and (tonumber(mon.personality) or 0) == tonumber(packed.personality)
    and (tonumber(mon.otId) or 0) % 65536 == tonumber(packed.otId)
end

local function identity12(packed)
  if type(packed) ~= "table" then return nil end
  return Protocol.canonical({ species = packed.species, dvs = packed.dvs,
                              ot = packed.ot, otId = packed.otId })
end

local function wireIdentity12(generation, mon)
  if type(mon) ~= "table" then return nil end
  local ok, packed = pcall(packFor, generation, mon)
  if not ok then return nil end
  local clean = require("src.link.Wire").sanitize({ type = "party", mons = { packed } })
  return identity12(clean and clean.mons and clean.mons[1])
end

function Trade.pendingSentAt(savePath)
  local out = {}
  for _, e in ipairs(readJournal(Trade.journalPath(savePath))) do
    if type(e) == "table" and type(e.sent) == "table" then out[#out + 1] = e.sent end
  end
  return out
end

function Trade.pendingHolds(handle, mon)
  local list = type(handle) == "table" and handle.pendingSent or nil
  if type(list) ~= "table" or #list == 0 or type(mon) ~= "table" then return false end
  local mine = handle.generation ~= 3 and wireIdentity12(handle.generation, mon) or nil
  for _, sent in ipairs(list) do
    if handle.generation == 3 then
      if sameMon3(mon, sent) then return true end
    elseif mine ~= nil and identity12(sent) == mine then
      return true
    end
  end
  return false
end

local function locateSent(handle, e)
  if type(e.sent) ~= "table" then return nil end
  if handle.generation == 3 then
    for i, mon in ipairs(handle.party or {}) do
      if sameMon3(mon, e.sent) then return { where = "party", index = i } end
    end
    return nil
  end
  local want = identity12(e.sent)
  local ref = refOf(e.ref)
  if ref and wireIdentity12(handle.generation, TeamPick.monAt(handle, ref)) == want then
    return ref
  end
  for i, mon in ipairs(handle.party or {}) do
    if wireIdentity12(handle.generation, mon) == want then
      return { where = "party", index = i }
    end
  end
  for b, box in pairs(handle.boxes or {}) do
    for i, mon in pairs(type(box) == "table" and box or {}) do
      if tonumber(b) and tonumber(i) and wireIdentity12(handle.generation, mon) == want then
        return { where = "box", box = tonumber(b), index = tonumber(i) }
      end
    end
  end
  return nil
end

function Trade.applyPending(item)
  if Trade.gameIsLive() then return false, "close the game first" end
  local e = item.entry
  local handle, reason = Trade.openSlot(item.version, item.slotId, item.cartId)
  if not handle then return false, reason end
  local ref = locateSent(handle, e)
  if not ref then return false, "missing" end
  local result, why = Trade.withDataset(item.version, function(data)
    handle.data = data
    local warnings, side, sideWhy = {}, nil, nil
    if handle.generation == 3 then
      local record, unpackWhy = Protocol.unpackMon3(data, e.mon, { strict = true })
      if not record then return { error = unpackWhy or "unknown POKéMON" } end
      side, sideWhy = sideFor3(handle, ref, record, e.mail, warnings, e.name)
    else
      local record = type(e.record) == "table" and deepCopy(e.record) or nil
      side, sideWhy = sideFor(handle, ref, e.mon, record, warnings)
    end
    if not side then return { error = tostring(sideWhy) } end
    if side.error then return { error = side.error } end
    side.role = "a"
    local ok, committed = Trade.commit(planFrom({ side }, warnings))
    if not ok then return { error = tostring(committed) } end
    return { ok = true }
  end)
  handle.data = nil
  if not result then return false, why end
  if result.error then return false, result.error end
  pcall(Trade.pruneBackups, handle.path, 3)
  return true
end

function Trade.settlePending(item, outcome)
  local e = item.entry
  if outcome == "abort" then
    journalDrop(item.file, e.room, e.digest)
    return "abort"
  end
  if outcome ~= "commit" or Trade._applied[pendingKey(item)] then return nil end
  local ok, why = Trade.applyPending(item)
  if ok then
    Trade._applied[pendingKey(item)] = true
    journalDrop(item.file, e.room, e.digest)
    return "commit"
  end
  if why == "missing" then
    journalDrop(item.file, e.room, e.digest)
    return "dropped"
  end
  print("[trade] pending trade " .. pendingKey(item) .. " not applied: " .. tostring(why))
  return nil, why
end

function Trade.resumePending()
  Trade._scanned = true
  if Trade._resolver then return Trade._resolver end
  if #Trade.pendingTrades() == 0 then return nil end
  Trade._resolver = { wait = 0, fails = 0, index = 0 }
  return Trade._resolver
end

function Trade.pumpPending(dt)
  local st = Trade._resolver
  if not st then
    if Trade._scanned then return false end
    st = Trade.resumePending()
    if not st then return false end
  end
  if Trade.gameIsLive() or Trade.mounted() then return false end
  local LT = require("src.core.game3.link.trade")
  if st.job then
    local status, outcome = LT.pollOutcome(st.job)
    if status == "pending" then return false end
    local item = st.job.item
    st.job = nil
    local settled = status == "ok"
    if settled then
      local done = Trade.settlePending(item, outcome)
      settled = done ~= nil or outcome == "open"
    end
    st.fails = settled and 0 or math.min((st.fails or 0) + 1, 6)
    st.wait = Trade.OUTCOME_RETRY_SECONDS * 2 ^ st.fails
  end
  if (st.wait or 0) > 0 then
    st.wait = st.wait - (tonumber(dt) or 0)
    return false
  end
  local now, open = os.time(), {}
  for _, item in ipairs(Trade.pendingTrades()) do
    if now - (tonumber(item.entry.at) or 0) > Trade.JOURNAL_TTL then
      journalDrop(item.file, item.entry.room, item.entry.digest)
    elseif item.version and not Trade._applied[pendingKey(item)] then
      open[#open + 1] = item
    end
  end
  if #open == 0 then
    Trade._resolver = nil
    return true
  end
  st.index = ((st.index or 0) % #open) + 1
  local job = LT.fetchOutcome(open[st.index].entry)
  job.item = open[st.index]
  st.job = job
  return false
end

local function roomOf(link)
  local id = type(link) == "table" and link.target or nil
  return type(id) == "string" and id ~= "" and id or nil
end

local function journalOpen(remote, fields)
  local room = roomOf(remote.link)
  local handle = remote.handle
  local file = Trade.journalPath(handle.path)
  if not (room and file and remote.digest) then return true end
  local entry = { room = room, digest = remote.digest, at = os.time(),
    engine = "launcher", version = handle.version, slotId = handle.slotId,
    cartId = handle.cartId, generation = handle.generation, unionRoom = false }
  for k, v in pairs(fields) do entry[k] = deepCopy(v) end
  if not journalAdd(file, entry) then return false end
  remote._journal = { file = file, room = room, digest = remote.digest }
  remote._journaled = true
  return true
end

local function journalClose(remote)
  local j = remote._journal
  remote._journal = nil
  if j then journalDrop(j.file, j.room, j.digest) end
end

-- ------- remote

local Remote = {}
Remote.__index = Remote

local Remote3 = {}
Remote3.__index = Remote3

local LEFT = "the other trainer left"
local JOURNAL_FAILED = "the trade couldn't be saved"

local function seatOf(link)
  if type(link.seat) ~= "function" then return nil end
  local ok, seat = pcall(link.seat, link)
  seat = ok and tonumber(seat) or nil
  if seat == 0 or seat == 1 then return seat end
  return nil
end

local function wireField(msg, field)
  local clean = require("src.link.Wire").sanitize(msg)
  return clean and clean[field] or nil
end

local function digestFor(seat, mine, theirs)
  if seat == 0 then return Protocol.tradeDigest(mine, theirs) end
  return Protocol.tradeDigest(theirs, mine)
end

local function commitMatches(msg, digest)
  local d = type(msg.digests) == "table" and msg.digests or {}
  return digest ~= nil and d[1] == digest and d[2] == digest
end

local function withHandleData(remote, fn)
  local handle = remote.handle
  local injected = handle.data
  handle.data = remote.data
  local ok, a, b, c = pcall(fn)
  handle.data = injected
  if not ok then return nil, tostring(a) end
  return a, b, c
end

function Trade.remote(handle, link, opts)
  if type(handle) ~= "table" then return nil, "no save" end
  if type(link) ~= "table" or type(link.send) ~= "function" then
    return nil, "no room"
  end
  opts = type(opts) == "table" and opts or {}
  local seat = seatOf(link)
  if seat == nil then return nil, "no seat" end
  local data, release = handle.data, nil
  if not data then
    if Trade.gameIsLive() then return nil, "close the game first" end
    local mounted, freeOrReason = mountDataset(handle.version)
    if not mounted then return nil, tostring(freeOrReason) end
    data, release = mounted, freeOrReason
  end
  if handle.generation == 3 then
    return setmetatable({
      handle = handle,
      link = link,
      data = data,
      release = release,
      seat = seat,
      opts = opts,
      phase = "handshake",
      session = { theirParty = {}, peerName = opts.peerName },
    }, Remote3)
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
    seat = seat,
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
  if msg.type == "party" then self._sentMons = wireField(msg, "mons") end
  self.link:send(msg)
end

function Remote:_cancel(why)
  self.phase = "cancelled"
  self.session.error = why
  return self.phase
end

function Remote:_open()
  return self.phase ~= "committed" and self.phase ~= "cancelled"
    and self.session.stage ~= "cancelled"
end

function Remote:_confirmBarrier()
  local session = self.session
  local mine = type(self._sentMons) == "table"
    and self._sentMons[session:wireIndex(session.myPick)] or nil
  local theirs = type(self._theirMons) == "table"
    and self._theirMons[session.theirPick] or nil
  if type(mine) ~= "table" or type(theirs) ~= "table" then
    return self:_cancel("the other game sent nothing")
  end
  local plan, why = self:plan()
  if plan then
    local prepared, prepWhy = withHandleData(self, function() return Trade.prepare(plan) end)
    if not prepared then plan, why = nil, prepWhy end
  end
  if not plan then
    self.link:send({ type = "bye" })
    return self:_cancel(why)
  end
  self._plan = plan
  self.digest = digestFor(self.seat, mine, theirs)
  local journaled = journalOpen(self, {
    sent = mine, mon = theirs, record = session.theirParty[session.theirPick],
    ref = refOf(session.myPick), name = session.peerName,
  })
  if not journaled then
    self.link:send({ type = "bye" })
    return self:_cancel(JOURNAL_FAILED)
  end
  self.link:send({ type = "trade_confirm", digest = self.digest })
  self.phase = "commit_wait"
  return self.phase
end

function Remote:_onCommit(msg)
  if self.phase ~= "commit_wait" then return end
  if not commitMatches(msg, self.digest) then return self:_cancel("digest") end
  self._relayCommitted = true
  local ok, result = self:commit()
  if ok then
    journalClose(self)
    self.phase = "committed"
  else
    self:_cancel(tostring(result))
  end
end

function Remote:_onAbort(msg)
  if self.phase ~= "commit_wait" then return end
  journalClose(self)
  self:_cancel(tostring(msg.why or "abort"))
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
  local messages = self.link:poll() or {}
  for _, msg in ipairs(messages) do
    if type(msg) == "table" and type(msg.type) == "string" then
      if msg.type == "trade_commit" then
        self:_onCommit(msg)
      elseif msg.type == "trade_abort" then
        self:_onAbort(msg)
      elseif not self.phase then
        if msg.type == "party" then self._theirMons = msg.mons end
        if msg.type == "party" and self.handle.generation == 2 then
          self:_theirParty(msg)
        else
          local reply = self.session:handle(msg)
          if reply then self:_send(reply) end
        end
      end
    end
  end
  if not self.phase and session.stage == "done" then self:_confirmBarrier() end
  if (self.link.closed or self.link.paired == false) and self:_open() then
    self:_cancel(LEFT)
  end
  return self:stage()
end

function Remote:stage()
  return self.phase or self.session.stage
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
  if not self.phase and self.session.stage == "done" then self:_confirmBarrier() end
  return true
end

function Remote:plan()
  local session = self.session
  if session.stage ~= "done" then return nil, "the trade isn't finished" end
  local record = session.theirParty[session.theirPick]
  if type(record) ~= "table" then return nil, "the other game sent nothing" end
  return withHandleData(self, function()
    return Trade.planIncoming({
      to = self.handle, toIndex = session.myPick, record = record,
    })
  end)
end

function Remote:commit()
  if self.commitResult then return unpack(self.commitResult, 1, 3) end
  if not self._relayCommitted then return false, "the trade isn't committed" end
  local plan, reason = self._plan, nil
  if not plan then plan, reason = self:plan() end
  if not plan then return false, reason end
  local ok, result, backups = withHandleData(self, function()
    return Trade.commit(plan)
  end)
  self.commitResult = { ok, result, backups }
  return ok, result, backups
end

function Remote:close()
  if self.release then
    self.release()
    self.release = nil
  end
  if self.link.close then pcall(function() self.link:close() end) end
  if self._journaled then
    self._journal, self._journaled = nil, nil
    Trade.resumePending()
  end
end

local function lt()
  return require("src.core.game3.link.trade")
end

local MSG3 = {
  SEAT = "game3_battle_seat",
  PARTY = "game3_trade_party",
  MON = "game3_trade_mon",
  CMD = "game3_trade_cmd",
  CONFIRM = "game3_trade_confirm",
  COMMIT = "trade_commit",
  ABORT = "trade_abort",
}

local STATUS = { NONE = 0, READY = 1, CANCEL = 2 }

local function saveName3(save)
  return type(save) == "table" and type(save.name) == "string" and save.name or "PLAYER"
end

local function saveGender3(save)
  local g = type(save) == "table" and save.gender or 0
  return (g == 1 or g == "female" or g == "F") and 1 or 0
end

local function saveTrainerId3(save)
  return tonumber(type(save) == "table" and save.trainerId) or 0
end

function Remote3:_send(msg)
  local g3 = self.g3
  if not g3 then return false end
  return g3:send(msg)
end

function Remote3:_cmd(cmd, cursor)
  return self:_send({ type = MSG3.CMD, cmd = cmd, cursor = cursor or 0 })
end

function Remote3:_clearStatuses()
  self.playerSelect, self.partnerSelect = STATUS.NONE, STATUS.NONE
  self.playerConfirm, self.partnerConfirm = STATUS.NONE, STATUS.NONE
end

function Remote3:_clearExchange()
  self._myPacked, self._theirBlock = nil, nil
  self._plan, self.digest = nil, nil
end

function Remote3:_cancel(why)
  self.phase = "cancelled"
  self.session.error = why
  return self.phase
end

local EXCHANGING = { exchange = true, commit_wait = true }

-- pokefirered/src/trade.c:2094
function Remote3:_resume(result)
  if self.phase == "committed" or self.phase == "cancelled" then return end
  if EXCHANGING[self.phase] then self._staleRound = (self._lastRound or 0) + 1 end
  self.phase = "picking"
  self.lastResult = result
  self.session.myPick, self.session.theirPick = nil, nil
  self.myCursor, self.partnerCursor = nil, nil
  self:_clearStatuses()
  self:_clearExchange()
end

function Remote3:start()
  if self.g3 then return true end
  local Game3Link = require("src.link.Game3Link")
  local Dataset = require("src.core.game3.dataset")
  local cache = Dataset.cache()
  local ok, inputs = pcall(Fingerprint.gen3Inputs, function(rel) return cache:read(rel) end)
  if not ok then
    self:_cancel(tostring(inputs))
    return false
  end
  local save = self.handle.save
  local game = { data = { generation = 3, gen3Inputs = inputs },
                 save = { player = { name = saveName3(save) } } }
  local player = { name = saveName3(save), trainerId = saveTrainerId3(save),
                   gender = saveGender3(save) }
  local hello = Game3Link.hello(game, Game3Link.LINKTYPE.TRADE, player)
  self.transport = self.opts.transport
    or require("src.core.game3.link.relay_transport").new(self.link)
  self.g3 = Game3Link.attach(self.transport, {
    seat = self.seat, seats = 2, linkType = Game3Link.LINKTYPE.TRADE,
    hello = hello, game = game, timeout = self.opts.timeout,
  })
  self:_clearStatuses()
  return true
end

-- pokefirered/src/trade.c:778
function Remote3:_sendParty()
  local handle = self.handle
  self:_send({
    type = MSG3.PARTY,
    party = Protocol.packParty3(handle.party),
    name = saveName3(handle.save),
    trainerId = saveTrainerId3(handle.save),
    gender = saveGender3(handle.save),
    version = partnerInfo3(handle).version,
    progressFlags = partnerInfo3(handle).progressFlags,
  })
end

local PARTY_PHASES = { seat = true, waitParty = true, picking = true, waitPick = true }

function Remote3:_theirParty(msg)
  if not PARTY_PHASES[self.phase] then return end
  local list = type(msg.party) == "table" and msg.party or {}
  local out = {}
  for i = 1, math.min(#list, 6) do
    local mon, why = Protocol.unpackMon3(self.data, list[i], { strict = true })
    if not mon then
      self:_cmd(lt().LINKCMD.BOTH_CANCEL_TRADE, 0)
      return self:_cancel(why or "the other game sent an unknown POKéMON")
    end
    out[i] = mon
  end
  self._theirPacked = list
  self.session.theirParty = out
  self.session.peerName = type(msg.name) == "string" and msg.name or self.session.peerName
  self.partner = {
    version = tonumber(msg.version) or 0,
    progressFlags = tonumber(msg.progressFlags) or 0,
    name = msg.name,
    trainerId = tonumber(msg.trainerId) or 0,
  }
  if self.phase == "waitParty" then self.phase = "picking" end
end

function Remote3:canPick(index)
  local mon, _, ref = pickable(self.handle, index)
  if not mon then return false end
  if not self.partner then return false end
  return refusal3(self.handle, ref, self.partner) == nil
end

function Remote3:pick(index)
  if self.phase ~= "picking" then return false, "wait for the other trainer" end
  local mon, reason, ref = pickable(self.handle, index)
  if not mon then return false, reason end
  if not self.partner then return false, "wait for the other trainer" end
  local why = refusal3(self.handle, ref, self.partner)
  if why then return false, why end
  self.session.myPick = ref.index
  self.myCursor = ref.index - 1
  self.phase = "waitPick"
  if self.seat == 0 then
    self.playerSelect = STATUS.READY
    self:_leaderHandle()
  else
    self:_cmd(lt().LINKCMD.READY_TO_TRADE, self.myCursor)
  end
  return true
end

-- pokefirered/src/trade.c:2043
function Remote3:cancelPick()
  if self.phase ~= "picking" and self.phase ~= "waitPick" then return false end
  self.phase = "waitPick"
  if self.seat == 0 then
    self.playerSelect = STATUS.CANCEL
    self:_leaderHandle()
  else
    self:_cmd(lt().LINKCMD.REQUEST_CANCEL, 0)
  end
  return true
end

-- pokefirered/src/trade.c:1951
function Remote3:_partnerMonValid()
  local mon = self.session.theirParty[self.session.theirPick or 0]
  if type(mon) ~= "table" then return false end
  local species = tonumber(mon.species) or 0
  if (species == 151 or species == 410) and mon.fatefulEncounter == false then
    return false
  end
  return true
end

-- pokefirered/src/trade.c:1976
function Remote3:confirm(yes)
  if self.phase ~= "confirming" then return false end
  local status = STATUS.CANCEL
  if yes and self:_partnerMonValid() then status = STATUS.READY end
  if yes and status ~= STATUS.READY then self.lastResult = "partner_invalid" end
  self.phase = "waitConfirm"
  if self.seat == 0 then
    self.playerConfirm = status
    self:_leaderHandle()
  else
    self:_cmd(status == STATUS.READY and lt().LINKCMD.INIT_BLOCK
      or lt().LINKCMD.READY_CANCEL_TRADE, 0)
  end
  return true
end

-- pokefirered/src/trade.c:1681
function Remote3:_leaderHandle()
  local C = lt().LINKCMD
  if self.playerSelect ~= STATUS.NONE and self.partnerSelect ~= STATUS.NONE then
    local player, partner = self.playerSelect, self.partnerSelect
    if player == STATUS.READY and partner == STATUS.READY then
      self:_cmd(C.SET_MONS_TO_TRADE, self.myCursor)
      self.playerSelect, self.partnerSelect = STATUS.NONE, STATUS.NONE
      self.session.theirPick = (self.partnerCursor or 0) + 1
      self.phase = "confirming"
    elseif player == STATUS.READY then
      self:_cmd(C.PARTNER_CANCEL_TRADE, 0)
      self:_resume("partner_canceled")
    elseif partner == STATUS.READY then
      self:_cmd(C.PLAYER_CANCEL_TRADE, 0)
      self:_resume("player_canceled")
    else
      self:_cmd(C.BOTH_CANCEL_TRADE, 0)
      self:_cancel("both_canceled")
    end
  end
  if self.playerConfirm ~= STATUS.NONE and self.partnerConfirm ~= STATUS.NONE then
    if self.playerConfirm == STATUS.READY and self.partnerConfirm == STATUS.READY then
      self:_cmd(C.START_TRADE, 0)
      self.playerConfirm, self.partnerConfirm = STATUS.NONE, STATUS.NONE
      self:_beginTrade()
    else
      self:_cmd(C.PLAYER_CANCEL_TRADE, 0)
      self:_resume("trade_canceled")
    end
  end
end

-- pokefirered/src/trade.c:1593
function Remote3:_leaderRead(msg)
  local C = lt().LINKCMD
  local cmd = tonumber(msg.cmd)
  if cmd == C.REQUEST_CANCEL then
    self.partnerSelect = STATUS.CANCEL
  elseif cmd == C.READY_TO_TRADE then
    self.partnerCursor = math.floor(tonumber(msg.cursor) or 0)
    self.partnerSelect = STATUS.READY
  elseif cmd == C.INIT_BLOCK then
    self.partnerConfirm = STATUS.READY
  elseif cmd == C.READY_CANCEL_TRADE then
    self.partnerConfirm = STATUS.CANCEL
  elseif cmd == C.CONFIRM_FINISH_TRADE then
    self.peerFinished = true
  elseif cmd == C.PLAYER_CANCEL_TRADE and EXCHANGING[self.phase] then
    self:_resume("trade_canceled")
  elseif cmd == C.BOTH_CANCEL_TRADE and self.phase ~= "committed" then
    self:_cancel("both_canceled")
  end
  self:_leaderHandle()
end

-- pokefirered/src/trade.c:1637
function Remote3:_followerRead(msg)
  local C = lt().LINKCMD
  local cmd = tonumber(msg.cmd)
  if cmd == C.BOTH_CANCEL_TRADE then
    if self.phase ~= "committed" then self:_cancel("both_canceled") end
  elseif cmd == C.PARTNER_CANCEL_TRADE then
    self:_resume("partner_canceled")
  elseif cmd == C.SET_MONS_TO_TRADE then
    self.partnerCursor = math.floor(tonumber(msg.cursor) or 0)
    self.session.theirPick = self.partnerCursor + 1
    self.phase = "confirming"
  elseif cmd == C.START_TRADE then
    self:_beginTrade()
  elseif cmd == C.PLAYER_CANCEL_TRADE then
    self:_resume("trade_canceled")
  elseif cmd == C.CONFIRM_FINISH_TRADE then
    self.peerFinished = true
  end
end

-- pokefirered/src/trade.c:1302
function Remote3:_beginTrade()
  if EXCHANGING[self.phase] or self.phase == "committed" then return end
  local mon = (self.handle.party or {})[self.session.myPick or 0]
  if type(mon) ~= "table" then return self:_resume("no_mon") end
  self._plan, self.digest = nil, nil
  local block = {
    type = MSG3.MON,
    mon = Protocol.packMon3(mon),
    mail = mailOf3(self.handle.save, mon),
    name = saveName3(self.handle.save),
    trainerId = saveTrainerId3(self.handle.save),
  }
  self._myPacked = wireField(block, "mon")
  self.phase = "exchange"
  self:_send(block)
  self:_tryConfirm()
end

function Remote3:_tryConfirm()
  if self.phase ~= "exchange" then return end
  local block = self._theirBlock
  if not (block and self._myPacked) then return end
  local C = lt().LINKCMD
  local shown = type(self._theirPacked) == "table"
    and self._theirPacked[self.session.theirPick or 0] or nil
  if type(shown) ~= "table" or type(block.mon) ~= "table"
      or Protocol.canonical(Protocol.wireMon3(shown)) ~= Protocol.canonical(block.mon) then
    self.lastRefusal = "not the POKéMON that was shown"
    self:_cmd(C.PLAYER_CANCEL_TRADE, 0)
    return self:_resume("bad_mon")
  end
  local record, why = Protocol.unpackMon3(self.data, block.mon, { strict = true })
  if not record then
    self.lastRefusal = why
    self:_cmd(C.PLAYER_CANCEL_TRADE, 0)
    return self:_resume("bad_mon")
  end
  local plan, planWhy = withHandleData(self, function()
    return Trade.planIncoming({
      to = self.handle, toIndex = self.session.myPick, record = record,
      mail = block.mail, partner = self.partner,
      partnerName = block.name or (self.partner and self.partner.name),
    })
  end)
  if not plan then
    self.lastRefusal = planWhy
    self:_cmd(C.PLAYER_CANCEL_TRADE, 0)
    return self:_resume("bad_mon")
  end
  local prepared, prepWhy = withHandleData(self, function() return Trade.prepare(plan) end)
  if not prepared then
    self.lastRefusal = prepWhy
    self:_cmd(C.PLAYER_CANCEL_TRADE, 0)
    return self:_resume("bad_mon")
  end
  self._plan = plan
  self.received = record
  self.digest = digestFor(self.seat, self._myPacked, block.mon)
  local journaled = journalOpen(self, {
    sent = self._myPacked, mon = block.mon, mail = block.mail,
    name = block.name or (self.partner and self.partner.name),
    partner = self.partner,
  })
  if not journaled then
    self.lastRefusal = JOURNAL_FAILED
    self:_cmd(C.PLAYER_CANCEL_TRADE, 0)
    return self:_resume("journal")
  end
  local g3 = self.g3
  local drained = g3:take(MSG3.COMMIT) or g3:take(MSG3.ABORT)
  while drained do
    self:_noteRound(drained)
    drained = g3:take(MSG3.COMMIT) or g3:take(MSG3.ABORT)
  end
  self.phase = "commit_wait"
  self:_send({ type = MSG3.CONFIRM, digest = self.digest })
end

function Remote3:_noteRound(msg)
  local n = math.floor(tonumber(msg.n) or 0)
  if n > (self._lastRound or 0) then self._lastRound = n end
end

function Remote3:_onCommit(msg)
  if self.phase ~= "commit_wait" then return end
  if not commitMatches(msg, self.digest) then return self:_cancel("digest") end
  self._relayCommitted = true
  local ok, result = self:commit()
  if not ok then return self:_cancel(tostring(result)) end
  journalClose(self)
  self.phase = "committed"
  self:_cmd(lt().LINKCMD.CONFIRM_FINISH_TRADE, 0)
end

function Remote3:_onAbort(msg)
  if self.phase ~= "commit_wait" then return end
  local n = tonumber(msg.n)
  if self._staleRound and n and n <= self._staleRound then
    self._staleRound = nil
    self:_send({ type = MSG3.CONFIRM, digest = self.digest })
    return
  end
  journalClose(self)
  self:_cancel(tostring(msg.why or "abort"))
end

function Remote3:update(dt)
  local g3 = self.g3
  if not g3 then return self.phase end
  g3:update(tonumber(dt) or 0)
  local commit = g3:take(MSG3.COMMIT)
  while commit do
    self:_onCommit(commit)
    self:_noteRound(commit)
    commit = g3:take(MSG3.COMMIT)
  end
  local abort = g3:take(MSG3.ABORT)
  while abort do
    self:_onAbort(abort)
    self:_noteRound(abort)
    abort = g3:take(MSG3.ABORT)
  end
  if self.phase == "handshake" and g3:isReady() then
    self.session.peerName = g3:peerName() or self.session.peerName
    self:_send({ type = MSG3.SEAT, seat = self.seat })
    self.phase = "seat"
  end
  if self.phase == "seat" and g3:take(MSG3.SEAT) then
    self:_sendParty()
    self.phase = "waitParty"
  end
  if self.phase ~= "handshake" and self.phase ~= "cancelled" then
    local party = g3:take(MSG3.PARTY)
    while party do
      self:_theirParty(party)
      party = g3:take(MSG3.PARTY)
    end
    local block = g3:take(MSG3.MON)
    while block do
      if EXCHANGING[self.phase] or self.phase == "waitConfirm" or self.phase == "confirming" then
        self._theirBlock = block
      end
      block = g3:take(MSG3.MON)
    end
    local cmd = g3:take(MSG3.CMD)
    while cmd do
      if self.seat == 0 then self:_leaderRead(cmd) else self:_followerRead(cmd) end
      cmd = g3:take(MSG3.CMD)
    end
    self:_tryConfirm()
  end
  if self.phase ~= "committed" and self.phase ~= "cancelled"
      and (g3.closed or g3:peerGone()) then
    self:_cancel(g3.verdict and g3.verdict ~= "full" and tostring(g3.reason or g3.verdict) or LEFT)
  end
  return self.phase
end

function Remote3:stage()
  return self.phase
end

function Remote3:commit()
  if self.commitResult then return unpack(self.commitResult, 1, 3) end
  if not self._relayCommitted then return false, "the trade isn't committed" end
  local plan = self._plan
  if not plan then return false, "the trade isn't finished" end
  local ok, result, backups = withHandleData(self, function()
    return Trade.commit(plan)
  end)
  self.commitResult = { ok, result, backups }
  return ok, result, backups
end

function Remote3:close()
  local g3, transport = self.g3, self.transport
  if g3 then pcall(function() g3:close("bye") end) end
  if transport and type(transport.leave) == "function" then
    pcall(function() transport:leave() end)
  elseif self.link.close then
    pcall(function() self.link:close() end)
  end
  if self.release then
    self.release()
    self.release = nil
  end
  if self._journaled then
    self._journal, self._journaled = nil, nil
    Trade.resumePending()
  end
end

return Trade
