package.path = "./?.lua;./?/init.lua;./tools/save-editor/?.lua;" .. package.path
love = require("tests.love_stub")

local S = require("tests.harness").suite("gen2 dataset builders install builtins")
local check = S.check

local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local Merge = require("src.mods.Merge")
local PHONE = require("tests.fixtures.gen2_phone_events")
local ArenaData = require("src.online.ArenaData")
local Gen = require("tools.save-editor.Gen")
local Phone = require("src.core.gen2.Phone")

local function fakeRegistry()
  local rows = {}
  return { rows = rows, register = function(_, id, row) rows[id] = row end }
end

local order = {}
for index in pairs(PHONE.events.phone) do
  while #order < index do order[#order + 1] = "PHONE_UNUSED" end
  order[index + 1] = ("PHONE_%02d"):format(index)
end
local files = {
  constants = { phoneContactOrder = order, rematchFlags = PHONE.constants.rematchFlags,
    trainerClassOrder = PHONE.constants.trainerClassOrder,
    trainerClassMembers = PHONE.constants.trainerClassMembers },
  events = Merge.deepCopy(PHONE.events),
}

local realRead, realLoad = CacheFs.readActive, CacheFs.loadActive
CacheFs.readActive = function(rel)
  local name = rel:match("^data/generated/(.-)%.lua$")
  return files[name] and Serializer.encode(files[name]) or nil
end
CacheFs.loadActive = function(rel)
  local bytes = CacheFs.readActive(rel)
  return bytes and assert(loadstring(bytes))() or nil
end
GameVersion.set("gold")

local arena = ArenaData.gen2Dataset()
check(type(arena.gen2EventTables) == "table" and type(arena.gen2EventTables.phone) == "table",
  "the arena dataset carries events.lua")
local okArena, arenaCount = pcall(Phone.registerInto, fakeRegistry(), arena, "builtin")
check(okArena and arenaCount > 0, "and the builtin phone install runs over it (" .. tostring(arenaCount) .. ")")

local editor = Gen.bindGoldData({})
check(type(editor.gen2EventTables) == "table" and type(editor.gen2EventTables.phone) == "table",
  "the save editor dataset carries events.lua")
local okEditor, editorCount = pcall(Phone.registerInto, fakeRegistry(), editor, "builtin")
check(okEditor and editorCount > 0, "and the builtin phone install runs over it (" .. tostring(editorCount) .. ")")

files.events = nil
local okMissing = pcall(Phone.registerInto, fakeRegistry(), Gen.bindGoldData({}), "builtin")
check(not okMissing, "a cache without events.lua is an error, not an empty phone book")

CacheFs.readActive, CacheFs.loadActive = realRead, realLoad

local CacheRoot = require("tests.cache_gen2_constants")
local ran = 0
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local root = CacheRoot.root(version)
  if not root then
    print("[skip] no " .. version .. " cache")
  else
    ran = ran + 1
    local identity = root:sub(1, #root - #version - 1)
    love.filesystem.read = function(rel)
      local handle = io.open(identity .. "/" .. rel, "rb")
      if not handle then return nil end
      local body = handle:read("*a")
      handle:close()
      return body, #body
    end
    GameVersion.set(version)
    local Loader = require("src.mods.Loader")

    local data = ArenaData.gen2Dataset()
    local ok, err = pcall(function()
      return Loader.new({ generation = 2 }):load(data, { mode = "disableAll" })
    end)
    check(ok, version .. ": the arena dataset installs every builtin" .. (ok and "" or (": " .. tostring(err))))
    if Loader.endSession then pcall(Loader.endSession) end

    local savedData = package.loaded["src.core.Data"]
    package.loaded["src.core.Data"] = nil
    local Data = require("src.core.Data")
    local okEd, errEd = pcall(function()
      Data:load()
      Gen.bindGoldData(Data)
      return Loader.new():load(Data)
    end)
    check(okEd, version .. ": the save editor dataset installs every builtin" .. (okEd and "" or (": " .. tostring(errEd))))
    if Loader.endSession then pcall(Loader.endSession) end
    pcall(Data.unloadGenerated, Data)
    package.loaded["src.core.Data"] = savedData
  end
end
if ran == 0 then print("[skip] gen2 dataset builtins: no Gen 2 cache") end

S.finish()
