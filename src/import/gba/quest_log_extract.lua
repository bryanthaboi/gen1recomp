local Versions = require("src.import.gba.versions")
-- Quest Log text offsets relative to the header; BPRE revisions 0 and 1.
-- Only offsets are shipped. All strings are read from the imported ROM.
local TextIR=require('src.core.game3.scripting.text_ir')
local E={PATH='data/generated/gba/quest_log/pack.lua'}
local ENTRIES={
  {"PreviouslyOnYourQuest", 0x0},
  {"SwitchMon1WithMon2", 0x1A},
  {"SwappedHeldItemsOnMon", 0x3E},
  {"TookHeldItemFromMon", 0x78},
  {"UsedItemOnMonAtThisLocation", 0x92},
  {"UsedTheItem", 0xBB},
  {"UsedTheKeyItem", 0xCB},
  {"MonLearnedMoveFromTM", 0x100},
  {"MonReplacedMoveWithTM", 0x122},
  {"MonsWereFullyRestoredAtCenter", 0x15B},
  {"PlayerBattledChampionRival", 0x18C},
  {"PlayerSentOutMon1RivalSentOutMon2", 0x1BD},
  {"WonTheMatchAsAResult", 0x1F4},
  {"StoredItemInPC", 0x23C},
  {"WithdrewItemFromPC", 0x285},
  {"TradedMon1ForPersonsMon2", 0x2AA},
  {"SingleBattleWithPersonResultedInOutcome", 0x2CD},
  {"DoubleBattleWithPersonResultedInOutcome", 0x322},
  {"MultiBattleWithPeopleResultedInOutcome", 0x371},
  {"Win", 0x3AD},
  {"Loss", 0x3B1},
  {"MingledInUnionRoom", 0x3B6},
  {"DepartedPlaceInTownForNextDestination", 0x3E5},
  {"SwitchedMonsBetweenBoxes", 0x411},
  {"MovedMonToNewBox", 0x447},
  {"SwitchedMonsWithinBox", 0x484},
  {"MovedMonWithinBox", 0x4A5},
  {"SwitchedPartyMonForPCMon", 0x4B5},
  {"WithdrewMonFromPC", 0x4DD},
  {"DepositedMonInPC", 0x4FA},
  {"SwitchedMultipleMons", 0x519},
  {"ADifferentSpot", 0x53F},
  {"GaveMonHeldItemFromPC", 0x550},
  {"SwappedHeldItemFromPC", 0x58C},
  {"ChattedWithManyTrainers", 0x5DD},
  {"Handily", 0x5F9},
  {"Tenaciously", 0x601},
  {"Somehow", 0x60D},
  {"TradedMon1ForTrainersMon2", 0x615},
  {"BattledTrainerEndedInOutcome", 0x65B},
  {"BoughtItem", 0x688},
  {"BoughtItemsIncludingItem", 0x6BB},
  {"SoldNumOfItem", 0x703},
  {"SoldItemsIncludingItem", 0x741},
  {"JustOne", 0x77F},
  {"Num", 0x788},
  {"UsedSoftboiled", 0x78B},
  {"UsedMilkDrink", 0x7B7},
  {"MonLearnedMoveFromHM", 0x7E3},
  {"MonReplacedMoveWithHM", 0x810},
  {"DefeatedWildMon", 0x854},
  {"DefeatedWildMons", 0x87F},
  {"CaughtWildMon", 0x8AC},
  {"CaughtWildMons", 0x8D6},
  {"DefeatedWildMonAndCaughtWildMon", 0x921},
  {"DefeatedWildMonAndCaughtWildMons", 0x955},
  {"DefeatedWildMonsAndCaughtWildMon", 0x997},
  {"DefeatedWildMonsAndCaughtWildMons", 0x9D4},
  {"GaveMonHeldItem", 0xA1F},
  {"GaveMonHeldItem2", 0xA39},
  {"UsedCut", 0xA56},
  {"UsedFly", 0xA78},
  {"UsedSurf", 0xAA4},
  {"UsedStrength", 0xAD5},
  {"UsedFlash", 0xAFC},
  {"UsedRockSmash", 0xB3E},
  {"UsedWaterfall", 0xB67},
  {"UsedDive", 0xBA4},
  {"UsedDigInLocation", 0xBC8},
  {"UsedSweetScent", 0xBE7},
  {"UsedTeleportToLocation", 0xC14},
  {"LeftTownsLocationForNextDestination", 0xC49},
  {"PlayedGamesAtGameCorner", 0xC73},
  {"RestedAtHome", 0xCAA},
  {"LeftOaksLab", 0xCC9},
  {"GymWasFullOfToughTrainers", 0xCF3},
  {"DepartedGym", 0xD3A},
  {"HadGreatTimeInSafariZone", 0xD52},
  {"ManagedToGetOutOfLocation", 0xD87},
  {"TookOnGymLeadersMonWithMonAndWon", 0xDB7},
  {"TookOnEliteFoursMonWithMonAndWon", 0xDE9},
  {"TookOnTrainersMonWithMonAndWon", 0xE18},
  {"Coolly", 0xE43},
  {"Barely", 0xE4A},
  {"UsedEscapeRope", 0xE51},
  {"Draw", 0xE7C},
  {"DepartedTheLocationForNextDestination", 0xE81},
  {"DepartedFromLocationToNextDestination", 0xEB0},
  {"ObtainedItemInLocation", 0xEEA},
  {"ArrivedInLocation", 0xF0F},
  {"SavedGameAtLocation", 0xF1E},
  {"Home", 0xF4A},
  {"OakResearchLab", 0xF4F},
  {"Gym", 0xF60},
  {"PokemonLeagueGate", 0xF64},
  {"ViridianForest", 0xF78},
  {"PewterMuseumOfScience", 0xF88},
  {"MtMoon", 0xFA1},
  {"BikeShop", 0xFAA},
  {"BillsHouse", 0xFB4},
  {"DayCare", 0xFC1},
  {"UndergroundPath", 0xFCA},
  {"PokemonFanClub", 0xFDB},
  {"SSAnne", 0xFEC},
  {"DiglettsCave", 0xFF6},
  {"RockTunnel", 0x1005},
  {"PowerPlant", 0x1011},
  {"PokemonTower", 0x101D},
  {"VolunteerHouse", 0x102B},
  {"NameRatersHouse", 0x103B},
  {"CeladonDeptStore", 0x104E},
  {"CeladonMansion", 0x1062},
  {"RocketGameCorner", 0x1072},
  {"Restaurant", 0x1085},
  {"RocketHideout", 0x1090},
  {"SafariZone", 0x109F},
  {"WardensHome", 0x10AB},
  {"FightingDojo", 0x10B9},
  {"SilphCo", 0x10C7},
  {"SeafoamIslands", 0x10D1},
  {"PokemonMansion", 0x10E1},
  {"PokemonResearchLab", 0x10F1},
  {"VictoryRoad", 0x1106},
  {"PokemonLeague", 0x1113},
  {"CeruleanCave", 0x1122},
}
local function locate(rom)
  local sig={0xCA,0xE6,0xD9,0xEA,0xDD,0xE3,0xE9,0xE7,0xE0,0xED,0,0xE3,0xE2}
  for off=Versions.address(0x41A000),Versions.address(0x41A500) do
    local match=true
    for i,b in ipairs(sig) do if rom:get(off+i-1)~=b then match=false;break end end
    if match then return off end
  end
  error('Quest Log text not found in this ROM revision')
end
local function read(rom,off)
  local out,bytes={},{}
  local function flush()
    for _,s in ipairs(TextIR.decode(bytes)) do
      if s.t=='text' then out[#out+1]=s.s
      elseif s.t=='nl' or s.t=='para' or s.t=='scroll' then out[#out+1]='\n'
      elseif s.t=='player' then out[#out+1]='{PLAYER}'
      elseif s.t=='rival' then out[#out+1]='{RIVAL}'
      elseif s.t=='strvar' then out[#out+1]='{S'..s.n..'}' end
    end
    bytes={}
  end
  for _=1,1024 do
    local b=rom:get(off);off=off+1
    if b==255 then flush();return table.concat(out) end
    if b==0xF7 then
      flush();out[#out+1]='{D'..rom:get(off)..'}';off=off+1
    else bytes[#bytes+1]=b end
  end
  error('Unterminated Quest Log string')
end
function E.read(rom)
  local base=locate(rom);local pack={version=1,text={}}
  for _,entry in ipairs(ENTRIES) do pack.text[entry[1]]=read(rom,base+entry[2]) end
  return pack
end
function E.writeExtract(rom,cache)
  local pack=E.read(rom);local out={'return {version=1,text={'}
  for _,entry in ipairs(ENTRIES) do
    local key=entry[1];out[#out+1]=string.format('[%q]=%q,',key,pack.text[key])
  end
  out[#out+1]='}}\n';assert(cache:write(E.PATH,table.concat(out)))
  return pack
end
return E
