package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local SyncEngine = require("src.sync.SyncEngine")

local realFS = love.filesystem

local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    createDirectory = function() return true end,
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

local function slotOnDisk(files, slotId)
  local body = files["saves/red/" .. slotId .. ".lua"]
  return body and SaveSerializer.decode(body) or nil
end

local function opaque(id)
  return type(id) == "string" and #id == 32 and id:match("^%x+$") ~= nil
end

do
  local files = fresh()
  local provider = SyncEngine.defaultSaves()
  T.eq(#provider.list(), 0, "a fresh install has nothing to sync")

  local slotId = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", slotId)
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta({}, save.meta, os.time() - 60)
  T.check(SaveData.save(save), "a vanilla in-game save lands")
  T.eq(slotOnDisk(files, slotId).meta.playthroughId, nil,
    "a save nobody has synced or tooled carries no identity yet")

  local entries = provider.list()
  T.eq(#entries, 1, "a vanilla slot is synced without a mod")
  local id = entries[1] and entries[1].playthroughId
  T.check(opaque(id), "under an opaque 32-hex identity")
  T.eq(entries[1] and entries[1].slot, slotId, "from the slot the game saved into")
  T.eq(SaveData.loadOptions().playthroughIds.red[slotId], id,
    "the identity is persisted as that slot's mapping")
  T.eq(provider.list()[1].playthroughId, id,
    "and a second listing answers the same id")
  T.eq(slotOnDisk(files, slotId).meta.playthroughId, nil,
    "listing never rewrites the progress bytes")

  save.money = 777
  T.check(SaveData.save(save), "the next in-game save")
  T.eq(slotOnDisk(files, slotId).meta.playthroughId, id,
    "stamps the mapped identity into the progress meta")
  T.eq(save.meta.playthroughId, id, "and onto the live save")
  T.eq(SaveData.loadOptions().playthroughIds.red[slotId], id,
    "while the stale in-game options snapshot leaves the mapping alone")
  T.eq(provider.list()[1].playthroughId, id, "so the sync key never moves")
end

do
  fresh()
  local provider = SyncEngine.defaultSaves()
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta(nil, { format = "gen1_import", mods = {} })
  local slot = SaveData.createSlot("red")
  T.check(SaveData.writeSlot("red", slot, save), "an imported .sav slot writes")
  SaveData.setActiveSlot("red", slot)

  local entries = provider.list()
  T.eq(#entries, 1, "an imported .sav is uploaded")
  T.eq(entries[1] and entries[1].slot, slot, "from its own slot")
  T.check(opaque(entries[1] and entries[1].playthroughId),
    "under an identity minted for it")
end

do
  fresh()
  local provider = SyncEngine.defaultSaves()
  local shared = ("ab"):rep(16)
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta(nil,
    { format = "gen1_import", mods = {}, playthroughId = shared })
  local slot = SaveData.createSlot("red")
  SaveData.writeSlot("red", slot, save)
  SaveData.setActiveSlot("red", slot)

  local entries = provider.list()
  T.eq(entries[1] and entries[1].playthroughId, shared,
    "an identity stamped by the import wins over minting a new one")
  T.eq(SaveData.loadOptions().playthroughIds.red[slot], shared,
    "and is mapped to its slot so a replace can find it")

  local theirs = SaveData.newGame()
  theirs.player.name = "ASH"
  theirs.money = 5
  theirs.meta = SaveData.buildMeta({}, { playthroughId = shared }, os.time() - 10)
  local wrote, created = provider.write("red", shared, SaveData.encode(theirs), "replace")
  T.eq(wrote, slot, "the other device's copy replaces the imported slot in place")
  T.eq(created, false, "and reports that no slot was created")
  T.eq(#SaveData.listSlots("red"), 1, "leaving one slot")
  T.eq(SaveData.load("red").money, 5, "holding the downloaded progress")

  local stranger = SaveData.newGame()
  stranger.player.name = "BLUE"
  stranger.meta = SaveData.buildMeta({}, { playthroughId = ("cd"):rep(16) })
  local newSlot, made = provider.write("red", ("cd"):rep(16),
    SaveData.encode(stranger), "replace")
  T.check(newSlot ~= nil and newSlot ~= slot, "an unknown playthrough gets its own slot")
  T.eq(made, true, "and reports the slot as created")
  T.eq(SaveData.activeSlot("red"), slot, "without becoming the slot CONTINUE loads")
end

do
  fresh()
  local slot1 = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", slot1)
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta({}, save.meta, os.time() - 60)
  T.check(SaveData.save(save), "first in-game save")

  local slot2 = SyncEngine.defaultSaves().write("red", "idA", SaveData.encode(save), "replace")
  T.check(slot2 ~= nil and slot2 ~= slot1,
    "sync lands the other playthrough in a second slot mid-session")
  local opts = SaveData.loadOptions()
  T.eq(#opts.saveSlots.red.list, 2, "the registry holds both slots after the download")
  T.eq(opts.playthroughIds.red[slot2], "idA", "and the mapping for slot2")

  save.money = 999
  T.check(SaveData.save(save), "second in-game save")
  opts = SaveData.loadOptions()
  T.eq(#opts.saveSlots.red.list, 2, "slot2 registration survives an in-game save")
  T.eq(opts.playthroughIds.red[slot2], "idA",
    "slot2 identity mapping survives an in-game save")
  T.eq(opts.saveSlots.red.active, slot1, "without moving the active slot")
  T.eq(SaveData.load("red").money, 999, "and the progress itself was written")
end

do
  fresh()
  local slot1 = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", slot1)
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta({}, save.meta, os.time() - 60)
  T.check(SaveData.save(save), "in-game save before the download")

  local slot2 = SyncEngine.defaultSaves().write("red", "idA", SaveData.encode(save), "replace")
  T.check(slot2 ~= nil and slot2 ~= slot1, "sync lands a second slot mid-session")

  local Game = require("src.core.Game")
  local game = setmetatable({ save = save }, { __index = Game })
  save.options.textSpeed = 1
  Game.writeOptions(game)
  local opts = SaveData.loadOptions()
  T.eq(opts.textSpeed, 1, "an Options menu write lands the live setting")
  T.eq(#opts.saveSlots.red.list, 2,
    "slot2 registration survives an Options menu write")
  T.eq(opts.playthroughIds.red[slot2], "idA",
    "slot2 identity mapping survives an Options menu write")
end

do
  fresh()
  local slot = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", slot)
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta({}, save.meta, os.time() - 60)
  save.options.textSpeed = 1
  T.check(SaveData.save(save), "an in-game save with a live options change")
  T.eq(SaveData.loadOptions().textSpeed, 1,
    "still writes the player's live settings")
  T.eq(SaveData.loadOptions().playthroughIds, nil,
    "and mints no identity of its own")
end

do
  local files = fresh()
  local provider = SyncEngine.defaultSaves()
  local keep = SaveData.createSlot("red")
  local slot = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", keep)
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta({}, save.meta, os.time() - 60)
  T.check(SaveData.save(save), "the kept slot saves")
  SaveData.setActiveSlot("red", slot)
  save = SaveData.newGame()
  save.player.name = "GONE"
  save.meta = SaveData.buildMeta({}, save.meta, os.time() - 30)
  T.check(SaveData.save(save), "the doomed slot saves")
  T.eq(#provider.list(), 2, "both slots sync")
  local ids = SaveData.loadOptions().playthroughIds.red
  local keptId, goneId = ids[keep], ids[slot]
  T.check(opaque(keptId) and opaque(goneId) and keptId ~= goneId,
    "under two identities")

  T.check(SaveData.deleteSlot("red", slot), "the doomed slot is deleted")
  ids = SaveData.loadOptions().playthroughIds.red
  T.eq(ids[slot], nil, "deleting a slot forgets its playthrough mapping")
  T.eq(ids[keep], keptId, "and leaves the other slot's mapping alone")

  local again = SaveData.createSlot("red")
  T.eq(again, slot, "the next new slot reuses the id")
  SaveData.setActiveSlot("red", again)
  local fresh = SaveData.newGame()
  fresh.player.name = "NEW"
  fresh.meta = SaveData.buildMeta({}, fresh.meta, os.time() - 10)
  T.check(SaveData.save(fresh), "a New Game in the recreated slot saves")
  T.eq(slotOnDisk(files, again).meta.playthroughId, nil,
    "without inheriting the deleted playthrough's identity")
  local entries = provider.list()
  T.eq(#entries, 2, "and syncs")
  for _, entry in ipairs(entries) do
    T.neq(entry.playthroughId, goneId,
      "under a key that is not the deleted playthrough's (" .. entry.slot .. ")")
  end

  T.check(SaveData.deleteSlot("red", again), "deleting the recreated slot")
  T.check(SaveData.deleteSlot("red", keep), "and the kept slot")
  T.eq(SaveData.loadOptions().playthroughIds, nil,
    "leaves no playthrough mappings behind")
end

love.filesystem = realFS
SaveData.resetSlotState()
GameVersion.set("red")

do
  fresh()
  local provider = SyncEngine.defaultSaves()
  local slotId = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", slotId)
  local save = SaveData.newGame()
  save.player.name = "ASH"
  save.meta = SaveData.buildMeta({}, save.meta, os.time() - 60)
  SaveData.save(save)
  local id = provider.list()[1].playthroughId
  T.eq(provider.keyForSlot("red", slotId), "red/" .. id,
    "keyForSlot answers the sync key the launcher deletes under")
  T.eq(provider.keyForSlot("red", "slot9"), nil, "and nil for an empty slot")

  local gone, cart = provider.remove("red", id)
  T.eq(gone, slotId, "remove deletes the slot that carries the playthrough")
  T.eq(cart, nil, "a plain version slot has no cart")
  T.eq(#SaveData.listSlots("red"), 0, "so the slot is gone")
  local ids = SaveData.loadOptions().playthroughIds
  T.eq(((ids or {}).red or {})[slotId], nil,
    "and its identity mapping with it")
  T.eq(#provider.list(), 0, "nothing is left to sync")
  T.eq(provider.remove("red", id), false, "removing it again finds nothing")
end

T.finish("sync_save_identity")
