package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
love = require("tests.love_stub")
local T = require("tests.harness")
local Version = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local Codec = require("src.save_convert.Gen3Save")
local Compat = require("src.save_convert.Compat")
local Gen, Ops = require("Gen"), require("Ops")
local State, History = require("State"), require("History")
local Kit, Touch = require("Kit"), require("TouchEditor")
local Trainer, Items = require("Trainer"), require("Items")

-- pokeemerald/include/global.h:449, :541
local BP_OFF = 0x64C + 0x86C
local CARD_OFF = 0x64C + 0x86E

local function state(save, version)
  local s = State.new()
  s.save, s.version = save, version
  s.save.pcItems = s.save.pcItems or {}
  Gen.ensureBoxes(s.save)
  return s
end
local function snapshot(s)
  return { bytes = Serializer.encode(s.save), dirty = s.dirty, revision = s.revision,
    token = s.historyToken, undo = #(s.undoStack or {}), redo = #(s.redoStack or {}) }
end
local function unchanged(s, before, msg) T.same(snapshot(s), before, msg) end
local function bp(save) return Gen.battlePoints and Gen.battlePoints(save, "emerald") or nil end
local function seed()
  return { version = "emerald", generation = 3, map = "EM_LITTLEROOT_TOWN", x = 5, y = 8,
    name = "BRENDAN", trainerId = 1234, secretId = 5678, gender = 0,
    money = 123456, coins = 4321, frontier = { battlePoints = 500, cardBattlePoints = 777 },
    party = {}, pcItems = {}, boxes = {} }
end
local function export(save)
  local bytes, err = Codec.forVersion("emerald").exportPort(save, {
    version = "emerald", metGame = Version.gameCode("emerald"), itemId = tonumber,
    toNational = function() return nil end,
    mapLayoutId = function() return 1 end,
    healWarp = function() return { group = 0, num = 9, warpId = -1, x = 5, y = 8 } end,
  })
  return assert(bytes, err)
end
local function word(s, off) return s:byte(off + 1) + s:byte(off + 2) * 256 end

Version.set("emerald")
local C = Codec.forVersion("emerald")
local raw = export(seed())
for _, value in ipairs({ 0, 1234, 9999 }) do
  local s = state(assert(C.importPort(raw, "emerald")), "emerald")
  T.eq(bp(s.save), 500, "reads imported battle points")
  local baseline = export(Serializer.decode(Serializer.encode(s.save)))
  T.eq(Ops.setTrainerProperty(s, "battlePoints", value), true, "accepts battle points " .. value)
  T.eq(s.save.frontier.battlePoints, value, "writes the frontier battle points")
  T.eq(s.save.frontier.cardBattlePoints, 777, "trainer card BP total untouched")
  T.eq(s.dirty, true, "edit marks dirty")
  T.eq(#(s.undoStack or {}), 1, "edit records one undo")
  T.eq(s.status, "Battle Points updated", "edit status")
  local out = export(Serializer.decode(Serializer.encode(s.save)))
  local blocks = assert(Compat.gen3Blocks(out, "emerald"))
  local original = assert(Compat.gen3Blocks(baseline, "emerald"))
  T.eq(word(blocks.sb2, BP_OFF), value, "raw SaveBlock2 battlePoints word")
  T.eq(word(blocks.sb2, CARD_OFF), 777, "raw SaveBlock2 cardBattlePoints word")
  local normalized = blocks.sb2:sub(1, BP_OFF) .. original.sb2:sub(BP_OFF + 1, BP_OFF + 2)
    .. blocks.sb2:sub(BP_OFF + 3)
  T.eq(normalized, original.sb2, "all other SaveBlock2 bytes preserved")
  T.eq(blocks.sb1, original.sb1, "all SaveBlock1 bytes preserved")
  T.eq(blocks.storage, original.storage, "all storage bytes preserved")
  local changed = 0
  for i = 1, #out do if out:byte(i) ~= baseline:byte(i) then changed = changed + 1 end end
  T.check(changed <= 4, "only the BP u16 and sector checksum change (" .. changed .. ")")
  T.eq(bp(assert(C.importPort(out, "emerald"))), value, "cart reimport keeps battle points")
  T.eq(History.undo(s), true, "undo succeeds")
  T.eq(bp(s.save), 500, "undo restores imported battle points")
  T.eq(History.redo(s), true, "redo succeeds")
  T.eq(bp(s.save), value, "redo restores battle points")
  local before = snapshot(s)
  T.eq(Ops.setTrainerProperty(s, "battlePoints", value), true, "same value accepted")
  unchanged(s, before, "same value adds no history")
end

local s = state(seed(), "emerald")
T.eq(Ops.setTrainerProperty(s, "battlePoints", "777"), true, "numeric string accepted")
T.eq(bp(s.save), 777, "numeric string stored as number")
for _, draft in ipairs({ { -1 }, { 10000 }, { 1.5 }, { 0/0 }, { math.huge }, { "" }, { "bp" }, { false }, {} }) do
  local before = snapshot(s)
  T.eq(Ops.setTrainerProperty(s, "battlePoints", draft[1]), false, "invalid battle points rejected")
  unchanged(s, before, "invalid battle points leave save unchanged")
  T.eq(s.status, "Battle Points must be a whole number from 0 to 9999", "validation feedback")
end
s = state({ version = "emerald", generation = 3, frontier = "malformed" }, "emerald")
local before = snapshot(s)
T.eq(Ops.setTrainerProperty(s, "battlePoints", 5), false, "malformed frontier rejected")
unchanged(s, before, "malformed frontier untouched")

local rows, realValue = {}, Touch.value
Touch.value = function(st, kit, id, title, value, limits, x, y, w, apply, issue)
  rows[id] = { title = title, value = value, limits = limits, apply = apply }
  return realValue(st, kit, id, title, value, limits, x, y, w, apply, issue)
end
local function panel(st, which)
  rows = {}
  Kit.layout(720, 1400)
  Kit.blockClicks = false
  Kit.beginFrame(-1, -1, false, 0)
  if which == "wallet" then st.itemView = "wallet"; Items.draw(st, Kit, 0, 0, 720, 1400)
  else Trainer.draw(st, Kit, 0, 0, 720, 1400) end
  Kit.endFrame()
  return rows[(which == "wallet" and "wallet-" or "trainer-") .. "battlePoints"]
end
for _, v in ipairs(Version.ORDER) do
  local info = assert(Version.info(v))
  Version.set(v)
  local eligible = v == "emerald"
  local st = state({ version = v, generation = info.generation, player = { name = "ASH" },
    frontier = { battlePoints = 7 } }, v)
  local prior = snapshot(st)
  T.eq(Ops.setTrainerProperty(st, "battlePoints", 15), eligible, v .. " operation edition gate")
  if not eligible then
    unchanged(st, prior, v .. " unsupported save not mutated")
    T.eq(st.status, "Battle Points are only in Emerald", v .. " unsupported feedback")
  end
  for _, which in ipairs({ "trainer", "wallet" }) do
    local row = panel(st, which)
    T.eq(row ~= nil, eligible, v .. " " .. which .. " row eligibility")
    if row then
      T.eq(row.title, "Battle Points", which .. " row label")
      T.eq(row.value, 15, which .. " row reads frontier battle points")
      T.eq(row.limits.lo, 0, which .. " row minimum")
      T.eq(row.limits.hi, 9999, which .. " row cap")
      T.check(row.limits.help:find("Battle Frontier", 1, true), which .. " row explains the currency")
      T.eq(row.apply(2345), true, which .. " row applies edits")
      T.eq(st.save.frontier.battlePoints, 2345, which .. " row writes battle points")
      Ops.setTrainerProperty(st, "battlePoints", 15)
    end
  end
end
Touch.value = realValue

local f = assert(io.open("tests/quick.list", "r"))
local quick = f:read("*a"); f:close()
T.check(quick:find("tests/engine/save_editor_battle_points_2773.lua", 1, true), "registered in quick suite")
Version.set("red")
T.finish("save_editor_battle_points_2773")
