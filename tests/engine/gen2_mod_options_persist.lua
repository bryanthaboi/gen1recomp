package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local Save = require("src.core.gen2.Save")

local function memfs()
  local files = {}
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] ~= nil then return { type = "file" } end
      return nil
    end,
  }
end

local fs = memfs()
SaveData.saveOptions(SaveData.defaultOptions(), fs)
local opts = Save.loadOptions(fs)
opts.modOptions = { nuzlocke = { dupes = true } }
opts.modProfiles = { { name = "casual", enabled = {} } }
opts.activeProfile = "casual"
opts.mods = { nuzlocke = true }
opts.modsByVersion = { gold = { hardmode = true } }
opts.textSpeed = "SLOW"
check(Save.saveOptions(opts, fs), "gold options write lands")

local file = SaveData.loadOptions(fs)
eq(file.modOptions and file.modOptions.nuzlocke and file.modOptions.nuzlocke.dupes,
  true, "modOptions lands flat where gen1 and the launcher read it")
eq(file.activeProfile, "casual", "activeProfile lands flat")
eq(file.modProfiles and file.modProfiles[1] and file.modProfiles[1].name,
  "casual", "modProfiles lands flat")
eq(file.mods and file.mods.nuzlocke, true, "enable flags land flat")
eq(file.modsByVersion and file.modsByVersion.gold
  and file.modsByVersion.gold.hardmode, true, "per-version flags land flat")
eq(file[Save.OPTIONS_KEY].modOptions, nil, "gold block no longer traps modOptions")
eq(file[Save.OPTIONS_KEY].activeProfile, nil,
  "gold block no longer traps activeProfile")
eq(file[Save.OPTIONS_KEY].textSpeed, "SLOW", "gold-only keys stay in the gold block")

local back = Save.loadOptions(fs)
eq(back.modOptions.nuzlocke.dupes, true, "flat modOptions round-trips into gold's table")
eq(back.activeProfile, "casual", "flat activeProfile round-trips")

local fs2 = memfs()
fs2.files["options.lua"] = [[return { gold = { textSpeed = "FAST",
  modOptions = { nuzlocke = { dupes = true } }, activeProfile = "old" } }]]
local legacy = Save.loadOptions(fs2)
eq(legacy.modOptions and legacy.modOptions.nuzlocke
  and legacy.modOptions.nuzlocke.dupes, true,
  "modOptions trapped in the gold block migrates out")
eq(legacy.activeProfile, "old", "trapped activeProfile migrates")
eq(legacy.textSpeed, "FAST", "gold-only keys still merge")
check(Save.saveOptions(legacy, fs2), "migrated write lands")
local migrated = SaveData.loadOptions(fs2)
eq(migrated.modOptions and migrated.modOptions.nuzlocke.dupes, true,
  "migration lands the trapped store flat")
eq(migrated[Save.OPTIONS_KEY].modOptions, nil, "migration empties the trap")

local fs3 = memfs()
fs3.files["options.lua"] = [[return { modOptions = { nuzlocke = { dupes = false } },
  gold = { modOptions = { nuzlocke = { dupes = true } } } }]]
local both = Save.loadOptions(fs3)
eq(both.modOptions.nuzlocke.dupes, false, "flat modOptions wins over a trapped copy")

local Game2 = require("src.core.Game2")
check(type(Game2.writeOptions) == "function", "Game2 exposes writeOptions")
eq(Game2.writeOptions, Game2.persistOptions, "writeOptions is the persist path")

local ManagerState = require("src.mods.ManagerState")
local wrote = false
ManagerState.persistOptions({ game = { writeOptions = function() wrote = true end } })
check(wrote, "ManagerState:persistOptions writes through game.writeOptions")

T.finish("gen2_mod_options_persist")
