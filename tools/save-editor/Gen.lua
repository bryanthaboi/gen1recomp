-- Generation adapter for the save editor. Panels stay generation-blind;
-- Ops and App read Gold vs RBY vs FRLG through this module so a write never
-- lands in wrong-generation fields.

local GameVersion = require("src.core.GameVersion")

local Gen = {}

local function versionGeneration(version)
  if type(version) ~= "string" then return nil end
  local info = GameVersion.info(version)
  if info then return info.generation or 1 end
  return nil
end

function Gen.of(save, version)
  if type(save) == "table" then
    if save.generation == 3 or save.engine == "game3" or save.version == "firered" then return 3 end
    if save.healMap ~= nil or (save.bag and save.bag.pockets ~= nil) or (save.dex and save.dex.national ~= nil) then return 3 end
    if save.generation == 2 then return 2 end
    local fromVersion = versionGeneration(save.version)
    if fromVersion then return fromVersion end
  end
  local fromArg = versionGeneration(version)
  if fromArg then return fromArg end
  return GameVersion.generation()
end

local function versionOf(save, version)
  if type(save) == "table" and GameVersion.VERSIONS[save.version] then
    return save.version
  end
  if type(version) == "string" and GameVersion.VERSIONS[version] then
    return version
  end
  return GameVersion.get()
end
Gen.versionOf = versionOf

function Gen.engineOf(save, version)
  return GameVersion.engine(versionOf(save, version))
end

function Gen.editionLabel(save, version)
  local info = GameVersion.info(versionOf(save, version))
  if Gen.of(save, version) == 3 then
    return tostring((info and info.label) or "FIRE RED"):upper()
  end
  return tostring((info and info.label) or "GEN 2"):upper()
end

function Gen.hasCaughtData(save, version)
  if Gen.of(save, version) ~= 2 then return false end
  return require("src.battle.gen2.Mon").hasCaughtData(versionOf(save, version))
end

-- engine/menus/init_gender.asm:23-38 (Crystal), FRLG Oak intro (gender 0/1)
function Gen.hasPlayerGender(save, version)
  local g = Gen.of(save, version)
  if g == 3 then return true end
  if g == 2 then return Gen.engineOf(save, version) == "crystal" end
  return false
end

function Gen.ofState(S)
  if not S then return GameVersion.generation() end
  return Gen.of(S.save, S.version)
end

function Gen.is2(save, version)
  return Gen.of(save, version) == 2
end

function Gen.is3(save, version)
  return Gen.of(save, version) == 3
end

local function overlayRecords(base, overlay)
  if not overlay then return base or {} end
  if not base or base == overlay then return overlay end
  local out = {}
  for id, def in pairs(base) do out[id] = def end
  for id, def in pairs(overlay) do
    local prior = out[id]
    if type(def) == "table" and type(prior) == "table" then
      local merged = {}
      for k, v in pairs(prior) do merged[k] = v end
      for k, v in pairs(def) do merged[k] = v end
      out[id] = merged
    else
      out[id] = def
    end
  end
  return out
end

function Gen.maps(data)
  if type(data) ~= "table" then return {} end
  local m = overlayRecords(data.maps, data.gen2Maps)
  return overlayRecords(m, data.game3Maps)
end

function Gen.tilesets(data)
  if type(data) ~= "table" then return {} end
  local t = overlayRecords(data.tilesets, data.gen2Tilesets)
  return overlayRecords(t, data.game3Tilesets)
end

-- Point the Gen 2 Data keys at the tables Data:load already filled
function Gen.bindGoldData(data)
  if type(data) ~= "table" then return data end
  if data.maps and data.gen2Maps == nil then data.gen2Maps = data.maps end
  if data.tilesets and data.gen2Tilesets == nil then
    data.gen2Tilesets = data.tilesets
  end
  if data.palettes and data.gen2Palettes == nil then
    data.gen2Palettes = data.palettes
  end

  local loadGen = function(rel)
    local CacheFs = require("src.import.CacheFs")
    local bytes = CacheFs.readActive("data/generated/" .. rel .. ".lua")
    if type(bytes) == "string" then
      local chunk = loadstring(bytes, "@gold/data/generated/" .. rel .. ".lua")
      if chunk then
        local ok, res = pcall(chunk)
        if ok and type(res) == "table" then return res end
      end
    end
    local ok, res = pcall(require, "data.generated." .. rel)
    if ok and type(res) == "table" then return res end
    return nil
  end

  data.gen2Palettes = data.gen2Palettes or loadGen("palettes")
  data.gen2Constants = data.gen2Constants or loadGen("constants")
  data.gen2Icons = data.gen2Icons or loadGen("icons")
  data.gen2Pokedex = data.gen2Pokedex or loadGen("pokedex")
  data.gen2Landmarks = data.gen2Landmarks or loadGen("landmarks")
  data.gen2Roofs = data.gen2Roofs or loadGen("roofs") or data.roofs
  data.gen2Sprites = data.gen2Sprites or loadGen("sprites")
  return data
end

function Gen.game3CacheReady()
  local RomText = require("src.core.game3.rom_text")
  if RomText.has(RomText.key("gNatureNamePointers", 0)) then return true end
  require("src.core.game3.scripting.space").bundle = nil
  return false
end

function Gen.missingCacheMessage(version)
  local info = GameVersion.info(versionOf(nil, version))
  local label = tostring((info and info.label) or "FireRed")
  return ("No imported %s ROM cache found. Import the %s ROM from the launcher, then open this save again."):format(label, label)
end

-- Bind Game 3 (FireRed) data into Data table for Save Editor
function Gen.bindGame3Data(data)
  if type(data) ~= "table" then return data end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset then
    if Dataset.mountExtractRoots then pcall(Dataset.mountExtractRoots) end
    local okM, g3Maps = pcall(Dataset.buildMaps)
    if okM and g3Maps then
      local cache = Dataset.cache and Dataset.cache()
      if cache and Dataset.attachMidLayouts then
        pcall(Dataset.attachMidLayouts, g3Maps, cache)
      end
      local okN, NativeTileset = pcall(require, "src.core.game3.tileset_native")
      if okN and NativeTileset and NativeTileset.install and cache then
        pcall(NativeTileset.install, cache, nil)
      end
      data.game3Maps = g3Maps
      data.maps = overlayRecords(data.maps, g3Maps)
    end
  end

  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if okP and Pokemon then
    pcall(Pokemon.install, nil)
    data.pokemon = data.pokemon or {}
    for id = 1, Pokemon.SPECIES_EGG - 1 do
      local okN, name = pcall(Pokemon.name, id)
      if okN and name and name ~= "??????????" and name ~= "" then
        local def = {
          id = name,
          name = name,
          species = id,
          speciesId = id,
          dex = id,
          growthRate = (Pokemon.speciesMeta and Pokemon.speciesMeta(id) and Pokemon.speciesMeta(id).growthRate) or 0,
        }
        data.pokemon[name] = def
        data.pokemon[id] = def
      end
    end

    data.moves = data.moves or {}
    local okB, BuiltinMoves = pcall(require, "src.core.game3.battle.builtin_moves")
    for id = 1, 354 do
      local mName = Pokemon.moveName(id)
      local bMove = Pokemon.battleMove(id) or (okB and BuiltinMoves and BuiltinMoves[id])
      if mName and mName ~= "-------" and not mName:find("^MOVE %d+") then
        local mDef = {
          id = mName,
          moveId = id,
          name = mName,
          pp = (bMove and tonumber(bMove.pp)) or 10,
          power = (bMove and tonumber(bMove.power)) or 40,
          type = (bMove and bMove.type) or "NORMAL",
        }
        data.moves[mName] = mDef
        data.moves[id] = mDef
      end
    end
  end

  local okI, ItemsData = pcall(require, "src.core.game3.items_data")
  if okI and ItemsData then
    data.items = data.items or {}
    for k, v in pairs(ItemsData.BY_HOST or {}) do
      local iDef = { id = k, name = v.name or k, pocket = v.pocket, itemId = v.frlg }
      data.items[k] = iDef
    end
    for num = 1, 375 do
      local okInf, info = pcall(ItemsData.info, num)
      if okInf and info and info.name and info.name ~= "none" and info.name ~= "" then
        local normName = info.name:upper():gsub("[^A-Z0-9_]", "_"):gsub("_+", "_")
        local iDef = { id = normName, name = info.name, pocket = info.pocket, itemId = num }
        data.items[normName] = iDef
        data.items[num] = iDef
        data.items[tostring(num)] = iDef
      end
    end
  end

  return data
end

function Gen.newGame(version)
  local id = type(version) == "string" and GameVersion.VERSIONS[version] and version
    or nil
  local g = versionGeneration(id) or GameVersion.generation()
  if g == 3 then
    return require("src.core.game3.save_schema_firered").newGame({ version = id })
  elseif g == 2 then
    local Save2 = require("src.core.gen2.Save")
    local save = Save2.newGame({
      playerName = id and Save2.defaultPlayerName(id) or nil,
    })
    if id then save.version = id end
    return save
  end
  return require("src.core.SaveData").newGame({ version = id })
end

function Gen.validate(save, data)
  local g = Gen.of(save)
  if g == 3 then
    return { lostMons = {}, lostItems = {}, remappedMaps = {} }
  elseif g == 2 then
    return require("src.core.gen2.Save").validate(save)
  end
  return require("src.core.SaveData").validate(save, data)
end

function Gen.emptyReport(save, report)
  local g = Gen.of(save)
  if g == 3 then
    if not report then return true end
    return #(report.lostMons or {}) == 0 and #(report.lostItems or {}) == 0 and #(report.remappedMaps or {}) == 0
  elseif g == 2 then
    return require("src.core.gen2.Save").emptyReport(report)
  end
  return require("src.core.SaveData").emptyReport(report)
end

function Gen.hydrateMon(data, mon)
  if type(mon) ~= "table" then return mon end
  local isG3 = mon.speciesId ~= nil or mon.personality ~= nil or mon.ivs ~= nil or (mon.evs ~= nil and mon.evs.spa ~= nil)
  if isG3 then
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    if okP and Pokemon then
      require("src.core.game3.save_mon").normalize(mon)
      local spId = Pokemon.speciesOf(mon)
      if spId then
        mon.speciesId = spId
        local name = Pokemon.name(spId)
        if name and name ~= "" and name ~= "??????????" then
          mon.species = spId
          mon.name = mon.name or name
          mon.speciesNumbering = Pokemon.NUMBERING_INTERNAL
        end
      end
      mon.ivs = mon.ivs or { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
      mon.evs = mon.evs or { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
      mon.dvs = mon.dvs or {
        attack = math.floor((mon.ivs.atk or 0) / 2),
        defense = math.floor((mon.ivs.def or 0) / 2),
        speed = math.floor((mon.ivs.spe or 0) / 2),
        special = math.floor(((mon.ivs.spa or 0) + (mon.ivs.spd or 0)) / 4),
        hp = math.floor((mon.ivs.hp or 0) / 2),
      }
      require("src.core.game3.save_mon").normalize(mon)
    end
    return mon
  end
  local def = data and data.pokemon and data.pokemon[mon.species]
  local gen2 = (mon.stats and mon.stats.specialAttack)
    or (def and def.baseStats and def.baseStats.specialAttack)
    or mon.experience ~= nil
  if gen2 then
    require("src.battle.gen2.Mon").refreshStats(mon, data)
  else
    require("src.pokemon.Stats").ensure(def, mon)
  end
  return mon
end

function Gen.hydrateSave(data, save)
  if type(save) ~= "table" then return save end
  local g = Gen.of(save)
  if g == 3 then
    require("Game3Adapter").hydrate(data, save)
    local Mons = require("src.core.game3.save_mon")
    Mons.each(save, function(mon) Mons.normalize(mon); Gen.hydrateMon(data, mon) end)
    return save
  elseif g == 2 then
    local Mon = require("src.battle.gen2.Mon")
    Mon.eachSaveMon(save, function(mon) Mon.refreshStats(mon, data) end)
    return save
  end
  for _, mon in ipairs(save.party or {}) do Gen.hydrateMon(data, mon) end
  for _, box in ipairs(save.boxes or {}) do
    if type(box) == "table" then
      for _, mon in ipairs(box) do Gen.hydrateMon(data, mon) end
    end
  end
  if save.daycare and save.daycare.mon then
    Gen.hydrateMon(data, save.daycare.mon)
  end
  return save
end

function Gen.ensureBoxes(save)
  local g = Gen.of(save)
  if g == 3 then
    return require("Game3Adapter").ensureStorage(save)
  elseif g == 2 then
    local Boxes2 = require("src.core.gen2.Boxes")
    save.boxes = save.boxes or {}
    for i = 1, Boxes2.NUM_BOXES do
      save.boxes[i] = save.boxes[i] or {}
    end
    save.currentBox = math.max(1, math.min(Boxes2.NUM_BOXES, save.currentBox or 1))
    return save.boxes
  end
  return require("src.pokemon.Boxes").ensure(save)
end

function Gen.boxCount(save)
  local g = Gen.of(save)
  if g == 3 then return 14 end
  if g == 2 then return require("src.core.gen2.Boxes").NUM_BOXES end
  return require("src.pokemon.Boxes").COUNT
end

function Gen.boxCapacity(save)
  local g = Gen.of(save)
  if g == 3 then return 30 end
  if g == 2 then return require("src.core.gen2.Boxes").MONS_PER_BOX end
  return require("src.pokemon.Boxes").CAPACITY
end

function Gen.money(save)
  if type(save) ~= "table" then return 0 end
  if Gen.of(save) == 2 then
    return (save.player and save.player.money) or 0
  end
  return save.money or 0
end

function Gen.setMoney(save, amount)
  if type(save) ~= "table" then return end
  if Gen.of(save) == 2 then
    save.player = save.player or {}
    save.player.money = amount
  else
    save.money = amount
  end
end

function Gen.coins(save)
  if type(save) ~= "table" then return 0 end
  if Gen.of(save) == 2 then
    return (save.player and save.player.coins) or 0
  end
  return save.coins or 0
end

function Gen.setCoins(save, amount)
  if type(save) ~= "table" then return end
  if Gen.of(save) == 2 then
    save.player = save.player or {}
    save.player.coins = amount
  else
    save.coins = amount
  end
end

function Gen.playerGender(save)
  if type(save) ~= "table" then return "male" end
  if save.gender == 1 or (save.player and (save.player.gender == 1 or save.player.gender == "female")) then
    return "female"
  end
  return "male"
end

function Gen.setPlayerGender(save, gender)
  if type(save) ~= "table" then return "male" end
  local isFemale = (gender == "female" or gender == 1)
  save.gender = isFemale and 1 or 0
  if save.player then
    save.player.gender = isFemale and "female" or "male"
  end
  return isFemale and "female" or "male"
end

function Gen.landmarkName(data, index)
  index = math.floor(tonumber(index) or 0)
  local Mon = require("src.battle.gen2.Mon")
  if index == Mon.LANDMARK_EVENT then return "EVENT" end
  if index == Mon.LANDMARK_GIFT then return "GIFT" end
  if index == 0 then return "UNKNOWN" end
  local rows = data and data.gen2Landmarks and data.gen2Landmarks.landmarks
  for _, rec in pairs(rows or {}) do
    if type(rec) == "table" and rec.index == index then
      return (tostring(rec.name or rec.id):gsub("\n", " "))
    end
  end
  return ("#%d"):format(index)
end

function Gen.dexOwnedKey(save)
  if Gen.of(save) == 2 then return "caught" end
  return "owned"
end

function Gen.playerMap(save)
  if type(save) ~= "table" then return "FR_PALLET_TOWN", 0, 0 end
  local g = Gen.of(save)
  if g == 3 then
    local map = save.map or (save.position and save.position.map) or (save.player and save.player.map) or "FR_PALLET_TOWN"
    local x = save.x or (save.position and save.position.x) or (save.player and save.player.x) or 0
    local y = save.y or (save.position and save.position.y) or (save.player and save.player.y) or 0
    local facing = save.facing or (save.position and save.position.facing) or "down"
    return map, x, y, facing
  elseif g == 2 then
    local p = save.position
    if p and p.map then return p.map, p.x or 0, p.y or 0, p.facing end
    if type(save.spawn) == "table" then
      return save.spawn.map or "PLAYERS_HOUSE_2F", save.spawn.x or 0, save.spawn.y or 0, save.spawn.facing
    elseif type(save.spawn) == "string" then
      return save.spawn, 0, 0
    end
    return "PLAYERS_HOUSE_2F", 3, 3
  end
  local p = save.player or {}
  return p.map or "REDS_HOUSE_2F", p.x or 0, p.y or 0
end

function Gen.setPlayerHere(save, mapId, x, y, facing)
  if type(save) ~= "table" then return end
  local g = Gen.of(save)
  if g == 3 then
    save.map = mapId
    save.x = x
    save.y = y
    save.facing = facing or save.facing or "down"
    save.position = {
      map = mapId,
      x = x,
      y = y,
      facing = save.facing,
    }
    if save.player then
      save.player.map = mapId
      save.player.x = x
      save.player.y = y
    end
    return
  elseif g == 2 then
    local prev = save.position or {}
    save.position = {
      map = mapId,
      x = x,
      y = y,
      facing = facing or prev.facing or "down",
    }
    return
  end
  save.player = save.player or {}
  save.player.map = mapId
  save.player.x = x
  save.player.y = y
end

local JOHTO = {
  "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING",
}
local KANTO = {
  "BOULDER", "CASCADE", "THUNDER", "RAINBOW",
  "SOUL", "MARSH", "VOLCANO", "EARTH",
}

function Gen.badgeIds(save, cat)
  local g = Gen.of(save)
  if g == 3 then
    local ids = {}
    for _, name in ipairs(KANTO) do ids[#ids + 1] = name .. "BADGE" end
    return ids
  elseif g == 2 then
    local ids = {}
    for _, name in ipairs(JOHTO) do ids[#ids + 1] = name end
    for _, name in ipairs(KANTO) do ids[#ids + 1] = name end
    return ids
  end
  local ids = {}
  for _, id in ipairs((cat and cat.items) or {}) do
    if tostring(id):find("BADGE", 1, true) then ids[#ids + 1] = id end
  end
  return ids
end

local KANTO_SET = {}
for _, name in ipairs(KANTO) do KANTO_SET[name] = true end

function Gen.hasBadge(save, id)
  if type(save) ~= "table" then return false end
  local g = Gen.of(save)
  if g == 3 then
    local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
    if okF and Flags then
      return Flags.hasBadge(save, id)
    end
    return save.flags and (save.flags[id] or save.flags[id:gsub("BADGE$", "")]) == true
  elseif g == 2 then
    local p = save.player or {}
    local store = KANTO_SET[id] and (p.kantoBadges or {}) or (p.badges or {})
    if store[id] then return true end
    local list = KANTO_SET[id] and KANTO or JOHTO
    for index, name in ipairs(list) do
      if name == id then return store[index] == true end
    end
    return false
  end
  return save.inventory and save.inventory[id] and true or false
end

function Gen.toggleBadge(save, id)
  if type(save) ~= "table" then return false end
  local g = Gen.of(save)
  if g == 3 then
    local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
    if okF and Flags then
      local on = Flags.hasBadge(save, id)
      Flags.setBadge(save, id, not on)
      return not on
    end
    local on = Gen.hasBadge(save, id)
    save.flags = save.flags or {}
    save.flags[id] = (not on) and true or nil
    return not on
  elseif g == 2 then
    save.player = save.player or {}
    local storeName = KANTO_SET[id] and "kantoBadges" or "badges"
    save.player[storeName] = save.player[storeName] or {}
    local store = save.player[storeName]
    local on = Gen.hasBadge(save, id)
    store[id] = (not on) and true or nil
    for index, name in ipairs(KANTO_SET[id] and KANTO or JOHTO) do
      if name == id then store[index] = nil end
    end
    return not on
  end
  save.inventory = save.inventory or {}
  local on = save.inventory[id] and true or false
  save.inventory[id] = (not on) and 1 or nil
  return not on
end

local function gen2FlagId(save, name)
  return require("Gen2Flags").byName(Gen.engineOf(save))[name]
end

function Gen.getFlag(save, name)
  if type(save) ~= "table" then return false end
  local g = Gen.of(save)
  if g == 3 then
    local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
    if okF and Flags then
      return Flags.getFlag(save, nil, name)
    end
    return save.flags and (save.flags[name] == true or save.flags[tostring(name)] == true)
  elseif g == 2 then
    local id = gen2FlagId(save, name)
    if id then
      local Events2 = require("src.world.gen2.Events")
      local ev = Events2.new()
      ev:restore(save.events)
      return ev:get(id)
    end
    return save.flags and save.flags[name] == true
  end
  return save.flags and save.flags[name] == true
end

function Gen.setFlag(save, name, on)
  if type(save) ~= "table" then return end
  local g = Gen.of(save)
  if g == 3 then
    local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
    if okF and Flags then
      Flags.setFlag(save, nil, name, on)
      return
    end
    save.flags = save.flags or {}
    save.flags[name] = on and true or nil
    return
  elseif g == 2 then
    local id = gen2FlagId(save, name)
    if id then
      local Events2 = require("src.world.gen2.Events")
      local ev = Events2.new()
      ev:restore(save.events)
      ev:set(id, on and true or false)
      save.events = ev:serialize()
      return
    end
    save.flags = save.flags or {}
    save.flags[name] = on and true or nil
    return
  end
  save.flags = save.flags or {}
  save.flags[name] = on and true or nil
end

function Gen.getVar(save, nameOrId)
  if type(save) ~= "table" then return 0 end
  local g = Gen.of(save)
  if g == 3 then
    local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
    if okF and Flags then
      return Flags.getVar(save, nil, nameOrId)
    end
    if save.vars then
      return save.vars[nameOrId] or save.vars[tonumber(nameOrId)] or save.vars[tostring(nameOrId)] or 0
    end
  end
  return 0
end

function Gen.setVar(save, nameOrId, val)
  if type(save) ~= "table" then return end
  val = math.max(0, math.min(65535, math.floor(tonumber(val) or 0)))
  local g = Gen.of(save)
  if g == 3 then
    local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
    if okF and Flags then
      Flags.setVar(save, nil, nameOrId, val)
      return
    end
    save.vars = save.vars or {}
    save.vars[nameOrId] = val
    if tonumber(nameOrId) then
      save.vars[tonumber(nameOrId)] = val
    end
  end
end

function Gen.flagCount(save)
  if type(save) ~= "table" then return 0 end
  local g = Gen.of(save)
  if g == 2 then
    local n = 0
    for _ in pairs(save.events or {}) do n = n + 1 end
    for _ in pairs(save.flags or {}) do n = n + 1 end
    return n
  end
  local n = 0
  for _ in pairs(save.flags or {}) do n = n + 1 end
  return n
end

function Gen.exp(mon)
  return mon.exp or mon.experience or 0
end

return Gen
