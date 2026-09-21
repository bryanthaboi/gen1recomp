#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Flags = require("src.core.game3.scripting.flags")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local Runtime = require("src.core.game3.runtime")
local Mail = require("src.core.game3.mail")
local Trade = require("src.core.game3.scripting.natives_trade")
local Daycare = require("src.core.game3.scripting.natives_daycare")
local Party = require("src.core.game3.party")
local Schema = require("src.core.game3.save_schema_firered")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local VAR_0x8004 = 0x8004
local VAR_0x8005 = 0x8005

local SPECIAL_CREATE_IN_GAME_TRADE_POKEMON = 0xFD
local SPECIAL_DO_IN_GAME_TRADE_SCENE = 0xFE
local SPECIAL_PUT_MON_IN_ROUTE5_DAYCARE = 0x176
local SPECIAL_TAKE_POKEMON_FROM_ROUTE5_DAYCARE = 0x17A
local SPECIAL_STORE_SELECTED_POKEMON_IN_DAYCARE = 0xBB
local SPECIAL_TAKE_POKEMON_FROM_DAYCARE = 0xC0

local SPECIES_POLIWHIRL = 61
local SPECIES_JYNX = 124
local SPECIES_ABRA = 63
local ITEM_FAB_MAIL = 131
local ITEM_ORANGE_MAIL = 121
local ITEM_POTION = 13

-- pokefirered/src/data/ingame_trades.h:184 sInGameTradeMailMessages
local ZYNX_WORDS = { 3613, 4128, 5147, 10876, 3072, 4102, 5183, 4143, 4137 }

local prevSession = Runtime.session

local function newSession()
  local session = {
    party = {},
    store = Flags.newStore(),
    dex = { seen = {}, owned = {} },
    modData = {},
    name = "RED",
    trainerId = 24680,
  }
  Runtime.session = session
  return session
end

local function newVm(rows)
  local vm = Vm.new({
    store = Flags.newStore(),
    scripts = { t = rows },
    adapters = Adapters.host(nil, nil, nil),
  })
  vm:start("t")
  return vm
end

local function runToEnd(rows, maxFrames)
  local vm = newVm(rows)
  for _ = 1, maxFrames or 600 do
    if not vm:isRunning() then break end
    vm:resume()
  end
  return vm
end

local function wordsOf(record)
  local out = {}
  for i = 1, Mail.MAIL_WORDS_COUNT do out[i] = record and record.words and record.words[i] end
  return table.concat(out, ",")
end

print("[test] 1. ItemIsMail is the twelve mail items and nothing else")
local mailItems = { 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132 }
local allMail = true
for _, id in ipairs(mailItems) do
  if not Mail.isMailItem(id) then allMail = false end
end
check(allMail, "all twelve of pret's ITEM_ORANGE_MAIL..ITEM_RETRO_MAIL are mail")
check(not Mail.isMailItem(120) and not Mail.isMailItem(133) and not Mail.isMailItem(ITEM_POTION),
  "the items on either side of the block, and POTION, are not")
eq(Mail.designOf(ITEM_ORANGE_MAIL), 0, "ITEM_TO_MAIL(ORANGE_MAIL) is design 0")
eq(Mail.designOf(ITEM_FAB_MAIL), 10, "ITEM_TO_MAIL(FAB_MAIL) is design 10")
eq(Mail.designOf(ITEM_POTION), nil, "a non mail item has no design")

print("[test] 2. GiveMailToMon only uses the six party-half slots, TakeMailFromMon frees one")
local s2 = newSession()
local held = {}
for i = 1, 7 do
  local mon = { species = SPECIES_ABRA, level = 5, personality = i }
  held[i] = mon
  held[i].id = Mail.giveMailToMon(s2, mon, ITEM_ORANGE_MAIL)
end
eq(held[1].id, 0, "the first letter takes mail slot 0")
eq(held[6].id, 5, "the sixth takes mail slot 5, the last of the party half")
eq(held[7].id, Mail.MAIL_NONE, "the seventh is refused with MAIL_NONE")
eq(held[7].item, nil, "and the refused mon was never given the item")
check(Mail.monHasMail(held[1]), "MonHasMail is true for a mon holding its letter")
eq(held[1].item, ITEM_ORANGE_MAIL, "GiveMailToMon set the held item too")
eq(Mail.get(s2, 0).playerName, "RED", "the author is the player name")
eq(Mail.get(s2, 0).trainerId, 24680, "and the player trainer id")
eq(Mail.get(s2, 0).species, SPECIES_ABRA, "SpeciesToMailSpecies stamped the mon species")
eq(Mail.get(s2, 0).words[1], Mail.EC_WORD_UNDEFINED, "a blank letter is nine empty words")
Mail.takeMailFromMon(s2, held[1])
check(not Mail.monHasMail(held[1]), "TakeMailFromMon leaves the mon with no mail")
eq(held[1].item, 0, "and no held item")
eq(Mail.get(s2, 0), nil, "the pool slot is free again")
local reuse = { species = SPECIES_ABRA, level = 5, personality = 99 }
eq(Mail.giveMailToMon(s2, reuse, ITEM_FAB_MAIL), 0, "and the next letter reuses slot 0")
check(not Mail.monHasMail({ species = 1, item = ITEM_FAB_MAIL }),
  "a mon holding mail with no mail id does not have mail")

print("[test] 3. the ZYNX trade carries DONTAE's FAB MAIL, run through the real specials")
local s3 = newSession()
check(select(1, Party.giveMon(s3, SPECIES_POLIWHIRL, 20, "POLI")) == true,
  "the player has the POLIWHIRL DONTAE asks for")
local vm3 = runToEnd({
  { op = "setvar", [1] = VAR_0x8004, [2] = 1 },
  { op = "setvar", [1] = VAR_0x8005, [2] = 0 },
  { op = "special", [1] = SPECIAL_CREATE_IN_GAME_TRADE_POKEMON,
    id = SPECIAL_CREATE_IN_GAME_TRADE_POKEMON },
  { op = "special", [1] = SPECIAL_DO_IN_GAME_TRADE_SCENE,
    id = SPECIAL_DO_IN_GAME_TRADE_SCENE },
  { op = "waitstate" },
  { op = "end" },
})
check(not vm3:isRunning(), "the trade scene finished")
local zynx = s3.party[1]
eq(zynx and (zynx.species or zynx.speciesId), SPECIES_JYNX, "ZYNX is in the party slot")
eq(zynx and zynx.item, ITEM_FAB_MAIL, "holding FAB MAIL")
check(Mail.monHasMail(zynx), "and MonHasMail says the letter came with it")
local letter = Mail.get(s3, zynx and zynx.mail)
check(letter ~= nil, "the letter is in the player's mail pool")
eq(wordsOf(letter), table.concat(ZYNX_WORDS, ","),
  "with sInGameTradeMailMessages[0], the nine easy chat words")
eq(letter and letter.playerName, "DONTAE", "signed by DONTAE, not by the player")
eq(letter and letter.trainerId, 36728, "with DONTAE's trainer id")
eq(letter and letter.itemId, ITEM_FAB_MAIL, "and the FAB MAIL stationery")
eq(letter and letter.design, 10, "which resolves to mail design 10")

print("[test] 4. the mail of the mon the player sends away is freed")
local s4 = newSession()
Party.giveMon(s4, SPECIES_POLIWHIRL, 20, "POLI")
eq(Mail.giveMailToMon(s4, s4.party[1], ITEM_ORANGE_MAIL), 0,
  "the POLIWHIRL leaves carrying its own ORANGE MAIL in slot 0")
local before = Mail.get(s4, 0)
eq(before and before.playerName, "RED", "which the player wrote")
runToEnd({
  { op = "setvar", [1] = VAR_0x8004, [2] = 1 },
  { op = "setvar", [1] = VAR_0x8005, [2] = 0 },
  { op = "special", [1] = SPECIAL_CREATE_IN_GAME_TRADE_POKEMON,
    id = SPECIAL_CREATE_IN_GAME_TRADE_POKEMON },
  { op = "special", [1] = SPECIAL_DO_IN_GAME_TRADE_SCENE,
    id = SPECIAL_DO_IN_GAME_TRADE_SCENE },
  { op = "waitstate" },
  { op = "end" },
})
local after = Mail.get(s4, 0)
eq(after and after.playerName, "DONTAE",
  "ClearMailStruct freed slot 0 and GiveMailToMon2 reused it for the partner letter")
eq(s4.party[1] and s4.party[1].mail, 0, "the received ZYNX points at that slot")
local occupied = 0
for i = 1, Mail.MAIL_COUNT do
  if not Mail.isEmpty(Mail.pool(s4)[i]) then occupied = occupied + 1 end
end
eq(occupied, 1, "exactly one letter is in the pool, the sent one did not leak")

print("[test] 5. the Route 5 day care moves the letter into its slot and hands it back")
local s5 = newSession()
Party.giveMon(s5, SPECIES_POLIWHIRL, 20, "POLI")
Party.giveMon(s5, SPECIES_ABRA, 20, "ABBY")
Mail.giveMailToMon(s5, s5.party[1], ITEM_FAB_MAIL)
for i = 1, Mail.MAIL_WORDS_COUNT do Mail.get(s5, 0).words[i] = ZYNX_WORDS[i] end
local depositedWords = wordsOf(Mail.get(s5, 0))
runToEnd({
  { op = "setvar", [1] = VAR_0x8004, [2] = 0 },
  { op = "special", [1] = SPECIAL_PUT_MON_IN_ROUTE5_DAYCARE,
    id = SPECIAL_PUT_MON_IN_ROUTE5_DAYCARE },
  { op = "end" },
})
local r5 = Daycare.route5Of(s5)
check(r5 and r5.mon ~= nil, "the POLIWHIRL is in the Route 5 day care")
eq(r5 and r5.mon and r5.mon.item, 0, "TakeMailFromMon took its held mail on the way in")
eq(r5 and r5.mon and r5.mon.mail, nil, "and its mail id")
check(r5 and r5.mail ~= nil, "the letter moved into the day-care slot")
eq(r5 and r5.mail and r5.mail.otName, "RED", "DayCareMail.OT_name is the player")
eq(r5 and r5.mail and r5.mail.monName, "POLI", "DayCareMail.monName is the mon nickname")
eq(Mail.get(s5, 0), nil, "and the pool slot it used is free while the mon is away")
eq(#s5.party, 1, "the party compacted down to the ABRA")

runToEnd({
  { op = "special", [1] = SPECIAL_TAKE_POKEMON_FROM_ROUTE5_DAYCARE,
    id = SPECIAL_TAKE_POKEMON_FROM_ROUTE5_DAYCARE },
  { op = "end" },
})
eq(#s5.party, 2, "the POLIWHIRL came back to the party")
local back = s5.party[2]
eq(back and (back.species or back.speciesId), SPECIES_POLIWHIRL, "it is the POLIWHIRL")
eq(back and back.item, ITEM_FAB_MAIL, "GiveMailToMon2 put the FAB MAIL back in its hands")
check(Mail.monHasMail(back), "and it has its mail again")
eq(wordsOf(Mail.get(s5, back and back.mail)), depositedWords,
  "the words came back unchanged")
eq(Daycare.route5Of(s5).mail, nil, "the day-care slot no longer holds a letter")

print("[test] 6. the two-slot day care keeps one letter per slot and shifts it")
local s6 = newSession()
Party.giveMon(s6, SPECIES_POLIWHIRL, 20, "POLI")
Party.giveMon(s6, SPECIES_ABRA, 20, "ABBY")
Party.giveMon(s6, SPECIES_ABRA, 20, "SPARE")
Mail.giveMailToMon(s6, s6.party[2], ITEM_FAB_MAIL)
runToEnd({
  { op = "setvar", [1] = VAR_0x8004, [2] = 0 },
  { op = "special", [1] = SPECIAL_STORE_SELECTED_POKEMON_IN_DAYCARE,
    id = SPECIAL_STORE_SELECTED_POKEMON_IN_DAYCARE },
  { op = "setvar", [1] = VAR_0x8004, [2] = 0 },
  { op = "special", [1] = SPECIAL_STORE_SELECTED_POKEMON_IN_DAYCARE,
    id = SPECIAL_STORE_SELECTED_POKEMON_IN_DAYCARE },
  { op = "end" },
})
local dc = Daycare.stateOf(s6)
eq(Daycare.count(dc), 2, "both mons are in the day care")
eq(dc.mail and dc.mail[1], nil, "slot 1, the POLIWHIRL, brought no letter")
check(dc.mail and dc.mail[2] ~= nil, "slot 2, the ABRA, did")
eq(dc.mail and dc.mail[2] and dc.mail[2].monName, "ABBY", "and it is that mon's letter")

runToEnd({
  { op = "setvar", [1] = VAR_0x8004, [2] = 0 },
  { op = "special", [1] = SPECIAL_TAKE_POKEMON_FROM_DAYCARE,
    id = SPECIAL_TAKE_POKEMON_FROM_DAYCARE },
  { op = "end" },
})
dc = Daycare.stateOf(s6)
-- pokefirered/src/daycare.c:471
check(dc.mail and dc.mail[1] ~= nil, "ShiftDaycareSlots moved the letter into slot 1 with its mon")
eq(dc.mail and dc.mail[2], nil, "and cleared slot 2")
eq(dc.mail and dc.mail[1] and dc.mail[1].monName, "ABBY", "it is still the ABRA's letter")

runToEnd({
  { op = "setvar", [1] = VAR_0x8004, [2] = 0 },
  { op = "special", [1] = SPECIAL_TAKE_POKEMON_FROM_DAYCARE,
    id = SPECIAL_TAKE_POKEMON_FROM_DAYCARE },
  { op = "end" },
})
local abby = nil
for _, mon in ipairs(s6.party) do
  if mon.nickname == "ABBY" then abby = mon end
end
check(abby ~= nil, "the ABRA is back in the party")
eq(abby and abby.item, ITEM_FAB_MAIL, "holding its FAB MAIL again")
check(Mail.monHasMail(abby), "with its letter attached")
local leftover = Daycare.stateOf(s6).mail
eq(leftover and leftover[1], nil, "the day care kept no copy")

print("[test] 7. the pool survives a save round trip")
local s7 = newSession()
Party.giveMon(s7, SPECIES_POLIWHIRL, 20, "POLI")
Mail.giveMailToMon(s7, s7.party[1], ITEM_FAB_MAIL)
Mail.get(s7, 0).words[1] = ZYNX_WORDS[1]
local saved = Schema.toSaveTable(s7)
check(saved.mail ~= nil, "toSaveTable wrote the mail pool")
local loaded = Schema.fromSaveTable(saved)
eq(loaded.mail and loaded.mail[1] and loaded.mail[1].itemId, ITEM_FAB_MAIL,
  "fromSaveTable restored the letter")
eq(loaded.mail and loaded.mail[1] and loaded.mail[1].words[1], ZYNX_WORDS[1],
  "with its words")
eq(#(loaded.mail or {}), Mail.MAIL_COUNT, "as all sixteen SaveBlock1 slots")
eq(Mail.export({ party = {} }), nil, "an empty pool is not written into the save at all")
eq(Mail.restore(nil), nil, "and a save from before the pool existed restores to no pool")
eq(#Mail.pool({ party = {} }), Mail.MAIL_COUNT, "which the first letter creates on demand")

Runtime.session = prevSession

if failed > 0 then
  print(string.format("FAILED %d check(s)", failed))
  os.exit(1)
end
print("PASS game3_stitchscript_mail")
os.exit(0)
