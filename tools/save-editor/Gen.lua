-- Generation adapter for the save editor.  Panels stay generation-blind;
-- Ops and App read Gold vs RBY through this module so a Gold write never
-- lands in Gen 1 fields (save.money, pokedex.owned, 12 boxes, ...).

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
  return tostring((info and info.label) or "GEN 2"):upper()
end

function Gen.hasCaughtData(save, version)
  if Gen.of(save, version) ~= 2 then return false end
  return require("src.battle.gen2.Mon").hasCaughtData(versionOf(save, version))
end

-- engine/menus/init_gender.asm:23-38
function Gen.hasPlayerGender(save, version)
  if Gen.of(save, version) ~= 2 then return false end
  return Gen.engineOf(save, version) == "crystal"
end

function Gen.ofState(S)
  if not S then return GameVersion.generation() end
  return Gen.of(S.save, S.version)
end

function Gen.is2(save, version)
  return Gen.of(save, version) == 2
end

-- Data:load writes Gold maps/tilesets to the Gen 1 keys; Game2 and the mod
-- merge write gen2Maps / gen2Tilesets.  Overlay the gen2 table on the loaded
-- cache so a mod patch that landed on an empty gen2Maps (objects only, no
-- width) does not hide the extractor's record, and a new map like BERRY_FARM
-- still appears.
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
  return overlayRecords(data.maps, data.gen2Maps)
end

function Gen.tilesets(data)
  if type(data) ~= "table" then return {} end
  return overlayRecords(data.tilesets, data.gen2Tilesets)
end

-- Point the Gen 2 Data keys at the tables Data:load already filled, before
-- mods:load folds into gen2Maps.  Same wiring Game2 does when it boots Gold.
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
  -- Namespaced AND differently shaped in Schemas.GEN2 (the cart's ordered
  -- name lists, not Gen 1's rule table), same as palettes/icons below --
  -- omitting it left mod.content.constants:get(...) reading an empty table
  -- under a Gold save-editor boot, which is what misreads "generation" and
  -- rejects every record a mod shapes off it.
  data.gen2Constants = data.gen2Constants or loadGen("constants")
  data.gen2Icons = data.gen2Icons or loadGen("icons")
  data.gen2Pokedex = data.gen2Pokedex or loadGen("pokedex")
  data.gen2Landmarks = data.gen2Landmarks or loadGen("landmarks")
  data.gen2Roofs = data.gen2Roofs or loadGen("roofs") or data.roofs
  data.gen2Sprites = data.gen2Sprites or loadGen("sprites")
  return data
end

function Gen.newGame(version)
  local id = type(version) == "string" and GameVersion.VERSIONS[version] and version
    or nil
  if (versionGeneration(id) or GameVersion.generation()) == 2 then
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
  if Gen.of(save) == 2 then
    return require("src.core.gen2.Save").validate(save)
  end
  return require("src.core.SaveData").validate(save, data)
end

function Gen.emptyReport(save, report)
  if Gen.of(save) == 2 then
    return require("src.core.gen2.Save").emptyReport(report)
  end
  return require("src.core.SaveData").emptyReport(report)
end

function Gen.hydrateMon(data, mon)
  if type(mon) ~= "table" then return mon end
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

-- Party, boxes, Day-Care.  Gold's dayCare.man/lady/egg are not save.daycare.
function Gen.hydrateSave(data, save)
  if type(save) ~= "table" then return save end
  if Gen.of(save) == 2 then
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
  if Gen.of(save) == 2 then
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
  if Gen.of(save) == 2 then
    return require("src.core.gen2.Boxes").NUM_BOXES
  end
  return require("src.pokemon.Boxes").COUNT
end

function Gen.boxCapacity(save)
  if Gen.of(save) == 2 then
    return require("src.core.gen2.Boxes").MONS_PER_BOX
  end
  return require("src.pokemon.Boxes").CAPACITY
end

function Gen.money(save)
  if Gen.of(save) == 2 then
    return (save.player and save.player.money) or 0
  end
  return save.money or 0
end

function Gen.setMoney(save, amount)
  if Gen.of(save) == 2 then
    save.player = save.player or {}
    save.player.money = amount
  else
    save.money = amount
  end
end

function Gen.coins(save)
  if Gen.of(save) == 2 then
    return (save.player and save.player.coins) or 0
  end
  return save.coins or 0
end

function Gen.setCoins(save, amount)
  if Gen.of(save) == 2 then
    save.player = save.player or {}
    save.player.coins = amount
  else
    save.coins = amount
  end
end

-- constants/ram_constants.asm:176-177
function Gen.playerGender(save)
  local stored = save and save.player and save.player.gender
  return stored == "female" and "female" or "male"
end

function Gen.setPlayerGender(save, gender)
  save.player = save.player or {}
  save.player.gender = (gender == "female") and "female" or "male"
  return save.player.gender
end

-- constants/landmark_constants.asm:3, :111-113
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
  if Gen.of(save) == 2 then
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
  if Gen.of(save) == 2 then
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
  if Gen.of(save) == 2 then
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
  if Gen.of(save) == 2 then
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
  if Gen.of(save) == 2 then
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
  local on = save.inventory[id] and true or false
  save.inventory[id] = (not on) and 1 or nil
  return not on
end

local function gen2FlagId(save, name)
  return require("Gen2Flags").byName(Gen.engineOf(save))[name]
end

function Gen.getFlag(save, name)
  if Gen.of(save) == 2 then
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
  if Gen.of(save) == 2 then
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

function Gen.flagCount(save)
  if Gen.of(save) == 2 then
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
  return mon.experience or mon.exp or 0
end

return Gen
