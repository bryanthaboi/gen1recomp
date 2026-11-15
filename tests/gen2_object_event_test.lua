-- home/map.asm ObjectEvent, the generic "Object event." line an object with no
-- script of its own says.  It is a ROM0 body, so every map names it with the
-- same sub-$4000 `dw` and the extractor's map walk (which only ever queues
-- banked pointers) used to drop all 44 of them on the floor: the objects kept
-- a scriptKey in their own map's script bank, where nothing was disassembled,
-- and talking to one did nothing at all.
--
-- ROM-free: `luajit tests/gen2_object_event_test.lua`.  The cache section at
-- the bottom SKIPs when no Gold cache is present, and again when the cache
-- predates the extractor change (a re-import is what fills it in).
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 object event")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local Opcodes = require("src.script.gen2.Opcodes")

-- ---- the key a ROM0 body gets ---------------------------------------------
-- pokegold.sym: 00:2812 ObjectEvent, 00:2815 ObjectEventText.  Bank 0 is not a
-- banked script bank, it is the home bank every other bank can see, so the one
-- key is shared by every map rather than repeated per map bank.
local OBJECT_EVENT = Opcodes.key(0, 0x2812)
local OBJECT_EVENT_TEXT = Opcodes.key(0, 0x2815)
eq(OBJECT_EVENT, "00:2812", "ObjectEvent keys at bank 0")
eq(OBJECT_EVENT_TEXT, "00:2815", "and so does the text behind it")

-- ---- the VM runs a bank 0 key like any other ------------------------------
-- home/map.asm: `ObjectEvent: jumptextfaceplayer ObjectEventText`, so the body
-- is one command, it turns the object toward the player, and it ends there.
do
  local shown, faced = {}, {}
  local scripts = {
    generation = 2,
    [OBJECT_EVENT] = {
      { op = "jumptextfaceplayer", text = OBJECT_EVENT_TEXT },
    },
  }
  local texts = { [OBJECT_EVENT_TEXT] = "Object event." }
  local vm = Vm.new(scripts, texts, Events.new(), {
    showText = function(body, onDone)
      shown[#shown + 1] = body
      onDone()
    end,
    facePlayer = function() faced[#faced + 1] = true end,
  })
  check(vm:start(OBJECT_EVENT), "a bank 0 script key starts")
  for _ = 1, 4 do vm:update() end
  check(not vm:running(), "jumptextfaceplayer is a terminator")
  eq(shown[1], "Object event.", "the shared line prints")
  check(#faced >= 1, "and the object faces the player first")

  -- The regression itself: the same pointer keyed at the MAP's bank is not in
  -- the table, and Vm:start answers false rather than saying anything.
  check(not vm:start(Opcodes.key(0x42, 0x2812)),
    "the same address keyed at a map bank resolves to nothing")
end

-- ---- the extractor half ----------------------------------------------------
-- Read as source: the walk itself needs the ROM, so what is checked here is
-- that the ROM0 arm is still wired as the normalisation an object_event
-- pointer goes through.
do
  local f = assert(io.open("src/import/RomExtractorGen2.lua", "r"))
  local src = f:read("*a")
  f:close()
  check(src:find("local function enqueueHome(address)", 1, true) ~= nil,
    "the extractor has a ROM0 queue arm")
  check(src:find("obj.scriptKey = enqueueHome(obj.script)", 1, true) ~= nil,
    "an object_event pointer goes through it before its map bank")
  -- enqueue proper must keep refusing bank 0: a farscall or a map pointer that
  -- decodes to ROM0 is noise, and only the two call sites above know better.
  check(src:find("-- Scripts live in banked ROM, not ROM0.", 1, true) ~= nil,
    "the banked queue still refuses ROM0 pointers")
end

-- ---- the cache -------------------------------------------------------------
local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local mapsFile = io.open(cache .. "/data/generated/maps.lua", "r")
local scriptsFile = io.open(cache .. "/data/generated/scripts.lua", "r")
if not mapsFile or not scriptsFile then
  if mapsFile then mapsFile:close() end
  if scriptsFile then scriptsFile:close() end
  check(true, "gold cache absent : unit checks only (SKIP cache facts)")
  S.finish()
  return
end
mapsFile:close(); scriptsFile:close()

local maps = assert(loadfile(cache .. "/data/generated/maps.lua"))()
local scripts = assert(loadfile(cache .. "/data/generated/scripts.lua"))()
local texts = assert(loadfile(cache .. "/data/generated/text.lua"))()

-- Every object that names the shared line, and every one that names it the old
-- way (its own map's bank plus the ROM0 address).
local shared, stale = 0, 0
for _, def in pairs(maps) do
  if type(def) == "table" then
    for _, obj in ipairs(def.objects or {}) do
      if obj.scriptKey == OBJECT_EVENT then
        shared = shared + 1
      elseif type(obj.scriptKey) == "string"
          and obj.scriptKey:find(":2812", 1, true) then
        stale = stale + 1
      end
    end
  end
end

if shared == 0 and stale > 0 then
  check(true, ("cache predates the ROM0 seed (%d stale rows) : re-import " ..
    "for the shared line (SKIP)"):format(stale))
  S.finish()
  return
end

-- 44 object_events across pokegold/maps/ point at ObjectEvent; the one that is
-- OBJECTTYPE_TRAINER (BurnedTower1F's rival) reads the pointer as a `trainer`
-- struct instead, so the count of SCRIPT rows is one short of that.
check(shared >= 40, ("%d objects share the ObjectEvent line"):format(shared))
eq(stale, 0, "no object is left pointing into its own bank at $2812")

local body = scripts[OBJECT_EVENT]
check(type(body) == "table" and #body >= 1, "the shared body was disassembled")
if type(body) == "table" and body[1] then
  eq(body[1].op, "jumptextfaceplayer", "and it is the one jumptextfaceplayer")
  local line = body[1].text and texts[body[1].text]
  check(type(line) == "string" and line:find("Object event", 1, true) ~= nil,
    "whose text decoded through TX_FAR into _ObjectEventText")
end

S.finish()
