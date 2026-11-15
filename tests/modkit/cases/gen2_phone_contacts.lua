package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Phone = require("src.core.gen2.Phone")
local Events = require("src.world.gen2.Events")
local Vm = require("src.script.gen2.Vm")
local Pokegear = require("src.ui.gen2.Pokegear")
local Serializer = require("src.core.SaveSerializer")

local BODY = [[local mod = ...
local contacts = mod.content.phone_contacts
mod.content.map_scripts:register("mod:callee", {{op="setevent",event=1001},{op="end"}})
mod.content.map_scripts:register("mod:caller", {{op="setevent",event=1002},{op="end"}})
local row = contacts:register("MOD_GUIDE", {name="GUIDE",class="YOUNGSTER",member="JOEY1",
  map="FIX_ROUTE",calleeTime=7,callerTime=7,calleeKey="mod:callee",callerKey="mod:caller",rematchEvent=1000})
mod.exports.index = row.index
assert(type(row.index) == "number")
contacts:register("MOD_EXPLICIT", {index=50,name="SECOND",callerTime=0,calleeTime=0})
assert(not pcall(function() contacts:register("CLASH", {index=50,name="CLASH"}) end))
for _, index in ipairs({0,8,9,10,25,256,-1,1.5}) do
  assert(not pcall(function() contacts:register("BAD", {index=index,name="BAD"}) end))
end
assert(not pcall(function() contacts:patch("MOD_GUIDE", {index=60}) end))
assert(not pcall(function() contacts:register("NO_SCRIPT", {name="BAD",callerTime=7}) end))
assert(not pcall(function() contacts:register("BAD_EVENT", {name="BAD",rematchEvent=2048}) end))
contacts:patch("MOD_GUIDE", {name="GUIDE"})
assert(contacts:get("MOD_GUIDE").index == row.index)
mod.exports.mutations = {}
local checks = mod.exports.mutations
for _, direction in ipairs({"caller", "callee"}) do
  local time, key = direction .. "Time", direction .. "Key"
  local id = "LATE_" .. direction
  contacts:register(id, {name="LATE",callerTime=0,calleeTime=0})
  checks[direction .. " enable patch refused"] = not pcall(function()
    contacts:patch(id, {[time]=7})
  end)
  checks[direction .. " enable override refused"] = not pcall(function()
    contacts:override(id, {name="LATE",[time]=7})
  end)
  checks[direction .. " rejected writes preserve disabled row"] = contacts:get(id)[time] == 0
  checks[direction .. " enabled key deletion refused"] = not pcall(function()
    contacts:patch("MOD_GUIDE", {[key]=mod.DELETE})
  end)
  checks[direction .. " enabled replacement without key refused"] = not pcall(function()
    contacts:override("MOD_GUIDE", {name="GUIDE",[time]=7})
  end)
  contacts:patch("MOD_GUIDE", {[time]=7})
  checks[direction .. " partial patch retains key"] = contacts:get("MOD_GUIDE")[key] == "mod:" .. direction
  contacts:patch(id, {[time]=7,[key]="mod:" .. direction})
  contacts:patch(id, {[time]=0,[key]=mod.DELETE})
  checks[direction .. " disabled key deletion accepted"] = contacts:get(id)[key] == nil
  local native = contacts:get("PHONE_YOUNGSTER_JOEY")
  contacts:patch("PHONE_YOUNGSTER_JOEY", {[time]=7})
  checks[direction .. " native partial patch retains script"] =
    contacts:get("PHONE_YOUNGSTER_JOEY")[key] == native[key]
  contacts:patch("PHONE_YOUNGSTER_JOEY", {[key]=mod.DELETE,
    [direction]=direction == "caller" and "JoeyPhoneCallerScript" or "JoeyPhoneCalleeScript"})
  checks[direction .. " native script label accepted"] = contacts:get("PHONE_YOUNGSTER_JOEY")[key] == nil
end
contacts:patch("PHONE_00", {calleeTime=0})
checks["native zero index preserved"] = contacts:get("PHONE_00").index == 0
]]

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  for _, api in ipairs({ 2, 3 }) do
    T.sdk.captureRuntime()
    Phone.useRegistry(nil)
    local max = version == "crystal" and 37 or 36
    local order, raw = {}, {}
    for index = 0, max do
      order[index + 1] = "PHONE_NATIVE_" .. index
      raw[index] = { trainerClass = 0, number = 0, calleeTime = 0, callerTime = 0,
        callee = "native:callee", caller = "native:caller" }
    end
    order[1], order[16] = "PHONE_00", "PHONE_YOUNGSTER_JOEY"
    for _, index in ipairs({ 8, 9, 10, 25 }) do order[index + 1] = "PHONE_UNUSED" end
    if version == "crystal" then order[38] = "PHONE_BUENA" end
    raw[15].trainerClass, raw[15].number = 1, 1
    local data = { gen2Constants = { phoneContactOrder = order,
      trainerClassOrder = { "TRAINER_NONE", "YOUNGSTER" },
      trainerClassMembers = { YOUNGSTER = { "JOEY1" } },
      rematchFlags = { { 15, "event", 628 } } },
      gen2EventTables = { phone = raw, phoneNames = { [0] = "----------" },
        specialCalls = {}, permanentNumbers = { 1, 4 }, phoneScripts = {
        JoeyPhoneCalleeScript = { script = "native:callee" },
        JoeyPhoneCallerScript = { script = "native:caller" } } },
      gen2Maps = { FIX_ROUTE = {} },
      gen2Trainers = { classes = { YOUNGSTER = { name = "YOUNGSTER", trainers = {
        { id = "JOEY1", name = "JOEY", party = {} },
      } } } }, gen2Scripts = {},
    }
    local files = {
      ["mods/a_good/manifest.json"] = ('{"id":"a_good","name":"good","version":"1.0.0",'
        .. '"api":%d,"games":["all"],"entry":"main.lua"}'):format(api),
      ["mods/a_good/main.lua"] = BODY,
      ["mods/b_failed/manifest.json"] = ('{"id":"b_failed","name":"failed","version":"1.0.0",'
        .. '"api":%d,"games":["all"],"entry":"main.lua"}'):format(api),
      ["mods/b_failed/main.lua"] = 'local mod=...;mod.content.phone_contacts:register("ROLLBACK",'
        .. '{index=51,name="ROLLBACK"});error("rollback fixture")',
    }
    local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = version, dev = true })
    loader:load(data)
    local label = version .. " API " .. api .. " "
    T.eq(loader.mods.a_good.failed, nil, label .. "contact registration succeeds")
    for name, passed in pairs(loader.exports.a_good and loader.exports.a_good.mutations or {}) do
      T.eq(passed, true, label .. name)
    end
    T.eq(loader.mods.b_failed.failed, true, label .. "rollback fixture fails")
    local index = loader.exports.a_good and loader.exports.a_good.index
    T.eq(index, max + 1, label .. "appends after native cache including Crystal Buena")
    Phone.useRegistry(data)
    Phone.useExtracted(data.gen2EventTables)
    T.eq(Phone.CONTACTS[51], nil, label .. "failed contact never materializes")
    local save = {}
    T.eq(Phone.askForNumber(save, index, true), Phone.CONTACT_GOT, label .. "asked contact is acquired")
    T.eq(Phone.contacts(save)[1], index, label .. "contact enters the ten-slot book")
    T.eq(Pokegear.contactRow({ trainers = data.gen2Trainers }, index), "GUIDE:", label .. "Pokegear displays mod name")
    T.eq(Phone.CONTACTS[index] and Phone.CONTACTS[index].member, "JOEY1", label .. "display name preserves trainer identity")
    local ctx = { mapId = "OTHER_MAP", phoneService = true, timeOfDay = Phone.DAY }
    local call = Phone.call(save, index, ctx)
    T.eq(call.scriptKey, "mod:callee", label .. "outgoing call uses direct mod script")
    T.eq(Phone.availableCallers(save, ctx)[1], index, label .. "incoming scheduler includes mod contact")
    local events = Events.new()
    local vm = Vm.new(data.gen2Scripts, {}, events)
    vm:start(call.scriptKey)
    for _ = 1, 10 do vm:update() end
    T.eq(events:get(1001), true, label .. "callee mod script executes")
    local incoming = Phone.loadCallerScript(index, "incoming", "caller")
    vm:start(incoming.scriptKey)
    for _ = 1, 10 do vm:update() end
    T.eq(events:get(1002), true, label .. "caller mod script executes")
    T.eq(Phone.setRematchReady(events, index), true, label .. "mod rematch flag can be set")
    T.eq(Phone.isReadyForRematch(events, index), true, label .. "mod rematch flag reads back")
    local decoded = assert(loadstring(Serializer.encode(save)))()
    T.eq(Phone.contacts(decoded)[1], index, label .. "numeric contact survives save serialization")
    T.eq(Phone.CONTACTS[15].member, "JOEY1", label .. "native trainer identity comes from cache")
    Phone.useRegistry(nil)
    T.eq(Phone.CONTACTS[index], nil, label .. "unbinding clears mod contact")
    T.eq(Phone.rematchEvent(index), nil, label .. "unbinding clears mod rematch flag")
    T.eq(Phone.call(decoded, index, ctx).kind, "outofarea", label .. "old saved number cannot call stale row")
    T.eq(Phone.contacts(decoded)[1], index, label .. "unknown saved number is retained")
    T.sdk.restoreRuntime()
  end
end
T.finish("Gen 2 mod phone contacts")
