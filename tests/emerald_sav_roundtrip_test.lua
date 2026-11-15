package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
if not cache:read("data/generated/gba/native/manifest.lua") or not cache:read("data/generated/gba/pokemon/national.lua") then
  print("emerald_sav_roundtrip_test: skipped (no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d") .. ")")
  os.exit(0)
end
Dataset.mountExtractRoots()
Dataset.hydrate({ data = {} })

local SaveSections = require("src.core.game3.save_sections")
local registered = {}
local realRegister = SaveSections.register
SaveSections.register = function(name, def)
  registered[name] = true
  return realRegister(name, def)
end
for _, mod in ipairs({ "src.core.game3.rse.ribbons", "src.core.game3.rse.dewford_trend", "src.core.game3.weather",
  "src.core.game3.rse.contest_util", "src.core.game3.rse.lilycove_lady", "src.core.game3.rse.lottery",
  "src.core.game3.rse.tv", "src.core.game3.rse.pokeblock", "src.core.game3.rse.secret_base",
  "src.core.game3.rse.rematch", "src.core.game3.rse.old_man", "src.core.game3.rse.berry_trees",
  "src.core.game3.rse.decoration_inventory" }) do
  package.loaded[mod] = nil
  local ok, err = pcall(require, mod)
  check(ok, "loads " .. mod .. " (" .. tostring(err) .. ")")
end
SaveSections.register = realRegister
for _, name in ipairs({ "rtc", "encryptionKey", "berryTrees", "tv", "decorations" }) do registered[name] = true end

local Rse = require("src.save_convert.gen3_port.rse")
for name in pairs(registered) do
  check(Rse.SECTIONS[name] ~= nil, "the cart mapper covers registered save section " .. name)
end
local Profile = require("src.core.game3.profile")
local listed = {}
for _, entry in ipairs(Profile.of("emerald").save.sections or {}) do
  local name = type(entry) == "table" and entry.name or entry
  listed[name] = true
  check(Rse.SECTIONS[name] ~= nil, "the cart mapper covers profile save section " .. tostring(name))
end
for name in pairs(registered) do
  if not listed[name] then print("emerald_sav_roundtrip_test: note: section " .. name .. " is registered but not in profiles/emerald/save.lua sections") end
end

local SaveConvert = require("src.save_convert.SaveConvert")
local Schema = require("src.core.game3.save_schema_firered")
local Gen3Save = require("src.save_convert.Gen3Save")
local E = Gen3Save.forVersion("emerald")
local F = require("tests.fixture_data.gen3_saves_emerald")
local FR = require("tests.fixture_data.gen3_saves")

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then
      out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else
      out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
    end
  end
  return table.concat(out)
end

local function mapExists(mapId)
  for g = 0, 40 do
    for n = 0, 120 do
      if E.mapFor(g, n) == mapId then
        return cache:read(("data/generated/gba/map_tree/maps/%d_%d/header.json"):format(g, n)) ~= nil
      end
    end
  end
  return false
end

for _, name in ipairs({ "em_battle", "em_fresh", "em_doctored" }) do
  local bytes = unrle(F.images[name])
  local o = F.oracle[name]
  local save, err = SaveConvert.importSav(bytes, "emerald", "emerald")
  check(save ~= nil, name .. " imports through SaveConvert (" .. tostring(err) .. ")")
  if save then
    check(mapExists(save.map), name .. " lands on a cached map " .. tostring(save.map))
    eq(save.x, o.pos[1], name .. " x")
    eq(save.y, o.pos[2], name .. " y")
    eq(#save.party, #o.party, name .. " party size")
    check(type(save.rtcSkew) == "number", name .. " RTC anchored to the save's last berry update")
    local ok, sess = pcall(Schema.fromSaveTable, save)
    check(ok, name .. " loads into a session (" .. tostring(not ok and sess or "") .. ")")
    if ok then
      eq(sess.version, "emerald", name .. " session is emerald")
      eq(sess.money, o.money, name .. " session money")
      eq(sess.encryptionKey, o.key, name .. " session keeps the cart key")
      check(type(sess.berryTrees) == "table", name .. " berry trees restored")
      if listed.pokeblocks then check(type(sess.pokeblocks) == "table", name .. " pokeblocks restored") end
      check(type(sess.localTimeOffset) == "table", name .. " local time offset restored")
      local back = Schema.toSaveTable(sess)
      local out, xerr = SaveConvert.exportSav(back, "emerald", bytes)
      check(out ~= nil, name .. " exports through SaveConvert (" .. tostring(xerr) .. ")")
      if out then
        local a, b = E.readBlocks(bytes), E.readBlocks(out)
        if o.key == 0 then
          local ca, cb = E.decode(bytes), E.decode(out)
          check(cb.encryptionKey ~= 0 and cb.encryptionKey ~= 1, name .. " key 0 is re-keyed through the native schema")
          eq(cb.money, ca.money, name .. " money survives the re-key")
          check(a.storage == b.storage, name .. " storage byte-identical through the native schema")
        else
          for _, blk in ipairs(E.L.BLOCKS) do
            check(a[blk.key] == b[blk.key], name .. " " .. blk.key .. " byte-identical through the native schema")
          end
        end
        for sec = 28, 31 do
          local off = sec * 0x1000
          check(out:sub(off + 1, off + 0x1000) == bytes:sub(off + 1, off + 0x1000), name .. " sector " .. sec .. " kept")
        end
      end
      sess.money = 12345
      sess.x = sess.x + 1
      local moved = assert(SaveConvert.exportSav(Schema.toSaveTable(sess), "emerald", bytes))
      local c = assert(E.decode(moved))
      eq(c.money, 12345, name .. " edited money reaches the cart")
      eq(c.posX, o.pos[1] + 1, name .. " moved position reaches the cart")
      eq(c.continueGameWarp.x, o.pos[1] + 1, name .. " continue warp follows the player")
    end
  end
end

do
  local sess = Schema.newGame({ version = "emerald", name = "BRENDAN", gender = 0, trainerIdLower = 4321 })
  local save = Schema.toSaveTable(sess)
  local out, err = SaveConvert.exportSav(save, "emerald", nil)
  check(out ~= nil, "a native new game exports with no cart template (" .. tostring(err) .. ")")
  if out then
    local c = assert(E.decode(out))
    eq(c.name, "BRENDAN", "fresh export player name")
    eq(c.trainerId, 4321, "fresh export trainer id")
    eq(c.money, 3000, "fresh export money")
    eq(E.mapFor(c.location.group, c.location.num), "EM_INSIDE_OF_TRUCK", "fresh export starts in the truck")
    eq(#c.pcItems, 1, "fresh export PC potion")
    eq(save.encryptionKey, 0, "the native new game keeps key 0 like NewGameInitData")
    check(c.encryptionKey ~= 0 and c.encryptionKey ~= 1, "fresh export gets a derived key readers type as Emerald")
    eq(c.encryptionKey, E.deriveKey(4321, sess.secretId, save.meta and save.meta.playthroughId, 0),
      "the fresh key is derived from TID, SID and playthrough")
    eq(c.easyChatBattle.start[1], 8 * 512 + 15, "fresh export battle-start words (EC_WORD_ARE)")
    eq(c.easyChatBattle.lost[5], 3 * 512 + 48, "fresh export battle-lost words (EC_WORD_LOST)")
    local again = assert(SaveConvert.importSav(out, "emerald", "emerald"))
    eq(again.name, "BRENDAN", "fresh export re-imports")
    eq(again.encryptionKey, c.encryptionKey, "the re-import keeps the derived key")
    local sess2 = Schema.fromSaveTable(again)
    eq(sess2.encryptionKey, c.encryptionKey, "the engine accepts a nonzero key at import")
    local same_flags = true
    for k, v in pairs(save.flags or {}) do if v and not sess2.flags[k] then same_flags = false end end
    check(same_flags, "the re-key leaves story flags alone")
    local back = Schema.toSaveTable(sess2)
    back.modData.cartImage = nil
    eq(SaveConvert.exportSav(back, "emerald", nil), out, "export(import(export)) is a fixed point")
  end
end

do
  local _, msg = SaveConvert.importSav(unrle(FR.images.fr_rich_game), "emerald", "emerald")
  eq(msg, E.MSG.frlg, "a FireRed cart dropped on Emerald says so")
  local _, frMsg = SaveConvert.importSav(unrle(F.images.em_fresh), "firered", "firered")
  eq(frMsg, Gen3Save.MSG.emerald, "an Emerald cart dropped on FireRed says so")
  local _, gen1 = SaveConvert.mainChecksumValid(unrle(F.images.em_fresh), "red")
  eq(gen1, "That is an Emerald (Game Boy Advance) save, not a save for this game.", "an Emerald cart dropped on Red")
end

do
  local SaveData = require("src.core.SaveData")
  local save = assert(SaveConvert.importSav(unrle(F.images.em_battle), "emerald", "emerald"))
  GameVersion.set("firered")
  local _, meta = SaveData.slotSummary(save)
  GameVersion.set("emerald")
  eq(meta and meta.badges, 8, "launcher counts Emerald badges (0x867-0x86E) while FireRed is active")
  eq(meta and meta.timeText, "135:33", "launcher play time from the cart")
end

T.finish("emerald_sav_roundtrip")
