package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 moomoo")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local FlagIds = require("src.core.gen2.FlagIds")
local EventFlagOrder = require("tests.fixture_data.gen2_event_flag_order")
local Ser = require("src.core.SaveSerializer")
local Save = require("src.core.gen2.Save")

-- pokecrystal constants/event_flags.asm:70
local EVENTS = FlagIds.events({ eventFlagOrder = EventFlagOrder.crystal })
local HEALED = EVENTS.EVENT_HEALED_MOOMOO
local TALKED = EVENTS.EVENT_TALKED_TO_FARMER_ABOUT_MOOMOO
-- pokecrystal ram/wram.asm:3142 wMooMooBerries
local BERRIES = 0xd962
local BERRY_ITEM = 173

eq(HEALED, 61, "EVENT_HEALED_MOOMOO is flag 61")
eq(TALKED, 63, "EVENT_TALKED_TO_FARMER_ABOUT_MOOMOO is flag 63")

do
  local events = Events.new()
  events:set(HEALED, true)
  events:set(0, true)
  events:resetMapBuffer()
  check(events:get(HEALED), "a map reload cannot clear flag 61")
  check(not events:get(0), "the map buffer byte is the one that is wiped")
end

local cache = os.getenv("CRYSTAL_CACHE")
if not cache then
  cache = (os.getenv("HOME") or "")
    .. "/Library/Application Support/LOVE/crystal-dev/crystal"
end

local scriptsPath = cache .. "/data/generated/scripts.lua"
local probe = io.open(scriptsPath, "r")
if not probe then
  check(true, "crystal cache absent : SKIP")
  S.finish()
  return
end
probe:close()

local function loadLua(rel)
  local chunk = loadfile(cache .. "/" .. rel)
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  return ok and value or nil
end

local scripts = loadLua("data/generated/scripts.lua")
local texts = loadLua("data/generated/text.lua")
local maps = loadLua("data/generated/maps.lua")
check(scripts ~= nil, "scripts.lua loads")
check(texts ~= nil, "text.lua loads")
check(maps ~= nil, "maps.lua loads")

local barn = (maps or {}).ROUTE_39_BARN
check(barn ~= nil, "the cache carries ROUTE_39_BARN")

-- pokecrystal maps/Route39Barn.asm:47 MoomooScript
local miltank
for _, obj in ipairs((barn or {}).objects or {}) do
  if obj.sprite == "SPRITE_TAUROS" then miltank = obj end
end
check(miltank ~= nil, "the Miltank object is on the map")
local moomooKey = miltank and (miltank.scriptKey or miltank.script)
eq(moomooKey, "27:4caa", "and it points at MoomooScript")

local seven
for _, row in ipairs((scripts or {})["27:4d04"] or {}) do
  if row.op == "setevent" then seven = row.event end
end
-- pokecrystal maps/Route39Barn.asm:106
eq(seven, HEALED, ".SevenBerries ends on setevent EVENT_HEALED_MOOMOO")

local hasClear = false
for key, rows in pairs(scripts or {}) do
  if type(rows) == "table" and type(key) == "string" then
    for _, row in ipairs(rows) do
      if row.op == "clearevent" and row.event == HEALED then hasClear = true end
    end
  end
end
check(not hasClear, "nothing in the cache ever clears flag 61")

local events = Events.new()
events:set(TALKED, true)

local bag = { [BERRY_ITEM] = 10 }
local seen = {}
local vm = Vm.new(scripts, texts, events, {
  showText = function(body, onDone)
    seen[#seen + 1] = tostring(body)
    if onDone then onDone() end
  end,
  yesorno = function(onChoose) onChoose(true) end,
  hasItem = function(item) return (bag[item] or 0) > 0 end,
  takeItem = function(item, qty)
    local have = bag[item] or 0
    if have < (qty or 1) then return false end
    bag[item] = have - (qty or 1)
    return true
  end,
})

local function drain()
  for _ = 1, 600 do
    if not vm:running() then break end
    vm:update()
  end
  return not vm:running()
end

for i = 1, 7 do
  check(vm:start(moomooKey), ("talk %d starts MoomooScript"):format(i))
  check(drain(), ("talk %d runs to end"):format(i))
  eq(vm.mem[BERRIES], i, ("berry %d counted into wMooMooBerries"):format(i))
  if i < 7 then
    check(not events:get(HEALED),
      ("berry %d does not heal MOOMOO"):format(i))
  end
end

check(events:get(HEALED), "EVENT_HEALED_MOOMOO is set on the seventh berry")
eq(bag[BERRY_ITEM], 3, "seven BERRIES left the bag")

local function saw(fragment)
  for _, body in ipairs(seen) do
    if body:find(fragment, 1, true) then return true end
  end
  return false
end
check(saw("little healthier"), "the third berry prints the 3-berry line")
check(saw("quite healthy"), "the fifth berry prints the 5-berry line")
check(saw("totally healthy"), "the seventh berry prints the 7-berry line")

-- pokecrystal maps/Route39Barn.asm:121
seen = {}
check(vm:start(moomooKey), "the next talk starts")
check(drain(), "and runs to end")
check(saw("Mooo!"), "a healed MOOMOO takes the .HappyCow arm")
eq(vm.mem[BERRIES], 7, "and does not take another berry")

local snapshot = { scriptMem = vm:serializeMem(), events = events:serialize() }
eq(snapshot.scriptMem[BERRIES], 7, "the counter reaches serializeMem")

local encoded = Ser.encode(snapshot)
check(type(encoded) == "string", "the snapshot encodes")
local decoded, err = Ser.decode(encoded)
check(decoded ~= nil, "and decodes (" .. tostring(err) .. ")")

local report = Save.validate(decoded or {})
check(Save.emptyReport(report), "validate quarantines nothing")

local back = Vm.new({}, {}, Events.new(), {}):restoreMem((decoded or {}).scriptMem)
eq(back.mem[BERRIES], 7, "the counter survives a save round trip")
local backEvents = Events.new():restore((decoded or {}).events)
check(backEvents:get(HEALED), "and so does EVENT_HEALED_MOOMOO")

S.finish()
