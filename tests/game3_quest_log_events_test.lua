package.path='./?.lua;./?/init.lua;'..package.path
if not require("tests.game3_cache").mount() then
  package.loaded["src.core.game3.rom_text"] = (function()
    local function plain(key) return key end
    return {
      plain = plain, box = plain, ascii = plain, has = function() return true end,
      key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
      at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
      count = function() return 0 end, list = function() return {} end,
      lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
    }
  end)()
end
require("tests.fixture_data.game3_items").install()
local R=require('src.core.game3.quest_log_recorder')
local Runtime=require('src.core.game3.runtime')
local Schema=require('src.core.game3.save_schema_firered')
local Items=require('src.core.game3.item_use')
local Bag=require('src.core.game3.bag')
local Storage=require('src.core.game3.storage')
local s=Schema.newGame({rngSeed=1})
s.party={{species=1,nickname='BULB',hp=10,maxHp=20},{species=4,nickname='CHAR',hp=12,maxHp=20}}
Runtime.active=true;Runtime.session=s;Runtime._game={session=s}
R.capture=function()return {x=0,y=0,actors={}}end
R.tiles=function()return {}end
local function last()local scene=s.questLog.scenes[#s.questLog.scenes];return scene.events[#scene.events]end
Bag.add(s.bag,13,2)
assert(Items.useField(s,s.bag,13,1))
assert(last().key=='UsedItemOnMonAtThisLocation')
local first=last()
assert(not Items.useField(s,s.bag,13,1));assert(last()==first,'failed item use created event')
assert(Items.giveToMon(s,s.bag,13,1));assert(last().key=='GaveMonHeldItem2')
assert(Items.takeFromMon(s,s.bag,1));assert(last().key=='TookHeldItemFromMon')
assert(Storage.deposit(s,2,1,1));assert(last().key=='DepositedMonInPC')
assert(Storage.withdraw(s,1,1));assert(last().key=='WithdrewMonFromPC')
assert(Storage.moveMon(s,'party',1,'box',1,nil,1));assert(last().key=='DepositedMonInPC')
assert(Storage.moveMon(s,'box',1,'box',2,1,1));assert(last().key=='MovedMonWithinBox')
local N=require('src.core.game3.scripting.natives')
local Std=require('src.core.game3.scripting.stdscripts')
N.ALLOW['special:'..Std.SPECIAL.SetUsedPkmnCenterQuestLogEvent]()
assert(last().key=='MonsWereFullyRestoredAtCenter')
local old=s.questLog;s.map='FR_TRAINER_TOWER_1F';R.event(s,'ArrivedInLocation',{'TOWER'})
assert(s.questLog==old and last().key=='MonsWereFullyRestoredAtCenter','disabled map recorded event')
print('PASS Quest Log successful/failed items, held items, PC movement, nurse special, disabled locations')
