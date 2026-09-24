#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local GAME = require("tests.game3_cart_cache").mountOrSkip("game3_cart_import_load_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

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

local SaveConvert = require("src.save_convert.SaveConvert")
local SaveSerializer = require("src.core.SaveSerializer")
local Schema = require("src.core.game3.save_schema_firered")
local Pokemon = require("src.core.game3.pokemon")
local F = require("tests.fixture_data.gen3_saves")

local oracle = F.oracle.fr_rich_game
local save = assert(SaveConvert.importSav(unrle(F.images.fr_rich_game), GAME, GAME))
save = assert(SaveSerializer.decode(SaveSerializer.encode(save)))
local s = Schema.fromSaveTable(save)

check(s.map == "FR_PLAYERS_HOUSE_2F" and s.x == 6 and s.y == 6, "continue lands in the bedroom at 6,6")
check(s.healMap == "FR_PLAYERS_HOUSE_1F" and s.healX == 8 and s.healY == 5,
  "the Pallet heal spot resolves to Mom's tile (" .. tostring(s.healMap) .. " " .. tostring(s.healX) .. "," .. tostring(s.healY) .. ")")
check(s.modData.cartImport == nil, "the import marker is spent after the first load")
for i, o in ipairs(oracle.party) do
  local m = s.party[i]
  check(m.level == o.statLevel, ("party %d level %s"):format(i, tostring(m.level)))
  check(m.maxHp == o.maxHp, ("party %d max HP %s == %s"):format(i, tostring(m.maxHp), tostring(o.maxHp)))
  check(m.attack == o.stats[1] and m.defense == o.stats[2] and m.speed == o.stats[3]
    and m.spAtk == o.stats[4] and m.spDef == o.stats[5], ("party %d stats match the cart"):format(i))
  check(m.hp == o.hp, ("party %d HP %s"):format(i, tostring(m.hp)))
  check(m.cartImport == nil, ("party %d finished"):format(i))
end
check(s.party[1].nickname == "BLAZE", "a real nickname stays")
check(s.party[2].nickname == "", "a nickname equal to the species name clears")
check(s.party[2].name == Pokemon.name(277), "Treecko name comes from the species table")
check(s.party[1].gender == Pokemon.gender(6, oracle.party[1].pid), "gender from personality")
check(s.party[1].ability == Pokemon.abilities(6)[1], "ability slot 1")
check(s.party[1].maxPp[1] == Pokemon.movePp(53) + math.floor(Pokemon.movePp(53) * 20 * 3 / 100),
  "three PP Ups raise max PP on move 1")
check(s.party[1].maxPp[2] == Pokemon.movePp(17), "no PP Ups on move 2")
check(s.party[3].isEgg == true and s.party[3].eggCycles == 10, "the egg keeps its cycles")
local levels = {}
for _, b in ipairs(oracle.boxes) do
  local m = s.storage.boxes[b.box + 1].mons[b.slot + 1]
  levels[#levels + 1] = m and m.level
end
check(levels[1] == 4 and levels[2] == 3 and levels[3] == 70 and levels[4] == 30 and levels[5] == 50,
  "box levels come from exp (" .. table.concat(levels, ",") .. ")")
check(s.storage.boxes[2].mons[20].hp == s.storage.boxes[2].mons[20].maxHp, "box mons are full HP")
for _, nat in ipairs(oracle.caught) do
  local sp = Pokemon.speciesFromNational(nat)
  check(s.dex.owned[sp] == true and s.dex.caught[sp] == true, "caught national " .. nat .. " -> species " .. tostring(sp))
end
for _, nat in ipairs(oracle.seen) do
  check(s.dex.seen[Pokemon.speciesFromNational(nat)] == true, "seen national " .. nat)
end
check(s.dex.owned[277] == true and s.dex.owned[252] == nil, "Treecko is internal 277, not 252")
check(s.options.textSpeed == 1, "text speed carried")
check(#s.bag.pockets.ITEMS == 3, "bag items")

do
  local Gen3Save = require("src.save_convert.Gen3Save")
  local L = require("src.save_convert.Gen3Layout")
  local Mail = require("src.core.game3.mail")
  local c, blocks = Gen3Save.decode(unrle(F.images.fr_rich_game))
  c.party[1].heldItem, c.party[1].mail = 121, 0
  c.mail[1] = { words = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }, playerName = "AAA", trainerId = c.trainerId, species = 6, itemId = 121 }
  local N = L.NATIONAL_DEX
  c.dexNationalMagic, c.vars[N.var] = N.magic, N.varValue
  c.flags[#c.flags + 1] = N.flag
  c.fameChecker[3] = { pickState = 1, flavorTextFlags = 5 }
  local img = Gen3Save.buildFlash(Gen3Save.encodeBlocks(c, blocks), { counter = c.counter + 1, image = blocks.image })
  local cart = assert(SaveConvert.importSav(img, GAME, GAME))
  local s2 = Schema.fromSaveTable(assert(SaveSerializer.decode(SaveSerializer.encode(cart))))
  check(Mail.monHasMail(s2.party[1]), "a cart mon holding mail still has its letter after load")
  local letter = Mail.get(s2, s2.party[1].mail)
  check(letter ~= nil and letter.words[1] == 1 and letter.itemId == 121, "the letter's words survive the load")
  check(require("src.core.game3.pokedex_data").isNationalUnlocked(s2, s2.dex) == true, "a National Dex cart loads unlocked")
  local fc = require("src.core.game3.fame_checker").records(s2)
  check(fc and fc[3].pickState == 1 and fc[3].flavorTextFlags == 5, "Fame Checker progress loads")
end

if failed > 0 then
  print(string.format("\n%d FAILED", failed))
  os.exit(1)
end
print("\nAll cart import load tests passed.")
os.exit(0)
