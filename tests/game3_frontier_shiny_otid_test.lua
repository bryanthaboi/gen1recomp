package.path = "./?.lua;./?/init.lua;" .. package.path

local bit = require("bit")
local T = require("tests.harness")
local check, eq = T.check, T.eq

local SummaryData = require("src.core.game3.summary_data")
local Pokemon = require("src.core.game3.pokemon")
local ShinySeq = require("src.core.game3.battle.shiny_seq")

-- pokeemerald/include/pokemon.h:371
local function cartShiny(otId, personality)
  local v = bit.bxor(bit.bxor(math.floor(otId / 65536), otId % 65536),
    bit.bxor(math.floor(personality / 65536), personality % 65536))
  return v < 8
end

local OT = 0x9ABC * 65536 + 12345
local plain = { personality = 0x00010002, otId = OT }
eq(cartShiny(OT, plain.personality), false, "fixture is a non-shiny cart mon")
eq(SummaryData.isShiny(plain), false, "32-bit otId with secret id >= 0x8000 is not shiny in the summary check")
eq(ShinySeq.isShiny({ mon = plain }), false, "send-out shiny check rejects a non-shiny 32-bit otId mon")
eq(Pokemon.isShiny(plain), false, "Pokemon.isShiny rejects a non-shiny 32-bit otId mon")

local hi, lo = 0x9ABC, 12345
local shinyP = bit.bxor(hi, lo) * 65536 + 0
shinyP = shinyP % 4294967296
eq(cartShiny(OT, shinyP), true, "fixture is a shiny cart mon")
eq(SummaryData.isShiny({ personality = shinyP, otId = OT }), true, "summary check reads the secret id from the otId high half")
eq(Pokemon.isShiny({ personality = shinyP, otId = OT }), true, "Pokemon.isShiny reads the secret id from the otId high half")
eq(SummaryData.isShiny({ personality = shinyP, otId = lo, otSecretId = hi }), true, "split otId stays shiny")

do
  local SwitchSeq = require("src.core.game3.battle.switch_seq")
  local Anim = require("src.core.game3.battle.anim")
  local Audio = require("src.core.game3.audio")
  local oldCry, oldPlaying = Audio.playCry, Audio.isCryPlaying
  local cryFrame
  local frame = 0
  Audio.playCry = function() cryFrame = cryFrame or frame end
  Audio.isCryPlaying = function() return false end
  Anim.reset({ headless = false })
  local mon = { species = 25, isShiny = true }
  SwitchSeq.reset()
  SwitchSeq._st = { enemy = { side = "enemy", species = 25, hp = 10, mon = mon } }
  SwitchSeq._steps = {
    monAnim = true,
    { kind = "shiny_check", data = { side = "enemy" } },
    { kind = "cry", data = { side = "enemy" } },
  }
  SwitchSeq._i = 1
  local doneFrame
  for _ = 1, 600 do
    frame = frame + 1
    if SwitchSeq.update() then doneFrame = frame break end
    Anim.update(1 / 60)
  end
  Audio.playCry, Audio.isCryPlaying = oldCry, oldPlaying
  check(doneFrame ~= nil, "shiny switch-in sequence completes")
  eq(cryFrame, 1, "release cry plays when the shiny sparkle starts, not after it")
  check(doneFrame > 60, "sequence still waits for the sparkle before moving on")
end

local GameVersion = require("src.core.GameVersion")
require("src.core.game3.profile").reset()
GameVersion.set("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local src = cache and cache.read and cache:read("data/generated/gba/frontier/trainers.lua")
if type(src) ~= "string" then
  if T.failures > 0 then T.finish("game3_frontier_shiny_otid") end
  print("[skip] game3_frontier_shiny_otid_test: no Emerald frontier cache")
  os.exit(0)
end
require("src.import.gba.versions").select("emerald")
Pokemon.install(nil)
local C = require("src.core.game3.constants").of("emerald")
local D = require("src.core.game3.rse.frontier.trainers")
local Tower = require("src.core.game3.rse.frontier.tower")

local species = C:require("species", "SPECIES_PIKACHU")
local mismatches, shinies = 0, 0
for i = 0, 199 do
  local p = (i * 2654435761) % 4294967296
  local m = D.createMon(species, 30, 0, p, OT)
  local want = cartShiny(OT, p)
  if want then shinies = shinies + 1 end
  if ShinySeq.isShiny({ mon = m }) ~= want then mismatches = mismatches + 1 end
end
eq(mismatches, 0, "frontier mons built with the player's 32-bit otId match the cart shiny check")
local m = D.createMon(species, 30, 0, 7, OT)
eq(m.otId, lo, "frontier mon keeps the 16-bit trainer id in otId")
eq(m.otSecretId, hi, "frontier mon keeps the secret id in otSecretId")
eq(Tower.toBattleTowerMon(m).otId, OT, "battle tower record keeps the full 32-bit otId")

local Tents = require("src.core.game3.rse.frontier.tents")
local F = D.FACILITY
local tent = D.tentPack and D.tentPack(F.FACTORY)
if tent and tent.mons then
  local ids = {}
  for id in pairs(tent.mons) do ids[#ids + 1] = id if #ids == 3 then break end end
  local sess = { version = "emerald", trainerId = lo, secretId = hi, frontierTempParty = ids }
  local party = Tents.factoryTentParty(sess)
  for i, mon in ipairs(party) do
    eq(ShinySeq.isShiny({ mon = mon }), cartShiny(OT, mon.personality), "slateport tent opponent " .. i .. " shiny matches the cart")
  end
end
T.finish("game3_frontier_shiny_otid")
